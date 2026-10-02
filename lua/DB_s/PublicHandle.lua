package.path = require("./lua/DB_s/Head").path
local tBase = require("base")           -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local cjson   = require("cjson")


local tParserAux = require("ParserAux")

local dbCmd1 =ProtoMgr.DbServer1_pb.Db_Proto1()



local PublicHandle ={}

local function GetHandleFunction(moduleName,sFuncName)
    local func =function(...)
        moduleName[sFuncName](...)
    end
    return func
end

-- 小游戏  协议 
function PublicHandle.PublicHandleProto()

    tBase.RegFunc(dbCmd1.Main_CMD, dbCmd1.DbPublicAPIReq_CMD, GetHandleFunction(PublicHandle,"OnDbPublicAPIReq"))



end  


--DB 公共操作
function PublicHandle.OnDbPublicAPIReq(sReturnKey, sData, nLen) 
    local ReadData = tBase.GetRP().new(sData, nLen)
    local Read = ProtoMgr.DbServer1_pb.DbPublicAPIReq()
    Read:ParseFromString(ReadData:GetString()) 
    local sDatabaseName = Read.sDatabaseName
    local sSql = Read.sSql
    local connection =dbSink.GetDbConnectForRead(sDatabaseName)
    SqlExecut(sSql,connection)
    tBase.Log("_OnDbPublicAPIReq   %s  sSql: %s ",sDatabaseName,sSql)


end 


return PublicHandle