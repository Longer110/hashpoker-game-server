--[[
	牌桌阶段管理器
]]
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase 		= require("base")         -- 基础功能接口
local tTableMgr      = require("TableManage")
local tSrvPub = require("SrvPublic")
local tEventHelp = require("EventHelp")
local tUserMgr = require("UserManager") 
local mlogger = require("logger")
local tJson = require("cjson")
local tGConfig = require("GConfig")
local tPulicMath = require("PublicMath")
local tTableApi = require("TableApi")
local tUserAI = require("UserAi")

AndroidEnter = {
	nLimitEnter = 5,
	nNeedEnter = 5,
}
enumTimeOut=
{
	nDelAndroid 	= 101,    --删除机器人
	nDissolveTable 	= 102,    --超时自动解散牌桌
	nAndroidchat	= 103,	  --机器人自动发表情
}

local Step = {
	
}

--游戏阶段
function Step.GameStep(nTimerID)
	local nTableId = nTimerID % SrvPub.Timer.TableStep
	local tTable = tTableMgr.GetTable(nTableId)
	if not tTable then
		tBase.Log("_GameStep  nTableId: %d tTable is nil",nTableId)		
		return 
	end
	tTable:Print("_GameStep	游戏阶段: %d",tTable.nStep)
	tEventHelp.tEventMgr.tTbEvent.Call(tTable.nStep, nTableId) 
end

--玩家进入触发开始游戏
function Step.EffectStart(nTableId)
	-- tBase.Log("_EffectStart 牌桌流程  nTableId: %d", nTableId)
	local  bFlag = true
	local tTable = tTableMgr.GetTable(nTableId)
	if tTable == nil then
		tBase.Log("_EffectStart    tTable is nil nTableId: %d", nTableId) 
		return
	--人数不够不能开
	elseif tTable:GetReadyUserCnt() < tTable.nPlayerCntAtLeast  then
		tTable:Print("_EffectStart  当前人数: %d   ",tTable:GetReadyUserCnt()) 
		bFlag = false
		--tMgrAndroid:Time_Load_Android(1000,nTableId)
	--已经开局不能开
	elseif tTable.boPlay == true then
		tTable:Print("_EffectStart   已经开始游戏了")  
		bFlag = false
	end 
	if (bFlag == false) then
		tTable:Print("_EffectStart   不能开始游戏")   
		if (tTable.nStep == tSrvPub.enumStep.nStartGame)  then -- 牌桌不能开始，继续等人
			tTable.nStep = tSrvPub.enumStep.nNull
			tBase.KillTimer(tSrvPub.Timer.TableStep + nTableId)
			tTable:Print("_EffectStart   广播取消开始游戏")   
			for i = 1, #tTable.tUserIDArr do 
				local tUser = tUserMgr.GetUserInfo(tTable.tUserIDArr[i])
				if tUser and tUser.isAndroid == false and tUser:IsOnLine() == true then
					Protocol.WatiStartGame(tUser.sClientID,{nResult = 0})
				end	
			end
		end	
	else
		--下面这段开放
		tTable:Print("_EffectStart    nStep_%d  ",tTable.nStep)   
		--统计房间机器人数量,如果房间只有机器人则让牌桌用户解散
		local nAndroidCnt = 0
		for  i = 1, #tTable.tUserIDArr do
			local nUsrId = tTable.tUserIDArr[i]
			local tUser = tUserMgr.GetUserInfo(nUsrId)
			if tUser and tUser.isAndroid == true then
				nAndroidCnt = nAndroidCnt + 1
			end
		end	
		if nAndroidCnt == #tTable.tUserIDArr and tTable.bPreOpenTable == false   then
			local RmUserArr = {}
			tPulicMath.CopyTable(RmUserArr,tTable.tUserIDArr)
			mlogger:info(tJson.encode(RmUserArr))
			for i = 1, #RmUserArr do
				local tData = {["userid"]=RmUserArr[i]}
				tTable:ExitTable(RmUserArr[i]) 
				local  tUser = tUserMgr.GetUserInfo(RmUserArr[i])
				tUserMgr.DelUser(tUser)
			end
			local tData = {["TableId"]=tTable.nTableId} 
			tTableMgr.RemoveTable(nTableId)
			return false
		end
		tTable:Print("_EffectStart   可以开始游戏  nStep_%d  ",tTable.nStep)   
		if (tTable.nStep ~= tSrvPub.enumStep.nStartGame) then
			tTable.nStep = tSrvPub.enumStep.nStartGame
			--生成一个随机牌局
			tTable:MakePaiJuKey(tTableApi.RandomKey())
			for i = 1, #tTable.tUserIDArr do 
				local tUser = tUserMgr.GetUserInfo(tTable.tUserIDArr[i])
				if tUser and tUser.isAndroid == false and tUser:IsOnLine() == true then
					Protocol.WatiStartGame(tUser.sClientID,{nResult = 1,WaitTime = tTable.tTimeCfg.nStartGame,sPaiJuID=tTable.nPaiJuKey})
				end
			end
			tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nStartGame, 1, Step.GameStep)
		end
		local isSuccee,sErr =pcall(tTableMgr.GetNNOnlinePeople,tTable.nGameType)
		if not isSuccee then
			if type(sErr) == "string" then 
				mlogger:error(sErr)
			else 
				tBase.LogT(sErr) 
			end
		end
	end
