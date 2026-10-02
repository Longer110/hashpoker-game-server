
local Aux ={}
Aux.pb=nil
Aux.ToCMD =nil

function Aux.Init(pb,ToCMD)
    Aux.pb=pb
    Aux.ToCMD =ToCMD
end

function Aux.Encode(strProto,tData)
    local f =Aux.pb[strProto]
    if f==nil then
       Base.Log("Aux.pb[strProto] is nil,strProto: %s",strProto)
        return
    end
    local nMainCmd,nSubCmd =Aux.ToCMD(strProto)
    if nMainCmd==nil or nSubCmd==nil then
       Base.Log(" nMainCmd,nSubCmd is nil,  strProto: %s",strProto)
        return
    end
    local tProtoObject =f()
    local packet =ProtoCoder.EncodeToPacket(tProtoObject,tData,nMainCmd,nSubCmd)
    return packet
end

function Aux.Parser(Data, len,strProto)
    local ReadData = Base.GetRP().new(Data, len)
    local Sys = ReadData:GetModuleID()
    local Sub = ReadData:GetMsgID() 
    local f = Aux.pb[strProto]
    if f==nil then 
       Base.Log("Aux.pb[strProto] is nil,strProto: %s",strProto)
       return
    end
    local tProtoObject =f()
    tProtoObject:ParseFromString(ReadData:GetString())
    return tProtoObject
end

return Aux