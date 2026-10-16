-- Opt-in candidate diagnostics. This module never sends an annexation request.
EC_EligibilityObserver = {}
local function Integer(value) return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value) end
local function ID(value) return Integer(value) and value < 64 end
local function Safe(callback)
    local ok, value = pcall(callback)
    if ok then return value, true end
    return nil, false
end
local function Player(id) return ID(id) and Players ~= nil and Players[id] or nil end
local function Count(player)
    local n = Safe(function() return player:GetCities():GetCount() end)
    return Integer(n) and n or nil
end
local function Party(player)
    return Safe(function() return player:IsAlive() and player:IsMajor() end) == true
end
local function AtWar(attacker, target)
    local first = Safe(function() return Player(attacker):GetDiplomacy():IsAtWarWith(target) end)
    local second = Safe(function() return Player(target):GetDiplomacy():IsAtWarWith(attacker) end)
    if type(first) == "boolean" and first == second then return first end
    return nil
end
local function Baseline(player)
    local cities = Count(player)
    local capital = Safe(function() return player:GetCities():GetCapitalCity() end)
    local x, y = Safe(function() return capital:GetX() end), Safe(function() return capital:GetY() end)
    if cities == nil or not Integer(x) or not Integer(y) then return nil end
    return { Cities = cities, CapitalX = x, CapitalY = y }
end
local function Inspect(x, y)
    -- CityManager can be unavailable during map bootstrap or while a save is
    -- restoring.  Keep the probe fail-closed so a late battle event cannot
    -- abort the observer callback.
    local city, readable = Safe(function()
        return CityManager.GetCityAt(x, y)
    end)
    if not readable then return nil end
    if city == nil then return { Exists = false } end
    local owner = Safe(function() return city:GetOwner() end)
    return { Exists = true, Owner = owner }
end

function EC_EligibilityObserver.WarChanged(first, second, atWar, turn)
    if not ID(first) or not ID(second) or first == second or not Integer(turn) then return end
    local observed = false
    for _, pair in ipairs({ { first, second }, { second, first } }) do
        local attacker, target = pair[1], pair[2]
        if Party(Player(attacker)) and Party(Player(target)) and AtWar(attacker, target) == atWar then
            local ok = EC_WarContext.Observe(Player(target), attacker, turn, atWar, atWar and Baseline(Player(target)) or nil)
            observed = observed or ok == true
        end
    end
    return observed
end

function EC_EligibilityObserver.CityConquered(attacker, target, cityID, x, y, turn)
    if not ID(attacker) or not ID(target) or attacker == target or not Integer(cityID)
        or not Integer(x) or not Integer(y) or not Integer(turn)
        or not Party(Player(attacker)) or not Party(Player(target)) or AtWar(attacker, target) ~= true then return end
    local fact = Safe(function() return Inspect(x, y) end)
    if fact == nil or fact.Exists ~= true or fact.Owner ~= attacker then return end
    -- Without an observed session/baseline, no pre-mod conquest is invented.
    local ok, reason = EC_WarContext.Capture(Player(target), attacker, turn, x, y)
    print("[EC] battle_capture attacker=" .. attacker .. " target=" .. target .. " turn=" .. turn
        .. " accepted=" .. tostring(ok) .. " reason=" .. tostring(reason))
    return ok, reason
end

local function Snapshot(id, options)
    local player = Player(id)
    if not Party(player) or options.IsIndependent(id) ~= true then return nil end
    local row = EC_DataStore.ReadSnapshot(player, options.Turn, 5)
    if row == nil or row.AuthorID ~= options.AuthorID or row.SpeedMultiplier ~= options.SpeedMultiplier
        or row.Human ~= Safe(function() return player:IsHuman() end) or row.Cities ~= Count(player)
        or not row.Independent or not row.Alive or not row.Major then return nil end
    return row
end

