#include "lua_engine.h"
#include <iostream>
#include "modules/kmbridge_stub.hpp"

namespace
{
    void LoadStdLibs(lua_State *L)
    {
        luaL_openlibs(L);
    }
}

// —— 完整 traceback
static int CErrorHandler(lua_State *L)
{
    const char *msg = nullptr;
    if (lua_isstring(L, 1))
    {
        msg = lua_tostring(L, 1);
    }
    else
    {
        // 尝试 tostring(err)
        lua_getglobal(L, "tostring");
        lua_pushvalue(L, 1);
        if (lua_pcall(L, 1, 1, 0) == LUA_OK && lua_isstring(L, -1))
        {
            msg = lua_tostring(L, -1);
            lua_pop(L, 1);
        }
        if (!msg)
            msg = "(non-string error)";
    }
    luaL_traceback(L, L, msg, 1);
    return 1;
}

static void DumpLuaStack(lua_State *L, const char *tag)
{
    int top = lua_gettop(L);
    std::cerr << "[Lua] StackDump(" << (tag ? tag : "") << ") size=" << top << "\n";
    for (int i = 1; i <= top; ++i)
    {
        int t = lua_type(L, i);
        std::cerr << "  [" << i << "] " << lua_typename(L, t) << "  ";
        switch (t)
        {
        case LUA_TSTRING:
            std::cerr << "\"" << lua_tostring(L, i) << "\"";
            break;
        case LUA_TBOOLEAN:
            std::cerr << (lua_toboolean(L, i) ? "true" : "false");
            break;
        case LUA_TNUMBER:
#if LUA_VERSION_NUM >= 503
            if (lua_isinteger(L, i))
                std::cerr << lua_tointeger(L, i);
            else
                std::cerr << lua_tonumber(L, i);
#else
            std::cerr << lua_tonumber(L, i);
#endif
            break;
        case LUA_TFUNCTION:
            std::cerr << "(function)";
            break;
        case LUA_TTABLE:
            std::cerr << "(table)";
            break;
        case LUA_TUSERDATA:
            std::cerr << "(userdata)";
            break;
        case LUA_TTHREAD:
            std::cerr << "(thread)";
            break;
        case LUA_TLIGHTUSERDATA:
            std::cerr << "(lightuserdata)";
            break;
        default:
            break;
        }
        std::cerr << "\n";
    }
}

// ---------- 构造 / 析构 / 移动 ----------
LuaEngine::LuaEngine() : lua_state_(NULL)
{
    lua_state_ = luaL_newstate();
    if (!lua_state_)
    {
        throw std::runtime_error("luaL_newstate failed");
    }
    // 加载std库等
    LoadStdLibs(lua_state_);
}

LuaEngine::~LuaEngine()
{
    if (lua_state_)
    {
        lua_close(lua_state_);
        lua_state_ = NULL;
    }
}

LuaEngine::LuaEngine(LuaEngine &&other) noexcept : lua_state_(other.lua_state_)
{
    other.lua_state_ = NULL;
}

LuaEngine &LuaEngine::operator=(LuaEngine &&other) noexcept
{
    if (this != &other)
    {
        if (lua_state_)
            lua_close(lua_state_);
        lua_state_ = other.lua_state_;
        other.lua_state_ = NULL;
    }
    return *this;
}

// ---------- 执行脚本 ----------
bool LuaEngine::DoString(const std::string &code)
{
    int msgh = pushErrorHandler(lua_state_);
    int err = luaL_loadbuffer(lua_state_, code.data(), code.size(), "DoString");
    if (err == LUA_OK)
        err = lua_pcall(lua_state_, 0, 0, msgh);

    if (err != LUA_OK)
    {
        const char *e = lua_tostring(lua_state_, -1);
        std::cerr << "[Lua] DoString error:\n"
                  << (e ? e : "(unknown)") << "\n";
        DumpLuaStack(lua_state_, "DoString-error"); // 可选
        lua_pop(lua_state_, 1);
        lua_remove(lua_state_, msgh);
        return false;
    }
    lua_remove(lua_state_, msgh);
    return true;
}

