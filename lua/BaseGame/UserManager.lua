--[[
	负责用户管理，管理登入该服务器的所有用户
]]
UserManager = 
{
	
}


-- 创建一个对象
function UserManager:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tUserArr = {}
	t.enumUserType = 
	{
		nMiss 	= -1, --未知
		nUser 	= 0,  --玩家
		nLooker = 1,  --旁观
	}
	return t
end

-- 增加一个用会信息
function UserManager:AddUser(tUser)
	if not tUser then
		return false
	end
	--[[
	if self.tUserArr[tUser.nUserID] then
		return false
	end
	]]
	self.tUserArr[tUser.nUserID] = tUser
	return true
end

-- 删除用户
function UserManager:DelUser(tDelUser)

	local tCurUser = self.tUserArr[tDelUser.nUserID]
	if tCurUser ~= nil then
		tCurUser:Del()
		self.tUserArr[tDelUser.nUserID] = nil
	end 

end

--获取玩家信息
function UserManager:GetUserInfo(nUserID)
	if nUserID == nil then
		return nil
	end
	return self.tUserArr[nUserID]
end

--获取clientId玩家
function UserManager:LogAllUserData()
	for _, v in pairs(self.tUserArr) do
		tBase.Log("UserID".._)
	end
end

--通过用户连接获取用户
function UserManager:GetUserInfoByLink(sClientID)
	for _, v in pairs(self.tUserArr) do
		if v.sClientID == sClientID then
			return v
		end
	end
	return
end

return UserManager

