local ClubC = {}

function ClubC:New()
	local t = {}
	setmetatable(t, self)
	self.__index = self
	t.Timer = TimerAux:New()   --初始化定时器
	t.nClubId = 0 --俱乐部id
	t.sClubName = "" --俱乐部名称
	t.nClubGold = 0 --俱乐部资产(俱乐部币)
	t.nIncome = 0 --总收益(俱乐部币)
	t.nTodayIncome = 0 --今日收益(俱乐部币)
	t.nMaxUserCnt = Define.nMaxUserCnt --俱乐部最大人数
	t.nClubTax = Define.nClubTax --俱乐部桌服务费分成
	t.nInsuranceTax = Define.nInsuranceTax --俱乐部保险分成
	t.nGroupId = 0 --分组id
	t.nMaster = 0 --主席id
	t.tMasterInfo = {} --主席信息
	t.sCreateTime = "1970-01-01 08:00:00" --俱乐部创建时间
	t.nUserCnt = 0 --成员数目
	t.nCanSearch = 0 --是否允许搜索 0:允许 1:不允许
	t.nCanApply = 0 --是否允许申请加入 0:允许 1:不允许
	t.sPassWord = "" --库存密码
	t.nApplyJionCnt=0; --加入俱乐部申请数目
	t.nApplyAddGoldCnt=0; --增加俱乐部币申请数目
	t.nApplyCutGoldCnt=0; --增加俱乐部币申请数目
	t.nTableIndex = 1 --牌桌顺序id
	t.IsNeedAndroid = false --牌桌是否加载机器人
	t.IsUseGold = true --俱乐部是否使用金币
	t.IsUserClubGold = true --俱乐部是否使用俱乐部币
	t.nGold = 0 --俱乐部资产(金币)
	t.nGoldIncome = 0 --总收益(金币)
	t.nGoldTodayIncome = 0 --今日收益(金币)
	t.nCheckTableIndex = 0 --检查到的牌桌的index
	t.isCheckTableEnd = true --是否进行一轮牌桌检查结束

	t.arrTable = {} --俱乐部牌桌列表
	t.tGameServer = {} --牌桌对应的游戏服id
	t.tNotExistGameServer = {} --可能已经不存在的游戏服
	t.tNotExistCenterServer = {} --可能已经不存在的俱乐部中心服
  
	return t
end

--初始化场景数据
function ClubC:InitScene(tData)
	self.sClubName = tData.sClubName or ""
	self.nClubGold = tData.nClubGold or 0
	self.nIncome = tData.nIncome or 0
	self.nMaster = tData.nMaster or 0
	self.sCreateTime = tData.sCreateTime or "1970-01-01 08:00:00"
	self.nUserCnt = tData.nUserCnt or 0
	self.nCanSearch = tData.nCanSearch or 0
	self.nCanApply = tData.nCanApply or 0
	self.sPassWord = tData.sPassWord or ""
	self.nApplyJionCnt=tData.nApplyJionCnt or 0
	self.nApplyAddGoldCnt=tData.nApplyAddGoldCnt or 0
	self.nApplyCutGoldCnt=tData.nApplyCutGoldCnt or 0
	self.nGold=tData.nGold or 0
	self.nGoldIncome=tData.nGoldIncome or 0

	--主席公共信息
	local tMasterInfo = {}
	tMasterInfo.sShopAcc=tData.sShopAcc or ""
	tMasterInfo.sFaceId=tData.sFaceId or ""
	tMasterInfo.sName=tData.sName or ""
	tMasterInfo.nSex=tData.nSex or 0
	tMasterInfo.nMaster=tData.nMaster or 0
	self.tMasterInfo = tMasterInfo

	if self.nClubId >= Define.nMinClubId then
		--私人俱乐部
		self.nTodayIncome = PublicRedis.GetClubTodayIncome(self.nClubId,self.nClubId) --今日收益(俱乐部币)
		self.nGoldTodayIncome = PublicRedis.GetClubTodayIncome(self.nClubId,1) --今日收益(金币)
	end
	--加载俱乐部配置
	self:UpDateClubConfig(true)
	--加载牌桌
	self:LoadClubTable()
end

--延迟更新俱乐部后台配置
function ClubC:DelayUpDateClubConfig()
	local func = function ()
		self:UpDateClubConfig()
	end
	self.Timer:DelayCall(math.random(1,10*1000),func)
end

--更新俱乐部后台配置
--@params IsNotNotify 是否不需要通知从服
function ClubC:UpDateClubConfig(IsNotNotify)
	local tConfig = PubClubApi.GetClubWebConfig(self.nGroupId)
	-- self:Print("_UpDateClubConfig tConfig_%s",Cjson.encode(tConfig))

	local arrChange = {}

	--俱乐部最大人数
	local nOldMaxUserCnt = self.nMaxUserCnt
	self.nMaxUserCnt = tConfig.nMaxUserCnt
	
	local OldIsNeedAndroid = self.IsNeedAndroid
	local nOldClubTax = self.nClubTax
	local nOldInsuranceTax = self.nInsuranceTax
	local nOldIsUseGold = self.IsUseGold
	local nOldIsUserClubGold = self.IsUserClubGold
	if self.nClubId<Define.nMinClubId then
		--大厅
		--牌桌是否加载机器人
		self.IsNeedAndroid = tConfig.IsNeedAndroidInHall

		self.nClubTax = 0 --俱乐部桌服务费分成
		self.nInsuranceTax = 0 --俱乐部保险分成
		self.IsUseGold = true --俱乐部是否使用金币
		self.IsUserClubGold = false --俱乐部是否使用俱乐部币
	else
		--俱乐部
		--牌桌是否加载机器人
		self.IsNeedAndroid = tConfig.IsNeedAndroidInClub

		--俱乐部桌服务费分成
		self.nClubTax = tConfig.nClubTax

		--俱乐部保险分成
		self.nInsuranceTax = tConfig.nInsuranceTax

		--俱乐部是否使用金币
		self.IsUseGold = tConfig.IsUseGold

		--俱乐部是否使用俱乐部币
		self.IsUserClubGold = tConfig.IsUserClubGold
	end

	if IsNotNotify then
		return
	end

	if nOldMaxUserCnt~=self.nMaxUserCnt then
		table.insert(arrChange,{sKey="nMaxUserCnt",Val=self.nMaxUserCnt})
	end
	if nOldClubTax~=self.nClubTax then
		table.insert(arrChange,{sKey="nClubTax",Val=self.nClubTax})
	end
	if nOldInsuranceTax~=self.nInsuranceTax then
		table.insert(arrChange,{sKey="nInsuranceTax",Val=self.nInsuranceTax})
	end
	if OldIsNeedAndroid~=self.IsNeedAndroid then
		table.insert(arrChange,{sKey="IsNeedAndroid",Val=self.IsNeedAndroid})
	end
	if nOldIsUseGold~=self.IsUseGold then
		table.insert(arrChange,{sKey="IsUseGold",Val=self.IsUseGold})
	end
	if nOldIsUserClubGold~=self.IsUserClubGold then
		table.insert(arrChange,{sKey="IsUserClubGold",Val=self.IsUserClubGold})
	end

	self:ClubConfigChange(arrChange)
end

--加载redis上的俱乐部牌桌
function ClubC:LoadClubTable()
	local arrTableInfo = PublicRedis.GetAllClubTableInfo(self.nClubId)
	local now = os.time()
	if type(arrTableInfo)=="table" then
		for sTableId,sTableInfo in pairs(arrTableInfo) do
			repeat
				if PublicRedis.CheckTableIsExits(sTableId) then
					local isSuccee,tTableInfo = pcall(Cjson.decode,sTableInfo)
					if isSuccee then
						local nOpentime = tonumber(tTableInfo.nOpentime) or 0
						local nKeepTime = tonumber(tTableInfo.nKeepTime) or 0
						if nOpentime > 0 and now >= (nOpentime + nKeepTime) then
							PublicRedis.DelClubTableInfo(self.nClubId,sTableId)
							break
						end
						table.insert(self.arrTable,tTableInfo)
						self:Print("_LoadClubTable 加载redis上的俱乐部牌桌 sTableInfo:%s",sTableInfo)
					else
						self:Print("_LoadClubTable 加载redis上的俱乐部牌桌 decode sConfig fail,sTableId:%s,sTableInfo:%s",sTableId,sTableInfo)
					end
				else
					self:Print("_LoadClubTable 加载redis上的俱乐部牌桌 table is not exits,sTableId:%s",sTableId)
					PublicRedis.DelClubTableInfo(self.nClubId,sTableId)
				end
			until true
		end
	end
