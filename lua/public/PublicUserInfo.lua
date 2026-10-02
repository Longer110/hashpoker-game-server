--[[
    用户信息：   全服共用的用户信息
]]
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
package.path = "../lua/Lobby/Config/?.lua;./lua/Lobby/Config/?.lua;" .. package.path
package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path
package.path = "../lua/Control/?.lua;./lua/Control/?.lua;" .. package.path 

local rdf = require("redisdefine")
local tBase 	= require("base")
local tname      = require("typename")       -- 类弄定义接口
local cjson     = require("cjson")          -- json (空对象编码成空对象)
local json     = require("json")          -- json (空对象编码成空数组)

local api       = require("publicApi")    -- 共用功能接口
local ProtoMgr  = require("ProtoManager") -- 协议管理对象 
local tPubHelper = require("PubHelper")
local mlogger = require("logger") 	     -- 日志对象   
local tSrvInfo = require("ServerInfo")
local tSetingConfig = require("SetingConfig")
local PublicRedis =   require("PublicRedis")
local tPublicUserGold = require("PublicUserGold")
local ctlDefine = require("ControlDefine")
require("GLock") 

PublicUserInfo = {

	tInfoAnItem = {},  -- 机器人数据

	tAnUserIdRange = {
		[12] = {nMin=12000000, nMax=12999999},
		[15] = {nMin=15000000, nMax=15999999},
		[17] = {nMin=17000000, nMax=17999999},
		[22] = {nMin=22000000, nMax=22999999},
		[24] = {nMin=24000000, nMax=24999999},
		[27] = {nMin=27000000, nMax=27999999},
		[33] = {nMin=33000000, nMax=33999999}
	},

	_arrIsReplyOka = {}, 
	tOnlinePeople = {},
}


-- 异常输出
function tpLog(e)
    local kl = base.GetKernel()
    local km = km_FD55292F51334A64AC61470D796F8D43.new(kl)
    km:Log(e)
    km:Log(debug.traceback())
    return e
end

-- 清除控牌的redis的key
function PublicUserInfo.DelRedisControlUser(nUserID)
    local sKey ="GameControlUser"
    local sMember =string.format("%d",nUserID)

	local nRes = base.m_MyRedisData[1].redis:hdel(sKey, sMember)
	
	base.Log("DelRedisControlUser, %s, %s, %d", sKey, sMember, (nRes == 1 and 1 or 0))
end

-- 清除控牌的redis的key
function PublicUserInfo.DelRedisControlRoom(nShopID, nGameID, nRoomID, nUserID)
    local sKey ="GameControl"
    local sMember =string.format("%d_%d_%d",nGameID,nRoomID,nUserID)
	local nRes = base.m_MyRedisData[1].redis:hdel(sKey, sMember)
	base.Log("DelRedisControlRoom, %s, %s, %d", sKey, sMember, (nRes == 1 and 1 or 0))
end
 
-----------------------------------------合集机器人用户数据--------------------------
--合集是否是机器人判断
function PublicUserInfo.IsComAndroid(tData)
	local isAndroid = false
	local _checkHit = function(nUserId)
		local n = math.floor(nUserId / 1000000) --nUserId // 1000000
		if PublicUserInfo.tAnUserIdRange[n] then
			return true
		end
		return false
	end
	if type(tData) == "number" then
		isAndroid = _checkHit(tData)
	elseif type(tData) == "table" then
		isAndroid = _checkHit(tData.nUserID)
	end
	return isAndroid
end 

--合集机器人添加用户数据
function PublicUserInfo.AddComAndroidUserInfo(tAnItem)
	local tUserBasic = {}
    tUserBasic["nUserID"] = tAnItem.nUserId 
    tUserBasic["sClientID"] = "" 
    tUserBasic["sNickName"] = tAnItem.sNickName
    tUserBasic["nSex"] = tAnItem.nSex 
    tUserBasic["sFaceID"] = tAnItem.sHeadUrl
    tUserBasic["sPhone"] = "119"
    tUserBasic["sChannel"] = "gz"
    tUserBasic["nShopID"] = "663"
    tUserBasic["nGrpId"] = tAnItem.nGrpId
    tUserBasic["isAndroid"] = 1
    tUserBasic["nGold"] = tAnItem.nGold 
	tUserBasic["nExp"] = 0
	tUserBasic["nDiamonds"] = 0
	tUserBasic["sShopAcc"] = tAnItem.sShopAcc
	tUserBasic["nLanguageId"] = tAnItem.nLanguageId
	tUserBasic["nServerId"] = tAnItem.nServerId
	tUserBasic["nVip"] = tAnItem.nVip or 0
	PublicUserInfo.tInfoAnItem[tAnItem.nUserId] = tUserBasic
end

--更新合集机器人用户数据
function PublicUserInfo.UpdateComAndroidUserInfo(tData)
	local tAnItem = PublicUserInfo.tInfoAnItem[tData.nUserID]
	if not tAnItem then return end

	for k, v in pairs(tData) do
		tAnItem[k] = v
	end
end

--更改合集机器人金币
function PublicUserInfo.ChangeComAndroidGold(tData)
	local tAnItem = PublicUserInfo.tInfoAnItem[tData.nUserID]
	if not tAnItem then return false end

	if tData.nItemID == 1 then
		local nOldGold = tAnItem.nGold
		tAnItem.nGold = tAnItem.nGold + tData.nDel
		if tAnItem.nGold<0 and math.abs(tAnItem.nGold)>=1e-6 then
			tAnItem.nGold = 0
			tBase.Log("修改机器人的财富错误UserId:%d 当前%.3f Change:%.3f", tData.nUserID, nOldGold, tData.nDel)
		end
	end
end

--合集机器人删除用户数据
function PublicUserInfo.DelComAndroidUserInfo(nUserId)
	tBase.Log("删除机器人de财富 UserId:%d", nUserId)
	PublicUserInfo.tInfoAnItem[nUserId] = nil
end

--合集返回机器人用户数据
function PublicUserInfo.GetComAndroidUserInfo(nUserId)
	--mlogger:debug(string.format("机器人de财富 UserId:%d Gold:%.3f", nUserId, PublicUserInfo.tInfoAnItem[nUserId].nGold))
	return PublicUserInfo.tInfoAnItem[nUserId]
end

-- 获取机器人金币
function PublicUserInfo.GetComAndroidUserGold(nUserId)
	--mlogger:debug(string.format("机器人de财富 UserId:%d Gold:%.3f", nUserId, PublicUserInfo.tInfoAnItem[nUserId].nGold))
	if PublicUserInfo.tInfoAnItem[nUserId] then
		return PublicUserInfo.tInfoAnItem[nUserId].nGold
	end
	tBase.Log("Error,AndroidUser Not In Cache,nUserId:%d",nUserId)
	return 0
end

--直接设置机器人金币
function PublicUserInfo.SetComAndroidGold(nUserId,nGold)
	if PublicUserInfo.tInfoAnItem[nUserId] then
		PublicUserInfo.tInfoAnItem[nUserId].nGold = nGold
		-- tBase.Log("设置机器人金币UserId:%d nGold:%.3f", nUserId, nGold)
		if nGold<0 and math.abs(nGold)>=1e-6 then
			PublicUserInfo.tInfoAnItem[nUserId].nGold = 0
			-- mlogger:error(string.format("设置机器人金币错误UserId:%d nGold:%.3f",nUserId, nGold))
		end
	end
end

---------------------- 设置或添加用户信息-----------------------
function PublicUserInfo.CacheExperienceCoin(nGameId, nUserId, nCoin)
	if PublicUserInfo.IsComAndroid(nUserId) then
		return
	end

	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local sK = "nExpCoin"..nGameId
	local tData = {}
	tData[sK] = nCoin
	tBase.m_MyRedisData[1].redis:hmset(sKey, tData)
	tBase.Log("保存用户体验场金币 UserId:%d Coin:%d", nUserId, tData[sK])
end

function PublicUserInfo._optBROnlinePeople(nGameId,tGroup,cOption,nCurPeople,nGroupId)
	if nCurPeople == nil then nCurPeople = 0 end
	if nGroupId == nil then nGroupId = 0 end
	local Rds = tBase.m_MyRedisData[1].redis
	local sKey 	=string.format("GmOnlinePeople_GameId_%d:GroupId_%d",nGameId,nGroupId)
	local gline = Rds:get(sKey)
	if cOption=="set" then
		for k,v in pairs(tGroup) do 
			tBase.LogT("_optBROnlinePeople k,v", k, tGroup)
			sKey =string.format("GmOnlinePeople_GameId_%d:GroupId_%d",nGameId,k)
			Rds:set(sKey,v) 
		end
		return true
	elseif cOption=="get" then 
		if not gline or gline=="0" or gline=="" then gline=0 end
		return gline
	elseif cOption=="updata" then
		local n = (nCurPeople+tonumber(gline) )
		Rds:set(sKey,n)
		return n
	end 
end

function PublicUserInfo.GetExperienceCoin(nGameId, nUserId)
	if PublicUserInfo.IsComAndroid(nUserId) then
		return
	end

	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId) 
	local tTreasure = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	local sK = "nExpCoin"..nGameId
	if tTreasure and tTreasure[sK] then
		tBase.Log("取出用户体验场金币 UserId:%d Coin:%d", nUserId, tTreasure[sK])
		return tonumber(tTreasure[sK])
	end

	return
end

function PublicUserInfo.ClearExperienceCoin(nGameId, nUserId)
	if PublicUserInfo.IsComAndroid(nUserId) then
		return
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId) 
	local sK = "nExpCoin"
	if nGameId == -1 then
		local arr = tBase.m_MyRedisData[1].redis:hgetall(sKey)
		local isFind
		for k, _ in pairs(arr) do
			isFind = string.find(k, sK)
			if isFind then
				tBase.m_MyRedisData[1].redis:hdel(sKey, k)
			end
		end
	else
		sK = sK..nGameId
		tBase.m_MyRedisData[1].redis:hdel(sKey, sK)	
	end
	
	tBase.Log("删除用户体验场金币:"..nUserId)
end

function PublicUserInfo.SetOnlinePeopleNum(nGameId,nPeople)
end

-- 设置用户信息
function PublicUserInfo.SetUserInfo(tData)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==102   ")  
		return
	end
	tData.nUserID = api.Double2Int(tData.nUserID)
	local sKey = "PublicUserInfo_"..tData.nUserID
	local t = {}
	t["nUserID"] = tData.nUserID
	t["nClientId"] = tData.nClientId
	t["sGateKey"] = tData.sGateKey
	t["sIp"] = tData.sIp
	t["nSocketId"] = tData.nSocketId
	t["sRealIp"] = tData.sRealIp
	tBase.Log(" 设置用户信息   GetUserInfo: %s", sKey)
	return tBase.m_MyRedisData[1].redis:hmset(sKey, t)
end
--获得玩家的所有信息
--({nUserID = tClient.nUserId,nGameID = 0,nLevel = 0,nTableId =0}) 
function PublicUserInfo.GetUserInfo(nUserId)
	if PublicUserInfo.IsComAndroid(nUserId) then
		return PublicUserInfo.GetComAndroidUserInfo(nUserId)
	end
	if tBase.m_MyRedisData[1].redis == nil then
		Log.Error(" Error_Info==128   ")
		return
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return t
end

-- 获取玩家基本数据
function PublicUserInfo.GetUserBasic(nUserID)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return PublicUserInfo.GetComAndroidUserInfo(nUserID)
	end
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==114   ")  
		return {}, ""
	end
    local sBkey = "PublicUserInfo_"..api.Double2Int(nUserID)
	local t = tBase.m_MyRedisData[1].redis:hgetall(sBkey)
	if t == nil then  
		tBase.Log(" Error_Info==115   ")  
		return 
	end 	
	local tBasic = {}  
	tBasic.nUserID   = nUserID
	tBasic.sNickName = t["sNickName"] or "0"
	tBasic.nSex 	= tonumber(t["nSex"] or 0 )
	tBasic.sFaceID   = t["sFaceID"]  or 1
	tBasic.Location = t["Location"]  
	tBasic.sIP   = t["sIp"]  
	tBasic.isAndroid = tonumber(t["isAndroid"])
	tBasic.nShopID = tonumber(t["nShopID"]) 
	tBasic.nGold = PublicUserInfo.Get_User_Gold(nUserID) 	 
	tBasic.sShopAcc =  t["sShopAccount"] or ""
	tBasic.nVip = tonumber(t["nVip"]) or 0
	return tBasic
end
function PublicUserInfo.GetUserNickName(nUserID)
	local tRedis =tBase.m_MyRedisData[1].redis
	if tRedis == nil then
		return
	end
	local sKey =string.format("PublicUserInfo_%d",nUserID)
	local sNickName =tRedis:hget(sKey,"sNickName")
	return sNickName
end

-- 更新或增加  用户数据
function PublicUserInfo.UpdateUserData(tData)
	if PublicUserInfo.IsComAndroid(tData.nUserID) then
		PublicUserInfo.UpdateComAndroidUserInfo(tData)
		return 1
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(tData.nUserID)
	tBase.Log(" 更新用户数据   sKey:  %s", sKey)
	return tBase.m_MyRedisData[1].redis:hmset(sKey, tData)
end

--同时可以通过这判断该玩家是否在线 返回的是一个布尔值
function PublicUserInfo.IsUserInfoInRedis(nUserID)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return true
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserID)
	local isExists =tBase.m_MyRedisData[1].redis:exists(sKey);
	return isExists  --布尔值
end
 
--  获取用户所有数据
function PublicUserInfo.GetAllUserInfo(nUserID)
	nUserID = api.Double2Int(nUserID)
    local sBkey = "PublicUserInfo_"..nUserID
	local tem= tBase.m_MyRedisData[1].redis:hgetall(sBkey)
	tem.nGold = PublicUserInfo.Get_User_Gold(nUserID)
	tem.nUnLockGold =PublicUserInfo.Get_User_UnLockGold(nUserID,1)
	return tem
end

-- 是否在线
function PublicUserInfo.IsUsernOnline(nUserID)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return true
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserID)
	local nOnline = tonumber(tBase.m_MyRedisData[1].redis:hget(sKey, "nOnline") or 0)
	return nOnline
end

-- 清除数据
function PublicUserInfo.DeleteUserInfo(nUserID)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return true
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserID)
	return tBase.m_MyRedisData[1].redis:del(sKey)
end


