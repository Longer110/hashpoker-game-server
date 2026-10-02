#pragma once
#include "jit/global_vm.h"
#include <luajit-2.1/lua.hpp>
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>
#include <memory>
#include <random>
#include <iostream>
#include "km_log.h"
#include <boost/asio.hpp>
#include <thread>
#include <atomic>
#include <deque>
#include <mutex>
#include "mysql_lua.h"
#include <algorithm>
#include "mysql_cursor.h"
#include <lnet/protocol.hpp>
#include <hiredis/hiredis.h>
#include <hiredis/hiredis_ssl.h> // 如果需要 TLS
#include <cerrno>
#include <sstream>
#include <cassert>
#include "kafka.hpp"
// extern "C" int luaopen_kafka(lua_State* L);
bool gv_send_to(int64_t clientId, const void *data, size_t len);
// 与 Lua 脚本一致的全局名
inline static const char *G_KM_NAME = "km_FD55292F51334A64AC61470D796F8D43";
inline static const char *G_RP_NAME = "RP_437298BD4BB04659AA7F7918B6065421";
inline static const char *G_SP_NAME = "SP_AA72D5F10D7743BDAF54EF1F9E6E3B87";
inline static const char *G_Queue_NAME = "Queue_E1989A69093D4002BC9CE34F025361B6";
inline static const char *G_MyRedis_NAME = "MyRedis_198BBDC36C2C4C33AA80C462D2E95F31";
inline static const char *G_LOG_NAME = "LOG_003501BF4D4F408A8D1EFED467DAEF9B";
inline static const char *G_NET_NAME = "Net_042AC81D472F49B8984E27B471123EB5";
inline static const char *G_Int64_NAME = "Int64_22B4A82EC1264817AF8A995DF22CA66F";
inline static const char *G_mysql_NAME = "mysql_427F56073F604A338B2FE790AB2A825A";
inline static const char *MT_Q = "queue.meta";
inline static const char *MT_MR = "myredis.meta";
inline static const char *MT_KM = "km.meta";
inline static const char *KM_REGKEY = "kmbridge.single_instance";
inline static const char *MT_MYSQL_ENV = "mysql.env.meta";
inline static const char *MT_MYSQL_CONN = "mysql.conn.meta";
inline static const char *MT_RP = "rp.meta";
inline static const char *MT_SP = "sp.meta";

// PendingRedisMsg
struct PendingRedisMsg
{
    lua_State *L = nullptr;
    std::string cb;
    std::string channel;
    std::string payload;
};

class RedisPendingQueue
{
public:
    void push(PendingRedisMsg m)
    {
        std::lock_guard<std::mutex> lk(mu_);
        q_.push_back(std::move(m));
    }
    bool pop_for(lua_State *L, PendingRedisMsg &out)
    {
        std::lock_guard<std::mutex> lk(mu_);
        for (auto it = q_.begin(); it != q_.end(); ++it)
        {
            if (it->L == L)
            {
                out = std::move(*it);
                q_.erase(it);
                return true;
            }
        }
        return false;
    }
    void purge_for(lua_State *L)
    {
        std::lock_guard<std::mutex> lk(mu_);
        q_.erase(std::remove_if(q_.begin(), q_.end(),
                                [&](const PendingRedisMsg &m)
                                { return m.L == L; }),
                 q_.end());
    }

private:
    std::mutex mu_;
    std::deque<PendingRedisMsg> q_;
};

inline RedisPendingQueue g_redis_pending;

// ======================= Redis
namespace redis_u
{
    struct Options
    {
        std::string host;
        int port = 6379;
        std::string pass;
        int db = 0;
        bool use_tls = false;
        int timeout_ms = 1000; // socket R/W 超时
        bool keepalive = true;
    };

    struct Reply
    {
        redisReply *r = nullptr;
        Reply() = default;
        explicit Reply(redisReply *p) : r(p) {}
        ~Reply()
        {
            if (r)
                freeReplyObject(r);
        }
        redisReply *get() const { return r; }
        redisReply *release()
        {
            auto *p = r;
            r = nullptr;
            return p;
        }
        operator bool() const { return r != nullptr; }
    };

    struct Conn
    {
        Options opt;
        redisContext *ctx = nullptr;
        redisSSLContext *sslctx = nullptr;
        void close()
        {
            if (ctx)
            {
                redisFree(ctx);
                ctx = nullptr;
            }
            if (sslctx)
            {
                redisFreeSSLContext(sslctx);
                sslctx = nullptr;
            }
        }
        bool ok() const { return ctx && ctx->err == 0; }
        bool open()
        {
            close();
            timeval tv{opt.timeout_ms / 1000, (opt.timeout_ms % 1000) * 1000};
            ctx = redisConnectWithTimeout(opt.host.c_str(), opt.port, tv);
            if (!ctx || ctx->err)
            {
                KM_LOG_INFO("[RedisQueue] !ctx || ctx->err");
                close();
                return false;
            }

            opt.use_tls = false;
            KM_LOG_INFO("[RedisQueue] opt.use_tls = {}", opt.use_tls);
            if (opt.use_tls)
            {
                redisInitOpenSSL();
                redisSSLContextError sslerr = REDIS_SSL_CTX_NONE;
                sslctx = redisCreateSSLContext(nullptr, nullptr, nullptr, nullptr, nullptr, &sslerr);
                if (!sslctx)
                {
                    KM_LOG_INFO("[RedisQueue] error :!sslctx");
                    close();
                    return false;
                }
                if (redisInitiateSSLWithContext(ctx, sslctx) != REDIS_OK)
                {
                    KM_LOG_INFO("[RedisQueue] redisInitiateSSLWithContext(ctx, sslctx) != REDIS_OK");
                    close();
                    return false;
                }
            }
            // 超时&keepalive
            timeval rtv{opt.timeout_ms / 1000, (opt.timeout_ms % 1000) * 1000};
            redisSetTimeout(ctx, rtv);
#if defined(HIREDIS_MAJOR) && (HIREDIS_MAJOR > 1 || (HIREDIS_MAJOR == 1 && HIREDIS_MINOR >= 2))
            if (opt.keepalive)
                redisEnableKeepAlive(ctx);
#endif
            if (!opt.pass.empty())
            {
                Reply r{(redisReply *)redisCommand(ctx, "AUTH %s", opt.pass.c_str())};
                if (!r || r.get()->type == REDIS_REPLY_ERROR)
                {
                    KM_LOG_INFO("!r || r.get()->type == REDIS_REPLY_ERROR");
                    close();
                    return false;
                }
            }
            if (opt.db != 0)
            {
                Reply r{(redisReply *)redisCommand(ctx, "SELECT %d", opt.db)};
                if (!r || r.get()->type == REDIS_REPLY_ERROR)
                {
                    KM_LOG_INFO("!r || r.get()->type == REDIS_REPLY_ERROR");
                    close();
                    return false;
                }
            }
            return ok();
        }

        bool reconnect() { return open(); }

        // 非阻塞式, 带超时读：0=OK(拿到一条), 1=超时/无消息, -1=错误(需要重连)
        int getReply(redisReply **out)
        {
            if (out)
                *out = nullptr;
            if (!ok())
                return -1;
            errno = 0; // 先清 errno 便于判断
            redisReply *tmp = nullptr;
            int rc = redisGetReply(ctx, (void **)&tmp);
            if (rc == REDIS_OK)
            {
                if (out)
                    *out = tmp;
                else if (tmp)
                    freeReplyObject(tmp);
                return 0;
            }
            // 读超时/无数据
            const int e = errno;
            if (e == EAGAIN
#ifdef EWOULDBLOCK
                || e == EWOULDBLOCK
#endif
#ifdef ETIMEDOUT
                || e == ETIMEDOUT
#endif
            )
            {
                if (tmp)
                {
                    freeReplyObject(tmp);
                    tmp = nullptr;
                }
                // 清除 hiredis 上次 I/O 错误状态
                if (ctx)
                {
                    ctx->err = 0;
                }
                return 1; // 超时/无消息
            }
            // 其它情况视为真正错误
            if (tmp)
            {
                freeReplyObject(tmp);
                tmp = nullptr;
            }
            return -1;
        }
        Reply cmdf(const char *fmt, ...)
        {
            if (!ok())
                reconnect();
            va_list ap;
            va_start(ap, fmt);
            redisReply *raw = (redisReply *)redisvCommand(ctx, fmt, ap);
            va_end(ap);
            if (!raw)
            {
                if (reconnect())
                {
                    va_start(ap, fmt);
                    raw = (redisReply *)redisvCommand(ctx, fmt, ap);
                    va_end(ap);
                }
            }
            return Reply{raw};
        }

        // 订阅用
        Reply cmdArgv(const std::vector<const char *> &argv, const std::vector<size_t> &lens)
        {
            if (!ok())
                reconnect();
            const char **argvp = const_cast<const char **>(argv.data());
            redisReply *raw = (redisReply *)redisCommandArgv(ctx, (int)argv.size(), argvp, lens.data());
            if (!raw)
            {
                if (reconnect())
                {
                    const char **argvp2 = const_cast<const char **>(argv.data());
                    raw = (redisReply *)redisCommandArgv(ctx, (int)argv.size(), argvp2, lens.data());
                }
            }
            return Reply{raw};
        }

        // 二进制安全 PUBLISH
        bool publish(const std::string &ch, const void *p, size_t n)
        {
            Reply r = cmdf("PUBLISH %s %b", ch.c_str(), p, n);
            if (!r || r.get()->type == REDIS_REPLY_ERROR)
                return false;
            return ctx && ctx->err == 0;
        }
    };
}

