-- Optional, bounded AI military production. It never creates units directly:
-- native city production and the native at-war-and-known-opponent requirement
-- do the work.
EC_AIMilitaryProduction = {}

local PREFIX = "EC_AI_MILITARY_PRODUCTION_"
local SCHEMA_VERSION = 1
local MAX_PLAYER_ID = 63
local MAX_ATTACH_ATTEMPTS = 3
local COMPLETION_KEY = "COMPLETE"
local MODIFIERS = {
    { id = "EC_AI_MILITARY_PREWAR", key = "PREWAR" },
    { id = "EC_AI_MILITARY_WARTIME", key = "WARTIME" },
    { id = "EC_AI_MILITARY_PREWAR_PURCHASE", key = "PREWAR_PURCHASE" },
    { id = "EC_AI_MILITARY_WARTIME_PURCHASE", key = "WARTIME_PURCHASE" },
    { id = "EC_AI_MILITARY_CITY2", key = "CITY2" },
    { id = "EC_AI_MILITARY_CITY5", key = "CITY5" },
    { id = "EC_AI_MILITARY_MIDGAME_SURGE", key = "MIDGAME_SURGE" },
    { id = "EC_AI_MILITARY_LATE_SURGE", key = "LATE_SURGE" },
    { id = "EC_AI_MILITARY_HIGH_DIFFICULTY", key = "HIGH_DIFFICULTY" },
    { id = "EC_AI_MILITARY_TECH_PRODUCTION", key = "TECH_PRODUCTION" },
    { id = "EC_AI_MILITARY_WARTIME_TECH_SURGE", key = "WARTIME_TECH_SURGE" },
    { id = "EC_AI_MILITARY_WARTIME_COMBINED_ARMS_SURGE", key = "WARTIME_COMBINED_ARMS_SURGE" },
    { id = "EC_AI_MILITARY_MILITARY_TRADITION_CIVIC", key = "MILITARY_TRADITION_CIVIC" },
    { id = "EC_AI_MILITARY_MILITARY_TRAINING_CIVIC", key = "MILITARY_TRAINING_CIVIC" },
    { id = "EC_AI_MILITARY_DEFENSIVE_TACTICS_CIVIC", key = "DEFENSIVE_TACTICS_CIVIC" },
    { id = "EC_AI_MILITARY_MERCENARIES_CIVIC", key = "MERCENARIES_CIVIC" },
    { id = "EC_AI_MILITARY_NATIONALISM_CIVIC", key = "NATIONALISM_CIVIC" },
    { id = "EC_AI_MILITARY_SCORCHED_EARTH_CIVIC", key = "SCORCHED_EARTH_CIVIC" },
    { id = "EC_AI_MILITARY_MOBILIZATION_CIVIC", key = "MOBILIZATION_CIVIC" },
    { id = "EC_AI_MILITARY_RAPID_DEPLOYMENT_CIVIC", key = "RAPID_DEPLOYMENT_CIVIC" },
}

local State = {
    LastTurn = nil,
    DisabledLogged = false,
    CompletedPlayers = {},
    BlockedPlayers = {},
}

