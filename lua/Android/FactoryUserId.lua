--[[UserId生成模块]]
local tPublicUserInfo = require("PublicUserInfo")
local tPublicRedis = require("PublicRedis")
local tALog = require("AndroidLog")

local FactoryUserId = {
    arrDuan = {},
    nIdx = 1
}

--初始化当前UserId段数组
function FactoryUserId.InitBaseUserId()
    FactoryUserId.arrDuan = {}
    FactoryUserId.nIdx = 1
    for k, v in pairs(tPublicUserInfo.tAnUserIdRange) do
        table.insert(FactoryUserId.arrDuan, {nDuanIdx=k, nMinUserId=v.nMin, nMaxUserId=v.nMax})
    end
end

--同步redis上每段UserId的使用游标
function FactoryUserId.RefreshUserId()
    local tDuanUserId = tPublicRedis.GetUseAndroidUserId()
    local str = ""
    for k,v in pairs(FactoryUserId.arrDuan) do
        local nDuanIdx = v.nDuanIdx
        if tDuanUserId[nDuanIdx] then
            v.nMinUserId = tDuanUserId[nDuanIdx]
        end
        str = str..string.format("nDuanIdx:%d,nMinUserId:%d, ",nDuanIdx,v.nMinUserId)
    end
    tALog.Print("_RefreshUserId  同步redis上的UserId的使用游标,%s",str)
end

--保存每段UserId的使用游标到redis
function FactoryUserId.SetUseUserIdToRedis()
    local tDuanUserId = {}
    for k,v in pairs(FactoryUserId.arrDuan) do
        local nDuanIdx = v.nDuanIdx
        tDuanUserId[nDuanIdx] = v.nMinUserId
    end
    tPublicRedis.SetUseAndroidUserId(tDuanUserId)
end

--获取一个可用的UserId
function FactoryUserId.GetOneUserId()
    local nRetUserId = -1

    --首先在特定段里面获取UserId
    for k,v in pairs(FactoryUserId.arrDuan) do
        if k==FactoryUserId.nIdx then
            if v.nMinUserId<=v.nMaxUserId then
                nRetUserId = v.nMinUserId
                v.nMinUserId = v.nMinUserId + 1
                break
            end
        end
    end

    --在特定段里面没找到，遍历所有段，获取一个UserId
    if nRetUserId == -1 then
        for _,v in pairs(FactoryUserId.arrDuan) do
            if v.nMinUserId<=v.nMaxUserId then
                nRetUserId = v.nMinUserId
                v.nMinUserId = v.nMinUserId + 1
                break
            end
        end
    end

    FactoryUserId.nIdx = FactoryUserId.nIdx + 1
    if FactoryUserId.nIdx > #FactoryUserId.arrDuan then
        FactoryUserId.nIdx = 1
    end

    --最后还是没找到，那就是没UserId用了
    if nRetUserId == -1 then
        local str = ""
        for _,v in pairs(FactoryUserId.arrDuan) do
            str = str..string.format("nDuanIdx_%d,nMinUserId_%d,nMaxUserId_%d  ",v.nDuanIdx,v.nMinUserId,v.nMaxUserId)
        end
        tALog.Print("[FactoryUserId.GetOneUserId]没有可用的UserId了"..str)
    end

    return nRetUserId
end

return FactoryUserId
