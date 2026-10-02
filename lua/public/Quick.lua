package.path = "../lua/public/DBSink/?.lua;./lua/public/DBSink/?.lua;" .. package.path

local tBase     = require("base")
local tName     = require("typename")
local tApi      = require("publicApi")
local tJson     = require("cjson")
local tProtoMgr = require("ProtoManager") -- 协议管理对象 

Quick = {}

Quick.tFuc = {}
Quick.tJsonFunc = {}
Quick.nJsonIdx = 1
Quick.tReceiveCall = nil

function Quick.ThrowPoint0(table)
    for k, v in pairs(table) do
        if type(v) == "table" then
            Quick.ThrowPoint0(v)
        end

        if type(v) == "number" then
            if math.floor(v) == v then
                table[k] = math.floor(table[k])
            end
        end
    end
end

function Quick.Reg()
    --只支持内存buff块的返回数据
    tBase.RegFunc(tProtoMgr.Sys.DB, tProtoMgr.Sub_DB1.SUB_REP_QUICKDBLOAD, Quick.Response)
    --支持json格式返回数据，但目前只做小于8k的数据
    tBase.RegFunc(tProtoMgr.Sys.DB, tProtoMgr.Sub_DB1.SUB_REP_QUICKDBJSON, Quick.JsonResponse)

    --json消息传输回调
    tBase.RegFunc(tProtoMgr.GatewayPro.GATEWAY, tProtoMgr.Sub_GateWay.SUB_REQ_QUICKSEND, Quick.Receive)
end

function Quick.RegMyReceiveCallBack(callbackfunc)
    Quick.tReceiveCall = callbackfunc
end

--buff数据回调
function Quick.Response(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local nUserId = ReadData:GetInt32()
    local sTableName = ReadData:GetString()
    local nIsSuccess = ReadData:GetByte()

    local sBuff, nSize = nil, 0
    if nIsSuccess == 1 then
        sBuff, nSize = ReadData:GetBuff()   
    end

    if Quick.tFuc[sTableName] ~= nil then
        Quick.tFuc[sTableName](nUserId, sBuff, nSize)
    end
end

--json格式数据回调
function Quick.JsonResponse(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()
    local nCallBackId = ReadData:GetInt32()
    local sJson = ReadData:GetString()

    local args = Quick.tJsonFunc[nCallBackId].args

    local tD = tJson.decode(sJson)
    Quick.ThrowPoint0(tD)
    table.insert(args, tD)
    Quick.tJsonFunc[nCallBackId].ctor(table.unpack(args))
end

--接收内网json消息传输
function Quick.Receive(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local sJson = ReadData:GetString()

    -- tBase.Log("Quick 收到一个消息返回")
    if Quick.tReceiveCall then
        local tD = tJson.decode(sJson)
        Quick.ThrowPoint0(tD)
        Quick.tReceiveCall(sClientID, tD)
    end
end

function Quick.QuickSave(nUserId, sTableName, sData, nLen)
    local s = tBase.GetSP().new(tProtoMgr.Sys.DB, tProtoMgr.Sub_DB1.SUB_REQ_QUICKDBSAVE)
    s:AddInt32(nUserId)
    s:AddString(sTableName)
    s:AddBuff(sData, nLen)

    tBase.Log("QuickSave: nuserId:%d", nUserId)
    tBase.PostDatasByType(tName.db, 0, nUserId, s:GetData(), s:GetSize())
end

function Quick.QuickLoad(nUserId, sTableName, callbackfunc)
    Quick.tFuc[sTableName] = callbackfunc
    local s = tBase.GetSP().new(tProtoMgr.Sys.DB, tProtoMgr.Sub_DB1.SUB_REQ_QUICKDBLOAD)
    s:AddInt32(nUserId)
    s:AddString(sTableName)
    tBase.PostDatasByType(tName.db, 0, nUserId, s:GetData(), s:GetSize())
end

--仅仅执行一条不带返回值的sql语句
function Quick.JustExcute(sDbName, sSql)
    if string.len(sSql) >= 7000 then
        tBase.Log(" Error_Info==101   sql:%s", sSql) 
        return
    end

    local s = tBase.GetSP().new(tProtoMgr.Sys.DB, tProtoMgr.SUB_DB1.SUB_REQ_JUSTEXCUTE)
    s:AddString(sDbName)

    local arr = tApi.CutString(sSql, 1000)
    s:AddInt32(#arr)
    for i = 1, #arr do 
        s:AddString(arr[i])
    end 
    tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
end

--执行一个可以带返回的sql语句
function Quick.ExcuteSql(tInfo, callbackfunc, ...)
    if not tInfo.sMsgM or not tInfo.sMsgS or not tInfo.sSql or not callbackfunc then
        tBase.Log("缺少必要参数,不予执行")
        return
    end

    if Quick.nJsonIdx > 0xFFFFFFFF then
        Quick.nJsonIdx = 1
    else
        Quick.nJsonIdx = Quick.nJsonIdx + 1
    end
    Quick.tJsonFunc[Quick.nJsonIdx] = {ctor=callbackfunc, args={...}}
    local s = tBase.GetSP().new(tProtoMgr.Sys.DB, tProtoMgr.Sub_DB1.SUB_REQ_QUICKDBJSON)
    s:AddInt32(Quick.nJsonIdx)
    s:AddString(tJson.encode(tInfo))
    tBase.PostDatasByType(tName.db, 0, 0, s:GetData(), s:GetSize())
end

--发一条消息到特定内网服务器
function Quick.SendMsgToTargetServer(sTargetKey, tInfo)
    local tVal = tApi.Split(sTargetKey, ":")
    sTargetKey = tVal[1]
    
    local s = tBase.GetSP().new(tProtoMgr.GatewayPro.GATEWAY, tProtoMgr.Sub_GateWay.SUB_REQ_QUICKSEND)
    s:AddString(tJson.encode(tInfo))
    tBase.PostToServer(sTargetKey, 2, s:GetData(), s:GetSize())
end

return Quick
