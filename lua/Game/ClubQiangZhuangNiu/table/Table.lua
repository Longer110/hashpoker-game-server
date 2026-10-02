--[[
	每张牌桌，负责牌桌逻辑开发每张牌桌，负责牌桌逻辑开发
]]
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase 	  = require("base")         -- 基础功能接口
local tSrvPub     = require("SrvPublic")
local mlogger = require("logger")
local tUserMgr    = require("UserManager")
local tCfg = require("GConfig")
local tPublicMath = require("PublicMath")
local tGNiuNiuMath = require("GNiuNiuMath")
local tJson = require("cjson")
local tPubUserApi   = require("PublicUserInfo")    --玩家数据同步
local tGameCfgRedis = require("GameCfgRedis")
local tGm = require("GmPai") -- GM命令
local  tApi = require("publicApi")
local tRecordDbr = require("RecordDbr")
local tConfig =require("GameConfig")
local MsgPush =require("MsgPush")
local RedisCahche =require("RedisCahche")
local tTimerAux =require("TimerAux")
local tPublicClub =require("PublicClub")
local tOverview =require("Overview")
local tPublicRedis =require("PublicRedis")
local Statistic =require("Statistic")
local tname = require("typename") -- 类弄定义接口
local json    = require("json") 
local tTaxGather =require("TaxGather")
local tPubUser = require("PublicUserInfo") -- 用户信息
local tStack =require("Stack")
local bit = require("bit")
RoomType = {
	TiYanFang = 0,
}

TiYanFuGold = 10000 --体验币
NotActionNumber = 2
local Table = {
	EnumProtocol = {
		UserEnter = 1, --玩家进入
		UserLeave = 2, --玩家离开牌桌
		UserOffLine = 3, -- 玩家断线
		UserOnLine = 4, -- 玩家重连上

		UserXiaZhu = 5, -- 玩家下注
		UserTanPaiReady = 6, -- 摊牌准备
		UserTanPai = 7, -- 玩家摊牌
		UserSitDown = 8,    -- 玩家坐下或者站起
		UserSitUp = 9,    -- 玩家坐下或者站起
		WaitStartGame = 10, -- 等待游戏开始广播
		DingZhuang =11, -- 定庄广播
		FaPai = 12,      -- 发牌广播
		JieSuan = 13,   -- 结算广播
		ResetGame = 14, -- 重置牌桌广播
		UserExit = 15, --玩家退出牌桌
		QiangZhuang = 16, -- 抢庄
		GoldChange = 17, -- 金币改变
		UserStatusChange = 18, --用户状态改变
		XiaZhuPush = 19, -- 下注推送
		PeiZhiDiuShi = 20, -- 配置丢失
		CloseServer = 21, -- 关服维护
		Retain =22, --留座离桌
		ChatNotify =23, --聊天通知
	},
}

function Table:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	--Gm命令
	t.tGm = tGm:New()
	--牌桌用户
	t.tUserIDArr = {} -- 加进来的牌桌用户

	--创建牌桌成功自动分配tableId
	t.nTableId = 0
	t.nPaiJuKey = "0"
	--桌子是否可用
	t.bEnable	= true

	t.tXiaZhuCfg = {1, 2, 3, 5, 10}
	t.tQiangZhuangCfg = {0, 1}
	--最大玩家数
	t.nMaxUser = 9
	-- 旁观者最大玩家数
	t.nMaxLookUser = 10000

	t.arrLooker = {} -- 旁观者
	--桌子生成时间
	t.nTableCreateTime = os.time()
	--桌子生命周期(不是所有的桌子都有生命周期)
	t.nCreateTime = 0 --秒
	t.tAction = {} -- 增加action数据
	--牌桌相关
	t.nStep = tSrvPub.enumStep.nNull --当前游戏阶段
	t.nRound = 0  --当前局数
	t.nCurOperSitId = 1 --当前操作位置号
	t.nZhuangUserID = 0 -- 当前牌桌庄家ID
	t.nZhuangSitId = 0 --当前庄家座位号
	t.arrSit = {} -- 桌子座位号
	t.tXiaZhuArr = {} -- 牌桌下注信息
	t.tQiangZhuang = {} -- 抢庄信息 
	t.tUserHandPaiArr = {} -- 玩家手牌信息
	t.tTanPaiReady = {}
	t.tTanPaiArr = {} -- 牌桌摊牌信息
	t.arrPai = {}  -- 牌桌的牌
	t.tZhuang =  {} -- 庄家信息
	t.ZhouShui = {} -- 抽水信息
	t.tJieSuan = {} -- 结算数据
	t.tTotalJieSuan = {} -- 总结算
	t.tPlayFan = {} -- 玩法类型
	t.tHuFan = {} --玩法相对的倍数
	t.tUserAction = {} --玩家动作
	t.tMinGold = 5000 --最小金币(坐下或者打赏或者发表情弹幕时最低金币)
	t.bPreOpenTable = false -- 预开桌标志
	t.nRandStopStep = -1 -- 牌桌暂停
	t.bControl = false -- 控牌标志（这个牌桌是否控牌操作）
	t.tCtrlUserData = {}
	-- 初始化牌子座位号
	for i = 1, t.nMaxUser do
		table.insert(t.arrSit,0)
	end
	--牌局相关
	t.nPaiJuIdx = 0 --牌局的id
	t.boPlay = false --牌桌是否开局过
	t.nReaddy = 0 --已准备好人数
	--有时效性的桌子数据，用于大厅服共用数据redis管理
	t.tCreateTableInfo = nil
	--牌桌时间属性
	t.tTimeCfg = tSrvPub.NiuNiuRoomTime
	t.nGameType =0 -- 游戏类型
	t.nLevel =0	   -- 游戏场次
	t.nGroup = 0   -- 牌桌群主
	t.AndroidChat = {}
	t.nTax = 0.05
	t.nBaseScore = 1	-- 牌桌创建的底分
	t.tUserPaiJuData = {  -- 上局牌局信息
		ZhuangJia = {
			nUserID = 0, -- 谁是庄家
			nSitID  = 0, -- 座位号
		},
		MaxPai = {  -- 上把最大的牌
			nUserID = nil, --
			nNiuWhat= nil, --什么牌
		},
	} 
	t.nShangZhuangRound = 0 -- 当前庄家连庄次数
	t.nKickUser = {} -- 踢人操作
	t.nTableBlacklist = {} -- 被后台强制踢出后加入黑名单，不能再进入
	t.nForcedStandList = {} -- 被强制站起名单
	t.nStandupUser = {} -- 站起操作(本局游戏结束后站起)
	t.nNeedControlUser = 0  --需要控牌用户
	t.nItemId = 1 --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	t.nOpentime = -1 --开桌时间
	t.nGoldType = 1 -- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)
	t.nClubId =nil                --俱乐部id (俱乐部房配置,否时为nil)
	t.sTableId = "" --牌桌ID
	t.nPlayerCntAtLeast = 2 --至少满2人开始
	t.TimerForRetain =tTimerAux:New()	--玩家留座计时
	t.TimerForElapWarn=tTimerAux:New()	--时间剩余警告
	t.arrChat ={}    	--表情价格表：  nChatId： 1-49
	t.nCloseTableWhenOver = 0 --一局结束后关闭桌子的原因
	t.nUserCntOfReal = 0	--本桌子当前真人玩家数量(包括旁观)
	t.nUserCnt =0						--本桌子当前玩家数量(包括旁观)
	t.isNeedAndroid = false --牌桌是否需要加载机器人
	t.tTableOverview =tOverview:New() --牌桌总览
	t.nKeepTime =3600*6      --房间时长(秒) (俱乐部房配置,否时为nil)
	t.nFirstPaiJuTime = 0 							-- 首局开始时间
	t.nClubIdOfCorrect=nil	--经过校正后的ClubId (大厅统一用0表示)
	t.sTableName=""
	t.tStatistic =Statistic:New()	--数据统计
	t.TimerForAndroid =tTimerAux:New() --机器人用户操作
	t.startTime = nil --概念与nNewBeginStamp相同
	t.sClubName = "unknown"
	t.nContinuedNum = 0  -- 补开桌子数量
	t.tTimeKeeping={nElapsed=0,nNewBeginStamp=nil,nPauseStamp=nil}
	t.tWarnHistory={}								--桌子剩余时间告警记录
	t.tGather =tTaxGather:New()						--按桌抽水时的一个辅助
	t.CurConfigAndroid = 0							--当前机器人后台配置数量
	t.ifAdjustedAndroid = 0 						--后台是否调整过机器人
	t.adjustAddCnt = 0								--后台增加的机器人
	t.nAndroidCnt =0								--当前机器人数量
	t.arrTaxForUpdate={}							--缓存需要延迟更新的抽水记录(按牌桌抽水)
	t.tOverviewSnapshoot={}							--总览快照
	t.nOverViewRtLen = 20							--总览一次拿的条数
	return t
end

--桌子暂停计时
function Table:StopTiming()
	if self.tTimeKeeping.nNewBeginStamp==nil then
		return
	end
	local nNow =os.time()
	self.tTimeKeeping.nElapsed =self.tTimeKeeping.nElapsed +(nNow -self.tTimeKeeping.nNewBeginStamp)
	self.tTimeKeeping.nNewBeginStamp =nil
	self.tTimeKeeping.nPauseStamp =nNow
	tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{nTableStatus=1})
end

--桌子开始或重新开始计时
function Table:BeginTiming()
	if self.tTimeKeeping.nNewBeginStamp~=nil then
		return
	end
	self:Print("BeginTiming")
	self.tTimeKeeping.nNewBeginStamp =os.time()
	self.tTimeKeeping.nPauseStamp =nil
	tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{nTableStatus=0})
	return true
end

function Table:BeginTiming_v2()
	if self.startTime ~= nil then
		return
	end
	self.startTime = os.time()
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser and tUser.isAndroid == false then 
			Protocol.StateChangeNotify(tUser.sClientID,{nElapsedStatus = self:_ifStarted()})
		end
	end	self:_ElapWarnReset(false) ----启动剩余时间告警定时器
	self:Print("self.nKeepTime_%d self.startTime_%d",self.nKeepTime,self.startTime)
end

--获得桌子剩余时间,-1:表示时间无限制,>=0表示剩余时间
function Table:_GetRemainTime()
	if not self.nKeepTime or self.nKeepTime<0 then
		return -1		
	end
	local nElapsedSum =self.tTimeKeeping.nElapsed
	if self.tTimeKeeping.nNewBeginStamp then
		nElapsedSum =nElapsedSum +(os.time() -self.tTimeKeeping.nNewBeginStamp)
	end
	return math.max((self.nKeepTime -nElapsedSum),0)
end

--获得桌子剩余时间,-1:表示时间无限制,>=0表示剩余时间
function Table:_GetRemainTime_v2()
	if not self.nKeepTime or self.nKeepTime<0 then
		return -1
	end
	local nElapsedSum = nil
	if self.startTime then
		nElapsedSum = os.time() -self.startTime
	end
	self:Print("self.nKeepTime_%d self.startTime_%d nElapsedSum_%d",self.nKeepTime,self.startTime,nElapsedSum)
	return math.max((self.nKeepTime - nElapsedSum),0)
end

--桌子暂停状态 0正常 1暂停
function Table:_ElapsedStatus()
	if self.tTimeKeeping.nNewBeginStamp==nil then
		return 1
	end
	return 0
end

--桌子是否开始状态 0非开始 1开始
function Table:_ifStarted()
	if self.startTime==nil or self.tTimeKeeping.nNewBeginStamp==nil then
		return 0
	end
	return 1
end


