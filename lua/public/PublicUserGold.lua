
local tBase 	= require("base")
local cjson     = require("cjson")          -- json 
local mlogger = require("logger") -- 日志对象  
local tSrvInfo = require("ServerInfo")
local api =require("publicApi")

local PublicUserGold ={
	-- 资产类型： 1 个人资产,2俱乐部总资产
	arrAssetType ={
		[1] ="UserGoldInfo_",       -- 个人资产key
		[2] ="ClubSumAssetInfo_",   -- 俱乐部总资产key
	}
}
 
--浮点数判断
-- 是否小于
local function LessThan(a,b)
	return (a<b and math.abs(a-b)>1e-6)
 end
-- 是否大于
 local function GreaterThan(a,b)
	return (a>b and math.abs(a-b)>1e-6)
end
-- 是否小于等于
local function LessOrEqual(a,b)
	return (not GreaterThan(a,b))
end
-- 是否大于等于
local function GreaterOrEqual(a,b)
	return (not LessThan(a,b))
end
-- 是否等于
local function Equal(a,b)
	return (math.abs(a-b) <1e-6)
end

--[[
	Redis 使用单个 Lua 解释器去运行所有脚本，并且， Redis 也保证脚本会以原子性(atomic)的方式执行：当某个脚本正在运行的时候，不会有其他脚本或 Redis 命令被执行。
]]

--用户金币信息 (UserGold_???)
--nGold 			:当前金币
--nFreezeGoldSum	:冻结的金币总数
--nFreezeGold_Serv1 :Serv1冻结的金币数
--nFreezeGold_Serv2 :Serv2冻结的金币数

local function UserGoldInfoKey(nUserId,nAssetType)
	if not nAssetType then
		nAssetType = 1
	end
	local sKey = PublicUserGold.arrAssetType[nAssetType]
	return string.format("%s%d",sKey,nUserId),nAssetType
end
local function _GetGoldKey(nItemId)
	return string.format("nGold_%d",nItemId)
end	
local function FreezeGoldServField(nItemId,nServerId)
	local nServerId =nServerId or tSrvInfo.nServerId
	return string.format("nFreezeGold_Serv_%d_%d",nServerId,nItemId)
end
local function FreezeGoldSumKey(nItemId)
	return string.format("nFreezeGoldSum_%d",nItemId)
end
local function UsersHasGoldLock(nServerId)
	local nServerId =nServerId or tSrvInfo.nServerId
	return string.format("UsersHasGoldLock_%d",nServerId)
end

local function _GetItemId(sStr,nServerId)
	local sField = string.format("nFreezeGold_Serv_%d_",nServerId or tSrvInfo.nServerId)
	local sMatch =string.match(sStr,sField)
	if not sMatch then return  end
	local nItemId = string.gsub(sStr,sField,"")
	if nItemId and #nItemId > 0 and tonumber(nItemId) > 0 then
		return tonumber(nItemId)
	end
	return nil
end

local function GetRedis()
	return tBase.m_MyRedisData[2].redis
end

function PublicUserGold.Init(nUserId,nInitGold,nItemId,nAssetType)
	local tRedis =GetRedis()
	if  tRedis ==nil then
		return false,"Redis Error"
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nInitGold=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5])   
		if redis.call("exists",sKey) ==0 then 
			redis.call("hset",sKey,nGoldKey,nInitGold)
			return {0,"succee",tostring(nInitGold)}
		end
		if redis.call("hexists",sKey,nGoldKey) ==0 then 
			redis.call("hset",sKey,nGoldKey,nInitGold)
			return {0,"succee",tostring(nInitGold)}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,"sFreezeGoldSumKey",sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		if math.abs(nGold-nInitGold)<1e-6 then
			return {0,"succee1",tostring(nGold)}
		end
		if math.abs(nFreezeGoldSum)<1e-6 then
			redis.call("hset",sKey,nGoldKey,nInitGold)
			return {1,"waring",tostring(nInitGold)}
		end
		return {2,"Error",tostring(nGold)}
	]]

	local sKey = UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze =FreezeGoldServField(nItemId)
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nInitGold)
	tBase.Log("_Init %s  nInitGold_%f  nItemId_%d  rlt: %s  ",sKey,nInitGold,nItemId,cjson.encode(rlt))
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nCurGold =tonumber(rlt[3])
	return isSuccee,sErr,nCurGold