// ----------解析cb路径"Func", "A.B.C", "Mod.Func", "Mod:Method"
inline static bool push_lua_callable(lua_State *L, const std::string &cb, bool &pushed_self)
{
    pushed_self = false;
    // :解析
    std::string path = cb;
    std::string method;
    const auto colon = path.find(':');
    if (colon != std::string::npos)
    {
        method = path.substr(colon + 1);
        path = path.substr(0, colon);
    }

    // .
    std::vector<std::string> segs;
    {
        size_t pos = 0;
        while (true)
        {
            size_t dot = path.find('.', pos);
            if (dot == std::string::npos)
            {
                segs.emplace_back(path.substr(pos));
                break;
            }
            segs.emplace_back(path.substr(pos, dot - pos));
            pos = dot + 1;
        }
    }
    if (segs.empty() || segs[0].empty())
        return false;

    // 全局
    lua_getglobal(L, segs[0].c_str()); // -> [val]
    if (lua_isnil(L, -1))
        return false;

    // 逐级下钻后续段
    for (size_t i = 1; i < segs.size(); ++i)
    {
        if (!lua_istable(L, -1))
            return false;
        lua_getfield(L, -1, segs[i].c_str()); // -> [tbl, field]
        lua_remove(L, -2);                    // 保留 field -> [field]
        if (lua_isnil(L, -1))
            return false;
    }

    // 冒号语法，栈顶应为self,从中再取 method 函数，并把栈排成 [func, self]
    if (!method.empty())
    {
        if (!lua_istable(L, -1))
            return false;
        lua_pushvalue(L, -1);                // [self, self]
        lua_getfield(L, -2, method.c_str()); // [self, self, func]
        lua_remove(L, -2);                   // [self, func]
        if (!lua_isfunction(L, -1))
            return false;
        lua_insert(L, -2); // [func, self]
        pushed_self = true;
        return true;
    }

    // 非冒号
    if (lua_isfunction(L, -1))
        return true;
    if (lua_istable(L, -1))
    {
        return true;
    }
    return false;
}

// 待回调队列Asio -> Lua
struct PendingTimer
{
    lua_State *owner = nullptr; // 所属 Lua VM
    uint32_t ti;
    uint32_t timerID;
};

class PendingQueue
{
public:
    void push(PendingTimer p)
    {
        std::lock_guard<std::mutex> lk(mu_);
        q_.push_back(std::move(p));
    }
    // 只弹出属于该 Lua VM 的到期任务
    bool pop_for(lua_State *L, PendingTimer &out)
    {
        std::lock_guard<std::mutex> lk(mu_);
        for (auto it = q_.begin(); it != q_.end(); ++it)
        {
            if (it->owner == L)
            {
                out = *it;
                q_.erase(it);
                return true;
            }
        }
        return false;
    }
    void purge_for(lua_State *L, uint32_t ti, uint32_t timerID)
    {
        std::lock_guard<std::mutex> lk(mu_);
        q_.erase(std::remove_if(q_.begin(), q_.end(),
                                [&](const PendingTimer &p)
                                {
                                    return p.owner == L && p.ti == ti && p.timerID == timerID;
                                }),
                 q_.end());
    }

private:
    std::mutex mu_;
    std::deque<PendingTimer> q_;
};

inline PendingQueue g_pending;

// 单例io_context/工作线程
class AsioHub
{
public:
    inline static AsioHub &instance()
    {
        static AsioHub h;
        return h;
    }
    boost::asio::io_context &io() { return io_; }

private:
    AsioHub()
        : guard_(boost::asio::make_work_guard(io_)),
          th_([this]
              { io_.run(); }) {}
    ~AsioHub()
    {
        guard_.reset();
        io_.stop();
        if (th_.joinable())
            th_.join();
    }
    boost::asio::io_context io_;
    boost::asio::executor_work_guard<boost::asio::io_context::executor_type> guard_;
    std::thread th_;
};

// 定时器句柄
struct TimerHandle
{
    std::shared_ptr<boost::asio::steady_timer> timer;
    std::atomic<bool> stopped{false};
    int interval_ms = 0;
    std::atomic<int> repeat_count{-1}; // -1 无限；>0 剩余次数；0 结束
    uint32_t ti = 0;
    uint32_t timerID = 0;
    lua_State *L = nullptr; // 所属 Lua VM

    TimerHandle(boost::asio::io_context &io,
                lua_State *Ls, uint32_t ti_, uint32_t id_, int ms, int cnt)
        : timer(std::make_shared<boost::asio::steady_timer>(io)),
          interval_ms(ms), repeat_count(cnt), ti(ti_), timerID(id_), L(Ls) {}
};

inline static void arm_timer(const std::shared_ptr<TimerHandle> &h)
{
    if (!h || h->stopped.load() || h->repeat_count.load() == 0)
        return;

    h->timer->expires_after(std::chrono::milliseconds(h->interval_ms));
    std::weak_ptr<TimerHandle> weak = h;
    h->timer->async_wait([weak](const boost::system::error_code &ec)
                         {
        auto sh = weak.lock();
        if (!sh || sh->stopped.load() || ec) return;

        g_pending.push(PendingTimer{sh->L, sh->ti, sh->timerID});

        if (sh->repeat_count.load() > 0) sh->repeat_count--;
        if (sh->repeat_count.load() != 0) {
            arm_timer(sh);
        } });
}

// logger
inline static void dbg(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    va_list ap_copy;
    va_copy(ap_copy, ap);
    int need = vsnprintf(nullptr, 0, fmt, ap_copy);
    va_end(ap_copy);
    if (need < 0)
    {
        va_end(ap);
        KM_LOG_INFO("{}", "<format error>");
        return;
    }
    std::vector<char> buf(static_cast<size_t>(need) + 1); // +1 放结尾 '\0'
    vsnprintf(buf.data(), buf.size(), fmt, ap);
    va_end(ap);
    KM_LOG_INFO("{}", buf.data());
}

inline static void luaLog(lua_State *L, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    va_list ap_copy;
    va_copy(ap_copy, ap);
    int need = vsnprintf(nullptr, 0, fmt, ap_copy);
    va_end(ap_copy);
    if (need < 0)
    {
        va_end(ap);
        KM_LOG_WARN_L(L, "LUA,<format error>");
        return;
    }
    std::vector<char> buf(static_cast<size_t>(need) + 1); // +1 放结尾 '\0'
    vsnprintf(buf.data(), buf.size(), fmt, ap);
    va_end(ap);
    KM_LOG_WARN_L(L, "LUA,{}", buf.data());
}

// 小工具
inline static std::string luaL_checkstring_std(lua_State *L, int idx)
{
    size_t len = 0;
    const char *s = luaL_checklstring(L, idx, &len);
    return std::string(s, len);
}

/*======================================================
 * KM
 *======================================================*/
struct KM
{
    std::unordered_map<uint32_t, std::string> proto_cb;                       // (mid<<16|sid) -> cb
    std::unordered_map<uint32_t, std::string> timer_cb;                       // (ti<<16|timer) -> cb
    std::unordered_map<uint32_t, std::shared_ptr<TimerHandle>> timer_handles; //(ti<<16|timer) -> handle
    std::string log_path = "./logs";
    std::string log_file = "server.log";
    std::mt19937_64 rng{std::random_device{}()};
};

// 注册到lua全局引用住
inline static KM **checkKM(lua_State *L, int idx)
{
    return (KM **)luaL_checkudata(L, idx, MT_KM);
}

inline static int km_gc(lua_State *L)
{
    // km常驻无需清理
    return 0;
}

inline static int km_Shutdown(lua_State *L)
{
    auto km = *checkKM(L, 1);
    if (!km)
        return 0;
    for (auto &kv : km->timer_handles)
    {
        auto &h = kv.second;
        if (h)
        {
            h->stopped.store(true);
            boost::system::error_code ig;
            h->timer->cancel(ig);
        }
    }
    km->timer_handles.clear();
    km->timer_cb.clear();
    return 0;
}

