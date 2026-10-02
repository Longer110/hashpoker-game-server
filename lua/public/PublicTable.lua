
local tBase  = require("base")         -- 基础功能接口
local mlogger = require("logger")      -- 日志对象 
local api       = require("publicApi")    -- 共用功能接口
local tSrvInfo = require("ServerInfo")
local cjson     = require("cjson")          -- json 
local tPubUser = require("PublicUserInfo")  -- 用户信息 
local RecordDbr =require("RecordDbr")       -- 写记录


local PublicTableManager = {}
local PublicTable = {}
local tTimerAux = {}

PublicTableManager.arrTable = {}   

local nTimerIdStart =1000
local nTimerIdEnd =60000

local MaxUserCnt = 10000   --  牌桌最大人数


local TableState ={
    nInit =0,           --未开始
    nBet=1,             --下注阶段
    nSettle=2,          --结算阶段(开牌阶段)
    nFree=3,            --空闲阶段
}


------------------- 牌桌管理 start ---------------------------------
--------------------------------------------------------------------


--初始化桌子管理
function PublicTableManager.Init()
    local nInitCnt = 10000
    for i = 1, nInitCnt do
        PublicTableManager.arrTable[i] = 0
    end
end

--找空闲的位置
function PublicTableManager.FindFreePlace()
    local arrPlace = PublicTableManager.arrTable
    for i = 1, #arrPlace do
        if type(arrPlace[i]) == "number" and arrPlace[i] == 0 then
            return i
        end
    end
    return -1
end

--创建牌桌
function PublicTableManager.CreateTables()
    local nTableId = PublicTableManager.FindFreePlace()
    if nTableId ~= -1 then
        local tNewTable = PublicTable:New()
        tNewTable.nTableId    = nTableId 
        tNewTable.sOpentable_Time   = os.date("%Y-%m-%d %H:%M:%S")
        PublicTableManager.arrTable[nTableId] = tNewTable

        local fCloseFunc = function()  
            PublicTableManager.RemoveTable(nTableId)    

            tNewTable.Timer:KillAllTimer()  
        end     
        tNewTable.Close_Table = fCloseFunc
        tNewTable:Print(" CreateTables  success  nTableId_%d  sOpentable_Time_%s  ",nTableId,tNewTable.sOpentable_Time)
        return tNewTable
    else
        local arrTableId = PublicTableManager.Get_Live_TableId(nLiveUserID)
        if #arrTableId > 0 then 
           return PublicTableManager.arrTable[arrTableId[1]] 
        end 
        assert(nTableId == -1," no usable nTableId_"..nTableId)
        return nil 
    end
end

--获取某个table
function PublicTableManager.GetTable(nIdx)
    if PublicTableManager.arrTable[nIdx] ~= 0 then
        return PublicTableManager.arrTable[nIdx]
    end
    return nil
end

-- 删除牌桌
function PublicTableManager.RemoveTable(nTableId)
    local tTable = PublicTableManager.GetTable(nTableId) 
    if tTable then 
        tTable:Print("  Remove  Table   success   ")
        PublicTableManager.arrTable[nTableId] = 0      --从新设置标志位为0,让桌子空闲
        return true 
    else
        tBase.Log(" nTableId_%d   RemoveTable   GetTable is nil   ",nTableId)    
        return  false 
    end 
end


------------------- 牌桌管理 end -----------------------------------
--------------------------------------------------------------------


------------------- 牌桌 start -------------------------------------
--------------------------------------------------------------------


-- 牌桌开始
function PublicTable:Table_Start()
    self:Print("Table_Start  牌局 3s 后开始   ")
    self:ToGoInFreeStage(3)
end

-- 初始化牌桌数据
function PublicTable:New()
    local t = {}
    setmetatable(t, self)
    self.__index = self
    local arrTimerId ={}
    for i=1,20 do
        table.insert(arrTimerId,tTimerAux.GetATimerId())
    end

    t.nTableId = -1   
    
    t.Timer = tTimerAux:New(arrTimerId)

    t.nCount = 0   -- 轮数

    t.DurationTime_BetStage = 15        --下注阶段时间  15  
    t.DurationTime_SettleStage = 10     --结算阶段时间(结算5s)  10
    t.DurationTime_FreeStage = 3        --空闲阶段时间

    t.nStage = TableState.nInit         --当前游戏阶段
    t.nStageEndTime=0                   --当前阶段预计结束时间 os.time()

    t.nMaxUserCnt = MaxUserCnt   --本桌子人数上限

    t.Close_Table = nil          --  调用 此函数以便关闭桌子

    -- 游戏配置
    t.nGameId = -1
    t.nRoomId = -1

    --当前庄家信息
    t.tBanker={
        nUserId=0,              --玩家id
        sFaceId='1' ,           --url
        sName= "quanyumj" ,     --昵称
        nGold= 0,               --  math.random(1000000,  99999999),      --身上金币
        nSex=0 ,                --性别 0:男 1:女
        isAndroid = false ,      -- 是否机器人
        sPublicTableKey = "",
    }

    t.arrUsers={}                                                                   --各玩家信息
    t.sPaiJuId = nil                                                                --牌局id，一局开始时生成一次


    return t
