-- Pure awakening protection policy. It does not inspect Map/Players or mutate diplomacy.
EC_Protection = {}
local STAGES = { PREPARATION = true, CONQUEST = true, SHOWDOWN = true }

local function Safe(callback)
    local ok, value = pcall(callback)
    if ok then return value end
    return nil
end

local function Integer(value) return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value) end
local function ID(value) return Integer(value) and value < 64 end
local function ValidNearby(list, human, awakened)
    if type(list) ~= "table" or #list > 62 then return false end
    local length = #list
    for key in pairs(list) do if not Integer(key) or key < 1 or key > length then return false end end
    local seen = {}
    for _, entry in ipairs(list) do
        if type(entry) ~= "table" or not ID(entry.PlayerID) or entry.PlayerID == human or entry.PlayerID == awakened
            or entry.Human ~= false or entry.Alive ~= true or entry.Major ~= true or entry.Independent ~= true
            or type(entry.Distance) ~= "number"
            or entry.Distance < 0 or entry.Distance ~= entry.Distance or entry.Distance == math.huge
            or seen[entry.PlayerID] then return false end
        seen[entry.PlayerID] = true
    end
    return true
end

-- Build a deterministic nearby-AI roster from already observed candidate rows.
-- The caller supplies distance calculation because Map/Players are unavailable
-- to the pure policy module and every unreadable row must remain fail-closed.
function EC_Protection.BuildNearby(context)
    if type(context) ~= "table" or type(context.Candidates) ~= "table"
        or type(context.Distance) ~= "function" or not ID(context.HumanPlayerID)
        or not ID(context.AwakenedPlayerID) or context.HumanPlayerID == context.AwakenedPlayerID
        or #context.Candidates > 62 then
        return nil, "INPUT_UNKNOWN"
    end
    local candidateKeys = 0
    for key in pairs(context.Candidates) do
        if not Integer(key) or key < 1 or key > #context.Candidates then
            return nil, "CANDIDATE_UNKNOWN"
        end
        candidateKeys = candidateKeys + 1
    end
    if candidateKeys ~= #context.Candidates then
        return nil, "CANDIDATE_UNKNOWN"
    end
    for index = 1, #context.Candidates do
        if context.Candidates[index] == nil then
            return nil, "CANDIDATE_UNKNOWN"
        end
    end
    local roster = {}
    local seen = {}
    for _, candidate in ipairs(context.Candidates) do
        if type(candidate) ~= "table" or not ID(candidate.PlayerID)
            or candidate.PlayerID == context.HumanPlayerID
            or candidate.PlayerID == context.AwakenedPlayerID
            or candidate.Human ~= false or candidate.Alive ~= true
            or candidate.Major ~= true or candidate.Independent ~= true
            or seen[candidate.PlayerID] then
            return nil, "CANDIDATE_UNKNOWN"
        end
        local distance = Safe(function() return context.Distance(candidate) end)
        if type(distance) ~= "number" or distance < 0 or distance ~= distance
            or distance == math.huge or distance == -math.huge then
            return nil, "DISTANCE_UNKNOWN"
        end
        seen[candidate.PlayerID] = true
        roster[#roster + 1] = {
            PlayerID = candidate.PlayerID,
            Human = false,
            Alive = true,
            Major = true,
            Independent = true,
            Distance = distance,
        }
    end
    table.sort(roster, function(a, b)
        if a.Distance == b.Distance then return a.PlayerID < b.PlayerID end
        return a.Distance < b.Distance
    end)
    return roster, "OK"
end

function EC_Protection.Evaluate(context)
    if type(context) ~= "table" or not Integer(context.Turn)
        or not ID(context.TargetID) or not ID(context.HumanPlayerID)
        or not ID(context.AwakenedPlayerID) or context.HumanPlayerID == context.AwakenedPlayerID
        or not ID(context.AttackerID)
        or not STAGES[context.Stage] then return nil, "CONTEXT_UNKNOWN" end
    local count = context.NearbyCount == nil and 2 or context.NearbyCount
    if count ~= 1 and count ~= 2 then return nil, "COUNT_INVALID" end
    if context.AttackerID ~= context.AwakenedPlayerID then return false, "OTHER_ATTACKER" end
    if context.TargetID == context.AwakenedPlayerID then return true, "SELF_ACTION_BLOCKED" end
    if context.Stage == "SHOWDOWN" then return false, "SHOWDOWN_RELEASED" end
    if context.Stage ~= "PREPARATION" and context.Stage ~= "CONQUEST" then return false, "NOT_ACTIVE" end
    if context.TargetID == context.HumanPlayerID then return true, "PLAYER_PROTECTED" end
    if context.NearbyComplete ~= true or not ValidNearby(context.Nearby, context.HumanPlayerID, context.AwakenedPlayerID) then
        return nil, "NEARBY_UNKNOWN"
    end
    local nearest = {}
    for _, entry in ipairs(context.Nearby) do nearest[#nearest + 1] = entry end
    table.sort(nearest, function(a, b)
        if a.Distance == b.Distance then return a.PlayerID < b.PlayerID end
        return a.Distance < b.Distance
    end)
    for index = 1, math.min(count, #nearest) do
        if nearest[index].PlayerID == context.TargetID then return true, "NEARBY_AI_PROTECTED" end
    end
    return false, "OUTSIDE_PROTECTED_NEIGHBORS"
end

function EC_Protection.IsProtected(context)
    local value, reason = EC_Protection.Evaluate(context)
    return value, reason
end
