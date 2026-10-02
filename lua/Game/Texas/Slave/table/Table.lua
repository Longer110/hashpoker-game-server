
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

local TableState =PublicDefine.TableState
local UserStatus =PublicDefine.UserStatus
local TableType =PublicDefine.TableType

local UserOp =PublicDefine.UserOp

local function _CopyArr(arr)
	local cp ={}
	for _,v in ipairs(arr) do
		cp[#cp+1]=v
	end
	return cp
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

	t.nGroupId =tConfig.nGroupId or 9					---
	t.nRoomId  =tConfig.nRoomId or -1					---
	t.nTableType =tConfig.nTableType or -1				---	--桌子类型
	t.nLiveUserID =tConfig.nLiveUserID or 0				---	--主播ID
	t.sLiveID =tConfig.sLiveID or ""					---
	t.nSmallBlind=tConfig.nSmallBlind or 1 				--- --小盲注数额
	t.nBigBlind=tConfig.nBigBlind or (t.nSmallBlind*2)	--- --大盲注数额(通常等于:小盲注x2)
	t.nZhuaTou=tConfig.nZhuaTou or t.nBigBlind*2					--抓头数额
	t.nCapacity =tConfig.nCapacity or 0					--- --能供玩游戏的座位数
	t.nBuyMin =tConfig.nBuyMin or (t.nBigBlind*10)		--- --最小买入
	t.nBuyMax =tConfig.nBuyMax or (t.nBuyMin*20)		--- --最大买入
	t.nOperateTime=10									--- --操作最大时间,单位:秒 (通常为10)

	t.nPotSum =0										--- --底池总额(已押筹码总额)
	t.arrPool={}										--- --底池,例如:{100,200,250}
	t.arrCommunityCards={}								--- --公共牌
	t.nStage =0											--- --当前游戏状态 0:未开始(等待游戏开始) 1:游戏中
	t.nClubId=nil										--俱乐部id
	t.nItemId =nil										--使用的金币类型 1:金币 其它:俱乐部币的id (俱乐部房配置,否时为nil)
	t.nGoldType =nil									-- 1:金币 2:俱乐部币 3:积分 (俱乐部房配置,否时为nil)

	--本桌子是否需要配置后才能开始 true:(需要等待主播选配置) false:(使用当前配置)
	t.isConfigNotSet =true									---			 	
	if t.nLiveUserID==nil or t.nLiveUserID<=0 then
		t.isConfigNotSet =false
	end

	t.tDeZhouConfigOption ={arrCapacity={},arrConfig={}}	--- --桌子可选配置(主播有)
	t.isPause =false										--- --是否设置了暂停 true:是  false:否		 	
	t.sPaiJuId =""											--- --牌局id
	t.nJuShu =0												--- --当前局数
	t.nTimeStart =0											--- -- >0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	t.nBankerPos=nil										--- --庄家位置

	t.tPosToPlayerSeatUser={}								--- --玩家席用户
	t.arrUsers ={}											--本桌子所有用户(nUserId作索引)

	t.isReporting=false										--一个标志位,确保不会重复执行

	t.tAuthor={}											--比赛桌管理员 tAuthor[10086]=true
	t.nMStatus=0											--比赛桌状态,0:未开始 1:暂停 2:正常 (管理员可使用原暂停协议,控制该状态切换, 0->2<->1)
	return t
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
		local item =self:_GetProtoUser(v,v.nUserId ==nUserId)
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
	if not isCanSeeHoleCards then
		for i=1,#DeZhouUser.arrHoleCards do
			DeZhouUser.arrHoleCards[i]=0
		end
		DeZhouUser.nCardType=0
	end
	--剩余可操作(思考)时间
	DeZhouUser.nOpTimeRemain =self.nOperateTime -(os.time() -tUser.nGetRightTime) 
	if tUser.nStatus ~= UserStatus.nThinking or DeZhouUser.nOpTimeRemain<0 then
		DeZhouUser.nOpTimeRemain=0
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
	local tData =tPublicRedis.GetGameRecommendInfo(Define.nGameId,nUserId) or {}
	local nConfigId =tData.nConfigId or 1
	local nCapacity =tData.nCapacity or 6
	local nIntervalLev =tData.nIntervalLev or 1
	return nConfigId,nCapacity,nIntervalLev
end

function Table:Get_User_UnLockGold(nUserId)
	if  not self:IsUseCredit() then	--非积分房
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
	end
end

--通知玩家金币变化
function Table:_NotifyGoldChange(tUser)
	local nGold =self:Get_User_UnLockGold(tUser.nUserId)
	local DeZhouGoldNotify={}
	DeZhouGoldNotify.nGold =publicApi.Floor_2(nGold)  
	self:SendToUser(tUser.nUserId,"DeZhouGoldNotify",DeZhouGoldNotify)
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
		local _,nCardType =tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,#self.arrCommunityCards-nCntOfNewAdd))
		local _,nCardTypeA =tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,3))	--与前3个公共牌组合成的牌型
		local _,nCardTypeB =tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,4))	--与前4个公共牌组合成的牌型
		local _,nCardTypeC =tAlg.DeZhouCardType(arrHoleCards,_FrontCards(self.arrCommunityCards,5))	--与前5个公共牌组合成的牌型
		local UserHoleCard ={}
		UserHoleCard.nPos=tSeatUser.nSitId			--座位号
		UserHoleCard.arrHoleCards=arrHoleCards		--底牌(2张)
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


