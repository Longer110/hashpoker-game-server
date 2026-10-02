Table = {}

-- 创建一个对象
function Table:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.nPriKey = "-1"
	t.tUserIDArr = {} -- 用户数组
	t.nTableId = 0 -- 牌桌ID
	t.sPaiJuKey = "0" -- 牌局ID
	t.nStep = 0 -- 牌桌流程
	t.nRound = 0 -- 牌桌局数
	t.nGameId = 0 -- 游戏ID
	t.nRoomId = 0 -- 房间ID
	t.nGroupId = 0 -- 组ID
	t.bEnable = true -- 标识牌桌是否可用
	t.nMaxUser = 5 -- 牌桌最大用户
	for i = 1, t.nMaxUser do
		table.insert(t.tUserIDArr,0)
	end
	t.EmError = {
		UserOnTable = -2 -- 玩家已经在牌桌上
	}
	return t
end

-- 设置牌桌ID
function Table:SetTableId(nTableId)
	self.nTableId = nTableId
end

-- 获取牌桌的ID
function Table:GetTableId()
	return self.nTableId
end

-- 找到空余座位
function Table:FindFreeSid()
	for i = 1, #self.tUserIDArr  do
		if self.tUserIDArr[i] <= 0  then
			return i
		end
	end
	return 0
end


-- 设置牌桌最大人数（重新初始化）
function Table:SetTableMaxUser(nMaxUser)
	if nMaxUser <= 0 then
		return false
	end

	self.nMaxUser = nMaxUser
	self.tUserIDArr = {}
	for i = 1, self.nMaxUser do
		table.insert(self.tUserIDArr,0)
	end
	return true
end

-- 匹配游戏接口 
function Table:Matching(nGameId, nRoomId, nGroupId)
	if (nGameId == self.nGameId and nRoomId == self.nRoomId and nGroupId == self.nGroupId) then
		return true
	else
		return false
	end
end

-- 获取牌桌当前人数个数
function Table:GetCurUserCount()
	local nCount = 0
	for i = 1, #self.tUserIDArr  do
		if self.tUserIDArr[i] > 0 then
			nCount = nCount + 1
		end
	end
	return nCount
end

--  牌桌是否满人
function Table:IsUserFull()
	
	local nCount = self:GetCurUserCount()
	if nCount >= #self.tUserIDArr  then
		return true
	else
		return false
	end
end
-- 检查牌桌用户是否在牌桌上ture 在， false 不在
function Table:CheckUserInTable(nUserID)
	for i = 1, #self.tUserIDArr  do
		if self.tUserIDArr[i] == nUserID then
			return true
		end
	end
	return false
end

-- 增加一个牌桌用户
function Table:AddUser(nUserID)
	local  nFreeSid = self:FindFreeSid()
	if  nFreeSid > 0 then
		if self:CheckUserInTable(nUserID) then
			return self.EmError.UserOnTable
		end
		self.tUserIDArr[nFreeSid] = nUserID
	end
	return nFreeSid
end

-- 删除牌桌用户
function Table:DelUser(nUserID)
	for i = 1, #self.tUserIDArr  do
		if self.tUserIDArr[i] == nUserID then
			self.tUserIDArr[i] = 0 
			break;
		end
	end
end

-- 清除指定用户用户数据
function Table:ClearUserData(nUserID)
	
end
-- 牌桌清除数据
function Table:ClearData()
	
end

-- 设置key = val (自定义key - val)
function Table:SetData(tTableData)
	for key, val in pairs(tTableData) do
		self[key] = val 
	end
end

-- 获取key - val (自定义)
function Table:GetData(tTableData)
	for key, val in pairs(tTableData) do
		tTableData[key] = self[key]
	end
end
-- 牌桌删除
function Table:Del()
	self:ClearData()
	self = nil
end
function Table:Log()
	print("I am Table")
end
return Table