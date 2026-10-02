--redis数据读取缓存类
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
local tProtoMgr   = require("ProtoManager")
local tBase 	  = require("base")         -- 基础功能接口
local cjson     = require("cjson")        -- json 
local tSrvInfo = require("ServerInfo")
local api    = require("publicApi")    -- 共用功能接口
local mlogger = require("logger")      -- 日志对象 
local tBase64 = require("BaseSink")    -- base 编码解码

RedisCahche = {
    nMinTime = 60*5, --读取redis的最小时间间隔
    nMaxTime = 60*10,--读取redis的最大时间间隔
    tCache = {}, --缓存数据
	tCacheHash = {}, --缓存数据，哈希结构
	isInit = false, --是否有初始化
	WebCallBack = nil, --后台通知更新的回调函数
}


local function PrintError(str,...)
	mlogger:error(string.format("ErrorMsg ==>"..str,...))
end


function RedisCahche.Start()
	RedisCahche.isInit = true
    local BackstagePro = tProtoMgr.Backstage_pb.Backstage_Proto()
    tBase.RegFunc(BackstagePro.Main_CMD, BackstagePro.WebRedisNotify_CMD, RedisCahche._OnWebRedisNotify)
	tBase.SetTimer(65510,1000*5,1,RedisCahche.CheckCache)
end

--后台通知更新(需要更新的key缓存删掉)
function RedisCahche._OnWebRedisNotify()
	tBase.Log("_OnWebRedisNotify 后台配置修改通知")
    local redis =tBase.m_MyRedisData[2].redis
    local sMainKey = "GSP_ConfigNotice"
    if redis:exists(sMainKey) then
        local arrList = redis:hkeys(sMainKey)
        for _,skey in pairs(arrList) do
            RedisCahche.tCache[skey] = nil
			RedisCahche.tCacheHash[skey] = nil
			tBase.Log("后台修改的配置 skey:%s",skey)
			--机器人数量的key特殊处理
			local sAndroidCfgKey = string.match(skey,"LiveAndroidConfig_GameId_%d+:GroupId_%d+:RoomId_%d+")
			if sAndroidCfgKey then
				RedisCahche.tCache[sAndroidCfgKey] = nil
			end
        end
		--如果有设置回调函数，调用回调函数
		if type(RedisCahche.WebCallBack)=="function" then
			RedisCahche.WebCallBack(arrList)
		end
    end
end

-- redis[2] 的 实例
function RedisCahche._Redis()
	return tBase.m_MyRedisData[2].redis 
end
--定时检查超时的缓存数据，并且删除
function RedisCahche.CheckCache()
	local nNowTime = os.time()
	for sKey,v in pairs(RedisCahche.tCache) do
		local nTime = v.nTime or 0
		local nSpaceTime = v.nSpaceTime or 0
		if nNowTime-nTime >= nSpaceTime then
			RedisCahche.tCache[sKey] = nil
		end
	end
	for sKey,tData in pairs(RedisCahche.tCacheHash) do
		local nCnt = 0
		for SubKey,v in pairs(tData) do
			local nTime = v.nTime or 0
			local nSpaceTime = v.nSpaceTime or 0
			if nNowTime-nTime >= nSpaceTime then
				RedisCahche.tCacheHash[sKey][SubKey]=nil
			else
				nCnt = nCnt + 1 
			end
		end
		tBase.Log("_CheckCache  skey:%s  nCnt: %d",sKey,nCnt)
	end


	tBase.SetTimer(60110,1000*60*5,1,RedisCahche.CheckCache)
end

--手动删除缓存数据
function RedisCahche.DelCacheData(skey)
	RedisCahche.tCache[skey] = nil
	RedisCahche.tCacheHash[skey] = nil
end

--手动删除缓存数据（哈希中的某一项）
function RedisCahche.DelCacheDataHash(skey,SubKey)
	if RedisCahche.tCacheHash[skey] then
		RedisCahche.tCacheHash[skey][SubKey]=nil
	end
end

--获取缓存
function RedisCahche.GetChache(sKey)
	if not RedisCahche.isInit then
		RedisCahche.Start()
	end
    if sKey and RedisCahche.tCache[sKey] then
		local arrRlt = RedisCahche.tCache[sKey].arrRlt
		local nTime = RedisCahche.tCache[sKey].nTime or 0
		local nSpaceTime = RedisCahche.tCache[sKey].nSpaceTime or 0
		if arrRlt and os.time()-nTime < nSpaceTime then
			-- tBase.Log("GetChache Use Chache,skey:%s",sKey)
			local arrNewRlt = {}
			for k,v in ipairs(arrRlt) do
				if type(v)=="table" then
					table.insert(arrNewRlt,api.Clone(v))
				else
					table.insert(arrNewRlt,v)
				end
			end
			return arrNewRlt
		else
			RedisCahche.tCache[sKey] = nil
		end
    end 
    return nil
end

--获取缓存(哈希结构)
function RedisCahche.GetChacheHash(sKey,SubKey)
	if not RedisCahche.isInit then
		RedisCahche.Start()
	end
	if sKey and RedisCahche.tCacheHash[sKey] then
		if SubKey and RedisCahche.tCacheHash[sKey][SubKey] then
			local arrRlt = RedisCahche.tCacheHash[sKey][SubKey].arrRlt
			local nTime = RedisCahche.tCacheHash[sKey][SubKey].nTime or 0
			local nSpaceTime = RedisCahche.tCacheHash[sKey][SubKey].nSpaceTime or 0
			if arrRlt and os.time()-nTime < nSpaceTime then
				-- tBase.Log("GetChacheHash Use Chache,skey:%s SubKey:%s",sKey,tostring(SubKey))
				local arrNewRlt = {}
				for k,v in ipairs(arrRlt) do
					if type(v)=="table" then
						table.insert(arrNewRlt,api.Clone(v))
					else
						table.insert(arrNewRlt,v)
					end
				end
				return arrNewRlt
			else
				RedisCahche.tCacheHash[sKey][SubKey] = nil
			end
		end
    end
    return nil
end

--保存非哈希结构的数据
function RedisCahche.SetChache(sKey,...)
	local arrRlt = {}
	for k,v in ipairs({...}) do
		if type(v)=="table" then
			table.insert(arrRlt,api.Clone(v))
		else
			table.insert(arrRlt,v)
		end
	end
    RedisCahche.tCache[sKey] = RedisCahche.tCache[sKey] or {}
    RedisCahche.tCache[sKey].arrRlt = arrRlt
    RedisCahche.tCache[sKey].nTime = os.time()
    RedisCahche.tCache[sKey].nSpaceTime = math.random(RedisCahche.nMinTime,RedisCahche.nMaxTime)
end

--保存哈希结构的数据
function RedisCahche.SetChacheHash(sKey,SubKey,...)
	local arrRlt = {}
	for k,v in ipairs({...}) do
		if type(v)=="table" then
			table.insert(arrRlt,api.Clone(v))
		else
			table.insert(arrRlt,v)
		end
	end
	RedisCahche.tCacheHash[sKey] = RedisCahche.tCacheHash[sKey] or {}
	RedisCahche.tCacheHash[sKey][SubKey] = RedisCahche.tCacheHash[sKey][SubKey] or {}
    RedisCahche.tCacheHash[sKey][SubKey].arrRlt = arrRlt
    RedisCahche.tCacheHash[sKey][SubKey].nTime = os.time()
    RedisCahche.tCacheHash[sKey][SubKey].nSpaceTime = math.random(RedisCahche.nMinTime,RedisCahche.nMaxTime)
end

--修改缓存的过期时间
--@params nSpaceTime 新的时间（秒）
--@params sKey 一级key
--@params SubKey 二级key（改的试哈希结构的缓存才需要传）
--@retrun true:成功 false:失败
function RedisCahche.ChangeChacheTime(nSpaceTime,sKey,SubKey)
	nSpaceTime = nSpaceTime or math.random(RedisCahche.nMinTime,RedisCahche.nMaxTime)
	if sKey then
		if SubKey then --修改哈希结构缓存的过期时间
			if RedisCahche.tCacheHash[sKey] and RedisCahche.tCacheHash[sKey][SubKey] then
				RedisCahche.tCacheHash[sKey][SubKey].nSpaceTime = nSpaceTime
				return true
			end
		else --修改非哈希结构缓存的过期时间
			if RedisCahche.tCache[sKey] then
				RedisCahche.tCache[sKey].nSpaceTime = nSpaceTime
				return true
			end
		end
	end
	return false
end

--设置后台通知更新的回调函数
--@param CallBack 回调函数
function RedisCahche.SetRedisNotifyCallBack(CallBack)
	RedisCahche.WebCallBack = CallBack
end

-- 获取鱼虾蟹生成牌参数
function RedisCahche._YuXiaXie_CreateCardParameter(nGroupId)
    local sKey = "YuXiaXie_CreateCardParameter_"..math.floor(nGroupId)

    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
    local MyRedis2 = tBase.m_MyRedisData[2].redis 
	local nCreateCardParameter =  MyRedis2:get(sKey)
	if nCreateCardParameter then 
		-- tBase.Log("_YuXiaXie_CreateCardParameter  nCreateCardParameter_"..nCreateCardParameter)
		nCreateCardParameter = tonumber(nCreateCardParameter)
	else
		-- tBase.Log("_YuXiaXie_CreateCardParameter  nCreateCardParameter  is nil   sKey_"..sKey)
		nCreateCardParameter = nil 
	end

    --保存到缓存
    RedisCahche.SetChache(sKey,nCreateCardParameter)

	return nCreateCardParameter	
end

-- 获取骰宝生成牌参数
function RedisCahche._TouBao_CreateCardParameter(nGroupId)
    local sKey = "TouBao_CreateCardParameter_"..math.floor(nGroupId)

    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

    local MyRedis2 = tBase.m_MyRedisData[2].redis 
	local nCreateCardParameter =  MyRedis2:get(sKey)
	if nCreateCardParameter then 
		-- tBase.Log("__TouBao_CreateCardParameter  nCreateCardParameter_"..nCreateCardParameter)
		nCreateCardParameter = tonumber(nCreateCardParameter)
	else
		tBase.Log("__TouBao_CreateCardParameter  nCreateCardParameter  is nil   sKey_"..sKey)
		nCreateCardParameter = nil 
	end 

    --保存到缓存
    RedisCahche.SetChache(sKey,nCreateCardParameter)

	return nCreateCardParameter	
end

function RedisCahche._OnGeHelptUI(nGroupId)
	local Rds = tBase.m_MyRedisData[2].redis
	local sKey =string.format("HelpUI:Group_%d",nGroupId)
	local sDefaultKey = "HelpUI:Default"

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end


	local sUi = Rds:get(sKey)
	if not sUi then
		sUi = Rds:get(sDefaultKey)
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,sUi)

	return sUi
end

