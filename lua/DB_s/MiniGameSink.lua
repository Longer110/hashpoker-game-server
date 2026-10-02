-- 小游戏
package.path = require("./lua/DB_s/Head").path
local tBase = require("base")           -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local cjson   = require("cjson")


local tParserAux = require("ParserAux")

local DbMiniGameParse =tParserAux.DbMiniGameParse
local DbMiniGameSendToServer =tParserAux.DbMiniGameSendToServer


local MiniGameSink ={}

local DbMiniGame_pb =ProtoMgr.DbMiniGame_pb
local DbMiniGameCmd =DbMiniGame_pb.DbMiniGame_Proto()


local function GetHandleFunction(moduleName,sFuncName)
    local func =function(...)
        moduleName[sFuncName](...)
    end
    return func
end

-- 小游戏  协议 
function MiniGameSink.MiniGameProto()
    tBase.RegFunc(DbMiniGameCmd.Main_CMD, DbMiniGameCmd.OldHandHandleReq_CMD, GetHandleFunction(MiniGameSink,"OnOldHandHandleReq")) --俱乐部数据 请求
    tBase.RegFunc(DbMiniGameCmd.Main_CMD, DbMiniGameCmd.DiShuHandleReq_CMD, GetHandleFunction(MiniGameSink,"OnDiShuHandleReq")) --俱乐部数据 请求
    tBase.RegFunc(DbMiniGameCmd.Main_CMD, DbMiniGameCmd.TanQiuHandleReq_CMD, GetHandleFunction(MiniGameSink,"OnTanQiuHandleReq")) --俱乐部数据 请求
    tBase.RegFunc(DbMiniGameCmd.Main_CMD, DbMiniGameCmd.TanXianHandleReq_CMD, GetHandleFunction(MiniGameSink,"OnTanXianHandleReq")) --俱乐部数据 请求


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

-- 老司机
function MiniGameSink.OnOldHandHandleReq(sReturnKey,Data,nLen)
    local strReq ="OldHandHandleReq"
    local tData =DbMiniGameParse(Data, nLen,strReq)
    if not tData then
        assert(false,"_OldHandHandleReq Err happen ,Parse error strReq:"..strReq)
        return
    end
    tBase.Log("_OnOldHandHandleReq   sSubPro_%s sJson: %s sSql_%s ",tData.sSubPro,tData.sJson or "",tData.sSql)
    local t = {}
    if tData.sJson and #tData.sJson > 0 then 
        t = cjson.decode(tData.sJson)
    end 
    local arrRows =RecordDB_SqlExecute(tData.sSql) 
    if arrRows and arrRows[1] and arrRows[1].ErrorCode and arrRows[1].ErrorInfo then
        tBase.Log("_OnOldHandHandleReq ErrorMsg ErrorCode:%s ErrorInfo:%s",arrRows[1].ErrCode,arrRows[1].ErrorInfo or "")
        assert(not arrRows[1].ErrorInfo,"  ErrorInfo: "..arrRows[1].ErrorInfo)
        return 
    end 

    local OldHandHandleRsp ={}
    OldHandHandleRsp.sSubPro = tData.sSubPro
    if tData.sSubPro == "OldHandLevelGateReq" or tData.sSubPro == "OldHandLogonReq" then 
        t.row = arrRows[1]  
    elseif tData.sSubPro == "OldHandLevelRecordReq" then   
        t.row = arrRows              
    elseif tData.sSubPro == "LoadCountTopList" or tData.sSubPro == "LoadTimeTopList"  or tData.sSubPro == "LoadWordTop"  then  
        if #arrRows <= 50 then 
            t.row = arrRows
        else
            local redis = tBase.m_MyRedisData[1].redis
            local sKey = string.format("%s_%d",tData.sSubPro,os.time())
            redis:set(sKey,cjson.encode(arrRows))
            redis:expire(sKey,5)
            t.sKey = sKey
        end  
    end     
    local sDate = cjson.encode(t)
    local sKey = "OldHandHandleRsp_"..os.time().." "..math.random(1,99999)
	local tRedis =tBase.m_MyRedisData[1].redis     
	tRedis:set(sKey,sDate)
	tRedis:expire(sKey,3)   

    OldHandHandleRsp.sJson = sKey
    DbMiniGameSendToServer(sReturnKey,"OldHandHandleRsp",OldHandHandleRsp)
    tBase.Log("_OnOldHandHandleReq  [%s] Sql: %s ",tData.sSubPro,tData.sSql)
