// MySQLHandle.cpp
#include "mysql_lua.h"
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <limits>
#include "km_log.h"
#include <mysql/errmsg.h>
namespace
{

    // 兼容不同 MySQL 版本的 MYSQL_OPT_RECONNECT 设置
    inline void set_opt_reconnect(MYSQL *c, bool enable)
    {
#if defined(MARIADB_BASE_VERSION) || (MYSQL_VERSION_ID < 80000)
        my_bool v = enable ? 1 : 0;
        mysql_options(c, MYSQL_OPT_RECONNECT, &v);
#else
        (void)c;
        (void)enable;
#endif
    }

    inline int ull_to_int(unsigned long long x)
    {
        if (x > static_cast<unsigned long long>(std::numeric_limits<int>::max()))
            return std::numeric_limits<int>::max();
        return static_cast<int>(x);
    }
    inline void set_timeouts(MYSQL *c, unsigned to)
    {
        mysql_options(c, MYSQL_OPT_CONNECT_TIMEOUT, &to);
        mysql_options(c, MYSQL_OPT_READ_TIMEOUT, &to);
        mysql_options(c, MYSQL_OPT_WRITE_TIMEOUT, &to);
    }
}

bool MySQLHandle::connect(const std::string &host, int port,
                          const std::string &user, const std::string &pass,
                          const std::string &db, int timeout_sec)
{
    close();
    host_ = host;
    port_ = port;
    user_ = user;
    pass_ = pass;
    db_ = db;
    timeout_sec_ = timeout_sec > 0 ? timeout_sec : 5;
    return open_with_saved_params();
}

bool MySQLHandle::open_with_saved_params()
{
    conn = mysql_init(nullptr);
    if (!conn)
        return (connected = false);

    set_timeouts(conn, static_cast<unsigned>(timeout_sec_));
    set_opt_reconnect(conn, true); // MariaDB / <8.0 有效；8.0+ no-op
    mysql_options(conn, MYSQL_SET_CHARSET_NAME, "utf8mb4");

    MYSQL *ok = mysql_real_connect(conn, host_.c_str(), user_.c_str(), pass_.c_str(),
                                   db_.empty() ? nullptr : db_.c_str(),
                                   static_cast<unsigned>(port_), nullptr, 0);
    if (!ok)
    {
        KM_LOG_ERROR("MySQL connect failed: {}", mysql_error(conn));
        mysql_close(conn);
        conn = nullptr;
        return (connected = false);
    }
    mysql_set_server_option(conn, MYSQL_OPTION_MULTI_STATEMENTS_ON);
    return (connected = true);
}

bool MySQLHandle::reconnect()
{
    KM_LOG_WARN("MySQL reconnecting to {}:{} db={}", host_, port_, db_);
    close();
    return open_with_saved_params();
}

bool MySQLHandle::is_lost_error(unsigned ec)
{
    return ec == CR_SERVER_GONE_ERROR || ec == CR_SERVER_LOST || ec == CR_SERVER_HANDSHAKE_ERR;
}

int MySQLHandle::exec(const std::string &sql) {
    if (!connected || !conn) {
        if (!reconnect()) return -1;
    }

    auto run = [&](const std::string& q)->int {
        if (mysql_query(conn, q.c_str()) != 0) return -1;

        MYSQL_RES* res = mysql_store_result(conn);
        if (res) {
            unsigned long long rows = mysql_num_rows(res);
            mysql_free_result(res);
            return rows > static_cast<unsigned long long>(std::numeric_limits<int>::max())
                   ? std::numeric_limits<int>::max()
                   : static_cast<int>(rows);
        }
        if (mysql_field_count(conn) == 0) {
            unsigned long long aff = mysql_affected_rows(conn);
            return aff > static_cast<unsigned long long>(std::numeric_limits<int>::max())
                   ? std::numeric_limits<int>::max()
                   : static_cast<int>(aff);
        }
        return -1;
    };

    int rc = run(sql);
    if (rc >= 0) return rc;

    unsigned ec = mysql_errno(conn);
    if (is_lost_error(ec)) {
        KM_LOG_WARN("MySQL lost connection ({}:{}) -> retry once", ec, mysql_error(conn));
        if (reconnect()) {
            rc = run(sql);
            if (rc >= 0) return rc;
        }
    }

    KM_LOG_ERROR("MySQL query failed ({}): {}", ec, mysql_error(conn));
    return -1;
}


void MySQLHandle::close()
{
    if (conn)
    {
        mysql_close(conn);
        conn = nullptr;
    }
    connected = false;
}