end

--获取某张牌桌的信息
--@params sTableId:牌桌id
function ClubC:GetTableInfo(sTableId)
	for nIndex,tTable in pairs(self.arrTable) do
		if tTable.sTableId==sTableId then 
			return tTable
		end
	end
end

--延迟检查牌桌所在服务器是否还在
function ClubC:DelayCheckServerOfTable()
	local func = function ()
		self:CheckServerOfTable()
	end
	self.Timer:DelayCall(math.random(1,10*1000),func)
end

--检查牌桌所在服务器是否还在
function ClubC:CheckServerOfTable()
	local nNow = os.time()
	for nServerId,sServerKey in pairs(self.tGameServer) do
		local bExist = Base.m_centerRedis.Mo:exists(sServerKey) or false
		if not bExist then
			if not self.tNotExistGameServer[nServerId] then
				self.tNotExistGameServer[nServerId] = nNow --记录serverkey不存在的游戏服
			end
		else
			self.tNotExistGameServer[nServerId] = nil --删除serverkey不存在的游戏服
		end
	end

	local tLoseRelationServer = {} --serverkey不存在，而且超过一段时间了
	for nServerId,nTime in pairs(self.tNotExistGameServer) do
		self:Print("定时检查牌桌所在服务器是否还在 nServerId_%d 首次失联:%s 现在:%s 时间差_%d 超时时间_%d",
			nServerId,os.date("%Y-%m-%d %H:%M:%S",nTime),os.date("%Y-%m-%d %H:%M:%S",nNow),nNow-nTime,Define.nAutoCloseTime)
		if nNow-nTime>=Define.nAutoCloseTime then
			tLoseRelationServer[nServerId] = nServerId
		end
	end

	for nServerId,_ in pairs(tLoseRelationServer) do
		self:Print("已经确认挂掉的服务器 nServerId_%d",nServerId)
	end

	for nIndex,tTable in pairs(self.arrTable) do
		if tTable.nServerId and tLoseRelationServer[tTable.nServerId] then
			self:Print("牌桌所在服务器已经不存在,关闭牌桌 tTable:%s",Cjson.encode(tTable))
			self:TableClose(nIndex,tTable)
		end
	end

	--删除缓存
	for nServerId,nTime in pairs(self.tNotExistGameServer) do
		if tLoseRelationServer[nServerId]  then
			self.tNotExistGameServer[nServerId] = nil
		end
	end 
	for nServerId,sServerKey in pairs(self.tGameServer) do
		if tLoseRelationServer[nServerId]  then
			self.tGameServer[nServerId] = nil
		end
	end
end

--延迟检查牌桌是否还存在
function ClubC:DelayCheckTableIsExits()
	if not self.isCheckTableEnd then
		return
	end
	self.isCheckTableEnd = false
	local func = function ()
		self:CheckTableIsExits(#self.arrTable)
	end
	self.Timer:DelayCall(math.random(1,10*1000),func)
end

--检查牌桌是否还存在
function ClubC:CheckTableIsExits(nBegin)
	if nBegin<=0 then
		self.isCheckTableEnd = true
		return
	end

	local nEnd = math.max(1,nBegin-Define.nCheckTableCnt)
	for i=nBegin,nEnd,-1 do
		local tTable = self.arrTable[i]
		if tTable then
			if not PublicRedis.CheckTableIsExits(tTable.sTableId) then
				self:Print("_CheckTableIsExits redis上的俱乐部牌桌信息不存在 table is not exits,sTableId:%s",tTable.sTableId)
				PublicRedis.DelClubTableInfo(self.nClubId,sTableId)
			end
		end
	end

	if nEnd>1 then
		--还有牌桌没检测完，1s后继续检测
		local func = function ()
			self:CheckTableIsExits(nEnd-1)
		end
		self.Timer:DelayCall(1000,func)
	else
		self.isCheckTableEnd = true
	end 
end

--延迟检查俱乐部所在中心服id是否能删掉
function ClubC:DelayCheckCenterId()
	local func = function ()
		self:CheckCenterId()
	end
	self.Timer:DelayCall(math.random(1,10*1000),func)
end

--检查俱乐部所在中心服id是否能删掉
function ClubC:CheckCenterId()
	local nNow = os.time()
	local arrCenterServId =  PublicRedis.GetClubCenterSerArray(self.nClubId)
	for _,nServId in pairs(arrCenterServId) do
		local sKey = Base.GetServerIdIdKey(nServId)
		if sKey then
			self.tNotExistCenterServer[nServId] = nil
		else
			if not self.tNotExistCenterServer[nServId] then
				self.tNotExistCenterServer[nServId] = nNow --记录serverkey不存在的中心服
			end
		end
	end

	local tLoseRelationServer = {} --serverkey不存在，而且超过一段时间了
	for nServerId,nTime in pairs(self.tNotExistCenterServer) do
		self:Print("定时检查俱乐部所在服务器是否还在 nServerId_%d 首次失联:%s 现在:%s 时间差_%d 超时时间_%d",
			nServerId,os.date("%Y-%m-%d %H:%M:%S",nTime),os.date("%Y-%m-%d %H:%M:%S",nNow),nNow-nTime,Define.nDelectServIdTime)
		if nNow-nTime>=Define.nDelectServIdTime then
			tLoseRelationServer[nServerId] = nServerId
		end
	end

	for nServerId,_ in pairs(tLoseRelationServer) do
		self:Print("已经确认挂掉的俱乐部中心服务器 nServerId_%d",nServerId)
		PublicRedis.DelClubCenterSrvKey(self.nClubId,nServerId)
	end

	--删除缓存
	for nServerId,nTime in pairs(self.tNotExistCenterServer) do
		if tLoseRelationServer[nServerId]  then
			self.tNotExistCenterServer[nServerId] = nil
		end
	end 
end

--延迟刷新过期的申请
function ClubC:DelayToReqRefreshApply()
	local func = function ()
		local ClubApplyInvalidReq = {}
		ClubApplyInvalidReq.nClubId = self.nClubId
		MsgApi.SendToDBServer("ClubApplyInvalidReq",ClubApplyInvalidReq)
	end
	
	self.Timer:DelayCall(math.random(1,10*1000),func)
end

--刷新俱乐部申请数量
function ClubC:RefreshApplyCnt(tData)
	self:Print("_RefreshApplyCnt 刷新俱乐部申请数量 nApplyJionCnt:%d nApplyAddGoldCnt:%d nApplyCutGoldCnt:%d",tData.nApplyJionCnt,tData.nApplyAddGoldCnt,tData.nApplyCutGoldCnt)

	local isRefresh = false
	local tChangeInfo = {}
	if self.nApplyJionCnt~=tData.nApplyJionCnt  then
		self.nApplyJionCnt=tData.nApplyJionCnt --加入俱乐部申请数目
		tChangeInfo.nApplyJionCnt = self.nApplyJionCnt
		isRefresh = true
	end
	if self.nApplyAddGoldCnt~=tData.nApplyAddGoldCnt then
		self.nApplyAddGoldCnt=tData.nApplyAddGoldCnt --增加俱乐部币申请数目
		tChangeInfo.nApplyAddGoldCnt = self.nApplyAddGoldCnt
		isRefresh = true
	end
	if self.nApplyCutGoldCnt~=tData.nApplyCutGoldCnt then
		self.nApplyCutGoldCnt=tData.nApplyCutGoldCnt --增加俱乐部币申请数目
		tChangeInfo.nApplyCutGoldCnt = self.nApplyCutGoldCnt
		isRefresh = true
	end

	if isRefresh then
		--通知从服
		local ClubCSceneChangeNotify = {}
		ClubCSceneChangeNotify.nClubId = self.nClubId
		ClubCSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo)
		MsgApi.Broadcast("ClubCSceneChangeNotify",ClubCSceneChangeNotify)
	end
