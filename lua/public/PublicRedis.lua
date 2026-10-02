--[[
	一些供有 Redis 公共接口
-- ]]

local tBase  = require("base")         -- 基础功能接口
local api    = require("publicApi")    -- 共用功能接口
local cjson     = require("cjson")        -- json 
local tSrvInfo = require("ServerInfo")
local tRedisCahche = require("RedisCahche")
local logger = require("logger")      -- 日志对象
local tPublicUserGold =require("PublicUserGold")

PublicRedis = {

}
 
PublicRedis.tGameType = {
    nBaiRenNiuNiu = 104,
    nBaiRenZhaJinHua = 118,
    nBaiRenBaiJiaLe = 107,
    nYuXiaXie = 212,
    nPilot = 133,
    nSeDie=150,     --合集色碟(百人游戏)
    nSeDieM=153,    --直播色蝶
    nToubao = 155,  -- 直播骰宝 
	nFootBall = 129,--射龙门
	nFellTree = 157,--砍树
	nBasketball = 159,--篮球 
}

PublicRedis.nServStartTime=os.time()

-- local MyRedis1 = tBase.m_MyRedisData[1].redis     -- Redis 用户临时数据（关服清除）
-- local MyRedis2 = tBase.m_MyRedisData[2].redis     -- Redis 持久化(不能清除)
-- local MyRedis3 = tBase.m_MyRedisData[3].redis     -- Redis 监控用(不能清除)	


-- 异常输出
function tpLog(e)
    local kl = base.GetKernel()
    local km = km_FD55292F51334A64AC61470D796F8D43.new(kl)
    km:Log(e)
    km:Log(debug.traceback())
    return e
end

-- 锁操作 
local  function PublicLock(sKey,f)
	local nTime1 = tBase.GetTime()
	-- tBase.Log("_PublicLock  sKey_%s   %d毫秒 ",sKey,tBase.GetTime()-nTime1)
    tBase.m_MyRedisData[1].redis:lock(sKey)
    xpcall(f,tpLog) 
    tBase.m_MyRedisData[1].redis:unlock(sKey)  
	-- tBase.Log("_PublicLock  sKey_%s   %d毫秒 ",sKey,tBase.GetTime()-nTime1)
    return 
end

-- 获取鱼虾蟹生成牌参数
function PublicRedis._YuXiaXie_CreateCardParameter(nGroupId)
	return tRedisCahche._YuXiaXie_CreateCardParameter(nGroupId)	
end

-- 获取骰宝生成牌参数
function PublicRedis._TouBao_CreateCardParameter(nGroupId)
	return tRedisCahche._TouBao_CreateCardParameter(nGroupId)	
end

-- 获取 推荐控概率 配置
function PublicRedis._GetLiveRecommendControl(nLiveUserID,nGameId)
	local nProbability = 0
	local function func()
		local tProbability = tRedisCahche._GetLiveRecommendControl(nLiveUserID,nGameId) 
		if not tProbability or  type(tProbability) == "number" then 
			tBase.Log("_GetLiveRecommendControl_%d nGameId_%d 获取配置有问题 tProbability: %s ",nLiveUserID,nGameId,cjson.encode(tProbability))
			return 0
		end   
		table.sort(tProbability)  
		nProbability = math.random(tProbability[1],tProbability[2])
		local isDefault = true 
		local sKey = string.format("Live_RecommendProbabilityNew_%d_Inning_Win",nLiveUserID)	
		local Redis = tBase.m_MyRedisData[2].redis 
		local sLog = ""
		local tEndData = Redis:hgetall(sKey) 
		if tEndData and nGameId==121 and tEndData.nPlanInning and tonumber(tEndData.nPlanInning) > 20 then 
			local dProbability = tonumber(tEndData.nNatureWin) / tonumber(tEndData.nPlanInning) 
			if dProbability <= 0 or dProbability >= 1 then 
				sLog = "超出默认: "..dProbability 
			else
				dProbability =  (nProbability/ 100 - dProbability) /(1-dProbability) 
				nProbability = math.floor(dProbability*100)
				isDefault = false 		
				sLog = "统计: "..dProbability 							
			end 			
		end 
		if isDefault then  
			--公式a = (c - b) / (1 - b) a为内部真正主播风控概率，b为该下注区自然中奖概率，c为后台设置的主播风控概率
			if nGameId==121 then --直播鱼虾蟹 41.5%
				local dProbability = (nProbability/100-0.415)/(1-0.415)
				nProbability = math.floor(dProbability*100)
			elseif nGameId==122 then--直播百家乐 庄45.8% 闲44.6%
				local dProbability = (nProbability/100-0.45)/(1-0.45)
				nProbability = math.floor(dProbability*100)
			elseif nGameId==153 then--直播色碟 单50.08%  双49.92%
				local dProbability = (nProbability/100-0.5)/(1-0.5)
				nProbability = math.floor(dProbability*100)
			elseif nGameId==155 then--直播骰宝 双50% 单50% 大49.62% 小49.99%
				local dProbability = (nProbability/100-0.5)/(1-0.5)
				nProbability = math.floor(dProbability*100)
			end
			sLog = sLog.."默认 "..nProbability
		end 
		if nProbability<0 then
			sLog = sLog.."超出: "..nProbability
			nProbability = 0
		elseif nProbability>100 then
			sLog = sLog.."低于: "..nProbability
			nProbability = 100
		end 
		tBase.Log("_GetLiveRecommendControl_%d_%d %s nProbability: %f  %s   %s "
		,nLiveUserID,nGameId,sLog,nProbability,cjson.encode(tProbability),cjson.encode(tEndData))

	end
	local isSuccee,sErr = pcall(func)
	if not isSuccee then 
		tBase.Log("_GetLiveRecommendControl_%d  ErrorMsg  _CheckLogic sErr: %s ",nLiveUserID,sErr)
		if type(sErr) == "string" then 
			logger:error(sErr)
		else 
			tBase.LogT(sErr) 
		end
		return 0
	end 	
	return nProbability 
end
 
--处理 主播下注与推荐 风控数据 
function PublicRedis._DisposeLiveControl_Win(tData)
	local nLiveUserID = tData.tElseInfo.nLiveUserID
	local nGameId = tData.nGameType
	local nWinLose = tData.nWinlose
	local nControl = tData.tElseInfo.nControl or 0
	local nControlType = tData.tElseInfo.nControlType or -1 
	-- if nControlType < 100 then 
	-- 	tBase.Log("_DisposeLiveControl_Win_%d_%d nControlType: %d  非主播下注风控 nControl_%d  ",nLiveUserID,nGameId,nControlType,nControl)
	-- 	return
	-- end 
	local tProbability = tRedisCahche._GetLiveRecommendControl(nLiveUserID,nGameId,true) 
	if tProbability == 0 then  
		tBase.Log("_DisposeLiveControl_Win_%d_%d nWinLose: %f 没计划配置 ",nLiveUserID,nGameId,nWinLose)
		return
	end 
	local Redis = tBase.m_MyRedisData[2].redis 
    local sKey = string.format("Live_RecommendProbabilityNew_%d_Inning_Win",nLiveUserID)	 
	local tInfo = Redis:hgetall(sKey) 
	if not tInfo or not tInfo.nEndInning then 
		tBase.Log("_DisposeLiveControl_Win_%d_%d nWinLose: %f 没有初始化计划数据 ",nLiveUserID,nGameId,nWinLose) 
		return 
	end 

	Redis:hincrbyfloat(sKey,"nNowWin",nWinLose)   -- 更新当前输赢情况	
	if nControlType >= 111 then  			 
		Redis:hincrby(sKey,"nNowInning",1)   -- 增加局数	
	end 
	
	tInfo = Redis:hgetall(sKey) 

	local tLiveBetControl = {}
	tLiveBetControl.nEndInning = tonumber(tInfo.nEndInning) or 0        -- 赢的结束局数
	tLiveBetControl.nEndWin   = tonumber(tInfo.nEndInning)  or  0  	    -- 赢结束的数量 
	tLiveBetControl.nNowInning = tonumber(tInfo.nNowInning) or 0        -- 当前调控局数
	tLiveBetControl.nNowWin   = tonumber(tInfo.nNowWin)  or  0  	    -- 计划内盈利情况 
	tLiveBetControl.nNatureWin = tonumber(tInfo.nNatureWin) or 0        -- 自然赢局数
	tLiveBetControl.nPlanInning = tonumber(tInfo.nPlanInning) or 0	    -- 计划内总局数 
	tLiveBetControl.isControl   = false     -- 是否调控无效
	if tInfo.nPlanInning and nGameId == 121 then  -- 处理直播鱼虾蟹 计划内的统计数据
		if not tData.isLiveBetControl then 
			local arrBet = tData.tElseInfo.tBet
			tBase.Log("_DisposeLiveControl_Win_%d_%d %d 下注不符合规则(超过3个单区域或者下注高赔率)  %s ",nLiveUserID,nGameId,nControlType,cjson.encode(arrBet)) 
			return tLiveBetControl
		end  
		-- if nControlType ~= 112 then 
		-- 	tBase.Log("_DisposeLiveControl_Win_%d_%d nControlType: %d  非本主播下注风控 nControl_%d  ",nLiveUserID,nGameId,nControlType,nControl)
		-- 	return
		-- end 		
		local nNowWin = Redis:hincrbyfloat(sKey,"nPlanInning",1)  	  -- 计划的总局数	
		if nControlType < 111 and nWinLose > 0 then 
			local nNatureWin = Redis:hincrby(sKey,"nNatureWin",1)    -- 自然赢局数 
		end 
	end
	 	
	local tInfo = Redis:hgetall(sKey) 
	local tLiveBetControl = {}
	tLiveBetControl.nEndInning = tonumber(tInfo.nEndInning) or 0        -- 赢的结束局数
	tLiveBetControl.nEndWin   = tonumber(tInfo.nEndInning)  or  0  	    -- 赢结束的数量 
	tLiveBetControl.nNowInning = tonumber(tInfo.nNowInning) or 0        -- 当前调控局数 
	tLiveBetControl.nNowWin   = tonumber(tInfo.nNowWin)  or  0  	    -- 计划内盈利情况
	tLiveBetControl.nNatureWin = tonumber(tInfo.nNatureWin) or 0        -- 自然赢局数
	tLiveBetControl.nPlanInning = tonumber(tInfo.nPlanInning) or 0	    -- 计划内总局数 
	tLiveBetControl.isControl   = true     -- 是否调控无效
	tBase.Log("_DisposeLiveControl_Win_%d_%d %d nWinLose_%f  %s ",nLiveUserID,nGameId,nControlType,nWinLose,cjson.encode(tInfo))
	return tLiveBetControl
end 

function PublicRedis._OnGeHelptUI(nGroupId)
	return tRedisCahche._OnGeHelptUI(nGroupId)
end

--获取下注时间(可能返回nil)
function PublicRedis.GetBetTime(nGameId,nGroupId)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sKey 		  =string.format("LiveSwitchConfig:Game%d:Group%d",nGameId,nGroupId)
	local sBetTime =tRedis:hget(sKey,"BetTime")
	return tonumber(sBetTime)
end

--直播游戏 功能开关配置 (推荐、跟投、上庄 功能开关)
--返回示例:{isRecommendOn=true,isFollowBetOn=true,isUserBankerOn=false}
function PublicRedis.Get_LiveSwitchConfig(nGameId,nGroupId)
	return tRedisCahche.Get_SwitchConfig(nGameId,nGroupId)
end

--功能开关配置 (推荐、跟投、上庄 功能开关)

--设置功能开关(Game122,Group20); 推荐、跟投、上庄; 1:开 0:关
--返回示例:{isRecommendOn=true,isFollowBetOn=true,isUserBankerOn=false,nAutoBet=false}
function PublicRedis.Get_SwitchConfig(nGameId,nGroupId)
	return tRedisCahche.Get_SwitchConfig(nGameId,nGroupId)
end

