package.path = require("./lua/DB_s/Head").path


local tBase     = require("base")           -- 基础功能接口
local tName     = require("typename")
local tErr      = require("ErrorSink")       -- 捕捉错误
local tPubUsrApi  = require("PublicUserInfo")   -- 用户信息  
local cjson     = require("cjson")        -- json 
local ProtoMgr   = require("ProtoManager") -- 协议管理对象 
local mlogger    = require("logger")
local tPublicRedis    = require("PublicRedis")
require("ControlTableLink")

TreasureSink = {}


-- 获取玩家财富数据
function TreasureSink.GetUserTreasureInfo(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()

    local Read = ProtoMgr.PubProto_pb.RUQ_GetTreasure()
    Read:ParseFromString(ReadData:GetString())
    local tData = {}
    tData.nClientID    = Read.nClientID
    tData.nUserID      = Read.nUserID
    local sSql         = Read.sSql

    tBase.Log("_GetUserTreasureInfo  请求获取财富数据  sSql %s  ",sSql)  
    local cursor = assert (dbSink.AccountsDB_connect:execute (sSql))  
    repeat
        row = cursor:fetch({},"a")
        while row do  
           function TreasureSink.GetRes(row)
               tData.nGold = tonumber(row.nGold) or 0  
               tBase.Log("_GetUserTreasureInfo 玩家 %d  财富数据 nGold：%f ",tData.nUserID,tData.nGold) 
           end  
           xpcall(TreasureSink.GetRes,tErr.tpLog, row)
            row = cursor:fetch(row,"a")
        end
        cursor:close()
        cursor = dbSink.AccountsDB_connect:nextres()
    until( cursor == 0 ) 
    TreasureSink.PushTreasureData(sReturnKey,tData)
end

-- 给玩家发送 财富数据
function TreasureSink.PushTreasureData(sReturnKey,tData)
    local Send = ProtoMgr.PubProto_pb.RUP_GetTreasure()
    Send.nClientID = tData.nClientID
    Send.nUserID   = tData.nUserID
    Send.nGold     = tData.nGold  
    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_READTREASURE)
    s:AddString(Send:SerializeToString())      
    tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
    tBase.Log("_PushTreasureData   玩家： %d 修改财富数据成功     主动推送nGold: %f DB成功  ",tData.nUserID,tData.nGold)
end 