local function ToText(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function Log(options, message)
    if type(options) == "table" and type(options.Log) == "function" then
        pcall(options.Log, message)
    else
        print("[EC] " .. message)
    end
end

local function IsInteger(value)
    return type(value) == "number" and value >= 0 and value < math.huge
        and value == math.floor(value)
end

local function IsPlayerID(value)
    return IsInteger(value) and value <= MAX_PLAYER_ID
end

local function HasCallable(object, methodName)
    if object == nil then return false end
    local ok, method = pcall(function() return object[methodName] end)
    return ok and type(method) == "function"
end

local function ReadConfig(key, defaultValue)
    if not HasCallable(GameConfiguration, "GetValue") then return defaultValue end
    local ok, value = pcall(function() return GameConfiguration.GetValue(key) end)
    if not ok or value == nil then return defaultValue end
    return value
end

local function IsTrue(value)
    return value == true or value == 1 or value == "1" or value == "true"
end

local function IsFalse(value)
    return value == false or value == 0 or value == "0" or value == "false"
end

local function Enabled(options)
    local enabled = IsTrue(ReadConfig("EC_AI_MILITARY_PRODUCTION_TEST", 0))
    local observationOnly = ReadConfig("EC_OBSERVATION_ONLY", 1)
    return enabled and IsFalse(observationOnly)
end

local function ReadProperty(player, key)
    if not HasCallable(player, "GetProperty") then return nil, false end
    local ok, value = pcall(function() return player:GetProperty(PREFIX .. key) end)
    return value, ok
end

local function WriteProperty(player, key, value)
    if not HasCallable(player, "SetProperty") then return false end
    local ok, result = pcall(function() return player:SetProperty(PREFIX .. key, value) end)
    return ok and result ~= false
end

local function MarkUnknown(player, key)
    WriteProperty(player, key, "UNKNOWN")
end

local function ApplyModifier(player, playerID, modifier, options, attachmentContext)
    local schema = attachmentContext.Schema
    if not HasCallable(player, "AttachModifierByID") then
        return false, "MODIFIER_API_UNAVAILABLE"
    end

    local status, statusReadable = ReadProperty(player, modifier.key)
    if not statusReadable then return false, modifier.key .. "_READ_FAILED" end
    if status == "APPLIED" then return true, "ALREADY_APPLIED" end
    if status == "UNKNOWN" then return false, modifier.key .. "_OUTCOME_UNKNOWN" end
    if status ~= nil and status ~= "RETRY" and status ~= "ATTACHING" then
        MarkUnknown(player, modifier.key)
        return false, modifier.key .. "_STATE_INVALID"
    end
    if status == "ATTACHING" then
        -- A previous process may have committed the native effect before a
        -- crash. Retrying could double-apply it, so fail closed.
        MarkUnknown(player, modifier.key)
        return false, modifier.key .. "_OUTCOME_UNKNOWN"
    end

    local attemptsKey = modifier.key .. "_ATTEMPTS"
    local attempts, attemptsReadable = ReadProperty(player, attemptsKey)
    if not attemptsReadable then return false, modifier.key .. "_ATTEMPTS_READ_FAILED" end
    if attempts == nil then attempts = 0 end
    if not IsInteger(attempts) or attempts > MAX_ATTACH_ATTEMPTS then
        MarkUnknown(player, modifier.key)
        return false, modifier.key .. "_ATTEMPTS_INVALID"
    end
    if attempts >= MAX_ATTACH_ATTEMPTS then
        MarkUnknown(player, modifier.key)
        return false, modifier.key .. "_ATTEMPTS_EXHAUSTED"
    end

    if schema == nil then
        if not WriteProperty(player, "SCHEMA", SCHEMA_VERSION) then
            return false, "SCHEMA_WRITE_FAILED"
        end
        attachmentContext.Schema = SCHEMA_VERSION
    end
    if not WriteProperty(player, attemptsKey, attempts + 1)
        or not WriteProperty(player, modifier.key, "ATTACHING") then
        return false, modifier.key .. "_STATE_WRITE_FAILED"
    end

    local result, callOK = nil, false
    callOK, result = pcall(function() return player:AttachModifierByID(modifier.id) end)
    if not callOK then
        MarkUnknown(player, modifier.key)
        Log(options, "ai_military_production_attach_error player=" .. ToText(playerID)
            .. " modifier=" .. modifier.id)
        return false, modifier.key .. "_OUTCOME_UNKNOWN"
    end
    if result == false then
        if attempts + 1 >= MAX_ATTACH_ATTEMPTS then
            MarkUnknown(player, modifier.key)
        else
            WriteProperty(player, modifier.key, "RETRY")
        end
        return false, modifier.key .. "_RETRY"
    end
    if not WriteProperty(player, modifier.key, "APPLIED") then
        MarkUnknown(player, modifier.key)
        return false, modifier.key .. "_OUTCOME_UNKNOWN"
    end
    Log(options, "ai_military_production_applied player=" .. ToText(playerID)
        .. " modifier=" .. modifier.id)
    return true, "APPLIED"
end

local function ReadRoster(options)
    if not HasCallable(PlayerManager, "GetAliveMajors") then
        Log(options, "ai_military_production_roster_unavailable")
        return nil
    end
    local ok, roster = pcall(function() return PlayerManager.GetAliveMajors() end)
    if not ok or type(roster) ~= "table" or #roster > 64 then
        Log(options, "ai_military_production_roster_invalid")
        return nil
    end
    local count = 0
    for key in pairs(roster) do
        if not IsInteger(key) or key < 1 or key > #roster then
            Log(options, "ai_military_production_roster_invalid")
            return nil
        end
        count = count + 1
    end
    if count ~= #roster then
        Log(options, "ai_military_production_roster_invalid")
        return nil
    end
    return roster
end

local function ApplyToPlayer(player, options)
    if player == nil or not HasCallable(player, "GetID")
        or not HasCallable(player, "IsAlive") or not HasCallable(player, "IsMajor")
        or not HasCallable(player, "IsHuman") then
        return false, "PLAYER_IDENTITY_UNAVAILABLE"
    end
    local ok, playerID, alive, major, human = pcall(function()
        return player:GetID(), player:IsAlive(), player:IsMajor(), player:IsHuman()
    end)
    if not ok or not IsPlayerID(playerID) or alive ~= true or major ~= true
        or type(human) ~= "boolean" then
        return false, "PLAYER_IDENTITY_UNKNOWN"
    end
    if human then return false, "HUMAN_SKIPPED" end

    -- Modifier attachment is a one-time setup. Once every native modifier has
    -- been applied, avoid rereading all modifier states on every player turn.
    -- A session-local block also prevents a persistent property failure from
    -- becoming an unbounded retry loop until the next reload.
    if State.BlockedPlayers[playerID] then
        return false, "PLAYER_STATE_BLOCKED"
    end
    if State.CompletedPlayers[playerID] then
        return true, 0
    end
    local complete, completeReadable = ReadProperty(player, COMPLETION_KEY)
    if not completeReadable then
        State.BlockedPlayers[playerID] = true
        return false, "COMPLETION_READ_FAILED"
    end
    if complete == "APPLIED" then
        State.CompletedPlayers[playerID] = true
        return true, 0
    end
    if complete ~= nil then
        MarkUnknown(player, COMPLETION_KEY)
        State.BlockedPlayers[playerID] = true
        return false, "COMPLETION_STATE_INVALID"
    end

    -- Read the schema once per incomplete player. Re-reading it for every
    -- modifier made the one-time attachment pass needlessly expensive and
    -- allowed an invalid schema to repeat the same failure every turn.
    local schema, schemaReadable = ReadProperty(player, "SCHEMA")
    if not schemaReadable then
        State.BlockedPlayers[playerID] = true
        return false, "SCHEMA_READ_FAILED"
    end
    if schema ~= nil and schema ~= SCHEMA_VERSION then
        MarkUnknown(player, "SCHEMA")
        State.BlockedPlayers[playerID] = true
        return false, "SCHEMA_UNSUPPORTED"
    end
    local attachmentContext = { Schema = schema }

    local applied = 0
    local allApplied = true
    for _, modifier in ipairs(MODIFIERS) do
        local changed, reason = ApplyModifier(
            player, playerID, modifier, options, attachmentContext)
        if changed then applied = applied + 1 end
        if reason ~= "APPLIED" and reason ~= "ALREADY_APPLIED" then
            allApplied = false
            Log(options, "ai_military_production_modifier_skipped player=" .. ToText(playerID)
                .. " modifier=" .. modifier.id .. " reason=" .. ToText(reason))
            if reason == "SCHEMA_WRITE_FAILED"
                or string.find(reason, "_STATE_WRITE_FAILED", 1, true) ~= nil then
                State.BlockedPlayers[playerID] = true
                break
            end
        end
    end
    if allApplied then
        if not WriteProperty(player, COMPLETION_KEY, "APPLIED") then
            State.BlockedPlayers[playerID] = true
            Log(options, "ai_military_production_completion_write_failed player="
                .. ToText(playerID))
            return false, "COMPLETION_WRITE_FAILED"
        end
        State.CompletedPlayers[playerID] = true
    end
    return true, applied
end

function EC_AIMilitaryProduction.Update(turn, options)
    options = type(options) == "table" and options or {}
    if not IsInteger(turn) then return false, "TURN_INVALID" end
    if State.LastTurn == turn then return true, "ALREADY_UPDATED" end
    State.LastTurn = turn
    if not Enabled(options) then
        if not State.DisabledLogged then
            State.DisabledLogged = true
            Log(options, "ai_military_production_disabled")
        end
        return false, "DISABLED"
    end
    local roster = ReadRoster(options)
    if roster == nil then return false, "ROSTER_UNAVAILABLE" end
    local aiCount, appliedCount = 0, 0
    for _, player in ipairs(roster) do
        local valid, result = ApplyToPlayer(player, options)
        if valid then
            aiCount = aiCount + 1
            appliedCount = appliedCount + result
        end
    end
    Log(options, "ai_military_production_update turn=" .. ToText(turn)
        .. " ai_players=" .. ToText(aiCount) .. " modifiers_applied=" .. ToText(appliedCount))
    return true, "UPDATED"
end

function EC_AIMilitaryProduction.ResetForTests()
    State.LastTurn = nil
    State.DisabledLogged = false
    State.CompletedPlayers = {}
    State.BlockedPlayers = {}
end