end

--  弹球 
function MiniGameSink.OnTanQiuHandleReq(sReturnKey,Data,nLen)
    local strReq ="TanQiuHandleReq"
    local tData =DbMiniGameParse(Data, nLen,strReq)
    if not tData then
        assert(false,"_OnTanQiuHandleReq Err happen ,Parse error strReq:"..strReq)
        return
    end
    -- tBase.Log("_OnTanQiuHandleReq   sSubPro_%s sJson: %s sSql_%s ",tData.sSubPro,tData.sJson or "",tData.sSql)
    local t = {}
    if tData.sJson and #tData.sJson > 0 then 
        t = cjson.decode(tData.sJson)
    end 
    local arrRows =RecordDB_SqlExecute(tData.sSql) 
    if arrRows and arrRows[1] and arrRows[1].ErrorCode and arrRows[1].ErrorInfo then
        tBase.Log("_OnTanQiuHandleReq ErrorMsg ErrorCode:%s ErrorInfo:%s",arrRows[1].ErrCode,arrRows[1].ErrorInfo or "")
        assert(not arrRows[1].ErrorInfo,"  ErrorInfo: "..arrRows[1].ErrorInfo)
        return 
    end 
    local TanQiuHandleRsp ={}
    TanQiuHandleRsp.sSubPro = tData.sSubPro
    if tData.sSubPro == "TanQiuScoreReq" or tData.sSubPro == "TanQiuLogonReq" then 
        t.row = arrRows[1]   
    elseif tData.sSubPro == "LoadWordTop"  then  
        if #arrRows <= 50 then 
            t.row = arrRows
        else
            local redis = tBase.m_MyRedisData[1].redis
            local sKey = string.format("%s_%d",tData.sSubPro,os.time())
            redis:set(sKey,cjson.encode(arrRows))
            redis:expire(sKey,5)
            t.sKey = sKey
        end  
    end     
     
    local sDate = cjson.encode(t)
    local sKey = "TanQiuHandleRsp_"..os.time().." "..math.random(1,99999)
	local tRedis =tBase.m_MyRedisData[1].redis     
	tRedis:set(sKey,sDate)
	tRedis:expire(sKey,3)   
    TanQiuHandleRsp.sJson = sKey
    DbMiniGameSendToServer(sReturnKey,"TanQiuHandleRsp",TanQiuHandleRsp)
    tBase.Log("_OnTanQiuHandleReq  [%s] Sql: %s ",tData.sSubPro,tData.sSql)
end 