bool LuaEngine::DoFile(const std::string &file)
{
    int msgh = pushErrorHandler(lua_state_);
    int err = luaL_loadfile(lua_state_, file.c_str());
    if (err == LUA_OK)
        err = lua_pcall(lua_state_, 0, 0, msgh);

    if (err != LUA_OK)
    {
        const char *e = lua_tostring(lua_state_, -1);
        std::cerr << "[Lua] DoFile error:\n"
                  << (e ? e : "(unknown)") << "\n";
        DumpLuaStack(lua_state_, "DoFile-error"); // 可选
        lua_pop(lua_state_, 1);
        lua_remove(lua_state_, msgh);
        return false;
    }
    lua_remove(lua_state_, msgh);
    return true;
}

// ---------- 注册 C 函数 ----------
void LuaEngine::Register(const std::string &name, lua_CFunction fn)
{
    lua_register(lua_state_, name.c_str(), fn);
}

// ---------- 调用 Lua 函数 ----------
bool LuaEngine::pushGlobalFunction(const char *funcName)
{
    // 取函数，到栈顶
    lua_getglobal(lua_state_, funcName);
    // 栈顶不是函数
    if (!lua_isfunction(lua_state_, -1))
    {
        lua_pop(lua_state_, 1);
        std::cerr << "[Lua] function not found: " << (funcName ? funcName : "(null)") << "\n";
        return false;
    }
    return true;
}

bool LuaEngine::CallPreparedGlobal(const char *funcName, int argCount, int retCount)
{
    lua_getglobal(lua_state_, funcName);
    if (!lua_isfunction(lua_state_, -1))
    {
        lua_pop(lua_state_, 1);
        std::cerr << "[Lua] function not found: " << (funcName ? funcName : "(null)") << "\n";
        if (argCount > 0)
            lua_pop(lua_state_, argCount);
        return false;
    }
    if (argCount > 0)
    {
        lua_insert(lua_state_, -1 - argCount); // 函数移到参数前
    }
    return pCall(argCount, retCount);
}
// 打印lua堆栈如果有可能
// int LuaEngine::pushTracebac()
// {
//     lua_getglobal(lua_state_, "debug");
//     if (!lua_istable(lua_state_, -1))
//     {
//         lua_pop(lua_state_, 1);
//         lua_pushnil(lua_state_);
//         return lua_gettop(lua_state_);
//     }
//     lua_getfield(lua_state_, -1, "traceback");
//     lua_remove(lua_state_, -2); // 移除 debug 表
//     if (!lua_isfunction(lua_state_, -1))
//     {
//         lua_pop(lua_state_, 1);
//         lua_pushnil(lua_state_);
//     }
//     return lua_gettop(lua_state_);
// }

int LuaEngine::pushErrorHandler(lua_State *L)
{
    lua_pushcfunction(L, CErrorHandler);
    return lua_gettop(L);
}
bool LuaEngine::pCall(int nargs, int nresults)
{
    // 栈： [..., func, arg1, ..., argN]
    int top_before = lua_gettop(lua_state_);
    int msgh = pushErrorHandler(lua_state_); // [..., func, args..., msgh]
    int func_index = top_before - nargs;     // 压 msgh 之前 func 的位置
    lua_insert(lua_state_, func_index);      // [..., msgh, func, args...]

    int rc = lua_pcall(lua_state_, nargs, nresults, func_index);

    lua_remove(lua_state_, func_index); // 移除 msgh

    if (rc != LUA_OK)
    {
        const char *err = lua_tostring(lua_state_, -1);
        std::cerr << "[Lua] pcall error:\n"
                  << (err ? err : "(unknown)") << "\n";
        DumpLuaStack(lua_state_, "after-error"); // 可选
        lua_pop(lua_state_, 1);
        return false;
    }
    return true;
}

// ---------- 压栈 ----------
void LuaEngine::push(bool v)
{
    lua_pushboolean(lua_state_, v);
}
void LuaEngine::push(int v)
{
    lua_pushinteger(lua_state_, v);
}
void LuaEngine::push(long long v)
{
    lua_pushinteger(lua_state_, (lua_Integer)v);
}
void LuaEngine::push(double v)
{
    lua_pushnumber(lua_state_, v);
}
void LuaEngine::push(const char *s)
{
    lua_pushstring(lua_state_, s ? s : "");
}
void LuaEngine::push(const std::string &s)
{
    lua_pushlstring(lua_state_, s.data(), s.size());
}

