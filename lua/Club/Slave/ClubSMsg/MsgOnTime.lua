--消息定时处理
local MsgOnTime = {}

MsgOnTime.arrQueue = {} --消息队列

--插入消息队列
--@params tData = {MsgType=消息类型,nSpacetime=检测时间间隔,...}
function MsgOnTime.Push(tData)
    tData.nCheckTime = os.time()
    tData.nSpacetime = tData.nSpacetime or 1 --没传检测时间间隔，默认1秒
    table.insert(MsgOnTime.arrQueue,tData)
end

function MsgOnTime.Check()
    --处理踢出，回收俱乐部币以及同意退还俱乐部币申请
    local nLen_Queue = #MsgOnTime.arrQueue --消息队列长度
    local nNowTime = os.time()
    if nLen_Queue>0 then
        for i=nLen_Queue,1,-1 do
            local tData = MsgOnTime.arrQueue[i]
            if nNowTime-tData.nCheckTime>=tData.nSpacetime then
                tData.nCheckTime = nNowTime
                if tData.MsgType==Define.MsgType.KickOut then
                    --踢出俱乐部
                    local nCurGameId = PublicUserInfo.GetUserPlayingGame(tData.nTUserId)
                    if not nCurGameId or nCurGameId==0 then
                        MsgOnTime.HandleKickOut(tData)
                        table.remove(MsgOnTime.arrQueue,i)
                    end
                elseif tData.MsgType==Define.MsgType.Recycling then
                    --回收玩家俱乐部币
                    local nCurGameId = PublicUserInfo.GetUserPlayingGame(tData.nTUserId)
                    if not nCurGameId or nCurGameId==0 then
                        MsgOnTime.HandAdminDelGold(tData)
                        table.remove(MsgOnTime.arrQueue,i)
                    end
                elseif tData.MsgType==Define.MsgType.DelApply then
                    --处理玩家退还俱乐部币申请
                    local nCurGameId = PublicUserInfo.GetUserPlayingGame(tData.nTUserId)
                    if not nCurGameId or nCurGameId==0 then
                        MsgOnTime.HandDelGoldApply(tData)
                        table.remove(MsgOnTime.arrQueue,i)
                    end
                elseif tData.MsgType==Define.MsgType.OpenTable then
                    --处理玩家开桌超时
                    if nNowTime-tData.nOpentime > Define.nOverTime then
                        MsgApi.SendToUser(tData.nUserId,"ClubSOpenTableResp",{nRlt=PubErrCode.OpenTable.OverTime})
                        Base.Log("处理玩家开桌超时 %s",Cjson.encode(tData))
                        table.remove(MsgOnTime.arrQueue,i)
                    end
                elseif tData.MsgType==Define.MsgType.CloseTable then
                     --处理玩家关桌超时
                     if nNowTime - tData.nOpentime > Define.nOverTime then
                        MsgApi.SendToUser(tData.nUserId,"ClubSCloseTableResp",{nRlt=PubErrCode.CloseTable.OverTime})
                        Base.Log("处理玩家关桌超时 %s",Cjson.encode(tData))
                        table.remove(MsgOnTime.arrQueue,i)
                    end
                end
            end
        end 
    end
end

--是否有还没处理的操作
--@params tData = {nClubId,nTUserId,nType,nOpUserId}
function MsgOnTime.HasUnDealMsg(tData)
    tData = tData or {}
    for k,v in pairs(MsgOnTime.arrQueue) do
        if tData.MsgType==Define.MsgType.KickOut or tData.MsgType==Define.MsgType.Recycling then
            if v.nClubId==tData.nClubId and v.nTUserId==tData.nTUserId 
            and v.nType==tData.nType and v.nOpUserId==tData.nOpUserId then
                return true
            end
        end
    end
    return false
end

--是否有在等待结果的消息
--@params tData = {nClubId,nUserId,MsgType}
function MsgOnTime.HasWaitingMsg(tData)
    tData = tData or {}
    for k,v in pairs(MsgOnTime.arrQueue) do
        if tData.MsgType==Define.MsgType.OpenTable then
            if v.nClubId==tData.nClubId and v.nUserId==tData.nUserId and v.MsgType==tData.MsgType  then
                return true
            end
        elseif tData.MsgType==Define.MsgType.CloseTable then
            if v.nClubId==tData.nClubId and v.nUserId==tData.nUserId and v.MsgType==tData.MsgType and v.sTableId==tData.sTableId then
                return true
            end
        end
    end
    return false
