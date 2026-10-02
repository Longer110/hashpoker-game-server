local cjson        = require("cjson")        -- json  

-- 推荐活动
local Recommend = {
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

-- 推荐人关系: 推荐人与新用户ID      
function Recommend.ClubRecommendUserReq(sClientID,Data,nLen)
    local strProto = "ClubRecommendUserReq"
    local isCheckPass,tData,nUserId = _CheckClientMsg2(sClientID, strProto, Data, nLen)
    if not isCheckPass then
        return
    end
    if not tData then
        return
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then 
        Base.Log("_ClubRecommendUserReq nUserId_%d  tUser is nil",nUserId)    
        return 
    end 
    Base.Log("_ClubRecommendUserReq nUserId_%d nRecommendId_%d ",tData.nUserId,tData.nRecommendId)
     
    -- 建立绑定关系    
    local sSql = string.format("call ActivityRecommend_BinDing(%d,%d)",tData.nUserId,tData.nRecommendId) 
    ActivityPublic.ClubActivityPublicReq({sSql=sSql}) 
end

local function _GetRecommendCfg(nGroupId,nRecommendCnt)
    local tCfg = RedisCahche._GetActiSwitch(nGroupId)
    if not tCfg or (not tCfg.sRecommendAward) then 
        return 
    end 
    local tCfg = cjson.decode(tCfg.sRecommendAward) 
    for _, v in pairs(tCfg) do
        if nRecommendCnt >= tonumber(v.nMin) and nRecommendCnt <= tonumber(v.nMax) then 
            Base.Log("_GetRecommendCfg nGroupId_%d  nRecommendCnt_%d nAward_%d",nGroupId,nRecommendCnt,v.nAward)       
            return tonumber(v.nAward) 
        end  
    end 
    return 
end

-- 获取推荐人数量奖励 
local function _GetRecommendAwardCnt(nGroupId,nRecommendCnt)
    local nAward = _GetRecommendCfg(nGroupId,nRecommendCnt) 
    if nAward then 
        return nAward
    end 
    if nRecommendCnt <= 2 then 
        return 100
    elseif nRecommendCnt >= 3 and nRecommendCnt <= 5 then
        return 150
    elseif nRecommendCnt >= 6 and nRecommendCnt <= 10 then
        return 200
    elseif nRecommendCnt >= 11 and nRecommendCnt <= 20 then
        return 300 
    end  
end

--推荐操作
function Recommend.OnClubRecommendHandleRsp(sClientID,Data,nLen)
    local strProto = "ClubRecommendHandleRsp" 
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then return end     
    Base.Log("_OnClubRecommendHandleRsp nHandle_%d  %s ",tData.nHandle,tData.sJson)       
    if tData.nHandle == 1 then  -- 推荐成功
        local tRecommend = cjson.decode(tData.sJson)
        if not tRecommend then 
            return 
        end 
        local nRecommendId =tonumber(tRecommend.nRecommendId)
        local nRecommendCnt =tonumber(tRecommend.nRecommendCnt)   -- 当前提交的数量 
        local nGroupId =tonumber(tRecommend.nGroupId)   -- 当前提交的数量 
        if nRecommendCnt > 20 then 
            Base.Log("_OnClubRecommendHandleRsp nRecommendId_%d  nRecommendCnt_%d > 20 无需发奖励 ",nRecommendId,nRecommendCnt)   
            return 
        end 
        tRecommend.nRecommendId = nil  
        local nAwardCount =_GetRecommendAwardCnt(nGroupId,nRecommendCnt) 
        -- 发放 推荐奖励 
        local tData = {}
        tData.nUserId =  nRecommendId
        tData.nActivityType = 2 
        tData.nAwardCount = nAwardCount
        tData.nAging = 1
        tData.sExpand = cjson.encode(tRecommend)

        Base.Log("_OnClubRecommendHandleRsp nRecommendId_%d  nRecommendCnt_%d 发奖励_%d "
        ,nRecommendId,nRecommendCnt,nAwardCount)   

        -- 通知前端有奖励
        local function _SenToUserRecommendAward(...)
            local arrArg = table.pack(...)
            local nUserId = arrArg[1] 
            local nActivityId = arrArg[2]        
            tBase.Log("_SenToUserRecommendAward  通知前端有奖励  回调  nUserId_%d  nActivityId_%d ",nUserId,nActivityId)

            local tUser = UserManager.GetUserInfo(nUserId)
            if not tUser then 
                -- Base.Log("_SenToUserRecommendAward nUserId_%d  tUser is nil",nUserId)    
                return 
            end 
            ActivityPublic.SendUserActivityReward(nUserId,2)       
        end
        ActivityPublic.GrantActivityAward(tData,_SenToUserRecommendAward,nRecommendId)     
    else
        return 
    end  

end






return Recommend 