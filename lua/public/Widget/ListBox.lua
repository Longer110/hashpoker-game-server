--ListBox控件

CListBox = {} 

--创建lisbbox控件
function CListBox:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self

	t.arrItem = {}

	return t
end

--销毁listbox控件
function CListBox:Del()
	self = nil
end

--新增加一个item项
function CListBox:AddItem(tItemData)
	table.insert(self.arrItem, tItemData)
end

--移除一个item项目
function CListBox:RemoveItem(nItemId)
	table.remove(self.arrItem, nItemId)
end

--获取某个itemId下的item
function CListBox:GetItem(nItemId)
	return self.arrItem[nItemId]
end

--获取所有item
function CListBox:GetAllItem()
	return self.arrItem
end

--获得listbox大小
function CListBox:GetSize()
	return #self.arrItem
end

return CListBox

