

local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local ProtoCoder =require("ProtoCoder")
local tname = require("typename")
local tBase = require("base")
local tReforwardRule = require("ReforwardRule")
local tPublicRedis = require("PublicRedis")
local tPubUserApi    = require("PublicUserInfo")    --玩家数据

require "DeZhou_pb"
require "DeZhouClub_pb"
require "DeZhouClubSC_pb"
require "LongHuSlave_pb"
require "NiuNiuSlave_pb"
require("LottelyBR_pb")

local CMD_LiveBaiJiaLe =ProtoMgr.BaiJiaLeSlave_pb.BJLS_Proto()
local CMD_YuXiaXie =ProtoMgr.YuXiaXie_pb.YuXiaXie_Proto()
local CMD_PilotSlave =ProtoMgr.PilotSlavePro
local CMD_PilotJCGame =ProtoMgr.PilotJCGamePro
local CMD_DeZhou =DeZhou_pb.DeZhou_Proto()
local CMD_DeZhouClub =DeZhouClub_pb.ClubDeZhou_Proto()
local CMD_DeZhouClubSC =DeZhouClubSC_pb.ClubDeZhouSC_Proto()
local CMD_TouBao =ProtoMgr.TouBao_pb.TouBao_Proto()
local CMD_SeDieMS =ProtoMgr.SeDieMS_Proto
local CMD_LiveSlave =ProtoMgr.LiveSlave_pb.LiveSlave_Proto()
local CMD_FootBallSlave =ProtoMgr.FootBallSlave_pb.FBS_Proto()
local CMD_FellTreeSlave =ProtoMgr.FellTreeSlavePro
local CMD_CluSlave = ProtoMgr.ClubSlave_pb.ClubS_Proto()
local CMD_BasketballSlave =ProtoMgr.BasketballSlavePro
local CMD_LongHuSlave =LongHuSlave_pb.LHS_Proto()
local CMD_ClubQZNiuNiuGame =ProtoMgr.ClubQZNiuNiuGamePro
local CMD_ZBNiuNiuSlave =ProtoMgr.NiuNiuSlave_pb.NNS_Proto()
local CMD_LottelyBR =LottelyBR_pb.LBR_Proto()

local GameLogon ={}

function GameLogon.IsLiveGameLogon(MainID,SubID,Data,Len)
    local tData=nil
    if MainID==CMD_LiveBaiJiaLe.Main_CMD and SubID==CMD_LiveBaiJiaLe.BJLSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.BaiJiaLeSlave_pb.BJLSLogOnReq(),Data,Len)
    end   
    if MainID==CMD_YuXiaXie.Main_CMD and SubID==CMD_YuXiaXie.YXXSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.YuXiaXie_pb.YXXSLogOnReq(),Data,Len)
    end

    --骰宝
    if MainID==CMD_TouBao.Main_CMD and SubID==CMD_TouBao.TBSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.TouBao_pb.TBSLogOnReq(),Data,Len)
    end

    --德州扑克
    if MainID==CMD_DeZhou.Main_CMD and SubID==CMD_DeZhou.DeZhouLogOnReq_CMD then
        tData =ProtoCoder.Parser(DeZhou_pb.DeZhouLogOnReq(),Data,Len)
    end

     --俱乐部德州扑克
     if MainID==CMD_DeZhouClub.Main_CMD and SubID==CMD_DeZhouClub.ClubDeZhouLogOnReq_CMD then
        tData =ProtoCoder.Parser(DeZhouClub_pb.ClubDeZhouLogOnReq(),Data,Len)
    end

     --俱乐部德州短牌
     if MainID==CMD_DeZhouClubSC.Main_CMD and SubID==CMD_DeZhouClubSC.ClubDeZhouSCLogOnReq_CMD then
        tData =ProtoCoder.Parser(DeZhouClubSC_pb.ClubDeZhouSCLogOnReq(),Data,Len)
    end
    
    -- 离开德州
    if MainID==CMD_DeZhou.Main_CMD and SubID==CMD_DeZhou.DeZhouBackToLobbyReq_CMD then
        tData =ProtoCoder.Parser(DeZhou_pb.DeZhouBackToLobbyReq(),Data,Len)
    end

    -- 飞行棋 
    if MainID==CMD_PilotSlave.Main and SubID==CMD_PilotSlave.SUB_REQ_LOGIN then
        tData =ProtoCoder.Parser(ProtoMgr.PilotSlave_pb.Req_PLS_Login(),Data,Len)
    end

    -- 竞猜服
    if MainID==CMD_PilotJCGame.Main_CMD and SubID==CMD_PilotJCGame.PilotJCLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.PilotJCGame_pb.PilotJCLogOnReq(),Data,Len)
    end    
    
    --直播色碟
    if MainID==CMD_SeDieMS.Main_CMD and SubID==CMD_SeDieMS.SDMSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.SeDieMSlave_pb.SDMSLogOnReq(),Data,Len)
    end

    --直播色碟
    if MainID==CMD_SeDieMS.Main_CMD and SubID==CMD_SeDieMS.SDMSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.SeDieMSlave_pb.SDMSLogOnReq(),Data,Len)
    end    
    
    --直播旁观服
    if MainID==CMD_LiveSlave.Main_CMD and SubID==CMD_LiveSlave.LiveSlaveLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.LiveSlave_pb.LiveSlaveLogOnReq(),Data,Len)        
    end    

    --直播足球
    if MainID==CMD_FootBallSlave.Main_CMD and SubID==CMD_FootBallSlave.FBSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.FootBallSlave_pb.FBSLogOnReq(),Data,Len) 
    end

    -- 砍树
    if MainID==CMD_FellTreeSlave.Main_CMD and SubID==CMD_FellTreeSlave.FTSLoginReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.FellTreeSlave_pb.FTSLoginReq(),Data,Len)
    end

    -- 篮球
    if MainID==CMD_BasketballSlave.Main_CMD and SubID==CMD_BasketballSlave.BASLoginReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.BasketballSlave_pb.BASLoginReq(),Data,Len)
    end

    --俱乐部抢庄牛牛
    if MainID==CMD_ClubQZNiuNiuGame.Main and SubID==CMD_ClubQZNiuNiuGame.SUB_REQ_LOGIN then
        tData =ProtoCoder.Parser(ProtoMgr.ClubQZNiuNiuGame_pb.ClubQZLoginGame_Q(),Data,Len)
    end

    --龙虎
    if MainID==CMD_LongHuSlave.Main_CMD and SubID==CMD_LongHuSlave.LHSLogOnReq_CMD then
        tData =ProtoCoder.Parser(LongHuSlave_pb.LHSLogOnReq(),Data,Len)
    end

    -- 直播百家乐 OB 区块链 
    if MainID==CMD_LiveBaiJiaLe.Main_CMD and SubID==CMD_LiveBaiJiaLe.BJLS_OBTableListReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.BaiJiaLeSlave_pb.BJLS_OBTableListReq(),Data,Len)
    end

    --直播牛牛
    if MainID==CMD_ZBNiuNiuSlave.Main_CMD and SubID==CMD_ZBNiuNiuSlave.NNSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.NiuNiuSlave_pb.NNSLogOnReq(),Data,Len)
    end

    --直播红黑彩
    if MainID==CMD_LottelyBR.Main_CMD and SubID==CMD_LottelyBR.LBRLogOnReq_CMD then
        tData =ProtoCoder.Parser(LottelyBR_pb.LBRLogOnReq(),Data,Len)
    end

    if tData==nil then
        return
    end
    local sTableId=tData.sTableId or ""
    local nCenterServerId =tonumber(string.match(sTableId,"(%d+)#"))
    return nCenterServerId,sTableId
