include("InstanceManager")

-- The shared model is imported by the mod action, but an in-game UI context
-- can be created before that import is visible (especially during hot reload
-- or when another UI action fails first).  Keep the panel loadable in that
-- case and show its existing unsupported/unknown state instead of aborting
-- the whole EC_UI action and losing the LaunchBar entry with it.
local modelLoaded = pcall(function() include("EC_OverviewModel") end)
if not modelLoaded or type(EC_OverviewModel) ~= "table"
    or type(EC_OverviewModel.Build) ~= "function" then
    print("[EC:UI] overview_model_unavailable")
    EC_OverviewModel = {
        Build = function()
            return { Supported = false, Entries = {}, Mode = "LOC_EC_OVERVIEW_UNKNOWN",
                Metrics = "LOC_EC_OVERVIEW_UNKNOWN", Awakening = "LOC_EC_OVERVIEW_UNKNOWN",
                AttachAvailable = false, RestoreAvailable = false,
                OperationReason = "LOC_EC_OVERVIEW_NATIVE_PENDING" }
        end,
    }
end

local rows = InstanceManager:new("EC_OverviewRow", "Root", Controls.ArchiveStack)
local opened = false
local warned = false
local subscriptions = {}
local initialized = false
local unpackValues = table.unpack or unpack
local FALLBACKS = {
    LOC_EC_OVERVIEW_UNKNOWN = "暂不可用",
    LOC_EC_OVERVIEW_NOT_TRIGGERED = "尚未建立觉醒记录",
    LOC_EC_OVERVIEW_METRICS_FRESH = "已收到有效数据",
    LOC_EC_OVERVIEW_METRICS_WAITING = "等待统计数据",
    LOC_EC_OVERVIEW_METRICS_STALE = "统计数据已过期",
    LOC_EC_OVERVIEW_LEGACY_OWNER = "旧存档记录所属玩家不一致，已暂停",
    LOC_EC_OVERVIEW_UNSUPPORTED = "此总览目前仅支持存活的人类玩家所在的单人游戏。",
    LOC_EC_OVERVIEW_NO_DATA = "当前无法读取附庸档案，请返回单人测试局。",
    LOC_EC_OVERVIEW_EMPTY = "当前没有已接触文明的附庸档案。",
    LOC_EC_OVERVIEW_TITLE = "附庸与终局",
    LOC_EC_OVERVIEW_NOTICE = "影子附庸是演练档案，尚未接管城市；真实附庸与复国还未接通。",
    LOC_EC_OVERVIEW_READ_ONLY = "只读总览 · 不发起城市移交、宣战或复国",
    LOC_EC_OVERVIEW_NATIVE_PENDING = "真实附庸与复国事务尚未接通；当前不会提交城市、单位或玩家变更。",
    LOC_EC_OVERVIEW_CANDIDATE_UNKNOWN = "资格观察暂不可用",
    LOC_EC_OVERVIEW_CANDIDATE_OBSERVED = "附庸候选（仅观察）",
    LOC_EC_OVERVIEW_CANDIDATE_INVALIDATED = "附庸候选已失效",
    LOC_EC_OVERVIEW_CANDIDATE_DETAILS = "资格记录：%s    层级：%s[NEWLINE]最后采样：第%s回合    样本：%s",
    LOC_EC_OVERVIEW_CLOSE = "关闭总览",
}
local function ReadMember(object, memberName)
    if object == nil then return nil, false end
    local ok, value = pcall(function() return object[memberName] end)
    return value, ok
