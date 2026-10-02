
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
    -- -10:(1/2底池)  -11:(2/3底池) -12:(1个底池)  -13:(2个大盲) -14:(3个大盲)  -15:(4个大盲)
    nHalfPool =-10,         --(1/2底池)
    nTwoThirdsPool =-11,    --(2/3底池)
    nOnePool =-12,          --1个底池
    nTwoBlind=-13,          --2个大盲
    nThreeBlind=-14,        --3个大盲
    nFourBlind =-15,        --4个大盲
}

PublicDefine.TableType ={
    nCompete=3,         --比赛房
    nMatch =4,          --匹配房
}

function PublicDefine.CheckRoomConfig(tRoomConfig)
    if not tRoomConfig then
       return nil,"tRoomConfig is nil"
    end
    if tRoomConfig.nAnte <=0 or tRoomConfig.nEnterFloorLimit< (tRoomConfig.nAnte*2) then
       return nil,"config error"
    end
    local tRlt={}
    tRlt.nSmallBlind = tRoomConfig.nAnte            --小盲
    tRlt.nBigBlind =tRoomConfig.nAnte *2            --大盲
    tRlt.nBuyMin =tRoomConfig.nEnterFloorLimit      --最小买入
    tRlt.nBuyMax =tRoomConfig.nEnterFloorLimit *20  --最大买入
    tRlt.nTax = (tRoomConfig.nTax/10)               --抽水(数据库配置为千分比，游戏里用百分比，所以除以10)
    return tRlt,"succee"
 end


return PublicDefine