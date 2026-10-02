
package.path = "../lua/base/?.lua;./lua/base/?.lua;" .. package.path
local tBase     = require("base")
local tName     = require("typename")
local tPubHelper = require("PubHelper")
local api = require("publicApi")    -- 共用功能接口



TreasureDbr = {}

TreasureDbr.enumTre = 
{
    nRoomCard = 1,
    nDiamond = 2,
    nGold = 3,
    nQuanyuCoin = 4,
    nSunPrice = 5,
}

-- 请求或主动 玩家财富数据：  tData : UserID, ClientID 
function TreasureDbr.GetTreasureData(tData)
    tBase.Log(" 玩家数据      玩家财富数据     GetTreasureData  ")  
    local sSql = "Call User_Get_Treasure("..tData.nUserID..")"
    -- local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_REQ_READTREASURE)
    -- s:AddString(tData.nClientID)   
    -- s:AddInt32(tData.nUserID)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, tData.nUserID, s:GetData(), s:GetSize())
    tBase.Log(" 玩家数据   请求  SQL   玩家财富数据     成功  ")  
    return
end

-- 下发 玩家财富数据
function TreasureDbr.SendUserTreasureData(sReturnKey, sData, nLen)
  local ReadData = tBase.GetRP().new(sData, nLen)
  local MainID = ReadData:GetModuleID() 
  local SubID = ReadData:GetMsgID()
  local sClientID = ReadData:GetString()  
  local tTreasure = {}

  local nUserID   = ReadData:GetInt32()  
  local nRoomCard = ReadData:GetInt32()   
  local nDiamond  = ReadData:GetInt32()  
  local nGold     = ReadData:GetInt32()   
  local nQuanyuCoin = ReadData:GetInt32()  
  local nSunPrice = ReadData:GetInt32()
  
  -- local tClient = tBase.GetSP().new(tPubProto.MAIN.SYSLOBBY, tPubProto.SubLobby.SUB_REP_ACC_TREASURE) 
  --  tClient:AddInt32(nRoomCard)    --房卡  
  -- tClient:AddInt32(nDiamond)     --钻石
  -- tClient:AddInt32(nGold)        --金币
  -- tClient:AddInt32(nQuanyuCoin)  --全娱币
  -- tClient:AddInt32(nSunPrice)    --阳光值
  -- tBase.PostToGateway(sClientID, tClient:GetData(), tClient:GetSize())
  tBase.Log(" 返回财富数据成功    nUserID:   %d ,nRoomCard:   %d , nDiamond:   %d ,nGold:   %d ,nQuanyuCoin:   %d ,nSunPrice:   %d    ",
  nUserID, nRoomCard,nDiamond, nGold,nQuanyuCoin,nSunPrice) 
  return 
end

-- 修改玩家财富数据
function TreasureDbr.WriteTreasure(tData)
    local nClientId = nil
    if tPubHelper.tLocation then
        nClientId = tPubHelper.tLocation.GetClientId(tData.nUserId)
    end
    if nClientId == nil then 
         nClientId = TreasureDbr.GetClientID_String(tData.nUserId)
    end 
    -- local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_REQ_WRITETREASURE)
    -- s:AddInt32(tData.nUserId)
    -- s:AddInt32(tData.nItemID)
    -- s:AddInt32(tData.nDel)
    -- s:AddString("Call WriteUserTreasure("..tData.nUserId..","..tData.nItemID..","..tData.nDel..","..tData.nSourceType..")")  
    -- tBase.PostDatasByType(tName.db, nClientId, tData.nUserId, s:GetData(), s:GetSize())
    tBase.Log(" 我在写入财富")
end

function TreasureDbr.GetClientID_String(nUserId)
  if tBase.m_MyRedisData[1].redis == nil then
    tBase.Log(" Error_Info==210  ")  
    return
  end
  local sKey = "PublicUserInfo_"..nUserId
  local t = tBase.m_MyRedisData[1].redis:hgetall(sKey)
  local  nClientId =  api.SClientIdtoNumber(t["sClientID"] )
  return nClientId
end

-- 修改玩家道具数据
function TreasureDbr.UpdateUserItemData(tData)
    tBase.Log(" 修改玩家道具数据   UpdateUserItemData   ")

    -- local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_REQ_UPDATE_ITEM)    
 
    -- local sSql = "Call User_Write_Item("..tData.nUserID..","..tData.nItemID..","..tData.nCount..","..tData.nItemType..",'"..tData.sInDate.."',"..tData.nSourceType..")" 
  
    -- tBase.Log(" 修改玩家道具数据   sSql   "..sSql)
    -- s:AddInt32(tData.nUserID)
    -- s:AddString(sSql)
    -- tBase.PostDatasByType(tName.db, 0, tData.nUserID, s:GetData(), s:GetSize())

    tBase.Log(" 修改玩家道具数据   发送DB    成功！ ")
end


function TreasureDbr.WriteScoreLocker(tData)

    local nClientId = nil
    if tPubHelper.tLocation then
        nClientId = tPubHelper.tLocation.GetClientId(tData.nUserId)
    end

    if tData.nServerId == nil then
        tBase.Log(" Error_Info==211   ")  
        return
    end

    -- local s = tBase.GetSP().new(tPubProto.Sys.SYS_DB, tPubProto.SUB_DB.SUB_REQ_WRITESCORELOCK)
    -- s:AddString("Call SetGameScoreLocker("..tData.nUserId..","..tData.nServerId..")")
    -- tBase.PostDatasByType(tName.db, nClientId, tData.nUserId, s:GetData(), s:GetSize())
end

return TreasureDbr


