local ClubS = {}

function ClubS:New()
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
	t.nClubTax = 0 --俱乐部桌服务费分成
	t.nInsuranceTax = 0 --俱乐部保险分成
	t.nGroupId = 0 --分组id
	t.nMaster = 0 --主席id
	t.sCreateTime = "1970-01-01 08:00:00" --俱乐部创建时间
	t.nUserCnt = 0 --成员数目
	t.nCanSearch = 0 --是否允许搜索 0:允许 1:不允许
	t.nCanApply = 0 --是否允许申请加入 0:允许 1:不允许
	t.sPassWord = "" --库存密码
	t.nApplyJionCnt=0; --加入俱乐部申请数目
	t.nApplyAddGoldCnt=0; --增加俱乐部币申请数目
	t.nApplyCutGoldCnt=0; --增加俱乐部币申请数目
	t.IsNeedAndroid = false --牌桌是否加载机器人
	t.IsUseGold = true --俱乐部是否使用金币
	t.IsUserClubGold = true --俱乐部是否使用俱乐部币
	t.nGold = 0 --俱乐部资产(金币)
	t.nGoldIncome = 0 --总收益(金币)
	t.nGoldTodayIncome = 0 --今日收益(金币)

	--主席公共信息
	t.tMasterInfo = {}

	t.arrUser = {} --登录的俱乐部玩家

	t.arrTable = {} --俱乐部牌桌列表 
	return t
end

--初始化场景数据
function ClubS:InitScene(tData)
	self.sClubName = tData.sClubName or ""
	self.nClubGold = tData.nClubGold or 0
	self.nIncome = tData.nIncome or 0
	self.ServIdToKey = tData.ServIdToKey or {}
	self.nMaster = tData.nMaster or 0
	self.sCreateTime = tData.sCreateTime or "1970-01-01 08:00:00"
	self.nUserCnt = tData.nUserCnt or 0
	self.nTodayIncome = tData.nTodayIncome or 0
	self.nCanSearch = tData.nCanSearch or 0
	self.nCanApply = tData.nCanApply or 0
	self.sPassWord = tData.sPassWord or ""
	self.nApplyJionCnt=tData.nApplyJionCnt or 0
	self.nApplyAddGoldCnt=tData.nApplyAddGoldCnt or 0
	self.nApplyCutGoldCnt=tData.nApplyCutGoldCnt or 0
	self.nGold=tData.nGold or 0
	self.nGoldIncome=tData.nGoldIncome or 0
	self.nGoldTodayIncome = tData.nGoldTodayIncome or 0

	self.nMaxUserCnt = tData.nMaxUserCnt or  Define.nMaxUserCnt --俱乐部最大人数
	self.nClubTax = tData.nClubTax or 0 --俱乐部桌服务费分成
	self.nInsuranceTax = tData.nInsuranceTax or 0 --俱乐部保险分成
	self.IsNeedAndroid = tData.IsNeedAndroid or false --牌桌是否加载机器人
	--俱乐部是否使用金币
	if tData.IsUseGold~=nil then
		self.IsUseGold = tData.IsUseGold
	end
	--俱乐部是否使用俱乐部币
	if tData.IsUserClubGold~=nil then
		self.IsUserClubGold = tData.IsUserClubGold
	end

	local tMasterInfo = {}
	tMasterInfo.nClubId=self.nClubId
	tMasterInfo.nMaster=self.nMaster
	tMasterInfo.sFaceId=tData.sFaceId or ""
	tMasterInfo.sName=tData.sName or ""
	tMasterInfo.nSex=tData.nSex or 0
	tMasterInfo.sShopAcc=tData.sShopAcc or ""
	
	self.tMasterInfo = tMasterInfo
end

------------------------------中心服通知 start--------------------------
--中心服消息处理
function ClubS:OnCenterMsgHandle(strReq,tData)
	if strReq=="ClubCSceneChangeNotify" then --俱乐部场景信息改变通知
		self:_OnClubCSceneChangeNotify(tData)
		return
	end

	if strReq=="ClubCUserInfoChangeNotify" then --俱乐部玩家信息改变通知
		self:_OnClubCUserInfoChangeNotify(tData)
		return
	end

	if strReq=="ClubCTableOpenNotify" then --俱乐部桌开桌通知
		self:_OnClubCTableOpenNotify(tData)
		return
	end

	if strReq=="ClubCTableCloseNotify" then --俱乐部桌关桌通知
		self:_OnClubCTableCloseNotify(tData)
		return
	end

	if strReq=="ClubCTableInfoNotify" then --俱乐部桌信息改变通知
		self:_OnClubCTableInfoNotify(tData)
		return
	end

	self:PrintError("_OnCenterMsgHandle proto_%s 没有对应的处理函数",strReq)
end

--俱乐部场景信息改变通知
function ClubS:_OnClubCSceneChangeNotify(tData)
	self:Print("__OnClubCSceneChangeNotify 俱乐部场景信息改变通知 sChangeInfo:%s",tData.sChangeInfo)

	local isSuccee1,tChangeInfo = pcall(Cjson.decode,tData.sChangeInfo)
	if not isSuccee1 then
		self:Print("__OnClubCSceneChangeNotify decode sChangeInfo fail")
		if type(tChangeInfo) == "string" then 
			Logger:error(tChangeInfo)
		else 
			Base.LogT(tChangeInfo) 
		end
		return
	end

	--不通知前端的字段
	local tNotSendKeys = {
		["IsNeedAndroid"] = true,
	}
	
	local tChangeInfo_Normal = {}
	local tChangeInfo_MemberPower = {}
	local tChangeInfo_ClubGoldPower = {}
	local tChangeInfo_AllPower = {}
	for k,v in pairs(tChangeInfo) do
		self[k] = v
		if not tNotSendKeys[k] then
			tChangeInfo_AllPower[k] = v
			if k=="nApplyJionCnt" then
				tChangeInfo_MemberPower[k] = v
			elseif k=="nApplyAddGoldCnt" or k=="nApplyCutGoldCnt" then
				tChangeInfo_ClubGoldPower[k] = v
			else
				tChangeInfo_Normal[k] = v
			end
		end
	end

	local arrClientID_Normal = {} --普通成员
	local arrClientID_MemberPower = {} --只有成员权限的管理员
	local arrClientID_ClubGoldPower = {} --只有俱乐部币权限的管理员
	local arrClientID_AllPower = {} --有成员权限和俱乐部币权限的管理员
	for k,v in pairs(self.arrUser) do
		local sClientID = UserManager.GetUserClientID(v.nUserId)
		if sClientID then 
			if v.nIdentify==Define.nAdmin then
				local HasPower_Member = self:HasPower(v.nUserId,Define.tPower.Member)
				local HasPower_ClubGold = self:HasPower(v.nUserId,Define.tPower.ClubGold)
				if HasPower_Member and HasPower_ClubGold then
					--有成员权限和俱乐部币权限的管理员
					table.insert(arrClientID_AllPower,sClientID)
				elseif HasPower_Member then
					--只有成员权限的管理员
					table.insert(arrClientID_MemberPower,sClientID)
				elseif HasPower_ClubGold then
					--只有俱乐部币权限的管理员
					table.insert(arrClientID_ClubGoldPower,sClientID)
				else
					--没有成员权限和俱乐部币权限的管理员
					table.insert(arrClientID_Normal,sClientID)
				end
			elseif v.nIdentify==Define.nMaster then
				table.insert(arrClientID_AllPower,sClientID)
			else
				table.insert(arrClientID_Normal,sClientID)
			end
		end
	end

	if next(tChangeInfo_Normal) and #arrClientID_Normal>0 then
		local ClubSSceneChangeNotify = {}
		ClubSSceneChangeNotify.nClubId = self.nClubId
		ClubSSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo_Normal)
		self:BroadcastToSomeUser(arrClientID_Normal,"ClubSSceneChangeNotify",ClubSSceneChangeNotify)
	end

	if next(tChangeInfo_MemberPower) and #arrClientID_MemberPower>0 then
		local ClubSSceneChangeNotify = {}
		ClubSSceneChangeNotify.nClubId = self.nClubId
		ClubSSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo_MemberPower)
		self:BroadcastToSomeUser(arrClientID_MemberPower,"ClubSSceneChangeNotify",ClubSSceneChangeNotify)
	end

	if next(tChangeInfo_ClubGoldPower) and #arrClientID_ClubGoldPower>0 then
		local ClubSSceneChangeNotify = {}
		ClubSSceneChangeNotify.nClubId = self.nClubId
		ClubSSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo_ClubGoldPower)
		self:BroadcastToSomeUser(arrClientID_ClubGoldPower,"ClubSSceneChangeNotify",ClubSSceneChangeNotify)
	end

	if #arrClientID_AllPower>0 then
		local ClubSSceneChangeNotify = {}
		ClubSSceneChangeNotify.nClubId = self.nClubId
		ClubSSceneChangeNotify.sChangeInfo = Cjson.encode(tChangeInfo_AllPower)
		self:BroadcastToSomeUser(arrClientID_AllPower,"ClubSSceneChangeNotify",ClubSSceneChangeNotify)
	end
