--广播游戏战绩记录给APP

local tBase  = require("base")         -- 基础功能接口
local cjson     = require("cjson")        -- json 
local tPublicRedis =require("PublicRedis") -- Redis 公共接口 
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tSrvInfo = require("ServerInfo")
local tname = require("typename") -- 类弄定义接口
local WebCMD = ProtoMgr.Web_pb.Web_Sys()

local BroadCastRecordApp = {
    nReqTime = 0, --上次请求的时间
    arrRecords = {}, --游戏战绩
    nSpaceTime = 10, --请求的时间间隔
    nSpaceRedisTime = 60*5, --读取redis的时间间隔
    nReqWebCount = 0, --请求web服的次数
    nMaxCnt = 30,--单次发送最大条数
    arrParams = {
    ["nUserId"]="gameMemberId",          -- 玩家id
    ["nGameType"]="gameCode",            -- 游戏id
    ["sLiveID"]="liveId",                -- 场次ID
    ["nWinlose"]="amount",               -- 输赢
    ["nwin"]="win",                      -- 输赢和：1赢，2输，3和
    ["sExData"]="sExData"                -- 拓展字段{currentAmount=当前金币,recordType=0:普通,1试玩,2:pk,pkNumber=唯一索引,nPaiJuIndex=当局索引}   
    }
}

local tCache ={}
local function DoCache(func,...)  
	local parameter ={...}
	local sparameter =table.concat(parameter,"_")
	tCache[func]=tCache[func] or {}
	local tCacheRlt =tCache[func][sparameter]
	if tCacheRlt and (os.time()-tCacheRlt.nTime)<BroadCastRecordApp.nSpaceRedisTime then
		return table.unpack(tCacheRlt.arrRlt)
	end
	local arrRlt ={func(...)}
	tCache[func][sparameter] ={arrRlt=arrRlt,nTime=os.time()}
	return table.unpack(arrRlt)
end

--写游戏记录
--@params tRecord = {gameMemberId=玩家id,gameCode=游戏id,liveId=场次ID,amount=输赢,win=输赢和：1赢，2输，3和}
function BroadCastRecordApp.WriteGameRecord(tRecord)
    if not tRecord then   
        tBase.Log("_WriteGameRecord tData is nil  ",cjson.encode(tRecord))
        return
    end
    -- 不需要的字段 
    local tNotKey = {
        ["tElseInfo"]= true, 
        ["IsControl"]= true, 
        ["nWinloseToRobot"]= true,      
        ["nDrawWaterToRobot"] = true,
        ["nDrawWater"] =true,
        ["nShopId"] = true,
        ["nSession"] = true,
        --["sPaiJuId"] = true,
        ["nIsZhuang"] = true,
        ["nGroupId"] = true,
        ["nWinLose"] = true, 
    }
    local tData = {} 
    for skey,v in pairs(tRecord) do 
        if not tNotKey[skey] then 
            tData[skey] = v 
        end  
    end 
    if not tData.sLiveID or #tData.sLiveID <= 0 then
        tData.sLiveID = "0" 
    end
    tData.nwin = 3    --输赢和：1赢，2输，3和
    if tData.nWinlose > 0 then
        tData.nwin =  1  
    elseif tData.nWinlose < 0 then
        tData.nwin = 2    
    end   
    if tRecord.nRecordType == 2 then   -- 试玩
        local tExData = {}
        tExData.tElseInfo = tRecord.tElseInfo
        tData.sExData = cjson.encode(tExData)
    end 
    tData.settleTime = os.time() 
    if tRecord.sPaiJuId then
        tData.sPaiJuId = tRecord.sPaiJuId
    else
        tData.sPaiJuId = ""
    end

    table.insert(BroadCastRecordApp.arrRecords,tData)
    -- tBase.Log("_WriteGameRecord  战绩播报 nUserId_%d   nRecordType_%d  tData: %s  ",tData.nUserId,tData.nRecordType,cjson.encode(tData))

    if tRecord.nRecordType ~= 1 then 
        BroadCastRecordApp.CheckIsSend()
    else
        BroadCastRecordApp.PackDataToSend()    -- PK 立即 推送战绩    
    end 
    return
end

