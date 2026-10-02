--机器人昵称管理
local tALog = require("AndroidLog")
local tPublicApi = require("publicApi")
local cjson     = require("cjson")        -- json
local tPublicRedis = require("PublicRedis")
local ProtoManager = require("ProtoManager")
local Define = require("Define")
local tBase = require("base")
local tTypeName = require("typename")
local Quick = require("Quick")
local tSrvInfo = require("ServerInfo")
local tAndroidData = require("AndroidData")

local NameLibMgr = {
    isInitFinish = false, --是否初始化完成
    tGrpCfg = {}, --分组昵称配置
    nCheckCnt = 0, --检查的次数
    nRequetCnt = 0,  --无机器人请求次数超过 100次就加载机器人昵称
}

--加载多语言
function NameLibMgr.Init()
    NameLibMgr.isInitFinish = false
    NameLibMgr.CreateGrpCfg()
end

--创建语言
function NameLibMgr.CreateLanguage(nLanguageId)
    local t = {}
    t.nLanguageId = nLanguageId --语言种类
    t.isFirLoadFinish = false --首次加载结束
    t.nLoadFlag = false --加载结束
    t.nMax = 5000--未使用的昵称缓存个数
    t.arrAnNameList = {}--昵称数据
    t.nUseCursorId = 0 --使用到的游标
    t.nCursorId = 0 --缓存的昵称库游标(最大值)
    return t
end

