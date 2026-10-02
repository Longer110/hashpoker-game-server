

local Review = {}


function Review:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tData={}
	t.tBetData = {}
	return t
end

---
function Review:Init(sPaijuId,nSmallBlind,nBigBlind,nCapacity,nOperateTime,nZhuaTou)
	local tem ={sPaijuId=sPaijuId,nSmallBlind=nSmallBlind,nBigBlind=nBigBlind,nCapacity=nCapacity,nZhuaTou = nZhuaTou}
	tem.arrUserPartIn ={}
	tem.arrEvent ={}
	tem.arrUserSettle={}
	tem.arrPool={}
	tem.arrBreakSettle={}
	tem.nOperateTime=nOperateTime
	self.tData =tem
	self.tBetData = {}
	self.nLookData = {}
	self.arrPenalty = {}
end
---
function Review:AddUser(nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn)
	local nInsure =0
	local arr ={nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn,nInsure}
	table.insert(self.tData.arrUserPartIn,arr)
end
---
function Review:SetBankerPos(nBankerPos)
	self.tData.arrEvent[1]={-10,nBankerPos}
end

function Review:SetPenaltyData(tPenaltyData)
	self.arrPenalty=tPenaltyData
end

function Review:GetPenaltyData()
	return self.arrPenalty
end

function Review:_AssertExist(nEvenId)
	local nLen =#self.tData.arrEvent
	local item =self.tData.arrEvent[nLen]
	if item and item[1] ==nEvenId then
		return item
	end
	item ={nEvenId}
	table.insert(self.tData.arrEvent,item)
	return item
end

function Review:PreAnteBet(nPos,nPreAnte)
	local item =self:_AssertExist(-13)
	table.insert(item,{nPos,nPreAnte})
end

---
function Review:BlindBet(nSmallPos,nSmallBet,nBigPos,nBigBet)
	table.insert(self.tData.arrEvent,{-11,{nSmallPos,nSmallBet},{nBigPos,nBigBet}})
end

function Review:ZhuaTouBet(nPos,nBet)
	self.tData.arrEvent[2] =self.tData.arrEvent[2] or {-14}
	table.insert(self.tData.arrEvent[2],{nPos,nBet})
end

function Review:ForceBlind(nPos,nBet)
	local item =self:_AssertExist(-11)
	table.insert(item,{nPos,nBet})
end

---
function Review:DealHoleCard(nPos,arrCard,nCardType)
	local item =self:_AssertExist(-12)
	table.insert(item,{nPos,arrCard,nCardType})
end

