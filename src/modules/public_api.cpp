// publicapi.cpp
#include <luajit-2.1/lua.hpp>
#include <vector>
#include <string>
#include <chrono>
#include <cstring>
#include <cstdio>

// =============== 平台相关 ===============
#if defined(_WIN32)
#include <winsock2.h>
#include <iphlpapi.h>
#include <ws2tcpip.h>
#pragma comment(lib, "iphlpapi.lib")
#pragma comment(lib, "ws2_32.lib")
#include <windows.h>
#elif defined(__APPLE__)
#include <TargetConditionals.h>
#include <mach/mach_time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netdb.h>
#else
// Linux/Android/其它 *nix
#include <time.h>
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#endif

#ifndef NI_MAXHOST
#define NI_MAXHOST 1025
#endif

// =============== 本机 IP 列表 ===============
#if defined(_WIN32)
static std::vector<std::string> list_local_ips()
{
    std::vector<std::string> ips;
    ULONG flags = GAA_FLAG_INCLUDE_PREFIX;
    ULONG family = AF_UNSPEC;
    ULONG bufLen = 0;
    if (GetAdaptersAddresses(family, flags, NULL, NULL, &bufLen) == ERROR_BUFFER_OVERFLOW)
    {
        std::vector<unsigned char> buf(bufLen);
        IP_ADAPTER_ADDRESSES *addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES *>(buf.data());
        if (GetAdaptersAddresses(family, flags, NULL, addrs, &bufLen) == NO_ERROR)
        {
            for (auto p = addrs; p; p = p->Next)
            {
                for (auto u = p->FirstUnicastAddress; u; u = u->Next)
                {
                    char host[NI_MAXHOST] = {0};
                    if (getnameinfo(u->Address.lpSockaddr,
                                    (socklen_t)u->Address.iSockaddrLength,
                                    host, sizeof(host), NULL, 0, NI_NUMERICHOST) == 0)
                    {
                        ips.emplace_back(host);
                    }
                }
            }
        }
    }
    return ips;
}
#else
static std::vector<std::string> list_local_ips()
{
    std::vector<std::string> ips;
    ifaddrs *ifaddr = nullptr;
    if (getifaddrs(&ifaddr) == -1)
        return ips;

    for (auto p = ifaddr; p; p = p->ifa_next)
    {
        if (!p->ifa_addr)
            continue;
        int fam = p->ifa_addr->sa_family;
        char host[NI_MAXHOST] = {0};
        if (fam == AF_INET)
        {
            inet_ntop(AF_INET, &((sockaddr_in *)p->ifa_addr)->sin_addr, host, sizeof(host));
            ips.emplace_back(host);
        }
        else if (fam == AF_INET6)
        {
            inet_ntop(AF_INET6, &((sockaddr_in6 *)p->ifa_addr)->sin6_addr, host, sizeof(host));
            ips.emplace_back(host);
        }
    }
    freeifaddrs(ifaddr);
    return ips;
}
#endif

// =============== 自开机以来的毫秒数 ===============
static inline long long tick_ms_boot()
{
#if defined(_WIN32)
    return static_cast<long long>(GetTickCount64());
#elif defined(__APPLE__)
    static mach_timebase_info_data_t timebase = {0, 0};
    if (timebase.denom == 0)
        mach_timebase_info(&timebase);

    uint64_t t;
#if defined(MAC_OS_X_VERSION_10_12) && (MAC_OS_X_VERSION_MIN_REQUIRED >= 101200)
    if (&mach_continuous_time != nullptr)
        t = mach_continuous_time();
    else
        t = mach_absolute_time();
#else
    t = mach_absolute_time();
#endif
    long double ns = (long double)t * (long double)timebase.numer / (long double)timebase.denom;
    return static_cast<long long>(ns / 1e6L);
#else
    struct timespec ts{};
#ifdef CLOCK_BOOTTIME
    clock_gettime(CLOCK_BOOTTIME, &ts);
#else
    clock_gettime(CLOCK_MONOTONIC, &ts);
#endif
    return static_cast<long long>(ts.tv_sec) * 1000LL + static_cast<long long>(ts.tv_nsec / 1000000LL);
#endif
}