--功能开关配置 (推荐、跟投、上庄,统一结果,Vip 功能开关)
--设置功能开关(Game122,Group20); 推荐、跟投、上庄、统一结果; 1:开 0:关
--返回示例:{isRecommendOn=true,isFollowBetOn=true,isUserBankerOn=false,isUnifyResult=false}
function RedisCahche.Get_SwitchConfig(nGameId,nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 		  =string.format("LiveSwitchConfig:Game%d:Group%d",nGameId,nGroupId)
	local sDefaultKey =string.format("LiveSwitchConfig:Game%d:Default",nGameId)

    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local arrRlt 		= My_2:hmget(sKey,"isRecommendOn","isFollowBetOn","isUserBankerOn","isUnifyResult","isVipOn","BetTime","nAutoBet")
	local arrDefaultRlt =My_2:hmget(sDefaultKey,"isRecommendOn","isFollowBetOn","isUserBankerOn","isUnifyResult","isVipOn")
	
	local tSwitchConfig = {}
	tSwitchConfig.isRecommendOn=(tonumber(arrRlt[1] or arrDefaultRlt[1])  ==1)
	tSwitchConfig.isFollowBetOn=(tonumber(arrRlt[2] or arrDefaultRlt[2])  ==1)
	tSwitchConfig.isUserBankerOn=(tonumber(arrRlt[3] or arrDefaultRlt[3]) ==1)
	if nGameId == 121 then   -- 统一牌桌结果: 只是直播鱼虾蟹 
		tSwitchConfig.isUnifyResult=(tonumber(arrRlt[4] or arrDefaultRlt[3]) ==1) 
	end  
	if nGameId==121 or nGameId==122 or nGameId==153 then
		tSwitchConfig.isVipOn=(tonumber(arrRlt[5] or arrDefaultRlt[5]) ==1)
	end
	if arrRlt[6] then 
		tSwitchConfig.nBetTime = tonumber(arrRlt[6] or 25)   -- 下注时间
		if tSwitchConfig.nBetTime <= 10 then tSwitchConfig.nBetTime = 25 end 
	else
		tSwitchConfig.nBetTime = 25  -- 默认 
	end 

	-- 自动下注开关:  0全关、1: 全开、2: 区块链开(幸运扑克关)、3幸运扑克开(区块链关)
	tSwitchConfig.nAutoBet=(tonumber(arrRlt[7] or 0)) 

    --保存到缓存
    RedisCahche.SetChache(sKey,tSwitchConfig)

	return tSwitchConfig
end

--集合游戏 可下注筹码
--返回示例:{5,10,50,100,1000,2000,5000,10000,20000}
--注意:如果返回nil,表示没有任何设置,请自行处理该情况
function RedisCahche.GetRoomCanBetChip(nGameId,nGroupId,nSession)
	local My_2 = tBase.m_MyRedisData[2].redis  
	local sKey 		  =string.format("LiveChipsConfig:Game%d:Group%d:Room%d",nGameId,nGroupId,nSession)
	local sDefaultKey =string.format("LiveChipsConfig:Game%d:Default:Room%d",nGameId,nSession)
    
    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
    
	local arrChips =My_2:smembers(sKey)
	if arrChips==nil or #arrChips==0 then
		arrChips =My_2:smembers(sDefaultKey) or {}
	end
	if #arrChips ==0 then
		--保存到缓存
		RedisCahche.SetChache(sKey,nil)
		return nil
	end
	tBase.Log("_GetRoomCanBetChip sKey: %s arrChipsForBet: %s ",sKey,cjson.encode(arrChipsForBet))
	--确保返回的是>=0的递增整数数组
	local arrChipsForBet ={}
	for _,sChip in ipairs(arrChips) do
		local nChip =tonumber(sChip) or 0
		nChip =math.floor(nChip)
		if nChip>=0 then
			table.insert(arrChipsForBet,nChip)
		end
	end
	table.sort(arrChipsForBet)

    --保存到缓存
    RedisCahche.SetChache(sKey,arrChipsForBet)

	return arrChipsForBet
end

--功能开关配置 (直播聊天开关 功能开关)
--设置功能开关(Group20); 聊天; 1:开 0:关
--返回示例:{isChatOn=true}
function RedisCahche.Get_SwitchChatConfig(nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 		  =string.format("LiveChatConfig_Group%d",nGroupId)
    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local IsChatOn = My_2:get(sKey)
	if not IsChatOn then
        IsChatOn = true
	else
		IsChatOn = (tonumber(IsChatOn)  ==1)
    end
	
    --保存到缓存
    RedisCahche.SetChache(sKey,IsChatOn)

	return IsChatOn
end

function RedisCahche._OnGetSwitchCfg(nGameId,nGroupId)
	local Rds = tBase.m_MyRedisData[2].redis
	local sKey =string.format("ControlSwitch:Game_%d:Group_%d",nGameId,nGroupId)
	local sDefaultKey =string.format("ControlSwitch:Game_%d:Default",nGameId)

    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local IsOn = Rds:get(sKey)
	if not IsOn then
		IsOn = Rds:get(sDefaultKey)
	end

    if not IsOn then
        IsOn = "false"
    end

    --保存到缓存
    RedisCahche.SetChache(sKey,IsOn)

    return IsOn
end

function RedisCahche._getGameSkinVal(sSelectSkin,nGroupId) 
	local Rds = tBase.m_MyRedisData[2].redis
	local sKey =string.format("Game_Skin%d",nGroupId)

    --读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        local arrskin = tCache[1]
        return arrskin[sSelectSkin] or ""
    end

	local arrskin = Rds:hgetall(sKey)

	arrskin = arrskin or {}

    --保存到缓存
    RedisCahche.SetChache(sKey,arrskin)

	return arrskin[sSelectSkin] or ""
end

--[[
local t =dosplit("min=33; max=56 ;odds=100", ";")
print(t.min)	--33
print(t.max)	--56
print(t.odds)	--100
]]
function dosplit(str,reps)
	if str==nil then return nil end
	local r={}
	local function repl(s)
		local key,val =string.match(s,"(%w+)=(%w+)")
		r[key] =tonumber(val)
	end
	string.gsub(str,"[^"..reps.."]+",repl)
	return r
end


--获取限红数据
--返回示例: {[Area1]={min=1,max=100},[Area2]={min=1,max=2000}}
function RedisCahche.Get_UserAreaLimit(nGameId,nGroupId,nRoomId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 	=string.format("UserAreaLimit_GameId_%d:GroupId_%d:RoomId_%d",nGameId,nGroupId,nRoomId)
	local sDefaultKey =string.format("UserAreaLimit_GameId_%d:GroupId_Default:RoomId_%d",nGameId,nRoomId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local BetLimit = {}
	local tR = My_2:hgetall(sKey) or My_2:hgetall(sDefaultKey) or {}
	--数据组合
	for sBetArea,v in pairs(tR) do
		local nBetArea =tonumber(sBetArea)
		if nBetArea then
			local t =dosplit(v,";")
			t.VipRate =t.odds
			BetLimit[nBetArea] =t
		else
			BetLimit[sBetArea]=v
		end
	end
	--保存到缓存
    RedisCahche.SetChache(sKey,BetLimit)
	return BetLimit
end

--获取游戏ID数组(nType:1:允许转入转出的游戏  2:只允许转入的游戏)
function RedisCahche.GetArrGameId(nType)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey = ""
	if nType == 1 then
		sKey  =string.format("ArrOutInGameId")
	elseif nType == 2 then
		sKey  =string.format("ArrInGameId")
	else
		tBase.Log("_GetArrGameId type is error:nType_%d",nType)
		return
	end

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local ArrGameId =My_2:smembers(sKey)
	if #ArrGameId ==0 then
		if nType == 1 then 
			local arrGame = {107,212,150,178,125,126,127} --合集游戏(合集百家乐,合集鱼虾蟹,合集色碟,俱乐部抢庄牛、红黑彩) 合集游戏不允许转出
			-- local arrGame = {107,178,125,126,127} --合集游戏(合集百家乐,俱乐部抢庄牛、红黑彩) 合集游戏不允许转出
			for k,v in pairs(SetingConfig.tZhiBoGameId) do --所有直播游戏都可以转入转出
				table.insert(arrGame,v) 
			end
			ArrGameId = arrGame --默认所有可以转入转出的游戏
		elseif nType == 2 then
			ArrGameId = {106,114,115}  --默认所有只可以转入的游戏(目前21点3个游戏只可以转入)			
		else
			ArrGameId = nil
		end
		
		--保存到缓存
		RedisCahche.SetChache(sKey,ArrGameId)
		tBase.Log("_GetArrGameId use default config ArrGameId_%s",cjson.encode(ArrGameId))
		return ArrGameId
	end
	--确保返回的是整数数组
	local arrGameID ={}
	for _,sGameId in ipairs(ArrGameId) do
		local nGameId =tonumber(sGameId) or 0
		nGameId =math.floor(nGameId)
		if nGameId>0 then
			table.insert(arrGameID,nGameId)
		end
	end

	--保存到缓存
    RedisCahche.SetChache(sKey,arrGameID)
	tBase.Log("_GetArrGameId  arrGameID_%s",cjson.encode(arrGameID))
	return arrGameID
end

--直播游戏 可下注筹码
--返回示例:{5,10,50,100,1000,2000,5000,10000,20000}
--注意:如果返回nil,表示没有任何设置,请自行处理该情况
function RedisCahche.Get_LiveChips(nGameId,nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 		  =string.format("LiveChipsConfig:Game%d:Group%d",nGameId,nGroupId)
	local sDefaultKey =string.format("LiveChipsConfig:Game%d:Default",nGameId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local arrChips =My_2:smembers(sKey)
	if arrChips==nil or #arrChips==0 then
		arrChips =My_2:smembers(sDefaultKey) or {}
	end
	if #arrChips ==0 then
		--保存到缓存
		RedisCahche.SetChache(sKey,nil)
		return nil
	end
	--确保返回的是>=0的递增整数数组
	local arrChipsForBet ={}
	for _,sChip in ipairs(arrChips) do
		local nChip =tonumber(sChip) or 0
		nChip =math.floor(nChip)
		if nChip>=0 then
			table.insert(arrChipsForBet,nChip)
		end
	end
	table.sort(arrChipsForBet)

	--保存到缓存
    RedisCahche.SetChache(sKey,arrChipsForBet)

	return arrChipsForBet
end

--获得游戏房间的最低上庄金额
function RedisCahche.Get_UserBankerLimit(nGroupId,nGameId,RoomId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 		= string.format("UserBanker:Group%d:Game%d",nGroupId,nGameId)
	local sFile 	= string.format("RoomId%d",RoomId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sFile)
    if tCache then
        return table.unpack(tCache)
    end

	local nValues 	=My_2:hget(sKey,sFile) 
	local sDefaultKey = string.format("UserBanker:Default:Game%d",nGameId)
	local nDefaultValues =My_2:hget(sDefaultKey,sFile)
	local nName = ""
	local nSVal = 0
	if nValues and tonumber(nValues)>0 then  
		nName = "config"
		nSVal = tonumber(nValues)
	elseif nDefaultValues and tonumber(nDefaultValues)>0 then
		nName = "Default"
		nSVal = tonumber(nDefaultValues)
	else
		nName = "Nohave" 
	end

	--保存到缓存
    RedisCahche.SetChacheHash(sKey,sFile,nSVal)

	tBase.Log("获得游戏房间_"..sFile.." 最低上庄 配置_"..nName.." 金额值_"..nSVal.." sKey_ "..sKey.." sDefaultKey_ "..sDefaultKey)
	return nSVal
end

--返回当前应该使用的机器人数量
--LiveAndroidConfig_GameId_121:GroupId_1:RoomId_1:01,02,03,04,05,06,07,       需要保持两位
function RedisCahche._LiveAndroidCount(nGroupId,nGameId,nRoomId)
	local sHour = os.date("%H")
	local sKey =string.format("LiveAndroidConfig_GameId_%d:GroupId_%d:RoomId_%d*[:,]%s[,]*",nGameId,nGroupId,nRoomId,sHour)

	--读取缓存数据
	local sSaveKey = string.format("LiveAndroidConfig_GameId_%d:GroupId_%d:RoomId_%d",nGameId,nGroupId,nRoomId)
    local tCache = RedisCahche.GetChache(sSaveKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tRedis = tBase.m_MyRedisData[2].redis 
	local arrKeys = tRedis:keys(sKey)
	local nCnt = 0
	if arrKeys and #arrKeys>0 then
		local sConfigKey =arrKeys[1]
		local tConfig =  tRedis:hgetall(sConfigKey)
		local nMinCount =tonumber(tConfig.nMinCount) or 0
		local nMaxCount =tonumber(tConfig.nMaxCount) or 0
		-- local nRandomNum =math.random(5,30)
		-- if math.random(1,2) ==1 then
		-- 	nRandomNum =-nRandomNum
		-- end
		-- nMinCount =math.floor(nMinCount +(nRandomNum/100)*nMinCount)
		-- nMaxCount =math.floor(nMaxCount +(nRandomNum/100)*nMaxCount)

		if nMinCount >nMaxCount or nMinCount<0 or nMaxCount<0 then
			tBase.Log("_LiveAndroidCount Config Error")
		else
			nCnt = math.random(nMinCount,nMaxCount)
		end
	end

	--保存到缓存
    RedisCahche.SetChache(sSaveKey,nCnt)

	return nCnt
end

-- 直播底分
function RedisCahche._LiveConfigAnte(nGroupId,nGameId,nRoomId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 	=string.format("LiveRoomConfig_GameId_%d:GroupId_%d:RoomId_%d",nGameId,nGroupId,nRoomId)
	local sSubKey = "Ante"

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sAnte =My_2:hget(sKey,sSubKey)
	local nAnte=(tonumber(sAnte) or 1)

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nAnte)

	return nAnte
end

-- 获取 区块链 域名
function RedisCahche._GetBlockchainDomainName()
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 	=  string.format("LiveBlockchainDomainName")

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sDomainName =My_2:get(sKey)
	sDomainName = sDomainName or nil

	--保存到缓存
    RedisCahche.SetChache(sKey,sDomainName)
	
	return sDomainName
end

-- 获取 MySource 域名
function RedisCahche._GetMySourceDomainName()
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 	=  string.format("BlockchainUrl")
	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sDomainName =My_2:hget("IMAppWebKey",sKey)
	sDomainName = sDomainName or nil 
    RedisCahche.SetChache(sKey,sDomainName)
	return sDomainName
end

-- 获取 彩票 域名
function RedisCahche._GetJackLotDomainName(sKey)
	local My_2 = tBase.m_MyRedisData[2].redis  
	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sDomainName =My_2:hget("IMAppWebKey",sKey)
	sDomainName = sDomainName or nil 
    RedisCahche.SetChache(sKey,sDomainName)
	return sDomainName
end

-- 获取充值提现域名
function RedisCahche._GetRechargeWithdrawalDomainName()
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 	=  string.format("sManualTransferUrl")
	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sDomainName =My_2:hget("IMAppWebKey",sKey)
	sDomainName = sDomainName or nil 
    RedisCahche.SetChache(sKey,sDomainName)
	return sDomainName
end

-- 获取 俱乐部充值 网页地址
function RedisCahche._GetPayUrl(sKey)
	local My_2 = tBase.m_MyRedisData[2].redis  
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sDomainName =My_2:hget("IMAppWebKey",sKey)
	sDomainName = sDomainName or nil 
    RedisCahche.SetChache(sKey,sDomainName)	
	return sDomainName
end


--机器人 信息(头像路径，头像最小范围，头像最大范围，最小局数，最大局数，休息时间，生成机器人数)
function RedisCahche._GetAndroidBasicConfig(nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey 	=string.format("getAndroidBasicConfig_%d",math.floor(nGroupId))

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tConfig = My_2:hgetall(sKey)
	tBase.LogT("getAndroidBasicConfig_ Config:",tConfig)
	if tConfig==nil or #tConfig==0 then
		tConfig = nil
	end

	--保存到缓存
    RedisCahche.SetChache(sKey,tConfig)

	return tConfig
end

--  机器人数量    动态数量 
function RedisCahche._GetGameAndroidCount(nGroupId,nGameId,nRoomId)
    local sKey =string.format("GameAndroidCount_GroupId_%d:GameId_%d:RoomId_%d",nGroupId,nGameId,nRoomId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

    local tRedis = tBase.m_MyRedisData[1].redis 
    local nAndroidCnt = tRedis:get(sKey) or 0 

	--保存到缓存
    RedisCahche.SetChache(sKey,tonumber(nAndroidCnt))

    return tonumber(nAndroidCnt) 
end

--  获取 游戏中 玩家人数  
function RedisCahche._GetGameCenterUserCount(nGroupId,nGameId,nRoomId)
	assert(nGroupId~= nil," nGroupId is nil ")
	assert(nGameId~= nil," nGameId is nil ")
	assert(nRoomId~= nil," nRoomId is nil ")
    local sKey =string.format("GameCenterUserCount_GroupId_%d:GameId_%d:RoomId_%d",nGroupId,nGameId,nRoomId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

    local tRedis = tBase.m_MyRedisData[1].redis 
    local nUserCount = tRedis:get(sKey) or 0 

	--保存到缓存
    RedisCahche.SetChache(sKey,tonumber(nUserCount))

    return tonumber(nUserCount) 
end

-- 庄闲下注是否互斥, true:是 false:否
-- nGroupId:分组id
function RedisCahche.IsBetExclusive(nGroupId,nGameId)
	local tRedisOfPersistent=tBase.m_MyRedisData[2].redis
	local sKey =string.format("BetExclusiveConfig_Group%d_Game%d",nGroupId,(nGameId or -1))

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sValue =tRedisOfPersistent:get(sKey)
	tBase.Log("IsBetExclusive sKey:%s sValue:%s",sKey,(sValue or "nil"))

	--保存到缓存
    RedisCahche.SetChache(sKey,(tonumber(sValue) ==1))

	return (tonumber(sValue) ==1)
end

-- 获取直播 下播解绑时间（秒）
function RedisCahche.GetLiveTheSowingTime(nGroupId)
    local sKey =string.format("LiveTheSowingTime_GroupId_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

    local tRedis = tBase.m_MyRedisData[2].redis 
    local nTheSowingTime = tRedis:get(sKey)

	local nTime = tonumber(nTheSowingTime) or (10*60)

	--保存到缓存
    RedisCahche.SetChache(sKey,nTime)

	return nTime	
end

-- 获取飞行棋 游戏配置 : nCfgType:  1 赏金配置  2抽水配置 3: 机器人策略开关 4: 策略2, 5: 多人模式奖池分配配置
function RedisCahche._GetPilotGameConfig(nGroupId,nCfgType)
	nGroupId = math.floor(nGroupId)
	local sKey = string.format("PilotGameConfig_%s",nGroupId)
	local tRedis = tBase.m_MyRedisData[2].redis
	if nCfgType == 1 then -- 赏金配置
		local sSubKey = "nMoneryRewardPlaying"
		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
		if tCache then
			return table.unpack(tCache)
		end
		
		local nMoneryRewardPlaying = tRedis:hget(sKey,sSubKey)
		nMoneryRewardPlaying = tonumber(nMoneryRewardPlaying) or 1

		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,nMoneryRewardPlaying)

		return nMoneryRewardPlaying 
	elseif nCfgType == 2 then   -- 抽水配置
		local sSubKey = "nDrawWater"
		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
		if tCache then
			return table.unpack(tCache)
		end

		local nDrawWater = Base.m_MyRedisData[2].redis:hget(sKey,sSubKey)
		nDrawWater = tonumber(nDrawWater) or 0.98

		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,nDrawWater)

		return nDrawWater
	elseif nCfgType == 3 or nCfgType == 4 then   -- 机器人策略开关 
		local sTacticsNumber = "sTacticsNumber"   -- 策略1
		if nCfgType == 4 then 
			sTacticsNumber="sTacticsNumber2"      --策略2
		end

		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,sTacticsNumber)
		if tCache then
			return table.unpack(tCache)
		end

		local t = {}
		t.nSwitch =0
		local tTacticsSwitchCfg = Base.m_MyRedisData[2].redis:hget(sKey,sTacticsNumber)
		if not tTacticsSwitchCfg then 
			--保存到缓存
			RedisCahche.SetChacheHash(sKey,sTacticsNumber,t)
			return t
		end 
		local isSuccee,Rlt =pcall(cjson.decode,tTacticsSwitchCfg)
		if not isSuccee then 
			tBase.Log("_GetPilotGameConfig ErrorMsg sKey_%s Rlt_%s ",sKey,Rlt)
			if type(Rlt) == "string" then 
                mlogger:error(Rlt)
            end
			--保存到缓存
			RedisCahche.SetChacheHash(sKey,sTacticsNumber,t)
			return t
		end 
		local tTactics = Rlt 
		t.nCfgType = nCfgType
		t.sTacticsNumber = sTacticsNumber
		t.nSwitch =  tonumber(tTactics.nTacticsSwitch) or 0
		if t.nSwitch == 1 then  
	    	t.nKillCnt = tonumber(tTactics.nKillCnt) or 1
	    	t.nEnterTerminusCnt = tonumber(tTactics.nEnterTerminusCnt) or 1 
	    	t.nRock6Cnt = tonumber(tTactics.nRock6Cnt) or 1
	    	t.nEnterSafeCnt = tonumber(tTactics.nEnterSafeCnt) or 2
		    if not tTactics.nKillCnt or t.nKillCnt < 0 or t.nKillCnt > 5 then 
		    	t.nKillCnt = 1
		    end 
		    if not t.nEnterTerminusCnt or t.nEnterTerminusCnt < 0 or t.nEnterTerminusCnt > 5 then 
		    	t.nEnterTerminusCnt = 1
		    end 
		    if not tTactics.nRock6Cnt or t.nRock6Cnt < 0 or t.nRock6Cnt > 5 then 
		    	t.nRock6Cnt = 1
		    end 
		    if not tTactics.nEnterSafeCnt or t.nEnterSafeCnt < 0 or t.nEnterSafeCnt > 5 then 
		    	t.nEnterSafeCnt = 2
		    end 		    		    
		end
		
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sTacticsNumber,t)

		return t

	elseif nCfgType == 5 then -- 多人模式奖池分配配置 
		local sSubKey = "nPeoplePatternCfg"
		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
		if tCache then
			return table.unpack(tCache)
		end

		local sCfg = tRedis:hget(sKey,sSubKey)
		local arrPeoplePatternCfg = {}
		if not sCfg then 
			table.insert(arrPeoplePatternCfg,{1,0})
			table.insert(arrPeoplePatternCfg,{0.8,0.2,0})
			table.insert(arrPeoplePatternCfg,{0.6,0.3,0.1,0}) 
		else
	 		local tCfg = cjson.decode(sCfg)
	 		for _,v in pairs(tCfg) do
	 			local t = {}
	 			for _,v1 in pairs(v) do
	 				table.insert(t,tonumber(v1))
	 			end
	 			table.insert(arrPeoplePatternCfg,t)
	 		end
		end
		
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,arrPeoplePatternCfg)

		return arrPeoplePatternCfg
	end 
	return 
end

--风控余额
function RedisCahche._GetBalance(nUserId,nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("Group%d_Balance_B4BB66A9E84D4E16874EED6439F08D01",nGroupId)

	-- key userId    value 风控余额
	local sSubKey = math.floor(nUserId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sBalance =redis:hget(sKey,sSubKey)
	local nBalance=(tonumber(sBalance) or -1)
	 
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nBalance) 
	return nBalance
end

--机器人配置
function RedisCahche._GetRobConfig(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("DB_RobotConfig")

	local sSubKey = math.floor(nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sRConfig =redis:hget(sKey,sSubKey)
	local nRConfig=(tonumber(sRConfig) or 0)
	 
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nRConfig) 
	return nRConfig
end

--获取邀请码相关内容显示开关
function RedisCahche._GetCodeSwitch(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("CodeSwitch_Group%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sFlag =redis:get(sKey)
	local nFlag=(tonumber(sFlag) or -1)

	--保存到缓存
	RedisCahche.SetChache(sKey,nFlag)
	return nFlag
end

--获取转账方式
function  RedisCahche._GetTransferWay(nGroupId,sSubKey)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("GSP_TransferChannel_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sWay =redis:hget(sKey,sSubKey)
	local nWay= sWay or ""

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nWay)
	return nWay
end	

--获取全部转账信息
function RedisCahche._GetTransferInfos()
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("GSP_TransferArea")
	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end
	local tData =  redis:hgetall(sKey)
	
	RedisCahche.SetChache(sKey,tData)  	--保存到缓存	
	return tData
end

--获取一条转账信息
function RedisCahche._GetOneTransferInfo(sSubKey)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("GSP_TransferArea")
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sWay =redis:hget(sKey,sSubKey)
	local nWay= sWay or ""

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nWay)
	return nWay
end

--获取前端用文件编码
function RedisCahche._GetFileConfig()
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("GSP_FileConfig")

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sFile = redis:get(sKey) or "1"
	-- local nFile = tostring(sFile) or ""
	local nFile = tBase64.encode(sFile)
	
	--保存到缓存
	RedisCahche.SetChache(sKey,nFile)
	return nFile
end

--获取汇率
function RedisCahche._GetPayExchangeRate(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("GSP_PayExchangeRate")

	local sSubKey =string.format("Group_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end
	
	local sRate =redis:hget(sKey,sSubKey)
	local nRate=(tonumber(sRate) or 1)
	
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nRate)
	return nRate
end

--获取活动开关
function RedisCahche._GetActiSwitch(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("ClubActiSwitch_%d",nGroupId)
	--读取缓存数据
	-- local tCache = RedisCahche.GetChache(sKey)
	-- if tCache then
	-- 	return table.unpack(tCache)
	-- end
	local tData =  redis:hgetall(sKey)
	
	RedisCahche.SetChache(sKey,tData)  	--保存到缓存	
	RedisCahche.ChangeChacheTime(1*60*60,sKey)  --修改过期时间为一天

	return tData
end

--获取充值提现开关
function RedisCahche._GetUserTransferSwitch(nUserId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserTransferSwitch")
	local sSubKey =string.format(nUserId)

	local sSwitch =redis:hget(sKey,sSubKey)
	local nSwitch=(tonumber(sSwitch) or 0)
	RedisCahche.SetChacheHash(sKey,sSubKey,nSwitch)
	return nSwitch
end

--修改充值提现开关 --1为关 0为开
function RedisCahche._UpdateUserTransferSwitch(nUserId,nSwitch)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserTransferSwitch")
    redis:hset(sKey,math.floor(nUserId),nSwitch)
	RedisCahche.SetChacheHash(sKey,nUserId,nSwitch)
end

--获取“手动”充值提现开关 1为关 0为开
function RedisCahche._GetOnliTransSwitch(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("ClubOnlineTransferSwitch_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sFlag =redis:get(sKey)
	local nFlag=(tonumber(sFlag) or -1)

	--保存到缓存
	RedisCahche.SetChache(sKey,nFlag)
	return nFlag
end

--获取分享活动开关
function RedisCahche._GetUserShareActiSwitch(nUserId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserShareActiSwitch")
	local sSubKey = math.floor(nUserId)
	local sSwitch = redis:hget(sKey,math.floor(nUserId))
	tBase.Log("sSwitch%s,userId_%d",sSwitch,nUserId)
	local nSwitch=(tonumber(sSwitch) or 0)
	RedisCahche.SetChacheHash(sKey,sSubKey,nSwitch)
	return nSwitch
end

--修改分享活动开关 --1为关 0为开
function RedisCahche._UpdateUserShareActiSwitch(nUserId,nSwitch)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("UserShareActiSwitch")
    redis:hset(sKey,math.floor(nUserId),nSwitch)
	RedisCahche.SetChacheHash(sKey,nUserId,nSwitch)
end

--获取最小充值金额
function RedisCahche._GetMinRecharge(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("ClubMinRecharge_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sFlag =redis:get(sKey)
	local nFlag=(tonumber(sFlag) or -1)

	--保存到缓存
	RedisCahche.SetChache(sKey,nFlag)
	return nFlag
end

--通用keyvalue配置
function RedisCahche._GetKeyValueConfig(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("ClubGetValue")

	local sSubKey =string.format("Group_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end
	
	local sValue =redis:hget(sKey,sSubKey)
	local nValue=(sValue or "")
	
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nValue)
	return nValue
end

--key作为参数拿value(number)
function RedisCahche._GetNumValueByKey(sKey)
	local redis = tBase.m_MyRedisData[2].redis

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sValue = redis:get(sKey)
	local nValue = (tonumber(sValue) or -1)

	--保存到缓存
	RedisCahche.SetChache(sKey,nValue)
	return nValue
end

--key作为参数拿value(string)
function RedisCahche._GetStringValueByKey(sKey)
	local redis = tBase.m_MyRedisData[2].redis

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sValue = redis:get(sKey)
	local nValue = (sValue or "")

	--保存到缓存
	RedisCahche.SetChache(sKey,nValue)
	return nValue
end



--获取飞行棋底分配置 五个底分和最大最小底分
function RedisCahche.Get_PilotGameBaseScoreConfig(nGameId,nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis
	local sKey =string.format("PilotGameConfig_%d",nGroupId)

	local sSubKey = "Score"
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local arrRlt =My_2:hmget(sKey,"Score1","Score2","Score3","Score4","Score5","Score6","MinScore","MaxScore")

	local num = 0
	for k,v in pairs(arrRlt) do
	   if v and tonumber(v) > 0 then
		 num = num + 1
	   end
    end

	if num >= 8 then
		local Score1=(tonumber(arrRlt[1]))
		local Score2=(tonumber(arrRlt[2]))
		local Score3=(tonumber(arrRlt[3]))
		local Score4=(tonumber(arrRlt[4]))
		local Score5=(tonumber(arrRlt[5]))
		local Score6=(tonumber(arrRlt[6]))
		local MinScore=(tonumber(arrRlt[7]))
		local MaxScore=(tonumber(arrRlt[8]))
		tBase.Log("nGroupId：%d 后台底分配置列表： %d %d %d %d %d %d MinScore:%d  MaxScore:%d",nGroupId,Score1,Score2,Score3,Score4,Score5,Score6,MinScore,MaxScore)
		
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,{Score1,Score2,Score3,Score4,Score5,Score6,MinScore,MaxScore})

		return {Score1,Score2,Score3,Score4,Score5,Score6,MinScore,MaxScore}
	else
		tBase.Log("未获取到后台底分配置列表 将使用默认配置")
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,nil)

		return nil
	end
end

--飞行棋竞猜游戏 飞行员竞猜额度配置筹码
--返回示例:{100,250,500,1000，2000}
--注意:如果返回nil,表示没有任何设置,请自行处理该情况
--nType: 1 游戏额度筹码配置  2 下注限制筹码配置
function RedisCahche.Get_PilotGuessAmountChips(nGameId,nGroupId,nType)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey
	local sDefaultKey 
	if nType == 1 then 
		sKey 		  =string.format("GuessAmountChipsConfig:Game%d:Group%d",nGameId,nGroupId)
	 	sDefaultKey =string.format("GuessAmountChipsConfig:Game%d:Default",nGameId)
	else
		sKey 		  =string.format("GuessBetChipsLimitConfig:Game%d:Group%d",nGameId,nGroupId)
	 	sDefaultKey =string.format("GuessBetChipsLimitConfig:Game%d:Default",nGameId)
	end

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	 
	local arrChips =My_2:smembers(sKey)
	if arrChips==nil or #arrChips==0 then
		arrChips =My_2:smembers(sDefaultKey) or {}
	end
	if #arrChips ==0 then
		--保存到缓存
		RedisCahche.SetChache(sKey,nil)
		return nil
	end
	--确保返回的是>=0的递增整数数组
	local arrChipsForBet ={}
	for _,sChip in ipairs(arrChips) do
		local nChip =tonumber(sChip) or 0
		nChip =math.floor(nChip)
		if nChip>=0 then
			table.insert(arrChipsForBet,nChip)
		end
	end
	table.sort(arrChipsForBet)

	--保存到缓存
	RedisCahche.SetChache(sKey,arrChipsForBet)

	return arrChipsForBet
end

-- 获取砍树 游戏配置 : nCfgType:  1 基本配置(入场费,最大秒数,每节树干分数) 2 机器人策略配置
function RedisCahche._GetFellTreeGameConfig(nGroupId,nRoomId,nCfgType)
	nGroupId = nGroupId or 0
	nRoomId = nRoomId or 2
	local tRedis = tBase.m_MyRedisData[2].redis
	if nCfgType == 1 then -- 基本配置(入场费,最大秒数,每节树干分数)
		local sKey = string.format("LiveLumbering_%d_157_%d",nGroupId,nRoomId)
		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,nCfgType)
		if tCache then
			return table.unpack(tCache)
		end
		
		local List = tRedis:hgetall(sKey) or {}

		local tData = {}
		tData.nEntranceFee = tonumber(List.AdmissionFee)
		tData.nOperationTime = tonumber(List.OperationTime)
		tData.nScore = tonumber(List.Score)
		tData.nIncrementTime = tonumber(List.IncrementTime)--毫秒

		--保存到缓存
		RedisCahche.SetChacheHash(sKey,nCfgType,tData)

		return tData 
	elseif nCfgType==2 then --2 机器人策略配置
		local sKey = string.format("LiveLumbering_%d_157_%d",nGroupId,nRoomId)
		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,nCfgType)
		if tCache then
			return table.unpack(tCache)
		end
		
		local sAndroidStrategy = tRedis:hget(sKey,"AndroidStrategy")
		local isSuccee,arrAndroidStrategy = pcall(cjson.decode,sAndroidStrategy)
		if not isSuccee then
			arrAndroidStrategy = nil
		end

		--保存到缓存
		RedisCahche.SetChacheHash(sKey,nCfgType,arrAndroidStrategy)

		return arrAndroidStrategy
	end 
end

-- 获取篮球 游戏配置 : nCfgType:  1 基本配置(入场费,最大秒数,每个进球分数,暴击持续时间)
function RedisCahche._GetBasketballGameConfig(nGroupId,nRoomId,nCfgType)
	nGroupId = nGroupId or 0
	nRoomId = nRoomId or 2
	local tRedis = tBase.m_MyRedisData[2].redis
	if nCfgType == 1 then -- 基本配置(入场费,最大秒数,每个进球分数,暴击持续时间)
		local sKey = string.format("LiveLumbering_%d_159_%d",nGroupId,nRoomId)
		--读取缓存数据
		local tCache = RedisCahche.GetChache(sKey)
		if tCache then
			return table.unpack(tCache)
		end
		
		local List = tRedis:hgetall(sKey) or {}
		if List == nil or #List < 0 then
			Base.Log("GetRoomBasecfg 159 篮球后台配置不存在 ")
			return nil
		end

		local tData = {}
		tData.nEntranceFee = tonumber(List.AdmissionFee)
		tData.nOperationTime = tonumber(List.OperationTime)
		tData.nScore = tonumber(List.Score)
		tData.nknockingTime = tonumber(List.IncrementTime)--暴击持续时间
		tData.isRimMove = (tonumber(List.isRimMove) == 1)
		tData.tRimCoord = {}

		--数据组合
		if List.tRimCoord and List.nRimRadii then
			local x,y =string.match(List.tRimCoord,"(%w+),(%w+)")
			if tonumber(x) > 0  and tonumber(y) > 0 then
				table.insert(tData.tRimCoord,tonumber(x))
				table.insert(tData.tRimCoord,tonumber(y))
			else
				Base.Log("GetRoomBasecfg 159  tData 配置错误")
			end
			tData.nRimRadii = tonumber(List.nRimRadii)
			--保存到缓存
			RedisCahche.SetChache(sKey,tData)
			Base.Log("GetRoomBasecfg 159  tData_%s",cjson.encode(tData))
			return tData 
		else
			Base.Log("GetRoomBasecfg 篮球游戏 后台配置不存在 ")
		end
	elseif nCfgType==2 then --2 机器人策略配置
		local sKey = string.format("LiveLumbering_%d_159_%d",nGroupId,nRoomId)
		--读取缓存数据
		local tCache = RedisCahche.GetChacheHash(sKey,nCfgType)
		if tCache then
			return table.unpack(tCache)
		end
		
		local sAndroidStrategy = tRedis:hget(sKey,"AndroidStrategy")
		local isSuccee,arrAndroidStrategy = pcall(cjson.decode,sAndroidStrategy)
		if not isSuccee then
			arrAndroidStrategy = nil
		end

		--保存到缓存
		RedisCahche.SetChacheHash(sKey,nCfgType,arrAndroidStrategy)

		return arrAndroidStrategy
	end 
end

--获取飞行飞刀底分配置三个底分和最大最小底分
function RedisCahche.Get_FellTreeGameBaseScoreConfig(nGameId,nGroupId)
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("FellTreeGameConfig_%d",nGroupId)

	local sSubKey = "Score"
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local arrRlt =My_2:hmget(sKey,"Score1","Score2","Score3","MinScore","MaxScore")

	local num = 0
	for k,v in pairs(arrRlt) do
	   if v and tonumber(v) > 0 then
		 num = num + 1
	   end
    end

	if num >= 8 then
		local Score1=(tonumber(arrRlt[1]))
		local Score2=(tonumber(arrRlt[2]))
		local Score3=(tonumber(arrRlt[3]))
		local MinScore=(tonumber(arrRlt[4]))
		local MaxScore=(tonumber(arrRlt[5]))
		tBase.Log("nGroupId：%d 后台底分配置列表： %d %d %d MinScore:%d  MaxScore:%d",nGroupId,Score1,Score2,Score3,MinScore,MaxScore)
		
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,{Score1,Score2,Score3,MinScore,MaxScore})

		return {Score1,Score2,Score3,MinScore,MaxScore}
	else
		tBase.Log("未获取到后台底分配置列表 将使用默认配置")
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,nil)

		return nil
	end
end

--机器人金币范围设置信息.
--返回示例 :{{20,100,1000},{60,100,10000},{20,10000,20000}}
function RedisCahche.GetAndroidGoldConfig(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("AndroidGoldConfig_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sJsonData =redis:get(sKey)
	local tData =nil
	if sJsonData then
		tData= cjson.decode(sJsonData)  
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,tData)
	
	return tData  
end

--通知转账地址与一些配置
function RedisCahche.GetTransferNotifyInfo(nGroupId)
	local nGroupId =nGroupId or -1
	local My_2 = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("TransferNotifyConfig_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tConfig =  My_2:hgetall(sKey)

	--保存到缓存
	RedisCahche.SetChache(sKey,tConfig)

	return tConfig
end

--机器人在桌子开始后多少局开始进入
function RedisCahche.InnRangeOfAndroidEnter(nGameId,nGroupId)
	local nGameId =nGameId or -1
	local nGroupId =nGroupId or -1
	local tRedis = tBase.m_MyRedisData[2].redis
	local sKey =string.format("InnRangeOfAndroidEnter_Group%d_Game%d",nGroupId,nGameId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local arrRlt =tRedis:hmget(sKey,"nMin","nMax")
	local nMin =tonumber(arrRlt[1])
	local nMax =tonumber(arrRlt[2])
	if nMin==nil or nMax==nil or nMin>nMax then
		tBase.Log("sKey:%s something wrong",sKey)
		nMin=4
		nMax=8
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,nMin,nMax)

	return nMin,nMax
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
function RedisCahche.GetTexasConfig(nGroupId,nRoomId)
	local nGroupId =nGroupId or -1
	local nRoomId =nRoomId or -1
	local sKey =string.format("TexasConfig_Group%d_Room%d",nGroupId,nRoomId)
	local sDefault ="TexasConfig_Default"

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tData =  tBase.m_MyRedisData[2].redis:hgetall(sKey)
	if next(tData) ==nil then
		tData = tBase.m_MyRedisData[2].redis:hgetall(sDefault) or {}
	end
	local tConfig ={}
	tConfig.nFee =tonumber(tData.nFee) or 0												--手续费
	tConfig.nTax =tonumber(tData.nTax) or 0												--抽水

	--人数选项
	tConfig.arrCapacityOption ={}
	local isSuccee,tRlt =pcall(cjson.decode,tData.arrCapacityOption or "[2,3,4,5,6]")
	if isSuccee then
		for _,num in ipairs(tRlt) do
			if num>=2 and num<=9 then
				table.insert(tConfig.arrCapacityOption,num)
			else
				tBase.Log("find error config")
			end
		end
	else
		tBase.LogT("json decode fail:",tRlt,tData.arrCapacityOption)
		if type(tRlt) == "string" then 
			mlogger:error(tRlt)
		end
	end

   --大小盲、最低最高带入选项
   	tConfig.arrConfigOption ={}
	local isSuccee1,tRlt1 =pcall(cjson.decode,tData.arrConfigOption or "[[5,10,100,2000],[200,400,3000,6000],[1600,3200,32000,640000]]")
	if isSuccee1 then
		for _,arr in ipairs(tRlt1) do
			if isTexasConfigItemLegal(arr) then
				table.insert(tConfig.arrConfigOption,arr)
			else
				tBase.Log("find error config")
			end
		end
	else
		tBase.LogT("json decode fail:",tRlt1,tData.arrConfigOption)
		if type(tRlt1) == "string" then 
			mlogger:error(tRlt1)
		end
	end
	if tConfig.nFee <0 then
		tConfig.nFee =0
		tBase.Log("find error: nFee Error")
	end
	if tConfig.nTax<0 or tConfig.nTax>100 then
		tConfig.nTax =0
		tBase.Log("find error: nTax Error")
	end

	--牌桌持续时间
	tConfig.arrKeepTimeOption ={}
	local isSuccee,tRlt =pcall(cjson.decode,tData.arrKeepTimeOption or "[30,60,120]")
	if isSuccee then
		for _,num in ipairs(tRlt) do
			if num>=2 and num<=9 then
				table.insert(tConfig.arrKeepTimeOption,num)
			else
				tBase.Log("find error config")
			end
		end
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,tConfig)

	return tConfig
end

--德州桌子 猜牌配置
function RedisCahche.GetTexasGuessConfig(nGroupId,nRoomId)
	local nGroupId =nGroupId or -1
	local nRoomId =nRoomId or -1
	local sKey =string.format("TexasConfig_Group%d_Room%d",nGroupId,nRoomId)
	local sDefault ="TexasConfig_Default"

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tData =  tBase.m_MyRedisData[2].redis:hgetall(sKey)
	if next(tData) ==nil then
		tData = tBase.m_MyRedisData[2].redis:hgetall(sDefault) or {}
	end 
 	if not tData then
		--保存到缓存
		RedisCahche.SetChache(sKey,nil) 
 		return 
 	end 
 	local tConfig = {}
 	tConfig.nDeZhouCountDown = tonumber(tData.nDeZhouCountDown) or 3    -- 答题时间
 	tConfig.isSwitch = tData.isSwitch or true						    -- 德州猜牌开关
 	tConfig.nStrikeProb = tonumber(tData.nStrikeProb) or 10				        -- 触发概率
 	tConfig.nRatioUser = tonumber(tData.nRatioUser) or 10 					    -- 比例用户
 	tConfig.nMaxUserCount =tonumber(tData.nMaxUserCount) or 10				    -- 参与最大用户数量
 	tConfig.nAwardGold = tonumber(tData.nAwardGold) or 10					 	    -- 奖励金币
 	tConfig.tCorrectCardModel = tData.tCorrectCardModel	or {20,35,50}   -- 正确牌型概率: 开三张20%，四张35%，全部50%
	 
	--保存到缓存
	RedisCahche.SetChache(sKey,tConfig) 

	return tConfig
end

--获取洗牌所需金币
function RedisCahche.GetShuffleCardsCost(nGroupId,nGameId)
	local sKey = string.format("ShuffleCards:Group%d:Game%d",nGroupId,nGameId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tRedis =tBase.m_MyRedisData[2].redis
	local sNeedGold = tRedis:get(sKey)
	local nNeedGold = 0
	if sNeedGold then
		nNeedGold = tonumber(sNeedGold) or 0
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,nNeedGold)

	return nNeedGold
end

--德州游戏间隔配置
function RedisCahche.GetDeZhouIntervalTime(nGroupId,nLev)
	if true then
		local ToStartTime, ToSettleEndTime = 3, 7  --开局倒计时时间, 结算动画时间
		if nLev == 1 then
			return 1, 4
		elseif nLev ==2 then
			return 3, 5
		elseif nLev ==3 then
			return 6, 7
		end
		return ToStartTime, ToSettleEndTime
	end

	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("DeZhouIntervalConfig_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sToStartTimeKey =string.format("%d_1",nLev)
	local sSettleTimeKey =string.format("%d_2",nLev)

	local arrRlt =redis:hmget(sKey,sToStartTimeKey,sSettleTimeKey)

	local nToStartTimeKey =tonumber(arrRlt[1]) or 0
	local nSettleTimeKey =tonumber(arrRlt[2]) or 0

	--保存到缓存
	RedisCahche.SetChache(sKey,nToStartTimeKey,nSettleTimeKey)

	return nToStartTimeKey,nSettleTimeKey
end

function RedisCahche.IsGmOpen()
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = "GmSwitch"
	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sResult2 = redis:get(sKey)
	if sResult2 =="1" then
		--保存到缓存
		RedisCahche.SetChache(sKey,true)
		return true
	end
	--保存到缓存
	RedisCahche.SetChache(sKey,false)
	return false
end

--德州每天最大免费试玩次数
function RedisCahche.GetMaxTryPlayCntOfTexas(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("CountOfTexasTryPlay_%d",nGroupId)
	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sResult = redis:get(sKey)
	--保存到缓存
	RedisCahche.SetChache(sKey,(tonumber(sResult) or 3))
	return (tonumber(sResult) or 3)
end

--看广告每天最大赠送金币次数和金币数量
function RedisCahche.GetGiveInfoOfLookAdvertisement(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("CountOfLookAdvertisement_%d",nGroupId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local arrRlt =redis:hmget(sKey,"sTodayMaxGetCnt","sGiveGold")

	local nTodayMaxGetCnt =tonumber(arrRlt[1]) or 0
	local nGiveGold =tonumber(arrRlt[2]) or 0

	--保存到缓存
	RedisCahche.SetChache(sKey,nTodayMaxGetCnt,nGiveGold)

	return nTodayMaxGetCnt,nGiveGold
end

--获取直播百人类游戏的抽水率(闲家默认是0，庄家默认是0.05)
function RedisCahche.GetLiveBRDrowWaterRate(nGroupId,nGameId,nRoomId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =  string.format("Hundred_GroupId%d_GameId%d_RoomId%d",nGroupId,nGameId,nRoomId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	--闲家抽水率
	local sResult = redis:hget(sKey,"Tax") --如果存在，理论上是0~1000
	local nDrowWaterRate = 0
	if sResult then
		local nResult = tonumber(sResult) or 0
		nDrowWaterRate = nResult/1000
	end

	--庄家抽水率
	local sResult_Banker = redis:hget(sKey,"SZ_Tax") --如果存在，理论上是0~1000
	local nDrowWaterRate_Banker = 0.05
	if sResult_Banker then
		local nResult = tonumber(sResult_Banker) or 0
		nDrowWaterRate_Banker = nResult/1000
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,nDrowWaterRate,nDrowWaterRate_Banker)

	return nDrowWaterRate,nDrowWaterRate_Banker
end

--获取维护服的状态
--@params nServerId:服务器服id  如101
--@return nServerState 服务器状态 0:未启用 1:正常 2:维护 3:测试 4:进程没开 (默认1)
function RedisCahche.GetServerState(nServerId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("nServerId_State")
	local sSubKey =string.format("%d",nServerId)

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
    if tCache then
        return table.unpack(tCache)
    end

	local sRlt =redis:hget(sKey,sSubKey)
	local nServerState = 1
	if sRlt then
		nServerState = tonumber(sRlt) or 1
	end

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nServerState)

	return nServerState
end

--  区块链 停服维护:  {nType(维护类型:0维护期间,1开始维护倒计时),nCountDown:倒计时}
function RedisCahche.BlockchainStopServerMaintian(nServerId)
	if not nServerId then 
		nServerId = tSrvInfo.nServerId
	end
	local sKey = "Maintenance_TimePeriod" 
	local sField =string.format("nCenterId_%d",nServerId)

	--更新状态
	local _RefreshStatus = function (tData)
		if type(tData)~="table" then
			return
		end
		--维护结束 检查
		local nNow =os.time()
		if nNow>=tData.ActualEnd then
			tBase.Log("Maintenance End")
			--保存到缓存
			RedisCahche.SetChacheHash(sKey,sField,nil)
			return
		end

		--兼容如虹定义字段
		local nType =1							--0 正在维护，1 即将维护
		local nCountDown = tData.ActualStart -nNow
		if nNow>=tData.ActualStart and nNow<tData.ActualEnd then
			nType =0
			nCountDown =tData.ActualEnd -nNow
		end

		tData.nType = nType
		tData.nCountDown= nCountDown
		tData.nPassTime = nNow -tData.ActualStart
		return tData
	end

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sField)
    if tCache then
		local temCache = table.unpack(tCache)
        return _RefreshStatus(temCache)
    end

	local redis =tBase.m_MyRedisData[2].redis
	local sRlt =redis:hget(sKey,sField)
	if sRlt==nil then
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sField,nil)
		return
	end
	local isSuccee,tRlt =pcall(cjson.decode,sRlt)
	if not isSuccee then
		tBase.LogT(tRlt)	--error msg
		if type(tRlt) == "string" then 
			mlogger:error(tRlt)
		end
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sField,nil)
		return
	end
	local ActualStart =tonumber(tRlt.ActualStart or -1)	--维护开始时间戳，届时踢出所有用户
	local ActualEnd =tonumber(tRlt.ActualEnd or -1)		--预计维护结束时间戳

	--配置合法性 检查
	if ActualStart==-1 or ActualEnd==-1 then
		tBase.Log("Fied Error")
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sField,nil)
		return
	end
	--配置合法性 检查
	if ActualEnd < ActualStart then
		tBase.Log("Fied Error2")
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sField,nil)
		return
	end

	tBase.Log("_BlockchainStopServerMaintian   %s   %s   ",api.OsTimetoDataTime(ActualStart),api.OsTimetoDataTime(ActualEnd))

	local t ={}
	t.ActualStart=ActualStart					--维护开始时间戳，届时踢出所有用户
	t.ActualEnd=ActualEnd						--预计维护结束时间戳
	t.sStartTime= tostring(ActualStart)		--开始时间(本地时区)
	t.sEndTime= tostring(ActualEnd)	    	--结束时间(本地时区)

	local tem = _RefreshStatus(t)

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sField,tem)

	return tem
end

--是否白名单用户. 是:true
function RedisCahche.IsWhiteListUser(nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sField =string.format("%d",nUserId)
	local sKey = "Maintenance_whitelist"

	--读取缓存数据
    local tCache = RedisCahche.GetChacheHash(sKey,sField)
    if tCache then
        return table.unpack(tCache)
    end

	local sRlt =redis:hget(sKey,sField)
	if sRlt and #sRlt>0 then
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sField,true)
		return true
	end
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sField,false)
	return false
end

--获取试玩金币下注记录域名
function RedisCahche.GetDemoPetternDomainName()
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="DemoPetternDomainName"

	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt =redis:get(sKey)

	--保存到缓存
	RedisCahche.SetChache(sKey,sRlt)

	return sRlt
end

--获取战绩播报域名
function RedisCahche.GetRecordBraodCastDomainName()
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="GSP_UserControlTele"
	local sSubKey = "RecordBroadCast"

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt =redis:hget(sKey,"RecordBroadCast")

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,sRlt)

	return sRlt
end

--读取其它厂商输赢域名
function RedisCahche.GetOtherPlatformWinloseDomainName()
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="GSP_UserControlTele"
	local sSubKey = "OtherPlatformWinlose"

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt =redis:hget(sKey,"OtherPlatformWinlose")
	if not sRlt then
		sRlt = ""
	end

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,sRlt)

	return sRlt
end

--请求APP黑名单接口
function RedisCahche.GetAppBlackUserListDomainName()
	local redis =tBase.m_MyRedisData[2].redis
	local sKey ="GSP_UserControlTele"
	local sSubKey = "AppBlackUserList"

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt =redis:hget(sKey,"AppBlackUserList")

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,sRlt)

	return sRlt
end

--获取试玩模式配置
function RedisCahche.GetConfigOfTryPlay(nGroupId,sSubKey)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("GoldOfTryPlay_%d",nGroupId)

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt = redis:hget(sKey,sSubKey)

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,sRlt)

	return sRlt
end

--获取 鱼虾蟹赔率配置
function RedisCahche.GetConfigAreaOdds(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = "YuXiaXieM_AreaOdds"
	local sSubKey =  string.format("AreaOdds_GroupId_%d",nGroupId)
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then 
		return table.unpack(tCache)
	end 
	local sRlt = redis:hget(sKey,sSubKey) 
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,sRlt)
	return sRlt
end

--获取  直播牌桌 统一结果
function RedisCahche._GetLiveOpenTable_UnifyResult(nGameId,nGroupId,nGetIndex,sTableId)
    local t = api.string_split(sTableId,"#") 
	local nNowTime = tBase.GetCountDTime()  -- 当前时间戳 
	local sKey = "LiveOpenTable_Result"
	local sSubKey = string.format("GameId_%d_Date_%s",nGameId,os.date("%Y-%m-%d",nNowTime))
	--[[
	LiveOpenTable_Result={ 
		nPaiJuTime  = 50                      -- 一整局时间  
		GameId_121_Date_2021-10-26 = {  
		nTime = os.time() 		    		  -- 牌局开始时间戳
		tResult = {1,2,3}    				  -- 开局结果   
		}
	}
	]] 

	local function _GetCacheData(sKey,nGetIndex) 
		local tCache = RedisCahche.GetChacheHash(sKey,nGetIndex)
		if tCache then 
			return table.unpack(tCache)
		end 	
		return nil 	
	end 
	local function _LoadCacheData(sLoadKey) 
		if not sLoadKey then 
			local sSubKey = string.format("GameId_%d_Date_%s",nGameId,os.date("%Y-%m-%d",nNowTime))
			sLoadKey = sSubKey
		end 
		local redis =tBase.m_MyRedisData[2].redis 
		local sResult = redis:hget("LiveOpenTable_Result",sLoadKey)	
		if sResult then 
			local arrResult = cjson.decode(sResult)	  
			for k,tPaiJuData in pairs(arrResult) do			  		
				if tPaiJuData and tonumber(tPaiJuData.nTime) and tPaiJuData.tResult and #tPaiJuData.tResult == 3 then  
					local tData = {}
					tData.nTime 	= tonumber(tPaiJuData.nTime)      
					tData.sDate 	= api.OsTimetoDataTime(tPaiJuData.nTime)
					tData.nIndex 	= math.floor(tonumber(tPaiJuData.nTime) / 50)  
					tData.arrDice 	= tPaiJuData.tResult
					RedisCahche.SetChacheHash(sKey,tData.nIndex,tData)   --保存到缓存   	 
				end 
			end	 
			tBase.Log("_LoadCacheData  nGetIndex: %d  %s 加载配置 nSum: %d  ",nGetIndex,sLoadKey,#arrResult) 	
			if #arrResult <= 1000 then 
	        	local sSend =string.format("统一牌桌结果告警: %d  %s 数据不够nSum: %d",tSrvInfo.nServerId,sLoadKey,#arrResult) 
	        	PrintError("_LoadCacheData sTableId: %s  %s ",sTableId,sSend)
			end  
			return arrResult
		else
			-- tBase.Log("_LoadCacheData  nGetIndex: %d  %s 没有配置数据  sTableId: %s  ",nGetIndex,sLoadKey,sTableId) 				
		end 
		return {}
	end  	
	local function _CheckCacheData()  
		local nZeroTime = api.GetLeroLeadTime(nNowTime) 
		if nZeroTime > 0 and nZeroTime <= 60*30 then   
			if math.random(1,100) > 50 then return end  
			if math.floor(nNowTime/50) ~= nGetIndex then return end 
			local arrKey = {}  	-- 检测 未来 3天 数据是否正常 
			for i=1,3 do   
				local nSeconds = 60*60*24 * i
				local nDaySeconds = nNowTime + nSeconds
				local sLoadKey = string.format("GameId_%d_Date_%s",nGameId,os.date("%Y-%m-%d",nDaySeconds)) 
				table.insert(arrKey,sLoadKey)
			end 
			for k,sLoadKey in pairs(arrKey) do
				local arrResult = _LoadCacheData(sLoadKey)
				if #arrResult < 1000 then 
					PrintError("_CheckCacheData 统一牌桌结果告警   %s  arrResult: %d ",sLoadKey,#arrResult)  
					break
				end 				 
			end 
		end 
		return
	end 
 	local isSuccee,sErr = pcall(_CheckCacheData)
	if not isSuccee then
		PrintError("_CheckCacheData %s ",sErr)  
	end    		
	local tData = _GetCacheData(sKey,nGetIndex)
	if tData then 
		return tData
	end 
	local isSuccee,sErr = pcall(_LoadCacheData)
	if not isSuccee then
		PrintError(" _LoadCacheData 需要加载配置  sTableId: %s  sErr: %s ",sTableId,sErr)  
	end    
	tData = _GetCacheData(sKey,nGetIndex)
	if tData then 
		return tData
	end 
	return   
end

--获取  直播牌桌 结果
function RedisCahche._GetUnifyResult(nGameId,nGroupId,isNow,sTableId) 
	local nNowTime = tBase.GetCountDTime()  -- 当前时间戳 
	local nGetIndex = math.floor(nNowTime/50)
	if not isNow then 
		nGetIndex = nGetIndex + 1
	end 
	local tData = RedisCahche._GetLiveOpenTable_UnifyResult(nGameId,nGroupId,nGetIndex,sTableId)   
	if not tData then   -- 报警 
		local sDate = api.OsTimetoDataTime(nNowTime)
        local t = api.string_split(sTableId,"#") 
		local sToDayKey= string.format("GameId_%d_Date_%s",nGameId,os.date("%Y-%m-%d",nNowTime))
        local sSend =string.format("统一牌桌结果告警: %d=%s nGameId: %d %d  Now: %s nGetIndex: %d 当局没有数据 "
        ,tSrvInfo.nServerId,t[2] or -1,nGameId,nGroupId,sDate,nGetIndex)
        PrintError("_GetUnifyResult sTableId: %s %s ",sTableId,sSend)
		return 
	end       
	return tData
end

--与机器人输赢的抽水百分比,默认返回0
function RedisCahche.GetPoolWinWaterPer(nGameId,nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = "50F3DF333BB14C9AA7B51EAA8D0A18C7_Control"
	local sSubKey = string.format('Group_%d_%d_PoolWinWaterPer',nGroupId,nGameId)
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end
	local sVal = redis:hget(sKey,sSubKey)
	local nPoolWinWaterPer = tonumber(sVal)  or 0
	nPoolWinWaterPer = nPoolWinWaterPer /100
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nPoolWinWaterPer)

	return nPoolWinWaterPer
end

-- 获取 推荐控概率 配置
function RedisCahche._GetLiveRecommendControl(nLiveUserID,nGameId,isLoadConfig)
    local sKey = string.format("Live_RecommendProbabilityNew_%d",nLiveUserID)	   
	local tConfig = {}
	local arr = {} 
	local nLoadResult = true 
    local function _GetConfig() 
		local tCache = RedisCahche.GetChacheHash(sKey)
	    if tCache then 
	        return table.unpack(tCache)
	    end  
		nLoadResult = false
		local Redis = tBase.m_MyRedisData[2].redis 
		local tProbability = Redis:hgetall(sKey)
		if not tProbability or not tProbability.nPlanType then 
			tBase.Log("_GetLiveRecommendControl_%d 没有配置",nLiveUserID) 
			return  
		end   
		tConfig.bSwitch = (tonumber(tProbability.bSwitch)==1)                   -- 配置开关:  true,false 
		tConfig.arrEndInning = cjson.decode(tProbability.arrEndInning) 		    -- 结束局数范围:  
		tConfig.arrWinLose = cjson.decode(tProbability.arrWinLose)		        -- 结束赢利范围:     
		tConfig.arrGameId = cjson.decode(tProbability.arrGameId)                -- 支持游戏GameId: 
		tConfig.arrProbability = cjson.decode(tProbability.arrProbability)      -- 概率范围: 1-100    
		tConfig.nPlanType = tonumber(tProbability.nPlanType) 			        -- 计划类型: 1 时间段,2时间点 	
		if tConfig.nPlanType == 1 then 
			if not tProbability.arrTimeSlot or #tProbability.arrTimeSlot == 0 then 
				tBase.Log("_GetLiveRecommendControl  sKey_%s  arrTimeSlot: %s  arrTimeSlot is nil ",nLiveUserID,cjson.encode(tProbability.arrTimeSlot)) 
				return 0
			end  
			tConfig.arrTimeSlot = cjson.decode(tProbability.arrTimeSlot) 			-- 时间段: [开始时间戳,结束时间戳]   
		else
			if not tProbability.arrHour or #tProbability.arrHour == 0 then 
				tBase.Log("_GetLiveRecommendControl  sKey_%s  arrHour: %s  arrHour is nil ",sKey,cjson.encode(tProbability.arrHour)) 
				return 0
			end 
			tConfig.arrHour = cjson.decode(tProbability.arrHour)                    -- 时间点: 0 -24 点
		end 
		if not tConfig.arrProbability or #tConfig.arrProbability ~= 2 then 
			tBase.Log("_GetLiveRecommendControl_%d  arrProbability is nil arrProbability: %s  ",nLiveUserID,cjson.encode(tConfig.arrProbability)) 
			return 0
	  	end 
		if not tConfig.arrGameId or #tConfig.arrGameId == 0 then 
			tBase.Log("_GetLiveRecommendControl_%d arrGameId is nil  arrGameId: %s ",nLiveUserID,cjson.encode(tConfig.arrGameId)) 
			return 0 
		end 
		if not tConfig.arrEndInning or #tConfig.arrEndInning == 0 then 
			tBase.Log("_GetLiveRecommendControl_%d arrEndInning is nil  arrEndInning: %s ",nLiveUserID,cjson.encode(tConfig.arrEndInning)) 
			return 0 
		end 
		if not tConfig.arrWinLose or #tConfig.arrWinLose == 0 then 
			tBase.Log("_GetLiveRecommendControl_%d arrWinLose is nil  arrWinLose: %s ",nLiveUserID,cjson.encode(tConfig.arrWinLose)) 
			return 0 
		end 
		nLoadResult = true 
		RedisCahche.SetChacheHash(sKey,tConfig) 
		return tConfig	    
    end 
    local function _CheckLogic(tProbability)    
		local Redis = tBase.m_MyRedisData[2].redis 	    
		if not tProbability.bSwitch then 
			tBase.Log("_GetLiveRecommendControl_%d 该配置关闭了 ",nLiveUserID) 
			return 0
		end
		local arrGameId = {}
		for k,v in pairs(tProbability.arrGameId) do
			arrGameId[tonumber(v)] = true  
		end
		if not arrGameId[nGameId] then 
			tBase.Log("_GetLiveRecommendControl_%d arrGameId: %s 没有该游戏: %d ",nLiveUserID,cjson.encode(tProbability.arrGameId),nGameId) 
			return 0  
		end 
		local nTime = os.time()
		local nPlanType = tonumber(tProbability.nPlanType) 
		local sSubkey = string.format("%s_Inning_Win",sKey)  
		local nKeyEndTIme = 0
		if nPlanType == 1 then   -- 时间段
			local nStartTime = tonumber(tProbability.arrTimeSlot[1])
			local nEndTime = tonumber(tProbability.arrTimeSlot[2])
			if nTime >= nStartTime and nTime <= nEndTime then   

			else
				local s1 = api.OsTimetoDataTime(nStartTime)
				local s2 = api.OsTimetoDataTime(nEndTime)
				tBase.Log("_GetLiveRecommendControl_%d   时间不正常 nStartTime: %s  %s %d  ",nLiveUserID,s1,s2,nTime) 
				return 0 
			end 
			nKeyEndTIme = tonumber(nEndTime - nStartTime)
		else
			table.sort(tProbability.arrHour) 
			local nHour = tonumber(os.date("%H",os.time()))
			local arrHour = {}
			for k,v in pairs(tProbability.arrHour) do
				arrHour[tonumber(v)] = true  
			end
			if not arrHour[nHour] then 
				tBase.Log("_GetLiveRecommendControl_%d arrHour: %s 此时没有: %d ",nLiveUserID,cjson.encode(tProbability.arrHour),nHour)  
				return 0  
			end 
			nKeyEndTIme = api.GetLeroLeadTime()   -- 获取当天零点时间 
			-- sSubkey = string.format("%s_%s",sSubkey, os.date("%Y-%m-%d",nTime))  
		end   		  
		local tEndData = Redis:hgetall(sSubkey) 
		if not tEndData or not tEndData.nEndInning then 
			if not isLoadConfig then 		
				tBase.Log("_GetLiveRecommendControl_%d  加载配置  %s",nLiveUserID,cjson.encode(tProbability)) 	  
				tEndData.nEndWin   =  api.RandDouble(tProbability.arrWinLose[1],tProbability.arrWinLose[2])      -- 赢结束的数量
				tEndData.nEndInning = tonumber(math.random(tProbability.arrEndInning[1],tProbability.arrEndInning[2]) or 0)  -- 赢的结束局数
				tEndData.nNowInning = 0          -- 当前调控局数
				tEndData.nNowWin = 0             -- 计划内盈利情况
				tEndData.nNatureWin = 0          -- 自然赢局数
				tEndData.nPlanInning = 0         -- 计划内总局数
				tBase.Log("_GetLiveRecommendControl_%d  初始化数据 %d 秒,nEndInning_%f nEndWin_%f  %s",nLiveUserID,nKeyEndTIme,tEndData.nEndInning,tEndData.nEndWin,(nKeyEndTIme)) 
				Redis:hmset(sSubkey,tEndData)
				Redis:expire(sSubkey,math.floor(nKeyEndTIme))   
			end 
		else	
			-- 检查 结束局数
			if tonumber(tEndData.nNowInning) >= tonumber(tEndData.nEndInning) then 
				tBase.Log("_GetLiveRecommendControl_%d 超局数了,结束  %s",nLiveUserID,cjson.encode(tEndData)) 
				return 0 
			end 
			-- 检查 盈利情况
			if tonumber(tEndData.nNowWin) >= tonumber(tEndData.nEndWin) then 
				tBase.Log("_GetLiveRecommendControl_%d 赢过份了,结束  %s",nLiveUserID,cjson.encode(tEndData))  
				return 0 
			end 	 
		end 
		table.sort(tProbability.arrProbability)
		for k, v in pairs(tProbability.arrProbability) do
			table.insert(arr,tonumber(v))
		end				
		return arr 
    end     
	local isSuccee,sErr = pcall(_GetConfig)
	if not isSuccee then  
		PrintError("_GetConfig %s ",sErr)
		tBase.Log("_GetLiveRecommendControl_%d  ErrorMsg  _GetConfig sErr: %s ",nLiveUserID,sErr) 
		return 0
	else
		if not nLoadResult then 
			return 0			 
		end 
		if not tConfig.nPlanType or not tConfig.bSwitch then   		
			return 0  
		end   
	end      
	local isSuccee,sErr = pcall(_CheckLogic,tConfig)
	if not isSuccee then 
		PrintError("_CheckLogic %s ",sErr)
		tBase.Log("_GetLiveRecommendControl_%d  ErrorMsg  _CheckLogic sErr: %s ",nLiveUserID,sErr) 
		return 0
	end 	
	if not arr or #arr ~= 2 then  
		return 0  
	end
	if isLoadConfig then   -- 只是获取配置
		return tConfig	 
	end
	return arr
end

--获取俱乐部配置
--@params nGroupId 分组id
function RedisCahche.GetClubConfig(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubConfig_Group%d",nGroupId or 0)

	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end

	local tData =  redis:hgetall(sKey)

	local tConfig = {}
	tConfig.nMaxUserCnt = tonumber(tData.nMaxUserCnt) --俱乐部成员上限
	tConfig.nClubTax = tonumber(tData.nClubTax) --俱乐部服务费分成(占抽水的多少，千分比，如95%,就填950)
	tConfig.nInsuranceTax = tonumber(tData.nInsuranceTax) --俱乐部保险分成(占抽水的多少，千分比，如95%,就填950)
	tConfig.IsNeedAndroidInHall = tData.IsNeedAndroidInHall--大厅桌是否加载机器人
	tConfig.IsNeedAndroidInClub = tData.IsNeedAndroidInClub--俱乐部桌是否加载机器人
	tConfig.IsUseGold = tData.IsUseGold--是否使用金币
	tConfig.IsUserClubGold = tData.IsUserClubGold--是否使用俱乐部币
	tConfig.IsOpenHall = tData.IsOpenHall--是否开启大厅
	tConfig.IsOpenClub = tData.IsOpenClub--是否开启俱乐部
	tConfig.IsCanCreateHallTable = tData.IsCanCreateHallTable--玩家是否能创建大厅桌
	
	tConfig.nUserOpenHallCnt = tonumber(tData.nUserOpenHallCnt) --一个玩家可以在大厅开多少张桌子
	tConfig.nUserOpenClubCnt = tonumber(tData.nUserOpenClubCnt) --一个玩家可以在一个俱乐部开多少张桌子
	tConfig.nUserCreateClubCnt = tonumber(tData.nUserCreateClubCnt) --一个玩家可以创建的俱乐部上限
	tConfig.nUserApplyClubCnt = tonumber(tData.nUserCreateClubCnt) --玩家加入俱乐部申请的数量上限
	tConfig.nUserApplyClubGoldCnt = tonumber(tData.nUserCreateClubCnt) --玩家俱乐部币增加退还申请的数量上限
	
	tConfig.IsManchu = tData.IsManchu   				--牌桌满人开关
	tConfig.arrOpenGameId = tData.arrOpenGameId	 	    --开放游戏id 
	tConfig.nOperateTime = tonumber(tData.nOperateTime)	or 15  --操作最大时间 
  
	-- 机器人 局数 退出机制
	tConfig.arrAndroidPlayCnt = {}
	tConfig.arrAndroidPlayCnt[1] = tonumber(tData.nAndroidPlayCntMin) or 30  -- 最小局数
	tConfig.arrAndroidPlayCnt[2] = tonumber(tData.nAndroidPlayCntMax) or 60  -- 最大局数
	
	tConfig.arrOddsList=tData.arrOddsList						--json数组;保险outs赔率表
	tConfig.nInsureNormalType=tonumber(tData.nInsureNormalType)	--常规保险时的保险类型;1:常规一,2常规二

	--保存到缓存
	RedisCahche.SetChache(sKey,tConfig)
	--修改过期时间为一天
	RedisCahche.ChangeChacheTime(1*10*60,sKey)

	return tConfig
end

--获取收费功能 配置
--@params nGroupId 分组id
function RedisCahche.GetClubChangeConfig(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = string.format("ClubChangeConfig_Group%d",nGroupId or 0) 
	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end
	local tData =  redis:hgetall(sKey) 
	local tConfig = {} 	 
	if tData.arrChatChangeCfg then  -- {{nChatId=1,nCost=10} } 表情价格表:  1-49 , 弹幕价格表:50-100  
		tConfig.arrChatChangeCfg = cjson.decode(tData.arrChatChangeCfg) 
	end 
	if tData.arrTableChangeCfg then   --nId: 1-9  延时操作    10-20看牌操作（10 看翻牌，11看转牌，12看河牌）
		tConfig.arrTableChangeCfg = cjson.decode(tData.arrTableChangeCfg) or {}	
	end  
	RedisCahche.SetChache(sKey,tConfig)  	--保存到缓存	
	RedisCahche.ChangeChacheTime(1*60*60,sKey)  --修改过期时间为一天
	return tConfig
end

--获取后台设置的金币标准值
function RedisCahche.GetGoldStandard(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = "GoldStandard"
	local sSubKey = string.format("nGroupId_%d",nGroupId)

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt = redis:hget(sKey,sSubKey)
	local nGoldStandard = tonumber(sRlt) or 0

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nGoldStandard)

	return nGoldStandard
end

-- 获取 俱乐部 德州 操作时间
function RedisCahche.GetClubConfigOperateTime(nGroupId)
	local tConfig =  RedisCahche.GetClubConfig(nGroupId)
	return tConfig.nOperateTime
end 

-- 获取 机器人局数退出机制
function RedisCahche.GetClubConfigAndroidPlayCnt(nGroupId)
	local tConfig =  RedisCahche.GetClubConfig(nGroupId)
	return tConfig.arrAndroidPlayCnt or {30,60}
end 

--获取常规保险配置
function RedisCahche.GetInsuerNormalCfg(nGroupId)
	local tConfig =  RedisCahche.GetClubConfig(nGroupId)
	--tConfig.arrOddsList						--json数组;保险outs赔率表
	--tConfig.nInsureNormalType					--常规保险时的保险类型;1:常规一,2常规二
	return {arrOddsList=tConfig.arrOddsList,nInsureNormalType=tConfig.nInsureNormalType}
end



--俱乐部德州桌子配置
function RedisCahche.GetClubTexasConfig(nGroupId,nRoomId,nGameId)
	local nGroupId =nGroupId or -1
	local nRoomId =nRoomId or -1
	local sKey =string.format("ClubTexasConfig_Group%d_GameId%d_Room%d",nGroupId,nGameId,nRoomId)

	--读取缓存数据
    local tCache = RedisCahche.GetChache(sKey)
    if tCache then
        return table.unpack(tCache)
    end

	local tData =  tBase.m_MyRedisData[2].redis:hgetall(sKey)
	if next(tData) ==nil then
		tData = {}
	end
	local tConfig ={}
	
	--人数选项
	tConfig.arrCapacityOption ={}
	local isSuccee,arrCapacityOption =pcall(cjson.decode,tData.arrCapacityOption)
	if isSuccee then
		tConfig.arrCapacityOption = arrCapacityOption
	else
		tConfig.arrCapacityOption = {2,3,4,5,6,7,8,9}
	end

   	--大小盲、默认带入,前注选项
   	tConfig.arrClubAnteOption ={}
	local isSuccee,arrClubAnteOption =pcall(cjson.decode,tData.arrClubAnteOption)
	if isSuccee then
		tConfig.arrClubAnteOption = arrClubAnteOption
	else
		tConfig.arrClubAnteOption = {{1,2,200,{0,1,2},2,2,2},{2,4,400,{0,1,2,4},4,4,4},{5,10,1000,{0,1,2,5,10},10,10,10}}
		if nGameId==175 then
			tConfig.arrClubAnteOption = {{1,2,200,{2},2,2,2},{2,3,400,{4},4,4,4},{4,8,1000,{10},10,10,10}}
		end
	end

	--牌桌持续时间选项
	tConfig.arrKeepTimeOption ={}
	local isSuccee2,arrKeepTimeOption =pcall(cjson.decode,tData.arrKeepTimeOption)
	if isSuccee2 then
		tConfig.arrKeepTimeOption = arrKeepTimeOption
	else
		tConfig.arrKeepTimeOption = {1,1.5,2,2.5,3,4,5,6}
	end

	--带入筹码倍数选项
	tConfig.arrTakeinOption ={}
	local isSuccee,arrTakeinOption =pcall(cjson.decode,tData.arrTakeinOption)
	if isSuccee then
		tConfig.arrTakeinOption = arrTakeinOption
	else
		tConfig.arrTakeinOption = {0.5,1,1.5,2,2.5,3,3.5,4}
	end

	--入池率选项
	tConfig.arrPoolEntryRateOption ={}
	local isSuccee,arrPoolEntryRateOption =pcall(cjson.decode,tData.arrPoolEntryRateOption)
	if isSuccee then
		tConfig.arrPoolEntryRateOption = arrPoolEntryRateOption
	else
		tConfig.arrPoolEntryRateOption = {25,30,35,40,45}
	end

	--抽水封顶选项
	tConfig.arrDWLimitOption ={}
	local isSuccee,arrDWLimitOption =pcall(cjson.decode,tData.arrDWLimitOption)
	if isSuccee then
		tConfig.arrDWLimitOption = arrDWLimitOption
	else
		tConfig.arrDWLimitOption = {1,2,3,4}
	end

	--保险赔率表
	tConfig.arrOddsTable ={}
	local isSuccee,arrOddsTable =pcall(cjson.decode,tData.arrOddsTable)
	if isSuccee then
		tConfig.arrOddsTable = arrOddsTable
	else
		tConfig.arrOddsTable = {}
	end

	--语聊收费价格
	local nVideoFee = tonumber(tData["VideoFee"]) or 0
	if nVideoFee == 0 then
		-- nVideoFee = 0.002
	end
	tConfig.nVideoFee = nVideoFee

	-- 离桌限制
	tConfig.tLeaveTableConfig = {
		arrWinThreshold = {},
		arrLots = {},
		arrPenaltyRatio = {},
		arrUserRatio = {},
	}
	local isSuccee,arrWinThreshold =pcall(cjson.decode,tData.profitThreshold)
	if isSuccee then
		tConfig.tLeaveTableConfig.arrWinThreshold = arrWinThreshold
	end

	local isSuccee,arrLots =pcall(cjson.decode,tData.handsOffTheTable)
	if isSuccee then
		tConfig.tLeaveTableConfig.arrLots = arrLots
	end

	-- 后台传的都是百分百前面的数值,使用时需要除100
	local isSuccee,arrPenaltyRatio =pcall(cjson.decode,tData.fineRate)
	if isSuccee then
		tConfig.tLeaveTableConfig.arrPenaltyRatio = getActualProportion(arrPenaltyRatio)
	end

	-- 后台传的都是百分百前面的数值,使用时需要除100
	local isSuccee,arrUserRatio =pcall(cjson.decode,tData.deskMatePlayerAllocationRatio)
	if isSuccee then
		tConfig.tLeaveTableConfig.arrUserRatio = getActualProportion(arrUserRatio)
	end

	
	--保存到缓存
	RedisCahche.SetChache(sKey,tConfig)

	return tConfig
end

function getActualProportion(arrRatio)
	local res = {}
	for _, v in ipairs(arrRatio) do
		table.insert(res, v / 100)
	end

	return res
end

--俱乐部德州配置  赔率表
function RedisCahche.GetClubTexasConfig_OddsTable(nGroupId,nRoomId,nGameId) 	
	local tConfig = RedisCahche.GetClubTexasConfig(nGroupId,nRoomId,nGameId)
	local arrOddsList = {}
	for k, v in pairs(tConfig.arrOddsTable) do
		if v and v[1] and v[2] and v[1] > 0 and v[2] > 0 then 
			local nCnt =  tonumber(v[1])
			local nOdds = tonumber(v[2])
			arrOddsList[nCnt] = nOdds
		end 
	end 
	for i = 1, 25, 1 do
		if not arrOddsList[i] then 
			arrOddsList[i] = 20
		end 
	end

	return arrOddsList
end 

--获取一张牌桌允许进入的真人数目
function RedisCahche.GetOneTableRealCnt(nGroupId,nGameId,nRoomId)
	local sKey =string.format("StandAlone_GroupID%d_GameID_%d_RoomID%d",nGroupId,nGameId,nRoomId)
	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end
	local redis = tBase.m_MyRedisData[2].redis
	local sRlt =  redis:get(sKey)
	local isSuccee,arrRlt = pcall(cjson.decode,sRlt or "[1,1]")
	if not isSuccee then
		arrRlt = {1,1}
	end
	local nMinCnt = arrRlt[1] or 1
	local nMaxCnt = arrRlt[2] or 1

	if nMinCnt and nMaxCnt and nMinCnt>nMaxCnt then
		tBase.Log("_GetOneTableRealCnt nMinCnt_%d>nMaxCnt_%d, set nMaxCnt=nMinCnt",nMinCnt,nMaxCnt)
		nMaxCnt = nMinCnt
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,nMinCnt,nMaxCnt)

	return nMinCnt,nMaxCnt
end

--获取修改昵称的消耗金币
function RedisCahche.GetChangeUserInfoConsume(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = "ChangeUserInfoConsume"
	local sSubKey = string.format("nGroupId_%d",nGroupId)

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local nGold = 10000 --金币消耗
	local nFreeCnt = 4 --免费次数
	local sRlt = redis:hget(sKey,sSubKey)
	local isSuceess,tConfig = pcall(cjson.decode,sRlt)
	if isSuceess then
		nGold = tConfig.nGold or 10000
		nFreeCnt = tConfig.nFreeCnt or 4
	end

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nGold,nFreeCnt)

	return nGold,nFreeCnt
end

--获取开桌消耗金币
function RedisCahche.GetOpenTableConsume(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = "ClubOpenTableConsume"
	local sSubKey = string.format("nGroupId_%d",nGroupId)

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local nGold = 0 --消耗数量
	local nGoldType = 1 --金币类型 1:金币 2:俱乐部币
	local sRlt = redis:hget(sKey,sSubKey)
	local isSuceess,tConfig = pcall(cjson.decode,sRlt)
	if isSuceess then
		nGold = tConfig.nGold or 0
		nGoldType = tConfig.nGoldType or 1
	end

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,nGold,nGoldType)

	return nGold,nGoldType
end

--获取等级配置
function RedisCahche.GetLevelConfig(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = "ClubLevelConfig_nGroupId_%d"

	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end

	local arrLevel = nil
	local tData = redis:hgetall(sKey)
	if next(tData) ~=nil then
		for k,v in pairs(tData) do
			local nLevel = tonumber(k)
			local nExp = tonumber(v)
			if nLevel and nExp then
				arrLevel = arrLevel or {}
				table.insert(arrLevel,{nLevel,nExp})
			end
		end
	end

	if arrLevel and #arrLevel>1 then
		table.sort(arrLevel,function (a, b)
			return a[1]<b[1]
		end)
	end

	--保存到缓存
	RedisCahche.SetChache(sKey,arrLevel)

	return arrLevel
end

--获取短信验证码域名
function RedisCahche.GetMsgCodeDomainName(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = string.format("MsgCodeDomainName_%d",nGroupId)

	--读取缓存数据
	local tCache = RedisCahche.GetChache(sKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sRlt =redis:get(sKey)

	--保存到缓存
	RedisCahche.SetChache(sKey,sRlt)

	return sRlt
end

--获取充值相关的域名
function RedisCahche.GetPayDomainName(sSubKey)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey = "IMAppWebKey"

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end

	local sUrl = redis:hget(sKey,sSubKey) 

	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,sUrl)

	return sUrl
end
 
-- LiveFollowConfig = {ArrList = {10,100,1000,10000},isSameMoneyFollowLiver = false,nMin = 10,nMax = 10000}
--获取直播跟投配置(nType 1:金额配置 2:倍数配置 3:局数配置)
function RedisCahche.GetLiveFollowConfig(nGameId,nGroupId,nType)
	local redis = tBase.m_MyRedisData[2].redis 
	local sKey =string.format("LiveFollowConfig")
	local sSubKey = string.format("nGroupId%d_nGameId%d_nType%d",nGroupId,nGameId,nType)

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		--tBase.LogT("GetLiveFollowConfig: cache ",sRlt)
		return table.unpack(tCache)
	end

	local sRlt = redis:hget(sKey,sSubKey)
	tBase.LogT("GetLiveFollowConfig: ",sRlt)
	local tRlt = {}
	if sRlt then
		tRlt = cjson.decode(sRlt)
	elseif nType == 1 then
		-- 使用默认配置
		tRlt = {ArrList = {100,1000,5000,10000},isSameMoneyFollowLiver = true,nMin = 100,nMax = 1000000}
		tBase.Log("GetLiveFollowConfig default: nGroupId_%d nGameId_%d nType_%d tRlt_%s",nGroupId,nGameId,nType,cjson.encode(tRlt))
	else
		tBase.Log("GetLiveFollowConfig: nType_%d is false request",nType)
	end

	if nType == 1 and tRlt.ArrList and #tRlt.ArrList > 0 and tRlt.nMin and tRlt.nMax and tRlt.nMax >= tRlt.nMin and tRlt.isSameMoneyFollowLiver ~= nil then
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,tRlt)
		tBase.LogT("GetLiveFollowConfig: no cache ",tRlt)
	else
		tBase.LogT("GetLiveFollowConfig is fail. sRlt_",sRlt)
	end
	return tRlt
end

--获取后台配置(金币是否带单位)
function RedisCahche.GetExtraConfigureInfo(nGroupId)
	local redis = tBase.m_MyRedisData[2].redis
	local sKey = "ExtraConfigureInfo"
	local sSubKey = string.format("nGroupId_%d",nGroupId)

	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end
	local sRlt = redis:hget(sKey,sSubKey)
	if sRlt then
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sSubKey,sRlt)
	else
		tBase.Log("ExtraConfigureInfo: nGroupId_%d is nil",nGroupId)
	end
	return sRlt
end

-- 服务器是否 维护
local function _IsServerIdMainTain(nServerId)    
    local nStatus = RedisCahche.GetServerState(nServerId) 
    if nStatus == 2 then  -- 服务器状态 0:未启用 1:正常 2:维护 3:测试 4:进程没开 (默认1)   
        return true 
    else
        return false
    end 
end

-- 获取 直播牌桌列表: (nGroupId,nTableType,nGameId)  nTableType: 牌桌类型: 0:预开桌,1:主播开桌,2区块链牌桌   nBlockChian 桌型: 1区块链、2固定桌、自己源桌、主播桌 
function RedisCahche.GetLiveTableList(nGroupId,nTableType,nGameId,nBlockChian) 
	-- 需要增加缓存机制，以此缓解 Redis 压力 
	local sKey = "APIOpenTale_*"
    local tRedis = tBase.m_MyRedisData[2].redis
    local arrTableInfo = tRedis:keys(sKey)
	local arrTable = {}
    for _,sTableId in pairs(arrTableInfo) do
        local tInfo = tRedis:hgetall(sTableId)
		if tInfo and tInfo.nGameId then 
			arrTable[sTableId] = tInfo
		end 
	end 
	local arrTableId = {}
    for sTableId,tInfo in pairs(arrTable) do
        if tonumber(tInfo.nGameId) == nGameId and tonumber(tInfo.nGroupId) == nGroupId then 
			local isLoad= false  
			if nBlockChian == 1 then 
				if tonumber(tInfo.nTableType) == 2 then  
					isLoad = true 
				end 
			else 
				-- 2固定桌、自己源桌、主播桌 
				isLoad = true  
				if tonumber(tInfo.nTableType) == 2 then  --   过滤 区块链、AG
					isLoad = false 
				end 				
			end 			
			if isLoad and tInfo.isPassWordRoom =="true" then   -- 密码房 需隐藏 
				isLoad = false 
			end 
			if isLoad then 
				local nServerId = tonumber(tInfo.nServerId) 
				if  _IsServerIdMainTain(nServerId) then 
					isLoad = false
					tBase.Log("ExtraConfigureInfo: nGroupId_%d  nServerId_%d  维护了  sTableId_%s ",nGroupId,nServerId,sTableId)
				end 
			end 
			if isLoad then   
				table.insert(arrTableId,tInfo.sTableId) 	 
			end 
        end 
	end  
	return arrTableId 
end

-- 获取 域名
function RedisCahche._Get_WebDomainName(sSubKey)
	local My_2 = tBase.m_MyRedisData[2].redis   
    local tCache = RedisCahche.GetChache(sSubKey)
    if tCache then
        return table.unpack(tCache)
    end
	local sDomainName =My_2:hget("IMAppWebKey",sSubKey)
	sDomainName = sDomainName or nil 
    RedisCahche.SetChache(sSubKey,sDomainName)	
	return sDomainName
end
  
-- 获取 小游戏配置
function RedisCahche._GetMiniGameCfg(nGameId)
	local redis = tBase.m_MyRedisData[2].redis 
	local sKey = string.format("MiniGame_%d",nGameId) 
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey)
	if tCache then
		return table.unpack(tCache)
	end
	local sCfg = redis:hgetall(sKey)
	if sCfg then
		--保存到缓存
		RedisCahche.SetChacheHash(sKey,sCfg)
	else
		tBase.Log("_GetMiniGameCfg: nGameId_%d is nil",nGameId)
	end
	return sCfg
end

-- 获取 德州机器人 等级配置
function RedisCahche._GetTexasAndroidLevelCfg(nGroupId,nGameId,nRoomId)
	local redis = tBase.m_MyRedisData[2].redis 
	local sKey = string.format("TexasAndroidLevelCfg") 
	nRoomId=-1
	local sSubKey = string.format("nGroupId_%d_%d_%d",nGroupId,nGameId,nRoomId) 
	--读取缓存数据
	local tCache = RedisCahche.GetChacheHash(sKey,sSubKey)
	if tCache then
		return table.unpack(tCache)
	end
 	local arrLevel = redis:hget(sKey,sSubKey) 
	tBase.Log("_GetTexasAndroidLevelCfg:  arrLevel: %s    sSubKey: %s ",arrLevel,sSubKey)

	if not arrLevel or #arrLevel < 2 then 
		arrLevel={50,50}
	else
		arrLevel=cjson.decode(arrLevel)
	end    
	arrLevel[1]= tonumber(arrLevel[1])
	arrLevel[2]= tonumber(arrLevel[2]) 
	tBase.Log("_GetTexasAndroidLevelCfg:  arrLevel: %s    %d %d  ",cjson.encode(arrLevel),arrLevel[1],arrLevel[2] )
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,sSubKey,arrLevel)
 	return arrLevel
end

 
-- 获取游戏的对应 typename 
function RedisCahche._GetMainIdToTypeName(nMainID)
	local sKey = "GameGateWay_MainIdToTypeName"
	local nMainId = math.floor(nMainID) 
	
	--读取缓存数据
	local sTypeName = RedisCahche.GetChacheHash(sKey,nMainId)
	if sTypeName then
		tBase.Log("_GetMainIdToTypeName 缓存  nMainId_%d  %s ",nMainId,table.unpack(sTypeName))
		return table.unpack(sTypeName)
	end
	local tRedis =tBase.m_MyRedisData[2].redis
	local sTypeName = tRedis:hget(sKey,nMainId)
	if not sTypeName then 
		tBase.Log("_GetMainIdToTypeName   nMainId_%d  sTypeName is nil tRedis  ",nMainId)
		return  
	end 
	tBase.Log("_GetMainIdToTypeName   nMainId_%d    tRedis  sTypeName_%s ",nMainId,sTypeName)
	--保存到缓存
	RedisCahche.SetChacheHash(sKey,nMainId,sTypeName)

	return sTypeName
end

return RedisCahche