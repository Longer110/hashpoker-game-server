
local tBase 	  = require("base")         -- 基础功能接口
local RecordDbr =require("RecordDbr")
local tPubUser = require("PublicUserInfo") -- 用户信息
local tConfig =require("GameConfig") -- 
local tTimerAux =require("TimerAux")
local cjson    = require("cjson")
local tPublicRedis =require("PublicRedis")
local publicApi =require("publicApi")
local json    = require("json")
local tRedisCahche=	require("RedisCahche")
local tAlg =require("Alg")
local tTbBind =require("TbBind")
local tSlaveManager =require("SlaveManage")
local Define =require("Define")
local tname = require("typename")
local BaseSink =require("BaseSink")


local GoldCReason =Define.GoldCReason

local LoopType={}	--开赛时间循环方式
LoopType.Month=1	--1按月
LoopType.Week=2		--2按周
LoopType.Day=3		--3按天
LoopType.Once=4		--4按次
LoopType.FixTest=5	--5测试循环方式，结束后离开开始下一轮. 报名时间为5分钟

--赛事阶段
local Stage={}
Stage.Init=0
Stage.SignUp=1		--报名阶段
Stage.Before=2		--可进入比赛阶段
Stage.Begin=3		--可延迟报名阶段
Stage.After=4		--比赛阶段(截止报名)
Stage.Rank=5		--排名阶段
Stage.Award=6		--奖励阶段
Stage.End=10		--比赛结束阶段


--用户状态,属于协议的一部分(莫改,包括名称)
local Ustatus={}
Ustatus.Sign=1		--已报名
Ustatus.NotSign=0	--未报名
Ustatus.Oust=2		--已淘汰
Ustatus.Bind=3		--已经绑定到比赛桌

--可进行的操作 1报名 2取消报名 3进入比赛 4延迟报名 5观战  0不能操作(未报名时有:1,4,5; 已报名时有:2,3,5;已淘汰时:5) 
local Op={}
Op.Sign=1
Op.SignCancel=2
Op.Enter=3
Op.SignDelay=4
Op.Watch=5
Op.Ban=0

--参赛费支付方式
local PayType={}
PayType.Coin="Coin"			--金币支付
PayType.Ticket="Ticket"		--门票支付
PayType.Free="Free"		--免费

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


local Match = {}

function Match:New(nEventId,tInterface,tCfg)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	assert(tCfg~=nil)
	t.tInterface=tInterface
	t.Timer =tTimerAux:New()
	t.TimerWaitRoom  =tTimerAux:New()
	t.TimerRuleD  =tTimerAux:New()

	t.nStage =Stage.Init
	t.nJuShu =0
	t.nStatus=-1								--赛事状态 -1:没开始(不能报名) 0:进行中 1:结束
	t.nTimeStampBegin=os.time()+3600*24*500		--开赛时间戳
	
	--s
	t.nTestMatchTime=tCfg.nTestMatchTime --比赛时间(测试)
	t.CloseTime=3600	--关闭时间 秒(单次比赛结束后多久进行关闭入口)
	t.RankTime=2		--排名阶段时间 秒
	t.AwardTime=2		--奖励阶段时间 秒
	t.EndTime =2		--结束阶段时间
	t.MatchTime=2		--匹配时间

	--s
	assert(tCfg.sUkey~=nil,"sUkey is nil")
	t.nGroupId =tCfg.nGroupId									--分组id
	t.sKeyRedisCfg =tCfg.sKeyRedisCfg							--redis配置哈希表键
	t.sFieldRedisCfg=tCfg.sFieldRedisCfg						--redis配置哈希表Field
	t.sUkey=tCfg.sUkey											--历史唯一赛事id
	t.nEventId=nEventId											--赛事id (本次服务运行唯一id)
	t.sName=tCfg.sName or "赛事名称"							 --赛事名称
	t.sBackground=tCfg.sBackground or ""						--背景图url (空字符串时,前端默认一个图)
	t.nTimeBefore=tCfg.nTimeBefore or 120						--开赛前时间 秒(期间内，已报名者可"进入比赛")
	t.nTimeAfter=tCfg.nTimeAfter or 120							--开赛后时间 秒(期间内，未报名者可"延迟报名",超过后所有人仅能"观战")
	t.nUserCntMax=tCfg.nUserCntMax or 100						--最大报名人数
	t.nTakeIn=tCfg.nTakeIn or 1000								--初始记分牌
	t.nCntBegin=tCfg.nCntBegin or 10							--最小开赛人数
	t.nBlindUpGap=tCfg.nBlindUpGap or 180						--涨盲时间 秒
	t.nUserCntOfTable=tCfg.nUserCntOfTable or 6					--单桌人数

	--报名费s
	t.tFeeSignUp={}  				
	t.tFeeSignUp.nFeeType=tCfg.tFeeSignUp.nFeeType or 3			--费用类型,1免费 2仅门票 3金币或门票
	t.tFeeSignUp.nTicketNeed=tCfg.tFeeSignUp.nTicketNeed or 1	--所需门票数量					(nFeeType 2或3时有效)
	t.tFeeSignUp.nFeeA=tCfg.tFeeSignUp.nFeeA or 10000			--参赛费					   (nFeeType 3时有效)
	t.tFeeSignUp.nFeeB=tCfg.tFeeSignUp.nFeeB or 1000			--报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--重购费s
	t.tFeeR={}	  	
	t.tFeeR.nFeeType=tCfg.tFeeR.nFeeType or 3		--费用类型,1免费 2仅门票 3金币或门票
	t.tFeeR.nTicketNeed=tCfg.tFeeR.nTicketNeed or 1	--所需门票数量					(nFeeType 2或3时有效)
	t.tFeeR.nFeeA=tCfg.tFeeR.nFeeA or 10000			--参赛费					   (nFeeType 3时有效)
	t.tFeeR.nFeeB=tCfg.tFeeR.nFeeB or 1000			--报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--增购费s
	t.tFeeA={}	  			
	t.tFeeA.nFeeType=tCfg.tFeeA.nFeeType or 3		--费用类型,1免费 2仅门票 3金币或门票
	t.tFeeA.nTicketNeed=tCfg.tFeeA.nTicketNeed or 1	--所需门票数量					(nFeeType 2或3时有效)
	t.tFeeA.nFeeA=tCfg.tFeeA.nFeeA or 10000			--参赛费					   (nFeeType 3时有效)
	t.tFeeA.nFeeB=tCfg.tFeeA.nFeeB or 1000			--报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--重购规则s
	t.tEvtTakInR={}
	t.tEvtTakInR.nLevel=tCfg.tEvtTakInR.nLevel or 5 	--盲注级别
	t.tEvtTakInR.nCnt=tCfg.tEvtTakInR.nCnt or 10		--可购次数
	t.tEvtTakInR.nChip=tCfg.tEvtTakInR.nChip or 1000	--增加的筹码数量

	--增购规则s
	t.tEvtTakInA={}		
	t.tEvtTakInA.nLevel=tCfg.tEvtTakInA.nLevel or 6 	--盲注级别
	t.tEvtTakInA.nCnt=tCfg.tEvtTakInA.nCnt or 10		--可购次数
	t.tEvtTakInA.nChip=tCfg.tEvtTakInA.nChip or 1000	--增加的筹码数量
	
	--升盲列表s
	t.arrLvItem={}
	for nD,v in ipairs(tCfg.arrLvItem) do
		--级别 小盲 大盲 重购标识 前注(1:可重购 2:可增购 0:不能购)
		local nRA =0
		if nD<=t.tEvtTakInR.nLevel then
			nRA =1
		elseif nD==t.tEvtTakInA.nLevel then
			nRA =2
		end
		table.insert(t.arrLvItem,{nLv=nD,nSmallB=v.nSmallB,nBigB=v.nBigB,nRA=nRA,nPreAnte=v.nPreAnte}) 
	end

	--开赛循环方式s
	t.tTRule ={}
	t.tTRule.nLoopType =tCfg.tTRule.nLoopType or 1	--1按月 2按周 3按天 4按次
	t.tTRule.nZone =tCfg.tTRule.nZone or 8			--参数所用时区(8为北京时区)
	t.tTRule.nYear=tCfg.tTRule.nYear or 2024		--年 (按次时有效)
	t.tTRule.nMonth=tCfg.tTRule.nMonth or 12		--月 (按次时有效;1~12)
	t.tTRule.nMonthday=tCfg.tTRule.nMonthday or 1	--日 (1~28)
	t.tTRule.nHour=tCfg.tTRule.nHour or 23			--时(0~23)
	t.tTRule.nMin=tCfg.tTRule.nMin or 30			--分(0~59)
	t.tTRule.nSec=tCfg.tTRule.nSec or 0				--秒(0~59)
	t.tTRule.nWeekday=tCfg.tTRule.nWeekday or 1		--(1~7) 一周里的第几天 （按周时有效;1=星期日,7=星期六,）
	t.tTRule.nLoopSec=tCfg.tTRule.nLoopSec or 300   --按次循序周期 秒

	--奖励列表s
	t.nAwardType =tCfg.nAwardType					--奖励方式 1:固定 2:奖池百分比
	t.arrAward={}
	for _,v in ipairs(tCfg.arrAward or {}) do
		table.insert(t.arrAward,{nRank=v.nRank,nCoin=v.nCoin,nTicket=v.nTicket}) --排名 奖励金币 奖励门票
	end
	--nPercent 30 即是30%
	t.arrAwardPercent={}
	for _,v in ipairs(tCfg.arrAwardPercent or {}) do
		table.insert(t.arrAwardPercent,{nRank=v.nRank,nPercent=v.nPercent,nTicket=v.nTicket})
	end
	--游戏id s
	t.nGameId =tCfg.nGameId				

	--非配置
	t.tUserIdToUser={}						--记录有报名过的玩家信息(真人)
	t.tUserIdToAndroid={}					--记录报名的机器人
	t.tOx =tTbBind:New(t.nUserCntOfTable)	--记录玩家与比赛桌的绑定关系
	t.nServId =nil							--记录所使用的游戏中心服id
	t.sWaitRoomTalbeId=nil					--等待室桌子id(用于玩家等待分配桌子)
	t.nMttUserCnt =0						--当前比赛人数
	t.nUserCnt=0							--当前报名人数
	t.nMttTableCnt=0						--当前已请求创建的桌子数
	t.isCanDynamicAddMttTable=false			--当前是否允许动态新增比赛桌子 (视报名人数而定)
	t.isEnd=false							--比赛是否结束

	t.isSetClose=false						--是否设置了关闭比赛
	return t
