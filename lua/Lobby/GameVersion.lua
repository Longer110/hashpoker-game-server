
local tBase	= require("base") -- 基础功能接口
local tName	= require("typename") -- 类弄定义接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tParserAux = require("ParserAux")

local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse

local DbServer_pb =ProtoMgr.DbServer_pb
local dbCmd =DbServer_pb.Db_Proto()

local tKeyToInfo ={}

local GameVersionInfo ={}

--向db服请求版本信息
function GameVersionInfo.RequestGameVersion()	
	local strReq ="GameVersionReq"
    local tPacket,nMainCmd,nSubCmd =DbProtoEncode(strReq,{nNoUse=0})
    if not tPacket then
        tBase.Log("Err happen,DbProtoEncode_%s fail",strReq)
        return
	end
	if not GameVersionInfo.IsRegGameVersionRsp then
        tBase.RegFunc(dbCmd.Main_CMD,dbCmd.GameVersionRsp_CMD,GameVersionInfo.OnGameVersionRsp)       --注册游戏列表返回处理
        GameVersionInfo.IsRegGameVersionRsp =true
	end
    tBase.Log("begin to RequestGameVersion")
    tBase.PostDatasByType(tName.db, 0, 0, tPacket:GetData(), tPacket:GetSize())    
	return 
end


function GameVersionInfo.OnGameVersionRsp(sReturnKey, Data, nLen)
    local strReq ="GameVersionRsp"
    local tData =DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen,DbProtoParse_%s fail",strReq)
        return
	end
	
	local tem ={}
	local GUPTem = {}
	for _,item in ipairs(tData.arrItems) do
		local nGroupId=tonumber( item.nGroupId)
		local sGameCode =item.sGameCode
		local sVersion =item.sVersion
		local sMD5FilePath =item.sMD5FilePath
		local sZipFilePath =item.sZipFilePath
		local sPlatform =item.sPlatform
		local sKey =string.format("%d_%s_%s",nGroupId,sGameCode,sPlatform)
		tKeyToInfo[sKey] ={sVersion=sVersion,sMD5FilePath=sMD5FilePath,sZipFilePath=sZipFilePath,sPlatform=sPlatform}
	end
end

function GameVersionInfo.GetGameVersionInfo(nGroupId,sGameCode,sPlatform)
	local sKey =string.format("%d_%s_%s",nGroupId,sGameCode,sPlatform or "")
	local sDefaultKey =string.format("%d_%s_%s",0,sGameCode,sPlatform or "")
	return tKeyToInfo[sKey] or tKeyToInfo[sDefaultKey] or {}
end

return GameVersionInfo

