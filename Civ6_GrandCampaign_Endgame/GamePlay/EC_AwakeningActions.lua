-- Explicit live experiments use bounded modifiers and one persisted war attempt.
EC_AwakeningActions = {}
local PREFIX = "EC_AWAKENING_ACTIONS_"
-- Awakening develops the economy and military production, never unit strength.
-- The retired COMBAT journal is retained unchanged for old saves.
local BONUSES = { "PRODUCTION", "MILITARY", "FOOD", "GOLD", "SCIENCE", "CULTURE" }
local BONUS_PHASE = { PRODUCTION = 1, MILITARY = 1, FOOD = 1, GOLD = 2, SCIENCE = 3, CULTURE = 3 }
local STAGES = { TRIGGERED = 1, PREPARATION = 1, CONQUEST = 2, SHOWDOWN = 3 }
local MAX_AI_FRONTS = 3
local function Integer(value) return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value) end
local function ID(value) return Integer(value) and value < 64 end
local function Safe(callback)
    local ok, value = pcall(callback)
    return value, ok
end
local function Get(player, key)
    return Safe(function() return player:GetProperty(PREFIX .. key) end)
end
local function Set(player, key, value)
    local result, ok = Safe(function() return player:SetProperty(PREFIX .. key, value) end)
    return ok and result ~= false
end
local function Log(options, message)
    -- Diagnostics must not interrupt a committed native action.
    pcall(function()
        if options.Log then options.Log(message) else print("[EC] " .. message) end
    end)
end
local function Party(id, human, independent)
    if not ID(id) or Players == nil or Players[id] == nil then return false end
    local valid, ok = Safe(function()
        local player = Players[id]
        return player:IsAlive() == true and player:IsMajor() == true
            and player:IsHuman() == human and player:GetCities():GetCount() > 0
            and independent(id) == true
    end)
    return ok and valid == true
end
local function AtWar(first, second)
    local a, aOK = Safe(function() return Players[first]:GetDiplomacy():IsAtWarWith(second) end)
    local b, bOK = Safe(function() return Players[second]:GetDiplomacy():IsAtWarWith(first) end)
    if aOK and bOK and type(a) == "boolean" and a == b then return a end
    return nil
end
local function Capital(id)
    local result, ok = Safe(function()
        local city = Players[id]:GetCities():GetCapitalCity()
        if city == nil or city:GetOwner() ~= id then return nil end
        local x, y = city:GetX(), city:GetY()
        if not Integer(x) or not Integer(y) then return nil end
        return { X = x, Y = y }
    end)
    return ok and result or nil
end
local function Protected(options, target, human)
    local value, ok = Safe(function() return options.IsProtected(options.AwakenedID, target, human) end)
    if ok and type(value) == "boolean" then return value end
    return nil
end

local function RetireStrength(player, options)
    local legacy, readable = Get(player, "BONUS_COMBAT")
    if not readable then return false, "READ_FAILED" end
    if legacy == nil then return true end
    local retired, retiredOK = Get(player, "RETIRED_COMBAT")
    if not retiredOK then return false, "READ_FAILED" end
    if retired == "APPLIED" or retired == "ZERO" then return true end
    if retired ~= nil then return false, "MODIFIER_OUTCOME_UNKNOWN" end
    -- Saved modifier instances retain their original arguments even when the
    -- database Amount changes to zero. Inspect the instance, not the XML row.
    local amount, known = Safe(function()
        local found, total = 0, 0
        for _, instance in ipairs(GameEffects.GetModifiers()) do
            local definition = GameEffects.GetModifierDefinition(instance)
            if definition.Id == "EC_AWAKENING_COMBAT" or definition.Id == "EC_AWAKENING_RETIRE_COMBAT_10" then
                local owner = GameEffects.GetModifierOwner(instance)
                if GameEffects.GetObjectsPlayerId(owner) == options.AwakenedID then
                    if definition.Id ~= "EC_AWAKENING_COMBAT" then return nil end
                    local value = tonumber(definition.Arguments and definition.Arguments.Amount)
                    if value ~= 0 and value ~= 10 then return nil end
                    found = found + 1; total = total + value
                end
            end
        end
        if found ~= 1 then return nil end
        return total
    end)
    if not known or amount == nil then return false, "LEGACY_STRENGTH_UNKNOWN" end
    if amount == 0 then
        return Set(player, "RETIRED_COMBAT", "ZERO"), "WRITE_FAILED"
    end
    if not Set(player, "RETIRED_COMBAT", "ATTACHING") then return false, "WRITE_FAILED" end
    local result, attached = Safe(function() return player:AttachModifierByID("EC_AWAKENING_RETIRE_COMBAT_10") end)
    if not attached or result == false then return false, "MODIFIER_OUTCOME_UNKNOWN" end
    if not Set(player, "RETIRED_COMBAT", "APPLIED") then return false, "MODIFIER_OUTCOME_UNKNOWN" end
    Log(options, "awakening_retired_strength player=" .. options.AwakenedID .. " amount=10")
    return true