end


--加锁用户金币(锁住的金币只能由本服负责解锁与使用)
--参数:nUserId(用户id) ,nGoldToLock(加锁的金币数量,>=0) ,nServerId(nil时默认为本服)
--返回: true(成功), false(失败)
function PublicUserGold.Lock(nUserId,nGoldToLock,nItemId,nAssetType)
	if LessThan(nGoldToLock,0) then
		return false,"Pamameter Error"
	end
	if Equal(nGoldToLock,0) then
		return true
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local tRedis =GetRedis()
	if  tRedis ==nil then 
		return false,"Redis Error"
	end
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldToLock=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5])   
		if redis.call("exists",sKey) ==0 then 
			return {2,"sKeyNotExist"} 
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		local nGoldCanFreeze =nGold -nFreezeGoldSum
		if not (nGoldCanFreeze <nGoldToLock and math.abs(nGoldCanFreeze-nGoldToLock)>1e-6 ) then
			redis.call("hincrbyfloat",sKey,sFieldServFreeze,nGoldToLock)
			redis.call("hincrbyfloat",sKey,sFreezeGoldSumKey,nGoldToLock)
			return {0,"succee",tostring(nGold)}
		end
		return {1,"GoldNotEnought",tostring(nGold)}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType) 
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze =FreezeGoldServField(nItemId, nil)
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldToLock)  
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nCurGold =tonumber(rlt[3])
	if isSuccee then
		local sKeyOfSet =UsersHasGoldLock(nil)
		tRedis:sadd(sKeyOfSet,nUserId)
		local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
		tBase.Log("_LocKPrint %d Lock nUserId:%d nLockGold:%.2f nItemId: %d  sKey: %s ",dex,nUserId,nGoldToLock,nItemId,sKey)
	else		
		local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
		local sTip = cjson.encode(PublicUserGold.GetUserGoldInfo(nUserId,nItemId,nAssetType))	
		tBase.Log("_LocKFailPrint %d LockFail nUserId:%d nLockGold:%.2f sTip:%s nItemId:%d  sKey: %s ",dex,nUserId,nGoldToLock,sTip,nItemId,sKey)
	end
	return isSuccee,sErr,nCurGold
end

--解锁用户金币 (只能解锁被本服锁住的金币)
--参数:nUserId(用户id) ,nGoldToLock(解锁的金币数量,>=0) ,nServerId(nil时默认为本服)
--返回: true(成功), false(失败) isGame 游戏内有撤码 解锁不检测
function PublicUserGold.UnLock(nUserId,nGoldToUnLock,nItemId,nAssetType,isGame)
	if LessThan(nGoldToUnLock, 0) then
		return false,"Pamameter Error"
	end
	if Equal(nGoldToUnLock,0)  then
		return true
	end
	local tRedis =GetRedis()
	if  tRedis ==nil then 
		return false,"Redis Error"
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local isGameSrg = isGame and "1" or "0"
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldToUnLock,isGameSrg=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5]),ARGV[6]   
		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist"}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		if not (nFreezeGold_Serv <nGoldToUnLock and math.abs(nFreezeGold_Serv-nGoldToUnLock)>1e-6) then
			local sV_str = redis.call("hincrbyfloat", sKey, sFieldServFreeze, -nGoldToUnLock)
			local sumV_str = redis.call("hincrbyfloat", sKey, sFreezeGoldSumKey, -nGoldToUnLock)
			local sV = tonumber(sV_str) or 0
			local sumV = tonumber(sumV_str) or 0
			if sV < 0 then
				sV = 0
				redis.call("hset", sKey, sFieldServFreeze, 0)
			end
			if sumV < 0 then
				sumV = 0
				redis.call("hset", sKey, sFreezeGoldSumKey, 0)
			end
			return {0,"succee",sV}
		elseif isGameSrg == "1" then
			local sV_str = redis.call("hincrbyfloat", sKey, sFieldServFreeze, -nGoldToUnLock)
			local sumV_str = redis.call("hincrbyfloat", sKey, sFreezeGoldSumKey, -nGoldToUnLock)
			local sV = tonumber(sV_str) or 0
			local sumV = tonumber(sumV_str) or 0
			if sV < 0 then
				sV = 0
				redis.call("hset", sKey, sFieldServFreeze, 0)
			end
			if sumV < 0 then
				sumV = 0
				redis.call("hset", sKey, sFreezeGoldSumKey, 0)
			end
			return {0,"succee",sV}
		end
		return {1,"Gold Not Enought"}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze =FreezeGoldServField(nItemId, nil)
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldToUnLock,isGameSrg)
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nServFreezeNow =tonumber(rlt[3]) or 0
	if isSuccee and math.abs(nServFreezeNow)<1e-6 then
		local sKeyOfSet =UsersHasGoldLock(nil)
		tRedis:srem(sKeyOfSet,nUserId)

		local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
		tBase.Log("_UnLocKPrint  %d UnLock nUserId:%d nGoldToUnLock:%.2f nItemId: %d sKey: %s  ",dex,nUserId,nGoldToUnLock,nItemId,sKey)
	else
		local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
		local sTip = cjson.encode(PublicUserGold.GetUserGoldInfo(nUserId,nItemId,nAssetType))
		tBase.Log("_UnLocKFailPrint %d UnLockFail nUserId:%d nGoldToUnLock:%.2f sTip:%s nItemId: %d sKey: %s sErr_%s ",dex,nUserId,nGoldToUnLock,sTip,nItemId,sKey,sErr)
	end
	return isSuccee,sErr
