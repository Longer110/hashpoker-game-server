local MsgWeb = {}

--后台个人信息刷新通知
function MsgWeb.OnWebChangeUserInfoNotify(sReturnKey,Data,nLen)
    local tData =BackstageAux:Parser(Data, nLen,"ChangeUserInfoNotify")
    if not tData then
        Base.Log("ChangeUserInfoNotify _Parse Err")
        return
    end

    Base.Log("_OnWebChangeUserInfoNotify 后台个人信息刷新通知 sChangeInfo:%s",tData.sChangeInfo)

    local isSuccee,tChangeInfo = pcall(Cjson.decode,tData.sChangeInfo)
    if isSuccee then
        if tChangeInfo.nUserID then
            --更新redis上的玩家数据
            PublicUserInfo.UpdateUserData(tChangeInfo)
            --通知游戏服
            MsgApi.SendUserInfoChangeToGameServer(tChangeInfo.nUserID,tChangeInfo) 

            --修改本地缓存
            local tUser = UserManager.GetUserInfo(tChangeInfo.nUserID)
            if tUser then
                for k,v in pairs(tChangeInfo) do
                    if k=="sFaceID" then
                        tUser.sFaceId = tChangeInfo.sFaceID
                    end
                end

                local nNowClubId = tUser:GetNowClub()
                --通知玩家所在俱乐部，玩家信息改变
                MsgApi.SendUserInfoChange(nNowClubId,tChangeInfo.nUserID,{sFaceId=tChangeInfo["sFaceID"]})
            end

            local arrClub = ClubSManager.GetAllClub()
            for _,tClub in pairs(arrClub) do
                local tMasterInfo = tClub:GetMasterInfo()
                if tMasterInfo.nMaster==tChangeInfo.nUserID then
                    --通知这个玩家所创建的俱乐部，主席信息改变
                    if tChangeInfo["sFaceID"] then
                        tMasterInfo.sFaceId = tChangeInfo["sFaceID"]
                    end
                    MsgApi.SendClubInfoChange(tClub.nClubId,{tMasterInfo=tMasterInfo})
                end
            end

            MsgApi.SendPerSonInfoChange(tChangeInfo.nUserID,{sFaceId=tChangeInfo["sFaceID"]})
        end
    end
end

--后台踢人通知
function MsgWeb.OnWebKickOut(sReturnKey,Data,nLen)
    local ReadData = Base.GetRP().new(Data, nLen)
   local Sys = ReadData:GetModuleID()
   local Sub = ReadData:GetMsgID()
   local Read = ProtoManager.PubProto_1_pb.REQ_Kick_User()
   Read:ParseFromString(ReadData:GetString())
   local nUserId    = Read.nUserId or -1
   local nType      = Read.nType or -1    --1:立即踢出，解散 2:下局踢出  4:踢到登录界面

   local tUser =  UserManager.GetUserInfo(nUserId)
   if not tUser then
       return
   end
   if nType == 1 then
        -- 禁止提现 内转
        PublicUserInfo.UpdateUserData({nUserID = tonumber(nUserId), isBan = true})
   end

   Base.Log("_OnWebKickOut 后台踢人通知  nUserId_%d nType_%d",nUserId,nType)

   if not (nType == 1 or nType == 4) then
       return
   end

   local ClubSWebKickOutNotify = {}
   ClubSWebKickOutNotify.nUserId = nUserId
   ClubSWebKickOutNotify.nType = nType
   MsgApi.SendToUser(nUserId,"ClubSWebKickOutNotify",ClubSWebKickOutNotify)

   local nNowClubId = tUser:GetNowClub()
    if nNowClubId~=0 then
        --有所在的俱乐部
        local tClub = ClubSManager.GetClub(nNowClubId)
        if tClub then
            tClub:Leave(nUserId)
        end
    end
    UserManager.DelUser(nUserId)
    Base.Log("_OnWebKickOut 删除玩家")
end

return MsgWeb