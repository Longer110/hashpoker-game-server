#pragma once
#include <mysql/mysql.h>
#include <string>

struct MySQLHandle {
    bool connected = false;
    MYSQL* conn = nullptr;
    // 保存参数以便重连
    std::string host_, user_, pass_, db_;
    int port_ = 0;
    int timeout_sec_ = 5;

    bool connect(const std::string& host, int port, const std::string& user,
                 const std::string& pass, const std::string& db, int timeout_sec);
    int  exec(const std::string& sql);
    void close();

private:
    bool open_with_saved_params();          // 
    bool reconnect();                       // 
    static bool is_lost_error(unsigned ec); //
};