end

------------------- 牌桌流程  start ---------------------------------
---------------------------------------------------------------------

--游戏流程: 下注阶段--> 结算阶段-->空闲阶段-->下注阶段

--nSeconds秒后进入空闲阶段
function PublicTable:ToGoInFreeStage(nSeconds)
    self:Print("ToGoInFreeStage   开始 %d轮游戏    %d 秒后进入空闲阶段     ",self.nCount,nSeconds)
    self.Timer:DelayCall(nSeconds*1000,self.GoInFreeStage,self)
    self.nCount = self.nCount + 1   
end

--进入空闲阶段
function PublicTable:GoInFreeStage()
    self:Print("GoInFreeStage --------> 进入下注阶段  ")
    self:_ResetData()
    
    self:ToGoInBetStage(self.DurationTime_FreeStage)        -- 一段时间后进入下注阶段
end

--nSeconds秒后进入下注阶段
function PublicTable:ToGoInBetStage(nSeconds)
    self:Print("ToGoInBetStage  %d 秒后进入下注阶段  ",nSeconds)
    self.Timer:DelayCall(nSeconds*1000,self.GoInBetStage,self)
end

--进入下注阶段
function PublicTable:GoInBetStage()
    self:Print("GoInBetStage  进入下注阶段 ")
    self.nStage =TableState.nBet            
    self.nStageEndTime=os.time()+self.DurationTime_BetStage

    self:ToGoInSettleStage(self.DurationTime_BetStage) 
end

--nSeconds秒后进入结算阶段
function PublicTable:ToGoInSettleStage(nSeconds)
    self:Print("ToGoInSettleStage %d 秒后进入结算阶段 ",nSeconds)
    self.Timer:DelayCall(nSeconds*1000,self.GoInSettleStage,self)
end

--进入结算阶段
function PublicTable:GoInSettleStage()
    self:Print("GoInSettleStage  ---------> 结算阶段 ")
    self.nStage =TableState.nSettle         
    self.nStageEndTime=os.time()+self.DurationTime_SettleStage

    self:ToGoInFreeStage(self.DurationTime_SettleStage)          --一段时间后进入空闲阶段
end

-- 重置数据
function PublicTable:_ResetData()

    --重置数据
end


------------------- 牌桌流程  end -----------------------------------
---------------------------------------------------------------------

-- 获取牌桌 空闲座位
function PublicTable:_FindAFreePos()
    for pos=1,self.nMaxUserCnt do
        if self.arrUsers[pos]==nil then
            return pos
        end
    end
    return nil
end

--下注请求
function PublicTable:_OnBetReq(sReturnKey,tData)
end

-- 获取庄家信息
function PublicTable:_GetProtoUser_Banker()
    local tProtoUser ={}
    tProtoUser.nUserId=self.tBanker.nUserId
    tProtoUser.sFaceId=self.tBanker.sFaceId
    tProtoUser.sName=self.tBanker.sName
    tProtoUser.nGold=self.tBanker.nGold
    tProtoUser.nSex =self.tBanker.nSex
    self:Print(" 获取庄家信息 ----->   tBanker_%s   ", cjson.encode(self.tBanker))
    return tProtoUser
end

--获取场景
function PublicTable:GetScence()

    return tScence
end

-- 牌局记录
function PublicUserInfo:_WritePaiJuRecord()

end



------------------- 用户 管理  start ---------------------------------
--------------------------------------------------------------------

-- 获取玩家信息
function PublicTable:_GetUserInfo(nSitId)
    local tUser =self.arrUsers[nSitId]
    assert(tUser~=nil)
    return tUser
end

-- 是否为机器人
function PublicTable:_IsAndroid(nSitId)
    local tUser =self.arrUsers[nSitId]
    return tUser.isAndroid
end

