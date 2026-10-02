
local tBase 	  = require("base")         -- 基础功能接口
local Define =require("Define")
local RecordDbr =require("RecordDbr")
local tPubUser = require("PublicUserInfo") -- 用户信息
local tConfig =require("GameConfig") -- 
local tTimerAux =require("TimerAux")
local cjson    = require("cjson")
local tPublicRedis =require("PublicRedis")
local tAlg =require("GameAlg")
local tScAlg =require("GameAlg_Sc")
local assets_manager = require("public/Assets/Assets")    -- 资产管理接口
local publicApi =require("publicApi")
local tSlaveManager =require("SlaveManage")
local tPublicClub =require("PublicClub")
local Review =require("Review")
local json    = require("json")
local tOverview =require("Overview")
local Statistic =require("Statistic")
local PublicDefine =require("PublicDefine")
local tRedisCahche=	require("RedisCahche")
local tTaxGather =require("TaxGather")
local tStack =require("Stack")
local MsgCode =PublicDefine.MsgCode
local TableState =PublicDefine.TableState
local UserStatus =PublicDefine.UserStatus
local UserOp =PublicDefine.UserOp
local RoomType =PublicDefine.RoomType
local TableCloseReason =Define.TableCloseReason
local InsureMode =Define.InsureMode
local GoldCReason =PublicDefine.GoldCReason

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
    local nPoint = nCard % 16  -- 计算牌点
    local nHuaSe = math.floor(nCard / 16)  -- 使用 math.floor 来代替整除操作符
    return (nPoint >= 1 and nPoint <= 13) and (nHuaSe >= 1 and nHuaSe <= 4)
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

local function _CutOff(arr,nRemainCnt)
	local tS =tStack:New()
	while (#arr>nRemainCnt) do
		local tItem =table.remove(arr)
		tS:Push(tItem)
	end
	return tS
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

local sin=math.sin
local cos =math.cos
local rad =math.rad
local acos =math.acos
local asin=math.asin
local sqrt =math.sqrt
local pow=math.pow

--返回gps两点距离 (单位:km)
local function GetDistance(lng1, lat1,lng2,lat2)
	local R =6371.004		--单位 km
    local radLat1 = rad(lat1)
    local radLat2 = rad(lat2)
    local a = radLat1 - radLat2
    local b = rad(lng1) - rad(lng2)
    local s = 2 * asin(sqrt(pow(sin(a/2),2) + 
     cos(radLat1)*cos(radLat2)*pow(sin(b/2),2)))
    s = s * R
    s = math.floor(s * 10000+0.5) / 10000;
    return s; --单位 km
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
	
	--桌子基本信息
	t.sTableId=sTableId or ""					--table id
	t.tInterFace=tInterFace     				--Game层接口 (Game =>table =>user)	
	t.sTableName=tConfig.sTableName
	t.nGroupId =tConfig.nGroupId
	t.nRoomId=tConfig.nRoomId
	t.nLiveUserID =tConfig.nLiveUserID			--主播ID
	t.nTableType =tConfig.nTableType			--桌子类型
	t.sLiveID =tConfig.sLiveID

	--德州配置信息
	local tJsonConfig =tConfig.tJsonConfig
	t.sClubName ="unknown"
	t.isRobotBan =true --是否禁止机器人进入
	t.nSmallBlind=tJsonConfig.nSmallBlind 			--小盲注数额
	t.nBigBlind=tJsonConfig.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	t.nForceBlind=tJsonConfig.nBigBlind*2			--强盲数额
	t.nCapacity =tJsonConfig.nCapacity				--能供玩游戏的座位数
	t.nIntervalLev =2								--牌局间隔 1:短暂 2:适中 3:漫长
	t.nClubId =0                 					--俱乐部id (俱乐部房配置,否时为nil)
	t.nItemId=1              						--使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	t.nKeepTime =-1              					--房间时长(秒) (俱乐部房配置,否时为nil) -1:无限制

	t.nGoldType =3			   						 -- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)
	t.nBuyMin =tJsonConfig.nBigBlind*100	 		--最小买入
	t.nBuyMax =tJsonConfig.nBigBlind*1000			--最大买入
	t.nTakeIn =tJsonConfig.nTakeIn					--默认带入(初始记分牌)
	t.nGameId =tJsonConfig.nGameId					--游戏Id
	t.nFee =0 										--手续费 (已无用)
	t.nTax =0 										--抽水 (百分比) (已无用)
	t.isTabkeOut =false								--是否开启带出功能 true:是 false:否

	t.nPlayerCntAtLeast=2									--至少几人牌局才能开始(nil或<2表示无效)
	t.nPreAnte =0											--前注（0表示没前注)
	t.isForceBlind=false 	 								--强制盲注 true:开启 false:关闭
	t.nPoolEntryRate=0 										--入池率 0%~100%，95%就是95 (低于300手玩家不限制)
	t.isOnlyPlayByIOS=false									--true:只能IOS设备玩 fasle:所有设备都能玩
	t.isGPSLimit=false										--GPS限制 禁止地理位置接近的玩家同时在一张桌子上进行牌局  true:开启 false:关闭
	t.isIPLimit	=false										--IP限制 禁止相同IP地址的玩家同时在一张桌子上进行牌局  true:开启 false:关闭
	t.isAOF	=false											--是否只有AllIn和弃牌 true:是 false:否
	t.isDelayLook=false										--延迟看牌 true:开启 false:关闭
	t.nInsureMode=0											--保险模式 0:无保险 1:传统保险 2:低水保险
	t.nEnterMin =t.nBigBlind+t.nPreAnte 					--最小进入(玩家必须满足最小进入才能开始游戏)
	if t.isForceBlind then
		t.nEnterMin =t.nForceBlind+t.nPreAnte
	end
	t.nEnterMin =math.max(t.nEnterMin,t.nBuyMin)

	t.nStartAtLeast =t.nPlayerCntAtLeast or 2								--实际使用的开始人数(动态值)
	t.nRoomType =RoomType.nMtt
	t.nHoleCardCnt =(t.nGameId ==Define.nGameId_Ahm) and 4 or 2				--底牌数量(奥哈马玩法为4,底牌数量为4同样也视为奥哈马)
	t.nClubIdOfCorrect=0													 --经过校正后的ClubId (大厅统一用0表示)

	--服务费收取配置
	t.tConfitOfTax ={
		nModeType=0,				   		 --1:按比例  2:按固定 3:按牌桌 0:不收取
		--按比例收取配置
		isProfitOrPool =false, 				--true:按盈利比例 false:按底池比例 x
		nRate=0,							--服务费比例
		nCap =0,							--封顶nCap倍大盲 
		isFreeWhenPreFlop=false,			--翻牌前,免服务费
		isHalfWhenFewUser=false,			--低于3人服务费5折
		nFreeWhenLowProfit=0,				--盈利低于nFreeWhenLowProfit倍大盲,免服务费
		--按固定收取配置
		isProfitOrPoolF =false, 			--true:按盈利分界 false:按底池分界 x
		nMiddleValue=0,						--分界值
		nValueWhenLess=0,					--少于分界值收取
		nValueWhenGreate=0,					--大于等于分界值收取
		--按牌桌
		nTaxRate=0,							--
	}

	t.isTableStart=true	   			--牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	t.isAutoNext=true				--下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始
	if (t.nLiveUserID and t.nLiveUserID>0) and t.nRoomType==RoomType.nClub then
		t.isTableStart=false
		if t.nPlayerCntAtLeast ==nil or t.nPlayerCntAtLeast<2 then
			t.isAutoNext=false
		end
	end

	t.nOpentime =os.time()									--桌子创建时间戳
	--主播可选的房间配置
	t.tDeZhouConfigOption ={arrCapacity={},arrConfig={}} 	--(已无用)
	--本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	t.isConfigNotSet =false									--(已无用)					 	
	
	t.arrPreSetCommCard={}			--预设置的公共牌
	t.arrPreSetCommCardEffect={}	--正在生效使用的预设置公共牌
	t.nOperateTime=15				--操作最大时间,单位:秒 (通常为10)
	t.nJuShu =0						--当前局数
	t.nBankerPos=nil				--庄家位置
	t.arrUsers ={}					--本桌子用户
	t.tUserIdToPos ={}
	t.Timer =tTimerAux:New()
	t.TimerForAndroid =tTimerAux:New()
	t.TimerForAndroidEnter =tTimerAux:New()	--用于控制机器人进桌(勿作它用)
	t.TimerForPause =tTimerAux:New()		--用于桌子暂停计时
	t.TimerForRetain =tTimerAux:New()		--玩家留座计时
	t.TimerForElapWarn=tTimerAux:New()		--时间剩余警告
	t.TimerForForceUp=tTimerAux:New()		--比赛强制站起
	t.TimerForSplit =tTimerAux:New()		--比赛拆桌检测
	t.TimerForMatchStart =tTimerAux:New()	--用于开始比赛
	t.TimerGetMttAndroid =tTimerAux:New()	--用于获取比赛机器人和加入机器人到比赛

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

	t.nPartInCount =0			--牌局开始时，参与牌局的玩家数量
	t.arrPosPartIn	={}			--参与当前牌局的玩家座位号
	t.nTheRightsEndPos =nil		--操作权终止位置(一轮开始时为第一个获得操作权的玩家，接着谁提高了下注值便设置为谁的座位号)
	t.nUserIdLeader=nil			--ai场景信息的一个辅助变量
	t.nTheHighestBet =0			--当前最高下注 (牌局中的玩家,除了弃牌和AllIn的玩家外,一轮结束时，所有人下注都会与该值持平)
	t.nLatelyIncreasesBet=0		--最近一次的nTheHighestBet增幅 (加注提升nTheHighestBet时,提升幅度需>= Max(1个大盲,最近提升幅度))

	t.isBanStandUpReq =false	--游戏中有一些间隙状态, 禁止玩家游戏中站起(现已不会设置为true)

	t.sPaiJuId =""				--牌局id
	
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
	t.isUseHardAi =false			--是否使用强AI (强机器人能预知输赢)(废弃)
	t.nAiModel =0					-- 0:放水模式(150倍大盲内，机器人放开下注) 1:自然模式(牌越好注越大) 2:预知输赢模式(真人唬不住机器人) nil:独立随机使用一个模式

	t.isGapOfNow =false				--当前是否正在流程跳转(调用了定时器，即将跳到下一流程)

	t.nLastHeartTickTime=os.time()	--游戏开始后，会不时更新该时间 (用来辅助检测是否卡桌了)

	t.isTableError=false			--桌子是否检查到出错了

	t.tUserIdToGoldFlowInfo={}		--记录结算过程中的金币流向(写战绩用)
	t.arrWinLoseRecord ={}			--缓存战绩记录，用于延迟写
	t.arrTaxForUpdate={}			--缓存需要延迟更新的抽水记录(按牌桌抽水)

	t.tReview =Review:New()			 --回顾记录
	t.tTableOverview =tOverview:New() --牌桌总览
	t.tStatistic =Statistic:New()	--数据统计

	t.tTimeKeeping={nElapsed=0,nNewBeginStamp=nil,nPauseStamp=nil}

	t.tFlopAfterInsur =nil			--翻牌后保险信息
	t.tTurnAfterInsur =nil			--转牌后保险信息

	t.nInsurPool =0					--保险池

	--表情价格表 (根据配置，其中的值会动态变)
	t.arrChat ={{nChatId=1,nCost=10},{nChatId=2,nCost=10},{nChatId=3,nCost=10},
				{nChatId=4,nCost=10},{nChatId=5,nCost=10},{nChatId=6,nCost=10},
				{nChatId=7,nCost=10},{nChatId=8,nCost=10},{nChatId=9,nCost=10},
				{nChatId=10,nCost=10},{nChatId=11,nCost=10}}

	t.arrDelayCost={50,100,200,400,800}  	--延时操作花费,第一次0，第二次500,...,nil时禁止延时  (根据配置，其中的值会动态变)
	t.nFeeA =100      					 	--看翻牌费用(根据配置，值会动态变)
	t.nFeeB =200       						--看转牌费用(根据配置，值会动态变)
	t.nFeeC =300       						--看河牌费用(根据配置，值会动态变)

	--传统保险赔率表
	t.arrOddsList={31,16,10,8,6,5,4,3.5,3,2.5,2.2,2.1,1.8,1.6,1.4,1.3,1.2,1.1,1,0.8}
	t.nMaxAndroidCnt = math.floor(t.nCapacity / 2)	--机器人最大数量
	t.arrCardsOpenForPay={}				--付费看的牌
	self.nCardOpenFee =-1				--看牌费用

	t.nContinuedNum = 0 			 -- 补开桌子数量

	t.tWarnHistory={}								--桌子剩余时间告警记录
	t.tGather =tTaxGather:New()						--按桌抽水时的一个辅助

	t.tAndroidCfg={nMin=1,nMax=5}					--机器人数量配置
	t.nAndroidCnt =0								--当前机器人数量
	t.nDecrAndroidCnt=0								--牌局结束时需要强制减少的机器人数量
	t.nIncrAndroidCnt=0								--需要增加的机器人数量

	t.tUserLatelyBalance={}							--玩家最近的余额记录(仅记录真人)
	t.tUsersKickToLobbyWhenOver={}					--记录本局结束后,需要踢出到大厅的玩家id

	t.nSlaveUserCnt =0								--真人 旁观数
	t.tOverviewSnapshoot={}							--总览快照
	t.nBackstageRobotAdd =0							--后台动态加减机器人数量

	t.nPlayCnt =0									--桌子手数(发牌次数)
	t.nLatelyStartTime=nil							--最近一局的开始时间
	t.tExpUserR ={}									--用来记录试玩房玩家最近一次写记录的时间

	t.nFirstPos=nil									--一个辅助,不解释

	t.nSeq =0										--机器人ai请求标识
	t.isUseAi= (t.nGameId ==Define.nGameId_Normal and t.isAOF==false)	--是否使用ai请求
	t.isDPreAnte =(t.nGameId ==Define.nGameId_Sc)          -- 庄家是否2倍前注 (短牌时要 )
	t.tAlg =(t.nGameId ==Define.nGameId_Sc) and tScAlg or tAlg	
	
	t.sAiUrl=nil

	t.tOpHistory={}									--玩家各阶段的操作次数(服务于ai场景)
	t.nFirstBet=0									--本局大小盲累计下注总额(服务于ai场景)
	t.arrPreSetCommCardCp={}						--公共牌(服务于ai场景)
	

	--比赛桌新增状态
	t.tUserIdToBind={}								--记录绑定到改桌的比赛玩家信息
	t.nBlindLv=1									--当前盲注级别
	t.nLatelyStageTimeSt=0							--最近一次变换桌子阶段的时间戳
	t.isMatchStart=false							--比赛是否已开始
	t.arrRank ={}					--玩家排名
	t.nMttCnt=0						--比赛总玩家数
	t.nChipAv=0						--平均筹码
	t.isPassOfBindForBatch=false	--是否已经过了统一分配桌子的时间点
	t.tUserIdWait ={}				--当前在本桌子旁观的玩家
	t.nNextAssignTime=nil			--下一次统一分配桌子的时间戳

	t.nMttAndroidNeed =0			--总共需要的比赛机器人数量
	t.nMttAndroidNow =0				--当前已获取的比赛机器人数量
	t.arrMttAndroid={}				--已获取但还没加进比赛的机器人

	--比赛桌新增配置
	t.nEventId=	tJsonConfig.nEventId				--赛事id
	t.tFeeR =tJsonConfig.tFeeR 				        --重购费s
	t.tFeeA =tJsonConfig.tFeeA 					    --增购费s
	t.tEvtTakInR =tJsonConfig.tEvtTakInR 		    --重购规则s
	t.tEvtTakInA =tJsonConfig.tEvtTakInA 		    --增购规则s
	t.arrLvItem =tJsonConfig.arrLvItem 		        --升盲列表s
	t.nBlindUpGap =tJsonConfig.nBlindUpGap     	    --涨盲时间 秒
	t.nTimeStampBegin =tJsonConfig.nTimeStampBegin  --开赛时间(涨盲初始时间)
	t.nTimeBefore=tJsonConfig.nTimeBefore 			--开赛前时间 秒(期间内，已报名者可"进入比赛")
	t.nTimeAfter=tJsonConfig.nTimeAfter				--开赛后时间 秒(期间内，未报名者可"延迟报名",超过后所有人仅能"观战")
	t.nCntBegin =tJsonConfig.nCntBegin				--最小开赛人数
	t.nAwardType=tJsonConfig.nAwardType				--奖励方式 1:固定 2:奖池百分比
	t.arrAward=tJsonConfig.arrAward
	t.arrAwardPercent=tJsonConfig.arrAwardPercent
	t.isWaitRoom =tJsonConfig.isWaitRoom			--是否为等待室(仅用来给玩家等待分配桌子)
	t.isFree =tJsonConfig.isFree					--报名是否免费
	t.nUserCntMax =tJsonConfig.nUserCntMax			--最大报名人数
	t.nLoopType =tJsonConfig.nLoopType              --比赛周期 1按月 2按周 3按天 4按次 5测试循环
	t.sUkey =tJsonConfig.sUkey						--比赛唯一标识
	return t
end


function Table:IsWaitRoom()
	return self.isWaitRoom
end

function Table:GetUserCnt()
	local nCnt =0
	for _,v in pairs(self.arrUsers) do
		nCnt =nCnt +1
	end
	return nCnt,self.nCapacity,nCnt
end

function Table:GetUsersChip()
	local arr={}
	local isPlaying =(TableState.nPlaying ==self.nStage)
	for _,v in pairs(self.arrUsers) do
		local nBetSum =0
		if isPlaying then
			nBetSum =v.nBetSum
		end
		table.insert(arr,{nUserId=v.nUserId,nChip=v.nBalance +nBetSum +v.nBuyTo})
	end
	return arr
end


function Table:UpdateRank(nUserCnt,nChipAv,tUserIdToRank)
	--排名
	local arrRank={}
	for _,v in pairs(self.arrUsers) do
		local nRank =tUserIdToRank[v.nUserId] or 0	--0表示没排名
		table.insert(arrRank,{nUserId=v.nUserId,nRank=nRank})
	end
	self.arrRank =arrRank					--玩家排名
	self.nMttCnt=nUserCnt					--比赛总玩家数
	self.nChipAv=nChipAv					--平均筹码

	self:_BroadCastMttRank()
end

function Table:_BroadCastMttRank()
	--升盲剩余时间 秒
	local nNow =os.time()
	local nBlindUpR =self:_GetBlindUpRemainTime(nNow)
	self:Print("_BroadCastMttRank,nBlindUpR:%d nMttCnt:%d nChipAv:%s",nBlindUpR,self.nMttCnt,tostring(self.nChipAv))

	local nBlindUpTimeSt =nNow +nBlindUpR
	if nBlindUpR<0 then
		nBlindUpTimeSt =-1
	end

	local t={}
	t.arrRank =self.arrRank						--玩家排名
	t.nCnt=self.nMttCnt							--比赛中玩家数
	t.nBlindUpTimeSt=nBlindUpTimeSt				--下一次升盲时间戳 (已达最大级别时 为-1)
	t.nChipAv=self.nChipAv						--平均筹码
	self:_BroadCastToSlaves("MttRank",t)
end

--升盲剩余时间 -1:表示已达到最大盲注级别
function Table:_GetBlindUpRemainTime(nNow)
	if self.nBlindLv >= #self.arrLvItem then
		return -1
	end
	local nNow =nNow or os.time()
	local nBlindUpR =self.nTimeStampBegin +self.nBlindLv *self.nBlindUpGap -nNow
	nBlindUpR =math.max(0,nBlindUpR)
	return nBlindUpR
end


