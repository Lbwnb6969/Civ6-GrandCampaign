include("PopupDialog")

local dialog = PopupDialog:new("EC_ConsentPopup")
local active = nil
local sentToken = nil
local deferredToken = nil
local unpackValues = table.unpack or unpack

local function Missing(value, key)
    return type(value) ~= "string" or value == ""
        or (type(key) == "string" and string.match(key, "^LOC_") ~= nil and value == key)
        or string.find(value, "TRANSLATION MISSING", 1, true) ~= nil
        or string.match(value, "^LOC_[A-Z0-9_]+$") ~= nil
end
local function Localized(key, fallback, ...)
    local values = { ... }
    local ok, value = pcall(function() return Locale.Lookup(key, unpackValues(values)) end)
    if ok and not Missing(value, key) then return value end
    if #values > 0 then
        local formatted, formattedValue = pcall(function() return string.format(fallback, unpackValues(values)) end)
        if formatted and not Missing(formattedValue, key) then return formattedValue end
    end
    return fallback
end

local function Integer(value)
    return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

local function Safe(callback)
    local ok, value = pcall(callback)
    return value, ok
end

local function ReadMember(object, memberName)
    if object == nil then return nil, false end
    local ok, value = pcall(function() return object[memberName] end)
    return value, ok
end

local function BindEvent(name, handler)
    local event, readable = ReadMember(Events, name)
    local add, callable = ReadMember(event, "Add")
    if readable and callable and type(add) == "function" then
        pcall(function() add(handler) end)
    end
end

local function UnbindEvent(name, handler)
    local event, readable = ReadMember(Events, name)
    local remove, callable = ReadMember(event, "Remove")
    if readable and callable and type(remove) == "function" then
        pcall(function() remove(handler) end)
    end
end

local function Enabled()
    local observation = GameConfiguration.GetValue("EC_OBSERVATION_ONLY")
    local test = GameConfiguration.GetValue("EC_PLAYER_CONSENT_TEST")
    return (observation == false or observation == 0 or observation == "0" or observation == "false")
        and (test == true or test == 1 or test == "1" or test == "true")
end

local function ReadNativeRequest()
    local observation=GameConfiguration.GetValue("EC_OBSERVATION_ONLY")
    local mode=GameConfiguration.GetValue("EC_NATIVE_VASSAL_TEST")
    if not (observation==false or observation==0 or observation=="0")
        or not (mode==true or mode==1 or mode=="1")
        or GameConfiguration.IsAnyMultiplayer()~=false then return nil end
    local id=Game.GetLocalPlayer()
    if not Integer(id) or id>=64 or not Players[id] or not Players[id]:IsHuman() or not Players[id]:IsAlive()
        or Players[id]:IsTurnActive()~=true then return nil end
    local value=Players[id]:GetProperty("EC_NATIVE_REQUEST")
    local turn=Game.GetCurrentGameTurn()
    if type(value)~="table" or value.Schema~=1 or value.Mode~="LIVE_TEST" or value.State~="PENDING"
        or value.TargetID~=id or (value.Action~="ATTACH" and value.Action~="RESTORE")
        or type(value.Token)~="string" or #value.Token==0 or #value.Token>160
        or not Integer(value.OverlordID) or value.OverlordID>=64 or value.OverlordID==id
        or not Integer(value.Turn) or not Integer(value.ExpiresTurn) or turn<value.Turn or turn>=value.ExpiresTurn then return nil end
    return {PlayerID=id,Token=value.Token,Overlord=value.OverlordID,Expires=value.ExpiresTurn,
        Native=true,Action=value.Action}
end

local function ReadRequest()
    local native=ReadNativeRequest()
    if native then return native end
    if not Enabled() then return nil end
    local id = Game.GetLocalPlayer()
    if not Integer(id) or id >= 64 then return nil end
    local player = Players[id]
    if player == nil or player:IsHuman() ~= true or not player:IsAlive() then return nil end
    local prefix = "EC_VASSAL_" .. id .. "_CONFIRMATION_"
    if player:GetProperty(prefix .. "STATE") ~= "PLAYER_CONFIRMATION_PENDING"
        or player:GetProperty(prefix .. "SCHEMA_VERSION") ~= 1
        or player:GetProperty(prefix .. "MODE") ~= "DRY_RUN"
        or player:GetProperty(prefix .. "READY") ~= 1 then return nil end
    local token = player:GetProperty(prefix .. "TOKEN")
    local overlord = player:GetProperty(prefix .. "OVERLORD")
    local expires = player:GetProperty(prefix .. "EXPIRES_TURN")
    local created = player:GetProperty(prefix .. "CREATED_TURN")
    local turn = Game.GetCurrentGameTurn()
    if type(token) ~= "string" or token == "" or #token > 160
        or not Integer(overlord) or overlord >= 64 or overlord == id
        or not Integer(expires) or not Integer(created) or expires <= created
        or not Integer(turn) or turn < created or turn >= expires then return nil end
    return { PlayerID = id, Token = token, Overlord = overlord, Expires = expires }
end

local function Close()
    if active ~= nil then
        dialog:Close()
        UIManager:DequeuePopup(ContextPtr)
        active = nil
    end
end

