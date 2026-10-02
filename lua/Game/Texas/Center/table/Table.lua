
local tBase 	  = require("base")         -- 基础功能接口
local Define =require("Define")
local RecordDbr =require("RecordDbr")
local tPubUser = require("PublicUserInfo") -- 用户信息
local tGameConfig =require("GameConfig") -- 
local bit = require("bit")
local tTimerAux =require("TimerAux")
local cjson    = require("cjson")
local tPublicRedis =require("PublicRedis")
local tAlg =require("GameAlg")
local publicApi =require("publicApi")
local tSlaveManager =require("SlaveManage")
local tPublicClub =require("PublicClub")
local Review =require("Review")
local json    = require("json")
local Statistic =require("Statistic")
local PublicDefine =require("PublicDefine")


local TableState =Define.TableState
local UserStatus =Define.UserStatus
local UserOp =Define.UserOp
local TableCloseReason =Define.TableCloseReason

local function _CopyArr(arr)
	local cp ={}
	for _,v in ipairs(arr) do
		cp[#cp+1]=v
	end
	return cp
end
local function _IsHaveEle(arr,ele)
	for _,v in ipairs(arr) do
		if v==ele then return true end
	end
	return false
end
local function isCardValue(nCard)
	local nPoint = nCard % 16
	local nHuaSe = bit.rshift(nCard, 4) 
	return ((nPoint>=1 and nPoint<=13) and (nHuaSe>=1 and nHuaSe<=4))
end
local function _removeItem( list,item,isRemoveAll)
    local rmCount = 0
    for i = 1,#list do
        if list[i - rmCount] == item then
            table.remove(list,i - rmCount)
			if not isRemoveAll then
				return 1
			end
            rmCount = rmCount + 1
        end
    end
	return rmCount
end
local function _PoolPosMerge(arrPosFormA,arrPosFormB)
	local tTem={}
	for _,nPos in ipairs(arrPosFormA) do
		tTem[nPos]=true
	end
	for _,nPos in ipairs(arrPosFormB) do
		tTem[nPos]=true
	end
	local arr ={}
	for nPos ,_ in pairs(tTem) do
		table.insert(arr,nPos)
	end
	return arr
end
local function _PoolFormMerge(tUserIdToPoolFormA,tUserIdToPoolFormB)
	local tNew ={}
	for nUserId,nPoolForm in pairs(tUserIdToPoolFormA) do
		tNew[nUserId] =nPoolForm
	end
	for nUserId,nPoolForm in pairs(tUserIdToPoolFormB) do
		tNew[nUserId] =tNew[nUserId] or 0
		tNew[nUserId] =tNew[nUserId] +nPoolForm
	end
	return tNew
end

--判断两个整数数组是否相等
local function _isNumArrEqual(arrA,arrB)
	if #arrA ~=#arrB then
		return false
	end
	local tem={}
	for _,v in ipairs(arrA) do
		tem[v]=true
	end
	for _,v in ipairs(arrB) do
		if not tem[v] then
			return false
		end
	end
	return true
end

local function Reverse(arr)
	local arrTem={}
	for i=#arr,1,-1 do
		table.insert(arrTem,arr[i])
	end
	return arrTem
end

local function _IsCardsValue(arrCard,n,tTem)
	if #arrCard~=n then
		return false
	end
	for _,c in ipairs(arrCard) do
		if (not isCardValue(c)) or tTem[c] then
			return false
		else
			tTem[c]=true
		end
	end
	return true
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


local Table = {}


--use
function Table:New(sTableId,tInterFace,tConfig)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	assert(tConfig~=nil)

	t.sTableId=sTableId or ""					--table id
	
	t.tInterFace=tInterFace     				--Game层接口 (Game =>table =>user)	
	
	t.sTableName=tConfig.sTableName
	t.nGroupId =tConfig.nGroupId
	t.nRoomId=tConfig.nRoomId
	t.nSmallBlind=tConfig.nSmallBlind 			--小盲注数额
	t.nBigBlind=tConfig.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	t.nZhuaTou=tConfig.nZhuaTou or tConfig.nBigBlind*2			--抓头数额
	t.nEnterMin =tConfig.nBigBlind     			--最小进入(玩家必须满足最小进入才能开始游戏)
	t.nBuyMin =tConfig.nBuyMin	 				--最小买入
	t.nBuyMax =tConfig.nBuyMax					--最大买入
	t.nCapacity =tConfig.nCapacity				--能供玩游戏的座位数
	t.nFee =tConfig.nFee						--手续费
	t.nTax =tConfig.nTax						--抽水 (百分比)
	t.nLiveUserID =tConfig.nLiveUserID			--主播ID
	t.nTableType =tConfig.nTableType			--桌子类型
	t.isPassWordRoom =tConfig.isPassWordRoom	--是否为密码房
	t.nIntervalLev =tConfig.nIntervalLev or 2	--牌局间隔 1:短暂 2:适中 3:漫长
	t.sLiveID =tConfig.sLiveID
	t.nElapseMax =tConfig.nElapseMax			--多久没真人进入便关桌

	t.nClubId =tConfig.nClubId                 --俱乐部id (俱乐部房配置,否时为nil)
	t.nItemId=tConfig.nItemId or 1             --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	t.nKeepTime =tConfig.nKeepTime             --房间时长(秒) (俱乐部房配置,否时为nil)
	t.nGoldType =tConfig.nGoldType			   -- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)

	t.nOpentime =os.time()						--桌子创建时间戳
	--主播可选的房间配置
	local arrConfig ={}
	for dex,arrNum in ipairs(tConfig.arrConfigOption or {}) do
		local item ={}
		item.nConfigId=dex				--配置id
		item.nSmallBlind=arrNum[1]		--小盲
		item.nBigBlind=arrNum[2]		--大盲
		item.nZhuaTou=arrNum[3] or arrNum[2]*2	--抓头
		item.nTakeInMin=arrNum[3]		--最低带入
		item.nTakeInMax=arrNum[4]		--最高带入
		table.insert(arrConfig,item)
	end
	local arrCapacity =tConfig.arrCapacityOption or {}	--可选的桌子座位数
	t.tDeZhouConfigOption ={arrCapacity=arrCapacity,arrConfig=arrConfig}

	--本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	t.isConfigNotSet =true					 	
	if t.nLiveUserID==nil or t.nLiveUserID<=0 or tConfig.isUseApiConfig then
		t.isConfigNotSet =false
	end

	t.arrPreSetCommCard={}			--预设置的公共牌
	t.arrPreSetCommCardEffect={}	--正在生效使用的预设置公共牌
	t.nOperateTime=15				--操作最大时间,单位:秒 (通常为10)
	t.nJuShu =0						--当前局数
	t.nBankerPos=nil				--庄家位置
	t.arrUsers ={}					--本桌子用户
	t.tUserIdToPos ={}
	t.Timer =tTimerAux:New()
	t.TimerForAndroid =tTimerAux:New()
	
	t.nCloseTableWhenOver =nil			--一局结束后关闭桌子的原因

	t.isTableClose =false				--桌子是否已经关闭(设为true后,桌子不再能发出消息)
	t.nUserCnt =0						--本桌子当前玩家数量(包括旁观)
	t.nUserCntOfReal=0					--本桌子当前真人玩家数量(包括旁观)
	t.nTimestampZeroRealUser=os.time()  --真人玩家数量减至0时记录的时间

	t.tPile =nil				--牌
	t.arrCommunityCards={}		--公共牌
	t.nStage =TableState.nInit	--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	t.nPotSum =0				--底池总额(已押筹码总额)
	t.arrPoolInfo={}			--底池,例如:{{arrPosForm={1,2},nPool=100},{arrPosForm={1},nPool=50}}

	t.arrPosPartIn	={}			--参与当前牌局的玩家座位号
	t.nTheRightsEndPos =nil		--操作权终止位置(一轮开始时为第一个获得操作权的玩家，接着谁提高了下注值便设置为谁的座位号)
	t.nTheHighestBet =0			--当前最高下注 (牌局中的玩家,除了弃牌和AllIn的玩家外,一轮结束时，所有人下注都会与该值持平)
	t.nLatelyIncreasesBet=0		--最近一次的nTheHighestBet增幅 (加注提升nTheHighestBet时,提升幅度需>= Max(1个大盲,最近提升幅度))

	t.isBanStandUpReq =false	--游戏中有一些间隙状态, 禁止玩家游戏中站起(现已不会设置为true)

	t.sPaiJuId =""				--牌局id
	t.isRobotBan =false			-- 是否禁止机器人进入
	--牌局详情(存放本局里结算了的玩家信息)
	t.tUsersInfo={}
	t.tDealCardInfo={}
	t.tBetInfo={}
	t.tWinUserInfo={}

	t.isToStartGame=false			--游戏是否即将开始(设置了定时器)
	t.nTimeStart =0					-- >0:时间戳(游戏开始) -1:进入了暂停 0:空闲

	t.nRobotBetSum =0				--当局当前机器人下注总额

	t.isControl =nil				--本局是否尽量控牌 (2或3控机器人赢,4控真人赢)
	t.nControlUserId=nil		    --被控玩家id

	t.tUserNameToIsUsed ={}			--本桌子玩家的昵称 (用以判断机器人昵称重复)

	t.ToStartTime =3				--开局倒计时时间  秒
	t.ToSettleEndTime=8.5           --结算动画时间  秒
	
	t.isPause =false				--是否设置了暂停 true:是  false:否
	t.isUseHardAi =false			--是否使用强AI (强机器人能预知输赢)

	t.isGapOfNow =false				--当前是否正在流程跳转(调用了定时器，即将跳到下一流程)

	t.nLastHeartTickTime=os.time()	--游戏开始后，会不时更新该时间 (用来辅助检测是否卡桌了)

	t.isTableError=false			--桌子是否检查到出错了

	t.tUserIdToGoldFlowInfo={}		--记录结算过程中的金币流向(写战绩用)
	t.arrWinLoseRecord ={}			--缓存战绩记录，用于延迟写

	t.tReview =Review:New()			--回顾记录

	t.tStatistic =Statistic:New()	--数据统计

	t.nRealCountForBanRobot=2		--真人数量达到多少时，禁止机器人进入

	t.nUserIdLeader=nil				--ai场景信息的一个辅助变量
	t.arrPreSetCommCardCp={}		--公共牌(服务于ai场景)
	t.tOpHistory={}					--玩家各阶段的操作次数(服务于ai场景)
	t.nFirstBet=0					--本局大小盲累计下注总额(服务于ai场景)
	t.sAiUrl=nil
	t.IsBackstageCtrl=false			--后台控牌标识
	t.isDelCrtlAfterRead=true		--这标志默认true. 用gm命令控制其变false用来测试

	t.isUseAi=true					--机器人是否接ai服
	t.tUserIdToIsRaise={}			--记录玩家本局是否有加注过
	return t
end

function Table:_UpdateAiUrl()
	self.sAiUrl =PublicRedis.GetAiUrl(self.nGroupId) 
end

function Table:_UpdateHeartTick()
	self.nLastHeartTickTime =os.time()
end
function Table:ClubId()
	return self.nClubId
end
function Table:TableType()
	return self.nTableType
end
function Table:RoomId()
	return self.nRoomId
end
function Table:GroupId()
	return self.nGroupId
end
function Table:TableId()
	return self.sTableId
end
function Table:BanRobot()
	self.isRobotBan =true
end

function Table:GetTableInfoForClub()
	local tTableInfo ={}
	tTableInfo.nGameId = Define.nGameId
	tTableInfo.sTableName = self.sTableName
	tTableInfo.nItemId = self.nItemId  			--使用的金币id
	tTableInfo.nOpentime = self.nOpentime		--开桌时间
	tTableInfo.nLiveUserID = self.nLiveUserID
	tTableInfo.nKeepTime = self.nKeepTime
	tTableInfo.nSmallBlind = self.nSmallBlind
	tTableInfo.nBigBlind = self.nBigBlind
	tTableInfo.nTakeInMin = self.nBuyMin
	tTableInfo.nTakeInMax = self.nBuyMax
	tTableInfo.nIntervalLev = self.nIntervalLev
	tTableInfo.nCapacity = self.nCapacity
	tTableInfo.nGoldType = self.nGoldType
	tTableInfo.nZhuaTou = self.nZhuaTou
	return tTableInfo
end

function Table:_UpdateRoomCfg()
	if not self:MatchRoomId() then
		return
	end
	local tRoomConfig =tGameConfig.GetRoomConfig_v2(Define.nGameId,self.nRoomId,self.nGroupId)
	local tRlt,sError=PublicDefine.CheckRoomConfig(tRoomConfig)
	if not tRlt then
		self:Print("_UpdateRoomCfg,CheckRoomConfig fail:%s",sError)
		return
	 end
	if self.nSmallBlind==tRlt.nSmallBlind and self.nBuyMin==tRlt.nBuyMin and self.nTax ==tRlt.nTax then
		self:Print("_UpdateRoomCfg,NoChange")
		return
	end
	self.nSmallBlind=tRlt.nSmallBlind 			--小盲注数额
	self.nBigBlind=tRlt.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou=tRlt.nZhuaTou or tRlt.nBigBlind*2			--抓头数额
	self.nEnterMin =tRlt.nBigBlind     			--最小进入(玩家必须满足最小进入才能开始游戏)
	self.nBuyMin =tRlt.nBuyMin	 				--最小买入
	self.nBuyMax =tRlt.nBuyMax					--最大买入
	self.nTax =tRlt.nTax						--抽水 (百分比)
	self:Print("_UpdateRoomCfg ChangeTo nSmallBlind:%d nBuyMin:%d nTax:%d",self.nSmallBlind,self.nBuyMin,self.nTax)
	--广播给从服
	self:_BroadCastToSlaves("DeZhouRoomCfgChange",tRlt)
end


--是否使用积分结算
function Table:IsUseCredit()
	if self:MatchRoomId() ==0 then	--匹配模式的试玩房
		return true
	end
	if self.nGoldType ==3 then		--俱乐部房指定使用积分结算
		return true
	end
	return false
end

function Table:Get_User_UnLockGold(tUser)
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid then
			return self.nBuyMax
		end
		return tPubUser.Get_User_UnLockGold(tUser.nUserId,self.nItemId)
	end
	return (tUser.nGold -tUser.nLockGoldInTable)
end

function Table:Gold_Lock(tUser,nGoldToLock)
	local nUserId =tUser.nUserId
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUser.Gold_Lock(nUserId,nGoldToLock,self.nItemId) then
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
	local nUserId =tUser.nUserId
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid  then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable +nChange
			return true,nChange
		end
		local isSucc,_,nAcChange =tPubUser.Gold_ChangeAndReLock(nUserId,tUser.nLockGoldInTable,nChange,nSourceType,nRoomId,self.nItemId)
		if isSucc then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable +(nAcChange or nChange)
			return true,(nAcChange or nChange)
		end
		return false
	end
	tUser.nGold =tUser.nGold +nChange
	tUser.nLockGoldInTable =tUser.nLockGoldInTable +nChange
	return true,nChange
end

function Table:Gold_UnLockAll(tUser)
	if Equal(tUser.nLockGoldInTable,0) then 
		return true
	end
	local nUserId =tUser.nUserId
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUser.Gold_UnLock(nUserId,tUser.nLockGoldInTable,self.nItemId) then
			tUser.nLockGoldInTable =0
			return true
		end
		return false
	end
	tUser.nLockGoldInTable =0
	return true
end

--匹配房场次id. 非匹配房返回nil
function Table:MatchRoomId()
	if self.nTableType ==Define.TableType.nMatch then
		return self.nRoomId 
	end
end

--间隔时间更新
function Table:_UpdateIntervalTime()
	local ToStartTime,ToSettleEndTime =tPublicRedis.GetDeZhouIntervalTime(self.nGroupId,self.nIntervalLev)
	self:Print("_UpdateIntervalTime nGroupId:%d nIntervalLev:%d ToStartTime:%.1f ToSettleEndTime:%.1f",self.nGroupId,self.nIntervalLev,ToStartTime,ToSettleEndTime)
	if ToStartTime>=1 and ToSettleEndTime>=1 then
		self.ToStartTime =ToStartTime				
		self.ToSettleEndTime =ToSettleEndTime           
	elseif self.nIntervalLev ==1 then
		self.ToStartTime =1				--开局倒计时时间  秒
		self.ToSettleEndTime=5           --结算动画时间  秒
	elseif self.nIntervalLev ==2 then
		self.ToStartTime =3				--开局倒计时时间  秒
		self.ToSettleEndTime=7           --结算动画时间  秒
	elseif self.nIntervalLev ==3 then
		self.ToStartTime =6				--开局倒计时时间  秒
		self.ToSettleEndTime=7           --结算动画时间  秒
	else
		self.ToStartTime =3				--开局倒计时时间  秒
		self.ToSettleEndTime=7          --结算动画时间  秒
	end
	self:Print("nToStartTime is:%.1f nToSettleEndTime is:%.1f",self.ToStartTime,self.ToSettleEndTime)
end


function Table:GetBigBlind()
	return self.nBigBlind
end
function Table:GetZhuaTou()
	return self.nZhuaTou
end
function Table:GetPlayerCnt()
	local nCnt =0
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.nStatus ~=UserStatus.nFold then
			nCnt =nCnt+1
		end
	end
	return nCnt
end

--初始化机器人强度
function Table:InitAiGrade()
	if self.isControl ==2 or self.isControl ==3 then
		self.isUseHardAi =true
		return self.isUseHardAi
	end
	local tWaterInfo= Define.AssertWaterInfoExist(self.nBigBlind)
	local nCurSysWinRate =(tWaterInfo.nSysSumIn /tWaterInfo.nSysSumOut)
	if nCurSysWinRate< 1 then
		self.isUseHardAi =true
		return self.isUseHardAi
	end
	if nCurSysWinRate < Define.nSysWinRate and math.random(1,100) <70 then
		self.isUseHardAi =true
		return self.isUseHardAi
	end
	self.isUseHardAi =false
	return self.isUseHardAi
end

--机器人根据该返回决定是否使用预知输赢模式来进行游戏
function Table:IsPoolEnough()
	if self.isUseHardAi then
		return false
	end
	return true
end

function Table:RealUserProfit(nProfix)
	local tWaterInfo= Define.AssertWaterInfoExist(self.nBigBlind)
	local nAbs =math.abs(nProfix)
	if nProfix <0 then
		tWaterInfo.nSysSumIn =tWaterInfo.nSysSumIn +nAbs     --系统累计流入(系统赢,正数)
	else
		tWaterInfo.nSysSumOut =tWaterInfo.nSysSumOut +nAbs   --系统累计流出(系统输,正数)
	end
end

--来自从服的请求处理
function Table:OnSlaveMsgHandle(sReturnKey,sCmd,tJsonData,nEcho)
	self:Print("OnSlaveMsgHandle sCmd:%s",sCmd)

	--操作请求 xx
	if sCmd =="DeZhouOpReq" then
		self:DeZhouOpReq(tJsonData,sReturnKey)
		return
	end
	--预操作请求 xx
	if sCmd =="DeZhouPreOpReq" then
		self:DeZhouPreOpReq(tJsonData,sReturnKey)
		return
	end
	--坐下请求(坐下到玩家位置)xx
	if sCmd =="DeZhouSitDownReq" then
		self:DeZhouSitDownReq(tJsonData,sReturnKey)
		return
	end
	--站起请求xx
	if sCmd =="DeZhouStanpUpReq" then
		self:DeZhouStanpUpReq(tJsonData,sReturnKey)
		return
	end
	--用户离线通知
	if sCmd =="UserOffLine" then
		self:UserOffLine(tJsonData,sReturnKey)
		return
	end
	--用户上线通知
	if sCmd =="UserOnLine" then
		self:UserOnLine(tJsonData,sReturnKey)
		return
	end
	--取消托管请求
	if sCmd =="DeZhouCancelAutoReq" then
		self:DeZhouCancelAutoReq(tJsonData,sReturnKey)
		return
	end
	--表情聊天
	if sCmd =="DeZhouChatReq" then
		self:_DeZhouChatReq(tJsonData,sReturnKey)
		return
	end
	--房间设置 请求
	if sCmd =="DeZhouCofingReq" then
		self:DeZhouCofingReq(tJsonData,sReturnKey)
		return
	end
	--Gm命令
	if sCmd =="DeZhouGmReq" then
		self:DeZhouGmReq(tJsonData,sReturnKey)
		return
	end
	--主播暂停请求
	if sCmd =="DeZhouPauseReq" then
		self:DeZhouPauseReq(tJsonData,sReturnKey)
		return
	end
	--主播踢人请求
	if sCmd =="DeZhouKickUserReq" then
		self:DeZhouKickUserReq(tJsonData,sReturnKey)
		return
	end
	--筹码买入请求
	if sCmd =="DeZhoTakeInReq" then
		self:DeZhoTakeInReq(tJsonData,sReturnKey)
		return
	end
	--后台踢人
	if strReq =="REQ_Kick_User" then
		self:REQ_Kick_User(tJsonData,sReturnKey)
		return
	end
	--从服人数汇报
	if strReq =="UserCnt_Report" then
		self:UserCnt_Report(tJsonData)
		return
	end

