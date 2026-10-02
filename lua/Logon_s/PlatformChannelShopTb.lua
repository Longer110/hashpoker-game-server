
local tBase	= require("base") -- 基础功能接口
local tName	= require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")

local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse

local Platform_Channel_ToShopId={}

local obj={}
--向db服请求负载均衡表
function obj.ReqPlatformChannelShopTb()	
	local strReq ="PlatformChannelShopReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    tBase.Log("begin to ReqPlatformChannelShopTb")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end


function obj.onTimerReqPlatformChannelShopTb(nTimerId)
	obj.ReqPlatformChannelShopTb()
end

--db服负载均衡表返回处理
function obj.OnPlatformChannelShopRsp(ClientID, Data, Len)
	tBase.Log("OnPlatformChannelShopRsp")
	local strReq ="PlatformChannelShopRsp"
    local tData =DbProtoParse(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
	end
	local tkeyToShopId={}
	for _,item in ipairs(tData.arrItems) do
		local tmpItem ={}
		tmpItem.sPlatform= item.sPlatform
		tmpItem.sChannel= item.sChannel		
		tmpItem.nShopId= item.nShopId	
		local sKey =string.format("%s_%s",tmpItem.sPlatform,tmpItem.sChannel)
		tkeyToShopId[sKey]=tmpItem.nShopId
	end
	Platform_Channel_ToShopId =tkeyToShopId
	tBase.LogT(Platform_Channel_ToShopId)
end

function obj.GetShopId(sPlatform,sChannel,nShopId)
	if nShopId and nShopId>0 then
		return nShopId
	end
	return 1
	--[[
	local sKey =string.format("%s_%s",sPlatform,sChannel)
	local nShopId =Platform_Channel_ToShopId[sKey]
	if nShopId then
		return nShopId
	end
	nShopId =Platform_Channel_ToShopId["default_default"] or -1
	return nShopId
	]]
end


return obj

