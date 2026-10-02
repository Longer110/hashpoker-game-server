package.path = require("./lua/DB_s/Head").path



local bit           = require("bit")-- 位运算 使用luajit自带的
local tBase         = require("base")           -- 基础功能接口
local tname         = require("typename")          -- 类弄定义接口
local ProtoMgr      = require("ProtoManager") -- 协议管理对象 
local tParserAux    = require("ParserAux")
local cjson         = require("cjson")
local tPubUserApi   = require("PublicUserInfo")   -- 用户信息 
local tPublicUserGold = require("PublicUserGold")
local tPublicRedis  = require("PublicRedis")
local logger        = require("logger")      -- 日志对象
local publicApi     =require("publicApi")
local tMoblieBinder =require("MoblieBinder")
local http          = require("socket.http")  -- Http 服务器
local myHttp        = require("MyHttps")
local payConfig     = require("PayConfig")


local DbProtoParse =tParserAux.DbProtoParse
local DbSendToServer =tParserAux.DbSendToServer
local DbServer_pb =ProtoMgr.DbServer_pb 
local DbProtoParse1 =tParserAux.DbProtoParse1
local DbSendToServer1 =tParserAux.DbSendToServer1
local DbServer1_pb =ProtoMgr.DbServer1_pb

local DbClubProtoParse =tParserAux.DbClubParse
local DbClubSendToServer =tParserAux.DbClubSendToServer

local _DbProtoEncode1 =tParserAux.DbProtoEncode1
--_DbProtoEncode1(strProto,tData)

local dbCmd =DbServer_pb.Db_Proto()

local ConfigReqHandle ={}
ConfigReqHandle.sql = {}

local RegistWay={}
RegistWay.Accout=1      --账号
RegistWay.Phone=5       --手机注册
RegistWay.Mail=6        --邮箱注册


function checkEmail(str)    --检验邮箱格式是否正确
	if not str then
		return false
	end
	if (str:match("[A-Za-z0-9%.%%%+%-]+@[A-Za-z0-9%.%%%+%-]+%.%w%w%w?%w?"))then
		return true
	else
		return false
	end
end
function checkPhone(str)        --检验手机号格式是否正确 ,格式类似为: 86-13679573345
	return string.match(str,"^%d?%d?%d?%d?%-%d+$")==str
end
local function checkAddr(str,nWay)
    if nWay ==RegistWay.Phone then return checkPhone(str) end
    if nWay ==RegistWay.Mail then return checkEmail(str) end
    return true
end


local function Check_ExecutIsError(sSql,arrRows)
    if arrRows and arrRows[1] and arrRows[1].ErrorCode and arrRows[1].ErrorInfo then
        tBase.Log("ErrorMsg  ErrorCode: %s  ErrorInfo_%s sSql_%s   ",arrRows[1].ErrorCode,arrRows[1].ErrorInfo,sSql)
    end 
end  

function SqlExecut(sSql,dbConnect)
    local arrRows ={} 
    local cursor,msg =assert(dbConnect:execute (sSql))
    if cursor==nil or type(cursor)=='number' then
        return
    end
    repeat
        local row = cursor:fetch({},"a")
        while row do
          table.insert(arrRows,tBase.DeepCopy(row))
           row = cursor:fetch(row,"a")
        end
        cursor:close()
        cursor = dbConnect:nextres()
    until( cursor == 0 )   

    Check_ExecutIsError(sSql,arrRows)  
    return arrRows
end

-- 支持多个结果集返回的通用函数
function SqlExecuts(sSql, dbConnect)
    local results = {}   -- 每个结果集一个数组
    local cursor, msg = assert(dbConnect:execute(sSql))
    if cursor == nil or type(cursor) == "number" then
        return results
    end
    local resIndex = 1
    repeat
        local arrRows = {}
        local row = cursor:fetch({}, "a")
        while row do
            table.insert(arrRows, tBase.DeepCopy(row))
            row = cursor:fetch(row, "a")
        end
        cursor:close()
        results[resIndex] = arrRows
        resIndex = resIndex + 1
        cursor = dbConnect:nextres()
    until(cursor == 0 or cursor == nil)
    return results
end

local function PlatformDB_SqlExecute(sSql,isForRead)
    local connection =dbSink.PlatformDB_connect
    if isForRead then
        connection =dbSink.GetDbConnectForRead("DJH_PlatformDB")
    end
    return SqlExecut(sSql,connection)
end
local function AccountsDB_SqlExecute(sSql,isForRead)
    local connection =dbSink.AccountsDB_connect
    if isForRead then
        connection =dbSink.GetDbConnectForRead("DJH_AccountsDB")
    end
    return SqlExecut(sSql,connection)
end
local function RecordDB_SqlExecute(sSql,isForRead)
    local connection =dbSink.RecordDB_connect
    if isForRead then
        connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    end
    return SqlExecut(sSql,connection)
end
local function TreasureDB_SqlExecute(sSql,isForRead)
    local connection =dbSink.TreasureDB_connect
    if isForRead then
        connection =dbSink.GetDbConnectForRead("DJH_TreasureDB")
    end
    return SqlExecut(sSql,connection)
end
local function WebDB_SqlExecute(sSql,isForRead)
    local connection =dbSink.WebDB_connect
    if isForRead then
        connection =dbSink.GetDbConnectForRead("DJH_WebDB")
    end
    return SqlExecut(sSql,connection)
end

local function ExecuteDbSql(sSql,sDbName)
    local sDbName =sDbName or "nil"
    local dbConnect =nil
    if sDbName =="DJH_RecordDB" then
        dbConnect =dbSink.RecordDB_connect
    elseif sDbName=="DJH_PlatformDB" then
        dbConnect =dbSink.PlatformDB_connect
    elseif sDbName=="DJH_AccountsDB" then
        dbConnect =dbSink.AccountsDB_connect
    elseif sDbName=="DJH_TreasureDB" then
        dbConnect =dbSink.TreasureDB_connect        
    elseif sDbName=="DJH_WebDB" then
        dbConnect =dbSink.WebDB_connect
    end
    if not dbConnect then
        return false,"no db connect "..sDbName
    end
    --dbConnect:execute (sSql)
    return SqlExecut(sSql,dbConnect)
end

local tConnToTimeZone ={}
function SetTimeZone(connection,nUserId)
    local nGroupId =tPubUserApi.Get_User_GroupId(nUserId)
    local sTimeZone =tPublicRedis.GetTimeZone(nGroupId)
    if tConnToTimeZone[connection] ==sTimeZone then
        tBase.Log("repeat set sTimeZone:%s",sTimeZone)
        return sTimeZone,nGroupId
    end
    local sqlOfTimeZone =string.format("set time_zone='%s'",sTimeZone)
    SqlExecut(sqlOfTimeZone,connection)     --设置时区
    tConnToTimeZone[connection] =sTimeZone
    return sTimeZone,nGroupId
end


function ConfigReqHandle.OnDbCheckReq(sReturnKey,Data,nLen)
  
    local strReq ="DbCheckReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
   local sSql ="SELECT CURRENT_TIMESTAMP() as ctime"
   local row1 =PlatformDB_SqlExecute(sSql)
   local row2 =AccountsDB_SqlExecute(sSql)
   local row3 =RecordDB_SqlExecute(sSql)
   local row4 =TreasureDB_SqlExecute(sSql)
   local row5 =WebDB_SqlExecute(sSql)
   --tBase.LogT(row1)
   --tBase.LogT(row2)
   --tBase.LogT(row3)
   --tBase.LogT(row4)
   --tBase.LogT(row5)
   local DbCheckRsp ={}
   DbCheckRsp.nIsNormal =1
   DbCheckRsp.sErrStr=""
   if tData.nId then
    DbCheckRsp.nId=tData.nId
   end
   DbSendToServer(sReturnKey,"DbCheckRsp",DbCheckRsp)
end

