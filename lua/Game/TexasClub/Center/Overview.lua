
local tTableUtils = require("TableUtils")

local Overview = {}

--由大到小排序
local function _ForSort(itemA,itemB)
	return itemA.nDex>itemB.nDex
end
local function _ForSortA(itemA,itemB)
    return itemA.nProfitSum >itemB.nProfitSum
end

local function Floor_n(nNumber, n)
    local factor = math.pow(10, n)
    if nNumber >= 0 then
        return math.floor(nNumber * factor) / factor
    else
        return math.ceil(nNumber * factor) / factor
    end
end

function Overview:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tData={}
    t.nMaxNum = 100

    t.tUserLatelyChipInEnd ={}
    t.tUserIdToInfo ={}
    t.tOverviewOfPartIn ={} --nUserId => {sName="",nPlayCnt=0,nInPoolCnt=0,nTakeIn=0,nProfitSum=0,nStatus=0}
    t.arrPenalty = {}
    t.tOverviewOfLooker ={} --nUserId => {sName="",nStatus=0}
    t.nDex =0
    t.tInsuranceInfo = {}   --保险[{nUserId=,sName="",stage=1/2,buy=1,win=0}]
    t.nInsur = 0          --保险赔付
    t.nInsurGot = 0       --保险收入
	return t
end

function Overview:PaiJuStart()
    self.tUserIdToInfo ={}
end

function Overview:_GetADex()
    self.nDex =self.nDex +1
    return self.nDex
end

-- 处理玩家保险下注
function Overview:AddPenaltyRecord(data)
    table.insert(self.arrPenalty, data)
end

function Overview:DelPenaltyRecord(nUserId)
    for i=1,#self.arrPenalty do
        if self.arrPenalty[i].nUserId == nUserId then
            table.remove(self.arrPenalty, i)
            break
        end
    end
end

function Overview:GetPenaltyRecord()
    local arrRecord = tTableUtils:ReverseArray(self.arrPenalty)
    return arrRecord
end

-- 处理玩家保险下注
function Overview:DealUserInsurance(data)
    local nUserId = data.nUserId
    local insuranceInfo = self.tUserIdToInfo[nUserId].insuranceInfo or {}
    local stageData = insuranceInfo[data.stage] or {}
    if data.isSet then
        stageData = {hand = data.nPlayCnt, buy = data.buy, win = 0}
        insuranceInfo[data.stage] = stageData
    elseif data.cansel then
        insuranceInfo[data.stage] = nil
    elseif data.win then
        stageData.win = data.win
    end
    self.tUserIdToInfo[nUserId].insuranceInfo = insuranceInfo
end

-- 记录保险
function Overview:RecordInsurance()
    for userId, info in pairs(self.tUserIdToInfo) do
        if info.insuranceInfo then
            for stage, v in pairs(info.insuranceInfo) do
                table.insert(self.tInsuranceInfo, {nUserId = userId, sName = info.sName, stage = stage, buy = v.buy, win = v.win})
            end
        end
    end
end

--玩家参与牌局(sName:昵称 nChipInStart:牌局开始时的筹码)
--牌局开始时更新: 昵称,局数,带入
function Overview:UserPartIn(nUserId,sName,nChipInStart,sFaceId,nSitId)
    self.tUserIdToInfo[nUserId] ={sName=sName,nChipInStart=nChipInStart,nSitId=nSitId}
    --更新(昵称,局数,带入)
    local tViewInfo= self:_JoinList_PartIn(nUserId,sName,sFaceId)
    self:_SetLookerStatus(nUserId,1)        --变灰(旁观头像)
    tViewInfo.nPlayCnt =tViewInfo.nPlayCnt +1
   
    local nLatelyChipInEnd =self.tUserLatelyChipInEnd[nUserId]  --最近一次结算时的剩余筹码数
    local nTakeInInit =tViewInfo.nTakeIn
    if not nLatelyChipInEnd then
        tViewInfo.nTakeIn =nChipInStart
    else
        tViewInfo.nTakeIn =tViewInfo.nTakeIn +math.max(nChipInStart -nLatelyChipInEnd,0)
    end
    return (tViewInfo.nTakeIn -nTakeInInit)       --返回一个带入增加值
end

function Overview:_JoinList_PartIn(nUserId,sName,sFaceId)
    local tInfo =self.tOverviewOfPartIn[nUserId]
    if tInfo then
        tInfo.sName=sName
        tInfo.sFaceId=sFaceId
        tInfo.nStatus =0
        tInfo.nDex =self:_GetADex()
        return tInfo
    end
    tInfo ={}
    tInfo.sName=sName
    tInfo.sFaceId=sFaceId
    tInfo.nStatus =0
    tInfo.nDex =self:_GetADex()
    tInfo.nPlayCnt      = 0
    tInfo.nInPoolCnt    = 0
    tInfo.nTakeIn       = 0
    tInfo.nProfitSum    = 0
    tInfo.nTempTakeIn   = 0
    tInfo.nTakeOutChips = 0
    self.tOverviewOfPartIn[nUserId] =tInfo
    return tInfo
