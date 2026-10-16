-- Deterministic vassalization and restoration contract.
-- This module consumes caller-provided snapshots and an explicit adapter. It
-- does not discover or mutate native Civ VI objects until a future caller
-- supplies a reviewed API adapter.
EC_VassalTransaction = {}

function EC_VassalTransaction.CreateJournal(game, token)
    assert(token==nil or (type(token)=="string" and #token>0 and #token<=160))
    local prefix=token and "EC_NATIVE_JOURNAL_"..token.."_" or ""
    return {
        Read=function(_,key)
            local value=game:GetProperty(prefix..key)
            return value
        end,
        Write=function(_,key,value)
            game:SetProperty(prefix..key,value)
            local stored=game:GetProperty(prefix..key)
            return stored==value
        end,
    }
end

local SCHEMA_VERSION = 1
local AUTONOMY_AUTHORIZATION_SCHEMA_VERSION = 1
local MAX_PLAYERS = 64
local MAX_CITIES = 64
local MAX_UNITS = 256
local JOURNAL_PREFIX = "EC_VASSAL_TX_"
local Unpack = table.unpack or unpack

local function Integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function PlayerID(value)
    return Integer(value) and value < MAX_PLAYERS
end

local function Text(value)
    return type(value) == "string" and value ~= "" and #value <= 160
end

local function Safe(callback)
    local ok, first, second = pcall(callback)
    if not ok then return nil, false end
    return first, true, second
end

local function CopyRecord(record)
    if record.Payload ~= nil then
        assert(EC_CityPayload ~= nil, "City payload codec required")
        return EC_CityPayload.Copy(record)
    end
    local copy = {}
    for key, value in pairs(record) do copy[key] = value end
    return copy
end

local function SortByID(first, second)
    return first.ID < second.ID
end

local function DenseList(records, limit, minimum)
    if type(records) ~= "table" or #records < minimum or #records > limit then return false end
    local count = 0
    for key in pairs(records) do
        if not Integer(key) or key < 1 or key > #records then return false end
        count = count + 1
    end
    return count == #records
end

local function ValidateEnvelope(input, action)
    if type(input) ~= "table" or input.Mode ~= "LIVE_TEST" or input.ObservationOnly ~= false
        or input.SinglePlayer ~= true or input.Action ~= action then
        return false, "DISABLED"
    end
    if not Integer(input.Turn) or not PlayerID(input.OverlordID) or not PlayerID(input.VassalID)
        or input.OverlordID == input.VassalID or not Text(input.TransactionToken) then
        return false, "INPUT_INVALID"
    end
    return true
end

local function ValidateParty(row, expectedID, archived)
    if type(row) ~= "table" or row.ID ~= expectedID or row.Alive ~= true or row.Major ~= true
        or type(row.Human) ~= "boolean" or row.Independent ~= (not archived)
        or row.Archived ~= archived or not Integer(row.Cities) then
        return false
    end
    if archived and row.Cities ~= 0 then return false end
    if not archived and row.Cities < 1 then return false end
    return true
end

local function NormalizeCities(records, ownerID, expectedCount)
    if not DenseList(records, MAX_CITIES, 1)
        or not Integer(expectedCount) or expectedCount ~= #records then
        return nil, nil, "CITY_LIST_INVALID"
    end
    local seenIDs, seenCoordinates, normalized, capitalID = {}, {}, {}, nil
    for index = 1, #records do
        local row = records[index]
        if type(row) ~= "table" or not Integer(row.CityID) or row.Owner ~= ownerID
            or not Integer(row.X) or not Integer(row.Y) or type(row.Capital) ~= "boolean"
            or seenIDs[row.CityID] or seenCoordinates[row.X .. ":" .. row.Y] then
            return nil, nil, "CITY_RECORD_INVALID"
        end
        if row.OriginalOwner ~= nil and not PlayerID(row.OriginalOwner) then
            return nil, nil, "CITY_ORIGINAL_OWNER_INVALID"
        end
        if row.Population ~= nil and (not Integer(row.Population) or row.Population < 0) then
            return nil, nil, "CITY_POPULATION_INVALID"
        end
        if row.Capital then
            if capitalID ~= nil then return nil, nil, "CAPITAL_DUPLICATE" end
            capitalID = row.CityID
        end
        seenIDs[row.CityID] = true
        seenCoordinates[row.X .. ":" .. row.Y] = true
        local copy, copied = Safe(function() return CopyRecord(row) end)
        if not copied then return nil, nil, "CITY_PAYLOAD_INVALID" end
        normalized[#normalized + 1] = copy
    end
    if capitalID == nil then return nil, nil, "CAPITAL_UNKNOWN" end
    table.sort(normalized, function(a, b) return a.CityID < b.CityID end)
    return normalized, capitalID
end

local function NormalizeUnits(records, ownerID)
    if not DenseList(records, MAX_UNITS, 0) then return nil, "UNIT_LIST_INVALID" end
    local seen, normalized = {}, {}
    for index = 1, #records do
        local row = records[index]
        if type(row) ~= "table" or not Integer(row.UnitID) or row.Owner ~= ownerID or seen[row.UnitID] then
            return nil, "UNIT_RECORD_INVALID"
        end
        if row.Type ~= nil and not Text(row.Type) then return nil, "UNIT_TYPE_INVALID" end
        seen[row.UnitID] = true
        normalized[#normalized + 1] = CopyRecord(row)
    end
    table.sort(normalized, function(a, b) return a.UnitID < b.UnitID end)
    return normalized
end

local function CandidateValid(input, vassal)
    local candidate = input.Candidate
    if type(candidate) ~= "table" or candidate.Eligible ~= true
        or candidate.OverlordID ~= nil and candidate.OverlordID ~= input.OverlordID
        or candidate.TargetID ~= nil and candidate.TargetID ~= input.VassalID
        or (candidate.Tier ~= "REGULAR" and candidate.Tier ~= "EXTREME") then
        return false, "CANDIDATE_INVALID"
    end
    if candidate.NeedsPlayerConfirmation ~= vassal.Human then return false, "CONFIRMATION_REQUIRED" end
    if candidate.Tier == "REGULAR" then
        if input.AtWar ~= true or not Integer(input.WarStartTurn) or input.WarStartTurn > input.Turn then
            return false, "WAR_EVIDENCE_UNKNOWN"
        end
        local victory = input.KeyVictory
        if type(victory) ~= "table" or victory.By ~= input.OverlordID
            or victory.Against ~= input.VassalID or not Integer(victory.Turn)
            or victory.Turn < input.WarStartTurn or victory.Turn > input.Turn then
            return false, "KEY_VICTORY_INVALID"
        end
    elseif input.AtWar ~= nil and type(input.AtWar) ~= "boolean" then
        return false, "WAR_STATUS_UNKNOWN"
    end
    return true
end

local function ConsentValid(input, vassal)
    if not vassal.Human then return true end
    local consent = input.Consent
    if type(consent) ~= "table" or consent.State ~= "ACCEPTED" or consent.Token ~= input.TransactionToken
        or not Text(consent.Token) or consent.OverlordID ~= input.OverlordID
        or consent.TargetID ~= input.VassalID or not Integer(consent.ExpiresTurn)
        or consent.ExpiresTurn <= input.Turn then
        return false
    end
    return true
end

local function OperationsForAttach(cities, units, overlordID, vassalID, nativeLifecycle, capitalLast)
    local operations = {}
    if nativeLifecycle == true then
        operations[#operations + 1] = {Kind="PRESERVE_PLAYER", ID=vassalID}
    end
    local ordered = {}
    for _, city in ipairs(cities) do
        if not capitalLast or not city.Capital then ordered[#ordered + 1] = city end
    end
    if capitalLast then
        for _, city in ipairs(cities) do if city.Capital then ordered[#ordered + 1] = city end end
    end
    -- Keeping the source capital until its last city prevents the engine from
    -- moving the Palace into another city whose exact payload is still bound.
    for _, city in ipairs(ordered) do
        operations[#operations + 1] = { Kind = "TRANSFER_CITY", ID = city.CityID,
            From = vassalID, To = overlordID }
    end
    for _, unit in ipairs(units) do
        operations[#operations + 1] = { Kind = "REMOVE_UNIT", ID = unit.UnitID,
            Owner = vassalID }
    end
    operations[#operations + 1] = { Kind = "ARCHIVE_PLAYER", ID = vassalID, Overlord = overlordID }
    return operations
end

function EC_VassalTransaction.BuildAttachPlan(input)
    local valid, reason = ValidateEnvelope(input, "ATTACH")
    if not valid then return nil, reason end
    if not ValidateParty(input.Overlord, input.OverlordID, false)
        or not ValidateParty(input.Vassal, input.VassalID, false) then
        return nil, "PARTY_INVALID"
    end
    if input.Protected ~= false then return nil, "PROTECTION_UNKNOWN" end
    local candidateValid, candidateReason = CandidateValid(input, input.Vassal)
    if not candidateValid then return nil, candidateReason end
    if not ConsentValid(input, input.Vassal) then return nil, "PLAYER_CONFIRMATION_REQUIRED" end
    local cities, capitalID, cityReason = NormalizeCities(input.Cities, input.VassalID, input.Vassal.Cities)
    if cities == nil then return nil, cityReason end
    local units, unitReason = NormalizeUnits(input.Units, input.VassalID)
    if units == nil then return nil, unitReason end
    return {
        SchemaVersion = SCHEMA_VERSION, Action = "ATTACH", Mode = input.Mode,
        ObservationOnly = false, SinglePlayer = true, Turn = input.Turn,
        TransactionToken = input.TransactionToken, Tier = input.Candidate.Tier,
        OverlordID = input.OverlordID, VassalID = input.VassalID,
        VassalHuman = input.Vassal.Human, CapitalCityID = capitalID,
        NativeLifecycle = input.NativeLifecycle,
        QueuePolicy = input.QueuePolicy,
        Cities = cities, Units = units,
        CapitalLast = input.NativeLifecycle == true and true or nil,
        Operations = OperationsForAttach(cities, units, input.OverlordID, input.VassalID, input.NativeLifecycle, input.NativeLifecycle == true),
    }, "READY"
end

local function RestoreAuthorization(input)
    local authorization = input.Authorization
    if type(authorization) ~= "table" or authorization.Authorized ~= true
        or authorization.SchemaVersion ~= AUTONOMY_AUTHORIZATION_SCHEMA_VERSION
        or authorization.Token ~= input.TransactionToken or not Text(authorization.Token)
        or authorization.OverlordID ~= input.OverlordID
        or authorization.VassalID ~= input.VassalID
        or authorization.Turn ~= input.Turn
        or authorization.Human ~= input.Vassal.Human
        or authorization.Confirmed ~= true
        or not Integer(authorization.Autonomy) or authorization.Autonomy > 100
        or not Integer(authorization.AutonomyTarget) or authorization.AutonomyTarget < 1
        or authorization.AutonomyTarget > 100
        or authorization.Autonomy < authorization.AutonomyTarget
        or not Integer(authorization.ArchiveCityCount)
        or authorization.ArchiveCityCount < 1
        or authorization.ArchiveCityCount > MAX_CITIES then
        return false
    end
    return true
end

local function OperationsForRestore(cities, capitalID, overlordID, vassalID, queuePolicy)
    local operations = {}
    for _, city in ipairs(cities) do
        operations[#operations + 1] = { Kind = "RESTORE_CITY", ID = city.CityID,
            From = overlordID, To = vassalID }
    end
    operations[#operations + 1] = { Kind = "SET_CAPITAL", ID = capitalID, Owner = vassalID }
    if queuePolicy=="ARCHIVE_PAUSE" then
        for _,city in ipairs(cities) do
            operations[#operations+1]={Kind="RESTORE_PRODUCTION",ID=city.CityID,Owner=vassalID}
        end
    end
    operations[#operations + 1] = { Kind = "UNARCHIVE_PLAYER", ID = vassalID, Overlord = overlordID }
    return operations
end

function EC_VassalTransaction.BuildRestorePlan(input)
    local valid, reason = ValidateEnvelope(input, "RESTORE")
    if not valid then return nil, reason end
    if not ValidateParty(input.Overlord, input.OverlordID, false)
        or not ValidateParty(input.Vassal, input.VassalID, true) then
        return nil, "PARTY_INVALID"
    end
    if not RestoreAuthorization(input) then return nil, "RESTORE_NOT_AUTHORIZED" end
    local archive = input.Archive
    if type(archive) ~= "table" or archive.SchemaVersion ~= SCHEMA_VERSION
        or archive.State ~= "VASSALIZED" or archive.OverlordID ~= input.OverlordID
        or archive.VassalID ~= input.VassalID or archive.UnitsRemoved ~= true then
        return nil, "ARCHIVE_INVALID"
    end
    local archiveCount = type(archive.Cities) == "table" and #archive.Cities or -1
    local cities, capitalID, cityReason = NormalizeCities(archive.Cities, input.OverlordID, archiveCount)
    if cities == nil then return nil, cityReason end
    if #cities ~= input.Authorization.ArchiveCityCount then
        return nil, "RESTORE_AUTHORIZATION_MISMATCH"
    end
    if archive.CapitalCityID ~= capitalID then return nil, "CAPITAL_MISMATCH" end
    return {
        SchemaVersion = SCHEMA_VERSION, Action = "RESTORE", Mode = input.Mode,
        ObservationOnly = false, SinglePlayer = true, Turn = input.Turn,
        TransactionToken = input.TransactionToken, Tier = "RESTORE",
        OverlordID = input.OverlordID, VassalID = input.VassalID,
        VassalHuman = input.Vassal.Human, CapitalCityID = capitalID,
        NativeLifecycle = input.NativeLifecycle,
        QueuePolicy = input.QueuePolicy,
        Cities = cities, Units = {},
        Operations = OperationsForRestore(cities, capitalID, input.OverlordID, input.VassalID,input.QueuePolicy),
    }, "READY"
end

local function JournalKey(plan, field)
    return JOURNAL_PREFIX .. plan.Action .. "_" .. plan.VassalID .. "_" .. field
end

local function PlanSignature(plan)
    if type(plan) ~= "table" or plan.SchemaVersion ~= SCHEMA_VERSION
        or not ValidateEnvelope(plan, plan.Action) or (plan.Action ~= "ATTACH" and plan.Action ~= "RESTORE")
        or type(plan.VassalHuman) ~= "boolean"
        or (plan.Action == "ATTACH" and plan.Tier ~= "REGULAR" and plan.Tier ~= "EXTREME")
        or (plan.Action == "RESTORE" and plan.Tier ~= "RESTORE") then return nil end
    local owner = plan.Action == "ATTACH" and plan.VassalID or plan.OverlordID
    local cities, capital = NormalizeCities(plan.Cities, owner, type(plan.Cities) == "table" and #plan.Cities or -1)
    local units = NormalizeUnits(plan.Units, plan.VassalID)
    if cities == nil or units == nil or capital ~= plan.CapitalCityID
        or (plan.Action == "RESTORE" and #units ~= 0) then return nil end
    if plan.NativeLifecycle ~= nil and type(plan.NativeLifecycle) ~= "boolean" then return nil end
    if plan.CapitalLast ~= nil and (plan.CapitalLast ~= true or plan.NativeLifecycle ~= true or plan.Action ~= "ATTACH") then return nil end
    if plan.QueuePolicy~=nil and plan.QueuePolicy~="ARCHIVE_PAUSE" then return nil end
    local expected = plan.Action == "ATTACH" and OperationsForAttach(cities, units, plan.OverlordID, plan.VassalID, plan.NativeLifecycle, plan.CapitalLast)
        or OperationsForRestore(cities, capital, plan.OverlordID, plan.VassalID,plan.QueuePolicy)
    if not DenseList(plan.Operations, MAX_CITIES*2 + MAX_UNITS + 3, #expected)
        or #plan.Operations ~= #expected then return nil end
    for index, operation in ipairs(expected) do
        local actual = plan.Operations[index]
        if type(actual) ~= "table" then return nil end
        for key, value in pairs(operation) do if actual[key] ~= value then return nil end end
        for key in pairs(actual) do if operation[key] == nil then return nil end end
    end
    -- Length-prefixed scalars bind a resumed journal to the complete plan.
    local parts = {}
    local function Add(value)
        local text = tostring(value)
        parts[#parts + 1] = type(value) .. ":" .. #text .. ":" .. text
    end
    for _, key in ipairs({ "Action", "Turn", "TransactionToken", "Tier", "OverlordID", "VassalID", "VassalHuman", "CapitalCityID" }) do Add(plan[key]) end
    if plan.NativeLifecycle ~= nil then Add(plan.NativeLifecycle) end
    if plan.CapitalLast ~= nil then Add("CAPITAL_LAST"); Add(plan.CapitalLast) end
    if plan.QueuePolicy~=nil then Add(plan.QueuePolicy) end
    for _, city in ipairs(cities) do
        for _, key in ipairs({ "CityID", "Owner", "X", "Y", "Capital", "OriginalOwner", "Population" }) do Add(city[key]) end
        if city.Payload ~= nil then
            if EC_CityPayload == nil then return nil end
            local payload, valid = Safe(function() return EC_CityPayload.Encode(EC_CityPayload.Copy(city.Payload)) end)
            if not valid then return nil end
            Add(city.NativeID)
            Add(payload)
        end
        if city.Construction~=nil then
            local construction,readable=Safe(function() return EC_CityPayload.Encode(EC_CityPayload.Copy(city.Construction)) end)
            if not readable then return nil end
            Add(construction)
        end
            if plan.QueuePolicy=="ARCHIVE_PAUSE" then
                local production, readable=Safe(function()
                    assert(type(city.ProductionArchive)=="table" and city.ProductionArchive.Schema==1
                        and city.ProductionArchive.Owner==plan.VassalID)
                    return EC_CityPayload.Encode(EC_CityPayload.Copy(city.ProductionArchive))
                end)
                if not readable then return nil end
                Add(production)
            end
    end
    Add("UNITS")
    for _, unit in ipairs(units) do
        for _, key in ipairs({ "UnitID", "Owner", "Type" }) do Add(unit[key]) end
    end
    return table.concat(parts, "|")
end

local function JournalRead(journal, key)
    if type(journal) ~= "table" then return nil, false end
    return Safe(function()
        local reader = journal.Read
        if type(reader) == "function" then return reader(journal, key) end
        if reader ~= nil then error("Journal reader is not callable") end
        return journal[key]
    end)
end

local function JournalWrite(journal, key, value)
    if type(journal) ~= "table" then return false end
    local result, ok = Safe(function()
        local writer = journal.Write
        if type(writer) == "function" then return writer(journal, key, value) end
        if writer ~= nil then error("Journal writer is not callable") end
        journal[key] = value
        return true
    end)
    return ok and result ~= false
end

local function ReadHeader(plan, journal, signature)
    local fields = { "SCHEMA_VERSION", "ACTION", "TOKEN", "OVERLORD_ID", "VASSAL_ID",
        "PLAN_SIGNATURE", "STATE", "NEXT_INDEX", "CURRENT_INDEX", "CURRENT_KIND" }
    local values = {}
    for _, field in ipairs(fields) do
        local value, readable = JournalRead(journal, JournalKey(plan, field))
        if not readable then return nil, "JOURNAL_READ_FAILED" end
        values[field] = value
    end
    if values.STATE == nil then
        for _, field in ipairs(fields) do
            if field ~= "STATE" and values[field] ~= nil then return nil, "JOURNAL_CORRUPT" end
        end
        return nil, "EMPTY"
    end
    if values.SCHEMA_VERSION ~= SCHEMA_VERSION or values.ACTION ~= plan.Action
        or values.TOKEN ~= plan.TransactionToken or values.OVERLORD_ID ~= plan.OverlordID
        or values.PLAN_SIGNATURE ~= signature
        or values.VASSAL_ID ~= plan.VassalID or not Integer(values.NEXT_INDEX)
        or values.NEXT_INDEX < 1 or values.NEXT_INDEX > #plan.Operations + 1
        or (values.CURRENT_INDEX ~= nil and (not Integer(values.CURRENT_INDEX)
            or values.CURRENT_INDEX > #plan.Operations
            or (values.CURRENT_INDEX == 0 and values.CURRENT_KIND ~= "DONE")
            or values.CURRENT_INDEX > 0 and values.CURRENT_KIND == "DONE")) then
        return nil, "JOURNAL_CONFLICT"
    end
    if values.STATE ~= "ATTACHING" and values.STATE ~= "RESTORING"
        and values.STATE ~= "VASSALIZED" and values.STATE ~= "INDEPENDENT"
        and values.STATE ~= "UNKNOWN" and values.STATE ~= "WAITING" then
        return nil, "JOURNAL_CORRUPT"
    end
    if (values.STATE == "VASSALIZED" or values.STATE == "INDEPENDENT")
        and (values.NEXT_INDEX ~= #plan.Operations + 1
            or values.CURRENT_INDEX ~= 0 or values.CURRENT_KIND ~= "DONE") then
        return nil, "JOURNAL_CONFLICT"
    end
    if values.STATE=="WAITING" and (plan.Action~="RESTORE" or values.CURRENT_INDEX~=values.NEXT_INDEX
        or values.CURRENT_KIND~="RESTORE_PRODUCTION" or not plan.Operations[values.NEXT_INDEX]
        or plan.Operations[values.NEXT_INDEX].Kind~="RESTORE_PRODUCTION") then
        return nil,"JOURNAL_CONFLICT"
    end
    return values, "OK"
end

local function MarkUnknown(plan, journal, reason)
    JournalWrite(journal, JournalKey(plan, "UNKNOWN_REASON"), reason)
    JournalWrite(journal, JournalKey(plan, "STATE"), "UNKNOWN")
end

local function Initialize(plan, journal, signature)
    local state = plan.Action == "ATTACH" and "ATTACHING" or "RESTORING"
    local values = {
        { "SCHEMA_VERSION", SCHEMA_VERSION }, { "ACTION", plan.Action },
        { "TOKEN", plan.TransactionToken }, { "OVERLORD_ID", plan.OverlordID },
        { "VASSAL_ID", plan.VassalID }, { "NEXT_INDEX", 1 },
        { "PLAN_SIGNATURE", signature },
        { "CURRENT_INDEX", nil }, { "CURRENT_KIND", nil },
    }
    for _, item in ipairs(values) do
        if item[2] ~= nil and not JournalWrite(journal, JournalKey(plan, item[1]), item[2]) then
            return false, "JOURNAL_WRITE_FAILED"
        end
    end
    if not JournalWrite(journal, JournalKey(plan, "STATE"), state) then
        return false, "JOURNAL_WRITE_FAILED"
    end
    return true
end

local function Call(adapter, method, ...)
    if type(adapter) ~= "table" then return nil, false end
    local member, readable = Safe(function() return adapter[method] end)
    if not readable or type(member) ~= "function" then return nil, false end
    local arguments = { ... }
    local result, ok, second = Safe(function()
        return member(adapter, Unpack(arguments))
    end)
    if not ok then return nil, false end
    return result, true, second
end

local function VerifyCity(adapter, city, ownerID, queuePolicy, action, originalOwner)
    -- City IDs alone can collide between players. Require the physical city
    -- and preserved scalar payload, not merely an ownership number.
    local row, ok, known = Call(adapter, "GetCityRecord", city.CityID, ownerID, city.X, city.Y)
    if not ok or known ~= true or type(row) ~= "table" then return false end
    for _, key in ipairs({ "CityID", "X", "Y", "Population", "OriginalOwner" }) do
        if city[key] ~= nil and row[key] ~= city[key] then return false end
    end
    if city.Payload ~= nil then
        if EC_CityPayload == nil or row.Payload == nil then return false end
        if ownerID==city.Owner then
            -- A newly captured plan binds the exact live city before any
            -- transfer. Natural changes during attachment are captured by
            -- BuildRestorePlan; they do not weaken this precondition.
            if not EC_CityPayload.Equal(city.Payload,row.Payload) then return false end
        end
        -- The city remains playable while attached: population, extra
        -- districts/buildings, followers and production can advance under the
        -- overlord. Verify the immutable captured subset and let the adapter
        -- restore any missing original district/building before this check.
        if city.Payload.Name ~= row.Payload.Name
            or not EC_CityPayload.Equal(city.Payload.Properties, row.Payload.Properties) then return false end
        local actualDistricts={}
        local function districtKey(value) return value.Type..":"..value.X..":"..value.Y end
        for _, value in ipairs(row.Payload.Districts or {}) do actualDistricts[districtKey(value)]=value end
        for _, expected in ipairs(city.Payload.Districts or {}) do
            local actual=actualDistricts[districtKey(expected)]
            if actual==nil or actual.X~=expected.X or actual.Y~=expected.Y
                or (expected.Complete and not actual.Complete) then return false end
        end
        local actualBuildings={}
        for _, value in ipairs(row.Payload.Buildings or {}) do actualBuildings[value.Type]=value end
        for _, expected in ipairs(city.Payload.Buildings or {}) do
            if expected.Type~="BUILDING_PALACE" then
                local actual=actualBuildings[expected.Type]
                if actual==nil or actual.Location~=expected.Location then return false end
            end
        end
        local actualPlots={}
        for _, value in ipairs(row.Payload.Plots or {}) do actualPlots[value.Index]=value end
        for _, expected in ipairs(city.Payload.Plots or {}) do
            local actual=actualPlots[expected.Index]
            if actual==nil or actual.Terrain~=expected.Terrain or actual.Feature~=expected.Feature
                or actual.Resource~=expected.Resource or actual.Improvement~=expected.Improvement
                or actual.Route~=expected.Route
                or (expected.District~=-1 and actual.District~=expected.District) then return false end
        end
        local expectedReligion=city.Payload.Religion or {}
        local actualReligion=row.Payload.Religion or {}
        if expectedReligion.Majority~=nil and expectedReligion.Majority~=-1
            and expectedReligion.Majority~=actualReligion.Majority then return false end
        for religion,count in pairs(expectedReligion.Followers or {}) do
            if count~=0 and (actualReligion.Followers or {})[religion]~=count then return false end
        end
    end
    return row.Owner == ownerID
end

local function AdapterComplete(adapter, action, nativeLifecycle, queuePolicy)
    local methods = { "GetCityRecord", "GetParty" }
    local specific = action == "ATTACH" and { "TransferCity", "RemoveUnit", "GetUnitOwner", "ArchivePlayer" }
        or { "RestoreCity", "SetCapital", "GetCapital", "UnarchivePlayer" }
    for _, method in ipairs(specific) do methods[#methods + 1] = method end
    if action == "ATTACH" and nativeLifecycle == true then
        methods[#methods + 1] = "PreservePlayer"
        methods[#methods + 1] = "IsPreserved"
    end
    if action=="RESTORE" and queuePolicy=="ARCHIVE_PAUSE" then methods[#methods+1]="RestoreProduction" end
    for _, method in ipairs(methods) do
        local ok, value = pcall(function() return adapter[method] end)
        if not ok or type(value) ~= "function" then return false end
    end
    return true
end

local function VerifyUnit(adapter, unitID, ownerID)
    local owner, ok, known = Call(adapter, "GetUnitOwner", unitID, ownerID)
    return ok and known == true and owner == ownerID
end

local function VerifyRemovedUnit(adapter, unitID, ownerID)
    local owner, ok, known = Call(adapter, "GetUnitOwner", unitID, ownerID)
    return ok and known == true and owner == nil
end

local function VerifyParty(adapter, playerID, archived, cityCount, overlordID)
    local row, ok = Call(adapter, "GetParty", playerID)
    if not ok or type(row) ~= "table" then return false end
    return row.ID == playerID and row.Alive == true and row.Major == true
        and row.Archived == archived and row.Independent == (not archived)
        and row.Cities == cityCount and (not archived or row.OverlordID == overlordID)
end

local function VerifyInitialParties(plan, adapter)
    local overlord, overlordOK = Call(adapter, "GetParty", plan.OverlordID)
    local vassal, vassalOK = Call(adapter, "GetParty", plan.VassalID)
    local archived = plan.Action == "RESTORE"
    return overlordOK and vassalOK
        and ValidateParty(overlord, plan.OverlordID, false)
        and ValidateParty(vassal, plan.VassalID, archived)
        and vassal.Human == plan.VassalHuman
        and vassal.Cities == (archived and 0 or #plan.Cities)
        and (not archived or vassal.OverlordID == plan.OverlordID)
end

local function RunOperation(plan, adapter, operation)
    local city
    if operation.Kind == "TRANSFER_CITY" or operation.Kind == "RESTORE_CITY" then
        for _, record in ipairs(plan.Cities) do
            if record.CityID == operation.ID then city = record; break end
        end
        if city == nil or not VerifyCity(adapter, city, operation.From, plan.QueuePolicy, plan.Action,plan.VassalID) then return false end
    end
    if operation.Kind == "PRESERVE_PLAYER" then
        local result, ok = Call(adapter, "PreservePlayer", operation.ID)
        local preserved, known = Call(adapter, "IsPreserved", operation.ID)
        return ok and result == true and known and preserved == true
    elseif operation.Kind == "TRANSFER_CITY" then
        local result, ok = Call(adapter, "TransferCity", operation.ID, operation.From, operation.To)
        return ok and result == true and VerifyCity(adapter, city, operation.To,plan.QueuePolicy,plan.Action,plan.VassalID)
    elseif operation.Kind == "REMOVE_UNIT" then
        if not VerifyUnit(adapter, operation.ID, operation.Owner) then return false end
        local result, ok = Call(adapter, "RemoveUnit", operation.ID, operation.Owner)
        return ok and result == true and VerifyRemovedUnit(adapter, operation.ID, operation.Owner)
    elseif operation.Kind == "ARCHIVE_PLAYER" then
        local result, ok = Call(adapter, "ArchivePlayer", operation.ID, operation.Overlord)
        return ok and result == true and VerifyParty(adapter, operation.ID, true, 0, operation.Overlord)
    elseif operation.Kind == "RESTORE_CITY" then
        local result, ok = Call(adapter, "RestoreCity", operation.ID, operation.From, operation.To)
        return ok and result == true and VerifyCity(adapter, city, operation.To,plan.QueuePolicy,plan.Action,plan.VassalID)
    elseif operation.Kind == "SET_CAPITAL" then
        local result, ok = Call(adapter, "SetCapital", operation.Owner, operation.ID)
        if not ok or result ~= true then return false end
        local capital, capitalOK, known = Call(adapter, "GetCapital", operation.Owner)
        return capitalOK and known == true and capital == operation.ID
    elseif operation.Kind=="RESTORE_PRODUCTION" then
        local result,ok=Call(adapter,"RestoreProduction",operation.ID,operation.Owner)
        if ok and result=="PENDING" then return "PENDING" end
        return ok and result==true
    elseif operation.Kind == "UNARCHIVE_PLAYER" then
        local result, ok = Call(adapter, "UnarchivePlayer", operation.ID, operation.Overlord)
        return ok and result == true and VerifyParty(adapter, operation.ID, false, #plan.Cities, operation.Overlord)
    end
    return false
end

function EC_VassalTransaction.Apply(plan, adapter, journal)
    local signature = PlanSignature(plan)
    if signature == nil then return false, "PLAN_INVALID" end
    if type(adapter) ~= "table" or type(journal) ~= "table" then return false, "ADAPTER_INVALID" end
    local header, reason = ReadHeader(plan, journal, signature)
    if header == nil and reason == "EMPTY" then
        if not AdapterComplete(adapter, plan.Action, plan.NativeLifecycle,plan.QueuePolicy) then return false, "ADAPTER_INCOMPLETE" end
        if not VerifyInitialParties(plan, adapter) then return false, "PARTY_PRECONDITION_FAILED" end
        -- Validate the entire city set before the first engine mutation.
        for _, city in ipairs(plan.Cities) do
            if not VerifyCity(adapter, city, city.Owner,plan.QueuePolicy,plan.Action,plan.VassalID) then return false, "CITY_PRECONDITION_FAILED" end
        end
        for _, unit in ipairs(plan.Units) do
            if not VerifyUnit(adapter, unit.UnitID, unit.Owner) then return false, "UNIT_PRECONDITION_FAILED" end
        end
        local initialized, initializeReason = Initialize(plan, journal, signature)
        if not initialized then return false, initializeReason end
        header, reason = ReadHeader(plan, journal, signature)
        if header == nil then return false, reason end
    elseif header == nil then
        return false, reason
    end
    local complete = plan.Action == "ATTACH" and "VASSALIZED" or "INDEPENDENT"
    if header.STATE == "UNKNOWN" then return false, "OUTCOME_UNKNOWN" end
    if header.CURRENT_INDEX ~= nil and header.CURRENT_INDEX > 0
        and header.CURRENT_INDEX >= header.NEXT_INDEX then
        if header.STATE~="WAITING" or header.CURRENT_KIND~="RESTORE_PRODUCTION"
            or header.CURRENT_INDEX~=header.NEXT_INDEX then return false,"OUTCOME_UNKNOWN" end
    end
    if header.STATE == complete then return true, "ALREADY_APPLIED" end
    if not AdapterComplete(adapter, plan.Action, plan.NativeLifecycle,plan.QueuePolicy) then return false, "ADAPTER_INCOMPLETE" end
    local expectedState = plan.Action == "ATTACH" and "ATTACHING" or "RESTORING"
    if header.STATE~=expectedState and not (header.STATE=="WAITING" and plan.Action=="RESTORE") then return false,"JOURNAL_CONFLICT" end
    for index = header.NEXT_INDEX, #plan.Operations do
        local operation = plan.Operations[index]
        if type(operation) ~= "table" or not Text(operation.Kind) or not Integer(operation.ID) then
            MarkUnknown(plan, journal, "OPERATION_INVALID")
            return false, "PLAN_INVALID"
        end
        if not JournalWrite(journal, JournalKey(plan, "CURRENT_INDEX"), index)
            or not JournalWrite(journal, JournalKey(plan, "CURRENT_KIND"), operation.Kind) then
            MarkUnknown(plan, journal, "JOURNAL_WRITE_FAILED")
            return false, "JOURNAL_WRITE_FAILED"
        end
        local result=RunOperation(plan, adapter, operation)
        if result=="PENDING" then
            if not JournalWrite(journal,JournalKey(plan,"STATE"),"WAITING") then
                MarkUnknown(plan,journal,"JOURNAL_WRITE_FAILED")
                return false,"JOURNAL_WRITE_FAILED"
            end
            return false,"PRODUCTION_PENDING"
        end
        if not result then
            MarkUnknown(plan, journal, "OPERATION_OUTCOME_UNKNOWN")
            return false, "OUTCOME_UNKNOWN"
        end
        if not JournalWrite(journal, JournalKey(plan, "NEXT_INDEX"), index + 1) then
            MarkUnknown(plan, journal, "JOURNAL_WRITE_FAILED")
            return false, "JOURNAL_WRITE_FAILED"
        end
    end
    if not JournalWrite(journal, JournalKey(plan, "CURRENT_INDEX"), 0)
        or not JournalWrite(journal, JournalKey(plan, "CURRENT_KIND"), "DONE")
        or not JournalWrite(journal, JournalKey(plan, "STATE"), complete) then
        MarkUnknown(plan, journal, "JOURNAL_WRITE_FAILED")
        return false, "JOURNAL_WRITE_FAILED"
    end
    return true, "COMMITTED"
end

EC_VassalTransaction.SchemaVersion = SCHEMA_VERSION
EC_VassalTransaction.Limits = { Players = MAX_PLAYERS, Cities = MAX_CITIES, Units = MAX_UNITS }
