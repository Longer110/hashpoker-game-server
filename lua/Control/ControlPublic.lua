local tGameConfig = require("GameConfig") --  游戏匹配
local ProtoMgr   = require("ProtoManager") -- 协议管理对象 
local Define = require("ControlDefine") -- 定义
local tPublicRedis =require("PublicRedis") -- Redis 公共接口
local tBRRecord = require("BroadCastRecordApp")

ControlPublic = {}

ControlPublic.m_sKey = "Control_UserScope_50BBCB77C9F94F0B90E73F026E072B4A_"
ControlPublic.m_sTableHKey = "Control_Table_E3BBC0E1417E4B538FD23D75D996CB34_"
ControlPublic.m_sLockName = "50BBCB77C9F94F0B90E73F026E072B4A_"
ControlPublic.m_bLoadData_Config = false
-- ControlPublic.m_bLoadData_Scope = false

-- -- 请求获取UserID范围
-- function ControlPublic.GetUserIDScope()
--     local s = base.GetSP().new(ProtoMgr.Sys.DB, ProtoMgr.Sub_DB.SUB_REQ_USERID_SCOPE_DATA)
--     base.PostDatasByType(typename.db, base.GetThreadIndex(), base.GetThreadIndex(), s:GetData(), s:GetSize())
-- end


-- -- 返回UserID范围，并进行分服处理
-- function ControlPublic.OnGetUserIDScope(sClientID, Data, len)   

--     logger:info('[U] OnGetUserIDScope')

--     ControlPublic.m_bLoadData_Scope = true

--     local s = base.GetRP().new(Data, len)
--     local Read = ProtoManager.PubProto_1_pb.REP_UserID_Scope_Data()
--     Read:ParseFromString(s:GetString())

--     ControlPublic.m_arrNewScopeID = {}
--     ControlPublic.m_arrMyScopeID = {}
--     ControlPublic.m_tScopeID = {}

--     base.KillTimer(Define.TimerID_SetUserIDScope)

--     -- // SUB_REP_USERID_SCOPE_DATA = 45 用户ID范围数据返回
--     -- message REP_UserID_Scope_Data { 

--     --     // 用户ID范围项
--     --     message REP_UserID_Scope_Item { 
--     --       optional int32 nID   = 1 [default = -99];     // ID
--     --       optional int32 nStartID  = 2 [default = -99]; // 开始ID
--     --       optional int32 nEndID  = 3 [default = -99];   // 结束ID
--     --     }

--     --     repeated REP_UserID_Scope_Item tItems = 1;   // 返回数据数组
--     -- }

--     local f = function ()

--         local tTmpCurAllScopeIDs = {}
--         -- 获取所有id
--         for i, Item in ipairs(Read.tItems) do
--             local nID = math.floor(Item.nID)
--             tTmpCurAllScopeIDs[nID] = {}
--             tTmpCurAllScopeIDs[nID].nStartID = math.floor(Item.nStartID)
--             tTmpCurAllScopeIDs[nID].nEndID = math.floor(Item.nEndID)
--             ControlPublic.m_tScopeID[nID] = tTmpCurAllScopeIDs[nID] -- 记录全部范围
--             logger:info('[U] tTmpCurAllScopeIDs:'..nID)
--         end

--         -- 清除redis上无效的id
--         local tTmpKeyName = base.m_MyRedisData[1].redis:keys(ControlPublic.m_sKey..'*')

--         for _, sKeyName in ipairs(tTmpKeyName) do

--             logger:info('[U] sKeyName:'..sKeyName)

--             local sID = string.gsub(sKeyName, ControlPublic.m_sKey, '')

--             logger:info('[U] R exist S:'..sID)

--             local nID = publicApi.Double2Int(tonumber(sID))

--             if tTmpCurAllScopeIDs[nID] == nil then
--                 base.m_MyRedisData[1].redis:del(sKeyName)
--                 logger:info('[U] del redis S:'..sID)
--             end
--         end

--         -- 清除缓存上无效的id
--         ControlUserLink.ClearData(tTmpCurAllScopeIDs)

--         -- redis上已是自己的nShopID, 就设置回自己
--         tTmpKeyName = base.m_MyRedisData[1].redis:keys(ControlPublic.m_sKey..'*')

