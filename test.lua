
local hora = require "hora"

-- This range includes a couple of DST changes and a leap year.
local startT, endT = os.time({year = 2011, month = 01, day = 01}), os.time({year = 2013, month = 01, day = 01})
-- This range is for DST -> no-DST testing.
--local startT, endT = os.time({year = 2012, month = 10, day = 26, hour = 23}), os.time({year = 2012, month = 10, day = 28, hour = 04})
-- This range is for no-DST -> DST testing.
--local startT, endT = os.time({year = 2012, month = 03, day = 24, hour = 23}), os.time({year = 2012, month = 03, day = 25, hour = 07})
local jump = 900 -- 15 minutes

local errors = 0

local function check(cond, msg)
    if not cond then
        errors = errors + 1
        print(msg)
    end
end

local origTZ = io.open('/etc/timezone'):read('*all')

-- Set origTZ last to correct the timezone.
local timezones = {'Africa/Johannesburg', 'Africa/Windhoek', 'Africa/Khartoum', 'Australia/Tasmania', 'America/Kralendijk', 'Asia/Colombo', origTZ}

local lastErrors    = errors
local ret
print('\n\n\tTesting range: '..os.date('%c', startT)..', '..os.date('%c', endT)..' in increments of '..jump..' seconds.\n')
for i, tz in ipairs(timezones) do
    local etcTZ = assert(io.open('/etc/timezone', 'w'))
    assert(etcTZ:write(tz))
    assert(etcTZ:close())
    assert(os.execute('sudo dpkg-reconfigure --frontend noninteractive tzdata'))
    print('\n\t\tTesting timezone: '..tz)
    local lastUTCDate   = hora.utcDate(startT - jump)
    local lastISODate   = hora.ISO8601Date(startT - jump)
    local lastRFCDate   = hora.RFC1123Date(startT - jump)
    for stamp = startT, endT, jump do
        -- Test utcDate() for monotonic time increase.
        local thisUTCDate = hora.utcDate(stamp)
        local dt = ((thisUTCDate.hour - lastUTCDate.hour) * 60 + (thisUTCDate.min - lastUTCDate.min)) * 60 + (thisUTCDate.sec - lastUTCDate.sec)
        check(jump == dt or jump == (86400 + dt), "hora.utcDate fails for: "..stamp..' ('..os.date('%c', stamp).."); does not increase monotonically ("..dt.."; should be "..jump..")")

        --  Test utcDateToStamp() in terms of utcDate()
        ret = hora.utcDateToStamp(thisUTCDate)
        --print(stamp, ret, os.date('%c', stamp), os.date('%c', ret), inter.hour, inter.min)
        check(stamp == ret, "hora.utcDateToStamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')'..' ('..os.date('%c', ret)..')')

        -- Test localDateToStamp() against os.date().
        ret = hora.localDateToStamp(os.date('*t', stamp))
        check(stamp == ret, "hora.localDateToStamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test localDate() in terms of localDateToStamp()
        ret = hora.localDateToStamp(hora.localDate(stamp))
        check(stamp == ret, "hora.localDate fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test localDateToUTCDate() in terms of utcDateToStamp() and localDate()
        ret = hora.utcDateToStamp(hora.localDateToUTCDate(hora.localDate(stamp)))
        check(stamp == ret, "hora.localDateToUTCDate fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test utcDateToLocalDate() in terms of localDateToStamp() and utcDate()
        ret = hora.localDateToStamp(hora.utcDateToLocalDate(hora.utcDate(stamp)))
        check(stamp == ret, "hora.utcDateToLocalDate fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test RFC1123Date() for monotonic time increase.
        local thisRFCDate = hora.RFC1123Date(stamp)
        local lastH, lastM, lastS  = lastRFCDate:match('(%d%d):(%d%d):(%d%d) GMT$')
        local thisH, thisM, thisS  = thisRFCDate:match('(%d%d):(%d%d):(%d%d) GMT$')
        local lastTime = (((lastH * 60 + lastM) * 60) + lastS)
        local thisTime = (((thisH * 60 + thisM) * 60) + thisS)
        local dt = thisTime - lastTime
        --print(thisRFCDate, lastRFCDate)
        check(jump == dt or jump == (86400 + dt), "hora.RFC1123Date fails for: "..stamp..' ('..os.date('%c', stamp).."); does not increase monotonically ("..dt.."; should be "..jump..")")

        -- Test HTTPDateToTimestamp() in terms of RFC1123Date()
        ret = hora.HTTPDateToTimestamp(thisRFCDate)
        --print(os.date('%c', stamp), thisRFCDate)
        check(stamp == ret, "hora.HTTPDateToTimestamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..'), ('..thisRFCDate..')')

        -- Test ISO8601Date() for monotonic time increase.
        local thisISODate = hora.ISO8601Date(stamp)
        local lastH, lastM, lastS, lastOffSign, lastOffH, lastOffM  = lastISODate:match('T(%d%d).?(%d%d).?(%d%d%.?%d*)([+-])(%d%d).?(%d%d)$')
        local thisH, thisM, thisS, thisOffSign, thisOffH, thisOffM  = thisISODate:match('T(%d%d).?(%d%d).?(%d%d%.?%d*)([+-])(%d%d).?(%d%d)$')
        local lastTime = (((lastH * 60 + lastM) * 60) + lastS) + (lastOffSign == '+' and -60 or 60) * (lastOffH * 60 + lastOffM)
        local thisTime = (((thisH * 60 + thisM) * 60) + thisS) + (thisOffSign == '+' and -60 or 60) * (thisOffH * 60 + thisOffM)
        local dt = thisTime - lastTime
        --print(thisISODate, lastISODate)
        check(jump == dt or jump == (86400 + dt), "hora.ISO8601Date fails for: "..stamp..' ('..os.date('%c', stamp).."); does not increase monotonically ("..dt.."; should be "..jump..")")

        -- Test ISO8601DateToTimestamp() in terms of ISO8601Date()
        ret = hora.ISO8601DateToTimestamp(thisISODate)
        --print(os.date('%c', stamp), thisISODate)
        check(stamp == ret, "hora.ISO8601DateToTimestamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..'), ('..thisISODate..')')

        if lastErrors ~= errors then    print(os.date('\27[01;31m%c failed!\27[0m'))end

        -- Set last values.
        lastUTCDate = thisUTCDate
        lastISODate = thisISODate
        lastRFCDate = thisRFCDate
        lastErrors  = errors
    end
end

for _, duration in ipairs({0, 10, 45, 60, 100, 120, 200, 300, 360, 900, 1000, 2700, 3600, 4000, 7200, 8000, 100000, 10000000}) do
    ret = hora.ISO8601DurationToSeconds(hora.ISO8601Duration(duration))
    check(duration == ret, "hora.ISO8601DurationToSeconds and/or hora.ISO8601Duration fail for: "..duration..'; is '..ret)
end

if 0 == errors then
    print('\n\t\tSuccess!\n\n')
else
    print(string.format('\n\t\tErrors: %i\n', errors))
end
