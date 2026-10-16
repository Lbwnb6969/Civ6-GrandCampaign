-- Each engine request has a persisted intent. Pending requests are observed,
-- never sent again after a callback, reload, or an uncertain outcome.
EC_ProductionRestore={}
local function entryType(entry,api)
    for _,group in ipairs({{"UnitType","Units","UnitType"},{"BuildingType","Buildings","BuildingType"},
        {"DistrictType","Districts","DistrictType"},{"ProjectType","Projects","ProjectType"}}) do
        if entry[group[1]]~=nil then
            return assert(api.GameInfo[group[2]][entry[group[1]]])[group[3]]
        end
    end
    error("Unsupported archived production directive")
end

local function exactGrant(city,kind,amount,api)
    assert(type(amount)=="number" and amount>0 and amount<math.huge and amount==math.floor(amount),
        "Fractional production requires a verified precise native write")
    local multiplier,reason=EC_AIProductionCredit.Multiplier(city,kind,api)
    assert(multiplier,reason)
    -- UI truncates native fractional investment: raw 5 with a 50% bonus
    -- displays 7 but stores 7.5 (City_BuildQueue.csv). Do not award that extra
    -- fraction or accept an integer publication as a precise native grant.
    local raw,delivered=EC_AIProductionCredit.ExactBatch(amount,multiplier)
    assert(raw>0 and delivered==amount,
        "Investment has no exact integer native grant under current bonuses")
    return raw,multiplier
end

