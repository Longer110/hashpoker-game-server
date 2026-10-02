local tBase = require("base")               --基础功能接口

local obj={}
local tWhitelist ={}

function obj.OnTimerGetWhiteList()
    local redis =tBase.m_MyRedisData[2].redis
    tWhitelist =redis:hgetall("Maintenance_whitelist") or {}
end

function obj.IsUserInWhiteList(nUserId)
    if tWhitelist[string.format("%d",nUserId)] then
        return true
    end
    return false
end


return obj
