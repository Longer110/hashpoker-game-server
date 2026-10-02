package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tBase 	  = require("base")         -- 基础功能接口
local tName       = require("typename")     -- 类弄定义接口
local tProtoMgr   = require("ProtoManager") 
local tPubUserInfo= require("PublicUserInfo") 
local tPublicApi  = require("publicApi")
local tPublicRedis = require("PublicRedis")
local tGoldRange = require("GoldRange") 
local cjson    = require("cjson")
local Quick = require("Quick")


AndroidIo = {
    nR = 1,
    nMax = 5000000,
    xmlcallbackfunc = {},
    xmlandroidmap = {}, --缓存的机器人信息,用于从游戏中返回的机器人数据是否正确 {[nUserId]=tAnItem,...}
    nLimit = 25, --每次请求的机器人数目
    tCachePool = {}, --可用缓存池 {[nUserId]=tAnItem,...}
    nTimerTime = 1000 * 60 * 1, -- 定时归还
    nLimitTime = 60 * 5, --限制5分钟
    tRecyclePool = {}, --回收池，发送回机器人服 {[nUserId]=tAnItem,...}
    tGrpGetCntByMin = {}, --过去一断时间内请求获取的机器人个数
    nStatisticsTime = 2*60, --统计时间
    tAndroidGetTime = {}, --借到机器人的时间点 {[nUserId]=os.time(),...}
    tAnServer = {}, --各个机器人服的状态
    nReqTimeLimt = 3, --向机器人服请求机器人的时间间隔(秒)
    tInGameAndroid = {}, --在游戏中的机器人 {[nUserId]={nUserId,nGrpId}}
    nLastReqTime = 0, --上次向机器人服请求的时间
    nLastCheckTime = os.time(), --上次向机器人服归还机器人的时间
    nMaxSpaceCheckTime = 60*10, --每次检测最大间隔时间，如果间隔了这么长没有进行过归还检测，就必须强制执行
    tRepeatAndroid = {}, --重复的机器人(不同服) {[nServerId]={[nUserId]=tItem,...},...}
}

