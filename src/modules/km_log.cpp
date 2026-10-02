#include "km_log.h"
#include <vector>
#include <filesystem>
#include <mutex>
#include <unordered_map>
#include <iomanip>
#include <sstream>
#include <iostream>
#include <spdlog/async.h>
#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/sinks/daily_file_sink.h>

namespace km_log
{

    static std::string g_path;
    static std::string g_file;
    static bool g_inited = false;

    static std::mutex g_mu;
    static std::unordered_map<VMKey, std::shared_ptr<spdlog::logger>> g_vm_loggers;
    static std::shared_ptr<spdlog::sinks::stdout_color_sink_mt> g_console_sink; // 共享控制台 sink

    static std::string hex_ptr(VMKey p)
    {
        std::ostringstream oss;
        oss << std::hex << std::nouppercase << (uintptr_t)p;
        return oss.str();
    }

    static std::string with_suffix(const std::string &base, const std::string &suffix)
    {
        auto pos = base.find_last_of('.');
        if (pos == std::string::npos)
            return base + suffix;
        return base.substr(0, pos) + suffix + base.substr(pos);
    }

    static void ensure_pool()
    {
        if (!spdlog::thread_pool())
            spdlog::init_thread_pool(16384, 2);
        if (!g_console_sink)
        {
            g_console_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
            g_console_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%^%l%$] %v");
        }
    }

    static void recreate_default_unlocked()
    {
        ensure_pool();
        spdlog::drop("kmbridge");
        std::vector<spdlog::sink_ptr> sinks{g_console_sink};

        if (!g_path.empty() && !g_file.empty())
        {
            try
            {
                std::error_code ec;
                std::filesystem::create_directories(g_path, ec);
                const auto full = (std::filesystem::path(g_path) / g_file).lexically_normal().string();
                auto file_sink = std::make_shared<spdlog::sinks::daily_file_sink_mt>(full, 0, 0, false, 7);
                file_sink->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
                sinks.push_back(file_sink);
                std::cerr << "[km_log] default file -> " << std::filesystem::absolute(full).string() << "\n";
            }
            catch (const spdlog::spdlog_ex &ex)
            {
                std::cerr << "[km_log] default file sink failed: " << ex.what() << "\n";
            }
        }
        else
        {
            std::cerr << "[km_log] default file sink disabled\n";
        }

        auto logger = std::make_shared<spdlog::async_logger>(
            "kmbridge", sinks.begin(), sinks.end(), spdlog::thread_pool(),
            spdlog::async_overflow_policy::block);
        spdlog::register_logger(logger);
        spdlog::set_default_logger(logger);
        spdlog::set_level(spdlog::level::debug);
        spdlog::flush_on(spdlog::level::info);
    }

    void init_once()
    {
        std::lock_guard<std::mutex> lk(g_mu);
        if (g_inited)
            return;
        g_inited = true;
        recreate_default_unlocked();
        static bool registered = false;
        if (!registered)
        {
            registered = true;
            std::atexit([]
                        { km_log::shutdown(); });
        }
    }

    void set_path(const std::string &path, const std::string &file)
    {
        std::lock_guard<std::mutex> lk(g_mu);
        g_path = path;
        g_file = file;
        recreate_default_unlocked();
    }

    std::shared_ptr<spdlog::logger> get()
    {
        init_once();
        return spdlog::default_logger();
    }

    //
    void set_path_for(VMKey vm, const std::string &path, const std::string &file, const std::string &tag)
    {
        std::lock_guard<std::mutex> lk(g_mu);
        ensure_pool();
        std::error_code ec;
        std::filesystem::create_directories(path, ec);
        const auto full = (std::filesystem::path(path) / file).lexically_normal().string();
        // 共享 console/独立文件
        std::vector<spdlog::sink_ptr> sinks{g_console_sink};
        try
        {
            auto fs = std::make_shared<spdlog::sinks::daily_file_sink_mt>(full, 0, 0, false, 7);
            fs->set_pattern("[%Y-%m-%d %H:%M:%S.%e] [%l] %v");
            sinks.push_back(fs);
        }
        catch (const spdlog::spdlog_ex &ex)
        {
            std::cerr << "[km_log] vm file sink failed: " << ex.what() << "\n";
        }
        const std::string lname = "kmbridge-" + hex_ptr(vm);
        spdlog::drop(lname); 
        auto logger = std::make_shared<spdlog::async_logger>(
            lname, sinks.begin(), sinks.end(), spdlog::thread_pool(),
            spdlog::async_overflow_policy::block);
        spdlog::register_logger(logger);
        logger->set_level(spdlog::level::debug);
        logger->flush_on(spdlog::level::info);
        g_vm_loggers[vm] = logger;

        std::cerr << "[km_log] vm logger -> " << lname << " file=" << std::filesystem::absolute(full).string() << "\n";
    }

    std::shared_ptr<spdlog::logger> get_for(VMKey vm)
    {
        init_once();
        std::lock_guard<std::mutex> lk(g_mu);
        auto it = g_vm_loggers.find(vm);
        if (it != g_vm_loggers.end())
            return it->second;
        return spdlog::default_logger(); // 回退
    }

    void drop_for(VMKey vm)
    {
        std::lock_guard<std::mutex> lk(g_mu);
        const std::string lname = "kmbridge-" + hex_ptr(vm);
        g_vm_loggers.erase(vm);
        spdlog::drop(lname);
    }

    void shutdown()
    {
        std::lock_guard<std::mutex> lk(g_mu);
        if (g_inited)
        {
            g_vm_loggers.clear();
            spdlog::shutdown();
            g_inited = false;
        }
    }

}
