

local TbBind = {}

function TbBind:New(nUserCntOfTable)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.nUserCntOfTable=nUserCntOfTable

	t.tTableIdToInfo={}
	t.tUserIdToWDex={}
	return t
end

function TbBind:Init()
	self.tTableIdToInfo={}
	self.tUserIdToWDex={}
end

function TbBind:AddTable(sTableId)
	assert(self.tTableIdToInfo[sTableId]==nil)
	local t={}
	t.nUserCnt=0		--当前绑定的玩家数
	t.tUserIdTo={}		--当前绑定的玩家ID
	self.tTableIdToInfo[sTableId]=t
end

function TbBind:BindUserToTable(nUserId,sTableId)
	local tTbInfo =self.tTableIdToInfo[sTableId]
	if tTbInfo==nil then
		return false,"can not find table"
	end
	if tTbInfo.tUserIdTo[nUserId] then
		return false,"user already exist"
	end
	if tTbInfo.nUserCnt>=self.nUserCntOfTable then
		return false,"out of MaxUserCnt"
	end
	tTbInfo.tUserIdTo[nUserId]=true
	tTbInfo.nUserCnt =tTbInfo.nUserCnt +1
	return true,"succee"
end

function TbBind:UnBindUserFromTable(nUserId,sTableId)
	local tTbInfo =self.tTableIdToInfo[sTableId]
	if tTbInfo==nil then
		return false,"can not find table"
	end
	if not tTbInfo.tUserIdTo[nUserId] then
		return false,"user not exist"
	end
	tTbInfo.tUserIdTo[nUserId]=nil
	tTbInfo.nUserCnt =tTbInfo.nUserCnt -1
	return true,"succee"
end


function TbBind:GetWatchTable(nUserId)
	local arr={}
	local arrB={}
	for sTableId,tInfo in pairs(self.tTableIdToInfo) do
		if tInfo.nUserCnt>0 then
			table.insert(arr,sTableId)
		else
			table.insert(arrB,sTableId)
		end
	end
	if #arr==0 and #arrB==0 then
		return nil
	end
	if #arr==0 then
		arr=arrB
	end
	table.sort(arr)
	local nWDex =self.tUserIdToWDex[nUserId] or math.random(1,10)
	self.tUserIdToWDex[nUserId]=(nWDex+1)
	local nD=(nWDex % #arr)+1
	return arr[nD]
end

return TbBind
