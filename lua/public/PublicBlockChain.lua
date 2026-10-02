--[[
	 直播区块链 相应接口
-- ]]

local tBase  = require("base")         -- 基础功能接口
local api    = require("publicApi")    -- 共用功能接口 
local cjson     = require("cjson")        -- json 
local tPublicRedis =require("PublicRedis") -- Redis 公共接口 
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local tname = require("typename") -- 类弄定义接口
local tSrvInfo = require("ServerInfo")
local logger = require("logger")      -- 日志对象
local WebCMD = ProtoMgr.Web_pb.Web_Sys()

local arrSendMsg = {}

PublicBlockChain = {}


--数据源 (不要变，游戏中也有同样的定义)
local SrcType={
    Normal=1,       --后台数据源 
    Block=2,        --区块链数据源
    AG =3,          --AG数据源
    Pro=4,           --结果自生成(这里没用)
    JackLot=5,          --彩票 
}


local function _GetDomainName(nGameId,nSource)
    local nSource =nSource or SrcType.Block
    if nSource ==SrcType.Normal then    --后台数据源          
        return tPublicRedis._GetMySourceDomainName() or "http://192.168.0.215:82/" 
    end  
    if nSource ==SrcType.Block then     --区块链数据源--
        return tPublicRedis._GetBlockchainDomainName()  or "http://192.168.3.38/"
    end
    if nSource ==SrcType.JackLot then     -- 彩票地址
        return tPublicRedis._GetJackLotDomainName(nGameId)  or " 没有彩票地址配置 "
    end
end


-- API Game 对应关系
local function _GetAPIGameId(nGameId)
	if nGameId == 122 then 
		return 1    -- 百家乐
	elseif nGameId == 121 then 
		return 9    -- 鱼虾蟹
    elseif nGameId == 153 then
        return 10   --直播色碟
    elseif nGameId == 155 then 
		return 7    -- 骰宝
	elseif nGameId==139 then --龙虎
        return 11
    elseif nGameId==143 then --直播牛牛
        return 12
    elseif nGameId==306 then --香港彩
        return 20
    else
		return nGameId
	end 
end

-- code 错误码:  10000->系统发生错误 , 10001->IP未授权 , 10002->系统维护中 , 10003->用户登录失效 
-- 10004->DES解密失败 , 10005->参数错误 , 10006->无效的厂商编码 , 10007->无权限访问
-- 10008--> 不存在的局号 

