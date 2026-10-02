--消息通知api 
local MsgApi = {
    nCenterServId = nil,  --中心服id
    sCenterServKey = nil,  --中心服key
}

--网络协议发送(发给前端)
function MsgApi.SendToClient(sClientID,strProto,tSendData)
    local tPacket =SlaveAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())
end

function MsgApi.SendToClient2(sClientID,strProto,tSendData)
    local tPacket =SlaveAux2:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())
end
 
 --发送协议消息给玩家
function  MsgApi.SendToUser(nUserId,strProto,tSendData)
    local tUser = UserManager.GetUserInfo(nUserId)
    if tUser == nil then   
        Base.Log("_SendToUser  nUserId_%d tUser is nil   strProto_%s ",nUserId,strProto)
        return
    end
    if not tUser.isAndroid then
        local sClientID =ClientIdMgr.GetClientIdByUserId(nUserId)
        if sClientID then
            MsgApi.SendToClient(sClientID,strProto,tSendData)
        else
            Base.Log("_SendToUser  nUserId_%d sClientID is nil   strProto_%s ",nUserId,strProto)
        end
        return
    end
end

function  MsgApi.SendToUser2(nUserId,strProto,tSendData)
    local tUser = UserManager.GetUserInfo(nUserId)
    if tUser == nil then   
        Base.Log("_SendToUser  nUserId_%d tUser is nil   strProto_%s ",nUserId,strProto)
        return
    end 
    if not tUser.isAndroid then
        local sClientID =ClientIdMgr.GetClientIdByUserId(nUserId)
        if sClientID then
            MsgApi.SendToClient2(sClientID,strProto,tSendData)
        else
            Base.Log("_SendToUser  nUserId_%d sClientID is nil   strProto_%s ",nUserId,strProto)
        end
        return
    end
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


--网络协议发送(发给到DB服 1)
function MsgApi.SendToDB1Server(strProto,tSendData,nUserId)
    local tPacket =DbServer1Aux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
   -- Base.PostDatasByType(Typename.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
    Base.PostDatasByTypeAndUID(Typename.db, 0, nUserId, tPacket:GetData(), tPacket:GetSize())
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

--网络协议发送(同一个nClubId发到同一个db服)
function MsgApi.SendToDBServerByClubId(nClubId,strProto,tSendData)
    local tPacket =DbClubServAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostDatasByType(Typename.db, 0, nClubId, tPacket:GetData(), tPacket:GetSize())
end

--网络协议发送(发给到本服对应的中心服)
function MsgApi.SendToCenterServer(strProto,tSendData)
    local tPacket =CenterAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    assert(MsgApi.sCenterServKey~=nil,"sCenterServKey is nil")
    Base.PostToServer(MsgApi.sCenterServKey, 0, tPacket:GetData(), tPacket:GetSize())
end

--网络协议发送(发给到所有中心服)
function MsgApi.SendToAllCenterServer(strProto,tSendData)
    local tPacket =CenterAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    local arrSrvKey = Base.GetSrcAllKey(Typename.ClubCenter)
    for k,sServerKey in pairs(arrSrvKey) do
        Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
    end
end

--网络协议发送(发给到俱乐部所在中心服)
function MsgApi.SendToClubCenterServer(strProto,tSendData,nClubId)
    local tPacket =CenterAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    local arrServKey = PublicRedis.GetClubCenterSrvKey(nClubId) --获取俱乐部所在中心服
    if #arrServKey>0 then
        for _,sCenterServKey in pairs(arrServKey) do
            Base.PostToServer(sCenterServKey, 0, tPacket:GetData(), tPacket:GetSize())
        end
    else
        Base.Log(string.format("俱乐部所在中心服不存在 nClubId:%d",nClubId))
    end
end

--发送到从服
--@param strProto 协议名称
--@param tSendData 协议数据
--@param isToOther 是否只发送给其他从服
function MsgApi.SendToSlaveServer(strProto,tSendData,isToOther)
    local tPacket =CenterAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)

    local arrSrvKey = Base.GetSrcAllKey(Typename.ClubSlave)
    for k,sServerKey in pairs(arrSrvKey) do
        if isToOther then
            local nServerId =tonumber(string.match(sServerKey,"_(%d+)"))
            if ServerInfo.nServerId~=nServerId then
                Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
            end
        else
            Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
        end
    end
