
local tBase 	  = require("base")         -- 基础功能接口
local Define =require("Define")
local RecordDbr =require("RecordDbr")
local tPubUser = require("PublicUserInfo") -- 用户信息
local tConfig =require("GameConfig") -- 
local tTimerAux =require("TimerAux")
local cjson    = require("cjson")
local tPublicRedis =require("PublicRedis")
local publicApi =require("publicApi")
local PublicDefine =require("PublicDefine")
local tAlg =require("GameAlg")
local tScAlg =require("GameAlg_Sc")
local GoldCReason =PublicDefine.GoldCReason

local MsgCode=PublicDefine.MsgCode
local TableState =PublicDefine.TableState
local UserStatus =PublicDefine.UserStatus
local UserOp =PublicDefine.UserOp
local RoomType =PublicDefine.RoomType

local function _CopyArr(arr)
	local cp ={}
	for _,v in ipairs(arr) do
		cp[#cp+1]=v
	end
	return cp
end
local function _ZeroArr(arr)
	if not arr then
		return
	end
	for dex,_ in ipairs(arr) do
		arr[dex]=0
	end
end


local Table = {}

--use
function Table:New(sTableId,tInterFace,tConfig)
	local tConfig =tConfig or {}
	local t = {}
	setmetatable(t, self)
	self.__index = self

	t.sTableId=sTableId or ""					--table id
	t.sTableName=""
	t.tInterFace=tInterFace     				--Game层接口 (Game =>table =>user)	
	t.Timer =tTimerAux:New()

	t.nRoomType =10										--10:大厅桌子 11:俱乐部桌子 12:比赛桌
	t.nGroupId =tConfig.nGroupId or 9					---
	t.nRoomId  =tConfig.nRoomId or -1					---
	t.nTableType =tConfig.nTableType or -1				---	--桌子类型
	t.nLiveUserID =tConfig.nLiveUserID or 0				---	--主播ID
	t.sLiveID =tConfig.sLiveID or ""					---
	t.nSmallBlind=tConfig.nSmallBlind or 1 				--- --小盲注数额
	t.nBigBlind=tConfig.nBigBlind or (t.nSmallBlind*2)	--- --大盲注数额(通常等于:小盲注x2)
	t.nZhuaTou = tConfig.nZhuaTou or (t.nBigBlind*2)	--- --抓头数额
	t.nCapacity =tConfig.nCapacity or 0					--- --能供玩游戏的座位数
	t.nBuyMin =tConfig.nBuyMin or (t.nBigBlind*10)		--- --最小买入
	t.nBuyMax =tConfig.nBuyMax or (t.nBuyMin*20)		--- --最大买入
	t.nOperateTime=15									--- --操作最大时间,单位:秒 (通常为10)

	t.nPotSum =0										--- --底池总额(已押筹码总额)
	t.arrPool={}										--- --底池,例如:{100,200,250}
	t.arrCommunityCards={}								--- --公共牌
	t.nStage =0											--- --当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	t.nClubId=nil										--俱乐部id
	t.nClubIdOfCorrect=nil								--经过校正后的ClubId (大厅统一用0表示)

	t.nItemId =nil										--使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	t.nGoldType =nil									-- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)

	--本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	t.isConfigNotSet =true									---
	t.tDeZhouConfigOption ={arrCapacity={},arrConfig={}}	--- --桌子可选配置(主播有)
	t.isPause =false										--- --是否设置了暂停 true:是  false:否		 	
	t.sPaiJuId =""											--- --牌局id
	t.nJuShu =0												--- --当前局数
	t.nTimeStart =0											--- -- >0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	t.nBankerPos=nil										--- --庄家位置

	t.tPosToPlayerSeatUser={}								--- --玩家席用户
	t.arrUsers ={}											--本桌子所有用户(nUserId作索引)
	t.arrStandUpUsers = {}                                      -- 站起玩家的信息,需要记录牌桌上用户的历史信息

	t.isReporting=false										--一个标志位,确保不会重复执行
	t.tOverViewCatch ={nUpdateTime=0,tOverViewRsp=nil}		--牌桌总览缓存

	t.isTableStart=false	   								--牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	t.isAutoNext=false										--下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始(前端判断>=2人时才给房主显示该按钮)

	t.tCountDown={nBeginStamp=0,nLong=0}					--os.time()-nBeginStamp <nLong时，表示倒计时开始中
	t.tPause ={nBeginStamp=0,nLong=0}						--os.time()-nBeginStamp <nLong时，表示暂停中
	t.tTableConfig =nil
	t.tInsurInfo=nil										--存放保险阶段信息
	t.isCanSeeAllHoleCard=false								--是否能看到其他玩家底牌(亮牌后为true)

	t.nGameId =nil											--德州玩法125:正常玩法 126:奥哈马玩法
	t.arrChat={}											--表情价格表
	t.tAlg =tAlg

	t.nElapsedStatus =0										--桌子当前计时状态 0正常 1暂停

	t.tUserIdBanEnter={}									--禁止进入该桌子的玩家id (被后台踢出该牌桌的玩家)


	--比赛桌新增状态
	t.tUserIdToRank ={}						--玩家排名
	t.nMttCnt=0								--比赛总玩家数
	t.nBlindUpTimeSt=0						--升盲时间戳
	t.nChipAv=0								--平均筹码
	t.nNextAssignTime=nil					--下一次系统分配桌子时的 时间戳
	t.nEventId=nil							--赛事id
	t.nKeepTime = 0
	t.isForceBlind = false
	return t
end

function Table:GameId()
	return self.nGameId
end

function Table:ToDoReport()
	if self.isReporting then return end
	self.isReporting =true
	self.Timer:DelayCall(60*1000,self.Report,self)
end

function Table:Report()
	self.Timer:DelayCall(60*1000,self.Report,self)
	local isHaveUser =false
	for _,v in pairs(self.arrUsers) do
		isHaveUser =true
		break
	end
	self:SendToCenterServ("UserCnt_Report",{isHaveUser=isHaveUser}) 
end


function Table:_GetProtoArrUsers(nUserId)
	local arr ={}
	for _,v in pairs(self.tPosToPlayerSeatUser) do
		local isCanSeeHoleCard =(v.nUserId ==nUserId and v.isShowHoleCard)
		isCanSeeHoleCard =isCanSeeHoleCard or self.isCanSeeAllHoleCard
		local item =self:_GetProtoUser(v,isCanSeeHoleCard)
		table.insert(arr,item)
	end
	return arr
end

function Table:_GetProtoUser(tUser,isCanSeeHoleCards)
	--玩家信息
	local DeZhouUser ={}
	DeZhouUser.nUserId=tUser.nUserId 				--玩家ID
	DeZhouUser.nSitId=tUser.nSitId			 		--座位号
	DeZhouUser.sFaceId=tUser.sFaceId 				--头像url
	DeZhouUser.sName=tUser.sName	 				--昵称
	DeZhouUser.nSex=tUser.nSex	     				--性别 0:男 1:女
	DeZhouUser.nBalance=tUser.nBalance				--余额
	DeZhouUser.isBanker=tUser.isBanker							--是否为庄; true:是 ,false:否
	DeZhouUser.arrHoleCards=_CopyArr(tUser.arrHoleCards or {})  --底牌(值为0的牌，显示牌背,表示还没亮牌)
	DeZhouUser.nCardType=tUser.nCardType						--牌型(见本文件头部"牌型定义")
	DeZhouUser.nBet =tUser.nBet			 						--玩家当轮当前下注数目(0时不要显示)
	DeZhouUser.nStatus=tUser.nStatus		 					--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
	DeZhouUser.isAuto =tUser.isAuto								--是否托管中
	DeZhouUser.sShopAcc =tUser.sShopAccount						--第三方用户ID
	DeZhouUser.isAndroid =tUser.isAndroid or false  			--是否机器人
	DeZhouUser.nWinRate=tUser.nWinRate or -1					--胜率
	DeZhouUser.nPlayCnt=tUser.nPlayCnt or 0					--已玩局数
	DeZhouUser.nTotalWinGold = tUser.nLoseAmount or 0
	if not isCanSeeHoleCards then
		_ZeroArr(DeZhouUser.arrHoleCards)
		DeZhouUser.nCardType=0
	end

	--剩余可操作(思考)时间
	DeZhouUser.nOpTimeRemain =tUser.nOpLong -(os.time() -tUser.nGetRightTime) 
	DeZhouUser.nDelay =tUser.nDelay or 0
	if tUser.nStatus ~= UserStatus.nThinking or DeZhouUser.nOpTimeRemain<0 then
		DeZhouUser.nOpTimeRemain=0
		DeZhouUser.nDelay =0
	end
	
	local tRInfo =tUser.tRetainInfo
	if tRInfo then
		DeZhouUser.nRetain=	tRInfo.nLen -(os.time() -tRInfo.nStartTime)
		DeZhouUser.nRetain =math.max(0,DeZhouUser.nRetain)
	end
	return DeZhouUser
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

function Table:IsFullCapacity()
	local nSeatUserCnt =0
	for _,v in pairs(self.tPosToPlayerSeatUser) do
		nSeatUserCnt =nSeatUserCnt+1
	end
	return (self.nCapacity ==nSeatUserCnt)
end

--匹配房场次id. 非匹配房返回nil
function Table:MatchRoomId()
	if self.nTableType ==PublicDefine.TableType.nMatch then
		return self.nRoomId 
	end
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

--速度貌似要优化
function Table:IsPlayerSeatUser(nUserId)
	for _,v in pairs(self.tPosToPlayerSeatUser) do
		if v.nUserId ==nUserId then
			return v
		end
	end
end

function Table:_GetLiveLastConfig(nUserId)
	local nConfigId = 1
	local nCapacity = 6
	local nIntervalLev =1
	return nConfigId,nCapacity,nIntervalLev
end

function Table:Get_User_UnLockGold(nUserId)
	if not self:IsUseCredit() then	--非积分房
		return tPubUser.Get_User_UnLockGold(nUserId,self.nItemId)
	end
	local tUser =self.arrUsers[nUserId]
	if tUser then
		return tUser.nGold
	end
	return 0
end

function Table:_ReSetTable()
	--重置桌子一些状态
	self.nPotSum =0								--底池总额(已押筹码总额)
	self.arrPool={}								--底池,例如:{100,200,250}
	self.arrCommunityCards={}					--公共牌
	self.tInsurInfo=nil							--保险相关信息
	self.isCanSeeAllHoleCard=false
	self.potUsers={}								--底池,例如:{100,200,250}
end

function Table:_ReSetSeatUser()
	for _,item in pairs(self.tPosToPlayerSeatUser) do
		item.isBanker=false		 		--是否为庄; true:是 ,false:否
		item.arrHoleCards={}	 		--底牌(值为0的牌，显示牌背,表示还没亮牌)
		item.nCardType=0		 		--牌型(见本文件头部"牌型定义")
		item.nBet =0			 		--玩家当轮当前下注数目(0时不要显示)
		item.nStatus=UserStatus.nLooker	--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
		item.nGetRightTime=0			--最近获得操作权时的时间戳
		item.tOperation=nil				--当前自己可操作信息(自己为思考状态时有)
		item.tPreOpOption=nil 			--自己当前可预操作选项
		item.nChipBuy =0				--筹码增加值
		item.isAuto =false
		item.nWinRate =-1
		item.nInsureStatus = 0
	end
end

--通知玩家金币变化
function Table:_NotifyGoldChange(tUser)
	local nGold =self:Get_User_UnLockGold(tUser.nUserId)
	local DeZhouGoldNotify={}
	DeZhouGoldNotify.nGold = publicApi.DealFloat(publicApi.Floor_2(nGold))
	self:SendToUser(tUser.nUserId,"ClubDeZhouGoldNotify",DeZhouGoldNotify)
end

function Table:NotifyGoldChange_gold(tJsonData)
	local nUserId = tJsonData.nUserId
	local nGold = tJsonData.nGold
	local DeZhouGoldNotify={}
	DeZhouGoldNotify.nGold = publicApi.DealFloat(publicApi.Floor_2(nGold))
	self:SendToUser(nUserId,"ClubDeZhouGoldNotify",DeZhouGoldNotify)
end

--下注
function Table:_DoBet(tUser,nBet)
	tUser.nBalance=tUser.nBalance -	nBet --余额
	tUser.nBet =tUser.nBet +nBet		 --玩家当轮当前下注数目(0时不要显示)
	self.nPotSum =self.nPotSum +nBet
end

--获取所有玩家的底牌信息(一个辅助函数)
function Table:_GetProtoUsersHoleCard(nCntOfNewAdd,nPosToSend)
	local function _FrontCards(arrCards,nFrontCnt) 			--一个辅助函数,返回arrCards的前n个牌
		local arr={}
		for i=1,nFrontCnt do
			if arrCards[i] then
				table.insert(arr,arrCards[i])
			end
		end
		return arr
	end
	local function _GetHoleCardInfo(tSeatUser,nPosToSend)	--一个辅助函数
		local arrHoleCards =tSeatUser.arrHoleCards or {}
		if #arrHoleCards ==0 then
			return 
		end
		if tSeatUser.nStatus ==UserStatus.nFold and tSeatUser.nSitId ~=nPosToSend then	--看不到别人弃牌时的牌(但自己的可以)
			return
		end
		local _,nCardType =self.tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,#self.arrCommunityCards-nCntOfNewAdd))
		local _,nCardTypeA =self.tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,3))	--与前3个公共牌组合成的牌型
		local _,nCardTypeB =self.tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,4))	--与前4个公共牌组合成的牌型
		local _,nCardTypeC =self.tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,5))	--与前5个公共牌组合成的牌型
		local UserHoleCard ={}
		UserHoleCard.nPos=tSeatUser.nSitId			--座位号
		UserHoleCard.arrHoleCards=arrHoleCards		--底牌
		UserHoleCard.nCardType=nCardType 			--新增公共牌前的牌型
		UserHoleCard.arrCardType ={nCardTypeA,nCardTypeB,nCardTypeC} 
		return UserHoleCard
	end
	local arrRlt ={}
	for _,tSeatUser in pairs(self.tPosToPlayerSeatUser) do
		local tHoleCardInfo =_GetHoleCardInfo(tSeatUser,nPosToSend)
		if tHoleCardInfo then
			table.insert(arrRlt,tHoleCardInfo)
		end
	end
	return arrRlt
end

function Table:_GetProtoInsurPaneData()
	if not self.tInsurInfo then
		return {}
	end
	if self.tInsurInfo.isEnd then
		return {}
	end
	local nElapse =os.time() -self.tInsurInfo.nTime
	local nRemain =self.tInsurInfo.nLong -nElapse
	nRemain =math.max(nRemain,0)
	for _, v in ipairs(self.tInsurInfo.arrInsurPanelData) do
		v.nSeconds=nRemain
	end
	return self.tInsurInfo.arrInsurPanelData
end