end

function Match:GroupId()
	return self.nGroupId
end
function Match:EventId()
	return self.nEventId
end
function Match:GameId()
	return self.nGameId
end
function Match:UKey()
	return self.sUkey
end

--协议 赛事列表元素
function Match:GetProtoItemInfo(nUserId)
	local item={}
	item.nEventId=self.nEventId					--赛事ID
	item.sName=self.sName						--赛事名称
	item.sBackground=self.sBackground			--背景图url (空字符串时,前端默认一个图)
	item.nStatus=self.nStatus					--赛事状态 1:比赛已结束 0:正常
	item.nTimeStampBegin=self.nTimeStampBegin	--开赛时间戳
	item.nTimeBefore=self.nTimeBefore			--开赛前时间 秒(期间内，已报名者可"进入比赛")
	item.nTimeAfter=self.nTimeAfter				--开赛后时间 秒(期间内，未报名者可"延迟报名",超过后所有人仅能"观战")
	item.nUserCnt=self.nUserCnt					--当前报名人数
	item.nUserCntMax=self.nUserCntMax			--最大报名人数	(比赛信息页面=>规则 静态部分)
	item.nTakeIn=self.nTakeIn					--初始记分牌 	(比赛信息页面=>规则 静态部分)
	item.nCntBegin=self.nCntBegin				--最小开赛人数  (比赛信息页面=>规则 静态部分)
	item.nBlindUpGap=self.nBlindUpGap			--涨盲时间 秒   (比赛信息页面=>规则 静态部分)
	item.nUserCntOfTable=self.nUserCntOfTable	--单桌人数		(比赛信息页面=>规则 静态部分)
	item.nGameId =self.nGameId					--游戏id (125:普通德州 126:奥哈马 175:短牌)
	
	--报名费 (比赛信息页面=>规则 静态部分)
	item.tFeeSignUp={}  	
	item.tFeeSignUp.nFeeType =self.tFeeSignUp.nFeeType			--费用类型,1免费 2仅门票 3金币或门票
	item.tFeeSignUp.nTicketNeed =self.tFeeSignUp.nTicketNeed	--所需门票数量					(nFeeType 2或3时有效)
	item.tFeeSignUp.nFeeA =self.tFeeSignUp.nFeeA				--参赛费					   (nFeeType 3时有效)
	item.tFeeSignUp.nFeeB =self.tFeeSignUp.nFeeB				--报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--重购费 (比赛信息页面=>规则 静态部分)	
	item.tFeeR={}	
	item.tFeeR.nFeeType=self.tFeeR.nFeeType			--费用类型,1免费 2仅门票 3金币或门票
	item.tFeeR.nTicketNeed=self.tFeeR.nTicketNeed	--所需门票数量					(nFeeType 2或3时有效)
	item.tFeeR.nFeeA=self.tFeeR.nFeeA				--参赛费					   (nFeeType 3时有效)
	item.tFeeR.nFeeB=self.tFeeR.nFeeB				--报名服务费 或重购费 或增购费 	(nFeeType 3时有效)

	--增购费 (比赛信息页面=>规则 静态部分)
	item.tFeeA={}		  		
	item.tFeeA.nFeeType=self.tFeeA.nFeeType			--费用类型,1免费 2仅门票 3金币或门票
	item.tFeeA.nTicketNeed=self.tFeeA.nTicketNeed	--所需门票数量					(nFeeType 2或3时有效)
	item.tFeeA.nFeeA=self.tFeeA.nFeeA				--参赛费					   (nFeeType 3时有效)
	item.tFeeA.nFeeB=self.tFeeA.nFeeB				--报名服务费 或重购费 或增购费 	 (nFeeType 3时有效)
	
	--重购规则(比赛信息页面=>规则 静态部分)
	item.tEvtTakInR={}		
	item.tEvtTakInR.nLevel=self.tEvtTakInR.nLevel 	--盲注级别
	item.tEvtTakInR.nCnt=self.tEvtTakInR.nCnt		--可购次数
	item.tEvtTakInR.nChip=self.tEvtTakInR.nChip		--增加的筹码数量

	--增购规则(比赛信息页面=>规则 静态部分)
	item.tEvtTakInA={}		
	item.tEvtTakInA.nLevel=self.tEvtTakInA.nLevel 	--盲注级别
	item.tEvtTakInA.nCnt=self.tEvtTakInA.nCnt		--可购次数
	item.tEvtTakInA.nChip=self.tEvtTakInA.nChip		--增加的筹码数量

	--(比赛信息页面=>盲注列表)
	item.arrLvItem={}		
	for _,v in ipairs(self.arrLvItem) do
		local t={}
		t.nLv=v.nLv
		t.nSmallB=v.nSmallB
		t.nBigB=v.nBigB
		t.nRA=v.nRA
		t.nPreAnte=v.nPreAnte
		table.insert(item.arrLvItem,t)
	end

	--(比赛信息页面=>规则 动态部分,比赛中才有)
	item.tSt=self:_GetProtoRuleD()
	--当前显示的操作按钮 1报名 2取消报名 3进入比赛 4延迟报名 5观战  0不能操作(未报名时有:1,4,5; 已报名时有:2,3,5;已淘汰时:5)
	item.nOp=self:_GetOpCan(nUserId,false)			
	--当前报名状态 0:未报名 1:已报名 2:已淘汰
	item.nSignUp=self:_GetUserStatus(nUserId)		
	--拥有的门票数量
	item.nTicketOwn=self:_GetTicketOwn(nUserId)		
	return item