-- 获取玩家 UserID 
function PublicTable:_GetUserIdBySit(nSitId)
    local tUserInfo =self.arrUsers[nSitId]
    if not tUserInfo then
        return
    end
    return tUserInfo.nUserId
end

--use  添加玩家信息
function PublicTable:AddUserTable(tUserInfo)
    local nFreePos =self:_FindAFreePos()
    if nFreePos==nil then
        return false
    end
    local tUser ={}
    tUser.nUserId=tUserInfo.nUserId
    tUser.nSitId=nFreePos
    tUser.sFaceId=tUserInfo.sFaceId or '1'
    tUser.sName=tUserInfo.sName or "No Name"
    tUser.nGold=tUserInfo.nGold or 0             
    tUser.nChannel = tUserInfo.nChannel or 1 
    tUser.nSex =tUserInfo.nSex or 0 --0:男 1:女
    tUser.isAndroid =tUserInfo.isAndroid
    tUser.bIsLeaveTable=false               --是否已经离开了本桌子
    tUser.nKickType =nil                    --是否玩完一局后被踢出
    tUser.nShopId=tUserInfo.nShopId or -1

    tUser.isLockForRecharge=false           --是否锁定中(充值中)
    tUser.isBeting = false                  --是否下注
    tUser.IsControl = false                  --是否控牌    
    self.arrUsers[nFreePos]=tUser
    return true,nFreePos
end

------------------- 消息处理 start ---------------------------------
--------------------------------------------------------------------

--广播
function PublicTable:Broadcast(sProto,tSendData)
end

-- 消息处理 
function PublicTable:OnMsgHandle(sReturnKey,strReq,tData)
    if strReq =="LogOnReq" then             --登录请求
        self:_OnLogOnReq(sReturnKey,tData)
        return
    end    
    if strReq =="BetReq" then       --下注请求
        self:_OnBetReq(sReturnKey,tData)
        return
    end 

    if strReq =="GMReq" then                --GM 请求
        self:_OnLGMOnReq(sReturnKey,tData)
        return
    end 
end


--发送数据接口
function PublicTable:SendToUser(nSitId,strMsgName,tMsgData)

end

------------------- 消息处理 start ---------------------------------
--------------------------------------------------------------------

-- 日志输出
function PublicTable:Print(str,...)
    mlogger:info(string.format(" nTableId_"..self.nTableId.."=>"..str,...))
end

function PublicTable:PrintError(str,...)
    mlogger:error(string.format(" nTableId_"..self.nTableId.."=>"..str,...))
end

------------------- 定时器 start ---------------------------------
------------------------------------------------------------------

function tTimerAux.GetATimerId()
    nTimerIdStart =nTimerIdStart+1
    return nTimerIdStart
end

function tTimerAux:New(arrTimerId)
    local t = {}
    setmetatable(t, self)
    self.__index = self
    t.arrTimerId ={}
    local arrTimerId =arrTimerId or {}
    for _,nTimerId in ipairs(arrTimerId) do
        table.insert(t.arrTimerId,nTimerId)
    end
    t.nFunctionId =0
    t.tFunctionIdToTimerId={}
    return t
end

function tTimerAux:DelayCall(nMSeconds,fFunc,...)
    local nFunctionId =self.nFunctionId
    self.nFunctionId =self.nFunctionId +1
    local arrparameter =table.pack(...)
    local temF =function()
        fFunc(table.unpack(arrparameter))           
        self:KillTimer(nFunctionId)     
    end
    local nTimerId =table.remove(self.arrTimerId)
    assert(nTimerId ~=nil,"DelayCall size_",#self.arrTimerId)
    self.tFunctionIdToTimerId[nFunctionId] =nTimerId
    tBase.SetTimer(nTimerId, nMSeconds, 1, temF)
    return nFunctionId
end

function tTimerAux:KillTimer(nFunctionId)
    local nTimerId =self.tFunctionIdToTimerId[nFunctionId]
    if nTimerId~=nil then
        tBase.KillTimer(nTimerId)
        table.insert(self.arrTimerId,nTimerId)
        self.tFunctionIdToTimerId[nFunctionId]=nil
    end
end

function tTimerAux:KillAllTimer()
    for nFunctionId,_ in pairs(self.tFunctionIdToTimerId) do
        self:KillTimer(nFunctionId)
    end
end

------------------- 定时器 end     -------------------------------
------------------------------------------------------------------

 
PublicTable.PublicTableManager = PublicTableManager



return PublicTable
