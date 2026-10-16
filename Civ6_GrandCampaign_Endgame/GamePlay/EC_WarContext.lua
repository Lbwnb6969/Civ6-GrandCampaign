-- Bounded war evidence; observations and captures never issue diplomacy commands.
EC_WarContext = {}
local CAPACITY = 64
local FIELDS = { "AttackerID", "TargetID", "Turn", "Revision", "State", "Session",
    "SinceTurn", "BaselineCities", "CapitalX", "CapitalY", "Count", "Overflow" }
for slot = 1, CAPACITY do
    for _, key in ipairs({ "X", "Y", "CapturedTurn" }) do FIELDS[#FIELDS + 1] = key .. slot end
end
local function Integer(value) return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value) end
local function ID(value) return Integer(value) and value < 64 end
local function Prefix(attacker) return "EC_WAR_" .. attacker .. "_" end
local function Valid(row, owner)
    if not ID(row.AttackerID) or row.TargetID ~= owner or not ID(owner) or row.AttackerID == owner
        or not Integer(row.Turn) or not Integer(row.Revision) or row.Revision < 1
        or (row.State ~= "WAR" and row.State ~= "PEACE") or not Integer(row.Session)
        or row.Session < 1 or not Integer(row.SinceTurn) or row.SinceTurn > row.Turn
        or not Integer(row.BaselineCities) or not Integer(row.CapitalX) or not Integer(row.CapitalY)
        or not Integer(row.Count) or row.Count > CAPACITY or type(row.Overflow) ~= "boolean" then return false end
    local seen = {}
    for slot = 1, row.Count do
        local x, y, turn = row["X" .. slot], row["Y" .. slot], row["CapturedTurn" .. slot]
        if not Integer(x) or not Integer(y) or not Integer(turn) or turn < row.SinceTurn or turn > row.Turn then return false end
        local key = x .. ":" .. y
        if seen[key] then return false end
        seen[key] = true
    end
    -- Inactive slots retain physical properties but are not part of this session.
    for slot = row.Count + 1, CAPACITY do
        row["X" .. slot], row["Y" .. slot], row["CapturedTurn" .. slot] = nil, nil, nil
    end
    return true
end
local function Read(target, attacker)
    if not ID(attacker) then return nil, "PARTY_INVALID" end
    return EC_DataStore.ReadWarRecord(target, Prefix(attacker), FIELDS, Valid)
end
local function Write(target, row)
    return EC_DataStore.WriteWarRecord(target, Prefix(row.AttackerID), FIELDS, Valid, row)
end
local function Copy(row)
    local copy = {}; for key, value in pairs(row) do copy[key] = value end; return copy
end

function EC_WarContext.Observe(target, attacker, turn, atWar, baseline)
    if not ID(attacker) or not Integer(turn) or type(atWar) ~= "boolean" then return false, "WAR_UNKNOWN" end
    local row, reason = Read(target, attacker)
    if row == nil and reason ~= "EMPTY" then return false, reason end
    if row ~= nil and turn < row.Turn then return false, "TURN_REVERSED" end
    if row ~= nil and (row.State == "WAR") == atWar then return true, "UNCHANGED" end
    if not atWar and row == nil then return true, "NO_WAR" end
    if atWar then
        if type(baseline) ~= "table" or not Integer(baseline.Cities) or baseline.Cities == 0
            or not Integer(baseline.CapitalX) or not Integer(baseline.CapitalY) then return false, "BASELINE_UNKNOWN" end
        local ok, targetID = pcall(function() return target:GetID() end)
        if not ok or not ID(targetID) or attacker == targetID then return false, "PARTY_INVALID" end
        row = { AttackerID = attacker, TargetID = targetID, Turn = turn,
            Revision = row ~= nil and row.Revision + 1 or 1, State = "WAR",
            Session = row ~= nil and row.Session + 1 or 1, SinceTurn = turn,
            BaselineCities = baseline.Cities, CapitalX = baseline.CapitalX, CapitalY = baseline.CapitalY,
            Count = 0, Overflow = false }
    else row = Copy(row); row.State, row.Turn, row.Revision = "PEACE", turn, row.Revision + 1 end
    return Write(target, row)
end

function EC_WarContext.Capture(target, attacker, turn, x, y)
    if not ID(attacker) or not Integer(turn) or not Integer(x) or not Integer(y) then return false, "CAPTURE_INVALID" end
    local row, reason = Read(target, attacker)
    if row == nil then return false, reason end
    if row.State ~= "WAR" or turn < row.Turn then return false, "SESSION_INVALID" end
    row = Copy(row)
    local slot = nil
    for index = 1, row.Count do if row["X" .. index] == x and row["Y" .. index] == y then slot = index; break end end
    if slot ~= nil and row["CapturedTurn" .. slot] == turn then return true, "DUPLICATE" end
    if slot == nil then
        if row.Count == CAPACITY then
            if row.Overflow then return true, "CAPACITY_REACHED" end
            row.Overflow = true
        else slot = row.Count + 1; row.Count = slot end
    end
    if slot ~= nil then row["X" .. slot], row["Y" .. slot], row["CapturedTurn" .. slot] = x, y, turn end
    row.Turn, row.Revision = turn, row.Revision + 1
    return Write(target, row)
end

function EC_WarContext.Context(target, attacker, turn, atWar, inspect)
    local row, reason = Read(target, attacker)
    if row == nil then return nil, reason end
    if not Integer(turn) or turn < row.Turn then return nil, "TURN_REVERSED" end
    if atWar ~= true or row.State ~= "WAR" then return { AtWar = atWar }, "NOT_AT_WAR" end
    local context = { AtWar = true, WarStartTurn = row.SinceTurn }
    local held, latest, capitalTurn = 0, nil, nil
    for slot = 1, row.Count do
        local x, y = row["X" .. slot], row["Y" .. slot]
        local ok, fact = pcall(inspect, x, y)
        if not ok or type(fact) ~= "table" or type(fact.Exists) ~= "boolean" then return context, "OWNERSHIP_UNKNOWN" end
        if fact.Exists then
            if not ID(fact.Owner) then return context, "OWNERSHIP_UNKNOWN" end
            if fact.Owner == attacker then
                local capturedTurn = row["CapturedTurn" .. slot]
                held = held + 1; latest = math.max(latest or capturedTurn, capturedTurn)
                if x == row.CapitalX and y == row.CapitalY then capitalTurn = capturedTurn end
            end
        end
    end
    if capitalTurn ~= nil then
        context.KeyVictory = { Kind = "CAPITAL_CAPTURE", By = attacker, Against = row.TargetID,
            Turn = capitalTurn, CapitalStillHeld = true }
    elseif not row.Overflow and latest ~= nil and held >= 2 and held * 2 >= row.BaselineCities then
        context.KeyVictory = { Kind = "SIGNIFICANT_CITY_LOSS", By = attacker, Against = row.TargetID,
            Turn = latest, LostCities = held, BaselineCities = row.BaselineCities }
    end
    return context, row.Overflow and "CAPACITY_REACHED" or "OK"
end
