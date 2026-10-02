local RecordDbr =require("RecordDbr")
local tPublicRedis =require("PublicRedis")

local Statistic = {}


function Statistic:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self

    t.arrGiveUpUser={}
    t.arrWinUser ={}
    t.tPartInUser={}
	return t
end

function Statistic:Init()
    self.arrGiveUpUser={}
    self.arrWinUser ={}
    self.tPartInUser ={}
end

--玩家弃牌(中途站起也算)
function Statistic:UserGiveUp(nUserId,isAndroid)
    if isAndroid then
        return
    end
    table.insert(self.arrGiveUpUser,nUserId)
end
--玩家牌局获利
function Statistic:UserWin(nUserId,nProfit,isAndroid)
    if isAndroid then
        return
    end
    self.tPartInUser[nUserId]=true
    if nProfit<0 then
        return
    end

    table.insert(self.arrWinUser,nUserId)
end


--持久化
--nClubId (大厅统一用0表示)
function Statistic:DoPersist(nGroupId)

    for _,nFoldUserId in ipairs(self.arrGiveUpUser) do
        tPublicRedis._SurrenderStatistics(nGroupId,nFoldUserId,self.arrWinUser)
    end
    if #self.arrGiveUpUser>0 and #self.arrWinUser>0 then
        for _,nUserId in ipairs(self.arrGiveUpUser) do
            self.tPartInUser[nUserId] =nil
        end
        for _,nUserId in ipairs(self.arrWinUser) do
            self.tPartInUser[nUserId] =nil
        end
    end

    for nUserId,_ in pairs(self.tPartInUser) do
        tPublicRedis._ResetSurrenderStatistics(nUserId)
    end

end


return Statistic