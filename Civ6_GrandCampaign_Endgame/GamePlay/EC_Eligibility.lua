-- Pure candidate evaluation. No engine calls, persistence or annexation authority.
EC_Eligibility = {}

local DOMAINS = { "Military", "Economy", "Science", "Culture" }
local DEFAULTS = {
    Regular = { Military = 2, Economy = 1.5, Science = 1.5, Culture = 1.5 },
    Extreme = { Military = 4, Economy = 3, Science = 3, Culture = 3 },
    Floors = { Military = 100, Economy = 10, Science = 10, Culture = 10 },
    HoldTurnsStandard = 10, VictoryWindowStandard = 20, SnapshotMaxAge = 5,
}

local function Number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function Integer(value)
    return Number(value) and value >= 0 and value == math.floor(value)
end

local function PolicyValid(policy)
    if type(policy) ~= "table" then return false end
    for _, group in ipairs({ "Regular", "Extreme", "Floors" }) do
        if type(policy[group]) ~= "table" then return false end
        for _, domain in ipairs(DOMAINS) do
            if not Number(policy[group][domain]) or policy[group][domain] <= 0 then return false end
        end
    end
    for _, domain in ipairs(DOMAINS) do
        if policy.Regular[domain] <= 1 or policy.Extreme[domain] < policy.Regular[domain] then return false end
    end
    return Integer(policy.HoldTurnsStandard) and policy.HoldTurnsStandard > 0
        and Integer(policy.VictoryWindowStandard) and policy.VictoryWindowStandard > 0
        and Integer(policy.SnapshotMaxAge)
end

function EC_Eligibility.DefaultPolicy()
    local copy = {}
    for key, value in pairs(DEFAULTS) do
        if type(value) == "table" then
            copy[key] = {}
            for domain, threshold in pairs(value) do copy[key][domain] = threshold end
        else copy[key] = value end
    end
    return copy
end

local function CopyPolicy(policy)
    local copy = {}
    for _, group in ipairs({ "Regular", "Extreme", "Floors" }) do
        copy[group] = {}
        for _, domain in ipairs(DOMAINS) do copy[group][domain] = policy[group][domain] end
    end
    for _, key in ipairs({ "HoldTurnsStandard", "VictoryWindowStandard", "SnapshotMaxAge" }) do
        copy[key] = policy[key]
    end
    return copy
end

local function SamePolicy(first, second)
    for _, group in ipairs({ "Regular", "Extreme", "Floors" }) do
        for _, domain in ipairs(DOMAINS) do
            if first[group][domain] ~= second[group][domain] then return false end
        end
    end
    return first.HoldTurnsStandard == second.HoldTurnsStandard
        and first.VictoryWindowStandard == second.VictoryWindowStandard
        and first.SnapshotMaxAge == second.SnapshotMaxAge
end

function EC_Eligibility.Economy(netGold, goldBalance, speedMultiplier)
    if not Number(netGold) or not Number(goldBalance) or goldBalance < 0
        or not Number(speedMultiplier) or speedMultiplier <= 0 then return nil end
    local result = math.max(0, netGold) + goldBalance / (20 * speedMultiplier / 100)
    if not Number(result) then return nil end
    return result
end

local function PlayerValid(player)
    if type(player) ~= "table" or not Integer(player.PlayerID)
        or player.PlayerID >= 64
        or type(player.Human) ~= "boolean" or type(player.Alive) ~= "boolean"
        or type(player.Major) ~= "boolean" or type(player.Independent) ~= "boolean"
        or not Integer(player.Cities) or not Integer(player.TechsCompleted)
        or not Integer(player.CivicsCompleted) then return false end
    for _, domain in ipairs(DOMAINS) do
        if not Number(player[domain]) or player[domain] < 0 then return false end
    end
    return true
end

