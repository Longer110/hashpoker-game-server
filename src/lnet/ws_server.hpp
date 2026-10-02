#pragma once
#include <memory>
#include <boost/asio.hpp>
#include "ws_session.hpp"

namespace asio = boost::asio;
using tcp = asio::ip::tcp;

class ws_server
{
public:
    ws_server(asio::io_context &ioc, unsigned short port)
        : ioc_(ioc),
          acceptor_(ioc, tcp::endpoint(tcp::v4(), port))
    {
        // 允许重启绑定
        acceptor_.set_option(tcp::acceptor::reuse_address(true));
    }

    void run() { do_accept(); }

private:
    void do_accept()
    {
        // 在多线程ioc下回调串行
        acceptor_.async_accept(asio::make_strand(ioc_),
                               [this](const boost::system::error_code &ec, tcp::socket s)
                               {
                                   if (!ec)
                                   {
                                       std::make_shared<ws_session>(std::move(s))->start();
                                   }
                                   do_accept();
                               });
    }

private:
    asio::io_context &ioc_;
    tcp::acceptor acceptor_;
};