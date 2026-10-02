package.path = require("./lua/DB_s/Head").path

local tBase	= require("base")           -- 基础功能接口
local tErr   = require("ErrorSink")       -- 捕捉错误


NoticeSink = {}



function NoticeSink.LoadNoticeConfig(sReturnKey, sData, nLen)
    local ReadData = tBase.GetRP().new(sData, nLen)
    local MainID = ReadData:GetModuleID() 
    local SubID = ReadData:GetMsgID()
    local sSql = ReadData:GetString()
	
	local tSqlRes = {}
	local nIndex = 0
	tBase.Log("加载公告配置表    执行SQL: %s ", sSql)    
    local cursor = assert (dbSink.PlatformDB_connect:execute (sSql))  
    repeat
        row = cursor:fetch({},"a")
        while row do
           function NoticeSink.GetRes(row)
                tSqlRes[nIndex..",".."nID"]         = tonumber(row.ID)
                tSqlRes[nIndex..",".."nScope"]      = tonumber(row.Scope)           
                tSqlRes[nIndex..",".."sChannel"]    = row.Channel 
                tSqlRes[nIndex..",".."nType"]       = tonumber(row.Type)
                tSqlRes[nIndex..",".."nNoticeType"] = tonumber(row.NoticeType) 
                tSqlRes[nIndex..",".."sStartTime"]  = row.StartTime
                tSqlRes[nIndex..",".."sEndTime"]    = row.EndTime
                tSqlRes[nIndex..",".."nFrequency"]  = tonumber(row.Frequency) 
                tSqlRes[nIndex..",".."nPriority"]   = tonumber(row.Priority)     
                tSqlRes[nIndex..",".."sDetails"]    = row.Details or "0" 
                tBase.Log(" 跑马灯内容：       sDetails：        "..tSqlRes[nIndex..",".."sDetails"])
                tSqlRes[nIndex..",".."sInStart"]    = tonumber(row.InStart)   
                tSqlRes[nIndex..",".."nNewsType"]    = tonumber(row.NewsType)   
                tSqlRes[nIndex..",".."sWeekTime"]       = row.WeekTime    
                tSqlRes[nIndex..",".."sStartPlayTime"]  = row.StartPlayTime    
                tSqlRes[nIndex..",".."sEndPlayTime"]    = row.EndPlayTime   
           end  
           xpcall(NoticeSink.GetRes,tErr.tpLog, row)
            nIndex = nIndex + 1
            row = cursor:fetch(row,"a")
        end
        cursor:close()
        cursor = dbSink.PlatformDB_connect:nextres()
    until( cursor == 0 ) 
    local s = tBase.GetSP().new(MainID, SubID)
    tBase.Log(" 加载公告配置表         nIndex：  "..nIndex)
    s:AddInt32(nIndex)
    for i = 0,nIndex - 1 do
        s:AddInt32(tSqlRes[i..",".."nID"])
        s:AddInt32(tSqlRes[i..",".."nScope"])
        s:AddString(tSqlRes[i..",".."sChannel"])
        s:AddInt32(tSqlRes[i..",".."nType"])
        s:AddInt32(tSqlRes[i..",".."nNoticeType"])
        s:AddString(tSqlRes[i..",".."sStartTime"])
        s:AddString(tSqlRes[i..",".."sEndTime"])
        s:AddInt32(tSqlRes[i..",".."nFrequency"])
        s:AddInt32(tSqlRes[i..",".."nPriority"])
        s:AddString(tSqlRes[i..",".."sDetails"])
        s:AddInt32(tSqlRes[i..",".."sInStart"])
        s:AddInt32(tSqlRes[i..",".."nNewsType"])
        s:AddString(tSqlRes[i..",".."sWeekTime"])
        s:AddString(tSqlRes[i..",".."sStartPlayTime"])
        s:AddString(tSqlRes[i..",".."sEndPlayTime"])            
    end
    tBase.PostToClient(sReturnKey, s:GetData(), s:GetSize())
    tBase.Log(" 加载公告配置表      DB服  返回成功  ")
end



return NoticeSink