local nReqWebCount =1
local arrUrlReqWebKey = {}
local function SendToWebServer(sUrl)
    local sChooseKey 
    if arrUrlReqWebKey[sUrl] and arrUrlReqWebKey[sUrl].sKey then  
        sChooseKey = arrUrlReqWebKey[sUrl].sKey
        -- tBase.Log("_SendToWebServer sUrl: %s sChooseKey1_%s",sUrl,sChooseKey)    
    else
        local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
        if #arrServerKey==0 then
            tBase.Log("_SendToWebServer  arrServerKey: %d ",#arrServerKey)
            return false,"no web server"
        end
        local dex =nReqWebCount%(#arrServerKey) +1
        sChooseKey = arrServerKey[dex]  
        -- tBase.Log("_SendToWebServer sUrl: %s  dex_%d nReqWebCount_%d sChooseKey_%s #arrServerKey_%d",sUrl,dex,nReqWebCount,sChooseKey,#arrServerKey)   
    end 
    local sSerialNum = string.format("%d_%d",tSrvInfo.nServerId,nReqWebCount)
    local Send = ProtoMgr.Web_pb.WebUrlReq()
    Send.sUrl = sUrl
    Send.sSerialNum = sSerialNum
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUrlReq_CMD)
    tPacket:AddString(Send:SerializeToString())   
    tBase.PostToServer(sChooseKey, 0, tPacket:GetData(), tPacket:GetSize()) 
    -- tBase.Log("_SendToWebServer sSerialNum: %s sUrl: %s sChooseKey_%s",sSerialNum,sUrl,sChooseKey)

    local function _CheckKeyTimeOut(sUrl,sChooseKey)
        local arrDel = {}
        for ssUrl,tData in pairs(arrUrlReqWebKey) do
            local nTime = tBase.GetCountDTime() - tData.nRequetTIme 
            if nTime > 30 then 
                table.insert(arrDel,ssUrl)
            end  
        end
        if not arrUrlReqWebKey[sUrl] or not arrUrlReqWebKey[sUrl].sKey then  
            arrUrlReqWebKey[sUrl] ={nRequetTIme=tBase.GetCountDTime(),sKey = sChooseKey}
        end
        for k,sUrl in pairs(arrDel) do
            arrUrlReqWebKey[sUrl] = nil  
        end
        nReqWebCount =nReqWebCount + 1
        return false
    end  
    _CheckKeyTimeOut(sUrl,sChooseKey)
    return true
end

local function SendToWebServer_v2(sUrl,nUserId)
    local sChooseKey 
    if arrUrlReqWebKey[sUrl] and arrUrlReqWebKey[sUrl].sKey then  
        sChooseKey = arrUrlReqWebKey[sUrl].sKey
        tBase.Log("_SendToWebServer sUrl: %s sChooseKey1_%s",sUrl,sChooseKey)    
    else
        local arrServerKey = tPublicRedis.GetNotMaintainAllKey(tname.web) or {}
        if #arrServerKey==0 then
            tBase.Log("_SendToWebServer  arrServerKey: %d ",#arrServerKey)
            return false,"no web server"
        end
        local dex =nUserId%(#arrServerKey) +1
        sChooseKey = arrServerKey[dex]  
        -- tBase.Log("_SendToWebServer sUrl: %s  dex_%d nUserId_%d sChooseKey_%s #arrServerKey_%d",sUrl,dex,nUserId,sChooseKey,#arrServerKey)   
    end 
    local sSerialNum = string.format("%d_%d",tSrvInfo.nServerId,nUserId)
    local Send = ProtoMgr.Web_pb.WebUrlReqAndReturn() 
    Send.sUrl = sUrl
    Send.sSerialNum = sSerialNum
    Send.nUserId = nUserId
    local tPacket = tBase.GetSP().new(WebCMD.Main_CMD, WebCMD.WebUrlReqAndReturn_CMD)
    tPacket:AddString(Send:SerializeToString())   
    tBase.PostToServer(sChooseKey, 0, tPacket:GetData(), tPacket:GetSize()) 
    -- tBase.Log("_SendToWebServer sSerialNum: %s sUrl: %s sChooseKey_%s",sSerialNum,sUrl,sChooseKey)

    local function _CheckKeyTimeOut(sUrl,sChooseKey)
        local arrDel = {}
        for ssUrl,tData in pairs(arrUrlReqWebKey) do
            local nTime = tBase.GetCountDTime() - tData.nRequetTIme 
            if nTime > 30 then 
                table.insert(arrDel,ssUrl)
            end  
        end
        if not arrUrlReqWebKey[sUrl] or not arrUrlReqWebKey[sUrl].sKey then  
            arrUrlReqWebKey[sUrl] ={nRequetTIme=tBase.GetCountDTime(),sKey = sChooseKey}
        end
        for k,sUrl in pairs(arrDel) do
            arrUrlReqWebKey[sUrl] = nil  
        end
        -- nReqWebCount =nReqWebCount + 1
        return false
    end  
    _CheckKeyTimeOut(sUrl,sChooseKey)
    return true
end

local function TryGetContent(sUrl)
    local tRedis = tBase.m_MyRedisData[1].redis 
    local sKey ="HttpResult:"..sUrl
    --先从redis中读取结果
    local json_data =tRedis:get(sKey)
    --redis中没有,再发送请求到web服
    if json_data==nil then
        SendToWebServer(sUrl)  
        return nil
    end
    --tRedis:del(sKey)
    return json_data
end

--公共接口
function PublicBlockChain.GetContent(sUrl,nUserId)
    SendToWebServer_v2(sUrl,nUserId)
    return 1
end

-- 发送消息到tg群
local function SendMsgToTG(sErr,sUrl,nErrCode)
    local function func() 
        if sErr then
            if type(sErr)=="table" then
                sErr = cjson.encode(sErr)
            end
            local isSend = true
            local nNowTime = os.time()
            if #arrSendMsg>0 then
                for i=#arrSendMsg,1,-1 do
                    local data = arrSendMsg[i]
                    if data then
                        if nNowTime-data.nTime > 60 * 10 then
                            --超过一段时间的消息删除
                            table.remove(arrSendMsg,i)
                        else
                            if data.sMsg == sErr then
                                --短时间内相同的消息不发
                                isSend = false
                            end
                        end
                    end
                end
            end        
            if isSend then
                table.insert(arrSendMsg,{sMsg=sErr,nTime=nNowTime})
                local SendSMS = sErr
                if sUrl then
                    local nErrCode =nErrCode or -1
                    SendSMS = SendSMS.." sUrl:"..tostring(sUrl).." nErrCode: "..nErrCode
                end
                tBase._OnMonitorInfo(SendSMS,tSrvInfo.nServerId) 
            end
        end
    end 
    xpcall(func,tpLog)  
end

-- nSource: 1:区块链，2:MySource,3:其他
function PublicBlockChain.GetTableList(nGameId,nSource)
    local nSource =nSource or SrcType.Block
    local nThirdPartyGameId =_GetAPIGameId(nGameId)
    local sDomainName = _GetDomainName(nGameId,nSource)
    local sUrl =string.format("%stable/list?gameId=%d",sDomainName,nThirdPartyGameId) 
    local json_data =TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        return nil,"may be http problem"
    end
    local isSuccee,Rlt =pcall(cjson.decode,json_data)
	if not isSuccee then
        local sErr = "decode failed, sUrl:"..sUrl..', json_data:'..json_data
        SendMsgToTG(sErr)
		return nil,Rlt..json_data
    end 
    return Rlt
end

local function CheckJsonData(json_data)
    local isSuccee,Rlt =pcall(cjson.decode,json_data)
    if not isSuccee then
        tBase.Log("CheckJsonData json decode fail  "..(json_data or "-1"))
        if type(Rlt) == "string" then 
            logger:error(Rlt)
        else
            tBase.LogT(Rlt) 
        end
        return nil,Rlt
    end 
    if Rlt.code and Rlt.error then
       return nil,json_data,Rlt.code
    end   
    return Rlt
end 

-- nSource: 1:区块链，2:MySource,3:其他
function PublicBlockChain.GetTableScene(nGameId,nThirdPartyTableId,nSource)
    local nSource =nSource or SrcType.Block
    local nThirdPartyGameId =_GetAPIGameId(nGameId)
    local sDomainName = _GetDomainName(nGameId,nSource)
    local sUrl =string.format("%stable/scene?gameId=%d&tableId=%d",sDomainName,nThirdPartyGameId,nThirdPartyTableId)  
    local json_data = TryGetContent(sUrl)    
    if json_data ==nil or json_data=="" then 
        return nil,"may be http problem sUrl: "..string.format("gameId=%d&tableId=%d",nThirdPartyGameId,nThirdPartyTableId)
    end
    local Rlt,sErr = CheckJsonData(json_data)
    SendMsgToTG(sErr,sUrl)
    return Rlt,sErr
end

function PublicBlockChain.GetResult(sThirdPartyPaiJuId,nGameId,nSource)
    local nSource =nSource or SrcType.Block
    local sDomainName = _GetDomainName(nGameId,nSource)
    local sUrl =string.format("%stable/res?number=%s",sDomainName,sThirdPartyPaiJuId) 
    local json_data = TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        return nil,"may be http problem  sUrl: "..string.format("number=%s",sThirdPartyPaiJuId)
    end
    local Rlt,sErr,nErrCode = CheckJsonData(json_data)
    if nErrCode~=10005 then
        SendMsgToTG(sErr,sUrl,nErrCode)  
    end
    return Rlt,sErr
end

function PublicBlockChain.GetCardsBatch(nGameId,nThirdPartyTableId,nBootsno,nSource)
    local nSource =nSource or SrcType.Block
    local nThirdPartyGameId =_GetAPIGameId(nGameId)
    local sDomainName = _GetDomainName(nGameId,nSource)
    local sUrl =string.format("%scards/batch?gameId=%d&tableId=%d&bootsno=%d",sDomainName,nThirdPartyGameId,nThirdPartyTableId,nBootsno)
    tBase.Log(sUrl)
    local json_data = TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        return nil,"may be http problem sUrl: "..string.format("gameId=%d&tableId=%d&bootsno=%d",nThirdPartyGameId,nThirdPartyTableId,nBootsno)
    end
    local Rlt,sErr = CheckJsonData(json_data)
    SendMsgToTG(sErr,sUrl)
    return Rlt,sErr
end

-- 区块链告警  :  nType： 1:故障中,2:恢复正常
function PublicBlockChain._BlockChainGiveAnAlarm(sTableId,nType,sData)
    function tpLog(e)
        local kl = base.GetKernel()
        local km = km_FD55292F51334A64AC61470D796F8D43.new(kl)
        km:Log(e)
        km:Log(debug.traceback())
        return e
    end
    sData = sData or ""
    local function func()
        local tRedis = tBase.m_MyRedisData[2].redis 
        local sKey = "APIOpenTale_"..sTableId
        local tTable = tRedis:hgetall(sKey)
        if tTable and tTable.sTableId then
            local sSend =  "区块链告警: "
            if nType == 1 then 
                sSend=sSend.."故障中"
            elseif nType == 2 then 
                sSend=sSend.."恢复正常"
            end   
            local t =api.string_split(sTableId,"#")
            sSend = string.format("%s nServerId: %d,sTableId: %s,nGameId: %d,sTableName: %s,sPaiJuId: %s,nThirdPartyTableId: %d,nGroupId:%d"
            ,sSend,t[1],t[2],tTable.nGameId,tTable.sTableName,tTable.sPaiJuId,tTable.nThirdPartyTableId,tTable.nGroupId) 
            
            sSend = sSend.." "..sData or ""
            tBase.Log("_BlockChainGiveAnAlarm  sSend: %s ",sSend)
            tBase._OnMonitorInfo(sSend,tSrvInfo.nServerId)
        else
            tBase.Log("_BlockChainGiveAnAlarm  sTableId: %s is nil",sTableId)        
        end 
    end 
    xpcall(func,tpLog)  
end 

-- 获取 MySource 历史记录（最近20条）
function PublicBlockChain.GetMySourceRecord(nGameId,nSource)
    if not nSource or nSource == 1 then return end 
    local nThirdPartyGameId =_GetAPIGameId(nGameId)
    local sDomainName = _GetDomainName(nGameId,nSource)
    local sUrl =string.format("%stable/histors?gameId=%d",sDomainName,nThirdPartyGameId)
    tBase.Log(sUrl)
    local json_data = TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        return nil,"may be http problem sUrl: "..string.format("%stable/histors?gameId=%d",sDomainName,nThirdPartyGameId)
    end
    local Rlt,sErr = CheckJsonData(json_data)
    SendMsgToTG(sErr,sUrl)
    return Rlt,sErr
end
 
-- 数据库时间转换为   秒数 :   格式必须是这样  "2018-11-01 11:47:36"
local function _GetDateTime(timeString)  
    local Y = string.sub(timeString , 1, 4)  
    local M = string.sub(timeString , 6, 7)  
    local D = string.sub(timeString , 9, 10)  
    local h = string.sub(timeString , 12,13)  
    local m = string.sub(timeString , 15,16)  
    local s = string.sub(timeString , 18,19) 
    local tRet = {year=Y, month=M, day=D, hour=h,min=m,sec=s} 
    return  tRet   
end  

-- 以下是夺宝彩票


-- 历史记录

-- 获取某天的历史记录
local function _GetJackLot_Date_Record_Url(nGameId,date) 
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
    ]]
    local sDomainName = ""
    local sUrl= ""
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩由内部后台提供 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId) 
        sDomainName =sDomainName or  "http://154.204.32.100:82"   
        sUrl =string.format("%s/api/GetDrawResults?GameID=%d",sDomainName,nGameId) 
 
    elseif nGameId >= 310 and nGameId <= 316 then   -- 澳洲六合彩 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId) 
        sDomainName = sDomainName or "http://lotterycenterapi.rytest.com"   -- 测试 

        -- gameId:  310欧洲六合彩、 311芬兰六合彩、 312极速六合彩、313幸运球、314区块链幸运球、315区块链极速六合、316 俄罗斯六合彩
          --[[ RY 提供数据
            1  欧洲彩       europe/last 
            3  芬兰六合彩 finland/last
            25  极速乐透6 rapidlotto6/last   
            26  幸运球       luckball/last
            30  俄罗斯六合彩  russia/last
            历史接口：/hf/page
            参数：(int id, int index, int size, DateTime? date)
                https://lotterycenterapi.rytest.com/hf/page?id=1&index=1&size=100

            7  区块链幸运球 lottery/xyq/last
            8  区块链极速六合 lottery/jslh/last

            历史接口：/blocklottery/histroylist 
            参数：(int id, int index, int size, DateTime? date)
                https://lotterycenterapi.rytest.com/blocklottery/histroylist?id=7&index=1&size=100
        ]]
        local nCount = 1000
        local nRyid =0
        local sApi = "hf/page"
        if nGameId == 310 then     -- 欧洲六合彩
            nRyid=1 
        elseif nGameId == 311 then -- 芬兰六合彩
            nRyid=3
        elseif nGameId == 312 then  -- 极速六合彩 
            nCount = 1500
            nRyid=25 
        -- elseif nGameId == 313 then  -- 幸运球 （不做了）
        --     sType="luckball"
        elseif nGameId == 314 then  -- 区块链幸运球
            nRyid=7 
            sApi = "lottery/histroy"
        elseif nGameId == 315 then  -- 区块链极速六合
            -- https://lotterycenterapi.rytest.com/lottery/histroy?id=7&index=1&size=100&date=2024-08-06
            nRyid=8 
            sApi = "lottery/histroy"
        elseif nGameId == 316 then  -- 俄罗斯六合彩  
            nRyid=30 
        end 
        -- https://lotterycenterapi.rytest.com/hf/page?id=1&index=1&size=1000&date=2024-08-06
        sUrl =string.format("%s/%s?id=%d&index=1&size=%d&date=%s",sDomainName,sApi,nRyid,nCount)  
    end 
    return sUrl
end 

-- 获取 彩种历史 url：(最近100期)
local function _GetJackLotRecord_Url(nGameId) 
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
    ]]
    local sDomainName = ""
    local sUrl= ""
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩由内部后台提供 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId)         
        if not sDomainName then 
            local sErr = "_GetJackLotRecord_Url   No Url Config nGameId:"..nGameId 
            SendMsgToTG(sErr)
            return nil 
        end   
        sUrl =string.format("%s/api/GetDrawResults?GameID=%d",sDomainName,nGameId) 
 
    elseif nGameId >= 310 and nGameId <= 316 then   -- 澳洲六合彩 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId) 
        if not sDomainName then 
            local sErr = "_GetJackLotRecord_Url   No Url Config nGameId:"..nGameId 
            SendMsgToTG(sErr)
            return nil 
        end  

        -- gameId:  310欧洲六合彩、 311芬兰六合彩、 312极速六合彩、313幸运球、314区块链幸运球、315区块链极速六合、316 俄罗斯六合彩
          --[[ RY 提供数据
            1  欧洲彩       europe/last 
            3  芬兰六合彩 finland/last
            25  极速乐透6 rapidlotto6/last   
            26  幸运球       luckball/last
            30  俄罗斯六合彩  russia/last
            历史接口：/hf/page
            参数：(int id, int index, int size, DateTime? date)
                https://lotterycenterapi.rytest.com/hf/page?id=1&index=1&size=100

            7  区块链幸运球 lottery/xyq/last
            8  区块链极速六合 lottery/jslh/last

            历史接口：/blocklottery/histroylist 
            参数：(int id, int index, int size, DateTime? date)
                https://lotterycenterapi.rytest.com/blocklottery/histroylist?id=7&index=1&size=100
        ]]
        local nRyid =0
        local sApi = "hf/page"
        if nGameId == 310 then     -- 欧洲六合彩
            nRyid=1 
        elseif nGameId == 311 then -- 芬兰六合彩
            nRyid=3
        elseif nGameId == 312 then  -- 极速六合彩 
            nRyid=25 
        -- elseif nGameId == 313 then  -- 幸运球 （不做了）
        --     sType="luckball"
        elseif nGameId == 314 then  -- 区块链幸运球
            nRyid=7 
            sApi = "lottery/histroy"
        elseif nGameId == 315 then  -- 区块链极速六合
            -- https://lotterycenterapi.rytest.com/lottery/histroy?id=8&index=1&size=100
            nRyid=8 
            sApi = "lottery/histroy"
        elseif nGameId == 316 then  -- 俄罗斯六合彩  
            nRyid=30 
        end 
        local nCount = 500
        sUrl =string.format("%s/%s?id=%d&index=1&size=%d",sDomainName,sApi,nRyid,nCount)  
    end 
    return sUrl
