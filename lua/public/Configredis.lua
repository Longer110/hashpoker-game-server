
--配置信息

package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path

local tBase 	= require("base")
local tSrvInfo  = require("ServerInfo")
local cjson    = require("cjson")          -- json 
local tApi  	   = require("publicApi")    -- 共用功能接口
local tPubUserApi  = require("PublicUserInfo")   -- 用户信息 



Configredis = {
	m_gold_roomkey = "gold_room_config",
	m_game_serveridkey = "Game_ServerID_Cfg",
}

--保存金币房的配置
--{nServerID = serverid,level =level,score=score,mincapital=mincapital,pima=pima}
function Configredis.SaveGoldRoomData(tData)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==141   ")  
		return
	end
	---------------------------------------------------------------------
	local sData = tData.Id..","..tData.level..","..tData.ServiceCharge..","..tData.score..","..
		tData.mincapital..","..tData.pima..","..tData.GameType..","..tData.MinGold..","..tData.Maxcapital

	-- tBase.Log("机器人机器人机器人机器人机器人机器人机器人机器人===> %s ",sData)
	local key = Configredis.m_gold_roomkey
	tBase.m_MyRedisData[1].redis:sadd(key, sData)
	--------------------------------------------------------------------------
end

-- 保存  游戏服 serverid 配置
function Configredis.Save_GameServerID_Data(tData)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==142   ")  
		return
	end
	local sData = tData.Id..","..tData.nServerID..","..tData.nGameServerType..","..tData.nGoldLevel
	local key = Configredis.m_game_serveridkey
	tBase.m_MyRedisData[1].redis:sadd(key, sData)
end

--根据金币房的等级获取数据(不使用)
function Configredis.GetGoldRoomData(level)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==143   ")  
		return {}
	end
	local tData ={}
	local key = Configredis.m_gold_roomkey
	local strList = tBase.m_MyRedisData[1].redis:smembers(key)
	local DataList = {}
	for i =1, #strList do 
		local tDatatm ={}
		local tData = tApi.Split(strList[i],",")
		local level1 = tonumber(tData[2])
		if (level == level1) then
			--1,6,1312,1500,15000,6
			local tDatatm ={}
			tDatatm.Id = tonumber(tData[1])
			tDatatm.level =tonumber(tData[2])
			tDatatm.free =tonumber(tData[3])
			tDatatm.score =tonumber(tData[4])
			tDatatm.mincapital =tonumber(tData[5])
			tDatatm.pima =tonumber(tData[6])
			tDatatm.GameType =tonumber(tData[7])
			tDatatm.MinGold =tonumber(tData[8])
			tBase.Log("Gold Level:"..cjson.encode(tDatatm))
			return tDatatm
		end
	end
	return tData
end


function Configredis.Get_Game_ServerID_Cfg()
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==144   ")  
		return {}
	end
	local tData ={}
	local key = Configredis.m_game_serveridkey
	local strList = tBase.m_MyRedisData[1].redis:smembers(key)
	local DataList = {}

	local tConfig ={}
		
	for i =1, #strList do 
		local tData = tApi.Split(strList[i],",")
		local tDatatm ={}
		tDatatm.Id = tonumber(tData[1])
		tDatatm.nServerID =tonumber(tData[2])
		tDatatm.nGameServerType =tonumber(tData[3])
		tDatatm.nGoldLevel =tonumber(tData[4])
		if tDatatm.nGameServerType == 2  and  tDatatm.nGoldLevel > 0  then   --  金币房
			-- tBase.Log("  Get  GameServerID   Config  :"..cjson.encode(tDatatm))
			table.insert( tConfig,tDatatm )
		end
	end
	return tConfig
end 

