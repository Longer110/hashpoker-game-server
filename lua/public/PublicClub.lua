--俱乐部公用接口
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path
package.path = "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path

local ProtoAux = require("ProtoCoder").Aux
local tBase = require("base")
local tPublicRedis = require("PublicRedis")
local tLogger = require("logger")
local cjson = require("cjson")
local ProtoMgr = require("ProtoManager")
local Typename = require("typename")
local tServInfo = require("ServerInfo")
local tPubUser = require("PublicUserInfo")
local tPublicApi = require("publicApi")

--俱乐部中心服协议
local pb_ClubCenter = ProtoMgr.ClubCenter_pb
local CMD_ClubCenter = pb_ClubCenter.ClubC_Proto()
local ToCMD_ClubCenter =function(strProto)
    return CMD_ClubCenter.Main_CMD,CMD_ClubCenter[strProto..'_CMD']
end
--生成个编解码辅助对象
local ClubCenterAux = ProtoAux:New(pb_ClubCenter,ToCMD_ClubCenter)

--db服<->游戏服协议
local pb_DbClubServer =ProtoManager.DbServerClub_pb
local CMD_DbClubServer =pb_DbClubServer.Db_ClubProto()
local ToCMD_DbClubServer =function(strProto)
    return CMD_DbClubServer.Main_CMD,CMD_DbClubServer[strProto..'_CMD']
end
--生成个编解码辅助对象
local DbClubServAux =ProtoAux:New(pb_DbClubServer,ToCMD_DbClubServer)

local PublicClub = {}