end

--俱乐部玩家信息改变通知
function ClubS:_OnClubCUserInfoChangeNotify(tData)
	local nUserId = tData.nUserId
	local tUser = self:GetUserByUserId(nUserId)
	if not tUser then
		self:Print("_OnClubCUserInfoChangeNotify no find user_%d",nUserId)
		return
	end

	self:Print("_OnClubCUserInfoChangeNotify 俱乐部玩家信息改变通知 nUserId:%d, sChangeInfo:%s",nUserId,tData.sChangeInfo)

	local isSuccee1,tChangeInfo = pcall(Cjson.decode,tData.sChangeInfo)
	if not isSuccee1 then
		self:Print("_OnClubCUserInfoChangeNotify decode sChangeInfo fail")
		if type(tChangeInfo) == "string" then
			Logger:error(tChangeInfo)
		else 
			Base.LogT(tChangeInfo)
		end
		return
	end
	
	local tUserChangeInfo = {}
	for k,v in pairs(tChangeInfo) do
		if k=="sPower" then
			--权限特殊处理
			local isSuccee,arrPower = pcall(Cjson.decode,v)
			if isSuccee then
				tUser.arrPower = {}
				for _,t in pairs(arrPower) do
					table.insert(tUser.arrPower,{nPowerType=t.nPowerType,isOpen=t.isOpen})
				end
			else 
				if type(arrPower) == "string" then 
					Logger:error(arrPower)
				else 
					Base.LogT(arrPower) 
				end
			end
			tUserChangeInfo[k]=v
		elseif k=="nContribution" then
			tUser.nContribution = tUser.nContribution + v
			tUserChangeInfo["nContribution"]=tUser.nContribution
		elseif k=="nGoldContribution" then
			tUser.nGoldContribution = tUser.nGoldContribution + v
			tUserChangeInfo["nGoldContribution"]=tUser.nGoldContribution
		elseif k=="nSettleNotify" then
			self:_UserSettleHandle(nUserId, tChangeInfo)
		else
			tUser[k] = v
			tUserChangeInfo[k]=v
		end
		if k=="nGold" then
			UserManager.RefleshUserGold(nUserId,v)
		end
	end

	local ClubSUserInfoChangeNotify = {}
	ClubSUserInfoChangeNotify.nClubId = self.nClubId
	ClubSUserInfoChangeNotify.nUserId = nUserId
	ClubSUserInfoChangeNotify.sChangeInfo = Cjson.encode(tUserChangeInfo)

	-- self:Print("__OnClubCUserInfoChangeNotify 俱乐部玩家信息改变通知 nUserId_%d  %s",nUserId,Cjson.encode(ClubSUserInfoChangeNotify))
	self:SendToUser(nUserId,"ClubSUserInfoChangeNotify",ClubSUserInfoChangeNotify)
end

--俱乐部桌开桌通知
function ClubS:_OnClubCTableOpenNotify(tData)
	self:Print("__OnClubCTableOpenNotify 俱乐部桌开桌通知 sTableId:%s sTableInfo:%s",tData.sTableId,tData.sTableInfo)
	for _,tTable in pairs(self.arrTable) do
		if tTable.sTableId == tData.sTableId then
			self:Print("__OnClubCTableOpenNotify 牌桌已存在")
			return
		end
	end
	local isSuccee,tTable = pcall(Cjson.decode,tData.sTableInfo)
	if not isSuccee then
		self:Print("__OnClubCTableOpenNotify decode sTableInfo fail")
		return
	end
	if not tTable.nClubId then
		self:Print("__OnClubCTableOpenNotify 不是俱乐部桌")
		return
	end
	table.insert(self.arrTable, tTable)

	local tProtoTableInfo = self:GetProtoTableInfo(tTable)

	local tMsgData = {nClubId = tTable.nClubId, nUserId = tTable.nLiveUserID, MsgType = Define.MsgType.OpenTable}
	if MsgOnTime.HasWaitingMsg(tMsgData) then
		self:Print("玩家等待开桌结果返回 nUserId_%d", tTable.nLiveUserID)
		--删除队列消息
		local nUserId, nItemId, nCount = MsgOnTime.DelWaitingMsg(tMsgData)
		local sClientID = UserManager.GetUserClientID(nUserId)
		if sClientID and sClientID ~= "" then
			MsgApi.SendToClient(sClientID, "ClubSOpenTableResp", {nRlt = PubErrCode.OpenTable.Success})
			self:Print("玩家开桌成功 nUserId_%d", nUserId)
			if nItemId and nCount then
				self:Print("玩家开桌消耗 nItemId_%d nCount_%.2f", nItemId, nCount)
				local isSuccee, sErr, nGoldAfterChange = PublicUserInfo.UnLockAndMinus(nUserId, PublicApi.Floor_2(nCount), Define.SourceType.OpenTable, 1, nItemId)
				if isSuccee then
					local tChangeInfo = {}
					if nItemId == 1 then
						tChangeInfo.nGold = nGoldAfterChange
						--通知用户金币改变了
						PublicUserInfo.Send_UserGold(nUserId, nGoldAfterChange, nItemId, -nCount)
						UserManager.RefleshUserGold(nUserId, nGoldAfterChange)
					elseif nItemId == tTable.nClubId then
						tChangeInfo.nClubGold = nGoldAfterChange
					end
					MsgApi.SendUserInfoChange(tTable.nClubId, nUserId, tChangeInfo)
				else
					self:Print("玩家开桌扣费失败 %s", sErr or "")
				end
			end
			self:Print("__OnClubCTableOpenNotify 玩家开桌成功 nUserId_%d", nUserId)
		end
	end

	local nClubId = tData.nClubId
	if nClubId < Define.nMinClubId then
		-- nClubId = 0 --大厅
	end

	self:Print("__OnClubCTableOpenNotify nClubId nClubId_%d", nClubId)

	--通知所有俱乐部玩家
	local ClubSOpenTableNotify = {}
	ClubSOpenTableNotify.nClubId = nClubId
	ClubSOpenTableNotify.sTableId = tData.sTableId
	ClubSOpenTableNotify.sTableInfo = Cjson.encode(tProtoTableInfo)

	local arrClientID = {}
	self:SetUserGetTableId(tMsgData.nUserId, tData.sTableId)
	for _,tUser in pairs(self.arrUser) do
		UserManager.GetUserClientID(tUser.nUserId)
		local sClientID = UserManager.GetUserClientID(tUser.nUserId)
		if sClientID and sClientID ~= "" then
			table.insert(arrClientID, sClientID)
		end
	end
	self:BroadcastToSomeUser(arrClientID, "ClubSOpenTableNotify", ClubSOpenTableNotify)
