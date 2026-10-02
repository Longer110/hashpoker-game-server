local tPubUser = require("PublicUserInfo") -- 用户信息



local TaxGather = {}
function TaxGather:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.tData={}
    t.tUserIdToInfo={}
	return t
end

function _NewUser()
    local tInfo ={}
    tInfo.nProfitSum =0
    tInfo.sTaxTag =string.format("#%s", tPubUser.CreatePaiJuID()) 
    return tInfo
end

---
function TaxGather:Gather(nProfit,nUserId,sPaiJuId)
    local tInfo =self.tUserIdToInfo[nUserId] or _NewUser()
    self.tUserIdToInfo[nUserId] =tInfo
    tInfo.nProfitSum =tInfo.nProfitSum +nProfit
    tInfo.sLatelyPaiJuId =sPaiJuId
    tInfo.sLatelyTableId = sTableId
    return tInfo.sTaxTag
end

function TaxGather:Settle(nUserId,nTaxRate)
    local tInfo =self.tUserIdToInfo[nUserId]
    self.tUserIdToInfo[nUserId]=nil
    if not tInfo then
        return nil
    end
    if tInfo.nProfitSum>0 then
        return tInfo.nProfitSum*nTaxRate,tInfo.sTaxTag,tInfo.sLatelyPaiJuId, tInfo.sLatelyTableId
    end
    return 0,tInfo.sTaxTag,tInfo.sLatelyPaiJuId, tInfo.sLatelyTableId
end

function TaxGather:GetAllUserId()
    local arr={}
    for nUserId,_ in pairs(self.tUserIdToInfo) do
        table.insert(arr,nUserId)
    end
    return arr
end


return TaxGather