local function Respond(request, decision)
    local ok, current = pcall(ReadRequest)
    Close()
    if not ok or current == nil or current.PlayerID ~= request.PlayerID
        or current.Token ~= request.Token or current.Overlord ~= request.Overlord
        or current.Native~=request.Native or current.Action~=request.Action
        or sentToken == request.Token then return end
    local submitted, message = pcall(function()
        return UI.RequestPlayerOperation(request.PlayerID, PlayerOperations.EXECUTE_SCRIPT, {
            OnStart = request.Native and "EC_NativeConsentResponse" or "EC_ConsentResponse", ForPlayer = request.PlayerID,
            Token = request.Token, Overlord = request.Overlord, Decision = decision,
            TargetID=request.PlayerID,Action=request.Action,
        })
    end)
    if submitted and message ~= false then sentToken = request.Token
    else print("[EC:UI] consent_submit_failed " .. tostring(message)) end
end

local function Refresh()
    local ok, request = pcall(ReadRequest)
    if not ok or request == nil then Close(); return end
    if active ~= nil and active.Token == request.Token and active.PlayerID == request.PlayerID then return end
    Close()
    if sentToken == request.Token or deferredToken == request.Token then return end
    local config = PlayerConfigurations[request.Overlord]
    local name = tostring(request.Overlord)
    if config ~= nil then
        local value, readable = Safe(function() return config:GetCivilizationShortDescription() end)
        if readable and type(value) == "string" and value ~= "" then name = value end
    end
    dialog:Reset()
    local title=request.Native and "LOC_EC_NATIVE_CONSENT_TITLE" or "LOC_EC_CONSENT_TITLE"
    local body=request.Native and (request.Action=="RESTORE" and "LOC_EC_NATIVE_RESTORE_BODY" or "LOC_EC_NATIVE_ATTACH_BODY") or "LOC_EC_CONSENT_BODY"
    local fallback="%s 提出附庸请求。此演练只记录你的决定，不改变城市或军队。请求将在第 %s 回合到期。"
    if request.Native then
        fallback=request.Action=="RESTORE" and
            "对 %s 的自治已达标。确认后归还档案城市，恢复首都和原生产队列与产能，重新独立。第 %s 回合到期。" or
            "%s 提出真实附庸请求。接受后档案城市移交宗主、你的单位移除；原生产归档暂停，自治达标复国时恢复。第 %s 回合到期。"
    end
    dialog:AddTitle(Localized(title, request.Native and "附庸与复国确认" or "附庸请求演练"))
    dialog:AddText(Localized(body,
        fallback,
        Localized(name, "暂不可用"), request.Expires))
    -- Only a click accepts; Escape and Enter both select the safe refusal.
    dialog:AddButton(Localized(request.Native and "LOC_EC_NATIVE_ACCEPT" or "LOC_EC_CONSENT_ACCEPT",
        request.Native and "确认执行" or "接受演练请求"), function() Respond(request, "ACCEPT") end)
    dialog:AddButton(Localized("LOC_EC_CONSENT_REJECT", "拒绝"), function() Respond(request, "REJECT") end,
        PopupDialog.COMMAND_CANCEL)
    dialog:AddButton(Localized("LOC_EC_CONSENT_LATER", "稍后决定"), function()
        deferredToken = request.Token
        Close()
    end)
    active = request
    dialog:Open()
    UIManager:QueuePopup(ContextPtr, PopupPriority.Current)
end

local function OnPublish()
    -- Allow resubmission after a core update if the property write failed.
    sentToken = nil
    Refresh()
end

local function OnTurnActivated(playerID)
    local localID, readable = Safe(function() return Game.GetLocalPlayer() end)
    if readable and playerID == localID then deferredToken = nil end
    Refresh()
end

-- SetInputHandler supplies a native input object.  Accept the legacy
-- (message, key) shape too so a reload/test context cannot lose ESC handling.
local function ReadInput(messageOrInput, key)
    if key ~= nil then return messageOrInput, key end
    if messageOrInput == nil then return nil, nil end
    local message, inputKey
    local ok = pcall(function()
        message = messageOrInput:GetMessageType()
        inputKey = messageOrInput:GetKey()
    end)
    if ok then return message, inputKey end
    return nil, nil
end
local function OnInput(messageOrInput, key)
    local message, inputKey = ReadInput(messageOrInput, key)
    if active == nil then return false end
    if message == KeyEvents.KeyUp and (inputKey == Keys.VK_ESCAPE or inputKey == Keys.VK_RETURN) then
        dialog:ActivateCommand(PopupDialog.COMMAND_CANCEL)
    end
    return true
end

local function Shutdown()
    UnbindEvent("LoadScreenClose", Refresh)
    UnbindEvent("PlayerTurnActivated", OnTurnActivated)
    UnbindEvent("LocalPlayerChanged", Refresh)
    UnbindEvent("GameCoreEventPublishComplete", OnPublish)
    Close()
end

-- Register the input-object form used by the native TechCivicCompletedPopup
-- and Haikesi/CQUI popups. OnInput consumes input only while active.
ContextPtr:SetInputHandler(OnInput, true)
ContextPtr:SetShutdown(Shutdown)
BindEvent("LoadScreenClose", Refresh)
BindEvent("PlayerTurnActivated", OnTurnActivated)
BindEvent("LocalPlayerChanged", Refresh)
BindEvent("GameCoreEventPublishComplete", OnPublish)