local tRoomListCache ={}
--房间列表请求
function ConfigReqHandle.OnDbRoomListReq(sReturnKey,Data,nLen)
    local strReq ="DbRoomListReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local sKey =string.format("%d_%d",tData.nGroupId,tData.nGameId)
    local tCache =tRoomListCache[sKey] or {nEcho=-1,nTime=0,DbRoomListRsp=nil}
    tRoomListCache[sKey] =tCache

    --使用缓存回复,不重新读数据库 (nEcho>0是针对后台发出的通知;nEcho<0针对的是定时更新)
    if tData.nEcho>0 and tData.nEcho<=tCache.nEcho and tCache.DbRoomListRsp then
        tCache.DbRoomListRsp.nEcho =tData.nEcho
        DbSendToServer(sReturnKey,"DbRoomListRsp",tCache.DbRoomListRsp)
        -- tBase.Log("DbRoomListRsp use cache,nEcho:%d",tData.nEcho) 
        return
    end
    if tData.nEcho<0 and (os.time()-tCache.nTime)<30 and tCache.DbRoomListRsp then
        tCache.DbRoomListRsp.nEcho =tData.nEcho
        DbSendToServer(sReturnKey,"DbRoomListRsp",tCache.DbRoomListRsp)
        -- tBase.Log("DbRoomListRsp use cache,nEcho:%d",tData.nEcho) 
        return
    end

    local arrRoomItems ={}
    local nGameId = tData.nGameId
    local sql =string.format("call Load_RoomList(%d,%d)",tData.nGroupId,nGameId)
    local arrRows =PlatformDB_SqlExecute(sql)
    -- tBase.Log("GameId_%d RoomList arrRows Len:%d",nGameId,#arrRows)

    for _,row in ipairs(arrRows) do
        local roomItem ={}
        roomItem.nGameId=tonumber(row.GameId)
        roomItem.nRoomId=tonumber(row.RoomId)
        roomItem.nEnterFloorLimit=tonumber(row.EnterFloorLimit)
        roomItem.nAnte=tonumber(row.Ante)
        roomItem.nGroupId=tonumber(row.GroupId)
        roomItem.nTax =tonumber(row.Tax)
        roomItem.tScoreCfg = row.ScoreCfg or "{}"
        roomItem.sHelpUI = row.HelpUI or ""
        table.insert(arrRoomItems,roomItem)
        -- tBase.Log("游戏"..roomItem.nGameId.."    房间"..roomItem.nRoomId.."   人数"..roomItem.nAnte.." ="..type(row.ScoreCfg).." sHelpUI_"..roomItem.sHelpUI)
    end
    local DbRoomListRsp ={}
    DbRoomListRsp.arrRoomItems =arrRoomItems
    DbRoomListRsp.nGroupId=tData.nGroupId
    DbRoomListRsp.nGameId=tData.nGameId
    DbRoomListRsp.nEcho=tData.nEcho
    DbSendToServer(sReturnKey,"DbRoomListRsp",DbRoomListRsp)
    -- tBase.Log("OnDbRoomListReq nGameId_%d",nGameId) 
    -- tBase.Log("DbRoomListRsp use db,nEcho:%d",tData.nEcho)
    --缓存数据()
    tCache.nTime =os.time()
    tCache.DbRoomListRsp =DbRoomListRsp
    tCache.nEcho =math.max(tCache.nEcho,tData.nEcho)

end

local tGameListCache ={}
--游戏列表请求
function ConfigReqHandle.OnDbGameListReq(sReturnKey, Data, nLen)
    -- tBase.Log("OnDbGameListReq-") 
    local strReq ="DbGameListReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local tCache =tGameListCache[tData.nGroupId] or {nEcho=-1,nTime=0,DbGameListRsp=nil}
    tGameListCache[tData.nGroupId] =tCache

    --使用缓存回复,不重新读数据库 (nEcho>0是针对后台发出的通知;nEcho<0针对的是定时更新)
    if tData.nEcho>0 and tData.nEcho<=tCache.nEcho and tCache.DbGameListRsp then
        tCache.DbGameListRsp.nEcho =tData.nEcho
        DbSendToServer(sReturnKey,"DbGameListRsp",tCache.DbGameListRsp)
        -- tBase.Log("DbGameListRsp use cache,nEcho:%d",tData.nEcho) 
        return
    end
    if tData.nEcho<0 and (os.time()-tCache.nTime)<30 and tCache.DbGameListRsp then
        tCache.DbGameListRsp.nEcho =tData.nEcho
        DbSendToServer(sReturnKey,"DbGameListRsp",tCache.DbGameListRsp)
        -- tBase.Log("DbGameListRsp use cache,nEcho:%d",tData.nEcho) 
        return
    end

    local arrGameItems ={}
    local sql =string.format("call Load_GameList(%d)",tData.nGroupId)
    local arrRows =PlatformDB_SqlExecute(sql)
    -- tBase.Log("GameList arrRows Len:%d",#arrRows)
    for _,row in ipairs(arrRows) do
        local gameItem ={}
        gameItem.nGameId     	=tonumber(row.GameId) or -1;          --游戏id, 105:扎金花 113:三公 106:21点 104:百人牛牛 103:通比牛牛 ...
        gameItem.nGameOrder  	=tonumber(row.GameOrder) or 1;  	    --游戏排序的位置:1 -- 100 
        gameItem.nGameStatus 	=tonumber(row.GameStatus) or 0; 	    --游戏状态:0默认 1热门 2最新 3即将开启 4正在维护
        gameItem.sIconUrl    	=row.IconUrl or ""; 	    -- 图标地址
        gameItem.sGamePath   	=row.GamePath or "";        -- 游戏路径
        gameItem.sVersion    	=row.Version or ""; 	    -- 版本号
        gameItem.sZipFilePath 	=row.ZipFilePath or "";		--地址
        gameItem.sMD5FilePath   =row.MD5FilePath or "";	    -- 地址
        gameItem.nGroupId       =tonumber(row.GroupId) or -1
        gameItem.sPlatform      =row.Platform or ""
        gameItem.sCUPGroupID    =row.CUPGroupID or ""
        table.insert(arrGameItems,gameItem)
    end
    local DbGameListRsp ={}
    DbGameListRsp.arrGameItems =arrGameItems
    DbGameListRsp.nGroupId=tData.nGroupId
    DbGameListRsp.nEcho =tData.nEcho
    DbSendToServer(sReturnKey,"DbGameListRsp",DbGameListRsp)
    -- tBase.Log("DbGameListRsp use db,nEcho:%d",tData.nEcho)
    --缓存数据()
    tCache.nTime =os.time()
    tCache.DbGameListRsp =DbGameListRsp
    tCache.nEcho =math.max(tCache.nEcho,tData.nEcho)
end

function ConfigReqHandle.OnRecordBetSettleReq(sReturnKey, Data, nLen)
    tBase.Log("RecordBetSettleReq-") 
    local strReq ="RecordBetSettleReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sPrefix ="UPDATE Betting_Record SET GoldWin= CASE BetId "
    local sBody =""
    local arrBetId ={}
    for dex,item in ipairs(tData.arrItems) do
        sBody =sBody ..string.format("when %s then %.2f ",item.sBetId,item.nGoldWin)
        table.insert(arrBetId,item.sBetId)
       if dex%100 ==0 or dex ==#tData.arrItems then
            local sSuffix =string.format("where BetId in(%s)",table.concat(arrBetId,","))
            local sSql =sPrefix..sBody.."END "..sSuffix
            local row =RecordDB_SqlExecute(sSql)
            tBase.Log("arrBetId Len:%d",#arrBetId)
            tBase.LogT(row)
            sBody =""
            arrBetId={}
       end
    end
end

local function SetWebRedisResulte(sRequestkey,tData)
    if not sRequestkey then
       return
    end
    local tRedis =tBase.m_MyRedisData[1].redis
    tRedis:hmset(sRequestkey,tData)
    tRedis:expire(sRequestkey,60)
 end


 --当前能转出金币数量 查询
function ConfigReqHandle.OnCoinCanDrawReq(sReturnKey, Data, nLen)
    local tData =BackstageAux:Parser(Data, nLen,"CoinCanDrawReq")
    assert(tData~=nil,"OnCoinCanDrawReq _Parse Err,tData is nil")

    local nUserId=math.floor(tData.nUserId)
    local sRequestkey= 	 tData.sRequestkey
   
    local isSuccee,nCoinCanDraw =ConfigReqHandle._GetCoinCanDraw(nUserId)
    if not isSuccee then
        tBase.Log("OnCoinCanDrawReq nUserId:%d fail",nUserId)
        SetWebRedisResulte(sRequestkey,{nUserId=nUserId,nResult=0,nCoinCanDraw=0})
        return
    end
    tBase.Log("OnCoinCanDrawReq nUserId:%d nCoinCanDraw:%.3f",nUserId,nCoinCanDraw)
    SetWebRedisResulte(sRequestkey,{nUserId=nUserId,nResult=1,nCoinCanDraw=nCoinCanDraw})
end


function ConfigReqHandle._GetCoinCanDraw(nUserId)
    local RetainGold,UnLockGold,_,isSuccee =tPublicUserGold.GetRetainGold(nUserId)
    if not isSuccee then
        return false,0
    end
    local nCoinCanDraw= (UnLockGold -RetainGold)
    nCoinCanDraw =math.max(nCoinCanDraw,0)
    nCoinCanDraw =publicApi.Floor_2(nCoinCanDraw)
    tBase.Log("_GetCoinCanDraw nUserId:%d nCoinCanDraw:%.3f RetainGold:%.3f UnLockGold:%.3f",nUserId,nCoinCanDraw,RetainGold,UnLockGold)
    return true,nCoinCanDraw
end





 --0: 成功
 --21:序列号查询失败
 --22:用户ID错误
 --23:用户在合集游戏中
 --24:锁定用户金币失败
 --25:GSP_UpdateGold调用失败
 --26:GSP_UpdateGold返回失败

--后台充值请求
function ConfigReqHandle.OnRechargeReq(sReturnKey, Data, nLen)
    local tData =BackstageAux:Parser(Data, nLen,"RechargeReq")
    if tData ==nil then
       tBase.Log("RechargeReq _Parse Err")
       return
    end
    if tData.nAssetType and tData.nAssetType > 1 then   -- 俱乐部总资产 充值  
        ClubSink.ClubAssetRecharge(tData) 
        return          
    end     
    tBase.Log("_OnRechargeReq nUserId:%d sSerialNumber:%s sResultKey:%s ",tData.nUserId,tData.sSerialNumber,tData.sResultKey)
    local sSql =string.format("select UserID,Amount,ItemId,AssetType FROM Bill_Record WHERE id=%s",tData.sSerialNumber)
    local sFailSql =string.format('Call GSP_Bill_Fail("%s")',tData.sSerialNumber)
    local arrRows =AccountsDB_SqlExecute(sSql)
    tBase.LogT(arrRows)
    if arrRows==nil or #arrRows~=1 then
        tBase.Log("_OnRechargeReq ERROR 21 sql:%s fail",sSql)
        SetWebRedisResulte(tData.sResultKey,{nRlt=21,sErr="sql ERROR"})
        AccountsDB_SqlExecute(sFailSql)
        return
    end
    local tRow =arrRows[1]
    local nUserId =tonumber(tRow.UserID) or 0
    local nAmount =tonumber(tRow.Amount)
    local nItemId = tonumber(tRow.ItemId) or 1      
    local nAssetType = tonumber(tRow.AssetType) or 1   -- 资产类型: 1 个人,其他资产 
    if nAssetType <= 0 then   -- 
        tBase.Log("_OnRechargeReq  UserId:%d nAssetType_%d 默认值 ",nUserId,nAssetType)
        nAssetType = 1 
    end 
    --判断UserId是否正确
    if nUserId~=tData.nUserId then
        tBase.Log("_OnRechargeReq  UserId wrong:%d ~= %d",nUserId,tData.nUserId)
        SetWebRedisResulte(tData.sResultKey,{nRlt=22,sErr="UserId wrong"})
        AccountsDB_SqlExecute(sFailSql)
        return 
    end
    --合集游戏中禁止扣钱
    local nGameId,nRoomId,sServerKey =tPubUserApi.GetUserPlayingGame(nUserId)
    local nTransferType = tPublicRedis._IsAllowTransferGameId(nGameId)
    if nGameId then
        local isAllow = false
        if nTransferType == 1 then
            -- 该游戏类型允许转入转出
            isAllow = true 
            tBase.Log("_OnRechargeReq UserId:%d in Game:%d   允许该游戏转入转出",nUserId,nGameId) 
        elseif nTransferType == 2 and nAmount > 0 then
            -- 该游戏类型只允许转入
            isAllow = true 
            tBase.Log("_OnRechargeReq UserId:%d in Game:%d  允许该游戏转入",nUserId,nGameId)   
        end

        if not isAllow then
            tBase.Log("_OnRechargeReq fail UserId:%d in Game:%d nAmount:%f of HeJi",nUserId,nGameId,nAmount)
            SetWebRedisResulte(tData.sResultKey,{nRlt=23,sErr="user in game of HeJi nGameId: "..nGameId})
            AccountsDB_SqlExecute(sFailSql)
            return  
        end
    end
    --如果是扣钱，先锁住同等数量金币
    local nLockGold =0
    if nAmount<0 and math.abs(nAmount) >1e-6 then
        nLockGold = -nAmount
        local isSuc,nCoinCanDraw =ConfigReqHandle._GetCoinCanDraw(nUserId)      --允许转出的金币数量
        if isSuc and nLockGold>nCoinCanDraw and math.abs(nLockGold -nCoinCanDraw) >1e-6 then
            tBase.Log("_OnRechargeReq fail UserId:%d,CoinCanDraw Error,nCoinCanDraw:%.3f",nUserId,nCoinCanDraw)
            SetWebRedisResulte(tData.sResultKey,{nRlt=33,sErr="CoinCanDraw Error"})
            AccountsDB_SqlExecute(sFailSql)
            return
        end
    end
    
    local isLockSuccee,sErr =tPublicUserGold.Lock(nUserId,nLockGold,nItemId,nAssetType)
    if not isLockSuccee and sErr~="sKeyNotExist" then
        local nRlt = 24  --24 有锁金币导致 
        local tUserGold =tPublicUserGold.GetUserGoldInfo(nUserId,nItemId,nAssetType)
        if tUserGold and tUserGold.nFreezeGoldSum == 0 then 
            nRlt = 27   --  27，余额不足
        end 
        tBase.Log("_OnRechargeReq LockGold Fail,nUserId:%d nLockGold:%.2f sErr:%s  nRlt: %d(24:有锁金币导致,27:余额不足) nItemId: %d nAssetType: %d ",
        nUserId,nLockGold,sErr,nRlt,nItemId,nAssetType)

        SetWebRedisResulte(tData.sResultKey,{nRlt=nRlt,sErr="LockGold Fail"})
        AccountsDB_SqlExecute(sFailSql)
        return
    end

    --[[
    local RetainGold,UnLockGold =tPublicUserGold.GetRetainGold(nUserId)
    if UnLockGold<RetainGold and math.abs(RetainGold -UnLockGold) >1e-6 then
        local nBackGold =RetainGold -UnLockGold
        nBackGold =math.min(nLockGold,nBackGold)
        local isSuccee =tPublicUserGold.UnLock(nUserId,nBackGold,nItemId,nAssetType)
        assert(isSuccee)
        if isSuccee then
            nLockGold =nLockGold -nBackGold
            nAmount =-nLockGold
            tBase.Log("nAmount change To:%.3f RetainGold:%.3f nUserId:%d",nAmount,RetainGold,nUserId)
        end
    end
    ]]
    
    --更新数据库金币
    local sql =string.format('Call GSP_UpdateGoldV2("%s",%.3f)',tData.sSerialNumber,nAmount)
    local arrRows =AccountsDB_SqlExecute(sql)
    tBase.LogT(arrRows)
    if arrRows==nil or #arrRows ~=1 then
        tBase.Log("_OnRechargeReq  ERROR 25 sql:%s fail",sql)
        SetWebRedisResulte(tData.sResultKey,{nRlt=25,sErr="sql ERROR"})
        local isUnLockSuccee,sErr =tPublicUserGold.UnLock(nUserId,nLockGold,nItemId,nAssetType)
        if not isUnLockSuccee and sErr~="sKeyNotExist" then
            tBase.Log("_OnRechargeReq  ERROR 25 UnLock nUserId:%d nLockGold:%.2f fail,sErr:%s nItemId: %d %d ",nUserId,nLockGold,sErr,nItemId,nAssetType)
        end
        AccountsDB_SqlExecute(sFailSql)
        return
    end
    local tRow =arrRows[1]
    local nError =tonumber(tRow.Error)
    local nAmount =tonumber(tRow.Amounts) or 0
    local nNowAmounts =tonumber(tRow.NowAmounts) or 0 --玩家当前金币
    if nError ~=0 then
        tBase.Log("_OnRechargeReq GSP_UpdateGold return fail,nError:%d",nError)
        SetWebRedisResulte(tData.sResultKey,{nRlt=26,sErr="GSP_UpdateGold return fail"})
        local isUnLockSuccee,sErr =tPublicUserGold.UnLock(nUserId,nLockGold,nItemId,nAssetType)
        if not isUnLockSuccee and sErr~="sKeyNotExist" then
            tBase.Log("_OnRechargeReq  ERROR 26 UnLock nUserId:%d nLockGold:%.2f fail,sErr:%s nItemId: %d nAssetType: %d ",nUserId,nLockGold,sErr,nItemId,nAssetType)
        end
        AccountsDB_SqlExecute(sFailSql)
        return
    else
        tBase.Log("_OnRechargeReq GSP_UpdateGold Succee")
        SetWebRedisResulte(tData.sResultKey,{nRlt=0})
    end
    local nUserId =tonumber(tRow.UserIDs) or 0
    local isSuccee,sErr =false,""
    if nLockGold~=0 then
        isSuccee,sErr =tPublicUserGold.UnLockAndMinus(nUserId,nLockGold,nItemId,nAssetType)
    else
        isSuccee,sErr =tPublicUserGold.Change(nUserId,nAmount,nItemId,nAssetType)
    end
    if not isSuccee then
        tBase.Log("_OnRechargeReq Warining chang gold to redis fail,but change to db,sErr:%s nItemId: %d  %d ",sErr,nItemId,nAssetType)
        return
    else
        tBase.Log("_OnRechargeReq  Change Gold Succee nUserId: %d nItemId: %d nAssetType: %d  ",nUserId,nItemId,nAssetType)
    end
    nGameId,nRoomId,sServerKey =tPubUserApi.GetUserPlayingGame(nUserId)
    if sServerKey and #sServerKey>0 then
        local DbRechargeRsp={}
        DbRechargeRsp.nRlt=0
        DbRechargeRsp.nUserId=tData.nUserId
        DbRechargeRsp.sSerialNumber=tData.sSerialNumber
        DbRechargeRsp.nItemId=nItemId
        DbRechargeRsp.nAmount=nAmount
        DbRechargeRsp.sResultKey=tData.sResultKey
        DbRechargeRsp.nCurrentAmount=nNowAmounts
        local tPacket =_DbProtoEncode1("DbRechargeRsp",DbRechargeRsp)
        tBase.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
        local nNowGold = tPubUserApi.Get_User_Gold(nUserId,nItemId)
        tBase.Log("_OnRechargeReq  充值成功,通知游戏 nUserId: %d nNowGold: %f  nItemId: %d  sServerKey: %s ",nUserId,nNowGold,nItemId,sServerKey) 
    else
        local nNowGold = tPubUserApi.Get_User_Gold(nUserId,nItemId)
        tPubUserApi.Send_UserGold(nUserId,nNowGold,nItemId,nAmount)      -- 在大厅时通知金币   
        tBase.Log("_OnRechargeReq  充值成功,通知大厅 nUserId: %d nNowGold: %f  nItemId: %d ",nUserId,nNowGold,nItemId)
    end
    return
end

--打赏
function ConfigReqHandle.OnRewardReq(sReturnKey, Data, nLen)
    
end

--修改跟投锁通知
function ConfigReqHandle.OnFollowBetLockReq(sReturnKey, Data, nLen)
    local tData =BackstageAux:Parser(Data, nLen,"FollowBetLockReq")
    assert(tData~=nil,"FollowBetLockReq _Parse Err,tData is nil")
    tBase.Log("OnFollowBetLockReq sResultKey:%s",tostring(tData.sResultKey))

    if not tData.nUserId or tData.nUserId<=0 then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr=string.format("nUserId Error,nUserId_%s",tostring(tData.nUserId))})
        return
    end

    tBase.Log("OnFollowBetLockReq nUserId:%d nIsLock:%d",tData.nUserId,tData.nIsLock)
    if tData.nIsLock~=0 and tData.nIsLock~=1 then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr="nIsLock Error,not 0 or 1"})
        return   
    end

    SetWebRedisResulte(tData.sResultKey,{nRlt=0,sErr=string.format("nIsLock=%d",tData.nIsLock)})

    local tLockInfo = tPublicRedis.GetUserFollowBetLockInfo(tData.nUserId) or {}
    if tLockInfo.nIsLock == tData.nIsLock then
        tBase.Log("OnFollowBetLockReq nUserId:%d set same nIsLock:%d",tData.nUserId,tData.nIsLock) 
        return
    end

    tLockInfo.nIsLock = tData.nIsLock
    tPublicRedis.SetUserFollowBetLockInfo(tData.nUserId,tLockInfo)

    --通知游戏服玩家跟投锁状态改变
    local nGameId,nRoomId,sServerKey =tPubUserApi.GetUserPlayingGame(tData.nUserId)
    if sServerKey and #sServerKey>0 then
        local DbFollowLockChangeNotify={}
        DbFollowLockChangeNotify.nUserId=tData.nUserId
        DbFollowLockChangeNotify.nLock=tData.nIsLock
        local tPacket =_DbProtoEncode1("DbFollowLockChangeNotify",DbFollowLockChangeNotify)
        tBase.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
        tBase.Log("DbFollowLockChangeNotify send notify to serv %s",sServerKey)
    end
end



--解锁跟投
function ConfigReqHandle.OnCanFollowBetReq(sReturnKey, Data, nLen)
    local tData =BackstageAux:Parser(Data, nLen,"CanFollowBetReq")
    assert(tData~=nil,"OnCanFollowBetReq _Parse Err,tData is nil")
    tBase.Log("OnCanFollowBetReq sResultKey:%s",tostring(tData.sResultKey))
    if not tData.nFromUserId or tData.nFromUserId<=0 then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr=string.format("nFromUserId Error,nFromUserId_%s",tostring(tData.nFromUserId))})
        return
    end
    if not tData.nToUserId or tData.nToUserId<=0 then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr=string.format("nToUserId Error,nToUserId_%s",tostring(tData.nToUserId))})
        return
    end
    if not tData.sTimeTem or tData.sTimeTem == "" then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr=string.format("sTimeTem Error,sTimeTem_%s",tostring(tData.sTimeTem))})
        return
    end

    local nTimeTem = tonumber(tData.sTimeTem)
    if not nTimeTem then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr=string.format("tonumber(sTimeTem) Error,nTimeTem_%s",tostring(nTimeTem))})
        return
    end

    local nowTimeTem = os.time()
    local nSec = nTimeTem-nowTimeTem
    if nSec<1 then
        SetWebRedisResulte(tData.sResultKey,{nRlt=1,sErr=string.format("sTimeTem Error,sTimeTem_%s is overtime,nowTimeTem_%d sTimeTem-nowTimeTem=%d",tostring(nTimeTem),nowTimeTem,nSec)})
        return
    end

    if tData.sLiveID and tData.sLiveID~="" then
        local str = string.format("Until timestamp_%s, nUserId_%d can follow nUserId_%d in room_%s",tData.sTimeTem,tData.nFromUserId,tData.nToUserId,tData.sLiveID)
        SetWebRedisResulte(tData.sResultKey,{nRlt=0,sErr=str})
    else
        local str = string.format("Until timestamp_%s, nUserId_%d can follow nUserId_%d in any room",tData.sTimeTem,tData.nFromUserId,tData.nToUserId)
        SetWebRedisResulte(tData.sResultKey,{nRlt=0,sErr=str})
    end

    tBase.Log("OnCanFollowBetReq nFromUserId:%d nToUserId:%d sTimeTem:%s sLiveID:%s nSec:%d",tData.nFromUserId,tData.nToUserId,tData.sTimeTem,tData.sLiveID or "",nSec)

    local tSaveData = {}
    tSaveData.nFromUserId = tData.nFromUserId
    tSaveData.nToUserId = tData.nToUserId
    tSaveData.sLiveID = tData.sLiveID
    tSaveData.sTimeTem = tData.sTimeTem
    tSaveData.nSec = nSec
    tPublicRedis.SetCanFollowBetStatus(tSaveData)

    --通知游戏服玩家打赏解锁
    local nGameId,nRoomId,sServerKey =tPubUserApi.GetUserPlayingGame(tData.nFromUserId)
    if sServerKey and #sServerKey>0 then
        local DbUnLockFollowNotify={}
        DbUnLockFollowNotify.nUserId=tData.nToUserId
        DbUnLockFollowNotify.nLock=0
        DbUnLockFollowNotify.nTargetUserId=tData.nFromUserId
        local tPacket =_DbProtoEncode1("DbUnLockFollowNotify",DbUnLockFollowNotify)
        tBase.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
        tBase.Log("DbUnLockFollowNotify send notify to serv %s",sServerKey)
    end