end

--发送到特定的服务器
--@param strProto 协议名称
--@param tSendData 协议数据
--@param sServerKey 服务器key
function MsgApi.SendToThisServer(sServerKey,strProto,tSendData)
    local tPacket =CenterAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
end

-- 发网关进行广播 
function MsgApi.SendToGateWay(strProto,tSendData,arrClientID)
    if not arrClientID or #arrClientID == 0 then 
        -- Base.Log("_SendToGateWay strProto_%s 从服通知网关进行广播 没有找到用户",strProto) 	
        return 
    end
	local tPacket =SlaveAux:Encode(strProto,tSendData)
	local tData = {}
	tData.arrClientID = arrClientID 
	tData.tPacket = tPacket
    PublicUserInfo._BroadcastGateway(tData)	
	-- Base.Log("_SendToGateWay  从服通知网关进行广播  tClientID_%d  sendsize_%d ",#tData.arrClientID,tData.tPacket:GetSize()) 	
	return true
end

-- 发网关进行广播 
function MsgApi.SendToGateWay2(strProto,tSendData,arrClientID)
    if not arrClientID or #arrClientID == 0 then 
        -- Base.Log("_SendToGateWay strProto_%s 从服通知网关进行广播 没有找到用户",strProto) 	
        return
    end
	local tPacket =SlaveAux2:Encode(strProto,tSendData)
	local tData = {}
	tData.arrClientID = arrClientID
	tData.tPacket = tPacket
    PublicUserInfo._BroadcastGateway(tData)
	-- Base.Log("_SendToGateWay  从服通知网关进行广播  tClientID_%d  sendsize_%d ",#tData.arrClientID,tData.tPacket:GetSize()) 	
	return true
end

--发送踢人到游戏服
function MsgApi.SendKickUserToGame(nUserId,sServerKey)
    local tSend = ProtoManager.PubProto_1_pb.REQ_Kick_User()
    tSend.nUserId = nUserId
    tSend.nType = 2
    local tPacket = Base.GetSP().new(ProtoManager.Sub_LobbyGame.SYSLOBBY_GAME, ProtoManager.Sub_LobbyGame.SUB_GAME_KICK_USER)
    tPacket:AddString(tSend:SerializeToString())
    if sServerKey then
        Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
        Base.Log("_SendKickUserToGame KickUser_%d Serverkey_%s",nUserId,sServerKey)
    end
end

--发送开桌到游戏服
function MsgApi.SendOpenTableToGame(nGameId,tSendData)
    local sGameName = nil

    for _,v in pairs(Define.GameList) do
        if nGameId==v.nGameId then
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
    for _,sServerKey in pairs(arrServerKey) do
        local nServerId =tonumber(string.match(sServerKey,"_(%d+)"))
        if nServerId then 
            local nServerState = PublicRedis.GetServerState(nServerId)
            if nServerState==1 or nServerState==3 then
                table.insert(arrCanUseServer,sServerKey)
            else
                Base.Log("_SendOpenTableToGame nServerId_%d,nServerState:%d",nServerId,nServerState)
            end
        end
    end

    if #arrCanUseServer==0 then
        Base.Log("_SendOpenTableToGame 游戏服务器维护中 nGameId_%d",nGameId)
        return false
    end

    local nIndex = math.random(1,#arrCanUseServer)
    local sServerKey = arrCanUseServer[nIndex]

    local strProto = "ReqAPI_Table"
    local tPacket = BackstageAux:Encode(strProto,tSendData)
    Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
    
    Base.Log("_SendOpenTableToGame 通知游戏服务器开桌 sServerKey:%s",sServerKey)

    return true
end

--发送关桌到游戏服
function MsgApi.SendCloseTableToGame(tSendData)
    local nCenterServerId =tonumber(string.match(tSendData.sTableId,"(%d+)#"))
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

--发送俱乐部玩家信息改变
function MsgApi.SendUserInfoChange(nClubId,nUserId,tChangeInfo)
    local ClubCUserInfoChangeNotify = {}
    ClubCUserInfoChangeNotify.nClubId = nClubId
    ClubCUserInfoChangeNotify.nUserId = nUserId
    ClubCUserInfoChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo)
    MsgApi.SendToSlaveServer("ClubCUserInfoChangeNotify",ClubCUserInfoChangeNotify)
end

--发送玩家消息通知
function MsgApi.SendUserMessage(nUserId,nType,tExData)
    local ClubCUserMsgNotify = {}
    ClubCUserMsgNotify.nUserId = nUserId
    ClubCUserMsgNotify.nType = nType
    ClubCUserMsgNotify.sExData = Cjson.encode(tExData)
    MsgApi.SendToSlaveServer("ClubCUserMsgNotify",ClubCUserMsgNotify)
end

--发送俱乐部场景信息改变
function MsgApi.SendClubInfoChange(nClubId,tChangeInfo)
    local ClubCSceneChangeReq = {}
    ClubCSceneChangeReq.nClubId = nClubId
    ClubCSceneChangeReq.sChangeInfo = Cjson.encode(tChangeInfo)
    MsgApi.SendToClubCenterServer("ClubCSceneChangeReq",ClubCSceneChangeReq,nClubId)
end

--发送玩家信息改变到游戏服
function MsgApi.SendUserInfoChangeToGameServer(nUserId,tChangeInfo)
    tChangeInfo.nUserID = nUserId
    local strProto = "ChangeUserInfoNotify"
    local tSendData = {}
    tSendData.sChangeInfo = Cjson.encode(tChangeInfo)
    local tPacket = BackstageAux:Encode(strProto,tSendData)
    for _,v in pairs(Define.GameList) do
        local arrServerKey = Base.GetSrcAllKey(v.sGameCenter) or {}
        for _,sServerKey in pairs(arrServerKey) do
            Base.PostToServer(sServerKey, 0, tPacket:GetData(), tPacket:GetSize())
        end
    end
end

--发送到tg群
function MsgApi.SendToTGChat(sSendSMS)
    Base._OnMonitorInfo(sSendSMS,ServerInfo.nServerId)
end

--发送到web服,通过GET方式
function MsgApi.SendToWebByGET(sUrl,sBody)
    local WebUrlReq = {}  
    WebUrlReq.sUrl = sUrl
    WebUrlReq.sSerialNum =string.format("%d_%d",ServerInfo.nServerId,SlaveData.nReqWebCount)
    WebUrlReq.sSendType = "GET"
    WebUrlReq.sBody = sBody
    local tPacket = WebAux:Encode("WebUrlReq",WebUrlReq)   
    Base.PostDatasByType(Typename.web, 0, 0, tPacket:GetData(), tPacket:GetSize())
    SlaveData.nReqWebCount = SlaveData.nReqWebCount + 1
end

--发送获取短信验证码
function MsgApi.SendGetMsgCode(nUserId,sPhone,nGroupId)
    local sDomainName = RedisCahche.GetMsgCodeDomainName(nGroupId)
    if not sDomainName then
        Base.Log("_SendGetMsgCode 后台没有设置获取短信验证码的域名")
        MsgApi.SendToTGChat("后台没有设置获取短信验证码的域名")
        return false
    end
    local sUrl = string.format("%sUserID=%d&phone=%d",sDomainName,nUserId,sPhone)
    MsgApi.SendToWebByGET(sUrl)
    return true
end

--发送玩家个人信息改变
function MsgApi.SendPerSonInfoChange(nUserId,tChangeInfo)
    local ClubSPersonInfoNotify = {}
    ClubSPersonInfoNotify.nUserId = nUserId
    ClubSPersonInfoNotify.sChangeInfo = Cjson.encode(tChangeInfo)
    MsgApi.SendToUser(nUserId,"ClubSPersonInfoNotify",ClubSPersonInfoNotify)
end

function MsgApi.SendPerSonInfoChange2(nUserId,tChangeInfo)
    local ClubSPersonInfoNotify = {}
    ClubSPersonInfoNotify.nUserId = nUserId
    ClubSPersonInfoNotify.sChangeInfo = Cjson.encode(tChangeInfo)
    MsgApi.SendToUser2(nUserId,"ClubSPersonInfoNotify",ClubSPersonInfoNotify)
end

return MsgApi