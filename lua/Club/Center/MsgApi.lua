--消息通知api
local MsgApi = {
    ServIdToKey = {}, --从服 {[nServerId]=sServerKey,...}
}

--添加从服
function MsgApi.AddSlaveServ(nServerId,sServerKey)
    local isRefresh = false
	if MsgApi.ServIdToKey[nServerId] == nil then 
        MsgApi.ServIdToKey[nServerId] = sServerKey
        Base.Log("_AddSlaveServ 中心服  添加从服nServerId:%d     sReturnKey_%s  ",nServerId,sServerKey) 
        isRefresh = true
    else
        if  MsgApi.ServIdToKey[nServerId] ~= sServerKey then 
            MsgApi.ServIdToKey[nServerId] = sServerKey
            Base.Log("_AddSlaveServ 从服已失效    nServerId:%d   需要更新 sReturnKey_%s  ",nServerId,sServerKey)
            isRefresh = true
        end 
    end
    return isRefresh
end

--网络协议发送(发给到DB服)
function MsgApi.SendToDBServer(strProto,tSendData,nUserId)
    local tPacket =DbClubServAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    if nUserId ~= nil then
        Base.PostDatasByTypeAndUID(Typename.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
    else
        Base.PostDatasByType(Typename.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    end
end

--网络协议发送(发给到DB服)
function MsgApi.SendToDBServer1(strProto,tSendData,nUserId)
    local tPacket =DbClubServAux1:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    if nUserId ~= nil then
        Base.PostDatasByTypeAndUID(Typename.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
    else
        Base.PostDatasByType(Typename.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    end
end

--网络协议发送(根据userid发给指定DB服)
function MsgApi.SendToDBServerByUID(strProto,tSendData,sUserId)
    local tPacket =DbClubServAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostDatasByTypeAndUID(Typename.db, 0, sUserId, tPacket:GetData(), tPacket:GetSize())
end 

--网络协议发送(同一个nClubId发到同一个db服)
function MsgApi.SendToDBServerByClubId(nClubId,strProto,tSendData)
    local tPacket =DbClubServAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostDatasByType(Typename.db, 0, nClubId, tPacket:GetData(), tPacket:GetSize())
end

--发送到某个从服
function MsgApi.SendToSlaveServer(sServerKey,strProto,tSendData)
    local tPacket =CenterAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostToClient(sServerKey, tPacket:GetData(), tPacket:GetSize())
end

--广播给所有从服
function MsgApi.Broadcast(sProto,tSendData)
    local tPacket =CenterAux:Encode(sProto,tSendData)
    assert(tPacket~=nil)
    for nServerId,sServerKey in pairs(MsgApi.ServIdToKey) do
		Base.PostToClient(sServerKey, tPacket:GetData(), tPacket:GetSize())
	end
end

--发送俱乐部玩家信息改变
function MsgApi.SendUserInfoChange(nClubId,nUserId,tChangeInfo)
    local ClubCUserInfoChangeNotify = {}
    ClubCUserInfoChangeNotify.nClubId = nClubId
    ClubCUserInfoChangeNotify.nUserId = nUserId
    ClubCUserInfoChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo)
    MsgApi.Broadcast("ClubCUserInfoChangeNotify",ClubCUserInfoChangeNotify)
end

--发送到tg群
function MsgApi.SendToTGChat(sSendSMS)
    Base._OnMonitorInfo(sSendSMS,ServerInfo.nServerId)
end

--发送后台操作结果
function MsgApi.SendWebOprateResult(sKey,tData)
    local Redis = Base.m_MyRedisData[1].redis
    Redis:hmset(sKey,tData)
    Redis:expire(sKey,10)
end

--获取游戏服 key 
function MsgApi._GetGameServerKey(nGameId,nClubId,sTableName)
    local tClub = ClubManager.GetClub(nClubId)
    if not tClub then
        Base.Log("_GetGameServerKey not find Club  nClubId_%d ",nClubId)
        return nil 
    end  
    local sGameName = nil
    for _,v in pairs(Define.GameList) do
        if nGameId==v.nGameId then
            sGameName = v.sGameCenter
            break
        end
    end
    if not sGameName then
        tClub:Print("_GetGameServerKey 未定义的游戏 nGameId_%d",nGameId)
        return nil
    end
    local arrServerKey = Base.GetSrcAllKey(sGameName) or {}
    if #arrServerKey==0 then
        tClub:Print("_GetGameServerKey 没有游戏服务器 nGameId_%d sGameName_%s",nGameId,sGameName)
        return nil
    end
    local arrCanUseServer = {}
    for _,sServerKey in pairs(arrServerKey) do
        local nServerId =tonumber(string.match(sServerKey,"_(%d+)"))
        if nServerId then 
            local nServerState = PublicRedis.GetServerState(nServerId)
            if nServerState==1 or nServerState==3 then
                table.insert(arrCanUseServer,sServerKey) 
            else
                tClub:Print("_GetGameServerKey nServerId_%d,nServerState:%d  游戏服务器维护中 ",nServerId,nServerState)                
            end
        end
    end
    if #arrCanUseServer==0 then
        tClub:Print("_GetGameServerKey 没有可用服 nGameId_%d",nGameId)
        return nil 
    end
    local nIndex = math.random(1,#arrCanUseServer)
    local sServerKey = arrCanUseServer[nIndex] or arrCanUseServer[1]    
    tClub:Print("_GetGameServerKey nGameId:%d sGameName:%s nClubId_%d sTableName_%s  arrkey:%d /%s "
    ,nGameId,sGameName,nClubId,B_Decode(sTableName),#arrServerKey,sServerKey) 
    return sServerKey
end

function MsgApi.SendToGameServer(sServerKey,tSendData) 
    local strProto = "ReqAPI_Table"
    local tPacket = BackstageAux:Encode(strProto,tSendData)
    Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
    return         
end

--发送开桌到游戏服
function MsgApi.SendOpenTableToGame(nGameId, tSendData)
    local sGameName = nil
    for _, v in pairs(Define.GameList) do
        if nGameId == v.nGameId then
            sGameName = v.sGameCenter
            break
        end
    end

    if not sGameName then
        Base.Log("_SendOpenTableToGame 未定义的游戏 nGameId_%d",nGameId)
        return false
    end

    local arrServerKey = Base.GetSrcAllKey(sGameName) or {}
    if #arrServerKey==0 then
        Base.Log("_SendOpenTableToGame 没有游戏服务器 nGameId_%d sGameName_%s",nGameId,sGameName)
        return false
    end
    Base.Log("_SendOpenTableToGame nGameId:%d sGameName:%s #arrServerKey:%d",nGameId,sGameName,#arrServerKey)
    local arrCanUseServer = {}
    for _, sServerKey in pairs(arrServerKey) do
        local nServerId = tonumber(string.match(sServerKey,"_(%d+)"))
        if nServerId then
            local nServerState = PublicRedis.GetServerState(nServerId)
            if nServerState == 1 or nServerState == 3 then
                --如果该服中已存在同名牌桌 则不可以再开
                local tRoomConfig = Cjson.decode(tSendData.sConfig)
                local nClubId = tRoomConfig.nClubId
                local tClub = ClubManager.GetClub(nClubId)
                if not tClub then
                    Base.Log("_SendOpenTableToGame not find Club")
                else
                    local isCanCreate = tClub:GetSameNameTable(nServerId, nGameId, tSendData.sTableName)
                    if isCanCreate then
                        table.insert(arrCanUseServer, sServerKey)
                    else
                        Base.Log("_SendOpenTableToGame nServerId_%d:this server have exist this same sTableName", nServerId)
                    end
                end
            else
                Base.Log("_SendOpenTableToGame nServerId_%d,nServerState:%d", nServerId, nServerState)
            end
        end
    end
    if #arrCanUseServer == 0 then
        Base.Log("_SendOpenTableToGame 游戏服务器维护中 nGameId_%d", nGameId)
        return false
    end

    local nIndex = math.random(1, #arrCanUseServer)
    local sServerKey = arrCanUseServer[nIndex]

    local strProto = "ReqAPI_Table"
    local tPacket = BackstageAux:Encode(strProto, tSendData)
    Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())

    Base.Log("_SendOpenTableToGame 通知游戏服务器开桌 sServerKey:%s", sServerKey)

    return true
end

--发送关桌到游戏服
function MsgApi.SendCloseTableToGame(tSendData)
    local nCenterServerId = tonumber(string.match(tSendData.sTableId,"(%d+)#"))
    if not nCenterServerId then
        Base.Log("_SendCloseTableToGame 没有中心服id,sTableId:%d",tSendData.sTableId)
        return false
    end
    local sServerKey = Base.GetServerIdIdKey(nCenterServerId)
    if not sServerKey then
        Base.Log("_SendCloseTableToGame 游戏服务器不存在,sTableId:%d",tSendData.sTableId)
        return false
    end

    local strProto = "ReqAPI_Table"
    local tPacket = BackstageAux:Encode(strProto,tSendData)
    Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
    
    Base.Log("_SendCloseTableToGame 通知游戏服务器关桌 sServerKey:%s",sServerKey)

    return true
end
 



return MsgApi