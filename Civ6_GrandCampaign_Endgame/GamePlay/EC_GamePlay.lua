-- Endgame observation, persistent state and explicit action experiments.
-- Native vassal transactions require an explicit single-player test mode,
-- full qualification, production preflight and token-bound human consent.
-- Victory integration remains under development.
include("EC_Eligibility")
include("EC_DataStore")
include("EC_WarContext")
include("EC_EligibilityObserver")
include("EC_Protection")
include("EC_AwakeningActions")
include("EC_AIMilitaryProduction")
include("EC_VassalTransaction")
include("EC_CityPayload")
include("EC_NativeLifecycle")
include("EC_NativeCityAdapter")
include("EC_ProductionArchive")
include("EC_ProductionRestore")
include("EC_AIProductionCredit")
include("EC_HumanProductionRefund")
include("EC_AutonomyPolicy")
include("EC_NativeVassals")
include("EC_NativeVictory")

local PREFIX = "[EC]"
local SAMPLE_INTERVAL = 5
local MAX_CITY_PROBE_RETRIES = 4
local START_MAJOR_KEY = "EC_OBSERVED_START_MAJOR_COUNT"
local AWAKENING_STATE_KEY = "EC_AWAKENING_STATE"
local AWAKENING_CIV_KEY = "EC_AWAKENING_CIV"
local AWAKENING_TRIGGER_TURN_KEY = "EC_AWAKENING_TRIGGER_TURN"
local AWAKENING_PREP_END_KEY = "EC_AWAKENING_PREP_END_TURN"
local AWAKENING_CONQUEST_END_KEY = "EC_AWAKENING_CONQUEST_END_TURN"
local AWAKENING_LAST_TRANSITION_KEY = "EC_AWAKENING_LAST_TRANSITION_TURN"
local AWAKENING_SCHEMA_KEY = "EC_AWAKENING_SCHEMA_VERSION"
local AWAKENING_MODE_KEY = "EC_AWAKENING_MODE"
local AWAKENING_READY_KEY = "EC_AWAKENING_PAYLOAD_READY"
local WAR_PAIR_CURSOR_KEY = "EC_WAR_PAIR_CURSOR"
local SCHEMA_VERSION = 1
local AWAKENING_TOP_PERCENT = 30
local AWAKENING_FARTHEST_PERCENT = 30
local ResolveProjectCycleTurns
local NativeController
local NativeDispatchReady=false
if type(ExposedMembers)=="table" then
    ExposedMembers.EC_NativeDispatchReady=function() return NativeDispatchReady end
end
local AdvanceNativeVassals
local RefreshNativeMetrics
local RunDeferredCityProbe

