--[[
	负责用户管理，管理登入该服务器的所有用户
]]
local tBase = require("base")           -- 基础功能接口
local tUser = require("User")
local tPubUserApi  = require("PublicUserInfo")    --玩家数据 
local tAndroidIo =require("AndroidIo") 
local cjson =require("json") 


tAndroidIo.Start()

local UserManager ={}
local tUserIdToUser ={}		 	--用户id对应的用户信息(包括机器人)
local arrRecycleRobot={}		--用于回收机器人的缓存队列
local tUserIdToRobotItem={}
local tListKeyToRobotList ={}	--用于存放相应房间配置可用的机器人


local function PushRobotToList(sListKey,tUserObj)
	tListKeyToRobotList[sListKey] =tListKeyToRobotList[sListKey] or {}
	table.insert(tListKeyToRobotList[sListKey],tUserObj)
end
local function CreateAndroidCallBack(tRoomConfig)
	local sListKey =string.format("Group%d_Room%d",tRoomConfig.nGroupId,tRoomConfig.nRoomId)
	local CallBackFunc= function(...)
		local arrParameters ={...}
		local arrUserItem =arrParameters[1]
		for _,userItem in ipairs(arrUserItem) do
			local tUserObj =tUser:New()
			tUserObj.nUserId = userItem.nUserId
			tUserObj.sName = userItem.sNickName
			tUserObj.sFaceId =  userItem.sHeadUrl
			tUserObj.nGold =userItem.nGold
			tUserObj.isAndroid =true
			tUserObj.nSex=userItem.nSex
			tUserObj.sShopAccount =userItem.sShopAcc
		
			if not tUserIdToRobotItem[userItem.nUserId] then
				PushRobotToList(sListKey,tUserObj)
				tUserIdToRobotItem[userItem.nUserId]=userItem
				--tBase.LogT(userItem)
			end
		end
	end
	return CallBackFunc
end
local function GetRobotFromAndroidServ(tRoomConfig,nGetCnt)
	local nGoldFloor =(tRoomConfig.nEnterFloorLimit or 1000) *10
	local nGoldTop =nGoldFloor *5
	local nGroupId =tRoomConfig.nGroupId
	local AndroidCallBack =CreateAndroidCallBack(tRoomConfig)
	local tData = {nGrpId=nGroupId, sIndex="nGold", nMin=nGoldFloor, nHigh=nGoldTop, nCnt=nGetCnt}
	--tBase.LogT("GetRobotFromAndroidServ:",tData)
	tAndroidIo.GetAndroid(tData,AndroidCallBack)
end

local function TheRobotList(tRoomConfig)
	local sListKey =string.format("Group%d_Room%d",tRoomConfig.nGroupId,tRoomConfig.nRoomId)
	return tListKeyToRobotList[sListKey]
end
local function GetARobot(tRoomConfig)
	local robotList =TheRobotList(tRoomConfig) or {}
	local robot =table.remove(robotList)
	return robot
end

