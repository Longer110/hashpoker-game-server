
local tBase 	  = require("base")         -- 基础功能接口

local Timer = {}

local arrAllTimerId ={}
for nTimerId=64000,70000 do
	table.insert(arrAllTimerId,nTimerId)
end

--获取一个timerid
function Timer.GetATimerId()
	local nTimerId =table.remove(arrAllTimerId)
	assert(nTimerId ~=nil,"timerid use up")
	return nTimerId
end
--归还一个timerid
function Timer.BackTimerId(nTimerId)
	table.insert(arrAllTimerId,nTimerId)
end
--批量获取timerid
function Timer.GetTimerId(cnt)
	local arr={}
	for i=1,cnt do
		table.insert(arr,Timer.GetATimerId())
	end
	return arr
end


function Timer:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.nFunctionId =0
	t.tFunctionIdToTimerId={}
	return t
end

function Timer:DelayCall(nMSeconds,fFunc,...)
	local nFunctionId =self.nFunctionId
	self.nFunctionId =self.nFunctionId +1
	local arrparameter =table.pack(...)
	local temF =function()
		fFunc(table.unpack(arrparameter))       	
		self:KillTimer(nFunctionId)		
	end
	local nTimerId =Timer.GetATimerId()
	assert(nTimerId ~=nil)
	self.tFunctionIdToTimerId[nFunctionId] =nTimerId
	tBase.SetTimer(nTimerId, nMSeconds, 1, temF)
	return nFunctionId
end
function Timer:KillTimer(nFunctionId)
	local nTimerId =self.tFunctionIdToTimerId[nFunctionId]
	if nTimerId~=nil then
		tBase.KillTimer(nTimerId)
		Timer.BackTimerId(nTimerId)
		self.tFunctionIdToTimerId[nFunctionId]=nil
	end
end
--杀死所有经本对象运行的定时器
function Timer:KillAllTimer()
	for nFunctionId,_ in pairs(self.tFunctionIdToTimerId) do
		self:KillTimer(nFunctionId)
	end
end
return Timer
