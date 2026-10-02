package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase 	= require("base")         -- 基础功能接口
local tSrvPub	= require("SrvPublic")	  -- 本服务器共享文件

local tTableMgr = require("TableManage")
local tStep		= require("Step")
local  tMgrAndriod = require("MgrAndroid")

Chanel = {}


function Chanel.OnNewChanel(nClientID, sData, nLen)
	local ReadData = tBase.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    tBase.Log("New Chanel MainId:%d, SubID:%d", nMainId, nSubId)
    --内部消息
    if nMainId == tSrvPub.EMain then
    	local tRet = tSrvPub.GetEventData(sData, nLen) 
				
		if nSubId == tSrvPub.Event.USERSTATUSCHANGE then
			local tUserInfo = UserManager.GetUserInfo(tonumber(tRet["userid"]))
			if tUserInfo == nil then
				tBase.Log("用户信息错误")
				return 
			end
			local tTable = tTableMgr.GetTable(tUserInfo.nTableId)
			if tTable == nil then
				tBase.Log("牌桌信息错误")
				return
			end
			tTable:SendAllUser(tonumber(tRet["userid"]), tTable.EnumProtocol.UserStatusChange)
		end
		
    	--设置桌子生命周期
		if nSubId == tSrvPub.Event.SETTABLELIEFE then
			local nTableId = tonumber(tRet["TableId"])
			local nSec = tonumber(tRet["Time"])
			tStep.SetTableLife(nTableId, nSec)
		end

		--删除牌桌
		-- if nSubId == tSrvPub.Event.REMOVETABLE then
		-- 	local nTableId = tonumber(tRet["TableId"])
		-- 	tTableMgr.RemoveTable(nTableId)
		-- end	

		--牌桌开始检测
		if nSubId == tSrvPub.Event.EFFECTSTART then
			local nTableId = tonumber(tRet["TableId"])
			tStep.EffectStart(nTableId)
		end
		
		--牌桌下注完成
		if nSubId == tSrvPub.Event.XIAZHUFINISH then
			local nTableId = tonumber(tRet["TableId"])
			tStep.XiaZhuFinish(nTableId)
		end
		--牌桌摊牌完成
		if nSubId == tSrvPub.Event.TANPAIREADYFINISH then
			local nTableId = tonumber(tRet["TableId"])
			tStep.TanPaiReadyFinish(nTableId)
		end

		--牌桌抢庄完成
		if nSubId == tSrvPub.Event.QIANGZHUANGFINISH then
			local nTableId = tonumber(tRet["TableId"])
			tStep.QiangZhuangFinish(nTableId)
		end

		-- 机器人回收
		if nSubId == tSrvPub.Event.ANDROIDEXIT then
			local nUserID = tonumber(tRet["userid"])
			local nLevel = tonumber(tRet["nLevel"])
			tMgrAndriod:Del(nUserID,nLevel)
		end
		
		if nSubId == tSrvPub.Event.STEP then
			local nTableId = tonumber(tRet["nTableId"])
			local tTable = tTableMgr.GetTable(nTableId)
			if tTable ~= nil then
				tBase.Log("牌桌ID:%d当前步骤: %d", tTable.nTableId, tTable.nStep)
				if tTable.nStep == tSrvPub.enumStep.nDingZhuang then
					tStep.DingZhuangTimer(nTableId)
				elseif  tTable.nStep == tSrvPub.enumStep.nQiangZhuang then
					tStep.QiangZhuangTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nXiaZhu then
					tStep.XiaZhuTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nShouPai then
					tStep.ShouPaiTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nFaPai then
					tStep.FaPaiTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nTanPaiReady then
					tStep.TanPaiReadyTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nTanPai then
					tStep.TanPaiTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nJieSuan then
					tStep.CaleScoreTimer(nTableId)
				elseif tTable.nStep == tSrvPub.enumStep.nReset then
					tStep.ResetTimer(nTableId)
				end
			else
				tBase.Log("错误的牌桌ID %d", nTableId)
			end			
		end	
    end
end

-- 机器人本地操作
function Chanel.OnAnriod(sClientID, sData, nLen)
	
end

return Chanel