function Table:GetScenceByUserId(nUserId)
	local DeZhouScence={}
	DeZhouScence.nSmallBlind=self.nSmallBlind						--小盲注数额
	DeZhouScence.nBigBlind=self.nBigBlind							--大盲注数额(通常等于:小盲注x2)
	DeZhouScence.nZhuaTou = self.nZhuaTou
	DeZhouScence.nPreAnte = self.nPreAnte
	DeZhouScence.nCapacity=self.nCapacity							--桌子座位数(6或9)
	DeZhouScence.nOperateTime=self.nOperateTime						--操作最大时间,单位:秒 (通常为10)
	DeZhouScence.nPotSum =self.nPotSum								--底池总额(已押筹码总额)
	DeZhouScence.arrPot =_CopyArr(self.arrPool)						--已收归的各底池数额(池数量:>=0)
	DeZhouScence.arrCommunityCards=_CopyArr(self.arrCommunityCards)	--公共牌(最多5个牌)
	DeZhouScence.nStage =self.nStage								--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	DeZhouScence.isConfigNotSet =self.isConfigNotSet
	DeZhouScence.nLiveUserId =self.nLiveUserID
	DeZhouScence.isPause =self.isPause
	DeZhouScence.nRoomId=self:MatchRoomId() or -1
	DeZhouScence.arrUsers=self:_GetProtoArrUsers(nUserId)			--座位上的玩家
	DeZhouScence.tTableConfig= tBase.DeepCopy(self.tTableConfig)
	DeZhouScence.tTableConfig.sPassWord = ""
	local nTableCost = DeZhouScence.tTableConfig.nTableCost or "[]"
	DeZhouScence.tTableConfig.nTableCost = cjson.encode(nTableCost)
	DeZhouScence.arrCombinedCards={}
	DeZhouScence.nKeepTime = self.nKeepTime or 0
	-- DeZhouScence.nBuyMax = self.nBuyMax or 0
	DeZhouScence.potUsers = _CopyArr(self.potUsers or {})

	DeZhouScence.nLoseAmount = 0
	DeZhouScence.nPlayCnt = 0
	if self.arrStandUpUsers[nUserId] then
		local tStandUpUser = self.arrStandUpUsers[nUserId]
		DeZhouScence.nLoseAmount = tStandUpUser.nLoseAmount or 0
		DeZhouScence.nPlayCnt = tStandUpUser.nPlayCnt or 0
		local tUser = self.arrUsers[nUserId]   -- 盈利值和牌局数需要继承历史牌局的
		tUser.nLoseAmount = tStandUpUser.nLoseAmount or 0
		tUser.nPlayCnt = tStandUpUser.nPlayCnt or 0
		self.arrStandUpUsers[nUserId] = nil
	end

	local tUser =self:IsPlayerSeatUser(nUserId)
	if tUser and (not tUser.isAuto) then
		DeZhouScence.tOperation=tUser.tOperation					--当前自己可操作信息(自己为思考状态时有)
		DeZhouScence.tPreOpOption=tUser.tPreOpOption 				--自己当前可预操作选项
	end
	if tUser then
		DeZhouScence.arrCombinedCards=tUser.arrCombinedCards or tUser.arrHoleCards or {}
	end

	if nUserId==self.nLiveUserID then
		DeZhouScence.tDeZhouConfigOption =self.tDeZhouConfigOption
		local nConfigIdDefault,nCapacityDefault,nIntervalLevDefault =self:_GetLiveLastConfig(self.nLiveUserID)
		DeZhouScence.tDeZhouConfigOption.nConfigIdDefault=nConfigIdDefault 			--默认配置
		DeZhouScence.tDeZhouConfigOption.nCapacityDefault=nCapacityDefault			--默认人数
		DeZhouScence.tDeZhouConfigOption.nIntervalLevDefault =nIntervalLevDefault   --默认牌局间隔
	end

	local nCurrentTime =os.time()
	local nGameStartCountDown =nCurrentTime -self.tCountDown.nBeginStamp
	local nPauseCountDown =nCurrentTime -self.tPause.nBeginStamp
	if nGameStartCountDown<=self.tCountDown.nLong then
		DeZhouScence.nMSeconds =(self.tCountDown.nLong-nGameStartCountDown)*1000	--毫秒
	elseif nPauseCountDown<=self.tPause.nLong then
		DeZhouScence.nMSeconds =-1
		DeZhouScence.nPauseRemain =(self.tPause.nLong -nPauseCountDown) 			--秒
	else
		DeZhouScence.nMSeconds =0							-- >0:开局倒计时剩余时间(毫秒) -1:无限等待状态(因为主播设置了暂停) 其它:无意义
	end
	DeZhouScence.nGold = publicApi.DealFloat(publicApi.Floor_2(self:Get_User_UnLockGold(nUserId)))

	DeZhouScence.nClubId= self.nClubId
	DeZhouScence.sTableName= self.sTableName
	DeZhouScence.nCurrency =self.nItemId or 1					--本桌子使用的币种 1:金币 >1:俱乐部币

	DeZhouScence.isTableStart=self.isTableStart	   				--牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	DeZhouScence.isAutoNext=self.isAutoNext						--下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始(前端判断>=2人时才给房主显示该按钮)
	
	if tPublicRedis.HasClubTableMgrPower(self.nClubId,nUserId,self.nLiveUserID) then
		DeZhouScence.isCanCloseTable =true
	else
		DeZhouScence.isCanCloseTable =false
	end
	DeZhouScence.tInsurPanelData =self:_GetProtoInsurPaneData()
	
	DeZhouScence.nTableType =11					--俱乐部桌子
	
	DeZhouScence.nTableType =self.nRoomType		--10:大厅桌子 11:俱乐部桌子 12:比赛桌
	
	DeZhouScence.arrChat=self.arrChat
	DeZhouScence.nElapsedStatus=self.nElapsedStatus	--桌子当前计时状态 0正常 1暂停中
	DeZhouScence.sTableId =self.sTableId

	if self.nRoomType ==RoomType.nMtt then
		DeZhouScence.isMttUser = (tUser ~=nil)
		DeZhouScence.nEventId =self.nEventId
		DeZhouScence.tMInfo=self:_GetProtoMttRankInfo(nCurrentTime,nUserId)
		if self.nNextAssignTime then
			DeZhouScence.nAssignTime = math.max(self.nNextAssignTime -nCurrentTime,0)
		else
			DeZhouScence.nAssignTime =-1
		end
		self:Print("nAssignTime:%d,nUserId:%d isMttUser:%s",DeZhouScence.nAssignTime,nUserId,tostring(DeZhouScence.isMttUser))
	end
	self:Print("GetScenceByUserId_%d nElapsedStatus:%d nSmallBlind:%.1f",nUserId,self.nElapsedStatus,DeZhouScence.nSmallBlind)

	return DeZhouScence
end

--场景恢复
function Table:RecoverCenterScence(tScenc)
	self.nGroupId =tScenc.nGroupId or assert(false)							--分组id
	self.nRoomId  =tScenc.nRoomId or assert(false)							--房间id
	self.nTableType =tScenc.nTableType or assert(false)						--桌子类型
	self.nLiveUserID =tScenc.nLiveUserID or assert(false)					--主播ID
	self.sLiveID =tScenc.sLiveID or assert(false)							--主播ID(app)
	self.nSmallBlind=tScenc.nSmallBlind or assert(false) 					--小盲注数额
	self.nBigBlind=tScenc.nBigBlind or assert(false)						--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou = tScenc.nZhuaTou or 0               						--抓头数额
	self.nPreAnte = tScenc.nPreAnte	or 0				                    --前注
	self.nCapacity =tScenc.nCapacity or assert(false)						--能供玩游戏的座位数
	self.nBuyMin =tScenc.nBuyMin or assert(false) 							--最小买入
	self.nBuyMax =tScenc.nBuyMax or assert(false)							--最大买入
	self.nOperateTime=tScenc.nOperateTime or assert(false)					--操作最大时间,单位:秒 (通常为10)

	self.nPotSum =tScenc.nPotSum or assert(false)							--底池总额(已押筹码总额)
	self.arrPool=tScenc.arrPool or assert(false)							--底池
	self.arrCommunityCards=tScenc.arrCommunityCards or assert(false) 		--公共牌
	self.nStage =tScenc.nStage or assert(false)						 		--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中

	self.isConfigNotSet =tScenc.isConfigNotSet or false
	self.tDeZhouConfigOption =tScenc.tDeZhouConfigOption 					--桌子可选配置(主播有)
	self.isPause =tScenc.isPause or false									--是否设置了暂停 true:是  false:否		 	
	self.sPaiJuId =tScenc.sPaiJuId or assert(false)							--牌局id
	self.nJuShu =tScenc.nJuShu or assert(false)								--当前局数
	self.nBankerPos=tScenc.nBankerPos										--庄家位置
	self.nTimeStart =tScenc.nTimeStart or assert(false)						-->0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	self.nClubId =tScenc.nClubId											--俱乐部id
	self.nItemId =tScenc.nItemId											--使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	self.sTableName =tScenc.sTableName										--桌子名称
	self.nGoldType =tScenc.nGoldType										-- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)
	self.isTableStart=tScenc.isTableStart	   								--牌桌是否开始 true:是, false:否(房主需点击"开始牌局"才能开始)
	self.isAutoNext=tScenc.isAutoNext										--下局是否自动开始 true:是, false:房主点击 "开始游戏"才能开始(前端判断>=2人时才给房主显示该按钮)
	self.tTableConfig= tScenc.tTableConfig
	self.nRoomType =tScenc.nRoomType										--10:大厅桌子 11:俱乐部桌子

	self.arrChat =tScenc.arrChat or {}										--表情价格表
	self.nGameId =tScenc.nGameId
	self.nClubIdOfCorrect =tScenc.nClubIdOfCorrect							--经过了校正的nClubId (大厅统一用0表示)
	self.nElapsedStatus =tScenc.nElapsedStatus								--桌子当前计时状态 0正常 1暂停
	self.nNextAssignTime =tScenc.nNextAssignTime
	self.nEventId =tScenc.nEventId											--赛事id
	self.nKeepTime =tScenc.nKeepTime or 0								    --桌子时长
	self.tTableConfig.isForceBlind = self.tTableConfig.isForceBlind or false
	self.potUsers = tScenc.potUsers or {}

	if tScenc.nGameId ==Define.nGameId_Sc then
		self.tAlg =tScAlg
	end

	self.tPosToPlayerSeatUser ={}											--玩家席用户
	for _,v in ipairs(tScenc.arrPartInUser) do
		local item ={}
		item.nUserId=v.nUserId		     	--玩家ID
		item.nSitId=v.nSitId			 	--座位号
		item.sFaceId=v.sFaceId			 	--头像url
		item.sName=v.sName			 		--昵称
		item.nSex=v.nSex	    	 		--性别 0:男 1:女
		item.nBalance=v.nBalance		 	--余额
		item.sShopAccount =v.sShopAccount	--第三方用户ID
		item.isAndroid =v.isAndroid	 		--是否机器人
		item.nStatus=v.nStatus		 		--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 

		item.isBanker=v.isBanker		 	--是否为庄; true:是 ,false:否
		item.arrHoleCards=v.arrHoleCards	 --底牌(值为0的牌，显示牌背,表示还没亮牌)
		item.nCardType=v.nCardType		 	--牌型(见本文件头部"牌型定义")
		item.nBet =v.nBet			 		--玩家当轮当前下注数目(0时不要显示)
		item.nGetRightTime=v.nGetRightTime	--最近获得操作权时的时间戳
		item.isAuto=v.isAuto			 	--是否托管中
		item.tOperation=v.tOperation		--当前自己可操作信息(自己为思考状态时有)
		item.tPreOpOption=v.tPreOpOption 	--自己当前可预操作选项
		item.nOpLong =v.nOpLong
		self.tPosToPlayerSeatUser[v.nSitId] =item
	end
end

--来自中心服的消息处理
function Table:OnCenterMsgHandle(sCmd,tJsonData,nEcho)
	self:Print("OnCenterMsgHandle sCmd:%s",sCmd)
	
	if sCmd =="UserOust" then			--玩家被淘汰
		self:OnUserOust(tJsonData)
		return
	end
	if sCmd =="MttRank" then			--比赛排名筹码等信息更新
		self:OnMttRank(tJsonData)
		return
	end
	if sCmd =="NextAssignTime" then		--下一次比赛统一匹配时间
		self.nNextAssignTime =tJsonData.nNextAssignTime
		return
	end
	if sCmd =="RAWinRsp" then			--重购窗口打开回复
		self:OnRAWinRsp(tJsonData)			
		return
	 end
	 if sCmd =="RARsp" then				--重购回复
		self:OnRARsp(tJsonData)					
		return
	 end
	 if sCmd =="ChangeWRsp" then		--换桌回复或通知
		self:OnChangeWRsp(tJsonData)
		return
	 end


	if sCmd =="UserSitDownNotify" then			--有玩家坐下
		self:OnUserSitDownNotify(tJsonData)
		return
	end
	if sCmd =="UserStanpUpNotify" then			--有玩家离开座位
		self:OnUserStanpUpNotify(tJsonData)
		return
	end
	if sCmd =="GameStartNotify" then			--游戏开始通知
		self:OnGameStartNotify(tJsonData)
		return
	end
	if sCmd =="GetRightNotify" then
		self:OnGetRightNotify(tJsonData)		--有玩家获得操作权通知
		return
	end
	if sCmd =="OpNotify" then					--有玩家操作通知
		self:OnOpNotify(tJsonData)
		return
	end
	if sCmd =="DealNotify" then					--发牌通知
		self:OnDealNotify(tJsonData)
		return
	end
	if sCmd =="SettleNotify" then				--结算通知
		self:OnSettleNotify(tJsonData)
		return
	end
	if sCmd =="TableResetNotify" then			--桌子重置通知(发生在结算后)
		self:OnTableResetNotify(tJsonData)
		return
	end
	if sCmd =="ToStartNotify" then				--开始倒计时通知
		self:OnToStartNotify(tJsonData)
		return
	end
	if sCmd =="TableCloseNotify" then			--桌子关闭通知
		self:OnTableCloseNotify(tJsonData)
		return
	end
	if sCmd =="ShowCardNotify" then
		self:OnShowCardNotify(tJsonData)		--有玩家亮牌通知
		return
	end
	if sCmd =="DeZhouPreOpRsp" then				--预操作回复
		self:OnDeZhouPreOpRsp(tJsonData)
		return
	end
	if sCmd =="DeZhouFailNotify" then			--异常提示通知
		self:OnDeZhouFailNotify(tJsonData)
		return
	end
	if sCmd =="CancelAutoNotify" then			--有玩家取消托管通知
		self:OnCancelAutoNotify(tJsonData)
		return
	end
	if sCmd =="DeZhouChatNotify" then			--表情聊天通知
		self:OnDeZhouChatNotify(tJsonData)
		return
	end

	if sCmd =="DeZhouConfigNotify" then			--配置更改通知
		self:OnDeZhouConfigNotify(tJsonData)
		return
	end
	if sCmd =="DeZhouPauseRsp" then				--暂停回复
		self:OnDeZhouPauseRsp(tJsonData)
		return
	end
	if sCmd =="DeZhouKickUserRsp" then			--主播踢人回复
		self:OnDeZhouKickUserRsp(tJsonData)
		return
	end
	if sCmd =="DeZhouBalanceNotify" then		--玩家 筹码余额变动通知
		self:OnDeZhouBalanceNotify(tJsonData)
		return
	end
	if sCmd =="RSP_Kick_User" then				--后台踢人成功回复
		self:OnRSP_Kick_User(tJsonData)
		return
	end
	if sCmd =="OverviewRsp" then				--牌桌总览
		self:OnOverviewRsp(tJsonData)
		return
	end
	if sCmd =="TableStarNotify" then			--房主点击了"开始牌局" 通知
		self:OnTableStarNotify(tJsonData)
		return 
	end

	if sCmd =="AutoNextNotify" then				--房主点击了"开始游戏" 通知
		self:OnAutoNextNotify(tJsonData)
		return 
	end
	 if sCmd =="InsurNotify" then				--进入保险阶段通知
		self:OnInsurNotify(tJsonData)
		return 
	 end
	 if sCmd =="InsurDealNotify" then			--保险后发牌通知
		self:OnInsurDealNotify(tJsonData)
		return
	 end
	 if sCmd =="InsurBuyRsp" then				--保险购买回复
		self:OnInsurBuyRsp(tJsonData)
		return
	 end
	 if sCmd =="DelayRsp" then					--延时回复
		self:OnDelayRsp(tJsonData)
		return
	 end
	 if sCmd =="DelayNotify" then				--有人延时成功通知
		self:OnDelayNotify(tJsonData)
		return
	 end

	 if sCmd =="TakeOutRangeRsp" then		 	--筹码带出范围查看 回复
		self:OnTakeOutRangeRsp(tJsonData)
		return
	 end
	 if sCmd =="TakeOutRsp" then				--筹码带出回复
		self:OnTakeOutRsp(tJsonData)
		return
	 end

	 if sCmd =="RetainRsp" then					--'留座离桌'或'回到座位' 回复
		self:OnRetainRsp(tJsonData)
		return
	 end

	 if sCmd =="RetainNotify" then				--'留座离桌'或'回到座位' 生效通知
		self:OnRetainNotify(tJsonData)
		return
	 end

	 if sCmd =="CardOpenRsp" then				--翻牌回复
		self:OnCardOpenRsp(tJsonData)
		return
	 end
	 if sCmd =="WinRateNotify" then				--玩家胜率通知
		self:OnWinRateNotify(tJsonData)
		return
	 end
	 if sCmd =="ElapStatusUpdate" then			--桌子计时状态变化通知
		self:OnElapStatusUpdate(tJsonData)
		return
	 end
	 if sCmd =="ElapWarn" then					--桌子剩余时间告警通知
		self:OnElapWarn(tJsonData)
		return
	 end
	 if sCmd =="TakeInRsp" then					--带入请求回复
		self:OnTakeInRsp(tJsonData)
		return
	 end
	 if sCmd =="DeZhouBackToLobbyRsp" then					--返回大厅回复
		self:OnDeZhouBackToLobbyRsp(tJsonData)
		return
	 end
	 if sCmd =="HashListRsp" then					--可存证hash请求返回
		self:OnHashListRsp(tJsonData)
		return
	 end
	 if sCmd == "TableHashRsp" then
		self:OnTableHashRsp(tJsonData)
		return
	 end
	 if sCmd =="CloseUserDataNotify" then				--关闭用户数据统计通知
		self:OnCloseUserDataNotify(tJsonData)
		return
	 end
	 if sCmd =="TakeOutInfoRsp" then				--撤码查看请求
		self:OnTakeOutInfoRsp(tJsonData)
		return
	 end
	 if sCmd =="TakeOutSetRsp" then				--撤码设置
		self:OnTakeOutSetRsp(tJsonData)
		return
	 end
	 if sCmd =="TakeChipsOutRsp" then				--手动撤码
		self:OnTakeChipsOutRsp(tJsonData)
		return
	 end
	 if sCmd =="GoldNotify" then				--临时金币更新
		self:NotifyGoldChange_gold(tJsonData)
		return
	 end
	 if sCmd =="InsurBuyNotify" then				--保险购买通知
		self:OnInsurBuyNotify(tJsonData)
		return
	 end
	 if sCmd =="HandCardRsp" then				--看手牌请求
		self:OnHandCardRsp(tJsonData)
		return
	 end
	 if sCmd =="CutCardRsp" then				--切牌请求
		self:OnCutCardRsp(tJsonData)
		return
	 end
	 if sCmd =="CardOpNotify" then				--牌操作广播
		self:OnCardOpNotify(tJsonData)
		return
	 end
	 if sCmd =="TakeInNotify" then				--买入广播
		self:OnTakeInNotify(tJsonData)
		return
	 end
	 if sCmd =="DeZhouEnterNotify" then
		self:OnDeZhouEnterNotify(tJsonData)		--有玩家进入桌子通知
		return
	 end
	 if sCmd =="LeaveTableNotify" then
		self:OnLeaveTableNotify(tJsonData)		--有玩家进入桌子通知
		return
	 end
	 if sCmd =="BalanceChangeNotify" then
		self:OnBalanceChangeNotify(tJsonData)		--玩家离桌罚款以及收益通知
		return
	 end
	 if sCmd =="SyncUserInfor" then
		self:OnSyncUserInfor(tJsonData)		--同步用户信息通知
		return
	 end
	self:Print("sCmd:%s Not Handle",sCmd)