function Table:_UpdateBlind()
	local nNow =os.time()
	local diff =nNow -self.nTimeStampBegin
	diff=math.max(diff,1)
	local nLv =1
	if self.nBlindUpGap>0 then
		nLv =math.ceil(diff/self.nBlindUpGap) 
	end
	nLv = math.min(#self.arrLvItem,nLv)
	local item =self.arrLvItem[nLv]
	if item then
		self.nSmallBlind=item.nSmallB 			--小盲注数额
		self.nBigBlind=item.nBigB				--大盲注数额(通常等于:小盲注x2)
		self.nBlindLv =nLv
		self.nPreAnte =item.nPreAnte or 0
		self:Print("_UpdateBlind to nSmallBlind:%s nBigBlind:%s nBlindLv:%d nPreAnte:%d",tostring(self.nSmallBlind),tostring(self.nBigBlind),self.nBlindLv,self.nPreAnte)
	else
		self:Print("_UpdateBlind Fail,nLv:%d",nLv)
	end
end


function Table:EventId()
	return self.nEventId
end

function Table:_GetRACfg(nRA,nUserId)
	local _,tBindUser =self:_GetSitIdByUserId(nUserId)
	if tBindUser==nil then
		return nil,"NotBindUser"
	end
	local tFee =nil
	local tRule=nil
	local nRACnt =nil
	if nRA==1 then
		tFee =self.tFeeR
		tRule =self.tEvtTakInR
		nRACnt =tBindUser.nRCnt
	elseif nRA==2 then
		tFee =self.tFeeA
		tRule=self.tEvtTakInA
		nRACnt =tBindUser.nACnt
	elseif nRA==0 then
		return nil,"RA_Ban"
	else
		return nil,"NotDefineFlag"
	end
 
	local nCoin,nTicket =0,0			--默认所需金币或门票
	if tFee.nFeeType==2 then			--仅门票
		nTicket =tFee.nTicketNeed
	end
	if tFee.nFeeType==3 then			--金币或门票
		nCoin=tFee.nFeeB
		nTicket =tFee.nTicketNeed
	end
	
	local tRlt ={}
	tRlt.nCoin=nCoin					--所需金币
	tRlt.nChip=tRule.nChip				--可换取的筹码
	tRlt.nCnt=tRule.nCnt-nRACnt			--剩余换取次数
	tRlt.nTicket=nTicket				--所需门票
	tRlt.nRA=nRA
	return tRlt
end

--尝试进入'允许进入比赛阶段'
function Table:_TryStartMatch()
	local nNow =os.time()
	local diff =self.nTimeStampBegin -nNow +2
	self:Print("_TryStartMatch,diff:%d sec",diff)
	diff=math.max(diff,1)
	if diff <60*2 then
		self.TimerForMatchStart:DelayCall(diff*1000,self.StartMatch,self)
		return
	end
	self.TimerForMatchStart:DelayCall(60*1000,self._TryStartMatch,self)
end

function Table:StartMatch()
	self:Print("StartMatch")
	self.isMatchStart=true
	--更新比赛排名和平均筹码等信息
	self:_TryToStartGame()
end

function Table:_TryBindForBatch()
	local nNow =os.time()
	self.nNextAssignTime =self.nTimeStampBegin +1
	local diff =self.nNextAssignTime -nNow
	self:Print("_TryBindForBatch,diff:%d sec",diff)
	self:_BroadCastToSlaves("NextAssignTime",{nNextAssignTime=self.nNextAssignTime})
	diff=math.max(diff,1)
	if diff <60*2 then
		self.TimerForMatchStart:DelayCall(diff*1000,self.BindForBatch,self)
	else
		self.TimerForMatchStart:DelayCall(60*1000,self._TryBindForBatch,self)
	end
end

--为正在等待比赛的玩家统一分配桌子
function Table:BindForBatch()
	local arrUserItem ={}
	for nUserId,item in pairs(self.tUserIdWait) do
		if self:_IsUserSign(item) then
			table.insert(arrUserItem,item)
		else
			self:Print("MTT Waring:Find NotSign User:%d",nUserId)
		end
	end
	local nCnt =#arrUserItem
	self:Print("BindForBatch,nCnt:%d",nCnt)
	local nCntBegin =math.max(self.nCntBegin,2)
	if nCnt <nCntBegin then		--人数太少,取消比赛
		self.tInterFace.CloseMtt(self.nEventId,"UserTooFew",true)	--莫改这原因字符串(被当作了识别码处理的)
	else
		self.isPassOfBindForBatch=true
		self.tInterFace.BindForBatch(self.nEventId,arrUserItem,self.nCapacity,self)
	end
end


--为单个比赛玩家分配桌子
function Table:TryBindForSingle(tUserItem)
	if not self.isWaitRoom then
		return
	end
	if not self.isPassOfBindForBatch then
		return
	end
	if not self:_IsUserSign(tUserItem) then
		return
	end
	self.tInterFace.BindForSingle(self.nEventId,tUserItem,self)
end


--玩家是否已报名
function Table:_IsUserSign(tUserItem)
	if tUserItem.isAndroid then
		return true
	end
	local nUserId =tUserItem.nUserId
	local sField =string.format("U:%d",nUserId)
	local s1,s2,s3 =tPublicRedis.GetMttFieldSplit(self.sUkey,sField)
	return (s1=="ST" and s2=="Sign")
end


--重(增)购窗口打开 请求 
function Table:RAWinReq(tJsonData,sReturnKey)
	local nUserId=tJsonData.nUserId
	local item =self.arrLvItem[self.nBlindLv]
	assert(item~=nil)
	local nRA =item.nRA								--1:可重购 2:可增购 0:不能购
	local tUserCfg,sErr =self:_GetRACfg(nRA,nUserId)
	if tUserCfg==nil then
		self:Print("RAWinReq Fail,sErr:%s nUserId:%d",tostring(sErr),nUserId)
		return
	end
	self:Print("RAWinReq succee,nUserId:%d",nUserId)
	self:_RAWinOpenNotify(sReturnKey,tUserCfg,nUserId,-1)
end

function Table:_RAWinOpenNotify(sReturnKey,tUserCfg,nUserId,nLimitTime)
	local tRlt ={}
	tRlt.nRAFlag=tUserCfg.nRA		--1:可重购 2:可增购 0:不能购
	tRlt.nCoin=tUserCfg.nCoin		--所需金币
	tRlt.nChip=tUserCfg.nChip		--可换取的筹码
	tRlt.nCnt=tUserCfg.nCnt			--剩余换取次数
	tRlt.nLimitTime=nLimitTime		--限时购买时间 秒;>=0时有效
	tRlt.nUserId=nUserId
	self:Print("_RAWinOpenNotify,nUserId:%d nCoin:%d nChip:%d nCnt:%d nLimitTime:%d",nUserId,tRlt.nCoin,tRlt.nChip,tRlt.nCnt,nLimitTime)
	if sReturnKey then
		self:_SendToSlave(sReturnKey,"RAWinRsp",tRlt)
	else
		self:_BroadCastToSlaves("RAWinRsp",tRlt)
	end
end

--是否能重购
function Table:_IsCanRA(nUserId)
	local item =self.arrLvItem[self.nBlindLv]
	assert(item~=nil)

	--非座位玩家,也即非参赛玩家
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		return false,"can not find user",7
	end

	local nRA =item.nRA			--1:可重购 2:可增购 0:不能购
	local tUserCfg,sErr =self:_GetRACfg(nRA,nUserId)
	if tUserCfg==nil then
		return false,sErr,5,tUser
	end

	--剩余次数不足
	if tUserCfg.nCnt <=0 then
		return false,"RemaitCnt is zero",1,tUser
	end
	
	--剩余筹码超过初始筹码
	local nBetSum=0
	if self.nStage ==TableState.nPlaying then
		nBetSum =tUser.nBetSum
	end
	if nRA ==1 and (tUser.nBalance+nBetSum)>=self.nTakeIn then
		return false,"chip too many",2,tUser
	end
	--已经购买过
	if nRA ==1 and tUser.nBuyTo>0 then
		return false,"Repeat",4,tUser
	end
	--扣金币或门票
	if not self:_IsFeeEnough(tUserCfg.nTicket,tUserCfg.nCoin) then
		return false,"FeeNotEnough",3,tUser
	end
	return true,"succee",0,tUser,tUserCfg
end


--重(增)购 请求
function Table:RAReq(tJsonData,sReturnKey)
	local nUserId=tJsonData.nUserId
	local isCan,sErr,nCode,tUser,tUserCfg =self:_IsCanRA(nUserId)
	if not isCan then
		self:Print("RAReq Fail,%s,nUserId:%d",tostring(sErr),nUserId)
		self:_SendToSlave(sReturnKey,"RARsp",{nRlt=(nCode or 10),nUserId=nUserId,nChip=0})
		return
	end
	--取消强制站起倒计时，如果有的话
	self:_StopForceTimer(tUser)

	--扣金币或门票
	if not self:_FeeTake(tUserCfg.nTicket,tUserCfg.nCoin) then
		self:Print("RAReq Fail,Fee not")
		self:_SendToSlave(sReturnKey,"RARsp",{nRlt=3,nUserId=nUserId,nChip=0})
		return
	end

	--购买成功
	tUser.nBuyTo =tUser.nBuyTo +tUserCfg.nChip
	if tUserCfg.nRA==1 then
		tUser.nRCnt =tUser.nRCnt+1	--已重购次数
	end
	if tUserCfg.nRA==2 then
		tUser.nACnt =tUser.nACnt+1	--已增购次数
	end
	self:Print("RAReq,Succee,nUserId:%d",nUserId)
	local tRlt ={}
	tRlt.nRlt=0					--0:成功 1:次数不足 2:筹码过多 3:费用不足 4:重复购买 其它:未定义失败
	tRlt.nChip=tUserCfg.nChip	--获得的筹码数
	tRlt.nUserId=nUserId
	self:_SendToSlave(sReturnKey,"RARsp",tRlt)

	--尝试开始游戏
	self:_TryToStartGame()
end

-- todo 扣门票或金币
function Table:_FeeTake(nTicket,nOrCoin)
	return true
end
-- todo 门票或金币是否足够
function Table:_IsFeeEnough(nTicket,nOrCoin)
	return true
end

--给玩家限时补充筹码,否则强制站起
--返回 0:表示站起淘汰 1:限时补充,否则站起淘汰
function Table:_TryGiveChanceBuyChip(nUserId)
	local isCan,sErr,nCode,tUser,tUserCfg =self:_IsCanRA(nUserId)
	local tTem =tUser or {}
	local nOffLineCnt =tTem.nOffLineCnt or 0
	if (not isCan) or (nOffLineCnt ~=0) or (tUser and tUser.isAndroid) then
		self:Print("_TryGiveChanceBuyChip Fail,nUserId:%d,sErr:%s nOffLineCnt:%d",nUserId,tostring(sErr),nOffLineCnt)
		if tUser then
			self:Oust(tUser.nSitId,nil,"IsNotCanRA")
		else
			assert(false,"MTT Error")
		end
		return 0
	end
	self:Print("_TryGiveChanceBuyChip Succee,nUserId:%d",nUserId)
	local nLimitTimeSec =10
	self:_StopForceTimer(tUser)
	tUser.nToForceUpTimerId= self.TimerForForceUp:DelayCall(nLimitTimeSec*1000+500,self.Oust,self,tUser.nSitId,23,"NoChip")
	self:_RAWinOpenNotify(nil,tUserCfg,nUserId,nLimitTimeSec)
	return 1
end

function Table:_StopForceTimer(tUser)
	if tUser.nToForceUpTimerId then
		self.TimerForForceUp:KillTimer(tUser.nToForceUpTimerId)
		tUser.nToForceUpTimerId =nil
	end
end

--换桌旁观 请求	<触发ClubDeZhouTbChangeNotify>
function Table:ChangeWReq(tJsonData,sReturnKey)
	local nUserId=tJsonData.nUserId

	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	--非旁观玩家
	if nSitId then
		self:Print("ChangeWReq Fail,Not WatchUser")
		return
	end
	local sNextTalbeId =self.tInterFace.GetNextTableIdOfMtt(self.nEventId,self.sTableId)
	--没桌子可换
	if sNextTalbeId==nil or sNextTalbeId ==self.sTableId then
		self:Print("ChangeWReq Fail,No Tb to change")
		return
	end
	self:Print("ChangeWReq,Succee,nUserId:%d,sNextTalbeId:%s",nUserId,sNextTalbeId)
	--回复
	self:_SendChangeWRsp(sReturnKey,sNextTalbeId,1,nUserId)
end

--nReason 0:换到人数较少的桌,继续比赛 1:换桌旁观
function Table:_SendChangeWRsp(sReturnKey,sTableId,nReason,nUserId)
	local tRlt ={}
	tRlt.sTableId=sTableId		--新的桌子id
	tRlt.nReason=nReason		--原因 0:换到人数较少的桌,继续比赛 1:换桌旁观
	tRlt.nUserId=nUserId
	if sReturnKey then
		self:_SendToSlave(sReturnKey,"ChangeWRsp",tRlt)
	else
		self:_BroadCastToSlaves("ChangeWRsp",tRlt)
	end
end

--绑定比赛玩家到本桌(初始绑定或从其它桌转过来)
function Table:BindUser(tUserItem,tD)
	local nUserId =tUserItem.nUserId
	self:Print("BindUser nUserId:%d isAndroid:%s",nUserId,tostring(tUserItem.isAndroid))
	if not tUserItem.isAndroid then
		local sField =string.format("U:%d",nUserId)
		local sValue =string.format("ST:Bind:%s",self.sTableId)
		tPublicRedis.SetMttField(self.sUkey,sField,sValue)
	end
	local tRt =self:OnUserEnter(tUserItem,nil)
	assert(tRt~=nil,"MTT Error")
	self.tInterFace.SendToMatchServ(self.nEventId,"Bind",{nUserId=nUserId,sTableId=self.sTableId})
end

--分配玩家到某个桌子进行比赛
function Table:AssignUserTo(nUserId,sTableIdTo)
	self:Print("AssignUserTo,nUserId:%d sTableIdTo:%s",nUserId,sTableIdTo)
	self:_SendChangeWRsp(nil,sTableIdTo,0,nUserId)					--换桌原因 0:换到人数较少的桌,继续比赛 1:换桌旁观
end


--解绑以便去其它桌
function Table:UnBindForR(nUserId,sTableIdTo)
	self:Print("UnBindForR nUserId:%d sTableIdTo:%s",nUserId,sTableIdTo)
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	assert(tUser~=nil)

	--注意执行顺序 (被从服请离后，该人不能再收通知或回复)
	self:_SetLeaveSeat(nSitId,true)
	self:_SendChangeWRsp(nil,sTableIdTo,0,nUserId)					--换桌原因 0:换到人数较少的桌,继续比赛 1:换桌旁观

	--当本桌没参赛者后，通知旁观的玩家去其它桌子旁观
	if self:_UserCount() ==0 then
		self:_SendChangeWRsp(nil,sTableIdTo,1,0) 					--nUserId为0表示广播给所有玩家
	end
	return nil,tUser
end


--告知比赛服玩家当前筹码
function Table:MttUsersChipNotify(sTip)
	local arr={}
	for nPos,tUser in pairs(self.arrUsers) do
		table.insert(arr,{nBalance =math.floor(tUser.nBalance),nUserId=tUser.nUserId})
	end
	self.tInterFace.SendToMatchServ(self.nEventId,"UsersBalance",{sTableId=self.sTableId,arrUser=arr,sTip=sTip})
end


function Table:_GetAward(nRank)
	--奖励方式 1:固定 2:奖池百分比
	if self.nAwardType==1 then
		local item =self.arrAward[nRank]
		if item ==nil then
			return false,0,0
		end
		return true,item.nCoin,item.nTicket
	end
	if self.nAwardType==2 then
		local item =self.arrAwardPercent[nRank]
		if item ==nil then
			return false,0,0
		end
		return true,1,0
	end
	return false,0,0
end



--淘汰
function Table:Oust(nSitId,nCode,sTips)
	local tUser =self:_GetUser(nSitId)
	if tUser then
		tUser =self:_SetLeaveSeat(nSitId)
	end
	self:Print("Oust nUserId:%d,nCode:%s, sTips:%s",tUser.nUserId,tostring(nCode),tostring(sTips))

	local nMttUserCnt =self.tInterFace.GetMttUserCnt(self.nEventId)
	local nRank =nMttUserCnt +1

	local isAward,nCoin,nTicket =self:_GetAward(nRank)
	local tD ={}
	tD.nRank =nRank
	tD.isAward=isAward			--是否获得奖励 true:是
	tD.nCoin=nCoin					--获得的金币奖励数
	tD.nTicket=nTicket				--获得的门票奖励数
	tD.nUserId=tUser.nUserId
	self:Print("nUserId:%d nRank:%d isAward:%s nCoin:%s nTicket:%s",tUser.nUserId,nRank,tostring(isAward),tostring(nCoin),tostring(nTicket))

	self:_BroadCastToSlaves("UserOust",tD)
	self.tInterFace.SendToMatchServ(self.nEventId,"UserOust",tD)
	
	if nCode then
		self:SendFailNotifyV2(nil,tUser.nUserId,nCode,"_ForceStandUp")
	end
	self.tInterFace.UpdateMttUsersRank(self.nEventId)

	if not tUser.isAndroid then
		local sField =string.format("U:%d",tUser.nUserId)
		local sValue =string.format("ST:Oust:%d",nRank)
		tPublicRedis.SetMttField(self.sUkey,sField,sValue)
	end

	sField =string.format("Rank:%d",nRank)
	sValue =string.format("%d",tUser.nUserId)
	tPublicRedis.SetMttField(self.sUkey,sField,sValue)

	if nMttUserCnt ==0 then
		self.tInterFace.CloseMtt(self.nEventId,"ChampionBorn",true)	--莫改这原因字符串(被当作了识别码处理的)
	end
end


function Table:GetAiReqSeq()
	self.nSeq =self.nSeq +1
	return self.nSeq
end

function Table:_UpdateAiUrl()
	self.sAiUrl =PublicRedis.GetAiUrl(self.nGroupId)
end


function Table:_GetLatelyBalance(nUserId)
	return self.tUserLatelyBalance[nUserId] or 0
end
function Table:_SaveLatelyBalance(nUserId,nBalance,isAndroid)
	if not isAndroid then
		self.tUserLatelyBalance[nUserId] =nBalance
	end
end

function Table:_GetTableConfig()
	local tem ={}
	tem.sTableName=self.sTableName	  			--房间名称,不带<>符号
	tem.sPaiJuId=self.sPaiJuId		 			--牌局编号
	tem.sClubName=self.sClubName	  			--俱乐部名称,不带[]符号
	tem.nSmallBlind=self.nSmallBlind	 		--小盲
	tem.nBigBlind=self.nBigBlind	  			--大盲
	tem.isForceBlind=self.isForceBlind    		--是否强制盲注 true:是 false:否
	tem.isOnlyPlayByIOS=self.isOnlyPlayByIOS 	--是否仅限IOS玩 true:是 fasle:否
	tem.isGPSLimit=self.isGPSLimit	  			--是否开启GPS限制 true:是 fasle:否
	tem.isIPLimit=self.isIPLimit		  		--是否开启ip地址限制 true:是 fasle:否
	tem.nPoolEntryRate=self.nPoolEntryRate 		--入池率限制,取值范围0~100; 0: 表示不限制
	tem.isDelayLook=self.isDelayLook	  		--是否延迟看牌 true:是 fasle:否
	tem.nInsureMode=self.nInsureMode	  		--保险模式 0:无保险 1:传统保险 2:低水保险
	tem.nPreAnte =self.nPreAnte					--前注
	tem.isAOF =self.isAOF						--是否仅限AllIn和弃牌 true:是 其它:否
	tem.nPlayerAtLeast =self.nPlayerCntAtLeast
	if tem.nPlayerAtLeast==nil or tem.nPlayerAtLeast<2 then
		tem.nPlayerAtLeast =10
	end
	tem.isTabkeOut =self.isTabkeOut		    	--是否允许带出
	return tem
end

function Table:_UpdatePriceList(isUpdateChat)
	local tem =tRedisCahche.GetClubChangeConfig(self.nGroupId)
	local arrChat =tem.arrChatChangeCfg or {}
	local arrElse =tem.arrTableChangeCfg or {}

	local tChatIdToPrice ={}
	for _,v in ipairs(arrChat) do
		tChatIdToPrice[v.nChatId] =v.nCost
	end

	local tElseIdToPrice ={}
	for _,v in ipairs(arrElse) do
		tElseIdToPrice[v.nId]=v.nCost
	end

	--更新价格
	if isUpdateChat then
		for _,v in ipairs(self.arrChat) do
			v.nCost = tChatIdToPrice[v.nChatId] or v.nCost
		end
	end

	self.nFeeA =tElseIdToPrice[10] or  self.nFeeA    				--看翻牌费用(根据配置会动态变)
	self.nFeeB =tElseIdToPrice[11] or  self.nFeeB    				--看转牌费用(根据配置会动态变)
	self.nFeeC =tElseIdToPrice[12]  or  self.nFeeC   				--看河牌费用(根据配置会动态变)

	self.arrDelayCost[1] =tElseIdToPrice[1] or self.arrDelayCost[1]
	self.arrDelayCost[2] =tElseIdToPrice[2] or self.arrDelayCost[1]
	self.arrDelayCost[3] =tElseIdToPrice[3] or self.arrDelayCost[2]
	self.arrDelayCost[4] =tElseIdToPrice[4] or self.arrDelayCost[3]
	self.arrDelayCost[5] =tElseIdToPrice[5] or self.arrDelayCost[4]

end


function Table:Init()
	self:_UpdatePriceList(true)
	 self:TryLetAndroidEnter(1)   	--定时检查桌子是否需要加入机器人,是则加入
	 self:TableCheck()           	--定时检查真人进入情况,桌子过久没真人则自动关闭
	 self:_UpdateAndroidCntCfg(1)	--定时更新机器人数量限制配置
	 self:_UpdateBlind()			--更新大小盲注

	if not self.isWaitRoom then
		self:SplitCheck()			--定时检测要不要拆桌，要则拆
		self:_TryStartMatch()
		return
	end
	if self.isFree or self.nLoopType ==5 then	--免费或测试时
		self.nMttAndroidNeed =math.random(self.nCntBegin,math.floor(self.nUserCntMax/2))
	else
		self.nMttAndroidNeed =math.random(self.nCntBegin,self.nCntBegin*3)  
	end
	
	self.nMttAndroidNeed =math.min(self.nMttAndroidNeed,self.nUserCntMax)
	self:Print("nMttAndroidNeed:%d",self.nMttAndroidNeed)
	self:_GetMttAndroid()			--获取足够数量的机器人,以备加入比赛
	self:_TryJoinMttAndroid(0)		--尝试加进机器人到比赛
	self:_TryBindForBatch()
end

--获取足够数量的机器人,以备加入比赛
function Table:_GetMttAndroid()
	if self.nMttAndroidNow>=self.nMttAndroidNeed then
		return
	end
	if os.time()>=(self.nTimeStampBegin +self.nTimeAfter) then
		return
	end
	local nGetCnt = math.floor(Define.nCacheRobot / 2)
	local nGetCnt=math.min(self.nMttAndroidNeed-self.nMttAndroidNow,nGetCnt)

	local arrRobots =self.tInterFace._GetRobots({nGroupId=self.nGroupId,nRoomId=self.nRoomId,nEnterFloorLimit=10*self.nTakeIn},nGetCnt)
	for _,v in ipairs(arrRobots) do
		v.nBalance=nil
		table.insert(self.arrMttAndroid,v)
	end
	self.nMttAndroidNow =self.nMttAndroidNow +#arrRobots
	self.TimerGetMttAndroid:DelayCall(3*1000,self._GetMttAndroid,self)
	self:Print("_GetMttAndroid,nMttAndroidNeed:%d nMttAndroidNow:%d",self.nMttAndroidNeed,self.nMttAndroidNow)
end


--加入机器人到比赛
function Table:_JoinMttAndroid(nFromZero)
	local sSignCnt =tPublicRedis.GetMttField(self.sUkey,"SignCnt")
	local nSignCnt =tonumber(sSignCnt) or 0
	self:Print("_JoinMttAndroid,nSignCnt:%s nUserCntMax:%d nCntBegin:%d isFree:%s",tostring(nSignCnt),self.nUserCntMax,self.nCntBegin,tostring(self.isFree))
	if nSignCnt ==0 or nSignCnt>=self.nUserCntMax then
		return
	end
	if not self.isFree and nSignCnt < (math.floor(self.nCntBegin / 2)) then
		return
	end
	local nJoinMax =self.nUserCntMax -nSignCnt
	nJoinMax =math.min(nJoinMax,self.nCapacity*2)	--self.nCapacity*2 ,这样做是因为只预留了2张空桌子
	local nJoinMin =1
	local nJoinCnt =math.random(nJoinMin,nJoinMax)

	local nCnt=0
	for i=1,nJoinCnt do
		local tRobot =table.remove(self.arrMttAndroid)
		if tRobot==nil then
			break
		end
		self.tUserIdWait[tRobot.nUserId] =tRobot
		self:TryBindForSingle(tRobot)
		local tItem ={}
		tItem.nUserId =tRobot.nUserId
		tItem.sName =tRobot.sName
		tItem.sFaceId =tRobot.sFaceId
		tItem.nGold =tRobot.nGold
		tItem.isAndroid=tRobot.isAndroid
		tItem.nSex=tRobot.nSex
		self.tInterFace.SendToMatchServ(self.nEventId,"MttAndroidJoin",{tRobot=tItem})
		nCnt =nCnt +1
		self:Print("_JoinMttAndroid,nUserId:%d nBalance:%s",tRobot.nUserId,tostring(tRobot.nBalance))
	end
	self:Print("_JoinMttAndroid,nJoinCntShould:%d nAddCnt:%d",nJoinCnt,nCnt)
end


function Table:_TryJoinMttAndroid(nFromZero)
	local nNow =os.time()
	if nNow >=self.nTimeStampBegin +self.nTimeAfter then
		self:Print("_TryJoinMttAndroid,beyondTime")
		return
	end
	local nJoinStart =self.nTimeStampBegin -self.nTimeBefore-120		--允许进入比赛前两分钟开始加机器人
	local diff =nJoinStart -nNow
	self:Print("_TryJoinMttAndroid,diff:%d",diff)
	if diff<=0 then
		self:_JoinMttAndroid(nFromZero)
		self.TimerGetMttAndroid:DelayCall(math.random(5,25)*1000,self._TryJoinMttAndroid,self,nFromZero+1)
	elseif diff <60*2 then
		self.TimerGetMttAndroid:DelayCall((diff+1)*1000,self._TryJoinMttAndroid,self,nFromZero)
	else
		self.TimerGetMttAndroid:DelayCall(60*1000,self._TryJoinMttAndroid,self,nFromZero)
	end
end


--归还还没使用的机器人
function Table:_BackMttAndroid()
	for _,tRobot in ipairs(self.arrMttAndroid) do
		self.tInterFace._LeaveTable(tRobot.nUserId,self)	--归还机器人
	end
end

function Table:SplitCheck()
	self:TrySplit(true)
	self.TimerForSplit:DelayCall(3*1000,self.SplitCheck,self)
end


function Table:CalTax(nProfit,nUserId,isAndroid)
	if self.tConfitOfTax.nModeType==1 then
		return self:TaxByRate(nProfit)
	elseif self.tConfitOfTax.nModeType==2 then
		return self:TaxByFixed(nProfit)
	elseif self.tConfitOfTax.nModeType==3 and (not isAndroid) then			--该模式的抽水，延迟至站起时才收
		local sTaxTag =self.tGather:Gather(nProfit,nUserId,self.sPaiJuId, self.sTableId)	--不记录机器人的抽水
		return 0,sTaxTag
	end
	return 0
end


function Table:TaxByFixed(nProfit)
	if LessOrEqual(nProfit,0) then
		return 0
	end
	local nBody =nProfit
	if not self.tConfitOfTax.isProfitOrPoolF then
		nBody =self:_GetValPoolSum()
	end
	--计算服务费
	local nTax =nil
	if LessThan(nBody,self.tConfitOfTax.nMiddleValue) then
		nTax= self.tConfitOfTax.nValueWhenLess
	else
		nTax= self.tConfitOfTax.nValueWhenGreate
	end
	--服务费不能大于盈利
	nTax =math.min(nTax,nProfit)
	--保留两位小数返回
	nTax =publicApi.Floor_2(nTax)
	return nTax
end

--按比例收取服务费
function Table:TaxByRate(nProfit)
	if LessOrEqual(nProfit,0) then
		return 0
	end
	--翻牌前免服务费
	if self.tConfitOfTax.isFreeWhenPreFlop then
		if #self.arrCommunityCards==0 then
			return 0
		end
	end
	--盈利过低免服务费
	local nLow =self.nBigBlind*self.tConfitOfTax.nFreeWhenLowProfit
	if LessThan(nProfit,nLow) then
		 return 0
	end
	--计算服务费
	local nBody =nProfit
	if not self.tConfitOfTax.isProfitOrPool then
		nBody =self:_GetValPoolSum()
	end
	local nTax =nBody*self.tConfitOfTax.nRate
	--封顶
	nTax =math.min(nTax,self.nBigBlind*self.tConfitOfTax.nCap)
	--低于3人服务费5折
	if self.tConfitOfTax.isHalfWhenFewUser then
		if self.nPartInCount<3 then
			nTax =(nTax/2)
		end
	end
	--服务费不能大于盈利
	nTax =math.min(nTax,nProfit)
	--保留两位小数返回
	nTax =publicApi.Floor_2(nTax)
	return nTax
end


function Table:_GetValPoolSum()
	local nValPoolSum =0
	for _,v in ipairs(self.arrPoolInfo) do
		if #v.arrPosForm>1 then
			nValPoolSum =nValPoolSum +v.nPool
		end
	end
	return nValPoolSum
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
	self:ClubTableInfoNotify({nTableStatus=1})
	self:_BroadCastToSlaves("ElapStatusUpdate",{nElapsedStatus=1})
	self:_ElapWarnReset(true)		--停止剩余时间告警定时器
	self:Print("StopTiming,Table_nElapsed:%d",self.tTimeKeeping.nElapsed)
end


--桌子开始或重新开始计时
function Table:BeginTiming(isInit)
	if self.tTimeKeeping.nNewBeginStamp~=nil then
		return
	end
	self:Print("BeginTiming")
	self.tTimeKeeping.nNewBeginStamp =os.time()
	self.tTimeKeeping.nPauseStamp =nil
	self:_ElapWarnReset(false)		--启动剩余时间告警定时器
	if isInit then 
		return
	end
	self:ClubTableInfoNotify({nTableStatus=0})
	self:_BroadCastToSlaves("ElapStatusUpdate",{nElapsedStatus=0})
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

--桌子当前计时状态  0正常 1暂停
function Table:_ElapsedStatus()
	if self.tTimeKeeping.nNewBeginStamp==nil then
		return 1
	end
	return 0
end

function Table:GetTableInfoForClub()
	local tTableInfo ={}
	tTableInfo.nGameId =self.nGameId
	tTableInfo.sTableName =self.sTableName
	tTableInfo.nItemId =self.nItemId  			--使用的金币id
	tTableInfo.nOpentime =self.nOpentime		--开桌时间
	tTableInfo.nLiveUserID =self.nLiveUserID
	tTableInfo.nKeepTime =self.nKeepTime
	tTableInfo.nSmallBlind =self.nSmallBlind
	tTableInfo.nBigBlind =self.nBigBlind
	tTableInfo.nTakeInMin =self.nBuyMin
	tTableInfo.nTakeInMax =self.nBuyMax
	tTableInfo.nIntervalLev =self.nIntervalLev
	tTableInfo.nCapacity =self.nCapacity
	tTableInfo.nGoldType =self.nGoldType
	tTableInfo.nTableStatus =self:_ElapsedStatus() 				 --0正常 1暂停
	tTableInfo.nStartAtLeast = self.nStartAtLeast
	
	tTableInfo.isAOF =self.isAOF
	tTableInfo.nInsureMode =self.nInsureMode

	tTableInfo.isForceBlind=self.isForceBlind    		--是否强制盲注 true:是 false:否
	tTableInfo.isOnlyPlayByIOS=self.isOnlyPlayByIOS 	--是否仅限IOS玩 true:是 fasle:否
	tTableInfo.isGPSLimit=self.isGPSLimit	  			--是否开启GPS限制 true:是 fasle:否
	tTableInfo.isIPLimit=self.isIPLimit		  			--是否开启ip地址限制 true:是 fasle:否

	tTableInfo.nPreAnte =self.nPreAnte
	tTableInfo.sTableId =self.sTableId
	return tTableInfo
end

--是否使用积分结算
function Table:IsUseCredit()
	if self:MatchRoomId() ==0 then	--试玩房 
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

function Table:Gold_Lock(tUser,nGoldToLock, sourceType)
	if Equal(nGoldToLock,0) then
		nGoldToLock=0
	end
	local nUserId =tUser.nUserId
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUser.Gold_Lock(nUserId,nGoldToLock,self.nItemId) then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable +nGoldToLock
			sourceType = sourceType or PublicDefine.TakeInGoldType.TopUp
			if not tUser.isAndroid and sourceType == PublicDefine.TakeInGoldType.TopUp then -- 非机器人,需要记录买入金额
				RecordDbr.UpdateUserLockGlodRecord(nUserId, self.sTableId, -nGoldToLock)
			end
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
function Table:Gold_UnLock(tUser,nToUnLock)
	nToUnLock =math.max(nToUnLock,0)
	if GreaterThan(nToUnLock,tUser.nLockGoldInTable) then
		return false
	end
	local nUserId =tUser.nUserId
	if  not self:IsUseCredit() then	--非积分结算房
		if tUser.isAndroid or tPubUser.Gold_UnLock(nUserId,nToUnLock,self.nItemId) then
			tUser.nLockGoldInTable =tUser.nLockGoldInTable -nToUnLock
			return true
		end
		return false
	end
	tUser.nLockGoldInTable =tUser.nLockGoldInTable -nToUnLock
	return true
end

function Table:TaxByTableRateSettle(nUserId,isAndroid)
	local nTax,sTaxTag,sLatelyPaiJuId, sLatelyTableId =self.tGather:Settle(nUserId,self.tConfitOfTax.nTaxRate)
	if self:IsUseCredit() then	--积分结算房
		return
	end
	if nTax==nil then
		return
	end
	local nSourceType =10000 +100*self.nGameId +GoldCReason.nTableTax
	local isSuccee =tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=self.nItemId,nDel=-nTax,nSourceType=nSourceType,
		sTableId = sLatelyTableId,
		sPaiJuId = sLatelyPaiJuId})
	if not isSuccee then
		self:Print("TaxByTableRateSettle fail,nUserID:%d,nTax:%.2f,sTaxTag:%s",nUserId,nTax,sTaxTag)
		return
	end
	self:Print("TaxByTableRateSettle,nUserID:%d,nTax:%.2f,sTaxTag:%s,nTaxRate:%.2f",nUserId,nTax,sTaxTag,self.tConfitOfTax.nTaxRate)
	self:WriteRecordForTax(nUserId,nTax,sTaxTag,sLatelyPaiJuId,isAndroid)
