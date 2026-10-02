-- 定时器ID对象
local tBase = require("base")

TimerObject = {}

function TimerObject:New(nMixTimerID, nMaxTimerID)
    local t = {}
    setmetatable(t, self)
    self.__index = self
    if nMixTimerID == nil or nMaxTimerID == nil or nMixTimerID < tBase.m_wTimer_ID_Max then
        
        assert(false,"定时器使用错误")
    end

    self.nMixTimerID = nMixTimerID
    self.nMaxTimerID = nMaxTimerID
    self.m_tTimerID = {}
    for i =  self.nMixTimerID, self.nMaxTimerID do
        self.m_tTimerID[i] = i
    end
    return  t
end

-- 获取定时器ID
function TimerObject:GetTimerID()
    if #self.m_tTimerID  <= 0 then
        tBase.Log("warn %s 定时器ID 不足",self)
        return nil 
    end

    for k, v in pairs(self.m_tTimerID) do
        local nTimerID = k
        self.m_tTimerID[k] = nil 
        return k
    end
end

-- 归还定时器ID
function TimerObject:SetTimerID(nTimerID)
    if nTimerID > self.nMaxTimerID  or nTimerID < self.nMixTimerID then
        return 
    end
    self.m_tTimerID[nTimerID] = nTimerID
    
end

function TimerObject:LogMySelf()
    tBase.Log("%s LogMySelf",self)
end
function TimerObject.ExecuteFuntion(nTimerID,nMSeconds,nCount,self,fFunc,...)
    tBase.Log("ExecuteFuntion")
    self:LogMySelf()
    if nCount > 0 then
        self:SetTimerID(nTimerID)
    end
    fFunc(...)
end

-- 启动定时器
function TimerObject:SetTimer(nTimerID,nMSeconds,nCount,fFunc,...)
    local MySelfFunc = self.ExecuteFuntion
    tBase.TokenCallTimeID(nTimerID,nMSeconds,nCount,MySelfFunc,nTimerID,nMSeconds,nCount,self,fFunc,...)
end

function TimerObject:KillTimerID(nTimerID)
    self:SetTimerID(nTimerID)
    tBase.KillTimer(nTimerID)
end

-- 使用用例
function TimerObject:eg()
    -- local tempFunction = function ()
    --     mlogger:info(string.format( "wo shi 123123123123213" ))
    --    end
    -- local tempTimerObject1 =  TimerObject:New(60000,61000)
    -- tempTimerObject1:SetTimer(1000 * 3, 1, tempFunction)
    -- tempTimerObject1:SetTimer(1000 * 3, 1, tempFunction)
    -- local tempTimerObject2 =  TimerObject:New(62000,63000)
    -- tempTimerObject2:SetTimer(1000 * 3, 1, tempFunction)
    -- tempTimerObject2:SetTimer(1000 * 3, 1, tempFunction)
end
return TimerObject 