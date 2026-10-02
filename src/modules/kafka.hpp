// kafka_lua.cpp
// 线程安全的 LuaJIT Kafka 消费模块：
// 后台线程只拉取消息入队；Lua 回调在主线程 PollKafka 中执行。
#include <luajit-2.1/lua.hpp>
#include <librdkafka/rdkafka.h>

#include <thread>
#include <atomic>
#include <vector>
#include <string>
#include <deque>
#include <mutex>
#include <iostream>
#include <cstring>

// ====== 全局状态（单 VM 版本） ======
static rd_kafka_t *g_consumer = nullptr;
static std::thread g_poll_thread;
static std::atomic<bool> g_running(false);

// Lua 回调函数引用（registry 上）
// static int g_consumer_cb_ref = LUA_NOREF;
static bool isruning = false;
// ====== 线程安全队列：后台线程入队，主线程出队并回调 Lua ======
struct KafkaMsg
{
    std::string topic;
    int32_t partition = 0;
    int64_t offset = 0;
    std::string value;
};

static std::mutex g_q_mu;
static std::deque<KafkaMsg> g_q;

static void q_push(KafkaMsg m)
{
    std::lock_guard<std::mutex> lk(g_q_mu);
    g_q.emplace_back(std::move(m));
}

static bool q_pop(KafkaMsg &out)
{
    std::lock_guard<std::mutex> lk(g_q_mu);
    if (g_q.empty())
        return false;
    out = std::move(g_q.front());
    g_q.pop_front();
    return true;
}

static void q_clear()
{
    std::lock_guard<std::mutex> lk(g_q_mu);
    g_q.clear();
}

// ====== 后台消费线程：只操作 librdkafka，不碰 Lua ======
static void poll_loop()
{
    // std::cerr << "[Kafka][DBG] poll_loop started\n";
    while (g_running.load(std::memory_order_relaxed))
    {
        rd_kafka_message_t *msg = rd_kafka_consumer_poll(g_consumer, 500);
        if (!msg)
            continue;

        if (!msg->err)
        {
            KafkaMsg m;
            m.topic = rd_kafka_topic_name(msg->rkt);
            m.partition = msg->partition;
            m.offset = msg->offset;
            if (msg->payload && msg->len > 0)
                m.value.assign(static_cast<const char *>(msg->payload), static_cast<size_t>(msg->len));
            std::cerr << "[Kafka][DBG] recv msg topic=" << m.topic<< "\n";
            //  << " part=" << m.partition << " off=" << m.offset
            //  << " len=" << m.value.size() << "\n";
            q_push(std::move(m));
        }
        else if (msg->err != RD_KAFKA_RESP_ERR__PARTITION_EOF)
        {
            std::cerr << "[Kafka][ERR] consumer error: " << rd_kafka_message_errstr(msg)
                      << " (code=" << msg->err << ")\n";
        }
        rd_kafka_message_destroy(msg);
    }
    // std::cerr << "[Kafka][DBG] poll_loop exited\n";
}

