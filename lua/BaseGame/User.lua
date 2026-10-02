--[[
	用户信息，负责用户信息的存取
]]


User = {}

function User:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self

	t.nUserID = 0
	t.sName = ""
	t.nSex = 0
	t.sFaceID = "1"
	t.nGold = 0 -- 
	t.sClientID = ""
	--区分是否是机器人
	t.isAndroid = false

	--跟牌桌系统数据对接
	t.nTableId = 0
	t.nSitId = 0
	t.nStatus = 0

	t.isOnLine = true
	
	return t
end

function User:Del()
	self = nil
end

function User:Init(tData)
	
	self.nUserID = tData.nUserID
	self.sNickName = tData.sNickName
	self.nSex = tData.nSex
	self.sFaceID = tData.sFaceID or "1"
	self.nTableId = tData.nTableId
	self.dScore = tData.dScore or 1
	self.sClientID = tData.sClientID
	self.nUserType = tData.nUserType or 0
	self.GameType = tData.GameType or 0
	self.GameLevel = tData.GameLevel or 0
	self.nShopID = tData.nShopID or 0
	self.nGold = tData.nGold or 0
end

function User:SetStatus(nStatus)
	--0：空闲 1：准备 2：正在玩
	if self.nStatus ~= nStatus then
		local tData = {["userid"]=self.nUserID}
		--SrvPub.PostInnerEvent(SrvPub.Event.USERSTATUSCHANGE,tData)
	end
	self.nStatus = nStatus
	
end

function User:GetStatus()
	return self.nStatus
end


--设置玩家离线
function User:SetOffLine()
	self.isOnLine = false
end

--设置玩家在线
function User:SetOnLine()
	self.isOnLine = true
end

--玩家是否在线判断
function User:IsOnLine()
	return self.isOnLine
end


return User

