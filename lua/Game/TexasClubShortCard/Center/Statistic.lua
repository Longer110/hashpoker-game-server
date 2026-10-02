local RecordDbr =require("RecordDbr")
local tPublicRedis =require("PublicRedis")
local publicApi =require("publicApi")

local Statistic = {}


function Statistic:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
    t.tUserIdToInfo ={}
    t.tRobotIdToTime={}

    t.arrGiveUpUser={}
    t.arrWinUser ={}
    t.dictWinUser ={}
    t.dictGiveUpUser ={}

    t.dictUser = {}
    t.tShowdown = {} -- [userId] = {seeFlop = 0, reachShowdown = 0}
	return t
end

function Statistic:Init(profitBase,nBigBlind,nSmallBlind,nPreAnte,nZhuaTou, nPreAnteOdd)
    self.tUserIdToInfo ={}
    self.arrGiveUpUser={}
    self.arrWinUser ={}
    self.dictWinUser ={}
    self.dictGiveUpUser ={}
    self.profitBase = profitBase or 0
    self.tShowdown = {}
    self.nBigBlind = nBigBlind
    self.nSmallBlind = nSmallBlind
    self.nPreAnte = nPreAnte
    self.nPreAnteOdd = nPreAnteOdd
    self.nZhuaTou = nZhuaTou
    self.nInsurWin = 0
    self.nInsurCost = 0
end

function Statistic:AddInsure(cost, win)
    self.nInsurWin = self.nInsurWin + win
    self.nInsurCost = self.nInsurCost + cost
end

function Statistic:SetIsAndroid(nUserId,isAndroid,nTakeInAdd,sFaceId,sName)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isAndroid =isAndroid
    tInfo.nTakeInAdd =nTakeInAdd
    tInfo.sFaceId =sFaceId
    tInfo.sName =sName
    self.tUserIdToInfo[nUserId] =tInfo
    local ttInfo =self.dictUser[nUserId] or {}
    ttInfo.nTakeIn = (ttInfo.nTakeIn or 0) + nTakeInAdd
    self.dictUser[nUserId] = ttInfo
end

