-- local tGameConfig = require("GameConfig") --  游戏匹配
-- local ProtoMgr   = require("ProtoManager") -- 协议管理对象 

-- local g_sNullTime = '1970-01-01 00:00:01'

-- local g_arUserInfo = {}

-- local g_CheckGetNewUser = {}
-- local g_CheckGetNewUserData = {}

-- local g_GetNewUser = {}
-- local g_GetNewUserData = {}
-- local g_GetNewUserStatData = {}

-- local g_lstUserPer = {}          -- 用户调控概率

-- local g_tUserIDToShopId = {}     -- 用户ID与组ID的关系
-- local g_tUserIDToScopeID = {}    -- 用户ID与UserID范围的关系
-- local g_tUserIDToLockLuck = {}    -- 用户ID与是否锁定、运气的关系

-- ControlUserLink = {}

-- function ControlUserLink.InitUser(tObj)
--     tObj.lstWin = {}
--     tObj.dUserStatWin = 0
--     tObj.sRTime = g_sNullTime
--     tObj.nCountControlJS = 0
-- end

-- -- 请求用户的数据
-- function ControlUserLink.GetUserData(nScopeID, tData)

--     local nMaxSendCount = Define.GetVal("MaxSendCount", Define.m_Setting.nMaxSendCount)

--     -- 插入用户数据
--     if g_arUserInfo[nScopeID] == nil then
--         g_arUserInfo[nScopeID] = {}
--     end

--     local tObj = g_arUserInfo[nScopeID]

--     local tResData = {}
--     tResData.nScopeID = nScopeID
--     tResData.sTimestamp = base.GetUniqueKey()
--     tResData.tJZ = {}

--     local nCount = 0
--     for i, nUserID in ipairs(tData) do

--         nCount = nCount + 1

--         g_GetNewUser[nUserID] = tResData.sTimestamp
--         g_GetNewUserData[nUserID] = {}
--         g_GetNewUserStatData[nUserID] = {}

--         local tItem = {}
--         tItem.nUserID = nUserID

--         if tObj[nUserID] ~= nil then
--             tItem.sLastTime = tObj[nUserID].sRTime
--         else
--             tItem.sLastTime = g_sNullTime
--         end

--         logger:info('[U] tItem.sLastTime: '..tItem.sLastTime..', UserID:'..nUserID)

--         table.insert(tResData.tJZ, tItem)

--         if nCount == nMaxSendCount or i == #tData then

--             local Send = ProtoMgr.PubProto_1_pb.REQ_Control_User_Data()
--             base.ProtoInit(Send, tResData)
--             local s = base.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_CONTROL_USER_DATA)
--             s:AddString(Send:SerializeToString())      
--             base.PostDatasByType(typename.db, nScopeID, nScopeID, s:GetData(), s:GetSize())

--             nCount = 0
--             tResData.tJZ = {}
--         end
--     end
-- end

-- function ControlUserLink.CheckUser(nScopeID)

--     -- logger:info('[U] CheckUser: '..nScopeID)

--     local tData = {}

--     local tScopeIDObj = ControlPublic.m_arrMyScopeID[nScopeID]
--     tData.nStartID = tScopeIDObj.nStartID
--     tData.nEndID = tScopeIDObj.nEndID

--     tData.tTVal = {}
--     local tGLst = tGameConfig.GetGroupList()
--     for _, nShopId in ipairs(tGLst) do 

--         local nUserTriggerVal = Define.GetValByShopID("UserTriggerVal", nShopId, Define.m_Setting.nUserTriggerVal)
--         local nUserStopTriggerVal = Define.GetValByShopID("UserStopTriggerVal", nShopId, Define.m_Setting.nUserStopTriggerVal)

--         local tItem = {}
--         tItem.nGroupID = nShopId

--         local nTVal = base.GetNormalRandomInt(nUserTriggerVal, nUserTriggerVal / 4, false)
--         if nUserStopTriggerVal >= nTVal then
--             nTVal = nUserStopTriggerVal + nUserStopTriggerVal / 4
--         end

