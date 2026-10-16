-- Grand Map Stability diagnostics and opt-in satellite exploration.

local PREFIX = "[GMS]"
local SAMPLE_INTERVAL = 5
local SATELLITE_PREFIX = "GMS_SATELLITE_"
local SATELLITE_SCHEMA_VERSION = 1
local SATELLITE_LAST_WORK_TURN_KEY = "GMS_SATELLITE_LAST_WORK_TURN"
local SATELLITE_LAST_PLAYER_KEY = "GMS_SATELLITE_LAST_PLAYER"
local CLIMATE_DIAGNOSTICS_VERSION = 1
local CLIMATE_FIRST_TURN_KEY = "GMS_CLIMATE_FIRST_SEA_LEVEL_TURN"
local CLIMATE_FIRST_POINTS_KEY = "GMS_CLIMATE_FIRST_SEA_LEVEL_POINTS"
local CLIMATE_FIRST_EVENT_KEY = "GMS_CLIMATE_FIRST_SEA_LEVEL_EVENT"
local SNAPSHOT_OBJECT_BUDGET_DEFAULT = 10000
local SNAPSHOT_OBJECT_BUDGET_MAX = 100000

local State = {
    Initialized = false,
    LastTurn = nil,
    LastSnapshotTurn = nil,
    LastClimateTurn = nil,
    ClimateApiLogged = false,
    EventCounts = {},
}

local function ToText(value)
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local function Log(message)
    print(PREFIX .. " " .. message)
end

local function SafeCall(label, callback)
    local ok, first, second, third = pcall(callback)
    if not ok then
        Log("error label=" .. label .. " message=" .. ToText(first))
        return nil
    end
    return first, second, third
end

local function HasCallable(object, methodName)
    if object == nil then return false end
    local ok, method = pcall(function() return object[methodName] end)
    return ok and type(method) == "function"
end

local function ReadMember(object, memberName)
    if object == nil then return nil, false end
    local ok, value = pcall(function() return object[memberName] end)
    return value, ok
end

local function ReadConfig(key, defaultValue)
    if HasCallable(GameConfiguration, "GetValue") then
        local value = SafeCall("config_" .. key, function()
            return GameConfiguration.GetValue(key)
        end)
        if value ~= nil then
            return value
        end
    end
    if defaultValue ~= nil then
        return defaultValue
    end
    return "UNKNOWN"
end