end
local function Bind(event, handler)
    local add, readable = ReadMember(event, "Add")
    if not readable or type(add) ~= "function" then return false end
    local ok = pcall(function() add(handler) end)
    if ok then subscriptions[#subscriptions + 1] = { event, handler } end
    return ok
end
local function BindNamed(container, name, handler)
    local event, readable = ReadMember(container, name)
    if not readable then return false end
    return Bind(event, handler)
end
local function PublishNamed(container, name)
    local event, readable = ReadMember(container, name)
    if readable and event ~= nil then pcall(function() event() end) end
end
local function Missing(value, key)
    return type(value) ~= "string" or value == ""
        or (type(key) == "string" and string.match(key, "^LOC_") ~= nil and value == key)
        or string.find(value, "TRANSLATION MISSING", 1, true) ~= nil
        or string.match(value, "^LOC_[A-Z0-9_]+$") ~= nil
end
local function Localized(key, fallback, ...)
    local values = { ... }
    local ok, value = pcall(function() return Locale.Lookup(key, unpackValues(values)) end)
    if ok and not Missing(value, key) then
        -- An already-loaded localization database may retain the old printf
        -- template until reload. Only this legacy key needs Lua formatting.
        if key == "LOC_EC_OVERVIEW_METRIC_DATA" and value:find("%%s") then
            local formatted, result = pcall(string.format, value, unpackValues(values))
            if formatted and not Missing(result, key) then return result end
        else
            return value
        end
    end
    if #values > 0 then
        local formatted, formattedValue = pcall(function() return string.format(fallback, unpackValues(values)) end)
        if formatted and not Missing(formattedValue, key) then return formattedValue end
    end
    return fallback
end
local function Lookup(key)
    key = key or "LOC_EC_OVERVIEW_UNKNOWN"
    return Localized(key, FALLBACKS[key] or FALLBACKS.LOC_EC_OVERVIEW_UNKNOWN)
end
local function Display(value)
    return type(value) == "string" and value ~= "" and value or Lookup(nil)
end
local function Number(value)
    if type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge then
        return tostring(value)
    end
    return Lookup(nil)
end
local function ControlHeight(control, fallback)
    if control == nil then return fallback end
    -- Labels with Size="auto" update their measured height only after the
    -- native layout pass.  Refresh can run immediately after SetText (for
    -- example when a localized summary changes), so ask the control to
    -- recalculate before reading its size.  Some test doubles/older UI
    -- contexts do not expose CalculateSize; keep that path fail-closed.
    pcall(function()
        if type(control.CalculateSize) == "function" then control:CalculateSize() end
    end)
    local ok, height = pcall(function() return control:GetSizeY() end)
    if ok and type(height) == "number" and height == height
        and height ~= math.huge and height ~= -math.huge and height > 0 then
        return height
    end
    return fallback
end

local function Refresh()
    if not opened then return end
    rows:ResetInstances()
    local ok, view = pcall(EC_OverviewModel.Build)
    local validView = ok and type(view) == "table" and type(view.Entries) == "table"
    if not validView and not warned then
        warned = true
        print("[EC:UI] overview_data_unavailable " .. tostring(ok and "invalid_model" or view))
    end
    if not validView or view.Supported ~= true then
        Controls.Summary:SetText(Lookup("LOC_EC_OVERVIEW_UNSUPPORTED"))
        Controls.Empty:SetHide(false)
        Controls.Empty:SetText(Lookup("LOC_EC_OVERVIEW_NO_DATA"))
    else
        local summary = Localized("LOC_EC_OVERVIEW_SUMMARY",
            "当前模式：%s    单人实力统计：%s[NEWLINE]觉醒状态：%s",
            Lookup(view.Mode), Lookup(view.Metrics), Lookup(view.Awakening))
        summary = summary .. "[NEWLINE]" .. Localized(
            "LOC_EC_OVERVIEW_METRIC_DATA", "统计数据：%s", Lookup(view.MetricData))
        local timer = view.AwakeningTimer
        if type(timer) == "table" then
            summary = summary .. "[NEWLINE]" .. Localized("LOC_EC_OVERVIEW_AWAKENING_TIMER",
                "%s · %s预计于第%s回合开始（剩余%s回合）", Display(timer.Name),
                Lookup(timer.Stage), Number(timer.Due), Number(timer.Remaining))
        end
        Controls.Summary:SetText(summary)
        local entries = {}
        for _, entry in ipairs(view.Entries) do
            if type(entry) == "table" then entries[#entries + 1] = entry end
        end
        Controls.Empty:SetHide(#entries > 0)
        Controls.Empty:SetText(Lookup("LOC_EC_OVERVIEW_EMPTY"))
        for _, entry in ipairs(entries) do
            local row = rows:GetInstance()
            row.Name:SetText(Display(entry.Name))
            row.Status:SetText(Lookup(entry.Status))
            if entry.Kind=="PRODUCTION_ARCHIVE" then
                row.Details:SetText(Localized("LOC_EC_NATIVE_ARCHIVE_PRODUCTION_DETAILS",
                    "原队列：%s[NEWLINE]原投入：%s（共%s点）[NEWLINE]%s · %s · 剩余%s点",
                    entry.Queue,entry.Investment,Number(entry.Total),Lookup(entry.Policy),Lookup(entry.CreditState),Number(entry.Remaining)))
            elseif entry.Native and entry.OperationStatus=="PRODUCTION_PENDING" then
                row.Details:SetText(Localized("LOC_EC_NATIVE_PRODUCTION_PENDING","城市已归还，正在核对原生产队列与产能。"))
            elseif entry.Kind == "CANDIDATE" then
                row.Details:SetText(Localized("LOC_EC_OVERVIEW_CANDIDATE_DETAILS",
                    Display(entry.ReasonLabel), Display(entry.TierLabel), Number(entry.LastSampleTurn),
                    Number(entry.Samples)))
            else
                row.Details:SetText(Localized("LOC_EC_OVERVIEW_DETAILS",
                    "宗主：%s    自治度：%s/100[NEWLINE]项目：%s · %s    本期截止：第%s回合",
                    Display(entry.Overlord), Number(entry.Autonomy), Lookup(entry.Project),
                    Lookup(entry.Focus), Number(entry.Due)))
            end
            if entry.OperationStatus and entry.OperationStatus~="COMMITTED" and entry.OperationStatus~="ALREADY_APPLIED"
                and entry.OperationStatus~="PRODUCTION_PENDING" then
                row.Details:SetText(row.Details:GetText().."[NEWLINE]"..tostring(entry.OperationStatus))
            end
            local hasButtons=entry.Action~=nil or entry.ProjectChoice~=nil
            if row.OperationButton then
                row.OperationButton:SetHide(entry.Action==nil)
                row.OperationLabel:SetText(Localized(entry.ActionLabel or "LOC_EC_NATIVE_ATTACH","提交附庸请求"))
                row.OperationButton:RegisterCallback(Mouse.eLClick,function()
                    local id=Game.GetLocalPlayer()
                    UI.RequestPlayerOperation(id,PlayerOperations.EXECUTE_SCRIPT,{OnStart="EC_NativeOperate",ForPlayer=id,
                        TargetID=entry.TargetID,Overlord=entry.OverlordID,Action=entry.Action})
                end)
            end
            if row.ProjectButton then
                row.ProjectButton:SetHide(entry.ProjectChoice==nil)
                row.ProjectLabel:SetText(Localized("LOC_EC_NATIVE_PROJECT_SWITCH","切换支持 / 削弱项目"))
                row.ProjectButton:RegisterCallback(Mouse.eLClick,function()
                    local id=Game.GetLocalPlayer()
                    UI.RequestPlayerOperation(id,PlayerOperations.EXECUTE_SCRIPT,{OnStart="EC_NativeProject",ForPlayer=id,TargetID=id,
                        Project=entry.ProjectChoice=="SUPPORT_OVERLORD" and "WEAKEN_OVERLORD" or "SUPPORT_OVERLORD"})
                end)
            end
            row.Root:SetSizeY(math.max(86, ControlHeight(row.Details, 22) + (hasButtons and 80 or 42)))
        end
    end
    if Controls.OperationStatus ~= nil then
        local reason = validView and view.OperationReason or "LOC_EC_OVERVIEW_NATIVE_PENDING"
        Controls.OperationStatus:SetText(Lookup(reason))
    end
    if validView and view.OperationReason=="LOC_EC_NATIVE_OPERATION_NOTICE" then
        Controls.Notice:SetText(Localized("LOC_EC_NATIVE_OPERATION_NOTICE","真实附庸模式已启用。资格与保护将在提交时复核；玩家请求需要明确确认。"))
        Controls.ReadOnly:SetText(Localized("LOC_EC_NATIVE_FOOTER","附庸期间原生产归档暂停，复国时恢复"))
    else
        Controls.Notice:SetText(Lookup("LOC_EC_OVERVIEW_NOTICE"))
        Controls.ReadOnly:SetText(Lookup("LOC_EC_OVERVIEW_READ_ONLY"))
    end
    local noticeY = 54 + ControlHeight(Controls.Summary, 22) + 10
    Controls.Notice:SetOffsetY(noticeY)
    local scrollY = noticeY + ControlHeight(Controls.Notice, 22) + 16
    Controls.ArchiveScroll:SetOffsetY(scrollY)
    -- The native footer labels are auto-sized. Reserve their measured height
    -- so a long localized transaction status cannot overlap the scroll area.
    local footerHeight = 44
    if Controls.OperationStatus ~= nil then
        footerHeight = math.max(footerHeight, ControlHeight(Controls.OperationStatus, 22) + 34)
    end
    if Controls.ReadOnly ~= nil then
        footerHeight = math.max(footerHeight, ControlHeight(Controls.ReadOnly, 22) + 12)
    end
    Controls.ArchiveScroll:SetSizeY(math.max(80, Controls.Panel:GetSizeY() - scrollY - footerHeight))
    Controls.ArchiveStack:CalculateSize()
    Controls.ArchiveStack:ReprocessAnchoring()
    Controls.ArchiveScroll:CalculateInternalSize()
end

local function Close()
    if not opened then return end
    opened = false
    UIManager:DequeuePopup(ContextPtr)
    ContextPtr:SetHide(true)
    print("[EC:UI] overview_closed")
end
local function Toggle()
    if opened then Close(); return end
    local screen = ContextPtr:LookUpControl("/InGame/Screens")
    if screen ~= nil then ContextPtr:ChangeParent(screen) end
    for _, name in ipairs({ "LaunchBar_CloseTechTree", "LaunchBar_CloseCivicsTree",
        "LaunchBar_CloseGovernmentPanel", "LaunchBar_CloseReligionPanel",
        "LaunchBar_CloseGreatPeoplePopup", "LaunchBar_CloseGreatWorksOverview",
        "GovernorPanel_Close", "Launchbar_Expansion2_ClimateScreen_Close",
        "QD_CloseDealPopupSilently" }) do PublishNamed(LuaEvents, name) end
    local _, height = UIManager:GetScreenSizeVal()
    local panelHeight = math.min(580, math.max(320, height - 110))
    Controls.Panel:SetSizeY(panelHeight)
    Controls.ArchiveScroll:SetSizeY(panelHeight - 218)
    opened = true
    warned = false
    ContextPtr:SetHide(false)
    UIManager:QueuePopup(ContextPtr, PopupPriority.Low, {
        RenderAtCurrentParent = true, InputAtCurrentParent = true, AlwaysVisibleInQueue = true,
    })
    Refresh()
    print("[EC:UI] overview_opened")
end
-- Civ VI passes a UI input object to SetInputHandler.  Keep the two-argument
-- fallback as well because a few test doubles and older contexts still call
-- handlers with (message, key).
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
    if opened and message == KeyEvents.KeyUp and inputKey == Keys.VK_ESCAPE then Close(); return true end
    return false
end
local function RemoveSubscriptions()
    for _, subscription in ipairs(subscriptions) do
        local remove, readable = ReadMember(subscription[1], "Remove")
        if readable and type(remove) == "function" then
            pcall(function() remove(subscription[2]) end)
        end
    end
    subscriptions = {}
end

local function Initialize()
    if initialized then return end
    initialized = true
    ContextPtr:SetHide(true)
    ContextPtr:SetInputHandler(OnInput, true)
    if Controls.Title ~= nil then Controls.Title:SetText(Lookup("LOC_EC_OVERVIEW_TITLE")) end
    if Controls.Notice ~= nil then Controls.Notice:SetText(Lookup("LOC_EC_OVERVIEW_NOTICE")) end
    if Controls.ReadOnly ~= nil then Controls.ReadOnly:SetText(Lookup("LOC_EC_OVERVIEW_READ_ONLY")) end
    if Controls.OperationStatus ~= nil then Controls.OperationStatus:SetText(Lookup("LOC_EC_OVERVIEW_NATIVE_PENDING")) end
    if Controls.CloseButton ~= nil then Controls.CloseButton:SetToolTipString(Lookup("LOC_EC_OVERVIEW_CLOSE")) end
    Controls.CloseButton:RegisterCallback(Mouse.eLClick, Close)
    BindNamed(LuaEvents, "EC_Overview_Toggle", Toggle)
    BindNamed(Events, "GameCoreEventPublishComplete", Refresh)
    BindNamed(Events, "LocalPlayerChanged", Close)
    BindNamed(Events, "LeaveGameComplete", Close)
    for _, name in ipairs({ "TechTree_OpenTechTree", "CivicsTree_OpenCivicsTree",
        "Government_OpenGovernment", "Religion_OpenReligion", "GreatPeople_OpenGreatPeople",
        "GreatWorks_OpenGreatWorks", "GovernorPanel_Opened", "HistoricMoments_Opened",
        "ClimateScreen_Opened", "QDDealPopup_Opened", "Tutorial_CloseAllLaunchBarScreens" }) do
        BindNamed(LuaEvents, name, Close)
    end
end

local function Shutdown()
    RemoveSubscriptions()
    Close()
    initialized = false
    rows:ResetInstances()
end

function OnInit(isReload)
    if isReload then Shutdown() end
    Initialize()
end
ContextPtr:SetInitHandler(OnInit)
ContextPtr:SetShutdown(Shutdown)
