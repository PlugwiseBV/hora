local floor, insert, concat = math.floor, table.insert, table.concat
local format                = string.format
local osDate, osTime        = os.date, os.time

local function copyTable(source, target)
    target = (target ~= nil and target) or {}
    for k, v in pairs(source) do
        target[(type(k) == "table" and copyTable(k)) or k] = (type(v) == "table" and copyTable(v)) or v
    end
    return target
end

-- Some base tables
local letMult = {
    S = 1,
    M = 60,
    H = 3600,
    D = 86400,
    W = 604800,
}

-- RFC2616 (and RFC850 and RFC1123 and ANSI C asctime()) months and days.
local months = {
    "Jan",      "Feb",      "Mar",      "Apr",      "May",      "Jun",      "Jul",      "Aug",      "Sep",      "Oct",      "Nov",      "Dec",
    Jan = 1,    Feb = 2,    Mar = 3,    Apr = 4,    May = 5,    Jun = 6,    Jul = 7,    Aug = 8,    Sep = 9,    Oct = 10,   Nov = 11,   Dec = 12,
}
local days = {
    "Sun",      "Mon",      "Tue",      "Wed",      "Thu",      "Fri",      "Sat",
    Sun = 1,    Mon = 2,    Tue = 3,    Wed = 4,    Thu = 5,    Fri = 6,    Sat = 7,
}

-- Base functions are local for speed.

-- Memoizes the result of converting an offset as returned by strftime() to seconds.
local offsetSeconds = setmetatable({}, {__index = function(cache, offset)
    local sign, hours, mins = offset:match("^(.)(%d%d)(%d%d)$")
    local secs = hours * 3600 + mins * 60
    if sign == '-' then
        secs = secs * -1
    end
    cache[offset] = secs
    return secs
end})

-- You give it a stamp in local time, it tells you what the ofset to UTC in seconds is.
local function offset(stamp)
    return offsetSeconds[osDate("%z", floor(tonumber(stamp) or osTime()))]
end

-- You give it a timestamp in local time, convert it to a table in local time.
local function localDate(stamp)             return osDate('*t', tonumber(stamp) or osTime()) end
-- You give it a timestamp in local time, convert it to a table in UTC.
local function utcDate(stamp)               return osDate('!*t', tonumber(stamp) or osTime()) end

-- You have a table in local time, convert it to a timestamp in localtime
local localDateToTimestamp = osTime
-- You have a table in local time, convert it to a table in UTC.
local function localDateToUTCDate(stamp)    return utcDate(localDateToTimestamp(stamp)) end
-- You have a table in UTC. Convert it to its UTC timestamp
local function utcDateToTimestamp(utcD)
    local stamp = osTime(utcD)
    if not stamp then return nil, "Please pass a valid utc date" end
    stamp = stamp + offset(stamp)
    local calcHour, thisHour = utcDate(stamp).hour, tonumber(utcD.hour or 0)
    if calcHour ~= thisHour then
        local diffHour = calcHour - thisHour
        if      diffHour >  12 then diffHour = 24 - diffHour
        elseif  diffHour < -12 then diffHour = 24 + diffHour
        end
        return stamp - 3600 * diffHour
    end
    return stamp
end
-- You have a table in UTC. Convert it to a table in local time.
local function utcDateToLocalDate(utcD)   return osDate('*t', utcDateToTimestamp(utcD)) end

local function ISO8601DurationToSeconds(str)
    if type(str) == "string" then
        local seconds = nil
        local nDays, time = str:match("^P([%dDW]*)T?([%dSMH]*)$")
        if not (nDays and time) then return nil, "Not an ISO8601 Duration that can be converted to seconds." end
        for num, let in time:gmatch("(%d+)([SMH])") do
            seconds = (seconds or 0) + tonumber(num) * letMult[let]
        end
        for num, let in nDays:gmatch("(%d+)([DW])") do
            seconds = (seconds or 0) + tonumber(num) * letMult[let]
        end
        return seconds
    else
        return nil, "Please pass a string."
    end
end

local function changeDateTable(table, str, increment)
    local timediff = ISO8601DurationToSeconds(str)
    assert(timediff, "The passed duration "..str.." is not a valid ISO 8601 duration.")
    local newTable
    if timediff ~= nil then
        if not increment then
            timediff = timediff *-1
        end
        local tableSec = localDateToTimestamp(table)
        newTable = localDate(tableSec + timediff)
        if (timediff % 86400 == 0) and (newTable.isdst ~= table.isdst) then
            table = copyTable(table)
            table.isdst = newTable.isdst
            tableSec = localDateToTimestamp(table)
            local testTable = localDate(tableSec + timediff)
            -- This is the test where you want to land in an hour that does not exists because the DST removes that hour. In that case, go for the 24 hour day rather then landing one hour early
            if testTable.isdst == newTable.isdst then
                newTable = testTable
            end
        end
    end
    return newTable or table