inline static KM *getKM(lua_State *L)
{
    KM *km = nullptr;
    // 常驻内存
    lua_getfield(L, LUA_REGISTRYINDEX, KM_REGKEY);
    if (lua_isuserdata(L, -1))
    {
        km = *(KM **)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return km;
}

// km_new：返回同一个 userdata（单例）
inline static int km_new(lua_State *L)
{
    (void)lua_touserdata(L, 1); // kernel 占位
    // 1) registry里已有直接返回userdata
    lua_getfield(L, LUA_REGISTRYINDEX, KM_REGKEY);
    if (lua_isuserdata(L, -1))
    {
        return 1; // 栈顶就是 userdata
    }
    lua_pop(L, 1);

    // 2) 没有则创建并写入 registry
    auto ud = (KM **)lua_newuserdata(L, sizeof(KM *));
    *ud = new KM();

    luaL_getmetatable(L, MT_KM);
    lua_setmetatable(L, -2);

    lua_pushvalue(L, -1); // dup userdata
    lua_setfield(L, LUA_REGISTRYINDEX, KM_REGKEY);

    return 1;
}

// km:RegFunc(MainID, SubID, cbName)
inline static int km_RegFunc(lua_State *L)
{
    auto km = *checkKM(L, 1);
    uint32_t mid = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t sid = (uint32_t)luaL_checkinteger(L, 3);
    auto cb = luaL_checkstring_std(L, 4);
    uint32_t key = (mid << 16) | (sid & 0xFFFF);
    km->proto_cb[key] = cb;
    return 0;
}

// km:GetFunC(MainID, SubID) -> string|""
inline static int km_GetFunC(lua_State *L)
{
    auto km = *checkKM(L, 1);
    uint32_t mid = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t sid = (uint32_t)luaL_checkinteger(L, 3);
    uint32_t key = (mid << 16) | (sid & 0xFFFF);
    auto it = km->proto_cb.find(key);
    if (it == km->proto_cb.end())
        lua_pushliteral(L, "");
    else
        lua_pushlstring(L, it->second.data(), it->second.size());
    return 1;
}

// km:SetTimer(threadIndex, timerID, elapse_ms, repeat, cbName)
inline static int km_SetTimer(lua_State *L)
{
    auto km = *checkKM(L, 1);
    uint32_t ti = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t timerID = (uint32_t)luaL_checkinteger(L, 3);
    int elapse_ms = (int)luaL_checkinteger(L, 4);
    int repeat = (int)luaL_checkinteger(L, 5); // -1 无限；>0 次数；0 将视为不触发
    auto cb = luaL_checkstring_std(L, 6);
    uint32_t key = (ti << 16) | (timerID & 0xFFFF);
    km->timer_cb[key] = cb;

    // 如果已存在旧定时器，先停掉
    auto it_old = km->timer_handles.find(key);
    if (it_old != km->timer_handles.end())
    {
        it_old->second->stopped.store(true);
        boost::system::error_code ig;
        it_old->second->timer->cancel(ig);
        km->timer_handles.erase(it_old);
    }
    // 清掉旧的 pending 事件
    g_pending.purge_for(L, ti, timerID);
    if (repeat == 0 || elapse_ms <= 0)
    {
        // 不启动定时器只登记 cb
        return 0;
    }
    // 创建定时器
    auto &io = AsioHub::instance().io();
    auto h = std::make_shared<TimerHandle>(io, L, ti, timerID, elapse_ms, repeat);
    km->timer_handles[key] = h;
    arm_timer(h);
    return 0;
}

// km:GetTimerFun(threadIndex, timerID) -> string|""
inline static int km_GetTimerFun(lua_State *L)
{
    auto km = *checkKM(L, 1);
    uint32_t ti = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t timerID = (uint32_t)luaL_checkinteger(L, 3);
    uint32_t key = (ti << 16) | (timerID & 0xFFFF);
    auto it = km->timer_cb.find(key);
    if (it == km->timer_cb.end())
        lua_pushliteral(L, "");
    else
        lua_pushlstring(L, it->second.data(), it->second.size());
    return 1;
}

// km:KillTimer(threadIndex, timerID)
inline static int km_KillTimer(lua_State *L)
{
    auto km = *checkKM(L, 1);
    uint32_t ti = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t timerID = (uint32_t)luaL_checkinteger(L, 3);
    uint32_t key = (ti << 16) | (timerID & 0xFFFF);

    // 取消 asio 定时器
    auto it = km->timer_handles.find(key);
    km->timer_cb.erase(key);
    if (it != km->timer_handles.end())
    {
        it->second->stopped.store(true);
        boost::system::error_code ig;
        it->second->timer->cancel(ig);
        km->timer_handles.erase(it);
    }
    // 清掉队列中同 ID 的悬挂任务
    g_pending.purge_for(L, ti, timerID);
    return 0;
}

inline int PollTimers(lua_State *L, int max_calls)
{
    KM *k = getKM(L);
    if (!k)
        return 0;

    int done = 0;
    PendingTimer pt;
    while (done < max_calls && g_pending.pop_for(L, pt))
    {
        const uint32_t key = (pt.ti << 16) | (pt.timerID & 0xFFFF);
        auto it = k->timer_cb.find(key);
        if (it == k->timer_cb.end())
        {
            KM_LOG_DEBUG("[timer] TI={} ID={} (no cb)", pt.ti, pt.timerID);
            ++done;
            continue;
        }
        const std::string &cbname = it->second;
        lua_getglobal(L, cbname.c_str());
        if (!lua_isnil(L, -1))
        {
            lua_pushinteger(L, (lua_Integer)pt.timerID);
            if (lua_pcall(L, 1, 0, 0) != LUA_OK)
            {
                const char *err = lua_tostring(L, -1);
                KM_LOG_ERROR("[timer] cb='{}' TI={} ID={} error: {}",
                             cbname.c_str(), pt.ti, pt.timerID, err ? err : "(unknown)");
                lua_pop(L, 1);
            }
        }
        else
        {
            lua_pop(L, 1);
        }
        ++done;
    }
    return done;
}

// km:CloseClient(net, clientID)
inline static int km_CloseClient(lua_State *L)
{
    (void)checkKM(L, 1);
    (void)lua_touserdata(L, 2); // net
    uint32_t cid = (uint32_t)luaL_checkinteger(L, 3);
    dbg("[km] CloseClient id=%u (stub)", cid);
    return 0;
}

// km:Log(str)
inline static int km_Log(lua_State *L)
{
    auto msg = luaL_checkstring_std(L, 2);
    luaLog(L, "%s", msg.c_str());
    return 0;
}

inline static int km_SetLogPath(lua_State *L)
{
    auto km = *checkKM(L, 1);
    auto path = luaL_checkstring_std(L, 2);
    auto base = luaL_checkstring_std(L, 3);
    std::string tag;
    if (lua_gettop(L) >= 4 && lua_type(L, 4) == LUA_TSTRING)
    {
        tag = luaL_checkstring_std(L, 4);
    }
    km->log_path = path;
    km->log_file = base;
    km_log::set_path_for((km_log::VMKey)L, path, base, tag);
    return 0;
}

// km:GetLogPath() -> {path, file}
inline static int km_GetLogPath(lua_State *L)
{
    auto km = *checkKM(L, 1);
    lua_createtable(L, 2, 0);
    lua_pushlstring(L, km->log_path.data(), km->log_path.size());
    lua_rawseti(L, -2, 1);
    lua_pushlstring(L, km->log_file.data(), km->log_file.size());
    lua_rawseti(L, -2, 2);
    dbg("[km] GetLogPath %s / %s", km->log_path.c_str(), km->log_file.c_str());
    return 1;
}

// km:NormalRandom(mu, sigma, changeSeedInt) -> number
inline static int km_NormalRandom(lua_State *L)
{
    auto km = *checkKM(L, 1);
    double mu = luaL_optnumber(L, 2, 0.0);
    double sigma = luaL_optnumber(L, 3, 1.0);
    int changeSeed = (int)luaL_optinteger(L, 4, 0);
    if (changeSeed)
        km->rng.seed(std::random_device{}());
    std::normal_distribution<double> dist(mu, sigma);
    lua_pushnumber(L, dist(km->rng));
    dbg("[km] NormalRandom mu=%f sigma=%f changeSeed=%d", mu, sigma, changeSeed);
    return 1;
}

inline static void push_km_class(lua_State *L)
{
    // 创建/获取 metatable
    if (luaL_newmetatable(L, MT_KM))
    {
        // methods 表
        lua_newtable(L);
        lua_pushcfunction(L, km_RegFunc);
        lua_setfield(L, -2, "RegFunc");
        lua_pushcfunction(L, km_GetFunC);
        lua_setfield(L, -2, "GetFunC");
        lua_pushcfunction(L, km_SetTimer);
        lua_setfield(L, -2, "SetTimer");
        lua_pushcfunction(L, km_GetTimerFun);
        lua_setfield(L, -2, "GetTimerFun");
        lua_pushcfunction(L, km_KillTimer);
        lua_setfield(L, -2, "KillTimer");
        lua_pushcfunction(L, km_CloseClient);
        lua_setfield(L, -2, "CloseClient");
        lua_pushcfunction(L, km_Log);
        lua_setfield(L, -2, "Log");
        lua_pushcfunction(L, km_SetLogPath);
        lua_setfield(L, -2, "SetLogPath");
        lua_pushcfunction(L, km_GetLogPath);
        lua_setfield(L, -2, "GetLogPath");
        lua_pushcfunction(L, km_NormalRandom);
        lua_setfield(L, -2, "NormalRandom");

        // mt.__index = methods
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");

        // mt.__gc
        lua_pushcfunction(L, km_gc);
        lua_setfield(L, -3, "__gc");

        // 弹出 methods，保留 mt 在栈顶
        lua_pop(L, 1);
    }
    // 弹出 mt
    lua_pop(L, 1);

    // 类表（仅导出 new）
    lua_newtable(L);
    lua_pushcfunction(L, km_new);
    lua_setfield(L, -2, "new");
    lua_setglobal(L, G_KM_NAME);
}

/*======================================================
 * mysql
 *======================================================*/

inline static MySQLHandle **checkConn(lua_State *L, int idx)
{
    return (MySQLHandle **)luaL_checkudata(L, idx, MT_MYSQL_CONN);
}

inline static int my_env_mysql(lua_State *L)
{
    if (lua_gettop(L) >= 1)
    {
        lua_settop(L, 1);
        return 1;
    }
    lua_getglobal(L, G_mysql_NAME);
    return 1;
}
inline static int my_env_close(lua_State *L)
{
    (void)luaL_checkudata(L, 1, MT_MYSQL_ENV); // 可选：校验类型
    return 0;                                  // 没有返回值
}

inline static int my_env_connect(lua_State *L)
{
    bool styleB = (lua_gettop(L) >= 3) && lua_type(L, 3) == LUA_TNUMBER;
    std::string db, user, pass, host;
    int port = 0, timeoutSec = 5;
    if (styleB)
    {
        // host, port, user, pass, db [,timeout]
        host = luaL_checkstring_std(L, 2);
        port = (int)luaL_checkinteger(L, 3);
        user = luaL_checkstring_std(L, 4);
        pass = luaL_checkstring_std(L, 5);
        db = luaL_checkstring_std(L, 6);
        timeoutSec = (int)luaL_optinteger(L, 7, 5);
    }
    else
    {
        // db, user, pass, host, port [,timeout]
        db = luaL_checkstring_std(L, 2);
        user = luaL_checkstring_std(L, 3);
        pass = luaL_checkstring_std(L, 4);
        host = luaL_checkstring_std(L, 5);
        port = (int)luaL_checkinteger(L, 6);
        timeoutSec = (int)luaL_optinteger(L, 7, 5);
    }

    // 创建一个新的连接对象
    auto ud = (MySQLHandle **)lua_newuserdata(L, sizeof(MySQLHandle *));
    *ud = new MySQLHandle();

    bool ok = (*ud)->connect(host, port, user, pass, db, timeoutSec);
    KM_LOG_INFO("mysql.connect host={} port={} db={} user={} -> {}",
                host, port, db, user, ok ? "OK" : "FAIL");
    luaL_getmetatable(L, MT_MYSQL_CONN);
    lua_setmetatable(L, -2);
    return 1;
}

inline static int myc_execute(lua_State *L)
{
    auto pp = checkConn(L, 1);
    if (!pp || !*pp || !(*pp)->conn)
    {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid connection");
        return 2;
    }

    MySQLHandle *h = *pp;
    std::string sql = luaL_checkstring_std(L, 2);

    if (mysql_real_query(h->conn, sql.c_str(), (unsigned long)sql.size()) != 0)
    {
        lua_pushnil(L);
        lua_pushstring(L, mysql_error(h->conn));
        return 2;
    }

    MYSQL_RES *res = mysql_store_result(h->conn);
    if (res)
    {
        return push_cursor(L, h, res); // => cursor
    }
    if (mysql_field_count(h->conn) == 0)
    {
        lua_pushinteger(L, (lua_Integer)mysql_affected_rows(h->conn)); // => number
        return 1;
    }
    lua_pushnil(L);
    lua_pushstring(L, mysql_error(h->conn));
    return 2;
}

inline static int myc_nextres(lua_State *L)
{
    auto pp = checkConn(L, 1);
    if (!pp || !*pp || !(*pp)->conn)
    {
        lua_pushnil(L);
        lua_pushliteral(L, "invalid connection");
        return 2;
    }

    MySQLHandle *h = *pp;
    return myc_nextres_impl(pp, L);
}

inline static int myc_close(lua_State *L)
{
    auto pp = checkConn(L, 1);
    if (pp && *pp)
        (*pp)->close();
    KM_LOG_INFO("[mysql] close conn ud={} mysql_ptr={}", (void *)pp, (void *)(*pp ? (*pp)->conn : nullptr));
    return 0;
}

inline static int myc_gc(lua_State *L)
{
    auto pp = checkConn(L, 1);
    if (pp && *pp)
    {
        (*pp)->close();
        delete *pp;
        *pp = nullptr;
    }
    KM_LOG_INFO("[mysql] __gc conn ud={} mysql_ptr={}", (void *)pp, (void *)(*pp ? (*pp)->conn : nullptr));
    return 0;
}

inline static void push_mysql_class(lua_State *L)
{
    // metatable
    if (luaL_newmetatable(L, MT_MYSQL_CONN))
    {
        lua_newtable(L);
        lua_pushcfunction(L, myc_execute);
        lua_setfield(L, -2, "exec");
        lua_pushcfunction(L, myc_execute);
        lua_setfield(L, -2, "execute"); // alias
        lua_pushcfunction(L, myc_nextres);
        lua_setfield(L, -2, "nextres");

        lua_pushcfunction(L, myc_close);
        lua_setfield(L, -2, "close");
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");
        lua_pushcfunction(L, myc_gc);
        lua_setfield(L, -3, "__gc");
        lua_pop(L, 1); // pop methods
    }
    lua_pop(L, 1); // pop mt
    //  metatable
    if (luaL_newmetatable(L, MT_MYSQL_ENV))
    {
        lua_newtable(L);
        lua_pushcfunction(L, my_env_connect);
        lua_setfield(L, -2, "connect");
        lua_pushcfunction(L, my_env_mysql);
        lua_setfield(L, -2, "mysql"); // 兼容 m.GetMySQL().mysql()
        lua_pushcfunction(L, my_env_close);
        lua_setfield(L, -2, "close");
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");
        lua_pop(L, 1); // pop methods
    }
    lua_pop(L, 1); // pop mt

    // 占位 userdata
    void **ud_env = (void **)lua_newuserdata(L, sizeof(void *));
    *ud_env = nullptr;
    luaL_getmetatable(L, MT_MYSQL_ENV);
    lua_setmetatable(L, -2);
    lua_setglobal(L, G_mysql_NAME);
}

/*======================================================
 * RP（读包）
 *======================================================*/
struct RP
{
    std::vector<unsigned char> buf;
    size_t cur = 0; // 读游标

    RP(const unsigned char *p, size_t n)
    {
        if (p && n)
            buf.assign(p, p + n);
    }

    // 仅取得 body 起始指针与总长度（不带游标）
    std::pair<const unsigned char *, size_t> body_span() const
    {
        if (buf.size() < MIN_FRAME10)
            return {nullptr, 0};
        const unsigned char *base = buf.data();
        uint16_t body_len = load_le16(base + OFF_BODY_LEN);
        const size_t start = OFF_BODY_LEN + 2;
        const size_t need = start + body_len;
        if (need > buf.size())
            return {nullptr, 0};
        return {base + start, static_cast<size_t>(body_len)};
    }

    uint16_t main_cmd() const
    {
        if (buf.size() < OFF_MAIN_CMD + 2)
            return 0;
        return load_le16(buf.data() + OFF_MAIN_CMD);
    }
    uint16_t sub_cmd() const
    {
        if (buf.size() < OFF_SUB_CMD + 2)
            return 0;
        return load_le16(buf.data() + OFF_SUB_CMD);
    }
    uint16_t packet_size() const
    {
        if (buf.size() < OFF_PKT_SZ + 2)
            return 0;
        return load_le16(buf.data() + OFF_PKT_SZ);
    }
    uint16_t body_len() const
    {
        if (buf.size() < OFF_BODY_LEN + 2)
            return 0;
        return load_le16(buf.data() + OFF_BODY_LEN);
    }
};

// ---- Lua 绑定：游标式读取 ----
inline static RP **checkRP(lua_State *L, int idx)
{
    return (RP **)luaL_checkudata(L, idx, MT_RP);
}

inline static int rp_gc(lua_State *L)
{
    auto pp = checkRP(L, 1);
    if (pp && *pp)
    {
        delete *pp;
        *pp = nullptr;
    }
    return 0;
}

// GetString(): main/sub==0时按 '\0' 分段，否则一次性读剩余
inline static int rp_GetString(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    auto [p, n] = rp->body_span();
    if (!p || rp->cur >= n)
    {
        lua_pushliteral(L, "");
        return 1;
    }
    if (rp->main_cmd() == 0 && rp->sub_cmd() == 0)
    {
        size_t i = rp->cur;
        while (i < n && p[i] != '\0')
            ++i;
        lua_pushlstring(L, reinterpret_cast<const char *>(p + rp->cur), i - rp->cur);
        rp->cur = (i < n && p[i] == '\0') ? (i + 1) : n;
        return 1;
    }
    else
    {
        size_t left = n - rp->cur;
        lua_pushlstring(L, reinterpret_cast<const char *>(p + rp->cur), left);
        rp->cur = n;
        return 1;
    }
}

// GetUint32(): 从游标按小端读取 4 字节
inline static int rp_GetUint32(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    auto [p, n] = rp->body_span();
    if (!p || rp->cur + 4 > n)
    {
        lua_pushinteger(L, 0);
        return 1;
    }
    const unsigned char *q = p + rp->cur;
    uint32_t v = (uint32_t)q[0] | ((uint32_t)q[1] << 8) | ((uint32_t)q[2] << 16) | ((uint32_t)q[3] << 24);
    rp->cur += 4;
    lua_pushinteger(L, (lua_Integer)v);
    return 1;
}

// GetInt32():
inline static int rp_GetInt32(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    auto [p, n] = rp->body_span();
    if (!p || rp->cur + 4 > n)
    {
        lua_pushinteger(L, 0);
        return 1;
    }

    const unsigned char *q = p + rp->cur;
    uint32_t u = (uint32_t)q[0] | ((uint32_t)q[1] << 8) | ((uint32_t)q[2] << 16) | ((uint32_t)q[3] << 24);

    int32_t v = (int32_t)u; // 关键：符号解释
    rp->cur += 4;
    lua_pushinteger(L, (lua_Integer)v);
    return 1;
}

// GetBuff(): 返回“剩余未读”的全部字节 + 长度
inline static int rp_GetBuff(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    auto [p, n] = rp->body_span();
    if (!p || rp->cur >= n)
    {
        lua_pushliteral(L, "");
        lua_pushinteger(L, 0);
        return 2;
    }
    size_t left = n - rp->cur;
    lua_pushlstring(L, reinterpret_cast<const char *>(p + rp->cur), left);
    lua_pushinteger(L, (lua_Integer)left);
    rp->cur = n;
    return 2;
}

inline static int rp_GetBodyLen(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    lua_pushinteger(L, (lua_Integer)rp->body_len());
    return 1;
}
inline static int rp_GetPacketSize(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    lua_pushinteger(L, (lua_Integer)rp->packet_size());
    return 1;
}

// RP.new(bytes) / RP(ptr, len)
inline static int rp_new(lua_State *L)
{
    int idx = 1;
    if (lua_gettop(L) >= 1)
    {
        int t0 = lua_type(L, 1);
        if (t0 != LUA_TSTRING && t0 != LUA_TLIGHTUSERDATA && t0 != LUA_TUSERDATA)
            idx = 2;
    }
    const unsigned char *p = nullptr;
    size_t len = 0;
    int t = lua_type(L, idx);
    if (t == LUA_TSTRING)
    {
        p = (const unsigned char *)luaL_checklstring(L, idx, &len);
    }
    else if ((t == LUA_TLIGHTUSERDATA || t == LUA_TUSERDATA) && lua_isnumber(L, idx + 1))
    {
        p = (const unsigned char *)lua_touserdata(L, idx);
        lua_Integer n = lua_tointeger(L, idx + 1);
        if (n < 0)
            return luaL_error(L, "length must be >= 0");
        len = (size_t)n;
    }
    else
    {
        return luaL_error(L, "RP.new expects (string) or (pointer, length)");
    }

    auto ud = (RP **)lua_newuserdata(L, sizeof(RP *));
    *ud = new RP(p, len);
    luaL_getmetatable(L, MT_RP);
    lua_setmetatable(L, -2);
    return 1;
}

inline static int rp_GetModuleID(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    lua_pushinteger(L, (lua_Integer)rp->main_cmd());
    return 1;
}

inline static int rp_GetMsgID(lua_State *L)
{
    auto rp = *checkRP(L, 1);
    lua_pushinteger(L, (lua_Integer)rp->sub_cmd());
    return 1;
}

inline static void push_rp_class(lua_State *L)
{
    if (luaL_newmetatable(L, MT_RP))
    {
        lua_newtable(L);
        // 解析 API（游标式）
        lua_pushcfunction(L, rp_GetString);
        lua_setfield(L, -2, "GetString");
        lua_pushcfunction(L, rp_GetUint32);
        lua_setfield(L, -2, "GetUint32");
        lua_pushcfunction(L, rp_GetInt32);
        lua_setfield(L, -2, "GetInt32");
        lua_pushcfunction(L, rp_GetBuff);
        lua_setfield(L, -2, "GetBuff");
        // 其它查询
        lua_pushcfunction(L, rp_GetBodyLen);
        lua_setfield(L, -2, "GetBodyLen");
        lua_pushcfunction(L, rp_GetPacketSize);
        lua_setfield(L, -2, "GetPacketSize");

        lua_pushcfunction(L, rp_GetModuleID);
        lua_setfield(L, -2, "GetModuleID");
        lua_pushcfunction(L, rp_GetMsgID);
        lua_setfield(L, -2, "GetMsgID");

        // 元方法
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");
        lua_pushcfunction(L, rp_gc);
        lua_setfield(L, -3, "__gc");
        lua_pop(L, 1); // pop methods
    }
    lua_pop(L, 1); // pop mt

    lua_newtable(L); // RP 类表
    lua_pushcfunction(L, rp_new);
    lua_setfield(L, -2, "new");

    lua_newtable(L); // 让 RP(...) 可直接调用
    lua_pushcfunction(L, rp_new);
    lua_setfield(L, -2, "__call");
    lua_setmetatable(L, -2);

    lua_setglobal(L, G_RP_NAME);
}

/*======================================================
 * SP（写包）
 *======================================================*/
struct SP
{
    uint16_t main_cmd = 0;
    uint16_t sub_cmd = 0;
    std::vector<unsigned char> body; // Packet body
    std::vector<unsigned char> out;  // build 后的完整帧

    inline static void store_le16(unsigned char *p, uint16_t v)
    {
        p[0] = (unsigned char)(v & 0xFF);
        p[1] = (unsigned char)((v >> 8) & 0xFF);
    }
    inline static void wrU32LE(std::vector<unsigned char> &v, uint32_t x)
    {
        v.push_back((unsigned char)(x & 0xFF));
        v.push_back((unsigned char)((x >> 8) & 0xFF));
        v.push_back((unsigned char)((x >> 16) & 0xFF));
        v.push_back((unsigned char)((x >> 24) & 0xFF));
    }
    inline static void wrI32LE(std::vector<unsigned char> &v, int32_t x)
    {
        wrU32LE(v, (uint32_t)x);
    }
    inline static void append_bytes(std::vector<unsigned char> &v, const void *p, size_t n)
    {
        const auto *b = reinterpret_cast<const unsigned char *>(p);
        v.insert(v.end(), b, b + n);
    }

    void build()
    {
        const uint16_t body_len = (uint16_t)body.size();
        const uint16_t total = (uint16_t)(HEADER_BYTES + 2 + body_len);
        out.assign(total, 0);
        unsigned char *base = out.data();

        auto ok_off = [&](size_t off)
        { return off < out.size(); };
        assert(ok_off(OFF_VER) && ok_off(OFF_CHECK) && ok_off(OFF_PKT_SZ + 1) &&
               ok_off(OFF_MAIN_CMD + 1) && ok_off(OFF_SUB_CMD + 1) && ok_off(OFF_BODY_LEN + 1));
        assert((size_t)OFF_BODY_LEN + 2 + body_len <= out.size());

        base[OFF_VER] = 0;
        base[OFF_CHECK] = 0;
        store_le16(base + OFF_PKT_SZ, total);
        store_le16(base + OFF_MAIN_CMD, main_cmd);
        store_le16(base + OFF_SUB_CMD, sub_cmd);
        store_le16(base + OFF_BODY_LEN, body_len);

        if (body_len)
        {
            std::memcpy(base + OFF_BODY_LEN + 2, body.data(), body_len);
        }
    }
};

inline static SP **checkSP(lua_State *L, int idx)
{
    return (SP **)luaL_checkudata(L, idx, MT_SP);
}

inline static int sp_gc(lua_State *L)
{
    auto pp = checkSP(L, 1);
    if (pp && *pp)
    {
        delete *pp;
        *pp = nullptr;
    }
    return 0;
}

// SP.new([main_cmd, sub_cmd])
inline static int sp_new(lua_State *L)
{
    auto ud = (SP **)lua_newuserdata(L, sizeof(SP *));
    *ud = new SP();
    luaL_getmetatable(L, MT_SP);
    lua_setmetatable(L, -2);
    if (lua_gettop(L) >= 2)
    {
        (*ud)->main_cmd = (uint16_t)luaL_checkinteger(L, 1);
        (*ud)->sub_cmd = (uint16_t)luaL_checkinteger(L, 2);
    }
    KM_LOG_INFO("sp_new, main_cmd={}, sub_cmd={}", (*ud)->main_cmd, (*ud)->sub_cmd);
    return 1;
}

inline static int sp_new2(lua_State *L)
{
    size_t n = 0;
    const unsigned char *p = (const unsigned char *)luaL_checklstring(L, 1, &n);
    auto ud = (SP **)lua_newuserdata(L, sizeof(SP *));
    *ud = new SP();
    SP *sp = *ud;
    // 直接把完整帧放进out,后面 SendData就不会再 uild()
    sp->out.assign(p, p + n);
    // 尝试解析 main/sub/body（用于日志/调试，不改变 out）
    if (n >= MIN_FRAME10)
    {
        const uint16_t pkt_sz = load_le16(p + OFF_PKT_SZ);
        const uint16_t main_cmd = load_le16(p + OFF_MAIN_CMD);
        const uint16_t sub_cmd = load_le16(p + OFF_SUB_CMD);
        const uint16_t body_len = load_le16(p + OFF_BODY_LEN);
        const size_t need = OFF_BODY_LEN + 2 + (size_t)body_len;
        if (pkt_sz == n && need == n)
        {
            sp->main_cmd = main_cmd;
            sp->sub_cmd = sub_cmd;
            // 仅为了后续若用户还会在此 SP 上追加 body/重建时可复用
            if (body_len)
            {
                const unsigned char *body = p + OFF_BODY_LEN + 2;
                sp->body.assign(body, body + body_len);
            }
        }
    }
    luaL_getmetatable(L, MT_SP);
    lua_setmetatable(L, -2);
    return 1;
}

inline static int sp_SendData(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    // 占位参数，与旧脚本签名兼容
    (void)lua_touserdata(L, 2);
    const int64_t clientId = (int64_t)luaL_checkinteger(L, 3);
    // 若 out 为空，说明是用 new()/AddString()/AddBuff() 构建的,build 一次；
    // 若是 new2() 传入的完整帧，out 已经有内容，就不再 build。
    if (sp->out.empty())
    {
        sp->build();
    }
    const bool ok = gv_send_to(clientId, sp->out.data(), sp->out.size());
    lua_pushinteger(L, ok ? 1 : 0);
    return 1;
}

// 覆盖=>追加 AddString
inline static int sp_AddString(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    size_t n = 0;
    const char *s = luaL_checklstring(L, 2, &n);
    SP::append_bytes(sp->body, s, n);
    if (sp->main_cmd == 0 && sp->sub_cmd == 0)
    {
        sp->body.push_back('\0');
    }
    KM_LOG_INFO("sp_AddString(append),maincmd={},subCmd={},len={}", sp->main_cmd, sp->sub_cmd, n);
    return 0;
}

// 覆盖=>追加 AddBuff
inline static int sp_AddBuff(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    size_t n = 0;
    const char *p = luaL_checklstring(L, 2, &n);
    SP::append_bytes(sp->body, p, n);
    KM_LOG_INFO("sp_AddBuff(append), len={}", n);
    return 0;
}

// 追加 AddUint32
inline static int sp_AddUint32(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    uint32_t v = (uint32_t)luaL_checkinteger(L, 2);
    SP::wrU32LE(sp->body, v);
    KM_LOG_INFO("sp_AddUint32, v={}", v);
    return 0;
}

// 追加 AddInt32
inline static int sp_AddInt32(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    int32_t v = (int32_t)luaL_checkinteger(L, 2);
    SP::wrI32LE(sp->body, v);
    KM_LOG_INFO("sp_AddInt32, v={}", v);
    return 0;
}

// sp:SetCmd(main_cmd, sub_cmd)
inline static int sp_SetCmd(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    sp->main_cmd = (uint16_t)luaL_checkinteger(L, 2);
    sp->sub_cmd = (uint16_t)luaL_checkinteger(L, 3);
    KM_LOG_INFO("sp_SetCmd, main={}, sub={}", sp->main_cmd, sp->sub_cmd);
    return 0;
}

// sp:GetData()->完整帧（含头+body_len+body）
inline static int sp_GetData(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    sp->build();
    lua_pushlstring(L, (const char *)sp->out.data(), sp->out.size());
    return 1;
}

// sp:GetSize()->完整帧长度
inline static int sp_GetSize(lua_State *L)
{
    auto sp = *checkSP(L, 1);
    sp->build();
    lua_pushinteger(L, (lua_Integer)sp->out.size());
    return 1;
}

inline static void push_sp_class(lua_State *L)
{
    if (luaL_newmetatable(L, MT_SP))
    {
        lua_newtable(L);
        static const luaL_Reg sp_methods[] = {
            {"AddString", sp_AddString},
            {"AddBuff", sp_AddBuff},
            {"AddUint32", sp_AddUint32},
            {"AddInt32", sp_AddInt32},
            {"SetCmd", sp_SetCmd},
            {"GetData", sp_GetData},
            {"GetSize", sp_GetSize},
            {"SendData", sp_SendData},
            {NULL, NULL}};
        luaL_setfuncs(L, sp_methods, 0);
        lua_setfield(L, -2, "__index");
        lua_pushcfunction(L, sp_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
    lua_newtable(L);
    static const luaL_Reg sp_ctor[] = {
        {"new", sp_new},
        {"new2", sp_new2},
        {NULL, NULL}};
    luaL_setfuncs(L, sp_ctor, 0);
    lua_setglobal(L, G_SP_NAME);
}

// inline static void push_sp_class(lua_State *L)
// {
//     if (luaL_newmetatable(L, MT_SP))
//     {
//         lua_newtable(L);
//         lua_pushcfunction(L, sp_AddString);
//         lua_setfield(L, -2, "AddString");
//         lua_pushcfunction(L, sp_AddBuff);
//         lua_setfield(L, -2, "AddBuff");
//         lua_pushcfunction(L, sp_AddUint32);
//         lua_setfield(L, -2, "AddUint32");
//         // 新增addint32
//         lua_pushcfunction(L, sp_AddInt32);
//         lua_setfield(L, -2, "AddInt32");
//         lua_pushcfunction(L, sp_SetCmd);
//         lua_setfield(L, -2, "SetCmd");
//         lua_pushcfunction(L, sp_GetData);
//         lua_setfield(L, -2, "GetData");
//         lua_pushcfunction(L, sp_GetSize);
//         lua_setfield(L, -2, "GetSize");
//          lua_pushcfunction(L, sp_SendData); //新增导出
//         lua_setfield(L, -2, "SendData");
//         lua_pushvalue(L, -1);
//         lua_setfield(L, -3, "__index");
//         lua_pushcfunction(L, sp_gc);
//         lua_setfield(L, -3, "__gc");
//         lua_pop(L, 1);
//     }
//     lua_pop(L, 1);

//     lua_newtable(L);
//     lua_pushcfunction(L, sp_new);
//     lua_setfield(L, -2, "new");
//     lua_pushcfunction(L, sp_new2);
//     lua_setfield(L, -2, "new2");
//     lua_setglobal(L, G_SP_NAME);
// }

/*======================================================
 * Queue（hiredis）
 *======================================================*/
struct Queue
{
    std::string host;
    int port = 0;
    std::string pass;
    int db = 0;
    bool use_tls = true;
    bool connected = false;
    redis_u::Conn conn;
};

inline static void q_free_conn(Queue *q)
{
    if (!q)
        return;
    q->conn.close();
    q->connected = false;
}

inline static bool q_connect_impl(Queue *q, int timeout_ms = 3000)
{
    if (!q)
        return false;
    q_free_conn(q);
    q->conn.opt.host = q->host;
    q->conn.opt.port = q->port;
    q->conn.opt.pass = q->pass;
    q->conn.opt.db = q->db;
    q->conn.opt.use_tls = q->use_tls || (q->port == 6380);
    q->conn.opt.timeout_ms = timeout_ms;
    q->conn.opt.keepalive = true;

    bool ok = q->conn.open();
    q->connected = ok;
    KM_LOG_INFO("[RedisQueue] connect host={} port={} db={} tls={} -> {}",
                q->host, q->port, q->db, q->conn.opt.use_tls, ok ? "OK" : "FAIL");
    return ok;
}

inline static int q_PostMsg(lua_State *L)
{
    Queue **pp = (Queue **)luaL_checkudata(L, 1, MT_Q);
    if (!pp || !*pp)
    {
        lua_pushinteger(L, 0);
        return 1;
    }
    Queue *q = *pp;

    size_t tag_len = 0;
    const char *tag_c = luaL_checklstring(L, 2, &tag_len);
    std::string tag(tag_c, tag_len);

    size_t n = 0;
    const char *p = luaL_checklstring(L, 3, &n);
    if (lua_gettop(L) >= 4 && lua_isnumber(L, 4))
    {
        lua_Integer want = lua_tointeger(L, 4);
        if (want >= 0 && (size_t)want <= n)
            n = (size_t)want;
    }
    KM_LOG_ERROR("[q_PostMsg] publish tag={},", tag);
    const bool ok = q->conn.publish(tag, p, n);
    if (!ok)
        KM_LOG_WARN("[RedisQueue] publish channel={} failed (will reconnect on next call)", tag);
    lua_pushinteger(L, ok ? 1 : 0);
    return 1;
}

inline static Queue **checkQ(lua_State *L, int idx)
{
    return (Queue **)luaL_checkudata(L, idx, MT_Q);
}

inline static int q_gc(lua_State *L)
{
    auto pp = checkQ(L, 1);
    if (pp && *pp)
    {
        q_free_conn(*pp);
        delete *pp;
        *pp = nullptr;
    }
    return 0;
}

inline static int q_new(lua_State *L)
{
    auto ud = (Queue **)lua_newuserdata(L, sizeof(Queue *));
    *ud = new Queue();
    luaL_getmetatable(L, MT_Q);
    lua_setmetatable(L, -2);
    return 1;
}

inline static int q_connect(lua_State *L)
{
    auto q = *checkQ(L, 1);
    q->host = luaL_checkstring(L, 2);
    q->port = (int)luaL_checkinteger(L, 3);
    q->pass.clear();
    q->db = 0;
    q->use_tls = false;

    if (lua_gettop(L) >= 4 && !lua_isnil(L, 4))
    {
        q->pass = luaL_checkstring(L, 4);
    }
    if (lua_gettop(L) >= 5 && !lua_isnil(L, 5))
    {
        q->db = (int)luaL_checkinteger(L, 5);
    }
    if (lua_gettop(L) >= 6 && !lua_isnil(L, 6))
    {
        q->use_tls = lua_toboolean(L, 6) != 0;
    }
    else
    {
        if (q->port == 6380)
            q->use_tls = true;
    }

    bool ok = q_connect_impl(q);
    KM_LOG_ERROR("q_connect, host={},port={},pwd={},db={}", q->host, q->port, q->pass, q->db);
    lua_pushinteger(L, ok ? 1 : 0);
    return 1;
}

inline static int q_close(lua_State *L)
{
    auto q = *checkQ(L, 1);
    q_free_conn(q);
    return 0;
}

inline static void push_queue_class(lua_State *L)
{
    if (luaL_newmetatable(L, MT_Q))
    {
        lua_newtable(L);
        lua_pushcfunction(L, q_connect);
        lua_setfield(L, -2, "connect");
        lua_pushcfunction(L, q_PostMsg);
        lua_setfield(L, -2, "PostMsg");
        lua_pushcfunction(L, q_close);
        lua_setfield(L, -2, "close");

        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");
        lua_pushcfunction(L, q_gc);
        lua_setfield(L, -3, "__gc");
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    lua_newtable(L);
    lua_pushcfunction(L, q_new);
    lua_setfield(L, -2, "new");
    lua_setglobal(L, G_Queue_NAME);
}

/*======================================================
 * MyRedis
 *======================================================*/
struct MyRedis
{
    // 配置
    std::string host;
    int port = 0;
    std::string pass;
    std::string marks;  // "ch1 ch2 ch3"
    std::string cbName; // base.wrap(...) 的返回名
    // 运行态
    lua_State *L = nullptr; // 归属 VM
    std::thread th;
    std::atomic<bool> stop{false};
    std::atomic<bool> connected{false};

    void run()
    {
        using namespace std::chrono_literals;
        int backoff_ms = 500; // 指数退避
        const int backoff_max = 5000;
        while (!stop.load())
        {
            redis_u::Conn conn;
            conn.opt.host = host;
            conn.opt.port = port;
            conn.opt.pass = pass;
            conn.opt.db = 0;
            conn.opt.use_tls = false;
            conn.opt.timeout_ms = 1000; // 统一1s超时
            conn.opt.keepalive = true;
            if (!conn.open())
            {
                KM_LOG_WARN_L(L, "[RedisSub] connect {}:{} failed, retry in {}ms", host, port, backoff_ms);
                std::this_thread::sleep_for(std::chrono::milliseconds(backoff_ms));
                backoff_ms = std::min(backoff_ms * 2, backoff_max);
                continue;
            }
            backoff_ms = 500;

            std::istringstream iss(marks);
            std::vector<std::string> channels;
            for (std::string ch; iss >> ch;)
                channels.push_back(ch);
            if (channels.empty())
            {
                KM_LOG_WARN_L(L, "[RedisSub] empty channels");
                std::this_thread::sleep_for(2s);
                continue;
            }
            std::vector<const char *> argv;
            argv.reserve(channels.size() + 1);
            std::vector<size_t> lens;
            lens.reserve(channels.size() + 1);
            argv.push_back("SUBSCRIBE");
            lens.push_back(strlen("SUBSCRIBE"));
            for (auto &ch : channels)
            {
                argv.push_back(ch.c_str());
                lens.push_back(ch.size());
            }

            {
                auto r = conn.cmdArgv(argv, lens);
                if (!r || r.get()->type == REDIS_REPLY_ERROR)
                {
                    KM_LOG_WARN_L(L, "[RedisSub] SUBSCRIBE fail");
                    std::this_thread::sleep_for(2s);
                    continue;
                }
            }

            connected.store(true);
            for (auto &ch : channels)
            {
                KM_LOG_INFO_L(L, "[RedisSub] subscribed channel: {}", ch);
            }
            KM_LOG_INFO_L(L, "[RedisSub] connected & subscribed {} channel(s)", (int)channels.size());

            // 拉消息：超时(1) => 仅继续,错误(-1)=> 断线重连
            while (!stop.load())
            {
                redisReply *r = nullptr;
                int rc = conn.getReply(&r);
                if (rc == 1)
                {
                    continue;
                }
                if (rc < 0)
                {
                    KM_LOG_WARN_L(L, "[RedisSub] getReply error, will reconnect");
                    break;
                }
                if (!r)
                    continue;

                // ["message", channel, payload]
                if (r->type == REDIS_REPLY_ARRAY && r->elements >= 3 &&
                    r->element[0]->type == REDIS_REPLY_STRING &&
                    std::string(r->element[0]->str, r->element[0]->len) == "message" &&
                    r->element[1]->type == REDIS_REPLY_STRING &&
                    r->element[2]->type == REDIS_REPLY_STRING)
                {
                    PendingRedisMsg m;
                    m.L = L;
                    m.cb = cbName;
                    m.channel.assign(r->element[1]->str, r->element[1]->len);
                    m.payload.assign(r->element[2]->str, r->element[2]->len);
                    g_redis_pending.push(std::move(m));
                }
                freeReplyObject(r);
            }

            connected.store(false);
            conn.close();

            if (!stop.load())
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(backoff_ms));
                backoff_ms = std::min(backoff_ms * 2, backoff_max);
            }
        }
    }

    void start()
    {
        stop.store(false);
        th = std::thread([this]
                         { run(); });
    }
    void close()
    {
        stop.store(true);
        if (th.joinable())
            th.join();
    }
};

inline static MyRedis **checkMR(lua_State *L, int idx)
{
    return (MyRedis **)luaL_checkudata(L, idx, MT_MR);
}

inline static int mr_new(lua_State *L)
{
    // new(kernel, threadIndex) —— 兼容老签名，但我们只需要 L
    (void)lua_touserdata(L, 1);
    (void)lua_tointeger(L, 2);

    auto ud = (MyRedis **)lua_newuserdata(L, sizeof(MyRedis *));
    *ud = new MyRedis();
    (*ud)->L = L; // 归属 VM
    luaL_getmetatable(L, MT_MR);
    lua_setmetatable(L, -2);
    return 1;
}

// mr:connect(kernel, host, port, pass, marks, cbName, uniqKey) -> 1/0
inline static int mr_connect(lua_State *L)
{
    auto mr = *checkMR(L, 1);
    (void)lua_touserdata(L, 2); // kernel 忽略
    mr->host = luaL_checkstring_std(L, 3);
    mr->port = (int)luaL_checkinteger(L, 4);
    if (lua_gettop(L) >= 5)
        mr->pass = luaL_checkstring_std(L, 5);
    mr->marks = luaL_checkstring_std(L, 6);
    mr->cbName = luaL_checkstring_std(L, 7);
    KM_LOG_ERROR("cbname={},marks={}", mr->cbName, mr->marks);
    if (lua_gettop(L) >= 8)
    {
        (void)luaL_checkstring_std(L, 8); // uniqKey, 这里用不上
    }
    try
    {
        mr->start();
        lua_pushinteger(L, 1);
    }
    catch (...)
    {
        lua_pushinteger(L, 0);
    }
    return 1;
}

inline static int mr_close(lua_State *L)
{
    auto mr = *checkMR(L, 1);
    if (mr)
    {
        mr->close();
        g_redis_pending.purge_for(mr->L);
    }
    return 0;
}

inline static int mr_gc(lua_State *L)
{
    auto pp = checkMR(L, 1);
    if (pp && *pp)
    {
        (*pp)->close();
        delete *pp;
        *pp = nullptr;
    }
    return 0;
}

inline static void push_myredis_class(lua_State *L)
{
    if (luaL_newmetatable(L, MT_MR))
    {
        lua_newtable(L);
        lua_pushcfunction(L, mr_connect);
        lua_setfield(L, -2, "connect");
        lua_pushcfunction(L, mr_close);
        lua_setfield(L, -2, "close");

        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");
        lua_pushcfunction(L, mr_gc);
        lua_setfield(L, -3, "__gc");
        lua_pop(L, 1);
    }
    lua_pop(L, 1);

    lua_newtable(L);
    lua_pushcfunction(L, mr_new);
    lua_setfield(L, -2, "new");
    lua_setglobal(L, G_MyRedis_NAME);
}

/*======================================================
 * 其他全局占位
 *======================================================*/
inline static void push_globals(lua_State *L)
{
    // Net：占位（裸 userdata）
    void **ud = (void **)lua_newuserdata(L, sizeof(void *));
    *ud = nullptr;
    lua_setglobal(L, G_NET_NAME);
    // Int64 / LOG（kmlog 已经有了这个暂时不知干嘛的 后续补）
    lua_newtable(L);
    lua_setglobal(L, G_Int64_NAME);
    lua_newtable(L);
    lua_setglobal(L, G_LOG_NAME);
}

/*======================================================
 * luaopen
 *======================================================*/
inline int luaopen_kmbridge(lua_State *L)
{
    static bool inited = []
    {
        mysql_library_init(0, nullptr, nullptr); // 只调一次
        return true;
    }();
    km_log::init_once();
    push_km_class(L);
    push_rp_class(L);
    push_sp_class(L);
    push_queue_class(L);
    push_myredis_class(L);
    push_globals(L);
    push_mysql_class(L);
    push_mysql_cur(L);
    //
    luaopen_kafka(L); // 注入kafka
    lua_setglobal(L, "Kafka");
    lua_newtable(L);
    return 1;
}

// 直接从字节创建RP userdata
inline static int push_rp_from_bytes(lua_State *L, const unsigned char *p, size_t n)
{
    auto ud = (RP **)lua_newuserdata(L, sizeof(RP *));
    *ud = new RP(p, n);
    luaL_getmetatable(L, MT_RP);
    lua_setmetatable(L, -2);
    return 1;
}

/*======================================================
 * 分发（去掉 traceback 版本）
 *======================================================*/

// 回退调用：dispatch(name, clientId, body, len)
static void call_fallback_dispatch(lua_State *L,
                                   const std::string &name,
                                   const Packet &packet)
{
    const int top0 = lua_gettop(L);

    lua_getglobal(L, "dispatch");
    if (!lua_isfunction(L, -1))
    {
        KM_LOG_ERROR_L(L, "[dispatch] neither 'dispatch_full' nor 'dispatch' found");
        lua_settop(L, top0);
        return;
    }

    lua_pushlstring(L, name.data(), name.size());
    lua_pushinteger(L, static_cast<lua_Integer>(packet.clientId));
    lua_pushlstring(L, reinterpret_cast<const char *>(packet.body.data()), packet.body.size());
    lua_pushinteger(L, static_cast<lua_Integer>(packet.body.size()));
    if (!packet.clientIp.empty())
        lua_pushlstring(L, packet.clientIp.data(), packet.clientIp.size());
    else
        lua_pushnil(L);
    if (lua_pcall(L, 5, 0, 0) != LUA_OK)
    {
        const char *err = lua_tostring(L, -1);
        KM_LOG_ERROR_L(L, "[dispatch] dispatch error: {}", err ? err : "(unknown)");
        lua_pop(L, 1);
    }

    lua_settop(L, top0);
}

inline void dispatch_to_lua(lua_State *L, const Packet &packet)
{
    KM *k = getKM(L);
    if (!k)
    {
        KM_LOG_WARN_L(L, "[dispatch] KM not initialized (mainId={} subId={})",
                      packet.main_cmd, packet.sub_cmd);
        return;
    }
    if (packet.acceptPort >= 0 && packet.acceptIpV4 != 0)
    {
        const int top0 = lua_gettop(L);
        lua_getglobal(L, "OnAccept");
        if (lua_isfunction(L, -1))
        {
            lua_pushinteger(L, static_cast<lua_Integer>(packet.clientId));
            lua_pushinteger(L, static_cast<lua_Integer>(packet.acceptIpV4)); // DWORD
            lua_pushinteger(L, static_cast<lua_Integer>(packet.acceptPort));
            // 不插 traceback
            if (lua_pcall(L, 3, 0, 0) != LUA_OK)
            {
                const char *err = lua_tostring(L, -1);
                KM_LOG_ERROR_L(L, "[OnAccept] error: {}", err ? err : "(unknown)");
                lua_pop(L, 1);
            }
        }
        else
        {
            lua_pop(L, 1); // 弹掉非函数
        }
        lua_settop(L, top0);
        return;
        // 注意：这是一个独立事件，与握手事件各自投递各自调用，无需 return
    }
    // 握手
    // 断开
    if (!packet.handShake.empty() && packet.handShake == "offline")
    {
        const int top0 = lua_gettop(L);
        lua_getglobal(L, "OnClose");
        if (!lua_isfunction(L, -1))
        {
            KM_LOG_ERROR_L(L, "[handshake] offline not found");
            lua_settop(L, top0);
            return;
        }
        lua_pushinteger(L, packet.clientId);
        if (lua_pcall(L, 1, 0, 0) != LUA_OK)
        {
            const char *err = lua_tostring(L, -1);
            KM_LOG_ERROR_L(L, "[handshake] error: {}", err ? err : "(unknown)");
            lua_pop(L, 1);
        }
        lua_settop(L, top0);
        return;
    }
    if (!packet.handShake.empty())
    {
        const int top0 = lua_gettop(L);
        lua_getglobal(L, "OnHandShake");
        if (!lua_isfunction(L, -1))
        {
            KM_LOG_ERROR_L(L, "[handshake] OnHandShake not found");
            lua_settop(L, top0);
            return;
        }
        lua_pushinteger(L, packet.clientId);
        lua_pushlstring(L, packet.handShake.data(), packet.handShake.size());
        if (lua_pcall(L, 2, 0, 0) != LUA_OK)
        {
            const char *err = lua_tostring(L, -1);
            KM_LOG_ERROR_L(L, "[handshake] error: {}", err ? err : "(unknown)");
            lua_pop(L, 1);
        }
        lua_settop(L, top0);
        return;
    }

    // 非握手, 先查注册
    const uint32_t key = (static_cast<uint32_t>(packet.main_cmd) << 16) |
                         (static_cast<uint32_t>(packet.sub_cmd) & 0xFFFF);
    auto it = k->proto_cb.find(key);

    // 未注册，回退到全局分发
    if (it == k->proto_cb.end())
    {
        KM_LOG_WARN_L(L, "[dispatch] no cb registered for mainId={} subId={}",
                      packet.main_cmd, packet.sub_cmd);
        char namebuf[64];
        std::snprintf(namebuf, sizeof(namebuf), "%u:%u",
                      static_cast<unsigned>(packet.main_cmd),
                      static_cast<unsigned>(packet.sub_cmd));
        call_fallback_dispatch(L, namebuf, packet);
        return;
    }

    // 已注册：直接调用注册函数 (clientId, body, len)
    const std::string &cb = it->second;
    bool pushed_self = false;
    if (!push_lua_callable(L, cb, pushed_self))
    {
        KM_LOG_WARN_L(L, "[dispatch] cannot resolve callable: %s (mainId=%u subId=%u)",
                      cb.c_str(), packet.main_cmd, packet.sub_cmd);
        if (lua_gettop(L) > 0)
            lua_pop(L, 1);
        call_fallback_dispatch(L, cb.empty() ? std::string("unresolved_cb") : cb, packet);
        return;
    }

    // 压参数：clientId, body, len
    lua_pushinteger(L, static_cast<lua_Integer>(packet.clientId));
    lua_pushlstring(L, reinterpret_cast<const char *>(packet.body.data()), packet.body.size());
    lua_pushinteger(L, static_cast<lua_Integer>(packet.body.size()));
    const int nargs = (pushed_self ? 1 : 0) + 3;

    if (lua_pcall(L, nargs, 0, 0) != LUA_OK)
    {
        const char *err = lua_tostring(L, -1);
        KM_LOG_ERROR_L(L, "[dispatch] cb '{}' error: {}", cb.c_str(), err ? err : "(unknown)");
        lua_pop(L, 1);
        call_fallback_dispatch(L, cb, packet);
        return;
    }
}

/*======================================================
 * PollRedis（去掉 traceback 版本）
 *======================================================*/
inline int PollRedis(lua_State *L, int max_calls)
{
    KM *k = getKM(L);
    if (!k)
        return 0;

    int done = 0;
    PendingRedisMsg m;
    while (done < max_calls && g_redis_pending.pop_for(L, m))
    {
        const int top0 = lua_gettop(L);
        const unsigned char *buf = (const unsigned char *)m.payload.data();
        const size_t n = m.payload.size();
        bool dispatched = false;

        if (n >= MIN_FRAME10)
        {
            const uint16_t tmp = load_le16(buf + OFF_PKT_SZ);
            const uint16_t main_cmd = load_le16(buf + OFF_MAIN_CMD);
            const uint16_t sub_cmd = load_le16(buf + OFF_SUB_CMD);
            const uint16_t body_len = load_le16(buf + OFF_BODY_LEN);
            const size_t need = OFF_BODY_LEN + 2 + (size_t)body_len; // 10+body_len
            KM_LOG_ERROR("M={}S={}================", main_cmd, sub_cmd);
            if (n >= need)
            {
                const char *body = (const char *)buf + OFF_BODY_LEN + 2;
                const size_t blen = body_len;
                const uint32_t key = (static_cast<uint32_t>(main_cmd) << 16) |
                                     (static_cast<uint32_t>(sub_cmd) & 0xFFFF);
                auto it = k->proto_cb.find(key);
                if (it != k->proto_cb.end())
                {
                    const std::string &cb = it->second;
                    bool pushed_self = false;
                    if (push_lua_callable(L, cb, pushed_self))
                    {
                        // 压参：clientId(=0), body, len
                        lua_pushinteger(L, 0);
                        lua_pushlstring(L, body, blen);
                        lua_pushinteger(L, (lua_Integer)blen);
                        const int nargs = (pushed_self ? 1 : 0) + 3;
                        if (lua_pcall(L, nargs, 0, 0) != LUA_OK)
                        {
                            const char *err = lua_tostring(L, -1);
                            // KM_LOG_ERROR_L(L, "[redis->proto] cb {} ({}:{}) error: {}",
                            //                cb.c_str(),
                            //                (unsigned)main_cmd, (unsigned)sub_cmd,
                            //                err ? err : "(unknown)");
                            lua_pop(L, 1);
                        }

                        KM_LOG_INFO_L(L, "[redis->proto] dispatched {}:{} via '{}' body_len={}",
                                      (unsigned)main_cmd, (unsigned)sub_cmd,
                                      cb.c_str(), (unsigned)blen);
                        dispatched = true;
                    }
                    else
                    {
                        KM_LOG_WARN_L(L, "[redis->proto] resolve cb '{}' failed for {}:{}",
                                      cb.c_str(), (unsigned)main_cmd, (unsigned)sub_cmd);
                    }
                }
            }
            else
            {
                KM_LOG_WARN_L(L, "[redis->proto] truncated frame: n={} need={}",
                              (unsigned)n, (unsigned)need);
            }
        }
        if (!dispatched)
        {
            // KM_LOG_ERROR("M============================");
            bool pushed_self = false;
            if (!push_lua_callable(L, m.cb, pushed_self))
            {
                KM_LOG_WARN_L(L, "[redis] cb {} not found!!!!!!!!!!!!!!!!!!!!!!!", m.cb.c_str());
                lua_settop(L, top0);
                ++done;
                continue;
            }
            // 压参：channel, payload, len
            lua_pushlstring(L, m.channel.data(), m.channel.size());
            lua_pushlstring(L, m.payload.data(), m.payload.size());
            lua_pushinteger(L, (lua_Integer)m.payload.size());
            const int nargs = (pushed_self ? 1 : 0) + 3;

            if (lua_pcall(L, nargs, 0, 0) != LUA_OK)
            {
                const char *err = lua_tostring(L, -1);
                KM_LOG_ERROR_L(L, "[redis] cb {} error:\n{}",
                               m.cb.c_str(), err ? err : "(unknown)");
                lua_pop(L, 1);
            }
            // KM_LOG_INFO_L(L, "[redis] fallback -> '{}' payload_len={}",
            //               m.cb.c_str(), (unsigned)n);
        }

        lua_settop(L, top0);
        ++done;
    }

    return done;
}