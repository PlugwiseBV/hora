
-- Base functions are local for speed.
local function offset(stamp)
    local stamp     = math.floor(tonumber(stamp) or os.time())
    local utcD      = os.date("!*t", stamp)
    utcD.isdst      = os.date('*t', stamp).isdst
    return stamp - os.time(utcD)
end

local function localDate(stamp)              return os.date('*t', tonumber(stamp) or os.time()) end
local function utcDate(stamp)
    local stamp     = tonumber(stamp) or os.time()
    local date      = os.date('*t', stamp)
    local offset    = offset(stamp)
    local utcD      = os.date('*t', stamp - offset)
    if      (not date.isdst)    and utcD.isdst       then    -- Still Summer!
        utcD        = os.date('*t', stamp - offset - 3600)
    elseif  date.isdst          and (not utcD.isdst) then    -- Not yet Winter!
        local nextUTCD = os.date('*t', stamp - offset + 3600)
        utcD        = os.date('*t', stamp - offset + 3600)
        if nextUTCD.isdst  == false then
            -- If this is the first of the two hours affected by DST, add something to the date.
        else
            -- os.date does not want to show the skipped hour; so subtract manually.
            local bangOffset = stamp - os.time(os.date('!*t', stamp))
            utcD.hour = utcD.hour - 1
        end
    end
    utcD.isdst      = nil
    return utcD
end

local localDateToTimestamp = os.time
local function localDateToUTCDate(localDate) return utcDate(localDateToTimestamp(localDate)) end

local function utcDateToTimestamp(utcD)
    local stamp = os.time(utcD)
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

local function utcDateToLocalDate(utcD)   return os.date('*t', utcDateToTimestamp(utcD)) end

-- Base functions are local for speed.
local hora = {
    offset                  = offset,
    localDate               = localDate,
    utcDate                 = utcDate,
    localDateToTimestamp    = localDateToTimestamp,
    localDateToUTCDate      = localDateToUTCDate,
    utcDateToTimestamp      = utcDateToTimestamp,
    utcDateToLocalDate      = utcDateToLocalDate,
}

function hora.ISO8601Date(stamp)
    if type(stamp) == "number" and stamp >= 0 then
        if stamp == 0 then
            return ''
        else
            local stamp = stamp or scheduler.time()
            local offset = hora.offset(stamp) / 3600
            local pre = '+'
            if offset < 0 then
                pre = '-'
                offset = offset * -1
            end
            local subsecond = stamp - math.floor(stamp)
            local now = os.date('*t', stamp)
            stamp = math.floor(stamp)
            if subsecond ~= 0 then
                now.sec = now.sec + subsecond
            else
                subsecond = nil
            end
            if now.sec == 60 then
                now.sec = (subsecond ~= 0 and 59.99) or 59
            end
            return string.format((subsecond     and '%04d-%02d-%02dT%02d:%02d:%06.3f%s%02d:%02d')
                                                or  '%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d',
                now.year, now.month, now.day, now.hour, now.min, now.sec,
                pre, math.floor(offset), math.floor((offset-math.floor(offset))*60))
        end
    else
        return nil, "Please pass a positive number."
    end
end
function hora.ISO8601DateToTimestamp(str)
    if str == '' then
        return 0
    elseif type(str) == "string" then
        local d = {}
        -- Try to match the UTC offset in minute resolution, first.
        d.offSign, d.offHour, d.offMin = str:match('([+-])(%d%d):?(%d%d)[ \t]*$')
        if not (d.offSign and d.offHour and d.offMin) then
            d.offSign, d.offHour = str:match('([+-])(%d%d)[ \t]*$')
        end
        -- Both no timezone and 'Z' mean UTC.
        if (not (d.offSign and d.offHour)) or str:match('Z[ \t]*$') then
            d.offSign, d.offHour = '+', 0
        end
        if not d.offMin then d.offMin = 0 end
        local offset = tonumber(d.offHour) * 3600 + tonumber(d.offMin) * 60
        if d.offSign == '-' then
            offset = -1 * offset
        end
        d = {}
        -- Match subsecond precision.
        d.year, d.month, d.day, d.hour, d.min, d.sec        = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)T(%d%d):?(%d%d):?(%d%d%.%d+)')
        local subsecond = 0
        -- Match second precision.
        if not (d.year and d.month and d.day and d.hour and d.min and d.sec) then
            d.year, d.month, d.day, d.hour, d.min, d.sec    = str:match('^[ \t]*(%d%d%d%d)%-?(%d%d)%-?(%d%d)T(%d%d):?(%d%d):?(%d%d)')
        else
            subsecond = d.sec - math.floor(d.sec)
            d.sec = math.floor(d.sec)
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
            return hora.utcDateToTimestamp(d) - offset + subsecond
        end
    else
        return nil, "Please pass a string."
    end