end


-- 同步用户信息, 当前主要是离桌罚款,用户罚款后重新进入牌桌时,需要同步盈利信息 因为用户未进行牌局,只会有罚款
function Table:OnSyncUserInfor(tJsonData)
	local tUser = self.arrStandUpUsers[tJsonData.nUserId]
	if tUser ~= nil then
		tUser.nLoseAmount = tJsonData.nLoseAmount or 0
	end
end

function Table:OnBalanceChangeNotify(tJsonData)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouRevenueNotify",{arrUserBalance = tJsonData})
	end
end

function Table:OnLeaveTableNotify(tJsonData)
	local nUserId = tJsonData.nNotifyUserId
	tPubUser.Send_User_Notice(nUserId, 3, tJsonData.sMsgToLobby)
	RecordDbr.WriteSystemNoticeNotic(nUserId, 1, tJsonData.nMsgType, tJsonData.sMsgToSystem)
end

function Table:OnDeZhouEnterNotify(tJsonData)
	for nUserId,_ in pairs(self.arrUsers) do
		if nUserId ~= tJsonData.nUserId then
			self:SendToUser(nUserId,"ClubDeZhouEnterNotify",{nName = tJsonData.sName})
		end
	end
end

--买入广播(中心服消息)
function Table:OnTakeInNotify(tJsonData)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouTakeInNotify",{nPos = tJsonData.nSitId, nBalance = tJsonData.nBalance})
	end
end

-- 看手牌请求
function Table:OnHandCardRsp(tJsonData)
	local tRsp = {}
	tRsp.nHands = tJsonData.nHandInfo
	tRsp.nRlt = tJsonData.nRlt
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouHandCardRsp",tRsp)
	self:OnBroadcastUserOperation(tJsonData.nUserId, GoldCReason.nLookHands)
end

-- 切牌请求
function Table:OnCutCardRsp(tJsonData)
	local tRsp = {}
	tRsp.nRlt = tJsonData.nRlt
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouCutCardRsp",tRsp)
end

-- 广播给其他用户该玩家的操作, 如看手牌等操作
function Table:OnBroadcastUserOperation(operationUserId, operationId)
	for nUserId, v in pairs(self.arrUsers) do
		if operationUserId ~= v.nUserId then -- 不需要通知本人
			self:SendToUser(v.nUserId,"ClubDeZhouUserOperationTypeNotify",{nPos = v.nSitId or 0, nName = v.sName, nOperationType = operationId})
		end
	end
end

--牌操作广播(中心服消息)
function Table:OnCardOpNotify(tJsonData)
	--广播给前端(桌子关闭)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouCardOpNotify",{nOpId = tJsonData.nOpId, nRemain = tJsonData.nRemain, nIndex = tJsonData.nIndex,
		nUserId = tJsonData.nUserId, nName = tJsonData.nName})
	end
end

-- 可存证hash请求返回
function Table:OnHashListRsp(tJsonData)
	local tRsp = {}
	tRsp.arrItem = tJsonData.list or {}
	tRsp.nMinId = tJsonData.nMinId
	tRsp.nRlt = 0
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouHashListRsp",tRsp)
end

-- Hash指定局牌序返回
function Table:OnTableHashRsp(tJsonData)
	local tRsp = {}
	tRsp.nCards = tJsonData.nCards or ""
	tRsp.nDetail = tJsonData.nDetail or ""
	tRsp.nRlt = tJsonData.nRlt or 0
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouHashCardRsp",tRsp)
end

-- 关闭用户数据统计通知
function Table:OnCloseUserDataNotify(tJsonData)
	local arr = tJsonData.arr
	for _, v in ipairs(arr) do
		self:Print("OnCloseUserDataNotify v.tProfit:%.2f nHandProfit:%.2f nCount:%.2f", v.tProfit, v.nHandProfit, v.nCount)
		local tRsp = {}
		tRsp.tProfit = v.tProfit or 0
		tRsp.nHandProfit = v.nHandProfit or 0
		tRsp.nCount = v.nCount or 0
		tRsp.nTakeIn = v.nTakeIn or 0
		if tRsp.nCount > 0 then
			tRsp.nHandProfit = publicApi.Floor_n(tRsp.nHandProfit/tRsp.nCount,2)
		end
		self:SendToUser(v.nUserId,"ClubDeZhouUserStaticRsp",tRsp)
	end
end

--来自中心服 换桌回复或通知
function Table:OnChangeWRsp(tJsonData)
	local tRsp={}
	tRsp.sTableId=tJsonData.sTableId		--新桌子id
	tRsp.nReason=tJsonData.nReason			--原因 0:换到人数较少的桌,继续比赛 1:换桌旁观
	--目标:单个用户
	if tJsonData.nUserId and tJsonData.nUserId>0 then
		self:SendToUser(tJsonData.nUserId,"ClubDeZhouTbChangeNotify",tRsp)
		self:OnUserLeave(tJsonData.nUserId)
		return
	end
	--目标:全体用户
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouTbChangeNotify",tRsp)
		self:OnUserLeave(nUserId)
	end
end

--来自中心服 玩家淘汰通知
function Table:OnUserOust(tJsonData)
	local nUserId =tJsonData.nUserId
	local tRsp={}
	tRsp.nRank=tJsonData.nRank			--名次
	tRsp.isAward=tJsonData.isAward		--是否获得奖励 true:是
	tRsp.nCoin=tJsonData.nCoin			--获得的金币奖励数
	tRsp.nTicket=tJsonData.nTicket		--获得的门票奖励数
	local isSuccee=self:SendToUser(nUserId,"ClubDeZhouOustNotify",tRsp)
	self:Print("Send UserOust %s,nUserId:%d nRank:%d",tostring(isSuccee),nUserId,tJsonData.nRank)
end

--来自中心服 比赛排名信息更新通知
function Table:OnMttRank(tJsonData)
	self.nMttCnt=tJsonData.nCnt							--比赛总玩家数
	self.nBlindUpTimeSt=tJsonData.nBlindUpTimeSt		--升盲时间戳
	self.nChipAv=tJsonData.nChipAv						--平均筹码
	self.tUserIdToRank ={}								--玩家排名
	for _,v in ipairs(tJsonData.arrRank) do
		self.tUserIdToRank[v.nUserId] =v.nRank
	end
	local nNowTimeSt =os.time()
	for nUserId,_ in pairs(self.arrUsers) do
		local tMInfo=self:_GetProtoMttRankInfo(nNowTimeSt,nUserId)
		local isSuccee=self:SendToUser(nUserId,"ClubDeZhouMInfoNotify",{tMInfo=tMInfo})
		self:Print("Send nBlindUpR %s, nUserId:%d nBlindUpR:%d",tostring(isSuccee),nUserId,tMInfo.nBlindUpR)
	end
end

function Table:_GetProtoMttRankInfo(nNowTimeSt,nUserId)
	local tMInfo ={}
	tMInfo.nRank=self.tUserIdToRank[nUserId] or 0		--当前玩家排名 		(0表示还没有排名)
	tMInfo.nCnt=self.nMttCnt							--比赛中玩家数
	tMInfo.nChipAv=self.nChipAv							--平均筹码
	if self.nBlindUpTimeSt>=0 then
		tMInfo.nBlindUpR=self.nBlindUpTimeSt -nNowTimeSt	--升盲剩余时间 秒,>=0
	else
		tMInfo.nBlindUpR=-1								--已达最大盲注级别
	end
	tMInfo.nBlindUpR =math.max(tMInfo.nBlindUpR,0)
	return tMInfo
end

--重购回复
function Table:OnRARsp(tJsonData)		
	--tJsonData.nRlt=0	--0:成功 其它:失败
	--tJsonData.nChip=0	--获得的筹码数
	--tJsonData.nUserId=nUserId
	local ClubDeZhouRARsp={}
	ClubDeZhouRARsp.nRlt=tJsonData.nRlt
	ClubDeZhouRARsp.nChip=tJsonData.nChip
	--回复给前端
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouRARsp",ClubDeZhouRARsp)
end

--重购窗口打开回复(中心服消息)
function Table:OnRAWinRsp(tJsonData)	
	--tJsonData.nRAFlag	--1:可重购 2:可增购 0:不能购
	--tJsonData.nCoin		--所需金币
	--tJsonData.nChip		--可换取的筹码
	--tJsonData.nCnt		--剩余换取次数
	--tJsonData.nLimitTime	--限时购买时间 秒;>=0时有效
	--tJsonData.nUserId
	local ClubDeZhouRANotify={}
	ClubDeZhouRANotify.nRAFlag=tJsonData.nRAFlag		--1:重购 2:增购
	ClubDeZhouRANotify.nCoin=tJsonData.nCoin			--所需金币
	ClubDeZhouRANotify.nChip=tJsonData.nChip			--可换取的筹码
	ClubDeZhouRANotify.nCnt=tJsonData.nCnt				--剩余换取次数
	ClubDeZhouRANotify.nLimitTime=tJsonData.nLimitTime	--限时购买时间 秒;>=0时有效
	--回复给前端
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouRANotify",ClubDeZhouRANotify)
end


--筹码带出范围查看回复(中心服消息)
function Table:OnTakeOutRangeRsp(tJsonData)
	local nUserId =tJsonData.nUserId
	self:Print("OnTakeOutRangeRsp,nUserId_%d",nUserId)
	local ClubDeZhouTakeOutRangeRsp ={}
	ClubDeZhouTakeOutRangeRsp.nGold =tJsonData.nGold			--当前身上金币
	ClubDeZhouTakeOutRangeRsp.nNowSelect=tJsonData.nNowSelect  --当前选择带出的筹码
	ClubDeZhouTakeOutRangeRsp.nMax =tJsonData.nMax				--最大可带出
	--回复给前端
	self:SendToUser(nUserId,"ClubDeZhouTakeOutRangeRsp",ClubDeZhouTakeOutRangeRsp)
end


--筹码带出回复(中心服消息)
function Table:OnTakeOutRsp(tJsonData)
	local nUserId =tJsonData.nUserId
	self:Print("OnTakeOutRsp,nUserId_%d",nUserId)

	local tUser =self.arrUsers[nUserId]
	if tUser and tJsonData.nRlt==0 then
		tUser.nIsAutoBuy =0
	end

	local ClubDeZhoTakeOutRsp ={}
	ClubDeZhoTakeOutRsp.nRlt=tJsonData.nRlt				--0:成功(下局开始时生效) 其他：失败
	--回复给前端
	self:SendToUser(nUserId,"ClubDeZhoTakeOutRsp",ClubDeZhoTakeOutRsp)
end

--'留座离桌'或'回到座位' 回复
function Table:OnRetainRsp(tJsonData)
	local nUserId =tJsonData.nUserId
	self:Print("OnRetainRsp,nUserId_%d",nUserId)
	--回复给前端
	self:SendToUser(nUserId,"ClubDeZhouRetainRsp",{nRlt=tJsonData.nRlt,nOp=tJsonData.nOp})
end

--翻牌回复
function Table:OnCardOpenRsp(tJsonData)
	local nUserId=  tJsonData.nUserId
	self:Print("OnCardOpenRsp,nUserId_%d",nUserId)

	local ClubDeZhouCardOpenRsp={}
	ClubDeZhouCardOpenRsp.nRlt=tJsonData.nRlt
	ClubDeZhouCardOpenRsp.arrCards=tJsonData.arrCards
	
	--回复给前端
	self:SendToUser(nUserId,"ClubDeZhouCardOpenRsp",ClubDeZhouCardOpenRsp)
	self:OnBroadcastUserOperation(nUserId, GoldCReason.nLookCard)
end


--'留座离桌'或'回到座位' 生效通知
function Table:OnRetainNotify(tJsonData)
	local nPos =tJsonData.nPos
	local nOp =tJsonData.nOp
	local nSeconds =tJsonData.nSeconds or 0
	self:Print("OnRetainNotify,nPos:%d nOp:%d nSeconds:%d",nPos,nOp,nSeconds)

	local tSeatUser =self.tPosToPlayerSeatUser[nPos] 
	if tSeatUser then
		if nOp ==0 then
			tSeatUser.tRetainInfo={nStartTime=os.time(),nLen=nSeconds}
		elseif nOp ==1 then
			tSeatUser.tRetainInfo=nil
		end
	end
	local ClubDeZhouRetainNotify ={}
	ClubDeZhouRetainNotify.nPos=nPos				--座位号
	ClubDeZhouRetainNotify.nOp=nOp					--0:留座离桌 1:回到座位
	ClubDeZhouRetainNotify.nSeconds=nSeconds		--留座离桌剩余时间 秒 (nOp为0时有效)
	
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouRetainNotify",ClubDeZhouRetainNotify)
	end
