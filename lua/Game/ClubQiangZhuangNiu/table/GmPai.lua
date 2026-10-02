-- 编码 UTF8
package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path
GmPai = {}

function GmPai:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	
	t.tPaiDui =
	{
		isGm = false,
		arrCard = {}
	}
	-- 手牌队列
	t.tHandCard =
	{

	}
	-- 要牌队列
	t.tWaitCard =
	{
	
	}
	
	--控牌要的牌
	t.tConrolPai = {

	}
	return t
end

function GmPai:Del()
	self = nil
end


return GmPai