end

--等待游戏开始
function Step.WaitStartGame(nTableId) 
	local  bFlag = true
	local tTable = tTableMgr.GetTable(nTableId)
	if tTable == nil then 
		tBase.Log("_WaitStartGame  牌桌流程  nTableId: %d Table is nil", nTableId)
		bFlag = false
		return
	--人数不够不能开
	elseif tTable:GetReadyUserCnt() < tTable.nPlayerCntAtLeast  then
		tTable:Print("_WaitStartGame  不够 %d 游戏开始人数：%d", tTable:GetReadyUserCnt(),tTable.nPlayerCntAtLeast)
		bFlag = false 
	--已经开局不能开
	elseif tTable.boPlay == true then
		tTable:Print("_WaitStartGame  已经开始游戏了")    
		bFlag = false
	end 
	--统计房间机器人数量,如果房间只有机器人则让牌桌用户解散
	local nAndroidCnt = 0
	for  i = 1, #tTable.tUserIDArr do
		local nUsrId = tTable.tUserIDArr[i]
		local tUser = tUserMgr.GetUserInfo(nUsrId)
		if tUser.isAndroid == true then
			nAndroidCnt = nAndroidCnt + 1
		end
	end
	if nAndroidCnt == #tTable.tUserIDArr and tTable.bPreOpenTable == false then
		local RmUserArr = {}
		tPulicMath.CopyTable(RmUserArr,tTable.tUserIDArr)
		mlogger:info(tJson.encode(RmUserArr))
		for i = 1, #RmUserArr do
			local tData = {["userid"]=RmUserArr[i]}
			tTable:ExitTable(RmUserArr[i]) 
			local  tUser = tUserMgr.GetUserInfo(RmUserArr[i])
			tUserMgr.DelUser(tUser)
		end
		local tData = {["TableId"]=tTable.nTableId} 
		tTableMgr.RemoveTable(nTableId)
		return false
	end
	--设置游戏阶段
	if bFlag == false then
		tTable:Print("_WaitStartGame  不能开始游戏")    
		tTable.nStep = tSrvPub.enumStep.nNull
		return false
	end
	local nUserCnt = tTable:GetReadyUserCnt()
	--牌桌开始 
	tTable:Print("_WaitStartGame  牌桌游戏开始 nUserCnt: %d ",nUserCnt)   

	-- 抢庄牛牛 有两个人以上就可以开始了
	if nUserCnt >= tTable.nPlayerCntAtLeast then 
		tTable:Print("_WaitStartGame  开局了 GameID:%d,level:%d开始了",tTable.nGameType, tTable.nLevel) 
	   --生成一个随机牌局 
	   tTable.boPlay = true   --确认已开局
	   tTable.nPlayerCntAtLeast = 2 --开局后最少开局人数变为两人
	   tTable:BeginTiming_v2() --开始计时
	--    tTable:Print("开始计时！！！！！！！！！！")
	   tTable.tTableOverview:PaiJuStart(tTable.nKeepTime)
	   tTable.tStatistic:Init()	   
	   for i = 1, #tTable.tUserIDArr do
			local tUser = tUserMgr.GetUserInfo(tTable.tUserIDArr[i])
			if (tUser:GetStatus() == tSrvPub.enumState.nSetDown and not tUser.isRetain)  then
				tUser:SetStatus(tSrvPub.enumState.nPlay)
				tTable.tTableOverview:UserPartIn(tUser.nUserID,tUser.sNickName,tUser.sFaceID)
				tTable.tStatistic:SetIsAndroid(tUser.nUserID,tUser.isAndroid,tUser.sNickName,tUser.sFaceID) 
			end
		end		
		if tTable.nGameType == tGConfig.GameType.KanPaiNiuNiu then 
			tTable.nStep = tSrvPub.enumStep.nQiangZhuang
			if tTable.nStep ~= tTable.nRandStopStep then
				Step.QiangZhuangTimer(nTableId)
			end
		end
		tTable:InitControlStatus()
	end
	return true
