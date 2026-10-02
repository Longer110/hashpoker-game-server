--[[
	用户信息，负责用户信息的存取
]]
package.path = require("./lua/Lobby/Head").path

local tBase = require("base")           -- 基础功能接口
local tName     = require("typename")     -- 类弄定义接口

User = {}

User.nCRoomCard = 0  --当天房卡消费数据  

function User:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self

	--玩家个人信息
	t.nUserId = 0
	-- t.sName = ""      --昵称
	-- t.nSex = 0		  --性别

	t.sPhone  = ""    --绑定手机
	t.nRealName  = 0  --实名制：0 已完成，1 未完成
	
	-- 玩家财富数据    -- 暂时不用，以redis 为准
	t.nRoomCard = 0   --房卡-- 钻石，金币，门票，全娱币

	--玩家道具表 
	
	--玩家的统计数据
	-- t.nInning = 0		--总局数：玩家一共进行的局数
	-- t.nHuPaiRate  = 0	--胡牌率：胡牌局数/总游玩局数  *100%，取一位小数；
	-- t.nWinRecord = 0    --连胜记录：连续胡牌的最长局数。

	--玩家连接信息
	t.sIP	= ""		--玩家IP
	t.sClientID = ""	    --连接ID
	t.nStatus = false   --玩家在线状态

	t.arrItem = {}   -- 道具数据： 只存大厅服
	return t
end

function User:Del()
	self = nil
end

function User:Init(tData)
	self.nUserId = tData.nUserId
	self.sName = tData.sName
	self.nSex = tData.nSex
	self.nRoomCard = tData.nRoomCard
	self.sClientID = tData.sClientID
	self.nStatus = true 
	self.arrItem = {} 
	-- --更新玩家 当天消费房卡数据
	User.UpdateRoomConsume(tData.nUserId) 
	tBase.Log(" 玩家信息初始化成功 nUserId :%s nRoomCard:%d", self.nUserId, self.nRoomCard)


	User.LoadUserStatustiData(tData.nUserId) 	--加载 玩家统计数据

	User.Load_User_Item_Data(tData.nUserId) 	--加载 玩家道具数据


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

-- 定时 1秒更新 用户数据
-- function User.TimeUpdateUserData(tData)
	
-- 		--更新玩家 当天消费房卡数据
-- 	User.UpdateRoomConsume(tData.nUserId) 
-- 	tBase.Log(" 玩家信息初始化成功 nUserId :%s nRoomCard:%d", self.nUserId, self.nRoomCard)

-- 	--加载 玩家统计数据
-- 	User.LoadUserStatustiData(tData.nUserId) 	

-- 	return
-- end


-- 加载玩家道具数据 
function User.Load_User_Item_Data(nUserID)
	if nUserID == nil and nUserID == 0 then return 0 end 

	tBase.Log(" 加载玩家:  %d  道具数据      ",nUserID)
	local sSql = "Call User_Get_Item_Data("..nUserID..")"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_ITEM_DATA)
    -- s:AddInt32(nUserID)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, nUserID, s:GetData(), s:GetSize())
	return 0
end


--定时更新玩家  房卡消费数据
function User.UpdateRoomConsume(nUserId)
    tBase.Log(" 房卡消费数据   UpdateRoomConsume  ")  
	if nUserId == nil and nUserId == 0 then return 0 end 

	tBase.Log(" 玩家数据  定时更新玩家: %d  ,当天房卡消费数据   ",nUserId)
	local sSql = "Call User_Get_Consume_Count("..nUserId..")"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_CONSUME)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, nUserId, s:GetData(), s:GetSize())
    tBase.Log(" 定时更新玩家  房卡消费数据   请求SQL   成功  ")  

	return 0 
end

-- 更新玩家当天消费房卡数据
function User.LoadRoomConsume(ClientID, sData, nLen)
    tBase.Log(" 更新玩家当天消费房卡数据   LoadRoomConsume  ")  

    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()  
	local nUserId =  ReadData:GetInt32()
	User.nCRoomCard = ReadData:GetInt32()
	tBase.Log(" 玩家数据:   %d   更新玩家当天消费房卡数据    nCRoomCard:  %d  ",nUserId,User.nCRoomCard)	
	return 0
end

--加载 玩家统计数据
function User.LoadUserStatustiData(nUserId)
	if nUserId == nil and nUserId == 0 then return 0 end 
	tBase.Log(" 玩家数据  玩家： %d,  加载玩家统计数据    ",nUserId)
	
	local sSql = "Call User_Get_Statustical_Data("..nUserId..")"
    -- local s = tBase.GetSP().new(tPubProto.MAIN.DB, tPubProto.SUB_DB.SUB_REQ_STATUSTI)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, nUserId, s:GetData(), s:GetSize())
    tBase.Log(" 玩家数据  加载玩家统计数据   请求SQL   成功  ")  
	return 0 
end


return User

