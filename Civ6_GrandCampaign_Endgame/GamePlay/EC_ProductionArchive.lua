-- Capture in the UI context, persist in gameplay before a transfer. The
-- archive is the original owner's queue; the new owner may produce freely.
EC_ProductionArchive = {}
function EC_ProductionArchive.CreateCapture(api, queueOnly)
    return function(owner,id,x,y)
        assert(api.GameConfiguration.IsAnyMultiplayer()==false,"Single-player production bridge required")
        local city=api.CityManager.GetCity(owner,id)
        if city==nil or city:GetID()~=id then return nil,"NATIVE_UI_CITY_PENDING" end
        assert(city:GetOwner()==owner and city:GetX()==x and city:GetY()==y,"Production city identity changed")
        return queueOnly and EC_ProductionArchive.CaptureQueue(city,api) or EC_ProductionArchive.Capture(city,api)
    end
end
local function number(value)
    assert(type(value)=="number" and value==value and value>=0 and value<math.huge,
        "Production progress unavailable")
    return value
end

-- Restore needs the current owner's queue only to bind unfinished wonder
-- footprints. Its dormant investments do not belong to the original owner.
-- Keep that snapshot separate from the strict original production archive.
function EC_ProductionArchive.CaptureQueue(city, api)
    local queue=city:GetBuildQueue()
    local size=number(queue:GetSize())
    assert(size==math.floor(size) and size<=16,"Production queue exceeds archive limit")
    local record={Schema=1,Owner=city:GetOwner(),NativeID=city:GetID(),X=city:GetX(),Y=city:GetY(),
        Turn=api.Game.GetCurrentGameTurn(),Entries={},Progress={}}
    for i=0,size-1 do record.Entries[#record.Entries+1]=EC_CityPayload.Copy(assert(queue:GetAt(i))) end
    return record
end

function EC_ProductionArchive.Capture(city, api)
    local record=EC_ProductionArchive.CaptureQueue(city,api)
    local queue=city:GetBuildQueue()
    for _,group in ipairs({{"Units","UnitType","GetUnitProgress"},
        {"Buildings","BuildingType","GetBuildingProgress"},
        {"Districts","DistrictType","GetDistrictProgress"},
        {"Projects","ProjectType","GetProjectProgress"}}) do
        for row in api.GameInfo[group[1]]() do
            local progress=number(queue[group[3]](queue,row.Index))
            if progress==0 then
                -- Native getters truncate 0.5 to zero. The separate presence
                -- flag still records an investment; never archive it as empty.
                assert(type(queue.HasProductionProgress)=="function",
                    "Native production investment presence unavailable")
                local present=queue:HasProductionProgress(assert(row.Hash,"Production type hash unavailable"))
                assert(type(present)=="boolean","Native production investment presence unavailable")
                assert(not present,"Hidden fractional production investment: "..row[group[2]])
            end
            if progress>0 then record.Progress[row[group[2]]]=progress end
        end
    end
    return record
end

function EC_ProductionArchive.Parameters(entry, api, first)
    local params={}
    local operations=api.CityOperationTypes
    params[operations.PARAM_INSERT_MODE]=first and operations.VALUE_EXCLUSIVE or operations.VALUE_APPEND
    local kind,key,member
    if entry.UnitType~=nil then kind,key,member="Units","PARAM_UNIT_TYPE",entry.UnitType
    elseif entry.BuildingType~=nil then kind,key,member="Buildings","PARAM_BUILDING_TYPE",entry.BuildingType
    elseif entry.DistrictType~=nil then kind,key,member="Districts","PARAM_DISTRICT_TYPE",entry.DistrictType
    elseif entry.ProjectType~=nil then kind,key,member="Projects","PARAM_PROJECT_TYPE",entry.ProjectType
    else error("Production directive unsupported") end
    local row=assert(api.GameInfo[kind][member],"Archived production type missing")
    params[operations[key]]=row.Hash
    if entry.MilitaryFormationType~=nil then params[operations.MILITARY_FORMATION_TYPE]=entry.MilitaryFormationType end
    if entry.Modifiers~=nil then params[operations.PARAM_MODIFIERS]=entry.Modifiers end
    if entry.Location and entry.Location.x>=0 and entry.Location.y>=0 then
        params[operations.PARAM_X]=entry.Location.x
        params[operations.PARAM_Y]=entry.Location.y
    end
    return params,row
end

function EC_ProductionArchive.CaptureActive(city,api)
    local queue=city:GetBuildQueue()
    local result={Owner=city:GetOwner(),NativeID=city:GetID(),X=city:GetX(),Y=city:GetY(),
        Turn=api.Game.GetCurrentGameTurn(),Kind="NONE",Progress=0,Cost=0}
    if queue:GetSize()==0 then return result end
    local entry=assert(queue:GetAt(0))
    for _,group in ipairs({{"Units","UnitType","GetUnitProgress","GetUnitCost"},
        {"Buildings","BuildingType","GetBuildingProgress","GetBuildingCost"},
        {"Districts","DistrictType","GetDistrictProgress","GetDistrictCost"},
        {"Projects","ProjectType","GetProjectProgress","GetProjectCost"}}) do
        if entry[group[2]]~=nil then
            local row=assert(api.GameInfo[group[1]][entry[group[2]]])
            result.Kind=row[group[2]]
            result.Progress=number(queue[group[3]](queue,row.Index))
            result.Cost=number(queue[group[4]](queue,row.Index))
            return result
        end
    end
    error("AI active production directive unsupported")
end

function EC_ProductionArchive.RequestLocalQueue(city, record, api, replaceManagedQueue)
    assert(record.Schema==1 and city:GetOwner()==record.Owner
        and city:GetX()==record.X and city:GetY()==record.Y, "Production archive identity changed")
    assert(city:GetOwner()==api.Game.GetLocalPlayer(), "Native non-local production dispatch unavailable")
    assert(replaceManagedQueue==true or city:GetBuildQueue():GetSize()==0,"Production queue already changed; do not overwrite")
    if #record.Entries==0 then
        if city:GetBuildQueue():GetSize()==0 then return end
        assert(replaceManagedQueue==true and city:GetBuildQueue():GetSize()==1,
            "Empty archive can only remove the verified temporary production")
        local operations=api.CityOperationTypes
        local params={[operations.PARAM_INSERT_MODE]=assert(operations.VALUE_REMOVE_AT)}
        params[assert(operations.PARAM_QUEUE_LOCATION)]=0
        api.CityManager.RequestOperation(city,operations.BUILD,params)
        return
    end
    -- Caller persists a sent intent before dispatch and verifies the actual
    -- queue in a later publish. A nil native return is never a success proof.
    local requests={}
    for index,entry in ipairs(record.Entries) do
        local params,row=EC_ProductionArchive.Parameters(entry,api,index==1)
        assert(city:GetBuildQueue():CanProduce(row.Hash,true)==true
            and api.CityManager.CanStartOperation(city,api.CityOperationTypes.BUILD,params,true)==true,
            "Archived production no longer legal")
        requests[#requests+1]=params
    end
    for _,params in ipairs(requests) do
        api.CityManager.RequestOperation(city,api.CityOperationTypes.BUILD,params)
    end
end

function EC_ProductionArchive.CreateRequest(api)
    return function(record,replaceManagedQueue)
        assert(api.GameConfiguration.IsAnyMultiplayer()==false,"Single-player production bridge required")
        local city=assert(api.CityManager.GetCityAt(record.X,record.Y),"Production city missing")
        EC_ProductionArchive.RequestLocalQueue(city,record,api,replaceManagedQueue)
    end
end

function EC_ProductionArchive.CreateCapability(api)
    return function(owner,record,preflightStage)
        if #record.Entries==0 and next(record.Progress)==nil then return true end
        if api.GameConfiguration.IsAnyMultiplayer()~=false or api.Game.GetLocalPlayer()~=owner then return false end
        if preflightStage then
            if #record.Entries==0 and (api.CityOperationTypes.VALUE_REMOVE_AT==nil
                or api.CityOperationTypes.PARAM_QUEUE_LOCATION==nil) then return false end
            local city=api.CityManager.GetCityAt(record.X,record.Y)
            if not city then return false end
            local foreign=city:GetOwner()~=owner
            local target=api.Players and api.Players[owner]
            if foreign then
                local lifecycle=target and target:GetProperty("EC_NATIVE_ARCHIVE")
                local wrapper=api.Game:GetProperty("EC_NATIVE_VASSAL_"..owner)
                if not lifecycle or lifecycle.Schema~=2 or lifecycle.State~="ARCHIVED"
                    or lifecycle.OverlordID~=city:GetOwner() or not wrapper
                    or wrapper.Format~="EC_ARCHIVE_TEXT_V1" then return false end
                local archived=EC_CityPayload.Deserialize(wrapper.Payload)
                local sourceRecord=record.RefundOriginal and EC_CityPayload.Deserialize(record.RefundOriginal) or record
                local bound=false
                if archived.VassalID~=owner or (archived.State~="VASSALIZED" and archived.State~="RESTORING") then return false end
                for _,original in ipairs(archived.OriginalCities) do
                    local production=original.ProductionArchive
                    if production and production.NativeID==record.NativeID and production.Owner==owner
                        and production.X==record.X and production.Y==record.Y and production.Turn==record.Turn
                        and EC_CityPayload.Equal(production,sourceRecord)
                        and original.OriginalOwner==city:GetOriginalOwner() then bound=true;break end
                end
                if not bound then return false end
            end
            for _,entry in ipairs(record.Entries) do
                local params,row=EC_ProductionArchive.Parameters(entry,api,true)
                if foreign then
                    -- The recipient has no city yet. The lord's obsolescence
                    -- rules cannot authorize or reject this human's archive.
                    -- Bound land units without resource/location prerequisites
                    -- can be checked against the recipient's actual research;
                    -- other categories still require their native city check.
                    if entry.BuildingType~=nil then
                        -- Granary has a native round-trip/queue/precise-progress
                        -- proof. Keep other building and placement families
                        -- gated until their own prerequisites are verified.
                        if row.BuildingType~="BUILDING_GRANARY" or row.PrereqDistrict~="DISTRICT_CITY_CENTER"
                            or row.IsWonder==true or row.IsWonder==1 or row.TraitType
                            or row.MaxPlayerInstances~=-1 or row.MaxWorldInstances~=-1 then return false end
                        for _,flag in ipairs({"InternalOnly","MustPurchase","RequiresPlacement","RequiresRiver",
                            "RequiresAdjacentRiver","RequiresReligion","EnabledByReligion","Capital",
                            "AllowsHolyCity","MustBeLake","MustNotBeLake","MustBeAdjacentLand","AdjacentCapital"}) do
                            if row[flag]==true or row[flag]==1 then return false end
                        end
                        for _,field in ipairs({"AdjacentDistrict","AdjacentResource","AdjacentToMountain",
                            "AdjacentImprovement","CityAdjacentTerrain","GovernmentTierRequirement"}) do
                            if row[field]~=nil and row[field]~=false and row[field]~=0 then return false end
                        end
                        local district=api.GameInfo.Districts.DISTRICT_CITY_CENTER
                        -- CityDistricts:GetDistrictByType is Gameplay-only.
                        -- The native UI city-center ID belongs to its owner's
                        -- PlayerDistricts collection (also used by CitySupport).
                        local ownerPlayer=api.Players[city:GetOwner()]
                        local actual=district and ownerPlayer
                            and ownerPlayer:GetDistricts():FindID(city:GetDistrictID())
                        if not actual or actual:GetType()~=district.Index
                            or actual:GetX()~=city:GetX() or actual:GetY()~=city:GetY()
                            or not actual:IsComplete() or city:GetBuildings():HasBuilding(row.Index) then return false end
                        for pair in api.GameInfo.BuildingPrereqs() do
                            if pair.Building==row.BuildingType then return false end
                        end
                    elseif entry.UnitType==nil or row.Domain~="DOMAIN_LAND" or row.StrategicResource
                        or row.PrereqDistrict or row.RequiresPopulation==true or row.CanTrain==false then return false end
                    for _,requirement in ipairs({{"PrereqTech","Technologies","GetTechs","HasTech",true},
                        {"PrereqCivic","Civics","GetCulture","HasCivic",true},
                        {"ObsoleteTech","Technologies","GetTechs","HasTech",false},
                        {"MandatoryObsoleteTech","Technologies","GetTechs","HasTech",false}}) do
                        local kind=row[requirement[1]]
                        if kind then
                            local definition=api.GameInfo[requirement[2]][kind]
                            if not definition then return false end
                            local subsystem=target[requirement[3]](target)
                            if subsystem[requirement[4]](subsystem,definition.Index)~=requirement[5] then return false end
                        end
                    end
                elseif city:GetBuildQueue():CanProduce(row.Hash,true)~=true
                    or api.CityManager.CanStartOperation(city,api.CityOperationTypes.BUILD,params,true)~=true then return false end
                local getter=entry.UnitType~=nil and "GetUnitCost" or entry.BuildingType~=nil and "GetBuildingCost"
                    or entry.DistrictType~=nil and "GetDistrictCost" or "GetProjectCost"
                local kind=row.UnitType or row.BuildingType or row.DistrictType or row.ProjectType
                if (record.Progress[kind] or 0)>=city:GetBuildQueue()[getter](city:GetBuildQueue(),row.Index) then return false end
            end
        end
        return true
    end
end

function EC_ProductionArchive.ProgressMatches(actual,record)
    return EC_CityPayload.Equal(actual.Progress,record.Progress)
end

function EC_ProductionArchive.QueueMatches(city, record)
    local queue=city:GetBuildQueue()
    if queue:GetSize()~=#record.Entries then return false end
    for index,entry in ipairs(record.Entries) do
        if not EC_CityPayload.Equal(entry,queue:GetAt(index-1)) then return false end
    end
    return true
end
