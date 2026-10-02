package.path = require("./lua/Game/ClubQiangZhuangNiu/Head").path

local tBase = require("base")           -- 基础功能接口
local mlogger = require("logger") -- 日志对象 
local tJson = require("cjson")


-- 智能操作
UserAi = {}

-- Ai 定时器
function UserAi.UserActionAiTimes(nMSeconds,fFunc,...)
	local nTimerId = SrvPub.GetTimerID(nMSeconds)
	local arrP =table.pack(...)
	local temF =function()
		fFunc(table.unpack(arrP))
		mlogger:info(string.format( "准备启动定时器%d", nTimerId ))       	
	end
	tBase.SetTimer(nTimerId, nMSeconds, 1, temF)
end

--调用这个函数 
-- tTable 牌桌对象
--nMinTimes 随机操作的开始时间
--nMaxTimes 随机操作的结束时间
function UserAi.UserAction(tTable,nMinTimes,nMaxTimes)
    --if true then return end
    if tTable == nil then
        return 
    end

    local tUserArr = tTable:GetAndroidPlayArr()
    if (#tUserArr <=0) then
        mlogger:info("无机器人")
        return 
    end
    mlogger:info(string.format( "%s=>机器人用户数组：%d",tTable.sTableId,#tUserArr ))
    local  tUserTimeArr  = {}

    for k, nUserID in pairs(tUserArr) do
        local tTemp = {}
        tTemp.nUserID = nUserID
        tTemp.nMSeconds = math.random(nMinTimes + 1000,nMaxTimes )
        table.insert(tUserTimeArr,tTemp )
    end

    --排序执行时间（升序）
    local nMix 
    for i = 1, #tUserTimeArr do
        nMix = i
        for j = i + 1, #tUserTimeArr do
           
            if tUserTimeArr[i].nMSeconds > tUserTimeArr[j].nMSeconds then
                nMix = j
                local  tTemp = {}
                tTemp = tUserTimeArr[j]
                tUserTimeArr[j] =  tUserTimeArr[i]
                tUserTimeArr[i] = tTemp
            end
        end
    end
    --启用定时器执行（多用户并发操作共用一个定时器ID）
    UserAi.UserActionAiTime2(tUserTimeArr,0,tTable)
end

--Ai定时器优化版{ID优化}（多用户操作共用一个定时器ID）
function UserAi.UserActionAiTime2(tUserTime,nIndex,tTable,...)

    if #tUserTime == 0 then
        mlogger:error("执行的定时器数组为 0")
        return 
    end

    if nIndex == 0 then -- 第一次进来不执行
        mlogger:info(string.format( "%s=>第一次执行",tTable.sTableId))
    else
        --每次执行动作重新算时间
        local UserTime = tUserTime[nIndex]
        for  i = nIndex + 1,  #tUserTime do
            tUserTime[i].nMSeconds =  tUserTime[i].nMSeconds - UserTime.nMSeconds
        end

        UserAi.AiAction(tUserTime[nIndex].nUserID, tTable)
    end

    if #tUserTime == nIndex then
        mlogger:info(string.format( "%s=>定时器执行完毕",tTable.sTableId))
        return 
    end

    nIndex = nIndex + 1
    local UserTime = tUserTime[nIndex]
    local nTimerId = tTable.nTableId + SrvPub.Timer.AndroidAi
    local arrP = table.pack(...)
    local temF = function()
        UserAi.UserActionAiTime2(tUserTime,nIndex,tTable,table.unpack(arrP))
        mlogger:info(string.format( "%s=>准备启动定时器%d",tTable.sTableId,nTimerId))  	
     end
   
     tBase.SetTimer(nTimerId, UserTime.nMSeconds, 1, temF)
   
end
-- AI 智能动作
function UserAi.AiAction(nUserID,tTable)
    mlogger:info("AiAction 成功")
    if tTable == nil then
        mlogger:error("AiAction 失败table为空")
        return
    end

    if tTable.nStep == SrvPub.enumStep.nXiaZhu then
        UserAi.AutoXiaZhu(nUserID,tTable)
    elseif tTable.nStep == SrvPub.enumStep.nQiangZhuang then
        UserAi.AutoQiangZhuang(nUserID,tTable)
    elseif tTable.nStep == SrvPub.enumStep.nTanPaiReady then
        UserAi.AutoReady(nUserID,tTable)
    end
    
end
--智能下注
function UserAi.AutoXiaZhu(nUserID,tTable)
    mlogger:info("AutoXiaZhu")
  
    if nUserID == tTable.nZhuangUserID then
        return
    end
    if tTable.nGameType == GConfig.GameType.KanPaiNiuNiu then
        local nIndex = math.random(1,#tTable.tXiaZhuCfg)
        local nVal = tTable.tXiaZhuCfg[nIndex] or 1
        -- tTable:UserXiaZhu(nUserID,nVal)

        local tShouHand = tTable.tUserHandPaiArr[nUserID]
        if tShouHand ~= nil then
            local PaiShu = NiuNiuMath.NumberToCount2(tShouHand)

            local nNiuWhat = NiuNiuMath.GetNiuCard(PaiShu)
            mlogger:info(string.format( "%s=>机器人: %d  牌数 :%s 牛数：%s",tTable.sTableId,nUserID, tJson.encode(PaiShu), tJson.encode(nNiuWhat) ))
            if nNiuWhat.NiuWhat > 0 then -- 有牛
                local nRand = math.random(1,100)
                if nRand > 20 then -- 80%下大注注
                    local nIndex = math.random(3,#tTable.tXiaZhuCfg)
                    local nVal = tTable.tXiaZhuCfg[nIndex] or 5
                    tTable:UserXiaZhu(nUserID,nVal)
                else 
                    local nIndex = math.random(1,#tTable.tXiaZhuCfg)
                    local nVal = tTable.tXiaZhuCfg[nIndex] or 5
                    tTable:UserXiaZhu(nUserID,nVal)
                end
            else    --无牛
                local nRand = math.random(1,100)
                if nRand > 20 then -- 80%下小注
                    local nIndex = math.random(1,2)
                    local nVal = tTable.tXiaZhuCfg[nIndex] or 5
                    tTable:UserXiaZhu(nUserID,nVal)
                else 
                    local nIndex = math.random(1,#tTable.tXiaZhuCfg)
                    local nVal = tTable.tXiaZhuCfg[nIndex] or 5
                    tTable:UserXiaZhu(nUserID,nVal)
                end
            end
        else
            --nIndex = math.random(1,#tTable.tXiaZhuCfg)
            --nVal = tTable.tXiaZhuCfg[nIndex] or 1
            tTable:UserXiaZhu(nUserID,nVal)
        end
    else
        local nIndex = math.random(1,#tTable.tXiaZhuCfg)
        local nVal = tTable.tXiaZhuCfg[nIndex] or 5
        tTable:UserXiaZhu(nUserID,nVal)
    end
 
end

--智能抢庄
function UserAi.AutoQiangZhuang(nUserID,tTable)
    mlogger:info(string.format( "%s=>AutoQiangZhuang",tTable.sTableId))  	
    if tTable.nGameType == GConfig.GameType.KanPaiNiuNiu then

        local tShouHand = tTable.tUserHandPaiArr[nUserID]
        if tShouHand ~= nil then
            local PaiShu = NiuNiuMath.NumberToCount2(tShouHand)

            local nNiuWhat = NiuNiuMath.GetNiuCard(PaiShu)
            mlogger:info(string.format( "%s=>机器人: %d  牌数 :%s 牛数：%s",tTable.sTableId,nUserID, tJson.encode(PaiShu), tJson.encode(nNiuWhat) ))
            if nNiuWhat.NiuWhat > 0 then -- 有牛
               
                if tTable:IsNeedControl() then -- 控牌要必定3倍抢庄
                    mlogger:info("控牌抢庄")
                    if tTable:GetAndroidQiangZhuang() == false then
                        tTable:QiangZhuang(nUserID, tTable.tQiangZhuangCfg[#tTable.tQiangZhuangCfg])
                    else
                        local nIndex = math.random(1,#tTable.tQiangZhuangCfg)
                        local nVal = tTable.tQiangZhuangCfg[nIndex] or 0
                        tTable:QiangZhuang(nUserID,nVal)
                    end                   
                else
                    local nRand = math.random(1,100)
                    if nRand > 10 then -- 90%会抢庄
                        mlogger:info("机器人抢庄")
                        local nIndex = math.random(1,#tTable.tQiangZhuangCfg)
                        local nVal = tTable.tQiangZhuangCfg[nIndex] or 0
                        tTable:QiangZhuang(nUserID,nVal)
                   
                    else
                        tTable:QiangZhuang(nUserID,0)
                    end
                   
                end        
            else    --无牛
                local nRand = math.random(1,100)
                if nRand > 80 then -- 20%会抢庄
                    local nVal = tTable.tQiangZhuangCfg[1] 
                    tTable:QiangZhuang(nUserID,nVal)
                else
                    tTable:QiangZhuang(nUserID,0)
                end
            end
        else
            local nRand = math.random(1,100)
            if nRand > 50 then -- 50%会抢庄
                local nVal = tTable.tQiangZhuangCfg[2] 
                tTable:QiangZhuang(nUserID,nVal)
            else
                tTable:QiangZhuang(nUserID,0)
            end
        end
     
    end
 
end

--智能抢庄(看牌抢庄牛牛)
function UserAi.AutoQiangZhuang2(nUserID,tTable)
    mlogger:info(string.format( "%s=>AutoQiangZhuang2",tTable.sTableId))  	
   local nIndex = math.random(1,#tTable.tQiangZhuangCfg)
   local nVal = tTable.tQiangZhuangCfg[nIndex] or 0
   tTable:QiangZhuang(nUserID,nVal)
end

-- 智能开牌
function UserAi.AutoReady(nUserID,tTable)
    mlogger:info(string.format( "%s=>AutoReady",tTable.sTableId))  	
    tTable:UserTanPaiReady(nUserID,true)
end

return  UserAi