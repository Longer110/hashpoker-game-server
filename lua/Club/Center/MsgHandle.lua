local MsgHandle = {}

local function OnTimeFunction(nIndex,sType)
    local arrClub = CenterData.arrSplitClub[nIndex]
    if arrClub then
        for _,tClub in pairs(arrClub) do
            if tClub then
                if sType=="UpdateClubConfig" then
                    tClub:DelayUpDateClubConfig()
                elseif sType=="CheckClubTable" then
                    tClub:DelayCheckTableIsExits()
                elseif sType=="CheckServerOfTable" then
                    tClub:DelayCheckServerOfTable()
                elseif sType=="CheckCenterId" then
                    tClub:DelayCheckCenterId()
                elseif sType=="OnTimeDealOverTimeApply" then
                    tClub:DelayToReqRefreshApply()
                end
            end
        end
    end
end
  
--定时更新俱乐部后台配置
function MsgHandle.UpdateClubConfig()
    local nSplit = math.ceil(CenterData.nClubCnt/Define.nSplitClubCnt)
    if nSplit>0 then
        for i=1,nSplit do
            CenterData.tTimerObj:DelayCall(i*10*1000,OnTimeFunction,i,"UpdateClubConfig")
        end
    end
end

--定时检查俱乐部牌桌是否还存在
function MsgHandle.CheckClubTable()
    local nSplit = math.ceil(CenterData.nClubCnt/Define.nSplitClubCnt)
    if nSplit>0 then
        for i=1,nSplit do
            CenterData.tTimerObj:DelayCall(i*10*1000,OnTimeFunction,i,"CheckClubTable")
        end
    end
    Base.SetTimer(CenterData.tTimerId.CheckClubTable, 1000*60*60, 1, MsgHandle.CheckClubTable) --定时检查俱乐部牌桌
end

--检查牌桌所在服务器是否还在
function MsgHandle.CheckServerOfTable()
    local nSplit = math.ceil(CenterData.nClubCnt/Define.nSplitClubCnt)
    if nSplit>0 then
        for i=1,nSplit do
            CenterData.tTimerObj:DelayCall(i*10*1000,OnTimeFunction,i,"CheckServerOfTable")
        end
    end
end

--检查俱乐部所在中心服id是否能删掉
function MsgHandle.CheckCenterId()
    local nSplit = math.ceil(CenterData.nClubCnt/Define.nSplitClubCnt)
    if nSplit>0 then
        for i=1,nSplit do
            CenterData.tTimerObj:DelayCall(i*10*1000,OnTimeFunction,i,"CheckCenterId")
        end
    end
end

--定时检查俱乐部服维护状态
function MsgHandle.CheckMaintenanceOfServer()
    local tData = PublicRedis.BlockchainStopServerMaintian(ServerInfo.nServerId)
    if tData then
        local tMaintenanceInfo = {}
        tMaintenanceInfo.ActualStart = tData.ActualStart
        tMaintenanceInfo.ActualEnd = tData.ActualEnd
        tMaintenanceInfo.sStartTime = os.date("%Y-%m-%d %H:%M:%S",tData.ActualStart)
        tMaintenanceInfo.sEndTime = os.date("%Y-%m-%d %H:%M:%S",tData.ActualEnd)
        if os.time()<tData.ActualEnd then
            CenterData.tMaintenanceInfo = tMaintenanceInfo
            local sMaintenance = Cjson.encode(tMaintenanceInfo)
            Base.Log("俱乐部维护信息 %s",sMaintenance)
            local ClubCServerMaintenanceNotify = {}
            ClubCServerMaintenanceNotify.sMaintenance = sMaintenance
            MsgApi.Broadcast("ClubCServerMaintenanceNotify",ClubCServerMaintenanceNotify)
        end
    else
        CenterData.tMaintenanceInfo = nil
    end
    Base.SetTimer(CenterData.tTimerId.CheckMaintenanceOfServer, 1000*60, 1, MsgHandle.CheckMaintenanceOfServer) --定时检查俱乐部服维护状态
end

--定时处理过期申请
function MsgHandle.OnTimeDealOverTimeApply()
    local nSplit = math.ceil(CenterData.nClubCnt/Define.nSplitClubCnt)
    if nSplit>0 then
        for i=1,nSplit do
            CenterData.tTimerObj:DelayCall(i*10*1000,OnTimeFunction,i,"OnTimeDealOverTimeApply")
        end
    end
end

--DB服 申请失效处理返回
function MsgHandle.OnDBClubApplyInvalidRsp(sReturnKey, Data, nLen)
    local tData =DbClubServAux:Parser(Data, nLen,"ClubApplyInvalidRsp")
    if tData ==nil then
        Base.Log("ClubApplyInvalidRsp _Parse Err")
        return
    end

    local tClub = ClubManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnDBClubApplyInvalidRsp not find Club")
        return
    end

    tClub:RefreshApplyCnt(tData)
end

--服务器分组请求
function MsgHandle.DBServerGroupReq()
    local ServerIdGroupReq = {}
    ServerIdGroupReq.nServerId = ServerInfo.nServerId
    ServerIdGroupReq.nLoadAll = 1
    MsgApi.SendToDBServer("ServerIdGroupReq",ServerIdGroupReq)

    Base.SetTimer(CenterData.tTimerId.DBServerGroupReq, Define.nTime_LoadGroup, 1, MsgHandle.DBServerGroupReq) --服务器分组请求