end

-- Base functions are local for speed.
local hora = {
    offset                      = offset,
    localDate                   = localDate,
    utcDate                     = utcDate,
    localDateToTimestamp        = localDateToTimestamp,
    localDateToUTCDate          = localDateToUTCDate,
    utcDateToTimestamp          = utcDateToTimestamp,
    utcDateToLocalDate          = utcDateToLocalDate,
    ISO8601DurationToSeconds    = ISO8601DurationToSeconds,
}

function hora.incrementDateTable(table, str)
    return changeDateTable(table, str, true)
end

function hora.decrementDateTable(table, str)
    return changeDateTable(table, str, false)
end

-- Offsets as returned by strftime() need a small modification. Memoize the result here.
local offsetCache = setmetatable({}, {__index = function(cache, offsetStr)
    cache[offsetStr] = offsetStr:gsub("^(.-)(%d%d)$", "%1:%2")
    return cache[offsetStr]
end})

function hora.ISO8601Date(stamp)
    if type(stamp) == "number" and stamp > 0 then
        local flooredStamp  = floor(stamp)
        local now = osDate("%FT%H:%M:%S", flooredStamp)
        if flooredStamp == stamp then
            return now..offsetCache[osDate('%z', flooredStamp)]
        else
            -- An fp date is serialized to millisecond precision. C's printf() always rounds, but we need our dates to be floored.
            return format('%s.%03d%s', now, (1000 * stamp) % 1000, offsetCache[osDate('%z', flooredStamp)])
        end
    elseif stamp == 0 then
        return ''
    end
    return nil, "Please pass a positive number."
end

function hora.ISO8601DateToTimestamp(str)
    if str == '' then
        return 0
    elseif type(str) == "string" then
        local d = {}
        -- Try to match the UTC offset in minute resolution, first.
        d.offSign, d.offHour, d.offMin = str:match('([+-])(%d%d):?(%d%d)[ \t]*$')
        if not (d.offSign and d.offHour and d.offMin) then
        -- If that fails, try to match only the hour diff
            d.offSign, d.offHour = str:match('^[ \t]*%d%d%d%d%-?%d%d%-?%d%dT?%d?%d?:?%d?%d?:?%d?%d?%.?%d?%d?%d?([+-])(%d%d)[ \t]*$')
        end
        -- Both no timezone and 'Z' mean UTC.
        if (not (d.offSign and d.offHour)) or str:match('Z[ \t]*$') then
            d.offSign, d.offHour = '+', 0
        end
        if not d.offMin then d.offMin = 0 end
        local offsetSecs = tonumber(d.offHour) * 3600 + tonumber(d.offMin) * 60
        if d.offSign == '-' then
            offsetSecs = -1 * offsetSecs
        end
        d = {}
        -- Match subsecond precision.
        d.year, d.month, d.day, d.hour, d.min, d.sec        = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)T(%d%d):?(%d%d):?(%d%d%.%d+)')
        local subsecond = 0
        -- Match second precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year, d.month, d.day, d.hour, d.min, d.sec    = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)T(%d%d):?(%d%d):?(%d%d)')
        else
            subsecond = d.sec - floor(d.sec)
            d.sec = floor(d.sec)
        end
        -- Match minute precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year, d.month, d.day, d.hour, d.min           = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)T(%d%d):?(%d%d)')
            d.sec                                           = 0
        end
        -- Match hour precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year, d.month, d.day, d.hour                  = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)T(%d%d)')
            d.min, d.sec                                    = 0, 0
        end
        -- Match day precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year, d.month, d.day                          = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)')
            d.hour, d.min, d.sec                            = 0, 0, 0
        end
        -- Match month precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year, d.month                                 = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)')
            d.day, d.hour, d.min, d.sec                     = 0, 0, 0, 0
        end
        -- Match year precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year                                          = str:match('^[ \t]*(%d%d%d%d)')
            d.month, d.day, d.hour, d.min, d.sec            = 0, 0, 0, 0, 0
        end
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            return nil, 'Could not parse date string: does not conform to ISO 8601, or we don\'t implement that part of ISO 8601: we don\'t allow ordinal and year-week dates.'
        else
            -- To get UTC, we assume the date already is UTC and then subtract the specified offset.
            -- Finally, we add subsecond precision.
            return hora.utcDateToTimestamp(d) - offsetSecs + subsecond
        end
    else
        return nil, "Please pass a string."
    end
end