end


--有玩家坐下(中心服消息) ---
function Table:OnUserSitDownNotify(tJsonData)
	local tSeatUser =tJsonData.tUser
	if self.tPosToPlayerSeatUser[tSeatUser.nSitId] then
		self:ErrorHappen("OnUserSitDownNotify")
		return
	end
	local item ={}
	item.nUserId=tSeatUser.nUserId		     	--玩家ID
	item.nSitId=tSeatUser.nSitId			 	--座位号
	item.sFaceId=tSeatUser.sFaceId			 	--头像url
	item.sName=tSeatUser.sName			 		--昵称
	item.nSex=tSeatUser.nSex	    	 		--性别 0:男 1:女
	item.nBalance=tSeatUser.nBalance		 	--可用筹码余额
	item.sShopAccount =tSeatUser.sShopAccount	--第三方用户ID
	item.isAndroid =tSeatUser.isAndroid	 		--是否机器人
	item.nStatus=tSeatUser.nStatus		 		--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 

	item.isBanker=false		 				--是否为庄; true:是 ,false:否
	item.arrHoleCards={}	 				--底牌(值为0的牌，显示牌背,表示还没亮牌)
	item.nCardType=0		 				--牌型(见本文件头部"牌型定义")
	item.nBet =0			 				--玩家当轮当前下注数目(0时不要显示)
	item.nGetRightTime=0					--最近获得操作权时的时间戳
	item.nOpLong =self.nOperateTime
	item.nDelay =0							--是否有延时,0:没延时 >0:延时后的总时间
	item.isAuto=false			 			--是否托管中
	item.tOperation=nil						--当前自己可操作信息(自己为思考状态时有)
	item.tPreOpOption=nil 					--自己当前可预操作选项
	item.tRetainInfo=nil					--留座离桌的一些时间信息
	item.arrCombinedCards=nil
	item.nLoseAmount = tSeatUser.nLoseAmount or 0
	item.nPlayCnt = tSeatUser.nPlayCnt or 0

	self.tPosToPlayerSeatUser[item.nSitId] =item
	tBase.LogT("OnUserSitDownNotify", tSeatUser)
	self:Print("OnUserSitDownNotify nUserId_%d nSitId_%d",item.nUserId,item.nSitId)

	--同步可用金币(主要服务于匹配试玩房,其它情况以redis为准)
	local tUser =self.arrUsers[tSeatUser.nUserId]
	if tUser then
		tUser.nGold =tSeatUser.nUnLockGold
		self:_NotifyGoldChange(tUser)
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouUserSitDownNotify",{tUser=self:_GetProtoUser(item,false)})
	end
	--提示玩家弹窗补冲筹码
	if tSeatUser.isPop then
		self:_DeZhouTakeInRangeRsp(tSeatUser.nUserId)
	end

end

--有玩家离开座位(中心服消息) ---
function Table:OnUserStanpUpNotify(tJsonData)
	local nPos =tJsonData.nPos
	local tSeatUser =self.tPosToPlayerSeatUser[nPos]
	if not tSeatUser then
		self:ErrorHappen("OnUserStanpUpNotify")
		return
	end
	self.tPosToPlayerSeatUser[nPos]=nil
	self:Print("OnUserStanpUpNotify nUserId_%d nSitId_%d",tSeatUser.nUserId,nPos)

	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouUserStanpUpNotify",{nSitId=nPos})
	end
	local tUser =self.arrUsers[tSeatUser.nUserId]
	if not tUser then
		return
	end
	if tUser.isOffLine then
		self:Print("OnUserStanpUpNotify _SetLeaveTable nUserId_%d nSitId_%d",tSeatUser.nUserId,nPos)
		self:_SetLeaveTable(tSeatUser.nUserId, PublicDefine.LeaveTableType.nStandUp)
		return
	end
	tUser.nBuyTo=0					
	tUser.nIsAutoBuy=0
	tUser.nGold =tJsonData.nUnLockGold	--同步可用金币(主要服务于匹配试玩房,其它情况以redis为准)
	self:_NotifyGoldChange(tUser)
end

--主播踢人回复(中心服消息)---
function Table:OnDeZhouKickUserRsp(tJsonData)
	self:Print("OnDeZhouKickUserRsp nUserId_%d nRlt_%d",tJsonData.nUserId,tJsonData.nRlt)
	--回复给前端
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouKickUserRsp",{nRlt=tJsonData.nRlt})
end

--暂停回复(中心服消息)---
function Table:OnDeZhouPauseRsp(tJsonData)
	self:Print("OnDeZhouPauseRsp nUserId_%d isPause_%s",tJsonData.nUserId,tostring(tJsonData.isPause))
	self.isPause =tJsonData.isPause
	--回复给前端
	self:SendToUser(tJsonData.nUserId,"ClubDeZhouPauseRsp",{isPause=tJsonData.isPause})
end

--购买保险回复(中心服消息)
function Table:OnInsurBuyRsp(tJsonData)
	local nCode =tJsonData.nCode
	local nUserId =tJsonData.nUserId
	local nPlanId =tJsonData.nPlanId
	local nCost = tJsonData.nCost or 0
	-- self:Print("OnInsurBuyRsp nUserId:%d nCode:%d nPlanId:%d",nUserId,nCode,nPlanId)
	--回复给前端
	self:SendToUser(nUserId,"InsurBuyRsp",{nCode=nCode,nPlanId=nPlanId,nCost=nCost})
end

--有人买保险通知(中心服消息)
function Table:OnInsurBuyNotify(tJsonData)
	--广播给前端(桌子关闭)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouInsureNotify",{nCost = tJsonData.nCost, nPos = tJsonData.nSitId})
	end
end

--延时回复(中心服消息)
function Table:OnDelayRsp(tJsonData)
	local nRlt =tJsonData.nRlt
	local nUserId =tJsonData.nUserId
	local nDelayCost =tJsonData.nDelayCost
	local nOpLong =tJsonData.nOpLong or 0
	local nGetRightTime =tJsonData.nGetRightTime
	local isInsure = tJsonData.isInsure
	local nInsureDelayCount = tJsonData.nInsureDelayCount
	self:Print("OnDelayRsp nUserId:%d nRlt:%d nDelayCost:%.2f",nUserId,nRlt,nDelayCost)
	--回复给前端
	self:SendToUser(nUserId,"DelayRsp",{nRlt=nRlt,nDelayCost=nDelayCost,isInsure=isInsure,nOpLong=nOpLong})

	if nRlt~=0 then
		return
	end

	--状态同步
	local tSeatUser =self:IsPlayerSeatUser(nUserId)
	if not tSeatUser then
		return
	end
	tSeatUser.nGetRightTime =nGetRightTime
	tSeatUser.nOpLong =nOpLong
	tSeatUser.nDelay =nOpLong					--是否有延时,0:没延时 >0:延时后的总时间
	local tOperation =tSeatUser.tOperation
	if tOperation then
		if isInsure then
			tOperation.nInsureDelayCost = nDelayCost
		else
			tOperation.nDelayCost = nDelayCost
		end
	end
end

--有人延时成功通知(中心服消息)
function Table:OnDelayNotify(tJsonData)
	local nPos =tJsonData.nPos
	local nSeconds =tJsonData.nSeconds
	local nRemain =tJsonData.nRemain
	--广播给前端(桌子关闭)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DelayNotify",{nPos=nPos,nSeconds=nSeconds,nRemain=nRemain,isInsure=tJsonData.isInsure,resRemain=tJsonData.resRemain})
	end
end


--桌子关闭通知(中心服消息)---
function Table:OnTableCloseNotify(tJsonData)
	self:Print("OnTableCloseNotify,nReason:%d",tJsonData.nReason)
	
	self.Timer:KillAllTimer()

	--广播给前端(桌子关闭)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouFailNotify",{nCode=18})
	end 
	for nUserId,_ in pairs(self.arrUsers) do
		self:_SetLeaveTable(nUserId)
	end
	self.tInterFace.CloseTable(self.sTableId)
end

--玩家筹码余额变动通知(中心服消息,发生在主播更改配置后,重新调整带入) ---
function Table:OnDeZhouBalanceNotify(tJsonData)
	local tSeatUser =self.tPosToPlayerSeatUser[tJsonData.nPos]
	if not tSeatUser then
		self:ErrorHappen("OnDeZhouBalanceNotify")
		return
	end
	tJsonData.nBalance = publicApi.DealFloat(publicApi.Floor_2(tJsonData.nBalance))
	tSeatUser.nBalance = tJsonData.nBalance --玩家可用筹码余额更新
	self:Print("OnDeZhouBalanceNotify,nPos_%d nBalance_%.3f",tJsonData.nPos,tJsonData.nBalance)
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouBalanceNotify",{nPos=tJsonData.nPos,nBalance=tJsonData.nBalance})
	end 
end

--桌子配置变动通知(中心服消息,发生在主播更改配置后)---
function Table:OnDeZhouConfigNotify(tJsonData)
	local tConfigItem =tJsonData.tConfigItem
	self.nSmallBlind=tConfigItem.nSmallBlind 			--小盲注数额
	self.nBigBlind=tConfigItem.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou = tConfigItem.nZhuaTou or (self.nBigBlind*2)		--抓头数额
	self.nBuyMin =tConfigItem.nTakeInMin	 			--最小买入
	self.nBuyMax =tConfigItem.nTakeInMax				--最大买入
	self.nCapacity =tJsonData.nCapacity					--能供玩游戏的座位数
	self.isConfigNotSet=false
	self:Print("OnDeZhouConfigNotify,%s",cjson.encode(tJsonData))
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouConfigNotify",{nCapacity=tJsonData.nCapacity,tConfigItem=tConfigItem})
	end 
end

--有玩家亮牌通知(中心服消息)---
function Table:OnShowCardNotify(tJsonData)
	if not self.tPosToPlayerSeatUser[tJsonData.nPos] then
		self:ErrorHappen("OnShowCardNotify")
		return
	end
	self:Print("OnShowCardNotify,nPos_%d",tJsonData.nPos)
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouShowCardNotify",{nPos=tJsonData.nPos})
	end 
end

--有玩家取消托管通知(中心服消息)---
function Table:OnCancelAutoNotify(tJsonData)
	local tSeatUser =self.tPosToPlayerSeatUser[tJsonData.nPos]
	if not tSeatUser then
		self:ErrorHappen("OnCancelAutoNotify")
		return
	end
	tSeatUser.isAuto =false
	self:Print("OnCancelAutoNotify,nPos_%d",tJsonData.nPos)
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouCancelAutoNotify",{nPos =tJsonData.nPos})
	end
end

--表情聊天通知(中心服消息)---
function Table:OnDeZhouChatNotify(tJsonData)
	self:Print("OnDeZhouChatNotify,nSpeaker_%d,nChatId_%d",tJsonData.nSpeaker,tJsonData.nChatId)
	--广播给前端
	 local DeZhouChatNotify={}
	 DeZhouChatNotify.nSpeaker =tJsonData.nSpeaker		--聊天发起者座位号
	 DeZhouChatNotify.nChatId =tJsonData.nChatId		--表情id
	 DeZhouChatNotify.nTarget =tJsonData.nTarget	    --聊天对象(对谁聊天)
	 for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouChatNotify",DeZhouChatNotify)
	end
end

--异常提示通知(中心服消息)---
function Table:OnDeZhouFailNotify(tJsonData)
	local nUserId =tJsonData.nUserId
	local DeZhouFailNotify={}
	DeZhouFailNotify.nCode=tJsonData.nCode			--错误码,见错码定义
	DeZhouFailNotify.sErr=tJsonData.sErr			--错误提示
	DeZhouFailNotify.tRsp=tJsonData.tRsp			--最小最大带入(金币不足时有)
	DeZhouFailNotify.nLoseMaxAmount = tJsonData.nLoseMaxAmount
	self:Print("OnDeZhouFailNotify,nUserId_%d,nCode_%d",nUserId,tJsonData.nCode)
	--广播给前端
	if nUserId>0 then
		self:SendToUser(nUserId,"ClubDeZhouFailNotify",DeZhouFailNotify)
		return
	end
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouFailNotify",DeZhouFailNotify)
	end 
end

--预操作回复(中心服消息)---
function Table:OnDeZhouPreOpRsp(tJsonData)
	self:Print("OnDeZhouPreOpRsp,nUserId_%d,nRlt_%d",tJsonData.nUserId,tJsonData.nRlt)
	local nUserId =tJsonData.nUserId
	local DeZhouPreOpRsp={}
	DeZhouPreOpRsp.nRlt =tJsonData.nRlt		--0:成功 其它:错误码
	DeZhouPreOpRsp.nOpId =tJsonData.nOpId	--(成功时有效)请求的操作
	DeZhouPreOpRsp.isOn =tJsonData.isOn		--(成功时有效)操作状态 true:选中成功 false:取消成功
	DeZhouPreOpRsp.sErr=tJsonData.sErr		--(失败时有)失败提示
	self:SendToUser(nUserId,"ClubDeZhouPreOpRsp",DeZhouPreOpRsp)
end

--开始倒计时通知(中心服消息)---
function Table:OnToStartNotify(tJsonData)
	self:Print("OnToStartNotify,nMSeconds_%d",tJsonData.nMSeconds)
	if tJsonData.nMSeconds >0 then  				--倒计时时间(毫秒),并取消暂停(如果有)
		self.tCountDown ={nBeginStamp=os.time(),nLong=(tJsonData.nMSeconds/1000)}
		self.tPause ={nBeginStamp=0,nLong=0}
	elseif tJsonData.nMSeconds==0 then				--取消倒计时或暂停(如果有)
		self.tCountDown ={nBeginStamp=0,nLong=0}
		self.tPause ={nBeginStamp=0,nLong=0}
	elseif tJsonData.nMSeconds==-1 then				---1:取消倒计时(如果有),并暂停等待(等待时间为nPauseRemain)
		self.tCountDown ={nBeginStamp=0,nLong=0}	
		self.tPause ={nBeginStamp=os.time(),nLong=tJsonData.nPauseRemain}
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouToStartNotify",{nMSeconds=tJsonData.nMSeconds,nPauseRemain=tJsonData.nPauseRemain})
	end
end

--结算通知(中心服消息)---
function Table:OnSettleNotify(tJsonData)
	self:Print("OnSettleNotify")
	self.nStage =tJsonData.nStage
	self.arrPool =tJsonData.arrPot

	local tPartInUserId ={}
	for _,item in ipairs(tJsonData.arrUserForSlave) do
		local tSeatUser =self.tPosToPlayerSeatUser[item.nPos]
		if tSeatUser then
			tSeatUser.nBalance=item.nBalance		--同步当前可用筹码
			tSeatUser.nBet =0
			tSeatUser.nTempChips = item.nTempChips or 0
		end
		local tUser =self.arrUsers[item.nUserId]
		if tUser then
			tUser.nGold =item.nUnLockGold  			--同步可用金币(主要服务于匹配试玩房,其它情况以redis为准)
			tUser.nTempChips = item.nTempChips or 0
			tUser.nLoseAmount = item.nLoseAmount or 0
			tUser.nPlayCnt = item.nPlayCnt or 0
		end
		tPartInUserId[item.nUserId]=true
	end
	--广播给前端
	for nUserId, tUser in pairs(self.arrUsers) do
		local nCardOpenFee =tPartInUserId[nUserId] and tJsonData.nCardOpenFee or -1
		self:SendToUser(nUserId,"ClubDeZhouSettleNotify",{
			arrUsersWin=tJsonData.arrUsersWin,
			arrPot=tJsonData.arrPot,
			nCardOpenFee=nCardOpenFee,
			nTempChips=tUser.nTempChips,
			nPools=tJsonData.nPoolData,
			nTotalWinGold=tUser.nLoseAmount,
			nPlayCnt=tUser.nPlayCnt})
	end

	--提示玩家弹窗补冲筹码
	for _,item in ipairs(tJsonData.arrUserForSlave) do
		if item.isPop then
			self:_DeZhouTakeInRangeRsp(item.nUserId)
		end
	end