end

--DB服 服务器分组数据
function MsgHandle.OnDBServerGroupRsp(sReturnKey, Data, nLen)
    local tData =DbClubServAux:Parser(Data, nLen,"ServerIdGroupRsp")
    if tData ==nil then
        Base.Log("ServerIdGroupRsp _Parse Err")
        return
    end

    local arrGroup = {}
    local tGroup_New = {}
    for k,v in pairs(tData.arrGroup) do
        if type(v)=="number" then
            table.insert(arrGroup,v)
            tGroup_New[v] = true
        end
    end
    -- Base.Log("_OnDBServerGroupRsp nowGroup:%s oldGroup:%s nMinClubId_%d nMaxClubId_%d",
    -- Cjson.encode(arrGroup),Cjson.encode(CenterData.arrGroup),tData.nMinClubId,tData.nMaxClubId)

    local tGroup_old = {}
    --删除不存在分组的大厅
    for _,nGroupId in pairs(CenterData.arrGroup) do
        if not tGroup_New[nGroupId] then
            Base.Log("_OnDBServerGroupRsp 分组关闭 nGroupId_%d",nGroupId)
            ClubManager.RemoveClub(nGroupId)
        end
        tGroup_old[nGroupId] = true
    end
    
    --新增分组
    local arrAddGroup = {}
    for _,v in pairs(arrGroup) do
        if not tGroup_old[v] then
            table.insert(arrAddGroup,v)
        end
    end
    if #arrAddGroup > 0 then
        Base.Log("_OnDBServerGroupRsp 新增分组 arrGroup_%s",Cjson.encode(arrAddGroup))
        MsgHandle.ReCorverClubHall(arrAddGroup) --创建对应分组的俱乐部大厅
    end

    CenterData.arrGroup = arrGroup

    MsgHandle.BroadcastGroup() --通知从服分组id

    local isNeedLoad = false
    if CenterData.nMinClubId==nil and CenterData.nMaxClubId==nil then
        Base.Log("_OnDBServerGroupRsp 首次加载 ")
        CenterData.nMinClubId = tData.nMinClubId
        CenterData.nMaxClubId = tData.nMaxClubId
        table.insert(CenterData.arrClubReqQueue,{nMinClubId=tData.nMinClubId,nMaxClubId=tData.nMaxClubId})
        isNeedLoad = true
    else
        if CenterData.nMinClubId<tData.nMinClubId then
            --本服加载的俱乐部最小值变大，删除部分俱乐部
            Base.Log("_OnDBServerGroupRsp nMinClubId:%d -> %d 删除部分俱乐部",CenterData.nMinClubId,tData.nMinClubId)
            local arrClub = ClubManager.GetAllClub()
            for _,tClub in pairs(arrClub) do
                if tClub.nClubId>=Define.nMinClubId and tClub.nClubId<tData.nMinClubId then
                    ClubManager.RemoveClub(tClub.nClubId)
                end
            end
        elseif CenterData.nMinClubId>tData.nMinClubId then
            --本服加载的俱乐部最小值变大，获取新增部分的俱乐部数据
            Base.Log("_OnDBServerGroupRsp nMinClubId:%d -> %d 需要获取新的俱乐部数据",CenterData.nMinClubId,tData.nMinClubId)
            table.insert(CenterData.arrClubReqQueue,{nMinClubId=tData.nMinClubId,nMaxClubId=CenterData.nMinClubId-1})
            isNeedLoad = true
        end
        CenterData.nMinClubId = tData.nMinClubId
    
        if CenterData.nMaxClubId~=-1 and tData.nMaxClubId~=-1 then --新旧值都不是无穷大
            if CenterData.nMaxClubId>tData.nMaxClubId then
                --本服加载的俱乐部最大值变小，删除部分俱乐部
                Base.Log("_OnDBServerGroupRsp nMaxClubId:%d -> %d 删除部分俱乐部",CenterData.nMaxClubId,tData.nMaxClubId)
                local arrClub = ClubManager.GetAllClub()
                for _,tClub in pairs(arrClub) do
                    if tClub.nClubId>tData.nMaxClubId then
                        ClubManager.RemoveClub(tClub.nClubId)
                    end
                end
            elseif CenterData.nMaxClubId<tData.nMaxClubId then
                --本服加载的俱乐部最大值变大，获取新增部分的俱乐部数据
                Base.Log("_OnDBServerGroupRsp nMaxClubId:%d->%d 需要获取新的俱乐部数据",CenterData.nMaxClubId,tData.nMaxClubId)
                table.insert(CenterData.arrClubReqQueue,{nMinClubId=CenterData.nMaxClubId+1,nMaxClubId=tData.nMaxClubId})
                isNeedLoad = true
            end
        elseif CenterData.nMaxClubId==-1 and tData.nMaxClubId~=-1 then --旧值是无穷大，新值不是
            --本服加载的俱乐部最大值变小，删除部分俱乐部
            Base.Log("_OnDBServerGroupRsp nMaxClubId:oo ->%d 删除部分俱乐部",tData.nMaxClubId)
            local arrClub = ClubManager.GetAllClub()
            for _,tClub in pairs(arrClub) do
                if tClub.nClubId>tData.nMaxClubId then
                    ClubManager.RemoveClub(tClub.nClubId)
                end
            end
        elseif CenterData.nMaxClubId~=-1 and tData.nMaxClubId==-1 then --旧值不是无穷大，新值是
            Base.Log("_OnDBServerGroupRsp nMaxClubId:%d -> oo 需要获取新的俱乐部数据",CenterData.nMaxClubId,tData.nMaxClubId)
            table.insert(CenterData.arrClubReqQueue,{nMinClubId=CenterData.nMaxClubId+1,nMaxClubId=tData.nMaxClubId})
            isNeedLoad = true
        end
        CenterData.nMaxClubId = tData.nMaxClubId
    end

    if isNeedLoad then
        MsgHandle.CheckNeedToReqClubData()
    end