--发送到俱乐部中心服
function PublicClub.SendToClubCenter(nClubId,strProto,tSendData)
    local arrNormal,arrOther = tPublicRedis.GetClubCenterServer(nClubId)
    if #arrNormal==0 and #arrOther==0 then
        tLogger:error(string.format("俱乐部所在中心服不存在 nClubId:%d",nClubId))
        return
    end
    --随机选一个服计算收益
    if #arrNormal>0 then
        tSendData.nServId = arrNormal[math.random(1,#arrNormal)]
    elseif #arrOther>0 then
        tSendData.nServId = arrOther[math.random(1,#arrOther)]
    end
    local tPacket =ClubCenterAux:Encode(strProto,tSendData)
    for _,nServId in pairs(arrNormal) do
        local sKey = tBase.GetServerIdIdKey(nServId)
        if sKey then
            tBase.PostToServer(sKey, 0, tPacket:GetData(), tPacket:GetSize())
        end
    end
    for _,nServId in pairs(arrOther) do
        local sKey = tBase.GetServerIdIdKey(nServId)
        if sKey then
            tBase.PostToServer(sKey, 0, tPacket:GetData(), tPacket:GetSize())
        end
    end
end

--发送到db服
function PublicClub.SendToDBServer(strProto,tSendData)
    local tPacket =DbClubServAux:Encode(strProto,tSendData)
    assert(tPacket~=nil)
    tBase.PostDatasByType(Typename.db, 0, 0, tPacket:GetData(), tPacket:GetSize())
end

--俱乐部桌开桌通知
--[[牌桌信息 必须有的信息 tTableInfo = {
    nGameId=游戏id,
    sTableName=牌桌名字,
    nItemId=使用的金币id,
    nOpentime=开桌时间,
    nLiveUserID=房主id,
    nKeepTime=房间时长,
    nCapacity=最大人数,
    nGoldType=使用的金币类型 1:金币 2:俱乐部币 3:积分
    nTableStatus=房间状态 0:正常状态 1:暂停状态,停止计时

    德州要有的: 
    nSmallBlind=小盲,
    nBigBlind=大盲,
    isAOF=全下或弃牌 true:开启 false:关闭
    nInsureMode=保险模式 0:无保险 1:传统保险 2:低水保险
]]--
function PublicClub.ClubTableOpenNotify(nClubId,sTableId,tTableInfo)
    local ClubCGameOpenTableNotify = {}
    ClubCGameOpenTableNotify.nClubId = nClubId
    ClubCGameOpenTableNotify.sTableId = sTableId
    ClubCGameOpenTableNotify.sTableInfo = cjson.encode(tTableInfo)
    PublicClub.SendToClubCenter(nClubId,"ClubCGameOpenTableNotify",ClubCGameOpenTableNotify)
    tBase.Log("ClubTableOpenNotify 俱乐部桌开桌通知 nClubId:%d,sTableId:%s",nClubId,sTableId)
end

--俱乐部桌关桌通知
function PublicClub.ClubTableCloseNotify(nClubId,sTableId)
    local ClubCGameCloseTableNotify = {}
    ClubCGameCloseTableNotify.nClubId = nClubId
    ClubCGameCloseTableNotify.sTableId = sTableId
    PublicClub.SendToClubCenter(nClubId,"ClubCGameCloseTableNotify",ClubCGameCloseTableNotify)
    tBase.Log("ClubTableCloseNotify 俱乐部桌关桌通知 nClubId:%d,sTableId:%s",nClubId,sTableId)
end

--俱乐部桌信息改变通知
--[[改变的牌桌信息 例如德州:tTableInfo = {
    nNowCnt=目前坐下的人数,
    nSmallBlind=小盲,
    nBigBlind=大盲,
    nTableStatus=房间状态 0:正常状态 1:暂停状态,停止计时
    }
]]--
function PublicClub.ClubTableInfoNotify(nClubId,sTableId,tTableInfo)
    if nClubId==nil then
        return
    end
    local ClubCGameTableInfoNotify = {}
    ClubCGameTableInfoNotify.nClubId = nClubId
    ClubCGameTableInfoNotify.sTableId = sTableId
    ClubCGameTableInfoNotify.sTableInfo = cjson.encode(tTableInfo)
    PublicClub.SendToClubCenter(nClubId,"ClubCGameTableInfoNotify",ClubCGameTableInfoNotify)
end

--俱乐部玩家结算通知
function PublicClub.ClubUserSettleNotify(tData)
    local tSData = {}
    tSData.nClubId = tData.nClubId --俱乐部id
    tSData.sTableId = tData.sTableId --牌桌id
    tSData.nUserId = tData.nUserId --玩家id
    tSData.nWinlose = tData.nWinlose --玩家输赢
    tSData.nDrawWater = tData.nDrawWater --抽水
    tSData.nItemId = tData.nItemId --道具id
    tSData.nGameId = tData.nGameType --游戏id
    tSData.sPaiJuId = tData.sPaiJuId --牌局id
    tSData.nInsurance = tData.tElseInfo and tData.tElseInfo.nInsur --保险输赢
    tSData.nJuShu = tData.nJuShu --第几局
    tSData.nHandProfit = tData.nHandProfit or 0

    --必要字段
    local tRequired = {
        ["nClubId"] = "number",
        ["sTableId"] = "string",
        ["nUserId"] = "number",
        ["nWinlose"] = "number",
        ["nDrawWater"] = "number",
        ["nItemId"] = "number",
        ["nGameId"] = "number",
        ["sPaiJuId"] = "string",
        ["nJuShu"] = "number",
    }
    for sKey,sType in pairs(tRequired) do
        if not tSData[sKey] then
            local sErrStr = string.format("俱乐部玩家结算必要数据缺失 key:%s",sKey)
            tBase.Log(sErrStr)
            Base._OnMonitorInfo(sErrStr,tServInfo.nServerId)
            return
        elseif type(tSData[sKey])~=sType then
            local sErrStr = string.format("俱乐部玩家结算必要数据类型错误 key:%s value:%s 目前数据类型:%s 所需数据类型:%s",
            sKey,tostring(tSData[sKey]),type(tSData[sKey]),sType)
            tBase.Log(sErrStr)
            Base._OnMonitorInfo(sErrStr,tServInfo.nServerId)
            return
        end
    end
    --选要的字段
    local tOptional = {
        ["nInsurance"] = "number",
    }
    for sKey,sType in pairs(tOptional) do
        if tSData[sKey] and type(tSData[sKey])~=sType then
            local sErrStr = string.format("俱乐部玩家结算选要数据类型错误 key:%s value:%s 目前数据类型:%s 所需数据类型:%s",
            sKey,tostring(tSData[sKey]),type(tSData[sKey]),sType)
            tBase.Log(sErrStr)
            Base._OnMonitorInfo(sErrStr,tServInfo.nServerId)
            return
        end
    end

    local ClubCGameUserSettleNotify = {}
    ClubCGameUserSettleNotify.nClubId = tSData.nClubId
    ClubCGameUserSettleNotify.sTableId = tSData.sTableId
    ClubCGameUserSettleNotify.nUserId = tSData.nUserId
    ClubCGameUserSettleNotify.nWinlose = tSData.nWinlose
    ClubCGameUserSettleNotify.nDrawWater = tSData.nDrawWater
    ClubCGameUserSettleNotify.nItemId = tSData.nItemId
    ClubCGameUserSettleNotify.nGameId = tSData.nGameId
    ClubCGameUserSettleNotify.sPaiJuId = tSData.sPaiJuId
    ClubCGameUserSettleNotify.nInsurance = tSData.nInsurance
    ClubCGameUserSettleNotify.nJuShu = tSData.nJuShu
    ClubCGameUserSettleNotify.nHandProfit = tSData.nHandProfit
    PublicClub.SendToClubCenter(tSData.nClubId,"ClubCGameUserSettleNotify",ClubCGameUserSettleNotify)
end

--写入回放数据
--@params tData.nClubId 俱乐部id
--@params tData.nGameId 游戏id
--@params tData.sTableId 牌桌id
--@params tData.sPaiJuId 牌局id
--@params tData.sPlayBackData 回放数据 Json格式
-- sTableName
function PublicClub.WritePlayBackData(tData)
    if not tData then
        return
    end
    if type(tData.nClubId)~="number" then
        tBase.Log("WritePlayBackData nClubId Err")
        return
    end
    if type(tData.nGameId)~="number" then
        tBase.Log("WritePlayBackData nGameId Err")
        return
    end
    if type(tData.sTableId)~="string" then
        tBase.Log("WritePlayBackData sTableId Err")
        return
    end
    if type(tData.sPaiJuId)~="string" then
        tBase.Log("WritePlayBackData sPaiJuId Err")
        return
    end
    if type(tData.sPlayBackData)~="string" then
        tBase.Log("WritePlayBackData sPlayBackData Err")
        return
    end
    if tData.nClubId<0 then
        tBase.Log("WritePlayBackData nClubId<=0 ??????")
        return
    end

    tBase.Log("写入回放数据 nClubId_%d nGameId_%d sTableId_%s sPaiJuId_%s #sPlayBackData_%s",
    tData.nClubId,tData.nGameId,tData.sTableId,tData.sPaiJuId,#tData.sPlayBackData)

    local sTableName =tData.sTableName or ""
    local sSql = string.format("call Club_WritePlayBackData_v2(%d,%d,'%s','%s','%s','%s','%s','%s')",
        tData.nClubId,tData.nGameId,tData.sTableId,tData.sPaiJuId,tData.sPlayBackData,sTableName,tData.sLookData, tData.sPenaltyData or "[]")

    local ClubWritePlaybackDataReq = {}
    ClubWritePlaybackDataReq.sSql = sSql
    PublicClub.SendToDBServer("ClubWritePlaybackDataReq",ClubWritePlaybackDataReq)
end

function PublicClub.RecordUserGPS(nUserId,tGps)
    if tGps and tGps.nLongitude and tGps.nLatitude and not tPubUser.IsComAndroid(nUserId) then
        tGps.nLongitude = tPublicApi.Floor_n(tGps.nLongitude,5)
        tGps.nLatitude = tPublicApi.Floor_n(tGps.nLatitude,5)
        local t = {tGps.nLongitude,tGps.nLatitude}
        local ClubWriteUserGPS = {}
        ClubWriteUserGPS.sSql = string.format("call WriteUserGPS(%d,'%s')",nUserId,cjson.encode(t))
        PublicClub.SendToDBServer("ClubWriteUserGPS",ClubWriteUserGPS)
    end
end

return PublicClub