function Table:GetScenceByUserId(nUserId)
	local DeZhouScence={}
	DeZhouScence.nSmallBlind=self.nSmallBlind						--小盲注数额
	DeZhouScence.nBigBlind=self.nBigBlind							--大盲注数额(通常等于:小盲注x2)
	DeZhouScence.nZhuaTou=self.nZhuaTou							    --抓头数额
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

	local tUser =self:IsPlayerSeatUser(nUserId)
	if tUser and (not tUser.isAuto) then
		DeZhouScence.tOperation=tUser.tOperation					--当前自己可操作信息(自己为思考状态时有)
		DeZhouScence.tPreOpOption=tUser.tPreOpOption 				--自己当前可预操作选项
	end
	if nUserId==self.nLiveUserID then
		DeZhouScence.tDeZhouConfigOption =self.tDeZhouConfigOption
		local nConfigIdDefault,nCapacityDefault,nIntervalLevDefault =self:_GetLiveLastConfig(self.nLiveUserID)
		DeZhouScence.tDeZhouConfigOption.nConfigIdDefault=nConfigIdDefault 			--默认配置
		DeZhouScence.tDeZhouConfigOption.nCapacityDefault=nCapacityDefault			--默认人数
		DeZhouScence.tDeZhouConfigOption.nIntervalLevDefault =nIntervalLevDefault   --默认牌局间隔
	end
	local nCurrentTime =os.time()
	if self.nTimeStart >nCurrentTime then
		DeZhouScence.nMSeconds =(self.nTimeStart -nCurrentTime)*1000
	elseif self.nTimeStart <=0 then
		DeZhouScence.nMSeconds =self.nTimeStart
	else
		DeZhouScence.nMSeconds =0 									-- >0:开局倒计时剩余时间(毫秒) -1:无限等待状态(因为主播设置了暂停) 其它:无意义
	end
	DeZhouScence.nGold =publicApi.Floor_2(self:Get_User_UnLockGold(nUserId))

	DeZhouScence.nClubId= self.nClubId
	DeZhouScence.sTableName= self.sTableName
	DeZhouScence.nCurrency =self.nItemId or 1					--本桌子使用的币种 1:金币 >1:俱乐部币

	if self.nTableType ==TableType.nCompete then
		DeZhouScence.nTableType=10								--桌子类型 10:比赛桌子 ,其它:无效
		DeZhouScence.nMStatus=self.nMStatus						--比赛桌状态,0:未开始 1:暂停 2:正常 (管理员可使用原暂停协议,控制该状态切换, 0->2<->1)
		DeZhouScence.isAuthor=self:_IsAuthor(nUserId)			--是否为管理员(管理员可控制比赛桌状态,请离用户,关闭桌子)
	end

	return DeZhouScence
