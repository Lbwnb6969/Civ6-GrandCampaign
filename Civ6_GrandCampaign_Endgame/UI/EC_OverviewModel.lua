-- Read-only view of existing archives. No operation or Property writes belong here.
EC_OverviewModel = {}
local snapshotsLoaded = pcall(function()
    include("EC_Eligibility")
    include("EC_DataStore")
end)
local archiveLoaded=pcall(function()
    include("EC_CityPayload")
    include("EC_NativeVassals")
    include("EC_AIProductionCredit")
    include("EC_HumanProductionRefund")
end)

local function True(v) return v == true or v == 1 or v == "1" or v == "true" end
local function False(v) return v == false or v == 0 or v == "0" or v == "false" end
local function Integer(v)
    return type(v) == "number" and v >= 0 and v < math.huge and v == math.floor(v)
end
local function Slot(v) return Integer(v) and v < 64 end
local function Read(callback)
    local ok, value = pcall(callback)
    if ok then return value, true end
    return nil, false
end
local function Config(key) return Read(function() return GameConfiguration.GetValue(key) end) end
local function Property(player, key) return Read(function() return player:GetProperty(key) end) end
local function Localized(key, fallback)
    local ok, value = pcall(function() return Locale.Lookup(key) end)
    if not ok or type(value) ~= "string" or value == ""
        or (type(key) == "string" and string.match(key, "^LOC_") ~= nil and value == key)
        or string.find(value, "TRANSLATION MISSING", 1, true) ~= nil
        or string.match(value, "^LOC_[A-Z0-9_]+$") ~= nil then
        return fallback
    end
    return value
end
local reasonLabels = {
    DATA_UNKNOWN = { "LOC_EC_OVERVIEW_REASON_DATA", "等待完整统计数据" },
    SNAPSHOT_STALE = { "LOC_EC_OVERVIEW_REASON_DATA", "等待完整统计数据" },
    ADVANTAGE_PENDING = { "LOC_EC_OVERVIEW_REASON_HOLD", "等待持续优势确认" },
    ADVANTAGE_UNVERIFIED = { "LOC_EC_OVERVIEW_REASON_HOLD", "等待持续优势确认" },
    KEY_VICTORY_REQUIRED = { "LOC_EC_OVERVIEW_REASON_WAR", "等待战争及关键胜利证据" },
    WAR_UNKNOWN = { "LOC_EC_OVERVIEW_REASON_WAR", "等待战争及关键胜利证据" },
    PROTECTED = { "LOC_EC_OVERVIEW_REASON_PROTECTED", "该文明受到保护" },
    PROTECTION_UNKNOWN = { "LOC_EC_OVERVIEW_REASON_PROTECTION_UNKNOWN", "保护状态暂不可用" },
    RESEARCH_PROGRESS_BEHIND = { "LOC_EC_OVERVIEW_REASON_RESEARCH", "科技或市政进度不足" },
    BELOW_THRESHOLDS = { "LOC_EC_OVERVIEW_REASON_THRESHOLDS", "实力优势未达到要求" },
    NO_QUALIFIED_OVERLORD = { "LOC_EC_OVERVIEW_REASON_NO_OVERLORD", "暂无符合条件的宗主" },
    AI_CANDIDATE = { "LOC_EC_OVERVIEW_REASON_READY", "资格条件已满足，等待真实玩法接通" },
    PLAYER_CONFIRMATION_REQUIRED = { "LOC_EC_OVERVIEW_REASON_CONSENT", "需要玩家明确同意" },
}

