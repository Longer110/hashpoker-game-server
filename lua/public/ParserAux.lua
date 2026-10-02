
local tBase = require("base") -- 基础功能接口
local ProtoMgr = require("ProtoManager") -- 协议管理对象 
local logger = require("logger")      -- 日志对象

local Aux = {}
function Aux:New(tPb,tCMD)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tPb = tPb
	t.tCMD =tCMD
	return t
end

function Aux:Parser(Data, len,strReq)
	local ReadData = tBase.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 
    local Read = self.tPb[strReq]
    if not Read then 
       return
    end
    Read =Read()
    Read:ParseFromString(ReadData:GetString())
    return Read
end
function Aux:ToCMD(strProto)
	local strMainCmdKey ="Main_CMD"
	local strSubCmdKey =strProto.."_CMD"
	return self.tCMD[strMainCmdKey] ,self.tCMD[strSubCmdKey]
end

function Aux:Encode(strProto,tData)
    tBase.LogT("Encode strProto=",strProto)
    local nMainCmd ,nSubCmd =self:ToCMD(strProto)
    tBase.LogT("Encode LogT=",nMainCmd," nSubCmd=",nSubCmd)
	local fProto =self.tPb[strProto]
    tBase.LogT("Encode fProto=",fProto)
    if nMainCmd==nil or nSubCmd==nil or fProto==nil then
        tBase.Log("Encode %s fail",(strProto or "nil"))
        tBase.LogT("nMainCmd:",nMainCmd," nSubCmd:",nSubCmd)
       return
    end
    local  tProtoObj = fProto()
    local isSuccee,ret =pcall(tBase.ProtoInit,tProtoObj,tData)
     if isSuccee==false then
        logger:error("SendToClient ProtoInit Err happen=>")
       	tBase.LogT("SendToClient Err happen=>",strProto," ",tData)
         if type(ret)=="string" then
             tBase.Log(ret)
         end
         return
    end
    local tPacket = tBase.GetSP().new(nMainCmd, nSubCmd) 
    tPacket:AddString(tProtoObj:SerializeToString())   
    return tPacket,nMainCmd,nSubCmd
end


function Aux:SendToClient(sClientID,strProto,tData)
    local tPacket =self:Encode(strProto,tData)
    if not tPacket then
        return false
    end
    tBase.PostToGateway(sClientID, tPacket:GetData(), tPacket:GetSize())  
    return true	
end

function Aux:SendToServer(sReturnKey,strProto,tData)
    local tPacket =self:Encode(strProto,tData)  
    if not tPacket then
        return false
    end
    tBase.PostToClient(sReturnKey, tPacket:GetData(), tPacket:GetSize())
    return true	
end

local LobbyAux =Aux:New(ProtoMgr.Lobby_pb,ProtoMgr.LobbyPro)
local ZhaJinHuaAux =Aux:New(ProtoMgr.ZhaJinHuaGame_pb,ProtoMgr.ZhaJinHuaGame_pb.ZhaJinHuaGame_Proto())  
local DbAux =Aux:New(ProtoMgr.DbServer_pb,ProtoMgr.DbServer_pb.Db_Proto()) 
local DbAux1 =Aux:New(ProtoMgr.DbServer1_pb,ProtoMgr.DbServer1_pb.Db_Proto1()) 
local NotifyAux =Aux:New(ProtoMgr.NotifyToCli_pb,ProtoMgr.NotifyToCli_pb.NotifyCli_Proto())
local MaintainerAux =Aux:New(ProtoMgr.Maintainer_pb,ProtoMgr.Maintainer_pb.Maintainer_Proto())
local MaJiangAux =Aux:New(ProtoMgr.MaJiang_pb,ProtoMgr.MaJiang_pb.MaJiang_Proto())
local LogAux =Aux:New(ProtoMgr.Log_pb,ProtoMgr.Log_pb.Log_Proto())
local BackstageAux =Aux:New(ProtoMgr.Backstage_pb,ProtoMgr.Backstage_pb.Backstage_Proto())
local PaiJiuAux =Aux:New(ProtoMgr.PaiJiu_pb,ProtoMgr.PaiJiu_pb.PaiJiu_Proto()) 
local SeDieAux = Aux:New(ProtoMgr.SeDie_pb, ProtoMgr.SeDie_pb.SeDie_Proto())

local ErBaGangAux =Aux:New(ProtoMgr.ErBaGang_pb,ProtoMgr.ErBaGang_pb.ErBaGang_Proto())    -- 二八杠协议
local YuXiaXieAux =Aux:New(ProtoMgr.YuXiaXie_pb,ProtoMgr.YuXiaXie_pb.YuXiaXie_Proto())    -- 鱼虾蟹协议
local TouBaoAux =Aux:New(ProtoMgr.TouBao_pb,ProtoMgr.TouBao_pb.TouBao_Proto())          -- 骰宝协议
local TexasAux    =Aux:New(ProtoMgr.Texas_pb,ProtoMgr.Texas_pb.Texas_Proto())    
local BaiRenZhaJinHuaAux =Aux:New(ProtoMgr.BaiRenZhaJinHua_pb,ProtoMgr.BaiRenZhaJinHua_pb.BaiRenZjh_Proto())
local WebAux    =Aux:New(ProtoMgr.Web_pb,ProtoMgr.Web_pb.Web_Sys())   
local DbClubAux1 =Aux:New(ProtoMgr.DbServerClub_pb,ProtoMgr.DbServerClub_pb.Db_ClubProto())
local DbClubAux2 =Aux:New(ProtoMgr.DbServerClub1_pb,ProtoMgr.DbServerClub1_pb.Db_ClubProto1())
local DbMiniGameAux =Aux:New(ProtoMgr.DbMiniGame_pb,ProtoMgr.DbMiniGame_pb.DbMiniGame_Proto())   