end

local function ApplyBonuses(player, options)
    local schema, readable = Get(player, "SCHEMA")
    if not readable then return false, "READ_FAILED" end
    if schema ~= nil and schema ~= 1 then return false, "VERSION_UNSUPPORTED" end
    if type(player.AttachModifierByID) ~= "function" then return false, "MODIFIER_API_UNAVAILABLE" end
    local states = {}
    for _, bonus in ipairs(BONUSES) do
        local state, stateOK = Get(player, "BONUS_" .. bonus)
        if not stateOK then return false, "READ_FAILED" end
        if state ~= nil and state ~= "APPLIED" then return false, "MODIFIER_OUTCOME_UNKNOWN" end
        states[bonus] = state
    end
    local retired, retireReason = RetireStrength(player, options)
    if not retired then return false, retireReason end
    if schema == nil and not Set(player, "SCHEMA", 1) then return false, "WRITE_FAILED" end
    for _, bonus in ipairs(BONUSES) do
        local key = "BONUS_" .. bonus
        if states[bonus] == nil and BONUS_PHASE[bonus] <= STAGES[options.Stage] then
            -- Persist intent before calling an API whose instances cannot be counted reliably.
            if not Set(player, key, "ATTACHING") then return false, "WRITE_FAILED" end
            local result, attached = Safe(function() return player:AttachModifierByID("EC_AWAKENING_" .. bonus) end)
            if not attached or result == false then return false, "MODIFIER_OUTCOME_UNKNOWN" end
            if not Set(player, key, "APPLIED") then return false, "MODIFIER_OUTCOME_UNKNOWN" end
            -- The action gate already validated this identity.  Do not call a
            -- second native GetID getter only for logging after a modifier was
            -- attached; some builds expose the player object without that
            -- getter, and a logging failure must not turn a committed effect
            -- into an escaped gameplay exception.
            Log(options, "awakening_bonus_applied player=" .. tostring(options.AwakenedID) .. " bonus=" .. bonus)
        end
    end
    return true, "BONUSES_READY"
end

local function LegalWarType(diplomacy,target)
    if WarTypes==nil then return nil end
    for _,name in ipairs({"FORMAL_WAR","SURPRISE_WAR"}) do
        local kind=WarTypes[name]
        if kind~=nil then
            local legal,known=Safe(function() return diplomacy:CanDeclareWarOn(target,kind,false) end)
            if known and legal==true then return kind end
            if not known then return nil end
        end
    end
    return nil
end

local function Target(options, ids)
    local attacker = options.AwakenedID
    if options.Stage == "SHOWDOWN" then
        local humanProtection = Protected(options, options.HumanID, true)
        if humanProtection == nil then return nil, "PROTECTION_UNKNOWN" end
        if Party(options.HumanID, true, options.IsIndependent) and humanProtection == false then
            local war = AtWar(attacker, options.HumanID)
            if war == nil then return nil, "WAR_STATUS_UNKNOWN" end
            if not war then
                local diplomacy, known = Safe(function() return Players[attacker]:GetDiplomacy() end)
                if known and LegalWarType(diplomacy, options.HumanID) ~= nil then return options.HumanID end
            end
        end
    end
    local origin = Capital(attacker)
    if origin == nil then return nil, "CAPITAL_UNKNOWN" end
    local selected, distance, fronts = nil, nil, 0
    for _, id in ipairs(ids) do
        if id ~= attacker then
            local atWar = AtWar(attacker, id)
            if atWar == nil then return nil, "WAR_STATUS_UNKNOWN" end
            local independentAI = Party(id, false, options.IsIndependent)
            if atWar and independentAI then fronts = fronts + 1 end
            if not atWar and independentAI and Protected(options, id, false) == false then
                local capital = Capital(id)
                if capital ~= nil then
                    local length, ok = Safe(function() return Map.GetPlotDistance(origin.X, origin.Y, capital.X, capital.Y) end)
                    local diplomacy, dipOK = Safe(function() return Players[attacker]:GetDiplomacy() end)
                    local warType = dipOK and LegalWarType(diplomacy,id)
                    if ok and Integer(length) and warType ~= nil
                        and (distance == nil or length < distance or (length == distance and id < selected)) then
                        selected, distance = id, length
                    end
                end
            end
        end
    end
    if fronts >= MAX_AI_FRONTS then return nil, "AI_FRONT_LIMIT" end
    return selected, selected == nil and "NO_LEGAL_TARGET" or nil
end