end

--(比赛信息页面=>规则 动态部分,比赛中才有) 
function Match:_GetProtoRuleD()
	local nLv,nBlindUpR =self:_CalBlindLv()
	local t={}
	t.nUserCnt=self:_AddMttUserCnt(0)		--比赛剩余人数
	t.nChipAvg=self:_CalChipAvg()			--平均记分牌
	t.nBlindUpR=nBlindUpR					--涨盲剩余时间 秒 (前端需要自己倒计时至0)
	t.nBlindLevel=nLv						--当前盲注级别
	t.nLevelUpTo=self.tEvtTakInR.nLevel		--截止买入级别
	return t
end

function Match:_BroadCastRuleD()
	local tNotify={}
	tNotify.nEventId=self.nEventId				--赛事ID
	if self.isEnd then
		tNotify.nRlt=1							--0:成功 1:比赛已结束
	else
		tNotify.nRlt=0							--0:成功 1:比赛已结束
		tNotify.tSt=self:_GetProtoRuleD()		--
	end
	self.tInterface.SendToUsersOfOpen("TEvtRuleDNotify",tNotify)
end

function Match:_ToBroadCastRuleD(nDelaySec)
	local nDelaySec=nDelaySec or 3
	self.TimerRuleD:KillAllTimer()
	self.TimerRuleD:DelayCall(nDelaySec*1000,self._BroadCastRuleD,self)
end

--返回:盲注级别,剩余升盲时间
function Match:_CalBlindLv()
	local nNow =os.time()
	local diff =nNow -self.nTimeStampBegin
	diff=math.max(diff,1)
	local nLv =1						--当前盲注级别
	if self.nBlindUpGap>0 then
		nLv =math.ceil(diff/self.nBlindUpGap) 
	end
	nLv = math.min(#self.arrLvItem,nLv)
	local nBlindUpR =nil				--剩余升盲时间 秒
	if nLv >= #self.arrLvItem then
		nBlindUpR =-1
	else
		nBlindUpR =self.nTimeStampBegin +nLv *self.nBlindUpGap -nNow
		nBlindUpR =math.max(0,nBlindUpR)
	end
	return nLv,nBlindUpR
end

function Match:_CalChipAvg()
	local nSum=0
	local nCnt=0
	for _,v in pairs(self.tUserIdToUser) do
		if v.nChip>=0 and (v.nStatus ==Ustatus.Sign or v.nStatus ==Ustatus.Bind) then
			nSum =nSum +v.nChip
			nCnt =nCnt +1
		end
	end
	for _,v in pairs(self.tUserIdToAndroid) do
		if v.nChip>=0 and (v.nStatus ==Ustatus.Sign or v.nStatus ==Ustatus.Bind) then
			nSum =nSum +v.nChip
			nCnt =nCnt +1
		end
	end
	if nCnt >0 then
		return math.floor(nSum/nCnt)
	end
	return 0
end

--是否允许延迟进入比赛 (视当前入场人数而定)
function Match:_IsAllowDelayEnter()
	local nCnt =self:_AddMttUserCnt(0) --入场人数
	if nCnt ==0 then
		nCnt =self:_AddSignCnt(0)		--报名人数
	end
	return nCnt > (2*#self.arrAward)
end


--当前可进行的操作
--isDoOp:true(用来判断玩家操作的合法性) ,false或nil(用来显示比赛入口的可操作按钮)
function Match:_GetOpCan(nUserId,isDoOp)
	local nStatus =self:_GetUserStatus(nUserId)
	local nStage=self.nStage

	--未报名时
	if nStatus ==Ustatus.NotSign then	
		if nStage==Stage.SignUp or nStage==Stage.Before then
			return Op.Sign
		end
		if nStage==Stage.Begin then
			if isDoOp and (not self:_IsAllowDelayEnter()) then
				return Op.Watch,5
			end
			return Op.SignDelay
		end
		if nStage==Stage.After then
			return Op.Watch
		end
		return Op.Ban
	end
	--已报名时
	if nStatus ==Ustatus.Sign then
		if nStage==Stage.SignUp then
			return Op.SignCancel
		end
		if nStage==Stage.Before then
			return Op.Enter
		end
		if nStage==Stage.Begin then
			if isDoOp and (not self:_IsAllowDelayEnter()) then
				return Op.Watch,5
			end
			return Op.Enter
		end
		if nStage==Stage.After then
			return Op.Watch
		end
		return Op.Ban
	end
	--已淘汰时
	if nStatus ==Ustatus.Oust then
		if nStage==Stage.Begin or nStage==Stage.After then
			return Op.Watch
		end
		return Op.Ban
	end
	--已绑定时
	if nStatus ==Ustatus.Bind then
		if nStage==Stage.Begin or nStage==Stage.After then
			return Op.Enter
		end
		return Op.Ban
	end
	return Op.Ban
end


 -- todo 
--拥有的门票数量
function Match:_GetTicketOwn(nUserId)
	return 0
end

--增加报名人数
function Match:_AddSignCnt(nAddValue)
	self.nUserCnt =self.nUserCnt +nAddValue
	if nAddValue~=0 then
		self.tInterface.SendToUsersOfOpen("TEvtUserCntNotify",{nEventId=self.nEventId,nUserCnt=self.nUserCnt})
		tPublicRedis.SetMttField(self.sUkey,"SignCnt",self.nUserCnt)
	end
	return self.nUserCnt
end
--赛事状态更新 通知
function Match:_BroadCastStatusNotify()
	local tD={}
	tD.nEventId=self.nEventId					--赛事ID
	tD.nStage=self.nStage						--赛事阶段 
	tD.nOp=0									--当前可进行的操作
	tD.nTimeStampBegin=self.nTimeStampBegin		--开赛时间戳
	tD.nTimeStampNow=os.time()					--当前时间戳

	local f=function(nUserId)
		tD.nOp=self:_GetOpCan(nUserId,false) 	--当前显示的操作按钮
		return tD
	end
	self.tInterface.SendToUsersOfOpenByF("TEvtStatusNotify",f)
end

--isBanNew:不存在时，是否禁止创建新的
function Match:_GetUser(nUserId,isBanNew)
	local tUser =self.tUserIdToUser[nUserId]
	if tUser then
		return tUser
	end
	if isBanNew then
		return self.tUserIdToAndroid[nUserId]
	end
	local tUserInfo =tPubUser.GetAllUserInfo(nUserId)
	tUser ={}
	tUser.nUserId = nUserId
	tUser.sName = tUserInfo.sNickName or ("User_"..nUserId)
	tUser.nSex = tonumber(tUserInfo.nSex) or 0 --0:男 1:女
	tUser.sFaceId = tUserInfo.sFaceID or "1"

	tUser.nStatus =Ustatus.NotSign 				--状态;  没报名 已报名 已绑定到比赛桌 已淘汰
	tUser.nChip =-1								--当前筹码 (-1表示未初始化,也即未开始)

	tUser.nServiceCoin =nServiceCoin	--报名时扣除的服务费
	tUser.sPayType =sPayType			--参赛费支付方式
	tUser.nPayCount =nPayCount			--参赛费
	tUser.isAndroid=false				--是否机器人
	return tUser
end
--添加一个机器人到报名列表
function Match:_AddAndroidToSign(tRobot)
	local tUser ={}
	tUser.nUserId = tRobot.nUserId
	tUser.sName = tRobot.sName
	tUser.nSex = tRobot.nSex
	tUser.sFaceId = tRobot.sFaceId
	tUser.nStatus =Ustatus.Sign 				--状态;  没报名 已报名 已绑定到比赛桌 已淘汰
	tUser.nChip =-1								--当前筹码 (-1表示未初始化,也即未开始)
	tUser.nServiceCoin =0						--报名时扣除的服务费
	tUser.sPayType =PayType.Coin				--参赛费支付方式
	tUser.nPayCount =0							--参赛费
	tUser.isAndroid=true						--是否机器人
	self.tUserIdToAndroid[tRobot.nUserId]=tUser
	local nSignCnt=self:_AddSignCnt(1)	--报名人数加1
	self:Print("_AddAndroidToSign,nUserId:%d nSignCnt:%d",tRobot.nUserId,nSignCnt)
	--根据需要，新增比赛桌
	self:_CheckCreateMtTable()
end


--返回报名金币(用于计算奖池)
function Match:_GetSignFee()
	local nFeeType =self.tFeeSignUp.nFeeType		--费用类型,1免费 2仅门票 3金币或门票
	local nTicketNeed= self.tFeeSignUp.nTicketNeed	--所需门票数量					(nFeeType 2或3时有效)
	local nFeeA =self.tFeeSignUp.nFeeA				--参赛费,可用门票抵扣			(nFeeType 3时有效)
	local nFeeB =self.tFeeSignUp.nFeeB				--报名服务费 或重购费 或增购费 	(nFeeType 3时有效)
	if nFeeType==1 then					--免费
		return 0
	end
	if nFeeType==2 then					--仅门票
		return 0	
	end
	if nFeeType==3 then					--金币或门票
		return (nFeeA+nFeeB)
	end
	return 0
end

--是否够付报名费
--返回 isCan,nServiceCoin,PayType,PayCount
function Match:_IsSignFeeEnough(tUser)
	local nFeeType =self.tFeeSignUp.nFeeType					--费用类型,1免费 2仅门票 3金币或门票
	local nEntryTicket =self.tFeeSignUp.nTicketNeed				--入场门票数量
	local nEntryCoin =self.tFeeSignUp.nFeeA						--入场金币
	local nServiceCoin =self.tFeeSignUp.nFeeB					--手续费金币
	local nGold =tPubUser.Get_User_UnLockGold(tUser.nUserId)	--玩家剩余金币
	local nTicket =self:_GetTicketOwn(tUser.nUserId)			--玩家拥有门票数量
	--免费(同样收取手续费，防恶意取消报名)
	if nFeeType==1 then			
		if GreaterOrEqual(nGold,nServiceCoin) then
			return true,nServiceCoin,PayType.Free,0
		end
		return false
	end
	--仅门票(同样收取手续费，防恶意取消报名)
	if nFeeType==2 then			
		if nTicket >=nEntryTicket and GreaterOrEqual(nGold,nServiceCoin) then
			return true,nServiceCoin,PayType.Ticket,nEntryTicket
		end
		return false
	end
	--金币或门票
	if nFeeType==3 then		
		--优先使用门票(同样收取手续费，防恶意取消报名)
		if nTicket>=nEntryTicket and GreaterOrEqual(nGold,nServiceCoin) then	
			return true,nServiceCoin,PayType.Ticket,nEntryTicket			--
		end
		--再金币
		if GreaterOrEqual(nGold,(nEntryCoin +nServiceCoin)) then
			return true,nServiceCoin,PayType.Coin,nEntryCoin
		end
		return false
	end
	return false
end


-- ==>todo 扣费 (门票没处理)
--sReason : "SignUp"  "SignUpCancel"
function Match:_AddFee(nUserId,nAddValueGold,nAddValueTicket,nReason)
	self:Print("_AddFee nUserId:%d nAddGold:%s nAddTicket:%d nReason:%d",nUserId,tostring(nAddValueGold),nAddValueTicket,nReason)
	if Equal(nAddValueGold,0) then
		return true
	end
	local nSourceType =10000 +10*self.nGameId +nReason
	local isSuccee =tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=1,nDel=nAddValueGold,nSourceType=nSourceType,isNotCheck=true})
	return isSuccee