end 

-- 获取 彩种历史记录： period 第三方期数 
local function _GetJackLot_Record(nGameId,Rlt,period) 
    if period then 
        period=tostring(period)
    end 
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
        310欧洲六合彩、 311芬兰六合彩、 312极速六合彩、313幸运球、314区块链幸运球、315区块链极速六合、316俄罗斯六合彩
    ]]
    local tRlt={} 
    tRlt.nIssue = nil       --期号
    tRlt.arrResult =nil     --结果：  
    local arrRecord = {} 
    local arrIssueId = {}
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩          
        local code = tonumber(Rlt.code)  
        if code ~= 1 then 
            tBase.Log("_GetJackLotResult  有问题  Rlt: %s ",cjson.encode(Rlt))
            return nil 
        end 
 
        -- 上期 
        local tPrior = {} 
        tPrior.nIssue = Rlt.issue                 --期号 
        local arrResult = publicApi.string_split(Rlt.number, ",") 
        tPrior.arrResult ={}
        for _, v in pairs(arrResult) do
            table.insert(tPrior.arrResult,tonumber(v))
        end  
        table.insert(arrRecord,tPrior)
        table.insert(arrIssueId,tPrior.nIssue)  

        for _, tRecord in pairs(Rlt.hResult) do 
            local t ={}
            t.nIssue = tRecord.issue  --期号          
            local arrResult = publicApi.string_split(tRecord.openCode, ",") 
            t.arrResult ={}
            for _, v in pairs(arrResult) do
                table.insert(t.arrResult,tonumber(v))
            end 
            table.insert(arrRecord,t)
            table.insert(arrIssueId,t.nIssue)   
        end   
 
    elseif nGameId >= 310 and nGameId <= 316 then  
        local code = tonumber(Rlt.code)  
        if code then 
            tBase.Log("_GetJackLotRecord  有问题 nGameId_%d Rlt: %s ",nGameId,cjson.encode(Rlt))
            return nil 
        end  
        local data = Rlt.data   
        for _, v in pairs(data) do
            --  "createTime":"2024-08-06 16:50:05","jackpot":0,"secondSpan":0,"lottoId":25,"remaining":0,"state":0,
            --  "drawTimeLocal":"2024-08-06 09:50:00","drawDateLocal":"2024-08-06 00:00:00","drawDate":"2024-08-06 00:00:00",
            --  "period":118,"id":4315344,"remark":null,"openNumbers":"31,45,46,17,03,32,30","drawTime":"2024-08-06 09:50:00"}

            local tRecord = {}
            tRecord.nIssue = v.period   
            tRecord.createTime = v.createTime 
            tRecord.arrResult ={}
            local openNumbers = v.openNumbers     -- 结果
            local arrResult = publicApi.string_split(openNumbers, ",") 
            for _, id in pairs(arrResult) do 
                table.insert(tRecord.arrResult,tonumber(id)) 
            end   
            table.insert(arrRecord,tRecord)   
            table.insert(arrIssueId,tRecord.nIssue)             
        end 
    else
        tBase.Log("_GetJackLot_Record    nGameId_%d is nil  ",nGameId)
        return nil 
    end 
    if not period then 
        return arrRecord
    end  
    for _, tRecord in ipairs(arrRecord) do 
        if tonumber(tRecord.nIssue) == tonumber(period) then    
            tRlt.nIssue = _GetJackLotIssue(nGameId,tRecord.nIssue,tRecord.createTime or "")  
            tRlt.arrResult = tRecord.arrResult
            return tRlt 
        end 
    end
    if #arrRecord > 0 then  
        tBase.Log("_GetJackLot_Record  tRlt.nIssue is nil  nGameId_%d period: %s  arrIssueId: %s   ",nGameId,period,cjson.encode(arrIssueId))
        return nil 
    end 
    return nil 
