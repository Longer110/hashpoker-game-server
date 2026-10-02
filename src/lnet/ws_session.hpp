#pragma once
#include "jit/global_vm.h"
#include "protocol.hpp"
#include <algorithm>
#include <boost/asio.hpp>
#include <boost/asio/buffer.hpp>
#include <boost/beast.hpp>
#include <boost/beast/http.hpp>
#include <boost/system/error_code.hpp>
#include <boost/uuid/uuid_generators.hpp>
#include <deque>
#include <memory>
#include <string>
#include <vector>

namespace asio = boost::asio;
namespace beast = boost::beast;
namespace http = beast::http;
namespace ws = beast::websocket;
using boost::system::error_code;
using tcp = asio::ip::tcp;

constexpr std::size_t MAX_FRAME = (1u << 16) - 1;

class ws_session : public std::enable_shared_from_this<ws_session>
{
private:
  std::string client_ip_;

public:
  inline static constexpr std::array<uint8_t, 8> HEARTBEAT_PACKET = {
      0x01, 0x00, 0x08, 0x00, // ver=1, check=0, packet_size=8
      0x00, 0x00,             // main_cmd=0
      0x00, 0x00              // sub_cmd=0
  };
  inline static const std::string HEARTBEAT{
      reinterpret_cast<const char *>(HEARTBEAT_PACKET.data()),
      HEARTBEAT_PACKET.size()};
  static constexpr size_t MaxQueue = 1024;
  inline static std::atomic<int64_t> s_next_id{1};
  int64_t clientId_{0};
  explicit ws_session(tcp::socket s) : ws_(std::move(s))
  {
    inbuf_.reserve(64 * 1024);
  };
  std::string get_hdr(beast::string_view name) const
  {
    if (!req_)
      return {};
    auto it = req_->find(name); // 这里匹配到 string_view 的重载
    return it != req_->end() ? std::string(it->value()) : std::string();
  }
  void start()
  {
    // 生成 UUID 作为 clientId
    this->clientId_ = s_next_id.fetch_add(1, std::memory_order_relaxed);
    ws_.set_option(
        ws::stream_base::timeout::suggested(beast::role_type::server));
    ws_.read_message_max(64 * 1024 * 1024);
    ws_.binary(true);
    {
      boost::system::error_code ec;
      beast::get_lowest_layer(ws_).set_option(tcp::no_delay(true), ec);
      beast::get_lowest_layer(ws_).set_option(
          asio::socket_base::keep_alive(true), ec);
    }
    uint32_t ip_v4 = 0;
    int port = -1;
    {
      boost::system::error_code ig;
      auto ep = beast::get_lowest_layer(ws_).remote_endpoint(ig);
      if (!ig)
      {
        auto addr = ep.address();
        if (addr.is_v4())
        {
          ip_v4 = addr.to_v4().to_uint(); // 数值 IPv4（DWORD）
        }
        port = static_cast<int>(ep.port());
      }
    }

    // 先读TTP请求,握
    req_ = std::make_unique<http::request<http::string_body>>();
    auto self = shared_from_this();
    http::async_read(
        beast::get_lowest_layer(ws_), read_buf_, *req_,
        [this, self, ip_v4, port](error_code ec, std::size_t /*bytes*/)
        {
          if (ec)
            return close();
          if (!ws::is_upgrade(*req_))
            return close();
          // 2) 解析对端地址
          std::string peer_ip = "0.0.0.0";
          error_code ig;
          auto ep = beast::get_lowest_layer(ws_).remote_endpoint(ig);
          if (!ig)
            peer_ip = ep.address().to_string();
          auto get_hdr_ci = [&](beast::string_view name) -> std::string
          {
            if (!req_)
              return {};
            for (auto const &f : *req_)
            {
              if (beast::iequals(f.name_string(), name))
                return std::string(f.value());
            }
            return {};
          };

          std::string cfcip = get_hdr_ci("cf-connecting-ip");
          std::string xff = get_hdr_ci("x-forwarded-for");
          std::string xreal = get_hdr_ci("x-real-ip");
          std::string host = get_hdr_ci("host");
          std::string ua = get_hdr_ci("user-agent");
          auto first_token = [](std::string s) -> std::string
          {
            auto pos = s.find(',');
            if (pos != std::string::npos)
              s.resize(pos);
            return s;
          };
          auto trim = [](std::string &s)
          {
            auto issp = [](unsigned char c)
            { return std::isspace(c); };
            while (!s.empty() && issp((unsigned char)s.front()))
              s.erase(s.begin());
            while (!s.empty() && issp((unsigned char)s.back()))
              s.pop_back();
          };

          std::string real_ip;
          if (!cfcip.empty())
            real_ip = cfcip; // 真实用户 IP
          else if (!xff.empty())
            real_ip = first_token(xff); // 代理链第一个
          else if (!xreal.empty())
            real_ip = xreal; // 备选
          else
            real_ip = peer_ip; // 没有任何头就用 TCP 对端
          trim(real_ip);
          std::string hs;
          hs.reserve(256);
          hs += "real-ip: " + real_ip + "\r\n";
          if (!host.empty())
            hs += "Host: " + host + "\r\n";
          if (!ua.empty())
            hs += "User-Agent: " + ua + "\r\n";
          if (!xff.empty())
            hs += "X-Forwarded-For: " + xff + "\r\n";
          ws_.async_accept(*req_,
                           [this, self, ip_v4, port,
                            hs = std::move(hs),
                            real_ip = std::move(real_ip)](error_code ec2) mutable
                           {
                             if (ec2)
                               return close();
                             client_ip_ = std::move(real_ip);
                             GlobalVM::register_client(clientId_, self);
                             Packet acc;
                             acc.clientId = clientId_;
                             acc.acceptIpV4 = ip_v4; // 0 表示未知/非 OnAccept
                             acc.acceptPort = port;  // <0 表示未知/非 OnAccept
                             acc.clientIp = client_ip_;
                             GlobalVM::push_all(acc); // 走与握手相同的投递途径
                             Packet pkt;
                             pkt.handShake = std::move(hs);
                             pkt.clientIp = client_ip_;
                             pkt.clientId = clientId_;
                             GlobalVM::push_all(pkt);
                             do_read();
                           });
        });
  }

