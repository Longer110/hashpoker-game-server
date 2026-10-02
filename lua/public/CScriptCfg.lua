package.path = "../lua/public/?.lua;./lua/public/?.lua;" .."../lua/Gateway/?.lua;./lua/Gateway/?.lua;" .. package.path
local tBase = require("base")
local tName = require("typename") 
local ProtoMgr = require("ProtoManager") 
local tParserAux = require("ParserAux")
local tRedisdefine = require("redisdefine")
local tRedis = require("redis")
local cjson = require("cjson")

local DbServer_pb =ProtoMgr.DbServer_pb
local DbProtoParse =tParserAux.DbProtoParse
local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoEncode1 =tParserAux.DbProtoEncode1
local DbProtoParse1 =tParserAux.DbProtoParse1
local DbServer1_pb =ProtoMgr.DbServer1_pb
local Backstage_pb =ProtoMgr.Backstage_pb
local BackstageCmd=Backstage_pb.Backstage_Proto()
local dbCmd =DbServer_pb.Db_Proto()
local dbCmd1 =DbServer1_pb.Db_Proto1()

CScriptCfg = { } 
CScriptCfg.arrAllCfg = {}

function SqlExecut(sSql,dbConnect)
    local arrRows ={} 
    local cursor,msg =assert(dbConnect:execute (sSql))
    if cursor==nil then
        return
    end
    repeat
        row = cursor:fetch({},"a")
        while row do
          table.insert(arrRows,tBase.DeepCopy(row))
           row = cursor:fetch(row,"a")
        end
        cursor:close()
        cursor = dbConnect:nextres()
    until( cursor == 0 ) 
    return arrRows
end

--新建對象
CScriptCfg.New = function()
    return {}
end

--销毁池子
CScriptCfg.FreePool = function()
	return nil
end

--重置ID池
CScriptCfg.ReleasePool = function(nCfgId)
	CScriptCfg.arrAllCfg[nCfgId] = nil
end

--构建全池
CScriptCfg.MakeScriptPool = function(tCScriptCfg)
	CScriptCfg.arrAllCfg = CScriptCfg.FreePool()
	CScriptCfg.arrAllCfg = tCScriptCfg 
    tBase.m_MyRedisData[1].redis:del("sBurKey_")
    local t = {}
    local b = tBase.m_MyRedisData[1].redis:hmset('sBurKey_', tCScriptCfg)
    if not b then tBase.Log("Bur Cfg Load is fail") end
    for k=1, #CScriptCfg.arrAllCfg do 
        table.insert(t,t.val)
        -- tBase.LogT("配置=",k,CScriptCfg.arrAllCfg[k])
    end
end

--获取索引
CScriptCfg.GetIndexScript = function(nCfgId)
	local tConfig = CScriptCfg.arrAllCfg
end

--后台请求:[lua脚本列表]
function CScriptCfg.WebReqAdNoticNoteList()
    CScriptCfg.ReqDbAdNoticNoteList()
    tBase.Log("Web_Req_Notice_Update_Ad")
end

--db服请求:[lua脚本列表]
function CScriptCfg.ReqDbScriptList() 
    local strReq ="DbScriptCfgListReq"
    local tPacket,nMainCmd,nSubCmd = DbProtoEncode1(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err_happen,LuaScript_DbProtoReqEncode_%s fail",strReq)
        return
    end
    if not CScriptCfg.IsRegDbScriptCfgListRsp then
        tBase.RegFunc(dbCmd1.Main_CMD,dbCmd1.DbScriptCfgListRsp_CMD,CScriptCfg.OnDbScriptCfgListRsp)
        CScriptCfg.IsRegDbScriptCfgListRsp = true
    end
    tBase.PostDatasByType(tName.burdb, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--db服返回:[lua脚本列表]
function CScriptCfg.OnDbScriptCfgListRsp(sReturnKey, Data, nLen)
    local ReadData = tBase.GetRP().new(Data, nLen)
    local Read = ProtoMgr.DbServer1_pb.DbScriptCfgListRsp()
    Read:ParseFromString(ReadData:GetString())
    local tItem = CScriptCfg.New()
    for k,item in ipairs(Read.arrScriptItem) do
        local ScriptItem ={ID=item.ID, ScriptName=item.ScriptName, UIPath=item.UIPath, Event=item.Event, Script=item.Script, UUID=item.UUID  }
        tBase.Log("AddNewScriptCfg_Item.ID:"..item.ID)
        tItem[#tItem+1] = ScriptItem
    end
    CScriptCfg.MakeScriptPool(tItem)
end

--执行脚本
function CScriptCfg.ExeScriptEvent(tData,tBcfg)
    assert(tData~=nil,"The front-end data is empty")
    local tPacket, m ,s  = DbProtoEncode1("DbBurWriteNotify",{tBuildUserData=tData})
    tBase.PostDatasByType(tName.burdb, 0, 0, tPacket:GetData(), tPacket:GetSize())
end
 
--执行脚本
function CScriptCfg.DbPublicHandleEvent(sDatabaseName,sSql) 
    local tPacket, m ,s  = DbProtoEncode1("DbPublicAPIReq",{sDatabaseName=sDatabaseName,sSql=sSql})
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end
 


return CScriptCfg