end

function Table:TaxByTableRateSettle_All()
	local arrUserId =self.tGather:GetAllUserId()
	for _,nUserId in ipairs(arrUserId) do
		self:TaxByTableRateSettle(nUserId,false)
	end
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
		self.nAiModel =2
		return self.nAiModel  --best hard
	end
	if self.isControl==4 then
		self.nAiModel =0
		return self.nAiModel
	end

	local tWaterInfo= Define.AssertWaterInfoExist(self.nBigBlind)
	local nCurSysWinRate =(tWaterInfo.nSysSumIn /tWaterInfo.nSysSumOut)
	if nCurSysWinRate< 1 then
		self.nAiModel =2
		return self.nAiModel  --best hard
	end
	if nCurSysWinRate < Define.nSysWinRate and math.random(1,100) <70 then
		self.nAiModel =2
		return self.nAiModel  --best hard
	end
	self.nAiModel =nil
	return self.nAiModel
end

--机器人根据该返回决定是否使用预知输赢模式来进行游戏 (废弃)
function Table:IsPoolEnough()
	if self.isUseHardAi then
		return false
	end
	return true
end
-- 0:放水模式(100倍大盲内，机器人放开下注) 1:自然模式(牌越好注越大) 2:预知输赢模式(真人唬不住机器人) 
function Table:RobotActModel()
	return self.nAiModel
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

	--从服玩家坐下
	if sCmd =="SlaveUserSit" then
		self.tTableOverview:LookerIn(tJsonData.nUserId,tJsonData.sName,tJsonData.sFaceId)
		self.nSlaveUserCnt=self.nSlaveUserCnt +1
		self.tUserIdWait[tJsonData.nUserId] =tJsonData.item
		self:UserOnLine(tJsonData.nUserId)
		self:TryBindForSingle(tJsonData.item)
		return
	end
	--从服玩家离开
	if sCmd =="SlaveUserUp" then
		self.nSlaveUserCnt=self.nSlaveUserCnt -1
		self.tUserIdWait[tJsonData.nUserId] =nil
		self:OnSlaveUserUp(tJsonData)
		return
	end
	--用户离线通知
	if sCmd =="UserOffLine" then
		self:UserOffLine(tJsonData,sReturnKey)
		return
	end
	--用户上线通知
	if sCmd =="UserOnLine" then
		self:UserOnLine(tJsonData.nUserId)
		return
	end
	--从服人数汇报
	if sCmd =="UserCnt_Report" then
		self:UserCnt_Report(tJsonData)
		return
	end


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
	--Gm命令
	if sCmd =="DeZhouGmReq" then
		self:DeZhouGmReq(tJsonData,sReturnKey)
		return
	end
	--后台踢人
	if sCmd =="REQ_Kick_User" then
		self:REQ_Kick_User(tJsonData,sReturnKey)
		return
	end
	--牌桌总览请求
	if sCmd =="OverViewReq" then
		self:OverViewReq(tJsonData,sReturnKey)
		return
	end
	--保险购买请求
	if sCmd =="InsurBuyReq" then
		self:InsurBuyReq(tJsonData,sReturnKey)
		return
	end
	--延时请求
	if sCmd =="DelayReq" then
		self:DelayReq(tJsonData,sReturnKey)
		return
	end
	--'留座离桌'或'回到座位' 请求
	if sCmd =="RetainReq" then
		self:RetainReq(tJsonData,sReturnKey)
		return
	end
	--翻牌请求
	if sCmd =="CardOpenReq" then
		self:CardOpenReq(tJsonData,sReturnKey)
		return
	end

	--重(增)购窗口打开 请求 <触发ClubDeZhouRANotify>
	if sCmd =="RAWinReq" then
		self:RAWinReq(tJsonData,sReturnKey)
		return
	end
	--换桌旁观 请求	<触发ClubDeZhouTbChangeNotify>
	if sCmd =="ChangeWReq" then
		self:ChangeWReq(tJsonData,sReturnKey)
		return
	end
	--重(增)购 请求
	if sCmd =="RAReq" then
		self:RAReq(tJsonData,sReturnKey)
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

--用户下线通知(来自从服,掉线或返回大厅都使用该通知)
function Table:UserOffLine(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local isBackToLobby =(tJsonData.sReason =="BackToLobby")

	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		return
	end
	if (not self:_IsPartInUser(nSitId)) and (not tUser.isRetain or isBackToLobby) then 
		self:Oust(nSitId,nil,"OffLine")
		return
	end
	tUser.nOffLineCnt =tUser.nOffLineCnt +1
	tUser.isBackToLobby =isBackToLobby
	self:Print("User_%d OffLineCnt Became:%d",nUserId,tUser.nOffLineCnt)
end


--用户重新上线通知(来自从服)
function Table:UserOnLine(nUserId)
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		return
	end
	tUser.nOffLineCnt =tUser.nOffLineCnt -1
	tUser.isBackToLobby =false
	self:Print("User_%d OffLineCnt Became:%d",nUserId,tUser.nOffLineCnt)
end

function Table:_GetChatCost(nChatId)
	for _,v in ipairs(self.arrChat) do
		if v.nChatId ==nChatId then
			return v.nCost
		end
	end
	return 0
end

--表情聊天请求(来自从服)---
function Table:_DeZhouChatReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	self:Print("_DeZhouChatReq,nSitId:%d nChatId:%d nTarget:%s",(nSitId or -1),tData.nChatId,tostring(tData.nTarget))
	nSitId=nSitId or 0				--聊天发起者座位号，如果是旁观者则用0表示
	--if not nSitId then
	--	self:Print("Chat Fail,Not Player Pos")
	--	return
	--end
	if self:_IsPlayerPos(tData.nTarget or 0) then
		if not self:_GetUser(tData.nTarget) then
			self:Print("Chat Fail,nTarget Pos User is Nil")
			return
		end
	end

	local nCost =self:_GetChatCost(tData.nChatId)
	self:Print("Chat Cost:%.2f",nCost)
	--扣金币
	if nCost>0 then
		local nSourceType =10000 +100*self.nGameId +GoldCReason.nFaceChat
		if not tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=1,nDel=-nCost,nSourceType=nSourceType, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or ""}) then
			self:Print("Chat Fail,no Gold ")
			self:SendFailNotifyV2(sReturnKey,nUserId,36,"no Gold")
			return
		end
		-- local data,err = assets_manager:OtherConsumption(nUserId,nCost*100,"表情聊天扣除金币")
		-- self:Print("Chat Cost Result,data:%s err:%s",tostring(data),tostring(err))
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
	self:_SendToSlave(sReturnKey,"DeZhouPauseRsp",{isPause =tData.isPause,nUserId=nUserId})
	self:_ChangePause(tData.isPause)
end

function Table:_ChangePause(isPause)
	if self.isPause ==isPause then
		self:Print("WaringPause")
		return
	end
	self.isPause =isPause
	if self.isPause then
		self:_Pause()
	else
		self.TimerForPause:KillAllTimer()
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

