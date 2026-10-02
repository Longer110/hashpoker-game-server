Head ={}

Head.path =  "./lua/base/?.lua;" ..
"./lua/base/socket/?.lua;" ..
"./lua/base/logging/?.lua;" ..
"./lua/public/?.lua;" ..
"./lua/protocol/?.lua;" ..
"./lua/public/DBSink/?.lua;" ..
"./lua/HotFix/?.lua;" ..
"./lua/Club/?.lua;"..
"./lua/Club/Center/?.lua;"..
"../lua/Control/?.lua;./lua/Control/?.lua;" ..
"./lua/public/PublicLogic/?.lua;" ..
package.path

package.path = Head.path

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
PublicRedis = require("PublicRedis") --redis
RedisCahche = require("RedisCahche") --redis缓存类，读后台配置
BaseSink = require("BaseSink")    -- base 编码解码

Define =require("Define") --变量定义
PubClubApi = require("PubClubApi") --俱乐部公共接口
PubErrCode = require("PubErrCode") --错误码定义


MsgHandle = require("MsgHandle") --消息处理类
ClubManager =require("ClubManager") --俱乐部管理类(中心服)
MsgApi = require("MsgApi") --消息发送api
ClubC = require("ClubC") --俱乐部类
PacketEncoder =require("PacketEncoder") --协议编码解码类
CenterData = require("CenterData") --中心服数据缓存

--从服<->中心服协议
Pb_Center =ProtoManager.ClubCenter_pb
CMD_Center =ProtoManager.ClubCenter_pb.ClubC_Proto()
ToCMD_Center =function(strProto)
    return CMD_Center.Main_CMD,CMD_Center[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
CenterAux =ProtoAux:New(Pb_Center,ToCMD_Center)

--web<->中心服协议
Pb_Web =ProtoManager.Web_pb
CMD_Web =ProtoManager.Web_pb.Web_Sys()
ToCMD_Web =function(strProto)
    return CMD_Web.Main_CMD,CMD_Web[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
WebAux =ProtoAux:New(Pb_Web,ToCMD_Web)

--db服<->中心服协议
Pb_DbClubServer =ProtoManager.DbServerClub_pb
CMD_DbClubServer =Pb_DbClubServer.Db_ClubProto()
ToCMD_DbClubServer =function(strProto)
    return CMD_DbClubServer.Main_CMD,CMD_DbClubServer[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
DbClubServAux =ProtoAux:New(Pb_DbClubServer,ToCMD_DbClubServer)

--后台<->中心服协议
Pb_Backstage =ProtoManager.Backstage_pb
CMD_Backstage =ProtoManager.Backstage_pb.Backstage_Proto()
ToCMD_Backstage =function(strProto)
    return CMD_Backstage.Main_CMD,CMD_Backstage[strProto..'_CMD']
end
--生成个全局的编解码辅助对象
BackstageAux =ProtoAux:New(Pb_Backstage,ToCMD_Backstage)


B_Encode=function(str)
    return BaseSink.encode(str)
end

B_Decode=function(str)
    return BaseSink.decode(str)
end

return Head