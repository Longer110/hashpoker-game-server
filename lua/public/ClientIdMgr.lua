

local tClientIdToUserId ={}
local tUserIdToClientId ={}
local function _BuildContact(sClientID,nUserId)
   local sOldCliendID =tUserIdToClientId[nUserId]
   if sOldCliendID then
      tClientIdToUserId[sOldCliendID]=nil
   end
   tClientIdToUserId[sClientID]=nUserId
   tUserIdToClientId[nUserId]=sClientID
end

local function _DestroyContact(sClientID)
   local nUserId= tClientIdToUserId[sClientID]
   tClientIdToUserId[sClientID] =nil
   if nUserId then
      tUserIdToClientId[nUserId]=nil
   end
end

local function _DestroyUserContact(nUserId)
   local sClientID =tUserIdToClientId[nUserId]
   tUserIdToClientId[nUserId]=nil
   if sClientID then
      tClientIdToUserId[sClientID] =nil
      return sClientID
   end
end

local function _GetUserID(sClientID)
   if sClientID then
      return tClientIdToUserId[sClientID]
   end
end
local function _GetClientID(nUserId)
   if nUserId then
      return tUserIdToClientId[nUserId]
   end
end

local function _GetAllClientID()
   local arrClientID = {}
   for nUserId, sClientID in pairs(tUserIdToClientId) do
       table.insert(arrClientID,sClientID)
   end
   return arrClientID
end


local obj ={}
obj.BuildContact =_BuildContact
obj.DestroyClientID =_DestroyContact
obj.GetUserIdByClientId =_GetUserID
obj.GetClientIdByUserId =_GetClientID
obj.DestroyUserContact =_DestroyUserContact
obj.GetAllClientID =_GetAllClientID
return obj