function EC_OverviewModel.Build()
    local view = { Supported = false, Entries = {}, Mode = "LOC_EC_OVERVIEW_UNKNOWN",
        Metrics = "LOC_EC_OVERVIEW_UNKNOWN", MetricData = "LOC_EC_OVERVIEW_UNKNOWN",
        Awakening = "LOC_EC_OVERVIEW_UNKNOWN",
        AttachAvailable = false, RestoreAvailable = false,
        OperationReason = "LOC_EC_OVERVIEW_NATIVE_PENDING" }
    local localID = Read(function() return Game.GetLocalPlayer() end)
    local localPlayer = Slot(localID) and Players[localID] or nil
    if localPlayer == nil or Read(function() return localPlayer:IsHuman() end) ~= true
        or Read(function() return localPlayer:IsAlive() end) ~= true
        or Read(function() return GameConfiguration.IsAnyMultiplayer() end) ~= false then return view end
    view.Supported = true
    local nativeMode=False(Config("EC_OBSERVATION_ONLY")) and True(Config("EC_NATIVE_VASSAL_TEST"))
    if nativeMode then view.OperationReason="LOC_EC_NATIVE_OPERATION_NOTICE" end
    local observation = Config("EC_OBSERVATION_ONLY")
    if True(observation) then view.Mode = "LOC_EC_OVERVIEW_OBSERVATION"
    elseif False(observation) then view.Mode = "LOC_EC_OVERVIEW_EXPERIMENT" end
    local metrics = Config("EC_METRIC_BRIDGE_TEST")
    if True(metrics) then view.Metrics = "LOC_EC_OVERVIEW_ENABLED"
    elseif False(metrics) then view.Metrics = "LOC_EC_OVERVIEW_DISABLED" end
    if False(metrics) then view.MetricData = "LOC_EC_OVERVIEW_DISABLED"
    elseif True(metrics) and snapshotsLoaded and type(EC_DataStore) == "table" then
        local turn = Read(function() return Game.GetCurrentGameTurn() end)
        local ok, record, reason = pcall(function()
            return EC_DataStore.ReadSnapshot(localPlayer, turn, 5)
        end)
        if ok and Integer(turn) and record ~= nil and record.AuthorID == localID
            and record.Human == true and record.Alive == true and record.Major == true then
            view.MetricData = "LOC_EC_OVERVIEW_METRICS_FRESH"
        elseif ok and Integer(turn) and reason == "EMPTY" then
            view.MetricData = "LOC_EC_OVERVIEW_METRICS_WAITING"
        elseif ok and Integer(turn) and reason == "STALE" then
            view.MetricData = "LOC_EC_OVERVIEW_METRICS_STALE"
        end
    end

    local function Known(id)
        return Slot(id) and (id == localID or Read(function()
            return localPlayer:GetDiplomacy():HasMet(id)
        end) == true)
    end
    local function Name(id)
        if not Known(id) then return Localized("LOC_EC_OVERVIEW_UNMET", "尚未接触的文明") end
        local key = Read(function() return PlayerConfigurations[id]:GetCivilizationShortDescription() end)
        if type(key) ~= "string" or key == "" then return "暂不可用" end
        return Localized(key, "暂不可用")
    end

    local enabled, dry = Config("EC_AWAKENING_ENABLED"), Config("EC_AWAKENING_DRY_RUN")
    if False(enabled) and False(dry) then view.Awakening = "LOC_EC_OVERVIEW_DISABLED"
    elseif True(observation) and (True(enabled) or True(dry)) then
        view.Awakening = "LOC_EC_OVERVIEW_TRIGGER_ONLY"
    elseif False(observation) and (True(enabled) or True(dry)) then
        -- The local human may occupy any player slot; state belongs to that
        -- player rather than the hard-coded slot 0.
        local owner = localPlayer
        local stage, stageReadable = Property(owner, "EC_AWAKENING_STATE")
        local stages = { LOCKED = "LOC_EC_OVERVIEW_LOCKED", TRIGGERED = "LOC_EC_OVERVIEW_TRIGGERED",
            PREPARATION = "LOC_EC_OVERVIEW_PREPARATION", CONQUEST = "LOC_EC_OVERVIEW_CONQUEST",
            SHOWDOWN = "LOC_EC_OVERVIEW_SHOWDOWN", RESOLVED = "LOC_EC_OVERVIEW_RESOLVED" }
        local schema, schemaReadable = Property(owner, "EC_AWAKENING_SCHEMA_VERSION")
        local mode, modeReadable = Property(owner, "EC_AWAKENING_MODE")
        local ready, readyReadable = Property(owner, "EC_AWAKENING_PAYLOAD_READY")
        local live = True(enabled) and True(Config("EC_AWAKENING_ACTIONS_TEST")) and False(dry)
        local expected = live and "LIVE_TEST" or "DRY_RUN"
        if stageReadable and schemaReadable and modeReadable and readyReadable
            and stage == nil and schema == nil and mode == nil and ready == nil then
            -- No persisted record does not establish why gameplay has not triggered.
            view.Awakening = "LOC_EC_OVERVIEW_NOT_TRIGGERED"
            if localID ~= 0 and Players[0] ~= nil then
                for _, key in ipairs({ "EC_AWAKENING_STATE", "EC_AWAKENING_SCHEMA_VERSION",
                    "EC_AWAKENING_MODE", "EC_AWAKENING_PAYLOAD_READY", "EC_AWAKENING_CIV" }) do
                    local value, readable = Property(Players[0], key)
                    if not readable or value ~= nil then
                        view.Awakening = "LOC_EC_OVERVIEW_LEGACY_OWNER"
                        break
                    end
                end
            end
        elseif schema == 1 and mode == expected and stages[stage] ~= nil
            and (stage == "LOCKED" or ready == 1) then
            view.Awakening = stages[stage]
            if ready == 1 and (stage == "TRIGGERED" or stage == "PREPARATION" or stage == "CONQUEST") then
                local candidate = Property(owner, "EC_AWAKENING_CIV")
                local trigger = Property(owner, "EC_AWAKENING_TRIGGER_TURN")
                local prepEnd = Property(owner, "EC_AWAKENING_PREP_END_TURN")
                local conquestEnd = Property(owner, "EC_AWAKENING_CONQUEST_END_TURN")
                local turn = Read(function() return Game.GetCurrentGameTurn() end)
                if Slot(candidate) and candidate ~= localID and Integer(turn)
                    and Integer(trigger) and trigger <= turn and Integer(prepEnd) and prepEnd > trigger
                    and Integer(conquestEnd) and conquestEnd > prepEnd then
                    local due = stage == "CONQUEST" and conquestEnd or prepEnd
                    view.AwakeningTimer = { Name = Name(candidate), Due = due,
                        Remaining = math.max(0, due - turn),
                        Stage = stage == "CONQUEST" and stages.SHOWDOWN or stages.CONQUEST }
                end
            end
        end
    end

    local projects = { SUPPORT_OVERLORD = "LOC_EC_OVERVIEW_SUPPORT", WEAKEN_OVERLORD = "LOC_EC_OVERVIEW_WEAKEN" }
    local focuses = { MILITARY = "LOC_EC_OVERVIEW_MILITARY", ECONOMY = "LOC_EC_OVERVIEW_ECONOMY",
        SCIENCE = "LOC_EC_OVERVIEW_SCIENCE", CULTURE = "LOC_EC_OVERVIEW_CULTURE", GENERAL = "LOC_EC_OVERVIEW_GENERAL" }
    local function ReadAdvantage(player, id)
        local schema = Property(player, "EC_ADVANTAGE_SCHEMA")
        local bank = Property(player, "EC_ADVANTAGE_ACTIVE_BANK")
        if schema == nil and bank == nil then return nil end
        if schema ~= 1 or (bank ~= 1 and bank ~= 2) then
            return { Valid = false }
        end
        local prefix = "EC_ADVANTAGE_BANK" .. bank .. "_"
        local ready = Property(player, prefix .. "READY")
        local state = Property(player, prefix .. "State")
        local reason = Property(player, prefix .. "Reason")
        local turn = Property(player, prefix .. "Turn")
        local target = Property(player, prefix .. "TargetID")
        local tier = Property(player, prefix .. "Tier")
        local samples = Property(player, prefix .. "Samples")
        local lastSample = Property(player, prefix .. "LastSampleTurn")
        if ready ~= 1 or target ~= id or (state ~= "ACTIVE" and state ~= "INVALIDATED")
            or type(reason) ~= "string" or not string.match(reason, "^[A-Z_]+$")
            or not Integer(turn) then
            return { Valid = false }
        end
        if lastSample ~= nil and not Integer(lastSample) then return { Valid = false } end
        if samples ~= nil and not Integer(samples) then return { Valid = false } end
        return { Valid = true, State = state, Reason = reason, Turn = turn,
            Tier = tier, Samples = samples, LastSampleTurn = lastSample,
            OverlordID=Property(player,prefix.."OverlordID") }
    end
    for id = 0, 63 do
        local player = Players[id]
        if player ~= nil and Known(id) and Read(function() return player:IsMajor() end) == true then
            local prefix = "EC_VASSAL_" .. id .. "_"
            local state, readable = Property(player, prefix .. "STATE")
            if not readable or (state ~= nil and state ~= "INDEPENDENT") then
                local entry = { Name = Name(id), TargetID=id,Status = "LOC_EC_OVERVIEW_ARCHIVE_UNKNOWN" }
                if (state == "SHADOW_ARCHIVED" or state=="VASSALIZED") and Property(player, prefix .. "SCHEMA_VERSION") == 1 then
                    entry.Status = state=="VASSALIZED" and "LOC_EC_NATIVE_VASSAL" or "LOC_EC_OVERVIEW_SHADOW"
                    local overlord = Property(player, prefix .. "OVERLORD")
                    if Slot(overlord) and overlord ~= id then entry.Overlord = Name(overlord) end
                    local autonomy = Property(player, prefix .. "AUTONOMY")
                    if Integer(autonomy) and autonomy <= 100 then entry.Autonomy = autonomy end
                    entry.Project = projects[Property(player, prefix .. "PROJECT")]
                    entry.Focus = focuses[Property(player, prefix .. "PROJECT_FOCUS")]
                    local start, due = Property(player, prefix .. "PROJECT_START_TURN"), Property(player, prefix .. "PROJECT_END_TURN")
                    if Integer(start) and Integer(due) and due > start then entry.Due = due end
                    if state=="VASSALIZED" and nativeMode then
                        entry.Native=true
                        entry.OperationStatus=Property(player,"EC_NATIVE_OPERATION_STATUS")
                        if entry.Autonomy==100 and (id==localID or overlord==localID) then
                            entry.Action="RESTORE"; entry.ActionLabel="LOC_EC_NATIVE_RESTORE"
                            entry.OverlordID=overlord
                        end
                        if id==localID then entry.ProjectChoice=Property(player,prefix.."PROJECT") end
                    end
                end
                view.Entries[#view.Entries + 1] = entry
            elseif state == nil or state == "INDEPENDENT" then
                local advantage = ReadAdvantage(player, id)
                if advantage ~= nil then
                    local entry = { Kind = "CANDIDATE", Name = Name(id),
                        Status = "LOC_EC_OVERVIEW_CANDIDATE_UNKNOWN" }
                    if advantage.Valid then
                        entry.Status = advantage.State == "ACTIVE"
                            and "LOC_EC_OVERVIEW_CANDIDATE_OBSERVED"
                            or "LOC_EC_OVERVIEW_CANDIDATE_INVALIDATED"
                        entry.Reason = advantage.Reason
                        local reason = reasonLabels[advantage.Reason]
                        entry.ReasonLabel = reason ~= nil and Localized(reason[1], reason[2])
                            or Localized("LOC_EC_OVERVIEW_UNKNOWN", "暂不可用")
                        entry.Tier = advantage.Tier
                        entry.TierLabel = advantage.Tier == "REGULAR"
                            and Localized("LOC_EC_OVERVIEW_TIER_REGULAR", "常规优势")
                            or advantage.Tier == "EXTREME"
                            and Localized("LOC_EC_OVERVIEW_TIER_EXTREME", "极端优势")
                            or Localized("LOC_EC_OVERVIEW_UNKNOWN", "暂不可用")
                        entry.Samples = advantage.Samples
                        entry.LastSampleTurn = advantage.LastSampleTurn
                        entry.Turn = advantage.Turn
                        if nativeMode and advantage.State=="ACTIVE" and Slot(advantage.OverlordID)
                            and (advantage.OverlordID==localID or id==localID)
                            and (advantage.Reason=="AI_CANDIDATE" or advantage.Reason=="PLAYER_CONFIRMATION_REQUIRED") then
                            entry.TargetID=id; entry.OverlordID=advantage.OverlordID
                            entry.Action="ATTACH"; entry.ActionLabel="LOC_EC_NATIVE_ATTACH"
                            entry.OperationStatus=Property(player,"EC_NATIVE_OPERATION_STATUS")
                        end
                    end
                    view.Entries[#view.Entries + 1] = entry
                end
            end
        end
    end
    if nativeMode then
        for id=0,63 do
            local player=Players[id]
            local operation=player and Known(id) and Property(player,"EC_NATIVE_OPERATION_STATUS")
            if operation=="PRODUCTION_PENDING" then
                view.Entries[#view.Entries+1]={Name=Name(id),Status="LOC_EC_NATIVE_RESTORING",Native=true,
                    OperationStatus=operation}
            end
            if player and Known(id) and archiveLoaded then
                local archive,known=Read(function() return EC_NativeVassals.ReadArchive(Game,id) end)
                if known and archive and archive.Schema==1 and archive.VassalID==id then
                    for _,city in ipairs(archive.OriginalCities or {}) do
                        local ok,entry=pcall(function()
                            local record=assert(city.ProductionArchive)
                            assert(record.Schema==1 and record.Owner==id and record.X==city.X and record.Y==city.Y)
                            local queue,progress,total={},{},0
                            local function productionName(kind)
                                for _,group in ipairs({"Units","Buildings","Districts","Projects"}) do
                                    local row=GameInfo[group] and GameInfo[group][kind]
                                    if row then return Localized(row.Name,kind) end
                                end
                                return kind
                            end
                            for _,directive in ipairs(record.Entries) do
                                local kind
                                for _,group in ipairs({{"Units","UnitType"},{"Buildings","BuildingType"},
                                    {"Districts","DistrictType"},{"Projects","ProjectType"}}) do
                                    if directive[group[2]]~=nil then
                                        kind=assert(GameInfo[group[1]][directive[group[2]]])[group[2]];break
                                    end
                                end
                                queue[#queue+1]=productionName(assert(kind))
                            end
                            local kinds={}
                            for kind,amount in pairs(record.Progress) do
                                assert(type(kind)=="string" and type(amount)=="number" and amount==amount
                                    and amount>0 and amount<1000000000)
                                total=total+amount;kinds[#kinds+1]=kind
                            end
                            table.sort(kinds)
                            for _,kind in ipairs(kinds) do progress[#progress+1]=productionName(kind)..": "..record.Progress[kind] end
                            local policy=Read(function() return player:IsHuman() end)==true and "HUMAN" or "AI"
                            local state,remaining="ARCHIVED",total
                            if policy=="AI" and archive.State=="INDEPENDENT" then
                                local key="EC_NATIVE_PRODUCTION_"..archive.Plan.TransactionToken.."_"..city.CityID
                                local credit=assert(EC_AIProductionCredit.Read(Game,key))
                                assert(credit.Owner==id and credit.X==city.X and credit.Y==city.Y
                                    and credit.Total==total and credit.Archive==EC_CityPayload.Serialize(record))
                                state,remaining=credit.State,credit.Remaining
                            elseif policy=="HUMAN" and archive.State=="INDEPENDENT" then
                                state,remaining="COMPLETE",0
                                local key="EC_NATIVE_PRODUCTION_"..archive.Plan.TransactionToken.."_"..city.CityID
                                local credit=EC_HumanProductionRefund.Read(Game,key)
                                if credit then
                                    local source=EC_CityPayload.Deserialize(credit.Archive)
                                    assert(credit.Owner==id and credit.X==city.X and credit.Y==city.Y
                                        and source.RefundOriginal==EC_CityPayload.Serialize(record))
                                    policy="HUMAN_REFUND";state,remaining=credit.State,credit.Remaining
                                end
                            end
                            return {Kind="PRODUCTION_ARCHIVE",Native=true,Name=Name(id).." · "..Localized(city.Payload.Name,city.Payload.Name),
                                Status="LOC_EC_NATIVE_PRODUCTION_ARCHIVE",Queue=#queue>0 and table.concat(queue," → ") or Localized("LOC_EC_NATIVE_QUEUE_EMPTY","空"),
                                Investment=#progress>0 and table.concat(progress,"; ") or "0",Total=total,Remaining=remaining,
                                Policy=policy=="AI" and "LOC_EC_NATIVE_AI_CREDIT_POLICY" or policy=="HUMAN_REFUND"
                                    and "LOC_EC_NATIVE_HUMAN_REFUND_POLICY" or "LOC_EC_NATIVE_HUMAN_QUEUE_POLICY",
                                CreditState=assert(({ARCHIVED="LOC_EC_NATIVE_CREDIT_ARCHIVED",WAITING=policy=="HUMAN_REFUND"
                                    and "LOC_EC_NATIVE_HUMAN_REFUND_WAITING" or "LOC_EC_NATIVE_CREDIT_WAITING",
                                    SENT="LOC_EC_NATIVE_CREDIT_SENT",COMPLETE="LOC_EC_NATIVE_CREDIT_COMPLETE",
                                    UNKNOWN="LOC_EC_NATIVE_CREDIT_UNKNOWN"})[state])}
                        end)
                        view.Entries[#view.Entries+1]=ok and entry or {Name=Name(id),Status="LOC_EC_OVERVIEW_ARCHIVE_UNKNOWN"}
                    end
                end
            end
        end
    end
    return view
end
