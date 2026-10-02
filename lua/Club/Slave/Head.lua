Head ={}

Head.path =  "./lua/base/?.lua;" ..
"./lua/base/socket/?.lua;" ..
"./lua/base/logging/?.lua;" ..
"./lua/base/luasec/?.lua;" ..
"./lua/public/?.lua;" ..
"./lua/protocol/?.lua;" ..
"./lua/public/DBSink/?.lua;" ..
"./lua/HotFix/?.lua;" ..
"./lua/Club/?.lua;"..
"./lua/Club/Slave/?.lua;"..
"./lua/Club/Slave/User/?.lua;"..
"./lua/Club/Slave/ClubS/?.lua;"..
"./lua/Club/Slave/ClubSMsg/?.lua;"..
"./lua/Club/Slave/Activity/?.lua;"..
"./lua/public/Moblie/?.lua;" ..
package.path

package.path = Head.path

tBase = require("base") -- 基础功能接口
Base = require("base") -- 基础功能接口
Typename = require("typename") --服务器名字
Cjson     = require("cjson")        -- json  
ServerInfo = require("ServerInfo") --服务器信息
Logger = require("logger")      -- 日志对象
TimerAux =require("TimerAux") --定时器类
PublicApi =require("publicApi") --公共api
ProtoManager = require("ProtoManager") -- 协议管理对象 
PublicUserInfo = require("PublicUserInfo") -- 用户信息
Logging = require("logging") -- 日志等级接口
DBInfo = require("DBInfo") --数据库信息
ProtoCoder =require("ProtoCoder") --协议编码解码类
ProtoAux = ProtoCoder.Aux
RecordDbr =require("RecordDbr") --记录类
MsgPush = require("MsgPush")

Store = require("Store")    -- base 编码解码
Define =require("Define") --变量定义
PubClubApi = require("PubClubApi") --俱乐部公共接口
PubErrCode = require("PubErrCode") --错误码定义

ClientIdMgr =require("ClientIdMgr") --玩家ClientId与Userid关系类
LiveCSRelation =require("LiveCSRelation") --主从服关系类
GameConfig =require("GameConfig") --游戏配置类
BaseSink = require("BaseSink")    -- base 编码解码

ActivityPublic = require("ActivityPublic")       -- 活动公共接口
Recommend = require("Recommend")                 -- 推荐活动
FirstCharge = require("FirstCharge")                 -- 首充活动
Share = require("Share")                        --分享活动



MsgClient = require("MsgClient") --前端消息
MsgOnTime = require("MsgOnTime") --消息队列
MsgCenter = require("MsgCenter") --中心服消息
MsgWeb = require("MsgWeb") --后台消息
PublicRedis = require("PublicRedis") --redis
RedisCahche = require("RedisCahche") --redis缓存类，读后台配置
MsgApi = require("MsgApi") --消息发送api
UserManager   = require("UserManager") --玩家管理
User = require("User") --用户类
ClubSManager = require("ClubSManager") --俱乐部管理类(从服)
ClubS = require("ClubS") --俱乐部类
MsgMaintenance = require("MsgMaintenance") --服务器维护
SlaveData = require("SlaveData") --从服数据缓存
UserOnTime = require("UserOnTime") --玩家处理

HttpNB = require("HttpNB")       -- HTTP 异步 


--web后台<->游戏服协议
local pb_Backstage =ProtoManager.Backstage_pb
CMD_Backstage =ProtoManager.Backstage_pb.Backstage_Proto()
local ToCMD_Backstage =function(strProto)
    return CMD_Backstage.Main_CMD,CMD_Backstage[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
BackstageAux =ProtoAux:New(pb_Backstage,ToCMD_Backstage)

--web服<->游戏服协议
Pb_Web =ProtoManager.Web_pb
CMD_Web =ProtoManager.Web_pb.Web_Sys()
ToCMD_Web =function(strProto)
    return CMD_Web.Main_CMD,CMD_Web[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
WebAux =ProtoAux:New(Pb_Web,ToCMD_Web)

--db服<->游戏服协议
Pb_DbClubServer =ProtoManager.DbServerClub_pb
Pb_DbClubServer1 =ProtoManager.DbServerClub1_pb
CMD_DbClubServer =Pb_DbClubServer.Db_ClubProto()
CMD_DbClubServer1 =Pb_DbClubServer1.Db_ClubProto1()
ToCMD_DbClubServer =function(strProto)
    return CMD_DbClubServer.Main_CMD,CMD_DbClubServer[strProto..'_CMD']
end
ToCMD_DbClubServer1 =function(strProto)
    return CMD_DbClubServer1.Main_CMD,CMD_DbClubServer1[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
DbClubServAux =ProtoAux:New(Pb_DbClubServer,ToCMD_DbClubServer)
DbClubServAux1 =ProtoAux:New(Pb_DbClubServer1,ToCMD_DbClubServer1)

--db服1<->游戏服协议
Pb_DbServer1 =ProtoManager.DbServer1_pb
CMD_DbServer1 =Pb_DbServer1.Db_Proto1()
ToCMD_DbServer1 =function(strProto)
    return CMD_DbServer1.Main_CMD,CMD_DbServer1[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
DbServer1Aux =ProtoAux:New(Pb_DbServer1,ToCMD_DbServer1)


--从服<->中心服协议
Pb_Center =ProtoManager.ClubCenter_pb
CMD_Center =ProtoManager.ClubCenter_pb.ClubC_Proto()
ToCMD_Center =function(strProto)
    return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
CenterAux =ProtoAux:New(Pb_Center,ToCMD_Center)

--从服<->前端协议
Pb_Slave =ProtoManager.ClubSlave_pb
Pb_Slave2 =ProtoManager.ClubSlave2_pb
CMD_Slave =ProtoManager.ClubSlave_pb.ClubS_Proto()
CMD_Slave2 = ProtoManager.ClubSlave2_pb.ClubS_Proto2()
ToCMD_Slave =function(strProto)
    return CMD_Slave.Main_CMD,CMD_Slave[strProto..'_CMD']
end
ToCMD_Slave2 =function(strProto)
    return CMD_Slave2.Main_CMD,CMD_Slave2[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
SlaveAux =ProtoAux:New(Pb_Slave,ToCMD_Slave)
SlaveAux2 =ProtoAux:New(Pb_Slave2,ToCMD_Slave2)

--web服<->从服协议
Pb_Web =ProtoManager.Web_pb
CMD_Web = ProtoManager.Web_pb.Web_Sys()
ToCMD_Web =function(strProto)
    return CMD_Web.Main_CMD,CMD_Web[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
WebAux =ProtoAux:New(Pb_Web,ToCMD_Web)

return Head