// ====== Lua 导出：init({brokers, group, topics={...}, config={k=v,...}}) ======
static int l_kafka_init(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TTABLE);

    if (g_consumer)
    {
        // std::cerr << "[Kafka][DBG] init called but already initialized\n";
        //  已经初始化过：直接成功返回（幂等）
        lua_pushboolean(L, 1);
        return 1;
    }

    const char *brokers = nullptr;
    const char *group = nullptr;
    std::vector<std::string> topics;
    // std::cerr << "[Kafka][DBG] init() begin\n";
    //  读取 brokers
    lua_getfield(L, 1, "brokers");
    if (lua_isstring(L, -1))
        brokers = lua_tostring(L, -1);
    lua_pop(L, 1);

    // 读取 group
    lua_getfield(L, 1, "group");
    if (lua_isstring(L, -1))
        group = lua_tostring(L, -1);
    lua_pop(L, 1);

    // 读取 topics
    lua_getfield(L, 1, "topics");
    if (lua_istable(L, -1))
    {
        size_t len = lua_objlen(L, -1);
        for (size_t i = 1; i <= len; ++i)
        {
            lua_rawgeti(L, -1, (int)i);
            if (lua_isstring(L, -1))
                topics.emplace_back(lua_tostring(L, -1));
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);

    if (!brokers || !group || topics.empty())
    {
        // std::cerr << "[Kafka][ERR] init missing fields: brokers=" << (brokers ? brokers : "(null)")
        //  << " group=" << (group ? group : "(null)")
        //  << " topics_size=" << topics.size() << "\n";
        lua_pushnil(L);
        lua_pushstring(L, "brokers/group/topics required");
        return 2;
    }
    // std::cerr << "[Kafka][DBG] brokers=" << brokers << " group=" << group
    //  << " topics=";
    // for (auto &t: topics) {
    //     //std::cerr << t << " ";
    // }
    // std::cerr << "\n";
    // 新建 conf
    char errstr[512];
    rd_kafka_conf_t *conf = rd_kafka_conf_new();

    // 基础配置
    if (rd_kafka_conf_set(conf, "bootstrap.servers", brokers, errstr, sizeof(errstr)) != RD_KAFKA_CONF_OK)
    {
        rd_kafka_conf_destroy(conf);
        lua_pushnil(L);
        lua_pushstring(L, errstr);
        return 2;
    }
    if (rd_kafka_conf_set(conf, "group.id", group, errstr, sizeof(errstr)) != RD_KAFKA_CONF_OK)
    {
        // std::cerr << "[Kafka][ERR] conf_set bootstrap.servers: " << errstr << "\n";
        rd_kafka_conf_destroy(conf);
        lua_pushnil(L);
        lua_pushstring(L, errstr);
        return 2;
    }
    // 常用的安全默认
    rd_kafka_conf_set(conf, "auto.offset.reset", "earliest", nullptr, 0);
    rd_kafka_conf_set(conf, "enable.auto.commit", "true", nullptr, 0);
    rd_kafka_conf_set(conf, "session.timeout.ms", "45000", nullptr, 0);
    rd_kafka_conf_set(conf, "max.poll.interval.ms", "300000", nullptr, 0);

    // 可选覆盖项：config = {["key"]="value", ...}
    lua_getfield(L, 1, "config");
    if (lua_istable(L, -1))
    {
        lua_pushnil(L);
        while (lua_next(L, -2))
        {
            const char *k = lua_tostring(L, -2);
            const char *v = lua_tostring(L, -1);
            if (k && v)
            {
                rd_kafka_conf_res_t r = rd_kafka_conf_set(conf, k, v, errstr, sizeof(errstr));
                if (r != RD_KAFKA_CONF_OK)
                {
                    // std::cerr << "[Kafka] conf_set " << k << "=" << v << " failed: " << errstr << "\n";
                }
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1); // pop config
    // 创建 consumer
    g_consumer = rd_kafka_new(RD_KAFKA_CONSUMER, conf, errstr, sizeof(errstr));
    if (!g_consumer)
    {
        // std::cerr << "[Kafka][ERR] rd_kafka_new failed: " << errstr << "\n";
        //  失败时 conf 已经被释放或接管，这里只报错
        lua_pushnil(L);
        lua_pushstring(L, errstr);
        return 2;
    }
    // std::cerr << "[Kafka][DBG] rd_kafka_new OK\n";

    // 与 consumer 绑定 poll
    rd_kafka_poll_set_consumer(g_consumer);

    // 订阅 topic 列表
    rd_kafka_topic_partition_list_t *tlist =
        rd_kafka_topic_partition_list_new((int)topics.size());
    for (auto &t : topics)
        rd_kafka_topic_partition_list_add(tlist, t.c_str(), RD_KAFKA_PARTITION_UA);

    if (rd_kafka_subscribe(g_consumer, tlist) != RD_KAFKA_RESP_ERR_NO_ERROR)
    {
        rd_kafka_topic_partition_list_destroy(tlist);
        rd_kafka_destroy(g_consumer);
        g_consumer = nullptr;
        lua_pushnil(L);
        lua_pushstring(L, "subscribe failed");
        return 2;
    }
    rd_kafka_topic_partition_list_destroy(tlist);
    // std::cerr << "[Kafka][DBG] subscribe OK (topics=" << topics.size() << ")\n";
    lua_pushboolean(L, 1);
    // std::cerr << "[Kafka][DBG] init() end\n";
    return 1;
}

// ====== Lua 导出：registerConsumerCb(function(msg) ...) ======
// static int l_kafka_register_cb(lua_State *L) {
//     luaL_checktype(L, 1, LUA_TFUNCTION);
//     if (g_consumer_cb_ref != LUA_NOREF) {
//         luaL_unref(L, LUA_REGISTRYINDEX, g_consumer_cb_ref);
//         g_consumer_cb_ref = LUA_NOREF;
//     }
//     lua_pushvalue(L, 1);
//     g_consumer_cb_ref = luaL_ref(L, LUA_REGISTRYINDEX);
//     //std::cerr << "[Kafka][DBG] registerConsumerCb OK (ref=" << g_consumer_cb_ref << ")\n";
//     return 0;
// }

// ====== Lua 导出：start() —— 启动后台消费线程 ======
static int l_kafka_start(lua_State *L)
{
    (void)L;
    if (!g_consumer)
    {
        // std::cerr << "[Kafka][ERR] start() but not initialized\n";
        lua_pushnil(L);
        lua_pushstring(L, "not initialized");
        return 2;
    }
    if (g_running.load())
    {
        // std::cerr << "[Kafka][DBG] start() ignored, already running\n";
        return 0; // 已经在跑，幂等
    }
    g_running.store(true, std::memory_order_relaxed);
    // std::cerr << "[Kafka][DBG] starting poll thread...\n";
    g_poll_thread = std::thread(poll_loop);
    isruning = true;
    return 0;
}

// ====== Lua 导出：stop()/close() —— 停止线程并销毁 consumer ======
static int l_kafka_stop(lua_State *L)
{
    (void)L;
    g_running.store(false, std::memory_order_relaxed);
    if (g_poll_thread.joinable())
        g_poll_thread.join();
    if (g_consumer)
    {
        // 优雅离组
        rd_kafka_consumer_close(g_consumer);
        rd_kafka_destroy(g_consumer);
        g_consumer = nullptr;
    }
    q_clear();
    isruning = false;
    return 0;
}

// 可选：释放回调
// static int l_kafka_clear_cb(lua_State *L) {
//     (void) L;
//     if (g_consumer_cb_ref != LUA_NOREF) {
//         luaL_unref(L, LUA_REGISTRYINDEX, g_consumer_cb_ref);
//         g_consumer_cb_ref = LUA_NOREF;
//     }
//     return 0;
// }

// ====== 主线程轮询：把消息从队列取出并触发 Lua 回调
extern "C" inline int PollKafka(lua_State *L, int max_calls)
{
    // if (g_consumer_cb_ref == LUA_NOREF) return 0;
    if (!isruning)
    {
        return 0;
    }
    int done = 0;
    KafkaMsg m;
    lua_getglobal(L, "onKafkaMsg");
    if (!lua_isfunction(L, -1))
    {
        lua_pop(L, 1); // 不是函数，弹掉
        return 0;
    }
    int cb_index = lua_gettop(L);
    // int popped = 0;
    while (done < max_calls && q_pop(m))
    {
        std::cerr << "[Kafka] got msg" << "\n";
        // 取回调
        // ++popped;
        // lua_rawgeti(L, LUA_REGISTRYINDEX, g_consumer_cb_ref);
        // 构造 msg 表
        lua_pushvalue(L, cb_index);
        lua_newtable(L);
        lua_pushlstring(L, m.topic.data(), m.topic.size());
        lua_setfield(L, -2, "topic");
        lua_pushinteger(L, m.partition);
        lua_setfield(L, -2, "partition");
        lua_pushinteger(L, m.offset);
        lua_setfield(L, -2, "offset");
        lua_pushlstring(L, m.value.data(), m.value.size());
        lua_setfield(L, -2, "value");
        // 调回调
        if (lua_pcall(L, 1, 0, 0) != LUA_OK)
        {
            const char *err = lua_tostring(L, -1);
            std::cerr << "[Kafka] Lua callback error: " << (err ? err : "unknown") << "\n";
            lua_pop(L, 1);
        }
        ++done;
    }
    lua_pop(L, 1);
    // if (popped > 0) {
    // std::cerr << "[Kafka][DBG] PollKafka delivered " << popped << " msg(s)\n";
    // }
    return done;
}

// ====== Lua 模块导出 ======
extern "C" inline int luaopen_kafka(lua_State *L)
{
    lua_newtable(L);
    lua_pushcfunction(L, l_kafka_init);
    lua_setfield(L, -2, "init");
    // lua_pushcfunction(L, l_kafka_register_cb);
    // lua_setfield(L, -2, "registerConsumerCb");
    lua_pushcfunction(L, l_kafka_start);
    lua_setfield(L, -2, "start");
    lua_pushcfunction(L, l_kafka_stop);
    lua_setfield(L, -2, "stop");
    lua_pushcfunction(L, l_kafka_stop);
    lua_setfield(L, -2, "close"); // alias
    // lua_pushcfunction(L, l_kafka_clear_cb);
    // lua_setfield(L, -2, "clearCallback");
    return 1;
}