end

--解锁同时扣减用户金币
--参数:nUserId(用户id) ,nGoldToUnLockAndMinus(解锁与扣减的金币数量,>=0) ,nServerId(nil时默认为本服)
--返回: true(成功), false(失败)
function PublicUserGold.UnLockAndMinus(nUserId,nGoldToUnLockAndMinus,nItemId,nAssetType)
	if LessThan(nGoldToUnLockAndMinus,0) then
		return false,"Pamameter Error"
	end
	if Equal(nGoldToUnLockAndMinus,0) then
		return true
	end
	local tRedis =GetRedis()
	if  tRedis ==nil then
		return false,"Redis Error"
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldToUnLockAndMinus=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5])   
		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist"}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		if not (nFreezeGold_Serv <nGoldToUnLockAndMinus and math.abs(nFreezeGold_Serv-nGoldToUnLockAndMinus)>1e-6) then
			local sV =redis.call("hincrbyfloat",sKey,sFieldServFreeze,-nGoldToUnLockAndMinus)
			redis.call("hincrbyfloat",sKey,sFreezeGoldSumKey,-nGoldToUnLockAndMinus)
			local nGoldAfterChange =redis.call("hincrbyfloat",sKey,nGoldKey,-nGoldToUnLockAndMinus)
			return {0,"succee",nGoldAfterChange,sV}
		end
		return {1,"Gold Not Enought",tostring(nGold)}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze =FreezeGoldServField(nItemId,nil) 
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldToUnLockAndMinus)   
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nGoldAfterChange =tonumber(rlt[3])
	local nServFreezeNow =tonumber(rlt[4]) or 0
	if isSuccee and math.abs(nServFreezeNow)<1e-6 then
		local sKeyOfSet =UsersHasGoldLock(nil)
		tRedis:srem(sKeyOfSet,nUserId)
	end
	return isSuccee,sErr,nGoldAfterChange
end