--获取游戏配置 (Game122,Group20)
--返回示例: 
function PublicRedis._GetGameConfig(nGameId,nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("LiveSwitchConfig:Game%d:Group%d",nGameId,nGroupId) 
	local tCfg = My_2:hgetall(sKey)  
	tCfg.isRecommendOn=(tonumber(tCfg.isRecommendOn or 0)  ==1)
	tCfg.isFollowBetOn=(tonumber(tCfg.isFollowBetOn or 0)  ==1)
	tCfg.isUserBankerOn=(tonumber(tCfg.isUserBankerOn or 0) ==1) 
	if nGameId == 121 then   -- 统一牌桌结果: 只是直播鱼虾蟹 
		tCfg.isUnifyResult=(tonumber(tCfg.isUnifyResult or 0) ==1) 
	end  
	if nGameId==121 or nGameId==122 or nGameId==153 then
		tCfg.isVipOn=(tonumber(tCfg.isVipOn or 0) ==1)
	end
	if tCfg.nBetTime then 
		tCfg.nBetTime = tonumber(tCfg.nBetTime or 25)   -- 下注时间
		if tCfg.nBetTime <= 10 then tCfg.nBetTime = 25 end 
	else
		tCfg.nBetTime = 25  -- 默认 
	end 
	if nGameId == 122 then 	
		tCfg.nAutoBet=(tonumber(tCfg.nAutoBet or 0)) 	-- 自动下注开关:  0全关、1: 全开、2: 区块链开(幸运扑克关)、3幸运扑克开(区块链关)
		tCfg.nAutoBetTableCfg = tonumber(tCfg.nAutoBetTableCfg or 0)   --  1独立牌桌、2混合牌桌		  
	end 
	tBase.Log("_GetGameConfig   tCfg_%s ",cjson.encode(tCfg)) 
	return tCfg
end

--集合游戏 可下注筹码
--返回示例:{5,10,50,100,1000,2000,5000,10000,20000}
--注意:如果返回nil,表示没有任何设置,请自行处理该情况
function PublicRedis.GetRoomCanBetChip(nGameId,nGroupId,nSession)
	return tRedisCahche.GetRoomCanBetChip(nGameId,nGroupId,nSession)
end

--功能开关配置 (直播聊天开关 功能开关)
--设置功能开关(Group20); 聊天; 1:开 0:关
--返回示例:{isChatOn=true}
function PublicRedis.Get_SwitchChatConfig(nGroupId)
	return tRedisCahche.Get_SwitchChatConfig(nGroupId)
end

function PublicRedis._OnGetSwitchCfg(nGameId,nGroupId)
	return tRedisCahche._OnGetSwitchCfg(nGameId,nGroupId)
end

function PublicRedis._getGameSkinVal(sSelectSkin,nGroupId) 
	return tRedisCahche._getGameSkinVal(sSelectSkin,nGroupId)
end

--获取限红数据
--返回示例: {[Area1]={min=1,max=100},[Area2]={min=1,max=2000}}
function PublicRedis.Get_UserAreaLimit(nGameId,nGroupId,nRoomId)
	return tRedisCahche.Get_UserAreaLimit(nGameId,nGroupId,nRoomId)
end

--赔率配置
function PublicRedis.Get_GameOdds(nGameId,nGroupId)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("GameOdds:GameId%d:GrounpId%d",nGameId,nGroupId)
	local tRlt =tRedis:hgetall(sKey) or {}
	return tRlt
end

--获取游戏ID数组(nType:1.允许转入转出的游戏  2.只允许转入的游戏)
function PublicRedis.GetArrGameId(nType)
	return tRedisCahche.GetArrGameId(nType)
end

--是否允许转账的游戏
function PublicRedis._IsAllowTransferGameId(nGameId)
	local nType = 0 --0:不可以转入转出 1:可以转入转出 2.只可以转出 
	local arrGameId = PublicRedis.GetArrGameId(1)
	for index, value in ipairs(arrGameId) do
		if value == nGameId then
			nType = 1
		end
	end
	arrGameId = PublicRedis.GetArrGameId(2)
	for index, value in ipairs(arrGameId) do
		if value == nGameId then
			nType = 2
		end
	end
	return nType
end

--直播游戏 可下注筹码
--返回示例:{5,10,50,100,1000,2000,5000,10000,20000}
--注意:如果返回nil,表示没有任何设置,请自行处理该情况
function PublicRedis.Get_LiveChips(nGameId,nGroupId)
	return tRedisCahche.Get_LiveChips(nGameId,nGroupId)
end

--获得游戏房间的最低上庄金额
function PublicRedis.Get_UserBankerLimit(nGroupId,nGameId,RoomId)
	return tRedisCahche.Get_UserBankerLimit(nGroupId,nGameId,RoomId)
end

function PublicRedis._GetMonitorCfg()
	local Rds = tBase.m_MyRedisData[2].redis
	local tMotCfg = Rds:hgetall("MonitorKey")
	if not tMotCfg then 
		return nil
	else
		return tMotCfg
	end
end

--返回机器人数量上下限
function PublicRedis.AndroidCountLimit(nGroupId,nGameId,nRoomId)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sHour = os.date("%H")
	local sKey =string.format("LiveAndroidConfig_GameId_%d:GroupId_%d:RoomId_%d*[:,]%s[,]*",nGameId,nGroupId,nRoomId,sHour)
	local arrKeys = tRedis:keys(sKey) or {}
	local sConfigKey =arrKeys[1]
	if sConfigKey and #sConfigKey>0 then
		local tConfig =  tRedis:hgetall(sConfigKey)
		local nMinCount =tonumber(tConfig.nMinCount)
		local nMaxCount =tonumber(tConfig.nMaxCount)
		return nMinCount,nMaxCount
	end
end

--返回当前应该使用的机器人数量
function PublicRedis._LiveAndroidCount(nGroupId,nGameId,nRoomId)
	return tRedisCahche._LiveAndroidCount(nGroupId,nGameId,nRoomId)
end

-- 直播底分
function PublicRedis._LiveConfigAnte(nGroupId,nGameId,nRoomId)
	return tRedisCahche._LiveConfigAnte(nGroupId,nGameId,nRoomId)
end

-- 获取 区块链 域名
function PublicRedis._GetBlockchainDomainName()
	return tRedisCahche._GetBlockchainDomainName()
end

-- 获取 MySource 域名
function PublicRedis._GetMySourceDomainName()
	return tRedisCahche._GetMySourceDomainName()
end

-- 获取 彩票 域名
function PublicRedis._GetJackLotDomainName(nGameId)
	local sKey=string.format("") 
	if nGameId >= 307 and nGameId < 310 then    -- 香港彩、澳门彩、新澳门彩
		sKey= string.format("Game_Url") 
	elseif nGameId >= 310 and nGameId <= 316 then    -- RY彩 
		sKey= string.format("RY_Url")	
	end 
	return tRedisCahche._GetJackLotDomainName(sKey)
end

-- 获取充值提现域名
function PublicRedis._GetRechargeWithdrawalDomainName()
	return tRedisCahche._GetRechargeWithdrawalDomainName()
end

-- 获取风控余额
function PublicRedis.__GetBalance(nUserId,nGroupId)
	return tRedisCahche._GetBalance(nUserId,nGroupId)
end

-- 机器人配置
function PublicRedis._GetRobConfig(nGroupId)
	return tRedisCahche._GetRobConfig(nGroupId)
end

--获取邀请码相关内容显示开关
function PublicRedis._GetCodeSwitch(nUserId)
	return tRedisCahche._GetCodeSwitch(nUserId)
end

--获取前端用文件编码
function PublicRedis._GetFileConfig()
	return tRedisCahche._GetFileConfig()
end

--获取转账方式
function PublicRedis._GetTransferWay(nGroupId,sSubKey)
	return tRedisCahche._GetTransferWay(nGroupId,sSubKey)
end

--获取充值提现开关
function PublicRedis._GetUserTransferSwitch(nUserId)
	return tRedisCahche._GetUserTransferSwitch(nUserId)
end

--获取分享活动开关
function PublicRedis._GetUserShareActiSwitch(nUserId)
	return tRedisCahche._GetUserShareActiSwitch(nUserId)
end

--获取“手动”充值提现开关 1为关 0为开
function PublicRedis._GetOnliTransSwitch(nGroupId)
	return tRedisCahche._GetOnliTransSwitch(nGroupId)
end

--获取最小充值金额
function PublicRedis._GetMinRecharge(nGroupId)
	return tRedisCahche._GetMinRecharge(nGroupId)
end

-- 区块链
--主播推荐开关信息持久化
function PublicRedis.SetGameRecommendInfo(nGameId,nUserId,tData)
	local redis =tBase.m_MyRedisData[2].redis
	local sJsonData =cjson.encode(tData)
	local sKey =string.format("GameRecommendInfo_%d",nGameId)
	local sSubKey =string.format("%d",nUserId)
	redis:hmset(sKey, {[sSubKey]=sJsonData})
end

--主播推荐开关信息. 返回nil或上一次所设置的信息
function PublicRedis.GetGameRecommendInfo(nGameId,nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("GameRecommendInfo_%d",nGameId)
	local sSubKey =string.format("%d",nUserId)
	local sJsonData =redis:hget(sKey,sSubKey)
	local tData =nil
	if sJsonData then
		tData= cjson.decode(sJsonData)
	end
	return tData
end

function PublicRedis._SetBlockChainData(nType,sPaiJuId,sResult)
	local sKey = "BlockChain_"
	local My_1 = tBase.m_MyRedisData[1].redis 
	if nType ==1 then 
		sKey =sKey.."TableScene_"..sPaiJuId
	elseif nType == 2 then 
		sKey =sKey.."OpenCardResult_"..sPaiJuId
	elseif nType == 3 then 
		sKey =sKey.."CardBatch_"..sPaiJuId
		My_1:set(sKey,sResult)
		tBase.Log("_SetBlockChainData  nType_%d  sKey_%s 获取批量牌 " ,nType,sKey)
		return 
	elseif nType == 4 then 
		sKey =sKey.."OpenCardResult_"..sPaiJuId
	end 
	My_1:set(sKey,sResult)
	tBase.Log("_SetBlockChainData  nType_%d  sKey_%s  sPaiJuId_%s sResult_%s   " ,nType,sKey,sPaiJuId,sResult)
end

-- 区块链
function PublicRedis._GetBlockChainData(nType,sPaiJuId)
	local sKey = "BlockChain_"
	local My_1 = tBase.m_MyRedisData[1].redis 
	if nType ==1 then 
		sKey =sKey.."TableScene_"..sPaiJuId
	elseif nType == 2 then 
		sKey =sKey.."OpenCardResult_"..sPaiJuId
	elseif nType == 3 then 
		sKey =sKey.."CardBatch_"..sPaiJuId
		local sResult = My_1:get(sKey)
		if not sResult then 
			return nil 
		end 
		return cjson.decode(sResult) 
	elseif nType == 4 then 
		sKey =sKey.."OpenCardResult_"..sPaiJuId
	end 
	local sResult = My_1:get(sKey)
	if not sResult then 
		-- tBase.Log("_GetBlockChainData  nType_%d  sKey_%s  sResult is nil ",nType,sKey)
		return nil 
	end 
	-- tBase.Log("_GetBlockChainData sKey_%s  sResult_%s ",sKey,sResult)
	My_1:del(sKey)
	return cjson.decode(sResult) 
end

-- 合集百人机器人配置数量 
function PublicRedis._GetHJBR_AndroidCount(nGroupId,nGameId,nRoomId)
	return tRedisCahche._LiveAndroidCount(nGroupId,nGameId,nRoomId)
end

-- 合集百人游戏 机器人 
function PublicRedis._GetBRAndroidPeople_Logic(nGroupId,nGameId,nRoomId,nAndroidsCnt)
    local nCnt = 0   -- 增加或者减少机器人数量   
    local sKey = string.format("LiveChipsConfig:Group%d:Game%d:Room%d",nGroupId,nGameId,nRoomId)
    -- local nAndroidsCnt = PublicRedis._GetGameAndroidCount(nGroupId,nGameId,nRoomId)  -- 获取当前机器人数量
  	nAndroidsCnt = nAndroidsCnt or 0 
    local nAndroidCfgCnt = PublicRedis._GetHJBR_AndroidCount(nGroupId,nGameId,nRoomId)   -- 获取机器人数量配置 
    local nCnt = 0
    if nAndroidsCnt > nAndroidCfgCnt then  
        if (nAndroidsCnt - nAndroidCfgCnt) > 10 then 
            nCnt = math.random(1,10) 
        else
            nCnt = nAndroidsCnt - nAndroidCfgCnt
        end 
        nCnt = -nCnt  -- 减少 
    elseif nAndroidsCnt < nAndroidCfgCnt then 
        if (nAndroidCfgCnt - nAndroidsCnt) > 10 then 
             nCnt = math.random(1,10) 
        else
             nCnt = nAndroidCfgCnt - nAndroidsCnt
        end          
    elseif nAndroidCfgCnt == 0 and  nAndroidsCnt > 0 then 
        if nAndroidsCnt > 10 then 
             nCnt = math.random(1,10)            
        else
            nCnt = math.random(1,nAndroidsCnt) 
        end        
        nCnt = -nCnt  -- 减少 
    end 
    -- tBase.Log("_GetBRAndroidPeople_Logic  nAndroidsCntt_%d  nAndroidCfgCnt_%d   nCnt_%d nGroupId_%d nGameId_%d nRoomId_%d ",
	 	--nAndroidsCnt,nAndroidCfgCnt,nCnt,nGroupId,nGameId,nRoomId)
    return nCnt 
end

-- 定时处理 非百人 游戏机器人数量 
function PublicRedis._TimerAndroidPeople()
	local tRedis = tBase.m_MyRedisData[2].redis
	local bOneLoad = false
	local bAndroidCfgKey = false
	local nKeyCnt = 0
	local nLoadKeyCfgProbability = 50    -- 加载配置概率
	local nAddCntProbability = 50     -- 处理机器人动态数量概率
	local nLoadKeyTime =  3600        --加载key 秒
	local nLoadKeyCfgTime = 3600        --加载key配置 秒
	nLoadKeyTime =  60          --加载key 秒         -- 测试
	nLoadKeyCfgTime = 30        --加载key配置 秒     -- 测试

	local nKeyTime = 0
	local nKeyCfgTime = 0
	local nLogicTime = 0      
	local nRemoveTime = 0 
	local nStartTime = tBase.GetTime()

	-- 加载机器人配置 key 
	local function _LoadKey()
		local nTime = tBase.GetTime()
		local isLoad = false
	    if not PublicRedis.arrAndroidCfg then
	    	PublicRedis.arrAndroidCfg = {}
	    	isLoad = true
	    	bOneLoad = true
	    	PublicRedis.nLoadTime = os.time()
	    else
    		local nLoadTime = (os.time() - PublicRedis.nLoadTime)
    		if nLoadTime >= nLoadKeyTime then
    			isLoad = true
    		end
	    end
	    if isLoad then
		    local sAndroidCfgKey = "LiveAndroidConfig_GameId*"
		    local arrKeys = tRedis:keys(sAndroidCfgKey) or {}
		    if #arrKeys == 0 then 
		    	return false
		    end 
		    bAndroidCfgKey = true
	    	for k,sKey in pairs(arrKeys) do
		    	if not PublicRedis.arrAndroidCfg[sKey] then
		    		PublicRedis.arrAndroidCfg[sKey] = {}
		    	end
	    	end
	    	PublicRedis.nLoadTime = os.time()
	    	nKeyTime = tBase.GetTime()-nTime
	    	tBase.Log("_LoadKey  nKeyTime_%d  isLoad: %s   ",nKeyTime,isLoad and "true" or "false")
	    end
	    return true
	end
	    
	-- 先获取配置 数量 
	local function _LoadKeyCfg()
		local nTime = tBase.GetTime()
		local function _GetTime(sTime)
			local arrnHourTime = {}
	    	local tHourTime = publicApi.Split(sTime,",")
    		for k,nHour in pairs(tHourTime) do
    			if #nHour ==0 or k == #tHourTime then
    				break
    			else
    				if tonumber(nHour) >= 0 then
    					table.insert(arrnHourTime, tonumber(nHour))
    				end
    			end
    		end
    		return arrnHourTime
		end
		local arrLoadKey = {}
	    for sKey,tAndroidCfg in pairs(PublicRedis.arrAndroidCfg) do
	    	nKeyCnt = nKeyCnt + 1 
	    	local isLoad = false
	    	if not tAndroidCfg.nGroupId then  
	    		isLoad = true 
	    	else
	    		local nUpdateTime = (os.time() - tAndroidCfg.nUpdateTime) 
	    		if nUpdateTime >= nLoadKeyCfgTime then 
	    			isLoad = true  
	    		else
			    	if isLoad and math.random(1,50) >= nLoadKeyCfgProbability then 
			    		isLoad = false 
			    	end 
	    		end 
	    		if isLoad and tAndroidCfg.isRemove then 
	    			isLoad = false 
	    		end 
	    	end  
	    	if bOneLoad then  
	    		isLoad = true 
	    	end 
	    	if isLoad then 
	    		table.insert(arrLoadKey,sKey)
	    	end  
	    end   
	    if #arrLoadKey == 0 then 
	    	return 
	    end 
	    for k,sKey in pairs(arrLoadKey) do
        	local t = tRedis:hgetall(sKey)      
        	if t and t.nGroupID and t.nGameID and t.nRoomID and t.nMaxCount and t.nMinCount and t.nTime then 
        		local tCfg = {}
		        tCfg.nGroupId = tonumber(t.nGroupID)
		        tCfg.nGameId = tonumber(t.nGameID)
		        tCfg.nRoomId = tonumber(t.nRoomID)
				tCfg.nMaxCount =tonumber(t.nMaxCount)   
				tCfg.nMinCount =tonumber(t.nMinCount)  
				tCfg.arrHourTime = _GetTime(t.nTime)		        
		        tCfg.nUpdateTime = os.time() 
		    	tCfg.isRemove = false     -- 是否 删除key 
		    	PublicRedis.arrAndroidCfg[sKey] = tCfg
		    else
		    	if PublicRedis.arrAndroidCfg[sKey] and not PublicRedis.arrAndroidCfg[sKey].isRemove then 
		    		PublicRedis.arrAndroidCfg[sKey].isRemove = true     -- 是否 删除key 
	    			tBase.Log("_LoadKeyCfg  删除sKey: %s  ",sKey)  
		    	end 
		    end  
	    end
	    nKeyCfgTime = tBase.GetTime()-nTime   
	    tBase.Log("_LoadKeyCfg  arrKeys_%d  arrLoadKey: %d  nKeyCfgTime_%d   ",nKeyCnt,#arrLoadKey,nKeyCfgTime)  
    	return
	end 

 	local function _RemoveAndroidCount()  
 		if bOneLoad then return end  
		local nTime = tBase.GetTime() 
		local arrDelKey = {}
		local nRemoveCnt = 0
		local arrRemoveKey = {}
	    for sConfigKey,tAndroidCfg in pairs(PublicRedis.arrAndroidCfg) do
	    	if tAndroidCfg and tAndroidCfg.isRemove then 
			    table.insert(arrRemoveKey,sConfigKey)	
	    		nRemoveCnt = nRemoveCnt + 1
	    	end  
	    end 
	    if #arrRemoveKey == 0 then 
	    	return
	    end 
		local tRedis1 = tBase.m_MyRedisData[1].redis 
	    for k,sConfigKey in pairs(arrRemoveKey) do 
	    	local tAndroidCfg = PublicRedis.arrAndroidCfg[sConfigKey]
	    	if tAndroidCfg and tAndroidCfg.nGroupId and tAndroidCfg.nGameId and tAndroidCfg.nRoomId then 
	    		local sKey =string.format("GameAndroidCount_GroupId_%d:GameId_%d:RoomId_%d",tAndroidCfg.nGroupId,tAndroidCfg.nGameId,tAndroidCfg.nRoomId)
	    		if not tRedis1:exists(sKey) then 
			       table.insert(arrDelKey,sConfigKey)
			        tBase.Log("_RemoveAndroidCount Redis is nil sKey_%s ",sKey) 
	    		else
			        local nCnt =tonumber(tRedis1:get(sKey)) or 0
			        local nCount = 0
			        if nCnt and tonumber(nCnt) ~= 0 then     
			            if nCnt > 5 then 
			                nCount = math.random(1,5)
			            else
			                nCount = nCnt
			            end 
			            local nUserCount= tRedis1:incrby(sKey,-nCount) or 0
			            tBase.Log("_RemoveAndroidCount   nUserCount_%d  sKey_%s ",nUserCount,sKey) 
			        else
			        	tBase.Log("_RemoveAndroidCount nCnt_%d sKey_%s   ",nCnt,sKey) 
		                tRedis1:del(sKey)
		                table.insert(arrDelKey,sConfigKey)
			        end 
	    		end 
	    	else
			    table.insert(arrDelKey,sConfigKey)
	    	end 
	    end
	    for k,sConfigKey in pairs(arrDelKey) do
	    	tBase.Log("_RemoveAndroidCount  删除sKey: %s  ",sConfigKey)  
	    	PublicRedis.arrAndroidCfg[sConfigKey] = nil  
	    end
	    nRemoveTime = tBase.GetTime()-nTime   
	    tBase.Log("_RemoveAndroidCount arrDelKey_%d nRemoveKeyCnt_%d  nRemoveTime_%d  ",#arrDelKey,nRemoveCnt,nRemoveTime)  
	    return
	end 

	local function _AndroidCountLogic()
		local nTime = tBase.GetTime() 
	    local arrGameId = {}
		for k,nGameType in pairs(PublicRedis.tGameType) do
			arrGameId[nGameType] = true  
		end		
		local function _GetAndroidCnt(nAndroidsCnt,nAndroidCfgCnt)
		    local nCnt = 0    -- 增加或者减少机器人数量  
		    if nAndroidsCnt > nAndroidCfgCnt then  
		        if (nAndroidsCnt - nAndroidCfgCnt) > 5 then 
		            nCnt = math.random(1,10) 
		        else
		            nCnt = nAndroidsCnt - nAndroidCfgCnt
		        end 
		        nCnt = -nCnt  -- 减少 
		    elseif nAndroidsCnt < nAndroidCfgCnt then 
		        if (nAndroidCfgCnt - nAndroidsCnt) > 10 then 
		             nCnt = math.random(1,10) 
		        else
		             nCnt = nAndroidCfgCnt - nAndroidsCnt
		        end          
		    elseif nAndroidCfgCnt == 0 and  nAndroidsCnt > 0 then 
		        if nAndroidsCnt > 10 then 
		             nCnt = math.random(1,10)            
		        else
		            nCnt = math.random(1,nAndroidsCnt) 
		        end        
		        nCnt = -nCnt  -- 减少 
		    end  
		    return nCnt						 
		end 
		local arrAddKey = {}
	    for sKey,tAndroidCfg in pairs(PublicRedis.arrAndroidCfg) do		 	    	
	    	if tAndroidCfg and not tAndroidCfg.isRemove and not arrGameId[tAndroidCfg.nGameId] then  -- 合集游戏 
				if #tAndroidCfg.arrHourTime > 0 and math.random(1,50) >= nAddCntProbability then 
					table.insert(arrAddKey,sKey)
				end   
	    	end 
	    end
	    if #arrAddKey == 0 then 
	    	return 
	    end 
	    for k,sKey in pairs(arrAddKey) do
	    	local tAndroidCfg = PublicRedis.arrAndroidCfg[sKey]
	    	if tAndroidCfg and tAndroidCfg.nGroupId and tAndroidCfg.nGameId and tAndroidCfg.nRoomId then 
				local nHour = tonumber(os.date("%H"))
				for k,v in pairs(tAndroidCfg.arrHourTime) do
					if nHour == v then 
		    			local nAndroidsCnt = PublicRedis._GetGameAndroidCount(tAndroidCfg.nGroupId,tAndroidCfg.nGameId,tAndroidCfg.nRoomId)  -- 获取当前机器人数量	
						local nAndroidCfgCnt = math.random(tAndroidCfg.nMinCount,tAndroidCfg.nMaxCount) 	  -- 获取机器人数量配置
				    	local nCnt = _GetAndroidCnt(nAndroidsCnt,nAndroidCfgCnt)   -- 增加或者减少机器人数量 
						local nNewCount = PublicRedis._SetGameAndroidCount(tAndroidCfg.nGroupId,tAndroidCfg.nGameId,tAndroidCfg.nRoomId,nCnt)  
						break
					end 
				end	    	
			end 
	    end
	    nLogicTime = tBase.GetTime()-nTime  
	    -- tBase.Log("_AndroidCountLogic  arrKeys_%d  nLogicTime_%d  ",nKeyCnt,nLogicTime)  
	end  
    local function func() 
    	if not _LoadKey() then 
	    	tBase.SetTimer(65002, 1000 * SetingConfig.SetUserNumber, -1, PublicRedis._TimerAndroidPeople)  -- 非百人游戏 数量 
	    	tBase.Log("_TimerAndroidPeople  arrKeys_%d  没有机器人配置",nKeyCnt)  
    		_RemoveAndroidCount()
	    	return  
    	end 
    	_LoadKeyCfg()      	
    	_AndroidCountLogic()
    	_RemoveAndroidCount()
	    tBase.SetTimer(65002, 1000 * SetingConfig.SetUserNumber, -1, PublicRedis._TimerAndroidPeople)  -- 非百人游戏 数量  
	    local nAllTime = tBase.GetTime()-nStartTime
    	tBase.Log("_TimerAndroidPeople  nKeyCnt_%d  LoadKey: %d,LoadCfg: %d,nLogicTime: %d,nRemoveTime: %d,总耗时:%d毫秒"
    	,nKeyCnt,nKeyTime,nKeyCfgTime,nLogicTime,nRemoveTime,nAllTime)  
    end     
    xpcall(func,tpLog)  
    -- func()
    return 
end

--合集 非百人游戏 机器人配置
function PublicRedis._GetHJAndroidCount(nGroupId,nGameId,nRoomId) 
	return tRedisCahche._LiveAndroidCount(nGroupId,nGameId,nRoomId)
end

--机器人 信息(头像路径，头像最小范围，头像最大范围，最小局数，最大局数，休息时间，生成机器人数)
function PublicRedis._GetAndroidBasicConfig(nGroupId)
	return tRedisCahche._GetAndroidBasicConfig(nGroupId)
end
 
--  机器人数量    动态数量 
function PublicRedis._GetGameAndroidCount(nGroupId,nGameId,nRoomId)
    return tRedisCahche._GetGameAndroidCount(nGroupId,nGameId,nRoomId)
end

--  机器人数量    动态数量
function PublicRedis._SetGameAndroidCount(nGroupId,nGameId,nRoomId,nCnt)
    local sKey =string.format("GameAndroidCount_GroupId_%d:GameId_%d:RoomId_%d",nGroupId,nGameId,nRoomId)
    local tRedis = tBase.m_MyRedisData[1].redis 
    local nAndroidCnt = tRedis:incrby(sKey,nCnt) or 0
    if nAndroidCnt <= 0 then 
    	if nAndroidCnt < 0 then 
    		-- tBase.Log("_SetGameAndroidCount  ErrorMsg  sKey_%s nAndroidCnt_%d  ",sKey,nAndroidCnt)
    	end 
    	tRedis:del(sKey)
    	nAndroidCnt = 0
    end     
    tBase.Log("_SetGameAndroidCount  sKey_%s nAndroidCnt_%d  nCnt_%d ",sKey,nAndroidCnt,nCnt)
    return tonumber(nAndroidCnt) 
end

--  获取 游戏中 玩家人数  
function PublicRedis._GetGameCenterUserCount(nGroupId,nGameId,nRoomId)
	return tRedisCahche._GetGameCenterUserCount(nGroupId,nGameId,nRoomId) 
end

--  游戏真人数量  
function PublicRedis._UpdateGameCenterUserCount(nGroupId,nGameId,nRoomId,nCnt)
	assert(nGroupId~= nil," nGroupId is nil ")
	assert(nGameId~= nil," nGameId is nil ")
	assert(nRoomId~= nil," nRoomId is nil ")
    local sKey =string.format("GameCenterUserCount_GroupId_%d:GameId_%d:RoomId_%d",nGroupId,nGameId,nRoomId)
    local tRedis = tBase.m_MyRedisData[1].redis 
    local nUserCount= tRedis:incrby(sKey,nCnt) or 0
    if nUserCount == 0 then 
    	tRedis:del(sKey)
    end  
    return tonumber(nUserCount) 
end
 
-- 庄闲下注是否互斥, true:是 false:否
-- nGroupId:分组id
function PublicRedis.IsBetExclusive(nGroupId,nGameId)
	return tRedisCahche.IsBetExclusive(nGroupId,nGameId)
end

local function idiv(a, b)
    return math.floor(a / b)
end

local function _NumberToStrID(N)
	local arr ={}
	local m=nil
	for i=1,2 do
		m, N = N % 10, idiv(N, 10) -- m,N =N%10,N//10
		table.insert(arr,1,48+m)
	end
	for i=1,1 do
		m,N =N%26,idiv(N,26) --m,N =N%26,N//26
		table.insert(arr,1,65+m)
	end
	return string.char(table.unpack(arr))
end

local function _GetSerieslNum(nServerId,sKey)
	local scrip =[[
		local sKey =ARGV[1]
		local sField =ARGV[2]
		local sFieldOfEnd ="EndNum"
		local nCurVal =redis.call("hincrby",sKey,sField,1)
		local arrVal =redis.call("hvals",sKey) or {}
		local nEndNum =tonumber(redis.call("hget",sKey,sFieldOfEnd)) or 0
		if nCurVal==1 and #arrVal==1 then
			redis.call("expire",sKey,25*60*60)
		end
		local arrNum ={}
		for _,sVal in ipairs(arrVal) do
			table.insert(arrNum,tonumber(sVal))
		end
		local nMaxVal =math.max(unpack(arrNum))
		if nMaxVal>nCurVal then
			nCurVal =nMaxVal
			redis.call("hset",sKey,sField,nCurVal)
		end
		if nCurVal<=nEndNum then
			nCurVal =nEndNum +1
			redis.call("hset",sKey,sField,nCurVal)
		end
		return nCurVal
	]]
	local sField =string.format("%d",nServerId)
	local redis =tBase.m_MyRedisData[2].redis
	local nRlt =redis:eval(scrip,0,sKey,sField)
	return nRlt
end

local function _EndSerieslNum(nServerId,sKey)
	local scrip =[[
		local sKey =ARGV[1]
		local sField =ARGV[2]
		local sFieldOfEnd ="EndNum"
		local nCurNum =tonumber(redis.call("hget",sKey,sField)) or 0
		local nEndNum =tonumber(redis.call("hget",sKey,sFieldOfEnd)) or 0
		local nMaxNum =math.max(nCurNum,nEndNum)
		redis.call("hset",sKey,sFieldOfEnd,nMaxNum)
		return nMaxNum
	]]
	local sField =string.format("%d",nServerId)
	local redis =tBase.m_MyRedisData[2].redis
	local nRlt =redis:eval(scrip,0,sKey,sField)
	return nRlt
end



--飞行棋小游戏用于期号生成(不包括斗棋)
function PublicRedis.GetSerieslNum(sTableName,nServerId)
	local sDate =os.date("%y%m%d", os.time())
	local sKey =string.format("PilotSmallGame_%s_%s",sDate,sTableName)
	local nRlt =_GetSerieslNum(nServerId,sKey)
	local str =string.format("%s%s%s",sDate,sTableName,_NumberToStrID(nRlt))
	return str
end
function PublicRedis.EndSerieslNum(sTableName,nServerId)
	local sDate =os.date("%y%m%d", os.time())
	local sKey =string.format("PilotSmallGame_%s_%s",sDate,sTableName)
	local nRlt =_EndSerieslNum(nServerId,sKey)
	local str =string.format("%s%s%s",sDate,sTableName,_NumberToStrID(nRlt))
	return str
end


--用于斗棋期号生成
function PublicRedis.GetSerieslNumOfDouQi(sTableName,nServerId)
	local nServerId =nServerId or tSrvInfo.nServerId
	local sDate =os.date("%y%m%d", os.time())
	local sKey =string.format("PilotSmallGameDouQi_%s_%s",sDate,sTableName)
	local nRlt =_GetSerieslNum(nServerId,sKey)
	local str =string.format("%s%sA%s",sDate,sTableName,_NumberToStrID(nRlt))
	return str
end
function PublicRedis.EndSerieslNumOfDouQi(sTableName,nServerId)
	local nServerId =nServerId or tSrvInfo.nServerId
	local sDate =os.date("%y%m%d", os.time())
	local sKey =string.format("PilotSmallGameDouQi_%s_%s",sDate,sTableName)
	local nRlt =_EndSerieslNum(nServerId,sKey)
	local str =string.format("%s%sA%s",sDate,sTableName,_NumberToStrID(nRlt))
	return str
end


function PublicRedis.GetValByGameID(sName, nShopID, nGameID, nDefaultVal)

	local sRedisName = 'Group_'..nShopID..'_'..nGameID..'_'..sName

	tBase.Log('PublicRedis.GetValByGameID, sName:'..sRedisName)
	local sVal = tBase.m_MyRedisData[2].redis:hget("50F3DF333BB14C9AA7B51EAA8D0A18C7_Control", sRedisName)
	if sVal ~= nil then
		tBase.Log('PublicRedis.GetValByGameID, sName:'..sRedisName..', Val:'..sVal)
		return tonumber(sVal)
	end

	return nDefaultVal
end

--生成一个唯一订单号(结算后用于修改订单状态)
function PublicRedis.CreateBetId()
	local scrip =[[
		local sKey ="ForBetIdCreate"
		local nFieldPrefixValue =ARGV[1]
		redis.call("hsetnx",sKey,"Prefix",nFieldPrefixValue)
		local IncrIdValue =redis.call("hincrby",sKey,"IncrId",1)
		local Prefix =redis.call("hget",sKey,"Prefix")
		local s =string.format("%d%d",tonumber(Prefix),tonumber(IncrIdValue))
		return tonumber(s)
	]]
	local redis =tBase.m_MyRedisData[2].redis
	local rlt =redis:eval(scrip,0,os.time()%100000000)
	return rlt
end

-- 检查主播是否已绑定 
function PublicRedis._CheckIsLiveBingding(nGroupId,nLiveUserID)
	local sKey = "APIOpenTale_*"
    local tRedis = tBase.m_MyRedisData[2].redis
    local arrTableInfo = tRedis:keys(sKey)
    for k,sTableId in pairs(arrTableInfo) do
        local tInfo = tRedis:hgetall(sTableId)
        if tInfo  and tonumber(tInfo.nTableType) ~= 1 and tonumber(tInfo.nGroupId) == nGroupId and tonumber(tInfo.nLiveUserID) ~= 0 and  tonumber(tInfo.nLiveUserID) == nLiveUserID then 
    		tBase.Log("_CheckIsLiveBingding nGroupId_%d  nLiveUserID_%d 已绑定 sTableId_%s ",nGroupId,nLiveUserID,sTableId) 			
			return sTableId	
        end 
    end	
	return nil 
end
 

-- 获取直播 下播解绑时间（秒）
function PublicRedis.GetLiveTheSowingTime(nGroupId)
    return tRedisCahche.GetLiveTheSowingTime(nGroupId)	
end

--数据库会话使用的时区配置
function PublicRedis.GetTimeZone(nGroupId)
	local sDefaultKey ="TimeZone:Default"
    local sKey =string.format("TimeZone:GroupId_%d",nGroupId)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sTimeZone = tRedis:get(sKey)
	sTimeZone =sTimeZone or tRedis:get(sDefaultKey)
	return sTimeZone or "+8:00"	
end

function PublicRedis.IncrTableStatus(sTableId)
	local tRedis = tBase.m_MyRedisData[1].redis 
	local sKey =string.format("PilotTableStatus_%s",sTableId)
	local scrip =[[
		local n =redis.call("incr",ARGV[1])
		redis.call("expire",ARGV[1],180)
		return n
	]]
	local nStatus =tRedis:eval(scrip,0,sKey)
	return nStatus
end

function PublicRedis.GetTableStatus(sTableId)
	local tRedis = tBase.m_MyRedisData[1].redis 
	local sKey =string.format("PilotTableStatus_%s",sTableId)
	local sVal = tRedis:get(sKey)
	return tonumber(sVal)
end

-- 更新牌局
function PublicRedis._UpdateLivePaiJuStartTime(sTableId,sPaiJuId)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
    local tTableInfo = tRedis:hgetall(sKey)
    if tTableInfo and tTableInfo.nGameId then 
		local t ={sPaiJuId=sPaiJuId,sPaiJuIdStartTime=os.time(),sPaiJuIdStartDate=os.date("%Y-%m-%d %H:%M:%S")}
		if not tRedis:hmset(sKey,t) then 
	    	tBase.Log("ErrorMsg  _UpdateLivePaiJuStartTime  sKey_%s Hmset error nResult_%s ",sKey,nResult) 			
		end 
	end 
	return 
end

--保存德州回顾记录
function PublicRedis._SaveTexasReview(sPaiJuId,sJsonData)
	local sKey =string.format("TexasReview_%s",os.date("!%Y_%m"))		--日期使用0时区(符号!,表示使用0时区)
	local tRedis =tBase.m_MyRedisData[2].redis
	tRedis:hset(sKey,sPaiJuId,sJsonData)
end
--获取德州回顾记录
function PublicRedis._GetTexasReview(sPaiJuId)
	local nNowTime =os.time()
	local tRedis =tBase.m_MyRedisData[2].redis
	for i=1,3 do		--至少能获取到最近两个月的记录
		local sKey =string.format("TexasReview_%s",os.date("!%Y_%m",nNowTime))
		local sReview =tRedis:hget(sKey,sPaiJuId)
		if sReview then
			return sReview
		end
		nNowTime =nNowTime -(24*3600*25)
	end
end

function PublicRedis._UpdateCurPaiJu(sTableId,sCurPaiJu)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis

	if not tRedis:exists(sKey) then
		return
	end
	if sCurPaiJu then
		local t ={sCurPaiJu=sCurPaiJu}
		tRedis:hmset(sKey,t)
	else
		tRedis:hdel(sKey,"sCurPaiJu")
	end
end



-- 退款  牌局 玩家下注数据  tBetInfo={nArea=0,nBet=0}  (庄家={全部区域下注详细})
function PublicRedis._AddPaiJuRefundBetInfo(sTableId,sPaiJuId,nUserId,tBetInfo)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("TablePaiJuUserBetInfo_%s_%s",sTableId,sPaiJuId)
	local sFieldKey =string.format("%d",nUserId)

	tBetInfo = cjson.encode(tBetInfo)
	local sResult = tRedis:hset(sKey,sFieldKey,tBetInfo)
	if not sResult and sResult == 'false'  then
    	tBase.Log("ErrorMsg  _AddPaiJuRefundBetInfo sKey_%s nUserId_%d %s  Hset error sResult_%s ",sKey,nUserId,tBetInfo,sResult) 	    	 
	end 
	tBase.m_MyRedisData[2].redis:expire(sKey,5*24*60*60)
	return  
end

-- 获取与 删除  牌局 玩家下注数据  
function PublicRedis._GetPaiJuRefundBetInfo(sTableId,sPaiJuId)
	local sKey =string.format("TablePaiJuUserBetInfo_%s_%s",sTableId,sPaiJuId)
	local arrBetInfo = tBase.m_MyRedisData[2].redis:hgetall(sKey)
	tBase.m_MyRedisData[2].redis:del(sKey)
    tBase.Log("_GetPaiJuRefundBetInfo  1s del sKey_%s ",sKey)
	return arrBetInfo
end

-- 删除玩家 下注数据 
function PublicRedis._DelUserBetInfo(sTableId,sPaiJuId,nUserId)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("TablePaiJuUserBetInfo_%s_%s",sTableId,sPaiJuId)
	if nUserId==nil then
		return tRedis:del(sKey)
	end
    tBase.Log("_DelUserBetInfo  sKey_%s nUserId_%d   ",sKey,nUserId) 
	return tRedis:hdel(sKey,nUserId)
end


-- 设置玩家跟投 
function PublicRedis._SetUserWithCast(nUserId,sTableId)
	local sLockName = string.format("LockUserWithCast_nUserId_%d",nUserId)
	local f = function()
		local sKey = string.format("UserWithCast_nUserId_%d",nUserId)
		tBase.m_MyRedisData[1].redis:hset(sKey,sTableId,1)		
    	tBase.Log("_SetUserWithCast  sKey_%s sTableId_%s ",sKey,sTableId) 
	end
	PublicLock(sLockName,f)
    return 
end

-- 检查玩家是否跟投
function PublicRedis._CheckUserWithCast(nUserId,sTableId)
	local sLockName = string.format("LockUserWithCast_nUserId_%d",nUserId)
	local bResult = false
	local f = function()
		local sKey = string.format("UserWithCast_nUserId_%d",nUserId)
		if sTableId then 
			local nWithCast=tBase.m_MyRedisData[1].redis:hget(sKey,sTableId)	
			if tonumber(nWithCast) == 1 then 
				bResult = true 
	    		tBase.Log("_CheckUserWithCast  sKey_%s sTableId_%s  is true ",sKey,sTableId) 
			else
	    		tBase.Log("_CheckUserWithCast  sKey_%s sTableId_%s is false ",sKey,sTableId) 
			end 
	    else
			bResult=tBase.m_MyRedisData[1].redis:exists(sKey)			
	    end 
	end
	PublicLock(sLockName,f)
    return bResult
end

-- 删除玩家跟投 
function PublicRedis._RemoveUserWithCast(nUserId,sTableId)
	local sLockName = string.format("LockUserWithCast_nUserId_%d",nUserId)
	local isRemoveKey = false
	local f = function()
		if not sTableId then 
			isRemoveKey = true 
			sTableId = "isRemoveKey"
		end 
		local sKey = string.format("UserWithCast_nUserId_%d",nUserId)
		if isRemoveKey then 
			tBase.m_MyRedisData[1].redis:del(sKey)
		else
			tBase.m_MyRedisData[1].redis:hdel(sKey,sTableId)
		end 
    	-- tBase.Log("_RemoveUserWithCast  sKey_%s sTableId_%s ",sKey,sTableId) 
	end
	PublicLock(sLockName,f)
	return isRemoveKey
end

--返回布尔值,成功:true 失败:false
function PublicRedis.PilotSmallGameMutalWrite(sTableId,sPaiJuId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("PilotSmallGame:%s:%s",sTableId,sPaiJuId)
	local rlt = tRedis:setnx(sKey,"1")	--返回布尔值
	if rlt then
		tRedis:expire(sKey,60)
	end
	return rlt
end

--返回:最近一次玩家进入合集游戏的时间戳
function PublicRedis.NotLiveGameEnterTimeStamp(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey ="UsersNotLiveGameEnterTimeStamp"
	local sField =string.format("%d",nUserId)
	local nTimeStamp =tonumber(tRedis:hget(sKey,sField)) or 0
	return nTimeStamp
end

-- 飞行棋 是否 关闭机器人 
function PublicRedis._GetPilotAndroidStop(nGroupId,nGameId)
    local sKey =string.format("PilotAndroidStop_GroupId_%d_nGameId_%d",nGroupId,nGameId)
	return tBase.m_MyRedisData[2].redis:exists(sKey)
end
function PublicRedis.SetNotLiveGameEnterTimeStamp(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey ="UsersNotLiveGameEnterTimeStamp"
	local sField =string.format("%d",nUserId)
	local nValue =os.time()
	tRedis:hset(sKey,sField,nValue)
end

-- 获取全部直播牌桌 主播ID 
function PublicRedis._CheckLiveTableIsBingDing(nLiveUserID)
    local sKey = "APIOpenTale_*"
    local tRedis = tBase.m_MyRedisData[2].redis
    local arrTableInfo = tRedis:keys(sKey)
    if #arrTableInfo == 0 then return end 
    local arrLiveUserID = {}
    for k,sTableId in pairs(arrTableInfo) do
        local tTableInfo = tRedis:hgetall(sTableId)
	   if tTableInfo and tTableInfo.nLiveUserID and tTableInfo.nGameId ~= 133 and tTableInfo.nLiveUserID == nLiveUserID  then
        	return tTableInfo.sTableId 
        end 
    end
    return 
end

--主播转让给飞行员 ，更换主播ID
function PublicRedis.ChangeLiverID(sTableId,nNewLiverUserId)
	local sKey = string.format("APIOpenTale_%s",sTableId)
	local tRedis = tBase.m_MyRedisData[2].redis
	Base.m_MyRedisData[2].redis:hmset(sKey, {nLiveUserID=nNewLiverUserId})
end

-- 获取飞行棋 游戏配置 : nCfgType:  1 赏金配置  2抽水配置 3: 机器人策略开关 4: 策略2, 5: 多人模式奖池分配配置
function PublicRedis._GetPilotGameConfig(nGroupId,nCfgType)
	return tRedisCahche._GetPilotGameConfig(nGroupId,nCfgType)
end

-- 获取砍树 游戏配置 : nCfgType:  1 基本配置(入场费,最大秒数,每节树干分数)
function PublicRedis._GetFellTreeGameConfig(nGroupId,nRoomId,nCfgType)
	return tRedisCahche._GetFellTreeGameConfig(nGroupId,nRoomId,nCfgType)
end

-- 获取篮球 游戏配置 : nCfgType:  1 基本配置(入场费,最大秒数,每个球分数)
function PublicRedis._GetBasketballGameConfig(nGroupId,nRoomId,nCfgType)
	return tRedisCahche._GetBasketballGameConfig(nGroupId,nRoomId,nCfgType)
end

--获取飞行棋底分配置 五个底分和最大最小底分
function PublicRedis.Get_PilotGameBaseScoreConfig(nGameId,nGroupId)
	return tRedisCahche.Get_PilotGameBaseScoreConfig(nGameId,nGroupId)
end
 
--强制踢人状态: nKickStatus: 0 正在踢人 ，1 踢人完成,2 删除强制踢人数据  3: 获取踢人,
-- 4:比赛游戏没开始不能强制踢人
function PublicRedis.SetPilotKickUser(nUserId,nStatus)
	local sKey = string.format("PilotTableKickUser_%d",nUserId)
	local tRedis = tBase.m_MyRedisData[1].redis
	if nStatus == 3 then
		return tRedis:exists(sKey)
	end
	if nStatus == 0 then 
		tRedis:hmset(sKey,{nKickUserId=nUserId,nKickStatus=0,nKickStartTime=os.time()})
		tRedis:expire(sKey,2)
	elseif nStatus == 1 then 
		tRedis:hmset(sKey,{nKickEndTime=os.time()})
		tRedis:hset(sKey,"nKickStatus",nStatus)
	elseif nStatus == 2 then 
		tRedis:del(sKey)
	elseif nStatus == 4 then  
		tRedis:hset(sKey,"nKickStatus",nStatus)
		tRedis:expire(sKey,2)   -- 3秒过期
	elseif nStatus == 5 then  
		tRedis:expire(sKey,2)   -- 3秒过期
	end 
	if nStatus ~= 2 then 
		tBase.Log("_SetPilotKickUser sKey_%s nUserId_%d   %d=[0:正在踢人,1:踢人完成,2:删除]  ",sKey,nUserId or 0,nStatus)
	end 
	return 
end  
--飞行棋竞猜游戏 飞行员竞猜额度配置筹码
--返回示例:{100,250,500,1000，2000}
--注意:如果返回nil,表示没有任何设置,请自行处理该情况
--nType: 1 游戏额度筹码配置  2 下注限制筹码配置
function PublicRedis.Get_PilotGuessAmountChips(nGameId,nGroupId,nType)
	return tRedisCahche.Get_PilotGuessAmountChips(nGameId,nGroupId,nType)
end 

--机器人金币范围设置信息.
--返回示例 :{{20,100,1000},{60,100,10000},{20,10000,20000}}
function PublicRedis.GetAndroidGoldConfig(nGroupId)
	return tRedisCahche.GetAndroidGoldConfig(nGroupId)  
end
 
-- 更新比赛牌桌 状态 与 比赛数据：  nType: 
function PublicRedis._UpdateMatchTableData(sTableId,tData)
	local sKey= string.format("PilotMatchTableData_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[1].redis 
	if not tRedis:hmset(sKey,tData) then 
    	tBase.Log("_UpdateMatchTableData  sKey_%s Hmset error  ",sKey) 			 
	end 	
	tRedis:expire(sKey,60*60*6)  -- 保留  一天
	if tData.nTableStatus and tData.nTableStatus ~=3 then 
		local sKey = string.format("APIOpenTale_%s",sTableId)
		local tRedis = tBase.m_MyRedisData[2].redis
		tRedis:hmset(sKey,{nTableStatus=tData.nTableStatus})
	end 
	return 
end

-- 更新牌桌状态 
function PublicRedis._UpdateTableStates(sTableId,nTableStatus)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis = tBase.m_MyRedisData[2].redis
	if tRedis:exists(sKey) then 
		tRedis:hmset(sKey,{nTableStatus= nTableStatus})   
    	tBase.Log("_UpdateTableStates  sKey_%s nTableStatus_%d  ",sKey,nTableStatus)   	  		 
	end 	  
	return 
end

-- 获取牌桌关桌状态:  nCloseTableStatus : 0 正常,1 正在关桌中
function PublicRedis._GetCloseTableStates(sTableId)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis = tBase.m_MyRedisData[2].redis
	local nCloseTableStatus =  tRedis:hget(sKey,"nCloseTableStatus")  or 1  
    -- tBase.Log("_GetCloseTableStates  sKey_%s nCloseTableStatus_%d  ",sKey,nCloseTableStatus)   
	return tonumber(nCloseTableStatus)
end
 
--保存飞行棋机器人数据
function PublicRedis.SaveAndroidInfo(Data)
	local androidUser = Data
	if androidUser ~= nil then
		local My_2 = tBase.m_MyRedisData[2].redis 
		tBase.Log("AnItem_%d",androidUser.nUserId)
		local BetLimit = {}
		local AndroidInfo = PublicRedis.GetRedisAndroidInfo(math.floor(androidUser.nUserId))
		if AndroidInfo then
			AndroidInfo.nGold=androidUser.nGold
			AndroidInfo.nLose=androidUser.nLose
			AndroidInfo.nWin=androidUser.nWin
			AndroidInfo.nSimilar=androidUser.nSimilar
			PublicRedis.SetRedisAndroidInfo(AndroidInfo)
			tBase.Log("飞行棋保存机器人数据信息 nUserId_%d nGold_%f nLose_%d nWin_%d ",androidUser.nUserId,androidUser.nGold,androidUser.nLose,androidUser.nWin)
			return true
		else
			return false
		end
	else
		return false
	end
end
 
--通知转账地址与一些配置
function PublicRedis.GetTransferNotifyInfo(nGroupId)
	return tRedisCahche.GetTransferNotifyInfo(nGroupId)
end

--获取Web服的用户离线信息 nType: 1:添加 2：获取 3：删除
function PublicRedis.OffLineUserInfo(nType,nUserId,sJsonData)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = "OffLineUserInfo"
	if nType == 1 then
		redis:hmset(sKey, {[nUserId]=sJsonData})
	elseif nType == 2 then
		local arrSubKeys = redis:hkeys(sKey)
		local tDataInfo = {}
		if arrSubKeys and #arrSubKeys > 0 then
			--tBase.LogT("OffLineUserInfo_arrSubKeys_",arrSubKeys)
			for _,sUserId in pairs(arrSubKeys) do
				local nUserId = tonumber(sUserId)
				if nUserId then
					local sJsonData = redis:hget(sKey,nUserId)
					if sJsonData then
						--	table.insert(tData,sJsonData)
						tDataInfo[nUserId] = cjson.decode(sJsonData)
					end
				end
			end
		end
		tBase.LogT("OffLineUserInfo_tDataInfo_",tDataInfo)
		return tDataInfo
	elseif nType == 3 then
		if nUserId then 
			redis:hdel(sKey,nUserId)
		end
	end
end

-- 检查是否已经参加 比赛了
function PublicRedis.CheckPilotUserJoinMatch(arrMathUserId)
    local sKey = "APIOpenTale_*"
    local tRedis = tBase.m_MyRedisData[2].redis
    local arrTableInfo = tRedis:keys(sKey)
    if #arrTableInfo == 0 then return false end 
    local arrMatchTable = {}
    for k,sTableId in pairs(arrTableInfo) do
        local tTableInfo = tRedis:hgetall(sTableId)
        tTableInfo.sTableId = sTableId
	    if tTableInfo and tTableInfo.sConfig and tonumber(tTableInfo.nTableType) == 3 then
	    	table.insert(arrMatchTable,tTableInfo)
        end 
    end 
    if #arrMatchTable == 0 then return false end 
    for _,tTableInfo in pairs(arrMatchTable) do
    	local sRuleDetail = cjson.decode(tTableInfo.sConfig) 
		if not sRuleDetail.arrMathUserId or #sRuleDetail.arrMathUserId == 0 then return false end 
    	for _,nUserId in pairs(sRuleDetail.arrMathUserId) do
    		for _,v in pairs(arrMathUserId) do
    			if tonumber(nUserId) == v then 
    				return true,tTableInfo.sTableId
    			end 
    		end
    	end	
    end
	return false
end

--_GameId_%d:GroupId_%d

--机器人在桌子开始后多少局开始进入
function PublicRedis.InnRangeOfAndroidEnter(nGameId,nGroupId)
	return tRedisCahche.InnRangeOfAndroidEnter(nGameId,nGroupId)
end



local function isTexasConfigItemLegal(arr)
	for _,v in ipairs(arr) do
		if v<=0 then return false end
	end
	if #arr<4 then return false end
	local nSmallBlind =arr[1]
	local nBigBlind =arr[2]
	local nBuyMin =arr[3]
	local nBuyMax =arr[4]

	if nBigBlind <nSmallBlind then
		return false
	end
	if nBuyMax <nBuyMin then
		return false
	end
	if nBuyMin <nBigBlind then
		return false
	end
	return true
end

--德州桌子配置
function PublicRedis.GetTexasConfig(nGroupId,nRoomId)
	return tRedisCahche.GetTexasConfig(nGroupId,nRoomId)
end

--德州桌子 猜牌配置
function PublicRedis.GetTexasGuessConfig(nGroupId,nRoomId)
	return tRedisCahche.GetTexasGuessConfig(nGroupId,nRoomId)
end


-- 飞行棋对战路珠: nType: 1 获取, 2 保存   nWinLose:  0 输,1赢
function PublicRedis.PilotFightRoadBead(nType,nUserId,nWinLose)
	local sKey= string.format("PilotFightRoadBead_%s",nUserId)
	local tRedis =tBase.m_MyRedisData[2].redis 	
	if nType == 1 then 
		local arrWinLose = tRedis:lrange(sKey,0,-1) or {}
		return arrWinLose
	else
		local nlen = tRedis:llen(sKey)
		if nlen >= 30 then 
			for i=1,nlen - 29 do
				tRedis:rpop(sKey)  
			end
		end 
		tRedis:lpush(sKey,nWinLose)     -- 添加 
		tRedis:expire(sKey,60*60*24*7)  -- 保留 7天
	end 
	return 
end 

--获取洗牌所需金币
function PublicRedis.GetShuffleCardsCost(nGroupId,nGameId)
	return tRedisCahche.GetShuffleCardsCost(nGroupId,nGameId)
end


--持久化保存玩家投注锁信息
function PublicRedis.SetUserFollowBetLockInfo(nUserId,tData)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserFollowBetLockInfo_%d",nUserId)
	local sJsonData =cjson.encode(tData)
	redis:set(sKey,sJsonData)
end

--获取玩家投注锁信息
function PublicRedis.GetUserFollowBetLockInfo(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserFollowBetLockInfo_%d",nUserId)
	local sJsonData =redis:get(sKey)
	local tData =nil
	if sJsonData then
		tData= cjson.decode(sJsonData)
	end
	return tData
end

--持久化保存玩家可以跟投状态
function PublicRedis.SetCanFollowBetStatus(tData)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("CanFollowBetStatus_%d_%d",tData.nFromUserId,tData.nToUserId)--打赏玩家模式
	if tData.sLiveID and tData.sLiveID~="" then
		sKey = string.format("CanFollowBetStatus_%d_%d_%s",tData.nFromUserId,tData.nToUserId,tData.sLiveID)--打赏房间模式
	end
	local sValue = "timestamp:"..tData.sTimeTem.." Duration:"..tData.nSec.."s"
	redis:set(sKey,sValue)
	redis:expire(sKey,math.floor(tData.nSec))
end

--获取玩家可以跟投的状态（只要玩家解锁了某个玩家的跟投，在有效时间内都可以跟投，不管那位玩家中途是否切换跟投锁模式）
--@params nFromUserId 跟投玩家
--@params nToUserId 被跟投锁的玩家
--@params sLiveID 直播间id
function PublicRedis.GetCanFollowBetStatus(nFromUserId,nToUserId,sLiveID)
	local tLockInfo = PublicRedis.GetUserFollowBetLockInfo(nToUserId)
	if not tLockInfo or tLockInfo.nIsLock==0 then
		--没有跟投锁信息或者没开跟投锁
		return true
	end

	local redis =tBase.m_MyRedisData[2].redis
	local sKey1 = string.format("CanFollowBetStatus_%d_%d",nFromUserId,nToUserId) --打赏玩家模式
	local sKey2 = string.format("CanFollowBetStatus_%d_%d_%s",nFromUserId,nToUserId,sLiveID or "") --打赏房间模式
	local isCan = false
	local sResult1 = redis:get(sKey1)
	local sResult2 = redis:get(sKey2)
	if sResult1 then
		isCan = true
	elseif sResult2 then
		isCan = true
	end
	return isCan
end

--设置房间用户的共享等信息
function PublicRedis.SetRoomUserShareInfo(nGameId,sTableId,nUserId,tData)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local sSubKey =string.format("nUserId_%d",nUserId)
	local sJsonData =cjson.encode(tData)
	redis:hmset(sKey, {[sSubKey]=sJsonData})
	redis:expire(sKey,24*60*60) --设置key的生存时间为24小时
end

--批量设置房间用户的共享等信息
function PublicRedis.SetRoomUserShareInfoBatch(nGameId,sTableId,arrData)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local arrJson = {}
	for k,v in pairs(arrData) do
		local sSubKey =string.format("nUserId_%d",v.nUserId)
		local sJsonData =cjson.encode(v)
		arrJson[sSubKey] = sJsonData
		
		if v.sShopAcc~="" and v.sShopAcc~="0" then
			local sSubKey1 = string.format("sShopAcc_%s",v.sShopAcc)
			local sJsonData1 =cjson.encode({nUserId=v.nUserId})
			arrJson[sSubKey1] = sJsonData1
		end
	end
	redis:hmset(sKey, arrJson)
	redis:expire(sKey,24*60*60) --设置key的生存时间为24小时
end

--获取房间用户的共享等信息
function PublicRedis.GetRoomUserShareInfo(nGameId,sTableId,nUserId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local sSubKey =string.format("nUserId_%d",nUserId)
	local sJsonData =redis:hget(sKey,sSubKey)
	local tData =nil
	if sJsonData then
		tData= cjson.decode(sJsonData)
	end
	return tData
end

--根据第三方id设置房间用户的共享等信息
function PublicRedis.SetRoomUserShareInfoByShopAcc(nGameId,sTableId,sShopAcc,tData)
	if not sShopAcc or sShopAcc=="" or sShopAcc=="0" then
		return
	end
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local sSubKey =string.format("sShopAcc_%s",sShopAcc)
	local sJsonData =cjson.encode(tData)
	redis:hmset(sKey, {[sSubKey]=sJsonData})
	redis:expire(sKey,24*60*60) --设置key的生存时间为24小时
end

--根据第三方id获取房间用户的共享等信息
function PublicRedis.GetRoomUserShareInfoByShopAcc(nGameId,sTableId,sShopAcc)
	if not sShopAcc or sShopAcc=="" then
		return nil
	end
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local sSubKey =string.format("sShopAcc_%s",sShopAcc)
	local sJsonData =redis:hget(sKey,sSubKey)
	local tData =nil
	if sJsonData then
		tData= cjson.decode(sJsonData)
	end
	return tData
end

--清理用户的共享等信息
function PublicRedis.RemoveRoomUserShareInfo(nGameId,sTableId,nUserId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local sSubKey =string.format("nUserId_%d",nUserId)
	redis:hdel(sKey,sSubKey)
end

--根据第三方id清理用户的共享等信息
function PublicRedis.RemoveRoomUserShareInfoByShopAcc(nGameId,sTableId,sShopAcc)
	if not sShopAcc or sShopAcc=="" then
		return nil
	end
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local sSubKey =string.format("sShopAcc_%s",sShopAcc)
	redis:hdel(sKey,sSubKey)
end

--批量删除用户的共享等信息
function PublicRedis.RemoveRoomUserShareInfoBatch(nGameId,sTableId,arrDelUser)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local arrSubKey = {}
	for k,v in pairs(arrDelUser) do
		local sSubKey1 =string.format("nUserId_%d",v.nUserId)
		local sSubKey2 =string.format("sShopAcc_%s",v.sShopAcc)
		table.insert(arrSubKey,sSubKey1)
		table.insert(arrSubKey,sSubKey2)
	end
	
	redis:hdel(sKey,table.unpack(arrSubKey))
end

--清除房间所有用户的共享等信息
function PublicRedis.ClearRoomAllUserShareInfo(nGameId,sTableId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local arrSubKeys = redis:hkeys(sKey)
	if arrSubKeys and #arrSubKeys > 0 then
		for _,sSubKey in pairs(arrSubKeys) do
			redis:hdel(sKey,sSubKey)
		end
	end
end

--获取某个房间所有玩家的共享等信息
function PublicRedis.GetRoomAllUserShareInfo(nGameId,sTableId)
	local tData = {}
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local arrSubKeys = redis:hkeys(sKey)
	if arrSubKeys and #arrSubKeys > 0 then
		for _,sSubKey in pairs(arrSubKeys) do
			if string.find(sSubKey,"nUserId_") then
				local sJsonData = redis:hget(sKey,sSubKey)
				if sJsonData then
					table.insert(tData,cjson.decode(sJsonData))
				end
			end
		end
	end
	return tData
end

--获取某个房间所有玩家的共享等信息
function PublicRedis.GetRoomUserShareInfoBatch(nGameId,sTableId)
	local tData = {}
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("RoomUserShareInfo_%d_%s",nGameId,sTableId)
	local arrJson = redis:hvals(sKey)
	if arrJson and #arrJson > 0 then
		for _,sJsonData in pairs(arrJson) do
			local tUserInfo = cjson.decode(sJsonData)
			if tUserInfo.nUserId and tUserInfo.sShopAcc then
				table.insert(tData,tUserInfo)
			end
		end
	end
	return tData
end

--德州游戏间隔配置
function PublicRedis.GetDeZhouIntervalTime(nGroupId,nLev)
	return tRedisCahche.GetDeZhouIntervalTime(nGroupId,nLev)
end

function PublicRedis.IsGmOpen()
	return tRedisCahche.IsGmOpen() 
end

--德州试玩次数加1
function PublicRedis.IncrUserTryPlayCntOfTexas(nUserId)
	local sKey =string.format("TexasTryPlayCnt_%s",os.date("%Y%m%d", os.time()))
	local tRedis =tBase.m_MyRedisData[2].redis
	local isExist =tRedis:exists(sKey)
	tRedis:hincrby(sKey,string.format("%d",nUserId),1)
	if not isExist then
		tRedis:expire(sKey,3600*24)
	end
end
--当天玩家已经试玩次数
function PublicRedis.GetTryPlayCntOfTexas(nUserId)
	local sKey =string.format("TexasTryPlayCnt_%s",os.date("%Y%m%d", os.time()))
	local sFied =string.format("%d",nUserId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sCnt = tRedis:hget(sKey,sFied)
	return (tonumber(sCnt) or 0)
end
--德州每天最大免费试玩次数
function PublicRedis.GetMaxTryPlayCntOfTexas(nGroupId)
	return tRedisCahche.GetMaxTryPlayCntOfTexas(nGroupId)
end


--看广告送金币 次数加1
function PublicRedis.IncrUserLookAdvertisement(nUserId)
	local sKey =string.format("LookAdvertisementCnt_%s",os.date("%Y%m%d", os.time()))
	local tRedis =tBase.m_MyRedisData[2].redis
	local isExist =tRedis:exists(sKey)
	tRedis:hincrby(sKey,string.format("%d",nUserId),1)
	if not isExist then
		tRedis:expire(sKey,3600*24)
	end
end
--当天玩家已经看广告送金币次数
function PublicRedis.GetLookAdvertisementCnt(nUserId)
	local sKey =string.format("LookAdvertisementCnt_%s",os.date("%Y%m%d", os.time()))
	local sFied =string.format("%d",nUserId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sCnt = tRedis:hget(sKey,sFied)
	return (tonumber(sCnt) or 0)
end
--每日看广告最大赠送金币次数和金币数量
function PublicRedis.GetGiveInfoOfLookAdvertisement(nGroupId)
	return tRedisCahche.GetGiveInfoOfLookAdvertisement(nGroupId)
end


--获取直播百人类游戏的抽水率(闲家默认是0，庄家默认是0.05)
function PublicRedis.GetLiveBRDrowWaterRate(nGroupId,nGameId,nRoomId)
	return tRedisCahche.GetLiveBRDrowWaterRate(nGroupId,nGameId,nRoomId)
end

--获取某个分组所有机器人key(读取redis机器人时用)
--@params nGrpId 分组id nAnCfgId:机器人类型id:1:合集机器人,2:app机器人 
--@return arrAndroidId：{sUserId,...}
function PublicRedis.GetAndroidKey(nGrpId,nAnCfgId)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = string.format("Android_GrpId%d_AnCfgId%d",nGrpId,nAnCfgId)
	local arrAndroidId = redis:hkeys(sKey)
    return arrAndroidId or {}
end

--保存机器人key(生成机器人并保存到redis时用)
--nGrpId 分组id nAnCfgId:机器人类型id:1:合集机器人,2:app机器人  tAndroidId:机器人id {[nUserId]=nUserId,...}
function PublicRedis.SetAndroidGrpKey(nGrpId,nAnCfgId,tAndroidId)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = string.format("Android_GrpId%d_AnCfgId%d",nGrpId,nAnCfgId)
	redis:hmset(sKey, tAndroidId)
end

--删除机器人key
--@params tAndroidId = {[nUserId]={[nGrpId]=nGrpId,[nAnCfgId]=nAnCfgId,[nUserId]=nUserId},...} 
--nGrpId 分组id nAnCfgId:机器人类型id:1:合集机器人,2:app机器人 nUserId 机器人id
function PublicRedis.DelAndroidKey(tAndroidId)
	local redis =tBase.m_MyRedisData[3].redis
	local t = {}
	for _,v in pairs(tAndroidId) do
		if not t[v.nGrpId] then
			t[v.nGrpId] = {}
		end
		if not t[v.nGrpId][v.nAnCfgId] then
			t[v.nGrpId][v.nAnCfgId] = {}
		end
		local sSubKey = string.format("%d",v.nUserId)
		table.insert(t[v.nGrpId][v.nAnCfgId],sSubKey)
	end

	for nGrpId,tData in pairs(t) do
		for nAnCfgId,arrSubKey in pairs(tData) do
			local sKey = string.format("Android_GrpId%d_AnCfgId%d",nGrpId,nAnCfgId)
			redis:hdel(sKey,table.unpack(arrSubKey))
		end
	end
end

--获取redis上的机器人信息
--@params nAnUserId 机器人id
--@return tAnItem:机器人信息
function PublicRedis.GetRedisAndroidInfo(nAnUserId)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "AnItem"
	local sSubKey = string.format("%d",nAnUserId)
	local tJosn = redis:hget(sKey, sSubKey)
	local tAnItem = nil
	local isSucess = false
	if not tJosn then
		return
	end
	isSucess,tAnItem = pcall(cjson.decode,tJosn)
	if not isSucess then
		tBase.Log("GetRedisAndroidInfo json decode fail")
		if type(tAnItem) == "string" then 
			logger:error(tAnItem)
		else 
			tBase.LogT(tAnItem) 
		end
	end
	return tAnItem
end

--把机器人信息写入redis
--@params tAnItem:机器人信息
function PublicRedis.SetRedisAndroidInfo(tAnItem)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "AnItem"
	local sSubKey = string.format("%d",tAnItem.nUserId)
	redis:hset(sKey, sSubKey, cjson.encode(tAnItem))
end

--把批量机器人信息写入redis
function PublicRedis.SetRedisAndroidInfoBatch(arrAnItem)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "AnItem"
	local arrJson = {}
	for k,v in pairs(arrAnItem) do
		arrJson[v.nUserId] = cjson.encode(v)
	end
	if #arrAnItem>0 then
		redis:hmset(sKey, arrJson)
	end
end

--获取各个机器人服从redis加载的机器人id
--@return tServerAndroidId:{[nServerId]={nUserId,...},...}
function PublicRedis.GetAllServerLoadAndroid()
	local redis =tBase.m_MyRedisData[1].redis
	local sDimKey = string.format("AnServer*_LoadAndroid")
	local arrKeys = redis:keys(sDimKey)
	local tServerAndroidId = {}
	if arrKeys then
		for _,sKey in pairs(arrKeys) do
			local sServerId = string.match(sKey,"%d+")
			local nServerId = tonumber(sServerId)
			local arrAndroidId = redis:hkeys(sKey)
			if arrAndroidId then
				local arr = {}
				for _, sUserId in ipairs(arrAndroidId) do
					local nUserId = tonumber(sUserId)
					if nUserId then
						nUserId = math.floor(nUserId)
						table.insert(arr,nUserId)
					end
				end
				tServerAndroidId[nServerId] = arr
			end
		end
	end
	return tServerAndroidId
end

--保存机器人服从redis加载的机器人id
--nAnServerId:机器人服id  101  tAndroidId:{[nUserId]=nUserId,...}
function PublicRedis.SetServerLoadAndroid(nAnServerId,tAndroidId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("AnServer%d_LoadAndroid",nAnServerId)
	redis:hmset(sKey, tAndroidId)
end

--删除机器人服从redis上加载的机器人
--nAnServerId:机器人服id  101  tAndroidId {[nUserId]={nUserId},...}
function PublicRedis.DelServerLoadAndroid(nAnServerId,tAndroidId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("AnServer%d_LoadAndroid",nAnServerId)
	local t = {}
	for _,v in pairs(tAndroidId) do
		local sSubkey = string.format("%d",v.nUserId)
		table.insert(t,sSubkey)
	end

	if #t>0 then
		redis:hdel(sKey,table.unpack(t))
	end
end

--保存机器人服已使用的昵称数据库游标(生成昵称机器人时存入)
--nCursor 数据库游标id
function PublicRedis.SetUseAnNickCursor(nGroupId,nLanguageId,nCursor)
	if not nGroupId or not nLanguageId then
		tBase.Log("SetUseAnNickCursor,参数错误,nGroupId:%s,nLanguageId:%s",nGroupId,nLanguageId)
		return
	end
	nCursor = nCursor or 0
	nCursor = math.floor(nCursor)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "UseAnNickCursor"
	local sSubKey = string.format("%d_%d",nGroupId,nLanguageId)
	tBase.Log("_SetUseAnNickCursor  nGroupId:%s,nLanguageId:%s  nCursor_%d ",nGroupId,nLanguageId,nCursor)
	redis:hset(sKey,sSubKey,nCursor)
end

--获取某分组某语言已使用的昵称数据库游标
function PublicRedis.GetUseAnNickCursor(nGroupId,nLanguageId)
	nGroupId = nGroupId or 0
	nLanguageId = nLanguageId or 0
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "UseAnNickCursor"
	local sSubKey = string.format("%d_%d",nGroupId,nLanguageId)
	local sRlt = redis:hget(sKey,sSubKey)
	local nCursor = 0
	if sRlt then
		nCursor = tonumber(sRlt) or 0
		nCursor = math.floor(nCursor)
	end
	return nCursor
end

--获取某分组所有语言已使用的昵称数据库游标
function PublicRedis.GetGrpUseAnNickCursor(nGroupId)
	nGroupId = nGroupId or 0
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "UseAnNickCursor"
	local arrSubKey = redis:hkeys(sKey) --{"nLanguageId_1,nLanguageId_2,..."}
	local tCursors = {}
	if arrSubKey then
		for _,sSubKey in pairs(arrSubKey) do
			local arr = api.Split(sSubKey,"_")
			local nGrpId = tonumber(arr[1] or "0")
			local nLanguage = tonumber(arr[2] or "0")
			if nGroupId==nGrpId then
				local sRlt = redis:hget(sKey,sSubKey)
				local nCursor = 0
				if sRlt then
					nCursor = math.floor(tonumber(sRlt) or 0)
				end
				tCursors[nLanguage] = nCursor
			end
		end
	end
	return tCursors
end

--获取所有分组所有语言已使用的昵称数据库游标
function PublicRedis.GetAllUseAnNickCursor()
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = "UseAnNickCursor"
	local arrSubKeys = redis:hkeys(sKey)
	local tGrpCursors = {}
	if arrSubKeys then
		for _,sSubKey in pairs(arrSubKeys) do
			local arr = api.Split(sSubKey,"_")
			local nGrpId = tonumber(arr[1] or "0")
			local nLanguage = tonumber(arr[2] or "0")
			tGrpCursors[nGrpId] = tGrpCursors[nGrpId] or {}
			local sRlt = redis:hget(sKey,sSubKey)
			local nCursor = 0
			if sRlt then
				nCursor = math.floor(tonumber(sRlt) or 0)
			end
			tGrpCursors[nGrpId][nLanguage] = nCursor
		end
	end
	
	return tGrpCursors
end

--设置机器人事务锁
function PublicRedis.SetAndroidLock(nServerId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = "AndroidLock"
	local sSubKey = string.format("%d",nServerId)
	redis:hset(sKey,sSubKey,os.time())
	redis:expire(sKey,60)
	tBase.Log("AndroidServer_%d=>设置机器人事务锁",nServerId)
end

--获取机器人事务锁
function PublicRedis.GetAndroidLock(nServerId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = "AndroidLock"
	local arrSubKey = redis:hkeys(sKey)
	local arrServerId = {}
	if arrSubKey then
		for k,v in pairs(arrSubKey) do
			if tonumber(v)~=nServerId then --排除自己设置的事务锁
				table.insert(arrServerId,tonumber(v))
			end
		end
		if #arrSubKey>0 then
			tBase.Log("AndroidServer_%d=>获取机器人事务锁 %s",nServerId,cjson.encode(arrSubKey))
		end
	end
	return arrServerId
end

--删除机器人事务锁
function PublicRedis.DelAndroidLock(nServerId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = "AndroidLock"
	local sSubKey = string.format("%d",nServerId)
	redis:hdel(sKey,sSubKey)
	tBase.Log("AndroidServer_%d=>删除机器人事务锁",nServerId)
end

--保存机器人服借出的机器人
--nAnServerId:机器人服id  101
--tAndroidKey {[nUserId]=sServerkey,...}
function PublicRedis.SetLendAndroid(nAnServerId,tAndroidKey)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("AnServer%d_LendAndroid",nAnServerId)
	redis:hmset(sKey,tAndroidKey)
end

--获取机器人服借出的机器人
--nAnServerId:机器人服id  101
--@return tAndroidKey {[nUserId]=sServerkey,...}
function PublicRedis.GetLendAndroid(nAnServerId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("AnServer%d_LendAndroid",nAnServerId)
	local arrSubKeys = redis:hkeys(sKey)
	local tAndroidKey = {}
	if arrSubKeys then
		for _,sSubKey in pairs(arrSubKeys) do
			local nUserId = tonumber(sSubKey)
			local sServerkey = redis:hget(sKey,sSubKey)
			if sServerkey and nUserId then
				nUserId = math.floor(nUserId)
				tAndroidKey[nUserId] = sServerkey
			end
		end
	end
	return tAndroidKey
end

--删除 机器人服借出的机器人
--nAnServerId:机器人服id  101 tAndroidId {[nUserId]={nUserId},...}
function PublicRedis.DelLendAndroid(nAnServerId,tAndroidId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey = string.format("AnServer%d_LendAndroid",nAnServerId)
	local t = {}
	for _,v in pairs(tAndroidId) do
		local sSubkey = string.format("%d",v.nUserId)
		table.insert(t,sSubkey)
	end

	if #t>0 then
		redis:hdel(sKey,table.unpack(t))
	end
end

--保存每段UserId使用游标
--@params arrDuanUserId = {[nDuanIdx]=nUseUserId,...}
function PublicRedis.SetUseAndroidUserId(tDuanUserId)
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = string.format("UseAndroidUserId")
	redis:hmset(sKey,tDuanUserId)
end

--获取每段UserId使用游标
--@return {[nDuanIdx]=nUseUserId,...}
function PublicRedis.GetUseAndroidUserId()
	local redis =tBase.m_MyRedisData[3].redis
	local sKey = string.format("UseAndroidUserId")

	local tDuanUserId = {}
	local arrSubkey = redis:hkeys(sKey)
	for _,sSubKey in pairs(arrSubkey) do
		local nDuanIdx = tonumber(sSubKey)
		local sRlt = redis:hget(sKey,sSubKey)
		if sRlt and nDuanIdx then
			local nUseUserId = tonumber(sRlt) or 0
			tDuanUserId[nDuanIdx] = nUseUserId
		end
	end
	return tDuanUserId
end

--获取维护服的状态
--@params nServerId:服务器服id  如101
--@return nServerState 服务器状态 0:未启用 1:正常 2:维护 3:测试 4:进程没开 (默认1)
function PublicRedis.GetServerState(nServerId)
	return tRedisCahche.GetServerState(nServerId)
end

-- 获取某类型服务器所有未维护的key(Web服)
function PublicRedis.GetNotMaintainAllKey(stypename)
    local arrAllCenterKey =tBase.GetSrcAllKey(stypename) or {}
    local InValidAllCenterKey = {}
    --tBase.LogT("_GetNotMaintainAllKey_arrAllKey_",arrAllCenterKey)
    for _,sServKey in ipairs(arrAllCenterKey) do
        local nServerId =tonumber(string.match(sServKey,"_(%d+)"))
        -- 服务器状态为%d(0:未启用 1:正常 2:维护 3:测试 4:进程没开)
        local state = PublicRedis.GetServerState(nServerId)
        -- tBase.Log("_GetNotMaintainAllKey nServerId_%d state_%d",nServerId,state)
        if state == 1 then
            table.insert(InValidAllCenterKey,sServKey)
        end
    end
    if #InValidAllCenterKey > 0 then
        --tBase.LogT("_GetNotMaintainAllKey_InValidAllCenterKey1_",InValidAllCenterKey)
        return InValidAllCenterKey
	else
		 tBase.LogT("_GetNotMaintainAllKey_arrAllCenterKey2_",arrAllCenterKey)
		return arrAllCenterKey
    end
end

--删除飞行棋路珠信息
--@params tAndroidId {[nUserId]={[nUserId]=nUserId},...}
function PublicRedis.DelPilotFightRoadBead(tAndroidId)
	local redis =tBase.m_MyRedisData[2].redis
	local t = {}
	for _,v in pairs(tAndroidId) do
		local sKey = string.format("PilotFightRoadBead_%d",v.nUserId)
		table.insert(t,sKey)
	end
	
	if #t > 0 then
		redis:del(table.unpack(t))
	end
end

-- 主播设置规则   sRuleDetail: 空 就是获取规则，非空设置规则 
function PublicRedis.LiveSetTableRuleDetail(nLiveUserID,sRuleDetail)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("LiveSetTableRuleDetail_%d",nLiveUserID) 
	if not sRuleDetail then 
		return redis:get(sKey)
	else
		redis:set(sKey,sRuleDetail)
		redis:expire(sKey,60*60*24*30)   -- 保留一个月
		return  
	end  
end
 
--  区块链 停服维护:  {nType(维护类型:0维护期间,1开始维护倒计时),nCountDown:倒计时}
function PublicRedis.BlockchainStopServerMaintian(nServerId)
	return tRedisCahche.BlockchainStopServerMaintian(nServerId)
end

--是否白名单用户. 是:true
function PublicRedis.IsWhiteListUser(nUserId)
	return tRedisCahche.IsWhiteListUser(nUserId)
end

--初始化主播体验金币,返回:体验金币数量
--创建主播可试玩房时初始化一次(下次调用前，金币不会自动重置;同一天调用也不会重置)
function PublicRedis.InitExperienceOfGold(nUserId,nGameId,nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ExperienceOfGold"
	local sGoldField =string.format("Gold_%d_%d",nUserId,nGameId)
	local sTimeField =string.format("Time_%d_%d",nUserId,nGameId)
	local sConutField = string.format("Count_%d_%d",nUserId,nGameId)
	
	local arrRlt =redis:hmget(sKey,sGoldField,sTimeField,sConutField)
	local nGold =tonumber(arrRlt[1]) 
	local nTime =tonumber(arrRlt[2])
	local nToday =tonumber(arrRlt[3]) or 0 --本日已补充试玩金币次数

	local sGoldGivePerDayField =string.format("Game_%d",nGameId)
	local sRlt1 = tRedisCahche.GetConfigOfTryPlay(nGroupId,sGoldGivePerDayField)
	local sRlt2 = tRedisCahche.GetConfigOfTryPlay(nGroupId,"ResetPeriod")
	local sRlt3 = tRedisCahche.GetConfigOfTryPlay(nGroupId,"ResetCount")
	local sRlt4 = tRedisCahche.GetConfigOfTryPlay(nGroupId,"TimeZone")
	local nGoldGivePerDay =tonumber(sRlt1) or 20000
	local sResetTime =sRlt2 or "00:00" --重置时间  时:分
	local nTotal = tonumber(sRlt3) or 0 --本日补充试玩金币总次数
	local sTimeZone = sRlt4 or "+8:00" --时区(默认东八时区)

	local nNow,tNowDate =api.GetTimeByTimeZone(sTimeZone) --转换成该时区的时间
	local sNowTime = os.date("%Y-%m-%d %H:%M:%S", nNow) --该时区的日期
	local sLastTime = "nil" --上一次初始化主播体验金币的日期
	if nTime then
		sLastTime = os.date("%Y-%m-%d %H:%M:%S", nTime)
	end
	local arrTime = api.Split(sResetTime,":")
	local nResetHour = tonumber(arrTime[1]) or 0 --重置时间  时
	local nResetMin = tonumber(arrTime[2]) or 0 --重置时间  分
	local tResetDate = api.Clone(tNowDate) --当天的重置时间点
	tResetDate.hour = nResetHour
	tResetDate.min = nResetMin
	tResetDate.sec = 0
	local nResetTime = os.time(tResetDate) --当天的重置时间戳
	if nNow<nResetTime then
		--如果现在的时间比当天的重置时间小，那就要取前一天的重置时间
		nResetTime = nResetTime-24*60*60
	end
	
    tBase.Log("_InitExperienceOfGold nUserId_%d,nGameId_%d,nGroupId_%d,sTimeZone_%s,sNowTime_%s,sLastTime_%s,nTodayReset_%d,nTotalReset_%d,sResetTime_%s nCount: %d",
		nUserId,nGameId,nGroupId,sTimeZone,sNowTime,sLastTime,nToday,nTotal,sResetTime,nGoldGivePerDay)
	tBase.Log("_InitExperienceOfGold nGold_%s,nTime_%s,nResetTime_%d,nNow_%d",tostring(nGold),tostring(nTime),nResetTime,nNow)
	if nGold and nTime and nTime>nResetTime then
		--上次开播时间大于重置时间
		if nGold<5 and nToday<nTotal then
			--如果试玩金币不足以下注，又还有补充次数，补充试玩金币
			PublicRedis:HincrbyExperienceOfCount(nUserId,nGameId)
			nGold = PublicRedis.ChangeExperienceOfGold(nUserId,nGameId,nGoldGivePerDay)
    		tBase.Log("_InitExperienceOfGold  nToday: %d  nTotal: %d  ",nToday,nTotal)
		end
		return nGold
	end
	tBase.Log("_InitExperienceOfGold Reset")
	redis:hmset(sKey,{[sGoldField]=nGoldGivePerDay,[sTimeField]=nNow,[sConutField]=0})
	return nGoldGivePerDay
end

--加减体验金币,返回:操作后的金币数量
function PublicRedis.ChangeExperienceOfGold(nUserId,nGameId,nChangeValue)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ExperienceOfGold"
	local sGoldField =string.format("Gold_%d_%d",nUserId,nGameId)
	if nChangeValue<0  and math.abs(nChangeValue)>1e-6 then
		local sRlt =redis:hget(sKey,sGoldField)
		local nGold =tonumber(sRlt) or 0
		local nSum = nGold +nChangeValue
		if nSum<0 and math.abs(nSum)>1e-6 then
			redis:hmset(sKey,{[sGoldField]=0})
			return 0
		end
	end
	local nGoldAfterChange =redis:hincrbyfloat(sKey,sGoldField,nChangeValue)
	return tonumber(nGoldAfterChange)
end

--返回:当前体验金币数量
function PublicRedis.GetExperienceOfGold(nUserId,nGameId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ExperienceOfGold"
	local sGoldField =string.format("Gold_%d_%d",nUserId,nGameId)
	local sRlt =redis:hget(sKey,sGoldField)
	local nGold =tonumber(sRlt) or 0
	return api.Floor_2(nGold)
end

--补充试玩金币
function PublicRedis.SupplementExperienceOfGold(nUserId,nGameId,nGroupId)
	local sGoldGivePerDayField =string.format("Game_%d",nGameId)
	local sRlt1 = tRedisCahche.GetConfigOfTryPlay(nGroupId,sGoldGivePerDayField)
	local nGoldGivePerDay =tonumber(sRlt1) or 20000
	PublicRedis:HincrbyExperienceOfCount(nUserId,nGameId)
	return PublicRedis.ChangeExperienceOfGold(nUserId,nGameId,nGoldGivePerDay)
end

--试玩金币本日已经补充的次数+1
function PublicRedis:HincrbyExperienceOfCount(nUserId,nGameId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ExperienceOfGold"
	local sConutField = string.format("Count_%d_%d",nUserId,nGameId)
	redis:hincrby(sKey,sConutField,1)
end

--获取试玩金币补充次数，返回:本日已经补充的次数,每日总次数
function PublicRedis.GetExperienceOfCount(nUserId,nGameId,nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ExperienceOfGold"
	local sConutField = string.format("Count_%d_%d",nUserId,nGameId)

	local sToday = redis:hget(sKey,sConutField)
	local nToday = sToday and tonumber(sToday) or 0

	local sTotal = tRedisCahche.GetConfigOfTryPlay(nGroupId,"ResetCount")
	local nTotal = tonumber(sTotal) or 0
	return nToday,nTotal
end

-- 获取 牌桌试玩金币 额度、次数
function PublicRedis._GetTableExperienceOfSwith(nGameId,nGroupId)
	local bTableSwith = tRedisCahche.GetConfigOfTryPlay(nGroupId,"bTableSwith")   
	if (tonumber(bTableSwith or 0)==1) then 
		local sGoldGivePerDayField =string.format("Table_Game_%d",nGameId)
		local sRlt1 = tRedisCahche.GetConfigOfTryPlay(nGroupId,sGoldGivePerDayField) 
		local nGoldGivePerDay =tonumber(sRlt1) or 20000 
		-- local sRlt3 = tRedisCahche.GetConfigOfTryPlay(nGroupId,"TableResetCount")
		-- local nTotal = tonumber(sRlt3) or 0 --本日补充试玩金币总次数
		return nGoldGivePerDay
	end 
end 

function PublicRedis.InitExperienceOfGold_tb(nUserId,nInitValue,sTableId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("ExperienceOfGold_%s",sTableId)
	local sGoldField =string.format("Gold_%d",nUserId)
	redis:hmset(sKey,{[sGoldField]=nInitValue})
	return nInitValue
end

--加减体验金币,返回:操作后的金币数量
function PublicRedis.ChangeExperienceOfGold_tb(nUserId,nChangeValue,sTableId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("ExperienceOfGold_%s",sTableId)
	local sGoldField =string.format("Gold_%d",nUserId)
	if nChangeValue<0  and math.abs(nChangeValue)>1e-6 then
		local sRlt =redis:hget(sKey,sGoldField)
		local nGold =tonumber(sRlt) or 0
		local nSum = nGold +nChangeValue
		if nSum<0 and math.abs(nSum)>1e-6 then
			redis:hmset(sKey,{[sGoldField]=0})
			return 0
		end
	end
	local nGoldAfterChange =redis:hincrbyfloat(sKey,sGoldField,nChangeValue)
	return tonumber(nGoldAfterChange)
end

--返回:当前体验金币数量
function PublicRedis.GetExperienceOfGold_tb(nUserId,sTableId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("ExperienceOfGold_%s",sTableId)
	local sGoldField =string.format("Gold_%d",nUserId)
	local sRlt =redis:hget(sKey,sGoldField)
	local nGold =tonumber(sRlt) or 0
	return api.Floor_2(nGold)
end

--删除桌子体验金币信息表
function PublicRedis.DelExperience_tb(sTableId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("ExperienceOfGold_%s",sTableId)
	redis:del(sKey)
end


--获取试玩金币下注记录域名
function PublicRedis.GetDemoPetternDomainName()
	return tRedisCahche.GetDemoPetternDomainName()
end

--获取战绩播报域名
function PublicRedis.GetRecordBraodCastDomainName()
	return tRedisCahche.GetRecordBraodCastDomainName()
end

--读取其它厂商输赢域名
function PublicRedis.GetOtherPlatformWinloseDomainName()
	return tRedisCahche.GetOtherPlatformWinloseDomainName()
end

--读取APP黑名单域名
function PublicRedis.GetAppBlackUserListDomainName()
	return tRedisCahche.GetAppBlackUserListDomainName()
end

--获取俱乐部今日收益
function PublicRedis.GetClubTodayIncome(nClubId,nItemId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ClubTodayIncome"
	local sIncomeFeild = string.format("TodayIncome_ClubId%d_ItemId%d",nClubId,nItemId)

	local sRlt = redis:hget(sKey,sIncomeFeild)
	local nTodayIncome = tonumber(sRlt) or 0

	return nTodayIncome
end

--增加俱乐部今日收益
function PublicRedis.IncrClubTodayIncome(nClubId,nItemId,nChange)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ClubTodayIncome"
	local sIncomeFeild = string.format("TodayIncome_ClubId%d_ItemId%d",nClubId,nItemId)
	local sNew = redis:hincrbyfloat(sKey,sIncomeFeild,nChange)
	local nTodayIncome = tonumber(sNew) or 0
	return nTodayIncome
end

--删除今日收益
--@params nClubId:俱乐部id 不传则删除所有俱乐部的今日收益
function PublicRedis.DelClubTodayIncome(nClubId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="ClubTodayIncome"
	if nClubId then
		local sIncomeFeild1 = string.format("TodayIncome_ClubId%d_ItemId%d",nClubId,1)
		local sIncomeFeild2 = string.format("TodayIncome_ClubId%d_ItemId%d",nClubId,nClubId)
		redis:hdel(sKey,sIncomeFeild1,sIncomeFeild2)
	else
		redis:del(sKey)
	end
end

--获取俱乐部玩家本周局数
function PublicRedis.GetClubUserWeekCount(nClubId,nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubUserWeekCount_%d",nClubId)
	local sWeekCountFeild = string.format("WeekCount_%d",nUserId)

	local sRlt = redis:hget(sKey,sWeekCountFeild)
	local nWeekCount = tonumber(sRlt) or 0

	return nWeekCount
end

--增加俱乐部玩家本周局数
function PublicRedis.IncrClubUserWeekCount(nClubId,nUserId,nIncr)
	local nIncr =nIncr or 1
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubUserWeekCount_%d",nClubId)
	local sWeekCountFeild = string.format("WeekCount_%d",nUserId)
	local sTimeFeild = string.format("Time_%d",nUserId)

	local sNew = redis:hincrby(sKey,sWeekCountFeild,nIncr)
	local nWeekCount = tonumber(sNew) or 0

	if redis:hexists(sKey,sTimeFeild)==0 and nIncr>0 then
		redis:hset(sKey,sTimeFeild,tostring(api.GetWeekZero()))
	end

	return nWeekCount
end

--删除俱乐部玩家本周局数
function PublicRedis.DelClubUserWeekCount(nClubId,nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	if nClubId then
		local sKey = string.format("ClubUserWeekCount_%d",nClubId)
		if nUserId then
			local sWeekCountFeild = string.format("WeekCount_%d",nUserId)
			local sTimeFeild = string.format("Time_%d",nUserId)
			redis:hdel(sKey,sWeekCountFeild,sTimeFeild)
		else
			redis:del(sKey)
		end
	else
		local sDimKey ="ClubUserWeekCount_*"
		local arrKeys = redis:keys(sDimKey)
		if #arrKeys>0 then
			redis:del(table.unpack(arrKeys))
		end
	end
end

--保存俱乐部玩家信息
--@params nClubId:俱乐部id
--@params arrUserInfo:玩家信息 {{['nUserId']=玩家id,['nIdentify']=身份,['sPower']=权限,...}
function PublicRedis.SetClubUserInfo(nClubId,arrUserInfo)
	if type(nClubId)~="number" or type(arrUserInfo)~="table" then
		return
	end
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubUserInfo_%d",nClubId)

	local arrJson = {}
	local nCnt = 0
	for _,tUserInfo in pairs(arrUserInfo) do
		local sSubKey = string.format("nUserId_%d",tUserInfo.nUserId)

		local tData = PublicRedis.GetClubUserInfo(nClubId,tUserInfo.nUserId) or {}

		for k,v in pairs(tUserInfo) do
			tData[k] = v
		end

		arrJson[sSubKey] = cjson.encode(tData)

		nCnt = nCnt + 1
	end
	
	if nCnt > 0 then
		redis:hmset(sKey,arrJson)
	end
end

--获取俱乐部玩家信息
--@params nClubId:俱乐部id
--@params nUserId:玩家id
--@return tUserInfo:玩家信息 {['nIdentify']=身份,['sPower']=权限}
function PublicRedis.GetClubUserInfo(nClubId,nUserId)
	if type(nClubId)~="number" or type(nUserId)~="number" then
		return
	end

	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubUserInfo_%d",nClubId)
	local sSubKey = string.format("nUserId_%d",nUserId)

	local sData = redis:hget(sKey,sSubKey)
	local isSuccee,tUserInfo = pcall(cjson.decode,sData)
	if not isSuccee then
		return
	end

	return tUserInfo
end

--获取俱乐部所有玩家的信息
--@params nClubId:俱乐部id
--@return arrClubUserInfo:玩家信息 {{['nIdentify']=身份,['sPower']=权限,...}
function PublicRedis.GetClubAllUserInfo(nClubId)
	local arrClubUserInfo = {}
	if type(nClubId)=="number" then
		local redis = tBase.m_MyRedisData[2].redis
		local sKey = string.format("ClubUserInfo_%d",nClubId)
		local arrRlt = redis:hgetall(sKey)
		if type(arrRlt)=="table" then
			for _,sData in pairs(arrRlt) do
				local isSuccee,tUserInfo = pcall(cjson.decode,sData)
				if isSuccee then
					table.insert(arrClubUserInfo,tUserInfo)
				end
			end
		end
	end
	return arrClubUserInfo
end

--俱乐部的玩家信息是否已存在
function PublicRedis.IsExitsClubUserInfo(nClubId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubUserInfo_%d",nClubId)
	return redis:exists(sKey)
end

--判断玩家是否能关闭牌桌
--@params nClubId 俱乐部id
--@params nUserId 玩家id
--@params nLiveUserID 房主id
--@return true:可以关桌   false:不能关桌
function PublicRedis.HasClubTableMgrPower(nClubId,nUserId,nLiveUserID)
	if nClubId<1000000 then
		--大厅,只有房主自己才能关桌
		if nUserId==nLiveUserID then
			return true
		end
	else
		--俱乐部房间，有权限的才能关
		local tClubUser = PublicRedis.GetClubUserInfo(nClubId,nUserId)
		if tClubUser and tClubUser.sPower then
			local isSuccee,arrPower = pcall(cjson.decode,tClubUser.sPower)
			if isSuccee then
				for _,v in pairs(arrPower) do
					if v.nPowerType==3 and v.isOpen==true then
						return true
					end
				end
			end
		end
	end
	return false
end

--删除俱乐部玩家信息
--@params nClubId:俱乐部id
--@params nUserId:玩家id
function PublicRedis.DelClubUserInfo(nClubId,nUserId)
	if type(nClubId)~="number" or type(nUserId)~="number" then
		return
	end
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubUserInfo_%d",nClubId)
	local sSubKey = string.format("nUserId_%d",nUserId)
	redis:hdel(sKey,sSubKey)
end

--设置俱乐部申请处理锁
--@params nClubId:俱乐部id
--@params nId:申请id
--@params nType:申请类型
--@params nOpUserId:管理员id
function PublicRedis.SetApplyDealLock(nClubId,nId,nType,nOpUserId)
	if type(nClubId)~="number" or type(nId)~="number" or type(nType)~="number" or type(nType)~="nOpUserId" then
		return
	end
	local redis = tBase.m_MyRedisData[1].redis
	local sKey = string.format("ClubApplyDealLock_ClubId%d_Type%d_Id%d",nClubId,nType,nId)
	redis:set(sKey,tostring(nOpUserId))
	redis:expire(sKey,60*60)   -- 保留3600s
end

--获取俱乐部申请处理锁
--@params nClubId:俱乐部id
--@params nId:申请id
--@params nType:申请类型
function PublicRedis.GetApplyDealLock(nClubId,nId,nType)
	if type(nClubId)~="number" or type(nId)~="number" or type(nType)~="number" then
		return
	end
	local redis = tBase.m_MyRedisData[1].redis
	local sKey = string.format("ClubApplyDealLock_ClubId%d_Type%d_Id%d",nClubId,nType,nId)
	local nOpUserId = redis:get(sKey)
	return nOpUserId
end

--删除俱乐部申请处理锁
--@params nClubId:俱乐部id
--@params nId:申请id
--@params nType:申请类型
function PublicRedis.DelApplyDealLock(nClubId,nId,nType)
	if type(nClubId)~="number" or type(nId)~="number" or type(nType)~="number" then
		return
	end
	local redis = tBase.m_MyRedisData[1].redis
	local sKey = string.format("ClubApplyDealLock_ClubId%d_Type%d_Id%d",nClubId,nType,nId)
	redis:del(sKey)
end

--保存俱乐部所在中心服id
function PublicRedis.SetClubCenterServer(arrClubId)
	arrClubId = arrClubId or {}
	local redis = tBase.m_MyRedisData[1].redis
	local sKey = "ClubCenterServer"
	local arrSetData = {}
	local nCnt = 0
	local arrClubCenterSerArray = PublicRedis.GetClubCenterSerArrayBatch(arrClubId)
	for nClubId,nCenterServId in pairs(arrClubId) do
		local sSubkey =  string.format("%d",nClubId)
		local arrCenterServId = arrClubCenterSerArray[nClubId] or {}
		local isExist = false
		for _,nServId in pairs(arrCenterServId) do
			if nServId==nCenterServId then
				isExist = true
				break
			end
		end
		if not isExist then
			table.insert(arrCenterServId,nCenterServId)
			arrSetData[sSubkey] = cjson.encode(arrCenterServId)
			nCnt = nCnt + 1
		end
	end
	if nCnt>0 then
	  redis:hmset(sKey,arrSetData)
	end
end

--获取俱乐部所在中心服id(优先返回非维护的中心服)
--return arrNormal 正常运行的中心服id arrOther 非正常运行的中心服id
function PublicRedis.GetClubCenterServer(nClubId)
	local arrCenterServId = PublicRedis.GetClubCenterSerArray(nClubId)
	local arrNormal = {}
	local arrOther = {}
	for _,nServId in pairs(arrCenterServId) do
		local nServerState = PublicRedis.GetServerState(nServId)
		if not nServerState or nServerState==1 then
			local sKey = tBase.GetServerIdIdKey(nServId)
			if sKey then
				table.insert(arrNormal,nServId)
			end
		else
			local sKey = tBase.GetServerIdIdKey(nServId)
			if sKey then
				table.insert(arrOther,nServId)
			end
		end
	end
	return arrNormal,arrOther
end

--获取俱乐部所在中心服id数组
--return arrCenterServId = {nCenterServId,nCenterServId,...}
function PublicRedis.GetClubCenterSerArray(nClubId)
	local redis = tBase.m_MyRedisData[1].redis
	local sKey = "ClubCenterServer"
	local sSubkey =  string.format("%d",nClubId)
	local sRlt = redis:hget(sKey,sSubkey)
	local isSuccee = false
	local arrCenterServId = {}
	if sRlt then
		isSuccee,arrCenterServId = pcall(cjson.decode,sRlt)
		if not isSuccee then
			arrCenterServId = {}
		end
	end
	return arrCenterServId
end

--获取俱乐部所在中心服id
--return arrServKey = {sKey,sKey,...}
function PublicRedis.GetClubCenterSrvKey(nClubId)
	local arrCenterServId =  PublicRedis.GetClubCenterSerArray(nClubId)
	local arrServKey = {} 
	for _,nServId in pairs(arrCenterServId) do
		local sKey = tBase.GetServerIdIdKey(nServId)
		if sKey then
			table.insert(arrServKey,sKey)
		end
	end
	return arrServKey
end

--删除俱乐部所在中心服id
function PublicRedis.DelClubCenterSrvKey(nClubId,nCenterServId)
	local arrCenterServId =  PublicRedis.GetClubCenterSerArray(nClubId)
	for k,nServId in pairs(arrCenterServId) do
		if nServId==nCenterServId then
			arrCenterServId[k] = nil
			break
		end
	end

	local redis = tBase.m_MyRedisData[1].redis
	local sKey = "ClubCenterServer"
	local sSubkey =  string.format("%d",nClubId)
	redis:hset(sKey,sSubkey,cjson.encode(arrCenterServId))
end

--获取部分俱乐部的中心服
function PublicRedis.GetClubCenterSerArrayBatch(arrClubId)
	local redis = tBase.m_MyRedisData[1].redis
	local sKey = "ClubCenterServer"
	local tData =  redis:hgetall(sKey)
	local arrClubCenterSerArray = {}
	if tData then
		for k,v in pairs(tData) do
			local nClubId = tonumber(k)
			if arrClubId[nClubId] then
				local arrCenterServId = cjson.decode(v) 
				arrClubCenterSerArray[nClubId] = arrCenterServId
			end
		end
	end
	return arrClubCenterSerArray
end

--保存用户在其它厂商的输赢
function PublicRedis.SetUserOherPlatformWinlose(nGroupId,tInfo)
	local redis = tBase.m_MyRedisData[1].redis
	nGroupId = math.floor(nGroupId)
	local sKey = "8775299EEA074CB590ABC586BFAF4566_"..nGroupId
	if tInfo then
		redis:hmset(sKey,{[tInfo.nUserID]=tInfo.nWinlose})
	end
end

--检查牌桌是否是官方房
--true 是  false:不是
function PublicRedis.CheckIsOffical(sTableId)
	local sKey = string.format("APIOpenTale_%s",sTableId)
	local sSubKey1 = "nTableType"
	local sSubKey2 = "sConfig"
   	local redis = tBase.m_MyRedisData[2].redis

	local arrData = redis:hmget(sKey,sSubKey1,sSubKey2)

	local nTableType = tonumber(arrData[1]) or -1
	local isOffical = false

	local sConfig = arrData[2]
	local isSuccee,tConfig = pcall(cjson.decode,sConfig)
	if isSuccee then
		if tConfig.isOfficialHouse then
			isOffical = true
		end
	else
		tBase.Log("table sConfig decode fail,sTableId:%s",sTableId)
	end
	return isOffical,nTableType
end

--保存俱乐部牌桌信息
function PublicRedis.SetClubTableInfo(nClubId,sTableId,sTableInfo)
	local sKey = string.format("ClubTableInfo_%d",nClubId)
	local sSubKey = sTableId
	local redis = tBase.m_MyRedisData[2].redis
	redis:hset(sKey,sSubKey,sTableInfo)
end

--删除俱乐部牌桌信息
function PublicRedis.DelClubTableInfo(nClubId,sTableId)
	local sKey = string.format("ClubTableInfo_%d",nClubId)
	local sSubKey = sTableId
	local redis = tBase.m_MyRedisData[2].redis
	redis:hdel(sKey,sSubKey)
end

--获取redis上俱乐部的所有牌桌
function PublicRedis.GetAllClubTableInfo(nClubId)
	local sKey = string.format("ClubTableInfo_%d",nClubId)
	local redis = tBase.m_MyRedisData[2].redis
	local arrTableInfo = redis:hgetall(sKey)
	return arrTableInfo
end

--俱乐部牌桌 后台操作： 1 关桌、2获取 
function PublicRedis._HandleClubTable_WebClose(sTableId,nHandle,nServerId)
	local sKey = string.format("ClubTable_WebClose_%s",sTableId) 
	local redis = tBase.m_MyRedisData[1].redis 
	tBase.Log("_HandleClubTable_WebClose  后台关桌 sTableId: %s  nHandle_%d nServerId_%d ",sTableId,nHandle,nServerId)
	if nHandle == 1 then 
		redis:set(sKey,nServerId) 
		redis:expire(sKey,60*10) --设置60秒过期
	elseif nHandle == 2 then
		local nSrvId = redis:get(sKey)
		if nSrvId then
			redis:del(sKey)   
			return true 
		end  
	end 
	return false 
end
 
--检查牌桌是否还存在
function PublicRedis.CheckTableIsExits(sTableId)
	local sKey = string.format("APIOpenTale_%s",sTableId)
	local redis = tBase.m_MyRedisData[2].redis
	return redis:exists(sKey)
end

--获取后台设置的金币标准值
function PublicRedis.GetGoldStandard(nGroupId)
	return 10
	-- return tRedisCahche.GetGoldStandard(nGroupId)
end

--判断牌桌是否正在游戏中
function PublicRedis.IsInPlaying(nGameId,sTableId)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis

	if not tRedis:exists(sKey) then
		return false
	end

	local sCurPaiJu = tRedis:hget(sKey,"sCurPaiJu")
	if sCurPaiJu then
		return true
	end
	return false
end

--获取一张牌桌允许进入的真人数目
function PublicRedis.GetOneTableRealCnt(nGroupId,nGameId,nRoomId)
	return tRedisCahche.GetOneTableRealCnt(nGroupId,nGameId,nRoomId)
end

--获取是否免费修改名字
function PublicRedis.GetIsFreeChangeName(nUserId,nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey= "ClubChangeNameCount"
	local sSubKey = string.format("UserId_%d",nUserId)
	local sCount = redis:hget(sKey,sSubKey)
	local nCount = tonumber(sCount) or 0
	local _,nFreeCnt = tRedisCahche.GetChangeUserInfoConsume(nGroupId)
	if nCount>=nFreeCnt then
		return false
	end
	return true
end

--设置玩家修改名字的次数
function PublicRedis.HincrbyChangeNameCount(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey= "ClubChangeNameCount"
	local sSubKey = string.format("UserId_%d",nUserId)
	redis:hincrby(sKey,sSubKey,1)
end

--设置玩家发送短信验证码的状态
function PublicRedis.SetSendCodeStatus(nUserId,nOverTime)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey= string.format("SendCodeStatus_%d",nUserId)
	redis:set(sKey,"1")
	redis:expire(sKey,nOverTime or 60) --设置60秒过期
end

--获取玩家发送短信验证码的状态
--@return 1:60s内有发送 其他:60s内没有发送
function PublicRedis.GetSendCodeStatus(nUserId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey= string.format("SendCodeStatus_%d",nUserId)
	local sRlt = redis:get(sKey)
	return sRlt
end

--获取玩家短信验证码
function PublicRedis.GetMsgCode(nUserId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey= string.format("ClubMsgCode_%d",nUserId)
	local sCode = redis:get(sKey)
	return sCode
end

--删除玩家短信验证码
function PublicRedis.DelMsgCode(nUserId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey= string.format("ClubMsgCode_%d",nUserId)
	redis:del(sKey)
end


-- 清除玩家统计数据
function PublicRedis.TexaStatistic_Clear(nUserId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("TexaStatistic_%d", nUserId)
	redis:del(sKey)
end


function PublicRedis.TexaStatistic_IsInit(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey= string.format("TexaStatistic_%d",nUserId)
	local isInit = redis:hget(sKey,"isInit")
	return isInit=="1"
end

local function genStaticKey(tData)
	return string.format("_%d_%d_%d_%.2f_%.2f_%.2f_%.2f",tData.nClubId,tData.nGameId,tData.nGoldType,tData.nSmallBlind or 0,tData.nBigBlind or 0,tData.nZhuaTou or 0,tData.nPreAnte or 0)
end

function PublicRedis.TexaStatistic_Init(nUserId, tData)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("TexaStatistic_%d",nUserId)
	local t = {}
	t["isInit"] = 1					--真人玩家,根据该字段判断需要不需要从数据库进行同步
	if tData then
		local sT = genStaticKey(tData)
		t["nPlayCount"..sT] = tData.nPlayCount
		t["nInPoolCount"..sT] = tData.nInPoolCount
		t["nRaiseCountBFlop"..sT] =tData.nRaiseCountBFlop
		t["nAllInAndWinCount"..sT] =tData.nAllInAndWinCount
		t["nProfitSum"..sT] = tData.nProfitSum
		t["nSumBet"..sT] = tData.nSumBet
		t["nWinCount"..sT] = tData.nWinCount
		t["nQiPaiCount"..sT] = tData.nQiPaiCount
		t["nAllInCount"..sT] = tData.nAllInCount
		t["nHandProfit"..sT] = tData.nHandProfit
		t["nOpCount"..sT] = tData.nOpCount
		t["nSeeFlop"..sT] = tData.nSeeFlop
		t["nReachShowdown"..sT] = tData.nReachShowdown
	end
	redis:hmset(sKey, t)
end
 
function PublicRedis.TexaStatistic_WriteN(tTableInfo,arrTableUsers)
	local nKeepTime =tTableInfo.nKeepTime or -1		-- -1时为永久桌
	-- if tTableInfo.nClubId ==0 and nKeepTime>0 then	-- nClubId为0代表大厅
	-- 	return
	-- end

	local redis =tBase.m_MyRedisData[2].redis
	local sT = genStaticKey(tTableInfo)
	-- local sDateDay =os.date("%d", os.time())
	-- local sDateMonth =os.date("%y%m", os.time())

	for _,tData in ipairs(arrTableUsers) do
		local sKey= string.format("TexaStatistic_%d",tData.nUserId)
		if tData.isHaveSelfOp > 0 then
			redis:hincrby(sKey,"nPlayCount"..sT,tData.nPlayCount or 1)
		end
		if tData.nInPoolCount > 0 then
			redis:hincrby(sKey,"nInPoolCount"..sT, tData.nInPoolCount)
		end
		if tData.nRaiseCountBFlop > 0 then
			redis:hincrby(sKey,"nRaiseCountBFlop"..sT,tData.nRaiseCountBFlop)
		end
		if tData.nAllInAndWinCount > 0 then
			redis:hincrby(sKey,"nAllInAndWinCount"..sT,tData.nAllInAndWinCount)
		end
		redis:hincrbyfloat(sKey,"nProfitSum"..sT, tData.nProfitSum)
		if tData.nSumBet and tData.nSumBet > 0 then
			redis:hincrbyfloat(sKey,"nSumBet"..sT, tData.nSumBet)
		end
		if tData.nWinCount and tData.nWinCount > 0 then
			redis:hincrby(sKey,"nWinCount"..sT, tData.nWinCount)
		end
		if tData.nQiPaiCount and tData.nQiPaiCount > 0 then
			redis:hincrby(sKey,"nQiPaiCount"..sT, tData.nQiPaiCount)
		end
		if tData.nHandProfit then
			redis:hincrbyfloat(sKey,"nHandProfit"..sT, tData.nHandProfit)
		end
		if tData.isAllIn and tData.isAllIn > 0 then
			redis:hincrby(sKey,"nAllInCount"..sT, tData.isAllIn)
		end
		if tData.nOpCount and tData.nOpCount > 0 then
			redis:hincrby(sKey,"nOpCount"..sT, tData.nOpCount)
		end
		if tData.nSeeFlop and tData.nSeeFlop > 0 then
			redis:hincrby(sKey,"nSeeFlop"..sT, tData.nSeeFlop)
		end
		if tData.nReachShowdown and tData.nReachShowdown > 0 then
			redis:hincrby(sKey,"nReachShowdown"..sT, tData.nReachShowdown)
		end
		--[[
		--按 "月->日" 记录
		sKey= string.format("TexaStatistic_%d_%s",tData.nUserId,sDateMonth)
		redis:hincrby(sKey,sDateDay.."_nPlayCount"..sT,tData.nPlayCount or 1)
		redis:hincrby(sKey,sDateDay.."_nInPoolCount"..sT,tData.nInPoolCount)
		redis:hincrby(sKey,sDateDay.."_nRaiseCountBFlop"..sT,tData.nRaiseCountBFlop)
		redis:hincrby(sKey,sDateDay.."_nAllInAndWinCount"..sT,tData.nAllInAndWinCount)
		redis:hincrbyfloat(sKey,sDateDay.."_nProfitSum"..sT,tData.nProfitSum)
		if tData.nJuShu and tData.nJuShu>0 then
			redis:hincrby(sKey,sDateDay.."_nJuShu"..sT,tData.nJuShu)
		end
		if tData.nSumBet and tData.nSumBet>0 then
			redis:hincrbyfloat(sKey,sDateDay.."_nSumBet"..sT,tData.nSumBet)
		end
		if tData.nWinCount and tData.nWinCount>0 then
			redis:hincrbyfloat(sKey,sDateDay.."_nWinCount"..sT,tData.nWinCount)
		end
		if tData.nQiPaiCount and tData.nQiPaiCount>0 then
			redis:hincrbyfloat(sKey,sDateDay.."_nQiPaiCount"..sT,tData.nQiPaiCount)
		end
		redis:expire(sKey,3600*24*60) --60天过期
		]]
	end
end

--主要起因按桌抽水,玩家离桌时抽水，改变了利润
function PublicRedis.TexaStatistic_ProfitAdd(nUserId, nProfit, tData)
	local sT = genStaticKey(tData)
	local sDateDay =os.date("%d", os.time())
	local sDateMonth =os.date("%y%m", os.time())
	local redis =tBase.m_MyRedisData[2].redis

	local sKey= string.format("TexaStatistic_%d",nUserId)
	redis:hincrbyfloat(sKey,"nProfitSum"..sT,nProfit)

	-- sKey= string.format("TexaStatistic_%d_%s",nUserId,sDateMonth)
	-- redis:hincrbyfloat(sKey,sDateDay.."_nProfitSum"..sT,nProfit)
end


--获得某年某月的最大天数
function getDayByYearMonth(_year, _month)
    local _curDate = {}
    _curDate.year = _year
    _curDate.month = _month + 1
    _curDate.day = 0
    local _maxDay = os.date("%d",os.time(_curDate))
    return _maxDay
end

--最近30天的统计数据
function PublicRedis.GetUserTexaStatisticL(nUserId,nClubId,nGameId,nGoldType)
	local redis =tBase.m_MyRedisData[2].redis
	local nNow =os.time()
	local nDateDay =tonumber(os.date("%d", nNow))
	local nLastMothTime =nNow-3600*24*(nDateDay+1)
	
	local tem ={}
	tem.nPlayCount=0
	tem.nInPoolCount=0
	tem.nRaiseCountBFlop=0
	tem.nAllInAndWinCount=0
	tem.nProfitSum=0
	tem.nJuShu =0

	local sT =string.format("_%d_%d_%d",nClubId,nGameId,nGoldType)

	--今个月的nDateDay天数据
	local sKey= string.format("TexaStatistic_%d_%s",nUserId,os.date("%y%m", nNow))	--今月
	local t =redis:hgetall(sKey) 													--今月数据
	for i=1,nDateDay do
		local sDay =string.format("%02d",i)
		tem.nPlayCount =tem.nPlayCount +tonumber(t[sDay.."_nPlayCount"..sT] or 0)
		tem.nInPoolCount =tem.nInPoolCount +tonumber(t[sDay.."_nInPoolCount"..sT] or 0)
		tem.nRaiseCountBFlop =tem.nRaiseCountBFlop +tonumber(t[sDay.."_nRaiseCountBFlop"..sT] or 0)
		tem.nAllInAndWinCount =tem.nAllInAndWinCount +tonumber(t[sDay.."_nAllInAndWinCount"..sT] or 0)
		tem.nProfitSum =tem.nProfitSum +tonumber(t[sDay.."_nProfitSum"..sT] or 0)
		tem.nJuShu =tem.nJuShu +tonumber(t[sDay.."_nJuShu"..sT] or 0)
	end
	if nDateDay>=30 then
		return tem
	end

	--上个月的(30-nDateDay)天数据;(3月1日时,由于上个月二月份是28天，只能得29天数据)
	local sLastKey= string.format("TexaStatistic_%d_%s",nUserId,os.date("%y%m", nLastMothTime))	 --上个月
	local tt =redis:hgetall(sLastKey) 															--上个月数据
	local sYear,sMoth =string.match(os.date("%Y-%m", nLastMothTime),"(%d+)-(%d+)")
	local nMaxDay =getDayByYearMonth(tonumber(sYear), tonumber(sMoth))
	local nMin =nMaxDay -(30 -nDateDay) +1
	for i=nMin,nMaxDay do
		local sDay =string.format("%02d",i)
		tem.nPlayCount =tem.nPlayCount +tonumber(tt[sDay.."_nPlayCount"..sT] or 0)
		tem.nInPoolCount =tem.nInPoolCount +tonumber(tt[sDay.."_nInPoolCount"..sT] or 0)
		tem.nRaiseCountBFlop =tem.nRaiseCountBFlop +tonumber(tt[sDay.."_nRaiseCountBFlop"..sT] or 0)
		tem.nAllInAndWinCount =tem.nAllInAndWinCount +tonumber(tt[sDay.."_nAllInAndWinCount"..sT] or 0)
		tem.nProfitSum =tem.nProfitSum +tonumber(tt[sDay.."_nProfitSum"..sT] or 0)
		tem.nJuShu =tem.nJuShu +tonumber(tt[sDay.."_nJuShu"..sT] or 0)
	end
	return tem
end

function PublicRedis.GetUserTexaStatistic(nUserId, tData)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey= string.format("TexaStatistic_%d",nUserId)
	local sT = genStaticKey(tData)

	local t =redis:hgetall(sKey)
	local tem ={}
	tem.nPlayCount=tonumber(t["nPlayCount"..sT] or 0)
	tem.nInPoolCount=tonumber(t["nInPoolCount"..sT] or 0)
	tem.nRaiseCountBFlop=tonumber(t["nRaiseCountBFlop"..sT] or 0)
	tem.nAllInAndWinCount=tonumber(t["nAllInAndWinCount"..sT] or 0)
	tem.nProfitSum=tonumber(t["nProfitSum"..sT] or 0)
	tem.nWinCount=tonumber(t["nWinCount"..sT] or 0)
	tem.nQiPaiCount=tonumber(t["nQiPaiCount"..sT] or 0)
	tem.nAllInCount=tonumber(t["nAllInCount"..sT] or 0)
	tem.nHandProfit=tonumber(t["nHandProfit"..sT] or 0)
	tem.nOpCount=tonumber(t["nOpCount"..sT] or 0)
	tem.nSeeFlop=tonumber(t["nSeeFlop"..sT] or 0)
	tem.nReachShowdown=tonumber(t["nReachShowdown"..sT] or 0)
	return tem
end

-- 返回玩家在某牌桌的最近结算时间戳
function PublicRedis.GetLastTexaTime(sTableName,nUserId)
	if true then
		return 0
	end
	local redis =tBase.m_MyRedisData[2].redis
	local sKey= "TexaUsersPlayTime"
	local sField =string.format("%d_%s",nUserId,sTableName)
	local sTime =redis:hget(sKey,sField)
	return tonumber(sTime)
end

-- 记录玩家在某牌桌的结算时间戳
function PublicRedis.SetTexaTime(sTableName,nUserId,nNow)
	if true then
		return
	end
	local redis =tBase.m_MyRedisData[2].redis
	local sKey= "TexaUsersPlayTime"
	local sField =string.format("%d_%s",nUserId,sTableName)
	redis:hset(sKey,sField,nNow)
end

--获取已被使用的从库
function PublicRedis.GetUsedDBRead()
	local redis =tBase.m_MyRedisData[1].redis
	local sKey= "UsedDBRead"
	local t = redis:hgetall(sKey)
	return t or {}
end

--设置已被使用的从库
function PublicRedis.SetUsedDBRead(nUsedDB)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey= "UsedDBRead"
	local sSubKey = string.format("Index_%d",nUsedDB)
	redis:hincrby(sKey,sSubKey,1)
end

--删除已被使用的从库
function PublicRedis.DelUsedDBRead(nUsedDB)
	if tBase and tBase.m_MyRedisData and tBase.m_MyRedisData[1] and tBase.m_MyRedisData[1].redis then
		local redis =tBase.m_MyRedisData[1].redis
		local sKey= "UsedDBRead"
		local sSubKey = string.format("Index_%d",nUsedDB)
		redis:hincrby(sKey,sSubKey,-1)
	end
end

--获取后台设置的配置
function PublicRedis.GetExtraConfigureInfo(nGroupId)
	return tRedisCahche.GetExtraConfigureInfo(nGroupId)
end

--获取直播跟投配置(nType 1:金额配置 2:倍数配置 3:局数配置)
function PublicRedis.GetLiveFollowConfig(nGameId,nGroupId,nType)
	return RedisCahche.GetLiveFollowConfig(nGameId,nGroupId,nType)
end

--获取 Redis 持久化数据 
function PublicRedis._GetRedisData(sKey,sSubKey)
	local redis =tBase.m_MyRedisData[2].redis 
	local t = redis:hget(sKey,""..sSubKey) 
	return t or {}
end

--返回table示例:
--[[
local cfg={}
cfg.nBet=10				        	--每注下注						(<0为无效)
cfg.nLossLimit=100		       		--亏损>x 时停止下注				(<0为无效)
cfg.nProfitLimit=50		      	  	--盈利>x 时停止追注				(<0为无效)
cfg.nStopTimestamp=os.time()	    	--/追注停止时间戳				(<0为无效)		
cfg.nWinSuccPause=10 		    	--好路连赢>x 次后暂停追注		(<0为无效)
cfg.nLossSuccPause=5 	        	--桌台连输>x 次后暂停下注30分钟	(<0为无效)
cfg.arrTableId={"360#001","360#002"}	--已选桌台id
cfg.arrTrendType={22,33}		    	--已选好路类型
cfg.nBetLogic=1			        	--下注逻辑(固定为1好路判断)
cfg.arrMulti={1,2,2,3,3}				--周期倍数
cfg.nBetStrategy=211		        	--投注策略 112(112投注),122(122投注),121(121投注),211(211投注),212(212投注),1(追输),2(赢追),3(固定基码)
									--4(鸡尾酒下注法) 5(天梯下注法) 6(五局八星A投) 7(五局八星B投) 8(五局八星C投2星级) 9(五局八星C投3星级) 10(五局八星C投4星级)
									--11(五局八星C投5星级) 12(五局八星C投6星级) 13(五局八星C投7星级) 14(五局八星C投7星级)
return cfg		
]]
function PublicRedis.GetUserAutoBetCfg(nUserId)
	if nUserId==nil then
		return
	end
	local redis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d",nUserId)
	local sCfg =redis:hget("LiveAutoBetUser",sSubkey)
	if sCfg==nil or #sCfg<2 then
		return
	end
	local tt= cjson.decode(sCfg) 
	tt.arrMulti=PublicRedis.tStToMulti[tt.nBetStrategy] or {1,1,1,1}
	return tt
end

local tStToMulti={}
tStToMulti[112]={(1),(1),(2)}			--112投注	
tStToMulti[122]={(1),(2),(2)}			--122投注	
tStToMulti[121]={(1),(2),(1)}			--121投注
tStToMulti[211]={(2),(1),(1)}			--211投注	
tStToMulti[212]={(2),(1),(2)}			--212投注	
tStToMulti[1]={(1),(2),(4),(8)}			--输追模式
tStToMulti[2]={(1),(2),(4),(8)} 		--赢追模式
tStToMulti[3]={(1),(1),(1),(1)} 		--固定底注
tStToMulti[4]={(1),(3),(2),(6)}			--鸡尾酒下注法
tStToMulti[5]={(1),(3),(6),(10),(15)} 	--天梯下注法
tStToMulti[6]={(1),(1),(2),(3),(5)} 	--五局八星A投	
tStToMulti[7]={(1),(1),(3),(6),(10)} 	--五局八星B投
tStToMulti[8]={(2),(2),(3),(4),(5)}		--五局八星C投2星级
tStToMulti[9]={(3),(3),(4),(5),(6)} 	--五局八星C投3星级
tStToMulti[10]={(4),(4),(5),(6),(7)} 	--五局八星C投4星级
tStToMulti[11]={(5),(5),(7),(9),(10)} 	--五局八星C投5星级
tStToMulti[12]={(6),(6),(8),(10),(12)} 	--五局八星C投6星级
tStToMulti[13]={(7),(7),(9),(12),(15)} 	--五局八星C投7星级
tStToMulti[14]={(8),(8),(10),(15),(20)} --五局八星C投8星级	
PublicRedis.tStToMulti=tStToMulti

--返回桌子所有玩家的自动下注配置
--返回数组示例: { {nUserId=10086,tCfg=tCfg},{nUserId=10087,tCfg=tCfg},{nUserId=10088,tCfg=tCfg} }
function PublicRedis.GetTableAllCfg(sTableId)
	if sTableId==nil then
		return {}
	end
	local redis =tBase.m_MyRedisData[2].redis
	local sSetKey =string.format("AutoBet:%s",sTableId)
	local arrUserId =redis:smembers(sSetKey) or {}
	local arrRt={}
	for _,sUserId in ipairs(arrUserId) do
		local nUserId =tonumber(sUserId)
		local tCfg =PublicRedis.GetUserAutoBetCfg(nUserId)
		if nUserId and tCfg then
			table.insert(arrRt,{nUserId=nUserId,tCfg=tCfg})
		end
	end
	return arrRt
end

--[[
function PublicRedis.AutoBetTableCloseNotify(sTableId,sTableName)
	local redis =tBase.m_MyRedisData[2].redis
	local sSetKey =string.format("AutoBet:%s",sTableId)
	local arrUserId =redis:smembers(sSetKey) or {}
	for _,sUserId in ipairs(arrUserId) do
		local nUserId =tonumber(sUserId)

	end
end
]]

--下注记录(投注后调用); 只记录玩家自动下注记录,主动下注不在本范围内。
--使用示例:
--	local tD ={sTableId="360#01",sPaiJuId="F0F",nTrendType=3,nBetArea=1,nBetGold=100} --各字段分别为:桌子id,局号,好路类型,下注区域,下注金币
--	AutoBetRecord(nUserId,tD)	
function PublicRedis.AutoBetRecord(nUserId,tD)
	local tItem ={nMsgId=2,tBet={},nTimestamp=os.time()}
	tItem.tBet.sTableId=tD.sTableId or "Nil"
	tItem.tBet.sPaiJuId=tD.sPaiJuId or "Nil"
	tItem.tBet.nTrendType=tD.nTrendType or -1
	tItem.tBet.nBetArea=tD.nBetArea or -1
	tItem.tBet.sTableName=tD.sTableName or "nil"

	--记录玩家本次运行所涉及的sPaiJuId
	PublicRedis.SaveBetPaiJuRelate(nUserId,tD.sPaiJuId)
	--保存记录
	PublicRedis._SaveRunMsgItem(nUserId,tItem)
	--通知监听者
	PublicRedis._NotifyUser(nUserId,tItem)

	--首条下注时，插入一条账务总览记录
	if PublicRedis._IncrBetCnt(nUserId)==1 then
		local sGrpNo,nTimeStart =PublicRedis.GetGrpNo(nUserId)
		if not sGrpNo then
			tBase.Log("AutoBetRecord BJLAutoBetRecordOverview_Start Do Fail")
			return
		end
		RecordDbr.BJLAutoBetRecordOverview_Start(nUserId,sGrpNo,nTimeStart)
	end
end

--结算记录(结算后调用); 只记录玩家自动下注记录,主动下注不在本范围内。
--使用示例:
--	local tD={sTableId="360#01",sPaiJuId="F0F",nXianDian=2,nZhuangDian=5,nProfit=100}	--各字段分别为:桌子id,局号,闲点数,庄点数,盈利
--	local nNowProfit=SettleRecord(nUserId,tD)		--返回结算后的总盈利
function PublicRedis.SettleRecord(nUserId,tD)
	local nXianDian =tD.nXianDian or 0
	local nZhuangDian =tD.nZhuangDian or 0
	local tItem={nMsgId=3,tResult={},nTimestamp=os.time()}
	tItem.tResult.sTableId=tD.sTableId or "nil"
	tItem.tResult.sTableName=tD.sTableName or "nil"
	tItem.tResult.sPaiJuId=tD.sPaiJuId or "nil"
	tItem.tResult.nProfit=tD.nProfit or 0
	tItem.tResult.nRlt=1							--1:闲赢 2:庄赢 0:和赢
	if nZhuangDian>nXianDian then
		tItem.tResult.nRlt=2
	elseif nZhuangDian==nXianDian then
		tItem.tResult.nRlt=0
	end
	local sGrpNo =PublicRedis.GetGrpNoByPaiJu(nUserId,tD.sPaiJuId)
	local sNowGrpNo,nStatus =PublicRedis._GetGrpNo(nUserId)
	if sGrpNo~=sNowGrpNo then
		return 0
	end
	--累加盈利
	local nNowProfit =PublicRedis._IncrProfit(nUserId,tItem.tResult.nProfit)


	tItem.tResult.nProfitSum =nNowProfit									--结算后盈亏余额
	tItem.tResult.nBalance =PublicRedis.Get_User_Gold(nUserId)					--结算后余额
	--保存记录
	PublicRedis._SaveRunMsgItem(nUserId,tItem)
	--通知监听者
	PublicRedis._NotifyUser(nUserId,tItem)
	
	return nNowProfit
end

--桌台连输而暂停记录(因桌台连输而暂停时调用)
--使用示例:
--	PauseByLossStraightRecord(nUserId,{sTableId="360#01",nPauseTime=30})
function PublicRedis.PauseByLossStraightRecord(nUserId,tD)
	local tItem={nMsgId=4,tLossPause={},nTimestamp=os.time()}
	tItem.tLossPause.sTableId=tD.sTableId or "nil"		--桌台id
	tItem.tLossPause.nPauseTime=tD.nPauseTime or 30		--暂停时间(固定30分钟)
	tItem.tLossPause.sTableName=tD.sTableName or "nil"		--桌台id
	--保存记录
	PublicRedis._SaveRunMsgItem(nUserId,tItem)
	--通知监听者
	PublicRedis._NotifyUser(nUserId,tItem)
end

--好路连赢而暂停记录(因好路连赢而暂停时调用)
--使用示例:
--PauseByWinStraightRecord(nUserId,{nTrendType=2})
function PublicRedis.PauseByWinStraightRecord(nUserId,tD)
	local tItem={nMsgId=5,tWinStop={},nTimestamp=os.time()}
	tItem.tWinStop.nTrendType=tD.nTrendType or -1
	tItem.tWinStop.sTableName=tD.sTableName or "nil"
	--保存记录
	PublicRedis._SaveRunMsgItem(nUserId,tItem)
	--通知监听者
	PublicRedis._NotifyUser(nUserId,tItem)
end
--停止运行记录
--nReason(停止原因 1触及止损点 2触及止盈点 3截止时间到 4玩家主动停止) 6金币不足 7停服维护  8 做主播停止
function PublicRedis.StopRecord(nUserId,nReason)
	local tItem={nMsgId=6,tStop={},nTimestamp=os.time()}
	tItem.tStop.nReason=nReason
	--保存记录
	PublicRedis._SaveRunMsgItem(nUserId,tItem)
	--通知监听者
	PublicRedis._NotifyUser(nUserId,tItem)
	--非主动停止运行
	if nReason~=4 then
		PublicRedis._StopAutoBetRun(nUserId)
	end
end

function PublicRedis.StopRecordV2(nUserId,nReason,sGrpNo)
	local sNowGrpNo =PublicRedis.GetGrpNo(nUserId)
	if sNowGrpNo~=sGrpNo then
		return
	end
	PublicRedis.StopRecord(nUserId,nReason)
end

--开始运行记录
function PublicRedis.StartRecord(nUserId)
	local tMsg ={nMsgId=1,nTimestamp=os.time()}
	--保存记录
	PublicRedis._SaveRunMsgItem(nUserId,tMsg)
	--通知监听者
	PublicRedis._NotifyUser(nUserId,tMsg)
end

--获取玩家自动下注状态
--返回: {nProfit=0,arrRunMsg={},tBetAutoConfig=cfg,nStatus=0}
function PublicRedis.GetAutoBetStatus(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local arrRlt =redis:hmget(sKey,"nProfit","nStatus","sCfg")
	local tCfgDefault={}
	tCfgDefault.nBet=-1						--每注下注						(<0为无效)
	tCfgDefault.nLossLimit=-1				--亏损>x 时停止下注				(<0为无效)
	tCfgDefault.nProfitLimit=-1				--盈利>x 时停止追注				(<0为无效)
	tCfgDefault.nStopTimestamp=-1			--/追注停止时间戳				(<0为无效)		
	tCfgDefault.nWinSuccPause=-1		    --好路连赢>x 次后暂停追注		(<0为无效)
	tCfgDefault.nLossSuccPause=-1	        --桌台连输>x 次后暂停下注30分钟	(<0为无效)
	tCfgDefault.arrTableId={}				--已选桌台id
	tCfgDefault.arrTrendType={}				--已选好路类型
	tCfgDefault.nBetLogic=1			        --下注逻辑(固定为1好路判断)
	tCfgDefault.nBetStrategy=211		    --投注策略 112(112投注),122(122投注),121(121投注),211(211投注),212(212投注),1(追输),2(赢追),3(固定基码)
	tCfgDefault.nRetainGold=0				--保留在下注系统的金币数量
	tCfgDefault.nFenMu=0					--一个分数的分母(后端不使用，仅作前端场景恢复用)

	local tCfg =tCfgDefault
	local sCfg =arrRlt[3] or ""
	if #sCfg>=2 then
		tCfg =cjson.decode(sCfg) 
	end
	local tRt ={}
	tRt.nProfit =tonumber(arrRlt[1]) or 0
	tRt.nStatus =tonumber(arrRlt[2]) or 0
	tRt.arrRunMsg =PublicRedis._GetRunMsg(nUserId)
	tRt.tBetAutoConfig=tCfg
	return tRt
end

--累加盈利(自动下注)
function PublicRedis._IncrProfit(nUserId,nIncrValue)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local sNew =redis:hincrbyfloat(sKey,"nProfit",nIncrValue)
	return tonumber(sNew) or 0
end

--获取累加盈利(自动下注)
function PublicRedis._GetIncrProfit(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local nProfit =redis:hget(sKey,"nProfit") 
	return tonumber(nProfit) or 0
end


--监听玩家运行记录
function PublicRedis.AddAutoBetListener(nUserId,sServKey)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	redis:hmset(sKey, {sListenServKey=sServKey,nListenTime=os.time()})
end
--停止监听运行记录
function PublicRedis.StopListenRunMsg(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	redis:hdel(sKey,"sListenServKey")
end
--保存配置并开始运行 {nStopTimestamp=,arrTableId={}}
function PublicRedis.SaveAndRun(nUserId,tCfg)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local sCfg =cjson.encode(tCfg)
	local tSave ={}

	local nTimeStart =os.time()
	local nTimeEnd =tCfg.nStopTimestamp

	--nProfit重新置0, nStatus(1开始,0停止)
	local sGrpNo =PublicRedis.CreateGrpNo()		--归类号(唯一标识一次运行)
	redis:hmset(sKey, {nProfit=0,nBetCnt=0,nStatus=1,sCfg=sCfg,nTimeStart=nTimeStart,nTimeEnd=nTimeEnd,nTimeMissing=nTimeStart,sGrpNo=sGrpNo})
	--清空玩家运行记录
	PublicRedis._ClearRunMsg(nUserId)
	--清空玩家下注记录表
	PublicRedis._ClearUserAutoBetPaiJu(nUserId)
	--清空玩家遗漏记录表
	 PublicRedis._ClearUserMissingRecord(nUserId)
	 --清空玩家遗漏胜率统计表
	 PublicRedis._ClearUserMissingWinRate(nUserId)

	--动态配置(停止运行时会删)
	nUserId =math.floor(nUserId)
	redis:hmset("LiveAutoBetUser",{[nUserId]=sCfg})

	--redis:hkeys(sKey)
	--设置离线转出金币时，保留不转出的数量
	tPublicUserGold.SetRetainGold(nUserId,tCfg.nRetainGold)

	--维护一个Table到Users的映射，以方便查询
	for _,sTableId in ipairs(tCfg.arrTableId) do
		local sSetKey =string.format("AutoBet:%s",sTableId)
		redis:sadd(sSetKey,nUserId)
	end
	
	PublicRedis._InitUserAutoBetStatistics(nUserId)	
	return sGrpNo
end

function PublicRedis._IncrBetCnt(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local sNew =redis:hincrby(sKey,"nBetCnt",1)
	return tonumber(sNew)
end

--获取当前归类号(自动下注,停止状态时返回nil)
function PublicRedis.GetGrpNo(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local arrRlt =redis:hmget(sKey,"nStatus","sGrpNo","nTimeStart")
	local nStatus =tonumber(arrRlt[1])
	local sGrpNo =arrRlt[2]
	local nTimeStart =tonumber(arrRlt[3])
	local sGrpNo,nStatus,nTimeStart =PublicRedis._GetGrpNo(nUserId)
	if nStatus==1 then			--运行状态时才返回
		return (sGrpNo or "ErrorGrpNo"),nTimeStart
	end
	return nil					--非运行状态时才返回nil
end

function PublicRedis._GetGrpNo(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local arrRlt =redis:hmget(sKey,"nStatus","sGrpNo","nTimeStart")
	local nStatus =tonumber(arrRlt[1])
	local sGrpNo =arrRlt[2]
	local nTimeStart =tonumber(arrRlt[3])
	return sGrpNo,nStatus,nTimeStart
end


--生成唯一归类号(自动下注)
function PublicRedis.CreateGrpNo()
	local time =os.time()
	local dex =tBase.m_MyRedisData[1].redis:incr("ForGrpNoCreate")
	if dex >=99999 then
		tBase.m_MyRedisData[1].redis:del("ForGrpNoCreate")
	end
	return string.format("%X:%05X",time,dex)
end

--记录sPaiJuId属于哪一次运行(归类号)
function PublicRedis.SaveBetPaiJuRelate(nUserId,sPaiJuId)
	local redis =tBase.m_MyRedisData[2].redis
	local sGrpNo =PublicRedis.GetGrpNo(nUserId)
	if (not sGrpNo) or (not sPaiJuId) then
		return false
	end
	local sKey =string.format("AutoBetPaiJuRelate:%d:%s",nUserId,sPaiJuId)
	redis:setex(sKey,3600,sGrpNo)	--假设下注后，一个小时内必然会进行结算
	return true
end

--根据sPaiJuId返回归类号
function PublicRedis.GetGrpNoByPaiJu(nUserId,sPaiJuId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetPaiJuRelate:%d:%s",nUserId,sPaiJuId)
	local sGrpNo =redis:get(sKey)
	return sGrpNo
end

--判断牌局id是否属于当前运行的自动下注
function PublicRedis.IsPaiJuBelongNow(nUserId,sPaiJuId)
	local sGrpNo =PublicRedis.GetGrpNoByPaiJu(nUserId,sPaiJuId)
	local sNowGrpNo =PublicRedis.GetGrpNo(nUserId)
	return (sGrpNo ==sNowGrpNo)
end


--返回所有正在自动下注玩家id ;return {001,002,003...}
function PublicRedis.GetAutoBetUsers()
	local redis =tBase.m_MyRedisData[2].redis
	local arr =redis:hkeys("LiveAutoBetUser") or {}
	local arrRlt={}
	for _,v in ipairs(arr) do
		table.insert(arrRlt,tonumber(v))
	end
	return arrRlt
end

--开服时调用 (停止所有玩家自动下注)
function PublicRedis.StopAllUsersAtBet()
	local redis =tBase.m_MyRedisData[2].redis
	local sLockKey="StopAllUsersAtBet"
	redis:lock(sLockKey)
    local arrUsers =PublicRedis.GetAutoBetUsers()
	for _,nUserId in ipairs(arrUsers) do
		PublicRedis._SaveRunMsgItem(nUserId,{nMsgId=6,tStop={nReason=9},nTimestamp=os.time()}) 	--保存记录
		PublicRedis._StopAutoBetRun(nUserId)
	end
	redis:unlock(sLockKey)
end


--好路结算记录(用于统计遗漏表)
function PublicRedis.GoodtrendSettle(nGroupId,sPaiJuId)
	local sKey =string.format("GoodtrendSettle:%d",nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local nNow=os.time()
	--插入
	redis:zadd(sKey,nNow,sPaiJuId)
	--移除太久的数据
	if (nNow%5) ==0 then
		redis:zremrangebyscore(sKey,0,(nNow-3600*24*30))
	end
end
--记录进行过自动投注的牌局(用于统计遗漏表)
function PublicRedis.SaveUserAutoBetPaiJu(nUserId,sPaiJuId,nIsOffLine)
	nIsOffLine=nIsOffLine or 0
	if sPaiJuId==nil or nUserId==nil then
		return
	end
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("DoAutoBetPaiJu:%d",nUserId)
	redis:hset(sKey,sPaiJuId,nIsOffLine)
end
--清空玩家下注记录表
function PublicRedis._ClearUserAutoBetPaiJu(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("DoAutoBetPaiJu:%d",nUserId)
	redis:del(sKey)
end
--玩家是否有在所指定的牌局下注(在线下注)
function PublicRedis._IsDoOnLineAutoBet(nUserId,sPaiJuId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("DoAutoBetPaiJu:%d",nUserId)
	local sIsOffLine =redis:hget(sKey,sPaiJuId)
	local nIsOffLine=tonumber(sIsOffLine)
	if nIsOffLine ==0 then	
		return true,nIsOffLine
	end
	return false,nIsOffLine
end

--清空玩家遗漏记录表
function PublicRedis._ClearUserMissingRecord(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserMissingPaiJu:%d",nUserId)
	redis:del(sKey)
end
--更新玩家遗漏记录表
function PublicRedis._UpdateUserMissingRecord(nUserId,nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local nNow =os.time()
	local nStart,nEnd,nMissing =PublicRedis.GetLatelyRunTime(nUserId)
	nStart=nStart or 0
	nEnd =nEnd or 0
	nMissing =nMissing or 0
	nStart=math.max(nStart,nMissing)
	nEnd=math.min(nEnd,nNow)
	if nStart==0 or nStart>nEnd then
		tBase.Log("_UpdateUserMissingRecord nStart:%d nEnd:%d nMissing:%d nNow:%d",nStart,nEnd,nMissing,nNow)
		return
	end
	local sKey =string.format("GoodtrendSettle:%d",nGroupId)
	local sKeyMissing =string.format("UserMissingPaiJu:%d",nUserId)
	local nDelta=60*15
	local nCnt =  idiv(nEnd-nStart,nDelta) + 1       --((nEnd-nStart)//nDelta)+1
	for i=0,nCnt do
		local nS =nStart+i*nDelta
		local nE =nStart+(i+1)*nDelta
		local arr =redis:zrangebyscore(sKey,nS,nE,"WITHSCORES") or {} 	--{[1]={[1]="member01",[2]="1600"},[2]={[1]="member03",[2]="1700"}}
		for _,arrV in ipairs(arr) do
			local sPaiJuId =arrV[1]
			local nTimestamp =tonumber(arrV[2])
			if nTimestamp<=nEnd and (not PublicRedis._IsDoOnLineAutoBet(nUserId,sPaiJuId)) then
				redis:zadd(sKeyMissing,nTimestamp,sPaiJuId) --该牌局属于遗漏牌局
			end
		end
		if nE>=nEnd then break end
	end
	local ssKey =string.format("AutoBetStatus_%d",nUserId)
	redis:hset(ssKey,"nTimeMissing",nNow)
end
 
--获取玩家的遗漏牌局
function PublicRedis.GetLatelyMissingRecord(nUserId,nMinDex,nCnt,nGroupId)
	nMinDex=math.floor(nMinDex)
	nCnt=math.floor(nCnt)
	if nMinDex==1 then
		return {}
	end
	PublicRedis._UpdateUserMissingRecord(nUserId,nGroupId)			--更新遗漏表
	local redis =tBase.m_MyRedisData[2].redis
	local sKeyMissing =string.format("UserMissingPaiJu:%d",nUserId)
	local nE =nMinDex-2
	if nMinDex<=0 then
		nE =redis:zcard(sKeyMissing)-1
	end
	local nS =nE-nCnt+1
	nS =math.max(nS,0)
	local arr =redis:zrange(sKeyMissing,nS,nE)
	local arrRt={}
	for _,sPaiJuId in ipairs(arr) do
		nS =nS +1
		local _,nIsOffLine =PublicRedis._IsDoOnLineAutoBet(nUserId,sPaiJuId)
		table.insert(arrRt,{Id=nS,sPaiJuId=sPaiJuId,nIsOffLine=nIsOffLine or 0})
	end
	return arrRt
end

 --local arrMissPaiju=tPublicRedis.GetUserMissingPaiJu(nUserId,50)
 --local tNowSt=tPublicRedis.UpdateUserMissingWinRate(nUserId,tSt)
function PublicRedis.GetUserMissingPaiJu(nUserId,nCnt,nGroupId)
	PublicRedis._UpdateUserMissingRecord(nUserId,nGroupId)
	nCnt=math.floor(nCnt)
	local redis =tBase.m_MyRedisData[2].redis
	local sKeyMissing =string.format("UserMissingPaiJu:%d",nUserId)
	local sKey =string.format("MissingWinRate:%d",nUserId)
	local sProgress =redis:hget(sKey,"Progress")
	local nS =tonumber(sProgress) or 0
	local nE =nS+nCnt-1
	local arr =redis:zrange(sKeyMissing,nS,nE) or {}
	redis:hset(sKey,"Progress",(#arr +nS))
	return arr
end
function PublicRedis.UpdateUserMissingWinRate(nUserId,tSt)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MissingWinRate:%d",nUserId)
	local tNowSt =redis:hgetall(sKey) or {}
	for k,v in pairs(tSt) do
		tNowSt[k]=tNowSt[k] or 0
		tNowSt[k] =tonumber(tNowSt[k]) +v
	end
	redis:hmset(sKey, tNowSt)
	return tNowSt
end
function PublicRedis._ClearUserMissingWinRate(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MissingWinRate:%d",nUserId)
	redis:del(sKey)
end


--获取最近一次运行的开始与结束时间
--示例:local nTimeStart,nTimeEnd =GetLatelyRunTime()
function PublicRedis.GetLatelyRunTime(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	local arrRlt =redis:hmget(sKey,"nTimeStart","nTimeEnd","nTimeMissing")
	local nTimeStart =tonumber(arrRlt[1])
	local nTimeEnd =tonumber(arrRlt[2])
	local nTimeMissing =tonumber(arrRlt[3])
	return nTimeStart,nTimeEnd,nTimeMissing
end

--主动点击停止运行
function PublicRedis.StopAutoBetRun(nUserId)
	PublicRedis._StopAutoBetRun(nUserId)
	PublicRedis._DelAutoBetStatistics(nUserId)	
end

--停止运行(主动或自动)
function PublicRedis._StopAutoBetRun(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AutoBetStatus_%d",nUserId)
	--已经停止了的，不再重复停止
	local sGrpNo =PublicRedis.GetGrpNo(nUserId)
	if sGrpNo==nil then	
		return
	end
	--离线转出金币时，保留的数量设置为0
	tPublicUserGold.SetRetainGold(nUserId,0)
	--更改状态 nStatus(1开始,0停止)
	local nTimeEnd =os.time()
	redis:hmset(sKey, {nStatus=0,nTimeEnd=nTimeEnd})
	--取得当前配置
	local tCfg=PublicRedis.GetUserAutoBetCfg(nUserId)
	--删除动态配置
	nUserId =math.floor(nUserId)
	redis:hdel("LiveAutoBetUser",tostring(nUserId))
	--更新映射表
	if tCfg then
		for _,sTableId in ipairs(tCfg.arrTableId) do
			local sSetKey =string.format("AutoBet:%s",sTableId)
			redis:srem(sSetKey,nUserId)
		end
	end

	PublicRedis._DelAutoBetStatistics(nUserId)	

	--更新总览记录的结束时间和标志
	RecordDbr.BJLAutoBetRecordOverview_End(nUserId,sGrpNo,nTimeEnd)
end


--获取运行记录
function PublicRedis._GetRunMsg(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserAutoBetMsg:%d",nUserId)
	local arr =redis:lrange(sKey,-50,-1)   --最近100个元素
	arr =arr or {}
	local arrRt={}
	for _,v in ipairs(arr) do
		table.insert(arrRt,cjson.decode(v))
	end
	return arrRt
end
--保存运行记录(自动下注运行记录)
function PublicRedis._SaveRunMsgItem(nUserId,tItem)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserAutoBetMsg:%d",nUserId)
	local sItem =cjson.encode(tItem)
	--插入
	redis:rpush(sKey,sItem)
	redis:ltrim(sKey,(-100),-1)		--只保留最近的100条数据
	return sItem
end
--清空玩家运行记录
function PublicRedis._ClearRunMsg(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserAutoBetMsg:%d",nUserId)
	redis:ltrim(sKey,1,0)
end

--通知监听者(自动下注运行记录)
function PublicRedis._NotifyUser(nUserId,tMsg)
	local redis =tBase.m_MyRedisData[2].redis
	local ssKey =string.format("AutoBetStatus_%d",nUserId)
	local arrRlt =redis:hmget(ssKey,"sListenServKey","nListenTime")
	local sServKey =arrRlt[1] or ""
	local nListenTime=tonumber(arrRlt[2]) or 0

	if #sServKey==0 then
		return
	end
	if not (nListenTime>= PublicRedis.nServStartTime) then
		return
	end

	local tPostData={}
	tPostData.nUserId=nUserId
	tPostData.tItem=tMsg
	local sPostStr =cjson.encode(tPostData)
	local tPacket = tBase.GetSP().new(301, 100) 
    tPacket:AddString(sPostStr) 
	local nRes =tBase.PostToServer(sServKey, 0, tPacket:GetData(), tPacket:GetSize())
	-- tBase.Log("_NotifyUser nUserId:%d sServKey:%s nRes:%s",nUserId,sServKey,tostring(nRes))
	if nRes ~=1 then
		PublicRedis.StopListenRunMsg(nUserId)
	end
end

-- 初始化 自动下注 用户统计 
function PublicRedis._InitUserAutoBetStatistics(nUserId)
	local cfg = PublicRedis.GetUserAutoBetCfg(nUserId)
	if not cfg then 
		tBase.Log("_InitUserAutoBetStatistics  任务不存在了 nUserId_%d ",nUserId)
		return 
	end 
	assert(cfg~=nil)
	local arrTableLinkLose={}			--桌台连输次数 
	local arrGoodThreadWin={}			--好路连赢次数  
	for _, sTableId in ipairs(cfg.arrTableId) do				--已选桌台id	
		arrTableLinkLose[sTableId]={nLinkLose=0,nPauseTime=-1}		-- nLinkLose 输次数, nPauseTime：暂停时间戳,-1则无
		local arrLinkWin = {}
		for _,nGTType in ipairs(cfg.arrTrendType) do	 	--已选好路类型
			nGTType = string.format("%d",nGTType)		
			arrLinkWin[nGTType] = {isStop=false,nLinkWin=0} -- nGTType: 好路类型, nLinkWin: 连赢次数,isStop 暂停
		end	
		arrGoodThreadWin[sTableId] = arrLinkWin 
	end	
	
	local tData = {}
	tData.nLoseWin = 0  						--当前 输赢   
	tData.arrTableLinkLose = arrTableLinkLose  	--当前 桌台连输次数 
	tData.arrGoodThreadWin = arrGoodThreadWin  	--当前 好路连赢次数 	
	local tStatistics = cjson.encode(tData)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d",nUserId)
	local arrRlt =tRedis:hmset("AutoBet_UserStatistics",sSubkey,tStatistics)	
 
	PublicRedis._Handle_AutoBet_BetMultiple(1,nUserId,cfg)	 
	return 1
end

--[[--返回table示例:
   local cfg={} 
   cfg.nLoseWin=0		       											--当前 输赢   
   cfg.arrTableLinkLose={sTableId,nLinkLose,nPauseTime}    				--桌台连输次数  	
   cfg.arrGoodThreadWin={sTableId,arrLinkWin=[nGTType,nLinkWin]} 		--好路连赢次数  
   return cfg
]]
-- 自动下注统计数据   
function PublicRedis.GetUserAutoBetStatistics(nUserId)
	if nUserId==nil then return	end
	local tRedis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d",nUserId)
	local sCfg =tRedis:hget("AutoBet_UserStatistics",sSubkey) 
	if not sCfg then 
		tBase.Log("_GetUserAutoBetStatistics  任务不存在了 nUserId_%d",nUserId)
		return 
	end 
	return cjson.decode(sCfg) 
end

function PublicRedis._ChangeAutoBetStatistics(nUserId,tStatistics)	
	local tRedis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d",nUserId) 
	tRedis:hmset("AutoBet_UserStatistics",sSubkey,cjson.encode(tStatistics)) 
end 

-- 重置统计数据：nReset：1:重置好路连赢, 2:重置牌桌连输，3: 重置连输连赢
function PublicRedis._ResetAutoBetStatistics(nUserId,sTableId,nReset)   
	local cfg = PublicRedis.GetUserAutoBetCfg(nUserId)
	if not cfg then 
		tBase.Log("_ResetAutoBetStatistics  无任务 nUserId_%d %s",nUserId,sTableId)
		PublicRedis._DelAutoBetStatistics(nUserId)	
		return 
	end   
	local tStatistics = PublicRedis.GetUserAutoBetStatistics(nUserId)
	if not tStatistics then 
		tBase.Log("_UpdateAutoBetStatistics  无统计数据 nUserId_%d",nUserId)
		return 
	end   
	local sLog =""
	if nReset == 1 then   -- 重置好路连赢
		local arrLinkWin = tStatistics.arrGoodThreadWin[sTableId] 
		if arrLinkWin then 
			for nType, v in pairs(arrLinkWin) do	
				arrLinkWin[nType] = {isStop=false,nLinkWin=0}  
			end 	
			tStatistics.arrGoodThreadWin[sTableId]=arrLinkWin	
			sLog="重置连赢"
		end 		
	elseif nReset == 2 then  -- 重置牌桌连输
		if tStatistics.arrTableLinkLose[sTableId] then 
			tStatistics.arrTableLinkLose[sTableId] = {sTableId=sTableId,nLinkLose=0,nPauseTime=-1}
			sLog="重置连输"
		end 
	elseif nReset == 3 then  -- 重置连输连赢
		local arrLinkWin = tStatistics.arrGoodThreadWin[sTableId] 
		if arrLinkWin then 
			for nType, v in pairs(arrLinkWin) do	
				arrLinkWin[nType] = {isStop=false,nLinkWin=0}  
			end 	
			tStatistics.arrGoodThreadWin[sTableId]=arrLinkWin	
		end 	
		if tStatistics.arrTableLinkLose[sTableId] then 
			tStatistics.arrTableLinkLose[sTableId] = {sTableId=sTableId,nLinkLose=0,nPauseTime=-1}
		end 	
		sLog="重置连输连赢"
	end 	 
	local tRedis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d",nUserId) 
	tRedis:hmset("AutoBet_UserStatistics",sSubkey,cjson.encode(tStatistics)) 
	tBase.Log("_ResetAutoBetStatistics  nUserId_%d sTableId_%s nReset_%d %s ",nUserId,sTableId,nReset,sLog)
	return
end

function PublicRedis._DelAutoBetStatistics(nUserId)	
	local tRedis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d",nUserId) 
	tRedis:hdel("AutoBet_UserStatistics",sSubkey) 
	tBase.Log("_DelAutoBetStatistics  删除统计 nUserId_%d ",nUserId) 

	PublicRedis._Handle_AutoBet_BetMultiple(3,nUserId)	
end

-- 操作自动下注倍数： nHandle 1：初始化、2: 修改、3: 删除
function PublicRedis._Handle_AutoBet_BetMultiple(nHandle,nUserId,tData)	
	local tRedis =tBase.m_MyRedisData[2].redis
	local sSubkey =string.format("%d_",nUserId) 
	local sKey = "AutoBet_UserTable_BetMultiple"
	if nHandle == 1 then 
		for _, sTableId in ipairs(tData.arrTableId) do				--已选桌台id	
			local tBetMultiple = {}
			tBetMultiple.sTableId= sTableId   	     		 
			tBetMultiple.nMultiple = tData.arrMulti[1] or 1   	 -- 策略倍数 
			tBetMultiple.arrWinLoseRecord= {}   	     		 -- 桌子下注输赢记录
			local sSubkey = sSubkey..sTableId
			tRedis:hmset(sKey,sSubkey,cjson.encode(tBetMultiple)) 
		end 
	elseif nHandle == 2 then
		sSubkey = sSubkey..tData.sTableId
		tRedis:hmset(sKey,sSubkey,cjson.encode(tData)) 
	elseif nHandle == 3 then		
		tRedis:hdel(sKey,sSubkey.."*") 
	elseif nHandle == 4 then		
		sSubkey = sSubkey..tData.sTableId
		local tBetMultiple = tRedis:hget(sKey,sSubkey) 
		if tBetMultiple then 
			return cjson.decode(tBetMultiple)
		else
			return 
		end 
	end 
end 

--List测试
function PublicRedis.TestList()
	local redis =tBase.m_MyRedisData[2].redis
	--插入
	redis:rpush("TestList","item1")
	redis:rpush("TestList","item2")
	redis:rpush("TestList","item3")
	redis:rpush("TestList","item4")
	--查找
	local arr =redis:lrange("TestList",(-3),-1)   --取最后3个元素
	tBase.LogT("TestList the last three item:",arr)
	--删除
	redis:ltrim("TestList",-3,-1)				--只保留最近插入的3个元素
	arr =redis:lrange("TestList",0,-1)
	tBase.LogT("TestList all item after trim:",arr)
end

function PublicRedis.TestSortedSet()
	local redis =tBase.m_MyRedisData[2].redis
	--插入
	redis:zadd("TestSortedSet",1600,"member01")
	redis:zadd("TestSortedSet",1500,"member02")
	redis:zadd("TestSortedSet",1700,"member03")
	redis:zadd("TestSortedSet",1800,"member04")
	redis:zadd("TestSortedSet",1800,"member05")

	--查找(按分数闭区间)
	local arr =redis:zrangebyscore("TestSortedSet",1600,1700,"WITHSCORES")
	tBase.LogT("TestSortedSet items:",arr)	--{[1]={[1]="member01",[2]="1600"},[2]={[1]="member03",[2]="1700"}}

	local nN =redis:zcard("TestSortedSet")
	tBase.Log("zcard:%d",nN)			---5

	--ZREVRANGE salary 0 -1 WITHSCORES     # 递减排列
	arr =redis:zrange("TestSortedSet",0,-1)
	tBase.LogT("TestSortedSet itemss0:",arr)		--{[1]="member02",[2]="member01",[3]="member03",[4]="member04"}
end

--俱乐部牌桌名计数:  nHandle 1:设置、2:更新、3:获取、4:删除
function PublicRedis._HandleClubOpenTableNameCount(nHandle,nGroupId,nGameId,nOpenTableCfgId,sTableNo) 
	local Redis = tBase.m_MyRedisData[2].redis
	-- local sKey = string.format("ClubTableCfg_NameConut_%d_%d_CfgId_%s",nGroupId,nGameId,nOpenTableCfgId)
	local sKey = string.format("ClubTableCfg_NameConut_%d_%d",nGroupId or -1,nGameId or -1)
	if nHandle <= 2 then
		local nCnt = Redis:incr(sKey)
		if tonumber(nCnt) >= 900000000 then
			Redis:set(sKey,1)
		end
		return tonumber(nCnt)
	elseif nHandle == 3 then
		local arrKey = Redis:keys("ClubTableCfg_NameConut_*")
		if arrKey and #arrKey > 0 then
			tBase.Log("_HandleClubOpenTableNameCount 每月1号零点重置 arrKey: "..(#arrKey or 0))
			for _, sKey in pairs(arrKey) do
				Redis:del(sKey)
			end
		else
			tBase.Log("_HandleClubOpenTableNameCount 每月1号零点重置 arrKey: "..(#arrKey or 0))
		end
	elseif nHandle == 4 then
		Redis:del(sKey)
	end
end

--俱乐部开桌配置:  nHandle 1:更新、2:获取、3:删除
function PublicRedis._HandleClubTableCongfig(nHandle,nGroupId,nClubId,nGameId,nOpenTableCfgId,tTableConfig)
	local Redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubTableCfg_OpenTable_%d_%d",nClubId,nGroupId)
	local sSubKey = string.format("nGameId_%d_CfgId_%s",nGameId,nOpenTableCfgId)
	if nHandle == 1 then
		tBase.Log("_HandleClubTableCongfig  sKey_%s sSubKey: %s cfg: %s",sKey,sSubKey, cjson.encode(tTableConfig))
		Redis:hset(sKey,sSubKey,cjson.encode(tTableConfig))
	elseif nHandle == 2 then
		local tTableConfig = Redis:hget(sKey,sSubKey)
		if not tTableConfig then
			return
		end
		return cjson.decode(tTableConfig)
	elseif nHandle == 3 then
		Redis:hdel(sKey,sSubKey)
		-- PublicRedis._HandleClubOpenTableNameCount(4,nGroupId,nGameId,nOpenTableCfgId)
	end
end

--俱乐部牌桌 开始游戏:  nHandle 1:设置、2:更新并获取、3:删除、4:获取,5获取全部
function PublicRedis._HandleClubTableStartGame(nHandle,nGroupId,nGameId,nOpenTableCfgId,sTableId,tData) 
	local Redis = tBase.m_MyRedisData[1].redis 
	local sKey = string.format("ClubTableCig_StartGame_%d_%d_CfgId_%s",nGroupId,nGameId,nOpenTableCfgId) 
	local sSubKey = sTableId 
	if nHandle == 1 then
		if tData.sTableId and #tData.sTableId > 1 then 
			local tTableInfo = Redis:hget(sKey,tData.sTableName)
			if not tTableInfo then 
				tBase.Log("_HandleClubTableStartGame  sKey_%s sSubKey: %s ",sKey,sSubKey)
				return nil 
			end 
			tTableInfo = cjson.decode(tTableInfo)		
			tTableInfo.sTableId = tData.sTableId  	
			tTableInfo.sTableName = tData.sTableName  		 		
			tData = tTableInfo						
			Redis:hdel(sKey,tData.sTableName) 			
		end 
		Redis:hset(sKey,sSubKey,cjson.encode(tData))  
	elseif nHandle == 2 then
		local tTableInfo = Redis:hget(sKey, sSubKey)
		if not tTableInfo then
			return nil
		end
		tTableInfo = cjson.decode(tTableInfo)
		if tData.isStartGame ~= nil then
			tTableInfo.isStartGame = tData.isStartGame or false
		end
		if tData.hadAutomatic ~= nil then
			tTableInfo.hadAutomatic = tData.hadAutomatic or false
		end

		Redis:hset(sKey, sSubKey, cjson.encode(tTableInfo))
		local arr = Redis:hgetall(sKey)
		if not arr then
			return nil
		end
		local arrTableInfo = {}
		for sSubKey, v in pairs(arr) do
			table.insert(arrTableInfo, cjson.decode(v))
		end
		return arrTableInfo
	elseif nHandle == 3 then
		Redis:hdel(sKey,sSubKey)
	elseif nHandle == 4 then
		local tTableInfo = Redis:hget(sKey,sSubKey) 
		if not tTableInfo then 
			return nil 
		end 
		tTableInfo = cjson.decode(tTableInfo)	
		return tTableInfo	
	elseif nHandle == 5 then
		local arr  = Redis:hgetall(sKey) 
		if not arr then 
			return nil 
		end 
		local arrTableInfo = {}
		for sSubKey, v in pairs(arr) do
			table.insert(arrTableInfo, cjson.decode(v))
		end
		return arrTableInfo
	end 
	return nil 
end

--切换中心服时 旧服是否打开牌桌列表  nHandle 1:设置、2:获取删除 
function PublicRedis._SwitchServer_Old_OpenTableList(nHandle,nUserId) 
	local Redis = tBase.m_MyRedisData[1].redis 
	local sKey = string.format("SwitchServer_Old_OpenTableList_%d ",nUserId)  
	if nHandle == 1 then  
		Redis:set(sKey,1) 
		Redis:expire(sKey,2)  
	else
		if Redis:exists(sKey) then  
			return true 
		end 
	end 
end 

-- 操作共享主播牌桌: 1获取 、2设置、3删除、4获取全部牌桌
function PublicRedis._HadleShareLiveTable(nHandle,nGroupId,nLiveUserID,nShareGroupId,sTableId)
	local tRedis =tBase.m_MyRedisData[1].redis 
	local sKey = string.format("ShareLiveTable_%d_%d",nGroupId,nLiveUserID)
	local sSubKey = string.format("%d",nShareGroupId or -1)
	if nHandle == 1 then   
		return tRedis:hget(sKey,sSubKey) 
	elseif nHandle == 2 then
		tRedis:hset(sKey,sSubKey,sTableId) 
	elseif nHandle == 3 then
		tRedis:hdel(sKey,sSubKey) 	
	elseif nHandle == 4 then		
		local tData = tRedis:hgetall(sKey) 
		local arrTableId ={}
		for nShareGroupId, sTableId in pairs(tData) do
			table.insert(arrTableId,sTableId)
		end
		return arrTableId
	end 	
end

-- 服务器信息 
function PublicRedis._HandleServerInfo(nHandle) 
    local sKey =string.format("SeverInfoConfig")
	local tRedis = tBase.m_MyRedisData[1].redis 
	local tServerInfoCfg = tRedis:hgetall(sKey)
	local arrServerInfo ={}
	for nServerId, sInfo in pairs(tServerInfoCfg) do
		local row= cjson.decode(sInfo)
        local t ={}
        t.nServerId=tonumber(row.nServerId)
        t.sName= row.Name or ""
        t.nStype=tonumber(row.nStype) 
        t.nPort=tonumber(row.nPort)
        t.nSocketType=tonumber(row.nSocketType)
        t.nMachineID=tonumber(row.nMachineID)
        t.nState=tonumber(row.nState)   
		arrServerInfo[t.nServerId] = t
	end
	return arrServerInfo
end


function PublicRedis.GetVeriCodeByPhoneUrl()
	local tRedis = tBase.m_MyRedisData[2].redis 
	local host =tRedis:hget("IMAppWebKey","sPhoneUrl")
	if not host then
		return
	end
	return string.format("%sphone/SendSMS?phone=%%s&code=%%s&CountryCode=%%s",host)
	--return tRedis:get("VeriCodeByPhoneUrl")
end
function PublicRedis.GetVeriCodeByMailUrl()
	local tRedis = tBase.m_MyRedisData[2].redis 
	local host =tRedis:hget("IMAppWebKey","sPhoneUrl")
	if not host then
		return
	end
	return string.format("%sphone/SendEmail?email=%%s&code=%%s",host)
	--return tRedis:get("VeriCodeByMailUrl")
end


function PublicRedis.GetVeriCodeByPhoneUrlForeign()
	return PublicRedis.GetVeriCodeByPhoneUrl()
end
--获取手机绑定活动金币奖励数目
function PublicRedis.GetBindPhoneAward(nGroupId)
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("ClubActiSwitch_%d",nGroupId)
	local sAWard =tRedis:hget(sKey,"isBindActionGold")
	return tonumber(sAWard) or 200
end

-- 获取投降上报 URL
function PublicRedis._GetSurrenderUrl()
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sDomainName =tRedis:hget("IMAppWebKey","BlockchainUrl")
	if not sDomainName then
		return
	end
	return sDomainName
end

-- 获取投降配置
function PublicRedis._GetSurrenderCfg(nGroupId)
	local tCfg={}
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sCfgKey = string.format("GSP_UserRule")   
	local sData = tRedis:hget(sCfgKey,math.floor(nGroupId))  
	if not sData then 
		tCfg.nSurrenderCfg = 5
		tCfg.nSurrenderWinCfg = 5
	else
		local tData = cjson.decode(sData) 
		tCfg.nSurrenderCfg = tonumber(tData.nSurrenderCfg)
		tCfg.nSurrenderWinCfg = tonumber(tData.nSurrenderWinCfg)
	end 
 	return tCfg
end
 
-- 正常输赢 重置统计数据
function PublicRedis._ResetSurrenderStatistics(nUserId)
	local sKey = string.format("SurrenderStatistics_%d",nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	if not tRedis:exists(sKey) then 
		tBase.Log("_ResetSurrenderStatistics  sKey: %s   没有数据 ",sKey)
		return
	else
		tRedis:del(sKey)   -- 先删除不连续用户
		tBase.Log("_ResetSurrenderStatistics  sKey: %s   正常输赢重置",sKey)
	end 
end 

-- 投降统计
function PublicRedis._SurrenderStatistics(nGroupId,nLoseUserId,arrWinUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local tCfg = PublicRedis._GetSurrenderCfg(nGroupId)
	local nSurrenderCfg = tCfg.nSurrenderCfg        -- 投降次数 
	local nSurrenderWinCfg = tCfg.nSurrenderWinCfg -- 被投降赢次数 
	local sKey = string.format("SurrenderStatistics_%d",nLoseUserId)
	local arr={} 
	for _, nWinUserId in ipairs(arrWinUserId) do  
		arr[nWinUserId]=0
	end	 
	if not tRedis:exists(sKey) then 
		tBase.Log("_SurrenderStatistics  sKey: %s   没有数据 ",sKey)
	else
		local arrList= tRedis:hgetall(sKey)  
		tRedis:del(sKey)   -- 先删除不连续用户 
		for nId, nLoseCnt in pairs(arrList) do
			local nWinUserId = math.floor(nId) 
			local sLog =" 没参与本局,清除数据"
			for _, v in ipairs(arrWinUserId) do 
				if nWinUserId == v then 
					arr[nWinUserId] = tonumber(nLoseCnt) 
					sLog =" 参与本局 "
					break				
				end 
			end  
			tBase.Log("_SurrenderStatistics  sKey: %s   nId_%d  %s  nLoseCnt_%d ",sKey,nId,sLog,tonumber(nLoseCnt))
		end  
	end    
	local arrLoseReported = {} -- 投降用户
	local arrWinReported = {}  -- 被投降用户

	for nId, nLoseCnt in pairs(arr) do 
		-- 统计投降者
		local nWinUserId = math.floor(nId)  
		local nCnt = tonumber(nLoseCnt) + 1 
		local sLog="先统计"
		if nCnt > nSurrenderCfg then  
			table.insert(arrLoseReported,nLoseUserId)
			sLog="投降的上报APP"
		else
			tRedis:hset(sKey,nWinUserId,nCnt)	
		end  		 
		-- 统计被投降
		local sWinKey = string.format("BySurrender_%d",nWinUserId) 		
		local nCnt1 = tRedis:incrby(sWinKey,1) or 0
		tRedis:expire(sWinKey,60*60*24)   
		local sLog1="先统计"
		if tonumber(nCnt1) > nSurrenderWinCfg then  
			table.insert(arrWinReported,nWinUserId)
			sLog1="被投降上报APP" 
			tRedis:del(sWinKey)   
		end  	 
		tBase.Log("_SurrenderStatistics  投降用户:%d %s %d   被投降用户:%d  %s %d  tCfg: %s  "
		,nLoseUserId,sLog,tonumber(nCnt),nWinUserId,sLog1,tonumber(nCnt1),cjson.encode(tCfg))
	end
	tRedis:expire(sKey,60*60*24)   

	if #arrLoseReported == 0 and #arrWinReported ==0 then 
		tBase.Log("_SurrenderStatistics  没有数据上报 arrLoseReported_%d arrWinReported_%d  ",#arrLoseReported,#arrWinReported)
		return 
	else
		tBase.Log("_SurrenderStatistics  数据上报 arrLoseReported_%s arrWinReported_%s  ",cjson.encode(arrLoseReported),cjson.encode(arrWinReported))
	end 

	local sDomainName = PublicRedis._GetSurrenderUrl()
	if not sDomainName then 
		tBase.Log("_SurrenderStatistics   sDomainName  is nil ")
		return
	end 
	local function PushWeb(nType,arr)
		for _, nId in ipairs(arr) do
			local sUrl = string.format("table/ReportUsers?type=%d&memberId=%d",nType,nId)  --   type 2:灰名单 3：黑名单 
			local sHttp = sDomainName..sUrl
			tBase.Log("_SurrenderStatistics PushWeb 上报APP sKey: %s  sHttp: %s  ",sKey,sHttp)
			tBase.PublicPushWebHttp(sHttp) 		
		end	
	end
	PushWeb(2,arrLoseReported)
	PushWeb(3,arrWinReported)
 
end

--上报异常用户(对压)
--type 2:灰名单 3：黑名单 
function PublicRedis.AbnormalUserReport(nUserId,nType)
	local sDomainName = PublicRedis._GetSurrenderUrl()
	if not sDomainName then 
		tBase.Log("AbnormalUserReport fail. no config")
		return -1
	end 
	local sUrl = string.format("%stable/ReportUsers?type=%d&memberId=%d&code=107",sDomainName,nType,nUserId)
	tBase.PublicPushWebHttp(sUrl) 	
	tBase.Log("AbnormalUserReport nUserId:%d nType:%d",nUserId,nType)
	return 0
end

function PublicRedis.AddAbnormalCnt(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sField =string.format("%d",nUserId)
	local sCnt = tRedis:hincrby("AbnormalUsers",sField,1) 
	return tonumber(sCnt)
end

function PublicRedis.DelAbnormalCnt(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sField =string.format("%d",nUserId)
	tRedis:hdel("AbnormalUsers",sField)
end

function PublicRedis.GetAiUrl(nGroupId)
	local fFunc =function(nGroupId)
		local redis =tBase.m_MyRedisData[2].redis
		local sKey ="TexasAiUrl"
		local sField=string.format("GroupId%d",nGroupId)
		local arrRlt =redis:hmget(sKey,sField,"Default")   
		if arrRlt[1] and #arrRlt[1] > 2 then  
			local arrGroup = cjson.decode(arrRlt[1])
			local nRandom = math.random(1,#arrGroup)
			local sUrl =arrGroup[nRandom]
			if sUrl and #sUrl>0 then
				tBase.Log("_GetAiUrl    sUrl:  "..sUrl)
				return sUrl
			end 
		end  	
		if arrRlt[2] and #arrRlt[2] > 2 then  
			local arrDefault = cjson.decode(arrRlt[2])
			local nRandom = math.random(1,#arrDefault)
			local sUrlDefault =arrDefault[nRandom]
			if sUrlDefault and #sUrlDefault>0 then
				tBase.Log("_GetAiUrl    sUrlDefault:  "..sUrlDefault)
				return sUrlDefault
			end 
		end  
		return 
	end
	local isSuccee,sUrl =pcall(fFunc,nGroupId)   
	if isSuccee then 
		return sUrl 
	else 
		tBase.Log("_GetAiUrl  sUrl is nil  error ".. sUrl ..  " nGroupId:  "..nGroupId)
		return 
	end 
end
 
--红黑彩玩法模式
function PublicRedis.GetState(nGroupId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey ="GroupNation"
	local sField=string.format("GroupId%d",nGroupId)
	local sNation =tRedis:hget(sKey,sField)
	return tonumber(sNation) or 0		--0:泰国 1:大陆
end

--真人达到多少时，禁止机器人进入牌桌
function PublicRedis.RealCountForBanRobot(nGroupId,nGameId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey ="RealCountForBanRobot"
	local sField=string.format("GroupId%d:GameId%d",nGroupId,nGameId)
	local sCnt =tRedis:hget(sKey,sField)
	return tonumber(sCnt)		
end

--获取并删除德州下局需要控赢的玩家id
function PublicRedis.GetCrtlWinUsers(sTableId,isDel)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey ="GSP_DZOpposingcard"
	local sArrUserId =tRedis:hget(sKey,sTableId)
	if sArrUserId and isDel then
		tRedis:hdel(sKey,sTableId)
	end
	return sArrUserId
end

--获取并删除德州下局预设牌设置
function PublicRedis.GetPreSetInfo(sTableId,isDel)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("APIOpenTale_%s",sTableId)
	local sField ="sPreSetCard"
	local sInfo =tRedis:hget(sKey,sField)
	if sInfo and isDel then
		tRedis:hdel(sKey,sField)
	end
	return sInfo
end

--德州比赛相关
function PublicRedis.SetMttField(sUkey,sField,sValue)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MTTUsers_%s",sUkey)
	tRedis:hset(sKey,sField,sValue)
end
function PublicRedis.GetMttField(sUkey,sField)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MTTUsers_%s",sUkey)
	if sField==nil then
		return tRedis:hgetall(sKey) 
	end
	return tRedis:hget(sKey,sField)
end
function PublicRedis.DelMttField(sUkey,sField)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MTTUsers_%s",sUkey)
	tRedis:hdel(sKey,sField)
end
function PublicRedis.DelMtt(sUkey)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MTTUsers_%s",sUkey)
	tRedis:del(sKey)
end
function PublicRedis.GetMttFieldSplit(sUkey,sField)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("MTTUsers_%s",sUkey)
	local sValue= tRedis:hget(sKey,sField) or ""
	local s1,s2,s3 =string.match(sValue,"(.*):(.*):(.*)")
	return s1,s2,s3
end

function PublicRedis.Hmset(sKey, tData)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:hmset(sKey, tData)
end
function PublicRedis.Del(sKey)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:del(sKey)
end
function PublicRedis.Hgetall(sKey)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:hgetall(sKey)
end

function PublicRedis.Rpush(sKey,sValue)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:rpush(sKey,sValue)
end

function PublicRedis.Lrange(sKey,nSt,nEnd)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:lrange(sKey,nSt,nEnd)
end

function PublicRedis.Hget(sKey,sFied)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:hget(sKey,sFied)
end

function PublicRedis.Hdel(sKey,sFied)
	local tRedis =tBase.m_MyRedisData[2].redis
	return tRedis:hdel(sKey,sFied)
end

function PublicRedis.GetJackLot_Redis_Result(nGameId,nIssue)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("JacketResult_%d_%s",nGameId,nIssue)
	local sValue= tRedis:get(sKey) or "" 
    -- tBase.Log("GetJackLot_Redis_Result    nGameId: %d nIssue: %s [%s] ",nGameId,nIssue,sValue or "") 
	if not sValue or #sValue <= 1 then return end 
	local arrResult = cjson.decode(sValue)
	tRedis:expire(sKey,60*60)   -- 一小时过期
	return arrResult
end

function PublicRedis.SetRedis1(sKey, val, time)
	local redis =tBase.m_MyRedisData[1].redis
	redis:setex(sKey, time, val)
end

function PublicRedis.GetRedis1(sKey)
	local redis =tBase.m_MyRedisData[1].redis
	local val =redis:get(sKey) or ""
	return val
end

--
--这函数在PublicUserInfo里进行了赋值,为 PublicUserInfo.Get_User_Gold
PublicRedis.Get_User_Gold =nil

--设置redis 1
function PublicRedis.HsetRedis1(key, subKey, value)
	local tRedis = tBase.m_MyRedisData[1].redis
	local _ = tRedis:hset(key, subKey, value)
end

-- 获取redis 1
function PublicRedis.HgetRedis1(key, subKey)
	local tRedis = tBase.m_MyRedisData[1].redis
	local value = tRedis:hget(key, subKey)
	return value
end

--保险池当前额度获取
function PublicRedis.GetInsureSumPool()
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey = "APollInfo"
	local sSubKey = "InsurePoll"
	local nProfit =tRedis:hget(sKey, sSubKey)
	return tonumber(nProfit) or 0
	-- tRedis:hincrbyfloat(sKey, sSubKey, tData.nHandProfit)
end

-- 修改保险池金额
function PublicRedis.AtomicUpdateInsurePool(nChange, nAdd, minBalance)
    minBalance = minBalance or 0
    local tRedis = tBase.m_MyRedisData[2].redis
    local script = [[
        local key = KEYS[1]
        local insurePoolField = KEYS[2]
        local insureGetField = KEYS[3]
        local change = tonumber(ARGV[1])
        local add = tonumber(ARGV[2])
        local minBalance = tonumber(ARGV[3])
        
        -- 获取当前保险池余额
        local current = tonumber(redis.call('HGET', key, insurePoolField)) or 0
        -- 检查余额是否足够（仅在减少时检查）
        if change < 0 and current + change < minBalance then
            return {0, current, 0}  -- 第一个元素0表示失败,第二个是当前保险池余额,第三个是当前赔付金额
        end
        -- 执行保险池更新
        if change ~= 0 then
            redis.call('HINCRBYFLOAT', key, insurePoolField, change)
        end
        -- 执行赔付金额更新
        if add ~= 0 then
            redis.call('HINCRBYFLOAT', key, insureGetField, add)
        end
        -- 获取新值
        local newPoolValue = tonumber(redis.call('HGET', key, insurePoolField)) or 0
        local newCostValue = tonumber(redis.call('HGET', key, insureGetField)) or 0
        
        return {1, newPoolValue, newCostValue}  -- 第一个元素1表示成功,第二个是新保险池余额,第三个是赔付金额
    ]]

    local result = tRedis:eval(script, 3, "APollInfo", "InsurePoll", "InsureGet", nChange, nAdd or 0, minBalance)
    if result[1] == 1 then
        return true, result[2], result[3]  -- 返回成功标志、新保险池余额、赔付金额
    else
        return false, result[2], result[3]  -- 返回失败标志、当前保险池余额、当前赔付金额
    end
end

return PublicRedis
