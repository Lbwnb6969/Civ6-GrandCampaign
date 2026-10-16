local attemptedTurn = nil
local attempted = {}
local lastError = nil
local function ReadMember(object, memberName)
    if object == nil then return nil, false end
    local ok, value = pcall(function() return object[memberName] end)
    return value, ok
end
local function BindEvent(name, handler)
    local event, readable = ReadMember(Events, name)
    local add, callable = ReadMember(event, "Add")
    if readable and callable and type(add) == "function" then pcall(function() add(handler) end) end
end
local function UnbindEvent(name, handler)
    local event, readable = ReadMember(Events, name)
    local remove, callable = ReadMember(event, "Remove")
    if readable and callable and type(remove) == "function" then pcall(function() remove(handler) end) end
end
local function True(value) return value == true or value == 1 or value == "1" or value == "true" end
local function Number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function Integer(value) return Number(value) and value >= 0 and value == math.floor(value) end
local tracedTurn, traced=nil,{}
local function Trace(stage)
    if not True(GameConfiguration.GetValue("EC_DEBUG_TIMING")) then return end
    local turn=Game.GetCurrentGameTurn()
    if tracedTurn~=turn then tracedTurn,traced=turn,{} end
    if traced[stage] then return end
    traced[stage]=true
    print("[EC:UI] metric_bridge_stage turn="..tostring(turn).." stage="..stage)
end

local function Collect(player, author, turn, speed)
    Trace("collect_"..player:GetID())
    local stats, techs, culture, treasury = player:GetStats(), player:GetTechs(), player:GetCulture(), player:GetTreasury()
    local grossGold, maintenance = treasury:GetGoldYield(), treasury:GetTotalMaintenance()
    if not Number(grossGold) or not Number(maintenance) or maintenance < 0 then return nil end
    local row = {
        OnStart = "EC_MetricSnapshot", SchemaVersion = 1, ForPlayer = author, PlayerID = player:GetID(),
        Turn = turn, SpeedMultiplier = speed, Human = player:IsHuman(),
        Military = stats:GetMilitaryStrengthWithoutTreasury(), TechsCompleted = stats:GetNumTechsResearched(),
        CivicsCompleted = stats:GetNumCivicsCompleted(), NetGold = grossGold - maintenance,
        GoldBalance = treasury:GetGoldBalance(), Science = techs:GetScienceYield(),
        Culture = culture:GetCultureYield(), Cities = player:GetCities():GetCount(),
    }
    Trace("collect_done_"..player:GetID())
    if not Integer(row.PlayerID) or row.PlayerID >= 64 or type(row.Human) ~= "boolean" then return nil end
    for _, key in ipairs({ "Cities", "TechsCompleted", "CivicsCompleted" }) do if not Integer(row[key]) then return nil end end
    for _, key in ipairs({ "Military", "GoldBalance", "Science", "Culture" }) do
        if not Number(row[key]) or row[key] < 0 then return nil end
    end
    if not Number(row.NetGold) then return nil end
    return row
end

local function Refresh()
    local ok, message = pcall(function()
        Trace("enter")
        if not True(GameConfiguration.GetValue("EC_METRIC_BRIDGE_TEST"))
            or GameConfiguration.IsAnyMultiplayer == nil or GameConfiguration.IsAnyMultiplayer() ~= false then return end
        local turn, author = Game.GetCurrentGameTurn(), Game.GetLocalPlayer()
        if not Integer(turn) or not Integer(author) or Players[author] == nil
            or Players[author]:IsHuman() ~= true or Players[author]:IsAlive() ~= true
            or Players[author]:IsTurnActive() ~= true then return end
        Trace("active")
        if attemptedTurn ~= nil and turn % 5 ~= 0 and not True(GameConfiguration.GetValue("EC_NATIVE_VASSAL_TEST")) then return end
        if attemptedTurn ~= turn then attemptedTurn, attempted = turn, {} end
        local gameSpeeds, speedsReadable = ReadMember(GameInfo, "GameSpeeds")
        local speedRow, rowReadable = nil, false
        if speedsReadable then
            speedRow, rowReadable = ReadMember(gameSpeeds, GameConfiguration.GetGameSpeedType())
        end
        local costMultiplier, multiplierReadable = ReadMember(speedRow, "CostMultiplier")
        local speed = rowReadable and multiplierReadable and costMultiplier or nil
        if not Number(speed) or speed <= 0 then return end
        local majors = {}
        for index, player in ipairs(PlayerManager.GetAliveMajors()) do
            if index > 64 then break end
            majors[#majors + 1] = player
        end
        table.sort(majors, function(a, b) return a:GetID() < b:GetID() end)
        for index = 1, math.min(64, #majors) do
            local player = majors[index]
            local id = player:GetID()
            local countOK, cities = pcall(function() return player:GetCities():GetCount() end)
            local prior = attempted[id]
            if countOK and Integer(cities) and (prior == nil or (prior.Cities ~= cities and prior.Attempts < 64)) then
                -- Mark before transport: failed writes cannot create a publish/retry loop.
                attempted[id] = { Cities = cities, Attempts = prior and prior.Attempts + 1 or 1 }
                local sent, result = pcall(function()
                    Trace("read_bank_"..id)
                    local bank = player:GetProperty("EC_METRICS_ACTIVE_BANK")
                    Trace("read_bank_done_"..id)
                    local refreshBank, refreshCities
                    if player:GetProperty("EC_METRICS_SCHEMA") == 1 and (bank == 1 or bank == 2)
                        and player:GetProperty("EC_METRICS_BANK" .. bank .. "_READY") == 1
                        and player:GetProperty("EC_METRICS_BANK" .. bank .. "_Turn") == turn then
                        local oldCities = player:GetProperty("EC_METRICS_BANK" .. bank .. "_Cities")
                        if oldCities == cities then return end
                        if not Integer(oldCities) then error("incomplete metric city count") end
                        refreshBank, refreshCities = bank, oldCities
                    end
                    local row = Collect(player, author, turn, speed)
                    if row == nil then error("incomplete metric row") end
                    row.RefreshBank, row.RefreshCities = refreshBank, refreshCities
                    Trace("dispatch_"..id)
                    return UI.RequestPlayerOperation(author, PlayerOperations.EXECUTE_SCRIPT, row)
                end)
                Trace("dispatch_done_"..id)
                if not sent then
                    print("[EC:UI] metric_snapshot_unavailable player=" .. tostring(id)
                        .. " reason=" .. tostring(result))
                elseif result == false then
                    print("[EC:UI] metric_snapshot_rejected player=" .. tostring(id))
                end
            end
        end
        Trace("complete")
    end)
    if not ok and lastError ~= tostring(message) then
        lastError = tostring(message)
        print("[EC:UI] metric_bridge_unavailable reason=" .. lastError)
    end
end

local function Shutdown()
    UnbindEvent("LoadScreenClose", Refresh)
    UnbindEvent("PlayerTurnActivated", Refresh)
    UnbindEvent("GameCoreEventPublishComplete", Refresh)
end
ContextPtr:SetShutdown(Shutdown)
BindEvent("LoadScreenClose", Refresh)
BindEvent("PlayerTurnActivated", Refresh)
BindEvent("GameCoreEventPublishComplete", Refresh)