end

--俱乐部桌关桌通知
function ClubS:_OnClubCTableCloseNotify(tData)
	self:Print("__OnClubCTableCloseNotify 俱乐部桌关桌通知 sTableId:%s", tData.sTableId)

	for nIndex,tTable in ipairs(self.arrTable) do
		if tTable.sTableId==tData.sTableId then

			-- local tMsgData = {nClubId=tTable.nClubId,nUserId=tTable.nLiveUserID,MsgType=Define.MsgType.CloseTable,sTableId=tData.sTableId}
			-- if MsgOnTime.HasWaitingMsg(tMsgData) then
			-- 	--删除队列消息
			-- 	local nUserId = MsgOnTime.DelWaitingMsg(tMsgData) or 0
			-- 	local sClientID = UserManager.GetUserClientID(nUserId)
			-- 	if sClientID and sClientID~="" then
			-- 		MsgApi.SendToClient(sClientID,"ClubSCloseTableResp",{nRlt=PubErrCode.CloseTable.Success})
			-- 		self:Print("玩家关桌成功 nUserId_%d",nUserId)
			-- 	end
			-- end

			local nClubId = tData.nClubId
			if nClubId<Define.nMinClubId then
				nClubId = 0 --大厅
			end

			local ClubSCloseTableNotify = {}
			ClubSCloseTableNotify.nClubId = nClubId
			ClubSCloseTableNotify.sTableId = tData.sTableId
			local arrClientID = self:GetAndDelUserClientIDOfTable(tData.sTableId)
			self:BroadcastToSomeUser(arrClientID,"ClubSCloseTableNotify",ClubSCloseTableNotify)

			table.remove(self.arrTable,nIndex)
			-- self:Print("_OnClubCGameCloseTableNotify 俱乐部关桌成功")
			return
		end
	end

	self:Print("__OnClubCTableCloseNotify 俱乐部关桌失败，没找到牌桌")
end

--俱乐部桌信息改变通知
function ClubS:_OnClubCTableInfoNotify(tData)
	self:Print("__OnClubCTableInfoNotify 俱乐部桌信息改变通知 sTableId:%s sTableInfo:%s",tData.sTableId,tData.sTableInfo)

	local isSuccee,tTabletInfo = pcall(Cjson.decode,tData.sTableInfo)
	if not isSuccee then
		self:Print("__OnClubCTableInfoNotify decode sTableInfo fail")
		return
	end

	for nIndex,tTable in pairs(self.arrTable) do
		if tTable.sTableId==tData.sTableId then
			for k,v in pairs(tTabletInfo) do
				tTable[k] = v
			end

			local nClubId = tData.nClubId
			if nClubId<Define.nMinClubId then
				nClubId = 0 --大厅
			end

			local ClubSTableInfoNotify = {}
			ClubSTableInfoNotify.nClubId = nClubId
			ClubSTableInfoNotify.sTableId = tData.sTableId
			ClubSTableInfoNotify.sTableInfo = tData.sTableInfo
			local arrClientID = self:GetUserClientIDOfTable(tData.sTableId)
			self:BroadcastToSomeUser(arrClientID,"ClubSTableInfoNotify",ClubSTableInfoNotify)
			return
		end
	end

	self:Print("__OnClubCTableInfoNotify 俱乐部修改牌桌信息失败，没找到牌桌")
end
------------------------------中心服通知 end--------------------------

------------------------------前端请求 start--------------------------
--前端请求
function ClubS:OnReqHandle(nUserId,strReq,tData)
	
end
------------------------------前端请求 end--------------------------

------------------------------进入退出 start--------------------------
--玩家进入
function ClubS:Enter(tUserInfo)
	local tUser = {}
	tUser.nUserId = tUserInfo.nUserId
	tUser.sFaceId = tUserInfo.sFaceId or "1"
	tUser.sName = tUserInfo.sName or "Tm9OYW1l"
	tUser.nSex = tUserInfo.nSex or 0
	tUser.nGold = tUserInfo.nGold or 0
	tUser.nClubGold = tUserInfo.nClubGold or 0
	tUser.nIdentify = tUserInfo.nIdentify or Define.nMember
	tUser.nContribution = tUserInfo.nContribution or 0
	tUser.nGoldContribution = tUserInfo.nGoldContribution or 0
	tUser.arrPower = tUserInfo.arrPower or {}
	tUser.nGroupId = tUserInfo.nGroupId or 0
	tUser.sShopAcc = tUserInfo.sShopAcc
	tUser.tAlreadyGetTable = {} --玩家已获取的牌桌id
	tUser.ifBinging = tUserInfo.ifBinging
	tUser.nCreateTime = tUserInfo.nCreateTime
	-- if self.nClubId<Define.nMinClubId then
	-- 	--大厅,判断是否给玩家开桌权限
	-- 	local tConfig = PubClubApi.GetClubWebConfig(self.nGroupId)
	-- 	if tConfig.IsCanCreateHallTable==true then
	-- 		self:Print("_Enter 大厅玩家开桌权限 true")
	-- 		table.insert(tUser.arrPower,{nPowerType=Define.tPower.OpenTable,isOpen=true})
	-- 	else
	-- 		table.insert(tUser.arrPower,{nPowerType=Define.tPower.OpenTable,isOpen=false})
	-- 	end
	-- 	--大厅成员默认是管理
	-- 	tUser.nIdentify = Define.nAdmin
	-- end
	--玩家本周局数
	tUser.nWeekCount = PublicRedis.GetClubUserWeekCount(self.nClubId,tUserInfo.nUserId)
	local sUserId = tostring(math.floor(tUserInfo.nUserId))
	self.arrUser[sUserId] = tUser
	UserManager.UserEnterClub(tUser.nUserId,self.nClubId)
	--保存玩家进入的俱乐部
	PublicUserInfo.SetUserLastEnterClub(tUser.nUserId,self.nClubId)
	--修改redis上玩家的权限
    PublicRedis.SetClubUserInfo(self.nClubId,{{nUserId=tUserInfo.nUserId,sPower=tUser.arrPower}})
	self:Print("_Enter 玩家进入俱乐部  User_%d arrPower: %s  ",tUser.nUserId,Cjson.encode(tUser.arrPower))
	return tUser
