local MsgCenter = {}

--中心服消息统一校验
function MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   local tData =CenterAux:Parser(Data, nLen, strProto)
   if not tData then
       Base.Log("%s _Parse Err",strProto)
       return
   end

   return tData
end

--中心服消息处理
function MsgCenter._OnCenterServTableMsgHandle(strReq,Data,nLen) 
   local tData =CenterAux:Parser(Data, nLen,strReq)
   assert(tData~=nil and tData.nClubId~=nil)
   local tClub =ClubSManager.GetClub(tData.nClubId)
   if tClub==nil  then
      Base.Log(" nClubId_%d tClub is nil  strReq  %s  ",tData.nClubId,strReq)
      return
   end

   tClub:OnCenterMsgHandle(strReq,tData)
end

--俱乐部场景通知
function MsgCenter.OnClubCSceneNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCSceneNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end

   Base.Log("_OnClubCSceneNotify 俱乐部场景通知,本服需要创建俱乐部")

   if ClubSManager.ClubIsExist(tData.nClubId) then
      Base.Log("_OnClubCSceneNotify 本服已有这个俱乐部, nClubId:%d",tData.nClubId)
      return
   end

   local tScence = tData.tScence
   local tClub = ClubSManager.CreateClub(tScence.nGroupId,tScence.nClubId)
   if tClub then
      tClub:InitScene(tScence)
   end
end

--切换俱乐部通知
function MsgCenter.OnClubCSwitchNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCSwitchNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end
   local tUser = UserManager.GetUserInfo(tData.nUserId)
   if not tUser then
      return
   end

   Base.Log("_OnClubCSwitchNotify 切换俱乐部通知 玩家在其他从服登录了,清除本服数据 nUserId_%d",tData.nUserId)

   --删除玩家在本服的数据
   ClientIdMgr.DestroyUserContact(tData.nUserId)
   local nNowClubId = tUser:GetNowClub()
   if nNowClubId~=0 then
      --有所在的俱乐部
      local tClub = ClubSManager.GetClub(nNowClubId)
      if tClub then
         tClub:Leave(tData.nUserId)
      end
   end
   UserManager.DelUser(tData.nUserId)
end

--俱乐部场景信息改变通知
function MsgCenter.OnClubCSceneChangeNotify(sReturnKey,Data,nLen)
   MsgCenter._OnCenterServTableMsgHandle("ClubCSceneChangeNotify",Data,nLen)
end

--俱乐部玩家信息改变通知
function MsgCenter.OnClubCUserInfoChangeNotify(sReturnKey,Data,nLen)
   MsgCenter._OnCenterServTableMsgHandle("ClubCUserInfoChangeNotify",Data,nLen)
end

--踢出俱乐部通知
function MsgCenter.OnClubCKickOutNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCKickOutNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end

   Base.Log("_OnClubCKickOutNotify 踢出俱乐部通知 nClubId_%d,nUserId_%d",tData.nClubId,tData.nUserId)

   --玩家离开俱乐部
   local tClub = ClubSManager.GetClub(tData.nClubId)
   if tClub then
      tClub:Leave(tData.nUserId)
   end

   --通知玩家
   local sClientID = ClientIdMgr.GetClientIdByUserId(tData.nUserId)
   if sClientID then
      local ClubSKickOutNotify = {}
      ClubSKickOutNotify.nClubId = tData.nClubId
      ClubSKickOutNotify.nUserId = tData.nUserId
      ClubSKickOutNotify.sClubName = tData.sClubName
      MsgApi.SendToClient(sClientID,"ClubSKickOutNotify",ClubSKickOutNotify)
      Base.Log("_OnClubCKickOutNotify 通知玩家被踢出俱乐部 nClubId_%d,nUserId_%d",tData.nClubId,tData.nUserId)
   end
end

