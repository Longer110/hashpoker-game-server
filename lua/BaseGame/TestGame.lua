local tTable = require("Table")
local tTableMgr = require("TableManage")

local tUser = require("User")
local tUserMgr = require("UserManager")

local tAsyncEvent = require("AsyncEvent")
local tTableStep = require("TableStep")
local tPrivatelog = require("PrivateLog")
local tTestGame = require("TestGame")
local tPublicMath = require("PublicMath")


TestGame = {

    Table = nil,
    TableManage = nil,
  
}
local tTestGameTable =  tTable:New() -- 创建对象
TestGame.Table = tTestGameTable

function TestGame.Table:Log() -- 重写或者实现
	print(self.nTableId)
    print(11111111)
end


local tTestTableMgr =  tTableMgr:New()
TestGame.TableManage = tTestTableMgr

function TestGame.TableManage:Log()
    Base.Log("TableManage")
end

local tTestUser = tUser:New()
TestGame.User = tTestUser


function TestGame.User:Log()
    Base.Log("User")
end
local tTestUserMgr = tUserMgr:New()
TestGame.UserMgr = tTestUserMgr


function TestGame.User:Log()
    Base.Log("User2")
end

function TestGame.UserMgr:Log()
    Base.Log("UserMgr")
end

-- 牌桌流程
local tStepConfig = {}
    tStepConfig.tGameStep = {}
    tStepConfig.tGameStepTime = {}
    tStepConfig.tStepFun = {}

    tStepConfig.tGameStep[1] = 1
    tStepConfig.tGameStepTime[1] = 3000
    tStepConfig.tStepFun[1] = function (tParamData)
        Base.Log("我是步骤执行")
        Base.LogT(tParamData)
    end

    tStepConfig.tGameStep[2] = 2
    tStepConfig.tGameStepTime[2] = 3000
    tStepConfig.tStepFun[2] = function (tParamData)
        Base.Log("我是步骤执行2")
        Base.LogT(tParamData)
    end

    tStepConfig.tGameStep[3] = 3
    tStepConfig.tGameStepTime[3] = 3000
    tStepConfig.tStepFun[3] = function (tParamData)
            Base.Log("我是步骤执行3")
            Base.LogT(tParamData)
	end
    
    local temptTableStep = tTableStep:New()
    temptTableStep:SetEventMode(2)
    temptTableStep:SetStepMode(1)
    temptTableStep:Init(tStepConfig)
   
    temptTableStep:ExecuteStep(1,1,0,true,{["nTableId"] = 1 })

    local temptTableStep2 = tTableStep:New()
    temptTableStep2:SetEventMode(2)
    temptTableStep2:SetStepMode(1)
    temptTableStep2:Init(tStepConfig)
   
    temptTableStep2:ExecuteStep(2,1,0,true,{["nTableId"] = 2 })

    -- 标识日志
    local tempLog =  tPrivatelog:New()
    tempLog:info("woshi谁")
    tempLog:SetLogFlag(temptTableStep)
    tempLog:info("woshi谁")
    tempLog:info("aaa","woshi谁")
    tTestGame.Table:Log()
    tTestGame.TableManage:Log()
    local tempUser =  tTestGame.User:New()
    tempUser.nUserID = 11111
    tTestGame.UserMgr:AddUser(tempUser)
    local tempUser2 =  tTestGame.UserMgr:GetUserInfo(11111)
    tempLog:info(string.format( "%d", tempUser.nUserID ))
    tempLog:info(string.format( "%d", tempUser2.nUserID ))
   
    tTestGame.User:Log()
    tTestGame.UserMgr:Log()

    -- 牌的生成
    local tempMath = tPublicMath:New()
    tempMath:InitGameCard(nil,4)
    Base.LogT( tempMath:RandCard())


 return TestGame