local function dormantStages(record,api)
    local active=record.Entries[1] and entryType(record.Entries[1],api)
    local dormant=false
    for kind in pairs(record.Progress) do if kind~=active then dormant=true end end
    if not dormant then return nil end
    local stages={}
    for kind,amount in pairs(record.Progress) do
        assert(type(amount)=="number" and amount>0 and amount<math.huge and amount==math.floor(amount),
            "Fractional production requires a verified precise native write")
        local entry
        for _,item in ipairs(record.Entries) do
            if entryType(item,api)==kind then entry=EC_CityPayload.Copy(item);break end
        end
        if not entry then
            for _,group in ipairs({{"Units","UnitType"},{"Buildings","BuildingType"},{"Projects","ProjectType"}}) do
                local row=api.GameInfo[group[1]] and api.GameInfo[group[1]][kind]
                if row then
                    assert(not row.IsWonder,"Dormant wonder restoration requires captured placement")
                    entry={[group[2]]=row.Index};break
                end
            end
        end
        assert(entry,"Dormant production placement unavailable")
        stages[#stages+1]={Kind=kind,Amount=amount,Entry=entry}
    end
    table.sort(stages,function(a,b) return a.Kind<b.Kind end)
    return stages
end

function EC_ProductionRestore.Validate(record,api)
    assert(type(record)=="table" and record.Schema==1 and type(record.Entries)=="table"
        and type(record.Progress)=="table","Production archive invalid")
    for _,key in ipairs({"Owner","NativeID","X","Y","Turn"}) do
        local value=record[key]
        assert(type(value)=="number" and value>=0 and value<math.huge and value==math.floor(value),"Production identity invalid")
    end
    assert(record.Owner<64 and #record.Entries<=16,"Production archive exceeds bounds")
    local count=0
    for key in pairs(record.Entries) do
        assert(type(key)=="number" and key>=1 and key<=#record.Entries and key==math.floor(key),"Sparse production queue")
        count=count+1
    end
    assert(count==#record.Entries,"Incomplete production queue")
    if record.RefundOriginal then
        assert(api.HumanProductionRefund==true,"Human completed-building policy unavailable")
        EC_HumanProductionRefund.Prepare(record,api)
    end
    for _,entry in ipairs(record.Entries) do entryType(entry,api) end
    if api.AIProductionCredit==true and api.Players[record.Owner]:IsHuman()==false then
        EC_AIProductionCredit.Validate(record,api)
        return true
    end
    assert(api.CanRestoreProduction(record.Owner,record),"Native non-local production restore unavailable")
    local stages=dormantStages(record,api)
    if stages then
        if #record.Entries==0 then
            assert(api.CanRestoreProduction(record.Owner,record,true),"Native empty-queue restoration unavailable")
        end
        for _,stage in ipairs(stages) do
            local temporary=EC_CityPayload.Copy(record);temporary.Entries={EC_CityPayload.Copy(stage.Entry)}
            assert(api.CanRestoreProduction(record.Owner,temporary,true),"Dormant production is no longer legally buildable")
        end
        return true
    end
    local active=record.Entries[1] and entryType(record.Entries[1],api)
    -- The supported native AddProgress path addresses the active item. Do not
    -- silently discard dormant production or change the archived queue.
    for kind,progress in pairs(record.Progress) do
        assert(kind==active and type(progress)=="number" and progress>0 and progress<math.huge
            and progress==math.floor(progress),
            "Dormant production restore requires a native type-specific path")
    end
    for _,entry in ipairs(record.Entries) do entryType(entry,api) end
    if #record.Entries>0 then
        assert(api.CanRestoreProduction(record.Owner,record,true),"Archived production is no longer legally buildable")
    end
    return true
end

local function restoreDormant(city,record,api,key,stages,actual)
    local text=api.Game:GetProperty(key)
    local receipt=text and EC_CityPayload.Deserialize(assert(type(text)=="string" and text,
        "Multi-type production receipt invalid")) or nil
    local function save()
        local value=EC_CityPayload.Serialize(receipt)
        api.Game:SetProperty(key,value)
        assert(api.Game:GetProperty(key)==value,"Multi-type production receipt unavailable")
    end
    local function temporary(stage)
        local row=EC_CityPayload.Copy(record);row.Entries={EC_CityPayload.Copy(stage.Entry)}
        return row
    end
    if not receipt then
        assert(#actual.Entries==0 and next(actual.Progress)==nil,"Restored city production already changed")
        receipt={Schema=2,Archive=EC_CityPayload.Serialize(record),NativeID=city:GetID(),State="QUEUE_SENT",
            Index=1,Completed={}}
        save()
        api.RequestProduction(temporary(stages[1]))
        return "PENDING"
    end
    assert(receipt.Schema==2 and receipt.NativeID==city:GetID()
        and receipt.Archive==EC_CityPayload.Serialize(record),"Multi-type production archive conflict")
    assert(type(receipt.Index)=="number" and receipt.Index==math.floor(receipt.Index)
        and receipt.Index>=1 and receipt.Index<=#stages and type(receipt.Completed)=="table")
    if receipt.State=="COMPLETE" then
        assert(EC_CityPayload.Equal(actual.Entries,record.Entries)
            and EC_ProductionArchive.ProgressMatches(actual,record),"Completed production changed")
        return true
    end
    if receipt.State=="FINAL_QUEUE_SENT" then
        if not EC_CityPayload.Equal(actual.Entries,record.Entries) then return "PENDING" end
        assert(EC_ProductionArchive.ProgressMatches(actual,record),"Final dormant progress changed")
        receipt.State="COMPLETE";save();return true
    end
    local stage=assert(stages[receipt.Index])
    local current=actual.Entries[1]
    if #actual.Entries~=1 or entryType(current,api)~=stage.Kind then return "PENDING" end
    assert((current.MilitaryFormationType or 0)==(stage.Entry.MilitaryFormationType or 0)
        and (current.Modifiers or 0)==(stage.Entry.Modifiers or 0),"Temporary production modifiers changed")
    if stage.Entry.Location and stage.Entry.Location.x>=0 and stage.Entry.Location.y>=0 then
        assert(EC_CityPayload.Equal(current.Location,stage.Entry.Location),"Temporary production placement changed")
    end
    assert(city:GetBuildQueue():CurrentlyBuilding()==stage.Kind,"Temporary native production identity changed")
    if receipt.State=="QUEUE_SENT" then
        assert(EC_CityPayload.Equal(actual.Progress,receipt.Completed),"Production changed before staged grant")
        local raw,multiplier=exactGrant(city,stage.Kind,stage.Amount,api)
        receipt.State="PROGRESS_SENT";receipt.RawAmount=raw;receipt.Multiplier=multiplier
        save();city:GetBuildQueue():AddProgress(raw);return "PENDING"
    end
    assert(receipt.State=="PROGRESS_SENT","Unknown staged production phase")
    local expected=EC_CityPayload.Copy(receipt.Completed);expected[stage.Kind]=stage.Amount
    if not EC_CityPayload.Equal(actual.Progress,expected) then return "PENDING" end
    receipt.Completed=expected;receipt.RawAmount=nil;receipt.Multiplier=nil
    if receipt.Index<#stages then
        receipt.Index=receipt.Index+1;receipt.State="QUEUE_SENT";save()
        api.RequestProduction(temporary(stages[receipt.Index]),true)
    else
        receipt.State="FINAL_QUEUE_SENT";save();api.RequestProduction(record,true)
    end
    return "PENDING"
end

function EC_ProductionRestore.Step(city,record,api,key)
    assert(city:GetOwner()==record.Owner and city:GetX()==record.X and city:GetY()==record.Y)
    if record.RefundOriginal then
        assert(api.HumanProductionRefund==true,"Human completed-building policy unavailable")
        EC_HumanProductionRefund.Prepare(record,api)
    end
    if api.AIProductionCredit==true and api.Players[record.Owner]:IsHuman()==false then
        return EC_AIProductionCredit.Schedule(city,record,api,key)
    end
    local receipt=api.Game:GetProperty(key)
    local actual=api.CaptureProduction(city:GetOwner(),city:GetID(),city:GetX(),city:GetY())
    if actual==nil then return "PENDING" end
    local stages=dormantStages(record,api)
    if stages then
        EC_ProductionRestore.Validate(record,api)
        local result=restoreDormant(city,record,api,key,stages,actual)
        if result==true and record.RefundOriginal then EC_HumanProductionRefund.Schedule(city,record,api,key) end
        return result
    end
    local function save(value)
        api.Game:SetProperty(key,EC_CityPayload.Copy(value))
        assert(EC_CityPayload.Equal(api.Game:GetProperty(key),value),"Production receipt unavailable")
    end
    if receipt==nil then
        EC_ProductionRestore.Validate(record,api)
        assert(#actual.Entries==0 and next(actual.Progress)==nil,"Restored city production already changed")
        receipt={Schema=1,Archive=EC_CityPayload.Encode(record),NativeID=city:GetID(),State="QUEUE_SENT"}
        save(receipt)
        if #record.Entries>0 then api.RequestProduction(record) end
        return "PENDING"
    end
    assert(receipt.Schema==1 and receipt.NativeID==city:GetID()
        and receipt.Archive==EC_CityPayload.Encode(record),"Production receipt conflict")
    if receipt.State=="QUEUE_SENT" then
        if not EC_CityPayload.Equal(actual.Entries,record.Entries) then return "PENDING" end
        local kind=record.Entries[1] and entryType(record.Entries[1],api)
        local progress=kind and (record.Progress[kind] or 0) or 0
        assert(next(actual.Progress)==nil or EC_ProductionArchive.ProgressMatches(actual,record),
            "Production changed before progress restoration")
        if progress>0 and not EC_ProductionArchive.ProgressMatches(actual,record) then
            assert(city:GetBuildQueue():CurrentlyBuilding()==kind,"Active production identity changed")
            local raw,multiplier=exactGrant(city,kind,progress,api)
            receipt.State="PROGRESS_SENT";receipt.RawAmount=raw;receipt.Multiplier=multiplier
            save(receipt)
            city:GetBuildQueue():AddProgress(raw)
            return "PENDING"
        end
        receipt.State="COMPLETE"
        save(receipt)
    elseif receipt.State=="PROGRESS_SENT" then
        if not EC_CityPayload.Equal(actual.Entries,record.Entries)
            or not EC_ProductionArchive.ProgressMatches(actual,record) then return "PENDING" end
        receipt.State="COMPLETE"
        save(receipt)
    end
    assert(receipt.State=="COMPLETE" and EC_CityPayload.Equal(actual.Entries,record.Entries)
        and EC_ProductionArchive.ProgressMatches(actual,record),"Production restoration outcome unknown")
    if record.RefundOriginal then EC_HumanProductionRefund.Schedule(city,record,api,key) end
    return true
end
