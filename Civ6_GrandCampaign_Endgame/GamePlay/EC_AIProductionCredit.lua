-- Approved AI restoration policy: retain the archive, let native AI choose,
-- and add the original investment once. Never overwrite its new production.
EC_AIProductionCredit={}
local function finite(value)
    return type(value)=="number" and value==value and value>=0 and value<1000000000
end
local function knownType(kind,api)
    for _,group in ipairs({"Units","Buildings","Districts","Projects"}) do
        if api.GameInfo[group] and api.GameInfo[group][kind] then return true end
    end
    return false
end
function EC_AIProductionCredit.Validate(record,api)
    assert(type(record)=="table" and record.Schema==1 and type(record.Entries)=="table"
        and type(record.Progress)=="table","AI production archive invalid")
    for _,key in ipairs({"Owner","NativeID","X","Y","Turn"}) do
        assert(finite(record[key]) and record[key]==math.floor(record[key]),"AI production identity invalid")
    end
    assert(record.Owner<64,"AI production owner invalid")
    local p=assert(api.Players[record.Owner])
    local human=api.HumanCompletedBuildingCredit==true
    assert(p:IsMajor() and p:IsHuman()==human,"Production credit identity invalid")
    if human then EC_HumanProductionRefund.ValidateCredit(record,api) end
    local total=0
    for kind,amount in pairs(record.Progress) do
        assert(type(kind)=="string" and knownType(kind,api) and finite(amount) and amount>0,"AI investment invalid")
        total=total+amount
    end
    assert(finite(total),"AI investment exceeds bounds")
    return total
end
function EC_AIProductionCredit.Read(game,key,suffix)
    local text=game:GetProperty(key..(suffix or "_AI_CREDIT"))
    if text==nil then return nil end
    assert(type(text)=="string","AI credit receipt invalid")
    local row=EC_CityPayload.Deserialize(text)
    assert(row.Schema==1 and finite(row.Total) and finite(row.Remaining) and finite(row.Delivered)
        and row.Remaining+row.Delivered==row.Total
        and (row.State=="WAITING" or row.State=="SENT" or row.State=="COMPLETE" or row.State=="UNKNOWN"),
        "AI credit receipt inconsistent")
    return row
end
local function save(api,key,row)
    local text=EC_CityPayload.Serialize(row)
    local property=key..(api.CreditSuffix or "_AI_CREDIT")
    api.Game:SetProperty(property,text)
    assert(api.Game:GetProperty(property)==text,"Production credit receipt unavailable")