end

function Table:_IsAuthor(nUserId)
	if self.tAuthor[nUserId] then
		return true
	end
	return false
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
	self.nZhuaTou=tScenc.nZhuaTou or self.nBigBlind*2						--抓头数额
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
		self.tPosToPlayerSeatUser[v.nSitId] =item
	end

	--比赛桌状态
	self.tAuthor={}
	for _,nUserId in ipairs(tScenc.arrAuthor or {}) do	--比赛桌管理员
		self.tAuthor[nUserId]=true
	end
	self.nMStatus =tScenc.nMStatus or 0 				--比赛桌状态,0:未开始 1:暂停 2:正常
end

--来自中心服的消息处理
function Table:OnCenterMsgHandle(sCmd,tJsonData,nEcho)
	self:Print("OnCenterMsgHandle sCmd:%s",sCmd)
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
	if sCmd =="CompeteStatusChange" then		--比赛桌状态变化通知
		self:OnCompeteStatusChange(tJsonData)
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

	if sCmd =="DeZhouRoomCfgChange" then		--匹配房间配置更改通知
		self:OnRoomCfgChange(tJsonData)
		return
	end

	self:Print("sCmd:%s Not Handle",sCmd)
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
	item.isAuto=false			 			--是否托管中
	item.tOperation=nil						--当前自己可操作信息(自己为思考状态时有)
	item.tPreOpOption=nil 					--自己当前可预操作选项
	self.tPosToPlayerSeatUser[item.nSitId] =item	
	self:Print("OnUserSitDownNotify nUserId_%d nSitId_%d",item.nUserId,item.nSitId)

	--同步可用金币(主要服务于匹配试玩房,其它情况以redis为准)
	local tUser =self.arrUsers[tSeatUser.nUserId]
	if tUser then
		tUser.nGold =tSeatUser.nUnLockGold
		self:_NotifyGoldChange(tUser)
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouUserSitDownNotify",{tUser=self:_GetProtoUser(item,false)})
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
		self:SendToUser(nUserId,"DeZhouUserStanpUpNotify",{nSitId=nPos})
	end
	local tUser =self.arrUsers[tSeatUser.nUserId]
	if not tUser then
		return
	end
	if tUser.isOffLine then
		self:_SetLeaveTable(tSeatUser.nUserId)
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
	self:SendToUser(tJsonData.nUserId,"DeZhouKickUserRsp",{nRlt=tJsonData.nRlt})
end

--暂停回复(中心服消息)---
function Table:OnDeZhouPauseRsp(tJsonData)
	self:Print("OnDeZhouPauseRsp nUserId_%d isPause_%s",tJsonData.nUserId,tostring(tJsonData.isPause))
	self.isPause =tJsonData.isPause
	self.nMStatus =tJsonData.nMStatus
	--回复给前端
	self:SendToUser(tJsonData.nUserId,"DeZhouPauseRsp",{isPause=tJsonData.isPause,nMStatus=tJsonData.nMStatus})
end

--比赛桌状态变化通知(中心服消息)---
function Table:OnCompeteStatusChange(tJsonData)
	self.nMStatus =tJsonData.nMStatus
	self.isPause =tJsonData.isPause
	--广播给其它管理员
	for nUserId,_ in pairs(self.arrUsers) do
		if self:_IsAuthor(nUserId) and nUserId~=tJsonData.nUserId then
			self:SendToUser(nUserId,"DeZhouPauseRsp",{isPause=self.isPause,nMStatus=self.nMStatus})
		end
	end 
end


