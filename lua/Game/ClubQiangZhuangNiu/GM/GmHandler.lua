package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase      = require("base")         -- 基础功能接口
local tUserMgr   = require("UserManager")
local tTableMgr  = require("TableManage")

local tGmTable   = require("GmTable")
GmHandler = {}



function GmHandler.GmWantCard(sClientID, arr, tOther)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    if tUser == nil then return end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable == nil then return end

    local arrNum = {}
    for i = 1, #arr do
        if tonumber(arr[i]) == nil then return end
        table.insert(arrNum, tonumber(arr[i]))
    end

    tTable.tGmPai.tWaitCard.isGm = true
    table.insert(tTable.tGmPai.tWaitCard[tUser.nSitId], arrNum[1])
end
 -- 初始化手牌
function GmHandler.GmInitHand(sClientID, arr, tOther)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    if tUser == nil then return end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable == nil then return end

    local arrNum = {}
    for i = 1, #arr do
        if tonumber(arr[i]) == nil then return end
        table.insert(arrNum, tonumber(arr[i]))
    end

    local nSitId = arrNum[1]
    table.remove(arrNum, 1)
    tBase.Log("GmInitHand")
    
    tTable.tGm.tHandCard[nSitId] = arrNum

end

function GmHandler.GmChangeTimer(sClientID, arr, tOther)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    if tUser == nil then return end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable == nil then return end
    if #arr ~= 2 then return end

    tTable.tGmTable.arrRoomTime[arr[1]] = tonumber(arr[2])
    tTable.tGmTable:AddGm(tUser.nUserId, tOther.val, tOther.val)
end

function GmHandler.GmOpenGmTable(sClientID, tOther)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    if tUser == nil then return end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable == nil then return end

    tTable.tGmPai.tPaiDui.isGm = true
    tTable.tGmPai.tHandCard.isGm = true
    tTable.tGmPai.tNai.isGm = true
end

function GmHandler.GmCloseGmTable(sClientID, tOther)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    if tUser == nil then return end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable == nil then return end

    tTable.tGmPai.tPaiDui.isGm = false
    tTable.tGmPai.tHandCard.isGm = false
    tTable.tGmPai.tNai.isGm = false
end

function GmHandler.GmClearGmTable(sClientID, tOther)
    local tUser = tUserMgr.GetUserInfoByLink(sClientID)
    if tUser == nil then return end
    local tTable = tTableMgr.GetTable(tUser.nTableId)
    if tTable == nil then return end

    tTable.tGmPai.tPaiDui.isGm = false
    tTable.tGmPai.tPaiDui.arrCard = {}

    tTable.tGmPai.tHandCard.isGm = false
    for i = 1, 4 do
        tTable.tGmPai.tHandCard[i] = {}
    end

   tTable.tGmPai.tNai.isGm = false
   tTable.tGmPai.tNai.nId = 0 
end


return GmHandler