end

--桌子重置通知(中心服消息)---
function Table:OnTableResetNotify(tJsonData)
	self:Print("OnTableResetNotify")
	self.nStage =tJsonData.nStage
	self:_ReSetTable()
	self:_ReSetSeatUser()
	self.tOverViewCatch.nUpdateTime=0			--令牌桌回顾缓存过期,以便重新获取
	self.isAutoNext =tJsonData.isAutoNext		--下局是否自动开始

	--给前端同步一下可用金币
	for _,tSeatUser in pairs(self.tPosToPlayerSeatUser) do
		local tUser =self.arrUsers[tSeatUser.nUserId]
		if tUser then
			self:_NotifyGoldChange(tUser)
		end
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouTableResetNotify",{nNoUse=0,isAutoNext=tJsonData.isAutoNext})
	end
end

--后台踢人成功回复(中心服消息)--- 踢出牌桌
function Table:OnRSP_Kick_User(tJsonData)
	local nUserId =tJsonData.nUserId
	self:Print("OnRSP_Kick_User,%d",nUserId)
	self.tUserIdBanEnter[nUserId]=true
	if self.arrUsers[nUserId] then
		self:_KickOutToLobby(nUserId)
		return
	end
end

--踢出牌桌(通知前端令玩家返回大厅)
function Table:_KickOutToLobby(nUserId)
	self:SendToUser(nUserId,"ClubDeZhouFailNotify",{nCode=MsgCode.nKickToLobbyByAdmin,sErr="kick by backstage"})
	self:_SetLeaveTable(nUserId)
end

--有玩家操作通知(中心服消息)---
function Table:OnOpNotify(tJsonData)
	local tSeatUser =self.tPosToPlayerSeatUser[tJsonData.nPos]
	if not tSeatUser then
		self:ErrorHappen("OnOpNotify")
		return
	end
	tSeatUser.isAuto =tJsonData.isAuto
	tSeatUser.nStatus=tJsonData.nStatus
	tSeatUser.tOperation =nil
	tSeatUser.tPreOpOption=nil
	self:Print("OnOpNotify,nPos:%d nOp:%d",tJsonData.nPos,tJsonData.nOp)
	local nIsRoundBet = tJsonData.nIsRoundBet

	--预操作状态同步
	for _,v in ipairs(tJsonData.arrPreOpOption) do
		local tm =self.tPosToPlayerSeatUser[v.nSitId]
		assert(tm~=nil)
		tm.tPreOpOption =v.tPreOpOption
	end

	--下注状态同步
	local nOp =tJsonData.nOp
	local nCallOrRaiseChip =tJsonData.nCallOrRaiseChip
	if (nOp ==UserOp.nCall or nOp==UserOp.nRaise or nOp==UserOp.nAllIn) then
		self:_DoBet(tSeatUser,nCallOrRaiseChip)
	else
		nCallOrRaiseChip=0
	end
	if nOp == UserOp.nRaise and not nIsRoundBet then
		nOp = UserOp.nBet
	end

	--广播给前端
	local DeZhouOpNotify ={}
	DeZhouOpNotify.nPos =tJsonData.nPos					--座位号
	DeZhouOpNotify.nOp=nOp								---5:弃牌,  -1:AllIn, -2:看牌, -6:跟注, -3:加注 -7下注
	DeZhouOpNotify.isAuto =tJsonData.isAuto
	DeZhouOpNotify.nBet=nCallOrRaiseChip 		    	--跟注或加注时有效，表示具体的跟注\加注数值(>0)
	for nUserId,_ in pairs(self.arrUsers) do
		local tm =self:IsPlayerSeatUser(nUserId) or {}
		DeZhouOpNotify.tPreOpOption=tm.tPreOpOption
		self:SendToUser(nUserId,"ClubDeZhouOpNotify",DeZhouOpNotify)
	end
end

--有玩家获得操作权通知(中心服消息)---
function Table:OnGetRightNotify(tJsonData)
	local tSeatUser =self.tPosToPlayerSeatUser[tJsonData.nPos]
	if not tSeatUser then
		self:ErrorHappen("OnGetRightNotify")
		return
	end
	self:Print("OnGetRightNotify,nPos_%d",tJsonData.nPos)
	tSeatUser.tOperation=tJsonData.tOperation
	tSeatUser.tPreOpOption =nil
	tSeatUser.nGetRightTime=tJsonData.nGetRightTime
	tSeatUser.nOpLong =tJsonData.nOpLong
	tSeatUser.nStatus =tJsonData.nStatus
	tSeatUser.nDelay =0

	local tNeedOpenUser={}
	for _,nUseridN in ipairs(tJsonData.arrUserIdNeedOpenHodeCard) do
		local tSeatUser =self:IsPlayerSeatUser(nUseridN)
		if tSeatUser then
			tNeedOpenUser[nUseridN]=tSeatUser
		end
	end
	
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		if nUserId==tSeatUser.nUserId --[[and (not tSeatUser.isAuto)]] then
			local ClubDeZhouOperationNotify={nPos=tJsonData.nPos,tOperation=tSeatUser.tOperation}
			if tJsonData.isDoOpenHodeCard then	--如果因延迟看牌导致游戏开始时不能看底牌，则在第一次获得操作时公布底牌
				tSeatUser.isShowHoleCard =true
				local tHandCard ={}
				tHandCard.arrHoleCards=tSeatUser.arrHoleCards
				tHandCard.nCardType=tSeatUser.nCardType
				ClubDeZhouOperationNotify.tHandCard=tHandCard
			end
			self:SendToUser(nUserId,"ClubDeZhouOperationNotify",ClubDeZhouOperationNotify)
		elseif tNeedOpenUser[nUserId] then
			tNeedOpenUser[nUserId].isShowHoleCard=true
			local tHandCard ={}
			tHandCard.arrHoleCards=tNeedOpenUser[nUserId].arrHoleCards
			tHandCard.nCardType=tNeedOpenUser[nUserId].nCardType
			self:SendToUser(nUserId,"ClubDeZhouOperationNotify",{nPos=tJsonData.nPos,tHandCard=tHandCard})
		else
			self:SendToUser(nUserId,"ClubDeZhouOperationNotify",{nPos=tJsonData.nPos})
		end
	end 
end


--进入保险阶段通知(中心服消息)
function Table:OnInsurNotify(tJsonData)
	local tShowCard=tJsonData.tShowCard
	local tPoolChange=tJsonData.tPoolChange
	local arrInsurPanelData=tJsonData.arrInsurPanelData
	local arrWinRate =tJsonData.arrWinRate
	self.tInsurInfo={arrInsurPanelData=arrInsurPanelData,nTime=os.time(),nLong=Define.nInsureStageTime,isEnd=false}

	--标记所有玩家已亮牌
	if tShowCard then
		self.isCanSeeAllHoleCard=true
	end
	--底池同步
	if tPoolChange then
		local nPotSum =0
		self.arrPool=tPoolChange.arrPot
		for _,v in ipairs(self.arrPool) do
			nPotSum =nPotSum+v
		end
		self.nPotSum =nPotSum
	end
	self.potUsers = tJsonData.potUsers
	--同步座位席玩家状态
	for _,v in ipairs(tJsonData.arrUser) do
		local tSeatUser =self.tPosToPlayerSeatUser[v.nSitId]
		assert(tSeatUser~=nil)
		tSeatUser.tPreOpOption =v.tPreOpOption
		tSeatUser.nCardType =v.nCardType
		tSeatUser.nStatus =v.nStatus
		tSeatUser.nBet =0
		tSeatUser.nInsureStatus = v.nInsureStatus
	end
	--记录座位席玩家胜率
	for _,v in ipairs(arrWinRate) do
		local tSeatUser =self.tPosToPlayerSeatUser[v.nPos]
		assert(tSeatUser~=nil)
		tSeatUser.nWinRate =v.nWinRate
	end
	
	for _, v in ipairs(arrInsurPanelData) do
		local tElseUserHoleCard =v.tElseUserHoleCard
		if tElseUserHoleCard and (#tElseUserHoleCard.arrOuts + #tElseUserHoleCard.arrCard)==0 then
			v.tElseUserHoleCard =nil
		end
	end

	--广播给前端
	for nUserId, tUser in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"InsurNotify",{tShowCard=tShowCard,tPoolChange=tPoolChange,tInsurPanelData=arrInsurPanelData,
			arrWinRate=arrWinRate,potUsers=tJsonData.potUsers,nInsureStatus = tUser.nInsureStatus})
	end
end

---玩家胜率通知(中心服消息) 
function Table:OnWinRateNotify(tJsonData)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"WinRateNotify",{arrWinRate=tJsonData.arrWinRate})
	end
end

--桌子计时状态变化通知(中心服消息) 
function Table:OnElapStatusUpdate(tJsonData)
	self.nElapsedStatus =tJsonData.nElapsedStatus
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ElapsedStatusNotify",{nElapsedStatus=self.nElapsedStatus})
	end
end
--桌子剩余时间告警通知(中心服消息) 
function Table:OnElapWarn(tJsonData)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ElapWarnNotify",{nRemainTime=tJsonData.nRemainT})
	end
end
--带入请求回复(中心服消息)
function Table:OnTakeInRsp(tJsonData)
	local nUserId =tJsonData.nUserId
	local nRlt=tJsonData.nRlt
	local nBalance=tJsonData.nBalance
	local nTempChips = tJsonData.nTempChips
	local nCanOutChips = tJsonData.nCanOutChips
	local tSeatUser = self:IsPlayerSeatUser(nUserId)
	if tSeatUser and nRlt==0 and nBalance>-0.1 then
		nCanOutChips = publicApi.DealFloat(publicApi.Floor_2(nCanOutChips))
		tSeatUser.nBalance =nBalance				--同步当前可用筹码
		tSeatUser.nCanOutChips = nCanOutChips
		tSeatUser.nTempChips = nTempChips
	end
	if tSeatUser and nRlt==0 then
		tSeatUser.nBuyTo = tJsonData.nBuyTo
	end
	self:SendToUser(nUserId,"ClubDeZhoTakeInRsp",{nRlt=nRlt,nBalance=nBalance,nTempChips=nTempChips,nCanOutChips=nCanOutChips})
end

--返回大厅回复(中心服消息)
function Table:OnDeZhouBackToLobbyRsp(tJsonData)
	self:Print("OnDeZhouBackToLobbyRsp, nUserId%d nRlt:%d", tJsonData.nUserId, tJsonData.nRlt)
	local nUserId =tJsonData.nUserId
	local nRlt=tJsonData.nRlt
	local nBalance = tJsonData.nBalance or 0
	self:SendToUser(nUserId,"ClubDeZhouBackToLobbyRsp",{nRlt=nRlt})
	if nRlt == 0 and nBalance > 0 then
		--广播给前端
		for userId,_ in pairs(self.arrUsers) do
			if userId ~= nUserId then
				self:SendToUser(userId,"ClubDeZhouLeaveNotify",{nPos=tJsonData.nPos,nName=tJsonData.sName})
			end
		end
	end
end

--保险后发牌通知(中心服消息) 
function Table:OnInsurDealNotify(tJsonData)
	local nCard =tJsonData.nCard							--转牌或河牌
	local arrUsersCardType =tJsonData.arrUsersCardType		--发牌后，各玩家的牌型变化
	local arrChoices =tJsonData.arrChoices
	--同步状态
	self.tInsurInfo.isEnd=true								--self.tInsurInfo可能为nil (还没连上中心服,中途恢复场景，漏了这个)
	table.insert(self.arrCommunityCards,nCard)
	for _,v in ipairs(arrUsersCardType) do
		local tSeatUser =self.tPosToPlayerSeatUser[v.nPos]
		assert(tSeatUser~=nil)
		tSeatUser.nCardType =v.nCardType
		tSeatUser.arrCombinedCards =v.arrCombinedCards
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"InsurDealNotify",{nCard=nCard,arrUsersCardType=arrUsersCardType,tChoice=arrChoices,nHit=tJsonData.nHit})
	end
end