end

--删除等待结果的消息
--@params tData = {nClubId,nUserId,MsgType,sTableId}
function MsgOnTime.DelWaitingMsg(tData)
    tData = tData or {}
    local nUserId = nil
    local nItemId = nil
    local nCount = nil
    for k,v in ipairs(MsgOnTime.arrQueue) do
        if tData.MsgType==Define.MsgType.OpenTable then
            if v.nClubId==tData.nClubId and v.nUserId==tData.nUserId and v.MsgType==tData.MsgType  then
                nUserId = tData.nUserId
                nItemId = v.nConsumeItemId
                nCount = v.nConsume
                table.remove(MsgOnTime.arrQueue,k)
                break
            end
        elseif tData.MsgType==Define.MsgType.CloseTable then
            if v.nClubId==tData.nClubId and v.MsgType==tData.MsgType and v.sTableId==tData.sTableId then
                nUserId = v.nUserId
                table.remove(MsgOnTime.arrQueue,k)
                break
            end
        end
    end
    return nUserId,nItemId,nCount
end

--处理管理员踢出玩家
-- tData {nClubId=俱乐部id,nTUserId=被操作者id,nType=操作类型,nOpUserId=管理员id,}
function MsgOnTime.HandleKickOut(tData)
    Base.Log("_HandleKickOut 定时任务,处理管理员踢出玩家 nClubId:%d nUserId:%d nTUserId:%d nType:%d",
    tData.nClubId,tData.nOpUserId,tData.nTUserId,tData.nType)

    local tNewData ={}
    tNewData.nClubId = tData.nClubId
    tNewData.nType = tData.nType
    tNewData.nTUserId = tData.nTUserId
    MsgClient.HandleAdminOperate(tData.nOpUserId,tNewData)
end

--处理管理员回收俱乐部币
-- tData {nClubId=俱乐部id,nTUserId=被操作者id,nType=操作类型,nOpUserId=管理员id,nChange=修改值,sPassWord=库存密码}
function MsgOnTime.HandAdminDelGold(tData)
    Base.Log("_HandAdminDelGold 定时任务,处理管理员回收俱乐部币 nClubId:%d nUserId:%d nTUserId:%d nType:%d  nChange:%f sPassWord:%s",
    tData.nClubId,tData.nOpUserId,tData.nTUserId,tData.nType,tData.nChange or 0,tData.sPassWord or "")

    local tNewData ={}
    tNewData.nClubId = tData.nClubId
    tNewData.nType = tData.nType
    tNewData.nTUserId = tData.nTUserId
    tNewData.nChange = tData.nChange
    tNewData.sPassWord = tData.sPassWord
    MsgClient.HandleAdminOperate(tData.nOpUserId,tNewData)
end

--处理玩家退还俱乐部币申请
-- tData {nClubId=俱乐部id,nTUserId=被操作者id,nOpUserId=管理员id,nChange=修改值}
function MsgOnTime.HandDelGoldApply(tData)
    Base.Log("_HandDelGoldApply 定时任务,处理玩家退还俱乐部币申请 nId:%d nClubId:%d nUserId:%d nTUserId:%d nType:%d  nChange:%f sPassWord:%s",
    tData.nId,tData.nClubId,tData.nOpUserId,tData.nTUserId,tData.nType,tData.nChange,tData.sPassWord)

    local tNewData ={}
    tNewData.nClubId = tData.nClubId
    tNewData.nId = tData.nId
    tNewData.nType = tData.nType
    tNewData.nOpType = 1
    tNewData.sPassWord = tData.sPassWord
    MsgClient.HandleApply(tData.nOpUserId,tNewData)
end