--检查是否发送
function BroadCastRecordApp.CheckIsSend()
    --tBase.Log("战绩播报 CheckIsSend")
    local nSpaceTime = os.time()-BroadCastRecordApp.nReqTime
    if (nSpaceTime>=BroadCastRecordApp.nSpaceTime and #BroadCastRecordApp.arrRecords > 0) or (#BroadCastRecordApp.arrRecords >= BroadCastRecordApp.nMaxCnt)  then
        --距离上一次请求发送web时间有一段时间了,发送一次
        BroadCastRecordApp.PackDataToSend()
    else
        --距离上一次请求发送web时间还没多久，过一会再检查一次
        tBase.SetTimer(60111,1000*BroadCastRecordApp.nSpaceTime,1,BroadCastRecordApp.CheckIsSend)
    end
end

--发送到
function BroadCastRecordApp.PackDataToSend()
    --tBase.Log("战绩播报 PackDataToSend")
    local nLen = #BroadCastRecordApp.arrRecords
    local nMaxCnt = BroadCastRecordApp.nMaxCnt
    local nSendCnt = math.min(nMaxCnt,nLen)

    local sDomainName = DoCache(tPublicRedis.GetRecordBraodCastDomainName)
    --sDomainName = "http://192.168.0.215:91/SFAPI/ReportGameWin"
    if not sDomainName then
        tBase.Log("_PackDataToSend 后台没有在redis设置http请求的域名")
        tBase._OnMonitorInfo("后台没有在redis设置http请求的域名",tSrvInfo.nServerId)
        return
    end

    local arrSend = {}
    for i=1,nSendCnt do
        local tData = table.remove(BroadCastRecordApp.arrRecords,1)
        if tData then
            table.insert(arrSend,tData)
        end
    end
   
    if #arrSend>0 then
        local sUrl = sDomainName
        local sBody = cjson.encode(arrSend)
        tBase.Log("_PackDataToSend nCnt_%d sUrl_%s #arrSend_%d ",#arrSend,sUrl,#arrSend)
        BroadCastRecordApp.SendToWeb(sUrl,sBody)
    end

    if nLen>nMaxCnt then
        --超过nMaxCnt条数据,间隔一段时间再发
        tBase.SetTimer(60115,1000*6,1,BroadCastRecordApp.PackDataToSend)
    end
end

--发送到web服
function BroadCastRecordApp.SendToWeb(sUrl,sBody) 
    local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
    if #arrServerKey==0 then
        tBase.Log("_SendToWeb ERROR  arrServerKey:  %d ",#arrServerKey)
        return false
    end
    BroadCastRecordApp.nReqTime = os.time()

    local dex =BroadCastRecordApp.nReqWebCount%(#arrServerKey) +1
    local sChooseKey =arrServerKey[dex]
    BroadCastRecordApp.nReqWebCount =BroadCastRecordApp.nReqWebCount +1
    local Send = ProtoMgr.Web_pb.WebUrlReq()  
    Send.sUrl = sUrl
    Send.sSerialNum =string.format("%d_%d",tSrvInfo.nServerId,BroadCastRecordApp.nReqWebCount)
    Send.sSendType = "POST"
    Send.sBody = sBody
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUrlReq_CMD)
    tPacket:AddString(Send:SerializeToString())   
    tBase.PostToServer(sChooseKey, 0, tPacket:GetData(), tPacket:GetSize())
    return true
end

--发送到web服（用Get方法请求）
function BroadCastRecordApp.SendToWebGetRequset(sUrl) 
    local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
    if #arrServerKey==0 then
        tBase.Log("_AppBlackListSendToWeb ERROR  arrServerKey:  %d ",#arrServerKey)
        return false
    end
    if not sUrl then
        base.Log("SendToWebGetRequset: sUrl is nil")
        return
    end
    base.Log("SendToWebGetRequset_%s",sUrl)
    local dex =BroadCastRecordApp.nReqWebCount%(#arrServerKey) +1
    local sChooseKey =arrServerKey[dex]
    BroadCastRecordApp.nReqWebCount =BroadCastRecordApp.nReqWebCount +1
    local Send = ProtoMgr.Web_pb.WebUrlReq()  
    Send.sUrl = sUrl
    Send.sSerialNum =string.format("%d_%d",tSrvInfo.nServerId,BroadCastRecordApp.nReqWebCount)
    Send.sSendType = "GET"
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUrlReq_CMD)
    tPacket:AddString(Send:SerializeToString())   
    tBase.PostToServer(sChooseKey, 0, tPacket:GetData(), tPacket:GetSize())
    return true
end

--发送到web服（其它厂商输赢）
function BroadCastRecordApp.SendToWebPlatformWinloseRequset(sUrl,nUserId,nGroupId,sSendType) 
    local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
    if #arrServerKey==0 then
        tBase.Log("SendToWebPlatformWinloseRequset ERROR  arrServerKey:  %d ",#arrServerKey)
        return false
    end
    if not sUrl then
        base.Log("SendToWebPlatformWinloseRequset: sUrl is nil")
        return
    end
    base.Log("SendToWebPlatformWinloseRequset_%s",sUrl)
    local dex =BroadCastRecordApp.nReqWebCount%(#arrServerKey) +1
    local sChooseKey =arrServerKey[dex]
    BroadCastRecordApp.nReqWebCount =BroadCastRecordApp.nReqWebCount +1
    local Send = ProtoMgr.Web_pb.WebOtherPlatformWinloseReq()  
    Send.sUrl = sUrl
    Send.sSerialNum =string.format("%d_%d",tSrvInfo.nServerId,BroadCastRecordApp.nReqWebCount)
    Send.sSendType = sSendType
    Send.nUserId = nUserId
    Send.nGroupId = nGroupId
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebOtherPlatformWinloseReq_CMD)
    tPacket:AddString(Send:SerializeToString())   
    tBase.PostToServer(sChooseKey, 0, tPacket:GetData(), tPacket:GetSize())
    return true
end



return BroadCastRecordApp