--发牌通知(中心服消息)---
function Table:OnDealNotify(tJsonData)
	--同步桌子状态
	self.nPotSum =tJsonData.nPotSum
	self.arrPool=tJsonData.arrPot
	self.potUsers = tJsonData.potUsers
	for _,nCard in ipairs(tJsonData.arrCardsNewAdd) do
		table.insert(self.arrCommunityCards,nCard)
	end
	if #self.arrCommunityCards>5 then
		self:ErrorHappen("OnDealNotify")
		return
	end
	self:Print("OnDealNotify,CommunityCard Cnt become:%d",#self.arrCommunityCards)
	--同步座位席玩家状态
	for _,v in ipairs(tJsonData.arrUser) do
		local tSeatUser =self.tPosToPlayerSeatUser[v.nSitId]
		assert(tSeatUser~=nil)
		tSeatUser.tPreOpOption =v.tPreOpOption
		tSeatUser.nCardType =v.nCardType
		tSeatUser.nStatus =v.nStatus
		tSeatUser.nBet =0
		tSeatUser.arrCombinedCards =v.arrCombinedCards
		tSeatUser.nInsureStatus = v.nInsureStatus
	end
	
	--广播给前端
	local function _GetUserHoleCard(nPosToSend)				--一个辅助函数
		if not tJsonData.isShowCard then
			return {}
		end
		local nNewAddCnt =#tJsonData.arrCardsNewAdd
		return self:_GetProtoUsersHoleCard(nNewAddCnt,nPosToSend)
	end
	local arrUsersHoleCardForLooker =_GetUserHoleCard(nil)	--给旁观玩家看的底牌(看不到弃牌玩家的底牌)

	local DeZhouDealNotify ={}
	DeZhouDealNotify.nPotSum =tJsonData.nPotSum				--底池总额(已押筹码总额)
	DeZhouDealNotify.arrPot =tJsonData.arrPot				--收归的各底池数额(池数量:>0),数组索引代表池ID,索引从1开始
	DeZhouDealNotify.arrCards=tJsonData.arrCardsNewAdd		--新增的公共牌
	DeZhouDealNotify.nCardType=0							--新增公共牌后，自己的牌型(见本文件头部"牌型定义")
	DeZhouDealNotify.tPreOpOption=nil 						--自己当前可预操作选项
	DeZhouDealNotify.arrUsersHoleCard={}					--各玩家的底牌(某些情况下非空数组);
	DeZhouDealNotify.potUsers = tJsonData.potUsers
	for nUserId,_ in pairs(self.arrUsers) do
		local tSeatUser =self:IsPlayerSeatUser(nUserId)
		if tSeatUser and tSeatUser.nStatus ~=UserStatus.nLooker then
			DeZhouDealNotify.arrUsersHoleCard =_GetUserHoleCard(tSeatUser.nSitId) --(看不到弃牌玩家的底牌信息,自己的除外)
			DeZhouDealNotify.nCardType =tSeatUser.nCardType
			DeZhouDealNotify.tPreOpOption=tSeatUser.tPreOpOption
			DeZhouDealNotify.arrCombinedCards =tSeatUser.arrCombinedCards
			DeZhouDealNotify.nInsureStatus = tSeatUser.nInsureStatus
		else
			DeZhouDealNotify.arrUsersHoleCard =arrUsersHoleCardForLooker
			DeZhouDealNotify.nCardType = 0
			DeZhouDealNotify.tPreOpOption=nil
			DeZhouDealNotify.arrCombinedCards ={}
		end
		self:SendToUser(nUserId,"ClubDeZhouDealNotify",DeZhouDealNotify)
	end
end

-- 从服做hash缓存
function Table:DealHashData(hashData)
	if #hashData == 2 then
		self.nHashData = hashData
	elseif #hashData > 0 then
		for _, v in ipairs(hashData) do
			table.insert(self.nHashData, v)
		end
		self.nHashDataAll = table.insert(self.nHashDataAll, table.remove(self.nHashData, 1))
		if #self.nHashDataAll > PublicDefine.HashMaxNum then
			table.remove(self.nHashDataAll, 1)
		end
	end
end

--游戏开始通知(中心服消息)---
function Table:OnGameStartNotify(tJsonData)
	--重置玩家信息
	self:_ReSetSeatUser()
	self:_ReSetTable()
	self.tOverViewCatch.nUpdateTime=0			--令牌桌回顾缓存过期,以便重新获取
	self.isTableStart = true

	--桌子状态同步
	self.nPotSum =tJsonData.nPotSum					--底池总额(已押筹码总额)
	self.arrPool={}									--底池,例如:{100,200,250}
	self.potUsers = {}
	self.arrCommunityCards={}						--公共牌
	self.nStage =tJsonData.nStage					--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中	
	self.sPaiJuId =tJsonData.sPaiJuId				--牌局id
	self.tTableConfig.sPaiJuId=tJsonData.sPaiJuId   --
	self.tTableConfig.tLeaveTableConfig = tJsonData.tLeaveTableConfig
	self.nJuShu =tJsonData.nJuShu					--当前局数
	self.nBankerPos=tJsonData.nBankerPos			--庄家位置
	self.nTimeStart =tJsonData.nTimeStart			-- >0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	self.nOperateTime =tJsonData.nOperateTime	--操作时间
	self.arrChat = tJsonData.arrChat

	self.nSmallBlind=tJsonData.nSmallBlind or self.nSmallBlind  --小盲注数额
	self.nBigBlind=tJsonData.nBigBlind or self.nBigBlind		--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou = tJsonData.nZhuaTou or (self.nBigBlind*2)	--抓头数额
	self.nBuyMin = tJsonData.nTakeInMin
	self.nBuyMax = tJsonData.nTakeInMax
	self:Print("OnGameStartNotify nZhuaTou:" .. tJsonData.nZhuaTou .. "self.nZhuaTou:" .. self.nZhuaTou)
	if self.tTableConfig then
		self.tTableConfig.nPreAnte =tJsonData.nPreAnte
		self.tTableConfig.nSmallBlind=self.nSmallBlind
		self.tTableConfig.nBigBlind=self.nBigBlind
		self.tTableConfig.nZhuaTou = self.nZhuaTou
		self.tTableConfig.nBuyMin = self.nBuyMin
		self.tTableConfig.nBuyMax = self.nBuyMax
	end

	local nSmallBlindPos =tJsonData.nSmallBlindPos 	--小盲位置
	local nBigBlindPos =tJsonData.nBigBlindPos 		--大盲位置
	local nZhuaTouPos = tJsonData.nZhuaTouPos
	local nPreAnte =tJsonData.nPreAnte			    --前注
	local nAcBetSmall=tJsonData.nAcBetSmall			--小盲位实际盲注(因存在筹码不足的情况，所以有此值)
	local nAcBetBig =tJsonData.nAcBetBig			--大盲位实际盲注(因存在筹码不足的情况，所以有此值)
	local nAcForceBet =tJsonData.nAcForceBet		--实际强盲下注
	self:Print("OnGameStartNotify  nOperateTime_%d  ",self.nOperateTime)

	local arrPosPartInSort={}
	local arrUserPartInSort ={}
	for _,v in ipairs(tJsonData.arrPartInUser) do
		local tSeatUser =self.tPosToPlayerSeatUser[v.nSitId]
		assert(tSeatUser~=nil)
		assert(tSeatUser.nUserId ==v.nUserId)
		tSeatUser.nBalance=v.nBalance		 		--余额
		tSeatUser.isBanker=v.isBanker				--是否为庄; true:是 ,false:否
		tSeatUser.arrHoleCards=v.arrHoleCards 		--底牌(值为0的牌，显示牌背,表示还没亮牌)
		tSeatUser.nCardType=v.nCardType				--牌型(见本文件头部"牌型定义")
		tSeatUser.nBet =v.nBet				 		--玩家当轮当前下注数目(0时不要显示)
		tSeatUser.nStatus=v.nStatus		 			--当前玩家状态, 0:等待操作权中 1:思考中 2:跟注 3:看牌 4:加注 5:AllIn 6:弃牌 7:旁观 
		tSeatUser.tPreOpOption=v.tPreOpOption		--自己当前可预操作选项
		tSeatUser.nChipBuy =v.nChipBuy
		tSeatUser.isShowHoleCard=v.isShowHoleCard  --是否现在就公布底牌给玩家
		tSeatUser.arrCombinedCards=nil
		tSeatUser.nInsureStatus = v.nInsureStatus
		tSeatUser.nBuyTo = v.nBuyTo
		tSeatUser.nLoseAmount = v.nLoseAmount or 0
		tSeatUser.nPlayCnt = v.nPlayCnt or 0
		local nAcPreAnteBet =v.nPreAnte or math.min(v.nBet,nPreAnte)	--玩家实际的前注下注(因为存在筹码不够的情况,下不全)
		table.insert(arrPosPartInSort,v.nSitId)
		table.insert(arrUserPartInSort,{nPos=v.nSitId,nTakeIn=v.nBalance,nBet=v.nBet-nAcPreAnteBet,nPreAnte=nAcPreAnteBet})	
		local tUser =self.arrUsers[v.nUserId]
		if tUser then
			tUser.nGold=v.nUnLockGold
			tUser.isAddFreeTimeIfStart=false	--试玩房有关状态 
			tUser.isPlay = true
			tUser.nSitId = v.nSitId
			self:_NotifyGoldChange(tUser)
		end
	end
	--广播给前端
	local arrInitUsersBet ={{nPos=nSmallBlindPos,nBet=nAcBetSmall},{nPos=nBigBlindPos,nBet=nAcBetBig}}
	if tJsonData.nForceBlindPos then
		table.insert(arrInitUsersBet,{nPos=tJsonData.nForceBlindPos,nBet=nAcForceBet})
	end
	if tJsonData.nZhuaTouPos then
		table.insert(arrInitUsersBet, {nPos=tJsonData.nZhuaTouPos,nBet=self.nZhuaTou})
	end
	if tJsonData.nHashData then
		-- self:DealHashData(tJsonData.nHashData)
	end

	local DeZhouStartNotify ={}
	DeZhouStartNotify.arrPosPartIn=arrPosPartInSort		--参与本局游戏的玩家座位号(每人发两个底牌,只能自己看到自己的底牌是啥) (发牌顺序按数组顺序)
	DeZhouStartNotify.nBankerPos=self.nBankerPos		--庄家座位号(头像显示标识:'D')
	DeZhouStartNotify.arrUsersBet=arrInitUsersBet 		--(大小盲)玩家下注
	DeZhouStartNotify.arrUserPartIn =arrUserPartInSort --参与本局游戏的玩家信息(发牌顺序按数组顺序)
	DeZhouStartNotify.sPaiJuId=self.sPaiJuId
	DeZhouStartNotify.nSmallBlind=self.nSmallBlind  	--小盲注数额
	DeZhouStartNotify.nBigBlind=self.nBigBlind			--大盲注数额(通常等于:小盲注x2)
	DeZhouStartNotify.nZhuaTou = self.nZhuaTou
	DeZhouStartNotify.nBlindUpR =tJsonData.nBlindUpR	--下一次升盲时间
	DeZhouStartNotify.nPreAnte =nPreAnte				--前注
	DeZhouStartNotify.arrChat=self.arrChat
	
	for _,tUser in pairs(self.arrUsers) do
		local tSeatUser =self:IsPlayerSeatUser(tUser.nUserId) or {}
		DeZhouStartNotify.nCardType =tSeatUser.nCardType or 0
		DeZhouStartNotify.tPreOpOption=tSeatUser.tPreOpOption or nil		
		DeZhouStartNotify.nTakeIn =tSeatUser.nBalance or 0
		DeZhouStartNotify.arrHoleCards =_CopyArr((tSeatUser.arrHoleCards or {}))
		DeZhouStartNotify.nChipBuy =tSeatUser.nChipBuy or 0
		DeZhouStartNotify.nInsureStatus = tSeatUser.nInsureStatus or 0
		DeZhouStartNotify.nTotalWinGold = tSeatUser.nLoseAmount or 0
		DeZhouStartNotify.nPlayCnt = tSeatUser.nPlayCnt or 0
		if (not tSeatUser.isShowHoleCard) and #DeZhouStartNotify.arrHoleCards>0 then
			_ZeroArr(DeZhouStartNotify.arrHoleCards)
			DeZhouStartNotify.nCardType=0
		end
		--self:Print("HoleCardCnt:%d nUserId:%d",#DeZhouStartNotify.arrHoleCards,tUser.nUserId)
		self:SendToUser(tUser.nUserId,"ClubDeZhouStartNotify",DeZhouStartNotify)
	end
end

--牌桌总览回复(来自中心服)
function Table:OnOverviewRsp(tData)
	self.tOverViewCatch.nUpdateTime =os.time()
	self.tOverViewCatch.tOverViewRsp =tData.tOverview
	self:SendToUser(tData.nUserId,"ClubDeZhouOverViewRsp",self.tOverViewCatch.tOverViewRsp)
end

--房主点击了"开始牌局" 通知(中心服消息)---
function Table:OnTableStarNotify(tData)
	self:Print("OnTableStarNotify")
	self.isTableStart=true
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouTableStartNotify",{isTableStart=true})
	end
end
--房主点击了"开始游戏" 通知 (中心服消息)---
function Table:OnAutoNextNotify(tJsonData)
	self:Print("OnAutoNextNotify")
	self.isAutoNext=true
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"ClubDeZhouAutoNextNotify",{isAutoNext=true})
	end
end


--use 用户请求处理
function Table:OnReqHandle(nUserId,strReq,tData)
	local tUser =self.arrUsers[nUserId]
	if not tUser then
		self:Print("Error, Can Not Find User_%d in Table",nUserId)
		return
	end
	--操作请求xx
	if strReq =="ClubDeZhouOpReq" then
		self:DeZhouOpReq(nUserId,tData)
		return
	end
	--预操作请求xx
	if strReq =="ClubDeZhouPreOpReq" then
		self:DeZhouPreOpReq(nUserId,tData)
		return
	end
	--站起请求(从玩家位置站起)xx
	if strReq =="ClubDeZhouStanpUpReq" then
		self:DeZhouStanpUpReq(nUserId,tData)
		return
	end
	--坐下请求(坐下到玩家位置)xx
	if strReq =="ClubDeZhouSitDownReq" then	
		self:DeZhouSitDownReq(nUserId,tData)
		return
	end
	--筹码买入范围查看请求xx
	if strReq =="ClubDeZhouTakeInRangeReq" then 
		self:DeZhouTakeInRangeReq(nUserId,tData)
		return
	end
	--筹码买入请求xx
	if strReq =="ClubDeZhoTakeInReq" then	
		self:DeZhoTakeInReq(nUserId,tData)
		return
	end
	--手动撤码
	if strReq =="ClubDeZhouTakeChipsOutReq" then
		self:DeZhouTakeOutReq(nUserId,tData)
		return
	end
	--撤码查看请求
	if strReq =="ClubDeZhouTakeOutInfoReq" then
		self:DeZhouTakeOutInfoReq(nUserId,tData)
		return
	end
	--撤码设置
	if strReq =="ClubDeZhouTakeOutSetReq" then
		self:DeZhouTakeOutSetReq(nUserId,tData)
		return
	end
	--返回大厅请求xx
	if strReq =="ClubDeZhouBackToLobbyReq" then 
		self:DeZhouBackToLobbyReq(nUserId,tData)
		return
	end
	--取消托管请求xx
	if strReq =="ClubDeZhouCancelAutoReq" then
		self:DeZhouCancelAutoReq(nUserId,tData)
		return
	end
	--房间设置 请求xx
	if strReq =="ClubDeZhouCofingReq" then
		self:DeZhouCofingReq(nUserId,tData)
		return
	end
	--Gm命令xxx
	if strReq =="ClubDeZhouGmReq" then
		self:DeZhouGmReq(nUserId,tData)
		return
	end
	--后台踢人xxx
	if strReq =="REQ_Kick_User" then
		self:REQ_Kick_User(nUserId,tData)
		return
	end
	--主播踢人请求
	if strReq =="ClubDeZhouKickUserReq" then
		self:DeZhouKickUserReq(nUserId,tData)
		return
	end
	--主播暂停请求xxx
	if strReq =="ClubDeZhouPauseReq" then
		self:DeZhouPauseReq(nUserId,tData)
		return
	end
	--来自db服的金币变化(充值)通知xx
	if strReq =="DbRechargeRsp" then
		self:_NotifyGoldChange(tUser)
		return
	end
	--表情聊天xxx
	if strReq =="ClubDeZhouChatReq" then
		self:_DeZhouChatReq(nUserId,tData)
		return
	end
	--牌局总览请求
	if strReq =="ClubDeZhouOverViewReq" then
		self:OverViewReq(nUserId,tData)
		return
	end
	--"开始牌局"请求 (房主使用)
	if strReq =="ClubDeZhouTableStartReq" then
		self:_TableStartReq(nUserId,tData)
		return
	end
	--"开始游戏" 请求 (房主使用)
	if strReq =="ClubDeZhouAutoNextReq" then
		self:_AutoNextReq(nUserId,tData)
		return
	end
	--保险购买请求
	if strReq =="InsurBuyReq" then	
		self:_InsurBuyReq(nUserId,tData)
		return
	 end
	 --延时请求
	 if strReq =="DelayReq" then
		self:_DelayReq(nUserId,tData)
		return
	 end
	 --头像信息
	 if strReq =="HeadInfoReq" then
		self:_HeadInfoReq(nUserId,tData)
		return
	 end
	 --带出范围查看请求
	 if strReq =="ClubDeZhouTakeOutRangeReq" then
		self:_ClubDeZhouTakeOutRangeReq(nUserId,tData)
		return
	 end
	 --带出请求
	 if strReq =="ClubDeZhoTakeOutReq" then
		self:_ClubDeZhoTakeOutReq(nUserId,tData)
		return
	 end
	 --'留座离桌'或'回到座位' 请求
	 if strReq =="ClubDeZhouRetainReq" then
		self:_ClubDeZhouRetainReq(nUserId,tData)
		return
	 end
	 --翻牌请求
	 if strReq =="ClubDeZhouCardOpenReq" then
		self:_ClubDeZhouCardOpenReq(nUserId,tData)
		return
	 end

	--重(增)购窗口打开 请求 <触发ClubDeZhouRANotify>
	if strReq =="ClubDeZhouRAWinReq" then
		self:Print("ClubDeZhouRAWinReq,nUserId_%d ",nUserId)
		self:SendToCenterServ("RAWinReq",{nUserId=nUserId}) 		--发送给中心服
		return
	end
	--换桌旁观 请求	<触发ClubDeZhouTbChangeNotify>
	if strReq =="ClubDeZhouChangeWReq" then
		self:Print("ClubDeZhouChangeWReq,nUserId_%d ",nUserId)
		self:SendToCenterServ("ChangeWReq",{nUserId=nUserId}) 		--发送给中心服
		return
	end
	--重(增)购 请求
	if strReq =="ClubDeZhouRAReq" then
		self:Print("ClubDeZhouRAReq,nUserId_%d ",nUserId)
		self:SendToCenterServ("RAReq",{nUserId=nUserId}) 			--发送给中心服
		return
	end
	--可存证hash请求
	if strReq =="ClubDeZhouHashListReq" then
		self:Print("ClubDeZhouHashListReq,nUserId_%d ",nUserId)
		local tSeatUser = self:IsPlayerSeatUser(nUserId)
		for _, v in pairs(self.tPosToPlayerSeatUser) do
			self:Print("ClubDeZhouHashListReq,  v nUserId_%d ", v.nUserId)
		end
		if not tSeatUser then
			local ClubDeZhouHashListRsp = {}
			ClubDeZhouHashListRsp.arrItem = {}
			ClubDeZhouHashListRsp.nMinId = 0
			ClubDeZhouHashListRsp.nRlt = 1
			self:SendToUser(nUserId,"ClubDeZhouHashListRsp", ClubDeZhouHashListRsp)
			return
		end
		self:SendToCenterServ("HashListReq",{nUserId = nUserId, nQueryCnt = tData.nQueryCnt, nMinId= tData.nMinId, sTableId = self.sTableId, sPaiJuId = self.sPaiJuId})		--发送给中心服
		return
	end
	if strReq == "ClubDeZhouHashCardReq" then
		local tSeatUser = self:IsPlayerSeatUser(nUserId)
		local nRlt = 0
		if not tSeatUser then
			nRlt = 1
		end
		if self.sPaiJuId == tData.sPaiJuId then
			nRlt = 2
		end
		if nRlt ~= 0 then
			local ClubDeZhouHashCardRsp = {}
			ClubDeZhouHashCardRsp.nDetail = ""
			ClubDeZhouHashCardRsp.nCards = ""
			ClubDeZhouHashCardRsp.nRlt = nRlt
			self:SendToUser(nUserId,"ClubDeZhouHashCardRsp", ClubDeZhouHashCardRsp)
		end
		self:SendToCenterServ("TableHashReq",{nUserId = nUserId, sPaiJuId = tData.sPaiJuId, sTableId = self.sTableId})		--发送给中心服
		return
		-- return nRlt, self.sTableId
	 end
	 --看手牌请求
	if strReq =="ClubDeZhouHandCardReq" then
		self:Print("ClubDeZhouHandCardReq,nUserId_%d ",nUserId)
		self:SendToCenterServ("HandCardReq",{nUserId=nUserId, sTableId = self.sTableId, sPaiJuId = self.sPaiJuId}) 			--发送给中心服
		return
	end
	--切牌请求
	if strReq =="ClubDeZhouCutCardReq" then
		self:Print("ClubDeZhouCutCardReq,nUserId_%d ",nUserId)
		-- if tData.nIndex == 0 or tData.nIndex >= 52 then
		-- 	self:SendToUser(nUserId,"ClubDeZhouCutCardRsp", {nRlt = 2})
		-- 	return
		-- end
		self:SendToCenterServ("CutCardReq",{nUserId=nUserId, nIndex = tData.nIndex, nIsStart = tData.nIsStart, sTableId = self.sTableId, sPaiJuId = self.sPaiJuId}) 			--发送给中心服
		return
	end
end


--后台踢人请求---
function Table:REQ_Kick_User(nUserId,tData)
	self:Print("REQ_Kick_User,nUserId_%d",nUserId)
	local nType = tData.nType or -1    		--1:立即踢出牌桌(令玩家返回大厅) 2:当局结束后踢出牌桌(令玩家返回大厅) 3:当局结束后强制站起
	local tSeatUser =self:IsPlayerSeatUser(nUserId)
	if tSeatUser then
		self:SendToCenterServ("REQ_Kick_User",{nUserId=nUserId,nType=nType})
		return
	end
	if (nType==1 or nType==2 or nType==5 or nType==6) then
		self:SendToCenterServ("REQ_Kick_User",{nUserId=nUserId,nType=nType})
	end
end

--
function Table:_HeadInfoReq(nUserId,tData)
	local nPos =tData.nPos
	self:Print("_HeadInfoReq,nUserId_%d nPos_%d",nUserId,nPos)
	
	local tSeatUser =self.tPosToPlayerSeatUser[nPos]
	if not tSeatUser then
		self:Print("Not Find SeatUser")
		return
	end
	local data = {nClubId = self.nClubId, nGameId = self.nGameId, nGoldType = self.nGoldType, nSmallBlind = self.nSmallBlind, nBigBlind = self.nBigBlind,
		nZhuaTou = self.nZhuaTou, nPreAnte = self.nPreAnte}
	local tInfo =tPublicRedis.GetUserTexaStatistic(tSeatUser.nUserId, data)
	local tUserInfo ={}
	local nUnLockGold =0
	local nMarkInfo
	if not tSeatUser.isAndroid then
		tUserInfo =tPubUser.GetAllUserInfo(tSeatUser.nUserId)
		nUnLockGold =self:Get_User_UnLockGold(tSeatUser.nUserId)
		nMarkInfo = tPubUser.GetUserMarkInfo(nUserId, tSeatUser.nUserId)
	else
		nUnLockGold =tSeatUser.nUnLockGold or math.random(1,10*self.nBuyMax)
		tSeatUser.nUnLockGold=nUnLockGold
	end

	local HeadInfoRsp ={}
	HeadInfoRsp.nUserId=tSeatUser.nUserId								 --玩家ID
	HeadInfoRsp.sFaceId=tSeatUser.sFaceId								 --头像url
	HeadInfoRsp.sName=tSeatUser.sName			 						--昵称
	HeadInfoRsp.nSex=tSeatUser.nSex	    								--性别 0:男 1:女
	HeadInfoRsp.nBalance=nUnLockGold									--余额(金币)
	HeadInfoRsp.sSigna=tUserInfo.sPersonality or ""						--签名 (""表示没签名)
	HeadInfoRsp.nVipLev=tonumber(tUserInfo.nVip or 0)					--vip等级
	HeadInfoRsp.nPlayCount=tInfo.nPlayCount								--总手数
	HeadInfoRsp.nProfit=tInfo.nProfitSum								--盈亏
	HeadInfoRsp.nJuShu =tInfo.nJuShu or 0								--局数
	HeadInfoRsp.nInpoolRate=0		 --入池率(值50即表示50%)
	HeadInfoRsp.nBFlopRaiseRate=0 	--翻前加注率(值50即表示50%)
	HeadInfoRsp.nAllInAndWinRate=0	--All in胜率(值50即表示50%)
	HeadInfoRsp.nWinRate = 0
	HeadInfoRsp.nQiPaiRate = 0
    HeadInfoRsp.nHandProfit = 0
	HeadInfoRsp.nTanPaiRate = 0
	HeadInfoRsp.nMarkText = (nMarkInfo and nMarkInfo.nText) or ""				--备注信息
	HeadInfoRsp.nMarkColorId = (nMarkInfo and nMarkInfo.nColorId) or 0				--备注颜色ID
	if tInfo.nPlayCount>0 then
		HeadInfoRsp.nInpoolRate=publicApi.Floor_n(100*tInfo.nInPoolCount/tInfo.nPlayCount,1)		 	--入池率(值50即表示50%)
		HeadInfoRsp.nBFlopRaiseRate=publicApi.Floor_n(100*tInfo.nRaiseCountBFlop/tInfo.nPlayCount,1) 	--翻前加注率(值50即表示50%)
		HeadInfoRsp.nWinRate = publicApi.Floor_n(100*tInfo.nWinCount/tInfo.nPlayCount,1)
		HeadInfoRsp.nQiPaiRate = publicApi.Floor_n(100*tInfo.nQiPaiCount/tInfo.nPlayCount,1)
		HeadInfoRsp.nHandProfit = publicApi.Floor_n(tInfo.nHandProfit/tInfo.nPlayCount,2)
		HeadInfoRsp.nTanPaiRate = publicApi.Floor_n(100*tInfo.nReachShowdown/tInfo.nPlayCount,1)
	end
	if tInfo.nAllInCount > 0 then
		HeadInfoRsp.nAllInAndWinRate = publicApi.Floor_n(100*tInfo.nAllInAndWinCount/tInfo.nAllInCount,1)
	end

	self:SendToUser(nUserId,"HeadInfoRsp",HeadInfoRsp)
end


--表情聊天---
function Table:_DeZhouChatReq(nUserId,tData)
	self:Print("_DeZhouChatReq,nUserId_%d nChatId:%d",nUserId,tData.nChatId)
	local DeZhouChatReq ={}
	DeZhouChatReq.nUserId =nUserId
	DeZhouChatReq.nChatId =tData.nChatId
	DeZhouChatReq.nTarget =tData.nTarget
	DeZhouChatReq.nType =tData.nType
	DeZhouChatReq.sTableId = self.sTableId
	DeZhouChatReq.sPaiJuId = self.sPaiJuId
	self:SendToCenterServ("DeZhouChatReq",DeZhouChatReq)
end

--"开始牌局"请求 (房主使用)
function Table:_TableStartReq(nUserId,tData)
	self:Print("_TableStartReq,nUserId_%d",nUserId)
	local isHavePower =tPublicRedis.HasClubTableMgrPower(self.nClubId,nUserId,self.nLiveUserID)
	if not isHavePower then
		self:Print("NoPower,nLiveUserID is:%d",self.nLiveUserID)
		return
	end
	self:SendToCenterServ("TableStartReq",{nUserId=nUserId}) 
end
--"开始游戏" 请求 (房主使用)
function Table:_AutoNextReq(nUserId,tData)
	self:Print("_AutoNextReq,nUserId_%d",nUserId)
	local isHavePower =tPublicRedis.HasClubTableMgrPower(self.nClubId,nUserId,self.nLiveUserID)
	if not isHavePower then
		self:Print("NoPower,nLiveUserID is:%d",self.nLiveUserID)
		return
	end
	self:SendToCenterServ("AutoNextReq",{nUserId=nUserId}) 
end

--购买保险请求
function Table:_InsurBuyReq(nUserId,tData)
	self:Print("_InsurBuyReq,nUserId_%d",nUserId)
	local arrOuts,nBuy ={},{}
	for _,v in ipairs(tData.arrOuts or {}) do
		table.insert(arrOuts,v)
	end
	for _,v in ipairs(tData.nBuy or {}) do
		table.insert(nBuy,{nPoolId = v.nPoolId, nPlanId = v.nPlanId})
	end
	self:SendToCenterServ("InsurBuyReq",{nUserId=nUserId,nPlanId=tData.nPlanId,arrOuts=arrOuts,nBuy=nBuy, sTableId = self.sTableId, sPaiJuId = self.sPaiJuId})
end
--延时请求
function Table:_DelayReq(nUserId,tData)
	self:Print("_DelayReq,nUserId_%d",nUserId)
	self:SendToCenterServ("DelayReq",{nUserId=nUserId,isInsure=tData.isInsure, sTableId = self.sTableId, sPaiJuId = self.sPaiJuId})
end

--牌桌总览请求
function Table:OverViewReq(nUserId,tData)
	self:Print("OverViewReq,nUserId_%d",nUserId)
	self:SendToCenterServ("OverViewReq",{nUserId=nUserId,nNoUse=tData.nNoUse}) 

	--[[
	--从服做缓存，加过期时间或按局数过期
	local nNow =os.time()
	if (nNow -self.tOverViewCatch.nUpdateTime) >=2 then
		self:SendToCenterServ("OverViewReq",{nUserId=nUserId}) 
		return 
	end
	self:SendToUser(nUserId,"ClubDeZhouOverViewRsp",self.tOverViewCatch.tOverViewRsp)
	]]
end



--主播暂停请求 (分游戏中请求暂停，非游戏中请求暂停)---
function Table:DeZhouPauseReq(nUserId,tData)
	self:Print("DeZhouPauseReq,nUserId_%d",nUserId)
	local DeZhouPauseReq ={}
	DeZhouPauseReq.nUserId=nUserId
	DeZhouPauseReq.isPause =tData.isPause
	self:SendToCenterServ("DeZhouPauseReq",DeZhouPauseReq) 
end

--主播踢人请求---
function Table:DeZhouKickUserReq(nUserId,tData)
	self:Print("DeZhouKickUserReq,nUserId_%d,nPos_%d",nUserId,tData.nPos)
	local DeZhouKickUserReq={}
	DeZhouKickUserReq.nUserId =nUserId
	DeZhouKickUserReq.nPos =tData.nPos
	self:SendToCenterServ("DeZhouKickUserReq",DeZhouKickUserReq)
end

--设置更改请求---
function Table:DeZhouCofingReq(nUserId,tData)
	self:Print("DeZhouCofingReq,nUserId_%d",nUserId)
	local DeZhouCofingReq ={}
	DeZhouCofingReq.nUserId =nUserId
	DeZhouCofingReq.nCapacity=tData.nCapacity
	DeZhouCofingReq.nConfigId=tData.nConfigId
	DeZhouCofingReq.nIntervalLev=tData.nIntervalLev
	self:SendToCenterServ("DeZhouCofingReq",DeZhouCofingReq)
end

--Gm命令请求---
function Table:DeZhouGmReq(nUserId,tData)
	self:Print("DeZhouGmReq,nUserId_%d,sStr:%s",nUserId,tData.sStr)
	local DeZhouGmReq ={}
	DeZhouGmReq.nUserId =nUserId
	DeZhouGmReq.sStr =tData.sStr
	self:SendToCenterServ("DeZhouGmReq",DeZhouGmReq)
end

--取消托管请求---
function Table:DeZhouCancelAutoReq(nUserId,tData)
	self:Print("DeZhouCancelAutoReq,nUserId_%d",nUserId)
	self:SendToCenterServ("DeZhouCancelAutoReq",{nUserId=nUserId})
end

--操作请求---
function Table:DeZhouOpReq(nUserId,tData)
	self:Print("DeZhouOpReq,nUserId_%d",nUserId)
	local DeZhouOpReq ={}
	DeZhouOpReq.nUserId =nUserId
	DeZhouOpReq.nOpButton =tData.nOpButton
	DeZhouOpReq.nRaise =tData.nRaise
	self:SendToCenterServ("DeZhouOpReq",DeZhouOpReq)	--发送给中心服
end

--预操作请求---
--isShowCardWhenEnd
--20:弃或过  -21:过牌 -22:跟任何注 >0:跟xx -23:结束后亮牌 -24:亮牌
function Table:DeZhouPreOpReq(nUserId,tData)
	self:Print("DeZhouPreOpReq,nUserId_%d",nUserId)
	local DeZhouPreOpReq={}
	DeZhouPreOpReq.nUserId=nUserId
	DeZhouPreOpReq.nOpId =tData.nOpId				
	DeZhouPreOpReq.isOn =tData.isOn						
	self:SendToCenterServ("DeZhouPreOpReq",DeZhouPreOpReq) --发送给中心服
end	

--站起请求(从玩家位置站起)---
function Table:DeZhouStanpUpReq(nUserId,tData)
	self:Print("DeZhouStanpUpReq,nUserId_%d",nUserId)
	local tSeatUser =self:IsPlayerSeatUser(nUserId)
	if tSeatUser then
		self:SendToCenterServ("DeZhouStanpUpReq",{nUserId=nUserId}) --发送给中心服
	else
		self:Print("DeZhouStanpUpReq Fail,Not in player seat")
	end
end

function Table:_SitDownReq(tUser,nPos,sIP,tGps)
	local item ={}
	item.nUserId=tUser.nUserId		     	--玩家ID
	item.sFaceId=tUser.sFaceId			 	--头像url
	item.sName=tUser.sName			 		--昵称
	item.nSex=tUser.nSex	    	 		--性别 0:男 1:女
	item.sShopAccount =tUser.sShopAccount	--第三方用户ID
	item.isAndroid =tUser.isAndroid	 		--是否机器人
	item.nGold=tUser.nGold					
	item.nShopId =tUser.nShopId
	item.nBuyTo =tUser.nBuyTo
	item.nIsAutoBuy =tUser.nIsAutoBuy
	item.isAddFreeTimeIfStart =tUser.isAddFreeTimeIfStart
	item.sIP=sIP
	item.tGps =tGps
		
	tUser.tGps=tGps
	tUser.sIP =sIP

	local DeZhouSitDownReq ={}
	DeZhouSitDownReq.nUserId=tUser.nUserId
	DeZhouSitDownReq.nPos=nPos 					-->0:坐下的座位号. 0:随机坐下
	DeZhouSitDownReq.tUserInfo=item
	
	self:SendToCenterServ("DeZhouSitDownReq",DeZhouSitDownReq)	--发送给中心服
end


--坐下请求(坐下到玩家位置)---
function Table:DeZhouSitDownReq(nUserId,tData)
	self:Print("DeZhouSitDownReq,nUserId_%d",nUserId)
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)

	local tGps=nil
	if tData.tGps then
		tGps ={nLongitude=tData.tGps.nLongitude,nLatitude=tData.tGps.nLatitude}
	end
	self:_SitDownReq(tUser,tData.nPos,tData.sIP,tGps)	--发送给中心服坐下