--根据 金币房 level 随机分配服务器
function Configredis.Random_Get_ServerID(nLevel)
   tBase.Log(" nLevel：%d  随机分配服务器    ",nLevel )
   local  tConfig =	Configredis.Get_Game_ServerID_Cfg()
   if tConfig == nil then 
		tBase.Log(" Error_Info==145   ")  
   	  return  0
   end 	
   local arrConfig = {}
   for k,v in pairs(tConfig) do
	   tBase.Log("  筛选同等级的服务器  :"..cjson.encode(v))
   	  if nLevel == v.nGoldLevel then 
   	  	 table.insert(arrConfig, v)
   	  end 
   end
   if arrConfig == nil or #arrConfig == 0  then
   	  tBase.Log(" nLevel：%d ,   没有找到服务器 Error_Info==145  ",nLevel )
   	  return 0 
   end 
   -- if #arrConfig == 1 then 
   -- 	  tBase.Log(" nLevel：%d , 就一个服务器 不用随机分配 serverID: %d  ",nLevel,arrConfig.nServerID )
   -- 	  return arrConfig.nServerID
   -- end 

   local nCount = #arrConfig
   local nRandom  = math.random(1,nCount)
   tBase.Log("  随机分配服务器   nRandom: %d ,nCount: %d  ",nRandom,nCount)
   for k,v in pairs(arrConfig) do
   	   if  nRandom == k then 
   		   tBase.Log(" nLevel：%d , 随机分配服务器 serverID: %d  ",nLevel,v.nServerID)
   	   	   return v.nServerID
   	   end    	   	
   end
   return -1
end

--扩展，ygj add
function Configredis.GetGoldRoomListBy(nGameType,nLevel)
	tBase.Log("GetGoldRoomListBy..GetGoldRoomListBy:%d,nLevel:%d ",nGameType,nLevel)
	local tDatatm ={}
	tDatatm.Id = 1
	tDatatm.level =nLevel
	tDatatm.free = 10
	tDatatm.score =10
	tDatatm.mincapital =10
	tDatatm.pima =10
	tDatatm.GameType =nGameType
	tDatatm.MinGold =10				--玩家金币小于这个值不能进入
	tDatatm.Maxcapital =100000000  --//进入房间最高限额(玩家金币大于这个值不能进入)
	tBase.Log("Gold Level:"..cjson.encode(tDatatm))
	return tDatatm
end


--根据场次随机分配一个GameID给玩家
function Configredis.GetGoldRoomListBy_Rand(nLevel)
	tBase.Log("GetGoldRoomListBy_Rand nLevel:%d ",nLevel)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==1211   ")  
		return {}
	end

	local tData ={}
	local key = Configredis.m_gold_roomkey
	local strList = tBase.m_MyRedisData[1].redis:smembers(key)
	local DataList = {}
	for i =1, #strList do 
		local tDatatm ={}
		
		local tData = tApi.Split(strList[i],",")
		local m_level = tonumber(tData[2])
		if (m_level ==nLevel or nLevel ==0) then
			--1,6,1312,1500,15000,6,10000
			local tDatatm ={}
			tDatatm.Id = tonumber(tData[1])
			tDatatm.level =tonumber(tData[2])
			tDatatm.free = tonumber(tData[3])
			tDatatm.score =tonumber(tData[4])
			tDatatm.mincapital =tonumber(tData[5])
			tDatatm.pima =tonumber(tData[6])
			tDatatm.GameType =tonumber(tData[7])
			tDatatm.MinGold =tonumber(tData[8])		--玩家金币小于这个值不能进入
			tDatatm.Maxcapital =tonumber(tData[9])  --//进入房间最高限额(玩家金币大于这个值不能进入)
			tBase.Log("Gold Level:"..cjson.encode(tDatatm))
			return tDatatm
		end
	end
end


