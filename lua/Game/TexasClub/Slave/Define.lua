
--60000以下的id保留为Table里使用
local tname = require("typename") -- 类弄定义接口

local Define ={}

Define.sGameName=tname.clubdezhouslave          --游戏名称
Define.LLogDir   = "slave"              --日志目录名称
Define.MaxUserCnt =10000                        --桌子人数上限
Define.nGameId =125                             --该常量已废弃

Define.nGameId_Normal=125                          --德州 正常玩法
Define.nGameId_Ahm=126                             --德州 奥哈马玩法
Define.nGameId_Sc =175                             --德州 短牌

--桌子状态 
Define.TableState ={
    
}

Define.nInsureStageTime=20  --保险阶段时间 秒

Define.TableType ={
    nMatch =4,          --匹配房
}
Define.GoldOfFreeRoom =1000         --试玩场玩家金币系数 (玩家金币 =GoldOfFreeRoom*大盲)
Define.GoldOfMttRoom =2000000000     --比赛房无限金币(积分)

Define.nCenterServId=nil  --中心服id,获取到时会赋值
Define.isLogonCenterSuccee=false
return Define