local State = {
    Initialized = false,
    NativeStarted = false,
    LastTurn = nil,
    LastSnapshotTurn = nil,
    StartMajorCount = nil,
    TriggerLogged = false,
    ShadowVassals = {},
    AwakeningState = nil,
    AwakeningCandidateID = nil,
    Metrics = {},
    EraReached = false,
    DeadPercent = nil,
    MetricsDirty = false,
    LastProtectionProbeStage = nil,
    UnavailableMetricMethods = {},
    CityProbeCompleted = {},
    CityProbePending = false,
    CityProbeRetries = 0,
    LastCityProbeTurn = nil,
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
    local ok, first, second = pcall(callback)
    if not ok then
        Log("error label=" .. label .. " message=" .. ToText(first))
        return nil
    end
    return first, second
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
    return defaultValue
end

local function IsTrue(value)
    return value == true or value == 1 or value == "1" or value == "true";
end

local function IsFalse(value)
    return value == false or value == 0 or value == "0" or value == "false"
end

local function AwakeningActionsEnabled()
    return IsFalse(ReadConfig("EC_OBSERVATION_ONLY", 1))
        and IsTrue(ReadConfig("EC_AWAKENING_ENABLED", 0))
        and IsTrue(ReadConfig("EC_AWAKENING_ACTIONS_TEST", 0))
        and IsFalse(ReadConfig("EC_AWAKENING_DRY_RUN", nil))
        and HasCallable(GameConfiguration, "IsAnyMultiplayer")
        and SafeCall("awakening_single_player", function() return GameConfiguration.IsAnyMultiplayer() end) == false
end

local function AwakeningMode()
    return AwakeningActionsEnabled() and "LIVE_TEST" or "DRY_RUN"
end

local function DebugTimingEnabled()
    return IsTrue(ReadConfig("EC_DEBUG_TIMING", 0))
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
    if not HasCallable(os, "clock") then return nil end
    local value = SafeCall("clock", function() return os.clock() end)
    return value ~= nil and value * 1000 or nil
end

local function TimingResult(startedMs,finishedMs)
    if finishedMs<startedMs then return "UNKNOWN clock_reversed=true" end
    local elapsed=finishedMs-startedMs
    local value=elapsed==0 and "below_clock_resolution" or string.format("%.3f",elapsed)
    return value.." clock="..TimingClockSource
end

local function WarObservationEnabled()
    -- Runtime evidence remains opt-in and observation-only until native
    -- ownership, protection and save/load gates are accepted.
    return IsTrue(ReadConfig("EC_WAR_OBSERVATION_TEST", 0))
        and (IsTrue(ReadConfig("EC_OBSERVATION_ONLY", 1)) or IsTrue(ReadConfig("EC_NATIVE_VASSAL_TEST",0)))
end

local function SetPropertySafe(playerID, key, value)
    local player = Players ~= nil and Players[playerID] or nil
    if not HasCallable(player, "SetProperty") then
        Log("property_unavailable player=" .. ToText(playerID) .. " key=" .. key)
        return false
    end
    return SafeCall("property_set_" .. key, function()
        return player:SetProperty(key, value) ~= false
    end) == true
end

local function GetPropertySafe(playerID, key, defaultValue)
    local player = Players ~= nil and Players[playerID] or nil
    if not HasCallable(player, "GetProperty") then
        return defaultValue, false
    end
    local ok, value = pcall(function() return player:GetProperty(key) end)
    if not ok then
        Log("property_read_failed player=" .. ToText(playerID) .. " key=" .. key)
        return defaultValue, false
    end
    if value == nil then return defaultValue, true end
    return value, true
end

local function IsNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function PlayerSlot(value)
    return IsNumber(value) and value >= 0 and value < 64 and value == math.floor(value)
end

-- Native player wrappers can expose a getter that throws instead of returning
-- an ID. Keep the identity read inside the same fail-closed boundary as every
-- other probe so one malformed player cannot abort a snapshot.
local function ReadPlayerID(player, label)
    if player == nil then return nil end
    local ok, getter = pcall(function() return player.GetID end)
    if not ok or type(getter) ~= "function" then return nil end
    local id = SafeCall(label or "player_id", function() return player:GetID() end)
    if not IsNumber(id) or id < 0 or id >= 64 or id ~= math.floor(id) then return nil end
    return id
end

local function ValidMajorRoster(majors, requireAlive)
    if type(majors) ~= "table" or #majors > 64 then return false end
    local count, seen = 0, {}
    for key in pairs(majors) do
        if not IsNumber(key) or key < 1 or key > #majors or key ~= math.floor(key) then return false end
        count = count + 1
    end
    if count ~= #majors then return false end
    for _, player in ipairs(majors) do
        local id = ReadPlayerID(player, "major_player_id")
        if id == nil or seen[id] then return false end
        if requireAlive ~= false and HasCallable(player, "IsAlive") then
            local alive = SafeCall("major_player_alive_" .. ToText(id), function() return player:IsAlive() end)
            if alive ~= true then return false end
        end
        if HasCallable(player, "IsMajor") then
            local major = SafeCall("major_player_major_" .. ToText(id), function() return player:IsMajor() end)
            if major ~= true then return false end
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
    if not ValidMajorRoster(majors) then
        return {}, false
    end
    return majors, true
end

local function CountCities(player)
    if not HasCallable(player, "GetCities") then
        return 0, false
    end
    local playerID = ReadPlayerID(player, "cities_player_id")
    if playerID == nil then return 0, false end
    local cities = SafeCall("cities_" .. ToText(playerID), function()
        return player:GetCities()
    end)
    if not HasCallable(cities, "GetCount") then
        return 0, false
    end
    local count = SafeCall("city_count_" .. ToText(playerID), function()
        return cities:GetCount()
    end)
    if not IsNumber(count) or count < 0 or count ~= math.floor(count) then return 0, false end
    return count, true
end

local function ReadMetric(player, methodLabel, callback, defaultValue)
    if player == nil then
        return defaultValue, false
    end
    local playerID = ReadPlayerID(player, methodLabel .. "_player_id")
    if playerID == nil then return defaultValue, false end
    local value = SafeCall(methodLabel .. "_" .. ToText(playerID), callback)
    value = tonumber(value)
    if not IsNumber(value) then return defaultValue, false end
    return value, true
end

local function ReadMetricMethod(player, field, object, method)
    if player == nil then return nil end
    local ok, callback = pcall(function() return object ~= nil and object[method] or nil end)
    local playerID = ReadPlayerID(player, field .. "_player_id")
    if playerID == nil then return nil end
    if not ok or type(callback) ~= "function" then
        local key = field .. "_" .. ToText(playerID)
        if not State.UnavailableMetricMethods[key] then
            State.UnavailableMetricMethods[key] = true
            Log("metric_unavailable source=GAMEPLAY_PROBE field=" .. field
                .. " player=" .. ToText(playerID)
                .. " method=" .. method
                .. " hint=enable_EC_METRIC_BRIDGE_TEST")
        end
        return nil
    end
    -- Gameplay and UI expose different methods on native objects. Never call a
    -- missing method or replace unknown strength with an eligible zero value.
    return SafeCall(field .. "_" .. ToText(playerID), function() return callback(object) end)
end

local function IsHumanPlayer(player)
    if not HasCallable(player, "IsHuman") then
        return nil
    end
    local playerID = ReadPlayerID(player, "human_player_id")
    if playerID == nil then return nil end
    local value = SafeCall("human_" .. ToText(playerID), function()
        return player:IsHuman()
    end)
    if type(value) ~= "boolean" then return nil end
    return value
end

local function MetricBridgeEnabled()
    return IsTrue(ReadConfig("EC_METRIC_BRIDGE_TEST", 0))
        and SafeCall("bridge_single_player", function() return GameConfiguration.IsAnyMultiplayer() end) == false
end

local function SingleObserverID()
    local id = nil
    for _, player in ipairs(GetAliveMajors()) do
        local human = IsHumanPlayer(player)
        if human == nil then return nil end
        if human then
            if id ~= nil then return nil end
            id = ReadPlayerID(player, "observer_player_id")
            if id == nil then return nil end
        end
    end
    return id
end

local function ReadPlayerMetrics(player, bridgeAuthor, bridgeSpeed)
    local playerID = ReadPlayerID(player, "metrics_player_id")
    if playerID == nil then return nil end
    if bridgeAuthor ~= nil then
        local turn = SafeCall("metric_turn", function() return Game.GetCurrentGameTurn() end)
        local cached = EC_DataStore.ReadSnapshot(player, turn, SAMPLE_INTERVAL)
        local cities, citiesValid = CountCities(player)
        if cached ~= nil and cached.SpeedMultiplier == bridgeSpeed and cached.Alive and cached.Major and cached.AuthorID == bridgeAuthor
            and cached.Human == IsHumanPlayer(player)
            and citiesValid and cached.Cities == cities then
            local era, eraValid = ReadMetric(player, "era", function()
                return ReadMetricMethod(player, "era", player, "GetEra")
            end, 0)
            return { PlayerID = cached.PlayerID, Human = cached.Human, Military = cached.Military,
                Science = cached.Science, Culture = cached.Culture, Gold = math.max(0, cached.NetGold),
                Cities = cached.Cities, Score = 0, Era = era, EraValid = eraValid, ProjectMetricsComplete = true,
                MilitaryValid = true, MetricSource = "UI_BRIDGE_TEST",
                MetricTurn = cached.Turn, EligibilitySnapshot = cached }
        end
    end
    local stats = ReadMetricMethod(player, "stats", player, "GetStats")
    local techs = ReadMetricMethod(player, "techs", player, "GetTechs")
    local culture = ReadMetricMethod(player, "culture", player, "GetCulture")
    local treasury = ReadMetricMethod(player, "treasury", player, "GetTreasury")

    local military, militaryValid = ReadMetric(player, "military", function()
        return ReadMetricMethod(player, "military", stats, "GetMilitaryStrengthWithoutTreasury")
    end, 0)
    local science, scienceValid = ReadMetric(player, "science", function()
        return ReadMetricMethod(player, "science", techs, "GetScienceYield")
    end, 0)
    local cultureYield, cultureValid = ReadMetric(player, "culture_yield", function()
        return ReadMetricMethod(player, "culture_yield", culture, "GetCultureYield")
    end, 0)
    local gold, goldValid = ReadMetric(player, "gold_yield", function()
        local grossGold = ReadMetricMethod(player, "gold_yield", treasury, "GetGoldYield")
        local maintenance = ReadMetricMethod(player, "maintenance", treasury, "GetTotalMaintenance")
        if not IsNumber(grossGold) or not IsNumber(maintenance) or maintenance < 0 then return nil end
        return grossGold - maintenance
    end, 0)
    local score = ReadMetric(player, "score", function()
        return ReadMetricMethod(player, "score", player, "GetScore")
    end, 0)
    local era, eraValid = ReadMetric(player, "era", function()
        return ReadMetricMethod(player, "era", player, "GetEra")
    end, 0)
    local cities, citiesValid = CountCities(player)

    return {
        PlayerID = playerID,
        Human = IsHumanPlayer(player),
        Military = math.max(0, military),
        MilitaryValid = militaryValid and military >= 0,
        Science = math.max(0, science),
        Culture = math.max(0, cultureYield),
        Gold = math.max(0, gold),
        ProjectMetricsComplete = militaryValid and military >= 0 and scienceValid and science >= 0
            and cultureValid and cultureYield >= 0 and goldValid and citiesValid,
        Cities = cities,
        Score = math.max(0, score),
        Era = era,
        EraValid = eraValid,
    }
end

local function GetStartMajorCount(majors)
    if State.StartMajorCount ~= nil then
        return State.StartMajorCount
    end

    local stored, readable = GetPropertySafe(0, START_MAJOR_KEY, nil)
    if not readable then return nil end
    if IsNumber(stored) and stored > 0 and stored == math.floor(stored) then
        State.StartMajorCount = stored
        return stored
    end
    if stored ~= nil then
        Log("start_major_count_invalid")
        return nil
    end
    local count = nil
    if HasCallable(PlayerManager, "GetWasEverAliveMajors") then
        local historical = SafeCall("historical_majors", function() return PlayerManager.GetWasEverAliveMajors() end)
        if ValidMajorRoster(historical, false) and #historical >= #majors and #historical > 0 then
            count = #historical
        end
    end
    local turn = HasCallable(Game, "GetCurrentGameTurn")
        and (SafeCall("start_major_turn", function() return Game.GetCurrentGameTurn() end) or -1)
        or -1
    if count == nil and turn >= 0 and turn <= 1 and #majors > 0 then count = #majors end
    if count == nil then
        Log("start_major_count_unknown turn=" .. ToText(turn))
        return nil
    end
    if not SetPropertySafe(0, START_MAJOR_KEY, count) then return nil end
    State.StartMajorCount = count
    return count
end

local function Normalize(value, maximum)
    if maximum == nil or maximum <= 0 then
        return 0
    end
    return value / maximum
end

local function ResolveTargetEra()
    local eraType = ReadConfig("EC_AWAKENING_ERA", "ERA_INDUSTRIAL")
    local eras, erasReadable = ReadMember(GameInfo, "Eras")
    local eraRow, rowReadable = ReadMember(eras, eraType)
    if erasReadable and rowReadable and eraRow ~= nil then
        local chronology, chronologyReadable = ReadMember(eraRow, "ChronologyIndex")
        local index, indexReadable = ReadMember(eraRow, "Index")
        -- Player:GetEra returns the GameInfo index, not ChronologyIndex.
        if indexReadable and type(index) == "number" then return index end
        if chronologyReadable and type(chronology) == "number" then return chronology end
    end
    return 4
end

local function BuildSnapshot(majors)
    local metrics = {}
    local maximums = { Military = 1, Science = 1, Culture = 1, Gold = 1, Cities = 1, Score = 1 }
    local targetEra = ResolveTargetEra()
    local eraReached = false
    local complete = true
    local bridgeAuthor = MetricBridgeEnabled() and SingleObserverID() or nil
    local bridgeSpeed = nil
    if bridgeAuthor ~= nil then local _; _, bridgeSpeed = ResolveProjectCycleTurns() end

    for _, player in ipairs(majors) do
        local row = ReadPlayerMetrics(player, bridgeAuthor, bridgeSpeed)
        if row == nil then
            complete = false
        else
            table.insert(metrics, row)
            for _, key in ipairs({ "Military", "Science", "Culture", "Gold", "Cities", "Score" }) do
                if row.ProjectMetricsComplete then maximums[key] = math.max(maximums[key], row[key]) end
            end
            if row.EraValid and row.Era >= targetEra then
                eraReached = true
            end
        end
    end

    if not complete or #metrics ~= #majors then
        return {}, false, false
    end

    for _, row in ipairs(metrics) do
        row.Power = row.ProjectMetricsComplete and (0.35 * Normalize(row.Military, maximums.Military)
            + 0.20 * Normalize(row.Science, maximums.Science)
            + 0.20 * Normalize(row.Culture, maximums.Culture)
            + 0.15 * Normalize(row.Gold, maximums.Gold)
            + 0.10 * Normalize(row.Cities, maximums.Cities)) or 0
    end
    table.sort(metrics, function(a, b)
        if a.Power == b.Power then
            return a.PlayerID < b.PlayerID
        end
        return a.Power > b.Power
    end)

    return metrics, eraReached, true
end

local PROJECT_POLICY_VERSION = 1
local PROJECT_EFFECT_TOKEN = "PROJECT_EFFECT_APPLIED_TOKEN"
local PROJECT_EFFECT_STATE = "PROJECT_EFFECT_STATE"
local PROJECT_BUDGET_PREFIX = "EC_PROJECT_BUDGET_"
local PROJECT_EFFECT_LIMIT = 3
local PROJECT_EFFECT_ORDER = { "SUPPORT_MILITARY", "WEAKEN_MILITARY", "SUPPORT_ECONOMY", "WEAKEN_ECONOMY",
    "SUPPORT_SCIENCE", "WEAKEN_SCIENCE", "SUPPORT_CULTURE", "WEAKEN_CULTURE" }
local PROJECT_DOMAINS = { { "Military", "MILITARY" }, { "Gold", "ECONOMY" },
    { "Science", "SCIENCE" }, { "Culture", "CULTURE" } }
local PROJECT_EFFECT_MODIFIERS = {
    SUPPORT_OVERLORD = {
        MILITARY = "EC_PROJECT_SUPPORT_MILITARY", ECONOMY = "EC_PROJECT_SUPPORT_ECONOMY",
        SCIENCE = "EC_PROJECT_SUPPORT_SCIENCE", CULTURE = "EC_PROJECT_SUPPORT_CULTURE",
    },
    WEAKEN_OVERLORD = {
        MILITARY = "EC_PROJECT_WEAKEN_MILITARY", ECONOMY = "EC_PROJECT_WEAKEN_ECONOMY",
        SCIENCE = "EC_PROJECT_WEAKEN_SCIENCE", CULTURE = "EC_PROJECT_WEAKEN_CULTURE",
    },
}

local function ProjectEffectsEnabled()
    return IsFalse(ReadConfig("EC_OBSERVATION_ONLY", 1))
        and IsTrue(ReadConfig("EC_PROJECT_EFFECTS_TEST", 0))
end

local function PrepareProjectBudget(overlordID)
    local schema, readable = GetPropertySafe(overlordID, PROJECT_BUDGET_PREFIX .. "SCHEMA", nil)
    if not readable or (schema ~= nil and schema ~= 1) then return nil end
    local counts = {}
    for _, effect in ipairs(PROJECT_EFFECT_ORDER) do
        local value, known = GetPropertySafe(overlordID, PROJECT_BUDGET_PREFIX .. effect .. "_COUNT", nil)
        if not known or (schema == 1 and (not IsNumber(value) or value < 0
            or value > PROJECT_EFFECT_LIMIT or value ~= math.floor(value)))
            or (schema == nil and value ~= nil and value ~= 0) then return nil end
        counts[effect] = value or 0
    end
    if schema == 1 then return counts end
    -- Older archives retain only their latest modifier token, so their native
    -- instance count cannot be reconstructed. Never start a fresh allowance
    -- on top of an uncounted legacy effect, including one from a dead player.
    local historical=HasCallable(PlayerManager,"GetWasEverAliveMajors") and SafeCall("project_budget_roster",function()
        return PlayerManager.GetWasEverAliveMajors()
    end) or nil
    if not ValidMajorRoster(historical,false) then return nil end
    for _,player in ipairs(historical) do
        local id=player:GetID()
        if Players ~= nil and Players[id] ~= nil then
            local prefix = "EC_VASSAL_" .. id .. "_"
            local owner, ownerOK = GetPropertySafe(id, prefix .. "OVERLORD", nil)
            local token, tokenOK = GetPropertySafe(id, prefix .. PROJECT_EFFECT_TOKEN, -1)
            local state, stateOK = GetPropertySafe(id, prefix .. PROJECT_EFFECT_STATE, "NONE")
            if not ownerOK or not tokenOK or not stateOK or not IsNumber(token)
                or token < -1 or token ~= math.floor(token)
                or (state ~= "NONE" and state ~= "PENDING" and state ~= "APPLIED"
                    and state ~= "CAPPED" and state ~= "UNKNOWN") then return nil end
            if token ~= -1 or state ~= "NONE" then
                if not PlayerSlot(owner) or owner == overlordID then
                    Log("project_budget_legacy_uncounted overlord=" .. overlordID .. " vassal=" .. id)
                    return nil
                end
            end
        end
    end
    for _, effect in ipairs(PROJECT_EFFECT_ORDER) do
        if not SetPropertySafe(overlordID, PROJECT_BUDGET_PREFIX .. effect .. "_COUNT", 0) then return nil end
    end
    if not SetPropertySafe(overlordID, PROJECT_BUDGET_PREFIX .. "SCHEMA", 1) then return nil end
    return counts
end

local function ApplyShadowProjectEffect(vassalID, overlordID, project, focus, token)
    if not ProjectEffectsEnabled() then return true end
    if not IsNumber(overlordID) or not IsNumber(token) then return false end
    local modifier = PROJECT_EFFECT_MODIFIERS[project] ~= nil
        and PROJECT_EFFECT_MODIFIERS[project][focus] or nil
    local player = Players ~= nil and Players[overlordID] or nil
    if modifier == nil or not HasCallable(player, "AttachModifierByID") then
        Log("project_effect_unavailable vassal=" .. ToText(vassalID)
            .. " overlord=" .. ToText(overlordID)
            .. " project=" .. ToText(project) .. " focus=" .. ToText(focus))
        return false
    end
    local applied = SafeCall("project_effect_" .. modifier, function()
        return player:AttachModifierByID(modifier) ~= false
    end)
    if applied ~= true then return false end
    Log("project_effect_applied vassal=" .. ToText(vassalID)
        .. " overlord=" .. ToText(overlordID)
        .. " project=" .. ToText(project)
        .. " focus=" .. ToText(focus)
        .. " token=" .. ToText(token)
        .. " modifier=" .. modifier)
    return true
end

local function ShadowDisposition(overlordID, vassalID)
    -- Stable test diversity; this is not a claim about native leader personality.
    return (overlordID + vassalID) % 3 == 0 and "COOPERATIVE" or "DEFIANT"
end

local function IsProjectFocus(value)
    return value == "GENERAL" or value == "MILITARY" or value == "ECONOMY"
        or value == "SCIENCE" or value == "CULTURE"
end

local function ChooseShadowProject(overlordRow, vassalRow, autonomy, disposition)
    if overlordRow == nil or vassalRow == nil or not overlordRow.ProjectMetricsComplete
        or not vassalRow.ProjectMetricsComplete or not IsNumber(overlordRow.Power)
        or not IsNumber(vassalRow.Power) or not IsNumber(autonomy)
        or (disposition ~= "COOPERATIVE" and disposition ~= "DEFIANT") then return nil end
    local pressure = math.max(0, overlordRow.Power - vassalRow.Power)
    local score = (disposition == "COOPERATIVE" and 65 or 35) - 20 * pressure - 0.3 * autonomy
    if overlordRow.Military >= 3 * math.max(1, vassalRow.Military) then score = score + 20 end
    local project = score >= 50 and "SUPPORT_OVERLORD" or "WEAKEN_OVERLORD"
    local focus, best = nil, nil
    for _, domain in ipairs(PROJECT_DOMAINS) do
        local ratio = overlordRow[domain[1]] / math.max(1, vassalRow[domain[1]])
        if best == nil or (project == "SUPPORT_OVERLORD" and ratio < best)
            or (project == "WEAKEN_OVERLORD" and ratio > best) then
            best, focus = ratio, domain[2]
        end
    end
    return project, focus
end

local function IsShadowVassal(playerID)
    local native,nativeKnown=GetPropertySafe(playerID,"EC_NATIVE_ARCHIVE",nil)
    if not nativeKnown then return nil end
    if native~=nil then
        if type(native)~="table" or native.Schema~=2 or native.PlayerID~=playerID then return nil end
        if native.State=="ARCHIVED" then return true end
        if native.State~="RESTORED" then return nil end
    end
    local prefix = "EC_VASSAL_" .. ToText(playerID) .. "_"
    local status, readable = GetPropertySafe(playerID, prefix .. "STATE", nil)
    local schema, schemaReadable = GetPropertySafe(playerID, prefix .. "SCHEMA_VERSION", nil)
    if not readable or not schemaReadable or (schema ~= nil and schema ~= SCHEMA_VERSION) then return nil end
    if status == nil or status == "INDEPENDENT" then return false end
    if status == "SHADOW_ARCHIVED" or status=="VASSALIZED" then return true end
    return nil
end

local function EligibilityObservationEnabled()
    return IsTrue(ReadConfig("EC_ELIGIBILITY_OBSERVATION_TEST", 0))
        and (IsTrue(ReadConfig("EC_OBSERVATION_ONLY", 1)) or IsTrue(ReadConfig("EC_NATIVE_VASSAL_TEST",0)))
        and MetricBridgeEnabled()
end

local function ProtectionCapital(playerID)
    return SafeCall("protection_capital_" .. ToText(playerID), function()
        local capital = Players[playerID]:GetCities():GetCapitalCity()
        if capital == nil or capital:GetOwner() ~= playerID then return nil end
        local x, y = capital:GetX(), capital:GetY()
        if not IsNumber(x) or not IsNumber(y) or x < 0 or y < 0
            or x ~= math.floor(x) or y ~= math.floor(y) then return nil end
        return { X = x, Y = y }
    end)
end

local function BuildProtectionRoster(humanID, awakenedID)
    if not HasCallable(Map, "GetPlotDistance") then return nil, "DISTANCE_API_UNKNOWN" end
    local origin = ProtectionCapital(humanID)
    if origin == nil then return nil, "PLAYER_CAPITAL_UNKNOWN" end
    local majors = SafeCall("protection_majors", function() return PlayerManager.GetAliveMajors() end)
    if type(majors) ~= "table" or #majors < 2 or #majors > 64 then return nil, "ROSTER_UNKNOWN" end
    for key in pairs(majors) do
        if not IsNumber(key) or key < 1 or key > #majors or key ~= math.floor(key) then
            return nil, "ROSTER_UNKNOWN"
        end
    end
    local candidates, seen = {}, {}
    for _, player in ipairs(majors) do
        local id = SafeCall("protection_player_id", function() return player:GetID() end)
        if not PlayerSlot(id) or seen[id] then return nil, "ROSTER_UNKNOWN" end
        seen[id] = true
        if SafeCall("protection_party_" .. id, function() return player:IsAlive() and player:IsMajor() end) ~= true then
            return nil, "IDENTITY_UNKNOWN"
        end
        local human = IsHumanPlayer(player)
        local archived = IsShadowVassal(id)
        if human == nil or archived == nil or (id == humanID and human ~= true)
            or (id ~= humanID and human ~= false) then return nil, "IDENTITY_UNKNOWN" end
        if id ~= humanID and id ~= awakenedID and not archived then
            local capital = ProtectionCapital(id)
            if capital == nil then return nil, "AI_CAPITAL_UNKNOWN" end
            candidates[#candidates + 1] = { PlayerID = id, Human = false, Alive = true,
                Major = true, Independent = true, X = capital.X, Y = capital.Y }
        end
    end
    if not seen[humanID] or not seen[awakenedID] then return nil, "PARTY_MISSING" end
    return EC_Protection.BuildNearby({ HumanPlayerID = humanID, AwakenedPlayerID = awakenedID,
        Candidates = candidates, Distance = function(candidate)
            return Map.GetPlotDistance(origin.X, origin.Y, candidate.X, candidate.Y)
        end })
end

local function ProtectionForObservation(turn, humanID)
    local enabled = IsTrue(ReadConfig("EC_AWAKENING_ENABLED", 0)) or IsTrue(ReadConfig("EC_AWAKENING_DRY_RUN", 0))
    local stage, awakenedID = State.AwakeningState, State.AwakeningCandidateID
    -- This cache belongs to one Update invocation, including failed reads.
    local attempted, roster = false, nil
    return function(attackerID, targetID, targetHuman)
        if not enabled then return false end
        if stage == nil then return nil end
        if stage == "LOCKED" or stage == "TRIGGERED" or stage == "RESOLVED" then return false end
        if not PlayerSlot(awakenedID) or awakenedID == humanID then return nil end
        if SafeCall("protection_awakened_party", function()
            return Players[awakenedID]:IsAlive() and Players[awakenedID]:IsMajor()
        end) ~= true or IsHumanPlayer(Players ~= nil and Players[awakenedID] or nil) ~= false
            or IsShadowVassal(awakenedID) ~= false then return nil end
        if attackerID ~= awakenedID then return false end
        if targetID == awakenedID then return true end
        if stage == "SHOWDOWN" then return false end
        if stage ~= "PREPARATION" and stage ~= "CONQUEST" then return nil end
        if targetID == humanID then return targetHuman == true and true or nil end
        if targetHuman ~= false then return nil end
        if not attempted then
            attempted = true
            local reason
            roster, reason = BuildProtectionRoster(humanID, awakenedID)
            local selected = {}
            if roster ~= nil then
                for index = 1, math.min(2, #roster) do selected[index] = ToText(roster[index].PlayerID) end
            end
            Log("protection_roster turn=" .. ToText(turn) .. " stage=" .. ToText(stage)
                .. " awakened=" .. ToText(awakenedID) .. " human=" .. ToText(humanID)
                .. " complete=" .. ToText(roster ~= nil) .. " reason=" .. ToText(reason)
                .. " selected=" .. table.concat(selected, ","))
        end
        return EC_Protection.IsProtected({ Turn = turn, Stage = stage, TargetID = targetID,
            HumanPlayerID = humanID, AttackerID = attackerID, AwakenedPlayerID = awakenedID,
            NearbyCount = 2, NearbyComplete = roster ~= nil, Nearby = roster })
    end
end

local function RunEligibilityObservation(turn)
    if not EligibilityObservationEnabled() or turn < 0 then return end
    local timingEnabled = DebugTimingEnabled()
    local startedMs = timingEnabled and ReadClockMs() or nil
    local authorID = SingleObserverID()
    local _, speedMultiplier = ResolveProjectCycleTurns()
    if authorID == nil or speedMultiplier == nil then
        Log("eligibility_observation_unavailable turn=" .. ToText(turn))
        return
    end

    local ids = {}
    for _, row in ipairs(State.Metrics) do
        if row.ProjectMetricsComplete then ids[#ids + 1] = row.PlayerID end
    end
    if #ids < 2 then
        Log("eligibility_observation_insufficient turn=" .. ToText(turn) .. " players=" .. ToText(#ids))
        return
    end

    local ok, message = pcall(function()
        EC_EligibilityObserver.Update({
            Turn = turn,
            AuthorID = authorID,
            SpeedMultiplier = speedMultiplier,
            PlayerIDs = ids,
            IsIndependent = function(playerID) return IsShadowVassal(playerID) == false end,
            IsProtected = ProtectionForObservation(turn, authorID),
        })
    end)
    Log("eligibility_observation_update turn=" .. ToText(turn)
        .. " players=" .. ToText(#ids)
        .. " success=" .. ToText(ok)
        .. " reason=" .. ToText(message))
    if timingEnabled and startedMs ~= nil then
        local finishedMs = ReadClockMs()
        if finishedMs ~= nil then
            Log("eligibility_observation_timing turn=" .. ToText(turn)
                .. " elapsed_ms=" .. TimingResult(startedMs,finishedMs)
                .. " players=" .. ToText(#ids)
                .. " success=" .. ToText(ok))
        end
    end
end

local function OnMetricSnapshot(authorID, parameters)
    if not MetricBridgeEnabled() or type(parameters) ~= "table" or parameters.SchemaVersion ~= 1
        or not IsNumber(authorID) or authorID < 0 or authorID ~= math.floor(authorID)
        or authorID ~= SingleObserverID() or parameters.ForPlayer ~= authorID
        or not IsNumber(parameters.PlayerID) or parameters.PlayerID < 0 or parameters.PlayerID >= 64
        or parameters.PlayerID ~= math.floor(parameters.PlayerID) then return end
    local turn = SafeCall("bridge_turn", function() return Game.GetCurrentGameTurn() end)
    if parameters.Turn ~= turn then return end
    local player = Players ~= nil and Players[parameters.PlayerID] or nil
    if player == nil or IsHumanPlayer(player) ~= parameters.Human
        or SafeCall("bridge_party", function() return player:IsAlive() and player:IsMajor() end) ~= true then return end
    local cities, citiesValid = CountCities(player)
    local shadow = IsShadowVassal(parameters.PlayerID)
    if not citiesValid or cities ~= parameters.Cities or shadow == nil then return end
    local _, speed = ResolveProjectCycleTurns()
    if speed == nil or parameters.SpeedMultiplier ~= speed then return end
    local record = {}
    for _, key in ipairs({ "PlayerID", "Turn", "SpeedMultiplier", "Human", "Cities", "Military",
        "NetGold", "GoldBalance", "Science", "Culture", "TechsCompleted", "CivicsCompleted" }) do
        record[key] = parameters[key]
    end
    record.AuthorID, record.Source = authorID, "UI_BRIDGE_TEST"
    record.Alive, record.Major, record.Independent = true, true, not shadow
    local accepted, reason
    if parameters.RefreshBank ~= nil or parameters.RefreshCities ~= nil then
        accepted, reason = EC_DataStore.RefreshSnapshot(player, record, parameters.RefreshBank, parameters.RefreshCities)
    else
        accepted, reason = EC_DataStore.WriteSnapshot(player, record)
    end
    Log("metric_snapshot player=" .. ToText(parameters.PlayerID) .. " turn=" .. ToText(turn)
        .. " accepted=" .. ToText(accepted) .. " reason=" .. ToText(reason))
    if accepted and reason == "WRITTEN" then
        State.NativeStarted = true
        State.MetricsDirty = true
        if RefreshNativeMetrics then RefreshNativeMetrics(turn) end
    end
end

local function RestoreShadowVassals(metrics)
    local restored = 0
    for _, row in ipairs(metrics) do
        if IsShadowVassal(row.PlayerID) == true and State.ShadowVassals[row.PlayerID] == nil then
            local prefix = "EC_VASSAL_" .. ToText(row.PlayerID) .. "_"
            local overlordValue = GetPropertySafe(row.PlayerID, prefix .. "OVERLORD", -1)
            local overlordID = tonumber(overlordValue) or -1
            State.ShadowVassals[row.PlayerID] = overlordID
            restored = restored + 1
            Log("shadow_vassal_restored vassal=" .. ToText(row.PlayerID)
                .. " overlord=" .. ToText(overlordID))
        end
    end
    return restored
end

ResolveProjectCycleTurns = function()
    local baseTurns = 5
    local speedType = nil
    if HasCallable(GameConfiguration, "GetGameSpeedType") then
        speedType = SafeCall("game_speed_type", function()
            return GameConfiguration.GetGameSpeedType()
        end)
    end
    if speedType == nil then
        speedType = ReadConfig("GAME_SPEED_TYPE", nil)
    end
    local multiplier = nil
    local gameSpeeds, speedsReadable = ReadMember(GameInfo, "GameSpeeds")
    if speedType ~= nil and speedsReadable then
        local speedRow = SafeCall("game_speed_row", function()
            local row, readable = ReadMember(gameSpeeds, speedType)
            return readable and row or nil
        end)
        local costMultiplier, multiplierReadable = ReadMember(speedRow, "CostMultiplier")
        if multiplierReadable and costMultiplier ~= nil then
            local configured = tonumber(costMultiplier)
            if IsNumber(configured) and configured > 0 then
                multiplier = configured
            end
        end
    end

    if multiplier == nil then
        Log("project_speed_unknown type=" .. ToText(speedType))
        return nil
    end
    return math.max(1, math.ceil(baseTurns * multiplier / 100)), multiplier, speedType
end

local function ConsentTestEnabled()
    return IsFalse(ReadConfig("EC_OBSERVATION_ONLY", 1))
        and IsTrue(ReadConfig("EC_PLAYER_CONSENT_TEST", 0))
end

local function ConsentPrefix(playerID)
    return "EC_VASSAL_" .. ToText(playerID) .. "_CONFIRMATION_"
end

local function ReadConsent(playerID)
    local prefix = ConsentPrefix(playerID)
    local result = {}
    for _, key in ipairs({ "SCHEMA_VERSION", "MODE", "READY", "STATE", "TOKEN", "OVERLORD",
        "CREATED_TURN", "EXPIRES_TURN" }) do
        local value, ok = GetPropertySafe(playerID, prefix .. key, nil)
        if not ok then return nil end
        result[key] = value
    end
    if result.SCHEMA_VERSION ~= SCHEMA_VERSION or result.MODE ~= "DRY_RUN" or result.READY ~= 1
        or type(result.TOKEN) ~= "string" or result.TOKEN == "" or #result.TOKEN > 160
        or not PlayerSlot(result.OVERLORD) or result.OVERLORD == playerID
        or not IsNumber(result.CREATED_TURN) or not IsNumber(result.EXPIRES_TURN)
        or result.CREATED_TURN < 0 or result.EXPIRES_TURN <= result.CREATED_TURN
        or result.CREATED_TURN ~= math.floor(result.CREATED_TURN)
        or result.EXPIRES_TURN ~= math.floor(result.EXPIRES_TURN) then return nil end
    return result
end

local function ConsentPartiesValid(playerID, overlordID)
    local player = Players ~= nil and Players[playerID] or nil
    local overlord = Players ~= nil and Players[overlordID] or nil
    if IsHumanPlayer(player) ~= true or overlord == nil then return false end
    for _, party in ipairs({ player, overlord }) do
        local valid = SafeCall("consent_party", function() return party:IsAlive() and party:IsMajor() end)
        if valid ~= true then return false end
    end
    return true
end

local function MaintainConsent(playerID, turn)
    local request = ReadConsent(playerID)
    if request == nil then return end
    local prefix = ConsentPrefix(playerID)
    if request.STATE ~= nil and request.STATE ~= "PLAYER_CONFIRMATION_PENDING" then return end
    local status = "PLAYER_CONFIRMATION_PENDING"
    if turn >= request.EXPIRES_TURN then status = "EXPIRED"
    elseif not ConsentPartiesValid(playerID, request.OVERLORD) then status = "INVALIDATED" end
    if status ~= request.STATE then SetPropertySafe(playerID, prefix .. "STATE", status) end
end

local function AdvanceConsentTests(metrics, turn)
    if not ConsentTestEnabled() or turn < 0 then return end
    local candidate = nil
    for _, row in ipairs(metrics) do
        local player = Players ~= nil and Players[row.PlayerID] or nil
        if row.Human == false and IsHumanPlayer(player) == false
            and SafeCall("consent_candidate", function() return player:IsAlive() and player:IsMajor() end) == true then
            candidate = row.PlayerID
            break
        end
    end
    for _, row in ipairs(metrics) do
        local playerID = row.PlayerID
        local prefix = ConsentPrefix(playerID)
        local status, statusReadable = GetPropertySafe(playerID, prefix .. "STATE", nil)
        local schema, schemaReadable = GetPropertySafe(playerID, prefix .. "SCHEMA_VERSION", nil)
        local mode, modeReadable = GetPropertySafe(playerID, prefix .. "MODE", nil)
        local ready, readyReadable = GetPropertySafe(playerID, prefix .. "READY", nil)
        if statusReadable and schemaReadable and modeReadable and readyReadable then
            if status ~= nil or ready == 1 then
                MaintainConsent(playerID, turn)
            elseif (schema == nil or schema == SCHEMA_VERSION) and (mode == nil or mode == "DRY_RUN")
                and (ready == nil or ready == 0) and row.Human == true and candidate ~= nil
                and ConsentPartiesValid(playerID, candidate) then
                local cycleTurns = ResolveProjectCycleTurns()
                if cycleTurns ~= nil then
                    local token = "DRY_RUN:" .. playerID .. ":" .. candidate .. ":" .. turn
                    local complete = true
                    for _, property in ipairs({
                        { "SCHEMA_VERSION", SCHEMA_VERSION }, { "MODE", "DRY_RUN" },
                        { "TOKEN", token }, { "OVERLORD", candidate },
                        { "CREATED_TURN", turn }, { "EXPIRES_TURN", turn + cycleTurns },
                        { "READY", 1 },
                    }) do
                        if not SetPropertySafe(playerID, prefix .. property[1], property[2]) then
                            complete = false
                            break
                        end
                    end
                    if complete then
                        MaintainConsent(playerID, turn)
                        Log("consent_test_created player=" .. playerID .. " token=" .. token)
                    end
                end
            end
        end
    end
end

local function OnConsentResponse(playerID, parameters)
    if not ConsentTestEnabled() or type(parameters) ~= "table" or not IsNumber(playerID)
        or parameters.ForPlayer ~= playerID
        or (parameters.Decision ~= "ACCEPT" and parameters.Decision ~= "REJECT") then return end
    local request = ReadConsent(playerID)
    if request == nil or request.STATE ~= "PLAYER_CONFIRMATION_PENDING"
        or parameters.Token ~= request.TOKEN or parameters.Overlord ~= request.OVERLORD then return end
    local turn = SafeCall("consent_turn", function() return Game.GetCurrentGameTurn() end)
    if not IsNumber(turn) or turn < request.CREATED_TURN then return end
    MaintainConsent(playerID, turn)
    if turn >= request.EXPIRES_TURN or not ConsentPartiesValid(playerID, request.OVERLORD) then return end
    request = ReadConsent(playerID)
    if request == nil or request.STATE ~= "PLAYER_CONFIRMATION_PENDING" then return end
    -- Acceptance in this test cannot authorize a future live annexation.
    local nextState = parameters.Decision == "ACCEPT" and "ACCEPTED_DRY_RUN" or "REJECTED"
    if SetPropertySafe(playerID, ConsentPrefix(playerID) .. "STATE", nextState) then
        Log("consent_test_response player=" .. playerID .. " token=" .. request.TOKEN .. " state=" .. nextState)
    end
end

local function CreateShadowVassal(overlordRow, vassalRow, turn, cycleTurns)
    local vassalID = vassalRow.PlayerID
    for _, row in ipairs({ overlordRow, vassalRow }) do
        local player = Players ~= nil and Players[row.PlayerID] or nil
        if SafeCall("shadow_create_party", function() return player:IsAlive() and player:IsMajor() end) ~= true
            or IsHumanPlayer(player) ~= row.Human or IsShadowVassal(row.PlayerID) ~= false then return false end
    end
    local prefix = "EC_VASSAL_" .. ToText(vassalID) .. "_"
    local disposition = ShadowDisposition(overlordRow.PlayerID, vassalID)
    local project, focus = ChooseShadowProject(overlordRow, vassalRow, 0, disposition)
    if project == nil then return false end
    local properties = {
        { "SCHEMA_VERSION", SCHEMA_VERSION }, { "OVERLORD", overlordRow.PlayerID },
        { "CIV_TYPE", "UNVERIFIED" }, { "CAPTURE_TURN", turn },
        { "AUTONOMY", 0 }, { "AUTONOMY_TARGET", 100 },
        { "PROJECT_POLICY_VERSION", PROJECT_POLICY_VERSION }, { "PROJECT_DISPOSITION", disposition },
        { "PROJECT", project }, { "PROJECT_FOCUS", focus },
        { "PROJECT_START_TURN", turn }, { "PROJECT_END_TURN", turn + cycleTurns },
        { "PROJECT_PENDING_TOKEN", -1 }, { "PROJECT_APPLIED_TOKEN", -1 },
        { PROJECT_EFFECT_TOKEN, -1 }, { PROJECT_EFFECT_STATE, "NONE" },
    }
    for _, property in ipairs(properties) do
        if not SetPropertySafe(vassalID, prefix .. property[1], property[2]) then return false end
    end
    if not SetPropertySafe(vassalID, prefix .. "STATE", "SHADOW_ARCHIVED") then return false end
    State.ShadowVassals[vassalID] = overlordRow.PlayerID
    Log("shadow_vassal_created vassal=" .. ToText(vassalID)
        .. " overlord=" .. ToText(overlordRow.PlayerID)
        .. " turn=" .. ToText(turn)
        .. " cycle_turns=" .. ToText(cycleTurns))
    return true
end

local function AdvanceShadowVassalProject(vassalID, turn, cycleTurns, metricsByID)
    local native=HasCallable(Game,"GetProperty") and EC_NativeVassals.ReadArchive(Game,vassalID)
    local real=type(native)=="table" and native.Schema==1 and native.VassalID==vassalID and native.State=="VASSALIZED"
    if IsShadowVassal(vassalID) ~= true or (not real and IsHumanPlayer(Players ~= nil and Players[vassalID] or nil) ~= false) then return end
    if real and native.Metrics then metricsByID[vassalID]=native.Metrics end
    local prefix = "EC_VASSAL_" .. ToText(vassalID) .. "_"
    local schema, readable = GetPropertySafe(vassalID, prefix .. "SCHEMA_VERSION", nil)
    if not readable or (schema ~= nil and schema ~= SCHEMA_VERSION) then
        Log("shadow_schema_unsupported player=" .. ToText(vassalID))
        return
    end
    local fields = {}
    for _, key in ipairs({ "AUTONOMY", "PROJECT_START_TURN", "PROJECT_END_TURN", "OVERLORD" }) do
        local value, ok = GetPropertySafe(vassalID, prefix .. key, nil)
        if not ok or not IsNumber(value) then return end
        fields[key] = value
    end
    local project = GetPropertySafe(vassalID, prefix .. "PROJECT", nil)
    if project ~= "SUPPORT_OVERLORD" and project ~= "WEAKEN_OVERLORD" then return end
    local policy, policyReadable = GetPropertySafe(vassalID, prefix .. "PROJECT_POLICY_VERSION", nil)
    local disposition, dispositionReadable = GetPropertySafe(vassalID, prefix .. "PROJECT_DISPOSITION", nil)
    if not policyReadable or not dispositionReadable or (policy ~= nil and policy ~= PROJECT_POLICY_VERSION)
        or (policy ~= nil and disposition == nil)
        or (disposition ~= nil and disposition ~= "COOPERATIVE" and disposition ~= "DEFIANT") then return end
    local pending, pendingReadable = GetPropertySafe(vassalID, prefix .. "PROJECT_PENDING_TOKEN", -1)
    local applied, appliedReadable = GetPropertySafe(vassalID, prefix .. "PROJECT_APPLIED_TOKEN", -1)
    local effectApplied, effectReadable = GetPropertySafe(vassalID, prefix .. PROJECT_EFFECT_TOKEN, -1)
    local effectState, effectStateReadable = GetPropertySafe(vassalID, prefix .. PROJECT_EFFECT_STATE, "NONE")
    if not pendingReadable or not appliedReadable or not IsNumber(pending) or not IsNumber(applied)
        or not effectReadable or not IsNumber(effectApplied)
        or not effectStateReadable or (effectState ~= "NONE" and effectState ~= "PENDING"
            and effectState ~= "APPLIED" and effectState ~= "CAPPED" and effectState ~= "UNKNOWN")
        or pending < -1 or applied < -1 or effectApplied < -1
        or pending ~= math.floor(pending) or applied ~= math.floor(applied)
        or effectApplied ~= math.floor(effectApplied) then return end
    if fields.AUTONOMY < 0 or fields.AUTONOMY > 100
        or fields.AUTONOMY ~= math.floor(fields.AUTONOMY)
        or fields.PROJECT_START_TURN < 0 or fields.PROJECT_END_TURN < 0
        or fields.PROJECT_START_TURN ~= math.floor(fields.PROJECT_START_TURN)
        or fields.PROJECT_END_TURN ~= math.floor(fields.PROJECT_END_TURN)
        or fields.OVERLORD == vassalID
        or (pending <= applied and fields.PROJECT_END_TURN <= fields.PROJECT_START_TURN) then return end
    if not PlayerSlot(fields.OVERLORD) then
        Log("shadow_overlord_unknown player=" .. ToText(vassalID)
            .. " overlord=" .. ToText(fields.OVERLORD))
        return
    end
    for _, id in ipairs({ fields.OVERLORD, vassalID }) do
        if SafeCall("project_party_alive", function() return Players[id]:IsAlive() end) ~= true then return end
    end
    if schema == nil and not SetPropertySafe(vassalID, prefix .. "SCHEMA_VERSION", SCHEMA_VERSION) then return end
    if pending <= applied then
        -- Shadow archives cannot restore territory; stop at the autonomy cap.
        if fields.AUTONOMY == 100 then return end
        if turn < fields.PROJECT_END_TURN then return end
        local overlordRow, vassalRow = metricsByID[fields.OVERLORD], metricsByID[vassalID]
        if overlordRow == nil or vassalRow == nil then return end
        local currentFocus, focusReadable = GetPropertySafe(vassalID, prefix .. "PROJECT_FOCUS",
            policy == nil and "GENERAL" or nil)
        if not focusReadable or not IsProjectFocus(currentFocus) then return end
        disposition = disposition or ShadowDisposition(fields.OVERLORD, vassalID)
        local nextProject, nextFocus = ChooseShadowProject(overlordRow, vassalRow,
            math.min(100, fields.AUTONOMY + 10), disposition)
        if nextProject == nil then return end
        if ProjectEffectsEnabled() then
            local effectToken = fields.PROJECT_END_TURN
            if effectState == "UNKNOWN" then return end
            if effectState == "PENDING" and effectApplied == effectToken then return end
            if (effectState ~= "APPLIED" and effectState ~= "CAPPED") or effectApplied ~= effectToken then
                local budget = PrepareProjectBudget(fields.OVERLORD)
                local modifier = PROJECT_EFFECT_MODIFIERS[project][currentFocus]
                if budget == nil or modifier == nil then return end
                local effect = string.sub(modifier, #"EC_PROJECT_" + 1)
                local capped = budget[effect] >= PROJECT_EFFECT_LIMIT
                -- Reserve a slot before the native call. An uncertain outcome
                -- keeps that slot, rather than granting another attempt.
                if not capped and not SetPropertySafe(fields.OVERLORD,
                    PROJECT_BUDGET_PREFIX .. effect .. "_COUNT", budget[effect] + 1) then return end
                if not SetPropertySafe(vassalID, prefix .. PROJECT_EFFECT_STATE, "PENDING")
                    or not SetPropertySafe(vassalID, prefix .. PROJECT_EFFECT_TOKEN, effectToken) then return end
                effectState, effectApplied = "PENDING", effectToken
                if not capped and not ApplyShadowProjectEffect(vassalID, fields.OVERLORD, project, currentFocus,
                    effectToken) then
                    SetPropertySafe(vassalID, prefix .. PROJECT_EFFECT_STATE, "UNKNOWN")
                    return
                end
                if capped then
                    Log("project_effect_capped overlord=" .. fields.OVERLORD .. " vassal=" .. vassalID
                        .. " modifier=" .. modifier .. " limit=" .. PROJECT_EFFECT_LIMIT)
                end
                local outcome = capped and "CAPPED" or "APPLIED"
                if not SetPropertySafe(vassalID, prefix .. PROJECT_EFFECT_STATE, outcome) then return end
                effectState = outcome
            end
        end
        if policy == nil then
            for _, property in ipairs({ { "PROJECT_DISPOSITION", disposition },
                { "PROJECT_FOCUS", currentFocus }, { "PROJECT_POLICY_VERSION", PROJECT_POLICY_VERSION } }) do
                if not SetPropertySafe(vassalID, prefix .. property[1], property[2]) then return end
            end
            policy = PROJECT_POLICY_VERSION
        end
        -- Stage the complete next result before updating any published fields.
        -- A retry reapplies these fixed values rather than awarding autonomy twice.
        local staged = {
            { "PROJECT_NEXT_AUTONOMY", math.min(100, fields.AUTONOMY + 10) },
            { "PROJECT_NEXT_TYPE", nextProject }, { "PROJECT_NEXT_FOCUS", nextFocus },
            { "PROJECT_NEXT_START_TURN", turn }, { "PROJECT_NEXT_END_TURN", turn + cycleTurns },
        }
        for _, property in ipairs(staged) do
            if not SetPropertySafe(vassalID, prefix .. property[1], property[2]) then return end
        end
        pending = fields.PROJECT_END_TURN
        if not SetPropertySafe(vassalID, prefix .. "PROJECT_PENDING_TOKEN", pending) then return end
    end
    local nextAutonomy = GetPropertySafe(vassalID, prefix .. "PROJECT_NEXT_AUTONOMY", nil)
    local nextProject = GetPropertySafe(vassalID, prefix .. "PROJECT_NEXT_TYPE", nil)
    local nextStart = GetPropertySafe(vassalID, prefix .. "PROJECT_NEXT_START_TURN", nil)
    local nextEnd = GetPropertySafe(vassalID, prefix .. "PROJECT_NEXT_END_TURN", nil)
    local nextFocus, focusReadable = GetPropertySafe(vassalID, prefix .. "PROJECT_NEXT_FOCUS",
        policy == nil and "GENERAL" or nil)
    if turn < pending
        or not IsNumber(nextAutonomy) or not IsNumber(nextStart) or not IsNumber(nextEnd)
        or nextAutonomy < 0 or nextAutonomy > 100 or nextAutonomy ~= math.floor(nextAutonomy)
        or nextStart < pending or nextStart > turn or nextEnd <= nextStart
        or nextStart ~= math.floor(nextStart) or nextEnd ~= math.floor(nextEnd)
        or (nextProject ~= "SUPPORT_OVERLORD" and nextProject ~= "WEAKEN_OVERLORD")
        or not focusReadable or not IsProjectFocus(nextFocus) then return end
    for _, property in ipairs({
        { "AUTONOMY", nextAutonomy }, { "PROJECT", nextProject },
        { "PROJECT_FOCUS", nextFocus },
        { "PROJECT_START_TURN", nextStart }, { "PROJECT_END_TURN", nextEnd },
    }) do
        if not SetPropertySafe(vassalID, prefix .. property[1], property[2]) then return end
    end
    if not SetPropertySafe(vassalID, prefix .. "PROJECT_APPLIED_TOKEN", pending) then return end
    Log("shadow_vassal_project vassal=" .. ToText(vassalID)
        .. " autonomy=" .. ToText(nextAutonomy)
        .. " project=" .. ToText(project)
        .. " next_project=" .. ToText(nextProject)
        .. " next_focus=" .. ToText(nextFocus)
        .. " turn=" .. ToText(turn)
        .. " cycle_turns=" .. ToText(cycleTurns))
end

local function AdvanceShadowVassals(metrics, turn)
    if not IsFalse(ReadConfig("EC_OBSERVATION_ONLY", 1))
        or not IsTrue(ReadConfig("EC_SHADOW_VASSAL_TEST", 0))
        or #metrics < 2 then
        return
    end

    RestoreShadowVassals(metrics)
    local cycleTurns, speedMultiplier, speedType = ResolveProjectCycleTurns()
    if cycleTurns == nil then return end
    local limit = tonumber(ReadConfig("EC_SHADOW_VASSAL_LIMIT", 1)) or 1
    limit = math.max(1, math.min(math.floor(limit), #metrics - 1))

    local overlord = nil
    for _, row in ipairs(metrics) do
        if IsShadowVassal(row.PlayerID) == false and row.Human ~= nil and row.ProjectMetricsComplete then
            overlord = row
            break
        end
    end
    if overlord == nil then
        return
    end

    local existing = 0
    for _, row in ipairs(metrics) do
        -- Unreadable/unknown archives occupy capacity until verified.
        if IsShadowVassal(row.PlayerID) ~= false then
            existing = existing + 1
        end
    end

    local remaining = math.max(0, limit - existing)
    local created = 0
    for index = #metrics, 1, -1 do
        if created >= remaining then
            break
        end
        local vassal = metrics[index]
        if vassal.PlayerID ~= overlord.PlayerID and vassal.Human == false
            and IsShadowVassal(vassal.PlayerID) == false then
            if CreateShadowVassal(overlord, vassal, turn, cycleTurns) then
                created = created + 1
            end
        end
    end

    local metricsByID = {}
    for _, row in ipairs(metrics) do metricsByID[row.PlayerID] = row end
    for _, row in ipairs(metrics) do
        if State.ShadowVassals[row.PlayerID] ~= nil then
            AdvanceShadowVassalProject(row.PlayerID, turn, cycleTurns, metricsByID)
        end
    end

    if created > 0 then
        Log("shadow_vassal_batch limit=" .. ToText(limit)
            .. " existing=" .. ToText(existing)
            .. " created=" .. ToText(created)
            .. " cycle_turns=" .. ToText(cycleTurns)
            .. " speed_multiplier=" .. ToText(speedMultiplier)
            .. " speed_type=" .. ToText(speedType))
    end
end

local function AwakeningOwnerID()
    if not HasCallable(GameConfiguration, "IsAnyMultiplayer")
        or SafeCall("awakening_owner_single_player", function()
            return GameConfiguration.IsAnyMultiplayer()
        end) ~= false then return nil end
    local turn = SafeCall("awakening_owner_turn", function() return Game.GetCurrentGameTurn() end)
    if not IsNumber(turn) or turn < 0 or turn ~= math.floor(turn) then return nil end
    local cached = State.AwakeningOwner
    if cached ~= nil and cached.Turn == turn then return cached.ID end
    State.AwakeningOwner = { Turn = turn }
    local id = SingleObserverID()
    if id == nil then return nil end
    -- Old versions stored every campaign on slot 0. Do not silently start a
    -- second live campaign when a nonzero human loads such a legacy save.
    if id ~= 0 and Players ~= nil and Players[0] ~= nil then
        for _, marker in ipairs({ AWAKENING_STATE_KEY, AWAKENING_SCHEMA_KEY,
            AWAKENING_MODE_KEY, AWAKENING_READY_KEY, AWAKENING_CIV_KEY }) do
            local value, readable = GetPropertySafe(0, marker, nil)
            if not readable or value ~= nil then
                Log("awakening_legacy_owner_conflict owner=" .. ToText(id))
                return nil
            end
        end
    end
    State.AwakeningOwner.ID = id
    return id
end

local function GetAwakeningProperty(key, defaultValue)
    local owner = AwakeningOwnerID()
    if owner == nil then return defaultValue, false end
    return GetPropertySafe(owner, key, defaultValue)
end

local function SetAwakeningProperty(key, value)
    local owner = AwakeningOwnerID()
    return owner ~= nil and SetPropertySafe(owner, key, value)
end

local function RestoreAwakeningState()
    local previousState = State.AwakeningState
    State.AwakeningState, State.AwakeningCandidateID = nil, nil
    local schema, schemaReadable = GetAwakeningProperty(AWAKENING_SCHEMA_KEY, nil)
    local mode, modeReadable = GetAwakeningProperty(AWAKENING_MODE_KEY, nil)
    if not schemaReadable or not modeReadable or (schema ~= nil and schema ~= SCHEMA_VERSION)
        or (mode ~= nil and mode ~= AwakeningMode()) then
        Log("awakening_schema_or_mode_unsupported")
        return nil
    end
    local status, readable = GetAwakeningProperty(AWAKENING_STATE_KEY, "LOCKED")
    local known = { LOCKED = true, TRIGGERED = true, PREPARATION = true, CONQUEST = true, SHOWDOWN = true, RESOLVED = true }
    if not readable or not known[status] then
        Log("awakening_state_unreadable_or_unknown")
        return nil
    end
    if mode == nil and status ~= "LOCKED" and AwakeningMode() == "LIVE_TEST" then
        Log("awakening_legacy_not_live_authorization")
        return nil
    end
    local candidate, candidateReadable = GetAwakeningProperty(AWAKENING_CIV_KEY, nil)
    if status ~= "LOCKED" then
        if not candidateReadable or not PlayerSlot(candidate) then
            Log("awakening_candidate_unreadable_or_unknown")
            return nil
        end
        State.AwakeningCandidateID = candidate
    else
        State.AwakeningCandidateID = nil
    end
    if previousState == nil and status ~= "LOCKED" then
        Log("awakening_state_restored state=" .. status)
    end
    State.AwakeningState = status
    return status, schema
end

local function ReadAwakeningPayload()
    local payload = {}
    for _, key in ipairs({ AWAKENING_CIV_KEY, AWAKENING_TRIGGER_TURN_KEY, AWAKENING_PREP_END_KEY, AWAKENING_CONQUEST_END_KEY }) do
        local value, readable = GetAwakeningProperty(key, nil)
        if not readable or not IsNumber(value) or value < 0 or value ~= math.floor(value) then
            Log("awakening_payload_incomplete key=" .. key)
            return nil
        end
        payload[key] = value
    end
    if payload[AWAKENING_PREP_END_KEY] <= payload[AWAKENING_TRIGGER_TURN_KEY]
        or payload[AWAKENING_CONQUEST_END_KEY] <= payload[AWAKENING_PREP_END_KEY] then return nil end
    return payload
end

local function SetAwakeningState(nextState, turn, reason)
    local previousState = State.AwakeningState or "LOCKED"
    if previousState == nextState then
        return true
    end
    if not SetAwakeningProperty(AWAKENING_LAST_TRANSITION_KEY, turn)
        or not SetAwakeningProperty(AWAKENING_STATE_KEY, nextState) then
        return false
    end
    State.AwakeningState = nextState
    Log("awakening_state_transition from=" .. ToText(previousState)
        .. " to=" .. ToText(nextState)
        .. " turn=" .. ToText(turn)
        .. " reason=" .. ToText(reason))
    return true
end

local function AwakeningMinimumDistance()
    local value = tonumber(ReadConfig("EC_AWAKENING_MIN_DISTANCE", 12))
    if not IsNumber(value) or value < 0 or value ~= math.floor(value) then
        return nil
    end
    return value
end

local function ChooseAwakeningCandidate(metrics)
    local humanID = SingleObserverID()
    if humanID == nil then return nil end
    local minimumDistance = AwakeningMinimumDistance()
    if minimumDistance == nil then
        Log("awakening_candidate_policy_invalid_distance")
        return nil
    end

    local aiRows = {}
    for _, row in ipairs(metrics) do
        if row.Human == false and row.ProjectMetricsComplete and row.Cities > 0
            and IsShadowVassal(row.PlayerID) == false then
            aiRows[#aiRows + 1] = row
        end
    end

    if #aiRows == 0 then return nil end
    local rankLimit = math.max(1, math.floor(#aiRows * AWAKENING_TOP_PERCENT / 100))
    local origin = nil
    if minimumDistance > 0 then
        if not HasCallable(Map, "GetPlotDistance") then
            Log("awakening_candidate_distance_unknown reason=DISTANCE_API_UNKNOWN")
            return nil
        end
        origin = ProtectionCapital(humanID)
        if origin == nil then
            Log("awakening_candidate_distance_unknown reason=PLAYER_CAPITAL_UNKNOWN")
            return nil
        end
    end

    local selected, selectedRank, selectedDistance = nil, nil, nil
    local farthestRows = {}
    if minimumDistance > 0 then
        for _, row in ipairs(aiRows) do
            local capital = ProtectionCapital(row.PlayerID)
            if capital == nil then
                Log("awakening_candidate_distance_unknown player=" .. ToText(row.PlayerID))
                return nil
            end
            local distance = SafeCall("awakening_candidate_distance_" .. ToText(row.PlayerID), function()
                return Map.GetPlotDistance(origin.X, origin.Y, capital.X, capital.Y)
            end)
            if not IsNumber(distance) or distance < 0 then
                Log("awakening_candidate_distance_unknown player=" .. ToText(row.PlayerID))
                return nil
            end
            row.AwakeningDistance = distance
            farthestRows[#farthestRows + 1] = row
        end
        table.sort(farthestRows, function(a, b)
            if a.AwakeningDistance == b.AwakeningDistance then
                if a.Power == b.Power then return a.PlayerID < b.PlayerID end
                return a.Power > b.Power
            end
            return a.AwakeningDistance > b.AwakeningDistance
        end)
    else
        for _, row in ipairs(aiRows) do farthestRows[#farthestRows + 1] = row end
    end

    local farthestLimit = math.max(1, math.floor(#farthestRows * AWAKENING_FARTHEST_PERCENT / 100))
    local farthestIDs = {}
    for index = 1, math.min(farthestLimit, #farthestRows) do
        farthestIDs[farthestRows[index].PlayerID] = true
    end
    for rank = 1, math.min(rankLimit, #aiRows) do
        local row = aiRows[rank]
        local distance = row.AwakeningDistance or 0
        if farthestIDs[row.PlayerID] and (minimumDistance == 0 or distance >= minimumDistance)
            and (selected == nil or distance > selectedDistance
                or (distance == selectedDistance and rank < selectedRank)
                or (distance == selectedDistance and rank == selectedRank and row.PlayerID < selected.PlayerID)) then
            selected, selectedRank, selectedDistance = row, rank, distance
        end
    end
    if selected == nil then return nil end
    selected.AwakeningRank = selectedRank
    selected.AwakeningDistance = selectedDistance
    Log("awakening_candidate_policy ai_top_percent=" .. ToText(AWAKENING_TOP_PERCENT)
        .. " farthest_percent=" .. ToText(AWAKENING_FARTHEST_PERCENT)
        .. " ai_rank=" .. ToText(selectedRank) .. " ai_count=" .. ToText(#aiRows)
        .. " distance=" .. ToText(selectedDistance) .. " min_distance=" .. ToText(minimumDistance)
        .. " selection=farthest_strong_ai")
    return selected
end

local function CandidateIsEligible()
    if State.AwakeningCandidateID == nil then
        return false
    end
    if Players == nil then return nil end
    local player = Players[State.AwakeningCandidateID]
    if player == nil then return false, "candidate_not_alive" end
    if not HasCallable(player, "IsAlive") then return nil end
    local alive = SafeCall("candidate_alive", function() return player:IsAlive() end)
    if alive == false then return false, "candidate_not_alive" end
    if alive ~= true then return nil end
    local human = IsHumanPlayer(player)
    if human == nil then return nil end
    if human then return false, "candidate_no_longer_ai" end
    local major = SafeCall("candidate_major", function() return player:IsMajor() end)
    if major == false then return false, "candidate_no_longer_major" end
    if major ~= true then return nil end
    local archived = IsShadowVassal(State.AwakeningCandidateID)
    if archived == true then return false, "candidate_no_longer_independent" end
    if archived ~= false then return nil end
    local cities, citiesKnown = CountCities(player)
    if not citiesKnown then return nil end
    if cities == 0 then return false, "candidate_no_cities" end
    return true
end

local function AwakeningMinimumTurn()
    if DebugTimingEnabled() then Log("awakening_minimum_read_config") end
    local base = tonumber(ReadConfig("EC_AWAKENING_MIN_TURN", 120))
    if DebugTimingEnabled() then Log("awakening_minimum_read_speed") end
    local _, multiplier = ResolveProjectCycleTurns()
    if DebugTimingEnabled() then Log("awakening_minimum_speed_ready") end
    if not IsNumber(base) or base < 0 or base ~= math.floor(base)
        or not IsNumber(multiplier) or multiplier <= 0 then return nil end
    local turn = math.ceil(base * multiplier / 100)
    if IsNumber(turn) and turn >= 0 then return turn end
    return nil
end

local function CommitAwakeningPayload(payload)
    for _, property in ipairs({
        { AWAKENING_SCHEMA_KEY, SCHEMA_VERSION }, { AWAKENING_MODE_KEY, AwakeningMode() },
        { AWAKENING_CIV_KEY, payload[AWAKENING_CIV_KEY] },
        { AWAKENING_TRIGGER_TURN_KEY, payload[AWAKENING_TRIGGER_TURN_KEY] },
        { AWAKENING_PREP_END_KEY, payload[AWAKENING_PREP_END_KEY] },
        { AWAKENING_CONQUEST_END_KEY, payload[AWAKENING_CONQUEST_END_KEY] },
    }) do
        if not SetAwakeningProperty(property[1], property[2]) then return false end
    end
    return SetAwakeningProperty(AWAKENING_READY_KEY, 1)
end

local function AdvanceAwakening(metrics, turn, deadPercent, triggerByEra, triggerByCollapse)
    if not IsFalse(ReadConfig("EC_OBSERVATION_ONLY", 1))
        or (not IsTrue(ReadConfig("EC_AWAKENING_DRY_RUN", 0)) and not AwakeningActionsEnabled())
        or #metrics == 0 then
        return
    end

    local state, schema = RestoreAwakeningState()
    if state == nil then return end
    local ready, readyReadable = GetAwakeningProperty(AWAKENING_READY_KEY, 0)
    if not readyReadable then return end
    local minimumTurn = AwakeningMinimumTurn()
    local targetDeadPercent = tonumber(ReadConfig("EC_AWAKENING_DEAD_PERCENT", 30)) or 30
    local trigger = minimumTurn ~= nil and turn >= minimumTurn and (triggerByEra or triggerByCollapse)

    local payload = nil
    if state ~= "LOCKED" or ready == 1 then
        payload = ReadAwakeningPayload()
        if payload == nil then return end
        -- Adopt legacy property-only records only after validating every field.
        if schema == nil then
            if not CommitAwakeningPayload(payload) then return end
        elseif ready ~= 1 then
            Log("awakening_payload_not_committed")
            return
        end
    elseif state == "LOCKED" and trigger then
        local candidate = ChooseAwakeningCandidate(metrics)
        if candidate == nil then
            Log("awakening_candidate_unavailable turn=" .. ToText(turn))
            return
        end
        local prepBase = tonumber(ReadConfig("EC_AWAKENING_PREP_TURNS", 20))
        local conquestBase = tonumber(ReadConfig("EC_AWAKENING_CONQUEST_TURNS", 50))
        local _, multiplier = ResolveProjectCycleTurns()
        if not IsNumber(prepBase) or prepBase < 1 or not IsNumber(conquestBase) or conquestBase < 1
            or not IsNumber(multiplier) or multiplier <= 0 then
            Log("awakening_duration_invalid")
            return
        end
        local prepTurns = math.ceil(prepBase * multiplier / 100)
        local conquestTurns = math.ceil(conquestBase * multiplier / 100)
        if not IsNumber(prepTurns) or not IsNumber(conquestTurns) then return end
        payload = {
            [AWAKENING_CIV_KEY] = candidate.PlayerID, [AWAKENING_TRIGGER_TURN_KEY] = turn,
            [AWAKENING_PREP_END_KEY] = turn + prepTurns,
            [AWAKENING_CONQUEST_END_KEY] = turn + prepTurns + conquestTurns,
        }
        if not CommitAwakeningPayload(payload) then return end
    end
    if payload == nil then return end
    State.AwakeningCandidateID = payload[AWAKENING_CIV_KEY]
    local lastTransition, transitionReadable = GetAwakeningProperty(AWAKENING_LAST_TRANSITION_KEY, -1)
    if not transitionReadable or not IsNumber(lastTransition) or lastTransition >= turn then return end
    if state == "RESOLVED" then return end
    local alive, ineligibleReason = CandidateIsEligible()
    if alive == nil then
        Log("awakening_candidate_status_unknown")
        return
    elseif alive == false then
        SetAwakeningState("RESOLVED", turn, ineligibleReason)
        return
    end
    if state == "LOCKED" then
        if SetAwakeningState("TRIGGERED", turn, (triggerByEra and "era" or "collapse")) then
            Log((AwakeningMode() == "DRY_RUN" and "awakening_dry_run_trigger" or "awakening_live_test_trigger")
                .. " candidate=" .. ToText(State.AwakeningCandidateID)
                .. " dead_percent=" .. ToText(deadPercent)
                .. " target_dead_percent=" .. ToText(targetDeadPercent)
                .. " trigger_turn=" .. ToText(payload[AWAKENING_TRIGGER_TURN_KEY]))
        end
        return
    end

    if state == "TRIGGERED" then
        SetAwakeningState("PREPARATION", turn, "trigger_acknowledged")
        return
    end

    if state == "PREPARATION" then
        local prepEnd = payload[AWAKENING_PREP_END_KEY]
        if turn >= prepEnd then
            SetAwakeningState("CONQUEST", turn, "preparation_complete")
        end
        return
    end

    if state == "CONQUEST" then
        local conquestEnd = payload[AWAKENING_CONQUEST_END_KEY]
        if turn >= conquestEnd then
            SetAwakeningState("SHOWDOWN", turn, "conquest_window_complete")
        end
        return
    end

end

local function RunAwakeningActions(turn)
    if not AwakeningActionsEnabled() or State.AwakeningState == nil or State.AwakeningState == "LOCKED" then return end
    local payload = ReadAwakeningPayload()
    local mode, modeOK = GetAwakeningProperty(AWAKENING_MODE_KEY, nil)
    local ready, readyOK = GetAwakeningProperty(AWAKENING_READY_KEY, nil)
    local transition, transitionOK = GetAwakeningProperty(AWAKENING_LAST_TRANSITION_KEY, nil)
    if payload == nil or not modeOK or mode ~= "LIVE_TEST" or not readyOK or ready ~= 1
        or not transitionOK or not IsNumber(transition) or transition ~= math.floor(transition)
        or transition < payload[AWAKENING_TRIGGER_TURN_KEY] or transition > turn
        or turn < payload[AWAKENING_TRIGGER_TURN_KEY] or CandidateIsEligible() ~= true then return end
    if (State.AwakeningState == "CONQUEST" and turn < payload[AWAKENING_PREP_END_KEY])
        or (State.AwakeningState == "SHOWDOWN" and turn < payload[AWAKENING_CONQUEST_END_KEY]) then return end
    local humanID = SingleObserverID()
    local interval = ResolveProjectCycleTurns()
    if humanID == nil or interval == nil then return end
    local ok, reason = SafeCall("awakening_actions", function()
        return EC_AwakeningActions.Update({ Enabled = true, ObservationOnly = false, DryRun = false,
            Mode = mode, Turn = turn, Stage = State.AwakeningState, AwakenedID = State.AwakeningCandidateID,
            HumanID = humanID, WarInterval = interval, IsIndependent = function(id) return IsShadowVassal(id) == false end,
            IsProtected = ProtectionForObservation(turn, humanID), Log = Log })
    end)
    Log("awakening_actions_update turn=" .. ToText(turn) .. " success=" .. ToText(ok) .. " reason=" .. ToText(reason))
end

local function RunNativeVictory(turn)
    if not State.NativeStarted or not AwakeningActionsEnabled()
        or GameConfiguration.IsAnyMultiplayer()~=false or SingleObserverID()==nil then return end
    local stage,id=State.AwakeningState,State.AwakeningCandidateID
    if stage==nil or stage=="LOCKED" or not PlayerSlot(id) then return end
    local mode,known=GetAwakeningProperty(AWAKENING_MODE_KEY,nil)
    if not known or mode~="LIVE_TEST" then return end
    local ok,reason=pcall(function()
        local winner=Game.GetWinningTeam()
        assert(winner==nil or (IsNumber(winner) and winner>=0 and winner==math.floor(winner)),
            "Native winning team unknown")
        if winner~=nil and stage~="RESOLVED" then
            assert(SetAwakeningState("RESOLVED",turn,"native_victory_team_"..ToText(winner)),
                "Native victory state could not be resolved")
            stage="RESOLVED"
        end
        local success,status=EC_NativeVictory.Update({Players=Players,Game=Game,GameInfo=GameInfo,GameEffects=GameEffects},
            {SinglePlayer=true,Enabled=true,PlayerID=id,Stage=stage,Turn=turn})
        if status~="ALREADY_APPLIED" then Log("native_victory_gate player="..id.." stage="..stage.." status="..status) end
        assert(success,status)
    end)
    if not ok then Log("native_victory_failed reason="..ToText(reason)) end
end

local function OnNativeTeamVictory(team)
    -- Read the engine result; a notification alone cannot resolve the crisis.
    local winner=SafeCall("native_team_victory",function() return Game.GetWinningTeam() end)
    if not IsNumber(team) or winner~=team then return end
    local turn=SafeCall("native_victory_turn",function() return Game.GetCurrentGameTurn() end)
    if IsNumber(turn) and turn>=0 and turn==math.floor(turn) then
        -- A verified engine victory can occur immediately after loading,
        -- before the first turn/metric event. It proves the native world is
        -- active without weakening the initialization-time access gate.
        State.NativeStarted=true
        RunNativeVictory(turn)
    end
end

local function ReadWarStatus(first, second)
    local firstID = ReadPlayerID(first, "war_first_player_id")
    local secondID = ReadPlayerID(second, "war_second_player_id")
    if firstID == nil or secondID == nil then return nil end
    local firstStatus = SafeCall("war_status_" .. ToText(firstID) .. "_" .. ToText(secondID), function()
        return first:GetDiplomacy():IsAtWarWith(secondID)
    end)
    local secondStatus = SafeCall("war_status_" .. ToText(secondID) .. "_" .. ToText(firstID), function()
        return second:GetDiplomacy():IsAtWarWith(firstID)
    end)
    if type(firstStatus) ~= "boolean" or type(secondStatus) ~= "boolean" or firstStatus ~= secondStatus then
        return nil
    end
    return firstStatus
end

local function ObserveWarPairs(majors, turn)
    if not WarObservationEnabled() or turn < 0 then return end
    local timingEnabled = DebugTimingEnabled()
    local startedMs = timingEnabled and ReadClockMs() or nil
    local pairLimit = 256
    local pairs = {}
    for firstIndex = 1, #majors do
        for secondIndex = firstIndex + 1, #majors do
            pairs[#pairs + 1] = { majors[firstIndex], majors[secondIndex] }
        end
    end
    if #pairs == 0 then return end
    local cursor, cursorReadable = GetPropertySafe(0, WAR_PAIR_CURSOR_KEY, 1)
    cursor = tonumber(cursor)
    if not cursorReadable or cursor == nil or cursor ~= math.floor(cursor) then cursor = 1 end
    cursor = ((cursor - 1) % #pairs) + 1
    local checked, observed, complete = 0, 0, true
    local checks = math.min(pairLimit, #pairs)
    for offset = 0, checks - 1 do
        local index = ((cursor - 1 + offset) % #pairs) + 1
        local first, second = pairs[index][1], pairs[index][2]
        checked = checked + 1
        local firstID = ReadPlayerID(first, "war_pair_first_id")
        local secondID = ReadPlayerID(second, "war_pair_second_id")
        if firstID == nil or secondID == nil then
            complete = false
        else
            local atWar = ReadWarStatus(first, second)
            local warPrefix = "EC_WAR_" .. ToText(firstID) .. "_"
            local schema = GetPropertySafe(secondID, warPrefix .. "SCHEMA", nil)
            local activeBank = GetPropertySafe(secondID, warPrefix .. "ACTIVE_BANK", nil)
            local existing = schema == 1 and (activeBank == 1 or activeBank == 2)
            if not existing then
                local reversePrefix = "EC_WAR_" .. ToText(secondID) .. "_"
                local reverseSchema = GetPropertySafe(firstID, reversePrefix .. "SCHEMA", nil)
                local reverseBank = GetPropertySafe(firstID, reversePrefix .. "ACTIVE_BANK", nil)
                existing = reverseSchema == 1 and (reverseBank == 1 or reverseBank == 2)
            end
            if atWar ~= nil and (atWar or existing == true) then
                local ok = SafeCall("war_observation_changed", function()
                    return EC_EligibilityObserver.WarChanged(firstID, secondID, atWar, turn)
                end)
                if ok == true then observed = observed + 1 end
            end
        end
    end
    complete = complete and checked >= #pairs
    local nextCursor = ((cursor - 1 + checked) % #pairs) + 1
    if not SetPropertySafe(0, WAR_PAIR_CURSOR_KEY, nextCursor) then
        Log("war_observation_cursor_store_failed turn=" .. ToText(turn)
            .. " next=" .. ToText(nextCursor))
    end
    Log("war_observation_pairs turn=" .. ToText(turn)
        .. " checked=" .. ToText(checked)
        .. " observed=" .. ToText(observed)
        .. " complete=" .. ToText(complete))
    if timingEnabled and startedMs ~= nil then
        local finishedMs = ReadClockMs()
        if finishedMs ~= nil then
            Log("war_observation_timing turn=" .. ToText(turn)
                .. " elapsed_ms=" .. TimingResult(startedMs,finishedMs)
                .. " checked=" .. ToText(checked)
                .. " observed=" .. ToText(observed))
        end
    end
end

local function OnCityConqueredObserved(attackerID, targetID, cityID, cityX, cityY)
    if not WarObservationEnabled() then return end
    local turn = SafeCall("city_conquered_turn", function() return Game.GetCurrentGameTurn() end)
    if not IsNumber(turn) or turn < 0 or turn ~= math.floor(turn) then
        Log("war_observation_city_conquered_invalid_turn")
        return
    end
    local accepted, reason = SafeCall("city_conquered_observation", function()
        return EC_EligibilityObserver.CityConquered(attackerID, targetID, cityID, cityX, cityY, turn)
    end)
    Log("war_observation_city_conquered attacker=" .. ToText(attackerID)
        .. " target=" .. ToText(targetID)
        .. " city=" .. ToText(cityID)
        .. " turn=" .. ToText(turn)
        .. " accepted=" .. ToText(accepted)
        .. " reason=" .. ToText(reason))
end

local function LogSnapshot(turn, activePlayerID)
    local timingEnabled = DebugTimingEnabled()
    local startedMs = timingEnabled and ReadClockMs() or nil
    local majors, majorsReadable = GetAliveMajors()
    if not majorsReadable then
        State.MetricsDirty = true
        Log("snapshot_majors_unavailable turn=" .. ToText(turn))
        return false
    end
    local startMajors = GetStartMajorCount(majors)
    local metrics, eraReached, metricsReadable = BuildSnapshot(majors)
    if not metricsReadable then
        State.MetricsDirty = true
        Log("snapshot_metrics_unavailable turn=" .. ToText(turn)
            .. " expected=" .. ToText(#majors))
        return false
    end
    local deadPercent = nil
    if startMajors ~= nil and startMajors > 0 then
        deadPercent = math.max(0, (startMajors - #majors) * 100 / startMajors)
    end

    Log("snapshot turn=" .. ToText(turn)
        .. " active_player=" .. ToText(activePlayerID)
        .. " alive_majors=" .. ToText(#majors)
        .. " start_majors=" .. ToText(startMajors)
        .. " dead_percent=" .. ToText(deadPercent)
        .. " era_reached=" .. ToText(eraReached)
        .. " observation_only=" .. ToText(IsTrue(ReadConfig("EC_OBSERVATION_ONLY", 1)))
        .. " awakening_enabled=" .. ToText(IsTrue(ReadConfig("EC_AWAKENING_ENABLED", 0)))
        .. " awakening_dry_run=" .. ToText(IsTrue(ReadConfig("EC_AWAKENING_DRY_RUN", 0)))
        .. " awakening_actions=" .. ToText(AwakeningActionsEnabled())
        .. " metric_bridge=" .. ToText(IsTrue(ReadConfig("EC_METRIC_BRIDGE_TEST", 0)))
        .. " war_observation=" .. ToText(WarObservationEnabled())
        .. " eligibility_observation=" .. ToText(EligibilityObservationEnabled())
        .. " debug_timing=" .. ToText(DebugTimingEnabled()));

    for rank = 1, math.min(3, #metrics) do
        local row = metrics[rank]
        Log("rank=" .. ToText(rank)
            .. " player=" .. ToText(row.PlayerID)
            .. " power=" .. (row.ProjectMetricsComplete and string.format("%.4f", row.Power) or "UNKNOWN")
            .. " military=" .. (row.MilitaryValid and ToText(row.Military) or "UNKNOWN")
            .. " science=" .. ToText(row.Science)
            .. " culture=" .. ToText(row.Culture)
            .. " gold=" .. ToText(row.Gold)
            .. " project_metrics_complete=" .. ToText(row.ProjectMetricsComplete)
            .. " metric_source=" .. ToText(row.MetricSource or "GAMEPLAY_PROBE")
            .. " cities=" .. ToText(row.Cities)
            .. " era=" .. ToText(row.Era));
    end

    State.Metrics = metrics
    State.EraReached = eraReached
    State.DeadPercent = deadPercent
    State.LastSnapshotTurn = turn
    State.MetricsDirty = false
    ObserveWarPairs(majors, turn)
    RunEligibilityObservation(turn)
    if timingEnabled and startedMs ~= nil then
        local finishedMs = ReadClockMs()
        if finishedMs ~= nil then
            Log("snapshot_timing turn=" .. ToText(turn)
                .. " elapsed_ms=" .. TimingResult(startedMs,finishedMs)
                .. " major_count=" .. ToText(#majors)
                .. " metric_count=" .. ToText(#metrics))
        end
    end
    return true
end

local function AdvanceTimedState(turn)
    if turn < 0 then return end
    local metrics = State.Metrics
    AdvanceConsentTests(metrics, turn)
    AdvanceShadowVassals(metrics, turn)
    if AdvanceNativeVassals then AdvanceNativeVassals(turn) end
    local minimumTurn = AwakeningMinimumTurn()
    if DebugTimingEnabled() then Log("timed_state_minimum_ready turn="..ToText(turn)) end
    local targetDeadPercent = tonumber(ReadConfig("EC_AWAKENING_DEAD_PERCENT", 30)) or 30
    local triggerByEra = State.EraReached
    local triggerByCollapse = State.DeadPercent ~= nil and State.DeadPercent >= targetDeadPercent
    local trigger = minimumTurn ~= nil and turn >= minimumTurn and (triggerByEra or triggerByCollapse)
    if IsTrue(ReadConfig("EC_AWAKENING_DRY_RUN", 0)) or AwakeningActionsEnabled() then
        AdvanceAwakening(metrics, turn, State.DeadPercent, triggerByEra, triggerByCollapse)
        RunAwakeningActions(turn)
        RunNativeVictory(turn)
        local stage = State.AwakeningState
        if IsTrue(ReadConfig("EC_API_PROBE", 0)) and not IsTrue(ReadConfig("EC_OBSERVATION_ONLY", 1))
            and (stage == "PREPARATION" or stage == "CONQUEST" or stage == "SHOWDOWN")
            and (State.LastProtectionProbeStage ~= stage or State.LastSnapshotTurn == turn) then
            State.LastProtectionProbeStage = stage
            local humanID = SingleObserverID()
            if humanID ~= nil then
                local protected = ProtectionForObservation(turn, humanID)
                for _, player in ipairs(GetAliveMajors()) do
                    local playerID = ReadPlayerID(player, "protection_probe_player_id")
                    if playerID ~= nil then
                        Log("protection_probe turn=" .. ToText(turn) .. " stage=" .. stage
                            .. " awakened=" .. ToText(State.AwakeningCandidateID)
                            .. " target=" .. ToText(playerID)
                            .. " protected=" .. ToText(protected(State.AwakeningCandidateID, playerID, IsHumanPlayer(player))))
                    end
                end
            end
        end
    elseif trigger and not State.TriggerLogged then
        State.TriggerLogged = true
        local candidate = ChooseAwakeningCandidate(metrics)
        Log("awakening_trigger turn=" .. ToText(turn)
            .. " by_era=" .. ToText(triggerByEra)
            .. " by_collapse=" .. ToText(triggerByCollapse)
            .. " candidate=" .. ToText(candidate and candidate.PlayerID));
    end
    if DebugTimingEnabled() then Log("timed_state_complete turn="..ToText(turn)) end
end

local function CurrentTurn()
    if not HasCallable(Game, "GetCurrentGameTurn") then
        return -1
    end
    return SafeCall("current_turn", function()
        return Game.GetCurrentGameTurn()
    end) or -1
end

local function OnPlayerTurnStarted(playerID)
    State.NativeStarted = true
    local turn = CurrentTurn()
    if turn ~= State.LastTurn then
        State.LastTurn = turn
        EC_AIMilitaryProduction.Update(turn, { Log = Log })
        RunDeferredCityProbe(turn)
        local snapshotOK = true
        if State.MetricsDirty or State.LastSnapshotTurn == nil or turn <= 1 or turn % SAMPLE_INTERVAL == 0 then
            snapshotOK = LogSnapshot(turn, playerID) ~= false
        end
        if not snapshotOK then
            Log("timed_state_skipped_snapshot_unavailable turn=" .. ToText(turn))
            return
        end
        AdvanceTimedState(turn)
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

local function HasMethod(object, methodName)
    if object == nil then return false end
    local ok, method = pcall(function() return object[methodName] end)
    return ok and type(method) == "function"
end

local function ProbeMethod(object, methodName, label)
    if not HasMethod(object, methodName) then return nil end
    return SafeCall(label, function() return object[methodName](object) end)
end

local function ProbeCity(player, playerID)
    local cities = SafeCall("probe_cities_" .. ToText(playerID), function() return player:GetCities() end)
    local capital = ProbeMethod(cities, "GetCapitalCity", "probe_capital_" .. ToText(playerID))
    local cityCount, cityCountValid = CountCities(player)
    Log("api_probe_city_collection player=" .. ToText(playerID)
        .. " count=" .. ToText(cityCount)
        .. " count_valid=" .. ToText(cityCountValid)
        .. " get_capital=" .. ToText(HasMethod(cities, "GetCapitalCity"))
        .. " members=" .. ToText(HasMethod(cities, "Members"))
        .. " find_id=" .. ToText(HasMethod(cities, "FindID"))
        .. " create=" .. ToText(HasMethod(cities, "Create"))
        .. " destroy=" .. ToText(HasMethod(cities, "Destroy")))
    Log("api_probe_city player=" .. ToText(playerID)
        .. " exists=" .. ToText(capital ~= nil)
        .. " get_owner=" .. ToText(HasMethod(capital, "GetOwner"))
        .. " get_original_owner=" .. ToText(HasMethod(capital, "GetOriginalOwner"))
        .. " get_last_transfer=" .. ToText(HasMethod(capital, "GetLastTransferType"))
        .. " get_id=" .. ToText(HasMethod(capital, "GetID"))
        .. " get_x=" .. ToText(HasMethod(capital, "GetX"))
        .. " get_y=" .. ToText(HasMethod(capital, "GetY"))
        .. " get_population=" .. ToText(HasMethod(capital, "GetPopulation"))
        .. " get_buildings=" .. ToText(HasMethod(capital, "GetBuildings"))
        .. " get_build_queue=" .. ToText(HasMethod(capital, "GetBuildQueue"))
        .. " get_properties=" .. ToText(HasMethod(capital, "GetProperties"))
        .. " owner=" .. ToText(ProbeMethod(capital, "GetOwner", "probe_city_owner_" .. ToText(playerID)))
        .. " original_owner=" .. ToText(ProbeMethod(capital, "GetOriginalOwner", "probe_city_original_owner_" .. ToText(playerID)))
        .. " id=" .. ToText(ProbeMethod(capital, "GetID", "probe_city_id_" .. ToText(playerID)))
        .. " x=" .. ToText(ProbeMethod(capital, "GetX", "probe_city_x_" .. ToText(playerID)))
        .. " y=" .. ToText(ProbeMethod(capital, "GetY", "probe_city_y_" .. ToText(playerID)))
        .. " population=" .. ToText(ProbeMethod(capital, "GetPopulation", "probe_city_population_" .. ToText(playerID))))
    local kind = type(capital)
    return (kind == "table" or kind == "userdata") and cityCountValid and cityCount > 0, cityCount
end

RunDeferredCityProbe = function(turn)
    if not State.CityProbePending or not IsTrue(ReadConfig("EC_API_PROBE", 0))
        or State.CityProbeRetries >= MAX_CITY_PROBE_RETRIES or not IsNumber(turn)
        or turn < 0 or turn ~= math.floor(turn) or turn % SAMPLE_INTERVAL ~= 0
        or turn == State.LastCityProbeTurn then return end
    -- One bounded diagnostic attempt per global sampling turn, even if roster reads fail.
    State.LastCityProbeTurn = turn
    State.CityProbeRetries = State.CityProbeRetries + 1
    local majors, readable = GetAliveMajors()
    local pending, attempted = not readable, 0
    if not readable then
        Log("api_probe_city_retry_roster_unavailable turn=" .. ToText(turn))
    else
        for _, player in ipairs(majors) do
            local id = ReadPlayerID(player, "probe_retry_player_id")
            if id == nil then pending = true
            elseif not State.CityProbeCompleted[id] then
                attempted = attempted + 1
                State.CityProbeCompleted[id] = ProbeCity(player, id)
                if not State.CityProbeCompleted[id] then pending = true end
            end
        end
    end
    State.CityProbePending = pending
    Log("api_probe_city_retry turn=" .. ToText(turn) .. " attempted=" .. ToText(attempted)
        .. " pending=" .. ToText(pending) .. " retries=" .. ToText(State.CityProbeRetries))
    if pending and State.CityProbeRetries == MAX_CITY_PROBE_RETRIES then
        Log("api_probe_city_retry_incomplete turn=" .. ToText(turn)
            .. " reason=city_objects_unavailable")
    end
end

local function RunApiProbe()
    if not IsTrue(ReadConfig("EC_API_PROBE", 0)) then
        return
    end

    Log("api_probe_begin");
    Log("api_probe_city_manager"
        .. " transfer_city=" .. ToText(HasMethod(CityManager, "TransferCity"))
        .. " transfer_free=" .. ToText(HasMethod(CityManager, "TransferCityToFreeCities"))
        .. " set_capital=" .. ToText(HasMethod(CityManager, "SetAsCapital"))
        .. " set_original_capital=" .. ToText(HasMethod(CityManager, "SetAsOriginalCapital")));
    Log("api_probe_player_manager"
        .. " was_ever_alive_majors=" .. ToText(HasMethod(PlayerManager, "GetWasEverAliveMajors"))
        .. " was_ever_alive_count=" .. ToText(HasMethod(PlayerManager, "GetWasEverAliveCount")));
    local cycleTurns, speedMultiplier, speedType = ResolveProjectCycleTurns()
    Log("api_probe_speed"
        .. " configuration_get_speed=" .. ToText(HasMethod(GameConfiguration, "GetGameSpeedType"))
        .. " speed_type=" .. ToText(speedType)
        .. " speed_multiplier=" .. ToText(speedMultiplier)
        .. " cycle_turns=" .. ToText(cycleTurns));
    Log("api_probe_victory"
        .. " is_victory_valid=" .. ToText(HasMethod(Game, "IsVictoryValid"))
        .. " set_victory_valid=" .. ToText(HasMethod(Game, "SetVictoryValid"))
        .. " get_victory=" .. ToText(HasMethod(Game, "GetVictory"))
        .. " set_winner=" .. ToText(HasMethod(Game, "SetWinner"))
        .. " get_winning_team=" .. ToText(HasMethod(Game, "GetWinningTeam"))
        .. " set_winning_team=" .. ToText(HasMethod(Game, "SetWinningTeam")));

    local majors, readable = GetAliveMajors()
    State.CityProbePending = not readable
    State.LastCityProbeTurn = CurrentTurn()
    for _, player in ipairs(majors) do
        local playerID = ReadPlayerID(player, "probe_player_id")
        if playerID == nil then
            State.CityProbePending = true
            Log("api_probe_player id=UNKNOWN")
        else
        local stats = SafeCall("probe_stats_" .. ToText(playerID), function() return player:GetStats() end)
        local treasury = SafeCall("probe_treasury_" .. ToText(playerID), function() return player:GetTreasury() end)
        local observed, cityCount = ProbeCity(player, playerID)
        State.CityProbeCompleted[playerID] = observed
        if not observed then State.CityProbePending = true end
        Log("api_probe_metric_context player=" .. ToText(playerID)
            .. " military_no_treasury=" .. ToText(HasMethod(stats, "GetMilitaryStrengthWithoutTreasury"))
            .. " completed_techs=" .. ToText(HasMethod(stats, "GetNumTechsResearched"))
            .. " completed_civics=" .. ToText(HasMethod(stats, "GetNumCivicsCompleted"))
            .. " gold_yield=" .. ToText(HasMethod(treasury, "GetGoldYield"))
            .. " total_maintenance=" .. ToText(HasMethod(treasury, "GetTotalMaintenance"))
            .. " gold_balance=" .. ToText(HasMethod(treasury, "GetGoldBalance")))
        Log("api_probe_player id=" .. ToText(playerID)
            .. " is_alive=" .. ToText(ProbeMethod(player, "IsAlive", "probe_alive_" .. ToText(playerID)))
            .. " is_major=" .. ToText(ProbeMethod(player, "IsMajor", "probe_major_" .. ToText(playerID)))
            .. " cities=" .. ToText(cityCount)
            .. " get_property=" .. ToText(HasMethod(player, "GetProperty"))
            .. " set_property=" .. ToText(HasMethod(player, "SetProperty")));
        end
    end
    if State.CityProbePending then
        Log("api_probe_city_pending turn=" .. ToText(State.LastCityProbeTurn)
            .. " max_retries=" .. ToText(MAX_CITY_PROBE_RETRIES)
            .. " interval=" .. ToText(SAMPLE_INTERVAL))
    end
    Log("api_probe_end");
end

local function NativeEnabled()
    if not State.NativeStarted then return false end
    if not IsFalse(ReadConfig("EC_OBSERVATION_ONLY",1)) or not IsTrue(ReadConfig("EC_NATIVE_VASSAL_TEST",0)) then return false end
    local human=SingleObserverID()
    return MetricBridgeEnabled() and WarObservationEnabled() and EligibilityObservationEnabled() and human~=nil
        and HasCallable(GameConfiguration,"IsAnyMultiplayer") and GameConfiguration.IsAnyMultiplayer()==false
        and GameInfo.Resources~=nil and GameInfo.Resources.RESOURCE_EC_ARCHIVE_STATUS~=nil
end

RefreshNativeMetrics=function(turn)
    if not NativeEnabled() or State.NativeMetricsTurn==turn then return end
    local author=SingleObserverID()
    local _,speed=ResolveProjectCycleTurns()
    local majors,readable=GetAliveMajors()
    if not readable or #majors==0 then return end
    for _,player in ipairs(majors) do
        local id=player:GetID()
        local shadow=IsShadowVassal(id)
        if shadow==nil then return end
        if not shadow then
            local row=EC_DataStore.ReadSnapshot(player,turn,0)
            if not row or row.AuthorID~=author or row.SpeedMultiplier~=speed
                or row.Cities~=player:GetCities():GetCount() or row.Human~=player:IsHuman() then return end
        end
    end
    -- UI operations arrive after PlayerTurnStarted. Publish the complete
    -- current roster once, so qualification and actions can use this turn.
    if LogSnapshot(turn,author) then
        State.NativeMetricsTurn=turn
        AdvanceTimedState(turn)
    end
end

local function NativeCandidate(id,lord)
    local turn=CurrentTurn()
    local author=SingleObserverID()
    local _,speed=ResolveProjectCycleTurns()
    if not PlayerSlot(id) or not PlayerSlot(lord) or author==nil or speed==nil then return nil end
    local observation=EC_DataStore.ReadObservation(Players[id])
    local target=EC_DataStore.ReadSnapshot(Players[id],turn,5)
    local overlord=EC_DataStore.ReadSnapshot(Players[lord],turn,5)
    if not observation or not observation.Active or observation.Ledger.OverlordID~=lord
        or observation.Ledger.TargetID~=id or observation.Ledger.SpeedMultiplier~=speed
        or not target or not overlord or target.AuthorID~=author or overlord.AuthorID~=author
        or target.Turn~=overlord.Turn or target.SpeedMultiplier~=speed or overlord.SpeedMultiplier~=speed
        or IsShadowVassal(id)~=false or IsShadowVassal(lord)~=false then return nil end
    for _,row in ipairs({target,overlord}) do
        local p=Players[row.PlayerID]
        if not p:IsAlive() or not p:IsMajor() or p:IsHuman()~=row.Human
            or p:GetCities():GetCount()~=row.Cities then return nil end
    end
    local war=Players[id]:GetDiplomacy():IsAtWarWith(lord)
    if war~=Players[lord]:GetDiplomacy():IsAtWarWith(id) then return nil end
    local context=EC_WarContext.Context(Players[id],lord,turn,war,function(x,y)
        local city=CityManager.GetCityAt(x,y)
        return city and {Exists=true,Owner=city:GetOwner()} or {Exists=false}
    end) or {}
    context.Turn=turn; context.SnapshotTurn=target.Turn; context.SpeedMultiplier=speed
    context.Protected=ProtectionForObservation(turn,author)(lord,id,target.Human)
    context.AtWar=war
    local ledger=observation.Ledger
    context.AdvantageSinceTurn=ledger.SinceTurn; context.AdvantageTier=ledger.Tier
    context.AdvantageOverlordID=lord; context.AdvantageTargetID=id
    return EC_Eligibility.Evaluate(overlord,target,context),context
end

local function NativeAutonomy(id,row,token,confirmed)
    local p=Players[id]
    local prefix="EC_VASSAL_"..id.."_"
    local pending=p:GetProperty(prefix.."PROJECT_PENDING_TOKEN")
    local applied=p:GetProperty(prefix.."PROJECT_APPLIED_TOKEN")
    local lifecycle=EC_NativeLifecycle.Create({Players=Players,GameInfo=GameInfo,Game=Game,GameEffects=GameEffects,
        GameConfiguration=GameConfiguration,CityManager=CityManager})
    local party=lifecycle.GetParty(id)
    local lord=lifecycle.GetParty(row.OverlordID)
    local projectPending
    if IsNumber(pending) and IsNumber(applied) then projectPending=pending>applied end
    local effect=p:GetProperty(prefix..PROJECT_EFFECT_STATE)
    if effect=="PENDING" or effect=="UNKNOWN" then projectPending=true end
    return EC_AutonomyPolicy.Evaluate({Turn=CurrentTurn(),TransactionToken=token,
        OverlordID=row.OverlordID,VassalID=id,VassalAlive=party.Alive,VassalMajor=party.Major,
        VassalArchived=party.Archived,OverlordAlive=lord.Alive,OverlordMajor=lord.Major,
        Autonomy=p:GetProperty(prefix.."AUTONOMY"),AutonomyTarget=p:GetProperty(prefix.."AUTONOMY_TARGET"),
        ArchiveState=row.State,ArchiveComplete=row.State=="VASSALIZED",UnitsRemoved=true,
        ArchiveCityCount=#row.OriginalCities,Human=party.Human,Confirmed=confirmed,
        ProjectPending=projectPending})
end

local function NativePublished(id,row)
    local prefix="EC_VASSAL_"..id.."_"
    if row.State=="VASSALIZED" then
        local seed=assert(row.InitialProject,"Native project initialization unavailable")
        local project,focus,cycle,disposition=seed.Project,seed.Focus,seed.Cycle,seed.Disposition
        for _,property in ipairs({{"SCHEMA_VERSION",1},{"OVERLORD",row.OverlordID},
            {"CAPTURE_TURN",row.CreatedTurn},{"AUTONOMY",0},{"AUTONOMY_TARGET",100},
            {"PROJECT_POLICY_VERSION",PROJECT_POLICY_VERSION},{"PROJECT_DISPOSITION",disposition},
            {"PROJECT",project},{"PROJECT_FOCUS",focus},{"PROJECT_START_TURN",row.CreatedTurn},
            {"PROJECT_END_TURN",row.CreatedTurn+cycle},{"PROJECT_PENDING_TOKEN",-1},{"PROJECT_APPLIED_TOKEN",-1},
            {PROJECT_EFFECT_TOKEN,-1},{PROJECT_EFFECT_STATE,"NONE"}}) do
            assert(SetPropertySafe(id,prefix..property[1],property[2]))
        end
    end
    assert(SetPropertySafe(id,prefix.."STATE",row.State))
    State.MetricsDirty=true
    Log("native_vassal_committed player="..id.." state="..row.State)
end

local function GetNativeController()
    if not NativeEnabled() then return nil end
    if NativeController then return NativeController end
    NativeController=EC_NativeVassals.Create({Players=Players,GameInfo=GameInfo,Game=Game,AIProductionCredit=true,HumanProductionRefund=true,
        GameConfiguration=GameConfiguration,GameEffects=GameEffects,CityManager=CityManager,UnitManager=UnitManager,Map=Map,RouteBuilder=RouteBuilder,
        CaptureProduction=function(...) return assert(ExposedMembers.EC_CaptureProductionArchive,"Production bridge unavailable")(... ) end,
        CaptureConstructionQueue=function(...) return assert(ExposedMembers.EC_CaptureConstructionQueue,"Construction queue bridge unavailable")(... ) end,
        RequestProduction=function(...) return assert(ExposedMembers.EC_RequestProductionArchive,"Production bridge unavailable")(... ) end,
        CanRestoreProduction=function(...) return assert(ExposedMembers.EC_CanRestoreProductionArchive,"Production bridge unavailable")(... ) end},
        {Enabled=NativeEnabled,HumanID=SingleObserverID,Candidate=NativeCandidate,Autonomy=NativeAutonomy,
            ConsentTurns=function() local _,speed=ResolveProjectCycleTurns(); return math.max(1,math.ceil(3*speed/100)) end,
            Metrics=function(id) for _,row in ipairs(State.Metrics) do if row.PlayerID==id then return EC_CityPayload.Copy(row) end end end,
            Project=function(id,lord,targetMetric,lordMetric)
                local disposition=ShadowDisposition(lord,id)
                local project,focus=ChooseShadowProject(lordMetric,targetMetric,0,disposition)
                local cycle=ResolveProjectCycleTurns()
                if project and cycle then return {Project=project,Focus=focus,Cycle=cycle,Disposition=disposition} end
            end,
            Published=NativePublished,Log=Log})
    return NativeController
end

AdvanceNativeVassals=function(turn)
    if IsTrue(ReadConfig("EC_DEBUG_TIMING",0)) then Log("native_update_enter turn="..tostring(turn)) end
    if not NativeEnabled() then return end
    if IsTrue(ReadConfig("EC_DEBUG_TIMING",0)) then Log("native_update_enabled turn="..tostring(turn)) end
    local ok,reason=pcall(function()
        local controller=GetNativeController()
        if IsTrue(ReadConfig("EC_DEBUG_TIMING",0)) then Log("native_update_controller_ready turn="..tostring(turn)) end
        local metrics={}
        for _,row in ipairs(State.Metrics) do metrics[row.PlayerID]=row end
        local cycle=ResolveProjectCycleTurns()
        for id=0,63 do
            local row=EC_NativeVassals.ReadArchive(Game,id)
            if row and row.Schema==1 and row.VassalID==id and row.State=="VASSALIZED" then
                AdvanceShadowVassalProject(id,turn,cycle,metrics)
            end
        end
        controller.Tick()
        for id=0,63 do
            local row=EC_NativeVassals.ReadArchive(Game,id)
            if row and row.Schema==1 and row.VassalID==id and row.State=="INDEPENDENT"
                and row.Plan.Action=="RESTORE" then
                local phases,pending,unknown={},false,false
                local human=Players[id]:IsHuman()==true
                local creditModule=human and EC_HumanProductionRefund or EC_AIProductionCredit
                local prefix=human and "EC_HUMAN_PRODUCTION_CREDIT_" or "EC_AI_PRODUCTION_CREDIT_"
                local creditAPI={Game=Game,GameInfo=GameInfo,Players=Players,
                    GameEffects=GameEffects,CityManager=CityManager,
                    PublishedProduction=function(...) return assert(ExposedMembers.EC_GetPublishedProduction)(...) end}
                for _,record in ipairs(row.Plan.Cities) do
                    local key="EC_NATIVE_PRODUCTION_"..row.Plan.TransactionToken.."_"..record.CityID
                    local receipt=creditModule.Read(Game,key)
                    if receipt then
                        local city=assert(CityManager.GetCityAt(record.X,record.Y),"AI credited city missing")
                        local phase=creditModule.Step(city,creditAPI,key)
                        phases[#phases+1]=phase
                        unknown=unknown or phase=="UNKNOWN"
                        pending=pending or (phase~="COMPLETE" and phase~="UNKNOWN")
                    end
                end
                if #phases>0 then
                    SetPropertySafe(id,prefix.."PHASE",table.concat(phases,"|"))
                    SetPropertySafe(id,prefix.."STATUS",pending and "PENDING" or unknown and "UNKNOWN" or "COMPLETE")
                end
            end
        end
        if IsTrue(ReadConfig("EC_DEBUG_TIMING",0)) then Log("native_update_complete turn="..tostring(turn)) end
    end)
    if not ok then Log("native_vassal_update_failed reason="..tostring(reason)) end
end

local function OnNativeConsent(actor,parameters)
    if not NativeDispatchReady or actor~=SingleObserverID() or type(parameters)~="table"
        or parameters.ForPlayer~=actor then return end
    State.NativeStarted=true
    if IsTrue(ReadConfig("EC_DEBUG_TIMING",0)) then
        local request=parameters and PlayerSlot(actor) and Players[actor]:GetProperty("EC_NATIVE_REQUEST")
        Log("native_consent_enter actor="..ToText(actor).." for_player="..ToText(parameters and parameters.ForPlayer)
            .." target="..ToText(parameters and parameters.TargetID).." action="..ToText(parameters and parameters.Action)
            .." decision="..ToText(parameters and parameters.Decision).." token="..ToText(parameters and parameters.Token)
            .." over="..ToText(parameters and parameters.Overlord).." req_state="..ToText(request and request.State)
            .." req_action="..ToText(request and request.Action).." req_token="..ToText(request and request.Token)
            .." req_over="..ToText(request and request.OverlordID))
    end
    local ok,reason=pcall(function() local controller=GetNativeController(); if controller then controller.Respond(actor,parameters) end end)
    if not ok then
        if PlayerSlot(actor) then SetPropertySafe(actor,"EC_NATIVE_OPERATION_STATUS",tostring(reason)) end
        Log("native_consent_blocked reason="..tostring(reason))
    end
end
local function OnNativeAdvance(actor,parameters)
    if not NativeDispatchReady or actor~=SingleObserverID() or type(parameters)~="table"
        or parameters.ForPlayer~=actor then return end
    -- Valid UI recovery requests can resume a loaded transaction before a new
    -- PlayerTurnStarted or a changed metric snapshot. SAME snapshots do not
    -- set NativeStarted, although the archive and turn are already loaded.
    State.NativeStarted=true
    if not NativeEnabled() then return end
    AdvanceNativeVassals(CurrentTurn())
end
local function OnNativeOperate(actor,parameters)
    if not NativeDispatchReady or actor~=SingleObserverID() or type(parameters)~="table"
        or parameters.ForPlayer~=actor then return end
    State.NativeStarted=true
    local ok,reason=pcall(function() local controller=GetNativeController(); if controller then controller.Operate(actor,parameters) end end)
    if not ok then
        if parameters and PlayerSlot(parameters.TargetID) then SetPropertySafe(parameters.TargetID,"EC_NATIVE_OPERATION_STATUS",tostring(reason)) end
        Log("native_operation_blocked reason="..tostring(reason))
    end
end
local function OnNativeProject(actor,parameters)
    if not NativeDispatchReady or actor~=SingleObserverID() or type(parameters)~="table"
        or parameters.ForPlayer~=actor then return end
    State.NativeStarted=true
    local ok,reason=pcall(function() local controller=GetNativeController(); if controller then controller.ChooseProject(actor,parameters) end end)
    if not ok then Log("native_project_blocked reason="..tostring(reason)) end
end

local function Initialize()
    if State.Initialized then
        return
    end
    State.Initialized = true
    Log("init version=endgame-transactional-dry-run")
    RegisterEvent(GameEvents, "PlayerTurnStarted", OnPlayerTurnStarted)
    RegisterEvent(GameEvents, "EC_ConsentResponse", OnConsentResponse)
    RegisterEvent(GameEvents, "EC_MetricSnapshot", OnMetricSnapshot)
    RegisterEvent(GameEvents,"EC_NativeConsentResponse",OnNativeConsent)
    RegisterEvent(GameEvents,"EC_NativeAdvance",OnNativeAdvance)
    RegisterEvent(GameEvents,"EC_NativeOperate",OnNativeOperate)
    RegisterEvent(GameEvents,"EC_NativeProject",OnNativeProject)
    RegisterEvent(Events,"TeamVictory",OnNativeTeamVictory)
    if WarObservationEnabled() then
        RegisterEvent(GameEvents, "CityConquered", OnCityConqueredObserved)
    else
        Log("war_observation_disabled")
    end
    local loadScreenClose, loadScreenReadable = ReadMember(Events, "LoadScreenClose")
    if loadScreenReadable and HasCallable(loadScreenClose, "Add") then
        -- This handler is intentionally not used for gameplay state; it only
        -- makes early setup failures visible in the log.
        Log("event_available name=LoadScreenClose")
    end
    if IsTrue(ReadConfig("EC_AWAKENING_ENABLED", 0))
        or IsTrue(ReadConfig("EC_AWAKENING_DRY_RUN", 0)) then
        RestoreAwakeningState()
    end
    RunApiProbe();
    local turn = CurrentTurn()
    State.LastTurn = turn
    if LogSnapshot(turn, -1) then
        AdvanceTimedState(turn)
    else
        Log("timed_state_skipped_snapshot_unavailable turn=" .. ToText(turn))
    end
    NativeDispatchReady=true
    if DebugTimingEnabled() then Log("initialization_complete turn="..ToText(turn)) end
end

if not RegisterEvent(Events, "LoadScreenClose", Initialize) then
    Initialize()
end