--         tItem.nTriggerVal = nTVal

--         table.insert(tData.tTVal, tItem)
--     end

--     local SendObj = ProtoMgr.PubProto_1_pb.REQ_Check_User()
--     base.ProtoInit(SendObj, tData)
--     local s = base.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_CHECK_USER)
--     s:AddString(SendObj:SerializeToString())  

--     base.PostDatasByType(typename.db, nScopeID, nScopeID, s:GetData(), s:GetSize())

-- end


-- function ControlUserLink.SetShop(nScopeID, nUserID)

--     logger:info('[U] SetShop: '..nScopeID..', UserID:'..nUserID)

--     local dControlPer = Define.GetVal("UserAddPerInit", Define.m_Setting.nUserAddPerInit)
--     local dUserLuckPer1 = Define.GetVal("UserLuckPer1", Define.m_Setting.nUserLuckPer1)
--     local dUserLuckPer2 = Define.GetVal("UserLuckPer2", Define.m_Setting.nUserLuckPer2)

--     -- 插入用户数据
--     if g_arUserInfo[nScopeID] == nil then
--         g_arUserInfo[nScopeID] = {}
--     end

--     local tCheckTemp = {}
--     -- 通过战绩数据收集输赢信息
--     for _, item in ipairs(g_GetNewUserData[nUserID]) do 

--         local nUserID = item.nUserID
--         local sRTime = item.sRTime
--         local dWin = item.dWinLose + item.dDrawWater        

--         -- logger:info("CheckShop, nScopeID: "..nScopeID..", nUserID:"..nUserID..", sRTime:"..sRTime..", dWin:"..dWin)

--         if g_arUserInfo[nScopeID][nUserID] == nil then
--             g_arUserInfo[nScopeID][nUserID] = {}

--             -- 记录UserID与UserID范围的关系
--             g_tUserIDToScopeID[nUserID] = nScopeID

--             local tUser = g_arUserInfo[nScopeID][nUserID]
--             ControlUserLink.InitUser(tUser)
--             logger:info('[U] InitUser, nScopeID:'..nScopeID..', nUserID:'..nUserID)

--             local dPer = ControlUserLink.GetUserPer(nUserID)
--             if dPer ~= nil then -- 恢复原来的控制数据           
--                 logger:info('[U] UserInfo Init Restore:'..nUserID)
--             else                
--                 ControlUserLink.SetUserPer(nUserID, dControlPer)

--                 tCheckTemp[nUserID] = {}
--             end
--         end
        
--         local tUser = g_arUserInfo[nScopeID][nUserID]
--         -- 保存取大的记录时间，为下次读取服务
--         if tUser.sRTime == g_sNullTime or sRTime >= tUser.sRTime then

--             if tUser.sRTime == g_sNullTime then
--                 logger:info('[U] sRTime:'..tUser.sRTime..', UserID:'..nUserID)
--             end

--             tUser.sRTime = sRTime
--         else
--             logger:info('[U] OtherInfo.sRTime:'..tUser.sRTime..", sRTime:"..sRTime..', UserID:'..nUserID)
--             assert(sRTime >= tUser.sRTime)
--         end

--         table.insert(tUser.lstWin, dWin)

--         if tCheckTemp[nUserID] ~= nil then
--             tCheckTemp[nUserID] = sRTime
--         end

--         -- 手工加入用户设置
--         if g_tUserIDToLockLuck[nUserID] ~= nil and g_tUserIDToLockLuck[nUserID].nLock == 1 then
--             local tLuckObj = g_tUserIDToLockLuck[nUserID]
--             if tLuckObj.nLuck == 2 then
--                 ControlUserLink.SetUserPer(nUserID, dUserLuckPer2)
--             else
--                 ControlUserLink.SetUserPer(nUserID, dUserLuckPer1)
--             end
--         end

--     end