--         for _, sKeyName in ipairs(tTmpKeyName) do

--             local sID = string.gsub(sKeyName, ControlPublic.m_sKey, '')
--             local nID = publicApi.Double2Int(tonumber(sID))
--             local sServIDInfo = base.m_MyRedisData[1].redis:get(sKeyName)

--             local tV = publicApi.string_split(sServIDInfo, '\n')

--             local nServID = publicApi.Double2Int(tonumber(tV[1]))

--             if nServID == publicApi.Double2Int(ServerInfo.nServerId) then
--                 ControlPublic.m_arrMyScopeID[nID] = tTmpCurAllScopeIDs[nID]

--                 logger:info('[U] Add S:'..nID)

--                 -- 服务器key有更新
--                 if tV[2] ~= base.m_tKey then
--                     base.m_MyRedisData[1].redis:set(sKeyName, publicApi.Double2Int(ServerInfo.nServerId)..'\n'..base.m_tKey)

--                     logger:info('[U] Reset K:'..base.m_tKey)
--                 end
--             else
--                 logger:info('[U] not me:'..sID..', '..nServID..', '..publicApi.Double2Int(ServerInfo.nServerId))
--             end

--             tTmpCurAllScopeIDs[nID] = nil
--         end

--         -- 获取新的shopid
--         local nTmpNewCount = 0
--         for nID, Obj in pairs(tTmpCurAllScopeIDs) do
--             ControlPublic.m_arrNewScopeID[nID] = Obj
--             nTmpNewCount = nTmpNewCount + 1
--         end

--         -- 平均分配
--         local tServer = base.GetSrcAllKey(typename.control)
--         if nTmpNewCount > 0 and #tServer > 0 then
            
