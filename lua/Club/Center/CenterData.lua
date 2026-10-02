--俱乐部中心服公用数据缓存
local CenterData = {}

CenterData.arrGroup = {} --本服对应的分组 {nGroupId,nGroupId,...}
CenterData.tMaintenanceInfo = {} --服务器维护信息

CenterData.arrClubReqQueue = {} --俱乐部信息请求队列

CenterData.tTimerId = {} --中心服定时任务的定时器id集合

CenterData.tTimerObj = nil --定时器对象

CenterData.nMinClubId = nil --本服加载的最小俱乐部id
CenterData.nMaxClubId = nil --本服加载的最大俱乐部id

CenterData.nClubCnt = 0 --本中心服的俱乐部数量
CenterData.arrSplitClub = {} --俱乐部分批

return CenterData