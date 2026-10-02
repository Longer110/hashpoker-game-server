--[[
	用户信息，负责用户信息的存取
]]

local tBase = require("base")           -- 基础功能接口
local Define =require("Define")
local tAlg =require("GameAlg")
local publicApi =require("publicApi")
local PublicDefine =require("PublicDefine")
local RedisCahche =require("RedisCahche")
local cjson    = require("cjson")
local tAiGet =require("AiGet")
local UserOp =PublicDefine.UserOp


--从[nMin,nMax]随机一个数,当isLess为true时产生比较小的数,否则产生比较大的数
local function RandomNum(nMin,nMax,isLess)
	local nRandom =math.random()
	local nHit =1
	for i=1,100 do
		if nRandom<= (i*0.01)^2 then
			nHit= i
			break
		end
	end
	if isLess then nHit =(101 -nHit) end
	local nLen =nMax -nMin
	local a= math.floor(nMin +(nLen*nHit/100) +0.5)
	if a<=nMax then return a end
	return nMax
end
--离散随机变量
--arrDistributiveLaw ={{p=0.3,X=1} ,{p=0.2,X=2} ,{p=0.5,X=3} }  --分布率,所有p相加必需为1
local function XFunc(arrDistributiveLaw)
	local arr ={}
	for _,item in ipairs(arrDistributiveLaw) do
		local tailP =arr[#arr] or 0
		local split =tailP +item.p
		table.insert(arr,split)
	end
	if #arr==0 then
		return
	end
	local nR =math.random()
	for dex,v in ipairs(arr) do
		if nR<v then
			return arrDistributiveLaw[dex].X
		end
	end
	return nil
end



local User = {}
function User:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self

	t.nUserId = 0
	t.sName = ""
	t.nSex = 0
	t.sFaceID = "1"
	t.nGold =0
	t.isAndroid = false
	t.nRoomId =nil
	t.nSitId =nil
	t.tTable = nil
	t.nShopId =-1
	t.nGroupId=-1
	t.arrGmCmd={}
	t.nPlayCnt =0						--局数
	t.nPlayCntMax =math.random(5,20)	--玩多少局了离开
	
	t.tTableIdToTable={}
	t.nRaiseCnt =0						--当轮加注次数
	t.nRoundBet =0						--当轮下注
	t.nBetSum =0						--当局累计下注
	t.arrHoleCard={}					--本局手牌
	t.arrCommunityCards={}				--本局当前公共牌
	t.nBigBlind =1						--大盲
	t.nBalance =0						--当前筹码余额
	t.nRoundActionCnt =0				--当轮已操作的次数
	t.isOrderToLeave=false				--是否收到外部指令要求离开桌子
	t.isPlaying=false					--是否正在游戏中
	t.ToLeaveTimerId=nil
	t.nElapseAiReq=0					--ai请求所用时间 ms
	t.sAiScenceBody=nil					--ai场景
	t.sAiRes=nil						--ai返回

	t.nActModel =nil					--0:放水模式(150倍大盲内，机器人放开下注) 1:自然模式(牌越好注越大) 2:预知输赢模式(真人唬不住机器人) nil:独立随机使用一个模式
	return t
end


--根据胜率和人数决定 "最高总下注建议值"
--一个分段函数
local function HighestBlind(nWinRate,nPlayerCnt,nCommunityCardsCnt)
	local B =1/nPlayerCnt	
	local N =B*0.75					--值越大越谨慎(怕死)
	local nHighestBlindCnt =70		--该值越大斜率越大 (越大机器人越勇敢)
	if nWinRate < N then			--胜率低于该值时，为烂牌，不跟注
		return 0
	end
	if nCommunityCardsCnt==0 then
		if nPlayerCnt==2 and nWinRate>0.6 then
			return 10000
		end
		if nPlayerCnt==3 and nWinRate>0.4 then
			return 10000
		end
		if nWinRate>2*B then
			return 10000
		end
	end
	if nWinRate> 0.7 then			--大于该胜率时一般为超强牌，跟任何注
		return 10000
	end
	local k =(nHighestBlindCnt-1) /(1-N)
	local a =nHighestBlindCnt-k
	local Y =k*nWinRate +a
	return Y
end


local arrDistributiveLaw ={{p=0.3,X=0} ,{p=0.15,X=1} ,{p=0.1,X=2},{p=0.1,X=3} ,{p=0.1,X=4} ,
							{p=0.05,X=5} ,{p=0.05,X=6} ,{p=0.05,X=7},{p=0.05,X=8} ,{p=0.05,X=9} }

local function RaiseValue(tRaiseChoice,nBigBlind)
	if tRaiseChoice==nil then
		return 0
	end
	local x =XFunc(arrDistributiveLaw)
	if x==0 or x==nil then
		return tRaiseChoice.nMin
	end
	local v =tRaiseChoice.nMin +math.random((x-1)*nBigBlind,x*nBigBlind)
	v =math.min(v,tRaiseChoice.nMax)
	return v
end

function User:OnMsgHandle(strProto,tData)
	if strProto =="DeZhouStartNotify" then			--游戏开始通知
		self:_StopToLeave()
		self.nPlayCnt =self.nPlayCnt +1
		self.isPlaying=true
		self.nRoundBet =0							--当轮下注
		self.nBetSum =0								--当局累计下注
		self.arrHoleCard={}							--本局手牌
		self.arrCommunityCards={}					--本局当前公共牌
		self.nBigBlind =self.tTable:GetBigBlind()   --大盲
		self.nBalance =tData.nTakeIn				--当前筹码余额
		self.nRoundActionCnt =0
		self.nLatelyRaisePos =nil					--最近加注的玩家座位号(不包括自己)
		self.nLatelyOpPos =nil						--最近操作的玩家座位号(不包括自己)
		for _,v in ipairs(tData.arrHoleCards) do
			table.insert(self.arrHoleCard,v)
		end
		for _,v in ipairs(tData.arrUsersBet) do
			if v.nPos ==self.nSitId then
				self.nRoundBet =self.nRoundBet +v.nBet
				self.nBetSum   =self.nBetSum +v.nBet
			end
		end

		self.nActModel =self.tTable:RobotActModel()
		if self.nActModel ==nil then
			local nRand =math.random(1,100)
			if nRand<40 then
				self.nActModel =1
			elseif nRand<75 then
				self.nActModel =0
			else
				self.nActModel =2
			end
		end
		self.nRaiseCnt =0
		self.tTable:Print("Robot Pos_%d nActModel:%s",self.nSitId,tostring(self.nActModel))
		return
	end

	if strProto =="InsurNotify" then					--进入保险阶段通知
		local nUserIdOfInsur =nil
		for _,v in ipairs(tData.tInsurPanelData.arrRelevantUser) do
			if v.nOuts ==-1 then
				nUserIdOfInsur =v.nUserId
				break
			end
		end
		if self.nUserId ~=nUserIdOfInsur then
			return
		end
		local nLostRate =0								--输的概率(值100即为100%)
		for _,v in ipairs(tData.arrWinRate) do
			if v.nPos ==self.nSitId then
				nLostRate =(100 -v.nWinRate)
				break
			end
		end
		if nLostRate<=20 and (not tData.tInsurPanelData.isMustBuy) then							
			self:_ToInsurBuy(-1)						--不买保险
			return
		end
		
		--决定购买保险的数额
		local arrPlan={}
		for _,v in ipairs(tData.tInsurPanelData.arrInsurancePlan) do
			table.insert(arrPlan,{nPlanId=v.nPlanId,nCosts=v.nCosts})
		end
		table.sort(arrPlan,function(A,B) return A.nCosts<B.nCosts end)	--按nCosts从小到大排序
		if #arrPlan ==0 then
			self:_ToInsurBuy(-1)						--不买保险
			return
		end
		-- local nDex =nLostRate//(100//#arrPlan)
		local nDex = math.floor(nLostRate / math.floor(100 / #arrPlan))
		nDex =math.max(nDex,1)
		nDex =math.min(nDex,#arrPlan)
		local nPlanId =arrPlan[nDex].nPlanId

		self:_ToInsurBuy(nPlanId,tData.tInsurPanelData.tRemaining.arrOuts)		--保本
		return
	end


	if strProto =="InsurDealNotify" then				--保险发牌通知
		table.insert(self.arrCommunityCards,tData.nCard)
		return
	end

	if strProto =="DeZhouDealNotify" then				--公共牌新增通知
		self.nRoundBet =0
		self.nRoundActionCnt=0
		for _,v in ipairs(tData.arrCards) do
			table.insert(self.arrCommunityCards,v)
		end
		self.nRaiseCnt =0
		return	
	end
	if strProto =="DeZhouOpNotify" then					--有玩家操作通知
		if tData.nPos ==self.nSitId then
			self.nRoundBet =self.nRoundBet +(tData.nBet or 0)
			self.nBetSum   =self.nBetSum +(tData.nBet or 0)
			self.nBalance =self.nBalance -(tData.nBet or 0)
			self.nRoundActionCnt =self.nRoundActionCnt +1
			if tData.nOp ==UserOp.nFold then
				self:_ToChatReq(self.nLatelyRaisePos,{1,4,5}) --炸弹 番茄 抓鸡表情
			end
			return
		end
		self.nLatelyOpPos =tData.nPos
		if tData.nOp ==UserOp.nRaise or tData.nOp ==UserOp.nAllIn then
			self.nLatelyRaisePos =tData.nPos
			return
		end
		return 
	end
	if strProto =="DeZhouTableResetNotify" then			--桌子重置通知
		self.isPlaying=false
		tBase.Log("Robot_%d nPlayCnt:%d nPlayCntMax:%d",self.nUserId,self.nPlayCnt,self.nPlayCntMax)
		if self:_IsLeaveWhenEnd()then
			self:_ToLeave()
			return
		end
		self:_ToLeave(math.random(10,25))		--一段时间不开始游戏就离开
		return
	end
	if strProto =="DeZhouSettleNotify" then				--结算通知
		for _,v in ipairs( tData.arrUsersWin) do
			if v.nPos ==self.nSitId then
				if v.nProfit>0 then
					self:_ToChatReq(self.nLatelyOpPos,{2,3,6})	--干杯 亲吻 玫瑰
				end
				if v.nCurGold <0.01 then						--0金币时离开
					self.tTable:Print("Robot NoGold SetTo Leave Pos:%d",self.nSitId)
					self:SetLeaveWhenEnd()
				end
				return
			end
		end
		return
	end

	if strProto =="UserOpTimeOut" then			--非正式协议,仅仅是用来通知机器人有人超时
		if tData.nTimeOutCnt and tData.nTimeOutCnt==2 then
			self:_ToChatReq(tData.nPos,{1,4})	--番茄 炸弹
		end
		return
	end

	if strProto =="DeZhouOperationNotify" then
		if tData.nPos~=self.nSitId then
			return
		end
		self.nElapseAiReq =0
		self.sAiScenceBody=nil
		self.sAiRes=nil
		self.sAiUrl=nil
		local tOperation =tData.tOperation
		local arrHoleCard,arrCommunityCards =self.tTable:_GetCards(self.nSitId) --self.arrHoleCard,self.arrCommunityCards --手牌与公共牌
		local nCommunityCardsCnt =#arrCommunityCards							--公共牌个数
		
		local nPlayerCnt =self.tTable:GetPlayerCnt()							--当前非弃牌玩家数量
		local nWinRate =tAlg.WinRate(nPlayerCnt,arrHoleCard,arrCommunityCards) 	--当前牌胜率 [0,1]

		local tBigUserInfo = self.tTable:_GetBigUserInfo()						--当前最大牌玩家
		local nBalance =self.tTable:_GetBalance(self.nSitId) or 0				--当前自己筹码数量		
		local isBigUser =(self.nSitId ==(tBigUserInfo or {}).nPos)				--自己是否为最大牌玩家
		local isBigCards =(nWinRate >=(0.8/nPlayerCnt)) 						--当前是否为好牌
	
		local isDanger =false													--当前是否危险 
	 	if not (tBigUserInfo and tBigUserInfo.isAndroid and nBalance<=tBigUserInfo.nChipSum) then
			isDanger =true
		end
		local  nHighestBlind =HighestBlind(nWinRate,nPlayerCnt,nCommunityCardsCnt)
		local nHighestBet =nHighestBlind *self.nBigBlind						--当局自己的最高总下注建议值
		if nHighestBlind>=100 then
			nHighestBet =nBalance +self.nBetSum
		end
		
		local nRaiseLow=RaiseValue(tOperation.tRaiseChoice,self.nBigBlind)
		local nRaiseMin,nRaiseMax =0,0
		if tOperation.tRaiseChoice then
			nRaiseMin =tOperation.tRaiseChoice.nMin or 0
			nRaiseMax =tOperation.tRaiseChoice.nMax or 0
		end

		--跟注前进行判断，如果跟注后余额变得很小，干脆AllIn
		local function TryDoOpCAllIn()
			if (nBalance -tOperation.nOpB)<(self.nBigBlind/2) and tOperation.nOpC ==UserOp.nAllIn then
				self:_ToOpReq(3,0)
				return true
			end
			return false
		end

		--非预知输赢模式
		local function NormalAct()
			if tOperation.nOpB ==UserOp.nAllIn  then
				if nBalance< self.nBigBlind then
					self:_ToOpReq(2,0)
					return
				end
				if (nBalance+self.nBetSum) <=nHighestBet then
					self:_ToOpReq(2,0)
					return
				end
				self:_ToOpReq(1,0)
				return
			end
			if tOperation.nOpB ==UserOp.nPass then
				if (self.nBetSum +nRaiseMin) >= nHighestBet then
					self:_ToOpReq(2,0)
					return
				end
				local nRaiseMaxC =math.min(nHighestBet-self.nBetSum,nRaiseMax)
				if nRaiseMaxC<=0 or nRaiseMaxC <= nRaiseMin then 
					self:_ToOpReq(2,0)
					return
				end
				if self.nRoundActionCnt >0 then
					self:_ToOpReq(2,0)
					return
				end
				local nPRaise = ((nRaiseMaxC-self.nBetSum) / (2*nRaiseMaxC)) + (nCommunityCardsCnt/10)
				nPRaise =nPRaise*100
				if self.nRaiseCnt>0 or math.random(1,100) >= nPRaise then
					self:_ToOpReq(2,0)
					return
				end
				nRaiseMaxC =publicApi.Floor_2(nRaiseMaxC)
				local nRaiseC =RandomNum(nRaiseMin,nRaiseMaxC,true)
				self:_ToOpReq(3,nRaiseC)
				return
			end
			if tOperation.nOpB>0 then
				if (self.nBetSum + tOperation.nOpB) > nHighestBet then
					self:_ToOpReq(1,0)
					return
				end
				if (self.nBetSum + nRaiseMin) > nHighestBet then
					if TryDoOpCAllIn() then return end
					self:_ToOpReq(2,0)
					return
				end
				if self.nRoundActionCnt >0 then
					if TryDoOpCAllIn() then return end
					self:_ToOpReq(2,0)
					return
				end
				local nRaiseMaxC =math.min(nHighestBet - self.nBetSum,nRaiseMax)
				if nRaiseMaxC<=0 or nRaiseMaxC <= nRaiseMin then 
					if TryDoOpCAllIn() then return end
					self:_ToOpReq(2,0)
					return
				end
				local nPRaise = ((nRaiseMaxC-self.nBetSum) / (2*nRaiseMaxC)) + (nCommunityCardsCnt/10)
				nPRaise =nPRaise*100
				if self.nRaiseCnt>0 or math.random(1,100) >= nPRaise then
					if TryDoOpCAllIn() then return end
					self:_ToOpReq(2,0)
					return
				end
				nRaiseMaxC =publicApi.Floor_2(nRaiseMaxC)
				local nRaiseC =RandomNum(nRaiseMin,nRaiseMaxC,true)
				self:_ToOpReq(3,nRaiseC)
				return
			end
		end

		--预知输赢模式
		local function ForeseeAct()
			if tOperation.nOpB ==UserOp.nAllIn  then
				if isBigUser or ((not isDanger) and isBigCards) then
					self:_ToOpReq(2,0)
					return
				end
				self:_ToOpReq(1,0)
				return
			end
			if tOperation.nOpB ==UserOp.nPass then
				if isDanger or (not isBigCards) or tOperation.nOpC==UserOp.nRaiseBan  then
					self:_ToOpReq(2,0)
					return
				end
				if self.nRaiseCnt==0 and math.random(1,100)<=(35 + (nCommunityCardsCnt*10)) then
					self:_ToOpReq(3,nRaiseLow)
					return
				end
				self:_ToOpReq(2,0)
				return
			end
			if tOperation.nOpB>0 then		--跟注xx
				if isDanger then
					if tOperation.nOpB> (self.nBigBlind *math.random(1,4)) then
						self:_ToOpReq(1,0)
						return
					end
					if isBigCards and math.random(1,100)<=50 then
						if TryDoOpCAllIn() then return end
						self:_ToOpReq(2,0)
						return
					end
					self:_ToOpReq(1,0)
					return
				end
				if tOperation.nOpC ==UserOp.nRaiseBan then
					if isBigUser or isBigCards then
						if TryDoOpCAllIn() then return end
						self:_ToOpReq(2,0)
						return
					end
					self:_ToOpReq(1,0)
					return
				end
				if isBigUser or isBigCards then
					if self.nRaiseCnt==0 and math.random(1,100)<=(20 + (nCommunityCardsCnt*5)) then
						self:_ToOpReq(3,nRaiseLow)
						return
					end
					if TryDoOpCAllIn() then return end
					self:_ToOpReq(2,0)		--跟注
					return
				end
				self:_ToOpReq(1,0)
				return
			end
		end

		--放水模式 self.tTable.nRobotBetSum
		local function RelaxAct()
			local nTopLimitRelax =self.nBigBlind *120		--所有机器人的总下注不能超过该值
			if tOperation.nOpB ==UserOp.nAllIn  then
				if (nBalance +self.tTable.nRobotBetSum) <=nTopLimitRelax then
					self:_ToOpReq(2,0)
					return
				end
				self:_ToOpReq(1,0)
				return
			end
			if tOperation.nOpB ==UserOp.nPass then
				if tOperation.nOpC==UserOp.nRaiseBan or (nRaiseLow +self.tTable.nRobotBetSum)>nTopLimitRelax then
					self:_ToOpReq(2,0)
					return
				end
				if self.nRaiseCnt==0 and math.random(1,100)<=25 then
					self:_ToOpReq(3,nRaiseLow)
					return
				end
				self:_ToOpReq(2,0)
				return
			end
			if tOperation.nOpB>0 then		--跟注xx
				if (tOperation.nOpB +self.tTable.nRobotBetSum)>nTopLimitRelax then
					self:_ToOpReq(1,0)
					return
				end
				if tOperation.nOpC ==UserOp.nRaiseBan then
					if TryDoOpCAllIn() then return end
					self:_ToOpReq(2,0)
					return
				end
				if self.nRaiseCnt==0 and math.random(1,100)<=25 and (nRaiseLow +self.tTable.nRobotBetSum)<=nTopLimitRelax then
					self:_ToOpReq(3,nRaiseLow)
					return
				end
				if TryDoOpCAllIn() then return end
				self:_ToOpReq(2,0)		--跟注
				return
			end
		end

		local function LocalAi()
			if self.nActModel==1 then
				NormalAct()	 --正常输赢模式
			elseif self.nActModel==2 then
				ForeseeAct() --预知输赢模式
			elseif self.nActModel==0 then
				RelaxAct()	--放水模式
			else
				NormalAct()
			end
		end
		local function RemoteAiError(sError)
			local sMsg =string.format("AiError,%s Elapse:%dms sUrl:%s",sError,self.nElapseAiReq,(self.sAiUrl or "nil"))
			local sDetail =string.format("AiError Detail,sBody:%s sRes:%s",(self.sAiScenceBody or "nil"),(self.sAiRes or "nil"))
			self.tTable:Print(sMsg)
			self.tTable:Print(sDetail)
			tBase._OnMonitorInfo(sMsg)
			tBase._OnMonitorInfo(sDetail)
			LocalAi()
		end

		local function TryFollowOrAllIn()
			if tOperation.nOpB>0 then
				self:_ToOpReq(2,0)
				return "follow"
			end 
			if tOperation.nOpB ==UserOp.nAllIn then
				self:_ToOpReq(2,0)
				return "AllIn"
			end
			if tOperation.nOpC==UserOp.nAllIn  then
				self:_ToOpReq(3,0)
				return "AllIn"
			end
		end

		if self.tTable.isUseAi then
			local nReqTime =tBase.GetTime()
			local funcRes = function(sRes,nCode)  
				self.nElapseAiReq =tBase.GetTime() - nReqTime
				self.sAiRes =sRes
				local isSuccee,tRlt =pcall(cjson.decode,sRes)   
				if not isSuccee then
					RemoteAiError("json decode")
					return
				end

				local nActionId =tRlt.nAction or -1
				local nRaiseBet =tRlt.nAddSource or 0
				local sEcho =tRlt.sEcho or "-1"
				self.tTable:Print("sEcho:%s nActionId:%d nRaiseBet:%.2f",sEcho,nActionId,nRaiseBet)

				if nActionId ==0 then				--跟注
					if tOperation.nOpB>0 or tOperation.nOpB ==UserOp.nAllIn then
						self:_ToOpReq(2,0)
					elseif tOperation.nOpC==UserOp.nAllIn  then
						self:_ToOpReq(3,0)
					else
						RemoteAiError("Follow")
					end
					return
				end
				if nActionId ==1 then				--加注
					if nRaiseBet>=nRaiseMin and nRaiseBet<=nRaiseMax and nRaiseMin >0 then
						self:_ToOpReq(3,nRaiseBet)
						return
					end
					local sE =TryFollowOrAllIn()
					self.tTable:Print("Turn Raise To %s",tostring(sE))
					if not sE then
						RemoteAiError("Raise")
					end
					return
				end
				if nActionId ==2 then				--过牌
					if tOperation.nOpB ==UserOp.nPass then
						self:_ToOpReq(2,0)
					else
						RemoteAiError("Pass")
					end
					return
				end
				if nActionId ==3 then			 	--弃牌
					self:_ToOpReq(1,0)
					return
				end
				if nActionId ==4 then				--AllIn
					if tOperation.nOpB ==UserOp.nAllIn  then
						self:_ToOpReq(2,0)
					elseif tOperation.nOpC==UserOp.nAllIn  then
						self:_ToOpReq(3,0)
					elseif tOperation.nOpC==UserOp.nRaise then
						self:_ToOpReq(3,nRaiseMax)
					else
						RemoteAiError("AllIn")
					end
					return
				end
				RemoteAiError("nActionIdWrong")
			end	

			local funcError = function(nCode)
				self.nElapseAiReq =tBase.GetTime() - nReqTime
				local sMsg =string.format("HttpCode:%s",tBase.tostring(nCode))
				RemoteAiError(sMsg)
			end  
			--local sUrl = "http://192.168.0.225:7861/step"
			local tAiSc,sUrl=self.tTable:GetAiScence(self.nUserId,tOperation)
			self.sAiScenceBody =cjson.encode(tAiSc)
			self.sAiUrl =sUrl
			if sUrl then
				UrlRequest(sUrl, funcRes, funcError,"POST",self.sAiScenceBody)
			else
				RemoteAiError("sAiUrl is nil")
			end
		else
			LocalAi()
		end

	end
end

function User:_ToLeave(nSeconds)
	if not nSeconds then  -- 立即离开
		tBase.Log("_ToLeave  Robot_%d 	立即离开 ",self.nUserId)
		self.tTable:DeZhouStanpUpReq({nUserId=self.nUserId})
		return 
	end 
	local fTemFunc =function()
		self.ToLeaveTimerId=nil
		--self.tTable:OnUserLeave(self.nUserId)
		self.tTable:DeZhouStanpUpReq({nUserId=self.nUserId})
	end
	self:_StopToLeave()
	local nSeconds =nSeconds or 0.05
	self.ToLeaveTimerId=  self.tTable.TimerForAndroid:DelayCall(nSeconds*1000,fTemFunc) 
end

function User:_StopToLeave()
	if self.ToLeaveTimerId then
		self.tTable.TimerForAndroid:KillTimer(self.ToLeaveTimerId)
		self.ToLeaveTimerId =nil
	end
end


function User:_ToChatReq(nTarget,arrChatId)
	if nTarget==nil or #arrChatId ==0 or self.nSitId==nTarget then
		return
	end
	if math.random(1,100)<95 then
		return 
	end
	local nRd =math.random(1,#arrChatId)
	local nChatId =arrChatId[nRd]
	local fTemFunc =function()
		self.tTable:OnReqHandle(self.nUserId,"DeZhouChatReq",{nTarget=nTarget,nChatId=nChatId})
	end
	local nRandomMSeconds =math.random(1000,3000)
	self.tTable.TimerForAndroid:DelayCall(nRandomMSeconds,fTemFunc)
end

function User:_ToInsurBuy(nPlanId,arrOuts)
	local fTemFunc =function()
		self.tTable:OnReqHandle(self.nUserId,"InsurBuyReq",{nPlanId=nPlanId,arrOuts=arrOuts})
	end
	local nRandomMSeconds =math.random(1000,3500)
	self.tTable.TimerForAndroid:DelayCall(nRandomMSeconds,fTemFunc)
end

function User:_ToOpReq(nOpButton,nRaise)
	if nRaise and nRaise>0 then
		self.nRaiseCnt =self.nRaiseCnt +1
	end

	local DeZhouOpReq ={nOpButton=nOpButton,nRaise=nRaise}
	local fTemFunc =function()
		self.tTable:OnReqHandle(self.nUserId,"DeZhouOpReq",DeZhouOpReq)
	end
	local nRandomNum =math.random(1,100)
	local nRandomMSeconds =1000 --思考时间(毫秒)
	if nRandomNum<20 then
		nRandomMSeconds =math.random(1000,2000)
	elseif nRandomNum<50 then
		nRandomMSeconds =math.random(1500,2500)
	elseif nRandomNum<80 then
		nRandomMSeconds =math.random(2000,4500)
	else
		nRandomMSeconds =math.random(4000,9500)
	end

	nRandomMSeconds =nRandomMSeconds -self.nElapseAiReq
	nRandomMSeconds =math.max(nRandomMSeconds,500)
	self.tTable.TimerForAndroid:DelayCall(nRandomMSeconds,fTemFunc) 
end

--DeZhoTakeInReq
function User:_ToTakeInReq()
	local nTakeIn =self.tTable:RandomTakeInForAndroid()	--买入数量
	local nIsAuto =0									--是否每局自动买入 1:是 其它:否
	if not nTakeIn then
		return
	end
	if math.random(1,100)<25 then nIsAuto=1 end
	local fTemFunc =function()
		self.ToTakeInTimerId =nil
		self.tTable:OnReqHandle(self.nUserId,"DeZhoTakeInReq",{nBuyTo=nTakeIn,nIsAuto=nIsAuto})
	end
	self.ToTakeInTimerId = self.tTable.TimerForAndroid:DelayCall(500,fTemFunc) 
end

function User:_StopToTakeIn()
	if self.ToTakeInTimerId then
		self.tTable.TimerForAndroid:KillTimer(self.ToTakeInTimerId)
		self.ToTakeInTimerId =nil
	end
end


--立即离开
function User:SetLeaveImmediate()
	if self.isPlaying then
		return false
	end
	self:_ToLeave(0.1)
	return true
end

--一局结束后离开
function User:SetLeaveWhenEnd()
	if self:_IsLeaveWhenEnd() then
		return true
	end
	self.isOrderToLeave=true
	return true
end

--一局结束后是否应该离开桌子
function User:_IsLeaveWhenEnd()
	if self.nPlayCnt>=self.nPlayCntMax or self.isOrderToLeave then
		return true
	end
	return false
end


function User:EnterTable(tTable,nSitId)
	assert(tTable~=nil)
	self.tTableIdToTable[tTable:TableId()]=tTable
	self.tTable =tTable
	self.nSitId =nSitId
	if self.isAndroid then
		local arr =  RedisCahche.GetClubConfigAndroidPlayCnt(self.nGroupId)
		if arr and arr[1] and arr[2] then 
			self.nPlayCntMax = math.random(arr[1],arr[2])
		end 
		if tTable.nEventId then		--比赛桌
			self.nPlayCntMax =1000
		end
		self:_ToLeave(math.random(120,300))
		--self:_ToTakeInReq()
	end
	return true
end
function User:LeaveTable(sTableId)
	assert(sTableId~=nil)
	self.tTableIdToTable[sTableId]=nil
	if self.tTable and self.tTable:TableId()==sTableId then
		self:_StopToLeave() --针对机器人
		self:_StopToTakeIn()
		self.tTable =nil
		self.nSitId =nil
	end
end
function User:IsNoTable()
	local n=0
	for _,v in pairs(self.tTableIdToTable) do
		n=n+1
	end
	return (n==0)
end

function User:GetTable()
	return self.tTable
end

function User:IsAndroid()
	return self.isAndroid
end


return User

