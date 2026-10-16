-- Deterministic autonomy-to-restoration policy.
-- It produces an authorization DTO for EC_VassalTransaction and does not
-- inspect or mutate native Civ VI objects.
EC_AutonomyPolicy = {}

local MAX_PLAYERS = 64
local AUTHORIZATION_SCHEMA_VERSION = 1

local function PlayerID(value)
    return type(value) == "number" and value >= 0 and value < MAX_PLAYERS
        and value == math.floor(value)
end

local function Integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge
        and value == math.floor(value)
end

local function Block(reason)
    return { Eligible = false, Reason = reason, NextAction = "WAIT" }
end

function EC_AutonomyPolicy.Evaluate(input)
    if type(input) ~= "table" then return Block("INPUT_UNKNOWN") end
    if not PlayerID(input.OverlordID) or not PlayerID(input.VassalID)
        or input.OverlordID == input.VassalID then
        return Block("IDENTITY_UNKNOWN")
    end
    if not Integer(input.Turn) or not Integer(input.Autonomy)
        or not Integer(input.AutonomyTarget) or input.Autonomy > 100
        or input.AutonomyTarget < 1 or input.AutonomyTarget > 100 then
        return Block("AUTONOMY_UNKNOWN")
    end
    if input.VassalAlive ~= true or input.VassalMajor ~= true
        or input.VassalArchived ~= true then
        return Block("VASSAL_STATE_INVALID")
    end
    if input.OverlordAlive ~= true or input.OverlordMajor ~= true then
        return Block("OVERLORD_STATE_INVALID")
    end
    if input.ArchiveState ~= "VASSALIZED" or input.ArchiveComplete ~= true
        or input.UnitsRemoved ~= true then
        return Block("ARCHIVE_INCOMPLETE")
    end
    if not Integer(input.ArchiveCityCount) or input.ArchiveCityCount < 1
        or input.ArchiveCityCount > 64 then
        return Block("ARCHIVE_CITIES_UNKNOWN")
    end
    if type(input.Human) ~= "boolean" then return Block("HUMAN_IDENTITY_UNKNOWN") end
    if type(input.ProjectPending) ~= "boolean" then return Block("PROJECT_STATE_UNKNOWN") end
    if input.ProjectPending == true then return Block("PROJECT_PENDING") end
    if input.Autonomy < input.AutonomyTarget then
        return Block("AUTONOMY_BELOW_TARGET")
    end
    if type(input.TransactionToken) ~= "string" or input.TransactionToken == ""
        or #input.TransactionToken > 160 then
        return Block("TRANSACTION_TOKEN_UNKNOWN")
    end
    if input.Human == true and input.Confirmed ~= true then
        return { Eligible = false, Reason = "PLAYER_CONFIRMATION_REQUIRED",
            NextAction = "REQUEST_PLAYER_CONFIRMATION" }
    end
    return {
        Eligible = true, Reason = "AUTONOMY_REACHED", NextAction = "BUILD_RESTORE_PLAN",
        Authorization = {
            Authorized = true,
            SchemaVersion = AUTHORIZATION_SCHEMA_VERSION,
            Token = input.TransactionToken,
            OverlordID = input.OverlordID,
            VassalID = input.VassalID,
            Turn = input.Turn,
            Autonomy = input.Autonomy,
            AutonomyTarget = input.AutonomyTarget,
            ArchiveCityCount = input.ArchiveCityCount,
            Human = input.Human,
            Confirmed = input.Human ~= true or input.Confirmed == true,
        },
    }
end

EC_AutonomyPolicy.Limits = {
    Players = MAX_PLAYERS, Autonomy = 100, AuthorizationSchema = AUTHORIZATION_SCHEMA_VERSION,
}