--桌子关闭通知(中心服消息)---
function Table:OnTableCloseNotify(tJsonData)
	self:Print("OnTableCloseNotify,nReason:%d",tJsonData.nReason)
	self.Timer:KillAllTimer()
	--广播给前端(桌子关闭)
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouFailNotify",{nCode=18})
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
	tSeatUser.nBalance =tJsonData.nBalance --玩家可用筹码余额更新
	self:Print("OnDeZhouBalanceNotify,nPos_%d nBalance_%.3f",tJsonData.nPos,tJsonData.nBalance)
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouBalanceNotify",{nPos=tJsonData.nPos,nBalance=tJsonData.nBalance})
	end 
end

--桌子配置变动通知(中心服消息,发生在主播更改配置后)---
function Table:OnDeZhouConfigNotify(tJsonData)
	local tConfigItem =tJsonData.tConfigItem
	self.nSmallBlind=tConfigItem.nSmallBlind 			--小盲注数额
	self.nBigBlind=tConfigItem.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou=tConfigItem.nZhuaTou or self.nBigBlind*2		--抓头数额
	self.nBuyMin =tConfigItem.nTakeInMin	 			--最小买入
	self.nBuyMax =tConfigItem.nTakeInMax				--最大买入
	self.nCapacity =tJsonData.nCapacity					--能供玩游戏的座位数
	self.isConfigNotSet=false
	self:Print("OnDeZhouConfigNotify,%s",cjson.encode(tJsonData))
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouConfigNotify",{nCapacity=tJsonData.nCapacity,tConfigItem=tConfigItem})
	end 
end

--
function Table:OnRoomCfgChange(tJsonData)
	self.nSmallBlind=tJsonData.nSmallBlind 			--小盲注数额
	self.nBigBlind=tJsonData.nBigBlind				--大盲注数额(通常等于:小盲注x2)
	self.nZhuaTou=tJsonData.nZhuaTou or self.nBigBlind*2		--抓头数额
	self.nBuyMin =tJsonData.nBuyMin	 			--最小买入
	self.nBuyMax =tJsonData.nBuyMax				--最大买入

	local t={}
	t.nConfigId=1		--配置id
	t.nSmallBlind=self.nSmallBlind	--小盲
	t.nBigBlind=self.nBigBlind		--大盲
	t.nZhuaTou=self.nZhuaTou		--抓头
	t.nTakeInMin=self.nBuyMin		--最低带入
	t.nTakeInMax=self.nBuyMax		--最高带入
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouConfigNotify",{nCapacity=self.nCapacity,tConfigItem=t})
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
		self:SendToUser(nUserId,"DeZhouShowCardNotify",{nPos=tJsonData.nPos})
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
		self:SendToUser(nUserId,"DeZhouCancelAutoNotify",{nPos =tJsonData.nPos})
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
		self:SendToUser(nUserId,"DeZhouChatNotify",DeZhouChatNotify)
	end
end

--异常提示通知(中心服消息)---
function Table:OnDeZhouFailNotify(tJsonData)
	local nUserId =tJsonData.nUserId
	local DeZhouFailNotify={}
	DeZhouFailNotify.nCode=tJsonData.nCode			--错误码,见错码定义
	DeZhouFailNotify.sErr=tJsonData.sErr			--错误提示
	DeZhouFailNotify.tRsp=tJsonData.tRsp			--最小最大带入(金币不足时有)
	self:Print("OnDeZhouFailNotify,nUserId_%d,nCode_%d",nUserId,tJsonData.nCode)
	--广播给前端
	if nUserId>0 then
		self:SendToUser(nUserId,"DeZhouFailNotify",DeZhouFailNotify)
		return
	end
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouFailNotify",DeZhouFailNotify)
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
	self:SendToUser(nUserId,"DeZhouPreOpRsp",DeZhouPreOpRsp)
end

--开始倒计时通知(中心服消息)---
function Table:OnToStartNotify(tJsonData)
	self:Print("OnToStartNotify,nMSeconds_%d",tJsonData.nMSeconds)
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouToStartNotify",{nMSeconds=tJsonData.nMSeconds})
	end
end