--得到金币房列表  --{Id=index,nServerID = serverid,level =level,score=score,mincapital=mincapital,pima=pima}
function Configredis.GetGoldRoomList()
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==146   ")  
		return {}
	end

	local key = Configredis.m_gold_roomkey
	local strList = tBase.m_MyRedisData[1].redis:smembers(key)
	local DataList = {}
	local DataListtm = {}
	for i =1, #strList do 
		-- tBase.Log("得到的金币房配置数据表 %s",strList[i])
		local tData = tApi.Split(strList[i],",")

		--1,6,1312,1500,15000,6
		local tDatatm ={}
		tDatatm.Id = tonumber(tData[1])
		--tDatatm.nServerID =tonumber(tData[3])
		tDatatm.level =tonumber(tData[2])
		tDatatm.free =tonumber(tData[3])
		tDatatm.score =tonumber(tData[4])
		tDatatm.mincapital =tonumber(tData[5])
		tDatatm.pima =tonumber(tData[6])
		tDatatm.GameType =tonumber(tData[7])
		tDatatm.MinGold =tonumber(tData[8])
		tDatatm.Maxcapital =tonumber(tData[9])
		table.insert(DataList,tDatatm)
		table.insert(DataListtm,tDatatm)
	end

	for i =1,#DataListtm do 
		local id = DataListtm[i].Id
		--tBase.Log("最终返回给前端的数据是: %d",id)
		DataList[id] =DataListtm[i]
	end
	
	return DataList
end

--获得金币房的底分
function Configredis.GetGoolRoomScore(level)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("  Error_Info==147  ")
		return -1
	end

	local tData =Configredis.GetGoldRoomData(level)
	tBase.Log("GetGoolRoomScore:"..tData.score)
	return tonumber(tData.score)
end

-- 获取金币房的底分通过游戏类型，等级获取
function Configredis.GetGoolRoomScoreBy(nGameType,nLevel)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("  Error_Info==148   ")
		return -1
	end

	local tData =Configredis.GetGoldRoomListBy(nGameType,nLevel)
	tBase.Log("GetGoolRoomScore:"..tData.score)
	return tonumber(tData.score)
end


------------------------------------------------------------------------------
--保存玩家的破产补助次数
function Configredis.SaveUserBroketTime(nUserID)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==149   ")  
		return 
	end

	local sDate = os.date("%Y-%m-%d");   --当天时间
	local Broke_Count = tonumber(Configredis.GetUserBroketTime(nUserID))+1 

    local tData = {}
    tData["nUserID"] = nUserID
    tData["Broke_Time"] = sDate
    tData["Broke_Count"] = Broke_Count
    tData["Broke_Second"] = os.time()

    tPubUserApi.UpdateUserData(tData) 

	return 
end

--获得玩家已领取破产补助的次数
function Configredis.GetUserBroketTime(nUserID)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==150   ")  
		return -1
	end

    local nCount =0
    local DateTime 
    local dtNow = os.date("%Y-%m-%d");   --当天时间
    local tData = tPubUserApi.GetUserInfo(nUserID)

    if (dtNow ==tData.Broke_Time) then   --当天时间相同就累计
    	nCount = tData.Broke_Count
    else
    	nCount =0
    end
	return nCount
end

--获得玩家上次领取的时间，以便作准却处理
function Configredis.GetUserBroketSecond(nUserID)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==151   ")  
		return -1
	end

	local nSecond0 = os.time()
    local tData = tPubUserApi.GetUserInfo(nUserID)

    
    if (tData.Broke_Second == nil) then
    	tData.Broke_Second = 0
    end

    local nSecond1 =tonumber(tData.Broke_Second) 
    if (nSecond1 ==0) then
    	nSecond1 = nSecond0
    end

    
    tBase.Log("破产补助冷却时间 :%s   当前的: %d",tData.Broke_Second,nSecond0)

    local nVal = nSecond0- nSecond1
	return nVal
end

--保存金币房玩家的分数
function Configredis.SaveGoldRoomAmount(nUserID,nScore)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("  Error_Info==152  ")
		return
	end

	local old_Amount = tonumber(Configredis.GetGoldRoomAmount(nUserID));
	local Amount = old_Amount + tonumber(nScore)

	local tData = {}
    tData["nUserID"] = nUserID
    tData["Amount_Time"] = os.date("%Y-%m-%d");   --当天时间
    tData["Amount_Values"] = Amount
    tPubUserApi.UpdateUserData(tData) 

	return 
end