end

--玩家退出
function ClubS:Leave(nUserId)
	local sUserId = tostring(math.floor(nUserId))
	if not self.arrUser[sUserId] then
		self:Print("_Leave 俱乐部中没有该玩家的信息 user_%d",nUserId)
		return false
	end
	self.arrUser[sUserId] = nil
	UserManager.UserLeaveClub(nUserId,self.nClubId)
	self:Print("_Leave 玩家离开俱乐部 User_%d",nUserId)
	return true
end
------------------------------进入退出 end--------------------------

------------------------------俱乐部数据相关 start--------------------------
--根据玩家id获取是否为绑定用户
function ClubS:GetBingingByUserId(nUserId)
	local sUserId = tostring(math.floor(nUserId))
	if not self.arrUser[sUserId] then
		self:Print("俱乐部中没有该玩家的信息 user_%d",nUserId)
		return 0
	end
	local User = self.arrUser[sUserId]
	return User.ifBinging
end

--根据玩家id获取对应场景
function ClubS:GetScenceByUserId(nUserId)
	local tScence = {}
	tScence.nClubId = self.nClubId
	tScence.sClubName = self.sClubName
	tScence.nClubGold = self.nClubGold
	tScence.nIncome = self.nIncome
	tScence.nTodayIncome = self.nTodayIncome
	tScence.nMaxUserCnt = self.nMaxUserCnt
	tScence.nClubTax = self.nClubTax
	tScence.nInsuranceTax = self.nInsuranceTax
	tScence.tMyself = self:GetClubSUser(nUserId)
	tScence.nCanSearch = self.nCanSearch
	tScence.nCanApply = self.nCanApply
	tScence.IsUseGold = self.IsUseGold
	tScence.IsUserClubGold = self.IsUserClubGold
	tScence.nGold = self.nGold
	tScence.nGoldIncome = self.nGoldIncome
	tScence.nGoldTodayIncome = self.nGoldTodayIncome

	if self.nClubId<Define.nMinClubId then
		tScence.nClubId = 0
	end
	if self:HasPower(nUserId, Define.tPower.Member) then
		tScence.nApplyJionCnt = self.nApplyJionCnt
	end
	if self:HasPower(nUserId, Define.tPower.ClubGold) then
		tScence.nApplyAddGoldCnt = self.nApplyAddGoldCnt
		tScence.nApplyCutGoldCnt = self.nApplyCutGoldCnt
	end
	self:Print("_GetScenceByUserId tMyself_%s",Cjson.encode(tScence.tMyself))

	self:Print("_GetScenceByUserId User_%d nApplyJionCnt_%d %d %d nGold_%.2f "
	,nUserId,tScence.nApplyJionCnt or -1,tScence.nApplyAddGoldCnt or -1,tScence.nApplyCutGoldCnt or -1,self.nGold) 
	
	self:Print("_GetScenceByUserId tMasterInfo_%s",Cjson.encode(self.tMasterInfo))

	--主席公共信息下发
	if self.tMasterInfo ~= nil then
		local tMasterInfo =  self.tMasterInfo
		if tMasterInfo then
			local tMasterInfoPublic = {}
			tMasterInfoPublic.nUserId = self.nMaster
			tMasterInfoPublic.sFaceId = self.tMasterInfo.sFaceId
			tMasterInfoPublic.sName = self.tMasterInfo.sName
			tMasterInfoPublic.nSex = self.tMasterInfo.nSex
			tMasterInfoPublic.sShopAcc = self.tMasterInfo.sShopAcc
			tMasterInfoPublic.nClubId = self.nClubId
			tScence.tMasterInfo = tMasterInfoPublic
		end	
	end	

	local tConfig = PubClubApi.GetClubWebConfig(self.nGroupId)
	tScence.sClubConfig = Cjson.encode(tConfig)

	local nTodayMaxGetCnt,nGiveGold = PublicRedis.GetGiveInfoOfLookAdvertisement(self.nGroupId)
    local nTodayCnt = PublicRedis.GetLookAdvertisementCnt(nUserId)
	local nAdertisementLeftCnt = nTodayMaxGetCnt - nTodayCnt
	if nAdertisementLeftCnt < 0 then
		nAdertisementLeftCnt =0
	end
	tScence.nAdertisementGoldLeftCnt =nAdertisementLeftCnt
	

	return tScence
end

--获取玩家信息(从服协议ClubSUser结构)
function ClubS:GetClubSUser(nUserId)
	local tUser = self:GetUserByUserId(nUserId)
	assert(tUser~=nil,string.format("Club_%d Get User_%d fail",self.nClubId,nUserId))
	local nGold = self:GetUserClubGold(nUserId)
	local tClubSUser = {}
	tClubSUser.nUserId = nUserId
	tClubSUser.sFaceId = tUser.sFaceId
	tClubSUser.sName = tUser.sName
	tClubSUser.nSex = tUser.nSex
	tClubSUser.nGold = nGold
	tClubSUser.nClubId = self.nClubId
	tClubSUser.nClubGold = tUser.nClubGold
	tClubSUser.nIdentify = tUser.nIdentify
	tClubSUser.nWeekCount = tUser.nWeekCount
	tClubSUser.nContribution = tUser.nContribution
	tClubSUser.nGoldContribution = tUser.nGoldContribution
	tClubSUser.sPower = Cjson.encode(tUser.arrPower)
	tClubSUser.sShopAcc = tUser.sShopAcc

	return tClubSUser
end

--根据玩家id获取玩家信息
function ClubS:GetUserByUserId(nUserId)
	local sUserId = tostring(math.floor(nUserId))
	return self.arrUser[sUserId]
end

--获取俱乐部玩家的sClientID
function ClubS:GetUserClientID()
	local arrClientID = {}
	for _,tUser in pairs(self.arrUser) do
		local sClientID = UserManager.GetUserClientID(tUser.nUserId)
		if sClientID then 
			table.insert(arrClientID,sClientID)
		end
	end
	return arrClientID
end

--获取俱乐部账户上的俱乐部币
function ClubS:GetClubGold()
	return self.nClubGold or 0
end

--获取玩家俱乐部币
function ClubS:GetUserClubGold(nUserId)
	local tUser = self:GetUserByUserId(nUserId)
	if tUser then
		local nItemId = self.nClubId
		if self.nClubId<Define.nMinClubId then  -- 大厅获取 金币 
			nItemId = 1 
		end 
		local nClubGold = PublicUserInfo.Get_User_Gold(nUserId,nItemId)
		return nClubGold
	end
	return 0
end

--玩家是否有权限
--@param nUserId 玩家id
--@param nPowerType 权限类型, 可以看Define.tPower
function ClubS:HasPower(nUserId, nPowerType)
	local isHas = false
	local tUser = self:GetUserByUserId(nUserId)
	if tUser then
		for k,v in pairs(tUser.arrPower or {}) do
			if v.nPowerType == nPowerType and v.isOpen then
				isHas = true
				break
			end
		end
	end
	return isHas
end

--获取某张牌桌的信息
--@params sTableId:牌桌id
function ClubS:GetTableInfo(sTableId)
	for nIndex,tTable in ipairs(self.arrTable) do
		if tTable.sTableId==sTableId then
			return tTable
		end
	end
end

