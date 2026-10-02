
--60000以下的id保留为Table里使用
local tname = require("typename") -- 类弄定义接口

local Define ={}

Define.sGameName=tname.dezhouslave               --游戏名称
Define.LLogDir   =Define.sGameName              --日志目录名称
Define.GoldOfFreeRoom =10000                    --体验房金币
Define.MaxUserCnt =10000                         --桌子人数上限
Define.nGameId =123                             --游戏id

--桌子状态 
Define.TableState ={
    
}

Define.TableType ={
    nMatch =4,          --匹配房
}
Define.GoldOfFreeRoom =10000  --免费场玩家身上金币 (已经不用,改为大盲的100倍)

Define.nCenterServId=nil  --中心服id,获取到时会赋值
Define.isLogonCenterSuccee=false
return Define