#pragma once

#include <unordered_map>
#include <mutex>
#include <memory>
#include <string>
#include "lnet/protocol.hpp"


bool gv_send_to(int64_t clientId, const void* data, size_t len);
// 前向声明，避免循环包含
class ws_session;
namespace LuaVM { class ThreadHandle; } 
class GlobalVM
{
public:
    static bool start(long idx = 1, const std::string &args = "", long port = 301);
    static void  stop(long idx);
    static void  stop_all();

    static int   push_all(const Packet &p);
    static bool  push_to(long idx, const Packet &p);

    static bool  running(long idx);
    static int   count();

    // 供网络层注册/注销会话
    static void register_client(int64_t clientId, std::shared_ptr<ws_session> sess);
    static void unregister_client(int64_t clientId);

    // 发送到指定 clientId
    static bool send_to(int64_t clientId, const void* data, size_t len);

private:
    static inline std::unordered_map<long, std::shared_ptr<LuaVM::ThreadHandle>> threads_{};
    // 注意：互斥量和路由表
    static inline std::mutex clients_mu_;
    static inline std::unordered_map<int64_t, std::weak_ptr<ws_session>> clients_;
};