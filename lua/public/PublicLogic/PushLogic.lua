
--  推送公共逻辑

package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
package.path = "../lua/base/socket/?.lua;./lua/base/socket/?.lua;" .. package.path
package.path = "../lua/Logon_s/?.lua;./lua/Logon_s/?.lua;" .. package.path
package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path



local tBase       = require("base")         -- 基础功能接口
local tApi        = require("publicApi")    -- 共用功能接口
local tName       = require("typename")     -- 类弄定义接口
local http        = require("socket.http")  -- Http 服务器
local dbInfo      = require("DBInfo")    -- 数据库连接信息
local tBase64     = require("BaseSink")    -- base 编码解码
local tErr    = require("ErrorSink")       -- 捕捉错误

PushLogic = {}




-- 推送比赛信息
function PushLogic.Push_MatchInfo(tCfg)
    local sTitle = "全娱广东麻将比赛通知"  
    local n2, tStartTime = tApi.string2time(tCfg.sStartTime)
    local sTIme = ""
    sTIme = sTIme..tStartTime.hour..":"..tStartTime.min
    local sMessage = "比赛即将开始，亲爱的玩家，您报名的 "..sTIme.." 开始的"..tCfg.sMatchName.."将在3分钟后开始，请及时登录游戏参加比赛。"
    local sKey = "User_Sign_Table_"..tCfg.nMatchId   
    local sPushKey = "Push_Message_"..tCfg.nMatchId  
    if tBase.m_MyRedisData[2].redis:exists(sPushKey) == true  then 
        tBase.Log(" 多进程处理 不会再推送   ---nMatchId:  %d  ",tCfg.nMatchId )
        return 
    end 
    local sPushMessage = sTitle.."="..sMessage
    tBase.m_MyRedisData[2].redis:hset(sPushKey,sPushKey,sPushMessage)
    tBase.m_MyRedisData[2].redis:expire(sKey, 3*60)   -- 设置 3 分钟失效
    tBase.m_MyRedisData[2].redis:expire(sPushKey, 3*60)   -- 设置 3 分钟失效

    local sHttps = dbInfo.sHttp.."XinPush?Key="..sKey.."&Title="..sPushKey.."&Message="
    tBase.Log(" 推送比赛 sTitle：%s  ,sMessage        请求后台通知 sHttps:  %s   ",sTitle,sMessage ,sHttps)
    local nResult  = http.request(sHttps)     -- 请求后台 
    if type(nResult)  == "string" then 
        tBase.Log(" 请求推送结果失败，   没有资源  Error_Info==172  ")
        return 
    end 
    if nResult == 1 then     -- 0  成功， 其他失败
        tBase.Log(" 请求推送结果成功 nResult：%s ",nResult)
    else
        tBase.Log(" 请求推送结果失败  Error_Info==173 nResult ：%s ",nResult)
    end 
    return 
end




return PushLogic