// =============== 小工具 ===============
static inline long long double_to_int(double d) { return (long long)(d); }
static inline std::string dword_to_ipv4(uint32_t dw)
{
    unsigned char b1 = (dw) & 0xFF;
    unsigned char b2 = (dw >> 8) & 0xFF;
    unsigned char b3 = (dw >> 16) & 0xFF;
    unsigned char b4 = (dw >> 24) & 0xFF;
    char buf[32];
    std::snprintf(buf, sizeof(buf), "%u.%u.%u.%u", b1, b2, b3, b4);
    return std::string(buf);
}

static const char b64_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static std::string to_base64(const unsigned char *data, size_t len)
{
    std::string out;
    out.reserve(((len + 2) / 3) * 4);
    for (size_t i = 0; i < len; i += 3)
    {
        unsigned int a = i < len ? data[i] : 0;
        unsigned int b = i + 1 < len ? data[i + 1] : 0;
        unsigned int c = i + 2 < len ? data[i + 2] : 0;
        unsigned int triple = (a << 16) | (b << 8) | c;
        out.push_back(b64_table[(triple >> 18) & 0x3F]);
        out.push_back(b64_table[(triple >> 12) & 0x3F]);
        out.push_back(i + 1 < len ? b64_table[(triple >> 6) & 0x3F] : '=');
        out.push_back(i + 2 < len ? b64_table[(triple >> 0) & 0x3F] : '=');
    }
    return out;
}

// =============== Buffer userdata ===============
struct Buffer
{
    std::vector<unsigned char> bytes;
};
static const char *MT_BUFFER = "publicapi.buffer";

static Buffer *check_buffer(lua_State *L, int idx)
{
    void *ud = luaL_checkudata(L, idx, MT_BUFFER);
    luaL_argcheck(L, ud != nullptr, idx, "buffer expected");
    return (Buffer *)ud;
}
static int buffer_gc(lua_State *L)
{
    auto *b = (Buffer *)luaL_checkudata(L, 1, MT_BUFFER);
    b->~Buffer();
    return 0;
}
static int buffer_tostring(lua_State *L)
{
    auto *b = check_buffer(L, 1);
    lua_pushlstring(L, (const char *)b->bytes.data(), b->bytes.size());
    return 1;
}
static void ensure_buffer_mt(lua_State *L)
{
    if (luaL_newmetatable(L, MT_BUFFER))
    {
        lua_pushcfunction(L, buffer_gc);
        lua_setfield(L, -2, "__gc");
        lua_pushcfunction(L, buffer_tostring);
        lua_setfield(L, -2, "__tostring");
    }
    lua_pop(L, 1);
}
static int push_new_buffer(lua_State *L, const unsigned char *data, size_t len)
{
    void *ud = lua_newuserdata(L, sizeof(Buffer));
    new (ud) Buffer();
    luaL_getmetatable(L, MT_BUFFER);
    lua_setmetatable(L, -2);
    auto *b = (Buffer *)ud;
    b->bytes.assign(data, data + len);
    return 1;
}

// =============== PAPI userdata ===============
struct PAPI
{
};
static const char *MT_PAPI = "publicapi.class";

// 判断第 1 个参数是否是 PAPI 实例；用于兼容 . / : 调用
static inline bool has_papi_self(lua_State *L)
{
    return (lua_type(L, 1) == LUA_TUSERDATA) && (luaL_testudata(L, 1, MT_PAPI) != nullptr);
}
static inline int argbase(lua_State *L)
{
    // 如果是冒号调用，1 号位是 self，真实参数从 2 开始；否则从 1 开始
    return has_papi_self(L) ? 2 : 1;
}

static int l_papi_new(lua_State *L)
{
    void *ud = lua_newuserdata(L, sizeof(PAPI));
    new (ud) PAPI();
    luaL_getmetatable(L, MT_PAPI);
    lua_setmetatable(L, -2);
    return 1;
}

