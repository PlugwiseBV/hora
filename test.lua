#!/usr/bin/luajit

local hora = require "hora"

-- This range includes a couple of DST changes and a leap year.
local startT, endT = os.time({year = 2018, month = 01, day = 01}), os.time({year = 2020, month = 01, day = 01})
-- This range is for DST -> no-DST testing.
--local startT, endT = os.time({year = 2012, month = 10, day = 26, hour = 23}), os.time({year = 2012, month = 10, day = 28, hour = 04})
-- This range is for no-DST -> DST testing.
--local startT, endT = os.time({year = 2012, month = 03, day = 24, hour = 23}), os.time({year = 2012, month = 03, day = 25, hour = 07})
local jump = 900 -- 15 minutes
local day_sec = 86400 -- 24H
local errors = 0

local function check(cond, msg)
    if not cond then
        errors = errors + 1
        print(msg)
    end
end

local function compareDateTables(tableA, tableB)
    for key,value in pairs(tableA) do
        if tableA[key] ~= tableB[key] then
            return false
        end
    end
    return true
end

local origTZ = io.open('/etc/timezone'):read('*all')

-- Set origTZ last to correct the timezone.
local timezones = {'Africa/Johannesburg', 'Africa/Windhoek', 'Africa/Khartoum', 'Australia/Tasmania', 'America/Kralendijk', 'Asia/Colombo', origTZ}

