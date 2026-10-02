--[[
	用户信息，负责用户信息的存取
]]
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase = require("base")           -- 基础功能接口
local mlogger = require("logger") -- 日志对象 
local tJosn = require("cjson")
local  tCallBack = require("EventCallBack")

User = {}

function User:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self

	t.nUserID = 0
	t.sName = ""
	t.nSex = 0
	t.sFaceID = "1"
	t.dScore = 0 --这个不是玩家的金币，是玩家的计数分
	--区分是否是机器人
	t.isAndroid = false

	--跟牌桌系统数据对接
	t.nTableId = 0
	t.nSitId = 0
	t.nStatus = 0

	--玩家动作序号，持续更新，验证玩家动作是否合法
	t.nTableAction = 0

	--断线标志位
	t.isOnLine = true

	t.tAction = {}
	-- 用户连跪次数
	t.nLostRound = 0

	-- 机器人多少局离场（只有机器人才有）
	t.nPlayRound = 0
	t.nControlStatus = -1 -- 控牌壮态
	return t
end

function User:Del()
	self = nil
end

function User:Init(tData)
	mlogger:info(tJosn.encode(tData))
	self.nUserID = tData.nUserID
	self.sNickName = tData.sNickName
	self.nSex = tData.nSex
	self.sFaceID = tData.sFaceID or "1"
	self.nTableId = tData.nTableId
	self.dScore = tData.dScore or 1
	self.sClientID = tData.sClientID or ""
	self.nUserType = tData.nUserType or self.nUserType
	self.GameType = tData.GameType or 0
	self.GameLevel = tData.GameLevel or 0
	self.nShopID = tData.nShopID or 0
	self.nGold = tData.nGold or 0
	self.nGroup = tData.nGroup or 0
	self.nLockGoldInTable=0	--当前被锁在本桌子的金币
	tBase.Log("玩家创建成功 sName:%s nUserID:%d nGold:%f", self.sNickName, self.nUserID,self.nGold)
end

function User:SetStatus(nStatus)
	--0：空闲 1：准备 2：正在玩
	if self.nStatus ~= nStatus then
		local tData = {["userid"]=self.nUserID}
		self.nStatus = nStatus
		tCallBack.CallBack(self.nUserID)
		tBase.Log("SetStatus nUserID:%d nStatus:%d [0:空闲/站起 1:坐下 2:玩]", self.nUserID, nStatus)
	end
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

function User:SetIsAndroid(nFlag)
	self.isAndroid = nFlag
end

return User

