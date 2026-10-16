-- Grand Map Stability optional SAFE mode for the vanilla NaturalWonderPopup.
-- The discovery event is observed, but the cinematic popup and temporary
-- visibility/camera lock are skipped so the turn cannot wait on the UI movie.

local function OnNaturalWonderRevealed(plotX, plotY, featureIndex, isFirstToFind)
    print("[GMS] natural_wonder_safe_popup_skipped x=" .. tostring(plotX)
        .. " y=" .. tostring(plotY)
        .. " feature=" .. tostring(featureIndex)
        .. " first=" .. tostring(isFirstToFind));
end

local function HasCallable(object, methodName)
    if object == nil then return false end
    local ok, method = pcall(function() return object[methodName] end)
    return ok and type(method) == "function"
end

local m_Event = nil
local m_Registered = false

local function Unregister()
    if not m_Registered then return end
    if HasCallable(m_Event, "Remove") then
        local removed, message = pcall(function() m_Event.Remove(OnNaturalWonderRevealed) end)
        if not removed then
            print("[GMS] natural_wonder_safe_unbind_failed " .. tostring(message));
        end
    end
    m_Event = nil
    m_Registered = false
end

local function Register()
    if m_Registered then return true end
    local event, readable = nil, false
    local ok = pcall(function()
        event = Events ~= nil and Events.NaturalWonderRevealed or nil
        readable = HasCallable(event, "Add")
    end)
    if not ok or not readable then
        print("[GMS] natural_wonder_safe_event_unavailable");
        return false;
    end
    local registered, message = pcall(function() event.Add(OnNaturalWonderRevealed) end)
    if not registered then
        print("[GMS] natural_wonder_safe_bind_failed " .. tostring(message));
        return false;
    end
    m_Event = event
    m_Registered = true
    print("[GMS] natural_wonder_safe_popup_initialized");
    return true
end

local function OnInit(isReload)
    if isReload then Unregister() end
    Register()
end

local function OnShutdown()
    Unregister()
end

if HasCallable(ContextPtr, "SetInitHandler") then
    ContextPtr:SetInitHandler(OnInit)
end
if HasCallable(ContextPtr, "SetShutdown") then
    ContextPtr:SetShutdown(OnShutdown)
end
OnInit(false)

