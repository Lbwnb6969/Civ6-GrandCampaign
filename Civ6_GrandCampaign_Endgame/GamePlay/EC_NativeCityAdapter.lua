-- Explicit native implementation of the transaction adapter. All writes
-- run under EC_VassalTransaction's durable operation intent.
EC_NativeCityAdapter = {}

function EC_NativeCityAdapter.CaptureCities(api, playerID)
    local records = {}
    for _, city in api.Players[playerID]:GetCities():Members() do
        local record=EC_CityPayload.Capture(city,api)
        if api.CaptureProduction ~= nil then
            record.ProductionArchive=EC_CityPayload.Copy(api.CaptureProduction(playerID,city:GetID(),city:GetX(),city:GetY()))
            assert(record.ProductionArchive.Schema==1 and record.ProductionArchive.Owner==playerID
                and record.ProductionArchive.NativeID==city:GetID() and record.ProductionArchive.X==city:GetX()
                and record.ProductionArchive.Y==city:GetY()
                and record.ProductionArchive.Turn==api.Game.GetCurrentGameTurn(),"Production snapshot mismatch")
            record.Construction=EC_CityPayload.CaptureConstruction(city,api,record.ProductionArchive)
        end
        records[#records+1] = record
    end
    table.sort(records,function(a,b) return a.CityID < b.CityID end)
    assert(#records == api.Players[playerID]:GetCities():GetCount(), "Incomplete native city list")
    return records
end

function EC_NativeCityAdapter.CaptureUnits(api, playerID)
    local records = {}
    for _, unit in api.Players[playerID]:GetUnits():Members() do
        local kind = assert(api.GameInfo.Units[unit:GetType()])
        records[#records+1] = {UnitID=unit:GetID(),Owner=playerID,Type=kind.UnitType}
    end
    table.sort(records,function(a,b) return a.UnitID < b.UnitID end)
    assert(#records == api.Players[playerID]:GetUnits():GetCount(), "Incomplete native unit list")
    return records
end

function EC_NativeCityAdapter.Create(api, plan)
    assert(plan.NativeLifecycle == true, "Native lifecycle intent required")
    local lifecycle = EC_NativeLifecycle.Create(api)
    local map,routeBuilder=api.Map or Map,api.RouteBuilder or RouteBuilder
    local records = {}
    for _, record in ipairs(plan.Cities) do
        assert(record.Payload and record.NativeID and record.OriginalOwner ~= nil)
        local capturedPlots={}
        for _,plot in ipairs(record.Payload.Plots or {}) do capturedPlots[plot.Index]=plot end
        for _,construction in ipairs(record.Construction or {}) do
            local kind=assert(api.GameInfo.Buildings[construction.Type],"Construction type missing")
            assert((kind.IsWonder==true or kind.IsWonder==1) and capturedPlots[construction.Location]
                and capturedPlots[construction.Location].District==api.GameInfo.Districts.DISTRICT_WONDER.Index,
                "Construction footprint not bound to captured city")
        end
        if record.Payload.Plots and #record.Payload.Plots>0 then
            assert(map and type(map.GetPlotByIndex)=="function" and routeBuilder
                and type(routeBuilder.SetRouteType)=="function","Native plot route preservation unavailable")
            for _,plot in ipairs(record.Payload.Plots) do
                assert(type(plot.Index)=="number" and type(plot.Route)=="number"
                    and plot.Index>=0 and plot.Index==math.floor(plot.Index)
                    and plot.Route>=-1 and plot.Route==math.floor(plot.Route),"Archived route identity invalid")
                assert(map.GetPlotByIndex(plot.Index),"Archived plot missing")
            end
        end
        if plan.QueuePolicy=="ARCHIVE_PAUSE" and plan.Action=="ATTACH" then
            assert(record.ProductionArchive and record.ProductionArchive.Schema==1
                and record.ProductionArchive.Owner==plan.VassalID,"Production archive missing")
        elseif plan.QueuePolicy=="ARCHIVE_PAUSE" and plan.Action=="RESTORE" then
            assert(record.ProductionArchive and record.ProductionArchive.Owner==plan.VassalID,"Production archive missing")
            EC_ProductionRestore.Validate(record.ProductionArchive,api)
        elseif plan.Action=="ATTACH" then
            assert(record.Payload.Production=="NONE","Production preservation policy required before transfer")
        end
        records[record.CityID] = record
    end
    local mapKey = "EC_VASSAL_NATIVE_MAP_"..plan.VassalID
    local saved = api.Game:GetProperty(mapKey)
    if saved ~= nil then
        assert(type(saved)=="table" and saved.Schema==1 and saved.VassalID==plan.VassalID
            and type(saved.Entries)=="table", "Native identity map invalid")
    end
    local mapping = saved and EC_CityPayload.Copy(saved) or {Schema=1,VassalID=plan.VassalID,Entries={}}
    local adapter = {}
    local function resolve(id, owner)
        local record = assert(records[id], "Logical city unknown")
        local city = assert(api.CityManager.GetCityAt(record.X,record.Y), "Native city missing")
        assert(city:GetOwner()==owner and city:GetOriginalOwner()==record.OriginalOwner, "City identity changed")
        local entry = mapping.Entries[tostring(id)]
        if entry ~= nil then
            assert(entry.X==record.X and entry.Y==record.Y and entry.OriginalOwner==record.OriginalOwner
                and entry.Owner==owner and entry.NativeID==city:GetID(), "Native city map conflict")
        else
            assert(city:GetID()==record.NativeID, "Native city identity unknown")
        end
        return city, record
    end
    function adapter:GetCityRecord(id, owner, x, y)
        local city, record = resolve(id,owner)
        assert(record.X==x and record.Y==y)
        return EC_CityPayload.Capture(city,api,id), true
    end
    function adapter:GetParty(id) return lifecycle.GetParty(id) end
    function adapter:PreservePlayer(id) return lifecycle.Preserve(id) end
    function adapter:IsPreserved(id) return lifecycle.IsPreserved(id) end
    local function transfer(id, from, to)
        local city, record = resolve(id,from)
        local properties = EC_CityPayload.Copy(city:GetProperties())
        local oldNativeID = city:GetID()
        api.CityManager.TransferCity(city,to)
        local moved = assert(api.CityManager.GetCityAt(record.X,record.Y), "Native transfer outcome unknown")
        assert(moved:GetOwner()==to and moved:GetOriginalOwner()==record.OriginalOwner)
        for _,construction in ipairs(record.Construction or {}) do
            local kind=api.GameInfo.Buildings[construction.Type]
            local plot=assert(map.GetPlotByIndex(construction.Location))
            assert(plot:GetOwner()==to,"Transferred construction plot identity changed")
            if plot:GetDistrictType()==-1 then
                assert(not moved:GetBuildings():HasBuilding(kind.Index),"Construction completion changed")
                moved:GetBuildQueue():CreateIncompleteBuilding(kind.Index,construction.Location,0)
            end
            assert(plot:GetDistrictType()==api.GameInfo.Districts.DISTRICT_WONDER.Index,
                "Construction footprint outcome unknown")
        end
        if to==plan.VassalID and plan.Action=="RESTORE" then
            -- TransferCity can omit an incomplete district or building. The
            -- original snapshot is authoritative; recreate only missing
            -- entries on their captured plots before transaction verification.
            local queue=moved:GetBuildQueue()
            for _,district in ipairs(record.Payload.Districts or {}) do
                local current=moved:GetDistricts():GetDistrictAtLocation(district.X,district.Y)
                local expected=assert(api.GameInfo.Districts[district.Type])
                if current and current:GetType()~=expected.Index then
                    local actual=assert(api.GameInfo.Districts[current:GetType()])
                    local replacement=false
                    for pair in api.GameInfo.DistrictReplaces() do
                        if (pair.CivUniqueDistrictType==district.Type and pair.ReplacesDistrictType==actual.DistrictType)
                            or (pair.CivUniqueDistrictType==actual.DistrictType and pair.ReplacesDistrictType==district.Type) then
                            replacement=true;break
                        end
                    end
                    assert(replacement,"Transferred district type changed outside its native replacement family")
                end
                if current==nil or current:GetType()~=expected.Index then
                    local plot=assert(map.GetPlot(district.X,district.Y),"Archived district plot missing")
                    queue:CreateIncompleteDistrict(expected.Index,plot:GetIndex(),district.Complete and 100 or 0)
                    current=moved:GetDistricts():GetDistrictAtLocation(district.X,district.Y)
                    assert(current~=nil and current:GetType()==expected.Index
                        and current:IsComplete()==district.Complete,
                        "Archived district restoration outcome unknown")
                end
            end
            for _,building in ipairs(record.Payload.Buildings or {}) do
                if building.Type~="BUILDING_PALACE" and not moved:GetBuildings():HasBuilding(api.GameInfo.Buildings[building.Type].Index) then
                    local plot=assert(map.GetPlotByIndex(building.Location),"Archived building plot missing")
                    queue:CreateIncompleteBuilding(api.GameInfo.Buildings[building.Type].Index,plot:GetIndex(),100)
                    assert(moved:GetBuildings():HasBuilding(api.GameInfo.Buildings[building.Type].Index),
                        "Archived building restoration outcome unknown")
                end
            end
        end
        -- TransferCity can promote the city-center road to the recipient's
        -- technology tier. Preserve the captured physical plot data before
        -- transaction verification instead of accepting that silent change.
        for _,original in ipairs(record.Payload.Plots or {}) do
            local plot=assert(map.GetPlotByIndex(original.Index),"Transferred plot missing")
            if plot:GetRouteType()~=original.Route then routeBuilder.SetRouteType(plot,original.Route) end
            assert(plot:GetRouteType()==original.Route,"Transferred route outcome unknown")
        end
        for key, value in pairs(properties) do moved:SetProperty(key,EC_CityPayload.Copy(value)) end
        assert(EC_CityPayload.Equal(properties,moved:GetProperties()), "City properties outcome unknown")
        mapping.Entries[tostring(id)] = {NativeID=moved:GetID(), PreviousNativeID=oldNativeID,
            Owner=to,X=record.X,Y=record.Y,OriginalOwner=record.OriginalOwner}
        api.Game:SetProperty(mapKey,EC_CityPayload.Copy(mapping))
        assert(EC_CityPayload.Equal(mapping,api.Game:GetProperty(mapKey)), "City identity receipt unknown")
        return true
    end
    function adapter:TransferCity(id,from,to) return transfer(id,from,to) end
    function adapter:RestoreCity(id,from,to) return transfer(id,from,to) end
    function adapter:GetUnitOwner(id,owner)
        local player = assert(api.Players[owner])
        local unit = player:GetUnits():FindID(id)
        if unit == nil then return nil,true end
        assert(unit:GetOwner()==owner)
        return owner,true
    end
    function adapter:RemoveUnit(id,owner)
        local unit = assert(api.Players[owner]:GetUnits():FindID(id), "Native unit missing")
        assert(unit:GetOwner()==owner)
        api.UnitManager.Kill(unit)
        assert(api.Players[owner]:GetUnits():FindID(id)==nil, "Native unit removal outcome unknown")
        return true
    end
    function adapter:ArchivePlayer(id,overlord) return lifecycle.Archive(id,overlord) end
    function adapter:SetCapital(owner,id)
        local city = resolve(id,owner)
        return lifecycle.SetCapital(city)
    end
    function adapter:GetCapital(owner)
        local city = api.Players[owner]:GetCities():GetCapitalCity()
        if city == nil then return nil,true end
        for id,record in pairs(records) do
            if record.X==city:GetX() and record.Y==city:GetY() then
                resolve(id,owner)
                return id,true
            end
        end
        error("Capital outside archived identity set")
    end
    function adapter:RestoreProduction(id,owner)
        local city,record=resolve(id,owner)
        return EC_ProductionRestore.Step(city,record.ProductionArchive,api,
            "EC_NATIVE_PRODUCTION_"..plan.TransactionToken.."_"..id)
    end
    function adapter:UnarchivePlayer(id,overlord)
        local savedParty = api.Players[id]:GetProperty("EC_NATIVE_ARCHIVE")
        assert(type(savedParty)=="table" and savedParty.OverlordID==overlord)
        return lifecycle.Unarchive(id)
    end
    return adapter
end