end

-------------------从服消息 start---------------------------
--从服消息处理
function ClubC:OnSlaveMsgHandle(sReturnKey,strReq,tData)
	--俱乐部从服
	if strReq =="ClubCSceneChangeReq" then	--俱乐部场景信息改变请求
		self:_OnClubCSceneChangeReq(sReturnKey,tData)
		return
	end

	--其它游戏中心服
	if strReq =="ClubCGameOpenTableNotify" then	--俱乐部桌开桌通知
		self:_OnClubCGameOpenTableNotify(sReturnKey,tData)
		return
	end

	if strReq =="ClubCGameCloseTableNotify" then	--游戏服关桌通知
		self:_OnClubCGameCloseTableNotify(sReturnKey,tData)
		return
	end

	if strReq =="ClubCGameTableInfoNotify" then	--游戏服牌桌信息改变通知
		self:_OnClubCGameTableInfoNotify(sReturnKey,tData)
		return
	end

	if strReq =="ClubCGameUserSettleNotify" then	--游戏服玩家结算通知
		self:_OnClubCGameUserSettleNotify(sReturnKey,tData)
		return
	end

	self:Print("_OnSlaveMsgHandle strReq_%s 没有对应的处理函数",strReq)
end

--俱乐部场景通知
--@params sServerKey:从服key,不传则通知所有从服
function ClubC:SceneNotify(sServerKey)
	self:Print("__OnSceneNotify sServerKey:")
	-- 通知游戏服
	local ClubCSceneNotify = {}
	ClubCSceneNotify.nClubId = self.nClubId
	ClubCSceneNotify.tScence =  self:GetScence()
	if sServerKey then
		MsgApi.SendToSlaveServer(sServerKey,"ClubCSceneNotify",ClubCSceneNotify)
	else
		MsgApi.Broadcast("ClubCSceneNotify",ClubCSceneNotify)
	end
end

--俱乐部场景信息改变请求
function ClubC:_OnClubCSceneChangeReq(sReturnKey,tData)

	self:Print("__OnClubCSceneChangeReq sChangeInfo:%s",tData.sChangeInfo)

	local isSuccee1,tChangeInfo = pcall(Cjson.decode,tData.sChangeInfo)
	if not isSuccee1 then
		self:Print("__OnClubCSceneChangeReq decode sChangeInfo fail")
		if type(tChangeInfo) == "string" then 
			Logger:error(tChangeInfo)
		else 
			Base.LogT(tChangeInfo)
		end
		return
	end

	for k,v in pairs(tChangeInfo) do
		self[k] = v
	end

	local ClubCSceneChangeNotify = {}
	ClubCSceneChangeNotify.nClubId = self.nClubId
	ClubCSceneChangeNotify.sChangeInfo = tData.sChangeInfo
	MsgApi.Broadcast("ClubCSceneChangeNotify",ClubCSceneChangeNotify)
end

--俱乐部后台配置更新
function ClubC:ClubConfigChange(arrChange)
	if #arrChange>0 then
		local tChangeInfo = {}
		for _,v in pairs(arrChange) do
			tChangeInfo[v.sKey] = v.Val
		end

		local ClubCSceneChangeNotify = {}
		ClubCSceneChangeNotify.nClubId = self.nClubId
		ClubCSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo)
		MsgApi.Broadcast("ClubCSceneChangeNotify",ClubCSceneChangeNotify)
	end
end
------------------从服消息  end----------------------------

-------------------游戏服消息 start---------------------------

--删除俱乐部牌桌
function ClubC:TableClose(nIndex,tTable)
	local tAutomatic = {}
	tAutomatic.sTableId= tTable.sTableId
	tAutomatic.sTableName= tTable.sTableName
	tAutomatic.sServerKey= tTable.sServerKey
	tAutomatic.sRequestkey= tTable.sRequestkey
	tAutomatic.nClubId= tTable.nClubId
	tAutomatic.nGameId= tTable.nGameId

	--广播到从服
	local ClubCTableCloseNotify = {}
	ClubCTableCloseNotify.nClubId = tTable.nClubId
	ClubCTableCloseNotify.sTableId = tTable.sTableId
	MsgApi.Broadcast("ClubCTableCloseNotify",ClubCTableCloseNotify)
	--删除本地数据
	table.remove(self.arrTable,nIndex)
	self.nTableIndex = self.nTableIndex + 1

	self:TableAutoMatic(tAutomatic)

	return
end

--游戏服开桌通知
function ClubC:_OnClubCGameOpenTableNotify(sReturnKey,tData)
	self:Print("_OnClubCGameOpenTableNotify 游戏服开桌通知 sTableId:%s sTableInfo:%s nServId:%d",tData.sTableId,tData.sTableInfo,tData.nServId)
	for _,tTable in pairs(self.arrTable) do
		if tTable.sTableId == tData.sTableId then
			self:Print("_OnClubCGameOpenTableNotify 牌桌已存在")
			return
		end
	end
	local isSuccee,tTableInfo = pcall(Cjson.decode,tData.sTableInfo)
	if not isSuccee then
		self:Print("_OnClubCGameOpenTableNotify decode sConfig fail")
		return
	end
	local tTable = {}
	for k,v in pairs(tTableInfo) do
		tTable[k] = v
	end
	local arrMustParams = { --必须要有的参数
		["nGameId"]="number", --游戏id
		["sTableName"]="string", --牌桌名字
		["nItemId"]="number", --所用金币的id
		["nLiveUserID"]="number", --房主id
		["nKeepTime"]="number", --持续时间
		["nCapacity"]="number", --最大人数
		["nGoldType"]="number",--使用的金币类型 1:金币 2:俱乐部币 3:积分
	}
	--检查必须要有的参数有没有缺
	for sKey, sType in pairs(arrMustParams) do
		if not tTable[sKey] then
			local sSendSMS = string.format("缺少必需参数%s,俱乐部中心服开桌失败",sKey)
			self:Print("_OnClubCGameOpenTableNotify %s",sSendSMS)
			MsgApi.SendToTGChat(sSendSMS)
			return
		elseif type(tTable[sKey]) ~= sType then
			local sSendSMS = string.format("参数%s数据类型错误,需要的数据类型:%s,目前的数据类型:%s,俱乐部中心服开桌失败",sKey,sType,type(tTable[sKey]))
			self:Print("_OnClubCGameOpenTableNotify %s",sSendSMS)
			MsgApi.SendToTGChat(sSendSMS)
			return
		end
	end
	tTable.sTableId = tData.sTableId
	tTable.nTableIndex = self.nTableIndex
	tTable.nClubId =  tData.nClubId
	tTable.nNowCnt = 0 --目前人数
	tTable.nOpentime = tTableInfo.nOpentime or os.time()
	tTable.nServerId = tonumber(string.match(tData.sTableId,"(%d+)#"))
	tTable.nStopTimeTemp = -1 --暂停状态的时间戳
	tTable.nSuspendStopTime = 0 --累计暂停时长
	tTable.isGameing = 0 --是否游戏中
	tTable.nSittedList = {}
    local tVal = PublicApi.Split(sReturnKey, ":")
    local sServerKey = tVal[1]
	tTable.sServerKey = sServerKey
	tTable.sRequestkey = tTableInfo.sRequestkey or ""

	if tTable.nTableStatus == 1 then
		tTable.nStopTimeTemp = tTable.nOpentime
	end
	if tTable.nServerId then
		self.tGameServer[tTable.nServerId] = Base.GetServerIdIdKey(tTable.nServerId) or ""
	end
	table.insert(self.arrTable,tTable)
	local sTableInfo = Cjson.encode(tTable)
	self:Print("_OnClubCGameOpenTableNotify 俱乐部中心服开桌成功 tTable:%s",sTableInfo)
	self.nTableIndex = self.nTableIndex + 1
	--广播到从服
	local ClubCTableOpenNotify = {}
	ClubCTableOpenNotify.nClubId = tData.nClubId
	ClubCTableOpenNotify.sTableId = tData.sTableId
	ClubCTableOpenNotify.sTableInfo = sTableInfo
	MsgApi.Broadcast("ClubCTableOpenNotify",ClubCTableOpenNotify)
	self:Print("RecordTableInfo  ClubCTableOpenNotify:%s",Cjson.encode(ServerInfo))
	self:Print("RecordTableInfo  ClubCTableOpenNotify:%d",tData.nServId)
	if ServerInfo.nServerId == tData.nServId then	--发送到db服
		self:RecordTableInfo(tTable, false)
	end

	self:_TableHandle(1, tTable)