end

--检查是否需要请求俱乐部数据
function MsgHandle.CheckNeedToReqClubData()
    if #CenterData.arrClubReqQueue==0 then
        local sSendSMS = "加载俱乐部数据完毕"
        Base.Log("_CheckNeedToReqClubData %s",sSendSMS)
        MsgApi.SendToTGChat(sSendSMS)
        return
    end
    local tData = CenterData.arrClubReqQueue[1]
    if tData.nMinClubId ~=-1 then
        MsgHandle.DBClubDataReq(tData.nMinClubId,tData.nMaxClubId)
    end
end

--加载俱乐部数据
--@params arrGroup 分组数组
function MsgHandle.DBClubDataReq(nMinClubId,nMaxClubId)
    local ClubDataReq = {}
    ClubDataReq.nMinClubId = nMinClubId
    ClubDataReq.nLimitCnt = Define.nLimitCnt
    ClubDataReq.nMaxClubId = nMaxClubId
    MsgApi.SendToDBServer("ClubDataReq",ClubDataReq)
    Base.Log("_DBClubDataReq nMinClubId:%d nMaxClubId:%d nLimitCnt:%d",nMinClubId,nMaxClubId,Define.nLimitCnt) 
end

--加载俱乐部成员的基本信息  不加载了
function MsgHandle.DBLoadClubUserReq(arrClubId)
    local ClubLoadUserInfoReq = {}
    ClubLoadUserInfoReq.arrClubId = arrClubId
    -- MsgApi.SendToDBServer("ClubLoadUserInfoReq",ClubLoadUserInfoReq)
end

