
local cjson        = require("cjson")        -- json  
local tPublicRedis =require("PublicRedis") -- Redis 公共接口 

-- 活动公共接口
-- 使用回调方式 进行通知 是否成功，参考机器人 的回调 


local ActivityPublic = {
    nRequest = 1,   --  请求次数
    nMax = 9000000,
    xmlcallbackfunc = {},

}

-- 活动协议
function ActivityPublic.Protocol()   
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubActivityInfoReq_CMD,ActivityPublic.OnClubActivityInfoReq) --活动信息请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubActivityCfgReq_CMD,ActivityPublic.OnClubActivityCfgReq) --活动配置请求


    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubDrawActivityRewardReq_CMD,ActivityPublic.OnClubDrawActivityRewardReq) -- 奖励领取请求

    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubFirChargeRewardReq_CMD,FirstCharge.ClubFirChargeRewardReq) --首充奖励领取请求
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubShareRewardReq_CMD,Share.ClubShareRewardReq) --分享奖励领取请求


    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubGetActiInfoRsp_CMD,ActivityPublic.OnDBClubActivityInfoRsp)--活动信息返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubActivityHandleRsp_CMD,ActivityPublic.OnClubActivityHandleRsp)--领取活动返回
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubActivityAwardGrantRsp_CMD,ActivityPublic.OnClubActivityAwardGrantRsp)--发放活动奖励返回
    
    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubActivityReviewDataRsp_CMD,ActivityPublic.OnClubActivityReviewDataRsp)--写审核数据返回
    
    Base.RegFunc(CMD_Slave2.Main_CMD ,CMD_Slave2.ClubRecommendUserReq_CMD,Recommend.ClubRecommendUserReq)     -- 推荐关系
    Base.RegFunc(CMD_DbClubServer.Main_CMD ,CMD_DbClubServer.ClubRecommendHandleRsp_CMD,Recommend.OnClubRecommendHandleRsp)  -- 推荐完成
 

    Base.RegFunc(CMD_DbClubServer.Main_CMD,CMD_DbClubServer.ClubActivityPublicRsp_CMD,ActivityPublic.OnClubActivityPublicRsp)--活动公共操作返回
   
end

--  发送DB 
local function SendToDBServer(strProto,tSendData,nUserId)
    MsgApi.SendToDBServer(strProto,tSendData,nUserId)
end
 
local  function _GetRequest(CallBack,...)
    ActivityPublic.nRequest = ActivityPublic.nRequest + 1
    if ActivityPublic.nRequest > ActivityPublic.nMax then ActivityPublic.nRequest = 1 end
    ActivityPublic.xmlcallbackfunc[ActivityPublic.nRequest] = {ctor=CallBack, args={...},nReqTime=os.time()}
    
    return ActivityPublic.nRequest
end
 
local function _CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not SlaveData.isInitFinish then
        Base.Log("_CheckClientMsg2 开服加载数据还没结束")
        return false
    end
    local tData =SlaveAux2:Parser(Data, nLen, strProto)
    if not tData then
        Base.Log("_CheckClientMsg2  %s _Parse Err",strProto)
        return false
    end
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("_CheckClientMsg2 not find nUserId by sClientID_%s,strProto_%s",tostring(sClientID),strProto)
        return false
    end
    return true,tData,nUserId
end

-- 通知前端活动奖励更新
function ActivityPublic.SendUserActivityReward(nUserId,nActivityType)
    local ClubGetActiInfoReq = {}
    ClubGetActiInfoReq.nUserId = nUserId
    ClubGetActiInfoReq.nActivityType = nActivityType
    MsgApi.SendToDBServer("ClubGetActiInfoReq",ClubGetActiInfoReq,nUserId)
    Base.Log("_SendUserActivityReward nUserId_%d  nActivityType_%d ",nUserId,nActivityType)    
end 

--活动信息请求
function ActivityPublic.OnClubActivityInfoReq(sClientID,Data,nLen)
    local strProto = "ClubActivityInfoReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
    local ClubGetActiInfoReq = {}
    ClubGetActiInfoReq.nUserId = tData.nUserId
    ClubGetActiInfoReq.nActivityType = tData.nActivityType
    MsgApi.SendToDBServer("ClubGetActiInfoReq",ClubGetActiInfoReq,tData.nUserId)

end