end

--获取一个服中同名的牌桌数目
function ClubC:GetSameNameTable(nServerId, nGameId, sTableName)
	local nCnt = 0
	for _,tTable in pairs(self.arrTable) do
		if tTable.nServerId == nServerId and tTable.nGameId == nGameId and tTable.sTableName == sTableName then
			nCnt = nCnt + 1
		end
	end
	if nCnt > 0 then
		return false
	end
	return true
end

--俱乐部牌桌通知
--@params sServerKey:从服key,不传则通知所有从服
function ClubC:TableNotify(sServerKey)
	self:Print("__TableNotify self.arrTable:%d", #self.arrTable)
	-- 通知游戏服
	for _,tTable in pairs(self.arrTable) do
		local ClubCTableOpenNotify = {}
		ClubCTableOpenNotify.nClubId = tTable.nClubId
		ClubCTableOpenNotify.sTableId = tTable.sTableId
		ClubCTableOpenNotify.sTableInfo = Cjson.encode(tTable)
		self:Print("__TableNotify ClubCTableOpenNotify_%s",Cjson.encode(ClubCTableOpenNotify))
		if sServerKey then
			MsgApi.SendToSlaveServer(sServerKey,"ClubCTableOpenNotify",ClubCTableOpenNotify)
		else
			MsgApi.Broadcast("ClubCTableOpenNotify",ClubCTableOpenNotify)
		end
	end
end

--游戏服关桌通知
function ClubC:_OnClubCGameCloseTableNotify(sReturnKey,tData)
	self:Print("_OnClubCGameCloseTableNotify 游戏服关桌通知 sTableId:%s nServId:%d",tData.sTableId,tData.nServId)
	for nIndex,tTable in ipairs(self.arrTable) do
		if tTable.sTableId==tData.sTableId then
			local sTableName = B_Decode(tTable.sTableName)
			if ServerInfo.nServerId==tData.nServId  then
				self:RecordTableInfo(tTable,true)
			end
			self:TableClose(nIndex,tTable)
			self:Print("_OnClubCGameCloseTableNotify 俱乐部中心服关桌成功  sTableName: %s ",sTableName)
			return
		end
	end
	self:Print("_OnClubCGameCloseTableNotify 俱乐部中心服关桌失败，没找到牌桌")
end

-- 从列表中移除指定玩家
local function removeFromList(list, playerId)
    for i = #list, 0, -1 do
        if list[i] == playerId then
            table.remove(list, i)
            return true
        end
    end
    return false
end

--检查玩家是否在列表中
local function isInList(list, playerId)
    for i = 0, #list do
        if list[i] == playerId then
            return true
        end
    end
    return false
end

--游戏服牌桌信息改变通知
function ClubC:_OnClubCGameTableInfoNotify(sReturnKey,tData)
	self:Print("_OnClubCGameTableInfoNotify 牌桌信息改变_%s sTableInfo:%s nServId:%d",tData.sTableId,tData.sTableInfo,tData.nServId)
	local isSuccee,tTabletInfo = pcall(Cjson.decode,tData.sTableInfo)
	if not isSuccee then
		self:Print("_OnClubCGameTableInfoNotify decode sTableInfo fail")
		return
	end
	local isLeave = tTabletInfo["isLeave"]   --玩家离开标记
	for nIndex,tTable in pairs(self.arrTable) do
		if tTable.sTableId==tData.sTableId then
			local isNeedRecord = false --是否需要修改牌桌信息的记录 
			for k,v in pairs(tTabletInfo) do
				tTable[k] = v
				if k=="isStartGame" then
					-- self:Print("_OnClubCGameTableInfoNotify isStartGame: %s ",v and "true" or "false") 					
					self:_TableHandle(3,tTable)
					return
				end
				if k=="nTableStatus" then
					if v==0 and tTable.nStopTimeTemp~=-1 then
						--从暂停状态->正常状态
						tTable.nSuspendStopTime = tTable.nSuspendStopTime + (os.time() - tTable.nStopTimeTemp)
						tTable.nStopTimeTemp = -1
						tTabletInfo.nStopTimeTemp = tTable.nStopTimeTemp
						tTabletInfo.nSuspendStopTime = tTable.nSuspendStopTime
						self:Print("牌桌从暂停状态->正常状态")
					elseif v==1 and tTable.nStopTimeTemp==-1 then
						--从正常状态->暂停状态
						tTable.nStopTimeTemp = os.time()
						tTabletInfo.nStopTimeTemp = tTable.nStopTimeTemp
						self:Print("牌桌从正常状态->暂停状态")
					end
				elseif k=="sitId" then
					if isLeave then
						-- 如果玩家离开，从列表中移除
						if removeFromList(tTable.nSittedList, v) then
							self:Print("用户_%d 已离开，从入座过列表中移除", v)
						end
					else
						-- 如果玩家没有离开，且不在列表中，则添加
						if not isInList(tTable.nSittedList, v) then
							table.insert(tTable.nSittedList, v)
							self:Print("用户_%d 加入 入座过列表", v)
						end
					end
					tTabletInfo.nSittedList = tTable.nSittedList
				-- elseif k=="isGameing" then
				-- 	tTable.isGameing = 1
				-- 	self:Print("有人入座，房间游戏中")
				elseif k~="nTableStatus" and k~="nNowCnt" then
					isNeedRecord = true
				end
			end

			--广播到从服
			tTabletInfo.nSittedList = tTable.nSittedList      -- 人数列表每次都同步
			local ClubCTableInfoNotify = {}
			ClubCTableInfoNotify.nClubId = tData.nClubId
			ClubCTableInfoNotify.sTableId = tData.sTableId
			ClubCTableInfoNotify.sTableInfo = Cjson.encode(tTabletInfo)
			MsgApi.Broadcast("ClubCTableInfoNotify",ClubCTableInfoNotify)

			if isNeedRecord then
				if ServerInfo.nServerId==tData.nServId then
					self:RecordTableInfo(tTable,false)
				end
			end
			return
		end
	end

	self:Print("_OnClubCGameTableInfoNotify 俱乐部中心服修改牌桌信息失败，没找到牌桌")
end

--游戏服玩家结算通知
function ClubC:_OnClubCGameUserSettleNotify(sReturnKey,tData)
	self:Print("_OnClubCGameUserSettleNotify 游戏服玩家结算通知 sTableId:%s nUserId:%d nItemId:%d nWinlose:%f nDrawWater:%f nItemId:%d nGameId:%d nServId:%d nJuShu:%d nInsurance:%.2f sPaiJuId:%s",
	tData.sTableId,tData.nUserId,tData.nItemId,tData.nWinlose,tData.nDrawWater,tData.nItemId,tData.nGameId,tData.nServId or -1,tData.nJuShu or -1,tData.nInsurance or 0,tData.sPaiJuId or "")

	if not self:GetTable(tData.sTableId) then
		self:Print("_OnClubCGameUserSettleNotify 没找到牌桌")
		return
	end
	local nDrawWater =math.max((tData.nDrawWater or 0),0)
	local nInsurance =math.min(tData.nInsurance or 0,0)

	local nServiceCharge = PublicApi.Floor_2(nDrawWater * self.nClubTax/1000) --服务费
	local nISContribution =PublicApi.Floor_2(math.abs(nInsurance) * self.nInsuranceTax/1000)  --保险贡献
	local nContribution =nServiceCharge +nISContribution  --个人贡献(总)

	--私人俱乐部，计算收益
	if tData.nClubId>=Define.nMinClubId and (tData.nItemId and tData.nItemId>0) then
		local nSum =nil
		if ServerInfo.nServerId==tData.nServId then
			--增加俱乐部总资产
			local t = {nClubId=tData.nClubId,nChange=nServiceCharge,nSourceType=(10000 +tData.nGameId*100 +1),nMemberId=tData.nUserId,nHandleId=0,nItemId=tData.nItemId}
			if not PublicUserInfo.ChangeClubSumAsset(t) then
				self:Print("__OnClubCGameUserSettleNotify 增加服务费到俱乐部总资产失败")
			end
			--增加俱乐部总资产
			local t = {nClubId=tData.nClubId,nChange=nISContribution,nSourceType=(10000 +tData.nGameId*100 +3),nMemberId=tData.nUserId,nHandleId=0,nItemId=tData.nItemId}
			if not PublicUserInfo.ChangeClubSumAsset(t) then
				self:Print("__OnClubCGameUserSettleNotify 增加保险费到俱乐部总资产失败")
			end
			--增加俱乐部今日收益
			nSum =PublicRedis.IncrClubTodayIncome(self.nClubId,tData.nItemId,nContribution)
		end

		local sChangeInfo=nil
		if tData.nItemId==1 then	--1为金币,其它为俱乐部币
			self.nGoldTodayIncome =nSum or (self.nGoldTodayIncome + nContribution)
			self.nGoldIncome = self.nGoldIncome + nContribution
			sChangeInfo =Cjson.encode({nGoldIncome=self.nGoldIncome,nGoldTodayIncome = self.nGoldTodayIncome})
		else
			self.nTodayIncome =nSum or (self.nTodayIncome + nContribution)
			self.nIncome = self.nIncome + nContribution
			sChangeInfo =Cjson.encode({nIncome=self.nIncome,nTodayIncome = self.nTodayIncome})
		end
		--广播到从服
		MsgApi.Broadcast("ClubCSceneChangeNotify",{nClubId= self.nClubId,sChangeInfo= sChangeInfo})
		self:Print("__OnClubCGameUserSettleNotify ClubCSceneChangeNotify:%s",sChangeInfo)
	end

	local nWeekCountIncr =1
	if tData.sPaiJuId==nil or #tData.sPaiJuId<1 then
		nWeekCountIncr =0
	end

	local nWeekCount = PublicRedis.GetClubUserWeekCount(self.nClubId,tData.nUserId)
	if ServerInfo.nServerId==tData.nServId then
		--增加个人本周局数
		nWeekCount = PublicRedis.IncrClubUserWeekCount(self.nClubId,tData.nUserId,nWeekCountIncr)

		--发送到db服,个人记录
		local ClubWriteUserRecordReq = {}
		ClubWriteUserRecordReq.nClubId = tData.nClubId
		ClubWriteUserRecordReq.sTableId = tData.sTableId
		ClubWriteUserRecordReq.nUserId = tData.nUserId
		ClubWriteUserRecordReq.nItemId = tData.nItemId
		ClubWriteUserRecordReq.nWinlose = tData.nWinlose
		ClubWriteUserRecordReq.nServiceCharge = nServiceCharge
		ClubWriteUserRecordReq.sPaiJuId = tData.sPaiJuId
		ClubWriteUserRecordReq.nGameId = tData.nGameId
		ClubWriteUserRecordReq.nInsurance = tData.nInsurance or 0
		ClubWriteUserRecordReq.arrItemWinLose = {}
		ClubWriteUserRecordReq.nISContribution = nISContribution
		ClubWriteUserRecordReq.nContribution = nContribution
		ClubWriteUserRecordReq.nJuShu = tData.nJuShu or 0

		local tTable = self:GetTableInfo(tData.sTableId)
		local nKeepTime = 0
		local sTableName = "NoName"
		if not tTable then
			self:Print("_OnClubCGameUserSettleNotify not find table  sTableId: "..tData.sTableId)
		else
			nKeepTime = tTable.nKeepTime
			sTableName = tTable.sTableName
		end
		ClubWriteUserRecordReq.nKeepTime = nKeepTime
		ClubWriteUserRecordReq.sTableName = sTableName

		if tData.nClubId>=Define.nMinClubId then
			--俱乐部桌
			MsgApi.SendToDBServerByClubId(tData.nClubId,"ClubWriteUserRecordReq",ClubWriteUserRecordReq)
		else
			--大厅永久牌桌
			-- if nKeepTime == -1 then
			-- 	MsgApi.SendToDBServerByClubId(tData.nClubId,"ClubWriteUserRecord2Req",ClubWriteUserRecordReq)
			-- else
			-- 	--大厅普通桌
			-- 	MsgApi.SendToDBServerByClubId(tData.nClubId,"ClubWriteUserRecordReq",ClubWriteUserRecordReq)
			-- end
			MsgApi.SendToDBServerByClubId(tData.nClubId,"ClubWriteUserRecordReq",ClubWriteUserRecordReq)
		end
	else
		nWeekCount = nWeekCount + nWeekCountIncr
		self:Print("_OnClubCGameUserSettleNotify   不同服 nServId:  "..tData.nServId)
	end

	--通知从服玩家金币改变,每周次数改变，个人贡献改变
	local nNewGold = PublicUserInfo.Get_User_Gold(tData.nUserId,tData.nItemId)
	local tChangeInfo = {}
	if tData.nItemId==1 then
		tChangeInfo.nGold = nNewGold
		tChangeInfo.nGoldContribution = nContribution
	else
		tChangeInfo.nClubGold = nNewGold
		tChangeInfo.nContribution = nContribution
	end
	tChangeInfo.nWeekCount = nWeekCount
	tChangeInfo.nSettleNotify = 1 	-- 结算通知
	tChangeInfo.nHandProfit = tData.nHandProfit
	tChangeInfo.nWinlose = tData.nWinlose

	MsgApi.SendUserInfoChange(tData.nClubId,tData.nUserId,tChangeInfo)
end

function ClubC:TableAutoMaticWithStartGame(tTable, nClubId)
	local sTableId = tTable.sTableId or ""
	local sTableName = tTable.sTableName
	local nOpenTableCfgId = tTable.sRequestkey or ""

	local tCfg = PublicRedis._HandleClubTableCongfig(2, self.nGroupId, self.nClubId, tTable.nGameId, nOpenTableCfgId)
	if not tCfg then
		self:Print("TableAutoMaticWithStartGame  无配置 nCfgId: %s  ", nOpenTableCfgId)
		return
	end

	if tonumber(tCfg.nServerId) ~= ServerInfo.nServerId then
		self:Print("TableAutoMaticWithStartGame  非本服操作 【%d %d 】  nOpenTableCfgId: %s  ", tonumber(tCfg.nServerId),
			ServerInfo.nServerId,
			nOpenTableCfgId)
		return
	end

	if not tCfg.automatic then
		self:Print("TableAutoMaticWithStartGame  nCfgId_%s   automatic: %s  sTableId_%s ", nOpenTableCfgId,
			tCfg.automatic, sTableId)
		return
	end

	local tTableInfo = PublicRedis._HandleClubTableStartGame(4, self.nGroupId, tTable.nGameId, nOpenTableCfgId,
		sTableId)
	if not tTableInfo then
		self:Print("TableAutoMaticWithStartGame  nCfgId_%s  tTableInfo is nil  sTableName: %s  sTableId: %s  ",
			nOpenTableCfgId,
			B_Decode(sTableName), sTableId)
		return
	end

	if tTableInfo.hadAutomatic then
		self:Print("TableAutoMaticWithStartGame nCfgId_%s 已经自动开桌了 sTableName: %s sTableId: %s ", nOpenTableCfgId,
			B_Decode(sTableName), sTableId)
		return
	end

	if not tTableInfo.automatic then
		self:Print("TableAutoMaticWithStartGame nCfgId_%s  automatic is empty sTableName: %s sTableId: %s ",
			nOpenTableCfgId, B_Decode(sTableName), sTableId)
		return
	end

	-- 人数不达标也不开桌
	if tTable.nNowCnt < (tCfg.automaticCount or 0) then
		self:Print("TableAutoMaticWithStartGame  nCfgId_%s  人数不达标  sTableName: %s  sTableId: %s  ", nOpenTableCfgId,
			B_Decode(sTableName), sTableId)
		return
	end

	local sServerKey = MsgApi._GetGameServerKey(tTable.nGameId, nClubId, sTableName)
	if not sServerKey then
		self:Print("TableAutoMaticWithStartGame  sTableName: %s   自动续开失败 sServerKey is nil sTableId: %s  ",
			B_Decode(sTableName), sTableId)
		return
	end

	if not tCfg.isConfigSwitch then
		self:Print("TableAutoMaticWithStartGame  nOpenTableCfgId_%d   isConfigSwitch is false  ", tCfg.nOpenTableCfgId)
		return
	end

	local tSendData = tCfg.tSendData
	local tRoomConfig = tCfg.tRoomConfig
	tSendData.sConfig = Cjson.encode(tRoomConfig)
	local nIndex = PublicRedis._HandleClubOpenTableNameCount(2, self.nGroupId, tTable.nGameId, nOpenTableCfgId)
	local sName = string.format("%s-%d", tCfg.sTableName, nIndex)
	sTableName = B_Encode(sName)
	tSendData.sTableName = sTableName
	tSendData.nOpentime = os.time()

	PublicRedis._HandleClubTableStartGame(2, self.nGroupId, tTable.nGameId, nOpenTableCfgId,
		sTableId, { hadAutomatic = true })

	MsgApi.SendToGameServer(sServerKey, tSendData)
	self:_AddTableInfo(tTable.nGameId, nOpenTableCfgId, sName, tCfg.isAutomatic, tCfg.automatic, tCfg.automaticCount)
	self:Print("TableAutoMaticWithStartGame  %s 自动开桌 旧sTableId: %s   nOpenTableCfgId: %s  sServerKey: %s ",
		B_Decode(sTableName),
		sTableId, nOpenTableCfgId, sServerKey)
end

-- 牌桌自动续开
function ClubC:TableAutoMatic(tAutomatic)
	local sTableId = tAutomatic.sTableId or ""
	local sTableName = tAutomatic.sTableName or ""
	local nOpenTableCfgId = tAutomatic.sRequestkey or ""
	if PublicRedis._HandleClubTable_WebClose(sTableId,2,ServerInfo.nServerId) then  -- 后台开桌
		self:Print("_TableAutoMatic  sTableId: %s  后台关桌,无需自动续开 ",sTableId)
		-- 清除原先 牌桌数据
		PublicRedis._HandleClubTableStartGame(3,self.nGroupId,tAutomatic.nGameId,nOpenTableCfgId,sTableId)
		return
	end
	local tCfg =PublicRedis._HandleClubTableCongfig(2,self.nGroupId,self.nClubId,tAutomatic.nGameId,nOpenTableCfgId)
	if not tCfg then
		self:Print("_TableAutoMatic  无配置 nCfgId: %s  ",nOpenTableCfgId)
		return
	end
	if tonumber(tCfg.nServerId) ~= ServerInfo.nServerId then
		self:Print("_TableAutoMatic  非本服操作 【%d %d 】  nOpenTableCfgId: %s  ",tonumber(tCfg.nServerId),ServerInfo.nServerId,nOpenTableCfgId)	 
		return
	end
	-- 检测配置 是否自动续开桌 
	if not tCfg.isAutomatic then
		self:Print("_TableAutoMatic  nCfgId_%s   isAutomatic: %s  sTableId_%s ",nOpenTableCfgId,tCfg.isAutomatic and "true" or "false",sTableId)
		-- 清除原先 牌桌数据 	
		PublicRedis._HandleClubTableStartGame(3,self.nGroupId,tAutomatic.nGameId,nOpenTableCfgId,sTableId)  
		self:_CheckNoRunTable(nOpenTableCfgId,tAutomatic.nGameId)
		return
	end
	local tTableInfo = PublicRedis._HandleClubTableStartGame(4,self.nGroupId,tAutomatic.nGameId,nOpenTableCfgId,sTableId) 
	if not tTableInfo then
		self:Print("_TableAutoMatic  nCfgId_%s  tTableInfo is nil  sTableName: %s  sTableId: %s  ",nOpenTableCfgId,B_Decode(sTableName),sTableId)
		return
	end
	if tTableInfo.hadAutomatic or not tTableInfo.isAutomatic then -- 牌桌配置了自动开桌, 且已自动开桌
		self:Print("_TableAutoMatic nCfgId_%s  isAutomatic is false sTableName: %s sTableId: %s ", nOpenTableCfgId,
			B_Decode(sTableName), sTableId)
		-- 清除原先 牌桌数据
		PublicRedis._HandleClubTableStartGame(3,self.nGroupId,tAutomatic.nGameId,nOpenTableCfgId,sTableId)  
		return
	end
	local sServerKey = MsgApi._GetGameServerKey(tAutomatic.nGameId,tAutomatic.nClubId,sTableName)
	if not sServerKey then 
		self:Print("_TableAutoMatic  sTableName: %s   自动续开失败 sServerKey is nil sTableId: %s  ",B_Decode(sTableName),sTableId)	
		return
	end
	-- 清除原先 牌桌数据
	PublicRedis._HandleClubTableStartGame(3,self.nGroupId,tAutomatic.nGameId,nOpenTableCfgId,sTableId) 
	
	if not tCfg.isConfigSwitch then
		self:Print("_TableAutoMatic  nOpenTableCfgId_%d   isConfigSwitch is false  ",tCfg.nOpenTableCfgId)
		return
	end
	local tSendData = tCfg.tSendData
	local tRoomConfig =tCfg.tRoomConfig
	tSendData.sConfig = Cjson.encode(tRoomConfig)
	local nIndex = PublicRedis._HandleClubOpenTableNameCount(2,self.nGroupId,tAutomatic.nGameId,nOpenTableCfgId)
 	local sName = string.format("%s-%d",tCfg.sTableName,nIndex)
	sTableName = B_Encode(sName)
	tSendData.sTableName = sTableName
    tSendData.nOpentime = os.time()
	MsgApi.SendToGameServer(sServerKey,tSendData)
	self:_AddTableInfo(tAutomatic.nGameId,nOpenTableCfgId,sName,tCfg.isAutomatic) 
	self:Print("_TableAutoMatic  %s 自动续开 旧sTableId: %s   nOpenTableCfgId: %s  sServerKey: %s ",B_Decode(sTableName),sTableId,nOpenTableCfgId,sServerKey)
	return 
end

-- 补桌
function ClubC:TableReopening(nOpenTableCfgId,nGameId)
	local tCfg = PublicRedis._HandleClubTableCongfig(2,self.nGroupId,self.nClubId,nGameId,nOpenTableCfgId)
	if not tCfg then
		self:Print("_TableReopening  无配置 nOpenTableCfgId: %s  ",nOpenTableCfgId)
		return
	end
	if not tCfg.isConfigSwitch then
		self:Print("_TableReopening  nOpenTableCfgId_%d   isConfigSwitch is false  ",tCfg.nOpenTableCfgId)
		return
	end
	if tonumber(tCfg.nServerId) ~= ServerInfo.nServerId then
		self:Print("_TableReopening  非本服操作 【%d %d 】  nOpenTableCfgId: %s  ",tonumber(tCfg.nServerId),ServerInfo.nServerId,nOpenTableCfgId)
		return
	end
	if tCfg.nContinuedNum <= 0 then
		self:Print("_TableReopening   nContinuedNum: %d  nOpenTableCfgId: %s  ",tCfg.nContinuedNum,nOpenTableCfgId)
		return
	end
	local tSendData =tCfg.tSendData
	local nOpenCount = tCfg.nOpenCount
	local nContinuedNum = tCfg.nContinuedNum
	local tRoomConfig =tCfg.tRoomConfig
    local arrSuccessTableName={}
    local arrSuccess={}
	local arrTableIndex ={}
    for i = 1, nContinuedNum, 1 do
        local nIndex = PublicRedis._HandleClubOpenTableNameCount(2,self.nGroupId,tRoomConfig.nGameId,nOpenTableCfgId)
        table.insert(arrTableIndex,nIndex)
    end
    for _, nIndex in ipairs(arrTableIndex) do
        local sName = string.format("%s-%d",tCfg.sTableName,nIndex)
        local sTableName = B_Encode(sName)
		table.insert(arrSuccessTableName,sTableName)
		table.insert(arrSuccess,sName)
	end
	self:Print("_TableReopening  nGroupId: %d nClubId: %d nGameId: %d nOpenTableCfgId_%d 补桌牌桌名: %s "
	,self.nGroupId,tRoomConfig.nClubId,tRoomConfig.nGameId,nOpenTableCfgId,Cjson.encode(arrSuccess))

	tRoomConfig.isAutomatic = false
	tRoomConfig.automatic = false
	
    for k, sTableName in ipairs(arrSuccessTableName) do
        local sServerKey = MsgApi._GetGameServerKey(tRoomConfig.nGameId,self.nClubId,sTableName)
        if sServerKey then
			tSendData.sConfig = Cjson.encode(tRoomConfig)
            tSendData.sTableName = sTableName
			tSendData.nOpentime = os.time()
            MsgApi.SendToGameServer(sServerKey,tSendData)
			self:_AddTableInfo(tRoomConfig.nGameId, nOpenTableCfgId, B_Decode(sTableName), false, false, 0)
        end
    end
	self:Print("_TableReopening nCfgId_%d  nGameId_%d nOpenCount_%d / %d  nContinuedNum: %d  "
	,nOpenTableCfgId,nGameId,tCfg.nOpenCount,nOpenCount,nContinuedNum)

	return
end

-- 牌桌操作: nHandle： 1开桌、2关桌、3游戏状态
function ClubC:_TableHandle(nHandle,tTable)
	local sTableId = tTable.sTableId
	-- log tTable
	self:Print("_TableHandle nHandle:%d",nHandle)
	self:Print("_TableHandle tTable:%s",Cjson.encode(tTable))
	self:Print("_TableHandle tTable.sRequestkey:%s",tTable.sRequestkey)
	self:Print("_TableHandle tTable.nGameId:%d",tTable.nGameId)
	local nOpenTableCfgId =tTable.sRequestkey or ""
	local tCfg = PublicRedis._HandleClubTableCongfig(2,self.nGroupId,self.nClubId,tTable.nGameId,nOpenTableCfgId)
	-- if not tCfg then 		
	-- 	self:Print("_TableHandle  sTableId: %s   %s  无配置 nHandle: %d nOpenTableCfgId: %s",tTable.sTableId or "",B_Decode(tTable.sTableName or""),nHandle,nOpenTableCfgId)
	-- 	return 
	-- end  		
	-- if tonumber(tCfg.nServerId) ~= ServerInfo.nServerId then 
	-- 	self:Print("_TableHandle  非本服操作 【%d %d 】  nOpenTableCfgId: %s  ",tonumber(tCfg.nServerId),ServerInfo.nServerId,nOpenTableCfgId)	 
	-- 	return 
	-- end 
	self:Print("_TableHandle  sTableId: %s nGameId: %d sTableName: %s nHandle_%d automatic_%s",tTable.sTableId,tTable.nGameId,BaseSink.decode(tTable.sTableName),nHandle, tTable.automatic and "true" or "false") 
	if nHandle == 1 then
		local tTableInfo = {}
		tTableInfo.sTableId = sTableId
		tTableInfo.sTableName = BaseSink.decode(tTable.sTableName)
 		PublicRedis._HandleClubTableStartGame(1,self.nGroupId,tTable.nGameId,nOpenTableCfgId,sTableId,tTableInfo)
	elseif nHandle == 2 then
		PublicRedis._HandleClubTableStartGame(3,self.nGroupId,tTable.nGameId,nOpenTableCfgId,sTableId) 
		 
	elseif nHandle == 3 then
		local arrTableInfo = PublicRedis._HandleClubTableStartGame(2,self.nGroupId,tTable.nGameId,nOpenTableCfgId,sTableId,{isStartGame =tTable.isStartGame})
		if not tTable.isStartGame then
			return
		end
		self:TableAutoMaticWithStartGame(tTable, self.nClubId)
		if not arrTableInfo then
			return
		end
		local nStartCnt = 0
		local nCnt = 0
		for _,tTableInfo in pairs(arrTableInfo) do
			if tTableInfo.isStartGame then
				nStartCnt = nStartCnt + 1
			end
			nCnt = nCnt + 1
		end
		if nStartCnt == nCnt then  -- 全部牌桌开始了，补桌
			if tCfg.nContinuedNum == 0 then
				self:Print("_TableHandle  nContinuedNum_%d   nOpenTableCfgId: %s ",tCfg.nContinuedNum,nOpenTableCfgId) 
				return
			end
			self:Print("_TableHandle  需要补桌 nCnt: %d nStartCnt: %d  sRequestkey: %s ",nCnt,nStartCnt,nOpenTableCfgId) 
			self:TableReopening(nOpenTableCfgId,tTable.nGameId) 
		else
			self:Print("_TableHandle  nGameId: %d nCnt: %d nStartCnt: %d  sRequestkey: %s ",tTable.nGameId,nCnt,nStartCnt,nOpenTableCfgId) 
		end 
	end 
end 

-- 检查 是否要清除配置
function ClubC:_CheckNoRunTable(nOpenTableCfgId,nGameId)
	local tCfg =PublicRedis._HandleClubTableCongfig(2,self.nGroupId,self.nClubId,nGameId,nOpenTableCfgId)
	if not tCfg then
		self:Print("_CheckNoRunTable  无配置 nOpenTableCfgId: %s  ",nOpenTableCfgId)
		return
	end
	if tonumber(tCfg.nServerId) ~= ServerInfo.nServerId then
		self:Print("_CheckNoRunTable  非本服操作 【%d %d 】  nOpenTableCfgId: %s  ",tonumber(tCfg.nServerId),ServerInfo.nServerId,nOpenTableCfgId)	 
		return
	end
	local arrTableInfo = PublicRedis._HandleClubTableStartGame(5,self.nGroupId,nGameId,nOpenTableCfgId,nOpenTableCfgId)
	if not arrTableInfo or #arrTableInfo == 0 then
		self:Print("_CheckNoRunTable  已无桌子,是否清除配置  nOpenTableCfgId: %s  ",nOpenTableCfgId)
	else
		self:Print("_CheckNoRunTable  还有桌子  arrTableInfo: %s  ",Cjson.encode(arrTableInfo))
	end
end

-- 重启恢复 配置牌桌
function ClubC:_ReStartRecover(tCfg)
	if not tCfg then
		self:Print("_ReStartRecover  tCfg is nil ")
		return
	end
	if not tCfg.isConfigSwitch then
		self:Print("_ReStartRecover  nOpenTableCfgId_%d   isConfigSwitch is false  ",tCfg.nOpenTableCfgId)
		return
	end
	if tonumber(tCfg.nServerId) ~= ServerInfo.nServerId then
		self:Print("_ReStartRecover  非本服操作 【%d %d 】   ",tonumber(tCfg.nServerId),ServerInfo.nServerId)
		return
	end
	local tSendData = tCfg.tSendData
	local nOpenCount = tCfg.nOpenCount
	local tRoomConfig =tCfg.tRoomConfig
	local nOpentime = tonumber(tSendData.nOpentime) or 0
	local nKeepTime = tonumber(tRoomConfig.nKeepTime) or 0
	if nOpentime > 0 then
		local now = os.time()
		if now >= nOpentime + nKeepTime then         -- 超时检测
			PublicRedis._HandleClubTableCongfig(3,self.nGroupId,self.nClubId,tRoomConfig.nGameId,tCfg.nOpenTableCfgId)
			self:Print("_ReStartRecover  nGroupId:%d nClubId:%d nGameId:%d nOpenTableCfgId_%d 重启恢复牌桌 超时"
				,self.nGroupId,tRoomConfig.nClubId,tRoomConfig.nGameId,tCfg.nOpenTableCfgId)
			return
		end
	end
    local arrSuccessTableName={}
    local arrSuccess={}
	local arrTableIndex ={}
    for i = 1, nOpenCount, 1 do
        local nIndex = PublicRedis._HandleClubOpenTableNameCount(2,self.nGroupId,tRoomConfig.nGameId,tCfg.nOpenTableCfgId)
        table.insert(arrTableIndex,nIndex)
    end
    for _, nIndex in ipairs(arrTableIndex) do
        local sName = string.format("%s-%d",tCfg.sTableName,nIndex)
        local sTableName = B_Encode(sName)
		table.insert(arrSuccessTableName,sTableName)
		table.insert(arrSuccess,sName)
	end
	self:Print("_ReStartRecover  nGroupId: %d nClubId: %d nGameId: %d nOpenTableCfgId_%d 重启恢复牌桌: %s "
	,self.nGroupId,tRoomConfig.nClubId,tRoomConfig.nGameId,tCfg.nOpenTableCfgId,Cjson.encode(arrSuccess))

    for k, sTableName in ipairs(arrSuccessTableName) do
        local sServerKey = MsgApi._GetGameServerKey(tRoomConfig.nGameId,self.nClubId,sTableName)
        if sServerKey then
			tSendData.sConfig = Cjson.encode(tRoomConfig)
            tSendData.sTableName = sTableName
			tSendData.nOpentime = os.time()
            MsgApi.SendToGameServer(sServerKey,tSendData)

			self:_AddTableInfo(tRoomConfig.nGameId, tCfg.nOpenTableCfgId, B_Decode(sTableName), tCfg.isAutomatic,
				tCfg.automatic, tCfg.automaticCount)
		end
	end
end

-- 添加牌桌配置
function ClubC:_AddTableInfo(nGameId, nOpenTableCfgId, sTableId, isAutomatic, automatic, automaticCount)
	local tTableInfo = {}
	tTableInfo.isAutomatic = isAutomatic
	tTableInfo.isStartGame = false
	tTableInfo.sTableName = sTableId -- 牌桌还没创建,
	tTableInfo.sTableId = ""
	tTableInfo.hadAutomatic = false -- 是否已经自动创建过了
	tTableInfo.automatic = automatic
	tTableInfo.automaticCount = automaticCount
	PublicRedis._HandleClubTableStartGame(1,self.nGroupId,nGameId,nOpenTableCfgId,sTableId,tTableInfo)
end

------------------从服消息  end----------------------------

-------------------数据获取 start---------------------------
--获取俱乐部场景
function ClubC:GetScence()
	local tScence = {}
	tScence.nClubId = self.nClubId --俱乐部id
	tScence.sClubName = self.sClubName --俱乐部名称
	tScence.nClubGold = self.nClubGold --俱乐部资产(俱乐部币)
	tScence.nIncome = self.nIncome --总收益(俱乐部币)
	tScence.nTodayIncome = self.nTodayIncome --今日收益(俱乐部币)
	tScence.nMaxUserCnt = self.nMaxUserCnt --俱乐部最大人数
	tScence.nClubTax = self.nClubTax --俱乐部桌服务费分成
	tScence.nInsuranceTax = self.nInsuranceTax --俱乐部保险分成
	tScence.nMaster = self.nMaster --主席id
	tScence.nGroupId = self.nGroupId --分组id
	tScence.nCanSearch = self.nCanSearch--是否允许搜索 0:允许 1:不允许
	tScence.nCanApply = self.nCanApply--是否允许申请加入 0:允许 1:不允许
	tScence.sPassWord = self.sPassWord--库存密码
	tScence.nUserCnt = self.nUserCnt--成员数目
	tScence.nApplyJionCnt=self.nApplyJionCnt --加入俱乐部申请数目
	tScence.nApplyAddGoldCnt=self.nApplyAddGoldCnt --增加俱乐部币申请数目
	tScence.nApplyCutGoldCnt=self.nApplyCutGoldCnt --增加俱乐部币申请数目
	tScence.IsNeedAndroid=self.IsNeedAndroid --是否需要机器人
	tScence.IsUseGold=self.IsUseGold --俱乐部是否使用金币
	tScence.IsUserClubGold=self.IsUserClubGold --俱乐部是否使用俱乐部币
	tScence.nGold=self.nGold --俱乐部资产(金币)
	tScence.nGoldIncome=self.nGoldIncome --总收益(金币)
	tScence.nGoldTodayIncome=self.nGoldTodayIncome --今日收益(金币)

	tScence.sShopAcc = self.tMasterInfo.sShopAcc --主席公共信息
	tScence.sFaceId = self.tMasterInfo.sFaceId --主席公共信息
	tScence.sName = self.tMasterInfo.sName --主席公共信息
	tScence.nSex = self.tMasterInfo.nSex --主席公共信息
	--self:Print("GetScence %s",Cjson.encode(tScence))

	return tScence
end

--获取俱乐部牌桌
function ClubC:GetTable(sTableId)
	for nIndex,tTable in pairs(self.arrTable) do
		if tTable.sTableId==sTableId then
			return tTable
		end
	end
end

--获取牌桌记录需要的信息
function ClubC:GetRecordInfo(tTable)
	local tNotRecordKey = { --不需要记录的字段
		["nStopTimeTemp"] = true,
		["nServerId"] = true,
		["nTableIndex"] = true,
		["nSuspendStopTime"] = true,
		--["sTableId"] = true,
		["nNowCnt"] = true,
		--["nClubId"] = true,
		-- ["nLiveUserID"] = true,
		-- ["nGameId"] = true,
		-- ["nTableStatus"] = true,
		["isGameing"] = true,
		["nSittedList"] = true,
	}
	local tInfo = {}
	for k,v in pairs(tTable) do
		if not tNotRecordKey[k] then
			tInfo[k] = v
		end
	end
	return tInfo
end

------------------数据获取  end----------------------------

-------------------消息发送 start---------------------------
function ClubC:RecordTableInfo(tTable,isEnd)
	self:Print("RecordTableInfo  tTable: %s  isEnd: %s",Cjson.encode(tTable),isEnd and "true" or "false")
	local sTableInfo = Cjson.encode(self:GetRecordInfo(tTable))

	if isEnd then
		--删除redis数据
		PublicRedis.DelClubTableInfo(tTable.nClubId,tTable.sTableId)
	else
		--保存俱乐部牌桌信息
		PublicRedis.SetClubTableInfo(tTable.nClubId,tTable.sTableId,sTableInfo)
	end

	--发送到db服
	local ClubWriteTableRecordReq = {}
	ClubWriteTableRecordReq.nClubId = tTable.nClubId
	ClubWriteTableRecordReq.sTableId = tTable.sTableId
	ClubWriteTableRecordReq.nKeepSec = tTable.nKeepTime
	ClubWriteTableRecordReq.sTableInfo = sTableInfo
	ClubWriteTableRecordReq.isEnd = isEnd
	ClubWriteTableRecordReq.nLiveUserID = tTable.nLiveUserID
	ClubWriteTableRecordReq.nGameId = tTable.nGameId
	ClubWriteTableRecordReq.nGroupId = self.nGroupId
	MsgApi.SendToDBServerByClubId(tTable.nClubId,"ClubWriteTableRecordReq",ClubWriteTableRecordReq)
end
-------------------消息发送  end----------------------------

function ClubC:Print(str,...)
	Logger:info(string.format("Id=>"..self.nClubId.."=>"..str,...))
end

--俱乐部关闭
function ClubC:Close()
	self.Timer:KillAllTimer()
	self.Timer = nil

	PublicRedis.DelClubCenterSrvKey(self.nClubId,ServerInfo.nServerId)

	--通知从服关闭俱乐部
	local ClubCCloseNotify = {}
	ClubCCloseNotify.nClubId = self.nClubId
	MsgApi.Broadcast("ClubCCloseNotify",ClubCCloseNotify)

	self = nil
end




return ClubC