end
-- AddProgress takes integer base production and applies current item bonuses.
-- Read active native city subjects, not policy names or a guessed AI bonus.
function EC_AIProductionCredit.Multiplier(city,kind,api)
    local unit=api.GameInfo.Units[kind]
    local building=api.GameInfo.Buildings[kind]
    local district=api.GameInfo.Districts and api.GameInfo.Districts[kind]
    local project=api.GameInfo.Projects and api.GameInfo.Projects[kind]
    local effects=assert(api.GameEffects,"Native production effects unavailable")
    local bonus=0
    for _,instance in ipairs(effects.GetModifiers()) do
        if effects.GetModifierActive(instance)==true then
            local def=effects.GetModifierDefinition(instance)
            local db=api.GameInfo.Modifiers[def.Id]
            local dynamic=db and api.GameInfo.DynamicModifiers[db.ModifierType]
            local effect=dynamic and dynamic.EffectType
            if type(effect)=="string" and effect:find("PRODUCTION",1,true) then
                local applies=false
                for _,subject in ipairs(effects.GetModifierSubjects(instance) or {}) do
                    if effects.GetObjectsPlayerId(subject)==city:GetOwner()
                        and effects.GetObjectType(subject)=="LOC_MODIFIER_OBJECT_CITY" then
                        local native=tonumber((effects.GetObjectString(subject) or ""):match("^City %((%d+)%)"))
                        if native==city:GetID() then applies=true;break end
                    end
                end
                if applies then
                    local args=assert(def.Arguments)
                    local matches=false
                    if effect=="EFFECT_ADJUST_UNIT_TAG_ERA_PRODUCTION" then
                        if unit then
                            local era="ERA_ANCIENT"
                            for _,pair in ipairs({{"PrereqTech","Technologies"},{"PrereqCivic","Civics"}}) do
                                local prereq=unit[pair[1]] and api.GameInfo[pair[2]][unit[pair[1]]]
                                if prereq and prereq.EraType then era=prereq.EraType end
                            end
                            matches=args.UnitPromotionClass==unit.PromotionClass and args.EraType==era
                        end
                    elseif effect=="EFFECT_ADJUST_UNIT_PRODUCTION" then
                        matches=unit~=nil and args.UnitType==kind
                    elseif effect=="EFFECT_ADJUST_UNIT_DOMAIN_PRODUCTION" then
                        matches=unit~=nil and args.Domain==unit.Domain
                    elseif effect=="EFFECT_ADJUST_ALL_UNIT_PRODUCTION_MODIFIER" then
                        matches=unit~=nil
                    elseif effect=="EFFECT_ADJUST_CITY_ALL_MILITARY_UNITS_PRODUCTION" then
                        matches=unit~=nil and ((unit.Combat or 0)>0 or (unit.RangedCombat or 0)>0)
                    elseif effect=="EFFECT_ADJUST_BUILDING_PRODUCTION" then
                        matches=building~=nil and args.BuildingType==kind
                    elseif effect=="EFFECT_ADJUST_ALL_BUILDING_PRODUCTION_MODIFIER" then
                        matches=building~=nil
                    elseif effect=="EFFECT_ADJUST_DISTRICT_PRODUCTION" then
                        matches=district~=nil and args.DistrictType==kind
                    elseif effect=="EFFECT_ADJUST_ALL_DISTRICTS_PRODUCTION"
                        or effect=="EFFECT_ADJUST_ALL_DISTRICT_PRODUCTION_MODIFIER" then
                        matches=district~=nil
                    elseif effect=="EFFECT_ADJUST_PROJECT_PRODUCTION" then
                        matches=project~=nil and args.ProjectType==kind
                    elseif effect=="EFFECT_ADJUST_ALL_PROJECTS_PRODUCTION" then
                        matches=project~=nil
                    elseif effect:find("DISTRICT",1,true) and district==nil
                        and not (effect=="EFFECT_ADJUST_DISTRICT_BUILDING_PRODUCTION" and building~=nil) then
                        -- These native effect families only affect other item categories.
                    elseif effect:find("WONDER",1,true) and not (building and building.IsWonder==true) then
                    elseif effect:find("BUILDING",1,true) and building==nil then
                    elseif effect:find("PROJECT",1,true) and project==nil then
                        -- These native effect families only affect other item categories.
                    else
                        return nil,"UNSUPPORTED_PRODUCTION_MODIFIER:"..effect
                    end
                    if matches then
                        local amount=tonumber(args.Amount)
                        assert(type(amount)=="number" and amount==amount and math.abs(amount)<1000000,
                            "Native production bonus invalid")
                        bonus=bonus+amount
                    end
                end
            end
        end
    end
    local multiplier=1+bonus/100
    assert(multiplier>0 and multiplier<10000,"Native production multiplier invalid")
    return multiplier
end
-- Native UI progress is truncated: 7.5 reads back as 7. Only send a whole
-- number of base-production steps whose boosted result is also an integer.
-- Computing the step with integer percentages avoids floating-point division
-- and never counts an unseen fractional increment as delivered credit.
function EC_AIProductionCredit.ExactBatch(limit,multiplier)
    assert(finite(limit) and type(multiplier)=="number" and multiplier>0 and multiplier<10000)
    local percent=math.floor(multiplier*100+0.5)
    if math.abs(multiplier*100-percent)>0.0000001 then
        return 0,0,"NON_INTEGER_NATIVE_PRODUCTION_PERCENT"
    end
    local a,b=percent,100
    while b~=0 do a,b=b,a%b end
    local rawStep,amountStep=100/a,percent/a
    local batches=math.floor(limit/amountStep)
    if batches==0 then return 0,0,"WAITING_FOR_EXACT_PRODUCTION_BATCH" end
    return batches*rawStep,batches*amountStep