function EC_Eligibility.Evaluate(overlord, target, context, policy)
    if policy == nil then policy = DEFAULTS end
    local result = { Eligible = false, Reason = "DATA_UNKNOWN", Tier = "NONE", Ratios = {},
        NeedsPlayerConfirmation = false, NextAction = "NONE" }
    local function Block(reason) result.Reason = reason; return result end
    if not PolicyValid(policy) then return Block("POLICY_INVALID") end
    if not PlayerValid(overlord) or not PlayerValid(target) then return result end
    if overlord.PlayerID == target.PlayerID then return Block("SAME_PLAYER") end
    if not overlord.Alive or not target.Alive or not overlord.Major or not target.Major
        or not overlord.Independent or not target.Independent
        or overlord.Cities == 0 or target.Cities == 0 then return Block("PARTY_INELIGIBLE") end
    if type(context) ~= "table" or not Integer(context.Turn) or not Integer(context.SnapshotTurn)
        or context.SnapshotTurn > context.Turn or not Number(context.SpeedMultiplier)
        or context.SpeedMultiplier <= 0 then return Block("CONTEXT_INVALID") end
    local holdTurns = math.ceil(policy.HoldTurnsStandard * context.SpeedMultiplier / 100)
    local victoryWindow = math.ceil(policy.VictoryWindowStandard * context.SpeedMultiplier / 100)
    if not Integer(holdTurns) or holdTurns <= 0 or not Integer(victoryWindow) or victoryWindow <= 0 then
        return Block("CONTEXT_INVALID")
    end
    if context.Turn - context.SnapshotTurn > policy.SnapshotMaxAge then return Block("SNAPSHOT_STALE") end
    local regular, extreme = true, true
    for _, domain in ipairs(DOMAINS) do
        local ratio = overlord[domain] / math.max(target[domain], policy.Floors[domain])
        result.Ratios[domain] = ratio
        regular = regular and ratio >= policy.Regular[domain]
        extreme = extreme and ratio >= policy.Extreme[domain]
    end
    result.Tier = extreme and "EXTREME" or (regular and "REGULAR" or "NONE")
    if type(context.Protected) ~= "boolean" then return Block("PROTECTION_UNKNOWN") end
    if context.Protected then return Block("PROTECTED") end
    if overlord.TechsCompleted < target.TechsCompleted or overlord.CivicsCompleted < target.CivicsCompleted then
        return Block("RESEARCH_PROGRESS_BEHIND")
    end
    if not regular then return Block("BELOW_THRESHOLDS") end
    -- The caller must track continuous advantage for this exact pair and tier.
    if not Integer(context.AdvantageSinceTurn) or context.AdvantageSinceTurn > context.SnapshotTurn
        or context.AdvantageOverlordID ~= overlord.PlayerID or context.AdvantageTargetID ~= target.PlayerID
        or context.AdvantageTier ~= result.Tier then return Block("ADVANTAGE_UNVERIFIED") end
    if context.Turn - context.AdvantageSinceTurn < holdTurns then return Block("ADVANTAGE_PENDING") end
    if not extreme then
        if type(context.AtWar) ~= "boolean" then return Block("WAR_UNKNOWN") end
        if not context.AtWar then return Block("KEY_VICTORY_REQUIRED") end
        local victory = context.KeyVictory
        if not Integer(context.WarStartTurn) or context.WarStartTurn > context.Turn
            or type(victory) ~= "table" or victory.By ~= overlord.PlayerID
            or victory.Against ~= target.PlayerID or not Integer(victory.Turn)
            or victory.Turn < context.WarStartTurn or victory.Turn > context.Turn
            or context.Turn - victory.Turn > victoryWindow then return Block("KEY_VICTORY_REQUIRED") end
        local capital = victory.Kind == "CAPITAL_CAPTURE" and victory.CapitalStillHeld == true
        local cityLoss = victory.Kind == "SIGNIFICANT_CITY_LOSS" and Integer(victory.LostCities)
            and Integer(victory.BaselineCities) and victory.LostCities >= 2
            and victory.LostCities <= victory.BaselineCities
            and victory.LostCities * 2 >= victory.BaselineCities
        if not capital and not cityLoss then return Block("KEY_VICTORY_REQUIRED") end
    end
    result.Eligible = true
    result.NeedsPlayerConfirmation = target.Human
    result.Reason = target.Human and "PLAYER_CONFIRMATION_REQUIRED" or "AI_CANDIDATE"
    result.NextAction = target.Human and "REQUEST_PLAYER_CONFIRMATION" or "AI_VASSAL_CANDIDATE"
    return result