--检查需要归还机器人服的机器人
function AndroidIo.CheckNeedComeback()
    local arrComeback = {}
    AndroidIo.nLastCheckTime = os.time()

    --检查不在游戏中，不在可用缓存池，不在回收池的机器人
    for k,v in pairs(AndroidIo.xmlandroidmap) do
        local nGrpId = v.nGrpId
        local nServerId = v.nServerId
        local nUserId = v.nUserId

        if not AndroidIo.tCachePool[nUserId] then
            if not AndroidIo.tRecyclePool[nUserId] then
                if not AndroidIo.tInGameAndroid[nUserId] then
                    tBase.Log("_CheckNeedComeback]机器人异常,不在可用缓存池,不在回收池,不在游戏中 nServerId:%d nGrpId:%d nUserId:%d",
                    nServerId,nGrpId,nUserId)
                    if not arrComeback[nServerId] then
                        arrComeback[nServerId] = {}
                    end
                    table.insert(arrComeback[nServerId],nUserId)
                end
            end
        end
    end

    --可用缓存池里面太久没用或者所属服已维护的机器人放入回收池
    local nNowTime = os.time()
    for _,nUserId in pairs(AndroidIo.tCachePool) do
        local tAnItem = AndroidIo.xmlandroidmap[nUserId]
        if tAnItem then
            local nGrpId = tAnItem.nGrpId
            local nGetTime = AndroidIo.tAndroidGetTime[nUserId] or 0
            local nDiff =  nNowTime - nGetTime
            local nServerId = tAnItem.nServerId
            local nServerState = (AndroidIo.tAnServer[nServerId] and AndroidIo.tAnServer[nServerId].nServerState) or 0
            if nDiff >= AndroidIo.nLimitTime or nServerState~=1 then
                AndroidIo.PushToRecyclePool(nUserId)
                AndroidIo.tCachePool[nUserId] = nil
            end
        else
            AndroidIo.tCachePool[nUserId] = nil
        end
    end

    --回收池的机器人全部返还机器人服
    for _,nUserId in pairs(AndroidIo.tRecyclePool) do
        local tAnItem = AndroidIo.xmlandroidmap[nUserId]
        if tAnItem then
            local nServerId = tAnItem.nServerId
            if not arrComeback[nServerId] then
                arrComeback[nServerId] = {}
            end
            local nRecycleUserId = nUserId
            table.insert(arrComeback[nServerId],nRecycleUserId)
        else
            AndroidIo.tRecyclePool[nUserId] = nil
        end
    end    
    AndroidIo.TotalTempNumber() 

    -- tBase.Log("_CheckNeedComeback      检查需要归还机器人服 11")
    local arrTempAndroid = {}
    for nServerId,arrAndroid in pairs(arrComeback) do
        arrTempAndroid = {}
        for i=1,#arrAndroid do
            local nUserId = arrAndroid[i]
            table.insert(arrTempAndroid,nUserId)
            if i%AndroidIo.nLimit==0 or i==#arrAndroid then
                AndroidIo.SetAndroidBackToAnServer(nServerId,arrTempAndroid)
                arrTempAndroid = {}
            end
        end
        tBase.Log("_CheckNeedComeback    arrAndroid_%d  归还机器人: %s ",#arrAndroid,cjson.encode(arrAndroid))
    end

    AndroidIo.SetBackRepeatAndroid()

    AndroidIo.CheckAndroidServer()

    AndroidIo.CheckOverTimeConfigForAnroid()

end 

--检查过期的机器人配置请求并删除
function AndroidIo.CheckOverTimeConfigForAnroid()
    local nAllReqNum = 0
    local nOverTimeNum = 0 
    local nInNum = 0 
    local nLostNum = 0 
    local arrId = {}
    for k, v in pairs(AndroidIo.xmlcallbackfunc) do
        nAllReqNum = nAllReqNum + 1
        if v then    
            if (os.time() - v.nReqTime) > 120 then --超过120秒就删除保存记录
                AndroidIo.xmlcallbackfunc[k] = nil
                nOverTimeNum = nOverTimeNum + 1 
                table.insert(arrId,k)
            else
                nInNum = nInNum + 1
                --tBase.Log("CheckOverTimeConfigForAnroid nInNum nR_%d",k)
            end 
        else
            nLostNum = nLostNum + 1
            --tBase.Log("CheckOverTimeConfigForAnroid nLostNum nR_%d",k)
        end
    end
    if nOverTimeNum > 0 or nLostNum > 0 then
        tBase.Log("_CheckOverTimeConfigForAnroid  nAllReqNum_%d nOverTimeNum_%d nInNum_%d nLostNum_%d arrId_%s "
        ,nAllReqNum,nOverTimeNum,nInNum,nLostNum,cjson.encode(arrId))
    end
end

--统计当前缓存
function AndroidIo.TotalTempNumber()
    --可用缓存池的机器人
    local arrCachePoolCnt = {}
    for _,nUserId in pairs(AndroidIo.tCachePool) do
        local tAnItem = AndroidIo.xmlandroidmap[nUserId]
        if tAnItem then
            local nServerId = tAnItem.nServerId
            local nGrpId = tAnItem.nGrpId
            if not arrCachePoolCnt[nServerId] then
                arrCachePoolCnt[nServerId] = {}
            end
            if not arrCachePoolCnt[nServerId][nGrpId] then
                arrCachePoolCnt[nServerId][nGrpId] = 0
            end
            arrCachePoolCnt[nServerId][nGrpId] = arrCachePoolCnt[nServerId][nGrpId] + 1
        end
    end
    local sCachePool = ""
    for nServerId,tData in pairs(arrCachePoolCnt) do
        sCachePool = sCachePool..string.format("nServerId_%d:",nServerId)
        for nGrpId,nCnt in pairs(tData) do
            sCachePool = sCachePool..string.format("(nGrpId_%d:%d),",nGrpId,nCnt)
        end
        sCachePool = sCachePool.." "
    end
    -- tBase.Log("[AndroidIo.TotalTempNumber]统计可用缓存池机器人数量:%s",sCachePool)

    --回收池的机器人
    local arrRecycleCnt = {}
    for _,nUserId in pairs(AndroidIo.tRecyclePool) do
        local tAnItem = AndroidIo.xmlandroidmap[nUserId]
        if tAnItem then
            local nServerId = tAnItem.nServerId
            local nGrpId = tAnItem.nGrpId
            if not arrRecycleCnt[nServerId] then
                arrRecycleCnt[nServerId] = {}
            end
            if not arrRecycleCnt[nServerId][nGrpId] then
                arrRecycleCnt[nServerId][nGrpId] = 0
            end
            arrRecycleCnt[nServerId][nGrpId] = arrRecycleCnt[nServerId][nGrpId] + 1
        end
    end
    local sRecycle = ""
    for nServerId,tData in pairs(arrRecycleCnt) do
        sRecycle = sRecycle..string.format("nServerId_%d:",nServerId)
        for nGrpId,nCnt in pairs(tData) do
            sRecycle = sRecycle..string.format("(nGrpId_%d:%d),",nGrpId,nCnt)
        end
        sRecycle = sRecycle.." "
    end
    -- tBase.Log("[AndroidIo.TotalTempNumber]统计回收池机器人数量:%s",sRecycle)

    --游戏中的机器人
    local arrGameCnt = {}
    for _,tData in pairs(AndroidIo.tInGameAndroid) do
        if not arrGameCnt[tData.nServerId] then
            arrGameCnt[tData.nServerId] = {}
        end
        if not arrGameCnt[tData.nServerId][tData.nGrpId] then
            arrGameCnt[tData.nServerId][tData.nGrpId] = 0
        end
        arrGameCnt[tData.nServerId][tData.nGrpId] = arrGameCnt[tData.nServerId][tData.nGrpId] + 1
    end
    local sInGame = ""
    for nServerId,tData in pairs(arrGameCnt) do
        sInGame = sInGame..string.format("nServerId_%d:",nServerId)
        for nGrpId,nCnt in pairs(tData) do
            sInGame = sInGame..string.format("(nGrpId_%d:%d),",nGrpId,nCnt)
        end
        sInGame = sInGame.." "
    end
    -- tBase.Log("[AndroidIo.TotalTempNumber]统计游戏中机器人数量:%s",sInGame)

    --借用的机器人
    local arrTotalCnt = {}
    for k,v in pairs(AndroidIo.xmlandroidmap) do
        local nGrpId = v.nGrpId
        local nServerId = v.nServerId
        if not arrTotalCnt[nServerId] then
            arrTotalCnt[nServerId] = {}
        end
        if not arrTotalCnt[nServerId][nGrpId] then
            arrTotalCnt[nServerId][nGrpId] = 0
        end
        arrTotalCnt[nServerId][nGrpId] = arrTotalCnt[nServerId][nGrpId] + 1
    end
    local s = ""
    for nServerId,tCnt in pairs(arrTotalCnt) do
        s = s..string.format("{nServerId_%d=",nServerId)
        for nGrpId,nCnt in pairs(tCnt) do
            s = s..string.format("[nGrpId_%d nCnt_%d] ",nGrpId,nCnt)
        end
        s = s.."}"
    end

    tBase.Log("_TotalTempNumber 统计当前缓存 借用机器人:%s 游戏中: %s 可用缓存池: %s 回收池: %s ",s,sInGame,sCachePool,sRecycle)

    AndroidIo.CheckComeBackOverTime()
end

function AndroidIo.Start()
    tBase.RegFunc(tProtoMgr.Sys.ANDROID, tProtoMgr.Sub_Android.SUB_REP_GETANDROID, AndroidIo.CallBack)
    tBase.RegFunc(tProtoMgr.Sys.ANDROID, tProtoMgr.Sub_Android.SUB_REP_SETANDROID, AndroidIo.SetAndroidCallBack)
    tBase.SetTimer(65511,AndroidIo.nTimerTime,-1,AndroidIo.CheckNeedComeback)
    tBase.SetTimer(65512,1000*5,1,AndroidIo.CheckAndroidServer)
end

--获取机器人
--tData 如{nGrpId=23,nMin=1, nHigh=100000, nCnt=3} 
--nGrpId:分组  nMin：金币下限  nHigh：金币上限  nCnt：数量
--tData中的tData.nIndex机器人索引类型说明：
--若不传： 默认用原有的配置（索引为0）  若传：则需在后台配置一套新的（新的GrpId = 索引*1000 +分组id），新的只针对一个分组，调用时应加上对其他分组的判断：若后台此分组没对应配置，则传0。
function AndroidIo.GetAndroid(tData, CallBack, ...)
    if not tData or not CallBack then return end

    if not (tData.nMin and tData.nHigh and tData.nGrpId and tData.sIndex and
        tData.nCnt) then
        tBase.Log("_GetAndroid 参数错误，不予处理")
        return
    end

    if tData.nMin > tData.nHigh then
        tBase.Log("_GetAndroid  上下限错误，不予处理 (%d, %d)", tData.nMin, tData.nHigh)
        return
    end

    local index = tData.nIndex or 0 --索引默认用0（原始那套配置）

    if tPubUserInfo.GetRobConfig(index*1000 + tData.nGrpId)==0 then
        index = 0
    end

    local nNewGrpId = index*1000 + tData.nGrpId

    tBase.Log("_GetAndroid nNewGrpId_%d,index_%d", nNewGrpId, index)

    --保存一次获取机器人数量
    AndroidIo.SetAndroidCntByMin(tData) 

    --先判断下可用缓存池里面符合要求的机器人够不够 
    local arrTempUserId = {}
    for nUserId,tAnItem in pairs(AndroidIo.tCachePool) do
        local tAnItem = AndroidIo.xmlandroidmap[nUserId]
        if tAnItem and tAnItem.nGrpId==nNewGrpId  then --todo
            table.insert(arrTempUserId,nUserId)
        end
    end

    --可用缓存池里的机器人够用
    if #arrTempUserId>=tData.nCnt then
        local arrAndroid = {}
        for i=1,tData.nCnt do
            local nUserId = arrTempUserId[i]
            local tAnItem = AndroidIo.xmlandroidmap[nUserId]
            local tItem = {}
            for a, b in pairs(tProtoMgr.PubProto_pb.AndroidItem()._setter) do
                tItem[a] = tAnItem[a]
            end

            local nMin,nHigh = tData.nMin,tData.nHigh
            if nMin==0 and nHigh==0 then
                nMin,nHigh =tGoldRange.GetRange(nNewGrpId)
            end

            --修改机器人金币 
            local nChange = (nHigh-nMin)*math.random(1,100)/100+nMin 
            nChange = nChange>0 and nChange or 0
            tItem.nGold = nChange
            tPubUserInfo.SetComAndroidGold(nUserId,nChange)

            table.insert(arrAndroid,tItem)
            AndroidIo.tCachePool[nUserId] = nil
            AndroidIo.PushAndroidInGame(tItem)
        end
        local args = {...}
        table.insert(args, arrAndroid)
        tBase.Log("_GetAndroid  nGrpId_%d从可用缓存池读取机器人:%d,需求是:%d nMin=%.2f,nHigh=%.2f",nNewGrpId, #arrAndroid,tData.nCnt,tData.nMin,tData.nHigh)
        CallBack(table.unpack(args))
        return
    end

    local sClientID = AndroidIo.GetAndroidServer()
    if not sClientID then
        tBase.Log("_GetAndroid   没有可用的机器人服")
        return
    end

    local nNowTime = os.time()
    if nNowTime - AndroidIo.nLastReqTime < AndroidIo.nReqTimeLimt then
        tBase.Log("_GetAndroid  每%d秒内只允许向机器人服请求一次,nGrpId_%d",
            AndroidIo.nReqTimeLimt,nNewGrpId)
        return
    end

    AndroidIo.nR = AndroidIo.nR + 1
    if AndroidIo.nR > AndroidIo.nMax then AndroidIo.nR = 1 end
    AndroidIo.xmlcallbackfunc[AndroidIo.nR] = {ctor=CallBack, args={...}, tGetData=tData,nReqTime=os.time()}

    local nLastMinCnt = AndroidIo.GetAndroidCntByMin(tData) --过去一断时间内获取机器人的数目
    local nCnt = math.max(nLastMinCnt,tData.nCnt)
    nCnt = math.min(nCnt,AndroidIo.nLimit)

    tBase.Log("_GetAndroid 向机器人服请求机器人 nR_%d  nGrpId_%d,nCnt_%d,nMin=%.2f,nHigh=%.2f sServerKey: %s"
    ,AndroidIo.nR,nNewGrpId,nCnt, tData.nMin, tData.nHigh,sClientID)

    local tSend = tProtoMgr.PubProto_pb.Req_GetAndroid() 
    tSend.nGrpId = nNewGrpId
    tSend.sIndex = tData.sIndex
    tSend.nMin = tData.nMin
    tSend.nHigh = tData.nHigh
    tSend.nCnt = nCnt
    tSend.nR = AndroidIo.nR
    tSend.nGameNeedCnt = tData.nCnt
    -- tSend.nIndex = tData.nIndex or 0
    
    local s = tBase.GetSP().new(tProtoMgr.Sys.ANDROID, tProtoMgr.Sub_Android.SUB_REQ_GETANDROID)
    s:AddString(tSend:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

--回收机器人 tData = {arrAndroid}
--isToChache 是否放入缓存池,true:放入缓存池，false:放入回收池，默认是true
function AndroidIo.SetAndroid(tData,isToChache)
    if isToChache==nil then isToChache = true end
    local  tDelAndroid = {}
    tDelAndroid = tData.arrAndroid
    if #tDelAndroid <= 0 then return end
    local _IsInfoRight = function(tItem, tStander)
        for k, v in pairs(tStander) do
            if tItem[k] == nil then
                tBase.Log("Error 字段空 k:%s", k)
                return false
            elseif tStander[k] ~= tItem[k] then
                if not (k == "nDiamond" or k == "nMaxRound" or k == "nGold" or k == "nWin" or k == "nLose" or k == "nSimilar") then
                    tBase.Log("[AndroidIo.SetAndroid]Error 不能被修改的字段被修改 k:%s", k)
                    tBase.Log("[AndroidIo.SetAndroid]Error 修改前:"..tStander[k].." 修改后:"..tItem[k])
                    return false
                end
            end
        end
        return true
    end

    local nNowTime = os.time()
    local nToRecyCnt = 0
    local nToCacheCnt = 0
    local sToRecy = ""
    local sToCache = ""
    for _, v in pairs(tDelAndroid) do
        AndroidIo.tInGameAndroid[v.nUserId] = nil
        if AndroidIo.xmlandroidmap[v.nUserId] then
            if not _IsInfoRight(v, AndroidIo.xmlandroidmap[v.nUserId]) then
                tBase.Log("[AndroidIo.SetAndroid]ERROR:归还的机器人信息错误UserId:%d", v.nUserId)
            else
                --放入回收池
                local t = tPubUserInfo.GetComAndroidUserInfo(v.nUserId)
                v.nGold = t.nGold
                local nGetTime = AndroidIo.tAndroidGetTime[v.nUserId] or 0
                local nDiff =  nNowTime - nGetTime
                local nServerState = (AndroidIo.tAnServer[v.nServerId] and AndroidIo.tAnServer[v.nServerId].nServerState) or 0
                if isToChache and nDiff < AndroidIo.nLimitTime and nServerState==1 then
                    --金币还在所在范围，而且使用时间还没达到限制,而且这个机器人所属的服没有维护
                    --放到可用缓存池
                    AndroidIo.PushToCachePool(v.nUserId)
                    nToCacheCnt = nToCacheCnt + 1
                    sToCache = sToCache..string.format("%d,",v.nUserId)
                else
                    AndroidIo.PushToRecyclePool(v.nUserId)
                    nToRecyCnt = nToRecyCnt + 1
                    sToRecy = sToRecy..string.format("%d,",v.nUserId)
                end
            end
        else
            tBase.Log("[AndroidIo.SetAndroid]ERROR:你并没有借这个机器人,不能归还 UserId:%d", v.nUserId)
        end 
    end
    
    if nToRecyCnt>0 then
        tBase.Log("[AndroidIo.SetAndroid]机器人从游戏中退出,放入回收池 nCnt:%d  %s", nToRecyCnt,sToRecy)
        AndroidIo.CheckComeBackOverTime()
    end
    if nToCacheCnt>0 then
        tBase.Log("[AndroidIo.SetAndroid]机器人从游戏中退出,放入可用缓存池 nCnt:%d  %s", nToCacheCnt,sToCache)
    end
end

--机器人服返回获取机器人
function AndroidIo.CallBack(sClientID, sData, nLen)
    local s = tBase.GetRP().new(sData, nLen)
    local tGetAndroid = tProtoMgr.PubProto_pb.Rep_GetAndroid()
    tGetAndroid:ParseFromString(s:GetString())
    tBase.Log("_CallBack 从机器人服返回   nR_%d   ",tGetAndroid.nR or -1 ) 
    if not tGetAndroid.nR then 
        tBase.Log("_CallBack 从机器人服  借到机器人有问题  nR_%d   ",tGetAndroid.nR or -1 )
        return 
    end 
    local tCallback = AndroidIo.xmlcallbackfunc[tGetAndroid.nR]
    if not tCallback then 
        tBase.Log("_CallBack 从机器人服  借到机器人有问题  nR_%d   xmlcallbackfunc is nil ",tGetAndroid.nR or -1 )        
        return 
    end 
    if not tCallback.tGetData then 
        tBase.Log("_CallBack 从机器人服 借到机器人有问题  nR_%d   tGetData is nil ",tGetAndroid.nR or -1 )        
        return 
    end 
    local tGetData = tCallback.tGetData or  {nMin=0,nHigh=0} 
    local arrAndroidItem = {}
    local nCnt = 0
    local sArrUserId = ""
    for k, v in ipairs(tGetAndroid.arrAndroidItem) do
        local tItem = {}
        for a, b in pairs(tProtoMgr.PubProto_pb.AndroidItem()._setter) do
            tItem[a] = v[a]
        end
        nCnt = nCnt + 1
        sArrUserId = sArrUserId .. string.format("%d,",tItem.nUserId)
        if not AndroidIo.xmlandroidmap[tItem.nUserId] then
            AndroidIo.Setxmlandroidmap(tItem)      
            tItem.nRandRound = math.random(math.min(tItem.nMinRound, tItem.nMaxRound), tItem.nMaxRound)
            --修改机器人金币
            local nMin,nHigh = tGetData.nMin,tGetData.nHigh
            if nMin==0 and nHigh==0 then
                nMin,nHigh =tGoldRange.GetRange(tItem.nGrpId)
            end
            local nGold = (nHigh-nMin)*math.random(1,100)/100+nMin
            nGold = nGold>0 and nGold or 0
            tItem.nGold = nGold
            AndroidIo.tAndroidGetTime[tItem.nUserId] = os.time()
            tPubUserInfo.AddComAndroidUserInfo(tItem)
            tPubUserInfo.SetComAndroidGold(tItem.nUserId,tItem.nGold)          
            if k<=tGetAndroid.nGameNeedCnt then
                --游戏服需要多少个，优先给游戏服
                table.insert(arrAndroidItem, tPublicApi.Clone(tItem))
                AndroidIo.PushAndroidInGame(tItem)
            else
                --多余的机器人放到可用缓存池
                AndroidIo.PushToCachePool(tItem.nUserId)
            end
        else
            tBase.Log("_CallBack    Error:这个机器人已经获取过了,nUserId_%d,nServerId_%d,nOldServerId_%d", 
                tItem.nUserId,tItem.nServerId,AndroidIo.xmlandroidmap[tItem.nUserId].nServerId)
            if tItem.nServerId~=AndroidIo.xmlandroidmap[tItem.nUserId].nServerId then
                --不同服的重复机器人，先存起来，稍后返回机器人服
                if not AndroidIo.tRepeatAndroid[tItem.nServerId] then
                    AndroidIo.tRepeatAndroid[tItem.nServerId] = {}
                end
                AndroidIo.tRepeatAndroid[tItem.nServerId][tItem.nUserId] = tItem
            end
        end
    end

    tBase.Log("_CallBack  从机器人服%s借到机器人%d个 %s",sClientID, nCnt, sArrUserId)
    AndroidIo.TotalTempNumber()

    local args = AndroidIo.xmlcallbackfunc[tGetAndroid.nR].args
    table.insert(args, arrAndroidItem)
    AndroidIo.xmlcallbackfunc[tGetAndroid.nR].ctor(table.unpack(args))
    AndroidIo.xmlcallbackfunc[tGetAndroid.nR] =nil
end

--把机器人放回机器人服
function AndroidIo.SetAndroidBackToAnServer(nServerId,arrReturn)
    local sClientID = tBase.GetServerIdIdKey(nServerId)

    if sClientID then
        sClientID = sClientID..":0"
        local tRelease = tProtoMgr.PubProto_pb.Req_SetAndroid()

        local nCnt = 0
        for _, nUserId in pairs(arrReturn) do
            local tItem = AndroidIo.xmlandroidmap[nUserId]
            if tItem then
                local tAnItem = tRelease.arrAndroidItem:add()
                for a, b in pairs(tProtoMgr.PubProto_pb.AndroidItem()._setter) do
                    tAnItem[a] = tItem[a]
                end
                nCnt = nCnt + 1
            end
        end
        tBase.Log(string.format("_SetAndroidBackToAnServer  机器人归还 nServerId:%d nCnt:%d", nServerId, nCnt))
        
        local s = tBase.GetSP().new(tProtoMgr.Sys.ANDROID, tProtoMgr.Sub_Android.SUB_REQ_SETANDROID)
        s:AddString(tRelease:SerializeToString())
        tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
    else
        tBase.Log("_SetAndroidBackToAnServer  没找到机器人服nServerId_%d的serverKey,", nServerId)
    end
end

--机器人服返回回收机器人
function AndroidIo.SetAndroidCallBack(sClientID, sData, nLen)
    local s = tBase.GetRP().new(sData, nLen)
    local tSetAndroidRep = tProtoMgr.PubProto_pb.Rep_SetAndroid()
    tSetAndroidRep:ParseFromString(s:GetString())

    local nServerId =tonumber(string.match(sClientID,"_(%d+)"))

    local nCnt = 0
    local sArrUserId = ""
    for k,v in pairs(tSetAndroidRep.arrUserId) do
        if type(v)=="number" then
            if AndroidIo.xmlandroidmap[v] and AndroidIo.xmlandroidmap[v].nServerId==nServerId then
                AndroidIo.DelAndroid(v)
            elseif AndroidIo.tRepeatAndroid[nServerId] then
                AndroidIo.tRepeatAndroid[nServerId][v] = nil
            end
            nCnt = nCnt + 1
            sArrUserId = sArrUserId .. string.format("%d,",v)
        end
    end

    tBase.Log(string.format("[AndroidIo.SetAndroidCallBack]机器人服%s成功回收机器人 nCnt:%d %s",sClientID, nCnt, sArrUserId))
    AndroidIo.TotalTempNumber()
end

--把机器人放入可用缓存池
function AndroidIo.PushToCachePool(nUserId)
    AndroidIo.tCachePool[nUserId] = nUserId
    tBase.Log("_PushToCachePool nUserId_%d  机器人放入可用池 ",nUserId)
end

--把机器人放入回收缓存池
function AndroidIo.PushToRecyclePool(nUserId)
    AndroidIo.tRecyclePool[nUserId] = nUserId
    tBase.Log("_PushToRecyclePool nUserId_%d  机器人放入回收池 ",nUserId)
end

--获取过去一断时间内请求的机器人数目
--@params tData 如{nGrpId=23,nMin=1, nHigh=100000, nCnt=3}
--@return 机器人数量（默认0）
function AndroidIo.GetAndroidCntByMin(tData)
    local nCnt = 0
    local nNowTime = os.time()
    local nGrpId = tData.nGrpId
    if AndroidIo.tGrpGetCntByMin[nGrpId] then
        for i=#AndroidIo.tGrpGetCntByMin[nGrpId],1,-1 do
            local t = AndroidIo.tGrpGetCntByMin[nGrpId][i]
            if nNowTime - t.nTime <= AndroidIo.nStatisticsTime then
                if t.nMin==tData.nMin and t.nHigh==tData.nHigh then
                    nCnt = nCnt + t.nCnt
                end
            else
                table.remove(AndroidIo.tGrpGetCntByMin[nGrpId],i)
            end
        end
    end
    return nCnt
end

--保存一次获取机器人数量
--@params tData 如{nGrpId=23,nMin=1, nHigh=100000, nCnt=3}
function AndroidIo.SetAndroidCntByMin(tData)
    local nGrpId = tData.nGrpId
    if not AndroidIo.tGrpGetCntByMin[nGrpId] then
        AndroidIo.tGrpGetCntByMin[nGrpId] = {}
    end
    local t = {}
    t.nTime = os.time()
    t.nCnt = tData.nCnt
    t.nMin = tData.nMin
    t.nHigh = tData.nHigh
    table.insert(AndroidIo.tGrpGetCntByMin[nGrpId],t)
end

--获取一个正常运行的机器人服key
--@return sClientID(默认nil)
function AndroidIo.GetAndroidServer()
    local sClientID = nil
    local arrAnServer = {}

    for nServerId,tData in pairs(AndroidIo.tAnServer) do
        if tData.nServerState==1 then
            table.insert(arrAnServer,tData.sServerKey)
        end
    end

    if #arrAnServer>0 then
        local nIdx = math.random(1,#arrAnServer)
        sClientID = arrAnServer[nIdx]..":0"
    end
    return sClientID
end

--检查机器人服的状态
function AndroidIo.CheckAndroidServer()
    local str = "[AndroidIo.CheckAndroidServer]机器人服状态(0:未启用 1:正常 2:维护 3:测试 4:进程没开):"
    local arrServerKey = tBase.GetSrcAllKey(tName.android) or {}
    AndroidIo.tAnServer = {}
    for _,sServerKey in pairs(arrServerKey) do
        local nServerId =tonumber(string.match(sServerKey,"_(%d+)"))
        if nServerId then 
            local nServerState = tPublicRedis.GetServerState(nServerId)
            local t = {}
            t.nServerState = nServerState
            t.sServerKey = sServerKey
            AndroidIo.tAnServer[nServerId] = t
            str = str..string.format("nServerId_%d,nServerState:%d, ",nServerId,nServerState)
        end
    end

    if #arrServerKey > 0 then
        -- tBase.Log(str)
    end
end

--保存机器人信息，以便校对
function AndroidIo.Setxmlandroidmap(tItem)
    local nUserId = tItem.nUserId
    local tAnItem = {}
    for a, b in pairs(tProtoMgr.PubProto_pb.AndroidItem()._setter) do
        tAnItem[a] = tItem[a]
    end
    AndroidIo.xmlandroidmap[nUserId] = tAnItem
end

--删除机器人数据
function AndroidIo.DelAndroid(nUserId)
    tPubUserInfo.DelComAndroidUserInfo(nUserId)
    AndroidIo.xmlandroidmap[nUserId] = nil
    AndroidIo.tAndroidGetTime[nUserId] = nil
    AndroidIo.tRecyclePool[nUserId] = nil
    AndroidIo.tCachePool[nUserId] = nil
    AndroidIo.tInGameAndroid[nUserId] = nil
end

--记录机器人进入游戏牌桌中
function AndroidIo.PushAndroidInGame(tItem)
    tBase.Log("_PushAndroidInGame nUserId_%d  机器人进入游戏牌桌中 ",tItem.nUserId)
    AndroidIo.tInGameAndroid[tItem.nUserId] = {nUserId=tItem.nUserId,nGrpId=tItem.nGrpId,nServerId=tItem.nServerId}
end

--把重复的机器人放回机器人服
function AndroidIo.SetBackRepeatAndroid()
    local arrComeback = {}
    for nServerId,arrAndroid in pairs(AndroidIo.tRepeatAndroid) do
        arrComeback[nServerId] = {}
        for k,v in pairs(arrAndroid) do
            table.insert(arrComeback[v.nServerId],v)
        end
    end

    for nServerId, arrAndroid in pairs(arrComeback) do
        local sClientID = tBase.GetServerIdIdKey(nServerId)
        if sClientID then
            sClientID = sClientID..":0"

            local arrTempAndroid = {}
            for i=1,#arrAndroid do
                table.insert(arrTempAndroid,arrAndroid[i])
                if i%AndroidIo.nLimit==0 or i==#arrAndroid then
                    local tRelease = tProtoMgr.PubProto_pb.Req_SetAndroid()

                    local nCnt = 0
                    for _, tItem in pairs(arrAndroid) do
                        local tAnItem = tRelease.arrAndroidItem:add()
                        for a, b in pairs(tProtoMgr.PubProto_pb.AndroidItem()._setter) do
                            tAnItem[a] = tItem[a]
                        end
                        nCnt = nCnt + 1
                    end

                    tBase.Log(string.format("[AndroidIo.SetBackRepeatAndroid]把重复的机器人归还到机器人服nServerId:%d nCnt:%d", nServerId, nCnt))
                    
                    local s = tBase.GetSP().new(tProtoMgr.Sys.ANDROID, tProtoMgr.Sub_Android.SUB_REQ_SETANDROID)
                    s:AddString(tRelease:SerializeToString())
                    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
                end
            end
        else
            tBase.Log("[AndroidIo.SetBackRepeatAndroid]没找到机器人服nServerId_%d的serverKey,", nServerId)
        end
    end
end

--检查是否很久没有回收机器人了
function AndroidIo.CheckComeBackOverTime()
    if os.time()-AndroidIo.nLastCheckTime>AndroidIo.nMaxSpaceCheckTime then
        tBase.Log("[AndroidIo.CheckComeBackOverTime]Warning:很长时间没有进行回收检测了,强行回收机器人，并且重设回收定时器")
        AndroidIo.CheckNeedComeback()
        tBase.SetTimer(65511,AndroidIo.nTimerTime,-1,AndroidIo.CheckNeedComeback)
    end
end

return AndroidIo