function Review:DoOp(nPos,nOp,nBet,nTimeUse)
	local nBet=nBet or 0
	local arr ={nOp,nPos,nBet,nTimeUse}
	table.insert(self.tData.arrEvent,arr)
	--assert(#self.tData.arrEvent>3)
end

---
function Review:LeaveInPlaying(nPos,nPaiJuProfit)
	local arr ={-8,nPos}
	table.insert(self.tData.arrEvent,arr)
	if nPaiJuProfit then
		table.insert(self.tData.arrBreakSettle,{nPos,nPaiJuProfit})
	end
end

---
function Review:DealCard(arrNewCard,arrUsersCardType,arrPool,isShowCard)
	local arr ={-9,arrNewCard,arrUsersCardType,arrPool,isShowCard}
	table.insert(self.tData.arrEvent,arr)
	-- assert(#self.tData.arrEvent>3)
end
---

function Review:DealLessCard(arrNewCard)
	local arr ={-15,arrNewCard}
	table.insert(self.tData.arrEvent,arr)
	assert(#self.tData.arrEvent>3)
end

function Review:Settle(arrPool,arrUsersWin)
	self.tData.arrPool =arrPool
	for _,v in ipairs(arrUsersWin) do
		local arrGoldGet ={}
		for _,v in ipairs(v.arrGoldGet) do
			table.insert(arrGoldGet,{v.nPotIdFrom,v.nGold})
		end
		local arr={}
		table.insert(arr,v.nPos)
		table.insert(arr,v.arrCombinedCards)
		table.insert(arr,v.nCardType)
		table.insert(arr,arrGoldGet)
		table.insert(arr,v.isWin)
		table.insert(arr,v.nProfit)
		table.insert(arr,v.nCmpValue)
		table.insert(arr,v.isShowCardWhenEnd)
		table.insert(arr,v.nCurGold)
		table.insert(arr,v.nChouShui)
		table.insert(arr,v.nBetSum)
		table.insert(arr,v.nHandProfit)
		table.insert(self.tData.arrUserSettle,arr)
	end
end

function Review:SettleMid(usersLeave)
	local arrGoldGet ={}
	for _,v in ipairs(usersLeave.arrGoldGet) do
		table.insert(arrGoldGet,{v.nPotIdFrom,v.nGold})
	end
	local arr={}
	table.insert(arr,usersLeave.nPos)
	table.insert(arr,usersLeave.arrCombinedCards)
	table.insert(arr,usersLeave.nCardType)
	table.insert(arr,arrGoldGet)
	table.insert(arr,usersLeave.isWin)
	table.insert(arr,usersLeave.nProfit)
	table.insert(arr,usersLeave.nCmpValue)
	table.insert(arr,usersLeave.isShowCardWhenEnd)
	table.insert(arr,usersLeave.nCurGold)
	table.insert(arr,usersLeave.nChouShui)
	table.insert(arr,usersLeave.nBetSum)
	table.insert(arr,usersLeave.nHandProfit)
	table.insert(self.tData.arrUserSettle,arr)
end


function Review:GetData()
	return self.tData
end

function Review:GetLookData()
	return self.nLookData
end

-- "lookData" = [{"nUserId": 111,"nType":1},{"nUserId": 111,"nType":1}]
function Review:SetLookData(info)
	table.insert(self.nLookData, info)
end

function Review:InsureProfit(nUserId,nInsure)
	for _,v in ipairs(self.tData.arrUserPartIn) do
		if v[1] ==nUserId then
			v[8]=nInsure
			break
		end
	end
end

function Review:InsureDetail(nInsureArr)
	if #nInsureArr == 0 then
		return
	end
	local arr ={-16}
	for _, detail in ipairs(nInsureArr) do
		table.insert(arr, detail)
	end
	table.insert(self.tData.arrEvent,arr)
	assert(#self.tData.arrEvent>3)
end

function Review:CacheCostGoldData(nUserId, name, cost, after, reason)
	table.insert(self.tBetData, {nUserId=nUserId, name = name, cost=cost, before=after-cost, after=after, reason=reason, time = os.date("%Y-%m-%d %H:%M:%S")})
end

function Review:DoPersist(sTableId, nGameId, sTableName, sPaiJuId)
	if not self.tBetData or #self.tBetData == 0 then
		return
	end
	RecordDbr.WriteRecordCost(sTableId, nGameId, sTableName, sPaiJuId, self.tBetData)
end

-- 个人开放消耗配置 [{nId = 1, open = 0, nCost = 10},{nId = 2, open = 0, nCost = 10},{nId = 3, open = 0, nCost = 10}]  付费看公牌1 付费看手牌2 付费切牌3
function Review:SetTableCost(nTableCost)
	self.tData.nTableCost = nTableCost
end

function Review:SetData(data)
	for k,v in pairs(data) do
		self.tData[k] = v
	end
end

--[[
--回顾数据解析
{
	"sPaijuId":"",										//牌局id
	"nSmallBlind":50,									//小盲注数额
	"nBigBlind":100,									//大盲注数额
	"nCapacity":6,										//桌子座位数(6或9)
	"nOperateTime":10,									//
	"nInsur" :0,										//保险(废弃,所有人共用一份数据,没法区分是谁)
	//参与本局游戏的玩家 (nTakeIn为游戏开始前的可用筹码(定庄前))
	"arrUserPartIn":[									
			[10022,1,"","nickName",1,"",10000,99],         //nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn,nInsur
			[10023,2,"","nickName",1,"",10000,88],			//nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn,nInsur
		],
	//事件序列
	"arrEvent":[											 
				[-10,4],								 		//定庄(-10) 庄家位置为4
				[-13,[1,100],[2,100],[3,200] ]					//前注(-13),位置1下100，位置2下100，位置3下200，
				[-11,[2,50],[3,100],[4,200] ],					 //大小盲下注(-11),小盲位置2下注50,大盲位置3下注100,位置4下强制盲注200
				[-12,[1,[17,18],0],[2,[19,20],0] ],				 //发底牌(-12);位置1发17 18,牌型为0;位置2发19 20,牌型为0
				[-5,1],									 		//位置1玩家 弃牌(-5)		
				[-1,2,100],									 	//位置2玩家 ALLIn(-1) 100
				[-2,3],											//位置3玩家 过牌(-2)
				[-6,4,100],								 		//位置4玩家 跟注100(-6)
				[-3,5,100],								 		//位置5玩家 加注100(-3)
				[-8,2],									 		//位置2玩家 中途站起(-8)
				[-9,[17,18,19],[0,0,0,2,0,0],[100,200],false],  //发牌(-9), 新增的牌, 位置1到6玩家牌型, 分池, 是否翻底牌后再发公共牌(只翻非弃牌玩家的底牌)
				[-14,[2,50] ],					                //抓头下注(-14),抓头位置2下注50
			 ],
	//参与本局结算的玩家(不包含中途站起的玩家)
	"arrUserSettle":[
			[nSitId,arrCombinedCards,nCardType,arrGoldGet,isWin,nProfit,nCmpValue,isShowCardWhenEnd,nCurGold,nChouShui],
			[nSitId,arrCombinedCards,nCardType,arrGoldGet,isWin,nProfit,nCmpValue,isShowCardWhenEnd,nCurGold,nChouShui],
		   ],
	//中途站起的玩家结算
	"arrBreakSettle":[
			[nSitId,nProfit],
			[nSitId,nProfit],
		]

	//结算时的分池
	"arrPool":[100,200,300],
	//arrUserSettle字段解析
	//arrCombinedCards=[1,2,3,4,5] 		//能组成最大牌型的5个牌
	//nCardType	=1						//牌型
	//arrGoldGet=[ [1,10],[2,30] ]		//从各个池处中获得的金币 ,分池1获得10 分池2获得30
	//isWin =false						//true时高亮牌型.
	//nProfit=10.1						//盈利.>0时显示"胜利"
	//nCmpValue=111						//牌型相同时,由该字段决定大小
	//isShowCardWhenEnd=false			//是否亮牌,true:是 其它:否
	//nCurGold=10.22					//玩家当前筹码值(结算后)		
}
]]

return Review