end


--use 用户请求处理 (当前机器人会用,需优化)
function Table:OnReqHandle(nUserId,strReq,tData,sReturnKey)
	local nSitId, tUser=self:_GetSitIdByUserId(nUserId)
	if nSitId==nil then
		self:Print("Error, Can Not Find User_%d in Table",nUserId)
		return
	end
	
	tData.nUserId=nUserId
	self:OnSlaveMsgHandle(nil,strReq,tData,-2)
end

--用户下线通知(来自从服)
function Table:UserOffLine(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		return
	end
	if not self:_IsPartInUser(nSitId) then
		self:_SetLeaveSeat(nSitId)
		return
	end
	tUser.nOffLineCnt =tUser.nOffLineCnt +1
	self:Print("User_%d OffLineCnt Became:%d",nUserId,tUser.nOffLineCnt)
end
--用户重新上线通知(来自从服)
function Table:UserOnLine(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		return
	end
	tUser.nOffLineCnt =tUser.nOffLineCnt -1
	self:Print("User_%d OffLineCnt Became:%d",nUserId,tUser.nOffLineCnt)
end

--表情聊天请求(来自从服)---
function Table:_DeZhouChatReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	self:Print("_DeZhouChatReq,nSitId:%d nChatId:%d nTarget:%s",nSitId,tData.nChatId,tostring(tData.nTarget))
	if not nSitId then
		self:Print("Chat Fail,Not Player Pos")
		return
	end
	if self:_IsPlayerPos(tData.nTarget or 0) then
		if not self:_GetUser(tData.nTarget) then
			self:Print("Chat Fail,nTarget Pos User is Nil")
			return
		end
	end
	self:_BroadCastDeZhouChatNotify(nSitId,tData.nChatId,tData.nTarget)
end

--主播暂停请求,分游戏中请求暂停，非游戏中请求暂停 (来自从服) ---
function Table:DeZhouPauseReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	self:Print("DeZhouPauseReq nUserId:%d isPause:%s",nUserId,tostring(tData.isPause))
	if nUserId ~=self.nLiveUserID then
		self:Print("DeZhouPauseReq Fail,nLiveUserID is:%s",tostring(self.nLiveUserID))
		return
	end
	if self.isPause ==tData.isPause then
		self:Print("DeZhouPauseReq Fail,status is same:%s",tostring(tData.isPause))
		return
	end
	self.isPause =tData.isPause
	self:_SendToSlave(sReturnKey,"DeZhouPauseRsp",{isPause =self.isPause,nUserId=nUserId})
	if self.isPause then
		self:_Pause()
	else
		self:_PauseCancel()
	end
end


--取消托管请求(来自从服)
function Table:DeZhouCancelAutoReq(tData,sReturnKey)
	local nSitId,tUser =self:_GetSitIdByUserId(tData.nUserId)
	self:Print("DeZhouCancelAutoReq nSitId:%d",nSitId)
	assert(tUser~=nil)
	self:_CancelAuto(tUser)
end

--筹码买入请求(来自从服)
function Table:DeZhoTakeInReq(tData,sReturnKey)
	local nSitId,tUser =self:_GetSitIdByUserId(tData.nUserId)
	assert(tData.nBuyTo ~=nil)
	self:Print("DeZhoTakeInReq nUserId:%d,nBuyTo:%.2f",tData.nUserId,tData.nBuyTo)
	if not nSitId then
		self:Print("DeZhoTakeInReq Fail,can not find user")
		return
	end
	if not (GreaterOrEqual(tData.nBuyTo,self.nBuyMin) and LessOrEqual(tData.nBuyTo,self.nBuyMax)) then
		self:Print("DeZhoTakeInReq Fail,Out of Range")
		return 
	end
	local nMax =self:Get_User_UnLockGold(tUser) + tUser.nBalance
	if GreaterThan(tData.nBuyTo, nMax) then
		self:Print("DeZhoTakeInReq Fail,Gold Not Enough,nMax:%.2f,nBalance:%.2f",nMax,tUser.nBalance)
		return 
	end
	tUser.nBuyTo=tData.nBuyTo 						
	tUser.nIsAutoBuy=tData.nIsAutoBuy
end

--从服人数汇报(来自从服)---
function Table:UserCnt_Report(tData)
	if tData.isHaveUser then
		self.nTimestampZeroRealUser=os.time()		--过久不刷新该时间值,便视为过久没真人玩家进入
	end
end

--主播踢人请求(来自从服)---
function Table:DeZhouKickUserReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local nPos =tData.nPos

	self:Print("DeZhouKickUserReq nUserId:%d nTargetPos:%d",nUserId,nPos)
	if nUserId ~=self.nLiveUserID then
		self:Print("DeZhouKickUserReq Fail,nLiveUserID is:%s",tostring(self.nLiveUserID))
		self:_SendToSlave(sReturnKey,"DeZhouKickUserRsp",{nRlt =10,nUserId=nUserId})
		return
	end
	if not self:_IsPlayerPos(nPos) then
		self:Print("DeZhouKickUserReq Fail ,nTargetPos illeagel, nTargetPos:%d",nPos)
		self:_SendToSlave(sReturnKey,"DeZhouKickUserRsp",{nRlt =11,nUserId=nUserId})
		return
	end
	local tTargetUser =self:_GetUser(nPos)
	if tTargetUser==nil then
		self:Print("DeZhouKickUserReq Fail,tTargetUser is nil")
		self:_SendToSlave(sReturnKey,"DeZhouKickUserRsp",{nRlt =12,nUserId=nUserId})
		return
	end
	if not self:_IsPartInUser(nPos) then
		self:_SendToSlave(sReturnKey,"DeZhouKickUserRsp",{nRlt =0,nUserId=nUserId})
		self:_ForceStandUp(nPos,20)
		return
	end
	self:_SendToSlave(sReturnKey,"DeZhouKickUserRsp",{nRlt =1,nUserId=nUserId})
	tTargetUser.isKickWhenEnd =true --当局结束后踢出(站起)
end
--Gm命令请求(来自从服)
function Table:DeZhouGmReq(tData,sReturnKey)
	local nSitId,tUser =self:_GetSitIdByUserId(tData.nUserId)
	self:Print("DeZhouGmReq:%s",tData.sStr)
	if tData.sStr=="close" then
		self:SetClose(TableCloseReason.nGmClose)
		return
	end
	if tData.sStr=="pause" then
		local isPause =(not self.isPause)
		self:DeZhouPauseReq({nUserId=self.nLiveUserID,isPause=isPause})
		return
	end
	if tData.sStr=="delCtrl_true" then
		self.isDelCrtlAfterRead=true
		return 
	end
	if tData.sStr=="delCtrl_false" then
		self.isDelCrtlAfterRead=false
		return 
	end

	if tData.sStr=="Config" then
		self.isConfigNotSet=false
	end
	local isSuccee,tRlt =pcall(cjson.decode,tData.sStr)
	if not isSuccee then
		self:Print("Json decode Fail")
		return
	end
	local arrPreSetHoleCard =tRlt[1] or {}
	local arrPreSetCommCard =tRlt[2] or {}

	local tCardToCnt ={}
	local arrHoleCard ={}
	local arrCommCard ={}
	--检查参数合法性
	for _,nCard in ipairs(arrPreSetHoleCard) do
		if tCardToCnt[nCard]==nil and isCardValue(nCard) and #arrHoleCard<2 then
			table.insert(arrHoleCard,nCard)
			tCardToCnt[nCard]= true
		end
	end
	for _,nCard in ipairs(arrPreSetCommCard) do
		if tCardToCnt[nCard]==nil and isCardValue(nCard) and #arrCommCard<5 then
			table.insert(arrCommCard,nCard)
			tCardToCnt[nCard]= true
		end
	end
	--预设置玩家底牌与公共牌
	if tUser then
		tUser.arrPreSetHoleCard =arrHoleCard
	end
	self.arrPreSetCommCard =arrCommCard
end

--主播选择房间配置请求(来自从服)
function Table:DeZhouCofingReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	self:Print("DeZhouCofingReq,nUserId:%d nCapacity:%d nConfigId:%d nIntervalLev:%s",
	nUserId,tData.nCapacity,tData.nConfigId,tostring(tData.nIntervalLev))

	if nUserId ~= self.nLiveUserID then
		self:Print("NotLiveUserId")
		return
	end
	if not self.isConfigNotSet then
		if not (self.nStage ==TableState.nInit and self.isPause) then
			self:Print("Not Pause Stage")
			return
		end
	end
	local isCapcityLegal =_IsHaveEle(self.tDeZhouConfigOption.arrCapacity,tData.nCapacity)
	local isConfigIdLegal,tConfigItem =false,nil
	for _,v in ipairs(self.tDeZhouConfigOption.arrConfig) do
		if v.nConfigId==tData.nConfigId then
			isConfigIdLegal,tConfigItem =true,v
			break
		end
	end
	if isCapcityLegal==false or isConfigIdLegal==false then
		self:Print("Config Not Legal")
		return
	end
	--座位数减少时可能需要踢出一些玩家
	if (not self.isConfigNotSet) and tData.nCapacity<self.nCapacity then
		for i=tData.nCapacity+1,self.nCapacity do
			if self:_GetUser(i) then
				self:_ForceStandUp(i,14)
			end
		end
	end
	local isChange =								--配置是否发生了变化
		(self.isConfigNotSet or
		self.nSmallBlind~=tConfigItem.nSmallBlind or
		self.nBigBlind~=tConfigItem.nBigBlind or
		self.nBuyMin ~=tConfigItem.nTakeInMin or
		self.nBuyMax ~=tConfigItem.nTakeInMax or
		self.nCapacity ~=tData.nCapacity or
		self.nIntervalLev ~=tData.nIntervalLev or
		self.nZhuaTou ~= tConfigItem.nZhuaTou)

	self.nSmallBlind=tConfigItem.nSmallBlind 			--小盲注数额
	self.nBigBlind=tConfigItem.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou=tConfigItem.nZhuaTou or tConfigItem.nBigBlind*2			--抓头数额
	self.nBuyMin =tConfigItem.nTakeInMin	 			--最小买入
	self.nBuyMax =tConfigItem.nTakeInMax				--最大买入
	self.nEnterMin =self.nBigBlind     					--最小进入(玩家必须满足最小进入才能开始游戏)
	self.nCapacity =tData.nCapacity						--能供玩游戏的座位数
	self.isConfigNotSet=false
	self.nIntervalLev =tData.nIntervalLev				--牌局间隔 1:短暂 2:适中 3:漫长
	if self.nIntervalLev ~=1 and self.nIntervalLev ~=2 and self.nIntervalLev ~=3 then
		self:Print("Config nIntervalLev Error")
		self.nIntervalLev =2
	end
	--记忆玩家最近使用的设置
	local tDataToSave ={nCapacity=tData.nCapacity,nConfigId=tData.nConfigId,nIntervalLev=tData.nIntervalLev}
	tPublicRedis.SetGameRecommendInfo(Define.nGameId,nUserId,tDataToSave)

	self:_UpdateIntervalTime()

	if not isChange then								--配置没反生改变则返回
		return
	end
	self:Print("Config Change")
	--广播配置变化
	self:_BroadCastDeZhouConfigNotify(tConfigItem)

	--重新调整玩家筹码余额
	local function _ReAdjustmentBalance(tSeatUser)		--调整玩家可用筹码余额()
		local nBestTakeIn =0
		if tSeatUser.nBalance>self.nBuyMax then
			 nBestTakeIn =self.nBuyMax 
		end
		self:_UserBalanceToGold(tSeatUser)				--先解锁所有金币,再进行重新锁定
		if self:_InitUserTakeIn(tSeatUser,nBestTakeIn) then
			tSeatUser.nBalance =tSeatUser.nLockGoldInTable
			return true
		end
		return false
	end
	for nPos,tUser in pairs(self.arrUsers) do
		if tUser.nBalance<self.nBuyMin or tUser.nBalance>self.nBuyMax  then
			if _ReAdjustmentBalance(tUser) then
				self:Print("reset user balance to :%.2f,nPos_%d",tUser.nBalance,nPos)
				self:_BroadCastDeZhouBalanceNotify(nPos,tUser.nBalance)	--广播该玩家余额改变
			else
				self:_ForceStandUp(nPos,-1)
			end
		end
	end

	--俱乐部桌信息改变通知
	if self.nClubId then
		local tTableInfo ={}
		tTableInfo.nSmallBlind =self.nSmallBlind
		tTableInfo.nBigBlind =self.nBigBlind
		tTableInfo.nZhuaTou =self.nZhuaTou
		tTableInfo.nTakeInMin =self.nBuyMin
		tTableInfo.nTakeInMax =self.nBuyMax
		tTableInfo.nIntervalLev =self.nIntervalLev
		tTableInfo.nNowCnt =self.nUserCnt
		tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,tTableInfo)
	end
	return 
end

--操作请求(来自从服)
function Table:DeZhouOpReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("DeZhouOpReq can not find user_%d in player seat",nUserId)
		return
	end
	self:_CancelAuto(tUser)		--取消托管
	tUser.isHaveOp =true		--当局是否有操作

	local nOpButton =tData.nOpButton 		--1:"按钮1" 2:"按钮2" 3:"按钮3"
	local nRaise =tData.nRaise or 0		 	--nOpButton为3且有加注权时有效. >0:表示具体的加注值, <0:可快速操作的选项(见操作权信息定义)
	self:Print("DeZhouOpReq,nSitId:%d nOpButton:%.2f nRaise:%.3f",nSitId,nOpButton,nRaise)
	nRaise =publicApi.Floor_2(nRaise)

	if self.nStage ~=TableState.nPlaying then
		self:Print("Fail,Not Playing")
		return
	end
	if tUser.nStatus ~=UserStatus.nThinking then
		self:Print("Fail,Not nThinking")
		return
	end
	local tOperation =tUser.tOperation
	if tOperation==nil then
		self:Print("Fail,tOperation is nil")
		return
	end
	assert(tOperation ~=nil)
	if nOpButton ==3 and tOperation.nOpC ==UserOp.nRaiseBan then
		self:Print("Fail,nRaiseBan")
		return
	end
	local nOp =nil
	local nCallValue =0	--跟注值

	if nOpButton ==1 then
		nOp =tOperation.nOpA
	elseif nOpButton==2 then
		nOp =tOperation.nOpB
	elseif nOpButton ==3 then
		nOp =tOperation.nOpC
	else
		self:Print("Fail,nOpButton Not Define")
		return
	end
	if GreaterThan(nOp,0) then
		nCallValue =nOp
		nOp =UserOp.nCall
	end
	--弃牌
	if nOp ==UserOp.nFold then
		self:DoOpForUser(nSitId,UserOp.nFold,nil)
		return
	end
	--AllIn
	if nOp ==UserOp.nAllIn then
		self:DoOpForUser(nSitId,UserOp.nAllIn,nil)
		return
	end
	--看牌(过)
	if nOp ==UserOp.nPass then
		self:DoOpForUser(nSitId,UserOp.nPass,nil)
		return
	end
	--跟注
	if nOp ==UserOp.nCall then
		self:DoOpForUser(nSitId,UserOp.nCall,nCallValue)
		return
	end
	--加注
	if nOp ==UserOp.nRaise then
		assert(tOperation.tRaiseChoice ~=nil)
		if LessThan(nRaise,0) then
			if not _IsHaveEle(tOperation.tRaiseChoice.arrQuickRaise,nRaise) then
				self:Print("Fail,Quick nRaise option Not Support")
				return
			end
			nRaise =self:_QuickOptionToBetValue(nRaise,tUser.nBalance)
			self:Print("Turn QuickOption ToBetValue:%.2f",nRaise)
		end
		if GreaterOrEqual(nRaise,0) and not (GreaterOrEqual(nRaise,tOperation.tRaiseChoice.nMin) and LessOrEqual(nRaise,tOperation.tRaiseChoice.nMax)) then
			self:Print("Fail,nRaise Out of range,[%.2f,%.2f]",tOperation.tRaiseChoice.nMin,tOperation.tRaiseChoice.nMax)
			return
		end
		assert(LessOrEqual(nRaise ,tUser.nBalance))
		if Equal( nRaise,tUser.nBalance) then
			self:DoOpForUser(nSitId,UserOp.nAllIn,nil)
		else
			self:Print("nRaise:%.2f",nRaise)
			self:DoOpForUser(nSitId,UserOp.nRaise,nRaise)
		end
	end
end	

--预操作请求(来自从服)
--20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx -23:结束后亮牌 -24:亮牌
function Table:DeZhouPreOpReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("DeZhouPreOpReq can not find user_%d in player seat",nUserId)
		return
	end
	self:Print("DeZhouPreOpReq nOpId:%.2f isOn:%s",tData.nOpId,tostring(tData.isOn))

	tUser.isHaveOp =true		--当局是否有操作
	if tData.nOpId == -24 then	--亮牌操作
		self:_SendToSlave(sReturnKey,"DeZhouPreOpRsp",{nUserId=nUserId,nRlt=0,nOpId=tData.nOpId,isOn=tData.isOn,sErr="succee"})
		if not (self.nStage ==TableState.nSettle and not tUser.isShowCardWhenEnd) then
			return
		end
		tUser.isShowCardWhenEnd =true
		for _,v in ipairs(self.tDealCardInfo or {}) do
			if v.nSitId==nSitId then v.isShowCardWhenEnd=true end
		end
		self:_BroadCastShowCardNotify(nSitId)
		return
	end

	--合法性检查
	if not tUser.tPreOpOption then
		self:Print("DeZhouPreOpReq fail,tPreOpOption is nil")
		return
	end
	--更新玩家当前操作的选项状态
	local tOption=nil										
	for _,item in ipairs(tUser.tPreOpOption.arrOption) do 	
		if Equal( item.nOpId,tData.nOpId) or (GreaterThan(item.nOpId,0) and GreaterThan(tData.nOpId,0)) then -- >0:跟xxx
			tOption=item
			break
		end
	end
	if not tOption then
		self:Print("DeZhouPreOpReq fail,can not find option")
		return
	end
	tOption.isOn =tData.isOn

	--确保同时只能有一个预操作选项状态为true
	if tOption.isOn then
		for _,item in ipairs(tUser.tPreOpOption.arrOption) do
			if not Equal(item.nOpId,tOption.nOpId) then
				item.isOn =false
			end
		end
	end
	--是否结束后亮牌
	if tOption.nOpId ==-23 then		
		tUser.isShowCardWhenEnd =tOption.isOn
	end

	self:Print("DeZhouPreOpReq succee")
	local DeZhouPreOpRsp ={}
	DeZhouPreOpRsp.nUserId=nUserId
	DeZhouPreOpRsp.nRlt =0				--0:成功 其它:错误码
	DeZhouPreOpRsp.nOpId =tOption.nOpId	--(成功时有效)请求的操作
	DeZhouPreOpRsp.isOn =tOption.isOn	--(成功时有效)操作状态 true:选中成功 false:取消成功
	DeZhouPreOpRsp.sErr="succee"		--(失败时有)失败提示
	self:_SendToSlave(sReturnKey,"DeZhouPreOpRsp",DeZhouPreOpRsp)
end	

--站起请求(来自从服)
function Table:DeZhouStanpUpReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		self:SendFailNotifyV2(sReturnKey,nUserId,16,"not in Player seat")
		return
	end
	self:Print("DeZhouStanpUpReq,nSitId:%d",nSitId)
	self:_SetLeaveSeat(nSitId)
end	

--坐下请求(来自从服)
function Table:DeZhouSitDownReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local tUserInfo =tData.tUserInfo
	self:Print("DeZhouSitDownReq,nPos:%d nUserId:%d",tData.nPos,nUserId)
	
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if nSitId then
		self:Print("already in Player seat")
		self:SendFailNotifyV2(sReturnKey,nUserId,15,"already in Player seat")
		return
	end
	if self.isConfigNotSet then
		self:Print("table ConfigNotSet")
		self:SendFailNotifyV2(sReturnKey,nUserId,19,"table no config")
		return
	end

	local nPosForPlay =nil
	if tData.nPos==0 then
		nPosForPlay =self:_FindAPosForPlay()
	elseif self:_IsPlayerPos(tData.nPos) and self:_GetUser(tData.nPos)==nil then
		nPosForPlay =tData.nPos
	else
		self:Print("nPos illegal")
		self:SendFailNotifyV2(sReturnKey,nUserId,14,"nPos illegal")
		return
	end
	if nPosForPlay==nil then
		self:Print("_FindAPosForPlay Fail")
		self:SendFailNotifyV2(sReturnKey,nUserId,14,"_FindAPosForPlay Fail")
		return
	end

	local tSeatUser,nSitId,nCode= self:OnUserEnter(tUserInfo,nPosForPlay)
	if not tSeatUser then
		self:SendFailNotifyV2(sReturnKey,nUserId,nCode,"Enter Fail")
		return
	end
end	

--后台预设置牌控制
--arrCommunityCard:[1,2,3,4,5],      --公共牌
--arrUserHoleCard:[{nUserId:10086,arrHoleCards:[3,4]},{nUserId:10086,arrHoleCards:[3,4]}], --各个玩家的手牌
function Table:_BackStagePreSetCtrl(arrUserPartIn)
	local sPreSetInfo =tPublicRedis.GetPreSetInfo(self.sTableId,self.isDelCrtlAfterRead)
	local tPreSetInfo =nil
	if sPreSetInfo and #sPreSetInfo>0 then
		local isSuccee,tRlt =pcall(cjson.decode,sPreSetInfo)
		if isSuccee then
			tPreSetInfo =tRlt
		else
			self:Print("BackStageCtrl Error2,decode fail!")
		end
	end
	self:Print("BackStageCtrl sPreSetInfo:%s",tostring(sPreSetInfo))
	if tPreSetInfo==nil then
		return false
	end
	local arrCommunityCard =tPreSetInfo.arrCommunityCard or {}
	local arrUserHoleCard =tPreSetInfo.arrUserHoleCard or {}

	--检查公共牌设置合法性
	local tTem={}
	if not _IsCardsValue(arrCommunityCard,5,tTem) then
		self:Print("BackStageCtrl Error4,CardValue Error")		--公共牌数量不合法,或牌值不合法
		return false
	end
	--检查手牌设置合法性
	local arrSort ={}
	local tUserIdToHodeC={}
	for _,item in ipairs(arrUserHoleCard) do
		local nUserId =item.nUserId or 0
		local arrHoleCards=item.arrHoleCards or {}
		if not _IsCardsValue(arrHoleCards,2,tTem) then
			self:Print("BackStageCtrl Error5,CardValue Error")	--手牌数量不合法,或牌值不合法
			return false
		end
		local tCardType =tAlg.DeZhouCardType(arrHoleCards,arrCommunityCard)
		local t ={}
		t.nCardType =tCardType.nCardType
		t.nComValue =tCardType.nComValue
		t.nUserId =nUserId
		table.insert(arrSort,t)
		tUserIdToHodeC[nUserId] =arrHoleCards
	end
	tAlg.SortByCardType(arrSort)	--按牌型从大到小排序
	local tFirst =arrSort[1] or {}
	local nFirstUserId =tFirst.nUserId

	local tUserIdToUser ={}
	for _,tU in ipairs(arrUserPartIn) do
		tUserIdToUser[tU.nUserId]=tU
	end
	--最大牌玩家离开便不再控牌
	if not tUserIdToUser[nFirstUserId] then
		self:Print("BackStageCtrl,no FirstUser")
		return false
	end
	local tPile =tAlg.NewPile()

	--设置所使用的公共牌
	self.arrPreSetCommCard =tPile:GetCards(#arrCommunityCard,arrCommunityCard)

	--设置玩家所使用的手牌
	arrSort={}
	for _,tU in ipairs(arrUserPartIn) do
		local arrHoldePreSet =tUserIdToHodeC[tU.nUserId]
		if arrHoldePreSet then
			tU.arrPreSetHoleCard =tPile:GetCards(#arrHoldePreSet,arrHoldePreSet)
		else
			local arrH,sErr =tPile:GetLeSeV2(self.arrPreSetCommCard)	--给垃圾牌
			tU.arrPreSetHoleCard =arrH
			if sErr then
				self:Print("BackStageCtrl,ERR mayBe")
			end
		end
		assert(#tU.arrPreSetHoleCard==2)
		local tCardType =tAlg.DeZhouCardType(tU.arrPreSetHoleCard,self.arrPreSetCommCard)
		local t ={}
		t.nCardType =tCardType.nCardType
		t.nComValue =tCardType.nComValue
		t.nUserId =tU.nUserId
		table.insert(arrSort,t)
	end
	tAlg.SortByCardType(arrSort)	--按牌型从大到小排序
	for dex,v in ipairs(arrSort) do
		local tUser =tUserIdToUser[v.nUserId]
		tUser.nRank =dex
	end
	return true
end


--后台控牌. 有控则返回true
function Table:BackStageCtrl(arrUserPartIn)
	local arrCtrlUserId={}
	local sArrUsers =tPublicRedis.GetCrtlWinUsers(self.sTableId,self.isDelCrtlAfterRead)

	if self:_BackStagePreSetCtrl(arrUserPartIn) then
		return true
	end

	if sArrUsers and #sArrUsers>0 then
		local isSuccee,arrUserId =pcall(cjson.decode,sArrUsers)
		if isSuccee then
			arrCtrlUserId =arrUserId
		else
			self:Print("BackStageCtrl Error,decode fail!")
		end
	end
	self:Print("BackStageCtrl sArrUsers:%s",tostring(sArrUsers))

	local tUserIdToUser ={}
	for _,tU in ipairs(arrUserPartIn) do
		tUserIdToUser[tU.nUserId]=tU
	end
	local nFirstUserId =arrCtrlUserId[1] or 0
	if not tUserIdToUser[nFirstUserId] then		--第一位不在或没有，则不控
		self:Print("BackStageCtrl,no First User")
		return false
	end

	local arrUserWin ={}		--本牌局需要依次控赢的玩家
	for _,nCtrlUserId in ipairs(arrCtrlUserId) do
		local tU =tUserIdToUser[nCtrlUserId]
		if tU then
			table.insert(arrUserWin,tU)
			tUserIdToUser[nCtrlUserId] =nil
		end
	end
	local arrUserLose={}		--本牌局需要控输的玩家(拿垃圾牌)
	for _,tU in pairs(tUserIdToUser) do
		table.insert(arrUserLose,tU)
	end
	tAlg.random_array(arrUserLose)

	local arrPreSetCommCard ,arrUsersHoleCard =tAlg.PreSetCardsV2(#arrUserPartIn,#arrUserWin)
	self.arrPreSetCommCard =Reverse(arrPreSetCommCard) 
	assert(#arrPreSetCommCard ==5)
	assert(#arrUsersHoleCard ==#arrUserPartIn)

	local i=1
	for _,tUser in ipairs(arrUserWin) do
		local item =arrUsersHoleCard[i]
		tUser.arrPreSetHoleCard =item.arrHoleCard
		assert(#tUser.arrPreSetHoleCard ==2)
		tUser.nRank =item.nRank
		i=i+1
	end
	for _,tUser in ipairs(arrUserLose) do
		local item =arrUsersHoleCard[i]
		tUser.arrPreSetHoleCard =item.arrHoleCard
		assert(#tUser.arrPreSetHoleCard ==2)
		tUser.nRank =item.nRank
		i=i+1
	end
	--self:Print("BackStageCtrl,arrUserWin:%s arrUserLose:%s",table.concat(arrUserWin,","),table.concat(arrUserLose,","))
	return true
end

function Table:PreDealCard(arrUserPartIn)
	local arrPreSetCommCard ,arrUsersHoleCard =tAlg.PreSetCards(#arrUserPartIn)
	if self.arrPreSetCommCard ==nil or #self.arrPreSetCommCard ==0 then
		self.arrPreSetCommCard =arrPreSetCommCard
		assert(#arrPreSetCommCard ==5)
	end
	for _,tUser in ipairs(arrUserPartIn) do
		local item =table.remove(arrUsersHoleCard) or {}
		if tUser.arrPreSetHoleCard ==nil or #tUser.arrPreSetHoleCard==0 then
			tUser.arrPreSetHoleCard =item.arrHoleCard
			assert(#tUser.arrPreSetHoleCard ==2)
			tUser.nRank =item.nRank
		end
	end
end


function Table:StartGame()
	self.nJuShu =self.nJuShu +1
	self:Print("StartGame,nFee:%.2f,nTax:%.2f nItemId:%d",self.nFee,self.nTax,self.nItemId)
	self:_ResetTable()
	self:_ResetUsers()
	self:_UpdateIntervalTime()
	self:_UpdateAiUrl()

	self.nRealCountForBanRobot =tPublicRedis.RealCountForBanRobot(self.nGroupId,Define.nGameId) or 1000
	self:Print("nRealCountForBanRobot:%d",self.nRealCountForBanRobot)

	--锁定玩家入场必要的金币(一个辅助函数)
	local function _DoLockGold(tUser)
		local isSuccee,nNewLock =self:_InitUserTakeIn(tUser,tUser.nBuyTo)
		if tUser.nIsAutoBuy ~=1 then	--如非设置每局自动买入,则设置的买入只生效一次						
			tUser.nBuyTo =0
		end
		if not isSuccee then
			return false
		end
		tUser.nChipBuy =math.floor(nNewLock)
		if self:Gold_Lock(tUser,self.nFee) then
			return true
		elseif GreaterOrEqual((tUser.nLockGoldInTable -self.nFee) ,self.nEnterMin) then
			return true
		end
		return false
	end
	
	--确定可以参与本次牌局的玩家
	local arrPosPartIn ={}
	local arrUserPartIn ={}
	for nPos,tUser in pairs(self.arrUsers) do
		if _DoLockGold(tUser) then								--锁定玩家入场必要的金币
			table.insert(arrPosPartIn,nPos)
			table.insert(arrUserPartIn,tUser)
			tUser.nBalance =tUser.nLockGoldInTable -self.nFee	--初始化玩家可用筹码
			self:Print("_DoLockGold For User_%d,nPos_%d,nNowLock:%.3f,nBalance:%.3f isAndroid:%s",
				tUser.nUserId,nPos,tUser.nLockGoldInTable,tUser.nBalance,tostring(tUser.isAndroid))
		else
			self:Print("_DoLockGold Fail For User_%d,nPos_%d isAndroid:%s",tUser.nUserId,nPos,tostring(tUser.isAndroid))
			self:_ForceStandUp(nPos,13)	  						--强制金币不足玩家站起(13为金币不足的错误码)
		end
	end

	--判断人数是否足够开始游戏
	assert(#arrPosPartIn ==#arrUserPartIn)
	if #arrPosPartIn <2 then 
		self:Print("StartGame Fail,PartIn UserCnt not enough")
		return
	end
	self.arrPosPartIn =arrPosPartIn

	--牌局id生成
	self.sPaiJuId =tPubUser.CreatePaiJuID()   

	self.tStatistic:Init()

	--回顾记录
	self.tReview:Init(self.sPaiJuId,self.nSmallBlind,self.nBigBlind,self.nCapacity,self.nOperateTime,self.nZhuaTou)
	for _,v in ipairs(arrUserPartIn) do
		self.tReview:AddUser(v.nUserId,v.nSitId,v.sFaceId,v.sName,v.nSex,v.sShopAccount,v.nBalance)
	end

	--使用预设置牌模式(预先发好公共牌和各玩家底牌)
	if not self:BackStageCtrl(arrUserPartIn) then	--如果后台不控牌 (如控，就使用控牌的规则预设定牌)
		self.IsBackstageCtrl=false
		self:PreDealCard(arrUserPartIn)
	else
		self.IsBackstageCtrl=true					--后台控牌
	end

	--免费试玩次数加1(针对试玩房)
	for _,tUser in ipairs(arrUserPartIn) do
		if (not tUser.isAndroid) and tUser.isAddFreeTimeIfStart then
			tPublicRedis.IncrUserTryPlayCntOfTexas(tUser.nUserId)	--免费试玩次数加1
			tUser.isAddFreeTimeIfStart=false
		end
	end
	--控牌接口实现
	local arrRealUserId ={}
	for _,tUser in ipairs(arrUserPartIn) do
		if not tUser.isAndroid then
			table.insert(arrRealUserId,tUser.nUserId)
		end
	end
	if #arrRealUserId ==#arrUserPartIn or self.IsBackstageCtrl then		--全是真人或后台控牌时，不控牌
		self:Print("IsNeedControlBR Return:nUserId_0 nCtrlType_0,all is RealUser")
	else
		local nUserId,nCtrlType =self:_IsNeedControl(arrRealUserId)
		self:Print("IsNeedControlBR Return:nUserId_%d nCtrlType_%d",nUserId,nCtrlType)
		if (nCtrlType==2 or nCtrlType==3) and nUserId>0 then
			local isSuccee =self:_TryLetAndroidWin(arrUserPartIn,nUserId)	--优先将最大牌转移到机器人上
			self:Print("_TryLetAndroidWin:%s",tostring(isSuccee))
			self.isControl =nCtrlType
			self.nControlUserId =nUserId
		elseif nCtrlType==4 and nUserId>0 then
			local isSuccee =self:_TryLetRealUserWin(arrUserPartIn,nUserId)	--优先将最大牌转移到真人上
			self:Print("TryLetRealUserWin:%s",tostring(isSuccee))
			self.isControl =nCtrlType
			self.nControlUserId =nUserId
		end
	end

	--初始化牌堆;给参与牌局的玩家发两个底牌,并设置其状态为 '等待操作权中'
	self.tPile =tAlg.NewPile()
	self.arrPreSetCommCardEffect =self.arrPreSetCommCard
	self.arrPreSetCommCard ={}
	for _,tUser in ipairs(arrUserPartIn) do
		tUser.arrHoleCards=self.tPile:GetCards(2,tUser.arrPreSetHoleCard)	
		self:_SetUserStatus(tUser,UserStatus.nWaitForOp)	
		tUser.tCardType =tAlg.DeZhouCardType(tUser.arrHoleCards,self.arrCommunityCards)
		tUser.isNeedSettle =true
		if not tUser.isAndroid then
			self.isHaveRealUser =true
		end
		tUser.nAiType=math.random(0,2)					--随机一个Ai类型;0一般 1进取 2保守
	end
	self:Print("arrPreSetCommCardEffect:%s",Define.CardsToStr(self.arrPreSetCommCardEffect))
	self.arrPreSetCommCardCp = _CopyArr(self.arrPreSetCommCardEffect)

	--确定庄家位置
	if self.nBankerPos then
		self.nBankerPos =self:_NextGainRightsPos(self.nBankerPos)
	else
		local nRandNum =math.random(1,#self.arrPosPartIn)
		self.nBankerPos =self.arrPosPartIn[nRandNum]
	end
	assert(self.nBankerPos ~=nil)
	assert(_IsHaveEle(self.arrPosPartIn,self.nBankerPos))
	self.tReview:SetBankerPos(self.nBankerPos) 				--回顾记录
	
	--记录一个有序的玩家数组,服务于ai请求
	self.arrAiUser={}
	local nNowPos =self.nBankerPos
	for i=1,self.nCapacity do
		local item =self:_GetAiUser(nNowPos)
		if item and _IsHaveEle(self.arrPosPartIn,nNowPos) then
			table.insert(self.arrAiUser,item)
		end
		nNowPos =self:_NextPos(nNowPos)
		if nNowPos ==self.nBankerPos then
			break
		end
	end

	--确定大小盲,抓头玩家位置
	local nSmallBlindPos,nBigBlindPos,nZhuaTouPos=nil,nil,nil
	if #self.arrPosPartIn==2 then
		nSmallBlindPos =self.nBankerPos
		nBigBlindPos =self:_NextGainRightsPos(nSmallBlindPos)
	else
		nSmallBlindPos =self:_NextGainRightsPos(self.nBankerPos)
		nBigBlindPos =self:_NextGainRightsPos(nSmallBlindPos)
		-- nZhuaTouPos =self:_NextGainRightsPos(nBigBlindPos)
	end
	assert(nSmallBlindPos ~=nil and nBigBlindPos~=nil)
	assert(_IsHaveEle(self.arrPosPartIn,nSmallBlindPos))
	assert(_IsHaveEle(self.arrPosPartIn,nBigBlindPos))

	--大小盲玩家下注
	self:_DoBet(nSmallBlindPos,self.nSmallBlind)
	self:_DoBet(nBigBlindPos,self.nBigBlind)
	local tBigBlindUser= self:_GetUser(nBigBlindPos)
	assert(tBigBlindUser~=nil)
	if Equal( tBigBlindUser.nBalance,0) then
		self:_SetUserStatus(tBigBlindUser,UserStatus.nAllIn)
	end
	self.tReview:BlindBet(nSmallBlindPos,self.nSmallBlind,nBigBlindPos,self.nBigBlind) --回顾记录
	-- if nZhuaTouPos and _IsHaveEle(self.arrPosPartIn,nZhuaTouPos) then
	-- 	self:_DoBet(nZhuaTouPos,self.nZhuaTou) --抓头玩家下注
	-- 	local tZhuaTouUser= self:_GetUser(nZhuaTouPos)
	-- 	assert(tZhuaTouUser~=nil)
	-- 	if Equal( tZhuaTouUser.nBalance,0) then
	-- 		self:_SetUserStatus(tZhuaTouUser,UserStatus.nAllIn)
	-- 	end
	-- 	self.tReview:ZhuaTouBet(nZhuaTouPos,self.nZhuaTou) --回顾记录
	-- end
	
	self.nFirstBet =self.nSmallBlind +self.nBigBlind
	--设置桌子游戏状态为 '开始'
	self:_SetGameStage(TableState.nPlaying)
	     
	--初始化玩家"可预操作"选项
	self:_InitUsersPreOpOption()
	--初始化机器人难度
	local isAiHard= self:InitAiGrade()

	--广播游戏开始
	--按发牌顺序排序
	local arrPosPartInSort =self:_SortByDeal(self.arrPosPartIn,nSmallBlindPos)
	self:_BroadCastGameStartNotify(nSmallBlindPos,nBigBlindPos,arrPosPartInSort,nZhuaTouPos)

	--回顾记录
	for _,nPos in ipairs(arrPosPartInSort) do
		local tUser =self:_GetUser(nPos)
		assert(tUser ~=nil)
		self.tReview:DealHoleCard(nPos,tUser.arrHoleCards,self:_GetCardType(tUser.tCardType))
	end

	--确定第一获得操作权的玩家,且给予其操作权
	--翻牌前 大盲的下一玩家首先获得操作权. 翻牌后庄家的下一玩家首先获得操作权 有抓头玩家时,抓头玩家的下一玩家首先获得操作权
	-- if nZhuaTouPos then
	-- 	nBigBlindPos =nZhuaTouPos
	-- end
	local nPosToGainRights =self:_NextGainRightsPos(nBigBlindPos)
	assert(nPosToGainRights~=nil)
	self.nTheRightsEndPos =nPosToGainRights
	self:_ToGiveRightsTo((0.4*#arrPosPartIn)+2.2,nPosToGainRights)
	self:Print("StartGame Succee,sPaiJuId:%s,isAiHard:%s IsBackstageCtrl:%s",self.sPaiJuId,tostring(isAiHard),tostring(self.IsBackstageCtrl))
	
	self.nUserIdLeader =self:_GetUserId(nPosToGainRights)

	--牌局写redis(以便后台实时查看与控牌)
	self:_WriteCurDetailToRedis()

	tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{isStartGame=true})

end

function Table:_GetUserId(nPos)
	local tUser =self.arrUsers[nPos]
	if tUser then
		return tUser.nUserId
	end
end

function Table:NextRound(nTheOnlyNotFoldPos)
	--重置桌子一些状态
	self.isGapOfNow =false
	self.nTheRightsEndPos =nil			--操作权终止位置
	self.nTheHighestBet =0				--当前最高下注		
	self.nLatelyIncreasesBet=0			--最近最高下注提升幅度
	--收归玩家下注进底池
	self:_CollectBetToPoolsN(self.arrPosPartIn)	
	--没弃牌玩家数
	local  arrPosOfNotFold = self:_UserPosOfNotFold()
	local nUserCountOfNotFold =#arrPosOfNotFold
	self:Print("NextRound, nUserCountOfNotFold:%d",nUserCountOfNotFold)
	--重置玩家下注和一些状态
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		if tUser.nStatus~=UserStatus.nFold then
			tUser.tPreOpOption=nil
			if tUser.nStatus~=UserStatus.nAllIn then
				self:_SetUserStatus(tUser,UserStatus.nWaitForOp)
			end
		end
	end
	--当前公共牌数量
	local nCommunityCardsCnt =#self.arrCommunityCards
	--公共牌已够5个,或缺乏玩家竞争底池
	if nCommunityCardsCnt ==5 or #self.arrPosPartIn==0 or nUserCountOfNotFold<=1 then		
		self:_ToSettle(0.2)
		return
	end
	local arrCardsNewAdd =nil
	local arrCardType={}
	--如果少于两个玩家可以获得操作权，亮牌后,直接发够5个公共牌，然后进行结算
	local nPosToGainRights =self:_NextGainRightsPos(self.nBankerPos)
	if nPosToGainRights==nil or self:_NextGainRightsPos(nPosToGainRights)==nil then
		arrCardsNewAdd,arrCardType =self:_DealCommunityCards(5- nCommunityCardsCnt)
		self.tReview:DealCard(arrCardsNewAdd,arrCardType,self:_GetProtoArrPot(),true)  --回顾记录
		self:_BroadCastDeZhouDealNotify(arrCardsNewAdd,true)		   --广播	
		self:_ToNextRound(0.2+ (0.5*#arrCardsNewAdd))				   --进入下一轮(因已发够5牌，下一轮会直接进入结算)
		return
	end
	--初始化玩家可预操作选项
	self:_InitUsersPreOpOption()
	--发牌,第一次发时发3个，后续发1个
	if nCommunityCardsCnt ==0 then
		arrCardsNewAdd,arrCardType =self:_DealCommunityCards(3)
	else
		arrCardsNewAdd,arrCardType =self:_DealCommunityCards(1)
	end
	self.tReview:DealCard(arrCardsNewAdd,arrCardType,self:_GetProtoArrPot(),false)  --回顾记录

	--广播
	self:_BroadCastDeZhouDealNotify(arrCardsNewAdd)

	--新一轮，给予第一个玩家操作权 
	self.nTheRightsEndPos =nPosToGainRights	
	self.nUserIdLeader =self:_GetUserId(nPosToGainRights)
	if arrCardsNewAdd and #arrCardsNewAdd==3 then
		self:_ToGiveRightsTo(1.2,nPosToGainRights)	
	else
		self:_ToGiveRightsTo(0.4,nPosToGainRights)
	end
end

--结算
function Table:Settle()
	local nTheOnlyNotFoldPos =self:_IsJustOneNotFold()
	self:Print("Settle_ nTheOnlyNotFoldPos:%s",tostring(nTheOnlyNotFoldPos))
	self.isGapOfNow =false
	self:_SetGameStage(TableState.nSettle)

	--打印底池和公共牌信息
	self:_PrintPools()
	self:Print("arrCommunityCards:%s",Define.CardsToStr(self.arrCommunityCards))
	
	--打印玩家信息
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local tCardType =tUser.tCardType or 0
		local sHoleCard =Define.CardsToStr(tUser.arrHoleCards)
		local sCardType =Define.CardTypeToStr(tCardType.nCardType or 0)
		local sFiveCard =Define.CardsToStr(tCardType.arrFiveBack or {})
		self:Print("nPos_%d nUserId:%d CardType:%s HodeCard:%s FiveCard:%s Status:%s",nPos,tUser.nUserId,sCardType,sHoleCard,sFiveCard,tUser.nStatus)
	end
	--计算玩家输赢
	local tPosToArrWin =self:_UsersWinFromPools(nTheOnlyNotFoldPos)
	--打印金币流向信息
	self:Print("tUserIdToGoldFlowInfo:%s",tBase.tostring(self.tUserIdToGoldFlowInfo) )

	local arrUsersWin ={}
	local arrUserForSlave={}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local tCardType =tUser.tCardType or {}
		local UserGetFromPot ={}
		UserGetFromPot.nPos=nPos										 	--座位号
		UserGetFromPot.arrHoleCards=tUser.arrHoleCards			 			--底牌(该玩家可能在公共牌阶段已亮过牌,前端看重复亮牌会不会有问题)
		UserGetFromPot.arrCombinedCards=tCardType.arrFiveBack or {}	 		--能组成最大牌型的5个牌
		UserGetFromPot.nCardType=tUser.tCardType.nCardType or 0				--牌型(见本文件头部"牌型定义")						
		UserGetFromPot.arrGoldGet=tPosToArrWin[nPos] or {}					--从各个池处中获得的金币
		UserGetFromPot.isWin =self:_IsWin(UserGetFromPot.arrGoldGet)		--true时高亮牌型
	
		--弃牌的机器人随机亮牌
		if tUser.isAndroid and tUser.nStatus ==UserStatus.nFold and math.random(1,100)<10 then 
			tUser.isShowCardWhenEnd =true
		end
		--判断玩家是否亮牌
		local isShowCard =true
		if tUser.nStatus ==UserStatus.nFold and (not tUser.isShowCardWhenEnd) then
			isShowCard =false
		end
		if nPos ==nTheOnlyNotFoldPos then
			isShowCard =false
		end
		if nTheOnlyNotFoldPos or isShowCard==false then
			UserGetFromPot.isWin =false
		end
		local nPaiJuProfit,nChouShui =self:_UserChipsSettle(tUser,UserGetFromPot.arrGoldGet,true)
		UserGetFromPot.nProfit =nPaiJuProfit								--盈利 >0时显示 "胜利"
		UserGetFromPot.nCmpValue =tUser.tCardType.nComValue					--牌型相同时，使用该值来决定大小
		UserGetFromPot.isShowCardWhenEnd =isShowCard						--是否亮牌,true:是 其它:否
		UserGetFromPot.nCurGold =tUser.nBalance								--当前剩余可用筹码
		table.insert(arrUsersWin,UserGetFromPot)
		self:Print("nPos_%d isWin:%s Win:%s nPaiJuProfit:%.3f isShowCard:%s",nPos,tostring(UserGetFromPot.isWin),cjson.encode(UserGetFromPot.arrGoldGet),
				nPaiJuProfit,tostring(isShowCard))

		local item={}
		item.nPos=nPos
		item.nUserId=tUser.nUserId
		item.nUnLockGold=self:Get_User_UnLockGold(tUser)
		item.nBalance =tUser.nBalance
		table.insert(arrUserForSlave,item)
 	end
	self:WriteRecords()
	self.tReview:Settle(self:_GetProtoArrPot(),arrUsersWin)		--回顾记录
	self.tStatistic:DoPersist(self.nGroupId)
	
	if nTheOnlyNotFoldPos then
		self.tWinUserInfo.nCardType =0
	end

	--广播
	local DeZhouSettleNotify ={}
	DeZhouSettleNotify.arrUsersWin=arrUsersWin								--所有玩家牌型与输赢情况(弃牌玩家除外)
	DeZhouSettleNotify.arrPot =self:_GetProtoArrPot()
	DeZhouSettleNotify.nStage =self.nStage
	DeZhouSettleNotify.arrUserForSlave=arrUserForSlave
	self:_BroadCastSettleNotify(DeZhouSettleNotify)
	
	self:_ToSettleEnd()
end


function Table:SettleEnd()
	self:Print("SettleEnd nUserCnt:%d",self.nUserCnt)
	tPublicRedis._UpdateCurPaiJu(self.sTableId)
	
	if self.nClubId then
		local tReviewData =self.tReview:GetData()
		local sRevieData =json.encode(tReviewData)
		self:Print("sRevieData Len:%d",#sRevieData)
	--	tPublicRedis._SaveTexasReview(self.sPaiJuId,sRevieData)
		local tData ={}
		tData.nClubId =self.nClubId
		tData.nGameId =Define.nGameId
		tData.sTableId =self.sTableId
		tData.sPaiJuId =self.sPaiJuId
		tData.sPlayBackData =sRevieData
		tPublicClub.WritePlayBackData(tData)
	end

	if self.isHaveRealUser then
		local arrPool =self:_GetProtoArrPot()
		local tElseInfo ={arrCommunityCards =self.arrCommunityCards,arrPool=arrPool,tTableInfo=self:GetTableInfoForClub(),tWinUserInfo =self.tWinUserInfo}
		self:WriteDetail(self.tUsersInfo,self.tDealCardInfo,self.tBetInfo,tElseInfo)
	end
	self:_SetGameStage(TableState.nInit)

	--广播桌子重置
	self:_BroadCastTableResetNotify()

	--清理离线与连续两局没操作的玩家
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		if tUser then
			if tUser.isHaveOp then
				tUser.nConsecutiveNoOp =0
			elseif tUser.nGetChanceCnt>0 then
				tUser.nConsecutiveNoOp =tUser.nConsecutiveNoOp +1
			end
			if tUser.nOffLineCnt~=0 then
				self:_SetLeaveSeat(nPos)
			elseif tUser.nConsecutiveNoOp >=2 then
				self:_ForceStandUp(nPos,17)
			elseif tUser.isKickWhenEnd then
				self:_ForceStandUp(nPos,20)
			end
		end
	end

	self:_ResetTable()
	self:_ResetUsers()

		-- redis中APIOpenTale_对应桌子的信息需要更新
	-- 当存在玩家离开需要更新redis中玩家信息
	local arrUserPartIn ={}
	for nPos,tUser in pairs(self.arrUsers) do
		if (not tUser.isRetain) then
			if GreaterThan(tUser.nLockGoldInTable,0) then
				table.insert(arrUserPartIn,tUser)
			end
		end
	end

	local info = {}
	for _,v in ipairs(arrUserPartIn) do
		table.insert(info, {nUserId = v.nUserId, sName = v.sName, nBalance = v.nBalance})
	end
	tPubUser.API_ChangeTable(self.sTableId, cjson.encode(info))

	-- redis中APIOpenTale_对应桌子的信息需要更新
	-- 当存在玩家离开需要更新redis中玩家信息
	local arrUserPartIn ={}
	for nPos,tUser in pairs(self.arrUsers) do
		if (not tUser.isRetain) then
			if GreaterThan(tUser.nLockGoldInTable,0) then
				table.insert(arrUserPartIn,tUser)
			end
		end
	end

	local info = {}
	for _,v in ipairs(arrUserPartIn) do
		table.insert(info, {nUserId = v.nUserId, sName = v.sName, nBalance = v.nBalance})
	end
	tPubUser.API_ChangeTable(self.sTableId, cjson.encode(info))
	
	--俱乐部桌子超时判断
	if self:IsClubTableTimeOut() then
		self:CloseTable(TableCloseReason.nClubTableTimeOut)
		return
	end

	--关闭桌子还是继续下一局
	local nCloseReason =self:_IsCloseWhenOver()
	if nCloseReason then
		self:CloseTable(nCloseReason)
		return
	end
	
	self:_UpdateRoomCfg()

	if not self.isPause then
		self:_TryToStartGame()
	else
		self:_Pause()
	end
	self:TransmitProtobuf("DeZhouTableResetNotify",{nNoUse=0}) 
	
	tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{isStartGame=false})
	return
end



function Table:_GetCards(nSitId)
	local tUser =self:_GetUser(nSitId)
	assert(tUser~=nil)
	return _CopyArr(tUser.arrHoleCards),_CopyArr(self.arrCommunityCards)
end


--后台改牌
function Table:ChangeCard(sPaiJuId,nCardOriginal,nCardChangeTo)
	if self.sPaiJuId ~=sPaiJuId then
		return false,"PaiJuId Not Match"
	end
	if not (isCardValue(nCardOriginal) and isCardValue(nCardChangeTo)) then
		return false,"Card Value Illegal"
	end
	if not self.tPile:IsHaveCard(nCardChangeTo) then
		return false,"nCardChangeTo is Be Used"
	end
	if self.nStage ~=TableState.nPlaying then
		return false,"Not Playing Statu"
	end
	local function _Change(arr)
		for i=1,#arr do
			if arr[i] ==nCardOriginal then
				self.tPile:DelCard(nCardChangeTo)
				self.tPile:BackCard(arr[i])
				arr[i] =nCardChangeTo
				return true
			end
		end
		return false
	end
	local function _ChangeOnly(arr)
		for i=1,#arr do
			if arr[i] ==nCardOriginal then
				arr[i] =nCardChangeTo
				return true
			end
		end
		return false
	end
	local function _UpdateCopy()
		if  _ChangeOnly(self.tCurRedisDetail.arrCommunityCard) then
			self:_SortRedisUserItem(self.tCurRedisDetail.arrUsersInfo)
			tPublicRedis._UpdateCurPaiJu(self.sTableId,cjson.encode(self.tCurRedisDetail))
			return true
		end
		for _,v in ipairs ( self.tCurRedisDetail.arrUsersInfo) do
			if _ChangeOnly(v.arrHoleCards) then
				self:_SortRedisUserItem(self.tCurRedisDetail.arrUsersInfo)
				tPublicRedis._UpdateCurPaiJu(self.sTableId,cjson.encode(self.tCurRedisDetail))
				return true
			end
		end
		return false
	end
	if _Change(self.arrPreSetCommCardEffect) then
		self:_UpdateRank()
		_UpdateCopy()
		self:Print("change PreSetCommCard")
		return true,"succee"
	end
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		if  _Change(tUser.arrHoleCards) then
			tUser.tCardType =tAlg.DeZhouCardType(tUser.arrHoleCards,self.arrCommunityCards)
			self:_UpdateRank()
			_UpdateCopy()
			self:Print("change UserHoleCard")
			return true,"succee"
		end
	end
	return false,"Unknown,maybe user is leave"
end

--根据玩家的当前牌型，更新其排名
function Table:_UpdateRank()
	local arr ={}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local tCardType =tAlg.DeZhouCardType(tUser.arrHoleCards,self.tCurRedisDetail.arrCommunityCard)
		local item ={}
		item.nCardType =tCardType.nCardType
		item.nComValue =tCardType.nComValue
		item.tUser =tUser
		table.insert(arr,item)
	end
	tAlg.SortByCardType(arr)

	for dex,v in ipairs(arr) do
		v.tUser.nRank =dex
	end
end

--后台踢人 tJsonData,sReturnKey
function Table:REQ_Kick_User(tData,sReturnKey)
	local nSitId,tUser =self:_GetSitIdByUserId(tData.nUserId)
	if not nSitId then
		self:Print("REQ_Kick_User,can not find user_%d",tData.nUserId)
		return
	end
	local nType = tData.nType or -1    		--1:立即踢出，解散 2:下局踢出
	self:Print("REQ_Kick_User nSitId:%d nUserId:%d nType:%d",nSitId,tUser.nUserId,nType)

	if nType==1  then
		self:_ForceStandUp(nSitId,nil)	--立即踢出
		self:_SendToSlave(sReturnKey,"RSP_Kick_User",{nUserId =tUser.nUserId})
		return
	end
	if nType==2 then
		if self:_IsPartInUser(nSitId) then
			tUser.isKickWhenEnd =true		 --当局结束后踢出(站起)
		else
			self:_ForceStandUp(nSitId,nil)
			self:_SendToSlave(sReturnKey,"RSP_Kick_User",{nUserId =tUser.nUserId})
		end
	end
end


function Table:WriteRecord(nProfix,nTaxGold,tUser,isSettleInEnd)
	if self:MatchRoomId()==0 then return end
	if tUser.isAndroid then return end
	if Equal(nProfix,0) and Equal(nTaxGold,0) and Equal(tUser.nBetSum,0) then
		return
	end
	local isZhuang =(self.nBankerPos ==tUser.nSitId)

	local tData ={}
	tData.nUserId = tUser.nUserId
	tData.nGameType = Define.nGameId
	tData.nSession = self.nRoomId
	tData.nWinlose = nProfix 
	tData.nDrawWater = nTaxGold
	tData.sPaiJuId = self.sPaiJuId
	tData.nShopId =tUser.nShopId
	tData.nXiaZhu=tUser.nBetSum
	tData.nValid=tUser.nBetSum
	tData.IsControl =false
	tData.nGroupId =self.nGroupId
	if isZhuang then
		tData.nIsZhuang =1
	else
		tData.nIsZhuang =0
	end

	if self.nControlUserId ==tUser.nUserId then
		tData.IsControl =true
		tData.tElseInfo ={nControlType =self.isControl,nTableType=self.nTableType}
	else
		tData.tElseInfo ={nTableType=self.nTableType}
	end

	tData.tElseInfo.nLumpSumType=1		--1:正常结算 2:主动认输(弃牌)
	if tUser.nStatus ==UserStatus.nFold or (not isSettleInEnd) then
		tData.tElseInfo.nLumpSumType=2
		if self.tUserIdToIsRaise[tUser.nUserId] then
			tData.tElseInfo.FoldAfterRaise=1	--标记该玩家，加注后弃牌
		end
	end
	
	table.insert(self.arrWinLoseRecord,tData)	--缓存战绩，统一在结算后再写(因那时才能获得金币流向信息)
	--RecordDbr.Write_WinLoseRecord(tData)

	self:RealUserProfit(nProfix)
end

function Table:WriteRecords()
	for _,item in ipairs(self.arrWinLoseRecord) do
		local tGoldFlowInfo =self.tUserIdToGoldFlowInfo[item.nUserId]
		if tGoldFlowInfo then
			item.nWinloseToRobot = tGoldFlowInfo.nWinFromAndroid	--正确含义应该是:WinFromRobot
			item.nDrawWaterToRobot =0
			if GreaterThan(item.nWinloseToRobot,0) then
				item.nDrawWaterToRobot =publicApi.Floor_2(self.nTax*item.nWinloseToRobot/100)
			end
		else
			item.nWinloseToRobot = item.nWinlose+item.nDrawWater	--正确含义应该是:WinFromRobot
			item.nDrawWaterToRobot =item.nDrawWater
		end
		item.nClubId =self.nClubId                --俱乐部id (俱乐部房配置,否时为nil)
		item.nItemId=self.nItemId                 --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
		item.sTableId=self.sTableId
		RecordDbr.Write_WinLoseRecord(item)
	end
	self.arrWinLoseRecord ={}
end


function Table:WriteDetail(tUsersInfo,tDealCardInfo,tBetInfo,tElseInfo)
	if self:MatchRoomId()==0 then return end
	local tData ={}
	tData.sPaiJuId =self.sPaiJuId
	tData.nGameId =Define.nGameId
	tData.nRoomId =self.nRoomId
	tData.nAnte =self.nBigBlind
	tData.nZhuang =self.nBankerPos
	tData.tUsersInfo =tUsersInfo or {}
	tData.tDealCardInfo =tDealCardInfo or {}
	tData.tBetInfo =tBetInfo or {}
	tData.tElseInfo =tElseInfo or {}
	tData.sExData =cjson.encode({sLiveID=self.sLiveID})
	RecordDbr.Write_PaiJuDetail(tData)
end


function Table:_CancelAuto(tUser)
	tUser.nTimeOutCnt =0
	if not tUser.isAuto then
		return
	end
	tUser.isAuto =false
	self:_BroadCastCancelAutoNotify(tUser.nSitId)
end


function Table:_IsCloseWhenOver()
	local conditionA = (self.nCloseTableWhenOver ==TableCloseReason.nBackstageClose and (tPublicRedis._GetCloseTableStates(self.sTableId)==1))
	if conditionA then
		return self.nCloseTableWhenOver
	end
	return self.nCloseTableWhenOver 
end

--是否一局结束后关闭桌子
function Table:SetClose(nCloseReason)
	self:Print("SetClose,Reason:%d",nCloseReason)
	if self.nStage ~=TableState.nInit then
		self.nCloseTableWhenOver =nCloseReason
		return 
	end
	self:CloseTable(nCloseReason)
end

--sReturnKey为nil时广播到所有从服
--nUserId为0时,目标为所有用户
function Table:SendFailNotifyV2(sReturnKey,nUserId,nCode,sErr)
	local DeZhouFailNotify ={nCode=nCode,sErr=sErr}
	DeZhouFailNotify.nUserId =nUserId
	if nCode==11 or nCode==12 or nCode==13 then	--金币不足错误码
		local nPos,tUser =self:_GetSitIdByUserId(nUserId)
		DeZhouFailNotify.tRsp =self:_GetProtoTakeInRange(tUser)
	end
	if sReturnKey then
		self:_SendToSlave(sReturnKey,"DeZhouFailNotify",DeZhouFailNotify)
	else
		self:_BroadCastToSlaves("DeZhouFailNotify",DeZhouFailNotify)
	end
end


function Table:CloseTable(nReason)
	local nReason =nReason or -1
	self:Print("CloseTable,nReason:%d",nReason)
	self.Timer:KillAllTimer()
	self.TimerForAndroid:KillAllTimer()

	for nPos,_ in pairs(self.arrUsers) do
		self:_SetLeaveSeat(nPos)
	end
	--广播桌子关闭消息
	self:_BroadCastTableCloseNotify(nReason)

	self.isTableClose =true			--设为true后，桌子不再能发出消息
	self:_ResetTable()
	self.tInterFace._TableClose(self.sTableId,self.nTableType)
end

function Table:IsFullCapacity()
	local nUserCnt = self:_UserCount()
	return (nUserCnt == self.nCapacity)
end

function Table:TableCheck()
	--桌子太久没真人时,关闭桌子
	if self.nUserCntOfReal ==0 and (not self.nClubId) then
		local nElapse =os.time() -self.nTimestampZeroRealUser
		local nElapseMax =300
		if self:MatchRoomId() then --匹配房固定时间
			nElapseMax =1800
		else
			nElapseMax =tPubUser.GetTableCloseTime()
		end
		nElapseMax =(self.nElapseMax or nElapseMax)

		if nElapse >nElapseMax then
			self:Print("table to close, Reason:No Real User Too long")
			self:SetClose(TableCloseReason.nNoRealUserTooLong)
			return
		end
	end

	--俱乐部桌子超时判断
	if self:IsClubTableTimeOut() then
		self:SetClose(TableCloseReason.nClubTableTimeOut)
		return
	end

	self.TimerForAndroid:DelayCall(60*1000,self.TableCheck,self)

	--卡桌检查与处理
	if self.nStage ~=TableState.nInit then
		local nCurTime =os.time()
		if (nCurTime -self.nLastHeartTickTime)>100 then		
			self:Print("Table Is Error")
			self.isTableError=true
			self:CloseTable(TableCloseReason.nTableError)
			return
		end
	end
end

--俱乐部桌子是否超时
function Table:IsClubTableTimeOut()
	if self.nKeepTime then
		if (os.time() -self.nOpentime)>=self.nKeepTime then
			return true
		end
	end
	return false
end


--判断是否加入机器人. (机器人的离开，由该机器人本身决定，玩够随机的一个局数便主动离开)
function Table:TryLetAndroidEnter(nCntOfCall)
	if self.isRobotBan then
		self:Print("Android is ban")
		return
	end

	local nCntOfCall =nCntOfCall or 1
	local nRandomSeconds =10
	if self:MatchRoomId() and nCntOfCall <=3 then --匹配场开桌时加快机器人进入
		nRandomSeconds =math.random(1,3)
	else
		nRandomSeconds =math.random(5,18)
	end
	self.TimerForAndroid:DelayCall(nRandomSeconds*1000,self.TryLetAndroidEnter,self,nCntOfCall+1)

	if self.isConfigNotSet then
		self:Print("BanAndroid:isConfigNotSet is true")
		return
	end
	local nUserCnt,nRealUserCnt = self:_UserCount()

	if (self.nCapacity -nUserCnt)<=1 then 
		self:Print("BanAndroid:nUserCnt is small")
		return
	end
	if nRealUserCnt >=self.nRealCountForBanRobot then
		self:Print("BanAndroid,nRealUserCnt_%d >=nRealCountForBanRobot_%d",nRealUserCnt,self.nRealCountForBanRobot)
		return
	end

	local nCnt =tPublicRedis._LiveAndroidCount(self.nGroupId,Define.nGameId,self.nRoomId)
	local nNowRobotCnt =(nUserCnt -nRealUserCnt)
	self:Print("nNowRobotCnt:%d ShouldBet:%d nGroupId:%d nRoomId:%d",nNowRobotCnt,nCnt,self.nGroupId,self.nRoomId)
	if  nNowRobotCnt>=nCnt then
		return
	end

	local tRoomConfig ={nGroupId=self.nGroupId,nRoomId=self.nRoomId,nEnterFloorLimit=self.nBuyMin}
	local arrRobots =self.tInterFace._GetRobots(tRoomConfig,1)

	for _,tRobot in ipairs(arrRobots) do
		if self.tUserNameToIsUsed[tRobot.sName] then
			self:Print("Repeat NickName:%s,nUserId:%d",tRobot.sName,tRobot.nUserId)
			self.tInterFace._LeaveTable(tRobot.nUserId,self)
			return
		end
		local _,nSitId =self:OnUserEnter(tRobot)
		if nSitId then
		tRobot:EnterTable(self,nSitId)
		end
	end
end



function Table:_Pause()
	if self.isToStartGame then
		self.Timer:KillAllTimer()
		self.isToStartGame=false
		self:_BroadToStart(-1) 
		self.nTimeStart =-1
		return
	elseif self.nStage ==TableState.nInit then
		self:_BroadToStart(-1) 
		self.nTimeStart =-1
		return
	end
end

function Table:_PauseCancel()
	if not self:_TryToStartGame(3) then
		self:_BroadToStart(0)
		self.nTimeStart =0
	end
end

function Table:_TryToStartGame(nToStartTimeMin)
	if self.nStage ~=TableState.nInit then return end
	if self.isPause then 
		assert((not self.isToStartGame),"isToStartGame Error")
		return 
	end
	if self:_UserCount() <2 then
		if self.isToStartGame then
			self.Timer:KillAllTimer()
			self.isToStartGame =false
			self:_BroadToStart(0)
			self.nTimeStart =0
			return true
		end
	elseif not self.isToStartGame then 
		local nToStartTimeMin =nToStartTimeMin or 1
		self.Timer:KillAllTimer()
		self.isToStartGame=true
		local nSeconds =self.ToStartTime or 0
		if  nSeconds < nToStartTimeMin then nSeconds =nToStartTimeMin end
		self.Timer:DelayCall(nSeconds*1000+500,Table.StartGame,self)
		self:_BroadToStart(nSeconds)
		self.nTimeStart =os.time() +nSeconds
		return true
	end
end

function Table:_GetUser(nPos)
	return self.arrUsers[nPos]
end

function Table:_UserCount()
	local nCnt =0
	local nRealUserCnt =0
	for nPos=1,self.nCapacity do
		local tUser =self:_GetUser(nPos)
		if tUser then
			nCnt =nCnt+1
			if not tUser.isAndroid then
				nRealUserCnt =nRealUserCnt +1
			end
		end
	end
	return nCnt,nRealUserCnt
end

function Table:_ResetTable()
	self:Print("_ResetTable")
	self.tPile =nil					--牌
	self.arrCommunityCards={}		--公共牌
	self.nPotSum =0					--底池总额(已押筹码总额)
	self.arrPoolInfo={}
	self.arrPosPartIn ={}			--参与当前牌局的玩家座位号
	self.nTheRightsEndPos =nil		--操作权终止位置(一轮开始时为第一个获得操作权的玩家，接着谁提高了下注值便设置为谁的座位号)
	self.nTheHighestBet =0			--当前最高下注 (牌局中的玩家,除了弃牌和AllIn的玩家外,一轮结束时，所有人下注都会与该值持平)
	self.nLatelyIncreasesBet=0		--最近一次的nTheHighestBet增幅 (加注提升nTheHighestBet时,提升幅度需>= Max(1个大盲,最近提升幅度))
	self.isBanStandUpReq=false		--游戏中有一些间隙状态, 禁止玩家游戏中站起
	self.isHaveRealUser =false		--是否有真人参与本局游戏

	--牌局详情(存放本局里结算了的玩家信息)
	self.tUsersInfo={}
	self.tDealCardInfo={}
	self.tBetInfo={}
	self.tWinUserInfo={}

	self.isToStartGame =false
	self.nRobotBetSum =0				--当局当前机器人下注总额

	self.isControl=nil
	self.nControlUserId =nil
	self.nTimeStart =0
	self.isGapOfNow =false
	self.tUserIdToGoldFlowInfo={}
	self.arrWinLoseRecord ={}

	self.arrAiUser={}
	self.tOpHistory ={}
	self.tUserIdToIsRaise={}
end

function Table:_SetGameStage(nValueToSet)
	self.nStage =nValueToSet
end


function Table:_ResetUser(tUser)
	tUser.arrHoleCards={}		 		--底牌(值为0的牌，显示牌背,表示还没亮牌)
	tUser.nBet =0			 	 		--玩家当轮当前下注数目(0时不要显示)
	tUser.nStatus=UserStatus.nLooker 	--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
	tUser.nOpTimeRemain=0	 	 		--剩余可操作(思考)时间 (思考中时有效,其它情况时为0)
	tUser.tOperation=nil		 		--当前自己可操作信息(自己为思考状态时有)
	tUser.tPreOpOption=nil 		 		--自己当前可预操作选项
	tUser.tCardType=nil					--结算后存放牌型信息 {nCardType=nCardType,nComValue=nComValue,arrFiveBack=arrFiveBack}
	tUser.isToGainRights=false			--是否即将获得操作权
	tUser.nChipBuy=0					--一局开始时，新增的筹码买入
	tUser.nTimeOutCnt =0				--玩家超时次数
	tUser.isAuto=false					--是否托管
	tUser.isHaveOp=false        		--当局是否有操作
	tUser.nFee =0						--记录一局开始时扣减的手续费
	tUser.nRank =nil					--预发牌模式时记录牌型大小,1为最大，次之
	tUser.nBetSum =0					--当局总下注
	tUser.isShowCardWhenEnd=false		--是否结束后亮牌
	tUser.isKickWhenEnd =false			--当局结束后是否踢出(强制站起)
	tUser.nGetChanceCnt =0				--当局获得操作机会的次数
end

function Table:_GetBigUserInfo()
	local nRank =100
	local nBigPos =nil
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		if tUser.nRank ==nil then return end
		if  tUser.nStatus ~=UserStatus.nFold and tUser.nRank <nRank then
			nRank =tUser.nRank
			nBigPos =nPos
		end
	end
	local tBigUser =self:_GetUser(nBigPos)
	if tBigUser ==nil then return end
	return {isAndroid =tBigUser.isAndroid,nPos=nBigPos,nChipSum =tBigUser.nBet +tBigUser.nBalance}
end

function Table:_GetBalance(nPos)
	local tUser =self:_GetUser(nPos)
	if tUser then return tUser.nBalance end
end

function Table:_ResetUsers()
	self:Print("_ResetUsers")
	for nPos,tUser in pairs(self.arrUsers) do
		self:_ResetUser(tUser)
	end
end

function Table:_NextPos(nCurPos)
	return ((nCurPos % self.nCapacity) +1)
end

--如果返回nil,则表示本轮所有玩家操作权已使用完毕
function Table:_NextGainRightsPos(nCurPos)
	for i=1,self.nCapacity-1 do
		nCurPos =self:_NextPos(nCurPos)
		if nCurPos==self.nTheRightsEndPos then
			return 
		end
		local tUser =self:_GetUser(nCurPos)
		if tUser and tUser.nStatus ~=UserStatus.nAllIn and
		tUser.nStatus ~=UserStatus.nFold and tUser.nStatus ~=UserStatus.nLooker then
			return nCurPos
		end
	end
end



--下注
function Table:_DoBet(nPos,nBet)
	local tUser =self:_GetUser(nPos)
	assert(tUser ~=nil)
	assert(GreaterOrEqual( tUser.nBalance,nBet),tostring(nBet))
	assert(GreaterThan( nBet,0),tostring(nBet))

	tUser.nBalance=tUser.nBalance -	nBet --余额
	tUser.nBet =tUser.nBet +nBet		 --玩家当轮当前下注数目(0时不要显示)
	tUser.nBetSum =tUser.nBetSum +nBet	 --当局玩家总下注
	self.nPotSum =self.nPotSum +nBet

	if tUser.isAndroid then
		self.nRobotBetSum =self.nRobotBetSum +nBet
	end
	self:_UpdateAiUsers()

	self:Print("_DoBetForPos_%.2f %.3f",nPos,nBet)
	if GreaterThan(tUser.nBet ,self.nTheHighestBet) then
		self.nLatelyIncreasesBet =tUser.nBet -self.nTheHighestBet
		self.nTheHighestBet =tUser.nBet
		return true
	end
	
end

--按发牌顺序排序,重新返回一个新数组
function Table:_SortByDeal(arrPosPartIn,nSmallBlindPos)
	local arrA ={}
	local arrB ={}
	local isFind =false
	for _,nPos in ipairs(arrPosPartIn) do
		isFind =(isFind or (nPos ==nSmallBlindPos))
		if not isFind then
			table.insert(arrA,nPos)
		else
			table.insert(arrB,nPos)
		end
	end
	for _,nPos in ipairs(arrA) do
		table.insert(arrB,nPos)
	end
	return arrB
end


function Table:_GetCardType(tCardType)
	if tCardType==nil then
		return 0
	end
	return tCardType.nCardType
end

--玩家筹码结算 (返回的盈利中不包含手续费。)
function Table:_UserChipsSettle(tUser,arrGoldGet,isSettleInEnd)
	if not tUser.isNeedSettle then --预防重复结算
		return
	end
	tUser.isNeedSettle =false
	local nBalanceStart =tUser.nBalance +tUser.nBetSum	--游戏开始时的初始筹码
	local arrGoldGet=arrGoldGet or {}
	local nWinSum =0
	for _,v in ipairs(arrGoldGet) do
		nWinSum =nWinSum +v.nGold
	end
	tUser.nBalance =tUser.nBalance +nWinSum
	local nPaiJuProfit =nWinSum -tUser.nBetSum   --本局游戏盈利

	local nChouShui =0		-- 抽水
	if GreaterThan(nPaiJuProfit,0) then
		nChouShui =publicApi.Floor_2(self.nTax*nPaiJuProfit/100)
		nPaiJuProfit =nPaiJuProfit -nChouShui
		tUser.nBalance =tUser.nBalance -nChouShui
	end
	local nProfitSum =nPaiJuProfit -self.nFee	--游戏盈利扣除开场手续费后,就是本局的总盈利
	
	self:Print("ChipSettle nUserId:%d ,nPos:%d,nProfitSum:%.3f nChouShui:%.2f nFee:%.2f nBalance:%.3f",
		tUser.nUserId,tUser.nSitId,nProfitSum,nChouShui,self.nFee,tUser.nBalance)
	local isSuccee,nActChange =self:Gold_ChangeAndReLock(tUser,nProfitSum,Define.nGameId,self.nRoomId)
	
	assert(isSuccee)
	self:WriteRecord(nActChange,nChouShui +self.nFee,tUser,isSettleInEnd)
	local isWin =GreaterThan(nWinSum, tUser.nBetSum)

	self.tStatistic:UserWin(tUser.nUserId,nActChange,tUser.isAndroid)
	if (not isSettleInEnd) or tUser.nStatus ==UserStatus.nFold then
		if Equal(tUser.nBalance,0) then
			self.tStatistic:UserGiveUp(tUser.nUserId,tUser.isAndroid)
		end
	end

	--错误检测
	if not Equal(tUser.nBalance,tUser.nLockGoldInTable) then
		self:Print("Error Find,nBalance:%.3f,nLockGoldInTable:%.3f nActChange:%.3f",tUser.nBalance,tUser.nLockGoldInTable,nActChange)
		tUser.nBalance =tUser.nLockGoldInTable
	end
	--打印redis用户金币信息
	local __,tGoldInfo =self:Get_User_UnLockGold(tUser)
	if tGoldInfo then
		local sGoldInfo =cjson.encode((tGoldInfo or {}))
		self:Print("AfterChipSettle nUserId:%d sGoldInfo:%s",tUser.nUserId,sGoldInfo)
	end
	
	--牌局详情信息
	local isFold =false
	if not isSettleInEnd or tUser.nStatus ==UserStatus.nFold then
		isFold =true
	end
	local item ={}
	item.nUserId =tUser.nUserId
	item.nSitId=tUser.nSitId
	item.sName=tUser.sName
	item.nProfit =nPaiJuProfit
	item.nDrawWater =nChouShui
	item.nBalanceStart=publicApi.Floor_2(nBalanceStart) 	--游戏开始时的带入筹码
	item.nBalanceEnd =publicApi.Floor_2(tUser.nBalance)		--游戏结束时的剩余筹码
	item.isAndroid= tUser.isAndroid

	table.insert(self.tUsersInfo,item)
	table.insert(self.tDealCardInfo,{nSitId=tUser.nSitId,arrCard=tUser.arrHoleCards,nCardType=tUser.tCardType.nCardType,
		isFold=isFold,isShowCardWhenEnd =tUser.isShowCardWhenEnd})
	table.insert(self.tBetInfo,{nSitId=tUser.nSitId,nBet=tUser.nBetSum})

	if isWin then
        self.tWinUserInfo = {sName =tUser.sName,nUserId=tUser.nUserId,nCardType=tUser.tCardType.nCardType, nWin = nPaiJuProfit}
    end
	return nPaiJuProfit,nChouShui
end

--玩家余额(筹码)转为金币
function Table:_UserBalanceToGold(tUser)
	local isSuccee =self:Gold_UnLockAll(tUser)
	assert(isSuccee)
end

--筹码充值 
--nBalanceBest :最佳达到值
function Table:_InitUserTakeIn(tUser,nBalanceBest)
	local nGoldLockInit =tUser.nLockGoldInTable
	if LessThan(tUser.nLockGoldInTable,self.nEnterMin) then
		local nLack =self.nBuyMin -tUser.nLockGoldInTable
		if not self:Gold_Lock(tUser,nLack) then
			return false
		end
	end
	if LessThan(tUser.nLockGoldInTable,nBalanceBest) then
		local curGold =self:Get_User_UnLockGold(tUser)
		curGold=publicApi.Floor_2(curGold)
		local nLack =nBalanceBest-tUser.nLockGoldInTable
		nLack =math.min(curGold,nLack)
		local isSuccee =self:Gold_Lock(tUser,nLack) 
		assert(isSuccee)
	end
	local nNewLock =(tUser.nLockGoldInTable-nGoldLockInit)
	if LessThan(nNewLock,0) then
		nNewLock =0
	end
	return true,nNewLock
end


--nOpId -20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx -23:结束后亮牌 -24:亮牌
function Table:_InitUsersPreOpOption(isClearNotFoldUser)
	local function _InitUser(tUser)
		if isClearNotFoldUser then
			if tUser.nStatus ~=UserStatus.nFold then
				tUser.tPreOpOption =nil
			end
			return
		end
		if tUser.nStatus ==UserStatus.nAllIn or tUser.isAuto then
			tUser.tPreOpOption =nil
			return
		end
		tUser.tPreOpOption =tUser.tPreOpOption or {arrOption ={}}
		local arrOption =tUser.tPreOpOption.arrOption
		if tUser.nStatus ==UserStatus.nFold then
			arrOption[1] =arrOption[1] or {nOpId=-23,isOn=false}
			arrOption[2]=nil
			arrOption[3]=nil
			return
		end
		local nOpIdB = -21													--过牌
		if LessThan(tUser.nBet, self.nTheHighestBet) then
			nOpIdB =math.min(self.nTheHighestBet-tUser.nBet,tUser.nBalance) --跟xx
		end
		arrOption[1] =arrOption[1] or {nOpId=-20,isOn=false}
		arrOption[2] =arrOption[2] or {nOpId=nOpIdB,isOn=false}
		arrOption[3] =arrOption[3] or {nOpId=-22,isOn=false}
		if arrOption[2].nOpId ~=nOpIdB then
			arrOption[2] ={nOpId=nOpIdB,isOn=false}
		end
	end
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		_InitUser(tUser)
	end
end

function Table:_GetPreOpIdOfOn(tPreOpOption)
	if tPreOpOption==nil then
		return
	end
	for _,item in ipairs(tPreOpOption.arrOption) do
		if item.isOn then
			return item.nOpId
		end
	end
end

function Table:_TryLetRealUserWin(arrUser,nUserId)
	local tTargetUser =nil
	local arrAndoidUser ={}
	local arrElseUser ={}
	local tNowWinUser =nil

	for _,tUser in ipairs(arrUser) do
		if tUser.nUserId ==nUserId then
			tTargetUser =tUser
		elseif tUser.isAndroid then
			table.insert(arrAndoidUser,tUser)
		else
			table.insert(arrElseUser,tUser)
		end
		if tUser.nRank ==1 then
			tNowWinUser =tUser
		end
	end

	if tTargetUser==nil or tNowWinUser==nil then
		return false
	end
	if tNowWinUser.nUserId==nUserId then
		return true
	end

	local tUserShouldWin =tTargetUser
	
	--将最大牌型调换到 tUserShouldWin 身上
	local arrPreSetHoleCard =tNowWinUser.arrPreSetHoleCard
	local nRank =tNowWinUser.nRank

	tNowWinUser.arrPreSetHoleCard =tUserShouldWin.arrPreSetHoleCard
	tNowWinUser.nRank =tUserShouldWin.nRank

	tUserShouldWin.arrPreSetHoleCard =arrPreSetHoleCard
	tUserShouldWin.nRank =nRank
	return true
end


function Table:_TryLetAndroidWin(arrUser,nUserId)
	local tTargetUser =nil
	local arrAndoidUser ={}
	local arrElseUser ={}
	local tNowWinUser =nil

	for _,tUser in ipairs(arrUser) do
		if tUser.nUserId ==nUserId then
			tTargetUser =tUser
		elseif tUser.isAndroid then
			table.insert(arrAndoidUser,tUser)
		else
			table.insert(arrElseUser,tUser)
		end
		if tUser.nRank ==1 then
			tNowWinUser =tUser
		end
	end
	if tTargetUser==nil or tNowWinUser==nil then
		return false
	end
	if tNowWinUser.isAndroid then
		return true
	end
	local tUserShouldWin =arrAndoidUser[1] or arrElseUser[1]
	if tUserShouldWin==nil then
		return false
	end
	local arrPreSetHoleCard =tNowWinUser.arrPreSetHoleCard
	local nRank =tNowWinUser.nRank

	tNowWinUser.arrPreSetHoleCard =tUserShouldWin.arrPreSetHoleCard
	tNowWinUser.nRank =tUserShouldWin.nRank

	tUserShouldWin.arrPreSetHoleCard =arrPreSetHoleCard
	tUserShouldWin.nRank =nRank
	return true
end


function Table:_IsNeedControl(arrUserId)
	local nUserIdCtrlToWin =nil
	for _,nUserId in ipairs(arrUserId) do
		local nCtrlType =tPubUser.IsNeedControl(Define.nGameId,self.nRoomId,nUserId)
		if nCtrlType==2 or nCtrlType==3 then
			return nUserId,nCtrlType
		elseif nCtrlType ==4 then
			nUserIdCtrlToWin =nUserId
		end
	end
	if nUserIdCtrlToWin then
		return nUserIdCtrlToWin,4
	end
	return 0,0
end


function Table:_WriteCurDetailToRedis()
	local tem ={}
	tem.sPaiJuId=self.sPaiJuId
	tem.arrCommunityCard =_CopyArr(self.arrPreSetCommCardEffect)
	tem.arrUsersInfo ={}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local item ={}
		item.arrHoleCards =_CopyArr(tUser.arrHoleCards)
		item.nUserId =tUser.nUserId
		item.sName =tUser.sName
		item.isAndroid =tUser.isAndroid
		item.nRank =nPos --tUser.nRank
		table.insert(tem.arrUsersInfo,item)
	end
	self:_SortRedisUserItem(tem.arrUsersInfo)

	self.tCurRedisDetail =tem
	local sCurPaiJu =cjson.encode(tem)
	tPublicRedis._UpdateCurPaiJu(self.sTableId,sCurPaiJu)
end

function Table:_SortRedisUserItem(arr)
	for _,v in ipairs(arr) do
		local nSitId,tUser =self:_GetSitIdByUserId(v.nUserId)
		if tUser then
			v.nDex =tUser.nRank or 0
		else
			v.nDex =100
		end
	end
	local function _ss(A,B)
		return A.nDex<B.nDex
	end
	table.sort(arr,_ss)
end


function Table:_CancelRights(tNotFoldUser)
	tNotFoldUser.tOperation =nil
	tNotFoldUser.tPreOpOption =nil
end

function Table:DoOpForUser(nPos,nOp,nCallOrRaiseChip)
	local tUser= self:_GetUser(nPos)
	assert(tUser~=nil)
	assert(tUser.tOperation ~=nil)
	self:_CancelRights(tUser)
	self:Print("DoOpForPos_%d,nOp:%s",nPos,Define.UserOpToStr(nOp))

	local isIncreasesBet =false
	if nOp ==UserOp.nFold then
		self:_SetUserStatus(tUser,UserStatus.nFold)
		nCallOrRaiseChip =0
	elseif nOp ==UserOp.nAllIn then
		self:_SetUserStatus(tUser,UserStatus.nAllIn)
		nCallOrRaiseChip =tUser.nBalance
		isIncreasesBet =self:_DoBet(nPos,nCallOrRaiseChip)
	elseif nOp ==UserOp.nPass then
		self:_SetUserStatus(tUser,UserStatus.nPass)
		nCallOrRaiseChip =0
	elseif nOp ==UserOp.nCall then
		self:_SetUserStatus(tUser,UserStatus.nCall)
		assert(GreaterOrEqual( nCallOrRaiseChip,0))
		isIncreasesBet =self:_DoBet(nPos,nCallOrRaiseChip)
	elseif nOp ==UserOp.nRaise then
		self:_SetUserStatus(tUser,UserStatus.nRaise)
		assert(GreaterOrEqual(nCallOrRaiseChip,0))
		isIncreasesBet =self:_DoBet(nPos,nCallOrRaiseChip)
	else
		assert(false)
	end
	--当前最高下注被提升了,其他玩家重新获得操作权
	if isIncreasesBet then
		self.nTheRightsEndPos =nPos
		self.nUserIdLeader =self:_GetUserId(nPos)
		self.tUserIdToIsRaise[tUser.nUserId]=true
	end
	--操作结束(即将轮到下一玩家操作，或即将结束本轮)
	local isHasNextUser =self:_OpEnd(nPos)
	--初始化玩家可预操作选项
	if isHasNextUser then
		self:_InitUsersPreOpOption()		--设置玩家的预操作
	else
		self:_InitUsersPreOpOption(true)	--清除非弃牌玩家的预操作
	end
	self.tReview:DoOp(nPos,nOp,nCallOrRaiseChip)
	
	--广播有玩家操作通知
	self:_BroadCastOpNotify(nPos,nOp,nCallOrRaiseChip,tUser)
	--统计玩家操作次数
	self:_AddOpCount(tUser.nUserId,nOp)
	return
end


--操作结束 (轮到下一玩家操作，或结束本轮)
function Table:_OpEnd(nPos)
	self.Timer:KillAllTimer()

	--操作后,参与本轮的玩家如果只剩一个没弃牌 (在上一轮AllIn或弃牌的玩家不参与本轮)
	if self:_IsJustOneNotFoldInCurRound() then
		self:_ToNextRound(0.2)
		return
	end
	--下一玩家获得操作权 或结束本轮
	local nPosToGainRights =self:_NextGainRightsPos(nPos)
	if nPosToGainRights then
		self:_ToGiveRightsTo(0.4,nPosToGainRights)
		return true
	end
	self:_ToNextRound(0.2)
end

--本回合是否只剩一个没弃牌的玩家 (在上一回合AllIn或弃牌的玩家不包含在本回合里)
function Table:_IsJustOneNotFoldInCurRound()
	assert(TableState.nPlaying ==self.nStage)
	local cnt =0
	local tTargetUser =nil
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil,tostring(nPos))
		if tUser.nStatus ~=UserStatus.nFold then
			if not (tUser.nStatus ==UserStatus.nAllIn and Equal(tUser.nBet,0)) then --AllIn但下注为0的玩家属于上一回合玩家
				cnt =cnt +1
				tTargetUser =tUser
			end
		end
	end
	assert(cnt >0)
	if (cnt ==1) then
		return tTargetUser.nSitId,tTargetUser
	end
end

function Table:_IsJustOneNotFold()
	local arrPosOfNotFold =self:_UserPosOfNotFold()
	if #arrPosOfNotFold ==1 then
		return arrPosOfNotFold[1]
	end
end

--牌局中没弃牌的玩家位置
function Table:_UserPosOfNotFold()
	assert(TableState.nPlaying ==self.nStage)
	local arrPos ={}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil,tostring(nPos))
		if tUser.nStatus ~=UserStatus.nFold then
			table.insert(arrPos,nPos)
		end
	end
	return arrPos
end

function Table:_SetUserStatus(tUser,nValueToSet)
	tUser.nStatus =nValueToSet
end

--用于打印
function Table:_OperationRightsToStr(tOperation)
	if tOperation==nil then return "Nil" end
	local sBtnA =Define.UserOpToStr(tOperation.nOpA)
	local sBtnB =Define.UserOpToStr(tOperation.nOpB)
	local sBtnC =Define.UserOpToStr(tOperation.nOpC)
	local sStr =string.format("%s,%s,%s",sBtnA,sBtnB,sBtnC)
	if tOperation.tRaiseChoice then
		local sRaiseRange =string.format(" RaiseRange:[%.3f,%.3f]",tOperation.tRaiseChoice.nMin,tOperation.tRaiseChoice.nMax)
		sStr =sStr..sRaiseRange
		if #tOperation.tRaiseChoice.arrQuickRaise >0 then
			local sQuickRaise =string.format(" QuickRaise:%s",table.concat(tOperation.tRaiseChoice.arrQuickRaise,","))
			sStr =sStr..sQuickRaise
		end
	end
	return sStr
end

--给予玩家操作权
function Table:GiveRightsTo(nPosToGainRights)
	local tUser= self:_GetUser(nPosToGainRights)
	assert(tUser~=nil)
	tUser.nGetChanceCnt =tUser.nGetChanceCnt +1
	self:_SetUserStatus(tUser,UserStatus.nThinking)
	tUser.nGetRightTime =os.time()
	tUser.isToGainRights =false
	tUser.tOperation =self:_GetProtoOperationRights(nPosToGainRights)
	local nPreOpIdOfOn =self:_GetPreOpIdOfOn(tUser.tPreOpOption)
	tUser.tPreOpOption =nil
	self:Print("GiveRightsToPos_%d,%s,nPreOpIdOfOn:%s",nPosToGainRights,self:_OperationRightsToStr(tUser.tOperation),tostring(nPreOpIdOfOn))

	--nOpId -20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx
	if nPreOpIdOfOn ==-20 or nPreOpIdOfOn ==-21 then
		if tUser.tOperation.nOpB ==UserOp.nPass then
			self:DoOpForUser(nPosToGainRights,UserOp.nPass)
			return
		else
			self:DoOpForUser(nPosToGainRights,UserOp.nFold)
			return
		end
	elseif nPreOpIdOfOn ==-22 or (nPreOpIdOfOn and GreaterThan(nPreOpIdOfOn,0)) then
		if GreaterThan(tUser.tOperation.nOpB ,0) then
			self:DoOpForUser(nPosToGainRights,UserOp.nCall,tUser.tOperation.nOpB)
			return
		elseif tUser.tOperation.nOpB ==UserOp.nAllIn then
			self:DoOpForUser(nPosToGainRights,UserOp.nAllIn,0)
			return
		elseif tUser.tOperation.nOpB ==UserOp.nPass then
			self:DoOpForUser(nPosToGainRights,UserOp.nPass,0)
			return
		end
	end
	if tUser.isAuto then
		self:_ToOpForTimeOutUser(1,nPosToGainRights)
	else
		self:_ToOpForTimeOutUser(self.nOperateTime,nPosToGainRights)
	end
	--广播有玩家获得操作权
	self:_BroadCastGetRightNotify(tUser,nPosToGainRights)
end


function Table:_ToGiveRightsTo(nSeconds,nPosToGainRights)
	local tUser =self:_GetUser(nPosToGainRights)
	assert(tUser~=nil)
	tUser.isToGainRights =true --即将获得操作权
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.GiveRightsTo,self,nPosToGainRights)
	self:_UpdateHeartTick()
end

function Table:_ToNextRound(nSeconds,nTheOnlyNotFoldPos)
	self.isGapOfNow =true
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.NextRound,self,nTheOnlyNotFoldPos)
	self:_UpdateHeartTick()
end

function Table:_ToSettle(nSeconds,nTheOnlyNotFoldPos)
	self.isGapOfNow =true
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.Settle,self,nTheOnlyNotFoldPos)
	self:_UpdateHeartTick()
end

function Table:_ToSettleEnd()
	local nSeconds =self.ToSettleEndTime or 0
	if  nSeconds<1 then
		nSeconds =1
	end
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.SettleEnd,self)
	self:_UpdateHeartTick()
end

--返回:{{nPos=?,nGoldWin=?}}
function Table:_CalPoolItemWin(item)
	--非弃牌且非中途离开玩家牌型，才能参与底池争夺
	local arrNotFoldUsersCardType ={}		
	for _,nPos in ipairs(item.arrPosForm) do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.nStatus ~=UserStatus.nFold and tUser.nStatus ~=UserStatus.nLooker then	--该判断用意:该人已经中途离开或该位置已经被旁观玩家替换
			assert(tUser.tCardType ~=nil)
			tUser.tCardType.nPos =nPos
			tUser.tCardType.nUserId=tUser.nUserId
			tUser.tCardType.isAndroid =tUser.isAndroid
			table.insert(arrNotFoldUsersCardType,tUser.tCardType)
		end
	end
	--跳结算时,胜利玩家可能站起了,导致底池没人领取
	if #arrNotFoldUsersCardType ==0 then	
		return {}
	end
	--对牌型进行排序，获得最大牌型的元素
	local arrTheWinItem =tAlg.TheWinCardType(arrNotFoldUsersCardType)
	assert(#arrTheWinItem>0)
	--最大牌型的玩家平分该底池
	local arrRlt ={}
	local nGoldWin =publicApi.Floor_2(item.nPool/#arrTheWinItem) --这里流失精度,是否会产生问题
	for _,v in ipairs(arrTheWinItem) do
		table.insert(arrRlt,{nPos=v.nPos,nGoldWin =nGoldWin})
		self:_WinFromAndroid(v.nUserId,v.isAndroid,item.tAndroidToPoolForm,#arrTheWinItem)	--记录金币流向(机器人真人之间)
		self:_WinFromReal(v.nUserId,v.isAndroid,item.tRealUserToPoolForm,#arrTheWinItem)	--记录金币流向(机器人真人之间)
	end
	return arrRlt
end

function Table:_WinFromAndroid(nUserId,isAndroid,tAndroidToPoolForm,nWinCnt)
	local function _AssertInfoExist(nId)
		self.tUserIdToGoldFlowInfo[nId] =self.tUserIdToGoldFlowInfo[nId] or {nWinFromAndroid=0,nWinFromReal=0}
		return self.tUserIdToGoldFlowInfo[nId]
	end
	local tInfo =_AssertInfoExist(nUserId)
	for nUserIdOfAndroid,nPoolForm in pairs(tAndroidToPoolForm) do
		local nPoolFormA = nPoolForm/nWinCnt
		local tInfoA =_AssertInfoExist(nUserIdOfAndroid)
		tInfo.nWinFromAndroid =tInfo.nWinFromAndroid +nPoolFormA
		if isAndroid then
			tInfoA.nWinFromAndroid =tInfoA.nWinFromAndroid -nPoolFormA
		else
			tInfoA.nWinFromReal =tInfoA.nWinFromReal -nPoolFormA
		end
	end
end

function Table:_WinFromReal(nUserId,isAndroid,tRealUserToPoolForm,nWinCnt)
	local function _AssertInfoExist(nId)
		self.tUserIdToGoldFlowInfo[nId] =self.tUserIdToGoldFlowInfo[nId] or {nWinFromAndroid=0,nWinFromReal=0}
		return self.tUserIdToGoldFlowInfo[nId]
	end
	local tInfo =_AssertInfoExist(nUserId)
	for nUserIdOfAndroid,nPoolForm in pairs(tRealUserToPoolForm) do
		local nPoolFormA = nPoolForm/nWinCnt
		local tInfoA =_AssertInfoExist(nUserIdOfAndroid)
		tInfo.nWinFromReal =tInfo.nWinFromReal +nPoolFormA
		if isAndroid then
			tInfoA.nWinFromAndroid =tInfoA.nWinFromAndroid -nPoolFormA
		else
			tInfoA.nWinFromReal =tInfoA.nWinFromReal -nPoolFormA
		end
	end
end

function Table:_UsersWinFromPools(nTheOnlyNotFoldPos)
	local tPosToArrWin ={}
	local function _AssertValueExist(nPos)
		if tPosToArrWin[nPos]==nil then
			tPosToArrWin[nPos]={}
		end
		return tPosToArrWin[nPos]
	end
	if nTheOnlyNotFoldPos then		--只剩一个玩家没弃牌时，该玩家获得全部底池筹码
		local arr =_AssertValueExist(nTheOnlyNotFoldPos)
		local tUser =self:_GetUser(nTheOnlyNotFoldPos)
		for nPoolId,item in ipairs(self.arrPoolInfo) do
			table.insert(arr,{nPotIdFrom=nPoolId,nGold=item.nPool})
			if tUser then
			self:_WinFromAndroid(tUser.nUserId,tUser.isAndroid,item.tAndroidToPoolForm,1)	--记录金币流向(机器人和真人之间)
			self:_WinFromReal(tUser.nUserId,tUser.isAndroid,item.tRealUserToPoolForm,1)		--记录金币流向(机器人和真人之间)
			end
		end
		return tPosToArrWin
	end
	for nPoolId,item in ipairs(self.arrPoolInfo) do
		local arrUsersWin =self:_CalPoolItemWin(item)  --{{nPos=?,nGoldWin=?}}
		if #arrUsersWin==0 then
			self:Print("Waring:the Pool_%d is no user can Rec",nPoolId)		--底池没人领取，胜利玩家可能在跳结算是站起了
		end
		for _,v in ipairs(arrUsersWin) do
			local arr =_AssertValueExist(v.nPos)
			table.insert(arr,{nPotIdFrom=nPoolId,nGold=v.nGoldWin})
		end
	end
	return tPosToArrWin
end


function Table:_IsWin(arrGoldGet)
	if arrGoldGet==nil or #arrGoldGet==0 then
		return false
	end
	if #self.arrCommunityCards ~=5 then
		return false
	end
	for _,v in ipairs(arrGoldGet) do
		local tPoolInfo =self.arrPoolInfo[v.nPotIdFrom]
		if #tPoolInfo.arrPosForm >=2 then
			return true
		end
	end
	return false
end

--发公共牌，且更新各玩家牌型信息
function Table:_DealCommunityCards(nDealCnt)
	local arrCardsNewAdd =self.tPile:GetCards(nDealCnt,self.arrPreSetCommCardEffect)
	for _,v in ipairs(arrCardsNewAdd) do
		table.insert(self.arrCommunityCards,v)
	end
	local arrCardType ={}
	local nMaxPos =0
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		tUser.tCardType =tAlg.DeZhouCardType(tUser.arrHoleCards,self.arrCommunityCards)
		arrCardType[nPos] =self:_GetCardType(tUser.tCardType)
		nMaxPos =math.max(nPos,nMaxPos)
	end
	for i=1,nMaxPos do
		arrCardType[i] =arrCardType[i] or 0
	end
	self:Print("arrCardsNewAdd:%s",Define.CardsToStr(arrCardsNewAdd))
	return arrCardsNewAdd,arrCardType
end

--收归玩家下注到底池
function Table:_CollectBetToPoolsN(arrPos)
	local arrUsers ={}
	for _,nPos in ipairs(arrPos) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		table.insert(arrUsers,tUser)
	end
	--返回所有大于0的下注中,最小的那个下注值
	local function _MinBet()
		local nMinBet =0
		for _,tUser in ipairs(arrUsers) do
			if GreaterThan(tUser.nBet,0) and (nMinBet==0 or LessThan(tUser.nBet,nMinBet)) then
				nMinBet =tUser.nBet
			end
		end
		return nMinBet
	end
	--执行一轮收归操作 
	local function _DoOneCollect(nMinBet)
		local nPool=0
		local arrPosForm={}
		local tForReal ={}		--记录每个真人id投入该池的筹码
		local tForAndroid ={}	--记录每个机器人id投入该池的筹码
		for _,tUser in ipairs(arrUsers) do
			if GreaterOrEqual(tUser.nBet,nMinBet) then
				if tUser.isAndroid then
					tForAndroid[tUser.nUserId]=(tForAndroid[tUser.nUserId] or 0) +nMinBet
				else
					tForReal[tUser.nUserId]=(tForReal[tUser.nUserId] or 0) +nMinBet
				end
				tUser.nBet =tUser.nBet -nMinBet
				nPool 	   =nPool +nMinBet
				table.insert(arrPosForm,tUser.nSitId)
			end
		end
		assert(GreaterThan(nPool,0))
		return {nPool=nPool,arrPosForm=arrPosForm,tRealUserToPoolForm=tForReal,tAndroidToPoolForm=tForAndroid}
	end
	--执行多轮收归操作,最终收归所有下注,即主池+边池全部收集完毕
	for i=1,#arrUsers do
		local nMinBet =_MinBet()
		if LessOrEqual(nMinBet,0) then
			break
		end
		local tPoolItem =_DoOneCollect(nMinBet)
		self:_AddPool(tPoolItem)
	end
	--收归结束后,断言所有下注都被收归置0
	for _,tUser in ipairs(arrUsers) do
		assert(Equal(tUser.nBet,0))
	end
	--打印底池信息
	self:_PrintPools()							
end


-- 有存活且不同才追加,其它情况合并
-- 如果底池为空，直接插入。
-- 否则，判断新池和当前最后一个池的存活玩家座位号是否完全一致：
-- 如果不一致（即有新边池），追加新池。
-- 如果一致（即同一池），合并金额和玩家列表。
-- 合并时同步合并真人/机器人分布。
function Table:_AddPool(tPoolItem)
	if #self.arrPoolInfo ==0 then
		table.insert(self.arrPoolInfo,tPoolItem)
		return
	end
	local arrSurvivePosA ={}
	local arrSurvivePosB ={}
	local tEndPoolItem =self.arrPoolInfo[#self.arrPoolInfo]
	for _,nPos in ipairs(tEndPoolItem.arrPosForm) do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.nStatus ~=UserStatus.nFold and tUser.nStatus ~=UserStatus.nLooker then
			table.insert(arrSurvivePosA,nPos)
		end
	end
	for _,nPos in ipairs(tPoolItem.arrPosForm) do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.nStatus ~=UserStatus.nFold and tUser.nStatus ~=UserStatus.nLooker then
			table.insert(arrSurvivePosB,nPos)
		end
	end
	--有存活且不同才追加,其它情况合并
	if #arrSurvivePosA>0 and #arrSurvivePosB>0 and (not _isNumArrEqual(arrSurvivePosA,arrSurvivePosB)) then
		table.insert(self.arrPoolInfo,tPoolItem)
		return
	end
	tEndPoolItem.nPool =tEndPoolItem.nPool +tPoolItem.nPool
	tEndPoolItem.arrPosForm =_PoolPosMerge(tEndPoolItem.arrPosForm,tPoolItem.arrPosForm)
	tEndPoolItem.tRealUserToPoolForm =_PoolFormMerge(tEndPoolItem.tRealUserToPoolForm,tPoolItem.tRealUserToPoolForm)
	tEndPoolItem.tAndroidToPoolForm =_PoolFormMerge(tEndPoolItem.tAndroidToPoolForm,tPoolItem.tAndroidToPoolForm)
end


---10:(1/2底池)  -11:(2/3底池) -12:(1个底池)  -13:(2个大盲) -14:(3个大盲)  -15:(4个大盲)
--[[
UserOp.nHalfPool =-10,         --(1/2底池)
UserOp.nTwoThirdsPool =-11,    --(2/3底池)
UserOp.nOnePool =-12,          --1个底池
UserOp.nTwoBlind=-13,          --2个大盲
UserOp.nThreeBlind=-14,        --3个大盲
UserOp.nFourBlind =-15,        --4个大盲
]]
function Table:_QuickOptionToBetValue(nOption,nBalance)
	if nOption ==UserOp.nHalfPool then
		return publicApi.Floor_2( (1/2) *self.nPotSum)
	end
	if nOption ==UserOp.nTwoThirdsPool then
		return publicApi.Floor_2( (2/3) *self.nPotSum)
	end
	if nOption ==UserOp.nOnePool then
		return self.nPotSum
	end
	if nOption ==UserOp.nTwoBlind then
		return 2 *self.nBigBlind
	end
	if nOption ==UserOp.nThreeBlind then
		return 3 *self.nBigBlind
	end
	if nOption ==UserOp.nFourBlind then
		return 4 *self.nBigBlind
	end
	if nOption ==UserOp.nAllIn then
		return nBalance
	end
	return 0
end
--publicApi.Floor_2(nNumber)

function Table:_GetUserQuickRaise(tUser,nMin,nMax)
	local arrOption ={}
	if #self.arrCommunityCards ==0 and LessOrEqual(self.nTheHighestBet,self.nBigBlind) then
		arrOption ={UserOp.nTwoBlind,UserOp.nThreeBlind,UserOp.nFourBlind}
	else
		arrOption ={UserOp.nHalfPool,UserOp.nTwoThirdsPool,UserOp.nOnePool}
	end
	local arrOptionNew ={}
	for _,nOption in ipairs(arrOption) do
		local nOptionBetValue =self:_QuickOptionToBetValue(nOption)
		if (GreaterOrEqual(nOptionBetValue,nMin) and LessOrEqual(nOptionBetValue,nMax)) and GreaterOrEqual(tUser.nBalance, nOptionBetValue) then
			table.insert(arrOptionNew,nOption)
		end
	end
	if #arrOptionNew<3 then
		table.insert(arrOptionNew,UserOp.nAllIn)
	end
	return arrOptionNew
end


function Table:_GetProtoOperationRights(nPos)
	local tUser= self:_GetUser(nPos)
	assert(tUser~=nil)
	local nDiffBet =self.nTheHighestBet -tUser.nBet
	assert(GreaterOrEqual(nDiffBet,0))

	local nOpA,nOpB,nOpC =nil,nil,nil

	--第一按钮,只有一种状态 '弃牌'
	nOpA =UserOp.nFold

	--第二按钮,有三种可能状态 'AllIn', '看牌', '跟注xx'
	if Equal( nDiffBet,0) then
		nOpB =UserOp.nPass
	elseif LessThan(nDiffBet ,tUser.nBalance) then
		nOpB =nDiffBet
	else
		nOpB =UserOp.nAllIn
	end

	--第三按钮,有三种可能状态 'AllIn', '加注', '加注(置灰)'  (缺:特殊情况时禁止加注的情况)
	if nOpB ==UserOp.nAllIn then
		nOpC =UserOp.nRaiseBan
		return {nOpA=nOpA,nOpB=nOpB,nOpC=nOpC}
	end
	local nMin =math.max(self.nLatelyIncreasesBet,self.nBigBlind) +self.nTheHighestBet -tUser.nBet
	if LessOrEqual(tUser.nBalance,nMin) then
		nOpC =UserOp.nAllIn
		return {nOpA=nOpA,nOpB=nOpB,nOpC=nOpC}
	end

	nOpC =UserOp.nRaise
	local tRaiseChoice ={}
	tRaiseChoice.nMin =nMin
	tRaiseChoice.nMax =tUser.nBalance
	tRaiseChoice.arrQuickRaise=self:_GetUserQuickRaise(tUser,tRaiseChoice.nMin,tRaiseChoice.nMax)	--(快速操作的选项)
	return {nOpA=nOpA,nOpB=nOpB,nOpC=nOpC,tRaiseChoice=tRaiseChoice}
end


function Table:_ToOpForTimeOutUser(nSeconds,nPos)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.OpForTimeOutUser,self,nPos)
end

function Table:OpForTimeOutUser(nPos)
	self:Print("OpForTimeOutUser %d",nPos)
	local tUser= self:_GetUser(nPos)
	assert(tUser~=nil)
	assert(tUser.tOperation ~=nil)
	assert(tUser.tOperation.nOpA ==UserOp.nFold)

	tUser.nTimeOutCnt =tUser.nTimeOutCnt +1
	tUser.isAuto =(tUser.nTimeOutCnt >=Define.TimeOutMax)
	--if tUser.tOperation.nOpB >0 then
	--	self:DoOpForUser(nPos,UserOp.nCall,tUser.tOperation.nOpB)
	if tUser.tOperation.nOpB ==UserOp.nPass then
		self:DoOpForUser(nPos,UserOp.nPass)
	else
		self:DoOpForUser(nPos,UserOp.nFold)
	end

	--通知机器人有人超时了，用以发表情
	self:_BroadCastToAndroidPlayer("UserOpTimeOut",{nPos=nPos,nTimeOutCnt=tUser.nTimeOutCnt})
end

function Table:_BroadCastToAndroidPlayer(strMsgName,tMsgData)
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.isAndroid then
			self:SendToUser(nPos,strMsgName,tMsgData)
		end
	end
end

function Table:TableId()
	return self.sTableId
end

function Table:_GetProtoArrPot()
	local arrPot ={}
	for _,v in ipairs(self.arrPoolInfo) do
		table.insert(arrPot,v.nPool)
	end
	return arrPot
end

function Table:_PrintPools()
	self:Print("arrPoolInfo:%s",tBase.tostring(self.arrPoolInfo))
end


function Table:GetScence()
	local tScenc ={}
	tScenc.nGroupId =self.nGroupId							--分组id
	tScenc.nRoomId  =self:MatchRoomId() or -1				--房间id
	tScenc.nTableType =self.nTableType						--桌子类型
	tScenc.nLiveUserID =self.nLiveUserID 					--主播ID
	tScenc.sLiveID =self.sLiveID 							--主播ID(app)
	tScenc.nSmallBlind=self.nSmallBlind						--小盲注数额
	tScenc.nBigBlind=self.nBigBlind							--大盲注数额(通常等于:小盲注x2)
	tScenc.nCapacity =self.nCapacity						--能供玩游戏的座位数
	tScenc.nOperateTime=self.nOperateTime					--操作最大时间,单位:秒 (通常为10)
	tScenc.nPotSum =self.nPotSum							--底池总额(已押筹码总额)
	tScenc.arrPool=self:_GetProtoArrPot()				    --底池
	tScenc.arrCommunityCards=self.arrCommunityCards 		--公共牌
	tScenc.nStage =self.nStage						   		--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	tScenc.isConfigNotSet =self.isConfigNotSet 				--本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	tScenc.tDeZhouConfigOption =self.tDeZhouConfigOption	--桌子可选配置(主播有)
	tScenc.isPause =self.isPause							--是否设置了暂停 true:是  false:否		 	
	tScenc.sPaiJuId =self.sPaiJuId							--牌局id
	tScenc.nJuShu =self.nJuShu								--当前局数
	tScenc.nBankerPos=self.nBankerPos 				--庄家位置
	tScenc.nTimeStart =self.nTimeStart						-->0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	tScenc.nBuyMin =self.nBuyMin	 				--最小买入
	tScenc.nBuyMax =self.nBuyMax					--最大买入
	tScenc.arrPartInUser ={}								--玩家位用户
	tScenc.sTableName =self.sTableName				--桌子名称 
	tScenc.nClubId=self.nClubId
	tScenc.nItemId =self.nItemId					--使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	tScenc.nGoldType =self.nGoldType				-- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)

	for nPos=1,self.nCapacity do
		local item =self:_GetProtoUserV2(nPos)
		if item then
			table.insert(tScenc.arrPartInUser,item)
		end
	end
	return tScenc
end

function Table:_GetProtoUserV2(nPos)
	local tUser =self.arrUsers[nPos]
	if tUser==nil then
		return
	end
	local isBanker =(self.nStage ~=TableState.nInit  and self.nBankerPos==nPos and tUser.nStatus ~=UserStatus.nLooker)
	local nCardType =self:_GetCardType(tUser.tCardType)
	local item ={}
	item.nUserId=tUser.nUserId		     	--玩家ID
	item.nSitId=nPos			 	 		--座位号
	item.sFaceId=tUser.sFaceId 			 	--头像url
	item.sName=tUser.sName			 		--昵称
	item.nSex=tUser.nSex	    	 		--性别 0:男 1:女
	item.nBalance=tUser.nBalance		 	--余额
	item.isBanker=isBanker		 			--是否为庄; true:是 ,false:否
	item.arrHoleCards=tUser.arrHoleCards 	--底牌(值为0的牌，显示牌背,表示还没亮牌)
	item.nCardType=nCardType				--牌型(见本文件头部"牌型定义")
	item.nBet =tUser.nBet				 	--玩家当轮当前下注数目(0时不要显示)
	item.nStatus=tUser.nStatus		 		--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
	item.nGetRightTime=tUser.nGetRightTime	--最近获得操作权时的时间戳
	item.isAuto=tUser.isAuto			 	--是否托管中
	item.sShopAccount =tUser.sShopAccount	--第三方用户ID
	item.isAndroid =tUser.isAndroid or false--是否机器人
	item.tOperation=tUser.tOperation		--当前自己可操作信息(自己为思考状态时有)
	item.tPreOpOption=tUser.tPreOpOption	--自己当前可预操作选项
	return item
end


function Table:_FindAPosForPlay()
	for nPos=1,self.nCapacity do
		if self.arrUsers[nPos] ==nil then
			return nPos
		end
	end
end

function Table:_IsPlayerPos(nPos)
	return (nPos>0 and nPos<=self.nCapacity)
end
function Table:_GetSitIdByUserId(nUserId)
	local nSitId =self.tUserIdToPos[nUserId]
	if nSitId then
		assert(self.arrUsers[nSitId]~=nil)
		assert(self.arrUsers[nSitId].nUserId==nUserId)
		return nSitId,self.arrUsers[nSitId]
	end
end

--广播到所有从服
function Table:_BroadCastToSlaves(sCmd,tData)
	local DZCRsp={}
	DZCRsp.sTableId =self.sTableId	
	DZCRsp.sCmd =sCmd
	DZCRsp.sJsonData=cjson.encode(tData)	--主从服通信内容主体用json格式
	DZCRsp.nEcho =-1
	tSlaveManager.Broadcast("DZCRsp",DZCRsp)
end
--发送到指定的一个从服
function Table:_SendToSlave(sReturnKey,sCmd,tData)
	if sReturnKey==nil then
		return
	end
	local DZCRsp={}
	DZCRsp.sTableId =self.sTableId	
	DZCRsp.sCmd =sCmd
	DZCRsp.sJsonData=cjson.encode(tData)	--主从服通信内容主体用json格式
	DZCRsp.nEcho =-1
	tSlaveManager.Send(sReturnKey,"DZCRsp",DZCRsp)
end

--广播有玩家取消托管通知
function Table:_BroadCastCancelAutoNotify(nSitId)
	--广播给从服
	self:_BroadCastToSlaves("CancelAutoNotify",{nPos =nSitId})
end

--广播发公共牌
function Table:_BroadCastDeZhouDealNotify(arrCardsNewAdd,isShowCard)
	--广播给从服
	local DealNotify={}
	DealNotify.nPotSum =self.nPotSum					--底池总额(已押筹码总额)
	DealNotify.arrPot =self:_GetProtoArrPot()			--收归的各底池数额(池数量:>0),数组索引代表池ID,索引从1开始
	DealNotify.arrCardsNewAdd=arrCardsNewAdd					--新增的公共牌
	DealNotify.isShowCard =isShowCard
	DealNotify.arrUser={}
	for _,pos in ipairs(self.arrPosPartIn) do
		local tUser =self.arrUsers[pos]
		assert(tUser~=nil)
		local item ={}
		item.nSitId =pos
		item.tPreOpOption =tUser.tPreOpOption
		local tCardType =tUser.tCardType or {}
		item.nCardType =tCardType.nCardType or 0
		item.nStatus =tUser.nStatus
		item.arrHoleCards =tUser.arrHoleCards
		table.insert(DealNotify.arrUser,item)
	end
	self:_BroadCastToSlaves("DealNotify",DealNotify)

	--主要是广播给机器人
	for nPos,tUser in pairs(self.arrUsers) do
		self:SendToUser(nPos,"DeZhouDealNotify",{arrCards=arrCardsNewAdd})
	end
end

--广播桌子关闭消息
function Table:_BroadCastTableCloseNotify(nReason)
	--广播给从服
	self:_BroadCastToSlaves("TableCloseNotify",{nReason=nReason})
end

--广播有玩家坐下
function Table:_BroadCastUserSitDownNotify(tUser)
	local item ={}
	item.nUserId=tUser.nUserId		     	 --玩家ID
	item.nSitId=tUser.nSitId			 	 --座位号
	item.sFaceId=tUser.sFaceId 			 	 --头像url
	item.sName=tUser.sName			 		 --昵称
	item.nSex=tUser.nSex	    	 		 --性别 0:男 1:女
	item.nBalance=tUser.nBalance		 	 --余额
	item.sShopAccount =tUser.sShopAccount	 --第三方用户ID
	item.isAndroid =tUser.isAndroid or false --是否机器人
	item.nStatus=tUser.nStatus		 		 --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
	item.nUnLockGold =self:Get_User_UnLockGold(tUser)
	self:_BroadCastToSlaves("UserSitDownNotify",{tUser=item})
end

--广播有玩家离开座位
function Table:_BroadCastUserStanpUpNotify(tUser)
	--广播给从服
	local nUnLockGold =self:Get_User_UnLockGold(tUser)
	self:_BroadCastToSlaves("UserStanpUpNotify",{nPos=tUser.nSitId,nUnLockGold=nUnLockGold})
end

--广播有玩家亮牌通知
function Table:_BroadCastShowCardNotify(nPos)
	--广播给从服
	self:_BroadCastToSlaves("ShowCardNotify",{nPos=nPos}) 
end

--广播表情聊天
function Table:_BroadCastDeZhouChatNotify(nSpeaker,nChatId,nTarget)
	--广播给从服
	local DeZhouChatNotify ={}
	DeZhouChatNotify.nSpeaker =nSpeaker
	DeZhouChatNotify.nChatId =nChatId
	DeZhouChatNotify.nTarget =nTarget
	self:_BroadCastToSlaves("DeZhouChatNotify",DeZhouChatNotify)
end

--广播有玩家获得操作权
function Table:_BroadCastGetRightNotify(tUser,nPosToGainRights)
	--广播给从服
	local GetRightNotify ={}
	GetRightNotify.nPos =nPosToGainRights
	GetRightNotify.tOperation =tUser.tOperation
	GetRightNotify.nGetRightTime =tUser.nGetRightTime
	GetRightNotify.nStatus =tUser.nStatus
	GetRightNotify.tPreOpOption =nil
	self:_BroadCastToSlaves("GetRightNotify",GetRightNotify)
	--广播给机器人
	local DeZhouOperationNotify={}
	DeZhouOperationNotify.nPos =nPosToGainRights 
	DeZhouOperationNotify.tOperation =tUser.tOperation
	for nPos,v in pairs(self.arrUsers) do
		self:SendToUser(nPos,"DeZhouOperationNotify",DeZhouOperationNotify)
	end 
end

--广播有玩家操作通知
function Table:_BroadCastOpNotify(nPos,nOp,nCallOrRaiseChip,tUser)
	--广播给从服
	local OpNotify ={}
	OpNotify.nPos =nPos
	OpNotify.nOp =nOp
	OpNotify.nCallOrRaiseChip =nCallOrRaiseChip
	OpNotify.isAuto =tUser.isAuto
	OpNotify.nStatus=tUser.nStatus
	OpNotify.arrPreOpOption ={}
	for _,pos in ipairs(self.arrPosPartIn) do
		local tem =self.arrUsers[pos]
		assert(tem~=nil)
		table.insert(OpNotify.arrPreOpOption,{nSitId=pos,tPreOpOption=tem.tPreOpOption})
	end
	self:_BroadCastToSlaves("OpNotify",OpNotify)
	--主要是广播给机器人
	local DeZhouOpNotify ={}
	DeZhouOpNotify.nPos =nPos							--座位号
	DeZhouOpNotify.nOp=nOp								---5:弃牌,  -1:AllIn, -2:看牌, -6:跟注, -3:加注
	DeZhouOpNotify.nBet=nCallOrRaiseChip 		    --跟注或加注时有效，表示具体的跟注\加注数值(>0)
	for nPos,_ in pairs(self.arrUsers) do
		self:SendToUser(nPos,"DeZhouOpNotify",DeZhouOpNotify)
	end
end

--广播游戏即将开始
function Table:_BroadToStart(nSeconds)
	local nMSeconds =nSeconds
	if nSeconds >0 then
		nMSeconds =nSeconds *1000
	end
	--广播给从服
	self:_BroadCastToSlaves("ToStartNotify",{nMSeconds =nMSeconds})
end

--广播游戏开始
function Table:_BroadCastGameStartNotify(nSmallBlindPos,nBigBlindPos,arrPosPartInSort,nZhuaTouPos)
	--广播给从服
	local GameStartNotify ={}
	GameStartNotify.nPotSum =self.nPotSum							--底池总额(已押筹码总额)
	GameStartNotify.nStage =self.nStage						   		--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	GameStartNotify.sPaiJuId =self.sPaiJuId							--牌局id
	GameStartNotify.nJuShu =self.nJuShu								--当前局数
	GameStartNotify.nBankerPos=self.nBankerPos 						--庄家位置
	GameStartNotify.nTimeStart =self.nTimeStart						-->0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	GameStartNotify.nSmallBlindPos =nSmallBlindPos					--小盲位置
	GameStartNotify.nBigBlindPos =nBigBlindPos						--大盲位置
	GameStartNotify.nZhuaTouPos =nZhuaTouPos						--抓头位置
	GameStartNotify.arrPartInUser={}
	for _,nPos in ipairs(arrPosPartInSort) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local item ={}
		item.nUserId=tUser.nUserId		     				--玩家ID
		item.nSitId=nPos			 	 					--座位号
		item.nBalance=tUser.nBalance		 				--余额
		item.isBanker=(self.nBankerPos==nPos)				--是否为庄; true:是 ,false:否
		item.arrHoleCards=tUser.arrHoleCards 				--底牌(值为0的牌，显示牌背,表示还没亮牌)
		item.nCardType=self:_GetCardType(tUser.tCardType)	--牌型(见本文件头部"牌型定义")
		item.nBet =tUser.nBet				 				--玩家当轮当前下注数目(0时不要显示)
		item.nStatus=tUser.nStatus		 					--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
		item.tPreOpOption=tUser.tPreOpOption				--自己当前可预操作选项
		item.nChipBuy =tUser.nChipBuy
		item.nUnLockGold =self:Get_User_UnLockGold(tUser)   --同步可用金币(主要服务于试玩房金币,其它一般以redis为准)
		table.insert(GameStartNotify.arrPartInUser,item)
	end
	self:_BroadCastToSlaves("GameStartNotify",GameStartNotify)

	--主要是广播给机器人
	local DeZhouStartNotify ={}
	DeZhouStartNotify.arrUsersBet={{nPos=nSmallBlindPos,nBet=self.nSmallBlind},{nPos=nBigBlindPos,nBet=self.nBigBlind}} 
	for nPos,tUser in pairs(self.arrUsers) do		
		DeZhouStartNotify.nTakeIn =tUser.nBalance
		DeZhouStartNotify.arrHoleCards =tUser.arrHoleCards
		self:SendToUser(nPos,"DeZhouStartNotify",DeZhouStartNotify)
	end
	return -1
end

--广播玩家筹码余额变动
function Table:_BroadCastDeZhouBalanceNotify(nPos,nBalance)
	--广播给从服
	self:_BroadCastToSlaves("DeZhouBalanceNotify",{nPos=nPos,nBalance=nBalance})
end

--广播配置更改
function Table:_BroadCastDeZhouConfigNotify(tConfigItem)
	local DeZhouConfigNotify ={}
	DeZhouConfigNotify.tConfigItem=tConfigItem
	DeZhouConfigNotify.nCapacity =self.nCapacity
	--广播给从服
	self:_BroadCastToSlaves("DeZhouConfigNotify",DeZhouConfigNotify)
end

--广播结算
function Table:_BroadCastSettleNotify(DeZhouSettleNotify)
	--广播给从服
	self:_BroadCastToSlaves("SettleNotify",DeZhouSettleNotify)
	--主要是广播给机器人
	for nPos,_ in pairs(self.arrUsers) do
		self:SendToUser(nPos,"DeZhouSettleNotify",DeZhouSettleNotify)
	end 
end

--广播桌子重置
function Table:_BroadCastTableResetNotify()
	--广播给从服
	self:_BroadCastToSlaves("TableResetNotify",{nStage=self.nStage})
	--主要是广播给机器人
	for nPos,_ in pairs(self.arrUsers) do
		self:SendToUser(nPos,"DeZhouTableResetNotify",{nNoUse=0})
	end
end

--发送数据接口
--//示例 : SendToUser(1,"RaiseReq",{nSitId=1,nRaiseChip=100})
function Table:SendToUser(nSitId,strMsgName,tMsgData)
	if self.isTableClose then
		return false
	end
	local tUserInfo =self.arrUsers[nSitId]
	if not tUserInfo then
		self:Print("_SendToUser Fail,can not find User of nSitId_%d  %s ",nSitId,strMsgName)
		return false
	end
	self.tInterFace.SendToUser(tUserInfo.nUserId,strMsgName,tMsgData)
	return true
end

function Table:OnUserEnter(tUserInfo,nPosForPlay)
	local nUserId =tUserInfo.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if nSitId  then
		self:Print("already in seat")
		return nil,nil,34
	end

	--设置位置上的玩家信息
	local tUser ={}
	tUser.nUserId=tUserInfo.nUserId
	tUser.sFaceId=tUserInfo.sFaceId or '1'
	tUser.sName=tUserInfo.sName or "No Name"
	tUser.nGold=tUserInfo.nGold or 0
	tUser.isAddFreeTimeIfStart =tUserInfo.isAddFreeTimeIfStart or false		--游戏开始时，免费场试玩次数是否加1
	
	tUser.nSex =tUserInfo.nSex or 0 --0:男 1:女
	tUser.isAndroid =tUserInfo.isAndroid
	tUser.nShopId=tUserInfo.nShopId or -1
	tUser.isOffLine =false		--是否掉线 废弃
	tUser.nOffLineCnt =0		--掉线+1 上线-1
	tUser.sShopAccount =tUserInfo.sShopAccount or ""

	tUser.nBuyTo =tUserInfo.nBuyTo or 0				--玩家设置的买入
	tUser.nIsAutoBuy =tUserInfo.nIsAutoBuy or 0		--玩家设置的是否自动每局买入

	tUser.nSitId=nil
	tUser.arrHoleCards={}		 	--底牌(值为0的牌，显示牌背,表示还没亮牌)
	tUser.nBet =0			 		 --玩家当轮当前下注数目(0时不要显示)
	tUser.nBetSum =0				 --当局总下注
	tUser.nStatus=UserStatus.nLooker --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
	tUser.nOpTimeRemain=0	 	 	 --剩余可操作(思考)时间 (思考中时有效,其它情况时为0)
	tUser.tOperation=nil			 --当前自己可操作信息(自己为思考状态时有)
	tUser.tPreOpOption=nil 			--自己当前可预操作选项
	tUser.tCardType=nil				--结算后存放牌型信息 {nCardType=nCardType,nComValue=nComValue,arrFiveBack=arrFiveBack}
	tUser.isToGainRights=false  	--是否即将获得操作权
	tUser.isNeedSettle =false   	--是否需要结算

	tUser.nChipBuy =0				--一局开始时新增的筹码买入
	tUser.nTimeOutCnt =0			--玩家超时次数
	tUser.isAuto =false				--是否托管 (托管时操作时间变短)

	tUser.isHaveOp=false        	--当局是否有操作
	tUser.nConsecutiveNoOp=0	--连续多少'局'没操作		
	tUser.nFee =0				--记录一局开始时扣减的手续费(废弃)

	tUser.isKickWhenEnd =false	--当局结束后是否踢出(强制站起)

	tUser.isShowCardWhenEnd =false --是否结束后亮牌
	tUser.arrPreSetHoleCard={} --预设置的底牌

	tUser.nGetChanceCnt =0		--当局获得操作机会的次数
	tUser.nGetRightTime =0      --最近一次获得操作权时的间戳

	tUser.nLockGoldInTable=0	--当前被锁在本桌子的金币
	tUser.nAiType =0			--机器人Ai类型;0一般 1进取 2保守

	--寻找一个空闲位置
	local nPosForPlay =nPosForPlay or self:_FindAPosForPlay()
	self:Print("_FindAPosForPlay %s",tostring(nPosForPlay))
	
	--如果不能坐下到牌局位置
	if not nPosForPlay then
		self:Print("OnUserEnter Fail,Find pos Fail")
		return nil,nil,14
	end
	assert(self:_IsPlayerPos(nPosForPlay))

	self:Print("todo: ------0:tUser.nBalance = %d", tUser.nBalance)
	local nBestTakeIn =self:_GetLatelyBalance(tUser.nUserId)
	if tUser.isAndroid then
		local arr = {}
		local nTabkeIn = self.nMinTabkeInBB
		self:Print("OnUserEnter self.nMinTabkeInBB: %.1f self.nMaxTabkeInBB: %0.1f  ",self.nMinTabkeInBB,self.nMaxTabkeInBB)
		for i = 1, 8, 1 do
			if nTabkeIn >= self.nMinTabkeInBB and nTabkeIn <= self.nMaxTabkeInBB then
				table.insert(arr,nTabkeIn)
				self:Print("OnUserEnter nTabkeIn: %0.1f  ",nTabkeIn)
			end 
			nTabkeIn = nTabkeIn + self.nMinTabkeInBB * 0.1
		end  
		local nRandom = math.random(1,#arr)
		nBestTakeIn =self.nBuyMin * nRandom    --机器人坐下时带入金币
		tUser.nLockGoldInTable = nBestTakeIn
		self:Print("OnUserEnter nBestTakeIn: %.1f  %d arr: %s  ",nBestTakeIn,nRandom,cjson.encode(arr))
	end

	--初始化带入金币
	if not self:_InitUserTakeIn(tUser,0) then  
		self:Print("OnUserEnter,Gold Not enough")
		return nil,nil,12
	end
	tUser.nBalance=tUser.nLockGoldInTable	--当前可用筹码

	self:_SetSitInSeat(nPosForPlay,tUser,true)
	tPubUser.IncrUnbalancedBy(tUser.nUserId,1)
	return tUser,nPosForPlay,0
end



--玩家游戏中离开(站起),调用时还没离开
function Table:_LeaveInPlaying(tUser)
	self:Print("_LeaveInPlaying,nPos:%d nUserId:%d",tUser.nSitId,tUser.nUserId)
	assert(not self.isBanStandUpReq)

	self:_CollectBetToPoolsN({tUser.nSitId})		--收归玩家下注到底池
	self:_UserChipsSettle(tUser,{},false)			--结算
	local nRmCnt =_removeItem( self.arrPosPartIn,tUser.nSitId,true)
	assert(nRmCnt==1)
	self.tReview:LeaveInPlaying(tUser.nSitId)		--回顾记录
	
	if self.isGapOfNow or self.isTableError then --正在跳转到下一轮或结算
		self:_ResetUser(tUser)
		return
	end

	--如果玩家当前获得了操作权或即将获得操作权, 则需要结束其操作权
	if tUser.nStatus ==UserStatus.nThinking or tUser.isToGainRights then
		self:_SetUserStatus(tUser,UserStatus.nFold)
		self:_OpEnd(tUser.nSitId)
	else
		local nTheOnlyNotFoldPos,tNotFoldUser =self:_IsJustOneNotFoldInCurRound()
		if nTheOnlyNotFoldPos then
			self:Print("Remain One NotFoldUser:%d",nTheOnlyNotFoldPos)
			assert(tNotFoldUser.nStatus==UserStatus.nThinking or tNotFoldUser.isToGainRights)
			self:_CancelRights(tNotFoldUser)
			self:_SetUserStatus(tNotFoldUser,UserStatus.nWaitForOp)
			self:_ToNextRound(0.2)
		end
	end
	self:_ResetUser(tUser)
end


function Table:_IncrUserCountBy(nIncrValue,isAndroid,nUserID)
	if isAndroid == false then
		tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,{sitId=nUserID})
	end
	self.nUserCnt =self.nUserCnt +nIncrValue
	if not isAndroid then
		self.nUserCntOfReal=self.nUserCntOfReal +nIncrValue
		--if self.nUserCntOfReal==0 then
		--	self.nTimestampZeroRealUser=os.time()
		--end
	end
	if self.nClubId then
		local tTableInfo ={}
		tTableInfo.nNowCnt =self.nUserCnt
		tPublicClub.ClubTableInfoNotify(self.nClubId,self.sTableId,tTableInfo)
	end
end

--坐下
function Table:_SetSitInSeat(nPos,tUser,isNotifySelf)
	self.arrUsers[nPos]=tUser
	self.tUserIdToPos[tUser.nUserId] =nPos
	self:_IncrUserCountBy(1,tUser.isAndroid,tUser.nUserId)
	tUser.nSitId =nPos
	tUser.nConsecutiveNoOp =0
	
	self:_BroadCastUserSitDownNotify(tUser)
	self:_TryToStartGame()
	tPubUser.SetUserSeatStatus(tUser.nUserId,true)
	
	self:Print("_SetSitInSeat nPos:%d nUserId:%d nUserCnt:%d",nPos,tUser.nUserId,self.nUserCnt)
	self.tUserNameToIsUsed[tUser.sName]= true
end


function Table:_SetLeaveSeat(nSitId,isNotifySelf)
	local tUser =self.arrUsers[nSitId]
	assert(tUser~=nil,'Err happen')

	--是否游戏中途退出(需收归下注、结束操作权等)
	if tUser.isNeedSettle and self:_IsPartInUser(nSitId) then	
		self:_LeaveInPlaying(tUser)
	end
	tPubUser.SetUserSeatStatus(tUser.nUserId,false)
	self.arrUsers[nSitId] =nil
	self.tUserIdToPos[tUser.nUserId] =nil

	self:_IncrUserCountBy(-1,tUser.isAndroid,tUser.nUserId)
	
	self.tUserNameToIsUsed[tUser.sName]= nil
	self:_ResetUser(tUser)

	self:_UserBalanceToGold(tUser)
	tPubUser.IncrUnbalancedBy(tUser.nUserId,-1)
	self.tInterFace._LeaveTable(tUser.nUserId,self)

	self:_BroadCastUserStanpUpNotify(tUser)
	self:_TryToStartGame()

	self:Print("_SetLeaveSeat nSitId:%d nUserId:%d  ",nSitId,tUser.nUserId)
	return tUser
end


--是否是正在参与牌局的玩家
function Table:_IsPartInUser(nPos)
	if self.nStage ==TableState.nInit then
		return false
	end
	return _IsHaveEle(self.arrPosPartIn,nPos)
end


--强制玩家站起
function Table:_ForceStandUp(nSitId,nCode)
	local tUser =self:_SetLeaveSeat(nSitId)
	self:Print("_ForceStandUp,nPos:%d nUserId:%d nCode:%s",nSitId,tUser.nUserId,tostring(nCode))
	if nCode then
		self:SendFailNotifyV2(nil,tUser.nUserId,nCode,"_ForceStandUp")
	end
end

function Table:_GetProtoTakeInRange(tUser)
	if tUser==nil then 
		return nil
	end
	local nUnLockGold =self:Get_User_UnLockGold(tUser)
	local DeZhouTakeInRangeRsp ={}
	DeZhouTakeInRangeRsp.nGold =nUnLockGold		--当前身上金币
	DeZhouTakeInRangeRsp.nMin=self.nBuyMin		--最小买入
	DeZhouTakeInRangeRsp.nMax =self.nBuyMax		--最大买入
	DeZhouTakeInRangeRsp.nIsAuto =tUser.nIsAutoBuy  --是否每局自动买入 1:是 其它:否
	return DeZhouTakeInRangeRsp
end

function Table:RandomTakeInForAndroid()
	if math.random(1,100) <=55 then return end
	return math.random(self.nBuyMin,self.nBuyMax)
end

-- 1 2 3 4 分别对应公共牌数量 0 3 4 5
function Table:_GetAiStage()
	local n =#self.arrCommunityCards
	if n==0 then
		return 1
	elseif n==3 then
		return 2
	elseif n==4 then
		return 3
	elseif n==5 then
		return 4
	end
	return -1  --ERROR
end

function Table:_GetAiUser(nPos)
	local tUser =self.arrUsers[nPos]
	if not tUser then
		return 
	end
	local item ={}
	item.nState=tUser.nStatus						--玩家当轮最近的操作 0:还未操作 1:正在思考操作中(自己) 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌
	item.nBet=tUser.nBet							--玩家当轮的下注数目
	item.nBetSum=tUser.nBetSum						--玩家开局至今的总下注数目
	item.nRemain=tUser.nBalance						--当前剩余筹码
	item.arrHoleCard=tUser.arrHoleCards				--底牌(2个)
	item.isAndroid=tUser.isAndroid					--是否是机器人
	item.nType=tUser.nAiType						--0一般 1进取 2保守
	item.nUserId=tUser.nUserId
	item.arrHistory={}								--玩家在各阶段的操作次数
	item.isEnableAdd=true							--当前轮是否能加注
	return item
end

function Table:_UpdateAiUsers(nSelfUserId)
	local nSelfDex =-1
	local nLeaderDex =-1
	for nDex,item in ipairs(self.arrAiUser) do
		local _,tUser =self:_GetSitIdByUserId(item.nUserId)
		if tUser then
			item.nPos= nDex									--玩家座位号
			item.nState=tUser.nStatus						--玩家当轮最近的操作 0:还未操作 1:正在思考操作中(自己) 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌
			item.nBet=tUser.nBet							--玩家当轮的下注数目
			item.nBetSum=tUser.nBetSum						--玩家开局至今的总下注数目
			item.nRemain=tUser.nBalance						--当前剩余筹码
			item.arrHoleCard=tUser.arrHoleCards				--底牌(2个)
		else
			item.nState=UserOp.nFold
		end
		if item.nUserId ==nSelfUserId then
			nSelfDex =nDex-1			--返回从0开始的索引，所以-1
		end
		if item.nUserId ==self.nUserIdLeader then
			nLeaderDex=nDex-1			--返回从0开始的索引，所以-1
		end
		item.isEnableAdd =(item.nState~=UserOp.nFold and item.nState~=UserOp.nAllIn and item.nState~=UserOp.nRaise)
	end
	return self.arrAiUser,nSelfDex,nLeaderDex				
end

function Table:_AddOpCount(nUserId,Op)
	local nStage =0
	if #self.arrCommunityCards==0 then
		nStage=0
	elseif #self.arrCommunityCards==3 then
		nStage=1
	elseif #self.arrCommunityCards==4 then
		nStage=2
	elseif #self.arrCommunityCards==5 then
		nStage=3
	end
	local Item ={}
	Item.nStage=nStage			
	Item.nFollowCnt=0			
	Item.nPassCnt=0			
	Item.nRaiseCnt=0			
	Item.nAllInCnt=0		
	Item.nGiveUpCnt=0		
	Item.nFollowAllIn=0		--这个没统计到 先这样
	local sKey =string.format("%d_%d",nUserId,nStage)
	local tInfo =self.tOpHistory[sKey] or Item
	if Op ==UserOp.nFold then
		tInfo.nGiveUpCnt =tInfo.nGiveUpCnt +1
	elseif Op ==UserOp.nAllIn then
		tInfo.nAllInCnt =tInfo.nAllInCnt +1
	elseif Op ==UserOp.nPass  then
		tInfo.nPassCnt =tInfo.nPassCnt +1
	elseif Op ==UserOp.nRaise then
		tInfo.nRaiseCnt =tInfo.nRaiseCnt +1
	elseif Op == UserOp.nCall then
		tInfo.nFollowCnt =tInfo.nFollowCnt +1
	end
	self.tOpHistory[sKey] =tInfo
end

function Table:_GetUserOpHistory(nUserId)
	local arr ={}
	for nStage=0,3 do
		local sKey =string.format("%d_%d",nUserId,nStage)
		local tInfo=self.tOpHistory[sKey]
		if tInfo then
			table.insert(arr,tInfo)
		else
			break
		end
	end
	return arr
end

--返回的数据不能改动(因为有些table不是copy的)
function Table:GetAiScence(nSelfUserId,tOperation)
	local tS ={}	
	tS.sTableId =self.sTableId or "-1"   			 
	tS.sPaiJuId =self.sPaiJuId or "-1"   	
	tS.nGameId =Define.nGameId
	tS.nGroupId =self.nGroupId
	tS.nRoomId =self.nRoomId	 

	tS.nLevel = RedisCahche._GetTexasAndroidLevelCfg(self.nGroupId,Define.nGameId,self.nRoomId)
	tS.bControl = false 
	if self.isControl and (self.isControl==2 or self.isControl==3) then 
		tS.bControl = true 
	end  
	tS.nStage =self:_GetAiStage()											--1 2 3 4 分别对应公共牌数量 0 3 4 5
	tS.nBankerPos=self.nBankerPos  	    									--庄家位置
	tS.nCapacity =self.nCapacity											--能供玩游戏的座位数
	tS.nSmallBlind=self.nSmallBlind											--小盲注数额
	tS.nBigBlind=self.nBigBlind												--大盲注数额(通常为小盲的两倍)
	tS.arrUser,tS.nSelfDex,tS.nLeaderDex =self:_UpdateAiUsers(nSelfUserId)	--参与本局的玩家,第一个为庄(按钮位置),按顺时针排序(行动顺序);
	tS.arrCommunityCard=self.arrPreSetCommCardCp							--当前公共牌(最多5个牌)
	tS.arrPool=self:_GetProtoArrPot()										--当前桌面底池

	for _,tU in ipairs(tS.arrUser) do
		tU.arrHistory=self:_GetUserOpHistory(tU.nUserId)
	end

	if tOperation.nOpB ==UserOp.nAllIn or tOperation.nOpC ==UserOp.nAllIn then
		tS.nAllIn =100								--能否AllIn标识(>0:AllIn的筹码数目, -1:不能AllIn)
	else
		tS.nAllIn =-1
	end

	if tOperation.nOpB>0 then
		tS.nFollow=tOperation.nOpB					--能否跟注标识 (>0:跟注的筹码数目, -1:不能跟注)
	else
		tS.nFollow=-1
	end

	if tOperation.nOpC ==UserOp.nRaise then
		local tRaiseChoice =tOperation.tRaiseChoice or {}
		local nRaiseMin =tRaiseChoice.nMin or 0
		local nRaiseMax =tRaiseChoice.nMax or 0
		tS.arrRaiseRange={nRaiseMin,nRaiseMax}		--能否加注标识 (数组长度2时:表示加注范围[Low,Top], 其它长度或nil:不能加注)
	end

	tS.isCanPass =(tOperation.nOpB==UserOp.nPass)	--能否过牌标识 (true:能 false:否)
	
	--确定大小盲玩家位置
	if #tS.arrUser==2 then
		tS.nSmallBlindDex =0    --小盲玩家索引(索引从0开始)
		tS.nBigBlindDex =1 		--大盲玩家索引(索引从0开始)
	else
		tS.nSmallBlindDex =1   --小盲玩家索引(索引从0开始)
		tS.nBigBlindDex =2 		--大盲玩家索引(索引从0开始)
	end
	tS.nBetDiff =self.nTheHighestBet- tS.arrUser[tS.nSelfDex+1].nBet	--当轮桌面最高下注和自己下注的相差值 (最高注-自己下注)

	tS.nFirstBet =self.nFirstBet			--本桌大小盲累计下注总额
	tS.nTheHighestBet=self.nTheHighestBet	--当轮桌面最高下注
	return tS,self.sAiUrl
end

--
function Table:Print(str,...)
	--if self.nLiveUserID==0 then return end
	tBase.Log(self.sTableId.."_"..self.nJuShu.."=>"..str,...)
end

-- 广播信息: 转发消息, 通知旁观服
function Table:TransmitProtobuf(strProto,tSendData)  
    return
end 

-- 通知旁观服: 维护旁观服的场景 
function Table:BroadCastLookerSrv(tData) 
end 


return Table