--玩家入池 (主动投入筹码)
function Statistic:UserInPool(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isInPool =true
    self.tUserIdToInfo[nUserId] =tInfo
end
--翻牌前加注
function Statistic:UserDoRaiseBeforeFlop(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isRaiseBeforeFlop =true
    self.tUserIdToInfo[nUserId] =tInfo
    self:UserNextDoRaiseBeforeFlop(nUserId)
end

--翻牌前对对手的加注加注
function Statistic:UserNextDoRaiseBeforeFlop(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId]
    for otherUserId, otherInfo in pairs(self.tUserIdToInfo) do
        if otherUserId ~= nUserId and otherInfo.isRaiseBeforeFlop then
            tInfo.isNextRaiseBeforeFlop = true
            return
        end
    end
end

function Statistic:UserWinAndAllIn(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isWinAndAllIn =true
    tInfo.isAllIn =true
    self.tUserIdToInfo[nUserId] =tInfo
end

function Statistic:UserAllIn(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isAllIn =true
    self.tUserIdToInfo[nUserId] =tInfo
end

function Statistic:UserProfit(nUserId,nProfit,nInsurance,nHandProfit)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.nProfit =nProfit
    tInfo.nInsurance =nInsurance
    tInfo.nHandProfit = nHandProfit
    self.tUserIdToInfo[nUserId] =tInfo
end
function Statistic:DoBet(nUserId, nBet)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.nSumBet = (tInfo.nSumBet or 0) + nBet
end

--玩家弃牌(中途站起也算)
function Statistic:UserGiveUp(nUserId,isAndroid)
    if isAndroid then
        return
    end
    table.insert(self.arrGiveUpUser,nUserId)
    self.dictGiveUpUser[nUserId] = true
end
--玩家牌局获利
function Statistic:UserWin(nUserId,nProfit,isAndroid)
    if isAndroid or nProfit<0 then
        return
    end
    table.insert(self.arrWinUser,nUserId)
    self.dictWinUser[nUserId] = (self.dictWinUser[nUserId] or 0) + nProfit
end

-- 是否有玩家自操作
function Statistic:UserSelfOp(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId] or {}
    tInfo.isHaveSelfOp = true
    self.tUserIdToInfo[nUserId] =tInfo
end

-- 所有玩家统计
function Statistic:UserStatic(nUserId,nProfit,nInsur,nHandProfit)
    local tInfo =self.dictUser[nUserId] or {}
    tInfo.tProfit = (tInfo.tProfit or 0 ) + nProfit
    tInfo.nHandProfit = (tInfo.nHandProfit or 0) + nHandProfit
    tInfo.nCount = (tInfo.nCount or 0) + 1
    tInfo.nInsur = (tInfo.nInsur or 0) + nInsur
    self.dictUser[nUserId] = tInfo
end

-- 看到翻牌圈
function Statistic:RecordSeeFlop(nUserId)
    local t = self.tShowdown[nUserId] or {seeFlop = 0, reachShowdown = 0}
    t.seeFlop = t.seeFlop + 1
    self.tShowdown[nUserId] = t
end

-- 打到摊牌
function Statistic:RecordShowdown(nUserId)
    local t = self.tShowdown[nUserId] or {seeFlop = 0, reachShowdown = 0}
    t.reachShowdown = t.reachShowdown + 1
    self.tShowdown[nUserId] = t
end

function Statistic:GetCloseAllUser()
    local dict = self.dictUser
    self.dictUser = {}
    return dict
end

function Statistic:GetCloseNoticeUser(nUserId)
    if self.dictUser[nUserId] then
        local data = self.dictUser[nUserId]
        self.dictUser[nUserId] = nil
        return data
    end
end

-- 获取玩家统计信息
function Statistic:GetUserSData(item)
    local tInfo = self.tUserIdToInfo[item.nUserId] or {}
    local tShow = self.tShowdown[item.nUserId] or {}
    item.nInPoolCount = tInfo.isInPool and 1 or 0                    --1:有入池 0:否
    item.nRaiseCountBFlop = tInfo.isRaiseBeforeFlop and 1 or 0       --1:有翻前加注 0:否
    item.nAllInAndWinCount = tInfo.isWinAndAllIn and 1 or 0          --1:AllIn且获胜 0:否
    item.nWinCount = self.dictWinUser[item.nUserId] and 1 or 0      --赢的局数
    -- if not tInfo.isHaveSelfOp then
    --     item.nWinCount = 0
    -- end
    item.nQiPaiCount = self.dictGiveUpUser[item.nUserId] and 1 or 0   --弃牌局数
    item.nNextRaiseBeforeFlop = tInfo.isNextRaiseBeforeFlop and 1 or 0 --翻前对对手的加注加注
    item.isAllIn = tInfo.isAllIn and 1 or 0                             --是否AllIn
    item.nHandProfit = tInfo.nHandProfit or 0
    item.isHaveSelfOp = tInfo.isHaveSelfOp and 1 or 1                             --是否有主动操作
    item.nSeeFlop = tShow.seeFlop or 0
    item.nReachShowdown = tShow.reachShowdown or 0
end

--持久化
--nClubId (大厅统一用0表示)
function Statistic:DoPersist(sTableId,nGameId,nClubId,nPool,nInsurPool,nGoldType,nKeepTime,sTableName,nGroupId,nSumBet,nClubIdOfCorrect,nRoomId,sumChouShui)
    local arrTableUsers ={}
    local nNow =os.time()
    for nUserId,v in  pairs(self.tUserIdToInfo) do
        local tShow = self.tShowdown[nUserId] or {}
        local tData ={}
        tData.nUserId =nUserId                                      --玩家Id
        tData.isAndroid =v.isAndroid                                --是否机器人
        tData.nProfitSum=v.nProfit                                  --总盈亏(包含保险)
        tData.nInPoolCount=v.isInPool and 1 or 0                    --1:有入池 0:否
        tData.nRaiseCountBFlop=v.isRaiseBeforeFlop and 1 or 0       --1:有翻前加注 0:否
        tData.nAllInAndWinCount=v.isWinAndAllIn and 1 or 0          --1:AllIn且获胜 0:否
        tData.nTakeInAdd =v.nTakeInAdd                              --带入
        tData.nInsurance =v.nInsurance                              --保险盈亏
        tData.sFaceId =v.sFaceId                                    --头像
        tData.sName =v.sName                                        --昵称
        tData.nSumBet =v.nSumBet or 0                               --总下注
        tData.nWinCount = self.dictWinUser[nUserId] and 1 or 0      --赢的局数
        -- if not v.isHaveSelfOp then
        --     tData.nWinCount = 0
        -- end
        tData.nQiPaiCount = self.dictGiveUpUser[nUserId] and 1 or 0   --弃牌局数
        tData.nNextRaiseBeforeFlop =v.isNextRaiseBeforeFlop and 1 or 0 --翻前对对手的加注加注
        tData.isAllIn = v.isAllIn and 1 or 0                             --是否AllIn
        tData.nHandProfit = v.nHandProfit or 0                             --本局盈亏
        tData.isHaveSelfOp = v.isHaveSelfOp and 1 or 1
        tData.nSeeFlop = tShow.seeFlop or 0
        tData.nReachShowdown = tShow.reachShowdown or 0
        
        if nClubIdOfCorrect ==0 then
            local nLastTime =nil
            if v.isAndroid then
                nLastTime =self.tRobotIdToTime[nUserId] or 0
                self.tRobotIdToTime[nUserId]=nNow
            else
                nLastTime =tPublicRedis.GetLastTexaTime(sTableName,nUserId) or 0
                tPublicRedis.SetTexaTime(sTableName,nUserId,nNow)
            end
            local a =7200               --两小时为一局
            tData.nJuShu =((math.floor(nNow / a) ~= math.floor(nLastTime / a))) and 1 or 0
        end
        table.insert(arrTableUsers,tData)
    end
    local tTableInfo ={}
    tTableInfo.sTableId =sTableId
    tTableInfo.nGameId =nGameId
    tTableInfo.nClubId =nClubId
    tTableInfo.nPool =nPool
    tTableInfo.nInsurPool =nInsurPool
    tTableInfo.nGoldType =nGoldType
    tTableInfo.nKeepTime =nKeepTime
    tTableInfo.sTableName =sTableName
    tTableInfo.nGroupId =nGroupId
    tTableInfo.nSumBet =nSumBet or 0
    tTableInfo.nRoomId = nRoomId
    tTableInfo.nBigBlind = self.nBigBlind
    tTableInfo.nSmallBlind = self.nSmallBlind
    tTableInfo.nPreAnte = self.nPreAnte
    tTableInfo.nZhuaTou = self.nZhuaTou
    tTableInfo.nSumChouShui = sumChouShui
    tTableInfo.nInsurWin = self.nInsurWin
    tTableInfo.nInsurCost = self.nInsurCost
    tTableInfo.nPreAnteOdd = self.nPreAnteOdd
    RecordDbr.TexaStatistic_WriteN(tTableInfo,arrTableUsers)     --持久化到数据库
    tPublicRedis.TexaStatistic_WriteN(tTableInfo,arrTableUsers)  --持久化到redis

  --  for _,nFoldUserId in ipairs(self.arrGiveUpUser) do
  --      for _,nWinUserId in ipairs(self.arrWinUser ) do
   --         tPublicRedis._SurrenderStatistics(nGroupId,nFoldUserId,nWinUserId)
   --     end
  --  end
end


return Statistic