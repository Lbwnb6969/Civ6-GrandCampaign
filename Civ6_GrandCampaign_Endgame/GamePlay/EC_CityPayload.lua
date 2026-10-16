-- Read native objects into persistent values; engine IDs are separate from
-- the transaction's logical identity (coordinates and original owner).
EC_CityPayload = {}

function EC_CityPayload.Copy(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then return value end
    if kind == "number" then
        assert(value == value and math.abs(value) < math.huge, "Non-finite city value")
        return value
    end
    assert(kind == "table" and depth < 16 and not seen[value], "Unsupported city value")
    seen[value] = true
    local result, count = {}, 0
    for key, item in pairs(value) do
        assert(type(key) == "string" or type(key) == "number", "Unsupported city key")
        count = count + 1
        assert(count <= 16384, "City property budget exceeded")
        result[key] = EC_CityPayload.Copy(item, depth + 1, seen)
    end
    seen[value] = nil
    return result
end

local function Encode(value, precise)
    local kind = type(value)
    if kind ~= "table" then
        assert(kind == "nil" or kind == "string" or kind == "boolean" or kind == "number")
        local text = precise and kind=="number" and string.format("%.17g",value) or tostring(value)
        return kind .. ":" .. #text .. ":" .. text
    end
    local keys, parts = {}, {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys, function(a,b) return Encode(a,precise) < Encode(b,precise) end)
    for _, key in ipairs(keys) do
        parts[#parts+1] = Encode(key,precise) .. Encode(value[key],precise)
    end
    return "table:" .. #keys .. ":{" .. table.concat(parts) .. "}"
end

function EC_CityPayload.Encode(value) return Encode(value,false) end
function EC_CityPayload.Serialize(value) return Encode(EC_CityPayload.Copy(value),true) end

-- Native Game properties round fractional numbers to float32. Store the
-- complete archive as bounded text so plan ratios and baselines survive
-- exact receipt checks and save/reload without weakening identity checks.
function EC_CityPayload.Deserialize(text)
    assert(type(text)=="string" and #text<=4194304,"Archive text invalid")
    local cursor=1
    local function parse(depth)
        assert(depth<=16,"Archive nesting exceeds bounds")
        local first,last,kind,count=string.find(text,"^(%a+):(%d+):",cursor)
        assert(first==cursor,"Archive value truncated")
        cursor=last+1
        count=tonumber(count)
        if kind=="table" then
            assert(depth<16 and count<=16384 and string.sub(text,cursor,cursor)=="{","Archive table invalid")
            cursor=cursor+1
            local result={}
            for i=1,count do
                local key=parse(depth+1)
                assert((type(key)=="string" or type(key)=="number") and result[key]==nil,"Archive key invalid")
                local value=parse(depth+1)
                assert(value~=nil,"Archive table value missing")
                result[key]=value
            end
            assert(string.sub(text,cursor,cursor)=="}","Archive table truncated")
            cursor=cursor+1
            return result
        end
        assert(count<=#text-cursor+1,"Archive scalar truncated")
        local value=string.sub(text,cursor,cursor+count-1)
        cursor=cursor+count
        if kind=="string" then return value end
        if kind=="number" then
            local number=tonumber(value)
            assert(type(number)=="number" and number==number and math.abs(number)<math.huge,"Archive number invalid")
            return number
        end
        if kind=="boolean" then assert(value=="true" or value=="false","Archive boolean invalid"); return value=="true" end
        assert(kind=="nil" and value=="nil","Archive type invalid")
        return nil
    end
    local result=parse(0)
    assert(cursor==#text+1 and EC_CityPayload.Serialize(result)==text,"Archive text inconsistent")
    return result
end

function EC_CityPayload.CaptureDistricts(city,api)
    local rows,seen={},{}
    local districts=city:GetDistricts()
    local function add(district)
        if not district then return end
        local key=district:GetX()..":"..district:GetY()
        assert(not seen[key],"District location duplicated")
        seen[key]=true
        local kind=assert(api.GameInfo.Districts[district:GetType()],"District type unavailable")
        rows[#rows+1]={Type=kind.DistrictType,X=district:GetX(),Y=district:GetY(),
            Complete=district:IsComplete(),Pillaged=district:IsPillaged(),Damage=district:GetDamage()}
    end
    if type(districts.GetDistrictAtLocation)=="function" then
        for _,plot in ipairs(city:GetOwnedPlots()) do
            add(districts:GetDistrictAtLocation(plot:GetX(),plot:GetY()))
        end
    else
        assert(type(districts.Members)=="function","Complete district enumeration unavailable")
        for _,district in districts:Members() do add(district) end
    end
    table.sort(rows,function(a,b)
        if a.Type~=b.Type then return a.Type<b.Type end
        if a.X~=b.X then return a.X<b.X end
        return a.Y<b.Y
    end)
    return rows
end

function EC_CityPayload.Capture(city, api, logicalID)
    local owner = city:GetOwner()
    local capital = api.Players[owner]:GetCities():GetCapitalCity()
    local payload = {Name=city:GetName(), Properties=EC_CityPayload.Copy(city:GetProperties()),
        Districts={}, Buildings={}, Plots={}, Religion={Followers={}},
        Production=city:GetBuildQueue():CurrentlyBuilding()}
    payload.Districts=EC_CityPayload.CaptureDistricts(city,api)
    for row in api.GameInfo.Buildings() do
        if city:GetBuildings():HasBuilding(row.Index) then
            payload.Buildings[#payload.Buildings+1] = {Type=row.BuildingType,
                Location=city:GetBuildings():GetBuildingLocation(row.Index),
                Pillaged=city:GetBuildings():IsPillaged(row.Index)}
        end
    end
    table.sort(payload.Buildings, function(a,b) return a.Type < b.Type end)
    for _, plot in ipairs(city:GetOwnedPlots()) do
        payload.Plots[#payload.Plots+1] = {Index=plot:GetIndex(), Terrain=plot:GetTerrainType(),
            Feature=plot:GetFeatureType(), Resource=plot:GetResourceType(),
            Improvement=plot:GetImprovementType(), Route=plot:GetRouteType(),
            District=plot:GetDistrictType()}
    end
    table.sort(payload.Plots, function(a,b) return a.Index < b.Index end)
    local religion = city:GetReligion()
    payload.Religion.Majority = religion:GetMajorityReligion()
    payload.Religion.Pantheon = religion:GetActivePantheon()
    for row in api.GameInfo.Religions() do
        payload.Religion.Followers[row.ReligionType] = religion:GetNumFollowers(row.Index)
    end
    return {CityID=logicalID or city:GetID(), NativeID=city:GetID(), Owner=owner,
        X=city:GetX(), Y=city:GetY(), OriginalOwner=city:GetOriginalOwner(),
        Population=city:GetPopulation(), Capital=capital ~= nil and capital:GetID()==city:GetID(),
        Payload=payload}
end

function EC_CityPayload.Equal(a,b)
    return EC_CityPayload.Encode(EC_CityPayload.Copy(a)) == EC_CityPayload.Encode(EC_CityPayload.Copy(b))
end

-- An unfinished wonder has a physical district plot but is absent from
-- GetBuildings(). Bind every physical footprint, including wonders that
-- the owner removed from the current queue; recreate missing ones at zero.
function EC_CityPayload.CaptureConstruction(city,api,production)
    assert(production and production.Schema==1 and production.Owner==city:GetOwner()
        and production.NativeID==city:GetID() and production.X==city:GetX() and production.Y==city:GetY()
        and production.Turn==api.Game.GetCurrentGameTurn(),"Construction snapshot identity unavailable")
    local rows,seen={},{}
    local map=api.Map or Map
    for _,plot in ipairs(city:GetOwnedPlots()) do
        if plot:GetDistrictType()==api.GameInfo.Districts.DISTRICT_WONDER.Index then
            local kind=assert(api.GameInfo.Buildings[plot:GetWonderType()],"Physical wonder type unavailable")
            assert((kind.IsWonder==true or kind.IsWonder==1) and plot:GetOwner()==city:GetOwner(),
                "Physical wonder identity unavailable")
            if not city:GetBuildings():HasBuilding(kind.Index) then
                assert(not seen[plot:GetIndex()],"Unfinished wonder identity duplicated")
                seen[plot:GetIndex()]=kind.BuildingType
                rows[#rows+1]={Type=kind.BuildingType,Location=plot:GetIndex()}
            end
        end
    end
    for _,entry in ipairs(production.Entries) do
        if entry.BuildingType~=nil then
            local kind=assert(api.GameInfo.Buildings[entry.BuildingType])
            if kind.IsWonder==true or kind.IsWonder==1 then
                if not city:GetBuildings():HasBuilding(kind.Index) then
                    local location=assert(entry.Location,"Unfinished wonder location unavailable")
                    local plot=assert(map.GetPlot(location.x,location.y),"Unfinished wonder plot unavailable")
                    assert(plot:GetOwner()==city:GetOwner() and plot:GetDistrictType()==api.GameInfo.Districts.DISTRICT_WONDER.Index,
                        "Unfinished wonder footprint unavailable")
                    assert(seen[plot:GetIndex()]==kind.BuildingType,
                        "Queued wonder does not match its physical footprint")
                end
            end
        end
    end
    table.sort(rows,function(a,b) return a.Location<b.Location end)
    return rows
end