// PAPI:GetIP()
static int l_GetIP(lua_State *L)
{
    (void)has_papi_self(L); // 仅为对齐，不强制
    auto ips = list_local_ips();
    lua_createtable(L, (int)ips.size(), 0);
    int i = 1;
    for (auto &s : ips)
    {
        lua_pushlstring(L, s.data(), s.size());
        lua_rawseti(L, -2, i++);
    }
    return 1;
}

// PAPI:Double2Int(d)
static int l_Double2Int(lua_State *L)
{
    int ab = argbase(L);
    double d = luaL_checknumber(L, ab + 0);
    lua_pushinteger(L, (lua_Integer)double_to_int(d));
    return 1;
}

// PAPI:Dword2String(dw)
static int l_Dword2String(lua_State *L)
{
    int ab = argbase(L);
    unsigned long long v = (unsigned long long)luaL_checkinteger(L, ab + 0);
    uint32_t dw = (uint32_t)v;
    auto s = dword_to_ipv4(dw);
    lua_pushlstring(L, s.data(), s.size());
    return 1;
}

// PAPI:LuaGetTickCount()  —— 自开机以来毫秒
static int l_LuaGetTickCount(lua_State *L)
{
    (void)has_papi_self(L);
    lua_pushinteger(L, (lua_Integer)tick_ms_boot());
    return 1;
}

// PAPI:udataToStr(buf_or_str[, len])
static int l_udataToStr(lua_State *L)
{
    int ab = argbase(L);
    const unsigned char *data = nullptr;
    size_t len = 0;

    if (luaL_testudata(L, ab + 0, MT_BUFFER))
    {
        auto *b = check_buffer(L, ab + 0);
        data = b->bytes.data();
        len = b->bytes.size();
    }
    else
    {
        const char *s = luaL_checklstring(L, ab + 0, &len);
        data = (const unsigned char *)s;
    }
    if (lua_gettop(L) >= ab + 1 && lua_isnumber(L, ab + 1))
    {
        size_t want = (size_t)lua_tointeger(L, ab + 1);
        if (want < len)
            len = want;
    }
    lua_pushlstring(L, (const char *)data, len);
    return 1;
}

// PAPI:StrToudata(str) -> buffer_ud
static int l_StrToudata(lua_State *L)
{
    int ab = argbase(L);
    size_t l = 0;
    const char *s = luaL_checklstring(L, ab + 0, &l);
    return push_new_buffer(L, (const unsigned char *)s, l);
}

// PAPI:objToBase64(buf_or_str[, len])
static int l_objToBase64(lua_State *L)
{
    int ab = argbase(L);
    const unsigned char *data = nullptr;
    size_t len = 0;

    if (luaL_testudata(L, ab + 0, MT_BUFFER))
    {
        auto *b = check_buffer(L, ab + 0);
        data = b->bytes.data();
        len = b->bytes.size();
    }
    else
    {
        const char *s = luaL_checklstring(L, ab + 0, &len);
        data = (const unsigned char *)s;
    }
    if (lua_gettop(L) >= ab + 1 && lua_isnumber(L, ab + 1))
    {
        size_t want = (size_t)lua_tointeger(L, ab + 1);
        if (want < len)
            len = want;
    }
    auto b64 = to_base64(data, len);
    lua_pushlstring(L, b64.data(), b64.size());
    return 1;
}

static int papi_gc(lua_State *L)
{
    auto *p = (PAPI *)luaL_checkudata(L, 1, MT_PAPI);
    p->~PAPI();
    return 0;
}

