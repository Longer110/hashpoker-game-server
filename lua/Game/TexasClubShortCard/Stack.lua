local Stack = {}

function Stack:New()
    local newObj = {top = 0}
    self.__index = self
    return setmetatable(newObj, self)
end

function Stack:Push(value)
    self.top = self.top + 1
    self[self.top] = value
end

function Stack:Pop()
    if self.top == 0 then
        return nil
    end
    local value = self[self.top]
    self[self.top] = nil
    self.top = self.top - 1
    return value
end

function Stack:Peek()
    if self.top == 0 then
        return nil
    end
    return self[self.top]
end

function Stack:IsEmpty()
    return self.top == 0
end

return Stack