--解锁用户所有金币 (只能解锁被本服锁住的金币)
--参数:nUserId(用户id) ,nServerId(nil时默认为本服)
--返回: true(成功), false(失败)
function PublicUserGold.UnLockAll(nUserId,nAssetType,nServerId)
	local tRedis =GetRedis()
	if  tRedis ==nil then 
		return false,"Redis Error" 
	end 
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local scrip =[[ 
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze=ARGV[1],ARGV[2],ARGV[3],ARGV[4]
		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist"}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		if nFreezeGold_Serv>0 and math.abs(nFreezeGold_Serv)>1e-6 then
			redis.call("hincrbyfloat",sKey,sFieldServFreeze,-nFreezeGold_Serv)
			redis.call("hincrbyfloat",sKey,sFreezeGoldSumKey,-nFreezeGold_Serv)
		end
		return {0,"succee"}
	]]
	nServerId = nServerId or tSrvInfo.nServerId
	local sKey = UserGoldInfoKey(nUserId,nAssetType)
	local tUserInfoGold = tRedis:hgetall(sKey)
	local arrItemId = {}
	for key, val in pairs(tUserInfoGold) do 
		local nItemId = _GetItemId(key,nServerId)   	  		
		if nItemId and tonumber(val) > 0 then    
			table.insert(arrItemId,nItemId)
			tBase.Log("_UnLockAll nUserId: %d  %s=%s  nItemId: %d ",nUserId,key,val,nItemId)  
		end  
	end  
	local isSuccee = true 
	local sErr = "succee" 
	if #arrItemId > 0 then 
		for _, nItemId in ipairs(arrItemId) do
			local nGoldKey = _GetGoldKey(nItemId)
			local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
			local sFieldServFreeze =FreezeGoldServField(nItemId,nServerId)
			local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
			isSuccee =(rlt[1]==0)	
			sErr =rlt[2] 
			if not isSuccee then  
				tBase.Log("_UnLockAll  ErrorMsg 解锁失败: nUserId: %d  nItemId: %d  rlt: %s  ",nUserId,nItemId,cjson.encode(rlt)) 
			else 
				tBase.Log("_UnLockAll  解锁成功: nUserId: %d    nItemId: %d  rlt: %s  ",nUserId,nItemId,cjson.encode(rlt))  
			end 		
		end
	end 	
	local sField = string.format("nFreezeGold_Serv_%d_",nServerId)
	tBase.Log("_UnLockAll  开服解锁本服金币： nUserId：%d  sField：%s  arrItemId: %s  ",nUserId,sField,cjson.encode(arrItemId))	
	return isSuccee,sErr
end

--锁住玩家剩下能锁住的金币(前提条件是该金币不少于nNotLessThan); 用于玩家上庄时
--返回:本次锁成功的金币数
function PublicUserGold.LockAllWhen(nUserId,nNotLessThan,nItemId,nAssetType)
	local tRedis =GetRedis()
	if  tRedis ==nil then 
		return false,"Redis Error"
	end
	if LessThan(nNotLessThan,0)  then
		return false,"Pamameter Error"
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nNotLessThan=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5])    
		if redis.call("exists",sKey) ==0 then 
			return {2,"sKeyNotExist",0} 
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		local nGoldCanUse =nGold -nFreezeGoldSum
		if not (nGoldCanUse <nNotLessThan and math.abs(nGoldCanUse-nNotLessThan)>1e-6) then
			redis.call("hincrbyfloat",sKey,sFieldServFreeze,nGoldCanUse)
			redis.call("hincrbyfloat",sKey,sFreezeGoldSumKey,nGoldCanUse)
			return {0,"succee",tostring(nGoldCanUse)}
		end
		return {1,"GoldNotEnought",0}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze = FreezeGoldServField(nItemId,nil) 
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nNotLessThan)  
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nGoldLock =tonumber(rlt[3])
	if isSuccee and math.abs(nGoldLock)>1e-6 then
		local sKeyOfSet =UsersHasGoldLock(nil)
		tRedis:sadd(sKeyOfSet,nUserId)
	end
	return isSuccee,sErr,nGoldLock
end

