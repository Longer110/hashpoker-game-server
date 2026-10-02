local Alg ={}


--按每星期开赛;返回最近开赛的时间戳
--weekday:一周里的第几天（1=星期日，7=星期六）
--hour(0~23) m(0~59) sec(0~59)
--zone:时区(8为北京时区)
function Alg.nearest_timestamp_week(weekday,hour,m,sec,zone,now)
    -- 获取当前时间戳
    local now = now or os.time()
    --所用时区当前日期
    local curDay = os.date("!*t", now+3600*zone)
	--获取当前是一周的第几天（1=星期日，7=星期六）
	local wday =curDay.wday
    -- 计算从当前天数到目标天数的差值
    local diff = (weekday - wday) % 7
    -- 如果差值是负数，则需要向前计算，否则向后计算
    if diff < 0 then diff = diff + 7 end
	--所用时区当天0点的时间戳
	local A =now -(curDay.hour*3600 +curDay.min*60 +curDay.sec)		
	-- 返回时间戳
	local nt =A +(diff*24*3600) +hour*3600 +m*60 +sec
	return nt
end

--某月有多少天
local function getMaxDayOfMonth(year,month)
	if month ==2 then
		if year %4==0 and (year %100 ~=0 or year %400==0) then
			return 29
		else
			return 28
		end
	end
	if month ==4 or month==6 or month==9 or month==11 then
		return 30
	end
	return 31
end

--按每月开赛;返回最近开赛的时间戳
--day(1~28) hour(0~23) m(0~59) sec(0~59)
--zone:时区(8为北京时区)
function Alg.nearest_timestamp_month(monthday,hour,m,sec,zone,now)
    -- 获取当前时间戳
    local now = now or os.time()
    --所用时区当前日期
    local curDay = os.date("!*t", now+3600*zone)
	--当前
	local cur =curDay.day*3600*24 +curDay.hour*3600 +curDay.min*60 +curDay.sec
	--目标
    local ntt =monthday*3600*24 +hour*3600 +m*60 +sec
	--所用时区本月第一天0点时间戳
	local A =now -cur
	if ntt>cur then
		return A +ntt
	end
    --所用时区下一个月第一天0点时间
	local B =A+ getMaxDayOfMonth(curDay.year,curDay.month)*3600*24
	return B +ntt
end

--按天开赛;返回最近开赛的时间戳
--hour(0~23) m(0~59) sec(0~59)
--zone:参数所用时区(8为北京时区)
function Alg.nearest_timestamp_day(hour,m,sec,zone,now)
    -- 获取当前时间戳
    local now =now or os.time()
    --所用时区当前日期
    local curDay = os.date("!*t", now+3600*zone)
	--当前
	local cur =curDay.hour*3600 +curDay.min*60 +curDay.sec
	--目标
    local ntt =hour*3600 +m*60 +sec
	--所用时区当天0点时间戳
	local A =now -cur
	if ntt>cur then
		return A +ntt
	end
    --所用时区下一天0点时间
	local B =A+ 3600*24
	return B +ntt
end

--获得本地时区
local function get_timezone()
    local now = os.time()
    local utc = os.time(os.date("!*t"))
    local offset = os.difftime(now, utc)
    return math.floor(offset / 60 / 60)  -- Convert to hours
end

--根据某时区的年月日时分秒，转成时间戳
function Alg.get_timestamp(year, month, day, hour, min, sec,zone)
  local z=get_timezone()		
  local hour = hour-(zone-z)	--将hour转化为本地时区
  local t = {year = year, month = month, day = day, hour =hour, min = min, sec = sec}
  local tt= os.time(t)
  return tt
end

--将时间戳转成字符串时间
function Alg.ToDate(timestamp,zone)
	if not timestamp then
		return "nil"
	end
	local zone=zone or 8	--默认使用北京时间
	return os.date("!%Y-%m-%d %H:%M:%S",timestamp+3600*zone)
end


return Alg