--大厅协议相关辅助
local function _LobbyParse(Data, len,strReq)
   return LobbyAux:Parser(Data, len,strReq)
end
local function _LobbySendToClient(sClientID,strProto,tData)
	return LobbyAux:SendToClient(sClientID,strProto,tData)
end

--扎金花协议相关辅助
local function _ZhaJinHuaParse(Data, len,strReq)
	return ZhaJinHuaAux:Parser(Data, len,strReq)
 end
local function _ZhaJinHuaSendToClient(sClientID,strProto,tData)
	 return ZhaJinHuaAux:SendToClient(sClientID,strProto,tData)
end

--Db服协议相关辅助
local function _DbParse(Data, len,strReq)
	return DbAux:Parser(Data, len,strReq)
 end
 local function _DbSendToServer(sReturnKey,strProto,tData)
    return DbAux:SendToServer(sReturnKey,strProto,tData)
end
local function _DbProtoEncode(strProto,tData)
    return DbAux:Encode(strProto,tData)
end

--Web 服协议
local function _WebAux(strProto,tData)
    return WebAux:Encode(strProto,tData)
end

--叠加
local function _DbParse1(Data, len,strReq)
	return DbAux1:Parser(Data, len,strReq)
end
local function _DbSendToServer1(sReturnKey,strProto,tData)
    return DbAux1:SendToServer(sReturnKey,strProto,tData)
end
local function _DbProtoEncode1(strProto,tData)
    return DbAux1:Encode(strProto,tData)
end

--推送协议相关辅助
local function _NotifyProtoEncode(strProto,tData)
    return NotifyAux:Encode(strProto,tData)
end

--俱乐部db
local function _DbClubParse(Data, len,strReq)
	return DbClubAux1:Parser(Data, len,strReq)
end
local function _DbClubSendToServer(sReturnKey,strProto,tData)
    return DbClubAux1:SendToServer(sReturnKey,strProto,tData)
end
local function _DbClubProtoEncode(strProto,tData)
    return DbClubAux1:Encode(strProto,tData)
end

--俱乐部db1
local function _DbClub1Parse(Data, len,strReq)
	return DbClubAux2:Parser(Data, len,strReq)
end
local function _DbClub1SendToServer(sReturnKey,strProto,tData)
    return DbClubAux2:SendToServer(sReturnKey,strProto,tData)
end
local function _DbClub1ProtoEncode(strProto,tData)
    return DbClubAux2:Encode(strProto,tData)
end

--小游戏db
local function _DbMiniGameParse(Data, len,strReq)
	return DbMiniGameAux:Parser(Data, len,strReq)
end
local function _DbMiniGameSendToServer(sReturnKey,strProto,tData)
    return DbMiniGameAux:SendToServer(sReturnKey,strProto,tData)
end
local function _DbMiniGameProtoEncode(strProto,tData)
    return DbMiniGameAux:Encode(strProto,tData)
end

local ParserAux ={}
ParserAux.LobbyParse =_LobbyParse
ParserAux.LobbySendToClient =_LobbySendToClient

ParserAux.ZhaJinHuaParse =_ZhaJinHuaParse
ParserAux.ZhaJinHuaSendToClient =_ZhaJinHuaSendToClient

ParserAux.DbProtoParse =_DbParse
ParserAux.DbSendToServer =_DbSendToServer 
ParserAux.DbProtoEncode =_DbProtoEncode
ParserAux.DbProtoParse1 =_DbParse1
ParserAux.DbSendToServer1 =_DbSendToServer1
ParserAux.DbProtoEncode1 =_DbProtoEncode1
ParserAux.DbClubParse =_DbClubParse
ParserAux.DbClubSendToServer =_DbClubSendToServer
ParserAux.DbClubProtoEncode =_DbClubProtoEncode

ParserAux.DbClub1Parse =_DbClub1Parse
ParserAux.DbClub1SendToServer =_DbClub1SendToServer
ParserAux.DbClub1ProtoEncode =_DbClub1ProtoEncode

ParserAux.NotifyProtoEncode =_NotifyProtoEncode


ParserAux.DbMiniGameParse =_DbMiniGameParse
ParserAux.DbMiniGameSendToServer =_DbMiniGameSendToServer
ParserAux.DbMiniGameProtoEncode =_DbMiniGameProtoEncode

ParserAux.MaintainerAux=MaintainerAux
ParserAux.MaJiangAux=MaJiangAux

ParserAux.LogAux =LogAux
ParserAux.BackstageAux=BackstageAux

ParserAux.PaiJiuAux=PaiJiuAux

ParserAux.ErBaGangAux=ErBaGangAux
ParserAux.YuXiaXieAux=YuXiaXieAux
ParserAux.TexasAux=TexasAux
ParserAux.WebAux=_WebAux

ParserAux.BaiRenZhaJinHuaAux =BaiRenZhaJinHuaAux

ParserAux.TouBaoAux=TouBaoAux

ParserAux.SeDieAux=SeDieAux

return ParserAux