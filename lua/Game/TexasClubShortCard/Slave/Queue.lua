
local Queue={}

function Queue:New()
	local t = {first = 0, last = -1}
	setmetatable(t, self)
	self.__index = self
	return t
end
function Queue:PushBack(value)
	self.last = self.last + 1
	self[self.last] = value
end
function Queue:PopFront()
    local first = self.first
    if first > self.last then
        return nil
    end
    local value = self[first]
    self[first] = nil
    self.first = first + 1
    return value
end
function Queue:GetLen()
    return (self.last -self.first +1)
end

return Queue