end 

-- 获取彩票 某期结果参数:period(第三方期数
-- 返回参数: {nIssue,arrResult} 、无期号则返回最近5记录(香港彩、澳门彩、新澳门彩)其他彩种 100条
function PublicBlockChain.GetJackLotHistoryResult(nGameId,period)
    local sUrl =_GetJackLotRecord_Url(nGameId)
    if not sUrl then 
        tBase.Log("_GetJackLotHistoryResult    nGameId_%d sUrl: %s is nil ",nGameId,sUrl or "")
        return nil,"_GetJackLotHistoryResult may be http problem"
    end  
    -- tBase.Log("_GetJackLotHistoryResult    nGameId_%d sUrl: %s  ",nGameId,sUrl or "")
    local json_data =TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        tBase.Log("_GetJackLotHistoryResult    nGameId_%d sUrl: %s  json_data is nil ",nGameId,sUrl or "")
        return nil,"_GetJackLotHistoryResult may be http problem"
    end
    local isSuccee,Rlt =pcall(cjson.decode,json_data)
	if not isSuccee then
        local sErr = "_GetJackLotHistoryResult  decode failed, sUrl:"..sUrl..', json_data:'..json_data
        SendMsgToTG(sErr)
		return nil,Rlt..json_data
    end 
    local tRlt = _GetJackLot_Record(nGameId,Rlt,period)
    if not tRlt then  
        tBase.Log("_GetJackLotHistoryResult     nGameId_%d period: %s  tRlt is nil  ",nGameId,period )
        return nil 
    end 
    return tRlt
end 


-- 彩种期号:  nextAwardTime(2024-08-14 15:15:00)
local function _GetJackLotIssue(nGameId,period,nextAwardTime)
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩     
        return period
    end 
    local sDateTime = os.date("%Y%m%d")

    -- nextAwardTime = "2024-08-15 15:15:00"

    local tOpenAward = _GetDateTime(nextAwardTime)  -- 开奖时间 
    local sOpenDateTime = string.format("%s%s",tOpenAward.month,tOpenAward.day)
    -- 以下是RY 

    if nGameId == 310 then     -- 欧洲六合彩 
        -- UTC+8 每天白天从中午13:05 开到凌晨03:00，每5分钟开一次奖, 每天开奖168期。 
        -- 期号格式：月日+期号=0806001期
        sDateTime = os.date("%Y%m%d")

    elseif nGameId == 311 then -- 芬兰六合彩
        --每天20:00开奖 
        -- 期号格式：年份+期号=2024001期
        sDateTime = os.date("%Y")
        sOpenDateTime = string.format("%s",tOpenAward.year)

    elseif nGameId == 312 then  -- 极速六合彩 
        --开始时间：UTC+8 每天上午07:00 开到第二天上午07:00，每5分钟开一次奖，每天开奖288期。
        -- 期号格式：月日+期号=0806001期
        sDateTime = os.date("%Y%m%d") 

    elseif nGameId == 314 then  -- 区块链幸运球 
        --UTC+8 每天凌晨 00:00 开到晚上 24:00，每10分钟开一次奖，每天开奖共计144期。
        -- UTC+8 每天凌晨 00:00 便生成当天所有号码，对每个号码加密并公开显示
        -- 期号格式：月日+期号=0806001期
        sDateTime = os.date("%Y%m%d") 

    elseif nGameId == 315 then  -- 区块链极速六合
        --开始时间：UTC+8 每天凌晨 00:00 开到晚上 24:00，每5分钟开一次奖，每天开奖共计288期。
        --UTC+8 每天凌晨 00:00 便生成当天所有号码，对每个号码加密并公开显示
        -- 期号格式：月日+期号=0806001期
        sDateTime = os.date("%Y%m%d") 

    elseif nGameId == 316 then  -- 俄罗斯六合彩  
        -- 每天晚上20:00分开奖
        -- 期号格式：年份+期号=2024001期
        sDateTime = os.date("%Y")
        sOpenDateTime = string.format("%s",tOpenAward.year)
    end       
    if sDateTime ~= sOpenDateTime then 
        sDateTime = sOpenDateTime
    end 
    period = math.floor(period)
    local str =string.format("%d",period)
    if #str < 3 then 
        local nLen = 3- #str 
        for i = 1, nLen, 1 do
            str = string.format("0%s",str)            
        end
    end 
    local sIssue =  string.format("%s%s",sDateTime,str)
    return sIssue
end

-- 获取当前期信息 url： nGameId: 
local function _GetNowPeriodInfo_Url(nGameId) 
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
    ]]
    local sDomainName = ""
    local sUrl= ""
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩由内部后台提供 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId) 
        sDomainName =sDomainName or  "http://154.204.32.100:82"   
        sUrl =string.format("%s/api/GetDrawResults?GameID=%d",sDomainName,nGameId) 
 
    elseif nGameId >= 310 and nGameId <= 316 then   -- 澳洲六合彩 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId) 
        sDomainName = sDomainName or "http://lotterycenterapi.rytest.com"   -- 测试 

        -- gameId:  310欧洲六合彩、 311芬兰六合彩、 312极速六合彩、313幸运球、314区块链幸运球、315区块链极速六合、316 俄罗斯六合彩
          --[[ RY 提供数据
            1  欧洲彩       europe/last 
            3  芬兰六合彩 finland/last
            25  极速乐透6 rapidlotto6/last   
            26  幸运球       luckball/last
            30  俄罗斯六合彩  russia/last
            历史接口：/hf/page
            参数：(int id, int index, int size, DateTime? date)

            7  区块链幸运球 lottery/xyq/last
            8  区块链极速六合 lottery/jslh/last

            历史接口：/blocklottery/histroylist 
            参数：(int id, int index, int size, DateTime? date)
        ]]
        local sType = ""
        if nGameId == 310 then     -- 欧洲六合彩
            sType="europe"
        elseif nGameId == 311 then -- 芬兰六合彩
            sType="finland"
        elseif nGameId == 312 then  -- 极速六合彩 
            sType="rapidlotto6"
        -- elseif nGameId == 313 then  -- 幸运球 （不做了）
        --     sType="luckball"
        elseif nGameId == 314 then  -- 区块链幸运球
            sType="lottery/xyq"
        elseif nGameId == 315 then  -- 区块链极速六合
            sType="lottery/jslh"
        elseif nGameId == 316 then  -- 俄罗斯六合彩  
            sType="russia"
        end 
        sUrl =string.format("%s/%s/last",sDomainName,sType) 
    end  
    return sUrl
