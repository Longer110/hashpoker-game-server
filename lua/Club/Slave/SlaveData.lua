--俱乐部从服公用数据缓存
local SlaveData = {}

SlaveData.tTimerId = {} --从服定时任务的定时器id集合
SlaveData.arrGroup = {} --分组id数组

SlaveData.arrChangeNameConsume = {} --修改昵称消耗
SlaveData.arrOpenTableConsume = {} --开桌消耗
SlaveData.arrFreeCnt = {} --修改昵称免费次数
SlaveData.arrLevelConfig = {} --等级配置

SlaveData.globalConfig = {} --全局配置数据

function SlaveData.GetConfig(name)
    return SlaveData.globalConfig[name]
end

-- 获取消耗配置
function SlaveData.GetConfigCost(name, name2)
    local conf = SlaveData.globalConfig[name]
    if not conf then
        return -1
    end
    local cost = conf[name2] or "0"
    return tonumber(cost) or 0
end

SlaveData.nReqWebCount = 0 --请求web的次数

SlaveData.tDBOprateWaitting = {  --DB服操作等待队列
    arrLogin = {}, --登录
    arrCreateClub = {}, --创建俱乐部
    arrChangeClubInfo = {}, --修改俱乐部信息
    arrAdminOprate = {}, --管理员操作
    arrBlackListOp = {}, --黑名单操作
    arrAdminMgr = {}, --俱乐部增加删除管理员
    arrChangeAdminPower = {},--修改管理员权限
    arrApplyDeal = {}, --管理员处理申请
    arrPaiPuOprate = {}, --牌谱操作
    arrUserNoticeOprate = {}, --处理个人通知
    arrUserApplyOprate = {}, --撤回个人申请
    arrChangeUserInfo = {}, --修改个人资料
    arrChangePassWard = {}, --修改登录密码
    arrInputRedeemCode = {}, --输入兑换码
}

SlaveData.isInitFinish = false --开服是否初始化完成

return SlaveData