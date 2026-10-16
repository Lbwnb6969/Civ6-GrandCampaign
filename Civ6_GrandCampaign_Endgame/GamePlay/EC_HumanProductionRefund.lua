-- Approved exception: keep completed ordinary buildings and the full original
-- archive. Return their investment to production chosen by the human later.
EC_HumanProductionRefund={}
local function ordinary(row)
    return row and row.IsWonder~=true and row.IsWonder~=1
end
local function transform(original,city,api)
    assert(original.Schema==1 and original.RefundOriginal==nil and original.RefundCompleted==nil)
    local result=EC_CityPayload.Copy(original)
    local removed,entries={},{}
    for _,entry in ipairs(original.Entries) do
        local row=entry.BuildingType~=nil and api.GameInfo.Buildings[entry.BuildingType]
        if ordinary(row) and city:GetBuildings():HasBuilding(row.Index)==true then
            removed[row.BuildingType]=original.Progress[row.BuildingType] or 0
        else entries[#entries+1]=EC_CityPayload.Copy(entry) end
    end
    for kind,amount in pairs(original.Progress) do
        assert(type(amount)=="number" and amount>0 and amount<1000000000 and amount==amount,
            "Original human investment invalid")
        local row=api.GameInfo.Buildings[kind]
        if ordinary(row) and city:GetBuildings():HasBuilding(row.Index)==true then removed[kind]=amount end
    end
    if next(removed)==nil then return original end
    result.Entries=entries
    for kind in pairs(removed) do result.Progress[kind]=nil end
    result.RefundOriginal=EC_CityPayload.Serialize(original)
    result.RefundCompleted=removed
    return result
end
function EC_HumanProductionRefund.Prepare(record,api)
    if api.HumanProductionRefund~=true or api.Players[record.Owner]:IsHuman()~=true then return record end
    local city=assert(api.CityManager.GetCityAt(record.X,record.Y),"Human refund city missing")
    if record.RefundOriginal then
        local original=EC_CityPayload.Deserialize(record.RefundOriginal)
        local expected=transform(original,city,api)
        assert(EC_CityPayload.Equal(expected,record),"Completed-building refund archive changed")
        return record
    end
    return transform(record,city,api)
end
function EC_HumanProductionRefund.ValidateCredit(record,api)
    local city=assert(api.CityManager.GetCityAt(record.X,record.Y))
    assert(city:GetOwner()==record.Owner and api.Players[record.Owner]:IsHuman()==true)
    local original=EC_CityPayload.Deserialize(assert(record.RefundOriginal))
    local effective=transform(original,city,api)
    local investment={}
    for kind,amount in pairs(effective.RefundCompleted or {}) do if amount>0 then investment[kind]=amount end end
    assert(effective.RefundOriginal==record.RefundOriginal and #record.Entries==0
        and EC_CityPayload.Equal(investment,record.Progress),"Human refund investment conflict")
    for _,key in ipairs({"Owner","NativeID","X","Y","Turn"}) do
        assert(record[key]==original[key],"Human refund source identity changed")
    end
end
local function creditAPI(api)
    local result={}
    for key,value in pairs(api) do result[key]=value end
    result.HumanCompletedBuildingCredit=true
    result.CreditSuffix="_HUMAN_CREDIT"
    result.CreditStatus="EC_HUMAN_PRODUCTION_CREDIT_STATUS"
    return result
end
function EC_HumanProductionRefund.Read(game,key)
    return EC_AIProductionCredit.Read(game,key,"_HUMAN_CREDIT")
end
function EC_HumanProductionRefund.Schedule(city,record,api,key)
    assert(record.RefundOriginal and type(record.RefundCompleted)=="table")
    local credit=EC_CityPayload.Copy(record)
    credit.Entries={};credit.Progress={};credit.RefundCompleted=nil
    for kind,amount in pairs(record.RefundCompleted) do if amount>0 then credit.Progress[kind]=amount end end
    return EC_AIProductionCredit.Schedule(city,credit,creditAPI(api),key)
end
function EC_HumanProductionRefund.Step(city,api,key)
    return EC_AIProductionCredit.Step(city,creditAPI(api),key)
end
