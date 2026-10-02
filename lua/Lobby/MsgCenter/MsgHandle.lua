local tBase        = require("base")            -- 基础功能接口
local tname        = require("typename")        -- 类弄定义接口
local ProtoMgr     = require("ProtoManager")    -- 协议管理对象 
local tPubUserApi  = require("PublicUserInfo")    --玩家数据
local tParserAux   = require("ParserAux")
local tClientIdMgr = require("ClientIdMgr")
local Cjson        = require("cjson")


local LobbyParse =tParserAux.LobbyParse
local LobbySendToClient =tParserAux.LobbySendToClient
local DbProtoEncode =tParserAux.DbProtoEncode
local DbProtoParse =tParserAux.DbProtoParse

local function LobbySendToUser(nUserId,strProto,tSendData)
    local sClientID = tClientIdMgr.GetClientIdByUserId(nUserId)
    if not sClientID then
        tBase.Log("Err happen ,can not find nUserId_%d clientID",(nUserId or -1))
       return false
    end

    return LobbySendToClient(sClientID,strProto,tSendData)
 end


-- 消息处理
local MsgHandle = {}

--[[
-- 用户登录主动发送请求消息，获取该用户的玩家通知
-- sClientID：用户ID
-- Data：响应数据
-- len：数据长度
]] 
function MsgHandle.OnClubSUserNoticeReq(sClientID, Data, nLen)
    tBase.Log("enter OnClubSUserNoticeReq")

    local strProto = "ClubSUserNoticeReq"
    local tData = LobbyParse(Data, nLen, strProto)
    if not tData then
        tBase.Log("%s _Parse Err",strProto)
        return false
    end

    local nUserID = math.floor(tData.nUserID)
    if not tPubUserApi.ChecksClientIDByUserID(nUserID, sClientID) then
        tBase.Log("nUserId_%d Error",nUserID)
        return
     end

    local tUserInfo = tPubUserApi.GetAllUserInfo(tData.nUserID)
    if tUserInfo == nil then   
        tBase.Log("OnClubSUserNoticeReq GetAllUserInfo fail,nUserID_%d",tData.nUserID)
        LobbySendToClient(sClientID, "ClubSUserNoticeResp", {nResult =1})
        return
    end 

    local nIdOfStart = tData.nIdOfStart
    if nIdOfStart<0 then
        nIdOfStart = 0
    end

    local nCnt = tData.nCnt
    if nCnt<=0 then
        nCnt = 10
    elseif nCnt > 30 then
        nCnt = 30
    end

    local ClubUserNoticeReq = {}
    ClubUserNoticeReq.nIdOfStart = nIdOfStart
    ClubUserNoticeReq.nCnt = nCnt
    ClubUserNoticeReq.nUserId = nUserID
    ClubUserNoticeReq.nType = tData.nType
   
    local packet = DbProtoEncode("ClubUserNoticeReq", ClubUserNoticeReq)
    tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())
end

--[[
-- DB服返回 玩家个人通知 返回
-- sReturnKey：请求返回的Key
-- Data：响应数据
-- len：数据长度
]] 