--结算通知(中心服消息)---
function Table:OnSettleNotify(tJsonData)
	self:Print("OnSettleNotify")
	self.nStage =tJsonData.nStage
	self.arrPool =tJsonData.arrPot
	for _,item in ipairs(tJsonData.arrUserForSlave) do
		local tSeatUser =self.tPosToPlayerSeatUser[item.nPos]
		if tSeatUser then
			tSeatUser.nBalance=item.nBalance		--同步当前可用筹码
			tSeatUser.nBet =0
		end
		local tUser =self.arrUsers[item.nUserId]
		if tUser then
			tUser.nGold =item.nUnLockGold  			--同步可用金币(主要服务于匹配试玩房,其它情况以redis为准)
		end
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouSettleNotify",{arrUsersWin=tJsonData.arrUsersWin,arrPot=tJsonData.arrPot})
	end 
end

--桌子重置通知(中心服消息)---
function Table:OnTableResetNotify(tJsonData)
	self:Print("OnTableResetNotify")
	self.nStage =tJsonData.nStage
	self.nSmallBlind=(tJsonData.nSmallBlind or self.nSmallBlind)
	self.nBigBlind=(tJsonData.nBigBlind or self.nBigBlind)

	self:_ReSetTable()
	self:_ReSetSeatUser()

	--给前端同步一下可用金币
	for _,tSeatUser in pairs(self.tPosToPlayerSeatUser) do
		local tUser =self.arrUsers[tSeatUser.nUserId]
		if tUser then
			self:_NotifyGoldChange(tUser)
		end
	end
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		self:SendToUser(nUserId,"DeZhouTableResetNotify",{nNoUse=0,nSmallBlind=self.nSmallBlind,nBigBlind=self.nBigBlind})
	end
end

--后台踢人成功回复(中心服消息)---
function Table:OnRSP_Kick_User(tJsonData)
	local nUserId =tJsonData.nUserId
	self:Print("OnRSP_Kick_User,%d",nUserId)
	if self.arrUsers[nUserId] then
		self:SendToUser(nUserId,"DeZhouFailNotify",{nCode=20,sErr="kick by backstage"})
		self:_SetLeaveTable(nUserId)
		return
	end
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

	--广播给前端
	local DeZhouOpNotify ={}
	DeZhouOpNotify.nPos =tJsonData.nPos					--座位号
	DeZhouOpNotify.nOp=nOp								---5:弃牌,  -1:AllIn, -2:看牌, -6:跟注, -3:加注
	DeZhouOpNotify.isAuto =tJsonData.isAuto
	DeZhouOpNotify.nBet=nCallOrRaiseChip 		    	--跟注或加注时有效，表示具体的跟注\加注数值(>0)
	for nUserId,_ in pairs(self.arrUsers) do
		local tm =self:IsPlayerSeatUser(nUserId) or {}
		DeZhouOpNotify.tPreOpOption=tm.tPreOpOption
		self:SendToUser(nUserId,"DeZhouOpNotify",DeZhouOpNotify)
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
	tSeatUser.nStatus =tJsonData.nStatus
	
	--广播给前端
	for nUserId,_ in pairs(self.arrUsers) do
		if nUserId==tSeatUser.nUserId and (not tSeatUser.isAuto) then
			self:SendToUser(nUserId,"DeZhouOperationNotify",{nPos=tJsonData.nPos,tOperation=tSeatUser.tOperation})
		else
			self:SendToUser(nUserId,"DeZhouOperationNotify",{nPos=tJsonData.nPos})
		end
	end 
end

