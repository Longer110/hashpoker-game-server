package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase 	= require("base")         -- 基础功能接口

--本服务器共享文件
SrvPub =
{
	--牌桌阶段
	enumStep = 
	{
		nNull 		= 0,  -- 不是游戏任何阶段
		nStartGame  = 1,  -- 开始游戏定时器
		nQiangZhuang = 2,  -- 抢庄
		nDingZhuang = 3,  -- 定庄
		nXiaZhu     = 4,  -- 下注
		nShouPai    = 5,  -- 手牌
		nFaPai      = 6,  -- 发牌
		nTanPaiReady = 7,  -- 摊牌准备
		nTanPai     = 8,  -- 摊牌
		nBiPai      = 9,  -- 比牌
		nJieSuan    = 10,  -- 结算
		nReset		= 11,  -- 游戏重置	 	
	},

	--玩家状态
	enumState = 
	{
		nSetUp     = 0,  --站起
		nSetDown   = 1, -- 坐下
		nPlay      = 2,  --正在玩
	},

	--玩家动作
	enumAction =
	{
		nNull	  	= 0, --玩家不需要操作，则动作为空

		nOverTime 	= 12,--操作超时
	}
}

-- 看牌抢庄步骤
SrvPub.KanPaiStep = {
		[1] = 2,  -- 抢庄
		[2] = 3,  -- 定庄
		[3]     = 4,  -- 下注
		[4]    = 5,  -- 手牌
		[5]      = 6,  -- 发牌
		[6] = 7,  -- 摊牌准备
		[7]     = 8,  -- 摊牌
		[8]    = 10,  -- 结算
		[9]		= 11,  -- 游戏重置	 	
}

--本服务器定时器id,最多定时器多少个
SrvPub.Timer = 
{
	--为了方便定时器传送参数，将定时器分段
	LoadTaskCheck     = 1103,  --检测任务配置  是否加载完成
	CheckTableBlock	  = 1104,  --检测桌子卡住
	LoadRoomCfg 	  = 10000, --加载房间配置
	LoadRoomCheck 	  = 10001, --检测房间配置是否加载完成
	CheckSngMatch	  = 10002, --检测sng比赛人数
	--
	CheckOuTime       = 30000, -- 检查牌桌超时
	--投票修改房间规则
	VoteCRule 		  = 40000, --投票修改房间规则

	--自动胡牌
	AutoHu 			  = 42000, --自动托管

	--牌桌超时解散
	OverLife 		  = 44000, --牌桌生命结束

	--投票解散
	VoteDissolution   = 46000, --投票解散

	--牌桌段定时器10001 -- 19999 牌桌1-9999牌桌id
	AndroidEnterTable = 48000, --机器人进入牌桌

	--牌桌阶段定时器 50001 -- 59999 牌桌1-9999牌桌id
	TableStep 		  = 50000, --牌桌阶段定时器
	AndroidAi         = 52000, -- 机器人ai操作定时器
	CurIndex          = 52000, -- 当前定时器的ID（机器人操作定时器）（52000 - 59999）
	AndroidAutoOpenTable = 60000, -- 机器人自动开桌
	PushXiaZhu       = 62000, -- 其他人的下注信息推送

}

--一些时间长度配置
SrvPub.SomeTimeLong =
{
	nSngUserCheckTime = 1 * 1000,	--sng检测周期
}



SrvPub.NiuNiuRoomTime =
{
	nAndroidPlay= 4 * 1000,  --机器人玩
	nStartGame = 0 * 1000,  -- 开始游戏定时器
	nQiangZhuang = 5 * 1000, -- 抢庄
	nDingZhuang = 1 * 1000,   --定庄
	nXiaZhu 	= 10 * 1000,   --下注
	nShouPai    = 0 * 1000,   -- 手牌
	nFaPai    	=  0 * 1000,   --发牌
	nPlay		= 18 * 1000,   --玩家打牌
	nTanPaiReady = 7 * 1000,   -- 摊牌准备
	nTanPai		= 1 * 1000,   --玩家摊牌
	nBiPai		= 500,    	  --比牌
	nJieSuan	= 3 * 1000,    --算分
	nReset		= 6 * 1000,    --游戏重置
}