--DB服返回 活动信息返回
function ActivityPublic.OnDBClubActivityInfoRsp(sReturnKey, Data, nLen)
    local strProto = "ClubGetActiInfoRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    local tUser = UserManager.GetUserInfo(tData.nUserId)
    if not tUser then
        Base.Log("_OnDBClubActivityInfoRsp 玩家信息不存在 nUserId:%d",nUserId)
        return
    end
    local nGroupId = tUser.nGroupId or -1

    local nActiSwitchData = RedisCahche._GetActiSwitch(nGroupId)

    local nShareSwitch = PublicUserInfo.GetUserShareActiSwitch(tData.nUserId)

    if nShareSwitch == 1 then --此处1为关
        nActiSwitchData.isShareOndOn = 1 --关
    end

    local arrActiInfo = {}
    for k,v in pairs(tData.arrActiInfos) do
        local ActiInfo = {}
        ActiInfo.nId = v.nId
        ActiInfo.nActivityType = v.nActivityType
        ActiInfo.nAwardCount = v.nAwardCount 
        ActiInfo.nGetStatus = v.nGetStatus
        ActiInfo.nAging = v.nAging
        ActiInfo.sCreateTime = v.sCreateTime
        ActiInfo.sExpand = v.sExpand
        ActiInfo.sGetTime = v.sGetTime
        table.insert(arrActiInfo,ActiInfo)
    end

    local ClubActivityInfoRsp = {}
    ClubActivityInfoRsp.nUserId = tData.nUserId
    ClubActivityInfoRsp.nActiSwitch = Cjson.encode(nActiSwitchData)
    ClubActivityInfoRsp.nActiInfos = arrActiInfo
    MsgApi.SendToUser2(tData.nUserId,"ClubActivityInfoRsp",ClubActivityInfoRsp)
end

-- 领取活动奖励请求 
function ActivityPublic.OnClubDrawActivityRewardReq(sClientID,Data,nLen)
    local strProto = "ClubDrawActivityRewardReq"
    local isCheckPass,tData,nUserId = _CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then  return end
    if not tData then return end 

    Base.Log("_OnClubDrawActivityRewardReq nUserId_%d  nActivityType_%d nRewardId_%d ",tData.nUserId,tData.nActivityType,tData.nRewardId)
    local SendData ={}
    SendData.nUserId = nUserId
    SendData.nActivityType = tData.nActivityType
    SendData.nRewardId = tData.nRewardId
    local function _DrawAwardRlt(...)
        local arrArg = table.pack(...)
        local nUserId = arrArg[1]
        local nActivityType = arrArg[2] 
        local nRlt = arrArg[3] 
        local nAwardCount = arrArg[4] or 0
        tBase.Log("_DrawAwardRlt nUserId_%d   领取奖励 nRlt_%d nAwardCount_%d ",nUserId,nRlt,nAwardCount)  
        local ClubDrawActivityRewardRsp = {}
        ClubDrawActivityRewardRsp.nActivityType = nActivityType
        ClubDrawActivityRewardRsp.nRlt =  nRlt
        ClubDrawActivityRewardRsp.nAwardCount = nAwardCount
        MsgApi.SendToUser2(nUserId,"ClubDrawActivityRewardRsp",ClubDrawActivityRewardRsp)    

        -- 领取后成功后刷新
        if nRlt == 1 then 
            ActivityPublic.SendUserActivityReward(nUserId,nActivityType)
        end 
    end
    ActivityPublic.GetDrawActivityAward(SendData,_DrawAwardRlt,nUserId)   
end

--[[ tDate： 
    nUserId
    nActivityType   活动类型:  1首冲、2推荐、3签到、4分享
    nAwardCount     奖励金币数量
    nAging          时效： 0 当天、 1 永久
    sExpand         JSON拓展： 可存 活动信息、 活动条件
]]
-- 发放活动奖励 
function ActivityPublic.GrantActivityAward(tData,CallBack,...)         
    if not tData or not tData.nUserId or not tData.nActivityType or not tData.nAwardCount or not tData.nAging or not tData.sExpand then 
        tBase.Log("_GrantActivityAward  tData is nil  "..cjson.encode(tData))
        return 
    end 
    local sSql = string.format("call ActivityAward_Write(%d,%d,%f,%d,'%s')",
    tData.nUserId,tData.nActivityType,tData.nAwardCount,tData.nAging,tData.sExpand) 
  
    local nRequest = _GetRequest(CallBack,...)
    SendToDBServer("ClubActivityAwardGrantReq",{nRequest=nRequest,sSql=sSql},tData.nUserId)
    tBase.Log("_GrantActivityAward  发放活动奖励_%d  sSql_%s  ",nRequest,sSql)
    return 