static void ensure_papi_mt(lua_State *L)
{
    if (luaL_newmetatable(L, MT_PAPI))
    {
        // __index = methods
        lua_newtable(L);
        lua_pushcfunction(L, l_GetIP);
        lua_setfield(L, -2, "GetIP");
        lua_pushcfunction(L, l_Double2Int);
        lua_setfield(L, -2, "Double2Int");
        lua_pushcfunction(L, l_Dword2String);
        lua_setfield(L, -2, "Dword2String");
        lua_pushcfunction(L, l_LuaGetTickCount);
        lua_setfield(L, -2, "LuaGetTickCount");
        lua_pushcfunction(L, l_udataToStr);
        lua_setfield(L, -2, "udataToStr");
        lua_pushcfunction(L, l_StrToudata);
        lua_setfield(L, -2, "StrToudata");
        lua_pushcfunction(L, l_objToBase64);
        lua_setfield(L, -2, "objToBase64");
        lua_setfield(L, -2, "__index");

        lua_pushcfunction(L, papi_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

static void export_global(lua_State *L)
{
    const char *gname = "PAPI_A178350C2F44461DB18C9DAD18D78121";
    lua_newtable(L); // 类表
    lua_pushcfunction(L, l_papi_new);
    lua_setfield(L, -2, "new");
    lua_setglobal(L, gname); // _G[gname] = 类表
}

// 给 Lua 注入：PAPI_A178350C2F44461DB18C9DAD18D78121
int luaopen_publicapi(lua_State *L)
{
    ensure_buffer_mt(L);
    ensure_papi_mt(L);
    export_global(L);

    // 兼容 Lua 5.1/5.2+/LuaJIT：同时保证 _G.unpack 与 table.unpack 都可用
    {
        // 先取出全局 unpack 和 table.unpack（如果有）
        bool has_g_unpack = false;
        bool has_tbl_unpack = false;

        // 取 _G.unpack
        lua_getglobal(L, "unpack"); // [.., g_unpack?]
        has_g_unpack = !lua_isnil(L, -1);

        // 取 table.unpack
        lua_getglobal(L, "table"); // [.., g_unpack?, table]
        if (lua_istable(L, -1))
        {
            lua_getfield(L, -1, "unpack"); // [.., g_unpack?, table, tbl_unpack?]
            has_tbl_unpack = !lua_isnil(L, -1);
            lua_pop(L, 1); // 弹出 tbl_unpack?
        }
        // 此时栈顶是 table（或不是 table 时是其他值）
        // 把它先保存一份标记，再决定如何写回
        int table_on_stack = lua_istable(L, -1);
        // 弹掉 table / 非 table 值
        lua_pop(L, 1);

        // 如果 _G.unpack 不存在但 table.unpack 存在：_G.unpack = table.unpack
        if (!has_g_unpack && has_tbl_unpack)
        {
            lua_getglobal(L, "table");     // [.., table]
            lua_getfield(L, -1, "unpack"); // [.., table, tbl_unpack]
            lua_setglobal(L, "unpack");    // _G.unpack = tbl_unpack, 栈变为 [.., table]
            lua_pop(L, 1);                 // 弹掉 table
        }
        // 如果 table.unpack 不存在但 _G.unpack 存在：table.unpack = _G.unpack
        else if (has_g_unpack && !has_tbl_unpack)
        {
            lua_getglobal(L, "table"); // [.., table]
            if (lua_istable(L, -1))
            {
                lua_getglobal(L, "unpack");    // [.., table, g_unpack]
                lua_setfield(L, -2, "unpack"); // table.unpack = g_unpack, 栈仍为 [.., table]
            }
            lua_pop(L, 1); // 弹掉 table（或非 table 值）
        }
        else
        {
            // 两边都有或两边都没有：都不用补，什么也不做
            // （两边都没有时，说明运行时本来就没有提供 unpack，保持原样）
        }

        // 清理最初取的 g_unpack
        lua_getglobal(L, "unpack"); // 再取一次只是为了保持逻辑对称，这里直接弹掉即可
        lua_pop(L, 1);
    }
    {
        lua_pop(L, 1);
    }

    // 返回模块表（可选导出）
    lua_newtable(L);
    lua_getglobal(L, "PAPI_A178350C2F44461DB18C9DAD18D78121");
    lua_setfield(L, -2, "PAPI");
    return 1;
}