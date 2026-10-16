-- Grand Map Stability replacement for the vanilla PantheonChooser Lua.
-- Only the candidate-pool partition is changed; confirmation and popup flow
-- remain aligned with the current Gathering Storm script.

include("InstanceManager");

local SIZE_BELIEF_ICON_LARGE = 64;
local BELIEFS_PANEL_RELATIVE_SIZE_UNSELECTED = -236;
local BELIEFS_PANEL_RELATIVE_SIZE_SELECTED = -326;
local DATA_FIELD_BELIEF_INDEX = "DataField_BeliefIndex";
local RESERVE_PREFIX = "BELIEF_GMS_RESERVE_";
local m_availableBeliefs = {};
local m_eventsRegistered = false;
local m_eventBound = {};
local m_controlsRegistered = false;

local m_pSelectBeliefsIM = InstanceManager:new("BeliefSlot", "BeliefButton", Controls.BeliftStack);
local function SafeCall(callback)
    local ok, value = pcall(callback)
    return ok and value or nil
end

local function PlaySound(name)
    if UI == nil then return end
    pcall(function() UI.PlaySound(name) end)
end

local function FindIconAtlas(iconName, iconSize)
    if IconManager == nil then return nil, nil, nil end
    local ok, x, y, sheet = pcall(function()
        return IconManager:FindIconAtlas(iconName, iconSize)
    end)
    if not ok then
        print("[GMS] pantheon_icon_atlas_unavailable icon=" .. tostring(iconName))
        return nil, nil, nil
    end
    return x, y, sheet
end

local function ReadMember(object, memberName)
    if object == nil then return nil, false end
    local ok, value = pcall(function() return object[memberName] end)
    return value, ok
end

local function HasCallable(object, memberName)
    local value, readable = ReadMember(object, memberName)
    return readable and type(value) == "function"
end

local function PublishEvent(name)
    local event, readable = ReadMember(LuaEvents, name)
    if readable and event ~= nil then
        pcall(function() event() end)
    end
end

local m_pGameReligion = SafeCall(function() return Game.GetReligion() end);
local m_uiSelectedBeliefInstance = nil;

local function IsReserveBelief(beliefDef)
    local ok, reserve = pcall(function()
        return beliefDef ~= nil
            and type(beliefDef.BeliefType) == "string"
            and string.sub(beliefDef.BeliefType, 1, string.len(RESERVE_PREFIX)) == RESERVE_PREFIX;
    end)
    return ok and reserve == true;
end

function CanSelectBelief(kBeliefDef)
    local shapeOK, shapeValid = pcall(function()
        return kBeliefDef ~= nil and m_pGameReligion ~= nil
            and type(kBeliefDef.Index) == "number"
            and kBeliefDef.Hash ~= nil
            and type(kBeliefDef.BeliefType) == "string"
            and type(kBeliefDef.Name) == "string"
            and type(kBeliefDef.Description) == "string"
            and kBeliefDef.BeliefClassType == "BELIEF_CLASS_PANTHEON";
    end)
    if not shapeOK or not shapeValid then return false, true end
    local pantheonOK, inPantheon = pcall(function()
        return m_pGameReligion:IsInSomePantheon(kBeliefDef.Index)
    end)
    if pantheonOK and inPantheon == true then return false, true end
    local religionOK, inReligion = pcall(function()
        return m_pGameReligion:IsInSomeReligion(kBeliefDef.Index)
    end)
    if religionOK and inReligion == true then return false, true end
    -- A belief is unused only when both native queries explicitly say so.
    if not pantheonOK or not religionOK or inPantheon ~= false or inReligion ~= false then
        return false, false
    end
    return true, true;
end