function EC_AwakeningActions.Update(options)
    if type(options) ~= "table" or options.Enabled ~= true or options.ObservationOnly ~= false
        or options.DryRun ~= false or options.Mode ~= "LIVE_TEST" then return false, "DISABLED" end
    if not Integer(options.Turn) or not ID(options.AwakenedID) or not ID(options.HumanID)
        or options.AwakenedID == options.HumanID or not Integer(options.WarInterval) or options.WarInterval < 1
        or type(options.IsIndependent) ~= "function" or type(options.IsProtected) ~= "function" then
        return false, "INPUT_INVALID"
    end
    local multiplayer, singleOK = Safe(function() return GameConfiguration.IsAnyMultiplayer() end)
    if not singleOK or multiplayer ~= false then return false, "SINGLE_PLAYER_REQUIRED" end
    if not Party(options.AwakenedID, false, options.IsIndependent) then return false, "CANDIDATE_INVALID" end
    if not Party(options.HumanID, true, options.IsIndependent) then return false, "HUMAN_INVALID" end
    if not STAGES[options.Stage] then return false, "STAGE_INACTIVE" end
    -- Validate the complete roster before attaching even preparation bonuses.
    local majors, majorsOK = Safe(function() return PlayerManager.GetAliveMajors() end)
    if not majorsOK or type(majors) ~= "table" or #majors > 64 then return false, "MAJORS_UNKNOWN" end
    local count = 0
    for key in pairs(majors) do
        if not Integer(key) or key < 1 or key > #majors then return false, "MAJORS_UNKNOWN" end
        count = count + 1
    end
    if count ~= #majors then return false, "MAJORS_UNKNOWN" end
    local ids, seen, humans = {}, {}, 0
    for _, major in ipairs(majors) do
        local id, ok = Safe(function() return major:GetID() end)
        if not ok or not ID(id) or seen[id] then return false, "MAJORS_UNKNOWN" end
        local human, roleOK = Safe(function()
            if major:IsAlive() ~= true or major:IsMajor() ~= true then return nil end
            return major:IsHuman()
        end)
        if not roleOK or type(human) ~= "boolean" then return false, "MAJORS_UNKNOWN" end
        if human then
            humans = humans + 1
            if id ~= options.HumanID then return false, "SINGLE_HUMAN_REQUIRED" end
        end
        seen[id] = true; ids[#ids + 1] = id
    end
    if not seen[options.AwakenedID] or not seen[options.HumanID] then return false, "PARTY_MISSING" end
    if humans ~= 1 then return false, "SINGLE_HUMAN_REQUIRED" end
    local player = Players[options.AwakenedID]
    local ready, bonusReason = ApplyBonuses(player, options)
    if not ready then return false, bonusReason end
    if options.Stage ~= "CONQUEST" and options.Stage ~= "SHOWDOWN" then return true, "PREPARING" end
    local last, readable = Get(player, "WAR_ATTEMPT_TURN")
    if not readable then return false, "READ_FAILED" end
    if last ~= nil and (not Integer(last) or last > options.Turn) then return false, "TURN_INVALID" end
    if last ~= nil and options.Turn - last < options.WarInterval then return true, "WAR_COOLDOWN" end
    if WarTypes == nil or (WarTypes.FORMAL_WAR == nil and WarTypes.SURPRISE_WAR == nil) then return false, "WAR_TYPE_UNAVAILABLE" end
    table.sort(ids)
    local target, reason = Target(options, ids)
    if target == nil then return true, reason end
    local human = target == options.HumanID
    if not Party(target, human, options.IsIndependent) or Protected(options, target, human) ~= false then
        return false, "TARGET_CHANGED"
    end
    local atWar = AtWar(options.AwakenedID, target)
    if atWar == true then return true, "WAR_ALREADY_ACTIVE" end
    if atWar == nil then return false, "WAR_STATUS_UNKNOWN" end
    local diplomacy, dipOK = Safe(function() return player:GetDiplomacy() end)
    local warType = dipOK and LegalWarType(diplomacy,target)
    if warType == nil then return false, "WAR_NOT_LEGAL" end
    if not Set(player, "WAR_TARGET", target) or not Set(player, "WAR_ATTEMPT_TURN", options.Turn) then
        return false, "WRITE_FAILED"
    end
    local _, declared = Safe(function() return diplomacy:DeclareWarOn(target, warType, false) end)
    local confirmed = AtWar(options.AwakenedID, target) == true
    Log(options, "awakening_war_attempt turn=" .. options.Turn .. " attacker=" .. options.AwakenedID
        .. " target=" .. target .. " stage=" .. options.Stage .. " war_type="..tostring(warType).." returned=" .. tostring(declared)
        .. " confirmed=" .. tostring(confirmed))
    return confirmed, confirmed and "WAR_CONFIRMED" or "WAR_OUTCOME_UNKNOWN"
end
