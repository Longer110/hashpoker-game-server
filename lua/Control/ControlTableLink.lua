
local api       = require("publicApi")    -- 共用功能接口
require("GLock")

ControlTableLink = {}

ControlTableLink.m_sLockName = 'PoolLock_C60DC5C5E4294869A871BA1CFE513F93'

ControlTableLink.m_sBaseKey = base.GetThreadIndex()..'_'..api.GetLocalIP() .. "_" .. base.GetPort()
ControlTableLink.m_nIndex = 0


-- 后台加减奖池
function ControlTableLink.OnWebSetPool(sClientID, sData, nLen)
    local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local s = base.GetRP().new(sData, nLen)
    local Read = ProtoManager.PubProto_1_pb.REQ_Control_TableInfo()
    Read:ParseFromString(s:GetString())
    
    Read.nShopId = math.floor(Read.nShopId)
    Read.nGameId = math.floor(Read.nGameId)
    Read.nLevelId = math.floor(Read.nLevelId)

    if Read.nLevelId <= 0 or Read.nLevelId >= 100 then -- 体验房和区块链不控
        ControlTableLink.SetWebRes(Read.nShopId, Read.nGameId, Read.nLevelId, Read.sTableId, 0)
        return
    end

    logger:info('[T] OnWebSetPool, nShopId:'..Read.nShopId..', nGameId:'..Read.nGameId..', nLevelId:'..Read.nLevelId..', sTableId:'..Read.sTableId..', dWinLose:'..Read.dWinLose)

    local bSend = true
    if (Read.dWinLose < 0) then -- 如果是减奖池值
        logger:info('[T] dWinLose < 0')
        if ControlTableLink.ApplyPool(Read.nShopId, Read.nGameId, Read.nLevelId, Read.sTableId, Read.dWinLose * -1.00) == false then
            bSend = false
        end
    end

    if bSend then
        logger:info('[T] bSend = true')

        local SendObj = {}
        SendObj.nShopId = Read.nShopId
        SendObj.nGameId = Read.nGameId
        SendObj.nLevelId = Read.nLevelId
        SendObj.sTableId = Read.sTableId
        SendObj.dWinLose = Read.dWinLose * -1.00
        SendObj.dDrawWater = 0
        SendObj.sPaiJuId = "-1000"

        local nIndex = SendObj.nShopId * 1000 + SendObj.nGameId  * 100 + SendObj.nLevelId * 10

        local SendControl = ProtoManager.PubProto_1_pb.REQ_Control_TableInfo()
        base.ProtoInit(SendControl, SendObj)
        local s = base.GetSP().new(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REQ_CONTROL_WINLOSE)
        s:AddString(SendControl:SerializeToString()) 
        base.PostDatasByType(typename.db, 0, nIndex, s:GetData(), s:GetSize())
    else
        ControlTableLink.SetWebRes(Read.nShopId, Read.nGameId, Read.nLevelId, Read.sTableId, 0)
    end
end

-- 设置返回web的信号
function ControlTableLink.SetWebRes(nShopID, nGameID, nRoomID, sTableID, nRes)
    -- 设置返回给web的信号
    local sResKey = nShopID.."_"..nGameID.."_"..nRoomID.."_"..sTableID
    base.m_MyRedisData[1].redis:set(sResKey, nRes)
    base.m_MyRedisData[1].redis:expire(sResKey, 60)   -- 设置60秒失效
end

