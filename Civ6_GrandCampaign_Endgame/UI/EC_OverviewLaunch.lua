-- Append to the shared stack, following the proven Haikesi entry-button pattern.
-- This context only owns the two instances it creates; it never replaces or
-- reparents controls belonging to the base game or other mods.
local m_LaunchButtonInstance = {}
local m_LaunchPinInstance = {}
local m_Attached = false
local m_LaunchParent = nil
local m_Initialized = false
local m_Waiting = false
local m_WaitReason = nil
local m_ViewStateReady = false
local m_ViewStateEventBound = false
local m_SystemUpdateEventBound = false
local m_SystemUpdateTicks = 0
local SYSTEM_UPDATE_FALLBACK_TICKS = 4
local unpackValues = table.unpack or unpack

local function ReadMember(object, memberName)
    if object == nil then return nil, false end
    local ok, value = pcall(function() return object[memberName] end)
    return value, ok
end

local function InvokeEvent(container, name, ...)
    local event, readable = ReadMember(container, name)
    if not readable or event == nil then return false end
    local args = { ... }
    local ok = pcall(function() event(unpackValues(args)) end)
    return ok
end

local function AddEvent(container, name, handler)
    local event, readable = ReadMember(container, name)
    local add, callable = ReadMember(event, "Add")
    if not readable or not callable or type(add) ~= "function" then return false end
    local ok = pcall(function() add(handler) end)
    if not ok then print("[EC:UI] overview_launch_event_add_failed name=" .. name) end
    return ok
end

local function RemoveEvent(container, name, handler)
    local event, readable = ReadMember(container, name)
    local remove, callable = ReadMember(event, "Remove")
    if not readable or not callable or type(remove) ~= "function" then return false end
    local ok = pcall(function() remove(handler) end)
    if not ok then print("[EC:UI] overview_launch_event_remove_failed name=" .. name) end
    return ok
end

local function Localized(key, fallback)
    local ok, value = pcall(function() return Locale.Lookup(key) end)
    if not ok or type(value) ~= "string" or value == "" or value == key
        or string.find(value, "TRANSLATION MISSING", 1, true) ~= nil
        or string.match(value, "^LOC_[A-Z0-9_]+$") ~= nil then
        return fallback
    end
    return value
end

local function ResizeLaunchBar()
    local ok, message = pcall(function()
        local buttonStack = ContextPtr:LookUpControl("/InGame/LaunchBar/ButtonStack")
        if buttonStack == nil then error("button_stack_unavailable") end
        buttonStack:CalculateSize()
        local width = buttonStack:GetSizeX()
        local backing = ContextPtr:LookUpControl("/InGame/LaunchBar/LaunchBacking")
        if backing ~= nil then backing:SetSizeX(width + 116) end
        local backingTile = ContextPtr:LookUpControl("/InGame/LaunchBar/LaunchBackingTile")
        if backingTile ~= nil then backingTile:SetSizeX(math.max(0, width - 20)) end
        local dropShadow = ContextPtr:LookUpControl("/InGame/LaunchBar/LaunchBarDropShadow")
        if dropShadow ~= nil then dropShadow:SetSizeX(width) end
        if not InvokeEvent(LuaEvents, "LaunchBar_Resize", width) then
            print("[EC:UI] overview_launch_resize_event_unavailable")
        end
    end)
    if not ok then
        print("[EC:UI] overview_launch_resize_failed " .. tostring(message))
        return false
    end
    return true
end

local function DestroyLaunchInstances()
    if m_LaunchParent == nil then return end
    for _, child in pairs({ m_LaunchButtonInstance.Button, m_LaunchPinInstance.Pin }) do
        if child ~= nil then
            local ok, message = pcall(function() m_LaunchParent:DestroyChild(child) end)
            if not ok then print("[EC:UI] overview_launch_cleanup_unavailable " .. tostring(message)) end
        end
    end
end

