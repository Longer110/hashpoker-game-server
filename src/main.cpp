#include "jit/lua_thread.hpp"
#include <string>
#include "lnet/ws_server.hpp"
#include <iostream>
#include "jit/global_vm.h"
#include "modules/json.hpp"
#include <mysql/mysql.h>
#include <fstream>

using json = nlohmann::json;
int main(int argc, char *argv[])
{
    std::string ws_port = "";
    std::string serviceId = "";
    std::string cores = "2";
    if (argc > 1)
    {
        serviceId = argv[1]; // 传参覆盖
        if (argc > 2)
        {
            ws_port = argv[2];
        }
        if (argc > 3)
        {
            cores = argv[3];
        }
    }
    // std::cout << "启动服务id=[ " << serviceId << " ]\n"
    //           << std::endl;
    // std::ifstream f("config.json");
    // if (!f.is_open())
    // {
    //     std::cerr << "无法打开配置文件 config.json" << std::endl;
    //     return 1;
    // }
    // json cfg;
    // try
    // {
    //     f >> cfg;
    // }
    // catch (const std::exception &e)
    // {
    //     std::cerr << "JSON 解析失败: " << e.what() << std::endl;
    //     return 1;
    // }

    // // 解析 mysql 配置
    // if (!cfg.contains("mysql"))
    // {
    //     std::cerr << "配置缺少 mysql 节点" << std::endl;
    //     return 1;
    // }
    // int coreNum = cfg["net_cores"].get<int>();

    // auto mysql = cfg["mysql"];
    // std::string host = mysql.value("host", "127.0.0.1");
    // int port = mysql.value("port", 3306);
    // std::string user = mysql.value("user", "root");
    // std::string pass = mysql.value("pass", "");
    // std::string db = mysql.value("db", "test");
    // int timeout = mysql.value("timeout", 5);
    // auto script = cfg["script"];
    // if (mysql_library_init(0, nullptr, nullptr))
    // {
    //     std::cerr << "mysql_library_init failed\n"
    //               << std::endl;
    //     ;
    //     return 1;
    // }
    // MYSQL *conn = mysql_init(nullptr);
    // if (!conn)
    // {
    //     std::cerr << "mysql_init failed\n"
    //               << std::endl;
    //     mysql_library_end();
    //     return 1;
    // }
    // mysql_options(conn, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
    // mysql_options(conn, MYSQL_OPT_READ_TIMEOUT, &timeout);
    // mysql_options(conn, MYSQL_OPT_WRITE_TIMEOUT, &timeout);
    // if (!mysql_real_connect(conn, host.c_str(), user.c_str(), pass.c_str(),
    //                         (db.empty() ? nullptr : db.c_str()),
    //                         port, nullptr, 0))
    // {
    //     std::cerr << "mysql_real_connect failed: " << mysql_error(conn) << "\n";
    //     mysql_close(conn);
    //     mysql_library_end();
    //     return 1;
    // }
    // std::cout << "MySQL connected: " << user << "@" << host << ":" << port
    //           << (db.empty() ? "" : ("/" + db)) << "\n";

    // std::string sql = "select * from ServerInfo  where id = " + serviceId;

    // if (mysql_real_query(conn, sql.c_str(), (unsigned long)sql.size()) != 0)
    // {
    //     std::cerr << "Query failed: " << mysql_error(conn) << "\n";
    //     return 1;
    // }
    // MYSQL_RES *res = mysql_store_result(conn);
    // if (!res)
    // {
    //     std::cerr << "未查询到id=" << serviceId << "的服务\n";
    //     return 1;
    // }
    // my_ulonglong rows = mysql_num_rows(res);
    // if (rows == 0)
    // {
    //     std::cerr << "未查询到id=" << serviceId << "的服务\n";
    //     mysql_free_result(res);
    //     return 1;
    // }
    // json dbTable;
    // MYSQL_ROW row;
    // unsigned int nfields = mysql_num_fields(res);
    // MYSQL_FIELD *fields = mysql_fetch_fields(res);
    // while ((row = mysql_fetch_row(res)))
    // {
    //     unsigned long *lengths = mysql_fetch_lengths(res);
    //     for (unsigned int i = 0; i < nfields; i++)
    //     {
    //         if (row[i])
    //         {
    //             dbTable[fields[i].name] = std::string(row[i], lengths[i]);
    //         }
    //     }
    // }
    // // script.value("1","0")
    // // 拼接 参数
    // std::string stype_key = dbTable.value("SType", ""); // dbTable 里我们存的是 string
    // if (stype_key.empty())
    // {
    //     std::cerr << "记录缺少 SType 字段\n";
    //     mysql_free_result(res);
    //     mysql_close(conn);
    //     mysql_library_end();
    //     return 1;
    // }
    // if (!script.is_object())
    // {
    //     std::cerr << "config.json 中 script 必须是一个对象：{\"5\": \"Gateway\", ...}\n";
    //     mysql_free_result(res);
    //     mysql_close(conn);
    //     mysql_library_end();
    //     return 1;
    // }
    // std::string scName = script.value(stype_key, ""); // 用 SType 字符串做 key
    // if (scName.empty())
    // {
    //     std::cerr << "未配置 SType=" << stype_key << " 的脚本名\n";
    //     mysql_free_result(res);
    //     mysql_close(conn);
    //     mysql_library_end();
    //     return 1;
    // }
    // std::string cmd;
    // cmd.reserve(256);
    // cmd.append(scName).append("/ClientStart:");
    // cmd.append(serviceId).push_back(':');                                   // serviceId 已是 std::string
    // cmd.append(dbTable.at("Port").get<std::string>()).push_back(':');       // 端口
    // cmd.append(dbTable.at("SType").get<std::string>()).push_back(':');      // nFun
    // cmd.append(dbTable.at("SType").get<std::string>()).push_back(':');      // nStype
    // cmd.append(dbTable.at("Ip").get<std::string>()).push_back(':');         // IP
    // cmd.append(dbTable.at("ScoketType").get<std::string>()).push_back(':'); // 套接字类型
    // cmd.append(dbTable.at("Name").get<std::string>());
    // std::cout << "cmd=[" << cmd << "]\n"
    //           << std::endl;
    // mysql_free_result(res);
    // mysql_close(conn);
    try
    {
        // 先获取启动参数
        auto *eng = new LuaEngine();
        // 装载c模块
        luaopen_publicapi(eng->L());
        lua_pop(eng->L(), 1);
        luaopen_kmbridge(eng->L());
        lua_pop(eng->L(), 1);
        // 包路径
        eng->AppendPackageCPath({"./libs/runtime/lib/?.so"});
        eng->AppendPackagePath({
            "./libs/runtime/?.lua",
            "./libs/runtime/pb/?.lua",
            "./lua/config/?.lua",
        });
        eng->DoFile("./lua/config/CmdLine.lua");
        lua_getglobal(eng->L(), "GetCmdLine");       // 压入函数
        lua_pushstring(eng->L(), serviceId.c_str()); // 压入参数
        if (lua_pcall(eng->L(), 1, 1, 0) != LUA_OK)
        {
            std::cerr << "调用GetCmdLine失败: " << lua_tostring(eng->L(), -1) << std::endl;
            return 1;
        }

        const char *result = lua_tostring(eng->L(), -1); // 取返回值
        if (result == nullptr)
        {
            std::cerr << "调用GetCmdLine失败,返回为空 " << std::endl;
            return 1;
        }
        std::cout << "Lua返回: " << (result ? result : "nil") << std::endl;
        lua_pop(eng->L(), 1);
        // lua_close(eng->L());
        // delete eng;
        // 核心数
        GlobalVM::start(0, result, 300);
        if (ws_port != "")
        {
            const unsigned ncores = std::max(1u, std::thread::hardware_concurrency());
            std::vector<std::thread> pool;
            int coreNum = std::atoi(cores.c_str());
            std::cout << "配置网络核心数=>" << cores << ",本机核心数=>" << ncores << std::endl;
            if (coreNum > ncores)
            {
                coreNum = ncores;
            }
            std::cout << "开启网络线程数=>" << coreNum << ",ws 端口:" << ws_port << std::endl;
            pool.reserve(coreNum);
            // 这里可以启动多个lua虚拟机 暂时就一个
            asio::io_context ioc;
            auto work = asio::make_work_guard(ioc);
            int _port = std::stoi(ws_port);
            ws_server ws_server(ioc, _port);
            ws_server.run();
            // 网络线程数
            for (unsigned i = 0; i < coreNum; ++i)
            {
                pool.emplace_back([&ioc]
                                  {
                                      ioc.run(); // 每个线程一个
                                  });
            }
            // 阻塞
            for (auto &t : pool)
            {
                t.join();
            }
        }
        else
        {
            // 阻塞
            asio::io_context ioc;
            auto work = asio::make_work_guard(ioc);
            ioc.run();
        }
    }
    catch (const std::exception &e)
    {
        std::cerr << "Exception: " << e.what() << std::endl;
    }
    return 0;
}
