--[[
	一些供有变量，宏的定义，错误码定义，不能写任何逻辑代码，不要包含其他头文件
-- ]]

PubDefine = {}
 
PubDefine.enumGame =
{
	nUserCantLeave = 1,
	nUserCanLeave  = 2,	
}

PubDefine.enumRoomType =
{
	nExpRoom 	= 0,    --体验场
	nPriRoom 	= 1,    --私人房
	nCoinRoom 	= 2,    --金币场
	nMatchRoom	= 3, 	--比赛场
	nExampleRoom= 4, 	--新版服务器(这个项目暂时不用)
}

PubDefine.SomeDefine =
{
	nOpenOnce 		  = 4,		--比赛坐满立即开
	
	nFinals 		  = 1,		--决赛 
	nSemifinal 		  = 2, 		--半决赛
	nPreliminary 	  = 3,		--初赛
	nHitFinals		  = 4,		--打立出局赛

	nMatchCfgPageSize = 10,		--比赛配置页大小
}

--私人房计时方式 
PubDefine.ConsumeType=
{
	nByHours=1,			--按小时计算房卡消耗
	nByQuan=2,			--按圈数计算房卡消耗
}

PubDefine.RoomCardNeed={
	nPerHour=16,		--每小时需要16张房卡
	nPerQuan=4,			--每圈需要4张房卡
	nPerRound=1,		--每局需要1张房卡
}


--Game目录中GConfig.lua也有这个定义 ，没统一起来,所以不要改
PubDefine.GameType={
	nPuLin			= 6,		--普宁
}

PubDefine.ChangeGoldReason = {
	BuDan = 100001,
	BackTurn = 100003,
	BackApi = 100002,
	AdminDelGold = 100004,
	AdminAddGold = 100005,
	TransferGold = 100006,
	TransferGetGold = 100007,
	TransferGoldBack = 100008,
	HashCheck = 100009,
	RobotGold = 88,
	ClubKicked = 33001,
	ClubOut = 33002,
	ClubAdminAddAward = 33003,
	ClubAdminDel = 33004,
	ClubRequestAward = 33005,
	ClubReturnCost = 33006,
	DuiHuanAward = 200001,
	BiaoQingCost = 99,
	RechartUMoney = 100010,
	WithdrawUMoney = 100011,
}

PubDefine.ChangeGoldReasonStr = {
    [100001] = "补单记录",
    [100003] = "后台转账",
    [100002] = "API转账",
	[100004] = "人工扣除金币",
	[100005] = "人工增加金币",
	[100006] = "内转消耗",
	[100007] = "收到玩家转账",
	[100008] = "内转退回",
	[100009] = "哈希验证",
    [1001] = "银行余额存入",
    [1002] = "银行余额取出",
    [88] = "机器人加余额",
    [33001] = "俱乐部被踢",
    [33002] = "俱乐部主动退出",
    [33003] = "俱乐部管理员增加",
    [33004] = "俱乐部管理员回收",
    [33005] = "俱乐部主动申请",
    [33006] = "俱乐部主动退还",
	[33007] = "修改昵称",
	[33008] = "开桌消耗",
	[33009] = "看公牌",
	[33010] = "看手牌",
    [200001] = "兑换码奖励",
    [99] = "魔法表情消耗",
    [10091] = "首冲奖励",
    [10092] = "推荐奖励",
    [10093] = "签到奖励",
    [10094] = "分享奖励",
    [10095] = "活动奖励",
}


return PubDefine