end 

-- 发放活动奖励返回 
function ActivityPublic.OnClubActivityAwardGrantRsp(sReturnKey, Data, nLen)
    local strProto = "ClubActivityAwardGrantRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end       
    local nRequest = tData.nRequest
    if not nRequest then 
        tBase.Log("_OnClubActivityAwardGrantRsp   nRequest_%d   ",nRequest or -1 )
        return 
    end 
    local tCallback = ActivityPublic.xmlcallbackfunc[nRequest]
    if not tCallback then 
        tBase.Log("_OnClubActivityAwardGrantRsp   nRequest_%d   xmlcallbackfunc is nil ",nRequest or -1 )        
        return 
    end  
    tBase.Log("_OnClubActivityAwardGrantRsp   nRequest_%d nActivityId_%d  ",nRequest,tData.nActivityId)  
    
    local args = ActivityPublic.xmlcallbackfunc[nRequest].args
    table.insert(args,tData.nActivityId)   -- 结果: -1失败、大于0 其他成功 
    ActivityPublic.xmlcallbackfunc[nRequest].ctor(table.unpack(args))
    ActivityPublic.xmlcallbackfunc[nRequest]=nil
end

--[[ tDate： 
    nUserId
    nActivityType   活动类型:  1首冲、2推荐、3签到、4分享
    nActivityId     活动ID:  
]]
-- 领取活动奖励: 
function ActivityPublic.GetDrawActivityAward(tData,CallBack,...)        
    if not tData.nUserId or not tData.nActivityType  then 
        tBase.Log("_GetDrawActivityAward   tData is nil "..cjson.encode(tData))
        return 
    end  
    local nRewardId = tData.nRewardId or 0
    local nRequest = _GetRequest(CallBack,...)
    local sSql = string.format("call ActivityAward_Handle(%d,%d,%d)",tData.nUserId,tData.nActivityType,nRewardId) 
    SendToDBServer("ClubActivityHandleReq",{nUserId=tData.nUserId,sSql=sSql,nRequest=nRequest},tData.nUserId)
    tBase.Log("_GetDrawActivityAward  领取活动奖励_%d  nUserId_%d nActivityType: %d=%d "
    ,nRequest,tData.nUserId,tData.nActivityType,nRewardId)        
    return 
end 

-- 领取奖励返回 
function ActivityPublic.OnClubActivityHandleRsp(sReturnKey, Data, nLen)
    local strProto = "ClubActivityHandleRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then return end       
    local nRequest = tData.nRequest 
    if not nRequest then 
        tBase.Log("_OnClubActivityHandleRsp   nRequest is nil ")
        return 
    end 
    local tCallback = ActivityPublic.xmlcallbackfunc[nRequest]
    if not tCallback then 
        tBase.Log("_OnClubActivityHandleRsp    nRequest_%d   xmlcallbackfunc is nil ",nRequest or -1 )        
        return 
    end  
    tBase.Log("_OnClubActivityHandleRsp   nRequest_%d nRlt_%d nAwardCount_%f ",nRequest,tData.nRlt,tData.nAwardCount)  
    local args = ActivityPublic.xmlcallbackfunc[nRequest].args 
    table.insert(args,tData.nActivityType)
    table.insert(args,tData.nRlt)
    table.insert(args,tData.nAwardCount)
    if tData.nRlt == 1 and tData.nAwardCount > 0 and tData.nActivityType > 0 then     -- 下发奖励        
        -- 俱乐部活动奖励： 10090 +  nActivityType（活动类型:  1首冲、2推荐、3签到、4分享 5绑定）
        local nSourceType = 10090 + tData.nActivityType
        PublicUserInfo.ChangeUserTreasure({nUserID=tData.nUserId, nItemID=1, nDel=tData.nAwardCount, nSourceType=nSourceType,nRoomId=-1})
        RecordDbr.WithdrawLimit(tData.nUserId,tData.nAwardCount,10+tData.nActivityType)        --提现限制
    end  
    ActivityPublic.xmlcallbackfunc[nRequest].ctor(table.unpack(args))
    ActivityPublic.xmlcallbackfunc[nRequest]=nil
    if tData.nActivityType == 1 then
        local ClubFirChargeRewardRsp = {}
        ClubFirChargeRewardRsp.nRlt = tData.nRlt
        ClubFirChargeRewardRsp.nJushu = tData.nJushu
        MsgApi.SendToUser2(tData.nUserId,"ClubFirChargeRewardRsp",ClubFirChargeRewardRsp)
    end
    if tData.nActivityType == 4 then
        local ClubShareRewardRsp = {}
        ClubShareRewardRsp.nRlt = tData.nRlt
        ClubShareRewardRsp.nJushu = tData.nJushu
        MsgApi.SendToUser2(tData.nUserId,"ClubShareRewardRsp",ClubShareRewardRsp)
    end