--发牌通知(中心服消息)---
function Table:OnDealNotify(tJsonData)
	--同步桌子状态
	self.nPotSum =tJsonData.nPotSum					
	self.arrPool=tJsonData.arrPot					
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
		tSeatUser.arrHoleCards =v.arrHoleCards
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
	for nUserId,_ in pairs(self.arrUsers) do
		local tSeatUser =self:IsPlayerSeatUser(nUserId)
		if tSeatUser and tSeatUser.nStatus ~=UserStatus.nLooker then
			DeZhouDealNotify.arrUsersHoleCard =_GetUserHoleCard(tSeatUser.nSitId) --(看不到弃牌玩家的底牌信息,自己的除外)
			DeZhouDealNotify.nCardType =tSeatUser.nCardType
			DeZhouDealNotify.tPreOpOption=tSeatUser.tPreOpOption
		else
			DeZhouDealNotify.arrUsersHoleCard =arrUsersHoleCardForLooker
			DeZhouDealNotify.nCardType = 0
			DeZhouDealNotify.tPreOpOption=nil
		end
		self:SendToUser(nUserId,"DeZhouDealNotify",DeZhouDealNotify)
	end
end

--游戏开始通知(中心服消息)---
function Table:OnGameStartNotify(tJsonData)
	--重置玩家信息
	self:_ReSetSeatUser()

	--桌子状态同步
	self.nPotSum =tJsonData.nPotSum					--底池总额(已押筹码总额)
	self.arrPool={}									--底池,例如:{100,200,250}
	self.arrCommunityCards={}						--公共牌
	self.nStage =tJsonData.nStage					--当前游戏状态 0:未开始(等待游戏开始) 1:游戏中	
	self.sPaiJuId =tJsonData.sPaiJuId				--牌局id
	self.nJuShu =tJsonData.nJuShu					--当前局数
	self.nBankerPos=tJsonData.nBankerPos			--庄家位置
	self.nTimeStart =tJsonData.nTimeStart			-- >0:时间戳(游戏开始) -1:进入了暂停 0:空闲
	local nSmallBlindPos =tJsonData.nSmallBlindPos 	--小盲位置
	local nBigBlindPos =tJsonData.nBigBlindPos 		--大盲位置
	local nZhuaTouPos =tJsonData.nZhuaTouPos 		--抓头位置
	local nAcBetSmall =tJsonData.nAcBetSmall or self.nSmallBlind --实际下注的小盲值
	local nAcBetBig =tJsonData.nAcBetBig or self.nBigBlind		 --实际下注的大盲值
	local nAcBetZhuaTou =tJsonData.nAcBetZhuaTou or 0	 --实际下注的抓头值(0表示没抓头)

	self:Print("OnGameStartNotify")

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
		table.insert(arrPosPartInSort,v.nSitId)
		table.insert(arrUserPartInSort,{nPos=v.nSitId,nTakeIn=v.nBalance,nBet=v.nBet})	
		local tUser =self.arrUsers[v.nUserId]
		if tUser then
			tUser.nGold=v.nUnLockGold
			tUser.isAddFreeTimeIfStart=false	--试玩房有关状态 
			self:_NotifyGoldChange(tUser)
		end
	end
	--广播给前端
	local arrInitUsersBet ={{nPos=nSmallBlindPos,nBet=nAcBetSmall},{nPos=nBigBlindPos,nBet=nAcBetBig}}
	if nZhuaTouPos then
		table.insert(arrInitUsersBet,{nPos=nZhuaTouPos,nBet=nAcBetZhuaTou})
	end
	local DeZhouStartNotify ={}
	DeZhouStartNotify.arrPosPartIn=arrPosPartInSort		--参与本局游戏的玩家座位号(每人发两个底牌,只能自己看到自己的底牌是啥) (发牌顺序按数组顺序)
	DeZhouStartNotify.nBankerPos=self.nBankerPos		--庄家座位号(头像显示标识:'D')
	DeZhouStartNotify.arrUsersBet=arrInitUsersBet 		--(大小盲)玩家下注
	DeZhouStartNotify.arrUserPartIn =arrUserPartInSort --参与本局游戏的玩家信息(发牌顺序按数组顺序)
	for nPos,tUser in pairs(self.arrUsers) do
		local tSeatUser =self:IsPlayerSeatUser(tUser.nUserId) or {}
		DeZhouStartNotify.nCardType =tSeatUser.nCardType or 0
		DeZhouStartNotify.tPreOpOption=tSeatUser.tPreOpOption or nil		
		DeZhouStartNotify.nTakeIn =tSeatUser.nBalance or 0
		DeZhouStartNotify.arrHoleCards =tSeatUser.arrHoleCards or {}
		DeZhouStartNotify.nChipBuy =tSeatUser.nChipBuy or 0
		self:SendToUser(tUser.nUserId,"DeZhouStartNotify",DeZhouStartNotify)
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
	if strReq =="DeZhouOpReq" then
		self:DeZhouOpReq(nUserId,tData)
		return
	end
	--预操作请求xx
	if strReq =="DeZhouPreOpReq" then	
		self:DeZhouPreOpReq(nUserId,tData)
		return
	end	
	--站起请求(从玩家位置站起)xx
	if strReq =="DeZhouStanpUpReq" then 
		self:DeZhouStanpUpReq(nUserId,tData)
		return
	end	
	--坐下请求(坐下到玩家位置)xx
	if strReq =="DeZhouSitDownReq" then	
		self:DeZhouSitDownReq(nUserId,tData)
		return
	end
	--筹码买入范围查看请求xx
	if strReq =="DeZhouTakeInRangeReq" then 
		self:DeZhouTakeInRangeReq(nUserId,tData)
		return
	end
	--筹码买入请求xx
	if strReq =="DeZhoTakeInReq" then	
		self:DeZhoTakeInReq(nUserId,tData)
		return
	end
	--返回大厅请求xx
	if strReq =="DeZhouBackToLobbyReq" then 
		self:DeZhouBackToLobbyReq(nUserId,tData)
		return
	end
	--取消托管请求xx
	if strReq =="DeZhouCancelAutoReq" then
		self:DeZhouCancelAutoReq(nUserId,tData)
		return
	end
	--房间设置 请求xx
	if strReq =="DeZhouCofingReq" then
		self:DeZhouCofingReq(nUserId,tData)
		return
	end
	--Gm命令xxx
	if strReq =="DeZhouGmReq" then
		self:DeZhouGmReq(nUserId,tData)
		return
	end
	--后台踢人xxx
	if strReq =="REQ_Kick_User" then
		self:REQ_Kick_User(nUserId,tData)
		return
	end
	--主播踢人请求
	if strReq =="DeZhouKickUserReq" then
		self:DeZhouKickUserReq(nUserId,tData)
		return
	end
	--主播暂停请求xxx
	if strReq =="DeZhouPauseReq" then
		self:DeZhouPauseReq(nUserId,tData)
		return
	end
	--来自db服的金币变化(充值)通知xx
	if strReq =="DbRechargeRsp" then
		self:_NotifyGoldChange(tUser)
		return
	end
	--表情聊天xxx
	if strReq =="DeZhouChatReq" then
		self:_DeZhouChatReq(nUserId,tData)
		return
	end