function SetBeliefIcon(targetControl, beliefType, iconSize)
    if targetControl == nil or type(beliefType) ~= "string" or beliefType == "" then
        if targetControl ~= nil then targetControl:SetHide(true); end
        print("[GMS] pantheon_icon_unavailable belief=" .. tostring(beliefType));
        return;
    end
    local iconType = beliefType;
    if string.sub(beliefType, 1, #RESERVE_PREFIX) == RESERVE_PREFIX then
        iconType = string.find(beliefType, "RESERVE_BORDER_", 1, true)
            and "BELIEF_RELIGIOUS_SETTLEMENTS" or "BELIEF_FERTILITY_RITES";
    end
    local textureOffsetX, textureOffsetY, textureSheet = FindIconAtlas("ICON_" .. iconType, iconSize);
    if textureSheet == nil or textureSheet == "" then
        targetControl:SetHide(true);
        print("[GMS] pantheon_icon_unavailable belief=" .. beliefType);
    else
        targetControl:SetHide(false);
        targetControl:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
        targetControl:SetSizeVal(iconSize, iconSize);
    end
end

local function AddBeliefInstance(row)
    local beliefInst = m_pSelectBeliefsIM:GetInstance();
    beliefInst[DATA_FIELD_BELIEF_INDEX] = row.Index;
    beliefInst.BeliefLabel:LocalizeAndSetText(Locale.ToUpper(row.Name));
    beliefInst.BeliefDescription:LocalizeAndSetText(row.Description);
    SetBeliefIcon(beliefInst.BeliefIcon, row.BeliefType, SIZE_BELIEF_ICON_LARGE);
    beliefInst.BeliefButton:SetSelected(beliefInst == m_uiSelectedBeliefInstance);
    beliefInst.BeliefButton:RegisterCallback(Mouse.eLClick, function() OnBeliefSelected(beliefInst); end);
    beliefInst.BeliefButton:RegisterCallback(Mouse.eMouseEnter, function() PlaySound("Main_Menu_Mouse_Over"); end);
    m_availableBeliefs[row.Index] = beliefInst;
    return beliefInst;
end

local function Beliefs()
    local beliefs, readable = ReadMember(GameInfo, "Beliefs")
    if not readable or beliefs == nil then
        print("[GMS] pantheon_beliefs_unavailable")
        return {}
    end
    local ok, rows = pcall(function()
        local result = {}
        for row in beliefs() do result[#result + 1] = row end
        return result
    end)
    if not ok then
        print("[GMS] pantheon_beliefs_unavailable")
        return {}
    end
    return rows
end

local function BeliefAt(index)
    local beliefs, readable = ReadMember(GameInfo, "Beliefs")
    if not readable or beliefs == nil then return nil end
    local ok, row = pcall(function() return beliefs[index] end)
    return ok and row or nil
end

function Realize()
    local selectedIndex = m_uiSelectedBeliefInstance ~= nil and m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX] or nil;
    m_uiSelectedBeliefInstance = nil;
    m_availableBeliefs = {};
    m_pSelectBeliefsIM:ResetInstances();

    local regularBeliefs = {};
    local reserveBeliefs = {};
    local regularComplete = true;
    for _, row in ipairs(Beliefs()) do
        local available, known = CanSelectBelief(row)
        if not known and not IsReserveBelief(row) then regularComplete = false end
        if available then
            if IsReserveBelief(row) then
                table.insert(reserveBeliefs, row);
            else
                table.insert(regularBeliefs, row);
            end
        end
    end

    local beliefsToShow = regularBeliefs;
    if #regularBeliefs == 0 and regularComplete then
        beliefsToShow = reserveBeliefs;
    end

    print("[GMS] pantheon_ui regular=" .. tostring(#regularBeliefs)
        .. " reserve=" .. tostring(#reserveBeliefs)
        .. " shown=" .. tostring(#beliefsToShow)
        .. " regular_complete=" .. tostring(regularComplete));
    for _, row in ipairs(beliefsToShow) do
        local instance = AddBeliefInstance(row);
        if row.Index == selectedIndex then
            m_uiSelectedBeliefInstance = instance;
            instance.BeliefButton:SetSelected(true);
        end
    end

    RealizeCurrentSelection();
end

function RealizeCurrentSelection()
    if m_uiSelectedBeliefInstance == nil then
        Controls.ReligionOrPatheonTitle:SetText(Locale.ToUpper("LOC_UI_RELIGION_CHOOSING_PANTHEON"));
        Controls.SelectedBeliefGrid:SetHide(true);
        Controls.ConfirmGrid:SetHide(true);
        Controls.BottomGrid:SetParentRelativeSizeY(BELIEFS_PANEL_RELATIVE_SIZE_UNSELECTED);
    else
        local beliefDef = BeliefAt(m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX]);
        if beliefDef == nil or not CanSelectBelief(beliefDef) then
            ClearBeliefSelection();
            return;
        end
        Controls.ReligionOrPatheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", beliefDef.Name)));
        Controls.SelectedBeliefLabel:LocalizeAndSetText(Locale.ToUpper(beliefDef.Name));
        Controls.SelectedBeliefDescription:LocalizeAndSetText(beliefDef.Description);
        SetBeliefIcon(Controls.SelectedBeliefIcon, beliefDef.BeliefType, SIZE_BELIEF_ICON_LARGE);
        Controls.SelectedBeliefGrid:SetHide(false);
        Controls.ConfirmGrid:SetHide(false);
        Controls.BottomGrid:SetParentRelativeSizeY(BELIEFS_PANEL_RELATIVE_SIZE_SELECTED);
    end
end

function OnBeliefSelected(instance)
    local index = instance ~= nil and instance[DATA_FIELD_BELIEF_INDEX] or nil;
    if index == nil or m_availableBeliefs[index] ~= instance or not CanSelectBelief(BeliefAt(index)) then
        Realize();
        return;
    end
    if m_uiSelectedBeliefInstance == instance then
        return;
    end
    SetSelectedBeliefInstance(instance);
end

function SetSelectedBeliefInstance(instance)
    if m_uiSelectedBeliefInstance ~= nil then
        m_uiSelectedBeliefInstance.BeliefButton:SetSelected(false);
    end
    m_uiSelectedBeliefInstance = instance;
    m_uiSelectedBeliefInstance.BeliefButton:SetSelected(true);
    RealizeCurrentSelection();
end

function ClearBeliefSelection()
    if m_uiSelectedBeliefInstance ~= nil then
        m_uiSelectedBeliefInstance.BeliefButton:SetSelected(false);
        m_uiSelectedBeliefInstance = nil;
    end
    RealizeCurrentSelection();
end

function ConfirmPantheon()
    if m_uiSelectedBeliefInstance ~= nil then
        local beliefIndex = m_uiSelectedBeliefInstance[DATA_FIELD_BELIEF_INDEX];
        local beliefDef = BeliefAt(beliefIndex)
        if not CanSelectBelief(beliefDef) then
            ClearBeliefSelection();
            Realize();
            return;
        end
        local parameters = {};
        parameters[PlayerOperations.PARAM_BELIEF_TYPE] = beliefDef.Hash;
        parameters[PlayerOperations.PARAM_INSERT_MODE] = PlayerOperations.VALUE_EXCLUSIVE;
        local playerID = SafeCall(function() return Game.GetLocalPlayer() end)
        if playerID == nil then
            ClearBeliefSelection();
            return;
        end
        local submitted, result = pcall(function()
            return UI.RequestPlayerOperation(playerID, PlayerOperations.FOUND_PANTHEON, parameters)
        end)
        if not submitted or result == false then
            print("[GMS] pantheon_operation_unavailable reason=" .. tostring(result))
            return
        end
        ClearBeliefSelection();
        PlaySound("Confirm_Religion");
        Close();
        PublishEvent("PantheonChooser_OpenReligionPanel");
    end
end

function Close()
    if not ContextPtr:IsHidden() and not Controls.PantheonChooserSlideAnim:IsReversing() then
        Controls.PantheonChooserSlideAnim:SetToEnd();
        Controls.PantheonChooserSlideAnim:Reverse();
        PlaySound("Tech_Tray_Slide_Closed");
        PublishEvent("PantheonChooser_CloseReligion");
    end
end

function Open()
    if ContextPtr:IsHidden() then
        ContextPtr:SetHide(false);
        m_uiSelectedBeliefInstance = nil;
        PublishEvent("PantheonChooser_OpenReligion");
        Controls.PantheonChooserSlideAnim:SetToBeginning();
        Controls.PantheonChooserSlideAnim:Play();
        PlaySound("Tech_Tray_Slide_Open");
        Realize();
    end
end

function OnInit(isReload)
    m_pGameReligion = SafeCall(function() return Game.GetReligion() end);
    LateInitialize();
    if isReload and not ContextPtr:IsHidden() then
        Realize();
    end
end

function OnInputHandler(inputStruct)
    if inputStruct:GetMessageType() == KeyEvents.KeyUp and inputStruct:GetKey() == Keys.VK_ESCAPE then
        Close();
        return true;
    end
    return false;
end

function OnShutdown()
    if not m_eventsRegistered and next(m_eventBound) == nil then
        return;
    end
    local function RemoveEvent(name, handler)
        local event, readable = ReadMember(LuaEvents, name)
        if readable and HasCallable(event, "Remove") then
            pcall(function() event.Remove(handler) end)
        end
    end
    if m_eventBound.NotificationPanel_OpenPantheonChooser then
        RemoveEvent("NotificationPanel_OpenPantheonChooser", Open)
    end
    if m_eventBound.LaunchBar_OpenPantheonChooser then
        RemoveEvent("LaunchBar_OpenPantheonChooser", Open)
    end
    if m_eventBound.LaunchBar_ClosePantheonChooser then
        RemoveEvent("LaunchBar_ClosePantheonChooser", Close)
    end
    m_eventBound = {}
    m_eventsRegistered = false;
end

function OnAnimEnd()
    if Controls.PantheonChooserSlideAnim:IsReversing() then
        ContextPtr:SetHide(true);
    end
end

function LateInitialize()
    if m_eventsRegistered then
        return;
    end
    local function AddEvent(name, handler)
        if m_eventBound[name] then return true end
        local event, readable = ReadMember(LuaEvents, name)
        if readable and HasCallable(event, "Add") then
            local added, message = pcall(function() event.Add(handler) end)
            if added then
                m_eventBound[name] = true
                return true
            end
            print("[GMS] pantheon_event_bind_failed name=" .. name .. " reason=" .. tostring(message))
        else
            print("[GMS] pantheon_event_unavailable name=" .. name)
        end
        return false
    end
    local openNotification = AddEvent("NotificationPanel_OpenPantheonChooser", Open)
    local openLaunchBar = AddEvent("LaunchBar_OpenPantheonChooser", Open)
    local closeLaunchBar = AddEvent("LaunchBar_ClosePantheonChooser", Close)
    if not m_controlsRegistered then
        Controls.Header_CloseButton:RegisterCallback(Mouse.eLClick, Close);
        Controls.SelectedBeliefGrid:RegisterCallback(Mouse.eLClick, ClearBeliefSelection);
        Controls.ConfirmPantheonButton:RegisterCallback(Mouse.eLClick, ConfirmPantheon);
        Controls.ConfirmPantheonButton:RegisterCallback(Mouse.eMouseEnter, function() PlaySound("Main_Menu_Mouse_Over"); end);
        Controls.CancelButton:RegisterCallback(Mouse.eLClick, ClearBeliefSelection);
        Controls.CancelButton:RegisterCallback(Mouse.eMouseEnter, function() PlaySound("Main_Menu_Mouse_Over"); end);
        Controls.PantheonChooserSlideAnim:RegisterEndCallback(OnAnimEnd);
        m_controlsRegistered = true;
    end
    m_eventsRegistered = openNotification and openLaunchBar and closeLaunchBar;
end

function Initialize()
    ContextPtr:SetInitHandler(OnInit);
    ContextPtr:SetShutdown(OnShutdown);
    ContextPtr:SetInputHandler(OnInputHandler, true);
end

Initialize();