end


function Match:_SetUserStatus(tUser,sStatus,sStatusInfo)
	local sStatusInfo=sStatusInfo or ""
	local nStatus =Ustatus[sStatus]
	assert(nStatus~=nil)
	tUser.nStatus =nStatus
	local sField =string.format("U:%d",tUser.nUserId)
	local sValue =string.format("ST:%s:%s",sStatus,sStatusInfo)
	if nStatus ==Ustatus.NotSign then
		tPublicRedis.DelMttField(self.sUkey,sField)
	else
		tPublicRedis.SetMttField(self.sUkey,sField,sValue)
	end
end

function Match:_GetUserStatus(nUserId)
	local sField =string.format("U:%d",nUserId)
	local sValue =tPublicRedis.GetMttField(self.sUkey,sField) or ""
	local s1,s2,s3 =string.match(sValue,"(.*):(.*):(.*)")
	if s2 then
		return (Ustatus[s2] or Ustatus.NotSign),s3
	end
	return Ustatus.NotSign
end

--协议 比赛信息=>玩家列表
function Match:GetProtoEvtUsers()
	local arr={}
	for nUserId,tUser in pairs(self.tUserIdToUser) do
		if tUser.nStatus ==Ustatus.Sign or tUser.nStatus ==Ustatus.Bind then
			local Item={}
			Item.nUserId=nUserId			--玩家ID
			Item.sFaceId=tUser.sFaceId		--头像url
			Item.sName=tUser.sName			--昵称
			Item.nSex=tUser.nSex	    	--性别 0:男 1:女
			Item.nChip=tUser.nChip			--持有筹码 (-1时,表示未开赛)
			table.insert(arr,Item)
		end
	end
	for nUserId,tUser in pairs(self.tUserIdToAndroid) do
		if tUser.nStatus ==Ustatus.Sign or tUser.nStatus ==Ustatus.Bind then
			local Item={}
			Item.nUserId=nUserId			--玩家ID
			Item.sFaceId=tUser.sFaceId		--头像url
			Item.sName=tUser.sName			--昵称
			Item.nSex=tUser.nSex	    	--性别 0:男 1:女
			Item.nChip=tUser.nChip			--持有筹码 (-1时,表示未开赛)
			table.insert(arr,Item)
		end
	end
	return arr
end

--协议 比赛信息=>奖励列表
function Match:GetProtoAwards()
	local arr ={}
	if self.nAwardType==1 then
		for _,v in ipairs(self.arrAward or {}) do
			table.insert(arr,{nRank=v.nRank,nCoin=v.nCoin,nTicket=v.nTicket})
		end
	end
	if self.nAwardType==2 then
		local nPool =(self:_GetSignFee() *self:_AddSignCnt(0))
		for _,v in ipairs(self.arrAwardPercent or {}) do
			local nCoin =math.floor(((v.nPercent/100) *nPool)) 
			table.insert(arr,{nRank=v.nRank,nCoin=nCoin,nTicket=v.nTicket})
		end
	end
	return arr