-- 修改玩家财富数据
function TreasureSink.WriteTreasure(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local Read = ProtoMgr.PubProto_pb.RUP_WriteTreasure()
    Read:ParseFromString(ReadData:GetString())
    local sSql    = Read.sSql
    local tUserTreasure = {}
    local nResult = 0
    local tResInfo = {}
    tBase.Log("_WriteTreasure  sSql_%s ",sSql)
    nResult,tUserTreasure = TreasureSink.ExecuteDbSql(sSql) 
    if nResult ~= 0 then 
        if nResult == 1 and tUserTreasure ~= nil then 
            mlogger:error(string.format("_WriteTreasure nUserID:  %d nGold:  %f  扣金币有问题,成负数了.  ",tUserTreasure["nUserID"],tUserTreasure["nGold"]))
        else
            tBase.Log("_WriteTreasure  修改失败 nResult_%d sSql： %s   ",nResult,sSql) 
        end  
    end
    return
end

-- 直播修改财富数据
function TreasureSink.BR_WriteTreasure(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local Read = ProtoMgr.PubProto_1_pb.RUP_BRWriteTreasure()
    Read:ParseFromString(ReadData:GetString())

    local nRoomId        = Read.nRoomId
    local nSourceType    = Read.nSourceType
    local arrUserTreasure  = Read.arrUserTreasure
    local nItemID = 1 
    local nTime = os.time()

    tBase.Log("_BR_WriteTreasure  sum_%d ",#arrUserTreasure )
    local arrError = {}
    for Index,tData in pairs(arrUserTreasure) do
        local sSql = "Call BR_WriteUserTreasure("..tData.nUserId..","..tData.nChannel..","..nItemID..","..tData.nDel..","..nSourceType..","..nRoomId..")"        
        tBase.Log("_BR_WriteTreasure  %d  %s  ",Index,sSql)
        local nResult = TreasureSink.ExecuteDbSql(sSql) 
        if nResult ~= 0 then 
            -- tBase.Log(" Index_%d  BR WriteTreasure   Error sSql_%s  ",Index,sSql )
            arrError[tData.nUserId] = sSql  
        end 

        if Index == #arrUserTreasure then break end         
    end
    nTime =  nTime - os.time()
    if next(arrError) == nil then 
        tBase.Log("_BR WriteTreasure   succee  size_%s   ",#arrUserTreasure)
    else
        for nUserId,sSql in pairs(arrError) do
            tBase.Log(" nUserId_%d  BR WriteTreasure   Error sSql_%s  ",nUserId,sSql )
        end
    end     
    return
end

function TreasureSink.ExecuteDbSql(sSql)
    local nResult = 0
    local nUserID = 0
    local nGold = 0
    local tUserTreasure = {}
    local tResInfo = {}
    local cursor = assert (dbSink.AccountsDB_connect:execute(sSql))
    repeat
        row = cursor:fetch({},"a")
        while row do 
           function TreasureSink.GetRes(row)
               if row.ErrorCode ~= nil then
                    tResInfo.ErrorCode = row.ErrorCode
                    tResInfo.ErrorInfo = row.ErrorInfo
                    nResult = 2 
                    --tBase.Log("error:_WriteTreasure 失败,  sSql_%s  Code:%s, Info:%s",sSql,tResInfo.ErrorCode, tResInfo.ErrorInfo)
                    mlogger:error(string.format("error:_WriteTreasure 失败,  sSql_%s  Code:%s, Info:%s ",sSql,tResInfo.ErrorCode, tResInfo.ErrorInfo))
                else
                    nResult = tonumber(row.Result)
                    if nResult ~= -1 then 
                        tUserTreasure.nUserID = tonumber(row.nUserId)
                        tUserTreasure.nGold  = tonumber(row.Gold)  
                        tUserTreasure.nItemID  = tonumber(row.nItemID)  
                        tBase.Log("_ExecuteDbSql   nResult: %d 【0成功, 1钱不够扣,2扣钱失败】%s  "
                        ,nResult,cjson.encode(tUserTreasure)) 
                    end 
                end
           end  
           xpcall(TreasureSink.GetRes,tErr.tpLog, row)
           row = cursor:fetch(row,"a")
        end
        cursor:close()
        cursor = dbSink.AccountsDB_connect:nextres()
    until( cursor == 0 )
    return nResult,tUserTreasure
end


function TreasureSink.WriteScoreLocker(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local sSql = ReadData:GetString()

    assert (dbSink.TreasureDB_connect:execute (sSql))
end  


-- 写入牌桌输赢情况
function TreasureSink.WriteControlTableWinLose(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local s = base.GetRP().new(sData, nLen)
    local Read = ProtoManager.PubProto_1_pb.REQ_Control_TableInfo()
    Read:ParseFromString(s:GetString())    
    Read.nShopId = math.floor(Read.nShopId)
    Read.nGameId = math.floor(Read.nGameId)
    Read.nLevelId = math.floor(Read.nLevelId)
    local sSql = string.format("Call DJH_TreasureDB.T_SetTableWinLoseStat(%d, %d, %d, '%s', %f, %f, '%s')",
                                        Read.nShopId, Read.nGameId, Read.nLevelId, Read.sTableId, Read.dWinLose, Read.dDrawWater, Read.sPaiJuId);
   
    local tResInfo = {}
    tResInfo.dStatVal = 0
    local cursor =  assert (dbSink.TreasureDB_connect:execute (sSql))
    local nIndex = 0
    repeat
        local row = cursor:fetch({}, "a")
        while row do
            function GetRes(row)
                if row.ErrorCode ~= nil then
                    tResInfo.ErrorCode = row.ErrorCode
                    tResInfo.ErrorInfo = row.ErrorInfo
                else
                    tResInfo.dStatVal =tonumber(row.StatVal)
                end
            end
            xpcall(GetRes,tErr.tpLog, row)
            row = cursor:fetch(row, "a")
        end
        cursor:close()
        cursor = dbSink.TreasureDB_connect:nextres()
    until(cursor == 0)

    if tResInfo.ErrorCode ~= nil then 
        --tBase.Log(" 写入牌桌失败, Code:%s, Info:%s", tResInfo.ErrorCode, tResInfo.ErrorInfo)
        mlogger:error(string.format("写入牌桌失败, Code:%s, Info:%s ",tResInfo.ErrorCode, tResInfo.ErrorInfo))
        tBase.Log(" 写入牌桌失败 -------->sSql:   "..sSql)

        assert(false)
    else

        tBase.Log(" 写入牌桌成 -------->sSql:   "..sSql)

        ControlTableLink.SetPool(Read.nShopId, Read.nGameId, Read.nLevelId, Read.sTableId, tResInfo.dStatVal, Read.dWinLose + Read.dDrawWater)
        ControlTableLink.SetWebRes(Read.nShopId, Read.nGameId, Read.nLevelId, Read.sTableId, 1)
    end 

end


-- 写入控制记录
function TreasureSink.Control_Info(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local Read = ProtoManager.PubProto_1_pb.REQ_Control_Record()
    Read:ParseFromString(ReadData:GetString())
    local sSql = Read.sSql    
    tBase.Log("_Control_Info  sSql:"..sSql)
    local tRoomInfo = {}
    local cursor =  assert (dbSink.TreasureDB_connect:execute (sSql))
    local nIndex = 0
    repeat
        local row = cursor:fetch({}, "a")
        while row do
            function GetRes(row)
                tRoomInfo.Result =tonumber(row.Result)
            end
            xpcall(GetRes,tErr.tpLog, row)
            row = cursor:fetch(row, "a")
        end
        cursor:close()
        cursor = dbSink.TreasureDB_connect:nextres()
    until(cursor == 0)
end


-- 写入房间统计数据 //废弃
function TreasureSink.WriteRoomData(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local s = base.GetRP().new(sData, nLen)
    local Read = ProtoManager.PubProto_1_pb.REQ_Control_Room_Data()
    Read:ParseFromString(s:GetString())
    
    Read.nShopId = math.floor(Read.nShopId)
    Read.nGameId = math.floor(Read.nGameId)
    Read.nLevelId = math.floor(Read.nLevelId)
    Read.nUserId = math.floor(Read.nUserId)

    local f1 = function ()
    end

    local f2 = function ()
        local tResInfo = {}
        local sSql = string.format("Call DJH_TreasureDB.R_SetUserWinLoseStat(%d, %d, %d, %d, %f, %f)",
            Read.nShopId, Read.nGameId, Read.nLevelId, Read.nUserId, Read.dWinLose, Read.dDrawWater);

        local cursor =  assert (dbSink.TreasureDB_connect:execute (sSql))
        local nIndex = 0
        repeat
            local row = cursor:fetch({}, "a")
            while row do
                function GetRes(row)
                    if row.ErrorCode ~= nil then
                        tResInfo.ErrorCode = row.ErrorCode
                        tResInfo.ErrorInfo = row.ErrorInfo
                    else
                        Read.dRoomUserStat =tonumber(row.StatVal)
                        Read.dUserStat =tonumber(row.UserStatVal)

                        -- tBase.Log("Read.isFirst 1:"..tostring(Read.isFirst))

                        if row.IsFirst == nil or tonumber(row.IsFirst) == 0 then
                            Read.isFirst = true
                          --   tBase.Log("Read.isFirst 2:"..tostring(Read.isFirst))
                        else
                            Read.isFirst = false
                            -- tBase.Log("Read.isFirst 3:"..tostring(Read.isFirst))
                        end

                       --  tBase.Log(" isFirst  UserID:"..Read.nUserId..", res:"..tostring(Read.isFirst)..", row.IsFirst:"..row.IsFirst)
                    end
                end
                xpcall(GetRes,tErr.tpLog, row)
                row = cursor:fetch(row, "a")
            end
            cursor:close()
            cursor = dbSink.TreasureDB_connect:nextres()
        until(cursor == 0)

        if tResInfo.ErrorCode ~= nil then 
            --tBase.Log(" R_SetUserWinLoseStat失败, Code:%s, Info:%s", tResInfo.ErrorCode, tResInfo.ErrorInfo)
            mlogger:error(string.format("R_SetUserWinLoseStat失败, Code:%s, Info:%s ",tResInfo.ErrorCode, tResInfo.ErrorInfo))
            tBase.Log(" R_SetUserWinLoseStat失败 -------->sSql:   "..sSql)
            assert(false)
        else
            tBase.Log(" R_SetUserWinLoseStat成功 -------->sSql:   "..sSql)
        end 
    end

    local f3 = function ()

        Read.nLock = 0
        
        local tResInfo = {}
        local sSql = string.format("Call DJH_TreasureDB.R_GetUserControl(%d, %d, %d, %d)",
            Read.nShopId, Read.nGameId, Read.nLevelId, Read.nUserId);

        local connection =dbSink.GetDbConnectForRead("DJH_TreasureDB")
        
        local cursor =  assert (dbSink.TreasureDB_connect:execute (sSql))
        local nIndex = 0
        repeat
            local row = cursor:fetch({}, "a")
            while row do
                function GetRes(row)
                    if row.ErrorCode ~= nil then
                        tResInfo.ErrorCode = row.ErrorCode
                        tResInfo.ErrorInfo = row.ErrorInfo
                    else
                        if tonumber(row.GroupID) == -1 then -- 全局监控
                            if tonumber(row.IsLock) >= 1 then
                                Read.nLock = tonumber(row.IsLock)
                                Read.nLuck = tonumber(row.Luck)
                                Read.dUnlockGames = tonumber(row.UnlockGames)
                                Read.dUnlockVal = tonumber(row.UnlockVal)
                            end
                        else
                            if tonumber(row.IsLock) >= 1 then -- 游戏或房间监控，优先房间监控
                                if Read.nRoomLock == 0 or row.RoomID ~= -1 then
                                    Read.nRoomLock = tonumber(row.IsLock)
                                    Read.nRoomLuck = tonumber(row.Luck)
                                end                              
                            end
                        end
                    end
                end
                xpcall(GetRes,tErr.tpLog, row)
                row = cursor:fetch(row, "a")
            end
            cursor:close()
            cursor = dbSink.TreasureDB_connect:nextres()
        until(cursor == 0)

        if tResInfo.ErrorCode ~= nil then 
            --tBase.Log(" R_GetUserControl失败, Code:%s, Info:%s", tResInfo.ErrorCode, tResInfo.ErrorInfo)
            mlogger:error(string.format("R_GetUserControl失败, Code:%s, Info:%s ",tResInfo.ErrorCode, tResInfo.ErrorInfo))
            tBase.Log(" R_GetUserControl失败 -------->sSql:   "..sSql)
            assert(false)
        else
            tBase.Log(" R_GetUserControl成功 -------->sSql:   "..sSql)
        end 
    end    

    xpcall(f1, tErr.tpLog)
    xpcall(f2, tErr.tpLog)
    xpcall(f3, tErr.tpLog)

    if Read.dRoomUserStat ~= nil and Read.dUserStat ~= nil then
        local s = tBase.GetSP().new(ProtoMgr.Sys1.CONTROL, ProtoMgr.Sub_Control.CONTROL_ROOMINFO)
        s:AddString(Read:SerializeToString()) 
        tBase.PostDatasByType(tName.control, 0, 0, s:GetData(), s:GetSize())
    end

end

return TreasureSink