--创建分组
function NameLibMgr.CreateGrpCfg()
    function _CallBack(...)
        local args = {...}
        local tPack = args[#args]
        local sErrStr = ""
        local nCnt = #tPack
        for k, v in pairs(tPack) do
            local nGrpId = tonumber(v["GrpId"])
            local sFirstName = v["FirstName"]
            local sProportion = v["Proportion"]
            local nRealRate = tonumber(v["RealRate"])
            local sGamePro = v["GamePro"] or ""
            if not NameLibMgr.tGrpCfg[nGrpId] then
                NameLibMgr.tGrpCfg[nGrpId] = {
                    nGrpId = nGrpId,
                    sFirstName = sFirstName,
                    arrLanguage = {}, --不同语言机器人比例
                    nRealRate = nRealRate or 1,----昵称机器人占用机器人总数百分率
                    tAnNameList = {}, --各个语言包的昵称
                    sProportion = sProportion or "",
                    sGamePro = sGamePro,
                    tGamePro = {}, --各游戏所用的机器人类型（1.合集机器人 2.app机器人）
                }
                local sErr = NameLibMgr.InitGrp(nGrpId, sProportion, sGamePro)
                sErrStr = sErrStr..sErr
                NameLibMgr.InitDBAndroidDetail(nGrpId)
                tALog.Print("_CreateGrpCfg  生成组管理 GrpId_%d Proportion_%s sGamePro_%s", nGrpId, sProportion, sGamePro)
            elseif NameLibMgr.tGrpCfg[nGrpId].sProportion~=sProportion or NameLibMgr.tGrpCfg[nGrpId].sFirstName~=sFirstName or
                NameLibMgr.tGrpCfg[nGrpId].sGamePro ~= sGamePro then
                NameLibMgr.tGrpCfg[nGrpId].arrLanguage = {}
                NameLibMgr.tGrpCfg[nGrpId].nRealRate = nRealRate or 1
                NameLibMgr.tGrpCfg[nGrpId].tAnNameList = {}
                NameLibMgr.tGrpCfg[nGrpId].sFirstName = sFirstName
                NameLibMgr.tGrpCfg[nGrpId].sProportion = sProportion
                NameLibMgr.tGrpCfg[nGrpId].sGamePro = sGamePro
                NameLibMgr.tGrpCfg[nGrpId].tGamePro = {}
                local sErr = NameLibMgr.InitGrp(nGrpId, sProportion, sGamePro)
                sErrStr = sErrStr..sErr
                tALog.Print("_CreateGrpCfg  刷新组管理 GrpId_%d Proportion_%s sGamePro_%s", nGrpId, sProportion, sGamePro) 
            end
        end
        if sErrStr~="" then
            sErrStr = "数据库DJH_ReCordDB表GrpAnProportion,"..sErrStr
            tALog.SendMsgToTG(sErrStr,nil,1) 
        end
        NameLibMgr.isInitFinish = true

        NameLibMgr.CheckLanguageEnough()
    end
    local sSql = string.format("SELECT * FROM GrpAnProportion;")
    tALog.Print("_CreateGrpCfg]sql sSql:  %s", sSql)
    local tInfo2 = {["sMsgM"]="ANDROID", ["sMsgS"]="REQ_GRP_ANDROIDPROP", sSql=sSql}
    Quick.ExcuteSql(tInfo2, _CallBack)
end

--初始化分组
function NameLibMgr.InitGrp(nGrpId, sProportion, sGamePro)
    local sErrStr = ""
    local arrLanguage = NameLibMgr.GetLanguageByDBCfg(sProportion)
    NameLibMgr.tGrpCfg[nGrpId].arrLanguage = arrLanguage
    if #arrLanguage == 0 then
        local sErr = string.format("_InitGrp  数据库DJH_ReCordDB表GrpAnProportion,分组%d的Proportion配置不对,Proportion:%s",
        nGrpId,sProportion or "")
        tALog.Print(sErr)
        sErrStr = sErrStr .. string.format("Proportion:%s配置不对. ",sProportion or "")
    end
    local hasAPPLanguage = false
    local hasHjLanguage = false
    for _,v in pairs(arrLanguage) do
        NameLibMgr.tGrpCfg[nGrpId].tAnNameList[v.nLanguageId] = NameLibMgr.CreateLanguage(v.nLanguageId)
        local nCursorId = tPublicRedis.GetUseAnNickCursor(nGrpId,v.nLanguageId)
        NameLibMgr.tGrpCfg[nGrpId].tAnNameList[v.nLanguageId].nCursorId = nCursorId
        tALog.Print("_InitGrp  分组_%d  生成语言包nLanguage_%d  nCursorId_%d ",nGrpId,v.nLanguageId,nCursorId)
        if v.nLanguageId==1 or v.nLanguageId==2 or v.nLanguageId==3 or v.nLanguageId==99 then
            hasHjLanguage = true
        elseif v.nLanguageId == 4 or v.nLanguageId==5 then --todo
            hasAPPLanguage = true
        end
    end
    if not hasAPPLanguage then
        local str = string.format("分组%d没有配置app的语言id,请确认是否所有游戏都不需要app机器人",nGrpId)
        tALog.Print(str)
        sErrStr = sErrStr .. string.format("没有配置app机器人的语言id. ")
    end
    if not hasHjLanguage then
        local str = string.format("分组%d没有配置合集的语言id,请确认是否所有游戏都不需要合集机器人",nGrpId)
        tALog.Print(str)
        sErrStr = sErrStr .. string.format("没有配置合集机器人的语言id. ")
    end
    if sGamePro=="" then
        local str = string.format("数据库GrpAnProportion表分组%d没有字段GamePro或者字段GamePro为'',请确认是否所有游戏都不需要app机器人",nGrpId)
        tALog.Print(str)
        sErrStr = sErrStr .. string.format("GamePro:%s配置不对. ",sGamePro)
    end
    NameLibMgr.tGrpCfg[nGrpId].tGamePro = NameLibMgr.GetGameProDBCfg(sGamePro)
    if sErrStr~="" then
        sErrStr = string.format("分组%d:",nGrpId)..sErrStr
    end
    return sErrStr
end

--获取语言比例数组
function NameLibMgr.GetLanguageByDBCfg(sProportion)
    sProportion = sProportion or ""
    local arrLanguage = {}
    local arrL = tPublicApi.Split(sProportion, ':')
    local nTatalRate = 0
    for _, v in pairs(arrL) do
        local arrLA = tPublicApi.Split(v, '#')          
        local nCnt = tonumber(arrLA[2]);
        local nLanguageId = tonumber(arrLA[1])
        if type(nCnt)=="number" and type(nLanguageId)=="number" then
            nTatalRate = nTatalRate+nCnt
            table.insert(arrLanguage,{nLanguageId=nLanguageId,nRate=nCnt})
        end
    end
    if nTatalRate<=0 then
        local sErr = string.format("_GetLanguageByDBCfg  所有语言比列之和小于等于0，后台配置出错,sProportion:%s",sProportion)
        tALog.Print(sErr)
        tALog.SendMsgToTG(sErr,sErr,1)
    end
    return arrLanguage
end

--获取各游戏所用的机器人类型
function NameLibMgr.GetGameProDBCfg(sGamePro)
    sGamePro = sGamePro or ""
    local tGamePro = {}
    local arr = tPublicApi.Split(sGamePro, ',')
    if #arr>0 then
        for k,v in pairs(arr) do
            local arr1 = tPublicApi.Split(v, '#')
            if #arr1 == 2  then
                local nGameId = tonumber(arr1[1] or "0") or 0
                local nAnCfgId = tonumber(arr1[2] or "1") or 1
                tGamePro[nGameId] = nAnCfgId
            elseif v~="" then
                local sErr = string.format("[NameLibMgr.GetGameProDBCfg]后台配置出错,sGamePro:%s 出错的配置:%s",sGamePro,v)
                tALog.Print(sErr)
                tALog.SendMsgToTG(sErr,sErr,1)
            end
        end        
    end
    return tGamePro
end

--加载特定语言包昵称
--@params nLanguageId: 语言id,nGrpId:分组
function NameLibMgr.Load(nLanguageId,nGrpId)
    if not nLanguageId or not nGrpId  then
        tALog.Print("_Load   参数错误,nLanguageId:%s,nGrpId:%s",tostring(nLanguageId),tostring(nGrpId))
        return
    end
    local tLNameLib = NameLibMgr.GetGrpLanguage(nGrpId,nLanguageId)
    if not tLNameLib then
        tALog.Print("_Load   nLanguageId:%s,nGrpId:%s  tLNameLib is nil",tostring(nLanguageId),tostring(nGrpId))
        return
    end
    if tLNameLib.nLoadFlag then
        tALog.Print("_Load   nGrpId_%d  nLanguageId_%d  还在加载中",nGrpId,nLanguageId)
        return
    end
    tLNameLib.nLoadFlag = true
    local nCursorId = tLNameLib.nCursorId
    local tSend = ProtoManager.PubProto_pb.Req_LoadAndroidName()
    tSend.nLanguageId = nLanguageId
    tSend.nGrpId = nGrpId
    tSend.sSql = string.format("Call Load_Android_NameInfoz(%d, %d, %d)", nCursorId, Define.CreateCount * 4, nLanguageId)
    local s = tBase.GetSP().new(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REQ_GETANDROIDNAME)
    s:AddString(tSend:SerializeToString())
    tBase.PostDatasByType(tTypeName.db, 1, 1, s:GetData(), s:GetSize())  
    tALog.Print("_Load Nick Name nGrpId:%d,Language:%d,nCursorId:%d", nGrpId,nLanguageId,nCursorId)
end

--处理加载
function NameLibMgr.DealLoad(sClientID, sData, nLen)
    local s = tBase.GetRP().new(sData, nLen)
    local nMainID = s:GetModuleID() 
    local nSubID = s:GetMsgID()
    local tAndroidNameCfg = ProtoManager.PubProto_pb.Rep_LoadAndroidName()
    tAndroidNameCfg:ParseFromString(s:GetString())
    local nLanguageId = tAndroidNameCfg.nLanguageId
    local nGrpId = tAndroidNameCfg.nGrpId
    NameLibMgr.nRandomLangue = NameLibMgr.nRandomLangue or nLanguageId
    local tLNameLib = NameLibMgr.GetGrpLanguage(nGrpId,nLanguageId)
    if not tLNameLib then
        tALog.Print("_DealLoad   nLanguageId:%s,nGrpId:%s  tLNameLib is nil",tostring(nLanguageId),tostring(nGrpId))
        return
    end
    for i,v in ipairs(tAndroidNameCfg.arrAndroidItemName) do
        local tItem = {}
        for a, b in pairs(ProtoManager.PubProto_pb.AndroidItemName()._setter) do
            tItem[a] = v[a]
        end        
        tLNameLib.nCursorId = math.max(tLNameLib.nCursorId, tItem.nId)
        -- tALog.Print("_DealLoad  分组_%d nLanguageId_%d,  目前加载的昵称库游标 nCursorId_%d Id_%d ",nGrpId,nLanguageId,tLNameLib.nCursorId,tItem.nId)
        table.insert(tLNameLib.arrAnNameList,tItem)
    end
    table.sort(tLNameLib.arrAnNameList,function (a, b)
        return a.nId < b.nId
    end)
    if tAndroidNameCfg.isLastPage then
        --本次请求的昵称数据最后一页，收到这个，证明本次请求的数据全部返回了
        tLNameLib.nLoadFlag = false
        tALog.Print("_DealLoad  分组_%d nLanguageId_%d,目前加载的昵称库游标 nCursorId_%d",nGrpId,nLanguageId,tLNameLib.nCursorId)
        if not tLNameLib.isFirLoadFinish then
            tLNameLib.isFirLoadFinish = true    
            if #tLNameLib.arrAnNameList < tLNameLib.nMax then
                tALog.Print("_DealLoad   分组_%d  nLanguageId_%d,昵称不够用,目前加载的昵称个数_%d, 想要缓存的昵称个数_%d ",
                nGrpId,nLanguageId,#tLNameLib.arrAnNameList,tLNameLib.nMax)
            end
        end
    end
end

--获取组管理
--@params nGrpId:分组
--@return 分组管理包（默认nil）
function NameLibMgr.GetGrp(nGrpId)
    if not NameLibMgr.tGrpCfg[nGrpId] then
        tALog.Print("_GetGrp  昵称配置没有这个分组_%d",nGrpId)
    end
    return NameLibMgr.tGrpCfg[nGrpId]
end

--获取分组下的语言包
--@params nGrpId:分组， nLanguageId: 语言id
--@return 对象（默认nil）
function NameLibMgr.GetGrpLanguage(nGrpId,nLanguageId)
    local tGrp = NameLibMgr.GetGrp(nGrpId)
    if not tGrp then
        return
    end
    if not nLanguageId then
        tALog.Print("_GetGrpLanguage  参数nLanguageId错误")
        return
    end
    local tLNameLib = tGrp.tAnNameList[nLanguageId]
    if not tLNameLib then
        tALog.Print("_GetGrpLanguage  分组_%d 没有语言包nLanguageId_%d",nGrpId,nLanguageId)
    end
    return tLNameLib
end

--检查各分组下每个语言包下机器人昵称是否足够，不够则加载
function NameLibMgr.CheckLanguageEnough()
    if tAndroidData.nServerState~=1 then
        return
    end
    if NameLibMgr.nCheckCnt==5 then
        NameLibMgr.nCheckCnt = 0
        NameLibMgr.CreateGrpCfg()
        tALog.Print("_CheckLanguageEnough   nCheckCnt: %d  ",NameLibMgr.nCheckCnt)
        return
    else
        NameLibMgr.nCheckCnt = NameLibMgr.nCheckCnt + 1
    end
    tALog.Print("_CheckLanguageEnough   nCheckCnt: %d",NameLibMgr.nCheckCnt)

    local tGrpCursors = tPublicRedis.GetAllUseAnNickCursor()
    for _, tGrp in pairs(NameLibMgr.tGrpCfg) do
        tALog.Print("_CheckLanguageEnough 11   nGrpId: %d",tGrp.nGrpId)
        for nLanguageId, v in pairs(tGrp.tAnNameList) do
            local nCursors = tGrpCursors[tGrp.nGrpId] and tGrpCursors[tGrp.nGrpId][nLanguageId] or 0
            local nUnUseCnt = NameLibMgr.GetGrpUnUseNickCnt(tGrp.nGrpId,nLanguageId,nCursors)
            if nUnUseCnt < v.nMax then
                NameLibMgr.Load(v.nLanguageId,tGrp.nGrpId) 
            end
            tALog.Print("_CheckLanguageEnough  nGrpId: %d  nLanguageId_%d nCursors_%d nUnUseCnt_%d nMax_%d  ",
            tGrp.nGrpId,nLanguageId,nCursors,nUnUseCnt,v.nMax)
        end
    end
end

--获取分组语言包剩余个数
--@params nGrpId:分组， nLanguageId: 语言id
--@return 剩余昵称个数(默认0)
function NameLibMgr.GetGrpUnUseNickCnt(nGrpId,nLanguageId,nCursors)
    local tLNameLib = NameLibMgr.GetGrpLanguage(nGrpId,nLanguageId)
    if not tLNameLib then
        return 0
    end
    local nUseCursor = nCursors or tPublicRedis.GetUseAnNickCursor(nGrpId,nLanguageId) --已被使用的数据库游标
    local nUnUseCnt = 0
    for k,v in pairs(tLNameLib.arrAnNameList) do
        if v.nId > nUseCursor then
            nUnUseCnt = nUnUseCnt + 1
        end
    end
    return nUnUseCnt
end

local function _GetAnCfgStr(nAnCfgId)
    local str = "合集机器人"
    if nAnCfgId and nAnCfgId == 2 then 
        str = "app机器人"
    end 
    return str
end

--获取一批机器人昵称
--@params nGrpId:分组， nAnCfgId(1:合集机器人,2:app机器人) nCnt:数量
--@return 数组{AndroidItemName,AndroidItemName,....}(默认空数组)
function NameLibMgr.PopAndroidNBatch(nGrpId,nAnCfgId,nCnt)
    local arrAndroidNane = {}  
    local sAnCfgStr = _GetAnCfgStr(nAnCfgId)
    if not nCnt or nCnt == 0 then
        tALog.Print("_PopAndroidNBatch  nGrpId_%d   %s   不需要昵称",nGrpId,sAnCfgStr)
        return arrAndroidNane
    end
    local tGrp = NameLibMgr.GetGrp(nGrpId)
    if not tGrp then
        return arrAndroidNane
    end
    local arrLanguage = tGrp.arrLanguage
    if not arrLanguage or #arrLanguage==0  then
        tALog.Print("_PopAndroidNBatch    分组_%d   没有语言配置",nGrpId)
        return arrAndroidNane
    end
    local arrWantLanguage = {}
    local nTotalRate = 0
    for k,v in ipairs(arrLanguage) do
        local isAPPLib = NameLibMgr.IsAPPLanguage(nGrpId,v.nLanguageId)
        if (nAnCfgId==1 and not isAPPLib) or (nAnCfgId==2 and isAPPLib) then
            table.insert(arrWantLanguage,{nLanguageId = v.nLanguageId,nRate=v.nRate})
            nTotalRate = nTotalRate + v.nRate
        end
    end
    if #arrWantLanguage == 0 then
        tALog.Print("_PopAndroidNBatch    分组_%d   %s 没有昵称 arrWantLanguage_%d ",nGrpId,sAnCfgStr,#arrWantLanguage) 
        return arrAndroidNane
    end
    if nTotalRate==0 then
        tALog.Print("_PopAndroidNBatch    分组_%d   %s  昵称比列配置有问题 nTotalRate_%d ",nGrpId,sAnCfgStr,nTotalRate)  
        return arrAndroidNane
    end    
    tALog.Print("_PopAndroidNBatch    分组_%d   %s arrLanguage_%d arrWantLanguage_%d nTotalRate_%d ",
    nGrpId,sAnCfgStr,#arrLanguage,#arrWantLanguage,nTotalRate)

    local nResCnt = nCnt --剩余的个数i
    local nLackCnt = 0 --上一种语言缺少几个昵称
    for k,v in ipairs(arrWantLanguage) do
        local tLNameLib = NameLibMgr.GetGrpLanguage(nGrpId,v.nLanguageId)
        if tLNameLib then
            if #tLNameLib.arrAnNameList>0 then
                local nUseCursor = tPublicRedis.GetUseAnNickCursor(nGrpId,v.nLanguageId)--目前已使用昵称的游标
                local nNeedCnt = math.floor(nCnt*(v.nRate/nTotalRate)) + nLackCnt --需要这种语言昵称的个数+上一种语言缺少的个数
                if k==#arrWantLanguage then
                    nNeedCnt = nResCnt --最后一种语言，剩余的个数就是需要的个数
                end
                local nGetCnt = 0 --获取了几个昵称
                local nNextCursor = 0 --最后一个昵称得游标id
                for _,tItem in ipairs(tLNameLib.arrAnNameList) do
                    if tItem.nId > nUseCursor then
                        table.insert(arrAndroidNane,tItem)
                        nGetCnt = nGetCnt + 1
                        nNextCursor = tItem.nId
                        if nGetCnt>= nNeedCnt then
                            break
                        end
                    end
                end
                nResCnt = nResCnt - nGetCnt
                nLackCnt = nNeedCnt - nGetCnt
                if nNextCursor > nUseCursor then
                    --保存已使用昵称的游标
                    tPublicRedis.SetUseAnNickCursor(nGrpId,v.nLanguageId,nNextCursor)

                    tALog.Print("_PopAndroidNBatch  分组_%d 语言包nLanguageId_%d  需要_%d个昵称,实际取出_%d 个昵称,旧游标_%d 新游标_%d",
                    nGrpId,v.nLanguageId,nCnt,nGetCnt,nUseCursor,nNextCursor)
                else                                     
                    NameLibMgr.nRequetCnt = NameLibMgr.nRequetCnt + 1
                    local sStr=""
                    if NameLibMgr.nRequetCnt >= 100 then 
                        NameLibMgr.nRequetCnt = 0 
                        -- NameLibMgr.Load(v.nLanguageId,tGrp.nGrpId) 
                        sStr="重新加载昵称"
                    end 
                    sStr= string.format("%s nRequetCnt: %d ",sStr,NameLibMgr.nRequetCnt)
                    tALog.Print("_PopAndroidNBatch   分组_%d 语言包nLanguageId_%d nUseCursor_%d 昵称已用完, %s ",nGrpId,v.nLanguageId,nUseCursor,sStr)
                end
            else
                tALog.Print("_PopAndroidNBatch   分组_%d  语言包nLanguageId_%d  没有昵称数据",nGrpId,v.nLanguageId) 
            end
        else
            tALog.Print("_PopAndroidNBatch   分组_%d  语言包nLanguageId_%d  没有语言包",nGrpId,v.nLanguageId)  
        end
    end
    return arrAndroidNane
end

--获取语言种类数组
--@return 对象{1=1,2=2,99=99} (默认nil)
function NameLibMgr.GetLanguageType(nGrpId)
    local tGrp = NameLibMgr.GetGrp(nGrpId)
    if not tGrp then
        return
    end
    local arrLanguage = tGrp.arrLanguage
    if not arrLanguage or #arrLanguage==0 then
        tALog.Print("_GetLanguageType  分组_%d  没有语言配置",nGrpId)
        return
    end
    local tLanguageType = {}
    for _,v in pairs(arrLanguage) do
        tLanguageType[v.nLanguageId] = v.nLanguageId
    end
    return tLanguageType
end

--是否是第三方的昵称库
--@params nGrpId:分组， nLanguageId: 语言id
--@return true:是，false：不是
function NameLibMgr.IsAPPLanguage(nGrpId,nLanguageId)
    local tLNameLib = NameLibMgr.GetGrpLanguage(nGrpId,nLanguageId)
    if tLNameLib then
        if tLNameLib.arrAnNameList and #tLNameLib.arrAnNameList > 0 then
            local tLAnItem = tLNameLib.arrAnNameList[1]
            if tLAnItem.sShopAcc and tLAnItem.sShopAcc~="" and tLAnItem.sShopAcc~="0" then
                return true
            end
        end
    end
    return false
end

--获取某个分组剩余的还没被使用的昵称个数
--@params nGrpId:分组， nAnCfgId: 1:合集机器人，2:app机器人
--@return 未被使用的昵称总数(默认0)
function NameLibMgr.GetUnUseCntByGrpId(nGrpId,nAnCfgId)
    if not nGrpId or not nAnCfgId then
        tALog.Print("_GetUnUseCntByGrpId    参数不正确 nGrpId_%s,nAnCfgId_%s",tostring(nGrpId),tostring(nAnCfgId))
        return 0
    end
    local sAnCfgStr = _GetAnCfgStr(nAnCfgId)
    local tLanguageType = NameLibMgr.GetLanguageType(nGrpId)
    if not tLanguageType then
        return 0
    end
    local arrWantLanguage = {}
    for _,nLanguageId in pairs(tLanguageType) do
        local isAPPLib = NameLibMgr.IsAPPLanguage(nGrpId,nLanguageId)
        if nAnCfgId==1 and not isAPPLib then
            table.insert(arrWantLanguage,nLanguageId)
        elseif nAnCfgId==2 and isAPPLib then
            table.insert(arrWantLanguage,nLanguageId)
        end
    end
    if #arrWantLanguage == 0 then
        tALog.Print("_GetUnUseCntByGrpId  分组_%d  没有 %s 昵称",nGrpId,sAnCfgStr)
        return 0
    end
    local nCnt = 0 --未被使用的昵称总数
    for _,nLanguageId in pairs(arrWantLanguage) do
        local tLNameLib = NameLibMgr.GetGrpLanguage(nGrpId,nLanguageId)
        if tLNameLib then
            local nUnUseCnt = NameLibMgr.GetGrpUnUseNickCnt(nGrpId,nLanguageId)
            if nUnUseCnt>=0 then
                nCnt = nCnt + nUnUseCnt
            else
                local nLanguageCnt = #tLNameLib.arrAnNameList --某种语言的昵称个数
                tALog.Print("_GetUnUseCntByGrpId  Error   分组_%d,nLanguageId_%d,已使用的昵称数目大于缓存的昵称数目,出现异常,nLanguageCnt:%d,nUnUseCnt:%d",
                nGrpId,nLanguageId,nLanguageCnt,tLNameLib.nUnUseCnt)
            end
        end
    end
    return nCnt
end

--获取分组昵称机器人比例
--@params nGrpId:分组
--@return 昵称机器人比例(默认nil)
function NameLibMgr.GetGrpRealRate(nGrpId)
    local tGrp = NameLibMgr.GetGrp(nGrpId)
    if not tGrp then
        return 
    end
    return tGrp.nRealRate
end

--获取非昵称机器人的前缀
--@params nGrpId:分组
--@return sFirstName(默认VIP)
function NameLibMgr.GetFirstName(nGrpId)
    local sFirstName = "VIP"
    local tGrp = NameLibMgr.GetGrp(nGrpId)
    if tGrp then
        sFirstName = tGrp.sFirstName
    end
    return sFirstName    
end

--昵称库是否已经准备好了
--@params nGrpId:分组
function NameLibMgr.IsPrepareFinsh(nGrpId)
    if NameLibMgr.isInitFinish then
        local tGrp = NameLibMgr.GetGrp(nGrpId)
        if tGrp then
            for _,tLanguage in pairs(tGrp.tAnNameList) do
                if tLanguage.isFirLoadFinish==false then
                    return false
                end
            end
            return true
        end
    end
    return false
end

--获取机器人类型
--@params nGrpId 分组id nGameId 游戏id
--@return nAnCfgId(1:合集机器人 2:app机器人),默认nil
function NameLibMgr.GetAnCfgId(nGrpId,nGameId)
    local tGrp = NameLibMgr.GetGrp(nGrpId)
    if tGrp then
        if tGrp.tGamePro and tGrp.tGamePro[nGameId] then
            local nAnCfgId = tGrp.tGamePro[nGameId]
            local sAnCfgStr = _GetAnCfgStr(nAnCfgId)
            tALog.Print("_GetAnCfgId 后台配置nGrpId_%d,nGameId_%d,nAnCfgId_%d %s",nGrpId,nGameId,nAnCfgId,sAnCfgStr)
            return nAnCfgId
        end
    end
end

--初始化数据库的机器人使用情况
--@params nGrpId 分组id
function NameLibMgr.InitDBAndroidDetail(nGrpId)
    local arrIndex = {"HJAndroid","AppAndroid"}
    for k,sIndex in pairs(arrIndex) do
        local tSend = ProtoManager.PubProto_pb.Req_UpdateAndroidMysql()
        tSend.nSrvId = tSrvInfo.nServerId
        tSend.nGrpId = nGrpId
        tSend.sIndex = sIndex
        tSend.nTotal = 0
        tSend.nWorking = 0
        tSend.nRelax = 0
        tSend.nLending = 0
        tSend.nCanUse = 0

        local s = tBase.GetSP().new(ProtoManager.Sys.DB, ProtoManager.Sub_DB.SUB_REQ_UPDATEMYSQL)
        s:AddString(tSend:SerializeToString())
        tBase.PostDatasByType(tTypeName.db, 0, 0, s:GetData(), s:GetSize())
    end
end

return NameLibMgr