end

--报名
--返回 0:报名成功 1: 费用不足 2:报名人数达上限 3:超出报名时间 其它:未定义错误
function Match:SignUp(nUserId)
	local nOpCan =self:_GetOpCan(nUserId,true)
	if nOpCan ~=Op.Sign then
		self:Print("SignUp Err,out of stage,nUserId:%d nOpCan:%d",nUserId,nOpCan)
		return 3	--超出报名时间
	end
	if self:_AddSignCnt(0)>=self.nUserCntMax then
		self:Print("SignUp Err,out of maxUser,nUserId:%d,nUserCntMax:%d",nUserId,self.nUserCntMax)
		return 2	--报名人数达上限
	end
	local tUser =self:_GetUser(nUserId,false)
	local isEg,nServiceCoin,sPayType,nPayCount =self:_IsSignFeeEnough(tUser)

	if not isEg then
		self:Print("SignUp Err,fee not enough,nUserId:%d",nUserId)
		return 1	--费用不足
	end
	--扣报名费
	local nFeeGold =nServiceCoin
	local nFeeTicket =0
	if sPayType ==PayType.Coin then
		nFeeGold =nFeeGold +nPayCount
	elseif sPayType ==PayType.Ticket then
		nFeeTicket =nPayCount
	end
	local isSuccee =self:_AddFee(nUserId,-nFeeGold,-nFeeTicket,GoldCReason.nSignUp)
	assert(isSuccee)

	--成功
	self:_SetUserStatus(tUser,"Sign",sPayType)	--设置玩家状态 为'已报名'
	tUser.nServiceCoin =nServiceCoin
	tUser.sPayType =sPayType
	tUser.nPayCount =nPayCount
	self.tUserIdToUser[nUserId]=tUser
	local nSignCnt=self:_AddSignCnt(1)	--报名人数加1
	self:Print("SignUp Succee,nUserId:%d nSignCnt:%d sPayType:%s",nUserId,nSignCnt,sPayType)
	--根据需要，新增比赛桌
	self:_CheckCreateMtTable()
	return 0
end




--取消报名
--返回 0:取消成功 其它:未定义错误
function Match:SignUpCancel(nUserId)
	local nOpCan =self:_GetOpCan(nUserId,true)
	if nOpCan ~=Op.SignCancel then
		self:Print("SignUpCancel Err,out of stage,nUserId:%d",nUserId)
		return 3	--超出时间
	end

	--只返还参赛费(不返服务费)
	local tUser =self:_GetUser(nUserId,true)
	local nGoldRt,nTicketRt =0,0
	if tUser.sPayType ==PayType.Coin then
		nGoldRt =tUser.nPayCount
	elseif tUser.sPayType ==PayType.Ticket then
		nTicketRt =tUser.nPayCount
	end
	local isSuccee =self:_AddFee(nUserId,nGoldRt,nTicketRt,GoldCReason.nSignUpCancel)
	assert(isSuccee)

	--成功
	self:_SetUserStatus(tUser,"NotSign")		--设置玩家状态 为'未报名'

	local nSignCnt=self:_AddSignCnt(-1)			--报名人数减1
	self:Print("SignUpCancel Succee,nUserId:%d nSignCnt:%d nGoldRt:%d nTicketRt:%d,sPayType:%s",nUserId,nSignCnt,nGoldRt,nTicketRt,tUser.sPayType)
	return 0  
end

--返还所有报名用户的报名费用 (比赛取消时用)
function Match:_BackUsersSignFee(nReason)
	self:Print("_BackUsersSignFee")
	for nUserId,tUser in pairs(self.tUserIdToUser) do
		if tUser.nStatus ==Ustatus.Sign then
			local nFeeGold =tUser.nServiceCoin
			local nFeeTicket =0
			if tUser.sPayType ==PayType.Coin then
				nFeeGold =nFeeGold +tUser.nPayCount
			elseif tUser.sPayType ==PayType.Ticket then
				nFeeTicket =tUser.nPayCount
			end
			local isSuccee =self:_AddFee(nUserId,nFeeGold,nFeeTicket,nReason)
			self:_WriteUserBackFeeNotic(nUserId)
			assert(isSuccee)
		end
	end
end

--给玩家发比赛取消邮件
function Match:_WriteUserBackFeeNotic(nUserId)
	local sName =BaseSink.encode(self.sName)
	local tInfo ={sName=sName,nEventId=self.nEventId}
	local sInfo =cjson.encode(tInfo)
	local sql =string.format("call Club_WriteUserNotice(%d,%d,'%s')",nUserId,5,sInfo) 
	local tPacket =DbServAux:Encode("DbPublicAPIReq",{sDatabaseName="DJH_RecordDB",sSql=sql})
	tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

--给玩家发领奖邮件
function Match:_WriteUserGetAwardNotic(nUserId,nGold,nRank)
	local sName =BaseSink.encode(self.sName)
	local tInfo ={sName=sName,nEventId=self.nEventId,nGameId=self.nGameId,nGold=nGold,nRank=nRank}
	local sInfo =cjson.encode(tInfo)
	local sql =string.format("call Club_WriteUserNotice(%d,%d,'%s')",nUserId,4,sInfo) 
	local tPacket =DbServAux:Encode("DbPublicAPIReq",{sDatabaseName="DJH_RecordDB",sSql=sql})
	tBase.PostDatasByType(tname.db, 0, 0, tPacket:GetData(), tPacket:GetSize()) 
end

function Match:_IsAndroid(nUserId)
	local tUser =self:_GetUser(nUserId,true)
	if tUser==nil or tUser.isAndroid then
		return true
	end
	return false
end

--颁奖
function Match:_Prize()
	self:Print("_Prize")
	local arr =self:GetProtoAwards()
	for _,v in ipairs(arr) do
		local sField =string.format("Rank:%d",v.nRank)
		local sUserId =tPublicRedis.GetMttField(self.sUkey,sField)
		local nUserId =tonumber(sUserId)
		local isAndroid =self:_IsAndroid(nUserId)
		self:Print("_Prize nUserId:%s nRank:%d nCoin:%d isAndroid:%s",tostring(nUserId),v.nRank,v.nCoin,tostring(isAndroid))
		if not isAndroid then
			self:_AddFee(nUserId,v.nCoin,0,GoldCReason.nAward)
			self:_WriteUserGetAwardNotic(nUserId,v.nCoin,v.nRank)
		end
	end
end


