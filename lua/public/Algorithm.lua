local Algorithm = {}
local deQueue = {}
function deQueue:Ctor()
    self.deQueue = {first = 0, last = -1}
    self.dSave = {}
end
function deQueue:PushBack(stu)
	self.deQueue.last = self.deQueue.last + 1
	self.dSave[self.deQueue.last] = stu
end
function deQueue:PopFront()
    local first = self.deQueue.first
    if first > self.deQueue.last then return nil end
    local stu = self.dSave[first]
	self.dSave[first] = nil
    self.deQueue.first = first + 1
    return stu
end
function deQueue:PushFront(stu)
	self.deQueue.first = self.deQueue.first - 1
	self.dSave[self.deQueue.first] = stu
end
function deQueue:PopBack()
    local last = self.deQueue.last
    if last < self.deQueue.first then return nil end
    local stu = self.dSave[last]
    self.dSave[last] = nil
    self.deQueue.last = self.deQueue.last - 1
	return stu
end
function deQueue:GetLen()
    return (self.deQueue.last -self.deQueue.first +1)
end
Algorithm.deQueue = deQueue

local Stack = {}
function Stack:Ctor()
    self.Stack = { _StackSize = 0}
    self.sSave = {}
end
function Stack:GetSize()
    return self.Stack._StackSize or 0
end
function Stack:PushStack(stu)
    local nSize = self:GetSize()
    self.sSave[nSize+1] = stu
    self.Stack._StackSize = nSize+1
end
function Stack:IsEmpty() 
    local nSize = self:GetSize()
    if nSize==0 then return true end
    return false
end
function Stack:PopStack() --出栈删除
    local nSize = self:GetSize()
    if self:IsEmpty() then return nil end
    self.Stack._StackSize = nSize - 1
    return table.remove(self.sSave,nSize)
end
function Stack:TopStack() --出栈不删除
    local nSize = self:GetSize()
    if self:IsEmpty() then return nil end 
    return self.sSave[nSize]
end
function Stack:ClearStack()
    self.Stack._StackSize = 0
    self.sSave = nil 
    self.sSave = {}
end
Algorithm.Stack = Stack

local list = {}
function list:InitNote(data, prev, next)
    local o = {}
    o.Data = data
    o.Prev = prev
    o.Next = next
    return o
end
function list:Ctor()
    self.Head = self:InitNote(nil)
	self.Head.Prev = self.Head
	self.Head.Next = self.Head
	self.nSize = 0
end
function list:AddLast(data)
    if self.nSize == 0 then
        self.Head = InitNote(data, nil ,nil)
        self.Head.Prev = self.Head
        self.Head.Next = self.Head
		self.nSize = self.nSize + 1
		return true
    else
        local p = self:GetElement(self.nSize)
        local q = self:InitNote(data,p,p.next)
        self.Head.Prev = q
        p.next = q 
        self.nSize = self.nSize + 1
    end
end 
function list:InsertList(index,data)
    if (self.nSize<=0 or index>=self.nSize or index<=0) then return false end
    if index==1 then
        local note = self:InitNote(data,self.Head.Prev,self.Head)
        self.Head.Prev.Next = note 
        self.Head.Prev = note
        self.Head = note
        self.nSize = self.nSize + 1
    else
        local newnote = self:GetElement(index)
        local nextnote = self:InitNote(data,newnote.Prev,newnote)
        newnote.Prev.Next = nextnote
        newnote.Prev = nextnote
        self.nSize = self.nSize + 1
    end
end
function list:GetElement(index)
    if (index<=0 or index>self.nSize) then return nil end
    if index==1 then return self.Head end
    if (index<self.nSize/2) then
        local item = self.Head
        for k=1, index do item = item.next end
        return item
    end
    local Prev = self.Head
    local rIndex = self.nSize - index + 1
    for k=1, rIndex do Prev = Prev.Prev end
    return Prev
end
function list:AppendList(index,data)
    if (self.nSize<=0 or index>=self.nSize or index<=0) then return false end
    local oldnode = self:GetElement(index)
    local newnote = self:InitNote(data,oldnode,oldnode.Next)
    oldnode.Next.Prev = newnote
    oldnode.Next = newnote
    self.nSize = self.nSize + 1
end
function list:Del(index)
    if (self.nSize<=0 or index>=self.nSize or index<=0) then return false end
    if index==1 then
        self.Head.Prev.Next = self.Head.Next
        self.Head.Next.Prev = self.Head.Prev
        self.Head = self.Head.Next
        self.nSize = self.nSize - 1
        return index
    end
    local oldnode = self:GetElement(index)
    if oldnode==nil then return end
    oldnode.Prev.Next = oldnode.Next
    oldnode.Next.Prev = oldnode.Prev
    self.nSize = self.nSize - 1 
end
function list:IsEmpty()
    return self.nSize==0
end
Algorithm.list = list

function Algorithm:New()
	deQueue:Ctor()
    Stack:Ctor()
    list:Ctor()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	return t
end

return Algorithm