--             local nCount = publicApi.Double2Int(#Read.tItems / #tServer)
--             if nCount == 0 then
--                 nCount = 1
--             end

--             logger:info('[U] me count:'..nCount)

--             local tTmpNew = {}
--             for nID, Obj in pairs(ControlPublic.m_arrNewScopeID) do
--                 tTmpNew[nID] = Obj
--             end

--             for nID, Obj in pairs(tTmpNew) do
--                 if nCount > 0 then
--                     local sID = tostring(nID)

--                     local sKeyName = ControlPublic.m_sKey..sID

--                     local nRes = base.m_MyRedisData[1].redis:set(sKeyName, publicApi.Double2Int(ServerInfo.nServerId)..'\n'..base.m_tKey)
                    
--                     if nRes == true then
--                         ControlPublic.m_arrMyScopeID[nID] = Obj
--                         ControlPublic.m_arrNewScopeID[nID] = nil

--                         nCount = nCount - 1
--                         logger:info('[U] Add new S:'..nID)
--                     else
--                         logger:error('[U] S fail:'..nID)
--                     end
--                 else
--                     break
--                 end
--             end
--         else
--             logger:info('[U] not new s:'..nTmpNewCount..', '..#tServer)
--         end
--     end

--     base.m_MyRedisData[1].redis:lock(ControlPublic.m_sLockName)

--     xpcall(f, ControlPublic.tpLog)

--     base.m_MyRedisData[1].redis:unlock(ControlPublic.m_sLockName)

--     base.SetTimer(Define.TimerID_SetUserIDScope, Define.m_Setting.nSetShopIDTimeOut, 1, ControlPublic.OnSetScopeIDTimer) 
-- end

-- -- 用一个算法，来设置自己的ID
-- function ControlPublic.OnSetScopeIDTimer(TimerID)

--     logger:info('[U] OnSetScopeIDTimer')

--     local f = function ()

--         local tTmpNew = {}
--         for nID, Obj in pairs(ControlPublic.m_arrNewScopeID) do
--             tTmpNew[nID] = Obj
--         end

--         for nID, Obj in pairs(tTmpNew) do

--             local sID = tostring(nID)

--             local sKeyName = ControlPublic.m_sKey..sID

--             if base.m_MyRedisData[1].redis:exists(sKeyName) == false then

--                 if base.m_MyRedisData[1].redis:set(sKeyName, publicApi.Double2Int(ServerInfo.nServerId)..'\n'..base.m_tKey) == true then
--                     ControlPublic.m_arrMyScopeID[nID] = Obj
--                     ControlPublic.m_arrNewScopeID[nID] = nil

--                     logger:info('[U] add new S:'..nID)
--                     break
--                 end
--             else
--                 ControlPublic.m_arrNewScopeID[nID] = nil
--             end            
--         end

--     end

--     base.m_MyRedisData[1].redis:lock(ControlPublic.m_sLockName)

--     xpcall(f, ControlPublic.tpLog)

--     base.m_MyRedisData[1].redis:unlock(ControlPublic.m_sLockName)

--     local nTmpNewCount = 0
--     for i, nShopID in pairs(ControlPublic.m_arrNewScopeID) do
--         nTmpNewCount = nTmpNewCount + 1
--     end

--     if nTmpNewCount > 0 then
--         logger:info('[U] ing w:'..nTmpNewCount)
--         base.SetTimer(Define.TimerID_SetUserIDScope, Define.m_Setting.nSetShopIDTimeOut, 1, ControlPublic.OnSetScopeIDTimer)
--     else
--         logger:info('[U] s End')
--         ControlPublic.OnCheckUserTimer(Define.TimerID_CheckUser)
--         base.SetTimer(Define.TimerID_CheckUser, Define.m_Setting.nCheckUserTimeOut, -1, ControlPublic.OnCheckUserTimer)
--     end

-- end

-- -- 进行监控
-- function ControlPublic.OnCheckUserTimer(TimerID)
--     for nID, Obj in pairs(ControlPublic.m_arrMyScopeID) do
--         ControlUserLink.CheckUser(nID)
--         ControlUserLink.StartCheck(nID)
--     end 
-- end

-- -- 获取ID对应的Server的key
-- function ControlPublic.GetServerKeyByID(nCurID)
    
--     local sServerIDInfo = nil
--     local sServerKey = nil
--     local nScopeID = nil
--     local f = function ()        

--         for nID, Obj in pairs(ControlPublic.m_tScopeID) do

--             -- logger:info('[U] m_tScopeID Item:'..nCurID..', nStartID:'..Obj.nStartID..', nEndID:'..Obj.nEndID)

--             if nCurID >= Obj.nStartID and nCurID < Obj.nEndID then

--                 if ControlPublic.m_arrMyScopeID[nID] ~= nil then
--                     -- 是本服
--                     sServerKey = base.m_tKey
--                     nScopeID = nID

--                     logger:info('[U] Get me S:'..nScopeID..', '..sServerKey)
--                     break
--                 end

--                 local sKeyName = ControlPublic.m_sKey..nID
--                 -- ControlPublic.m_tServerIDInfo = ControlPublic.m_tServerIDInfo or {}
--                 -- sServerIDInfo = ControlPublic.m_tServerIDInfo[sKeyName]

--                 -- if sServerIDInfo == nil then
--                     logger:info('[U] Get K By S:'..sKeyName)
--                     sServerIDInfo = base.m_MyRedisData[1].redis:get(sKeyName)
--                     -- ControlPublic.m_tServerIDInfo[sKeyName] = sServerIDInfo
--                 -- end
        
--                 if sServerIDInfo ~= nil then
        
--                     logger:info('[U] S KEY:'..sServerIDInfo)
            
--                     local tV = publicApi.string_split(sServerIDInfo, '\n')
--                     sServerKey = tV[2]
--                     nScopeID = nID
--                 end

--                 break
--             end

--         end

--     end

--     -- base.m_MyRedisData[1].redis:lock(ControlPublic.m_sLockName)

--     xpcall(f, ControlPublic.tpLog)

--     -- base.m_MyRedisData[1].redis:unlock(ControlPublic.m_sLockName)

--     return nScopeID, sServerKey
-- end


-- -- 获取Table对应的Server的key
-- function ControlPublic.GetServerKeyByTable(sTableMark)
    
--     local sServerKey = nil
--     ControlPublic.m_tTableServerKey = ControlPublic.m_tTableServerKey or {}

--     local f = function ()
--         logger:info('[T] GetServerKeyByTable redis:'..sTableMark)
--         sServerKey = base.m_MyRedisData[1].redis:hget(ControlPublic.m_sTableHKey, sTableMark)
--         if sServerKey == nil then
--             sServerKey = base.m_tKey
--             base.m_MyRedisData[1].redis:hset(ControlPublic.m_sTableHKey, sTableMark, sServerKey)
--             ControlPublic.m_tTableServerKey[sTableMark] = sServerKey -- 只记录本服的
--         end

--     end

--     if ControlPublic.m_tTableServerKey[sTableMark] ~= nil then
--         sServerKey = ControlPublic.m_tTableServerKey[sTableMark]
--     else
--         base.m_MyRedisData[1].redis:lock(ControlPublic.m_sLockName)
--         xpcall(f, ControlPublic.tpLog)
--         base.m_MyRedisData[1].redis:unlock(ControlPublic.m_sLockName)
--     end

--     return sServerKey
-- end

-----------------------------------------------------------------------------------------------------------
-- 获取分组ID列表
function ControlPublic.LoadConfig()

    logger:info('[R] LoadConfig')
    tGameConfig.SetCallBack_ShopListUpdate(ControlPublic.OnGetShopIDs)
    tGameConfig.Req_AllDbConfig(0)
end

-- 返回shopid
function ControlPublic.OnGetShopIDs()   

    ControlPublic.m_bLoadData_Config = true

    -- -- 暂不运行
    -- if true then
    --     return
    -- end

    logger:info('[R] OnGetShopIDs')

    ControlPublic.m_arrNewShopIDs = {}
    -- ControlPublic.m_arrMyShopIDs = {}

    base.KillTimer(Define.TimerID_ClearShopData)

    local sKey = "Control_ShopIDs_50BBCB77C9F94F0B90E73F026E072B4A_"
    local sLockName = "50BBCB77C9F94F0B90E73F026E072B4A_"

    local f = function ()

        local tTmpCurAllShopIDs = {}
        -- 获取所有shopid
        for i, nSID in ipairs(tGameConfig.GetGroupList()) do
            tTmpCurAllShopIDs[nSID] = nSID
            logger:info('[R] tTmpCurAllShopIDs:'..nSID)
        end

        -- 清除redis上、缓存上无效的shopid
        local tTmpRedisData = base.m_MyRedisData[1].redis:hgetall(sKey)

        for sShopID, sServIDInfo in pairs(tTmpRedisData) do

            logger:info('[R] R exist S:'..sShopID)

            local nShopID = publicApi.Double2Int(tonumber(sShopID))

            if tTmpCurAllShopIDs[nShopID] == nil then
                base.m_MyRedisData[1].redis:hdel(sKey, sShopID)
                logger:info('[R] del redis S:'..sShopID)
            end
        end

        -- redis上已是自己的nShopID, 就设置回自己
        tTmpRedisData = base.m_MyRedisData[1].redis:hgetall(sKey)

        local nTmpCount = 0
        for sShopID, sServIDInfo in pairs(tTmpRedisData) do
            nTmpCount = nTmpCount + 1
        end
        logger:info('[R] R Count:'..nTmpCount)

        for sShopID, sServIDInfo in pairs(tTmpRedisData) do

            local nShopID = publicApi.Double2Int(tonumber(sShopID))

            local tV = publicApi.string_split(sServIDInfo, '\n')

            local nServID = publicApi.Double2Int(tonumber(tV[1]))

            if nServID == publicApi.Double2Int(ServerInfo.nServerId) then
                --ControlPublic.m_arrMyShopIDs[nShopID] = nShopID

                logger:info('[R] Add S:'..nShopID)

                -- 服务器key有更新
                if tV[2] ~= base.m_tKey then
                    base.m_MyRedisData[1].redis:hset(sKey, sShopID, publicApi.Double2Int(ServerInfo.nServerId)..'\n'..base.m_tKey)

                    logger:info('[R] Reset K:'..base.m_tKey)
                end
            else
                logger:info('[R] not me:'..sShopID..', '..nServID..', '..publicApi.Double2Int(ServerInfo.nServerId))
            end

            tTmpCurAllShopIDs[nShopID] = nil
        end

        -- 获取新的shopid
        local nTmpNewCount = 0
        for i, nShopID in pairs(tTmpCurAllShopIDs) do
            ControlPublic.m_arrNewShopIDs[nShopID] = nShopID
            nTmpNewCount = nTmpNewCount + 1
        end

        -- 平均分配
        local tServer = base.GetSrcAllKey(typename.control)
        if nTmpNewCount > 0 and #tServer > 0 then
            
            local nCount = publicApi.Double2Int(#tGameConfig.GetGroupList() / #tServer)
            if nCount == 0 then
                nCount = 1
            end

            logger:info('[R] me count:'..nCount)

            local tTmpNew = {}
            for k, nShopID in pairs(ControlPublic.m_arrNewShopIDs) do
                tTmpNew[k] = nShopID
            end

            for k, nShopID in pairs(tTmpNew) do
                if nCount > 0 then
                    local sShopID = tostring(nShopID)
                    local nRes = base.m_MyRedisData[1].redis:hset(sKey, sShopID, publicApi.Double2Int(ServerInfo.nServerId)..'\n'..base.m_tKey)
                    
                    if nRes == true then
                        --ControlPublic.m_arrMyShopIDs[nShopID] = nShopID
                        ControlPublic.m_arrNewShopIDs[nShopID] = nil

                        nCount = nCount - 1
                        logger:info('[R] Add new S:'..nShopID)
                    else
                        logger:error('[R] S fail:'..sShopID)
                    end
                else
                    break
                end
            end
        else
            logger:info('[R] not new s:'..nTmpNewCount..', '..#tServer)
        end
    end

    base.m_MyRedisData[1].redis:lock(sLockName)

    xpcall(f, ControlPublic.tpLog)

    base.m_MyRedisData[1].redis:unlock(sLockName)

    base.SetTimer(Define.TimerID_SetShopID, Define.m_Setting.nSetShopIDTimeOut, 1, ControlPublic.OnSetShopIDTimer) 
end

-- 用一个算法，来设置自己的shopID
function ControlPublic.OnSetShopIDTimer(TimerID)

    logger:info('[R] OnSetShopIDTimer')

    local sKey = "Control_ShopIDs_50BBCB77C9F94F0B90E73F026E072B4A_"
    local sLockName = "50BBCB77C9F94F0B90E73F026E072B4A_"

    local f = function ()

        local tTmpData = {}
        for k, nShopID in pairs(ControlPublic.m_arrNewShopIDs) do
            tTmpData[k] = nShopID
        end

        for k, nShopID in pairs(tTmpData) do

            local sShopID = tostring(nShopID)

            if base.m_MyRedisData[1].redis:hexists(sKey, sShopID) == false then

                if base.m_MyRedisData[1].redis:hset(sKey, sShopID, publicApi.Double2Int(ServerInfo.nServerId)..'\n'..base.m_tKey) == true then
                    --ControlPublic.m_arrMyShopIDs[nShopID] = nShopID
                    ControlPublic.m_arrNewShopIDs[k] = nil

                    logger:info('[R] add new S:'..nShopID)
                    break
                end
            elseif base.m_MyRedisData[1].redis:hexists(sKey, sShopID) == true then
                ControlPublic.m_arrNewShopIDs[k] = nil
            end            
        end

    end

    base.m_MyRedisData[1].redis:lock(sLockName)

    xpcall(f, ControlPublic.tpLog)

    base.m_MyRedisData[1].redis:unlock(sLockName)

    local nTmpNewCount = 0
    for i, nShopID in pairs(ControlPublic.m_arrNewShopIDs) do
        nTmpNewCount = nTmpNewCount + 1
    end

    if nTmpNewCount > 0 then
        logger:info('[R] ing w:'..nTmpNewCount)
        base.SetTimer(Define.TimerID_SetShopID, Define.m_Setting.nSetShopIDTimeOut, 1, ControlPublic.OnSetShopIDTimer)
    else
        logger:info('[R] s End')
        base.SetTimer(Define.TimerID_Check, Define.m_Setting.nCheckRoomTimeOut, -1, ControlPublic.OnCheckTimer)
        base.SetTimer(Define.TimerID_ClearShopData, Define.m_Setting.nClearShopDataTimeOut, -1, ControlPublic.OnCheckClearShopDataTimer)
    end

end

-- 检测定时器
function ControlPublic.OnCheckTimer(TimerID)

    -- for ShopKey, ShopKey in pairs(ControlPublic.m_arrMyShopIDs) do
    --     ControlLink.StartCheck(ShopKey)
    -- end 

end

-- 清除店信息定时器
function ControlPublic.OnCheckClearShopDataTimer(TimerID)

    ControlLink.CheckTimeOut()
    
    -- logger:info('OnCheckClearShopDataTimer')

    -- local tTmpSrc = {}
    -- for nShopID, ShopObj in pairs(ControlLink.m_lstControl) do
    --     tTmpSrc[nShopID] = ShopObj
    -- end

    -- for nShopID, ShopObj in pairs(tTmpSrc) do
    --     if ControlPublic.m_arrMyShopIDs[nShopID] == nil then
    --         for nGameId, GameObj in pairs(ShopObj) do
    --             for nLevelId, tLevelObj in pairs(GameObj) do
    --                 ControlLink.ClearRedisControlRoom(nShopID, nGameId, nLevelId)
    --                 ControlLink.ResetLevel(nShopID, nGameId, nLevelId) -- 重置数据
    --             end
    --         end
    --         ControlLink.m_lstControl[nShopID] = nil

    --         logger:info('[R] OnCheckClearShopDataTimer S:'..sShopID)
    --     end
    -- end
end

-- 获取shopid对应的Server的key
function ControlPublic.GetServerKeyByShopID(nShopId)

    local sKey = "Control_ShopIDs_50BBCB77C9F94F0B90E73F026E072B4A_"
    local sLockName = "50BBCB77C9F94F0B90E73F026E072B4A_"

    local sServerIDInfo = nil
    local sServerKey = nil
    local f = function ()
        local sShopID = tostring(nShopId)

        logger:info('[R] Get K By S:'..sShopID..', '..nShopId)
        sServerIDInfo = base.m_MyRedisData[1].redis:hget(sKey, sShopID)

        if sServerIDInfo ~= nil then

            logger:info('[R] S KEY:'..sServerIDInfo)
    
            local tV = publicApi.string_split(sServerIDInfo, '\n')
            sServerKey = tV[2]
        end
    end

    base.m_MyRedisData[1].redis:lock(sLockName)

    xpcall(f, ControlPublic.tpLog)

    base.m_MyRedisData[1].redis:unlock(sLockName)

    return sServerKey
end

-- 异常输出
function ControlPublic.tpLog(e)
    local kl = base.GetKernel()
    local km = km_FD55292F51334A64AC61470D796F8D43.new(kl)
    km:Log(e)
    km:Log(debug.traceback())
    return e
end

-- 请求后台APP黑名单(Web服发送后台)
function ControlPublic.SengWebAppBlackList()
    local func =function()
        local sUrl = tPublicRedis.GetAppBlackUserListDomainName()
        base.LogT("GetAppBlackUserListDomainName_",sUrl)
        if sUrl then
            tBRRecord.SendToWebGetRequset(sUrl)
        else
            base.Log("后台没有配置App黑名单域名,请后台配置 ")
        end
     end

    local isSuccee,ret =pcall(func)              --使用pcall调用，防止报错导致定时器停止
    if isSuccee==false then
        if type(ret)=="string" then
            logger:error(ret)
        else
            logger:error("pcall SengWebAppBlackList Err")
        end
    end
end

-- 获取黑名单
function _GetBlacklistByRedis(nShopID)
    nShopID = math.floor(nShopID)
    local sDefineKey = Define.APP_Blacklist..nShopID
    local tRes = base.m_MyRedisData[1].redis:hgetall(sDefineKey)
    if tRes ~= nil then
        return tRes
    end
    return nil
end

function ControlPublic.GetBlacklist(nShopID)
    local tRes = publicApi.DoCache(60 * 1, _GetBlacklistByRedis, nShopID)
    return tRes or {}
end

-- 获取其它厂商的输赢
function ControlPublic.GetOtherWinLose(nShopID, nUserID)
    nShopID = math.floor(nShopID)
    nUserID = math.floor(nUserID)
    local sDefineKey = Define.Other_WinLose..nShopID
    local sVal = base.m_MyRedisData[1].redis:hget(sDefineKey, nUserID)
    if sVal ~= nil then
        return tonumber(sVal)
    end

    return 0
end

return ControlPublic