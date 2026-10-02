--[[牌桌流程类 -- 流程控制
--]]
local tAsyncEvent = require("AsyncEvent")
local tEventlo = require("EventIo")
TableStep = {}

function TableStep:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.nCurStep = 0 -- 当前步骤
	t.nPreStep = 0 -- 上个流程结束
	t.nStepTimerID = 12359
	t.tGameStep = {}
	t.tGameStepTime = {}
	t.tStepEvent = tAsyncEvent -- 默认异步事件模式
	t.nStepMode = 0 -- 循环模式
	t.bAutoNext = false
	t.tParamData = {}
	t.bReset = true -- 重设流程 
	t.nTableId = 0 -- 保留牌桌ID
	t.nStepRemainTime = 0 -- 当前阶段剩余时间
	t.nStepTime = 0 -- 设置流程时间
	return t
end

-- 设置牌桌流程执行ID起始ID 定时器执行是起始ID + 牌桌ID
function TableStep:SetStepTimerID(nStepTimerID)
	self.nStepTimerID = nStepTimerID
end

-- 设置流程驱动的事件模型 异步1，同步2
function TableStep:SetEventMode(nEventMode)
	if nEventMode == 1 then
		self.tStepEvent = tAsyncEvent
	else
		self.tStepEvent = tEventlo.New()
	end
end

-- 设置 流程模式 0 是循环模式
function TableStep:SetStepMode(nMode)
	self.nStepMode = nMode
end
-- 流程配置
function TableStep:Init(tStepConfig)
	if tStepConfig == nil then
		tStepConfig = {}
		tStepConfig.tGameStep = {}
		tStepConfig.tGameStepTime = {}
		tStepConfig.tStepFun = {}

		tStepConfig.tGameStep[1] = 1
		tStepConfig.tGameStepTime[1] = 3000
		tStepConfig.tStepFun[1] = function ()
			Base.Log("我是步骤执行")
		end

		tStepConfig.tGameStep[2] = 2
		tStepConfig.tGameStepTime[2] = 3000
		tStepConfig.tStepFun[2] = function ()
			Base.Log("我是步骤执行2")
		end

		tStepConfig.tGameStep[3] = 3
		tStepConfig.tGameStepTime[3] = 3000
		tStepConfig.tStepFun[3] = function ()
			Base.Log("我是步骤执行3")
		end
	end


	-- 步骤初始化
	for i = 1, #tStepConfig.tGameStep do
		-- Base.Log("步骤初始化   %d ",i)
		self.tGameStep[i] = tStepConfig.tGameStep[i]
	end

	-- 步骤时间初始化
	for nStep, nTime in pairs(tStepConfig.tGameStepTime) do
		self.tGameStepTime[nStep] = nTime
	end

	-- 步骤事件函数初始化
	for nStept, fFun in pairs(tStepConfig.tStepFun) do
		self.tStepEvent.RegistEvent(nStept,fFun)
	end
end

