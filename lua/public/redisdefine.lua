
local redisdefine = {}

---------------------------------------------------------------------------
-- redis的所有key都要在这里定义！！！

redisdefine.Lobby_key =
{
    LobbyList = "LobbyList_Key",
    LobbyTreeList = "TreeList_Key",   --用户种子表(弃用)
    LobbyTreeHash = "TreeHash_Key",   --使用哈希表
    LobbyVisitHash = "VisitHash_Key", --探访用户列表哈希表 key userID ,val requestTime
    LobbyBackVisitHash = "BackVisitHash_Key", --回访用户记希表 key userID ,val 探访的记录表，被探访者的id当keyrequestTime
    LobbyVisitedInfoList = "VisitedInfoList_Key", -- 
    LobbyVisitDynamicsHash = "DyResTime_Key" ,     -- 动态记录请求的时间
    LobbyVistVisitSatus = "VisitStatus_key",     -- -- 探访用户转态
    GameConfigRoom = "RoomHashKey"
    -- 已启动的大厅信息
    -- 哈希类型，字段：IP,端口
}

redisdefine.Game_key =
{
    GameList = "Game_Key",
    AndroidList = "Android_0_0"
}

redisdefine.Logon_key =
{
	--登录 玩家信息 
	UserList = "User_Key",
}

redisdefine.Room_key =
{
	 -- 房间信息 
    RoomList = "RoomInfo_Key",
    -- 房间玩家 信息
    AccoutList = "Accout_Key",
}

redisdefine.GateWay_key =
{
    --生成前端访问的信息
    GateList = "GateWay_Visit_68N897B987H65G89K875YA1V2B34B4534W_",
}

-- 全局配置key
redisdefine.GlobalConfigKey =
{
    ConfigKey = "GlobalConfig",
    ChangeNameRecharge = "ReNameCharge",  --{"open" : 1, "price" : 100}
    ChangeNameLoss = "ReNameLoss",        --{"open" : 1, "loss" : 50, "interval" : 86400, "price" : 100}
    ChangeNameHandProfit = "ReNameHandProfit", --{"open" : 1, "loss" : 50, "interval" : 86400, "price" : 100}
    ChangeNameTime = "ReNameTime",       --{"open" : 1, "interval" : 86400, "price" : 100}
    TransferOpen = "TransferOpen",       -- {"open" : 1}
    CostConfigs = "CostConfigs",       -- {"FaFaKan":0.1,"TouTouKan":0.1,"Hash":0.2}
    LinkConfigs = "LinkConfigs"       -- {"tgLink": "http://"}
}

-- 消耗配置名
redisdefine.CostName = {
    FaFaKan = "FaFaKan",            --发发看
    TouTouKan = "TouTouKan",        --偷偷看
    Hash = "Hash"                   --哈希验证
}

return redisdefine