end 

-- 获取当前期信息 结果
local function _GetNowPeriodInfo_Result(nGameId,Rlt,sUrl)
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
        310欧洲六合彩、 311芬兰六合彩、 312极速六合彩、313幸运球、314区块链幸运球、315区块链极速六合、316俄罗斯六合彩
    ]]
    local tRlt={}
    tRlt.period = nil       -- 获取结果期数 
    -- 上期 
    tRlt.nIssue = nil       --期号
    tRlt.arrResult =nil     --结果：  
    -- 当前期  
    tRlt.nStartSt =nil      --开始时间戳 
    tRlt.nOpenSt =nil       --开奖时间戳
    tRlt.nNextSt =nil       --当前期的下一期 开始时间戳
    tRlt.drawTime =""       -- 第三方开奖日期

    tRlt.arrRecord =nil     -- 历史记录  

    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩          
        local code = tonumber(Rlt.code)  
        if code ~= 1 then 
            tBase.Log("_GetNowPeriodInfo_Result  有问题  Rlt: %s ",cjson.encode(Rlt))
            return nil 
        end 

        -- 上期 
        tRlt.nIssue = tonumber(Rlt.issue)                 --期号
        tRlt.nOpenSt = tonumber(Rlt.open_time)            --开奖时间戳
        local arrResult = publicApi.string_split(Rlt.number, ",") 
        tRlt.arrResult ={}
        for _, v in pairs(arrResult) do
            table.insert(tRlt.arrResult,tonumber(v))
        end  

        -- 当前期 
        tRlt.nIssue = tonumber(Rlt.issue) + 1         --期号
        tRlt.nStartSt =tRlt.nOpenSt+1                 --当前期开始时间戳  
        tRlt.nOpenSt = tonumber(Rlt.next_open_time)   --当前期开奖时间戳 
        tRlt.nNextSt = tonumber(Rlt.next_open_time)  +1     --  下一期 开始时间戳 
        tRlt.period =  tRlt.nIssue
        local arrRecord = {}
        for _, tRecord in pairs(Rlt.hResult) do 
            local t ={}
            t.nIssue = tonumber(tRecord.issue)  --期号
            t.nOpenSt = tonumber(tRecord.openTime)       --开奖时间戳            
            local arrResult = publicApi.string_split(tRecord.openCode, ",") 
            t.arrResult ={}
            for _, v in pairs(arrResult) do
                table.insert(t.arrResult,tonumber(v))
            end 
            table.insert(arrRecord,t)
        end 
        tRlt.arrRecord = arrRecord

    elseif nGameId >= 310 and nGameId <= 316 then 
      
        local code = tonumber(Rlt.code)  
        if code then 
            tBase.Log("_GetNowPeriodInfo_Result  有问题 nGameId_%d Rlt: %s ",nGameId,cjson.encode(Rlt))
            return nil 
        end 
        -- tBase.Log("_GetNowPeriodInfo_Result  111 有问题 nGameId_%d Rlt: %s ",nGameId,cjson.encode(Rlt))
        -- {"drawTime":"2024-08-04 14:00:00","period":217,"openNumbers":"21,35,17,23,22,38,43",
        -- "nextLotteryNo":"2024218","nextPeriod":218,"nextAwardTime":"2024-08-05 20:00:00","countDown":6142}
        if not Rlt.awardTime then 
            tBase.Log("_GetNowPeriodInfo_Result  Rlt.awardTime  is nil  nGameId_%d Rlt: %s sUrl: %s",nGameId,cjson.encode(Rlt),sUrl)
            return nil 
        end      
        -- 上期
        local period = tonumber(Rlt.period)                              -- 上一期期号  
        local drawTime = Rlt.drawDate
        if not drawTime then 
            tBase.Log("_GetNowPeriodInfo_Result  Rlt.drawTime  is nil  nGameId_%d Rlt: %s sUrl: %s",nGameId,cjson.encode(Rlt),sUrl)
            return nil 
        end    
        -- 311芬兰六合彩、316俄罗斯六合彩 跨天的
        if nGameId == 311 or nGameId == 316 then 
            drawTime = Rlt.nextAwardTime
        end 
        if drawTime and #drawTime > 10 then 
            drawTime = string.sub(drawTime,1,10) 
        end 
        local awardTime = publicApi.string2time(Rlt.awardTime)           -- 开奖时间 秒 
        local openNumbers = Rlt.openNumbers     -- 结果
        local arrResult = publicApi.string_split(openNumbers, ",") 
        tRlt.arrResult ={}
        for _, v in pairs(arrResult) do
            table.insert(tRlt.arrResult,tonumber(v))
        end  

        -- 当前期
        local nextPeriod = tonumber(Rlt.nextPeriod)                           -- 下一期期数   
        local nextLotteryNo = _GetJackLotIssue(nGameId,nextPeriod,Rlt.nextAwardTime)            -- 下一期期号  
        local nextAwardTime =publicApi.string2time(Rlt.nextAwardTime)         -- 下一期开奖时间 秒 
   

        -- 当前期 
        tRlt.period = nextPeriod
        tRlt.nIssue = nextLotteryNo                   --期号
        tRlt.nStartSt = awardTime                      --当前期开始时间戳  
        tRlt.nOpenSt = tonumber(nextAwardTime)        --当前期开奖时间戳 
        tRlt.nNextSt = tonumber(nextAwardTime)+1     --下一期 开始时间戳 
        tRlt.drawTime = drawTime                     -- 第三方开奖日期

        if nGameId == 310 then     -- 欧洲六合彩 
            -- UTC+8 每天白天从中午13:05 开到凌晨03:00，每5分钟开一次奖, 每天开奖168期。
            local nDiffTime = nextAwardTime - awardTime
            -- 间隔超过5分钟，隔天再开了
            if nDiffTime > 300 then 
                tRlt.nStartSt = nextAwardTime - 300           --当前期开始时间戳 
                tRlt.nOpenSt = tonumber(nextAwardTime)        --当前期开奖时间戳 
                tRlt.nNextSt = tonumber(nextAwardTime)+1      --下一期 开始时间戳 
            end  
        end  
    else
        tBase.Log("_GetNowPeriodInfo_Result  nGameId_%d is nil  ",nGameId)
        return nil 
    end 
    if not tRlt.nIssue then 
        return nil 
    end 
    tBase.Log("_GetNowPeriodInfo_Result   获取当前期数 nGameId_%d tRlt: %s sUrl: %s ",nGameId,cjson.encode(tRlt),sUrl)
    return tRlt
