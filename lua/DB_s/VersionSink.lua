package.path = require("./lua/DB_s/Head").path

local tBase	= require("base") -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local mlogger = require("logger") -- 日志对象 
local tErr = require("ErrorSink") -- 捕捉错误
local cjson = require("cjson") -- json 

VersionSink = {}

function VersionSink.SendVersionSQL(sReturnKey, sData, nLen)
	
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()
	local Read = ProtoMgr.Gateway_pb.RUQ_VersionCfg() 
	Read:ParseFromString(ReadData:GetString())
	local sSql = ""
    sSql = Read.sSql
    tBase.Log("加载版本信息,sSql = %s",sSql)
    if sSql == "" then 
        mlogger:debug("没有加载加载版本信息,加载失败!")
        return false
    end

	local sPlatform = ""
	local sChannel = ""
	local sVersion = ""
	local sDownloadurl = ""
	local sAppurl = ""
	local cState = 0
	local sTime = ""
	local sConfigurl = ""
	local sConfigVersion = ""
	local sData = ""

	local nIndex = 0
	local tVersion = {}
	tBase.Log("开始读取版本信息的sql:%s ", sSql)
	local cursor = assert(dbSink.WebDB_connect:execute(sSql))
	repeat
		local row = cursor:fetch({}, "a")
		while row do
			function GetRes(row)
				sPlatform = row.Platform
				sChannel = row.Channel
				sVersion = row.Version			
				sDownloadurl = row.ZipFilePath
				sAppurl = row.AppUrl
				id = tonumber(row.id)
				cState = tonumber(row.State)
				sTime = row.OpenTime
				sCloseTime = row.CloseTime
				sConfigurl = row.MD5FilePath
				sConfigVersion = row.ConfigVersion
				
				if(sDownloadurl == nil) then sDownloadurl = "null_string" end
				if(sAppurl == nil) then sAppurl = "null_string" end
				if(sTime == nil) then sTime = "null_string" end
				if(sCloseTime == nil) then sCloseTime = "null_string" end
				if(sConfigurl == nil) then sConfigurl = "null_string" end
				if(sConfigVersion == nil) then sConfigVersion = "null_string" end

				local tRes ={}
				tRes.sPlatform = sPlatform
				tRes.sChannel = sChannel
				tRes.sVersion = sVersion
				tRes.sDownloadurl = sDownloadurl
				tRes.sAppurl = sAppurl 
				tRes.cState = cState
				tRes.sCloseTime = sCloseTime
				tRes.sTime = sTime
				tRes.sConfigurl = sConfigurl
				tRes.sConfigVersion = sConfigVersion
				table.insert(tVersion, tRes)
				sData = sData..sPlatform.."}}}"..sChannel.."}}}"..sVersion.."}}}"..sDownloadurl.."}}}"..sAppurl.."}}}"..cState.."}}}"..sCloseTime.."}}}"..sTime.."}}}"..sConfigurl.."}}}"..sConfigVersion.."}}}".."{{{{"
				tBase.Log("读取数据库，添加版本号信息  --->平台号：[%s]  渠道号：[%s]   版本号：%s ,配置版本号：%s ,热更下载地址：%s ,大版本更新下载地址：%s ,状态(0=错误 1=停机 2=正常)：%d ,关服时间:%s, 开服时间：%s,配置下载地址: %s ",
				sPlatform, sChannel,sVersion,sConfigVersion,sDownloadurl,sAppurl,cState,sCloseTime,sTime,sConfigurl)
			end

			-- 捕获异常,输出错误日志
            xpcall(GetRes,tErr.tpLog, row)

			nIndex = nIndex + 1
			row = cursor:fetch(row, "a")
		end
		cursor:close()
		cursor = dbSink.WebDB_connect:nextres()
	until(cursor == 0)

	local tSend = ProtoMgr.Gateway_pb.RUP_VersionCfg()
	tSend.sReturnKey = sReturnKey
	tSend.nIndex = nIndex
	tBase.Log("读取长度="..nIndex)
	if (nIndex > 0) then
		for key, val in pairs(tVersion) do
			local arr =  tSend.tVersion:add()
			arr.uVersionData = cjson.encode(val) 
		end
	else
		tBase.Log("data_err 长度不足 nIndex:"..nIndex)
	end

	local nMain = ProtoMgr.Sys.DB
	local nSub = ProtoMgr.Sub_GateWay.SUB_REP_VERSION_INFO
	local s = tBase.GetSP().new(nMain, nSub)
	s:AddString(tSend:SerializeToString())
	tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
	tBase.Log("读取数据库完毕,获取版本号信息 共(%d)条", nIndex)

end

function VersionSink.DBResLoadPhone(sReturnKey, sData, nLen)
	tBase.Log("DB加载手机苹果配置!")
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()

	local Read = ProtoMgr.Gateway_pb.RUQ_AppleCfg() 
	Read:ParseFromString(ReadData:GetString())
	local sSql = ""
    sSql = Read.sSql
    tBase.Log("sSql = %s",sSql)
    if sSql == "" then 
        mlogger:debug("没有载手机苹果信息,加载失败!")
        return false
    end

	local verson = ""
	local ShelfState
	local RegRes = {}
	local cursor = assert(dbSink.AccountsDB_connect:execute(sSql))
	local nIndex = 0
	repeat
		local row = cursor:fetch({}, "a")
		while row do
			function GetRes(row) 
				local temp = {}
				temp.Name = row.Name
				temp.channelMark =row.channelMark
				temp.CreateTime = row.CreateTime
				temp.Enbled = tonumber(row.Enabled)
				temp.version = row.version
				temp.ShelfState = tonumber(row.ShelfState) 
				table.insert(RegRes, temp)
			end 
			-- 捕获异常,输出错误日志
            xpcall(GetRes,tErr.tpLog, row)

			nIndex = nIndex + 1
			row = cursor:fetch(row, "a")
		end
		cursor:close()
		cursor = dbSink.AccountsDB_connect:nextres()
	until(cursor == 0)
	tBase.Log("加载完成后的配置表手机苹果信息RegRes = %s",cjson.encode(RegRes))
	local s = tBase.GetSP().new(nSystemID, nNewsID) 
	local tSend = ProtoMgr.Gateway_pb.RUP_AppleCfg()
	tSend.nIndex = nIndex
	if (nIndex > 0) then
		for key,val in pairs(RegRes) do
			local arr =  tSend.tApplecfg:add()
			arr.uApplecfgData = cjson.encode(val)
		end
	end
	s:AddString(tSend:SerializeToString())
	tBase.PostToGateway(sReturnKey, s:GetData(), s:GetSize())
	mlogger:debug("报告，加载手机版本配置完毕，请指示!")
	
end
 


return VersionSink
