local tBase        = require("base")            -- 基础功能接口
local ProtoMgr     = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")
local tName        = require("typename")     -- 类弄定义接口
local cjson = require("cjson")

local DbServer_pb =ProtoMgr.DbServer_pb
local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse
local dbCmd =DbServer_pb.Db_Proto()

local Config ={}
local tSlaveToCenter={}

function Config.GetCenterServId(nSlaveServId)
    return tSlaveToCenter[nSlaveServId]
end

-- 获取多级中心服
function Config.GetSlaveServId(nCenterServId)
    local arrSlaveId = {}
    for nSlaveServId,nId in pairs(tSlaveToCenter) do
        if nCenterServId == nId then
            table.insert(arrSlaveId,nSlaveServId)
        end     
    end 
    tBase.Log("_GetSlaveServId   arrSlaveId_%s ",cjson.encode(arrSlaveId))
    for _,v in pairs(arrSlaveId) do
        for nSlaveServId,nId in pairs(tSlaveToCenter) do
            if nId == v then 
                return v 
            end 
        end  
    end 
    return 
end

-- 获取多级中心服
function Config.GetAllSlaveServId(nCenterServId)
    local arrSlaveId = {}
    for nSlaveServId,nId in pairs(tSlaveToCenter) do
        if nCenterServId == nId then
            table.insert(arrSlaveId,nSlaveServId)
        end     
    end   
    return arrSlaveId
end

function Config.IsMatch(nSlaveServId,nCenterServId)
    return tSlaveToCenter[nSlaveServId] ==nCenterServId
end

--db服返回
function Config.OnDbLiveCSRelationRsp(sReturnKey, Data, nLen)
    local strReq ="DbLiveCSRelationRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    local tSlaveToCenterTmp={}
    for _,item in ipairs(tData.arrItems) do
        tSlaveToCenterTmp[item.SlaveServerId]=item.CenterServerId 
    end
    tSlaveToCenter =tSlaveToCenterTmp

    -- tBase.LogT("OnDbLiveCSRelationRsp:",tSlaveToCenterTmp)
end

--db服请求
function Config.ReqDbLiveCSRelation()
    local strReq ="DbLiveCSRelationReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    if not Config.IsRegOnDbLiveCSRelationRs then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.DbLiveCSRelationRsp_CMD,Config.OnDbLiveCSRelationRsp)       --注册游戏列表返回处理
        Config.IsRegOnDbLiveCSRelationRs =true
    end
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end

return Config