end

--后台踢人请求---
function Table:REQ_Kick_User(nUserId,tData)
	self:Print("REQ_Kick_User,nUserId_%d",nUserId)
	local nType = tData.nType or -1    		--1:立即踢出，解散 2:下局踢出
	local tSeatUser =self:IsPlayerSeatUser(nUserId)
	if not tSeatUser then
		self:SendToUser(nUserId,"DeZhouFailNotify",{nCode=20,sErr="kick by backstage"})
		self:_SetLeaveTable(nUserId)
		return
	end
	self:SendToCenterServ("REQ_Kick_User",{nUserId=nUserId,nType=nType}) 
end

--表情聊天---
function Table:_DeZhouChatReq(nUserId,tData)
	self:Print("_DeZhouChatReq,nUserId_%d nChatId:%d",nUserId,tData.nChatId)
	local DeZhouChatReq ={}
	DeZhouChatReq.nUserId =nUserId
	DeZhouChatReq.nChatId =tData.nChatId
	DeZhouChatReq.nTarget =tData.nTarget
	self:SendToCenterServ("DeZhouChatReq",DeZhouChatReq) 
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

--坐下请求(坐下到玩家位置)---
function Table:DeZhouSitDownReq(nUserId,tData)
	self:Print("DeZhouSitDownReq,nUserId_%d",nUserId)
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
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

	local DeZhouSitDownReq ={}
	DeZhouSitDownReq.nUserId=nUserId
	DeZhouSitDownReq.nPos=tData.nPos -->0:坐下的座位号. 0:随机坐下
	DeZhouSitDownReq.tUserInfo=item
	self:SendToCenterServ("DeZhouSitDownReq",DeZhouSitDownReq)	--发送给中心服
