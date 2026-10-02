package.path = "../lua/public/?.lua;./lua/public/?.lua;" .. package.path

local tBase        = require("base")            -- 基础功能接口
local tName        = require("typename")     -- 类弄定义接口
local ProtoMgr     = require("ProtoManager")
local tJson        = require("cjson")

MagicFace = {}

MagicFace.EmFace = {
    Tomato = 1, -- 番茄
    Lips   = 2, -- 嘴唇
    WineGlass = 3, --酒杯
    Bomb   = 4,    --炸弹
    Chicken = 5,   -- 鸡
    Rose    = 6,   -- 玫瑰
}

 --需要的金币
MagicFace.EmNeedGold = {
    [MagicFace.EmFace.Tomato] = 0,
    [MagicFace.EmFace.Lips] = 0,
    [MagicFace.EmFace.WineGlass] = 0,
    [MagicFace.EmFace.Bomb] = 0,
    [MagicFace.EmFace.Chicken] = 0,
    [MagicFace.EmFace.Rose] = 0,
}
-- 构造一个魔法表情数组
function MagicFace.MakeMagicFaceMsg()
    local  tMsg = {}
    for k, v in pairs(MagicFace.EmFace) do
        local  temp = {}
        temp.MagicFace = v
        temp.NeedGold = MagicFace.EmNeedGold[v]
        table.insert(tMsg, temp)
    end

    return tMsg
end

--获取一个表情需要的金币
function MagicFace.GetNeedGoldByFace(nMagicFace)
     return MagicFace.EmNeedGold[nMagicFace] or 0
end

--构造一个下发用户表情数据
function  MagicFace.REP_UserData(sClientID,nMainID,nSubID,tUserData)
    local REP_User_Msg = ProtoMgr.MagicFace_pb.REP_User_Msg()
    REP_User_Msg.UserID = tUserData.nUserID
    REP_User_Msg.Sex = tUserData.nSex
    REP_User_Msg.Name = tUserData.sNickName
    REP_User_Msg.Gold = tUserData.nGold
    REP_User_Msg.Sid = tUserData.nSidID

    local tMagicFace = MagicFace.MakeMagicFaceMsg()

    for k ,v in pairs(tMagicFace) do
        local tMagicFaceArr =  REP_User_Msg.tMagicFaceArr:add()
        tMagicFaceArr.MagicFace = v.MagicFace
        tMagicFaceArr.NeedGold = v.NeedGold
    end

    local s = tBase.GetSP().new(nMainID,nSubID)
    s:AddString(REP_User_Msg:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end 

-- 成功使用魔法表情
function MagicFace.REP_USE_FACE(sClientID,nMainID,nSubID,nResult)
    local REP_User_Face = ProtoMgr.MagicFace_pb.REP_User_Face()
    REP_User_Face.Result = nResult
    local s = tBase.GetSP().new(nMainID,nSubID)
    s:AddString(REP_User_Face:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end
--广播成功使用魔法表情
function MagicFace.REP_Use_Face(sClientID,nMainID,nSubID,tUserData)
    local REP_User_Face_All = ProtoMgr.MagicFace_pb.REP_User_Face_All()
    REP_User_Face_All.Sid = tUserData.Sid
    REP_User_Face_All.SidTarget = tUserData.SidTarget
    REP_User_Face_All.MagicFace = tUserData.MagicFace

    local s = tBase.GetSP().new(nMainID,nSubID)
    s:AddString(REP_User_Face_All:SerializeToString())
    tBase.PostToClient(sClientID,s:GetData(),s:GetSize())
end

return MagicFace