local function BackRobot(robot) 
	local robotItem =tUserIdToRobotItem[robot.nUserId]
	if robotItem==nil then
		assert(false,"_BackRobot Err happen,robotItem is nil nUserId: "..robot.nUserId)
		return
	end
	local nPlayCnt =(robot.nPlayCnt or 0)
	robotItem.nMaxRound =robotItem.nMaxRound -nPlayCnt
	if robotItem.nMaxRound<0 then	--
		tBase.Log("_BackRobot  Err happen,robotItem.nMaxRound<0  nMaxRound:%d  nPlayCnt:%d",robotItem.nMaxRound,nPlayCnt)
	end
	robotItem.nGold =robot.nGold
	tUserIdToRobotItem[robot.nUserId] =nil
	table.insert(arrRecycleRobot,robotItem)
	tBase.Log("_BackRobot  back robot nUserId_%d  arrRecycleRobot_%d",robot.nUserId,#arrRecycleRobot)

	if #arrRecycleRobot >=4 then
		local arrRobots =arrRecycleRobot
		arrRecycleRobot={}
		tAndroidIo.SetAndroid({arrAndroid=arrRobots},false) 
	end
end

--成功返回nRobotCntNeed个机器人,否则返回空数组
function UserManager.GetRobots(tRoomConfig,nRobotCntNeed) 
	if nRobotCntNeed<=0 then
		return {}
	end
	local robotList =TheRobotList(tRoomConfig) or {}
	tBase.Log("_GetRobots  robotList: %d   ",#robotList)

	if #robotList<nRobotCntNeed then
		return {}
	end
	local arrRobots ={}
	for i=1,nRobotCntNeed do
		local robot =table.remove(robotList)
		table.insert(arrRobots,robot)
		assert(tUserIdToUser[robot.nUserId]==nil,"robot userid dump")
		tUserIdToUser[robot.nUserId] =robot
	end
	local robotList1 =TheRobotList(tRoomConfig) or {}
	tBase.Log("_GetRobots  robotList1: %d   %d   ",#robotList1,#robotList)
	return arrRobots
end

--
function UserManager.GetUser(nUserId,isSynGoldWithRedis)
	local tUserObj =tUserIdToUser[nUserId]
	if isSynGoldWithRedis and tUserObj~=nil then
		local tUserInfo =tPubUserApi.GetAllUserInfo(nUserId)
		assert(tUserInfo~=nil,"Err happen,GetAllUserInfo return nil,nUserID_"..nUserId)
		tUserObj.nGold =tonumber(tUserInfo.nGold) or 0
		assert(tUserObj.nGold>-0.00001,"redis UserGold is negative")
	end
	return tUserObj
end
--
function UserManager.CreateUser(nUserId)
	local tUserInfo =tPubUserApi.GetAllUserInfo(nUserId)
	assert(tUserInfo~=nil,"Err happen,GetAllUserInfo return nil,nUserID_"..nUserId)
	tUserObj =tUser:New()
	tUserObj.nUserId = nUserId
	tUserObj.sName = tUserInfo.sNickName or ("User_"..nUserId)
	tUserObj.nSex = tonumber(tUserInfo.nSex) or 0 --0:男 1:女
	tUserObj.sFaceId = tUserInfo.sFaceID or "1"
	tUserObj.nGold =tonumber(tUserInfo.nGold) or 0
	tUserObj.nShopId =tonumber(tUserInfo.nShopID) or -1
	tUserObj.isAndroid =false
	tUserObj.sShopAccount =tUserInfo.sShopAccount or ""

	tUserIdToUser[nUserId] =tUserObj
	return tUserObj
end
--
function UserManager.AssureUserExist(nUserId)
	local tUser =UserManager.GetUser(nUserId)
	if not tUser then
		tUser =UserManager.CreateUser(nUserId)
		return tUser,true
	end
	return tUser,false
end
--
function UserManager.DelUser(nUserId)
	local obj = tUserIdToUser[nUserId]
	if obj and obj.isAndroid then
		BackRobot(obj)
	end
	tUserIdToUser[nUserId] =nil
end
--
function UserManager.DoPrepareRobot(tRoomConfig)
	local arr =TheRobotList(tRoomConfig) or {}
	if #arr<8 then
		GetRobotFromAndroidServ(tRoomConfig,(8-#arr))
	end
end

-- 释放机器人
function UserManager.DoReleaseRobot(tRoomConfig)
	local robotList =TheRobotList(tRoomConfig) or {}
	local sListKey =string.format("Group%d_Room%d",tRoomConfig.nGroupId,tRoomConfig.nRoomId)
	local arrUserId = {}
	for _, robot in pairs(robotList) do
		table.insert(arrUserId,robot.nUserId)
	end 
	tBase.Log("_DoReleaseRobot  %s  释放机器人 arr: %d= %s",sListKey,#robotList,cjson.encode(arrUserId))
	for _, robot in pairs(robotList) do
		-- BackRobot(robot) 
	end
	return 1
end


return UserManager