end	

--筹码带出范围查看请求
function Table:_ClubDeZhouTakeOutRangeReq(nUserId,tData)
	self:Print("_ClubDeZhouTakeOutRangeReq,nUserId_%d",nUserId)
	self:SendToCenterServ("TakeOutRangeReq",{nUserId=nUserId})						--发送给中心服
end
--筹码带出请求
function Table:_ClubDeZhoTakeOutReq(nUserId,tData)
	self:Print("_ClubDeZhoTakeOutReq,nUserId_%d",nUserId)
	self:SendToCenterServ("TakeOutReq",{nUserId=nUserId,nTakeOut=tData.nTakeOut}) --发送给中心服
end

--'留座离桌'或'回到座位' 请求
function Table:_ClubDeZhouRetainReq(nUserId,tData)
	self:Print("_ClubDeZhouRetainReq,nUserId_%d nOp_%d",nUserId,tData.nOp)
	self:SendToCenterServ("RetainReq",{nUserId=nUserId,nOp=tData.nOp}) 		--发送给中心服
end

--翻牌请求
function Table:_ClubDeZhouCardOpenReq(nUserId,tData)
	self:Print("_ClubDeZhouCardOpenReq,nUserId_%d ",nUserId)
	self:SendToCenterServ("CardOpenReq",{nUserId=nUserId, sTableId = self.sTableId, sPaiJuId = self.sPaiJuId}) 		--发送给中心服
