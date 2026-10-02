package.path = require("./lua/Gateway/Head").path

local tBase = require("base") -- 基础功能接口
local tName = require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")

local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse


local UserIpList ={}
local tMaintainerIp={} --ip be key

function UserIpList.LoaderIpInfo()
    local strReq ="MaintainerIpReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    tBase.Log("begin to MaintainerIpReq")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
end
function UserIpList.onTimerLoaderIpInfo(nTimerId)
    UserIpList.LoaderIpInfo()
end

--db服ip信息返回处理
function UserIpList.MaintainerIpRsp(ClientID, Data, Len)
	tBase.Log("MaintainerIpRsp")
	local strReq ="MaintainerIpRsp"
    local tData =DbProtoParse(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
    tMaintainerIp ={}
    for _,item in ipairs(tData.arrItems) do
        tMaintainerIp[item.sIp]=true
        tBase.Log(item.sIp..':'..item.nPort)
       --item.sIp 
       --item.nPort
	end
end

function UserIpList.IsMaintainerIp(sIp)
    return (tMaintainerIp[sIp] or false)
end

return UserIpList