--结算且重新锁定玩家金币值为(nLockGold+nChange);	用于庄家结算
--参数:nLockGold(当前玩家正在使用的被锁金币),nChange(输赢值)
--返回:true(成功),false(失败)
function PublicUserGold.ChangeAndReLock(nUserId,nLockGold,nChange,nItemId,nAssetType)
	local tRedis =GetRedis()
	if  tRedis ==nil then
		return false,"Redis Error"
	end
	if LessThan(nLockGold,0)  then
		return false,"Pamameter Error"
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error"
	end
	local scrip1 =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldChange,nLockGold=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5]),tonumber(ARGV[6]) 
 		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist",-1}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		local nGoldCanUse =math.min(nLockGold,nFreezeGold_Serv)
		if (nGoldChange +nGoldCanUse) <0 and math.abs(nGoldChange +nGoldCanUse)>1e-6 then
			return {3,"BeyondLockGold",tostring(nGold)}
		end
		local nGoldAfterChange =redis.call("hincrbyfloat",sKey,nGoldKey,nGoldChange)
		local sV =redis.call("hincrbyfloat",sKey,sFieldServFreeze,nGoldChange)
		redis.call("hincrbyfloat",sKey,sFreezeGoldSumKey,nGoldChange)
		return {0,"succee",nGoldAfterChange,sV}
	]]
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldChange,nLockGold=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5]),tonumber(ARGV[6]) 
 		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist",-1}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		local nGoldCanUse = nLockGold
		if (nGoldChange +nGoldCanUse) <0 and math.abs(nGoldChange +nGoldCanUse)>1e-6 then
			return {3,"BeyondLockGold",tostring(nGold)}
		end
		local nGoldAfterChange =redis.call("hincrbyfloat",sKey,nGoldKey,nGoldChange)
		local sV =redis.call("hincrbyfloat",sKey,sFieldServFreeze,nGoldChange)
		redis.call("hincrbyfloat",sKey,sFreezeGoldSumKey,nGoldChange)
		return {0,"succee",nGoldAfterChange,sV}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze = FreezeGoldServField(nItemId,nil)
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nChange,nLockGold)
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nGoldAfterChange =tonumber(rlt[3])
	local nServFreezeNow =tonumber(rlt[4]) or 0
	if isSuccee and math.abs(nServFreezeNow)<1e-6 then
		local sKeyOfSet =UsersHasGoldLock(nil)
		tRedis:srem(sKeyOfSet,nUserId)
	end
	return isSuccee,sErr,nGoldAfterChange
end

--对用户非加锁金币进行增减操作
--参数:nUserId(用户id) ,nGoldChange(金币变化值) ,nServerId(nil时默认为本服)
--返回: true(成功), false(失败)
function PublicUserGold.Change(nUserId,nGoldChange,nItemId,nAssetType)
	local tRedis =GetRedis()
	if tRedis ==nil then
		return false,"Redis Error",-1
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error",-1
	end
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldChange=ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5]) 
		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist: "..sKey,-1}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		local nCanUse =nGold -nFreezeGoldSum
		if (nCanUse +nGoldChange)< 0 and math.abs(nCanUse +nGoldChange)>1e-6 then
			return {1,"GoldNotEnought",tostring(nGold)}
		end
		local nGoldAfterChange =redis.call("hincrbyfloat",sKey,nGoldKey,nGoldChange)
		return {0,"succee",nGoldAfterChange}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze = FreezeGoldServField(nItemId,nil)
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldChange)
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nGoldAfterChange =tonumber(rlt[3])
	return isSuccee,sErr,nGoldAfterChange
end


-- 有锁定金币的转账
function PublicUserGold.ChangeWithFreeze(nUserId,nGoldChange,nFreeze, nItemId,nAssetType)
	local tRedis =GetRedis()
	nFreeze = tonumber(nFreeze) or 0
	if tRedis ==nil then
		return false,"Redis Error",-1
	end
	if not nUserId or nUserId <= 0 then
		return false,"Pamameter Error",-1
	end
	local scrip =[[
		local sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldChange,extraFreeze =ARGV[1],ARGV[2],ARGV[3],ARGV[4],tonumber(ARGV[5]),tonumber(ARGV[6])
		if redis.call("exists",sKey) ==0 then
			return {2,"sKeyNotExist: "..sKey,-1}
		end
		local arrVal =redis.call("hmget",sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze)
		local nGold =tonumber(arrVal[1]) or 0
		local nFreezeGoldSum =tonumber(arrVal[2]) or 0
		local nFreezeGold_Serv =tonumber(arrVal[3]) or 0
		local nCanUse =nGold - nFreezeGoldSum
		if (nCanUse +nGoldChange-extraFreeze)< -1e-6 then
			return {1,"GoldNotEnought",tostring(nGold)}
		end
		local nGoldAfterChange =redis.call("hincrbyfloat",sKey,nGoldKey,nGoldChange)
		return {0,"succee",nGoldAfterChange}
	]]
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sFieldServFreeze = FreezeGoldServField(nItemId,nil)
	local rlt =tRedis:eval(scrip,0,sKey,nGoldKey,sFreezeGoldSumKey,sFieldServFreeze,nGoldChange,nFreeze)
	local isSuccee =(rlt[1]==0)
	local sErr =rlt[2]
	local nGoldAfterChange =tonumber(rlt[3])
	return isSuccee,sErr,nGoldAfterChange