end 

-- 获取当前期信息:  {nIssue(期号)、nStartSt(当前局开始时间戳)、nOpenSt(当前局开奖时间戳)、nNextSt(当前局的下局开始时间戳)、period(第三方期数)}
function PublicBlockChain._GetJackLot_NowPeriodInfo(nGameId) 
    local sUrl = _GetNowPeriodInfo_Url(nGameId) 
    if not sUrl then 
        tBase.Log("_GetJackLot_NowPeriodInfo  nGameId_%d sUrl: %s is nil ",nGameId,sUrl or "")
        return nil,"_GetJackLot_NowPeriodInfo may be http problem"
    end   
    local json_data =TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        return nil,"_GetJackLot_NowPeriodInfo may be http problem"
    end
    local isSuccee,Rlt =pcall(cjson.decode,json_data)
	if not isSuccee then
        local sErr = "_GetJackLot_NowPeriodInfo  decode failed, sUrl:"..sUrl..', json_data:'..json_data
        SendMsgToTG(sErr)
		return nil,Rlt..json_data
    end 
    local tRlt = _GetNowPeriodInfo_Result(nGameId,Rlt,sUrl)
    return tRlt
end


-- 根据期号获取结果(日期) 地址
local function _GetJackLot_Date_Result_Url(nGameId,period,sOpenDate) 
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
    ]]
    local sDomainName = ""
    local sUrl= ""
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩由内部后台提供 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId)         
        if not sDomainName then 
            local sErr = "_GetJackLot_Date_Result_Url   No Url Config nGameId:"..nGameId 
            SendMsgToTG(sErr)
            return nil 
        end   
        sUrl =string.format("%s/api/GetDrawResults?GameID=%d",sDomainName,nGameId) 
 
    elseif nGameId >= 310 and nGameId <= 316 then   -- 澳洲六合彩 
        sDomainName = tPublicRedis._GetJackLotDomainName(nGameId) 
        if not sDomainName then 
            local sErr = "_GetJackLot_Date_Result_Url   No Url Config nGameId:"..nGameId 
            SendMsgToTG(sErr)
            return nil 
        end   
        local nRyid =0
        local sApi = "hf/drawinfo"
        if nGameId == 310 then     -- 欧洲六合彩
            nRyid=1 
        elseif nGameId == 311 then -- 芬兰六合彩
            nRyid=3
        elseif nGameId == 312 then  -- 极速六合彩 
            nRyid=25 
        -- elseif nGameId == 313 then  -- 幸运球 （不做了）
        --     sType="luckball"
        elseif nGameId == 314 then  -- 区块链幸运球
            nRyid=7  
            --  https://lotterycenterapi.rytest.com/blocklottery/drawinfo?id=7&date=2024-10-14&period=103
            sApi = "blocklottery/drawinfo"
        elseif nGameId == 315 then  -- 区块链极速六合 
            nRyid=8 
            --  https://lotterycenterapi.rytest.com/blocklottery/drawinfo?id=8&date=2024-10-14&period=103
            sApi = "blocklottery/drawinfo"
        elseif nGameId == 316 then  -- 俄罗斯六合彩  
            nRyid=30 
        end   
        -- 例子   https://lotterycenterapi.rytest.com/hf/drawinfo?id=1&date=2024-10-14&period=35
        sUrl =string.format("%s/%s?id=%d&date=%s&period=%d",sDomainName,sApi,nRyid,sOpenDate,period)  
    end 
    return sUrl