-- 获取下个流程
function TableStep:GetNextStep()
	if self.nCurStep == 0 then
		Base.Log("启示流程")
		return self.tGameStep[1] or 0 -- 
	end

	if self.nCurStep == self.tGameStep[#self.tGameStep] then
		Base.Log("最后的流程")
		if self.nStepMode == 0 then
			Base.Log("循环模式")
			return self.tGameStep[1] or 0 -- 最后的流程 （循环模式）
		else
			Base.Log("顺序模式")
			return 0
		end
		
	end

	for i = 1, #self.tGameStep do
		if  self.nCurStep ==  self.tGameStep[i] then
			--Base.Log("下个流程")
			return self.tGameStep[i + 1]
		end
	end

end

-- 设置流程时间
function TableStep:SetStepTime(nTime)
	
end
-- 获取流程时间
function TableStep:GetStepTime(nStep)
	return self.tGameStepTime[nStep] or 0
end

-- 获取当前流程
-- nCallBackStatus -- 上个流程流程结束 -1 （当前流程结束就是下个流程的开始）, 当前流程开始 1 （当前流程开始。就是上个流程的结束）
function TableStep:GetCurStep(nCallBackStatus)
	if nCallBackStatus == -1  then
		return  self.nPreStep
	elseif nCallBackStatus == 1 then
		return  self.nCurStep
	end
end
-- 检查流程是否有配置
function TableStep:CheckStep(nStep)
	for i = 1, #self.tGameStep do
		if self.tGameStep[i] == nStep then
			return true
		end
	end

	return false
end

-- 获取流程当前剩余时间
function TableStep:GetStepRemainTime()
	local nStepTime = self.nStepTime
	local nTempTime = base.GetTime()

	return nStepTime + self.nStepRemainTime - nTempTime
end
-- 流程执行 -- 
-- nTableId 执行的牌桌ID
-- bAutoNext 是否自动执行下个流程
-- tParamData -- 事件回调的参数
function TableStep:Execute(nTableId)
	local ntempCurStep = self:GetNextStep()
	local nStepTime = self:GetStepTime(ntempCurStep)
	-- Base.Log("Execute")
	-- Base.Log(ntempCurStep)
	-- Base.Log(nStepTime)
	-- Base.LogT(self.tParamData)
	if ntempCurStep > 0 then
		self.nPreStep = self.nCurStep
		self.nCurStep = ntempCurStep
		self.nStepRemainTime = base.GetTime()
		self.nStepTime = nStepTime
		Base.TokenCallTimeID(self.nStepTimerID + nTableId, nStepTime, 1, TableStep.GemeStep, self.nStepTimerID + nTableId,self)
	end
end

-- 流程执行 -- nMode 是否循环执行
-- nTableId 执行的牌桌ID
-- nStep 指定执行某个流程
-- bAutoNext 是否自动执行下个流程
-- nTime 是覆盖当前的定时器时间设置（ 0 立马执行） 其它不做处理
-- tParamData -- 事件回调的参数
function TableStep:ExecuteStep(nTableId,nStep,nTime,bAutoNext,tParamData)
	Base.KillTimer(self.nStepTimerID + nTableId)
	--Base.LogT(tParamData)
	if self.nTableId == 0 then 
		self.nTableId = nTableId
	end
	self.bReset = true
	if self:CheckStep(nStep) then
		local nStepTime = nTime
		self.nPreStep = self.nCurStep
		self.nCurStep = nStep
		self.nStepRemainTime = base.GetTime()
		self.nStepTime = nStepTime
		self.bAutoNext = bAutoNext
		self.tParamData = tParamData
		-- Base.Log("cur step :%d ", nStep)
		if nTime == 0 then
			Base.Log("nTime ")
			self.bReset = false -- 回调函数没有重设阶段判断
			self.tStepEvent.Call(self.nCurStep, tParamData)
			if self.bReset == true then
				-- Base.Log("重设退出循环")
				return 
			end
			if bAutoNext == true then
				self.bReset = true
				self:Execute(nTableId)
			end
		else
			--Base.Log("TokenCallTimeID ")
			Base.TokenCallTimeID(self.nStepTimerID + nTableId, nStepTime, 1, TableStep.GemeStep, self.nStepTimerID + nTableId,self, bAutoNext,tParamData)
		end
		
	else
		Base.Log("无效的牌桌流程:%d",nStep)
	end
end

-- 终止流程
function TableStep:StopStep(nTableId,nStep)
	-- Base.Log("牌桌：%d 流程终止%d",nTableId,nStep)
	self.bAutoNext = false
	Base.KillTimer(self.nStepTimerID + nTableId)
end

-- 流程对象删除
function TableStep:Del()
	Base.KillTimer(self.nStepTimerID + self.nTableId)
	self = nil 
end
-- 流程响应
function TableStep.GemeStep(...)
	local arg = {...}
	local nTimerID = arg[1]
	local nStepObj =  arg[2]

	
	nStepObj.bReset = false -- 回调函数没有重设阶段判断
	nStepObj.tStepEvent.Call(nStepObj.nCurStep, nStepObj.tParamData)
	
	if nStepObj.bReset == true then
		-- Base.Log("重设退出循环")
		return 
	end

	nStepObj.nPreStep = nStepObj.nCurStep
	if nStepObj.bAutoNext == true then
		nStepObj.bReset = true -- 回调函数没有重设阶段判断
		local nTableId = nTimerID % nStepObj.nStepTimerID 
		nStepObj:Execute(nTableId)
	end
	
end

return  TableStep 