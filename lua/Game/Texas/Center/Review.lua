

local Review = {}


function Review:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tData={}
	return t
end

---
function Review:Init(sPaijuId,nSmallBlind,nBigBlind,nCapacity,nOperateTime,nZhuaTou)
	local tem ={sPaijuId=sPaijuId,nSmallBlind=nSmallBlind,nBigBlind=nBigBlind,nCapacity=nCapacity,nZhuaTou=nZhuaTou}
	tem.arrUserPartIn ={}
	tem.arrEvent ={}
	tem.arrUserSettle={}
	tem.arrPool={}
	tem.nOperateTime=nOperateTime
	self.tData =tem
end
---
function Review:AddUser(nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn)
	local arr ={nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn}
	table.insert(self.tData.arrUserPartIn,arr)
end
---
function Review:SetBankerPos(nBankerPos)
	self.tData.arrEvent[1]={-10,nBankerPos}
end
---
function Review:BlindBet(nSmallPos,nSmallBet,nBigPos,nBigBet)
	self.tData.arrEvent[2] ={-11,{nSmallPos,nSmallBet},{nBigPos,nBigBet}}
end

function Review:ZhuaTouBet(nPos,nBet)
	self.tData.arrEvent[2] =self.tData.arrEvent[2] or {-14}
	table.insert(self.tData.arrEvent[2],{nPos,nBet})
end
---
function Review:DealHoleCard(nPos,arrCard,nCardType)
	self.tData.arrEvent[3] =self.tData.arrEvent[3] or {-12}
	local arr ={nPos,arrCard,nCardType}
	table.insert(self.tData.arrEvent[3],arr)
end
---
function Review:DoOp(nPos,nOp,nBet)
	local arr ={nOp,nPos,nBet}
	table.insert(self.tData.arrEvent,arr)
	assert(#self.tData.arrEvent>3)
end
---
function Review:LeaveInPlaying(nPos)
	local arr ={-8,nPos}
	table.insert(self.tData.arrEvent,arr)
	assert(#self.tData.arrEvent>3)
end
---
function Review:DealCard(arrNewCard,arrUsersCardType,arrPool,isShowCard)
	local arr ={-9,arrNewCard,arrUsersCardType,arrPool,isShowCard}
	table.insert(self.tData.arrEvent,arr)
	assert(#self.tData.arrEvent>3)
end
---
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
		table.insert(self.tData.arrUserSettle,arr)
	end
end
function Review:GetData()
	return self.tData
end


--[[
--回顾数据解析
{
	"sPaijuId":"",										//牌局id
	"nSmallBlind":50,									//小盲注数额
	"nBigBlind":100,									//大盲注数额
	"nZhuaTou":200,										//抓头数额
	"nCapacity":6,										//桌子座位数(6或9)
	"nOperateTime":10,									//
	//参与本局游戏的玩家 (nTakeIn为游戏开始前的可用筹码(定庄前))
	"arrUserPartIn":[									
			[10022,1,"","nickName",1,"",10000],         //nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn
			[10023,2,"","nickName",1,"",10000],			//nUserId,nSitId,sFaceId,sName,nSex,sShopAcc,nTakeIn
		],
	//事件序列
	"arrEvent":[											 
				[-10,4],								 		//定庄(-10) 庄家位置为4
				[-11,[2,50],[3,100] ],					 		//大小盲抓头下注(-11),小盲位置2下注50,大盲位置3下注100,抓头位置4下注200
				[-12,[1,[17,18],0],[2,[19,20],0] ],				 //发底牌(-12);位置1发17 18,牌型为0;位置2发19 20,牌型为0
				[-5,1],									 		//位置1玩家 弃牌(-5)		
				[-1,2],									 		//位置2玩家 ALLIn(-1)
				[-2,3],											 //位置3玩家 过牌(-2)
				[-6,4,100],								 		//位置4玩家 跟注100(-6)
				[-3,5,100],								 		//位置5玩家 加注100(-3)
				[-8,2],									 		//位置2玩家 中途站起(-8)
				[-9,[17,18,19],[0,0,0,2,0,0],[100,200],false],  //发牌(-9), 新增的牌, 位置1到6玩家牌型, 分池, 是否翻底牌后再发公共牌(只翻非弃牌玩家的底牌)
				[-14,[2,50] ],					                //抓头下注(-14),抓头位置2下注50
			 ],
	//参与本局结算的玩家
	"arrUserSettle":[
			[nSitId,arrCombinedCards,nCardType,arrGoldGet,isWin,nProfit,nCmpValue,isShowCardWhenEnd,nCurGold],
			[nSitId,arrCombinedCards,nCardType,arrGoldGet,isWin,nProfit,nCmpValue,isShowCardWhenEnd,nCurGold],
		   ],
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