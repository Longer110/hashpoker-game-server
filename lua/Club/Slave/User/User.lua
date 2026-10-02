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
	t.nClubGold = 0
	t.nShopId =-1
	t.isAndroid =false
	t.nAccountType=-1
	t.sShopAcc = ""
	t.nGroupId = 0

	t.nClubId = 0 --俱乐部id

	return t
end

function User:SetGroupId(nGroupId)
	self.nGroupId = nGroupId
end

--设置玩家当前所在俱乐部
function User:SetNowClub(nClubId)
	self.nClubId = nClubId
end

--删除玩家当前所在俱乐部
function User:DelNowClub()
	self.nClubId = 0
end

--获取玩家当前所在俱乐部
function User:GetNowClub()
	return self.nClubId or 0
end

return User

