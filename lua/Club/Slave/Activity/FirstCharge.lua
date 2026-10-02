

-- 首充活动
local FirstCharge = {
    nInning = 30,       -- 满足30手方可领取游戏
}

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

local function _DrawAwardRlt(...)
    local arrArg = table.pack(...)
    local nUserId = arrArg[1]
    local nRlt = arrArg[2] 
    local nAwardCount = arrArg[3]     
    tBase.Log("_DrawAwardRlt  领取奖励结果   nUserId_%d  nRlt_%d nAwardCount_%d ",nUserId,nRlt,nAwardCount)  
end

function FirstCharge.ClubFirChargeRewardReq(sClientID,Data,nLen)
    local strProto = "ClubFirChargeRewardReq"
    local isCheckPass,tData,nUserId = _CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then 
        Base.Log("_ClubFirChargeRewardReq nUserId_%d  tUser is nil",nUserId)    
        return
    end
    Base.Log("_ClubFirChargeRewardReq nUserId_%d",tData.nUserId)

    local aData ={}
    aData.nUserId = nUserId
    aData.nActivityType = 1
    aData.nRewardId = tData.nId

    ActivityPublic.GetDrawActivityAward(aData,_DrawAwardRlt,nUserId)   

end





return FirstCharge