local function InjectLaunchButton()
    if m_Attached then return true end
    local buttonStack, readable = nil, false
    buttonStack, readable = (function()
        local ok, value = pcall(function()
            return ContextPtr:LookUpControl("/InGame/LaunchBar/ButtonStack")
        end)
        return value, ok
    end)()
    if not readable or buttonStack == nil then return false end
    m_LaunchParent = buttonStack
    local ok, message = pcall(function()
        ContextPtr:BuildInstanceForControl("EC_OverviewLaunchItem", m_LaunchButtonInstance, buttonStack)
        m_LaunchButtonInstance.Button:RegisterCallback(Mouse.eLClick,
            function() InvokeEvent(LuaEvents, "EC_Overview_Toggle") end)
        m_LaunchButtonInstance.Button:SetToolTipString(Localized("LOC_EC_OVERVIEW_TOOLTIP", "附庸总览"))
        ContextPtr:BuildInstanceForControl("EC_OverviewLaunchPin", m_LaunchPinInstance, buttonStack)
        if not ResizeLaunchBar() then error("resize_failed") end
    end)
    if not ok then
        print("[EC:UI] overview_launch_attach_failed " .. tostring(message))
        DestroyLaunchInstances()
        -- BuildInstanceForControl can succeed for the button and then fail for
        -- the pin or for a shared resize callback. Recalculate immediately so
        -- a failed attempt never leaves LaunchBacking wider than its real
        -- children while the retry listeners wait for the next ready event.
        ResizeLaunchBar()
        m_LaunchParent = nil
        m_LaunchButtonInstance, m_LaunchPinInstance = {}, {}
        return false
    end
    m_Attached = true
    print("[EC:UI] overview_launch_attached")
    return true
end

local function WaitFor(reason, message)
    if m_WaitReason ~= reason then
        m_WaitReason = reason
        print("[EC:UI] overview_launch_waiting reason=" .. reason
            .. (message ~= nil and " message=" .. tostring(message) or ""))
    end
    return false
end

local function TryAttach()
    if m_Attached then return true end
    local ok, eligible, reason = pcall(function()
        if Game == nil or Game.GetLocalPlayer == nil or Players == nil then
            return false, "local_player_unavailable"
        end
        local id = Game.GetLocalPlayer()
        if type(id) ~= "number" or id ~= id or id < 0 or id >= 64 or id ~= math.floor(id)
            or Players[id] == nil then return false, "local_player_unavailable" end
        return Players[id]:IsHuman() == true, "local_player_not_human"
    end)
    if not ok then return WaitFor("player_identity_unavailable", eligible) end
    if not eligible then return WaitFor(reason) end
    -- This action is deliberately loaded after common LaunchBar additions. When
    -- this late context is created, LoadGameViewStateDone may already have
    -- fired and can never be replayed for us.  The shared stack is the real
    -- readiness gate: attach immediately when it exists, and keep the event
    -- retries only for the case where the native toolbar is still building.
    if not InjectLaunchButton() then return WaitFor("launchbar_unavailable") end
    m_WaitReason = nil
    return true
end

local OnReadinessChanged
local OnViewStateReady
local OnViewStateFallback
local OnSystemUpdateUI
local function StopWaiting()
    if m_Waiting then
        RemoveEvent(Events, "LoadScreenClose", OnReadinessChanged)
        RemoveEvent(Events, "GameCoreEventPublishComplete", OnReadinessChanged)
        RemoveEvent(Events, "LocalPlayerChanged", OnReadinessChanged)
        RemoveEvent(Events, "LocalPlayerTurnBegin", OnReadinessChanged)
        RemoveEvent(Events, "VisualStateRestored", OnReadinessChanged)
        RemoveEvent(Events, "LocalPlayerTurnBegin", OnViewStateFallback)
        RemoveEvent(Events, "VisualStateRestored", OnViewStateFallback)
        if m_SystemUpdateEventBound then
            RemoveEvent(Events, "SystemUpdateUI", OnSystemUpdateUI)
        end
    end
    if m_ViewStateEventBound then
        RemoveEvent(Events, "LoadGameViewStateDone", OnViewStateReady)
    end
    m_Waiting = false
    m_ViewStateEventBound = false
    m_SystemUpdateEventBound = false
    m_SystemUpdateTicks = 0
end
OnViewStateFallback = function()
    m_ViewStateReady = true
    if m_Initialized and TryAttach() then StopWaiting() end
