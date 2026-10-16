-- The engine evaluates the additional team requirement. Only the awakened
-- AI receives a marker; normal human victory requirements remain enabled.
EC_NativeVictory={}
local function IsTerminal(api,context,locked)
    if context.Stage~="RESOLVED" or locked then return false end
    local winner=api.Game.GetWinningTeam()
    if type(winner)=="number" and winner>=0 and winner%1==0 then
        return true,"NATIVE_VICTORY_RESOLVED"
    end
    -- Defeated teams also lose their runtime victory requirement objects.
    -- This runs only after the marker receipt and actual resource agree.
    local player=api.Players[context.PlayerID]
    if player:IsAlive()==false and player:GetCities():GetCount()==0 then
        return true,"NATIVE_CANDIDATE_DEFEATED"
    end
    return false
end
local function VerifyGate(api,player,locked)
    local checked=0
    for victory in api.GameInfo.Victories() do
        local root=api.Game.GetVictoryRequirements(player:GetTeam(),victory.Index)
        if root~=nil and root~=-1 then
            local found=0
            for _,inner in ipairs(api.GameEffects.GetRequirementSetInnerRequirements(root)) do
                if api.GameEffects.GetRequirementDefinition(inner).Id=="EC_TEAM_NO_VICTORY_LOCK" then
                    found=found+1
                    local state=api.GameEffects.GetRequirementState(inner)
                    if state~=(locked and "NotMet" or "Met") then return false,"ENGINE_GATE_PENDING" end
                end
            end
            assert(found==1,"Native victory gate missing or duplicated")
            checked=checked+1
        end
    end
    assert(checked>0,"Native victory requirements unavailable")
    return true
end
function EC_NativeVictory.Update(api,context)
    assert(context.SinglePlayer==true and context.Enabled==true)
    assert(type(context.PlayerID)=="number" and context.PlayerID>=0 and context.PlayerID<64
        and context.PlayerID%1==0)
    assert(type(context.Turn)=="number" and context.Turn>=0 and context.Turn%1==0)
    local player=assert(api.Players[context.PlayerID])
    local marker=assert(api.GameInfo.Resources.RESOURCE_EC_VICTORY_LOCK,"Native victory rule not loaded")
    local locked=context.Stage=="TRIGGERED" or context.Stage=="PREPARATION" or context.Stage=="CONQUEST"
    assert(locked or context.Stage=="SHOWDOWN" or context.Stage=="RESOLVED","Victory stage unknown")
    if locked then assert(player:IsAlive() and player:IsMajor() and player:IsHuman()==false) end
    local resources=player:GetResources()
    local key="EC_NATIVE_VICTORY_RESOURCE_LOCK_"..context.PlayerID
    local receipt=api.Game:GetProperty(key)
    local quantity=resources:GetResourceAmount(marker.Index)
    assert(quantity==0 or quantity==1,"Native victory marker quantity unknown")
    local actual=quantity==1
    if receipt then
        assert(receipt.Schema==1 and receipt.PlayerID==context.PlayerID and type(receipt.Locked)=="boolean")
        if receipt.State=="PENDING" then
            assert(actual==receipt.Locked,"Unknown victory marker intent; no automatic replay")
            receipt.State="COMPLETE"; api.Game:SetProperty(key,receipt)
        else assert(receipt.State=="COMPLETE" and actual==receipt.Locked,"Victory marker receipt conflict") end
    else assert(actual==false,"Unowned native victory marker") end
    if actual==locked then
        -- The engine destroys victory requirement objects after TeamVictory.
        -- A real winner plus the released resource is the terminal receipt.
        local terminal,terminalReason=IsTerminal(api,context,actual)
        if terminal then return true,terminalReason end
        local verified,reason=VerifyGate(api,player,locked)
        return verified,verified and "ALREADY_APPLIED" or reason
    end
    receipt={Schema=1,PlayerID=context.PlayerID,Locked=locked,State="PENDING",Turn=context.Turn}
    api.Game:SetProperty(key,receipt)
    assert(EC_CityPayload.Equal(receipt,api.Game:GetProperty(key)),"Victory intent unavailable")
    resources:ChangeResourceAmount(marker.Index,locked and 1 or -1)
    assert(resources:GetResourceAmount(marker.Index)==(locked and 1 or 0),"Native victory marker outcome unknown")
    receipt.State="COMPLETE"; api.Game:SetProperty(key,receipt)
    assert(EC_CityPayload.Equal(receipt,api.Game:GetProperty(key)),"Victory receipt unavailable")
    local terminal,terminalReason=IsTerminal(api,context,locked)
    if terminal then return true,terminalReason end
    local verified,reason=VerifyGate(api,player,locked)
    return verified,verified and (locked and "VICTORY_BLOCKED_VERIFIED" or "VICTORY_RELEASED_VERIFIED") or reason
end
