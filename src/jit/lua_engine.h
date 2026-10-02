//
// Created by h on 2025/9/2.
//
#pragma once
#include <string>
#include <vector>
#include <stdexcept>
#include <utility>
// 使用luajit
#include <luajit-2.1/lua.hpp>
class LuaEngine
{
public:
    LuaEngine();
    ~LuaEngine();

    // 禁止拷贝，防止多次析构
    LuaEngine(const LuaEngine &) = delete;
    LuaEngine &operator=(const LuaEngine &) = delete;

    // 移动
    LuaEngine(LuaEngine &&other) noexcept;
    LuaEngine &operator=(LuaEngine &&other) noexcept;

    // 运行脚本
    bool DoString(const std::string &code);
    bool DoFile(const std::string &file);

    // 注册 C 函数
    void Register(const std::string &name, lua_CFunction fn);

    // 调Lua全局函数。需要先将参数压栈后使用
    bool CallPreparedGlobal(const char *funcName, int argCount, int retCount = 0);

    template <typename... Args>
    bool Call(const char *funcName, int retCount, Args &&...args)
    {
        if (!pushGlobalFunction(funcName))
        {
            return false;
        }
        int dummy[] = {0, (push(std::forward<Args>(args)), 0)...};
        (void)dummy;
        return pCall(sizeof...(Args), retCount);
    }

    void AppendPackagePath(const std::vector<std::string> &paths);
    void AppendPackageCPath(const std::vector<std::string> &paths);
    // 全局变量get/set
    void SetGlobal(const char *name, bool v);
    void SetGlobal(const char *name, int64_t v);
    void SetGlobal(const char *name, double v);
    void SetGlobal(const char *name, const std::string &v);

    bool GetGlobalBool(const char *name, bool def = false) const;
    long long GetGlobalInt(const char *name, long long def = 0) const;
    double GetGlobalDouble(const char *name, double def = 0.0) const;
    std::string GetGlobalString(const char *name, const std::string &def = "") const;

    // lua_State*
    lua_State *L() { return lua_state_; }
    const lua_State *L() const { return lua_state_; }

private:
    lua_State *lua_state_;
    // 压入 Lua 栈
    void push(bool v);
    void push(int v);
    void push(long long v);
    void push(double v);
    void push(const char *s);
    void push(const std::string &s);

    int pushErrorHandler(lua_State *L);
    // 压全局函数到栈顶
    bool pushGlobalFunction(const char *funcName);

    // 带 traceback 的受保护调用
    bool pCall(int nargs, int nresults);

    // 压traceback函数；返回其栈索引
    // int pushTracebac();

    // 读取 package.path
    std::string getPackagePath() const;
};