--玩家消息通知
function MsgCenter.OnClubCUserMsgNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCUserMsgNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end

   --通知玩家
   local sClientID = ClientIdMgr.GetClientIdByUserId(tData.nUserId)
   if sClientID then
      Base.Log("_OnClubCUserMsgNotify 玩家消息通知 nUserId_%d,nType_%d,sExData_%s",tData.nUserId,tData.nType,tData.sExData)
      local isSuccee,tExData = pcall(Cjson.decode,tData.sExData)
      if not isSuccee then
         if type(tExData) == "string" then 
            Logger:error(tExData)
         else 
            Base.LogT(tExData) 
         end
         return
      end

      local ClubSUserMsgNotify = {}
      ClubSUserMsgNotify.nUserId = tData.nUserId
      ClubSUserMsgNotify.nType = tData.nType
      if tData.nType==1 then
         ClubSUserMsgNotify.tClubInfo = tExData.tClubInfo
         ClubSUserMsgNotify.tApply = tExData.tApply
         ClubSUserMsgNotify.tNoticesItem = tExData.tNoticesItem
         ClubSUserMsgNotify.tUserInfo = tExData.tUserInfo
         ClubSUserMsgNotify.arrRedot = tExData.arrRedot
         Base.Log("_OnClubCUserMsgNotify 俱乐部申请被处理")
      elseif tData.nType==2 then 
         ClubSUserMsgNotify.tNoticesItem = tExData.tNoticesItem
         ClubSUserMsgNotify.arrRedot = tExData.arrRedot
         Base.Log("_OnClubCUserMsgNotify 收到俱乐部邀请")
      elseif tData.nType==3 then
         ClubSUserMsgNotify.tClubInfo = tExData.tClubInfo
         Base.Log("_OnClubCUserMsgNotify 同意加入俱乐部邀请")
      elseif tData.nType==4 then
         ClubSUserMsgNotify.tClubInfo = tExData.tClubInfo
         ClubSUserMsgNotify.tApply = tExData.tApply
         ClubSUserMsgNotify.tNoticesItem = tExData.tNoticesItem
         ClubSUserMsgNotify.tUserInfo = tExData.tUserInfo
         ClubSUserMsgNotify.arrRedot = tExData.arrRedot
         Base.Log("_OnClubCUserMsgNotify 俱乐部币申请被处理")
      elseif tData.nType==5 then
         ClubSUserMsgNotify.tClubInfo = tExData.tClubInfo
         ClubSUserMsgNotify.tApply = tExData.tApply
         ClubSUserMsgNotify.tNoticesItem = tExData.tNoticesItem
         ClubSUserMsgNotify.tUserInfo = tExData.tUserInfo
         ClubSUserMsgNotify.arrRedot = tExData.arrRedot
         Base.Log("_OnClubCUserMsgNotify 俱乐部币退还申请被处理")
      elseif tData.nType==6 then
         ClubSUserMsgNotify.tClubInfo = tExData.tClubInfo
         ClubSUserMsgNotify.tNoticesItem = tExData.tNoticesItem
         ClubSUserMsgNotify.tUserInfo = tExData.tUserInfo
         ClubSUserMsgNotify.arrRedot = tExData.arrRedot
         Base.Log("_OnClubCUserMsgNotify 管理员对玩家的操作通知")
      elseif tData.nType==7 then
         ClubSUserMsgNotify.arrRedot = tExData.arrRedot
         Base.Log("_OnClubCUserMsgNotify 后台审核通知")
      end
      MsgApi.SendToClient(sClientID,"ClubSUserMsgNotify",ClubSUserMsgNotify)
   end
end

--俱乐部桌开桌通知
function MsgCenter.OnClubCTableOpenNotify(sReturnKey,Data,nLen)
   MsgCenter._OnCenterServTableMsgHandle("ClubCTableOpenNotify",Data,nLen)
end

--俱乐部桌关桌通知
function MsgCenter.OnClubCTableCloseNotify(sReturnKey,Data,nLen)
   MsgCenter._OnCenterServTableMsgHandle("ClubCTableCloseNotify",Data,nLen)
end

--俱乐部桌信息改变通知
function MsgCenter.OnClubCTableInfoNotify(sReturnKey,Data,nLen)
   MsgCenter._OnCenterServTableMsgHandle("ClubCTableInfoNotify",Data,nLen)
end

--俱乐部关闭通知
function MsgCenter.OnClubCCloseNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCCloseNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end
   Base.Log("_OnClubCCloseNotify 中心服俱乐部关闭通知 nClubId:%d",tData.nClubId)
   ClubSManager.RemoveClub(tData.nClubId)
end

--维护信息通知
function MsgCenter.OnClubCServerMaintenanceNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCServerMaintenanceNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end
   Base.Log("_OnClubCServerMaintenanceNotify 中心服维护信息通知 %s",tData.sMaintenance)
   local isSuccee,tMaintenanceInfo = pcall(Cjson.decode,tData.sMaintenance)
   if not isSuccee then
      Base.Log("_OnClubCServerMaintenanceNotify decode sMaintenance Err")
      return
   end
   if MsgMaintenance.tMaintenanceInfo then
      if MsgMaintenance.tMaintenanceInfo.ActualStart==tMaintenanceInfo.ActualStart and MsgMaintenance.tMaintenanceInfo.ActualEnd==tMaintenanceInfo.ActualEnd then
         Base.Log("_OnClubCServerMaintenanceNotify 维护信息没有改变")
         return
      end
   end
   local nNowTime = os.time()
   if tMaintenanceInfo.ActualStart<=nNowTime and nNowTime<=tMaintenanceInfo.ActualEnd then
      Base.Log("已经是维护中 %s - %s",tMaintenanceInfo.sStartTime,tMaintenanceInfo.sEndTime)
      tMaintenanceInfo.isEnterMaintain = false
  end
   MsgMaintenance.tMaintenanceInfo = tMaintenanceInfo
   MsgMaintenance.CheckMaintenance()
end

--中心服分组数据通知
function MsgCenter.OnClubCServerGroupNotify(sReturnKey,Data,nLen)
   local strProto = "ClubCServerGroupNotify"
   local tData = MsgCenter._CheckCenterMsg(strProto, Data, nLen)
   if not tData then
      return
   end
   local isPrint = false
   local arrGroup = {}
   for _,nGroupId in pairs(tData.arrGroup) do
      if type(nGroupId)=="number" then
         table.insert(arrGroup,nGroupId)
      end
   end

   if #arrGroup>1 then
      table.sort(arrGroup,function (a, b)
         return a<b
      end)
   end

   if #arrGroup~=#SlaveData.arrGroup then
      isPrint = true
   elseif #arrGroup==#SlaveData.arrGroup and #arrGroup>1 then
      for i=1,#arrGroup do
         if arrGroup[i]~=SlaveData.arrGroup[i] then
            isPrint = true
            break
         end
      end
   end

   SlaveData.arrGroup = arrGroup

   if isPrint then
      Base.Log("_OnClubCServerGroupNotify arrGroup:%s",Cjson.encode(SlaveData.arrGroup))
   end

   MsgOnTime.UpdateClubConfig() --更新俱乐部配置
end
 

return MsgCenter