#include "jit/global_vm.h"
  // 这里需要 ws_session 的完整定义
#include <utility>
#include "jit/lua_thread.hpp" 
#include "lnet/ws_session.hpp" 

bool GlobalVM::start(long idx, const std::string &args, long port)
{
    if (threads_.count(idx)) return false;
    auto th = std::make_shared<LuaVM::ThreadHandle>(
        LuaVM::ThreadHandle::start_worker(args, idx, port)
    );
    th->set_auto_join(true);
    threads_.emplace(idx, std::move(th));
    return true;
}

void GlobalVM::stop(long idx)
{
    auto it = threads_.find(idx);
    if (it == threads_.end()) return;
    it->second->stop();
    it->second->join();
    threads_.erase(it);
}

void GlobalVM::stop_all()
{
    for (auto &kv : threads_) kv.second->stop();
    for (auto &kv : threads_) kv.second->join();
    threads_.clear();
}

int GlobalVM::push_all(const Packet &p)
{
    int sent = 0;
    for (auto &kv : threads_) { kv.second->push(p); ++sent; }
    return sent;
}

bool GlobalVM::push_to(long idx, const Packet &p)
{
    auto it = threads_.find(idx);
    if (it == threads_.end()) return false;
    it->second->push(p);
    return true;
}

bool GlobalVM::running(long idx) { return threads_.count(idx) != 0; }
int  GlobalVM::count()           { return static_cast<int>(threads_.size()); }

void GlobalVM::register_client(int64_t clientId, std::shared_ptr<ws_session> sess)
{
    std::lock_guard<std::mutex> lk(clients_mu_);
    clients_[clientId] = std::move(sess);
}

void GlobalVM::unregister_client(int64_t clientId)
{
    std::lock_guard<std::mutex> lk(clients_mu_);
    clients_.erase(clientId);
}

bool GlobalVM::send_to(int64_t clientId, const void* data, size_t len)
{
    std::shared_ptr<ws_session> s;
    {
        std::lock_guard<std::mutex> lk(clients_mu_);
        auto it = clients_.find(clientId);
        if (it == clients_.end()) return false;
        s = it->second.lock();
    }
    if (!s) return false;
    s->send(std::string(reinterpret_cast<const char*>(data), len));
    return true;
}
bool gv_send_to(int64_t clientId, const void* data, size_t len) {
    return GlobalVM::send_to(clientId, data, len);
}