-- 验证密码
function ClubS:CheckPass(sTableId, nPass)
	local tTable = self:GetTableInfo(sTableId)
	if not tTable then
		return false, ""
	end
	if (tTable.nIsPerson or 0) == 1 then
		local sPassWord = tTable.sPassWord or ""
		if sPassWord == "" then
			return true, ""
		end
		return sPassWord == nPass, sPassWord
	end
	return true, tTable.sPassWord or ""
end

--获取发送给前端的牌桌信息
function ClubS:GetProtoTableInfo(tTableInfo)
	local tProtoTableInfo = {}
	tProtoTableInfo.nTableIndex = tTableInfo.nTableIndex
	tProtoTableInfo.sTableId = tTableInfo.sTableId
	tProtoTableInfo.nGameId =  tTableInfo.nGameId
	tProtoTableInfo.sTableName =  tTableInfo.sTableName
	tProtoTableInfo.nClubId =  tTableInfo.nClubId
	tProtoTableInfo.nNowCnt = tTableInfo.nNowCnt --目前人数
	tProtoTableInfo.nOpentime = tTableInfo.nOpentime --开桌时间
	tProtoTableInfo.nLiveUserID = tTableInfo.nLiveUserID --房主id
	tProtoTableInfo.nKeepTime = tTableInfo.nKeepTime --房间时长
	tProtoTableInfo.nCapacity = tTableInfo.nCapacity --最大人数
	tProtoTableInfo.nGoldType = tTableInfo.nGoldType --使用的金币类型
	tProtoTableInfo.nTableStatus = tTableInfo.nTableStatus --房间状态 0:正常状态 1:暂停状态,停止计时
	tProtoTableInfo.isGameing = tTableInfo.isGameing --是否游戏中：0：非游戏中 1：游戏中
	tProtoTableInfo.nSittedList = tTableInfo.nSittedList --入座过列表 用于判断某张桌针对某个用户是否游戏中
	tProtoTableInfo.isAOF =tTableInfo.isAOF or false
	tProtoTableInfo.nInsureMode =tTableInfo.nInsureMode or 0
	tProtoTableInfo.nBuyMin = tTableInfo.nTakeInMin or 0
	tProtoTableInfo.nBuyMax = tTableInfo.nTakeInMax or 0
	tProtoTableInfo.nStartAtLeast = tTableInfo.nStartAtLeast or 2  --最低开始人数
	tProtoTableInfo.nTabkeOutOdd = tTableInfo.nTabkeOutOdd or 2  --撤码阙值倍数N
	tProtoTableInfo.nIsPerson = tTableInfo.nIsPerson or 0        		--是否私人房间 0否 1是
	-- tProtoTableInfo.nIsShow = tTableInfo.nIsShow						--是否显示房间 0否 1是

	--牌桌已过去的时间
	if tProtoTableInfo.nKeepTime~=-1 then
		local nNow = os.time()
		if tTableInfo.nTableStatus==1 and tTableInfo.nStopTimeTemp~=-1 then
			--牌桌处于暂停状态 牌桌已过去的时间 = 暂停的时间戳 - 开桌时间戳 - 累计暂停的时间
			tProtoTableInfo.nUseTime = tTableInfo.nStopTimeTemp - tTableInfo.nOpentime - tTableInfo.nSuspendStopTime
			local sNow = PublicApi.OsTimetoDataTime(nNow)
			local sOpen = PublicApi.OsTimetoDataTime(tTableInfo.nOpentime)
			local sStop = PublicApi.OsTimetoDataTime(tTableInfo.nSuspendStopTime)
			self:Print("_IsOpenGameId  暂停状态 sTableId_%s  nUseTime_%d sNow: %s sOpen: %s sStop: %s   "
			,tTableInfo.sTableId,tProtoTableInfo.nUseTime,sNow,sOpen,sStop )
		else
			--牌桌处于正常状态 牌桌已过去的时间 = 现在的时间戳 - 开桌时间戳 - 累计暂停的时间 
			tProtoTableInfo.nUseTime = nNow - tTableInfo.nOpentime - tTableInfo.nSuspendStopTime
			local sNow = PublicApi.OsTimetoDataTime(nNow)
			local sOpen = PublicApi.OsTimetoDataTime(tTableInfo.nOpentime)
			local sStop = PublicApi.OsTimetoDataTime(tTableInfo.nSuspendStopTime)
			self:Print("_IsOpenGameId  正常状态 sTableId_%s  nUseTime_%d sNow: %s sOpen: %s sStop: %s   "
			,tTableInfo.sTableId,tProtoTableInfo.nUseTime,sNow,sOpen,sStop )
		end
	end
	if PublicApi.IsTexasClassGame(tTableInfo.nGameId) then --德州,短牌,奥马哈
		tProtoTableInfo.nSmallBlind = tTableInfo.nSmallBlind --小盲
		tProtoTableInfo.nBigBlind = tTableInfo.nBigBlind --大盲  
		tProtoTableInfo.nPreAnte = tTableInfo.nPreAnte or tTableInfo.nSmallBlind  -- 前注
		tProtoTableInfo.nZhuaTou = tTableInfo.nZhuaTou   -- 抓头
		tProtoTableInfo.isDPreAnte = tTableInfo.isDPreAnte
		tProtoTableInfo.preAnteOdd = tTableInfo.preAnteOdd or 2
	elseif publicApi.IsNiuNiuClassGame(tTableInfo.nGameId) then --抢庄牛
		tProtoTableInfo.nBaseScore =  tTableInfo.nBaseScore   -- 牌桌底分 
	end
	
	tProtoTableInfo.isForceBlind=tTableInfo.isForceBlind    		--是否强制盲注 true:是 false:否
	tProtoTableInfo.isOnlyPlayByIOS=tTableInfo.isOnlyPlayByIOS 		--是否仅限IOS玩 true:是 fasle:否
	tProtoTableInfo.isGPSLimit=tTableInfo.isGPSLimit	  			--是否开启GPS限制 true:是 fasle:否
	tProtoTableInfo.isIPLimit=tTableInfo.isIPLimit		  			--是否开启ip地址限制 true:是 fasle:否 
	return tProtoTableInfo
end

-- 是否维护
local function ServiceMaintenance(sTableId)
    local nServerId =tonumber(string.match(sTableId,"(%d+)#"))
	if RedisCahche.GetServerState(nServerId) == 2 then
		Base.Log("ServiceMaintenance   维护  nServerId: "..nServerId)
		return true
	end
	Base.Log("ServiceMaintenance   不是维护  nServerId: "..nServerId)
	return false
end

-- 该游戏 是否开放 
function ClubS:IsOpenGameId(nGameId)
	return true
	-- self:Print("_IsOpenGameId  nGameId: "..nGameId)	
	-- local arrOpenGameId = PubClubApi.GetOpenGameIdConfig(self.nGroupId)  
	-- self:Print("_IsOpenGameId nGameId_%d  arrOpenGameId: %s ",nGameId,Cjson.encode(arrOpenGameId or {}))
	-- for _, nId in ipairs(arrOpenGameId) do
	-- 	if nId == nGameId then 
	-- 		return true 
	-- 	end 
	-- end	
	-- self:Print("_IsOpenGameId  nGameId: "..nGameId.."  false")
	-- return false 
end

