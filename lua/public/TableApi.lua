local tPubApi = require("publicApi")
local tPubUserApi  = require("PublicUserInfo")    --玩家数据
-- local tSrvPub     = require("SrvPublic")      -- 本服务器共享文件
local tBase = require("base")
local mlogger = require("logger") -- 日志对象 
local tJson = require("cjson")
local tSetingConfig = require("SetingConfig")
TableApi = {
    Em_Money = {
        Can     = 0, -- 允许进入 
        TooMoney = 1, -- 太多钱
        NotMoney = 2, -- 没有钱

    }
}


--MatchingNumber = 1
--匹配牌桌
-- nChannel -- 用户渠道
-- nGameType --游戏类型
-- nLevel -- 游戏等级（场次）
-- tTableMgrObject -- 牌桌管理对象
-- nMathType 匹配类型。 0 有桌就行 1:只匹配机器人 2:只匹配真人 3:优先匹配Min~max个真人的桌 其它:按后台概率来匹配
-- tParams.nMaxCnt 最大真人数目 tParams.nMinCnt 最小真人数目
function TableApi.MatchingTable( nUserID, nGameType, nLevel, nGroup, tTableMgrObject,nMatchingNumber,nMathType, tParams)

    tBase.Log("TableApi.MatchingTable UserID "..nUserID.."  nGameType "..nGameType.." nLevel "..nLevel.." nGroup "..nGroup)
    if nMatchingNumber  == nil then
        nMatchingNumber = SetingConfig.nMathRandNumber
    end

	local tTable = nil
	local bFlage = false
	local len = tonumber(#tTableMgrObject.arrTable)
	tBase.Log("发现有 %d 张 牌桌",len)

	local nGold =0
    local tUserTreasure = {}
    tUserTreasure = tPubUserApi.GetUserTreasure(nUserID)    --获得玩家的金币值
    if (tUserTreasure ~= nil) then
    	nGold = tonumber(tUserTreasure["nGold"])        --玩家的金币值 
    end

    local arrUsable = {}
    local tAndroidTable = {}
    local tUsertable = {}
    for i = 1, len do
        tTable = tTableMgrObject.arrTable[i]
        if type(tTable) == "number" and tTable == 0 then
            --tBase.Log("无效的牌桌")
        else
            if (tTable.bEnable == true) then --桌子可用状态
                --tBase.Log("发现有可用牌桌 %d   GroupID :%d:  ",tTable.nTableId,tTable.nGroup)
                if (tTable:Matching(nGameType, nLevel, nGroup)) then                    
                    if tTable:IsUserFull() == false then
                        if tTable:isAndroidTable(nGameType) then
                            table.insert(tAndroidTable,tTable.nTableId) -- 机器人桌
                        else
                            table.insert(tUsertable,tTable.nTableId) -- 真人桌
                        end
                        table.insert(arrUsable,tTable.nTableId) -- 全部桌子
                       
                        -- mlogger:info(string.format("在该组 %d 中找到空桌nTableId:  %d",nGroup,tTable.nTableId))
                    end
                end
            end
        end
    end

  
    if  nMathType == 0 and #arrUsable > 0 then -- 有桌就匹配
        local nIdx  = math.random(1,#arrUsable)
        local nTableId  = arrUsable[nIdx]
        tTable = tTableMgrObject.GetTable(nTableId)
        if (tTable == nil) then
            mlogger:info(string.format(" 该  %d  全部桌子：随机找到空桌:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
        else
            bFlage = true
            mlogger:info(string.format(" 该  %d  全部桌子总共可用牌桌： %d    随机找到空桌:   %d   ",nGroup,#arrUsable,nTableId))
        end
    elseif nMathType == 1 and #tAndroidTable  > 0 then --只匹配机器人
        local nIdx  = math.random(1,#tAndroidTable)
        local nTableId  = tAndroidTable[nIdx]
        tTable = tTableMgrObject.GetTable(nTableId)
        if (tTable == nil) then
            mlogger:info(string.format(" 该  %d  机器人桌子 随机找到空桌:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
        else
            bFlage = true
            mlogger:info(string.format(" 该  %d  机器人桌子 %d    随机找到空桌:   %d   ",nGroup,#tAndroidTable,nTableId))
        end
    elseif nMathType == 2 and #tUsertable  > 0 then --只匹配真人
        local nIdx  = math.random(1,#tUsertable)
        local nTableId  = tUsertable[nIdx]
        tTable = tTableMgrObject.GetTable(nTableId)
        if (tTable == nil) then
            mlogger:info(string.format(" 该  %d  真人桌子：随机找到空桌:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
        else
            bFlage = true
            mlogger:info(string.format(" 该  %d  真人桌子总共可用牌桌： %d    随机找到空桌:   %d   ",nGroup,#tUsertable,nTableId))
        end
    elseif nMathType == 3 and tParams then --优先匹配Min~Max个真人的桌
        local nMinCnt = tParams.nMinCnt or 0
        local nMaxCnt = tParams.nMaxCnt or 0
        local arrSuitTable = {} --合适的桌子
        if #tUsertable  > 0 then
            for _,nTableId in pairs(tUsertable) do
                local tTableOfFind = tTableMgrObject.GetTable(nTableId)
                if tTableOfFind and tTableOfFind.GetRealCnt then
                    local nRealCnt = tTableOfFind:GetRealCnt() or 0
                    if nRealCnt<nMaxCnt then
                       table.insert(arrSuitTable,{tTable=tTableOfFind,nRealCnt=nRealCnt,nTableId=nTableId})
                    end
                end
            end
        end

        if #arrSuitTable>0 then
            --按人数从大到小排序
            table.sort(arrSuitTable,function (a, b)
                return a.nRealCnt>b.nRealCnt
            end)
            tTable = arrSuitTable[1].tTable
            local nTableId = arrSuitTable[1].nTableId
            local nRealCnt = arrSuitTable[1].nRealCnt
            bFlage = true
            mlogger:info(string.format(" 该  %d  随机找到人数符合的真人桌:%d nRealCnt_%d nMinCnt_%d nMaxCnt_%d",nGroup,nTableId,nRealCnt,nMinCnt,nMaxCnt))
        end

        --找机器人桌
        if not bFlage and #tAndroidTable  > 0 then
            local nIdx  = math.random(1,#tAndroidTable)
            local nTableId  = tAndroidTable[nIdx]
            tTable = tTableMgrObject.GetTable(nTableId)
            if (tTable == nil) then
                mlogger:info(string.format(" 该  %d  随机找机器人桌子:   %d  获取牌桌失败",nGroup,nTableId))
            else
                bFlage = true
                mlogger:info(string.format(" 该  %d  随机找到机器人桌子 %d",nGroup,nTableId))
            end
        end
    else
        local nLimit = tPubUserApi.ProbabilityOfPlayWithAndroid(nGroup)
        mlogger:info(string.format( "获取匹配机器人概率:%f",nLimit ))
        local  nRandom = math.random(1,100)
        --nRandom  = nRandom / 100
        mlogger:info(string.format( "我计算的 机器人概率:%f",nRandom ))
        mlogger:info(string.format( "机器人桌子:%d, 真人桌子：%d, 全部桌子:%d  ",#tAndroidTable or 0, #tUsertable or 0, #arrUsable or 0 ))
        if nRandom <= nLimit or (nRandom > nLimit and #tUsertable <= 0 and #tAndroidTable > 0 )  then  -- 匹配机器人桌
            if #tAndroidTable  > 0 then -- 有桌子
             
             local nIdx  = math.random(1,#tAndroidTable)
             local nTableId  = tAndroidTable[nIdx]
             tTable = tTableMgrObject.GetTable(nTableId)
             if (tTable == nil) then
                 mlogger:info(string.format(" 该  %d  机器人桌子 随机找到空桌:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
             else
                 bFlage = true
                 mlogger:info(string.format(" 该  %d  机器人桌子 %d    随机找到空桌:   %d   ",nGroup,#tAndroidTable,nTableId))
             end
     
            end
             -- 匹配真人桌
         elseif #tUsertable > 0  and   nRandom > nLimit then
                 local nIdx  = math.random(1,#tUsertable)
                 local nTableId  = tUsertable[nIdx]
                 tTable = tTableMgrObject.GetTable(nTableId)
                 if (tTable == nil) then
                     mlogger:info(string.format(" 该  %d  真人桌子：随机找到空桌:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
                 else
                     bFlage = true
                     mlogger:info(string.format(" 该  %d  真人桌子总共可用牌桌： %d    随机找到空桌:   %d   ",nGroup,#tUsertable,nTableId))
                 end
             
         end

    end
   
   
    if (bFlage == false) then     --没有桌子就创建一个
        local nIdx  = tTableMgrObject.AddTable()
        base.Log("没有一张牌桌可用,只能新建一张 TableID:  %d   nGroup: %d  ",nIdx,nGroup )
        tTable = tTableMgrObject.GetTable(nIdx)
        if (tTable == nil) then
            mlogger:error("创建桌子失败")
            return tTable ,bFlage
        else
            tTable.nGameType = nGameType
            tTable.nLevel = nLevel
            tTable.nGroup = nGroup
        end
    else
        tBase.Log("已经找到有空闲的牌桌 nTableID %d  UserID %d ",tTable.nTableId,nUserID)
    end
    tBase.Log("牌桌信息 TableID: %d  GameID: %d Level %d",tTable.nTableId,nGameType,nLevel)
    return tTable, bFlage
end

-- 切换牌桌
-- nMatchingNumber 随机匹配桌
--
function TableApi.ChangeTable(nUserID, nGameType, nLevel, nGroup, tTableMgrObject,OldTable,nMatchingNumber, nRand)
    local tTable = nil
    local bFlage = false
    nRand = nRand or 0
    nMatchingNumber = nMatchingNumber or SetingConfig.nMathRandNumber
  
	local len = tonumber(#tTableMgrObject.arrTable)
	tBase.Log("发现有 %d 张 牌桌",len)

	local nGold =0
    local tUserTreasure = {}
    local arrUsable = {}
    local tAndroidTable = {}
    local tUsertable = {}
    tUserTreasure = tPubUserApi.GetUserTreasure(nUserID)    --获得玩家的金币值
    if (tUserTreasure ~= nil) then
    	nGold = tonumber(tUserTreasure["nGold"])        --玩家的金币值 
    end

    for i = 1, len do
        tTable = tTableMgrObject.arrTable[i]
        if (type(tTable) == "number" and tTable ==  0 ) or tTable ==OldTable then
            --tBase.Log("无效的牌桌")
        else           
            if (tTable.bEnable == true) then --桌子可用状态
                if tTable:Matching(nGameType, nLevel, nGroup) then
                    if tTable:IsUserFull() == false then
                        if tTable:isAndroidTable() then
                            table.insert(tAndroidTable,tTable.nTableId) -- 机器人桌
                        else
                            table.insert(tUsertable,tTable.nTableId) -- 真人桌
                        end
                        table.insert(arrUsable,tTable.nTableId) -- 全部桌子
                       
                        -- mlogger:info(string.format("在该组 %d 中找到空桌nTableId:  %d",nGroup,tTable.nTableId))
                    end
                end
            end
        end
    end


    local nLimit = tPubUserApi.ProbabilityOfPlayWithAndroid(nGroup)
    mlogger:info(string.format( "获取匹配机器人概率:%f",nLimit ))
    local  nRandom = math.random(1,100)
    mlogger:info(string.format( "我计算的 机器人概率:%f",nRandom ))
    mlogger:info(string.format( "机器人桌子:%d, 真人桌子：%d, 全部桌子:%d  ",#tAndroidTable or 0, #tUsertable or 0, #arrUsable or 0 ))
    if nRandom <= nLimit or (nRandom > nLimit and #tUsertable <= 0)  then  -- 匹配机器人桌
       if #tAndroidTable  > 0 then -- 有桌子
        local nIdx  = math.random(1,#tAndroidTable)
        local nTableId  = tAndroidTable[nIdx]
        tTable = tTableMgrObject.GetTable(nTableId)
        if (tTable == nil) then
            mlogger:info(string.format(" 该  %d  机器人桌子随机找到机器人桌子:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
        else
            bFlage = true
            mlogger:info(string.format(" 该  %d  机器人桌子 %d    随机找到空桌:   %d   ",nGroup,#tAndroidTable,nTableId))
        end

       end
    else                      -- 匹配真人桌
        if #tUsertable > 0 then
            local nIdx  = math.random(1,#tUsertable)
            local nTableId  = tUsertable[nIdx]
            tTable = tTableMgrObject.GetTable(nTableId)
            if (tTable == nil) then
                mlogger:info(string.format(" 该  %d  真人桌子：随机找到空桌:   %d  获取牌桌失败，重新创建牌桌    ",nGroup,nTableId))
            else
                bFlage = true
                mlogger:info(string.format(" 该  %d  真人桌子总共可用牌桌： %d    随机找到空桌:   %d   ",nGroup,#tUsertable,nTableId))
            end
        end
    end


    if (bFlage == false) then     --没有桌子就创建一个
        tBase.Log("没有找到一张可用的牌桌，就创建一个吧！")
        local nIdx  = tTableMgrObject.AddTable()
        base.Log("新创建的牌桌ID:%d",nIdx)
        tTable = tTableMgrObject.GetTable(nIdx)

        if (tTable == nil) then
            mlogger:error("创建桌子失败")
            return tTable ,bFlage
        else
            tTable.nGameType = OldTable.nGameType
            tTable.nLevel = OldTable.nLevel
            tTable.nGroup = OldTable.nGroup  
            tTable.nBaseScore = OldTable.nBaseScore
            tTable.nEnterFloorLimit = OldTable.nEnterFloorLimit
       end
    else
        tBase.Log("ChangeTable ================> 已经找到有空闲的牌桌 nTableID %d  UserID %d ",tTable.nTableId,nUserID)
    end

    return tTable, bFlage
end

function TableApi.NetTable(GameID,LevelID)
    local nIdx  = tTableMgrObject.AddTable()
   local tTable = tTableMgrObject.GetTable(nIdx)
    if (tTable == nil) then
        mlogger:error("创建桌子失败")
    end

    tTable.nGameType = GameID
    tTable.nLevel    = LevelID
    base.Log("成功创建一张牌桌 GameID %d  levelID %d",GameID,LevelID)
    return tTable 
end


-- 检查玩家进入房间是否足够钱
-- tTabelObject牌桌对象
function TableApi.CheckMoney(nUserID,tTabelObject)
    local tUserMoney = tPubUserApi.GetUserTreasure(nUserID)
 end

--检查玩家是否有未完成对局
function TableApi.CheckInRoom(nUserID)

end

--生成牌局的key（编号）
function TableApi.RandomKey()
    return tPubUserApi.CreatePaiJuID()
  
end

--启动统计定时器
function TableApi.OnStart(ffunc,nTimerID)
    if SetingConfig.isGm == false then
        return 
    end
    tBase.SetTimer(nTimerID,1000 * 2,-1,ffunc)
end
-- 牌桌信息上报
-- tTableData {sSeverKey,nGameID, nRoomID, nGroupID, nTableCount(桌子数), nAndroidCount （机器人数量）,nUserCount （真实用户人数） }
function TableApi.SetGameTableData(tTableData)
    
    local sSeverKey = base.m_IP.."_".. base.GetPort()
    local sKey = string.format( "StatisticsTable_%s_%d_%d",sSeverKey, tTableData.nGroupID,tTableData.nGameID)
    local  t = {}
    t.nTableCount = tTableData.nTableCount
    t.nAndroidCount = tTableData.nAndroidCount
    t.nUserCount = tTableData.nUserCount
    tBase.m_MyRedisData[1].redis:hset(sKey,tTableData.nRoomID ,tJson.encode(t))
    tBase.m_MyRedisData[1].redis:expire(sKey, 10)   -- 设置10钟失效
end


-- 根据玩家金币浮动
-- tGoldList 玩家的金币列表  nLimitGold当前玩家进入房间下限
-- 10至50倍，其中20~40倍大概率
-- 100分，1000 ~ 5000
-- 1000分，1万 ~ 5万
-- -- 5000分，5万 ~ 25万
-- function TableApi.AutoAndroidGold(tGoldList,nLimitGold)
--     local nMixGold = 0
--     local nMaxGold = 0 
--     -- local nTotal = 0
--     -- if #tGoldList <= 0 then
--     --     nMixGold = nLimitGold
--     --     nMaxGold = 1000000
--     --     return nMixGold, nMaxGold
--     -- end
--     -- for i = 1, #tGoldList do
--     --     nTotal  = nTotal + tGoldList[i]
--     -- end
   
--     -- local nAver = math.floor( nTotal / #tGoldList )

--     -- nMixGold = math.floor(nAver * 0.5)
--     -- nMaxGold = math.floor(nAver * 1.5)

--     -- if nMaxGold > 1000000 then
--     --     nMaxGold = 1000000
--     -- end
    
--     -- if nMixGold < nLimitGold then
--     --     nMixGold = nLimitGold
--     -- end

--     -- if nMixGold > 1000000 then
--     --     nMixGold = math.floor(1000000 * 0.5)
--     -- end
    
--     -- mlogger:info(string.format( "nMixGold : %f nMaxGold:%f ",nMixGold, nMaxGold  ))
--     --local nRandom = math.random(1, 1000)
--     -- if nRandom >= 1 and nRandom < 100 then  --  100分， %10 1000 ~ 5000
--     --     nMixGold = nLimitGold * 10
--     --     nMaxGold = nLimitGold * 20 
--     -- elseif  nRandom >= 100 and nRandom <= 900 then  --  100分， %80  2000- 4000
--     --     nMixGold = nLimitGold * 20
--     --     nMaxGold = nLimitGold * 40
--     -- else                                            -- --  100分， %80  4000  - 5000
--     --     nMixGold = nLimitGold * 40
--     --     nMaxGold = nLimitGold * 50
--     -- end 
--     -- return nMixGold, nMaxGold
--     local nMixTimes = 5
--     local mMaxTimes = 50

--     return nMixTimes * nLimitGold, mMaxTimes * nLimitGold
-- end

--  机器人自动金币
function TableApi.AutoAndroidGold(tGoldList,nLimitGold)

    local nMixTimes = 5
    local mMaxTimes = 50
     local nRandom = math.random(1, 1000)
    if nRandom >= 1 and nRandom < 50 then  --   %5 1000 ~ 5000
        nMixTimes = 5
        mMaxTimes = 10
       
    elseif  nRandom >= 50 and nRandom < 250 then  --  %20  10-20
        nMixTimes = 10
        mMaxTimes = 20
    elseif  nRandom >= 250 and nRandom < 600 then  --  %35  20-30
        nMixTimes = 20
        mMaxTimes = 30
    elseif  nRandom >= 600 and nRandom < 900 then  --  %30  30-40
        nMixTimes = 30
        mMaxTimes = 40
    else                                            --  %10  40-50
        nMixTimes = 40
        mMaxTimes = 50
    end 
    mlogger:info(string.format( "nMixTimes * nLimitGold:%d, mMaxTimes * nLimitGold:%d", nMixTimes * nLimitGold,mMaxTimes * nLimitGold ))
    return nMixTimes * nLimitGold, mMaxTimes * nLimitGold
end
-- 百人场的机器人上下限 
-- tGoldList = {} --暂时用空数组
-- nZhuangLimitGold -- 上庄的金币
function  TableApi.BaiRenAutoGold(tGoldList,nZhuangLimitGold)
    local nMixGold = 0
    local nMaxGold = 0 

    local nMixTimes = SetingConfig.nMinGoldTime or 5
    local mMaxTimes = SetingConfig.nMaxGoldTime or 60
    
    if nMixTimes > mMaxTimes then
        nMixTimes = 5
        mMaxTimes = 60
    end
    local nTempGold = nZhuangLimitGold / 10

    return  nMixTimes * nTempGold, mMaxTimes * nTempGold
end
function TableApi.test()
    base.Log("成功创建一张牌桌 ")
end

-- 百人机器人下注接口判断
function TableApi.BaiRenAutoXiaZhu(nGold,tBetCfg,tAreaRate,nLimitArea)
    local nRand =  math.random(1,100)
    local tTmepBetCfg = {}
    if nRand < 50 then
        return tTmepBetCfg
    end
   
    nRand =  math.random(5,10)
    nRand = nRand / 10
    
    local nXiaZhuGold = math.floor(nGold * nRand)  
    local nXiaTotalGold = 0
    -- 
    nRand =   math.random(1,nLimitArea)
    for i = 1, nRand do
        -- 计算哪个区域下
        local nRandArea =   math.random(1, 100)
        local nXiaZhuArea = 0
        for j = #tAreaRate, 1, -1 do
            if nRandArea > (j - 1 ) * tAreaRate[j] * 100 then
                nXiaZhuArea = j
                --Base.Log("获取的下注区域是：%d", nXiaZhuArea)
                break
            end
        end
        
        -- 该区域下多少钱
        tTmepBetCfg[nXiaZhuArea] = {}
        for k = 1, #tBetCfg do
            tTmepBetCfg[nXiaZhuArea][k] = 0
        end

        local nXiaZhuCount = math.random(1, 3)
        for l = 1, nXiaZhuCount do
            local nBetKey = math.random(1, #tBetCfg)
            if nXiaTotalGold + tBetCfg[nBetKey] >= nXiaZhuGold then
                Base.Log("用户金额:%f比例不够:%f", nGold,nXiaZhuGold )
                break
            end
            tTmepBetCfg[nXiaZhuArea][nBetKey] =  tTmepBetCfg[nXiaZhuArea][nBetKey] + 1
            nXiaTotalGold = nXiaTotalGold + tBetCfg[nBetKey]
        end
    end 
    --Base.LogT(tTmepBetCfg)
    return tTmepBetCfg
end

-- 体验房机器人金币
function TableApi.TiYanAutoGold()
    local nMixGold = 500
    local nMaxGold = 30000
    return math.random(500, 30000)
end

return TableApi