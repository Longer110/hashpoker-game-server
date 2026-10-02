package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../lua/base/socket/?.lua;./lua/base/socket/?.lua;" .. package.path
package.path = "../lua/DB_s/?.lua;./lua/DB_s/?.lua;" .. package.path
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path


local tBase     = require("base")           -- 基础功能接口
local tBase64 = require("BaseSink")    -- base 编码解码
local tErr   = require("ErrorSink")       -- 捕捉错误
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tName     = require("typename")
local tJson = require("cjson")
local mlogger        = require("logger")

RecordSink = {}



-- 写入牌局记录
function RecordSink.WriteUserPaiJuRecord(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local Read = ProtoMgr.PubProto_pb.Req_WritePaiJuRecord()
    Read:ParseFromString(ReadData:GetString())
    local sSql = Read.sSql
    tBase.Log("_WriteUserPaiJuRecord  写入牌局记录sSql: "..sSql)
    local tRoomInfo = {}

    local cursor =  assert (dbSink.RecordDB_connect:execute (sSql))
    local nIndex = 0
    repeat
        local row = cursor:fetch({}, "a")
        while row do
            function GetRes(row)
                tRoomInfo.Result =tonumber(row.Result)
                tRoomInfo.sPaiJuID =row.sPaiJuID
                tRoomInfo.sUserID =row.sFullHand
                tRoomInfo.nGameType = tonumber(row.nGameType)
            end
            xpcall(GetRes,tErr.tpLog, row)
            row = cursor:fetch(row, "a")
        end
        cursor:close()
        cursor = dbSink.RecordDB_connect:nextres()
    until(cursor == 0)
    tBase.Log("_WriteUserPaiJuRecord   结束写入牌局记录  Result: "..tRoomInfo.Result.."  sPaiJuID: "..tRoomInfo.sPaiJuID)
    return
end

-- 写入玩家输赢情况
function RecordSink.WriteUserWinLose(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local Read = ProtoMgr.PubProto_pb.Rep_Write_PaiJuWinLose()
    Read:ParseFromString(ReadData:GetString())
    local sSql = Read.sSql
    
    local tRoomInfo = {}
    local cursor =  assert (dbSink.RecordDB_connect:execute (sSql))
    local nIndex = 0
    repeat
        local row = cursor:fetch({}, "a")
        while row do
            function GetRes(row)
               if row.ErrorCode ~= nil then
                    local ErrorCode = row.ErrorCode
                    local ErrorInfo = row.ErrorInfo 
                    --tBase.Log("_WriteUserWinLose 失败,  sSql_%s  Code:%s, Info:%s",sSql,ErrorCode, ErrorInfo) 
                    mlogger:error(string.format(" _WriteUserWinLose 失败,  sSql_%s  Code:%s, Info:%s ",sSql,ErrorCode, ErrorInfo))
                    tRoomInfo.Result = -1
                else
                    tRoomInfo.Result =tonumber(row.Result)
                end
            end
            xpcall(GetRes,tErr.tpLog, row)
            row = cursor:fetch(row, "a")
        end
        cursor:close()
        cursor = dbSink.RecordDB_connect:nextres()
    until(cursor == 0)
    if tRoomInfo.Result ~= 0 then 
        tBase.Log("_WriteUserWinLose 写入失败   Result: %d sSql:  %s   ",tRoomInfo.Result,sSql)
    else
        tBase.Log("_WriteUserWinLose 写成功  Result: %d  sSql: %s  ",tRoomInfo.Result,sSql)
    end 
    return
end

-- 写入控制记录
function RecordSink.Control_Record(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local Read = ProtoManager.PubProto_1_pb.REQ_Control_Record()
    Read:ParseFromString(ReadData:GetString())
    local sSql = Read.sSql    
    tBase.Log("_Control_Record 写入控制记录sSql:   "..sSql)
    local tRoomInfo = {}
    local cursor =  assert (dbSink.RecordDB_connect:execute (sSql))
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
        cursor = dbSink.RecordDB_connect:nextres()
    until(cursor == 0)
end

function RecordSink.QuickSave(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local nUserId = ReadData:GetInt32()
    local sTableName = ReadData:GetString()

    local sBuff, nSize = ReadData:GetBuff()

    local s = dbSink.RecordDB_connect:escapeobj(sBuff, nSize)

    local sSql = "Call Quick_Save('"..sTableName.."',"..nUserId..",'"..s.."');"

    tBase.Log("quick save sql:%s size:%d", sSql, nSize)
    assert (dbSink.RecordDB_connect:execute (sSql))
end

function RecordSink.QuickLoad(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local nUserId = ReadData:GetInt32()
    local sTableName = ReadData:GetString()

    local sSql = "Call Quick_Load('"..sTableName.."',"..nUserId..");"
    local cursor = assert (dbSink.RecordDB_connect:execute (sSql))
    local tObj, nSize = cursor:fetch_obj()

    local nIsSuccess = 0

    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB1.SUB_REP_QUICKDBLOAD)
    s:AddInt32(nUserId)
    s:AddString(sTableName)
    if tObj then
        nIsSuccess = 1  
        s:AddByte(nIsSuccess)
        s:AddBuff(tObj, nSize)
    else
        nIsSuccess = 0
        s:AddByte(nIsSuccess)
    end
    tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())

    cursor:close()
    cursor = dbSink.RecordDB_connect:nextres() 
end

function RecordSink.JustExcute(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local sDbName = ReadData:GetString()

    local sSql = ""
    local nCnt = ReadData:GetInt32()
    for i=1, nCnt do
        local tmp = ReadData:GetString()
        sSql = sSql..tmp
    end

    tBase.Log("JustExcut sql %s", sSql)
    if sSql == "" then return end

    local t = {
        ["AccountsDB"] = dbSink.AccountsDB_connect,
        ["PlatformDB"] = dbSink.PlatformDB_connect,
        ["RecordDB"] = dbSink.RecordDB_connect,
        ["TreasureDB"] = dbSink.TreasureDB_connect,
        ["WebDb"] = dbSink.WebDB_connect
    }
    if not t[sDbName] then return end

    assert(t[sDbName]:execute (sSql)) 
end

--json数据访问mysql入口
function RecordSink.JsonExcute(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local nCallBackId = ReadData:GetInt32()
    local sJson = ReadData:GetString()

    local tInfo = tJson.decode(sJson)

    if tInfo.sMsgM and tInfo.sMsgS then
        tBase.Log("主消息M:%s, 次消息:%s", tInfo.sMsgM, tInfo.sMsgS)
    else
        tBase.Log("信息不全")
    end

    --返回值必须是个table
    local tRet
    tRet = RecordSink.MainFunc(tInfo)

    local s = tBase.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB1.SUB_REP_QUICKDBJSON)
    s:AddInt32(nCallBackId)
    s:AddString(tJson.encode(tRet or {}))
    Base.Log("db服返回的数据:%s", tJson.encode(tRet or {}))
    tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
end

--好友圈功能主函数
function RecordSink.MainFunc(tInfo)
    return RecordSink.NormalExcute(tInfo)
end

function RecordSink.NormalExcute(tInfo)
    local arr = {}
    local cursor = assert(dbSink.RecordDB_connect:execute(tInfo.sSql))  
    if type(cursor) ~= "number" then
        repeat
            row = cursor:fetch({},"a")
            xpcall(function(row) while row do
                local tRet = {}
                for k, v in pairs(row) do
                    tRet[k] = row[k]
                end

                table.insert(arr, tRet)
                row = cursor:fetch(row,"a")
            end end, tErr.tpLog, row)
            cursor:close()
            cursor = dbSink.RecordDB_connect:nextres()
        until(cursor == 0)
    end
    return arr 
end


-- 飞行棋写入控制记录
function RecordSink.PilotWriteControlRecord(sReturnKey, sData, nLen)

    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local Read = ProtoManager.PubProto_1_pb.REQ_Control_Record()
    Read:ParseFromString(ReadData:GetString())
    local sSql = Read.sSql
    
    tBase.Log("PilotWriteControlRecord -------->sSql:   "..sSql)
    assert (dbSink.RecordDB_connect:execute (sSql))

end

-- 聊天记录
function RecordSink.WriteChatRecord(sReturnKey, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local Read = ProtoManager.PubProto_1_pb.REQ_Control_Record()
    Read:ParseFromString(ReadData:GetString())
    local sSql = Read.sSql    
    tBase.Log("_WriteChatRecord  sSql:   "..sSql)
    assert(dbSink.RecordDB_connect:execute (sSql))
end

return RecordSink