--获取牌桌列表
--@params nTableIndex:开始的牌桌index
--@params nCnt：多少条
--版本修改只看见自己创建的牌桌和公共牌桌
function ClubS:GetTableList(nTableIndex,nCnt,isVacancy,nUserId, tScrean)
	self:Print("_GetTableList  nTableIndex_%d  nCnt_%d  nUserId_%d  ",nTableIndex,nCnt,nUserId)
	-- self:Print("_GetTableList  self.arrTable: %s",Cjson.encode(self.arrTable))
 	local arrTableInfo = {}
	local arrTableId = {}
	local nNowCnt = 0
	if #self.arrTable > 0 then
		for i = #self.arrTable, 1, -1 do
			local tTable = self.arrTable[i]
			local isSuccee = true
			local nChip = tTable.nSmallBlind
			if (nTableIndex == 0 or tTable.nTableIndex < nTableIndex) and not ServiceMaintenance(tTable.sTableId) then
				if tTable.nLiveUserID ~= nUserId then
					-- 不是自己开的桌子 并且 不是公共桌子 暂时为true
					isSuccee = true
				end
				-- 是否空位
				if isVacancy and tTable.nNowCnt == tTable.nCapacity then
					isSuccee = false
				end
				if tScrean and tScrean.arrChipLevel and #tScrean.arrChipLevel > 0 then
					local nCnt1 = 0
					for _, tChipLevel in ipairs(tScrean.arrChipLevel) do
						table.sort(tChipLevel)
						if nChip >= tChipLevel[1] and nChip <= tChipLevel[2] then
							nCnt1 = nCnt1 + 1
							break
						end
					end
					if nCnt1 == 0 then
						isSuccee = false
					end
				end
				-- 该游戏未开放
				if isSuccee and not self:IsOpenGameId(tTable.nGameId) then
					isSuccee = false
					self:Print("_GetTableList  not open nGameId_%d  ",tTable.nGameId)
				end
				if (tTable.nIsShow or 1) == 0 then --是否显示房间 0否 1是
					-- isSuccee = false
				end
				self:Print("_GetTableList  (tTable.nIsShow or 1) == 0 tTable.nIsShow:%d :%s  ", tTable.nIsShow, tostring((tTable.nIsShow or 1) == 0))
				if isSuccee then
					local tTableInfo = self:GetProtoTableInfo(tTable)
					for j = 0, #tTableInfo.nSittedList do
						if tTableInfo.nSittedList[j] == nUserId then
							tTableInfo.isGameing = 1
						end
					end
					local sTableInfo = Cjson.encode(tTableInfo)
					table.insert(arrTableInfo,sTableInfo)
					-- 优先显示自己坐过的桌子
					-- table.sort(arrTableInfo, function(a, b)
					-- 	local aHasUser = false
					-- 	local bHasUser = false
					-- 	for _, v in ipairs(Cjson.decode(a).nSittedList) do
					-- 	if v == nUserId then
					-- 		aHasUser = true
					-- 		break
					-- 	end
					-- 	end
					-- 	for _, v in ipairs(Cjson.decode(b).nSittedList) do
					-- 	if v == nUserId then
					-- 		bHasUser = true
					-- 		break
					-- 	end
					-- 	end
					-- 	if aHasUser == bHasUser then
					-- 	return (Cjson.decode(a).nUseTime or 0) < (Cjson.decode(b).nUseTime or 0)
					-- 	else
					-- 	return aHasUser and not bHasUser
					-- 	end
					-- end)

					table.insert(arrTableId,tTableInfo.sTableId)
					nNowCnt = nNowCnt + 1
					if nNowCnt>=nCnt then
						break
					end
				end
			end
		end
	end
	return arrTableInfo,arrTableId
end