local function IsTrue(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function ReadMapConfig(key)
    if HasCallable(MapConfiguration, "GetValue") then
        local value = SafeCall("map_config_" .. key, function()
            return MapConfiguration.GetValue(key)
        end)
        if value ~= nil then return value end
    end
    return "UNKNOWN"
end

local TimingClockSource="UNKNOWN"
local function ReadClockMs()
    if HasCallable(Automation,"GetTime") then
        local value=SafeCall("native_clock",function() return Automation.GetTime() end)
        if type(value)=="number" and value==value and value>=0 and value<math.huge then
            TimingClockSource="Automation.GetTime resolution_ms=1";return value*1000
        end
    end
    TimingClockSource="os.clock resolution_ms=UNKNOWN"
    if not HasCallable(os, "clock") then
        return nil
    end

    local value = SafeCall("clock", function()
        return os.clock()
    end)
    if value == nil then
        return nil
    end
    return value * 1000
end

local function TimingResult(startedMs,finishedMs)
    if finishedMs<startedMs then return "UNKNOWN clock_reversed=true" end
    local elapsed=finishedMs-startedMs
    local value=elapsed==0 and "below_clock_resolution" or string.format("%.3f",elapsed)
    return value.." clock="..TimingClockSource
end

local function CountList(list)
    if list == nil then
        return 0
    end

    local count = 0
    for _ in ipairs(list) do
        count = count + 1
    end
    return count
end

local function Integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function PlayerID(player, label)
    if player == nil then return nil end
    local id = SafeCall(label or "player_id", function() return player:GetID() end)
    if not Integer(id) or id >= 64 then return nil end
    return id
end

local function ValidRoster(list, expectedMajor)
    if type(list) ~= "table" or #list > 64 then return false end
    local seen, count = {}, 0
    for key in pairs(list) do
        if not Integer(key) or key < 1 or key > #list then return false end
        count = count + 1
    end
    if count ~= #list then return false end
    for _, player in ipairs(list) do
        local id = PlayerID(player, "roster_player_id")
        if id == nil or seen[id] then return false end
        if HasCallable(player, "IsAlive") then
            local aliveOK, alive = pcall(function() return player:IsAlive() end)
            if not aliveOK or alive ~= true then return false end
        end
        if expectedMajor ~= nil and HasCallable(player, "IsMajor") then
            local majorOK, major = pcall(function() return player:IsMajor() end)
            if not majorOK or major ~= expectedMajor then return false end
        end
        seen[id] = true
    end
    return true
end

local function GetAliveMajors()
    if not HasCallable(PlayerManager, "GetAliveMajors") then
        return {}, false
    end
    local majors = SafeCall("alive_majors", function()
        return PlayerManager.GetAliveMajors()
    end)
    if not ValidRoster(majors, true) then
        return {}, false
    end
    return majors, true
end

local function GetAliveMinors()
    if not HasCallable(PlayerManager, "GetAliveMinors") then
        return nil
    end
    local minors = SafeCall("alive_minors", function()
        return PlayerManager.GetAliveMinors()
    end)
    if not ValidRoster(minors, false) then
        return nil
    end
    return minors
end

local function SnapshotObjectBudget()
    local value = tonumber(ReadConfig("GMS_SNAPSHOT_OBJECT_BUDGET", SNAPSHOT_OBJECT_BUDGET_DEFAULT))
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        value = SNAPSHOT_OBJECT_BUDGET_DEFAULT
    end
    return math.max(1, math.min(SNAPSHOT_OBJECT_BUDGET_MAX, math.floor(value)))
end

local function CountPlayerObjects(players, budget)
    local cityCount = 0
    local unitCount = 0
    local scanned = 0
    local incompleteReason = nil

    local function ConsumeObject()
        if scanned >= budget then
            return false
        end
        scanned = scanned + 1
        return true
    end

    local function CountCollection(collection, increment)
        if (type(collection) ~= "table" and type(collection) ~= "userdata") or not HasCallable(collection, "Members") then
            incompleteReason = "collection_unavailable"
            return false
        end
        local ok, completed = pcall(function()
            for _ in collection:Members() do
                if not ConsumeObject() then
                    return false
                end
                increment()
            end
            return true
        end)
        if not ok then
            incompleteReason = "iterator_failed"
            return false
        end
        if completed ~= true then
            incompleteReason = "budget_exhausted"
            return false
        end
        return true
    end

    for _, player in ipairs(players) do
        if player ~= nil then
            local playerID = PlayerID(player, "snapshot_player_id")
            if playerID == nil then
                return cityCount, unitCount, scanned, false, "player_identity_unavailable"
            end
            if not HasCallable(player, "GetCities") or not HasCallable(player, "GetUnits") then
                return cityCount, unitCount, scanned, false, "collection_unavailable"
            end
            if HasCallable(player, "GetCities") then
                local cities = SafeCall("cities_" .. ToText(playerID), function()
                    return player:GetCities()
                end)
                if not CountCollection(cities, function() cityCount = cityCount + 1 end) then
                    return cityCount, unitCount, scanned, false, incompleteReason
                end
            end

            if HasCallable(player, "GetUnits") then
                local units = SafeCall("units_" .. ToText(playerID), function()
                    return player:GetUnits()
                end)
                if not CountCollection(units, function() unitCount = unitCount + 1 end) then
                    return cityCount, unitCount, scanned, false, incompleteReason
                end
            end
        end
    end

    return cityCount, unitCount, scanned, true, nil
end

local function CountPantheons()
    local total = 0
    local used = 0
    local religion = nil

    if HasCallable(Game, "GetReligion") then
        religion = SafeCall("game_religion", function()
            return Game.GetReligion()
        end)
    end

    -- GameInfo collections are native callable tables, not Lua functions.
    -- Iterate inside pcall; a failed/unknown usage query is not an unused belief.
    local usageKnown = religion ~= nil
    local ok = pcall(function()
        for belief in GameInfo.Beliefs() do
            if belief.BeliefClassType == "BELIEF_CLASS_PANTHEON" then
                total = total + 1

                local inPantheon, inReligion = nil, nil
                if HasCallable(religion, "IsInSomePantheon") then
                    inPantheon = SafeCall("pantheon_used_" .. ToText(belief.Index), function()
                        return religion:IsInSomePantheon(belief.Index)
                    end)
                end
                if inPantheon ~= true and HasCallable(religion, "IsInSomeReligion") then
                    inReligion = SafeCall("religion_used_" .. ToText(belief.Index), function()
                        return religion:IsInSomeReligion(belief.Index)
                    end)
                end
                if inPantheon == true or inReligion == true then
                    used = used + 1
                elseif inPantheon ~= false or inReligion ~= false then
                    usageKnown = false
                end
            end
        end
    end)
    if not ok then
        Log("pantheon_beliefs_unavailable")
        return nil, nil, nil, false
    end

    if not usageKnown then return total, nil, nil, false end
    return total, used, total - used, true
end

local function CurrentTurn()
    if not HasCallable(Game, "GetCurrentGameTurn") then
        return -1
    end
    return SafeCall("current_turn", function()
        return Game.GetCurrentGameTurn()
    end) or -1
end

local function GetGameProperty(key, defaultValue)
    if not HasCallable(Game, "GetProperty") then
        return defaultValue, false
    end
    local ok, value = pcall(function()
        return Game:GetProperty(key)
    end)
    if not ok then
        return defaultValue, false
    end
    if value == nil then
        return defaultValue, true
    end
    return value, true
end

local function SetGameProperty(key, value)
    if not HasCallable(Game, "SetProperty") then
        Log("game_property_set_unavailable key=" .. key)
        return false
    end
    local result = SafeCall("game_property_set_" .. key, function()
        return Game:SetProperty(key, value) ~= false
    end)
    return result == true
end

local function ClimateValue(methodName)
    if not HasCallable(GameClimate, methodName) then
        return nil, false
    end
    local value = SafeCall("climate_" .. methodName, function()
        return GameClimate[methodName]()
    end)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return nil, false
    end
    return value, true
end

local function FindClimateEvents(currentPoints)
    -- Native GameInfo rows are callable userdata, not Lua functions.
    local rows, readable = ReadMember(GameInfo, "RandomEvents")
    if not readable or rows == nil then
        return nil, nil, nil
    end

    local seaLevelEvents = SafeCall("climate_random_events", function()
        local events = {}
        for row in rows() do
            if row.EffectOperatorType == "SEA_LEVEL" then
                events[#events + 1] = row
            end
        end
        return events
    end)
    if seaLevelEvents == nil then
        return nil, nil, nil
    end
    table.sort(seaLevelEvents, function(left, right)
        return (tonumber(left.Index) or 0) < (tonumber(right.Index) or 0)
    end)

    local firstEvent = seaLevelEvents[1]
    local currentEvent = nil
    if currentPoints ~= nil then
        for _, row in ipairs(seaLevelEvents) do
            if tonumber(row.ClimateChangePoints) == tonumber(currentPoints) then
                currentEvent = row
                break
            end
        end
    end

    local phase = nil
    if currentEvent ~= nil then
        for index, row in ipairs(seaLevelEvents) do
            if row == currentEvent then
                phase = index
                break
            end
        end
    end
    return firstEvent, currentEvent, phase
end

local function ClimateText(value, available)
    if not available then
        return "UNKNOWN"
    end
    return ToText(value)
end

local function ValidClimateFirstTurn(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
        and value >= 0 and value == math.floor(value)
end

local function ValidClimateFirstPoints(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
        and value >= 0
end

local function LogClimateSnapshot(triggerPlayerID, turn)
    if not IsTrue(ReadConfig("GMS_CLIMATE_DIAGNOSTICS")) or turn < 0 then
        return
    end
    if State.LastClimateTurn == turn then
        return
    end
    State.LastClimateTurn = turn

    local points, pointsAvailable = ClimateValue("GetClimateChangeForLastSeaLevelEvent")
    local level, levelAvailable = ClimateValue("GetClimateChangeLevel")
    local realism, realismAvailable = ClimateValue("GetClimateChangeFromRealism")
    local temperature, temperatureAvailable = ClimateValue("GetClimateChangeFromTemperature")
    local nextRise, nextRiseAvailable = ClimateValue("GetNextSeaLevelRiseTurns")
    local iceLoss, iceLossAvailable = ClimateValue("GetNextIceLossTurns")
    local flooded, floodedAvailable = ClimateValue("GetTilesFlooded")
    local submerged, submergedAvailable = ClimateValue("GetTilesSubmerged")
    local firstEvent, currentEvent, phase = FindClimateEvents(pointsAvailable and points or nil)

    if not State.ClimateApiLogged then
        State.ClimateApiLogged = true
        Log("climate_api version=" .. ToText(CLIMATE_DIAGNOSTICS_VERSION)
            .. " points=" .. ToText(pointsAvailable)
            .. " level=" .. ToText(levelAvailable)
            .. " realism=" .. ToText(realismAvailable)
            .. " temperature=" .. ToText(temperatureAvailable)
            .. " next_rise=" .. ToText(nextRiseAvailable)
            .. " ice_loss=" .. ToText(iceLossAvailable)
            .. " flooded=" .. ToText(floodedAvailable)
            .. " submerged=" .. ToText(submergedAvailable)
            .. " sea_level_rows=" .. ToText(firstEvent ~= nil))
    end

    local firstTurn, firstTurnReadable = GetGameProperty(CLIMATE_FIRST_TURN_KEY, nil)
    local firstPoints, firstPointsReadable = GetGameProperty(CLIMATE_FIRST_POINTS_KEY, nil)
    local firstEventIndex, firstEventReadable = GetGameProperty(CLIMATE_FIRST_EVENT_KEY, nil)
    local firstRecordValid = firstTurnReadable and firstPointsReadable and firstEventReadable and firstTurn == nil
    if not firstTurnReadable or not firstPointsReadable or not firstEventReadable then
        Log("climate_first_sea_level_existing_unreadable")
    end
    if firstTurnReadable and firstTurn ~= nil and not ValidClimateFirstTurn(firstTurn) then
        Log("climate_first_sea_level_existing_invalid field=turn")
        firstRecordValid = false
    elseif firstTurnReadable and ValidClimateFirstTurn(firstTurn) then
        firstRecordValid = false
    end
    if firstPointsReadable and firstPoints ~= nil and not ValidClimateFirstPoints(firstPoints) then
        Log("climate_first_sea_level_existing_invalid field=points")
        firstRecordValid = false
    end
    if not firstEventReadable then
        firstEventIndex = nil
    end
    if pointsAvailable and ValidClimateFirstPoints(points) and firstRecordValid then
        local stored = SetGameProperty(CLIMATE_FIRST_POINTS_KEY, points)
        if stored then
            stored = SetGameProperty(CLIMATE_FIRST_EVENT_KEY,
                currentEvent ~= nil and ToText(currentEvent.Index) or "UNKNOWN")
        end
        if stored then
            stored = SetGameProperty(CLIMATE_FIRST_TURN_KEY, turn)
        end
        if stored then
            firstTurn = turn
            firstPoints = points
            firstEventIndex = currentEvent ~= nil and ToText(currentEvent.Index) or "UNKNOWN"
            Log("climate_first_sea_level turn=" .. ToText(turn)
                .. " points=" .. ToText(points)
                .. " event_index=" .. ToText(firstEventIndex)
                .. " phase=" .. ClimateText(phase, phase ~= nil)
                .. " semantics=FIRST_OBSERVED")
        else
            Log("climate_first_sea_level_store_failed turn=" .. ToText(turn))
        end
    end

    Log("climate_snapshot turn=" .. ToText(turn)
        .. " trigger_player=" .. ToText(triggerPlayerID)
        .. " points=" .. ClimateText(points, pointsAvailable)
        .. " level=" .. ClimateText(level, levelAvailable)
        .. " realism=" .. ClimateText(realism, realismAvailable)
        .. " temperature=" .. ClimateText(temperature, temperatureAvailable)
        .. " current_event_index=" .. ClimateText(currentEvent ~= nil and currentEvent.Index or nil, currentEvent ~= nil)
        .. " current_phase=" .. ClimateText(phase, phase ~= nil)
        .. " first_event_turn=" .. ClimateText(firstTurn, firstTurn ~= nil)
        .. " first_event_points=" .. ClimateText(firstPoints, firstPoints ~= nil)
        .. " first_event_index=" .. ClimateText(firstEventIndex, firstEventIndex ~= nil)
        .. " next_sea_rise_turns=" .. ClimateText(nextRise, nextRiseAvailable)
        .. " next_ice_loss_turns=" .. ClimateText(iceLoss, iceLossAvailable)
        .. " tiles_flooded=" .. ClimateText(flooded, floodedAvailable)
        .. " tiles_submerged=" .. ClimateText(submerged, submergedAvailable))
end

local function GetPlayerVisibility(playerID)
    if PlayersVisibility ~= nil then
        local readable, visibility = pcall(function() return PlayersVisibility[playerID] end)
        if readable and visibility ~= nil then
            return visibility
        end
        if not readable then
            Log("player_visibility_container_unavailable player=" .. ToText(playerID))
        end
    end
    if HasCallable(PlayerVisibilityManager, "GetPlayerVisibility") then
        return SafeCall("player_visibility_" .. ToText(playerID), function()
            return PlayerVisibilityManager.GetPlayerVisibility(playerID)
        end)
    end
    return nil
end

local function GetSatelliteProperty(player, key, defaultValue)
    if not HasCallable(player, "GetProperty") then
        return defaultValue, false
    end
    local ok, value = pcall(function() return player:GetProperty(SATELLITE_PREFIX .. key) end)
    if not ok then
        return defaultValue, false
    end
    if value == nil then
        return defaultValue, true
    end
    return value, true
end

local function SetSatelliteProperty(player, key, value)
    if not HasCallable(player, "SetProperty") then
        return false
    end
    return SafeCall("satellite_property_set_" .. key, function()
        return player:SetProperty(SATELLITE_PREFIX .. key, value) ~= false
    end) == true
end

local function PauseSatelliteReveal(player, reason, turn)
    local previousReason = GetSatelliteProperty(player, "ERROR", "")
    local previousState = GetSatelliteProperty(player, "STATE", "")
    SetSatelliteProperty(player, "ERROR", reason)
    SetSatelliteProperty(player, "STATE", "PAUSED")
    if previousState ~= "PAUSED" or previousReason ~= reason then
        Log("satellite_chunk_paused player=" .. ToText(PlayerID(player, "satellite_pause_player_id"))
            .. " turn=" .. ToText(turn) .. " reason=" .. reason)
    end
end

local function QueueSatelliteReveal(playerID, turn)
    if not IsTrue(ReadConfig("GMS_SATELLITE_CHUNKED_MODE")) then
        return
    end
    if IsTrue(ReadConfig("GMS_SATELLITE_SAFE_MODE")) then
        Log("satellite_chunk_disabled_by_safe_off player=" .. ToText(playerID))
        return
    end
    local player = Players ~= nil and Players[playerID] or nil
    if not HasCallable(player, "GetProperty") or not HasCallable(player, "SetProperty") then
        Log("satellite_chunk_player_unavailable player=" .. ToText(playerID))
        return
    end
    -- A completed queue remains a durable duplicate marker for this project.
    local status, readable = GetSatelliteProperty(player, "STATE", nil)
    local schema, schemaReadable = GetSatelliteProperty(player, "SCHEMA_VERSION", nil)
    if not schemaReadable or (schema ~= nil and schema ~= SATELLITE_SCHEMA_VERSION) then
        Log("satellite_chunk_schema_unsupported player=" .. ToText(playerID))
        return
    end
    if not readable then
        Log("satellite_chunk_player_properties_unreadable player=" .. ToText(playerID))
        return
    end
    if status ~= nil then
        Log("satellite_chunk_queue_duplicate_ignored player=" .. ToText(playerID))
        return
    end
    local total = HasCallable(Map, "GetPlotCount") and SafeCall("satellite_plot_count", function()
        return Map.GetPlotCount()
    end) or nil
    if not Integer(total) or total <= 0 or not Integer(turn) then
        Log("satellite_chunk_map_unavailable player=" .. ToText(playerID))
        return
    end
    local properties = {
        { "SCHEMA_VERSION", SATELLITE_SCHEMA_VERSION }, { "CURSOR", 0 },
        { "TOTAL", total }, { "START_TURN", turn }, { "ERROR", "" },
    }
    for _, property in ipairs(properties) do
        if not SetSatelliteProperty(player, property[1], property[2]) then
            Log("satellite_chunk_queue_write_failed player=" .. ToText(playerID))
            return
        end
    end
    if SetSatelliteProperty(player, "STATE", "QUEUED") then
        Log("satellite_chunk_queue_started player=" .. ToText(playerID) .. " turn=" .. ToText(turn))
    end
end

local function ProcessSatellitePlayer(player, turn, budget)
    local startedMs = IsTrue(ReadConfig("GMS_DEBUG_TIMING")) and ReadClockMs() or nil
    local playerID = PlayerID(player, "satellite_process_player_id")
    if playerID == nil then
        Log("satellite_chunk_player_identity_unavailable turn=" .. ToText(turn))
        return
    end
    if GetSatelliteProperty(player, "SCHEMA_VERSION", nil) ~= SATELLITE_SCHEMA_VERSION then
        Log("satellite_chunk_schema_unsupported player=" .. ToText(playerID))
        return
    end
    if not HasCallable(Map, "GetPlotCount") or not HasCallable(Map, "GetPlotByIndex") then
        PauseSatelliteReveal(player, "map_api_unavailable", turn)
        return
    end
    local ok, total = pcall(Map.GetPlotCount)
    local cursorValue = GetSatelliteProperty(player, "CURSOR", nil)
    local cursor = tonumber(cursorValue)
    if not ok or not Integer(total) or total <= 0
        or total ~= GetSatelliteProperty(player, "TOTAL", nil) then
        PauseSatelliteReveal(player, "map_size_unavailable_or_changed", turn)
        return
    end
    if cursor == nil or cursor < 0 or cursor > total or cursor ~= math.floor(cursor) then
        PauseSatelliteReveal(player, "invalid_cursor", turn)
        return
    end
    local visibility = GetPlayerVisibility(playerID)
    if not HasCallable(visibility, "IsRevealed") or not HasCallable(visibility, "ChangeVisibilityCount") then
        PauseSatelliteReveal(player, "visibility_api_unavailable", turn)
        return
    end
    if not SetSatelliteProperty(player, "STATE", "RUNNING") then
        return
    end
    local examined, failure = 0, nil
    while cursor < total and examined < budget do
        examined = examined + 1
        local gotPlot, plot = pcall(Map.GetPlotByIndex, cursor)
        if not gotPlot or plot == nil then
            failure = "plot_unavailable"
            break
        end
        local queried, revealed = pcall(function()
            return visibility:IsRevealed(plot:GetX(), plot:GetY())
        end)
        if not queried or type(revealed) ~= "boolean" then
            failure = "reveal_query_failed"
            break
        end
        if not revealed then
            -- The Pirates scenario explores plots with delta 0, without adding
            -- permanent line of sight. Native behavior still requires game QA.
            local applied, result = pcall(function()
                return visibility:ChangeVisibilityCount(plot:GetIndex(), 0)
            end)
            if not applied or result == false then
                failure = "reveal_failed"
                break
            end
        end
        cursor = cursor + 1
    end
    if not SetSatelliteProperty(player, "CURSOR", cursor) then
        PauseSatelliteReveal(player, "checkpoint_write_failed", turn)
        return
    end
    if failure ~= nil then
        PauseSatelliteReveal(player, failure, turn)
        return
    end
    SetSatelliteProperty(player, "ERROR", "")
    if cursor == total then
        if SetSatelliteProperty(player, "STATE", "DONE") then
            Log("satellite_chunk_queue_completed player=" .. ToText(playerID)
                .. " turn=" .. ToText(turn) .. " processed=" .. ToText(cursor) .. " total=" .. ToText(total))
        end
    else
        Log("satellite_chunk turn=" .. ToText(turn) .. " player=" .. ToText(playerID)
            .. " cursor=" .. ToText(cursor) .. " total=" .. ToText(total)
            .. " examined=" .. ToText(examined) .. " budget=" .. ToText(budget))
    end
    if startedMs ~= nil then
        local finishedMs = ReadClockMs()
        if finishedMs ~= nil then
            Log("satellite_chunk_timing turn=" .. ToText(turn) .. " player=" .. ToText(playerID)
                .. " elapsed_ms=" .. TimingResult(startedMs, finishedMs)
                .. " examined=" .. ToText(examined) .. " budget=" .. ToText(budget)
                .. " cursor=" .. ToText(cursor) .. " total=" .. ToText(total))
        else
            Log("satellite_chunk_timing_unavailable turn=" .. ToText(turn))
        end
    end
end

local function ProcessSatelliteReveal(turn)
    if not IsTrue(ReadConfig("GMS_SATELLITE_CHUNKED_MODE"))
        or IsTrue(ReadConfig("GMS_SATELLITE_SAFE_MODE")) or turn < 0 then
        return
    end
    local lastWorkTurn, readable = GetGameProperty(SATELLITE_LAST_WORK_TURN_KEY, -1)
    if not readable or type(lastWorkTurn) ~= "number" or lastWorkTurn < -1
        or lastWorkTurn ~= math.floor(lastWorkTurn) or lastWorkTurn >= turn then
        return
    end
    local majors, majorsReadable = GetAliveMajors()
    if not majorsReadable then
        Log("satellite_major_roster_unavailable turn=" .. ToText(turn))
        return
    end
    local pending = {}
    for _, player in ipairs(majors) do
        local status = GetSatelliteProperty(player, "STATE", nil)
        if status == "QUEUED" or status == "RUNNING" or status == "PAUSED" then
            local playerID = PlayerID(player, "satellite_pending_player_id")
            if playerID == nil then
                Log("satellite_pending_identity_unavailable turn=" .. ToText(turn))
                return
            end
            pending[#pending + 1] = { Player = player, ID = playerID }
        end
    end
    if #pending == 0 then
        return
    end
    table.sort(pending, function(a, b) return a.ID < b.ID end)
    local lastPlayerValue, playerReadable = GetGameProperty(SATELLITE_LAST_PLAYER_KEY, -1)
    if not playerReadable then
        return
    end
    local lastPlayer = tonumber(lastPlayerValue) or -1
    local selected = pending[1]
    for _, entry in ipairs(pending) do
        if entry.ID > lastPlayer then
            selected = entry
            break
        end
    end
    -- Reserve this global turn's budget before reveal calls can emit events.
    if not SetGameProperty(SATELLITE_LAST_WORK_TURN_KEY, turn)
        or not SetGameProperty(SATELLITE_LAST_PLAYER_KEY, selected.ID) then
        return
    end
    local budget = tonumber(ReadConfig("GMS_SATELLITE_CHUNK_SIZE", 500)) or 500
    if budget ~= budget or budget == math.huge or budget == -math.huge then budget = 500 end
    budget = math.max(1, math.min(10000, math.floor(budget)))
    ProcessSatellitePlayer(selected.Player, turn, budget)
end

local function LogSnapshot(triggerPlayerID, turn)
    local timingEnabled = IsTrue(ReadConfig("GMS_DEBUG_TIMING"))
    local startedMs = timingEnabled and ReadClockMs() or nil
    local majors, majorsReadable = GetAliveMajors()
    if not majorsReadable then
        Log("snapshot_majors_unavailable turn=" .. ToText(turn))
        return
    end
    local minors = GetAliveMinors()
    local objectBudget = SnapshotObjectBudget()
    local cityCount, unitCount, objectsScanned, objectsComplete, objectsReason =
        CountPlayerObjects(majors, objectBudget)
    local width, height = 0, 0
    local plotCount = 0

    if HasCallable(Map, "GetGridSize") then
        width, height = SafeCall("map_grid", function()
            return Map.GetGridSize()
        end)
    end
    if HasCallable(Map, "GetPlotCount") then
        plotCount = SafeCall("map_plot_count", function()
            return Map.GetPlotCount()
        end) or 0
    end

    local pantheonTotal, pantheonUsed, pantheonAvailable, pantheonsComplete = CountPantheons()
    Log("snapshot turn=" .. ToText(turn)
        .. " trigger_player=" .. ToText(triggerPlayerID)
        .. " map=" .. ToText(width) .. "x" .. ToText(height)
        .. " plots=" .. ToText(plotCount)
        .. " map_script=" .. ToText(ReadMapConfig("MAP_SCRIPT"))
        .. " map_size=" .. ToText(ReadMapConfig("MAP_SIZE"))
        .. " game_speed=" .. ToText(ReadConfig("GAME_SPEED_TYPE"))
        .. " alive_majors=" .. ToText(CountList(majors))
        .. " alive_minors=" .. (minors ~= nil and ToText(CountList(minors)) or "UNKNOWN")
        .. " cities=" .. ToText(cityCount)
        .. " units=" .. ToText(unitCount)
        .. " object_budget=" .. ToText(objectBudget)
        .. " objects_scanned=" .. ToText(objectsScanned)
        .. " objects_complete=" .. ToText(objectsComplete)
        .. " pantheon_total=" .. ToText(pantheonTotal == nil and "UNKNOWN" or pantheonTotal)
        .. " pantheon_used=" .. ToText(pantheonUsed == nil and "UNKNOWN" or pantheonUsed)
        .. " pantheon_available=" .. ToText(pantheonAvailable == nil and "UNKNOWN" or pantheonAvailable)
        .. " pantheons_complete=" .. ToText(pantheonsComplete))

    if not objectsComplete then
        local marker = objectsReason == "budget_exhausted"
            and "snapshot_budget_exhausted" or "snapshot_objects_unavailable"
        Log(marker .. " turn=" .. ToText(turn)
            .. " reason=" .. ToText(objectsReason)
            .. " object_budget=" .. ToText(objectBudget)
            .. " objects_scanned=" .. ToText(objectsScanned))
    end

    if timingEnabled and startedMs ~= nil then
        local finishedMs = ReadClockMs()
        if finishedMs ~= nil then
            Log("snapshot_timing turn=" .. ToText(turn)
                .. " elapsed_ms=" .. TimingResult(startedMs,finishedMs)
                .. " major_count=" .. ToText(CountList(majors))
                .. " city_count=" .. ToText(cityCount)
                .. " unit_count=" .. ToText(unitCount)
                .. " object_budget=" .. ToText(objectBudget)
                .. " objects_scanned=" .. ToText(objectsScanned)
                .. " objects_complete=" .. ToText(objectsComplete))
        else
            Log("snapshot_timing_unavailable turn=" .. ToText(turn))
        end
    end

    State.LastSnapshotTurn = turn
end

local function IncrementEvent(name)
    State.EventCounts[name] = (State.EventCounts[name] or 0) + 1
    Log("event=" .. name .. " count=" .. ToText(State.EventCounts[name]))
end

local function OnPlayerTurnStarted(playerID)
    local turn = CurrentTurn()
    if turn ~= State.LastTurn then
        State.LastTurn = turn
        Log("turn_begin turn=" .. ToText(turn) .. " active_player=" .. ToText(playerID))
        ProcessSatelliteReveal(turn)
        LogClimateSnapshot(playerID, turn)
        if State.LastSnapshotTurn == nil or turn <= 1 or turn % SAMPLE_INTERVAL == 0 then
            LogSnapshot(playerID, turn)
        end
    end
end

local function OnPantheonFounded(playerID, beliefIndex)
    IncrementEvent("pantheon_founded")
    Log("pantheon_founded player=" .. ToText(playerID) .. " belief_index=" .. ToText(beliefIndex) .. " turn=" .. ToText(CurrentTurn()))
end

local function OnNaturalWonderRevealed(plotX, plotY, featureIndex, isFirstToFind)
    IncrementEvent("natural_wonder_revealed")
    Log("natural_wonder_revealed x=" .. ToText(plotX)
        .. " y=" .. ToText(plotY)
        .. " feature=" .. ToText(featureIndex)
        .. " first=" .. ToText(isFirstToFind)
        .. " turn=" .. ToText(CurrentTurn()))
end

local function OnCityProjectCompleted(playerID, cityID, projectIndex, buildingIndex, locX, locY, isCanceled)
    local projectType = "UNKNOWN"
    local projects, readable = ReadMember(GameInfo, "Projects")
    if readable and projects ~= nil then
        local rowOK, row = pcall(function() return projects[projectIndex] end)
        if rowOK and row ~= nil and row.ProjectType ~= nil then
            projectType = row.ProjectType
        end
    end

    if projectType == "PROJECT_LAUNCH_EARTH_SATELLITE" then
        IncrementEvent("earth_satellite_completed")
        Log("earth_satellite_completed player=" .. ToText(playerID)
            .. " city=" .. ToText(cityID)
            .. " project_index=" .. ToText(projectIndex)
            .. " x=" .. ToText(locX)
            .. " y=" .. ToText(locY)
            .. " canceled=" .. ToText(isCanceled)
            .. " turn=" .. ToText(CurrentTurn()))
        if not IsTrue(isCanceled) then
            QueueSatelliteReveal(playerID, CurrentTurn())
        end
    end
end

local function RegisterEvent(container, eventName, handler)
    local event, readable = ReadMember(container, eventName)
    if not readable or not HasCallable(event, "Add") then
        Log("event_unavailable name=" .. eventName)
        return false
    end

    local ok, message = pcall(function() event.Add(handler) end)
    if not ok then
        Log("event_register_failed name=" .. eventName .. " message=" .. ToText(message))
        return false
    end
    Log("event_registered name=" .. eventName)
    return true
end

local function Initialize()
    if State.Initialized then
        return
    end
    State.Initialized = true

    Log("init version=round3-satellite-chunked")
    RegisterEvent(GameEvents, "PlayerTurnStarted", OnPlayerTurnStarted)

    -- These events are native UI/game events. Guard them because availability
    -- differs between gameplay and UI contexts and across DLC builds.
    RegisterEvent(Events, "PantheonFounded", OnPantheonFounded)
    RegisterEvent(Events, "NaturalWonderRevealed", OnNaturalWonderRevealed)
    RegisterEvent(Events, "CityProjectCompleted", OnCityProjectCompleted)
    RegisterEvent(Events, "CityProjectCompletedNarrative", OnCityProjectCompleted)

    LogSnapshot(-1, CurrentTurn())
end

if not RegisterEvent(Events, "LoadScreenClose", Initialize) then
    Initialize()
end

