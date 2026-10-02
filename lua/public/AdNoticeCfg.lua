package.path = "../lua/public/?.lua;./lua/public/?.lua;" .."../lua/Gateway/?.lua;./lua/Gateway/?.lua;" .. package.path
local tBase = require("base")
local tName = require("typename")
local AdNote = require("AdNoticeNote") 
local ProtoMgr = require("ProtoManager") 
local tParserAux = require("ParserAux")
local tRedisdefine = require("redisdefine")
local tRedis = require("redis")
local tRedis = require("redis")
local cjson = require("cjson")

local DbServer_pb =ProtoMgr.DbServer_pb
local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse
local Backstage_pb =ProtoMgr.Backstage_pb
local BackstageCmd=Backstage_pb.Backstage_Proto()
local dbCmd =DbServer_pb.Db_Proto()  
local AdNoticeCfg = { }
AdNoticeCfg.tAdNoticeNoteList = nil

--后台请求:[公告列表]
function AdNoticeCfg.WebReqAdNoticNoteList()
    AdNoticeCfg.ReqDbAdNoticNoteList()
    tBase.Log("Web_Req_Notice_Update_Ad")
end

--db服请求:[公告列表]
function AdNoticeCfg.ReqDbAdNoticNoteList() 
    local strReq ="DbAdCfgListReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err_happen,AdCfg_DbProtoEncode_%s fail",strReq)
        return
    end
    if not AdNoticeCfg.IsRegDbAdCfgListRsp then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.DbAdCfgListRsp_CMD,AdNoticeCfg.OnDbAdCfgListRsp) --注册公告列表
        AdNoticeCfg.IsRegDbAdCfgListRsp = true
    end
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
	return 
end 
--db服返回:[公告列表]
function AdNoticeCfg.OnDbAdCfgListRsp(sReturnKey, Data, nLen)
    local ReadData = tBase.GetRP().new(Data, nLen)
    local Read = ProtoMgr.DbServer_pb.DbAdCfgListRsp() 
    Read:ParseFromString(ReadData:GetString())
    local arrAdItem = {}
    for k,item in ipairs(Read.arrAdItem) do
        --Scope:公告范围：1 大厅 2、游戏房间, 3、大厅+游戏服, 4、停服公告 Details:消息
        --Channel:渠道 StartTime:公告开始时间 EndTime：公告结束时间 Frequency:是否重复
        local AdItem ={ID = item.ID, Scope = item.Scope, Channel = item.Channel, StartTime = item.StartTime, EndTime = item.EndTime, Frequency = item.Frequency, Details = item.Details}
        tBase.Log("AddNewAdCfg_Item.ID:"..item.ID)
        arrAdItem[#arrAdItem+1] = AdItem
    end
    AdNoticeCfg.tAdNoticeNoteList=arrAdItem    
    AdNote.BuildAdNoticeTime() 
	tBase.Log("公告： %s",cjson.encode(AdNoticeCfg.tAdNoticeNoteList) )
end

function AdNoticeCfg.delValByID(tTable,ID)
    for k,v in pairs(tTable) do 
        if AdNoticeCfg.FindKeyByID(tTable, ID) then
            table.remove(tTable,k)
        end
    end
end

function AdNoticeCfg.FindKeyByID(tTable, ID)
    if (type(tTable) ~= "table" or tTable == nil) then
        return nil
    end
    for key ,val in pairs(tTable) do
        if val.ID ~= nil and val.ID == ID then
            return key         
        end
    end
    return nil
end

function AdNoticeCfg.GetAdNoticeInfo(nScope)
    for k,v in pairs(AdNoticeCfg.tAdNoticeNoteList) do
        if math.floor(v.Scope) == math.floor(nScope) then
            return v
        end
    end
    return nil
end

return AdNoticeCfg