--定时更新俱乐部配置
function MsgOnTime.UpdateClubConfig()
    for _,nGroupId in pairs(SlaveData.arrGroup) do
        local nGold,nFreeCnt = RedisCahche.GetChangeUserInfoConsume(nGroupId) --修改名字消耗
        local nCount,nGoldType = RedisCahche.GetOpenTableConsume(nGroupId) --开桌消耗
        local arrLevel = RedisCahche.GetLevelConfig(nGroupId) --等级配置

        local isNotify = false --是否需要通知玩家配置改变
        local tChangeInfo = {}

        --修改名字消耗
        if not SlaveData.arrChangeNameConsume[nGroupId] then
            isNotify = true
            SlaveData.arrChangeNameConsume[nGroupId] = {nItemId=1,nCount=nGold or Define.tChangeName.nCount}
            tChangeInfo.tChangeName = SlaveData.arrChangeNameConsume[nGroupId]
        elseif nGold and SlaveData.arrChangeNameConsume[nGroupId].nCount~=nGold then
            isNotify = true
            SlaveData.arrChangeNameConsume[nGroupId].nCount=nGold
            tChangeInfo.tChangeName = SlaveData.arrChangeNameConsume[nGroupId]
        end

        --开桌消耗
        if not SlaveData.arrOpenTableConsume[nGroupId] then
            isNotify = true
            SlaveData.arrOpenTableConsume[nGroupId] = {nGoldType=nGoldType or Define.tOpenTableConsume.nGoldType,nCount=nCount or Define.tOpenTableConsume.nCount}
            tChangeInfo.tOpenTable = SlaveData.arrOpenTableConsume[nGroupId]
        elseif nGoldType and SlaveData.arrOpenTableConsume[nGroupId].nGoldType~=nGoldType then
            isNotify = true
            SlaveData.arrOpenTableConsume[nGroupId].nGoldType=nGoldType
            tChangeInfo.tOpenTable = SlaveData.arrOpenTableConsume[nGroupId]
        elseif nCount and SlaveData.arrOpenTableConsume[nGroupId].nCount~=nCount then
            isNotify = true
            SlaveData.arrOpenTableConsume[nGroupId].nCount=nCount
            tChangeInfo.tOpenTable = SlaveData.arrOpenTableConsume[nGroupId]
        end

        if not SlaveData.arrLevelConfig[nGroupId] then
            isNotify = true
            SlaveData.arrLevelConfig[nGroupId] = arrLevel or PublicApi.Clone(Define.arrLevel)
            tChangeInfo.arrLevel = SlaveData.arrLevelConfig[nGroupId]
        elseif arrLevel and #arrLevel~=#SlaveData.arrLevelConfig[nGroupId] then
            isNotify = true
            SlaveData.arrLevelConfig[nGroupId] = arrLevel
            tChangeInfo.arrLevel = SlaveData.arrLevelConfig[nGroupId]
        elseif arrLevel and #arrLevel==#SlaveData.arrLevelConfig[nGroupId] then
            local isChaneg = false
            local nLen1 = #arrLevel
            for i=1,nLen1 do
                local tNew = arrLevel[i]
                local tOld = SlaveData.arrLevelConfig[nGroupId][i]
                if tNew[1]~=tOld[1] or tNew[2]~=tOld[2] then
                    isChaneg = true
                    break
                end
            end
            if isChaneg then
                isNotify = true
                SlaveData.arrLevelConfig[nGroupId] = arrLevel
                tChangeInfo.arrLevel = SlaveData.arrLevelConfig[nGroupId]
            end
        end

        SlaveData.arrFreeCnt[nGroupId] = nFreeCnt or Define.nFreeCnt

        if isNotify then
            local ClubSGetClubConfigNotify = {}
            ClubSGetClubConfigNotify.schangeConfig = Cjson.encode(tChangeInfo)
            local arrClientID = UserManager.GetAllUserClientID()
            MsgApi.SendToGateWay("ClubSGetClubConfigNotify",ClubSGetClubConfigNotify,arrClientID)
            Base.Log("_UpdateClubConfig %s",ClubSGetClubConfigNotify.schangeConfig)
        end
    end
end

--后台修改配置通知回调
function MsgOnTime.OnWebRedisNotifyCallBack(arrKey)
    local isChange = false
    Base.Log("_OnWebRedisNotifyCallBack")
    for _,skey in pairs(arrKey) do
        if skey=="ChangeUserInfoConsume" then
            isChange = true
        elseif skey=="ClubOpenTableConsume" then
            isChange = true
        elseif skey==string.match(skey,"ClubLevelConfig_nGroupId") then
            isChange = true
        end
        if isChange then
            Base.Log("_OnWebRedisNotifyCallBack 后台修改的skey:%s",skey)
            MsgOnTime.UpdateClubConfig() 
            break
        end
    end
end

return MsgOnTime