--     -- 写入开始控制的记录
--     for nU, sT in pairs(tCheckTemp) do 
--         ControlLink.WriteControlRecord({nSId = -1, nGId = -1, nLId = -1, 
--         nUId = nU, 
--         nType = 21, 
--         dTime = sT,
--         dVal = 0})
--     end

--     logger:info('[U] CDTmpJZs UserID:'..nUserID..', Count:'..#g_GetNewUserData[nUserID])

--     -- 通过用户统计数据收集输赢信息
--     for _, item in ipairs(g_GetNewUserStatData[nUserID]) do 

--         local nUserID = item.nUserID        
--         local dWin = item.dStatVal
--         local sRTime = item.sRTime

--         local tUser = g_arUserInfo[nScopeID][nUserID]
--         assert(tUser ~= nil)
--         assert(sRTime <= tUser.sRTime)
--         tUser.dUserStatWin = dWin

--     end

--     logger:info('[U] CDTmpUserStats UserID:'..nUserID..', Count:'..#g_GetNewUserStatData[nUserID])    
-- end

-- -- 对用户进行干预
-- function ControlUserLink.ControlUser(nScopeID)

--     logger:info('[U] ControlUser:'..nScopeID)

--     local nCheckUserMinCount = Define.GetVal("CheckUserMinCount", Define.m_Setting.nCheckUserMinCount)
--     local nTriggerPpcc = Define.GetVal("PpccPer", Define.m_Setting.nPpccPer)    
--     local nUserAddPerStep = Define.GetVal("UserAddPerStep", Define.m_Setting.nUserAddPerStep)
--     local nUserMaxPer = Define.GetVal("UserMaxPer", Define.m_Setting.nUserMaxPer)
--     local nUserAddPerInit = Define.GetVal("UserAddPerInit", Define.m_Setting.nUserAddPerInit)
--     local nMaxUserCheckJS = Define.GetVal("MaxUserCheckJS", Define.m_Setting.nMaxUserCheckJS)
--     local nMaxSendCount = Define.GetVal("MaxSendCount", Define.m_Setting.nMaxSendCount)    

--     nTriggerPpcc = nTriggerPpcc * -1

--     local tShopObj = g_arUserInfo[nScopeID]

--     local tSendData = {}
--     -- 再看是否增加调控
--     for nUserID, tUser in pairs(tShopObj) do 

--         local nShopId = g_tUserIDToShopId[nUserID]
--         if nShopId ~= nil then

--             local nUserStopTriggerVal = Define.GetValByShopID("UserStopTriggerVal", nShopId, Define.m_Setting.nUserStopTriggerVal)

--             -- 获取锁定用户
--             local nLock = 0
--             local tLockUser = g_tUserIDToLockLuck[nUserID]
--             if tLockUser ~= nil then
--                 nLock = tLockUser.nLock
--             end

--             if ControlAPI.GetSum(tUser.lstWin, tUser.dUserStatWin) > nUserStopTriggerVal or nLock == 1 then
--                 logger:info('[U] nUserID:'..nUserID..' lstWinlose Count:'..tUser.nCountControlJS..'; tag Count:'..nCheckUserMinCount)

--                 if tUser.nCountControlJS >= nCheckUserMinCount and #tUser.lstWin > 0 and nLock == 0 then

--                     tUser.nCountControlJS = 0
--                     logger:info('[U] nCountControlJS reset:'..nUserID)

--                     -- 生成一个增长态势的随机数列
--                     local tTestWin = {0}
--                     for i = 2, #tUser.lstWin, 1 do
--                         tTestWin[i] = tTestWin[i -1] + math.random(1, 100)
--                     end

--                     -- 转换成有趋势的形式
--                     local tUserVal = ControlAPI.GetValToAvg(tUser.lstWin, 1, #tUser.lstWin, #tTestWin)

--                     -- 获取相关系数
--                     local nPpcc = Statist.Ppcc(tUserVal, tTestWin, 1)

--                     logger:info('[U] nPpcc:'..nPpcc..', nPpccPer:'..nTriggerPpcc)
--                     if nPpcc > nTriggerPpcc then -- 个人还是增张态势，那要加大控制概率，希望可以扭转为负增长
--                         local dPer = ControlUserLink.GetUserPer(nUserID)
--                         assert(dPer ~= nil)
--                         dPer = dPer + nUserAddPerStep

--                         logger:info('[U] !!!nUserID:'..nUserID..' dPer:'..dPer)
--                         if dPer >= nUserMaxPer then
--                             dPer = nUserAddPerInit
--                             logger:info('[U] nUserID:'..nUserID..', per max')
--                         end
--                         ControlUserLink.SetUserPer(nUserID, dPer)
--                     else
--                         logger:info('[U] nPpcc:'..nPpcc)
--                     end
--                 end

--                 -- 保留的局数够了，要归档处理
--                 if #tUser.lstWin >= nMaxUserCheckJS then
--                     local tItem = {}
--                     tItem.nUserID = nUserID
--                     tItem.sLastTime = tUser.sRTime
--                     tItem.bEndControl = false
--                     table.insert(tSendData, tItem)
                    
--                     logger:info('[U] Stat1 nUserID:'..nUserID..', lstWin Count:'..#tUser.lstWin..', nMaxUserCheckJS:'..nMaxUserCheckJS)
--                 end
--             else
--                 if #tUser.lstWin > 0 then
--                     -- 结束调控
--                     local tItem = {}
--                     tItem.nUserID = nUserID
--                     tItem.sLastTime = tUser.sRTime
--                     tItem.bEndControl = true
--                     table.insert(tSendData, tItem)

                    
--                     ControlLink.WriteControlRecord({nSId = -1, nGId = -1, nLId = -1, 
--                     nUId = nUserID, 
--                     nType = 22, 
--                     dTime = tUser.sRTime,
--                     dVal = 0})

--                     logger:info('[U] End Control nUserID:'..nUserID..', lstWin Win:'..ControlAPI.GetSum(tUser.lstWin, 0)..', dUserStatWin:'..tUser.dUserStatWin)
--                 end
--             end
--         end
--     end

--     -- 分批处理归档数据
--     local tResData = {}
--     tResData.tJZ = {}

--     local nCount = 0
--     for i, tDel in ipairs(tSendData) do

--         nCount = nCount + 1

--         tShopObj[tDel.nUserID] = nil
--         if tDel.bEndControl == true then
--             ControlUserLink.ClearRedisControlUser(tDel.nUserID)
--             ControlUserLink.DelUserPer(tDel.nUserID)
--             g_tUserIDToShopId[tDel.nUserID] = nil
--             g_tUserIDToScopeID[tDel.nUserID] = nil
--             g_tUserIDToLockLuck[tDel.nUserID] = nil
--         end
--         logger:info('[U] del C U:'..tDel.nUserID)

--         table.insert(tResData.tJZ, tDel)

--         if nCount == nMaxSendCount or i == #tSendData then

--             local Send = ProtoMgr.PubProto_1_pb.REQ_Control_User_Stat_Data()
--             base.ProtoInit(Send, tResData)
--             local s = base.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_CONTROL_USER_STAT_DATA)
--             s:AddString(Send:SerializeToString())      
--             base.PostDatasByType(typename.db, nScopeID, nScopeID, s:GetData(), s:GetSize())

--             nCount = 0
--             tResData.tJZ = {}
--         end
--     end
-- end


-- function ControlUserLink.SetUserPer(nUserID, dPer)
--     assert(nUserID ~= nil and dPer ~= nil)

--     if g_lstUserPer[nUserID] == nil then
--         g_lstUserPer[nUserID] = {}
--     end

--     g_lstUserPer[nUserID] = dPer

--     logger:info('[U] SetUserPer, nUserID:'..nUserID..", dPer:"..dPer)
-- end

-- function ControlUserLink.GetUserPer(nUserID)

--     assert(nUserID ~= nil)

--     if g_lstUserPer[nUserID] == nil then
--         return nil
--     end

--     local dPer = g_lstUserPer[nUserID]
--     logger:info('[U] GetUserPer, '.."nUserID:"..nUserID..", dPer:"..dPer)
--     return dPer
-- end

-- function ControlUserLink.DelUserPer(nUserID)
--     assert(nUserID ~= nil)

--     if g_lstUserPer[nUserID] == nil then
--         return
--     end

--     g_lstUserPer[nUserID] = nil
--     logger:info('[U] DelUserPer, '.."nUserID:"..nUserID)
-- end


-- -- 设置redis控牌的用户
-- function ControlUserLink.SetRedisControlUser(nUserID, dWin)
    
--     local sKey ="GameControlUser"
--     local sMember =string.format("%d",nUserID)

--     local nUserSecondGoordCardPer = Define.GetVal("UserSecondGoordCardPer", Define.m_Setting.nUserSecondGoordCardPer)

--     local nUserControlType = nil
--     local sRes = base.m_MyRedisData[1].redis:hget(sKey,sMember)
--     if sRes ~= nil then
--         local tV = publicApi.string_split(sRes, '\n')
-- 		nUserControlType = math.floor(tonumber(tV[2]))
--     end

--     local dPer = ControlUserLink.GetUserPer(nUserID)
--     if dPer ~= nil then
--         local tData = {}

--         local nRes = 1

--         logger:info('[U] nUserID:'..nUserID..', Per:'..dPer)
--         if math.random(1, 100) < dPer then
--             nRes = 2
--             if math.random(1, 100) < nUserSecondGoordCardPer then -- 第二好牌
--                 nRes = 3
--             end
--         end

--         if nUserControlType == nil or  nRes > nUserControlType then
--             tData[sMember] = nUserID..'\n'..nRes..'\n'..dWin
--             base.m_MyRedisData[1].redis:hmset(sKey, tData)

--             -- base.m_MyRedisData[1].redis:expire(sKey, 60 * 5)   -- 设置5分钟失效
            
--             base.Log("SetRedisControlUser:%s,%s", sKey, sMember)

--             if nRes == 1 then
--                 logger:info('[U] nUserID:'..nUserID..', C n C')
--             elseif nRes == 2 then
--                 logger:info('[U] nUserID:'..nUserID..', C 1')
--             elseif nRes == 3 then
--                 logger:info('[U] nUserID:'..nUserID..', C 2')
--             end
--         else
--             logger:info('[U] nUserID:'..nUserID..', Use Old:'..nUserControlType)
--         end

--         return true
--     end

--     logger:info('[U] nUserID:'..nUserID..', not C')

--     return false
-- end

-- -- 清除redis控牌的用户
-- function ControlUserLink.ClearRedisControlUser(nUserID)
--     local sKey ="GameControlUser"
--     local sMember =string.format("%d", nUserID)
--     base.m_MyRedisData[1].redis:hdel(sKey, sMember)
-- end

-- function ControlUserLink.StartCheck(nScopeID)

--     -- logger:info('[U] StartCheck: '..nScopeID)

--     local Send = ProtoMgr.PubProto_1_pb.REQ_Control_GetNew_User()

--     local tScopeIDObj = ControlPublic.m_arrMyScopeID[nScopeID]
--     Send.nScopeID = nScopeID
--     Send.nStartID = tScopeIDObj.nStartID
--     Send.nEndID = tScopeIDObj.nEndID
--     Send.sTimestamp = base.GetUniqueKey()

--     g_CheckGetNewUser[nScopeID] = Send.sTimestamp
--     g_CheckGetNewUserData[nScopeID] = {}

--     local s = base.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_CONTROL_GETNEW_USER)
--     s:AddString(Send:SerializeToString())      
--     base.PostDatasByType(typename.db, nScopeID, nScopeID, s:GetData(), s:GetSize())

-- end

-- -- 返回有新数据的用户ID
-- function ControlUserLink.OnRepGetNewUserData(sClientID, Data, len)

--     local s = base.GetRP().new(Data, len)
--     local Read = ProtoManager.PubProto_1_pb.REP_Control_GetNew_User()
--     Read:ParseFromString(s:GetString())

--     Read.nScopeID = math.floor(Read.nScopeID)

--     local nScopeID = Read.nScopeID

--     if g_CheckGetNewUser[nScopeID] == nil or g_CheckGetNewUser[nScopeID] ~= Read.sTimestamp then
--         logger:debug('[U] OnRepGetNewUserData dwTimestamp Error:'..Read.nScopeID..', g_CheckGetNewUser:'..', sTimestamp:'..Read.sTimestamp)
--         return
--     end

--     g_CheckGetNewUserData[nScopeID] = g_CheckGetNewUserData[nScopeID] or {}

--     for _, tObj in ipairs(Read.tInfo) do
--         local tItem = {}
--         tItem.nUserID = tObj.nUserID
--         tItem.nLuck = tObj.nLuck
--         tItem.nLock = tObj.nLock

--         table.insert(g_CheckGetNewUserData[nScopeID], tObj.nUserID)

--         -- 记录用户与控牌锁定、运气的关系
--         if tItem.nLock == 1 then
--             g_tUserIDToLockLuck[tItem.nUserID] = tItem
--         else
--             g_tUserIDToLockLuck[tItem.nUserID] = nil
--         end
--     end

--     if Read.bEnd then
--         ControlUserLink.GetUserData(nScopeID, g_CheckGetNewUserData[nScopeID])
--         g_CheckGetNewUser[nScopeID] = nil
--         g_CheckGetNewUserData[nScopeID] = {}
--     end

-- end

-- -- 返回战绩和统计数据
-- function ControlUserLink.OnRepControlData(sClientID, Data, len)

--     logger:info('[U] OnRepControlData')

--     local s = base.GetRP().new(Data, len)
--     local Read = ProtoManager.PubProto_1_pb.REP_Control_User_Data()
--     Read:ParseFromString(s:GetString())

--     Read.nScopeID = math.floor(Read.nScopeID)

--     local nScopeID = Read.nScopeID

--     for i,v in ipairs(Read.tResData) do
--         local item = {}
--         item.nType = math.floor(Read.tResData[i].nType) or 0
--         item.sRTime = Read.tResData[i].sRTime or g_sNullTime
--         item.nUserID = math.floor(Read.tResData[i].nUserID) or -1    
--         item.dWinLose = Read.tResData[i].dWinLose or 0
--         item.dDrawWater = Read.tResData[i].dDrawWater or 0
--         item.dStatVal = Read.tResData[i].dStatVal or 0

--         -- if Read.tResData[i].bEnd then
--             -- logger:info('[U]2 Type :'..item.nType..', nUserID:'..item.nUserID..', sRTime:'..item.dWinLose)
--         -- else
--             -- logger:info('[U]1 Type :'..item.nType..', nUserID:'..item.nUserID..', sRTime:'..item.dWinLose)
--         -- end

--         assert(g_GetNewUser[item.nUserID] ~= nil)

--         if g_GetNewUser[item.nUserID] == Read.sTimestamp then
--             if item.nType == 1 then
--                 g_GetNewUserData[item.nUserID] = g_GetNewUserData[item.nUserID] or {}
--                 table.insert(g_GetNewUserData[item.nUserID], item)
--             elseif item.nType == 2 then
--                 g_GetNewUserStatData[item.nUserID] = g_GetNewUserStatData[item.nUserID] or {}
--                 table.insert(g_GetNewUserStatData[item.nUserID], item)
--             else
--                 assert(false)
--             end
--         else
--             logger:error('[U] UserID:'..nUserID..', Data reset')
--         end

--         if Read.tResData[i].bEnd then
--             g_GetNewUser[item.nUserID] = nil
--             ControlUserLink.SetShop(nScopeID, item.nUserID)
--         end
--     end

--     if Read.bEnd then
--         ControlUserLink.ControlUser(nScopeID)
--     else
--         logger:info('[U] OnRepControlData Not End')
--     end
-- end



-- -- 记录用户输赢
-- function ControlUserLink.OnSetUserInfo(sClientID, Data, len)    
    
--     logger:info('[U] OnSetUserInfo')

--     local s = base.GetRP().new(Data, len)
--     local Read = ProtoManager.PubProto_1_pb.REQ_Control_UserInfo()
--     Read:ParseFromString(s:GetString())

--     Read.nShopId = publicApi.Double2Int(Read.nShopId)
--     Read.nGameId = publicApi.Double2Int(Read.nGameId)
--     Read.nLevelId = publicApi.Double2Int(Read.nLevelId)

--     if Read.nShopId == -1 then
--         logger:info('[U] shopid == -1: '..sClientID)
--         return
--     end

--     local f = function (nUserId, isControl)
--         local nScopeID, sServerKey = ControlPublic.GetServerKeyByID(nUserId)
--         if (sServerKey ~= base.m_tKey) then
--             logger:error('[U] sServerKey ~= base.m_tKey : '..sServerKey..","..base.m_tKey)
--             assert(false)
--         end

--         Read.nShopId = tGameConfig.GetGroupId(Read.nShopId);
--         if Read.nShopId == -1 then
--             logger:error('[U] GroupID == -1 : '..sClientID)
--             return false
--         end 
--         Read.nShopId = publicApi.Double2Int(Read.nShopId)

--         -- 记录UserID和GroupID的关系
--         g_tUserIDToShopId[nUserId] = Read.nShopId

--         local nControlType = 0
--         if isControl == true then
--             nControlType = 1
--             logger:info('[U] nControlType 1')
--         end

--         local nScopeID = g_tUserIDToScopeID[nUserId]
--         if nScopeID == nil then
--             logger:info('[U] aaa b 0')
--             return false
--         end

--         if g_arUserInfo[nScopeID] == nil then
--             logger:info('[U] aaa b 1')
--             return false
--         end
--         if g_arUserInfo[nScopeID][nUserId] == nil then
--             logger:info('[U] aaa b 2')
--             return false
--         end

--         local tUser = g_arUserInfo[nScopeID][nUserId]

--         if nControlType == 1 then
--             tUser.nCountControlJS = tUser.nCountControlJS + 1
--             logger:info('[U] isControl, UserID '..nUserId..', nCountControlJS:'..tUser.nCountControlJS)
--         end

--         local dWin = ControlAPI.GetSum(tUser.lstWin, tUser.dUserStatWin)

--         -- 是否控牌
--         return ControlUserLink.SetRedisControlUser(nUserId, dWin)
--     end

--     for _, tItem in ipairs(Read.tCItems) do
--         local nUserId = math.floor(tItem.nUserId)
--         if f(nUserId, tItem.isControl) == false then

--             -- 暂不运行
--             -- 非百人游戏，都转发房间控
--             -- if Define.BRGameID[Read.nGameId] == nil then
--             --     ControlPublic.SendRoom(sClientID, Read.nShopId, Read.nGameId, Read.nLevelId, nUserId, tItem.isControl)
--             -- end
--         end
--     end
-- end

-- -- 清除缓存数据
-- function ControlUserLink.ClearData(tTmpCurAllScopeIDs)

--     local tTmpDel = {}

--     local tControlShopTmp = {}
--     for nScopeID, tObj in pairs(g_arUserInfo) do
--         if tTmpCurAllScopeIDs[nScopeID] == nil then
--             tTmpDel[nScopeID] = tObj
--         end
--     end

--     for nScopeID, tObj in ipairs(tTmpDel) do

--         for nUserID, _ in pairs(tObj) do
--             ControlUserLink.ClearRedisControlUser(nUserID)
--             ControlUserLink.DelUserPer(nUserID)
--             g_tUserIDToShopId[nUserID] = nil
--             g_tUserIDToScopeID[nUserID] = nil
--             g_tUserIDToLockLuck[nUserID] = nil
--         end

--         g_arUserInfo[nScopeID] = nil
--         logger:info('[U] del data S:'..nScopeID)
--     end
-- end

-- return ControlUserLink





