-- Normal gameplay integration. Qualification and protection are supplied by
-- the same observer used by the overview; test fixtures do not authorize it.
EC_NativeVassals={}
function EC_NativeVassals.ReadArchive(game,id)
    local value=game:GetProperty("EC_NATIVE_VASSAL_"..id)
    if value and value.Format=="EC_ARCHIVE_TEXT_V1" then
        assert(value.Schema==1,"Native archive wrapper invalid")
        value=EC_CityPayload.Deserialize(value.Payload)
        assert(value.Schema==1 and value.VassalID==id,"Native archive identity invalid")
    elseif value then
        assert(value.State~="ATTACHING" and value.State~="RESTORING",
            "Legacy in-progress archive has no exact receipt; preserve it without replay")
    end
    return value
end
function EC_NativeVassals.Create(api,options)
    local self={}
    local function archive(id) return EC_NativeVassals.ReadArchive(api.Game,id) end
    local function store(id,value)
        api.Game:SetProperty("EC_NATIVE_VASSAL_"..id,{Schema=1,Format="EC_ARCHIVE_TEXT_V1",
            Payload=EC_CityPayload.Serialize(value)})
        assert(EC_CityPayload.Equal(archive(id),value),"Native vassal receipt unavailable")
    end
    local function status(id,reason)
        api.Players[id]:SetProperty("EC_NATIVE_OPERATION_STATUS",reason)
        if reason=="COMMITTED" then api.Players[id]:SetProperty("EC_NATIVE_OPERATION_PHASE","COMPLETE") end
    end
    local function nextToken(action,id,lord)
        local serial=api.Game:GetProperty("EC_NATIVE_REQUEST_SERIAL") or 0
        assert(type(serial)=="number" and serial>=0 and serial<1000000000 and serial==math.floor(serial))
        api.Game:SetProperty("EC_NATIVE_REQUEST_SERIAL",serial+1)
        assert(api.Game:GetProperty("EC_NATIVE_REQUEST_SERIAL")==serial+1)
        return "EC_"..action.."_"..id.."_"..lord.."_"..serial
    end
    local function request(id,action,lord,turn,series,force)
        local p=api.Players[id]
        local old=p:GetProperty("EC_NATIVE_REQUEST")
        if old~=nil then
            assert(old.Schema==1 and old.TargetID==id,"Native request conflict")
            if old.State=="ACCEPTED" then
                local active=archive(id)
                -- Older versions consumed consent before qualification failed.
                -- No archive means no transaction intent or engine write began.
                -- An existing matching intent always keeps its original token.
                if active==nil or (active.Plan and active.Plan.TransactionToken~=old.Token
                    and ((old.Action=="ATTACH" and active.State=="INDEPENDENT")
                        or (old.Action=="RESTORE" and active.State=="VASSALIZED"))) then
                    old.State="INVALIDATED";p:SetProperty("EC_NATIVE_REQUEST",old)
                end
            end
            if old.State=="PENDING" and turn>=old.ExpiresTurn then
                old.State="EXPIRED"; p:SetProperty("EC_NATIVE_REQUEST",old)
            end
            if old.Action==action and old.OverlordID==lord and old.Series==series
                and (not force or old.State=="PENDING" or old.State=="ACCEPTED") then return old end
            if old.State=="PENDING" then old.State="INVALIDATED"; p:SetProperty("EC_NATIVE_REQUEST",old) end
        end
        local value={Schema=1,Mode="LIVE_TEST",Action=action,State="PENDING",TargetID=id,
            OverlordID=lord,Turn=turn,ExpiresTurn=turn+options.ConsentTurns(),Series=series,
            Token=nextToken(action,id,lord)}
        p:SetProperty("EC_NATIVE_REQUEST",value)
        assert(EC_CityPayload.Equal(p:GetProperty("EC_NATIVE_REQUEST"),value))
        return value
    end
    local function apply(id,row)
        local plan=row.Plan
        local journal=EC_VassalTransaction.CreateJournal(api.Game,plan.TransactionToken)
        local ok,reason=EC_VassalTransaction.Apply(plan,EC_NativeCityAdapter.Create(api,plan),journal)
        status(id,reason)
        if reason=="PRODUCTION_PENDING" then
            local phases={}
            for _,city in ipairs(plan.Cities) do
                local receipt=api.Game:GetProperty("EC_NATIVE_PRODUCTION_"..plan.TransactionToken.."_"..city.CityID)
                if type(receipt)=="string" then receipt=EC_CityPayload.Deserialize(receipt) end
                phases[#phases+1]=receipt and receipt.State or "UI_PENDING"
            end
            api.Players[id]:SetProperty("EC_NATIVE_OPERATION_PHASE",table.concat(phases,"|"))
        end
        if ok then
            row.State=plan.Action=="ATTACH" and "VASSALIZED" or "INDEPENDENT"
            options.Published(id,row)
            store(id,row)
        end
        return ok,reason
    end
    function self.Attach(id,lord,consent)
        assert(options.Enabled(),"Native vassal mode disabled")
        local previous=archive(id)
        assert(previous==nil or previous.State=="INDEPENDENT","Native archive already active")
        if previous and api.HumanProductionRefund==true and api.Players[id]:IsHuman()==true then
            for _,city in ipairs(previous.Plan.Cities) do
                if city.ProductionArchive.RefundOriginal then
                    local key="EC_NATIVE_PRODUCTION_"..previous.Plan.TransactionToken.."_"..city.CityID
                    local credit=EC_HumanProductionRefund.Read(api.Game,key)
                    assert(credit and credit.State=="COMPLETE" and credit.Remaining==0,
                        "Previous human building refund unresolved; preserve its archive")
                end
            end
        end
        if previous and api.AIProductionCredit==true and api.Players[id]:IsHuman()==false then
            assert(previous.Plan and previous.Plan.Action=="RESTORE","Previous AI restoration identity unavailable")
            for _,city in ipairs(previous.OriginalCities) do
                local investment=EC_AIProductionCredit.Validate(city.ProductionArchive,api)
                if investment>0 then
                    local key="EC_NATIVE_PRODUCTION_"..previous.Plan.TransactionToken.."_"..city.CityID
                    local credit=EC_AIProductionCredit.Read(api.Game,key)
                    assert(credit and credit.State=="COMPLETE" and credit.Delivered==investment
                        and credit.Remaining==0,"Previous AI production credit unresolved; preserve its archive")
                end
            end
        end
        local result,context=options.Candidate(id,lord)
        assert(result and result.Eligible,"Native candidate not qualified")
        local lifecycle=EC_NativeLifecycle.Create(api)
        local target,overlord=lifecycle.GetParty(id),lifecycle.GetParty(lord)
        local turn=api.Game.GetCurrentGameTurn()
        local token=target.Human and assert(consent and consent.Token) or nextToken("ATTACH",id,lord)
        local cities=EC_NativeCityAdapter.CaptureCities(api,id)
        for _,city in ipairs(cities) do EC_ProductionRestore.Validate(city.ProductionArchive,api) end
        local input={Action="ATTACH",Mode="LIVE_TEST",ObservationOnly=false,SinglePlayer=true,
            Turn=turn,TransactionToken=token,OverlordID=lord,VassalID=id,Overlord=overlord,Vassal=target,
            NativeLifecycle=true,QueuePolicy="ARCHIVE_PAUSE",Cities=cities,
            Units=EC_NativeCityAdapter.CaptureUnits(api,id),Candidate=result,
            Protected=context.Protected,AtWar=context.AtWar,WarStartTurn=context.WarStartTurn,
            KeyVictory=context.KeyVictory,Consent=consent}
        local plan,reason=EC_VassalTransaction.BuildAttachPlan(input)
        assert(plan,reason)
        EC_NativeCityAdapter.Create(api,plan)
        local metrics=assert(options.Metrics(id),"Native vassal baseline unavailable")
        local lordMetrics=assert(options.Metrics(lord),"Native overlord baseline unavailable")
        local initialProject=assert(options.Project(id,lord,metrics,lordMetrics),"Native project initialization unavailable")
        local row={Schema=1,State="ATTACHING",OverlordID=lord,VassalID=id,Plan=plan,
            OriginalCities=EC_CityPayload.Copy(cities),Metrics=metrics,CreatedTurn=turn,
            InitialProject=initialProject}
        store(id,row)
        return apply(id,row)
    end
    function self.Restore(id,consent)
        assert(options.Enabled(),"Native vassal mode disabled")
        local row=assert(archive(id))
        assert(row.Schema==1 and row.State=="VASSALIZED" and row.VassalID==id)
        local lifecycle=EC_NativeLifecycle.Create(api)
        local target,overlord=lifecycle.GetParty(id),lifecycle.GetParty(row.OverlordID)
        local turn=api.Game.GetCurrentGameTurn()
        local token=target.Human and assert(consent and consent.Token) or nextToken("RESTORE",id,row.OverlordID)
        local authorization=options.Autonomy(id,row,token,consent~=nil)
        assert(authorization and authorization.Eligible,authorization and authorization.Reason or "Autonomy unavailable")
        local cities={}
        for _,original in ipairs(row.OriginalCities) do
            local city=assert(api.CityManager.GetCityAt(original.X,original.Y),"Archived city missing")
            assert(city:GetOwner()==row.OverlordID and city:GetOriginalOwner()==original.OriginalOwner)
            local current=EC_CityPayload.Capture(city,api,original.CityID)
            current.Capital=original.Capital
            current.ProductionArchive=EC_CityPayload.Copy(original.ProductionArchive)
            if api.HumanProductionRefund==true then
                current.ProductionArchive=EC_HumanProductionRefund.Prepare(current.ProductionArchive,api)
            end
            local capture=api.CaptureConstructionQueue or api.CaptureProduction
            local production=assert(capture(city:GetOwner(),city:GetID(),city:GetX(),city:GetY()),
                "Current construction snapshot unavailable")
            current.Construction=EC_CityPayload.CaptureConstruction(city,api,production)
            cities[#cities+1]=current
        end
        local plan,reason=EC_VassalTransaction.BuildRestorePlan({Action="RESTORE",Mode="LIVE_TEST",
            ObservationOnly=false,SinglePlayer=true,Turn=turn,TransactionToken=token,
            OverlordID=row.OverlordID,VassalID=id,Overlord=overlord,Vassal=target,
            NativeLifecycle=true,QueuePolicy="ARCHIVE_PAUSE",Authorization=authorization.Authorization,
            Archive={SchemaVersion=1,State="VASSALIZED",OverlordID=row.OverlordID,VassalID=id,
                UnitsRemoved=true,Cities=cities,CapitalCityID=row.Plan.CapitalCityID}})
        assert(plan,reason)
        EC_NativeCityAdapter.Create(api,plan)
        row.Plan=plan; row.State="RESTORING"
        store(id,row)
        return apply(id,row)
    end
    function self.Respond(actor,parameters)
        if not options.Enabled() or type(parameters)~="table" or parameters.ForPlayer~=actor
            or actor~=options.HumanID() then return end
        local target=parameters.TargetID
        if type(target)~="number" or target~=actor then return end
        local p=api.Players[target]
        local value=p:GetProperty("EC_NATIVE_REQUEST")
        if type(value)~="table" or value.Schema~=1 or value.Mode~="LIVE_TEST" or value.State~="PENDING"
            or value.TargetID~=actor or value.Token~=parameters.Token or value.OverlordID~=parameters.Overlord
            or value.Action~=parameters.Action then return end
        local turn=api.Game.GetCurrentGameTurn()
        if turn<value.Turn or turn>=value.ExpiresTurn then
            value.State="EXPIRED"; p:SetProperty("EC_NATIVE_REQUEST",value); return
        end
        if parameters.Decision~="ACCEPT" and parameters.Decision~="REJECT" and parameters.Decision~="CANCEL" then return end
        if parameters.Decision=="ACCEPT" and value.Action=="ATTACH" then
            local candidate=options.Candidate(actor,value.OverlordID)
            if not candidate or not candidate.Eligible then
                value.State="INVALIDATED";p:SetProperty("EC_NATIVE_REQUEST",value)
                status(actor,"QUALIFICATION_CHANGED:"..tostring(candidate and candidate.Reason or "SNAPSHOT_UNAVAILABLE"))
                return
            end
        end
        value.State=parameters.Decision=="ACCEPT" and "ACCEPTED" or parameters.Decision=="REJECT" and "REJECTED" or "CANCELLED"
        p:SetProperty("EC_NATIVE_REQUEST",value)
        assert(EC_CityPayload.Equal(p:GetProperty("EC_NATIVE_REQUEST"),value))
        if value.State=="ACCEPTED" then
            if value.Action=="ATTACH" then self.Attach(actor,value.OverlordID,value)
            elseif value.Action=="RESTORE" then self.Restore(actor,value) end
        end
    end
    function self.Operate(actor,parameters)
        if not options.Enabled() or actor~=options.HumanID() or type(parameters)~="table"
            or parameters.ForPlayer~=actor then return end
        local id=parameters.TargetID
        if type(id)~="number" or id<0 or id>=64 or id~=math.floor(id) or not api.Players[id] then return end
        local turn=api.Game.GetCurrentGameTurn()
        if parameters.Action=="ATTACH" then
            local lord=parameters.Overlord
            if lord~=actor and id~=actor then return end
            local observation=EC_DataStore.ReadObservation(api.Players[id])
            local candidate=options.Candidate(id,lord)
            if not observation or not observation.Active or not candidate or not candidate.Eligible then return end
            if api.Players[id]:IsHuman() then request(id,"ATTACH",lord,turn,observation.Ledger.SinceTurn,true)
            else self.Attach(id,lord) end
        elseif parameters.Action=="RESTORE" then
            local row=archive(id)
            if not row or row.Schema~=1 or row.State~="VASSALIZED" or (actor~=id and actor~=row.OverlordID) then return end
            local autonomy=options.Autonomy(id,row,"EC_AUTONOMY_PROBE",false)
            if not autonomy or (not autonomy.Eligible and autonomy.Reason~="PLAYER_CONFIRMATION_REQUIRED") then return end
            if api.Players[id]:IsHuman() then request(id,"RESTORE",row.OverlordID,turn,row.CreatedTurn,true)
            else self.Restore(id) end
        end
    end
    function self.ChooseProject(actor,parameters)
        if not options.Enabled() or actor~=options.HumanID() or type(parameters)~="table"
            or parameters.ForPlayer~=actor or parameters.TargetID~=actor then return end
        local row=archive(actor)
        if not row or row.Schema~=1 or row.State~="VASSALIZED" then return end
        local project=parameters.Project
        if project~="SUPPORT_OVERLORD" and project~="WEAKEN_OVERLORD" then return end
        local p=api.Players[actor]
        local prefix="EC_VASSAL_"..actor.."_"
        local pending,applied=p:GetProperty(prefix.."PROJECT_PENDING_TOKEN"),p:GetProperty(prefix.."PROJECT_APPLIED_TOKEN")
        if type(pending)~="number" or type(applied)~="number" or pending>applied then return end
        local effect=p:GetProperty(prefix.."PROJECT_EFFECT_STATE")
        if effect~="NONE" and effect~="APPLIED" and effect~="CAPPED" then return end
        p:SetProperty(prefix.."PROJECT",project)
        assert(p:GetProperty(prefix.."PROJECT")==project)
    end
    function self.Tick()
        if not options.Enabled() then return end
        local turn=api.Game.GetCurrentGameTurn()
        for id=0,63 do
            local player=api.Players[id]
            if player and player:IsMajor() and player:IsAlive() then
                local ok,reason=pcall(function()
                    local row=archive(id)
                    if row~=nil then
                        assert(row.Schema==1 and row.VassalID==id,"Native archive schema invalid")
                        if row.State=="RESTORING" then apply(id,row); return end
                        if row.State=="ATTACHING" then apply(id,row); return end
                        if row.State=="VASSALIZED" then
                            local autonomy=options.Autonomy(id,row,"EC_AUTONOMY_PROBE",false)
                            if autonomy and (autonomy.Eligible or autonomy.Reason=="PLAYER_CONFIRMATION_REQUIRED") then
                                if api.Players[id]:IsHuman() then request(id,"RESTORE",row.OverlordID,turn,row.CreatedTurn)
                                else self.Restore(id) end
                            end
                            return
                        end
                        assert(row.State=="INDEPENDENT","Native archive state invalid")
                    end
                    local observation=EC_DataStore.ReadObservation(api.Players[id])
                    if not observation or not observation.Active then return end
                    local lord=observation.Ledger.OverlordID
                    local candidate=options.Candidate(id,lord)
                    if candidate and candidate.Eligible then
                        if api.Players[id]:IsHuman() then request(id,"ATTACH",lord,turn,observation.Ledger.SinceTurn)
                        else self.Attach(id,lord) end
                    end
                end)
                if not ok then status(id,tostring(reason)); options.Log("native_vassal_blocked player="..id.." reason="..tostring(reason)) end
            end
        end
    end
    return self
end
