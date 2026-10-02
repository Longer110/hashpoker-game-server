
local tBase = require("base") -- 基础功能接口

local Coder = {}
local Aux ={}
Coder.Aux=Aux

function Coder.Parser(tProtoObject,Data,DataLen)
    local ReadData = tBase.GetRP().new(Data, DataLen)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 
    tProtoObject:ParseFromString(ReadData:GetString())
    return tProtoObject
end
function Coder.EncodeToPacket(tProtoObject,tProtoData,nMainCmd,nSubCmd)
    local isSuccee,ret =pcall(tBase.ProtoInit,tProtoObject,tProtoData)
    if not isSuccee then
        local sErrMsg =string.format("ProtoInit Err. tProtoData:%s",tBase.tostring(tProtoData))
        sErrMsg =sErrMsg..(ret or "")
        assert(false,sErrMsg)
    end
    local isSuccee,sStr =pcall(tProtoObject.SerializeToString,tProtoObject)
    if not isSuccee then
        local sErrMsg =string.format("SerializeToString Err. tProtoData:%s",tBase.tostring(tProtoData))
        sErrMsg =sErrMsg..(sStr or "")
        assert(false,sErrMsg)
    end
    local tPacket = tBase.GetSP().new(nMainCmd, nSubCmd) 
    tPacket:AddString(sStr) 
    return tPacket
end

function Aux:New(tPb,ToCMD)
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.pb = tPb
	t.ToCMD =ToCMD
	return t
end
function Aux:Encode(strProto,tData)
    local strProto=strProto or "nill"
    local f =self.pb[strProto]
    if f==nil then
        local sErr =string.format("can not find Proto:%s",strProto)
        assert(false,sErr)
    end
    local nMainCmd,nSubCmd =self.ToCMD(strProto)
    if nMainCmd==nil then
        local sErr =string.format("can not find nMainCmd of Proto:%s",strProto)
        assert(false,sErr)
    elseif nSubCmd==nil then
        local sErr =string.format("can not find nSubCmd of Proto:%s",strProto)
        assert(false,sErr)
    end
    local tProtoObject =f()
    local packet =Coder.EncodeToPacket(tProtoObject,tData,nMainCmd,nSubCmd)
    return packet,nMainCmd,nSubCmd
end
function Aux:Parser(Data, len,strProto)
    local f = self.pb[strProto]
    if f==nil then 
       return
    end
    local tProtoObject =f()
    return Coder.Parser(tProtoObject,Data,len)
end
return Coder