end

function PublicUserGold.GetUserGoldInfo(nUserId,nItemId,nAssetType)
	local tRedis =GetRedis()
	if tRedis ==nil then
		return {}
	end
	if not nUserId or nUserId <= 0 then
		return {}
	end
	local sKey =UserGoldInfoKey(nUserId,nAssetType)
	local nGoldKey = _GetGoldKey(nItemId)
	local sFreezeGoldSumKey = FreezeGoldSumKey(nItemId)
	local sField = FreezeGoldServField(nItemId,nil)
	local arrVal =tRedis:hmget(sKey,nGoldKey,sFreezeGoldSumKey,sField)
	local tem={}
	tem.nGold =tonumber(arrVal[1]) or 0
	tem.nFreezeGoldSum =tonumber(arrVal[2]) or 0
	tem[sField] =tonumber(arrVal[3]) or 0
	return tem
end

function PublicUserGold.SetRetainGold(nUserId,nRetain)
	local tRedis =GetRedis()
	if tRedis ==nil then 
		return
	end
	if not nUserId or nUserId <= 0 then
		return
	end
	local sKey =UserGoldInfoKey(nUserId)
	tRedis:hset(sKey,"RetainGold",nRetain)
end

function PublicUserGold.GetRetainGold(nUserId)
	local tRedis =GetRedis()
	if tRedis ==nil then
		return 0,0,0,false
	end
	if not nUserId or nUserId <= 0 then
		return 0,0,0,false
	end
	local sKey =UserGoldInfoKey(nUserId)
	if not tRedis:exists(sKey) then
		return 0,0,0,false
	end
	local sRetain =tRedis:hget(sKey,"RetainGold")
	local nRetain=tonumber(sRetain) or 0
	local tInfo =PublicUserGold.GetUserGoldInfo(nUserId,1)
	return nRetain,(tInfo.nGold -tInfo.nFreezeGoldSum),tInfo.nGold,true
end

-- 玩家下线时清理锁定金币
function PublicUserGold.OnPlayerLogout(nUserId, nAssetType)
    if not nUserId or nUserId <= 0 then
        return false, "Invalid user id"
    end
    local tRedis = GetRedis()
    if tRedis == nil then
        return false, "Redis Error"
    end
    -- 获取当前服务器ID
    local nServerId = tSrvInfo.nServerId
    -- 清理本服锁定的金币
    local isSuccess, sErr = PublicUserGold.UnLockAll(nUserId, nAssetType, nServerId)
    if isSuccess then
        tBase.Log("_OnPlayerLogout 玩家下线清理锁定金币成功: nUserId:%d, nServerId:%d", nUserId, nServerId)
    else
        tBase.Log("_OnPlayerLogout 玩家下线清理锁定金币失败: nUserId:%d, nServerId:%d, sErr:%s", 
                 nUserId, nServerId, sErr or "unknown error")
    end
    return isSuccess, sErr
end