end

function Overview:_SetLookerStatus(nUserId,nStatus)
    local tLooker =self.tOverviewOfLooker[nUserId]
    if tLooker then
        tLooker.nStatus=nStatus       --1:变灰 0:正常
    end
end
function Overview:_SetPartInStatus(nUserId,nStatus)
    local ttInfo =self.tOverviewOfPartIn[nUserId]
    if ttInfo then
        ttInfo.nStatus =nStatus        --1:变灰 0:正常
    end
    if ttInfo and nStatus==1 and ttInfo.nPlayCnt==0 then
        self.tOverviewOfPartIn[nUserId] =nil
        self.tUserIdToInfo[nUserId]=nil
    end
end


--玩家带入
function Overview:HaveTakeIn(nUserId,sName,nChipCurrent,sFaceId)
    if nChipCurrent>0 then
        local tViewInfo= self:_JoinList_PartIn(nUserId,sName,sFaceId)
        self:_SetLookerStatus(nUserId,1)        --变灰(旁观头像)
        tViewInfo.nTempTakeIn =nChipCurrent
    end
end

--站起
function Overview:StandUp(nUserId)
    local info =self.tUserIdToInfo[nUserId]
    if info then
        info.isStandUp=true
    end
    self:_SetPartInStatus(nUserId,1)            --变灰(战绩条目)
    self:_SetLookerStatus(nUserId,0)            --高亮(旁观头像)
end
--从服进入桌子
function Overview:LookerIn(nUserId,sName,sFaceId)
    self.tOverviewOfLooker[nUserId] ={sName=sName,nStatus=0,sFaceId=sFaceId,nDex=self:_GetADex()}
end

--从服离开桌子
function Overview:UserLeave(nUserId)
    self:_SetPartInStatus(nUserId,1)        --变灰(战绩条目)
    self:_SetLookerStatus(nUserId,1)        --变灰(旁观头像)
end


--玩家入池 (加注 跟注 AllIn)
function Overview:UserInPool(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId]
    assert(tInfo~=nil)
    tInfo.isInPool =true
end

-- 是否有玩家自操作
function Overview:UserSelfOp(nUserId)
    local tInfo =self.tUserIdToInfo[nUserId]
    assert(tInfo~=nil)
    tInfo.isHaveSelfOp =true
end

--玩家结算 (nProfit:盈利, nChipInEnd:结算后剩余的筹码)
function Overview:UserSettle(nUserId,nProfit,nChipInEnd,nHandProfit)
    local tInfo =self.tUserIdToInfo[nUserId]
    assert(tInfo~=nil)
    tInfo.nProfit =nHandProfit
    tInfo.nChipInEnd =nChipInEnd
end

-- 获取保险详情
function Overview:GetInsureDetail()
    local ret = {}
    for nUserId, tInfo in pairs(self.tUserIdToInfo) do
        if tInfo.insuranceInfo then
            for stage, v in pairs(tInfo.insuranceInfo) do
                table.insert(ret, {tInfo.nSitId,stage,v.buy,v.win})
            end
        end
    end
    return ret
end

--牌局结束时更新:入池，盈亏
function Overview:PaiJuEnd()
    for nUserId, tInfo in pairs(self.tUserIdToInfo) do
       local tViewInfo= self.tOverviewOfPartIn[nUserId]
       assert(tViewInfo~=nil)
       tViewInfo.nProfitSum =tViewInfo.nProfitSum +tInfo.nProfit
       if tInfo.isInPool then
            tViewInfo.nInPoolCnt =tViewInfo.nInPoolCnt +1
       end
    --    if not tInfo.isHaveSelfOp then
    --         tViewInfo.nPlayCnt = tViewInfo.nPlayCnt - 1
    --    end
       self.tUserLatelyChipInEnd[nUserId] =tInfo.nChipInEnd
       if tInfo.insuranceInfo then
            local win, buy = 0, 0
            for stage, v in pairs(tInfo.insuranceInfo) do
                table.insert(self.tInsuranceInfo, {nUserId = nUserId, sName = tInfo.sName, stage = stage, buy = v.buy, win = v.win})
                win = win + v.win
                buy = buy + v.buy
            end
            if #(self.tInsuranceInfo) > self.nMaxNum then
                table.remove(self.tInsuranceInfo, 10)
            end
            self.nInsur = self.nInsur + buy
            self.nInsurGot = self.nInsurGot + win
        end
    end
    self.tUserIdToInfo ={}
end

function Overview:ProfitAdd(nUserId,nProfit)
    local tInfo =self.tOverviewOfPartIn[nUserId]
    if tInfo then
        tInfo.nProfitSum =tInfo.nProfitSum +nProfit
    end