end

function Table:_DeZhouTakeInRangeRsp(nUserId)
	local tUser =self.arrUsers[nUserId]
	if tUser==nil then
		return
	end
	local nMax,nMin,nTempChips =self:_TakeInMaxAndMin(nUserId)
	local DeZhouTakeInRangeRsp ={}
	local gold = self:Get_User_UnLockGold(nUserId)+nTempChips
	gold = publicApi.DealFloat(gold)
	DeZhouTakeInRangeRsp.nGold =gold		--当前身上金币
	DeZhouTakeInRangeRsp.nMin=nMin										--最小买入
	DeZhouTakeInRangeRsp.nMax =nMax										--最大买入
	DeZhouTakeInRangeRsp.nIsAuto =tUser.nIsAutoBuy						--tUser.nIsAutoBuy  --是否每局自动买入 1:是 其它:否
	self:Print("_DeZhouTakeInRangeRsp,nUserId:%d nUnLockGold:%.2f",tUser.nUserId,DeZhouTakeInRangeRsp.nGold)
	self:SendToUser(nUserId,"ClubDeZhouTakeInRangeRsp",DeZhouTakeInRangeRsp)
end

function Table:_TakeInMaxAndMin(nUserId)
	local tSeatUser =self:IsPlayerSeatUser(nUserId)
	local nBalance, nTempChips, nBuyTo=0,0,0
	if tSeatUser  then
		nBalance =tSeatUser.nBalance
		nTempChips = tSeatUser.nTempChips or 0
		nBuyTo = tSeatUser.nBuyTo or 0
	end
	local nTakeInLimit = self.tTableConfig.nTakeInLimit or 0
	if nTakeInLimit == 0 then
		nBalance = 0
	else
		if nBalance >= nTakeInLimit then
			nBalance = nTakeInLimit
		else
			if (self.nBuyMax + nBalance + nBuyTo) >= nTakeInLimit then
				nBalance = self.nBuyMax - (nTakeInLimit - nBalance) - nBuyTo
			else
				nBalance = 0
			end
			nBalance = nBalance > 0 and nBalance or 0
		end
	end
	local nMax =math.max(self.nBuyMax-nBalance,0)
	local nMin =math.min(self.nBuyMin,nMax)
	return nMax,nMin,nTempChips
end


--筹码买入范围查看请求---
function Table:DeZhouTakeInRangeReq(nUserId,tData)
	self:_DeZhouTakeInRangeRsp(nUserId)
	self:Print("DeZhouTakeInRangeReq,nUserId:%d",nUserId)
end

--筹码买入请求---
function Table:DeZhoTakeInReq(nUserId,tData)
	self:Print("DeZhoTakeInReq,nUserId_%d",nUserId)
	--self:SendToUser(nUserId,"ClubDeZhoTakeInRsp",{nRlt=0})	--由中心服返回时再回复给玩家
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)

	if not self:IsPlayerSeatUser(nUserId)   then
		if  tData.nIsAutoSitDown~=1 then
			return
		end
		self:_SitDownReq(tUser,0,tUser.sIP,tUser.tGps)	--发送给中心服坐下
	end

	tUser.nBuyTo =publicApi.Floor_2(tData.nTakeIn)
	tUser.nIsAutoBuy =tData.nIsAuto
	local DeZhoTakeInReq ={}
	DeZhoTakeInReq.nUserId=nUserId
	DeZhoTakeInReq.nBuyTo=tUser.nBuyTo
	DeZhoTakeInReq.nIsAutoBuy=tUser.nIsAutoBuy
	self:SendToCenterServ("DeZhoTakeInReq",DeZhoTakeInReq)		--发送给中心服
end

--手动撤码---
function Table:DeZhouTakeOutReq(nUserId, tData)
	if not self:IsPlayerSeatUser(nUserId) then
		return
	end
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
	if tUser.nValue == 0 then
		self:SendToUser(nUserId,"ClubDeZhouTakeChipsOutRsp",{nRlt=4})
		return
	end
	local DeZhouTakeChipOutReq ={}
	DeZhouTakeChipOutReq.nUserId=nUserId
	DeZhouTakeChipOutReq.nValue=tUser.nValue
	self:SendToCenterServ("DeZhouTakeChipOutReq",DeZhouTakeChipOutReq)		--发送给中心服
end

--撤码查看请求---
function Table:DeZhouTakeOutInfoReq(nUserId,tData)
	if not self:IsPlayerSeatUser(nUserId) then
		return
	end
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
	local DeZhouTakeOutInfoReq ={}
	DeZhouTakeOutInfoReq.nUserId=nUserId
	self:SendToCenterServ("DeZhouTakeOutInfoReq",DeZhouTakeOutInfoReq)		--发送给中心服
end

--撤码设置---
function Table:DeZhouTakeOutSetReq(nUserId,tData)
	if not self:IsPlayerSeatUser(nUserId) then
		return
	end
	self:Print("DeZhouTakeOutSetReq,nUserId_%d tData.isAuto:%d",nUserId, tData.isAuto)
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
	-- tUser.isAutoTabkeOut = tData.nIsAuto
	local DeZhouTakeOutSetReq ={}
	DeZhouTakeOutSetReq.nUserId=nUserId
	DeZhouTakeOutSetReq.isAuto= tData.isAuto
	self:SendToCenterServ("DeZhouTakeOutSetReq",DeZhouTakeOutSetReq)		--发送给中心服
end

--撤码查看请求(中心服消息)
function Table:OnTakeOutInfoRsp(tData)
	self:Print("OnTakeOutInfoRsp tData.nRlt:%d nTempChips:%.2f nCanOutChips:%.2f isAutoTabkeOut:%s", tData.nRlt, tData.nTempChips, tData.nCanOutChips, tostring(tData.isAutoTabkeOut))
	local nUserId = tData.nUserId
	local nRlt = tData.nRlt
	local nTempChips = publicApi.DealFloat(publicApi.Floor_2(tData.nTempChips))
	local nCanOutChips = tData.nCanOutChips
	local isAutoTabkeOut = tData.isAutoTabkeOut
	local tSeatUser = self:IsPlayerSeatUser(nUserId)
	if tSeatUser and nRlt == 0 then
		nCanOutChips = publicApi.DealFloat(publicApi.Floor_2(nCanOutChips))
		tSeatUser.nTempChips = nTempChips
		tSeatUser.nCanOutChips = nCanOutChips
		tSeatUser.isAutoTabkeOut = isAutoTabkeOut
	end
	self:SendToUser(nUserId,"ClubDeZhouTakeOutInfoRsp",{nRlt=nRlt,nTempChips=nTempChips,nCanOutChips=nCanOutChips,isAutoTabkeOut=isAutoTabkeOut})
end

--撤码设置(中心服消息)
function Table:OnTakeOutSetRsp(tData)
	self:Print("OnTakeOutSetRsp isAuto:%s", tostring(tData.isAuto))
	local nUserId = tData.nUserId
	local nRlt = tData.nRlt
	local isAutoTabkeOut = tData.isAuto
	local tSeatUser = self:IsPlayerSeatUser(nUserId)
	if tSeatUser and nRlt == 0 then
		tSeatUser.isAutoTabkeOut = isAutoTabkeOut
		tSeatUser.nCanOutChips = publicApi.DealFloat(publicApi.Floor_2(tData.nCanOutChips))
		self:Print("nCanOutChips:" .. tSeatUser.nCanOutChips)
	end
	self:SendToUser(nUserId,"ClubDeZhouTakeOutSetRsp",{nRlt=nRlt,isAutoTabkeOut=isAutoTabkeOut,nCanOutChips=tData.nCanOutChips})
end

--手动撤码(中心服消息)
function Table:OnTakeChipsOutRsp(tData)
	local nUserId = tData.nUserId
	local nRlt = tData.nRlt
	local nTempChips = tData.nTempChips
	local nCanOutChips = tData.nCanOutChips
	local nBalance = tData.nBalance
	local tSeatUser = self:IsPlayerSeatUser(nUserId)
	if tSeatUser and nRlt == 0 then
		nCanOutChips = publicApi.DealFloat(publicApi.Floor_2(nCanOutChips))
		tSeatUser.nTempChips = nTempChips
		tSeatUser.nCanOutChips = nCanOutChips
		tSeatUser.nBalance = nBalance
	end
	self:SendToUser(nUserId,"ClubDeZhouTakeChipsOutRsp",{nRlt=nRlt,nTempChips=nTempChips,nCanOutChips=nCanOutChips,nBalance=nBalance})
end

--返回大厅---
function Table:DeZhouBackToLobbyReq(nUserId,tData)
	self:Print("DeZhouBackToLobbyReq--,nUserId_%d",nUserId)
	-- self:SendToUser(nUserId,"ClubDeZhouBackToLobbyRsp",{nRlt=0}) --返回大厅回复,只成功
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
	local nSitId = tUser.nSitId or 0

	if not self:IsPlayerSeatUser(nUserId) then
		self:SendToUser(nUserId,"ClubDeZhouBackToLobbyRsp",{nRlt=0})
		self:_SetLeaveTable(nUserId)
		if tUser.isPlay and nSitId > 0 then
			--广播给前端
			for userId,_ in pairs(self.arrUsers) do
				if userId ~= nUserId then
					self:SendToUser(userId,"ClubDeZhouLeaveNotify",{nPos=nSitId,nName=tUser.sName})
				end
			end
		end
		self:SendToCenterServ("DeZhouBackToLobbyReq",{nUserId=nUserId}) --发送给中心服
		return
	end
	self:SendToCenterServ("DeZhouBackToLobbyReq",{nUserId=nUserId}) --发送给中心服
	tUser.isOffLine = true
end

--断线---
function Table:OnUserLeave(nUserId)
	self:Print("OnUserLeave,nUserId_%d",nUserId)
	local tUser =self.arrUsers[nUserId]
	if tUser==nil then
		self:Print("UserNotInHere:%d",nUserId)
		return
	end
	if not self:IsPlayerSeatUser(nUserId) then
		self:_SetLeaveTable(nUserId)
		return
	end
	if not tUser.isOffLine then
		self:Print("set nUserId_%d OffLine",nUserId)
		tUser.isOffLine=true
		self:SendToCenterServ("UserOffLine",{nUserId=nUserId}) --发送给中心服
	end
end

--发送数据接口
--//示例 : SendToUser(1,"RaiseReq",{nSitId=1,nRaiseChip=100})
function Table:SendToUser(nUserId,strMsgName,tMsgData)
	local tUser =self.arrUsers[nUserId]
	if tUser==nil or tUser.isOffLine then
		self:Print("SendToUser fail,nUserId_%d  %s",nUserId,strMsgName)
		return
	end
	self.tInterFace._SendToUser(nUserId,strMsgName,tMsgData)
	return true
end

-- isReconnect 不检测密码
function Table:OnUserEnter(tUserInfo,isKeepStand,nPass,isReconnect)
	local nUserId =tUserInfo.nUserId
	if self.tUserIdBanEnter[nUserId] then				--被后台踢出过的玩家,禁止进入
		return false,MsgCode.nKickToLobbyByAdmin
	end
	if self.tTableConfig.nIsPerson == 1 and nUserId ~= self.nLiveUserID and not isReconnect then            --私人房间密码
		self:Print("OnUserEnter:%d nPass:%s sPassWord:%s",nUserId, nPass or "", self.tTableConfig.sPassWord or "")
		if nPass ~= self.tTableConfig.sPassWord then
			return false,MsgCode.nPassErr
		end
	end

	local tUser =self.arrUsers[nUserId]
	if tUser then
		if not tUser.isOffLine then
			return true
		end
		tUser.isOffLine=false
		if self:IsPlayerSeatUser(nUserId) then
			self:SendToCenterServ("UserOnLine",{nUserId=nUserId})
		end
		return true
	end
	local item ={}
	item.nUserId=tUserInfo.nUserId		     	--玩家ID
	item.sFaceId=tUserInfo.sFaceId			 	--头像url
	item.sName=tUserInfo.sName			 		--昵称
	item.nSex=tUserInfo.nSex	    	 		--性别 0:男 1:女
	item.sShopAccount =tUserInfo.sShopAccount		 --第三方用户ID
	item.isAndroid =tUserInfo.isAndroid	 		--是否机器人
	item.nShopId =tUserInfo.nShopId
	item.isOffLine =false
	item.nIsAuto =0								--是否每局自动买入 1:是 其它:否
	item.nBuyTo =0
	item.nGold=tUserInfo.nGold
	item.isAddFreeTimeIfStart =false
	if  self:IsUseCredit() then					--积分房
		item.nGold =(Define.GoldOfFreeRoom* self.nBigBlind)		--免费试玩房的积分
	end
	if self.nRoomType ==RoomType.nMtt then		--比赛房的积分
		item.nGold =Define.GoldOfMttRoom
	end

	if self:MatchRoomId() ==0 then
		item.isAddFreeTimeIfStart =true
	end
	self.arrUsers[item.nUserId] =item
	self:Print("OnUserEnter:%d",nUserId)
	self:SendToCenterServ("SlaveUserSit",{nUserId=nUserId,sName=item.sName,sFaceId=item.sFaceId,item=item})

	return true
end


function Table:_SetLeaveTable(nUserId, sourceType)
	self:Print("_SetLeaveTable:%d",nUserId)
	local t =self.arrUsers[nUserId] or {}
	local isAndroid =t.isAndroid or false
	self.arrUsers[nUserId]=nil
	self.arrStandUpUsers[nUserId]=t
	self.tInterFace._LeaveTable(nUserId,self, sourceType)
	self:SendToCenterServ("SlaveUserUp",{nUserId=nUserId,isAndroid=isAndroid, nLeaveType = sourceType})
end

function Table:SendToCenterServ(sCmd,tData)
	local DZCReq ={}
	DZCReq.sTableId =self.sTableId				
	DZCReq.sCmd =sCmd
	DZCReq.sJsonData=cjson.encode(tData)
	DZCReq.nEcho =0
	self.tInterFace.SendToCenterServer(nil,"DZCReq",DZCReq)
end

--
function Table:Print(str,...)
	tBase.Log(self.sTableId.."_"..self.nJuShu.."=>"..str,...)
end

function Table:ErrorHappen(sMsg)
	self:Print("Error Happen:%s",sMsg)
end

return Table
