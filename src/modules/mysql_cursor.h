#pragma once

#include <vector>
#include <string>
#include <cstring>
#include <luajit-2.1/lua.hpp>
#include "mysql_lua.h"

static const char *MT_MYSQL_CUR = "mysql.cursor.meta";

// 游标
struct LuaCursor
{
    MySQLHandle *h = nullptr;      // 归属连接
    MYSQL_RES *res = nullptr;      // 结果集
    std::vector<std::string> cols; // 列名缓存
};

// 取游标
static inline LuaCursor **checkCur(lua_State *L, int idx)
{
    return (LuaCursor **)luaL_checkudata(L, idx, MT_MYSQL_CUR);
}

// 关闭/GC
static inline int cur_close(lua_State *L)
{
    auto pp = checkCur(L, 1);
    if (pp && *pp)
    {
        if ((*pp)->res)
        {
            mysql_free_result((*pp)->res);
            (*pp)->res = nullptr;
        }
        delete *pp;
        *pp = nullptr;
        std::cout << "cur_close closed[gc]" << std::endl;
    }
    return 0;
}
static inline int cur_gc(lua_State *L)
{
    return cur_close(L);
}

static inline int cur_fetch(lua_State *L)
{
    auto pp = checkCur(L, 1);
    if (!pp || !*pp || !(*pp)->res)
    {
        lua_pushnil(L);
        return 1;
    }

    MYSQL_RES *res = (*pp)->res;
    MYSQL_ROW row = mysql_fetch_row(res);
    if (!row)
    {
        lua_pushnil(L);
        return 1;
    }

    unsigned int n = mysql_num_fields(res);
    unsigned long *lens = mysql_fetch_lengths(res);
    bool reuse = (lua_type(L, 2) == LUA_TTABLE);
    const char *mode = luaL_optstring(L, 3, "n"); // "a"=assoc, "n"=numeric
    if (!reuse)
        lua_newtable(L); // 新建
    else
        lua_pushvalue(L, 2); // 复用

    if (mode[0] == 'a')
    {
        // 关联键
        for (unsigned int i = 0; i < n; i++)
        {
            const char *k = (*pp)->cols[i].c_str();
            if (row[i])
                lua_pushlstring(L, row[i], lens ? lens[i] : std::strlen(row[i]));
            else
                lua_pushnil(L);
            lua_setfield(L, -2, k);
        }
    }
    else
    {
        for (unsigned int i = 0; i < n; i++)
        {
            lua_pushinteger(L, (lua_Integer)(i + 1));
            if (row[i])
                lua_pushlstring(L, row[i], lens ? lens[i] : std::strlen(row[i]));
            else
                lua_pushnil(L);
            lua_settable(L, -3);
        }
    }
    return 1;
}

// 创建并压栈一个cursor
static inline int push_cursor(lua_State *L, MySQLHandle *h, MYSQL_RES *res)
{
    auto ud = (LuaCursor **)lua_newuserdata(L, sizeof(LuaCursor *));
    *ud = new LuaCursor();
    (*ud)->h = h;
    (*ud)->res = res;
    // 列名缓存（用于 "a" 模式）
    unsigned int n = mysql_num_fields(res);
    MYSQL_FIELD *f = mysql_fetch_fields(res);
    (*ud)->cols.resize(n);
    for (unsigned int i = 0; i < n; i++)
    {
        (*ud)->cols[i] = f[i].name ? f[i].name : "";
    }

    luaL_getmetatable(L, MT_MYSQL_CUR);
    lua_setmetatable(L, -2);
    return 1;
}

// connection:nextres()
static inline int myc_nextres_impl(MySQLHandle **pp, lua_State *L)
{
    if (!pp || !*pp || !(*pp)->conn)
    {
        lua_pushinteger(L, 0);
        return 1;
    }
    MySQLHandle *h = *pp;
    // 跳过没有结果集的
    while (mysql_more_results(h->conn))
    {
        int rc = mysql_next_result(h->conn);
        if (rc > 0)
        {
            lua_pushnil(L);
            lua_pushstring(L, mysql_error(h->conn));
            return 2;
        }
        MYSQL_RES *res = mysql_store_result(h->conn);
        if (res)
            return push_cursor(L, h, res); // => cursor
    }
    lua_pushinteger(L, 0); // 无更多结果
    return 1;
}

// 注册cursor
static inline void push_mysql_cur(lua_State *L)
{
    if (luaL_newmetatable(L, MT_MYSQL_CUR))
    {
        lua_newtable(L);
        lua_pushcfunction(L, cur_fetch);
        lua_setfield(L, -2, "fetch");
        lua_pushcfunction(L, cur_close);
        lua_setfield(L, -2, "close");
        lua_pushvalue(L, -1);
        lua_setfield(L, -3, "__index");
        lua_pushcfunction(L, cur_gc);
        lua_setfield(L, -3, "__gc");
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
}
