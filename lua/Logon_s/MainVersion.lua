
local tBase	= require("base") -- 基础功能接口
local tName	= require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")

local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse

local DbServer_pb =ProtoMgr.DbServer_pb
local dbCmd =DbServer_pb.Db_Proto()

local tGroupIdToVersion ={}

local MainVersionInfo ={}

--向db服请求版本信息
function MainVersionInfo.RequestMainVersion()	
	local strReq ="MainVersionReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
	end
	if not MainVersionInfo.IsRegMainVersionRsp then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.MainVersionRsp_CMD,MainVersionInfo.OnMainVersionRsp)       --注册游戏列表返回处理
        MainVersionInfo.IsRegMainVersionRsp =true
	end
	
    tBase.Log("begin to RequestMainVersion")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end

function MainVersionInfo.OnMainVersionRsp(sReturnKey, Data, nLen)
    local strReq ="MainVersionRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
	end
	local tTem={}
	for _,item in ipairs(tData.arrItems) do
		local nGroupId =tonumber(item.nGroupId)
		local sVersion =item.sVersion
		local sPlatform =item.sPlatform
		local sKey =string.format("%d_%s",nGroupId,sPlatform)
		tTem[sKey]=sVersion
	end
	tGroupIdToVersion =tTem
	tBase.LogT("tGroupIdToVersion:",tGroupIdToVersion)
end

function MainVersionInfo.GetClientMainVersion(nGroupId,sPlatform)
	local sPlatform=sPlatform or ""
	local sKey =string.format("%d_%s",nGroupId,sPlatform)
	local sDefault =string.format("%d_%s",0,sPlatform)
	local sVersion =tGroupIdToVersion[sKey] or tGroupIdToVersion[sDefault] or ""
	return sVersion
end

return MainVersionInfo