--------------------------- 删除用户信息------------------------------------------------
-- 删除用户信息 
function PublicUserInfo.TryDelUserInfo(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==113")
		return false
	end
	nUserId = api.Double2Int(nUserId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local isAndroid = tonumber( tBase.m_MyRedisData[1].redis:hget(sKey,"isAndroid") )
	if isAndroid == 1 then
		return false
	end
	tBase.m_MyRedisData[1].redis:hmset(sKey, {["nOnline"] = 0})   --下线
	local sGateKey = PublicUserInfo.GetGateKey(nUserId)
	if sGateKey then
		return false
	end
	local arrRlt = PublicUserInfo.GetUserNumFields(nUserId,{"arrGame","UnbalancedCnt"})
	local arrGame = json.decode(arrRlt[1] or "[]")
	if (#arrGame>0) or (arrRlt[2] and arrRlt[2]>0) then
		return false, 'Playing'
	end
	local nAccountType = PublicUserInfo.GetUserAccountType(nUserId) or -1
	if nAccountType ~= 1 and nAccountType ~= 7 and nAccountType ~= 0 then
		tBase.Log("_TryDelUserInfo  nUserId_%d 测试账号nAccountType_%d   1s后,删除用户信息   sKey: %s",nUserId,nAccountType, sKey)
		tBase.m_MyRedisData[1].redis:expire(sKey, 1)
		return true
	end
	return false
end

function PublicUserInfo.ExpireUserInfo(nUserId,nSeconds)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==113   ")
		return false
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local bRlt =tBase.m_MyRedisData[1].redis:expire(sKey,nSeconds)
	tBase.Log("ExpireUserInfo nUserId_%d nSeconds_%d bRlt_%s",nUserId,nSeconds,tBase.tostring(bRlt))
	return bRlt
end

function PublicUserInfo.PersistUserInfo(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==113   ")  
		return false
	end	
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local bRlt =tBase.m_MyRedisData[1].redis:persist(sKey)
	tBase.Log("PersistUserInfo nUserId_%d  bRlt_%s",nUserId,tBase.tostring(bRlt))
	return bRlt
end

---------------------------------------------------- 用户所有信息-----------------------------------------------------------

function PublicUserInfo.GetUserAccountType(nUserId)
	nUserId = api.Double2Int(nUserId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local nAccountType = tonumber( tBase.m_MyRedisData[1].redis:hget(sKey,"nAccountType"))
	return nAccountType or nil 
end
 
-- 上密码锁
function PublicUserInfo.SetUserBankLockTime(tData)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info == 10001   ")  
		return
	end
	
	local sKey = "PublicUserInfo_"..tData.nUserID
	local t = {}
	t["SafeBoxLockTime"] = tData.SafeBoxLockTime
	
	return tBase.m_MyRedisData[1].redis:hmset(sKey, t)
end

-- 获取保险箱解锁时间
function PublicUserInfo.GetUserIDUnLockTime(nUserID)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("redis 无效连接 保险箱 Error_Info==10085  ")
		return {}, ""
	end
    local sBkey = "PublicUserInfo_"..api.Double2Int(nUserID)

    local sKey = "PublicUserInfo_"..nUserID
	local ttt = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	
	if (ttt == nil) then
		tBase.Log("无效数据  获取保险箱上锁时间 Error_Info==10086  nUserID:  "..nUserID)
		local tSafeBoxLockTime = {}   
		tSafeBoxLockTime.nUserID = nUserID
		tSafeBoxLockTime.SafeBoxLockTime = os.time()
		return tSafeBoxLockTime
	end

	local tSafeBoxLockTime = {}   
	tSafeBoxLockTime.nUserID = nUserID
    tSafeBoxLockTime.SafeBoxLockTime = ttt["SafeBoxLockTime"] or os.time()
	tBase.Log(" 获取保险箱上锁时间 %s",cjson.encode(tSafeBoxLockTime))
	return tSafeBoxLockTime
end

-- 添加玩家  nGroupIdid
function PublicUserInfo._SetUser_GroupId(nUserID,nGroupId)
    local sKey = "PublicUserInfo_"..api.Double2Int(nUserID)
    local nResult = tBase.m_MyRedisData[1].redis:hset(sKey,"nGroupId",nGroupId)  
end

--设置用户是否坐下状态 isSit
--true:坐下  false:非坐下
function PublicUserInfo.SetUserSeatStatus(nUserID,isSit)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserID)
	if not tBase.m_MyRedisData[1].redis:exists(sKey) then
		return
	end
	if isSit then
		tBase.m_MyRedisData[1].redis:hset(sKey,"nIsSeat",1)
	else
		tBase.m_MyRedisData[1].redis:hset(sKey,"nIsSeat",0)
	end
end
    
--更新redis的用户的皮肤
function PublicUserInfo.UpdateUserSkin(nUserID,tData)
	if not nUserID then return end
	
	--从redis上面拿用户正在使用的皮肤
	if PublicUserInfo.IsComAndroid(nUserID) then
		return true
	end
	--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
	local sKey =string.format("PublicUserInfo_%d",nUserID)
	for k,v in pairs(tData) do
		local key = "nSkin"..math.floor(v.nPos or 0)
		Base.Log("皮肤浮点数向下取整之后:  %s  nItemID: %d ",key,v.nItemID)
		tBase.m_MyRedisData[1].redis:hset(sKey,key,v.nItemID or 0)
	end
	 
	return true
end
---------------------------------------------------------- 用户统计信息------------------------------------------------------------
-- 获取用户统计信息
function PublicUserInfo.GetUserStatisti(nUserID)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return PublicUserInfo.GetComAndroidUserInfo(nUserID)
	end
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==118   ")  
		return {}, ""
	end
	nUserID = api.Double2Int(nUserID)
    local sBkey = "PublicUserInfo_"..nUserID
	local t = tBase.m_MyRedisData[1].redis:hgetall(sBkey)
	local tStatisti = {}   
	tStatisti.nUserID = nUserID  
	tStatisti.nSumIning =tonumber(t["nSumIning"] or 0 )
	tStatisti.nHuPaiRate =math.ceil(tonumber(t["nHuPaiRate"])or 0 )
	tStatisti.nWinRecord =tonumber(t["nWinRecord"] or 0 )
	tStatisti.nLastkeepWin =tonumber(t["nLastkeepWin"] or 0 )
	tStatisti.nHuPaiIning =tonumber(t["nHuPaiIning"] or 0 )
	tStatisti.sShopAccount = t["sShopAccount"]
	return tStatisti
end
 
---------------------------------------------------------- 用户相关数据------------------------------------------------------------

-- 设定玩家所有游戏的属性 集合所有游戏用到
function PublicUserInfo.SetUser_InRoom(tData)
	tData.nUserID = api.Double2Int(tData.nUserID)
	local sKey = "PublicUserInfo_"..tData.nUserID   
	local nResult =  -1
	local tNew_Data ={}
	tNew_Data.nUserID = tData.nUserID 
	tNew_Data.nLevel = tData.nLevel
	tNew_Data.nTableId =tData.nTableId 
	tNew_Data.nGameType = tData.nGameType or -1
	tNew_Data.GameTime =""
	tNew_Data.nRoomType=tData.nRoomType or -1
	if (tNew_Data.nGameType >0) or (tNew_Data.nRoomType>0) then
		tNew_Data.GameTime = os.date("%Y-%m-%d %H:%M:%S")
	end
	if not PublicUserInfo.EnterGame(tData.nUserID,tData.nGameID,tData.nLevel) then
		tBase.Log("_SetUser_InRoom waring EnterGame fail! nUserID:%d  nGameId:%d nLevel_%d",tData.nUserID,tData.nGameId,tData.nLevel)
	end
	nResult = tBase.m_MyRedisData[1].redis:hmset(sKey, tNew_Data)
	if nResult == true then 
		tBase.Log("_SetUser_InRoom  玩家所有游戏的属性    成功 ")
		return  1
	else
		tBase.Log("_SetUser_InRoom  玩家所有游戏的属性    失败  Error_Info==127 ")
		return 0
	end
end

-- 是否设置自动下注  nGameId: -1 则网关检查
function PublicUserInfo.IsRunAutoBetTask(nUserId,nGameId)
	nGameId = nGameId or 0 
	if nGameId < 0 then return false end -- 网关检测
	if SetingConfig._IsZhiBoGameId(nGameId) then return false end   -- 直播游戏可以进入 
	if PublicRedis.GetUserAutoBetCfg(nUserId) then    -- 运行自动任务,不能进入，其他游戏 
		tBase.Log("_IsRunAutoBetTask nUserId:%d nGameId:%d  正在运行,自动下注任务(OB区块链百家乐) ",nUserId,nGameId)
		return true 
	end  
	return false 
end

-- 检查是否在游戏中(在本服)
function PublicUserInfo.CheckInGame(nUserId,nGameId,nRoomId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local nCurrentEnterGameId =tonumber( tBase.m_MyRedisData[1].redis:hget(sKey,"nGameId") )
	if nCurrentEnterGameId and nCurrentEnterGameId~=nGameId then
	   --给前端提示弹个窗，让其到对应游戏服重连
		local sClientID =tBase.m_MyRedisData[1].redis:hget(sKey,"sClientID")
		local nCurRoomId =tonumber( tBase.m_MyRedisData[1].redis:hget(sKey,"nRoomId") )
		if nCurRoomId == nil then 
			mlogger:error(string.format("_CheckInGame  nUserId_%d nGameId_%d nCurrentEnterGameId_%d  ",nUserId,nGameId,nCurrentEnterGameId))
		end 
		return false,nCurrentEnterGameId,nCurRoomId
	end 
	if PublicUserInfo.IsRunAutoBetTask(nUserId,nGameId) then   
		return false,122,100
	end   
	return true
end

local _UserIdToUnbalanceCnt ={}

--IncrUnbalancedBy(10086,1)  未结算牌局数加1
--IncrUnbalancedBy(10086,-1) 未结算牌局数减1
function PublicUserInfo.IncrUnbalancedBy(nUserId,nIncrValue)
	assert(nIncrValue==1 or nIncrValue==-1)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	if not tRedis:exists(sKey) then
		_UserIdToUnbalanceCnt[nUserId]=nil
		return false
	end
	tRedis:hincrby(sKey,"UnbalancedCnt",nIncrValue)

	_UserIdToUnbalanceCnt[nUserId] =_UserIdToUnbalanceCnt[nUserId] or 0
	_UserIdToUnbalanceCnt[nUserId] =_UserIdToUnbalanceCnt[nUserId] +nIncrValue
	
	tBase.Log("IncrUnbalancedBy nUserId:%d nIncrValue:%d nNowCnt:%d",nUserId,nIncrValue,_UserIdToUnbalanceCnt[nUserId])

	if _UserIdToUnbalanceCnt[nUserId] ==0 then
		_UserIdToUnbalanceCnt[nUserId]=nil
	elseif _UserIdToUnbalanceCnt[nUserId] <0 then
		_UserIdToUnbalanceCnt[nUserId]=nil
		tBase.Log("IncrUnbalancedBy Error,negative happen")
	end
	return true
end

function PublicUserInfo.GetUserNumFields(nUserId,arrField)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local arrRlt =tBase.m_MyRedisData[1].redis:hmget(sKey,table.unpack(arrField))

	for dex,_ in ipairs(arrField) do
		arrRlt[dex] =tonumber(arrRlt[dex]) or arrRlt[dex]
	end
	return arrRlt
end

--进入游戏(必然成功)
function PublicUserInfo.EnterGameV2(nUserId,nGameId,nRoomId,sTableId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("PublicUserInfo_%d",nUserId)
	local sGameRecordField =string.format("sGame_%d",nGameId)

	if PublicUserInfo.IsRunAutoBetTask(nUserId,nGameId) then   
		return false,122,100
	end   
	local arrRlt =tRedis:hmget(sKey,"nShopID","nGroupId","nGameId","nRoomId")
	local nShopId =tonumber(arrRlt[1])
	local nGroupId =tonumber(arrRlt[2])
	local nCurrentEnterGameId =tonumber(arrRlt[3])
	local nCurrentRoomId =tonumber(arrRlt[4])
	
	local arrGameRecord ={}
	arrGameRecord[1]=os.date("!%Y%m%d%H%M%SGMT+8", os.time()+3600*8)
	arrGameRecord[2]=tSrvInfo.nServerId
	arrGameRecord[3]=nRoomId or -1

	--更新游戏列表和sGameRecordField字段值(涉及check-and-set操作)
	local scrip =[[
		local sKey =ARGV[1]
		local sGameRecordField =ARGV[2]
		local nGameId =tonumber(ARGV[3])
		local sGameRecord =ARGV[4]
		local arrRlt =redis.call("hmget",sKey,"arrGame")
		local arrGame =cjson.decode(arrRlt[1] or "[]")
		local arrGameUpdate ={}
		for _,v in ipairs(arrGame) do
			if v ~=nGameId then
				table.insert(arrGameUpdate,v)
			end
		end
		table.insert(arrGameUpdate,nGameId)
		redis.call("hset",sKey,"arrGame",cjson.encode(arrGameUpdate))
		redis.call("hset",sKey,sGameRecordField,sGameRecord)
	]]
	local arrEval =tRedis:eval(scrip,0,sKey,sGameRecordField,nGameId,cjson.encode(arrGameRecord))   

	local tem ={}
	tem.nGameId=nGameId
	tem.nRoomId=nRoomId
	tem.sGameServerKey=tBase.m_tKey
	tem.sGameName=base.m_tType
	tem.nServerId=tSrvInfo.nServerId
	tem.sTableId=sTableId
	local isSuccee =tRedis:hmset(sKey,tem)
	
	--设置一个最近进入合集游戏的时间戳 (进入过合集游戏后取消跟投功能)
	if nGameId~=121 and nGameId~=122 and nGameId~=153 then
		PublicRedis._RemoveUserWithCast(nUserId)
		PublicRedis.SetNotLiveGameEnterTimeStamp(nUserId)
	end
	PublicUserInfo.IncrbyGamingUser(nShopId,nGameId,nRoomId,PublicUserInfo.IsComAndroid(nUserId),1,nUserId)
	tBase.Log("_EnterGameV2 nUserId:%d nGameId:%d nRoomId:%d",nUserId,nGameId,(nRoomId or -1))

	-- 进入游戏人数统计
	if nCurrentEnterGameId == nGameId and nCurrentRoomId > 0 then 
		if nCurrentRoomId ~= nRoomId then 
			PublicRedis._UpdateGameCenterUserCount(nGroupId,nGameId,nCurrentRoomId,-1)  
			PublicRedis._UpdateGameCenterUserCount(nGroupId,nGameId,nRoomId,1)  
			tBase.Log("_EnterGameV2 nUserId:%d nGameId:%d 进入不同场次 New_%d,Old_%d  "
			,nUserId,nGameId,(nRoomId or -1),(nCurrentRoomId or -1))
		end 
	else
		PublicRedis._UpdateGameCenterUserCount(nGroupId,nGameId,nRoomId,1)  
	end 
	return true
end

--
function PublicUserInfo.IsInGame(nUserId,nGameId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("PublicUserInfo_%d",nUserId)
	local sGameRecordFied =string.format("sGame_%d",nGameId)
	local arrRlt =tRedis:hmget(sKey,sGameRecordFied,"arrGame")
	local arrGameRecord =cjson.decode(arrRlt[1] or "[]")
	local arrGame =  cjson.decode(arrRlt[2] or "[]")
	if #arrGameRecord>0 then
		return true,arrGameRecord[3],arrGame
	end
	return false,-1,arrGame
end

--进入游戏。返回:true或false  (大多情况下,应该在登陆游戏服时调用)
--失败原因可能是已经进入了其它游戏 或者redis设置失败
function PublicUserInfo.EnterGame(nUserId,nGameId,nRoomId,sTableId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local arrRlt =tBase.m_MyRedisData[1].redis:hmget(sKey,"nGameId","nRoomId")
	local nCurrentEnterGameId =tonumber(arrRlt[1])
	local nCurrentRoomId =tonumber(arrRlt[2])
	
	--local sCurrentTableId=arrRlt[5]
	if nCurrentEnterGameId and nCurrentEnterGameId~=nGameId then
		--当前所在的游戏id不等于要进入的游戏id
		return false,nCurrentEnterGameId,nCurrentRoomId
	end
	if nCurrentEnterGameId==nGameId and nCurrentRoomId and nCurrentRoomId ~= nRoomId then
		--当前所在的游戏id等于要进入的游戏id,但当前所在场次id不等于进入的场次id
		return false,nCurrentEnterGameId,nCurrentRoomId
	end
	if PublicUserInfo.IsRunAutoBetTask(nUserId,nGameId) then   
		return false,122,100
	end   
	PublicUserInfo.EnterGameV2(nUserId,nGameId,nRoomId,sTableId)
	return true
end


--离开游戏。返回:true或false
--大概以下情况需要调用离开游戏 [非游戏中,返回大厅或处于断线状态] [网关服发现没有该游戏服可转发消息时]
function PublicUserInfo.LeaveGame(nUserId,nGameId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("PublicUserInfo_%d",nUserId)
	local sGameRecordField =string.format("sGame_%d",nGameId)

	local arrRlt =tRedis:hmget(sKey,"nGameId","nShopID","nGroupId",sGameRecordField)
	local nCurrentEnterGameId =tonumber(arrRlt[1])
	local nShopId =tonumber(arrRlt[2])
	local nGroupId =tonumber(arrRlt[3]) 
	local arrGameRecord =cjson.decode(arrRlt[4] or "[]")
	local nRoomId =arrGameRecord[3] or -1

	if nCurrentEnterGameId ==nGameId then
		tRedis:hdel(sKey,"nRoomId","sGameServerKey","sGameName","nServerId","sTableId","nGameId")
	end

	--更新游戏列表和删除sRecordFied字段 (涉及check-and-set操作)
	local scrip =[[
		local sKey =ARGV[1]
		local sGameRecordField =ARGV[2]
		local nGameId =tonumber(ARGV[3])
		local arrRlt =redis.call("hmget",sKey,"arrGame")
		local arrGame =cjson.decode(arrRlt[1] or "[]")
		local arrGameUpdate ={}
		for _,v in ipairs(arrGame) do
			if v ~=nGameId then
				table.insert(arrGameUpdate,v)
			end
		end
		redis.call("hset",sKey,"arrGame",cjson.encode(arrGameUpdate))
		local nDel =redis.call("hdel",sKey,sGameRecordField)
		return {nDel}
	]]
	local arrEval =tRedis:eval(scrip,0,sKey,sGameRecordField,nGameId)   

	--
	if arrEval[1] ==1 then
		tBase.Log("LeaveGameSuccee nUserId:%d nGameId:%d",nUserId,nGameId)
		PublicUserInfo.TryDelUserInfo(nUserId)
		PublicUserInfo.IncrbyGamingUser(nShopId,nGameId,nRoomId,PublicUserInfo.IsComAndroid(nUserId),-1,nUserId)
		PublicRedis._UpdateGameCenterUserCount(nGroupId,nGameId,nRoomId,-1)
		return true
	end
	tBase.Log("LeaveGameFail nUserId:%d nGameId:%d",nUserId,nGameId)
	return true
end

-- 检查是否直播游戏  
function PublicUserInfo._CheckLiveGameId(nUserId,nGameId)
	if nGameId == 121 or nGameId == 122 or nGameId == 155 or nGameId == 153 or nGameId == 129 
		or nGameId == 107 or nGameId == 159 or nGameId == 150 or nGameId == 212 then 
		tBase.Log("_CheckLiveGameId nUserId:%d nGameId:%d",nUserId,nGameId)	
		PublicRedis._RemoveUserWithCast(nUserId)  -- 删除跟投数据
		PublicUserInfo.LeaveGame(nUserId,nGameId)
		return true 
	end 
	return false 
end

--直播百人游戏：(nYuXiaXie,121),(nBJLS,122),(nFootBall,129),(nTouBao,155),(nSeDie,153)
--直播非百人游戏：(nPilotGame,133),(nBJLS,122),(nFellTree,157),(nBasketball,159)
--合集百人游戏：(nBaiJiaLe,107),(nBaiRenZjh,118),(nHJYuXiaXie,212),(nsedie,150)
--合集非百人游戏：(nKanPaiQianZhuangNiuNiu,101),(nRandZhuangJiaNiuNiu,102),(nTongBiNiuNiu,103),(nBaiRenNiuNiu,104),
	--(nZhaJinHua,105),(nDian21,106),(nQianZhuanBaiJiaLe,109),(nSanGong,113),(nQianZhuang21,114),(nTongBi21,115),(nPaiJiu,116),(nTBBaiJiaLe,110),
	--(nErBaGang,120),(nBodeng,124),(nGaoBo,128),(nSanGong,113),(nQianZhuang21,114),(nTongBi21,115),(nPaiJiu,116),(nTBBaiJiaLe,110),,(nMaJiang,108)

-- 检查是否百人游戏（直播百人游戏,合集百人游戏）  
function PublicUserInfo._CheckBaiRenGameId(nUserId,nGameId)
	if nGameId == 121 or nGameId == 122 or nGameId == 155 or nGameId == 153 or nGameId == 129 then 
		tBase.Log("_CheckLiveBaiRenGameId nUserId:%d nGameId:%d",nUserId,nGameId)	
		PublicRedis._RemoveUserWithCast(nUserId)  -- 删除跟投数据
		PublicUserInfo.LeaveGame(nUserId,nGameId)
		return true 
	elseif nGameId == 107 or nGameId == 150 or nGameId == 118 or nGameId == 212 then
		tBase.Log("_CheckhejiBaiRenGameId nUserId:%d nGameId:%d",nUserId,nGameId)	
		--PublicRedis._RemoveUserWithCast(nUserId)  -- 删除跟投数据
		PublicUserInfo.LeaveGame(nUserId,nGameId)
		return true
	end 
	return false 
end


--返回玩家当前所处游戏 nGameId,nRoomId,sServerKey;可能为nil ,nil
function PublicUserInfo.GetUserPlayingGame(nUserId,nGameId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	if PublicUserInfo.IsRunAutoBetTask(nUserId,nGameId) then
		return 122,100
	end
	local arrRlt =tBase.m_MyRedisData[1].redis:hmget(sKey,"nGameId","nRoomId","sGameServerKey","sGameName","sTableId", "nIsSeat")
	local nGameId =tonumber( arrRlt[1])
	local nRoomId =tonumber( arrRlt[2])
	local sServerKey =arrRlt[3]
	local sGameName =arrRlt[4]
	local sTableId=arrRlt[5]
	local nIsSeat=tonumber(arrRlt[6])
	return nGameId,nRoomId,sServerKey,sGameName,sTableId, nIsSeat
end

--根据sTableId获取俱乐部id
function PublicUserInfo.GetClubIdByTableId(sTableId)
	if type(sTableId)~="string" then
		return
	end
	local sKey = string.format("APIOpenTale_%s",sTableId)
	local sSubKey = "sConfig"
   	local redis = tBase.m_MyRedisData[2].redis

	local sConfig = redis:hget(sKey,sSubKey)

	local isSuccee,tConfig = pcall(cjson.decode,sConfig)
	if isSuccee then
		if tConfig.nClubId then
			return tonumber(tConfig.nClubId)
		end
	else
		tBase.Log("GetClubIdByTableId table sConfig decode fail,sTableId:%s",sTableId)
	end
	return nil
end

-- 获取 sShopId
function PublicUserInfo.Get_User_SHopId(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then tBase.Log(" Error_Info==122    Get_User_SHopId  ")  return end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local nShopID = tonumber(tBase.m_MyRedisData[1].redis:hget(sKey,"nShopID")) or -1			--用于获取分组id;实际为表Accounts_InFo中的ChannelID
	local nShopIdReal =tonumber(tBase.m_MyRedisData[1].redis:hget(sKey,"nShopIdReal")) or -1	--表Accounts_InFo中的ShopID (暂无实际作用，仅作回写记录)
	return nShopID,nShopIdReal
end

-- 获取  nGroupId
function PublicUserInfo.Get_User_GroupId(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then tBase.Log(" Error_Info==122    Get_User_SHopId  ")  return end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local nGroupId = tBase.m_MyRedisData[1].redis:hget(sKey,"nGroupId") 
	return tonumber(nGroupId) or -1 
end

function PublicUserInfo.Get_User_Channel(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then tBase.Log(" Error_Info==122    Get_User_Channel  ")  return end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local sChannel = tBase.m_MyRedisData[1].redis:hget(sKey,"sChannel")
	return tostring(sChannel) or "" 
end

function PublicUserInfo.Get_User_ShopAccount(nUserId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	return tBase.m_MyRedisData[1].redis:hget(sKey,"sShopAccount") 
end

--sShopAccount

-- 检查 是否机器人:  1 机器人 ，0  用户 
function PublicUserInfo.Check_User_IsAndroid(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then tBase.Log(" Error_Info==122   ")  return  end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	if t["isAndroid"] == nil then 
		return nil 
	end 
	local nResult= tonumber(t["isAndroid"]) 
	return nResult
end

-- 获取 sClientID
function PublicUserInfo.GetClientID_String(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then tBase.Log(" Error_Info==122   ")  return end
	local sKey = string.format("PublicUserInfo_%d",nUserId or 0)
	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return t["sClientID"]
end

-- 获取 nClientID
function PublicUserInfo.GetClientID_Number(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then tBase.Log(" Error_Info==123   ")  return end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return  tonumber(t["nClientId"] ) 
end

-- 获取 sGateKey
function PublicUserInfo.GetGateKey(nUserId)
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==124   ")  
		return
	end
	nUserId = api.Double2Int(nUserId)
	local sKey = "PublicUserInfo_"..nUserId
	local sGateKey =tBase.m_MyRedisData[1].redis:hget(sKey,"sGateKey")
	--local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
	return sGateKey,sKey
end

function PublicUserInfo.IsServerKeyExists(sServerKey)
	return tBase.m_centerRedis.Mo:exists(sServerKey)
end

--isRudely:是否强制删除
function PublicUserInfo.DelGateKey(nUserId,sGateKey,isRudely)
	local sNowGateKey,sKey =PublicUserInfo.GetGateKey(nUserId)
	if not isRudely then
		if sNowGateKey==nil or sNowGateKey ~=sGateKey then
			return false
		end
	end
	tBase.m_MyRedisData[1].redis:hdel(sKey,"sGateKey")
	return true
end

function PublicUserInfo.CreatePaiJuID()
    -- 取时间戳中间6位，避免每秒重复
    local timestamp = os.time()
    local time_part = string.format("%06X", timestamp % 0xFFFFFF)  -- 取后6位十六进制
	local dex =tBase.m_MyRedisData[2].redis:incr("ForUIDCreate")
	if dex >= 9999 then
		tBase.m_MyRedisData[2].redis:del("ForUIDCreate")
	end
	-- return string.format("%X%05X",time,dex)
	return string.format("%s%04X", time_part, dex)
end

--生成一个观察者用户id
function PublicUserInfo.GetAVisitorUserId()
	local dex =tBase.m_MyRedisData[1].redis:incr("ForVisitorUserIdCreate")
	return 100000000 +dex
end

function ipToInt( str )
	if str and type(str)=="string" and #str>4 then
		local o1,o2,o3,o4 = str:match("(%d+)%.(%d+)%.(%d+)%.(%d+)" )
		return (2^24*o1 + 2^16*o2 + 2^8*o3 + o4)
	end
end

-- 获取nIP (返回一个整数类型的ip)
function PublicUserInfo.GetUserIP(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	if tRedis == nil then 
		return 0
	end
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local arrRlt =tRedis:hmget(sKey,"sRealIp","sIp")
	local nIp =ipToInt(arrRlt[1])
	local nIpB =tonumber(arrRlt[2])
	return (nIp or nIpB),(arrRlt[1] or api.Dword2String(nIpB))  --整数形式,点分字符串形式
end


 --添加或修改玩家  统计数据 reids 和 数据库
function PublicUserInfo.ChangeUserStatisti(tData)
	if 1 == 1 then
		return
	end

	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log(" Error_Info==126   ")  
		return
	end
    local sSkey = "PublicUserInfo_"..tData["nUserId"] 

	tBase.Log(" 获取统计数据  sSkey:  "..sSkey)
    local tUserStatisti = PublicUserInfo.GetUserStatisti(tData["nUserId"])
    if next(tUserStatisti) == nil then tBase.Log(" Error_Info==70   ") return -1 end
    tUserStatisti["nSumIning"] = tUserStatisti["nSumIning"] + 1
    --tData["cResult"] == 1是玩家赢牌
    if tData["cResult"] == 1 then
    	tUserStatisti["nHuPaiIning"] = tUserStatisti["nHuPaiIning"] + 1
    	tUserStatisti["nLastkeepWin"] = tUserStatisti["nLastkeepWin"] + 1
    	if tUserStatisti["nLastkeepWin"] > tUserStatisti["nWinRecord"] then
    		tUserStatisti["nWinRecord"] = tUserStatisti["nLastkeepWin"]
    	end
    else
    	tUserStatisti["nLastkeepWin"] = 0
    end 
    tUserStatisti["nHuPaiRate"] = tUserStatisti["nHuPaiIning"]*100 / tonumber(tUserStatisti["nSumIning"])
    tBase.m_MyRedisData[1].redis:hmset(sSkey,tUserStatisti)
	--更新数据库的数据 定时小时  或者 断开的时候更新数据库 
	-- 更新数据库数据
	local tUpdateTreasure = {}
	tUpdateTreasure["nUserID"] = tData["nUserId"]  -- UserID
	tUpdateTreasure["cResult"] = tData["cResult"]
	tUpdateTreasure.isAndroid = tData.isAndroid   -- 标识机器人： 暂时用不上！
	tRecordDb.UpdateStatistiData(tUpdateTreasure)
	return 
end

-- 更新房锁
function PublicUserInfo.WriteScoreLocker(tData)
    local nClientId = nil
    if tPubHelper.tLocation then
        nClientId = tPubHelper.tLocation.GetClientId(tData.nUserId)
    end
    if tData.nServerId == nil then
        tBase.Log(" Error_Info==211   ")  
        return
    end
    local s = tBase.GetSP().new(ProtoMgr.Sys.SYS_DB, ProtoMgr.SUB_DB.SUB_REQ_WRITESCORELOCK)
    s:AddString("Call SetGameScoreLocker("..tData.nUserId..","..tData.nServerId..")")
    tBase.PostDatasByType(tname.db, nClientId, tData.nUserId, s:GetData(), s:GetSize())
end

function PublicUserInfo.CheckClientIDByUserID(In_nUserID,In_nClient)
	local nClient = PublicUserInfo.GetClientID_Number(In_nUserID)
	if nClient == In_nClient then
		return true
	else
		return false
	end
end
function PublicUserInfo.ChecksClientIDByUserID(In_nUserID,In_sClient)
	local nClient =tonumber(string.match(In_sClient,":(%d+)"))
	return PublicUserInfo.CheckClientIDByUserID(In_nUserID,nClient)
end

--是否需要控牌,返回:3(第二好牌输) 2(一般牌型输) 1(优先匹配机器人) nil(不控牌)
function PublicUserInfo.IsNeedControl(nGameId,nRoomId,nUserId)
	if nRoomId <= 0 or nRoomId >= 100 then -- 体验房和区块链不控
		return nil
	end
	if tSetingConfig.isGm then
		--后台设置受控玩家以及玩家输赢
		local redis = tBase.m_MyRedisData[1].redis
		local sKey = string.format("PersonalControlGM")
		local sUserId = redis:hget(sKey,"UserId")
		local sControlType = redis:hget(sKey,"ControlType")
		if sUserId and sControlType then
			local nControl = tonumber(sUserId) or -1
			local nControlType = tonumber(sControlType) or 0
			if nControl==nUserId then
				tBase.Log("[IsNeedControl]后台GM设置个人控:nControl:%d,nControlType:%d",nControl,nControlType)
				redis:del(sKey)
				return nControlType
			end
		end
	end
	local nShopId = PublicUserInfo.Get_User_GroupId(nUserId)
	if nShopId ~= nil then
		local isSuccee, tParam = pcall(ctlDefine.GetRoomParam, nShopId, nGameId, nRoomId)
		if not isSuccee then
			mlogger:error("GetRoomParam error")
		else
			local isCtl = tParam.IsControl or 1
			if isCtl == 0 then
				mlogger:info('close control:'..nShopId..","..nGameId..","..nRoomId)
				return nil
			end
		end
	end

	local sRoomKey ="GameControl"
	local sUserKey ="GameControlUser"

	local nGameId =api.Double2Int(nGameId)
	local nRoomId =api.Double2Int(nRoomId)
	local nUserId =api.Double2Int(nUserId)

	local sMember =string.format("%d_%d_%d",nGameId,nRoomId,nUserId)
	local nRoomRes = tBase.m_MyRedisData[1].redis:hget(sRoomKey, sMember)

	local nRoomControlRes = nil
	if nRoomRes ~= nil then
		local tV = publicApi.string_split(nRoomRes, '\n')
		nRoomControlRes = math.floor(tonumber(tV[2]))
		tBase.Log("IsNeedControl Room Res:%d", nRoomControlRes)
	end

	local sUserMember =string.format("%d",nUserId)
	local nUserRes = tBase.m_MyRedisData[1].redis:hget(sUserKey, sUserMember)

	local nUserControlRes = nil
	if nUserRes ~= nil then
		local tV = publicApi.string_split(nUserRes, '\n')
		nUserControlRes = math.floor(tonumber(tV[2]))		
		tBase.Log("IsNeedControl User Res:%d", nUserControlRes)
	end	

	-- 房间控优先
	if nRoomControlRes ~= nil and nRoomControlRes >= 1 and nRoomControlRes <= 4 then
		return nRoomControlRes
	end

	if nUserControlRes ~= nil and nUserControlRes >= 1 and nUserControlRes <= 4 then
		return nUserControlRes
	end
	
	return nil
end

local function _sortWin(v1, v2)
	if v1.dWin > v2.dWin then
		return true
	end

	return false
end

local function _sortWin2(v1, v2)
	if v1.dWin < v2.dWin then
		return true
	end

	return false
end

-- 异常输出
function tpLog(e)
    local kl = base.GetKernel()
    local km = km_FD55292F51334A64AC61470D796F8D43.new(kl)
    km:Log(e)
    km:Log(debug.traceback())
    return e
end  
 
--是否需要控牌,返回:3(第二好牌输) 2(一般牌型输) 1(优先匹配机器人) nil(不控牌)
function PublicUserInfo.IsNeedControlBR(nShopId, nGameId, nRoomId, tUserIDs)

	if tSetingConfig.isGm then
		--后台设置受控玩家以及玩家输赢值
		local redis = tBase.m_MyRedisData[1].redis
		local sKey = string.format("PersonalControlGM")
		local sUserId = redis:hget(sKey,"UserId")
		local sControlType = redis:hget(sKey,"ControlType")
		if sUserId and sControlType then
			local nUserId = tonumber(sUserId) or -1
			local nControlType = tonumber(sControlType) or 0
			for k,v in pairs(tUserIDs) do
				if v==nUserId then
					tBase.Log("[IsNeedControlBR]后台GM设置个人控:nUserId:%d,nControlType:%d",nUserId,nControlType)
					redis:del(sKey)
					return nUserId,nControlType
				end
			end
		end
	end

	local uID = -1
	local nT = 0

	local _GetControlRes = function (sUserKey, tUTmp)
		local tUserControl = nil 
		if next(tUTmp) ~= nil then 
			tUserControl = tBase.m_MyRedisData[1].redis:hmget(sUserKey, tUTmp)
		end

		if tUserControl ~= nil and  next(tUserControl) ~= nil then
			local tTmp = {}
			local tTmpWin = {}
			for _, sRes in pairs(tUserControl) do
				local tItem = {}

				local tV = publicApi.string_split(sRes, '\n')
				
				tItem.nUserID = math.floor(tonumber(tV[1]))
				tItem.nUserControlType = math.floor(tonumber(tV[2]))
				tItem.dWin = tonumber(tV[3])

				-- tBase.Log("IsNeedControlBR  Item, UserID:%d, Type:%d, Win:%f", tItem.nUserID, tItem.nUserControlType, tItem.dWin)

				if tItem.nUserControlType == 4 then
					table.insert(tTmpWin, tItem)
				else
					table.insert(tTmp, tItem)
				end
				
			end  
			
			-- 按赢分从高到低排
			table.sort(tTmp, _sortWin)
			table.sort(tTmpWin, _sortWin2)

			local tResControl = {}
			if #tTmp > 0 and #tTmpWin > 0 then
				if math.random(1, 2) == 1 then
					tResControl = tTmp
				else
					tResControl = tTmpWin
				end
			elseif #tTmp > 0 then
				tResControl = tTmp
			elseif #tTmpWin > 0 then
				tResControl = tTmpWin
			end

			local nIndex = 0
			if #tResControl >= 10 then
				nIndex =  math.random(1, 10)
				tBase.Log("#tResControl >= 10")
			elseif #tResControl > 0 then

				local nBRControlPer = 50
				local isSuccee, tParam = pcall(ctlDefine.GetRoomParam, nShopId, nGameId, nRoomId)
				if not isSuccee then
					tBase.Log("GetRoomParam error")
					if type(tParam) == "string" then 
						mlogger:error(tParam)
					else 
						tBase.LogT(tParam) 
					end
				else
					nBRControlPer = tParam.BRControlPer or nBRControlPer
				end

				if nBRControlPer < 0 or nBRControlPer > 100 then
					nBRControlPer = 0
					mlogger:error("BRControlPer set error")
				end

				mlogger:info("BRControlPer:"..nBRControlPer)

				if math.random(1, 100) <= nBRControlPer then
					nIndex =  math.random(1, #tResControl)
				end
			end

			if nIndex > 0 then
				local nUserControlType = tResControl[nIndex].nUserControlType
				tBase.LogT(sUserKey,":",nUserControlType)
				if nUserControlType >= 1 and nUserControlType <= 4 then
					tBase.Log("IsNeedControlBR  nUserID_%d  ----- nUserControlType:%d",tResControl[nIndex].nUserID, nUserControlType)
					uID = tResControl[nIndex].nUserID
					nT = nUserControlType
					return true
				else
					assert(false)
				end
			end
		else
			tBase.Log("tUserControl nil")
		end

		return false
	end

	local _GetRoomRes = function ()
		tBase.Log("Control Room")
		local sKey ="GameControl"

		local tUTmp = {}
		for _, nUserID in ipairs(tUserIDs) do
			local sMember = string.format("%d_%d_%d", nGameId,nRoomId,nUserID)
			tUTmp[sMember] = sMember
		end

		return _GetControlRes(sKey, tUTmp)
	end

	local _GetUserRes = function ()
		tBase.Log("Control User")
		local sKey ="GameControlUser"

		local tUTmp = {}
		for _, nUserID in ipairs(tUserIDs) do
			local sUID = string.format("%d", nUserID)
			tUTmp[sUID] = sUID
		end

		return _GetControlRes(sKey, tUTmp)
	end	


	local _GetControltR = function ()
	
		if nRoomId <= 0 or nRoomId >= 100 then -- 体验房和区块链不控
			return
		end

		local isSuccee, tParam = pcall(ctlDefine.GetRoomParam, nShopId, nGameId, nRoomId)
		if not isSuccee then
			mlogger:error("GetRoomParam error")
		else
			local isCtl = tParam.IsControl or 1
			if isCtl == 0 then
				mlogger:info('close control:'..nShopId..","..nGameId..","..nRoomId)
				return
			end
		end

		if _GetRoomRes() == false then
			_GetUserRes()
		end

	end

	xpcall(_GetControltR, tpLog)

	return uID, nT
end

-- 返回风控余额， -1 不用风控
function PublicUserInfo.GetControlBalance(nUserId,nGroupId)
	local balance = -1

	local _GetBalance = function ()
		balance = PublicRedis.__GetBalance(nUserId,nGroupId)
	end

	local isSuccee,err = pcall(_GetBalance)

	if not isSuccee then
		base.Log("[ERROR] 返回用户风控余额:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return balance
end

--返回邀请码开关
function PublicUserInfo.GetCodeSwitch(nGroupId)
	local flag = -1

	local __GetCodeSwitch = function ()
		flag = PublicRedis._GetCodeSwitch(nGroupId)
	end

	local isSuccee,err = pcall(__GetCodeSwitch)

	if not isSuccee then
		base.Log("[ERROR] 返回邀请码相关内容显示开关:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return flag
end

--返回机器人配置
function PublicUserInfo.GetRobConfig(nGroupId)
	local flag = 0

	local __GetRobConfig = function ()
		flag = PublicRedis._GetRobConfig(nGroupId)
	end

	local isSuccee,err = pcall(__GetRobConfig)

	if not isSuccee then
		base.Log("[ERROR] 返回机器人配置:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return flag
end

--返回转账方式
function PublicUserInfo.GetTransferWay(nGroupId)
	local flag = ""
	local allFlag = {}

	local __GetTransferWay = function ()
		for i=0,30 do
			table.insert(allFlag,PublicRedis._GetTransferWay(nGroupId,i))
		end
	end

	local isSuccee,err = pcall(__GetTransferWay)

	if not isSuccee then
		base.Log("[ERROR] 返回转账方式:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return allFlag
end

--返回前端用文件编码
function PublicUserInfo.GetFileConfig()
	local flag = ""

	local __GetFileConfig = function ()
		flag = PublicRedis._GetFileConfig()
	end

	local isSuccee,err = pcall(__GetFileConfig)

	if not isSuccee then
		base.Log("[ERROR] 返回前端用文件编码:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return flag
end

--获取充值提现开关
function PublicUserInfo.GetUserTransferSwitch(nUserId)
	local switch = nil

	local __GetUserTransferSwitch = function ()
		switch = PublicRedis._GetUserTransferSwitch(nUserId)
	end

	local isSuccee,err = pcall(__GetUserTransferSwitch)

	if not isSuccee then
		base.Log("[ERROR] 返回充值提现开关:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return switch
end

--获取分享活动开关
function PublicUserInfo.GetUserShareActiSwitch(nUserId)
	local switch = nil

	local __GetUserShareActiSwitch = function ()
		switch = PublicRedis._GetUserShareActiSwitch(nUserId)
	end

	local isSuccee,err = pcall(__GetUserShareActiSwitch)

	if not isSuccee then
		base.Log("[ERROR] 返回分享活动开关:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return switch
end

--获取“手动”充值提现开关 1为关 0为开
function PublicUserInfo.GetOnliTransSwitch(nGroupId)
	local switch = nil

	local __GetOnliTransSwitch = function ()
		switch = PublicRedis._GetOnliTransSwitch(nGroupId)
	end

	local isSuccee,err = pcall(__GetOnliTransSwitch)

	if not isSuccee then
		base.Log("[ERROR] 返回分享活动开关:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return switch
end

--获取最小充值金额
function PublicUserInfo.GetMinRecharge(nGroupId)
	local switch = nil

	local __GetMinRecharge = function ()
		switch = PublicRedis._GetMinRecharge(nGroupId)
	end

	local isSuccee,err = pcall(__GetMinRecharge)

	if not isSuccee then
		base.Log("[ERROR] 返回分享活动开关:"..err)
        if type(err) == "string" then
           logger:error(err)
        end
	end

	return switch
end


--获取游戏难度
function PublicUserInfo.GetGameDiff(nGameId)
	local t = tBase.m_MyRedisData[2].redis:hgetall("per_game_control"..nGameId)
	local nDiff = 30
	if t and next(t) then
		if t["diff"] then
			nDiff = tonumber(t["diff"])
		end
	end

	tBase.Log("游戏获取难度 GameId:%d Diff:%d", nGameId, nDiff)
	return nDiff
end

--修复麻将难度
function PublicUserInfo.RepairMajiongDiff(nDiff)
	local nAfter = nDiff
	if nDiff < 2 or nDiff > 180 then
		nAfter = 30
	end

	if nDiff ~= nAfter then
		tBase.Log("难度范围设置%d不合理,系统强制修正为%d", nDiff, nAfter)
	else
		tBase.Log("系统难度设置合理,设置成功,难度为%d", nDiff)
	end

	return nAfter
end

-- 飞行棋获取控牌参数
function PublicUserInfo.GetPilotControl(nUserID, sSerieslNum, nDiceRecord)

	local nDiceID = -1

	local f = function ()

		tBase.Log("GetPilotControl :"..nUserID..","..sSerieslNum..","..nDiceRecord)

		local myredis = tBase.m_MyRedisData[1].redis
		local sKey ="PilotContro_338F0E839CA141C5ACEBFEFEF53BB354"

		local sMember1 = string.format("%d_%s_%d",nUserID, sSerieslNum, nDiceRecord)
		local sMember2 = string.format("%d_New",nUserID)

		local sVal = myredis:hget(sKey, sMember1)
		if sVal == nil then

			tBase.Log(sMember1..": nil")

			-- 先把旧数据删除
			-- hmdel(sUserKey, tUTmp)
			local nR, tDel = myredis:hscan(sKey, 0, 'match', nUserID..'_*')
			for key, val in pairs(tDel) do
				if key ~= sMember2 then
					local nTmpR = myredis:hdel(sKey, key)
					tBase.Log("hDel:"..key..", res:"..nTmpR)
				end
			end

			sVal = myredis:hget(sKey, sMember2)
			if sVal ~= nil then -- 获取新数据
				myredis:hset(sKey, sMember1, sVal)
				myredis:hdel(sKey, sMember2)
			else				-- 设置没用数据
				myredis:hset(sKey, sMember1, "-1")
			end
		end

		if sVal ~= nil then
			local nVal = tonumber(sVal)
			if nVal >= 1 and nVal <= 6 then
				nDiceID = nVal

				local Send = ProtoManager.PubProto_1_pb.REQ_Control_Record()
				local s = tBase.GetSP().new(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REQ_PILOT_CONTROLRECORD)
			
				Send.sSql = "insert into DJH_RecordDB.PilotControlRecord(UserID, Dice, Type, SerieslNum, DiceRecord) VALUES("..nUserID ..
				", "..nDiceID..
				", 0"..
				", '"..sSerieslNum.."'"..
				", "..nDiceRecord..
				")"
			
				s:AddString(Send:SerializeToString())     
				tBase.PostDatasByType(typename.db, nUserID, nUserID, s:GetData(), s:GetSize())

				tBase.Log("GetPilotControl Send DB:"..Send.sSql)
			end
		end
	end

	local sLockName = "Lock_C3F7C33588D743B49F54E2549EBB7CCB_"..nUserID
	mlogger:info("GetPilotControl GLock.Lock 1:"..nUserID)
	local nLockRes = GLock.Lock(base.m_MyRedisData[1].redis, sLockName, '1', 1000 * 2)
	mlogger:info("GetPilotControl GLock.Lock 2:"..nUserID)
    if nLockRes == 0 then -- 获取锁成功
        xpcall(f, GLock.tpLog)
		GLock.UnLock(base.m_MyRedisData[1].redis, sLockName, '1')
		mlogger:info("GetPilotControl UnLock :"..nUserID)
    else
        mlogger:error("GetPilotControl GLock Error :"..nUserID)
	end
	
	return nDiceID
end

function PublicUserInfo.GetUserIdByToken(sToken)
	if sToken==nil then
		return nil,nil
	end
	local nUserId =	tonumber(tBase.m_MyRedisData[1].redis:get(sToken))
	if not nUserId then
		return nil,nil
	end
	--local nKeyFlag =tonumber(string.match(sToken,"sToken_(%d+)_"))
	local sNewToken=sToken
	--if nKeyFlag ~=nUserId then
		--tBase.m_MyRedisData[1].redis:del(sToken)
		--sNewToken =string.format("sToken_%d_%d",nUserId,math.random(999,10000000))
		--tBase.m_MyRedisData[1].redis:set(sNewToken,""..nUserId)
	--end
	--tBase.m_MyRedisData[1].redis:expire(sNewToken,3600*24) --设置过期时间
	return nUserId,sNewToken
end

function PublicUserInfo.PreciseGetOpenGateNum()
	local num = 0
	local getwaykey = tBase.GetSrcAllKey(tname.gateway)
	if getwaykey then
		for key, val in pairs(getwaykey) do
			local t = tBase.m_MyRedisData[1].redis:hgetall(tostring(val))
			if t then num = num+1 end
		end
	end
	return num
end

function PublicUserInfo.SetGateKeyPortOnline(key, gatekey, nIp, nPort, nSocketType, nNum)
	local sKey = tostring(key)
	if gatekey and nIp and nPort and nNum then		
		local sRK = nIp..'_'..nPort.."_"..nSocketType.."_"..nNum
		tBase.m_MyRedisData[1].redis:hset(sKey, gatekey, sRK)
		mlogger:debug(string.format("UptateOnline_m_incr:%s",cjson.encode(sRK) ))
	end
end

function PublicUserInfo.IncrConnection()
	local script = [[
		-- KEYS[1] = 当前在线人数 key (如 "online:count")
		-- KEYS[2] = 今日最大在线人数 key (如 "online:max:20251111")

		local current = tonumber(redis.call("INCR", KEYS[1]))
		local max = tonumber(redis.call("GET", KEYS[2]) or "0")
		if current > max then
			redis.call("SETEX", KEYS[2], 86400, current)  -- 设置过期时间为一天
		end
		return {current, max}
	]]
	local ret = tBase.m_MyRedisData[1].redis:eval(script, 2, "GateWayConnectionCount", "GateWayConnectionCount:Max:" .. os.date("%Y%m%d"))
	mlogger:info(string.format("GateWayConnectionCount:%s,GateWayConnectionCount:Max:%s", ret[1], ret[2]))
	--tBase.m_MyRedisData[1].redis:incr("GateWayConnectionCount")
end

function PublicUserInfo.Incr(sKey)
	return tonumber( tBase.m_MyRedisData[1].redis:incr(sKey))
end

function PublicUserInfo.DecrConnection()
	tBase.m_MyRedisData[1].redis:decr("GateWayConnectionCount")
end

function PublicUserInfo.getcrConnection()
	local _Num = tBase.m_MyRedisData[1].redis:get("GateWayConnectionCount")
	return _Num or 0
end

function PublicUserInfo.setcrConnection()
	tBase.m_MyRedisData[1].redis:set("GateWayConnectionCount",0)
end

--用途:游戏服启动时，卡房检查与清理
function PublicUserInfo.GameClear(nGameId)
	local nGameId =nGameId or 0
	local redis =tBase.m_MyRedisData[1].redis
	local scrip =[[
	  local arrRlt ={}
	  local gameid =tonumber(ARGV[1])
	  local serverid =tonumber(ARGV[2])
	  local sSetGame =string.format("Set_game%d",gameid)
	  local arrUserId =redis.call(KEYS[1], sSetGame) or {}

	  local sTempSetKey =string.format("tmpSet_%d_%d",gameid,serverid)
	  redis.call(KEYS[3],sTempSetKey)

	  for _,userid in ipairs(arrUserId) do
		local skey=string.format("PublicUserInfo_%d",userid)
		local curGame =redis.call(KEYS[4],skey,'nGameId') or '0'
		local curServerid =redis.call(KEYS[4],skey,'nServerId') or '0'
		if tonumber(curGame) ==gameid and tonumber(curServerid) ==serverid then
		  redis.call(KEYS[2], skey,'nGameId','nRoomId','sGameServerKey','sGameName','nServerId')
		  redis.call(KEYS[7],sTempSetKey,userid)
		end
		if curGame =='0' then
			redis.call(KEYS[7],sTempSetKey,userid)
		end
	  end
	  local arrShopGamingKeys = redis.call(KEYS[5], "Set_sAllGaming_shop*") or {}
		for _, sShopKey in ipairs(arrShopGamingKeys) do
			redis.call(KEYS[6], sShopKey, sShopKey, sTempSetKey)
		end
	  local sSetKeys=string.format("Set*game%d*",gameid)
	  local arrSetKey =redis.call(KEYS[5],sSetKeys) or {}
	  for _,sSetkey in ipairs(arrSetKey) do
		redis.call(KEYS[6],sSetkey,sSetkey,sTempSetKey)
	  end
	  return arrSetKey
	]]
	local rlt =redis:eval(scrip,7,'smembers','hdel','del','hget','keys','sdiffstore','sadd',nGameId,tSrvInfo.nServerId)
	return rlt
end

--nIncrCnt:只能取 1或-1
--可优化为用redis内置lua执行
function PublicUserInfo.IncrbyGamingUser(nShopId,nGameId,nRoomId,isAndroid,nIncrCnt,nUserId)
	if isAndroid then
		return
	end
	if not (nIncrCnt==1 or nIncrCnt==-1) then
		return
	end
	nUserId =api.Double2Int(nUserId)

	local sShopGameRoom =string.format("shop%d_game%d_room%d",(nShopId or -1),(nGameId or -1),(nRoomId or -1))
	local sShopGame =string.format("shop%d_game%d",(nShopId or -1),(nGameId or -1))
	--local sShop =string.format("shop%d",(nShopId or -1))
	local sGame =string.format("game%d",(nGameId or -1))
	local sGameRoom =string.format("game%d_room%d",(nGameId or -1),(nRoomId or -1))
	local tRedis =tBase.m_MyRedisData[1].redis
	tRedis:multi()

	if nGameId == -2 then
		--大厅服、登录服加上在线人数功能，等后台可以查看是否还有人在线，决定是否关服
		if nIncrCnt==1  then
			tRedis:hset("Hm_ServerUsers"..tSrvInfo.nServerId,nUserId, os.date("%Y-%m-%d %H:%M %S", os.time()))
		elseif nIncrCnt==-1 then
			tRedis:hdel("Hm_ServerUsers"..tSrvInfo.nServerId,nUserId)
		end
		tRedis:exec()
		return
	end
	local sAllGaming = string.format("sAllGaming_shop%d", (nShopId or -1))

	if nIncrCnt==1  then
		tRedis:sadd("Set_"..sShopGameRoom,nUserId)
		tRedis:sadd("Set_"..sShopGame,nUserId)
		--tBase.m_MyRedisData[1].redis:sadd("Set_"..sShop,nUserId)
		tRedis:sadd("Set_"..sGame,nUserId)
		tRedis:sadd("Set_"..sGameRoom,nUserId)
		tRedis:sadd("Set_"..sAllGaming,nUserId)
		tRedis:hset("Hm_ServerUsers"..tSrvInfo.nServerId,nUserId, os.date("%Y-%m-%d %H:%M %S", os.time()))
	elseif nIncrCnt==-1 then
		tRedis:srem("Set_"..sShopGameRoom,nUserId)
		tRedis:srem("Set_"..sShopGame,nUserId)
		--tBase.m_MyRedisData[1].redis:srem("Set_"..sShop,nUserId)
		tRedis:srem("Set_"..sGame,nUserId)
		tRedis:srem("Set_"..sGameRoom,nUserId)
		tRedis:srem("Set_"..sAllGaming,nUserId)
		tRedis:hdel("Hm_ServerUsers"..tSrvInfo.nServerId,nUserId)
	end
	tRedis:exec()
end

--设置房间人数
--百人房需要显示在线人数的用到
function PublicUserInfo.SetRoomRealUserCnt(nGroupId,nGameId,nRoomId,nValue)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("group%d_game%d_room%d",nGroupId,nGameId,nRoomId)

	local n = tonumber(redis:hget(sKey,"RealUserCnt"))  or 0

	tBase.Log("设置房间人数时,原来的数量是 "..sKey.."  "..n)
	local nCount = n + nValue
	redis:hset(sKey,"RealUserCnt", nCount)

	PublicUserInfo.GetOnlineUserCount(nGroupId,nGameId,nRoomId)
end

--nOnlineCount:当前在线人数  nPassTime:距离上一次更新已经过去的时间(秒)
--返回:变化后的在线人数
local function DoChangeToOnlineCount(nOnlineCount,nPassTime)
	local nOffset =5		--偏移量
	local nChangeRange=10	--变化范围	
	local nDirection=0		--增长方向 1:整体正增长 -1:整体负增长  0:完全正增长
	--决定增长方向
	if nOnlineCount<20 then
		nDirection =0
	elseif nOnlineCount<80 then
		nDirection=1
	else
		nDirection=-1
	end
	--决定变化范围
	if nPassTime<5 then
		nOffset =0
		nChangeRange=0
	elseif nPassTime<10 then
		nOffset =5
		nChangeRange=10
	elseif nPassTime<25 then
		nOffset =7
		nChangeRange=20
	elseif nPassTime<40 then
		nOffset =10
		nChangeRange=35
	elseif nPassTime<60 then
		nOffset =10
		nChangeRange=45
	else
		nOffset =10
		nChangeRange=55
	end
	--根据变化范围与变化方向进行变化
	if nDirection==0 then
		nOnlineCount =nOnlineCount +math.random(0,nChangeRange)
	elseif nDirection==1 then
		nOnlineCount =nOnlineCount +math.random(-nChangeRange+nOffset,nChangeRange)
	elseif nDirection==-1 then
		nOnlineCount =nOnlineCount +math.random(-nChangeRange,nChangeRange-nOffset)
	end
	if nOnlineCount<20 then
		nOnlineCount =math.random(20,30)
	end
	return nOnlineCount
end

--获取房间在线人数
function PublicUserInfo.IncrRoomUser(nGroupId,nGameId,nRoomId)
	return PublicUserInfo.GetOnlineUserCount(nGroupId,nGameId,nRoomId)
end

local tOnlineCntCache ={}
--获取房间在线人数
function PublicUserInfo.GetOnlineUserCount(nGroupId,nGameId,nRoomId)
	local redis =tBase.m_MyRedisData[1].redis
	local sKey =string.format("group%d_game%d_room%d",nGroupId,nGameId,nRoomId)
	local nCurrentTime =os.time()
	local tCacheInfo =tOnlineCntCache[sKey] or {}
	local tCacheTime =tCacheInfo.UpdateTime or 0
	if (nCurrentTime-tCacheTime)<=5 then
		-- tBase.Log("_GetOnlineUserCount  无需更新 RealUserCnt :%d  OnlineCount :%d ",tCacheInfo.RealUserCnt,tCacheInfo.OnlineCount)
		return tCacheInfo.OnlineCount +(tCacheInfo.RealUserCnt or 0)
	end
	local arrRlt =redis:hmget(sKey,"OnlineCount","UpdateTime")
	local nOnlineCount =tonumber(arrRlt[1]) or 0
	local nUpdateTime =tonumber(arrRlt[2]) or 0
	local nPassTime =math.max(nCurrentTime-nUpdateTime,0)
	local nCurrentCount =DoChangeToOnlineCount(nOnlineCount,nPassTime)

	local sSetGameRoomKey =string.format("Set_game%d_room%d",nGameId,nRoomId)
	local nRealUserCnt =redis:scard(sSetGameRoomKey) 
	local tInfo ={OnlineCount=nCurrentCount,UpdateTime=nCurrentTime,RealUserCnt=nRealUserCnt}
	redis:hmset(sKey, tInfo)
	tOnlineCntCache[sKey] =tInfo
	--tBase.Log("nCurrentTime_%d nUpdateTime_%d",nCurrentTime,nUpdateTime)
	-- tBase.Log("_GetOnlineUserCount  需更新 nPassTime_%d nOnlineCount_%d nNewValue_%d nRealUserCnt_%d sKey_%s",nPassTime,nOnlineCount,nCurrentCount,nRealUserCnt,sKey)
	
	return nCurrentCount +nRealUserCnt
end

--[[
	状态1:	 维护目标下局被踢出,同时网关禁止非游戏中的维护目标进入.
	状态2:	 网关禁止除白名单外的维护目标通讯.
	其它状态:非维护状态
]]
function PublicUserInfo.IsMaintaining(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local nMaintenanceStatus =	tonumber(redis:get("Maintenance_status"))
	if nMaintenanceStatus~=1 then
		return false
	end
	local arrRlt =redis:hmget("Maintenance_target","All",string.format("Group%d",nGroupId))
	local nAllRlt =tonumber(arrRlt[1])
	local nGroupRlt =tonumber(arrRlt[2])
	if nAllRlt~=1 and nGroupRlt~=1 then
		return false
	end

	--hmset Maintenance_TimePeriod ActualStart 1576827113	--实际维护开始时间
	--hmset Maintenance_TimePeriod ActualEnd   1576827190 --实际维护结束时间

	local arrPeriod =redis:hmget("Maintenance_TimePeriod","StartTime","EndTime","ActualStart","ActualEnd")
	local sStartTime =arrPeriod[1] or "00-00-00"		--维护开始时间
	local sEndTime =arrPeriod[2] or "00-00-00"			--预计维护结束时间
	local nActualStart =tonumber(arrPeriod[3]) or 0
	local ActualEnd =tonumber(arrPeriod[4]) or 0
	local nCurrentTime =os.time()
	if (nActualStart==0 and ActualEnd==0) or (nCurrentTime>=nActualStart and nCurrentTime<=ActualEnd) then
		local sActualStart = string.format("%s",nActualStart)
    	local sActualEnd = string.format("%s",nCurrentTime)
		return true,sActualStart,sActualEnd
	end
	return false
end

--分组玩家优先匹配到全机器人的概率;返回值范围[0.0 ~100.0],分别表示0% ~100%
--用途动机:减少真人与真人匹配在一起的概率
function PublicUserInfo.ProbabilityOfPlayWithAndroid(nGroupId)
	local redis =tBase.m_MyRedisData[2].redis
	local arrRlt =redis:hmget("ProbabilityOfPlayWithAndroid","Default",string.format("Group%d",nGroupId))
	local nProbabilityOfDefault =tonumber(arrRlt[1]) or SetingConfig.nProbabilityOfDefault
	local nProbabilityOfGroup =tonumber(arrRlt[2]) or nProbabilityOfDefault
	if nProbabilityOfGroup<0 then
		nProbabilityOfGroup =0
	end
	if nProbabilityOfGroup>100 then
		nProbabilityOfGroup=100
	end
	return nProbabilityOfGroup
end

--放入元素
function PublicUserInfo.SetMember(sKey,Val)
	local r = tBase.m_MyRedisData[1].redis:sadd(sKey,Val)
	tBase.Log("SetMember sKey_"..sKey.." Val_"..Val.." result_"..r)
end

--取出元素
function PublicUserInfo.MoGetMember(sKey,Val,bGetList,bKey)
	local t = tBase.m_MyRedisData[1].redis:smembers(sKey)
	if t then
		if bKey then
			for i = 1, #t do
				local _tableId =tonumber(string.match(t[i],":(%d+)"))
				local _Findval =string.match(t[i],".+:")
				assert(_Findval~=nil, Val)
				if tonumber(Val) == _tableId then
					tBase.Log("GetMember f key sKey_"..sKey.." Val_"..Val)
					return _tableId, t[i]
				end
			end
			return 0
		end
		if bGetList then  return t end
		for i = 1, #t do
			local _tableId =tonumber(string.match(t[i],":(%d+)"))
			local _Findval =string.match(t[i],"(.+):")
			tBase.Log("_tableId=".._tableId.." _Findval=".._Findval)
			assert(_Findval~=nil, Val)
			if tostring(Val) == tostring(_Findval) then
				tBase.Log("GetMember f val sKey_"..sKey.." Val_"..Val)
				return _tableId
			end
		end
		tBase.Log("GetMember sKey_"..sKey.." E len=0 not Val")
	else
		tBase.Log("GetMember sKey_"..sKey.." not Val")
	end	
	return 0
end

--删除元素
function PublicUserInfo.DelMember(sKey,Val)
	local t = tBase.m_MyRedisData[1].redis:smembers(sKey)
	if t then 
		for i = 1, #t do
			if tostring(Val) == tostring(t[i]) then
				local r = tBase.m_MyRedisData[1].redis:srem(sKey,t[i])
				tBase.Log("DelMember sKey_"..sKey.." val_"..t[i].." r_"..r)
				return true
			end
		end
		tBase.Log("DelMember sKey_"..sKey.." E not Val")
	else
		tBase.Log("DelMember sKey_"..sKey.." not Val")
	end
	return false
end

--大小
function PublicUserInfo.ScardMember(sKey) 
	local num = tBase.m_MyRedisData[1].redis:scard(sKey)
	tBase.Log("ScardMember sKey_"..sKey.." size_"..num)
	return tonumber(num)	 
end

-- 获取牌桌分组
function PublicUserInfo.GetTableGroupId(sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local sGroupId =tRedis:hget(sKey,"nGroupId")
	return tonumber(sGroupId)
end

function PublicUserInfo.GetTableSLiveId(sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local sLiveID =tRedis:hget(sKey,"sLiveID")
	return sLiveID
end

--nAndroidCnt: 机器人数量, nUsersCnt:真人玩家数量
function PublicUserInfo.UpdateTableUserCnt(sTableId,nAndroidCnt,nUsersCnt)
	local sKey= string.format("APIOpenTale_%s",sTableId)
    local tRedis =tBase.m_MyRedisData[2].redis
	if tRedis:exists(sKey) then
		tRedis:hmset(sKey,{nAndroidCnt=nAndroidCnt,nUsersCnt=nUsersCnt})
	end
end

-- 直播开关桌数据
-- API开桌数据  Redis  {sTableId,nGameId,nRoomId,nLiveUserID}
function PublicUserInfo.API_Open_Table_InRedis(tData)
    local sKey= string.format("APIOpenTale_%s",tData.sTableId)
    local tRedis =tBase.m_MyRedisData[2].redis

	local tTableInfo={}
	tTableInfo.nTableStatus= 0     -- 0 开桌，1 关桌  
	tTableInfo.sTableId= tData.sTableId
	tTableInfo.nLiveUserID = api.Double2Int(tData.nLiveUserID)
	tTableInfo.nRoomId =  api.Double2Int(tData.nRoomId)
	tTableInfo.nGameId = api.Double2Int(tData.nGameId)
	tTableInfo.sCenterKey = tBase.m_tKey
	tTableInfo.nServerId = tSrvInfo.nServerId
	tTableInfo.sTableIdentify= tData.sTableIdentify or tData.sTableId
	tTableInfo.nGroupId = tData.nGroupId
	tTableInfo.sTableName = tData.sTableName
	tTableInfo.nTableType = tData.nTableType or 1
	tTableInfo.nDuration=tData.nDuration
	tTableInfo.sLiveID=tData.sLiveID
	tTableInfo.sPlatformID=tData.sPlatformID
	tTableInfo.nThirdPartyTableId =tData.nThirdPartyTableId
	tTableInfo.isPassWordRoom =tData.isPassWordRoom or false
	tTableInfo.nCloseTableStatus =tData.nCloseTableStatus or 0
	tTableInfo.sConfig =tData.sConfig or ""
	tTableInfo.nSrcType =tData.nSrcType
	tRedis:hmset(sKey,tTableInfo)
	tTableInfo.nClubId = tData.nClubId
	tBase.Log("_API_Open_Table_InRedis  nTableStatus 0  sKey_%s ",sKey)
	PublicUserInfo.SendToChatServer(tTableInfo)
    return true
end

-- API设置关桌
function PublicUserInfo.API_Close_Table(sTableId)    
	
	PublicUserInfo.SendToChatServer({sTableId = sTableId ,nTableStatus=1})

	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local tTableInfo={} 
	tTableInfo.nTableStatus= 1     -- 0 开桌，1 关桌   
	tRedis:hmset(sKey,tTableInfo)
	tRedis:expire(sKey,1)
	tBase.Log("_API_Close_Table   sTableId_%s 关桌   删除key_%s   ",sTableId,sKey) 
 	return 
end

-- API设置当前牌桌玩家
function PublicUserInfo.API_ChangeTable(sTableId, info)
	local sKey = string.format("APIOpenTale_%s",sTableId)
	local tRedis = tBase.m_MyRedisData[2].redis
	if tRedis:exists(sKey) then
		tRedis:hmset(sKey,{sUserInfo = info})
	end
	tBase.Log("API_ChangeTable   sTableId_%s info_%s", sTableId, info)
end

--解绑桌子主播
function PublicUserInfo.TableLiveUser_UnBind(sTableId)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
	if not tRedis:exists(sKey) then 
		tBase.Log("_TableLiveUser_UnBind  sKey: %s  is not",sKey) 	
		return
	end 
	local t ={nLiveUserID=0,sPlatformID="",sLiveID="",isPassWordRoom=false}
	tRedis:hmset(sKey,t)
end

--绑定桌子主播
function PublicUserInfo.TableLiveUser_Bind(sTableId,nLiveUserID,sPlatformID,sLiveID,isPassWordRoom)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
	if not tRedis:exists(sKey) then 
		tBase.Log("_TableLiveUser_Bind  sKey: %s  is not",sKey) 	
		return
	end 	
	local t ={nLiveUserID=nLiveUserID,sPlatformID=sPlatformID,sLiveID=sLiveID,isPassWordRoom=isPassWordRoom or false}
	tRedis:hmset(sKey,t)
end

-- API绑定解绑桌子
function PublicUserInfo.API_BingDingTable(tData)
   if tData.nType == 2 then 
		PublicUserInfo.TableLiveUser_UnBind(tData.sTableId)
	else
		tBase.Log("_API_BingDingTable nType_%d nLiveUserID_%d  sPlatformID_%s  sLiveID_%s sTableId_%s "
		,tData.nType,tData.nLiveUserID,tData.sPlatformID,tData.sLiveID,tData.sTableId)		
		PublicUserInfo.TableLiveUser_Bind(tData.sTableId,tData.nLiveUserID,tData.sPlatformID,tData.sLiveID,tData.isPassWordRoom)
   end 
end
 
-- 获取直播超时关桌 时间： 秒单位 （默认24小时）
function PublicUserInfo.GetTableCloseTime()
   local sKey = tSetingConfig.sPublicRedisKey.."ZhiBo_CloseTableTime"
   local tRedis =tBase.m_MyRedisData[2].redis
   local nCloseTime = tonumber(tRedis:get(sKey)) or 60*60*24
   return nCloseTime
end

--玩家跟投信息持久化 (多游戏服问题,不做缓存)
function PublicUserInfo.SetGameBetFollowInfo(nGameId,nUserId,tData)
	local redis =tBase.m_MyRedisData[2].redis
	local sJsonData =cjson.encode(tData)
	local sKey =string.format("UsersBetFollowInfo_%d",nGameId)
	local sSubKey =string.format("%d",nUserId)
	redis:hmset(sKey, {[sSubKey]=sJsonData})
	redis:expire(sKey,60*60*24*30)  -- 30 天过期
end

-- 恢复 永久俱乐部牌桌  聊天
function PublicUserInfo.Recover_Club_Table(sTableId)
	local sKey= string.format("APIOpenTale_%s",sTableId)
	local tRedis =tBase.m_MyRedisData[2].redis
	local tTableInfo= tRedis:hgetall(sKey)
	if not tTableInfo then
		tBase.Log("_Recover_Club_Table  sTableId_%s tTableInfo is nil ",sTableId)
		return 
	end 	
	tBase.Log("_Recover_Club_Table  sTableId_%s  恢复聊天",sTableId)
	tTableInfo.nGroupId = tonumber(tTableInfo.nGroupId)
	tTableInfo.nLiveUserID = tonumber(tTableInfo.nLiveUserID) 
	tTableInfo.nGameId = tonumber(tTableInfo.nGameId) 
	tTableInfo.nTableType = tonumber(tTableInfo.nTableType) 
	tTableInfo.nTableStatus= 0    -- 0 开桌，1 关桌   
	if not tTableInfo.sConfig then 
		tBase.Log("_Recover_Club_Table  sTableId_%s  sConfig is nil ",sTableId)
		return
	end 
    local tConfig = cjson.decode(tTableInfo.sConfig)
	tTableInfo.nClubId = math.floor(tConfig.nClubId or -1) 
	PublicUserInfo.SendToChatServer(tTableInfo)
	return 
end

-- 通知聊天服(开关桌) tTableInfo{sTableId,nTableStatus}
function PublicUserInfo.SendToChatServer(tTableInfo)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey = "TableChat_Key"
    local pSend = ProtoMgr.Backstage_pb.ReqAPI_Table()
	pSend.sTableId = tTableInfo.sTableId
	pSend.nType = 1
	pSend.nLiveUserID = 0
	pSend.nRoomId = 0
	pSend.nOpentime = os.time()
	pSend.sRequestkey = "" 
	pSend.sTableName = tTableInfo.sTableName or ""


	local sChatkey 
	local sLog = "开桌"
	-- 开桌 
	if tTableInfo.nTableStatus == 0 then
		pSend.nTableType = tTableInfo.nTableType or -1
		if tTableInfo.nTableType == 5 then   -- 俱乐部牌桌 
			if not tTableInfo.nClubId then
				tBase.Log("_SendToChatServer  开牌桌聊天_%s,nGameId_%d 非俱乐部牌桌",tTableInfo.sTableId,tTableInfo.nGameId)
				return
			end
		elseif tTableInfo.nTableType >= 0 then  -- 区块链牌桌 
			if tTableInfo.nGroupId < 0 then
				tBase.Log("_SendToChatServer  开牌桌聊天_%s,nGameId_%d  nGroupId_%d 非正式分组 ",tTableInfo.sTableId,tTableInfo.nGameId,tTableInfo.nGroupId)
				return
			end
			local arrChatOpenGame = {122}    -- 开放游戏： 目前就百家乐的OB区块链 
			local isOpen = false
			for _, nGameId in ipairs(arrChatOpenGame) do
				if nGameId == tTableInfo.nGameId then
					isOpen = true
					break
				end
			end
			if not isOpen then
				tBase.Log("_SendToChatServer  开牌桌聊天_%s,nGameId_%d 非开放游戏 ",tTableInfo.sTableId,tTableInfo.nGameId) 
				return
			end
		else
			tBase.Log("_SendToChatServer  开牌桌聊天_%s,nGameId_%d 非区块链 ",tTableInfo.sTableId,tTableInfo.nGameId) 
			return
		end
		pSend.nGroupId = tTableInfo.nGroupId 
		pSend.nLiveUserID = tTableInfo.nLiveUserID
		pSend.sConfig = tTableInfo.sConfig

		sChatkey = tRedis:hget(sKey,tTableInfo.sTableId)
		if sChatkey then 
			tBase.Log("_SendToChatServer  聊天已开 sTableId: %s  sChatkey: %s ",tTableInfo.sTableId,sChatkey)
			return
		end
		sChatkey = tBase.GetSrcKey(tname.chat,0)
		if not sChatkey then 
			tBase.Log("_SendToChatServer  开牌桌聊天: %s  sChatkey is nil",tTableInfo.sTableId)
			return
		end
		tRedis:hset(sKey,tTableInfo.sTableId,sChatkey)
		sLog = sLog .." nTableType: "..pSend.nTableType
	else
		-- 关桌
		pSend.nType = 2
		sChatkey = tRedis:hget(sKey,tTableInfo.sTableId)
		if not sChatkey then 
			tBase.Log("_SendToChatServer  关牌桌聊天: %s  sChatkey is nil",tTableInfo.sTableId)
			return
		end
   		tRedis:hdel(sKey,tTableInfo.sTableId)
		sLog = "关桌"
	end 	
	local CMD = ProtoMgr.Backstage_pb.Backstage_Proto()
	local s = tBase.GetSP().new(CMD.Main_CMD,CMD.ReqAPI_Table_CMD) 
    s:AddString(pSend:SerializeToString())
	tBase.PostToServer(sChatkey,0,s:GetData(), s:GetSize()) 
	tBase.Log("_SendToChatServer  %s  牌桌聊天: %s  sChatkey: %s ",sLog,tTableInfo.sTableId,sChatkey)
end

--玩家跟投信息
function PublicUserInfo.GetGameBetFollowInfo(nGameId,nUserId)
	local redis =tBase.m_MyRedisData[2].redis
	local sKey =string.format("UsersBetFollowInfo_%d",nGameId)
	local sSubKey =string.format("%d",nUserId)
	local sJsonData =redis:hget(sKey,sSubKey)
	local tData =nil
	if sJsonData then
		tData= cjson.decode(sJsonData)
	end
	return tData
end

-- 解析 clientid 
local function _Get_ArrTagKeyClientId(arrClientID)
	local arrTagKey = {}
	for k,sClientID in pairs(arrClientID) do		
	    local tVal = api.Split(sClientID, ":")
	    local sTagkey = tVal[1]
	    local nClientId = tonumber(tVal[2])
	    if arrTagKey[sTagkey] then 
	    	table.insert(arrTagKey[sTagkey],nClientId)
	    else
	    	arrTagKey[sTagkey] = {}
	    	table.insert(arrTagKey[sTagkey],nClientId)
	    end
	end
	return arrTagKey
end

-- 通知网关进行广播  
function PublicUserInfo._BroadcastGateway(tData)
	if #tData.arrClientID == 0 then return end
	local arrTagKey = _Get_ArrTagKeyClientId(tData.arrClientID)
	if arrTagKey then
		for sKey,arrClientID in pairs(arrTagKey) do
			-- tBase.Log("_BroadcastGateway  游戏通知网关进行广播  arrClientID_%d  sKey_%s ",#arrClientID,sKey) 
			local tClientID = {}
			for nDex,nClientID in pairs(arrClientID) do
				table.insert(tClientID,nClientID)
				if #tClientID >= 200 or nDex == #arrClientID then 
					local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWEY_BROAD)
					s:AddUint32(#tClientID)
					for nDex,nClientID in pairs(tClientID) do
						s:AddUint32(nClientID)
					end
				    s:AddBuff(tData.tPacket:GetData(), tData.tPacket:GetSize())
			        tBase.PostToServer(sKey,0,s:GetData(),s:GetSize())
					-- tBase.Log("_BroadcastGateway  游戏通知网关进行广播  tClientID_%d  sendsize_%d ",#tClientID,tData.tPacket:GetSize()) 
			        tClientID = {}
				end 
			end
		end 
	end 
end
 
-- 通知网关进行广播  
function PublicUserInfo._SendPacketGateway(tData)
	if #tData.arrClientID == 0 then return end
	local arrTagKey = _Get_ArrTagKeyClientId(tData.arrClientID)
	if arrTagKey then 
		for sKey,arrClientID in pairs(arrTagKey) do
			-- tBase.Log("_BroadcastGateway  游戏通知网关进行广播  arrClientID_%d  sKey_%s ",#arrClientID,sKey) 
			local tClientID = {}
			for nDex,nClientID in pairs(arrClientID) do
				table.insert(tClientID,nClientID)
				if #tClientID >= 200 or nDex == #arrClientID then
					local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWEY_BROAD)
					s:AddUint32(#tClientID)
					for nDex,nClientID in pairs(tClientID) do
						s:AddUint32(nClientID)
					end
				    s:AddBuff(tData.Buff, tData.nlen)
			        tBase.PostToServer(sKey,0,s:GetData(),s:GetSize())
					-- tBase.Log("_BroadcastGateway  游戏通知网关进行广播  tClientID_%d  sendsize_%d ",#tClientID,tData.tPacket:GetSize()) 
			        tClientID = {}
				end 
			end
		end 
	end 
end
 
--sTableName:非nil时，创建的是基于桌子名称的直播牌局编号,例如:"A01AAAA01"
function PublicUserInfo.CreatePaiJuID_Live(sTableName)
	return PublicUserInfo.CreatePaiJuID() 
end
  
--  牌桌总结算通知{nUserId,sTableId,sTableName,nBetSum,nWinLose }
function PublicUserInfo._SendTableSettleInfo(tData)	
    local f = function()
		local tSend = ProtoMgr.Gateway_pb.TableSettleInfo()
		tSend.nUserId = tData.nUserId
		tSend.nGold = tData.nGold
		tSend.sTableId = tData.sTableId  
		tSend.sTableName = tData.sTableName or "-1"
		tSend.nBetSum = tData.nBetSum 
		tSend.nWinLose = tData.nWinLose  
	   	local sClientID = PublicUserInfo.GetClientID_String(tData.nUserId)
	   	if not sClientID then 
			tBase.Log("_SendTableSettleInfo  nUserID_%d  sClientID is nil ",tData.nUserId)    	
	   		return
	   	end 
	    local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_REP_TableSettleInfo)
	    s:AddString(tSend:SerializeToString())       
	    tBase.PostToGateway(sClientID, s:GetData(), s:GetSize())
		-- tBase.Log("_SendTableSettleInfo  tData_%s    ",cjson.encode(tData)) 
	end
	xpcall(f,tpLog) 
    return 
end 

--写入飞行棋玩家输赢次数，总次数到数据库（新增，变化）
-- nUserID:玩家id,nWinLose:-1输，1赢
function PublicUserInfo.WritePilotWinLoseTimesToDB(nUserID,nWinLose)
	if not nUserID then
		tBase.Log("Error WritePilotWinLoseTimesToDB nUserID is nil") 
		return 
	end
	if not nWinLose or (nWinLose~=1 and nWinLose~=-1) then 
		tBase.Log("Error WritePilotWinLoseTimesToDB nWinLose is not 1 or -1")
		return 
	end
	local DbServer_pb =ProtoMgr.DbServer_pb
	local dbCmd =DbServer_pb.Db_Proto()
	
	local pSend = DbServer_pb.WritePilotWinLoseTimesReq()
	pSend.nUserId = nUserID
	pSend.sSql=string.format("Call Set_PilotWinLose_Times(%d,%d)",nUserID,nWinLose)

	local s = tBase.GetSP().new(dbCmd.Main_CMD,dbCmd.WritePilotWinLoseTimesReq_CMD)
    s:AddString(pSend:SerializeToString())
    tBase.PostDatasByType(tname.db, 0, nUserID, s:GetData(), s:GetSize())
end

--是否需要进行安全密码校验
--@return false:不需要 true:需要
function PublicUserInfo.IsNeedCheckSafePassWard(nUserId)
	local tUserInfo = PublicUserInfo.GetUserInfo(nUserId)
	if tUserInfo then
		if tonumber(tUserInfo.nOpenProtection)==1 then
			return true
		end
	end
	return false
end

--进行安全密码校验
--@return 0:校验失败 1:校验成功 
function PublicUserInfo.CheckSafePassWard(nUserId,sSafePassWard)
	local tUserInfo = PublicUserInfo.GetUserInfo(nUserId)
	if tUserInfo then
		if tUserInfo.sSafePassWard==sSafePassWard then
			return 1
		end
	end
	return 0
end

--设置安全密码校验结果
function PublicUserInfo.SetCheckSafePassWardResult(nUserId,nResult)
   	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey = "CheckSafePassWardResult"
	local sSubKey = string.format("nUserId_%d",nUserId)
	tRedis:hset(sKey,sSubKey,nResult)
end

--获取安全密码校验结果
--@return nil:没有进行校验 0:校验失败 1:校验成功
function PublicUserInfo.GetCheckSafePassWardResult(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey = "CheckSafePassWardResult"
	local sSubKey = string.format("nUserId_%d",nUserId)
	local sRlt = tRedis:hget(sKey,sSubKey)
	return tonumber(sRlt)
end

--删除安全密码校验结果
function PublicUserInfo.DelCheckSafePassWardResult(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey = "CheckSafePassWardResult"
	local sSubKey = string.format("nUserId_%d",nUserId)
	tRedis:hdel(sKey,sSubKey)
end

--保存玩家上一次登录的俱乐部中心服
function PublicUserInfo.SetUserEnterClubCenter(nUserId,nCenterId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey = "UserEnterClubCenter"
	local sSubKey = string.format("nUserId_%d",nUserId)
	tRedis:hset(sKey,sSubKey,nCenterId)
end

--获取玩家上一次登录的俱乐部中心服
function PublicUserInfo.GetUserEnterClubCenter(nUserId)
	local tRedis =tBase.m_MyRedisData[1].redis
	local sKey = "UserEnterClubCenter"
	local sSubKey = string.format("nUserId_%d",nUserId)
	local sRlt = tRedis:hget(sKey,sSubKey)
	return tonumber(sRlt)
end


-------------------------------------------用户财产操作  Start----------------------------------------
-----------------------------------------------------------------------------------------------------
function PublicUserInfo.LocKPrint(nUserId,nLockGold,nItemId)
	local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
	tBase.Log("_LocKPrint %d Lock nUserId:%d nLockGold:%.2f nItemId: %d  ",dex,nUserId,nLockGold,nItemId or -1)
end
function PublicUserInfo.UnLocKPrint(nUserId,nUnLockGold,nItemId)
	local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
	tBase.Log("_UnLocKPrint  %d UnLock nUserId:%d nUnLockGold:%.2f nItemId: %d  ",dex,nUserId,nUnLockGold,nItemId or -1 )
end
function PublicUserInfo.LocKFailPrint(nUserId,nLockGold,nItemId)
	local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
	local sTip = cjson.encode(tPublicUserGold.GetUserGoldInfo(nUserId,nItemId))	
	tBase.Log("_LocKFailPrint %d LockFail nUserId:%d nLockGold:%.2f sTip:%s nItemId:%d  ",dex,nUserId,nLockGold,sTip,nItemId or -1)
end
function PublicUserInfo.UnLocKFailPrint(nUserId,nUnLockGold,nItemId)
	local dex =tBase.m_MyRedisData[1].redis:incr("ForPrintTest")
	local sTip = cjson.encode( tPublicUserGold.GetUserGoldInfo(nUserId,nItemId))
	tBase.Log("_UnLocKFailPrint %d UnLockFail nUserId:%d nUnLockGold:%.2f sTip:%s nItemId: %d  ",dex,nUserId,nUnLockGold,sTip,nItemId)
end

local function _GetGoldKey(nItemId) 
    return string.format("nGold_%d",nItemId)
end

-- 发送 玩家财富数据
function PublicUserInfo.Send_UserGold(nUserId,nGold,nItemId,nChange)
	local sClientID = PublicUserInfo.GetClientID_String(nUserId)
	if not sClientID then return end
	local f = function()
		local tSend = ProtoMgr.Gateway_pb.CorrCapital()
		tSend.nUserId =nUserId
		tSend.nGold = api.DealFloat(nGold)
		tSend.nItemId = nItemId or -1
		tSend.nChange = api.DealFloat(nChange)
	    local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_CORR_CAPITAL)
	    s:AddString(tSend:SerializeToString())
	    tBase.PostToClient(sClientID, s:GetData(), s:GetSize())
	end
	xpcall(f,tpLog)
    return
end

--检查玩家金币是否低于后台设定值
function PublicUserInfo.CheckGoldLessThanStandard(nUserId,nGold,nItemId)
	local  sClientID = PublicUserInfo.GetClientID_String(nUserId)
	if not sClientID then return end

	local tUserInfo = PublicUserInfo.GetAllUserInfo(nUserId)
    local nGroupId = tonumber(tUserInfo.nGroupId) or 0

	local nGoldStandard = PublicRedis.GetGoldStandard(nGroupId)
	if nGold-nGoldStandard<0 and math.abs(nGold-nGoldStandard)>=1e-6 then
		--低于后台设定值，需要通知前端
		tBase.Log("CheckGoldLessThanStandard 低于后台设定值，需要通知前端 nUserId_%d nGold:%f nGoldStandard:%f",nUserId,nGold,nGoldStandard)
		local f = function()
			local tSend = ProtoMgr.Lobby_pb.UserGoldLessStandardNotify()
			tSend.nUserId =nUserId
			tSend.nGold = nGold
			tSend.nItemId = nItemId or -1 
			tSend.nStandard = nGoldStandard
			local s = tBase.GetSP().new(ProtoMgr.LobbyPro.Main_CMD, ProtoMgr.LobbyPro.UserGoldLessStandardNotify_CMD)
			s:AddString(tSend:SerializeToString())       
			tBase.PostToClient(sClientID, s:GetData(), s:GetSize())
		end	
		xpcall(f,tpLog)
	end
end

--用户金币,从数据库同步到redis
--用到的地方 1：旧方式充值,先改db再设置redis金币 2:玩家账号登陆与注册设置redis金币
function PublicUserInfo.UpdateUserGold(nUserID,nGold,nItemId,isNoDbCopy)
	if PublicUserInfo.IsComAndroid(nUserID) then
		PublicUserInfo.UpdateComAndroidUserInfo({nUserID=nUserID,nGold=nGold})
		return true
	end
	if not nItemId then
		nItemId = 1
		tBase.Log("_UpdateUserGold  default nItemId nUserId_%d ",nUserID)
	end
	if not isNoDbCopy then	--数据库中有拷贝的用户才持久化其金币
		if not PublicUserInfo._InitAsset(nUserID,nGold,nItemId,1) then
			return
		end
	end
	--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
	local sKey =string.format("PublicUserInfo_%d",nUserID)
	local nGoldKey = _GetGoldKey(nItemId)
	tBase.m_MyRedisData[1].redis:hset(sKey,nGoldKey,nGold)
	return true
end

-- 获取玩家财产
function PublicUserInfo.GetUserTreasure(nUserID,nItemId)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return PublicUserInfo.GetComAndroidUserInfo(nUserID)
	end
	if not nItemId then
		nItemId = 1
		tBase.Log("_GetUserTreasure  nUserId_%d  default nItemId ",nUserID)
	end
	local tGoldInfo =tPublicUserGold.GetUserGoldInfo(nUserID,nItemId) or {}
	local tUserTreasure = {}
	tUserTreasure.nGold = api.Floor_2(tGoldInfo.nGold or 0)--金币 
	tUserTreasure.nItemId  = nItemId
	if tUserTreasure.nGold< 0 and math.abs(tUserTreasure.nGold)>1e-6 then
		tBase.Log("_GetUserTreasure  ErrorMsg is negative,nUserId:%d nGold:%.2f  nItemId_%d ",nUserID,tUserTreasure.nGold,nItemId)
	end
	return tUserTreasure
end

-- 获取玩家金币
function PublicUserInfo.Get_User_Gold(nUserID,nItemId)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return PublicUserInfo.GetComAndroidUserGold(nUserID)
	end
	if not nItemId then
		nItemId = 1
		tBase.Log("Get_User_Gold  default nItemId nUserId_%d ",nUserID)
	end
    local tUserTreasure = PublicUserInfo.GetUserTreasure(nUserID,nItemId) or {}
	return tUserTreasure.nGold
end

function PublicUserInfo.Get_User_UnLockGold(nUserID,nItemId)
	if PublicUserInfo.IsComAndroid(nUserID) then
		return PublicUserInfo.GetComAndroidUserGold(nUserID)
	end
	if not nItemId then
		nItemId = 1
		tBase.Log("Get_User_UnLockGold  default nItemId nUserId_%d ",nUserID)
	end
	local tGoldInfo =tPublicUserGold.GetUserGoldInfo(nUserID,nItemId)
	return (tGoldInfo.nGold - tGoldInfo.nFreezeGoldSum),tGoldInfo
end

--同步reids 和 数据库  玩家财富数据   h和道具数据
--tData = {nUserID=nUserId, nItemID=1,nDel= 0 ( + )  ,
--nSourceType = 数据来源:  具体参考此表 Record.User_Treasure_Record  新增加需要添加类型 
-- isNotCheck 不检测破产补助} 
--返回:true(成功), false(失败)
function PublicUserInfo.ChangeUserTreasure(tData)
	if PublicUserInfo.IsComAndroid(tData) then
		PublicUserInfo.ChangeComAndroidGold(tData)
		return true
	end
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("_ChangeUserTreasure  ErrorMsg  redis is nil ")
		return false
	end
	local nUserId = api.Double2Int(tData.nUserID)
	local nItemId = tData.nItemID
	local nDel = api.Floor_2(tData.nDel or 0)
	local nSourceType =tData.nSourceType or 0
	local nRoomId = tData.nRoomId or 0
	local sTableId = tData.sTableId or ""
	local sPaiJuId = tData.sPaiJuId or ""
	local sOpUserName = tData.nOpUserName or ""
	local nOpUserId = tData.nOpUserId or 0
	if nSourceType == 100012 then
		tData.exData = {
			RedId = tData.nOpUserId,
			nUserId = 888,
			nName = sOpUserName
		}
		nOpUserId = 888
    nSourceType = 100007
	end

	--更新金币到redis
	local isSuccee,sErr,nGoldAfterChange =tPublicUserGold.Change(nUserId,nDel,nItemId)
	if not isSuccee then
		local sUserGoldInfo =cjson.encode(tPublicUserGold.GetUserGoldInfo(nUserId,nItemId))
		tBase.Log("_ChangeUserTreasure ErrorMsg  ChangGold Fail,sErr:%s nUserId:%d nDel:%.2f,nSourceType:%d,nRoomId:%d sUserGoldInfo:%s nItemId: %d",
		sErr,nUserId,nDel,nSourceType,nRoomId,sUserGoldInfo,nItemId)
		-- assert(false,"扣款失败 ")
		return false
	end
	--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
	local sKey =string.format("PublicUserInfo_%d",nUserId)
	local nGoldKey = _GetGoldKey(nItemId)
	tBase.m_MyRedisData[1].redis:hset(sKey,nGoldKey,nGoldAfterChange)

	--更新金币到数据库
	PublicUserInfo._ChangeGoldToDb(nUserId,nDel,nItemId,nSourceType,nRoomId,tData.nShopId,sOpUserName,nOpUserId, sTableId,
		sPaiJuId,tData.exData)
	--通知用户金币改变了
	if not tData.nNoNotice then
		PublicUserInfo.Send_UserGold(nUserId,nGoldAfterChange,nItemId,nDel)
	end
	if not tData.isNotCheck then
		--检查玩家金币是否低于后台设定值
		PublicUserInfo.CheckGoldLessThanStandard(nUserId,nGoldAfterChange,nItemId)
	end
	return true
end


-- 
function PublicUserInfo.ChangeUserTreasureWithRedLock(tData,redLock)
	redLock = tonumber(redLock) or 0
	if PublicUserInfo.IsComAndroid(tData) then
		PublicUserInfo.ChangeComAndroidGold(tData)
		return true
	end
	if tBase.m_MyRedisData[1].redis == nil then
		tBase.Log("_ChangeUserTreasure  ErrorMsg  redis is nil ")
		return false
	end
	local nUserId = api.Double2Int(tData.nUserID)
	local nItemId = tData.nItemID
	local nDel = api.Floor_2(tData.nDel or 0)
	local nSourceType =tData.nSourceType or 0
	local nRoomId = tData.nRoomId or 0
	local sTableId = tData.sTableId or ""
	local sPaiJuId = tData.sPaiJuId or ""
	local sOpUserName = tData.nOpUserName or ""
	local nOpUserId = tData.nOpUserId or 0
	if nSourceType == 100012 then
		tData.exData = {
			RedId = tData.nOpUserId,
			nUserId = 888,
			nName = sOpUserName
		}
		nOpUserId = 888
    nSourceType = 100007
	end

	--更新金币到redis
	local isSuccee,sErr,nGoldAfterChange =tPublicUserGold.ChangeWithFreeze(nUserId,nDel,redLock, nItemId)
	if not isSuccee then
		local sUserGoldInfo =cjson.encode(tPublicUserGold.GetUserGoldInfo(nUserId,nItemId))
		tBase.Log("_ChangeUserTreasure ErrorMsg  ChangGold Fail,sErr:%s nUserId:%d nDel:%.2f,nSourceType:%d,nRoomId:%d sUserGoldInfo:%s nItemId: %d",
		sErr,nUserId,nDel,nSourceType,nRoomId,sUserGoldInfo,nItemId)
		-- assert(false,"扣款失败 ")
		return false
	end
	--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
	local sKey =string.format("PublicUserInfo_%d",nUserId)
	local nGoldKey = _GetGoldKey(nItemId)
	tBase.m_MyRedisData[1].redis:hset(sKey,nGoldKey,nGoldAfterChange)

	--更新金币到数据库
	PublicUserInfo._ChangeGoldToDb(nUserId,nDel,nItemId,nSourceType,nRoomId,tData.nShopId,sOpUserName,nOpUserId, sTableId,
		sPaiJuId,tData.exData)
	--通知用户金币改变了
	if not tData.nNoNotice then
		PublicUserInfo.Send_UserGold(nUserId,nGoldAfterChange,nItemId,nDel)
	end
	if not tData.isNotCheck then
		--检查玩家金币是否低于后台设定值
		PublicUserInfo.CheckGoldLessThanStandard(nUserId,nGoldAfterChange,nItemId)
	end
	return true
end
--加锁用户金币;用于判断玩家是否够金币下注
--参数:nUserId(用户id) ,nGoldToLock(加锁的金币数量,>=0)
--返回: true(成功), false(失败)
function PublicUserInfo.Gold_Lock(nUserId,nGoldToLock,nItemId)
	if not nItemId then
		nItemId = 1
		tBase.Log("Gold_Lock  default nItemId nUserId_%d ",nUserId)
	end
	if PublicUserInfo.IsComAndroid(nUserId) then
		local nGold =PublicUserInfo.Get_User_Gold(nUserId,nItemId)
		return (not (nGold<nGoldToLock and math.abs(nGold-nGoldToLock)>1e-6))
	end
	local isSuccee,sErr,nCurGold = tPublicUserGold.Lock(nUserId,nGoldToLock,nItemId)
	return isSuccee,sErr,nCurGold
end
--解锁用户金币 ;下注不成功时解锁被锁金币,玩家下庄时解锁金币
--参数:nUserId(用户id) ,nGoldToLock(解锁的金币数量,>=0) 
--返回: true(成功), false(失败)
function PublicUserInfo.Gold_UnLock(nUserId,nGoldToUnLock,nItemId,isGame)
	if PublicUserInfo.IsComAndroid(nUserId) then
		return true,"succee"
	end
	if not nItemId then
		nItemId = 1
		tBase.Log("Gold_UnLock  default nItemId nUserId_%d ",nUserId)
	end
	local isSuccee,sErr =tPublicUserGold.UnLock(nUserId,nGoldToUnLock,nItemId,1,isGame)
	return isSuccee,sErr
end
--解锁同时扣减等量用户金币; 用于下注成功时
--参数:nUserId(用户id) ,nGoldToUnLockAndMinus(解锁与扣减的金币数量,>=0) 
--返回: true(成功), false(失败)
function PublicUserInfo.UnLockAndMinus(nUserId,nGoldToUnLockAndMinus,nSourceType,nRoomId,nItemId)
	if not nItemId then
		nItemId = 1
		tBase.Log("UnLockAndMinus  default nItemId nUserId_%d ",nUserId)
	end
	local nGoldToUnLockAndMinus =api.Floor_2(nGoldToUnLockAndMinus)
	if PublicUserInfo.IsComAndroid(nUserId) then
		PublicUserInfo.ChangeUserTreasure({nUserID=nUserId,nItemID=nItemId,nDel=-nGoldToUnLockAndMinus})
		return true,"succee"
	end
	local isSuccee,sErr,nGoldAfterChange =tPublicUserGold.UnLockAndMinus(nUserId,nGoldToUnLockAndMinus,nItemId)
	if isSuccee and nGoldAfterChange~=nil then
		local nSourceType =nSourceType or -1
		local nRoomId =nRoomId or -1
		--更新金币到数据库
		PublicUserInfo._ChangeGoldToDb(nUserId,-nGoldToUnLockAndMinus,nItemId,nSourceType,nRoomId)
		
		--通知用户金币改变了
		PublicUserInfo.Send_UserGold(nUserId,nGoldAfterChange,nItemId,-nGoldToUnLockAndMinus)

		--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
		local sKey =string.format("PublicUserInfo_%d",nUserId)
		local nGoldKey = _GetGoldKey(nItemId)
		tBase.m_MyRedisData[1].redis:hset(sKey,nGoldKey,nGoldAfterChange)
	end
	return isSuccee,(sErr or ""),nGoldAfterChange
end

--锁住玩家剩下能锁住的金币(前提条件是该金币不少于nNotLessThan); 用于玩家上庄时
--返回:本次锁成功的金币数
function PublicUserInfo.Gold_LockAllWhen(nUserId,nNotLessThan,nItemId)
	if not nItemId then 
		nItemId = 1 
		tBase.Log("Gold_LockAllWhen  default nItemId nUserId_%d ",nUserId)    
	end 	 
	if PublicUserInfo.IsComAndroid(nUserId) then
		local nGold =PublicUserInfo.Get_User_Gold(nUserId,nItemId)
		if nGold>=nNotLessThan then
			return nGold
		else	
			return 0
		end
	end
	local isSuccee,sErr,nGoldLock =tPublicUserGold.LockAllWhen(nUserId,nNotLessThan,nItemId) 
	return nGoldLock
end
--结算且重新锁定玩家金币值为(nLockGold+nChange);	用于庄家结算
--参数:nLockGold(当前玩家正在使用的被锁金币),nChange(输赢值)
--返回:true(成功),false(失败)
function PublicUserInfo.Gold_ChangeAndReLock(nUserId,nLockGold,nChange,nSourceType,nRoomId,nItemId,sTableId,sPaiJuId,nNoNotice)
	if not nItemId then
		nItemId = 1
		tBase.Log("Gold_ChangeAndReLock  default nItemId nUserId_%d ",nUserId)
	end
	local nChange =api.Floor_2(nChange)
	if PublicUserInfo.IsComAndroid(nUserId) then
		PublicUserInfo.ChangeUserTreasure({nUserID=nUserId,nItemID=nItemId,nDel=nChange})
		return true,"succee",nChange
	end
	local isSuccee,sErr,nGoldAfterChange =tPublicUserGold.ChangeAndReLock(nUserId,nLockGold,nChange,nItemId)
	if isSuccee then
		local nSourceType =nSourceType or -1
		local nRoomId =nRoomId or -1
		--更新金币到数据库
		PublicUserInfo._ChangeGoldToDb(nUserId,nChange,nItemId,nSourceType,nRoomId, nil, nil, nil,sTableId,sPaiJuId)
		--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
		local sKey =string.format("PublicUserInfo_%d",nUserId)
		local nGoldKey = _GetGoldKey(nItemId)
		tBase.m_MyRedisData[1].redis:hset(sKey,nGoldKey,nGoldAfterChange)
		--通知用户金币改变了
		if not nNoNotice then
			PublicUserInfo.Send_UserGold(nUserId,nGoldAfterChange,nItemId,nChange)
		end
		--检查玩家金币是否低于后台设定值
		PublicUserInfo.CheckGoldLessThanStandard(nUserId,nGoldAfterChange,nItemId)
	else
		local tGoldInfo =tPublicUserGold.GetUserGoldInfo(nUserId,nItemId)
		tBase.LogT("_Gold_ChangeAndReLock Fail:",{nUserId=nUserId,tGoldInfo=tGoldInfo,nLockGold=nLockGold,nChange=nChange,nItemId=nItemId,sErr=sErr})
	end
	return isSuccee,"",nChange
end


function PublicUserInfo.Gold_ChangeAndReLockWithPenalty(nUserId,nLockGold,nChange,nSourceType,nRoomId,nItemId,sTableId,sPaiJuId)
	if not nItemId then
		nItemId = 1
		tBase.Log("Gold_ChangeAndReLock  default nItemId nUserId_%d ",nUserId)
	end
	local nChange =api.Floor_2(nChange)
	
	local nSourceType =nSourceType or -1
	local nRoomId =nRoomId or -1
	--更新金币到数据库
	PublicUserInfo._ChangeGoldToDb(nUserId,nChange,nItemId,nSourceType,nRoomId, nil, nil, nil,sTableId,sPaiJuId)
	return
end

--扣除外部未加锁金币  目前用于保险扣除
--参数:nChange(输赢值)
--返回:true(成功),false(失败)
function PublicUserInfo.Gold_Change(nUserId,nChange,nSourceType,nRoomId,nItemId,sTableId,sPaiJuId,exData,nNoNotice)
	if not nItemId then
		nItemId = 1
		tBase.Log("Gold_Change  default nItemId nUserId_%d ",nUserId)
	end
	nChange = api.Floor_2(nChange)
	if PublicUserInfo.IsComAndroid(nUserId) then
		PublicUserInfo.ChangeUserTreasure({nUserID=nUserId,nItemID=nItemId,nDel=nChange})
		return true, nChange
	end
	--更新金币到redis
	local isSuccee,sErr,nGoldAfterChange = tPublicUserGold.Change(nUserId, nChange,nItemId)
	if not isSuccee then
		local sUserGoldInfo = cjson.encode(tPublicUserGold.GetUserGoldInfo(nUserId,nItemId))
		tBase.Log("Gold_Change ErrorMsg  ChangGold Fail,sErr:%s nUserId:%d nDel:%.2f,nSourceType:%d,nRoomId:%d sUserGoldInfo:%s nItemId: %d",
		sErr,nUserId,nChange,nSourceType,nRoomId,sUserGoldInfo,nItemId)
		-- assert(false,"Gold_Change 扣款失败")
		return false
	end
	--更新到非持久化redis(仅为兼容起见,最终以持久化redis为准)
	local sKey =string.format("PublicUserInfo_%d",nUserId)
	local nGoldKey = _GetGoldKey(nItemId)
	tBase.m_MyRedisData[1].redis:hset(sKey,nGoldKey,nGoldAfterChange)

	--更新金币到数据库
	PublicUserInfo._ChangeGoldToDb(nUserId,nChange,nItemId,nSourceType,nRoomId,-1,"",nil, sTableId, sPaiJuId, exData)
	--通知用户金币改变了
	if not nNoNotice then
		PublicUserInfo.Send_UserGold(nUserId,nGoldAfterChange,nItemId,-nChange)
	end
	return isSuccee, nChange
end

--解锁被本服加锁的所有用户金币. (服务器启动时用)                    
function PublicUserInfo.UnLockServAllUsersGold()
	local nCntUnLockUser =tPublicUserGold.UnLockUsersGold()
	PublicUserInfo.UnLocKPrint(-1,-1)
	return nCntUnLockUser
end

-- 解锁 本服用户金币
function PublicUserInfo.UnLockAll(nUserId)
	if PublicUserInfo.IsComAndroid(nUserId) then
		return true,"succee"
	end
	local isSuccee,sErr =tPublicUserGold.UnLockAll(nUserId)
	if isSuccee then
		PublicUserInfo.UnLocKPrint(nUserId,-1)
	else
		PublicUserInfo.UnLocKFailPrint(nUserId,-1)
	end
	return isSuccee,sErr
end
  
--更新金币到数据库 (私有函数)
function PublicUserInfo._ChangeGoldToDb(nUserId,nGoldChange,nItemId,nSourceType,nRoomId,nShopId,nOpUserName,nOpUserId, sTableId, sPaiJuId,exData)
	if not nItemId then
		nItemId = 1
		tBase.Log("_ChangeGoldToDb  默认金币 nUserId_%d ",nUserId)
	end
	local nChannel = nShopId or PublicUserInfo.Get_User_SHopId(nUserId) or -1
	nSourceType = nSourceType or -1
	nRoomId =nRoomId or -1
	exData = exData or {}
	if type(exData) == "table" then
	else
		exData = {}
	end
	exData = cjson.encode(exData)
	local sSql =string.format("Call WriteUserTreasure2(%d,%d,%d,%.3f,%d,%d,'%s',%d,'%s','%s','%s')",nUserId,nChannel,nItemId,nGoldChange,nSourceType,nRoomId,nOpUserName or "",nOpUserId or 0, sTableId or "", sPaiJuId or "", exData)
	local pSend = ProtoMgr.PubProto_pb.RUP_WriteTreasure()
	pSend.sSql=sSql
	local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_WRITETREASURE)
    s:AddString(pSend:SerializeToString())
	tBase.PostDatasByType(tname.db, 0, nUserId, s:GetData(), s:GetSize())
end
 
-- 初始化资产
function PublicUserInfo._InitAsset(nUserId,nGold,nItemId,nAssetType)
	local isSuccee,sErr,nCurGold = tPublicUserGold.Init(nUserId,nGold,nItemId,nAssetType)
	if not isSuccee then
		tBase.Log("_InitAsset Init User Gold Fail,sErr:%s,nUserId:%d nGold:%.2f nItemId: %d nAssetType: %d  ",sErr,nUserId,nGold,nItemId,nAssetType)		
	end
	return isSuccee,sErr,nCurGold
end

-- 处理离线玩家金币
function PublicUserInfo.ChangeUserDbGold(nUserId,nGoldChange,nItemId,nSourceType,nRoomId,nOpUserName,nOpUserId, sTableId, sPaiJuId, exData)
	if not nItemId then
		nItemId = 1
		tBase.Log("_ChangeGoldToDb  默认金币 nUserId_%d ",nUserId)
	end
	local nChannel = -1
	nSourceType = nSourceType or -1
	nRoomId =nRoomId or -1
	exData = exData or {}
    exData = cjson.encode(exData)
	local sSql =string.format("Call WriteUserTreasure2(%d,%d,%d,%.3f,%d,%d,'%s',%d,'%s','%s','%s')",nUserId,nChannel,nItemId,nGoldChange,nSourceType,nRoomId,nOpUserName or "",nOpUserId or 0, sTableId or "", sPaiJuId or "",exData)
	local pSend = ProtoMgr.PubProto_pb.RUP_WriteTreasure()
	pSend.sSql=sSql
	local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_WRITETREASURE)
    s:AddString(pSend:SerializeToString())
	tBase.PostDatasByType(tname.db, 0, nUserId, s:GetData(), s:GetSize())
end
 
----------------------------- 俱乐部总资产操作 ----------------------------------------

-- 获取 俱乐部 总资产
function PublicUserInfo._GetClubSumAsset(nClubId,nItemId)
	local nAssetType = 2      -- 俱乐部总资产类型
	local nItemId = nItemId or nClubId   -- 俱乐部总资产 Id  	
	local tGoldInfo =tPublicUserGold.GetUserGoldInfo(nClubId,nItemId,nAssetType)
	return (tGoldInfo.nGold -tGoldInfo.nFreezeGoldSum),tGoldInfo
end 

-- 初始化俱乐部总资产
function PublicUserInfo._InitClubSumAsset(nClubId,nClubGold,nItemId)
	local nAssetType = 2      -- 俱乐部总资产类型
	local nItemId = nItemId or nClubId   -- 俱乐部总资产 Id 
	local isSuccee,sErr,nCurGold = PublicUserInfo._InitAsset(nClubId,nClubGold,nItemId,2)
	if not isSuccee then 
		tBase.Log("_InitClubSumAsset  Fail ,nClubId:%d nClubGold:%.2f  sErr: %s  nCurGold_%f",nClubId,nClubGold,sErr,nCurGold)	
	end 
	return isSuccee,sErr,nCurGold 
end

-- 对非加锁 俱乐部总资产  进行增减操作 :
-- 参数:{ nClubId,nChange,nSourceType：操作类型,nMemberId:成员id,nHandleId: 管理员id}
--返回: true(成功), false(失败)
function PublicUserInfo.ChangeClubSumAsset(tData)
	local nAssetType = 2      -- 俱乐部总资产类型 
	local nClubId = tData.nClubId 
	if nClubId <= 0 then 
		tBase.Log("_ChangeClubAsset  nClubId is Error  %s ",cjson.encode(tData))		
		return
	end 
	local nChange = tData.nChange
	local nSourceType = tData.nSourceType
	local nMemberId = tData.nMemberId or 0 
	local nHandleId = tData.nHandleId or 0
	local nItemId = tData.nItemId or nClubId
	local isSuccee,sErr,nGoldAfterChange = tPublicUserGold.Change(nClubId,nChange,nItemId,nAssetType)
	if not isSuccee then
		local nClubGold,tGoldInfo = PublicUserInfo._GetClubSumAsset(nClubId,nItemId) 
		local sUserGoldInfo = cjson.encode(tGoldInfo)  
		tBase.Log("_ChangeClubAsset  ErrorMsg  ChangGold Fail,sErr:%s nClubId:%d nChange:%.2f,nClubGold_%f ,sUserGoldInfo:%s",sErr,nClubId,nChange,nClubGold,sUserGoldInfo or "-1")
		return false
	end
	tBase.Log("_ChangeClubAsset  Change Success  %s ",cjson.encode(tData))
	-- 更新数据库 
	PublicUserInfo._ChangeAssetToDb(nClubId,nChange,nSourceType,nMemberId,nHandleId,nItemId)	
	return true 
end

-- 加锁 俱乐部总资产：  参数:nClubId,nGoldToLock(加锁的金币数量,>=0)
--返回: true(成功), false(失败)
function PublicUserInfo.LockClubSumAsset(nClubId,nClubGoldToLock,nItemId) 
	if nClubId <= 0 then 
		tBase.Log("_LockClubSumAsset  nClubId is Error  %d ",nClubId)		
		return
	end 
	local nAssetType = 2      -- 俱乐部总资产类型
	local nItemId = nItemId or nClubId   -- 俱乐部总资产 Id  
	local isSuccee,sErr,nCurGold = tPublicUserGold.Lock(nClubId,nClubGoldToLock,nItemId,nAssetType) 
	return isSuccee,sErr,nCurGold
end

-- 解锁 俱乐部总资产： 参数:nClubId,nClubGoldToUnLock(解锁的金币数量,>=0) 
--返回: true(成功), false(失败)
function PublicUserInfo.UnLockClubSumAsset(nClubId,nClubGoldToUnLock,nItemId)
	if nClubId <= 0 then
		tBase.Log("_UnLockClubSumAsset  nClubId is Error  %d ",nClubId)
		return
	end
	local nAssetType = 2      -- 俱乐部总资产类型
	local nItemId = nItemId or nClubId   -- 俱乐部总资产 Id 
	local isSuccee,sErr =tPublicUserGold.UnLock(nClubId,nClubGoldToUnLock,nItemId,nAssetType)
	return isSuccee,sErr
end

--解锁同时扣减等量俱乐部总资产;  -参数:nClubId ,nGoldToUnLockAndMinus(解锁与扣减的金币数量,>=0) 
--返回: true(成功), false(失败)
function PublicUserInfo.UnLockAndMinusClubSumAsset(nClubId,nClubGoldToUnLockAndMinus,nSourceType,nMemberId,nHandleId,nItemId)
	if nClubId <= 0 then 
		tBase.Log("_UnLockAndMinusClubSumAsset  nClubId is Error  %d ",nClubId)		
		return
	end 	
	local nAssetType = 2      -- 俱乐部总资产类型
	local nItemId = nItemId or nClubId   -- 俱乐部总资产 Id  	
	local nGoldToUnLockAndMinus = api.Floor_2(nClubGoldToUnLockAndMinus)
	local isSuccee,sErr,nGoldAfterChange =tPublicUserGold.UnLockAndMinus(nClubId,nGoldToUnLockAndMinus,nItemId,nAssetType) 
	if isSuccee then 
		PublicUserInfo._ChangeAssetToDb(nClubId,-nClubGoldToUnLockAndMinus,nSourceType,nMemberId,nHandleId,nItemId)	
	end 
	return isSuccee,(sErr or ""),nGoldAfterChange
end

-- 修改资产通知俱乐部 
function PublicUserInfo._ChangeAssetToDb(nClubId,nChange,nSourceType,nMemberId,nHandleId,nItemId)
	nItemId = nItemId or nClubId
	nMemberId = nMemberId or 0
	nHandleId = nHandleId or 0	
    local sSql =string.format('Call Club_AssetWrite(%d,%f,%d,%d,%d,%d)',nClubId,nChange,nSourceType,nMemberId,nHandleId,nItemId) 
	local DbServerClub_pb =ProtoMgr.DbServerClub_pb
	local dbCmd =DbServerClub_pb.Db_ClubProto()	 
	local pSend = DbServerClub_pb.ClubAssetChangeRsq()
	pSend.sSql=sSql	
	local s = tBase.GetSP().new(dbCmd.Main_CMD,dbCmd.ClubAssetChangeRsq_CMD)  
    s:AddString(pSend:SerializeToString())
	tBase.PostDatasByType(tname.db,0,nClubId, s:GetData(), s:GetSize())  	 
end

--保存玩家上一次登录的俱乐部
function PublicUserInfo.SetUserLastEnterClub(nUserId,nClubId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local sSubKey = "nLastClubId"
	local redis = tBase.m_MyRedisData[1].redis
	redis:hset(sKey,sSubKey,tostring(nClubId))
end

--获取玩家上一次登录的俱乐部
function PublicUserInfo.GetUserLastEnterClub(nUserId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local sSubKey = "nLastClubId"
	local redis = tBase.m_MyRedisData[1].redis
	local sRlt = redis:hget(sKey,sSubKey)
	local nLastClubId = tonumber(sRlt)
	return nLastClubId
end

--删除玩家上一次登录的俱乐部
function PublicUserInfo.DelUserLastEnterClub(nUserId)
	local sKey = "PublicUserInfo_"..api.Double2Int(nUserId)
	local sSubKey = "nLastClubId"
	local redis = tBase.m_MyRedisData[1].redis
	redis:hdel(sKey,sSubKey)
end

-- 切换网关 用户缓存的服务器 key 
function PublicUserInfo._SwicthGateWayServerKey(sClientID,nUserId,nCenterServerId,stypename,sServerKey,Data,len) 
    local tVal = publicApi.Split(sClientID, ":")
    local sGateKey = tVal[1]
    local nClientId = tonumber(tVal[2])   
    local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_SwitchGateWayServerkey)
    s:AddUint32(nUserId)
    s:AddUint32(nClientId)
    s:AddUint32(nCenterServerId)
    s:AddString(stypename)      
    s:AddString(sServerKey)   
    s:AddBuff(Data,len)
    tBase.PostToServer(sGateKey, nClientId, s:GetData(),s:GetSize()) --转发消息到网关   
	tBase.Log("_SwicthGateWayServerKey   nUserId_%d stypename_%s  sServerKey_%s sClientID_%s ",nUserId,stypename,sServerKey,sClientID)
	return
end


--  测试 
function PublicUserInfo.TestAPI(nClubId,nChange)

	PublicUserInfo.ChangeClubSumAsset({nClubId=nClubId,nChange = nChange,nSourceType=99999,nMemberId=0,nHandleId=0,nItemId=nClubId})

end

PublicRedis.Get_User_Gold=PublicUserInfo.Get_User_Gold

-----------------------------------------------------------------------------------------------------

function PublicUserInfo.IncrRegister()
	tBase.m_MyRedisData[2].redis:incr("AllUserCount")
end

function PublicUserInfo.GetRegisterCount()
	local _Num = tBase.m_MyRedisData[2].redis:get("AllUserCount")
	return tonumber(_Num) or 0
end

-- 获取游戏玩家
function PublicUserInfo.GetGameMingUsers(nShopId)
	local sAllGaming = string.format("sAllGaming_shop%d", (nShopId or -1))
	local key = "Set_" .. sAllGaming
	local key1 = "Hm_ServerUsers302"    -- 大厅
	local tRedis =tBase.m_MyRedisData[1].redis
	local arrUserIds = tRedis:smembers(key)
	local arrUserIds2 = {}
	local t = tRedis:hgetall(key1)
	if t and type(t) == "table" then
		for userId, _ in pairs(t) do
			table.insert(arrUserIds2, userId)
		end
	end
	tBase.Log("GetGameMingUsers len:%d #arrUserIds2:%d key:%s", #arrUserIds, #arrUserIds2, key)
	local ret, ret2 = {}, {}
	if arrUserIds then
		for _, nUserId in pairs(arrUserIds) do
			ret[tonumber(nUserId)] = 1
			table.insert(ret2, tonumber(nUserId))
		end
	end
	for _, nUserId in pairs(arrUserIds2) do
		if not ret[tonumber(nUserId)] then
			table.insert(ret2, tonumber(nUserId))
		end
	end
	return ret2
end

-- 清除玩家标记用户信息
function PublicUserInfo.DelUserMarkInfo(nUserID)
	local sKey = "UserMarkInfo"
    local sUserKey = string.format("mark:%d",nUserID)
	local nRes = base.m_MyRedisData[1].redis:hdel(sKey, sUserKey)

	sKey = "UserNameChange"
    sUserKey = string.format("user:%d",nUserID)
	nRes = base.m_MyRedisData[1].redis:hdel(sKey, sUserKey)
end

-- 获取/设置玩家标记用户信息
function PublicUserInfo.TryGetUserMarkInfo(nUserID)
	local sKey = "UserMarkInfo"
    local sUserKey = string.format("mark:%d",nUserID)
	local nValue = base.m_MyRedisData[1].redis:hget(sKey, sUserKey)
	if not nValue or nValue == "" or nValue == "null" then
        return nil
    end
	return nValue
end

-- 获取玩家标记用户信息
function PublicUserInfo.GetUserMarkInfo(nUserID, nTarUid)
	local sKey = "UserMarkInfo"
    local sUserKey = string.format("mark:%d",nUserID)

	local nValue = base.m_MyRedisData[1].redis:hget(sKey, sUserKey)
	local json_str = nValue or "[]"
	if json_str == "" then
		json_str = "[]"
	end
	local nInfo =  cjson.decode(json_str)
	if not nTarUid then
		return nInfo
	end
	for _, v in pairs(nInfo) do
		if v.nUserID == nTarUid then
			return v
		end
	end
	return nil
end

-- 设置玩家标记用户信息
function PublicUserInfo.SetUserMarkInfo(nUserID, val)
    local sKey = "UserMarkInfo"
    local sUserKey = string.format("mark:%d",nUserID)

	local nRes = base.m_MyRedisData[1].redis:hset(sKey, sUserKey, val)
	base.Log("SetUserMarkInfo, %s, %s, %d", sKey, sUserKey, (nRes == 1 and 1 or 0))
end

-- 获取玩家改名信息
function PublicUserInfo.GetUserNameInfo(nUserID)
	local sKey = "UserNameChange"
    local sUserKey = string.format("user:%d",nUserID)

	local nValue = base.m_MyRedisData[1].redis:hget(sKey, sUserKey)
	local json_str = nValue or "[]"
	if json_str == "" then
		json_str = "[]"
	end
	local nInfo = cjson.decode(json_str)
	return nInfo
end

-- 设置玩家改名信息
function PublicUserInfo.SetUserNameInfo(nUserID, val)
    local sKey = "UserNameChange"
    local sUserKey = string.format("user:%d",nUserID)

	local nRes = base.m_MyRedisData[1].redis:hset(sKey, sUserKey, val)
	base.Log("SetUserNameInfo, %s, %s, %d val:%s", sKey, sUserKey, (nRes == 1 and 1 or 0), val)
end

-- 发送 玩家消息通知
function PublicUserInfo.Send_User_Notice(nUserId, nType, nMsg)
	local sClientID = PublicUserInfo.GetClientID_String(nUserId)
	if not sClientID then return end
	local f = function()
		local tSend = ProtoMgr.Gateway_pb.NoticeMsg()
		tSend.nUserId =nUserId
		tSend.nType = nType
		tSend.nMsg = nMsg or ""
	    local s = tBase.GetSP().new(ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_NOTICE_MSG)
	    s:AddString(tSend:SerializeToString())
	    tBase.PostToClient(sClientID, s:GetData(), s:GetSize())
	end
	xpcall(f,tpLog)
    return
end

-- 开服清除原有俱乐部信息
function PublicUserInfo.ClearClubData()
	local tRedis = base.m_MyRedisData[2].redis
	local pattern = "ClubSumAssetInfo_*"
	local nCnt, nCnt2 = 0, 0
	local keys = tRedis:keys(pattern)
	for _, val in pairs(keys) do
		tRedis:del(val)
        nCnt = nCnt + 1
	end
	base.Log("ClearClubData nCnt %d", nCnt)
	pattern = "ClubUserInfo_*"
	keys = tRedis:keys(pattern)
	for _, val in pairs(keys) do
		tRedis:del(val)
        nCnt2 = nCnt2 + 1
	end
	base.Log("ClearClubData 222 nCnt2 %d", nCnt2)
end


return PublicUserInfo