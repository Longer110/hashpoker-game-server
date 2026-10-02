// LuaEngine_runOnceAsync.hpp
#pragma once
#include <thread>
#include <pthread.h>
#include <string>
#include <memory>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <atomic>
#include <chrono>
#include "lua_engine.h"
#include "lnet/protocol.hpp"
#include "modules/kmbridge_stub.hpp"
#include "global_vm.h"

int luaopen_publicapi(lua_State *L);

int luaopen_kmbridge(lua_State *L);

int PollTimers(lua_State *L, int max_calls);

int PollRedis(lua_State *L, int max_calls);

void dispatch_to_lua(lua_State *L, const Packet &packet);

namespace LuaVM {
    // 线程安全队列
    class Mailbox {
    public:
        void push(Packet msg) {
            {
                std::lock_guard<std::mutex> lk(mu_);
                netQue.push(std::move(msg));
            }
            cv_.notify_one();
        }

        bool pop_wait_for(Packet &out, std::chrono::milliseconds wait) {
            std::unique_lock<std::mutex> lk(mu_);
            if (netQue.empty()) {
                if (!cv_.wait_for(lk, wait, [&] { return !netQue.empty() || closed_; }))
                    return false;
                if (closed_ && netQue.empty())
                    return false;
            }
            out = std::move(netQue.front());
            netQue.pop();
            return true;
        }

        void close() {
            {
                std::lock_guard<std::mutex> lk(mu_);
                closed_ = true;
            }
            cv_.notify_all();
        }

    private:
        std::queue<Packet> netQue;
        std::mutex mu_;
        std::condition_variable cv_;
        bool closed_ = false;
    };

    // 调用lua函数
    inline void callLuaSafe(LuaEngine &eng, const char *fn, const char *arg) {
        eng.Call(fn, 0, arg);
    }

    class ThreadHandle {
    public:
        ThreadHandle() = default;

        ThreadHandle(const ThreadHandle &) = delete;

        ThreadHandle &operator=(const ThreadHandle &) = delete;

        ThreadHandle(ThreadHandle &&) noexcept = default;

        ThreadHandle &operator=(ThreadHandle &&) noexcept = default;

        ~ThreadHandle() {
            if (auto_join_) {
                stop();
                join();
            }
        }

        void push(Packet s) const {
            if (inbox_)
                inbox_->push(std::move(s));
        }

        void stop() {
            if (running_)
                running_->store(false, std::memory_order_relaxed);
            if (inbox_)
                inbox_->close();
        }

        void join() {
            if (th_.joinable())
                th_.join();
        }

        void set_auto_join(bool on) { auto_join_ = on; }

        // 启动线程
        static ThreadHandle start_worker(std::string args, long threadIdx = 1, long port = 301) {
            ThreadHandle h;
            h.inbox_ = std::make_shared<Mailbox>();
            h.running_ = std::make_shared<std::atomic<bool> >(true);
            // 拷贝 shared_ptr
            auto inbox = h.inbox_;
            auto running = h.running_;
            h.th_ = std::thread([args = std::move(args), threadIdx, port, inbox, running] {
#if defined(__linux__)
                pthread_setname_np(pthread_self(), "lua_vm_once");
#endif
                try {
                    LuaEngine eng;
                    // 装载c模块
                    luaopen_publicapi(eng.L());
                    lua_pop(eng.L(), 1);
                    luaopen_kmbridge(eng.L());
                    lua_pop(eng.L(), 1);
                    // 设置全局
                    static const char *G_TI_NAME = "TI_67C4F52E263F422283C040A5ABE96B31";
                    static const char *G_PO_NAME = "PO_F05ADA09A24341BE9E76845C32DAA596";
                    eng.SetGlobal(G_TI_NAME, static_cast<int64_t>(threadIdx));
                    eng.SetGlobal(G_PO_NAME, static_cast<int64_t>(port));
                    // 包路径
                    eng.AppendPackageCPath({"./libs/runtime/lib/?.so"});
                    eng.AppendPackagePath({
                        "./libs/runtime/?.lua",
                        "./libs/runtime/pb/?.lua",
                        "./lua/config/?.lua",
                    });
                    // 入口脚本
                    if (!eng.DoFile("./lua/main.lua")) {
                        return; // 加载失败
                    }
                    // 启动回调
                    callLuaSafe(eng, "OnStartService", args.c_str());
                    // 主循环
                    while (running->load(std::memory_order_relaxed)) {
                        bool had_any = false;
                        int t = PollTimers(eng.L(), 256);
                        int r = PollRedis(eng.L(), 256);
                        int k = PollKafka(eng.L(), 256);
                        had_any |= (t > 0) || (r > 0) || (k > 0);
                        Packet msg;
                        if (had_any) {
                            int drained = 0;
                            while (drained < 1024 && inbox->pop_wait_for(msg, std::chrono::milliseconds(0))) {
                                dispatch_to_lua(eng.L(), msg);
                                ++drained;
                            }
                            if (drained == 0) {
                                std::this_thread::sleep_for(std::chrono::microseconds(100));
                            }
                            continue; //立刻下一轮不睡
                        }
                        if (inbox->pop_wait_for(msg, std::chrono::milliseconds(10))) {
                            dispatch_to_lua(eng.L(), msg);
                        }else {
                            std::this_thread::sleep_for(std::chrono::microseconds(100));
                        }
                    }
                } catch (...) {
                    // TODO:异常处理
                }
            });
            return h;
        }

    private:
        std::thread th_;
        std::shared_ptr<Mailbox> inbox_;
        std::shared_ptr<std::atomic<bool> > running_;
        bool auto_join_ = true;
    };
} // namespace LuaVM