end
function EC_AIProductionCredit.Schedule(city,record,api,key)
    local total=EC_AIProductionCredit.Validate(record,api)
    local archive=EC_CityPayload.Serialize(record)
    local old=EC_AIProductionCredit.Read(api.Game,key,api.CreditSuffix)
    if old then
        assert(old.Archive==archive and old.Owner==city:GetOwner() and old.NativeID==city:GetID()
            and old.X==city:GetX() and old.Y==city:GetY(),"AI credit archive conflict")
        return true
    end
    assert(city:GetOwner()==record.Owner and city:GetX()==record.X and city:GetY()==record.Y)
    save(api,key,{Schema=1,State=total==0 and "COMPLETE" or "WAITING",Archive=archive,
        Owner=record.Owner,NativeID=city:GetID(),OriginalOwner=city:GetOriginalOwner(),X=record.X,Y=record.Y,
        Total=total,Remaining=total,Delivered=0,
        ReadyTurn=api.Game.GetCurrentGameTurn()+(api.HumanCompletedBuildingCredit==true and 0 or 2)})
    if total>0 then api.Players[record.Owner]:SetProperty(api.CreditStatus or "EC_AI_PRODUCTION_CREDIT_STATUS","PENDING") end
    return true
end
function EC_AIProductionCredit.Step(city,api,key)
    local row=assert(EC_AIProductionCredit.Read(api.Game,key,api.CreditSuffix),"Production credit not scheduled")
    local archive=EC_CityPayload.Deserialize(row.Archive)
    assert(EC_AIProductionCredit.Validate(archive,api)==row.Total and archive.Owner==row.Owner
        and archive.X==row.X and archive.Y==row.Y and finite(row.ReadyTurn)
        and row.ReadyTurn==math.floor(row.ReadyTurn),"AI credit does not match its original archive")
    assert(city:GetOwner()==row.Owner and city:GetID()==row.NativeID and city:GetOriginalOwner()==row.OriginalOwner
        and city:GetX()==row.X and city:GetY()==row.Y,"AI credited city identity changed")
    local player=api.Players[row.Owner]
    assert(player:IsAlive() and player:IsMajor() and player:IsHuman()==(api.HumanCompletedBuildingCredit==true),
        "Production credit recipient invalid")
    local lifecycle=player:GetProperty("EC_NATIVE_ARCHIVE")
    assert(type(lifecycle)=="table" and lifecycle.Schema==2 and lifecycle.State=="RESTORED",
        "AI credit waits for completed native restoration")
    if row.State=="COMPLETE" or row.State=="UNKNOWN" then return row.State end
    local turn=api.Game.GetCurrentGameTurn()
    local actual=api.PublishedProduction(row.Owner,row.NativeID,row.X,row.Y)
    if not actual or actual.Turn~=turn or actual.HumanTurnReady~=true then return row.State end
    assert(actual.Owner==row.Owner and actual.NativeID==row.NativeID and actual.X==row.X and actual.Y==row.Y
        and type(actual.Session)=="string" and finite(actual.Epoch),"AI publication identity invalid")
    local queue=city:GetBuildQueue()
    if row.State=="SENT" then
        local sent=assert(row.Current)
        assert(finite(sent.Amount) and sent.Amount>0 and sent.Amount<=row.Remaining
            and finite(sent.Before) and sent.Expected==sent.Before+sent.Amount
            and finite(sent.Cost) and sent.Expected<sent.Cost
            and finite(sent.Turn) and sent.Turn==math.floor(sent.Turn),"AI credit intent invalid")
        if actual.Session==sent.Session and actual.Epoch<=sent.Epoch then return "SENT" end
        if turn==sent.Turn and actual.Kind==sent.Kind and queue:CurrentlyBuilding()==sent.Kind
            and actual.Progress==sent.Before then return "SENT" end
        local increment=actual.Progress-sent.Before
        local minimum=sent.Minimum or sent.Amount
        local maximum=sent.Maximum or sent.Amount
        if sent.RawAmount~=nil then
            assert(finite(sent.RawAmount) and sent.RawAmount>0 and sent.RawAmount==math.floor(sent.RawAmount)
                and finite(sent.Multiplier) and sent.Multiplier>0
                and finite(minimum) and minimum<=maximum and maximum==sent.Amount,
                "AI normalized credit intent inconsistent")
            if minimum~=maximum then
                assert(minimum==math.floor(sent.RawAmount*sent.Multiplier)
                    and maximum==math.ceil(sent.RawAmount*sent.Multiplier),"Legacy AI credit intent inconsistent")
                row.State="UNKNOWN";row.Reason="LEGACY_FRACTIONAL_CREDIT_INTENT"
                save(api,key,row);return row.State
            end
            local exactRaw,exactAmount=EC_AIProductionCredit.ExactBatch(sent.Amount,sent.Multiplier)
            assert(exactRaw==sent.RawAmount and exactAmount==sent.Amount,"AI exact credit intent inconsistent")
        end
        if turn~=sent.Turn or actual.Kind~=sent.Kind or queue:CurrentlyBuilding()~=sent.Kind
            or increment<minimum or increment>maximum or increment>row.Remaining then
            row.State="UNKNOWN";row.Reason="NATIVE_CREDIT_OUTCOME_UNKNOWN";save(api,key,row)
            return row.State
        end
        row.Delivered=row.Delivered+increment;row.Remaining=row.Total-row.Delivered
        row.Current.ActualIncrement=increment
        row.State=row.Remaining==0 and "COMPLETE" or "WAITING"
        save(api,key,row)
        return row.State
    end
    if turn<row.ReadyTurn or actual.Kind=="NONE" then return "WAITING" end
    assert(knownType(actual.Kind,api) and finite(actual.Progress) and finite(actual.Cost)
        and queue:CurrentlyBuilding()==actual.Kind,"AI active production identity unavailable")
    -- Native AddProgress also consumes stored overflow, even with amount 0
    -- (actual probe: an AI's new Warrior 0 -> 18). Establish the real baseline
    -- before adding credit. Persist the zero intent too; a lost response never
    -- repeats it in this turn and cannot count as delivered compensation.
    if actual.Progress==0 then
        local prime=row.Prime
        if prime and prime.Turn==turn then return "WAITING" end
        row.Prime={Turn=turn,Kind=actual.Kind,Session=actual.Session,Epoch=actual.Epoch,Amount=0}
        save(api,key,row)
        queue:AddProgress(0)
        return "WAITING"
    end
    -- Keep one point below completion so the next publication can prove the
    -- exact increment. Remaining credit follows AI to its later projects.
    local capacity=actual.Cost-actual.Progress-1
    if capacity<=0 then return "WAITING" end
    local multiplier,reason=EC_AIProductionCredit.Multiplier(city,actual.Kind,api)
    if not multiplier then
        row.Reason=reason;save(api,key,row);return "WAITING"
    end
    local raw,amount,batchReason=EC_AIProductionCredit.ExactBatch(math.min(row.Remaining,capacity),multiplier)
    if raw<=0 then row.Reason=batchReason;save(api,key,row);return "WAITING" end
    row.State="SENT"
    row.Reason=nil
    row.Current={Kind=actual.Kind,Before=actual.Progress,Amount=amount,Expected=actual.Progress+amount,
        Minimum=amount,Maximum=amount,RawAmount=raw,Multiplier=multiplier,
        Cost=actual.Cost,Turn=turn,Session=actual.Session,Epoch=actual.Epoch}
    save(api,key,row)
    queue:AddProgress(raw)
    return "SENT"
end
