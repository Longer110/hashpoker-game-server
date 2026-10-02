--create date: 2021-08-11
local tSrvInfo = require("ServerInfo")

local Define = {}

Define.ServerName = "AndroidServer_"..tSrvInfo.nServerId

--定时器id
Define.Timer ={
    LoadCfg = 20000,
    CheckAndroid = 20001,
    CheckRental = 20002,
    CheckInvalid = 20003,
    CheckNickLib = 20005,
}

Define.LoadCount = 500 --每次加载机器人的个数
Define.CreateCount = 100 --每次新增机器人个数
Define.nSpaceTimeTg = 6*60*60 --相同消息通知到tg群的间隔时间
Define.nServerKeyTimeOut = 60*30   -- 服务器key  超时

return Define