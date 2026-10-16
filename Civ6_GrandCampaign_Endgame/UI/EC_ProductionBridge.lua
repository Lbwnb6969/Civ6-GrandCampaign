include("EC_CityPayload")
include("EC_ProductionArchive")
local api={Game=Game,GameInfo=GameInfo,Players=Players,CityManager=CityManager,GameConfiguration=GameConfiguration,
    CityOperationTypes=CityOperationTypes}
local Capture=EC_ProductionArchive.CreateCapture(api)
local CaptureConstructionQueue=EC_ProductionArchive.CreateCapture(api,true)
local Request=EC_ProductionArchive.CreateRequest(api)
local Capability=EC_ProductionArchive.CreateCapability(api)
ExposedMembers.EC_CaptureProductionArchive=Capture
ExposedMembers.EC_CaptureConstructionQueue=CaptureConstructionQueue
ExposedMembers.EC_RequestProductionArchive=Request
ExposedMembers.EC_CanRestoreProductionArchive=Capability
local dispatching=false
local lastFingerprint={}
local published,epoch,session={},0,tostring({})
local function PublishedProduction(owner,id,x,y)
    local row=published[owner] and published[owner][id]
    if row and row.X==x and row.Y==y then return EC_CityPayload.Copy(row) end
end
ExposedMembers.EC_GetPublishedProduction=PublishedProduction
local function PublishCreditSnapshots()
    published={};epoch=epoch+1
    if GameConfiguration.IsAnyMultiplayer()~=false then return end
    local observation=GameConfiguration.GetValue("EC_OBSERVATION_ONLY")
    local mode=GameConfiguration.GetValue("EC_NATIVE_VASSAL_TEST")
    if observation~=false and observation~=0 and observation~="0" and observation~="false" then return end
    if mode~=true and mode~=1 and mode~="1" then return end
    local localID=Game.GetLocalPlayer()
    if type(localID)~="number" or not Players[localID] or not Players[localID]:IsHuman() then return end
    -- Publications also occur during AI production and before the UI finishes
    -- applying ordinary income. Such snapshots cannot authorize a grant.
    if Players[localID]:IsTurnActive()~=true or Players[localID]:IsTurnActiveComplete()~=true
        or UI.IsProcessingMessages()~=false then return end
    for _,p in ipairs(PlayerManager.GetAliveMajors()) do
        if p:GetProperty("EC_AI_PRODUCTION_CREDIT_STATUS")=="PENDING"
            or p:GetProperty("EC_HUMAN_PRODUCTION_CREDIT_STATUS")=="PENDING" then
            local owner=p:GetID();published[owner]={}
            for _,city in p:GetCities():Members() do
                local row=EC_ProductionArchive.CaptureActive(city,api)
                row.Epoch=epoch;row.Session=session;row.HumanTurnReady=true
                published[owner][row.NativeID]=row
            end
        end
    end
end
local tracedTurn, traced=nil,{}
local function Trace(stage)
    local debug=GameConfiguration.GetValue("EC_DEBUG_TIMING")
    if debug~=true and debug~=1 and debug~="1" then return end
    local turn=Game.GetCurrentGameTurn()
    if tracedTurn~=turn then tracedTurn,traced=turn,{} end
    if traced[stage] then return end
    traced[stage]=true
    print("[EC:UI] production_bridge_stage turn="..tostring(turn).." stage="..stage)
end
local function AdvancePending()
    Trace("enter")
    if dispatching or GameConfiguration.IsAnyMultiplayer()~=false then return end
    local observation=GameConfiguration.GetValue("EC_OBSERVATION_ONLY")
    if observation~=false and observation~=0 and observation~="0" and observation~="false" then return end
    local id=Game.GetLocalPlayer()
    if type(id)~="number" or id<0 or not Players[id] or not Players[id]:IsHuman()
        or not Players[id]:IsTurnActive() then return end
    local mode=GameConfiguration.GetValue("EC_NATIVE_VASSAL_TEST")
    if mode~=true and mode~=1 and mode~="1" then return end
    -- UI publishes while loading, before Gameplay registers EXECUTE_SCRIPT.
    -- Do not consume a fingerprint for a request that cannot be received yet.
    if type(ExposedMembers.EC_NativeDispatchReady)~="function"
        or ExposedMembers.EC_NativeDispatchReady()~=true then return end
    Trace("active")
    for _,p in ipairs(PlayerManager.GetAliveMajors()) do
        local target=p:GetID()
        Trace("read_status_"..target)
        local native=p:GetProperty("EC_NATIVE_OPERATION_STATUS")
        Trace("read_status_done_"..target)
        local creditPrefix=p:IsHuman() and "EC_HUMAN_PRODUCTION_CREDIT_" or "EC_AI_PRODUCTION_CREDIT_"
        local credit=native~="PRODUCTION_PENDING" and p:GetProperty(creditPrefix.."STATUS")=="PENDING"
        if native=="PRODUCTION_PENDING" or credit then
            local snapshots={Phase=p:GetProperty(credit and creditPrefix.."PHASE" or "EC_NATIVE_OPERATION_PHASE"),Cities={}}
            for _,city in p:GetCities():Members() do
                local row
                if credit then row=PublishedProduction(target,city:GetID(),city:GetX(),city:GetY())
                else row=Capture(target,city:GetID(),city:GetX(),city:GetY()) end
                if row then
                    row.Epoch=nil;row.Session=nil
                    snapshots.Cities[#snapshots.Cities+1]=row
                end
            end
            local fingerprint=EC_CityPayload.Encode(snapshots)
            if lastFingerprint[target]~=fingerprint then
                lastFingerprint[target]=fingerprint
                dispatching=true
                UI.RequestPlayerOperation(id,PlayerOperations.EXECUTE_SCRIPT,{OnStart="EC_NativeAdvance",ForPlayer=id})
                return
            end
        end
    end
    Trace("complete")
end
local function OnPublish() dispatching=false; PublishCreditSnapshots(); AdvancePending() end
Events.GameCoreEventPublishComplete.Add(OnPublish)
Events.PlayerTurnActivated.Add(AdvancePending)
ContextPtr:SetShutdown(function()
    Events.GameCoreEventPublishComplete.Remove(OnPublish)
    Events.PlayerTurnActivated.Remove(AdvancePending)
    if ExposedMembers.EC_CaptureProductionArchive==Capture then ExposedMembers.EC_CaptureProductionArchive=nil end
    if ExposedMembers.EC_CaptureConstructionQueue==CaptureConstructionQueue then ExposedMembers.EC_CaptureConstructionQueue=nil end
    if ExposedMembers.EC_RequestProductionArchive==Request then ExposedMembers.EC_RequestProductionArchive=nil end
    if ExposedMembers.EC_CanRestoreProductionArchive==Capability then ExposedMembers.EC_CanRestoreProductionArchive=nil end
    if ExposedMembers.EC_GetPublishedProduction==PublishedProduction then ExposedMembers.EC_GetPublishedProduction=nil end
end)
