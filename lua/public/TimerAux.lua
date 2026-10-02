
local tBase 	  = require("base")         -- 基础功能接口
local logger = require("logger")      -- 日志对象

local Timer = {}

local arrAllTimerId ={}
for nTimerId=1000,60000 do
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
		local isSuccee,sErr =pcall(fFunc,table.unpack(arrparameter))  
		if not isSuccee then
			if type(sErr) == "string" then 
                logger:error(sErr)
            else 
                tBase.LogT(sErr) 
            end
		end
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
function Timer:KillAllTimer()
	for nFunctionId,_ in pairs(self.tFunctionIdToTimerId) do
		self:KillTimer(nFunctionId)
	end
end

function Timer:GetRunTimerCnt()
	local nCnt =0
	for nFunctionId,_ in pairs(self.tFunctionIdToTimerId) do
		nCnt =nCnt +1
	end
	return nCnt
end

return Timer
