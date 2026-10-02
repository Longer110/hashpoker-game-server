local tPubUserApi  = require("PublicUserInfo") 
local mlogger = require("logger") -- 日志对象
-- 匹配模式接口
MatchingApi = {
    tTimerObject = nil,
    tUserMgr = nil,
    tMgrAndroid = nil,
    m_TimerID = 0,
    m_tWaitMatchingList = {}, -- 等待队列
    m_tMatchingList = {},-- 真人队列。真人会匹配到一起
    m_tMatchingAndroidList = {},-- 真人匹配机器人队列
    m_tAndroidList = {},--机器人队列
    m_fMatchingSuccessEvent = nil, -- 匹配成功事件
}


function MatchingApi.Init(tTimerObject,tUserMgr,tMgrAndroid,fMatchingSuccessEvent, mTimerID)
    MatchingApi.tTimerObject = tTimerObject
    MatchingApi.tUserMgr = tUserMgr
    MatchingApi.tMgrAndroid = tMgrAndroid
    MatchingApi.m_fMatchingSuccessEvent = fMatchingSuccessEvent
    
    Base.TokenCallTimeID(mTimerID, 1000, -1, MatchingApi.ExecuteMatching)
end

-- 匹配的队列的key
function MatchingApi.MakeKey(nGroupId,nGameId,nRoomId)
    local sKey = nGroupId..nGameId..nRoomId

    return sKey
end

-- 添加用户到等待队列
-- tWaitMathingData -- 等待队列数据
--tWaitMathingData.nGroupId -- 组
-- tWaitMathingData.nGameId -- 游戏
-- tWaitMathingData.nRoomId -- 场次
-- tWaitMathingData.nUserID -- 用户ID
-- tWaitMathingData.nMaxTablePeople -- 牌桌最大人数
--tWaitMathingData.nWaitTime -- 等待时长
function MatchingApi.AddUserToWaitList(nUserID,tWaitMathingData)
    Base.LogT(tWaitMathingData)
    tWaitMathingData.nWriteTime = os.time()
    MatchingApi.m_tWaitMatchingList[nUserID] = tWaitMathingData

    local  sKey = tWaitMathingData.nGroupId..tWaitMathingData.nGameId..tWaitMathingData.nRoomId
    MatchingApi.m_tAndroidList[sKey] =  MatchingApi.m_tAndroidList[sKey] or {}
    local  tTempAndroidList =  MatchingApi.m_tAndroidList[sKey]
    if #tTempAndroidList < tWaitMathingData.nMaxTablePeople then
        MatchingApi.tMgrAndroid.AndroidEnterTable(tWaitMathingData,tWaitMathingData.nMaxTablePeople)
    end
    
end

-- 添加机器人使用
function MatchingApi.AddAndroidToList(nUserID,tWaitMathingData)
    Base.Log("AddAndroidToList")
    local  sKey = tWaitMathingData.nGroupId..tWaitMathingData.nGameId..tWaitMathingData.nRoomId
    MatchingApi.m_tAndroidList[sKey] =  MatchingApi.m_tAndroidList[sKey] or {}
    local  tTempAndroidList =  MatchingApi.m_tAndroidList[sKey]
    table.insert(tTempAndroidList,nUserID )
    return true
end

--添加用户到匹配队列
function MatchingApi.AddUserToList(nUserID,tWaitMathingData)

    local nLimit = tPubUserApi.ProbabilityOfPlayWithAndroid(tWaitMathingData.nGroupId)
    mlogger:info(string.format( "获取匹配机器人概率:%f",nLimit ))
    nLimit = 0
    local  nRandom = math.random(1,100)
    --nRandom  = nRandom / 100
    local  sKey = tWaitMathingData.nGroupId..tWaitMathingData.nGameId..tWaitMathingData.nRoomId
   
    mlogger:info(string.format( "我计算的 机器人概率:%f",nRandom ))
    if nRandom <= nLimit   then -- 匹配机器人桌子
        MatchingApi.m_tMatchingAndroidList[sKey] = MatchingApi.m_tMatchingAndroidList[sKey] or {}
        local temptMatchingList = MatchingApi.m_tMatchingAndroidList[sKey]
        temptMatchingList[nUserID] = tWaitMathingData
    else
        MatchingApi.m_tMatchingList[sKey] = MatchingApi.m_tMatchingList[sKey] or {}
        local temptMatchingList = MatchingApi.m_tMatchingList[sKey]
        temptMatchingList[nUserID] = tWaitMathingData
    end
    