end

function EC_Eligibility.ValidLedger(previous)
    return type(previous) == "table" and previous.SchemaVersion == 1 and PolicyValid(previous.Policy)
        and Integer(previous.OverlordID) and Integer(previous.TargetID) and previous.OverlordID ~= previous.TargetID
        and previous.OverlordID < 64 and previous.TargetID < 64
        and (previous.Tier == "REGULAR" or previous.Tier == "EXTREME")
        and Integer(previous.SinceTurn) and Integer(previous.LastSampleTurn)
        and previous.SinceTurn <= previous.LastSampleTurn
        and Integer(previous.Samples) and previous.Samples > 0
        and previous.Samples <= previous.LastSampleTurn - previous.SinceTurn + 1
        and (previous.Samples ~= 1 or previous.SinceTurn == previous.LastSampleTurn)
        and (previous.Samples == 1 or previous.SinceTurn ~= previous.LastSampleTurn)
        and Number(previous.SpeedMultiplier) and previous.SpeedMultiplier > 0
end

function EC_Eligibility.Observe(overlord, target, context, previous, policy)
    if policy == nil then policy = DEFAULTS end
    local function ReadOnly(reason)
        return { ReadOnly = true, Ledger = previous,
            Candidate = { Eligible = false, Reason = reason, Tier = "NONE", NextAction = "NONE" } }
    end
    if not PolicyValid(policy) then return ReadOnly("POLICY_INVALID") end
    if previous ~= nil then
        if not EC_Eligibility.ValidLedger(previous) then
            return ReadOnly("OBSERVATION_RECORD_UNSUPPORTED")
        end
        if type(context) == "table" and Integer(context.SnapshotTurn)
            and context.SnapshotTurn < previous.LastSampleTurn then return ReadOnly("OBSERVATION_TIME_REVERSED") end
    end
    local probe = {}
    if type(context) == "table" then for key, value in pairs(context) do probe[key] = value end end
    probe.AdvantageSinceTurn, probe.AdvantageTier = nil, nil
    probe.AdvantageOverlordID, probe.AdvantageTargetID = nil, nil
    local candidate = EC_Eligibility.Evaluate(overlord, target, probe, policy)
    if candidate.Reason ~= "ADVANTAGE_UNVERIFIED" then
        return { ReadOnly = false, Ledger = nil, Candidate = candidate }
    end
    local sameSeries = previous ~= nil and previous.OverlordID == overlord.PlayerID
        and previous.TargetID == target.PlayerID and previous.Tier == candidate.Tier
        and previous.SpeedMultiplier == context.SpeedMultiplier and SamePolicy(previous.Policy, policy)
        and context.SnapshotTurn - previous.LastSampleTurn <= policy.SnapshotMaxAge
    local ledger = {
        SchemaVersion = 1, OverlordID = overlord.PlayerID, TargetID = target.PlayerID,
        Tier = candidate.Tier, SinceTurn = sameSeries and previous.SinceTurn or context.SnapshotTurn,
        LastSampleTurn = context.SnapshotTurn, Samples = 1, SpeedMultiplier = context.SpeedMultiplier,
        Policy = CopyPolicy(policy),
    }
    if sameSeries then
        ledger.Samples = previous.Samples + (context.SnapshotTurn > previous.LastSampleTurn and 1 or 0)
    end
    probe.AdvantageSinceTurn, probe.AdvantageTier = ledger.SinceTurn, ledger.Tier
    probe.AdvantageOverlordID, probe.AdvantageTargetID = ledger.OverlordID, ledger.TargetID
    return { ReadOnly = false, Ledger = ledger,
        Candidate = EC_Eligibility.Evaluate(overlord, target, probe, policy) }
end
