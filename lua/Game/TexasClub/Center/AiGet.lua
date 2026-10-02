
local tBase = require("base") -- 基础功能接口
local tname = require("typename") -- 类弄定义接口
local ProtoMgr  = require("ProtoManager") -- 协议管理对象 


local AiGet ={}
local tAiCallBack ={}
function AiGet.AiSend(sEcho,sJsonData,funcRes,nTimeOut)

	-- tAiCallBack[sEcho] ={funcRes=funcRes,SendTime=os.time(),nTimeOut=(nTimeOut or 5)}
	-- local tPacket =AiAux:Encode("DZAReq",{sEcho=sEcho,sJsonData=sJsonData})
	-- tBase.PostDatasByType(tname.AiTexas, 0, 0, tPacket:GetData(), tPacket:GetSize())

     local tSend = ProtoMgr.PubProto_1_pb.WebPublicMessReq()
     tSend.sBody = sJsonData
     local s = tBase.GetSP().new(ProtoMgr.Sys1.WebMain, ProtoMgr.Sub_Web.WebPublicMessReq_CMD)   
     s:AddString(tSend:SerializeToString())
     tBase.PostDatasByType(tname.web,0, 0, s:GetData(), s:GetSize())

     tBase.Log("_AiSend  sJsonData: "..sJsonData)
end

function AiGet.CallBack(sEcho,tPameter)
   local tInf= tAiCallBack[sEcho]
   if not tInf then
        return "can not find sEcho"
   end
   if (os.time() -tInf.SendTime) >tInf.nTimeOut then
        return "timeout"
   end
   tAiCallBack[sEcho]=nil
   tInf.funcRes(tPameter)
end

return AiGet