--延迟报名 
--返回 nRlt,sTableId;  nRlt 0:报名成功 1: 费用不足 2:报名人数达上限 3:超出报名时间 其它:未定义错误
function Match:SignUpDelay(nUserId)
	--超出延迟报名时间
	local nOpCan,nCode =self:_GetOpCan(nUserId,true)
	if nOpCan ~=Op.SignDelay then
		self:Print("SignUpDelay Err,out of stage,nUserId:%d nCode:%s",nUserId,tostring(nCode))
		return nCode or 3	
	end
	--报名人数达上限
	if self:_AddSignCnt(0)>=self.nUserCntMax then
		self:Print("SignUpDelay Err,out of maxUser,nUserId:%d",nUserId)
		return 2	
	end
	--费用不足
	local tUser =self:_GetUser(nUserId,false)
	local isEg,nServiceCoin,sPayType,nPayCount =self:_IsSignFeeEnough(tUser)
	if not isEg then
		self:Print("SignUpDelay Err,fee not enough,nUserId:%d",nUserId)
		return 1	
	end

	--分配一个桌子
	local sTableId = self.sWaitRoomTalbeId
	if sTableId==nil then
		self:Print("SignUpDelay Err,no table,nUserId:%d",nUserId)
		return 4
	end

	--扣报名费
	local nFeeGold =nServiceCoin
	local nFeeTicket =0
	if sPayType ==PayType.Coin then
		nFeeGold =nFeeGold +nPayCount
	elseif sPayType ==PayType.Ticket then
		nFeeTicket =nPayCount
	end
	local isSuccee =self:_AddFee(nUserId,-nFeeGold,-nFeeTicket,GoldCReason.nSignUp)
	assert(isSuccee)

	--成功
	self:_SetUserStatus(tUser,"Sign",sPayType)	--设置玩家状态 为'已报名'
	tUser.nServiceCoin =nServiceCoin
	tUser.sPayType =sPayType
	tUser.nPayCount =nPayCount
	self.tUserIdToUser[nUserId]=tUser
	local nSignCnt=self:_AddSignCnt(1)	--报名人数加1
	self:Print("SignUpDelay Succee,nUserId:%d nSignCnt:%d sTableId:%s sPayType:%s",nUserId,nSignCnt,sTableId,sPayType)
	--根据需要，新增比赛桌
	self:_CheckCreateMtTable()

	return 0,sTableId
end

--进入比赛;Rsp回调参数为: nRlt,sTableId,nRemainT
--nRlt 2:成功 其它:错误
function Match:TEvtEnter(nUserId,Rsp)
	local nOpCan,nCode =self:_GetOpCan(nUserId,true)
	--操作不合法
	if nOpCan ~=Op.Enter then
		self:Print("TEvtEnter Err,out of stage,nUserId:%d,nCode:%s",nUserId,tostring(nCode))
		Rsp(nCode or 3,nil,nil)	
		return	
	end
	local nStatus,sTableId =self:_GetUserStatus(nUserId)

	--已经有桌子
	if nStatus ==Ustatus.Bind then
		self:Print("TEvtEnter,nUserId:%d sTableId:%s",nUserId,tostring(sTableId))
		Rsp(2,sTableId,nil)
		return
	end
	--分配一个桌子
	local sTableId = self.sWaitRoomTalbeId 
	if sTableId then
		self:Print("TEvtEnter,nUserId:%d sTableId:%s",nUserId,sTableId)
		Rsp(2,sTableId,nil)
	else
		self:Print("TEvtEnter,nUserId:%d Fail",nUserId)
		Rsp(4,nil,nil)	
	end
end

--观战
--返回 nRlt,sTableId; nRlt 0:成功  其它:未定义错误
function Match:Watch(nUserId)
	--超出延迟报名时间
	local nOpCan =self:_GetOpCan(nUserId,true)
	if nOpCan ~=Op.Watch then
		self:Print("Watch Err,out of stage,nUserId:%d",nUserId)
		return 3	
	end
	local sTableId =self.tOx:GetWatchTable(nUserId)
	if sTableId==nil then
		self:Print("Watch Err,No table,nUserId:%d",nUserId)
		return 4
	end
	self:Print("Watch Succee,nUserId:%d sTableId:%s",nUserId,sTableId)
	return 0,sTableId
end

--入口提示查询
--nRlt 0:正在比赛当中 1:可以进入比赛 -1:没提示
function Match:EntryCheck(nUserId)
	local nStatus,sTableId =self:_GetUserStatus(nUserId)
	if nStatus ==Ustatus.Bind then
		self:Print("EntryCheck,nUserId:%d is in sTableId:%s",nUserId,tostring(sTableId))
		return 0,self.nEventId,self.sName	--正在比赛当中
	end
	local nOpCan =self:_GetOpCan(nUserId,true)
	if nOpCan ==Op.Enter then
		self:Print("EntryCheck,nUserId:%d is can Enter",nUserId)
		return 1,self.nEventId,self.sName	--可以进入比赛(进去等待分配桌子)
	end
	self:Print("EntryCheck,nUserId:%d is no tips",nUserId)
	return -1,self.nEventId,self.sName		--没提示
end


--获得最近开赛的时间戳
function Match:_GetNearestBeginTime(nNow)
	local nLoopType =self.tTRule.nLoopType
	local nZone =self.tTRule.nZone
	local nHour =self.tTRule.nHour
	local nMin=self.tTRule.nMin
	local nSec =self.tTRule.nSec
	local nWeekday=self.tTRule.nWeekday
	local nMonthday =self.tTRule.nMonthday
	local nYear=self.tTRule.nYear			
	local nMonth=self.tTRule.nMonth			
	local nLoopSec =self.tTRule.nLoopSec
	if nLoopType ==LoopType.Month then	--按月
		local nearest =tAlg.nearest_timestamp_month(nMonthday,nHour,nMin,nSec,nZone,nNow)
		return nearest,true
	end
	if nLoopType ==LoopType.Week then	--按周
		local nearest =tAlg.nearest_timestamp_week(nWeekday,nHour,nMin,nSec,nZone,nNow)
		return nearest,true
	end
	if nLoopType ==LoopType.Day then	--按天
		local nearest =tAlg.nearest_timestamp_day(nHour,nMin,nSec,nZone,nNow)
		return nearest,true
	end
	if nLoopType ==LoopType.Once then	--按次
		local nearest =tAlg.get_timestamp(nYear, nMonth, nMonthday, nHour, nMin, nSec,nZone)
		return nearest,false
	end
	if nLoopType ==LoopType.FixTest then --测试用循序方式
		return (os.time()+nLoopSec),true
	end

	assert(false)
end

function Match:Start()
	self:_TryGoInSignUpStage()
end


--尝试进入报名阶段
function Match:_TryGoInSignUpStage()
	assert(self.nStage==Stage.Init or self.nStage==Stage.End)
	local nNow =os.time()
	local nNearest,isLoop =self:_GetNearestBeginTime(nNow)
	local nDiff=nNearest -nNow
	if nDiff >(self.nTimeBefore+30) and nDiff<3600*24*30*12*3 then --比赛开始前3年可作报名阶段
		self:GoInSignUpStage(nNearest)
		return
	end
	if (not isLoop) and nDiff< -self.CloseTime then
		self:Close("normal")
		return
	end
	self:Print("_TryGoInSignUpStage,TimeBegin:%s nTimeBefore:%d sec",tAlg.ToDate(nNearest),self.nTimeBefore)
	self.Timer:DelayCall(60*1000,self._TryGoInSignUpStage,self)
end

--尝试创建等待室
function Match:_TryCreateWaitRoom()
	local nNow =os.time()
	local nNearest=self.nTimeStampBegin-self.nTimeBefore -60	--允许进入比赛前60秒创建
	local diff=nNearest -nNow
	self:Print("_TryCreateWaitRoom,diff:%d sec",diff)
	if diff <60*2 then
		diff=math.max(diff,0.1)
		self.TimerWaitRoom:DelayCall(diff*1000,self._ReqCreateMtTable,self,true)
		return
	end
	self.TimerWaitRoom:DelayCall(60*1000,self._TryCreateWaitRoom,self)
end


--广播比赛即将开始
function Match:_BroadCastToBegin()
	self:Print("_BroadCastToBegin")
	local tNotify ={}
	tNotify.nEventId =self.nEventId
	tNotify.sName =self.sName
	tNotify.nRemainT =(self.nTimeStampBegin -os.time())
	for nUserId,tUser in pairs(self.tUserIdToUser) do
		if tUser.nStatus ==Ustatus.Sign then
			self.tInterface._SendToUser(nUserId,"TEvtToStartNotify",tNotify)
		end
	end
