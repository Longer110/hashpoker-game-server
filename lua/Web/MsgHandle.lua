package.path = require("./lua/Web/Head").path

local tBase  = require("base")         -- 基础功能接口
local ProtoMgr  = require("ProtoManager") -- 协议管理对象 
local http      = require("socket.http")  -- Http 服务器
local cjson     = require("cjson")
local tPubUserApi  = require("PublicUserInfo")    --玩家数据
local tPublicRedis =require("PublicRedis")
local tSrvInfo = require("ServerInfo") 
local mlogger = require("logger")      -- 日志对象
local tname = require("typename") -- 类弄定义接口
local api       = require("publicApi")    -- 共用功能接口
local tPublicUserGold= require("PublicUserGold")

local MsgHandle ={}
local WebProto = ProtoMgr.Web_pb.Web_Sys()


local tRequestUrlToTime ={}

--结果放redis
function MsgHandle.OnWebUrlReq(sReturnKey,sData,nLen)
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()
	local Read = ProtoMgr.Web_pb.WebUrlReq() 
	Read:ParseFromString(ReadData:GetString())
	local sUrl =Read.sUrl
	local sSerialNum =Read.sSerialNum or "nil"
	local sSendType = Read.sSendType or "GET"  
	local sBody = Read.sBody or nil
	local requestTime =tBase.GetTime()
	local lastTime =tRequestUrlToTime[sUrl] or 0
	local reqGap =requestTime -lastTime				--同一url请求间隔 ms

	if reqGap <5000 then
		if sSendType == "POST" then
			tBase.Log("UrlReqWaring,POST %s in %dms",sUrl,reqGap)
		else
			tBase.LogT("UrlReq 短时间内拒绝重复请求 sUrl_",sUrl)
			return
		end
	end

	local funcRes = function(json_data,nCode) 
		tRequestUrlToTime[sUrl] =nil
		local json_data =json_data or ""
		local diffTime =tBase.GetTime() - requestTime
		if tonumber(nCode)~=200 then 
			local sErr =string.format("UrlReqFail,%s sUrl:%s nCode:%s res:%s seria:%s %dms",sSendType,sUrl,tostring(nCode),json_data,sSerialNum,diffTime)
			tBase.Log(sErr)
			tBase._OnMonitorInfo(sErr,tSrvInfo.nServerId)
			return
		end
		local tRedis = tBase.m_MyRedisData[1].redis 
		local sKey ="HttpResult:"..sUrl
		tRedis:set(sKey,json_data)
		tRedis:expire(sKey,20)
		tBase.Log("UrlReq %s sUrl:%s nCode:%s res:%s seria:%s %dms Len:%d",
			sSendType,sUrl,tostring(nCode),string.sub(json_data,1,50),sSerialNum,diffTime,#json_data)
	end

	local funcError = function(nCode)
		tRequestUrlToTime[sUrl] =nil
		local diffTime =tBase.GetTime() - requestTime
		local sErr =string.format("UrlReqError,%s sUrl:%s nCode:%s %dms seria:%s",sSendType,sUrl,tostring(nCode),diffTime,sSerialNum)
		tBase.Log(sErr)
		tBase._OnMonitorInfo(sErr,tSrvInfo.nServerId)
	end
	tRequestUrlToTime[sUrl] =requestTime
    UrlRequest(sUrl, funcRes, funcError,sSendType,sBody)
    return
end

--结果返回给对应服
function MsgHandle.OnWebUrlReqAndReturn(sReturnKey,sData,nLen)
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()
	local Read = ProtoMgr.Web_pb.WebUrlReqAndReturn() 
	Read:ParseFromString(ReadData:GetString())
	local sUrl =Read.sUrl
	local sUserId = Read.nUserId
	local sSerialNum =Read.sSerialNum or "nil"
	local sSendType = Read.sSendType or "GET"  
	local sBody = Read.sBody or nil
	local requestTime =tBase.GetTime()
	local lastTime =tRequestUrlToTime[sUrl] or 0
	local reqGap =requestTime -lastTime				--同一url请求间隔 ms

	if reqGap <5000 then
		if sSendType == "POST" then
			tBase.Log("UrlReqWaring,POST %s in %dms",sUrl,reqGap)
		else
			tBase.LogT("UrlReq 短时间内拒绝重复请求 sUrl_",sUrl)
			return
		end
	end

	local funcRes = function(json_data,nCode) 
		tRequestUrlToTime[sUrl] =nil
		local json_data =json_data or ""
		local diffTime =tBase.GetTime() - requestTime
		if tonumber(nCode)~=200 then 
			local sErr =string.format("UrlReqFail,%s sUrl:%s nCode:%s res:%s seria:%s %dms",sSendType,sUrl,tostring(nCode),json_data,sSerialNum,diffTime)
			tBase.Log(sErr)
			tBase._OnMonitorInfo(sErr,tSrvInfo.nServerId)
			local WebUrlRsp = ProtoMgr.Web_pb.WebUrlRsp()  
			WebUrlRsp.sJsonData = "502"
			WebUrlRsp.nCode = nCode
			WebUrlRsp.nUserId = sUserId
			local s = tBase.GetSP().new(WebProto.Main_CMD,WebProto.WebUrlRsp_CMD)
			s:AddString(WebUrlRsp:SerializeToString())
			tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
			return
		end
		local WebUrlRsp = ProtoMgr.Web_pb.WebUrlRsp()  
		WebUrlRsp.sJsonData = json_data
		WebUrlRsp.nCode = nCode
		WebUrlRsp.nUserId = sUserId
		local s = tBase.GetSP().new(WebProto.Main_CMD,WebProto.WebUrlRsp_CMD)
		s:AddString(WebUrlRsp:SerializeToString())
		tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
		tBase.Log("UrlReq %s sUrl:%s nCode:%s res:%s seria:%s %dms Len:%d",
			sSendType,sUrl,tostring(nCode),string.sub(json_data,1,50),sSerialNum,diffTime,#json_data)
	end

	local funcError = function(nCode)
		tRequestUrlToTime[sUrl] =nil
		local diffTime =tBase.GetTime() - requestTime
		local sErr =string.format("UrlReqError,%s sUrl:%s nCode:%s %dms seria:%s",sSendType,sUrl,tostring(nCode),diffTime,sSerialNum)
		tBase.Log(sErr)
		tBase._OnMonitorInfo(sErr,tSrvInfo.nServerId)
		-- local WebUrlRsp = ProtoMgr.Web_pb.WebUrlRsp()  
		-- WebUrlRsp.sJsonData = "500"
		-- WebUrlRsp.nCode = nCode
		-- WebUrlRsp.nUserId = sUserId
		-- local s = tBase.GetSP().new(WebProto.Main_CMD,WebProto.WebUrlRsp_CMD)
		-- s:AddString(WebUrlRsp:SerializeToString())
		-- tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
	end
	tRequestUrlToTime[sUrl] =requestTime
    UrlRequest(sUrl, funcRes, funcError,sSendType,sBody)
    return
end


local OnWebHttpReqId =0
function MsgHandle.OnWebHttpReq(sReturnKey,sData,nLen)
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()
	local Read = ProtoMgr.PubProto_1_pb.WebMessReq() 
	Read:ParseFromString(ReadData:GetString())
	local sUrl =Read.strHMsg
	local sSendType = Read.sSendType or nil  
	local sBody = Read.sBody or nil
	OnWebHttpReqId =OnWebHttpReqId+1
	local nReqId =OnWebHttpReqId

	tBase.Log("OnWebHttpReq_%d:%s",nReqId,sUrl)
	local funcRes = function(json_data,nCode) 
		tBase.Log("OnWebHttpReq_%d funcRes:%s,%s",nReqId,tostring(json_data),tostring(nCode))
	end
	local funcError = function(nCode)
		tBase.Log("OnWebHttpReq_%d funcError",nReqId)
		if nCode then
			tBase.LogT("OnWebHttpReq_ funcError nCode_",nCode)
		end
	end
	UrlRequest(sUrl, funcRes, funcError,sSendType,sBody)
 end


local nReqId =0
local function CreateHandleFunc()
	nReqId =nReqId +1
	local nIdCopy =nReqId
	local funcRes = function(sRes)
		local sStr =string.format("RequestId:%d Res:%s",nIdCopy,sRes)
		tBase.Log(sStr)
		local isSuccee,tRlt =pcall(cjson.decode,sRes)
		if (not isSuccee) or (not tRlt.code) or (tRlt.code~=1) then
			tBase._OnMonitorInfo(sStr,tSrvInfo.nServerId)
			if not isSuccee then
				tBase.Log(" not isSuccee,_CreateHandleFunc failed,RequestId:%d Res:%s",nIdCopy,sRes)
			end
			if not tRlt then
				tBase.Log(" not tRlt,_CreateHandleFunc failed,RequestId:%d Res:%s",nIdCopy,sRes)
			else
				if tRlt.code~=1 then
					tBase.Log(" tRlt.code~=1,_CreateHandleFunc failed,RequestId:%d Res:%s",nIdCopy,sRes)
				end
			end
			return
		end
	end
	local funcError = function(nCode)
		local sStr =string.format("RequestId:%d ErrorHappen",nIdCopy)
		tBase.Log(sStr) 
		if nCode then
			tBase.LogT("RequestId: ErrorHappen nCode_",nCode)
		end
		tBase._OnMonitorInfo(sStr,tSrvInfo.nServerId)
	 end
	 return funcRes,funcError,nIdCopy
end

--TransferNotifyConfig
--[[
local tTransferNotifyInfo={}
tTransferNotifyInfo.sUrl ="http://mwsys-gw-api.nn722.com/gamenotice/notify/callback"
tTransferNotifyInfo.vendorNo ="RY"
tTransferNotifyInfo.key ="28EOTrufKXHeErXb"
]]

local tGroupIdToTransferConfig ={}
local function GetTransferNotifyInfo(nGroupId)
	local nCurTime =os.time()
	local tCache =tGroupIdToTransferConfig[nGroupId]
	if tCache and (nCurTime -tCache.nUpdateTime)<15 then
		return tCache.tTransferConfig
	end
	local tem = tPublicRedis.GetTransferNotifyInfo(nGroupId)
	if tem.sUrl==nil or tem.vendorNo==nil or tem.key ==nil then
		tem=nil
	end
	tGroupIdToTransferConfig[nGroupId] ={nUpdateTime=nCurTime,tTransferConfig=tem}
	tBase.LogT("tTransferNotifyInfo,nGroupId:",nGroupId,tem)
	return tem
end

 --local tOffLineUserInfo ={}
 function MsgHandle.OnWebUserOnlineStatus(sReturnKey,sData,nLen)
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()
	local Read = ProtoMgr.Web_pb.WebUserOnlineStatus() 
	Read:ParseFromString(ReadData:GetString())

	local nUserId =Read.nUserId
	local nStatus =Read.nStatus
	local sShopAccount =Read.sElse

	local nGroupId =tPubUserApi.Get_User_GroupId(nUserId) or -1
	local tTransferInfo =GetTransferNotifyInfo(nGroupId)
	if tTransferInfo ==nil then
		tBase.Log("TransferNotifyInfo is nil,nGroupId:%d",nGroupId)
		return
	end

	--玩家上线
	if nStatus ==1 then
		--tOffLineUserInfo[nUserId] =nil
		local info ={}
		info.vendorNo =tTransferInfo.vendorNo
		info.action =1
		info.key =tTransferInfo.key
		info.userIds ={sShopAccount}
		local Req ={}
		Req.sUrl =tTransferInfo.sUrl
		Req.body =cjson.encode(info)
		local funcRes,funcError,nRequestId =CreateHandleFunc()
		tBase.Log("nRequestId:%d nUserId:%d sShopAccount:%s OnLine Req.body_%s,Req.sUrl_%s",nRequestId,nUserId,sShopAccount,Req.body,Req.sUrl)
		local sSendType = nil
		local sBody = nil
		UrlRequest(Req, funcRes, funcError,sSendType,sBody)

	    --local sRes,rr,bb = http.request(Req.sUrl, Req.body)
	    --tBase.LogT("OnWebUserOnlineStatus返回：",sRes,rr,bb) 

		return
	end
	--玩家离线
	if nStatus ==2 then
		tBase.Log("nUserId:%d sShopAccount:%s OffLine",nUserId,sShopAccount)
		local tData = {sShopAccount=sShopAccount,nOffLineTime=os.time(),nCntNotify=0,nGroupId=nGroupId}
		tPublicRedis.OffLineUserInfo(1,nUserId,cjson.encode(tData))
		--tOffLineUserInfo[nUserId] = {sShopAccount=sShopAccount,nOffLineTime=os.time(),nCntNotify=0,nGroupId=nGroupId}
		return
	end
 end

 local function _DoSomething(tInfo,nCurTime,nUserId)
	local nTimePass =nCurTime -tInfo.nOffLineTime
	if nTimePass < (tInfo.nCntNotify*60 +60)then
		-- tBase.LogT("_DoSomething: ",{nUserId=nUserId,nTimePass=nTimePass ,nCntNotify=(tInfo.nCntNotify*60 +60)})
		return
	end
	local isTimeOut =(nTimePass > 7200)
	
	local arrRlt=tPubUserApi.GetUserNumFields(nUserId,{"nGameId","UnbalancedCnt","sGateKey"})
	local nGameId =arrRlt[1]
	local UnbalancedCnt  =arrRlt[2]
	local sGateKey =arrRlt[3]
	tBase.LogT("_DoSomething: ",{nUserId=nUserId,nGameId=nGameId ,UnbalancedCnt=UnbalancedCnt,sGateKey=sGateKey})

	if sGateKey and #sGateKey>0 then
		return 0
	end
	if nGameId and (not isTimeOut) then
		return UnbalancedCnt 
	end
	if UnbalancedCnt and UnbalancedCnt >0 and (not isTimeOut) then
		return
	end 

	--local nGold =tPubUserApi.Get_User_Gold(nUserId)
	local nRetain,_,nGold =tPublicUserGold.GetRetainGold(nUserId)
	if (not (nGold>nRetain and (math.abs(nGold-nRetain) >1e-6))) and tInfo.nCntNotify>0 then
		return 0
	end
	
	local tTransferInfo =GetTransferNotifyInfo(tInfo.nGroupId)
	if tTransferInfo ==nil then
		tBase.Log("TransferNotifyInfo is nil in _DoSomething")
		return 0
	end
	local info ={}
	info.vendorNo =tTransferInfo.vendorNo
	info.action =2
	info.key =tTransferInfo.key
	info.userIds ={tInfo.sShopAccount}
	local Req ={}
	Req.sUrl =tTransferInfo.sUrl
	Req.body =cjson.encode(info)
	local funcRes,funcError,nRequestId =CreateHandleFunc()
	tBase.Log("nRequestId:%d nUserId:%d sShopAccount:%s OffLine",nRequestId,nUserId,tInfo.sShopAccount)
	local sSendType = nil
	local sBody = nil
	UrlRequest(Req, funcRes, funcError,sSendType,sBody)
	tInfo.nCntNotify =tInfo.nCntNotify +1
	tPublicRedis.OffLineUserInfo(1,nUserId,cjson.encode(tInfo))
	if isTimeOut then
		return 0
	end
 end

 function MsgHandle.OffLineUserCheck()
	local nCurTime =os.time()
	local tOffLineUserInfo =  tPublicRedis.OffLineUserInfo(2)
	local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
	local nIndex = math.floor(tBase.GetThreadIndex())
	--tBase.LogT("OffLineUserCheck  m_tKey: ",Base.m_tKey)
	local nSkeyCount = 0
	
    for _,sServKey in ipairs(arrServerKey) do
      local nServerId =tonumber(string.match(sServKey,"_(%d+)"))
      if nServerId ==tSrvInfo.nServerId then
		nSkeyCount = nSkeyCount + 1
      end
    end
	--tBase.Log("OffLineUserCheck  nSkeyCount: %d ",nSkeyCount)
	if nSkeyCount<=0 then
		tBase.Log("OffLineUserCheck  nSkeyCount: %d ",nSkeyCount)
		return
	end
	for nUserId,tInfo in pairs(tOffLineUserInfo) do
		if nUserId%nSkeyCount == nIndex then 
			if _DoSomething(tInfo,nCurTime,nUserId) ==0 then
				--tOffLineUserInfo[nUserId]=nil
				tPublicRedis.OffLineUserInfo(3,nUserId)
			elseif tInfo.nCntNotify > 2 then
				local sOffLine = api.OsTimetoDataTime(tonumber(tInfo.nOffLineTime))
				local sStr =string.format("金币转出告警: nUserId:%d 离线: %s,已通知APP %d 次,还没转走金币 ",nUserId,sOffLine,tInfo.nCntNotify)
				tBase.Log("_OffLineUserCheck: %s   %s ",sStr,cjson.encode(tInfo))
				tBase._OnMonitorInfo(sStr,tSrvInfo.nServerId)
			end
		end
	end
 end

 function MsgHandle.OnWebOtherPlatformWinloseReq(sReturnKey,sData,nLen)
	local ReadData = base.GetRP().new(sData, nLen)
	local nSystemID = ReadData:GetModuleID()
	local nNewsID = ReadData:GetMsgID()
	local Read = ProtoMgr.Web_pb.WebOtherPlatformWinloseReq() 
	Read:ParseFromString(ReadData:GetString())
	local sUrl =Read.sUrl
	local sSerialNum =Read.sSerialNum or "nil"
	local sSendType = Read.sSendType or nil  
	local sBody = Read.sBody or nil
	local nUserId = Read.nUserId
	local nGroupId = Read.nGroupId
	local nStartTime =os.time()	 


	if sSendType == "POST" and tRequestUrlToTime[sUrl] then
		tRequestUrlToTime[sUrl]=nil		
	end 
	local funcRes = function(json_data,nCode) 
		local nRequetTIme = tBase.GetTime()
		if tRequestUrlToTime[sUrl] then 
			nRequetTIme = tRequestUrlToTime[sUrl].nRequetTIme or 0 
		end 
		tRequestUrlToTime[sUrl]=nil
		if not json_data then 
			tBase.Log("_OnWebOtherPlatformWinloseReq  http fail,%s sSerialNum:%s",sUrl,sSerialNum)
			return
		elseif sSendType == "POST" then
			local err,unjson = pcall(function(str)return cjson.decode(str)end,json_data)
			if err then
				if tonumber(unjson.code) ~= 10000 then	
					mlogger:error(string.format("_OnWebOtherPlatformWinloseReq POST send fail,code_%d,sUrl_%s sBody_%s", unjson.code, sUrl,sBody))
					return
				end
			else
				mlogger:error(string.format("_OnWebOtherPlatformWinloseReq POST send fail,sUrl_%s sBody_%s", sUrl,sBody))
			end			
		end
		if nCode and type(nCode) == "tonumber" and tonumber(nCode) ~= 200  then 
			tBase.Log("_OnWebOtherPlatformWinloseReq fail nCode=%d, %s  ",nCode,sUrl)		
			return 				
		end		

		local nEndTime =os.time()
		local nDiffTime =nEndTime -nStartTime
		local nTime =tBase.GetTime() -nRequetTIme

		local strRet = cjson.decode(json_data)
		tBase.LogT(" _OnWebOtherPlatformWinloseRep json_data_",strRet)  
		if math.floor(tonumber(strRet.status))  == 0 then
			local tInfo = {nUserID=nUserId,nWinlose=strRet.winLose}
			tPublicRedis.SetUserOherPlatformWinlose(nGroupId,tInfo)

			tBase.Log("_OnWebOtherPlatformWinloseReq http succee,%s  sSerialNum:%s  %d毫秒  nDiffTime:%.3f   sSerialNum_%s json_data:%s Len:%d",
				sUrl,sSerialNum,nTime,nDiffTime,sSerialNum,string.sub(json_data,1,50),#json_data)
		else
			tBase.LogT("_OnWebOtherPlatformWinloseReq http fail 获取厂商信息错误_",sUrl,strRet.error_MS)
		end 

		return 
	end
	local funcError = function(nCode)
		local nRequetTIme = tBase.GetTime()
		if tRequestUrlToTime[sUrl] then 
			nRequetTIme = tRequestUrlToTime[sUrl].nRequetTIme or 0 
		end 	
		local nTime =tBase.GetTime() -nRequetTIme
		tRequestUrlToTime[sUrl]=nil
		local sLog = string.format("_OnWebOtherPlatformWinloseReq  %d毫秒 异常的处理 sUrl_%s sSerialNum_%s nCode_%s",nTime,sUrl,sSerialNum,nCode)
		tBase.Log(sLog)
		local nLastReqTime = os.time()
		if tRequestUrlToTime[sUrl] then
			nLastReqTime = tRequestUrlToTime[sUrl].ReqTime or os.time()
		end
		if os.time() - nLastReqTime > 60 then
			tBase._OnMonitorInfo(sLog,tSrvInfo.nServerId)
		end 
	end

	if sSendType ~= "POST" then --同一url，上一请求还没返回结果前，短时间内拒绝重复请求
		if tRequestUrlToTime[sUrl] and (nStartTime -tRequestUrlToTime[sUrl].ReqTime)<=5 then
			tBase.LogT("_OnWebOtherPlatformWinloseReq  短时间内拒绝重复请求 sUrl_",sUrl)
			return
		end
		tRequestUrlToTime[sUrl] ={ReqTime=nStartTime,nRequetTIme=tBase.GetTime()}
	end 
    UrlRequest(sUrl, funcRes, funcError,sSendType,sBody)
end

local arrLoadDate ={}


local function _LoadHoliday(sDate)
	--[[
		{
		"code": 0,              // 0服务正常。-1服务出错
		"type": {
			"type": enum(0, 1, 2, 3), // 节假日类型，分别表示 工作日、周末、节日、调休。
			"name": "周六",         // 节假日类型中文名，可能值为 周一 至 周日、假期的名字、某某调休。
			"week": enum(1 - 7)    // 一周中的第几天。值为 1 - 7，分别表示 周一 至 周日。
		},
		"holiday": {
			"holiday": false,     // true表示是节假日，false表示是调休
			"name": "国庆前调休",  // 节假日的中文名。如果是调休，则是调休的中文名，例如'国庆前调休'
			"wage": 1,            // 薪资倍数，1表示是1倍工资
			"after": false,       // 只在调休下有该字段。true表示放完假后调休，false表示先调休再放假
			"target": '国庆节'     // 只在调休下有该字段。表示调休的节假日
		}
		}
	]]

	local sUrl = "https://timor.tech/api/holiday/info/"..sDate 

	local funcRes = function(json_data,nCode) 
		if tonumber(nCode) ~= 200 then 
			tBase.Log("_LoadHoliday   funcRes_%s nCode_%s  ",tostring(json_data),tostring(nCode))
			return 
		end  
		local tResult = cjson.decode(json_data)		
		if tResult.code ~= 0 then 
			tBase.Log("_LoadHoliday   服务出错  加载节假日: "..json_data) 
			return 
		end  
		local sLog = "" 
		local nEnum = tonumber(tResult.type.type)  --"(0, 1, 2, 3)节假日类型，分别:工作日、周末、节日、调休。
		if nEnum == 0 then 
			sLog ="工作日"
		elseif nEnum == 1 then
			sLog ="周末"
		elseif nEnum == 2 then
			sLog ="节假日"
		elseif nEnum == 3 then
			sLog ="调休"
		end 
		local tRedis = tBase.m_MyRedisData[2].redis 
		local sKey ="HoliDay"
		tRedis:hset(sKey,sDate,nEnum) 		 
		tBase.Log("_LoadHoliday  加载节假日 sDate: %s %s  %s ",sDate,sLog,json_data)		
	end
	local funcError = function(nCode)
		tBase.Log("_LoadHoliday funcError  sUrl: "..sUrl)
		if nCode then
			tBase.LogT("_LoadHoliday funcError nCode_",nCode)
		end
	end	
	UrlRequest(sUrl,funcRes,funcError)  	
end	

function MsgHandle.LoadHoliday()
	local arrMother = {}
	arrMother[4] = {20,21,22,23,24,25,26,27,28,29,30}
	arrMother[5] = {1,2,3,4,5,6,7,8}
	local arrRequest ={}
	for Mother, arrDay in pairs(arrMother) do
		for _, nDay in ipairs(arrDay) do
			local sDate = "2023-0"..Mother
			if nDay < 10 then 
				sDate = sDate.."-0"..nDay
			else
				sDate = sDate.."-"..nDay
			end  
			if not arrLoadDate[sDate] then 
				table.insert(arrRequest,sDate)
			end  
		end
	end	
	tBase.Log("_LoadHoliday   arrRequest: "..#arrRequest) 	
	local function _Req_LoadHoliday()
		local sDate = table.remove(arrRequest)
		if sDate then 
			arrLoadDate[sDate] = 0
			_LoadHoliday(sDate)
		else
			local arrSuccess = {}
			for sDate, n in pairs(arrLoadDate) do
				if n == 1 then 
					table.insert(arrSuccess,sDate)
				end 
			end
			-- if #arrSuccess > 0 then 
				tBase.Log("_LoadHoliday   arrSuccess: "..#arrSuccess) 
			-- end 
		end 
	end 
    base.SetTimer(60012, 1000* 10, -1,_Req_LoadHoliday)   
end 
 
--[[
	加载 节假日
	参考： http://timor.tech/api/holiday/
	每天凌晨更新一次 
]] 
function MsgHandle.LoadHoliday1()
    local  sDate = os.date("%Y-%m-%d",os.time())	
	local tRedis = tBase.m_MyRedisData[2].redis 
	local sKey ="HoliDay"
	local nHoliDay = tRedis:hget(sKey,sDate) 	
	if not nHoliDay then 
		_LoadHoliday(sDate)
	end 
	-- 计算零点 再重新加载
	local nZero = publicApi.GetLeroLeadTime() 
    base.SetTimer(1120, 1000 * nZero, 1, MsgHandle.LoadHoliday1) 
	tBase.Log("_LoadHoliday1  nZero_%d   ",nZero) 
	return  
end


return MsgHandle
