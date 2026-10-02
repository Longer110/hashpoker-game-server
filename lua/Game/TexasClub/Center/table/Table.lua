local tBase            = require("base") -- 基础功能接口
local Define           = require("Define")
local RecordDbr        = require("RecordDbr")
local tPubUser         = require("PublicUserInfo") -- 用户信息

local taxHelp          = require("TaxHelp")        -- 局抽水工具
local tPenaltyManager  = require("PenaltyManager") -- 用户罚款数据
-- local tConfig =require("GameConfig") --
local tTimerAux        = require("TimerAux")
local cjson            = require("cjson")
local tPublicRedis     = require("PublicRedis")
local tAlg             = require("GameAlg")
local publicApi        = require("publicApi")
local tSlaveManager    = require("SlaveManage")
local tPublicClub      = require("PublicClub")
local Review           = require("Review")
local json             = require("json")
local tOverview        = require("Overview")
local Statistic        = require("Statistic")
local PublicDefine     = require("PublicDefine")
local tRedisCahche     = require("RedisCahche")
local tTaxGather       = require("TaxGather")
local tStack           = require("Stack")
local tgBotMessage     = require("TgBotMessage")
local HashHelper       = require("HashHelper")
local tRedisdefine     = require("redisdefine")
local tPublicUserGold  = require("PublicUserGold")
local BaseSink         = require("BaseSink")
local tPublicUserGold  = require("PublicUserGold")

local GlobalConfigKey  = tRedisdefine.GlobalConfigKey
local CostName         = tRedisdefine.CostName
local MsgCode          = PublicDefine.MsgCode
local TableState       = PublicDefine.TableState
local UserStatus       = PublicDefine.UserStatus
local UserOp           = PublicDefine.UserOp
local RoomType         = PublicDefine.RoomType
local TableCloseReason = Define.TableCloseReason
local InsureMode       = Define.InsureMode
local GoldCReason      = PublicDefine.GoldCReason
local tLeaveTableType  = PublicDefine.LeaveTableType

local function appendArray2(dest, src)
	local destLength = #dest
	for i = 1, #src do
		dest[destLength + i] = src[i]
	end
	return dest
end

local function _CopyArr(arr)
	local cp = {}
	for _, v in ipairs(arr) do
		cp[#cp + 1] = v
	end
	return cp
end
local function _IsHaveEle(arr, ele)
	for _, v in ipairs(arr) do
		if v == ele then return true end
	end
	return false
end
local function isCardValue(nCard)
	local nPoint = nCard % 16          -- 计算牌点
	local nHuaSe = math.floor(nCard / 16) -- 使用 math.floor 来代替整除操作符
	return (nPoint >= 1 and nPoint <= 13) and (nHuaSe >= 1 and nHuaSe <= 4)
end
local function _removeItem(list, item, isRemoveAll)
	local rmCount = 0
	for i = 1, #list do
		if list[i - rmCount] == item then
			table.remove(list, i - rmCount)
			if not isRemoveAll then
				return 1
			end
			rmCount = rmCount + 1
		end
	end
	return rmCount
end
local function _PoolPosMerge(arrPosFormA, arrPosFormB)
	local tTem = {}
	for _, nPos in ipairs(arrPosFormA) do
		tTem[nPos] = true
	end
	for _, nPos in ipairs(arrPosFormB) do
		tTem[nPos] = true
	end
	local arr = {}
	for nPos, _ in pairs(tTem) do
		table.insert(arr, nPos)
	end
	return arr
end
local function _PoolFormMerge(tUserIdToPoolFormA, tUserIdToPoolFormB)
	local tNew = {}
	for nUserId, nPoolForm in pairs(tUserIdToPoolFormA) do
		tNew[nUserId] = nPoolForm
	end
	for nUserId, nPoolForm in pairs(tUserIdToPoolFormB) do
		tNew[nUserId] = tNew[nUserId] or 0
		tNew[nUserId] = tNew[nUserId] + nPoolForm
	end
	return tNew
end

local function _CutOff(arr, nRemainCnt)
	local tS = tStack:New()
	while (#arr > nRemainCnt) do
		local tItem = table.remove(arr)
		tS:Push(tItem)
	end
	return tS
end

--判断两个整数数组是否相等
local function _isNumArrEqual(arrA, arrB)
	if #arrA ~= #arrB then
		return false
	end
	local tem = {}
	for _, v in ipairs(arrA) do
		tem[v] = true
	end
	for _, v in ipairs(arrB) do
		if not tem[v] then
			return false
		end
	end
	return true
end

local function roundToDecimal(num, decimals)
	local mult = 10 ^ (decimals or 1)
	return math.floor(num * mult + 0.5) / mult
end

local sin = math.sin
local cos = math.cos
local rad = math.rad
local acos = math.acos
local asin = math.asin
local sqrt = math.sqrt
local pow = math.pow

--返回gps两点距离 (单位:km)
local function GetDistance(lng1, lat1, lng2, lat2)
	local R = 6371.004 --单位 km
	local radLat1 = rad(lat1)
	local radLat2 = rad(lat2)
	local a = radLat1 - radLat2
	local b = rad(lng1) - rad(lng2)
	local s = 2 * asin(sqrt(pow(sin(a / 2), 2) +
		cos(radLat1) * cos(radLat2) * pow(sin(b / 2), 2)))
	s = s * R
	s = math.floor(s * 10000 + 0.5) / 10000;
	return s; --单位 km
end

--浮点数判断
-- 是否小于
local function LessThan(a, b)
	return (a < b and math.abs(a - b) > 1e-6)
end
-- 是否大于
local function GreaterThan(a, b)
	return (a > b and math.abs(a - b) > 1e-6)
end
-- 是否小于等于
local function LessOrEqual(a, b)
	return (not GreaterThan(a, b))
end
-- 是否大于等于
local function GreaterOrEqual(a, b)
	return (not LessThan(a, b))
end
-- 是否等于
local function Equal(a, b)
	return (math.abs(a - b) < 1e-6)
end


local Table = {}


--use
function Table:New(sTableId, tInterFace, tConfig)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	assert(tConfig ~= nil)

	--桌子基本信息
	t.sTableId = sTableId or "" --table id
	t.tInterFace = tInterFace --Game层接口 (Game =>table =>user)	
	t.sTableName = tConfig.sTableName
	t.nGroupId = tConfig.nGroupId
	t.nRoomId = tConfig.nRoomId
	t.nLiveUserID = tConfig.nLiveUserID --主播ID
	t.nTableType = tConfig.nTableType --桌子类型
	t.sLiveID = tConfig.sLiveID

	--德州配置信息
	local tJsonConfig = tConfig.tJsonConfig
	t.sClubName = tJsonConfig.sClubName or "unknown"
	t.isRobotBan = (tJsonConfig.isNeedAndroid == false) --是否禁止机器人进入
	t.nSmallBlind = tJsonConfig.nSmallBlind          --小盲注数额
	t.nBigBlind = tJsonConfig.nBigBlind              --大盲注数额(通常等于:小盲注x2)
	t.nZhuaTou = tJsonConfig.nZhuaTou or 0           --抓头数额
	t.nForceBlind = tJsonConfig.nBigBlind * 2        --强盲数额
	t.nCapacity = tJsonConfig.nCapacity              --能供玩游戏的座位数
	t.nIntervalLev = tJsonConfig.nIntervalLev or 2   --牌局间隔 1:短暂 2:适中 3:漫长
	t.nClubId = tJsonConfig.nClubId                  --俱乐部id (俱乐部房配置,否时为nil)
	t.nItemId = tJsonConfig.nItemId or 1             --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	t.nKeepTime = tJsonConfig.nKeepTime              --房间时长(秒) (俱乐部房配置,否时为nil)
	t.isVideoFee = tJsonConfig.isVideoFee or false
	t.nVideoFee = tJsonConfig.nVideoFee or 0

	t.nGoldType = tJsonConfig.nGoldType                        -- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)
	t.nBuyMin = tJsonConfig.nMinTabkeInBB * tJsonConfig.nBigBlind --最小买入
	t.nBuyMax = tJsonConfig.nMaxTabkeInBB * tJsonConfig.nBigBlind --最大买入
	t.nTakeIn = tJsonConfig.nTakeIn                            --默认带入
	t.nFee = 0                                                 --tJsonConfig.nFee					--手续费 (已无用)
	t.nTax = 0                                                 --tJsonConfig.nTax					--抽水 (百分比) (已无用)
	t.isTabkeOut = tJsonConfig.isTabkeOut or false             --是否开启带出功能 true:是 false:否
	t.nTabkeOutOdd = tJsonConfig.nTabkeOutOdd or 1             --撤码阈值的倍数N(仅在开启撤码功能时有效)
	t.nTakeInLimit = tJsonConfig.nTakeInLimit or 0             --补码限制 不能超过此值

	t.nPlayerCntAtLeast = tJsonConfig.tAutostart.nPlayerCnt or 2 --至少几人牌局才能开始(nil或<2表示无效)
	t.nPreAnte = tJsonConfig.nPreAnte                          --前注（0表示没前注)
	t.preAnteOdd = tJsonConfig.preAnteOdd or 0
	t.isForceBlind = tJsonConfig.isForceBlind                  --强制盲注 true:开启 false:关闭
	t.nPoolEntryRate = tJsonConfig.nPoolEntryRate              --入池率 0%~100%，95%就是95 (低于300手玩家不限制)
	t.nPoolEntryRateHands = tJsonConfig.nPoolEntryRateHands or 0 --入池率多少手不限制
	t.nPoolHands = tJsonConfig.nPoolHands or 0                 --手数限制
	t.isOnlyPlayByIOS = tJsonConfig.isOnlyPlayByIOS            --true:只能IOS设备玩 fasle:所有设备都能玩
	t.isGPSLimit = tJsonConfig.isGPSLimit                      --GPS限制 禁止地理位置接近的玩家同时在一张桌子上进行牌局  true:开启 false:关闭
	t.isIPLimit = tJsonConfig.isIPLimit                        --IP限制 禁止相同IP地址的玩家同时在一张桌子上进行牌局  true:开启 false:关闭
	t.isAOF = tJsonConfig.isAOF                                --是否只有AllIn和弃牌 true:是 false:否
	t.isDelayLook = tJsonConfig.isDelayLook                    --延迟看牌 true:开启 false:关闭
	t.nInsureMode = tJsonConfig.nInsureMode                    --保险模式 0:无保险 1:传统保险 2:低水保险
	t.nInsureNormalType = 2                                    --传统保险时的保险类型;1:传统一,2传统二  (分别模仿不同的app)
	t.nTsureType = 1                                           --保险类型 1 全部 2 单个
	t.nEnterMin = tJsonConfig.nBigBlind + tJsonConfig.nPreAnte --最小进入(玩家必须满足最小进入才能开始游戏)
	if tJsonConfig.isForceBlind then
		t.nEnterMin = t.nForceBlind + tJsonConfig.nPreAnte
	end
	t.nEnterMin = math.max(t.nEnterMin, t.nBuyMin)
	t.nLoseMaxAmount = tJsonConfig.nLoseMaxAmount or 0                    --输钱限制数额

	t.nGameId = tJsonConfig.nGameId                                       --游戏Id
	t.nStartAtLeast = t.nPlayerCntAtLeast or 2                            --实际使用的开始人数(动态值)
	t.nRoomType = t.nClubId < 1000000 and RoomType.nLobby or RoomType.nClub --房间类型(俱乐部id小于1000000的是大厅桌子)
	t.nHoleCardCnt = (t.nGameId == Define.nGameId_Ahm) and 4 or 2         --底牌数量(奥哈马玩法为4,底牌数量为4同样也视为奥哈马)
	t.nClubIdOfCorrect = (t.nRoomType == RoomType.nLobby) and 0 or t.nClubId --经过校正后的ClubId (大厅统一用0表示)

	--服务费收取配置
	local tDrawWaterMode = tJsonConfig.tDrawWaterMode
	t.tConfitOfTax = {
		nModeType = tDrawWaterMode.nModeType,               --1:按比例  2:按固定 3:按牌桌 0:不收取
		--按比例收取配置
		isProfitOrPool = (tDrawWaterMode.nComputeMode == 1), --true:按盈利比例 false:按底池比例 x
		nRate = (tDrawWaterMode.nTaxRate / 100),            --服务费比例
		nCap = tDrawWaterMode.nTopLimitBB,                  --封顶nCap倍大盲
		isFreeWhenPreFlop = tDrawWaterMode.isFreeBeforeFlop, --翻牌前,免服务费
		isHalfWhenFewUser = tDrawWaterMode.isHalf,          --低于3人服务费5折
		nFreeWhenLowProfit = tDrawWaterMode.tFreeConfig.nLimitBB, --盈利低于nFreeWhenLowProfit倍大盲,免服务费
		--按固定收取配置
		isProfitOrPoolF = (tDrawWaterMode.nComputeMode == 1), --true:按盈利分界 false:按底池分界 x
		nMiddleValue = tDrawWaterMode.nCutoffValue,         --分界值
		nValueWhenLess = tDrawWaterMode.nLessValue,         --少于分界值收取
		nValueWhenGreate = tDrawWaterMode.nGreaterValue,    --大于等于分界值收取
		--按牌桌
		nTaxRate = (tDrawWaterMode.nTaxRate / 100),         --
	}

	t.isTableStart = false --牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	t.isAutoNext = true --下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始
	if (t.nLiveUserID and t.nLiveUserID > 0) and t.nRoomType == RoomType.nClub then
		t.isTableStart = false
		if t.nPlayerCntAtLeast == nil or t.nPlayerCntAtLeast < 2 then
			t.isAutoNext = false
		end
	end

	t.nOpentime = os.time()                                   --桌子创建时间戳
	--主播可选的房间配置
	t.tDeZhouConfigOption = { arrCapacity = {}, arrConfig = {} } --(已无用)
	--本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	t.isConfigNotSet = false                                  --(已无用)					 	

	t.arrPreSetCommCard = {}                                  --预设置的公共牌
	t.arrPreSetCommCardEffect = {}                            --正在生效使用的预设置公共牌
	t.nOperateTime = 15                                       --操作最大时间,单位:秒 (通常为10)
	t.nJuShu = 0                                              --当前局数
	t.nBankerPos = nil                                        --庄家位置
	t.arrUsers = {}                                           --本桌子用户
	t.tUserIdToPos = {}
	t.Timer = tTimerAux:New()
	t.TimerForAndroid = tTimerAux:New()
	t.TimerForAndroidEnter = tTimerAux:New() --用于控制机器人进桌(勿作它用)
	t.TimerForPause = tTimerAux:New()     --用于桌子暂停计时
	t.TimerForRetain = tTimerAux:New()    --玩家留座计时
	t.TimerForElapWarn = tTimerAux:New()  --时间剩余警告
	t.TimerForOffline = tTimerAux:New()   --离线倒计时

	t.nCloseTableWhenOver = nil           --一局结束后关闭桌子的原因

	t.isTableClose = false                --桌子是否已经关闭(设为true后,桌子不再能发出消息)
	t.nUserCnt = 0                        --本桌子当前玩家数量(包括旁观)
	t.nUserCntOfReal = 0                  --本桌子当前真人玩家数量(包括旁观)
	t.nTimestampZeroRealUser = os.time()  --真人玩家数量减至0时记录的时间

	t.tPile = nil                         --牌
	t.preTPile = nil                      --下局牌
	t.arrCommunityCards = {}              --公共牌
	t.nStage = TableState.nInit           --当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	t.nPotSum = 0                         --底池总额(已押筹码总额)
	t.arrPoolInfo = {}                    --底池,例如:{{arrPosForm={1,2},nPool=100},{arrPosForm={1},nPool=50}}

	t.nPartInCount = 0                    --牌局开始时，参与牌局的玩家数量
	t.arrPosPartIn = {}                   --参与当前牌局的玩家座位号
	t.nTheRightsEndPos = nil              --操作权终止位置(一轮开始时为第一个获得操作权的玩家，接着谁提高了下注值便设置为谁的座位号)
	t.nUserIdLeader = nil                 --ai场景信息的一个辅助变量
	t.nTheHighestBet = 0                  --当前最高下注 (牌局中的玩家,除了弃牌和AllIn的玩家外,一轮结束时，所有人下注都会与该值持平)
	t.nLatelyIncreasesBet = 0             --最近一次的nTheHighestBet增幅 (加注提升nTheHighestBet时,提升幅度需>= Max(1个大盲,最近提升幅度))
	t.nIsRoundBet = false                 --本轮下注是否已经有过下注行为(true:有 false:无)

	t.isBanStandUpReq = false             --游戏中有一些间隙状态, 禁止玩家游戏中站起(现已不会设置为true)

	t.sPaiJuId = ""                       --牌局id

	--牌局详情(存放本局里结算了的玩家信息)
	t.tUsersInfo = {}
	t.tDealCardInfo = {}
	t.tBetInfo = {}
	t.tWinUserInfo = {}

	t.isToStartGame = false                                                  --游戏是否即将开始(设置了定时器)
	t.nTimeStart = 0                                                         -- >0:时间戳(游戏开始) -1:进入了暂停 0:空闲

	t.nRobotBetSum = 0                                                       --当局当前机器人下注总额

	t.isControl = nil                                                        --本局是否尽量控牌 (2或3控机器人赢,4控真人赢)
	t.nControlUserId = nil                                                   --被控玩家id

	t.tUserNameToIsUsed = {}                                                 --本桌子玩家的昵称 (用以判断机器人昵称重复)

	t.ToStartTime = 3                                                        --开局倒计时时间  秒
	t.ToSettleEndTime = 8.5                                                  --结算动画时间  秒

	t.isPause = false                                                        --是否设置了暂停 true:是  false:否
	t.isUseHardAi = false                                                    --是否使用强AI (强机器人能预知输赢)(废弃)
	t.nAiModel = 0                                                           -- 0:放水模式(150倍大盲内，机器人放开下注) 1:自然模式(牌越好注越大) 2:预知输赢模式(真人唬不住机器人) nil:独立随机使用一个模式

	t.isGapOfNow = false                                                     --当前是否正在流程跳转(调用了定时器，即将跳到下一流程)

	t.nLastHeartTickTime = os.time()                                         --游戏开始后，会不时更新该时间 (用来辅助检测是否卡桌了)

	t.isTableError = false                                                   --桌子是否检查到出错了

	t.tUserIdToGoldFlowInfo = {}                                             --记录结算过程中的金币流向(写战绩用)
	t.arrWinLoseRecord = {}                                                  --缓存战绩记录，用于延迟写
	t.arrTaxForUpdate = {}                                                   --缓存需要延迟更新的抽水记录(按牌桌抽水)

	t.tReview = Review:New()                                                 --回顾记录
	t.tTableOverview = tOverview:New()                                       --牌桌总览
	t.tStatistic = Statistic:New()                                           --数据统计
	t.hashHelper = HashHelper:New(t.sTableId, t.nGameId, t.nGroupId, t.nRoomId) --hash信息

	t.tTimeKeeping = { nElapsed = 0, nNewBeginStamp = nil, nPauseStamp = nil }

	t.tFlopAfterInsur = nil --翻牌后保险信息
	t.tTurnAfterInsur = nil --转牌后保险信息

	t.nInsurPool = 0     --保险池

	--表情价格表 (根据配置，其中的值会动态变)
	t.arrChat = { { nChatId = 1, nCost = 10 }, { nChatId = 2, nCost = 10 }, { nChatId = 3, nCost = 10 },
		{ nChatId = 4, nCost = 10 }, { nChatId = 5, nCost = 10 }, { nChatId = 6, nCost = 10 },
		{ nChatId = 7,  nCost = 10 }, { nChatId = 8, nCost = 10 }, { nChatId = 9, nCost = 10 },
		{ nChatId = 10, nCost = 10 }, { nChatId = 11, nCost = 10 } }

	t.arrDelayCost = { 50, 100, 200, 400, 800, 0, 0, 0, 0, 0, 0, 0, 100, 100, 100, 100, 100, 50, 80, 50 } --延时操作花费,第一次0，第二次500,...,nil时禁止延时  (根据配置，其中的值会动态变)
	t.nFeeA = 100                                                                                      --看翻牌费用(根据配置，值会动态变)
	t.nFeeB = 200                                                                                      --看转牌费用(根据配置，值会动态变)
	t.nFeeC = 300                                                                                      --看河牌费用(根据配置，值会动态变)

	--传统保险赔率表
	t.arrOddsList = { 30, 16, 10, 8, 6, 5, 4, 3.5, 3, 2.5, 2.2, 2, 1.8, 1.6 }
	-- {32,16,11,8,6,5,4,3.5,3,2.5,2.2,2,1.8,1.6,1.4,1.2,1,0.8,0.6,0.5}
	t.nMaxAndroidCnt = math.floor(t.nCapacity / 2)            --机器人最大数量
	t.arrCardsOpenForPay = {}                                 --付费看的牌
	self.nCardOpenFee = -1                                    --看牌费用

	t.nContinuedNum = math.floor(tJsonConfig.nContinuedNum or 0) -- 补开桌子数量

	t.tWarnHistory = {}                                       --桌子剩余时间告警记录
	t.tGather = tTaxGather:New()                              --按桌抽水时的一个辅助

	t.tAndroidCfg = { nMin = 1, nMax = 5 }                    --机器人数量配置
	t.nAndroidCnt = 0                                         --当前机器人数量
	t.nDecrAndroidCnt = 0                                     --牌局结束时需要强制减少的机器人数量
	t.nIncrAndroidCnt = 0                                     --需要增加的机器人数量

	t.tUserLatelyBalance = {}                                 --玩家最近的余额记录(仅记录真人)
	t.tUserLossMark = {}                                      --玩家输钱标记
	t.tUsersKickToLobbyWhenOver = {}                          --记录本局结束后,需要踢出到大厅的玩家id

	t.nSlaveUserCnt = 0                                       --真人 旁观数
	t.tOverviewSnapshoot = {}                                 --总览快照
	t.nBackstageRobotAdd = 0                                  --后台动态加减机器人数量

	t.nPlayCnt = 0                                            --桌子手数(发牌次数)
	t.nLatelyStartTime = nil                                  --最近一局的开始时间
	t.tExpUserR = {}                                          --用来记录试玩房玩家最近一次写记录的时间

	t.nFirstPos = nil                                         --一个辅助,不解释

	t.nSeq = 0                                                --机器人ai请求标识
	-- t.isUseAi= (t.nGameId ==Define.nGameId_Normal and t.isAOF==false)	--是否使用ai请求
	t.isUseAi = false
	t.sAiUrl = nil

	t.tOpHistory = {}                                                                                     --玩家各阶段的操作次数(服务于ai场景)
	t.nFirstBet = 0                                                                                       --本局大小盲累计下注总额(服务于ai场景)
	t.arrPreSetCommCardCp = {}                                                                            --公共牌(服务于ai场景)
	t.noticeOpenTimes = 0                                                                                 --开桌通知次数
	t.nUserRank = nil                                                                                     --整个桌子rank
	t.nShouHash = 1                                                                                       --是否公布手牌hash
	t.nIsZhuaTouBet = false                                                                               --是否有抓头下注
	t.nInsureStageEndTime = 0                                                                             --保险阶段结束时间
	t.nInsureStageStartTime = 0                                                                           --保险阶段开始时间
	t.nIsPerson = tJsonConfig.nIsPerson or
	0                                                                                                     --是否私人房间 0否 1是
	t.nIsShow = tJsonConfig.nIsShow or
	1                                                                                                     --是否显示房间 0否 1是
	t.sPassWord = tJsonConfig.sPassWord or
	""                                                                                                    --私人房间密码 默认 ""
	t.nTableCost = tJsonConfig.nTableCost or
		{ { nId = 1, open = 0, nCost = 0 }, { nId = 2, open = 0, nCost = 0 }, { nId = 3, open = 0, nCost = 0 } } --个人开放消耗配置 [{nId = 1, open = 0, nCost = 10},{nId = 2, open = 0, nCost = 10},{nId = 3, open = 0, nCost = 10}]  付费看公牌1 付费看手牌2 付费切牌3
	t.nCutIndex = 0
	t.nSettleEndTime = 0                                                                                  --结算结束时间
	t.nCutUserInfo = {}
	t.nInsurePlayers = {}

	-- 离桌限制, 限制玩家赢钱达到阈值时,需要打满指定局数才能自由离桌,否则会罚款
	-- like {
	-- 	isOpen = true, 是否开启离桌限制功能
	--	nWinThreshold = 1000,  达到离桌限制处罚的盈利金额阈值
	--	nLots = 10,  解除离桌限制需要的手数阈值
	--	nPenaltyRatio = 0.5, -- 离桌处罚金额比例,按玩家盈利计算
	--	nUserRatio = 0.5 -- 处罚时其他在座位上的玩家分配的处罚金额比例
	--  nType = 0 -- 0: 返回大厅时触发处罚 1: 站起时触发处罚
	--}
	t.tLeaveTableConfig = tJsonConfig.tLeaveTableConfig or {}

	-- 保存玩家抽水值
	-- 存储用户抽水的映射表 {userId = {tax = nChouShui, tableId = sTableId}}
	t.tUserIdToTax = {}
	return t
end

function Table:GetAiReqSeq()
	self.nSeq = self.nSeq + 1
	return self.nSeq
end

function Table:_UpdateAiUrl()
	self.sAiUrl = PublicRedis.GetAiUrl(self.nGroupId)
end

function Table:_GetLateSum(nUserId)
	local ret = self:_GetLatelyBalance(nUserId)
	return ret.nBalance + ret.nTempChips
end

function Table:_GetLatelyBalance(nUserId)
	local ret = self.tUserLatelyBalance[nUserId] or {}
	if next(ret) then
		-- if ret.nBalance < self.nBuyMin then
		-- 	return self.nBuyMin
		-- end
		return ret
	end
	return { nBalance = 0, nTempChips = 0 }
end

-- 防止余额为0不覆盖
function Table:_SaveLatelyBalance(nUserId, nBalance, nTempChips, isAndroid)
	if isAndroid then
		return
	end
	if self.tUserLatelyBalance[nUserId] then
		self.tUserLatelyBalance[nUserId] = { nBalance = nBalance, nTempChips = nTempChips }
	elseif nBalance > 0 then
		self.tUserLatelyBalance[nUserId] = { nBalance = nBalance, nTempChips = nTempChips }
	end
end

function Table:_GettUserLossMark(nUserId)
	return self.tUserLossMark[nUserId]
end

function Table:_SavetUserLossMark(nUserId, isAndroid)
	if not isAndroid then
		self.tUserLossMark[nUserId] = true
	end
end

function Table:_GetTableConfig()
	local tem = {}
	tem.sTableName = self.sTableName        --房间名称,不带<>符号
	tem.sPaiJuId = self.sPaiJuId            --牌局编号
	tem.sClubName = self.sClubName          --俱乐部名称,不带[]符号
	tem.nSmallBlind = self.nSmallBlind      --小盲
	tem.nBigBlind = self.nBigBlind          --大盲
	tem.nZhuaTou = self.nZhuaTou            --抓头
	tem.isForceBlind = self.isForceBlind    --是否强制盲注 true:是 false:否
	tem.isOnlyPlayByIOS = self.isOnlyPlayByIOS --是否仅限IOS玩 true:是 fasle:否
	tem.isGPSLimit = self.isGPSLimit        --是否开启GPS限制 true:是 fasle:否
	tem.isIPLimit = self.isIPLimit          --是否开启ip地址限制 true:是 fasle:否
	tem.nPoolEntryRate = self.nPoolEntryRate --入池率限制,取值范围0~100; 0: 表示不限制
	tem.isDelayLook = self.isDelayLook      --是否延迟看牌 true:是 fasle:否
	tem.nInsureMode = self.nInsureMode      --保险模式 0:无保险 1:传统保险 2:低水保险
	tem.nPreAnte = self.nPreAnte            --前注
	tem.isAOF = self.isAOF                  --是否仅限AllIn和弃牌 true:是 其它:否
	tem.nPlayerAtLeast = self.nPlayerCntAtLeast
	if tem.nPlayerAtLeast == nil or tem.nPlayerAtLeast < 2 then
		tem.nPlayerAtLeast = 10
	end
	tem.isTabkeOut = self.isTabkeOut       --是否允许带出
	tem.nTabkeOutOdd = self.nTabkeOutOdd   --撤码阈值的倍数N
	tem.nInsureNType = self.nInsureNormalType --传统保险时的保险类型; 1:传统一,2传统二(xpoker),其它值:当1处理
	tem.arrOdds = self.arrOddsList         --传统保险,outs赔率表;首元素为outs-1赔率，次之
	tem.nBuyMin = self.nBuyMin
	tem.nBuyMax = self.nBuyMax             --最高带入
	tem.nIsPerson = self.nIsPerson         --是否私人房间 0否 1是
	tem.nIsShow = self.nIsShow             --是否显示房间 0否 1是
	tem.sPassWord = self.sPassWord         --私人房间密码 默认 ""
	tem.nTableCost = self.nTableCost
	tem.isVideoFee = self.isVideoFee
	tem.nPoolHands = self.nPoolHands
	tem.nVideoFee = self.nVideoFee
	tem.nLoseMaxAmount = self.nLoseMaxAmount
	tem.nTakeInLimit = self.nTakeInLimit
	tem.nPoolEntryRateHands = self.nPoolEntryRateHands
	tem.tLeaveTableConfig = self.tLeaveTableConfig
	return tem
end

local order = { 3, 2, 10, 6, 7, 8, 1, 5, 4, 11, 9 }

local function sortChat(arrChat)
	local ret = {}
	local lookup = {}
	for _, item in ipairs(arrChat) do
		lookup[item.nChatId] = item
	end
	for _, id in ipairs(order) do
		if lookup[id] then
			table.insert(ret, lookup[id])
		end
	end
	return ret
end

function Table:_UpdatePriceList(isUpdateChat)
	local tem = tRedisCahche.GetClubChangeConfig(self.nGroupId)
	local arrChat = tem.arrChatChangeCfg or {}
	local arrElse = tem.arrTableChangeCfg or {}

	local tChatIdToPrice = {}
	for _, v in ipairs(arrChat) do
		tChatIdToPrice[v.nChatId] = v.nCost
	end

	local tElseIdToPrice = {}
	for _, v in ipairs(arrElse) do
		tElseIdToPrice[v.nId] = v.nCost
	end

	--更新价格
	if isUpdateChat then
		self.arrChat = sortChat(arrChat)
		-- for _,v in ipairs(self.arrChat) do
		-- 	v.nCost = tChatIdToPrice[v.nChatId] or v.nCost
		-- end
	end

	self.nFeeA = tElseIdToPrice[10] or self.nFeeA --看翻牌费用(根据配置会动态变)
	self.nFeeB = tElseIdToPrice[11] or self.nFeeB --看转牌费用(根据配置会动态变)
	self.nFeeC = tElseIdToPrice[12] or self.nFeeC --看河牌费用(根据配置会动态变)

	self.arrDelayCost[1] = tElseIdToPrice[1] or self.arrDelayCost[1]
	self.arrDelayCost[2] = tElseIdToPrice[2] or self.arrDelayCost[2]
	self.arrDelayCost[3] = tElseIdToPrice[3] or self.arrDelayCost[3]
	self.arrDelayCost[4] = tElseIdToPrice[4] or self.arrDelayCost[4]
	self.arrDelayCost[5] = tElseIdToPrice[5] or self.arrDelayCost[5]

	self.arrDelayCost[13] = tElseIdToPrice[13] or self.arrDelayCost[13]
	self.arrDelayCost[14] = tElseIdToPrice[14] or self.arrDelayCost[14]
	self.arrDelayCost[15] = tElseIdToPrice[15] or self.arrDelayCost[15]
	self.arrDelayCost[16] = tElseIdToPrice[16] or self.arrDelayCost[16]
	self.arrDelayCost[17] = tElseIdToPrice[17] or self.arrDelayCost[17]
	self.arrDelayCost[18] = tElseIdToPrice[18] or self.arrDelayCost[18]
	self.arrDelayCost[19] = tElseIdToPrice[19] or self.arrDelayCost[19]
	self.arrDelayCost[20] = tElseIdToPrice[20] or self.arrDelayCost[20]
end

--[{nId = 1, nCost = 10},{nId = 2, nCost = 10},{nId = 3, nCost = 10}]  付费看公牌1 付费看手牌2 付费切牌3
-- 18 看手牌 19 付费切牌 20 看公牌
function Table:_GetCardCost(count)
	local conf = self.nTableCost[count]
	if not conf then
		return { open = 0, nCost = 0 }
	end
	return conf
end

-- 获取保险延时花费
function Table:_GetInsureDelayCost(count)
	local nId = 13
	if count >= 4 then
		count = 4
	end
	nId = nId + count
	local nCost = self.arrDelayCost[nId]
	tBase.Log("arrDelayCost nId:%d nCost:%d", nId, nCost)
	tBase.LogT("arrDelayCost", self.arrDelayCost)
	return nCost
end

function Table:Init()
	self:_UpdatePriceList(true)
	self:TryLetAndroidEnter(1) --定时检查桌子是否需要加入机器人,是则加入
	self:TableCheck()         --定时检查真人进入情况,桌子过久没真人则自动关闭
	self:_UpdateAndroidCntCfg(1) --定时更新机器人数量限制配置
	self.nOperateTime = RedisCahche.GetClubConfigOperateTime(self.nGroupId)
	-- if self.isTableStart then
	--	self:BeginTiming(true)
	--end

	--常规保险配置
	local t = RedisCahche.GetInsuerNormalCfg(self.nGroupId)
	local isSuccee, arrRlt = pcall(cjson.decode, t.arrOddsList or "[]")
	if isSuccee and #arrRlt > 0 then
		self.arrOddsList = arrRlt
	end
	if t.nInsureNormalType then
		self.nInsureNormalType = t.nInsureNormalType
	end
	self:Print("GetInsuerNormalCfg:%s", cjson.encode(t))
end

function Table:CalTax(nProfit, nUserId, isAndroid, arrGoldGet)
	if self.tConfitOfTax.nModeType == 1 then
		return self:TaxByRate(nProfit, arrGoldGet, nUserId)
	elseif self.tConfitOfTax.nModeType == 2 then
		return self:TaxByFixed(nProfit)
	elseif self.tConfitOfTax.nModeType == 3 and (not isAndroid) then                  --该模式的抽水，延迟至站起时才收
		local sTaxTag = self.tGather:Gather(nProfit, nUserId, self.sPaiJuId, self.sTableId) --不记录机器人的抽水
		return 0, sTaxTag
	end
	return 0
end

-- 是不是局抽水模式
function Table:IsTotalRake()
	return self.tConfitOfTax.nModeType == 3
end

function Table:TaxByFixed(nProfit)
	if LessOrEqual(nProfit, 0) then
		return 0
	end
	local nBody = nProfit
	if not self.tConfitOfTax.isProfitOrPoolF then
		nBody = self:_GetValPoolSum()
	end
	--计算服务费
	local nTax = nil
	if LessThan(nBody, self.tConfitOfTax.nMiddleValue) then
		nTax = self.tConfitOfTax.nValueWhenLess
	else
		nTax = self.tConfitOfTax.nValueWhenGreate
	end
	--服务费不能大于盈利
	nTax = math.min(nTax, nProfit)
	--保留两位小数返回
	nTax = publicApi.Ceil_n(nTax, 1)
	if math.modf(nTax * 10) >= math.modf(nProfit * 10) then
		self:Print("TaxByFixed nTax>=nProfit nTax:%.2f nProfit:%.2f", nTax, nProfit)
		return 0
	else
		self:Print("TaxByFixed nTax:<nProfit nTax:%.2f nProfit:%.2f", nTax, nProfit)
		return nTax
	end
end

--按比例收取服务费
function Table:TaxByRate_old(nProfit, arrGoldGet)
	if LessOrEqual(nProfit, 0) then
		return 0
	end
	--翻牌前免服务费
	if self.tConfitOfTax.isFreeWhenPreFlop then
		if #self.arrCommunityCards == 0 then
			return 0
		end
	end
	--盈利过低免服务费 改成底池数
	local nPoll = self:_GetValPoolSum()
	local nLow = self.nBigBlind * self.tConfitOfTax.nFreeWhenLowProfit
	if LessThan(nPoll, nLow) then
		return 0
	end
	--计算服务费
	local nBody = nProfit
	local nTax = nBody * self.tConfitOfTax.nRate
	--封顶
	nTax = math.min(nTax, self.nBigBlind * self.tConfitOfTax.nCap)
	--低于3人服务费5折
	-- if self.tConfitOfTax.isHalfWhenFewUser then
	-- 	if self.nPartInCount<3 then
	-- 		nTax =(nTax/2)
	-- 	end
	-- end
	--服务费不能大于盈利
	nTax = math.min(nTax, nProfit)
	--保留两位小数返回
	nTax = publicApi.Ceil_n(nTax, 1)
	return nTax
end

--按比例收取服务费 按分池抽水
function Table:TaxByRate(nProfit, arrGoldGet, nUserId)
	-- if LessOrEqual(nProfit,0) then
	-- 	return 0
	-- end
	--翻牌前免服务费
	if self.tConfitOfTax.isFreeWhenPreFlop then
		if #self.arrCommunityCards == 0 then
			return 0
		end
	end
	local sum = 0
	-- 按分池抽水
	local nLow = self.nBigBlind * self.tConfitOfTax.nFreeWhenLowProfit
	for _, v in pairs(arrGoldGet) do
		--计算服务费
		local pool, bet = self:_GetPoolValue(v.nPotIdFrom, nUserId)
		local nBody = v.nGold - bet
		if nBody > 0 and not LessThan(pool, nLow) then
			local tax = nBody * self.tConfitOfTax.nRate
			--封顶
			tax = publicApi.Ceil_n(math.min(tax, self.nBigBlind * self.tConfitOfTax.nCap), 1)
			sum = sum + tax
		end
	end
	local nTax = sum
	--服务费不能大于盈利
	if nProfit > 0 then
		nTax = math.min(sum, nProfit)
	end
	--保留两位小数返回
	nTax = publicApi.Ceil_n(nTax, 1)
	if math.modf(nTax * 10) >= math.modf(nProfit * 10) then
		self:Print("TaxByRate nTax>=nProfit nTax:%.2f nProfit:%.2f", nTax, nProfit)
		return 0
	else
		self:Print("TaxByRate nTax:<nProfit nTax:%.2f nProfit:%.2f", nTax, nProfit)
		return nTax
	end
end

function Table:_GetPoolValue(pool_id, nUserId)
	for id, v in ipairs(self.arrPoolInfo) do
		if pool_id == id then
			local total = 0
			for userId, bet in pairs(v.tRealUserToPoolForm) do
				if nUserId == userId then
					total = total + bet
				end
			end
			return v.nPool, total
		end
	end
	return 0, 0
end

function Table:_GetValPoolSum()
	local nValPoolSum = 0
	for _, v in ipairs(self.arrPoolInfo) do
		if #v.arrPosForm > 1 then
			nValPoolSum = nValPoolSum + v.nPool
		end
	end
	return nValPoolSum
end

function Table:_GetSumBet()
	local nSumBet = 0
	for _, v in pairs(self.tBetInfo) do
		nSumBet = nSumBet + v.nBet
	end
	return nSumBet
end

--桌子暂停计时
function Table:StopTiming()
	if self.tTimeKeeping.nNewBeginStamp == nil then
		return
	end
	local nNow = os.time()
	self.tTimeKeeping.nElapsed = self.tTimeKeeping.nElapsed + (nNow - self.tTimeKeeping.nNewBeginStamp)
	self.tTimeKeeping.nNewBeginStamp = nil
	self.tTimeKeeping.nPauseStamp = nNow
	self:ClubTableInfoNotify({ nTableStatus = 1 })
	self:_BroadCastToSlaves("ElapStatusUpdate", { nElapsedStatus = 1 })
	self:_ElapWarnReset(true) --停止剩余时间告警定时器
	self:Print("StopTiming,Table_nElapsed:%d", self.tTimeKeeping.nElapsed)
end

--桌子开始或重新开始计时
function Table:BeginTiming(isInit)
	if self.tTimeKeeping.nNewBeginStamp ~= nil then
		return
	end
	self:Print("BeginTiming")
	self.tTimeKeeping.nNewBeginStamp = os.time()
	self.tTimeKeeping.nPauseStamp = nil
	self:_ElapWarnReset(false) --启动剩余时间告警定时器
	if isInit then
		return
	end
	self:ClubTableInfoNotify({ nTableStatus = 0 })
	self:_BroadCastToSlaves("ElapStatusUpdate", { nElapsedStatus = 0 })
end

function Table:_UpdateHeartTick()
	self.nLastHeartTickTime = os.time()
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
	self.isRobotBan = true
end

--桌子当前计时状态  0正常 1暂停
function Table:_ElapsedStatus()
	if self.tTimeKeeping.nNewBeginStamp == nil then
		return 1
	end
	return 0
end

function Table:GetTableInfoForClub()
	local tTableInfo = {}
	tTableInfo.nGameId = self.nGameId
	tTableInfo.sTableName = self.sTableName
	tTableInfo.nItemId = self.nItemId  --使用的金币id
	tTableInfo.nOpentime = self.nOpentime --开桌时间
	tTableInfo.nLiveUserID = self.nLiveUserID
	tTableInfo.nKeepTime = self.nKeepTime
	tTableInfo.nSmallBlind = self.nSmallBlind
	tTableInfo.nBigBlind = self.nBigBlind
	tTableInfo.nZhuaTou = self.nZhuaTou
	tTableInfo.nTakeInMin = self.nBuyMin
	tTableInfo.nTakeInMax = self.nBuyMax
	tTableInfo.nIntervalLev = self.nIntervalLev
	tTableInfo.nCapacity = self.nCapacity
	tTableInfo.nGoldType = self.nGoldType
	tTableInfo.nTableStatus = self:_ElapsedStatus() --0正常 1暂停
	tTableInfo.nStartAtLeast = self.nStartAtLeast

	tTableInfo.isAOF = self.isAOF
	tTableInfo.nInsureMode = self.nInsureMode

	tTableInfo.isForceBlind = self.isForceBlind    --是否强制盲注 true:是 false:否
	tTableInfo.isOnlyPlayByIOS = self.isOnlyPlayByIOS --是否仅限IOS玩 true:是 fasle:否
	tTableInfo.isGPSLimit = self.isGPSLimit        --是否开启GPS限制 true:是 fasle:否
	tTableInfo.isIPLimit = self.isIPLimit          --是否开启ip地址限制 true:是 fasle:否

	tTableInfo.nPreAnte = self.nPreAnte
	tTableInfo.sTableId = self.sTableId
	tTableInfo.nIsPerson = self.nIsPerson --是否私人房间 0否 1是
	tTableInfo.nIsShow = self.nIsShow  --是否显示房间 0否 1是
	tTableInfo.sPassWord = self.sPassWord --私人房间密码 默认 ""
	tTableInfo.isVideoFee = self.isVideoFee

	tTableInfo.tLeaveTableConfig = self.tLeaveTableConfig
	return tTableInfo
end

--是否使用积分结算
function Table:IsUseCredit()
	if self:MatchRoomId() == 0 then --试玩房
		return true
	end
	if self.nGoldType == 3 then --俱乐部房指定使用积分结算
		return true
	end
	return false
end

local function getMaxOdd(arrOddsList)
	return arrOddsList[#arrOddsList] or 1
end

local function geUserPots(arrPoolInfo, nUserId)
	local total = 0
	for _, v in ipairs(arrPoolInfo) do
		for userId, bet in pairs(v.tRealUserToPoolForm) do
			if nUserId == userId then
				total = total + bet
			end
		end
	end
	return total
end

-- 可购买保险状态
--[[
	没有形成底池时：（（小盲+大盲+前注+抓头）+玩家牌桌上的余额*2）/最大outs赔率
	已经形成底池：(底池1+底池n）/最大outs。注：这里的多个底池，只统计玩家自己进入的底池，而非所有底池。
	底池每次有变化时，需要同步刷新盾牌的判定。
]]
function Table:GetUserInsureState(tUser)
	if tUser.nStatus == UserStatus.nFold then
		return
	end
	local nSmallBlind = self.nSmallBlind or 0
	local nBigBlind = self.nBigBlind or 0
	local nPreAnte = self.nPreAnte or 0
	local nZhuaTou = self.nZhuaTou or 0
	local isForceBlind = self.isForceBlind
	if not isForceBlind then
		nZhuaTou = 0
	end
	local gold = self:Get_User_UnLockGold(tUser)
	gold = gold - tUser.nInsureCost
	if gold <= 0 then
		self:Print("GetUserInsureState userId:%d gold 0", tUser.nUserId)
		tUser.nInsureStatus = 1
		return
	end
	if #self.arrPoolInfo == 0 then
		local total = ((nSmallBlind + nBigBlind + nPreAnte + nZhuaTou) + tUser.nBalance * 2) /
			getMaxOdd(self.arrOddsList)
		local state = (gold > total) and 0 or 1
		self:Print("GetUserInsureState arrPoolInfo = 0 userId:%d total:%.2f gold:%.2f state:%d", tUser.nUserId, total,
			gold, state)
		tUser.nInsureStatus = state
	else
		local total = geUserPots(self.arrPoolInfo, tUser.nUserId) / getMaxOdd(self.arrOddsList)
		local state = (gold > total) and 0 or 1
		self:Print("GetUserInsureState arrPoolInfo  userId:%d total:%.2f gold:%.2f state:%d", tUser.nUserId, total, gold,
			state)
		tUser.nInsureStatus = state
	end
end

-- 桌子上金额
function Table:GetUserTableGold(tUser, nUserId, isSettle)
	if not tUser then
		_, tUser = self:_GetSitIdByUserId(nUserId)
	end
	if not tUser then
		self:Print("GetUserTableGold fail,nUserID:%d ", nUserId)
		return 0
	end
	if isSettle then
		self:Print("GetUserTableGold isSettle,nUserID:%d tUser.nCurCost:%.2f  tUser.nGold:%.2f", nUserId, tUser.nCurCost,
			tUser.nGold)
		tUser.nGold = tUser.nGold - tUser.nCurCost
		tUser.nCurCost = 0
	end
	local ret = tUser.nGold - tUser.nLockGoldInTable
	return ret > 0 and ret or 0
end

-- 消耗桌子上金额 返回剩余金额
function Table:CostUserTableGold(tUser, nUserId, cost, isInSure)
	if not tUser then
		_, tUser = self:_GetSitIdByUserId(nUserId)
	end
	if not tUser then
		self:Print("CostUserTableGold fail,nUserID:%d ", nUserId)
		return 0
	end
	if isInSure then
		tUser.nInsureCost = (tUser.nInsureCost or 0) + cost
	end
	tUser.nCurCost = tUser.nCurCost + cost
	return tUser.nGold - tUser.nCurCost
end

-- 获取撤码暂存区
function Table:Get_User_nTempChips(tUser)
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			return self.nBuyMax
		end
		return tUser.nTempChips
	end
	return tUser.nTempChips
end

-- 可撤码值  isNoBase 自动撤码时不算玩家预设值
function Table:Get_User_CanTempChips(tUser, isNoBase)
	local base = self.nBuyMin * self.nTabkeOutOdd
	local nTempS = tUser.nAutoChips
	if isNoBase then
		nTempS = 0
	end
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			return self.nBuyMax
		end
		local val = tUser.nBalance - base - nTempS
		val = val > 0 and val or 0
		return publicApi.DealFloat(val)
	end
	local val = tUser.nBalance - base - nTempS
	val = val > 0 and val or 0
	return publicApi.DealFloat(val)
end

-- 从余额扣除撤码值
function Table:Del_User_CanTempChips(tUser, nGold)
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			return self.nBuyMax
		end
		tUser.nLockGoldInTable = tUser.nLockGoldInTable + nGold
		tUser.nBalance = tUser.nBalance + nGold
		if tUser.nBalance < 0 then
			tUser.nBalance = 0
			self:Print("Del_User_CanTempChips userid:%d nBalance == 0", tUser.nUserId)
		end
		if tUser.nLockGoldInTable < 0 then
			tUser.nLockGoldInTable = 0
			self:Print("Del_User_CanTempChips userid:%d nLockGoldInTable == 0", tUser.nUserId)
		end
		return true
	end
	tUser.nBalance = tUser.nBalance + nGold
	if tUser.nBalance < 0 then
		tUser.nBalance = 0
	end
	return true
end

-- 撤码暂存区调整 isDelChips 是否结束后自动撤码
function Table:Deal_User_CanTempChips(tUser, nGold, isDelChips)
	if Equal(nGold, 0) then
		nGold = 0
	end
	if isDelChips then
		tUser.nAutoChips = 0
	end
	tUser.nTempChips = tUser.nTempChips or 0
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			return true
		end
		tUser.nTempChips = tUser.nTempChips + nGold
		if nGold < 0 then -- 扣除时加入金币
			tUser.nLockGoldInTable = tUser.nLockGoldInTable - nGold
			tUser.nBalance = tUser.nBalance - nGold
			self:Print("Deal_User_CanTempChips userid:%d nGold:%.2f tUser.nLockGoldInTable:%.2f nBalance:%.2f",
				tUser.nUserId, nGold, tUser.nLockGoldInTable, tUser.nBalance)
		end
		if tUser.nTempChips < 0 then
			tUser.nTempChips = 0
		end
		return true
	end
	tUser.nTempChips = tUser.nTempChips + nGold
	if tUser.nTempChips < 0 then
		tUser.nTempChips = 0
	end
	return true
end

-- 金币是否足够
function Table:Is_Gold_Enough(tUser, cost)
	local gold = self:Get_User_UnLockGold(tUser)
	return gold >= cost
end

function Table:Get_User_UnLockGold(tUser)
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			return self.nBuyMax
		end
		return tPubUser.Get_User_UnLockGold(tUser.nUserId, self.nItemId)
	end
	return (tUser.nGold - tUser.nLockGoldInTable)
end

function Table:Gold_Lock(tUser, nGoldToLock, sourceType)
	if Equal(nGoldToLock, 0) then
		nGoldToLock = 0
	end
	local nUserId = tUser.nUserId
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid or tPubUser.Gold_Lock(nUserId, nGoldToLock, self.nItemId) then
			tUser.nLockGoldInTable = tUser.nLockGoldInTable + nGoldToLock
			sourceType = sourceType or PublicDefine.TakeInGoldType.TopUp
			if not tUser.isAndroid and sourceType == PublicDefine.TakeInGoldType.TopUp then -- 非机器人,需要记录买入金额
				RecordDbr.UpdateUserLockGlodRecord(nUserId, self.sTableId, -nGoldToLock)
			end
			return true
		end
		return false
	end
	local nNowUnLockGold = (tUser.nGold - tUser.nLockGoldInTable)
	if (not (nNowUnLockGold < nGoldToLock and math.abs(nNowUnLockGold - nGoldToLock) > 1e-6)) then
		tUser.nLockGoldInTable = tUser.nLockGoldInTable + nGoldToLock
		return true
	end
	return false
end

function Table:Gold_ChangeAndReLock(tUser, nChange, nSourceType, nRoomId, nTempChips)
	local nUserId = tUser.nUserId
	nTempChips = nTempChips or 0
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			tUser.nLockGoldInTable = tUser.nLockGoldInTable + nChange
			return true, nChange
		end
		local isSucc, _, nAcChange = tPubUser.Gold_ChangeAndReLock(nUserId, tUser.nLockGoldInTable + nTempChips, nChange,
			nSourceType, nRoomId, self.nItemId, self.sTableId, self.sPaiJuId, true)
		if isSucc then
			tUser.nLockGoldInTable = tUser.nLockGoldInTable + (nAcChange or nChange)
			return true, (nAcChange or nChange)
		end
		return false
	end
	tUser.nGold = tUser.nGold + nChange
	tUser.nLockGoldInTable = tUser.nLockGoldInTable + nChange
	return true, nChange
end

-- 修改外部金币未锁定的
function Table:Gold_Change(tUser, nChange, nSourceType, nRoomId)
	local nUserId = tUser.nUserId
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid then
			tUser.nGold = tUser.nGold + nChange
			return true, nChange
		end
		local exData = { sTableId = self.sTableId, sPaiJuId = self.sPaiJuId }
		local isSucc, nAcChange = tPubUser.Gold_Change(nUserId, nChange, nSourceType, nRoomId, self.nItemId,
			self.sTableId, self.sPaiJuId, exData, true)
		if isSucc then
			return true, (nAcChange or nChange)
		end
		return false
	end
	tUser.nGold = tUser.nGold + nChange
	return true, nChange
end

function Table:Gold_UnLockAll(tUser)
	local nTempChips = tUser.nTempChips or 0
	if nTempChips <= 0 then
		nTempChips = 0
	end
	if Equal(tUser.nLockGoldInTable, 0) and Equal(nTempChips, 0) then
		return true
	end
	local nUserId = tUser.nUserId
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid or tPubUser.Gold_UnLock(nUserId, tUser.nLockGoldInTable + nTempChips, self.nItemId, true) then
			tUser.nLockGoldInTable = 0
			tUser.nTempChips = 0
			return true
		end
		return false
	end
	tUser.nLockGoldInTable = 0
	return true
end

function Table:Gold_UnLock(tUser, nToUnLock)
	nToUnLock = math.max(nToUnLock, 0)
	if GreaterThan(nToUnLock, tUser.nLockGoldInTable) then
		return false
	end
	local nUserId = tUser.nUserId
	if not self:IsUseCredit() then --非积分结算房
		if tUser.isAndroid or tPubUser.Gold_UnLock(nUserId, nToUnLock, self.nItemId) then
			tUser.nLockGoldInTable = tUser.nLockGoldInTable - nToUnLock
			return true
		end
		return false
	end
	tUser.nLockGoldInTable = tUser.nLockGoldInTable - nToUnLock
	return true
end

function Table:TaxByTableRateSettle(nUserId, isAndroid)
	local nTax, sTaxTag, sLatelyPaiJuId, sLatelyTableId = self.tGather:Settle(nUserId, self.tConfitOfTax.nTaxRate)
	if self:IsUseCredit() then --积分结算房
		return
	end
	if nTax == nil then
		return
	end
	if nTax <= 0 then
		return
	end
	local resTax = nTax
	nTax = publicApi.Ceil_n(nTax, 1)
	local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nTableTax
	local isSuccee = tPubUser.ChangeUserTreasure({
		nUserID = nUserId,
		nItemID = self.nItemId,
		nDel = -nTax,
		nSourceType = nSourceType,
		sTableId = sLatelyTableId,
		sPaiJuId = sLatelyPaiJuId
	})
	if not isSuccee then
		self:Print("TaxByTableRateSettle fail,nUserID:%d,nTax:%.2f,sTaxTag:%s", nUserId, nTax, sTaxTag)
		return
	end
	self:Print("TaxByTableRateSettle,nUserID:%d,resTax:%.3f,nTax:%.2f,sTaxTag:%s,nTaxRate:%.2f", nUserId, resTax, nTax,
		sTaxTag, self.tConfitOfTax.nTaxRate)
	self:WriteRecordForTax(nUserId, nTax, sTaxTag, sLatelyPaiJuId, isAndroid)
end

function Table:TaxByTableRateSettle_new(nUserId, nTax, lastPaijuId)
	local tData = {}
	tData.nClubId = self.nClubId --俱乐部id
	tData.sTableId = self.sTableId --牌桌id
	tData.nItemId = self.nItemId --道具id
	tData.nGameType = self.nGameId --游戏id
	tData.nGameId = self.nGameId --游戏id
	tData.nUserId = nUserId     --玩家id
	tData.nDrawWater = nTax     --抽水
	tData.sPaiJuId = lastPaijuId --牌局id
	tData.nClubIdOfCorrect = self.nClubIdOfCorrect
	tData.nGroupId = self.nGroupId
	tData.nSession = self.nRoomId
	tData.isAndroid = false
	tData.nBigBlind = self.nBigBlind
	tData.nSmallBlind = self.nSmallBlind
	tData.nPreAnte = self.nPreAnte
	tData.nZhuaTou = self.nZhuaTou
	tData.nGoldType = self.nGoldType
	tData.nPreAnteOdd = self.preAnteOdd
	RecordDbr.Update_WinLoseRecordTaxV2(tData)
	tPublicRedis.TexaStatistic_ProfitAdd(nUserId, -nTax, tData)
end

function Table:TaxByTableRateSettle_All()
	-- local arrUserId =self.tGather:GetAllUserId()
	-- for _,nUserId in ipairs(arrUserId) do
	-- 	self:TaxByTableRateSettle(nUserId,false)
	-- end
	local allUsers = taxHelp:getAllUser(self.sTableId)
	for uid, info in pairs(allUsers) do
		if info.taxed > 0 and info.lastPaijuId ~= "" then
			self:TaxByTableRateSettle_new(uid, info.taxed, info.lastPaijuId)
		end
	end
end

--匹配房场次id. 非匹配房返回nil
function Table:MatchRoomId()
	if self.nTableType == Define.TableType.nMatch then
		return self.nRoomId
	end
end

--间隔时间更新
function Table:_UpdateIntervalTime()
	local ToStartTime, ToSettleEndTime = tPublicRedis.GetDeZhouIntervalTime(self.nGroupId, self.nIntervalLev)
	self:Print("_UpdateIntervalTime nGroupId:%d nIntervalLev:%d ToStartTime:%.1f ToSettleEndTime:%.1f", self.nGroupId,
		self.nIntervalLev, ToStartTime, ToSettleEndTime)
	if ToStartTime >= 1 and ToSettleEndTime >= 1 then
		self.ToStartTime = ToStartTime
		self.ToSettleEndTime = ToSettleEndTime
	elseif self.nIntervalLev == 1 then
		self.ToStartTime = 1 --开局倒计时时间  秒
		self.ToSettleEndTime = 5 --结算动画时间  秒
	elseif self.nIntervalLev == 2 then
		self.ToStartTime = 3 --开局倒计时时间  秒
		self.ToSettleEndTime = 7 --结算动画时间  秒
	elseif self.nIntervalLev == 3 then
		self.ToStartTime = 6 --开局倒计时时间  秒
		self.ToSettleEndTime = 7 --结算动画时间  秒
	else
		self.ToStartTime = 3 --开局倒计时时间  秒
		self.ToSettleEndTime = 7 --结算动画时间  秒
	end
	self:Print("nToStartTime is:%.1f nToSettleEndTime is:%.1f", self.ToStartTime, self.ToSettleEndTime)
end

function Table:GetBigBlind()
	return self.nBigBlind
end

function Table:GetPlayerCnt()
	local nCnt = 0
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.nStatus ~= UserStatus.nFold then
			nCnt = nCnt + 1
		end
	end
	return nCnt
end

--初始化机器人强度
function Table:InitAiGrade()
	if self.isControl == 2 or self.isControl == 3 then
		self.nAiModel = 2
		return self.nAiModel --best hard
	end
	if self.isControl == 4 then
		self.nAiModel = 0
		return self.nAiModel
	end

	local tWaterInfo = Define.AssertWaterInfoExist(self.nBigBlind)
	local nCurSysWinRate = (tWaterInfo.nSysSumIn / tWaterInfo.nSysSumOut)
	if nCurSysWinRate < 1 then
		self.nAiModel = 2
		return self.nAiModel --best hard
	end
	if nCurSysWinRate < Define.nSysWinRate and math.random(1, 100) < 70 then
		self.nAiModel = 2
		return self.nAiModel --best hard
	end
	self.nAiModel = nil
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
	local tWaterInfo = Define.AssertWaterInfoExist(self.nBigBlind)
	local nAbs = math.abs(nProfix)
	if nProfix < 0 then
		tWaterInfo.nSysSumIn = tWaterInfo.nSysSumIn + nAbs --系统累计流入(系统赢,正数)
	else
		tWaterInfo.nSysSumOut = tWaterInfo.nSysSumOut + nAbs --系统累计流出(系统输,正数)
	end
end

--来自从服的请求处理
function Table:OnSlaveMsgHandle(sReturnKey, sCmd, tJsonData, nEcho)
	self:Print("OnSlaveMsgHandle sCmd:%s", sCmd)

	--从服玩家坐下
	if sCmd == "SlaveUserSit" then
		self.tTableOverview:LookerIn(tJsonData.nUserId, tJsonData.sName, tJsonData.sFaceId)
		self.nSlaveUserCnt = self.nSlaveUserCnt + 1
		local info = self.tUserLatelyBalance[tJsonData.nUserId] or {}
		if next(info) then
			self:_BroadCastToSlaves("DeZhouEnterNotify", { sName = tJsonData.sName, nUserId = tJsonData.nUserId })
		end
		return
	end
	--从服玩家离开
	if sCmd == "SlaveUserUp" then
		self.nSlaveUserCnt = self.nSlaveUserCnt - 1
		self:OnSlaveUserUp(tJsonData)
		return
	end

	--操作请求 xx
	if sCmd == "DeZhouOpReq" then
		self:DeZhouOpReq(tJsonData, sReturnKey)
		return
	end
	--预操作请求 xx
	if sCmd == "DeZhouPreOpReq" then
		self:DeZhouPreOpReq(tJsonData, sReturnKey)
		return
	end
	--坐下请求(坐下到玩家位置)xx
	if sCmd == "DeZhouSitDownReq" then
		self:DeZhouSitDownReq(tJsonData, sReturnKey)
		return
	end
	--站起请求xx
	if sCmd == "DeZhouStanpUpReq" then
		self:DeZhouStanpUpReq(tJsonData, sReturnKey)
		return
	end
	--返回大厅请求xx
	if sCmd == "DeZhouBackToLobbyReq" then
		self:DeZhouBackToLobbyReq(tJsonData, sReturnKey)
		return
	end
	--用户离线通知
	if sCmd == "UserOffLine" then
		self:UserOffLine(tJsonData, sReturnKey)
		return
	end
	--用户上线通知
	if sCmd == "UserOnLine" then
		self:UserOnLine(tJsonData, sReturnKey)
		return
	end
	--取消托管请求
	if sCmd == "DeZhouCancelAutoReq" then
		self:DeZhouCancelAutoReq(tJsonData, sReturnKey)
		return
	end
	--表情聊天
	if sCmd == "DeZhouChatReq" then
		self:_DeZhouChatReq(tJsonData, sReturnKey)
		return
	end
	--房间设置 请求
	if sCmd == "DeZhouCofingReq" then
		self:DeZhouCofingReq(tJsonData, sReturnKey)
		return
	end
	--Gm命令
	if sCmd == "DeZhouGmReq" then
		self:DeZhouGmReq(tJsonData, sReturnKey)
		return
	end
	--主播暂停请求
	if sCmd == "DeZhouPauseReq" then
		self:DeZhouPauseReq(tJsonData, sReturnKey)
		return
	end
	--主播踢人请求
	if sCmd == "DeZhouKickUserReq" then
		self:DeZhouKickUserReq(tJsonData, sReturnKey)
		return
	end
	--筹码买入请求 (可能是DeZhouTakeInReq拼写错误)
	if sCmd == "DeZhoTakeInReq" or sCmd == "DeZhouTakeInReq" then
		self:DeZhoTakeInReq(tJsonData, sReturnKey)
		return
	end
	--手动撤码
	if sCmd == "DeZhouTakeChipOutReq" then
		self:TakeChipsOutReq(tJsonData, sReturnKey)
		return
	end
	--撤码查看请求(来自从服)
	if sCmd == "DeZhouTakeOutInfoReq" then
		self:TakeOutInfoReq(tJsonData, sReturnKey)
		return
	end
	--撤码设置
	if sCmd == "DeZhouTakeOutSetReq" then
		self:TakeOutSetReq(tJsonData, sReturnKey)
		return
	end
	--后台踢人
	if sCmd == "REQ_Kick_User" then
		self:REQ_Kick_User(tJsonData, sReturnKey)
		return
	end
	--从服人数汇报
	if sCmd == "UserCnt_Report" then
		self:UserCnt_Report(tJsonData)
		return
	end
	--牌桌总览请求
	if sCmd == "OverViewReq" then
		self:OverViewReq(tJsonData, sReturnKey)
		return
	end

	--"开始牌局"请求 (房主使用)
	if sCmd == "TableStartReq" then
		self:TableStartReq(tJsonData, sReturnKey)
		return
	end
	--"开始游戏" 请求 (房主使用)
	if sCmd == "AutoNextReq" then
		self:AutoNextReq(tJsonData, sReturnKey)
		return
	end
	--保险购买请求
	if sCmd == "InsurBuyReq" then
		self:InsurBuyReq(tJsonData, sReturnKey)
		return
	end
	--延时请求
	if sCmd == "DelayReq" then
		self:DelayReq(tJsonData, sReturnKey)
		return
	end

	--筹码带出范围查看请求
	if sCmd == "TakeOutRangeReq" then
		self:TakeOutRangeReq(tJsonData, sReturnKey)
		return
	end
	--筹码带出请求
	if sCmd == "TakeOutReq" then
		self:TakeOutReq(tJsonData, sReturnKey)
		return
	end
	--'留座离桌'或'回到座位' 请求
	if sCmd == "RetainReq" then
		self:RetainReq(tJsonData, sReturnKey)
		return
	end
	--翻牌请求
	if sCmd == "CardOpenReq" then
		self:CardOpenReq(tJsonData, sReturnKey)
		return
	end
	--可存证hash请求
	if sCmd == "HashListReq" then
		self:OnHashListReq(tJsonData, sReturnKey)
		return
	end
	--Hash指定局牌序列请求
	if sCmd == "TableHashReq" then
		self:OnTableHashReq(tJsonData, sReturnKey)
		return
	end
	--看手牌请求
	if sCmd == "HandCardReq" then
		self:OnHandCardReq(tJsonData, sReturnKey)
		return
	end
	--切牌请求
	if sCmd == "CutCardReq" then
		self:OnCutCardReq(tJsonData, sReturnKey)
		return
	end
end

--use 用户请求处理 (当前机器人会用,需优化)
function Table:OnReqHandle(nUserId, strReq, tData, sReturnKey)
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if nSitId == nil then
		self:Print("Error, Can Not Find User_%d in Table", nUserId)
		return
	end

	tData.nUserId = nUserId
	self:OnSlaveMsgHandle(nil, strReq, tData, -2)
end

--用户下线通知(来自从服,掉线或返回大厅都使用该通知) 短线加上倒计时在清理
function Table:UserOffLine(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local isBackToLobby = ((tJsonData.sReason or "") == "BackToLobby")

	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		return
	end
	-- if (not self:_IsPartInUser(nSitId)) and (not tUser.isRetain or isBackToLobby) then
	-- 	self:_SetLeaveSeat(nSitId, tLeaveTableType.nOffLine)
	-- 	self:ProcessForLeavingTable(nUserId,tLeaveTableType.nOffLine)
	-- 	return
	-- end
	tUser.nOffLineCnt = tUser.nOffLineCnt + 1
	tUser.isBackToLobby = isBackToLobby
	tUser.isOffLine = true
	self:Print("User_%d OffLineCnt Became:%d", nUserId, tUser.nOffLineCnt)
	if not self:_IsPartInUser(nSitId) then
		self:_OfflineCountDown(tUser)
	end
end

--用户重新上线通知(来自从服)
function Table:UserOnLine(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("not in Player seat")
		return
	end
	tUser.nOffLineCnt = tUser.nOffLineCnt - 1
	tUser.isBackToLobby = false
	self:Print("User_%d OffLineCnt Became:%d", nUserId, tUser.nOffLineCnt)
	self:_OfflineLeaveCancel(nUserId, false)
end

function Table:_GetChatCost(nChatId)
	for _, v in ipairs(self.arrChat) do
		if v.nChatId == nChatId then
			return v.nCost
		end
	end
	return 0
end

--表情聊天请求(来自从服)---
function Table:_DeZhouChatReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	self:Print("_DeZhouChatReq,nSitId:%d nChatId:%d nTarget:%s", (nSitId or -1), tData.nChatId, tostring(tData.nTarget))
	nSitId = nSitId or 0 --聊天发起者座位号，如果是旁观者则用0表示
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
	local nType = tData.nType or 0
	local nCost = self:_GetChatCost(tData.nChatId)
	nCost = publicApi.Ceil_n(nCost, 2)
	-- self:Print("Chat Cost:%.2f",nCost)
	--扣金币
	if nCost > 0 and nType == 0 then
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nFaceChat
		local nNoNotice = tUser and true or false
		if not tPubUser.ChangeUserTreasure({ nUserID = nUserId, nItemID = 1, nDel = -nCost, nSourceType = nSourceType, nNoNotice = nNoNotice, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or "" }) then
			self:Print("Chat Fail,no Gold ")
			self:SendFailNotifyV2(sReturnKey, nUserId, 36, "no Gold")
			return
		end
		if tUser then
			tUser.nGold = tUser.nGold - nCost
			self:_SendToSlave(sReturnKey, "GoldNotify",
				{ nUserId = nUserId, nGold = self:GetUserTableGold(tUser, nUserId) })
		end
	end

	self:_BroadCastDeZhouChatNotify(nSitId, tData.nChatId, tData.nTarget)
end

--主播暂停请求,分游戏中请求暂停，非游戏中请求暂停 (来自从服) ---
function Table:DeZhouPauseReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	self:Print("DeZhouPauseReq nUserId:%d isPause:%s", nUserId, tostring(tData.isPause))
	if nUserId ~= self.nLiveUserID then
		self:Print("DeZhouPauseReq Fail,nLiveUserID is:%s", tostring(self.nLiveUserID))
		return
	end
	if self.isPause == tData.isPause then
		self:Print("DeZhouPauseReq Fail,status is same:%s", tostring(tData.isPause))
		return
	end
	self:_SendToSlave(sReturnKey, "DeZhouPauseRsp", { isPause = tData.isPause, nUserId = nUserId })
	self:_ChangePause(tData.isPause)
end

function Table:_ChangePause(isPause)
	if self.isPause == isPause then
		self:Print("WaringPause")
		return
	end
	self.isPause = isPause
	if self.isPause then
		self:_Pause()
	else
		self.TimerForPause:KillAllTimer()
		self:_PauseCancel()
	end
end

--取消托管请求(来自从服)
function Table:DeZhouCancelAutoReq(tData, sReturnKey)
	local nSitId, tUser = self:_GetSitIdByUserId(tData.nUserId)
	self:Print("DeZhouCancelAutoReq nSitId:%d", nSitId)
	assert(tUser ~= nil)
	self:_CancelAuto(tUser)
end

--筹码带出范围查看请求(来自从服)
function Table:TakeOutRangeReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local TakeOutRangeRsp = {}
	TakeOutRangeRsp.nGold = 0
	TakeOutRangeRsp.nNowSelect = 0 --当前选择带出的筹码
	TakeOutRangeRsp.nMax = 0    --最大可带出
	TakeOutRangeRsp.nUserId = nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("TakeOutRangeReq Fail, can not find user_%d in player seat", nUserId)
		TakeOutRangeRsp.nGold = tPubUser.Get_User_UnLockGold(nUserId, self.nItemId) --当前身上金币
		self:_SendToSlave(sReturnKey, "TakeOutRangeRsp", TakeOutRangeRsp)
		return
	end
	TakeOutRangeRsp.nGold = self:Get_User_UnLockGold(tUser)
	TakeOutRangeRsp.nMax = math.max(tUser.nBalance - self.nEnterMin, 0)
	TakeOutRangeRsp.nNowSelect = math.min(tUser.nTakeOutWant, TakeOutRangeRsp.nMax)
	self:_SendToSlave(sReturnKey, "TakeOutRangeRsp", TakeOutRangeRsp)
end

--筹码带出请求(来自从服)
function Table:TakeOutReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local nTakeOut = tJsonData.nTakeOut
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("TakeOutReq Fail, can not find user_%d in player seat", nUserId)
		self:_SendToSlave(sReturnKey, "TakeOutRsp", { nUserId = nUserId, nRlt = 1 })
		return
	end
	tUser.nTakeOutWant = math.max(nTakeOut, 0)
	tUser.nBuyTo = 0
	tUser.nIsAutoBuy = false
	self:_SendToSlave(sReturnKey, "TakeOutRsp", { nUserId = nUserId, nRlt = 0 })
end

--留座
function Table:_Retain(nUserId)
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		return -1, "user not in seat"
	end
	if tUser.isRetain then
		return -2, "state wrong"
	end
	if self.tLeaveTableConfig.isOpen and tPenaltyManager:getRetainCount(nUserId, self.sTableId) > 0 then
		return -3, "You can only keep it once"
	end
	tUser.isRetain = true
	tPenaltyManager:addRetainCount(nUserId, self.sTableId)

	if #tUser.arrHoleCards > 0 then --本手牌结束后计时再生效
		return 1
	end
	--开始留座倒计时
	local isB = self:_RetainCountDown(tUser)
	assert(isB, "something wrong")
	return 0
end

--取消留座
function Table:_RetainCancel(nUserId, isByTimeOut)
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		return -1, "user not in seat"
	end
	if not tUser.isRetain then
		return -2, "state wrong"
	end
	tUser.isRetain = false
	--取消留座倒计时,如果有的话 取消托管
	self:_RetainCountDownCancel(tUser)
	self:_CancelAuto(tUser)

	if (tUser.nOffLineCnt ~= 0 or isByTimeOut) and (not self:_IsPartInUser(nSitId)) then
		self:_SetLeaveSeat(nSitId)
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
	local nSeconds = Define.nRetainTime
	tUser.nRetainTimerId = self.TimerForRetain:DelayCall(nSeconds * 1000, self._RetainCancel, self, tUser.nUserId, true)
	--广播
	self:Print("_RetainCountDown for user:%d", tUser.nUserId)
	self:_BroadCastToSlaves("RetainNotify", { nPos = tUser.nSitId, nOp = 0, nSeconds = nSeconds })
	return true
end

--取消留座倒计时,如果有的话
function Table:_RetainCountDownCancel(tUser)
	if not tUser.nRetainTimerId then
		return false
	end
	self.TimerForRetain:KillTimer(tUser.nRetainTimerId)
	tUser.nRetainTimerId = nil
	--广播
	self:Print("_RetainCountDownCancel for user:%d", tUser.nUserId)
	self:_BroadCastToSlaves("RetainNotify", { nPos = tUser.nSitId, nOp = 1 })
	return true
end

--取消离线倒计时,如果有的话
function Table:_OfflineCountDownCancel(tUser)
	if not tUser.nOfflineTimerId then
		return false
	end
	self.TimerForOffline:KillTimer(tUser.nOfflineTimerId)
	tUser.nOfflineTimerId = nil
	--广播
	self:Print("_RetainCountDownCancel for user:%d", tUser.nUserId)
	-- self:_BroadCastToSlaves("OfflineNotify",{nPos=tUser.nSitId,nOp=4})
	return true
end

--取消离线倒计时
function Table:_OfflineLeaveCancel(nUserId, isByTimeOut)
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		return -1, "user not in seat"
	end
	if not tUser.isOffLine then
		return -2, "state wrong"
	end
	--取消离线倒计时,如果有的话
	self:_OfflineCountDownCancel(tUser)

	if isByTimeOut and (not self:_IsPartInUser(nSitId)) then
		self:_SetLeaveSeat(nSitId)
		return
	end
	if not isByTimeOut then
		tUser.isOffLine = true
	end

	self:_TryToStartGame()
	return 0
end

--离线倒计时开始,如果还没开始的话
function Table:_OfflineCountDown(tUser)
	if tUser.nOfflineTimerId then
		return false
	end
	local nSeconds = Define.nOfflineTime
	tUser.nOfflineTimerId = self.TimerForOffline:DelayCall(nSeconds * 1000, self._OfflineLeaveCancel, self, tUser
		.nUserId, true)
	--广播
	self:Print("_OfflineCountDown for user:%d", tUser.nUserId)
	-- self:_BroadCastToSlaves("OfflineNotify",{nPos=tUser.nSitId,nOp=3,nSeconds=nSeconds})
	return true
end

--翻牌请求
function Table:CardOpenReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	self:Print("CardOpenReq nUserId:%d", nUserId)

	--非结算阶段不允许操作
	if self.nStage ~= TableState.nSettle then
		self:Print("stage wrong")
		return
	end
	--没牌可看
	if #self.arrCardsOpenForPay == 0 then
		self:Print("no cards for open")
		return
	end
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("CardOpenReq Fail, can not find user_%d in player seat", nUserId)
		self:_SendToSlave(sReturnKey, "CardOpenRsp", { nRlt = 1, arrCards = {}, nUserId = nUserId })
		return
	end
	local conf = self:_GetCardCost(1)
	if not tonumber(conf.open) == 1 then
		self:Print("CardOpenReq Fail, not open user_%d", nUserId)
		return
	end
	--扣金币
	-- local nCost =self.nCardOpenFee
	local nCost = tonumber(conf.nCost) or 0
	nCost = publicApi.Ceil_n(nCost, 2)
	if nCost > 0 then
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nLookCard
		self:Print("CardOpenReq nSourceType:%d self.nGameId:%d", nSourceType, self.nGameId)
		if not tPubUser.ChangeUserTreasure({ nUserID = nUserId, nItemID = 1, nDel = -nCost, nSourceType = nSourceType, nNoNotice = true, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or "" }) then
			self:Print("gold not enought")
			self:_SendToSlave(sReturnKey, "CardOpenRsp", { nRlt = 2, arrCards = {}, nUserId = nUserId })
			return
		end
		tUser.nGold = tUser.nGold - nCost
		self:_SendToSlave(sReturnKey, "GoldNotify", { nUserId = nUserId, nGold = self:GetUserTableGold(tUser, nUserId) })
	end
	self.tReview:SetLookData({ nUserId = nUserId, nType = 1 })

	self:Print("CardOpenReq succee,nCardOpenFee:%.2f nUserId:%d", nCost, nUserId)
	--回复
	self:_SendToSlave(sReturnKey, "CardOpenRsp", { nRlt = 0, arrCards = self.arrCardsOpenForPay, nUserId = nUserId })
	self:_BroadCastToSlaves("CardOpNotify", { nOpId = 1, nUserId = nUserId, nName = tUser.sName })
end

-- 看手牌请求
function Table:OnHandCardReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	self:Print("OnHandCardReq nUserId:%d", nUserId)
	--非结算阶段不允许操作
	if self.nStage ~= TableState.nSettle then
		self:Print("stage wrong")
		return
	end
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("OnHandCardReq Fail, can not find user_%d in player seat", nUserId)
		self:_SendToSlave(sReturnKey, "HandCardRsp", { nRlt = 1, nHandInfo = {}, nUserId = nUserId })
		return
	end
	--扣金币
	local conf = self:_GetCardCost(2)
	if not tonumber(conf.open) == 1 then
		self:Print("OnHandCardReq Fail, not open user_%d", nUserId)
		return
	end
	local nHandInfo = {}
	local nCost = tonumber(conf.nCost) or 0
	nCost = publicApi.Ceil_n(nCost, 2)
	if nCost > 0 then
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nLookHands
		self:Print("OnHandCardReq nSourceType:%d self.nGameId:%d", nSourceType, self.nGameId)
		if not tPubUser.ChangeUserTreasure({ nUserID = nUserId, nItemID = 1, nDel = -nCost, nSourceType = nSourceType, nNoNotice = true, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or "" }) then
			self:Print("gold not enought")
			self:_SendToSlave(sReturnKey, "HandCardRsp", { nRlt = 2, nHandInfo = nHandInfo, nUserId = nUserId })
			return
		end
		tUser.nGold = tUser.nGold - nCost
		self:_SendToSlave(sReturnKey, "GoldNotify", { nUserId = nUserId, nGold = self:GetUserTableGold(tUser, nUserId) })
	end
	for _, nPos in ipairs(self.arrPosPartIn) do
		local TUser = self:_GetUser(nPos)
		if TUser and TUser.nUserId ~= nUserId then
			table.insert(nHandInfo, { nUserId = TUser.nUserId, arrHoleCards = _CopyArr(TUser.arrHoleCards), nPos = nPos })
		end
	end
	self.tReview:SetLookData({ nUserId = nUserId, nType = 2 })
	self:Print("OnHandCardReq succee,nCost:%.2f nUserId:%d", nCost, nUserId)
	--回复
	self:_SendToSlave(sReturnKey, "HandCardRsp", { nRlt = 0, nHandInfo = nHandInfo, nUserId = nUserId })
	self:_BroadCastToSlaves("CardOpNotify", { nOpId = 2, nUserId = nUserId, nName = tUser.sName })
end

-- 切牌请求
function Table:OnCutCardReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local nIsStart = tJsonData.nIsStart
	self:Print("OnCutCardReq nUserId:%d", nUserId)
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("OnCutCardReq Fail, can not find user_%d in player seat", nUserId)
		self:_SendToSlave(sReturnKey, "CutCardRsp", { nRlt = 1, nUserId = nUserId })
		return
	end
	--非结算阶段不允许操作
	if nIsStart then
		if self.nStage ~= TableState.nSettle then
			self:Print("stage wrong")
			return
		end
		if self.isCutting then
			self:Print("OnCutCardReq Fail, have cut user_%d", nUserId)
			return
		end
	else
		if (self.nCutUserInfo.nCutUserId or 0) ~= nUserId then
			self:Print("OnCutCardReq Fail, self.nCutUserId:%d not same user_%d", self.nCutUserInfo.nCutUserId, nUserId)
			return
		end
		self.nCutUserInfo.nCutIndex = tJsonData.nIndex
		self:_ToCutCardEnd(0.1, true)
		self:_SendToSlave(sReturnKey, "CutCardRsp", { nRlt = 0, nUserId = nUserId })
		self:_BroadCastToSlaves("CardOpNotify",
			{ nOpId = 3, nSitId = nSitId, nIndex = tJsonData.nIndex, nRemain = 5, nUserId = nUserId, nName = tUser.sName })
		return
	end
	--扣金币
	local conf = self:_GetCardCost(3)
	if not tonumber(conf.open) == 1 then
		self:Print("OnCutCardReq Fail, not open user_%d", nUserId)
		return
	end
	self.isCutting = true
	local nCost = tonumber(conf.nCost) or 0
	if nCost > 0 then
		local gold = self:Get_User_UnLockGold(tUser)
		if gold < nCost then
			self:Print("gold not enought")
			self:_SendToSlave(sReturnKey, "CutCardRsp", { nRlt = 2, nUserId = nUserId })
			self.isCutting = false
			return
		end
	end
	self.nCutUserInfo = { nCutUserId = nUserId, nSitId = nSitId, nName = tUser.sName }
	self:Print("OnCutCardReq succee,nCost:%.2f nUserId:%d tJsonData.nIndex:%d", nCost, nUserId, tJsonData.nIndex)

	-- local remain = os.time() - self.nSettleEndTime
	-- remain = remain > 0 and remain or 0
	-- remain = remain + Define.nCutTime
	-- self:_ToSettleEnd(remain)
	--回复
	self:_SendToSlave(sReturnKey, "CutCardRsp", { nRlt = 0, nUserId = nUserId })
	self:_BroadCastToSlaves("CardOpNotify",
		{ nOpId = 3, nSitId = nSitId, nIndex = tJsonData.nIndex, nRemain = 0, nUserId = nUserId, nName = tUser.sName })
end

--'留座离桌'或'回到座位' 请求(来自从服)
function Table:RetainReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local nOp = tJsonData.nOp
	self:Print("RetainReq nUserId:%d nOp:%d", nUserId, nOp)

	--0:留座离桌
	if nOp == 0 then
		local nCode, sErr = self:_Retain(nUserId)
		self:Print("_Retain nCode:%d sErr:%s", nCode, (sErr or "succee"))
		--回复
		self:_SendToSlave(sReturnKey, "RetainRsp", { nRlt = nCode, nOp = nOp, nUserId = nUserId })
		return
	end

	--1:取消'留座离桌'
	if nOp == 1 then
		local nCode, sErr = self:_RetainCancel(nUserId)
		self:Print("_Retain nCode:%d sErr:%s", nCode, (sErr or "succee"))
		--回复
		self:_SendToSlave(sReturnKey, "RetainRsp", { nRlt = nCode, nOp = nOp, nUserId = nUserId })
		return
	end
	self:Print("RetainReq parameter error")
end

--筹码买入请求(来自从服)
function Table:DeZhoTakeInReq(tData, sReturnKey)
	local nSitId, tUser = self:_GetSitIdByUserId(tData.nUserId)
	assert(tData.nBuyTo ~= nil)
	self:Print("DeZhoTakeInReq nUserId:%d,nBuyTo:%.2f", tData.nUserId, tData.nBuyTo)
	if not nSitId then
		self:Print("DeZhoTakeInReq Fail,can not find user")
		return
	end
	local nCanOutChips = self:Get_User_CanTempChips(tUser)
	local nBuyTo = tData.nBuyTo                  -- + tUser.nBalance    -- 单次上限
	if not (LessOrEqual(nBuyTo, self.nBuyMax)) then --有意不做严格限制
		self:Print("DeZhoTakeInReq Fail,Out of Range,nBalance:%.2f tUser.nTempChips:%.2f nCanOutChips:%.2f",
			tUser.nBalance, tUser.nTempChips, nCanOutChips)
		self:_SendToSlave(sReturnKey, "TakeInRsp",
			{
				nRlt = 2,
				nBalance = tUser.nBalance,
				nUserId = tData.nUserId,
				nTempChips = tUser.nTempChips,
				nCanOutChips =
					nCanOutChips
			})
		return
	end
	local nMax = self:Get_User_UnLockGold(tUser) + tUser.nTempChips -- tUser.nBalance
	if GreaterThan(nBuyTo, nMax) then
		self:Print("DeZhoTakeInReq Fail,Gold Not Enough,nMax:%.2f,nBalance:%.2f tUser.nTempChips:%.2f nCanOutChips:%.2f",
			nMax, tUser.nBalance, tUser.nTempChips, nCanOutChips)
		self:_SendToSlave(sReturnKey, "TakeInRsp",
			{
				nRlt = 1,
				nBalance = tUser.nBalance,
				nUserId = tData.nUserId,
				nTempChips = tUser.nTempChips,
				nCanOutChips =
					nCanOutChips
			})
		return
	end
	local tUnBuyTo = (tUser.nBuyTo or 0) + tData.nBuyTo
	if self.nTakeInLimit > 0 and (tUser.nBalance + tUnBuyTo) > self.nTakeInLimit then -- 超过补码限制
		self:Print(
			"DeZhoTakeInReq Fail, nTakeInLimit ,nTakeInLimit:%.2f,nLockGoldInTable:%.2f nBuyTo:%.2f tUser.nBalance:%.2f",
			self.nTakeInLimit, tUser.nLockGoldInTable, tUnBuyTo, tUser.nBalance)
		self:_SendToSlave(sReturnKey, "TakeInRsp",
			{
				nRlt = 3,
				nBalance = tUser.nBalance,
				nUserId = tData.nUserId,
				nTempChips = tUser.nTempChips,
				nCanOutChips =
					nCanOutChips
			})
		return
	end
	nBuyTo = nBuyTo + (tUser.nLockGoldInTable or 0)

	tUser.nBuyTo = (tUser.nBuyTo or 0) + tData.nBuyTo
	tUser.nIsAutoBuy = tData.nIsAutoBuy
	tUser.nTakeOutWant = 0

	local nBalance = -1                 -->=0:买入后当前筹码 ,-1:买入后下局生效
	if not self:_IsPartInUser(nSitId) then --非游戏中时，实时带入筹码
		if not self:_InitUserTakeIn(tUser, nBuyTo, 0) then
			self:Print("DeZhoTakeInReq,Error happen")
		end
		tUser.nBalance = tUser.nLockGoldInTable --当前可用筹码
		nBalance = tUser.nBalance
		if not (tUser.nIsAutoBuy == 1) then --非每局自动带入时，只生效一次
			tUser.nBuyTo = 0
		end
		nCanOutChips = self:Get_User_CanTempChips(tUser)
	end
	self.tTableOverview:HaveTakeIn(tData.nUserId, tUser.sName, tUser.nBalance, tUser.sFaceId)
	--回复
	self:_SendToSlave(sReturnKey, "TakeInRsp",
		{
			nRlt = 0,
			nBalance = nBalance,
			nUserId = tData.nUserId,
			nTempChips = tUser.nTempChips,
			nCanOutChips =
				nCanOutChips,
			nBuyTo = tUser.nBuyTo
		})
	self:_SendToSlave(sReturnKey, "GoldNotify", { nUserId = tData.nUserId, nGold = self:Get_User_UnLockGold(tUser) })
	if nBalance > -1 then
		self:_BroadCastToSlaves("TakeInNotify", { nSitId = nSitId, nBalance = nBalance })
	end
	--尝试开始游戏
	self:_TryToStartGame()
end

--撤码查看请求(来自从服)
function Table:TakeOutInfoReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local TakeOutInfoRsp = {}
	TakeOutInfoRsp.nTempChips = 0
	TakeOutInfoRsp.nCanOutChips = 0
	TakeOutInfoRsp.isAutoTabkeOut = false
	TakeOutInfoRsp.nUserId = nUserId
	TakeOutInfoRsp.nRlt = 0
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		TakeOutInfoRsp.nRlt = 1
		self:Print("TakeOutInfoReq Fail, can not find user_%d in player seat", nUserId)
		self:_SendToSlave(sReturnKey, "TakeOutInfoRsp", TakeOutInfoRsp)
		return
	end
	if not self.isTabkeOut then
		return
	end
	TakeOutInfoRsp.isAutoTabkeOut = tUser.isAutoTabkeOut
	TakeOutInfoRsp.nTempChips = tUser.nTempChips
	TakeOutInfoRsp.nCanOutChips = self:Get_User_CanTempChips(tUser)
	self:_SendToSlave(sReturnKey, "TakeOutInfoRsp", TakeOutInfoRsp)
end

--撤码设置
function Table:TakeOutSetReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local isAuto = tJsonData.isAuto
	local isAutoTabkeOut = isAuto == 1
	local TakeOutSetRsp = {}
	TakeOutSetRsp.isAuto = isAutoTabkeOut
	TakeOutSetRsp.nUserId = nUserId
	TakeOutSetRsp.nRlt = 0
	TakeOutSetRsp.nCanOutChips = 0
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("TakeOutSetReq Fail, can not find user_%d in player seat", nUserId)
		TakeOutSetRsp.nRlt = 1
		self:_SendToSlave(sReturnKey, "TakeOutSetRsp", TakeOutSetRsp)
		return
	end
	if not self.isTabkeOut then
		TakeOutSetRsp.nRlt = 2
		self:_SendToSlave(sReturnKey, "TakeOutSetRsp", TakeOutSetRsp)
		return
	end
	tUser.isAutoTabkeOut = isAutoTabkeOut
	tUser.nAutoChips = 0 --撤码预设值清零
	TakeOutSetRsp.nCanOutChips = self:Get_User_CanTempChips(tUser)
	self:_SendToSlave(sReturnKey, "TakeOutSetRsp", TakeOutSetRsp)
end

--手动撤码
function Table:TakeChipsOutReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local nValue = tJsonData.nValue
	local TakeOutRsp = {}
	TakeOutRsp.nUserId = nUserId
	TakeOutRsp.nTempChips = 0
	TakeOutRsp.nCanOutChips = 0
	TakeOutRsp.nBalance = 0
	TakeOutRsp.nRlt = 0
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("TakeChipsOutReq Fail, can not find user_%d in player seat", nUserId)
		TakeOutRsp.nRlt = 1
		self:_SendToSlave(sReturnKey, "TakeChipsOutRsp", TakeOutRsp)
		return
	end

	local nRlt, gold, nTempChips = self:AutoWithdrawChips(tUser, nValue, nil)
	if nRlt ~= 0 then
		TakeOutRsp.nRlt = nRlt
		self:_SendToSlave(sReturnKey, "TakeChipsOutRsp", TakeOutRsp)
		return
	end

	-- 更新玩家的总撤码数据
	self.tTableOverview:UpdateTakeOutChips(nUserId, nValue)
	-- 更新 hhhh
	if self:IsTotalRake() then
		taxHelp:removeChip(nUserId, self.sTableId, nValue)
	end
	tPenaltyManager:removeChip(nUserId, self.sTableId, nValue)

	-- 发送给从服
	TakeOutRsp.nBalance = tUser.nBalance
	TakeOutRsp.nTempChips = tUser.nTempChips
	TakeOutRsp.nCanOutChips = self:Get_User_CanTempChips(tUser)
	self:_SendToSlave(sReturnKey, "TakeChipsOutRsp", TakeOutRsp)
end

-- 自动撤码检查与执行 nValue 玩家输入数 isAuto 是否自动
function Table:AutoWithdrawChips(tUser, nValue, isAuto)
	if not self.isTabkeOut then
		return 2, 0
	end
	if isAuto then
		if not tUser.isAutoTabkeOut then
			if tUser.nAutoChips <= 0 then
				return 3, 0
			end
			nValue = tUser.nAutoChips
		end
	end
	local nCanOutChips = self:Get_User_CanTempChips(tUser, isAuto)
	nValue = nValue or nCanOutChips
	self:Print("nCanOutChips:%.2f nValue:%.2f tUser.nBalance:%.2f", nCanOutChips, nValue, tUser.nBalance)
	if LessThan(nCanOutChips, nValue) then
		if isAuto then
			tUser.nAutoChips = 0
		end
		return 4, 0
	end
	-- 撤出的额度
	local nWithdraw = nValue
	if not isAuto then -- 手动撤码 牌局结束才生效
		tUser.nAutoChips = tUser.nAutoChips + nWithdraw
	else
		if self:IsTotalRake() then
			-- 自动撤码
			taxHelp:removeChip(tUser.nUserId, self.sTableId, nWithdraw)
		end
		tPenaltyManager:removeChip(tUser.nUserId, self.sTableId, nWithdraw)
		-- 扣除桌上筹码
		self:Del_User_CanTempChips(tUser, -nWithdraw)
		-- 加入暂存区
		self:Deal_User_CanTempChips(tUser, nWithdraw, true)
	end

	self:Print("玩家[%d] 自动撤码 %.2f 到暂存区，总暂存 %.2f", tUser.nUserId, nWithdraw, tUser.nTempChips)
	return 0, nWithdraw, tUser.nTempChips
end

--可存证hash请求
function Table:OnHashListReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	self:Print("OnHashListReq nUserId:%d nMinId:%d nQueryCnt:%d", nUserId, tJsonData.nMinId, tJsonData.nQueryCnt)
	local result = self.hashHelper:GetHashList(tJsonData)
	--回复
	self:_SendToSlave(sReturnKey, "HashListRsp", { list = result.list, nMinId = result.nMinId, nUserId = nUserId })
end

function Table:OnTableHashReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	self:Print("OnTableHashReq nUserId:%d", nUserId)
	if self.sPaiJuId == tJsonData.sPaiJuId and self.nStage == TableState.nPlaying then
		self:_SendToSlave(sReturnKey, "TableHashRsp", { nRlt = 2, nUserId = nUserId })
		return
	end
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("OnTableHashReq Fail, can not find user_%d in player seat", nUserId)
		return
	end
	local result = self.hashHelper:GetTableHash(tJsonData)
	if not result then
		--回复
		self:_SendToSlave(sReturnKey, "TableHashRsp", { nRlt = 4, nUserId = nUserId })
		return
	end
	local lookData = result.lookData or {}
	local show = result.show
	if lookData[nUserId] then
		show = 1
	end
	local nCost = 0.2
	local value = tPublicRedis.HgetRedis1(GlobalConfigKey.ConfigKey, GlobalConfigKey.CostConfigs)
	if value and value ~= "" then
		local conf = cjson.decode(value)
		local cCost = conf[CostName.Hash] or "0"
		nCost = tonumber(cCost) or 0
	end
	nCost = publicApi.Ceil_n(nCost, 2)
	if show == 0 and nCost > 0 then
		local nSourceType = 100009
		if not tPubUser.ChangeUserTreasure({ nUserID = nUserId, nItemID = 1, nDel = -nCost, nSourceType = nSourceType, nNoNotice = true, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or "" }) then
			self:Print("OnTableHashReq gold not enought nUserId:%d nCost:%.2f", nUserId, nCost)
			self:_SendToSlave(sReturnKey, "TableHashRsp", { nRlt = 3, nUserId = nUserId })
			return
		end
		tUser.nGold = tUser.nGold - nCost
		self:_SendToSlave(sReturnKey, "GoldNotify", { nUserId = nUserId, nGold = self:GetUserTableGold(tUser, nUserId) })
		self.hashHelper:SetTableHashLook(tJsonData.sPaiJuId, nUserId)
		RecordDbr.UpdateHashRecord(nUserId, tJsonData.sPaiJuId)
	end
	self:_SendToSlave(sReturnKey, "TableHashRsp",
		{ nRlt = 0, nDetail = cjson.encode(result.exData), nCards = result.cards, nUserId = nUserId })
end

--从服人数汇报(来自从服)---
function Table:UserCnt_Report(tData)
	if tData.isHaveUser then
		self.nTimestampZeroRealUser = os.time() --过久不刷新该时间值,便视为过久没真人玩家进入
	end
end

--"开始牌局"请求,房主使用 (来自从服)
function Table:TableStartReq(tJsonData, sReturnKey)
	if self.isTableStart then
		self:Print("already start")
		return
	end
	self.isTableStart = true
	--self:BeginTiming()
	self:_BroadCastToSlaves("TableStarNotify", { isTableStart = true })
	self:_TryToStartGame()
end

--"开始游戏" 请求,房主使用 (来自从服)
function Table:AutoNextReq(tJsonData, sReturnKey)
	--if self.isAutoNext then
	--	self:Print("already AutoNext")
	--	return
	--end
	self.nStartAtLeast = 2
	self.isAutoNext = true
	self:_BroadCastToSlaves("AutoNextNotify", { isAutoNext = true })
	self:_TryToStartGame()
end

--牌局总览请求(来自从服)---
function Table:OverViewReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nNoUse = tData.nNoUse or 0
	self:Print("OverViewReq nUserId:%d nNoUse:%d", nUserId, nNoUse)

	if nNoUse == 0 then
		local tOverview = self.tTableOverview:GetOverview()
		self:Print("OverViewReq arrPartInUser Len:%d", #tOverview.arrPartInUser)
		local tRemainStack = _CutOff(tOverview.arrPartInUser, Define.nOverViewRtLen) --截断arrPartInUser,只保留20个数据
		tOverview.sPaiJuId = self.sPaiJuId
		tOverview.sTableName = self.sTableName
		tOverview.nSmallBlind = self.nSmallBlind
		tOverview.nBigBlind = self.nBigBlind
		tOverview.nZhuaTou = self.nZhuaTou
		tOverview.nBetBefore = self.nPreAnte --前注
		-- tOverview.nInsur =self.nInsurPool						--保险池
		tOverview.nRound = self.nJuShu
		tOverview.nRemainTime = self:_GetRemainTime()    --剩余时间
		tOverview.nEndFlag = tRemainStack:IsEmpty() and 0 or 1 --1:列表还未结束, 其它:已结束
		self:_SendToSlave(sReturnKey, "OverviewRsp", { tOverview = tOverview, nUserId = tData.nUserId })
		--创建快照
		tOverview.arrPartInUser = {}
		self:_DoSnapshoot(nUserId, tOverview, tRemainStack)
		return
	end
	if nNoUse == 1 then
		local tOverview, tRemainStack = self:ObtainFromSnapshoot(nUserId)
		assert(tOverview ~= nil)
		tOverview.nRemainTime = self:_GetRemainTime()
		tOverview.nEndFlag = tRemainStack:IsEmpty() and 0 or 1 --1:列表还未结束, 其它:已结束
		self:_SendToSlave(sReturnKey, "OverviewRsp", { tOverview = tOverview, nUserId = tData.nUserId })
		--创建快照
		tOverview.arrPartInUser = {}
		self:_DoSnapshoot(nUserId, tOverview, tRemainStack)
		return
	end
	if nNoUse == -1 then
		self:_DoSnapshoot(nUserId) --清空快照
		return
	end
end

function Table:ObtainFromSnapshoot(nUserId)
	local tCache = self.tOverviewSnapshoot[nUserId]
	if not tCache then
		return
	end
	local tOverview = tCache.tOverview
	local tRemainStack = tCache.tRemainStack
	local arrPartInUser = {}
	while (#arrPartInUser < Define.nOverViewRtLen and (not tRemainStack:IsEmpty())) do
		local tItem = tRemainStack:Pop()
		table.insert(arrPartInUser, tItem)
	end
	tOverview.arrPartInUser = arrPartInUser
	return tOverview, tRemainStack
end

function Table:_DoSnapshoot(nUserId, tOverview, tRemainStack)
	if tOverview == nil or tRemainStack == nil then
		self.tOverviewSnapshoot[nUserId] = nil
		return
	end
	if not tRemainStack:IsEmpty() then
		self.tOverviewSnapshoot[nUserId] = { tOverview = tOverview, tRemainStack = tRemainStack }
	else
		self.tOverviewSnapshoot[nUserId] = nil
	end
end

--主播踢人请求(来自从服)---
function Table:DeZhouKickUserReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nPos = tData.nPos

	self:Print("DeZhouKickUserReq nUserId:%d nTargetPos:%d", nUserId, nPos)
	if nUserId ~= self.nLiveUserID then
		self:Print("DeZhouKickUserReq Fail,nLiveUserID is:%s", tostring(self.nLiveUserID))
		self:_SendToSlave(sReturnKey, "DeZhouKickUserRsp", { nRlt = 10, nUserId = nUserId })
		return
	end
	if not self:_IsPlayerPos(nPos) then
		self:Print("DeZhouKickUserReq Fail ,nTargetPos illeagel, nTargetPos:%d", nPos)
		self:_SendToSlave(sReturnKey, "DeZhouKickUserRsp", { nRlt = 11, nUserId = nUserId })
		return
	end
	local tTargetUser = self:_GetUser(nPos)
	if tTargetUser == nil then
		self:Print("DeZhouKickUserReq Fail,tTargetUser is nil")
		self:_SendToSlave(sReturnKey, "DeZhouKickUserRsp", { nRlt = 12, nUserId = nUserId })
		return
	end
	if not self:_IsPartInUser(nPos) then
		self:_SendToSlave(sReturnKey, "DeZhouKickUserRsp", { nRlt = 0, nUserId = nUserId })
		self:_ForceStandUp(nPos, 20)
		return
	end
	self:_SendToSlave(sReturnKey, "DeZhouKickUserRsp", { nRlt = 1, nUserId = nUserId })
	tTargetUser.nStanpUpReason = MsgCode.nKickByLive --当局结束后站起
end

--Gm命令请求(来自从服)
function Table:DeZhouGmReq(tData, sReturnKey)
	local nSitId, tUser = self:_GetSitIdByUserId(tData.nUserId)
	self:Print("DeZhouGmReq:%s", tData.sStr)
	if tData.sStr == "close" then
		self:SetClose(TableCloseReason.nGmClose)
		return
	end
	if tData.sStr == "ai" then
		self.isUseAi = true
		return
	end
	if tData.sStr == "aiban" then
		self.isUseAi = false
		return
	end

	if tData.sStr == "y2" then
		Define.nOverViewRtLen = 2
		return
	end
	if tData.sStr == "y5" then
		Define.nOverViewRtLen = 5
		return
	end
	if tData.sStr == "y10" then
		Define.nOverViewRtLen = 10
		return
	end
	if tData.sStr == "y20" then
		Define.nOverViewRtLen = 20
		return
	end

	if tData.sStr == "retain" then
		self:_Retain(tUser.nUserId)
		return
	end
	if tData.sStr == "retainC" then
		self:_RetainCancel(tUser.nUserId)
		return
	end

	if tData.sStr == "Config" then
		self.isConfigNotSet = false
	end
	if tData.sStr == "TableStartReq" then
		self:TableStartReq()
		return
	end
	if tData.sStr == "AutoNextReq" then
		self:AutoNextReq()
		return
	end
	if tData.sStr == "Pause" then
		self:_ChangePause(true)
		return
	end
	if tData.sStr == "CancelPause" then
		self:_ChangePause(false)
		return
	end
	if tData.sStr == "DelayReq" and tUser then
		self:DelayReq({ nUserId = tUser.nUserId })
		return
	end
	if tData.sStr == "h2" then
		self.nHoleCardCnt = 2
		return
	end
	if tData.sStr == "h4" then
		self.nHoleCardCnt = 4
		return
	end
	if tData.sStr == "DR" then
		self.nMaxAndroidCnt = self.nMaxAndroidCnt - 1
		self.nMaxAndroidCnt = math.max(0, self.nMaxAndroidCnt)
		self:Print("DR nMaxAndroidCnt:%d", self.nMaxAndroidCnt)
		return
	end
	if tData.sStr == "IR" then
		self.nMaxAndroidCnt = self.nMaxAndroidCnt + 1
		self.nMaxAndroidCnt = math.min(self.nMaxAndroidCnt, self.nCapacity)
		return
	end

	-- if tData.sStr=="TakeOutReq" then
	-- 	self:TakeOutReq({nUserId=tData.nUserId,nTakeOut=100000})
	-- 	return
	-- end

	local isSuccee, tRlt = pcall(cjson.decode, tData.sStr)
	if not isSuccee then
		self:Print("Json decode Fail")
		return
	end
	local arrPreSetHoleCard = tRlt[1] or {}
	local arrPreSetCommCard = tRlt[2] or {}

	local tCardToCnt = {}
	local arrHoleCard = {}
	local arrCommCard = {}
	--检查参数合法性
	for _, nCard in ipairs(arrPreSetHoleCard) do
		if tCardToCnt[nCard] == nil and isCardValue(nCard) and #arrHoleCard < 2 then
			table.insert(arrHoleCard, nCard)
			tCardToCnt[nCard] = true
		end
	end
	for _, nCard in ipairs(arrPreSetCommCard) do
		if tCardToCnt[nCard] == nil and isCardValue(nCard) and #arrCommCard < 5 then
			table.insert(arrCommCard, nCard)
			tCardToCnt[nCard] = true
		end
	end
	--预设置玩家底牌与公共牌
	if tUser then
		tUser.arrPreSetHoleCard = arrHoleCard
	end
	self.arrPreSetCommCard = arrCommCard
end

--主播选择房间配置请求(来自从服)
function Table:DeZhouCofingReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	self:Print("DeZhouCofingReq,nUserId:%d nCapacity:%d nConfigId:%d nIntervalLev:%s",
		nUserId, tData.nCapacity, tData.nConfigId, tostring(tData.nIntervalLev))

	if nUserId ~= self.nLiveUserID then
		self:Print("NotLiveUserId")
		return
	end
	if not self.isConfigNotSet then
		if not (self.nStage == TableState.nInit and self.isPause) then
			self:Print("Not Pause Stage")
			return
		end
	end
	local isCapcityLegal = _IsHaveEle(self.tDeZhouConfigOption.arrCapacity, tData.nCapacity)
	local isConfigIdLegal, tConfigItem = false, nil
	for _, v in ipairs(self.tDeZhouConfigOption.arrConfig) do
		if v.nConfigId == tData.nConfigId then
			isConfigIdLegal, tConfigItem = true, v
			break
		end
	end
	if isCapcityLegal == false or isConfigIdLegal == false then
		self:Print("Config Not Legal")
		return
	end
	--座位数减少时可能需要踢出一些玩家
	if (not self.isConfigNotSet) and tData.nCapacity < self.nCapacity then
		for i = tData.nCapacity + 1, self.nCapacity do
			if self:_GetUser(i) then
				self:_ForceStandUp(i, 14)
			end
		end
	end
	local isChange = --配置是否发生了变化
		(self.isConfigNotSet or
			self.nSmallBlind ~= tConfigItem.nSmallBlind or
			self.nBigBlind ~= tConfigItem.nBigBlind or
			self.nBuyMin ~= tConfigItem.nTakeInMin or
			self.nBuyMax ~= tConfigItem.nTakeInMax or
			self.nCapacity ~= tData.nCapacity or
			self.nIntervalLev ~= tData.nIntervalLev)

	self.nSmallBlind = tConfigItem.nSmallBlind --小盲注数额
	self.nBigBlind = tConfigItem.nBigBlind  --大盲注数额(通常等于:小盲注x2)
	self.nBuyMin = tConfigItem.nTakeInMin   --最小买入
	self.nBuyMax = tConfigItem.nTakeInMax   --最大买入
	self.nEnterMin = self.nBigBlind         --最小进入(玩家必须满足最小进入才能开始游戏)
	self.nCapacity = tData.nCapacity        --能供玩游戏的座位数
	self.isConfigNotSet = false
	self.nIntervalLev = tData.nIntervalLev  --牌局间隔 1:短暂 2:适中 3:漫长
	if self.nIntervalLev ~= 1 and self.nIntervalLev ~= 2 and self.nIntervalLev ~= 3 then
		self:Print("Config nIntervalLev Error")
		self.nIntervalLev = 2
	end
	--记忆玩家最近使用的设置
	local tDataToSave = { nCapacity = tData.nCapacity, nConfigId = tData.nConfigId, nIntervalLev = tData.nIntervalLev }
	tPublicRedis.SetGameRecommendInfo(self.nGameId, nUserId, tDataToSave)

	self:_UpdateIntervalTime()

	if not isChange then --配置没反生改变则返回
		return
	end
	self:Print("Config Change")
	--广播配置变化
	self:_BroadCastDeZhouConfigNotify(tConfigItem)

	--重新调整玩家筹码余额
	local function _ReAdjustmentBalance(tSeatUser) --调整玩家可用筹码余额()
		local nBestTakeIn = 0
		if tSeatUser.nBalance > self.nBuyMax then
			nBestTakeIn = self.nBuyMax
		end
		self:_UserBalanceToGold(tSeatUser) --先解锁所有金币,再进行重新锁定
		if self:_InitUserTakeIn(tSeatUser, nBestTakeIn) then
			tSeatUser.nBalance = tSeatUser.nLockGoldInTable
			return true
		end
		return false
	end
	for nPos, tUser in pairs(self.arrUsers) do
		if tUser.nBalance < self.nBuyMin or tUser.nBalance > self.nBuyMax then
			if _ReAdjustmentBalance(tUser) then
				self:Print("reset user balance to :%.2f,nPos_%d", tUser.nBalance, nPos)
				self:_BroadCastDeZhouBalanceNotify(nPos, tUser.nBalance) --广播该玩家余额改变
			else
				self:_ForceStandUp(nPos, -1)
			end
		end
	end

	--俱乐部桌信息改变通知
	local tTableInfo = {}
	tTableInfo.nSmallBlind = self.nSmallBlind
	tTableInfo.nBigBlind = self.nBigBlind
	tTableInfo.nTakeInMin = self.nBuyMin
	tTableInfo.nTakeInMax = self.nBuyMax
	tTableInfo.nIntervalLev = self.nIntervalLev
	tTableInfo.nNowCnt = self.nUserCnt
	self:ClubTableInfoNotify(tTableInfo)
	return
end

function Table:DelayReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	self:Print("_DelayReq,nUserId:%d isInsure:%s", nUserId, tostring(tData.isInsure or false))

	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("DelayReq Fail, can not find user_%d in player seat", nUserId)
		return
	end
	self:_CancelAuto(tUser) --取消托管
	tUser.isHaveOp = true --当局是否有操作
	local isInsure = tData.isInsure
	local tOperation
	if not isInsure then
		tOperation = tUser.tOperation
		if tOperation == nil then
			self:Print("DelayReq Fail,tOperation is nil")
			return
		end
	end

	if isInsure then
		if tUser.nInsureDelayCount + 1 > 5 then
			self:Print("_DelayReq nUserId_%d  nInsureDelayCount:%d  超5次了", nUserId, tUser.nInsureDelayCount)
			return
		end
	else
		if tUser.nDelayCount + 1 > 5 then
			self:Print("_DelayReq nUserId_%d  nDelayCount:%d  超5次了", nUserId, tUser.nDelayCount)
			return
		end
	end
	local nDelayCost
	if isInsure then
		nDelayCost = self:_GetInsureDelayCost(tUser.nInsureDelayCount)
	else
		--延时操作花费
		nDelayCost = self.arrDelayCost[tUser.nDelayCount + 1]
	end
	if nDelayCost == nil then
		self:Print("DelayReq Fail,nDelayCost is nil")
		return
	end

	--扣金币
	if nDelayCost > 0 then
		nDelayCost = publicApi.Ceil_n(nDelayCost, 2)
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nOpDelay
		if not tPubUser.ChangeUserTreasure({ nUserID = nUserId, nItemID = 1, nDel = -nDelayCost, nSourceType = nSourceType, nNoNotice = true, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or "" }) then
			self:_SendToSlave(sReturnKey, "DelayRsp", {
				nUserId = nUserId,
				nRlt = 1,
				nDelayCost = nDelayCost,
				isInsure =
					isInsure
			}) --金币不足	
			return
		end
		tUser.nGold = tUser.nGold - nDelayCost
		self:_SendToSlave(sReturnKey, "GoldNotify", { nUserId = nUserId, nGold = self:GetUserTableGold(tUser, nUserId) })
	end

	--延长超时时间
	local nAddTime = Define.nAddTime --延时增加的时间 秒
	local nNow = os.time()
	local nElapse = nNow - tUser.nGetRightTime
	assert(nElapse >= 0)
	local nRemain = tUser.nOpLong - nElapse
	nRemain = math.max(nRemain, 0)
	local nNewOpLong = nRemain + nAddTime
	tUser.nGetRightTime = nNow
	tUser.nOpLong = nNewOpLong
	if isInsure then
		tUser.nInsureDelayCount = tUser.nInsureDelayCount + 1
	else
		tUser.nDelayCount = tUser.nDelayCount + 1
	end
	if isInsure then
		nRemain = self.nInsurePlayers[nUserId] - nNow
		tBase.Log("nRemain:%d self.nInsurePlayers[nUserId]:%s", nRemain, self.nInsurePlayers[nUserId])
		self.nInsurePlayers[nUserId] = self.nInsurePlayers[nUserId] + nAddTime

		tBase.Log("22 nRemain:%d self.nInsurePlayers[nUserId]:%s", nRemain, self.nInsurePlayers[nUserId])
		-- 更新公共结束时间为所有玩家中的最大值
		local maxEndTime = 0
		for userId, endTime in pairs(self.nInsurePlayers) do
			if endTime > maxEndTime then
				maxEndTime = endTime
			end
		end
		self.nInsureStageEndTime = maxEndTime
		nNewOpLong = self.nInsureStageEndTime - nNow
		tBase.Log("maxEndTime:%d nNewOpLong:%d", maxEndTime, nNewOpLong)
		if #self.arrCommunityCards == 3 then
			self:ToEndInsurOfFlopAfter(nNewOpLong)
		elseif #self.arrCommunityCards == 4 then
			self:ToEndInsurOfTurnAfter(nNewOpLong)
		end
	else
		self:_ToOpForTimeOutUser(nNewOpLong, nSitId)
	end

	local nNextCost
	if isInsure then
		nNextCost = self:_GetInsureDelayCost(tUser.nInsureDelayCount)
		if tUser.nInsureDelayCount + 1 > 5 then
			nNextCost = -1
		end
	else
		nNextCost = self.arrDelayCost[tUser.nDelayCount + 1]
		if tUser.nDelayCount + 1 > 5 then
			nNextCost = -1
		end
	end
	nNextCost = nNextCost or -1
	--成功回复
	self:_SendToSlave(sReturnKey, "DelayRsp",
		{
			nOpLong = nNewOpLong,
			nGetRightTime = nNow,
			nUserId = nUserId,
			nRlt = 0,
			nDelayCost = nNextCost,
			isInsure =
				isInsure,
			nInsureDelayCount = tUser.nInsureDelayCount
		})
	--有人延时成功广播
	self:_BroadCastToSlaves("DelayNotify",
		{ nPos = nSitId, nSeconds = nAddTime, nRemain = nNewOpLong, isInsure = isInsure, resRemain = nRemain })
end

--从服玩家离开
function Table:OnSlaveUserUp(tJsonData)
	self:_DoSnapshoot(tJsonData.nUserId) --清空总览快照
	self.tTableOverview:UserLeave(tJsonData.nUserId)
	-- self:TaxByTableRateSettle(tJsonData.nUserId,tJsonData.isAndroid)
	if (not tJsonData.isAndroid) and self:MatchRoomId() == 0 then
		self:SetClose(TableCloseReason.nTestTableUserLeave)
	end
end

--操作请求(来自从服)
function Table:DeZhouOpReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("DeZhouOpReq can not find user_%d in player seat", nUserId)
		return
	end
	self:_CancelAuto(tUser)        --取消托管
	tUser.isHaveOp = true          --当局是否有操作

	local nOpButton = tData.nOpButton --1:"按钮1" 2:"按钮2" 3:"按钮3"
	local nRaise = tData.nRaise or 0 --nOpButton为3且有加注权时有效. >0:表示具体的加注值, <0:可快速操作的选项(见操作权信息定义)
	self:Print("DeZhouOpReq,nSitId:%d nOpButton:%.2f nRaise:%.3f", nSitId, nOpButton, nRaise)
	nRaise = publicApi.Floor_1(nRaise)

	if self.nStage ~= TableState.nPlaying then
		self:Print("Fail,Not Playing nUserId:" .. nUserId)
		return
	end
	if tUser.nStatus ~= UserStatus.nThinking then
		self:Print("Fail,Not nThinking nUserId:" .. nUserId)
		return
	end
	local tOperation = tUser.tOperation
	if tOperation == nil then
		self:Print("Fail,tOperation is nil nUserId:" .. nUserId)
		return
	end
	assert(tOperation ~= nil)
	if nOpButton == 3 and tOperation.nOpC == UserOp.nRaiseBan then
		self:Print("Fail,nRaiseBan nUserId:" .. nUserId)
		return
	end
	local nOp = nil
	local nCallValue = 0 --跟注值

	if nOpButton == 1 then
		nOp = tOperation.nOpA
	elseif nOpButton == 2 then
		nOp = tOperation.nOpB
	elseif nOpButton == 3 then
		nOp = tOperation.nOpC
	else
		self:Print("Fail,nOpButton Not Define nUserId:" .. nUserId)
		return
	end
	if GreaterThan(nOp, 0) then
		nCallValue = nOp
		nOp = UserOp.nCall
	end
	--弃牌
	if nOp == UserOp.nFold then
		self:DoOpForUser(nSitId, UserOp.nFold, nil)
		return
	end
	--AllIn
	if nOp == UserOp.nAllIn then
		self:DoOpForUser(nSitId, UserOp.nAllIn, nil)
		return
	end
	--看牌(过)
	if nOp == UserOp.nPass then
		self:DoOpForUser(nSitId, UserOp.nPass, nil)
		return
	end
	--跟注
	if nOp == UserOp.nCall then
		self:DoOpForUser(nSitId, UserOp.nCall, nCallValue)
		return
	end
	--加注
	if nOp == UserOp.nRaise then
		assert(tOperation.tRaiseChoice ~= nil)
		if LessThan(nRaise, 0) then
			if not _IsHaveEle(tOperation.tRaiseChoice.arrQuickRaise, nRaise) then
				self:Print("Fail,Quick nRaise option Not Support nUserId:" .. nUserId)
				return
			end
			nRaise = self:_QuickOptionToBetValue(nRaise, tUser.nBalance)
			self:Print("Turn QuickOption ToBetValue:%.2f", nRaise)
		end

		if GreaterThan(nRaise, tUser.nBalance) then
			self:Print("nRaise:%.2f LimitTo:%.2f", nRaise, tUser.nBalance)
			nRaise = tUser.nBalance
		end

		if GreaterOrEqual(nRaise, 0) and not (GreaterOrEqual(nRaise, tOperation.tRaiseChoice.nMin) and LessOrEqual(nRaise, tOperation.tRaiseChoice.nMax)) then
			self:Print("Fail,nRaise Out of range,[%.2f,%.2f]", tOperation.tRaiseChoice.nMin, tOperation.tRaiseChoice
				.nMax)
			return
		end
		assert(LessOrEqual(nRaise, tUser.nBalance))
		if Equal(nRaise, tUser.nBalance) then
			self:DoOpForUser(nSitId, UserOp.nAllIn, nil)
		else
			self:Print("nRaise:%.2f", nRaise)
			self:DoOpForUser(nSitId, UserOp.nRaise, nRaise)
		end
	end
end

--预操作请求(来自从服)
--20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx -23:结束后亮牌 -24:亮牌
function Table:DeZhouPreOpReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("DeZhouPreOpReq can not find user_%d in player seat", nUserId)
		return
	end
	self:Print("DeZhouPreOpReq nOpId:%.2f isOn:%s", tData.nOpId, tostring(tData.isOn))

	tUser.isHaveOp = true   --当局是否有操作
	if tData.nOpId == -24 then --亮牌操作
		self:_SendToSlave(sReturnKey, "DeZhouPreOpRsp",
			{ nUserId = nUserId, nRlt = 0, nOpId = tData.nOpId, isOn = tData.isOn, sErr = "succee" })
		if not (self.nStage == TableState.nSettle and not tUser.isShowCardWhenEnd) then
			return
		end
		tUser.isShowCardWhenEnd = true
		for _, v in ipairs(self.tDealCardInfo or {}) do
			if v.nSitId == nSitId then v.isShowCardWhenEnd = true end
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
	local tOption = nil
	for _, item in ipairs(tUser.tPreOpOption.arrOption) do
		if Equal(item.nOpId, tData.nOpId) or (GreaterThan(item.nOpId, 0) and GreaterThan(tData.nOpId, 0)) then -- >0:跟xxx
			tOption = item
			break
		end
	end
	if not tOption then
		self:Print("DeZhouPreOpReq fail,can not find option")
		return
	end
	tOption.isOn = tData.isOn

	--确保同时只能有一个预操作选项状态为true
	if tOption.isOn then
		for _, item in ipairs(tUser.tPreOpOption.arrOption) do
			if not Equal(item.nOpId, tOption.nOpId) then
				item.isOn = false
			end
		end
	end
	--是否结束后亮牌
	if tOption.nOpId == -23 then
		tUser.isShowCardWhenEnd = tOption.isOn
	end

	self:Print("DeZhouPreOpReq succee")
	local DeZhouPreOpRsp = {}
	DeZhouPreOpRsp.nUserId = nUserId
	DeZhouPreOpRsp.nRlt = 0           --0:成功 其它:错误码
	DeZhouPreOpRsp.nOpId = tOption.nOpId --(成功时有效)请求的操作
	DeZhouPreOpRsp.isOn = tOption.isOn --(成功时有效)操作状态 true:选中成功 false:取消成功
	DeZhouPreOpRsp.sErr = "succee"    --(失败时有)失败提示
	self:_SendToSlave(sReturnKey, "DeZhouPreOpRsp", DeZhouPreOpRsp)
end

function Table:_IsBanUserStanpUp(tUser)
	if tUser.nStatus == UserStatus.nLooker then
		return false
	end
	if tUser.nStatus == UserStatus.nFold then
		return false
	end
	if not tUser.isNeedSettle then
		return false
	end
	-- 保险阶段也站起
	-- local tInsur = self.tFlopAfterInsur or self.tTurnAfterInsur
	-- if tInsur then
	-- 	return true
	-- end
	return false
end

--站起请求(来自从服)
function Table:DeZhouStanpUpReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)

	if not nSitId then
		self:Print("not in Player seat")
		self:SendFailNotifyV2(sReturnKey, nUserId, 16, "not in Player seat")
		return
	end
	if self:_IsBanUserStanpUp(tUser) then
		self:Print("ban user stanpUp")
		return
	end

	self:Print("DeZhouStanpUpReq,nSitId:%d nUserId:%d", nSitId, nUserId)
	self:_SetLeaveSeat(nSitId)
end

-- 返回大厅
function Table:_IsBanUserLeave(tUser)
	if tUser.nStatus == UserStatus.nLooker then
		return false
	end
	if not tUser.isNeedSettle then
		return true
	end
	local tInsur = self.tFlopAfterInsur or self.tTurnAfterInsur
	if tInsur then
		return true
	end
	return false
end

--返回大厅请求(来自从服)
function Table:DeZhouBackToLobbyReq(tData, sReturnKey)
	self:Print("DeZhouBackToLobbyReq,sReturnKey%s", sReturnKey)
	local nUserId = tData.nUserId
end

--根据gps判断是否存在距离过近的玩家
function Table:IsHaveNearUser(tGps)
	local nLongitudeA = tGps.nLongitude
	local nLatitudeA = tGps.nLatitude
	self:Print("nLongitudeA:%f ,nLatitudeA:%f", nLongitudeA, nLatitudeA)

	for _, tUser in pairs(self.arrUsers) do
		if (not tUser.isAndroid) and tUser.tGps then
			local nLongitudeB = tUser.tGps.nLongitude
			local nLatitudeB = tUser.tGps.nLatitude
			self:Print("nLongitudeB:%f ,nLatitudeB:%f", nLongitudeB, nLatitudeB)
			local nDistance = GetDistance(nLongitudeA, nLatitudeA, nLongitudeB, nLatitudeB)
			nDistance = nDistance * 1000 --转换为 米
			if nDistance <= 200 then --200米以内视作距离过近
				return true
			end
		end
	end
	return false
end

--判断是否有相同IP玩家
function Table:IsHaveSaveIp(nUserId)
	local sIp = tPubUser.GetUserIP(nUserId)
	local sDotIp = publicApi.Dword2String(tonumber(sIp) or 0)
	self:Print("nUserId_%d nIp:%s sIp:%s", nUserId, sIp, sDotIp)
	for _, tUser in pairs(self.arrUsers) do
		if (not tUser.isAndroid) then
			local ssIp = tPubUser.GetUserIP(tUser.nUserId)
			local ssDotIp = publicApi.Dword2String(tonumber(ssIp) or 0)
			self:Print("nUserId_%d nIp:%s sIp:%s", tUser.nUserId, ssIp, ssDotIp)
			if tonumber(sIp) == tonumber(ssIp) then
				return true
			end
		end
	end
	return false
end

--检查入池率限制 true:通过 false:不通过
function Table:_CheckPoolEntryRate(nUserId, isRobot)
	if isRobot then
		return true
	end
	local data = {
		nClubId = self.nClubId,
		nGameId = self.nGameId,
		nGoldType = self.nGoldType,
		nSmallBlind = self.nSmallBlind,
		nBigBlind = self.nBigBlind,
		nZhuaTou = self.nZhuaTou,
		nPreAnte = self.nPreAnte
	}
	local tInfo = tPublicRedis.GetUserTexaStatistic(nUserId, data)
	if self.nPoolHands > 0 and tInfo.nPlayCount < self.nPoolHands then
		return false, 41
	end
	if self.nPoolEntryRate <= 0 then
		return true
	end
	if tInfo.nPlayCount <= self.nPoolEntryRateHands then
		return true
	end
	local nRate = tInfo.nInPoolCount / tInfo.nPlayCount
	if (nRate * 100) < self.nPoolEntryRate then
		return false, 35
	end
	self:Print("_CheckPoolEntryRate,nUserId:%d nPlayCount_%d  nRate_%.2f nPoolEntryRate_%.2f "
	, nUserId, tInfo.nPlayCount, nRate * 100, self.nPoolEntryRate)

	return true
end

--坐下请求(来自从服)
function Table:DeZhouSitDownReq(tData, sReturnKey)
	local nUserId = tData.nUserId
	local tUserInfo = tData.tUserInfo
	self:Print("DeZhouSitDownReq,nPos:%d", tData.nPos)

	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if nSitId then
		self:Print("already in Player seat")
		self:SendFailNotifyV2(sReturnKey, nUserId, 15, "already in Player seat")
		return
	end
	if self.isConfigNotSet then
		self:Print("table ConfigNotSet")
		self:SendFailNotifyV2(sReturnKey, nUserId, 19, "table no config")
		return
	end

	--gps限制
	if self.isGPSLimit then
		if not tUserInfo.tGps then
			self:Print("lack of gps info")
			self:SendFailNotifyV2(sReturnKey, nUserId, 31, "lack of gps info")
			return
		end
		if self:IsHaveNearUser(tUserInfo.tGps) then
			self:Print("exist near gps")
			self:SendFailNotifyV2(sReturnKey, nUserId, 32, "exist gps near")
			return
		end
	end
	--ip限制
	if self.isIPLimit then
		if self:IsHaveSaveIp(nUserId) then
			self:Print("exist same ip")
			self:SendFailNotifyV2(sReturnKey, nUserId, 34, "exist same ip")
			return
		end
	end

	--入池率限制检查
	local ok, code = self:_CheckPoolEntryRate(nUserId)
	if not ok then
		self:Print("PoolRate too low")
		self:SendFailNotifyV2(sReturnKey, nUserId, code, "PoolRate too low")
		return
	end

	local nPosForPlay = nil
	if tData.nPos == 0 then
		nPosForPlay = self:_FindAPosForPlay()
	elseif self:_IsPlayerPos(tData.nPos) and self:_GetUser(tData.nPos) == nil then
		nPosForPlay = tData.nPos
	else
		self:Print("nPos illegal")
		self:SendFailNotifyV2(sReturnKey, nUserId, 14, "nPos illegal")
		return
	end
	if nPosForPlay == nil then
		self:Print("_FindAPosForPlay Fail")
		self:SendFailNotifyV2(sReturnKey, nUserId, 14, "_FindAPosForPlay Fail")
		return
	end

	local tSeatUser, nSitId, nCode = self:OnUserEnter(tUserInfo, nPosForPlay)
	if not tSeatUser then
		self:SendFailNotifyV2(sReturnKey, nUserId, nCode, "Enter Fail")
		return
	end
end

local function loadTestCard()
	if true then -- 开发环境
		package.loaded["AAATestCard"] = nil
	end
	return require("AAATestCard")
end

function Table:_ToCutCardEnd(nSeconds, isCutEnd)
	if nSeconds < 1 then
		nSeconds = 1
	end
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.StartGame, self, isCutEnd)
	self:_UpdateHeartTick()
end

function Table:_CostUserGold(nUserId)
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("_CostUserGold Fail, can not find user_%d in player seat", nUserId)
		return
	end
	local conf = self:_GetCardCost(3)
	if not tonumber(conf.open) == 1 then
		self:Print("_CostUserGold Fail, not open user_%d", nUserId)
		return
	end
	local nCost = tonumber(conf.nCost) or 0
	nCost = publicApi.Ceil_n(nCost, 2)
	if nCost > 0 then
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nCutCard
		self:Print("_CostUserGold nSourceType:%d self.nGameId:%d", nSourceType, self.nGameId)
		if not tPubUser.ChangeUserTreasure({ nUserID = nUserId, nItemID = 1, nDel = -nCost, nSourceType = nSourceType, nNoNotice = true, sTableId = self.sTableId or "", sPaiJuId = self.sPaiJuId or "" }) then
			self:Print("gold not enought")
			return
		end
		tUser.nGold = tUser.nGold - nCost
	end
	return true
end

function Table:StartGame(isCutEnd)
	self:Print("StartGame, isCutEnd:%s", tostring(isCutEnd))
	if isCutEnd then
		self.isCutting = false
	else
		if self.isCutting then
			local ok = self:_CostUserGold(self.nCutUserInfo.nCutUserId)
			if ok then
				self:_BroadCastToSlaves("CardOpNotify",
					{
						nOpId = 3,
						nSitId = self.nCutUserInfo.nSitId,
						nIndex = 0,
						nRemain = 1,
						nUserId = self.nCutUserInfo
							.nCutUserId,
						nName = self.nCutUserInfo.nName
					})
				self.nSettleEndTime = os.time() + Define.nCutTime
				self:_ToCutCardEnd(Define.nCutTime, true)
				return
			end
		end
	end
	self.nJuShu = self.nJuShu + 1
	self:Print("StartGame,nFee:%.2f,nTax:%.2f nItemId:%d", self.nFee, self.nTax, self.nItemId)
	self:_ResetTable()
	self:_ResetUsers()
	self:_UpdateIntervalTime()
	self:_UpdatePriceList(true)
	-- self:_UpdateAiUrl()

	--锁定玩家入场必要的金币(一个辅助函数)
	local function _DoLockGold(tUser)
		local nBuyTo = 0
		if tUser.nIsAutoBuy == 1 then                              --自动补充时
			nBuyTo = Equal(tUser.nLockGoldInTable, 0) and self.nBuyMax or 0 --只有在剩余筹码为0时才会触发 (自动补充到最大买入)
		else
			nBuyTo = tUser.nBuyTo + tUser.nBalance
			tUser.nBuyTo = 0 --如非设置每局自动买入,则设置的买入只生效一次	
		end
		local isSuccee, nNewLock = self:_InitUserTakeIn(tUser, nBuyTo, 0)
		if not isSuccee then
			return false
		end
		tUser.nChipBuy = publicApi.Round_n(nNewLock, 0)
		return true
	end

	--尝试执行带出操作
	local function _TryDoTakeOut(tUser)
		if tUser.nTakeOutWant == 0 then
			return
		end
		local nCanTakeOutMax = math.max(tUser.nLockGoldInTable - self.nEnterMin, 0)
		local nTakeOut = math.min(nCanTakeOutMax, tUser.nTakeOutWant)
		local isSuccee = self:Gold_UnLock(tUser, nTakeOut)
		assert(isSuccee)
		tUser.nBalance = tUser.nLockGoldInTable
		tUser.nTakeOutWant = 0
	end

	--确定可以参与本次牌局的玩家
	--self:_ForceStandUp(nPos,13) --强制玩家站起(13为金币不足的错误码)
	local arrPosPartIn = {}
	local arrUserPartIn = {}
	for nPos, tUser in pairs(self.arrUsers) do
		if (not tUser.isRetain) then
			_TryDoTakeOut(tUser) --尝试执行玩家设置的带出操作
			_DoLockGold(tUser) --尝试补充筹码
			if GreaterThan(tUser.nLockGoldInTable, 0) then
				table.insert(arrPosPartIn, nPos)
				table.insert(arrUserPartIn, tUser)
				tUser.nBalance = tUser.nLockGoldInTable --初始化玩家可用筹码
				self:Print("PartInUser_%d,nPos_%d,nNowLock:%.3f,nBalance:%.3f isAndroid:%s",
					tUser.nUserId, nPos, tUser.nLockGoldInTable, tUser.nBalance, tostring(tUser.isAndroid))
			else
				self:_ForceStandUp(nPos, 13)
			end
		end
	end

	--判断人数是否足够开始游戏
	assert(#arrPosPartIn == #arrUserPartIn)
	if #arrPosPartIn < 2 then
		self:Print("StartGame Fail,PartIn UserCnt not enough")
		return
	end
	if self.noticeOpenTimes == 0 then
		pcall(function() self:NoticeOpen() end)
		self.noticeOpenTimes = self.noticeOpenTimes + 1
	end
	self.arrPosPartIn = arrPosPartIn
	self.nPartInCount = #arrPosPartIn --牌局开始时，参与牌局的玩家数量

	--牌局id生成
	self.sPaiJuId = tPubUser.CreatePaiJuID()
	self.tStatistic:Init(self.nBigBlind, self.nSmallBlind, self.nPreAnte, self.nZhuaTou, self.preAnteOdd)
	self.tTableOverview:PaiJuStart()

	local first = false
	local handsDict = {}
	local arrUser = {}

	local TestCard = loadTestCard()
	local tCard = nil
	if TestCard.LonngCard and #TestCard.LonngCard > 0 then
		tCard = TestCard.LonngCard
	end
	if self.nZhuaTou == 40 then
		tCard = nil
	end
	if self.preTPile ~= nil then
		self.tPile = self.preTPile
		self.preTPile = tAlg.NewPile(nil, tCard)
	else
		first = true
		self.tPile = tAlg.NewPile(nil, tCard)
		self.preTPile = tAlg.NewPile(nil, tCard)
	end
	--回顾记录
	self.tReview:Init(self.sPaiJuId, self.nSmallBlind, self.nBigBlind, self.nCapacity, self.nOperateTime, self.nZhuaTou)
	local rds = tRedisCahche._Redis()
	for _, v in ipairs(arrUserPartIn) do
		-- 发送stream
		if rds then
			rds:xadd(
				"game_event_stream",
				"MAXLEN", "~", 10000,
				"*",
				"uid", tostring(v.nUserId),
				"sPaiJuId", tostring(self.sPaiJuId)
			)
			-- rds:xadd("game_event_stream", "*", "uid", tostring(v.nUserId) , "sPaiJuId", self.sPaiJuId)
		end
		self.tReview:AddUser(v.nUserId, v.nSitId, v.sFaceId, v.sName, v.nSex, v.sShopAccount, v.nBalance)
		local nTakeInAdd, nnDex = self.tTableOverview:UserPartIn(v.nUserId, v.sName, v.nLockGoldInTable, v.sFaceId,
			v.nSitId)
		self.tStatistic:SetIsAndroid(v.nUserId, v.isAndroid, nTakeInAdd, v.sFaceId, v.sName)
		self:Print("TestV PairtInUser_%d isAndroid:%s", v.nUserId, tostring(v.isAndroid))
		table.insert(arrUser, { id = v.nUserId, nSitId = v.nSitId, sFaceId = v.sFaceId })
		tPenaltyManager:initJoinTablePlayCnt(v.nUserId, self.sTableId, self.nPlayCnt, self.sPaiJuId)
		taxHelp:updatePaiJuid(v.nUserId, self.sTableId, self.sPaiJuId)
		if not v.isAndroid then
			v.nPlayCnt = v.nPlayCnt + 1
			tPenaltyManager:addPlayCnt(v.nUserId, self.sTableId)
		end
	end

	local nCutIndex = self.nCutUserInfo.nCutIndex or 0
	--使用预设置牌模式(预先发好公共牌和各玩家底牌)  改为3个公共牌
	local arrPreSetCommCard, arrUsersHoleCard = tAlg.PreSetCards(#self.arrPosPartIn, self.tPile, nCutIndex)
	if self.arrPreSetCommCard == nil or #self.arrPreSetCommCard == 0 then
		self.arrPreSetCommCard = arrPreSetCommCard
		-- assert(#arrPreSetCommCard ==5)
	end
	for _, tUser in ipairs(arrUserPartIn) do
		local item = table.remove(arrUsersHoleCard) or {}
		if tUser.arrPreSetHoleCard == nil or #tUser.arrPreSetHoleCard == 0 then
			tUser.arrPreSetHoleCard = item.arrHoleCard
			assert(#tUser.arrPreSetHoleCard == self.nHoleCardCnt)
			tUser.nRank = item.nRank
		end
	end
	--免费试玩次数加1(针对试玩房)
	for _, tUser in ipairs(arrUserPartIn) do
		if (not tUser.isAndroid) and tUser.isAddFreeTimeIfStart then
			tPublicRedis.IncrUserTryPlayCntOfTexas(tUser.nUserId) --免费试玩次数加1
			tUser.isAddFreeTimeIfStart = false
		end
	end
	--控牌接口实现
	-- local arrRealUserId ={}
	-- for _,tUser in ipairs(arrUserPartIn) do
	-- 	if not tUser.isAndroid then
	-- 		table.insert(arrRealUserId,tUser.nUserId)
	-- 	end
	-- end
	-- if #arrRealUserId ==#arrUserPartIn then		--全是真人时，不控牌
	-- 	self:Print("IsNeedControlBR Return:nUserId_0 nCtrlType_0,all is RealUser")
	-- else
	-- 	local nUserId,nCtrlType =self:_IsNeedControl(arrRealUserId)
	-- 	self:Print("IsNeedControlBR Return:nUserId_%d nCtrlType_%d",nUserId,nCtrlType)
	-- 	if (nCtrlType==2 or nCtrlType==3) and nUserId>0 then
	-- 		local isSuccee =self:_TryLetAndroidWin(arrUserPartIn,nUserId)	--优先将最大牌转移到机器人上
	-- 		self:Print("_TryLetAndroidWin:%s",tostring(isSuccee))
	-- 		self.isControl =nCtrlType
	-- 		self.nControlUserId =nUserId
	-- 	elseif nCtrlType==4 and nUserId>0 then
	-- 		local isSuccee =self:_TryLetRealUserWin(arrUserPartIn,nUserId)	--优先将最大牌转移到真人上
	-- 		self:Print("TryLetRealUserWin:%s",tostring(isSuccee))
	-- 		self.isControl =nCtrlType
	-- 		self.nControlUserId =nUserId
	-- 	end
	-- end

	--初始化牌堆;给参与牌局的玩家发两个底牌,并设置其状态为 '等待操作权中'
	-- self.tPile =tAlg.NewPile()
	self.arrPreSetCommCardEffect = self.arrPreSetCommCard
	self.arrPreSetCommCard = {}
	for _, tUser in ipairs(arrUserPartIn) do
		tUser.arrHoleCards = self.tPile:GetCards(self.nHoleCardCnt, tUser.arrPreSetHoleCard, true)
		self:_SetUserStatus(tUser, UserStatus.nWaitForOp)
		tUser.tCardType = tAlg.DeZhouCardType(tUser.arrHoleCards, self.arrCommunityCards)
		tUser.isNeedSettle = true
		if not tUser.isAndroid then
			self.isHaveRealUser = true
		end
		handsDict[tUser.nUserId] = tUser.arrHoleCards
		tUser.isShowHoleCard = (self.isDelayLook == false) --延迟看牌时，游戏开始时暂不公布玩家底牌,直到玩家获得第一次操作权
		tUser.nAiType = math.random(0, 2)            --随机一个Ai类型;0一般 1进取 2保守
	end
	handsDict[3] = self.nCapacity
	handsDict[2] = self.tPile:GetCutIndex()
	-- handsDict[1] = _CopyArr(self.arrPreSetCommCardEffect)
	self.hashHelper:GenTableHash(self.tPile, self.preTPile, self.sPaiJuId, self.nJuShu, handsDict, arrUser, first)
	self._RemoveNotPartUser(handsDict)

	self.isCutting = false
	self.nCutUserInfo = {}

	self:Print("arrPreSetCommCardEffect:%s", Define.CardsToStr(self.arrPreSetCommCardEffect))
	self.arrPreSetCommCardCp = _CopyArr(self.arrPreSetCommCardEffect)

	--确定庄家位置
	if self.nBankerPos then
		self.nBankerPos = self:_NextGainRightsPos(self.nBankerPos)
	else
		local nRandNum = math.random(1, #self.arrPosPartIn)
		self.nBankerPos = self.arrPosPartIn[nRandNum]
	end
	assert(self.nBankerPos ~= nil)
	assert(_IsHaveEle(self.arrPosPartIn, self.nBankerPos))
	self.tReview:SetBankerPos(self.nBankerPos) --回顾记录
	--记录一个有序的玩家数组,服务于ai请求
	self.arrAiUser = {}
	local nNowPos = self.nBankerPos
	for i = 1, self.nCapacity do
		local item = self:_GetAiUser(nNowPos)
		if item and _IsHaveEle(self.arrPosPartIn, nNowPos) then
			table.insert(self.arrAiUser, item)
		end
		nNowPos = self:_NextPos(nNowPos)
		if nNowPos == self.nBankerPos then
			break
		end
	end

	--确定大小盲玩家位置
	local nSmallBlindPos, nBigBlindPos, nZhuaTouPos = nil, nil, nil
	if #self.arrPosPartIn == 2 then
		nSmallBlindPos = self.nBankerPos
		nBigBlindPos = self:_NextGainRightsPos(nSmallBlindPos)
	else
		nSmallBlindPos = self:_NextGainRightsPos(self.nBankerPos)
		nBigBlindPos = self:_NextGainRightsPos(nSmallBlindPos)
	end
	assert(nSmallBlindPos ~= nil and nBigBlindPos ~= nil)
	assert(_IsHaveEle(self.arrPosPartIn, nSmallBlindPos))
	assert(_IsHaveEle(self.arrPosPartIn, nBigBlindPos))


	--前注下注
	if self.nPreAnte > 0 then
		-- self:Print("Do PreAnte:%.2f self.preAnteOdd:%d",self.nPreAnte, self.preAnteOdd)
		for _, nPos in ipairs(self.arrPosPartIn) do
			local nPreAnte = self.nPreAnte
			-- if self.nBankerPos == nPos and self.preAnteOdd > 0  andthen
			-- 	nPreAnte = nPreAnte * self.preAnteOdd
			-- end
			local nAcBet = self:_TryDoBet(nPos, nPreAnte, GoldCReason.nPreBet)
			self.tReview:PreAnteBet(nPos, nAcBet) --回顾记录
		end
	end

	--大小盲玩家下注
	self:Print("Do SmallAndBigBlind")
	local nAcBetSmall = self:_TryDoBet(nSmallBlindPos, self.nSmallBlind, GoldCReason.nSmallBlind)
	local nAcBetBig = self:_TryDoBet(nBigBlindPos, self.nBigBlind, GoldCReason.nBigBlind)
	self.tReview:BlindBet(nSmallBlindPos, nAcBetSmall, nBigBlindPos, nAcBetBig) --回顾记录

	--强制盲注
	local nForceBlindPos = nil
	local nAcForceBet = 0
	if #self.arrPosPartIn >= 3 and self.isForceBlind and self.nZhuaTou > 0 then
		self:Print("Do ForceBlind")
		nForceBlindPos = self:_NextGainRightsPos(nBigBlindPos)
		nAcForceBet = self:_TryDoBet(nForceBlindPos, self.nZhuaTou, GoldCReason.nZhuaTou)
		self.nIsZhuaTouBet = true
		--回顾记录
		self.tReview:ForceBlind(nForceBlindPos, nAcForceBet)
	end
	-- 抓头下注
	-- if nZhuaTouPos and self.nZhuaTou > 0 and _IsHaveEle(self.arrPosPartIn, nZhuaTouPos) then
	-- 	local nBet = self:_TryDoBet(nZhuaTouPos,self.nZhuaTou) --抓头玩家下注
	-- 	local tZhuaTouUser= self:_GetUser(nZhuaTouPos)
	-- 	assert(tZhuaTouUser~=nil)
	-- 	if Equal(tZhuaTouUser.nBalance,0) then
	-- 		self:_SetUserStatus(tZhuaTouUser,UserStatus.nAllIn)
	-- 	end
	-- 	self.tReview:ZhuaTouBet(nZhuaTouPos, nBet) --回顾记录
	-- end

	--将筹码为0的玩家设为AllIn状态
	self.nFirstBet = 0
	local arrNotAllInUsers = {}
	for _, tUser in ipairs(arrUserPartIn) do
		if Equal(tUser.nBalance, 0) then
			self:_SetUserStatus(tUser, UserStatus.nAllIn)
		else
			table.insert(arrNotAllInUsers, tUser)
		end
		self.nFirstBet = self.nFirstBet + tUser.nBetSum
		self:GetUserInsureState(tUser)
	end
	--如果只剩一个玩家没AllIn,且该玩家是下注最高的人，则可以马上发牌结算
	local isShouldEnd = (#arrNotAllInUsers == 1 and Equal(arrNotAllInUsers[1].nBet, self.nTheHighestBet))

	--设置桌子游戏状态为 '开始'
	self:_SetGameStage(TableState.nPlaying)

	--初始化玩家"可预操作"选项
	self:_InitUsersPreOpOption()
	--初始化机器人难度
	local isAiHard = self:InitAiGrade()

	--广播游戏开始
	--按发牌顺序排序
	local arrPosPartInSort = self:_SortByDeal(self.arrPosPartIn, nSmallBlindPos)
	self:_BroadCastGameStartNotify(nSmallBlindPos, nBigBlindPos, arrPosPartInSort, nForceBlindPos, nAcBetSmall, nAcBetBig,
		nAcForceBet, nZhuaTouPos)

	--回顾记录
	for _, nPos in ipairs(arrPosPartInSort) do --self.arrPosPartIn
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		self.tReview:DealHoleCard(nPos, tUser.arrHoleCards, self:_GetCardType(tUser.tCardType))
	end

	--确定第一获得操作权的玩家,且给予其操作权
	--翻牌前 大盲的下一玩家首先获得操作权. 翻牌后庄家的下一玩家首先获得操作权,有抓头玩家时,抓头玩家的下一玩家首先获得操作权
	self.nFirstPos = (nForceBlindPos or nBigBlindPos)
	local nPosToGainRights = self:_NextGainRightsPos(self.nFirstPos)
	--assert(nPosToGainRights~=nil)				--这里有可能是nil,如果是，就发牌结算
	local nDelayT = 1.2
	if nPosToGainRights == nil or isShouldEnd then
		self:_ToNextRound(nDelayT)
	else
		self.nTheRightsEndPos = nPosToGainRights
		self.nUserIdLeader = self:_GetUserId(nPosToGainRights)
		self:_ToGiveRightsTo(nDelayT, nPosToGainRights)
	end
	self:Print("StartGame Succee,sPaiJuId:%s,isAiHard:%s", self.sPaiJuId, tostring(isAiHard))

	--桌子开始计时
	self:BeginTiming()
	self.nPlayCnt = self.nPlayCnt + 1
	self.nLatelyStartTime = os.time()
	self:ClubTableInfoNotify({ isStartGame = true })

	self.hashHelper:ChangeCurrent({ [6] = self.nBankerPos }, true)
	self.tReview:SetTableCost(self.nTableCost)
	--牌局写redis(以便后台实时查看与控牌)
	-- self:_WriteCurDetailToRedis()
	local info = {}
	for _, v in ipairs(arrUserPartIn) do
		table.insert(info, { nUserId = v.nUserId, sName = v.sName, nBalance = v.nBalance })
	end
	tPubUser.API_ChangeTable(self.sTableId, cjson.encode(info))
end

function Table:_GetInsurPos()
	if self.nTsureType == 1 then
		return self:_GetInsurPos_all()
	end
	return self:_GetInsurPos_one()
end

-- 修改 _GetInsurPos 函数，返回所有可以购买保险的玩家
function Table:_GetInsurPos_all()
	self:Print("_GetInsurPos Start")
	local arrPool = {}
	for _, v in ipairs(self.arrPoolInfo) do
		if #v.arrPosForm > 1 then -- 只保留有两人以上竞争的底池
			table.insert(arrPool, { nPool = v.nPool, arrPosForm = _CopyArr(v.arrPosForm) })
		end
	end
	if #arrPool == 0 then
		return nil
	end
	-- 由大到小排序
	local TemSort = function(itemA, itemB)
		return itemA.nPool > itemB.nPool
	end
	table.sort(arrPool, TemSort)
	local arrInsurPos = {} -- 改为返回数组，支持多个玩家
	-- 检查每个底池中的领先玩家
	for _, tPoolInfo in ipairs(arrPool) do
		local arrValPosCardType = {} -- 底池中的有效玩家牌型
		local arrValPos = {}
		for _, nPos in ipairs(tPoolInfo.arrPosForm) do
			local tUser = self:_GetUser(nPos)
			if tUser and tUser.nStatus ~= UserStatus.nLooker and tUser.nStatus ~= UserStatus.nFold then
				tUser.tCardType.nPos = nPos
				table.insert(arrValPosCardType, tUser.tCardType)
				table.insert(arrValPos, nPos)
			end
		end
		-- 如果有效玩家过多或不足，则不触发保险
		if #arrValPos > 3 or #arrValPos <= 1 then
			self:Print("Skip Insur: arrValPos:%d", #arrValPos)
			goto continue
		end
		-- 直接使用 arrValPosCardType 数组，不再检查 arrTheWinItem 的数量
		for _, tCardType in ipairs(arrValPosCardType) do
			local nInsurPos = tCardType.nPos -- 可以买保险的玩家位置
			-- 检查是否已经包含该玩家
			local alreadyExists = false
			for _, existingPos in ipairs(arrInsurPos) do
				if existingPos.nPos == nInsurPos then
					alreadyExists = true
					break
				end
			end
			if not alreadyExists then
				table.insert(arrInsurPos, {
					nPos = nInsurPos,
					arrValPos = arrValPos,
					nPool = tPoolInfo.nPool,
					tCardType = tCardType -- 保留牌型信息
				})
			end
		end
		::continue::
	end
	if #arrInsurPos == 0 then
		return nil
	end
	return arrInsurPos
end

-- 修改 _GetInsurPos 函数，返回所有可以购买保险的玩家
function Table:_GetInsurPos_one()
	self:Print("_GetInsurPos Start")
	local arrPool = {}
	for _, v in ipairs(self.arrPoolInfo) do
		if #v.arrPosForm > 1 then -- 只保留有两人以上竞争的底池
			table.insert(arrPool, { nPool = v.nPool, arrPosForm = _CopyArr(v.arrPosForm) })
		end
	end
	if #arrPool == 0 then
		return nil
	end
	-- 由大到小排序
	local TemSort = function(itemA, itemB)
		return itemA.nPool > itemB.nPool
	end
	table.sort(arrPool, TemSort)
	local arrInsurPos = {} -- 改为返回数组，支持多个玩家
	-- 检查每个底池中的领先玩家
	for _, tPoolInfo in ipairs(arrPool) do
		local arrValPosCardType = {} -- 底池中的有效玩家牌型
		local arrValPos = {}
		for _, nPos in ipairs(tPoolInfo.arrPosForm) do
			local tUser = self:_GetUser(nPos)
			if tUser and tUser.nStatus ~= UserStatus.nLooker and tUser.nStatus ~= UserStatus.nFold then
				tUser.tCardType.nPos = nPos
				table.insert(arrValPosCardType, tUser.tCardType)
				table.insert(arrValPos, nPos)
			end
		end
		-- 如果有效玩家过多或不足，则不触发保险
		if #arrValPos > 3 or #arrValPos <= 1 then
			self:Print("Skip Insur: arrValPos:%d", #arrValPos)
			goto continue
		end
		local arrTheWinItem = tAlg.TheWinCardType(arrValPosCardType)
		if #arrTheWinItem ~= 1 then
			self:Print("Skip Insur: arrTheWinItem cnt:%d", #arrTheWinItem)
			goto continue
		end
		local nInsurPos = arrTheWinItem[1].nPos -- 可以买保险的玩家位置
		-- 检查是否已经包含该玩家
		local alreadyExists = false
		for _, existingPos in ipairs(arrInsurPos) do
			if existingPos.nPos == nInsurPos then
				alreadyExists = true
				break
			end
		end
		if not alreadyExists then
			table.insert(arrInsurPos, {
				nPos = nInsurPos,
				arrValPos = arrValPos,
				nPool = tPoolInfo.nPool
			})
		end
		::continue::
	end
	if #arrInsurPos == 0 then
		return nil
	end
	return arrInsurPos
end

function Table:PrintPanel(tInsurPanelData)
	local arrRelevantUser = {}
	for _, v in ipairs(tInsurPanelData.arrRelevantUser) do
		local item = {}
		item.arrHoleCards = Define.CardsToStr(v.arrHoleCards)
		item.nOuts = v.nOuts
		item.nUserId = v.nUserId
		table.insert(arrRelevantUser, item)
	end

	local tTem = tInsurPanelData.tElseUserHoleCard or {}
	local tElseUserHoleCard = {}
	tElseUserHoleCard.arrOuts = Define.CardsToStr(tTem.arrOuts or {})
	tElseUserHoleCard.arrCard = Define.CardsToStr(tTem.arrCard or {})

	local tRemaining = {}
	tRemaining.arrOuts = Define.CardsToStr(tInsurPanelData.tRemaining.arrOuts)
	tRemaining.nPileCnt = tInsurPanelData.tRemaining.nPileCnt
	tRemaining.nOdds = tInsurPanelData.tRemaining.nOdds

	self:Print("Insur_CommunityCards:%s", Define.CardsToStr(tInsurPanelData.arrCommunityCards))
	self:Print("Insur_RelevantUser:%s", json.encode(arrRelevantUser))
	self:Print("Insur_ElseUserHoleCard:%s", json.encode(tElseUserHoleCard))
	self:Print("Insur_Remaining:%s", json.encode(tRemaining))
	self:Print("Insur_tPool:%s", json.encode(tInsurPanelData.tPool))
	self:Print("Insur_arrInsurancePlan:%s", json.encode(tInsurPanelData.arrInsurancePlan))
	self:Print("Insur_nInsurUserId:%d", tInsurPanelData.nInsurUserId)
	self:Print("Insur_nInsureMode:%d", tInsurPanelData.nInsureMode)
	self:Print("Insur_isMustBuy:%s", tostring(tInsurPanelData.isMustBuy))
	self:Print("Insur_isPossibleEq:%s", tostring(tInsurPanelData.isPossibleEq))
	self:Print("Insur_nInvestInThisPool:%s", tostring(tInsurPanelData.nInvestInThisPool))
	self:Print("Insur_arrOddsList:%s", json.encode(tInsurPanelData.arrOddsList or {}))
end

-- 修改 GetInsurPanelData 函数，支持多个玩家
function Table:GetInsurPanelData(arrInsurInfo, isFlopAfter)
	local arrPanelData = {}
	for _, insurInfo in ipairs(arrInsurInfo) do
		local nInsurPos = insurInfo.nPos
		local arrValPos = insurInfo.arrValPos
		local nMaxPool = insurInfo.nPool
		if self.nInsureMode == InsureMode.nLow then --低水保险
			local panelData, arrWinRate = self:GetInsurPanelData_Low(nInsurPos, arrValPos, nMaxPool, isFlopAfter)
			if panelData then
				table.insert(arrPanelData, {
					tPanelData = panelData,
					arrWinRate = arrWinRate
				})
			end
		elseif self.nInsureMode == InsureMode.nNormal then --常规保险
			if self.nInsureNormalType == 2 then
				local panelData, arrWinRate = self:GetInsurPanelData_Normal2(nInsurPos, arrValPos, nMaxPool, isFlopAfter)
				if panelData then
					table.insert(arrPanelData, {
						tPanelData = panelData,
						arrWinRate = arrWinRate
					})
				end
			else
				local panelData, arrWinRate = self:GetInsurPanelData_Normal(nInsurPos, arrValPos, nMaxPool, isFlopAfter)
				if panelData then
					table.insert(arrPanelData, {
						tPanelData = panelData,
						arrWinRate = arrWinRate
					})
				end
			end
		end
	end
	return arrPanelData
end

function Table:_GetOutsOdds(nOutsCnt, arrOddsList)
	arrOddsList = arrOddsList or self.arrOddsList
	nOutsCnt = math.min(#arrOddsList, nOutsCnt)
	return (self.arrOddsList[nOutsCnt] or 1)
end

function Table:_GetUsersHoleCard(nInsurPos, arrValPos)
	local arrUsersHoleCard = {}
	local nInsurDex = nil
	local nInsurUserId = 0
	for n, nPos in ipairs(arrValPos) do
		local tUser = self:_GetUser(nPos)
		table.insert(arrUsersHoleCard, _CopyArr(tUser.arrHoleCards))
		nInsurDex = (nPos == nInsurPos) and n or nInsurDex
		nInsurUserId = (nPos == nInsurPos) and tUser.nUserId or nInsurUserId
	end
	return arrUsersHoleCard, nInsurUserId, nInsurDex
end

function Table:_PlanCostFilter_new(arrPlanTem, nLastCost, nMaxPool, isFlopAfter)
	local arr = {}
	for _, v in ipairs(arrPlanTem) do
		if v.nCosts <= nLastCost then
			table.insert(arr, v)
		end
	end
	return arr
end

function Table:_PlanCostFilter(arrPlanTem, nLastCost, nMaxPool, isFlopAfter)
	local maxCost = publicApi.Floor_1(nMaxPool / 3) -- 转牌阶段，保险的投保额不能超过1/3底池
	if not isFlopAfter then
		maxCost = publicApi.Floor_1(nMaxPool / 2) -- 河牌阶段，保险的投保额不能超过1/2底池
	end
	-- if nLastCost <= 0 then
	-- 	return arrPlanTem
	-- end
	local arr = {}
	for _, v in ipairs(arrPlanTem) do
		if v.nCosts >= nLastCost and maxCost >= v.nCosts then
			table.insert(arr, v)
		end
	end
	return arr
end

--保留nCosts处于闭区间[nFloor,nTop]的元素
function Table:_PlanCostFilterV(arrPlanTem, nFloor, nTop)
	local arr = {}
	for _, v in ipairs(arrPlanTem) do
		if GreaterOrEqual(v.nCosts, nFloor) and LessOrEqual(v.nCosts, nTop) then
			table.insert(arr, v)
		end
	end
	return arr
end

--[[
	取出要参与保险计算的玩家的手牌 nInsurUserId 可以买保险的那个人 nInsurDex 该玩家在数组中的下标
	tDexToOuts：每个玩家的outs（哪些牌能让他赢）isHaveWinEqual：是否存在平局；tDexToWinRate：每个玩家的胜率。
	tOuts 所有「会让保险玩家输掉」的牌
]]
--计算保险面板数据(常规保险1)
function Table:GetInsurPanelData_Normal(nInsurPos, arrValPos, nMaxPool, isFlopAfter)
	local arrUsersHoleCard, nInsurUserId, nInsurDex = self:_GetUsersHoleCard(nInsurPos, arrValPos)
	local tDexToOuts, isHaveWinEqual, tDexToWinRate = tAlg.CalUsersOutsNormal(arrUsersHoleCard,
		_CopyArr(self.arrCommunityCards), nInsurDex, false)

	local arrWinRate = {} --玩家胜率 {{nPos=,nWinRate}...}

	--与保险相关的玩家
	local arrRelevantUser = {}
	local tOuts = {} --outs去重用
	for dex, nPos in ipairs(arrValPos) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local item = { nUserId = tUser.nUserId, sName = tUser.sName, arrHoleCards = _CopyArr(tUser.arrHoleCards) }
		local arrOuts = tDexToOuts[dex] or {}
		item.nOuts = (nPos == nInsurPos) and -1 or #arrOuts
		table.insert(arrRelevantUser, item)
		for i = 1, item.nOuts do
			tOuts[arrOuts[i]] = true
		end
		local tRate = {}
		tRate.nPos = nPos
		tRate.nWinRate = publicApi.Floor_1(tDexToWinRate[dex] * 100)
		table.insert(arrWinRate, tRate)
	end

	--剩余outs,牌堆剩余多少张牌,赔率(默认outs全选)
	local arrOuts = {}
	for v, _ in pairs(tOuts) do
		table.insert(arrOuts, v)
	end
	if #arrOuts > 24 or #arrOuts == 0 then --outs数超24张或为0时不触发保险
		self:Print("outs count is %d", #arrOuts)
		return
	end
	local tRemaining = { arrOuts = arrOuts, nPileCnt = self.tPile:GetCnt(), nOdds = self:_GetOutsOdds(#arrOuts) }

	--可投保池,底池,投入 找出这个玩家在底池中的资金情况；nInsurePool 可买保险的金额 nInvest：玩家当前已投入的金额。
	local tInsurUser = self:_GetUser(nInsurPos)
	assert(tInsurUser ~= nil)
	local tPool = { nInsurePool = 0, nPool = nMaxPool, nInvest = tInsurUser.nBetSum }
	for _, v in ipairs(self.arrPoolInfo) do
		if _IsHaveEle(v.arrPosForm, nInsurPos) then
			tPool.nInsurePool = (#v.arrPosForm > 1) and (tPool.nInsurePool + v.nPool) or tPool.nInsurePool
			tPool.nInvest = (#v.arrPosForm == 1) and (tPool.nInvest - v.nPool) or tPool.nInvest
		end
	end

	--投保方案 (nCosts需要根据倍率变化而变化)
	-- local nLastCost = self:_GetCostOfLastInsur(nInsurUserId)
	-- local tPlanA ={nPlanId=0,nCosts=publicApi.Floor_1(tPool.nInvest/tRemaining.nOdds)}				--保本
	-- local tPlanB ={nPlanId=1,nCosts=publicApi.Floor_1(tPool.nInsurePool/tRemaining.nOdds)}			--满池
	-- local tPlanC ={nPlanId=2,nCosts=publicApi.Floor_1(tPool.nInsurePool/2/tRemaining.nOdds)}		--1/2池
	-- local tPlanD ={nPlanId=3,nCosts=publicApi.Floor_1(tPool.nInsurePool/3/tRemaining.nOdds)}		--1/3池
	-- local tPlanE ={nPlanId=5,nCosts=publicApi.Floor_1(tPool.nInsurePool/5/tRemaining.nOdds)}		--1/5池
	local nLastCost = self:_GetCostOfLastInsur(nInsurUserId)
	local tPlanA = { nPlanId = 0, nCosts = publicApi.Floor_1(tPool.nInvest / tRemaining.nOdds) }      --保本
	local tPlanB = { nPlanId = 1, nCosts = publicApi.Floor_1(tPool.nInsurePool / tRemaining.nOdds) }  --满池
	local tPlanC = { nPlanId = 2, nCosts = publicApi.Floor_1(tPool.nInsurePool / 2 / tRemaining.nOdds) } --1/2池
	local tPlanD = { nPlanId = 3, nCosts = publicApi.Floor_1(tPool.nInsurePool / 3 / tRemaining.nOdds) } --1/3池
	local tPlanE = { nPlanId = 5, nCosts = publicApi.Floor_1(tPool.nInsurePool / 5 / tRemaining.nOdds) } --1/5池
	local tPlanF = { nPlanId = 8, nCosts = publicApi.Floor_1(tPool.nInsurePool / 8 / tRemaining.nOdds) } --1/8池

	-- local tPlanA ={nPlanId=0, nCosts=publicApi.Floor_1(tPool.nInvest/tRemaining.nOdds)}				--保本
	-- local tPlanB ={nPlanId=1, nCosts=publicApi.Floor_1(tPool.nInsurePool/tRemaining.nOdds)}			--满池
	-- local tPlanC ={nPlanId=2, nCosts=publicApi.Floor_1(tPool.nInsurePool/ (2 * tRemaining.nOdds))}		--1/2池
	-- local tPlanD ={nPlanId=3, nCosts=publicApi.Floor_1(tPool.nInsurePool * 2 / (3 * tRemaining.nOdds))}		--1/3池 ->2/3
	-- local tPlanE ={nPlanId=5, nCosts=publicApi.Floor_1(tPool.nInsurePool / (4 * tRemaining.nOdds))}		--1/5池 ->1/4
	-- local tPlanF ={nPlanId=8,nCosts=publicApi.Floor_1(tPool.nInsurePool/8/tRemaining.nOdds)}		--1/8池
	if tPlanA.nCosts < 0.1 then
		tPlanA.nCosts = 0
	end
	if tPlanB.nCosts < 0.1 then
		tPlanB.nCosts = 0
	end
	if tPlanC.nCosts < 0.1 then
		tPlanC.nCosts = 0
	end
	if tPlanD.nCosts < 0.1 then
		tPlanD.nCosts = 0
	end
	if tPlanE.nCosts < 0.1 then
		tPlanE.nCosts = 0
	end
	if tPlanF.nCosts < 0.1 then
		tPlanF.nCosts = 0
	end
	if tPlanA.nCosts + tPlanB.nCosts + tPlanC.nCosts + tPlanD.nCosts + tPlanE.nCosts + tPlanF.nCosts <= 0 then
		self:Print("GetInsurPanelData_Normal  all plan costs is 0 ")
		return nil, nil
	end


	local arrPlanTem = { tPlanA, tPlanB, tPlanC, tPlanD, tPlanE, tPlanF }
	local arrInsurancePlan = self:_PlanCostFilter(arrPlanTem, (nLastCost / tRemaining.nOdds), nMaxPool, isFlopAfter) --剔除nCost<(nLastCost/nOdds),也即 "赔付额 <上一次的投保额" 的选项

	local nCostsTop = isFlopAfter and (tPool.nInsurePool / 3) or (tPool.nInsurePool / 2)
	local tInsurPanelData = {}
	tInsurPanelData.arrRelevantUser = arrRelevantUser                 --与保险相关的玩家显示
	tInsurPanelData.arrCommunityCards = _CopyArr(self.arrCommunityCards) --公共牌
	tInsurPanelData.tElseUserHoleCard = nil                           --其他玩家手牌
	tInsurPanelData.tRemaining = tRemaining                           --剩余outs,牌堆剩余多少张牌,赔率
	tInsurPanelData.tPool = tPool                                     --可投保池,底池,投入
	tInsurPanelData.arrInsurancePlan = arrInsurancePlan               --投保方案
	tInsurPanelData.nSeconds = Define.nInsureStageTime                --买保险阶段时间 秒
	tInsurPanelData.nInsurUserId = nInsurUserId                       --可以买保险的玩家id
	tInsurPanelData.nInsureMode = InsureMode.nNormal                  --保险模式 1:传统保险 2:低水保险
	tInsurPanelData.arrOddsList = _CopyArr(self.arrOddsList)          --传统保险赔率表
	tInsurPanelData.isMustBuy = GreaterThan(nLastCost, 0)             --是否必须购买保险(true时，保险玩家必须购买所有outs保险,放在函数外判断)
	tInsurPanelData.isPossibleEq = true                               --true时,保险费nCosts不能超过nInvestInThisPool
	tInsurPanelData.nInvestInThisPool = publicApi.Floor_n(nCostsTop, 3) --保险费nCosts的上限值,isPossibleEq为true时有效
	return tInsurPanelData, arrWinRate
end

--计算保险面板数据(常规保险2)
function Table:GetInsurPanelData_Normal2(nInsurPos, arrValPos, nTPool, isFlopAfter, sameCount)
	sameCount = sameCount or 1
	local nMaxPool = nTPool.nPool
	local arrUsersHoleCard, nInsurUserId, nInsurDex = self:_GetUsersHoleCard(nInsurPos, arrValPos)
	--除了能被超越的牌外，能平分的牌bu算进outs
	local tDexToOuts, isHaveWinEqual, tDexToWinRate = tAlg.CalUsersOutsNormal(arrUsersHoleCard,
		_CopyArr(self.arrCommunityCards), nInsurDex, false)
	local arrWinRate = {} --玩家胜率 {{nPos=,nWinRate}...}
	-- 新增逻辑：合并其它玩家的赢牌为 insurance player's outs
	local outsMap = {}
	for dex, cards in pairs(tDexToOuts) do
		if dex ~= nInsurDex and type(cards) == "table" then
			for _, c in ipairs(cards) do
				outsMap[c] = true
			end
		end
	end
	local arrOuts = {}
	for c, _ in pairs(outsMap) do
		table.insert(arrOuts, c)
	end
	-- outs数超15张或为0时不触发保险
	if #arrOuts > 15 or #arrOuts == 0 then
		self:Print("outs count is %d (no valid insurance trigger)", #arrOuts)
		return
	end

	--与保险相关的玩家
	-- local arrRelevantUser ={}
	-- local tOuts ={}		--outs去重用
	-- for dex,nPos in ipairs(arrValPos) do
	-- 	local tUser =self:_GetUser(nPos)
	-- 	assert(tUser~=nil)
	-- 	local item={nUserId =tUser.nUserId,sName =tUser.sName,arrHoleCards =_CopyArr(tUser.arrHoleCards)}
	-- 	local arrOuts =tDexToOuts[dex] or {}
	-- 	item.nOuts =(nPos ==nInsurPos) and -1 or #arrOuts
	-- 	table.insert(arrRelevantUser,item)
	-- 	for i=1,item.nOuts do
	-- 		tOuts[arrOuts[i]]=true
	-- 	end
	-- 	local tRate={}
	-- 	tRate.nPos =nPos
	-- 	tRate.nWinRate =publicApi.Floor_1(tDexToWinRate[dex]*100)
	-- 	table.insert(arrWinRate,tRate)
	-- end

	-- --剩余outs,牌堆剩余多少张牌,赔率(默认outs全选)
	-- local arrOuts ={}
	-- for v,_ in pairs(tOuts) do
	-- 	table.insert(arrOuts,v)
	-- end
	-- --outs数超15张或为0时不触发保险 (与保险1的不同之处)
	-- if #arrOuts>15 or #arrOuts==0 then
	-- 	self:Print("outs count is %d -",#arrOuts)
	-- 	return
	-- end
	local tRemaining = { arrOuts = arrOuts, nPileCnt = self.tPile:GetCnt(), nOdds = self:_GetOutsOdds(#arrOuts) }

	--可投保池,底池,投入
	local tInsurUser = self:_GetUser(nInsurPos)
	assert(tInsurUser ~= nil)
	local nInvest = self:_GetPoolUserBet(nTPool, tInsurUser.nUserId)
	local tPool = { nInsurePool = nTPool.nPool, nPool = nMaxPool, nInvest = nInvest, nPoolId = nTPool.nPoolId }
	tPool.nInsurePool = tonumber(string.format("%.1f", tPool.nInsurePool))
	tPool.nPool = tonumber(string.format("%.1f", tPool.nPool))
	local nPoolSum = nTPool.nPool
	--底池小于10个大盲时不触发保险 (与保险1的不同之处)
	-- if nPoolSum < 10*self.nBigBlind then
	-- 	self:Print("nPoolSum is %s -",tostring(nPoolSum))
	-- 	return
	-- end

	--投保方案 (nCosts需要根据倍率变化而变化)
	-- local nLastCost = self:_GetCostOfLastInsur(nInsurUserId)
	local nLastCost = 0
	-- local tPlanA ={nPlanId=0,nCosts=publicApi.Floor_1(tPool.nInvest/tRemaining.nOdds)}				--保本
	-- local tPlanB ={nPlanId=1,nCosts=publicApi.Floor_1(tPool.nInsurePool/tRemaining.nOdds)}			--满池
	-- local tPlanC ={nPlanId=2,nCosts=publicApi.Floor_1(tPool.nInsurePool/2/tRemaining.nOdds)}		--1/2池
	-- local tPlanD ={nPlanId=3,nCosts=publicApi.Floor_1(tPool.nInsurePool * 2 / 3 / tRemaining.nOdds)}		--1/3池 ->2/3
	-- local tPlanE ={nPlanId=5,nCosts=publicApi.Floor_1(tPool.nInsurePool/4/tRemaining.nOdds)}		--1/5池 ->1/4
	local tPlanA = { nPlanId = 0, nCosts = publicApi.Floor_1(tPool.nInvest / tRemaining.nOdds) }            --保本
	local tPlanB = { nPlanId = 1, nCosts = publicApi.Floor_1(tPool.nInsurePool / tRemaining.nOdds) }        --满池
	local tPlanC = { nPlanId = 2, nCosts = publicApi.Floor_1(tPool.nInsurePool / (2 * tRemaining.nOdds)) }  --1/2池
	local tPlanD = { nPlanId = 3, nCosts = publicApi.Floor_1(tPool.nInsurePool * 2 / (3 * tRemaining.nOdds)) } --1/3池 ->2/3
	local tPlanE = { nPlanId = 5, nCosts = publicApi.Floor_1(tPool.nInsurePool / (4 * tRemaining.nOdds)) }  --1/5池 ->1/4
	if tPlanA.nCosts < 0.1 then
		tPlanA.nCosts = 0
	end
	if tPlanB.nCosts < 0.1 then
		tPlanB.nCosts = 0
	end
	if tPlanC.nCosts < 0.1 then
		tPlanC.nCosts = 0
	end
	if tPlanD.nCosts < 0.1 then
		tPlanD.nCosts = 0
	end
	if tPlanE.nCosts < 0.1 then
		tPlanE.nCosts = 0
	end
	if tPlanA.nCosts + tPlanB.nCosts + tPlanC.nCosts + tPlanD.nCosts + tPlanE.nCosts <= 0 then
		self:Print("_GetInsurPanelData_Normal2  all plan costs is 0 ")
		return nil, nil, nil
	end
	-- local tPlanF ={nPlanId=8,nCosts=publicApi.Floor_1(tPool.nInsurePool/8/tRemaining.nOdds)}		--1/8池
	local arrPlanTem = { tPlanA, tPlanB, tPlanC, tPlanD, tPlanE }
	-- local nCostsTop = isFlopAfter and (tPool.nInsurePool/3) or (tPool.nInsurePool/2)
	local nCostsTop = publicApi.Floor_1(tPool.nInsurePool / (tRemaining.nOdds * sameCount))
	-- local arrInsurancePlan =self:_PlanCostFilter(arrPlanTem,(nLastCost/tRemaining.nOdds),nMaxPool,isFlopAfter)			--剔除nCost<(nLastCost/nOdds),也即 "赔付额 <上一次的投保额" 的选项
	local arrInsurancePlan = self:_PlanCostFilter_new(arrPlanTem, nCostsTop, nMaxPool, isFlopAfter)
	if #arrInsurancePlan == 0 then
		self:Print("_GetInsurPanelData_Normal  没有投保方案 arrInsurancePlan_%d ", #arrInsurancePlan)
		return
	end

	local tInsurPanelData = {}
	tInsurPanelData.arrRelevantUser = {}
	for dex, nPos in ipairs(arrValPos) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local arrPlayerOuts = (dex == nInsurDex) and {} or (tDexToOuts[dex] or {})
		table.insert(tInsurPanelData.arrRelevantUser, {
			nUserId = tUser.nUserId,
			sName = tUser.sName,
			arrHoleCards = _CopyArr(tUser.arrHoleCards),
			nOuts = (dex == nInsurDex) and -1 or #arrPlayerOuts
		})
		local tRate = {}
		tRate.nPos = nPos
		tRate.nWinRate = publicApi.Floor_1(tDexToWinRate[dex] * 100)
		table.insert(arrWinRate, tRate)
	end
	-- tInsurPanelData.arrRelevantUser=arrRelevantUser								--与保险相关的玩家显示
	tInsurPanelData.arrCommunityCards = _CopyArr(self.arrCommunityCards) --公共牌
	tInsurPanelData.tElseUserHoleCard = nil                           --其他玩家手牌
	tInsurPanelData.tRemaining = tRemaining                           --剩余outs,牌堆剩余多少张牌,赔率
	tInsurPanelData.tPool = tPool                                     --可投保池,底池,投入
	tInsurPanelData.arrInsurancePlan = arrInsurancePlan               --投保方案
	tInsurPanelData.nSeconds = Define.nInsureStageTime                --买保险阶段时间 秒
	tInsurPanelData.nInsurUserId = nInsurUserId                       --可以买保险的玩家id
	tInsurPanelData.nInsureMode = InsureMode.nNormal                  --保险模式 1:传统保险 2:低水保险
	tInsurPanelData.arrOddsList = _CopyArr(self.arrOddsList)          --传统保险赔率表
	tInsurPanelData.isMustBuy = GreaterThan(nLastCost, 0)             --是否必须购买保险(true时，保险玩家必须购买所有outs保险,放在函数外判断)
	tInsurPanelData.isPossibleEq = true                               --true时,保险费nCosts不能超过nInvestInThisPool
	tInsurPanelData.nInvestInThisPool = nCostsTop                     --保险费nCosts的上限值,isPossibleEq为true时有效
	return tInsurPanelData, arrWinRate, tPlanE.nCosts
end

--计算保险面板数据(低水保险)
function Table:GetInsurPanelData_Low(nInsurPos, arrValPos, nMaxPool, isFlopAfter)
	local arrUsersHoleCard, nInsurUserId = self:_GetUsersHoleCard(nInsurPos, arrValPos)
	local tDexToOuts, tDexToWinRate = tAlg.CalUsersOuts(arrUsersHoleCard, _CopyArr(self.arrCommunityCards))
	local tOuts = {}

	local arrWinRate = {} --玩家胜率
	--与保险相关的玩家显示
	local arrRelevantUser = {}
	for dex, nPos in ipairs(arrValPos) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local item = { nUserId = tUser.nUserId, sName = tUser.sName, arrHoleCards = _CopyArr(tUser.arrHoleCards) }
		local arrOuts = tDexToOuts[dex] or {}
		item.nOuts = (nPos == nInsurPos) and -1 or #arrOuts
		table.insert(arrRelevantUser, item)
		for i = 1, item.nOuts do
			tOuts[arrOuts[i]] = true
		end

		local tRate = {}
		tRate.nPos = nPos
		tRate.nWinRate = publicApi.Floor_1(tDexToWinRate[dex] * 100)
		table.insert(arrWinRate, tRate)
	end

	--其他玩家手牌
	local tElseUserHoleCard = { arrOuts = {}, arrCard = {} }
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		if (not _IsHaveEle(arrValPos, nPos)) and tUser.nStatus ~= UserStatus.nFold then
			for _, v in ipairs(tUser.arrHoleCards) do
				if tOuts[v] then
					table.insert(tElseUserHoleCard.arrOuts, v)
					tOuts[v] = nil
				else
					table.insert(tElseUserHoleCard.arrCard, v)
				end
			end
		end
	end

	--剩余outs,牌堆剩余多少张牌,赔率
	local arrOuts = {}
	for v, _ in pairs(tOuts) do
		table.insert(arrOuts, v)
	end
	if #arrOuts == 0 then --outs数为0时不触发保险
		self:Print("outs count is 0")
		return
	end
	local nPileCnt = self.tPile:GetCnt()
	local nOdds = ((nPileCnt / #arrOuts) * 0.95) - 1 --按公式计算赔率
	nOdds = publicApi.Floor_n(nOdds, 1)           --保留一位小数
	if nOdds < 0.1 then
		self:Print("nOdds is too small")
		return
	end
	local tRemaining = { arrOuts = arrOuts, nPileCnt = nPileCnt, nOdds = nOdds }

	--可投保池,底池,投入
	local tInsurUser = self:_GetUser(nInsurPos)
	assert(tInsurUser ~= nil)
	local tPool = { nInsurePool = 0, nPool = nMaxPool, nInvest = tInsurUser.nBetSum }
	for _, v in ipairs(self.arrPoolInfo) do
		if _IsHaveEle(v.arrPosForm, nInsurPos) then
			tPool.nInsurePool = (#v.arrPosForm > 1) and (tPool.nInsurePool + v.nPool) or tPool.nInsurePool
			tPool.nInvest = (#v.arrPosForm == 1) and (tPool.nInvest - v.nPool) or tPool.nInvest
		end
	end

	--投保方案 (nCosts需要根据倍率变化而变化)
	local nCostsTop = isFlopAfter and (tPool.nInsurePool / 3) or
		(tPool.nInsurePool / 2)                                                                       --转牌阶段:保险费不能超1/3底池,河牌阶段不能超1/2底池
	local nLastCost = self:_GetCostOfLastInsur(nInsurUserId)
	local tPlanA = { nPlanId = 0, nCosts = publicApi.Floor_1(tPool.nInvest / tRemaining.nOdds) }      --保本
	local tPlanB = { nPlanId = 1, nCosts = publicApi.Floor_1(tPool.nInsurePool / tRemaining.nOdds) }  --满池
	local tPlanC = { nPlanId = 2, nCosts = publicApi.Floor_1(tPool.nInsurePool / 2 / tRemaining.nOdds) } --1/2池
	local tPlanD = { nPlanId = 3, nCosts = publicApi.Floor_1(tPool.nInsurePool / 3 / tRemaining.nOdds) } --1/3池
	local tPlanE = { nPlanId = 5, nCosts = publicApi.Floor_1(tPool.nInsurePool / 5 / tRemaining.nOdds) } --1/5池
	local tPlanF = { nPlanId = 8, nCosts = publicApi.Floor_1(tPool.nInsurePool / 8 / tRemaining.nOdds) } --1/8池
	local arrPlanTem = { tPlanA, tPlanB, tPlanC, tPlanD, tPlanE, tPlanF }
	arrPlanTem = self:_PlanCostFilterV(arrPlanTem, 0, nCostsTop)
	local arrInsurancePlan = self:_PlanCostFilter(arrPlanTem, (nLastCost / tRemaining.nOdds), nMaxPool, isFlopAfter) --剔除nCost<(nLastCost/nOdds),也即 "赔付额 <上一次的投保额" 的选项

	local tInsurPanelData = {}
	tInsurPanelData.arrRelevantUser = arrRelevantUser                 --与保险相关的玩家显示
	tInsurPanelData.arrCommunityCards = _CopyArr(self.arrCommunityCards) --公共牌
	tInsurPanelData.tElseUserHoleCard = tElseUserHoleCard             --其他玩家手牌
	tInsurPanelData.tRemaining = tRemaining                           --剩余outs,牌堆剩余多少张牌,赔率
	tInsurPanelData.tPool = tPool                                     --可投保池,底池,投入
	tInsurPanelData.arrInsurancePlan = arrInsurancePlan               --投保方案
	tInsurPanelData.nSeconds = Define.nInsureStageTime                --买保险阶段时间 秒
	tInsurPanelData.nInsurUserId = nInsurUserId                       --可以买保险的玩家id
	tInsurPanelData.nInsureMode = InsureMode.nLow                     --保险模式 1:传统保险 2:低水保险
	tInsurPanelData.arrOddsList = {}                                  --赔率表(传统保险才有效);值1为补牌1赔率、值2为补牌2赔率...
	tInsurPanelData.isMustBuy = GreaterThan(nLastCost, 0)             --是否必须购买保险(true时，保险玩家必须购买所有outs保险)
	tInsurPanelData.isPossibleEq = false                              --true时,保险费nCosts不能超过nInvestInThisPool(低水保险不使用该字段)
	tInsurPanelData.nInvestInThisPool = 0                             --保险费nCosts的上限值,isPossibleEq为true时有效(低水保险不使用该字段)
	return tInsurPanelData, arrWinRate
end

local function GetSameHandGroups(arrUsers)
	local tSignToPos = {}
	for _, user in ipairs(arrUsers) do
		if user.hands and #user.hands == 2 then
			-- 把牌按大小排序避免顺序不同
			local c1, c2 = user.hands[1], user.hands[2]
			if c2 < c1 then c1, c2 = c2, c1 end
			local sign = string.format("%d|%d", c1, c2)
			tSignToPos[sign] = tSignToPos[sign] or {}
			table.insert(tSignToPos[sign], user.nPos)
		end
	end
	-- 返回所有重复组
	local arrSameGroups = {}
	for sign, arr in pairs(tSignToPos) do
		if #arr >= 2 then
			table.insert(arrSameGroups, { sign = sign, arrPos = arr })
		end
	end
	return arrSameGroups
end


-- 返回：arrTargets = { { tPool = pool, arrPos = {pos1,pos2,...} }, ... }
function Table:_GetEligibleInsurPotsAndPlayers()
	local arrPools = _CopyArr(self.arrPoolInfo or {})
	if #arrPools == 0 then return {} end
	local arrValidPools = {}
	for _, tPool in ipairs(arrPools) do
		local poolPosList = tPool.arrPosForm or {}
		if #poolPosList <= 1 then
			-- 只有一个人，直接无效
			goto continue_collect
		end
		local nAllinCount = 0
		local nActiveCount = 0
		for _, nPos in ipairs(poolPosList) do
			local tUser = self:_GetUser(nPos)
			if tUser and tUser.nStatus ~= UserStatus.nFold then
				nActiveCount = nActiveCount + 1
				if tUser.nStatus == UserStatus.nAllIn then
					nAllinCount = nAllinCount + 1
				end
			end
		end
		-- 有人 all-in，且至少 2 个活跃玩家，才算有效池
		if nAllinCount >= 1 and nActiveCount >= 2 then
			table.insert(arrValidPools, tPool)
		end
		::continue_collect::
	end
	-- 按池金额降序 (假设池结构字段是 nPool 或 nInsurePool)
	table.sort(arrValidPools, function(a, b) return a.nPool > b.nPool end)
	local nTake = math.min(3, #arrValidPools) -- 最多前三个池
	local arrSelectedPools = {}
	for i = 1, nTake do table.insert(arrSelectedPools, arrValidPools[i]) end
	local arrTargets, userDict = {}, {}
	-- 规则参数
	local nOutsLimit = 14
	local nMaxPerPot = 9
	-- 遍历每个选中池，筛选该池符合条件的玩家（领先玩家也可）
	for _, tPool in ipairs(arrSelectedPools) do
		local poolPosList = tPool.arrPosForm or {}
		if #poolPosList <= 1 then goto continue_pool end
		-- 1️判断该池内是否存在 2 人以上 All-in
		-- local nAllinCount = 0
		-- local nActiveCount = 0
		-- for _, nPos in ipairs(poolPosList) do
		--     local tUser = self:_GetUser(nPos)
		--     if tUser and tUser.nStatus ~= UserStatus.nFold then
		-- 		nActiveCount = nActiveCount + 1
		-- 		if tUser.nStatus == UserStatus.nAllIn then
		-- 			nAllinCount = nAllinCount + 1
		-- 		end
		-- 	end
		-- end
		-- self:Print("_GetEligibleInsurPotsAndPlayers nAllinCount:%d, nActiveCount:%d",nAllinCount, nActiveCount)
		-- if nAllinCount >= 1 and nActiveCount >= 2 then
		-- 	-- 2 有人 allin，有人还在跟（call、check、raise）
		-- else
		-- 	goto continue_pool
		-- end
		-- 2 计算各玩家当前胜率
		local arrValPosCardType, arrUserCards, arrUserDictCards = {}, {}, {}
		local handPos, arrPos = {}, {}
		for _, nPos in ipairs(poolPosList) do
			local tUser = self:_GetUser(nPos)
			if tUser and tUser.nStatus ~= UserStatus.nFold and tUser.nStatus ~= UserStatus.nLooker and tUser.tCardType then
				tUser.tCardType.nPos = nPos
				table.insert(arrUserCards, _CopyArr(tUser.arrHoleCards))
				handPos[nPos] = { index = #arrUserCards, userId = tUser.nUserId }
				arrUserDictCards[nPos] = _CopyArr(tUser.arrHoleCards)
				table.insert(arrValPosCardType, tUser.tCardType)
				table.insert(arrPos, nPos)
			end
		end
		local arrTheWinItem = tAlg.TheWinCardType(arrValPosCardType)
		-- if #arrTheWinItem ~= 1 then
		--     self:Print("Skip Insur: arrTheWinItem cnt:%d", #arrTheWinItem)
		--     goto continue_pool
		-- end
		tBase.LogT("_GetEligibleInsurPotsAndPlayers arrTheWinItem", arrTheWinItem)
		-- local tDexToOuts, _ = tAlg.CalUsersOuts(arrUserCards, _CopyArr(self.arrCommunityCards))
		-- tBase.LogT("_GetEligibleInsurPotsAndPlayers tDexToOuts", tDexToOuts)
		local arrLeaderPos, arrEligiblePos = {}, {}
		local arrUserList = {}
		local tDexToOuts = {}
		for _, v in ipairs(arrTheWinItem) do
			local nInsurDex = handPos[v.nPos].index
			--除了能被超越的牌外，能平分的牌也算进outs(与保险1的不同之处)
			local tOuts, _, _ = tAlg.CalUsersOutsNormal(arrUserCards, _CopyArr(self.arrCommunityCards), nInsurDex, false)
			tBase.LogT("_GetEligibleInsurPotsAndPlayers tOuts", tOuts)
			tBase.LogT("_GetEligibleInsurPotsAndPlayers handPos", handPos)
			-- 把所有能让其它玩家赢（dex != nInsurDex）的牌合并成 leader 被反超的 outs
			local outsMap = {}
			for dex, cards in pairs(tOuts) do
				if dex ~= nInsurDex and type(cards) == "table" then
					for _, c in ipairs(cards) do
						outsMap[c] = true
					end
				end
			end
			-- 构造去重后的 outs 列表
			local arrOutsForLeader = {}
			for c, _ in pairs(outsMap) do table.insert(arrOutsForLeader, c) end
			tBase.LogT("_GetEligibleInsurPotsAndPlayers arrOutsForLeader", arrOutsForLeader)
			if tOuts then
				for dex, arr in pairs(tOuts) do
					tDexToOuts[dex] = arr
				end
			end
			self:Print("_GetEligibleInsurPotsAndPlayers v.nPos:%d, #arrOuts:%d", v.nPos, #arrOutsForLeader)
			if #arrOutsForLeader > 0 and #arrOutsForLeader <= nOutsLimit then
				local nOdds = self:_GetOutsOdds(#arrOutsForLeader)
				table.insert(arrLeaderPos, v.nPos)
				table.insert(arrEligiblePos, v.nPos)
				table.insert(arrUserList, { hands = arrUserDictCards[v.nPos], nPos = v.nPos })
				userDict[handPos[v.nPos].userId] = (userDict[handPos[v.nPos].userId] or 0) +
					publicApi.Floor_1(tPool.nPool / 4 / nOdds) -- 1/5底池 ->1/4
			end
		end
		local arrSameGroups = GetSameHandGroups(arrUserList) --手牌相同
		tBase.LogT("_GetEligibleInsurPotsAndPlayers arrSameGroups", arrSameGroups)
		local hasOuts = false
		local sameCount = 1
		for _, group in ipairs(arrSameGroups) do
			-- 判断组内是否有人有 Outs（即存在能反超的情况）
			for _, nPos in ipairs(group.arrPos) do
				local index = handPos[nPos].index
				local arrOuts = tDexToOuts[index] or {}
				if #arrOuts > 0 and #arrOuts <= nOutsLimit then
					hasOuts = true
					break
				end
			end
			if hasOuts then
				sameCount = #group.arrPos
			end
		end
		-- table.insert(arrLeaderPos, arrTheWinItem[1].nPos)
		-- table.insert(arrEligiblePos, arrTheWinItem[1].nPos)
		if #arrEligiblePos > nMaxPerPot then
			arrEligiblePos = { unpack(arrEligiblePos, 1, nMaxPerPot) }
		end
		if #arrEligiblePos > 0 then
			table.insert(arrTargets, { tPool = tPool, arrInPos = arrEligiblePos, arrPos = arrPos, sameCount = sameCount })
		end
		::continue_pool::
	end

	return arrTargets, userDict
end

--尝试进入买保险阶段 返回:true(进入成功), false(进入失败)
function Table:TryTriggerInsur()
	if self.nInsureMode == 0 then
		return false
	end
	if #self.arrCommunityCards == 0 then
		return false
	end
	if #self.arrCommunityCards == 3 then
		return self:TryGoInInsurOfFlopAfter() -- 尝试进入翻牌后买保险阶段
	elseif #self.arrCommunityCards == 4 then
		return self:TryGoInInsurOfTurnAfter() -- 尝试进入转牌后买保险阶段
	end
	return false
end

function Table:_GetInsurProtoShowCard()
	local arrHoleCard = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		if tUser.nStatus ~= UserStatus.nFold then
			local item = {}
			item.nPos = nPos                           --座位号
			item.arrHoleCards = _CopyArr(tUser.arrHoleCards) --底牌(2张)
			item.nCardType = self:_GetCardType(tUser.tCardType) --牌型
			table.insert(arrHoleCard, item)
		end
	end
	return { arrHoleCard = arrHoleCard }
end

function Table:_GetInsurProtoPoolChange()
	return { arrPot = self:_GetProtoArrPot() }
end

function Table:_GetInsurProtoUsersCardType()
	local arrUsersCardType = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		if tUser.nStatus ~= UserStatus.nFold then
			local item = {}
			item.nPos = nPos                           --座位号
			item.nCardType = self:_GetCardType(tUser.tCardType) --牌型
			local tCardType = tUser.tCardType or {}
			item.arrCombinedCards = tCardType.arrFiveBack or {}
			table.insert(arrUsersCardType, item)
		end
	end
	return arrUsersCardType
end

function Table:_InsurSettleFlopAfter(nUserId)
	if not self.tFlopAfterInsur then
		return 0, 0
	end
	local nTotalSettle, cost = 0, 0
	for _, insurData in ipairs(self.tFlopAfterInsur.arrInsurData) do
		local tInsurPanelData = insurData.tPanelData
		if tInsurPanelData.nInsurUserId == nUserId then
			local nCosts = insurData.nChooseCost or 0
			local arrOutsAfterCheck = insurData.arrOutsAfterCheck or {}
			local nOdds = insurData.nOdds or 0
			cost = cost + nCosts
			local isHit = _IsHaveEle(arrOutsAfterCheck, self.arrCommunityCards[4])
			if isHit then
				nTotalSettle = nTotalSettle + publicApi.Floor_n(nCosts * nOdds, 1) -- 要求先取整后再求和
			else
				-- nTotalSettle = nTotalSettle - nCosts
			end
		end
	end
	return nTotalSettle, cost
end

function Table:_InsurSettleTurnAfter(nUserId)
	if not self.tTurnAfterInsur then
		return 0, 0
	end
	local nTotalSettle, cost = 0, 0
	for _, insurData in ipairs(self.tTurnAfterInsur.arrInsurData) do
		local tInsurPanelData = insurData.tPanelData
		if tInsurPanelData.nInsurUserId == nUserId then
			local nCosts = insurData.nChooseCost or 0
			local arrOutsAfterCheck = insurData.arrOutsAfterCheck or {}
			local nOdds = insurData.nOdds or 0
			cost = cost + nCosts
			local isHit = _IsHaveEle(arrOutsAfterCheck, self.arrCommunityCards[5])
			if isHit then
				nTotalSettle = nTotalSettle + publicApi.Floor_n(nCosts * nOdds, 1) -- 要求先取整后再求和
			else
				-- nTotalSettle = nTotalSettle - nCosts
			end
		end
	end
	return nTotalSettle, cost
end

function Table:InsurSettle(nUserId)
	local nInsurA, nCostA = self:_InsurSettleFlopAfter(nUserId) --第一次保险结算
	local nInsurB, nCostB = self:_InsurSettleTurnAfter(nUserId) --第二次保险结算
	if not Equal(nInsurA, 0) or not Equal(nInsurB, 0) then
		self:Print("InsurSettle nUserId_%d, %.2f,%.2f,%.2f,%.2f", nUserId, nInsurA, nInsurB, nCostA, nCostB)
	end
	local value = 0 --哪个保险中了 4, 5, 4 + 5
	if nInsurA > 0 then
		self.tTableOverview:DealUserInsurance({ nUserId = nUserId, stage = 1, win = nInsurA })
		value = 4
	end
	if nInsurB > 0 then
		self.tTableOverview:DealUserInsurance({ nUserId = nUserId, stage = 2, win = nInsurB })
		value = (value == 0) and 5 or (value + 5)
	end
	local poolSum = tPublicRedis.GetInsureSumPool()
	local win = nInsurA + nInsurB
	local cost = nCostA + nCostB
	self:Print("InsurSettle nUserId_%d, poolSum%.2f win:%.2f cost:%.2f", nUserId, poolSum, win, cost)
	if poolSum == 0 or poolSum < win then
		self:Print("InsurSettle nUserId_%d, not enough pool win:%.2f cost:%.2f", nUserId, win, cost)
		return 0, 0, value
	end
	return win, cost, value
end

function Table:_GetInsureCost(tInsurPanelData, nPlanId, nOutsCnt)
	local tPlan = nil
	for _, v in ipairs(tInsurPanelData.arrInsurancePlan) do
		if v.nPlanId == nPlanId then
			tPlan = v
			break
		end
	end
	if tPlan == nil then
		return nil, -11, 0
	end
	--低水保险	
	if tInsurPanelData.nInsureMode == InsureMode.nLow then
		return tPlan.nCosts, 0, tInsurPanelData.tRemaining.nOdds
	end
	--常规保险
	assert(tInsurPanelData.nInsureMode == InsureMode.nNormal)
	local nNowOdds = self:_GetOutsOdds(nOutsCnt, tInsurPanelData.arrOddsList)
	local nCosts = (tInsurPanelData.tRemaining.nOdds / nNowOdds) * tPlan.nCosts
	nCosts = publicApi.Floor_1(nCosts)

	if GreaterThan(nCosts, tInsurPanelData.nInvestInThisPool) then
		self:Print("_GetInsureCost is true and nChooseCost is Wrong")
		return nil, -11, 0
	end
	--如果存在平分可能,花费不能超过在该池的投入(针对常规保险;低水保险时isPossibleEq恒为false)
	if tInsurPanelData.isPossibleEq and GreaterThan(nCosts, tInsurPanelData.nInvestInThisPool) then
		self:Print("isPossibleEq is true and nChooseCost is Wrong")
		return nil, -10, 0
	end
	return nCosts, 0, nNowOdds
end

function Table:_CheckInsureOuts(tInsurPanelData, arrOuts)
	if tInsurPanelData.nInsureMode == InsureMode.nLow then
		return tInsurPanelData.tRemaining.arrOuts
	end
	--常规保险
	assert(tInsurPanelData.nInsureMode == InsureMode.nNormal)
	if self.nInsureNormalType == 2 then --必须购买全部outs
		return tInsurPanelData.tRemaining.arrOuts
	end
	local tTem = {}
	for _, v in ipairs(tInsurPanelData.tRemaining.arrOuts) do
		tTem[v] = true
	end
	for _, v in ipairs(arrOuts) do
		if not tTem[v] then
			return nil
		end
	end
	return arrOuts
end

local function GetInsurePlanData(arrInsurData, nUserId, nPoolId)
	for _, insurData in ipairs(arrInsurData) do
		if insurData.tPanelData.nInsurUserId == nUserId and nPoolId == insurData.tPanelData.tPool.nPoolId then
			return insurData
		end
	end
end

local function GetInsurePlanDataList(arrInsurData, nUserId)
	local list = {}
	for _, insurData in ipairs(arrInsurData) do
		if insurData.tPanelData.nInsurUserId == nUserId then
			table.insert(list, insurData)
		end
	end
	return list
end

-- 检测所有购买是否能成功
function Table:_checkInsure(tInsurInfo, nBuy, nPlanId, nUserId, sReturnKey)
	local sCount = 0
	local costTotal = 0
	local newPlanId = -2
	if nPlanId == 100 then --100:全保本 101:全满池
		newPlanId = 0
	elseif nPlanId == 101 then
		newPlanId = 1
	elseif nPlanId == -1 then
		newPlanId = -1
	elseif nPlanId == 102 then
		newPlanId = 2
	elseif nPlanId == 103 then
		newPlanId = 3
	elseif nPlanId == 104 then
		newPlanId = 4
	elseif nPlanId == 105 then
		newPlanId = 5
	end
	local newBuy = {}
	if newPlanId ~= -2 then
		local list = GetInsurePlanDataList(tInsurInfo.arrInsurData, nUserId)
		if #list == 0 then
			self:Print("_checkInsure newPlanId buy all baoben err nUserId:%d nPlanId:%d", nUserId, newPlanId)
			self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -1, nUserId = nUserId, nPlanId = nPlanId })
			return
		end
		for _, tUserInsurData in ipairs(list) do
			table.insert(newBuy, { nPoolId = tUserInsurData.tPanelData.tPool.nPoolId, nPlanId = newPlanId })
			if tUserInsurData.nChooseCost then --已经购买过了，不能重复购买
				self:Print("_checkInsure newPlanId baoben Repeat Buy nUserId:%d nPoolId:%d", nUserId,
					tUserInsurData.tPanelData.tPool.nPoolId)
				self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -3, nUserId = nUserId, nPlanId = nPlanId })
				return
			end
			if newPlanId == -1 then
				sCount = sCount + 1
			else
				--检查所选outs是否合法
				local arrOutsAfterCheck = self:_CheckInsureOuts(tUserInsurData.tPanelData, {})
				if arrOutsAfterCheck == nil then
					self:Print("_checkInsure newPlanId Outs Wrong")
					self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -2, nUserId = nUserId, nPlanId = nPlanId })
					return
				end
				self:Print("_checkInsure newPlanId arrOutsAfterCheck:%s", Define.CardsToStr(arrOutsAfterCheck))
				--计算购买该保险方案的花费
				local nChooseCost, nErrCode, nOdds = self:_GetInsureCost(tUserInsurData.tPanelData, newPlanId,
					#arrOutsAfterCheck)
				if nChooseCost == nil then --购买方案合法检查
					nErrCode = nErrCode or -3
					self:Print("_checkInsure newPlanId PlanId Wrong, nUserId:%d nPoolId:%d v.nPlanId", nUserId,
						tUserInsurData.tPanelData.tPool.nPoolId, newPlanId)
					self:_SendToSlave(sReturnKey, "InsurBuyRsp",
						{ nCode = nErrCode, nUserId = nUserId, nPlanId = nPlanId })
					return
				end
				costTotal = costTotal + nChooseCost
				sCount = sCount + 1
			end
		end
		return sCount == #list, costTotal, newBuy
	end
	for _, v in ipairs(nBuy) do
		table.insert(newBuy, { nPoolId = v.nPoolId, nPlanId = v.nPlanId })
		local tUserInsurData = GetInsurePlanData(tInsurInfo.arrInsurData, nUserId, v.nPoolId)
		if not tUserInsurData then
			self:Print("_checkInsure buy param err nUserId:%d nPoolId:%d", nUserId, v.nPoolId)
			self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -1, nUserId = nUserId, nPlanId = v.nPlanId })
			return
		end
		if tUserInsurData.nChooseCost then --已经购买过了，不能重复购买
			self:Print("_checkInsure Repeat Buy nUserId:%d nPoolId:%d", nUserId, v.nPoolId)
			self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -3, nUserId = nUserId, nPlanId = v.nPlanId })
			return
		end
		if v.nPlanId == -1 then
			self:Print("_checkInsure Insure Cancel nUserId:%d nPoolId:%d", nUserId, v.nPoolId)
			sCount = sCount + 1
		else
			--检查所选outs是否合法
			local arrOutsAfterCheck = self:_CheckInsureOuts(tUserInsurData.tPanelData, {})
			if arrOutsAfterCheck == nil then
				self:Print("_checkInsure Outs Wrong")
				self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -2, nUserId = nUserId, nPlanId = v.nPlanId })
				return
			end
			self:Print("_checkInsure arrOutsAfterCheck:%s", Define.CardsToStr(arrOutsAfterCheck))
			--计算购买该保险方案的花费
			local nChooseCost, nErrCode, nOdds = self:_GetInsureCost(tUserInsurData.tPanelData, v.nPlanId,
				#arrOutsAfterCheck)
			if nChooseCost == nil then --购买方案合法检查
				nErrCode = nErrCode or -3
				self:Print("_checkInsure PlanId Wrong, nUserId:%d nPoolId:%d v.nPlanId", nUserId, v.nPoolId, v.nPlanId)
				self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = nErrCode, nUserId = nUserId, nPlanId = v.nPlanId })
				return
			end
			costTotal = costTotal + nChooseCost
			sCount = sCount + 1
		end
	end
	return sCount == #nBuy, costTotal, newBuy
end

--保险购买
function Table:InsurBuyReq(tJsonData, sReturnKey)
	local nUserId = tJsonData.nUserId
	local nPlanId = tJsonData.nPlanId -- -1:全部不买 100:全保本 101:全满池 102 103 104 105
	local arrOuts = tJsonData.arrOuts or {}
	local nBuy = tJsonData.nBuy or {}
	self:Print("InsurBuyReq,nUserId:%d,nPlanId:%d", nUserId, nPlanId)
	self:Print("arrOuts:%s", Define.CardsToStr(arrOuts))
	tBase.LogT("InsurBuyReq nBuy", nBuy)
	if #nBuy == 0 and (nPlanId ~= -1 and nPlanId ~= 100 and nPlanId ~= 101 and nPlanId ~= 102 and nPlanId ~= 103 and nPlanId ~= 104 and nPlanId ~= 105) then
		self:Print("InsurBuyReq buy param err")
		return
	end

	local tInsurInfo = nil
	local stage = 1
	if #self.arrCommunityCards == 3 then
		tInsurInfo = self.tFlopAfterInsur
	elseif #self.arrCommunityCards == 4 then
		tInsurInfo = self.tTurnAfterInsur
		stage = 2
	end
	if tInsurInfo == nil or (not tInsurInfo.isInStage) then --当前是否为保险阶段检查
		self:Print("InsurBuyReq No Insur")
		return
	end
	local ok, sumCost, newBuy = self:_checkInsure(tInsurInfo, nBuy, nPlanId, nUserId, sReturnKey)
	if not ok then
		return
	end
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not tUser or tUser.nStatus == UserStatus.nFold then
		self:Print("InsurBuyReq not user")
		return
	end
	local gold = self:Get_User_UnLockGold(tUser)
	gold = gold - tUser.nInsureCost
	if gold < sumCost then
		self:Print("InsurBuyReq nChooseCost not enought, nUserId:%d", nUserId)
		self:_SendToSlave(sReturnKey, "InsurBuyRsp", { nCode = -4, nUserId = nUserId, nPlanId = nPlanId })
		return
	end

	--辅助函数(回复成功,并结束保险阶段)
	local function _SucceeAndEnd()
		self:_SendToSlave(sReturnKey, "InsurBuyRsp",
			{ nCode = 0, nUserId = nUserId, nPlanId = nPlanId, nCost = sumCost, nSitId = nSitId })
		self:_BroadCastToSlaves("InsurBuyNotify", { nSitId = nSitId, nCost = sumCost })
		local count, buyCount = 1, 1
		local userDict = {}
		for _, insurData in ipairs(tInsurInfo.arrInsurData) do
			if insurData.tPanelData.nInsurUserId ~= nUserId and not userDict[insurData.tPanelData.nInsurUserId] then
				count = count + 1
				if insurData.nPlanId then
					buyCount = buyCount + 1
				end
			end
		end
		if count == buyCount then -- 全部购买完毕进入下一个阶段
			if #self.arrCommunityCards == 3 then
				self:ToEndInsurOfFlopAfter(0.5)
			elseif #self.arrCommunityCards == 4 then
				self:ToEndInsurOfTurnAfter(0.5)
			end
		end
		if sumCost > 0 then
			local reamain = self:CostUserTableGold(tUser, tUser.nUserId, sumCost, true)
			gold = (gold - sumCost) > 0 and (gold - sumCost) or 0
			self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, -sumCost, reamain, GoldCReason.nInsurBuy) --记录复盘下注信息
			self:_SendToSlave(sReturnKey, "GoldNotify", { nUserId = nUserId, nGold = gold })
		end
	end
	for _, v in ipairs(newBuy) do
		local tUserInsurData = GetInsurePlanData(tInsurInfo.arrInsurData, nUserId, v.nPoolId)
		if v.nPlanId == -1 then
			tUserInsurData.nPlanId = -1
			tUserInsurData.nOdds = 0 --倍率
			tUserInsurData.arrOutsAfterCheck = {}
			tUserInsurData.nChooseCost = 0
		else
			--检查所选outs是否合法
			local arrOutsAfterCheck = self:_CheckInsureOuts(tUserInsurData.tPanelData, {})
			self:Print("InsurBuyReq arrOutsAfterCheck:%s", Define.CardsToStr(arrOutsAfterCheck))
			--计算购买该保险方案的花费
			local nChooseCost, nErrCode, nOdds = self:_GetInsureCost(tUserInsurData.tPanelData, v.nPlanId,
				#arrOutsAfterCheck)
			--记下玩家的选择
			tUserInsurData.nPlanId = v.nPlanId
			tUserInsurData.nOdds = nOdds    --倍率
			tUserInsurData.arrOutsAfterCheck = arrOutsAfterCheck
			tUserInsurData.nChooseCost = nChooseCost --记录玩家购买保险的花费 (0或nil表示不买保险,其中nil表示超时不买)
			self:Print("Insure succee, nChooseCost:%.2f,nOdds:%.2f", nChooseCost, nOdds)
		end
	end
	if sumCost > 0 then
		self.tTableOverview:DealUserInsurance({
			nUserId = nUserId,
			isSet = true,
			stage = stage,
			buy = sumCost,
			nPlayCnt =
				self.nPlayCnt
		})
	end
	_SucceeAndEnd()
end

--如果玩家必须购买保险但又没买，则自动帮其购买
function Table:_AutoChooseIfNeccessary(tInsurInfo)
	if tInsurInfo.nChooseCost then
		return
	end
	local tInsurPanelData = tInsurInfo.tPanelData
	if not tInsurPanelData.isMustBuy then
		return
	end
	tInsurInfo.nOdds = tInsurPanelData.tRemaining.nOdds
	tInsurInfo.arrOutsAfterCheck = tInsurPanelData.tRemaining.arrOuts
	tInsurInfo.nChooseCost = self:_GetCostOfLastInsur(tInsurPanelData.nInsurUserId)
	assert(GreaterThan(tInsurInfo.nChooseCost, 0))
	--低水保险
	if tInsurPanelData.nInsureMode == InsureMode.nLow then
		self:Print("Insure AutoChoose,nChooseCost:%.2f,nOdds:%.2f", tInsurInfo.nChooseCost, tInsurInfo.nOdds)
		return
	end
	--常规保险
	assert(tInsurPanelData.nInsureMode == InsureMode.nNormal)
	local nCost = nil
	for _, tPlan in ipairs(tInsurPanelData.arrInsurancePlan) do
		if GreaterOrEqual(tPlan.nCosts * tInsurInfo.nOdds, tInsurInfo.nChooseCost) then
			nCost = nCost or tPlan.nCosts
			nCost = math.min(nCost, tPlan.nCosts)
		end
	end
	assert(nCost ~= nil)
	tInsurInfo.nChooseCost = nCost
	self:Print("Insure AutoChoose,nChooseCost:%.2f,nOdds:%.2f", tInsurInfo.nChooseCost, tInsurInfo.nOdds)
end

--尝试进入买保险阶段(翻牌后的)
function Table:TryGoInInsurOfFlopAfter()
	-- local arrInsurPos = self:_GetInsurPos()
	-- if not arrInsurPos or #arrInsurPos == 0 then
	-- 	self:Print("GoIn Insur Of FlopAfter Fail,no InsurPos")
	-- 	return false
	-- end
	-- local arrPanelData =self:GetInsurPanelData(arrInsurPos, true)
	-- if not arrPanelData or #arrPanelData == 0 then
	--     self:Print("GoIn Insur Of FlopAfter Fail,arrPanelData is empty")
	--     return false
	-- end
	local arrTargets, userDict = self:_GetEligibleInsurPotsAndPlayers()
	if #arrTargets == 0 then
		self:Print("GoIn Insur Of FlopAfter Fail,no InsurPos")
		return false
	end
	tBase.LogT("TryGoInInsurOfFlopAfter userDict", userDict)
	local arrPanelData = {}
	local tempPanelData = {}
	for _, tT in ipairs(arrTargets) do
		local tPool = tT.tPool
		for _, nPos in ipairs(tT.arrInPos) do
			local tPanelData, arrWinRate, eCosts = self:GetInsurPanelData_Normal2(nPos, tT.arrPos, tPool,
				(#self.arrCommunityCards == 3), tT.sameCount)
			if tPanelData then
				local _, tUser = self:_GetSitIdByUserId(tPanelData.nInsurUserId)
				-- local nFullCost = userDict[tPanelData.nInsurUserId] or 0     -- 全部1/5
				if tUser then
					local gold = self:Get_User_UnLockGold(tUser)
					gold = gold - tUser.nInsureCost -- 扣除上次购买保险金币
					local userData = tempPanelData[tPanelData.nInsurUserId] or {}
					table.insert(userData,
						{ tPanelData = tPanelData, arrWinRate = arrWinRate, gold = gold - eCosts, cost = eCosts })
					tempPanelData[tPanelData.nInsurUserId] = userData
					-- table.insert(arrPanelData, {tPanelData = tPanelData, arrWinRate = arrWinRate})
				end
			end
		end
	end
	tBase.LogT("TryGoInInsurOfFlopAfter tempPanelData", tempPanelData)
	local sendFailUsers = {}
	for userId, arr in pairs(tempPanelData) do
		local num = 0
		local temArr = {}
		for _, v in ipairs(arr) do
			if v.gold >= 0 then
				num = num + 1
			else
			end
			table.insert(temArr, { tPanelData = v.tPanelData, arrWinRate = v.arrWinRate })
		end
		if num == 0 then
			table.insert(sendFailUsers, userId)
		else
			appendArray2(arrPanelData, temArr)
		end
	end
	tBase.LogT("TryGoInInsurOfFlopAfter arrPanelData", arrPanelData)
	if #arrPanelData == 0 then
		if next(sendFailUsers) then
			for _, userId in ipairs(sendFailUsers) do
				self:SendFailNotifyV2(nil, userId, MsgCode.nInsurGold, "_InsureNoGold")
			end
		end
		self:Print("GoIn Insur Of FlopAfter Fail,no arrPanelData")
		return false
	end
	self:Print("GoIn Insur Of FlopAfter succee")
	-- 初始化翻牌后保险信息
	self.tFlopAfterInsur = {
		isInStage = true,
		arrInsurData = {} -- 改为数组存储多个玩家的保险数据
	}
	-- 为每个玩家创建保险数据
	for _, panelDataInfo in ipairs(arrPanelData) do
		local tPanelData = panelDataInfo.tPanelData
		self:PrintPanel(tPanelData)
		table.insert(self.tFlopAfterInsur.arrInsurData, {
			tPanelData = tPanelData,
			nChooseCost = nil,
			arrOutsAfterCheck = nil,
			nOdds = nil
		})
	end

	--广播 亮牌 底池变化 弹保险
	local tShowCard = self:_GetInsurProtoShowCard()
	local tPoolChange = self:_GetInsurProtoPoolChange()
	-- 合并所有玩家的胜率信息
	local arrAllWinRate = {}
	local arr = {}
	local now = os.time()
	for _, panelDataInfo in ipairs(arrPanelData) do
		for _, winRate in ipairs(panelDataInfo.arrWinRate) do
			table.insert(arrAllWinRate, winRate)
		end
		local tPanelData = panelDataInfo.tPanelData
		local _, tUser = self:_GetSitIdByUserId(tPanelData.nInsurUserId)
		tUser.nGetRightTime = now
		tUser.nFGetRightTime = now
		self.nInsurePlayers[tPanelData.nInsurUserId] = now + Define.nInsureStageTime
		table.insert(arr, tPanelData)
	end

	self:_BroadCastInsur(arr, tShowCard, tPoolChange, arrAllWinRate)
	if next(sendFailUsers) then
		for _, userId in ipairs(sendFailUsers) do
			self:SendFailNotifyV2(nil, userId, MsgCode.nInsurGold, "_InsureNoGold")
		end
	end

	self.nInsureStageStartTime = now
	self.nInsureStageEndTime = self.nInsureStageStartTime + Define.nInsureStageTime
	-- 一段时间后,结束本保险阶段且发转牌
	self:ToEndInsurOfFlopAfter(Define.nInsureStageTime)
	return true
end

-- 修改广播函数支持多个保险面板
function Table:_BroadCastInsur(arrPanelData, tShowCard, tPoolChange, arrWinRate)
	local InsurNotify = {}
	InsurNotify.tShowCard = tShowCard
	InsurNotify.tPoolChange = tPoolChange
	InsurNotify.arrInsurPanelData = arrPanelData -- 改为数组
	InsurNotify.arrUser = self:_GetPartInUserStatus()
	InsurNotify.arrWinRate = arrWinRate
	self:_BroadCastToSlaves("InsurNotify", InsurNotify)

	for nPos, tUser in pairs(self.arrUsers) do
		self:SendToUser(nPos, "InsurNotify", InsurNotify)
	end
end

function Table:_BroadCastInsurDeal(nCard, arrChoices, hit)
	local InsurDealNotify = {}
	InsurDealNotify.nCard = nCard
	InsurDealNotify.arrUsersCardType = self:_GetInsurProtoUsersCardType()
	InsurDealNotify.arrChoices = arrChoices -- 改为数组，包含所有玩家的选择
	InsurDealNotify.potUsers = self:_GetProtoArrPotUsers()
	InsurDealNotify.nHit = hit

	self:_BroadCastToSlaves("InsurDealNotify", InsurDealNotify)
	for nPos, tUser in pairs(self.arrUsers) do
		self:SendToUser(nPos, "InsurDealNotify", InsurDealNotify)
	end
end

--保险阶段结束(翻牌后的)
function Table:EndInsurOfFlopAfter()
	assert(self.tFlopAfterInsur ~= nil)
	self.tFlopAfterInsur.isInStage = false

	-- 如果玩家必须购买保险但又没买，则自动帮其购买
	-- for _, insurData in ipairs(self.tFlopAfterInsur.arrInsurData) do
	--     self:_AutoChooseIfNeccessary(insurData)
	-- end
	--发转牌
	self:Print("Insur End,Deal Turn")
	assert(#self.arrCommunityCards == 3)
	local arrCardsNewAdd, arrCardType = self:_DealCommunityCards(1)
	self.tReview:DealCard(arrCardsNewAdd, arrCardType, self:_GetProtoArrPot(), true) --回顾记录
	--广播 发转牌(和所有玩家的牌型)
	assert(#arrCardsNewAdd == 1)

	-- 收集所有玩家的保险选择
	local arrChoices = {}
	local hit = 0
	for _, insurData in ipairs(self.tFlopAfterInsur.arrInsurData) do
		local nSitId, _ = self:_GetSitIdByUserId(insurData.tPanelData.nInsurUserId)
		if nSitId then
			local tChoice = {
				nPos = nSitId,
				nChoice = insurData.nChooseCost or 0
			}
			table.insert(arrChoices, tChoice)
			if tChoice.nChoice > 0 then
				local arrOutsAfterCheck = insurData.arrOutsAfterCheck or {}
				local isHit = _IsHaveEle(arrOutsAfterCheck, arrCardsNewAdd[1])
				if isHit then
					hit = 4
				end
			end
		end
	end
	self:_BroadCastInsurDeal(arrCardsNewAdd[1], arrChoices, hit)
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
	assert(#self.arrCommunityCards == 4)
	local arrCardsNewAdd, arrCardType = self:_DealCommunityCards(1)
	--广播 发河牌(和所有玩家的牌型)
	assert(#arrCardsNewAdd == 1)

	local isShowCard = false
	if not self.tFlopAfterInsur then
		isShowCard = true
	end
	self.tReview:DealCard(arrCardsNewAdd, arrCardType, self:_GetProtoArrPot(), isShowCard) --回顾记录

	local arrChoices = {}
	local hit = 0
	if self.tTurnAfterInsur then
		-- 收集所有玩家的保险选择
		for _, insurData in ipairs(self.tTurnAfterInsur.arrInsurData) do
			local nSitId, _ = self:_GetSitIdByUserId(insurData.tPanelData.nInsurUserId)
			if nSitId then
				local tChoice = {
					nPos = nSitId,
					nChoice = insurData.nChooseCost or 0
				}
				table.insert(arrChoices, tChoice)
				if tChoice.nChoice > 0 then
					local arrOutsAfterCheck = insurData.arrOutsAfterCheck or {}
					local isHit = _IsHaveEle(arrOutsAfterCheck, arrCardsNewAdd[1])
					if isHit then
						hit = 5
					end
				end
			end
		end
	end
	self:_BroadCastInsurDeal(arrCardsNewAdd[1], arrChoices, hit)
	self:_TryBroadCastWinRate()
	self:_ToSettle(1.5)
end

--上一次买保险的花费 (也即翻牌后买保险的花费)
function Table:_GetCostOfLastInsur(nInsurUserId)
	if not self.tFlopAfterInsur then
		return 0
	end
	for _, insurData in ipairs(self.tFlopAfterInsur.arrInsurData) do
		local tInsurPanelData = insurData.tPanelData
		if tInsurPanelData.nInsurUserId == nInsurUserId then
			return insurData.nChooseCost or 0
		end
	end
	return 0
end

--尝试进入转牌后买保险阶段
function Table:TryGoInInsurOfTurnAfter()
	-- local arrInsurInfo = self:_GetInsurPos()
	-- if not arrInsurInfo or #arrInsurInfo == 0 then
	--     self:Print("GoIn Insur Of TurnAfter Fail,no InsurPos")
	--     return false
	-- end
	--  local arrPanelData = self:GetInsurPanelData(arrInsurInfo, false)
	-- if not arrPanelData or #arrPanelData == 0 then
	--     self:Print("GoIn Insur Of TurnAfter Fail,arrPanelData is empty")
	--     return false
	-- end
	self.nInsurePlayers = {}
	local arrTargets, userDict = self:_GetEligibleInsurPotsAndPlayers()
	if #arrTargets == 0 then
		self:Print("GoIn Insur Of TurnAfter Fail,no InsurPos")
		return false
	end
	tBase.LogT("TryGoInInsurOfTurnAfter userDict", userDict)
	local arrPanelData = {}
	local tempPanelData = {}
	for _, tT in ipairs(arrTargets) do
		local tPool = tT.tPool
		for _, nPos in ipairs(tT.arrInPos) do
			local tPanelData, arrWinRate, eCosts = self:GetInsurPanelData_Normal2(nPos, tT.arrPos, tPool,
				(#self.arrCommunityCards == 3), tT.sameCount)
			if tPanelData then
				local _, tUser = self:_GetSitIdByUserId(tPanelData.nInsurUserId)
				-- local nFullCost = userDict[tPanelData.nInsurUserId] or 0     -- 全部1/5
				if tUser then
					local gold = self:Get_User_UnLockGold(tUser)
					gold = gold - tUser.nInsureCost
					local userData = tempPanelData[tPanelData.nInsurUserId] or {}
					table.insert(userData,
						{ tPanelData = tPanelData, arrWinRate = arrWinRate, gold = gold - eCosts, cost = eCosts })
					tempPanelData[tPanelData.nInsurUserId] = userData
					-- table.insert(arrPanelData, {tPanelData = tPanelData, arrWinRate = arrWinRate})
				end
			end
		end
	end
	tBase.LogT("TryGoInInsurOfTurnAfter tempPanelData", tempPanelData)
	local sendFailUsers = {}
	for userId, arr in pairs(tempPanelData) do
		local num = 0
		local temArr = {}
		for _, v in ipairs(arr) do
			if v.gold >= 0 then
				num = num + 1
			else
			end
			table.insert(temArr, { tPanelData = v.tPanelData, arrWinRate = v.arrWinRate })
		end
		if num == 0 then
			table.insert(sendFailUsers, userId)
		else
			appendArray2(arrPanelData, temArr)
		end
	end
	tBase.LogT("TryGoInInsurOfTurnAfter arrPanelData", arrPanelData)
	if #arrPanelData == 0 then
		if next(sendFailUsers) then
			for _, userId in ipairs(sendFailUsers) do
				self:SendFailNotifyV2(nil, userId, MsgCode.nInsurGold, "_InsureNoGold")
			end
		end
		self:Print("GoIn InsurOf TurnAfter Fail,no arrPanelData")
		return false
	end
	self:Print("GoIn InsurOf TurnAfter succee")
	-- 初始化转牌后保险信息
	self.tTurnAfterInsur = {
		isInStage = true,
		arrInsurData = {} -- 改为数组存储多个玩家的保险数据
	}
	-- 为每个玩家创建保险数据
	for _, panelDataInfo in ipairs(arrPanelData) do
		local tPanelData = panelDataInfo.tPanelData
		self:PrintPanel(tPanelData)
		table.insert(self.tTurnAfterInsur.arrInsurData, {
			tPanelData = tPanelData,
			nChooseCost = nil,
			arrOutsAfterCheck = nil,
			nOdds = nil
		})
	end
	-- 广播保险信息
	local tShowCard, tPoolChange = nil, nil
	if not self.tFlopAfterInsur then
		tShowCard = self:_GetInsurProtoShowCard()
		tPoolChange = self:_GetInsurProtoPoolChange()
	end
	-- 合并所有玩家的胜率信息
	local now = os.time()
	local arr = {}
	local arrAllWinRate = {}
	for _, panelDataInfo in ipairs(arrPanelData) do
		for _, winRate in ipairs(panelDataInfo.arrWinRate) do
			table.insert(arrAllWinRate, winRate)
		end
		local tPanelData = panelDataInfo.tPanelData
		local _, tUser = self:_GetSitIdByUserId(tPanelData.nInsurUserId)
		tUser.nGetRightTime = now
		tUser.nFGetRightTime = now
		self.nInsurePlayers[tPanelData.nInsurUserId] = now + Define.nInsureStageTime
		table.insert(arr, tPanelData)
	end
	self:_BroadCastInsur(arr, tShowCard, tPoolChange, arrAllWinRate)
	if next(sendFailUsers) then
		for _, userId in ipairs(sendFailUsers) do
			self:SendFailNotifyV2(nil, userId, MsgCode.nInsurGold, "_InsureNoGold")
		end
	end
	self.nInsureStageStartTime = now
	self.nInsureStageEndTime = self.nInsureStageStartTime + Define.nInsureStageTime
	-- 一段时间后,结束本保险阶段且发转牌
	self:ToEndInsurOfTurnAfter(Define.nInsureStageTime)
	return true
end

--保险阶段结束(转牌后的)
function Table:EndInsurOfTurnAfter()
	-- 如果玩家必须购买保险但又没买，则自动帮其购买
	-- for _, insurData in ipairs(self.tTurnAfterInsur.arrInsurData) do
	--     self:_AutoChooseIfNeccessary(insurData)
	-- end

	self.tTurnAfterInsur.isInStage = false
	--进发河牌阶段
	self:GoInDealOfRiver()
end

function Table:ToEndInsurOfTurnAfter(nSeconds)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.EndInsurOfTurnAfter, self)
	self:_UpdateHeartTick()
end

function Table:ToEndDealOfTurnCard(nSeconds)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.EndDealOfTurnCard, self)
	self:_UpdateHeartTick()
end

function Table:ToEndInsurOfFlopAfter(nSeconds)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.EndInsurOfFlopAfter, self)
	self:_UpdateHeartTick()
end

function Table:_DealCardCnt()
	local nCommunityCardsCnt = #self.arrCommunityCards
	if nCommunityCardsCnt == 0 then
		return 3
	end
	if nCommunityCardsCnt == 5 then
		return 0
	end
	return 1
end

function Table:NextRound(nTheOnlyNotFoldPos)
	--重置桌子一些状态
	self.isGapOfNow = false
	self.nTheRightsEndPos = nil --操作权终止位置
	self.nTheHighestBet = 0   --当前最高下注		
	self.nLatelyIncreasesBet = 0 --最近最高下注提升幅度
	self.nIsRoundBet = false  --本轮是否有下注
	--收归玩家下注进底池
	self:_CollectBetToPoolsN(self.arrPosPartIn)
	--没弃牌玩家数
	local arrPosOfNotFold = self:_UserPosOfNotFold()
	local nUserCountOfNotFold = #arrPosOfNotFold
	self:Print("NextRound, nUserCountOfNotFold:%d", nUserCountOfNotFold)
	local nCommunityCardsCnt = #self.arrCommunityCards
	--重置玩家下注和一些状态
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		if tUser.nStatus ~= UserStatus.nFold then
			if nCommunityCardsCnt == 3 then -- 翻牌圈开始
				self.tStatistic:RecordSeeFlop(tUser.nUserId)
			end
			tUser.tPreOpOption = nil
			if tUser.nStatus ~= UserStatus.nAllIn then
				self:_SetUserStatus(tUser, UserStatus.nWaitForOp)
			end
			self:GetUserInsureState(tUser)
		end
	end
	local nDealCardCnt = self:_DealCardCnt() --需要发牌的数量,0时表示不用再发

	--公共牌已够5个,或缺乏玩家竞争底池
	if nDealCardCnt == 0 or #self.arrPosPartIn == 0 or nUserCountOfNotFold <= 1 then
		self:_ToSettle(0.2)
		return
	end

	--发牌动画时间 秒
	local function dealAnimTime(nCnt)
		if nCnt == 1 then return 0.8 end
		if nCnt == 3 then return 2.2 end
		return 0.25 + nCnt * 0.5
	end

	--如果少于两个玩家可以获得操作权，亮牌后,直接发够5个公共牌，然后进行结算
	local nPosToGainRights = self:_NextGainRightsPos(self.nBankerPos)
	if nPosToGainRights == nil or self:_NextGainRightsPos(nPosToGainRights) == nil then
		if self:TryTriggerInsur() then
			return
		end
		local arrCardsNewAdd, arrCardType = self:_DealCommunityCards(nDealCardCnt)
		self.tReview:DealCard(arrCardsNewAdd, arrCardType, self:_GetProtoArrPot(), true) --回顾记录
		self:_BroadCastDeZhouDealNotify(arrCardsNewAdd, true)                      --广播	
		self:_TryBroadCastWinRate()
		self:_ToNextRound(dealAnimTime(#arrCardsNewAdd))                           --进入下一轮(因已发够5牌，下一轮会直接进入结算)
		return
	end

	--初始化玩家可预操作选项
	self:_InitUsersPreOpOption()
	--发牌,第一次发时发3个，后续发1个
	assert(nDealCardCnt > 0)
	local arrCardsNewAdd, arrCardType = self:_DealCommunityCards(nDealCardCnt)
	self.tReview:DealCard(arrCardsNewAdd, arrCardType, self:_GetProtoArrPot(), false) --回顾记录

	--广播
	self:_BroadCastDeZhouDealNotify(arrCardsNewAdd)

	--新一轮，给予第一个玩家操作权
	self.nTheRightsEndPos = nPosToGainRights
	self.nUserIdLeader = self:_GetUserId(nPosToGainRights)
	if arrCardsNewAdd and #arrCardsNewAdd == 3 then
		self:_ToGiveRightsTo(1.2, nPosToGainRights)
	else
		self:_ToGiveRightsTo(0.4, nPosToGainRights)
	end
end

--尝试计算并广播胜率
function Table:_TryBroadCastWinRate()
	local nLen = #self.arrCommunityCards
	if nLen == 0 then
		return
	end
	local arrUsersHoleCard = {}
	local arrPos = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		if tUser.nStatus ~= UserStatus.nFold then
			table.insert(arrUsersHoleCard, _CopyArr(tUser.arrHoleCards))
			table.insert(arrPos, nPos)
		end
	end
	local tDexToWinRate = tAlg.WinRateReal(arrUsersHoleCard, _CopyArr(self.arrCommunityCards))
	local arrWinRate = {}
	for dex, nPos in ipairs(arrPos) do
		local item = {}
		item.nPos = nPos
		item.nWinRate = publicApi.Floor_1((tDexToWinRate[dex] or 0) * 100)
		table.insert(arrWinRate, item)
	end
	self:_BroadCastToSlaves("WinRateNotify", { arrWinRate = arrWinRate })
	self:Print("BroadCastWinRate,%s", tBase.tostring(arrWinRate))
end

--是否需要弹窗提示玩家补充筹码
function Table:_IsShouldPop(tUser)
	return (Equal(tUser.nBalance, 0) and tUser.nBuyTo == 0)
end

-- 结算时间 两个及以上分池 每个池1秒
local function getSettleSec(arrPoolInfo, baseSec)
	local sec = 0
	for nPoolId, item in ipairs(arrPoolInfo) do
		sec = sec + 1
	end
	if sec == 1 then
		sec = 0
	end
	return baseSec + sec
end

--结算
function Table:Settle()
	local nTheOnlyNotFoldPos = self:_IsJustOneNotFold()
	self:Print("Settle_ nTheOnlyNotFoldPos:%s", tostring(nTheOnlyNotFoldPos))
	self.isGapOfNow = false
	self:_SetGameStage(TableState.nSettle)

	--打印底池和公共牌信息
	self:_PrintPools()
	self:Print("arrCommunityCards:%s", Define.CardsToStr(self.arrCommunityCards))

	--付费看的牌
	local nCommunityCardsCnt = #self.arrCommunityCards
	local nDealCnt = 5 - nCommunityCardsCnt
	self.arrCardsOpenForPay = {}
	self.nCardOpenFee = -1 --看牌费用
	if nDealCnt > 0 then
		self.arrCardsOpenForPay = self.tPile:GetCards(nDealCnt, self.arrPreSetCommCardEffect, true)
		local cost = self:_GetCardCost(1).nCost
		self.nCardOpenFee = tonumber(cost) or 0
		if nDealCnt ~= 3 then
			local data = nil
			if #self.arrCommunityCards == 3 then
				data = {}
				data[4] = self.arrCardsOpenForPay[1] --翻牌后发第四张牌
			elseif #self.arrCommunityCards == 4 then
				data = {}
				data[5] = self.arrCardsOpenForPay[1] --转牌后发第五
			end
			if data then
				self.hashHelper:ChangeCurrent(data, true)
			end
		end
	end
	self:Print("arrCardsOpenForPay:%s nCardOpenFee:%.2f", Define.CardsToStr(self.arrCardsOpenForPay), self.nCardOpenFee)
	if #self.arrCardsOpenForPay > 0 then
		self.tReview:DealLessCard(self.arrCardsOpenForPay)
	end

	--打印玩家信息
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local tCardType = tUser.tCardType or {}
		local sHoleCard = Define.CardsToStr(tUser.arrHoleCards)
		local sCardType = Define.CardTypeToStr(tCardType.nCardType or 0)
		local sFiveCard = Define.CardsToStr(tCardType.arrFiveBack or {})
		self:Print("nPos_%d nUserId:%d CardType:%s HodeCard:%s FiveCard:%s Status:%s", nPos, tUser.nUserId, sCardType,
			sHoleCard, sFiveCard, tUser.nStatus)
	end
	--计算玩家输赢
	local tPosToArrWin, nPoolData = self:_UsersWinFromPools(nTheOnlyNotFoldPos)
	--打印金币流向信息
	self:Print("tUserIdToGoldFlowInfo:%s", tBase.tostring(self.tUserIdToGoldFlowInfo))
	local nFoldNum = #self:_UserPosOfNotFold_2()

	local arrUsersWin, arrUsersWin2 = {}, {}
	local arrUserForSlave = {}
	local arrUserMsg = {}
	local sumChouShui = 0
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local tCardType = tUser.tCardType or {}
		local UserGetFromPot = {}
		UserGetFromPot.nPos = nPos                              --座位号
		UserGetFromPot.arrHoleCards = tUser.arrHoleCards        --底牌(该玩家可能在公共牌阶段已亮过牌,前端看重复亮牌会不会有问题)
		UserGetFromPot.arrCombinedCards = tCardType.arrFiveBack or {} --能组成最大牌型的5个牌
		UserGetFromPot.nCardType = tUser.tCardType.nCardType or 0 --牌型(见本文件头部"牌型定义")						
		UserGetFromPot.arrGoldGet = tPosToArrWin[nPos] or {}    --从各个池处中获得的金币
		UserGetFromPot.isWin = self:_IsWin(UserGetFromPot.arrGoldGet) --true时高亮牌型

		--弃牌的机器人随机亮牌
		if tUser.isAndroid and tUser.nStatus == UserStatus.nFold and math.random(1, 100) < 0 then
			tUser.isShowCardWhenEnd = true
		end
		if tUser.isAndroid then --for test
			tUser.isShowCardWhenEnd = true
		end

		--判断玩家是否亮牌
		local isShowCard = true
		if tUser.nStatus == UserStatus.nFold and (not tUser.isShowCardWhenEnd) then
			isShowCard = false
		end
		if nPos == nTheOnlyNotFoldPos then
			isShowCard = false
		end
		if nTheOnlyNotFoldPos or isShowCard == false then
			UserGetFromPot.isWin = false
		end
		local nPaiJuProfit, nChouShui, nInsurProfit, nInsureCardVal, drawChips, nHandProfit = self:_UserChipsSettle(
			tUser, UserGetFromPot.arrGoldGet, true)
		UserGetFromPot.nProfit = nPaiJuProfit          --盈利 >0时显示 "胜利"
		UserGetFromPot.nCmpValue = tUser.tCardType.nComValue --牌型相同时，使用该值来决定大小
		UserGetFromPot.isShowCardWhenEnd = isShowCard  --是否亮牌,true:是 其它:否
		UserGetFromPot.nCurGold = tUser.nBalance       --当前剩余可用筹码
		UserGetFromPot.nInsurProfit = nInsurProfit
		UserGetFromPot.nInsureCardVal = nInsureCardVal
		UserGetFromPot.nDrawChips = drawChips --撤码数值
		-- if not tUser.nHalfFold then                                         --弃牌不放入
		-- 	table.insert(arrUsersWin,UserGetFromPot)
		-- end
		local copy = tBase.DeepCopy(UserGetFromPot)
		copy.nChouShui = nChouShui
		copy.nBetSum = tUser.nBetSum
		copy.nHandProfit = nHandProfit
		table.insert(arrUsersWin2, copy)
		table.insert(arrUsersWin, UserGetFromPot)
		self:Print("nPos_%d isWin:%s Win:%s nPaiJuProfit:%.3f isShowCard:%s", nPos, tostring(UserGetFromPot.isWin),
			cjson.encode(UserGetFromPot.arrGoldGet),
			nPaiJuProfit, tostring(isShowCard))

		if tUser.nStatus ~= UserStatus.nFold then
			if nFoldNum >= 2 then
				self.tStatistic:RecordShowdown(tUser.nUserId)
			end
		end
		sumChouShui = sumChouShui + nChouShui
		local item = {}
		item.nPos = nPos
		item.nUserId = tUser.nUserId
		item.nUnLockGold = self:Get_User_UnLockGold(tUser)
		item.nBalance = tUser.nBalance
		item.isPop = self:_IsShouldPop(tUser)                                                        --是否需要弹窗提示玩家补充筹码
		item.nTempChips = self:Get_User_nTempChips(tUser)
		item.nLoseAmount = tPenaltyManager:GetProfit(tUser.nUserId, self.sTableId, tUser.nLockGoldInTable) -- 从服的输赢不包含保险盈利, 抽水等
		item.nPlayCnt = tPenaltyManager:getPlayCnt(tUser.nUserId, self.sTableId)                     --总局数
		table.insert(arrUserForSlave, item)
		local tMsg = {}
		tMsg.nUserId = tUser.nUserId
		tMsg.nProfit = nPaiJuProfit
		tMsg.nFaceID = tUser.sFaceId
		tMsg.nName = tUser.sName
		tMsg.nPos = tUser.nPos
		tMsg.nPlayCnt = tUser.nPlayCnt
		table.insert(arrUserMsg, tMsg)
		if not isShowCard then
			self.nShouHash = 0
		end
	end
	self:WriteRecords()
	self:UpdateCacheOfTax()                                -- 注意该操作须在WriteRecords()之后
	self.tReview:Settle(self:_GetProtoArrPot(), arrUsersWin2) --回顾记录
	local nPool = self:_GetValPoolSum()
	local nSumBet = self:_GetSumBet()
	self.tStatistic:DoPersist(self.sTableId, self.nGameId, self.nClubId, nPool, self.nInsurPool, self.nGoldType,
		self.nKeepTime, self.sTableName, self.nGroupId, nSumBet, self.nClubIdOfCorrect, self.nRoomId, sumChouShui)
	self.hashHelper:ChangeCurrent(nil, nil, self.nShouHash)
	self.hashHelper:DoPersist()
	self.tReview:InsureDetail(self.tTableOverview:GetInsureDetail()) --保险记录
	self.tReview:DoPersist(self.sTableId, self.nGameId, self.sTableName, self.sPaiJuId)

	if nTheOnlyNotFoldPos then
		self.tWinUserInfo.nCardType = 0
	end

	--广播
	local DeZhouSettleNotify = {}
	DeZhouSettleNotify.arrUsersWin = arrUsersWin --所有玩家牌型与输赢情况(弃牌玩家除外)
	DeZhouSettleNotify.arrPot = self:_GetProtoArrPot()
	DeZhouSettleNotify.nStage = self.nStage
	DeZhouSettleNotify.arrUserForSlave = arrUserForSlave
	DeZhouSettleNotify.nCardOpenFee = self.nCardOpenFee
	-- DeZhouSettleNotify.nPoolData = nPoolData
	self:_BroadCastSettleNotify(DeZhouSettleNotify)

	self:_DealRank(arrUserMsg)
	-- self:NoticeWinMsg(arrUserMsg)              --每一小局都通知

	local sec = getSettleSec(self.arrPoolInfo, self.ToSettleEndTime)
	self:_ToSettleEnd(sec)
end

-- 清理rank数据
function Table:_RemoveNotPartUser(handsDict)
	self.nRemoveTimes = self.nRemoveTimes or 0
	if self.nRemoveTimes > 5 then
		for uid, _ in pairs(self.totalStats) do
			if not handsDict[uid] then
				self.totalStats[uid] = nil
			end
		end
	else
		self.nRemoveTimes = self.nRemoveTimes + 1
	end
end

function Table:_DealRank(arrUserMsg)
	-- 初始化
	if not self.nUserRank then
		self.nUserRank = {
			maxProfit = nil,
			minProfit = nil,
			maxPlayCnt = nil,
		}
	end
	if not self.totalStats then
		self.totalStats = {} -- { [userId] = {profit=0, playCnt=0, name=..., faceId=..., pos=...} }
	end
	-- ① 累加每个玩家的数据
	for _, tMsg in ipairs(arrUserMsg) do
		local uid = tMsg.nUserId
		local profit = tonumber(tMsg.nProfit) or 0
		local playCnt = tonumber(tMsg.nPlayCnt) or 0
		if not self.totalStats[uid] then
			self.totalStats[uid] = {
				nUserId = uid,
				nName = tMsg.nName,
				nFaceID = tMsg.nFaceID,
				nPos = tMsg.nPos,
				nProfit = 0,
				nPlayCnt = 0,
			}
		else
			self.totalStats[uid].nPos = tMsg.nPos
		end
		-- 累加总值
		self.totalStats[uid].nProfit = self.totalStats[uid].nProfit + profit
		self.totalStats[uid].nPlayCnt = self.totalStats[uid].nPlayCnt + playCnt
	end
	local maxProfit, minProfit, maxPlayCnt = nil, nil, nil
	for _, stat in pairs(self.totalStats) do
		-- 盈利最高
		if (not maxProfit) or (stat.nProfit > maxProfit.nProfit) then
			maxProfit = stat
		end
		-- 盈利最低
		if (not minProfit) or (stat.nProfit < minProfit.nProfit) then
			minProfit = stat
		end
		-- 出场最多
		if (not maxPlayCnt) or (stat.nPlayCnt > maxPlayCnt.nPlayCnt) then
			maxPlayCnt = stat
		end
	end
	-- 更新结果
	self.nUserRank.maxProfit = maxProfit
	self.nUserRank.minProfit = minProfit
	self.nUserRank.maxPlayCnt = maxPlayCnt
end

-- 开桌通知机器人
function Table:NoticeOpen()
	local arrUserMsg = {}
	for _, tUser in pairs(self.arrUsers) do
		if tUser.nSitId > 0 then
			local tMsg = {}
			tMsg.nUserId = tUser.nUserId
			tMsg.nProfit = tUser.nBalance
			tMsg.nFaceID = tUser.sFaceId
			tMsg.nName = tUser.sName
			tMsg.nPos = tUser.nSitId
			table.insert(arrUserMsg, tMsg)
		end
	end
	local tMsg = {}
	tMsg.seats = arrUserMsg
	tMsg.baseCfg = self:GetPushMessageBase()
	tgBotMessage.PushTable(tMsg)
end

-- 获取推送消息基础信息
function Table:GetPushMessageBase()
	local t = {}
	t.sTableId = self.sTableId
	t.sTableName = self.sTableName
	t.nGameId = self.nGameId
	t.nRoomId = self.nRoomId
	t.nGroupId = self.nGroupId
	t.nClubId = self.nClubId
	t.nZhuaTou = self.nZhuaTou or 0
	t.nSmallBlind = self.nSmallBlind
	t.nBigBlind = self.nBigBlind
	t.isForceBlind = self.isForceBlind
	t.nForceBlind = self.nForceBlind
	t.nPreAnte = self.nPreAnte or 0
	return t
end

-- 牌桌关闭通知机器人
function Table:NoticeCloseMsg()
	local arr = {}
	if self.nUserRank then
		table.insert(arr, self.nUserRank.maxProfit)
		table.insert(arr, self.nUserRank.minProfit)
		table.insert(arr, self.nUserRank.maxPlayCnt)
	end
	local tMsg = {}
	tMsg.seats = arr
	tMsg.baseCfg = self:GetPushMessageBase()
	tgBotMessage.PushTableWin(tMsg)
	self.totalStats = nil
end

-- 游戏结算通知机器人
function Table:NoticeWinMsg(arrUserMsg)
	if #arrUserMsg == 0 then
		return
	end
	local tMsg = {}
	tMsg.seats = arrUserMsg
	tMsg.baseCfg = self:GetPushMessageBase()
	tgBotMessage.PushTableWin(tMsg)
end

--isAutoNext
function Table:ResetIsAutoNext()
	if (self.nPlayerCntAtLeast and self.nPlayerCntAtLeast >= 2) or self.nRoomType == RoomType.nLobby then
		self.isAutoNext = true
	else
		self.isAutoNext = false
	end
end

function Table:SettleEnd()
	self:Print("SettleEnd nUserCnt:%d", self.nUserCnt)
	self:_SetAndroidLeaveWhenEnd(self.nDecrAndroidCnt) --确保有nDecrAndroidCnt个机器人会离开

	tPublicRedis._UpdateCurPaiJu(self.sTableId)
	self.tTableOverview:PaiJuEnd()
	self:ResetIsAutoNext()

	--local nPool =self:_GetValPoolSum()
	--self.tStatistic:DoPersist(self.sTableId,self.nGameId,self.nClubIdOfCorrect,nPool,self.nInsurPool,self.nGoldType,self.nKeepTime,self.sTableName,self.nGroupId)

	if self.nClubId then
		local tReviewData = self.tReview:GetData()
		local lookData = self.tReview:GetLookData()
		local penaltyData = self.tReview:GetPenaltyData()
		local sLookData = "[]"
		if #lookData > 0 then
			sLookData = json.encode(lookData)
		end
		local sRevieData = json.encode(tReviewData)
		self:Print("sRevieData Len:%d", #sRevieData)
		local sPenaltyData = json.encode(penaltyData)
		--	tPublicRedis._SaveTexasReview(self.sPaiJuId,sRevieData)
		local tData = {}
		tData.nClubId = self.nClubId
		tData.nGameId = self.nGameId
		tData.sTableId = self.sTableId
		tData.sPaiJuId = self.sPaiJuId
		tData.sTableName = self.sTableName
		tData.sPlayBackData = sRevieData
		tData.sLookData = sLookData
		tData.sPenaltyData = sPenaltyData
		tPublicClub.WritePlayBackData(tData)
	end

	if self.isHaveRealUser then
		self:WriteDetail()
	end
	self:_SetGameStage(TableState.nInit)

	--广播桌子重置
	self:_BroadCastTableResetNotify()

	--清理离线与连续两局没操作的玩家
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		if tUser then
			if tUser.isHaveOp or tUser.isRetain then
				tUser.nConsecutiveNoOp = 0
			elseif tUser.nGetChanceCnt > 0 then
				tUser.nConsecutiveNoOp = tUser.nConsecutiveNoOp + 1
			end
			-- if tUser.nOffLineCnt~=0 and (not tUser.isRetain or tUser.isBackToLobby) then  --返回大厅,不保留座位
			-- 	self:_SetLeaveSeat(nPos, tLeaveTableType.nClean)
			if tUser.nOffLineCnt ~= 0 and tUser.nConsecutiveNoOp >= 3 then --游戏中短线托管两局再走
				-- self:_ForceStandUp(nPos,17)
				if not tUser.isRetain then
					if self.tLeaveTableConfig.isOpen and tPenaltyManager:getRetainCount(tUser.nUserId, self.sTableId) > 0 then --离桌限制牌桌只能离桌留座一次
						self:_ForceStandUp(nPos, 17)
					else
						tUser.isRetain = true
						tPenaltyManager:addRetainCount(tUser.nUserId, self.sTableId)
					end
				end
			elseif tUser.nConsecutiveNoOp >= 3 then
				if not tUser.isRetain then
					if self.tLeaveTableConfig.isOpen and tPenaltyManager:getRetainCount(tUser.nUserId, self.sTableId) > 0 then --离桌限制牌桌只能离桌留座一次
						self:_ForceStandUp(nPos, 17)
					else
						tUser.isRetain = true
						tPenaltyManager:addRetainCount(tUser.nUserId, self.sTableId)
					end
				end
				-- self:_ForceStandUp(nPos,17)
			elseif tUser.nStanpUpReason then
				self:_ForceStandUp(nPos, tUser.nStanpUpReason)
			elseif self.nLoseMaxAmount > 0 then
				if tUser.nLoseAmount < 0 and math.abs(tUser.nLoseAmount) >= self.nLoseMaxAmount then
					self:_ForceStandUp(nPos, 30) -- 输钱限制到达
					self:_SavetUserLossMark(tUser.nUserId)
				end
			elseif self.nTakeInLimit > 0 and tUser.nBuyTo > 0 then -- 买入限制检测
				if tUser.nBuyTo + tUser.nBalance > self.nTakeInLimit then
					tUser.nBuyTo = 0
					self:SendFailNotifyV2(nil, tUser.nUserId, 43, "_TakeInLimit")
				end
			end
		end
	end
	--处理需要踢出到大厅的玩家
	for nUserId, _ in pairs(self.tUsersKickToLobbyWhenOver) do
		self:_KickToLobby(nil, nUserId)
	end

	self:_ResetTable()
	self:_ResetUsers()

	local info = {}
	tPubUser.API_ChangeTable(self.sTableId, cjson.encode(info))

	--俱乐部桌子超时判断
	local isTimeOut = self:IsClubTableTimeOut()
	self:Print("self.tableid:%s, IsClubTableTimeOut:%s", self.sTableId, tostring(isTimeOut))

	if isTimeOut then
		self:SetClose(TableCloseReason.nClubTableTimeOut)
		self:Print("table close")
		return
	end

	--关闭桌子还是继续下一局
	local nCloseReason = self:_IsCloseWhenOver()
	if nCloseReason then
		self:CloseTable(nCloseReason)
		return
	end

	--让留座但还没开始计时的玩家，开始计时
	for _, tUser in pairs(self.arrUsers) do
		if tUser.isRetain then
			self:_RetainCountDown(tUser)
		end
	end

	if not self.isPause then
		self:_TryToStartGame()
	else
		self:_Pause()
	end
	self:TransmitProtobuf("DeZhouTableResetNotify", { nNoUse = 0 })

	self:ClubTableInfoNotify({ isStartGame = false })

	return
end

function Table:_GetCards(nSitId)
	local tUser = self:_GetUser(nSitId)
	assert(tUser ~= nil)
	return _CopyArr(tUser.arrHoleCards), _CopyArr(self.arrCommunityCards)
end

--后台改牌
function Table:ChangeCard(sPaiJuId, nCardOriginal, nCardChangeTo)
	if self.sPaiJuId ~= sPaiJuId then
		return false, "PaiJuId Not Match"
	end
	if true then
		return
	end
	if not (isCardValue(nCardOriginal) and isCardValue(nCardChangeTo)) then
		return false, "Card Value Illegal"
	end
	if not self.tPile:IsHaveCard(nCardChangeTo) then
		return false, "nCardChangeTo is Be Used"
	end
	if self.nStage ~= TableState.nPlaying then
		return false, "Not Playing Statu"
	end
	local function _Change(arr)
		for i = 1, #arr do
			if arr[i] == nCardOriginal then
				self.tPile:DelCard(nCardChangeTo)
				self.tPile:BackCard(arr[i])
				arr[i] = nCardChangeTo
				return true
			end
		end
		return false
	end
	local function _ChangeOnly(arr)
		for i = 1, #arr do
			if arr[i] == nCardOriginal then
				arr[i] = nCardChangeTo
				return true
			end
		end
		return false
	end
	local function _UpdateCopy()
		if _ChangeOnly(self.tCurRedisDetail.arrCommunityCard) then
			tPublicRedis._UpdateCurPaiJu(self.sTableId, cjson.encode(self.tCurRedisDetail))
			return true
		end
		for _, v in ipairs(self.tCurRedisDetail.arrUsersInfo) do
			if _ChangeOnly(v.arrHoleCards) then
				tPublicRedis._UpdateCurPaiJu(self.sTableId, cjson.encode(self.tCurRedisDetail))
				return true
			end
		end
		return false
	end
	if _Change(self.arrPreSetCommCardEffect) then
		_UpdateCopy()
		self:_UpdateRank()
		self:Print("change PreSetCommCard")
		return true, "succee"
	end
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		if _Change(tUser.arrHoleCards) then
			tUser.tCardType = tAlg.DeZhouCardType(tUser.arrHoleCards, self.arrCommunityCards)
			_UpdateCopy()
			self:_UpdateRank()
			self:Print("change UserHoleCard")
			return true, "succee"
		end
	end
	return false, "Unknown,maybe user is leave"
end

--根据玩家的当前牌型，更新其排名
function Table:_UpdateRank()
	local arr = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local tCardType = tAlg.DeZhouCardType(tUser.arrHoleCards, self.tCurRedisDetail.arrCommunityCard)
		local item = {}
		item.nCardType = tCardType.nCardType
		item.nComValue = tCardType.nComValue
		item.tUser = tUser
		table.insert(arr, item)
	end
	tAlg.SortByCardType(arr)

	for dex, v in ipairs(arr) do
		v.tUser.nRank = dex
	end
end

--后台踢人 tJsonData,sReturnKey
function Table:REQ_Kick_User(tData, sReturnKey)
	local nUserId = tData.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if not nSitId then
		self:Print("REQ_Kick_User,can not find user_%d", nUserId)
		self:_KickToLobby(nil, nUserId)
		return
	end
	local nType = tData.nType or -1 --1:立即踢出牌桌(令玩家返回大厅) 2:当局结束后踢出牌桌(令玩家返回大厅) 3:当局结束后强制站起
	self:Print("REQ_Kick_User nSitId:%d nUserId:%d nType:%d", nSitId, nUserId, nType)

	if nType == 1 then
		self:_KickToLobby(nSitId, nUserId)
		return
	end
	if nType == 2 then
		if self:_IsPartInUser(nSitId) then
			self.tUsersKickToLobbyWhenOver[nUserId] = true
		else
			self:_KickToLobby(nSitId, nUserId)
		end
	end
	if nType == 3 then
		if self:_IsPartInUser(nSitId) then
			tUser.nStanpUpReason = MsgCode.nKickByAdmin
		else
			self:_ForceStandUp(nSitId, MsgCode.nKickByAdmin, true)
		end
	end
	if nType == 5 then
		if self:_IsPartInUser(nSitId) then
			tUser.nStanpUpReason = MsgCode.nKickToLobbyByAdmin
		else
			self:_ForceStandUp(nSitId, MsgCode.nKickToLobbyByAdmin, true)
		end
	end
	if nType == 6 then
		if self:_IsPartInUser(nSitId) then
			tUser.nStanpUpReason = MsgCode.nKickBan
		else
			self:_ForceStandUp(nSitId, MsgCode.nKickBan, true)
		end
	end
end

--踢出牌桌(通知前端令玩家返回大厅)
function Table:_KickToLobby(nSitId, nUserId)
	if not nSitId then
		nSitId = self:_GetSitIdByUserId(nUserId)
	end
	if nSitId then
		self:_ForceStandUp(nSitId, nil, true)
	end
	self:_BroadCastToSlaves("RSP_Kick_User", { nUserId = nUserId })
end

function Table:_WriteExpRecord(nUserId, nProfit)
	local nNowT = os.time()
	local nLatelyTime = self.tExpUserR[nUserId]
	local nTFlag = (nLatelyTime == nil) and 1 or 0
	local nDuration = nNowT - (nLatelyTime or self.nLatelyStartTime)
	local tData = {}
	tData.nUserId = nUserId
	tData.nGameId = self.nGameId
	tData.nProfit = nProfit
	tData.nTakeIn = self.tStatistic:GetTakeIn(nUserId)
	tData.nDuration = nDuration
	tData.nTFlag = nTFlag
	RecordDbr.WriteTexaExperience(tData)

	self.tExpUserR[nUserId] = nNowT
end

function Table:WriteRecord(nProfix, nTaxGold, tUser, isSettleInEnd, nInsur, sTaxTag, nInsurWin, nInsurCost)
	if tUser.isAndroid then return end
	if self:MatchRoomId() == 0 then
		self:_WriteExpRecord(tUser.nUserId, nProfix)
		return
	end

	local isZhuang = (self.nBankerPos == tUser.nSitId)

	local tData = {}
	tData.nUserId = tUser.nUserId
	tData.nGameType = self.nGameId
	tData.nSession = self.nRoomId
	tData.nWinlose = nProfix
	tData.nDrawWater = nTaxGold
	tData.sPaiJuId = self.sPaiJuId
	tData.nShopId = tUser.nShopId
	tData.nXiaZhu = tUser.nBetSum
	tData.nValid = tUser.nBetSum
	tData.IsControl = false
	tData.nGroupId = self.nGroupId
	if isZhuang then
		tData.nIsZhuang = 1
	else
		tData.nIsZhuang = 0
	end

	if self.nControlUserId == tUser.nUserId then
		tData.IsControl = true
		tData.tElseInfo = { nControlType = self.isControl, nTableType = self.nTableType }
	else
		tData.tElseInfo = { nTableType = self.nTableType }
	end

	tData.tElseInfo.nLumpSumType = 1 --1:正常结算 2:主动认输(弃牌)
	if tUser.nStatus == UserStatus.nFold or (not isSettleInEnd) then
		tData.tElseInfo.nLumpSumType = 2
	end
	tData.tElseInfo.nInsur = nInsur
	tData.tElseInfo.sTaxTag = sTaxTag
	tData.nInsurWin = nInsurWin
	tData.nInsurCost = nInsurCost

	table.insert(self.arrWinLoseRecord, tData) --缓存战绩，统一在结算后再写(因那时才能获得金币流向信息)
	--RecordDbr.Write_WinLoseRecord(tData)

	self:RealUserProfit(nProfix)
end

--按桌抽水记录
function Table:WriteRecordForTax(nUserId, nTaxGold, sTaxTag, sLatelyPaiJuId, isAndroid)
	if self:MatchRoomId() == 0 then return end
	--if isAndroid then return end
	local tData = {}
	tData.nClubId = self.nClubId --俱乐部id
	tData.sTableId = self.sTableId --牌桌id
	tData.nItemId = self.nItemId --道具id
	tData.nGameType = self.nGameId --游戏id
	tData.nGameId = self.nGameId --游戏id
	tData.nUserId = nUserId      --玩家id
	tData.nDrawWater = nTaxGold  --抽水
	tData.sPaiJuId = sLatelyPaiJuId --牌局id
	tData.nClubIdOfCorrect = self.nClubIdOfCorrect
	tData.nGroupId = self.nGroupId
	tData.nSession = self.nRoomId
	tData.isAndroid = isAndroid
	tData.nBigBlind = self.nBigBlind
	tData.nSmallBlind = self.nSmallBlind
	tData.nPreAnte = self.nPreAnte
	tData.nZhuaTou = self.nZhuaTou
	tData.nGoldType = self.nGoldType
	tData.nPreAnteOdd = self.preAnteOdd
	if self.nStage == TableState.nPlaying and self.sPaiJuId == sLatelyPaiJuId then
		table.insert(self.arrTaxForUpdate, tData)
	else
		self.tTableOverview:ProfitAdd(nUserId, -nTaxGold)
		tPublicRedis.TexaStatistic_ProfitAdd(nUserId, -nTaxGold, tData)
		if not isAndroid then
			RecordDbr.Update_WinLoseRecordTaxV2(tData)
		end
	end
end

function Table:UpdateCacheOfTax()
	for _, item in ipairs(self.arrTaxForUpdate) do
		self.tTableOverview:ProfitAdd(item.nUserId, -item.nDrawWater)
		tPublicRedis.TexaStatistic_ProfitAdd(item.nUserId, -item.nDrawWater, item)
		if not item.isAndroid then
			RecordDbr.Update_WinLoseRecordTaxV2(item)
		end
	end
	self.arrTaxForUpdate = {}
end

function Table:WriteRecords()
	for _, item in ipairs(self.arrWinLoseRecord) do
		local tGoldFlowInfo = self.tUserIdToGoldFlowInfo[item.nUserId]
		if tGoldFlowInfo then
			item.nWinloseToRobot = tGoldFlowInfo.nWinFromAndroid + (item.tElseInfo.nInsur or 0) --正确含义应该是:WinFromRobot
			item.nDrawWaterToRobot = -item.nDrawWater
			--if GreaterThan(item.nWinloseToRobot,0) then
			--	item.nDrawWaterToRobot =publicApi.Floor_1(self.nTax*item.nWinloseToRobot/100)
			--end
		else
			item.nWinloseToRobot = item.nWinlose + item.nDrawWater + (item.tElseInfo.nInsur or 0) --正确含义应该是:WinFromRobot
			item.nDrawWaterToRobot = -item.nDrawWater
		end
		item.nClubId = self.nClubId --俱乐部id (俱乐部房配置,否时为nil)
		item.nItemId = self.nItemId --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
		item.sTableId = self.sTableId
		item.nJuShu = self.nJuShu
		item.nGoldType = self.nGoldType
		item.sTableName = self.sTableName
		item.nSmallBlind = self.nSmallBlind
		item.nPreAnte = self.nPreAnte
		item.nZhuaTou = self.nZhuaTou
		item.nPreAnteOdd = self.preAnteOdd
		self.tStatistic:GetUserSData(item)
		local tmpChouType = 0
		if self:IsTotalRake() then
			tmpChouType = 1
		end
		RecordDbr.Write_WinLoseRecord(item, tmpChouType)
		-- RecordDbr.Write_WinLoseRecord(item)
		if item.tElseInfo.nInsur and item.tElseInfo.nInsur ~= 0 then
			RecordDbr.WriteUserRecord(item.nUserId, item.sPaiJuId, item.nGameType, 1, item.tElseInfo.nInsur) --保险记录
		end
	end
	self.arrWinLoseRecord = {}
end

function Table:WriteDetail()
	if self:MatchRoomId() == 0 then return end

	local tElseInfo = {}
	tElseInfo.arrCommunityCards = self.arrCommunityCards
	tElseInfo.arrPool = self:_GetProtoArrPot()
	tElseInfo.tTableInfo = self:GetTableInfoForClub()
	tElseInfo.nClubId = self.nClubId
	tElseInfo.tWinUserInfo = self.tWinUserInfo

	local tData = {}
	tData.sPaiJuId = self.sPaiJuId
	tData.nGameId = self.nGameId
	tData.nRoomId = self.nRoomId
	tData.nAnte = self.nBigBlind
	tData.nZhuang = self.nBankerPos
	tData.tUsersInfo = self.tUsersInfo or {}
	tData.tDealCardInfo = self.tDealCardInfo or {}
	tData.tBetInfo = self.tBetInfo or {}
	tData.tElseInfo = tElseInfo or {}
	tData.sExData = cjson.encode({ sLiveID = self.sLiveID })
	tData.sTableId = self.sTableId
	RecordDbr.Write_PaiJuDetail(tData)
end

function Table:_CancelAuto(tUser)
	tUser.nTimeOutCnt = 0
	if not tUser.isAuto then
		return
	end
	tUser.isAuto = false
	self:_BroadCastCancelAutoNotify(tUser.nSitId)
end

function Table:_IsCloseWhenOver()
	local conditionA = (self.nCloseTableWhenOver == TableCloseReason.nBackstageClose and (tPublicRedis._GetCloseTableStates(self.sTableId) == 1))
	if conditionA then
		return self.nCloseTableWhenOver
	end
	return self.nCloseTableWhenOver
end

--是否一局结束后关闭桌子
function Table:SetClose(nCloseReason)
	self:Print("SetClose,Reason:%d", nCloseReason)
	if self.nStage ~= TableState.nInit then
		self.nCloseTableWhenOver = nCloseReason
		return
	end
	self:CloseTable(nCloseReason)
end

--sReturnKey为nil时广播到所有从服
--nUserId为0时,目标为所有用户
function Table:SendFailNotifyV2(sReturnKey, nUserId, nCode, sErr)
	local DeZhouFailNotify = { nCode = nCode, sErr = sErr }
	DeZhouFailNotify.nUserId = nUserId
	if nCode == 11 or nCode == 12 or nCode == 13 then --金币不足错误码
		local nPos, tUser = self:_GetSitIdByUserId(nUserId)
		DeZhouFailNotify.tRsp = self:_GetProtoTakeInRange(tUser)
	end
	if nCode == 40 or nCode == 30 then
		DeZhouFailNotify.nLoseMaxAmount = self.nLoseMaxAmount
	end
	if nCode == 42 then
		DeZhouFailNotify.nLoseMaxAmount = self:_GetLateSum(nUserId)
	end
	if nCode == 43 then
		DeZhouFailNotify.nLoseMaxAmount = self.nTakeInLimit
	end
	if sReturnKey then
		self:_SendToSlave(sReturnKey, "DeZhouFailNotify", DeZhouFailNotify)
	else
		self:_BroadCastToSlaves("DeZhouFailNotify", DeZhouFailNotify)
	end
end

function Table:_ElapWarnReset(isStop)
	local nRT = self:_GetRemainTime()
	if nRT == -1 then
		return
	end
	self.TimerForElapWarn:KillAllTimer()
	if isStop then
		return
	end
	local arrW = { 10 * 60, 5 * 60, 2 * 60 }
	for _, nW in ipairs(arrW) do
		local nDiff = nRT - nW
		if nDiff > 0 then
			self.TimerForElapWarn:DelayCall(nDiff * 1000, self._ElapWarnBroadCast, self, nW)
		end
	end
end

function Table:_ElapWarnBroadCast(nRemainT)
	if self.tWarnHistory[nRemainT] then
		return
	end
	local nRT = self:_GetRemainTime()
	if math.abs(nRT - nRemainT) > 30 then
		self:Print("_ElapWarnBroadCast Lost,nRemainT:%d Real:%d", nRemainT, nRT)
		return
	end
	self.tWarnHistory[nRemainT] = true
	self:_BroadCastToSlaves("ElapWarn", { nRemainT = nRemainT })
	self:Print("_ElapWarnBroadCast %d Succee", nRemainT)
end

function Table:CloseTable(nReason)
	nReason = nReason or -1
	self:Print("CloseTable,nReason:%d", nReason)
	self.Timer:KillAllTimer()
	self.TimerForAndroid:KillAllTimer()
	self.TimerForPause:KillAllTimer()
	self.TimerForRetain:KillAllTimer()
	self.TimerForElapWarn:KillAllTimer()
	self.TimerForAndroidEnter:KillAllTimer()
	self.TimerForOffline:KillAllTimer()

	-- 清空用户的抽水信息
	for _, tUser in pairs(self.arrUsers) do
		self:ClearUserTax(tUser.nUserId)
	end

	for nPos, _ in pairs(self.arrUsers) do
		self:_SetLeaveSeat(nPos, nReason)
	end
	--处理还没进行按桌抽水的玩家
	self:TaxByTableRateSettle_All()
	-- 处理用户离桌罚款
	self:PenaltyByTableSettle_All(nReason)
	RecordDbr.UpdateTableStatusOnPaiJuWinLossRecord(self.sTableId, 1)

	--广播桌子关闭消息
	self:BroadCastCloseUserData()
	self:_BroadCastTableCloseNotify(nReason)
	taxHelp:clearRoom(self.sTableId)
	tPenaltyManager:clearRoom(self.sTableId)
	self.isTableClose = true --设为true后，桌子不再能发出消息
	self:_ResetTable()
	self.tInterFace._TableClose(self.sTableId, self.nTableType)
	self:NoticeCloseMsg()
end

-- 广播统计用户数据
function Table:BroadCastCloseUserData()
	local dict = self.tStatistic:GetCloseAllUser()
	local arr = {}
	for nPos, tUser in pairs(self.arrUsers) do
		local data = dict[tUser.nUserId]
		if data then
			data.nUserId = tUser.nUserId
			dict[tUser.nUserId] = nil
			table.insert(arr, data)
		end
	end
	if #arr > 0 then
		self:_BroadCastToSlaves("CloseUserDataNotify", { arr = arr })
	end
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
	local cycle = math.min(60, remainTime) --单位 秒, 取牌桌剩余时间和周期的较小值， 保证牌桌到期时能自动关闭

	self.TimerForAndroid:DelayCall(cycle * 1000, self.TableCheck, self)
	--卡桌检查与处理
	if self.nStage ~= TableState.nInit then
		local nCurTime = os.time()
		if (nCurTime - self.nLastHeartTickTime) > 100 then
			self:Print("Table Is Error")
			self.isTableError = true
			self:CloseTable(TableCloseReason.nTableError)
			return
		end
	end
end

--获得桌子剩余时间,-1:表示时间无限制,>=0表示剩余时间
function Table:_GetRemainTime()
	if not self.nKeepTime or self.nKeepTime < 0 then
		return -1
	end
	local nElapsedSum = self.tTimeKeeping.nElapsed
	if self.tTimeKeeping.nNewBeginStamp then
		nElapsedSum = nElapsedSum + (os.time() - self.tTimeKeeping.nNewBeginStamp)
	end

	self:Print("nkeepTime:%d, elapsed:%d", self.nkeepTime or 0, nElapsedSum)
	return math.max((self.nKeepTime - nElapsedSum), 0)
end

--俱乐部桌子是否超时
function Table:IsClubTableTimeOut()
	if self:_GetRemainTime() == 0 then
		return true
	end
	return false
end

--更新机器人数量限制配置
function Table:_UpdateAndroidCntCfg(n)
	local nSeconds = (n == 1) and math.random(2, 5) or math.random(60, 120)
	self.TimerForAndroid:DelayCall(nSeconds * 1000, self._UpdateAndroidCntCfg, self, 0)
	if n == 1 then
		return
	end
	local nMin, nMax = tPublicRedis.AndroidCountLimit(self.nGroupId, self.nGameId, self.nRoomId)
	local isUseDefault = (nMin == nil or nMax == nil or nMin < 0 or nMax < 0 or nMin > nMax)
	if isUseDefault then
		if self:MatchRoomId() == 0 then --试玩房
			self.tAndroidCfg.nMin = self.nCapacity - 1
			self.tAndroidCfg.nMax = self.nCapacity - 1
		else
			self.tAndroidCfg.nMin = 0
			self.tAndroidCfg.nMax = math.floor(self.nCapacity / 2)
		end
	else
		self.tAndroidCfg.nMin = nMin
		self.tAndroidCfg.nMax = nMax
	end
	self:_AndroidCntCfgOffset(self.nBackstageRobotAdd) --后台增减机器人

	self:Print("tAndroidCfg nMin:%d nMax:%d isUseDefault:%s nGroupId:%d nRoomId:%d nGameId:%d nBackstageRobotAdd:%d",
		self.tAndroidCfg.nMin, self.tAndroidCfg.nMax, tostring(isUseDefault), self.nGroupId, self.nRoomId, self.nGameId,
		self.nBackstageRobotAdd)
end

function Table:_AndroidCntCfgOffset(nOffset)
	self.tAndroidCfg.nMin = self.tAndroidCfg.nMin + nOffset
	self.tAndroidCfg.nMax = self.tAndroidCfg.nMax + nOffset
	self.tAndroidCfg.nMin = math.max(self.tAndroidCfg.nMin, 0)
	self.tAndroidCfg.nMax = math.max(self.tAndroidCfg.nMax, 0)
end

--后台递减机器人命令
function Table:OnDecrAndroid()
	self.nBackstageRobotAdd = self.nBackstageRobotAdd - 1
	self:_AndroidCntCfgOffset(self.nBackstageRobotAdd)

	self.nIncrAndroidCnt = 0   --取消需要增加机器人的数量
	if self.nAndroidCnt == 0 then --当前机器人数量为0
		self:Print("OnDecrAndroid nAndroidCnt is 0")
		return
	end
	if self:_DecrAndroid() then --立即减少一个机器人
		self:Print("OnDecrAndroid immediate succee")
		return
	end
	self:Print("OnDecrAndroid delay")
	self.nDecrAndroidCnt = self.nDecrAndroidCnt + 1
end

--后台递增机器人命令
function Table:OnIncrAndroid()
	self.nBackstageRobotAdd = self.nBackstageRobotAdd + 1
	self:_AndroidCntCfgOffset(self.nBackstageRobotAdd)
	self.nDecrAndroidCnt = 0   --取消需要减少机器人的数量
	if self:IsFullCapacity() then --桌子已满人
		self:Print("OnIncrAndroid table is Full")
		return
	end
	if self:_IncrAndroid() then --立即增加一个机器人
		self:Print("OnIncrAndroid immediate succee")
		return
	end
	self:Print("OnIncrAndroid delay")
	self.nIncrAndroidCnt = self.nIncrAndroidCnt + 1
end

--立即递减一个机器人
function Table:_DecrAndroid()
	for nPos = 1, self.nCapacity do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.isAndroid and self:_SetAndroidLeaveImmediate(tUser.nUserId) then
			return true
		end
	end
end

function Table:_SetAndroidLeaveImmediate(nUserId)
	local tAndroid = self.tInterFace.GetUser(nUserId)
	if tAndroid then
		return tAndroid:SetLeaveImmediate()
	end
	return false
end

function Table:_SetLeaveWhenEnd(nUserId)
	local tAndroid = self.tInterFace.GetUser(nUserId)
	if tAndroid then
		return tAndroid:SetLeaveWhenEnd()
	end
	return false
end

--令nCnt个机器人在结束时离开
function Table:_SetAndroidLeaveWhenEnd(nCnt)
	if nCnt <= 0 then
		return
	end
	local n = 0
	for nPos = 1, self.nCapacity do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.isAndroid and self:_SetLeaveWhenEnd(tUser.nUserId) then
			n = n + 1
			if n == nCnt then
				return
			end
		end
	end
end

--尝试增加一个机器人
function Table:_IncrAndroid()
	local arrRobots = self.tInterFace._GetRobots(
		{ nGroupId = self.nGroupId, nRoomId = self.nRoomId, nEnterFloorLimit = self.nBuyMin }, 1)
	local tRobot = arrRobots[1]
	if tRobot == nil then
		return
	end
	if not self:_CheckPoolEntryRate(tRobot.nUserId) then --桌子有入池率限制
		self:_RaiseRobotEntryRate(tRobot.nUserId)
		self:Print("_CheckPoolEntryRate false,nUserId:%d", tRobot.nUserId)
		self.tInterFace._LeaveTable(tRobot.nUserId, self) --归还机器人
		return
	end
	if self.tUserNameToIsUsed[tRobot.sName] then    --发现有机器人昵称重复
		self:Print("Error Repeat NickName:%s,nUserId:%d", tRobot.sName, tRobot.nUserId)
		self.tInterFace._LeaveTable(tRobot.nUserId, self) --归还机器人
		return
	end
	self.tTableOverview:LookerIn(tRobot.nUserId, tRobot.sName, tRobot.sFaceId)

	local _, nSitId = self:OnUserEnter(tRobot)
	if not nSitId then
		self:Print("Error Android Enter Fail")
		self.tInterFace._LeaveTable(tRobot.nUserId, self) --归还机器人
		return
	end
	tRobot:EnterTable(self, nSitId)
	return true
end

--
function Table:_TryLetAndroidEnter(nCallCnt)
	if nCallCnt == 1 then --刚开桌子,隔个两三秒再进机器人
		return math.random(2, 5)
	end
	if self:IsFullCapacity() then --桌子已满人
		return math.random(5, 20)
	end
	if self:_IsMendOpenTableLimitRobot() then
		return math.random(10, 30)
	end

	local nCnt = math.random(self.tAndroidCfg.nMin, self.tAndroidCfg.nMax)
	if self.nAndroidCnt >= nCnt and self.nIncrAndroidCnt <= 0 then
		return math.random(5, 20)
	end
	if not self:_IncrAndroid() then --增加一个机器人
		return math.random(2, 5) --如果增加失败，则加快下一次调用时间
	end
	if self.nIncrAndroidCnt > 0 then
		self.nIncrAndroidCnt = self.nIncrAndroidCnt - 1
	end
	if self.nAndroidCnt > 0 and self.nAndroidCnt >= self.tAndroidCfg.nMax then
		return math.random(20, 60) --机器人数量已达到最大值，则延长下一次调用时间
	end
	if self.nAndroidCnt < self.tAndroidCfg.nMin or self.nIncrAndroidCnt > 0 then
		return math.random(1, 6) --机器人数量过小，则加快下一次调用时间
	end
	return math.random(5, 20)
end

--判断是否加入机器人. (机器人的离开，由该机器人本身决定，玩够随机的一个局数便主动离开)
function Table:TryLetAndroidEnter(n)
	if self.isRobotBan then
		self:Print("Android is ban")
		return
	end
	local nSeconds = self:_TryLetAndroidEnter(n) or 10
	self.TimerForAndroidEnter:KillAllTimer()
	self.TimerForAndroidEnter:DelayCall(nSeconds * 1000, self.TryLetAndroidEnter, self, n + 1)
	--self:_IsMendOpenTableLimitRobot()	
end

-- 是否补桌限制机器人进入： 游戏开始会自动补桌
--返回true:限制机器人进入
function Table:_IsMendOpenTableLimitRobot()
	if self.nContinuedNum == nil or self.nContinuedNum <= 0 or self.nPlayCnt > 0 then
		return false
	end
	local nUserCnt, nRealUserCnt = self:_UserCount()
	local nNowRobotCnt = (nUserCnt - nRealUserCnt)
	local nAllRealUserCnt = self.nSlaveUserCnt -- 全部真人: 旁观+坐下玩
	-- 无真人情况下，机器人数量要低于 自动开始人数
	if nAllRealUserCnt == 0 and self.nStartAtLeast > 0 then
		if nNowRobotCnt > 0 and nNowRobotCnt >= self.nStartAtLeast - 1 then
			self:Print("_IsMendOpenTableLimitRobot  限制机器人进入 补桌_%d 总人数_%d 机器人_%d 真人_[%d/%d] 自动开始_%d "
			, self.nContinuedNum, nUserCnt, nNowRobotCnt, nAllRealUserCnt, nRealUserCnt, self.nStartAtLeast)
			return true
		end
	end
	return false
end

--提升机器人入池率
function Table:_RaiseRobotEntryRate(nUserId)
	local tTableInfo = {
		nClubId = self.nClubId,
		nGameId = self.nGameId,
		nGoldType = self.nGoldType,
		nRoomId = self.nRoomId,
		nSmallBlind = self.nSmallBlind,
		nBigBlind = self.nBigBlind,
		nZhuaTou = self.nZhuaTou,
		nPreAnte = self.nPreAnte
	}
	local tUserData = {}
	tUserData.nUserId = nUserId
	tUserData.nPlayCount = math.random(1, 20)
	tUserData.nInPoolCount = tUserData.nPlayCount
	tUserData.nRaiseCountBFlop = 0
	tUserData.nAllInAndWinCount = 0
	tUserData.nProfitSum = math.random(self.nBigBlind, 5 * self.nBigBlind)
	tPublicRedis.TexaStatistic_WriteN(tTableInfo, { tUserData })
end

--非游戏中才会有动作
function Table:_Pause()
	if self.isToStartGame then
		self:StopTiming()
		self.Timer:KillAllTimer()
		self.isToStartGame = false
		self:_ToPauseCancel(Define.PauseTime)
		self:_BroadToStart(-1, Define.PauseTime) --广播取消倒计时(如果有),并暂停等待
		self.nTimeStart = -1
		return
	elseif self.nStage == TableState.nInit then
		self:StopTiming()
		self:_ToPauseCancel(Define.PauseTime)
		self:_BroadToStart(-1, Define.PauseTime) --广播取消倒计时(如果有),并暂停等待
		self.nTimeStart = -1
		return
	end
end

function Table:_ToPauseCancel(nDelaySeconds)
	--self.TimerForPause
	self.TimerForPause:DelayCall(nDelaySeconds * 1000 + 500, Table._ChangePause, self, false)
end

function Table:_PauseCancel()
	if not self:_TryToStartGame(3) then --如果没进行作为则
		self:_BroadToStart(0)        --广播取消倒计时或暂停(这里为取消暂停)
		self.nTimeStart = 0
	end
	self:BeginTiming()
end

function Table:_TryToStartGame(nToStartTimeMin)
	if self.nStage ~= TableState.nInit then
		self:Print("_TryToStartGame nStage not Init")
		return
	end
	if self.isPause then
		self:Print("_TryToStartGame isPause is true")
		assert((not self.isToStartGame), "isToStartGame Error")
		return
	end
	if not self.isAutoNext then
		self:Print("_TryToStartGame isAutoNext is false")
		assert((not self.isToStartGame), "isToStartGame Error2")
		return
	end
	-- if not self.isTableStart then
	-- 	self:Print("_TryToStartGame isTableStart is false")
	-- 	assert((not self.isToStartGame),"isToStartGame Error3")
	-- 	return
	-- end
	local valueUserCnt = self:_UserCount_NotRetain()
	self:Print("_TryToStartGame valueUserCnt:%d nStartAtLeast:%d isToStartGame:%s",
		valueUserCnt, self.nStartAtLeast, tostring(self.isToStartGame))

	if valueUserCnt < self.nStartAtLeast then
		if self.isToStartGame then
			self.Timer:KillAllTimer()
			self.isToStartGame = false
			self:_BroadToStart(0) --广播取消倒计时或暂停(这里为取消倒计时)
			self.nTimeStart = 0
			return true
		end
	elseif not self.isToStartGame then
		--local nToStartTimeMin =nToStartTimeMin or 1
		self.Timer:KillAllTimer()
		self.isToStartGame = true
		local nSeconds = 0.1
		--if  nSeconds < nToStartTimeMin then nSeconds =nToStartTimeMin end
		self.Timer:DelayCall(nSeconds * 1000 + 50, Table.StartGame, self, false)
		self:_BroadToStart(nSeconds) --广播倒计时时间(毫秒),并取消暂停(如果有)
		self.nTimeStart = os.time() + nSeconds
		return true
	end
end

function Table:_GetUser(nPos)
	return self.arrUsers[nPos]
end

function Table:_GetUserId(nPos)
	local tUser = self.arrUsers[nPos]
	if tUser then
		return tUser.nUserId
	end
end

function Table:_UserCount()
	local nCnt = 0
	local nRealUserCnt = 0
	for nPos = 1, self.nCapacity do
		local tUser = self:_GetUser(nPos)
		if tUser then
			nCnt = nCnt + 1
			if not tUser.isAndroid then
				nRealUserCnt = nRealUserCnt + 1
			end
		end
	end
	return nCnt, nRealUserCnt
end

function Table:_UserCount_NotRetain()
	local nCnt = 0
	for nPos = 1, self.nCapacity do
		local tUser = self:_GetUser(nPos)
		if tUser and (not tUser.isRetain) and self:_IsMoneyCanPartIn(tUser) then
			nCnt = nCnt + 1
		end
	end
	return nCnt
end

function Table:_IsMoneyCanPartIn(tUser)
	if Equal(tUser.nLockGoldInTable, 0) and tUser.nBuyTo == 0 then
		return false
	end
	if Equal((self:Get_User_UnLockGold(tUser) + tUser.nLockGoldInTable + self:Get_User_nTempChips(tUser)), 0) then
		return false
	end
	return true
end

function Table:_ResetTable()
	self:Print("_ResetTable")
	self.tPile = nil          --牌
	self.arrCommunityCards = {} --公共牌
	self.nPotSum = 0          --底池总额(已押筹码总额)
	self.arrPoolInfo = {}
	self.arrPosPartIn = {}    --参与当前牌局的玩家座位号
	self.nTheRightsEndPos = nil --操作权终止位置(一轮开始时为第一个获得操作权的玩家，接着谁提高了下注值便设置为谁的座位号)
	self.nTheHighestBet = 0   --当前最高下注 (牌局中的玩家,除了弃牌和AllIn的玩家外,一轮结束时，所有人下注都会与该值持平)
	self.nLatelyIncreasesBet = 0 --最近一次的nTheHighestBet增幅 (加注提升nTheHighestBet时,提升幅度需>= Max(1个大盲,最近提升幅度))
	self.nIsRoundBet = false  --本轮是否已出现过下注行为(加注/跟注)
	self.isBanStandUpReq = false --游戏中有一些间隙状态, 禁止玩家游戏中站起
	self.isHaveRealUser = false --是否有真人参与本局游戏
	self.nPartInCount = 0     --牌局开始时，参与牌局的玩家数量
	self.nDecrAndroidCnt = 0
	self.nIncrAndroidCnt = 0
	--牌局详情(存放本局里结算了的玩家信息)
	self.tUsersInfo = {}
	self.tDealCardInfo = {}
	self.tBetInfo = {}
	self.tWinUserInfo = {}

	self.isToStartGame = false
	self.nRobotBetSum = 0 --当局当前机器人下注总额

	self.isControl = nil
	self.nControlUserId = nil
	self.nTimeStart = 0
	self.isGapOfNow = false
	self.tUserIdToGoldFlowInfo = {}
	self.arrWinLoseRecord = {}

	self.tFlopAfterInsur = nil --翻牌后保险信息
	self.tTurnAfterInsur = nil --转牌后保险信息

	self.nSeq = 0
	self.arrAiUser = {}
	--[[
	self.nStartAtLeast=(self.nPlayerCntAtLeast or 2)
	self.nStartAtLeast=math.max(self.nStartAtLeast,2)
	]]
	--第一局开始后，后续开始最少人数统一为2人
	self.nStartAtLeast = 2
	self.tUsersKickToLobbyWhenOver = {}
	self.tOpHistory = {}
	self.nShouHash = 1
	self.nIsZhuaTouBet = false
	self.nInsureStageEndTime = 0
	self.nInsureStageStartTime = 0
	self.nInsurePlayers = {}
end

function Table:_SetGameStage(nValueToSet)
	self.nStage = nValueToSet
end

function Table:_ResetUser(tUser)
	tUser.arrHoleCards = {}         --底牌(值为0的牌，显示牌背,表示还没亮牌)
	tUser.nBet = 0                  --玩家当轮当前下注数目(0时不要显示)
	tUser.nStatus = UserStatus.nLooker --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观
	tUser.nOpTimeRemain = 0         --剩余可操作(思考)时间 (思考中时有效,其它情况时为0)
	tUser.tOperation = nil          --当前自己可操作信息(自己为思考状态时有)
	tUser.tPreOpOption = nil        --自己当前可预操作选项
	tUser.tCardType = nil           --结算后存放牌型信息 {nCardType=nCardType,nComValue=nComValue,arrFiveBack=arrFiveBack}
	tUser.isToGainRights = false    --是否即将获得操作权
	tUser.nChipBuy = 0              --一局开始时，新增的筹码买入
	tUser.nTimeOutCnt = 0           --玩家超时次数
	-- tUser.isAuto=false					--是否托管
	tUser.isHaveOp = false          --当局是否有操作
	tUser.nFee = 0                  --记录一局开始时扣减的手续费
	tUser.nRank = nil               --预发牌模式时记录牌型大小,1为最大，次之
	tUser.nBetSum = 0               --当局总下注
	tUser.isShowCardWhenEnd = false --是否结束后亮牌
	tUser.nGetChanceCnt = 0         --当局获得操作机会的次数
	tUser.nStanpUpReason = nil      --当局结束后,是否强制站起(nil:否,非nil:被站起原因)
	-- tUser.nLoseAmount = 0
	tUser.nHalfFold = false
	tUser.nCurCost = 0   --临时金币扣除记录
	tUser.nInsureCost = 0 --保险扣除金币
	tUser.nInsureStatus = 0 --保险可购买状态
	tUser.nDelayCount = 0
	tUser.nInsureDelayCount = 0
end

function Table:_GetBigUserInfo()
	local nRank = 100
	local nBigPos = nil
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		if tUser.nRank == nil then return end
		if tUser.nStatus ~= UserStatus.nFold and tUser.nRank < nRank then
			nRank = tUser.nRank
			nBigPos = nPos
		end
	end
	local tBigUser = self:_GetUser(nBigPos)
	if tBigUser == nil then return end
	return { isAndroid = tBigUser.isAndroid, nPos = nBigPos, nChipSum = tBigUser.nBet + tBigUser.nBalance }
end

function Table:_GetBalance(nPos)
	local tUser = self:_GetUser(nPos)
	if tUser then return tUser.nBalance end
end

function Table:_ResetUsers()
	self:Print("_ResetUsers")
	for nPos, tUser in pairs(self.arrUsers) do
		self:_ResetUser(tUser)
	end
end

function Table:_NextPos(nCurPos)
	return ((nCurPos % self.nCapacity) + 1)
end

--如果返回nil,则表示本轮所有玩家操作权已使用完毕
function Table:_NextGainRightsPos(nCurPos)
	for i = 1, self.nCapacity - 1 do
		--	self:Print("_NextGainRightsPos nCurPos_%d  nCapacity_%d ",nCurPos,self.nCapacity)
		nCurPos = self:_NextPos(nCurPos)
		if nCurPos == self.nTheRightsEndPos then
			return
		end
		if self:_IsCanGainRight(nCurPos) then
			return nCurPos
		end
	end
end

function Table:_IsCanGainRight(nPos)
	local tUser = self:_GetUser(nPos)
	if tUser and tUser.nStatus ~= UserStatus.nAllIn and
		tUser.nStatus ~= UserStatus.nFold and tUser.nStatus ~= UserStatus.nLooker then
		return true
	end
	return false
end

--无力解释的一个辅助函数
function Table:_CheckHoldCardOpen(nRPos)
	local arrUserId = {}
	local nCurPos = self.nFirstPos
	for i = 1, self.nCapacity do
		nCurPos = self:_NextPos(nCurPos)
		if nCurPos == nRPos then
			break
		end
		local tUser = self:_GetUser(nCurPos)
		if tUser and tUser.nStatus ~= UserStatus.nLooker and (not tUser.isShowHoleCard) then
			table.insert(arrUserId, tUser.nUserId)
		end
	end
	if nRPos == self.nFirstPos then
		return arrUserId
	end

	nCurPos = nRPos
	for i = 1, self.nCapacity do
		nCurPos = self:_NextPos(nCurPos)
		if self:_IsCanGainRight(nCurPos) then
			return arrUserId
		end
		if nCurPos == self.nFirstPos then
			break
		end
	end

	nCurPos = nRPos
	for i = 1, self.nCapacity do
		nCurPos = self:_NextPos(nCurPos)
		local tUser = self:_GetUser(nCurPos)
		if tUser and tUser.nStatus ~= UserStatus.nLooker and (not tUser.isShowHoleCard) then
			table.insert(arrUserId, tUser.nUserId)
		end
		if nCurPos == self.nFirstPos then
			break
		end
	end
	return arrUserId
end

--nFirstPos

--下注
function Table:_DoBet(nPos, nBet, reason)
	local tUser = self:_GetUser(nPos)
	assert(tUser ~= nil)
	assert(GreaterOrEqual(tUser.nBalance, nBet), tostring(nBet))
	assert(GreaterThan(nBet, 0), tostring(nBet))

	nBet = publicApi.Floor_2(nBet)
	tUser.nBalance = publicApi.Floor_2(tUser.nBalance - nBet) --余额
	tUser.nBet = tUser.nBet + nBet                         --玩家当轮当前下注数目(0时不要显示)
	tUser.nBetSum = tUser.nBetSum + nBet                   --当局玩家总下注
	self.nPotSum = self.nPotSum + nBet

	self.tStatistic:DoBet(tUser.nUserId, nBet) --玩家下注(当局统计)
	if not tUser.isAndroid then
		local reamain = self:CostUserTableGold(tUser, tUser.nUserId, nBet)
		self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, -nBet, reamain, reason) --记录复盘下注信息
	end

	if tUser.isAndroid then
		self.nRobotBetSum = self.nRobotBetSum + nBet
	end
	self.nIsRoundBet = true
	self:_UpdateAiUsers()
	self:Print("_DoBetForPos_%.2f %.3f", nPos, nBet)
	if GreaterThan(tUser.nBet, self.nTheHighestBet) then
		self.nLatelyIncreasesBet = tUser.nBet - self.nTheHighestBet
		self.nTheHighestBet = tUser.nBet
		return true
	end
end

--返回实际下注成功的数额
function Table:_TryDoBet(nPos, nBet, reason)
	local tUser = self:_GetUser(nPos)
	assert(tUser ~= nil)
	local nAcBet = math.min(tUser.nBalance, nBet)
	if GreaterThan(nAcBet, 0) then
		self:_DoBet(nPos, nAcBet, reason)
		return nAcBet, tUser.nBalance
	end
	return 0, tUser.nBalance
end

--按发牌顺序排序,重新返回一个新数组
function Table:_SortByDeal(arrPosPartIn, nSmallBlindPos)
	local arrA = {}
	local arrB = {}
	local isFind = false
	for _, nPos in ipairs(arrPosPartIn) do
		isFind = (isFind or (nPos == nSmallBlindPos))
		if not isFind then
			table.insert(arrA, nPos)
		else
			table.insert(arrB, nPos)
		end
	end
	for _, nPos in ipairs(arrA) do
		table.insert(arrB, nPos)
	end
	return arrB
end

function Table:_GetCardType(tCardType)
	if tCardType == nil then
		return 0
	end
	return tCardType.nCardType
end

-- 存储用户的抽水值
function Table:StoreUserTax(nUserId, nChouShui)
	if not self.tUserIdToTax then
		self:Print("tUserIdToTax does not exist")
		return 0
	end

	if nUserId and nChouShui and nChouShui > 0 then
		-- 存储抽水值和当前桌子ID
		self.tUserIdToTax[nUserId] = {
			tax = (self.tUserIdToTax[nUserId] and self.tUserIdToTax[nUserId].tax or 0) + nChouShui,
			tableId = self.sTableId
		}
		self:Print("StoreUserTax: userId %d tax %.2f, total %.2f, tableId %s",
			nUserId, nChouShui, self.tUserIdToTax[nUserId].tax, self.sTableId)
	end
end

-- 获取用户存储的抽水值
function Table:GetStoredUserTax(nUserId)
	if not self.tUserIdToTax then
		self:Print("tUserIdToTax does not exist")
		return 0
	end

	local storedData = self.tUserIdToTax[nUserId]
	if storedData then
		return storedData.tax or 0
	end

	return 0
end

-- 检查用户是否在同一个桌子
function Table:IsSameTable(nUserId)
	if not self.tUserIdToTax then
		self:Print("tUserIdToTax does not exist")
		return 0
	end

	local storedData = self.tUserIdToTax[nUserId]
	if storedData then
		return storedData.tableId == self.sTableId
	end

	return false
end

-- 归还用户的抽水值
function Table:ReturnUserTax(nUserId, tUser, sReturnKey)
	if not nUserId then
		self:Print("ReturnUserTax: nUserId is nil")
		return false, 0
	end
	if tUser.isAndroid then
		self:Print("ReturnUserTax: User %d is Android, not returning tax", nUserId)
		return false, 0
	end
	if not self:IsTotalRake() then
		return false, 0
	end
	-- 从 taxHelp 模块获取用户最后一次的抽水值
	local lastTaxed = taxHelp:joinRoom(nUserId, self.sTableId, 0)
	if lastTaxed and lastTaxed > 0 then
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nTaxReturn
		local isSuccess, actualChange = self:Gold_Change(tUser, lastTaxed, nSourceType, self.nRoomId)
		if not isSuccess then
			self:Print("ReturnUserTax: Failed to return tax to user %d, amount: %.2f", nUserId, lastTaxed)
			return false, lastTaxed
		end
		-- 更新用户金币信息
		if tUser then
			tUser.nGold = tUser.nGold + lastTaxed
		end
		self:_SendToSlave(sReturnKey, "GoldNotify", {
			nUserId = nUserId,
			nGold = self:GetUserTableGold(tUser, nUserId)
		})
		self:Print("ReturnUserTax: User %d returned %.2f tax on sitdown", nUserId, lastTaxed)
		self.tTableOverview:ProfitAdd(nUserId, lastTaxed)
		return true, lastTaxed
	end


	-- local storedData = self.tUserIdToTax[nUserId]
	-- if storedData and storedData.tax and storedData.tax > 0 then
	--     -- 检查是否是同一个桌子
	--     if not self:IsSameTable(nUserId) then
	--         self:Print("ReturnUserTax: User %d returned to different table (expected %s, current %s), not returning tax",
	--                    nUserId, storedData.tableId or "nil", self.sTableId)
	--         return false, 0
	--     end

	--     local storedTax = storedData.tax
	--     -- 将抽水返还给用户
	--     local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nTaxReturn  -- 定义一个新的来源类型
	--     local isSuccess, actualChange = self:Gold_Change(tUser, storedTax, nSourceType, self.nRoomId)
	--     if isSuccess then
	--         -- 清除存储的抽水值
	--         self.tUserIdToTax[nUserId] = nil
	--         self:Print("ReturnUserTax: Successfully returned %.2f tax to user %d from same table %s",
	--                    storedTax, nUserId, self.sTableId)

	--         -- 更新用户金币信息
	--         if tUser then
	--             tUser.nGold = tUser.nGold + storedTax
	--         end

	--         -- 广播金币变更通知
	--         self:_SendToSlave(sReturnKey, "GoldNotify", {
	--             nUserId = nUserId,
	--             nGold = self:GetUserTableGold(tUser, nUserId)
	--         })

	--         return true, storedTax
	--     else
	--         self:Print("ReturnUserTax: Failed to return tax to user %d, amount: %.2f",
	--                    nUserId, storedTax)
	--         return false, 0
	--     end
	-- end

	-- return true, 0
end

-- 清除用户的抽水存储（例如用户完全离开桌子时）
function Table:ClearUserTax(nUserId)
	if not self.tUserIdToTax then
		self:Print("tUserIdToTax does not exist")
		return 0
	end

	local storedData = self.tUserIdToTax[nUserId]
	if storedData and storedData.tax and storedData.tax > 0 then
		self:Print("ClearUserTax: Clearing %.2f tax for user %d who left completely from table %s",
			storedData.tax, nUserId, self.sTableId)
	end

	self.tUserIdToTax[nUserId] = nil
end

--玩家筹码结算 (返回的盈利中不包含手续费。)
function Table:_UserChipsSettle(tUser, arrGoldGet, isSettleInEnd)
	if not tUser.isNeedSettle then --预防重复结算
		return
	end
	tUser.isNeedSettle = false
	--保险结算
	local nInsurWin, nInsurCost, cardVal = self:InsurSettle(tUser.nUserId)
	self.tStatistic:AddInsure(nInsurCost, nInsurWin)

	--余额收入
	arrGoldGet = arrGoldGet or {}
	local nChipsGet = 0 --底池收入
	for _, v in ipairs(arrGoldGet) do
		nChipsGet = nChipsGet + v.nGold
	end
	local nInsurGet = GreaterThan(nInsurWin, 0) and nInsurWin or 0 --保险收入
	tUser.nBalance = tUser.nBalance + nChipsGet + nInsurGet
	if nChipsGet > 0 and not tUser.isAndroid then
		local reamain = self:CostUserTableGold(tUser, tUser.nUserId, -nChipsGet)
		self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, nChipsGet, reamain, GoldCReason.nPoolIn) --记录复盘下注信息
	end
	if nInsurGet > 0 and not tUser.isAndroid then
		taxHelp:insuranceWin(tUser.nUserId, self.sTableId, nInsurGet)                                   --记录保险赢取的抽水
		tPenaltyManager:insuranceWin(tUser.nUserId, self.sTableId, nInsurGet)                           --记录保险盈利
		local reamain = self:CostUserTableGold(tUser, tUser.nUserId, -nInsurGet)
		self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, nInsurGet, reamain, GoldCReason.nInsurWin) --记录复盘下注信息
		tPublicRedis.AtomicUpdateInsurePool(-nInsurGet, nInsurCost, 0)
	end

	--余额扣减
	local nInsurNotGold = 0     -- 防止外部金币不够
	local nInsurLoss = -nInsurCost --保险费
	if nInsurLoss < 0 and not tUser.isAndroid then
		-- local reamain = self:CostUserTableGold(tUser, tUser.nUserId, nInsurLoss)
		-- self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, nInsurLoss, reamain, GoldCReason.nInsurBuy) --记录复盘下注信息
		local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nInsurBuy
		local isSuccee, nAcChange = self:Gold_Change(tUser, nInsurLoss, nSourceType, self.nRoomId)
		if not isSuccee then
			self:Print("[ERROR_SETTLE] Error, nInsurLoss:%.2f, nUserId:%d", nInsurLoss, tUser.nUserId) --保险扣除不足
			nInsurNotGold = nInsurLoss
		end
	end
	local nChouShui, sTaxTag = self:CalTax(nChipsGet - tUser.nBetSum, tUser.nUserId, tUser.isAndroid, arrGoldGet) --服务费(保险赢不抽水)
	tUser.nBalance = tUser.nBalance - nChouShui + nInsurNotGold
	if nChouShui > 0 and not tUser.isAndroid then
		local reamain = self:CostUserTableGold(tUser, tUser.nUserId, nChouShui)
		self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, -nChouShui, reamain, GoldCReason.nTableTax) --记录复盘下注信息
		-- 记录抽水信息
		self:StoreUserTax(tUser.nUserId, nChouShui)
	end

	--余额欠费处理
	local nShort = LessThan(tUser.nBalance, 0) and -tUser.nBalance or 0 --欠费(由保险费引起的，导致被玩家白嫖的数额)
	tUser.nBalance = math.max(tUser.nBalance, 0)
	if GreaterThan(nShort, 0) then
		local nUnLockGold = self:Get_User_UnLockGold(tUser)
		local nToLock = math.min(nUnLockGold, nShort)
		if self:Gold_Lock(tUser, nToLock) then
			nShort = nShort - nToLock
		end
	end
	if GreaterThan(nShort, 0) then
		self:Print("[DEBUG_SETTLE] Waring,nShort:%.2f,nUserId:%d", nShort, tUser.nUserId) --欠费警告
	end

	--玩家账户盈利 保险盈利用于提示,净利润
	local nPaiJuProfit = (nChipsGet + nInsurGet) - (nChouShui + tUser.nBetSum) + nShort
	local nInsurProfit, nHandProfit = 0, 0
	nHandProfit = nChipsGet - (nChouShui + tUser.nBetSum) + nShort
	if nPaiJuProfit > 0 and nInsurGet > 0 then
		local num = nChipsGet - (nChouShui + tUser.nBetSum) + nShort
		nInsurProfit = (nInsurGet + num) > 0 and (nInsurGet + num) or 0
	end
	self:Print(
		"[DEBUG_SETTLE] ChipSettle nUserId:%d ,nPos:%d,nPaiJuProfit:%.3f nChipsGet:%.2f nChouShui:%.2f nBalance:%.3f nInsurWin:%.2f nInsurLoss:%.2f tUser.nBetSum:%.2f nShort:%.2f nGoldType:%s nInsurProfit:%.2f",
		tUser.nUserId, tUser.nSitId, nPaiJuProfit, nChipsGet, nChouShui, tUser.nBalance, nInsurWin, nInsurLoss,
		tUser.nBetSum, nShort, tostring(self.nGoldType), nInsurProfit)
	local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nSettle
	self:Print(
		"[DEBUG_SETTLE] Call Gold_ChangeAndReLock, nUserId:%d, nPaiJuProfit:%.3f, nSourceType:%d, nRoomId:%d, nItemId:%s",
		tUser.nUserId, nPaiJuProfit, nSourceType, self.nRoomId, tostring(self.nItemId))
	local isSuccee, nAcChange = self:Gold_ChangeAndReLock(tUser, nPaiJuProfit, nSourceType, self.nRoomId)
	self:Print("[DEBUG_SETTLE] Gold_ChangeAndReLock result: isSuccee=%s, nAcChange=%s", tostring(isSuccee),
		tostring(nAcChange))
	assert(isSuccee)
	self:GetUserTableGold(tUser, tUser.nUserId, true)
	self:Print("[DEBUG_SETTLE] After Gold_ChangeAndReLock, tUser.nGold=%s, tUser.nLockGoldInTable=%s",
		tostring(tUser.nGold), tostring(tUser.nLockGoldInTable))
	nPaiJuProfit = (nAcChange or nPaiJuProfit)

	--记录与统计
	local nInsurActual = nInsurWin - nInsurCost + nShort
	self.nInsurPool = self.nInsurPool - nInsurActual --保险池
	self:WriteRecord(nPaiJuProfit, nChouShui, tUser, isSettleInEnd, nInsurActual, sTaxTag, nInsurWin, nInsurCost)
	local isWin = GreaterThan(nChipsGet, tUser.nBetSum)
	self.tTableOverview:UserSettle(tUser.nUserId, nPaiJuProfit, tUser.nBalance, nHandProfit)
	self.tStatistic:UserProfit(tUser.nUserId, nPaiJuProfit, nInsurActual, nHandProfit)
	self.tStatistic:UserWin(tUser.nUserId, nChipsGet - tUser.nBetSum, tUser.isAndroid)
	self.tStatistic:UserStatic(tUser.nUserId, nPaiJuProfit, nInsurWin - nInsurCost, nHandProfit)
	tUser.nLoseAmount = tUser.nLoseAmount + nPaiJuProfit

	if (not isSettleInEnd) or tUser.nStatus == UserStatus.nFold then
		self.tStatistic:UserGiveUp(tUser.nUserId, tUser.isAndroid)
	end
	if tUser.nStatus == UserStatus.nAllIn and isWin then
		self.tStatistic:UserWinAndAllIn(tUser.nUserId)
	end
	self.tReview:InsureProfit(tUser.nUserId, nInsurActual)

	--错误检测
	if not Equal(tUser.nBalance, tUser.nLockGoldInTable) then
		self:Print("[DEBUG_SETTLE] Error Find,nBalance:%.3f,nLockGoldInTable:%.3f", tUser.nBalance,
			tUser.nLockGoldInTable)
	end
	local ret, drawChips = self:AutoWithdrawChips(tUser, nil, true)
	if ret == 4 then
		drawChips = -1
	end
	--打印redis用户金币信息
	local __, tGoldInfo = self:Get_User_UnLockGold(tUser)
	if tGoldInfo then
		local sGoldInfo = cjson.encode((tGoldInfo or {}))
		self:Print("[DEBUG_SETTLE] AfterChipSettle nUserId:%d sGoldInfo:%s", tUser.nUserId, sGoldInfo)
	end

	--牌局详情信息
	local isFold = false
	if not isSettleInEnd or tUser.nStatus == UserStatus.nFold then
		isFold = true
	end
	local item = {}
	item.nUserId = tUser.nUserId
	item.nSitId = tUser.nSitId
	item.sName = tUser.sName
	item.nProfit = nPaiJuProfit
	item.nDrawWater = nChouShui
	table.insert(self.tUsersInfo, item)
	table.insert(self.tDealCardInfo, {
		nSitId = tUser.nSitId,
		arrCard = tUser.arrHoleCards,
		nCardType = tUser.tCardType.nCardType,
		isFold = isFold,
		isShowCardWhenEnd = tUser.isShowCardWhenEnd
	})
	table.insert(self.tBetInfo, { nSitId = tUser.nSitId, nBet = tUser.nBetSum })
	if isWin then
		self.tWinUserInfo = {
			sName = tUser.sName,
			nUserId = tUser.nUserId,
			nCardType = tUser.tCardType.nCardType,
			nWin =
				nPaiJuProfit
		}
	end
	return nPaiJuProfit, nChouShui, nInsurProfit, cardVal, drawChips, nHandProfit
end

--玩家余额(筹码)转为金币
function Table:_UserBalanceToGold(tUser)
	local isSuccee = self:Gold_UnLockAll(tUser)
	assert(isSuccee)
end

--[[如果玩家当前锁定筹码（tUser.nLockGoldInTable）小于目标值（nBuyTo），则继续。
获取玩家当前可用金币（self:Get_User_UnLockGold(tUser)），并向下取两位小数。
计算还缺多少（nLack = nBuyTo - tUser.nLockGoldInTable），但最多只能锁定玩家现有金币。
调用 self:Gold_Lock(tUser, nLack) 实际锁定金币，断言成功。]]
-- 返回实际买入金额
function Table:_TryBuyUpTo(tUser, nBuyTo, sourceType)
	if LessThan(tUser.nLockGoldInTable, nBuyTo) then
		local curGold = self:Get_User_UnLockGold(tUser)
		curGold = publicApi.Floor_1(curGold)
		local nLack = nBuyTo - tUser.nLockGoldInTable
		local delGold, newLack = self:_GetChipsParam(tUser, nLack)
		newLack = math.min(curGold, newLack)
		self:Print("_TryBuyUpTo nUserId: %d curGold_%.1f [%.1f、%.1f、%.1f] nTempChips:%.2f delGold:%.2f newLack:%.2f",
			tUser.nUserId, curGold, tUser.nLockGoldInTable, nBuyTo, nLack, tUser.nTempChips, delGold, newLack)
		if newLack > 0 then
			local isSuccee = self:Gold_Lock(tUser, newLack, sourceType)
		end
		-- local isSuccee = self:Gold_Lock(tUser, nLack)
		if delGold > 0 then
			self:Deal_User_CanTempChips(tUser, -delGold)
			self:Print(
				"_TryBuyUpTo 2 nUserId: %d curGold_%.1f [%.1f、%.1f、%.1f] nTempChips:%.2f delGold:%.2f newLack:%.2f",
				tUser.nUserId, curGold, tUser.nLockGoldInTable, nBuyTo, nLack, tUser.nTempChips, delGold, newLack)
		end
		return nLack
	end
	return 0
end

-- 获取优先撤码处理值
-- 返回: delGold(要从撤码暂存区扣掉多少), nLack(剩余还差多少需要从金币锁)
function Table:_GetChipsParam(tUser, nLack)
	local chips = self:Get_User_nTempChips(tUser) or 0
	local delGold = 0
	if chips <= 0 or nLack <= 0 then
		return 0, nLack
	end
	if chips >= nLack then
		delGold = nLack -- 暂存区足够，全部用暂存区补
		nLack = 0
	else
		delGold = chips -- 暂存区不够，先把暂存区全用掉
		nLack = nLack - chips
	end
	return delGold, nLack
end

--筹码充值
--nBalanceBest :最佳达到值 ; nEnterMin:至少达到值 优先处理撤码暂存区值
-- sourceType: 充值来源 0 筹码充值, 1 筹码带入
function Table:_InitUserTakeIn(tUser, nBalanceBest, nEnterMin, sourceType)
	nEnterMin = nEnterMin or self.nEnterMin
	local nGoldLockInit = tUser.nLockGoldInTable
	if LessThan(tUser.nLockGoldInTable, nEnterMin) then
		local nLack = nEnterMin - tUser.nLockGoldInTable
		local delGold, newLack = self:_GetChipsParam(tUser, nLack)
		if not self:Gold_Lock(tUser, newLack, sourceType) then
			return false
		end
		if delGold > 0 then
			self:Deal_User_CanTempChips(tUser, -delGold)
		end
		local nBuyTo = math.min(self.nTakeIn, self.nBuyMax)
		self:_TryBuyUpTo(tUser, nBuyTo, sourceType)
	end
	self:_TryBuyUpTo(tUser, nBalanceBest, sourceType)
	local nNewLock = (tUser.nLockGoldInTable - nGoldLockInit)
	if LessThan(nNewLock, 0) then
		nNewLock = 0
	end
	-- 记录玩家买入信息. hhhh
	if self:IsTotalRake() and not tUser.isAndroid then
		taxHelp:buyChip(tUser.nUserId, self.sTableId, nNewLock)
	end
	tPenaltyManager:buyChip(tUser.nUserId, self.sTableId, nNewLock)
	return true, nNewLock
end

--nOpId -20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx -23:结束后亮牌 -24:亮牌
function Table:_InitUsersPreOpOption(isClearNotFoldUser)
	local function _InitUser(tUser)
		if isClearNotFoldUser then
			if tUser.nStatus ~= UserStatus.nFold then
				tUser.tPreOpOption = nil
			end
			return
		end
		if tUser.nStatus == UserStatus.nAllIn or tUser.isAuto or (not tUser.isShowHoleCard) then
			tUser.tPreOpOption = nil
			return
		end
		tUser.tPreOpOption = tUser.tPreOpOption or { arrOption = {} }
		local arrOption = tUser.tPreOpOption.arrOption
		if tUser.nStatus == UserStatus.nFold then
			arrOption[1] = arrOption[1] or { nOpId = -23, isOn = false }
			arrOption[2] = nil
			arrOption[3] = nil
			return
		end
		local nOpIdB = -21                                             --过牌
		if LessThan(tUser.nBet, self.nTheHighestBet) then
			nOpIdB = math.min(self.nTheHighestBet - tUser.nBet, tUser.nBalance) --跟xx
			if self.isAOF then
				nOpIdB = tUser.nBalance
			end
		end
		arrOption[1] = arrOption[1] or { nOpId = -20, isOn = false }
		arrOption[2] = arrOption[2] or { nOpId = nOpIdB, isOn = false }
		arrOption[3] = arrOption[3] or { nOpId = -22, isOn = false }
		if arrOption[2].nOpId ~= nOpIdB then
			arrOption[2] = { nOpId = nOpIdB, isOn = false }
		end
	end
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		_InitUser(tUser)
	end
end

function Table:_GetPreOpIdOfOn(tPreOpOption)
	if tPreOpOption == nil then
		return
	end
	for _, item in ipairs(tPreOpOption.arrOption) do
		if item.isOn then
			return item.nOpId
		end
	end
end

function Table:_TryLetRealUserWin(arrUser, nUserId)
	local tTargetUser = nil
	local arrAndoidUser = {}
	local arrElseUser = {}
	local tNowWinUser = nil

	for _, tUser in ipairs(arrUser) do
		if tUser.nUserId == nUserId then
			tTargetUser = tUser
		elseif tUser.isAndroid then
			table.insert(arrAndoidUser, tUser)
		else
			table.insert(arrElseUser, tUser)
		end
		if tUser.nRank == 1 then
			tNowWinUser = tUser
		end
	end

	if tTargetUser == nil or tNowWinUser == nil then
		return false
	end
	if tNowWinUser.nUserId == nUserId then
		return true
	end

	local tUserShouldWin = tTargetUser

	--将最大牌型调换到 tUserShouldWin 身上
	local arrPreSetHoleCard = tNowWinUser.arrPreSetHoleCard
	local nRank = tNowWinUser.nRank

	tNowWinUser.arrPreSetHoleCard = tUserShouldWin.arrPreSetHoleCard
	tNowWinUser.nRank = tUserShouldWin.nRank

	tUserShouldWin.arrPreSetHoleCard = arrPreSetHoleCard
	tUserShouldWin.nRank = nRank
	return true
end

function Table:_TryLetAndroidWin(arrUser, nUserId)
	local tTargetUser = nil
	local arrAndoidUser = {}
	local arrElseUser = {}
	local tNowWinUser = nil

	for _, tUser in ipairs(arrUser) do
		if tUser.nUserId == nUserId then
			tTargetUser = tUser
		elseif tUser.isAndroid then
			table.insert(arrAndoidUser, tUser)
		else
			table.insert(arrElseUser, tUser)
		end
		if tUser.nRank == 1 then
			tNowWinUser = tUser
		end
	end
	if tTargetUser == nil or tNowWinUser == nil then
		return false
	end
	if tNowWinUser.isAndroid then
		return true
	end
	local tUserShouldWin = arrAndoidUser[1] or arrElseUser[1]
	if tUserShouldWin == nil then
		return false
	end
	local arrPreSetHoleCard = tNowWinUser.arrPreSetHoleCard
	local nRank = tNowWinUser.nRank

	tNowWinUser.arrPreSetHoleCard = tUserShouldWin.arrPreSetHoleCard
	tNowWinUser.nRank = tUserShouldWin.nRank

	tUserShouldWin.arrPreSetHoleCard = arrPreSetHoleCard
	tUserShouldWin.nRank = nRank
	return true
end

function Table:_IsNeedControl(arrUserId)
	local nUserIdCtrlToWin = nil
	for _, nUserId in ipairs(arrUserId) do
		local nCtrlType = tPubUser.IsNeedControl(self.nGameId, self.nRoomId, nUserId)
		if nCtrlType == 2 or nCtrlType == 3 then
			return nUserId, nCtrlType
		elseif nCtrlType == 4 then
			nUserIdCtrlToWin = nUserId
		end
	end
	if nUserIdCtrlToWin then
		return nUserIdCtrlToWin, 4
	end
	return 0, 0
end

function Table:_WriteCurDetailToRedis()
	local tem = {}
	tem.sPaiJuId = self.sPaiJuId
	tem.arrCommunityCard = _CopyArr(self.arrPreSetCommCardEffect)
	tem.arrUsersInfo = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local item = {}
		item.arrHoleCards = _CopyArr(tUser.arrHoleCards)
		item.nUserId = tUser.nUserId
		item.sName = tUser.sName
		item.isAndroid = tUser.isAndroid
		item.nRank = nPos --tUser.nRank
		table.insert(tem.arrUsersInfo, item)
	end
	self.tCurRedisDetail = tem
	local sCurPaiJu = cjson.encode(tem)
	tPublicRedis._UpdateCurPaiJu(self.sTableId, sCurPaiJu)
end

function Table:_CancelRights(tNotFoldUser)
	tNotFoldUser.tOperation = nil
	tNotFoldUser.tPreOpOption = nil
end

function Table:DoOpForUser(nPos, nOp, nCallOrRaiseChip)
	local tUser = self:_GetUser(nPos)
	assert(tUser ~= nil)
	assert(tUser.tOperation ~= nil)
	self:_CancelRights(tUser)
	self:Print("DoOpForPos_%d,nOp:%s", nPos, Define.UserOpToStr(nOp))
	local nIsRoundBet = self.nIsRoundBet

	local isIncreasesBet = false
	if nOp == UserOp.nFold then
		self:_SetUserStatus(tUser, UserStatus.nFold)
		nCallOrRaiseChip = 0
	elseif nOp == UserOp.nAllIn then
		self:_SetUserStatus(tUser, UserStatus.nAllIn)
		nCallOrRaiseChip = tUser.nBalance
		isIncreasesBet = self:_DoBet(nPos, nCallOrRaiseChip, GoldCReason.nAllIn)
	elseif nOp == UserOp.nPass then
		self:_SetUserStatus(tUser, UserStatus.nPass)
		nCallOrRaiseChip = 0
	elseif nOp == UserOp.nCall then
		self:_SetUserStatus(tUser, UserStatus.nCall)
		assert(GreaterOrEqual(nCallOrRaiseChip, 0))
		isIncreasesBet = self:_DoBet(nPos, nCallOrRaiseChip, GoldCReason.nCall)
	elseif nOp == UserOp.nRaise then
		self:_SetUserStatus(tUser, UserStatus.nRaise)
		assert(GreaterOrEqual(nCallOrRaiseChip, 0))
		isIncreasesBet = self:_DoBet(nPos, nCallOrRaiseChip, GoldCReason.nRaise)
	else
		assert(false)
	end
	--当前最高下注被提升了,其他玩家重新获得操作权
	if isIncreasesBet then
		self.nTheRightsEndPos = nPos
		self.nUserIdLeader = self:_GetUserId(nPos)
	end
	--操作结束(即将轮到下一玩家操作，或即将结束本轮)
	local isHasNextUser = self:_OpEnd(nPos)
	--初始化玩家可预操作选项
	if isHasNextUser then
		self:_InitUsersPreOpOption() --设置玩家的预操作
	else
		self:_InitUsersPreOpOption(true) --清除非弃牌玩家的预操作
	end
	--广播有玩家操作通知
	self:_BroadCastOpNotify(nPos, nOp, nCallOrRaiseChip, tUser, nIsRoundBet)

	--统计玩家操作次数
	self:_AddOpCount(tUser.nUserId, nOp)

	--一些统计和记录
	local nTimeUse = math.max((os.time() - tUser.nFGetRightTime), 1)
	self.tReview:DoOp(nPos, nOp, nCallOrRaiseChip, nTimeUse) --回顾记录
	if GreaterThan(nCallOrRaiseChip, 0) then
		if #self.arrCommunityCards == 0 then
			self.tTableOverview:UserInPool(tUser.nUserId) --玩家入池(桌子总览)
			self.tStatistic:UserInPool(tUser.nUserId) --玩家入池(当局统计)
		end
	end
	if isIncreasesBet and #self.arrCommunityCards == 0 then
		self.tStatistic:UserDoRaiseBeforeFlop(tUser.nUserId) --翻牌前加注(当局统计)
	end
	if nOp == UserOp.nFold then                        -- 中途弃牌
		if #self.arrCommunityCards < 5 then
			tUser.nHalfFold = true
			self.nShouHash = 0
		end
	end
	if nOp == UserOp.nAllIn then
		self.tStatistic:UserAllIn(tUser.nUserId)
	end
	self.tStatistic:UserSelfOp(tUser.nUserId)
	self.tTableOverview:UserSelfOp(tUser.nUserId)
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
	local nPosToGainRights = self:_NextGainRightsPos(nPos)
	if nPosToGainRights then
		self:_ToGiveRightsTo(0.4, nPosToGainRights)
		return true
	end
	self:_ToNextRound(0.2)
end

--本回合是否只剩一个没弃牌的玩家 (在上一回合AllIn或弃牌的玩家不包含在本回合里)
function Table:_IsJustOneNotFoldInCurRound()
	self:Print("TableState.nPlaying:%d self.nStage:%d", TableState.nPlaying, self.nStage)
	-- assert(TableState.nPlaying == self.nStage)
	if TableState.nPlaying ~= self.nStage then
		return
	end
	local cnt = 0
	local tTargetUser = nil
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		-- assert(tUser ~= nil, tostring(nPos))
		if tUser == nil then
			tBase.LogError("_IsJustOneNotFoldInCurRound tUser == nil, nPos: %d", nPos or -1)
			goto continue
		end
		if tUser.nStatus ~= UserStatus.nFold then
			if not (tUser.nStatus == UserStatus.nAllIn and Equal(tUser.nBet, 0)) then --AllIn但下注为0的玩家属于上一回合玩家
				cnt = cnt + 1
				tTargetUser = tUser
			end
		end
	    ::continue::
	end
	-- assert(cnt >0)
	if (cnt == 1) then
		return tTargetUser.nSitId, tTargetUser
	end
end

function Table:_IsJustOneNotFold()
	local arrPosOfNotFold = self:_UserPosOfNotFold()
	if #arrPosOfNotFold == 1 then
		return arrPosOfNotFold[1]
	end
end

--牌局中没弃牌的玩家位置
function Table:_UserPosOfNotFold_2()
	local arrPos = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.nStatus ~= UserStatus.nFold then
			table.insert(arrPos, nPos)
		end
	end
	return arrPos
end

--牌局中没弃牌的玩家位置
function Table:_UserPosOfNotFold()
	assert(TableState.nPlaying == self.nStage)
	local arrPos = {}
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil, tostring(nPos))
		if tUser.nStatus ~= UserStatus.nFold then
			table.insert(arrPos, nPos)
		end
	end
	return arrPos
end

function Table:_SetUserStatus(tUser, nValueToSet)
	tUser.nStatus = nValueToSet
end

--用于打印
function Table:_OperationRightsToStr(tOperation)
	if tOperation == nil then return "Nil" end
	local sBtnA = Define.UserOpToStr(tOperation.nOpA)
	local sBtnB = Define.UserOpToStr(tOperation.nOpB)
	local sBtnC = Define.UserOpToStr(tOperation.nOpC)
	local sStr = string.format("%s,%s,%s", sBtnA, sBtnB, sBtnC)
	if tOperation.tRaiseChoice then
		local sRaiseRange = string.format(" RaiseRange:[%.3f,%.3f]", tOperation.tRaiseChoice.nMin,
			tOperation.tRaiseChoice.nMax)
		sStr = sStr .. sRaiseRange
		if #tOperation.tRaiseChoice.arrQuickRaise > 0 then
			local sQuickRaise = string.format(" QuickRaise:%s", table.concat(tOperation.tRaiseChoice.arrQuickRaise, ","))
			sStr = sStr .. sQuickRaise
		end
	end
	return sStr
end

--给予玩家操作权
function Table:GiveRightsTo(nPosToGainRights)
	local tUser = self:_GetUser(nPosToGainRights)
	assert(tUser ~= nil)
	tUser.nGetChanceCnt = tUser.nGetChanceCnt + 1
	self:_SetUserStatus(tUser, UserStatus.nThinking)
	tUser.nGetRightTime = os.time()
	tUser.nFGetRightTime = os.time()
	tUser.isToGainRights = false
	-- tUser.nDelayCount =0
	-- tUser.nInsureDelayCount = 0
	tUser.tOperation = self:_GetProtoOperationRights(nPosToGainRights)
	local nPreOpIdOfOn = self:_GetPreOpIdOfOn(tUser.tPreOpOption)
	tUser.tPreOpOption = nil
	tUser.nOpLong = self.nOperateTime
	self:Print("GiveRightsToPos_%d,%s,nPreOpIdOfOn:%s", nPosToGainRights, self:_OperationRightsToStr(tUser.tOperation),
		tostring(nPreOpIdOfOn))

	--nOpId -20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx
	if nPreOpIdOfOn == -20 or nPreOpIdOfOn == -21 then
		if tUser.tOperation.nOpB == UserOp.nPass then
			self:DoOpForUser(nPosToGainRights, UserOp.nPass)
			return
		else
			self:DoOpForUser(nPosToGainRights, UserOp.nFold)
			return
		end
	elseif nPreOpIdOfOn == -22 or (nPreOpIdOfOn and GreaterThan(nPreOpIdOfOn, 0)) then
		if GreaterThan(tUser.tOperation.nOpB, 0) then
			self:DoOpForUser(nPosToGainRights, UserOp.nCall, tUser.tOperation.nOpB)
			return
		elseif tUser.tOperation.nOpB == UserOp.nAllIn then
			self:DoOpForUser(nPosToGainRights, UserOp.nAllIn, 0)
			return
		elseif tUser.tOperation.nOpB == UserOp.nPass then
			self:DoOpForUser(nPosToGainRights, UserOp.nPass, 0)
			return
		end
	end
	if tUser.isAuto then
		self:_ToOpForTimeOutUser(1, nPosToGainRights)
	else
		self:_ToOpForTimeOutUser(self.nOperateTime, nPosToGainRights)
	end

	local isDoOpenHodeCard = false --是否进行底牌公开
	if not tUser.isShowHoleCard then
		tUser.isShowHoleCard = true
		isDoOpenHodeCard = true
	end
	local arrUserIdNeedOpenHodeCard = {} --除了当前获得操作权的玩家外，还需要进行底牌公开的玩家id
	if isDoOpenHodeCard then
		arrUserIdNeedOpenHodeCard = self:_CheckHoldCardOpen(nPosToGainRights)
	end
	for _, nUserIdNeed in ipairs(arrUserIdNeedOpenHodeCard) do
		local _, tUserr = self:_GetSitIdByUserId(nUserIdNeed)
		assert(tUserr ~= nil)
		tUserr.isShowHoleCard = true
	end
	if #arrUserIdNeedOpenHodeCard > 0 then
		self:Print("arrUserIdNeedOpenHodeCard:%s", table.concat(arrUserIdNeedOpenHodeCard))
	end

	--广播有玩家获得操作权
	self:_BroadCastGetRightNotify(tUser, nPosToGainRights, isDoOpenHodeCard, arrUserIdNeedOpenHodeCard)
end

function Table:_ToGiveRightsTo(nSeconds, nPosToGainRights)
	local tUser = self:_GetUser(nPosToGainRights)
	assert(tUser ~= nil)
	tUser.isToGainRights = true --即将获得操作权
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.GiveRightsTo, self, nPosToGainRights)
	self:_UpdateHeartTick()
end

function Table:_ToNextRound(nSeconds, nTheOnlyNotFoldPos)
	self.isGapOfNow = true
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.NextRound, self, nTheOnlyNotFoldPos)
	self:_UpdateHeartTick()
end

function Table:_ToSettle(nSeconds, nTheOnlyNotFoldPos)
	self.isGapOfNow = true
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.Settle, self, nTheOnlyNotFoldPos)
	self:_UpdateHeartTick()
end

function Table:_ToSettleEnd(nSeconds)
	nSeconds = nSeconds or self.ToSettleEndTime or 0
	if nSeconds < 1 then
		nSeconds = 1
	end
	-- self.nSettleEndTime = os.time() + nSeconds
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.SettleEnd, self)
	self:_UpdateHeartTick()
end

--返回:{{nPos=?,nGoldWin=?}}
function Table:_CalPoolItemWin(item)
	--非弃牌且非中途离开玩家牌型，才能参与底池争夺
	local arrNotFoldUsersCardType = {}
	for _, nPos in ipairs(item.arrPosForm) do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.nStatus ~= UserStatus.nFold and tUser.nStatus ~= UserStatus.nLooker then --该判断用意:该人已经中途离开或该位置已经被旁观玩家替换
			assert(tUser.tCardType ~= nil)
			tUser.tCardType.nPos = nPos
			tUser.tCardType.nUserId = tUser.nUserId
			tUser.tCardType.isAndroid = tUser.isAndroid
			table.insert(arrNotFoldUsersCardType, tUser.tCardType)
		end
	end
	--跳结算时,胜利玩家可能站起了,导致底池没人领取n
	if #arrNotFoldUsersCardType == 0 then
		return {}
	end
	--对牌型进行排序，获得最大牌型的元素
	local arrTheWinItem = tAlg.TheWinCardType(arrNotFoldUsersCardType)
	local totalUser = #arrTheWinItem
	assert(totalUser > 0)
	--最大牌型的玩家平分该底池
	local arrRlt = {}
	-- local nGoldWin = publicApi.Floor_1(item.nPool/#arrTheWinItem) --这里流失精度,是否会产生问题
	-- if totalUser == 1 then
	-- 	nGoldWin = item.nPool
	-- end
	local pool = item.nPool
	for idx, v in ipairs(arrTheWinItem) do
		local gold_per = totalUser - idx + 1 --当前未获取底池的玩家数量
		if gold_per <= 0 then
			break
		end
		local nGoldWin = 0
		if gold_per > 1 then
			nGoldWin = publicApi.Floor_1(pool / gold_per)
		else
			nGoldWin = pool
		end
		table.insert(arrRlt, { nPos = v.nPos, nGoldWin = nGoldWin })
		self:_WinFromAndroid(v.nUserId, v.isAndroid, item.tAndroidToPoolForm, totalUser) --记录金币流向(机器人真人之间)
		self:_WinFromReal(v.nUserId, v.isAndroid, item.tRealUserToPoolForm, totalUser) --记录金币流向(机器人真人之间)
		pool = pool - nGoldWin
	end
	return arrRlt
end

function Table:_WinFromAndroid(nUserId, isAndroid, tAndroidToPoolForm, nWinCnt)
	local function _AssertInfoExist(nId)
		self.tUserIdToGoldFlowInfo[nId] = self.tUserIdToGoldFlowInfo[nId] or { nWinFromAndroid = 0, nWinFromReal = 0 }
		return self.tUserIdToGoldFlowInfo[nId]
	end
	local tInfo = _AssertInfoExist(nUserId)
	for nUserIdOfAndroid, nPoolForm in pairs(tAndroidToPoolForm) do
		local nPoolFormA = nPoolForm / nWinCnt
		local tInfoA = _AssertInfoExist(nUserIdOfAndroid)
		tInfo.nWinFromAndroid = tInfo.nWinFromAndroid + nPoolFormA
		if isAndroid then
			tInfoA.nWinFromAndroid = tInfoA.nWinFromAndroid - nPoolFormA
		else
			tInfoA.nWinFromReal = tInfoA.nWinFromReal - nPoolFormA
		end
	end
end

function Table:_WinFromReal(nUserId, isAndroid, tRealUserToPoolForm, nWinCnt)
	local function _AssertInfoExist(nId)
		self.tUserIdToGoldFlowInfo[nId] = self.tUserIdToGoldFlowInfo[nId] or { nWinFromAndroid = 0, nWinFromReal = 0 }
		return self.tUserIdToGoldFlowInfo[nId]
	end
	local tInfo = _AssertInfoExist(nUserId)
	for nUserIdOfAndroid, nPoolForm in pairs(tRealUserToPoolForm) do
		local nPoolFormA = nPoolForm / nWinCnt
		local tInfoA = _AssertInfoExist(nUserIdOfAndroid)
		tInfo.nWinFromReal = tInfo.nWinFromReal + nPoolFormA
		if isAndroid then
			tInfoA.nWinFromAndroid = tInfoA.nWinFromAndroid - nPoolFormA
		else
			tInfoA.nWinFromReal = tInfoA.nWinFromReal - nPoolFormA
		end
	end
end

function Table:_UsersWinFromPools(nTheOnlyNotFoldPos)
	local tPosToArrWin, nPoolData = {}, {}
	local function _AssertValueExist(nPos)
		if tPosToArrWin[nPos] == nil then
			tPosToArrWin[nPos] = {}
		end
		return tPosToArrWin[nPos]
	end
	if nTheOnlyNotFoldPos then --只剩一个玩家没弃牌时，该玩家获得全部底池筹码
		local arr = _AssertValueExist(nTheOnlyNotFoldPos)
		local tUser = self:_GetUser(nTheOnlyNotFoldPos)
		for nPoolId, item in ipairs(self.arrPoolInfo) do
			table.insert(arr, { nPotIdFrom = nPoolId, nGold = item.nPool })
			table.insert(nPoolData, { nPotIdFrom = nPoolId, nPos = nTheOnlyNotFoldPos })
			if tUser then
				self:_WinFromAndroid(tUser.nUserId, tUser.isAndroid, item.tAndroidToPoolForm, 1) --记录金币流向(机器人和真人之间)
				self:_WinFromReal(tUser.nUserId, tUser.isAndroid, item.tRealUserToPoolForm, 1) --记录金币流向(机器人和真人之间)
			end
		end
		return tPosToArrWin, nPoolData
	end
	for nPoolId, item in ipairs(self.arrPoolInfo) do
		local arrUsersWin = self:_CalPoolItemWin(item)          --{{nPos=?,nGoldWin=?}}
		if #arrUsersWin == 0 then
			self:Print("Waring:the Pool_%d is no user can Rec", nPoolId) --底池没人领取，胜利玩家可能在跳结算是站起了
		end
		local poolWin
		for _, v in ipairs(arrUsersWin) do
			local arr = _AssertValueExist(v.nPos)
			table.insert(arr, { nPotIdFrom = nPoolId, nGold = v.nGoldWin })
			if not poolWin then
				poolWin = { nPotIdFrom = nPoolId, nPos = v.nPos }
			end
		end
		if poolWin then
			table.insert(nPoolData, poolWin)
		end
	end
	return tPosToArrWin, nPoolData
end

function Table:_IsWin(arrGoldGet)
	if arrGoldGet == nil or #arrGoldGet == 0 then
		return false
	end
	if #self.arrCommunityCards ~= 5 then
		return false
	end
	for _, v in ipairs(arrGoldGet) do
		local tPoolInfo = self.arrPoolInfo[v.nPotIdFrom]
		if #tPoolInfo.arrPosForm >= 2 then
			return true
		end
	end
	return false
end

--发公共牌，且更新各玩家牌型信息
function Table:_DealCommunityCards(nDealCnt)
	local oldLen = #self.arrCommunityCards
	local arrCardsNewAdd = self.tPile:GetCards(nDealCnt, self.arrPreSetCommCardEffect, true)
	for _, v in ipairs(arrCardsNewAdd) do
		table.insert(self.arrCommunityCards, v)
	end
	local data = nil
	if #arrCardsNewAdd == 3 then --公共牌3张发牌阶段已经记录了不处理
		data = {}
		data[1] = _CopyArr(arrCardsNewAdd)
	elseif #arrCardsNewAdd == 1 then
		data = {}
		if oldLen == 3 then
			data[4] = arrCardsNewAdd[1] --翻牌后发第四张牌
		elseif oldLen == 4 then
			data[5] = arrCardsNewAdd[1] --转牌后发第五
		end
	end
	if data then
		self.hashHelper:ChangeCurrent(data, true)
	end

	local arrCardType = {}
	local nMaxPos = 0
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		--if tUser.nStatus~=UserStatus.nFold then
		tUser.tCardType = tAlg.DeZhouCardType(tUser.arrHoleCards, self.arrCommunityCards)
		--end
		arrCardType[nPos] = self:_GetCardType(tUser.tCardType)
		nMaxPos = math.max(nPos, nMaxPos)
	end
	for i = 1, nMaxPos do
		arrCardType[i] = arrCardType[i] or 0
	end
	self:Print("arrCardsNewAdd:%s", Define.CardsToStr(arrCardsNewAdd))
	return arrCardsNewAdd, arrCardType
end

--收归玩家下注到底池
function Table:_CollectBetToPoolsN(arrPos)
	local arrUsers = {}
	for _, nPos in ipairs(arrPos) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		table.insert(arrUsers, tUser)
	end
	--返回所有大于0的下注中,最小的那个下注值
	local function _MinBet()
		local nMinBet = 0
		for _, tUser in ipairs(arrUsers) do
			if GreaterThan(tUser.nBet, 0) and (nMinBet == 0 or LessThan(tUser.nBet, nMinBet)) then
				nMinBet = tUser.nBet
			end
		end
		return nMinBet
	end
	--执行一轮收归操作
	local function _DoOneCollect(nMinBet)
		local nPool = 0
		local arrPosForm = {}
		local tForReal = {} --记录每个真人id投入该池的筹码
		local tForAndroid = {} --记录每个机器人id投入该池的筹码
		for _, tUser in ipairs(arrUsers) do
			if GreaterOrEqual(tUser.nBet, nMinBet) then
				if tUser.isAndroid then
					tForAndroid[tUser.nUserId] = (tForAndroid[tUser.nUserId] or 0) + nMinBet
				else
					tForReal[tUser.nUserId] = (tForReal[tUser.nUserId] or 0) + nMinBet
				end
				tUser.nBet = tUser.nBet - nMinBet
				nPool      = nPool + nMinBet
				table.insert(arrPosForm, tUser.nSitId)
			end
		end
		assert(GreaterThan(nPool, 0))
		return { nPool = nPool, arrPosForm = arrPosForm, tRealUserToPoolForm = tForReal, tAndroidToPoolForm = tForAndroid }
	end
	--执行多轮收归操作,最终收归所有下注
	for i = 1, #arrUsers do
		local nMinBet = _MinBet()
		if LessOrEqual(nMinBet, 0) then
			break
		end
		local tPoolItem = _DoOneCollect(nMinBet)
		self:_AddPool(tPoolItem)
	end
	--收归结束后,断言所有下注都被收归置0
	for _, tUser in ipairs(arrUsers) do
		assert(Equal(tUser.nBet, 0))
	end
	--打印底池信息
	self:_PrintPools()
end

-- 获取玩家对应分池下注
function Table:_GetPoolUserBet(nPool, userId)
	return nPool.tRealUserToPoolForm[userId] or 0
end

--有存活且不同才追加,其它情况合并
function Table:_AddPool(tPoolItem)
	if #self.arrPoolInfo == 0 then
		tPoolItem.nPoolId = 1
		table.insert(self.arrPoolInfo, tPoolItem)
		return
	end
	tPoolItem.nPoolId = #self.arrPoolInfo + 1
	local arrSurvivePosA = {}
	local arrSurvivePosB = {}
	local tEndPoolItem = self.arrPoolInfo[#self.arrPoolInfo]
	for _, nPos in ipairs(tEndPoolItem.arrPosForm) do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.nStatus ~= UserStatus.nFold and tUser.nStatus ~= UserStatus.nLooker then
			table.insert(arrSurvivePosA, nPos)
		end
	end
	for _, nPos in ipairs(tPoolItem.arrPosForm) do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.nStatus ~= UserStatus.nFold and tUser.nStatus ~= UserStatus.nLooker then
			table.insert(arrSurvivePosB, nPos)
		end
	end
	--有存活且不同才追加,其它情况合并
	if #arrSurvivePosA > 0 and #arrSurvivePosB > 0 and (not _isNumArrEqual(arrSurvivePosA, arrSurvivePosB)) then
		table.insert(self.arrPoolInfo, tPoolItem)
		return
	end
	tEndPoolItem.nPool = tEndPoolItem.nPool + tPoolItem.nPool
	tEndPoolItem.arrPosForm = _PoolPosMerge(tEndPoolItem.arrPosForm, tPoolItem.arrPosForm)
	tEndPoolItem.tRealUserToPoolForm = _PoolFormMerge(tEndPoolItem.tRealUserToPoolForm, tPoolItem.tRealUserToPoolForm)
	tEndPoolItem.tAndroidToPoolForm = _PoolFormMerge(tEndPoolItem.tAndroidToPoolForm, tPoolItem.tAndroidToPoolForm)
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
function Table:_QuickOptionToBetValue(nOption, nBalance)
	if nOption == UserOp.nHalfPool then
		return publicApi.Floor_1((1 / 2) * self.nPotSum)
	end
	if nOption == UserOp.nTwoThirdsPool then
		return publicApi.Floor_1((2 / 3) * self.nPotSum)
	end
	if nOption == UserOp.nOnePool then
		return self.nPotSum
	end
	if nOption == UserOp.nTwoBlind then
		return 2 * self.nBigBlind
	end
	if nOption == UserOp.nThreeBlind then
		return 3 * self.nBigBlind
	end
	if nOption == UserOp.nFourBlind then
		return 4 * self.nBigBlind
	end
	if nOption == UserOp.nAllIn then
		return nBalance
	end
	return 0
end

function Table:_GetUserQuickRaise(tUser, nMin, nMax)
	local arrOption = {}
	local nCompare = self.nBigBlind
	if self.nIsZhuaTouBet then
		nCompare = self.nZhuaTou
	end
	if self.nIsRoundBet then
		if #self.arrCommunityCards == 0 then -- 翻牌前
			if LessOrEqual(self.nTheHighestBet, nCompare) then
				arrOption = { UserOp.nTwoBlind, UserOp.nThreeBlind, UserOp.nFourBlind }
			end
		else
			arrOption = { UserOp.nHalfPool, UserOp.nTwoThirdsPool, UserOp.nOnePool }
		end
	else
		if #self.arrCommunityCards == 0 then -- 翻牌前
		else
			arrOption = { UserOp.nHalfPool, UserOp.nTwoThirdsPool, UserOp.nOnePool }
		end
	end
	-- 把候选选项映射为实际筹码值并根据 nMin/nMax/余额过滤
	local arrOptionNew = {}
	local seen = {}
	for _, nOption in ipairs(arrOption) do
		local nOptionBetValue = self:_QuickOptionToBetValue(nOption)
		-- 选项必须满足：筹码值 >= nMin && 筹码值 <= nMax && 玩家余额 >= 筹码值
		if GreaterOrEqual(nOptionBetValue, nMin) and LessOrEqual(nOptionBetValue, nMax) and GreaterOrEqual(tUser.nBalance, nOptionBetValue) then
			if not seen[nOption] then
				table.insert(arrOptionNew, nOption)
				seen[nOption] = true
			end
		end
	end
	if #arrOptionNew < 3 then
		table.insert(arrOptionNew, UserOp.nAllIn)
	end
	return arrOptionNew
end

--[[
当前最高下注额：当前回合中，桌面上任意玩家已经投入的最高筹码金额。
玩家本回合已投入金额：当前玩家在这一轮中已经投入的筹码。
需跟注金额：玩家要继续留在本轮中需要补齐的差额 = 当前最高下注额 − 玩家本回合已投入金额。
上一次有效加注差额：最近一次加注行为中，“加了多少”这个差值，用于约束后续最小再加注.
无人下注时的最小下注规则
	翻牌前：若轮到玩家操作，且前面没有出现下注（仅有大小盲注），则第一次主动加注的最小总额为 大盲注的两倍。
	翻牌后：若轮到玩家操作，且无人下注，则该玩家第一次主动下注的最小金额为 一个大盲注。
面对已有下注时的最小加注规则
	最小加注额 = 需跟注金额 + 上一次有效加注差额，即玩家要加注，除了补齐跟注金额，还必须至少再额外加与上一次加注幅度相同的金额，才算合法加注
不完整加注与全下规则
	全下金额 大于或等于最小加注额，视为有效加注，后续玩家可继续再加注。
	全下金额 介于跟注金额和最小加注额之间，视为不完整加注，后续已行动过的玩家只允许跟注或弃牌，不允许再加注。
	全下金额 不足以跟注，属于筹码不足的被动全下，只算跟注行为，不构成加注。
界面（滑杆与输入框）约束要求
	滑杆最小值不得低于需跟注金额，如玩家选择加注，滑杆最低可选金额必须为合法的
	最小加注额，无论何种情况，玩家都允许点“全下”按钮，出现不完整加注时，界面不得再提供新的加注选项。
]]

function Table:_GetProtoOperationRights(nPos)
	local tUser = self:_GetUser(nPos)
	assert(tUser ~= nil)
	--计算需跟注金额		6                    6
	local nDiffBet = self.nTheHighestBet - tUser.nBet
	nDiffBet = nDiffBet > 0 and nDiffBet or 0
	-- assert(GreaterOrEqual(nDiffBet,0))
	local nCompare = self.nBigBlind
	if self.nIsZhuaTouBet then
		nCompare = self.nZhuaTou
	end
	-- 4					   2                        4
	local nLastRaise = math.max(self.nLatelyIncreasesBet, self.nBigBlind)
	local nMin = nLastRaise + self.nTheHighestBet - tUser.nBet
	if #self.arrCommunityCards == 0 then -- 翻牌前
		if LessOrEqual(self.nTheHighestBet, nCompare) then
			nMin = self.nBigBlind * 2
		end
	else
		if not self.nIsRoundBet then -- 无人下注 一个大盲
			nMin = self.nBigBlind
		end
	end

	local nOpA, nOpB, nOpC = nil, nil, nil
	--第一按钮,只有一种状态 '弃牌'
	nOpA = UserOp.nFold
	--第二按钮,有三种可能状态 'AllIn', '看牌', '跟注xx'
	if Equal(nDiffBet, 0) then
		nOpB = UserOp.nPass
	elseif LessThan(nDiffBet, tUser.nBalance) then
		nOpB = nDiffBet
		if self.isAOF then
			nOpB = UserOp.nAllIn
		end
	else
		nOpB = UserOp.nAllIn
	end
	local nDelayCost = self.arrDelayCost[tUser.nDelayCount + 1] or 0 --延时操作花费
	if tUser.nDelayCount + 1 > 5 then
		nDelayCost = -1
	end
	local nInsureDelayCost = self:_GetInsureDelayCost(tUser.nInsureDelayCount)
	if tUser.nInsureDelayCount + 1 > 5 then
		nInsureDelayCost = -1
	end
	--第三按钮,有三种可能状态 'AllIn', '加注', '加注(置灰)'  (缺:特殊情况时禁止加注的情况)
	if nOpB == UserOp.nAllIn then
		nOpC = UserOp.nRaiseBan
		return { nOpA = nOpA, nOpB = nOpB, nOpC = nOpC, nDelayCost = nDelayCost, nInsureDelayCost = nInsureDelayCost }
	end
	-- local nMin =math.max(self.nLatelyIncreasesBet,self.nBigBlind) +self.nTheHighestBet -tUser.nBet
	if LessOrEqual(tUser.nBalance, nMin) then
		nOpC = UserOp.nAllIn
		return {
			nOpA = nOpA,
			nOpB = nOpB,
			nOpC = nOpC,
			tRaiseChoice = { nMin = tUser.nBalance, nMax = tUser.nBalance, arrQuickRaise = {} },
			nDelayCost =
				nDelayCost,
			nInsureDelayCost = nInsureDelayCost
		}
	end
	if tUser.nBalance > nDiffBet and tUser.nBalance < nMin then
		-- 不完整加注（全下金额小于最小加注额）
		nOpC = UserOp.nRaiseBan
		return { nOpA = nOpA, nOpB = nOpB, nOpC = nOpC, nDelayCost = nDelayCost, nInsureDelayCost = nInsureDelayCost }
	end

	nOpC = UserOp.nRaise
	local tRaiseChoice = {}
	tRaiseChoice.nMin = nMin
	tRaiseChoice.nMax = tUser.nBalance
	tRaiseChoice.arrQuickRaise = self:_GetUserQuickRaise(tUser, tRaiseChoice.nMin, tRaiseChoice.nMax) --(快速操作的选项)
	return {
		nOpA = nOpA,
		nOpB = nOpB,
		nOpC = nOpC,
		tRaiseChoice = tRaiseChoice,
		nDelayCost = nDelayCost,
		nInsureDelayCost =
			nInsureDelayCost
	}
end

function Table:_ToOpForTimeOutUser(nSeconds, nPos)
	self.Timer:KillAllTimer()
	self.Timer:DelayCall(nSeconds * 1000, Table.OpForTimeOutUser, self, nPos)
end

function Table:OpForTimeOutUser(nPos)
	self:Print("OpForTimeOutUser %d", nPos)
	local tUser = self:_GetUser(nPos)
	assert(tUser ~= nil)
	assert(tUser.tOperation ~= nil)
	assert(tUser.tOperation.nOpA == UserOp.nFold)

	tUser.nTimeOutCnt = tUser.nTimeOutCnt + 1
	if tUser.isAuto then
	else
		tUser.isAuto = (tUser.nTimeOutCnt >= Define.TimeOutMax)
	end
	--if tUser.tOperation.nOpB >0 then
	--	self:DoOpForUser(nPos,UserOp.nCall,tUser.tOperation.nOpB)
	if tUser.tOperation.nOpB == UserOp.nPass then
		self:DoOpForUser(nPos, UserOp.nPass)
	else
		self:DoOpForUser(nPos, UserOp.nFold)
	end

	--通知机器人有人超时了，用以发表情
	self:_BroadCastToAndroidPlayer("UserOpTimeOut", { nPos = nPos, nTimeOutCnt = tUser.nTimeOutCnt })
end

function Table:_BroadCastToAndroidPlayer(strMsgName, tMsgData)
	for _, nPos in ipairs(self.arrPosPartIn) do
		local tUser = self:_GetUser(nPos)
		if tUser and tUser.isAndroid then
			self:SendToUser(nPos, strMsgName, tMsgData)
		end
	end
end

function Table:_GetProtoArrPot()
	local arrPot = {}
	for _, v in ipairs(self.arrPoolInfo) do
		table.insert(arrPot, v.nPool)
	end
	return arrPot
end

function Table:_GetProtoArrPotUsers()
	local arrPotUsers = {}
	for _, v in ipairs(self.arrPoolInfo) do
		for userId, bet in pairs(v.tRealUserToPoolForm) do
			table.insert(arrPotUsers, { nUserId = userId, nBet = bet, nPoolId = v.nPoolId })
		end
	end
	return arrPotUsers
end

function Table:_PrintPools()
	self:Print("arrPoolInfo:%s", tBase.tostring(self.arrPoolInfo))
end

-- 1 2 3 4 分别对应公共牌数量 0 3 4 5
function Table:_GetAiStage()
	local n = #self.arrCommunityCards
	if n == 0 then
		return 1
	elseif n == 3 then
		return 2
	elseif n == 4 then
		return 3
	elseif n == 5 then
		return 4
	end
	return -1 --ERROR
end

--返回的数据不能改动(因为有些table不是copy的)
function Table:GetAiScence(nSelfUserId, tOperation)
	local tS = {}
	tS.sTableId = self.sTableId or "-1"
	tS.sPaiJuId = self.sPaiJuId or "-1"
	tS.nGameId = self.nGameId
	tS.nGroupId = self.nGroupId
	tS.nRoomId = self.nRoomId

	tS.nLevel = RedisCahche._GetTexasAndroidLevelCfg(self.nGroupId, self.nGameId, self.nRoomId)
	tS.bControl = false
	if self.isControl and (self.isControl == 2 or self.isControl == 3) then
		tS.bControl = true
	end
	tS.nStage = self:_GetAiStage()                                         --1 2 3 4 分别对应公共牌数量 0 3 4 5
	tS.nBankerPos = self.nBankerPos                                        --庄家位置
	tS.nCapacity = self.nCapacity                                          --能供玩游戏的座位数

	tS.nSmallBlind = self.nSmallBlind                                      --小盲注数额
	tS.nBigBlind = self.nBigBlind                                          --大盲注数额(通常为小盲的两倍)
	tS.arrUser, tS.nSelfDex, tS.nLeaderDex = self:_UpdateAiUsers(nSelfUserId) --参与本局的玩家,第一个为庄(按钮位置),按顺时针排序(行动顺序);
	tS.arrCommunityCard = self.arrPreSetCommCardCp                         --当前公共牌(最多5个牌)
	tS.arrPool = self:_GetProtoArrPot()                                    --当前桌面底池

	for _, tU in ipairs(tS.arrUser) do
		tU.arrHistory = self:_GetUserOpHistory(tU.nUserId)
	end

	if tOperation.nOpB == UserOp.nAllIn or tOperation.nOpC == UserOp.nAllIn then
		tS.nAllIn = 100 --能否AllIn标识(>0:AllIn的筹码数目, -1:不能AllIn)
	else
		tS.nAllIn = -1
	end

	if tOperation.nOpB > 0 then
		tS.nFollow = tOperation.nOpB --能否跟注标识 (>0:跟注的筹码数目, -1:不能跟注)
	else
		tS.nFollow = -1
	end

	if tOperation.nOpC == UserOp.nRaise then
		local tRaiseChoice = tOperation.tRaiseChoice or {}
		local nRaiseMin = tRaiseChoice.nMin or 0
		local nRaiseMax = tRaiseChoice.nMax or 0
		tS.arrRaiseRange = { nRaiseMin, nRaiseMax } --能否加注标识 (数组长度2时:表示加注范围[Low,Top], 其它长度或nil:不能加注)
	end

	tS.isCanPass = (tOperation.nOpB == UserOp.nPass) --能否过牌标识 (true:能 false:否)

	--确定大小盲玩家位置
	if #tS.arrUser == 2 then
		tS.nSmallBlindDex = 0                                         --小盲玩家索引(索引从0开始)
		tS.nBigBlindDex = 1                                           --大盲玩家索引(索引从0开始)
	else
		tS.nSmallBlindDex = 1                                         --小盲玩家索引(索引从0开始)
		tS.nBigBlindDex = 2                                           --大盲玩家索引(索引从0开始)
	end
	tS.nBetDiff = self.nTheHighestBet - tS.arrUser[tS.nSelfDex + 1].nBet --当轮桌面最高下注和自己下注的相差值 (最高注-自己下注)

	tS.nFirstBet = self.nFirstBet                                     --本桌大小盲累计下注总额
	tS.nTheHighestBet = self.nTheHighestBet                           --当轮桌面最高下注
	return tS, self.sAiUrl
end

function Table:_AddOpCount(nUserId, Op)
	local nStage = 0
	if #self.arrCommunityCards == 0 then
		nStage = 0
	elseif #self.arrCommunityCards == 3 then
		nStage = 1
	elseif #self.arrCommunityCards == 4 then
		nStage = 2
	elseif #self.arrCommunityCards == 5 then
		nStage = 3
	end
	local Item = {}
	Item.nStage = nStage
	Item.nFollowCnt = 0
	Item.nPassCnt = 0
	Item.nRaiseCnt = 0
	Item.nAllInCnt = 0
	Item.nGiveUpCnt = 0
	Item.nFollowAllIn = 0 --这个没统计到 先这样
	local sKey = string.format("%d_%d", nUserId, nStage)
	local tInfo = self.tOpHistory[sKey] or Item
	if Op == UserOp.nFold then
		tInfo.nGiveUpCnt = tInfo.nGiveUpCnt + 1
	elseif Op == UserOp.nAllIn then
		tInfo.nAllInCnt = tInfo.nAllInCnt + 1
	elseif Op == UserOp.nPass then
		tInfo.nPassCnt = tInfo.nPassCnt + 1
	elseif Op == UserOp.nRaise then
		tInfo.nRaiseCnt = tInfo.nRaiseCnt + 1
	elseif Op == UserOp.nCall then
		tInfo.nFollowCnt = tInfo.nFollowCnt + 1
	end
	self.tOpHistory[sKey] = tInfo
end

function Table:_GetUserOpHistory(nUserId)
	local arr = {}
	for nStage = 0, 3 do
		local sKey = string.format("%d_%d", nUserId, nStage)
		local tInfo = self.tOpHistory[sKey]
		if tInfo then
			table.insert(arr, tInfo)
		else
			break
		end
	end
	return arr
end

function Table:_GetAiUser(nPos)
	local tUser = self.arrUsers[nPos]
	if not tUser then
		return
	end
	local item = {}
	item.nState = tUser.nStatus        --玩家当轮最近的操作 0:还未操作 1:正在思考操作中(自己) 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌
	item.nBet = tUser.nBet             --玩家当轮的下注数目
	item.nBetSum = tUser.nBetSum       --玩家开局至今的总下注数目
	item.nRemain = tUser.nBalance      --当前剩余筹码
	item.arrHoleCard = tUser.arrHoleCards --底牌(2个)
	item.isAndroid = tUser.isAndroid   --是否是机器人
	item.nType = tUser.nAiType         --0一般 1进取 2保守
	item.nUserId = tUser.nUserId
	item.arrHistory = {}               --玩家在各阶段的操作次数
	item.isEnableAdd = true            --当前轮是否能加注
	return item
end

function Table:_UpdateAiUsers(nSelfUserId)
	local nSelfDex = -1
	local nLeaderDex = -1
	for nDex, item in ipairs(self.arrAiUser) do
		local _, tUser = self:_GetSitIdByUserId(item.nUserId)
		if tUser then
			item.nPos = nDex             --玩家座位号
			item.nState = tUser.nStatus  --玩家当轮最近的操作 0:还未操作 1:正在思考操作中(自己) 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌
			item.nBet = tUser.nBet       --玩家当轮的下注数目
			item.nBetSum = tUser.nBetSum --玩家开局至今的总下注数目
			item.nRemain = tUser.nBalance --当前剩余筹码
			item.arrHoleCard = tUser.arrHoleCards --底牌(2个)
		else
			item.nState = UserOp.nFold
		end
		if item.nUserId == nSelfUserId then
			nSelfDex = nDex - 1 --返回从0开始的索引，所以-1
		end
		if item.nUserId == self.nUserIdLeader then
			nLeaderDex = nDex - 1 --返回从0开始的索引，所以-1
		end
		item.isEnableAdd = (item.nState ~= UserOp.nFold and item.nState ~= UserOp.nAllIn and item.nState ~= UserOp.nRaise)
	end
	return self.arrAiUser, nSelfDex, nLeaderDex
end

function Table:GetScence()
	local tScenc               = {}
	tScenc.nGroupId            = self.nGroupId         --分组id
	tScenc.nRoomId             = self:MatchRoomId() or -1 --房间id
	tScenc.nTableType          = self.nTableType       --桌子类型
	tScenc.nLiveUserID         = self.nLiveUserID      --主播ID
	tScenc.sLiveID             = self.sLiveID          --主播ID(app)
	tScenc.nSmallBlind         = self.nSmallBlind      --小盲注数额
	tScenc.nBigBlind           = self.nBigBlind        --大盲注数额(通常等于:小盲注x2)
	tScenc.nZhuaTou            = self.nZhuaTou         --抓头数额(通常等于:小盲注x4)
	tScenc.nPreAnte            = self.nPreAnte         --前注
	tScenc.nCapacity           = self.nCapacity        --能供玩游戏的座位数
	tScenc.nOperateTime        = self.nOperateTime     --操作最大时间,单位:秒 (通常为10)
	tScenc.nPotSum             = self.nPotSum          --底池总额(已押筹码总额)
	tScenc.arrPool             = self:_GetProtoArrPot() --底池
	tScenc.arrCommunityCards   = self.arrCommunityCards --公共牌
	tScenc.nStage              = self.nStage           --当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	tScenc.isConfigNotSet      = self.isConfigNotSet   --本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	tScenc.tDeZhouConfigOption = self.tDeZhouConfigOption --桌子可选配置(主播有)
	tScenc.isPause             = self.isPause          --是否设置了暂停 true:是  false:否		 	
	tScenc.sPaiJuId            = self.sPaiJuId         --牌局id
	tScenc.nJuShu              = self.nJuShu           --当前局数
	tScenc.nBankerPos          = self.nBankerPos       --庄家位置
	tScenc.nTimeStart          = self.nTimeStart       -->0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	tScenc.nBuyMin             = self.nBuyMin          --最小买入
	tScenc.nBuyMax             = self.nBuyMax          --最大买入
	tScenc.arrPartInUser       = {}                    --玩家位用户
	tScenc.sTableName          = self.sTableName       --桌子名称
	tScenc.nClubId             = self.nClubId
	tScenc.nItemId             = self.nItemId          --使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	tScenc.nGoldType           = self.nGoldType        -- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)
	tScenc.isTableStart        = self.isTableStart     --牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	tScenc.isAutoNext          = self.isAutoNext       --下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始(前端判断>=2人时才给房主显示该按钮)				
	tScenc.tTableConfig        = self:_GetTableConfig()
	tScenc.nRoomType           = self.nRoomType        --10:大厅桌子 11:俱乐部桌子 12:比赛桌
	tScenc.arrChat             = self.arrChat
	tScenc.nGameId             = self.nGameId
	tScenc.nClubIdOfCorrect    = self.nClubIdOfCorrect --大厅的ClubId统一用0表示
	tScenc.isTabkeOut          = self.isTabkeOut    --是否带出筹码
	tScenc.nTabkeOutOdd        = self.nTabkeOutOdd  --撤码阈值的倍数N
	tScenc.nElapsedStatus      = self:_ElapsedStatus() --桌子当前计时状态 0正常 1暂停
	tScenc.nKeepTime           = self.nKeepTime
	tScenc.potUsers            = self:_GetProtoArrPotUsers()

	for nPos = 1, self.nCapacity do
		local item = self:_GetProtoUserV2(nPos)
		if item then
			table.insert(tScenc.arrPartInUser, item)
		end
	end
	return tScenc
end

function Table:_GetProtoUserV2(nPos)
	local tUser = self.arrUsers[nPos]
	if tUser == nil then
		return
	end
	local isBanker = (self.nStage ~= TableState.nInit and self.nBankerPos == nPos and tUser.nStatus ~= UserStatus.nLooker)
	local nCardType = self:_GetCardType(tUser.tCardType)
	local item = {}
	item.nUserId = tUser.nUserId           --玩家ID
	item.nSitId = nPos                     --座位号
	item.sFaceId = tUser.sFaceId           --头像url
	item.sName = tUser.sName               --昵称
	item.nSex = tUser.nSex                 --性别 0:男 1:女
	item.nBalance = tUser.nBalance         --余额
	item.isBanker = isBanker               --是否为庄; true:是 ,false:否
	item.arrHoleCards = tUser.arrHoleCards --底牌(值为0的牌，显示牌背,表示还没亮牌)
	item.nCardType = nCardType             --牌型(见本文件头部"牌型定义")
	item.nBet = tUser.nBet                 --玩家当轮当前下注数目(0时不要显示)
	item.nStatus = tUser.nStatus           --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观
	item.nGetRightTime = tUser.nGetRightTime --最近获得操作权时的时间戳
	item.isAuto = tUser.isAuto             --是否托管中
	item.sShopAccount = tUser.sShopAccount --第三方用户ID
	item.isAndroid = tUser.isAndroid or false --是否机器人
	item.tOperation = tUser.tOperation     --当前自己可操作信息(自己为思考状态时有)
	item.tPreOpOption = tUser.tPreOpOption --自己当前可预操作选项
	item.nOpLong = tUser.nOpLong
	return item
end

function Table:_FindAPosForPlay()
	for nPos = 1, self.nCapacity do
		if self.arrUsers[nPos] == nil then
			return nPos
		end
	end
end

function Table:_IsPlayerPos(nPos)
	return (nPos > 0 and nPos <= self.nCapacity)
end

function Table:_GetSitIdByUserId(nUserId)
	if not nUserId then
		return
	end
	local nSitId = self.tUserIdToPos[nUserId]
	if nSitId then
		assert(self.arrUsers[nSitId] ~= nil)
		assert(self.arrUsers[nSitId].nUserId == nUserId)
		return nSitId, self.arrUsers[nSitId]
	end
end

--广播到所有从服
function Table:_BroadCastToSlaves(sCmd, tData)
	local DZCRsp = {}
	DZCRsp.sTableId = self.sTableId
	DZCRsp.sCmd = sCmd
	DZCRsp.sJsonData = cjson.encode(tData) --主从服通信内容主体用json格式
	DZCRsp.nEcho = -1
	tSlaveManager.Broadcast("DZCRsp", DZCRsp)
end

--发送到指定的一个从服
function Table:_SendToSlave(sReturnKey, sCmd, tData)
	if not sReturnKey then return end
	local DZCRsp = {}
	DZCRsp.sTableId = self.sTableId
	DZCRsp.sCmd = sCmd
	DZCRsp.sJsonData = cjson.encode(tData) --主从服通信内容主体用json格式
	DZCRsp.nEcho = -1
	tSlaveManager.Send(sReturnKey, "DZCRsp", DZCRsp)

	--self:Print("_SendToSlave %s %s",sCmd,DZCRsp.sJsonData) --for test
end

--广播有玩家取消托管通知
function Table:_BroadCastCancelAutoNotify(nSitId)
	--广播给从服
	self:_BroadCastToSlaves("CancelAutoNotify", { nPos = nSitId })
end

function Table:_GetPartInUserStatus()
	local arrUser = {}
	for _, pos in ipairs(self.arrPosPartIn) do
		local tUser = self.arrUsers[pos]
		assert(tUser ~= nil)
		local item = {}
		item.nSitId = pos
		item.tPreOpOption = tUser.tPreOpOption
		local tCardType = tUser.tCardType or {}
		item.nCardType = tCardType.nCardType or 0
		item.nStatus = tUser.nStatus
		item.arrCombinedCards = (tUser.nStatus ~= UserStatus.nFold) and tCardType.arrFiveBack or {}
		item.nInsureStatus = tUser.nInsureStatus
		table.insert(arrUser, item)
	end
	return arrUser
end

--广播发公共牌
function Table:_BroadCastDeZhouDealNotify(arrCardsNewAdd, isShowCard)
	--广播给从服
	local DealNotify = {}
	DealNotify.nPotSum = self.nPotSum       --底池总额(已押筹码总额)
	DealNotify.arrPot = self:_GetProtoArrPot() --收归的各底池数额(池数量:>0),数组索引代表池ID,索引从1开始
	DealNotify.arrCardsNewAdd = arrCardsNewAdd --新增的公共牌
	DealNotify.isShowCard = isShowCard
	DealNotify.arrUser = self:_GetPartInUserStatus()
	DealNotify.potUsers = self:_GetProtoArrPotUsers()
	self:_BroadCastToSlaves("DealNotify", DealNotify)
	--主要是广播给机器人
	for nPos, tUser in pairs(self.arrUsers) do
		self:SendToUser(nPos, "DeZhouDealNotify", { arrCards = arrCardsNewAdd })
	end
end

--广播桌子关闭消息
function Table:_BroadCastTableCloseNotify(nReason)
	--广播给从服
	self:_BroadCastToSlaves("TableCloseNotify", { nReason = nReason })
end

--广播有玩家坐下
function Table:_BroadCastUserSitDownNotify(tUser)
	local item = {}
	item.nUserId = tUser.nUserId                                                                    --玩家ID
	item.nSitId = tUser.nSitId                                                                      --座位号
	item.sFaceId = tUser.sFaceId                                                                    --头像url
	item.sName = tUser.sName                                                                        --昵称
	item.nSex = tUser.nSex                                                                          --性别 0:男 1:女
	item.nBalance = tUser.nBalance                                                                  --余额
	item.sShopAccount = tUser.sShopAccount                                                          --第三方用户ID
	item.isAndroid = tUser.isAndroid or false                                                       --是否机器人
	item.nStatus = tUser
	.nStatus                                                                                        --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观
	item.nUnLockGold = self:Get_User_UnLockGold(tUser)
	item.isPop = self:_IsShouldPop(tUser)                                                           --是否弹窗提示玩家补充筹码
	item.nLoseAmount = tPenaltyManager:GetProfit(tUser.nUserId, self.sTableId, tUser.nLockGoldInTable) --总输赢
	item.nPlayCnt = tPenaltyManager:getPlayCnt(tUser.nUserId, self.sTableId)                        --总局数
	self:Print("广播有玩家坐下:%s", cjson.encode(item))
	self:_BroadCastToSlaves("UserSitDownNotify", { tUser = item })
end

--广播有玩家离开座位
function Table:_BroadCastUserStanpUpNotify(tUser)
	--广播给从服
	local nUnLockGold = self:Get_User_UnLockGold(tUser)
	self:_BroadCastToSlaves("UserStanpUpNotify", { nPos = tUser.nSitId, nUnLockGold = nUnLockGold })
end

--广播有玩家亮牌通知
function Table:_BroadCastShowCardNotify(nPos)
	--广播给从服
	self:_BroadCastToSlaves("ShowCardNotify", { nPos = nPos })
end

--广播表情聊天
function Table:_BroadCastDeZhouChatNotify(nSpeaker, nChatId, nTarget)
	--广播给从服
	local DeZhouChatNotify = {}
	DeZhouChatNotify.nSpeaker = nSpeaker
	DeZhouChatNotify.nChatId = nChatId
	DeZhouChatNotify.nTarget = nTarget
	self:_BroadCastToSlaves("DeZhouChatNotify", DeZhouChatNotify)
end

--广播有玩家获得操作权
function Table:_BroadCastGetRightNotify(tUser, nPosToGainRights, isDoOpenHodeCard, arrUserIdNeedOpenHodeCard)
	--广播给从服
	local GetRightNotify = {}
	GetRightNotify.nPos = nPosToGainRights
	GetRightNotify.tOperation = tUser.tOperation
	GetRightNotify.nGetRightTime = tUser.nGetRightTime
	GetRightNotify.nStatus = tUser.nStatus
	GetRightNotify.tPreOpOption = nil
	GetRightNotify.isDoOpenHodeCard = isDoOpenHodeCard
	GetRightNotify.nOpLong = tUser.nOpLong
	GetRightNotify.arrUserIdNeedOpenHodeCard = arrUserIdNeedOpenHodeCard
	self:_BroadCastToSlaves("GetRightNotify", GetRightNotify)
	--广播给机器人
	local DeZhouOperationNotify = {}
	DeZhouOperationNotify.nPos = nPosToGainRights
	DeZhouOperationNotify.tOperation = tUser.tOperation
	for nPos, v in pairs(self.arrUsers) do
		self:SendToUser(nPos, "DeZhouOperationNotify", DeZhouOperationNotify)
	end
end

--广播有玩家操作通知
function Table:_BroadCastOpNotify(nPos, nOp, nCallOrRaiseChip, tUser, nIsRoundBet)
	--广播给从服
	local OpNotify = {}
	OpNotify.nPos = nPos
	OpNotify.nOp = nOp
	OpNotify.nCallOrRaiseChip = nCallOrRaiseChip
	OpNotify.isAuto = tUser.isAuto
	OpNotify.nStatus = tUser.nStatus
	OpNotify.arrPreOpOption = {}
	OpNotify.nIsRoundBet = nIsRoundBet
	for _, pos in ipairs(self.arrPosPartIn) do
		local tem = self.arrUsers[pos]
		assert(tem ~= nil)
		table.insert(OpNotify.arrPreOpOption, { nSitId = pos, tPreOpOption = tem.tPreOpOption })
	end
	self:_BroadCastToSlaves("OpNotify", OpNotify)
	--主要是广播给机器人
	local DeZhouOpNotify = {}
	DeZhouOpNotify.nPos = nPos          --座位号
	DeZhouOpNotify.nOp = nOp            ---5:弃牌,  -1:AllIn, -2:看牌, -6:跟注, -3:加注
	DeZhouOpNotify.nBet = nCallOrRaiseChip --跟注或加注时有效，表示具体的跟注\加注数值(>0)
	for nPos, _ in pairs(self.arrUsers) do
		self:SendToUser(nPos, "DeZhouOpNotify", DeZhouOpNotify)
	end
end

--广播游戏即将开始,nPauseRemain:暂停时间 秒
function Table:_BroadToStart(nSeconds, nPauseRemain)
	local nMSeconds = nSeconds
	if nSeconds > 0 then
		nMSeconds = nSeconds * 1000
	end
	--广播给从服
	self:_BroadCastToSlaves("ToStartNotify", { nMSeconds = nMSeconds, nPauseRemain = nPauseRemain })
end

--广播游戏开始
function Table:_BroadCastGameStartNotify(nSmallBlindPos, nBigBlindPos, arrPosPartInSort, nForceBlindPos, nAcBetSmall,
										 nAcBetBig, nAcForceBet, nZhuaTouPos)
	--广播给从服
	local GameStartNotify = {}
	GameStartNotify.nPotSum = self.nPotSum                  --底池总额(已押筹码总额)
	GameStartNotify.nStage = self.nStage                    --当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	GameStartNotify.sPaiJuId = self.sPaiJuId                --牌局id
	GameStartNotify.nJuShu = self.nJuShu                    --当前局数
	GameStartNotify.nBankerPos = self.nBankerPos            --庄家位置
	GameStartNotify.nTimeStart = self.nTimeStart            -->0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	GameStartNotify.nSmallBlindPos = nSmallBlindPos         --小盲位置
	GameStartNotify.nBigBlindPos = nBigBlindPos             --大盲位置
	GameStartNotify.nZhuaTouPos = nZhuaTouPos               --抓头位置
	GameStartNotify.nZhuaTou = self.nZhuaTou
	GameStartNotify.nPreAnte = self.nPreAnte                --前注
	GameStartNotify.nOperateTime = self.nOperateTime        --操作时间
	GameStartNotify.arrChat = self.arrChat                  --表情配置
	if nForceBlindPos then
		GameStartNotify.nForceBlindPos = nForceBlindPos     --强盲位置(可能为nil,如果没强盲)
		GameStartNotify.nForceBlind = self.nForceBlind      --强盲数额
	end
	GameStartNotify.nAcBetSmall = nAcBetSmall               --小盲位实际盲注(因存在筹码不足的情况，所以有此值)
	GameStartNotify.nAcBetBig = nAcBetBig                   --大盲位实际盲注(因存在筹码不足的情况，所以有此值)
	GameStartNotify.nAcForceBet = nAcForceBet               --实际强盲下注
	GameStartNotify.nTakeInMin = self.nBuyMin               --最低带入
	GameStartNotify.nTakeInMax = self.nBuyMax               --最高带入
	GameStartNotify.tLeaveTableConfig = self.tLeaveTableConfig -- 离开牌桌配置

	GameStartNotify.arrPartInUser = {}
	-- GameStartNotify.nHashData = self.hashHelper:GetSlaveData()  -- 同步从服hash信息
	for _, nPos in ipairs(arrPosPartInSort) do
		local tUser = self:_GetUser(nPos)
		assert(tUser ~= nil)
		local item = {}
		item.nUserId = tUser.nUserId                  --玩家ID
		item.nSitId = nPos                            --座位号
		item.nBalance = tUser.nBalance                --余额
		item.isBanker = (self.nBankerPos == nPos)     --是否为庄; true:是 ,false:否
		item.arrHoleCards = tUser.arrHoleCards        --底牌(值为0的牌，显示牌背,表示还没亮牌)
		item.nCardType = self:_GetCardType(tUser.tCardType) --牌型(见本文件头部"牌型定义")
		item.nBet = tUser.nBet                        --玩家总下注(注意，发给前端的不是总下注，在从服进行了分开的)
		item.nStatus = tUser.nStatus                  --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观
		item.tPreOpOption = tUser.tPreOpOption        --自己当前可预操作选项
		item.nChipBuy = tUser.nChipBuy
		item.isShowHoleCard = tUser.isShowHoleCard    --如果延迟看牌,则不公布底牌给玩家,直到获得第一次操作权(由从服处理这个逻辑)
		item.nUnLockGold = self:Get_User_UnLockGold(tUser) --同步可用金币(主要服务于试玩房金币,其它一般以redis为准)
		item.nInsureStatus = tUser.nInsureStatus
		item.nBuyTo = tUser.nBuyTo
		item.nLoseAmount = tPenaltyManager:GetProfit(tUser.nUserId, self.sTableId, tUser.nLockGoldInTable)
		item.nPlayCnt = tPenaltyManager:getPlayCnt(tUser.nUserId, self.sTableId) --总局数
		table.insert(GameStartNotify.arrPartInUser, item)
	end
	self:_BroadCastToSlaves("GameStartNotify", GameStartNotify)

	--主要是广播给机器人
	local DeZhouStartNotify = {}
	DeZhouStartNotify.arrUsersBet = { { nPos = nSmallBlindPos, nBet = nAcBetSmall }, { nPos = nBigBlindPos, nBet = nAcBetBig },
		{ nPos = (nForceBlindPos or -1), nBet = nAcForceBet } }
	for nPos, tUser in pairs(self.arrUsers) do
		DeZhouStartNotify.nTakeIn = tUser.nBalance
		DeZhouStartNotify.arrHoleCards = tUser.arrHoleCards
		self:SendToUser(nPos, "DeZhouStartNotify", DeZhouStartNotify)
	end
	return -1
end

--广播玩家筹码余额变动
function Table:_BroadCastDeZhouBalanceNotify(nPos, nBalance)
	--广播给从服
	self:_BroadCastToSlaves("DeZhouBalanceNotify", { nPos = nPos, nBalance = nBalance })
end

--广播配置更改
function Table:_BroadCastDeZhouConfigNotify(tConfigItem)
	local DeZhouConfigNotify = {}
	DeZhouConfigNotify.tConfigItem = tConfigItem
	DeZhouConfigNotify.nCapacity = self.nCapacity
	--广播给从服
	self:_BroadCastToSlaves("DeZhouConfigNotify", DeZhouConfigNotify)
end

--广播结算
function Table:_BroadCastSettleNotify(DeZhouSettleNotify)
	--广播给从服
	self:_BroadCastToSlaves("SettleNotify", DeZhouSettleNotify)
	--主要是广播给机器人
	for nPos, _ in pairs(self.arrUsers) do
		self:SendToUser(nPos, "DeZhouSettleNotify", DeZhouSettleNotify)
	end
end

--广播桌子重置
function Table:_BroadCastTableResetNotify()
	--广播给从服
	self:_BroadCastToSlaves("TableResetNotify", { nStage = self.nStage, isAutoNext = self.isAutoNext })
	--主要是广播给机器人
	for nPos, _ in pairs(self.arrUsers) do
		self:SendToUser(nPos, "DeZhouTableResetNotify", { nNoUse = 0, isAutoNext = self.isAutoNext })
	end
end

--发送数据接口
--//示例 : SendToUser(1,"RaiseReq",{nSitId=1,nRaiseChip=100})
function Table:SendToUser(nSitId, strMsgName, tMsgData)
	if self.isTableClose then
		return false
	end
	local tUserInfo = self.arrUsers[nSitId]
	if not tUserInfo then
		self:Print("_SendToUser Fail,can not find User of nSitId_%d  %s ", nSitId, strMsgName)
		return false
	end
	self.tInterFace.SendToUser(tUserInfo.nUserId, strMsgName, tMsgData)
	return true
end

function Table:OnUserEnter(tUserInfo, nPosForPlay)
	local nUserId = tUserInfo.nUserId
	local nSitId, tUser = self:_GetSitIdByUserId(nUserId)
	if nSitId then
		self:Print("already in seat")
		return nil, nil, 34
	end
	if self:_GettUserLossMark(nUserId) then
		return nil, nil, 40
	end

	--设置位置上的玩家信息
	local tUser = {}
	tUser.nUserId = tUserInfo.nUserId
	tUser.sFaceId = tUserInfo.sFaceId or '1'
	tUser.sName = tUserInfo.sName or "No Name"
	tUser.nGold = tUserInfo.nGold or 0
	tUser.nCurCost = 0
	tUser.isAddFreeTimeIfStart = tUserInfo.isAddFreeTimeIfStart or false --游戏开始时，免费场试玩次数是否加1

	tUser.nSex = tUserInfo.nSex or 0                                  --0:男 1:女
	tUser.isAndroid = tUserInfo.isAndroid
	tUser.nShopId = tUserInfo.nShopId or -1
	tUser.isOffLine = false --是否掉线 废弃
	tUser.nOffLineCnt = 0 --掉线+1 上线-1
	tUser.sShopAccount = tUserInfo.sShopAccount or ""

	tUser.nBuyTo = tUserInfo.nBuyTo or 0      --玩家设置的买入
	tUser.nTakeOutWant = 0                    --玩家设置带出

	tUser.nIsAutoBuy = tUserInfo.nIsAutoBuy or 0 --玩家设置的是否自动每局买入

	tUser.tGps = tUserInfo.tGps
	tUser.sIP = tUserInfo.sIP

	tUser.nSitId = nil
	tUser.arrHoleCards = {}         --底牌(值为0的牌，显示牌背,表示还没亮牌)
	tUser.nBet = 0                  --玩家当轮当前下注数目(0时不要显示)
	tUser.nBetSum = 0               --当局总下注
	tUser.nStatus = UserStatus.nLooker --当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观
	tUser.nOpTimeRemain = 0         --剩余可操作(思考)时间 (思考中时有效,其它情况时为0)
	tUser.tOperation = nil          --当前自己可操作信息(自己为思考状态时有)
	tUser.tPreOpOption = nil        --自己当前可预操作选项
	tUser.tCardType = nil           --结算后存放牌型信息 {nCardType=nCardType,nComValue=nComValue,arrFiveBack=arrFiveBack}
	tUser.isToGainRights = false    --是否即将获得操作权
	tUser.isNeedSettle = false      --是否需要结算

	tUser.nChipBuy = 0              --一局开始时新增的筹码买入
	tUser.nTimeOutCnt = 0           --玩家超时次数
	tUser.isAuto = false            --是否托管 (托管时操作时间变短)

	tUser.isHaveOp = false          --当局是否有操作
	tUser.nConsecutiveNoOp = 0      --连续多少'局'没操作		
	tUser.nFee = 0                  --记录一局开始时扣减的手续费(废弃)

	tUser.nStanpUpReason = nil      --当局结束后,是否强制站起(nil:否,非nil:被站起原因)

	tUser.isShowCardWhenEnd = false --是否结束后亮牌
	tUser.arrPreSetHoleCard = {}    --预设置的底牌

	tUser.nGetChanceCnt = 0         --当局获得操作机会的次数
	tUser.nFGetRightTime = 0        --最近一次获得操作权时的间戳(延时操作不会重设置该值)
	tUser.nGetRightTime = 0         --最近一次获得操作权时的间戳(延时操作相当于重新获得操作)
	tUser.nOpLong = 0               --获得操作时，操作时间(延时操作相当于重新获得操作)
	tUser.nLockGoldInTable = 0      --当前被锁在本桌子的金币
	tUser.isShowHoleCard = true     --由于延迟看牌原因,false时不给玩家看底牌,直到第一次获得操作时才公布且置true
	tUser.nDelayCount = 0           --当前已进行延时的次数(玩家可操作时有效)
	tUser.nInsureDelayCount = 0     --当前保险已进行延时的次数(玩家可操作时有效)

	tUser.isRetain = false          --是否留座
	tUser.nRetainTimerId = nil      --留座计时器id
	tUser.isBackToLobby = false     --是否返回了大厅

	tUser.nAiType = 0               --机器人Ai类型;0一般 1进取 2保守
	tUser.nPlayCnt = 0              --当前局数
	tUser.nLoseAmount = 0           --输钱总数
	tUser.nHalfFold = false         --中途弃牌
	tUser.nTempChips = 0            --撤码暂存区
	tUser.nAutoChips = 0            --玩家自动撤码设置值
	tUser.isAutoTabkeOut = false    --是否设置了自动撤码
	tUser.nInsureCost = 0
	tUser.nInsureStatus = 0         --保险可购买状态

	--寻找一个空闲位置
	nPosForPlay = nPosForPlay or self:_FindAPosForPlay()
	self:Print("_FindAPosForPlay %s", tostring(nPosForPlay))

	--如果不能坐下到牌局位置
	if not nPosForPlay then
		self:Print("OnUserEnter Fail,Find pos Fail")
		return nil, nil, 14
	end
	assert(self:_IsPlayerPos(nPosForPlay))


	--检查并返还之前存储的抽水
	-- if tUser then
	--     -- 尝试返还之前存储的抽水
	--   self:ReturnUserTax(nUserId, tUser)
	--   self:ReturnPenalty(nUserId, tUser)
	-- end

	--初始化带入金币
	local info = self:_GetLatelyBalance(tUser.nUserId)
	local nBestTakeIn = info.nBalance + info.nTempChips
	local curGold = self:Get_User_UnLockGold(tUser)
	if LessThan(curGold, nBestTakeIn) then
		return nil, nil, 42
	end
	if tUser.isAndroid then
		local arr = {}
		local nTabkeIn = self.nMinTabkeInBB
		self:Print("OnUserEnter self.nMinTabkeInBB: %.1f self.nMaxTabkeInBB: %0.1f  ", self.nMinTabkeInBB,
			self.nMaxTabkeInBB)
		for i = 1, 8, 1 do
			if nTabkeIn >= self.nMinTabkeInBB and nTabkeIn <= self.nMaxTabkeInBB then
				table.insert(arr, nTabkeIn)
				self:Print("OnUserEnter nTabkeIn: %0.1f  ", nTabkeIn)
			end
			nTabkeIn = nTabkeIn + self.nMinTabkeInBB * 0.1
		end
		local nRandom = math.random(1, #arr)
		nBestTakeIn = self.nBuyMin * nRandom --机器人坐下时带入金币
		tUser.nLockGoldInTable = nBestTakeIn
		self:Print("OnUserEnter nBestTakeIn: %.1f  %d arr: %s  ", nBestTakeIn, nRandom, cjson.encode(arr))
	end

	if not self:_InitUserTakeIn(tUser, nBestTakeIn, 0, PublicDefine.TakeInGoldType.TakeIn) then
		self:Print("OnUserEnter,Gold Not enough") --不会执行到这
		return nil, nil, 12
	end
	tUser.nBalance = tUser.nLockGoldInTable or 0 --当前可用筹码
	self.tTableOverview:HaveTakeIn(nUserId, tUser.sName, tUser.nBalance, tUser.sFaceId)
	self:_SetSitInSeat(nPosForPlay, tUser, true)
	tPubUser.IncrUnbalancedBy(tUser.nUserId, 1)
	tPublicClub.RecordUserGPS(nUserId, tUser.tGps)
	return tUser, nPosForPlay, 0
end

function Table:_AndroidTakeIn()
	local arr = {}
	local x = self.nBigBlind * 50
	local n = math.floor((self.nBuyMax - self.nBuyMin) / x) -- 使用 math.floor 替代 // 操作符
	return self.nBuyMin + math.random(0, n) * x
end

--玩家游戏中离开(站起),调用时还没离开
function Table:_LeaveInPlaying(tUser)
	self:Print("_LeaveInPlaying,nPos:%d nUserId:%d", tUser.nSitId, tUser.nUserId)
	assert(not self.isBanStandUpReq)

	self:_CollectBetToPoolsN({ tUser.nSitId }) --收归玩家下注到底池
	local tCardType = tUser.tCardType or {}
	local nPaiJuProfit, nChouShui, nInsurProfit, nInsureCardVal, drawChips, nHandProfit = self:_UserChipsSettle(tUser, {},
		false) --结算
	self.tReview:SettleMid({
		arrGoldGet = {},
		nPos = tUser.nSitId,
		arrCombinedCards = tCardType.arrFiveBack or {},
		nCardType = tCardType.nCardType or 0,
		isWin = false,
		nProfit = nPaiJuProfit,
		nCmpValue = tCardType.nComValue,
		isShowCardWhenEnd = false,
		nCurGold = tUser.nBalance,
		nChouShui = nChouShui,
		nBetSum = tUser.nBetSum,
		nHandProfit = nHandProfit
	})
	local nRmCnt = _removeItem(self.arrPosPartIn, tUser.nSitId, true)
	assert(nRmCnt == 1)
	self.tReview:LeaveInPlaying(tUser.nSitId, nPaiJuProfit) --回顾记录

	if self.isGapOfNow or self.isTableError then         --正在跳转到下一轮或结算
		self:_ResetUser(tUser)
		return
	end

	--如果玩家当前获得了操作权或即将获得操作权, 则需要结束其操作权
	if tUser.nStatus == UserStatus.nThinking or tUser.isToGainRights then
		self:_SetUserStatus(tUser, UserStatus.nFold)
		self:_OpEnd(tUser.nSitId)
	elseif tUser.nStatus ~= UserStatus.nFold then
		local nTheOnlyNotFoldPos, tNotFoldUser = self:_IsJustOneNotFoldInCurRound()
		if nTheOnlyNotFoldPos then
			self:Print("Remain One NotFoldUser:%d", nTheOnlyNotFoldPos)
			assert(tNotFoldUser.nStatus == UserStatus.nThinking or tNotFoldUser.isToGainRights)
			self:_CancelRights(tNotFoldUser)
			self:_SetUserStatus(tNotFoldUser, UserStatus.nWaitForOp)
			self:_ToNextRound(0.2)
		end
	end
	self:_ResetUser(tUser)
end

function Table:_IncrUserCountBy(nIncrValue, isAndroid, nUserID)
	if isAndroid == false then
		self:ClubTableInfoNotify({ sitId = nUserID, isLeave = nIncrValue == -1 })
	end
	self.nUserCnt = self.nUserCnt + nIncrValue
	if not isAndroid then
		self.nUserCntOfReal = self.nUserCntOfReal + nIncrValue
	else
		self.nAndroidCnt = self.nAndroidCnt + nIncrValue
	end
	if self.nClubId then
		local tTableInfo = {}
		tTableInfo.nNowCnt = self.nUserCnt
		self:ClubTableInfoNotify(tTableInfo)
	end
	tPubUser.UpdateTableUserCnt(self.sTableId, self.nAndroidCnt, self.nUserCntOfReal)
end

function Table:ClubTableInfoNotify(tTableInfo)
	if self.nClubId == nil or self:MatchRoomId() == 0 then
		return
	end
	tPublicClub.ClubTableInfoNotify(self.nClubId, self.sTableId, tTableInfo)
end

function Table:_refreshUserInfo()
	local info = {}
	for nPos, tUser in pairs(self.arrUsers) do
		table.insert(info, { nUserId = tUser.nUserId, sName = tUser.sName, nBalance = tUser.nBalance })
	end
	tPubUser.API_ChangeTable(self.sTableId, cjson.encode(info))
end

--坐下
function Table:_SetSitInSeat(nPos, tUser, isNotifySelf)
	self.arrUsers[nPos] = tUser
	self.tUserIdToPos[tUser.nUserId] = nPos
	self:_IncrUserCountBy(1, tUser.isAndroid, tUser.nUserId)
	tUser.nSitId = nPos
	tUser.nConsecutiveNoOp = 0
	self:_BroadCastUserSitDownNotify(tUser)
	self:_TryToStartGame()
	tPubUser.SetUserSeatStatus(tUser.nUserId, true)
	self:Print("_SetSitInSeat nPos:%d nUserId:%d nUserCnt:%d", nPos, tUser.nUserId, self.nUserCnt)
	self.tUserNameToIsUsed[tUser.sName] = true
	if tUser then
		-- 坐下后再返还
		local user_id = tUser.nUserId
		self:ReturnUserTax(user_id, tUser)
		self:ReturnPenalty(user_id, tUser)
	end
	self:_refreshUserInfo()
end

function Table:_SetLeaveSeat(nSitId, nReason, isKick)
	local tUser = self.arrUsers[nSitId]
	assert(tUser ~= nil, 'Err happen')
	self.tTableOverview:StandUp(tUser.nUserId)
	if tUser.isAndroid then
		self.tTableOverview:UserLeave(tUser.nUserId)
	end
	--是否游戏中途退出(需收归下注、结束操作权等)
	if tUser.isNeedSettle and self:_IsPartInUser(nSitId) then
		self:_LeaveInPlaying(tUser)
	end
	-- self:TaxByTableRateSettle(tUser.nUserId, tUser.isAndroid)
	tPubUser.SetUserSeatStatus(tUser.nUserId, false)
	self.arrUsers[nSitId] = nil
	self.tUserIdToPos[tUser.nUserId] = nil
	self:_RetainCountDownCancel(tUser)
	self:_IncrUserCountBy(-1, tUser.isAndroid, tUser.nUserId)
	self.tUserNameToIsUsed[tUser.sName] = nil
	self:_SaveLatelyBalance(tUser.nUserId, tUser.nBalance, tUser.nTempChips, tUser.isAndroid)
	self:_ResetUser(tUser)
	-- 计算抽水 局抽
	local tableChip = tUser.nLockGoldInTable or 0
	if self:IsTotalRake() and not tUser.isAndroid then
		-- 局抽水交税
		local tax = taxHelp:onLeaveRoom(tUser.nUserId, self.sTableId, tableChip, self.tConfitOfTax.nTaxRate)
		if tax > 0 then
			local reamain = self:CostUserTableGold(tUser, tUser.nUserId, tax)
			self.tReview:CacheCostGoldData(tUser.nUserId, tUser.sName, -tax, reamain, GoldCReason.nTableTax) --记录复盘下注信息
			-- 记录抽水信息
			self:StoreUserTax(tUser.nUserId, tax)
			local nSourceType = 10000 + 100 * self.nGameId + GoldCReason.nTaxCost
			local isSuccee, nAcChange = self:Gold_ChangeAndReLock(tUser, -tax, nSourceType, self.nRoomId,
				tUser.nTempChips)
			self:Print("[_SetLeaveSeat] Gold_ChangeAndReLock result: isSuccee=%s, nAcChange=%s", tostring(isSuccee),
				tostring(nAcChange))
			self.tTableOverview:ProfitAdd(tUser.nUserId, -tax)
			tPenaltyManager:tax(tUser.nUserId, self.sTableId, tax)
		end
	end
	self:StandUpByPenalty(tUser, tableChip, nReason, isKick) -- 站起时属于暂时罚款,不更新用户下次带入金额, 只有正在罚款后再去更新

	self:_UserBalanceToGold(tUser)
	if (self.nCutUserInfo.nCutUserId or 0) == tUser.nUserId then
		self.nCutUserInfo = {}
		self.isCutting = false
	end
	tPubUser.IncrUnbalancedBy(tUser.nUserId, -1)
	self.tInterFace._LeaveTable(tUser.nUserId, self)

	self:_BroadCastUserStanpUpNotify(tUser)
	self:_TryToStartGame()
	self:_refreshUserInfo()

	self:Print("_SetLeaveSeat nSitId:%d nUserId:%d  ", nSitId, tUser.nUserId)
	return tUser
end

--是否是正在参与牌局的玩家
function Table:_IsPartInUser(nPos)
	if self.nStage == TableState.nInit then
		return false
	end
	return _IsHaveEle(self.arrPosPartIn, nPos)
end

--强制玩家站起
function Table:_ForceStandUp(nSitId, nCode, isKick)
	-- 强制站起类型需要区分, 属于用户侧原因导致强制站起时, 是需要罚款的,而管理侧的强制站起则不需要罚款
	local nForceStandUpType = tLeaveTableType.nForceStandUpBySystem
	if nCode ~= nil and nCode == 17 then
		nForceStandUpType = tLeaveTableType.nForceStandUpByUser
	end
	if nCode and (nCode == MsgCode.nKickByLive or nCode == MsgCode.nKickByAdmin or nCode == MsgCode.nKickToLobbyByAdmin or nCode == MsgCode.nKickBan) then
		isKick = true
	end
	local tUser = self:_SetLeaveSeat(nSitId, nil, isKick)
	self:Print("_ForceStandUp,nPos:%d nUserId:%d nCode:%s, isKick: %s", nSitId, tUser.nUserId, tostring(nCode),
		tostring(isKick))
	if nCode then
		self:SendFailNotifyV2(nil, tUser.nUserId, nCode, "_ForceStandUp")
	end
end

function Table:_GetProtoTakeInRange(tUser)
	if tUser == nil then
		return nil
	end
	local nUnLockGold = self:Get_User_UnLockGold(tUser)
	local DeZhouTakeInRangeRsp = {}
	DeZhouTakeInRangeRsp.nGold = nUnLockGold     --当前身上金币
	DeZhouTakeInRangeRsp.nMin = self.nBuyMin     --最小买入
	DeZhouTakeInRangeRsp.nMax = self.nBuyMax     --最大买入
	DeZhouTakeInRangeRsp.nIsAuto = tUser.nIsAutoBuy --是否每局自动买入 1:是 其它:否
	return DeZhouTakeInRangeRsp
end

--机器人进入桌子时带入随机筹码数量
function Table:RandomTakeInForAndroid()
	return math.random(self.nBuyMin, self.nBuyMax)
end

--
function Table:Print(str, ...)
	--if self.nLiveUserID==0 then return end
	tBase.Log(self.sTableId .. "_" .. self.nJuShu .. "=>| " .. self.sPaiJuId .. "=>" .. str, ...)
end

-- 广播信息: 转发消息, 通知旁观服
function Table:TransmitProtobuf(strProto, tSendData)
	return
end

-- 通知旁观服: 维护旁观服的场景
function Table:BroadCastLookerSrv(tData)
end

----------------------------------------------------------------------------------------------------------------------------------------------------
---
-- 关桌时, 结算用户罚款和盈利; 后台关桌的情况需要区分处理, 不需要罚款
function Table:PenaltyByTableSettle_All(nReason)
	local tPenatlyUsers = tPenaltyManager:getAllUser(self.sTableId)
	tBase.Log("[PenaltyByTableSettle_All] table has close[nReason=%d], penatly user info: %s", nReason,
		cjson.encode(tPenatlyUsers))

	local tCloseTableWithPenalty = self:_getCloseTableWithPenalty() -- 不需要罚款的关桌类型
	if nReason and tCloseTableWithPenalty[nReason] then          -- 关桌类型不需要罚款
		for sUserId, _ in pairs(tPenatlyUsers) do
			self:ReturnPenalty(tonumber(sUserId), nil, nReason)
		end
		return
	end

	-- 关桌类型需要罚款
	for sUserId, _ in pairs(tPenatlyUsers) do
		self:Penalty(tonumber(sUserId), nReason)
	end
end

-- 站起时暂扣罚款
function Table:StandUpByPenalty(tUser, tableChip, nReason, isKick)
	if not self.tLeaveTableConfig.isOpen then
		return
	end

	if isKick then
		tBase.Log("[StandUp] nUserId=%d, is Kick to lobby", tUser.nUserId)
		return
	end

	local tCloseTableWithPenalty = self:_getCloseTableWithPenalty() -- 不需要罚款的关桌类型
	if nReason and tCloseTableWithPenalty[nReason] then          --属于不罚款的关桌类型
		tBase.Log("[StandUp] nUserId=%d, table has close[nReason=%d], not need penatly", tUser.nUserId, nReason)
		return
	end

	local arrRevenueUsers = self:_getArrRevenueInfo()
	tBase.Log("[StandUp] nUserId=%d, revenue users: %s", tUser.nUserId, cjson.encode(arrRevenueUsers))
	local nPenalty2User, nPenalty2System, last_paijuid = tPenaltyManager:onStandUp(tUser.nUserId, self.sTableId,
		tableChip or 0,
		self.tLeaveTableConfig, arrRevenueUsers, tUser.sName)
	local totalPenaltyGold = nPenalty2User + nPenalty2System
	if LessOrEqual(totalPenaltyGold, 0) then
		return
	end
	-- 从用户筹码中扣除罚款
	-- 罚款用户收益部分
	local nSourceType = self:_getSourceTypeWithPenaltyToUser()
	local isSuccee, nAcChange = self:Gold_ChangeAndReLock(tUser, -nPenalty2User, nSourceType, self.nRoomId,
		tUser.nTempChips)
	tBase.Log("[StandUp] Gold_ChangeAndReLock[Penalty to users] result: isSuccee=%s, nAcChange=%s", tostring(isSuccee),
		tostring(nAcChange))

	-- 罚款系统收益部分
	nSourceType = self:_getSourceTypeWithPenaltyToSystem()
	local isSuccee, nAcChange = self:Gold_ChangeAndReLock(tUser, -nPenalty2System, nSourceType, self.nRoomId,
		tUser.nTempChips)
	tBase.Log("[StandUp] Gold_ChangeAndReLock[Penalty to system] result: isSuccee=%s, nAcChange=%s", tostring(isSuccee),
		tostring(nAcChange))

	-- 罚款是从用户收益中扣除, 不存在余额不够的情况, 就不需要校验nAcChange是否不够的情况
	self.tTableOverview:ProfitAdd(tUser.nUserId, -totalPenaltyGold)
	tBase.Log("[Penalty] ProfitAdd nUserId=%d, totalPenaltyGold=%s,", tUser.nUserId, tostring(totalPenaltyGold))

	local tmpChouType = 0
	if self:IsTotalRake() then
		tmpChouType = 1
	end
	-- 记录
	RecordDbr.UpdatePenaltyRevenueOnPaiJuWinLossRecord(self.sTableId, last_paijuid, tUser.nUserId, totalPenaltyGold, 0,
		tmpChouType, self.nGameId, self.nGoldType, self.sTableName, self.nSmallBlind, self.nPreAnte, self.nZhuaTou, self.preAnteOdd)

	-- 保存罚款信息
	local tPenaltyInfo = {
		nUserId = tUser.nUserId,
		sName = tUser.sName,
		nStatus = UserStatus.nLooker,                                  -- 用户已经站起了
		nPlayCnt = tPenaltyManager:getPlayCnt(tUser.nUserId, self.sTableId), --总局数,
		nLimitPlayCnt = self.tLeaveTableConfig.nLots,
		nWinGold = tPenaltyManager:GetProfit(tUser.nUserId, self.sTableId),
		nGoldCnt = -totalPenaltyGold,
		arrRevenue = {},
	}

	self.tTableOverview:AddPenaltyRecord(tPenaltyInfo)

	-- 通知玩家自己罚款信息
	local sMsgToSystem = string.format("因盈利后未完成%d手，系统已暂扣<color=#FF1E43>%.1fUSDT</color>，若牌局结束时仍未达标，罚款的%d%%将分配给同桌玩家",
		self.tLeaveTableConfig.nLots, totalPenaltyGold, publicApi.Floor_n(self.tLeaveTableConfig.nUserRatio, 2) * 100)
	local sMsgToLobby = string.format(
		"因盈利后未完成<color=#FAD553>%d手</color>，系统已暂扣<color=#FF1E43>%.1fUSDT</color>，若牌局结束时仍未达标，罚款的<color=#FAD553>%d%%</color>将分配给同桌玩家",
		self.tLeaveTableConfig.nLots, totalPenaltyGold, publicApi.Floor_n(self.tLeaveTableConfig.nUserRatio, 2) * 100)
	self:_BroadCastToSlaves("LeaveTableNotify",
		{
			nNotifyUserId = tUser.nUserId,
			nMsgType = PublicDefine.GoldCReason.nPenalty,
			sMsgToSystem = sMsgToSystem,
			sMsgToLobby =
				sMsgToLobby
		})
end

-- 用户罚款或者受益时可能不在座位上了, 这时候增减用户金币时,需要获取用户的金币信息才能操作用户余额
function Table:_getUserGoldInfo(nUserId)
	local tUserGold = tPublicUserGold.GetUserGoldInfo(nUserId, self.nItemId)
	return {
		nUserId = nUserId,
		nLockGoldInTable = tUserGold.nFreezeGoldSum,
		nTempChips = 0,
		nGold = tUserGold.nGold,
	}
end

-- 正式罚款
-- tUser 被罚款用户, arrUsers 牌桌中的用户
function Table:Penalty(nUserId, nReason)
	-- 正式罚款, 将用户收益部分分配给用户
	tBase.Log("[Penalty]  nUserId=%d tLeaveTableConfig=%s", nUserId, cjson.encode(self.tLeaveTableConfig or {}))
	-- 从用户筹码中扣除罚款
	local nPenalty2User, nPenalty2System, arrRevenueUsers = tPenaltyManager:GetPenaltyInfo(nUserId, self.sTableId)
	local totalPenaltyGold = nPenalty2User + nPenalty2System
	-- 用户没有罚款
	if LessOrEqual(totalPenaltyGold, 0) then
		return
	end

	-- 用户能玩的总手数不够, 需要返还罚款
	local nJoinInPlayCnt = tPenaltyManager:getJoinInPlayCnt(nUserId, self.sTableId)

	if self.nPlayCnt - nJoinInPlayCnt < self.tLeaveTableConfig.nLots then
		tBase.Log(
			"[Penalty] ReturnPenalty nUserId=%d nPenalty2User=%.2f nPenalty2System=%.2f, JoinInPlayCnt=%d, nTablePlayCnt=%d, limitPlayCnt=%d",
			nUserId, nPenalty2User, nPenalty2System, nJoinInPlayCnt, self.nPlayCnt, self.tLeaveTableConfig.nLots)
		self:ReturnPenalty(nUserId, nil, nReason)
		return
	end

	local _, _, _, last_paijuid = tPenaltyManager:Penalty(nUserId, self.sTableId)

	-- 通知玩家自己罚款信息
	local sMsgToSystem = string.format("由于您在盈利后未打满%d手，系统对你做出<color=#FF1E43>%.1fUSDT</color>的罚款，罚款的%d%%将分配给同桌玩家",
		self.tLeaveTableConfig.nLots, totalPenaltyGold, publicApi.Floor_n(self.tLeaveTableConfig.nUserRatio, 2) * 100)
	local sMsgToLobby = string.format(
		"由于您在盈利后未打满<color=#FAD553>%d手</color>，系统对你做出<color=#FF1E43>%.1fUSDT</color>的罚款，罚款的<color=#FAD553>%d%%</color>将分配给同桌玩家",
		self.tLeaveTableConfig.nLots, totalPenaltyGold, publicApi.Floor_n(self.tLeaveTableConfig.nUserRatio, 2) * 100)
	self:_BroadCastToSlaves("LeaveTableNotify",
		{
			nNotifyUserId = nUserId,
			nMsgType = PublicDefine.GoldCReason.nPenalty,
			sMsgToSystem = sMsgToSystem,
			sMsgToLobby =
				sMsgToLobby
		})       -- 大厅广播用户罚款通知

	local tmpChouType = 0
	if self:IsTotalRake() then
		tmpChouType = 1
	end
	-- 获取各个玩家的收益金额
	local nSourceType = self:_getSourceTypeWithRevenue()
	local arrRevenue = self:_getUsersRevenue(nPenalty2User, arrRevenueUsers)
	local nick_name = tPenaltyManager:getUserInfo(nUserId, self.sTableId)
	for _, tRevenueUser in pairs(arrRevenue) do
		--local isSuccee, nAcChange=self:Gold_ChangeAndReLock(tRevenueUser,tRevenueUser.nRevenue,nSourceType,self.nRoomId,tRevenueUser.nTempChips)
		local isSuccee, nAcChange = tPubUser.ChangeUserTreasure({ --收益时用户已经站起了
			nUserID = tRevenueUser.nUserId,
			nItemID = 1,
			nDel = tRevenueUser.nRevenue,
			nSourceType = nSourceType,
			nNoNotice = true,
			sTableId = self.sTableId or "",
			sPaiJuId = self.sPaiJuId or ""
		})
		tBase.Log("[Penalty] Gold_ChangeAndReLock[Revenue to user] result: isSuccee=%s, nAcChange=%s", tostring(isSuccee),
			tostring(nAcChange))

		RecordDbr.UpdatePenaltyRevenueOnPaiJuWinLossRecord(self.sTableId, last_paijuid, tRevenueUser.nUserId, 0,
			tRevenueUser.nRevenue, tmpChouType, self.nGameId, self.nGoldType, self.sTableName, self.nSmallBlind, self.nPreAnte, self.nZhuaTou, self.preAnteOdd)

		-- 通知用户收益
		local sMsgToSystem = string.format("%s 玩家盈利后未打满%d手，您收到罚款<color=#00FF86>%.1fUSDT</color>。",
			BaseSink.decode(nick_name), self.tLeaveTableConfig.nLots, tRevenueUser.nRevenue)
		local sMsgToLobby = string.format(
			"<color=#FAD553>%s</color> 玩家盈利后未打满<color=#FAD553>%d手</color>，您收到罚款<color=#00FF86>%.1fUSDT</color>。",
			BaseSink.decode(nick_name), self.tLeaveTableConfig.nLots, tRevenueUser.nRevenue)
		self:_BroadCastToSlaves("LeaveTableNotify",
			{
				nNotifyUserId = tRevenueUser.nUserId,
				nMsgType = PublicDefine.GoldCReason.nPenaltyRevenue,
				sMsgToSystem =
					sMsgToSystem,
				sMsgToLobby = sMsgToLobby
			})                                -- 大厅广播用户受益通知
	end
end

-- 返还用户的罚款, 有3条途径, 1 - 用户罚款时发现条件不满足, 2 - 重新坐下(离桌类型), 3 - 系统操作导致用户触发条件
function Table:ReturnPenalty(nUserId, tUser, nReason)
	if not nUserId then
		self:Print("ReturnPenalty: nUserId is nil")
		return false, 0
	end

	local nPenalty2User, nPenalty2System, last_paijuid = tPenaltyManager:ReturnPenalty(nUserId, self.sTableId)
	local totalPenaltyGold = nPenalty2User + nPenalty2System
	if LessOrEqual(totalPenaltyGold, 0) then
		return
	end

	-- 用户可能已经站起状态了, 找不到用户信息了
	if not tUser then
		tUser = self:_getUserGoldInfo(nUserId) -- 此处只是用了更新redis缓存, 归还罚款时都是正数,nLockGoldInTable和nTempChips字段只参与用户金额是否够扣减, 不参与实际金额的变更
	end
	tUser.nGold = tUser.nGold + nPenalty2User + nPenalty2System

	-- 罚款用户收益部分返还
	local nSourceType = self:_getSourceTypeWithPenaltyToUser()
	-- local isSuccee, nAcChange=self:Gold_ChangeAndReLock(tUser,nPenalty2User,nSourceType,self.nRoomId,tUser.nTempChips)
	if nReason then
		local isSuccee, nAcChange = tPubUser.ChangeUserTreasure({
			nUserID = nUserId,
			nItemID = 1,
			nDel = nPenalty2User,
			nSourceType =
				nSourceType,
			nNoNotice = true,
			sTableId = self.sTableId or "",
			sPaiJuId = self.sPaiJuId or ""
		})
		tBase.Log(
			"[ReturnPenalty] ChangeUserTreasure[ReturnPenalty to users on standUp] result: isSuccee=%s, nAcChange=%s",
			tostring(isSuccee), tostring(nAcChange))
	else -- 坐下状态的返还
		local isSuccee, nAcChange = self:Gold_Change(tUser, nPenalty2User, nSourceType, self.nRoomId)
		tBase.Log(
			"[ReturnPenalty] Gold_ChangeAndReLock[ReturnPenalty to users on sitdown] result: isSuccee=%s, nAcChange=%s",
			tostring(isSuccee), tostring(nAcChange))
	end

	-- 罚款系统收益部分返还
	nSourceType = self:_getSourceTypeWithPenaltyToSystem()
	if nReason then
		local isSuccee, nAcChange = tPubUser.ChangeUserTreasure({
			nUserID = nUserId,
			nItemID = 1,
			nDel = nPenalty2System,
			nSourceType =
				nSourceType,
			nNoNotice = true,
			sTableId = self.sTableId or "",
			sPaiJuId = self.sPaiJuId or ""
		})
		tBase.Log(
			"[ReturnPenalty] ChangeUserTreasure[ReturnPenalty to users on standUp] result: isSuccee=%s, nAcChange=%s",
			tostring(isSuccee), tostring(nAcChange))
	else -- 坐下状态的返还
		local isSuccee, nAcChange = self:Gold_Change(tUser, nPenalty2System, nSourceType, self.nRoomId)
		tBase.Log(
			"[ReturnPenalty] Gold_ChangeAndReLock[ReturnPenalty to system on sitdown] result: isSuccee=%s, nAcChange=%s",
			tostring(isSuccee), tostring(nAcChange))
	end

	--self.tTableOverview:ProfitAdd(nUserId, nPenalty2User + nPenalty2System)
	self.tTableOverview:ProfitAdd(tUser.nUserId, totalPenaltyGold)
	self.tTableOverview:DelPenaltyRecord(nUserId)

	local tmpChouType = 0
	if self:IsTotalRake() then
		tmpChouType = 1
	end
	-- 记录, 返回罚款时需要更新罚款数据
	RecordDbr.UpdatePenaltyRevenueOnPaiJuWinLossRecord(self.sTableId, last_paijuid, tUser.nUserId, -totalPenaltyGold, 0,
		tmpChouType, self.nGameId, self.nGoldType, self.sTableName, self.nSmallBlind, self.nPreAnte, self.nZhuaTou, self.preAnteOdd)

	-- 通知玩家自己罚款信息, 坐下时返还的通知
	local tCloseTableWithPenalty = self:_getCloseTableWithPenalty() -- 不需要罚款的关桌类型
	local nJoinInPlayCnt = tPenaltyManager:getJoinInPlayCnt(nUserId, self.sTableId)

	local msg = string.format("你已回到牌桌，系统暂扣<color=#FF1E43>%.1fUSDT</color>的罚款，已经返还", totalPenaltyGold)
	if nReason and tCloseTableWithPenalty[nReason] then -- 关桌类型不需要罚款时的返还提示
		msg = string.format("房间已被管理关闭，系统暂扣<color=#FF1E43>%.1fUSDT</color>的罚款，已经返还", totalPenaltyGold)
	elseif nReason and self.nPlayCnt - nJoinInPlayCnt < self.tLeaveTableConfig.nLots then
		msg = string.format("房间剩余牌局手数不足最低要求，未触发离桌处罚。系统暂扣的<color=#FF1E43>%.1fUSDT</color>已为你返还。", totalPenaltyGold)
	end
	self:_BroadCastToSlaves("LeaveTableNotify",
		{ nNotifyUserId = nUserId, nMsgType = PublicDefine.GoldCReason.nPenalty, sMsgToSystem = msg, sMsgToLobby = msg })
end

-- 返回每个收益用户的座位号和收益金额, 最后一个位置的玩家收益剩余部分
function Table:_getUsersRevenue(nPenalty2User, arrRevenueUsers)
	local nRevenueCount = #arrRevenueUsers
	local nAverageRevenue = publicApi.Floor_n(nPenalty2User / nRevenueCount, 1)

	local count = 0
	local tRevenueUsers = {} -- {nPos = nGold}
	for _, tUser in ipairs(arrRevenueUsers) do
		if tUser then
			count = count + 1
			local tUserWithGold = self:_getUserGoldInfo(tUser.nUserId)
			if count < nRevenueCount then
				tUserWithGold.nRevenue = nAverageRevenue
			else
				local nOtherUserRevenue = publicApi.Floor_n((nRevenueCount - 1) * nAverageRevenue, 1)
				tUserWithGold.nRevenue = nPenalty2User - nOtherUserRevenue
			end
			tUserWithGold.sName = tUser.sName
			tUserWithGold.nStatus = tUser.nStatus
			table.insert(tRevenueUsers, tUserWithGold)
		end
	end

	return tRevenueUsers
end

function Table:_getSourceTypeWithPenaltyToUser()
	return 10000 + 100 * self.nGameId + GoldCReason.nPenalty
end

function Table:_getSourceTypeWithPenaltyToSystem()
	return 10000 + 100 * self.nGameId + GoldCReason.nSystemPenaltyRevenue
end

function Table:_getSourceTypeWithRevenue()
	return 10000 + 100 * self.nGameId + GoldCReason.nPenaltyRevenue
end

function Table:_getArrRevenueInfo()
	local t = {}
	tBase.Log("[StandUp] revenue users: %s", cjson.encode(self.arrUsers))
	for _, tUser in pairs(self.arrUsers) do
		if tUser then
			table.insert(t, {
				nUserId = tUser.nUserId,
				sName = tUser.sName,
				nStatus = tUser.nStatus,
			})
		end
	end
	tBase.Log("[StandUp] revenue users: %s", cjson.encode(t))
	return t
end

function Table:_getCloseTableWithPenalty()
	local tCloseTableWithPenalty = {}                                        -- 不需要罚款的关桌类型
	tCloseTableWithPenalty[Define.TableCloseReason.nGmClose] = true
	tCloseTableWithPenalty[Define.TableCloseReason.nNoRealUserTooLong] = true -- 桌子长时间没人关闭
	tCloseTableWithPenalty[Define.TableCloseReason.nClubTableTimeOut] = false --桌子超时关闭
	tCloseTableWithPenalty[Define.TableCloseReason.nBackstageClose] = true   -- 后台关闭
	tCloseTableWithPenalty[Define.TableCloseReason.nTableError] = true
	tCloseTableWithPenalty[Define.TableCloseReason.nTestTableUserLeave] = false --试玩桌真人离开
	tCloseTableWithPenalty[Define.TableCloseReason.nMatchServ] = true        --比赛服请求关闭
	return tCloseTableWithPenalty
end

return Table