--筹码带出范围查看请求(来自从服)
function Table:TakeOutRangeReq(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local TakeOutRangeRsp ={}
	TakeOutRangeRsp.nGold =0
	TakeOutRangeRsp.nNowSelect=0     											--当前选择带出的筹码
	TakeOutRangeRsp.nMax =0													--最大可带出
	TakeOutRangeRsp.nUserId=nUserId
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("TakeOutRangeReq Fail, can not find user_%d in player seat",nUserId)
		TakeOutRangeRsp.nGold =tPubUser.Get_User_UnLockGold(nUserId,self.nItemId)	--当前身上金币
		self:_SendToSlave(sReturnKey,"TakeOutRangeRsp",TakeOutRangeRsp)
		return
	end
	TakeOutRangeRsp.nGold =self:Get_User_UnLockGold(tUser)
	TakeOutRangeRsp.nMax =math.max(tUser.nBalance -self.nEnterMin,0)
	TakeOutRangeRsp.nNowSelect=math.min(tUser.nTakeOutWant,TakeOutRangeRsp.nMax)
	self:_SendToSlave(sReturnKey,"TakeOutRangeRsp",TakeOutRangeRsp)
end

--筹码带出请求(来自从服)
function Table:TakeOutReq(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local nTakeOut =tJsonData.nTakeOut
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("TakeOutReq Fail, can not find user_%d in player seat",nUserId)
		self:_SendToSlave(sReturnKey,"TakeOutRsp",{nUserId=nUserId,nRlt=1})
		return
	end
	--比赛桌 禁止该请求
	if true then
		self:Print("TakeOutReq Fail,Ban")
		self:_SendToSlave(sReturnKey,"TakeOutRsp",{nUserId=nUserId,nRlt=0})
		return
	end

	tUser.nTakeOutWant =math.max(nTakeOut,0)
	tUser.nBuyTo=0 						
	tUser.nIsAutoBuy=false
	self:_SendToSlave(sReturnKey,"TakeOutRsp",{nUserId=nUserId,nRlt=0})
end

--留座
function Table:_Retain(nUserId)
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		return -1,"user not in seat"
	end
	if tUser.isRetain then
		return -2,"state wrong"
	end
	tUser.isRetain =true

	if #tUser.arrHoleCards>0 then	--本手牌结束后计时再生效
		return 1
	end
	--开始留座倒计时
	local isB =self:_RetainCountDown(tUser)
	assert(isB,"something wrong")
	return 0
end

--取消留座
function Table:_RetainCancel(nUserId,isByTimeOut)
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		return -1,"user not in seat"
	end
	if not tUser.isRetain then
		return -2,"state wrong"
	end
	tUser.isRetain =false
	--取消留座倒计时,如果有的话
	self:_RetainCountDownCancel(tUser)

	if (tUser.nOffLineCnt ~=0 or isByTimeOut) and (not self:_IsPartInUser(nSitId)) then
		self:Oust(nSitId,nil,"RetainCancel")
		return
	end

	self:_TryToStartGame()
	return 0
end

--留座倒计时开始,如果还没开始的话 (离开座位时取消，或玩家主动取消) 
function Table:_RetainCountDown(tUser)
	if tUser.nRetainTimerId then
		return false
	end
	local nSeconds =Define.nRetainTime
	tUser.nRetainTimerId =self.TimerForRetain:DelayCall(nSeconds*1000,self._RetainCancel,self,tUser.nUserId,true)
	--广播
	self:Print("_RetainCountDown for user:%d",tUser.nUserId)
	self:_BroadCastToSlaves("RetainNotify",{nPos=tUser.nSitId,nOp=0,nSeconds=nSeconds})
	return true
end

--取消留座倒计时,如果有的话
function Table:_RetainCountDownCancel(tUser)
	if not tUser.nRetainTimerId then
		return false
	end
	self.TimerForRetain:KillTimer(tUser.nRetainTimerId)
	tUser.nRetainTimerId=nil
	--广播
	self:Print("_RetainCountDownCancel for user:%d",tUser.nUserId)
	self:_BroadCastToSlaves("RetainNotify",{nPos=tUser.nSitId,nOp=1})
	return true
end

--翻牌请求
function Table:CardOpenReq(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	self:Print("CardOpenReq nUserId:%d",nUserId)

	--非结算阶段不允许操作
	if self.nStage ~=TableState.nSettle then
		self:Print("stage wrong")
		return
	end
	--没牌可看
	if #self.arrCardsOpenForPay==0 then
		self:Print("no cards for open")
		return
	end
	--扣金币
	local nCost =self.nCardOpenFee
	if nCost>0 then
		local nSourceType =10000 +100*self.nGameId +GoldCReason.nLookCard
		if not tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=1,nDel=-nCost,nSourceType=nSourceType, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or ""}) then
			self:Print("gold not enought")
			self:_SendToSlave(sReturnKey,"CardOpenRsp",{nRlt=1,arrCards={},nUserId=nUserId})
			return
		end
	end

	self:Print("CardOpenReq succee,nCardOpenFee:%.2f nUserId:%d",nCost,nUserId)
	--回复
	self:_SendToSlave(sReturnKey,"CardOpenRsp",{nRlt=0,arrCards=self.arrCardsOpenForPay,nUserId=nUserId})
end


--'留座离桌'或'回到座位' 请求(来自从服)
function Table:RetainReq(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local nOp =tJsonData.nOp					
	self:Print("RetainReq nUserId:%d nOp:%d",nUserId,nOp)

	--0:留座离桌
	if nOp ==0 then
		local nCode,sErr =self:_Retain(nUserId)
		self:Print("_Retain nCode:%d sErr:%s",nCode,(sErr or "succee"))
		--回复
		self:_SendToSlave(sReturnKey,"RetainRsp",{nRlt=nCode,nOp=nOp,nUserId=nUserId})
		return
	end

	--1:取消'留座离桌'
	if nOp==1 then
		local nCode,sErr =self:_RetainCancel(nUserId)
		self:Print("_Retain nCode:%d sErr:%s",nCode,(sErr or "succee"))
		--回复
		self:_SendToSlave(sReturnKey,"RetainRsp",{nRlt=nCode,nOp=nOp,nUserId=nUserId})
		return
	end
	self:Print("RetainReq parameter error")
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
	
	--比赛桌 禁止该买入请求
	if true then
		self:Print("DeZhoTakeInReq Fail,Ban")
		self:_SendToSlave(sReturnKey,"TakeInRsp",{nRlt=0,nBalance=tUser.nBalance,nUserId=tData.nUserId})
		return
	end

	local nBuyTo =tData.nBuyTo +tUser.nBalance
	if not (LessOrEqual(nBuyTo,self.nBuyMax)) then		--有意不做严格限制
		self:Print("DeZhoTakeInReq Fail,Out of Range,nBalance:%.2f",tUser.nBalance)
		self:_SendToSlave(sReturnKey,"TakeInRsp",{nRlt=0,nBalance=tUser.nBalance,nUserId=tData.nUserId})
		return 
	end
	local nMax =self:Get_User_UnLockGold(tUser) + tUser.nBalance
	if GreaterThan(nBuyTo, nMax) then
		self:Print("DeZhoTakeInReq Fail,Gold Not Enough,nMax:%.2f,nBalance:%.2f",nMax,tUser.nBalance)
		self:_SendToSlave(sReturnKey,"TakeInRsp",{nRlt=0,nBalance=tUser.nBalance,nUserId=tData.nUserId})
		return 
	end

	tUser.nBuyTo=tData.nBuyTo 						
	tUser.nIsAutoBuy=tData.nIsAutoBuy
	tUser.nTakeOutWant =0

	local nBalance=-1							-->=0:买入后当前筹码 ,-1:买入后下局生效
	if not self:_IsPartInUser(nSitId) then		--非游戏中时，实时带入筹码
		if not self:_InitUserTakeIn(tUser,nBuyTo,0) then  
			self:Print("DeZhoTakeInReq,Error happen")
		end
		tUser.nBalance=tUser.nLockGoldInTable	--当前可用筹码
		nBalance =tUser.nBalance
		if not (tUser.nIsAutoBuy==1) then		--非每局自动带入时，只生效一次
			tUser.nBuyTo=0
		end
	end
	self.tTableOverview:HaveTakeIn(tData.nUserId,tUser.sName,tUser.nBalance,tUser.sFaceId)
	--回复
	self:_SendToSlave(sReturnKey,"TakeInRsp",{nRlt=0,nBalance=nBalance,nUserId=tData.nUserId})
	--尝试开始游戏
	self:_TryToStartGame()
end


--从服人数汇报(来自从服)---
function Table:UserCnt_Report(tData)
	if tData.isHaveUser then
		self.nTimestampZeroRealUser=os.time()		--过久不刷新该时间值,便视为过久没真人玩家进入
	end
end

--"开始牌局"请求,房主使用 (来自从服)
function Table:TableStartReq(tJsonData,sReturnKey)
	if self.isTableStart then
		self:Print("already start")
		return
	end
	self.isTableStart =true
	--self:BeginTiming()
	self:_BroadCastToSlaves("TableStarNotify",{isTableStart=true})
	self:_TryToStartGame()
end

--"开始游戏" 请求,房主使用 (来自从服)
function Table:AutoNextReq(tJsonData,sReturnKey)
	--if self.isAutoNext then
	--	self:Print("already AutoNext")
	--	return
	--end
	self.nStartAtLeast =2
	self.isAutoNext =true
	self:_BroadCastToSlaves("AutoNextNotify",{isAutoNext=true})
	self:_TryToStartGame()
end

--牌局总览请求(来自从服)---
function Table:OverViewReq(tData,sReturnKey)
	local nUserId=tData.nUserId
	local nNoUse =tData.nNoUse or 0
	self:Print("OverViewReq nUserId:%d nNoUse:%d",nUserId,nNoUse)
	if nNoUse ==0 then
		local tOverview= self.tTableOverview:GetOverview()
		self:Print("OverViewReq arrPartInUser Len:%d",#tOverview.arrPartInUser)
		local tRemainStack =_CutOff(tOverview.arrPartInUser,Define.nOverViewRtLen)	--截断arrPartInUser,只保留20个数据
		tOverview.sPaiJuId=self.sPaiJuId
		tOverview.sTableName=self.sTableName
		tOverview.nSmallBlind=self.nSmallBlind
		tOverview.nBigBlind=self.nBigBlind
		tOverview.nBetBefore=self.nPreAnte						--前注
		tOverview.nInsur =self.nInsurPool						--保险池
		tOverview.nRound=self.nJuShu
		tOverview.nRemainTime=self:_GetRemainTime()						--剩余时间
		tOverview.nEndFlag =tRemainStack:IsEmpty() and 0 or 1			--1:列表还未结束, 其它:已结束
		self:_SendToSlave(sReturnKey,"OverviewRsp",{tOverview=tOverview,nUserId=tData.nUserId})
		--创建快照
		tOverview.arrPartInUser ={}
		self:_DoSnapshoot(nUserId,tOverview,tRemainStack)
		return
	end
	if nNoUse==1 then
		local tOverview,tRemainStack =self:ObtainFromSnapshoot(nUserId)
		assert(tOverview~=nil)
		tOverview.nRemainTime=self:_GetRemainTime()
		tOverview.nEndFlag =tRemainStack:IsEmpty() and 0 or 1			--1:列表还未结束, 其它:已结束
		self:_SendToSlave(sReturnKey,"OverviewRsp",{tOverview=tOverview,nUserId=tData.nUserId})
		--创建快照
		tOverview.arrPartInUser ={}
		self:_DoSnapshoot(nUserId,tOverview,tRemainStack)
		return
	end
	if nNoUse== -1 then
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
	while (#arrPartInUser<Define.nOverViewRtLen and (not tRemainStack:IsEmpty())) do
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
		self.tOverviewSnapshoot[nUserId]=nil
	end
end


--主播踢人请求(来自从服)---
function Table:DeZhouKickUserReq(tData,sReturnKey)
end

--Gm命令请求(来自从服)
function Table:DeZhouGmReq(tData,sReturnKey)
	local nSitId,tUser =self:_GetSitIdByUserId(tData.nUserId)
	self:Print("DeZhouGmReq:%s",tData.sStr)
	if tData.sStr=="close" then
		self:SetClose(TableCloseReason.nGmClose)
		return
	end
	if tData.sStr=="rawin" then
		self:RAWinReq({nUserId=tData.nUserId})
		return
	end
	if tData.sStr=="aareq" then
		self:RAReq({nUserId=tData.nUserId})
		return
	end
	if tData.sStr=="changewreq" then
		self:ChangeWReq({nUserId=tData.nUserId})
		return
	end
	
	if tData.sStr=="ai" then
		self.isUseAi =true
		return 
	end
	if tData.sStr=="aiban" then
		self.isUseAi =false
		return 
	end

	if tData.sStr=="y2" then
		Define.nOverViewRtLen=2
		return
	end
	if tData.sStr=="y5" then
		Define.nOverViewRtLen=5
		return
	end
	if tData.sStr=="y10" then
		Define.nOverViewRtLen=10
		return
	end
	if tData.sStr=="y20" then
		Define.nOverViewRtLen=20
		return
	end
	
	if tData.sStr=="retain" then
		self:_Retain(tUser.nUserId)
		return
	end
	if tData.sStr=="retainC" then
		self:_RetainCancel(tUser.nUserId)
		return
	end

	if tData.sStr=="Config" then
		self.isConfigNotSet=false
	end
	if tData.sStr=="TableStartReq" then
		self:TableStartReq()
		return
	end
	if tData.sStr=="AutoNextReq" then
		self:AutoNextReq()
		return 
	end
	if tData.sStr=="Pause" then
		self:_ChangePause(true)
		return 
	end
	if tData.sStr=="CancelPause" then
		self:_ChangePause(false)
		return 
	end
	if tData.sStr=="DelayReq" and tUser then
		self:DelayReq({nUserId=tUser.nUserId})
		return
	end
	if tData.sStr=="h2" then
		self.nHoleCardCnt=2
		return
	end
	if tData.sStr=="h4" then
		self.nHoleCardCnt=4
		return
	end
	if tData.sStr=="DR" then
		self.nMaxAndroidCnt =self.nMaxAndroidCnt -1
		self.nMaxAndroidCnt =math.max(0,self.nMaxAndroidCnt)
		self:Print("DR nMaxAndroidCnt:%d",self.nMaxAndroidCnt)
		return
	end
	if tData.sStr=="IR" then
		self.nMaxAndroidCnt =self.nMaxAndroidCnt +1
		self.nMaxAndroidCnt =math.min(self.nMaxAndroidCnt,self.nCapacity)
		return
	end

	if tData.sStr=="TakeOutReq" then
		self:TakeOutReq({nUserId=tData.nUserId,nTakeOut=100000})
		return
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
	return 
end


function Table:DelayReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	self:Print("DelayReq,nUserId:%d",nUserId)

	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("DelayReq Fail, can not find user_%d in player seat",nUserId)
		return
	end
	self:_CancelAuto(tUser)		--取消托管
	tUser.isHaveOp =true		--当局是否有操作
	tUser.nTimeOutCnt=0

	local tOperation =tUser.tOperation
	if tOperation==nil then
		self:Print("DelayReq Fail,tOperation is nil")
		return
	end

	self:Print("nDelayCount:%d",tUser.nDelayCount)
	--延时操作花费
	local nDelayCost =nil
	if tUser.nDelayCount ==0 then
		nDelayCost =tOperation.nDelayCost
	else
		nDelayCost =self.arrDelayCost[tUser.nDelayCount+1]
	end
	if nDelayCost==nil then
		self:Print("DelayReq Fail,nDelayCost is nil")
		return
	end

	--扣金币
	if nDelayCost>0 then
		local nSourceType =10000 +100*self.nGameId +GoldCReason.nOpDelay
		if not tPubUser.ChangeUserTreasure({nUserID=nUserId,nItemID=1,nDel=-nDelayCost,nSourceType=nSourceType, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or ""}) then
			self:_SendToSlave(sReturnKey,"DelayRsp",{nUserId=nUserId,nRlt=1,nDelayCost=nDelayCost}) --金币不足
			return
		end
	end

	--延长超时时间
	local nAddTime =Define.nAddTime				--延时增加的时间 秒
	local nNow =os.time()
	local nElapse =nNow -tUser.nGetRightTime
	assert(nElapse>=0)
	local nRemain =tUser.nOpLong -nElapse
	nRemain =math.max(nRemain,0)
	local nNewOpLong =nRemain +nAddTime
	tUser.nGetRightTime =nNow
	tUser.nOpLong =nNewOpLong
	tUser.nDelayCount =tUser.nDelayCount +1
	self:_ToOpForTimeOutUser(nNewOpLong,nSitId)

	local nNextCost =self.arrDelayCost[tUser.nDelayCount+1]
	nNextCost =nNextCost or -1
	--成功回复
	self:_SendToSlave(sReturnKey,"DelayRsp",{nOpLong=nNewOpLong,nGetRightTime=nNow,nUserId=nUserId,nRlt=0,nDelayCost=nNextCost})
	--有人延时成功广播
	self:_BroadCastToSlaves("DelayNotify",{nPos=nSitId,nSeconds=nAddTime,nRemain=nNewOpLong})
end

--从服玩家离开
function Table:OnSlaveUserUp(tJsonData)
	self:_DoSnapshoot(tJsonData.nUserId)								--清空总览快照
	self.tTableOverview:UserLeave(tJsonData.nUserId)
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
	tUser.nTimeOutCnt=0

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

		if GreaterThan(nRaise,tUser.nBalance) then
			self:Print("nRaise:%.2f LimitTo:%.2f",nRaise,tUser.nBalance)
			nRaise =tUser.nBalance
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
	tUser.nTimeOutCnt=0
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

function Table:_IsBanUserStanpUp(tUser)
	if tUser.nStatus==UserStatus.nLooker then 
		return false
	end
	if tUser.nStatus==UserStatus.nFold then
		return false
	end
	if not tUser.isNeedSettle then
		return false
	end
	local tInsur =self.tFlopAfterInsur or self.tTurnAfterInsur
	if tInsur then
		return true
	end
	return false
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
	if self:_IsBanUserStanpUp(tUser) then
		self:Print("ban user stanpUp")
		return 
	end
	
	self:Print("DeZhouStanpUpReq,nSitId:%d nUserId:%d",nSitId,nUserId)
	self:Oust(nSitId,nil,"StanpUpReq")
end	

--根据gps判断是否存在距离过近的玩家
function Table:IsHaveNearUser(tGps)
	local nLongitudeA =tGps.nLongitude
	local nLatitudeA=tGps.nLatitude
	self:Print("nLongitudeA:%f ,nLatitudeA:%f",nLongitudeA,nLatitudeA)

	for _,tUser in pairs(self.arrUsers) do
		if (not tUser.isAndroid) and tUser.tGps then
			local nLongitudeB =tUser.tGps.nLongitude
			local nLatitudeB=tUser.tGps.nLatitude
			self:Print("nLongitudeB:%f ,nLatitudeB:%f",nLongitudeB,nLatitudeB)
			local nDistance =GetDistance(nLongitudeA, nLatitudeA,nLongitudeB,nLatitudeB)
			nDistance =nDistance*1000 --转换为 米
			if nDistance<=200 then	  --200米以内视作距离过近
				return true
			end
		end
	end
	return false
end

--判断是否有相同IP玩家
function Table:IsHaveSaveIp(nUserId)
	local sIp =tPubUser.GetUserIP(nUserId)
	local sDotIp =publicApi.Dword2String(tonumber(sIp) or 0)
	self:Print("nUserId_%d nIp:%s sIp:%s",nUserId,sIp,sDotIp)
	for _,tUser in pairs(self.arrUsers) do
		if (not tUser.isAndroid) then
			local ssIp =tPubUser.GetUserIP(tUser.nUserId)
			local ssDotIp =publicApi.Dword2String(tonumber(ssIp) or 0)
			self:Print("nUserId_%d nIp:%s sIp:%s",tUser.nUserId,ssIp,ssDotIp)
			if tonumber(sIp) ==tonumber(ssIp) then
				return true
			end
		end
	end
	return false
end


--检查入池率限制 true:通过 false:不通过
function Table:_CheckPoolEntryRate(nUserId)
	if self.nPoolEntryRate <=0 then
		return true
	end
	local tInfo =tPublicRedis.GetUserTexaStatistic(nUserId,self.nClubIdOfCorrect,self.nGameId,self.nGoldType)
	if tInfo.nPlayCount <=Define.nAxx then
		return true
	end
	local nRate =tInfo.nInPoolCount/tInfo.nPlayCount
	if (nRate*100) <self.nPoolEntryRate then
		return false
	end
	return true
end


--坐下请求(来自从服)
function Table:DeZhouSitDownReq(tData,sReturnKey)
	local nUserId =tData.nUserId
	local tUserInfo =tData.tUserInfo
	self:Print("DeZhouSitDownReq,nPos:%d",tData.nPos)
	
	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if nSitId then
		self:Print("already in Player seat")
		self:SendFailNotifyV2(sReturnKey,nUserId,15,"already in Player seat")
		return
	end

	if true then
		self:Print("Can not sit by self")
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


function Table:StartGame()
	self.nJuShu =self.nJuShu +1
	self:Print("StartGame,nFee:%.2f,nTax:%.2f nItemId:%d",self.nFee,self.nTax,self.nItemId)
	self:_ResetTable()
	self:_ResetUsers()
	self:_UpdateIntervalTime()
	self:_UpdatePriceList(false)		--不更新表情价格(因为表情价格在场景里发给了前端，动态更新的话会出现不一致)
	self:_UpdateAiUrl()

	--锁定玩家入场必要的金币(一个辅助函数)
	local function _DoLockGold(tUser)
		local nBuyTo =0
		if tUser.nIsAutoBuy==1 then												--自动补充时
			nBuyTo =Equal(tUser.nLockGoldInTable,0) and self.nBuyMax or 0		--只有在剩余筹码为0时才会触发 (自动补充到最大买入)
		else
			nBuyTo=tUser.nBuyTo +tUser.nBalance
			tUser.nBuyTo =0														--如非设置每局自动买入,则设置的买入只生效一次	
		end
		local isSuccee,nNewLock =self:_InitUserTakeIn(tUser,nBuyTo,0)
		if not isSuccee then
			return false
		end
		tUser.nChipBuy =math.floor(nNewLock)
		return true
	end

	--尝试执行带出操作
	local function _TryDoTakeOut(tUser)
		if tUser.nTakeOutWant ==0 then 
			return
		end
		local nCanTakeOutMax =math.max(tUser.nLockGoldInTable -self.nEnterMin,0)
		local nTakeOut =math.min(nCanTakeOutMax,tUser.nTakeOutWant)
		local isSuccee =self:Gold_UnLock(tUser,nTakeOut)
		assert(isSuccee)
		tUser.nBalance = tUser.nLockGoldInTable
		tUser.nTakeOutWant =0
	end

	--确定可以参与本次牌局的玩家
	local arrPosPartIn ={}
	local arrUserPartIn ={}
	for nPos,tUser in pairs(self.arrUsers) do
		if (not tUser.isRetain) then
			_TryDoTakeOut(tUser)									--尝试执行玩家设置的带出操作
			_DoLockGold(tUser)										--尝试补充筹码
			if GreaterThan(tUser.nLockGoldInTable,0) then
				table.insert(arrPosPartIn,nPos)
				table.insert(arrUserPartIn,tUser)
				tUser.nBalance =tUser.nLockGoldInTable 				--初始化玩家可用筹码
				self:Print("PartInUser_%d,nPos_%d,nNowLock:%.3f,nBalance:%.3f isAndroid:%s",
					tUser.nUserId,nPos,tUser.nLockGoldInTable,tUser.nBalance,tostring(tUser.isAndroid))
			end
		end
	end

	--判断人数是否足够开始游戏
	assert(#arrPosPartIn ==#arrUserPartIn)
	if #arrPosPartIn <2 then 
		self:Print("StartGame Fail,PartIn UserCnt not enough")
		return
	end
	self:_UpdateBlind()	--更新大小盲注

	self.arrPosPartIn =arrPosPartIn
	self.nPartInCount =#arrPosPartIn			--牌局开始时，参与牌局的玩家数量

	--牌局id生成
	self.sPaiJuId =tPubUser.CreatePaiJuID()   

	self.tStatistic:Init()
	self.tTableOverview:PaiJuStart()
	--回顾记录
	self.tReview:Init(self.sPaiJuId,self.nSmallBlind,self.nBigBlind,self.nCapacity,self.nOperateTime)
	for _,v in ipairs(arrUserPartIn) do
		self.tReview:AddUser(v.nUserId,v.nSitId,v.sFaceId,v.sName,v.nSex,v.sShopAccount,v.nBalance)
		local nTakeInAdd,nnDex =self.tTableOverview:UserPartIn(v.nUserId,v.sName,v.nLockGoldInTable,v.sFaceId)
		self.tStatistic:SetIsAndroid(v.nUserId,v.isAndroid,nTakeInAdd,v.sFaceId,v.sName)
		self:Print("TestV PairtInUser_%d isAndroid:%s",v.nUserId,tostring(v.isAndroid))
	end
	
	--使用预设置牌模式(预先发好公共牌和各玩家底牌)
	local arrPreSetCommCard ,arrUsersHoleCard =self.tAlg.PreSetCards(#self.arrPosPartIn,self.nHoleCardCnt)
	if self.arrPreSetCommCard ==nil or #self.arrPreSetCommCard ==0 then
		self.arrPreSetCommCard =arrPreSetCommCard
		assert(#arrPreSetCommCard ==5)
	end
	for _,tUser in ipairs(arrUserPartIn) do
		local item =table.remove(arrUsersHoleCard) or {}
		if tUser.arrPreSetHoleCard ==nil or #tUser.arrPreSetHoleCard==0 then
			tUser.arrPreSetHoleCard =item.arrHoleCard
			assert(#tUser.arrPreSetHoleCard ==self.nHoleCardCnt)
			tUser.nRank =item.nRank
		end
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
	if #arrRealUserId ==#arrUserPartIn then		--全是真人时，不控牌
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
	
	--初始化牌堆;给参与牌局的玩家发底牌,并设置其状态为 '等待操作权中'
	self.tPile =self.tAlg.NewPile(self.nGameId==Define.nGameId_Sc)
	self.arrPreSetCommCardEffect =self.arrPreSetCommCard
	self.arrPreSetCommCard ={}
	for _,tUser in ipairs(arrUserPartIn) do
		tUser.arrHoleCards=self.tPile:GetCards(self.nHoleCardCnt,tUser.arrPreSetHoleCard)	
		self:_SetUserStatus(tUser,UserStatus.nWaitForOp)	
		tUser.tCardType =self.tAlg.DeZhouCardType(tUser.arrHoleCards,self.arrCommunityCards)
		tUser.isNeedSettle =true
		if not tUser.isAndroid then
			self.isHaveRealUser =true
		end
		tUser.isShowHoleCard =(self.isDelayLook==false)	--延迟看牌时，游戏开始时暂不公布玩家底牌,直到玩家获得第一次操作权 
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

	--确定大小盲玩家位置
	local nSmallBlindPos,nBigBlindPos=nil,nil
	if #self.arrPosPartIn==2 then
		nSmallBlindPos =self.nBankerPos
		nBigBlindPos =self:_NextGainRightsPos(nSmallBlindPos)
	else
		nSmallBlindPos =self:_NextGainRightsPos(self.nBankerPos)
		nBigBlindPos =self:_NextGainRightsPos(nSmallBlindPos)
	end
	assert(nSmallBlindPos ~=nil and nBigBlindPos~=nil)
	assert(_IsHaveEle(self.arrPosPartIn,nSmallBlindPos))
	assert(_IsHaveEle(self.arrPosPartIn,nBigBlindPos))
	

	--前注下注
	if self.nPreAnte >0 then
		self:Print("Do PreAnte:%.2f",self.nPreAnte)
		for _,nPos in ipairs(self.arrPosPartIn) do
			local nPreAnte =self.nPreAnte
			if self.isDPreAnte and nPos==self.nBankerPos then
				nPreAnte =nPreAnte*2
			end
			local nAcBet,_,tUser =self:_TryDoBet(nPos,nPreAnte)
			tUser.nPreAnte =nAcBet
			self.tReview:PreAnteBet(nPos,nAcBet) --回顾记录
		end
	end

	--大小盲玩家下注
	self:Print("Do SmallAndBigBlind")
	local nAcBetSmall =self:_TryDoBet(nSmallBlindPos,self.nSmallBlind)
	local nAcBetBig =self:_TryDoBet(nBigBlindPos,self.nBigBlind)
	self.tReview:BlindBet(nSmallBlindPos,nAcBetSmall,nBigBlindPos,nAcBetBig) --回顾记录
	
	--强制盲注
	local nForceBlindPos =nil
	local nAcForceBet =0
	if #self.arrPosPartIn>=4 and self.isForceBlind then
		self:Print("Do ForceBlind")
		nForceBlindPos =self:_NextGainRightsPos(nBigBlindPos)
		nAcForceBet =self:_TryDoBet(nForceBlindPos,self.nForceBlind)
		--回顾记录
		self.tReview:ForceBlind(nForceBlindPos,nAcForceBet)
	end
	
	--将筹码为0的玩家设为AllIn状态
	self.nFirstBet =0
	local arrNotAllInUsers={}
	for _,tUser in ipairs(arrUserPartIn) do
		if Equal(tUser.nBalance,0) then
			self:_SetUserStatus(tUser,UserStatus.nAllIn)
		else
			table.insert(arrNotAllInUsers,tUser)
		end
		self.nFirstBet =self.nFirstBet +tUser.nBetSum
	end
	--如果只剩一个玩家没AllIn,且该玩家是下注最高的人，则可以马上发牌结算
	local isShouldEnd=( #arrNotAllInUsers==1 and Equal(arrNotAllInUsers[1].nBet,self.nTheHighestBet))

	--设置桌子游戏状态为 '开始'
	self:_SetGameStage(TableState.nPlaying)
	     
	--初始化玩家"可预操作"选项
	self:_InitUsersPreOpOption()
	--初始化机器人难度
	local isAiHard= self:InitAiGrade()

	--广播游戏开始
	--按发牌顺序排序
	local arrPosPartInSort =self:_SortByDeal(self.arrPosPartIn,nSmallBlindPos) 
	self:_BroadCastGameStartNotify(nSmallBlindPos,nBigBlindPos,arrPosPartInSort,nForceBlindPos,nAcBetSmall,nAcBetBig,nAcForceBet)
	--
	self:_BroadCastMttRank()
	self:MttUsersChipNotify("GameStart")
	--回顾记录
	for _,nPos in ipairs(arrPosPartInSort) do --self.arrPosPartIn
		local tUser =self:_GetUser(nPos)
		assert(tUser ~=nil)
		self.tReview:DealHoleCard(nPos,tUser.arrHoleCards,self:_GetCardType(tUser.tCardType))
	end

	--确定第一获得操作权的玩家,且给予其操作权
	--翻牌前 大盲的下一玩家首先获得操作权. 翻牌后庄家的下一玩家首先获得操作权
	self.nFirstPos =(nForceBlindPos or nBigBlindPos)
	if self.nGameId==Define.nGameId_Sc then
		self.nFirstPos =self.nBankerPos
	end
	local nPosToGainRights =self:_NextGainRightsPos(self.nFirstPos)
	--assert(nPosToGainRights~=nil)				--这里有可能是nil,如果是，就发牌结算  
	local nDelayT=1.2
	if nPosToGainRights==nil or isShouldEnd then
		self:_ToNextRound(nDelayT)
	else
		self.nTheRightsEndPos =nPosToGainRights		
		self.nUserIdLeader =self:_GetUserId(nPosToGainRights)
		self:_ToGiveRightsTo(nDelayT,nPosToGainRights)
	end
	self:Print("StartGame Succee,sPaiJuId:%s,isAiHard:%s",self.sPaiJuId,tostring(isAiHard))
	
	--桌子开始计时
	self:BeginTiming()
	self.nPlayCnt =self.nPlayCnt +1
	self.nLatelyStartTime =os.time()
	self:ClubTableInfoNotify({isStartGame = true })

	--牌局写redis(以便后台实时查看与控牌)
	self:_WriteCurDetailToRedis()

end



function Table:_GetInsurPos()
	local arrPool ={}
	for _,v in ipairs(self.arrPoolInfo) do
		if #v.arrPosForm>1 then
			table.insert(arrPool,{nPool=v.nPool,arrPosForm=_CopyArr(v.arrPosForm)})
		end
	end
	if #arrPool==0 then
		return nil
	end
	--由大到小排序
	local TemSort =function(itemA,itemB)
		return itemA.nPool>itemB.nPool
	end
	table.sort(arrPool,TemSort)
	local tPoolInfo=arrPool[1]						--最大的底池
	local arrValPosCardType ={}						--最大底池中的有效玩家牌型
	local arrValPos={}
	for _,nPos in ipairs(tPoolInfo.arrPosForm) do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.nStatus~=UserStatus.nLooker and tUser.nStatus~=UserStatus.nFold then
			tUser.tCardType.nPos=nPos
			table.insert(arrValPosCardType,tUser.tCardType)
			table.insert(arrValPos,nPos)
		end
	end
	if #arrValPos>3 or #arrValPos<=1 then
		return nil
	end
	local arrTheWinItem =self.tAlg.TheWinCardType(arrValPosCardType)
	if #arrTheWinItem ~= 1 then
		return nil
	end
	local nInsurPos =arrTheWinItem[1].nPos					--可以买保险的玩家位置
	return nInsurPos,arrValPos,tPoolInfo.nPool
end

function Table:PrintPanel(tInsurPanelData)
	local arrRelevantUser ={}
	for _,v in ipairs( tInsurPanelData.arrRelevantUser) do
		local item={}
		item.arrHoleCards =Define.CardsToStr(v.arrHoleCards)
		item.nOuts =v.nOuts
		item.nUserId =v.nUserId
		table.insert(arrRelevantUser,item)
	end

	local tTem =tInsurPanelData.tElseUserHoleCard or {}
	local tElseUserHoleCard ={}
	tElseUserHoleCard.arrOuts =Define.CardsToStr(tTem.arrOuts or {})
	tElseUserHoleCard.arrCard =Define.CardsToStr(tTem.arrCard or {})

	local tRemaining ={}
	tRemaining.arrOuts =Define.CardsToStr(tInsurPanelData.tRemaining.arrOuts)
	tRemaining.nPileCnt =tInsurPanelData.tRemaining.nPileCnt
	tRemaining.nOdds =tInsurPanelData.tRemaining.nOdds

	self:Print("Insur_CommunityCards:%s",Define.CardsToStr(tInsurPanelData.arrCommunityCards))
	self:Print("Insur_RelevantUser:%s",json.encode(arrRelevantUser))
	self:Print("Insur_ElseUserHoleCard:%s",json.encode(tElseUserHoleCard))
	self:Print("Insur_Remaining:%s",json.encode(tRemaining))
	self:Print("Insur_tPool:%s",json.encode(tInsurPanelData.tPool))
	self:Print("Insur_arrInsurancePlan:%s",json.encode(tInsurPanelData.arrInsurancePlan))
	self:Print("Insur_nInsurUserId:%d",tInsurPanelData.nInsurUserId)
	self:Print("Insur_nInsureMode:%d",tInsurPanelData.nInsureMode)
	self:Print("Insur_isMustBuy:%s",tostring(tInsurPanelData.isMustBuy))
	self:Print("Insur_isPossibleEq:%s",tostring(tInsurPanelData.isPossibleEq))
	self:Print("Insur_nInvestInThisPool:%s",tostring(tInsurPanelData.nInvestInThisPool))
	self:Print("Insur_arrOddsList:%s",json.encode(tInsurPanelData.arrOddsList or {}))
end


function Table:GetInsurPanelData(nInsurPos,arrValPos,nMaxPool,isFlopAfter)
	if self.nInsureMode ==InsureMode.nLow then		--低水保险
		return self:GetInsurPanelData_Low(nInsurPos,arrValPos,nMaxPool,isFlopAfter)
	end
	if self.nInsureMode ==InsureMode.nNormal then		--传统保险
		return self:GetInsurPanelData_Normal(nInsurPos,arrValPos,nMaxPool,isFlopAfter)
	end
end

function Table:_GetOutsOdds(nOutsCnt,arrOddsList)
	local arrOddsList =arrOddsList or self.arrOddsList
	local nOutsCnt =math.min(#arrOddsList,nOutsCnt)
	return (self.arrOddsList[nOutsCnt] or 1)
end

function Table:_GetUsersHoleCard(nInsurPos,arrValPos)
	local arrUsersHoleCard ={}
	local nInsurDex =nil
	local nInsurUserId=0
	for n,nPos in ipairs(arrValPos) do
		local tUser =self:_GetUser(nPos)
		table.insert(arrUsersHoleCard,_CopyArr(tUser.arrHoleCards))
		nInsurDex = (nPos==nInsurPos) and n or nInsurDex
		nInsurUserId =(nPos==nInsurPos) and tUser.nUserId or nInsurUserId
	end
	return arrUsersHoleCard,nInsurUserId,nInsurDex
end

function Table:_PlanCostFilter(arrPlanTem,nLastCost)
	if nLastCost <=0 then 
		return arrPlanTem
	end
	local arr ={}
	for _,v in ipairs(arrPlanTem)  do
		if v.nCosts >=nLastCost then
			table.insert(arr,v)
		end
	end
	return arr
end


--保留nCosts处于闭区间[nFloor,nTop]的元素
function Table:_PlanCostFilterV(arrPlanTem,nFloor,nTop)
	local arr ={}
	for _,v in ipairs(arrPlanTem)  do
		if GreaterOrEqual(v.nCosts,nFloor) and LessOrEqual(v.nCosts,nTop) then
			table.insert(arr,v)
		end
	end
	return arr
end


--计算保险面板数据(常规保险)
function Table:GetInsurPanelData_Normal(nInsurPos,arrValPos,nMaxPool,isFlopAfter)
	local arrUsersHoleCard,nInsurUserId,nInsurDex =self:_GetUsersHoleCard(nInsurPos,arrValPos)
	local tDexToOuts,isHaveWinEqual,tDexToWinRate =self.tAlg.CalUsersOutsNormal(arrUsersHoleCard,_CopyArr(self.arrCommunityCards),nInsurDex)

	local arrWinRate={}		--玩家胜率 {{nPos=,nWinRate}...}

	--与保险相关的玩家
	local arrRelevantUser ={}
	local tOuts ={}		--outs去重用
	for dex,nPos in ipairs(arrValPos) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local item={nUserId =tUser.nUserId,sName =tUser.sName,arrHoleCards =_CopyArr(tUser.arrHoleCards)}
		local arrOuts =tDexToOuts[dex] or {}
		item.nOuts =(nPos ==nInsurPos) and -1 or #arrOuts
		table.insert(arrRelevantUser,item)
		for i=1,item.nOuts do
			tOuts[arrOuts[i]]=true
		end
		local tRate={}
		tRate.nPos =nPos
		tRate.nWinRate =publicApi.Floor_2(tDexToWinRate[dex]*100)
		table.insert(arrWinRate,tRate)
	end

	--剩余outs,牌堆剩余多少张牌,赔率(默认outs全选)
	local arrOuts ={}
	for v,_ in pairs(tOuts) do
		table.insert(arrOuts,v)
	end
	if #arrOuts>24 or #arrOuts==0 then	--outs数超24张或为0时不触发保险
		self:Print("outs count is %d",#arrOuts)
		return
	end
	local tRemaining={arrOuts=arrOuts,nPileCnt=self.tPile:GetCnt(),nOdds=self:_GetOutsOdds(#arrOuts)}

	--可投保池,底池,投入
	local tInsurUser =self:_GetUser(nInsurPos)
	assert(tInsurUser~=nil)
	local tPool ={nInsurePool=0,nPool=nMaxPool,nInvest=tInsurUser.nBetSum}
	for _,v in ipairs(self.arrPoolInfo) do
		if _IsHaveEle(v.arrPosForm,nInsurPos) then
			tPool.nInsurePool =(#v.arrPosForm>1) and (tPool.nInsurePool +v.nPool) or tPool.nInsurePool
			tPool.nInvest = (#v.arrPosForm==1) and (tPool.nInvest -v.nPool) or tPool.nInvest
		end
	end

	--投保方案 (nCosts需要根据倍率变化而变化)
	local nLastCost = self:_GetCostOfLastInsur(nInsurUserId)
	local tPlanA ={nPlanId=0,nCosts=publicApi.Floor_2(tPool.nInvest/tRemaining.nOdds)}				--保本
	local tPlanB ={nPlanId=1,nCosts=publicApi.Floor_2(tPool.nInsurePool/tRemaining.nOdds)}			--满池
	local tPlanC ={nPlanId=2,nCosts=publicApi.Floor_2(tPool.nInsurePool/2/tRemaining.nOdds)}		--1/2池
	local tPlanD ={nPlanId=3,nCosts=publicApi.Floor_2(tPool.nInsurePool/3/tRemaining.nOdds)}		--1/3池
	local tPlanE ={nPlanId=5,nCosts=publicApi.Floor_2(tPool.nInsurePool/5/tRemaining.nOdds)}		--1/5池
	local tPlanF ={nPlanId=8,nCosts=publicApi.Floor_2(tPool.nInsurePool/8/tRemaining.nOdds)}		--1/8池
	local arrPlanTem ={tPlanA,tPlanB,tPlanC,tPlanD,tPlanE,tPlanF}
	local arrInsurancePlan =self:_PlanCostFilter(arrPlanTem,(nLastCost/tRemaining.nOdds))			--剔除nCost<(nLastCost/nOdds),也即 "赔付额 <上一次的投保额" 的选项

	local nCostsTop =isFlopAfter and (tPool.nInsurePool/3) or (tPool.nInsurePool/2)
	local tInsurPanelData ={}
	tInsurPanelData.arrRelevantUser=arrRelevantUser								--与保险相关的玩家显示
	tInsurPanelData.arrCommunityCards=_CopyArr(self.arrCommunityCards)			--公共牌
	tInsurPanelData.tElseUserHoleCard=nil										--其他玩家手牌
	tInsurPanelData.tRemaining=tRemaining										--剩余outs,牌堆剩余多少张牌,赔率
	tInsurPanelData.tPool=tPool													--可投保池,底池,投入
	tInsurPanelData.arrInsurancePlan=arrInsurancePlan							--投保方案
	tInsurPanelData.nSeconds =Define.nInsureStageTime							--买保险阶段时间 秒
	tInsurPanelData.nInsurUserId=nInsurUserId									--可以买保险的玩家id
	tInsurPanelData.nInsureMode=InsureMode.nNormal	  							--保险模式 1:传统保险 2:低水保险
	tInsurPanelData.arrOddsList=_CopyArr(self.arrOddsList)						--传统保险赔率表
	tInsurPanelData.isMustBuy=GreaterThan(nLastCost,0)							--是否必须购买保险(true时，保险玩家必须购买所有outs保险,放在函数外判断)
	tInsurPanelData.isPossibleEq=true 											--true时,保险费nCosts不能超过nInvestInThisPool
	tInsurPanelData.nInvestInThisPool=publicApi.Floor_n(nCostsTop,3)			--保险费nCosts的上限值,isPossibleEq为true时有效
	return tInsurPanelData,arrWinRate
end

--计算保险面板数据(低水保险)
function Table:GetInsurPanelData_Low(nInsurPos,arrValPos,nMaxPool,isFlopAfter)
	local arrUsersHoleCard,nInsurUserId =self:_GetUsersHoleCard(nInsurPos,arrValPos)
	local tDexToOuts,tDexToWinRate =self.tAlg.CalUsersOuts(arrUsersHoleCard,_CopyArr(self.arrCommunityCards))
	local tOuts ={}

	local arrWinRate={} --玩家胜率
	--与保险相关的玩家显示
	local arrRelevantUser ={}
	for dex,nPos in ipairs(arrValPos) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		local item={nUserId =tUser.nUserId,sName =tUser.sName,arrHoleCards =_CopyArr(tUser.arrHoleCards)}
		local arrOuts =tDexToOuts[dex] or {}
		item.nOuts =(nPos ==nInsurPos) and -1 or #arrOuts
		table.insert(arrRelevantUser,item)
		for i=1,item.nOuts do
			tOuts[arrOuts[i]]=true
		end

		local tRate={}
		tRate.nPos =nPos
		tRate.nWinRate =publicApi.Floor_2(tDexToWinRate[dex]*100)
		table.insert(arrWinRate,tRate)
	end
	
	--其他玩家手牌
	local tElseUserHoleCard ={arrOuts={},arrCard={}}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		if (not _IsHaveEle(arrValPos,nPos)) and tUser.nStatus~=UserStatus.nFold then
			for _,v in ipairs(tUser.arrHoleCards) do
				if tOuts[v] then
					table.insert(tElseUserHoleCard.arrOuts,v)
					tOuts[v]=nil
				else
					table.insert(tElseUserHoleCard.arrCard,v)
				end
			end
		end
	end

	--剩余outs,牌堆剩余多少张牌,赔率
	local arrOuts ={}
	for v,_ in pairs(tOuts) do
		table.insert(arrOuts,v)
	end
	if #arrOuts==0 then							--outs数为0时不触发保险
		self:Print("outs count is 0")
		return
	end
	local nPileCnt=self.tPile:GetCnt()
	local nOdds =((nPileCnt/#arrOuts)*0.95)-1	--按公式计算赔率
	nOdds =publicApi.Floor_n(nOdds,1)			--保留一位小数
	if nOdds<0.1 then
		self:Print("nOdds is too small")
		return 
	end
	local tRemaining={arrOuts=arrOuts,nPileCnt=nPileCnt,nOdds=nOdds}
	
	--可投保池,底池,投入
	local tInsurUser =self:_GetUser(nInsurPos)
	assert(tInsurUser~=nil)
	local tPool ={nInsurePool=0,nPool=nMaxPool,nInvest=tInsurUser.nBetSum}
	for _,v in ipairs(self.arrPoolInfo) do
		if _IsHaveEle(v.arrPosForm,nInsurPos) then
			tPool.nInsurePool =(#v.arrPosForm>1) and (tPool.nInsurePool +v.nPool) or tPool.nInsurePool
			tPool.nInvest = (#v.arrPosForm==1) and (tPool.nInvest -v.nPool) or tPool.nInvest
		end
	end

	--投保方案 (nCosts需要根据倍率变化而变化)
	local nCostsTop =isFlopAfter and (tPool.nInsurePool/3) or (tPool.nInsurePool/2)					--转牌阶段:保险费不能超1/3底池,河牌阶段不能超1/2底池
	local nLastCost = self:_GetCostOfLastInsur(nInsurUserId)
	local tPlanA ={nPlanId=0,nCosts=publicApi.Floor_2(tPool.nInvest/tRemaining.nOdds)}				--保本
	local tPlanB ={nPlanId=1,nCosts=publicApi.Floor_2(tPool.nInsurePool/tRemaining.nOdds)}			--满池
	local tPlanC ={nPlanId=2,nCosts=publicApi.Floor_2(tPool.nInsurePool/2/tRemaining.nOdds)}		--1/2池
	local tPlanD ={nPlanId=3,nCosts=publicApi.Floor_2(tPool.nInsurePool/3/tRemaining.nOdds)}		--1/3池
	local tPlanE ={nPlanId=5,nCosts=publicApi.Floor_2(tPool.nInsurePool/5/tRemaining.nOdds)}		--1/5池
	local tPlanF ={nPlanId=8,nCosts=publicApi.Floor_2(tPool.nInsurePool/8/tRemaining.nOdds)}		--1/8池
	local arrPlanTem ={tPlanA,tPlanB,tPlanC,tPlanD,tPlanE,tPlanF}
	arrPlanTem =self:_PlanCostFilterV(arrPlanTem,0,nCostsTop)
	local arrInsurancePlan =self:_PlanCostFilter(arrPlanTem,(nLastCost/tRemaining.nOdds))			--剔除nCost<(nLastCost/nOdds),也即 "赔付额 <上一次的投保额" 的选项

	local tInsurPanelData ={}
	tInsurPanelData.arrRelevantUser=arrRelevantUser								--与保险相关的玩家显示
	tInsurPanelData.arrCommunityCards=_CopyArr(self.arrCommunityCards)			--公共牌
	tInsurPanelData.tElseUserHoleCard=tElseUserHoleCard							--其他玩家手牌
	tInsurPanelData.tRemaining=tRemaining										--剩余outs,牌堆剩余多少张牌,赔率
	tInsurPanelData.tPool=tPool													--可投保池,底池,投入
	tInsurPanelData.arrInsurancePlan=arrInsurancePlan							--投保方案
	tInsurPanelData.nSeconds =Define.nInsureStageTime							--买保险阶段时间 秒
	tInsurPanelData.nInsurUserId=nInsurUserId									--可以买保险的玩家id
	tInsurPanelData.nInsureMode=InsureMode.nLow	  								--保险模式 1:传统保险 2:低水保险
	tInsurPanelData.arrOddsList={}												--赔率表(传统保险才有效);值1为补牌1赔率、值2为补牌2赔率...
	tInsurPanelData.isMustBuy=GreaterThan(nLastCost,0)							--是否必须购买保险(true时，保险玩家必须购买所有outs保险)
	tInsurPanelData.isPossibleEq=false 											--true时,保险费nCosts不能超过nInvestInThisPool(低水保险不使用该字段)
	tInsurPanelData.nInvestInThisPool=0											--保险费nCosts的上限值,isPossibleEq为true时有效(低水保险不使用该字段)
	return tInsurPanelData,arrWinRate
end


--尝试进入买保险阶段 返回:true(进入成功), false(进入失败)
function Table:TryTriggerInsur()
	if self.nInsureMode ==0 then
		return false
	end
	if #self.arrCommunityCards==0 then
		return false
	end
	if #self.arrCommunityCards==3 then
		return self:TryGoInInsurOfFlopAfter()	-- 尝试进入翻牌后买保险阶段
	elseif #self.arrCommunityCards==4 then
		return self:TryGoInInsurOfTurnAfter()	-- 尝试进入转牌后买保险阶段
	end
	return false
end

function Table:_GetInsurProtoShowCard()
	local arrHoleCard ={}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		if tUser.nStatus~=UserStatus.nFold then
			local item ={}
			item.nPos=nPos										--座位号
			item.arrHoleCards=_CopyArr(tUser.arrHoleCards)		--底牌(2张)
			item.nCardType=self:_GetCardType(tUser.tCardType)	--牌型
			table.insert(arrHoleCard,item)
		end
	end
	return {arrHoleCard=arrHoleCard}
end
function Table:_GetInsurProtoPoolChange()
	return {arrPot =self:_GetProtoArrPot()}
end
function Table:_GetInsurProtoUsersCardType()
	local arrUsersCardType ={}
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		if tUser.nStatus~=UserStatus.nFold then
			local item ={}
			item.nPos=nPos										--座位号
			item.nCardType=self:_GetCardType(tUser.tCardType)	--牌型
			local tCardType =tUser.tCardType or {}
			item.arrCombinedCards =tCardType.arrFiveBack or {}
			table.insert(arrUsersCardType,item)
		end
	end
	return arrUsersCardType
end

function Table:_InsurSettleFlopAfter(nUserId)
	if not self.tFlopAfterInsur then
		return 0
	end
	local tInsurPanelData =self.tFlopAfterInsur.tPanelData
	if tInsurPanelData.nInsurUserId ~=nUserId then
		return 0
	end
	local nCosts =self.tFlopAfterInsur.nChooseCost or 0
	local arrOutsAfterCheck =self.tFlopAfterInsur.arrOutsAfterCheck or {}
	local nOdds =self.tFlopAfterInsur.nOdds or 0
	if LessOrEqual(nCosts,0) then
		return 0
	end
	local isHit =_IsHaveEle(arrOutsAfterCheck,self.arrCommunityCards[4]) --是否中保险
	if isHit then
		return publicApi.Floor_1(nCosts*nOdds)
	else
		return -nCosts
	end
end

function Table:_InsurSettleTurnAfter(nUserId)
	if not self.tTurnAfterInsur then
		return 0
	end
	local tInsurPanelData =self.tTurnAfterInsur.tPanelData
	if tInsurPanelData.nInsurUserId ~=nUserId then
		return 0
	end
	local nCosts =self.tTurnAfterInsur.nChooseCost or 0
	local arrOutsAfterCheck =self.tTurnAfterInsur.arrOutsAfterCheck or {}
	local nOdds =self.tTurnAfterInsur.nOdds or 0
	if LessOrEqual(nCosts,0) then
		return 0
	end
	local isHit =_IsHaveEle(arrOutsAfterCheck,self.arrCommunityCards[5])	--是否中保险
	if isHit then
		return publicApi.Floor_1(nCosts*nOdds)
	else
		return -nCosts
	end
end

function Table:InsurSettle(nUserId)
	local nInsurA =self:_InsurSettleFlopAfter(nUserId)		--第一次保险结算
	local nInsurB =self:_InsurSettleTurnAfter(nUserId)		--第二次保险结算
	if not Equal(nInsurA,0) or not Equal(nInsurB,0) then
		self:Print("InsurSettle nUserId_%d, %.2f,%.2f",nUserId,nInsurA,nInsurB)
	end
	return publicApi.Floor_1(nInsurA +nInsurB)
end


function Table:_GetInsureCost(tInsurPanelData,nPlanId,nOutsCnt)	
	local tPlan =nil
	for _,v in ipairs(tInsurPanelData.arrInsurancePlan) do
		if v.nPlanId ==nPlanId then
			tPlan =v
			break
		end
	end
	if tPlan ==nil then
		return nil,-11,0
	end
	--低水保险	
	if tInsurPanelData.nInsureMode ==InsureMode.nLow then
		return tPlan.nCosts,0,tInsurPanelData.tRemaining.nOdds
	end
	--常规保险
	assert(tInsurPanelData.nInsureMode ==InsureMode.nNormal)
	local nNowOdds =self:_GetOutsOdds(nOutsCnt,tInsurPanelData.arrOddsList)
    local nCosts = (tInsurPanelData.tRemaining.nOdds/nNowOdds) *tPlan.nCosts
	nCosts =publicApi.Floor_2(nCosts)

	--如果存在平分可能,花费不能超过在该池的投入(针对常规保险;低水保险时isPossibleEq恒为false)
	if tInsurPanelData.isPossibleEq and GreaterThan(nCosts,tInsurPanelData.nInvestInThisPool) then
		self:Print("isPossibleEq is true and nChooseCost is Wrong")
		return nil,-10,0
	end
	return nCosts,0,nNowOdds
end

function Table:_CheckInsureOuts(tInsurPanelData,arrOuts)
	if tInsurPanelData.nInsureMode ==InsureMode.nLow then
		return tInsurPanelData.tRemaining.arrOuts
	end
	--常规保险
	assert(tInsurPanelData.nInsureMode ==InsureMode.nNormal)
	if tInsurPanelData.isMustBuy then					--必须购买全部outs
		return tInsurPanelData.tRemaining.arrOuts
	end
	local tTem ={}
	for _,v in ipairs(tInsurPanelData.tRemaining.arrOuts) do
		tTem[v]=true
	end
	for _,v in ipairs(arrOuts) do
		if not tTem[v] then
			return nil
		end
	end
	return arrOuts
end

--保险购买
function Table:InsurBuyReq(tJsonData,sReturnKey)
	local nUserId =tJsonData.nUserId
	local nPlanId =tJsonData.nPlanId
	local arrOuts =tJsonData.arrOuts or {}
	self:Print("InsurBuyReq,nUserId:%d,nPlanId:%d",nUserId,nPlanId)
	self:Print("arrOuts:%s",Define.CardsToStr(arrOuts))
	
	local tInsurInfo =nil
	if #self.arrCommunityCards==3 then
		tInsurInfo =self.tFlopAfterInsur
	elseif #self.arrCommunityCards==4 then
		tInsurInfo =self.tTurnAfterInsur
	end
	if tInsurInfo==nil or (not tInsurInfo.isInStage) then	--当前是否为保险阶段检查
		self:Print("No Insur")
		return 
	end
	local tInsurPanelData =tInsurInfo.tPanelData
	
	if nUserId ~=tInsurPanelData.nInsurUserId then			--用户购买权限检查
		self:Print("No Rights")
		return
	end
	if tInsurInfo.nChooseCost then							--已经购买过了，不能重复购买
		self:Print("Repeat Buy")
		return
	end
	if tInsurPanelData.isMustBuy and nPlanId== -1 then		 --必须购买一个保险,不能取消 (-1表示不买保险)
		self:Print("Can Not GiveUp")
		self:_SendToSlave(sReturnKey,"InsurBuyRsp",{nCode=-1,nUserId=nUserId,nPlanId=nPlanId})
		return
	end

	--辅助函数(回复成功,并结束保险阶段)
	local function _SucceeAndEnd()
		self:_SendToSlave(sReturnKey,"InsurBuyRsp",{nCode=0,nUserId=nUserId,nPlanId=nPlanId}) 
		if #self.arrCommunityCards==3 then
			self:ToEndInsurOfFlopAfter(0.5)
		elseif #self.arrCommunityCards==4 then
			self:ToEndInsurOfTurnAfter(0.5)
		end
	end

	--玩家取消购买保险(-1表示不买保险)
	if nPlanId == -1 or (tInsurPanelData.nInsureMode ==InsureMode.nNormal and #arrOuts==0) then		
		self:Print("Insure Cancel succee")
		tInsurInfo.nOdds =0								--倍率
		tInsurInfo.arrOutsAfterCheck ={}				
		tInsurInfo.nChooseCost =0
		_SucceeAndEnd()
		return
	end
	
	--检查所选outs是否合法
	local arrOutsAfterCheck =self:_CheckInsureOuts(tInsurPanelData,arrOuts)
	if arrOutsAfterCheck ==nil then
		self:Print("Outs Wrong")
		self:_SendToSlave(sReturnKey,"InsurBuyRsp",{nCode=-2,nUserId=nUserId,nPlanId=nPlanId})
		return
	end
	self:Print("arrOutsAfterCheck:%s",Define.CardsToStr(arrOutsAfterCheck))

	--计算购买该保险方案的花费
	local nChooseCost,nErrCode,nOdds =self:_GetInsureCost(tInsurPanelData,nPlanId,#arrOutsAfterCheck)
	if nChooseCost==nil then						--购买方案合法检查
		nErrCode =nErrCode or -3
		self:Print("PlanId Wrong,nErrCode:%d",nErrCode)
		self:_SendToSlave(sReturnKey,"InsurBuyRsp",{nCode=nErrCode,nUserId=nUserId,nPlanId=nPlanId})
		return
	end
	self:Print("Insure succee,nChooseCost:%.2f,nOdds:%.2f",nChooseCost,nOdds)

	--记下玩家的选择
	tInsurInfo.nOdds =nOdds								--倍率
	tInsurInfo.arrOutsAfterCheck =arrOutsAfterCheck
	tInsurInfo.nChooseCost =nChooseCost	    			--记录玩家购买保险的花费 (0或nil表示不买保险,其中nil表示超时不买)
	_SucceeAndEnd()
end

--如果玩家必须购买保险但又没买，则自动帮其购买
function Table:_AutoChooseIfNeccessary(tInsurInfo)
	if tInsurInfo.nChooseCost then
		return
	end
	local tInsurPanelData =tInsurInfo.tPanelData
	if not tInsurPanelData.isMustBuy then
		return
	end
	tInsurInfo.nOdds =tInsurPanelData.tRemaining.nOdds								
	tInsurInfo.arrOutsAfterCheck =tInsurPanelData.tRemaining.arrOuts
	tInsurInfo.nChooseCost =self:_GetCostOfLastInsur(tInsurPanelData.nInsurUserId)
	assert( GreaterThan(tInsurInfo.nChooseCost,0) )
	--低水保险
	if tInsurPanelData.nInsureMode ==InsureMode.nLow then
		self:Print("Insure AutoChoose,nChooseCost:%.2f,nOdds:%.2f",tInsurInfo.nChooseCost,tInsurInfo.nOdds)
		return	    			
	end
	--常规保险
	assert(tInsurPanelData.nInsureMode ==InsureMode.nNormal)
	local nCost =nil
	for _,tPlan in ipairs(tInsurPanelData.arrInsurancePlan) do
		if GreaterOrEqual(tPlan.nCosts*tInsurInfo.nOdds,tInsurInfo.nChooseCost) then
			nCost =nCost or tPlan.nCosts
			nCost =math.min(nCost,tPlan.nCosts)
		end
	end
	assert(nCost ~=nil)
	tInsurInfo.nChooseCost =nCost
	self:Print("Insure AutoChoose,nChooseCost:%.2f,nOdds:%.2f",tInsurInfo.nChooseCost,tInsurInfo.nOdds)
end


--尝试进入买保险阶段(翻牌后的)
function Table:TryGoInInsurOfFlopAfter()
	local nInsurPos,arrValPos,nMaxPool= self:_GetInsurPos()
	if not nInsurPos then
		self:Print("GoIn Insur Of FlopAfter Fail,no InsurPos")
		return false
	end
	local tPanelData,arrWinRate =self:GetInsurPanelData(nInsurPos,arrValPos,nMaxPool,true)
	if not tPanelData then
		self:Print("GoIn Insur Of FlopAfter Fail,tPanelData is nil")
		return false
	end
	
	self:Print("GoIn Insur Of FlopAfter succee")
	self:Print("arrWinRate:%s",cjson.encode(arrWinRate))

	self:PrintPanel(tPanelData)
	self.tFlopAfterInsur ={tPanelData=tPanelData,isInStage=true}
	
	--广播 亮牌 底池变化 弹保险
	local tShowCard=self:_GetInsurProtoShowCard()
	local tPoolChange =self:_GetInsurProtoPoolChange()
	self:_BroadCastInsur(tPanelData,tShowCard,tPoolChange,arrWinRate)

	--一段时间后,结束本保险阶段且发转牌
	self:ToEndInsurOfFlopAfter(tPanelData.nSeconds)
	return true
end

function Table:_BroadCastInsur(tInsurPanelData,tShowCard,tPoolChange,arrWinRate)
	local InsurNotify ={}
	InsurNotify.tShowCard=tShowCard
	InsurNotify.tPoolChange =tPoolChange
	InsurNotify.tInsurPanelData=tInsurPanelData
	InsurNotify.arrUser =self:_GetPartInUserStatus()
	InsurNotify.arrWinRate=arrWinRate
	self:_BroadCastToSlaves("InsurNotify",InsurNotify)
	--主要是广播给机器人
	for nPos,tUser in pairs(self.arrUsers) do
		self:SendToUser(nPos,"InsurNotify",InsurNotify)
	end
end
function Table:_BroadCastInsurDeal(nCard,tChoice)
	local InsurDealNotify ={}
	InsurDealNotify.nCard =nCard
	InsurDealNotify.arrUsersCardType =self:_GetInsurProtoUsersCardType()
	InsurDealNotify.tChoice =tChoice

	self:_BroadCastToSlaves("InsurDealNotify",InsurDealNotify)
	--主要是广播给机器人
	for nPos,tUser in pairs(self.arrUsers) do
		self:SendToUser(nPos,"InsurDealNotify",InsurDealNotify)
	end
end

--保险阶段结束(翻牌后的)
function Table:EndInsurOfFlopAfter()
	assert(self.tFlopAfterInsur ~=nil)
	self.tFlopAfterInsur.isInStage=false
	--发转牌
	self:Print("Insur End,Deal Turn")
	assert(#self.arrCommunityCards==3)
	local arrCardsNewAdd,arrCardType =self:_DealCommunityCards(1)
	self.tReview:DealCard(arrCardsNewAdd,arrCardType,self:_GetProtoArrPot(),true)  --回顾记录
	--广播 发转牌(和所有玩家的牌型)
	assert(#arrCardsNewAdd==1)

	local tInsur =self.tFlopAfterInsur  --self.tTurnAfterInsur
	local nSitId,_=self:_GetSitIdByUserId(tInsur.tPanelData.nInsurUserId)
	local tChoice=nil
	if nSitId then
		tChoice={}
		tChoice.nPos=nSitId												--投保玩家座位号
		tChoice.nChoice=tInsur.nChooseCost or 0			-->0:投保xx ,其它:不投保
	end
	self:_BroadCastInsurDeal(arrCardsNewAdd[1],tChoice)
	self:_TryBroadCastWinRate()
	--延迟一个动画时间
	self:ToEndDealOfTurnCard(1.5)
end

--发转牌动画播放结束
function Table:EndDealOfTurnCard()
	self:Print("To Next Insur or Deal River")
	--尝试进入转牌后保险阶段
	if self:TryGoInInsurOfTurnAfter() then
		return
	end
	--进发河牌阶段
	self:GoInDealOfRiver()
end

--进发河牌阶段
function Table:GoInDealOfRiver()
	--发河牌
	self:Print("Deal River")
	assert(#self.arrCommunityCards==4)
	local arrCardsNewAdd,arrCardType =self:_DealCommunityCards(1)

	local isShowCard =false
	if not self.tFlopAfterInsur then
		isShowCard =true
	end
	self.tReview:DealCard(arrCardsNewAdd,arrCardType,self:_GetProtoArrPot(),isShowCard)  --回顾记录

	local tChoice=nil
	local tInsur =self.tTurnAfterInsur   -- self.tFlopAfterInsur
	if tInsur   then
		local nSitId,_=self:_GetSitIdByUserId(tInsur.tPanelData.nInsurUserId)
		if nSitId then
			tChoice={}
			tChoice.nPos=nSitId								--投保玩家座位号
			tChoice.nChoice=tInsur.nChooseCost or 0			-->0:投保xx ,其它:不投保
		end
	end

	--广播 发河牌(和所有玩家的牌型)
	assert(#arrCardsNewAdd==1)
	self:_BroadCastInsurDeal(arrCardsNewAdd[1],tChoice)
	self:_TryBroadCastWinRate()
	self:_ToSettle(1.5)
end


--上一次买保险的花费 (也即翻牌后买保险的花费)
function Table:_GetCostOfLastInsur(nInsurUserId)
	if self.tFlopAfterInsur and self.tFlopAfterInsur.tPanelData.nInsurUserId ==nInsurUserId then
		return self.tFlopAfterInsur.nChooseCost or 0
	end
	return 0
end


--尝试进入转牌后买保险阶段
function Table:TryGoInInsurOfTurnAfter()
	local nInsurPos,arrValPos,nMaxPool= self:_GetInsurPos()
	if not nInsurPos then
		self:Print("GoIn Insur Of TurnAfter Fail,no InsurPos")
		return false
	end
	local tPanelData,arrWinRate =self:GetInsurPanelData(nInsurPos,arrValPos,nMaxPool,false)
	if not tPanelData then
		self:Print("GoIn Insur Of TurnAfter Fail,tPanelData is nil")
		return false
	end
	
	self:Print("GoIn InsurOf TurnAfter succee")
	self:Print("arrWinRate:%s",cjson.encode(arrWinRate))
	
	self:PrintPanel(tPanelData)
	self.tTurnAfterInsur ={tPanelData=tPanelData,isInStage=true}
	
	--广播 [亮牌] [底池变化] 弹保险
	local tShowCard,tPoolChange =nil,nil
	if not self.tFlopAfterInsur then
	 	tShowCard=self:_GetInsurProtoShowCard()
	 	tPoolChange =self:_GetInsurProtoPoolChange()
	end
	self:_BroadCastInsur(tPanelData,tShowCard,tPoolChange,arrWinRate)

	--一段时间后,结束本保险阶段且发转牌
	self:ToEndInsurOfTurnAfter(tPanelData.nSeconds)
	return true
end

--保险阶段结束(转牌后的)
function Table:EndInsurOfTurnAfter()
	--如果玩家必须购买保险但又没买，则自动帮其购买
	self:_AutoChooseIfNeccessary(self.tTurnAfterInsur)

	self.tTurnAfterInsur.isInStage= false
	--进发河牌阶段
	self:GoInDealOfRiver()
end


function Table:ToEndInsurOfTurnAfter(nSeconds)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.EndInsurOfTurnAfter,self)
	self:_UpdateHeartTick()
end

function Table:ToEndDealOfTurnCard(nSeconds)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.EndDealOfTurnCard,self)
	self:_UpdateHeartTick()
end

function Table:ToEndInsurOfFlopAfter(nSeconds)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds*1000,Table.EndInsurOfFlopAfter,self)
	self:_UpdateHeartTick()
end



function Table:_DealCardCnt()
	local nCommunityCardsCnt =#self.arrCommunityCards
	if nCommunityCardsCnt ==0 then
		return 3
	end
	if nCommunityCardsCnt==5 then
		return 0
	end
	return 1
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
	local nDealCardCnt =self:_DealCardCnt()	--需要发牌的数量,0时表示不用再发

	--公共牌已够5个,或缺乏玩家竞争底池
	if nDealCardCnt ==0 or #self.arrPosPartIn==0 or nUserCountOfNotFold<=1 then		
		self:_ToSettle(0.2)
		return
	end
	
	--发牌动画时间 秒
	local function dealAnimTime(nCnt)
		if nCnt==1 then return 0.8 end
		if nCnt==3 then return 2.2 end
		return 0.25+nCnt*0.5
	end

	--如果少于两个玩家可以获得操作权，亮牌后,直接发够5个公共牌，然后进行结算
	local nPosToGainRights =self:_NextGainRightsPos(self.nBankerPos)
	if nPosToGainRights==nil or self:_NextGainRightsPos(nPosToGainRights)==nil then
		if self:TryTriggerInsur() then
			return
		end
		local arrCardsNewAdd,arrCardType =self:_DealCommunityCards(nDealCardCnt)
		self.tReview:DealCard(arrCardsNewAdd,arrCardType,self:_GetProtoArrPot(),true)  --回顾记录
		self:_BroadCastDeZhouDealNotify(arrCardsNewAdd,true)		   --广播	
		self:_TryBroadCastWinRate()
		self:_ToNextRound(dealAnimTime(#arrCardsNewAdd))			   --进入下一轮(因已发够5牌，下一轮会直接进入结算)
		return
	end

	--初始化玩家可预操作选项
	self:_InitUsersPreOpOption()
	--发牌,第一次发时发3个，后续发1个
	assert(nDealCardCnt>0)
	local arrCardsNewAdd,arrCardType =self:_DealCommunityCards(nDealCardCnt)
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

--尝试计算并广播胜率
function Table:_TryBroadCastWinRate()
	local nLen =#self.arrCommunityCards
	if nLen==0 then
		return
	end
	local arrUsersHoleCard={}
	local arrPos={}
	for _,nPos in ipairs(self.arrPosPartIn) do 
		local tUser =self:_GetUser(nPos)
		assert(tUser ~=nil)
		if tUser.nStatus ~=UserStatus.nFold then
			table.insert(arrUsersHoleCard,_CopyArr(tUser.arrHoleCards))
			table.insert(arrPos,nPos)
		end
	end
	local tDexToWinRate =self.tAlg.WinRateReal(arrUsersHoleCard,_CopyArr(self.arrCommunityCards))
	local arrWinRate={}
	for dex,nPos in ipairs(arrPos) do
		local item={}
		item.nPos=nPos
		item.nWinRate =publicApi.Floor_2( (tDexToWinRate[dex] or 0)*100)
		table.insert(arrWinRate,item)
	end
	self:_BroadCastToSlaves("WinRateNotify",{arrWinRate=arrWinRate})
	self:Print("BroadCastWinRate,%s",tBase.tostring(arrWinRate))
end


function Table:_GetFeeOfCardOpen()
	if self:MatchRoomId()==0 then
		return 0
	end
	local nLen =#self.arrCommunityCards
	if nLen==0 then
		return self.nFeeA			--翻牌费用
	elseif nLen==3 then
		return self.nFeeB			--转牌费用
	elseif nLen==4 then
		return self.nFeeC   		--河牌费用
	end
	return 0
end

--是否需要弹窗提示玩家补充筹码
function Table:_IsShouldPop(tUser)
	return false
	--return (Equal(tUser.nBalance,0) and tUser.nBuyTo==0) 
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
	
	--付费看的牌
	local nDealCnt =self:_DealCardCnt()
	self.arrCardsOpenForPay ={}
	self.nCardOpenFee =-1			--看牌费用
	if nDealCnt>0 then
		self.arrCardsOpenForPay =self.tPile:GetCards(nDealCnt,self.arrPreSetCommCardEffect)
		self.nCardOpenFee =self:_GetFeeOfCardOpen()
	end
	self:Print("arrCardsOpenForPay:%s nCardOpenFee:%.2f",Define.CardsToStr(self.arrCardsOpenForPay),self.nCardOpenFee)

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
		if tUser.isAndroid and tUser.nStatus ==UserStatus.nFold and math.random(1,100)<0 then 
			tUser.isShowCardWhenEnd =true
		end
		if tUser.isAndroid then					--for test
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
		item.isPop =self:_IsShouldPop(tUser) --是否需要弹窗提示玩家补充筹码
		table.insert(arrUserForSlave,item)
 	end
	self:WriteRecords()
	self:UpdateCacheOfTax()		-- 注意该操作须在WriteRecords()之后
	self.tReview:Settle(self:_GetProtoArrPot(),arrUsersWin)		--回顾记录
	local nPool =self:_GetValPoolSum()
	self.tStatistic:DoPersist(self.sTableId,self.nGameId,self.nClubIdOfCorrect,nPool,self.nInsurPool,self.nGoldType,self.nKeepTime,self.sTableName,self.nGroupId)

	if nTheOnlyNotFoldPos then
		self.tWinUserInfo.nCardType =0
	end

	--广播
	local DeZhouSettleNotify ={}
	DeZhouSettleNotify.arrUsersWin=arrUsersWin								--所有玩家牌型与输赢情况(弃牌玩家除外)
	DeZhouSettleNotify.arrPot =self:_GetProtoArrPot()
	DeZhouSettleNotify.nStage =self.nStage
	DeZhouSettleNotify.arrUserForSlave=arrUserForSlave
	DeZhouSettleNotify.nCardOpenFee =self.nCardOpenFee
	self:_BroadCastSettleNotify(DeZhouSettleNotify)
	
	self:_ToSettleEnd()
end


--isAutoNext
function Table:ResetIsAutoNext()
	if (self.nPlayerCntAtLeast and self.nPlayerCntAtLeast>=2) or self.nRoomType==RoomType.nLobby then
		self.isAutoNext =true
	else
		self.isAutoNext =false
	end
end

function Table:SettleEnd()
	self:Print("SettleEnd nUserCnt:%d",self.nUserCnt)
	self:_SetAndroidLeaveWhenEnd(self.nDecrAndroidCnt)	--确保有nDecrAndroidCnt个机器人会离开

	tPublicRedis._UpdateCurPaiJu(self.sTableId)
	self.tTableOverview:PaiJuEnd()
	self:ResetIsAutoNext()

	if self.isHaveRealUser then
		self:WriteDetail()
	end
	self:_SetGameStage(TableState.nInit)

	--广播桌子重置
	self:_BroadCastTableResetNotify()

	--清理离线与连续两局没操作的玩家
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		if tUser then
			if tUser.isHaveOp or tUser.isRetain then
				tUser.nConsecutiveNoOp =0
			elseif tUser.nGetChanceCnt>0 then
				tUser.nConsecutiveNoOp =tUser.nConsecutiveNoOp +1
			end
			if tUser.nOffLineCnt~=0 and tUser.isBackToLobby then  --返回大厅,不保留座位
				self:Oust(nPos,nil,"OffLineAndBackToLobby")
			elseif tUser.nConsecutiveNoOp >=100 then			--比赛允许无限局托管,不踢
				self:Oust(nPos,nil,"No_Op")
			elseif tUser.nStanpUpReason then
				self:Oust(nPos,tUser.nStanpUpReason,"BeKick")
			end
		end
	end
	
	--给筹码为0的参赛玩家，限时补充筹码
	--当有玩家限时补充筹码时,不触发换桌
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		if tUser and  Equal(tUser.nBalance +tUser.nBuyTo,0) then
			self:_TryGiveChanceBuyChip(tUser.nUserId)
		end
	end
	--报告给比赛服玩家当前筹码
	self:MttUsersChipNotify("GameSettle")

	--尝试拆桌
	self:TrySplit(false)
	--更新比赛排名和平均筹码等信息
	self.tInterFace.UpdateMttUsersRank(self.nEventId)
	
	--重置
	self:_ResetTable()
	self:_ResetUsers()
	
	--关闭桌子还是继续下一局
	local nCloseReason =self:_IsCloseWhenOver()
	if nCloseReason then
		self:CloseTable(nCloseReason)
		return
	end
	--让留座但还没开始计时的玩家，开始计时
	for _,tUser in pairs(self.arrUsers) do
		if tUser.isRetain then
			self:_RetainCountDown(tUser)
		end
	end
	if not self.isPause then
		self:_TryToStartGame()
	else
		self:_Pause()
	end
end

function Table:TrySplit(isCallFromTimer)
	if self.nStage ~=TableState.nInit then
		return
	end
	if self.isToStartGame then
		return
	end
	if self.TimerForForceUp:GetRunTimerCnt()>0 then	--有玩家限时补充筹码中
		return
	end
	if not self.isMatchStart then	--比赛未开始
		return
	end

	if isCallFromTimer then
		if self.nLatelyStageTimeSt ==os.time() then
			return
		end
	end
	local arrUserId={}
	for _,tUser in pairs(self.arrUsers) do
		table.insert(arrUserId,tUser.nUserId)
	end
	if #arrUserId==0 then
		return
	end
	local nUserCntAll =self.tInterFace.MttSplitUsers(self.nEventId,self,arrUserId)
	if nUserCntAll ==1 and self.isMatchStart then
		assert(#arrUserId==1)
		local nChampionUserId =arrUserId[1]	--冠军
		local nPos =self:_GetSitIdByUserId(nChampionUserId)
		assert(nPos~=nil)
		self:Oust(nPos,nil,"Champion")
	end
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
			tPublicRedis._UpdateCurPaiJu(self.sTableId,cjson.encode(self.tCurRedisDetail))
			return true
		end
		for _,v in ipairs ( self.tCurRedisDetail.arrUsersInfo) do
			if _ChangeOnly(v.arrHoleCards) then
				tPublicRedis._UpdateCurPaiJu(self.sTableId,cjson.encode(self.tCurRedisDetail))
				return true
			end
		end
		return false
	end
	if _Change(self.arrPreSetCommCardEffect) then
		_UpdateCopy()
		self:_UpdateRank()
		self:Print("change PreSetCommCard")
		return true,"succee"
	end
	for _,nPos in ipairs(self.arrPosPartIn) do
		local tUser =self:_GetUser(nPos)
		assert(tUser~=nil)
		if  _Change(tUser.arrHoleCards) then
			tUser.tCardType =self.tAlg.DeZhouCardType(tUser.arrHoleCards,self.arrCommunityCards)
			_UpdateCopy()
			self:_UpdateRank()
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
		local tCardType =self.tAlg.DeZhouCardType(tUser.arrHoleCards,self.tCurRedisDetail.arrCommunityCard)
		local item ={}
		item.nCardType =tCardType.nCardType
		item.nComValue =tCardType.nComValue
		item.tUser =tUser
		table.insert(arr,item)
	end
	self.tAlg.SortByCardType(arr)

	for dex,v in ipairs(arr) do
		v.tUser.nRank =dex
	end
end

--后台踢人 tJsonData,sReturnKey
function Table:REQ_Kick_User(tData,sReturnKey)
	local nUserId =tData.nUserId

	local nSitId,tUser =self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("REQ_Kick_User,can not find user_%d",nUserId)
		self:_KickToLobby(nil,nUserId)
		return
	end
	local nType = tData.nType or -1    		--1:立即踢出牌桌(令玩家返回大厅) 2:当局结束后踢出牌桌(令玩家返回大厅) 3:当局结束后强制站起
	self:Print("REQ_Kick_User nSitId:%d nUserId:%d nType:%d",nSitId,nUserId,nType)

	if nType==1  then							
		self:_KickToLobby(nSitId,nUserId)
		return
	end
	if nType==2 then							
		if self:_IsPartInUser(nSitId) then
			self.tUsersKickToLobbyWhenOver[nUserId]=true
		else
			self:_KickToLobby(nSitId,nUserId)
		end
	end
	if nType==3 then							
		if self:_IsPartInUser(nSitId) then
			tUser.nStanpUpReason =MsgCode.nKickByAdmin
		else
			self:Oust(nSitId,MsgCode.nKickByAdmin,"KickByAdmin")
		end
	end
end

--踢出牌桌(通知前端令玩家返回大厅)
function Table:_KickToLobby(nSitId,nUserId)
	if not nSitId then
		nSitId =self:_GetSitIdByUserId(nUserId)
	end
	if nSitId then
		self:Oust(nSitId,nil,"KickToLobby")	
	end
	self:_BroadCastToSlaves("RSP_Kick_User",{nUserId =nUserId})
end

function Table:_WriteExpRecord(nUserId,nProfit)
	local nNowT =os.time()
	local nLatelyTime =self.tExpUserR[nUserId]
	local nTFlag =(nLatelyTime==nil) and 1 or 0
	local nDuration =nNowT -(nLatelyTime or self.nLatelyStartTime)
	local tData ={}
	tData.nUserId =nUserId
	tData.nGameId =self.nGameId
	tData.nProfit =nProfit
	tData.nTakeIn =self.tStatistic:GetTakeIn(nUserId)
	tData.nDuration =nDuration
	tData.nTFlag =nTFlag
	RecordDbr.WriteTexaExperience(tData)

	self.tExpUserR[nUserId] =nNowT
end


function Table:WriteRecord(nProfix,nTaxGold,tUser,isSettleInEnd,nInsur,sTaxTag)
	if tUser.isAndroid then return end
	if self:MatchRoomId()==0 then 
		self:_WriteExpRecord(tUser.nUserId,nProfix)
		return 
	end
	
	local isZhuang =(self.nBankerPos ==tUser.nSitId)

	local tData ={}
	tData.nUserId = tUser.nUserId
	tData.nGameType = self.nGameId
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
	end
	tData.tElseInfo.nInsur =nInsur
	tData.tElseInfo.sTaxTag=sTaxTag

	table.insert(self.arrWinLoseRecord,tData)	--缓存战绩，统一在结算后再写(因那时才能获得金币流向信息)
	--RecordDbr.Write_WinLoseRecord(tData)

	self:RealUserProfit(nProfix)
end

--按桌抽水记录
function Table:WriteRecordForTax(nUserId,nTaxGold,sTaxTag,sLatelyPaiJuId,isAndroid)
	if self:MatchRoomId()==0 then return end
	--if isAndroid then return end
	local tData ={}
	tData.nClubId =self.nClubId --俱乐部id
	tData.sTableId=self.sTableId --牌桌id
	tData.nItemId= self.nItemId--道具id
	tData.nGameType=self.nGameId --游戏id
	tData.nUserId=nUserId --玩家id
	tData.nDrawWater=nTaxGold --抽水
	tData.sPaiJuId=sLatelyPaiJuId --牌局id
	tData.nClubIdOfCorrect=self.nClubIdOfCorrect
	tData.nGroupId =self.nGroupId
	tData.nSession = self.nRoomId
	tData.isAndroid =isAndroid
	if self.nStage ==TableState.nPlaying  and self.sPaiJuId==sLatelyPaiJuId then
		table.insert(self.arrTaxForUpdate,tData)
	else
		self.tTableOverview:ProfitAdd(nUserId,-nTaxGold)
		tPublicRedis.TexaStatistic_ProfitAdd(nUserId,-nTaxGold,self.nClubIdOfCorrect,self.nGameId,self.nGoldType)
		if not isAndroid then
			RecordDbr.Update_WinLoseRecordTaxV2(tData)
		end
	end
end

function Table:UpdateCacheOfTax()
	for _,item in ipairs(self.arrTaxForUpdate) do
		self.tTableOverview:ProfitAdd(item.nUserId,-item.nDrawWater)
		tPublicRedis.TexaStatistic_ProfitAdd(item.nUserId,-item.nDrawWater,self.nClubIdOfCorrect,self.nGameId,self.nGoldType)
		if not item.isAndroid then
			RecordDbr.Update_WinLoseRecordTaxV2(item)
		end
	end
	self.arrTaxForUpdate ={}
end

function Table:WriteRecords()
	for _,item in ipairs(self.arrWinLoseRecord) do
		local tGoldFlowInfo =self.tUserIdToGoldFlowInfo[item.nUserId]
		if tGoldFlowInfo then
			item.nWinloseToRobot = tGoldFlowInfo.nWinFromAndroid +(item.tElseInfo.nInsur or 0)	--正确含义应该是:WinFromRobot
			item.nDrawWaterToRobot =-item.nDrawWater
			--if GreaterThan(item.nWinloseToRobot,0) then
			--	item.nDrawWaterToRobot =publicApi.Floor_2(self.nTax*item.nWinloseToRobot/100)
			--end
		else
			item.nWinloseToRobot = item.nWinlose+item.nDrawWater +(item.tElseInfo.nInsur or 0)	--正确含义应该是:WinFromRobot
			item.nDrawWaterToRobot =-item.nDrawWater
		end
		item.nClubId =self.nClubId                --俱乐部id (俱乐部房配置,否时为nil)
		item.nItemId=self.nItemId                 --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
		item.sTableId=self.sTableId
		item.nJuShu = self.nJuShu
		item.nSmallBlind = self.nSmallBlind
		item.nPreAnte = self.nPreAnte
		item.nZhuaTou = self.nZhuaTou
		item.nPreAnteOdd = self.preAnteOdd
		RecordDbr.Write_WinLoseRecord(item)
		if item.tElseInfo.nInsur  and item.tElseInfo.nInsur~=0 then
			RecordDbr.WriteUserRecord(item.nUserId,item.sPaiJuId,item.nGameType,1,item.tElseInfo.nInsur)	--保险记录
		end
	end
	self.arrWinLoseRecord ={}
end


function Table:WriteDetail()
	if self:MatchRoomId()==0 then return end

	local tElseInfo ={}
	tElseInfo.arrCommunityCards =self.arrCommunityCards
	tElseInfo.arrPool =self:_GetProtoArrPot()
	tElseInfo.tTableInfo =self:GetTableInfoForClub()
	tElseInfo.nClubId=self.nClubId
	tElseInfo.tWinUserInfo =self.tWinUserInfo
	
	local tData ={}
	tData.sPaiJuId =self.sPaiJuId
	tData.nGameId =self.nGameId
	tData.nRoomId =self.nRoomId
	tData.nAnte =self.nBigBlind
	tData.nZhuang =self.nBankerPos
	tData.tUsersInfo =self.tUsersInfo or {}
	tData.tDealCardInfo =self.tDealCardInfo or {}
	tData.tBetInfo =self.tBetInfo or {}
	tData.tElseInfo =tElseInfo or {}
	tData.sExData =cjson.encode({sLiveID=self.sLiveID})
	tData.sTableId =self.sTableId
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

function Table:_ElapWarnReset(isStop)
	local nRT =self:_GetRemainTime()
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
	local nRT =self:_GetRemainTime()
	if math.abs(nRT-nRemainT)>30  then
		self:Print("_ElapWarnBroadCast Lost,nRemainT:%d Real:%d",nRemainT,nRT)
		return
	end
	self.tWarnHistory[nRemainT]=true
	self:_BroadCastToSlaves("ElapWarn",{nRemainT=nRemainT})
	self:Print("_ElapWarnBroadCast %d Succee",nRemainT)
end


function Table:CloseTable(nReason)
	local nReason =nReason or -1
	self:Print("CloseTable,nReason:%d",nReason)
	self.Timer:KillAllTimer()
	self.TimerForAndroid:KillAllTimer()
	self.TimerForPause:KillAllTimer()
	self.TimerForRetain:KillAllTimer()
	self.TimerForElapWarn:KillAllTimer()
	self.TimerForAndroidEnter:KillAllTimer()
	self.TimerForForceUp:KillAllTimer()
	self.TimerForSplit:KillAllTimer()
	self.TimerForMatchStart:KillAllTimer()
	self.TimerGetMttAndroid:KillAllTimer()

	self:_BackMttAndroid()

	for nPos,_ in pairs(self.arrUsers) do
		self:_SetLeaveSeat(nPos)
	end
	--广播桌子关闭消息
	self:_BroadCastTableCloseNotify(nReason)
	--处理还没进行按桌抽水的玩家
	self:TaxByTableRateSettle_All()

	self.isTableClose =true			--设为true后，桌子不再能发出消息
	self:_ResetTable()
	self.tInterFace._TableClose(self.sTableId,self.nTableType)
end

function Table:IsFullCapacity()
	local nUserCnt = self:_UserCount()
	return (nUserCnt == self.nCapacity)
end

function Table:TableCheck()
	--俱乐部桌子超时判断
	if self:IsClubTableTimeOut() then
		self:SetClose(TableCloseReason.nClubTableTimeOut)
		return
	end
	local remainTime = self:_GetRemainTime()
	local cycle = math.min(60, remainTime)  --单位 秒, 取牌桌剩余时间和周期的较小值， 保证牌桌到期时能自动关闭

	self.TimerForAndroid:DelayCall(cycle*1000,self.TableCheck,self)
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

--俱乐部桌子是否超时
function Table:IsClubTableTimeOut()
	if self:_GetRemainTime() ==0 then
		return true
	end
	return false
end


--更新机器人数量限制配置
function Table:_UpdateAndroidCntCfg(n)
	local nSeconds =(n==1) and math.random(2,5) or math.random(60,120)
	self.TimerForAndroid:DelayCall(nSeconds*1000,self._UpdateAndroidCntCfg,self,0)
	if n==1 then
		return
	end
	local nMin,nMax =tPublicRedis.AndroidCountLimit(self.nGroupId,self.nGameId,self.nRoomId)
	local isUseDefault =(nMin==nil or nMax==nil or nMin<0 or nMax<0 or nMin>nMax)
	if isUseDefault  then
		if self:MatchRoomId() ==0 then					--试玩房
			self.tAndroidCfg.nMin=self.nCapacity-1
			self.tAndroidCfg.nMax=self.nCapacity-1
		else
			self.tAndroidCfg.nMin=0
			self.tAndroidCfg.nMax= math.floor(self.nCapacity/2)
		end
	else
		self.tAndroidCfg.nMin=nMin
		self.tAndroidCfg.nMax=nMax
	end
	self:_AndroidCntCfgOffset(self.nBackstageRobotAdd)	--后台增减机器人

	self:Print("tAndroidCfg nMin:%d nMax:%d isUseDefault:%s nGroupId:%d nRoomId:%d nGameId:%d nBackstageRobotAdd:%d",
		self.tAndroidCfg.nMin,self.tAndroidCfg.nMax,tostring(isUseDefault),self.nGroupId,self.nRoomId,self.nGameId,self.nBackstageRobotAdd)
end

function Table:_AndroidCntCfgOffset(nOffset)
	self.tAndroidCfg.nMin=self.tAndroidCfg.nMin +nOffset
	self.tAndroidCfg.nMax=self.tAndroidCfg.nMax +nOffset
	self.tAndroidCfg.nMin =math.max(self.tAndroidCfg.nMin,0)
	self.tAndroidCfg.nMax =math.max(self.tAndroidCfg.nMax,0)
end

--后台递减机器人命令
function Table:OnDecrAndroid()
	self.nBackstageRobotAdd=self.nBackstageRobotAdd -1
	self:_AndroidCntCfgOffset(self.nBackstageRobotAdd)

	self.nIncrAndroidCnt=0		--取消需要增加机器人的数量
	if self.nAndroidCnt==0 then	 --当前机器人数量为0
		self:Print("OnDecrAndroid nAndroidCnt is 0")
		return
	end
	if self:_DecrAndroid() then	--立即减少一个机器人
		self:Print("OnDecrAndroid immediate succee")
		return
	end
	self:Print("OnDecrAndroid delay")
	self.nDecrAndroidCnt=self.nDecrAndroidCnt +1
end

--后台递增机器人命令
function Table:OnIncrAndroid()
	self.nBackstageRobotAdd=self.nBackstageRobotAdd +1
	self:_AndroidCntCfgOffset(self.nBackstageRobotAdd)
	self.nDecrAndroidCnt =0			--取消需要减少机器人的数量
	if self:IsFullCapacity() then	--桌子已满人
		self:Print("OnIncrAndroid table is Full")
		return
	end
	if self:_IncrAndroid() then		--立即增加一个机器人
		self:Print("OnIncrAndroid immediate succee")
		return
	end
	self:Print("OnIncrAndroid delay")
	self.nIncrAndroidCnt =self.nIncrAndroidCnt +1
end

--立即递减一个机器人
function Table:_DecrAndroid()
	for nPos=1,self.nCapacity do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.isAndroid and self:_SetAndroidLeaveImmediate(tUser.nUserId) then
			return true
		end
	end
end

function Table:_SetAndroidLeaveImmediate(nUserId)
	local tAndroid =self.tInterFace.GetUser(nUserId)
	if tAndroid then
		return tAndroid:SetLeaveImmediate()
	end
	return false
end
function Table:_SetLeaveWhenEnd(nUserId)
	local tAndroid =self.tInterFace.GetUser(nUserId)
	if tAndroid then
		return tAndroid:SetLeaveWhenEnd()
	end
	return false
end

--令nCnt个机器人在结束时离开 
function Table:_SetAndroidLeaveWhenEnd(nCnt)
	if nCnt <=0 then
		return
	end
	local n=0
	for nPos=1,self.nCapacity do
		local tUser =self:_GetUser(nPos)
		if tUser and tUser.isAndroid and self:_SetLeaveWhenEnd(tUser.nUserId) then
			n =n+1
			if n==nCnt then
				return
			end
		end
	end
end

--尝试增加一个机器人
function Table:_IncrAndroid()
	local arrRobots =self.tInterFace._GetRobots({nGroupId=self.nGroupId,nRoomId=self.nRoomId,nEnterFloorLimit=self.nBuyMin},1)
	local tRobot =arrRobots[1]
	if tRobot==nil then
		return 
	end
	if not self:_CheckPoolEntryRate(tRobot.nUserId) then	--桌子有入池率限制
		self:_RaiseRobotEntryRate(tRobot.nUserId)
		self:Print("_CheckPoolEntryRate false,nUserId:%d",tRobot.nUserId)
		self.tInterFace._LeaveTable(tRobot.nUserId,self)	--归还机器人
		return
	end
	if self.tUserNameToIsUsed[tRobot.sName] then			--发现有机器人昵称重复
		self:Print("Error Repeat NickName:%s,nUserId:%d",tRobot.sName,tRobot.nUserId)
		self.tInterFace._LeaveTable(tRobot.nUserId,self)	--归还机器人
		return
	end
	self.tTableOverview:LookerIn(tRobot.nUserId,tRobot.sName,tRobot.sFaceId)

	local _,nSitId =self:OnUserEnter(tRobot)
	if not nSitId then
		self:Print("Error Android Enter Fail")
		self.tInterFace._LeaveTable(tRobot.nUserId,self)	--归还机器人
		return
	end
	tRobot:EnterTable(self,nSitId)
	return true
end

--
function Table:_TryLetAndroidEnter(nCallCnt)
	if nCallCnt==1 then				--刚开桌子,隔个两三秒再进机器人
		return math.random(2,5)
	end
	if self:IsFullCapacity() then	--桌子已满人
		return math.random(5,20)
	end
	if self:_IsMendOpenTableLimitRobot() then 
		return math.random(10,30)
	end 

	local nCnt =math.random(self.tAndroidCfg.nMin,self.tAndroidCfg.nMax)
	if self.nAndroidCnt>=nCnt and self.nIncrAndroidCnt<=0 then
		return math.random(5,20)
	end
	if not self:_IncrAndroid() then	 --增加一个机器人
		return math.random(2,5)		--如果增加失败，则加快下一次调用时间
	end
	if self.nIncrAndroidCnt >0 then
		self.nIncrAndroidCnt =self.nIncrAndroidCnt -1
	end
	if self.nAndroidCnt>0 and self.nAndroidCnt>=self.tAndroidCfg.nMax then
		return math.random(20,60)	--机器人数量已达到最大值，则延长下一次调用时间
	end
	if self.nAndroidCnt <self.tAndroidCfg.nMin or self.nIncrAndroidCnt >0 then
		return math.random(1,6)	--机器人数量过小，则加快下一次调用时间
	end
	return math.random(5,20)
end

--判断是否加入机器人. (机器人的离开，由该机器人本身决定，玩够随机的一个局数便主动离开)
function Table:TryLetAndroidEnter(n)
	if self.isRobotBan then
		self:Print("Android is ban")
		return
	end
	local nSeconds =self:_TryLetAndroidEnter(n) or 10
	self.TimerForAndroidEnter:KillAllTimer()
	self.TimerForAndroidEnter:DelayCall(nSeconds*1000,self.TryLetAndroidEnter,self,n+1)
	--self:_IsMendOpenTableLimitRobot()	
end

-- 是否补桌限制机器人进入： 游戏开始会自动补桌
--返回true:限制机器人进入
function Table:_IsMendOpenTableLimitRobot()
	if self.nContinuedNum==nil or self.nContinuedNum<=0 or self.nPlayCnt >0 then 
		return false
	end
	local nUserCnt,nRealUserCnt = self:_UserCount()
	local nNowRobotCnt =(nUserCnt -nRealUserCnt) 
	local nAllRealUserCnt = self.nSlaveUserCnt -- 全部真人: 旁观+坐下玩
	-- 无真人情况下，机器人数量要低于 自动开始人数 
	if nAllRealUserCnt == 0 and self.nStartAtLeast > 0 then 
		if nNowRobotCnt > 0 and nNowRobotCnt >= self.nStartAtLeast - 1 then
			self:Print("_IsMendOpenTableLimitRobot  限制机器人进入 补桌_%d 总人数_%d 机器人_%d 真人_[%d/%d] 自动开始_%d "
			,self.nContinuedNum,nUserCnt,nNowRobotCnt,nAllRealUserCnt,nRealUserCnt,self.nStartAtLeast)
			return true 
		end
	end  
	return false 
end


--提升机器人入池率
function Table:_RaiseRobotEntryRate(nUserId)
	local tTableInfo ={nClubId=self.nClubIdOfCorrect,nGameId=self.nGameId,nGoldType=self.nGoldType}
	local tUserData ={}
	tUserData.nUserId =nUserId
	tUserData.nPlayCount =math.random(1,20)
	tUserData.nInPoolCount =tUserData.nPlayCount
	tUserData.nRaiseCountBFlop=0
	tUserData.nAllInAndWinCount=0
	tUserData.nProfitSum=math.random(self.nBigBlind,5*self.nBigBlind)
	tPublicRedis.TexaStatistic_WriteN(tTableInfo,{tUserData})
end


--非游戏中才会有动作
function Table:_Pause()
	if self.isToStartGame then
		self:StopTiming()
		self.Timer:KillAllTimer()
		self.isToStartGame=false
		self:_ToPauseCancel(Define.PauseTime)
		self:_BroadToStart(-1,Define.PauseTime) 		--广播取消倒计时(如果有),并暂停等待
		self.nTimeStart =-1
		return
	elseif self.nStage ==TableState.nInit then
		self:StopTiming()
		self:_ToPauseCancel(Define.PauseTime)
		self:_BroadToStart(-1,Define.PauseTime) 		--广播取消倒计时(如果有),并暂停等待
		self.nTimeStart =-1
		return
	end
end

function Table:_ToPauseCancel(nDelaySeconds)
	--self.TimerForPause
	self.TimerForPause:DelayCall(nDelaySeconds*1000+500,Table._ChangePause,self,false)
end

function Table:_PauseCancel()
	if not self:_TryToStartGame(3) then --如果没进行作为则
		self:_BroadToStart(0)			--广播取消倒计时或暂停(这里为取消暂停)
		self.nTimeStart =0
	end
	self:BeginTiming()
end


function Table:_TryToStartGame(nToStartTimeMin)
	if self.nStage ~=TableState.nInit then 
		self:Print("_TryToStartGame nStage not Init")
		return 
	end
	if not self.isMatchStart then
		self:Print("_TryToStartGame Match not start")
		return
	end
	if self.isPause then 
		self:Print("_TryToStartGame isPause is true")
		assert((not self.isToStartGame),"isToStartGame Error")
		return 
	end
	if not self.isAutoNext then
		self:Print("_TryToStartGame isAutoNext is false")
		assert((not self.isToStartGame),"isToStartGame Error2")
		return
	end
	if not self.isTableStart then
		self:Print("_TryToStartGame isTableStart is false")
		assert((not self.isToStartGame),"isToStartGame Error3")
		return
	end
	

	local valueUserCnt =self:_UserCount_NotRetain()
	self:Print("_TryToStartGame valueUserCnt:%d nStartAtLeast:%d isToStartGame:%s",
			valueUserCnt,self.nStartAtLeast,tostring(self.isToStartGame))

	if valueUserCnt <self.nStartAtLeast then
		if self.isToStartGame then
			self.Timer:KillAllTimer()
			self.isToStartGame =false
			self:_BroadToStart(0)				 --广播取消倒计时或暂停(这里为取消倒计时)
			self.nTimeStart =0
			return true
		end
	elseif not self.isToStartGame then 
		--local nToStartTimeMin =nToStartTimeMin or 1
		self.Timer:KillAllTimer()
		self.isToStartGame=true
		local nSeconds =1.5
		--if  nSeconds < nToStartTimeMin then nSeconds =nToStartTimeMin end
		self.Timer:DelayCall(nSeconds*1000+50,Table.StartGame,self)
		self:_BroadToStart(nSeconds)			  --广播倒计时时间(毫秒),并取消暂停(如果有)
		self.nTimeStart =os.time() +nSeconds
		return true
	end
end

function Table:_GetUser(nPos)
	return self.arrUsers[nPos]
end
function Table:_GetUserId(nPos)
	local tUser =self.arrUsers[nPos]
	if tUser then
		return tUser.nUserId
	end
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
function Table:_UserCount_NotRetain()
	local nCnt =0
	for nPos=1,self.nCapacity do
		local tUser =self:_GetUser(nPos)
		if tUser and (not tUser.isRetain) and self:_IsMoneyCanPartIn(tUser) then
			nCnt =nCnt+1
		end
	end
	return nCnt
end
function Table:_IsMoneyCanPartIn(tUser)
	if Equal(tUser.nLockGoldInTable,0) and tUser.nBuyTo==0 then
		return false
	end
	if Equal((self:Get_User_UnLockGold(tUser) +tUser.nLockGoldInTable),0) then
		return false
	end
	return true
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
	self.nPartInCount =0			--牌局开始时，参与牌局的玩家数量
	self.nDecrAndroidCnt=0			
	self.nIncrAndroidCnt=0
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

	self.tFlopAfterInsur =nil			--翻牌后保险信息
	self.tTurnAfterInsur =nil			--转牌后保险信息

	self.nSeq =0
	self.arrAiUser={}
	--[[
	self.nStartAtLeast=(self.nPlayerCntAtLeast or 2)
	self.nStartAtLeast=math.max(self.nStartAtLeast,2)
	]]
	--第一局开始后，后续开始最少人数统一为2人
	self.nStartAtLeast=2
	self.tUsersKickToLobbyWhenOver ={}
	self.tOpHistory ={}
end

function Table:_SetGameStage(nValueToSet)
	self.nStage =nValueToSet
	self.nLatelyStageTimeSt=os.time()
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
	tUser.nTimeOutCnt =tUser.nTimeOutCnt	--玩家超时次数
	tUser.isAuto=tUser.isAuto				--是否托管
	tUser.isHaveOp=false        		--当局是否有操作
	tUser.nFee =0						--记录一局开始时扣减的手续费
	tUser.nRank =nil					--预发牌模式时记录牌型大小,1为最大，次之
	tUser.nBetSum =0					--当局总下注
	tUser.isShowCardWhenEnd=false		--是否结束后亮牌
	tUser.nGetChanceCnt =0				--当局获得操作机会的次数
	tUser.nStanpUpReason=nil			--当局结束后,是否强制站起(nil:否,非nil:被站起原因)
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
	--	self:Print("_NextGainRightsPos nCurPos_%d  nCapacity_%d ",nCurPos,self.nCapacity)
		nCurPos =self:_NextPos(nCurPos)
		if nCurPos==self.nTheRightsEndPos then
			return 
		end
		if self:_IsCanGainRight(nCurPos) then
			return nCurPos
		end
	end
end

function Table:_IsCanGainRight(nPos)
	local tUser =self:_GetUser(nPos)
	if tUser and tUser.nStatus ~=UserStatus.nAllIn and 
			tUser.nStatus ~=UserStatus.nFold and tUser.nStatus ~=UserStatus.nLooker then
		return true
	end
	return false
end

--无力解释的一个辅助函数
function Table:_CheckHoldCardOpen(nRPos)

	local arrUserId ={}
	local nCurPos =self.nFirstPos
	for i=1,self.nCapacity do
		nCurPos =self:_NextPos(nCurPos)
		if nCurPos ==nRPos then
			break
		end
		local tUser =self:_GetUser(nCurPos)
		if tUser and tUser.nStatus ~=UserStatus.nLooker and (not tUser.isShowHoleCard) then
			table.insert(arrUserId,tUser.nUserId)
		end
	end
	if nRPos ==self.nFirstPos then
		return arrUserId
	end
	
	nCurPos =nRPos
	for i=1,self.nCapacity do
		nCurPos =self:_NextPos(nCurPos)
		if self:_IsCanGainRight(nCurPos) then
			return arrUserId
		end
		if nCurPos ==self.nFirstPos then 
			break
		end
	end
	
	nCurPos =nRPos
	for i=1,self.nCapacity do
		nCurPos =self:_NextPos(nCurPos)
		local tUser =self:_GetUser(nCurPos)
		if tUser and tUser.nStatus ~=UserStatus.nLooker and (not tUser.isShowHoleCard) then
			table.insert(arrUserId,tUser.nUserId)
		end
		if nCurPos ==self.nFirstPos then 
			break
		end
	end
	return arrUserId
end


--nFirstPos

--下注
function Table:_DoBet(nPos,nBet)
	local tUser =self:_GetUser(nPos)
	assert(tUser ~=nil)
	assert(GreaterOrEqual( tUser.nBalance,nBet),tostring(nBet))
	assert(GreaterOrEqual( nBet,0),tostring(nBet))

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

--返回实际下注成功的数额
function Table:_TryDoBet(nPos,nBet)
	local tUser =self:_GetUser(nPos)
	assert(tUser ~=nil)
	local nAcBet =math.min(tUser.nBalance,nBet)
	if GreaterThan(nAcBet,0) then
		self:_DoBet(nPos,nAcBet)
		return nAcBet,tUser.nBalance,tUser
	end
	return 0,tUser.nBalance,tUser
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
	--保险结算
	local nInsur =self:InsurSettle(tUser.nUserId)

	--余额收入
	local arrGoldGet=arrGoldGet or {}
	local nChipsGet =0													--底池收入
	for _,v in ipairs(arrGoldGet) do
		nChipsGet =nChipsGet +v.nGold
	end
	local nInsurGet =GreaterThan(nInsur,0) and nInsur or 0				--保险收入
	tUser.nBalance =tUser.nBalance +nChipsGet +nInsurGet

	--余额扣减
	local nInsurLoss =LessThan(nInsur,0) and -nInsur or 0								--保险费
	local nChouShui,sTaxTag =self:CalTax(nChipsGet -tUser.nBetSum -nInsurLoss,tUser.nUserId,tUser.isAndroid)	--服务费(保险赢不抽水)
	tUser.nBalance =tUser.nBalance -nInsurLoss -nChouShui

	--余额欠费处理
	local nShort =LessThan(tUser.nBalance,0) and -tUser.nBalance or 0	--欠费(由保险费引起的，导致被玩家白嫖的数额)
	tUser.nBalance =math.max(tUser.nBalance,0)
	if GreaterThan(nShort,0) then
		local nUnLockGold =self:Get_User_UnLockGold(tUser)
		local nToLock =math.min(nUnLockGold,nShort)
		if self:Gold_Lock(tUser,nToLock) then
			nShort =nShort -nToLock	
		end					
	end
	if GreaterThan(nShort,0) then
		self:Print("Waring,nShort:%.2f,nUserId:%d",nShort,tUser.nUserId) --欠费警告
	end

	--玩家账户盈利
	local nPaiJuProfit =(nChipsGet +nInsurGet) -(nInsurLoss +nChouShui +tUser.nBetSum) +nShort
	self:Print("ChipSettle nUserId:%d ,nPos:%d,nPaiJuProfit:%.3f nChouShui:%.2f nBalance:%.3f nInsur:%.2f nShort:%.2f",
		tUser.nUserId,tUser.nSitId,nPaiJuProfit,nChouShui,tUser.nBalance,nInsur,nShort)
	local nSourceType =10000 +100*self.nGameId +GoldCReason.nSettle
	local isSuccee, nAcChange=self:Gold_ChangeAndReLock(tUser,nPaiJuProfit,nSourceType,self.nRoomId)
	assert(isSuccee)
	self:Print("nAcChange:%s",tostring(nAcChange))
	nPaiJuProfit =(nAcChange or nPaiJuProfit)

	--记录与统计
	local nInsurActual =nInsur +nShort
	self.nInsurPool =self.nInsurPool -nInsurActual									--保险池
	self:WriteRecord(nPaiJuProfit,nChouShui,tUser,isSettleInEnd,nInsurActual,sTaxTag)
	local isWin =GreaterThan(nChipsGet,tUser.nBetSum)
	self.tTableOverview:UserSettle(tUser.nUserId,nPaiJuProfit,tUser.nBalance)
	self.tStatistic:UserProfit(tUser.nUserId,nPaiJuProfit,nInsurActual)
	self.tStatistic:UserWin(tUser.nUserId,nChipsGet-tUser.nBetSum,tUser.isAndroid)

	if (not isSettleInEnd) or tUser.nStatus ==UserStatus.nFold then
		if Equal(tUser.nBalance,0) then
			self.tStatistic:UserGiveUp(tUser.nUserId,tUser.isAndroid)
		end
	end
	if tUser.nStatus ==UserStatus.nAllIn and isWin then
		self.tStatistic:UserWinAndAllIn(tUser.nUserId)
	end
	self.tReview:InsureProfit(tUser.nUserId,nInsurActual)

	--错误检测
	if not Equal(tUser.nBalance,tUser.nLockGoldInTable) then
		self:Print("Error Find,nBalance:%.3f,nLockGoldInTable:%.3f",tUser.nBalance,tUser.nLockGoldInTable)
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
	table.insert(self.tUsersInfo,item)
	table.insert(self.tDealCardInfo,{nSitId=tUser.nSitId,arrCard=tUser.arrHoleCards,nCardType=tUser.tCardType.nCardType,
		isFold=isFold,isShowCardWhenEnd =tUser.isShowCardWhenEnd})
	table.insert(self.tBetInfo,{nSitId=tUser.nSitId,nBet=tUser.nBetSum})
	if isWin then
		self.tWinUserInfo = {sName =tUser.sName,nUserId=tUser.nUserId,nCardType=tUser.tCardType.nCardType}
	end
	return nPaiJuProfit,nChouShui
end

--玩家余额(筹码)转为金币
function Table:_UserBalanceToGold(tUser)
	local isSuccee =self:Gold_UnLockAll(tUser)
	assert(isSuccee)
end

function Table:_TryBuyUpTo(tUser,nBuyTo)
	self:Print("_TryBuyUpTo,nUserId:%d nBuyTo:%.2f",tUser.nUserId,nBuyTo)
	if LessThan(tUser.nLockGoldInTable,nBuyTo) then
		local curGold =self:Get_User_UnLockGold(tUser)
		curGold=publicApi.Floor_2(curGold)
		local nLack =nBuyTo-tUser.nLockGoldInTable
		nLack =math.min(curGold,nLack)
		local isSuccee =self:Gold_Lock(tUser,nLack) 
		self:Print("_TryBuyUpTo,nUserId:%d curGold:%.2f nLack:%.2f nBuyTo:%.2f",tUser.nUserId,curGold,nLack,nBuyTo)
		assert(isSuccee)
	end
end

--筹码充值 
--nBalanceBest :最佳达到值 ; nEnterMin:至少达到值
-- sourceType: 充值来源 0 筹码充值, 1 筹码带入
function Table:_InitUserTakeIn(tUser,nBalanceBest,nEnterMin,sourceType)
	local nEnterMin=nEnterMin or self.nEnterMin
	local nGoldLockInit =tUser.nLockGoldInTable
	if LessThan(tUser.nLockGoldInTable,nEnterMin) then
		local nLack =nEnterMin -tUser.nLockGoldInTable
		if not self:Gold_Lock(tUser,nLack,sourceType) then
			return false
		end
		local nBuyTo =math.min(self.nTakeIn,self.nBuyMax)
		self:_TryBuyUpTo(tUser,nBuyTo)
	end
	self:_TryBuyUpTo(tUser,nBalanceBest)
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
		if tUser.nStatus ==UserStatus.nAllIn or tUser.isAuto or (not tUser.isShowHoleCard) then
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
			if self.isAOF then
				nOpIdB =tUser.nBalance
			end
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
		local nCtrlType =tPubUser.IsNeedControl(self.nGameId,self.nRoomId,nUserId)
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
	self.tCurRedisDetail =tem
	local sCurPaiJu =cjson.encode(tem)
	tPublicRedis._UpdateCurPaiJu(self.sTableId,sCurPaiJu)
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
	end
	--操作结束(即将轮到下一玩家操作，或即将结束本轮)
	local isHasNextUser =self:_OpEnd(nPos)
	--初始化玩家可预操作选项
	if isHasNextUser then
		self:_InitUsersPreOpOption()		--设置玩家的预操作
	else
		self:_InitUsersPreOpOption(true)	--清除非弃牌玩家的预操作
	end
	--广播有玩家操作通知
	self:_BroadCastOpNotify(nPos,nOp,nCallOrRaiseChip,tUser)

	--统计玩家操作次数
	self:_AddOpCount(tUser.nUserId,nOp)

	--一些统计和记录
	local nTimeUse =math.max((os.time() -tUser.nFGetRightTime),1) 
	self.tReview:DoOp(nPos,nOp,nCallOrRaiseChip,nTimeUse)		--回顾记录
	if GreaterThan(nCallOrRaiseChip,0) then
		self.tTableOverview:UserInPool(tUser.nUserId)	--玩家入池(桌子总览)
		self.tStatistic:UserInPool(tUser.nUserId)		--玩家入池(当局统计)
	end
	if isIncreasesBet and #self.arrCommunityCards==0 then
		self.tStatistic:UserDoRaiseBeforeFlop(tUser.nUserId) --翻牌前加注(当局统计)
	end
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
	tUser.nFGetRightTime =os.time()
	tUser.isToGainRights =false
	tUser.tOperation =self:_GetProtoOperationRights(nPosToGainRights)
	local nPreOpIdOfOn =self:_GetPreOpIdOfOn(tUser.tPreOpOption)
	tUser.tPreOpOption =nil
	tUser.nDelayCount =0
	tUser.nOpLong =self.nOperateTime
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
		self:_ToOpForTimeOutUser(2,nPosToGainRights)
	else
		self:_ToOpForTimeOutUser(self.nOperateTime,nPosToGainRights)
	end

	local isDoOpenHodeCard =false		--是否进行底牌公开
	if not tUser.isShowHoleCard then
		tUser.isShowHoleCard=true
		isDoOpenHodeCard=true
	end
	local arrUserIdNeedOpenHodeCard ={}	--除了当前获得操作权的玩家外，还需要进行底牌公开的玩家id
	if isDoOpenHodeCard then
		arrUserIdNeedOpenHodeCard =self:_CheckHoldCardOpen(nPosToGainRights)
	end
	for _,nUserIdNeed in ipairs(arrUserIdNeedOpenHodeCard) do
		local _,tUserr =self:_GetSitIdByUserId(nUserIdNeed)
		assert(tUserr~=nil)
		tUserr.isShowHoleCard =true
	end
	if #arrUserIdNeedOpenHodeCard>0 then
		self:Print("arrUserIdNeedOpenHodeCard:%s",table.concat(arrUserIdNeedOpenHodeCard))
	end

	--广播有玩家获得操作权
	self:_BroadCastGetRightNotify(tUser,nPosToGainRights,isDoOpenHodeCard,arrUserIdNeedOpenHodeCard)
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
	local arrTheWinItem =self.tAlg.TheWinCardType(arrNotFoldUsersCardType)
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
		--if tUser.nStatus~=UserStatus.nFold then
			tUser.tCardType =self.tAlg.DeZhouCardType(tUser.arrHoleCards,self.arrCommunityCards)
		--end
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
	--执行多轮收归操作,最终收归所有下注
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


--有存活且不同才追加,其它情况合并
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
		if self.isAOF then	
			nOpB =UserOp.nAllIn
		end
	else
		nOpB =UserOp.nAllIn
	end
	local nDelayCost =self.arrDelayCost[1]	--延时操作花费

	--第三按钮,有三种可能状态 'AllIn', '加注', '加注(置灰)'  (缺:特殊情况时禁止加注的情况)
	if nOpB ==UserOp.nAllIn then
		nOpC =UserOp.nRaiseBan
		return {nOpA=nOpA,nOpB=nOpB,nOpC=nOpC,nDelayCost=nDelayCost}
	end
	local nMin =math.max(self.nLatelyIncreasesBet,self.nBigBlind) +self.nTheHighestBet -tUser.nBet
	if LessOrEqual(tUser.nBalance,nMin) then
		nOpC =UserOp.nAllIn
		return {nOpA=nOpA,nOpB=nOpB,nOpC=nOpC,nDelayCost=nDelayCost}
	end

	nOpC =UserOp.nRaise
	local tRaiseChoice ={}
	tRaiseChoice.nMin =nMin
	tRaiseChoice.nMax =tUser.nBalance
	tRaiseChoice.arrQuickRaise=self:_GetUserQuickRaise(tUser,tRaiseChoice.nMin,tRaiseChoice.nMax)	--(快速操作的选项)
	return {nOpA=nOpA,nOpB=nOpB,nOpC=nOpC,tRaiseChoice=tRaiseChoice,nDelayCost=nDelayCost}
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
	tUser.isAuto =tUser.isAuto or (tUser.nTimeOutCnt >=Define.TimeOutMax)
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

--返回的数据不能改动(因为有些table不是copy的)
function Table:GetAiScence(nSelfUserId,tOperation)
	local tS ={}	
	tS.sTableId =self.sTableId or "-1"   			 
	tS.sPaiJuId =self.sPaiJuId or "-1"   	
	tS.nGameId =self.nGameId
	tS.nGroupId =self.nGroupId
	tS.nRoomId =self.nRoomId	 

	tS.nLevel = RedisCahche._GetTexasAndroidLevelCfg(self.nGroupId,self.nGameId,self.nRoomId)
	tS.bControl = false 
	if self.isControl and (self.isControl==2 or self.isControl==3) then 
		tS.bControl = true 
	end  
	tS.nStage =self:_GetAiStage()					--1 2 3 4 分别对应公共牌数量 0 3 4 5
	tS.nBankerPos=self.nBankerPos  	    			--庄家位置
	tS.nCapacity =self.nCapacity					--能供玩游戏的座位数
 
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
	tScenc.nTimeStart =self.nTimeStart				-->0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	tScenc.nBuyMin =self.nBuyMin	 				--最小买入
	tScenc.nBuyMax =self.nBuyMax					--最大买入
	tScenc.arrPartInUser ={}						--玩家位用户
	tScenc.sTableName =self.sTableName				--桌子名称 
	tScenc.nClubId=self.nClubId
	tScenc.nItemId =self.nItemId					--使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	tScenc.nGoldType =self.nGoldType				-- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)
	tScenc.isTableStart=self.isTableStart	   		--牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	tScenc.isAutoNext=self.isAutoNext				--下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始(前端判断>=2人时才给房主显示该按钮)				
	tScenc.tTableConfig =self:_GetTableConfig()
	tScenc.nRoomType=self.nRoomType					--10:大厅桌子 11:俱乐部桌子
	tScenc.arrChat=self.arrChat
	tScenc.nGameId=self.nGameId
	tScenc.nClubIdOfCorrect =self.nClubIdOfCorrect	--大厅的ClubId统一用0表示
	tScenc.nElapsedStatus=self:_ElapsedStatus()		--桌子当前计时状态 0正常 1暂停
	tScenc.nNextAssignTime =self.nNextAssignTime
	tScenc.nEventId =self.nEventId					--赛事id

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
	item.nOpLong =tUser.nOpLong
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
	if not nUserId then
		return
	end
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
	if not sReturnKey then return end
	local DZCRsp={}
	DZCRsp.sTableId =self.sTableId	
	DZCRsp.sCmd =sCmd
	DZCRsp.sJsonData=cjson.encode(tData)	--主从服通信内容主体用json格式
	DZCRsp.nEcho =-1
	tSlaveManager.Send(sReturnKey,"DZCRsp",DZCRsp)

	--self:Print("_SendToSlave %s %s",sCmd,DZCRsp.sJsonData) --for test
end

--广播有玩家取消托管通知
function Table:_BroadCastCancelAutoNotify(nSitId)
	--广播给从服
	self:_BroadCastToSlaves("CancelAutoNotify",{nPos =nSitId})
end

function Table:_GetPartInUserStatus()
	local arrUser={}
	for _,pos in ipairs(self.arrPosPartIn) do
		local tUser =self.arrUsers[pos]
		assert(tUser~=nil)
		local item ={}
		item.nSitId =pos
		item.tPreOpOption =tUser.tPreOpOption
		local tCardType =tUser.tCardType or {}
		item.nCardType =tCardType.nCardType or 0
		item.nStatus =tUser.nStatus
		item.arrCombinedCards =(tUser.nStatus~=UserStatus.nFold) and tCardType.arrFiveBack or {}
		table.insert(arrUser,item)
	end
	return arrUser
end

--广播发公共牌
function Table:_BroadCastDeZhouDealNotify(arrCardsNewAdd,isShowCard)
	--广播给从服
	local DealNotify={}
	DealNotify.nPotSum =self.nPotSum					--底池总额(已押筹码总额)
	DealNotify.arrPot =self:_GetProtoArrPot()			--收归的各底池数额(池数量:>0),数组索引代表池ID,索引从1开始
	DealNotify.arrCardsNewAdd=arrCardsNewAdd					--新增的公共牌
	DealNotify.isShowCard =isShowCard
	DealNotify.arrUser=self:_GetPartInUserStatus()
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
	item.isPop=self:_IsShouldPop(tUser)		--是否弹窗提示玩家补充筹码
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
function Table:_BroadCastGetRightNotify(tUser,nPosToGainRights,isDoOpenHodeCard,arrUserIdNeedOpenHodeCard)
	--广播给从服
	local GetRightNotify ={}
	GetRightNotify.nPos =nPosToGainRights
	GetRightNotify.tOperation =tUser.tOperation
	GetRightNotify.nGetRightTime =tUser.nGetRightTime
	GetRightNotify.nStatus =tUser.nStatus
	GetRightNotify.tPreOpOption =nil
	GetRightNotify.isDoOpenHodeCard =isDoOpenHodeCard
	GetRightNotify.nOpLong =tUser.nOpLong
	GetRightNotify.arrUserIdNeedOpenHodeCard=arrUserIdNeedOpenHodeCard
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

--广播游戏即将开始,nPauseRemain:暂停时间 秒
function Table:_BroadToStart(nSeconds,nPauseRemain)
	local nMSeconds =nSeconds
	if nSeconds >0 then
		nMSeconds =nSeconds *1000
	end
	--广播给从服
	self:_BroadCastToSlaves("ToStartNotify",{nMSeconds =nMSeconds,nPauseRemain=nPauseRemain})
end

--广播游戏开始
function Table:_BroadCastGameStartNotify(nSmallBlindPos,nBigBlindPos,arrPosPartInSort,nForceBlindPos,nAcBetSmall,nAcBetBig,nAcForceBet)
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
	GameStartNotify.nPreAnte =self.nPreAnte							--前注
	GameStartNotify.nOperateTime =self.nOperateTime  				--操作时间
	if nForceBlindPos then
		GameStartNotify.nForceBlindPos =nForceBlindPos					--强盲位置(可能为nil,如果没强盲)
		GameStartNotify.nForceBlind =self.nForceBlind					--强盲数额
	end
	GameStartNotify.nAcBetSmall=nAcBetSmall							--小盲位实际盲注(因存在筹码不足的情况，所以有此值)
	GameStartNotify.nAcBetBig =nAcBetBig							--大盲位实际盲注(因存在筹码不足的情况，所以有此值)
	GameStartNotify.nAcForceBet =nAcForceBet						--实际强盲下注

	GameStartNotify.nSmallBlind=self.nSmallBlind 			--小盲注数额
	GameStartNotify.nBigBlind=self.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	GameStartNotify.nBlindUpR =self:_GetBlindUpRemainTime()	--下一次升盲剩余时间

	self:Print("GameStart nBlindUpR:%d",GameStartNotify.nBlindUpR)

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
		item.nBet =tUser.nBet				 				--玩家总下注(注意，发给前端的不是总下注，在从服进行了分开的)
		item.nStatus=tUser.nStatus		 					--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
		item.tPreOpOption=tUser.tPreOpOption				--自己当前可预操作选项
		item.nChipBuy =tUser.nChipBuy
		item.isShowHoleCard =tUser.isShowHoleCard			--如果延迟看牌,则不公布底牌给玩家,直到获得第一次操作权(由从服处理这个逻辑)
		item.nUnLockGold =self:Get_User_UnLockGold(tUser)   --同步可用金币(主要服务于试玩房金币,其它一般以redis为准)
		item.nPreAnte =tUser.nPreAnte or 0					--玩家所下前注
		table.insert(GameStartNotify.arrPartInUser,item)
	end
	self:_BroadCastToSlaves("GameStartNotify",GameStartNotify)

	--主要是广播给机器人
	local DeZhouStartNotify ={}
	DeZhouStartNotify.arrUsersBet={{nPos=nSmallBlindPos,nBet=nAcBetSmall},{nPos=nBigBlindPos,nBet=nAcBetBig},
										{nPos=(nForceBlindPos or -1),nBet=nAcForceBet}} 
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
	self:_BroadCastToSlaves("TableResetNotify",{nStage=self.nStage,isAutoNext=self.isAutoNext})
	--主要是广播给机器人
	for nPos,_ in pairs(self.arrUsers) do
		self:SendToUser(nPos,"DeZhouTableResetNotify",{nNoUse=0,isAutoNext=self.isAutoNext})
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
	tUser.nSex =tUserInfo.nSex or 0 --0:男 1:女
	tUser.isAndroid =tUserInfo.isAndroid
	tUser.nShopId=tUserInfo.nShopId or -1
	tUser.sShopAccount =tUserInfo.sShopAccount or ""
	
	--not use
	tUser.nIsAutoBuy =0								--玩家设置的是否自动每局买入
	tUser.nTakeOutWant =0							--玩家设置带出
	tUser.isAddFreeTimeIfStart =false				--游戏开始时，免费场试玩次数是否加1
	tUser.tGps =nil
	tUser.sIP =nil

	--
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
	tUser.isHaveOp=false        	--当局是否有操作
	tUser.nFee =0					--记录一局开始时扣减的手续费(废弃)
	tUser.nStanpUpReason=nil		--当局结束后,是否强制站起(nil:否,非nil:被站起原因)
	tUser.isShowCardWhenEnd =false 	--是否结束后亮牌
	tUser.arrPreSetHoleCard={} 		--预设置的底牌

	tUser.nGetChanceCnt =0		--当局获得操作机会的次数
	tUser.nFGetRightTime =0		--最近一次获得操作权时的间戳(延时操作不会重设置该值)
	tUser.nGetRightTime =0      --最近一次获得操作权时的间戳(延时操作相当于重新获得操作)
	tUser.nOpLong =0			--获得操作时，操作时间(延时操作相当于重新获得操作)
	tUser.isShowHoleCard=true	--由于延迟看牌原因,false时不给玩家看底牌,直到第一次获得操作时才公布且置true
	tUser.isRetain=false		--是否留座
	tUser.nRetainTimerId=nil	--留座计时器id
	tUser.nDelayCount =0		--当前已进行延时的次数(玩家可操作时有效)
	tUser.nAiType =0			--机器人Ai类型;0一般 1进取 2保守
	tUser.nLockGoldInTable=0	--当前被锁在本桌子的金币
	tUser.isBackToLobby=false		--是否返回了大厅

	--继承上一个牌桌的状态
	tUser.nBuyTo =tUserInfo.nBuyTo or 0							--玩家设置的买入
	tUser.nRCnt =tUserInfo.nRCnt or 0							--已重购次数
	tUser.nACnt =tUserInfo.nACnt or 0 							--已增购次数
	tUser.nTimeOutCnt = tUserInfo.nTimeOutCnt or 0				--玩家超时次数
	tUser.isAuto = tUserInfo.isAuto or false					--是否托管 (托管时操作时间变短)
	tUser.nConsecutiveNoOp=tUserInfo.nConsecutiveNoOp or 0		--连续多少'局'没操作
	
	--初始绑定时,默认为离线状态
	tUser.nOffLineCnt =1				--掉线+1 上线-1
	
	--寻找一个空闲位置
	local nPosForPlay =nPosForPlay or self:_FindAPosForPlay()
	self:Print("_FindAPosForPlay %s",tostring(nPosForPlay))
	if not nPosForPlay then
		self:Print("OnUserEnter Fail,Find pos Fail")
		return nil,nil,14
	end
	assert(self:_IsPlayerPos(nPosForPlay))

	--初始化带入金币 
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

	--带入筹码设置
	self:Print("OnUserEnter,nUserId:%d nBalance:%s nBestTakeIn:%.2f",tUser.nUserId,tostring(tUserInfo.nBalance),nBestTakeIn)
	if not self:_InitUserTakeIn(tUser,nBestTakeIn,0, PublicDefine.TakeInGoldType.TakeIn) then  
		self:Print("OnUserEnter,Gold Not enough")	--不会执行到这
		return nil,nil,12
	end
	tUser.nBalance=tUser.nLockGoldInTable	--当前可用筹码
	
	--坐下
	self:_SetSitInSeat(nPosForPlay,tUser,true)
	self.tTableOverview:HaveTakeIn(nUserId,tUser.sName,tUser.nBalance,tUser.sFaceId)
	self.tInterFace.UpdateMttUsersRank(self.nEventId)
	self.tInterFace.UserEnterTable(nUserId,self,nPosForPlay)
	

	tPubUser.IncrUnbalancedBy(tUser.nUserId,1)
	return tUser,nPosForPlay,0
end

function Table:_AndroidTakeIn()
	local arr ={}
	local x =self.nBigBlind*50
	local n = math.floor((self.nBuyMax -self.nBuyMin)/x)
	return self.nBuyMin +math.random(0,n)*x
end


--玩家游戏中离开(站起),调用时还没离开
function Table:_LeaveInPlaying(tUser)
	self:Print("_LeaveInPlaying,nPos:%d nUserId:%d",tUser.nSitId,tUser.nUserId)
	assert(not self.isBanStandUpReq)

	self:_CollectBetToPoolsN({tUser.nSitId})		--收归玩家下注到底池
	local nPaiJuProfit =self:_UserChipsSettle(tUser,{},false)			--结算
	local nRmCnt =_removeItem( self.arrPosPartIn,tUser.nSitId,true)
	assert(nRmCnt==1)
	self.tReview:LeaveInPlaying(tUser.nSitId,nPaiJuProfit)		--回顾记录
	
	if self.isGapOfNow or self.isTableError then --正在跳转到下一轮或结算
		self:_ResetUser(tUser)
		return
	end

	--如果玩家当前获得了操作权或即将获得操作权, 则需要结束其操作权
	if tUser.nStatus ==UserStatus.nThinking or tUser.isToGainRights then
		self:_SetUserStatus(tUser,UserStatus.nFold)
		self:_OpEnd(tUser.nSitId)
	elseif tUser.nStatus ~= UserStatus.nFold then
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
		self:ClubTableInfoNotify({sitId=nUserID})
	end
	self.nUserCnt =self.nUserCnt +nIncrValue
	if not isAndroid then
		self.nUserCntOfReal=self.nUserCntOfReal +nIncrValue
	else
		self.nAndroidCnt =self.nAndroidCnt +nIncrValue
	end
	if self.nClubId then
		local tTableInfo ={}
		tTableInfo.nNowCnt =self.nUserCnt
		self:ClubTableInfoNotify(tTableInfo)
	end
	tPubUser.UpdateTableUserCnt(self.sTableId,self.nAndroidCnt,self.nUserCntOfReal)
end

function Table:ClubTableInfoNotify(tTableInfo)
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
	
	self:Print("_SetSitInSeat nPos:%d nUserId:%d nUserCnt:%d nBalance:%s",nPos,tUser.nUserId,self.nUserCnt,tostring(tUser.nBalance))
	self.tUserNameToIsUsed[tUser.sName]= true
end


function Table:_SetLeaveSeat(nSitId,isChangTable)
	local tUser =self.arrUsers[nSitId]
	assert(tUser~=nil,'Err happen')
	self.tInterFace.SendToMatchServ(self.nEventId,"UnBind",{nUserId=tUser.nUserId,sTableId=self.sTableId})

	self:_StopForceTimer(tUser)
	self.tTableOverview:StandUp(tUser.nUserId)
	if tUser.isAndroid then
		self.tTableOverview:UserLeave(tUser.nUserId)
	end
	
	--是否游戏中途退出(需收归下注、结束操作权等)
	if tUser.isNeedSettle and self:_IsPartInUser(nSitId) then	
		self:_LeaveInPlaying(tUser)
	end
	tPubUser.SetUserSeatStatus(tUser.nUserId,false)
	self.arrUsers[nSitId] =nil
	self.tUserIdToPos[tUser.nUserId] =nil
	self:_RetainCountDownCancel(tUser)

	self:_IncrUserCountBy(-1,tUser.isAndroid,tUser.nUserId)
	
	self.tUserNameToIsUsed[tUser.sName]= nil
	self:_SaveLatelyBalance(tUser.nUserId,tUser.nBalance,tUser.isAndroid)
	self:_ResetUser(tUser)
	self:_UserBalanceToGold(tUser)
	--self:TaxByTableRateSettle(tUser.nUserId)

	tPubUser.IncrUnbalancedBy(tUser.nUserId,-1)
	self.tInterFace._LeaveTable(tUser.nUserId,self,isChangTable)

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

--机器人进入桌子时带入随机筹码数量
function Table:RandomTakeInForAndroid()
	return math.random(self.nBuyMin,self.nBuyMax)
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