--获取牌桌列表
--@params nTableIndex:开始的牌桌index
--@params nCnt：多少条
--版本修改只看见自己创建的牌桌和公共牌桌
function ClubS:GetGameTableList(nTableIndex,nCnt,nGameId,sScreen,nUserId)
	self:Print("_GetGameTableList  nTableIndex_%d  nCnt_%d  nGameId_%d  sScreen_%s  nUserId_%d  ",nTableIndex,nCnt,nGameId,sScreen or "",nUserId)
	-- self:Print("_GetGameTableList  self.arrTable: %s",Cjson.encode(self.arrTable))
	if nGameId == 0 then
		local isVacancy = false
		local tScrean = nil
		if sScreen and #sScreen > 0 then
			local isSuccee,tScrean1 = pcall(Cjson.decode,sScreen) -- 筛选：有则筛选
			if not isSuccee then
				self:Print("_GetGameTableList  decode Fail  sScreen: "..sScreen)
				return
			end
			isVacancy = tScrean1.isVacancy or false
			tScrean = tScrean1
		end
		return self:GetTableList(nTableIndex,nCnt,isVacancy,nUserId,tScrean)
	end
	self:Print("_GetGameTableList nTableIndex%d  nCnt%d  nGameId_%d   sScreen_%s  ",nTableIndex,nCnt,nGameId,sScreen or "")
	local arrTableInfo = {}
	local arrTableId = {}
	local arrIndex = {}
	-- self:Print("_GetGameTableList  self.arrTable: %s",Cjson.encode(self.arrTable))
	for i = #self.arrTable, 1, -1 do
		local tTable = self.arrTable[i]
		-- self:Print("_GetGameTableList for i=#self.arrTable,1,-1 do  tTable.nGameId_%d  nGameId_%d  ",tTable.nGameId,nGameId)
		if tTable.nGameId == nGameId and not ServiceMaintenance(tTable.sTableId) then
			if tTable.nLiveUserID == nUserId then
				-- 是自己开的桌子 并且 不是公共桌子
				-- table.insert(arrIndex, i)
			end
			table.insert(arrIndex, i)
		end
	end
	if sScreen and #sScreen > 0 then
		local isSuccee,tScrean = pcall(Cjson.decode,sScreen) -- 筛选：有则筛选
		if not isSuccee then
			self:Print("_GetGameTableList  decode Fail  sScreen: "..sScreen)
			return
		end 
		--[[
			arrChipLevel={{0-10},{10-50}} --筹码级别（指大盲配置）：0-10，10-50，50-100，100-1000，1000-100000000
			arrPlayerCnt={{2-2},{3-6}}    --指定人数（指牌桌座位）：2-2人，3-6人,7-9人
			isForceBlind                  --是否强制盲注 
			isAOF			              --是否仅限AllIn和弃牌 
			isOpenInsure	              --是否开保险 	
        	isVacancy	                  --是否 空位 	
		]]
		local arr = {}
		for _, i in ipairs(arrIndex) do
			local tTable = self.arrTable[i]
			local isSuccee = true
			local nChip = tTable.nSmallBlind
			if nGameId == 175 then   -- 短牌的前注 
				nChip = tTable.nPreAnte
			end
			local isOpenInsure = false
			if tTable.nInsureMode and math.floor(tTable.nInsureMode) ~= 0 then
				isOpenInsure = true
			end
			-- 是否空位
			if tScrean.isVacancy and tTable.nNowCnt == tTable.nCapacity then
				isSuccee = false
			end
			if tScrean.arrChipLevel and #tScrean.arrChipLevel > 0 then
				local nCnt = 0
				for _, tChipLevel in ipairs(tScrean.arrChipLevel) do
					table.sort(tChipLevel)
					if nChip >= tChipLevel[1] and nChip <= tChipLevel[2] then
						nCnt = nCnt + 1
						break
					end
				end
				if nCnt == 0 then
					isSuccee = false
				end
			end
			if isSuccee and tScrean.arrPlayerCnt and #tScrean.arrPlayerCnt > 0 then
				local nCnt = 0
				for _, tPlayerCnt in ipairs(tScrean.arrPlayerCnt) do
					table.sort(tPlayerCnt)
					if tTable.nCapacity >= tPlayerCnt[1] and tTable.nCapacity <= tPlayerCnt[2] then
						nCnt = nCnt + 1
						break
					end
				end
				if nCnt == 0 then
					isSuccee = false
				end
			end
			if (tTable.nIsShow or 1) == 0 then --是否显示房间 0否 1是
				isSuccee = false
			end
			if isSuccee then
				if tScrean.isAOF then
					if not tTable.isAOF then  --是否仅限AllIn和弃牌 true:是 fasle:否
						isSuccee = false
					end
				end
				if isSuccee and tScrean.isOpenInsure then
					if not isOpenInsure then 	--是否保险 true:是 false:否
						isSuccee = false
					end
				end
				if isSuccee and tScrean.isForceBlind then
					if not tTable.isForceBlind then 	--是否强制盲注 true:是 false:否
						isSuccee = false
					end
				end
				if isSuccee and tScrean.isOnlyPlayByIOS then
					if not tTable.isOnlyPlayByIOS then   --是否仅限IOS玩 true:是 fasle:否
						isSuccee = false
					end
				end
				if isSuccee and tScrean.isGPSLimit then
					if not tTable.isGPSLimit then  	--是否开启GPS限制 true:是 fasle:否
						isSuccee = false
					end
				end
				if isSuccee and tScrean.isIPLimit then
					if not tTable.isIPLimit then  --是否开启ip地址限制 true:是 fasle:否
						isSuccee = false
					end
				end
				-- 该游戏未开放
				if isSuccee and not self:IsOpenGameId(tTable.nGameId) then
					isSuccee = false
				end
			end
			if isSuccee then
				table.insert(arr, i)
			end
		end
		arrIndex = arr
	end
	local tempTable = {}
	if #arrIndex > 0 then
		for _, i in ipairs(arrIndex) do
			local tTable = self.arrTable[i]
			-- 检查房间是否显示 (nIsShow: 0=不显示, 1=显示)
			if (tTable.nIsShow or 1) == 0 then
				-- 不显示的房间跳过
				-- goto continue
			end
			self:Print("GetGameTableList  (tTable.nIsShow or 1) == 0 tTable.nIsShow:%d :%s  ", tTable.nIsShow, tostring((tTable.nIsShow or 1) == 0))
			local tTableInfo = self:GetProtoTableInfo(tTable)
			-- 检查用户是否在这个房间中
			local userInTable = false
			for j = 1, #tTableInfo.nSittedList do
				if tTableInfo.nSittedList[j] == nUserId then
					tTableInfo.isGameing = 1
					userInTable = true
					break
				end
			end
			-- 记录排序信息
			table.insert(tempTable, {
				json = Cjson.encode(tTableInfo),
				hasUser = userInTable,
				useTime = tTableInfo.nUseTime or 0,
				tableId = tTableInfo.sTableId
			})
			::continue::
		end
		-- 排序：有用户的房间优先，然后按使用时间排序
		table.sort(tempTable, function(a, b)
			-- 1. 用户是否在房间中（有用户的排在前面）
			if a.hasUser ~= b.hasUser then
				return a.hasUser  -- a有用户，b没有，a排前面
			end
			-- 2. 按使用时间升序（使用时间小的排前面）
			return a.useTime < b.useTime
		end)

		for _, item in ipairs(tempTable) do
			table.insert(arrTableInfo, item.json)
			table.insert(arrTableId, item.tableId)
		end
	end
	return arrTableInfo, arrTableId
end


--获取个人的桌子数目
--@params nUserId 玩家id
--@return nCnt 数目
function ClubS:GerPerSonTableCnt(nUserId)
	local nCnt = 0
	self:Print("_GerPerSonTableCnt  nUserId_%d  ",nUserId)
	self:Print("_GerPerSonTableCnt  self.arrTable: %s",Cjson.encode(self.arrTable))
	for nIndex,tTable in pairs(self.arrTable) do
		if tTable.nLiveUserID == nUserId then
			nCnt = nCnt + 1
		end
	end
	return nCnt
end

--获取主席信息
function ClubS:GetMasterInfo()
	return self.tMasterInfo or {}
end

--获取各种申请的数量
function ClubS:GetApplyCnt()
	return self.nApplyJionCnt,self.nApplyAddGoldCnt,self.nApplyCutGoldCnt
end

--获取所有拿了这张牌桌的玩家的ClientID
function ClubS:GetUserClientIDOfTable(sTableId)
	local arrClientID = {}
	for _,tUser in pairs(self.arrUser) do
		if self:HasUserGetThisTable(tUser.nUserId,sTableId) then
			UserManager.GetUserClientID(tUser.nUserId)
			local sClientID = UserManager.GetUserClientID(tUser.nUserId)
			if sClientID then 
				table.insert(arrClientID,sClientID)
			end
		end
	end
	return arrClientID
end

--获取所有拿了这张牌桌的玩家的ClientID，并且删除牌桌id
function ClubS:GetAndDelUserClientIDOfTable(sTableId)
	local arrClientID = {}
	for _,tUser in pairs(self.arrUser) do
		if self:HasUserGetThisTable(tUser.nUserId,sTableId) then
			UserManager.GetUserClientID(tUser.nUserId)
			local sClientID = UserManager.GetUserClientID(tUser.nUserId)
			if sClientID then 
				table.insert(arrClientID,sClientID)
			end
			self:DelUserGetTables(tUser.nUserId,sTableId)
		end
	end
	return arrClientID
end

--获取有相关权限的玩家的sClientID
function ClubS:GetAdminClientID(nPowerType)
	local arrClientID = {}
	for k,v in pairs(self.arrUser) do
		if v.nIdentify==Define.nAdmin and self:HasPower(v.nUserId,nPowerType) then
			local sClientID = UserManager.GetUserClientID(v.nUserId)
			if sClientID then 
				table.insert(arrClientID,sClientID)
			end
		elseif v.nIdentify==Define.nMaster then
			local sClientID = UserManager.GetUserClientID(v.nUserId)
			if sClientID then 
				table.insert(arrClientID,sClientID)
			end
		end
	end
	return arrClientID
end
------------------------------俱乐部数据相关 end--------------------------

------------------------------发送给玩家 start--------------------------
--广播给本俱乐部的所有玩家
function ClubS:Broadcast(strProto,tSendData)
	local arrClientID = self:GetUserClientID()
	MsgApi.SendToGateWay(strProto,tSendData,arrClientID)
end

--发送给玩家
function ClubS:SendToUser(nUserId,strProto,tSendData)
	MsgApi.SendToUser(nUserId,strProto,tSendData)
end

--发送给有权限的管理员(或者主席)
--@param nPowerType 权限类型, 可以看Define.tPower
function ClubS:SendToAdmin(strProto,tSendData,nPowerType)
	local arrClientID = self:GetAdminClientID(nPowerType)
	if #arrClientID<0 then
		return
	end
	self:BroadcastToSomeUser(arrClientID,strProto,tSendData)