function MsgHandle.OnDBClubUserNoticeRsp(sReturnKey, Data, nLen)
    tBase.Log("enter OnDBClubUserNoticeRsp")

    local strProto = "ClubUserNoticeRsp"
    local tData = DbProtoParse(Data, nLen, strProto)
    if not tData then
        tBase.Log("%s _Parse Err",strProto)
        return false
    end

    local arrNotices = {}
    for k,v in pairs(tData.arrNotices) do
        if v.nId and v.nId>0 then
            local tItem = {}
            tItem.nId = v.nId
            tItem.nType = v.nType
            tItem.nStatus = v.nStatus
            tItem.sTime = v.sTime
            tItem.sData = v.sData
            tItem.nHadRead = v.nHadRead
            table.insert(arrNotices,tItem)
        end
    end

    local arrApplyList = {}
    for k,v in pairs(tData.arrApplyList) do
        if v.nId and v.nId>0 then
            local tApplyInfo = {}
            tApplyInfo.nId = v.nId
            tApplyInfo.nClubId = v.nClubId
            tApplyInfo.nType = v.nType
            tApplyInfo.sTime = v.sTime
            tApplyInfo.sClubName = v.sClubName
            tApplyInfo.nStatus = v.nStatus
            table.insert(arrApplyList,tApplyInfo)
        end
    end

    tBase.Log("OnDBClubUserNoticeRsp nUserId_%d #arrNotices_%d nType_%d nAllCnt_%d #arrApplyList_%d nUnReadCnt_%d",
        tData.nUserId,#arrNotices,tData.nType,tData.nAllCnt,#arrApplyList,tData.nUnReadCnt or -1)

    local ClubSUserNoticeResp = {}
    ClubSUserNoticeResp.arrNotices = arrNotices
    ClubSUserNoticeResp.nAllCnt = tData.nAllCnt
    ClubSUserNoticeResp.nType = tData.nType
    ClubSUserNoticeResp.arrApplyList = arrApplyList
    ClubSUserNoticeResp.nUnReadCnt = tData.nUnReadCnt
    LobbySendToUser(tData.nUserId, "ClubSUserNoticeResp", ClubSUserNoticeResp) 
end


--[[
-- --给玩家发系统消息
-- nUserId ：用户ID
-- nMsgType ：消息类型
-- strTipInfo：消息内容
]]

function MsgHandle.WriteSystemNoticeNotic(nUserId, nMsgType, strTipInfo, nType)
    tBase.Log("enter WriteSystemNoticeNotic")

    -- 写入DB
    local LobbyNotifyRecordReq = {}
    LobbyNotifyRecordReq.nUserId = nUserId
    LobbyNotifyRecordReq.nMsgType = nMsgType
    LobbyNotifyRecordReq.sMsg = strTipInfo
    LobbyNotifyRecordReq.nType = nType
    local packet = DbProtoEncode("LobbyNotifyRecordReq", LobbyNotifyRecordReq)
    tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())

    tBase.Log("leave WriteSystemNoticeNotic")
end

-- 插入系统消息后，返回的消息
function MsgHandle.OnLobbyNotifyRecordRsp(sReturnKey, Data, nLen)
    tBase.Log("enter OnLobbyNotifyRecordRsp")

    local strReq = "LobbyNotifyRecordReq"
    local tData = DbProtoParse(Data, nLen,strReq)
    if not tData then
        tBase.Log("Err happen ,Parse error OnLobbyNotifyRecordRsp strReq:"..strReq) 
        assert(false,"Err happen ,Parse error OnLobbyNotifyRecordRsp strReq:"..strReq)
        return
    end
  

    local arrNotices = {}
    local tItem = {}
    tItem.nId = tData.nMsgID
    tItem.nType = tData.nMsgType
    tItem.nStatus = 3
    tItem.sTime = os.date("%Y-%m-%d %H:%M:%S")
    tItem.sData =  Cjson.encode(tData.strMsg)
    tItem.nHadRead = 0
    table.insert(arrNotices,tItem)

    local ClubSUserNoticeResp = {}
    ClubSUserNoticeResp.arrNotices = arrNotices
    ClubSUserNoticeResp.nAllCnt = 1
    ClubSUserNoticeResp.nType = 1
    ClubSUserNoticeResp.arrApplyList = {}
    ClubSUserNoticeResp.nUnReadCnt = 1
    LobbySendToUser(tData.nUserId, "ClubSUserNoticeResp", ClubSUserNoticeResp) 
    tBase.Log("leave OnLobbyNotifyRecordRsp")
end


--[[
-- 响应客户端请求下消息
-- sReturnKey：请求返回的Key
-- Data：响应数据
-- len：数据长度
]] 
function MsgHandle.OnClubSUserNoticeHandleReq(sClientID, Data, nLen)
    local strProto = "ClubSUserNoticeHandleReq"
    local tData= LobbyParse(Data, nLen, strProto)

    local nUserId =tClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId then
        tBase.Log("AccountPayURLRsp  Not Logon,sClientID_"..(sClientID or 'nil'))
        return false
    end 

    -- 写入DB
    local UpdateLobbyNotifyRecordReq = {}
    UpdateLobbyNotifyRecordReq.nUserId = nUserId
    UpdateLobbyNotifyRecordReq.nMsgType = 1
    local packet = DbProtoEncode("UpdateLobbyNotifyRecordReq", UpdateLobbyNotifyRecordReq)
    tBase.PostDatasByType(tname.db, 0, 0, packet:GetData(), packet:GetSize())
end

return MsgHandle
