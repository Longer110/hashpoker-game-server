
local PublicDefine ={}

--桌子状态 0:未开始 
PublicDefine.TableState ={
    nInit =0,           --未开始
    nPlaying =1,        --倒计时开始阶段
    nSettle=2,          --结算阶段
}

PublicDefine.UserStatus={
    nWaitForOp=0,   --0:等待操作权中
    nThinking=1,    --思考中
    nCall=2,        --跟注
    nPass=3,        --看牌
    nRaise=4,       --加注
    nAllIn=5,       --AllIn
    nFold=6,        --弃牌
    nLooker=7,      --旁观
}
PublicDefine.UserOp={
    nFold =-5,      --弃牌
    nAllIn =-1,     --AllIn
    nPass =-2,      --看牌(过牌)
    nRaise=-3,      --加注
    nRaiseBan=-4,   --加注(置灰)
    nCall =-6,      --跟注
    nBet =-7,      --下注
    -- -10:(1/2底池)  -11:(2/3底池) -12:(1个底池)  -13:(2个大盲) -14:(3个大盲)  -15:(4个大盲)
    nHalfPool =-10,         --(1/2底池)
    nTwoThirdsPool =-11,    --(2/3底池)
    nOnePool =-12,          --1个底池
    nTwoBlind=-13,          --2个大盲
    nThreeBlind=-14,        --3个大盲
    nFourBlind =-15,        --4个大盲
    nOneBlind =-16,        --1个大盲
}

PublicDefine.TableType ={
    nMatch =4,          --匹配房
}


PublicDefine.TakeInGoldType ={
    TopUp = 0,           -- 筹码充值
    TakeIn =1,          -- 筹码带入
}
--房间类型
PublicDefine.RoomType={
    nLobby=10,
    nClub =11,
    nMtt=12
}
PublicDefine.MsgCode={
    nKickByAdmin =21,       --被后台强制站起
    nKickByLive=20,         --被主播强制站起
    nKickToLobbyByAdmin=22, --被后台踢出牌桌(返回大厅)
    nKickBan=23, --封禁
    nInsurGold = 25, --余额不够买保险
    nPassErr = 26; --密码错误
}

--财产变动原因
PublicDefine.GoldCReason={
    nSettle =1,     --结算
    nFaceChat=7,    --表情聊天
    nOpDelay=8,     --延时操作
    nLookCard=9,    --看牌操作
    nTableTax =2,   --按桌抽水
    nHashCheck=10,   --牌局Hash检测
    nCall=11,        --跟注
    nRaise=12,       --加注
    nAllIn=13,       --AllIn
    nPreBet=14,      --前注
    nSmallBlind=15,  --小盲注
    nBigBlind=16,    --大盲注
    nZhuaTou=17,    --抓头注
    nPoolIn=18,    --底池收入
    nInsurBuy=19,   --购买保险花费
    nInsurWin=20,   --保险赔付
    nLookHands=21,   --看手牌
    nCutCard=22,   --切牌
    nTaxReturn=23, --抽水返还
    nTaxCost=24, --扣税
    nPenalty=25,   --处罚, 用户强制离开牌桌时的处罚
    nPenaltyRevenue=26,   --处罚收益, 用户强制离开牌桌时的处罚
    nSystemPenaltyRevenue=27,   --处罚时系统收益, 用户强制离开牌桌时的处罚
    nPenaltyCancel=28,   --处罚取消, 比如牌桌关闭,断线重连等
}

PublicDefine.HashMaxNum = 100


PublicDefine.LeaveTableType = {
    nNormal = 0,   -- 正常离开
    nOffLine = 1,  -- 断线
    nRetainCancel = 2,  -- 取消留座
    nStandUp = 3, -- 站起请求
    nToLobby = 4, -- 返回大厅
    nClean = 5, -- 结算清理,用户在座位中但是掉线了
    nCloseTable = 6, -- 关闭牌桌
    nKickTable = 7, -- 踢出牌桌  todo
    nForceStandUpBySystem = 8, -- 系统原因导致强制站起
    nLogonIn = 9, -- 登录时站起
    nForceStandUpByUser = 10, -- 玩家原因导致强制站起
}

PublicDefine.LeaveTablePenaltyType = {
    nToLobby = 0,   -- 返回大厅时罚款
    nStandUp = 1,  -- 站起时罚款
}

PublicDefine.DelayTimeWithLeaveTablePenalty = 180 -- 用户掉线后触发离桌处罚的延迟时间, 单位: 秒

PublicDefine.isTest =false
return PublicDefine