  void send(std::string data)
  {
    auto self = shared_from_this();
    // 同一个executor
    asio::dispatch(ws_.get_executor(),
                   [this, self, data = std::move(data)]() mutable
                   {
                     if (outq_.size() > MaxQueue)
                     {
                       close_impl();
                       return;
                     }
                     bool writing = !outq_.empty();
                     outq_.push_back(std::move(data));
                     if (!writing)
                       do_write();
                   });
  }

private:
  std::atomic<bool> closed_{false};
  void do_read()
  {
    auto self = shared_from_this();
    ws_.async_read(
        read_buf_, [this, self](error_code ec, std::size_t /*bytes*/)
        {
          if (ec)
            return close();

          auto data = read_buf_.data();
          std::size_t n = asio::buffer_size(data);
          inbuf_.insert(inbuf_.end(), asio::buffers_begin(data),
                        asio::buffers_end(data));
          read_buf_.consume(n);

          // 二进制协议拆包
          for (;;) {
            if (inbuf_.size() < MIN_HEADER)
              break;
            const uint16_t pkt_sz = load_le16(inbuf_.data() + OFF_PKT_SZ);
            // 心跳包
            if (pkt_sz == MIN_HEADER) {
              uint16_t main_cmd = load_le16(inbuf_.data() + OFF_MAIN_CMD);
              uint16_t sub_cmd = load_le16(inbuf_.data() + OFF_SUB_CMD);
              if (main_cmd == 0 && sub_cmd == 0) {
                send_heartbeat();
              } else {
                close();
                return;
              }
              inbuf_.erase(inbuf_.begin(), inbuf_.begin() + pkt_sz);
              continue;
            }
            if (pkt_sz < MIN_FRAME10) {
              close();
              return;
            }
            if (pkt_sz > MAX_FRAME || pkt_sz > inbuf_.size()) {
              if (pkt_sz > inbuf_.size()) {
                break;
              }
              close();
              return;
            }
            ByteBuf frame(inbuf_.begin(), inbuf_.begin() + pkt_sz);
            inbuf_.erase(inbuf_.begin(), inbuf_.begin() + pkt_sz);
            try {
              dispatch(std::move(frame));
            } catch (...) {
              close();
              return;
            }
          }
          do_read(); });
  }

  void dispatch(ByteBuf frame)
  {
    mark_alive();
    Packet pkt = parse_packet(frame);
    pkt.clientId = clientId_;
    pkt.clientIp = client_ip_;
    GlobalVM::push_all(pkt);
  }

  void do_write()
  {
    auto self = shared_from_this();
    ws_.async_write(asio::buffer(outq_.front()),
                    [this, self](error_code ec, std::size_t)
                    {
                      if (ec)
                        return close();
                      outq_.pop_front();
                      if (!outq_.empty())
                        do_write();
                    });
  }

  void close()
  {
    auto self = shared_from_this();
    asio::dispatch(ws_.get_executor(), [this, self]
                   { close_impl(); });
  }
  void send_heartbeat()
  {
    mark_alive();
    send(HEARTBEAT);
  }
  void close_impl()
  {
    if (closed_.exchange(true))
      return;
    error_code ig;
    if (ws_.is_open())
      ws_.close(ws::close_code::normal, ig);
    GlobalVM::unregister_client(this->clientId_);
    Packet acc;
    acc.clientId = clientId_;
    acc.handShake = "offline"; // 0 表示未知/非 OnAccept
    client_ip_.clear();
    GlobalVM::push_all(acc);
  }

private:
  std::atomic<int64_t> last_hb_ms{0};
  ws::stream<tcp::socket> ws_;
  beast::flat_buffer read_buf_;
  std::vector<uint8_t> inbuf_;
  std::deque<std::string> outq_;

  // 必须是成员，保证异步期间存活
  std::unique_ptr<http::request<http::string_body>> req_;
  inline void mark_alive()
  {
    last_hb_ms.store(now_ms_steady(), std::memory_order_relaxed);
  }
  inline static int64_t now_ms_steady()
  {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch())
        .count();
  }
};