-- Memoize duration serialization here.
local durationCache = setmetatable({[0] = "PT0H"}, {__index = function(cache, seconds)
    local insertedT = false
    local result = {'P'}
    if seconds >= 604800 then
        local weeks = floor(seconds / 604800)
        insert(result, weeks)
        insert(result, 'W')
        seconds     = seconds - weeks * 604800
    end
    if seconds >= 86400 then
        local nDays = floor(seconds / 86400)
        insert(result, nDays)
        insert(result, 'D')
        seconds     = seconds - nDays * 86400
    end
    if seconds >= 3600 then
        local hours = floor(seconds / 3600)
        insert(result, 'T')
        insertedT = true
        insert(result, hours)
        insert(result, 'H')
        seconds     = seconds - hours * 3600
    end
    if seconds >= 60 then
        local mins  = floor(seconds / 60)
        if not insertedT then
            insert(result, 'T')
            insertedT = true
        end
        insert(result, mins)
        insert(result, 'M')
        seconds     = seconds - mins * 60
    end
    if seconds > 0 then
        if not insertedT then
            insert(result, 'T')
        end
        insert(result, seconds)
        insert(result, 'S')
    end
    cache[seconds] = concat(result)
    return cache[seconds]
end})

function hora.ISO8601Duration(seconds)
    if type(seconds) == "number" and seconds >= 0 then
        return durationCache[seconds]
    else
        return nil, "Please pass a positive number."
    end
end

--- Produce RFC1123 dates, e.g. Sun, 06 Nov 1994 08:49:37 GMT
-- \publicfunction{util.RFC1123Date}{Produce RFC1123 dates, e.g. Sun, 06 Nov 1994 08:49:37 GMT}{
-- \param{stamp}{\myref{d:unix-timestamp}{The timestamp to convert to an RFC1123 date string.}
-- \result{\myref{d:string}}{The RFC1123 date string.}
-- }
function hora.RFC1123Date(stamp)
    local utcD = utcDate(stamp)
    return format('%s, %02d %s %04d %02d:%02d:%02d GMT', days[utcD.wday], utcD.day, months[utcD.month], utcD.year, utcD.hour, utcD.min, floor(utcD.sec))
end

--- We're trying to convert HTTP date fields to UNIX timestamps here. According to RFC2616, the supported formats are:
--      Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123
--      Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036
--      Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format
-- NOTE: all dates MUST be assumed to be GMT (according to RFC2616!). This makes the implementation trivial.
-- \publicfunction{util.HTTPDateToTimestamp}{We're trying to convert HTTP date fields to UNIX timestamps here. According to RFC2616, the supported formats are:\\
--      Sun, 06 Nov 1994 08:49:37 GMT  ; RFC 822, updated by RFC 1123\\
--      Sunday, 06-Nov-94 08:49:37 GMT ; RFC 850, obsoleted by RFC 1036\\
--      Sun Nov  6 08:49:37 1994       ; ANSI C's asctime() format}{
-- \param{date}{\myref{d:string}}{The date string.}
-- \result{\myref{d:unix-timestamp}{The timestamp converted from the date string.}
-- }
function hora.HTTPDateToTimestamp(date)
    if "string" == type(date) then
        local d = {}
        -- We first try to match HTTP/1.1's version of RFC1123.
        d.day, d.month, d.year, d.hour, d.min, d.sec = date:match('^[ \t]*[%w]+, (%d%d) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT')
        -- If that fails, we try the obsolete RFC 850
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.day, d.month, d.year, d.hour, d.min, d.sec = date:match('^[ \t]*[%w]+, (%d%d)%-(%a%a%a)%-(%d%d) (%d%d):(%d%d):(%d%d) GMT')
        end
        -- If that fails, we try ANSI C's asctime() format.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.month, d.day, d.hour, d.min, d.sec, d.year = date:match('^[ \t]*[%w]+, (%a%a%a) [ ]?(%d+) (%d%d):(%d%d):(%d%d) (%d%d%d%d)')
        end
        -- If that fails, we've received an invalid date format.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            return nil, "Could not parse date format. Is it HTTP/1.1's version of RFC1123, RFC850, or ANSI C asctime()?"
        else
            -- Because of the form of the patterns above, we know tonumber() must be successful. So we don't bother to check.
            d.year, d.day, d.hour, d.min, d.sec = tonumber(d.year), tonumber(d.day), tonumber(d.hour), tonumber(d.min), tonumber(d.sec)
            -- Interpret RFC850 dates according to RFC2616. This algorithm won't work anymore in 2100. Hopefully, this code will be replaced by then.
            if d.year < 100     then
                local now = osDate()
                local futureYear    = d.year + 2000
                local pastYear      = d.year + 1900
                if now.year - pastYear < futureYear - now.year then
                    d.year = pastYear
                else
                    d.year = futureYear
                end
            end
            d.month = months[d.month] or months[string.lower(d.month):gsub('^%l', string.upper)]
            if not d.month then
                return nil, 'Could not parse month name. Should be Jan, Feb, Mar, Apr, May, Jun, Jul, Aug, Sep, Oct, Nov or Dec (case-insensitive).'
            else
                return utcDateToTimestamp(d)
            end
        end
    else
        return nil, "Please pass a string."
    end
end


package.loaded.hora = hora

return package.loaded.hora