end

--玩家抢庄定时器
function Step.QiangZhuangTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_QiangZhuangTimer   nTableId: %d Table is nil", nTableId) 
		return
	end	
	for i = 1, #tTable.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(tTable.tUserIDArr[i])
		if tUser and tUser.isAndroid == false then 
			Protocol.QiangZhuangStartNotify(tUser.sClientID,{nTimes = tTable.tTimeCfg.nQiangZhuang})
		end	
	end
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nQiangZhuang, 1,Step.GameStep)
	UserAi.UserAction(tTable,1000,tTable.tTimeCfg.nQiangZhuang - 1000)	
end

--玩家抢庄
function Step.QiangZhuang(nTableId) 
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_QiangZhuang   nTableId: %d Table is nil", nTableId) 
		return
	end	
	--超时自动下注
	tTable:AutoQiangZhuang()			
end

-- 抢庄完成
function Step.QiangZhuangFinish(nTableId) 
	tBase.KillTimer(tSrvPub.Timer.TableStep + nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_QiangZhuangFinish   nTableId: %d Table is nil", nTableId)  
		return
	end
	tTable.nStep = tSrvPub.enumStep.nDingZhuang
	if tTable.nStep ~= tTable.nRandStopStep then
		Step.DingZhuangTimer(nTableId)
	end	
end

--定庄流程启用定时器
function Step.DingZhuangTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_DingZhuangTimer   nTableId: %d Table is nil", nTableId)   
		return
	end
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nDingZhuang, 1,Step.GameStep)	
end

--玩家定庄
function Step.DingZhuang(nTableId)
	mlogger:info(string.format("牌桌流程定庄阶段 nTableId:%d",nTableId))
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_DingZhuang   nTableId: %d Table is nil", nTableId)   
		return
	end
	local  nUserID = 0
	local nByway = 0
	if tTable.nGameType == tGConfig.GameType.KanPaiNiuNiu then -- 看牌
		nUserID,nByway = tTable:KanPaiQiangZhuang()
	end
	if (nUserID == 0) then
		tTable:Print("_DingZhuang   nUserID: %d 定庄错误 ", nUserID)   
		return 
	end
	tTable:ChooseZhuang(tTable.nZhuangSitId)
	local tUserInfo = tUserMgr.GetUserInfo(nUserID)
	if not tUserInfo then 
		tTable:Print("_DingZhuang   nUserID: %d  tUserInfo is nil",nUserID) 
		return 
	end 
	tTable:Print("_DingZhuang   nUserID: %d  tUserInfo: %s ",nUserID,tJson.encode(tUserInfo)) 
	local  IsChangeZhuang = 0
	if (tTable.tUserPaiJuData.ZhuangJia.nUserID ~= nUserID) then
		IsChangeZhuang = 1
	end
	if tTable.nGameType == tGConfig.GameType.KanPaiNiuNiu then --看牌抢庄一定是换庄
		IsChangeZhuang = 1
	end
	tTable.nZhuangSitId = tUserInfo.nSitId
	tTable.nZhuangUserID = tUserInfo.nUserID

	--广播庄家信息
	for i = 1, #tTable.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(tTable.tUserIDArr[i])
		if tUser and tUser.isAndroid == false and tUser:IsOnLine() == true then 
			local tData = {}
			tData.UserID = tTable.nZhuangUserID
			tData.SitID = tTable.nZhuangSitId
			tData.ByWay = nByway
			tData.IsChangeZhuang = IsChangeZhuang
			tData.Round = tTable.nShangZhuangRound
			
			Protocol.DingZhuang(tUser.sClientID,tData)
		end
	end
	tTable:Print("_DingZhuang  庄位置  nZhuangSitId_%d  ",tTable.nZhuangSitId)  
	if tTable.nGameType == tGConfig.GameType.KanPaiNiuNiu then --抢庄下注
		--进入下注阶段
		tTable.nStep = tSrvPub.enumStep.nXiaZhu
		if tTable.nStep ~= tTable.nRandStopStep then
			Step.XiaZhuTimer(nTableId) 
		end
	else
		--进入下一阶段洗牌阶段
		tTable.nStep = tSrvPub.enumStep.nXiaZhu
		if tTable.nStep ~= tTable.nRandStopStep then
			Step.XiaZhuTimer(nTableId)
		end
	end
