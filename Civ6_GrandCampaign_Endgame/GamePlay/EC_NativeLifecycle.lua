-- Native lifecycle used by city transactions. The caller persists intent
-- before invoking a mutation; no method retries or invents an alive state.
EC_NativeLifecycle = {}
local PROPERTY = "EC_NATIVE_ARCHIVE"

function EC_NativeLifecycle.Create(api)
    local marker = assert(api.GameInfo.Resources["RESOURCE_EC_ARCHIVE_STATUS"], "Resource archive rule not loaded; use a new test game")
    local guard=assert(api.GameInfo.Requirements["EC_PLAYER_CURRENTLY_HAS_NO_CITIES"],"Native city collection rule not loaded; use a new test game")
    assert(guard.RequirementType=="REQUIREMENT_COLLECTION_COUNT_ATLEAST" and (guard.Inverse==true or guard.Inverse==1),
        "Legacy city-count rule cannot restore ordinary defeat; use its Git checkpoint")
    local matched,collection,count = false,false,false
    for row in api.GameInfo.RequirementArguments() do
        if row.RequirementId == "EC_PLAYER_NOT_ARCHIVED_RESOURCE" and row.Name == "ResourceType" then
            matched = row.Value == marker.ResourceType
        end
        if row.RequirementId=="EC_PLAYER_CURRENTLY_HAS_NO_CITIES" then
            if row.Name=="CollectionType" then collection=row.Value=="COLLECTION_PLAYER_CITIES" end
            if row.Name=="Count" then count=tostring(row.Value)=="1" end
        end
    end
    assert(matched, "Native defeat requirement does not match archive status")
    assert(collection and count,"Native city collection arguments invalid")
    assert(api.GameConfiguration.IsAnyMultiplayer() == false, "Single-player lifecycle required")
    local function player(id)
        assert(type(id) == "number" and id >= 0 and id < 64 and id == math.floor(id))
        return assert(api.Players[id], "Native player missing")
    end
    local function has(p)
        local amount=p:GetResources():GetResourceAmount(marker.Index)
        assert(amount==0 or amount==1,"Archive resource quantity unknown")
        return amount==1
    end
    local function verifyDefeat(p,archived,restoring)
        local root=api.Game.GetDefeatRequirements(p:GetID(),"DEFEAT_DEFAULT")
        assert(type(root)=="number" and root>=0,"Native defeat requirement unavailable")
        local found,cityGuard=0,0
        for _,inner in ipairs(api.GameEffects.GetRequirementSetInnerRequirements(root)) do
            if api.GameEffects.GetRequirementDefinition(inner).Id=="EC_PLAYER_NOT_ARCHIVED_RESOURCE" then
                found=found+1
                assert(api.GameEffects.GetRequirementState(inner)==(archived and "NotMet" or "Met"),
                    "Native archive defeat gate did not update")
            end
            if api.GameEffects.GetRequirementDefinition(inner).Id=="EC_PLAYER_CURRENTLY_HAS_NO_CITIES" then
                cityGuard=cityGuard+1
                if restoring then
                    assert(api.GameEffects.GetRequirementState(inner)=="NotMet",
                        "Native defeat city count has not observed the restored city")
                end
            end
        end
        assert(found==1,"Native archive defeat gate missing or duplicated")
        if restoring then assert(cityGuard==1,"Native restoration city-count guard missing or duplicated; use a new test game") end
    end
    local lifecycle = {}
    function lifecycle.Preserve(id)
        local p = player(id)
        assert(p:IsAlive() and p:IsMajor() and p:GetCities():GetCount() > 0, "Player cannot be preserved")
        assert(not has(p), "Preservation already applied; inspect transaction intent")
        local old = p:GetProperty(PROPERTY)
        assert(old == nil or (type(old) == "table" and old.Schema == 2 and old.State == "RESTORED"
            and old.PlayerID == id), "Existing lifecycle record requires review")
        verifyDefeat(p,false)
        local era,score = p:GetEra(),p:GetScore()
        p:GetResources():ChangeResourceAmount(marker.Index,1)
        assert(has(p) and p:GetEra() == era and p:GetScore()==score, "Native preservation outcome unknown")
        verifyDefeat(p,true)
        p:SetProperty(PROPERTY, {Schema=2, State="PRESERVING", PlayerID=id})
        local stored = p:GetProperty(PROPERTY)
        assert(type(stored) == "table" and stored.Schema == 2 and stored.State == "PRESERVING"
            and stored.PlayerID == id, "Preservation receipt unknown")
        return true
    end
    function lifecycle.Archive(id, overlordID)
        local p, overlord = player(id), player(overlordID)
        assert(id ~= overlordID and overlord:IsAlive() and overlord:GetCities():GetCount() > 0)
        assert(p:IsAlive() and p:IsMajor() and has(p) and p:GetCities():GetCount() == 0
            and p:GetUnits():GetCount() == 0, "Native archived player precondition failed")
        local old = p:GetProperty(PROPERTY)
        assert(old == nil or (type(old) == "table" and old.Schema == 2 and old.PlayerID == id
            and (old.State == "RESTORED" or old.State == "PRESERVING")), "Existing archive requires review")
        verifyDefeat(p,true)
        p:SetProperty(PROPERTY, {Schema=2, State="ARCHIVED", PlayerID=id, OverlordID=overlordID})
        local stored = p:GetProperty(PROPERTY)
        assert(type(stored) == "table" and stored.Schema == 2 and stored.State == "ARCHIVED"
            and stored.PlayerID == id and stored.OverlordID == overlordID, "Archive receipt unknown")
        return true
    end
    function lifecycle.SetCapital(city)
        local p = player(city:GetOwner())
        assert(p:IsAlive(), "Capital owner is defeated")
        api.CityManager.SetAsCapital(city)
        local capital = p:GetCities():GetCapitalCity()
        assert(capital and capital:GetID() == city:GetID(), "Capital receipt unknown")
        -- TransferCity removes the former palace; SetAsCapital alone does
        -- not restore it (native evidence 119/123). Restore the seat of
        -- government only in the verified capital, never under a new lord.
        local palace = assert(api.GameInfo.Buildings["BUILDING_PALACE"])
        if not city:GetBuildings():HasBuilding(palace.Index) then
            city:GetBuildQueue():CreateIncompleteBuilding(palace.Index, 100)
            assert(city:GetBuildings():HasBuilding(palace.Index), "Capital palace outcome unknown")
        end
        return true
    end
    function lifecycle.Unarchive(id)
        local p = player(id)
        local saved = p:GetProperty(PROPERTY)
        assert(type(saved) == "table" and saved.Schema == 2 and saved.State == "ARCHIVED"
            and saved.PlayerID == id and has(p), "Archive identity invalid")
        assert(p:IsAlive() and p:GetCities():GetCount() > 0 and p:GetCities():GetCapitalCity())
        verifyDefeat(p,true,true)
        local era=p:GetEra()
        p:GetResources():ChangeResourceAmount(marker.Index,-1)
        -- Total score may publish returned-city points here. Survival is
        -- protected by the independently verified native city-count guard.
        assert(not has(p) and p:IsAlive() and p:GetEra()==era, "Native restoration outcome unknown")
        verifyDefeat(p,false,true)
        p:SetProperty(PROPERTY, {Schema=2, State="RESTORED", PlayerID=id, OverlordID=saved.OverlordID})
        local stored = p:GetProperty(PROPERTY)
        assert(type(stored) == "table" and stored.State == "RESTORED" and stored.PlayerID == id,
            "Restoration receipt unknown")
        return true
    end
    function lifecycle.GetParty(id)
        local p = player(id)
        local saved = p:GetProperty(PROPERTY)
        if saved ~= nil then
            assert(type(saved) == "table" and saved.Schema == 2 and saved.PlayerID == id
                and (saved.State == "ARCHIVED" or saved.State == "RESTORED"), "Lifecycle record incomplete, invalid or legacy; use its Git checkpoint")
        end
        local archived = type(saved) == "table" and saved.State == "ARCHIVED"
        assert(has(p) == archived, "Lifecycle marker and archive disagree")
        if archived then
            assert(type(saved.OverlordID) == "number" and saved.OverlordID ~= id and saved.OverlordID >= 0
                and saved.OverlordID < 64 and saved.OverlordID == math.floor(saved.OverlordID)
                and p:GetCities():GetCount() == 0 and p:GetUnits():GetCount() == 0, "Archive state inconsistent")
        end
        return {ID=id, Alive=p:IsAlive(), Major=p:IsMajor(), Human=p:IsHuman(),
            Cities=p:GetCities():GetCount(), Independent=not archived, Archived=archived,
            OverlordID=archived and saved.OverlordID or nil}
    end
    function lifecycle.IsPreserved(id)
        local p = player(id)
        local saved = p:GetProperty(PROPERTY)
        return p:IsAlive() and has(p) and type(saved) == "table" and saved.Schema == 2
            and saved.PlayerID == id and saved.State == "PRESERVING"
    end
    return lifecycle
end