end
  
--[[ tDate：  
    db 公共存在 
]]
-- DB公共操作: 
function ActivityPublic.ClubActivityPublicReq(tData,CallBack,...)    
    if not tData.sSql then 
        assert(tData.sSql ~= nil," ClubActivityPublicReq  sSql is nil ")
        return 
    end 
    local nRequest = 0 
    if CallBack then  
        nRequest = _GetRequest(CallBack,...)
    end 
    SendToDBServer("ClubActivityPublicReq",{sSql=tData.sSql,nRequest=nRequest})
    tBase.Log("_ClubActivityPublicReq  nRequest_%d = sSql_%s ",nRequest,tData.sSql)        
    return 
end 

-- DB公共操作返回 
function ActivityPublic.OnClubActivityPublicRsp(sReturnKey, Data, nLen)
    local strProto = "ClubActivityPublicRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then return end       
    local nRequest = tData.nRequest 
    if not nRequest then 
        tBase.Log("_OnClubActivityHandleRsp   nRequest is nil ")
        return 
    end 
    local tCallback = ActivityPublic.xmlcallbackfunc[nRequest]
    if not tCallback then 
        tBase.Log("_OnClubActivityPublicRsp    nRequest_%d   xmlcallbackfunc is nil ",nRequest)        
        return 
    end  
    tBase.Log("_OnClubActivityPublicRsp   nRequest_%d sArrRows_%s   ",nRequest,tData.sArrRows)  
    
    local args = ActivityPublic.xmlcallbackfunc[nRequest].args
    table.insert(args,tData.sArrRows)   -- 添加参数到回调中
    ActivityPublic.xmlcallbackfunc[nRequest].ctor(table.unpack(args))
    ActivityPublic.xmlcallbackfunc[nRequest]=nil 
end

--写审核数据返回
function ActivityPublic.OnClubActivityReviewDataRsp(sReturnKey, Data, nLen)
    local strProto = "ClubActivityReviewDataRsp"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
    tBase.Log("_OnClubActivityReviewDataRsp  写审核数据返回 nUserId_%d nRlt:%d ",tData.nUserId,tData.nRlt)
    local ErrorInfo = ""
    if tData.nRlt == 0 then
        ErrorInfo = "success"
    elseif tData.nRlt == -2 then
        ErrorInfo = "repeated submission"
    else
        ErrorInfo = "error"
    end
    local sJsonData = {}
    sJsonData.code = tData.nRlt
    sJsonData.text = ErrorInfo
    local ClubRechargeWithdrawalRsp = {}
    ClubRechargeWithdrawalRsp.nUserId = tData.nUserId
    ClubRechargeWithdrawalRsp.res = cjson.encode(sJsonData)
    MsgApi.SendToUser2(tData.nUserId,"ClubRechargeWithdrawalRsp",ClubRechargeWithdrawalRsp)
end

--活动配置请求
function ActivityPublic.OnClubActivityCfgReq(sClientID,Data,nLen)
    local strProto = "ClubActivityCfgReq"
    local isCheckPass,tData,nUserId = MsgClient._CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then return end
    if not tData then return end
    if tData.nCfgType == 1 then 
        local sRecommendShareUrl = RedisCahche._GetPayUrl("sRecommendShareUrl")
        local ClubActivityCfgRsp = {}
        ClubActivityCfgRsp.nCfgType = tData.nCfgType
        ClubActivityCfgRsp.sRecommendShareUrl = sRecommendShareUrl or ""
        MsgApi.SendToClient2(sClientID,"ClubActivityCfgRsp",ClubActivityCfgRsp) 
        tBase.Log("_OnClubActivityCfgReq   sRecommendShareUrl_%s ",sRecommendShareUrl)
    end 
end

return ActivityPublic