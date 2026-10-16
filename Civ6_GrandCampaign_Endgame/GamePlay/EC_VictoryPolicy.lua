-- Deterministic victory protection contract.
-- This module plans and verifies a caller-supplied adapter; it does not call
-- Civ VI globals or change victory state by itself.
EC_VictoryPolicy = {}

local MAX_PLAYERS = 64
local STAGES = { PREPARATION = true, CONQUEST = true, SHOWDOWN = true }

local function PlayerID(value)
    return type(value) == "number" and value >= 0 and value < MAX_PLAYERS
        and value == math.floor(value)
end

local function Safe(callback)
    local ok, first = pcall(callback)
    if not ok then return nil, false end
    return first, true
end

local function ValidateContext(context)
    if type(context) ~= "table" then return false, "CONTEXT_UNKNOWN" end
    if not PlayerID(context.AwakenedPlayerID) or not PlayerID(context.WinnerID)
        or type(context.Turn) ~= "number" or context.Turn < 0
        or context.Turn == math.huge
        or context.Turn ~= math.floor(context.Turn) then
        return false, "IDENTITY_OR_TURN_UNKNOWN"
    end
    if not STAGES[context.Stage] then return false, "STAGE_UNKNOWN" end
    if context.AwakenedAlive ~= true or context.AwakenedMajor ~= true
        or context.WinnerMajor ~= true then
        return false, "PARTY_IDENTITY_UNKNOWN"
    end
    return true
end

function EC_VictoryPolicy.Plan(context)
    local valid, reason = ValidateContext(context)
    if not valid then return { Decision = "UNKNOWN", Reason = reason } end

    if context.Stage == "SHOWDOWN" then
        return { Decision = "ALLOW", DesiredValid = true, Reason = "SHOWDOWN" }
    end
    if context.WinnerID == context.AwakenedPlayerID then
        return { Decision = "BLOCK", DesiredValid = false, Reason = "AWAKENED_PRE_SHOWDOWN" }
    end
    return { Decision = "ALLOW", DesiredValid = true, Reason = "OTHER_WINNER" }
end

function EC_VictoryPolicy.Apply(adapter, context)
    local plan = EC_VictoryPolicy.Plan(context)
    if plan.Decision == "UNKNOWN" then return false, plan.Reason end
    if type(adapter) ~= "table" or type(adapter.GetVictoryValid) ~= "function"
        or type(adapter.SetVictoryValid) ~= "function" then
        return false, "VICTORY_API_UNKNOWN"
    end

    local current, readable = Safe(function() return adapter:GetVictoryValid() end)
    if not readable or type(current) ~= "boolean" then
        return false, "VICTORY_STATE_UNKNOWN"
    end
    local changed = current ~= plan.DesiredValid
    if changed then
        local result, written = Safe(function()
            return adapter:SetVictoryValid(plan.DesiredValid)
        end)
        if not written or result ~= true then return false, "VICTORY_WRITE_UNKNOWN" end
    end

    local verified, verifiedReadable = Safe(function() return adapter:GetVictoryValid() end)
    if not verifiedReadable or verified ~= plan.DesiredValid then
        return false, "VICTORY_VERIFY_UNKNOWN"
    end
    return true, changed and plan.Reason or "ALREADY_APPLIED"
end
