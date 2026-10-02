--试玩金币投注记录

local tBase  = require("base")         -- 基础功能接口
local cjson     = require("cjson")        -- json 
local tPublicRedis =require("PublicRedis") -- Redis 公共接口 
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tSrvInfo = require("ServerInfo")
local tname = require("typename") -- 类弄定义接口
local WebCMD = ProtoMgr.Web_pb.Web_Sys()

local DemoPetternRecord = {
    nReqTime = 0, --上次请求的时间
    arrRecords = {}, --试玩金币战绩
    nSpaceTime = 10, --请求的时间间隔
    nSpaceRedisTime = 60*5, --读取redis的时间间隔
    nReqWebCount = 0, --请求web服的次数
    nMaxCnt = 50,--单次发送最大条数
    arrParams = {
    ["nUserId"]="UserId",
    ["nGameID"]="GameID",
    ["nXiaZhu"]="XiaZhu",
    ["nWinLose"]="WinLose",
    ["nValid"]="Valid",
    ["nTestGold"]="Balance",
    ["sLiveID"]="LiveID",
    ["sExData"]="sExData"         -- 拓展字段     
    }
}

local tCache ={}
local function DoCache(func,...)  
	local parameter ={...}
	local sparameter =table.concat(parameter,"_")
	tCache[func]=tCache[func] or {}
	local tCacheRlt =tCache[func][sparameter]
	if tCacheRlt and (os.time()-tCacheRlt.nTime)<DemoPetternRecord.nSpaceRedisTime then
		return table.unpack(tCacheRlt.arrRlt)
	end
	local arrRlt ={func(...)}
	tCache[func][sparameter] ={arrRlt=arrRlt,nTime=os.time()}
	return table.unpack(arrRlt)
end

--写试玩金币记录
--@params tRecord = {nUserId=玩家id,nGameID=游戏id,nXiaZhu=下注,nWinLose=输赢,nValid=有效投注,nTestGold=剩余的试玩金币,sLiveID=主播间id}
function DemoPetternRecord.WriteDemoPetternRecord(tRecord)
    --参数校验
    if not tRecord then
        return
    end
    for k,v in pairs(DemoPetternRecord.arrParams) do
        if not tRecord[k] and k ~= "sExData" then
            tBase.Log("WriteDemoPetternRecord Error:缺少参数 %s",k)
            return
        end
    end
    local tData = {}
    for k,v in pairs(tRecord) do
        local skey = DemoPetternRecord.arrParams[k]
        if skey then
            tData[skey] = v
        end
    end
    tData.CreateTime = tostring(os.time())

    table.insert(DemoPetternRecord.arrRecords,tData)

    DemoPetternRecord.CheckIsSend()
end

--检查是否发送
function DemoPetternRecord.CheckIsSend()
    local nSpaceTime = os.time()-DemoPetternRecord.nReqTime
    if nSpaceTime>=DemoPetternRecord.nSpaceTime then
        --距离上一次请求发送web时间有一段时间了,发送一次
        DemoPetternRecord.PackDataToSend()
    else
        --距离上一次请求发送web时间还没多久，过一会再检查一次
        tBase.SetTimer(60111,1000*DemoPetternRecord.nSpaceTime,1,DemoPetternRecord.CheckIsSend)
    end
end

--发送到
function DemoPetternRecord.PackDataToSend()
    local nLen = #DemoPetternRecord.arrRecords
    local nMaxCnt = DemoPetternRecord.nMaxCnt
    local nSendCnt = math.min(nMaxCnt,nLen)

    local sDomainName = DoCache(tPublicRedis.GetDemoPetternDomainName)
    if not sDomainName then
        tBase.Log("后台没有在redis设置接收试玩金币下注记录的域名")
        tBase._OnMonitorInfo("后台没有在redis设置接收试玩金币下注记录的域名",tSrvInfo.nServerId)
        return
    end

    local arrSend = {}
    for i=1,nSendCnt do
        local tData = table.remove(DemoPetternRecord.arrRecords,1)
        if tData then
            table.insert(arrSend,tData)
        end
    end

    if #arrSend>0 then
        local sUrl = sDomainName..cjson.encode(arrSend)
        tBase.Log("DemoPetternRecord.PackDataToSend nCnt_%d",#arrSend)
        DemoPetternRecord.SendToWeb(sUrl)
    end

    if nLen>nMaxCnt then
        --超过nMaxCnt条数据,间隔一段时间再发
        tBase.SetTimer(60110,1000*6,1,DemoPetternRecord.PackDataToSend)
    end
end

--发送到web服
function DemoPetternRecord.SendToWeb(sUrl)
    tBase.LogT("GetNotMaintainAllKey DemoPetternRecord")
    local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
    if #arrServerKey==0 then
        tBase.Log("ERROR  SendToWeb  %d ",#arrServerKey)
        return false
    end
    DemoPetternRecord.nReqTime = os.time()

    local dex =DemoPetternRecord.nReqWebCount%(#arrServerKey) +1
    local sChooseKey =arrServerKey[dex]
    DemoPetternRecord.nReqWebCount =DemoPetternRecord.nReqWebCount +1
    local Send = ProtoMgr.Web_pb.WebUrlReq()  
    Send.sUrl = sUrl
    Send.sSerialNum =string.format("%d_%d",tSrvInfo.nServerId,DemoPetternRecord.nReqWebCount)
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUrlReq_CMD)
    tPacket:AddString(Send:SerializeToString())   
    tBase.PostToServer(sChooseKey, 0, tPacket:GetData(), tPacket:GetSize())
    return true
end

return DemoPetternRecord