function EC_EligibilityObserver.Update(options)
    if type(options) ~= "table" or not Integer(options.Turn) or not ID(options.AuthorID)
        or type(options.PlayerIDs) ~= "table" or #options.PlayerIDs > 64
        or type(options.IsIndependent) ~= "function" or type(options.IsProtected) ~= "function" then return end
    local count = 0
    for key in pairs(options.PlayerIDs) do
        if not Integer(key) or key < 1 or key > #options.PlayerIDs then return end
        count = count + 1
    end
    if count ~= #options.PlayerIDs then return end
    local policy, snapshots = EC_Eligibility.DefaultPolicy(), {}
    local ids, seen = {}, {}
    for _, id in ipairs(options.PlayerIDs) do
        if not ID(id) or seen[id] then return end
        seen[id] = true; ids[#ids + 1] = id
    end
    table.sort(ids)
    for _, id in ipairs(ids) do snapshots[id] = Snapshot(id, options) end
    for _, targetID in ipairs(ids) do
        local player, target = Player(targetID), snapshots[targetID]
        local old, readReason = EC_DataStore.ReadObservation(player)
        if (old ~= nil or readReason == "EMPTY") and (old == nil or old.Turn < options.Turn) then
            local chosen, context, rank = nil, nil, nil
            if target ~= nil then
                for _, attackerID in ipairs(ids) do
                    local attacker = snapshots[attackerID]
                    if attackerID ~= targetID and attacker ~= nil and attacker.Turn == target.Turn then
                        local probe = { Turn = options.Turn, SnapshotTurn = target.Turn,
                            SpeedMultiplier = options.SpeedMultiplier, Protected = options.IsProtected(attackerID, targetID, target.Human) }
                        local result = EC_Eligibility.Evaluate(attacker, target, probe, policy)
                        if result.Reason == "ADVANTAGE_UNVERIFIED" then
                            local quality = math.huge
                            for _, domain in ipairs({ "Military", "Economy", "Science", "Culture" }) do
                                quality = math.min(quality, result.Ratios[domain] / policy.Regular[domain])
                            end
                            local previous = old ~= nil and old.Active and old.Ledger.OverlordID == attackerID
                            -- Preserve a still-qualified observer; otherwise choose the best weakest-domain ratio.
                            local score = previous and math.huge or quality
                            if chosen == nil or score > rank then chosen, context, rank = attacker, probe, score end
                        end
                    end
                end
            end
            if chosen ~= nil then
                local atWar = AtWar(chosen.PlayerID, targetID)
                local observed = EC_WarContext.Observe(player, chosen.PlayerID, options.Turn, atWar,
                    atWar and Baseline(player) or nil)
                if observed then
                    local war = EC_WarContext.Context(player, chosen.PlayerID, options.Turn, atWar, Inspect)
                    if war ~= nil then for key, value in pairs(war) do context[key] = value end end
                end
                context.AtWar = atWar
                local result = EC_Eligibility.Observe(chosen, target, context,
                    old ~= nil and old.Active and old.Ledger or nil, policy)
                if not result.ReadOnly then
                    local ok, reason = EC_DataStore.WriteObservation(player, result.Ledger, options.Turn, result.Candidate.Reason)
                    if ok and (old == nil or old.Reason ~= result.Candidate.Reason) then
                        print("[EC] eligibility_observation attacker=" .. chosen.PlayerID .. " target=" .. targetID
                            .. " eligible=" .. tostring(result.Candidate.Eligible) .. " reason=" .. result.Candidate.Reason
                            .. " tier=" .. result.Candidate.Tier .. " action=" .. result.Candidate.NextAction)
                    elseif not ok then print("[EC] eligibility_store_failed target=" .. targetID .. " reason=" .. reason) end
                end
            elseif old ~= nil and old.Active then
                EC_DataStore.WriteObservation(player, nil, options.Turn, target == nil and "DATA_UNKNOWN" or "NO_QUALIFIED_OVERLORD")
            end
        end
    end
end
