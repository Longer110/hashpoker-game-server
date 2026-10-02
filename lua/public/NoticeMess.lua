package.path =  "../lua/protocol/pb/?.lua;./lua/protocol/pb/?.lua;" .. package.path 
local ProtoMgr = require("ProtoManager")   

local NoticeMess = {}
function NoticeMess.NoticeMess(skey,sHttp)
    local tSend = ProtoMgr.PubProto_1_pb.WebMessReq()
    tSend.strHMsg = sHttp
    local s = base.GetSP().new(ProtoMgr.Sys1.WebMain, ProtoMgr.Sub_Web.WebMessReq_CMD)   
    s:AddString(tSend:SerializeToString())
    base.PostToServer(skey, 0, s:GetData(), s:GetSize())
end





return NoticeMess