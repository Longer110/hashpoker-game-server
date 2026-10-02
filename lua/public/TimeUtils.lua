
TimeUtils = {}

function TimeUtils:TimestampToBeiJingString(milliseconds)
    -- 将毫秒时间戳转换为秒时间戳
    local seconds = math.floor(milliseconds / 1000)
    seconds = seconds + 8 * 60 * 60  --加8小时后的UTC时间格式后的时间字符串， 期值等于北京时间, 可以避免跨天跨月的转化等
    -- 转换为UTC时间格式
    local utc_time = os.date("!*t", seconds)

    -- 东八区时间 = UTC时间 + 8小时
    local beijing_time = {
        year = utc_time.year,
        month = utc_time.month,
        day = utc_time.day,
        hour = utc_time.hour,
        min = utc_time.min,
        sec = utc_time.sec
    }

    -- 由于前面已经在时间戳上加了8小时, 故本初就不需要处理时区跨越问题（如果跨天, 跨月, 跨年等问题）
    
    -- 格式化输出UTC时间字符串
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", 
        beijing_time.year, beijing_time.month, beijing_time.day, 
        beijing_time.hour, beijing_time.min, beijing_time.sec)
end

return TimeUtils