end


--游戏中充值请求
function ConfigReqHandle.OnDbRechargeReq(sReturnKey, Data, nLen)
    tBase.Log("DbRechargeReq") 
    local strReq ="DbRechargeReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql =string.format('Call GSP_UpdateGold("%s")',tData.sSerialNumber)
    local arrRows =AccountsDB_SqlExecute(sql)
    tBase.LogT(sql,' ',arrRows)
    assert(arrRows~=nil and #arrRows ==1,'Err happen ,'..sql)
    local tRow =arrRows[1]

    local nError =tonumber(tRow.Error)
    local nUserId =tonumber(tRow.UserIDs) or 0
    local nAmount =tonumber(tRow.Amounts) or 0
    local nItemId =tonumber(tRow.nItemId) or 1 
    local nNowAmounts =tonumber(tRow.NowAmounts) or 0 --玩家当前金币
    
    local DbRechargeRsp={}
    if nError==0 then
        DbRechargeRsp.nRlt=0
        assert(nUserId==tData.nUserId)
        local nItemId = 1 
        tPubUserApi.UpdateUserGold(nUserId,nNowAmounts,nItemId) -- 同步redis金币
    else
        DbRechargeRsp.nRlt=-1
    end
	DbRechargeRsp.nUserId=tData.nUserId
	DbRechargeRsp.nItemId=nItemId
	DbRechargeRsp.sSerialNumber=tData.sSerialNumber
	DbRechargeRsp.nAmount=nAmount
    DbRechargeRsp.sResultKey=tData.sResultKey
    DbRechargeRsp.nCurrentAmount=nNowAmounts
    DbSendToServer1(sReturnKey,"DbRechargeRsp",DbRechargeRsp)
end

--德州统计数据初始化请求
function ConfigReqHandle.OnTexaStatisticInit(sReturnKey, Data, nLen)
    tBase.Log("OnTexaStatisticInit")
    local strReq ="DbTexaStatisticInit"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql =string.format('Call TexaClubUserStatistic_Read("%d")',tData.nUserId)
    local arrRows =RecordDB_SqlExecute(sql)
    tBase.LogT(sql,' ',arrRows)
    for _,v in ipairs(arrRows) do
        local tem ={}
        tem.nClubId=tonumber(v.ClubId or 0)
        tem.nGameId =tonumber(v.GameId or 0)
        tem.nPlayCount=tonumber(v.PlayCount or 0)
        tem.nInPoolCount=tonumber(v.InPoolCount or 0)
        tem.nRaiseCountBFlop=tonumber(v.RaiseCountBFlop or 0)
        tem.nAllInAndWinCount=tonumber(v.AllInAndWinCount or 0)
        tem.nProfitSum=tonumber(v.ProfitSum or 0)
        tem.nGoldType=tonumber(v.GoldType or 1)
        tem.nSumBet=tonumber(v.SumBet or 0)
        tem.nWinCount=tonumber(v.WinCount or 0)
        tem.nQiPaiCount=tonumber(v.QiPaiCount or 0)
        tem.nAllInCount=tonumber(v.AllInCount or 0)
        tem.nHandProfit=tonumber(v.HandProfit or 0)
        tem.nOpCount=tonumber(v.OpCount or 0)
        tem.nSeeFlop=tonumber(v.SeeFlop or 0)
        tem.nReachShowdown=tonumber(v.ReachShowdown or 0)
        tem.nSmallBlind=tonumber(v.SmallBlind or 0)
        tem.nBigBlind=tonumber(v.BigBlind or 0)
        tem.nZhuaTou=tonumber(v.ZhuaTou or 0)
        tem.nPreAnte=tonumber(v.PreAnte or 0)
        tPublicRedis.TexaStatistic_Init(tData.nUserId,tem)
    end
    if #arrRows ==0 then
        tPublicRedis.TexaStatistic_Init(tData.nUserId)
    end
end


--用户财富信息请求
function ConfigReqHandle.OnDbUserTreasureReq(sReturnKey, Data, nLen)
    tBase.Log("DbUserTreasureReq") 

    local strReq ="DbUserTreasureReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local nUserId =tData.nUserId
    local sql =string.format("Call User_Get_Treasure(%d)",nUserId)
    local arrRows =AccountsDB_SqlExecute(sql)
    tBase.LogT(sql,' ',arrRows)
    assert(arrRows~=nil and #arrRows ==1,'Err happen ,'..sql)

    local tRow =arrRows[1]
    local DbUserTreasureRsp ={}
    DbUserTreasureRsp.nUserId =nUserId
    DbUserTreasureRsp.nGold =tonumber(tRow.nGold) or 0  
    DbSendToServer(sReturnKey,"DbUserTreasureRsp",DbUserTreasureRsp)
end

local tShopListCache ={nEcho =-1,DbShopListRsp=nil,nTime=0} --nEcho:视作更新版本号
function ConfigReqHandle.OnDbShopListReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbShopListReq")
    local strReq ="DbShopListReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    
    --使用缓存回复,不重新读数据库 (nEcho>0是针对后台发出的通知;nEcho<0针对的是定时更新)
    if tData.nEcho>0 and tData.nEcho<=tShopListCache.nEcho and tShopListCache.DbShopListRsp then
        tShopListCache.DbShopListRsp.nEcho =tData.nEcho
        DbSendToServer(sReturnKey,"DbShopListRsp",tShopListCache.DbShopListRsp)
        -- tBase.Log("DbShopListRsp use cache,nEcho:%d",tData.nEcho) 
        return
    end

    if tData.nEcho<0 and (os.time()-tShopListCache.nTime)<30 and tShopListCache.DbShopListRsp then
        tShopListCache.DbShopListRsp.nEcho =tData.nEcho
        DbSendToServer(sReturnKey,"DbShopListRsp",tShopListCache.DbShopListRsp)
        -- tBase.Log("DbShopListRsp use cache,nEcho:%d",tData.nEcho) 
        return
    end

    --读数据库
    local arrShops ={}
    local sql ="call Load_ShopList()"
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.Log("ShopList arrRows Len:%d",#arrRows)   
    for _,row in ipairs(arrRows) do
        local shop ={}
        shop.nShopId =tonumber(row.ShopId) or 0
        shop.nGroupId =tonumber(row.GroupID) or 0
        shop.nSubStore =tonumber(row.SubStore) or 0
        shop.sChannel =row.Channel or ""
        shop.sTgLink = row.TgLink or ""
        table.insert(arrShops,shop)
    end
    local DbShopListRsp={}
    DbShopListRsp.arrShops=arrShops
    DbShopListRsp.nEcho =tData.nEcho
    DbSendToServer(sReturnKey,"DbShopListRsp",DbShopListRsp)
    tBase.Log("DbShopListRsp use db,nEcho:%d",tData.nEcho) 
    --缓存数据()
    tShopListCache.nTime =os.time()
    tShopListCache.DbShopListRsp =DbShopListRsp
    tShopListCache.nEcho =math.max(tShopListCache.nEcho,tData.nEcho)
end


function ConfigReqHandle.OnDbLiveCSRelationReq(sReturnKey, Data, nLen)
    -- tBase.Log("DbLiveCSRelationReq") 
    local strReq ="DbLiveCSRelationReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local sql ="call Load_LiveCSRelation()"
    local arrRows =PlatformDB_SqlExecute(sql,true)
    -- tBase.Log("arrRows Len:%d",#arrRows)   

    local arrItems={}
    for _,row in ipairs(arrRows) do
        local item ={}
        item.SlaveServerId=tonumber(row.SlaveServerId)
        item.CenterServerId=tonumber(row.CenterServerId)
        table.insert(arrItems,item)
    end

    local DbLiveCSRelationRsp={}
    DbLiveCSRelationRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"DbLiveCSRelationRsp",DbLiveCSRelationRsp)
end


--银行密码验证请求处理
function ConfigReqHandle.OnDbCheckSafePasswordReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbCheckSafePasswordReq") 
    local strReq ="DbCheckSafePasswordReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql =string.format("call SafeBox_Verify(%d,%d,'%s')",tData.nUserId,0,tData.sPassword)
    local arrRows =AccountsDB_SqlExecute(sql)
    tBase.LogT(sql,' ',arrRows)
    assert(#arrRows ==1,'Err happen ,'..sql)

    local tRow =arrRows[1] ----fieds:  Result, nGold, 
    local DbCheckSafePasswordRsp={}
    DbCheckSafePasswordRsp.nUserId=tData.nUserId
    DbCheckSafePasswordRsp.nResult =tonumber(tRow.Result) or -1
    DbSendToServer(sReturnKey,"DbCheckSafePasswordRsp",DbCheckSafePasswordRsp)
end

--银行存取明细请求处理
function ConfigReqHandle.OnDbBankAccessDetailReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbBankAccessDetailReq") 
    local strReq ="DbBankAccessDetailReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql =string.format("call SafeBox_Detail(%d)",tData.nUserId)
    local arrRows =RecordDB_SqlExecute(sql)
    tBase.Log("arrRows Len_%d",#arrRows)
   
    local DbBankAccessDetailRsp ={}
    DbBankAccessDetailRsp.nUserId =tData.nUserId
    DbBankAccessDetailRsp.arrDetails={}
    for _,row in ipairs(arrRows) do
        local item ={}
        item.sTime =row.UpdateTime			                --时间
	    item.nOperation =tonumber(row.SourceType) or -1     --操作 0:存钱 1:取钱
        item.nGold =tonumber(row.UpdateCount) or 0		    --所操作的金币数目
        if item.nOperation==1001 then
            item.nOperation =0
        end
        if item.nOperation==1002 then
            item.nOperation =1
        end
        table.insert(DbBankAccessDetailRsp.arrDetails,item)
    end
    DbSendToServer(sReturnKey,"DbBankAccessDetailRsp",DbBankAccessDetailRsp) 
end

--银行密码更改请求处理
function ConfigReqHandle.OnDbBankPasswordChangeReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbBankPasswordChangeReq") 
    local strReq ="DbBankPasswordChangeReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql =string.format("call SafeBox_ReSetCode(%d,'%s','%s')",tData.nUserId,tData.sOldPassword,tData.sNewPassword)
    local arrRows =AccountsDB_SqlExecute(sql)
    tBase.LogT(sql,' ',arrRows)
    assert(#arrRows ==1,'Err happen ,'..sql)

    local tRow =arrRows[1] ----fieds:  Result
    local DbBankPasswordChangeRsp ={}
    DbBankPasswordChangeRsp.nUserId =tData.nUserId
    DbBankPasswordChangeRsp.nResult =tonumber(tRow.Result) or -1
    DbSendToServer(sReturnKey,"DbBankPasswordChangeRsp",DbBankPasswordChangeRsp)
end

--客户端当前版本信息请求
function ConfigReqHandle.OnVersionReq(sReturnKey, Data, nLen)
    tBase.Log("OnVersionReq") 
    local sql ="call Get_Version_Infos()"
    local arrRows =WebDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.sPlatform =row.Platform or 'null_string:'
        item.sChannel =row.Channel or 'null_string:'
        item.sVersion =row.Version or 'null_string'
        item.sDownloadurl =row.ZipFilePath or 'null_string'
        item.sAppurl =row.AppUrl or 'null_string'
        item.sConfigUrl =row.MD5FilePath or 'null_string'
        item.sConfigVersion=row.ConfigVersion or 'null_string'
        table.insert(arrItems,item)
    end
    local VersionRsp={}
    VersionRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"VersionRsp",VersionRsp)
end

function ConfigReqHandle.OnMainVersionReq(sReturnKey, Data, nLen)
    tBase.Log("MainVersionReq") 
    local sql ="call Get_Version_Infos_v2()"
    local arrRows =WebDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.nGroupId=tonumber(row.GroupID) or -1
        item.sVersion=row.Version or ""
        item.sPlatform =row.Platform or ""
        table.insert(arrItems,item)
    end
    local MainVersionRsp={}
    MainVersionRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"MainVersionRsp",MainVersionRsp)
end

--前端大厅游戏版本请求
function ConfigReqHandle.OnGameVersionReq(sReturnKey, Data, nLen)
    tBase.Log("OnGameVersionReq") 
    local sql ="call Get_LobbyGameVersion_Infos()"
    local arrRows =WebDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.nGroupId=tonumber(row.GroupID) or -1
        item.sVersion=row.Version or ""
		item.sGameCode=row.GameCode or ""
        item.sMD5FilePath=row.MD5FilePath or ""
        item.sZipFilePath=row.ZipFilePath or ""
        item.sPlatform=row.Platform or ""
        table.insert(arrItems,item)
    end

    local nLen = #arrItems
    local arrSend = {}
    for k,v in ipairs(arrItems) do
        table.insert(arrSend,v)
        if k%20 == 0 or k==nLen then
            local GameVersionRsp={}
            GameVersionRsp.arrItems=arrSend
            DbSendToServer(sReturnKey,"GameVersionRsp",GameVersionRsp)
            arrSend = {}
        end
    end
end


function ConfigReqHandle.OnMaintainerIpReq(sReturnKey, Data, nLen)
    tBase.Log("OnMaintainerIpReq") 
    local sql ="call Load_UserIP()"
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.sIp =row.IPAdress or ''
        item.nPort =tonumber(row.Port) or 0
        table.insert(arrItems,item)
    end
    local MaintainerIpRsp={}
    MaintainerIpRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"MaintainerIpRsp",MaintainerIpRsp)   
end

function ConfigReqHandle.OnGetResultsBySqlReq(sReturnKey, Data, nLen)
    local strReq ="GetResultsBySqlReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    tBase.Log("_OnGetResultsBySqlReq  sSql:  "..tData.sSql) 

    local arrRows =ExecuteDbSql(tData.sSql,tData.sDbName)
    local sJsonRows =""
    if arrRows then
        sJsonRows =cjson.encode(arrRows)
    end
    DbSendToServer1(sReturnKey,"GetResultsBySqlRsp",{sEcho=tData.sEcho,sJsonRows=sJsonRows,nUserId=tData.nUserId}) 
end

function ConfigReqHandle.OnDbJackpotSettleCReq(sReturnKey, Data, nLen)
    local strReq ="DbJackpotSettleCReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    tBase.Log("OnDbJackpotSettleCReq  sSql:  "..tData.sSql) 
    local arrRows =ExecuteDbSql(tData.sSql,tData.sDbName) or {}
    local arr={}
    for _,v in ipairs(arrRows) do
        local item={}
        item.nIssue=tonumber(v.Issue) 
		item.nBetArea=tonumber(v.BetArea)
		item.nBetGold=tonumber(v.BetGold)
		item.nWin=tonumber(v.Win)
		item.nBetTime=tonumber(v.BetTime)
		item.sElse=""
        table.insert(arr,item)
    end
    DbSendToServer1(sReturnKey,"DbJackpotSettleCRsp",{sEcho=tData.sEcho,arrRow=arr,nUserId=tData.nUserId}) 
end


function ConfigReqHandle.OnDbLiveRecordReq(sReturnKey, Data, nLen)
    local strReq ="DbLiveRecordReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("_OnRecentRecordReq Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupId =SetTimeZone(connection,tData.nUserId)  --设置使用的时区
    tBase.Log("_OnRecentRecordReq  nUserId:%d nGroupId:%d sTimeZone:%s",tData.nUserId,nGroupId,sTimeZone)
    local isNewRecord = false 
    local sql =string.format("call PaiJuWinLoseRecord_LiveGame_Read(%d,%d,%d,%d)",tData.nUserId,tData.nGameId,tData.nIdOfStart,tData.nCnt)    
    if #tData.sStartTime > 2 and #tData.sEndTime > 2 then 
        sql =string.format("call PaiJuWinLoseRecord_LiveGame_Read_Date(%d,%d,%d,%d,'%s','%s')"
        ,tData.nUserId,tData.nGameId,tData.nIdOfStart,tData.nCnt,tData.sStartTime,tData.sEndTime)
        isNewRecord= true 
    end        
    local arrRows= SqlExecut(sql,connection)
    tBase.LogT(sql,'arrRows: ',#arrRows)
    local arrRecords ={}
    local tStatistics = {}   -- 统计数据 
    tStatistics.nAllWinlose = 0    
    tStatistics.nAllBet = 0
    tStatistics.nAllValid = 0
    for _,row in ipairs(arrRows) do
        local item={}
        item.sPaiJuID=row.PaiJuId
        item.nProfit =tonumber(row.WinLose)
        item.sTime =row.CreatetTime
        item.nBet = tonumber(row.XiaZhu)
        item.nId =tonumber(row.id)
        table.insert(arrRecords,item)
        if isNewRecord then 
            tStatistics.nAllWinlose = tStatistics.nAllWinlose + tonumber(row.WinLose)
            tStatistics.nAllBet = tStatistics.nAllBet + tonumber(row.XiaZhu)
            tStatistics.nAllValid = tStatistics.nAllValid + tonumber(row.Valid)    
        end 
    end

    local DbLiveRecordRsp={}
    DbLiveRecordRsp.nUserId =tData.nUserId
	DbLiveRecordRsp.arrRecords = arrRecords
    DbLiveRecordRsp.nGameId=tData.nGameId
    DbLiveRecordRsp.nIdOfStart =tData.nIdOfStart
    DbLiveRecordRsp.sEcho =tData.sEcho
    DbLiveRecordRsp.nSumItem =0
    if #arrRows>0 then
        DbLiveRecordRsp.nSumItem =tonumber(arrRows[1].nSumItem) or 0
        if not isNewRecord then 
            DbLiveRecordRsp.nSumItem = #arrRecords            
        end 
    end    
    if isNewRecord then 
        DbLiveRecordRsp.sData = cjson.encode(tStatistics)
    end 

    --页数相关
    if tData.nPage then
        DbLiveRecordRsp.nPage = tData.nPage --第几页
        --计算总页数
        if tData.nIdOfStart<=0 and tData.nCnt>0 then 
            local sql_Count = string.format("call PaiJuWinLoseRecord_LiveGame_Count(%d,%d)",tData.nUserId,tData.nGameId)
            local arrRows_Count= SqlExecut(sql_Count,connection)
            tBase.LogT(sql_Count,' ',#arrRows_Count)
            local nCount = 0
            for _,row in ipairs(arrRows_Count) do
                nCount = tonumber(row.nCount) or 0 --战绩总条数
                break
            end
            DbLiveRecordRsp.nAllPage = math.ceil(nCount/tData.nCnt) --总页数
        end
    end

    DbSendToServer1(sReturnKey,"DbLiveRecordRsp",DbLiveRecordRsp)  
end

--自动下注遗漏记录 请求
function ConfigReqHandle.OnAutoBetMissingRecordReq(sReturnKey, Data, nLen)
    tBase.Log("OnAutoBetMissingRecordReq") 
    local strReq ="AutoBetMissingRecordReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local tD ={}
    tD.nUserId=tData.nUserId            --玩家id
	tD.nTimeStart=tData.nTimeStart      --开始时间戳
	tD.nTimeEnd=tData.nTimeEnd          --结束时间戳
	tD.nIdStart=tData.nIdStart          --
	tD.nCnt=tData.nCnt                  --记录条数
	tD.nGroupId=tData.nGroupId or -1
    tD.sCdtPaiJuId=tData.sCdtPaiJuId
    local arrRt =ConfigReqHandle._GetAutoBetMissingRecordV2(tD)

    local tAutoBetMissingRecordRsp={}
    tAutoBetMissingRecordRsp.nUserId=tData.nUserId              --玩家id
    tAutoBetMissingRecordRsp.nEcho=tData.nEcho			        --回文
    tAutoBetMissingRecordRsp.sJsonRlt=cjson.encode(arrRt)		--图个方便,结果用json
    
    DbSendToServer1(sReturnKey,"AutoBetMissingRecordRsp",tAutoBetMissingRecordRsp)  
end

--local tD={}
--tD.nUserId        --玩家id
--tD.nTimeStart     --开始时间戳
--tD.nTimeEnd       --结束时间戳
--tD.nIdStart       --
--tD.nCnt           --记录条数
--tD.nGroupId
function ConfigReqHandle._GetAutoBetMissingRecord(tD)
    local nUserId=tD.nUserId         --玩家id
    local nTimeStart=tD.nTimeStart   --开始时间戳
    local nTimeEnd=tD.nTimeEnd       --结束时间戳
    local nIdStart=tD.nIdStart       --
    local nQueryCnt=tD.nCnt          --记录条数
    local nGroupId =tD.nGroupId
    local sCdtPaiJuId=tD.sCdtPaiJuId

    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupIdTz =SetTimeZone(connection,nUserId)  --设置使用的时区
    tBase.Log("_GetAutoBetMissingRecord,nUserId:%d nGroupId:%d sTimeZone:%s",nUserId,nGroupIdTz,sTimeZone)

    --有问题，这nQueryCnt应该是无限大才对
    local sql =string.format("call BJLGTSettleRecord_Read_ByTime(%d,%d,%d,%d,%d)",nIdStart,nQueryCnt,nTimeStart,nTimeEnd,nGroupId)
    if sCdtPaiJuId and #sCdtPaiJuId>0 then
        sql =string.format("call BJLGTSettleRecord_Read_ByPaiJu(%d,%d,%d,%d,%d,'%s')",0,1,nTimeStart,nTimeEnd,nGroupId,sCdtPaiJuId)
    end

    local arrRows= SqlExecut(sql,connection) or {}
    tBase.Log("sql:%s rowCnt:%d",sql,#arrRows)
    if #arrRows==0 then
        return {}
    end
    local arrGTRlt={}       --好路开牌结果
    for _,row in ipairs(arrRows) do
        local item={}
        item.Id=tonumber(row.Id)			            --记录id (最大的就是最近的记录)
		item.sTime=row.CreatetTime		                --开牌时间
		item.sPaiJuId=row.PaiJuID		                --局号
		item.sTableName=row.TableName	                --桌号
		item.nTrendType=tonumber(row.TrendType)	        --好路类型 (详见本文件头 "好路类型定义")
        item.nTrend=tonumber(row.Trend)		            --趋势 1:顺路 0:逆路
        item.tOpenRlt={}	                            --开牌结果(闲和庄点数)
        item.tOpenRlt.nXianDian =tonumber(row.XianD)
        item.tOpenRlt.nZhuangDian=tonumber(row.ZhuangD)
		item.nIsOffLine=0	--是否离线下注 1:是 0:否
        table.insert(arrGTRlt,item)
    end
    
    sql =string.format("call BJLAutoBetRecord_Read_ByTime(%d,%d,%d,%d,%d)",nUserId,0,nQueryCnt,nTimeStart,nTimeEnd)
    if sCdtPaiJuId and #sCdtPaiJuId>0 then
        sql =string.format("call BJLAutoBetRecord_Read_ByPaiJu(%d,%d,%d,'%s')",nUserId,0,1,sCdtPaiJuId)
    end

    arrRows= SqlExecut(sql,connection) or {}
    tBase.Log("sql:%s rowCnt:%d",sql,#arrRows)
    local tPjIdToV={}
    for _,row in ipairs(arrRows) do
        tPjIdToV[row.PaiJuID]=tonumber(row.IsOffLine)
    end
    local arrRt={}
    for _,item in ipairs(arrGTRlt) do
        local nIsOffLine =tPjIdToV[item.sPaiJuId]
        if nIsOffLine==nil or nIsOffLine==1 then
            item.nIsOffLine =nIsOffLine or 0
            table.insert(arrRt,item)
        end
    end
    return arrRt
end

--local tD={}
--tD.nUserId        --玩家id
--tD.nTimeStart     --开始时间戳
--tD.nTimeEnd       --结束时间戳
--tD.nIdStart       --
--tD.nCnt           --记录条数
--tD.nGroupId
function ConfigReqHandle._GetAutoBetMissingRecordV2(tD)
    local nUserId=tD.nUserId         --玩家id
    local nIdStart=tD.nIdStart       --
    local nQueryCnt=tD.nCnt          --记录条数
    local nGroupId=tD.nGroupId
    local arrMissing=  tPublicRedis.GetLatelyMissingRecord(nUserId,nIdStart,nQueryCnt,nGroupId)     --{{Id=nS,sPaiJuId=sPaiJuId,nIsOffLine=0},...}
    if #arrMissing==0 then
        tBase.Log("_GetAutoBetMissingRecordV2,nUserId:%d,empty",nUserId)
        return {}
    end
    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupIdTz =SetTimeZone(connection,nUserId)  --设置使用的时区
    tBase.Log("_GetAutoBetMissingRecordV2,nUserId:%d nGroupId:%d sTimeZone:%s",nUserId,nGroupIdTz,sTimeZone)

    --创建sql语句,执行查找
    local arrTem={}
    local tPaiJuToId={}
    local tPaiJuToOffLine={}
    for _,v in ipairs(arrMissing) do
        table.insert(arrTem, string.format("'%s'",v.sPaiJuId))
        tPaiJuToId[v.sPaiJuId] =v.Id
        tPaiJuToOffLine[v.sPaiJuId] =v.nIsOffLine or 0
    end
    local sql =string.format("SELECT * FROM DJH_RecordDB.BJLGTSettleRecord WHERE PaiJuID IN(%s);",table.concat(arrTem,","))
    local arrRows= SqlExecut(sql,connection) or {}
    tBase.Log("sql:%s rowCnt:%d",sql,#arrRows)

    --处理sql执行结果
    local arrGTRlt={}       --好路开牌结果
    for _,row in ipairs(arrRows) do
        local item={}
        item.Id=tPaiJuToId[row.PaiJuID] or 0			    --记录id (最大的就是最近的记录)
		item.sTime=row.CreatetTime		                    --开牌时间
		item.sPaiJuId=row.PaiJuID		                    --局号
		item.sTableName=row.TableName	                    --桌号
		item.nTrendType=tonumber(row.TrendType)	            --好路类型 (详见本文件头 "好路类型定义")
        item.nTrend=tonumber(row.Trend)		                --趋势 1:顺路 0:逆路
        item.tOpenRlt={}	                                --开牌结果(闲和庄点数)
        item.tOpenRlt.nXianDian =tonumber(row.XianD)
        item.tOpenRlt.nZhuangDian=tonumber(row.ZhuangD)
		item.nIsOffLine=tPaiJuToOffLine[row.PaiJuID] or 0 --是否离线下注 1:是 0:否  --离线下注也算是遗漏
        table.insert(arrGTRlt,item)
    end
    table.sort(arrGTRlt,function(tA,tB) return tA.Id>tB.Id end)
    return arrGTRlt
end


--账号注销 请求
function ConfigReqHandle.OnDbAccountCloseReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbAccountCloseReq") 
    local strReq ="DbAccountCloseReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
   
    local sSql = string.format("call Close_Account('%s','%s',%d);",tData.sAccounts,tData.sPassword,tData.nUserId)
    local arrRows= AccountsDB_SqlExecute(sSql)
    local tRow =arrRows[1] or {nCode=1}
    local nCode =tonumber(tRow.nCode)
    tBase.LogT({nUserId=tData.nUserId,tRow=tRow,strReq=strReq})

    local  DbAccountCloseRsp={}
    DbAccountCloseRsp.nUserId=tData.nUserId
    DbAccountCloseRsp.nCode=nCode			--0:成功 其它:失败
    DbAccountCloseRsp.sErr=""
    
    DbSendToServer1(sReturnKey,"DbAccountCloseRsp",DbAccountCloseRsp) 
end

--检查账号是否重复注册 true:否
local function _CheckRepeatRegist(sAddr,nWay)
    local sSql = string.format("call RegistCheckRepeat('%s',%d);",sAddr,nWay)
    local arrRows= AccountsDB_SqlExecute(sSql)
    local tRow =arrRows[1] or {RecordCnt=0}
    local RecordCnt =tonumber(tRow.RecordCnt)
    return (RecordCnt==0)
end
--检查账号与手机或邮箱是否匹配
local function _CheckMatchAccAddr(sAddr,nWay,sAcc)
    if sAcc==nil or #sAcc==0 then
        return true
    end
    local sSql = string.format("call GetBindAddr('%s');",sAcc)
    local arrRows= AccountsDB_SqlExecute(sSql)
    local tRow =arrRows[1] or {}
    if nWay ==RegistWay.Phone then
        return tRow.Bin_Ding_PHone ==sAddr
    end
    if nWay ==RegistWay.Mail then
        return tRow.Mail ==sAddr
    end
    return true
end

--获取验证码请求
function ConfigReqHandle.OnDbVeriCodeReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbVeriCodeReq")
    local strReq ="DbVeriCodeReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local nWay =tData.nWay
    local sWayAddr =tData.sWayAddr
    local sClientID =tData.sClientID
    
    local sAcc =tData.sAcc or ""            --账号(密码重置时才填); 注册和绑定用途时不要填
    local nPurpose =tData.nPurpose or 0     --验证码用途(nil或0:注册与绑定; 1:密码重置)
    local nRlt =-1                          --0成功 -1接口错误 9验证方式错误 10请求过频 8手机号或邮箱格式错误 11重复注册 12手机号或邮箱与账号不匹配
    local sErr="send Error"
    
    if not checkAddr(sWayAddr,nWay) then                                    --检查手机号或邮箱格式是否正确
        nRlt =8
        sErr="sAddr format Error"
    elseif tMoblieBinder.IsTempExist(sClientID,sWayAddr,nPurpose) then               --检查请求是否过于频繁
        nRlt =10
        sErr ="req too fast"
    -- elseif nPurpose==0 and (not _CheckRepeatRegist(sWayAddr,nWay)) then     --检查是否重复注册
    --     nRlt =11
    --     sErr="Repeat Regist"
    elseif nPurpose==1 and (not _CheckMatchAccAddr(sWayAddr,nWay,sAcc)) then --检查账号与手机或邮箱是否匹配
        nRlt =12
        sErr="sAcc not match"
    elseif nPurpose==1 and _CheckRepeatRegist(sWayAddr,nWay) then           --密码重置时，检测手机或邮箱是否存在
        nRlt=12
        sErr="Phone or Mail not exist"
    elseif nWay ==RegistWay.Phone then
        nRlt =tMoblieBinder.SendVeriCodeByPhone(sWayAddr) and 0 or -1
    elseif nWay ==RegistWay.Mail then
        nRlt =tMoblieBinder.SendVeriCodeByMail(sWayAddr, nPurpose) and 0 or -1
    else
        nRlt =9
        sErr ="registWay Error"
    end
 
    if nRlt==0 then
        sErr="succee"
        tMoblieBinder.SetTemp(sClientID,sWayAddr,60,nPurpose)
    end

    tBase.LogT("OnVeriCodeReq ",{nRlt=nRlt,sWayAddr=sWayAddr,nWay=nWay,sErr=sErr})

    --返回
    local  DbVeriCodeRsp={}
    DbVeriCodeRsp.nRlt= nRlt
    DbVeriCodeRsp.sClientID =sClientID
    DbVeriCodeRsp.nWay =nWay 
    
    DbSendToServer1(sReturnKey,"DbVeriCodeRsp",DbVeriCodeRsp) 
end

--手机邮箱绑定 请求
function ConfigReqHandle.OnDbBindReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbBindReq")
    local strReq ="DbBindReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local nWay =tData.nWay                    --5:绑定手机 6:绑定邮箱
	local sAddrNew  =tData.sAddrNew           --新手机或邮箱地址
	local sVeriCode =tData.sVeriCode         --验证码(使用Logon.proto里的VeriCodeReq获取验证码)
	local sAddrOld  =tData.sAddrOld           --旧手机或邮箱地址  (更换绑定时需要填，新绑定不用)
	local sPassWord =tData.sPassWord         --登陆密码			(更换绑定时需要填，新绑定不用)
	local nUserId   =tData.nUserId             --
    local nPurpose = tData.nPurpose or 1
    tBase.LogT("OnDbBindReq ",{nWay=nWay,sAddrNew=sAddrNew,sVeriCode=sVeriCode,sAddrOld=sAddrOld,nUserId=nUserId})
    if not tMoblieBinder.VerifyCode(sAddrNew,sVeriCode,nWay==RegistWay.Phone,false,nPurpose) then
        tBase.Log("OnDbBindReq VerifyCode not pass")
        DbSendToServer1(sReturnKey,"DbBindRsp",{nUserId=nUserId,nRlt=20})
        return
    end

    local sSql = string.format("call Club_BindAcc(%d,'%s','%s','%s',%d);",nWay,sAddrNew,sAddrOld,sPassWord,nUserId)
    local arrRows= AccountsDB_SqlExecute(sSql)
    local tRow =arrRows[1] or {ErrCode=1}
    local ErrCode =tonumber(tRow.ErrCode)
    tBase.Log("OnDbBindReq ErrCode:%d nUserId:%d",ErrCode,nUserId)
    if ErrCode == 0 and nWay==RegistWay.Mail then
        tPubUserApi.UpdateUserData({["nEmail"] = sAddrNew, ["nUserID"] = nUserId})
    end
    DbSendToServer1(sReturnKey,"DbBindRsp",{nUserId=nUserId,nRlt=ErrCode})
end

local function bit_or(a, b)
    -- 纯 Lua 实现（无bit库时）
    local res, p = 0, 1
    while a > 0 or b > 0 do
        local aa, bb = a % 2, b % 2
        if aa == 1 or bb == 1 then
            res = res + p
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return res
end

--账号绑定查询请求
function ConfigReqHandle.OnDbBindQuerryReq(sReturnKey, Data, nLen)
    tBase.Log("DbBindQuerryReq") 
    local strReq ="DbBindQuerryReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sAcc =tData.sAcc or ""
    local sSql = string.format("call GetBindAddr('%s');",sAcc)
    local arrRows= AccountsDB_SqlExecute(sSql)
    local tRow =arrRows[1] or {}

    tBase.LogT("DbBindQuerryReq:",{sAcc=sAcc,tRow=tRow})

    local nphone =0
    local nmail =0
    if tRow.Bin_Ding_PHone and #tRow.Bin_Ding_PHone>0 then
        nphone =1
    end
    if tRow.Mail and #tRow.Mail>0 then
        nmail=2
    end

    local nRlt  = bit.bor(nphone,nmail);
    -- local nRlt =(nphone|nmail)  --0:没绑定 1:仅绑定手机 2:仅绑定邮箱 3:手机邮箱皆绑定

     --返回
     local  DbBindQuerryRsp={}
     DbBindQuerryRsp.nRlt= nRlt
     DbBindQuerryRsp.sClientID =tData.sClientID
     DbSendToServer1(sReturnKey,"DbBindQuerryRsp",DbBindQuerryRsp)
end

--密码重置请求   
function ConfigReqHandle.OnDbPasswordResetReq(sReturnKey, Data, nLen)
    tBase.Log("DbPasswordResetReq") 
    local strReq ="DbPasswordResetReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local nWay= tData.nWay			            --5:通过手机重置 6:通过邮箱重置
	local sAddrNew=tData.sAddrNew		        --手机或邮箱地址
	local sVeriCode=tData.sVeriCode	            --验证码(使用Logon.proto里的VeriCodeReq获取验证码)
	local sPasswordNew=tData.sPasswordNew or "" --使用的新密码
	local sClientID=tData.sClientID

    tBase.LogT("DbPasswordResetReq:",{nWay=nWay,sAddrNew=sAddrNew,sVeriCode=sVeriCode,nPasswordNewLen=#sPasswordNew})
    if not tMoblieBinder.VerifyCode(sAddrNew,sVeriCode,nWay==RegistWay.Phone,false) then
        tBase.Log("OnDbBinDbPasswordResetReqdReq VerifyCode not pass")
        DbSendToServer1(sReturnKey,"DbPasswordResetRsp",{nRlt=20,sClientID=sClientID})
        return
    end

    local sSql = string.format("call PasswordReset(%d,'%s','%s');",nWay,sAddrNew,sPasswordNew)
    local arrRows= AccountsDB_SqlExecute(sSql)
    local tRow =arrRows[1] or {ErrCode=1}
    local ErrCode =tonumber(tRow.ErrCode)
    tBase.Log("DbPasswordResetReq ErrCode:%d,sAddr:%s",ErrCode,sAddrNew)
    DbSendToServer1(sReturnKey,"DbPasswordResetRsp",{nRlt=ErrCode,sClientID=sClientID}) 
end


local SignAwardsCache={time=0,arrAwards={}}
local function _GetClubSignAwards()
    local nNow =os.time()
    if (nNow -SignAwardsCache.time) <300 then
        return SignAwardsCache.arrAwards
    end
    local connection =dbSink.GetDbConnectForRead("DJH_PlatformDB")
    local sql =string.format("select * from ClubUserSignAward where Days<=7 and Days>=1;")
    local arrRows= SqlExecut(sql,connection)
    local arrAwards ={}
    for _,tRow in ipairs(arrRows) do
        local item={nDays=tonumber(tRow.Days),nAward=tonumber(tRow.Award)}
        table.insert(arrAwards,item)
    end
    SignAwardsCache.time =nNow
    SignAwardsCache.arrAwards=arrAwards
    return arrAwards
end

--签到界面信息 请求
function ConfigReqHandle.OnDbSignInfoReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbSignInfoReq") 
    local strReq ="DbSignInfoReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupId =SetTimeZone(connection,tData.nUserId)  --设置使用的时区
    tBase.Log("OnDbSignInfoReq  nUserId:%d nGroupId:%d sTimeZone:%s",tData.nUserId,nGroupId,sTimeZone)
    local sql =string.format("call ClubSignInfoRead(%d)",tData.nUserId)
    local arrRows= SqlExecut(sql,connection)
    local tRow =arrRows[1]
    assert(tRow~=nil)
    local isSign =(tonumber(tRow.nIsSign)==1)
    local nDaysCur =tonumber(tRow.nDaysCur)
    local nPlayToday =tonumber(tRow.nPlayToday)
    local nPlayCntMax =tonumber(tRow.nPlayCntMax)
    local DbSignInfoRsp={}
    DbSignInfoRsp.arrAwards=_GetClubSignAwards()   --1~7天的奖励,大于7的奖励使用第7天的
    DbSignInfoRsp.nDaysCur=nDaysCur		            --当前天数,取值为1至无穷大
    DbSignInfoRsp.isSign=isSign			            --当天是否已经签到 true:是,false:否
    DbSignInfoRsp.nPlayCntCur=math.min(nPlayToday,nPlayCntMax)	        --当天手数
    DbSignInfoRsp.nPlayCntMax=nPlayCntMax	                            --可领奖的手数
    DbSignInfoRsp.nUserId=tData.nUserId
    tBase.LogT("DbSignInfoRsp ",DbSignInfoRsp)
    DbSendToServer1(sReturnKey,"DbSignInfoRsp",DbSignInfoRsp) 
end


--签到 请求
function ConfigReqHandle.OnDbSignReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbSignReq") 
    local strReq ="DbSignReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupId =SetTimeZone(connection,tData.nUserId)  --设置使用的时区
    tBase.Log("OnDbSignReq  nUserId:%d nGroupId:%d sTimeZone:%s",tData.nUserId,nGroupId,sTimeZone)
    local sql =string.format("call ClubSign(%d)",tData.nUserId)
    local arrRows= SqlExecut(sql,connection)
    local tRow =arrRows[1]
    assert(tRow~=nil)
    
    local DbSignRsp={}
    DbSignRsp.nRlt=tonumber(tRow.nRlt)			    --0:成功 其它:失败
    DbSignRsp.nAward=tonumber(tRow.nAward) or 0	    --签到成功时获得的金币奖励
    DbSignRsp.nUserId=tData.nUserId
    tBase.LogT("DbSignRsp ",DbSignRsp)
    DbSendToServer1(sReturnKey,"DbSignRsp",DbSignRsp) 
end

--领取绑定奖励 请求
function ConfigReqHandle.OnDbGetBindAwardReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbGetBindAwardReq") 
    local strReq ="DbGetBindAwardReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local nGroupId =tPubUserApi.Get_User_GroupId(tData.nUserId)
    local nAward= tPublicRedis.GetBindPhoneAward(nGroupId)

    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sql =string.format("call ClubGetBindAward_v2(%d,%d)",tData.nUserId,nAward)
    local arrRows= SqlExecut(sql,connection)
    local tRow =arrRows[1]
    assert(tRow~=nil)
    tBase.LogT("OnDbGetBindAwardReq ",{nUserId=tData.nUserId,tRow=tRow})
   
    local DbGetBindAwardRsp={}
    DbGetBindAwardRsp.nRlt=tonumber(tRow.nRlt) or -1	    --0:成功 其它:失败
    DbGetBindAwardRsp.nAward=tonumber(tRow.nAward) or -10	-- >=0:金币数量 -1:未绑定 -2:已领取
    DbGetBindAwardRsp.nUserId=tData.nUserId
    tBase.LogT("DbGetBindAwardRsp ",DbGetBindAwardRsp)
    DbSendToServer1(sReturnKey,"DbGetBindAwardRsp",DbGetBindAwardRsp) 
end


--自动下注遗漏记录胜率 请求
function ConfigReqHandle.OnAutoBetMissingWinRateReq(sReturnKey, Data, nLen)
    tBase.Log("OnAutoBetMissingWinRateReq") 
    local strReq ="AutoBetMissingWinRateReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local tD ={}
    tD.nUserId=tData.nUserId            --玩家id
	tD.nTimeStart=tData.nTimeStart      --开始时间戳
	tD.nTimeEnd=tData.nTimeEnd          --结束时间戳
	tD.nGroupId=tData.nGroupId or -1
    local arrItemTable,arrItemTrend =ConfigReqHandle._GetMissingWinRateRecordV2(tD)

    local tAutoBetMissingWinRateRsp={}
    tAutoBetMissingWinRateRsp.nUserId=tData.nUserId              --玩家id
    tAutoBetMissingWinRateRsp.nEcho=tData.nEcho			        --回文
    tAutoBetMissingWinRateRsp.sJsonRlt=cjson.encode({arrItemTable=arrItemTable,arrItemTrend=arrItemTrend})		--图个方便,结果用json
    tAutoBetMissingWinRateRsp.nTimeStart=tData.nTimeStart
    tAutoBetMissingWinRateRsp.nTimeEnd=tData.nTimeEnd

    DbSendToServer1(sReturnKey,"AutoBetMissingWinRateRsp",tAutoBetMissingWinRateRsp)  
end

--local tD={}
--tD.nUserId        --玩家id
--tD.nTimeStart     --开始时间戳
--tD.nTimeEnd       --结束时间戳
--tD.nGroupId
function ConfigReqHandle._GetMissingWinRateRecord(tD)
    local nUserId=tD.nUserId         --玩家id
    local nTimeStart=tD.nTimeStart   --开始时间戳
    local nTimeEnd=tD.nTimeEnd       --结束时间戳
    local nIdStart=0                    --
    local nQueryCnt=1200            --记录条数
    local nGroupId =tD.nGroupId
    tBase.Log("_GetMissingWinRateRecord,nUserId:%d nGroupId:%d",nUserId,nGroupId)

    local sql =string.format("call BJLGTSettleRecord_Read_ByTimeV2(%d,%d,%d,%d,%d)",nIdStart,nQueryCnt,nTimeStart,nTimeEnd,nGroupId)
    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local arrRows= SqlExecut(sql,connection) or {}
    tBase.Log("sql:%s rowCnt:%d",sql,#arrRows)
    if #arrRows==0 then
        return {},{}
    end

    sql =string.format("call BJLAutoBetRecord_Read_ByTimeV2(%d,%d,%d,%d,%d)",nUserId,0,nQueryCnt,nTimeStart,nTimeEnd)
    local arrRowsA= SqlExecut(sql,connection) or {}
    tBase.Log("sql:%s rowCnt:%d",sql,#arrRowsA)
    local tPjIdToV={}
    for _,row in ipairs(arrRowsA) do
        tPjIdToV[row.PaiJuID]=true
    end

    local tTableNameToInfo={}
    local tTrendTypeToInfo={}
    for _,row in ipairs(arrRows) do
        local nTrendType=tonumber(row.TrendType)
        local nTrend =tonumber(row.Trend)
        local sPaiJuId =row.PaiJuID
        local sTableName=row.TableName
        if not tPjIdToV[sPaiJuId] then
            local tA =tTableNameToInfo[sTableName] or {nCnt=0,nShunCnt=0}
            local tB =tTrendTypeToInfo[nTrendType] or {nCnt=0,nShunCnt=0}
            tTableNameToInfo[sTableName]=tA
            tTrendTypeToInfo[nTrendType] =tB
            tA.nCnt =tA.nCnt +1
            tB.nCnt =tB.nCnt +1
            if nTrend==1 then
                tA.nShunCnt =tA.nShunCnt +1
                tB.nShunCnt =tB.nShunCnt +1
            end
        end
    end
    local arrForTable ={}
    for sTableName,tInfo in pairs(tTableNameToInfo) do
        local tItem={}
        tItem.sTableName=sTableName
        tItem.nCnt=tInfo.nCnt
        tItem.nWinRate=math.floor((tInfo.nShunCnt/tInfo.nCnt)*100)
        table.insert(arrForTable,tItem)
    end
    local arrForTrendType={}
    for nTrendType,tInfo in pairs(tTrendTypeToInfo) do
        local tItem={}
        tItem.nTrendType=nTrendType
        tItem.nCnt=tInfo.nCnt
        tItem.nWinRate=math.floor((tInfo.nShunCnt/tInfo.nCnt)*100)
        table.insert(arrForTrendType,tItem)
    end
    return arrForTable,arrForTrendType
end


function ConfigReqHandle._GetMissingWinRateRecordV2(tD)
    local nUserId=tD.nUserId         --玩家id
   -- local nTimeStart=tD.nTimeStart   --开始时间戳
   -- local nTimeEnd=tD.nTimeEnd       --结束时间戳
    --local nIdStart=0                    --
   -- local nQueryCnt=1200            --记录条数
    local nGroupId =tD.nGroupId

    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local tSt={}
    for i=1,10 do
        local arrMissPaiju=tPublicRedis.GetUserMissingPaiJu(nUserId,50,nGroupId)
        if #arrMissPaiju==0 then
            break
        end
        local arrTem={}
        for _,sPaiJuId in ipairs(arrMissPaiju) do
            table.insert(arrTem, string.format("'%s'",sPaiJuId))
        end
        local sql =string.format("SELECT TableName,TrendType,Trend FROM DJH_RecordDB.BJLGTSettleRecord WHERE PaiJuID IN(%s);",table.concat(arrTem,","))
        local arrRows= SqlExecut(sql,connection) or {}
        for _,row in ipairs(arrRows) do
            local sNameField =string.format("name:%s:sum",row.TableName)
            local sTypeField =string.format("type:%s:sum",row.TrendType)
            local sNameFieldShun =string.format("name:%s:shun",row.TableName)
            local sTypeFieldShun =string.format("type:%s:shun",row.TrendType) 
            tSt[sNameField] =tSt[sNameField] or 0
            tSt[sTypeField] =tSt[sTypeField] or 0
            tSt[sNameField] =tSt[sNameField] +1
            tSt[sTypeField] =tSt[sTypeField] +1
            if tonumber(row.Trend)==1 then
                tSt[sNameFieldShun] =tSt[sNameFieldShun] or 0
                tSt[sTypeFieldShun] =tSt[sTypeFieldShun] or 0
                tSt[sNameFieldShun] =tSt[sNameFieldShun] +1
                tSt[sTypeFieldShun] =tSt[sTypeFieldShun] +1
            end
        end
    end
    -- local arrMissPaiju=tPublicRedis.GetUserMissingPaiJu(nUserId,50)
    local tNowSt=tPublicRedis.UpdateUserMissingWinRate(nUserId,tSt)
    local tTableNameToInfo={}
    local tTrendTypeToInfo={}
    for sKey,sV in pairs(tNowSt) do
        local tagA,tagB,tagC =string.match(sKey,"(.*):(.*):(.*)")       --桌子名称不能包含冒号(:),否则有问题
        local nCount =tonumber(sV)
        if tagA=="name" then
            local sTableName =tagB
            local tA =tTableNameToInfo[sTableName] or {nCnt=0,nShunCnt=0}
            if tagC=="sum" then
                tA.nCnt =nCount
            elseif tagC=="shun" then
                tA.nShunCnt =nCount
            end
            tTableNameToInfo[sTableName]=tA
        elseif tagA=="type" then
            local nTrendType =tonumber(tagB)
            local tA =tTrendTypeToInfo[nTrendType] or {nCnt=0,nShunCnt=0}
            if tagC=="sum" then
                tA.nCnt =nCount
            elseif tagC=="shun" then
                tA.nShunCnt =nCount
            end
            tTrendTypeToInfo[nTrendType]=tA
        end
    end

    local arrForTable ={}
    for sTableName,tInfo in pairs(tTableNameToInfo) do
        local tItem={}
        tItem.sTableName=sTableName
        tItem.nCnt=tInfo.nCnt
        tItem.nWinRate=math.floor((tInfo.nShunCnt/tInfo.nCnt)*100)
        table.insert(arrForTable,tItem)
    end
    local arrForTrendType={}
    for nTrendType,tInfo in pairs(tTrendTypeToInfo) do
        local tItem={}
        tItem.nTrendType=nTrendType
        tItem.nCnt=tInfo.nCnt
        tItem.nWinRate=math.floor((tInfo.nShunCnt/tInfo.nCnt)*100)
        table.insert(arrForTrendType,tItem)
    end
    return arrForTable,arrForTrendType
end


--近期战绩查询
function ConfigReqHandle.OnRecentRecordReq(sReturnKey, Data, nLen)
    tBase.Log("OnRecentRecordReq") 
    local strReq ="RecentRecordReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupId =SetTimeZone(connection,tData.nUserId)  --设置使用的时区
    tBase.Log("OnRecentRecordReq,nUserId:%d nGroupId:%d sTimeZone:%s",tData.nUserId,nGroupId,sTimeZone)

    local sql =string.format("call PaiJuWinLoseRecord_Read(%d,%d,%d)",tData.nUserId,tData.nGameId,tData.nPage)
    local arrRows= SqlExecut(sql,connection)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems={}
    local mMaxCount = 0
    for _,row in ipairs(arrRows) do
        local item={}
        item.sPaiJuID=row.PaiJuId
        item.nRoomId =tonumber(row.Session)
        item.nProfit =tonumber(row.WinLose)
        item.sTime =row.CreatetTime
        item.nType = tonumber(row.nType)
        item.nAnte = tonumber(row.XiaZhu)
        mMaxCount = tonumber(row.mMaxCount)
        table.insert(arrItems,item)
    end
    local RecentRecordRsp={}
    RecentRecordRsp.nUserId =tData.nUserId
	RecentRecordRsp.arrRecords = arrItems
    RecentRecordRsp.nGameId=tData.nGameId
    RecentRecordRsp.nMaxCount = mMaxCount
    DbSendToServer(sReturnKey,"RecentRecordRsp",RecentRecordRsp)   

    --  迁移过去战绩记录
    -- local sql =string.format("call PaiJuWinLoseRecord_Read_BackUp(%d,%d)",tData.nUserId,tData.nGameId)
    -- local arrRows= RecordDB_SqlExecute(sql,true)

end

--下注记录查询(飞行棋小游戏)
function ConfigReqHandle.OnDbBetRecordReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbBetRecordReq") 
    local strReq ="DbBetRecordReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse—error—strReq:"..strReq)
        return
    end
    local connection =dbSink.GetDbConnectForRead("DJH_RecordDB")
    local sTimeZone,nGroupId =SetTimeZone(connection,tData.nUserId)  --设置使用的时区
    tBase.Log("OnDbBetRecordReq,nUserId:%d nGroupId:%d sTimeZone:%s",tData.nUserId,nGroupId,sTimeZone)

    if tData.nStatus==2 then
        local sql =string.format("call PaiJuWinLoseRecord_PilotRead(%d,%d,%d)",tData.nUserId,tData.nMinId,tData.nQueryCnt)
        local arrRows= SqlExecut(sql,connection)
        tBase.LogT(sql,' ',#arrRows)
        local arrItems={}
        for _,row in ipairs(arrRows) do
            local item={}
            item.sSeriesNumber=row.CreatetTime     --row.PaiJuId	        --期号
            item.nGameId =tonumber(row.GameType)	--游戏id
            item.Id=tonumber(row.id)				--记录id. (最大的就是最近的记录)
            item.nAnte=tonumber(row.XiaZhu)			--下注金币(底分)
            item.nGoldWin =tonumber(row.WinLose)    --输赢金币
            table.insert(arrItems,item)
        end
        DbSendToServer1(sReturnKey,"DbBetRecordRsp",{arrItem={},arrTtem=arrItems,nUserId=tData.nUserId,nStatus=tData.nStatus})
        return
    end

    local sql =string.format("call BettingRecord_Read(%d,%d,%d,%d,%d)",tData.nUserId,tData.nGameType,tData.nMinId,tData.nQueryCnt,tData.nStatus)
    local arrRows= SqlExecut(sql,connection)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.sSeriesNumber= row.BetTime --row.SeriesNumber	    --期号
		item.nGameId =tonumber(row.Game)		--游戏id
		item.nArean=tonumber(row.BetArea)		--对应游戏的下注区域
		item.nOdds=tonumber(row.Odds)			--赔率
		item.nBet=tonumber(row.BetGold)			--下注金币
		item.nBall =tonumber(row.Ball)   		--时时彩有效,[1~5]分别表示第[1~5]球
        item.Id=tonumber(row.id)				--记录id. (最大的就是最近的记录)
        item.nGoldWin =tonumber(row.GoldWin)
        table.insert(arrItems,item)
    end
    DbSendToServer1(sReturnKey,"DbBetRecordRsp",{arrItem=arrItems,nUserId=tData.nUserId,nStatus=tData.nStatus})
end

--近期牌局记录查询
function ConfigReqHandle.OnRecentDetailReq(sReturnKey, Data, nLen)
    tBase.Log("OnRecentDetailReq") 
    local strReq ="RecentDetailReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse—error—strReq:"..strReq)
        return
    end
    local sql =string.format("call PaiJuDetail_Read(%d,'%s')",tData.nUserId,tData.sPaiJuID)
    if tData.nVer ==2 then
        sql =string.format("call PaiJuDetail_Read_v2(%d,'%s')",tData.nUserId,tData.sPaiJuID)
    end

    local arrRows= RecordDB_SqlExecute(sql,true)
    tBase.LogT(sql,' sqlLen: ',#arrRows," nUserID=",tData.nUserId)
    if arrRows==nil or #arrRows<=0 then 
        tBase.LogT("牌局为空:",tData.sPaiJuID," 玩家:",tData.nUserId)
        arrRows[1] = {GameId=-1,Ante=-1,UsersInfo="{}",Zhuang=-1,DealCardInfo="{}",BetInfo="{}",WinLose=-1,ElseInfo="{}"}
    end
    local RecentDetailRsp={}
    RecentDetailRsp.GameId =tonumber(arrRows[1].GameId) or -1
	RecentDetailRsp.nAnte =tonumber(arrRows[1].Ante) or -1
    RecentDetailRsp.tUsersInfo =arrRows[1].UsersInfo or "{}"
    RecentDetailRsp.nZhuang =tonumber(arrRows[1].Zhuang) or -1 
    RecentDetailRsp.tDealCardInfo =arrRows[1].DealCardInfo or "{}"
    RecentDetailRsp.tBetInfo=arrRows[1].BetInfo or "{}"
    RecentDetailRsp.nWinLose = tonumber(arrRows[1].WinLose) or -1
    RecentDetailRsp.tElseInfo = arrRows[1].ElseInfo or "{}"
    RecentDetailRsp.nUserId =tonumber(tData.nUserId) 
    RecentDetailRsp.sPaiJuID =tData.sPaiJuID
    DbSendToServer1(sReturnKey,"RecentDetailRsp",RecentDetailRsp)
end

function ConfigReqHandle.OnLoadBalancingReq(sReturnKey, Data, nLen)
    tBase.Log("OnLoadBalancingReq") 
    local sql ="call Load_LoadBalancing()"
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrList ={}
    for _,row in ipairs(arrRows) do
        local item ={}
        item.sIp= row.Ip
		item.nPort =tonumber(row.Port)
		item.sPlatform = row.Platform
		item.sChannel 	= row.Channel
		item.nSocketType =tonumber(row.ScoketType)
        item.nServGroupId =tonumber(row.ServGroupID)
        table.insert(arrList,item)
    end
    local LoadBalancingRsp={}
    LoadBalancingRsp.arrList =arrList
    DbSendToServer(sReturnKey,"LoadBalancingRsp",LoadBalancingRsp)   
end


function ConfigReqHandle.OnPlatformChannelShopReq(sReturnKey, Data, nLen)
    tBase.Log("OnPlatformChannelShopReq") 
    local sql ="call Load_PlatformChannelShop()"
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems ={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.sPlatform= row.Platform
		item.sChannel=row.Channel
        item.nShopId=tonumber(row.ShopID)
        table.insert(arrItems,item)
    end
    local PlatformChannelShopRsp={}
    PlatformChannelShopRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"PlatformChannelShopRsp",PlatformChannelShopRsp) 
end

function ConfigReqHandle.OnRefowardRuleReq(sReturnKey, Data, nLen)
    tBase.Log("OnRefowardRuleReq") 
    local sql ="call Load_ReforwardRule_v2()"
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems ={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.nServerId= tonumber(row.ServerId)
		item.nGroupId=tonumber(row.GroupId)
        table.insert(arrItems,item)
    end
    local RefowardRuleRsp={}
    RefowardRuleRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"RefowardRuleRsp",RefowardRuleRsp)    
end

function ConfigReqHandle.OnServerIdOfMaitainingReq(sReturnKey, Data, nLen)
    tBase.Log("OnServerIdOfMaitainingReq") 
    local sql ="SELECT ID,State FROM ServerInfo WHERE State=2 or State=3"
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrItems ={}
    for _,row in ipairs(arrRows) do
        local item={}
        item.nServerId= tonumber(row.ID)
		item.nState=tonumber(row.State)
        table.insert(arrItems,item)
    end

    local ServerIdOfMaitainingRsp={}
    ServerIdOfMaitainingRsp.arrItems=arrItems
    DbSendToServer(sReturnKey,"ServerIdOfMaitainingRsp",ServerIdOfMaitainingRsp)  
end


function ConfigReqHandle.OnWhiteListReq(sReturnKey, Data, nLen)
    tBase.Log("OnWhiteListReq")
    local sql ="call Load_WhiteList()"
    local arrRows =AccountsDB_SqlExecute(sql)
    tBase.LogT(sql,' ',#arrRows)
    local arrUserId ={}
    for _,row in ipairs(arrRows) do
        table.insert(arrUserId,tonumber(row.UserId))
    end
    local WhiteListRsp={}
    WhiteListRsp.arrUserId=arrUserId
    DbSendToServer(sReturnKey,"WhiteListRsp",WhiteListRsp)
end

function ConfigReqHandle.OnSqlExcuteReq(sReturnKey, Data, nLen)
    tBase.Log("OnSqlExcuteReq") 
    local strReq ="SqlExcuteReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        return
    end
    ConfigReqHandle.sql[tData.sPaiJuID] = ConfigReqHandle.sql[tData.sPaiJuID] or ""
    ConfigReqHandle.sql[tData.sPaiJuID] = ConfigReqHandle.sql[tData.sPaiJuID]..tData.sSql
    
    if tData.bEnd then
        ExecuteDbSql(ConfigReqHandle.sql[tData.sPaiJuID],tData.sDbName)
        tBase.Log( tData.sPaiJuID.." ——PaiJuDetail.Sql:"..ConfigReqHandle.sql[tData.sPaiJuID])
        ConfigReqHandle.sql[tData.sPaiJuID] = nil
    end
end
function ConfigReqHandle.OnDbSqlExcuteReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbSqlExcuteReq") 
    local strReq ="DbSqlExcuteReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        return
    end
    tBase.Log(tData.sSql)
    ExecuteDbSql(tData.sSql,tData.sDbName)
    
end

--直播桌子创建
function ConfigReqHandle.OnDbLiveTableCreateReq(sReturnKey, Data, nLen)
    local strReq ="DbLiveTableCreateReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        return
    end 
    local sql =tData.sSql
    tBase.Log("OnDbLiveTableCreateReq sSql:"..tData.sSql) 
    local arrRows= RecordDB_SqlExecute(sql,false)
end
--直播桌子关闭
function ConfigReqHandle.OnDbLiveTableCloseReq(sReturnKey, Data, nLen)
    local strReq ="DbLiveTableCloseReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        return
    end
    local sTableId =tData.sTableId
    local sExData =tData.sExData or ""
    local sql =string.format("call LiveTableClose('%s','%s')",sTableId,sExData)
    tBase.Log(sql)
    local arrRows= RecordDB_SqlExecute(sql,false)
end

--主播绑定与解绑记录
function ConfigReqHandle.OnDbLiveBingdingReq(sReturnKey, Data, nLen)
    local strReq ="DbLiveBingdingReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        return
    end
    tBase.Log("OnDbLiveBingdingReq sSql:"..tData.sSql) 
    local arrRows= RecordDB_SqlExecute(tData.sSql,false)
end

function ConfigReqHandle.OnDbAdCfgListReq(sReturnKey, Data, nLen)
    local strReq ="DbAdCfgListReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        assert(false,"Err happen ,Parse error strReq_AdCfg:"..strReq) 
    end
    local arrAdItem ={}
    local sql = "call Load_Notice_Config()"
    local arrRows = PlatformDB_SqlExecute(sql)
    tBase.Log("AdCfgList_arrRows_Len:"..#arrRows.." sKey:"..sReturnKey)
    for _,row in ipairs(arrRows) do        
        local AdItem ={}
        AdItem.ID =tonumber(row.ID) or 1;
        AdItem.Scope =tonumber(row.Scope) or 1; -- 公告范围：1 大厅 2、游戏房间, 3、大厅+游戏服, 4、停服公告	  
        AdItem.Channel =tostring(row.Channel) or ""; -- 渠道 
        AdItem.StartTime =tostring(row.StartTime) or os.time() ; -- 公告开始时间
        AdItem.EndTime =tostring(row.EndTime) or os.time(); -- 公告结束时间
        AdItem.Frequency =tonumber(row.Frequency) or 0; -- 不重复播放0
        AdItem.Details =row.Details 
        table.insert(arrAdItem,AdItem)
    end

    local tSend = ProtoMgr.DbServer_pb.DbAdCfgListRsp() 
    for k=1,#arrAdItem do
        local tt = tSend.arrAdItem:add()
        tt.ID = arrAdItem[k].ID
        tt.Scope = arrAdItem[k].Scope
        tt.Channel = arrAdItem[k].Channel
        tt.StartTime = arrAdItem[k].StartTime
        tt.EndTime = arrAdItem[k].EndTime
        tt.Frequency = arrAdItem[k].Frequency
        tt.Details = arrAdItem[k].Details
    end 
    
    local s = tBase.GetSP().new(dbCmd.Main_CMD,dbCmd.DbAdCfgListRsp_CMD)
    s:AddString(tSend:SerializeToString())
    tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
end

--写记录 公共
function ConfigReqHandle.OnDbWriteRecordPublicReq(sReturnKey, Data, nLen)
    local strReq ="DbWriteRecordPublicReq"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq) 
        return
    end
    -- tBase.Log("_OnDbWriteRecordPublicReq sSql:"..tData.sSql) 
    local arrRows = RecordDB_SqlExecute(tData.sSql,false)
    -- if arrRows and  arrRows[1].ErrorCode and arrRows[1].ErrorInfo then
    --     tBase.Log('_OnDbWriteRecordPublicReq  ErrorCode:  '..arrRows[1].ErrorCode..', ErrorInfo:'..arrRows[1].ErrorInfo)
    -- end 
end

--服务器分组关系请求
function ConfigReqHandle.OnServerGroupRelationReq(sReturnKey, Data, nLen)
    local strReq ="ServerGroupRelationReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        return
    end

    local sSql1 = string.format("call Load_LiveCSRelation()")
    local arrRelation = {}
    local arrRows1 =PlatformDB_SqlExecute(sSql1)
    for _,row in ipairs(arrRows1) do        
        local nCenterServerId = tonumber(row.CenterServerId)
        local nSlaveServerId = tonumber(row.SlaveServerId)
        if nCenterServerId and nSlaveServerId and nCenterServerId~=nSlaveServerId then
            arrRelation[nCenterServerId] = arrRelation[nCenterServerId] or {}
            table.insert(arrRelation[nCenterServerId],nSlaveServerId)
        end
    end

    local sSql = string.format("call Load_ReforwardRule_v2()")
    local arrItems = {}
    local arrRows =PlatformDB_SqlExecute(sSql)
    for _,row in ipairs(arrRows) do        
        local tItem ={}
        tItem.nServerId = tonumber(row.ServerId)
        tItem.nGroupId = tonumber(row.GroupId)
        if tItem.nServerId and tItem.nGroupId then
            table.insert(arrItems,tItem)
            if arrRelation[tItem.nServerId] and #arrRelation[tItem.nServerId]>0 then
                for _,nSlaveServerId in pairs(arrRelation[tItem.nServerId]) do
                    table.insert(arrItems,{nServerId=nSlaveServerId,nGroupId=tItem.nGroupId})
                end
            end
        end
    end
    
    local nLen = #arrItems
    local nSendLen = 100
    local nPage = 1
    local nAllPage = 1
    if nLen>nSendLen then
        local arrTemp = {}
        local nAllPage = math.ceil(nLen/nSendLen)
        for i=1,nLen do
            table.insert(arrTemp,arrItems[i])
            if i%nSendLen==0 or i==nSendLen then
                local ServerGroupRelationRsp = {}
                ServerGroupRelationRsp.arrItems = arrTemp
                ServerGroupRelationRsp.nPage = nPage
                ServerGroupRelationRsp.nAllPage = nAllPage
                DbSendToServer1(sReturnKey,"ServerGroupRelationRsp",ServerGroupRelationRsp)
                arrTemp = {}
                nPage = nPage + 1
            end
        end
    else
        local ServerGroupRelationRsp = {}
        ServerGroupRelationRsp.arrItems = arrItems
        ServerGroupRelationRsp.nPage = nPage
        ServerGroupRelationRsp.nAllPage = nAllPage
        DbSendToServer1(sReturnKey,"ServerGroupRelationRsp",ServerGroupRelationRsp)
    end
end
 
-- 加载服务器信息 
function ConfigReqHandle._LoadServerInfoData()
    local sql =string.format("select * from ServerInfo ;")
    local arrRows =PlatformDB_SqlExecute(sql)
    tBase.Log("_LoadServerInfoData   sql: %s  arrRows Len:%d",sql,#arrRows)
    if not arrRows then
        return
    end
    local arrServerInfo = {}
    local sKey =string.format("SeverInfoConfig")
	local tRedis = tBase.m_MyRedisData[1].redis
    for _,row in pairs(arrRows) do
        local t ={}
        t.nServerId=tonumber(row.ID)
        t.sName= row.Name or ""
        t.nStype=tonumber(row.SType)
        t.nPort=tonumber(row.Port)
        t.nSocketType=tonumber(row.ScoketType)
        t.nMachineID=tonumber(row.MachineID)
        t.nState=tonumber(row.State)
        tRedis:hset(sKey,t.nServerId,cjson.encode(t))
    end
end

--牌局Hash记录请求
function ConfigReqHandle.OnDbWritePaiJuHashReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbWritePaiJuHashReq")
    local strReq ="DbWritePaiJuHashReq"
    local tData = DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql = tData.sSql
    tBase.Log("OnDbWritePaiJuHashReq sSql:"..tData.sSql)
    local arrRows = RecordDB_SqlExecute(sql, false)
    tBase.LogT(arrRows)
    -- DbSendToServer1(sReturnKey,"ServerGroupRelationRsp",ServerGroupRelationRsp)
end

--Hash指定局牌序列请求
function ConfigReqHandle.OnDbGetHashCardReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbGetHashCardReq")
    local strReq ="DbGetHashCardReq"
    local tData = DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    tBase.Log("OnDbGetHashCardReq sTableId::%s sPaiJuId:%s", tData.sTableId, tData.sPaiJuId)
    local sql = string.format("CALL PaiJuHashRecord_get('%s','%s')", tData.sTableId, tData.sPaiJuId)
    local arrRows = RecordDB_SqlExecute(sql, true)
    tBase.LogT(arrRows)
    arrRows1 = arrRows and arrRows[1] or {}
    local DbGetHashCardRsp = {}
    DbGetHashCardRsp.nUserId = tData.nUserId
    DbGetHashCardRsp.nCards = arrRows1.Cards or ""
    DbGetHashCardRsp.nDetail = arrRows1.ExData or ""
    DbGetHashCardRsp.seed = arrRows1.Seed or ""
    DbGetHashCardRsp.cardHash = arrRows1.CardHash or ""
    DbGetHashCardRsp.nIsShow = tonumber(arrRows1.IsShow) or 0
    DbSendToServer1(sReturnKey,"DbGetHashCardRsp",DbGetHashCardRsp)
end

--牌局花费记录存储请求
function ConfigReqHandle.OnDbWriteRecordCostReq(sReturnKey, Data, nLen)
    tBase.Log("OnDbWriteRecordCostReq")
    local strReq ="DbWriteRecordCostReq"
    local tData = DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end
    local sql = tData.sSql
    tBase.Log("OnDbWriteRecordCostReq sSql:"..tData.sSql)
    local arrRows = RecordDB_SqlExecute(sql, false)
    tBase.LogT(arrRows)
    -- DbSendToServer1(sReturnKey,"ServerGroupRelationRsp",ServerGroupRelationRsp)
end

--后台增减金币请求
function ConfigReqHandle.OnChangeGoldReq(sReturnKey, Data, nLen)
    local tData = BackstageAux:Parser(Data, nLen, "ChangeGoldReq")
    if tData == nil then
       tBase.Log("OnChangeGoldReq _Parse Err")
       return
    end
    tBase.Log("OnChangeGoldReq nUserId:%d nGold:%.2f sResultKey:%s nSourceType:%d nAssetType:%d nOpUserName:%s nOpUserId:%d",
        tData.nUserId,tData.nGold,tData.sResultKey,tData.nSourceType,tData.nAssetType,tData.nOpUserName or "", tData.nOpUserId or 0)
    
    local nItemId = tData.nAssetType or 1
    local nChannel = tData.nShopId or -1
    local nSourceType = tData.nSourceType
    local nRoomId = -1

    local tUser = tPubUserApi.GetUserInfo(tData.nUserId) or {}
    if next(tUser) == nil then -- 离线玩家操作
        tBase.Log("OnChangeGoldReq nUserId:%d offlin", tData.nUserId)
        local sql = string.format("select * from Accounts_Treasure where UserID = %d and ItemID = 1", tData.nUserId)
        local arrRows =AccountsDB_SqlExecute(sql)
        tBase.LogT(arrRows)
        if arrRows==nil or #arrRows ~=1 then
            tBase.Log("OnChangeGoldReq  ERROR 25 sql:%s fail",sql)
            SetWebRedisResulte(tData.sResultKey,{nRlt=25,sErr="sql ERROR"})
            return
        end
        local tRow =arrRows[1]
        local nNowAmounts =tonumber(tRow.Count) or 0 --玩家当前金币
        local exData = {}
        if nSourceType == 100012 then -- 运营红包处理
            exData = {
                RedId = tData.nOpUserId,
                nUserId = 888,
                nName = tData.nOpUserName
            }
            tData.nOpUserId = 888
            nSourceType = 100007
        end
        exData = cjson.encode(exData)
        tBase.Log("OnChangeGoldReq nUserId:%d nNowAmounts:%.2f",tData.nUserId,nNowAmounts)
        local sSql =string.format("Call WriteUserTreasure2(%d,%d,%d,%.3f,%d,%d,'%s',%d,'%s','%s','%s')",tData.nUserId,nChannel,nItemId,tData.nGold,nSourceType,nRoomId,tData.nOpUserName or "",tData.nOpUserId or 0, "", "",exData)
        if tData.nGold < 0 then  -- 扣钱
            if nNowAmounts <= 0 then
                SetWebRedisResulte(tData.sResultKey,{nRlt=2,sErr="Gold del not enough"})
                return
            end
        else
        end
        arrRows = AccountsDB_SqlExecute(sSql)
        tBase.LogT(arrRows)
        if arrRows==nil or #arrRows ~=1 then
            tBase.Log("OnChangeGoldReq  ERROR 26 sql:%s fail",sql)
            SetWebRedisResulte(tData.sResultKey,{nRlt=26,sErr="sql ERROR"})
            return
        end
        tRow =arrRows[1]
        local nResult = tonumber(tRow.Result)
        if nResult ~= -1 then
            SetWebRedisResulte(tData.sResultKey,{nRlt=0})
            return
        else
            SetWebRedisResulte(tData.sResultKey,{nRlt=3, sErr = "error happen"})
            return
        end
    else
        tBase.Log("OnChangeGoldReq nUserId:%d online", tData.nUserId)
        local nLockGold = 0
        if tData.nGold < 0 and math.abs(tData.nGold) > 1e-6 then
            nLockGold = tData.nGold
            local nGold = tPubUserApi.Get_User_UnLockGold(tData.nUserId, 1)
            if nLockGold > 0 and math.abs(nGold - nLockGold) >1e-6 then
                tBase.Log("OnChangeGoldReq fail UserId:%d, nGold:%.2f, nLockGold:%.2f ",tData.nUserId, nGold, nLockGold)
                SetWebRedisResulte(tData.sResultKey, {nRlt=33,sErr="del gold not enough"})
                return
            end
        end
        local ok = tPubUserApi.ChangeUserTreasure({nUserID = tData.nUserId, nItemID= nItemId, nDel = tData.nGold, nSourceType = nSourceType, nOpUserName = tData.nOpUserName or "", nOpUserId = tData.nOpUserId or 0})
        if not ok then
            tBase.Log("OnChangeGoldReq fail UserId:%d, nGold:%.2f",tData.nUserId, tData.nGold)
            SetWebRedisResulte(tData.sResultKey, {nRlt=34,sErr="change gold err"})
            return
        end
        local nGameId, _, sServerKey = tPubUserApi.GetUserPlayingGame(tData.nUserId)
        if sServerKey and #sServerKey>0 and tData.nGold > 0 then
            local nNowGold = tPubUserApi.Get_User_Gold(tData.nUserId,nItemId)
            local DbRechargeRsp={}
            DbRechargeRsp.nRlt=0
            DbRechargeRsp.nUserId=tData.nUserId
            DbRechargeRsp.sSerialNumber=""
            DbRechargeRsp.nItemId=nItemId
            DbRechargeRsp.nAmount=tData.nGold
            DbRechargeRsp.sResultKey=tData.sResultKey
            DbRechargeRsp.nCurrentAmount= nNowGold
            local tPacket =_DbProtoEncode1("DbRechargeRsp",DbRechargeRsp)
            tBase.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
            tBase.Log("_OnRechargeReq  充值成功,通知游戏 nUserId: %d nNowGold: %f  nItemId: %d  sServerKey: %s ",tData.nUserId,nNowGold,nItemId,sServerKey)
        else
            local nNowGold = tPubUserApi.Get_User_Gold(tData.nUserId,nItemId)
            tBase.Log("OnChangeGoldReq  充值成功,通知大厅 nUserId: %d nNowGold: %f  nItemId: %d ",tData.nUserId,nNowGold,nItemId)
        end
        SetWebRedisResulte(tData.sResultKey,{nRlt=0})
    end
    return
end


--[[
-- 插入充值地址信息
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function ConfigReqHandle.OnDBInsertClientAddressReq(sReturnKey, Data, len)
    local strReq = "PayInsertClientAddressReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayInsertClientAddressReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayInsertClientAddressReq strReq:"..strReq)
        return
    end
    tBase.Log("suc: PayInsertClientAddressReq")

    -- 执行数据库操作
    local sSql = string.format("CALL Pay_InsertClientAddress('%s')", tData.strAddressArr)
    local arrRows = AccountsDB_SqlExecute(sSql)
    
    -- 构造响应消息
    local rspData = {}
    rspData.nCode = 0
    rspData.nUserId = tData.nUserId
    
    -- 发送响应
    DbSendToServer(sReturnKey, "PayInsertClientAddressRsp", rspData)
   
end

--[[
-- 更新充值地址
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function ConfigReqHandle.OnDbUpdateAddressReq(sReturnKey, Data, len)
    local strReq ="PayUpdateAddressReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayUpdateAddressReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayUpdateAddressReq strReq:"..strReq)
        return
    end
    tBase.Log("PayUpdateAddressReq")

    -- 执行数据库操作
    local sSql = string.format("CALL Pay_UpdateAddress(%d, '%s')", tData.nUserID, tData.strNewPayAddress)
    local arrRows = AccountsDB_SqlExecute(sSql)
    
    -- 构造响应消息
    --local rspData = {}
    --rspData.nCode = 0
    --rspData.nUserId = tData.nUserId
    
    -- 发送响应
    --DbSendToServer(sReturnKey, "PayUpdateAddressRsp", rspData)
end

--[[
-- 插入付款信息
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function ConfigReqHandle.OnDbInsertPayInfoReq(sReturnKey, Data, len)
    local strReq ="PayInsertPayInfoReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayInsertPayInfoReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayInsertPayInfoReq strReq:"..strReq)
        return
    end
    tBase.Log("PayInsertPayInfoReq")

    -- 执行数据库操作
    local sSql = string.format("CALL Pay_InsertPayInfo(%d, '%s', '%s', '%s', '%s', '%s', '%s', %d)", 
        tData.nUserID, tData.sOrderID, tData.sAmount, tData.sChannel, tData.sCurrency, tData.sTopup_url, tData.sFee, tData.nResult)
    local arrRows = AccountsDB_SqlExecute(sSql)
    tBase.LogT(arrRows)

    -- 构造响应消息
    --local rspData = {}
    --rspData.nCode = 0
    --rspData.nUserId = tData.nUserId
    
    -- 发送响应
    --DbSendToServer(sReturnKey, "Pay_InsertPayInfoRsp", rspData)
end

--[[
-- 更新付款信息
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function ConfigReqHandle.OnDbUpdatePayInfoReq(sReturnKey, Data, len)
    local strReq ="PayUpdatePayInfoReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayUpdatePayInfoReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayUpdatePayInfoReq strReq:"..strReq)
        return
    end
    tBase.Log("PayUpdatePayInfoReq")

    -- 执行数据库操作
    local sSql = string.format("CALL Pay_UpdatePayInfo('%s', '%s', '%s', '%s', '%s')", 
        tData.sFrom, tData.sTo, tData.sAmount, tData.sTxHash, tData.sContract)
    local arrRows = AccountsDB_SqlExecute(sSql)
    if arrRows==nil or #arrRows ~=1 then
        tBase.Log("OnDbUpdatePayInfoReq  ERROR 25 sql:Pay_UpdatePayInfo fail")
        return
    end

    -- 更新玩家身上钱
    local tRow = arrRows[1]
    if tRow == nil or tRow["nUserID"] == nil then
        tBase.Log("tRow == nil or tRow[nUserID] == nil")
        return
    end
    local amount = tonumber(tData.sAmount)

    local nUserID = math.floor(tonumber(tRow["nUserID"]))
    local tUser = tPubUserApi.GetUserInfo(nUserID) or {}
    if next(tUser) == nil then -- 离线玩家操作
        local sSql =string.format("Call WriteUserTreasure2(%d,%d,%d,%.3f,%d,%d,'%s',%d,'%s','%s','%s')",nUserID,-1,1,amount,100010,-1,"",nUserID, "", "", cjson.encode({}))
        arrRows = AccountsDB_SqlExecute(sSql)
        if arrRows == nil or #arrRows ~=1 then
            tBase.Log("PayUpdatePayInfoReq  ERROR 26 sql:%s fail",sSql)
            return
        end
        tRow = arrRows[1]
        local nResult = tonumber(tRow.Result)
        if nResult ~= -1 then
            tBase.Log("OnDbUpdatePayInfoReq fail 1 UserId:%d, nGold:%.2f",tData.nUserId, amount)
            return
        else
            tBase.Log("PayUpdatePayInfoReq  nResult:%d", nResult)
        end
    else
        local ok = tPubUserApi.ChangeUserTreasure({nUserID = nUserID, nItemID= 1, nDel = amount, nSourceType = 100010, "", 0})
        if not ok then
            tBase.Log("OnDbUpdatePayInfoReq fail UserId:%d, nGold:%.2f",tData.nUserId, amount)
            return
        end
    end
    
    -- 构造响应消息
    local rspData = {}
    rspData.nCode = 0
    rspData.nUserId = nUserID
    rspData.sAmount = tData.sAmount
    DbSendToServer(sReturnKey, "PayUpdatePayInfoRsp", rspData)
end


--[[
-- 插入提现信息
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function ConfigReqHandle.OnDbInsertWithdrawInfoReq(sReturnKey, Data, len)
    local strReq = "PayInsertWithdrawInfoReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayInsertWithdrawInfoReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayInsertWithdrawInfoReq strReq:"..strReq)
        return
    end
    tBase.Log("PayInsertWithdrawInfoReq")

    -- 执行数据库操作
    local sSql = string.format("CALL Pay_InsertWithdrawalInfo(%d, '%s', '%s', '%s', '%s', '%s', '%s', %d)", 
    tData.nUserID, tData.sOrderID, tData.sToAddr, tData.sInputAmount, tData.sRealAmount, tData.sTxHash, tData.sRemark, tData.sResult)
    local arrRows = AccountsDB_SqlExecute(sSql)
    tBase.LogT(arrRows)
    tBase.Log(sSql)
    if arrRows==nil or #arrRows ~=1 then
        tBase.Log("OnChangeGoldReq  ERROR 25 sql:%s fail",sSql)
        SetWebRedisResulte(tData.sResultKey,{nRlt=25,sErr="sql ERROR"})
        return
    end

    if tData.sResult == 0 then
        -- 更新玩家身上钱
        local nUserID = math.floor(tonumber(tData.nUserID))
        local ok = tPubUserApi.ChangeUserTreasure({nUserID = nUserID, nItemID= 1, nDel = -tonumber(tData.sInputAmount), nSourceType = 100011, "", 0})
        if not ok then
            tBase.Log("OnChangeGoldReq fail UserId:%d, nGold:%s",tData.nUserId, tData.sInputAmount)
            return
        end
    end


    -- 构造响应消息
    -- local rspData = {}
    -- rspData.nCode = tData.sResult
    -- rspData.nUserId = math.floor(tData.nUserId)
    
    -- --发送响应
    -- DbSendToServer(sReturnKey, "PayInsertWithdrawInfoRsp", rspData)
end



--[[
-- 获取支付地址
-- sClientID：用户ID
-- Data：请求数据
-- len：数据长度
]] 
function ConfigReqHandle.OnDbGetPayAddressReq(sReturnKey, Data, len)
    tBase.Log("--OnDbGetPayAddressReq")
    local rspData = {}
    rspData.nCode = 1
    rspData.sPayAddres = ""

    local strReq ="PayGetPayAddressReq"
    local tData =DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error PayGetPayAddressReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error PayGetPayAddressReq strReq:"..strReq)

            -- 发送响应
        DbSendToServer(sReturnKey, "PayGetPayAddressRsp", rspData)
        return
    end
    
    -- 执行数据库操作
    local payAddress = ""
    local sSql = string.format("CALL Pay_GetPayAddress('%s', %d)", payAddress, tData.nUserID)
    local arrRows = AccountsDB_SqlExecute(sSql)
    if not arrRows or #arrRows<=0 then
        tBase.Log("Err happen ,Parse error OnDbGetPayAddressReq strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnDbGetPayAddressReq strReq:"..strReq)

        -- 发送响应
        DbSendToServer(sReturnKey, "PayGetPayAddressRsp", rspData)
        return
    end 

    local row = arrRows[1]
    if row == nil or row["OutAddress"] == nil or row["OutAddress"] == "" then
        -- payAddress为空，说明DB中没有这样的未使用的充值地址
        -- 需要再次请求
        local fullURL = payConfig.host.."/pay/v1/topup/address?num=10" 

        -- 否则如果没有可以用地址，直接向钱包请求
        local err, code, result  = myHttp.request(fullURL)
        tBase.Log("--OnDbGetPayAddressReq")
        if  result == nil or result.data == nil then
            tBase.Log("AccountPayURLRsp  Get Fail")
            
            -- 发送响应
            DbSendToServer(sReturnKey, "PayGetPayAddressRsp", rspData)
            return false
        end

        -- 从返回的数据中读取地址信息
        local addressArr = result.data
        if addressArr == nil or #addressArr == 0 then
            tBase.Log("addressArr == nil or #addressArr == 0")

            -- 发送响应
            DbSendToServer(sReturnKey, "PayGetPayAddressRsp", rspData)
            return false
        end

        -- 遍历地址数组，提取每个地址
        local insertObject = {}  -- 存储所有地址
        for i, addrObj in ipairs(addressArr) do
            if addrObj and addrObj.address then  -- 添加对addrObj和address的检查
                local addressItem  = {}  -- 存储所有地址
                addressItem .address = addrObj.address
                addressItem .idx = string.format("%d", addrObj.idx)
                addressItem .create_at = addrObj.create_at
                table.insert(insertObject, addressItem )
                tBase.Log("获取到地址[%d]: %s, idx: %d", i, addrObj.address, addrObj.idx)
            end
        end

        -- 检查是否有可用地址
        if #insertObject == 0 then
            tBase.Log("没有获取到有效的地址")
            DbSendToServer(sReturnKey, "PayGetPayAddressRsp", rspData)
            return false
        end

        -- 选择第一个address作为最终的支付地址
        payAddress = insertObject[1].address
        rspData.sPayAddres = payAddress

        -- 将地址数组转换为字符串格式以便存储到数据库
        local addressStrArr = ""
        local addressTimeArr = ""
        local idxArr = ""
        for i, oneObjec in ipairs(insertObject) do
            if i > 1 then
                idxArr = idxArr.. ","  
                addressStrArr = addressStrArr .. ","  
                addressTimeArr = addressTimeArr .. ","  
            end

            addressStrArr = addressStrArr .. oneObjec.address
            addressTimeArr = addressTimeArr .. oneObjec.create_at
            idxArr = idxArr .. oneObjec.idx
        end

        -- 保存地址到数据库
        local nTmpUserID = tonumber(tData.nUserID)
        local nUserID = math.floor(nTmpUserID)
        local sSql = string.format("CALL Pay_InsertClientAddress('%s', '%s','%s',%d)", addressStrArr, addressTimeArr, idxArr, nUserID)
        local arrRows = AccountsDB_SqlExecute(sSql)
    else
        rspData.sPayAddres = row["OutAddress"]
    end

    -- 发送响应
    tBase.Log("row.OutAddress :"..payAddress)
    rspData.nUserID = tData.nUserID
    DbSendToServer(sReturnKey, "PayGetPayAddressRsp", rspData)
end

-- 获取全局配置请求
function ConfigReqHandle.OnDbGetGloBalConfigReq(sReturnKey, Data, nLen)
    tBase.Log("DbGetGloBalConfigReq")
    local strReq ="DbGetGloBalConfigReq"
    local tData =DbProtoParse1(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error  strReq:"..strReq)
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local arr ={}
    local sql ="call Load_GlobalConfig()"
    local arrRows = PlatformDB_SqlExecute(sql, true)
    tBase.Log("GloBalConfig arrRows Len:%d", #arrRows)
    for _,row in ipairs(arrRows) do
        local item ={}
        item.nId =tonumber(row.id) or 0
        item.name = row.nName or ""
        item.detail =row.detail or ""
        item.content = row.content or ""
        table.insert(arr,item)
    end
    local DbGetGloBalConfigRsp={}
    DbGetGloBalConfigRsp.nList = arr
    DbSendToServer1(sReturnKey,"DbGetGloBalConfigRsp",DbGetGloBalConfigRsp)
end


--[[
-- 写入系统通知消息
-- Data：请求数据
-- len：数据长度
]]
function ConfigReqHandle.OnLobbyNotifyRecordReq(sReturnKey, Data, len)
    local strReq ="LobbyNotifyRecordReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("LobbyNotifyRecordReq Err happen ,Parse error strReq:"..strReq)
        return
    end
    local nType = tData.nType or 0
    local exData = {sMsg = tData.sMsg}
    if nType > 0 then
        exData.nType = nType
    end
    exData = cjson.encode(exData)
    local sSql= string.format("call Club_WriteUserNotice(%d,%d,'%s')", tData.nUserId, tData.nMsgType, exData)
    tBase.Log("LobbyNotifyRecordReq sSql1:%s", sSql)

    local arrRows = RecordDB_SqlExecute(sSql)
    if not arrRows or #arrRows<=0 then
        tBase.Log("LobbyNotifyRecordReq Err happen ,Parse error strReq:"..strReq)
        return
    end

    local LobbyNotifyRecordRsp = {}
    LobbyNotifyRecordRsp.nCode = tonumber(arrRows[1].ErrCode)
    LobbyNotifyRecordRsp.nUserId = tData.nUserId
    LobbyNotifyRecordRsp.nMsgType = tData.nMsgType
    LobbyNotifyRecordRsp.strMsg = tData.sMsg
    LobbyNotifyRecordRsp.nMsgID = tonumber(arrRows[1].nId)
    DbSendToServer(sReturnKey, "LobbyNotifyRecordRsp", LobbyNotifyRecordRsp)
end


--[[
-- 更新某个用户的系统通知消息
-- Data：请求数据
-- len：数据长度
]]
function ConfigReqHandle.OnUpdateLobbyNotifyRecordReq(sReturnKey, Data, len)
    local strReq ="UpdateLobbyNotifyRecordReq"
    local tData = DbProtoParse(Data, len,strReq)
    if not tData then
        tBase.Log("LobbyNotifyRecordReq Err happen ,Parse error strReq:"..strReq)
        return
    end

    local sSql = string.format("call Club_SetUserNoticesRead(%d,%d,%d,%d)",  0, 30, tData.nUserId, tData.nMsgType)
    tBase.Log("OnUpdateLobbyNotifyRecordReq sSql2:%s", sSql)
    local arrRows = RecordDB_SqlExecute(sSql)
    if not arrRows or #arrRows<=0 then
        tBase.Log("LobbyNotifyRecordReq Err happen ,Parse error strReq:"..strReq)
        return
    end

    local row2 = arrRows[1]
    if row2 then
        tBase.Log("call Club_SetUserNoticesRead result :"..tostring(row2))
    end
end



-- 玩家个人通知 请求
function ConfigReqHandle.OnClubUserNoticeReq(sReturnKey,Data,nLen)
    tBase.Log("enter OnClubUserNoticeReq")

    local strReq ="ClubUserNoticeReq"
    local tData = DbProtoParse(Data, nLen,strReq)
    if not tData then
        assert(false,"Err happen ,Parse error strReq:"..strReq)
        return
    end

    local arrNotices = {}
    local nAllCnt = 0
    local arrApplyList = {}
    local nUnReadCnt = nil

    if tData.nType==1 then
        local sSql = string.format("call Club_GetUserNotices(%d,%d,%d,%d)",tData.nIdOfStart,tData.nCnt,tData.nUserId,tData.nType)
        tBase.Log("OnClubUserNoticeReq sSql:%s",sSql)
        local tType ={}
        local arrRows = RecordDB_SqlExecute(sSql,true)
        for _,row in pairs(arrRows) do
            local tNoticesItem = {}
            tNoticesItem.nId = tonumber(row.id) or 0
            tNoticesItem.nType = tonumber(row.nType) or 0
            tNoticesItem.nStatus = tonumber(row.nStatus) or 0
            tNoticesItem.sTime = row.CreateTime or ""
            tNoticesItem.sData = row.sData or ""
            tNoticesItem.nUserId = tonumber(row.UserId) or 0
            tNoticesItem.nHadRead = tonumber(row.HasRead) or 0
            table.insert(arrNotices,tNoticesItem)
            nAllCnt = tonumber(row.nAllCnt) or 0
            tType[tNoticesItem.nType]=true
        end

        
        --设置已读
        for nType,_ in pairs(tType) do
            local sSql2 = string.format("call Club_SetUserNoticesRead(%d,%d,%d,%d)",tData.nIdOfStart,tData.nCnt,tData.nUserId,nType)
            tBase.Log("OnClubUserNoticeReq sSql2:%s",sSql2)
            local arrRows2 = RecordDB_SqlExecute(sSql2)
            local row2 = arrRows2[1]
            if row2 then
                nUnReadCnt =nUnReadCnt or 0
                nUnReadCnt = nUnReadCnt +tonumber(row2.nUnReadCnt)
            end
        end
    elseif tData.nType==2 then
        local sSql = string.format("call Club_GetUserInvitation(%d,%d,%d)",tData.nIdOfStart,tData.nCnt,tData.nUserId)
        tBase.Log("OnClubUserNoticeReq sSql:%s",sSql)
        local arrRows = RecordDB_SqlExecute(sSql,true)
        for _,row in pairs(arrRows) do
            local tExtData = {}
            tExtData.nMaster = tonumber(row.MasterId)
            tExtData.sClubName = row.ClubName
            tExtData.nClubId = tonumber(row.ClubId)
            tExtData.sFaceId = row.FaceID
            tExtData.sUserName = row.NickName
            tExtData.nUserId = tonumber(row.Invitee)

            local tNoticesItem = {}
            tNoticesItem.nId = tonumber(row.id) or 0
            tNoticesItem.nType = tData.nType
            tNoticesItem.nStatus = tonumber(row.nStatus) or 0
            tNoticesItem.sTime = row.CreateTime or ""
            tNoticesItem.sData = cjson.encode(tExtData)
            tNoticesItem.nUserId = tonumber(row.UserId) or 0
            table.insert(arrNotices,tNoticesItem)
            nAllCnt = tonumber(row.nAllCnt) or 0
        end
    elseif tData.nType==3 then
        local sSql = string.format("call Club_GetUserApplyList(%d,%d,%d)",tData.nIdOfStart,tData.nCnt,tData.nUserId)
        tBase.Log("OnClubUserNoticeReq sSql:%s",sSql)
        local arrRows = RecordDB_SqlExecute(sSql,true)
        for _,row in pairs(arrRows) do
            local tApplyInfo = {}
            tApplyInfo.nId = tonumber(row.id) or 0
            tApplyInfo.nClubId = tonumber(row.ClubId) or 0
            tApplyInfo.nType = 3
            tApplyInfo.sTime = row.CreateTime or ""
            tApplyInfo.sClubName = row.ClubName or ""
            tApplyInfo.nStatus = tonumber(row.nStatus) or 0
            table.insert(arrApplyList,tApplyInfo)
            nAllCnt = tonumber(row.nAllCnt) or 0
        end
    end

    local ClubUserNoticeRsp = {}
    ClubUserNoticeRsp.arrNotices = arrNotices
    ClubUserNoticeRsp.nAllCnt = nAllCnt
    ClubUserNoticeRsp.nUserId = tData.nUserId
    ClubUserNoticeRsp.nType = tData.nType
    ClubUserNoticeRsp.arrApplyList = arrApplyList
    ClubUserNoticeRsp.nUnReadCnt = nUnReadCnt
    DbSendToServer(sReturnKey,"ClubUserNoticeRsp",ClubUserNoticeRsp)
end

return ConfigReqHandle