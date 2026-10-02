#pragma once
#include <cstdint>
#include <cstddef>
#include <string>
#include <stdexcept>
#include <vector>
#include <cstring>

// 协议说明：
// 8字节 ver(1)|check(1)|packet_size(2,LE)|main_cmd(2,LE)|sub_cmd(2,LE)
// 紧跟 body_len(2,LE) + body(body_len)
// packet_sz == 8 + 2 + body_len

// 常量偏移
static constexpr std::size_t OFF_VER = 0;
static constexpr std::size_t OFF_CHECK = 1;
static constexpr std::size_t OFF_PKT_SZ = 2;
static constexpr std::size_t OFF_MAIN_CMD = 4;
static constexpr std::size_t OFF_SUB_CMD = 6;
static constexpr std::size_t OFF_BODY_LEN = 8;
static constexpr std::size_t HEADER_BYTES = 8;    
constexpr std::size_t MIN_HEADER = 8;   // 仅 8 字节头（短心跳）
constexpr std::size_t MIN_FRAME10 = MIN_HEADER + 2;       

using Byte = uint8_t;
using ByteBuf = std::vector<Byte>;

// 小端读写
static inline uint16_t load_le16(const void *p)
{
    const auto *u = reinterpret_cast<const uint8_t *>(p);
    return static_cast<uint16_t>(u[0]) |
           static_cast<uint16_t>(u[1]) << 8;
}
static inline void store_le16(Byte *p, uint16_t v)
{
    p[0] = static_cast<Byte>(v & 0xFF);
    p[1] = static_cast<Byte>((v >> 8) & 0xFF);
}

// 协议包
struct Packet
{
    std::string handShake{};
    int64_t clientId{0};
    uint16_t main_cmd{};
    uint16_t sub_cmd{};
    ByteBuf body;           // 二进制 body
    uint32_t acceptIpV4{0}; // 0 表示非 OnAccept 事件
    int acceptPort{-1};     // <0 表示非 OnAccept 事件
    std::string clientIp{}; // 连接的客户端地址
};

// 序列化
inline ByteBuf build_packet(uint16_t main_cmd,
                            uint16_t sub_cmd,
                            const Byte *body, std::size_t body_len)
{
    // 最长65535
    const uint16_t body_len16 = static_cast<uint16_t>(body_len);
    const uint16_t total = static_cast<uint16_t>(HEADER_BYTES + 2 + body_len16);
    ByteBuf buf;
    buf.resize(total);
    buf[OFF_VER] = 0;
    buf[OFF_CHECK] = 0;
    store_le16(buf.data() + OFF_PKT_SZ, total);
    store_le16(buf.data() + OFF_MAIN_CMD, main_cmd);
    store_le16(buf.data() + OFF_SUB_CMD, sub_cmd);
    store_le16(buf.data() + OFF_BODY_LEN, body_len16);
    if (body_len16)
    {
        std::memcpy(buf.data() + OFF_BODY_LEN + 2, body, body_len16);
    }
    return buf;
}

// ByteBuf
inline ByteBuf build_packet(uint16_t main_cmd,
                            uint16_t sub_cmd,
                            const ByteBuf &body)
{
    return build_packet(main_cmd, sub_cmd,
                        body.empty() ? nullptr : body.data(),
                        body.size());
}

// 从 std::string
inline ByteBuf build_packet(uint16_t main_cmd,
                            uint16_t sub_cmd,
                            const std::string &body)
{
    return build_packet(main_cmd, sub_cmd,
                        reinterpret_cast<const Byte *>(body.data()),
                        body.size());
}

// 反序列化
inline Packet parse_packet(const Byte *frame, std::size_t n)
{
    if (n < MIN_FRAME10)
    {
        throw std::runtime_error("packet too short");
    }
    const uint16_t pkt_sz = load_le16(frame + OFF_PKT_SZ);
    const uint16_t main_cmd = load_le16(frame + OFF_MAIN_CMD);
    const uint16_t sub_cmd = load_le16(frame + OFF_SUB_CMD);
    const uint16_t body_len = load_le16(frame + OFF_BODY_LEN);
    if (pkt_sz != n)
    {
        throw std::runtime_error("size mismatch");
    }
    if (HEADER_BYTES + 2 + body_len != pkt_sz)
    {
        throw std::runtime_error("body length mismatch");
    }
    Packet out;
    out.main_cmd = main_cmd;
    out.sub_cmd = sub_cmd;
    out.body.assign(frame, frame + n);
    return out;
}

//  ByteBuf
inline Packet parse_packet(const ByteBuf &frame)
{
    return parse_packet(frame.data(), frame.size());
}