--获取金币房玩家的分数(当天时间)
function Configredis.GetGoldRoomAmount(nUserID)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("	 Error_Info==153  ")
		return -1
	end

	local now = os.date("%Y-%m-%d");   --当天时间
	local tData = tPubUserApi.GetUserInfo(nUserID)

    local Amount =0
    if next(tData) ~= nil then
    	if (tData.Amount_Time ~= nil) then
			if (now == tData.Amount_Time) then
				Amount = tData.Amount_Values
			end
    	end
	else
		tBase.Log("机器人 取不到值   Error_Info==154 错了的 GetGoldRoomAmount"..nUserID.."  "..now.."  "..tData.Amount_Time)
    end

   return Amount
end


--金币房在线人数记录--增加
function Configredis.Add_GoldRoom_Online(GameID,Level)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("	Error_Info==155")
		return -1
	end

	local sKey = "gold_room_online_"..GameID..Level
	local nCount = Configredis.Get_GoldRoom_Online(GameID,Level)   --先获得在线的


	local tData = {}
	tData.count = nCount+1

	tBase.m_MyRedisData[1].redis:hmset(sKey, tData)
end

--获得当前金币房的在线人数
function Configredis.Get_GoldRoom_Online(GameID,Level)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("	Error_Info==156")
		return -1
	end

	local sKey = "gold_room_online_"..GameID..Level
	local tData = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	if (next(tData ) == nil) then
		-- tBase.Log(" Error_Info==157   ") 
		return 0
	end


	return tData.count
end

--金币房的在线人数减1
function Configredis.Sub_GoldRoom_Online(GameID,Level)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==158")
		return -1
	end

	local sKey = "gold_room_online_"..GameID..Level
	local nCount = Configredis.Get_GoldRoom_Online(GameID,Level)   --先获得在线的


	local tData = {}
	tData.count = nCount - 1
	if (tData.count <0) then
		tData.count = 0
	end

	tBase.m_MyRedisData[1].redis:hmset(sKey, tData)
end


--获得金币某个总类的在线人数
function Configredis.Sub_GoldRoom_Online_all(GameID)
	local nCount =0
	for i =0,5 do 
		 local nCount1 = Configredis.Get_GoldRoom_Online(GameID,i)
		 nCount = nCount +nCount1
	end
	return nCount
end

--
function Configredis.SetUserBrokeFlage(nUserId,nFlage)
    local tUserData = {}
    tUserData["nUserID"]     = nUserId
    tUserData["brokeflage"]     = nFlage

    tPubUserApi.UpdateUserData(tUserData)  
end

function Configredis.GetUserBrokeFlage(nUserId)
	local tUserData =  tPubUserApi.GetUserInfo(nUserId)
	if (tUserData ~= nil) then
		local nVal = tonumber(tUserData.brokeflage) or 0
		return nVal
	else
		tBase.Log("	Error_Info==159")
		return 0
	end
end

--设定配置
function Configredis.SetConfig(file,val)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("Error_Info==160")
		return false
	end

   local sKey = "config"   
   local tData = {}
   tData[file] = val

   local nResult =  -1
   nResult = tBase.m_MyRedisData[1].redis:hmset(sKey, tData)
   if nResult == 1 then 
   	  return  true
   end 
   return false 
end

--获得配置信息
function Configredis.GetConfig()
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("	Error_Info==161")
		return 
	end
	local sKey = "config"
	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return t 
end

--保存机器人池
function Configredis.SaveAndroidPool(GameID,Level)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==162")
		return 
	end
	local sKey1 = "Android_GameID"
	local sKey2 = "Android_Level"

	tBase.m_MyRedisData[1].redis:sadd(sKey1, GameID)
	tBase.m_MyRedisData[1].redis:sadd(sKey2, Level)
end


--获得集合数据
function Configredis.GetScaddList(key)
    if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==163")
        return nil
    end
    local strList = tBase.m_MyRedisData[1].redis:smembers(key)

    return strList
end


function Configredis.GetUserGameID(nUserId,nGameID,nLevel)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==164   ")  
		return -1
	end

	local nSecond0 = os.time()
    local tData = tPubUserApi.GetUserInfo(nUserId)

    if (tData ~= nil) then
    	nGameID = tData.nGameID
    	nLevel = tData.nLevel
    	return nGameID,nLevel
    end
	tBase.Log(" Error_Info==165   ")  
    return nil
end

return Configredis

