local tBase = require("base") -- 基础功能接口
local tJosn = require("cjson")
local Overview = {}
local bit = require("bit")
--由大到小排序
local function _ForSort(itemA,itemB)
	return itemA.nDex>itemB.nDex
end

local function _ForSortA_v2(itemA,itemB)
    return itemA.nProfitSum >itemB.nProfitSum
end

function Overview:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tData={}

    t.tUserIdToInfo ={}
    t.tOverviewOfPartIn ={} --nUserId => {sName="",nPlayCnt=0,nProfitSum=0,nStatus=0} 参与过牌局的用户
    t.tOverviewOfLooker ={} --nUserId => {sName="",nStatus=0} 旁观用户
    t.nDex =0
    t.nTimeStamp = os.time()
	return t
end

function Overview:PaiJuStart(nKeepTime)
    self.tUserIdToInfo ={}
    --永久牌桌两个小时清理一次
    if nKeepTime and nKeepTime == -1 then
        self:ClearDataTwoHour()
    end
end

function Overview:_GetADex()
    self.nDex =self.nDex +1
    return self.nDex
end

--玩家参与牌局(sName:昵称)
--牌局开始时更新: 昵称,局数
function Overview:UserPartIn(nUserId,sName,sFaceId)
    self.tUserIdToInfo[nUserId] ={sName=sName}
    --更新(昵称,局数)
    local tViewInfo= self:_JoinList_PartIn(nUserId,sName,sFaceId)
    self:_SetLookerStatus(nUserId,1)        --变灰(旁观头像)
    tViewInfo.nPlayCnt =tViewInfo.nPlayCnt +1
    tViewInfo.nStatus =0
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
    tInfo.nPlayCnt=0
    tInfo.nProfitSum=0
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

--玩家结算 (nProfit:盈利)
function Overview:UserSettle(nUserId,nProfit)
    local tInfo =self.tUserIdToInfo[nUserId]
    assert(tInfo~=nil)
    tInfo.nProfit =nProfit
end

--牌局结束时更新:盈亏
function Overview:PaiJuEnd()
    --tBase.Log("Overview_TestMemory---------#tUserIdToInfo_%d",#self.tUserIdToInfo)
    --tBase.Log("Overview_TestMemory---------#tOverviewOfPartIn%d",#self.tOverviewOfPartIn)
    --tBase.Log("Overview_TestMemory---------#tOverviewOfLooker%d",#self.tOverviewOfLooker)
    for nUserId,tInfo in pairs(self.tUserIdToInfo) do
       local tViewInfo= self.tOverviewOfPartIn[nUserId]
       assert(tViewInfo~=nil)
       tViewInfo.nProfitSum =tViewInfo.nProfitSum +tInfo.nProfit
    end
    self.tUserIdToInfo ={}
end

function Overview:LookerIn(nUserId,sName,sFaceId)
    self.tOverviewOfLooker[nUserId] ={sName=sName,nStatus=0,sFaceId=sFaceId,nDex=self:_GetADex()}
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

--离桌
function Overview:UserLeave(nUserId)
    self:_SetPartInStatus(nUserId,1)        --变灰(战绩条目)
    self:_SetLookerStatus(nUserId,1)        --变灰(旁观头像)
end

--nDex 
function Overview:GetOverview()
    --参与过牌局的玩家
    local arrTemForSort ={}
    for nUserId,tInfo in pairs(self.tOverviewOfPartIn) do
        table.insert(arrTemForSort,{nUserId=nUserId,nDex=tInfo.nDex,nProfitSum=tInfo.nProfitSum})
    end
    table.sort(arrTemForSort,_ForSortA_v2)
    local arrPartInUser ={}
    for n,v in ipairs(arrTemForSort) do
        local tInfo =self.tOverviewOfPartIn[v.nUserId]
        assert(tInfo~=nil)
        --tBase.Log("GetOverview arrPartInUser_%s",tJosn.encode(tInfo))
        if not (tInfo.nStatus == 1 and tInfo.nProfitSum == 0) then
            local item ={}
            item.nUserId =v.nUserId
            item.sName=tInfo.sName		                    --昵称
            item.nStatus=tInfo.nStatus		                --状态 0:正常 1:离桌
            item.nPlayCnt=tInfo.nPlayCnt	                --局数
            item.nProfitSum=tInfo.nProfitSum	            --盈亏
            item.sFaceId=tInfo.sFaceId
            table.insert(arrPartInUser,item)
            if n==500 then
                break
            end  
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
        --tBase.Log("GetOverview arrLooker_%s",tJosn.encode(tInfo))
        local item ={}
        item.nUserId =v.nUserId
        item.sName=tInfo.sName		                    --昵称
		item.nStatus=tInfo.nStatus		                --状态 0:正常 1:离桌
        item.sFaceId=tInfo.sFaceId
        table.insert(arrLooker,item)

        if #arrLooker==11 then
            break
        end
    end
    return {arrPartInUser=arrPartInUser,arrLooker=arrLooker}
end

-- 永久牌桌2个小时清理一次
function Overview:ClearDataTwoHour()
    local nNow = os.time()
    local nIntervalTime =7200               --两小时为一局
    -- local isClear =((nNow//nIntervalTime) ~=(self.nTimeStamp//nIntervalTime)) and 1 or 0

    local nNowDiv = math.floor(nNow / nIntervalTime)
    local nStampDiv = math.floor(self.nTimeStamp / nIntervalTime)
    local isClear = (nNowDiv ~= nStampDiv) and 1 or 0
    if isClear == 1 then
        tBase.Log("Overview ClearDataTwoHour 牌桌总览清理(两小时清理一次)")
        self.nTimeStamp = os.time()
        self.tOverviewOfPartIn = {}
    end
end

return Overview