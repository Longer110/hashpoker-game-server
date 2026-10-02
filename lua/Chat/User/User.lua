--[[
	用户信息，负责用户信息的存取
]]
local User = {}

function User:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self 
	t.nUserId = 0
	t.sName = ""
	t.nSex = 0
	t.sFaceId = "1"
	t.nGold = 0
	t.sClientID = ""
	t.nClubGold = 0
	t.nShopId =-1
	t.isAndroid =false
	t.nAccountType=-1
	t.sShopAcc = ""
	t.sTableId = "" 
	t.accid = "" 
	t.token = "" 
	t.tid = 0        -- 群组id
	t.vToken = ""
	return t
end

function User:_SetIMData(accid,token,tid)
	self.tid = tid
	self.token = token
	self.accid = accid
end

--设置玩家当前所在牌桌
function User:SetNowTable(sTableId)
	self.sTableId = sTableId
end

--删除玩家当前所在俱乐部
function User:DelNowTable()
	self.sTableId = ""
end

--获取玩家当前所在俱乐部
function User:GetNowTable()
	return self.sTableId or ""
end

function User:_SetVTokenData(vToken)
	self.vToken = vToken
end

return User

