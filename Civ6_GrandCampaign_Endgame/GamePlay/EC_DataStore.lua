-- Scalar double buffers keep the last complete record readable during a retry.
EC_DataStore = {}
local DOMAINS = { "Military", "Economy", "Science", "Culture" }
local SNAPSHOT_FIELDS = { "PlayerID", "AuthorID", "Turn", "SpeedMultiplier", "Source",
    "Human", "Alive", "Major", "Independent", "Cities", "Military", "NetGold", "GoldBalance",
    "Science", "Culture", "TechsCompleted", "CivicsCompleted" }
local OBSERVATION_FIELDS = { "State", "Reason", "Turn", "OverlordID", "TargetID", "Tier",
    "SinceTurn", "LastSampleTurn", "Samples", "SpeedMultiplier" }
for _, group in ipairs({ "Regular", "Extreme", "Floors" }) do
    for _, domain in ipairs(DOMAINS) do OBSERVATION_FIELDS[#OBSERVATION_FIELDS + 1] = group .. "_" .. domain end
end
for _, key in ipairs({ "HoldTurnsStandard", "VictoryWindowStandard", "SnapshotMaxAge" }) do
    OBSERVATION_FIELDS[#OBSERVATION_FIELDS + 1] = key
end

local function Number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function Integer(value) return Number(value) and value >= 0 and value == math.floor(value) end
local function Get(player, key)
    local ok, value = pcall(function() return player:GetProperty(key) end)
    return value, ok
end
local function Set(player, key, value)
    local ok, result = pcall(function() return player:SetProperty(key, value) end)
    return ok and result ~= false
end
local function Owner(player)
    local ok, id = pcall(function() return player:GetID() end)
    return ok and Integer(id) and id < 64 and id or nil
end
local function SnapshotValid(record, owner)
    if type(record) ~= "table" or not Integer(owner) or record.PlayerID ~= owner or not Integer(record.AuthorID)
        or record.AuthorID >= 64
        or not Integer(record.Turn) or not Number(record.SpeedMultiplier) or record.SpeedMultiplier <= 0
        or record.Source ~= "UI_BRIDGE_TEST" then return false end
    for _, key in ipairs({ "Human", "Alive", "Major", "Independent" }) do
        if type(record[key]) ~= "boolean" then return false end
    end
    for _, key in ipairs({ "Cities", "TechsCompleted", "CivicsCompleted" }) do
        if not Integer(record[key]) then return false end
    end
    for _, key in ipairs({ "Military", "GoldBalance", "Science", "Culture" }) do
        if not Number(record[key]) or record[key] < 0 then return false end
    end
    return Number(record.NetGold) and EC_Eligibility.Economy(record.NetGold, record.GoldBalance, record.SpeedMultiplier) ~= nil
end

local function Unflatten(record)
    local policy = {}
    for _, group in ipairs({ "Regular", "Extreme", "Floors" }) do
        policy[group] = {}
        for _, domain in ipairs(DOMAINS) do policy[group][domain] = record[group .. "_" .. domain] end
    end
    for _, key in ipairs({ "HoldTurnsStandard", "VictoryWindowStandard", "SnapshotMaxAge" }) do policy[key] = record[key] end
    return { SchemaVersion = 1, OverlordID = record.OverlordID, TargetID = record.TargetID, Tier = record.Tier,
        SinceTurn = record.SinceTurn, LastSampleTurn = record.LastSampleTurn, Samples = record.Samples,
        SpeedMultiplier = record.SpeedMultiplier, Policy = policy }
end
local function ObservationValid(record, owner)
    if type(record) ~= "table" or not Integer(record.Turn) or record.TargetID ~= owner
        or type(record.Reason) ~= "string" or #record.Reason > 64
        or not record.Reason:match("^[A-Z_]+$") then return false end
    if record.State == "INVALIDATED" then
        for _, key in ipairs(OBSERVATION_FIELDS) do
            if key ~= "State" and key ~= "Reason" and key ~= "Turn" and key ~= "TargetID" then record[key] = nil end
        end
        return true
    end
    return record.State == "ACTIVE" and EC_Eligibility.ValidLedger(Unflatten(record))
        and record.LastSampleTurn <= record.Turn
end

local function ReadRaw(player, prefix, fields, valid)
    local owner = Owner(player)
    if owner == nil then return nil, "OWNER_UNKNOWN" end
    local schema, schemaOK = Get(player, prefix .. "SCHEMA")
    local slot, slotOK = Get(player, prefix .. "ACTIVE_BANK")
    if not schemaOK or not slotOK then return nil, "READ_FAILED" end
    if schema == nil and slot == nil then return nil, "EMPTY" end
    if schema ~= 1 then return nil, "VERSION_UNSUPPORTED" end
    if slot == nil then return nil, "EMPTY" end
    if slot ~= 1 and slot ~= 2 then return nil, "BANK_INVALID" end
    local bank = prefix .. "BANK" .. slot .. "_"
    local ready, readyOK = Get(player, bank .. "READY")
    if not readyOK then return nil, "READ_FAILED" end
    if ready ~= 1 then return nil, "RECORD_INCOMPLETE" end
    local record = {}
    for _, key in ipairs(fields) do
        local value, ok = Get(player, bank .. key)
        if not ok then return nil, "READ_FAILED" end
        record[key] = value
    end
    if not valid(record, owner) then return nil, "RECORD_INVALID" end
    return record, "OK", slot
end

local function Write(player, prefix, fields, valid, record, revisioned, cityRefresh)
    if not valid(record, Owner(player)) then return false, "RECORD_INVALID" end
    local old, reason, active = ReadRaw(player, prefix, fields, valid)
    if old == nil and reason ~= "EMPTY" then return false, reason end
    if cityRefresh ~= nil then
        if old == nil or active ~= cityRefresh.Bank or old.Cities ~= cityRefresh.Cities
            or old.Turn ~= record.Turn or old.Cities == record.Cities then
            return false, "REFRESH_CONFLICT"
        end
        for _, key in ipairs({ "PlayerID", "AuthorID", "Source", "SpeedMultiplier", "Human", "Alive", "Major", "Independent" }) do
            if old[key] ~= record[key] then return false, "REFRESH_IDENTITY_CHANGED" end
        end
    end
    if old ~= nil then
        if record.Turn < old.Turn then return false, "TURN_REVERSED" end
        if record.Turn == old.Turn then
            local same = true
            for _, key in ipairs(fields) do
                if old[key] ~= record[key] then same = false; break end
            end
            if same then return true, "DUPLICATE" end
            if not revisioned and cityRefresh == nil then return false, "SAME_TURN_CONFLICT" end
        end
        if revisioned and record.Revision ~= old.Revision + 1 then return false, "REVISION_CONFLICT" end
    end
    local slot = active == 1 and 2 or 1
    local bank = prefix .. "BANK" .. slot .. "_"
    if not Set(player, bank .. "READY", 0) then return false, "WRITE_FAILED" end
    for _, key in ipairs(fields) do
        if record[key] ~= nil and not Set(player, bank .. key, record[key]) then return false, "WRITE_FAILED" end
    end
    if not Set(player, bank .. "READY", 1) or not Set(player, prefix .. "SCHEMA", 1)
        or not Set(player, prefix .. "ACTIVE_BANK", slot) then return false, "WRITE_FAILED" end
    return true, "WRITTEN"
end

-- War events can update multiple times in a turn; callers validate the schema
-- and advance one revision from the last published record.
function EC_DataStore.ReadWarRecord(player, prefix, fields, valid)
    return ReadRaw(player, prefix, fields, valid)
end
function EC_DataStore.WriteWarRecord(player, prefix, fields, valid, record)
    return Write(player, prefix, fields, valid, record, true)
end

function EC_DataStore.WriteSnapshot(player, record)
    return Write(player, "EC_METRICS_", SNAPSHOT_FIELDS, SnapshotValid, record)
end
-- Only the validated native bridge may replace a same-turn row after an actual
-- city-count change. The old bank and count bind the refresh to its source row.
function EC_DataStore.RefreshSnapshot(player, record, bank, cities)
    if (bank ~= 1 and bank ~= 2) or not Integer(cities) then return false, "REFRESH_INVALID" end
    return Write(player, "EC_METRICS_", SNAPSHOT_FIELDS, SnapshotValid, record, nil, { Bank = bank, Cities = cities })
end
function EC_DataStore.ReadSnapshot(player, turn, maxAge)
    local record, reason = ReadRaw(player, "EC_METRICS_", SNAPSHOT_FIELDS, SnapshotValid)
    if record == nil then return nil, reason end
    if not Integer(turn) or not Integer(maxAge) or record.Turn > turn then return nil, "TURN_INVALID" end
    if turn - record.Turn > maxAge then return nil, "STALE" end
    record.Economy = EC_Eligibility.Economy(record.NetGold, record.GoldBalance, record.SpeedMultiplier)
    return record, "OK"
end

function EC_DataStore.WriteObservation(player, ledger, turn, reason)
    local record = { State = "INVALIDATED", TargetID = Owner(player), Turn = turn, Reason = reason }
    if ledger ~= nil then
        if not EC_Eligibility.ValidLedger(ledger) or not Integer(turn) or ledger.LastSampleTurn > turn then return false, "RECORD_INVALID" end
        record.State = "ACTIVE"
        for _, key in ipairs({ "OverlordID", "TargetID", "Tier", "SinceTurn", "LastSampleTurn", "Samples", "SpeedMultiplier" }) do
            record[key] = ledger[key]
        end
        for _, group in ipairs({ "Regular", "Extreme", "Floors" }) do
            for _, domain in ipairs(DOMAINS) do record[group .. "_" .. domain] = ledger.Policy[group][domain] end
        end
        for _, key in ipairs({ "HoldTurnsStandard", "VictoryWindowStandard", "SnapshotMaxAge" }) do record[key] = ledger.Policy[key] end
    end
    return Write(player, "EC_ADVANTAGE_", OBSERVATION_FIELDS, ObservationValid, record)
end
function EC_DataStore.ReadObservation(player)
    local record, reason = ReadRaw(player, "EC_ADVANTAGE_", OBSERVATION_FIELDS, ObservationValid)
    if record == nil then return nil, reason end
    return { Active = record.State == "ACTIVE", Turn = record.Turn, Reason = record.Reason,
        Ledger = record.State == "ACTIVE" and Unflatten(record) or nil }, "OK"
end