//
std::string LuaEngine::getPackagePath() const
{
    lua_getglobal(lua_state_, "package");
    lua_getfield(lua_state_, -1, "path");
    const char *p = lua_tostring(lua_state_, -1);
    std::string cur = p ? p : "";
    lua_pop(lua_state_, 2);
    return cur;
}

void LuaEngine::AppendPackageCPath(const std::vector<std::string> &paths)
{
    // 先取当前的 cpath
    lua_getglobal(lua_state_, "package");
    lua_getfield(lua_state_, -1, "cpath");
    std::string cur = lua_tostring(lua_state_, -1) ? lua_tostring(lua_state_, -1) : "";
    lua_pop(lua_state_, 1); // 弹出旧的 cpath

    // 追加
    for (size_t i = 0; i < paths.size(); ++i)
    {
        if (!cur.empty() && cur.back() != ';')
            cur += ';';
        cur += paths[i];
    }

    // 设置回去
    lua_pushlstring(lua_state_, cur.data(), cur.size());
    lua_setfield(lua_state_, -2, "cpath");
    lua_pop(lua_state_, 1); // 弹出 package
}
void LuaEngine::AppendPackagePath(const std::vector<std::string> &paths)
{
    std::string cur = getPackagePath();
    for (size_t i = 0; i < paths.size(); ++i)
    {
        if (!cur.empty() && cur[cur.size() - 1] != ';')
            cur += ';';
        cur += paths[i];
    }
    lua_getglobal(lua_state_, "package");
    lua_pushlstring(lua_state_, cur.data(), cur.size());
    lua_setfield(lua_state_, -2, "path");
    lua_pop(lua_state_, 1);
}

//
void LuaEngine::SetGlobal(const char *name, bool v)
{
    lua_pushboolean(lua_state_, v);
    lua_setglobal(lua_state_, name);
}
void LuaEngine::SetGlobal(const char *name, int64_t v)
{
    lua_pushinteger(lua_state_, (lua_Integer)v);
    lua_setglobal(lua_state_, name);
}
void LuaEngine::SetGlobal(const char *name, double v)
{
    lua_pushnumber(lua_state_, v);
    lua_setglobal(lua_state_, name);
}
void LuaEngine::SetGlobal(const char *name, const std::string &v)
{
    lua_pushlstring(lua_state_, v.data(), v.size());
    lua_setglobal(lua_state_, name);
}

bool LuaEngine::GetGlobalBool(const char *name, bool def) const
{
    lua_getglobal(lua_state_, name);
    bool ret = lua_isboolean(lua_state_, -1) ? (lua_toboolean(lua_state_, -1) != 0) : def;
    lua_pop(lua_state_, 1);
    return ret;
}

long long LuaEngine::GetGlobalInt(const char *name, long long def) const
{
    lua_getglobal(lua_state_, name);
#if LUA_VERSION_NUM >= 503
    int isnum = 0;
    lua_Integer v = lua_tointegerx(lua_state_, -1, &isnum);
    long long ret = isnum ? (long long)v : def;
#else
    long long ret = lua_isnumber(lua_state_, -1)
                        ? (long long)lua_tointeger(lua_state_, -1)
                        : def;
#endif
    lua_pop(lua_state_, 1);
    return ret;
}

double LuaEngine::GetGlobalDouble(const char *name, double def) const
{
    lua_getglobal(lua_state_, name);
    double ret = lua_isnumber(lua_state_, -1) ? lua_tonumber(lua_state_, -1) : def;
    lua_pop(lua_state_, 1);
    return ret;
}

std::string LuaEngine::GetGlobalString(const char *name, const std::string &def) const
{
    lua_getglobal(lua_state_, name);
    const char *s = lua_tostring(lua_state_, -1);
    std::string ret = s ? s : def;
    lua_pop(lua_state_, 1);
    return ret;
}