-- 设置奖池
function ControlTableLink.SetPool(nShopID, nGameID, nRoomID, sTableID, dCurPool, dVal)
    
    local f = function ()

        nShopID = math.floor(nShopID)
        nGameID = math.floor(nGameID)
        nRoomID = math.floor(nRoomID)

        if nRoomID <= 0 or nRoomID >= 100 then -- 体验房和区块链不控
            return
        end

        local sBaseKey = nShopID.."_"..nGameID.."_"..nRoomID

        local sLockKey ="TableControl_1_"..sBaseKey
        local sPoolKey ="TableControl_2_"..sBaseKey

        local myredis = base.m_MyRedisData[1].redis

        logger:info('[T] SetPool, Add:'..(dVal * -1.00)..", Cur Pool:"..dCurPool)

        myredis:set(sPoolKey, dCurPool)

        if dVal > 0 then
            -- 清除锁定金额
            if myredis:hexists(sLockKey, sTableID) == true then
                myredis:hdel(sLockKey, sTableID)
            else
                logger:error("[T] lock pool val:"..sTableID)
            end
        end

        local dPool = 0.00
        local sPool = myredis:get(sPoolKey)
        if sPool ~= nil then
            dPool = tonumber(sPool)
        end
        if dPool < 0 then
            logger:error("[T] pool val error:"..sTableID..", Val:"..dPool)
        end
    end

    ControlTableLink.m_nIndex = ControlTableLink.m_nIndex + 1
    local sLockVal = ControlTableLink.m_sBaseKey.."_"..ControlTableLink.m_nIndex
    local sLockName = ControlTableLink.m_sLockName.."_"..nShopID.."_"..nGameID.."_"..nRoomID
    
    local nLockRes = GLock.Lock(base.m_MyRedisData[1].redis, sLockName, sLockVal, 500)
    if nLockRes == 0 then -- 获取锁成功
        xpcall(f, GLock.tpLog)
        GLock.UnLock(base.m_MyRedisData[1].redis, sLockName, sLockVal)
    else
        logger:error("[T] GLock Error:"..sTableID..", Val:"..nLockRes)
    end
end

-- 申请奖池额度
function ControlTableLink.ApplyPool(nShopID, nGameID, nRoomID, sTableID, dVal)
    
    logger:info('[T] ApplyPool, Val:'..dVal)

    local bRes = true

    local f = function ()

        nShopID = math.floor(nShopID)
        nGameID = math.floor(nGameID)
        nRoomID = math.floor(nRoomID)

        if nRoomID <= 0 or nRoomID >= 100 then -- 体验房和区块链不控
            bRes = true
            return
        end
        
        local sBaseKey = nShopID.."_"..nGameID.."_"..nRoomID

        local sLockKey ="TableControl_1_"..sBaseKey
        local sPoolKey ="TableControl_2_"..sBaseKey

        local myredis = base.m_MyRedisData[1].redis


        if dVal <= 0 then
            assert(false)
        else

            -- logger:info('[T] hexists, 1:'..sLockKey..", 2:"..sTableID)

            if myredis:hexists(sLockKey, sTableID) == true then
                -- 重复请求时，将原来的锁定值加回奖池
                myredis:hdel(sLockKey, sTableID)

                logger:error("[T] reset pool:"..sTableID)
            end

            local dPool = 0.00
            local sPool = myredis:get(sPoolKey)
            if sPool ~= nil then
                dPool = tonumber(sPool)
            end

            local dLockVal = 0.00
            local arVals = myredis:hvals(sLockKey)
            for _, dWLVal in ipairs(arVals) do
                dLockVal = dLockVal + dWLVal
            end

            if dPool - dLockVal < 0 then
                logger:error("[T] pool val error 2:"..sTableID..", Val:"..dPool)
            end

            if dPool - dLockVal - dVal >= 0 then

                logger:info('[T] ApplyPool, Reduce:'..dVal..", Work Pool:"..(dPool - dLockVal - dVal)..", TableID:"..sTableID)

                myredis:hset(sLockKey, sTableID, dVal)
                bRes = true
            else                
                logger:info('[T] ApplyPool Not, Reduce:'..dVal..", Work Pool:"..(dPool - dLockVal - dVal)..", TableID:"..sTableID)
                bRes = false
            end
        end
    end

    ControlTableLink.m_nIndex = ControlTableLink.m_nIndex + 1
    local sLockVal = ControlTableLink.m_sBaseKey.."_"..ControlTableLink.m_nIndex
    local sLockName = ControlTableLink.m_sLockName.."_"..nShopID.."_"..nGameID.."_"..nRoomID
    
    local nLockRes = GLock.Lock(base.m_MyRedisData[1].redis, sLockName, sLockVal, 500)
    if nLockRes == 0 then -- 获取锁成功
        xpcall(f, GLock.tpLog)
        GLock.UnLock(base.m_MyRedisData[1].redis, sLockName, sLockVal)
    else
        logger:error("[T] GLock Error 2:"..sTableID..", Val:"..nLockRes)
    end

    return bRes
end



return ControlTableLink