-- 批量清理多个玩家的锁定金币（用于服务器维护等场景）
function PublicUserGold.BatchUnlockOnMaintenance(arrUserIds, nAssetType)
    if not arrUserIds or type(arrUserIds) ~= "table" then
        return false, "Invalid user ids"
    end
    local tRedis = GetRedis()
    if tRedis == nil then
        return false, "Redis Error"
    end
    local nSuccessCount = 0
    local nFailCount = 0
    local nServerId = tSrvInfo.nServerId
    for _, nUserId in ipairs(arrUserIds) do
        if nUserId and nUserId > 0 then
            local isSuccess, sErr = PublicUserGold.UnLockAll(nUserId, nAssetType, nServerId)
            if isSuccess then
                nSuccessCount = nSuccessCount + 1
            else
                nFailCount = nFailCount + 1
                tBase.Log("_BatchUnlockOnMaintenance 批量清理失败: nUserId:%d, sErr:%s", nUserId, sErr or "unknown error")
            end
        end
    end
    tBase.Log("_BatchUnlockOnMaintenance 批量清理完成: 成功:%d, 失败:%d, 总计:%d",nSuccessCount, nFailCount, #arrUserIds)
    return nSuccessCount, nFailCount
end

-- 清理用户所有服务器的冻结金币（完全清理）
-- 参数: nUserId(用户id), nAssetType(资产类型)
-- 返回: true(成功), false(失败), 清理的服务器数量
function PublicUserGold.UnLockAllServersGold(nUserId, nAssetType)
    local tRedis = GetRedis()
    if tRedis == nil then
        return false, "Redis Error", 0
    end
	if not nUserId or nUserId <= 0 then
		return false, "Invalid user id", 0
	end
    local sKey = UserGoldInfoKey(nUserId, nAssetType)
    -- 获取哈希表的所有字段和值
    local tUserInfoGold = tRedis:hgetall(sKey)
    if not tUserInfoGold or type(tUserInfoGold) ~= "table" then
        return true, "No data to clean", 0
    end
    local arrFreezeFields = {}  -- 存储所有需要清理的冻结字段
    local arrItemIds = {}       -- 存储涉及的道具ID
    local cleanedServers = {}   -- 存储已清理的服务器ID
    -- 找出所有 nFreezeGold_Serv_ 开头的字段
    for field, value in pairs(tUserInfoGold) do
        if type(field) == "string" and string.find(field, "^nFreezeGold_Serv_") then
            -- 解析服务器ID和道具ID
            local nServerId, nItemId = PublicUserGold.ParseFreezeField(field)
            if nServerId and nItemId then
                table.insert(arrFreezeFields, {
                    field = field,
                    server_id = nServerId,
                    item_id = nItemId,
                    value = tonumber(value) or 0
                })
                -- 记录服务器ID
                if not cleanedServers[nServerId] then
                    cleanedServers[nServerId] = true
                end
                -- 记录道具ID
                if not arrItemIds[nItemId] then
                    arrItemIds[nItemId] = true
                end
            end
        end
    end
    if #arrFreezeFields == 0 then
        return true, "No freeze fields found", 0
    end
    -- 构建Lua脚本一次性清理所有冻结字段
    local script = [[
        local sKey = KEYS[1]
        -- 获取所有冻结字段的当前值
        local freezeFields = {}
        for i = 2, #ARGV do
            freezeFields[i-1] = ARGV[i]
        end
        -- 批量获取所有冻结字段的值
        local currentValues = redis.call("HMGET", sKey, unpack(freezeFields))
        -- 清理冻结字段并更新对应的冻结总和
        local totalCleaned = 0
        local cleanedCount = 0
        for i, field in ipairs(freezeFields) do
            local currentValue = tonumber(currentValues[i]) or 0
            if currentValue > 0 then
                -- 解析道具ID从字段名
                local itemId = string.match(field, "nFreezeGold_Serv_%d+_(%d+)$")
                if itemId then
                    -- 清零当前服务器的冻结值
                    redis.call("HSET", sKey, field, 0)
                    
                    -- 更新对应的冻结总和字段
                    local sumField = "nFreezeGoldSum_" .. itemId
                    local currentSum = tonumber(redis.call("HGET", sKey, sumField)) or 0
                    local newSum = math.max(0, currentSum - currentValue)
                    redis.call("HSET", sKey, sumField, newSum)
                    
                    totalCleaned = totalCleaned + currentValue
                    cleanedCount = cleanedCount + 1
                end
            end
        end
        
        return {cleanedCount, totalCleaned}
    ]]
    -- 准备参数
    local args = {sKey}
    for _, freezeInfo in ipairs(arrFreezeFields) do
        table.insert(args, freezeInfo.field)
    end
    -- 执行清理
    local rlt = tRedis:eval(script, 1, unpack(args))
    local cleanedCount = rlt[1] or 0
    local totalCleaned = rlt[2] or 0
    -- 从用户锁定集合中移除
    local serverIds = {}
    for serverId, _ in pairs(cleanedServers) do
        table.insert(serverIds, serverId)
        local sKeyOfSet = UsersHasGoldLock(serverId)
        tRedis:srem(sKeyOfSet, nUserId)
    end
	tRedis:del(sKey)
    -- 记录日志
    tBase.Log("_UnLockAllServers 完全清理: nUserId:%d, 清理字段:%d, 总金额:%.2f, 涉及服务器:%s, 涉及道具:%s",
             nUserId, cleanedCount, totalCleaned, cjson.encode(serverIds), cjson.encode(PublicUserGold.GetTableKeys(arrItemIds)))
    return true, "success", #serverIds
end

-- 清理用户所有服务器的冻结金币（完全清理）
function PublicUserGold.UnLockUserGold(nUserId, nAssetType)
    local tRedis = GetRedis()
    if tRedis == nil then
        return false, "Redis Error", 0
    end
	if not nUserId or nUserId <= 0 then
		return false, "Invalid user id", 0
	end
    local sKey = UserGoldInfoKey(nUserId, nAssetType)
    -- 获取哈希表的所有字段和值
    local tUserInfoGold = tRedis:hgetall(sKey)
    if not tUserInfoGold or type(tUserInfoGold) ~= "table" then
        return true, "No data to clean", 0
    end
    local arrItemIds = {}       -- 存储涉及的道具ID
    local cleanedServers = {}   -- 存储已清理的服务器ID
    -- 找出所有 nFreezeGold_Serv_ 开头的字段
    for field, value in pairs(tUserInfoGold) do
        if type(field) == "string" and string.find(field, "^nFreezeGold_Serv_") then
            -- 解析服务器ID和道具ID
            local nServerId, nItemId = PublicUserGold.ParseFreezeField(field)
            if nServerId and nItemId then
                -- 记录服务器ID
                if not cleanedServers[nServerId] then
                    cleanedServers[nServerId] = true
                end
                -- 记录道具ID
                if not arrItemIds[nItemId] then
                    arrItemIds[nItemId] = true
                end
            end
        end
    end
    -- 从用户锁定集合中移除
    local serverIds = {}
    for serverId, _ in pairs(cleanedServers) do
        table.insert(serverIds, serverId)
        local sKeyOfSet = UsersHasGoldLock(serverId)
        tRedis:srem(sKeyOfSet, nUserId)
    end
	tRedis:del(sKey)
    -- 记录日志
    tBase.Log("_UnLockAllServers 完全清理: nUserId:%d, 涉及服务器:%s, 涉及道具:%s",
             nUserId, cjson.encode(serverIds), cjson.encode(PublicUserGold.GetTableKeys(arrItemIds)))
    return true, "success", #serverIds
end

-- 解析冻结字段，提取服务器ID和道具ID
function PublicUserGold.ParseFreezeField(field)
    if type(field) ~= "string" then
        return nil, nil
    end
    -- 匹配格式: nFreezeGold_Serv_服务器ID_道具ID
    local serverId, itemId = string.match(field, "nFreezeGold_Serv_(%d+)_(%d+)$")
    if serverId and itemId then
        return tonumber(serverId), tonumber(itemId)
    end
    return nil, nil
end

-- 获取表的键列表
function PublicUserGold.GetTableKeys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

-- 安全清理函数（带重试机制）
function PublicUserGold.SafeUnLockAllServers(nUserId, nAssetType, nMaxRetry)
    nMaxRetry = nMaxRetry or 3
    for i = 1, nMaxRetry do
        local isSuccess, sErr, nServerCount = PublicUserGold.UnLockAllServersGold(nUserId, nAssetType)
        if isSuccess then
            return isSuccess, sErr, nServerCount
        end
        if i < nMaxRetry then
            tBase.Log("_SafeUnLockAllServers 清理失败，重试 %d/%d: nUserId:%d, error:%s", i, nMaxRetry, nUserId, sErr)
            -- 短暂延迟后重试
            os.execute("sleep 0.1")  -- 100ms 延迟
        end
    end
    return false, "Max retry exceeded", 0
end


-- 开服 解锁金币 
function PublicUserGold.UnLockUsersGold()
	local tRedis =GetRedis()
	if tRedis ==nil then
		return -1
	end
	local sKeyOfSet = UsersHasGoldLock()
	local nCntUnLock =0
	for i=1,1000000 do
		local nUserId = tonumber(tRedis:spop(sKeyOfSet))
		if nUserId==nil then
			break
		end
		local nAssetType = 1
		PublicUserGold.UnLockAll(nUserId,nAssetType)
		nCntUnLock=nCntUnLock+1
	end
	return nCntUnLock
end

return PublicUserGold