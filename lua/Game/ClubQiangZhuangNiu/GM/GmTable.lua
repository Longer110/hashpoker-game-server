package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase    = require("base")         -- 基础功能接口

GmTable = {}

function GmTable:New()
    local t = {}
    setmetatable(t, self)
    self.__index = self

    t.arrRoomTime = {}

    t.tUserGm = {}
    return t
end

function GmTable:Del()
    self = nil
end

function GmTable:Load(tTable)
    local tNewTimer = {}
    for k, v in pairs(tTable.tTimeCfg) do
        tNewTimer[k] = v
        if self.arrRoomTime[k] then
            tNewTimer[k] = self.arrRoomTime[k]
        end
    end

    tTable.tTimeCfg = tNewTimer
    tBase.Log("载入时间成功")
end

function GmTable:AddGm(nUserId, sKey, sGm)
    if self.tUserGm[nUserId] == nil then 
        self.tUserGm[nUserId] = {}
    end

    self.tUserGm[nUserId][sKey] = sGm
end

return GmTable
