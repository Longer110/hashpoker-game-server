--商城的逻辑

local http  = require("socket.http")  -- Http 服务器 
local cjson = require("cjson")   

Store = {
	arrStoreConfig ={},       -- 商城配置
	arrGiftBagConfig ={},     -- 礼包配置
}

local tPayType ={
	[1] ="支付宝",
	[2] = "USDT",
}

-- 测试商城接口
function Store.Test_Store(sClientID)
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("Test_Store not find nUserId by sClientID_%s",tostring(sClientID))
        return false
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("Test_Store 玩家信息不存在_%d   ",nUserId)  
        return
    end  

	Store.OnClubSGetStoreCfgReq(sClientID, "", 1)  -- 测试配置

	Store.OnClubSBuyGoodsReq(sClientID, "", 1)  -- 测试购买商品

end

--数据库返回统一校验
function Store._CheckDbMsg(strProto, Data, nLen)
    local tData =DbClubServAux:Parser(Data, nLen, strProto)
    if not tData then
       Base.Log("%s _Parse Err",strProto)
       return
    end
    return tData
end

-- 加载配置: 商城，礼包 
function Store.LoadStoreConfig()
	--if 1 then return end 

    -- Base.Log("_LoadStoreConfig  加载商城配置")
    local LoadStoreConfigReq = {} 
	LoadStoreConfigReq.sSql = ""
    MsgApi.SendToDBServer("LoadStoreConfigReq",LoadStoreConfigReq)	
	Store.isLoadStoreCfg = true 
	Store.isLoadGiftBagCfg = true 
	return 1
end

--DB服返回  获取商城配置 返回
function Store.OnDBLoadStoreConfigRep(sReturnKey, Data, nLen)
    local strProto = "LoadStoreConfigRep"
    local tData = Store._CheckDbMsg(strProto, Data, nLen)
    if not tData then
		Base.Log("_LoadStoreConfig    LoadStoreConfigRep is nil") 
        return
    end  	 
	if #tData.arrStoreConfig > 0 then  
		if Store.isLoadStoreCfg then 
			Store.arrStoreConfig = {}
			Store.isLoadStoreCfg = false
		end 
		if Store.isWebLoadStoreCfg then 
			Store.arrStoreConfig = {}
			Store.isWebLoadStoreCfg = false
		end 	
		local arrData = {}
		for _,row in pairs(tData.arrStoreConfig) do 
			if row and row.nGoodId then 
				local t = {}
				t.nGoodId = math.floor(row.nGoodId)     			   -- 商品id
				t.nPayType = math.floor(row.nPayType)  			   -- 支付类型
				t.nPayCount = tonumber(row.nPayCount)  			   -- 支付数量
				t.nGiftBagId = math.floor(row.nGiftBagId)     	   -- 礼包id
				t.nLimitStatus = math.floor(row.nLimitStatus)   	   -- 上架状态		
				t.nGroupId =  math.floor(row.nGroupId)            	   -- 分组列表  
				t.sLimitStart = row.sLimitStart					   -- 上架时间
				t.sLimitEnd =  row.sLimitEnd					   -- 下架时间	
				t.sGoodName = row.sGoodName                        -- 商品名称  
				t.nDisplaySort = row.nDisplaySort                  -- 排序字段    
				if not Store.arrStoreConfig[t.nGroupId] then 
					Store.arrStoreConfig[t.nGroupId] = {}				
				end 			
				Store.arrStoreConfig[t.nGroupId][t.nGoodId] = t    
        		-- Base.Log("_LoadStoreConfig nGoodId_%s  tGood_%s ",row.nGoodId,cjson.encode(t))  
				if not arrData[t.nGroupId] then 
					arrData[t.nGroupId] = 0  
				end 
				arrData[t.nGroupId] = arrData[t.nGroupId] + 1
			end  
		end  
		local sLog = ""		
		for nGroupId, value in pairs(arrData) do
			sLog=string.format("%s[%d=%d] ",sLog,nGroupId,value)	 		
		end
		Base.Log("_LoadStoreConfig  商城配置: %s ",sLog)  	
	end 
	if #tData.arrGiftBagConfig > 0 then   
		if Store.isLoadGiftBagCfg then 
			Store.arrGiftBagConfig = {}
			Store.isLoadGiftBagCfg = false
		end  
		if Store.isWebLoadGiftBagCfg then 
			Store.arrGiftBagConfig = {}
			Store.isWebLoadGiftBagCfg = false
		end 
		local arrData = {}
		for k,tGiftBag in pairs(tData.arrGiftBagConfig) do   
			if tGiftBag.nGiftBagId then 
				if not Store.arrGiftBagConfig[tGiftBag.nGiftBagId] then 
					Store.arrGiftBagConfig[tGiftBag.nGiftBagId] = {}
				end 
				Store.arrGiftBagConfig[tGiftBag.nGiftBagId] = tGiftBag.arrItem  
				if not arrData[tGiftBag.nGiftBagId] then 
					arrData[tGiftBag.nGiftBagId] = 0  
				end 
				arrData[tGiftBag.nGiftBagId] = arrData[tGiftBag.nGiftBagId] + 1
			end  
		end		 
		local sLog = ""		
		for nGiftBagId, value in pairs(arrData) do
			sLog=string.format("%s[%d=%d] ",sLog,nGiftBagId,value)		
		end
		Base.Log("_LoadStoreConfig  礼包配置  %s    ",sLog)  	
	end 