end

--移除用户匹配
function MatchingApi.DelUserIDForList(UserID)
    
end

-- 执行匹配
function MatchingApi.ExecuteMatching()
    local tDelUserID = {}

    if #MatchingApi.m_tWaitMatchingList < 0 then
        Base.Log("没人")
        return 
    end

    for temUserID, tWaitMathingData in pairs(MatchingApi.m_tWaitMatchingList)   do
        local tUserInfo = MatchingApi.tUserMgr.GetUserInfo(temUserID)
        if tUserInfo == nil then
            table.insert(tDelUserID, temUserID)
        else
            if os.time() - tWaitMathingData.nWriteTime >= tWaitMathingData.nWaitTime then -- 进入匹配队列
                table.insert(tDelUserID, temUserID)
                MatchingApi.AddUserToList(temUserID,tWaitMathingData)

            else
                Base.Log(tWaitMathingData.nWriteTime)
                --tWaitMathingData.nWriteTime =  os.time()
            end
        end 
    end

    -- 从等待队列移除
    for i = 1, #tDelUserID do
        MatchingApi.m_tWaitMatchingList[tDelUserID[i]] = nil
    end

    tDelUserID = {}
    
   
    local tMatchingSuccess = {}
    -- 匹配队列真人
    -- local  sKey = tWaitMathingData.nGroupId..tWaitMathingData.nGameId..tWaitMathingData.nRoomId
    -- MatchingApi.m_tMatchingList[sKey] = MatchingApi.m_tMatchingList[sKey] or {}
    -- local tempMatchingList = MatchingApi.m_tMatchingList[sKey]

    for sTempKey,  tempMatchingList in pairs(MatchingApi.m_tMatchingList) do
        local tTempWaitMathingData = {}
        local tempPeople = {}
        for temUserID, tWaitMathingData in pairs(tempMatchingList)   do
           

            tTempWaitMathingData = tWaitMathingData
            local tUserInfo = MatchingApi.tUserMgr.GetUserInfo(temUserID)
            if tUserInfo == nil then
                table.insert(tDelUserID, temUserID)
            else
               table.insert(tempPeople,temUserID )
            end 
        end

       
        -- 匹配真人
        if #tempPeople > 0  then -- 有真人需要匹配
            if #tempPeople < tTempWaitMathingData.nMaxTablePeople  then
                if  #MatchingApi.m_tAndroidList[sTempKey] < tTempWaitMathingData.nMaxTablePeople - #tempPeople then -- 真人 + 机器人不够
                     -- 加载机器人
                     Base.Log("需要加载机器人")
                else
                    -- 真人机器人混合
                    for i = 1, #tempPeople do
                        table.insert(tMatchingSuccess,tempPeople[i] )
                        table.insert(tDelUserID,tempPeople[i] )
                    end
    
                    for i = 1, tTempWaitMathingData.nMaxTablePeople - #tempPeople do -- 
                        table.insert(tMatchingSuccess,MatchingApi.m_tAndroidList[sTempKey][1] )
                        table.remove(MatchingApi.m_tAndroidList[sTempKey], 1 )
                    end
    
                     -- 成功匹配
                     Base.Log("真人机器人混合匹配成功")
                     Base.LogT(tTempWaitMathingData)
                     Base.LogT(tMatchingSuccess)
                     MatchingApi.m_fMatchingSuccessEvent(tTempWaitMathingData, tMatchingSuccess )
                end
               
            else -- 全部真人
        
                local nLen = #tempPeople
                local nList =  math.floor( nLen / tTempWaitMathingData.nMaxTablePeople )
                local nIndex = math.floor( nLen % tTempWaitMathingData.nMaxTablePeople )
                tMatchingSuccess = {}
                for j = 1, #tempPeople,  tTempWaitMathingData.nMaxTablePeople do
                    for i = j, tTempWaitMathingData.nMaxTablePeople do
                        table.insert(tMatchingSuccess,tempPeople[i] )
                        table.insert(tDelUserID,tempPeople[i] )
                    end
                       -- 成功匹配
                    Base.Log("真人匹配成功")
                    MatchingApi.m_fMatchingSuccessEvent(tTempWaitMathingData, tMatchingSuccess )
                end
        
             
                MatchingApi.m_tAndroidList[sTempKey] =  MatchingApi.m_tAndroidList[sTempKey] or {}
                local  tTempAndroidList =  MatchingApi.m_tAndroidList[sTempKey]
                if #tTempAndroidList >=  tTempWaitMathingData.nMaxTablePeople - nIndex then
                    for i = nList * tTempWaitMathingData.nMaxTablePeople + 1 , #tempPeople do
                        table.insert(tMatchingSuccess,tempPeople[i] )
                        table.insert(tDelUserID,tempPeople[i] )
                    end
                 
                    for i = 1, tTempWaitMathingData.nMaxTablePeople - nIndex do -- 
                        table.insert(tMatchingSuccess,MatchingApi.m_tAndroidList[sTempKey][1] )
                        table.remove(MatchingApi.m_tAndroidList[sTempKey], 1 )
                        
                    end
    
                     -- 成功匹配
                     Base.Log("真人不够组合机器人匹配成功")
                     MatchingApi.m_fMatchingSuccessEvent(tTempWaitMathingData, tMatchingSuccess )
                end
                
            end
        end
        
    end


  
    for __, nTempUserID in pairs(tDelUserID) do
        -- 删掉匹配队列
        Base.Log("匹配模式，真人队列删除删除用户 :%d",nTempUserID)
        for sTempKey,  tempMatchingList in pairs(MatchingApi.m_tMatchingList) do
            for temUserID, tWaitMathingData in pairs(tempMatchingList)   do
                if temUserID == nTempUserID then
                    MatchingApi.m_tMatchingList[sTempKey][temUserID] = nil
                    break;
                end
            end
         end
        -- -- 删除机器人队列
        -- for sTempKey,  tempAndroidList in pairs(MatchingApi.m_tAndroidList) do
        --     for i = 1, #tempAndroidList do
        --         if tempAndroidList[i] == nTempUserID then
        --             table.remove(MatchingApi.m_tAndroidList[sTempKey],i )
        --             break
        --         end
        --     end

        -- end
        
    end

    -- 匹配机器人队列
    tDelUserID = {}
    for sTempKey,  tempMatchingList in pairs(MatchingApi.m_tMatchingAndroidList) do

        for temUserID, tWaitMathingData in pairs(tempMatchingList)   do
            local  tMatchingSuccess = {}
            local tUserInfo = MatchingApi.tUserMgr.GetUserInfo(temUserID)
            if tUserInfo == nil then
                table.insert(tDelUserID, temUserID)
            else
                
                MatchingApi.m_tAndroidList[sTempKey] =  MatchingApi.m_tAndroidList[sTempKey] or {}
                local  tTempAndroidList =  MatchingApi.m_tAndroidList[sTempKey]
                if #tTempAndroidList < 0  and  #tTempAndroidList < tWaitMathingData.nMaxTablePeople - 1  then
                    -- 需要加载机器人TODO
                    Base.Log("需要加载机器人")
                    break
                else
   
                    table.insert(tMatchingSuccess,temUserID )
                    for i = 1, tWaitMathingData.nMaxTablePeople - 1  do -- 需要的机器人数量
                        table.insert(tMatchingSuccess,MatchingApi.m_tAndroidList[sTempKey][1] )
                        table.remove(MatchingApi.m_tAndroidList[sTempKey], 1 )
                    end

                    table.insert(tDelUserID, temUserID)
                      -- 成功匹配
                      Base.Log("匹配成功")
                      Base.LogT(tTempWaitMathingData)
                      Base.LogT(tMatchingSuccess)
                      MatchingApi.m_fMatchingSuccessEvent(tTempWaitMathingData, tMatchingSuccess )
                end

            end 
        end
    end



    for __, nTempUserID in pairs(tDelUserID) do
        -- 删掉匹配队列
        Base.Log("匹配模式，机器人队列删除删除用户 :%d",nTempUserID)
        for sTempKey,  tempMatchingList in pairs(MatchingApi.m_tMatchingAndroidList) do
            for temUserID, tWaitMathingData in pairs(tempMatchingList)   do
                if temUserID == nTempUserID then
                    MatchingApi.m_tMatchingAndroidList[sTempKey][temUserID] = nil
                    break;
                end
            end
         end
        -- -- 删除机器人队列
        -- for sTempKey,  tempAndroidList in pairs(MatchingApi.m_tAndroidList) do
        --     for i = 1, #tempAndroidList do
        --         if tempAndroidList[i] == nTempUserID then
        --             table.remove(MatchingApi.m_tAndroidList[sTempKey],i )
        --             break
        --         end
        --     end

        -- end
        
    end
    
end
return  MatchingApi
