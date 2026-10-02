--金币范围
local tPublicRedis =require("PublicRedis")

local GoldRange={}

--离散随机变量
--arrDistributiveLaw ={{p=0.3,X=1} ,{p=0.2,X=2} ,{p=0.5,X=3} }  --分布率,所有p相加必需为1
local function XFunc(arrDistributiveLaw)
	local arr ={}
	for _,item in ipairs(arrDistributiveLaw) do
		local tailP =arr[#arr] or 0
		local split =tailP +item.p
		table.insert(arr,split)
	end
	if #arr==0 then
		return
	end
	local nR =math.random()
	for dex,v in ipairs(arr) do
		if nR<v then
			return arrDistributiveLaw[dex].X
		end
	end
	return nil
end

--默认分布率
local tDefault ={{p=0.4,X={nMin =100,nMax=1000}} ,{p=0.6,X={nMin =1000,nMax=10000}} ,{p=0,X={nMin =10000,nMax=20000}}}
local tGroupIdToInfo={}

local function _GetDistributiveLaw(nGroupId)
    local tInfo =tGroupIdToInfo[nGroupId]
    local nCurTime =os.time()
    if tInfo ==nil or (nCurTime -tInfo.nLatelyTime)>10 then
        local tDistributiveLaw ={}
        local arrConfig =tPublicRedis.GetAndroidGoldConfig(nGroupId) or {}
        for _,arr in ipairs(arrConfig) do
            local item ={p=(arr[1]/100),X={nMin=arr[2],nMax=arr[3]}}
            table.insert(tDistributiveLaw,item)
        end
        if #tDistributiveLaw==0 then 
            tDistributiveLaw=nil
         end
        tGroupIdToInfo[nGroupId] ={nLatelyTime=nCurTime,tDistributiveLaw=tDistributiveLaw}
        return tDistributiveLaw
    end
    return tInfo.tDistributiveLaw 
end

function GoldRange.GetRange(nGroupId)
   local tDistributiveLaw =_GetDistributiveLaw(nGroupId) or tDefault
   local tRange = XFunc(tDistributiveLaw)
   return tRange.nMin,tRange.nMax
end

return GoldRange