end

-- 获取分组商品
function Store.GetGroupGoodIdCfg(nGroupId)
	local arrGood = {}
	for k,arrConfig in pairs(Store.arrStoreConfig) do
		if k == nGroupId then 
			for nGoodId,tGood in pairs(arrConfig) do
				table.insert(arrGood,tGood)  
			end
		end 
	end
	-- Base.Log("_GetGroupGoodIdCfg   获取分组商品   nGroupId_%d  arrGood_%d",nGroupId,#arrGood)   
	return arrGood
end

-- 获取商品
function Store.GetGoodIdCfg(nGoodId)
	for nGroupId,arrGood in pairs(Store.arrStoreConfig) do
		for k, tGood in pairs(arrGood) do
			if k == nGoodId then 
				return tGood 
			end 
		end
	end 
end

-- 获取礼包配置
function Store.GetGiftBagCfg(nGiftBagId)
	local arrGiftBag = Store.arrGiftBagConfig[nGiftBagId]
	if arrGiftBag and #arrGiftBag > 0 then 
		local arrItem = {}
		for k, v in pairs(arrGiftBag) do
			if v and v.nItemId and v.nItemId  > 0 then 
				local t = {}
				t.nItemId = v.nItemId 
				t.nCount = v.nCount 
				t.sGiftBagName = v.sGiftBagName 
				table.insert(arrItem,t)
			end 
		end
		return arrItem 
	end 
end

-- 请求商城配置 
function Store.OnClubSGetStoreCfgReq(sClientID, Data, nLen)
    local tData =SlaveAux:Parser(Data, nLen, "ClubSGetStoreCfgReq")
    if tData ==nil then
        Base.Log("_OnClubSGetStoreCfgReq   _Parse Err")
        return
    end 	 
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("_OnClubSGetStoreCfgReq not find nUserId by sClientID_%s",tostring(sClientID))
        return false
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSGetStoreCfgReq 玩家信息不存在_%d   ",nUserId)  
        return
    end  
	local nGroupId = math.floor(tUser.nGroupId)
	local nCnt = 0 
	local arrGoodCfg = {}
	local arrGoodInfo = Store.GetGroupGoodIdCfg(nGroupId)	
	for nGoodId,tGood in ipairs(arrGoodInfo) do
		nCnt = nCnt + 1
	end 
	for nGoodId,tGood in ipairs(arrGoodInfo) do
		local t = {}
		t.nGoodId = tGood.nGoodId
		t.sGoodName = tGood.sGoodName
		t.nPayType = tGood.nPayType
		t.nPayCount = tGood.nPayCount 
		t.nDisplaySort = tGood.nDisplaySort  		 
		local arrGiftBag = Store.GetGiftBagCfg(tGood.nGiftBagId)
		if arrGiftBag then 
			t.arrGiftBag = arrGiftBag
			table.insert(arrGoodCfg,t) 
			if #arrGoodCfg >= 10 or #arrGoodCfg == nCnt then 
				-- 下发商城配置 
				local ClubSGetStoreCfgRep = {} 
				ClubSGetStoreCfgRep.arrGoodCfg = arrGoodCfg
				MsgApi.SendToUser(nUserId,"ClubSGetStoreCfgRep",ClubSGetStoreCfgRep)
				arrGoodCfg = {}
			end 
		else
			Base.Log("_OnClubSGetStoreCfgReq nGoodId_%d  nGiftBagId_%d arrGiftBag is nil ",nGoodId,tGood.nGiftBagId)  
		end 
	end
	Base.Log("_OnClubSGetStoreCfgReq 请求商城配置 玩家_%d  nGroupId_%s nCnt_%d %d  ",nUserId,nGroupId,nCnt,#arrGoodInfo)  
end 
 
 -- 请求商城购买
function Store.OnClubSBuyGoodsReq(sClientID, Data, nLen)
    local tData =SlaveAux:Parser(Data, nLen, "ClubSBuyGoodsReq")
    if tData ==nil then
        Base.Log("ClubSBuyGoodsReq   _Parse Err")
        return
    end
	local nGoodId = tData.nGoodId
	local nPayType =  tData.nPayType
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("_OnClubSBuyGoodsReq not find nUserId by sClientID_%s",tostring(sClientID))
        return false
    end
	Base.Log("_OnClubSBuyGoodsReq 请求购买商品 nUserId_%d nGoodId_%d  nPayType_%d  ",nUserId,nGoodId,nPayType)
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSBuyGoodsReq 玩家信息不存在_%d   ",nUserId)  
        return
    end  
	local tGoodInfo = Store.GetGoodIdCfg(nGoodId) 
	if not tGoodInfo then 
        Base.Log("_OnClubSBuyGoodsReq 玩家_%d nGoodId_%d  tGoodInfo is nil",nUserId,nGoodId)  		
		return 
	end 
	-- 创建订单
	local sPayType = tPayType[nPayType] or ""  -- 支付方式
	local sSql="Call PayOrder_Create("..nUserId..","..nGoodId..","..tGoodInfo.nPayCount..",'"..Base.m_tKey.."Gateway'"..",'"..sPayType.."','"..tGoodInfo.nGroupId.."')"
    local PayOrder_CreateReq = {} 
	PayOrder_CreateReq.nUserId = nUserId 
	PayOrder_CreateReq.sSql = sSql 
	PayOrder_CreateReq.sExData = Cjson.encode({sPayType=sPayType,nPayCount=tGoodInfo.nPayCount})
    MsgApi.SendToDBServer("PayOrder_CreateReq",PayOrder_CreateReq,nUserId)	
end 

-- 创建订单返回	 
function Store.OnDBPayOrder_CreateRep(sReturnKey, Data, nLen)
    local strProto = "PayOrder_CreateRep"
    local tData = Store._CheckDbMsg(strProto, Data, nLen)
    if not tData then
		Base.Log("_OnDBPayOrder_CreateRep  is nil") 
        return
    end  	
    local tUser = UserManager.GetUserInfo(tData.nUserId)
    if not tUser then
        Base.Log("_OnDBPayOrder_CreateRep 玩家信息不存在_%d   ",tUser.nUserId)  
        return
    end  
	if tData.nId <= 0 then   
		Base.Log("_OnDBPayOrder_CreateRep  nUserId_%d nId_%d 创建订单失败  ",tUser.nUserId,tData.nId)  		
		return 
	end 
	Base.Log("_OnDBPayOrder_CreateRep  nUserId_%d nId_%d 创建订单成功  sExData:%s",tUser.nUserId,tData.nId,tData.sExData or "") 
	
	local ClubSBuyGoodsRep = {} 
	ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.Success
	ClubSBuyGoodsRep.nId = tData.nId

	if tData.nId <= 0 then   
		Base.Log("_OnDBPayOrder_CreateRep  nUserId_%d nId_%d 创建订单失败  ",tUser.nUserId,tData.nId)
		ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.CreateOrderFail
		MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
		return  		
	end

	local isSuccee,tExData = pcall(Cjson.decode,tData.sExData)
	if not isSuccee then
		Base.Log("_OnDBPayOrder_CreateRep decode sExData fail ")
		ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.OrderInfoLack
		MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
		return
	end

	--USDT渠道
	if tExData.sPayType==tPayType[2] then
		if not tExData.nPayCount then
			Base.Log("_OnDBPayOrder_CreateRep nPayCount 丢失 ")
			ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.OrderInfoLack
			MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
			return
		end
	
		if not tExData.sOrderid then
			Base.Log("_OnDBPayOrder_CreateRep sOrderid 丢失 ")
			ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.OrderInfoLack
			MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
			return
		end
	
		local sDomainName =  RedisCahche.GetPayDomainName(Define.DomainName.Pay)
		if not sDomainName then
			local sSendSMS = "后台没有设置USDT渠道充值的域名"
			Base.Log("_OnDBPayOrder_CreateRep %s",sSendSMS)
			ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.OrderInfoLack
			MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
			MsgApi.SendToTGChat(sSendSMS)
			return
		end

		-- http://192.168.0.215:82/api/Pay/createpay?PayAmount=0.01&PayOrderId=10001&id=101 
		local sUrl = string.format("%s?PayAmount=%.2f&PayOrderId=%s&id=%d",sDomainName,tExData.nPayCount,tExData.sOrderid,tData.nId)
		Base.Log("_OnDBPayOrder_CreateRep  请求 sUrl:%s",sUrl)
		local sResult = http.request(sUrl)   
		local isSuccee,tRlt = pcall(Cjson.decode,sResult)
		if not isSuccee then  
			Base.Log("_OnDBPayOrder_CreateRep  解析失败 sResult=%s,sUrl:%s",sResult,sUrl)
			ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.WebErr
			MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
			return
		end 
		Base.Log("_OnDBPayOrder_CreateRep  请求成功 code:%d msg:%s",tRlt.code,tRlt.msg)

		if tRlt.code~=1 then
			--第三方生成订单失败
			ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.ThirdOrderFail
			MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
			return
		end

		local isSuccee1,tWebData = pcall(Cjson.decode,tRlt.data)
		if not isSuccee1 then
			Base.Log("_OnDBPayOrder_CreateRep  decode tRlt.data fail")
			ClubSBuyGoodsRep.nRlt = PubErrCode.BuyGoods.WebErr
			MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)
			return
		end

		local tUSTInfo = {}
		tUSTInfo.nAmount =  PublicApi.Floor_2(tonumber(tWebData.amount) or 0)
		tUSTInfo.sThirdId = tWebData.id
		tUSTInfo.sOrderid = tWebData.orderid
		tUSTInfo.nState = tonumber(tWebData.state) or 0
		tUSTInfo.sNavurl = tWebData.navurl
		ClubSBuyGoodsRep.tUSTInfo = tUSTInfo
		Base.Log("_OnDBPayOrder_CreateRep  tUSTInfo:%s",Cjson.encode(tUSTInfo))
	end

	MsgApi.SendToUser(tData.nUserId,"ClubSBuyGoodsRep",ClubSBuyGoodsRep)

	-- 测试流程
    -- local sKey = "IMAppWebKey"
	-- local tRedis =Base.m_MyRedisData[2].redis 
    -- local sUrl = tRedis:hget(sKey,"Stor_Pay_Test") 
	-- -- local sUrl = "http://192.168.0.215:82/Text/Index1?nId=1"
	-- sUrl = string.format("%s%d&nStatus=1",sUrl,tData.nId)
    -- local sResult = http.request(sUrl)   
    -- local isSuccee,tRlt = pcall(cjson.decode,sResult)
	-- if not isSuccee then  
	-- 	Base.Log("_OnDBPayOrder_CreateRep  解析失败 sResult=%s,sUrl:%s",sResult,sUrl)
	-- else
	-- 	Base.Log("_OnDBPayOrder_CreateRep  请求成功 sUrl:%s",sUrl)
	-- end 
end 

-- 后台支付通知	 
function Store.OnWebRepPayResult(sReturnKey, Data, nLen)
    local tData =BackstageAux:Parser(Data, nLen,"StorePayReq")
    if not tData then
       Base.Log("_OnWebRepPayResult  StorePayReq _Parse Err")
       return
    end
	if tData.nId <= 0 then   
		Base.Log("_OnWebRepPayResult 后台支付通知  nId_%d  " ,tData.nId)  		
		return 
	end 
	local nId = tData.nId 
	local nStatus = tData.nStatus 
 	Base.Log("_OnWebRepPayResult 后台支付通知  nId_%d  nStatus_%d  ",tData.nId,nStatus)  
	-- 处理订单 
	local sSql= "Call PayOrder_Deal("..nId..","..nStatus..")"
    local PayOrder_DealReq = {} 
	PayOrder_DealReq.nType = 1 
	PayOrder_DealReq.nId = nId 
	PayOrder_DealReq.sSql = sSql  	 
    MsgApi.SendToDBServer("PayOrder_DealReq",PayOrder_DealReq)	
	return 
end 

-- 后台 通知加载配置
function Store.OnWebLoadConfig(sReturnKey, Data, nLen)
	Base.Log("_OnWebLoadConfig  后台通知加载配置")  	 
	Store.isWebLoadStoreCfg = true 
	Store.isWebLoadGiftBagCfg = true 
    local LoadStoreConfigReq = {} 
	LoadStoreConfigReq.sSql = ""
    MsgApi.SendToDBServer("LoadStoreConfigReq",LoadStoreConfigReq)	
end

-- 处理订单返回
function Store.OnDBPayOrder_DealRep(sReturnKey, Data, nLen)
    local strProto = "PayOrder_DealRep"
    local tData = Store._CheckDbMsg(strProto, Data, nLen)
    if not tData then
		Base.Log("_OnDBPayOrder_DealRep  is nil") 
        return
    end  	
	if tData.nFlag ~= 1 then   		
        local tStatus ={[2] = "已给道具",[3] = "支付取消",[4] = "支付失败",[5] = "重复使用过的苹果订单无效的订单"}
        local sStatus = tStatus[tData.nFlag] or "未支付"
		Base.Log("_OnDBPayOrder_DealRep  nUserId_%d nId_%d  处理订单失败：%s ",tData.nUserId,tData.nId,sStatus)  		
		return 
	end 
	Base.Log("_OnDBPayOrder_DealRep  nUserId_%d nId_%d  nGoodId_%d 处理订单成功  ",tData.nUserId,tData.nId,tData.nGoodId)  
	local tGoodInfo = Store.GetGoodIdCfg(tData.nGoodId) 
	if not tGoodInfo then 
		local SendSMS = string.format("_OnDBPayOrder_DealRep  nUserId_%d nGoodId_%d tGoodInfo is nil",tData.nUserId,tData.nGoodId)  	
        Base._OnMonitorInfo(SendSMS)   
        Base.Log(SendSMS)  	     	
		return 
	end 
	local arrGiftBag = Store.GetGiftBagCfg(tGoodInfo.nGiftBagId)
	if not arrGiftBag then 
		local SendSMS = string.format("_OnDBPayOrder_DealRep nUserId_%d nGoodId_%d nGiftBagId_%d  arrGiftBag is nil",tData.nUserId,tData.nGoodId,tGoodInfo.nGiftBagId) 	
        Base._OnMonitorInfo(SendSMS)   
        Base.Log(SendSMS)  	     		
		return 
	end 
	-- 下发礼包 
	Base.Log("_OnDBPayOrder_DealRep  下发礼包 nUserId_%d nGoodId_%d nGiftBagId_%d  ",tData.nUserId,tData.nGoodId,tGoodInfo.nGiftBagId)  
	for _, v in pairs(arrGiftBag) do
		if v and v.nItemId and v.nItemId > 0 and v.nCount > 0 then 
			local nSourceType = 200000  -- 俱乐部充值
			PublicUserInfo.ChangeUserTreasure({nUserID =tData.nUserId,nItemID=v.nItemId,nDel= PublicApi.Floor_2(v.nCount),nSourceType=nSourceType})
		end 
	end
	local t = {}	
	t.nGiftBagId = tGoodInfo.nGiftBagId
	t.arrGiftBag = arrGiftBag
	-- 写购买记录  	
	local sGiftBagInfo = Cjson.encode(t)
	local sSql= "Call Store_Buy_Record("..tData.nUserId..","..tData.nId..","..tData.nGoodId..","..tGoodInfo.nPayType..","..tGoodInfo.nPayCount..",'"..sGiftBagInfo.."')"
    local PayOrder_DealReq = {} 
	PayOrder_DealReq.nType = 2
	PayOrder_DealReq.nId = tData.nUserId 
	PayOrder_DealReq.sSql = sSql  	 
    MsgApi.SendToDBServer("PayOrder_DealReq",PayOrder_DealReq,tData.nUserId)	 
    local tUser = PublicUserInfo.GetUserInfo(tData.nUserId)
    if not tUser or tUser == nil  then
        Base.Log("_OnDBPayOrder_DealRep nUserId_%d 不在线，不通知",tData.nUserId)  
        return
    end  
	if not tUser.sClientID then 
        Base.Log("_OnDBPayOrder_DealRep nUserId_%d  sClientID is nil ",tData.nUserId)  
        return
	end 
	local ClubSPayResultRep = {} 
	ClubSPayResultRep.nGoodId = tData.nGoodId  
	ClubSPayResultRep.nRlt = 0 
	ClubSPayResultRep.arrGiftBag = arrGiftBag 	
	MsgApi.SendToClient(tUser.sClientID..":0","ClubSPayResultRep",ClubSPayResultRep)
	return 
end 

local function CreateUserIdByToken(nUserId,nGroupId)   
	local sNewToken =string.format("sToken_%d_%d%d",os.time(),math.random(99999,90000000),math.random(9999999,90000000))
	local sInfo = string.format("%d=%d",nUserId,nGroupId)
	Base.m_MyRedisData[1].redis:set(sNewToken,sInfo)
	Base.m_MyRedisData[1].redis:expire(sNewToken,60*5)   -- 一分钟 有效期
	return nUserId,sNewToken
end

local function _GetPayUrl(nType) 
	if nType == 1 then  
		return RedisCahche._GetPayUrl("sPayUrl") or ""   -- 充值
	else		
		return RedisCahche._GetPayUrl("sWithDrowUrl") or ""   -- 提现 
	end 
end 

-- 请求充值 信息 
function Store.OnClubSPayInfoReq(sClientID, Data, nLen)
    local tData =SlaveAux:Parser(Data, nLen, "ClubSPayInfoReq")
    if tData ==nil then
        Base.Log("_OnClubSPayInfoReq   _Parse Err")
        return
    end  
	local nType = tData.nType
    local nUserId =ClientIdMgr.GetUserIdByClientId(sClientID)
    if not nUserId or nUserId < 0 then
        Base.Log("_OnClubSPayInfoReq not find nUserId by sClientID_%s",tostring(sClientID))
        return false
    end
    local tUser = UserManager.GetUserInfo(nUserId)
    if not tUser then
        Base.Log("_OnClubSPayInfoReq  玩家信息不存在_%d   ",nUserId)  
        return
    end  
	local nGroupId = tUser.nGroupId 
	Base.Log("_OnClubSPayInfoReq 请求充值 信息 nUserId_%d  nType_%d ",nUserId,nType)
	local ClubSPayInfoRep = {} 
	ClubSPayInfoRep.nType = nType 
	ClubSPayInfoRep.arrPayRecord = {} 
	if nType == 1 or nType == 3 then  -- 获取token  
        local nTokenUserId,sNewToken = CreateUserIdByToken(nUserId,nGroupId)
		ClubSPayInfoRep.sToken = sNewToken 		
 		ClubSPayInfoRep.sUrl =  _GetPayUrl(nType) or ""
		if #ClubSPayInfoRep.sUrl < 5 then 
            local sSend = string.format("无充值提现网页地址配置  Key: IMAppWebKey  sPayUrl ")
            Base._OnMonitorInfo(sSend)
		end 
		Base.Log("_OnClubSPayInfoReq 请求充值信息 nUserId_%d  sNewToken: %s ",nUserId,sNewToken)
	else
		local ClubGetPayOrderReq = {}
		ClubGetPayOrderReq.nUserId = nUserId 
		MsgApi.SendToDBServer("ClubGetPayOrderReq",ClubGetPayOrderReq,nUserId)
		return 
	end  	
	MsgApi.SendToClient(sClientID..":0","ClubSPayInfoRep",ClubSPayInfoRep)
end

--DB服返回   账单查询   
function Store.OnDBClubGetPayOrderRep(sReturnKey, Data, nLen)
    local strProto = "ClubGetPayOrderRep"
    local tData = MsgClient._CheckDbMsg(strProto, Data, nLen)
    if not tData then
        return
    end
	Base.Log("_OnDBClubGetPayOrderRep  账单查询 nUserId_%d  arrPayRecord_%d ",tData.nUserId,#tData.arrPayRecord)

    local arrPayRecord = {}   
    for k,row in pairs(tData.arrPayRecord) do  
		if row.id and row.id > 0 then 
			local tRecord = {}
			tRecord.sCreateTime = row.sCreateTime or ""
			tRecord.nPayType = row.nPayType or 0
			tRecord.nChannelType = tonumber(row.nChannelType) or 0
			tRecord.nGoldType = tonumber(row.nGoldType) or 0
			tRecord.nCount = tonumber(row.nCount) or 0
			tRecord.nGoldChange = tonumber(row.nGoldChange) or 0
			tRecord.nBalance = tonumber(row.nBalance) or 0  
			tRecord.id = tonumber(row.id) or 0  
			tRecord.nAuditStatus = tonumber(row.nAuditStatus) or 0  
			tRecord.nExchangeRate = tonumber(row.nExchangeRate) or 0   
			tRecord.sBankAccount = row.sBankAccount or ""   
			tRecord.nState = tonumber(row.nState) or 0   
			table.insert(arrPayRecord,tRecord)
			if #arrPayRecord >= 130 or #tData.arrPayRecord == k then 
				local ClubSPayInfoRep = {} 
				ClubSPayInfoRep.nType = 2 	
				ClubSPayInfoRep.arrPayRecord = arrPayRecord
				Base.Log("_OnDBClubGetPayOrderRep nUserId_%d  arrPayRecord_%d ",tData.nUserId,#arrPayRecord)	 
				MsgApi.SendToUser(tData.nUserId,"ClubSPayInfoRep",ClubSPayInfoRep)
				arrPayRecord = {}
			end 
		end 
    end
end


return Store 