--DB服 返回俱乐部数据
function MsgHandle.OnDBClubDataRsp(sReturnKey, Data, nLen)
    local tData =DbClubServAux:Parser(Data, nLen,"ClubDataRsp")
    if tData ==nil then
        Base.Log("ClubDataRsp _Parse Err")
        return
    end

    local arrClubId = {}
    local tClubId = {}
    for k,v in pairs(tData.arrClub) do
        local tClubItem = {}
        tClubItem.nClubId = v.nClubId
        tClubItem.sClubName = v.sClubName
        tClubItem.nMaster = v.nMaster
        tClubItem.nClubGold = v.nClubGold
        tClubItem.nCanApply = v.nCanApply
        tClubItem.nCanSearch = v.nCanSearch
        tClubItem.nIncome = v.nIncome
        tClubItem.nUserCnt = v.nUserCnt
        tClubItem.nGroupId = v.nGroupId
        tClubItem.sCreateTime = v.sCreateTime
        tClubItem.sPassWord = v.sPassWord
        tClubItem.nApplyJionCnt = v.nApplyJionCnt
        tClubItem.nApplyAddGoldCnt = v.nApplyAddGoldCnt
        tClubItem.nApplyCutGoldCnt = v.nApplyCutGoldCnt
        tClubItem.sFaceId = v.sFaceId
        tClubItem.sName = v.sName
        tClubItem.nSex = v.nSex
        tClubItem.sShopAcc = v.sShopAcc
        tClubItem.nGold = v.nGold
        tClubItem.nGoldIncome = v.nGoldIncome
        

        if tClubItem.nClubId and tClubItem.nClubId>0 then
            local tClubC = ClubManager.GetClub(tClubItem.nClubId)
            if not tClubC then
                MsgHandle.ReCorverClub(tClubItem)
            end
            tClubId[tClubItem.nClubId] = ServerInfo.nServerId
            table.insert(arrClubId,tClubItem.nClubId)
        end
    end
    --保存俱乐部所在中心服id
    PublicRedis.SetClubCenterServer(tClubId)

    --俱乐部id从小到大排序
    if #arrClubId>1 then
        table.sort(arrClubId,function (a, b)
            return a < b
        end)
        MsgHandle.DBLoadClubUserReq(arrClubId)
    end

    --最后一个俱乐部id
    local nLastClubId = arrClubId[#arrClubId] or -1

    local tClubReqQueue = CenterData.arrClubReqQueue[1]
    if tClubReqQueue then
        if #arrClubId < tData.nLimitCnt then
            --不足每次请求的数目，这一项的俱乐部已经取完，可以删除
            table.remove(CenterData.arrClubReqQueue,1)
        else
            --更新这一项的已获取的最大俱乐部id
            tClubReqQueue.nMinClubId = nLastClubId
        end
    end

    Base.Log("_OnDBClubDataRsp #arrClubId:%d nLastClubId:%d nMinClubId:%d nMaxClubId:%d nLimitCnt:%d",
    #arrClubId,nLastClubId,tData.nMinClubId,tData.nMaxClubId,tData.nLimitCnt)

    --延迟检查是否还要请求俱乐部数据
    if not CenterData.tTimerId.CheckNeedToReqClubData then
        CenterData.tTimerId.CheckNeedToReqClubData = TimerAux.GetATimerId()
        Base.Log("CenterData.tTimerId.CheckNeedToReqClubData:%d",CenterData.tTimerId.CheckNeedToReqClubData)
    end
    Base.SetTimer(CenterData.tTimerId.CheckNeedToReqClubData, 1000*Define.nReqClubDelay, 1, MsgHandle.CheckNeedToReqClubData)
end

--DB服 修改俱乐部资产同步
function MsgHandle.OnDBClubAssetChangeNotify(sReturnKey, Data, nLen)
    local tData =DbClubServAux:Parser(Data, nLen,"ClubAssetChangeNotify")
    if tData ==nil then
        Base.Log("_OnDBClubAssetChangeNotify _Parse Err")
        return
    end
    local tClubC = ClubManager.GetClub(tData.nClubId)
    if not tClubC then
        Base.Log("_OnDBClubAssetChangeNotify  nClubId: %d tClubC is nil",tData.nClubId)
        return
    end
    local nOldClubGold =tData.nClubGold
    local nClubGold = PublicUserInfo._GetClubSumAsset(tData.nClubId,tData.nItemId)
    if nClubGold ~= tData.nClubGold then
        tData.nClubGold = nClubGold
    end 
    tClubC:Print("_OnDBClubAssetChangeNotify  nClubId: %d 修改俱乐部资产同步 nItemId:%d nClubGold: %f  nOldClubGold: %f  ",tData.nClubId,tData.nItemId,nClubGold,nOldClubGold)
    local tChangeInfo = {nClubGold=nClubGold}
    if tData.nItemId==1 then
        tChangeInfo = {nGold=nClubGold}
    end
    tClubC:_OnClubCSceneChangeReq(sReturnKey,{nClubId=tData.nClubId,sChangeInfo=Cjson.encode(tChangeInfo)})
    return  1
end


--从数据库恢复俱乐部
--@params tData 俱乐部数据
--@return tClubC 俱乐部对象
function MsgHandle.ReCorverClub(tData)
    local tClubC = ClubManager.CreateClub(tData.nGroupId,tData.nClubId)
    if tClubC then
        tClubC:InitScene(tData) --初始化场景
        tClubC:SceneNotify() --场景广播给所有游戏服
        tClubC:TableNotify() --通知牌桌
    end
    return tClubC
end

--创建俱乐部大厅
--@params arrGroup 分组数组
function MsgHandle.ReCorverClubHall(arrGroup)
    local arrClubId = {}
    for _,nGroupId in pairs(arrGroup) do
        local tHallData = {}
        tHallData.nClubId = nGroupId
        tHallData.sClubName = "SGFsbA=="
        tHallData.nGroupId = nGroupId
        MsgHandle.ReCorverClub(tHallData)

        arrClubId[nGroupId] = ServerInfo.nServerId
    end
    --把俱乐部大厅所在中心服存到redis
    PublicRedis.SetClubCenterServer(arrClubId)
end

--从服连接请求
function MsgHandle.OnClubCConnectReq(sReturnKey,Data,nLen)
    local tData =CenterAux:Parser(Data, nLen,"ClubCConnectReq")
    if not tData then
        Base.Log("ClubCConnectReq _Parse Err")
        return
    end

    local isRefresh = MsgApi.AddSlaveServ(tData.nServerId,sReturnKey)
    Base.Log("ClubCConnectReq 从服连接请求 nServerId_%d sReturnKey_%s isRefresh_%s",tData.nServerId,sReturnKey,tostring(isRefresh))

    if isRefresh == true then
        --从服key刷新，需要通知从服俱乐部场景
        local arrClub = ClubManager.GetAllClub()
        for _,tClubC in pairs(arrClub) do
            tClubC:SceneNotify(sReturnKey)
            tClubC:TableNotify(sReturnKey) --通知牌桌
        end

        --通知从服分组id
        local ClubCServerGroupNotify = {}
        ClubCServerGroupNotify.arrGroup = CenterData.arrGroup
        MsgApi.SendToSlaveServer(sReturnKey,"ClubCServerGroupNotify",ClubCServerGroupNotify) 
    end
end

--创建俱乐部请求
function MsgHandle.OnClubCCreateSucessReq(sReturnKey,Data,nLen)
    local tData =CenterAux:Parser(Data, nLen,"ClubCCreateSucessReq")
    if not tData then
        Base.Log("ClubCCreateSucessReq _Parse Err")
        return
    end 

    Base.Log("_OnClubCCreateSucessReq 玩家创建俱乐部成功,中心服创建俱乐部 sClubInfo_%s",tData.sClubInfo)
    local isSuccee,tClubItem = pcall(Cjson.decode,tData.sClubInfo)
    if isSuccee then
        for _,nGroupId in pairs(CenterData.arrGroup) do
            if tClubItem.nGroupId==nGroupId then
                local tClubC = ClubManager.GetClub(tClubItem.nClubId)
                if not tClubC then
                    MsgHandle.ReCorverClub(tClubItem)
                end
                --保存俱乐部所在中心服id
                local arrClubId = {}
                arrClubId[tClubItem.nClubId] = ServerInfo.nServerId
                PublicRedis.SetClubCenterServer(arrClubId)
                break
            end
        end
    else
        Base.Log("_OnClubCCreateSucessReq decode sClubInfo fail")
    end
    
end

function MsgHandle._OnMsgHandle(strReq,sReturnKey,Data,nLen)
    local tData =CenterAux:Parser(Data, nLen,strReq)
    assert(tData~=nil and tData.nClubId~=nil)
    local tClubC = ClubManager.GetClub(tData.nClubId)
    if tClubC==nil then
       Base.Log(" _OnMsgHandle  nClubId_%d   strReq_%s   tClubC  is nil  ",tData.nClubId,strReq) 
       return
    end
    tClubC:OnSlaveMsgHandle(sReturnKey,strReq,tData)
end

--俱乐部场景信息改变请求
function MsgHandle.OnClubCSceneChangeReq(sReturnKey,Data,nLen)
    MsgHandle._OnMsgHandle("ClubCSceneChangeReq",sReturnKey,Data,nLen)
end

--游戏服开桌通知
function MsgHandle.OnClubCGameOpenTableNotify(sReturnKey,Data,nLen)
    MsgHandle._OnMsgHandle("ClubCGameOpenTableNotify",sReturnKey,Data,nLen)
end

--游戏服关桌通知
function MsgHandle.OnClubCGameCloseTableNotify(sReturnKey,Data,nLen)
    MsgHandle._OnMsgHandle("ClubCGameCloseTableNotify",sReturnKey,Data,nLen)
end

--游戏服牌桌信息改变通知
function MsgHandle.OnClubCGameTableInfoNotify(sReturnKey,Data,nLen)
    MsgHandle._OnMsgHandle("ClubCGameTableInfoNotify",sReturnKey,Data,nLen)
end

--游戏服玩家结算通知
function MsgHandle.OnClubCGameUserSettleNotify(sReturnKey,Data,nLen)
    MsgHandle._OnMsgHandle("ClubCGameUserSettleNotify",sReturnKey,Data,nLen)
end

--后台开桌请求
function MsgHandle.OnWebOpenClubTableReq(sReturnKey,Data,nLen)
    local tData =BackstageAux:Parser(Data, nLen,"WebOpenClubTableReq")
    if not tData then
        Base.Log("WebOpenClubTableReq _Parse Err")
        return
    end
    Base.Log("_OnWebOpenClubTableReq 后台开桌请求 nClubId_%d,nGroupId_%d,nGameId_%d,sConfig_%s",
    tData.nClubId,tData.nGroupId,tData.nGameId,tData.sConfig)
    if tData.nClubId==0 then
        tData.nClubId = tData.nGroupId
        Base.Log("_OnWebOpenClubTableReq 开大厅桌子 nClubId_%d",tData.nClubId)
    end

    local sKey = tData.sRequestkey
    local tReturnData = {}
    tReturnData.nErrorCode = PubErrCode.OpenTable.Success

    local isSuccee,tConfig = pcall(Cjson.decode,tData.sConfig)
    if not isSuccee then
        Base.Log("_OnWebOpenClubTableReq decode sConfig fail")
        tReturnData.nErrorCode = PubErrCode.OpenTable.ParamsErr
        MsgApi.SendWebOprateResult(sKey,tReturnData)
        return
    end

    local tClub = ClubManager.GetClub(tData.nClubId)
    if not tClub then
        Base.Log("_OnWebOpenClubTableReq 俱乐部不存在")
        tReturnData.nErrorCode = PubErrCode.OpenTable.NoClub
        MsgApi.SendWebOprateResult(sKey,tReturnData)
        return
    end

    --检查公共开桌参数
    local nRlt = PubClubApi.CheckOpenTable(tClub,tConfig)
    if nRlt~=PubErrCode.OpenTable.Success then
        tReturnData.nErrorCode = nRlt
        MsgApi.SendWebOprateResult(sKey,tReturnData)
        return
    end
    local nItemId = 1
    if tConfig.nGoldType==2 then
        --使用俱乐部币
        nItemId=tData.nClubId
    elseif tConfig.nGoldType==3 then
        --使用积分
        nItemId=0
    end

    local tRoomConfig = {
        nClubId = tData.nClubId, --俱乐部id
        nItemId = nItemId, --使用的货币id 0:积分 1:金币 1000000~:俱乐部币
        nKeepTime = tonumber(tConfig.nKeepTime) or 1800, --房间时长
        nGoldType = tConfig.nGoldType, --使用的金币类型 1:金币 2:俱乐部币 3:积分
        -- isNeedAndroid = PubClubApi.IsUseAndroid(tClub,tConfig.nGoldType), --是否加载机器人
        isNeedAndroid = tConfig.isNeedAndroid or false, --是否加载机器人
        sClubName = tClub.sClubName, --俱乐部名称
        nGameId = tData.nGameId, --游戏id         
        nContinuedNum = tonumber(tConfig.nContinuedNum or 0),    -- 补开数量 
    }

    if PublicApi.IsTexasClassGame(tData.nGameId)  then --德州,短牌,奥马哈
        --参数校验
        local nRlt = PubClubApi.CheckTexasPubOpenTable(tConfig)
        if nRlt~=PubErrCode.OpenTable.Success then
            tReturnData.nErrorCode = nRlt
            MsgApi.SendWebOprateResult(sKey,tReturnData)
            return
        end

        --短牌
        if tData.nGameId==Define.GameList.nTexasShortCard.nGameId then
            nRlt = PubClubApi.CheckTexasShortCardOpenTable(tConfig)
            if nRlt~=PubErrCode.OpenTable.Success then
                tReturnData.nErrorCode = nRlt
                MsgApi.SendWebOprateResult(sKey,tReturnData)
                return
            end

            tRoomConfig.isDPreAnte = tConfig.isDPreAnte --庄家是否要下两倍前注 true:开启 false:关闭
        elseif tData.nGameId==Define.GameList.nTexas.nGameId or tData.nGameId==Define.GameList.nTexasOmaha.nGameId then
            --德州，奥马哈
            local nRlt = PubClubApi.CheckTexasOpenTable(tConfig)
            if nRlt~=PubErrCode.OpenTable.Success then
                tReturnData.nErrorCode = nRlt
                MsgApi.SendWebOprateResult(sKey,tReturnData)
                return
            end
        end

        tRoomConfig.nSmallBlind = tConfig.nSmallBlind --小盲
        tRoomConfig.nBigBlind = tConfig.nBigBlind--大盲
        tRoomConfig.nTakeIn = tConfig.nTakeIn--默认带入
        tRoomConfig.nTakeInMin = tConfig.nTakeIn--最低带入
        tRoomConfig.nTakeInMax = tConfig.nTakeIn--最高带入
        tRoomConfig.nCapacity = tConfig.nCapacity--人数
        tRoomConfig.nPreAnte = tConfig.nPreAnte--前注
        tRoomConfig.tAutostart = tConfig.tAutostart--自动开始设置
        tRoomConfig.nMinTabkeInBB = tConfig.nMinTabkeInBB--带入筹码倍数最小值
        tRoomConfig.nMaxTabkeInBB = tConfig.nMaxTabkeInBB--带入筹码倍数最大值
        tRoomConfig.nPoolEntryRate = tConfig.nPoolEntryRate--入池率
        tRoomConfig.isOnlyPlayByIOS = tConfig.isOnlyPlayByIOS--true:只能IOS设备玩 fasle:所有设备都能玩
        tRoomConfig.isForceBlind = tConfig.isForceBlind--强制盲注 true:开启 false:关闭
        tRoomConfig.isGPSLimit = tConfig.isGPSLimit--GPS限制
        tRoomConfig.isIPLimit = tConfig.isIPLimit--IP限制
        tRoomConfig.isAOF = tConfig.isAOF--全下或弃牌
        tRoomConfig.isDelayLook = tConfig.isDelayLook--延迟看牌
        tRoomConfig.nInsureMode = tConfig.nInsureMode--保险模式 0:无保险 1:传统保险 2:低水保险
        tRoomConfig.tDrawWaterMode = tConfig.tDrawWaterMode--抽水模式
        tRoomConfig.isTabkeOut = tConfig.isTabkeOut--是否开启带出筹码功能
        tRoomConfig.nZhuaTou = tConfig.nZhuaTou
        tRoomConfig.preAnteOdd = tConfig.preAnteOdd --庄家n倍数前注
        tRoomConfig.nLoseMaxAmount = tConfig.nLoseMaxAmount --输钱限制
        tRoomConfig.nTabkeOutOdd = tConfig.nTabkeOutOdd--撤码阈值的倍数N
        tRoomConfig.nTableCost = tConfig.nTableCost   --牌桌消耗
        tRoomConfig.nIsPerson = tConfig.nIsPerson                            --是否私人房间
        tRoomConfig.nIsShow = tConfig.nIsShow or 1                           --是否显示房间
        tRoomConfig.sPassWord = tConfig.sPassWord                            --私人房间密码
        tRoomConfig.isVideoFee = tConfig.isVideoFee                          --是否开启语聊收费
        tRoomConfig.nVideoFee = tConfig.nVideoFee                            --语聊收费价格
        tRoomConfig.nPoolHands = tConfig.nPoolHands                          --手数限制
        tRoomConfig.nPoolEntryRateHands = tConfig.nPoolEntryRateHands        --入池率多少手不限制
        tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit                      --补码上限值
        if tConfig.nTakeInLimit and tConfig.nTakeInLimit > 0 then
            --有设置补码上限值，计算补码: 补码 = 补码* 最大买入BB * 大盲
            tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit * tConfig.nMaxTabkeInBB * tConfig.nBigBlind
        end
        if tData.nGameId==Define.GameList.nTexasShortCard.nGameId then
            if tConfig.preAnteOdd ~= nil then
            --有设置PreAntOdd，计算补码: 补码 = 补码* 最大买入BB * 庄家N倍前注
                tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit * tConfig.nMaxTabkeInBB * tConfig.preAnteOdd * tConfig.nPreAnte
            elseif (tRoomConfig.nTakeInLimit and tRoomConfig.nTakeInLimit > 0) and tConfig.nBigBlind > 0 then
                tRoomConfig.nTakeInLimit = tConfig.nTakeInLimit * tConfig.nMaxTabkeInBB * tConfig.nBigBlind
            end
        end
        
        if tConfig.tLeaveTableConfig ~= nil and tConfig.tLeaveTableConfig.isOpen then
            tRoomConfig.tLeaveTableConfig = {
                isOpen = tConfig.tLeaveTableConfig.isOpen,
                nWinThreshold = tConfig.tLeaveTableConfig.nWinThreshold, -- 赢钱阈值, 超过阈值时会触发离桌限制
                nLots = tConfig.tLeaveTableConfig.nLots, -- 离桌限制局数, 当赢钱达到阈值时, 需要超过限制手数才不会触发离桌限制
                nPenaltyRatio = tConfig.tLeaveTableConfig.nPenaltyRatio, -- 罚款比例, 只罚赢钱部分
                nUserRatio = tConfig.tLeaveTableConfig.nUserRatio, -- 同桌玩家分配比例, 罚款金额中的占比,平均分配给牌桌上的人
                nType = tConfig.tLeaveTableConfig.nType or 0  -- 罚款触发模式 0: 返回大厅罚款 1: 站起罚款
            }
        end
    elseif tData.nGameId == Define.GameList.nClubQiangZhuangNiu.nGameId then
        --参数校验
        local nRlt = PubClubApi.CheckQZNiuOpenTable(tConfig)
        if nRlt~=PubErrCode.OpenTable.Success then
            tReturnData.nErrorCode = nRlt
            MsgApi.SendWebOprateResult(sKey,tReturnData)
            return
        end
        tRoomConfig.nCapacity = tConfig.nCapacity--人数
        tRoomConfig.tAutostart = tConfig.tAutostart--自动开始设置
        tRoomConfig.nAnte = tConfig.nAnte--底分
        tRoomConfig.HuType = tConfig.HuType--牌型倍率
        tRoomConfig.nTax = tConfig.nTax--抽水
        tRoomConfig.nNModeType = tConfig.nNModeType --抽水类型
    end

    -- tRoomConfig.nKeepTime = 60 * 2   -- 调试 
    
	local nOpenTableCfgId = tostring(tConfig.nOpenTableCfgId or os.time())		--开桌配置id 

    if tConfig.isAutomatic then                                  -- 自动续开
        tRoomConfig.sServerKey = Base.m_tKey                     -- 俱乐部中心服 key 关桌需要用
        tRoomConfig.isAutomatic = tConfig.isAutomatic            -- 自动续开
    end
    if tConfig.automatic then                         -- 自动开桌
        tRoomConfig.sServerKey = Base.m_tKey          -- 俱乐部中心服 key 关桌需要用
        tRoomConfig.automatic = tConfig.automatic     -- 自动开桌
        tRoomConfig.automaticCount = tConfig.automaticCount
    end
    local tSendData = {}
    tSendData.nType = 1
    tSendData.nRoomId = 2
    tSendData.nLiveUserID = 0
    tSendData.nOpentime = os.time()
    tSendData.sRequestkey = nOpenTableCfgId
    tSendData.nGroupId = tData.nGroupId
    tSendData.sTableName = B_Encode(tConfig.sTableName)
    tSendData.nTableType = 5
    tRoomConfig.nRoomId = tSendData.nRoomId
    tSendData.sConfig = Cjson.encode(tRoomConfig)
    local nOpenCount = 1    -- 开桌数量
    if tConfig.nOpenCount and tonumber(tConfig.nOpenCount) > 0 and tonumber(tConfig.nOpenCount) <= 100 then
        nOpenCount = tonumber(tConfig.nOpenCount)
    end
    local nContinuedNum = 0    -- 补桌数量
    if tConfig.nContinuedNum and tonumber(tConfig.nContinuedNum) > 0 and tonumber(tConfig.nContinuedNum) <= 100 then
        nContinuedNum = tonumber(tConfig.nContinuedNum)
    end
    -- local sTableNo = 1 -- 开桌序号
    -- if tConfig.sTableNo and tonumber(tConfig.sTableNo) > 0 and tonumber(tConfig.sTableNo) < 9000000 then 
    --     sTableNo =tonumber(tConfig.sTableNo) -1  -- 初始化牌桌序号
    -- end
    -- PublicRedis._HandleClubOpenTableNameCount(1,tData.nGroupId,tData.nGameId,nOpenTableCfgId,math.floor(sTableNo)) 
    local arrTableIndex = {}
    for i = 1, nOpenCount, 1 do
        local nIndex = PublicRedis._HandleClubOpenTableNameCount(2,tData.nGroupId,tData.nGameId,nOpenTableCfgId)
        table.insert(arrTableIndex,nIndex)
    end
    -- 保存持久化配置
    local tCfg = {}
    tCfg.nServerId = ServerInfo.nServerId
    tCfg.nOpenTableCfgId = nOpenTableCfgId                         -- 开桌配置id
    tCfg.isConfigSwitch = tConfig.isConfigSwitch or true           -- 配置开关: true、false 
    tCfg.nOpenCount = nOpenCount                                   -- 开桌数量
    tCfg.nContinuedNum = nContinuedNum                             -- 补桌数量:  该配置的所有牌桌 都开始游戏就自动补桌
    tCfg.isAutomatic =  tConfig.isAutomatic or false               -- 是否超时关桌后自动续开
    tCfg.automatic = tConfig.automatic or false          -- 是否开始游戏是自动开桌
    tCfg.automaticCount = tConfig.automaticCount or tConfig.nCapacity
    tCfg.automaticRatio = tConfig.automaticRatio or ""    -- 不参与业务,只是后台配置界面展示时使用
    tCfg.sTableName = tConfig.sTableName
    tCfg.nClubId = tData.nClubId
    tCfg.tSendData = tSendData
    tCfg.tRoomConfig = tRoomConfig

    PublicRedis._HandleClubTableCongfig(1, tData.nGroupId, tData.nClubId, tData.nGameId, nOpenTableCfgId, tCfg)

    local arrSuccess={}
    for _, nIndex in ipairs(arrTableIndex) do
        local sName = string.format("%s-%d",tConfig.sTableName,nIndex)
        local sTableName = B_Encode(sName)
        local sServerKey = MsgApi._GetGameServerKey(tData.nGameId,tData.nClubId,sTableName)
        if sServerKey then
            tSendData.sTableName = sTableName
            MsgApi.SendToGameServer(sServerKey, tSendData)
            table.insert(arrSuccess, sName)
            tClub:_AddTableInfo(tData.nGameId, nOpenTableCfgId, sName, tCfg.isAutomatic, tCfg.automatic,
                tCfg.automaticCount)
        end
    end
    tClub:Print("_OnWebOpenClubTableReq  nGroupId[%d_%d_%d] nOpenCount_%d 补桌_%d 牌桌名: %s "
    ,tData.nGroupId,tData.nClubId,tData.nGameId,nOpenCount,tConfig.nContinuedNum or 0,Cjson.encode(arrSuccess))

    MsgApi.SendWebOprateResult(sKey,tReturnData)
    return
end

--后台关桌请求
function MsgHandle.OnWebCloseClubTableReq(sReturnKey,Data,nLen)
    local tData =BackstageAux:Parser(Data, nLen,"WebCloseClubTableReq")
    if not tData then
        Base.Log("WebCloseClubTableReq _Parse Err")
        return
    end

    Base.Log("_OnWebCloseClubTableReq 后台关桌请求 nClubId:%d,nGroupId:%d,nGameId_%d,sTableId:%s"
    ,tData.nClubId,tData.nGroupId,tData.nGameId,tData.sTableId)
    local tReturnData = {}
    tReturnData.nErrorCode = PubErrCode.CloseTable.Success
    local tSendData = {}
    tSendData.nType = 2
    tSendData.nRoomId = 2
    tSendData.nLiveUserID = 0
    tSendData.nOpentime = 0
    tSendData.sRequestkey = tData.sRequestkey
    tSendData.sTableId = tData.sTableId
    local isSendSucess = MsgApi.SendCloseTableToGame(tSendData)
    if not isSendSucess then
        Base.Log("_OnWebCloseClubTableReq not find Game Center server")
        tReturnData.nErrorCode = PubErrCode.CloseTable.NoServer
        MsgApi.SendWebOprateResult(sKey,tReturnData)
        return
    end
    PublicRedis._HandleClubTable_WebClose(tData.sTableId,1,ServerInfo.nServerId)
end

-- 重启服务器 恢复开桌
function MsgHandle._RestartTable()
	local Redis = Base.m_MyRedisData[2].redis
	local sKey = string.format("ClubTableCfg_OpenTable_*")
    local arrKey = Redis:keys(sKey)
    Base.Log("_RestartTable  重启恢复   arrKey:%d  %s ",#arrKey,Cjson.encode(arrKey))
    for k,sKey in pairs(arrKey) do
        local arrTableCfg = Redis:hgetall(sKey)
        for sSubKey, tTableCfg in pairs(arrTableCfg) do
            repeat
                if tTableCfg then
                    local tCfg = Cjson.decode(tTableCfg)
                    local nClubId = tCfg.nClubId
                    if nClubId then
                        local tClub = ClubManager.GetClub(nClubId)
                        if not tClub then
                            Base.Log("_RestartTable 俱乐部不存在 nClubId "..nClubId)
                            break
                        end
                        tClub:_ReStartRecover(tCfg)
                    else
                        Base.Log("_RestartTable  nClubId  is nil  nClubId: "..nClubId)
                    end
                else
                    Base.Log("_RestartTable tTableCfg is nil   sKey: "..sKey)
                end
            until true
        end
    end
end

--定时广播分组id
function MsgHandle.BroadcastGroup()
    local ClubCServerGroupNotify = {}
    ClubCServerGroupNotify.arrGroup = CenterData.arrGroup
    MsgApi.Broadcast("ClubCServerGroupNotify",ClubCServerGroupNotify) 
end

--后台修改配置通知回调
function MsgHandle.OnWebRedisNotifyCallBack(arrKey)
    local isChange = false
    Base.Log("_OnWebRedisNotifyCallBack")
    for _,skey in pairs(arrKey) do
        if string.match(skey,"ClubConfig_Group") then
            isChange = true
        end
        if isChange then
            Base.Log("_OnWebRedisNotifyCallBack 后台修改的skey:%s",skey)
            MsgHandle.UpdateClubConfig()
            break
        end
    end
end

return MsgHandle