end 

-- 根据期号获取结果(日期) 地址
local function _GetJackLotResult(nGameId,Rlt,period,sDate) 
    if period then 
        period=tostring(period)
    end 
    --[[  gameId:    306 夺宝彩票： 
        307香港彩、308澳门彩、 309新澳门彩 
        310欧洲六合彩、 311芬兰六合彩、 312极速六合彩、313幸运球、314区块链幸运球、315区块链极速六合、316俄罗斯六合彩
    ]]
    local tRlt={} 
    tRlt.nIssue = nil       --期号
    tRlt.arrResult =nil     --结果：  
    local arrRecord = {} 
    local arrIssueId = {}
    if nGameId >= 307 and nGameId < 310 then   -- 香港彩、澳门彩、新澳门彩          
        local code = tonumber(Rlt.code)  
        if code ~= 1 then 
            tBase.Log("_GetJackLotResult  有问题  Rlt: %s ",cjson.encode(Rlt))
            return nil 
        end 
 
        -- 上期 
        local tPrior = {} 
        tPrior.nIssue = Rlt.issue                 --期号 
        local arrResult = publicApi.string_split(Rlt.number, ",") 
        tPrior.arrResult ={}
        for _, v in pairs(arrResult) do
            table.insert(tPrior.arrResult,tonumber(v))
        end  
        table.insert(arrRecord,tPrior)
        table.insert(arrIssueId,tPrior.nIssue)  
        for _, tRecord in pairs(Rlt.hResult) do 
            local t ={}
            t.nIssue = tRecord.issue  --期号          
            local arrResult = publicApi.string_split(tRecord.openCode, ",") 
            t.arrResult ={}
            for _, v in pairs(arrResult) do
                table.insert(t.arrResult,tonumber(v))
            end 
            table.insert(arrRecord,t)
            table.insert(arrIssueId,t.nIssue)   
        end   
 
    elseif nGameId >= 310 and nGameId <= 316 then  
        local code = tonumber(Rlt.code)  
        if code then 
            tBase.Log("_GetJackLotResult  有问题 nGameId_%d Rlt: %s ",nGameId,cjson.encode(Rlt))
            return nil 
        end  
        local data = Rlt.data   
        for _, v in pairs(data) do 
            local tRecord = {}
            tRecord.nIssue = v.period   
            tRecord.createTime = v.createTime 
            tRecord.arrResult ={}
            local openNumbers = v.openNumbers     -- 结果
            local arrResult = publicApi.string_split(openNumbers, ",") 
            for _, id in pairs(arrResult) do 
                table.insert(tRecord.arrResult,tonumber(id)) 
            end   
            table.insert(arrRecord,tRecord)   
            table.insert(arrIssueId,tRecord.nIssue)             
        end 
    else
        tBase.Log("_GetJackLotResult    nGameId_%d is nil  ",nGameId)
        return nil 
    end 
    if not period then 
        return arrRecord
    end  
    for _, tRecord in ipairs(arrRecord) do 
        if tonumber(tRecord.nIssue) == tonumber(period) then    
            tRlt.nIssue = _GetJackLotIssue(nGameId,tRecord.nIssue,tRecord.createTime or "")  
            tRlt.arrResult = tRecord.arrResult
            return tRlt 
        end 
    end
    if #arrRecord > 0 then  
        tBase.Log("_GetJackLotResult  tRlt.nIssue is nil  nGameId_%d period: %s  arrIssueId: %s   ",nGameId,period,cjson.encode(arrIssueId))
        return nil 
    end 
    return nil 
