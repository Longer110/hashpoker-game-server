
local tBase = require("base") -- 基础功能接口
local tParserAux = require("ParserAux")
local NotifyProtoEncode =tParserAux.NotifyProtoEncode
local MaintainerAux =tParserAux.MaintainerAux


MsgPush={}

--nRoomId可不填
function MsgPush.Push_PlayingNotify(sClientID,nGameId,nRoomId)
    local tPacket,nMainCmd,nSubCmd =NotifyProtoEncode("PlayingNotify",{nGameId=nGameId,nRoomId=nRoomId})
    if not tPacket then
        tBase.Log("Err happen,NotifyProtoEncode fail,in Push_PlayingNotify")
        return false
    end
    tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize()) 
end


function MsgPush.SendMaintenanceNotify(sClientID,sTimeStart,sTimeEnd)
    local MaintenanceNotify={}
    MaintenanceNotify.sTimeStart =sTimeStart or 'unknown'
    MaintenanceNotify.sTimeEnd =sTimeEnd or 'unknown'
    local tPacket =MaintainerAux:Encode('MaintenanceNotify',MaintenanceNotify)
    if not tPacket then
        tBase.Log("Err happen,MaintenanceNotify Encode fail,in SendMaintenanceNotify")
        return false
    end
    tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize()) 
end

function MsgPush.SendKickOutNotify(sClientID,sTips,isKickToLobby)
    if sClientID==nil then
        return
    end
    local KickOutNotify={}
    KickOutNotify.sTips =sTips or ""
    KickOutNotify.nToWhere  =0      --踢回登陆界面
    if isKickToLobby then
        KickOutNotify.nToWhere  =1  --踢回大厅
    end
    if sTips == "8" then
        KickOutNotify.nToWhere  =2  --留在房间
    end
    local tPacket =MaintainerAux:Encode('KickOutNotify',KickOutNotify)
    if not tPacket then
        tBase.Log("Err happen,KickOutNotify Encode fail,in SendKickOutNotify")
        return false
    end
    tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize()) 
end

 return MsgPush