-- 动作超时配置
SrvPub.ActionTime = {
	nXiaZhu 	= 10 * 1000,   --下注
	nTanPai		= 10 * 1000,   --玩家摊牌
}

--事件机制是相对于本服的
SrvPub.EMain = 65000
SrvPub.Event =
{
	USERLEAVE 		= 1,	  --玩家离开
	SETTABLELIEFE 	= 2,      --设置房间生命周期
	REMOVETABLE 	= 3,	  --删除牌桌
	PLAYALL			= 4,	  --牌桌已经玩完了
	EFFECTSTART		= 5,	  --牌桌开始检测
	XIAZHUFINISH    = 6,      -- 下注完成
	TANPAIREADYFINISH    = 7,      -- 摊牌完成
	ANDROIDEXIT     = 8,      -- 机器人退出牌桌
	QIANGZHUANGFINISH = 9,    -- 抢庄完成
	AIACTION = 10, --         -- AI动作
	USERSTATUSCHANGE = 11,     -- 用户状态改变
	STEP = 12,                  -- 牌桌步骤唤醒
}

SrvPub.TableCloseReason=
{
	nClubTableTimeOut=1,
    nGmClose =2,
    nNoRealUserTooLong=3,
    nBackstageClose=4,
    nTableError=5,
}

function SrvPub.PostInnerEvent(nEventId, tData)
	local nCnt = 0
	for _, _ in pairs(tData) do
		nCnt = nCnt + 1
	end

	local s = tBase.GetSP().new(SrvPub.EMain, nEventId)
	s:AddInt32(nCnt)
	for k, v in pairs(tData) do
		s:AddString(tostring(k))
		s:AddString(tostring(v))
	end
	tBase.PostToServer(tBase.m_tKey, 1, s:GetData(), s:GetSize())
end

function SrvPub.GetEventData(sData, nLen)
	local ReadData = base.GetRP().new(sData, nLen)
    local nMainId = ReadData:GetModuleID()
    local nSubId = ReadData:GetMsgID()

    local nCnt = ReadData:GetInt32()
    local tRet = {}
    for i=1, nCnt do 
    	local k = ReadData:GetString()
    	local v = ReadData:GetString()
    	tRet[k] = v
    end
    return tRet 
end

function SrvPub.SetTimer(nTimeID, nMil, nRepeact, func)
	--tBase.Log("设置时间 %d",nMil)
	--无限等待
	if nMil == 0xFFFF then
		return	
	end

	if nMil == 0 then
		func(nTimeID)
		return
	end

	tBase.SetTimer(nTimeID, nMil, nRepeact, func) 
end

--获得特定长度秘钥,秘钥有可能重复
function SrvPub.GetPrivateNumKey(nLen)
	if nLen <= 0 then
		return 0
	end
	
	return math.random(10^(nLen-1)+1, 10^nLen-1)
end

	--配置动作超时时间
function SrvPub.GetActionTime(nAction)
	if (nAction == SrvPub.enumStep.nXiaZhu) then
		return SrvPub.ActionTime.nXiaZhu
	elseif (nAction == SrvPub.enumStep.nTanPai) then
		return SrvPub.ActionTime.nTanPai
	else
		return 10;
	end
	
end

-- 获取可用的机器人AI操作定时器ID
function SrvPub.GetTimerID(nTimes)
	
	 local nGoodID = SrvPub.Timer.CurIndex
	 tBase.Log("ID:%d获取设置时长:%d",nGoodID,nTimes)
	
	 SrvPub.Timer.CurIndex =  SrvPub.Timer.CurIndex + 1
	 
	 if (SrvPub.Timer.CurIndex >= 60000) then
		SrvPub.Timer.CurIndex = SrvPub.Timer.AndroidAi
	 end

	 return nGoodID
end


-- 找到游戏对应阶段
function SrvPub.GetGameStep()
	
end


return SrvPub