end

--广播比赛因人数过少被取消
function Match:_BroadCastMttCancel()
	self:Print("_BroadCastMttCancel")
	local tNotify ={}
	tNotify.nEventId =self.nEventId
	tNotify.sName =self.sName
	for nUserId,tUser in pairs(self.tUserIdToUser) do
		if tUser.nStatus ==Ustatus.Sign then
			self.tInterface._SendToUser(nUserId,"TEvtCancelNotify",tNotify)
		end
	end
end

--尝试进入'允许进入比赛阶段'
function Match:_TryGoInBeforeStage()
	local nNow =os.time()
	local diff =self.nTimeStampBegin -self.nTimeBefore-nNow --
	assert(diff>=0)	--服务器卡了的话可能出现
	self:Print("_TryGoInBeforeStage,diff:%d sec",diff)
	if diff <60*2 then
		diff=math.max(diff,0.1)
		self.Timer:DelayCall(diff*1000,self.GoInBeforeStage,self)
		return
	end
	self.Timer:DelayCall(60*1000,self._TryGoInBeforeStage,self)
end

--检查是否需要新增比赛桌子(视当前报名人数而定)
function Match:_CheckCreateMtTable()
	if self.isCanDynamicAddMttTable then
		self:_ReqCreateMtTable(false)
	end
end

--发送请求到游戏服，获取桌子
function Match:_ReqCreateMtTable(isWaitRoom)
	local nCntSign =self:_AddSignCnt(0)								--报名人数
	local nCntAllNeed =math.ceil(nCntSign/self.nUserCntOfTable) +2	--总共需要的桌子数
	local nCntCreate = math.max(nCntAllNeed-self.nMttTableCnt,0)	--当前需要新增的数量
	if isWaitRoom then
		nCntCreate =1	
	else
		self.nMttTableCnt =self.nMttTableCnt +nCntCreate
	end
	if nCntCreate <=0 then
		return 0
	end
	self:Print("_ReqCreateMtTable,isWaitRoom:%s nCntCreate:%d",tostring(isWaitRoom),nCntCreate)

	local tData ={}
	tData.nCntCreate=nCntCreate				--创建桌子数量
	tData.nGameId=self.nGameId				--游戏id
	tData.nTakeIn=self.nTakeIn		 		--初始记分牌
	tData.nCapacity=self.nUserCntOfTable	--桌子座位数
	tData.tFeeR =self.tFeeR					--重购费s
	tData.tFeeA=self.tFeeA					--增购费s
	tData.tEvtTakInR=self.tEvtTakInR		--重购规则s
	tData.tEvtTakInA =self.tEvtTakInA		--增购规则s
	tData.arrLvItem=self.arrLvItem			--升盲列表s
	tData.nBlindUpGap=self.nBlindUpGap     	--涨盲时间 秒
	tData.nTimeStampBegin =self.nTimeStampBegin --开赛时间(涨盲初始时间)
	tData.nGroupId =self.nGroupId
	tData.nTimeBefore=self.nTimeBefore or 120	--开赛前时间 秒(期间内，已报名者可"进入比赛")
	tData.nTimeAfter=self.nTimeAfter or 120		--开赛后时间 秒(期间内，未报名者可"延迟报名",超过后所有人仅能"观战")
	tData.nCntBegin =self.nCntBegin				--最小开赛人数
	tData.sName =BaseSink.encode(self.sName)	--比赛名称(用来当牌桌名称)
	tData.isWaitRoom=isWaitRoom					--是否是创建等待桌(等待分配桌子)
	tData.isFree =(self.tFeeSignUp.nFeeType ==1)	--报名是否免费
	tData.nUserCntMax=self.nUserCntMax				--最大报名人数
	tData.nLoopType =self.tTRule.nLoopType			--
	tData.sUkey =self.sUkey

	--奖励列表s
	tData.nAwardType =self.nAwardType			--奖励方式 1:固定 2:奖池百分比
	tData.arrAward=self.arrAward
	tData.arrAwardPercent=self.arrAwardPercent
	
	self:_SendToGameServ("CreateMtTable",tData)
	return nCntCreate
end

function Match:_SendToGameServ(sCmd,tData)
	local DZCMtReq ={}
	DZCMtReq.sCmd =sCmd
	DZCMtReq.sJsonData=cjson.encode(tData)
	DZCMtReq.nEventId=self.nEventId
	DZCMtReq.nEcho =-1
	self.nServId =tSlaveManager.SendByServId(self.nServId,"DZCMtReq",DZCMtReq)
	return self.nServId
end