end 

function PublicBlockChain.GetJackLot_Redis_Result(nGameId,nIssue) 
    local arr= PublicRedis.GetJackLot_Redis_Result(nGameId,nIssue)
    if not arr or #arr == 0  then 
        return nil 
    end     
    local arrResult = {}
    for _, value in ipairs(arr) do
        table.insert(arrResult,tonumber(value))
    end
    local tRlt={} 
    tRlt.nIssue = nIssue          --期号
    tRlt.arrResult =arrResult     --结果：
    tBase.Log("_GetJackLot_Redis_Result 后台人工补录结果  nGameId: %d nIssue: %s tRlt: %s    ",nGameId,nIssue,cjson.encode(tRlt))
    return tRlt
end

-- 根据期号获取结果(日期) 地址
-- 返回参数: {nIssue,arrResult} 、无期号则返回最近5记录(香港彩、澳门彩、新澳门彩)其他彩种 100条
function PublicBlockChain.GetJackLot_Date_Result(nGameId,period,drawTime,nIssue)     
    local sUrl =_GetJackLot_Date_Result_Url(nGameId,period,drawTime)
    if not sUrl then 
        local tRlt1 = PublicBlockChain.GetJackLot_Redis_Result(nGameId,nIssue) 
        if tRlt1 then 
            return tRlt1 
        end 
        tBase.Log("GetJackLot_Date_Result    nGameId_%d sUrl: %s is nil ",nGameId,sUrl or "") 
        return 
    end   
    local json_data =TryGetContent(sUrl)
    if json_data ==nil or json_data=="" then 
        local tRlt1 = PublicBlockChain.GetJackLot_Redis_Result(nGameId,nIssue) 
        if tRlt1 then 
            return tRlt1 
        end 
        tBase.Log("GetJackLot_Date_Result   json_data is nil  nGameId_%d json_data: %s sUrl: %s  ",nGameId,cjson.encode(json_data or ""),sUrl) 
        return 
    end
    local isSuccee,Rlt =pcall(cjson.decode,json_data)
	if not isSuccee then
        local tRlt1 = PublicBlockChain.GetJackLot_Redis_Result(nGameId,nIssue) 
        if tRlt1 then 
            return tRlt1 
        end 
        tBase.Log("GetJackLot_Date_Result   json_data is nil  nGameId_%d json_data: %s sUrl: %s  ",nGameId,cjson.encode(json_data or ""),sUrl) 
        return nil 
    end 
    local tRlt = _GetJackLotResult(nGameId,Rlt,period) 
    if not tRlt or not tRlt.arrResult or #tRlt.arrResult == 0 then 
        local tRlt1 = PublicBlockChain.GetJackLot_Redis_Result(nGameId,nIssue) 
        if tRlt1 then 
            return tRlt1 
        end 
        tBase.Log("GetJackLot_Date_Result   arrResult is nil  nGameId_%d tRlt: %s sUrl: %s  ",nGameId,cjson.encode(tRlt),sUrl)  
        return nil  
    end
    return tRlt
end 


return PublicBlockChain
