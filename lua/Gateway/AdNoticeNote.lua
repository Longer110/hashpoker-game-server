package.path = require("./lua/Gateway/Head").path
local tBase = require("base")
local tName = require("typename")
local ProtoMgr = require("ProtoManager") 
local tParserAux = require("ParserAux")
local cjson = require("cjson")
local tApi	= require("publicApi")

AdNoticeNote = 
{
	arrAllCfg = nil,
	m_client_sink_list = nil, -- 网关保存的用户列表
	m_isOpenTimer = 0,  --定时器是否开启
	m_tNotice = {},
	m_TimerID = 15555,
	m_BatchID = 10419, -- 批量发送定时器标识
}

-- 公告推送:接口 （错开时间，定时，定量，去重，发送单条，重播，发多条）
function AdNoticeNote.BuildAdNoticeTime(ID)
	local tConfig = AdNoticeNote.arrAllCfg.tAdNoticeNoteList
	local bLimitNote = false
	tBase.Log("AdCfgToalLen:"..#tConfig)
	for i=1,#tConfig do
		if ID~=nil and ID==tConfig[i].ID then 
			bLimitNote=true
			tBase.Log("ReDo公告ID:"..ID)
		end
		local nSTime = tApi.string2time(tConfig[i].StartTime)				
		local nETime = tApi.string2time(tConfig[i].EndTime) 
		local bBegin = tonumber(os.time() - nSTime)    -- 开始日期   小于 0  还没开始， 大于 0  开始了
		local nIndate = tonumber(nETime - os.time())   -- 有效期    大于 0  没过期， 小于 0  过期了 
		tBase.Log("bBegin:"..bBegin.." nIndate:"..nIndate.." 公告内容：%s",cjson.encode(tConfig[i]) )
		if bBegin>=0  and nIndate>=0 then -- 开始公告: 
			local tNotice = {}
			tNotice.nScope = tConfig[i].Scope
			tNotice.sChannel = tConfig[i].Channel
			tNotice.sStartTime = nSTime
			tNotice.sEndTime = nETime
			tNotice.sDetails = tConfig[i].Details
			tNotice.Frequency = tConfig[i].Frequency
			AdNoticeNote.PushAdNote(AdNoticeNote.m_client_sink_list,ProtoMgr.GatewayPro.GATEWAY, ProtoMgr.Sub_GateWay.SUB_GATEWAY_NOTICE,tNotice,100,10)
			if tNotice.Frequency~=nil and tNotice.Frequency>=1 then
				tBase.TokenCallTimeID(AdNoticeNote.m_TimerID+tConfig[i].ID, (tConfig[i].ID+1000)*tNotice.Frequency*60, 1, AdNoticeNote.BuildAdNoticeTime, tConfig[i].ID)
			end
			if bLimitNote then return end
		else
			if bBegin < 0 then
			    bBegin = nSTime - os.time()
			    tBase.Log("距离该公告开始时间："..bBegin.." 秒设定时公告ID:"..tConfig[i].ID) 
				tBase.TokenCallTimeID(AdNoticeNote.m_TimerID+tConfig[i].ID, (tConfig[i].ID+1000)*10, 1, AdNoticeNote.BuildAdNoticeTime, tConfig[i].ID)
			elseif nIndate < 0 then 
				tBase.Log(" 检查公告过期:"..tConfig[i].Details)
			else 
				tBase.Log(" 检查公告时间错误 ")
			end 
		end
	end 
end

function AdNoticeNote.PushAdNote(tClientInfo, nMain, nSub, tNotice, nCount, nTime)
	tBase.Log("PushAdNote: "..type(tClientInfo) )
	if (tClientInfo == nil) or (tNotice==nil) or (tNotice.sChannel==nil) then
		tBase.Log("tClientInfo nil")
		return 
	end
	local tV = tApi.string_split(tNotice.sChannel, ",")
	tBase.LogT(tV)
	local  tClientList = {}
	for k, v in pairs(tClientInfo) do
		tBase.LogT("look_nID:",v.nID," nUserID:",v.nUserId," nShopId:",v.nShopId )
		Channel = function ()  
			if tApi.FindKeyByVal(tV, "0" ) then 
				tBase.Log("M")
				return true
			elseif tApi.FindKeyByVal(tV, tostring(v.nShopId) ) then  
				tBase.Log("T")
				return true
			else
				return false
			end
		end
		if v.nUserId > 0 and v.IsOnline and Channel() then
			tBase.Log("noticePeople = %d key:%s", v.nUserId, cjson.encode(k))
			table.insert(tClientList, k)
		end 
	end
	if (tClientList == nil or #tClientList <= 0) then
		tBase.Log("tClientList_nil")
		return 
	end
	tBase.Log("tClientList= %s", tClientList[1])
	local tempNotice = {}
	tempNotice.ClientList = tClientList
	tempNotice.nMain = nMain
	tempNotice.nSub = nSub
	tempNotice.tNotice = tNotice
	tempNotice.nCount = nCount
	tempNotice.Time = nTime
	if (tempNotice ~= nil ) then
		if ( AdNoticeNote.m_tNotice == nil) then
			tBase.Log("Not_Begin_m_tNotice=nil")
		end
		table.insert(AdNoticeNote.m_tNotice, tempNotice)
		if (AdNoticeNote.m_tNotice ~= nil) then
			--tBase.KillTimer(AdNoticeNote.m_TimerID)
			if (AdNoticeNote.m_isOpenTimer == 0 ) then
				--启用定时器向用户推送信息
				tBase.Log("AdNotice_Start_Timer")
				AdNoticeNote.m_isOpenTimer = 1
				tBase.SetTimer(AdNoticeNote.m_BatchID, nTime * 1000,-1, AdNoticeNote.RunPushAdNotice)
			end
		end
	else 
		tBase.Log("Not_To_Send_Notice_tClient=nil")
	end
end

function AdNoticeNote.RunPushAdNotice()
	tBase.Log("#AdNoticeNote.m_tNotice: "..#AdNoticeNote.m_tNotice)
	if (AdNoticeNote.m_tNotice ~= nil and #AdNoticeNote.m_tNotice > 0) then		
		for key, val in pairs(AdNoticeNote.m_tNotice) do
			if (val.ClientList ~= nil and #val.ClientList >=0 ) then
				local continue = 1
				repeat
					tBase.Log("I_am_repeat:%s",cjson.encode(val.ClientList) )
					local i = 1;
					local nCount = 0;
					tBase.Log("Notice_ClientList_nNum= %d", #val.ClientList)
					while val.ClientList and #val.ClientList > 0 do
						local clientID = val.ClientList[i]						
						if (AdNoticeNote.m_client_sink_list[clientID] ~= nil) then
							--向客户端推送内容
							tBase.Log("Push_The_%d_Of_clientID = %s",i, tostring(clientID))
							local s = tBase.GetSP().new(val.nMain, val.nSub)

							local tSend = ProtoMgr.Gateway_pb.AdNoticeNoteRep()
							tSend.nScope = val.tNotice.nScope
							tSend.sChannel = tostring(val.tNotice.sChannel)
							tSend.sStartTime = tostring(val.tNotice.sStartTime)
							tSend.sEndTime = tostring(val.tNotice.sEndTime)
							tSend.sDetails = tostring(val.tNotice.sDetails)
							s:AddString(tSend:SerializeToString())
							s:SendData(tBase.GetNetworkEngine(), clientID)
							nCount = nCount + 1
							table.remove(val.ClientList, i)

							if nCount >= val.nCount or val.ClientList == nil or #val.ClientList <= 0 then
								continue = 0
								if (val.ClientList == nil or #val.ClientList <= 0) then
									table.remove(AdNoticeNote.m_tNotice, key)
								end
								AdNoticeNote.RunPushAdNotice()								
								tBase.Log("Notice-OneList-Finsh:"..#val.ClientList)
								return
							end
						else 
							tBase.Log("No_In_nGroup_Or_Offline_The_clientID=%d", clientID)
							table.remove(val.ClientList, i)
							if (val.ClientList == nil or #val.ClientList <= 0) then
								table.remove(AdNoticeNote.m_tNotice, key)
							end
						end
						
					end
					continue = 0
				until( continue == 0)
			else 
				table.remove(AdNoticeNote.m_tNotice, key)
			end
		end
	else
		--公告内容推送完毕，关闭定时器
		tBase.Log("AdNoticeNote_KillTimer")
		tBase.KillTimer(AdNoticeNote.m_BatchID)
		AdNoticeNote.m_isOpenTimer = 0
	end
end

--计算零点时间差
function AdNoticeNote.GetLeroLeadTime()   
   local now_date = os.date("*t",now)   -- 获取当前时间
   -- 当天的最后时间
   local nEnd_Time = os.time{year=now_date.year, month=now_date.month, day=now_date.day, hour=23,min=59,sec=59} 
   tBase.Log(" 当天的最后时间--------------nEnd_Time:  "..nEnd_Time)
   -- 当前时间与零点的时间差
   local nLero_Time = (nEnd_Time - os.time()) +1
   tBase.Log(" 当前时间与零点的时间差--------nLero_Time:  "..nLero_Time)
   return nLero_Time
end

return AdNoticeNote