end

--下注启用定时器
function Step.XiaZhuTimer(nTableId) 
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_XiaZhuTimer   nTableId: %d Table is nil", nTableId)    
		return
	end
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nXiaZhu, 1,Step.GameStep)
	tUserAI.UserAction(tTable,1000,tTable.tTimeCfg.nXiaZhu - 4000)
end

-- 玩家下注（玩家超时检查）
function Step.XiaZhu(nTableId) 
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_XiaZhu   nTableId: %d Table is nil", nTableId)    
		return
	end	
	--超时自动下注
	tTable:XiaZhu()		
end

--下注完成
function Step.XiaZhuFinish(nTableId) 
	tBase.KillTimer(tSrvPub.Timer.TableStep + nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_XiaZhuFinish   nTableId: %d Table is nil",nTableId)     
		return
	end
	if tTable.nGameType == tGConfig.GameType.KanPaiNiuNiu then -- 看牌
		tTable.nStep = tSrvPub.enumStep.nShouPai
		if tTable.nStep ~= tTable.nRandStopStep then 
			Step.ShouPaiTimer(nTableId)
		end 
	end
end

-- 手牌定时器
function Step.ShouPaiTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_ShouPaiTimer   nTableId: %d Table is nil",nTableId)  
		return
	end	
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nShouPai, 1,Step.GameStep)	
end

 --手牌
function Step.ShouPai(nTableId) 
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_ShouPai   nTableId: %d Table is nil",nTableId)   
		return
	end	
	tTable:XiPai()
	if tTable.nGameType == tGConfig.GameType.TongBiNiuNiu then -- 通比
		tTable:ShouPai(5)
		--TODO 广播发牌
		tTable.nStep = tSrvPub.enumStep.nTanPaiReady
		if tTable.nStep ~= tTable.nRandStopStep then
			Step.TanPaiReadyTimer(nTableId)
		end		
	elseif tTable.nGameType == tGConfig.GameType.SuiJiNiuNiu then -- 随机
		--定庄流程
		tTable:ShouPai(5)
		--TODO 广播发牌
		tTable.nStep = tSrvPub.enumStep.nTanPaiReady
		if tTable.nStep ~= tTable.nRandStopStep then
			Step.TanPaiReadyTimer(nTableId)
		end
	elseif tTable.nGameType == tGConfig.GameType.KanPaiNiuNiu then -- 看牌
		--一开始是手牌
		tTable:ShouPai(5) 
		tTable.nStep = tSrvPub.enumStep.nTanPaiReady
		if tTable.nStep ~= tTable.nRandStopStep then 
			Step.TanPaiReadyTimer(nTableId)
		end
	end
end

-- 发牌定时器
function Step.FaPaiTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("_FaPaiTimer   nTableId: %d Table is nil",nTableId)    
		return
	end	
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nFaPai, 1,Step.GameStep)
end
--发牌流程
function Step.FaPai(nTableId) 
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then 
		tBase.Log("_FaPai   nTableId: %d Table is nil",nTableId)    
		return
	end	
	tTable:FaPai(1)
	--TODO 广播发牌
	tTable.nStep = tSrvPub.enumStep.nTanPaiReady
	if tTable.nStep ~= tTable.nRandStopStep then
		Step.TanPaiReadyTimer(nTableId)
	end
end

-- 摊牌准备定时器
function Step.TanPaiReadyTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then 
		tBase.Log("_TanPaiReadyTimer   nTableId: %d Table is nil",nTableId)   
		return
	end	
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nTanPaiReady, 1,Step.GameStep)
	UserAi.UserAction(tTable,1000,tTable.tTimeCfg.nTanPaiReady - 1000)
end

-- 摊牌准备（摊牌超时）
function Step.TanPaiReady(nTableId) 
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then 
		tBase.Log("_TanPaiReady   nTableId: %d Table is nil",nTableId)  
		return
	end	
	tTable:AutoTanPaiReady()
end

