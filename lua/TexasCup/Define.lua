

local Define ={}

Define.nGameId_Normal=125                          --德州 正常玩法
Define.nGameId_Ahm=126                             --德州 奥哈马玩法
Define.nGameId_Sc =175                             --德州 短牌

--财产变动原因 (只能用个位数)
-- nSourceType =10000 +10*nGameId +nReason
Define.GoldCReason={
    nSettle =1,     --结算
    nFaceChat=7,    --表情聊天
    nOpDelay=8,     --延时操作
    nLookCard=9,    --看牌操作
    nTableTax =2,   --按桌抽水

    nSignUp =3,      --报名
    nSignUpCancel=4, --取消报名
    nMttCancel =5,   --比赛取消
    nAward=6,        --比赛奖励
}
--Define.GoldCReason.nMttCancel
return Define