function Table:TestMemory()
	self:Print("#tUserIDArr:%d",#self.tUserIDArr)
	self:Print("#arrChat:%d",#self.arrChat)
	self:Print("#nStandupUser:%d",#self.nStandupUser)
	self:Print("#nKickUser:%d",#self.nKickUser)
	self:Print("#arrLooker:%d",#self.arrLooker)
	self:Print("#tAction:%d",#self.tAction)
	self:Print("#arrSit:%d",#self.arrSit)
	self:Print("#tXiaZhuArr:%d",#self.tXiaZhuArr)
	self:Print("#tQiangZhuang:%d",#self.tQiangZhuang)
	self:Print("#tUserHandPaiArr:%d",#self.tUserHandPaiArr)
	self:Print("#tTanPaiReady:%d",#self.tTanPaiReady)
	self:Print("#arrPai:%d",#self.arrPai)
	self:Print("#tZhuang:%d",#self.tZhuang)
	self:Print("#ZhouShui:%d",#self.ZhouShui)
	self:Print("#tJieSuan:%d",#self.tJieSuan)
	self:Print("#tTotalJieSuan:%d",#self.tTotalJieSuan)

	self:Print("#tPlayFan:%d",#self.tPlayFan)
	self:Print("#tHuFan:%d",#self.tHuFan)
	self:Print("#tUserAction:%d",#self.tUserAction)
	self:Print("#tCtrlUserData:%d",#self.tCtrlUserData)
	self:Print("#AndroidChat:%d",#self.AndroidChat)
	
end

function Table:Del()
	tBase.KillTimer(SrvPub.Timer.TableStep + self.nTableId)

    tBase.KillTimer(SrvPub.Timer.AndroidAi + self.nTableId) --牌桌ai
	tBase.KillTimer(SrvPub.Timer.AndroidEnterTable + self.nTableId) -- 牌桌机器人进入
	MgrAndroid.tTimeID[SrvPub.Timer.AndroidEnterTable + self.nTableId] = nil
	self:ClearData()
	self = nil
end

function Table:Init(tData)
	--tBase.Log("桌子初始化完成")
end
--生成牌局的key
function Table:MakePaiJuKey(nPaiJuKey)
	self:Print("_MakePaiJuKey	 nPaiJukey : %s",nPaiJuKey)
	self.nPaiJuKey = nPaiJuKey
end

-- 获取当前用户金币
function Table:Get_User_Gold(nUserID)
	local nGold = 0
	local  tUser =  tUserMgr.GetUserInfo(nUserID)
	if not tUser or tUser.isAndroid then
		nGold = tUserMgr.GetUserInfo(nUserID).nGold or 0
	else
		nGold = tUserMgr.GetUserInfo(nUserID).nLockGoldInTable or 0
	end
	return nGold
end

function Table:_ElapWarnReset(isStop)
	local nRT =self:_GetRemainTime_v2()
	if nRT ==-1 then
		return
	end
	self.TimerForElapWarn:KillAllTimer()
	if isStop then
		return
	end
	local arrW ={10*60,5*60,2*60}
	for _,nW in ipairs(arrW) do
		local nDiff =nRT -nW
		if nDiff>0 then
			self.TimerForElapWarn:DelayCall(nDiff*1000,self._ElapWarnBroadCast,self,nW)
		end
	end
end

function Table:_ElapWarnBroadCast(nRemainT)
	if self.tWarnHistory[nRemainT] then
		return
	end
	local nRT =self:_GetRemainTime_v2()
	if math.abs(nRT-nRemainT)>30  then
		self:Print("_ElapWarnBroadCast Lost,nRemainT:%d Real:%d",nRemainT,nRT)
		return
	end
	self.tWarnHistory[nRemainT]=true

	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser and tUser.isAndroid == false then 
			Protocol.RemainTimeWarning(tUser.sClientID,{nRemainTime = nRemainT})
		end
	end

	self:Print("_ElapWarnBroadCast %d Succee",nRemainT)
end

--浮点数判断
-- 是否小于
local function LessThan(a,b)
	return (a<b and math.abs(a-b)>1e-6)
 end
-- 是否大于
 local function GreaterThan(a,b)
	return (a>b and math.abs(a-b)>1e-6)
end
-- 是否小于等于
local function LessOrEqual(a,b)
	return (not GreaterThan(a,b))
end
-- 是否大于等于
local function GreaterOrEqual(a,b)
	return (not LessThan(a,b))
end
-- 是否等于
local function Equal(a,b)
	return (math.abs(a-b) <1e-6)
end

--是否使用积分结算
function Table:IsUseCredit()
	if self.nGoldType ==3 then		--俱乐部房指定使用积分结算
		return true
	end
	return false
end

function Table:Get_User_UnLockGold(tUser)
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid then
			return self.tMinGold
		end
		return tPubUserApi.Get_User_UnLockGold(tUser.nUserID,self.nItemId)
	end
	return (tUser.nGold)
end

function Table:Gold_Lock(tUser,nGoldToLock)
	local nUserId =tUser.nUserID
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUserApi.Gold_Lock(nUserId,nGoldToLock,self.nItemId) then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable +nGoldToLock
			return true
		end
		return false
	end
	local nNowUnLockGold =(tUser.nGold -tUser.nLockGoldInTable)
	if (not (nNowUnLockGold <nGoldToLock and math.abs(nNowUnLockGold-nGoldToLock)>1e-6)) then
		tUser.nLockGoldInTable =tUser.nLockGoldInTable +nGoldToLock
		return true
	end
	return false
end

function Table:Gold_ChangeAndReLock(tUser,nChange,nSourceType,nRoomId)
	local nUserId =tUser.nUserID
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUserApi.Gold_ChangeAndReLock(nUserId,tUser.nLockGoldInTable,nChange,nSourceType,nRoomId,self.nItemId) then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable +nChange
			return true
		end
		return false
	end
	tUser.nGold =tUser.nGold +nChange
	tUser.nLockGoldInTable =tUser.nLockGoldInTable +nChange
	return true
end

function Table:Gold_UnLockAll(tUser)
	if Equal(tUser.nLockGoldInTable,0) then 
		return true
	end
	local nUserId =tUser.nUserID
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUserApi.Gold_UnLock(nUserId,tUser.nLockGoldInTable,self.nItemId) then
			tUser.nLockGoldInTable =0
			return true
		end
		return false
	end
	tUser.nLockGoldInTable =0
	return true
end
function Table:Gold_UnLock(tUser,nToUnLock)
	nToUnLock =math.max(nToUnLock,0)
	if GreaterThan(nToUnLock,tUser.nLockGoldInTable) then
		return false
	end
	local nUserId =tUser.nUserID
	if not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUserApi.Gold_UnLock(nUserId,nToUnLock,self.nItemId) then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable -nToUnLock
			return true
		end
		return false
	end
	tUser.nLockGoldInTable =tUser.nLockGoldInTable -nToUnLock
	return true
end

-- 锁 玩家金币
function Table:LockUserGold()
	local arrLockGoldFail = {} --锁金币失败的玩家
	local ArrReadyUser =  self:GetUserReadyArr()
	local nNeedGold = self:_GetTableLowerCoin()
	for _, nUserId in pairs(ArrReadyUser) do
		local tUser = tUserMgr.GetUserInfo(nUserId)
		if (tUser ~= nil and tUser.isAndroid == false) then
		    --锁住玩家所有金币
		    local isSuccee = self:Gold_Lock(tUser,nNeedGold)
		    if not isSuccee then
		        tBase.Log("_LockUserGold  金币加锁失败 UserID:%d  nGold_%f ",tUser.nUserID,tUser.nGold) 
				table.insert(arrLockGoldFail,{nUserId=nUserId})
		    else
		       -- tUser.nGold = nGoldLock
		        tBase.Log("_LockUserGold 金币加锁成功 UserID:%d nGoldLock:%f",tUser.nUserID,nNeedGold)
		    end
		end
	end 
	return arrLockGoldFail
end

-- 解锁 玩家金币
function Table:UnLockUserGold()
	local ArrReadyUser =  self:GetUserReadyArr()
	for _, nUserId in pairs(ArrReadyUser) do
		local tUser = tUserMgr.GetUserInfo(nUserId)
		if (tUser ~= nil and tUser.isAndroid == false) then 
			tBase.Log("_UnLockUserGold 游戏结束解锁金币 UserID:%d nGoldLock:%f",tUser.nUserID,tUser.nLockGoldInTable)
            self:Gold_UnLock(tUser,tUser.nLockGoldInTable)--解锁玩家金币 
		end
	end 
end
--------------------------- 控牌逻辑 start ------------------------------------
-- 初始化牌桌控牌状态
function Table:InitControlStatus()
	self:Print("_InitControlStatus")	
	self.nRound = self.nRound + 1
	if self.nRound == 1 and self.nFirstPaiJuTime == 0 then  
		self.nFirstPaiJuTime = os.time() 
	end 
	local tPlayArr = self:GetUserPlayArr()
	for k, nUserID in pairs(tPlayArr) do
		local tUserInfo=tUserMgr.GetUserInfo(nUserID)
		if tUserInfo.isAndroid == false then
			local nControlStatus = tPubUserApi.IsNeedControl(self.nGameType,self.nLevel,nUserID) or -1
			self:Print("_InitControlStatus	游戏: %d 房间：%d 用户：%d 获取控牌状态：%d", self.nGameType,self.nLevel,nUserID, nControlStatus)			
			if nControlStatus ~= nil then
				tUserInfo.nControlStatus = nControlStatus
				--[[ if nUserID == math.floor(21020784) then
					tUserInfo.nControlStatus = 4
				end ]]
			else
				tUserInfo.nControlStatus  = -1
			end
		end
	end
	if self:BeginTiming() then
		local nRt=self:_GetRemainTime()
		self:SetEffectTime(nRt)
	end

	--local Send ={}
	--Send.isStartGame = true 
	--if self.nFirstPaiJuTime > 0 then 
	--	Send.nFirstPaiJuTime= self.nFirstPaiJuTime		
	--end 
	tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{isStartGame=true})  
end

-- 是否控牌玩家
function Table:IsCtrlUser(nUserID)
	if self.tCtrlUserData[nUserID] ~= nil then
		return true
	end
	return false
end

-- 牌桌是否需要控牌(需要控就需要初始化手牌)
function Table:IsNeedControl()
	local nNeedControl = 0
	local nReadyUserID = 0
	local nAndroid = 0
	local  tPlayArr = self:GetUserPlayArr()
	for k, nUserID in pairs(tPlayArr) do
		local  tUserInfo =  tUserMgr.GetUserInfo(nUserID)
		local nControlStatus = tUserInfo.nControlStatus
		if nControlStatus > 1 then
			nNeedControl = nNeedControl + 1
		end
		if tUserInfo.isAndroid == true then
			nAndroid = nAndroid + 1
		end
	end
	if nAndroid <= 0 or  nNeedControl <= 0 then -- 没有控牌玩家和机器人为0是不能控牌
		self:Print("_IsNeedControl   不能控牌")
		return false
	end
	self:Print("_IsNeedControl     控牌")
	return true	
end

-- 判断牌桌能不能控（定庄后能否满足控制）
function Table:IsCanControlTable()
	self:Print("_IsCanControlTable ")
	local nAnd, nUser = self:GetAndroidCountAndUserCount()
	if self:IsNeedControl() == false then -- 全部真人不控
		return 
	end
	local tZhuagnJiaData = tUserMgr.GetUserInfo(self.nZhuangUserID)
	if tZhuagnJiaData ~= nil and tZhuagnJiaData.isAndroid == false then --真人坐装
		if nAnd >= 2 then -- 机器人多于2人不控
			return 
		end
	end
end

-- 牌桌是否有玩家需要控牌
function Table:UserControlCount()
	local  tPlayArr = self:GetUserPlayArr()
	local nCount = 0
	local arrControlUser = {}
	for k, nUserID in pairs(tPlayArr) do
		local  tUserInfo =  tUserMgr.GetUserInfo(nUserID)
		if tUserInfo.nControlStatus > 1 then
			nCount = nCount + 1
			table.insert(arrControlUser,nUserID)
		end
	end
	if nCount > 0 and  self.nNeedControlUser <= 0 then
		self.nNeedControlUser = arrControlUser[math.random(1,nCount)]
	end
	return nCount
end


--------------------------- 控牌逻辑 end ------------------------------------
--获取牌桌当时应该取多少人
function Table:GetNeedFree()
	local Number = #self.tUserIDArr
	local nMax = self:GetMaxUser()
	local nNeed = 0
	local  nRand = math.random(1, 100)
	local nAnd = self:GetAndroidCount()
	if nAnd ==Number and nAnd == 4 then
		return 0
	end
	if 1 <= nRand and  nRand < 60 then
		nMax = 5
	elseif  60 <= nRand and  nRand < 75 then
		nMax = 3
	elseif  75 <= nRand and  nRand < 100 then
		nMax = 4
	end
	nNeed = nMax - Number 
	if nNeed < 0 then
		nNeed = 0
	end
	return nNeed
end

-- 构造改用户牌桌信息
function Table:MakeTableData(IsInRoom,nUserID)
	self:Print("_MakeTableData")
	local tData = {}
	if (IsInRoom== true or IsInRoom == false) then
		tData.TableNumber = self.nTableId
		tData.TabelStep = self.nStep
		tData.TabelZhuangJiaSit = self.nZhuangSitId
		tData.GameType = self.nGameType
		tData.GameLevel = self.nLevel
		tData.TabelDiFen = self.nBaseScore
		tData.TableSit = self.arrSit
		tData.nElapsedStatus=self:_ifStarted()
		self:Print("_MakeTableData 牌桌位置初始化:%s",tJson.encode(self.arrSit))
		tData.UserDataList = {}
		local tPlayingArr = self:GetUserReadyArr()
		for k ,v in pairs(tPlayingArr) do
			local tUser = tUserMgr.GetUserInfo(v)
			table.insert(tData.UserDataList, tUser )
		end
		local tMyself = tUserMgr.GetUserInfo(nUserID)
		tData.tMyself = tMyself

		 --抢庄配置
		 tData.QiangZhuangCfg = {}
		 tData.QiangZhuangCfg = self.tQiangZhuangCfg
		 
		 -- 抢庄信息
		 tData.QiangZhuangArr = {}
		 tData.QiangZhuangArr = self.tQiangZhuang

		 --下注配置
		 tData.XiaZhuCfg = {}
		 tData.XiaZhuCfg = self.tXiaZhuCfg
		--下注信息
		tData.tXiaZhuArr = {}
		tData.tXiaZhuArr = self.tXiaZhuArr

		tData.tOtherArr  ={}
		tData.tMyXiaZhu = {}
		tData.UserShouPai = {}
		tData.UserShouPai[nUserID]= self.tUserHandPaiArr[nUserID] or {}
	
		--摊牌准备
		tData.TanPaiReady = self.tTanPaiReady
		--摊牌信息
		tData.tTanPaiArr = {}
		tData.tTanPaiArr = self.tTanPaiArr
		tData.arrChat = self.arrChat

		--结算信息
		tData.tUserData = {}
		for k , v in pairs(self.tJieSuan) do		
			local tDataMsg = {}
			tDataMsg.UserID = k
			tDataMsg.TotalWin = self.tTotalJieSuan[k]
			tDataMsg.WinObjectArr = {}
			for k2,v2 in pairs(v) do
				--self:Print("%s",tJson.encode(v2))
				local Obj = {}
				Obj.UserID = v2.nUserID
				Obj.Gold = v2.Sum
				Obj.Index = v2.Index
				table.insert(tDataMsg.WinObjectArr, Obj)
			end
			table.insert(tData.tUserData, tDataMsg)
		end

		tData.tTableConfig = self:_GetTableConfig()
	end

	return tData
end

--加载牌桌规则
function Table:Loader(tData)
	self:Print("_Loader 牌桌加载数据 %s",tJson.encode(tData))
	self.nGameType = tData.nGameType
	self.nGroup = tData.nGroup or tData.nGroupId
	self.tPlayFan = tData.PlayFan
	self.nBaseScore = tData.BaseScore
	self.nTax      =   tData.nTax
	self.nNModeType = tData.nNModeType
	if tData.nNModeType == 3 then
		self.nTax = 0
		self.nTableTax = tData.nTax
	end
	self.nLimitGold = tData.nLimitGold
	self.nClubId = tData.nClubId
    self.bPreOpenTable = tData.bPreOpenTable
    self.nRandStopStep =  tData.nRandStopStep
    self.sTableId = tData.sTableId
	self.nLevel = tData.nRoomId --场次ID
	self.sTableName = tData.sTableName
	self.sClubName = tData.sClubName
	self.nTableType = tData.nTableType
	self.nOpentime = tData.nOpentime
	self.nGoldType = tData.nGoldType
	self.nItemId = tData.nItemId
	self.nPlayerCntAtLeast=tData.tAutostart.nPlayerCnt	--至少几人牌局才能开始(nil或<2表示无效)
	self.isNeedAndroid = tData.isNeedAndroid
	self.nKeepTime = tData.nKeepTime
	self.sRequestkey = tData.sRequestkey
	self.nLiveUserID = tData.nLiveUserID
	self.sLiveID = tData.sLiveID
	self.sPlatformID = tData.sPlatformID
	self.nContinuedNum = math.floor(tData.nContinuedNum or 0)  -- 补开桌子数量	 
	if tData.nClubId  < 1000000 then
		self.nClubIdOfCorrect=0 --经过校正后的ClubId (大厅统一用0表示)
	else
		self.nClubIdOfCorrect=tData.nClubId
	end	
	if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
		self.tXiaZhuCfg = {1, 2, 3, 5, 10}
		--self.tTimeCfg.nXiaZhu = 10 * 1000
		--self.tTimeCfg.nShouPai = 2 * 1000
	end
	self:SetTableUserCount(tData.nCapacity)
	self:_LoadConfig()
	self:SetCardTime(tData.HuType)
	--self:SetEffectTime(tData.nKeepTime) --设置牌桌时效
	self:Print("_Loader nContinuedNum_%d  牌型PlayFan_%s  牌型倍数 HuFan_%s "
	,self.nContinuedNum,tJson.encode(self.tPlayFan),tJson.encode(self.tHuFan))		
end

-- 加载Redis 配置
function Table:_LoadConfig() 
	local tCfg = RedisCahche.GetClubChangeConfig(self.nGroup)
	if not tCfg then 
		self:Print("_LoadConfig  nGroupId_%d  tCfg is nil ",self.nGroup)
		return 
	end  
	-- 表情  
	if not tCfg.arrChatChangeCfg then  
		-- self.arrChat={{nChatId=1,nCost=10},{nChatId=2,nCost=10},{nChatId=3,nCost=10},{nChatId=4,nCost=10},{nChatId=5,nCost=10},{nChatId=6,nCost=10}}		
	else
		local arrChatChangeCfg ={}
		for _, v in pairs(tCfg.arrChatChangeCfg) do
			if v and tonumber(v.nChatId) and tonumber(v.nChatId) < 50 then   -- 弹幕配置
				table.insert(arrChatChangeCfg ,v)
			end 
		end
		self.arrChat = arrChatChangeCfg
	end  	  
	self:Print("_LoadConfig  nGroupId_%d  arrChat_%s ",self.nGroup,tJson.encode(self.arrChat))
end

--牌桌基本信息
function Table:GetTableInfoForClub()
	local tTableInfo ={}
	tTableInfo.nGameId =self.nGameType
	tTableInfo.sTableName =self.sTableName
	tTableInfo.nItemId =self.nItemId  			--使用的金币id
	tTableInfo.nOpentime =self.nOpentime		--开桌时间
	tTableInfo.nCapacity =self.nMaxUser
	tTableInfo.nGoldType =self.nGoldType
	tTableInfo.nBaseScore = self.nBaseScore
	tTableInfo.HuFan = self.tHuFan
	tTableInfo.nLiveUserID = self.nLiveUserID
	tTableInfo.nKeepTime = self.nKeepTime
	tTableInfo.sTableId = self.sTableId
	tTableInfo.nClubId = self.nClubId
	tTableInfo.nTableStatus =self:_ElapsedStatus() 				 --0正常 1暂停

	self:Print("_GetTableInfoForClub tTableInfo :%s",tJson.encode(tTableInfo))
	return tTableInfo
end


--设置桌子时效,如果桌子没有设置时效,则永久有效
function Table:SetEffectTime(nSec)
	if not nSec or  nSec < 0 then
		self:Print("_SetEffectTime   牌桌设置为永久牌桌")
		--永久牌桌
		return
	end
	self.nCreateTime = os.time()
	local tData = {["TableId"]=self.nTableId,["Time"]=nSec}
	tSrvPub.PostInnerEvent(tSrvPub.Event.SETTABLELIEFE, tData)
end

--设置桌子牌型倍数(默认：没牛-牛六(1-7) 1倍,牛七-牛九(8-10) 2倍,牛牛(11) 3 倍,五花牛(12) 4倍,四炸(13) 5倍,五小牛(14) 8倍)
function Table:SetCardTime(HuFan)
	local tHuFan = {}
	local temp = 1
	if #HuFan == 6 then
		for k, v in pairs(HuFan) do
			if k == 1 then
				for i = temp, 7, 1 do
					tHuFan[i] = v
					temp = i
				end
			elseif k == 2 then
				for i = temp+1, 10, 1 do
					tHuFan[i] = v
					temp = i
				end
			else
				temp = temp + 1
				tHuFan[temp] = v
			end
		end
		self.tHuFan = tHuFan
		self:Print("_SetCardTime 使用后台牌型倍数 SetCardTime HuFan_%s",tJson.encode(tHuFan))
	else
		tPublicMath.CopyTable(self.HuFan, tCfg.HuFan[1])
		self:Print("_SetCardTime  使用默认牌型倍数 SetCardTime HuFan_%s",tJson.encode(tHuFan))
	end
end

function Table:Print(str,...)
	tBase.Log(self.sTableId.."=>"..str,...)
end

-- 增加玩家操作数据
function Table:AddAction(nUserID)
	self.tAction[nUserID] = nUserID
end
-- 清除玩家操作数据
function Table:ClearActionData()
	self.tAction = {}
end
--获得牌桌所有用户(玩家+旁观)
function Table:GetAllUser()
	local arr = {}
	for k, v in pairs(self.tUserIDArr) do
		table.insert(arr, v)
	end
	return arr
end

-- 检查用户是否在牌桌上(坐下的用户)
function Table:CheckUserInTable(nUserID)
	for k, v in pairs(self:GetUserPlayArr()) do
		if v == nUserID then
			return true
		end
	end
	return false
end

-- 检查用户是否在牌桌内（旁观或者坐下）
function Table:CheckUserInTable2(nUserID)
	for k, v in pairs(self.tUserIDArr) do
		if v == nUserID then
			return true
		end
	end
	return false
end

--获取配置信息
function Table:GetIndexByVal(nVal)
	local nMin = self.tXiaZhuCfg[1] or 1
	local nMax = self.tXiaZhuCfg[#self.tXiaZhuCfg] or 10
	if nVal >= nMin and nVal <= nMax then
		return nVal
	end
end

-- 获取不是机器人玩家
function Table:GetRealUser()
	local nAnd = 0;
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[k])
		if (tUser ~= nil and tUser.isAndroid == false) then
			nAnd = nAnd + 1;
		end
	end
	return nAnd;
end

-- 
function Table:isAndroidTable()
	local nAnd = 0;
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[k])
		if (tUser ~= nil and tUser.isAndroid == false) then
			nAnd = nAnd + 1;
			break;
		end
	end
	if nAnd > 0 then
		return false
	end
	return  true
end

-- 获取玩家数量
function Table:GetReadyUser()
	local nAnd = 0;
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[k])
		if (tUser ~= nil and tUser.isAndroid == false and tUser:GetStatus() >= tSrvPub.enumState.nPlay) then
			nAnd = nAnd + 1;
		end
	end

	return nAnd;
end

-- 分别获取机器人和真人 人数
function Table:GetAndroidCountAndUserCount()
	local nAnd = 0
	local nUser = 0 
	local arrUserId = {}
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[k])
		if (tUser ~= nil and tUser.isAndroid == false) then
			nUser = nUser + 1 -- 真人
		elseif tUser ~= nil and tUser.isAndroid == true then
			nAnd = nAnd + 1 -- 机器人
		end 
		table.insert(arrUserId,tUser.nUserID)
	end 
	self:Print("_GetAndroidCountAndUserCount  arrUserId: %s ",tJson.encode(arrUserId))
	return nAnd,nUser
end

-- 获取玩家金币列表
function Table:GetUserGoldList()
	local tGoldList = { }
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[k])
		if (tUser ~= nil and tUser.isAndroid == false) then
			table.insert(tGoldList, self:Get_User_Gold(tUser.nUserID) )
		end
	end
	return tGoldList
end

--获取是机器人玩家数组
function Table:GetAndroidUserArr(nGOld)
	local nAnd = {}
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		if (tUser.isAndroid) then
			local nGold = 0
			nGold = tUserMgr.GetUserInfo(v).nGold
			if (nGold >= (nGOld or 4000)) then
				table.insert(nAnd, v)
			end	
		end
	end
	return nAnd
end

-- 获取机器人数组
function Table:GetAndroidArr()
	local nAnd = {}
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		if ( tUser ~= nil and tUser.isAndroid) then
			table.insert(nAnd, v)
		end
	end
	return nAnd
end

--获取是机器人是玩家数组
function Table:GetAndroidPlayArr()
	local nAnd = {}
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		if (tUser.isAndroid and tUser:GetStatus() >= tSrvPub.enumState.nPlay) then
			table.insert(nAnd, v)
		end
	end
	return nAnd
end

--获取是机器人已准备玩家数组
function Table:GetAndroidReadyArr()
	local nAnd = {}
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		if (tUser.isAndroid and tUser:GetStatus() >= tSrvPub.enumState.nSetDown) then
			table.insert(nAnd, v)
		end
	end
	return nAnd
end

-- 获取机器人数
function Table:GetAndroidCount()
	local nAnd = 0
	for k, v in pairs(self.tUserIDArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		if ( tUser ~= nil and tUser.isAndroid) then
			nAnd = nAnd + 1
		end
	end
	return nAnd
end

--桌子已准备玩家数
function Table:GetReadyUserCnt()
	local nReadyCnt = 0
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() >= tSrvPub.enumState.nSetDown and not tUser.isRetain then
			nReadyCnt = nReadyCnt + 1
		end
	end
	return nReadyCnt
end

-- 玩家增加下局离场（或马上踢出）
function Table:AddKickUser(nUserID)
	if self:CheckUserInTable2(nUserID) == false then 
		return  
	end

	--若在游戏中则加入局后踢出列表，否则马上踢出
	if self.nStep >= tSrvPub.enumStep.nStartGame and self.nStep <= tSrvPub.enumStep.nReset then
		self.nKickUser[nUserID] = true
		return
	end

	local tUser = tUserMgr.GetUserInfo(nUserID)
	if tUser == nil then
		self:Print("_AddKickUser   获取玩家失败 _%d",nUserID)
		return
	end
	if tUser.nSitId > 0 then
		self:UserSetSitUp(tUser.nUserID)
	end
	self:ExitTable(nUserID)
	if tUser ~= nil and tUser.isAndroid ~= true and tUser:IsOnLine() == true then
		Protocol.Rep_LogOut(tUser.sClientID,{UserID = tUser.nUserID,Result = 1})
		MsgPush.SendKickOutNotify(tUser.sClientID,"9",0)
	end
	self:UserLout(tUser)
	table.insert(self.nTableBlacklist,tUser.nUserID)
end

-- 检查玩家是否在坐位上
function Table:CheckInSid(nUserID)
	for k ,v in pairs (self.arrSit) do
		if v == nUserID then
			return true
		end
	end
	return false
end

-- 检查玩家的座位号是否合法
function Table:CheckSidGood(nSid)
	for k ,v in pairs (self.arrSit) do
		if k == nSid and v <= 0 then 
			return true
		end
	end
	return false
end

-- 是否补桌限制机器人进入： 游戏开始会自动补桌
function Table:_IsMendOpenTableLimitRobot()
	self:Print("_IsMendOpenTableLimitRobot ")
    local nRobotCnt,nNotRobotCnt =self:GetAndroidCountAndUserCount()
    if self.nContinuedNum and self.nContinuedNum > 0 then 
        -- 无真人情况下，且游戏未开始，机器人数量要低于 自动开始人数 
        if nNotRobotCnt == 0 and self.nPlayerCntAtLeast > 0 and self:_ifStarted()==0 then
            if nRobotCnt > 0 and nRobotCnt >= self.nPlayerCntAtLeast - 1 then
				self:Print("_IsMendOpenTableLimitRobot  限制机器人进入 补桌_%d 总人数_%d 机器人_%d 真人_%d 自动开始_%d "
				,self.nContinuedNum,nRobotCnt+nNotRobotCnt,nRobotCnt,nNotRobotCnt,self.nPlayerCntAtLeast) 
                return true
            end 
        end 
    end  
	return false 
end

function Table:_IncrUserCountBy(nIncrValue,isAndroid,nUserID)
	if not isAndroid then
		tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{sitId=nUserID})
	end
	self.nUserCnt =self.nUserCnt +nIncrValue
	if not isAndroid then
		self.nUserCntOfReal=self.nUserCntOfReal +nIncrValue
	else
		self.nAndroidCnt =self.nAndroidCnt +nIncrValue
	end
	if self.nClubId then
		local tTableInfo ={}
		tTableInfo.nNowCnt =self:GetReadyUserCnt()
		tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,tTableInfo)
	end

	tPubUser.UpdateTableUserCnt(self.sTableId,self.nAndroidCnt,self.nUserCntOfReal)
end

-- 玩家坐下
function Table:UserSetSitDown(nUserID,nSit)
	local tUser =  tUserMgr.GetUserInfo(nUserID)
	if not tUser then
		self:Print("_UserSetSitDown no user %d",nUserID)
		return
	end
	self:Print("_UserSetSitDown nUserID %d",nUserID)
	local tSendData = {}
	tSendData.UserID = nUserID
	tSendData.Action = 1
	tSendData.SitID = nSit
	tSendData.isAndroid = tUser.isAndroid	
	if tUser.nGold < self:_GetTableLowerCoin() then
		tSendData.nRlt = 1
		Protocol.UserAction(tUser.sClientID, tSendData)
		self:Print("_UserSetSitDown nUserID_%d Gold is less %d",nUserID,self:_GetTableLowerCoin())
		if tUser.isAndroid then
			self:UserLeave(nUserID)
		end
		return
	end
	if (self:CheckInSid(nUserID) == true) then
		tSendData.nRlt = 2
		Protocol.UserAction(tUser.sClientID, tSendData)
		self:Print("_UserSetSitDown  玩家已经在坐位上 nUserID_%d ",nUserID)
		return
	end
	--寻找一个空闲位置
	if nSit == 0 then
		local nPosForPlay = self:FindFreePlace()
		self:Print("_UserSetSitDown  nUserID_%d  nPosForPlay: %s",nUserID,tostring(nPosForPlay))
		--如果不能坐下到牌局位置
		if not nPosForPlay then
			tSendData.nRlt = 4
			Protocol.UserAction(tUser.sClientID, tSendData)
			self:Print("_UserSetSitDown Fail, nUserID_%d  Find pos Fail",nUserID)
			if tUser.isAndroid then
				self:UserLeave(nUserID)
			end
			return
		end
	end	
	if (self:CheckSidGood(nSit) == false) then
		tSendData.nRlt = 5
		Protocol.UserAction(tUser.sClientID, tSendData)
		self:Print("_UserSetSitDown  userID:%f 是个疯子,坐错位置 :%f", nUserID,nSit)
		if tUser.isAndroid then
			self:UserLeave(nUserID)
		end
		return
	end
	if not tUser.isAndroid and not self:Gold_Lock(tUser,self:_GetTableLowerCoin()) then
		self:Print("_UserSetSitDown  金币加锁失败 UserID:%d  nGold_%f nGoldLock:%f",tUser.nUserID,tUser.nGold,self:_GetTableLowerCoin())
		tSendData.nRlt = 1
		Protocol.UserAction(tUser.sClientID, tSendData)
		return
	end
	self.arrSit[nSit] = nUserID
	self:Print("_UserSetSitDown  nUserID_%d 牌桌位置设置:%s",nUserID,tJson.encode(self.arrSit))
	local tUser = tUserMgr.GetUserInfo(nUserID)
	tUser.nSitId = nSit
	tUser:SetStatus(tSrvPub.enumState.nSetDown) 
	tPubUserApi.SetUserSeatStatus(nUserID,true)
	local tData = {["TableId"]=tUser.nTableId}
	tSrvPub.PostInnerEvent(tSrvPub.Event.EFFECTSTART, tData)
	self:SendAllUser(nUserID,self.EnumProtocol.UserSitDown)
	self:_IncrUserCountBy(1,tUser.isAndroid,nUserID) 

	local tUserInfo = tUserMgr.GetUserInfo(nUserID)
	if tUserInfo then
		self.tTableOverview:_JoinList_PartIn(nUserID,tUserInfo.sNickName,tUserInfo.sFaceID)
	end
	self.tTableOverview:_SetLookerStatus(nUserID,1) --头像变灰
	
	if tUser.isAndroid then
		--随机检测 如果机器人坐下后10-20秒还没开始 则自动站起退出
		local nRandomSeconds = math.random(180,360)
		self.TimerForAndroid:DelayCall(nRandomSeconds*1000,self.UserSetSitUp,self,nUserID)
		self:Print("_UserSetSitDown  nUserID_%d  %d 秒后没开始,则站起退出",nUserID,nRandomSeconds)
	end
end

--玩家站起
function Table:UserSetSitUp(nUserID)
	local tUser = tUserMgr.GetUserInfo(nUserID)
	if tUser == nil then
		self:Print("_UserSetSitUp  玩家数据为空 nUserID_%d",nUserID)
		return 
	end
	if (self:CheckInSid(nUserID) == false) then
		local tSendData = {}
		tSendData.UserID = nUserID
		tSendData.Action = 1
		tSendData.isAndroid = tUser.isAndroid
		tSendData.nRlt = 8
		self:Print("_UserSetSitUp 玩家不在坐位上 %d",nUserID)
		if self:IsForcedStandList(nUserID) then
			self:RemoveValueFromForcedStandList(nUserID)
			return
		end
		Protocol.UserAction(tUser.sClientID, tSendData)
		return
	end

	--如果机器人 游戏还没开始 则可以站起,如果游戏开始了,就不能中途站起
	if tUser.isAndroid and tUser:GetStatus() == tSrvPub.enumState.nSetDown then
		if self.nStep >= tSrvPub.enumStep.nStartGame and self.nStep <= tSrvPub.enumStep.nReset then
			self:Print("_UserSetSitUp	机器人在游戏中途不给站起 nUserID_%d",nUserID)
			return
		end
	end

	local isForcedStand = self:IsForcedStandList(nUserID)

	--站起后则取消留座离桌
	if tUser.isRetain then
		self:_RetainCancel(nUserID,false)
	end
	if self.nStep == tSrvPub.enumStep.nNull then
		--空闲阶段解锁金币
		self:Gold_UnLockAll(tUser)
	elseif self.nStep >= tSrvPub.enumStep.nStartGame and self.nStep <= tSrvPub.enumStep.nReset and tUser:GetStatus() == tSrvPub.enumState.nSetDown then	
		--坐下没参与游戏解锁金币
		self:Gold_UnLockAll(tUser)
	elseif self.nStep >= tSrvPub.enumStep.nStartGame and self.nStep <= tSrvPub.enumStep.nReset and tUser:GetStatus() == tSrvPub.enumState.nPlay then		
		--玩家中途站起 则本局结束后站起旁观
		self.nStandupUser[nUserID] = true
		local tSendData = {}
		tSendData.UserID = nUserID
		tSendData.Action = 0
		tSendData.SitID = tUser.nSitId
		tSendData.isAndroid = tUser.isAndroid
		tSendData.nRlt = 7
		Protocol.UserAction(tUser.sClientID, tSendData)
		return
	else
		self:Print("_UserSetSitUp 可能没有解锁金币")
	end	
	
	if tUser.nSitId > 0 then
		self.arrSit[tUser.nSitId] = 0
	end
	self:Print("_UserSetSitUp nUserID_%d  牌桌位置设置:%s",nUserID,tJson.encode(self.arrSit))
	tUser.nSitId = 0
	tUser:SetStatus(tSrvPub.enumState.nSetUp)
	tPubUserApi.SetUserSeatStatus(nUserID,false)

	--postt
	self:SendAllUser(nUserID,self.EnumProtocol.UserSitUp)
	self:_IncrUserCountBy(-1,tUser.isAndroid) 

	--离开时按桌抽水
	-- self:TaxByTableRateSettle(tUser)

	if isForcedStand then
		MsgPush.SendKickOutNotify(tUser.sClientID,"8",0)
		self:RemoveValueFromForcedStandList(nUserID)
	end
 
	--机器人 非游戏中途站起 则直接删除缓存数据
	for k, nUserId in ipairs(self.tUserIDArr) do
		if nUserID == nUserId then 
			local tUser = tUserMgr.GetUserInfo(nUserId)
			if tUser and tUser.isAndroid then
				-- self:UserLeave(nUserID)
				self:Print("_UserSetSitUp 机器人想要站起离开 nUserID_%d",nUserID)
			end	
			break 
		end 
	end 
	self.tTableOverview:StandUp(nUserID)
end

--自动坐下
function Table:AutoSetDown(nUserId)
	local tUser =  tUserMgr.GetUserInfo(nUserId)
	local nFreeSitId = self:FindFreePlace()
	if nFreeSitId == 0 then
		self:Print("_AutoSetDown	 桌子没有空位")
		return -1
	end

	--新增玩家的时候确定一次座位号，日后座位号不变
	self:UserSetSitDown(tUser.nUserID, nFreeSitId)
end

--判断桌子是否满人
function Table:IsUserFull()
	self:Print("_IsUserFull playerCnt:%d nMaxCnt:%d",self:GetReadyUserCnt(),self:GetMaxUser())
	if self:GetReadyUserCnt() >= self:GetMaxUser() then
		local s = ""
		for i = 1, #self.arrSit do
			s = s..self.arrSit[i].." "
		end
		tBase.Log("_IsUserFull	桌子满人,当前玩家Id:"..s)
		return true
	end
	return false
end
-- 获取牌桌最大人数
function Table:GetMaxUser()
	return self.nMaxUser
end

--判断旁观是否满人
function Table:IsLookerFull()
	local nLookCnt = 0
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() == tSrvPub.enumState.nSetUp then
			nLookCnt = nLookCnt + 1
		end
	end
	if (nLookCnt >= self.nMaxLookUser) then
		return true
	else
		return false
	end	
end

--获取已经准备的用户数组（包括正在玩的）
function Table:GetReadyUserArr()
	local nReadyCnt = 0
	local tUserArr = {}
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() >= tSrvPub.enumState.nSetDown then
			nReadyCnt = nReadyCnt + 1
			table.insert(tUserArr,tUser.nUserID)
		end
	end
	return tUserArr
end

--桌子设置桌子人数
function Table:SetTableUserCount(nUserCount)
	if nUserCount ~= nil then
		self.nMaxUser = nUserCount
		-- 初始化牌子座位号
		self.arrSit = {}
		for i = 1, self.nMaxUser do	
			table.insert(self.arrSit,0)
		end
		self:Print("_SetTableUserCount	牌桌位置初始化: %s",tJson.encode(self.arrSit))
	end
end

--桌子已经有多少个人
function Table:UserCount()
   local nCount = #self.tUserIDArr
   return nCount
end

--查找本桌没坐人的位置
function Table:FindFreePlace()
	self:Print("_FindFreePlace 	牌桌位置初始化:%s",tJson.encode(self.arrSit))
	for i = 1, #self.arrSit do
		if self.arrSit[i] == 0 then
			return i
		end
	end
	return 0
end

--发送信号
function Table:PostStep()
	local tData = {["nTableId"]=self.nTableId}
	tSrvPub.PostInnerEvent(tSrvPub.Event.STEP, tData)
end

--重置座位（退出牌桌，站起）
function Table:ResetSit(nUserID)
	for i = 1, #self.arrSit do
		if self.arrSit[i] == nUserID then
			self.arrSit[i] = 0 
			self:Print("_ResetSit  nUserID_%d 牌桌位置 arrSit: %s",nUserID,tJson.encode(self.arrSit))
			break
		end
	end
end

--新增玩家(旁观除外)
function Table:AddUser(nUserId)
	for k , v in pairs(self.tUserIDArr) do
		if v == nUserId then
			self:Print("_AddUser	牌桌已经有玩家 %d",nUserId)
			return 1
		end
	end
	table.insert(self.tUserIDArr,nUserId) 
	--目前这个接口不做错误校验，所以需要配合IsUserFull使用
	return 0
end

--获取玩家通过座位号(获取玩家ID)
function Table:GetUserIdBySit(nSitId)
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser.nSitId == nSitId then
			return self.tUserIDArr[i]
		end
	end
	return 0
end

--获取正在玩的玩家数量
function Table:GetUserPlay()
	local nPlaying = 0
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() == tSrvPub.enumState.nPlay  then
			nPlaying = nPlaying + 1
		end
	end
	return nPlaying
end

-- 获取正在玩的玩家数组
function Table:GetUserPlayArr()
	local tPlaying = {}
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() == tSrvPub.enumState.nPlay  then
			table.insert(tPlaying, self.tUserIDArr[i])
		end
	end
	return tPlaying
end

-- 获取已经坐下的的玩家数组
function Table:GetUserReadyArr()
	local tPlaying = {}
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() >= tSrvPub.enumState.nSetDown  then
			table.insert(tPlaying, self.tUserIDArr[i])
		end
	end
	return tPlaying
end

--获取旁观者用户数组
function Table:GetLookPlay()
	local tLook = {}
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if tUser:GetStatus() ~= tSrvPub.enumState.nPlay  then
			table.insert(tLook, self.tUserIDArr[i])
		end
	end
	return tLook
end

-- 看牌抢庄定庄
function Table:KanPaiQiangZhuang()
	local tMaxUserID = {}
	local nMaxTimes = 0
	local Byway = 0
	for k, v in pairs(self.tQiangZhuang) do
		if v.nTimes >= nMaxTimes then
			nMaxTimes = v.nTimes
		end
	end
	for k, v in pairs(self.tQiangZhuang) do
		if v.nTimes >= nMaxTimes then
			table.insert(tMaxUserID,k)
		end
	end	
	local nMaxUserID = 0
	if self:IsNeedControl() then
		local tAndUserArr = {}
		for k, v in pairs(tMaxUserID) do
			local tUserInfo = tUserMgr.GetUserInfo(v)
			if tUserInfo.isAndroid == true then
				table.insert(tAndUserArr, v)
			end
		end
		if #tAndUserArr > 0 then
			nMaxUserID = tAndUserArr[math.random(1,#tAndUserArr)]
		end
		if nMaxUserID == 0 then
			nMaxUserID = tMaxUserID[math.random(1,#tMaxUserID)]
		end
	else
		nMaxUserID = tMaxUserID[math.random(1,#tMaxUserID)]
	end
	if (nMaxTimes == 0) then
		self:Print("_KanPaiQiangZhuang  没人抢随机定庄")
		Byway =3
	else
		if (#tMaxUserID >=2) then
			self:Print("_KanPaiQiangZhuang 	倍数一样随机定庄")
			Byway = 2
		end
	end
	local tUserInfo = tUserMgr.GetUserInfo(nMaxUserID)
	self.nZhuangSitId = tUserInfo.nSitId
	return nMaxUserID, Byway
end

--看牌抢庄（抢庄倍数）
function Table:QiangZhuang(nUserID, nTimes,bIsUser)
	if (self.nStep ~= tSrvPub.enumStep.nQiangZhuang) then
		self:Print("_QiangZhuang nUserID: %d抢庄不合法 当前牌桌阶段是%d",nUserID or 0, self.nStep)
		return
	end
	local tPlayingArr = self:GetUserPlayArr()
	local bFlag = false
	for k, v in pairs(tPlayingArr) do
		if (nUserID == v) then
			local tUserQiang= {}
			tUserQiang.nUserID = tPlayingArr[k]
		
			tUserQiang.nTimes = nTimes or 0
			self.tQiangZhuang[nUserID] = tUserQiang
			--self.tUserAction[tSrvPub.enumStep.nXiaZhu] = nUserID
			self:Print("_QiangZhuang	用户: %d  %d 倍抢庄",nUserID, nTimes)
			bFlag = true
			break
		else
			bFlag = false
		end
	end
	if bFlag == true then
		self:Print("_QiangZhuang	广播抢庄")
		self:SendAllUser(nUserID,self.EnumProtocol.QiangZhuang)
		if bIsUser == true then
			self:AddAction(nUserID)
		end
	end
	self:IsAllQiangZhuangFinish()
end

-- 检测是否所有人已抢庄
function Table:IsAllQiangZhuangFinish()
	local tPlayingArr = self:GetUserPlayArr()
	local isAllQiangZhuangFinish = true
	for i = 1, #tPlayingArr do
		if (self.tQiangZhuang[tPlayingArr[i]] == nil) then
			isAllQiangZhuangFinish = false
			break
		end
	end	
	if isAllQiangZhuangFinish then
		local tData = {["TableId"]=self.nTableId}
		tSrvPub.PostInnerEvent(tSrvPub.Event.QIANGZHUANGFINISH, tData)
	end
end

-- 获取机器人是否抢庄最大倍数
function Table:GetAndroidQiangZhuang()
	for nUserID, v in pairs(self.tQiangZhuang) do
		local  tUserInfo = tUserMgr.GetUserInfo(nUserID)
		if tUserInfo ~= nil and tUserInfo.isAndroid == true then
			if v.nTimes >= self.tQiangZhuangCfg[#self.tQiangZhuangCfg] then
				return true
			end
		end
	end
	return false
end

--超时自动抢庄
function Table:AutoQiangZhuang()
	self:Print("_AutoQiangZhuang	超时自动抢庄")
	local tPlayingArr = self:GetUserPlayArr()
	local bFlag = false
	for k, v in pairs(tPlayingArr) do
		if (self.tQiangZhuang[v] == nil) then
			self:QiangZhuang(v,0)
		end
	end 
end

--选定庄家
function Table:ChooseZhuang(nSitId)
	self:Print("_ChooseZhuang  nSitId_%d", nSitId)
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if nSitId == tUser.nSitId then		
			return nSitId
		end
	end	
end

-- 超时自动下注
function Table:XiaZhu()
	local tPlayingArr = self:GetUserPlayArr()
	for i = 1, #tPlayingArr do
		if (self.tXiaZhuArr[tPlayingArr[i]] == nil ) then
			local  tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
			if (tUser ~= nil and tUser.nSitId ~= self.nZhuangSitId) then
				self:Print("_XiaZhu UserID下注超时%d 自动下注",tPlayingArr[i])
				local tUserXiaZhuData = {}
				local  nTimes = 0
				if self.nGameType == tCfg.GameType.TongBiNiuNiu then
					nTimes = 1
				else
					nTimes = 1
				end
				self:UserXiaZhu(tPlayingArr[i], nTimes)
			end
			
		end
	end	 
end

-- 检测是否所有人已下注
function Table:IsAllXiaZhuFinish()
	local tPlayingArr = self:GetUserPlayArr()
	local isAllXiaZhuFinish = true
	for i = 1, #tPlayingArr do
		if (self.tXiaZhuArr[tPlayingArr[i]] == nil ) then
			local  tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
			if (tUser ~= nil and tUser.nSitId ~= self.nZhuangSitId) then
				isAllXiaZhuFinish = false
				break
			end			
		end
	end	
	if isAllXiaZhuFinish then
		local tData = {["TableId"]=self.nTableId}
		tSrvPub.PostInnerEvent(tSrvPub.Event.XIAZHUFINISH, tData)
	end
end

-- 玩家下注
function Table:UserXiaZhu(nUserID, nTimes, bIsUser)
	self:Print("_UserXiaZhu nUserID: %d,nTimes:%d",nUserID or 0, nTimes or 0)
	if (self.nStep ~= tSrvPub.enumStep.nXiaZhu) then
		self:Print("_UserXiaZhu nUserID: %d下注不合法 当前牌桌阶段是%d",nUserID or 0, self.nStep)
		return
	end
	local  tUser = tUserMgr.GetUserInfo(nUserID)
	if (tUser ~= nil and tUser.nSitId == self.nZhuangSitId) then
		self:Print("_UserXiaZhu	庄家不能下注")
		return
	end

	local tPlayingArr = self:GetUserPlayArr()
	local bFlag = false
	for k, v in pairs(tPlayingArr) do 
		if (nUserID == v) then
			local tUserXiaZhuData = {}
			tUserXiaZhuData.nUserID = tPlayingArr[k]
			tUserXiaZhuData.nXiaZhuType = 1 -- 倍数
			tUserXiaZhuData.nGold = nTimes or 1
			self.tXiaZhuArr[nUserID] = tUserXiaZhuData 
			bFlag = true
			break
		else
			bFlag = false
		end
	end

	if bFlag == true then
		self:Print("_UserXiaZhu	广播下注")
		self:SendAllUser(nUserID,self.EnumProtocol.UserXiaZhu)
		if bIsUser == true then
			self:AddAction(nUserID)
		end
	end
	self:IsAllXiaZhuFinish()	
end

--洗牌
function Table:XiPai()
	local TempPai = {}
	TempPai = tPublicMath.RandCard(TempPai)
	self.arrPai = TempPai
	self:Print("_XiPai	不要大小鬼数据：%s",tJson.encode(self.arrPai))
	self.nMaxCardCnt = #self.arrPai
	return self.arrPai
end

--发牌（手牌）
function Table:ShouPai(nNumber)
	local tPlayingArr = self:GetUserPlayArr()
	local nControlStatus = false
	self.nNeedControlUser = 0
	local nUserCount = self:UserControlCount()
	local tPaiArr = {} 
	local tControlUser = tUserMgr.GetUserInfo(self.nNeedControlUser)
	local nControlType = 0
	if tControlUser ~= nil then
		nControlType = tControlUser.nControlStatus
	end
	for i = 1, #tPlayingArr do
		local tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
		local tShouPai = {}
		if nControlType == 4 then
			--控好牌
			if self.nNeedControlUser ~= self.nZhuangUserID then
				self:Print("_ShouPai	控牌用户：%d", tPlayingArr[i])
				-- 控牌 {看牌抢庄}
				if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
					if tUser.nControlStatus > 1 and tUser.isAndroid == false then -- 真人
						local  tCopyArrPai = {} 
						tPublicMath.CopyTable(tCopyArrPai,self.arrPai)
						local tNiuNiu =  tGNiuNiuMath.zuhe(tCopyArrPai,3)
						self.tGm.tHandCard[tUser.nSitId] = tNiuNiu 
					elseif  tUser.isAndroid == true then -- 机器人
						if nUserCount > 0 then -- 真人需要控。机器人一定要控
							self:Print("_ShouPai	机器人控牌：%d", tPlayingArr[i])
							local  tCopyArrPai = {} 
							tPublicMath.CopyTable(tCopyArrPai,self.arrPai)
							local tNiuNiu =  tGNiuNiuMath.zuhe(tCopyArrPai,3)
							self.tGm.tHandCard[tUser.nSitId] = tNiuNiu 
						end
					end
				end
			else	
				self:Print("_ShouPai	控牌用户坐庄 取消控：%d", tPlayingArr[i])
			end			
		else
			-- 控牌 {看牌抢庄}
			if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
				if tUser.nControlStatus > 1 and tUser.isAndroid == false then -- 真人
					local  tCopyArrPai = {} 
					tPublicMath.CopyTable(tCopyArrPai,self.arrPai)
					local tNiuNiu =  tGNiuNiuMath.zuhe(tCopyArrPai,3)
					self.tGm.tHandCard[tUser.nSitId] = tNiuNiu 
					if tUser.nControlStatus == 2 then
					elseif tUser.nControlStatus == 3 then
					end
				elseif  tUser.isAndroid == true then -- 机器人
					if nUserCount > 0 then -- 真人需要控。机器人一定要控
						self:Print("_ShouPai	机器人控牌：%d", tPlayingArr[i])
						local  tCopyArrPai = {} 
						tPublicMath.CopyTable(tCopyArrPai,self.arrPai)
						local tNiuNiu =  tGNiuNiuMath.zuhe(tCopyArrPai,3)
						self.tGm.tHandCard[tUser.nSitId] = tNiuNiu 
					end
				end
			end
		end
	
		-- 控牌end
		--Gm命令
		for j = 1, nNumber do 
			if (self.tGm.tHandCard[tUser.nSitId] ) then 
				if self.tGm.tHandCard[tUser.nSitId][1] ~=nil then
					self:Print("_ShouPai	tGm.tHandCard[tUser.nSitId [1] %s",tJson.encode(self.tGm.tHandCard[tUser.nSitId]))
					local  key =  tPublicMath.FindKeyByID(self.arrPai, self.tGm.tHandCard[tUser.nSitId][1])
					if key ~= nil then
						table.insert(tShouPai, self.arrPai[key])
						table.remove(self.arrPai, key)
					end
					table.remove(self.tGm.tHandCard[tUser.nSitId], 1)
				end
			end
		end
		--手牌
		for j = #tShouPai + 1 , nNumber do
			table.insert(tShouPai, self.arrPai[1])
			table.remove(self.arrPai, 1)
		end
		local tShuffleArr = PublicMath.Shuffle(tShouPai)
		tShouPai = tShuffleArr
		self:Print("_ShouPai	玩家UserID:%d 手牌是%s",tPlayingArr[i], tJson.encode(tShouPai)) 
		self.tUserHandPaiArr[tPlayingArr[i]] = tShouPai  
		if tUser.isAndroid == false and tUser:IsOnLine() == true then
			local tData = {}
			tData.UserID = tPlayingArr[i]
			 tData.ShouPai = tShouPai
			Protocol.ShouPai(tUser.sClientID, tData)
		end	
	end
	--旁观者发牌通知
	local tLook = self:GetLookPlay()
	for k , v in pairs(tLook) do
		local tShouPai = {}
		local tUser = tUserMgr.GetUserInfo(v)
		if tUser.isAndroid == false and tUser:IsOnLine() == true then
			local tData = {}
			tData.UserID = v
			tData.ShouPai = tShouPai
			Protocol.ShouPai(tUser.sClientID, tData)
		end
	end
end

--补发牌
function Table:FaPai(nNumber)
	local tPlayingArr = self:GetUserPlayArr()
	--控牌
	local bCanContor = false
	if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
		local nCount = self:UserControlCount() --玩家需要控牌才能控
		if nCount > 0 then
			local tControlUser = tUserMgr.GetUserInfo(self.nNeedControlUser)
			local nControlType = 0
			if tControlUser ~= nil then
				nControlType = tControlUser.nControlStatus
			end
			if nControlType == 4 then
				--玩家做庄家时不控
				if self.nZhuangUserID ~= self.nNeedControlUser then
					local tPaiShu = tGNiuNiuMath.NumberToCount2(self.tUserHandPaiArr[self.nNeedControlUser])
					local  tNiuWhat =  tGNiuNiuMath.GetNiuCard(  tPaiShu)
					local  nNiuCount = tNiuWhat.NiuWhat
					for j = 1, #self.arrPai do
						self:Print("_FaPai	 %d %d %d  %d  tNiuWhat: %s ",j,self.arrPai[j],tGNiuNiuMath.NumberToCount3(self.arrPai[j]),tNiuWhat.NiuWhat ,tJson.encode( tNiuWhat))
 						nNiuCount = (tGNiuNiuMath.NumberToCount3(self.arrPai[j]) + tNiuWhat.NiuWhat) % 10
						if nNiuCount == 0 then
							nNiuCount = 10
						end
						if nNiuCount > 5 then
							self:Print("_FaPai	nNiuCount: %d ", nNiuCount)
							table.insert(self.tUserHandPaiArr[self.nNeedControlUser], self.arrPai[j])
							table.remove(self.arrPai, j)
							break
						end
					end
					for i = 1, #tPlayingArr do
						if #self.tUserHandPaiArr[tPlayingArr[i]] < 5 then
							local tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
							if tUser.nUserID == self.nZhuangUserID then								
								self:Print("_FaPai	玩家: %d 控牌",tUser.nUserID)
								local tPaiShu = tGNiuNiuMath.NumberToCount2( self.tUserHandPaiArr[tUser.nUserID] )
								local  tUserNiuWhat =  tGNiuNiuMath.GetNiuCard(tPaiShu )
								self:Print("_FaPai	tUserNiuWhat: %s",tJson.encode( tUserNiuWhat))
								for j = 1, #self.arrPai do
									local nTempNiuCount = (tGNiuNiuMath.NumberToCount3(self.arrPai[j]) + tUserNiuWhat.NiuWhat)  % 10
									if nTempNiuCount == 0 then
										nTempNiuCount = 10
									end
										
									if nNiuCount > nTempNiuCount then
										self:Print("_FaPai   %d  NiuWhat_%d ",tGNiuNiuMath.NumberToCount3(self.arrPai[j]),tUserNiuWhat.NiuWhat) 
									
										if #self.tUserHandPaiArr[tUser.nUserID] < 5 then
											table.insert(self.tUserHandPaiArr[tUser.nUserID], self.arrPai[j])
											table.remove(self.arrPai, j)
										end
										break
									end
								end		
							end
						end
					end
				end
			else
				self:Print("_FaPai	满足控牌")
				local tZhuangjiaUser = tUserMgr.GetUserInfo(self.nZhuangUserID)
				if tZhuangjiaUser ~= nil and  tZhuangjiaUser.isAndroid == true then -- 机器人做装一定控
					bCanContor = true
				elseif  tZhuangjiaUser ~= nil and  tZhuangjiaUser.isAndroid == false then -- 庄家是真人
					if self:GetAndroidCount() <= 1 then -- 机器人数少于2人才控牌
						bCanContor = true
					end
				end
		
				if tZhuangjiaUser.isAndroid == true  and  bCanContor then -- 机器人当庄优先控牌 机器人坐庄控牌情况
					self:Print("_FaPai	 玩家: %d 控牌",tZhuangjiaUser.nUserID)
					local tPaiShu = tGNiuNiuMath.NumberToCount2(self.tUserHandPaiArr[tZhuangjiaUser.nUserID])
					local  tNiuWhat =  tGNiuNiuMath.GetNiuCard(  tPaiShu)
					local  nNiuCount = tNiuWhat.NiuWhat
					for j = 1, #self.arrPai do						
						self:Print("_FaPai	j: %d %d %d NiuWhat_%d  tNiuWhat: %s ",j,self.arrPai[j],tGNiuNiuMath.NumberToCount3(self.arrPai[j]),tNiuWhat.NiuWhat ,tJson.encode( tNiuWhat))
						nNiuCount = (tGNiuNiuMath.NumberToCount3(self.arrPai[j]) + tNiuWhat.NiuWhat) % 10
						if nNiuCount == 0 then
							nNiuCount = 10
						end
						if nNiuCount > 5 then
							self:Print("_FaPai	nNiuCount ：%d ", nNiuCount)
							table.insert(self.tUserHandPaiArr[tZhuangjiaUser.nUserID], self.arrPai[j])
							table.remove(self.arrPai, j)
							break;
						end
					end

					for i = 1, #tPlayingArr do
						if #self.tUserHandPaiArr[tPlayingArr[i]] < 5 then
							local tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
							if tUser.isAndroid == false and  tUser.nControlStatus > 1  then -- 控牌比庄家小
								self:Print("_FaPai	玩家: %d 控牌",tUser.nUserID)
								local tPaiShu = tGNiuNiuMath.NumberToCount2( self.tUserHandPaiArr[tUser.nUserID] )
								local  tUserNiuWhat =  tGNiuNiuMath.GetNiuCard(tPaiShu )
								self:Print("_FaPai	tUserNiuWhat_%s",tJson.encode( tUserNiuWhat))
								for j = 1, #self.arrPai do
									local nTempNiuCount = (tGNiuNiuMath.NumberToCount3(self.arrPai[j]) + tUserNiuWhat.NiuWhat)  % 10
									if nTempNiuCount == 0 then
										nTempNiuCount = 10
									end
									if tUser.nControlStatus == 2 then
										if nNiuCount > nTempNiuCount then
											self:Print("_FaPai   %d  NiuWhat_%d ",tGNiuNiuMath.NumberToCount3(self.arrPai[j]),tUserNiuWhat.NiuWhat) 
											
											if #self.tUserHandPaiArr[tUser.nUserID] < 5 then
												table.insert(self.tUserHandPaiArr[tUser.nUserID], self.arrPai[j])
												table.remove(self.arrPai, j)
											end										
											break
										end
									elseif tUser.nControlStatus == 3 then --拿比较好的牌
										if nNiuCount > nTempNiuCount and  nTempNiuCount >= 5 then
											self:Print("_FaPai   %d  NiuWhat_%d ",tGNiuNiuMath.NumberToCount3(self.arrPai[j]),tUserNiuWhat.NiuWhat)  
											if #self.tUserHandPaiArr[tUser.nUserID] < 5 then
												table.insert(self.tUserHandPaiArr[tUser.nUserID], self.arrPai[j])
												table.remove(self.arrPai, j)
											end
											break
										end
									end
									
								end

							end
						end
					end
				elseif tZhuangjiaUser.isAndroid == false  and  bCanContor then -- 真人坐庄控牌				
				end
			end			
		end	
	end
	
	for i = 1, #tPlayingArr do
		local tPai = {}
		for j = 1, nNumber do
			local tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
			--GM命令
			if (self.tGm.tHandCard[tUser.nSitId] ) then
				if self.tGm.tHandCard[tUser.nSitId][1] ~=nil then
					local  key =  tPublicMath.FindKeyByID(self.arrPai, self.tGm.tHandCard[tUser.nSitId][1])
					if key ~= nil then
						if #self.tUserHandPaiArr[tPlayingArr[i]] < 5 then
							table.insert(self.tUserHandPaiArr[tPlayingArr[i]], self.arrPai[key])
							table.remove(self.arrPai, key)
						end				
					end
					table.remove(self.tGm.tHandCard[tUser.nSitId], 1)
				end
			end
		end
		if #self.tUserHandPaiArr[tPlayingArr[i]] < 5 then
			for j = 1, nNumber do
				table.insert(self.tUserHandPaiArr[tPlayingArr[i]], self.arrPai[1])
				table.insert(tPai, self.arrPai[1])
				table.remove(self.arrPai, 1)
			end
		else
			table.insert(tPai, self.tUserHandPaiArr[tPlayingArr[i]][5])
		end 
		local tUser = tUserMgr.GetUserInfo(tPlayingArr[i])
		if tUser.isAndroid == false and tUser:IsOnLine() == true then
			self:Print("发牌:%s", tJson.encode(tPai))
			local tData = {}
			tData.UserID = tPlayingArr[i]
			tData.ShouPai = tPai 
			tData.Pai = tPai[1]
			Protocol.FaiPai(tUser.sClientID, tData)
		end	
	end

	--旁观者发牌通知
	local tLook = self:GetLookPlay()
	for k , v in pairs(tLook) do
		local tShouPai = {}
		local tUser = tUserMgr.GetUserInfo(v)
		if tUser.isAndroid == false and tUser:IsOnLine() == true then
			local tData = {}
			tData.UserID = v
			 tData.ShouPai = tShouPai
			 tData.Pai = 0
			Protocol.FaiPai(tUser.sClientID, tData)
		end
	end
end

--摊牌准备
function Table:UserTanPaiReady(nUserID,bIsUser)
	self:Print("_UserTanPaiReady nUserID: %d",nUserID or 0)
	if (self.nStep ~= tSrvPub.enumStep.nTanPaiReady) then
		self:Print("_UserTanPaiReady nUserID: %d摊牌准备不合法 当前牌桌阶段是%d",nUserID or 0, self.nStep)
		return
	end
	self.tUserAction[nUserID] = nUserID
	self.tTanPaiReady[nUserID] = nUserID
	local nCount = 0 
	for k, v in pairs(self.tTanPaiReady) do
		nCount = nCount + 1
	end
	self:Print("_UserTanPaiReady 摊牌准备人数：%d",nCount)
	self:SendAllUser(nUserID, self.EnumProtocol.UserTanPaiReady)
	if bIsUser == true then
		self:AddAction(nUserID)
	end
	if nCount == self:GetUserPlay() then
		local tData = {["TableId"]=self.nTableId}
		tSrvPub.PostInnerEvent(tSrvPub.Event.TANPAIREADYFINISH, tData) -- 全部准备可以摊牌了
	end
end

--(自动)摊牌准备
function Table:AutoTanPaiReady() 
	local tPlayingArr = self:GetUserPlayArr()
	 for i = 1, #tPlayingArr do
		--玩家超时没摊牌（自动摊牌）
		if (self.tUserAction[tPlayingArr[i]] == nil) then
			self:Print("_TanPai	玩家超时自动摊牌：%d", tPlayingArr[i])
			self:UserTanPaiReady(tPlayingArr[i])
		end
	 end
	 local tData = {["TableId"]=self.nTableId}
	 tSrvPub.PostInnerEvent(tSrvPub.Event.TANPAIREADYFINISH, tData) -- 全部准备可以摊牌了
end

--(自动)摊牌
function Table:TanPai()
	self:Print("_TanPai  正在摊牌")
	local tPlayingArr = self:GetUserPlayArr()
	for i = 1, #tPlayingArr do
		if (self.tTanPaiArr[tPlayingArr[i]] == nil ) then
			--摊牌结算
			self:Print("_TanPai	UserID%d 正在摊牌",tPlayingArr[i])
			self:UserTanPai(tPlayingArr[i])
		end	
	end
end

-- 玩家摊牌
function Table:UserTanPai(nUserID)
	local tShouPai = self.tUserHandPaiArr[nUserID]
	self:Print("_UserTanPai UserID:%d  手牌%s",nUserID, tJson.encode(tShouPai))
	local PaiShu = tGNiuNiuMath.NumberToCount2(tShouPai)
	self:Print("_UserTanPai UserID:%d  排数%s",nUserID, tJson.encode(PaiShu))
	local tCardWhat = tGNiuNiuMath.getNiubyCards(PaiShu)
	self:Print("_UserTanPai UserID:%d  摊牌判断%s 牛 %d",nUserID, tJson.encode(tCardWhat),tCardWhat.NiuWhat)
	if (tCardWhat.NiuWhat ~= 0) then
		tShouPai = tPublicMath.ChongZu(self.tUserHandPaiArr[nUserID], tCardWhat.i, tCardWhat.j)
		self:Print("_UserTanPai UserID:%d  重组后的手牌%s",nUserID, tJson.encode(tShouPai))
	end 
	local tUserData = {}
	local key = tPublicMath.FindKeyByID(self.tPlayFan, tCardWhat.NiuWhat )
	mlogger:info(tJson.encode(self.tHuFan))
	local Times = tPublicMath.FindFanByKey(self.tHuFan,key)
	tUserData.HandCard = tShouPai
	tPublicMath.CopyTable(tUserData.HandCard,tShouPai)
	tUserData.NiuWhat = tCardWhat.NiuWhat
	tUserData.NiuTimes = Times
	self:Print("%s",tJson.encode(tUserData))
	self.tTanPaiArr[nUserID] =   tUserData
	--广播玩家摊牌内容
	self:SendAllUser(nUserID,self.EnumProtocol.UserTanPai)
end

--算分
function Table:CaleScore()
	self:Print("_CaleScore 	统计时间 结算 start.....")
	if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
		self:KanPaiJieSuan()
	end
	self:Print("_CaleScore	统计时间 结算 end.....")
end

-- 写入输赢记录 
function Table:Write_WinLoseRecord(tData)
	local nNumber = 0 
	local tUser = tUserMgr.GetUserInfo(tData.nUserId)
	if (tUser.isAndroid == false) then
		self:Print("_Write_WinLoseRecord	真的写入输赢信息")
		tData.nShopId = tUser.nShopID
		if self.nClubId and self.nClubId > 0 then
			tData.nClubId = self.nClubId
			self:Print("_Write_WinLoseRecord	真的写入输赢信息nClubId_%d  ",tData.nClubId)
		end
		tData.nItemId = self.nItemId or 1
		tData.nJuShu = self.nRound
		tData.nGameId = self.nGameType
		tData.nJuShu = self.nRound
		tData.sTableId = self.sTableId
		if tUser.nUserID == self.nZhuangUserID and self.nGameType ~= tCfg.GameType.TongBiNiuNiu  then
			--按桌抽水
			if self.nNModeType == 3 and tUser.isAndroid == false then
				self:Print("按桌抽水统计: %d dWinLoss %f ",tData.nUserId,tData.nWinlose)
				self:CalTax(tData.nWinlose,tData.nUserId)
			end
			tRecordDbr.Write_BrZhuangWinLoseRecord(tData)
		else
			--按桌抽水
			if self.nNModeType == 3 and tUser.isAndroid == false then
				self:Print("按桌抽水统计: %d dWinLoss %f ",tData.nUserId,tData.nWinlose)
				self:CalTax(tData.nWinlose,tData.nUserId)
			end
			tRecordDbr.Write_WinLoseRecord(tData)
		end
	end
end

-- 写入牌局记录
function Table:WritePaiJu(tData)
	local tPlayUserArr = self:GetUserPlayArr()
	local nNumber = 0 
	for k, v in pairs(tPlayUserArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		if (tUser.isAndroid == false) then
			nNumber = nNumber + 1
		end
	end
	if nNumber > 0 then
		self:Print("_WritePaiJu	真的写入牌局信息")
		tRecordDbr.WritePaiJu(tData)
	end
end

-- 庄家结算
function Table:ZhuangJieSuan()	 
	local tTempJieSuan = {}
	local tZJ = {}
	tZJ.dScore = self:Get_User_Gold(self.nZhuangUserID)
	tZJ.dRes = 0
	self:Print("_ZhuangJieSuan 结算 nZhuangUserID_%d ",self.nZhuangUserID)
	for nZhuang, tJieSuan in pairs(self.tJieSuan) do
		for k , v in pairs(tJieSuan) do
			local tTemp = {}
			tTemp.nUserID = v.nUserID
			tTemp.dScore = self:Get_User_Gold(v.nUserID)
			tTemp.dWinLoss =  0 - v.Sum
			tTemp.dRes =  0
			table.insert(tTempJieSuan, tTemp)
		end
	end
	local nZhuangUserID = 0
	publicApi.QiangZhuangCalculate(tZJ, tTempJieSuan)
	for i = 1, #tTempJieSuan do
		self:Print("_ZhuangJieSuan	tTempJieSuan 用户: %d dWinLoss %f ",tTempJieSuan[i].nUserID,tTempJieSuan[i].dRes)
	end
	for nZhuang, tJieSuan in pairs(self.tJieSuan) do
		for k , v in pairs(tJieSuan) do
			for i = 1, #tTempJieSuan do				
				if v.nUserID == tTempJieSuan[i].nUserID then
					v.Water = 0
					self:Print("_ZhuangJieSuanteshu	tTempJieSuan 用户: %d  dWinLoss %f ",tTempJieSuan[i].nUserID,tTempJieSuan[i].dRes)
					
					-- 大于0算抽水
					if tTempJieSuan[i].dRes > 0 then
						local Sum = tTempJieSuan[i].dRes
						tTempJieSuan[i].dRes = tApi.Floor_2(tTempJieSuan[i].dRes * (1 - self.nTax) )	
						v.Water = tApi.Floor_2( Sum * ( self.nTax) )
					else
						tTempJieSuan[i].dRes = tApi.Floor_2(tTempJieSuan[i].dRes)
					end

					v.Sum = 0 - tTempJieSuan[i].dRes
					break
				end
			end
		end 
	end
	local nTotal =  (tZJ.dRes)
	local nZhuangJiaWater = 0
	-- 抽水扣钱写记录
	local tLostUser = {} --机器人离场数组
	for k, v in pairs(self.tJieSuan) do
		local nWinloseToRobot_zhuang = 0
		local nDrawWaterToRobot_zhuang = 0
		local  tZhuangUserData = tUserMgr.GetUserInfo(self.nZhuangUserID)
		if tZhuangUserData ~= nil and tZhuangUserData.isAndroid == false then --真人坐庄	
		end
		-- 扣除金币
		for k2,v2 in pairs(v) do
			local  tUserData = tUserMgr.GetUserInfo(v2.nUserID) 
			
			if v2.Sum < 0 then
				 tUserData.nLostRound = 0
				self:Print("_ZhuangJieSuan	玩家:%d扣除手续费:%f",v2.nUserID, v2.Water)
			end 			
			self:Print("_ZhuangJieSuan	k2 %d, v2.UserID: %d v2.Sum:%f",k2, v2.nUserID, v2.Sum)
			--机器人是否退出判断（金币因素）暂时废弃
			-- if v2.Sum > 0 then --输钱的人是否是机器人
			-- 	if tUserData.isAndroid == true then
			-- 		local  nGold = 0 
			-- 		tUserData.nLostRound =  tUserData.nLostRound + 1
			-- 		nGold = tUserData.nGold
			-- 		if v2.Sum / nGold >= 1/2  then -- 
			-- 			tLostUser[v2.nUserID] = true
			-- 		else
			-- 			local nRand = math.random(1, 100) 
			-- 			if 1<= nRand and nRand < 30 then -- 输钱 30%概率离场
			-- 				tLostUser[v2.nUserID] = true
			-- 			end			
			-- 		end
			-- 	end
			-- end
			if self.nLevel ~= 0 then
				local tData = {}
				tData.nUserID = v2.nUserID
				tData.nItemID = 1
				tData.nDel = 0 - v2.Sum
				tData.nSourceType = self.nGameType
				local isSuccee =self:Gold_ChangeAndReLock(tUserData,tData.nDel,tData.nSourceType,self.nLevel)
				assert(isSuccee)
				self.tTableOverview:UserSettle(tData.nUserID,tData.nDel)
				self.tStatistic:UserProfit(tData.nUserID,tData.nDel)

				local tRecordData = {}
				tRecordData.nUserId = v2.nUserID
				tRecordData.nGameType = self.nGameType
				tRecordData.nSession = self.nLevel
				tRecordData.nWinlose = 0 - v2.Sum
				tRecordData.nDrawWater = v2.Water
				tRecordData.sPaiJuId = self.nPaiJuKey
				tRecordData.nGroupId = self.nGroup

				local nShopID = 0
				local tUserInfo = tPubUserApi.GetAllUserInfo(v2.nUserID)
				if (tUserInfo ~= nil) then
					nShopID = tonumber(tUserInfo.nShopID)
				end
				tRecordData.nShopId = 	nShopID

				-- 统计跟机器人间发生的输赢
				tRecordData.nWinloseToRobot = 0 
				tRecordData.nDrawWaterToRobot = 0
				local nDrawWaterToRobot = 0
				local  tZhuangUserData = tUserMgr.GetUserInfo(self.nZhuangUserID)				
				local  tXianUserData = tUserMgr.GetUserInfo(v2.nUserID) 
				if tZhuangUserData.isAndroid then
					if tXianUserData.isAndroid == false then
						local nAndroidWinlose = 0
						nAndroidWinlose = tRecordData.nWinlose
						nDrawWaterToRobot = tRecordData.nDrawWater
						
						tRecordData.nWinloseToRobot =  tRecordData.nWinloseToRobot + nAndroidWinlose 
						tRecordData.nDrawWaterToRobot = tRecordData.nDrawWaterToRobot + nDrawWaterToRobot		
					end
				else
					if tXianUserData.isAndroid then
						--闲家
						local nAndroidWinlose = 0
						nAndroidWinlose = tRecordData.nWinlose
						nDrawWaterToRobot = tRecordData.nDrawWater					
						--庄家赢
						if nAndroidWinlose < 0 then	 -- -100													
							nAndroidWinlose = 0 - nAndroidWinlose 
						else
							--庄家输
							nAndroidWinlose = 0 - (nAndroidWinlose + nDrawWaterToRobot)  --100
							nDrawWaterToRobot = 0
						end
						nWinloseToRobot_zhuang = nWinloseToRobot_zhuang + nAndroidWinlose
						nDrawWaterToRobot_zhuang = nDrawWaterToRobot_zhuang + nDrawWaterToRobot
					end
				end
				if tRecordData.nWinloseToRobot ~= 0 then 
					 self:Print("_ZhuangJieSuan	   随机庄 闲 写和机器人战绩nUserId:_%d  nWinloseToRobot_%.2f nDrawWaterToRobot_%.2f ",
					 	v2.nUserID,tRecordData.nWinloseToRobot,tRecordData.nDrawWaterToRobot)
				end 
				if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
					tRecordData.IsControl = self:IsNeedControl()
				else
					tRecordData.IsControl = self:IsCtrlUser(tRecordData.nUserId)
				end
				tRecordData.tElseInfo = {}
				if tRecordData.IsControl then 
					if tUserData.nControlStatus >=1 then      
						tRecordData.tElseInfo.nControlType = tUserData.nControlStatus
					end
				end				
				local  XiaZhu = 0
				-- 牌局记录有效下注额度
				if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
					XiaZhu = self.tXiaZhuArr[v2.nUserID].nGold * self.nBaseScore *  self:GetTimes(k)
					--XiaZhu = self.nBaseScore *  self:GetTimes(k)
				elseif self.nGameType == tCfg.GameType.SuiJiNiuNiu then 
					XiaZhu = self.tXiaZhuArr[v2.nUserID].nGold * self.nBaseScore
				end			
				tRecordData.nXiaZhu = XiaZhu
				tRecordData.nValid = XiaZhu
				self:Write_WinLoseRecord(tRecordData)	
			end
			tUserData.nGold = tUserData.nGold  +  0  - v2.Sum
		end	
		local  tUserData = tUserMgr.GetUserInfo(k)
		--扣除庄家的钱
	
		local nRealGold = 0
		if (nTotal > 0) then
			self:Print("_ZhuangJieSuan	  nTax：%f",self.nTax)
			nRealGold  = tApi.Floor_2(nTotal * ( 1 - self.nTax) )
			nZhuangJiaWater =   tApi.Floor_2(nTotal * ( self.nTax) )
			tUserData.nLostRound = 0
		else
			--庄家是否离场
			nRealGold  = tApi.Floor_2(nTotal  )
			if tUserData.isAndroid == true then
				tUserData.nLostRound =  tUserData.nLostRound + 1
				local  nGold = 0 
				nGold = self:Get_User_Gold(k)
				-- if nTotal / nGold >= 1/2  then -- 
				-- 	tLostUser[k] = true
				-- else
				-- 	local nRand = math.random(1, 100) 
				-- 	if 1<= nRand and nRand < 30 then -- 输钱 30%概率离场
				-- 		tLostUser[k] = true
				-- 	end				
				-- end
			end
		end	
		if self.nLevel ~= 0 then
			local tData = {}
			tData.nUserID = k
			tData.nItemID = 1
			tData.nDel = nRealGold -- TODO手续费
			tData.nSourceType = self.nGameType
			--tPubUserApi.ChangeUserTreasure(tData)
			local isSuccee =self:Gold_ChangeAndReLock(tUserData,tData.nDel,tData.nSourceType,self.nLevel)
			assert(isSuccee)
			self.tTableOverview:UserSettle(tData.nUserID,tData.nDel)
			self.tStatistic:UserProfit(tData.nUserID,tData.nDel)

			local tRecordData = {}
			tRecordData.nUserId = k
			tRecordData.nGameType = self.nGameType
			tRecordData.nSession = self.nLevel
			tRecordData.nWinlose = nRealGold
			tRecordData.nDrawWater = nZhuangJiaWater
			tRecordData.sPaiJuId = self.nPaiJuKey
			tRecordData.nGroupId = self.nGroup
			if self.nGameType == tCfg.GameType.KanPaiNiuNiu then
				tRecordData.IsControl = self:IsNeedControl()
			else
				tRecordData.IsControl = self:IsCtrlUser(tRecordData.nUserId)
			end

			tRecordData.tElseInfo = {}
			if tRecordData.IsControl then 
				if tUserData.nControlStatus >=1 then      
					tRecordData.tElseInfo.nControlType = tUserData.nControlStatus
				end
			end

			tRecordData.nXiaZhu = 0
			tRecordData.nValid = 0

			local nShopID = 0
			local tUserInfo = tPubUserApi.GetAllUserInfo(k)
			if (tUserInfo ~= nil) then
				nShopID = tonumber(tUserInfo.nShopID)
			end
			tRecordData.nShopId = nShopID

			local nTemp = nWinloseToRobot_zhuang
			nDrawWaterToRobot_zhuang = 0
			if nTemp > 0 then
				nTemp =tApi.Floor_2(nTemp * ( 1 - self.nTax) ) -- TODO手续费							
				nDrawWaterToRobot_zhuang = nWinloseToRobot_zhuang - nTemp
				nWinloseToRobot_zhuang = nWinloseToRobot_zhuang - nDrawWaterToRobot_zhuang
			end
			tRecordData.nWinloseToRobot = nWinloseToRobot_zhuang 
			tRecordData.nDrawWaterToRobot = nDrawWaterToRobot_zhuang
			if tRecordData.nWinloseToRobot ~= 0 then 
				self:Print("_ZhuangJieSuan  随机庄 写机器人战绩nUserId:_%d  nWinloseToRobot_%.2f nDrawWaterToRobot_%.2f ",
					k,tRecordData.nWinloseToRobot,tRecordData.nDrawWaterToRobot)
			end
			self:Write_WinLoseRecord(tRecordData)		
		end
		tUserData.nGold = tUserData.nGold + nRealGold -- 扣掉钱
		self.tTotalJieSuan[k] = nRealGold
	end
	-- 加入牌局记录
	--牌局记录牌桌信息
	local  nNumber = self:GetReadyUser()
	if nNumber >= 0 then
		local tData = {}
		tData.tUsersInfo = {}
		tData.tDealCardInfo = {}
		tData.tBetInfo = {}
		tData.tElseInfo = {}
		tData.sPaiJuId = self.nPaiJuKey
		tData.nGameId = self.nGameType
		tData.nRoomId = self.nLevel
		tData.nAnte = self.nBaseScore
		tData.nZhuang = self.nZhuangSitId
		-- 手牌信息
		for k ,v in pairs(self.tTanPaiArr) do
			local  temp = {}
			local tUserInfo = tUserMgr.GetUserInfo(k)
			temp.nSitId = tUserInfo.nSitId
			temp.arrCard = v.HandCard
			temp.nCardType = v.NiuWhat
			temp.nNiuTimes = v.NiuTimes			
			table.insert(tData.tDealCardInfo, temp)	
		end
		local tempnZhuangUserID = 0
		for nZhuangUserID , tUserArr in pairs(self.tJieSuan) do
			tempnZhuangUserID = nZhuangUserID
			for _, tUserData in pairs(tUserArr) do
				while true do
					local tUserInfo = tUserMgr.GetUserInfo(tUserData.nUserID)
					if tUserInfo == nil then
						break
					end
					local  temp = {}
					temp.nUserId = tUserData.nUserID
					temp.nSitId = tUserInfo.nSitId
					temp.sName = tUserInfo.sNickName
					temp.nProfit = 0 - tUserData.Sum
					temp.nDrawWater = tUserData.Water
					temp.sFaceID = tUserInfo.sFaceID
					temp.sGold =  tUserInfo.nGold
					table.insert(tData.tUsersInfo, temp)
					break
				end	
			end
			local tUserInfo = tUserMgr.GetUserInfo(nZhuangUserID)
			if tUserInfo == nil then
				break
			end
			local  temp = {}
			temp.nUserId = nZhuangUserID
			temp.nSitId = tUserInfo.nSitId
			temp.sName = tUserInfo.sNickName
			temp.nProfit = self.tTotalJieSuan[nZhuangUserID]
			temp.nDrawWater = nZhuangJiaWater
			temp.sFaceID = tUserInfo.sFaceID
			temp.sGold =  tUserInfo.nGold
			table.insert(tData.tUsersInfo, temp)
		end
	
		for k, v in pairs(self.tXiaZhuArr) do
			local temp = {}
			local tUserInfo = tUserMgr.GetUserInfo(k)
			temp.nSitId = tUserInfo.nSitId
			temp.nBet = v.nGold
			local QiangZhuang = 0
			if self.tQiangZhuang[k] ~= nil then
				QiangZhuang = self.tQiangZhuang[k].nTimes
			else

			end
			temp.nQiang =  QiangZhuang
			table.insert(tData.tBetInfo,temp)
		end
		local tUserInfo = tUserMgr.GetUserInfo(tempnZhuangUserID)
		if tUserInfo ~= nil then
			local temp = {}
			temp.nSitId = tUserInfo.nSitId
			temp.nBet = 0
			local QiangZhuang = 0
			if self.tQiangZhuang[tempnZhuangUserID] ~= nil then
				QiangZhuang = self.tQiangZhuang[tempnZhuangUserID].nTimes
			else
			end
			temp.nQiang =  QiangZhuang
			table.insert(tData.tBetInfo,temp)
		end
		local tElseInfo ={}
		tElseInfo.tTableInfo =self:GetTableInfoForClub()
		tElseInfo.nClubId=self.nClubId
		tData.tElseInfo = tElseInfo
		tData.sTableId= self.sTableId
		tRecordDbr.Write_PaiJuDetail(tData)
		if self.nClubId then
			local sData ={}
			sData.nClubId =self.nClubId
			sData.nGameId =self.nGameType
			sData.sTableId =self.sTableId
			sData.sPaiJuId =self.nPaiJuKey
			tData.sClubName = self.sClubName
			tData.sSitCount = self.nMaxUser
			local PlayBackData = json.encode(tData)
			sData.sPlayBackData = PlayBackData
			tPublicClub.WritePlayBackData(sData)
		end			
	end	
	self.tTableOverview:PaiJuEnd()
	self.tStatistic:DoPersist(self.sTableId,self.nGameType,self.nClubIdOfCorrect,0,0,self.nGoldType,self.nKeepTime,self.sTableName,self.nGroup) 
	
	--机器人离场判断(场次因素)
	local tPlayUser = self:GetUserPlayArr()
	for k, UserId in pairs(tPlayUser) do
		local  tUserInfo = tUserMgr.GetUserInfo(UserId)
		if tUserInfo ~= nil then
			if tUserInfo.isAndroid == true then
				tUserInfo.nPlayRound = tUserInfo.nPlayRound - 1
				local tAndroidData = MgrAndroid.GetAndroidData(tUserInfo.nUserID)
				if tAndroidData == nil then
					self:Print("[Error]机器人数据错误%d",tUserInfo.nUserID)
					break
				end
				tAndroidData.nMaxRound = tAndroidData.nMaxRound - 1
				if tUserInfo.nPlayRound <= 0 or (self:IsUserFull() and math.random(1,100)<=15) then
					tLostUser[tUserInfo.nUserID] = true
					tUserInfo.nPlayRound =math.random(30,60)	--重新设置玩多少局离开
				end
			end	
		end
	end
	local nMaxCnt = bit.rshift(self.nMaxUser,1)   --self.nMaxUser//2
	nMaxCnt =math.min(nMaxCnt,self.nMaxUser)
	nMaxCnt =(nMaxCnt<0) and 0 or nMaxCnt
	local nCnt =math.random(0,nMaxCnt)
	local nUserCnt = self:GetReadyUserCnt()
	local nRealUserCnt = #self:GetAndroidReadyArr()
	local nNowRobotCnt =(nUserCnt - nRealUserCnt)
	self:Print("_ZhuangJieSuan	nNowRobotCnt:%d ShouldBet:%d nGroupId:%d nRoomId:%d nMaxUser:%d",nNowRobotCnt,nCnt,self.nGroup,self.nLevel,self.nMaxUser)
	if nNowRobotCnt>=nCnt and nNowRobotCnt > (self.nMaxUser-2) then
		--留空位
		local nRandom = math.random(1,2)
		if nRandom == 1 then
			if nNowRobotCnt >  (bit.rshift(self.nMaxUser,1) + 1) then
			-- if nNowRobotCnt >  (self.nMaxUser//2 + 1) then
				local tAndroidArr = self:GetAndroidReadyArr()
				if (#tAndroidArr > 0) then
					self:Print("_ZhuangJieSuan	留空位退出机器人4")
					local nkey = math.random(1, #tAndroidArr)
					tLostUser[tAndroidArr[nkey]] = true
				end
			end
		elseif nRandom == 2 then
			if nNowRobotCnt > (bit.rshift(self.nMaxUser,1) + 2) then
			-- if nNowRobotCnt > (self.nMaxUser//2 + 2) then
				local tAndroidArr = self:GetAndroidReadyArr()
				if (#tAndroidArr > 0) then
					self:Print("_ZhuangJieSuan	留空位退出机器人3")
					local nkey = math.random(1, #tAndroidArr)
					tLostUser[tAndroidArr[nkey]] = true
				end	
			end
		end
	else
		--加载机器人
	end	
	--退出游戏的机器人
	for k, v in pairs(tLostUser) do
		local tUser = tUserMgr.GetUserInfo(k)
		self:Print("_ZhuangJieSuan	退出游戏的机器人：%s", tJson.encode(k))
		if tUser == nil then
			self:Print("_ZhuangJieSuan	tLostUser 获取玩家失败 k_%d",k)
			break
		end
		self:UserLeave(tUser.nUserID)
	end
	self:SendAllUser(nil, self.EnumProtocol.JieSuan)
	-- for k, v in pairs(self.tTotalJieSuan) do
	-- 	self:Print("_ZhuangJieSuan	总结算k:%d,v:%f",k,v)
	-- 	if v > 0 then
	-- 		tLostUser[k] = true
	-- 	end
	-- end
	self:SendAllUser(nil,self.EnumProtocol.GoldChange, nil)
end

-- 获取抢庄倍数
function Table:GetTimes(nUserID)
	local nTimes = 0
	nTimes = self.tQiangZhuang[nUserID].nTimes
	if nTimes == 0 or nTimes == nil then
		nTimes = 1
	end
	return nTimes
end

--看牌抢庄结算
function Table:KanPaiJieSuan() 
	local nZhuangSitId = self.nZhuangSitId
	local tZhuangUserID = self:GetUserIdBySit(nZhuangSitId)
	self:Print("_KanPaiJieSuan	tZhuangUser%s",tJson.encode(tZhuangUserID))
	local tPlayingArr = self:GetUserPlayArr()
	self.nMaxPaiUser = tZhuangUserID
	-- 比牌结算
	for k, v in pairs(tPlayingArr) do
		local tUser = tUserMgr.GetUserInfo(v)
		self:Print("_KanPaiJieSuan	tUser:%s", tJson.encode(tUser)) 
		local nXianUserID = v
		local nZhuangSerID = tZhuangUserID
		if tUser.nSitId ~= self.nZhuangSitId  then
			self:Print("_KanPaiJieSuan	结算过程")
			-- 闲家与庄家对比		
			if (tPublicMath.ComepareCard(self,self.tTanPaiArr[v], self.tTanPaiArr[tZhuangUserID]) == 1)  then --闲家大
				mlogger:info("_KanPaiJieSuan	闲家大")
				local tJieSuan = {}
				local tUserJieSuan = nil			
				local  key = tPublicMath.FindKeyByID(self.tPlayFan, self.tTanPaiArr[v].NiuWhat) 
				self:Print("_KanPaiJieSuan	牌型倍数 key:%d  tHuFan:%s",key,tJson.encode(self.tHuFan))			
				self:Print("_KanPaiJieSuan	闲家:%d 下注金币:%d * 牌桌底分：%d * 牌型倍数:%d * 抢庄倍数:%d ", nXianUserID, self.tXiaZhuArr[nXianUserID].nGold, self.nBaseScore, self.tHuFan[key], self:GetTimes(nZhuangSerID))
				local Sum = self.tXiaZhuArr[nXianUserID].nGold * self.nBaseScore *  self.tHuFan[key] * self:GetTimes(nZhuangSerID)
				--庄家数据
				tJieSuan = {}
				tUserJieSuan = nil
				tJieSuan.nUserID = nXianUserID
				tJieSuan.Sum = 0 - Sum
				tUserJieSuan = self.tJieSuan[nZhuangSerID] 
				if (tUserJieSuan == nil) then
					tUserJieSuan = {}
					self.tJieSuan[nZhuangSerID]  = tUserJieSuan
				end				
				table.insert(tUserJieSuan, tJieSuan )				
			elseif (tPublicMath.ComepareCard(self,self.tTanPaiArr[v], self.tTanPaiArr[tZhuangUserID]) == 2) then -- 庄家大
				self:Print("_KanPaiJieSuan	庄家大")
				local  tJieSuan = {}
				local tUserJieSuan = nil
				local key = tPublicMath.FindKeyByID(self.tPlayFan, self.tTanPaiArr[tZhuangUserID].NiuWhat) 
				self:Print("_KanPaiJieSuan	牌型倍数 key: %d  tHuFan:%s",key, tJson.encode(self.tHuFan))
				self:Print( "_KanPaiJieSuan	闲家:%d 下注金币:%d * 牌桌底分：%d * 牌型倍数:%d * 抢庄倍数:%d ",
				nXianUserID, self.tXiaZhuArr[nXianUserID].nGold, self.nBaseScore, self.tHuFan[key], self:GetTimes(nZhuangSerID))
				local Sum = self.tXiaZhuArr[nXianUserID].nGold * self.nBaseScore *  self.tHuFan[key] * self:GetTimes(nZhuangSerID)				
				--庄家数据
				tJieSuan = {}
				tUserJieSuan = nil
				tJieSuan.nUserID = nXianUserID
				tJieSuan.Sum = Sum
				tUserJieSuan = self.tJieSuan[nZhuangSerID] 
				if (tUserJieSuan == nil) then
					tUserJieSuan = {}
					self.tJieSuan[nZhuangSerID]  = tUserJieSuan
				end
				table.insert(tUserJieSuan, tJieSuan )			
			end	
		end
	end

	self:ZhuangJieSuan()
	self:UpdateCacheOfTax()
end

-- 获取不操作动作的组
function Table:GetUserIDArrNotAction()
	local  tUserIDArr = {}
	for k, v in pairs(self.tUserIDArr) do
		local tUserInfo = tUserMgr.GetUserInfo(v)
		if tUserInfo == nil then
		elseif tUserInfo.nSitId < 1 then
			--旁观玩家不需要处理
		else
			if tUserInfo ~= nil and tUserInfo.nStatus >= tSrvPub.enumState.nPlay then
				tUserIDArr[v] = false
			elseif  tUserInfo ~= nil and  tUserInfo.nStatus < tSrvPub.enumState.nPlay then
				tUserInfo.nTableAction = 0
			end
		end	
	end
	return tUserIDArr
end

--重置游戏
function Table:ResetGame()
	--打印一下牌局状况
	self:Print("_ResetGame 统计时间start.....")
	--牌桌相关
	self.nStep = 0 --当前游戏阶段
	--解锁金币
	self:UnLockUserGold()
	--设置游戏阶段
	self.nStep = tSrvPub.enumStep.nNull
	self.boPlay = false --重新开局 
	local  tExitUser = {}
	local  tNotMoeny = {}
	
	-- 配置改动
	local tRoomConfig, nFail = tConfig.GetRoomConfig_v2(self.nGameType,self.nLevel,self.nGroup)
	if tRoomConfig == nil then
		-- 解散房间
		self:Print("_ResetGame 配置改动 fail") 
	end

	-- 关服维护
 	local IsMainTain, StartTime, EndTime =  tPubUserApi.IsMaintaining(self.nGroup)
	if IsMainTain then
		-- 解散房间
		self:SendAllUser(nil, self.EnumProtocol.CloseServer, {sTimeStart = StartTime, sTimeEnd = EndTime})
		GLogic.DisMissTable(self,1)
		return 
	end

	--关闭桌子还是继续下一局
	local nCloseReason =self:_IsCloseWhenOver()
	if nCloseReason > 0 then
		self:Print("_ResetGame 解散牌桌 解散原因:%d",nCloseReason)
		GLogic.DisMissTable(self,1)
		return
	end

	--下局离场退出
	-- self:Print("_ResetGame	nKickUser_%s",tJson.encode(self.nKickUser))
	for k, v in pairs(self.nKickUser) do
		while true do
			local tUser = tUserMgr.GetUserInfo(k)
			if tUser == nil then
				self:Print("_ResetGame   获取玩家失败 _%d",k)
				break
			end
			if tUser.nSitId > 0 then
				self:UserSetSitUp(tUser.nUserID)
			end
			self:ExitTable(k)
			if tUser ~= nil and tUser.isAndroid ~= true and tUser:IsOnLine() == true then
				Protocol.Rep_LogOut(tUser.sClientID,{UserID = tUser.nUserID,Result = 1})
				MsgPush.SendKickOutNotify(tUser.sClientID,"9",0)
			end
			self:UserLout(tUser)
			table.insert(self.nTableBlacklist,tUser.nUserID)
			break
		end
	end
	self.nKickUser = {}

	--下局离场站起
	for k, v in pairs(self.nStandupUser) do
		while true do
			local tUser = tUserMgr.GetUserInfo(k)
			if tUser == nil then
				self:Print("_ResetGame	nStandupUser 获取玩家失败 _%d",k)
				break
			end
			if self:IsForcedStandList(tUser.nUserID) then
				self:Print("强制站起_%d",tUser.nUserID)
				MsgPush.SendKickOutNotify(tUser.sClientID,"8",0)
				self:RemoveValueFromForcedStandList(tUser.nUserID)
			end
			self:Print("_ResetGame	nStandupUser_%d",tJson.encode(k))
			if tUser.nSitId > 0 then
				self:UserSetSitUp(tUser.nUserID)
			end
			if tUser.isAndroid then
				self:ExitTable(k)
				self:UserLout(tUser)
			end
			break
		end
	end
	self.nStandupUser = {}
	local tAndroidStandup = {}
	for i = 1, #self.tUserIDArr do
		while true do
			local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
			if tUser == nil then
				self:Print("_ResetGame	tUserIDArr 获取玩家失败 %d",self.tUserIDArr[i])
				tUserMgr.LogAllUserData()
				break
			end
			if tUser:GetStatus() < tSrvPub.enumState.nSetDown or tUser.nSitId < 1 then
				--旁观玩家是真实玩家:不是游戏玩家不需要踢出
				--旁观玩家是机器人:站起了就踢出去
				if tUser.isAndroid then
					table.insert(tAndroidStandup,self.tUserIDArr[i])
				end
				break
			end
			-- 离线踢出
			if (tUser:IsOnLine() == false and not tUser.isRetain) then -- 断线
				table.insert(tExitUser,self.tUserIDArr[i])	
				self:Print("_ResetGame	%d玩家断线 踢出房间",self.tUserIDArr[i])
				break
			end
			local  nGold = self:Get_User_UnLockGold(tUser) --self:Get_User_Gold(self.tUserIDArr[i])
			if nGold ~= nil then
				if nGold < self:_GetTableLowerCoin() then
					self:Print("_ResetGame	%d 玩家钱真的不够 站起_%f need_%f",self.tUserIDArr[i],nGold,self:_GetTableLowerCoin())
					table.insert(tNotMoeny,self.tUserIDArr[i])
					break
				end
			end
			break
		end
	end

	--离线退出
	self:Print("_ResetGame	tExitUser_%s",tJson.encode(tExitUser))
	for k, v in pairs(tExitUser) do
		while true do
			local tUser = tUserMgr.GetUserInfo(v)
			if tUser == nil then
				self:Print("_ResetGame	tExitUser 获取玩家失败 %d",v)
				break
			end
			self:UserSetSitUp(tUser.nUserID)
			self:ExitTable(v)
			if tUser ~= nil and tUser.isAndroid ~= true and tUser:IsOnLine() == true then
				Protocol.Rep_LogOut(tUser.sClientID,{UserID = tUser.nUserID,Result = 1})	
			end
			self:UserLout(tUser)
			break
		end
	end
	--机器人站起了退出
	self:Print("_ResetGame	tAndroidStandup_%s",tJson.encode(tAndroidStandup))
	for k, v in pairs(tAndroidStandup) do
		while true do
			local tUser = tUserMgr.GetUserInfo(v)
			if tUser == nil then
				self:Print("_ResetGame	tAndroidStandup 获取玩家失败 %d",v)
				break
			end
			self:ExitTable(v)
			self:UserLout(tUser)
			break
		end
	end
	--钱不够站起
	self:Print("_ResetGame	tNotMoeny_%s",tJson.encode(tNotMoeny))
	for k, v in pairs(tNotMoeny) do
		while true do
			local tUser = tUserMgr.GetUserInfo(v)
			if tUser == nil then
				self:Print("_ResetGame	tNotMoeny 获取玩家失败 %d",v)
				break
			end
			if tUser ~= nil and tUser.isAndroid ~= true and tUser:IsOnLine() == true then
				local  tData = {}
				tData.UserID = v
				tData.Result = -4
				Protocol.UserNotMoney(tUser.sClientID,tData)
				self:UserSetSitUp(tUser.nUserID)
				--Protocol.Rep_LogOut(tUser.sClientID,{UserID = tUser.nUserID,Result = 1})
			elseif tUser ~= nil and tUser.isAndroid == true then
				self:UserSetSitUp(tUser.nUserID)
			end
			break
		end
	end
	--检查是否是不操作站起
	local  tNotAction = {}
	local  tUserIDArr = self:GetUserIDArrNotAction()	
	for nUserID , bFlag in pairs(self.tAction) do
		local tUserInfo = tUserMgr.GetUserInfo(nUserID)
		if tUserInfo ~= nil then
			tUserInfo.nTableAction = 0
			tUserIDArr[nUserID] = true
		end
	end
	--玩家退出 
	for  nUserID , bFlag in pairs(tUserIDArr) do
		if bFlag == false then
			local tUserInfo = tUserMgr.GetUserInfo(nUserID)
			if tUserInfo ~= nil and  tUserInfo.isAndroid ~= true and not tUserInfo.isRetain then
				tUserInfo.nTableAction = tUserInfo.nTableAction + 1
				if tUserInfo.nTableAction >= NotActionNumber then
					table.insert(tNotAction,nUserID )
				end
			end
		end
	end
	self:Print("_ResetGame	tNotAction_%s",tJson.encode(tNotAction))
	for k, v in pairs(tNotAction) do
		while true do
			local tUser = tUserMgr.GetUserInfo(v)
			if tUser == nil then
				self:Print("_ResetGame	获取玩家失败 %d",v)
				break
			end
			--self:ExitTable(v)
			if tUser ~= nil and tUser.isAndroid ~= true then
				local  tData = {}
				tData.UserID = v
				tData.Result = -4
				--TODO 过长时间不操作退出
				self:Print("_ResetGame	长时间未操作退出 %s",tJson.encode(tUser))
				Protocol.UserNotAction(tUser.sClientID,{})
				self:UserSetSitUp(tUser.nUserID)
				--Protocol.Rep_LogOut(tUser.sClientID,{UserID = tUser.nUserID,Result = 1})
			end
			--self:UserLout(tUser)
			break
		end
	end
	--设置牌桌玩家坐下(坐下时重新加锁)
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if (tUser ~= nil and tUser:GetStatus() >= tSrvPub.enumState.nSetDown) then -- 站起
			if tUser.isAndroid then
				tUser:SetStatus(tSrvPub.enumState.nSetDown)
			else
				local isSuccee = self:Gold_Lock(tUser,self:_GetTableLowerCoin())
				if not isSuccee then
					self:Print("_ResetGame  金币加锁失败 UserID:%d  nGold_%f nGoldLock:%f",tUser.nUserID,tUser.nGold,self:_GetTableLowerCoin())
					self:UserSetSitUp(tUser.nUserID)
					return
				else
					tUser:SetStatus(tSrvPub.enumState.nSetDown)
				end
			end
		end
	end
	self:ClearData() -- 清除牌桌数据
	--self:SetEffectTime(3600* 6) --重新开始一局，重新设置牌桌时效
	local tData = {["TableId"]=self.nTableId}
	tSrvPub.PostInnerEvent(tSrvPub.Event.EFFECTSTART, tData)
	self:Print("_ResetGame	统计时间end.....")
	--MgrAndroid:Time_Load_Android(5 * 1000,self.nTableId)
	self:Print("_ResetGame	当前牌桌总人数:%d",#self.tUserIDArr)
	--让留座但还没开始计时的玩家，开始计时
	for i = 1, #self.tUserIDArr do
		local tUser = tUserMgr.GetUserInfo(self.tUserIDArr[i])
		if (tUser ~= nil and tUser:GetStatus() >= tSrvPub.enumState.nSetDown and tUser.isRetain) then -- 站起
			self:_RetainCountDown(tUser)
		end
	end
	tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{isStartGame=false})
end

--清除有关数据
function Table:ClearData() 
	-- 重置庄家ID
	self.tUserPaiJuData.ZhuangJia.nUserID = self.nZhuangUserID
	self.tUserPaiJuData.ZhuangJia.nSitID = self.nZhuangSitId
	self.nZhuangUserID = 0
	self.nZhuangSitId = 0
	self.tXiaZhuArr = {}
	self.tQiangZhuang = {}
	self.tUserHandPaiArr = {}
	self.tTanPaiReady = {}
	self.tTanPaiArr = {}
	self.arrPai = {}
	self.tJieSuan = {}
	self.tTotalJieSuan = {}
	self.tUserAction = {}
	self.tAction = {}
	self.tCtrlUserData = {}
end

--玩家退出房间
function Table:UserLout(tUser)
	if (self.nZhuangUserID == tUser.nUserID) then
		self.nZhuangUserID = 0
	end
	UserLogin.ClearUserData(tUser)
	self:Print("_UserLout	玩家%d退出房间......",tUser.nUserID)
end

--清除玩家动作缓存
function Table:ClearAction()
	self.tUserAction = {} 
end

--检查全部玩家动作是否完成
function Table:CheckActon()
	if (self:GetUserPlay() >= #self.tUserAction()) then
		return true
	else
		return false
	end
end

--玩家离开(断线，离开游戏服，被动)
function Table:UserLeave(nUserID)
	self:Print("_UserLeave 	玩家离开%d",nUserID)
	local tUser = tUserMgr.GetUserInfo(nUserID) 
	if tUser ~= nil then
		-- if (not tUser.isAndroid) then
		-- 	tBase.LogT("离开抽水",nUserID)
		-- 	self:TaxByTableRateSettle(tUser)
		-- end
		if tUser:GetStatus() == tSrvPub.enumState.nPlay then
			tUser:SetOffLine()
			self:Print("_UserLeave 玩家正在玩，不能离开")
			--self:SendAllUser(tUser.nUserID, self.EnumProtocol.UserLeave)
		elseif tUser.isRetain  then
			tUser:SetOffLine()
			self:Print("_UserLeave	玩家正在留坐中,不能离开")
		else
			if tUser:GetStatus() == tSrvPub.enumState.nSetDown then 
				self:UserSetSitUp(nUserID)
			end
			self.tTableOverview:UserLeave(nUserID)
			self:ExitTable(nUserID)
			self:_DoSnapshoot(nUserID)								--清空总览快照
			UserLogin.ClearUserData(tUser)
		end
	end
end


--玩家退出牌桌
function Table:ExitTable(nUserID, bExitGame)
	self:Print("_ExitTable  nUserID_%d", nUserID)
	for k, v in pairs(self.tUserIDArr) do
		if v == nUserID then
			local tUser = tUserMgr.GetUserInfo(nUserID)
			if (not tUser.isAndroid) then
				tBase.LogT("离开抽水",nUserID)
				self:TaxByTableRateSettle(tUser)
			end
			table.remove(self.tUserIDArr, k)
			self:ResetSit(v)
			if bExitGame == false then
				
			else
				tPubUserApi.LeaveGame(v,self.nGameType)
			end			
			local tUserInfo = tUserMgr.GetUserInfo(nUserID)
			if (tUserInfo ~= nil and tUserInfo.isAndroid == true) then
				self:Print("_ExitTable  机器人%d 回收",nUserID)
				local tData = {["userid"]=nUserID,["nLevel"] = self.nLevel}
				tSrvPub.PostInnerEvent(tSrvPub.Event.ANDROIDEXIT, tData)
			end
			tUserInfo.nTableId = 0
			tUserInfo.nSitId = 0
			--self:SendAllUser(v, self.EnumProtocol.UserExit)
			if #self.tUserIDArr <= 1 and self.nStep  <= 2 then
				self:Print("_ExitTable 重置牌桌")
				local tData = {["TableId"]=self.nTableId}
				tSrvPub.PostInnerEvent(tSrvPub.Event.EFFECTSTART, tData)
			end
			self.tTableOverview:UserLeave(nUserID)
			break
		end
	end	
end

-- 机器人回调函数
function Table:OnAndroid(tItem)
	local tUserData =  {}
	tUserData.nUserID = tItem.nUserId
	tUserData.sFaceID = tItem.sHeadUrl
	tUserData.sNickName = tItem.sNickName
	tUserData.nSex = tItem.nSex
	tUserData.nGold = tItem.nGold
	tUserData.isAndroid = true
	tUserData.nGroup = self.nGroup
	tUserData.Location = tItem.sLocation
	
	local tDataGameCfg = tGameCfgRedis.GetGameConifg(self.nGameType,self.nLevel)
	tUserData.nTableId = self.nTableId
	tUserData.dScore = self.nBaseScore
	tUserData.GameLevel = self.nLevel
	tUserData.GameType = self.nGameType
	
	if self.nLevel ~= 0 then
		local  tUserTeasure = tPubUserApi.GetUserTreasure(tItem.nUserId) -- 机器人进来就读
		if tUserTeasure == nil then
			mlogger:error(string.format( "获取财富失败%d",tItem.nUserId ))
		end
		tUserData.nGold = tUserTeasure.nGold or 1000
	else
		tUserData.nGold = TableApi.TiYanAutoGold()
		self:Print("_OnAndroid  虚拟财富 nUserID_%d nGold_%.1f ",tUserData.nUserID,tUserData.nGold)
	end

	if tItem.nMaxRound <=0  or tItem.nMinRound <=0 then
		mlogger:error(string.format( "错误的机器人数据:%s",tJson.encode(tItem) ))
		return
	end
	local nMixRound = tItem.nMinRound
	local nMaxRound = tItem.nMaxRound
	if nMaxRound < nMixRound then
		nMixRound = 1
		nMaxRound = nMixRound
	end
	local nPlay =math.random(30,60)	--玩多少局了离开
	-- if math.random(1,100)<50 then
	-- 	nPlay =math.random(6,20)
	-- end
	self.tTableOverview:LookerIn(tUserData.nUserID,tUserData.sNickName,tUserData.sFaceID)
	tUserMgr.AddUser(tUserData)
	local tUser = tUserMgr.GetUserInfo(tItem.nUserId)
	tUser:SetIsAndroid(true)
	tUser.nPlayRound = nPlay
	local nResult = self:AddUser(tItem.nUserId)
	if nResult >= 0 then 
		tUser.nTableId = self.nTableId
		tUser.dScore = self.nBaseScore
		--自动坐下
		if (nResult == 0) then
			self:AutoSetDown(tItem.nUserId)
		end
	end
end

--'留座离桌'或'回到座位' 请求
function Table:RetainReq(tJsonData)
	local nUserId =tJsonData.nUserId
	local nOp =tJsonData.nOp					
	self:Print("_RetainReq nUserId:%d nOp:%d",nUserId,nOp)
	local tCurUser   = tUserMgr.GetUserInfo(nUserId)
	if not tCurUser then
		return 
	end
	--0:留座离桌
	if nOp ==0 then
		local nCode,sErr =self:_Retain(nUserId)
		self:Print("_RetainReq nCode:%d sErr:%s",nCode,(sErr or "succee"))
		--回复
		Protocol.RetainRsp(tCurUser.sClientID,{nRlt=nCode,nOp=nOp,UserID=nUserId})
		return
	end
	--1:取消'留座离桌'
	if nOp==1 then
		local isStandup = false
		local nCode,sErr =self:_RetainCancel(nUserId,isStandup)
		self:Print("_RetainReq nCode:%d sErr:%s",nCode,(sErr or "succee"))
		--回复
		Protocol.RetainRsp(tCurUser.sClientID,{nRlt=nCode,nOp=nOp,UserID=nUserId})
		return
	end
	self:Print("_RetainReq parameter error")
end

--留座
function Table:_Retain(nUserId)
	local tUser = tUserMgr.GetUserInfo(nUserId)
	if tUser.nSitId < 1 then
		return -1,"user not in seat"
	end
	if tUser.isRetain then
		return -2,"state wrong"
	end
	tUser.isRetain =true

	--取消站起
	for k, v in pairs(self.nStandupUser) do
		while true do
			local tUser = tUserMgr.GetUserInfo(k)
			if tUser == nil then
				break
			end
			if tUser.nUserID == nUserId then
				self:Print("_Retain :cancel standup %d",nUserId)
				self.nStandupUser[k] = nil
				break
			end
			break
		end
	end

	if tUser:GetStatus() == tSrvPub.enumState.nPlay then	--本手牌结束后计时再生效
		return 1
	end
	--开始留座倒计时
	local isB =self:_RetainCountDown(tUser)
	assert(isB,"something wrong")
	return 0
end

--取消留座
function Table:_RetainCancel(nUserId,isStandup)
	local tUser = tUserMgr.GetUserInfo(nUserId)
	if tUser == nil or  tUser.nSitId < 1 then
		return -1,"user not in seat"
	end
	if not tUser.isRetain then
		return -3,"state wrong"
	end
	tUser.isRetain =false
	--取消留座倒计时,如果有的话
	self:_RetainCountDownCancel(tUser)	
	self:Print("_RetainCancel for nUserID: %d ",tUser.nUserID)
	if tUser:IsOnLine() == false or isStandup then
		self:UserSetSitUp(nUserId)
		self:Print("_RetainCancel for nUserID: %d  standup",tUser.nUserID)
		return 0
	end
	self:Print("_RetainCancel for nUserID: %d  sitdown ",tUser.nUserID) 

	-- 是否开始游戏 
	local tData = {["TableId"]=tUser.nTableId}
	tSrvPub.PostInnerEvent(tSrvPub.Event.EFFECTSTART, tData)
	return 0
end

--留座倒计时开始,如果还没开始的话 (离开座位时取消，或玩家主动取消) 
function Table:_RetainCountDown(tUser)
	if tUser.nRetainTimerId then
		return false
	end
	local nSeconds =180
	local isStandup = true --到时自动站起
	tUser.nRetainTimerId =self.TimerForRetain:DelayCall(nSeconds*1000,self._RetainCancel,self,tUser.nUserID,isStandup)
	tUser.tRetainInfo={nStartTime=os.time(),nLen=nSeconds}	
	--广播
	self:Print("_RetainCountDown for user:%d",tUser.nUserID)
	self:SendAllUser(tUser.nUserID,self.EnumProtocol.Retain,{nPos=tUser.nSitId,nOp=0,nSeconds=nSeconds})
	return true
end

--取消留座倒计时,如果有的话
function Table:_RetainCountDownCancel(tUser)
	if not tUser.nRetainTimerId then
		return false
	end
	self.TimerForRetain:KillTimer(tUser.nRetainTimerId)
	tUser.nRetainTimerId=nil
	tUser.tRetainInfo=nil
	--广播
	self:Print("_RetainCountDownCancel for user:%d",tUser.nUserID)
	self:SendAllUser(tUser.nUserID,self.EnumProtocol.Retain,{nPos=tUser.nSitId,nOp=1})
	return true
end

function Table:_UserCount_NotRetain()
	local nCnt =0
	for nPos=1,self.nMaxUser do
		local tUser = self:GetUserIdBySit(nPos)
		if tUser and (not tUser.isRetain) then
			nCnt =nCnt+1
		end
	end
	return nCnt
end

--表情金币花费
function Table:_GetChatCost(nChatId)
	for _,v in ipairs(self.arrChat) do
		if v.nChatId ==nChatId then
			return v.nCost
		end
	end
	return 0
end

--玩家坐下或者发表情最低保有金币
function Table:_GetTableLowerCoin()
	-- 底分*最大牌型倍数*牌桌最大人
	if self.nBaseScore > 0 and self.nMaxUser > 0 and self.tHuFan[14] > 0 then
		return self.nBaseScore*self.nMaxUser*self.tHuFan[14]
	else
		self:Print("_GetTableLowCoin nBaseScore:%d nMaxUser:%d  cardMaxtime:%d",self.nBaseScore,self.nMaxUser,self.tHuFan[14] or 8)
		return 5000
	end
end

--表情聊天 请求
function Table:Chat(sClientID,tData)
	local nUserID = tData.UserID
    local nChatId = tData.nChatId
    local nTarget = tData.nTarget					
	self:Print("_Chat nUserId:%d nChatId:%d  nTarget:%d",nUserID,nChatId,nTarget)
	local tCurUser   = tUserMgr.GetUserInfo(nUserID) 
	if not tCurUser then
		self:Print("_Chat  Fail,User is Nil  nUserID_%d ",nUserID)
		return 
	end
	local nSpeaker  = tCurUser.nSitId or 0 --聊天发起者座位号，如果是旁观者则用0表示
	local nTargetUserId = self:GetUserIdBySit(tData.nTarget)
	local tTargetUser   = tUserMgr.GetUserInfo(nTargetUserId) 
	if not tTargetUser or tTargetUser.nSitId <= 0 then
		self:Print("_Chat Fail,nTarget Pos User is Nil ")
		Protocol.ChatRsp(sClientID,{UserID= nUserID,nRlt=2})
		return
	end
	local nCost =self:_GetChatCost(tData.nChatId)
	self:Print("_Chat	nChatId:%d Chat Cost:%.2f",tData.nChatId,nCost)
	--扣金币
	if nCost>0 then
		if not tPubUserApi.ChangeUserTreasure({nUserID=nUserID,nItemID=1,nDel=-nCost,nSourceType=self.nGameType}) then
			self:Print("_Chat   Fail,no Gold 1 ")
			Protocol.ChatRsp(sClientID,{UserID= nUserID,nRlt=1})
			return
		end
	end
	tCurUser.nGold = tPubUserApi.Get_User_Gold(nUserID)
	self:Print("_Chat  User_%d nGold_%f",nUserID,tCurUser.nGold)
	local tSendData = {}
	tSendData.nSpeaker = nSpeaker
	tSendData.nChatId = tData.nChatId
	tSendData.nTarget = tData.nTarget
	self:SendAllUser(nUserID,self.EnumProtocol.ChatNotify,tSendData)
	if nCost>0 then
		local tSendData1 = {}
		tSendData1.nUserID = nUserID
		tSendData1.nReason = 1 --聊天扣费
		self:SendAllUser(nUserID,self.EnumProtocol.GoldChange, tSendData1)
	end	
end

local function _CutOff(arr,nRemainCnt)
	local tS =tStack:New()
	while (#arr>nRemainCnt) do
		local tItem =table.remove(arr)
		tS:Push(tItem)
	end
	return tS
end

--牌桌总览 请求
function Table:OverView(sClientID,tData)
	local nUserId = tData.nUserID			
	local nNoUse =tData.nNoUse or 0
	-- self:Print("OverView nUserId:%d nNoUse:%d",nUserId,nNoUse)
	local tCurUser   = tUserMgr.GetUserInfo(nUserId)
	if not tCurUser then
		return 
	end	
	if nNoUse == 0 then --新的请求
		local tOverview= self.tTableOverview:GetOverview()
		self:Print("OverViewReq arrPartInUser Len:%d",#tOverview.arrPartInUser)
		local tRemainStack =_CutOff(tOverview.arrPartInUser,self.nOverViewRtLen)	--截断arrPartInUser,只保留20个数据
		tOverview.sPaiJuId = self.nPaiJuKey --牌局编号
		tOverview.sTableName = self.sTableName --牌桌名称
		tOverview.nBaseScore = self.nBaseScore --牌桌底分
		tOverview.nRound = self.nRound --第几手
		tOverview.nRemainTime = self:_GetRemainTime() --剩余时间
		tOverview.nEndFlag =tRemainStack:IsEmpty() and 0 or 1			--1:列表还未结束, 其它:已结束
		-- self:Print("nEndFlag:%d,nRemainTime:%d",tOverview.nEndFlag,tOverview.nRemainTime)
		Protocol.OverViewRsp(sClientID,tOverview)
		--创建快照
		tOverview.arrPartInUser ={}
		self:_DoSnapshoot(nUserId,tOverview,tRemainStack)
		return
	end
	if nNoUse==1 then --继续获取剩下的数据
		local tOverview,tRemainStack =self:ObtainFromSnapshoot(nUserId)
		assert(tOverview~=nil)
		tOverview.nRemainTime=self:_GetRemainTime()
		tOverview.nEndFlag =tRemainStack:IsEmpty() and 0 or 1			--1:列表还未结束, 其它:已结束
		Protocol.OverViewRsp(sClientID,tOverview)
		--创建快照
		tOverview.arrPartInUser ={}
		self:_DoSnapshoot(nUserId,tOverview,tRemainStack)
		return
	end
	if nNoUse== -1 then --总览界面关闭
		self:_DoSnapshoot(nUserId)								--清空快照
		return
	end
end

function Table:ObtainFromSnapshoot(nUserId)
	local tCache =self.tOverviewSnapshoot[nUserId]
	if not tCache then
		return
	end
	local tOverview =tCache.tOverview
	local tRemainStack =tCache.tRemainStack
	local arrPartInUser ={}
	while (#arrPartInUser<self.nOverViewRtLen and (not tRemainStack:IsEmpty())) do
		local tItem =tRemainStack:Pop()
		table.insert(arrPartInUser,tItem)
	end
	tOverview.arrPartInUser =arrPartInUser
	return tOverview,tRemainStack
end

function Table:_DoSnapshoot(nUserId,tOverview,tRemainStack)
	if tOverview==nil or tRemainStack==nil then
		self.tOverviewSnapshoot[nUserId]=nil
		return
	end
	if not tRemainStack:IsEmpty() then
		self.tOverviewSnapshoot[nUserId] ={tOverview=tOverview,tRemainStack=tRemainStack}
	else
		if self.tOverviewSnapshoot[nUserId] then
			self.tOverviewSnapshoot[nUserId]=nil
		end
	end
end

-- 头像信息请求
function Table:HeadInfo(sClientID,tData)
	local nPos =tData.nPos 
	local nUserId = tData.nUserID
	self:Print("_HeadInfoReq,nUserId_%d nPos_%d",nUserId,nPos)
	if nPos <= 0 or nPos > self.nMaxUser then
		self:Print("_HeadInfoReq, nPos_%d  is wrong",nPos)
		return
	end
	local nTempUserID = self.arrSit[nPos] or 0
	local tSeatUser   = tUserMgr.GetUserInfo(nTempUserID) 
	if not tSeatUser or tSeatUser.nSitId <= 0 then
		self:Print("_HeadInfoReq	Not Find SeatUser %d",nTempUserID)
		return
	end
	local tInfo =tPublicRedis.GetUserTexaStatisticL(tSeatUser.nUserID,self.nClubIdOfCorrect,self.nGameType,self.nGoldType)
	local tUserInfo ={}
	local nUnLockGold =0
	if not tSeatUser.isAndroid then
		tUserInfo =tPubUserApi.GetAllUserInfo(tSeatUser.nUserID)
		nUnLockGold =self:Get_User_UnLockGold(tSeatUser)
	else
		nUnLockGold = math.random(1,self:_GetTableLowerCoin())
		tSeatUser.nUnLockGold=nUnLockGold
	end
	local HeadInfoRsp ={}
	HeadInfoRsp.nUserId=tSeatUser.nUserID								 --玩家ID
	HeadInfoRsp.sFaceId=tSeatUser.sFaceID								 --头像url
	HeadInfoRsp.sName=tSeatUser.sName			 						--昵称
	HeadInfoRsp.nSex=tSeatUser.nSex	    								--性别 0:男 1:女
	HeadInfoRsp.nBalance=nUnLockGold									--余额(金币)
	HeadInfoRsp.sSigna=tUserInfo.sPersonality or ""						--签名 (""表示没签名)
	HeadInfoRsp.nVipLev=tonumber(tUserInfo.nVip or 0)					--vip等级
	HeadInfoRsp.nPlayCount=tInfo.nPlayCount								--总手数
	HeadInfoRsp.nProfit=tInfo.nProfitSum								--盈亏
	HeadInfoRsp.nJuShu =tInfo.nJuShu or 0								--局数
	Protocol.HeadInfoRsp(sClientID,HeadInfoRsp)
end

-- 牌局详情 请求
function Table:PaijuDetail(sClientID,tData)
	local sPaiJuID =tData.sPaiJuID
	local nUserId = tData.nUserID
	self:Print("_PaijuDetail	nUserId_%d sPaiJuID_%s",nUserId,sPaiJuID)	
	local tUser   = tUserMgr.GetUserInfo(nUserId) 
	if not tUser then
		self:Print("_PaijuDetail  Not Find SeatUser nUserId: %d ",nUserId)
		return
	end
	local sSql =string.format("call PaiJuDetail_Read_v6('%s')",tData.sPaiJuID)
   	local tPacket =DbServAux:Encode("GetResultsBySqlReq",{sEcho=tData.sPaiJuID,sSql=sSql,sDbName="DJH_RecordDB",nUserId=nUserId})
   	tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

function Table:_IsCloseWhenOver()
	--local conditionA = (self.nCloseTableWhenOver ==tSrvPub.TableCloseReason.nBackstageClose --[[ and (tPublicRedis._GetCloseTableStates(self.sTableId)==1) ]])
	local conditionA = (self.nCloseTableWhenOver ==tSrvPub.TableCloseReason.nBackstageClose or self.nCloseTableWhenOver ==tSrvPub.TableCloseReason.nClubTableTimeOut)
	if conditionA then
		return self.nCloseTableWhenOver
	end
	return self.nCloseTableWhenOver 
end

--是否一局结束后关闭桌子
function Table:SetClose(nCloseReason)
	self:Print("_SetClose 	Reason:%d",nCloseReason)
	if self.nStep ~=tSrvPub.enumStep.nNull then
		self.nCloseTableWhenOver =nCloseReason
		return 
	end
end

--俱乐部桌子是否超时
function Table:IsClubTableTimeOut()
	if self:_GetRemainTime() ==0 then
		return true
	end
	--self:SetEffectTime(60) --设置牌桌时效	
	return false
end

--牌桌配置信息
function Table:_GetTableConfig()
	local tem ={}
	tem.sTableName=self.sTableName	  			--房间名称,不带<>符号
	tem.sPaiJuId=self.nPaiJuKey		 			--牌局编号
	tem.sClubName=self.sClubName	  			--俱乐部名称,不带[]符号
	tem.nBaseScore=self.nBaseScore	 			--底分
	tem.isOnlyPlayByIOS=false --self.isOnlyPlayByIOS 	--是否仅限IOS玩 true:是 fasle:否
	tem.isGPSLimit=false --self.isGPSLimit	  			--是否开启GPS限制 true:是 fasle:否
	tem.isIPLimit=false --self.isIPLimit		  		--是否开启ip地址限制 true:是 fasle:否
	tem.nPlayerAtLeast =self.nPlayerCntAtLeast
	if tem.nPlayerAtLeast==nil or tem.nPlayerAtLeast<2 then
		tem.nPlayerAtLeast =9
	end
	return tem
end

 --牌桌广播协议
function Table:SendAllUser(nUserID,nType,tData)
	local tUser = tUserMgr.GetUserInfo(nUserID)
	for k ,v in pairs(self.tUserIDArr) do
		local tCurUser   = tUserMgr.GetUserInfo(v)		
		if tCurUser ~= nil and tCurUser.isAndroid ~= true and tCurUser:IsOnLine() == true then
			if nType == self.EnumProtocol.UserXiaZhu  then
				local tXiaZhuData = self.tXiaZhuArr[nUserID] --其它
				if (tXiaZhuData == nil) then
					mlogger:error(string.format( "nUserID : %d 下注信息不存在",nUserID ))
					return
				end
				local tSendData = {}
				tSendData.UserID = nUserID
				tSendData.Times = tXiaZhuData.nGold
				Protocol.XiaZhu(tCurUser.sClientID, tSendData)
			elseif nType == self.EnumProtocol.XiaZhuPush then
				local tXiaZhuArr = self.InitXiaZhuCfg()
				for k, v in pairs(self.XiaZhuPush) do
					self:Print("下注信息 %s",tJson.encode(v))				
					if v.nUserID ~= tCurUser.nUserID then
						if (self:GetIndexByVal(v.nGold)) then
							local  key = self:GetIndexByVal(v.nGold)
							tXiaZhuArr[v.nIndex - 1][key] = tXiaZhuArr[v.nIndex - 1][key] + 1
						end
					end			
				end

			elseif nType == self.EnumProtocol.QiangZhuang then
				local tQiangZhuang = self.tQiangZhuang[nUserID]
				if (tQiangZhuang == nil) then
					mlogger:error(string.format( "nUserID : %d 抢庄信息不存在",nUserID ))
					return
				end
				local tSendData = {}
				tSendData.UserID = nUserID
				tSendData.Times = tQiangZhuang.nTimes
				Protocol.QiangZhuang(tCurUser.sClientID, tSendData)
			elseif nType == self.EnumProtocol.UserTanPaiReady then 
				local tSendData = {}
				tSendData.UserID = nUserID
				tSendData.Ready =  1
				Protocol.Rep_TanPaiReady(tCurUser.sClientID, tSendData)
			elseif nType == self.EnumProtocol.UserTanPai then
				local tTanPaiData = self.tTanPaiArr[nUserID]
				if (tTanPaiData == nil) then
					mlogger:error(string.format( "nUserID : %d 摊牌信息不存在",nUserID ))
					return
				end
				local tSendData = {}
				tSendData.UserID = nUserID
				tSendData.NiuWhat = tTanPaiData.NiuWhat
				tSendData.ShouPai = tTanPaiData.HandCard
				tSendData.NiuTimes = tTanPaiData.NiuTimes
				Protocol.TanPai(tCurUser.sClientID, tSendData)				
			elseif nType == self.EnumProtocol.UserEnter then
			elseif nType == self.EnumProtocol.UserSitDown then
				local tSendData = {}				
				tSendData.UserID = nUserID
				tSendData.Action = 1
				tSendData.SitID = tUser.nSitId
				tSendData.nRlt = 0
				local tUserData = {}
				tUserData.UserID = tUser.nUserID
				tUserData.Name = tUser.sNickName or "2111"
				tUserData.Sex = tUser.nSex
				tUserData.FaceID = tostring(tUser.sFaceID)
				tUserData.SitID =  tUser.nSitId or 0
				tUserData.Status = tUser.nStatus or 0
				tUserData.Gold = tUser.nGold or 0
				tUserData.Online = true
				tSendData.tUserData = tUserData
				Protocol.UserAction(tCurUser.sClientID, tSendData)
			elseif nType == self.EnumProtocol.UserSitUp then
				local tSendData = {}				
				tSendData.UserID = nUserID
				tSendData.Action = 0
				tSendData.SitID = tUser.nSitId
				tSendData.nRlt = 0
				Protocol.UserAction(tCurUser.sClientID, tSendData)
			elseif nType == self.EnumProtocol.JieSuan then
				local tSendData = {}
				tSendData.tUserData = {}
				for k , v in pairs(self.tJieSuan) do					
					local tData = {}
					tData.UserID = k
					tData.TotalWin = self.tTotalJieSuan[k]
					tData.WinObjectArr = {}
					for k2,v2 in pairs(v) do						
						local Obj = {}
						Obj.UserID = v2.nUserID
						Obj.Gold = v2.Sum
						Obj.Index = v2.Index
						table.insert(tData.WinObjectArr, Obj)
					end
					table.insert(tSendData.tUserData, tData)
				end
				Protocol.JieSuan(tCurUser.sClientID, tSendData)				
			elseif nType == self.EnumProtocol.ResetGame then
				local tSendData = {}
				tSendData.TableNumber = tostring(self.nTableId)
				tSendData.time = self.tTimeCfg.nReset
				Protocol.ResetGame(tCurUser.sClientID, tSendData)
			elseif nType ==  self.EnumProtocol.UserLeave then
				local tSendData = {}
				tSendData.UserID = nUserID
				tSendData.Status = 2
				Protocol.UserLeaveTable(tCurUser.sClientID, tSendData)
			elseif nType ==  self.EnumProtocol.UserExit then
				local tSendData = {}
				tSendData.UserID = nUserID
				tSendData.Status = 1
				Protocol.UserLeaveTable(tCurUser.sClientID, tSendData)
			elseif nType == self.EnumProtocol.GoldChange  then
				local  tPlayArr = {}
				tPlayArr = self:GetUserPlayArr()
				local tGoldArr ={}
				if tData and (tData.nReason == 1 or tData.nReason == 2) then
					--1.聊天扣费 2.后台充值
					local tGold = {}
					local tUserInfo = tUserMgr.GetUserInfo(tData.nUserID)
					if tUserInfo ~= nil then
						tGold.nUserID = tData.nUserID
						tGold.nGold = tUserInfo.nGold
					else
						tGold.nUserID = tData.nUserID or 0
						tGold.nGold = 0
					end
					table.insert(tGoldArr,tGold )
				else
					for k, v in pairs(tPlayArr) do
						local tGold = {}
						local tUserInfo = tUserMgr.GetUserInfo(v)
						if tUserInfo ~= nil then
							tGold.nUserID = v
							tGold.nGold = tUserInfo.nGold
						else
							tGold.nUserID = v or 0
							tGold.nGold = 0
						end
						table.insert(tGoldArr,tGold )
					end
				end				
				Protocol.UserGoldChange(tCurUser.sClientID, tGoldArr)
			elseif nType == self.EnumProtocol.UserStatusChange then
				--self:Print("UserStatusChange")
				local tUserInfo = tUserMgr.GetUserInfo(nUserID)
				if tUserInfo == nil  then
					mlogger:error(string.format( "UserStatusChange : %d 失败", nUserID ))
					return 
				end
				Protocol.UserStatusChange(tCurUser.sClientID,{nUserID = tUserInfo.nUserID, nStatus = tUserInfo.nStatus  })
			elseif nType == self.EnumProtocol.PeiZhiDiuShi then
				MsgPush.SendKickOutNotify(tCurUser.sClientID,"", -2)
			elseif nType == self.EnumProtocol.CloseServer then
				MsgPush.SendMaintenanceNotify(tCurUser.sClientID, tData.sTimeStart,tData.sTimeEnd)
			elseif nType ==  self.EnumProtocol.Retain then
				local tSendData = {}
				tSendData.nPos = tData.nPos
				tSendData.nOp = tData.nOp
				tSendData.nSeconds = tData.nSeconds
				Protocol.RetainNotify(tCurUser.sClientID, tSendData)
			elseif nType ==  self.EnumProtocol.ChatNotify then
				local tSendData = {}
				tSendData.nSpeaker = tData.nSpeaker
				tSendData.nChatId = tData.nChatId
				tSendData.nTarget = tData.nTarget
				Protocol.ChatNotify(tCurUser.sClientID, tSendData)
			end
		end
	end
end

function Table:TaxByTableRateSettle(tUser)
	-- tBase.LogT("进入方法",tUser.nUserID)
	local nUserId =tUser.nUserID
	local nTax,sTaxTag,sLatelyPaiJuId, sLatelyTableId =self.tGather:Settle(nUserId,self.nTableTax)
	if self:IsUseCredit() then	--积分结算房
		return
	end
	if nTax==nil then
		return
	end
	local isSuccee =tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=self.nItemId,nDel=-nTax,nSourceType=self.nGameId, 
		sTableId = sLatelyTableId,
		sPaiJuId = sLatelyPaiJuId})
	if not isSuccee then
		self:Print("TaxByTableRateSettle fail,nUserID:%d,nTax:%.2f,sTaxTag:%s",nUserId,nTax,sTaxTag)
		return
	end
	self:Print("TaxByTableRateSettle,nUserID:%d,nTax:%.2f,sTaxTag:%s,nTaxRate:%.2f",nUserId,nTax,sTaxTag,self.nTableTax)
	self:WriteRecordForTax(tUser,nTax,sTaxTag,sLatelyPaiJuId)
end

function Table:TaxByTableRateSettle_All()
	local arrUserId =self.tGather:GetAllUserId()
	for _,nUserId in ipairs(arrUserId) do
		self:TaxByTableRateSettle(nUserId)
	end
end


function Table:WriteRecordForTax(tUser,nTaxGold,sTaxTag,sLatelyPaiJuId)
	-- if self:MatchRoomId()==0 then return end
	if tUser.isAndroid then return end

	local tData ={}
	tData.nClubId =self.nClubId --俱乐部id
	tData.sTableId=self.sTableId --牌桌id
	tData.nItemId= self.nItemId--道具id
	tData.nGameType=self.nGameType --游戏id
	tData.nUserId=tUser.nUserID --玩家id
	tData.nDrawWater=nTaxGold --抽水
	tData.sPaiJuId=sLatelyPaiJuId --牌局id
	tData.nClubIdOfCorrect=self.nClubIdOfCorrect

	if self.nStep >= tSrvPub.enumStep.nStartGame and self.nStep <= tSrvPub.enumStep.nReset and self.nPaiJuKey==sLatelyPaiJuId then
		table.insert(self.arrTaxForUpdate,tData)
	else
		RecordDbr.Update_WinLoseRecordTaxV2(tData)
	end

end

function Table:UpdateCacheOfTax()
	for _,item in ipairs(self.arrTaxForUpdate) do
		RecordDbr.Update_WinLoseRecordTaxV2(item)
	end
	self.arrTaxForUpdate ={}
end

function Table:CalTax(nProfit,nUserId)
	if self.nNModeType==3 then	--该模式的抽水，延迟至站起时才收
		tBase.LogT("放入牌局id",self.nPaiJuKey)
		local sTaxTag =self.tGather:Gather(nProfit,nUserId,self.nPaiJuKey)
		return 0,sTaxTag
	end
	return 0
end

function Table:AdjustedAndroid()
	self.ifAdjustedAndroid = 1
end

function Table:ReserveAndroid(nReserve)
	-- self.CurConfigAndroid = self.CurConfigAndroid + nReserve
	if nReserve > 0 then
		self.adjustAddCnt = self.adjustAddCnt + nReserve
	end
end

function Table:ReduceAdjustAddCnt()
	self.adjustAddCnt = self.adjustAddCnt - 1
end

--桌子黑名单 被强制踢出后
function Table:IfBlacklist(nUserId)
	for _, v in ipairs(self.nTableBlacklist) do
        if v == nUserId then
            return true
        end
    end
    return false
end

--记录强制站起
function Table:AddForcedStandUser(nUserId)
	table.insert(self.nForcedStandList,nUserId)
end

--是否被强制站起
function Table:IsForcedStandList(nUserId)
	for _, v in ipairs(self.nForcedStandList) do
        if v == nUserId then
            return true
        end
    end
    return false
end

--移除强制站起
function Table:RemoveValueFromForcedStandList(nUserId)
	for i = #self.nForcedStandList, 1, -1 do
	  if self.nForcedStandList[i] == nUserId then
		table.remove(self.nForcedStandList, i)
	  end
	end
end


return Table