--来自游戏中心服的消息处理
function Match:MsgHandle(sReturnKey,sCmd,tRlt)
	if sCmd =="CreateMtTable" then
		local arrTb =tRlt.arrTb or {}
		self:Print("MsgHandle, CreateMtTable:%d isWaitRoom:%s",#arrTb,tostring(tRlt.isWaitRoom))
		if tRlt.isWaitRoom then
			self.sWaitRoomTalbeId =arrTb[1]
			return
		end
		for _,sTableId in ipairs(arrTb) do
			self.tOx:AddTable(sTableId)
		end
		return
	end
	if sCmd =="UserOust" then			--玩家淘汰通知
		self:Print("UserOust,nUserId:%d nRank:%d",tRlt.nUserId,tRlt.nRank)
		local tMttUser =self:_GetUser(tRlt.nUserId,true) or {}
		tMttUser.nStatus =Ustatus.Oust
		self:_AddMttUserCnt(-1)
		return
	end
	if sCmd =="Bind" then				--玩家绑定到比赛桌通知
		local nUserId =tRlt.nUserId
		local sTableId =tRlt.sTableId
		self:Print("Bind,nUserId:%d sTableId:%s",nUserId,sTableId)
		local isSuccee,sErr=self.tOx:BindUserToTable(nUserId,sTableId)
		self:_AddMttUserCnt(1)
		local tMttUser =self:_GetUser(tRlt.nUserId,true) or {}
		tMttUser.nStatus =Ustatus.Bind
		assert(isSuccee,sErr)
		return
	end
	if sCmd =="UnBind" then				--玩家从比赛桌解绑通知 (解绑以便分配到其它桌)
		local nUserId =tRlt.nUserId
		local sTableId =tRlt.sTableId
		self:Print("UnBind,nUserId:%d sTableId:%s",nUserId,sTableId)
		local isSuccee,sErr=self.tOx:UnBindUserFromTable(nUserId,sTableId)
		assert(isSuccee,sErr)
		return
	end
	if sCmd =="MttEnd" then				--比赛结束通知(游戏服会自行关闭所有比赛桌子)
		local sReason =tRlt.sReason
		self:Print("MttEnd,sReason:%s",tostring(sReason))
		self:_End(sReason =="ChampionBorn",nil)
		return
	end
	if sCmd =="UsersBalance" then		--玩家当前筹码情况
		self:Print("UsersBalance,sTableId:%s,sTip:%s",tRlt.sTableId,tRlt.sTip)
		for _,v in ipairs(tRlt.arrUser) do
			local tMttUser =self:_GetUser(v.nUserId,true) or {}
			tMttUser.nChip = math.floor(v.nBalance)
		end
		self:_ToBroadCastRuleD()
		return
	end

	if sCmd =="MttAndroidJoin" then		--机器人加进比赛
		local tRobot =tRlt.tRobot
		self:Print("MttAndroidJoin,nUserId:%d",tRobot.nUserId)
		self:_AddAndroidToSign(tRobot)
		return
	end

	self:Print("MTT Error,sCmd:%d NotHandle",sCmd)
end

--isRankNormal:是否需要排名结算
--sReason:由本服主动结束时填,游戏服触发时填nil
function Match:_End(isRank,sReason)
	self:Print("_End,isRank:%s sReason:%s",tostring(isRank),tostring(sReason))
	self.isEnd=true
	if isRank then		--进入正常排名结算流程
		self:GoInRankStage()
	else				
		self:_BroadCastMttCancel()
		self:_BackUsersSignFee(GoldCReason.nMttCancel)	--退报名费
		self:GoInEndStage()
	end
	if sReason then
		self:_SendToGameServ("CloseMtt",{sReason=sReason})
	end
	self:_ToBroadCastRuleD(1)
end


function Match:_SetStage(nStage)
	self.nStage =nStage
	self:_BroadCastStatusNotify()
end

function Match:_AddMttUserCnt(nAddValue)
	self.nMttUserCnt =self.nMttUserCnt +nAddValue
	return self.nMttUserCnt
end

--尝试进入'开赛比赛阶段'
function Match:_TryGoInBeginStage()
	local nNow =os.time()
	local diff =self.nTimeStampBegin -nNow
	assert(diff>=0)	--服务器卡了的话可能出现
	self:Print("_TryGoInBeginStage,diff:%d sec",diff)
	if diff <60*2 then
		diff=math.max(diff,0.1)
		self.Timer:DelayCall(diff*1000,self.GoInBeginStage,self)
		return
	end
	self.Timer:DelayCall(60*1000,self._TryGoInBeginStage,self)
end

--尝试进入'延迟报名截止阶段'
function Match:_TryGoInAfterStage()
	local nNow =os.time()
	local diff =self.nTimeStampBegin +self.nTimeAfter -nNow
	assert(diff>=0)	--服务器卡了的话可能出现
	self:Print("_TryGoInAfterStage,diff:%d sec",diff)
	if diff <60*2 then
		diff=math.max(diff,0.1)
		self.Timer:DelayCall(diff*1000,self.GoInAfterStage,self)
		return
	end
	self.Timer:DelayCall(60*1000,self._TryGoInAfterStage,self)	
end

--进入 '报名阶段'
function Match:GoInSignUpStage(nNearest)
	self.nJuShu =self.nJuShu+1
	self.nStatus=0									--赛事状态 1:比赛已结束 0:正常(允许报名)
	self.nTimeStampBegin=nNearest					--开赛时间戳
	self.nUserCnt=0									--当前报名人数
	self.tUserIdToUser={}
	self.tUserIdToAndroid={}
	self.nMttUserCnt =0								--当前比赛人数
	self.nMttTableCnt=0								--已请求创建的桌子数
	self.tOx:Init()									--重置桌子管理器
	self.sWaitRoomTalbeId=nil
	self.isCanDynamicAddMttTable=false				--是否能动态新增比赛桌子
	self.isEnd=false
	tPublicRedis.DelMtt(self.sUkey)					--清空玩家报名列表
	tPublicRedis.SetMttField(self.sUkey,"nEntryTicket",self.tFeeSignUp.nTicketNeed) --入场门票数量
	tPublicRedis.SetMttField(self.sUkey,"nEntryCoin",self.tFeeSignUp.nFeeA)			--入场金币
	tPublicRedis.SetMttField(self.sUkey,"nServiceCoin",self.tFeeSignUp.nFeeB)		--手续费金币
	tPublicRedis.SetMttField(self.sUkey,"nGameId",self.nGameId)						--有些id

	self:_SetStage(Stage.SignUp)
	self.Timer:KillAllTimer()
	self:_TryCreateWaitRoom()						--预先创建等待室
	self:Print("GoInSignUpStage,TimeBegin:%s sUkey:%s",tAlg.ToDate(nNearest),self.sUkey)
	self:_TryGoInBeforeStage()
end

--进入 '允许进比赛阶段'
function Match:GoInBeforeStage()
	self:_SetStage(Stage.Before)
	self.Timer:KillAllTimer()
	self:Print("GoInBeforeStage,%s",tAlg.ToDate(self.nTimeStampBegin-self.nTimeBefore))

	--报名人数太少，解散
	if self:_AddSignCnt(0) <self.nCntBegin then
		self:Print("SignCnt is too few")
		self:_End(false,"SignCntTooFew")
		return
	end
	--没有等待室(正常不会进入到这里)
	if self.sWaitRoomTalbeId==nil then
		self:Print("sWaitRoomTalbeId is nil")
		self:_End(false,"NoWaitRoomTable")
		return
	end
	self:_TryGoInBeginStage()
	--请求创建比赛桌
	self:_ReqCreateMtTable()
	--广播给报名用户,比赛即将开始
	self:_BroadCastToBegin()
	--允许动态新增比赛桌子
	self.isCanDynamicAddMttTable=true
end

--进入'比赛开始阶段'
function Match:GoInBeginStage()
	self:_SetStage(Stage.Begin)
	self.Timer:KillAllTimer()
	self:Print("GoInBeginStage,%s,sUkey:%s",tAlg.ToDate(self.nTimeStampBegin),self.sUkey)
	self:_TryGoInAfterStage()
end

--进入'比赛阶段(截止报名)'
function Match:GoInAfterStage()
	self:_SetStage(Stage.After)
	self.Timer:KillAllTimer()
	self:Print("GoInAfterStage,%s",tAlg.ToDate(self.nTimeStampBegin+self.nTimeAfter))
end

--进入排名阶段
function Match:GoInRankStage()
	self.nStatus=1		--1:比赛已结束 0:正常(允许报名)
	self:_SetStage(Stage.Rank)
	self.Timer:KillAllTimer()
	self:Print("GoInRankStage")
	self.Timer:DelayCall(self.RankTime*1000,self.GoInAwardStage,self)	
end

--进入奖励阶段
function Match:GoInAwardStage()
	self:_SetStage(Stage.Award)
	self.Timer:KillAllTimer()
	self:Print("GoInAwardStage")
	self.Timer:DelayCall(self.AwardTime*1000,self.GoInEndStage,self)
	self:_Prize()	-- 颁奖
	self:_SetSettleOver()
end


--进入结束阶段
function Match:GoInEndStage()
	self:_SetStage(Stage.End)
	self.Timer:KillAllTimer()
	self:Print("GoInEndStage")
	self:_SetSettleOver()
	if self.tTRule.nLoopType ==LoopType.Once or self.isSetClose then
		self.Timer:DelayCall(self.EndTime*1000,self.Close,self)
	else
		self.Timer:DelayCall(self.EndTime*1000,self._TryGoInSignUpStage,self)
	end
end

--设置本场比赛已经结算完毕
function Match:_SetSettleOver()
	tPublicRedis.SetMttField(self.sUkey,"SettleEnd",1)
end


--关闭比赛(入口)
function Match:Close()
	self:Print("Close,sUkey:%s",self.sUkey)
	self.Timer:KillAllTimer()
	self.TimerWaitRoom:KillAllTimer()
	self.TimerRuleD:KillAllTimer()
	self.tInterface.CloseMatch(self.nEventId,self.sKeyRedisCfg,self.sFieldRedisCfg)
end

function Match:OnClose()
	self:Print("OnClose")
	self.isSetClose =true
	self:_End(false,"BackstageClose")
end


function Match:Print(str,...)
	tBase.Log(self.sName.."_"..self.nJuShu.."=>"..str,...)
end

return Match
