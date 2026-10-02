
GLock = {}

function GLock.tpLog(e)
    local kl = base.GetKernel()
    local km = km_FD55292F51334A64AC61470D796F8D43.new(kl)
    km:Log(e)
    km:Log(debug.traceback())
    return e
end

-- 分布式上锁
function GLock.Lock(redis, name, val, timeout)

    local nRes = 2 -- 默认是出错状态

    local f = function ()
        local isLock = false
        local dtTime = base.GetTime()
        while(isLock ~= true)
        do
            isLock = redis:setnx(name, val)

            if timeout > 0 and isLock ~= true then
                if base.GetTime() - dtTime > timeout then
                    nRes = 1
                    return -- 超时
                else
                    base.Sleep(10)
                end
            end
        end
        nRes = 0
    end

    xpcall(f, GLock.tpLog)

    if nRes ~= 0 then -- 获取锁失败
        GLock.UnLock(redis, name, val)
    end

    return nRes
end

-- 分布式解锁
function GLock.UnLock(redis, name, val)

    local f = function ()
        if redis:get(name) == val then
            redis:del(name)
        end
    end

    xpcall(f, GLock.tpLog)
end

return GLock