--摊牌准备完成
function Step.TanPaiReadyFinish(nTableId)
	mlogger:info(string.format("牌桌流程摊牌准备完成 nTableId:%d",nTableId))
	tBase.KillTimer(tSrvPub.Timer.TableStep + nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("摊牌完成找不到桌子")
		return
	end
	tTable.nStep = tSrvPub.enumStep.nTanPai
	if tTable.nStep ~= tTable.nRandStopStep then
		Step.TanPaiTimer(nTableId)
	end
end

-- 摊牌定时器 
function Step.TanPaiTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("摊牌找不到桌子")
		return
	end	
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nTanPai, 1,Step.GameStep)
end

--摊牌
function Step.TanPai(nTableId)
	mlogger:info(string.format("牌桌流程摊牌阶段 nTableId:%d",nTableId))
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("摊牌找不到桌子")
		return
	end	
	tTable:TanPai()
	tTable.nStep = tSrvPub.enumStep.nJieSuan
	if tTable.nStep ~= tTable.nRandStopStep then
		Step.CaleScoreTimer(nTableId)
	end
end

-- 结算定时器
function Step.CaleScoreTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("结算找不到桌子")
		return
	end	
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nJieSuan, 1,Step.GameStep)	
end

--结算
function Step.CaleScore(nTableId)
	mlogger:info(string.format("牌桌流程结算阶段 nTableId:%d",nTableId))
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("结算找不到桌子")
		return
	end	
	tTable:CaleScore()
	tTable.nStep = tSrvPub.enumStep.nReset
	if tTable.nStep ~= tTable.nRandStopStep then
		Step.ResetTimer(nTableId)
	end	
end

-- 重置定时器
function Step.ResetTimer(nTableId)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("重置阶段找不到桌子")
		return
	end	
	tSrvPub.SetTimer(tSrvPub.Timer.TableStep + nTableId, tTable.tTimeCfg.nReset, 1,Step.GameStep)
end

--重置游戏
function Step.Reset(nTableId)
	mlogger:info(string.format("牌桌流程重置阶段 nTableId:%d",nTableId))
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		mlogger:error("重置阶段找不到桌子")
		return
	end	
	tTable:ResetGame()
	tTable:SendAllUser(nil,tTable.EnumProtocol.ResetGame)
end

--设置桌子生命周期
function Step.SetTableLife(nTableId, nSec)
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable ~= nil) then
		tSrvPub.SetTimer(tSrvPub.Timer.OverLife+nTableId, nSec*1000, 1, Step.CheckTableLife)
		if tTable.tCreateTableInfo then
			local sRoomId = "TbRoom"..tTable.tCreateTableInfo["nRoomID"]
			tBase.m_MyRedisData[1].redis:expire(sRoomId, nSec)
		end
		tBase.Log("建立TableId: %d 生命周期管理,时长%d秒", nTableId, nSec)
		tTable:Print("建立生命周期管理")
	end
end

--牌桌生命周期(时间)
function Step.CheckTableLife(nTimerID)
	tBase.Log("牌桌生命周期事件  %d",nTimerID)
	Step.OnTime(nTimerID)    --金币房时间计数器
end

function Step.OnTime(nTimerID)
	tBase.Log("_OnTime	 时间计算器  %d",tSrvPub.Timer.OverLife)
	local nTableId = nTimerID % tSrvPub.Timer.OverLife
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log("无效的牌桌")
		return 
	end
    if (tTable.boPlay == false) then 
		--超时自动解散
		if tTable:IsClubTableTimeOut() then
			tBase.Log("_OnTime 超时自动解散 IsClubTableTimeOut nKeepTime_%d",tTable.nKeepTime)
			tTable:Print("超时自动解散")
			GLogic.DisMissTable(tTable,1)
			return
		end
	else
		if tTable:IsClubTableTimeOut() then
			tTable:SetClose(tSrvPub.TableCloseReason.nClubTableTimeOut)   --设置本局结束后关闭桌子
		end
    end
end

function Step.Auto_AddAndroid(nTableId)  --添加机器人()
	local tTable = tTableMgr.GetTable(nTableId)
	if (tTable == nil) then
		tBase.Log(" Auto_AddAndroid 无效的牌桌")
		return 
	end
	local nCount = #tTable:GetReadyUserArr()   --获得桌子已经有多少个玩家 
	tBase.Log("检测牌桌已经有多少个玩家在场: %d", nCount)
end


return Step

