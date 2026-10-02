package.path = require("./lua/Gateway/Head").path
 
local tBase	= require("base") -- 基础功能接口
local tName	= require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")

local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse

local tVersionInfo ={}

local VersionInfo ={}						--sPlatform:sChannel be key

--向db服请求版本信息
function VersionInfo.RequestVersion()	
	local strReq ="VersionReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
    end
    tBase.Log("begin to RequestVersion")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end

function VersionInfo.onTimerRequestVersion(nTimerId)
	VersionInfo.RequestVersion()
end

--db服版本信息返回处理
function VersionInfo.OnDbVersionRsp(ClientID, Data, Len)
	tBase.Log("OnVersionRsp")
	local strReq ="VersionRsp"
    local tData =DbProtoParse(Data, Len,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
    end
	for _,item in ipairs(tData.arrItems) do
		local sKey =item.sPlatform..':'..item.sChannel
		local tVal ={}
		tVal.sVersion=item.sVersion
		tVal.sDownloadurl=item.sDownloadurl
		tVal.sAppurl=item.sAppurl
		tVal.sConfigUrl =item.sConfigUrl
		tVal.sConfigVersion=item.sConfigVersion
		tVersionInfo[sKey]=tVal
	end
end

function VersionInfo.GetVersionInfo(sPlatform,sChannel)
	local sKey =sPlatform..':'..sChannel
	return tVersionInfo[sKey]
end

return VersionInfo