--  地鼠
function MiniGameSink.OnDiShuHandleReq(sReturnKey,Data,nLen)
    local strReq ="DiShuHandleReq"
    local tData =DbMiniGameParse(Data, nLen,strReq)
    if not tData then
        assert(false,"_DiShuHandleReq Err happen ,Parse error strReq:"..strReq)
        return
    end
    tBase.Log("_OnDiShuHandleReq   sSubPro_%s sJson: %s sSql_%s ",tData.sSubPro,tData.sJson or "",tData.sSql)
    local t = {}
    if tData.sJson and #tData.sJson > 0 then 
        t = cjson.decode(tData.sJson)
    end 

    local arrRows =RecordDB_SqlExecute(tData.sSql) 
    if arrRows and arrRows[1] and arrRows[1].ErrorCode and arrRows[1].ErrorInfo then
        tBase.Log("_OnDiShuHandleReq ErrorMsg ErrorCode:%s ErrorInfo:%s",arrRows[1].ErrCode,arrRows[1].ErrorInfo or "")
        assert(not arrRows[1].ErrorInfo,"  ErrorInfo: "..arrRows[1].ErrorInfo)
        return 
    end 

    local DiShuHandleRsp ={}
    DiShuHandleRsp.sSubPro = tData.sSubPro
    if tData.sSubPro == "DiShuLogonReq" then 
        -- local arrRows =RecordDB_SqlExecute(tData.sSql) 
        t.row = arrRows[1] 
    elseif tData.sSubPro == "DiShuLevelGateReq" then 
        -- local arrRows =RecordDB_SqlExecute(tData.sSql) 
        t.row = arrRows[1] 
    elseif tData.sSubPro == "LoadWordTop" then
        -- local arrRows =RecordDB_SqlExecute(tData.sSql) 
        if #arrRows <= 50 then 
            t.row = arrRows
        else
            local redis = tBase.m_MyRedisData[1].redis
            local sKey = string.format("%s_%d",tData.sSubPro,os.time())
            redis:set(sKey,cjson.encode(arrRows))
            redis:expire(sKey,5)
            t.sKey = sKey
        end  
    end     
    local sDate = cjson.encode(t)
    local sKey = "DiShuHandleRsp_"..os.time().." "..math.random(1,99999)
	local tRedis =tBase.m_MyRedisData[1].redis     
	tRedis:set(sKey,sDate)
	tRedis:expire(sKey,3)   
    DiShuHandleRsp.sJson = sKey    
    DbMiniGameSendToServer(sReturnKey,"DiShuHandleRsp",DiShuHandleRsp)
    tBase.Log("_OnOldHandHandleReq  [%s] Sql: %s ",tData.sSubPro,tData.sSql)
end

--  弹线
function MiniGameSink.OnTanXianHandleReq(sReturnKey,Data,nLen)
    local strReq ="TanXianHandleReq"
    local tData =DbMiniGameParse(Data, nLen,strReq)
    if not tData then
        assert(false,"_TanXianHandleReq Err happen ,Parse error strReq:"..strReq)
        return
    end
    tBase.Log("_OnTanXianHandleReq   sSubPro_%s sJson: %s sSql_%s ",tData.sSubPro,tData.sJson or "",tData.sSql)
    local t = {}
    if tData.sJson and #tData.sJson > 0 then 
        t = cjson.decode(tData.sJson)
    end 

    local arrRows =RecordDB_SqlExecute(tData.sSql) 
    if arrRows and arrRows[1] and arrRows[1].ErrorCode and arrRows[1].ErrorInfo then
        tBase.Log("_OnTanXianHandleReq ErrorMsg ErrorCode:%s ErrorInfo:%s",arrRows[1].ErrCode,arrRows[1].ErrorInfo or "")
        assert(not arrRows[1].ErrorInfo,"  ErrorInfo: "..arrRows[1].ErrorInfo)
        return 
    end 

    local TanXianHandleRsp ={}
    TanXianHandleRsp.sSubPro = tData.sSubPro
    if tData.sSubPro == "TanXianLogonReq" then 
        -- local arrRows =RecordDB_SqlExecute(tData.sSql) 
        t.row = arrRows[1] 
    elseif tData.sSubPro == "TanXianLevelGateReq" then 
        -- local arrRows =RecordDB_SqlExecute(tData.sSql) 
        t.row = arrRows[1] 
    elseif tData.sSubPro == "LoadWordTop" then
        -- local arrRows =RecordDB_SqlExecute(tData.sSql) 
        if #arrRows <= 50 then 
            t.row = arrRows
        else
            local redis = tBase.m_MyRedisData[1].redis
            local sKey = string.format("%s_%d",tData.sSubPro,os.time())
            redis:set(sKey,cjson.encode(arrRows))
            redis:expire(sKey,5)
            t.sKey = sKey
        end  
    end     
    local sDate = cjson.encode(t)
    local sKey = "TanXianHandleRsp_"..os.time().." "..math.random(1,99999)
	local tRedis =tBase.m_MyRedisData[1].redis     
	tRedis:set(sKey,sDate)
	tRedis:expire(sKey,3)   
    TanXianHandleRsp.sJson = sKey
    DbMiniGameSendToServer(sReturnKey,"TanXianHandleRsp",TanXianHandleRsp)
    tBase.Log("_OnOldHandHandleReq  [%s] Sql: %s ",tData.sSubPro,tData.sSql)
end


 
return MiniGameSink