end

function GameLogon.IsClubLogon(MainID,SubID,Data,Len)
    local tData=nil
    --俱乐部
    if MainID==CMD_CluSlave.Main_CMD and SubID==CMD_CluSlave.ClubSLogOnReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.ClubSlave_pb.ClubSLogOnReq(),Data,Len)
        if tData and tData.nClubId then
            return GameLogon.GetCenterServerId(tData)
        end
    end
    if MainID==CMD_CluSlave.Main_CMD and SubID==CMD_CluSlave.ClubSSwitchReq_CMD then
        tData =ProtoCoder.Parser(ProtoMgr.ClubSlave_pb.ClubSSwitchReq(),Data,Len)
        if tData and tData.nNewClubId then
            return GameLogon.GetCenterServerId(tData)
        end
    end
    return nil
end

--获取中心服id
function GameLogon.GetCenterServerId(tData)
    local nUserId = tData.nUserId
    local nClubId = tData.nClubId or tData.nNewClubId
    local nCenterServerId = nil
    
    if nUserId and nClubId then
        if nClubId==0 then
            local tUserInfo =tPubUserApi.GetUserInfo(nUserId)
            if tUserInfo then
                nClubId = tonumber(tUserInfo.nGroupId) or 0
            end
        end
        local arrNormal,arrOther = tPublicRedis.GetClubCenterServer(nClubId) --获取俱乐部中心服
        local nLastCenterServerId =tPubUserApi.GetUserEnterClubCenter(nUserId) --获取上一次登录的中心服id
        --如果上一次登录的中心服id时正常工作的中心服，就选上一次登录的中心服id
        for _,nServerId in pairs(arrNormal) do
            if nServerId==nLastCenterServerId then
                nCenterServerId = nServerId
                break
            end
        end
        --没在正常工作的中心服中找到上一次登录的中心服,随机选一个正常的中心服
        if nCenterServerId==nil then
            if #arrNormal>0 then
                nCenterServerId = arrNormal[math.random(1,#arrNormal)]
                tPubUserApi.SetUserEnterClubCenter(nUserId,nCenterServerId)
            end
        end
        --没有正常工作的中心服,随机选一个不正常工作的中心服
        if nCenterServerId==nil then
            if #arrOther>0 then
                nCenterServerId = arrNormal[math.random(1,#arrOther)]
                tPubUserApi.SetUserEnterClubCenter(nUserId,nCenterServerId)
            end
        end
    end

    return nCenterServerId
end


return GameLogon