end

function hora.ISO8601Duration(seconds)
    if type(seconds) == "number" and seconds >= 0 then
        if seconds == 0 then
            return "PT0H"
        end
        local seconds = seconds
        local weeks =   math.floor(seconds / (7 * 24 * 3600))
        seconds = seconds - weeks * 7 * 24 * 3600
        local days =    math.floor(seconds / (24 * 3600))
        seconds = seconds - days * 24 * 3600
        local hours =   math.floor(seconds / 3600)
        seconds = seconds - hours * 3600
        local mins =   math.floor(seconds / 60)
        seconds = seconds - mins * 60
        local insertedT = false
        local result = {'P'}
        if weeks > 0 then
            table.insert(result, weeks)
            table.insert(result, 'W')
        end
        if days > 0 then
            table.insert(result, days)
            table.insert(result, 'D')
        end
        if hours > 0 then
            if not insertedT then
                insertedT = true
                table.insert(result, 'T')
            end
            table.insert(result, hours)
            table.insert(result, 'H')
        end
        if mins > 0 then
            if not insertedT then
                insertedT = true
                table.insert(result, 'T')
            end
            table.insert(result, mins)
            table.insert(result, 'M')
        end
        if seconds > 0 then
            if not insertedT then
                insertedT = true
                table.insert(result, 'T')
            end
            table.insert(result, seconds)
            table.insert(result, 'S')
        end
        return table.concat(result)
    else
        return nil, "Please pass a positive number."
    end
end

local letMult = {
    S = 1,
    M = 60,
    H = 3600,
    D = 86400,
    W = 604800,
}

function hora.ISO8601DurationToSeconds(str)
    if type(str) == "string" then
        local seconds = nil
        local days, time = str:match("^P([%dDW]*)T?([%dSMH]*)")
        if not (days and time) then return nil, "Not an ISO8601 Duration." end
        for num, let in time:gmatch("(%d+)([SMH])") do
            seconds = (seconds or 0) + tonumber(num) * letMult[let]
        end
        for num, let in days:gmatch("(%d+)([DW])") do
            seconds = (seconds or 0) + tonumber(num) * letMult[let]
        end
        return seconds
    else
        return nil, "Please pass a string."
    end
end

-- RFC2616 (and RFC850 and RFC1123 and ANSI C asctime()) months and days.
local months = {
    "Jan",      "Feb",      "Mar",      "Apr",      "May",      "Jun",      "Jul",      "Aug",      "Sep",      "Oct",      "Nov",      "Dec",
    Jan = 1,    Feb = 2,    Mar = 3,    Apr = 4,    May = 5,    Jun = 6,    Jul = 7,    Aug = 8,    Sep = 9,    Oct = 10,   Nov = 11,   Dec = 12,
}
local days = {
    "Sun",      "Mon",      "Tue",      "Wed",      "Thu",      "Fri",      "Sat",
    Sun = 1,    Mon = 2,    Tue = 3,    Wed = 4,    Thu = 5,    Fri = 6,    Sat = 7,
}

--- Produce RFC1123 dates, e.g. Sun, 06 Nov 1994 08:49:37 GMT
-- \publicfunction{util.RFC1123Date}{Produce RFC1123 dates, e.g. Sun, 06 Nov 1994 08:49:37 GMT}{
-- \param{stamp}{\myref{d:unix-timestamp}{The timestamp to convert to an RFC1123 date string.}
-- \result{\myref{d:string}}{The RFC1123 date string.}
-- }
function hora.RFC1123Date(stamp)
    local utcD = utcDate(stamp)
    return string.format('%s, %02d %s %04d %02d:%02d:%02d GMT', days[utcD.wday], utcD.day, months[utcD.month], utcD.year, utcD.hour, utcD.min, math.floor(utcD.sec))
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
                local now = os.date()
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