end

--广播给特定的玩家
function ClubS:BroadcastToSomeUser(arrClientID,strProto,tSendData)
	if #arrClientID<=0 then
		return
	end
	MsgApi.SendToGateWay(strProto,tSendData,arrClientID)
end

--通知玩家服务器维护，以及踢出玩家
--isEnterMaintain=true  未维护->维护,在俱乐部里面的玩家全部踢走
--isEnterMaintain=false 维护期间,在俱乐部里面的非白名单玩家全部踢走
function ClubS:NotifyAllUserMaintenance(isEnterMaintain)
	local ClubSMaintenanceNotify = {}
	ClubSMaintenanceNotify.sTime = string.format("%s - %s",MsgMaintenance.tMaintenanceInfo.sStartTime,MsgMaintenance.tMaintenanceInfo.sEndTime)

	for sUserId,tUser in pairs(self.arrUser) do
		local nUserId = tUser.nUserId
		if not PublicRedis.IsWhiteListUser(nUserId) then
			self:SendToUser(nUserId,"ClubSMaintenanceNotify",ClubSMaintenanceNotify)
			UserManager.DelUser(nUserId)
			self.arrUser[sUserId] = nil
			self:Print("_KickOutAllUser 服务器维护,非白名单玩家被强制踢出 sUserId:%s",sUserId)
		elseif isEnterMaintain then
			self:SendToUser(nUserId,"ClubSMaintenanceNotify",ClubSMaintenanceNotify)
			UserManager.DelUser(nUserId)
			self.arrUser[sUserId] = nil
			self:Print("_KickOutAllUser 服务器未维护->维护,白名单玩家也踢出 sUserId:%s",sUserId)
		else
			self:Print("_KickOutAllUser 服务器维护,白名单玩家不踢出 sUserId:%s",sUserId)
		end
	end
end
------------------------------发送给玩家 end--------------------------

------------------------------俱乐部玩家数据相关 start--------------------------

--批量保存玩家已获取的牌桌id
function ClubS:SetUserGetTables(nUserId,arrTableId)
	local tUser = self:GetUserByUserId(nUserId)
	if tUser then
		for _,sTableId in pairs(arrTableId or {}) do
			tUser.tAlreadyGetTable[sTableId] = sTableId
		end
	end
end

--保存玩家已获取的牌桌id
function ClubS:SetUserGetTableId(nUserId,sTableId)
	local tUser = self:GetUserByUserId(nUserId)
	if tUser then
		tUser.tAlreadyGetTable[sTableId] = sTableId
	end
end

--删除玩家已获得的牌桌
function ClubS:DelUserGetTables(nUserId,sTableId)
	local tUser = self:GetUserByUserId(nUserId)
	if tUser then
		tUser.tAlreadyGetTable[sTableId] = nil
	end
end

--玩家是否拿了这张牌桌
function ClubS:HasUserGetThisTable(nUserId,sTableId)
	local tUser = self:GetUserByUserId(nUserId)
	if tUser and tUser.tAlreadyGetTable[sTableId] then
		return true
	end
	return false
end

-- 用户结算
function ClubS:_UserSettleHandle(nUserId, tChangeInfo)
	local tUser = UserManager.GetUserInfo(nUserId)
	if not tUser then
	   self:Print("_UserSettleHandle     nUserId_%d  tUser is nil ",nUserId)
	   return
	end
	UserOnTime.StaticUser(nUserId, tChangeInfo)
	--[[
	local nPlayCnt = 0
	 local Redis =tBase.m_MyRedisData[2].redis
	local sKey= string.format("TexaStatistic_%d",nUserId)
	local tStatistic =  Redis:hgetall(sKey)
	for Str, v in pairs(tStatistic) do
	   local nCnt = publicApi.Get_String_Arise_Count(Str,"nPlayCount_0_")
	   if nCnt > 0 then
		  nPlayCnt = nPlayCnt + tonumber(v)
			self:Print("_UserSettleHandle    nUserId_%d  [%s=%d] %d  ",nUserId,Str,v,nPlayCnt)
	   end
	end
	if nPlayCnt + 1 == 30 then
		local tUserInfo = PublicUserInfo.GetUserBasic(nUserId)
		if not tUserInfo then
			self:Print("_UserSettleHandle  nUserId_%d  tUserInfo is nil  ",nUserId)
			return
		end
		local t = {nGroupId=tUser.nGroupId,nUserId=nUserId,sFaceId = tUserInfo.sFaceID,sName = tUserInfo.sNickName}
		local sSql = string.format("call ActivityRecommend_Handle(%d,%d)",1,nUserId)
		local ClubRecommendHandleReq = {}
		ClubRecommendHandleReq.nHandle = 1
		ClubRecommendHandleReq.sSql = sSql
		ClubRecommendHandleReq.sJson = Cjson.encode(t)
		MsgApi.SendToDBServer("ClubRecommendHandleReq",ClubRecommendHandleReq)
		self:Print("_UserSettleHandle  nUserId_%d  nPlayCnt_%d 满足条件 %s "
		,nUserId,nPlayCnt,Cjson.encode(t))
	else
		self:Print("_UserSettleHandle  nUserId_%d  nPlayCnt_%d  ",nUserId,nPlayCnt)
	end
	]]
end

function ClubS:GetPageUsers(nPage, nCnt)
    local users = self.arrUser or {}
    local total = 0
    local result = {}
    if not nCnt or nCnt <= 0 then
        nCnt = 10
    elseif nCnt > 30 then
        nCnt = 30
    end
    if not nPage or nPage <= 0 then
        nPage = 1
    end
    for _ in pairs(users) do
        total = total + 1
    end
    local userList = {}
    for _, info in pairs(users) do
        table.insert(userList, info)
    end
    -- table.sort(userList, function(a, b) return a.UserId < b.UserId end)
    local startIndex = (nPage - 1) * nCnt + 1
    local endIndex = math.min(startIndex + nCnt - 1, #userList)
    for i = startIndex, endIndex do
        table.insert(result, userList[i])
    end
    return {
        total = total,   -- 总人数
        page = nPage,    -- 当前页码
        pageSize = nCnt, -- 每页数量
        arrUser = result,  -- 当前页用户
		nMaxUserCnt = self.nMaxUserCnt,
    }
end


------------------------------俱乐部玩家数据相关 end--------------------------
function ClubS:Print(str,...) 
	Logger:info(string.format("Id=>"..self.nClubId.."=>"..str,...))
end

function ClubS:PrintError(str,...)
	Logger:error(string.format("Id=>"..self.nClubId.."=>"..str,...))
end

--俱乐部关闭
function ClubS:Close()
	self.Timer:KillAllTimer()
	self.Timer = nil

	--通知所有俱乐部玩家俱乐部关闭
	local ClubSCloseNotify = {}
	ClubSCloseNotify.nClubId = self.nClubId

	for sUserId,tUser in pairs(self.arrUser) do
		local nUserId = tUser.nUserId
		self:SendToUser(nUserId,"ClubSCloseNotify",ClubSCloseNotify)
		UserManager.UserLeaveClub(nUserId,self.nClubId)
		self.arrUser[sUserId] = nil
		self:Print("_Close 俱乐部关闭,玩家被强制踢出 sUserId:%s",sUserId)
	end
end

return ClubS