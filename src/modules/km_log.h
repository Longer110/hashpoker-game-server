#pragma once
#include <string>
#include <memory>
#include <spdlog/spdlog.h>

// 轻量封装：异步 + 控制台 + 每日文件保留7天
namespace km_log
{

    // 第一次用前调用（或在 luaopen 时）
    void init_once();
    void set_path(const std::string &path, const std::string &file); // 动态切换路径/文件
    void shutdown();
    std::shared_ptr<spdlog::logger> get(); //
    struct LuaVMTag
    {
    };
    using VMKey = const void *;
    void set_path_for(VMKey vm, const std::string &path, const std::string &file, const std::string &tag = "");
    std::shared_ptr<spdlog::logger> get_for(VMKey vm);
    void drop_for(VMKey vm);

// 便捷宏
#define KM_LOG_TRACE(...) SPDLOG_TRACE(__VA_ARGS__)
#define KM_LOG_DEBUG(...) SPDLOG_DEBUG(__VA_ARGS__)
#define KM_LOG_INFO(...) SPDLOG_INFO(__VA_ARGS__)
#define KM_LOG_WARN(...) SPDLOG_WARN(__VA_ARGS__)
#define KM_LOG_ERROR(...) SPDLOG_ERROR(__VA_ARGS__)
#define KM_LOG_CRITICAL(...) SPDLOG_CRITICAL(__VA_ARGS__)

#define KM_LOG_TRACE_L(L, ...) km_log::get_for((km_log::VMKey)(L))->trace(__VA_ARGS__)
#define KM_LOG_DEBUG_L(L, ...) km_log::get_for((km_log::VMKey)(L))->debug(__VA_ARGS__)
#define KM_LOG_INFO_L(L, ...) km_log::get_for((km_log::VMKey)(L))->info(__VA_ARGS__)
#define KM_LOG_WARN_L(L, ...) km_log::get_for((km_log::VMKey)(L))->warn(__VA_ARGS__)
#define KM_LOG_ERROR_L(L, ...) km_log::get_for((km_log::VMKey)(L))->error(__VA_ARGS__)
#define KM_LOG_CRITICAL_L(L, ...) km_log::get_for((km_log::VMKey)(L))->critical(__VA_ARGS__)
} // namespace km_log