end	

--筹码买入范围查看请求---
function Table:DeZhouTakeInRangeReq(nUserId,tData)
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
	local DeZhouTakeInRangeRsp ={}
	DeZhouTakeInRangeRsp.nGold =self:Get_User_UnLockGold(nUserId)		--当前身上金币
	DeZhouTakeInRangeRsp.nMin=self.nBuyMin								--最小买入
	DeZhouTakeInRangeRsp.nMax =self.nBuyMax								--最大买入
	DeZhouTakeInRangeRsp.nIsAuto =tUser.nIsAutoBuy						--tUser.nIsAutoBuy  --是否每局自动买入 1:是 其它:否
	self:Print("DeZhouTakeInRangeReq,nUserId:%d nUnLockGold:%.2f",tUser.nUserId,DeZhouTakeInRangeRsp.nGold)
	self:SendToUser(nUserId,"DeZhouTakeInRangeRsp",DeZhouTakeInRangeRsp)
end	

--筹码买入请求---
function Table:DeZhoTakeInReq(nUserId,tData)
	self:Print("DeZhoTakeInReq,nUserId_%d",nUserId)
	self:SendToUser(nUserId,"DeZhoTakeInRsp",{nRlt=0})
	if not self:IsPlayerSeatUser(nUserId) then
		return
	end
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)
	tUser.nBuyTo =publicApi.Floor_2(tData.nTakeIn)
	tUser.nIsAutoBuy =tData.nIsAuto
	local DeZhoTakeInReq ={}
	DeZhoTakeInReq.nUserId=nUserId
	DeZhoTakeInReq.nBuyTo=tUser.nBuyTo 						
	DeZhoTakeInReq.nIsAutoBuy=tUser.nIsAutoBuy
	self:SendToCenterServ("DeZhoTakeInReq",DeZhoTakeInReq)		--发送给中心服
end	

--返回大厅---
function Table:DeZhouBackToLobbyReq(nUserId,tData)
	self:Print("DeZhouBackToLobbyReq,nUserId_%d",nUserId)
	self:SendToUser(nUserId,"DeZhouBackToLobbyRsp",{nRlt=0}) --返回大厅回复,只成功
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)

	if not self:IsPlayerSeatUser(nUserId) then
		self:_SetLeaveTable(nUserId)
		return
	end

	--返回大厅自动站起
	self:SendToCenterServ("DeZhouStanpUpReq",{nUserId=nUserId}) --发送给中心服

	if not tUser.isOffLine then
		self:Print("set nUserId_%d OffLine",nUserId)
		tUser.isOffLine=true
		self:SendToCenterServ("UserOffLine",{nUserId=nUserId}) --发送给中心服
	end
end

--断线---
function Table:OnUserLeave(nUserId)
	self:Print("OnUserLeave,nUserId_%d",nUserId)
	local tUser =self.arrUsers[nUserId]
	assert(tUser~=nil)

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

function Table:OnUserEnter(tUserInfo,isKeepStand)
	local nUserId =tUserInfo.nUserId
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
		item.nGold =(100* self.nBigBlind)		--免费试玩房的积分
	end
	if self:MatchRoomId() ==0 then
		item.isAddFreeTimeIfStart =true
	end
	self.arrUsers[item.nUserId] =item
	return true
end

function Table:_SetLeaveTable(nUserId)
	self.arrUsers[nUserId]=nil
	self.tInterFace._LeaveTable(nUserId,self)
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