end

-- 玩家撤码值
function Overview:UpdateTakeOutChips(nUserId,nChipOut)
    local tInfo =self.tOverviewOfPartIn[nUserId]
    if tInfo then
        tInfo.nTakeOutChips = tInfo.nTakeOutChips + nChipOut
        if tInfo.nTakeOutChips <= 0 then
            tInfo.nTakeOutChips = 0
        end
    end 
end

--玩家带入
function Overview:UpdateTakeIn(nUserId, nTakeIn)
    local ttInfo =self.tOverviewOfPartIn[nUserId]
    if ttInfo then
        ttInfo.nTakeIn = ttInfo.nTakeIn + nTakeIn        --1:变灰 0:正常
        if ttInfo.nTakeIn <= 0 then
            ttInfo.nTakeIn = 0
        end
    end
end

-- 获取暂存值
function Overview:GetTakeOutChips(nUserId)
    local tInfo =self.tOverviewOfPartIn[nUserId]
    if tInfo then
        return tInfo.nTakeOutChips
    end 

    return nil
end


--nDex 
function Overview:GetOverview()
    --参与过牌局的玩家
    local arrTemForSort ={}
    for nUserId,tInfo in pairs(self.tOverviewOfPartIn) do
        table.insert(arrTemForSort,{nUserId=nUserId,nDex=tInfo.nDex,nProfitSum=tInfo.nProfitSum})
    end
    table.sort(arrTemForSort,_ForSortA)
    local arrPartInUser ={}
    local tIsNormalInPartIn={}
    for n,v in ipairs(arrTemForSort) do
        local tInfo =self.tOverviewOfPartIn[v.nUserId]
        assert(tInfo~=nil)
        local item ={}
        item.nUserId =v.nUserId
        item.sName=tInfo.sName		                    --昵称
		item.nStatus=tInfo.nStatus		                --状态 0:正常 1:离桌
		item.nPlayCnt=tInfo.nPlayCnt	                --局数
        if tInfo.nPlayCnt>0 then
            item.nPayRate = Floor_n(100*tInfo.nInPoolCnt/tInfo.nPlayCnt,1)
        else
            item.nPayRate=0  --入池率
        end
		item.nTakeIn=(tInfo.nTakeIn>0) and tInfo.nTakeIn or tInfo.nTempTakeIn       --带入
		item.nProfitSum=tInfo.nProfitSum	                                        --盈亏
        item.sFaceId= tInfo.sFaceId
        item.nTakeOutChips =tInfo.nTakeOutChips
        if not (tInfo.nStatus==1 and math.abs(tInfo.nProfitSum)<0.001) then --盈利为0且变灰的不显示
            table.insert(arrPartInUser,item)
        end
        if tInfo.nStatus==0 then
            tIsNormalInPartIn[v.nUserId]=true
        end
        if n==300 then
           break
        end
    end
    --旁观玩家
    arrTemForSort ={}
    for nUserId,tInfo in pairs(self.tOverviewOfLooker) do
        table.insert(arrTemForSort,{nUserId=nUserId,nDex=tInfo.nDex})
    end
    table.sort(arrTemForSort,_ForSort)
    local arrLooker ={}
    for n,v in ipairs(arrTemForSort) do
        local tInfo =self.tOverviewOfLooker[v.nUserId]
        assert(tInfo~=nil)
        local item ={}
        item.nUserId =v.nUserId
        item.sName=tInfo.sName		                    --昵称
		item.nStatus=tInfo.nStatus		                --状态 0:正常 1:离桌
        item.sFaceId=tInfo.sFaceId
        if not tIsNormalInPartIn[v.nUserId] then
            table.insert(arrLooker,item)
        end
        if #arrLooker==11 then
            break
        end
    end
    local arrtInsurance = {}
    -- for i = 1, 30 do
    --     table.insert(arrtInsurance, {nUserId = 100000, sName = "5bCP5piO", stage = 1, buy = 30.7, win = 11.2, hand = 22})
    -- end
    for n, v in ipairs(self.tInsuranceInfo) do
        table.insert(arrtInsurance, {nUserId = v.nUserId, sName = v.sName, stage = v.stage, buy = v.buy, win = v.win, hand = v.hand or 0})
        if #arrtInsurance==30 then
            break
        end
    end

    local arrPenalty = self:GetPenaltyRecord()
    return {arrPartInUser=arrPartInUser,arrLooker=arrLooker,arrInsurance=arrtInsurance,nInsurGot=self.nInsur-self.nInsurGot,nInsur=self.nInsurGot, 
    arrPenalty=arrPenalty}
end

-- 获取 真人数量 
function Overview:_GetUserCnt()
    local nCnt = 0
    for nUserId,tInfo in pairs(self.tOverviewOfLooker) do
        nCnt=nCnt + 1
    end
    return nCnt
end 


return Overview