local lastErrors    = errors
local ret
print('\n\n\tTesting range: '..os.date('%c', startT)..', '..os.date('%c', endT)..' in increments of '..jump..' seconds.\n')
for i, tz in ipairs(timezones) do
    assert(os.execute('sudo timedatectl set-timezone '..tz))
    print('\t\tTesting timezone: '..tz)
    local lastUTCDate   = hora.utcDate(startT - jump)
    local lastISODate   = hora.ISO8601Date(startT - jump)
    local lastRFCDate   = hora.RFC1123Date(startT - jump)
    for stamp = startT, endT, jump do
        -- Test utcDate() for monotonic time increase.
        local thisUTCDate = hora.utcDate(stamp)
        local dt = ((thisUTCDate.hour - lastUTCDate.hour) * 60 + (thisUTCDate.min - lastUTCDate.min)) * 60 + (thisUTCDate.sec - lastUTCDate.sec)
        check(jump == dt or jump == (day_sec + dt), "hora.utcDate fails for: "..stamp..' ('..os.date('%c', stamp).."); does not increase monotonically ("..dt.."; should be "..jump..")")

        --  Test utcDateToTimestamp() in terms of utcDate()
        ret = hora.utcDateToTimestamp(thisUTCDate)
        --print(stamp, ret, os.date('%c', stamp), os.date('%c', ret), inter.hour, inter.min)
        check(stamp == ret, "hora.utcDateToTimestamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')'..' ('..os.date('%c', ret)..')')

        -- Test localDateToTimestamp() against os.date().
        ret = hora.localDateToTimestamp(os.date('*t', stamp))
        check(stamp == ret, "hora.localDateToTimestamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test localDate() in terms of localDateToTimestamp()
        ret = hora.localDateToTimestamp(hora.localDate(stamp))
        check(stamp == ret, "hora.localDate fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test localDateToUTCDate() in terms of utcDateToTimestamp() and localDate()
        ret = hora.utcDateToTimestamp(hora.localDateToUTCDate(hora.localDate(stamp)))
        check(stamp == ret, "hora.localDateToUTCDate fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test utcDateToLocalDate() in terms of localDateToTimestamp() and utcDate()
        ret = hora.localDateToTimestamp(hora.utcDateToLocalDate(hora.utcDate(stamp)))
        check(stamp == ret, "hora.utcDateToLocalDate fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..')')

        -- Test RFC1123Date() for monotonic time increase.
        local thisRFCDate = hora.RFC1123Date(stamp)
        local lastH, lastM, lastS  = lastRFCDate:match('(%d%d):(%d%d):(%d%d) GMT$')
        local thisH, thisM, thisS  = thisRFCDate:match('(%d%d):(%d%d):(%d%d) GMT$')
        local lastTime = (((lastH * 60 + lastM) * 60) + lastS)
        local thisTime = (((thisH * 60 + thisM) * 60) + thisS)
        local dt = thisTime - lastTime
        --print(thisRFCDate, lastRFCDate)
        check(jump == dt or jump == (day_sec + dt), "hora.RFC1123Date fails for: "..stamp..' ('..os.date('%c', stamp).."); does not increase monotonically ("..dt.."; should be "..jump..")")

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
        check(jump == dt or jump == (day_sec + dt), "hora.ISO8601Date fails for: "..stamp..' ('..os.date('%c', stamp).."); does not increase monotonously ("..dt.."; should be "..jump..")")

        -- Test ISO8601DateToTimestamp() in terms of ISO8601Date()
        ret = hora.ISO8601DateToTimestamp(thisISODate)
        --print(os.date('%c', stamp), thisISODate)
        check(stamp == ret, "hora.ISO8601DateToTimestamp fails for: "..stamp..'; is '..ret..' ('..os.date('%c', stamp)..'), ('..thisISODate..')')

        -- Test the date increment and decrement feature for sub-day steps
        local curDateTable = hora.localDate(stamp)
        -- Make a deep copy of the original to ensure that the increment and decrement functions do not change the original table
        local curDateTableCopy = {}
        for key,value in pairs(curDateTable) do
            curDateTableCopy[key] = value
        end
        -- Increment tests
        local incrementedTable = hora.incrementDateTable(curDateTable, "PT1S")
        check(compareDateTables(curDateTable, curDateTableCopy), "hora.incrementDateTable fails: changes original table")
        check(hora.localDateToTimestamp(incrementedTable) - stamp == 1, string.format("hora.incrementTable fails: adding one second results in %d. Expected: %d", hora.localDateToTimestamp(incrementedTable), stamp + 1))
        local incrementedTable = hora.incrementDateTable(curDateTable, "PT4H")
        check(compareDateTables(curDateTable, curDateTableCopy), "hora.incrementDateTable fails: changes original table")
        check(hora.localDateToTimestamp(incrementedTable) - stamp == 14400, string.format("hora.incrementTable fails: adding four hours results in %d. Expected: %d", hora.localDateToTimestamp(incrementedTable), stamp + 14400))
        local incrementedTable = hora.incrementDateTable(curDateTable, "P1D")
        check(compareDateTables(curDateTable, curDateTableCopy), "hora.incrementDateTable fails: changes original table")
        if incrementedTable.hour == curDateTable.hour + 1 then
            incrementedTable.hour = incrementedTable.hour - 1
            check(hora.localDate((hora.localDateToTimestamp(incrementedTable))).hour == curDateTable.hour - 1 and incrementedTable.min == curDateTable.min and incrementedTable.sec == curDateTable.sec and incrementedTable.day ~= curDateTable.day,
                  string.format("hora.incrementDateTable fails: a one day increase leads to unexpected results. Expected hour, min, sec: %d, %d, %d, got: %d, %d, %d",
                  curDateTable.hour - 1, curDateTable.min, curDateTable.sec, hora.localDate((hora.localDateToTimestamp(incrementedTable))).hour, incrementedTable.min, incrementedTable.sec))
        else
            check(incrementedTable.hour == curDateTable.hour and incrementedTable.min == curDateTable.min and incrementedTable.sec == curDateTable.sec and incrementedTable.day ~= curDateTable.day,
                  string.format("hora.incrementDateTable fails: a one day increase leads to unexpected results. Expected hour, min, sec: %d, %d, %d, got: %d, %d, %d",
                  curDateTable.hour, curDateTable.min, curDateTable.sec, incrementedTable.hour, incrementedTable.min, incrementedTable.sec))
        end
        -- Decrement tests
        local decrementedTable = hora.decrementDateTable(curDateTable, "PT1S")
        check(compareDateTables(curDateTable, curDateTableCopy), "hora.decrementDateTable fails: changes original table")
        check(hora.localDateToTimestamp(decrementedTable) - stamp == -1, string.format("hora.decrementTable fails: adding one second results in %d. Expected: %d", hora.localDateToTimestamp(decrementedTable), stamp -1))
        local decrementedTable = hora.decrementDateTable(curDateTable, "PT4H")
        check(compareDateTables(curDateTable, curDateTableCopy), "hora.decrementDateTable fails: changes original table")
        check(hora.localDateToTimestamp(decrementedTable) - stamp == -14400, string.format("hora.decrementTable fails: adding four hours results in %d. Expected: %d", hora.localDateToTimestamp(decrementedTable), stamp - 14400))
        local decrementedTable = hora.decrementDateTable(curDateTable, "P1D")
        check(compareDateTables(curDateTable, curDateTableCopy), "hora.decrementDateTable fails: changes original table")
        if decrementedTable.hour == curDateTable.hour - 1 then
            decrementedTable.hour = decrementedTable.hour + 1
            check(hora.localDate((hora.localDateToTimestamp(decrementedTable))).hour == curDateTable.hour + 1 and decrementedTable.min == curDateTable.min and decrementedTable.sec == curDateTable.sec and decrementedTable.day ~= curDateTable.day,
                  string.format("hora.decrementDateTable fails: a one day decrease leads to unexpected results. Expected hour, min, sec: %d, %d, %d, got: %d, %d, %d",
                  curDateTable.hour + 1, curDateTable.min, curDateTable.sec, hora.localDate((hora.localDateToTimestamp(decrementedTable))).hour, decrementedTable.min, decrementedTable.sec))
        else
            check(decrementedTable.hour == curDateTable.hour and decrementedTable.min == curDateTable.min and decrementedTable.sec == curDateTable.sec and decrementedTable.day ~= curDateTable.day,
                  string.format("hora.decrementDateTable fails: a one day decrease leads to unexpected results. Expected hour, min, sec: %d, %d, %d, got: %d, %d, %d",
                  curDateTable.hour, curDateTable.min, curDateTable.sec, decrementedTable.hour, decrementedTable.min, decrementedTable.sec))
        end

        -- Set last values.
        lastUTCDate = thisUTCDate
        lastISODate = thisISODate
        lastRFCDate = thisRFCDate
        lastErrors  = errors
    end
end

-- Test ISO8601Date() to floor subseconds correctly.
local subseconds = {
    [1450000000            ] = "46:40[^%.]",
    [1450000000 -      1e-6] = "46:39%.999",
    [1450000000 -   3566e-6] = "46:39%.996",
    [1450000000 - 887766e-6] = "46:39%.112",
    [1450000000 - 999999e-6] = "46:39%.000",
    [1449999999            ] = "46:39[^%.]",
}
for stamp, match in pairs(subseconds) do
    assert(hora.ISO8601Date(stamp):match(match), "hora.ISO8601Date fails to properly floor subseconds for: "..stamp.."; which should match "..match)
end

for _, duration in ipairs({0, 10, 45, 60, 100, 120, 200, 300, 360, 900, 1000, 2700, 3600, 4000, 7200, 8000, 100000, 10000000}) do
    ret = hora.ISO8601DurationToSeconds(hora.ISO8601Duration(duration))
    check(duration == ret, "hora.ISO8601DurationToSeconds and/or hora.ISO8601Duration fail for: "..duration..'; is '..ret)
end

if 0 == errors then
    print('\t\tSuccess!')
else
    print(string.format('\n\t\tErrors: %i\n', errors))
end