end
OnReadinessChanged = function()
    if m_Initialized and TryAttach() then StopWaiting() end
end
OnViewStateReady = function()
    m_ViewStateReady = true
    if m_Initialized and TryAttach() then StopWaiting() end
end
OnSystemUpdateUI = function()
    if not m_Initialized or m_Attached then return end
    m_SystemUpdateTicks = m_SystemUpdateTicks + 1
    -- LoadGameViewStateDone is one-shot.  A late action can create this
    -- context after it has fired, so allow a few UI frames for the native
    -- LaunchBar and other late appenders, then use the normal attach path.
    if m_ViewStateEventBound and not m_ViewStateReady
        and m_SystemUpdateTicks < SYSTEM_UPDATE_FALLBACK_TICKS then
        return
    end
    m_ViewStateReady = true
    if TryAttach() then StopWaiting() end
end

local function Shutdown()
    m_Initialized = false
    StopWaiting()
    DestroyLaunchInstances()
    -- During game shutdown/reload the native LaunchBar can disappear before
    -- this late user-interface context.  Its children are already detached;
    -- there is nothing to resize when the shared stack is gone.
    if m_LaunchParent ~= nil then
        local stack, readable = nil, false
        local lookupOK, value = pcall(function()
            return ContextPtr:LookUpControl("/InGame/LaunchBar/ButtonStack")
        end)
        if lookupOK then stack, readable = value, true end
        if readable and stack ~= nil then ResizeLaunchBar() end
    end
    m_LaunchParent = nil
    m_LaunchButtonInstance, m_LaunchPinInstance = {}, {}
    m_Attached, m_WaitReason = false, nil
    m_ViewStateReady = false
end

function OnInit(isReload)
    StopWaiting()
    m_Initialized = true
    -- A reload happens after the shared LaunchBar and its late additions have
    -- already been built; waiting for the one-shot view-state event here
    -- would leave the entry invisible until a later turn.
    m_ViewStateReady = isReload == true
    m_SystemUpdateTicks = 0
    -- Keep the view-state event as a retry if the shared toolbar is missing.
    -- It may already have fired before this late action starts, so the
    -- immediate shared-stack check below must remain the primary path.
    local viewStateEvent, viewStateReadable = ReadMember(Events, "LoadGameViewStateDone")
    local viewStateAdd, viewStateCallable = ReadMember(viewStateEvent, "Add")
    if viewStateReadable and viewStateCallable and type(viewStateAdd) == "function"
        and AddEvent(Events, "LoadGameViewStateDone", OnViewStateReady) then
        m_ViewStateEventBound = true
    else
        m_ViewStateReady = true
    end
    -- Try immediately as well.  A late AddUserInterfaces action can be
    -- initialized after the one-shot view-state event and must not depend on
    -- an event that has already been consumed.
    if TryAttach() then
        StopWaiting()
        return
    end
    AddEvent(Events, "LoadScreenClose", OnReadinessChanged)
    -- This is raised by the vanilla UI after a game-core refresh and is also
    -- available when a context is hot-reloaded during the current turn.
    AddEvent(Events, "GameCoreEventPublishComplete", OnReadinessChanged)
    AddEvent(Events, "LocalPlayerChanged", OnReadinessChanged)
    -- If the view-state event was already consumed before a hot reload, these
    -- later readiness points are safe fallbacks for the current context.
    AddEvent(Events, "LocalPlayerTurnBegin", m_ViewStateEventBound and OnViewStateFallback or OnReadinessChanged)
    AddEvent(Events, "VisualStateRestored", m_ViewStateEventBound and OnViewStateFallback or OnReadinessChanged)
    m_SystemUpdateEventBound = AddEvent(Events, "SystemUpdateUI", OnSystemUpdateUI)
    m_Waiting = true
end

-- Keep the same bootstrap shape as the working Haikesi entry context.  The
-- engine still invokes the registered handler during normal context startup;
-- the immediate path remains available when the late view-state event is not
-- exposed by the current build.
ContextPtr:SetInitHandler(OnInit)
ContextPtr:SetShutdown(Shutdown)
print("[EC:UI] overview_launch_context_loaded")
OnInit(false)
