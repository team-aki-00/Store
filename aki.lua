--[[
    ============================================================================
      TEAM AKI — Mobile Liquid-Glass Tactical Suite (Full Rebuild)
      Executors : Delta, Arceus X, Fluxus, Krnl & Universal Luau Executors
      Features  : Liquid-Glass UI + Startup Loader, Per-Game Auto-Save Config,
                  Touch-Safe 3-Mode TriggerBot (VIM / firesignal / Tool:Activate),
                  Sub-0.1 Optical ESP Thickness, Extreme Potato Graphics
    ============================================================================
]]

if not game:IsLoaded() then
    pcall(function()
        game.Loaded:Wait()
    end)
end

-- ============================================================================
-- [SECTION 1] CLEANUP OF PREVIOUS INSTANCE & EXECUTOR SHIMS
-- ============================================================================
local globalEnv = (type(getgenv) == "function" and getgenv()) or _G
local unpackFn = table.unpack or unpack

if type(globalEnv.TEAM_AKI_UNLOAD) == "function" then
    pcall(globalEnv.TEAM_AKI_UNLOAD)
end

local function getService(name)
    local svc = game:GetService(name)
    if type(cloneref) == "function" then
        local ok, cloned = pcall(cloneref, svc)
        if ok and cloned ~= nil then
            return cloned
        end
    end
    return svc
end

local function tryGetService(name)
    local ok, svc = pcall(getService, name)
    if ok then
        return svc
    end
    return nil
end

local Players = getService("Players")
local RunService = getService("RunService")
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local Workspace = getService("Workspace")
local CoreGui = tryGetService("CoreGui")
local Teams = tryGetService("Teams")
local Lighting = tryGetService("Lighting")
local StatsService = tryGetService("Stats")
local HttpService = tryGetService("HttpService")
local ContextActionService = tryGetService("ContextActionService")
local VirtualInputManager = tryGetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players.PlayerAdded:Wait()
    LocalPlayer = Players.LocalPlayer
end

local function shallowClone(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local inner = {}
            for ik, iv in pairs(v) do
                inner[ik] = iv
            end
            copy[k] = inner
        else
            copy[k] = v
        end
    end
    return copy
end

local function clearTable(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
end

local function isFiniteNumber(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function isFiniteVector3(v)
    return typeof(v) == "Vector3"
        and isFiniteNumber(v.X)
        and isFiniteNumber(v.Y)
        and isFiniteNumber(v.Z)
end

local function getSafeGuiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then
            return hui
        end
    end
    if CoreGui then
        local okCore = pcall(function()
            return CoreGui.Name
        end)
        if okCore then
            return CoreGui
        end
    end
    return LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5) or CoreGui
end

local function mountGuiSafely(gui)
    local candidates = {}
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then
            table.insert(candidates, hui)
        end
    end
    if CoreGui then
        table.insert(candidates, CoreGui)
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 5)
    if pg then
        table.insert(candidates, pg)
    end
    for _, parent in ipairs(candidates) do
        local ok = pcall(function()
            gui.Parent = parent
        end)
        if ok and gui.Parent ~= nil then
            return true
        end
    end
    return false
end

local function cleanupOrphanGuis()
    local targets = {}
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then
            table.insert(targets, hui)
        end
    end
    if CoreGui then
        table.insert(targets, CoreGui)
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        table.insert(targets, pg)
    end
    local orphanNames = {
        TEAM_AKI_Overlay = true,
        TEAM_AKI_Hub = true,
        TEAM_AKI_Highlights = true,
        TEAM_AKI_Loader = true,
    }
    for _, parent in ipairs(targets) do
        pcall(function()
            for _, child in ipairs(parent:GetChildren()) do
                if orphanNames[child.Name] then
                    child:Destroy()
                end
            end
        end)
    end
end

cleanupOrphanGuis()

local function protectGui(gui)
    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    elseif type(protect_gui) == "function" then
        pcall(protect_gui, gui)
    end
end

-- ============================================================================
-- [SECTION 2] SINGLE SOURCE OF TRUTH (CONFIG, PERSISTENCE, INPUT GUARD & STATE)
-- ============================================================================
local Config = {
    Aimbot = {
        Enabled = false,
        ActivationMode = "GUI Toggle",  -- "GUI Toggle" | "Hold"
        TargetPart = "Head",            -- "Head" | "Chest" | "HumanoidRootPart" | "Closest"
        Smoothness = 6,                 -- 1 (instant) .. 20 (smooth)
        Prediction = 0.08,              -- 0.00 .. 0.30 seconds lead time
        AutoPredict = true,             -- Automatically scales prediction with ping, distance & target velocity
        ProjectileSpeed = 0,            -- 0 = pure lead time; >0 adds Distance / Speed
        PingCompensation = false,
        FOVRadius = 135,                -- pixels
        FOVThickness = 1.5,             -- 0.1 .. 10.0 pixels
        ShowFOV = true,
        TeamCheck = true,
        VisibleCheck = true,
        StickyTarget = true,
        IgnoreBots = false,
        MaxDistance = 2000,
    },
    TriggerBot = {
        Enabled = false,
        Mode = "VirtualInputManager",   -- "VirtualInputManager" | "firesignal" | "Tool:Activate()"
        PointerLocked = true,           -- Lock/Unlock Floating VIM Pointer position
        PointerScaleX = 0.84,           -- Normalized viewport X (0.04 .. 0.96)
        PointerScaleY = 0.68,           -- Normalized viewport Y (0.06 .. 0.94)
        SavedFireSignalKey = "",        -- Confirmed firesignal candidate key for current PlaceId
        BrokenFireSignals = {},         -- Map<string, boolean> blacklisted per PlaceId
        SavedToolCallKey = "",          -- Confirmed Tool:Activate() candidate key for current PlaceId
        BrokenToolCalls = {},           -- Map<string, boolean> blacklisted per PlaceId
        SyncWithAimbot = true,          -- Syncs lead prediction, Auto Predict, ProjectileSpeed & lock target with Aimbot
        TargetFilter = "Any Part",      -- "Any Part" | "Head & Chest" | "Head Only"
        HoldToFire = false,             -- true = hold trigger while locked; false = timed tap shots
        ReactionDelay = 0.03,           -- 0.00 .. 0.30 seconds
        ShotCooldown = 0.09,            -- 0.02 .. 0.60 seconds
        CrosshairTolerance = 6,         -- 0 .. 28 px proximity sweep
        TeamCheck = true,
        VisibleCheck = true,
        IgnoreBots = false,
        MaxDistance = 1200,
        ShowIndicator = true,
    },
    ESP = {
        Enabled = true,
        RenderEngine = "ScreenGui",     -- "ScreenGui" (100% reliable mobile) | "Drawing"
        BoxESP = true,
        BoxStyle = "Corner",            -- "Corner" | "Full"
        BoxThickness = 1.5,             -- 0.1 .. 10.0 pixels
        HealthBar = true,
        ShowHealthPercent = true,
        TracerESP = true,
        TracerOrigin = "Bottom",        -- "Bottom" | "Center" | "Top"
        LineThickness = 1.5,            -- 0.1 .. 10.0 pixels
        Alert360 = true,
        Alert360VisibleOnly = false,
        AlertRingRadius = 155,
        HighlightESP = true,
        HighlightVisibleOnly = false,
        TeamCheck = true,
        VisibleCheck = false,
        IgnoreBots = false,
        ColorByVisibility = true,
        ShowName = true,
        ShowDistance = true,            -- Renders distance right beneath enemy feet
        IgnoreGlassWater = true,
        MaxDistance = 2200,
        HighlightFillTransparency = 0.62,
        HighlightOutlineTransparency = 0.10,
    },
    Resolver = {
        TeamCheckMode = "Auto",         -- "Auto" (FFA-aware) | "Team Property" | "TeamColor" | "Off"
        CustomContainerScan = true,
    },
    Performance = {
        PotatoGraphics = false,         -- Aggressive FPS booster (lowers quality, shadows, effects, textures)
    },
    Colors = {
        Visible = Color3.fromRGB(56, 232, 198),     -- Mint-Cyan (Unobstructed)
        Hidden = Color3.fromRGB(244, 63, 94),       -- Crimson (Behind Cover)
        Box = Color3.fromRGB(88, 156, 255),         -- Electric Cyan-Indigo
        Tracer = Color3.fromRGB(125, 211, 252),     -- Ice-Blue Tracer
        Alert360 = Color3.fromRGB(251, 146, 60),    -- Amber Fallback Alert
        FOV = Color3.fromRGB(110, 165, 255),        -- Ice-Cyan FOV Ring
    },
    UI = {
        Visible = true,
        ActiveTab = "Aimbot",
        SelectedColorKey = "Visible",
        ShowMobileAimButton = true,
        MobileAimLocked = false,
        ShowMobileTriggerButton = true,
        MobileTriggerLocked = false,
        AutoSaveConfig = true,
    },
}

local DefaultConfig = {
    Aimbot = shallowClone(Config.Aimbot),
    TriggerBot = shallowClone(Config.TriggerBot),
    ESP = shallowClone(Config.ESP),
    Resolver = shallowClone(Config.Resolver),
    Performance = shallowClone(Config.Performance),
    Colors = shallowClone(Config.Colors),
    UI = shallowClone(Config.UI),
}

local Registry = {}

local State = {
    Unloaded = false,
    MainGui = nil,
    MainCard = nil,
    OverlayGui = nil,
    Connections = {},
    LocalConns = {},
    LocalCharacter = nil,
    LocalHumanoid = nil,
    LocalRootPart = nil,
    LocalAlive = false,
    LastLocalPos = nil,
    Camera = Workspace.CurrentCamera,
    CurrentAimTarget = nil,
    CurrentAimPart = nil,
    CurrentAimPredictedPos = nil,
    CurrentAimFrame = 0,
    IsHoldingAim = false,
    TriggerTarget = nil,
    TriggerAcquireTime = 0,
    LastTriggerFire = 0,
    TriggerHolding = false,
    TriggerVimTouchDown = false,
    TriggerVimTouchPos = Vector2.zero,
    TriggerToolRef = nil,
    ColorListeners = {},
    SavedGraphics = nil,
    PotatoDescConn = nil,
    FrameIndex = 0,
    LastRenderTick = 0,
    ReloadCount = 0,
    ReloadToken = 0,
    LastSafetySync = 0,
    LastWorkspaceDeepScan = 0,
    LastBotScan = 0,
    LastTeamScan = -1,
    DetectedTeamScheme = "FFA",
    LastReloadReason = "Startup",
    ActiveDragCount = 0,
    DragSinkBound = false,
    ConfigSaveToken = 0,
    ConfigStatusText = "Defaults",
}

local function addConnection(conn)
    table.insert(State.Connections, conn)
    return conn
end

local function notifyColorUpdated()
    for _, callback in ipairs(State.ColorListeners) do
        pcall(callback)
    end
end

-- Direct-touch drag ownership guard (uses native GuiObject.Active = true instead of global Touch camera sinking)
local InputGuard = {}
InputGuard.ACTION_NAME = "TEAM_AKI_DragCameraSink"
InputGuard.ActiveOwner = nil
InputGuard.ActiveInput = nil

function InputGuard.isActiveState(userInputState)
    return userInputState == Enum.UserInputState.Begin or userInputState == Enum.UserInputState.Change
end

function InputGuard.isPointInGui(gui, pos, pad)
    if not gui or not pos or not gui.Visible or not gui.Parent then
        return false
    end
    local absPos = gui.AbsolutePosition
    local absSize = gui.AbsoluteSize
    if absSize.X <= 0 or absSize.Y <= 0 then
        return false
    end
    local margin = pad or 0
    return pos.X >= (absPos.X - margin)
        and pos.X <= (absPos.X + absSize.X + margin)
        and pos.Y >= (absPos.Y - margin)
        and pos.Y <= (absPos.Y + absSize.Y + margin)
end

function InputGuard.beginDrag(owner, input)
    if not owner or not input then
        return false
    end
    if input.UserInputState ~= Enum.UserInputState.Begin then
        return false
    end
    if InputGuard.ActiveOwner and InputGuard.ActiveOwner ~= owner then
        local existing = InputGuard.ActiveInput
        local okVis, ownerVisible = pcall(function()
            return InputGuard.ActiveOwner.Visible and InputGuard.ActiveOwner.Parent ~= nil
        end)
        local alive = existing and InputGuard.isActiveState(existing.UserInputState) and (okVis and ownerVisible)
        if alive then
            return false
        end
        InputGuard.ActiveOwner = nil
        InputGuard.ActiveInput = nil
    end
    InputGuard.ActiveOwner = owner
    InputGuard.ActiveInput = input
    State.ActiveDragCount = 1
    return true
end

function InputGuard.isOwner(owner, input)
    if InputGuard.ActiveOwner ~= owner or not InputGuard.ActiveInput then
        return false
    end
    if not InputGuard.isActiveState(InputGuard.ActiveInput.UserInputState) then
        InputGuard.ActiveOwner = nil
        InputGuard.ActiveInput = nil
        State.ActiveDragCount = 0
        return false
    end
    if input == InputGuard.ActiveInput then
        return InputGuard.isActiveState(input.UserInputState)
    end
    if InputGuard.ActiveInput.UserInputType == Enum.UserInputType.MouseButton1
        and input and input.UserInputType == Enum.UserInputType.MouseMovement then
        return true
    end
    return false
end

function InputGuard.endDrag(owner)
    if owner == nil or InputGuard.ActiveOwner == owner then
        InputGuard.ActiveOwner = nil
        InputGuard.ActiveInput = nil
        State.ActiveDragCount = 0
    end
end

function InputGuard.forceReleaseAll()
    InputGuard.ActiveOwner = nil
    InputGuard.ActiveInput = nil
    State.ActiveDragCount = 0
    if State.DragSinkBound and ContextActionService then
        pcall(function()
            ContextActionService:UnbindAction(InputGuard.ACTION_NAME)
        end)
    end
    State.DragSinkBound = false
end

-- Per-game (PlaceId) configuration persistence with safe executor file fallback
local ConfigStore = {}
ConfigStore.FOLDER = "TEAM_AKI_Configs"
ConfigStore.StatusListeners = {}

function ConfigStore.hasFileApi()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
        and HttpService ~= nil
end

function ConfigStore.getFilePath()
    local pid = tonumber(game and game.PlaceId) or 0
    return string.format("%s/place_%d.json", ConfigStore.FOLDER, pid)
end

function ConfigStore.notifyStatus()
    for _, cb in ipairs(ConfigStore.StatusListeners) do
        pcall(cb, State.ConfigStatusText)
    end
end

function ConfigStore.serializeValue(val)
    if typeof(val) == "Color3" then
        return {
            __type = "Color3",
            r = math.round(val.R * 255),
            g = math.round(val.G * 255),
            b = math.round(val.B * 255),
        }
    elseif type(val) == "table" then
        local out = {}
        for k, v in pairs(val) do
            if type(k) == "string" then
                out[k] = ConfigStore.serializeValue(v)
            end
        end
        return out
    elseif type(val) == "number" or type(val) == "boolean" or type(val) == "string" then
        return val
    end
    return nil
end

function ConfigStore.applyTable(dst, src)
    if type(dst) ~= "table" or type(src) ~= "table" then
        return
    end
    for k, dv in pairs(dst) do
        local sv = src[k]
        if sv ~= nil then
            if typeof(dv) == "Color3" and type(sv) == "table" and sv.__type == "Color3" then
                local r = math.clamp(tonumber(sv.r) or 255, 0, 255)
                local g = math.clamp(tonumber(sv.g) or 255, 0, 255)
                local b = math.clamp(tonumber(sv.b) or 255, 0, 255)
                dst[k] = Color3.fromRGB(r, g, b)
            elseif type(dv) == "table" and type(sv) == "table" then
                -- For open-ended maps like BrokenFireSignals / BrokenToolCalls, copy keys directly
                if next(dv) == nil then
                    for mk, mv in pairs(sv) do
                        if type(mk) == "string" and type(mv) == "boolean" then
                            dv[mk] = mv
                        end
                    end
                else
                    ConfigStore.applyTable(dv, sv)
                end
            elseif type(dv) == type(sv) then
                dst[k] = sv
            end
        end
    end
end

function ConfigStore.sanitizeConfig()
    Config.Aimbot.FOVThickness = math.clamp(math.round((Config.Aimbot.FOVThickness or 1.5) * 10) / 10, 0.1, 10.0)
    Config.ESP.BoxThickness = math.clamp(math.round((Config.ESP.BoxThickness or 1.5) * 10) / 10, 0.1, 10.0)
    Config.ESP.LineThickness = math.clamp(math.round((Config.ESP.LineThickness or 1.5) * 10) / 10, 0.1, 10.0)
    Config.TriggerBot.PointerScaleX = math.clamp(Config.TriggerBot.PointerScaleX or 0.84, 0.04, 0.96)
    Config.TriggerBot.PointerScaleY = math.clamp(Config.TriggerBot.PointerScaleY or 0.68, 0.06, 0.94)
    if Config.TriggerBot.Mode ~= "VirtualInputManager"
        and Config.TriggerBot.Mode ~= "firesignal"
        and Config.TriggerBot.Mode ~= "Tool:Activate()"
    then
        Config.TriggerBot.Mode = "VirtualInputManager"
    end
    -- Always keep combat arms off at fresh game join for mobile safety unless user toggles ON
    Config.Aimbot.Enabled = false
    Config.UI.MobileAimLocked = false
    Config.TriggerBot.Enabled = false
    Config.UI.MobileTriggerLocked = false
    Config.UI.Visible = true
end

function ConfigStore.saveNow()
    if not ConfigStore.hasFileApi() then
        State.ConfigStatusText = "Memory Only (No File API)"
        ConfigStore.notifyStatus()
        return false
    end
    local ok = pcall(function()
        if type(isfolder) == "function" and type(makefolder) == "function" then
            if not isfolder(ConfigStore.FOLDER) then
                makefolder(ConfigStore.FOLDER)
            end
        end
        local payload = ConfigStore.serializeValue({
            Aimbot = Config.Aimbot,
            TriggerBot = Config.TriggerBot,
            ESP = Config.ESP,
            Resolver = Config.Resolver,
            Performance = Config.Performance,
            Colors = Config.Colors,
            UI = Config.UI,
        })
        local encoded = HttpService:JSONEncode(payload)
        writefile(ConfigStore.getFilePath(), encoded)
    end)
    if ok then
        local pid = tonumber(game and game.PlaceId) or 0
        State.ConfigStatusText = string.format("Saved (Place %d)", pid)
    else
        State.ConfigStatusText = "Save Skipped"
    end
    ConfigStore.notifyStatus()
    return ok
end

function ConfigStore.scheduleSave()
    if State.Unloaded or not Config.UI.AutoSaveConfig then
        return
    end
    State.ConfigSaveToken = (State.ConfigSaveToken or 0) + 1
    local myToken = State.ConfigSaveToken
    task.delay(0.35, function()
        if (not State.Unloaded) and State.ConfigSaveToken == myToken and Config.UI.AutoSaveConfig then
            ConfigStore.saveNow()
        end
    end)
end

function ConfigStore.loadNow()
    if not ConfigStore.hasFileApi() then
        State.ConfigStatusText = "Defaults (No File API)"
        return false
    end
    local path = ConfigStore.getFilePath()
    local okExists, exists = pcall(isfile, path)
    if not okExists or not exists then
        State.ConfigStatusText = string.format("New Profile (Place %d)", tonumber(game and game.PlaceId) or 0)
        return false
    end
    local okRead, raw = pcall(readfile, path)
    if not okRead or type(raw) ~= "string" or raw == "" then
        State.ConfigStatusText = "Defaults (Empty Save)"
        return false
    end
    local okDec, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not okDec or type(decoded) ~= "table" then
        State.ConfigStatusText = "Defaults (Invalid JSON)"
        return false
    end
    ConfigStore.applyTable(Config.Aimbot, decoded.Aimbot)
    ConfigStore.applyTable(Config.TriggerBot, decoded.TriggerBot)
    ConfigStore.applyTable(Config.ESP, decoded.ESP)
    ConfigStore.applyTable(Config.Resolver, decoded.Resolver)
    ConfigStore.applyTable(Config.Performance, decoded.Performance)
    ConfigStore.applyTable(Config.Colors, decoded.Colors)
    ConfigStore.applyTable(Config.UI, decoded.UI)
    ConfigStore.sanitizeConfig()
    State.ConfigStatusText = string.format("Loaded (Place %d)", tonumber(game and game.PlaceId) or 0)
    return true
end

ConfigStore.loadNow()

-- ============================================================================
-- [SECTION 3] RELIABLE SCREENGUI-FIRST + OPTIONAL DRAWING OVERLAY ENGINE
-- ============================================================================
local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "TEAM_AKI_Overlay"
OverlayGui.IgnoreGuiInset = true
OverlayGui.ResetOnSpawn = false
OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
OverlayGui.DisplayOrder = 999
protectGui(OverlayGui)
mountGuiSafely(OverlayGui)
State.OverlayGui = OverlayGui

local EspContainer = Instance.new("Folder")
EspContainer.Name = "ESP_Elements"
EspContainer.Parent = OverlayGui

local function getHighlightParent()
    local okCore = pcall(function()
        return CoreGui.Name
    end)
    if okCore then
        return CoreGui
    end
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        return pg
    end
    return OverlayGui
end

local HighlightContainer = Instance.new("Folder")
HighlightContainer.Name = "TEAM_AKI_Highlights"
do
    local okHighlightParent = pcall(function()
        HighlightContainer.Parent = getHighlightParent()
    end)
    if not okHighlightParent or not HighlightContainer.Parent then
        HighlightContainer.Parent = OverlayGui
    end
end

local DrawingSupported = false
do
    local ok, res = pcall(function()
        if Drawing and type(Drawing.new) == "function" then
            local probe = Drawing.new("Line")
            if probe ~= nil then
                probe.Visible = false
                if type(probe.Remove) == "function" then
                    probe:Remove()
                elseif type(probe.Destroy) == "function" then
                    probe:Destroy()
                end
                return true
            end
        end
        return false
    end)
    DrawingSupported = ok and res == true
end

local function safeNewDrawing(kind)
    local ok, obj = pcall(function()
        local inst = Drawing.new(kind)
        if inst ~= nil then
            inst.Visible = false
            pcall(function()
                inst.Transparency = 1
            end)
        end
        return inst
    end)
    if ok then
        return obj
    end
    return nil
end

local function safeDestroyDrawing(obj)
    if not obj then
        return
    end
    pcall(function()
        obj.Visible = false
        if type(obj.Remove) == "function" then
            obj:Remove()
        elseif type(obj.Destroy) == "function" then
            obj:Destroy()
        end
    end)
end

local function shouldUseDrawing()
    return DrawingSupported and Config.ESP.RenderEngine == "Drawing"
end

-- Optical hairline resolver: prevents <1.0 px lines/strokes from vanishing on mobile DPI or Drawing APIs
local VisualHelper = {}

function VisualHelper.resolveFrameThickness(rawT)
    local t = math.clamp(tonumber(rawT) or 1, 0.1, 10.0)
    local phys = math.max(t, 1)
    local opticalTrans = (t < 1.0) and math.clamp((1 - t) * 0.58, 0, 0.54) or 0
    return phys, opticalTrans
end

function VisualHelper.resolveStrokeThickness(rawT, baseTrans)
    local t = math.clamp(tonumber(rawT) or 1, 0.1, 10.0)
    local phys = math.max(t, 0.85)
    local base = baseTrans or 0
    local opticalTrans = (t < 1.0) and math.clamp(base + (1 - t) * 0.54, base, 0.72) or base
    return phys, opticalTrans
end

function VisualHelper.resolveDrawingThickness(rawT, baseOpacity)
    local t = math.clamp(tonumber(rawT) or 1, 0.1, 10.0)
    local phys = math.max(t, 1)
    local op = baseOpacity or 1
    if t < 1.0 then
        op = math.clamp(op * (0.42 + t * 0.58), 0.35, op)
    end
    return phys, op
end

-- FOV Circle (ScreenGui + optional Drawing synced cleanly)
local DrawingFOV = nil
if DrawingSupported then
    DrawingFOV = safeNewDrawing("Circle")
    if DrawingFOV then
        pcall(function()
            local fovT, fovOp = VisualHelper.resolveDrawingThickness(Config.Aimbot.FOVThickness, 0.9)
            DrawingFOV.Filled = false
            DrawingFOV.NumSides = 64
            DrawingFOV.Transparency = fovOp
            DrawingFOV.Thickness = fovT
            DrawingFOV.Color = Config.Colors.FOV
        end)
    end
end

local FOVRingFrame = Instance.new("Frame")
FOVRingFrame.Name = "FOVRing"
FOVRingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
FOVRingFrame.Position = UDim2.fromScale(0.5, 0.5)
FOVRingFrame.BackgroundTransparency = 1
FOVRingFrame.Visible = false
FOVRingFrame.Parent = OverlayGui

local FOVStroke = Instance.new("UIStroke")
do
    local st, strans = VisualHelper.resolveStrokeThickness(Config.Aimbot.FOVThickness, 0.15)
    FOVStroke.Thickness = st
    FOVStroke.Transparency = strans
end
FOVStroke.Color = Config.Colors.FOV
FOVStroke.Parent = FOVRingFrame

local TriggerDot = Instance.new("Frame")
TriggerDot.Name = "TriggerCrosshairDot"
TriggerDot.AnchorPoint = Vector2.new(0.5, 0.5)
TriggerDot.Position = UDim2.fromScale(0.5, 0.5)
TriggerDot.Size = UDim2.fromOffset(7, 7)
TriggerDot.BackgroundColor3 = Color3.fromRGB(251, 146, 60)
TriggerDot.BackgroundTransparency = 0.15
TriggerDot.BorderSizePixel = 0
TriggerDot.Visible = false
TriggerDot.ZIndex = 6
TriggerDot.Parent = OverlayGui

do
    local fovCorner = Instance.new("UICorner")
    fovCorner.CornerRadius = UDim.new(1, 0)
    fovCorner.Parent = FOVRingFrame

    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = TriggerDot

    local dotStroke = Instance.new("UIStroke")
    dotStroke.Thickness = 1.2
    dotStroke.Color = Color3.fromRGB(11, 13, 20)
    dotStroke.Transparency = 0.2
    dotStroke.Parent = TriggerDot
end

local function createRegistryVisualBundle()
    local guiRoot = Instance.new("Folder")
    guiRoot.Parent = EspContainer

    local fullBoxFrame = Instance.new("Frame")
    fullBoxFrame.BackgroundTransparency = 1
    fullBoxFrame.BorderSizePixel = 0
    fullBoxFrame.Visible = false
    fullBoxFrame.Parent = guiRoot

    local fullBoxStroke = Instance.new("UIStroke")
    fullBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    fullBoxStroke.Thickness = Config.ESP.BoxThickness
    fullBoxStroke.Color = Config.Colors.Box
    fullBoxStroke.Parent = fullBoxFrame

    local cornerSegs = {}
    for i = 1, 8 do
        local seg = Instance.new("Frame")
        seg.BorderSizePixel = 0
        seg.Visible = false
        seg.ZIndex = 2
        seg.Parent = guiRoot
        cornerSegs[i] = seg
    end

    local hpBack = Instance.new("Frame")
    hpBack.BackgroundColor3 = Color3.fromRGB(11, 13, 20)
    hpBack.BackgroundTransparency = 0.22
    hpBack.BorderSizePixel = 0
    hpBack.Visible = false
    hpBack.ZIndex = 2
    hpBack.Parent = guiRoot

    local hpBackStroke = Instance.new("UIStroke")
    hpBackStroke.Thickness = 1
    hpBackStroke.Color = Color3.fromRGB(0, 0, 0)
    hpBackStroke.Transparency = 0.3
    hpBackStroke.Parent = hpBack

    local hpFill = Instance.new("Frame")
    hpFill.AnchorPoint = Vector2.new(0, 1)
    hpFill.Position = UDim2.fromScale(0, 1)
    hpFill.Size = UDim2.fromScale(1, 1)
    hpFill.BorderSizePixel = 0
    hpFill.ZIndex = 3
    hpFill.Parent = hpBack

    local hpTextLabel = Instance.new("TextLabel")
    hpTextLabel.BackgroundTransparency = 1
    hpTextLabel.AnchorPoint = Vector2.new(1, 0.5)
    hpTextLabel.Size = UDim2.fromOffset(40, 14)
    hpTextLabel.Font = Enum.Font.Code
    hpTextLabel.TextSize = 10
    hpTextLabel.TextColor3 = Color3.fromRGB(242, 245, 252)
    hpTextLabel.TextStrokeTransparency = 0.25
    hpTextLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    hpTextLabel.TextXAlignment = Enum.TextXAlignment.Right
    hpTextLabel.Visible = false
    hpTextLabel.ZIndex = 3
    hpTextLabel.Parent = guiRoot

    local tracerFrame = Instance.new("Frame")
    tracerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    tracerFrame.BorderSizePixel = 0
    tracerFrame.Visible = false
    tracerFrame.ZIndex = 1
    tracerFrame.Parent = guiRoot

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Size = UDim2.fromOffset(220, 18)
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 12
    nameLabel.TextColor3 = Color3.fromRGB(242, 245, 252)
    nameLabel.TextStrokeTransparency = 0.25
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Visible = false
    nameLabel.ZIndex = 3
    nameLabel.Parent = guiRoot

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "DistLabel"
    distLabel.BackgroundTransparency = 1
    distLabel.AnchorPoint = Vector2.new(0.5, 0)
    distLabel.Size = UDim2.fromOffset(140, 16)
    distLabel.Font = Enum.Font.Code
    distLabel.TextSize = 11
    distLabel.TextColor3 = Color3.fromRGB(205, 224, 255)
    distLabel.TextStrokeTransparency = 0.22
    distLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    distLabel.Visible = false
    distLabel.ZIndex = 3
    distLabel.Parent = guiRoot

    local arrowHolder = Instance.new("Frame")
    arrowHolder.BackgroundTransparency = 1
    arrowHolder.AnchorPoint = Vector2.new(0.5, 0.5)
    arrowHolder.Size = UDim2.fromOffset(18, 18)
    arrowHolder.Visible = false
    arrowHolder.ZIndex = 4
    arrowHolder.Parent = guiRoot

    local arrowLeft = Instance.new("Frame")
    arrowLeft.BorderSizePixel = 0
    arrowLeft.AnchorPoint = Vector2.new(0.5, 0.5)
    arrowLeft.Position = UDim2.fromScale(0.35, 0.5)
    arrowLeft.Size = UDim2.fromOffset(11, 3)
    arrowLeft.Rotation = -45
    arrowLeft.ZIndex = 4
    arrowLeft.Parent = arrowHolder

    local arrowRight = Instance.new("Frame")
    arrowRight.BorderSizePixel = 0
    arrowRight.AnchorPoint = Vector2.new(0.5, 0.5)
    arrowRight.Position = UDim2.fromScale(0.65, 0.5)
    arrowRight.Size = UDim2.fromOffset(11, 3)
    arrowRight.Rotation = 45
    arrowRight.ZIndex = 4
    arrowRight.Parent = arrowHolder

    local drawCache = nil
    local function ensureDrawingCache()
        if drawCache then
            return drawCache
        end
        if not DrawingSupported then
            return nil
        end

        local boxObj = safeNewDrawing("Square")
        local hpBackObj = safeNewDrawing("Square")
        local hpFillObj = safeNewDrawing("Square")
        local tracerObj = safeNewDrawing("Line")
        local labelObj = safeNewDrawing("Text")
        local distObj = safeNewDrawing("Text")
        local hpTextObj = safeNewDrawing("Text")
        local arrowObj = safeNewDrawing("Triangle")

        if not (boxObj and hpBackObj and hpFillObj and tracerObj and labelObj) then
            safeDestroyDrawing(boxObj)
            safeDestroyDrawing(hpBackObj)
            safeDestroyDrawing(hpFillObj)
            safeDestroyDrawing(tracerObj)
            safeDestroyDrawing(labelObj)
            safeDestroyDrawing(distObj)
            safeDestroyDrawing(hpTextObj)
            safeDestroyDrawing(arrowObj)
            return nil
        end

        local corners = {}
        for i = 1, 8 do
            local ln = safeNewDrawing("Line")
            if not ln then
                for j = 1, i - 1 do safeDestroyDrawing(corners[j]) end
                safeDestroyDrawing(boxObj)
                safeDestroyDrawing(hpBackObj)
                safeDestroyDrawing(hpFillObj)
                safeDestroyDrawing(tracerObj)
                safeDestroyDrawing(labelObj)
                safeDestroyDrawing(distObj)
                safeDestroyDrawing(hpTextObj)
                safeDestroyDrawing(arrowObj)
                return nil
            end
            corners[i] = ln
        end

        pcall(function()
            boxObj.Filled = false
            hpBackObj.Filled = true
            hpBackObj.Color = Color3.fromRGB(11, 13, 20)
            hpFillObj.Filled = true
            labelObj.Center = true
            labelObj.Outline = true
            labelObj.Size = 13
            if Drawing.Fonts and Drawing.Fonts.UI then
                labelObj.Font = Drawing.Fonts.UI
            else
                labelObj.Font = 2
            end
            if distObj then
                distObj.Center = true
                distObj.Outline = true
                distObj.Size = 12
                distObj.Color = Color3.fromRGB(205, 224, 255)
                distObj.Font = 2
            end
            if hpTextObj then
                hpTextObj.Center = false
                hpTextObj.Outline = true
                hpTextObj.Size = 11
                hpTextObj.Color = Color3.fromRGB(242, 245, 252)
                hpTextObj.Font = 2
            end
            if arrowObj then
                arrowObj.Filled = true
                arrowObj.Thickness = 1
            end
        end)

        drawCache = {
            Box = boxObj,
            Corners = corners,
            HpBack = hpBackObj,
            HpFill = hpFillObj,
            HpText = hpTextObj,
            Tracer = tracerObj,
            Arrow = arrowObj,
            Label = labelObj,
            DistLabel = distObj,
        }
        return drawCache
    end

    local function hideDrawing()
        if not drawCache then
            return
        end
        pcall(function()
            drawCache.Box.Visible = false
            for i = 1, 8 do
                drawCache.Corners[i].Visible = false
            end
            drawCache.HpBack.Visible = false
            drawCache.HpFill.Visible = false
            if drawCache.HpText then drawCache.HpText.Visible = false end
            drawCache.Tracer.Visible = false
            if drawCache.Arrow then drawCache.Arrow.Visible = false end
            drawCache.Label.Visible = false
            if drawCache.DistLabel then drawCache.DistLabel.Visible = false end
        end)
    end

    local function hideGui()
        fullBoxFrame.Visible = false
        for i = 1, 8 do
            cornerSegs[i].Visible = false
        end
        hpBack.Visible = false
        hpTextLabel.Visible = false
        tracerFrame.Visible = false
        nameLabel.Visible = false
        distLabel.Visible = false
        arrowHolder.Visible = false
    end

    return {
        BoxLines = cornerSegs,
        TracerLine = tracerFrame,
        HealthBg = hpBack,
        HealthFill = hpFill,
        AlertArrow = arrowHolder,
        IsGuiAlive = function()
            return guiRoot ~= nil and guiRoot.Parent ~= nil
        end,
        HideAll = function()
            hideGui()
            hideDrawing()
        end,
        Render = function(self, state)
            local useDraw = shouldUseDrawing() and ensureDrawingCache() ~= nil
            if useDraw then
                hideGui()
                local d = drawCache
                pcall(function()
                    if state.ShowBox then
                        local x, y, w, h = state.BX, state.BY, state.BW, state.BH
                        local t, boxOp = VisualHelper.resolveDrawingThickness(state.BoxThickness, 0.96)
                        local col = state.BoxColor
                        if state.BoxStyle == "Full" then
                            d.Box.Visible = true
                            d.Box.Position = Vector2.new(x, y)
                            d.Box.Size = Vector2.new(w, h)
                            d.Box.Color = col
                            d.Box.Thickness = t
                            d.Box.Transparency = boxOp
                            for i = 1, 8 do d.Corners[i].Visible = false end
                        else
                            d.Box.Visible = false
                            local cw = math.max(math.clamp(w * 0.25, 4, 24), t + 2)
                            local ch = math.max(math.clamp(h * 0.22, 4, 24), t + 2)
                            local segs = {
                                { Vector2.new(x, y), Vector2.new(x + cw, y) },
                                { Vector2.new(x, y), Vector2.new(x, y + ch) },
                                { Vector2.new(x + w, y), Vector2.new(x + w - cw, y) },
                                { Vector2.new(x + w, y), Vector2.new(x + w, y + ch) },
                                { Vector2.new(x, y + h), Vector2.new(x + cw, y + h) },
                                { Vector2.new(x, y + h), Vector2.new(x, y + h - ch) },
                                { Vector2.new(x + w, y + h), Vector2.new(x + w - cw, y + h) },
                                { Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - ch) },
                            }
                            for i = 1, 8 do
                                local ln = d.Corners[i]
                                ln.Visible = true
                                ln.From = segs[i][1]
                                ln.To = segs[i][2]
                                ln.Color = col
                                ln.Thickness = t
                                ln.Transparency = boxOp
                            end
                        end
                    else
                        d.Box.Visible = false
                        for i = 1, 8 do d.Corners[i].Visible = false end
                    end

                    if state.ShowHealth then
                        local barX = state.BX - 6
                        local barY = state.BY
                        local barW = 3
                        local barH = math.max(state.BH, 2)
                        local fillH = barH * state.HealthRatio
                        d.HpBack.Visible = true
                        d.HpBack.Position = Vector2.new(barX - 1, barY - 1)
                        d.HpBack.Size = Vector2.new(barW + 2, barH + 2)
                        d.HpFill.Visible = fillH > 0.5
                        d.HpFill.Position = Vector2.new(barX, barY + (barH - fillH))
                        d.HpFill.Size = Vector2.new(barW, fillH)
                        d.HpFill.Color = state.HealthColor

                        if d.HpText then
                            if state.ShowHealthText and state.BH >= 14 then
                                d.HpText.Visible = true
                                d.HpText.Text = string.format("%d%%", math.round(state.HealthRatio * 100))
                                d.HpText.Color = state.HealthColor
                                d.HpText.Position = Vector2.new(barX - 30, math.clamp(barY + (barH - fillH) - 6, barY - 2, barY + barH - 10))
                            else
                                d.HpText.Visible = false
                            end
                        end
                    else
                        d.HpBack.Visible = false
                        d.HpFill.Visible = false
                        if d.HpText then d.HpText.Visible = false end
                    end

                    if state.ShowName then
                        d.Label.Visible = true
                        d.Label.Position = Vector2.new(state.BX + state.BW * 0.5, state.BY - 16)
                        d.Label.Text = state.NameText
                        d.Label.Color = state.BoxColor
                    else
                        d.Label.Visible = false
                    end

                    if d.DistLabel then
                        if state.ShowDist then
                            d.DistLabel.Visible = true
                            d.DistLabel.Position = Vector2.new(state.FeetX, state.FeetY)
                            d.DistLabel.Text = state.DistText
                            d.DistLabel.Color = state.BoxColor
                        else
                            d.DistLabel.Visible = false
                        end
                    end

                    if state.ShowTracer then
                        local lt, lineOp = VisualHelper.resolveDrawingThickness(state.LineThickness, 0.94)
                        d.Tracer.Visible = true
                        d.Tracer.From = state.TracerFrom
                        d.Tracer.To = state.TracerTo
                        d.Tracer.Color = state.TracerColor
                        d.Tracer.Thickness = lt
                        d.Tracer.Transparency = lineOp
                    else
                        d.Tracer.Visible = false
                    end

                    if d.Arrow then
                        if state.ShowArrow then
                            local dir = Vector2.new(math.cos(state.ArrowAngle), math.sin(state.ArrowAngle))
                            local perp = Vector2.new(-dir.Y, dir.X)
                            local tip = state.ArrowPos
                            local baseCenter = tip - dir * 14
                            local at, aOp = VisualHelper.resolveDrawingThickness(math.min(state.LineThickness, 6), 0.96)
                            d.Arrow.Visible = true
                            d.Arrow.PointA = tip
                            d.Arrow.PointB = baseCenter + perp * 7
                            d.Arrow.PointC = baseCenter - perp * 7
                            d.Arrow.Color = state.ArrowColor
                            d.Arrow.Thickness = at
                            d.Arrow.Transparency = aOp
                        else
                            d.Arrow.Visible = false
                        end
                    end
                end)
                return
            end

            -- Reliable Native ScreenGui Render Path (Sub-0.1 optical hairline support)
            hideDrawing()

            if state.ShowBox then
                local x, y, w, h = state.BX, state.BY, state.BW, state.BH
                local col = state.BoxColor

                if state.BoxStyle == "Full" then
                    local strokeT, strokeTrans = VisualHelper.resolveStrokeThickness(state.BoxThickness, 0.04)
                    fullBoxFrame.Visible = true
                    fullBoxFrame.Position = UDim2.fromOffset(x, y)
                    fullBoxFrame.Size = UDim2.fromOffset(w, h)
                    fullBoxStroke.Color = col
                    fullBoxStroke.Thickness = strokeT
                    fullBoxStroke.Transparency = strokeTrans
                    for i = 1, 8 do cornerSegs[i].Visible = false end
                else
                    local t, barTrans = VisualHelper.resolveFrameThickness(state.BoxThickness)
                    fullBoxFrame.Visible = false
                    local cw = math.max(math.clamp(w * 0.25, 4, 24), t + 2)
                    local ch = math.max(math.clamp(h * 0.22, 4, 24), t + 2)

                    cornerSegs[1].Position = UDim2.fromOffset(x, y)
                    cornerSegs[1].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[2].Position = UDim2.fromOffset(x, y)
                    cornerSegs[2].Size = UDim2.fromOffset(t, ch)

                    cornerSegs[3].Position = UDim2.fromOffset(x + w - cw, y)
                    cornerSegs[3].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[4].Position = UDim2.fromOffset(x + w - t, y)
                    cornerSegs[4].Size = UDim2.fromOffset(t, ch)

                    cornerSegs[5].Position = UDim2.fromOffset(x, y + h - t)
                    cornerSegs[5].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[6].Position = UDim2.fromOffset(x, y + h - ch)
                    cornerSegs[6].Size = UDim2.fromOffset(t, ch)

                    cornerSegs[7].Position = UDim2.fromOffset(x + w - cw, y + h - t)
                    cornerSegs[7].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[8].Position = UDim2.fromOffset(x + w - t, y + h - ch)
                    cornerSegs[8].Size = UDim2.fromOffset(t, ch)

                    for i = 1, 8 do
                        cornerSegs[i].BackgroundColor3 = col
                        cornerSegs[i].BackgroundTransparency = barTrans
                        cornerSegs[i].Visible = true
                    end
                end
            else
                fullBoxFrame.Visible = false
                for i = 1, 8 do cornerSegs[i].Visible = false end
            end

            if state.ShowHealth then
                local barH = math.max(state.BH, 2)
                hpBack.Visible = true
                hpBack.Position = UDim2.fromOffset(state.BX - 6, state.BY)
                hpBack.Size = UDim2.fromOffset(3, barH)
                hpFill.Size = UDim2.fromScale(1, state.HealthRatio)
                hpFill.BackgroundColor3 = state.HealthColor

                if state.ShowHealthText and state.BH >= 14 then
                    hpTextLabel.Visible = true
                    hpTextLabel.Text = string.format("%d%%", math.round(state.HealthRatio * 100))
                    hpTextLabel.TextColor3 = state.HealthColor
                    hpTextLabel.Position = UDim2.fromOffset(state.BX - 9, math.clamp(state.BY + barH * (1 - state.HealthRatio), state.BY, state.BY + barH))
                else
                    hpTextLabel.Visible = false
                end
            else
                hpBack.Visible = false
                hpTextLabel.Visible = false
            end

            if state.ShowName then
                nameLabel.Visible = true
                nameLabel.Position = UDim2.fromOffset(state.BX + state.BW * 0.5, state.BY - 3)
                nameLabel.Text = state.NameText
                nameLabel.TextColor3 = state.BoxColor
            else
                nameLabel.Visible = false
            end

            if state.ShowDist then
                distLabel.Visible = true
                distLabel.Position = UDim2.fromOffset(state.FeetX, state.FeetY)
                distLabel.Text = state.DistText
                distLabel.TextColor3 = state.BoxColor
            else
                distLabel.Visible = false
            end

            if state.ShowTracer then
                local delta = state.TracerTo - state.TracerFrom
                local mid = (state.TracerFrom + state.TracerTo) * 0.5
                local lineT, lineTrans = VisualHelper.resolveFrameThickness(state.LineThickness)
                tracerFrame.Visible = true
                tracerFrame.Position = UDim2.fromOffset(mid.X, mid.Y)
                tracerFrame.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), lineT)
                tracerFrame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                tracerFrame.BackgroundColor3 = state.TracerColor
                tracerFrame.BackgroundTransparency = lineTrans
            else
                tracerFrame.Visible = false
            end

            if state.ShowArrow then
                local rawArrowT = math.min(state.LineThickness, 6)
                local arrowT, arrowTrans = VisualHelper.resolveFrameThickness(rawArrowT)
                arrowT = math.max(arrowT, 1.5)
                arrowHolder.Visible = true
                arrowHolder.Position = UDim2.fromOffset(state.ArrowPos.X, state.ArrowPos.Y)
                arrowHolder.Rotation = math.deg(state.ArrowAngle) + 90
                arrowLeft.Size = UDim2.fromOffset(11, arrowT)
                arrowRight.Size = UDim2.fromOffset(11, arrowT)
                arrowLeft.BackgroundColor3 = state.ArrowColor
                arrowRight.BackgroundColor3 = state.ArrowColor
                arrowLeft.BackgroundTransparency = arrowTrans
                arrowRight.BackgroundTransparency = arrowTrans
            else
                arrowHolder.Visible = false
            end
        end,
        Destroy = function()
            pcall(function()
                guiRoot:Destroy()
            end)
            if drawCache then
                safeDestroyDrawing(drawCache.Box)
                for i = 1, 8 do safeDestroyDrawing(drawCache.Corners[i]) end
                safeDestroyDrawing(drawCache.HpBack)
                safeDestroyDrawing(drawCache.HpFill)
                safeDestroyDrawing(drawCache.HpText)
                safeDestroyDrawing(drawCache.Tracer)
                safeDestroyDrawing(drawCache.Arrow)
                safeDestroyDrawing(drawCache.Label)
                safeDestroyDrawing(drawCache.DistLabel)
                drawCache = nil
            end
        end,
    }
end

-- ============================================================================
-- [SECTION 4] EVENT-DRIVEN REGISTRY, CHARACTER RESOLVER & FULL RELOAD
-- ============================================================================
local RIG_PART_NAMES = {
    Head = true,
    UpperTorso = true,
    LowerTorso = true,
    Torso = true,
    HumanoidRootPart = true,
    LeftUpperArm = true,
    LeftLowerArm = true,
    LeftHand = true,
    RightUpperArm = true,
    RightLowerArm = true,
    RightHand = true,
    LeftArm = true,
    ["Left Arm"] = true,
    RightArm = true,
    ["Right Arm"] = true,
    LeftUpperLeg = true,
    LeftLowerLeg = true,
    LeftFoot = true,
    RightUpperLeg = true,
    RightLowerLeg = true,
    RightFoot = true,
    LeftLeg = true,
    ["Left Leg"] = true,
    RightLeg = true,
    ["Right Leg"] = true,
}

local CUSTOM_CHAR_FOLDERS = {
    "Players", "Characters", "Entities", "ActivePlayers", "Rigs",
    "GamePlayers", "Living", "Bots", "Units", "Models", "WorkspacePlayers", "Targets",
}
local SAFETY_SYNC_INTERVAL = 1.0

local ScheduleReload
local ReloadAllSystems

local function hasInstanceParts(inst)
    if not inst then
        return false
    end
    if inst:IsA("BasePart") then
        return true
    end
    return inst:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function isCandidateModelForPlayer(model, player)
    if not model or (not model:IsA("Model") and not model:IsA("BasePart")) or not model:IsDescendantOf(Workspace) then
        return false, false
    end
    if not hasInstanceParts(model) then
        return false, false
    end

    local matched = false
    local name = model.Name
    if name == player.Name or name == player.DisplayName or name == tostring(player.UserId) then
        matched = true
    end
    if not matched then
        local uid = model:GetAttribute("UserId") or model:GetAttribute("PlayerId") or model:GetAttribute("OwnerId")
        if uid == player.UserId then
            matched = true
        end
    end
    if not matched then
        local ownerVal = model:FindFirstChild("Player") or model:FindFirstChild("Owner") or model:FindFirstChild("Creator")
        if ownerVal and ownerVal:IsA("ObjectValue") and ownerVal.Value == player then
            matched = true
        end
    end
    if not matched then
        return false, false
    end

    local hum = model:FindFirstChildOfClass("Humanoid")
    local isAlive = (hum == nil) or (hum.MaxHealth <= 0) or (hum.Health > 0) or (model:GetAttribute("Alive") == true)
    return true, isAlive
end

local function scanContainerForPlayer(container, player)
    if not container then
        return nil
    end
    local fallback = nil
    local byName = container:FindFirstChild(player.Name) or container:FindFirstChild(player.DisplayName)
    if byName then
        local ok, alive = isCandidateModelForPlayer(byName, player)
        if ok then
            if alive then
                return byName
            end
            fallback = byName
        end
    end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("Model") or child:IsA("BasePart") then
            local ok, alive = isCandidateModelForPlayer(child, player)
            if ok then
                if alive then
                    return child
                end
                fallback = fallback or child
            end
        end
    end
    return fallback
end

local function resolveCharacterForPlayer(player, allowDeepScan)
    local directChar = player.Character
    if directChar and directChar.Parent and directChar:IsDescendantOf(Workspace) then
        if hasInstanceParts(directChar) then
            return directChar
        end
    end

    if not Config.Resolver.CustomContainerScan then
        if directChar and directChar.Parent and directChar:IsDescendantOf(Workspace) then
            return directChar
        end
        return nil
    end

    for _, folderName in ipairs(CUSTOM_CHAR_FOLDERS) do
        local found = scanContainerForPlayer(Workspace:FindFirstChild(folderName), player)
        if found then
            return found
        end
    end

    local wsDirect = Workspace:FindFirstChild(player.Name) or Workspace:FindFirstChild(player.DisplayName)
    if wsDirect then
        local okDirect = isCandidateModelForPlayer(wsDirect, player)
        if okDirect then
            return wsDirect
        end
    end

    if allowDeepScan then
        for _, child in ipairs(Workspace:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Model") or child:IsA("BasePart") then
                if child ~= directChar then
                    local okSelf, aliveSelf = isCandidateModelForPlayer(child, player)
                    if okSelf and aliveSelf then
                        return child
                    end
                    if (child:IsA("Folder") or child:IsA("Model")) and #child:GetChildren() <= 200 then
                        local nested = scanContainerForPlayer(child, player)
                        if nested then
                            return nested
                        end
                    end
                end
            end
        end
    end

    if directChar and directChar.Parent and directChar:IsDescendantOf(Workspace) then
        return directChar
    end

    return nil
end

local function cacheCharacterParts(entry, character)
    local rigParts = {}
    local seenRigParts = {}
    local bones = {}
    local allBodyParts = {}
    local targetCandidates = {}

    local primaryProp = character:IsA("Model") and character.PrimaryPart or nil
    local rootAnchor = character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("RootPart")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("UpperTorso")
        or primaryProp
        or (character:IsA("BasePart") and character or nil)
    local anchorPos = (rootAnchor and rootAnchor:IsA("BasePart") and isFiniteVector3(rootAnchor.Position)) and rootAnchor.Position or nil

    local function isNearAnchor(desc)
        local pos = desc.Position
        if not isFiniteVector3(pos) then
            return false
        end
        if not anchorPos then
            return true
        end
        return (pos - anchorPos).Magnitude <= 32
    end

    local largestTorso = nil
    local largestVol = 0
    local highestPart = nil
    local highestY = -math.huge
    local lowestPart = nil
    local lowestY = math.huge

    local function processPart(desc)
        if not desc:IsA("BasePart") then
            return
        end
        if desc:FindFirstAncestorOfClass("Tool") then
            return
        end
        if not isFiniteVector3(desc.Position) then
            return
        end

        table.insert(allBodyParts, desc)
        local n = desc.Name
        local nl = string.lower(n)
        local nearRoot = isNearAnchor(desc)

        if n == "Head" then
            targetCandidates.Head = desc
        elseif nearRoot and not targetCandidates.Head and (nl == "fakehead" or nl == "headhitbox" or nl == "skull" or nl == "face" or nl == "visor" or nl == "helmet" or nl == "cockpit" or string.find(nl, "head", 1, true)) then
            targetCandidates.Head = desc
        end

        if n == "UpperTorso" then
            targetCandidates.UpperTorso = desc
        elseif n == "Torso" or n == "Chest" then
            targetCandidates.Torso = desc
        elseif nearRoot and not targetCandidates.Torso and (nl == "lowertorso" or nl == "body" or nl == "upperbody" or nl == "core" or nl == "spine" or nl == "pelvis" or nl == "hull" or nl == "chassis" or nl == "main" or nl == "cab" or string.find(nl, "torso", 1, true) or string.find(nl, "chest", 1, true)) then
            targetCandidates.Torso = desc
        end

        if n == "HumanoidRootPart" or n == "RootPart" then
            targetCandidates.HumanoidRootPart = desc
        elseif nearRoot and not targetCandidates.HumanoidRootPart and (nl == "root" or nl == "center" or nl == "primary" or nl == "hitbox" or nl == "base") then
            targetCandidates.HumanoidRootPart = desc
        end

        if n == "LeftFoot" or n == "RightFoot" or n == "Left Leg" or n == "Right Leg" then
            targetCandidates.Foot = targetCandidates.Foot or desc
        elseif nearRoot and not targetCandidates.Foot and (string.find(nl, "foot", 1, true) or string.find(nl, "leg", 1, true) or string.find(nl, "wheel", 1, true) or string.find(nl, "hoof", 1, true)) then
            targetCandidates.Foot = desc
        end

        local inAccessory = desc:FindFirstAncestorOfClass("Accessory") ~= nil
        local isVisibleBodyPart = (desc.Transparency < 1) and (not inAccessory)
        if nearRoot and (RIG_PART_NAMES[n] or isVisibleBodyPart) then
            if not seenRigParts[desc] then
                seenRigParts[desc] = true
                table.insert(rigParts, desc)
            end
        end

        if nearRoot and isVisibleBodyPart then
            local s = desc.Size
            local vol = s.X * s.Y * s.Z
            if vol > largestVol then
                largestVol = vol
                largestTorso = desc
            end
            local py = desc.Position.Y
            if py > highestY then
                highestY = py
                highestPart = desc
            end
            if py < lowestY then
                lowestY = py
                lowestPart = desc
            end
        end
    end

    if character:IsA("BasePart") then
        processPart(character)
    end
    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("BasePart") then
            processPart(desc)
        elseif desc:IsA("Bone") then
            table.insert(bones, desc)
        end
    end

    -- Support custom morphs whose visible geometry lives inside Accessories or uses non-standard transparent root shells
    if #rigParts == 0 or (#rigParts == 1 and rigParts[1] == targetCandidates.HumanoidRootPart and #allBodyParts > 1) then
        for _, desc in ipairs(allBodyParts) do
            if desc.Transparency < 1 and not seenRigParts[desc] and isNearAnchor(desc) then
                seenRigParts[desc] = true
                table.insert(rigParts, desc)
                local s = desc.Size
                local vol = s.X * s.Y * s.Z
                if vol > largestVol then
                    largestVol = vol
                    largestTorso = desc
                end
                local py = desc.Position.Y
                if py > highestY then
                    highestY = py
                    highestPart = desc
                end
                if py < lowestY then
                    lowestY = py
                    lowestPart = desc
                end
            end
        end
    end

    if #rigParts == 0 then
        for _, desc in ipairs(allBodyParts) do
            if not seenRigParts[desc] and isNearAnchor(desc) then
                seenRigParts[desc] = true
                table.insert(rigParts, desc)
            end
        end
    end

    if #rigParts == 0 and #allBodyParts > 0 then
        table.insert(rigParts, allBodyParts[1])
    end

    if #rigParts == 0 and character:IsA("BasePart") then
        table.insert(rigParts, character)
    end

    entry.RigParts = rigParts
    entry.Bones = bones
    entry.TargetCandidates = targetCandidates
    entry.Humanoid = character:FindFirstChildOfClass("Humanoid")
    entry.Torso = targetCandidates.UpperTorso or targetCandidates.Torso or largestTorso or targetCandidates.HumanoidRootPart or primaryProp or rigParts[1]
    entry.Head = targetCandidates.Head or highestPart or entry.Torso
    if not targetCandidates.Foot then
        targetCandidates.Foot = lowestPart
    end
    entry.RootPart = targetCandidates.HumanoidRootPart
        or primaryProp
        or entry.Torso
        or entry.Head
        or rigParts[1]
        or (character:IsA("BasePart") and character or character:FindFirstChildWhichIsA("BasePart", true))
    entry.LastScanTime = os.clock()
end

-- Deep arbitrary-depth Workspace descendant scan used only for players whose Character isn't bound yet
local function deepWorkspaceScanForMissingPlayers(missingPlayers)
    local foundMap = {}
    if not missingPlayers or #missingPlayers == 0 or not Config.Resolver.CustomContainerScan then
        return foundMap
    end

    local remaining = {}
    local remainingCount = 0
    for _, plr in ipairs(missingPlayers) do
        if plr and plr ~= LocalPlayer and plr.Parent == Players then
            remaining[plr] = true
            remainingCount = remainingCount + 1
        end
    end
    if remainingCount == 0 then
        return foundMap
    end

    for _, desc in ipairs(Workspace:GetDescendants()) do
        if (desc:IsA("Model") or desc:IsA("BasePart")) and desc ~= State.LocalCharacter then
            for plr in pairs(remaining) do
                local ok, alive = isCandidateModelForPlayer(desc, plr)
                if ok then
                    if alive or not foundMap[plr] then
                        foundMap[plr] = desc
                    end
                    if alive then
                        remaining[plr] = nil
                        remainingCount = remainingCount - 1
                        break
                    end
                end
            end
            if remainingCount == 0 then
                break
            end
        end
    end

    return foundMap
end

local function destroyHighlight(entry)
    if entry.Highlight then
        pcall(function()
            entry.Highlight:Destroy()
        end)
        entry.Highlight = nil
    end
end

local function getEntryDisplayName(entry, targetKey)
    if entry and entry.IsBot then
        return entry.DisplayName or ((typeof(targetKey) == "Instance" and targetKey.Name) or "Bot")
    end
    if entry and entry.Player then
        return entry.Player.DisplayName or entry.Player.Name
    end
    return "Target"
end

local function attachRemoteHumanoidDeath(entry)
    local hum = entry.Humanoid
    if not hum or not hum.Parent or entry.DiedHookedHumanoid == hum then
        return
    end
    entry.DiedHookedHumanoid = hum
    table.insert(entry.CharConns, hum.Died:Connect(function()
        local key = entry.Key or entry.Player
        if State.CurrentAimTarget == key then
            State.CurrentAimTarget = nil
        end
        destroyHighlight(entry)
        if entry.Visuals then
            entry.Visuals:HideAll()
        end
        if not State.Unloaded then
            ScheduleReload("RemoteDied:" .. getEntryDisplayName(entry, key), false)
        end
    end))
end

local function clearCharacterFromEntry(entry)
    entry.Character = nil
    entry.Humanoid = nil
    entry.DiedHookedHumanoid = nil
    entry.RootPart = nil
    entry.Head = nil
    entry.Torso = nil
    entry.LastTrackedPart = nil
    entry.LastTrackedPos = nil
    entry.LastKnownWorldPos = nil
    entry.EstimatedVel = Vector3.zero
    entry.FrameVisualCache = nil
    clearTable(entry.RigParts)
    clearTable(entry.Bones)
    clearTable(entry.TargetCandidates)

    for _, c in ipairs(entry.CharConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearTable(entry.CharConns)

    destroyHighlight(entry)
    if entry.Visuals then
        entry.Visuals:HideAll()
    end
end

local function bindCharacterToEntry(entry, character)
    clearCharacterFromEntry(entry)
    if not character or State.Unloaded then
        return
    end

    entry.Character = character
    cacheCharacterParts(entry, character)
    attachRemoteHumanoidDeath(entry)
    if entry.RootPart and entry.RootPart.Parent then
        entry.LastKnownWorldPos = entry.RootPart.Position
    end

    local function onDescendantChanged(desc)
        if entry.Character == character and character.Parent and not State.Unloaded then
            if desc:IsA("BasePart") or desc:IsA("Humanoid") or desc:IsA("Bone") then
                entry.NeedsRescan = true
            end
        end
    end

    table.insert(entry.CharConns, character.DescendantAdded:Connect(onDescendantChanged))
    table.insert(entry.CharConns, character.DescendantRemoving:Connect(onDescendantChanged))
    table.insert(entry.CharConns, character.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            local key = entry.Key or entry.Player
            clearCharacterFromEntry(entry)
            if not State.Unloaded then
                ScheduleReload("RemoteCharRemoved:" .. getEntryDisplayName(entry, key), false)
            end
        end
    end))
end

local function destroyPlayerEntry(targetKey)
    local entry = Registry[targetKey]
    if not entry then
        return
    end

    if State.CurrentAimTarget == targetKey then
        State.CurrentAimTarget = nil
    end

    clearCharacterFromEntry(entry)

    for _, c in ipairs(entry.PlayerConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearTable(entry.PlayerConns)

    if entry.Visuals then
        entry.Visuals:Destroy()
        entry.Visuals = nil
    end
    Registry[targetKey] = nil
end

local function registerPlayerEntry(player)
    if player == LocalPlayer or Registry[player] or State.Unloaded then
        return
    end

    local bundle = createRegistryVisualBundle()
    local entry = {
        Key = player,
        Player = player,
        IsBot = false,
        DisplayName = player.DisplayName or player.Name,
        Character = nil,
        Humanoid = nil,
        DiedHookedHumanoid = nil,
        RootPart = nil,
        Head = nil,
        Torso = nil,
        RigParts = {},
        Bones = {},
        TargetCandidates = {},
        BoxLines = bundle.BoxLines,
        TracerLine = bundle.TracerLine,
        HealthBg = bundle.HealthBg,
        HealthFill = bundle.HealthFill,
        Highlight = nil,
        AlertArrow = bundle.AlertArrow,
        Visuals = bundle,
        NeedsRescan = false,
        LastScanTime = 0,
        LastDeepScan = 0,
        LastTrackedPart = nil,
        LastTrackedPos = nil,
        LastKnownWorldPos = nil,
        EstimatedVel = Vector3.zero,
        FrameVisualCache = nil,
        FrameVisualId = -1,
        PlayerConns = {},
        CharConns = {},
    }

    Registry[player] = entry

    table.insert(entry.PlayerConns, player.CharacterAdded:Connect(function(char)
        if not State.Unloaded then
            bindCharacterToEntry(entry, char)
            ScheduleReload("RemoteCharacterAdded:" .. player.Name, false)
        end
    end))

    table.insert(entry.PlayerConns, player.CharacterRemoving:Connect(function()
        clearCharacterFromEntry(entry)
        if not State.Unloaded then
            ScheduleReload("RemoteCharacterRemoving:" .. player.Name, false)
        end
    end))

    local initialChar = resolveCharacterForPlayer(player, true)
    if initialChar then
        bindCharacterToEntry(entry, initialChar)
    end
end

local BOT_CONTAINER_NAMES = {
    "Bots", "NPCs", "NPC", "Enemies", "Zombies", "Mobs", "Dummies",
    "Targets", "Units", "Living", "Entities", "Monsters", "AI",
}

local function isModelBotAlive(model)
    if not model or not model.Parent or not model:IsDescendantOf(Workspace) then
        return false
    end
    if not hasInstanceParts(model) then
        return false
    end
    if model:GetAttribute("Alive") == false then
        return false
    end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if hum then
        if hum.MaxHealth > 0 and hum.Health <= 0 then
            local customAlive = (model:GetAttribute("Alive") == true) or (type(model:GetAttribute("Health")) == "number" and model:GetAttribute("Health") > 0)
            return customAlive
        end
        return true
    end
    local hpVal = model:FindFirstChild("Health") or model:FindFirstChild("HP")
    if hpVal and (hpVal:IsA("NumberValue") or hpVal:IsA("IntValue")) and hpVal.Value <= 0 then
        return false
    end
    local hpAttr = model:GetAttribute("Health") or model:GetAttribute("HP")
    if type(hpAttr) == "number" and hpAttr <= 0 then
        return false
    end
    return true
end

local function registerBotEntry(botModel)
    if not botModel or Registry[botModel] or State.Unloaded then
        return
    end
    local bundle = createRegistryVisualBundle()
    local entry = {
        Key = botModel,
        Player = nil,
        IsBot = true,
        DisplayName = "[BOT] " .. botModel.Name,
        Character = nil,
        Humanoid = nil,
        DiedHookedHumanoid = nil,
        RootPart = nil,
        Head = nil,
        Torso = nil,
        RigParts = {},
        Bones = {},
        TargetCandidates = {},
        BoxLines = bundle.BoxLines,
        TracerLine = bundle.TracerLine,
        HealthBg = bundle.HealthBg,
        HealthFill = bundle.HealthFill,
        Highlight = nil,
        AlertArrow = bundle.AlertArrow,
        Visuals = bundle,
        NeedsRescan = false,
        LastScanTime = 0,
        LastDeepScan = 0,
        LastTrackedPart = nil,
        LastTrackedPos = nil,
        LastKnownWorldPos = nil,
        EstimatedVel = Vector3.zero,
        FrameVisualCache = nil,
        FrameVisualId = -1,
        PlayerConns = {},
        CharConns = {},
    }
    Registry[botModel] = entry
    bindCharacterToEntry(entry, botModel)
end

local MAX_TRACKED_BOTS = 36

local function syncWorkspaceBots(playerCharSet)
    if State.Unloaded then
        return
    end
    if Config.Aimbot.IgnoreBots and Config.TriggerBot.IgnoreBots and Config.ESP.IgnoreBots then
        local toDrop = {}
        for key, entry in pairs(Registry) do
            if entry.IsBot then
                table.insert(toDrop, key)
            end
        end
        for _, key in ipairs(toDrop) do
            destroyPlayerEntry(key)
        end
        return
    end

    local charLookup = playerCharSet or {}
    if not playerCharSet then
        if State.LocalCharacter then
            charLookup[State.LocalCharacter] = true
        end
        if LocalPlayer.Character then
            charLookup[LocalPlayer.Character] = true
        end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Character then
                charLookup[plr.Character] = true
            end
            local existing = Registry[plr]
            if existing and existing.Character then
                charLookup[existing.Character] = true
            end
        end
    end

    local cam = State.Camera or Workspace.CurrentCamera
    local camPos = cam and cam.CFrame.Position or nil
    local candidates = {}
    local candidateSeen = {}

    local function considerModel(model)
        if not model or candidateSeen[model] or charLookup[model] then
            return
        end
        if not (model:IsA("Model") or model:IsA("BasePart")) then
            return
        end
        if model == Workspace.Terrain or model == cam then
            return
        end
        if Players:GetPlayerFromCharacter(model) ~= nil then
            return
        end
        local hasHum = model:FindFirstChildOfClass("Humanoid") ~= nil
        local hasBotTag = (model:GetAttribute("IsBot") == true) or (model:GetAttribute("IsNPC") == true) or (model:GetAttribute("Enemy") == true)
        if not hasHum and not hasBotTag then
            return
        end
        if not isModelBotAlive(model) then
            return
        end
        candidateSeen[model] = true
        local root = model:FindFirstChild("HumanoidRootPart") or (model:IsA("Model") and model.PrimaryPart) or model:FindFirstChildWhichIsA("BasePart")
        local dist = (camPos and root and isFiniteVector3(root.Position)) and (root.Position - camPos).Magnitude or 999
        table.insert(candidates, { Model = model, Dist = dist })
    end

    for _, folderName in ipairs(BOT_CONTAINER_NAMES) do
        local folder = Workspace:FindFirstChild(folderName)
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                considerModel(child)
            end
        end
    end

    for _, child in ipairs(Workspace:GetChildren()) do
        if child:IsA("Model") then
            considerModel(child)
        end
    end

    if #candidates > MAX_TRACKED_BOTS then
        table.sort(candidates, function(a, b)
            return a.Dist < b.Dist
        end)
    end

    local activeBotSet = {}
    local limit = math.min(#candidates, MAX_TRACKED_BOTS)
    for i = 1, limit do
        local model = candidates[i].Model
        activeBotSet[model] = true
        local entry = Registry[model]
        if not entry then
            registerBotEntry(model)
        else
            if not entry.Visuals or not entry.Visuals:IsGuiAlive() then
                if entry.Visuals then
                    entry.Visuals:Destroy()
                end
                local rebuilt = createRegistryVisualBundle()
                entry.Visuals = rebuilt
                entry.BoxLines = rebuilt.BoxLines
                entry.TracerLine = rebuilt.TracerLine
                entry.HealthBg = rebuilt.HealthBg
                entry.HealthFill = rebuilt.HealthFill
                entry.AlertArrow = rebuilt.AlertArrow
            end
            if entry.Character ~= model then
                bindCharacterToEntry(entry, model)
            elseif entry.NeedsRescan then
                entry.NeedsRescan = false
                cacheCharacterParts(entry, model)
                attachRemoteHumanoidDeath(entry)
            end
        end
    end

    local staleBots = {}
    for key, entry in pairs(Registry) do
        if entry.IsBot and not activeBotSet[key] then
            table.insert(staleBots, key)
        end
    end
    for _, key in ipairs(staleBots) do
        destroyPlayerEntry(key)
    end
end

local releaseTriggerFire = function() end

local function clearLocalCharacterState()
    State.LocalCharacter = nil
    State.LocalHumanoid = nil
    State.LocalRootPart = nil
    State.LocalAlive = false
    State.LastLocalPos = nil
    State.CurrentAimTarget = nil
    State.CurrentAimPart = nil
    State.CurrentAimPredictedPos = nil
    State.TriggerTarget = nil
    State.TriggerAcquireTime = 0
    State.TriggerToolRef = nil
    releaseTriggerFire()

    for _, c in ipairs(State.LocalConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearTable(State.LocalConns)
end

local function bindLocalCharacter(character)
    clearLocalCharacterState()
    if not character or State.Unloaded then
        return
    end

    State.LocalCharacter = character
    State.Camera = Workspace.CurrentCamera
    State.LocalHumanoid = character:FindFirstChildOfClass("Humanoid")
    State.LocalRootPart = character:FindFirstChild("HumanoidRootPart")
        or character.PrimaryPart
        or (character:IsA("BasePart") and character or character:FindFirstChildWhichIsA("BasePart", true))
    State.LocalAlive = true
    if State.LocalRootPart and State.LocalRootPart.Parent then
        State.LastLocalPos = State.LocalRootPart.Position
    end

    local function attachHumanoidDeath(hum)
        State.LocalHumanoid = hum
        State.LocalAlive = (hum.MaxHealth <= 0) or (hum.Health > 0)
        table.insert(State.LocalConns, hum.Died:Connect(function()
            State.LocalAlive = false
            State.CurrentAimTarget = nil
            releaseTriggerFire()
            ScheduleReload("LocalPlayerDied", false)
        end))
    end

    if State.LocalHumanoid then
        attachHumanoidDeath(State.LocalHumanoid)
    else
        table.insert(State.LocalConns, character.ChildAdded:Connect(function(child)
            if State.Unloaded then return end
            if child:IsA("Humanoid") then
                attachHumanoidDeath(child)
                ScheduleReload("LocalHumanoidReady", false)
            elseif child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
                State.LocalRootPart = child
            elseif (not State.LocalRootPart or not State.LocalRootPart.Parent) and child:IsA("BasePart") then
                State.LocalRootPart = child
            end
        end))
    end

    table.insert(State.LocalConns, character.AncestryChanged:Connect(function(_, newParent)
        if not newParent and not State.Unloaded then
            clearLocalCharacterState()
            ScheduleReload("LocalCharacterRemoved", false)
        end
    end))
end

-- Full Reload & 1s Reconciliation: refreshes characters, parts, team detection, and healed visuals
ReloadAllSystems = function(reason, hardReset)
    if State.Unloaded then
        return
    end

    State.ReloadCount = State.ReloadCount + 1
    State.LastReloadReason = reason or "Event"
    State.Camera = Workspace.CurrentCamera
    State.LastTeamScan = -1

    if not OverlayGui.Parent then
        OverlayGui.Parent = getSafeGuiParent()
    end
    OverlayGui.Enabled = true
    if not HighlightContainer.Parent then
        local okHL = pcall(function()
            HighlightContainer.Parent = getHighlightParent()
        end)
        if not okHL or not HighlightContainer.Parent then
            HighlightContainer.Parent = OverlayGui
        end
    end

    if hardReset then
        State.CurrentAimTarget = nil
        local existing = {}
        for player in pairs(Registry) do
            table.insert(existing, player)
        end
        for _, player in ipairs(existing) do
            destroyPlayerEntry(player)
        end
        clearTable(Registry)

        for _, hl in ipairs(HighlightContainer:GetChildren()) do
            pcall(function()
                hl:Destroy()
            end)
        end
    end

    -- Re-bind LocalPlayer character & humanoid
    local liveLocalChar = LocalPlayer.Character
    if liveLocalChar and liveLocalChar.Parent then
        if State.LocalCharacter ~= liveLocalChar then
            bindLocalCharacter(liveLocalChar)
        else
            State.LocalHumanoid = liveLocalChar:FindFirstChildOfClass("Humanoid") or State.LocalHumanoid
            State.LocalRootPart = liveLocalChar:FindFirstChild("HumanoidRootPart")
                or liveLocalChar.PrimaryPart
                or State.LocalRootPart
                or (liveLocalChar:IsA("BasePart") and liveLocalChar or liveLocalChar:FindFirstChildWhichIsA("BasePart", true))
            if State.LocalHumanoid then
                State.LocalAlive = (State.LocalHumanoid.MaxHealth <= 0) or (State.LocalHumanoid.Health > 0)
            else
                State.LocalAlive = (State.LocalRootPart ~= nil and State.LocalRootPart.Parent ~= nil)
            end
        end
    end

    -- Reconcile every active player in Players:GetPlayers()
    local seen = {}
    local missingPlayers = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            seen[player] = true
            local entry = Registry[player]
            if not entry then
                registerPlayerEntry(player)
                entry = Registry[player]
            end
            if entry then
                if not entry.Visuals or not entry.Visuals:IsGuiAlive() then
                    if entry.Visuals then
                        entry.Visuals:Destroy()
                    end
                    local rebuilt = createRegistryVisualBundle()
                    entry.Visuals = rebuilt
                    entry.BoxLines = rebuilt.BoxLines
                    entry.TracerLine = rebuilt.TracerLine
                    entry.HealthBg = rebuilt.HealthBg
                    entry.HealthFill = rebuilt.HealthFill
                    entry.AlertArrow = rebuilt.AlertArrow
                end

                local liveChar = resolveCharacterForPlayer(player, true)
                if liveChar and liveChar.Parent then
                    if entry.Character ~= liveChar then
                        bindCharacterToEntry(entry, liveChar)
                    else
                        cacheCharacterParts(entry, liveChar)
                        attachRemoteHumanoidDeath(entry)
                    end
                else
                    if entry.Character ~= nil then
                        clearCharacterFromEntry(entry)
                    end
                    table.insert(missingPlayers, player)
                end
            end
        end
    end

    if #missingPlayers > 0 then
        local recovered = deepWorkspaceScanForMissingPlayers(missingPlayers)
        for player, liveChar in pairs(recovered) do
            local entry = Registry[player]
            if entry and liveChar and liveChar.Parent then
                bindCharacterToEntry(entry, liveChar)
            end
        end
    end

    -- Clean up any player who left (preserve bot entries until syncWorkspaceBots reconciles them)
    local toRemove = {}
    local playerCharSet = {}
    if State.LocalCharacter then
        playerCharSet[State.LocalCharacter] = true
    end
    if LocalPlayer.Character then
        playerCharSet[LocalPlayer.Character] = true
    end
    for key, entry in pairs(Registry) do
        if entry.IsBot then
            if entry.Character then
                playerCharSet[entry.Character] = false
            end
        else
            if not seen[key] then
                table.insert(toRemove, key)
            elseif entry.Character then
                playerCharSet[entry.Character] = true
            end
        end
    end
    for _, key in ipairs(toRemove) do
        destroyPlayerEntry(key)
    end

    syncWorkspaceBots(playerCharSet)
end

ScheduleReload = function(reason, hardReset)
    if State.Unloaded then
        return
    end
    State.ReloadToken = State.ReloadToken + 1
    local myToken = State.ReloadToken
    State.LastReloadReason = reason or "Event"

    task.delay(0.06, function()
        if not State.Unloaded and State.ReloadToken == myToken then
            ReloadAllSystems(reason, hardReset == true)
        end
    end)
end

addConnection(Players.PlayerAdded:Connect(function(player)
    if not State.Unloaded then
        registerPlayerEntry(player)
        ScheduleReload("PlayerAdded:" .. player.Name, false)
    end
end))

addConnection(Players.PlayerRemoving:Connect(function(player)
    destroyPlayerEntry(player)
    if not State.Unloaded then
        ScheduleReload("PlayerRemoving:" .. player.Name, false)
    end
end))

addConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    if not State.Unloaded then
        bindLocalCharacter(char)
        ScheduleReload("LocalPlayerRespawned", false)
    end
end))

addConnection(LocalPlayer.CharacterRemoving:Connect(function()
    clearLocalCharacterState()
    if not State.Unloaded then
        ScheduleReload("LocalCharacterRemoving", false)
    end
end))

if LocalPlayer.Character then
    bindLocalCharacter(LocalPlayer.Character)
end
ReloadAllSystems("InitialBootstrap", true)

local function runPeriodicSafetySync()
    ReloadAllSystems("Periodic1sRenderSync", false)
end

-- ============================================================================
-- [SECTION 5] FFA-SAFE TEAM RESOLVER, SHARED ELIGIBILITY & VISIBILITY PIPELINE
-- ============================================================================
local NON_COMBAT_TEAM_NAMES = {
    lobby = true,
    spectator = true,
    spectators = true,
    spectating = true,
    afk = true,
    waiting = true,
    ["waiting room"] = true,
    intermission = true,
    menu = true,
    queue = true,
    loading = true,
    spawn = true,
    dead = true,
    ghost = true,
    ffa = true,
    ["free for all"] = true,
    player = true,
    players = true,
    participant = true,
    participants = true,
    contestant = true,
    contestants = true,
    spawned = true,
    active = true,
    match = true,
    game = true,
    everyone = true,
    all = true,
    playing = true,
    alive = true,
    ingame = true,
    ["in-game"] = true,
    neutral = true,
    none = true,
    default = true,
    ["0"] = true,
    ["-1"] = true,
    ["false"] = true,
    [""] = true,
}

local function readTeamAttribute(inst)
    if not inst then
        return nil
    end
    local v = inst:GetAttribute("Team")
    if v == nil then v = inst:GetAttribute("TeamId") end
    if v == nil then v = inst:GetAttribute("TeamID") end
    if v == nil then v = inst:GetAttribute("Faction") end
    if v == nil then v = inst:GetAttribute("Squad") end
    if v == nil or typeof(v) == "boolean" then
        return nil
    end
    local key = string.lower(tostring(v))
    if NON_COMBAT_TEAM_NAMES[key] then
        return nil
    end
    return v
end

local function isCombatTeam(teamObj)
    if not teamObj then
        return false
    end
    local lowerName = string.lower(teamObj.Name)
    return not NON_COMBAT_TEAM_NAMES[lowerName]
end

local function playerHasLivingWorkspaceChar(plr)
    local ch = plr and plr.Character
    if ch and ch.Parent and ch:IsDescendantOf(Workspace) then
        local hum = ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.MaxHealth > 0 and hum.Health <= 0 then
            local customAlive = (ch:GetAttribute("Alive") == true) or (type(ch:GetAttribute("Health")) == "number" and ch:GetAttribute("Health") > 0)
            if not customAlive then
                return false
            end
        elseif not hum then
            local hpVal = ch:FindFirstChild("Health") or ch:FindFirstChild("HP")
            if hpVal and (hpVal:IsA("NumberValue") or hpVal:IsA("IntValue")) and hpVal.Value <= 0 then
                return false
            end
        end
        return hasInstanceParts(ch)
    end
    local entry = Registry[plr]
    return entry ~= nil and entry.Character ~= nil and entry.Character.Parent ~= nil and entry.RootPart ~= nil
end

-- Detects whether this server actually has >= 2 distinct combat teams among active players (never hides everyone!)
local function refreshDetectedTeamScheme()
    local now = os.clock()
    if State.LastTeamScan >= 0 and (now - State.LastTeamScan) < 0.75 then
        return State.DetectedTeamScheme
    end
    State.LastTeamScan = now

    local distinctTeams = {}
    local teamCount = 0
    local distinctAttrs = {}
    local attrCount = 0

    for _, plr in ipairs(Players:GetPlayers()) do
        if playerHasLivingWorkspaceChar(plr) then
            if isCombatTeam(plr.Team) and not plr.Neutral then
                if not distinctTeams[plr.Team] then
                    distinctTeams[plr.Team] = true
                    teamCount = teamCount + 1
                end
            end
            local attr = readTeamAttribute(plr)
            if attr == nil and plr.Character then
                attr = readTeamAttribute(plr.Character)
            end
            if attr ~= nil then
                local ak = tostring(attr)
                if not distinctAttrs[ak] then
                    distinctAttrs[ak] = true
                    attrCount = attrCount + 1
                end
            end
        end
    end

    if teamCount >= 2 and isCombatTeam(LocalPlayer.Team) and not LocalPlayer.Neutral then
        State.DetectedTeamScheme = "Team"
    elseif attrCount >= 2 then
        State.DetectedTeamScheme = "Attribute"
    else
        State.DetectedTeamScheme = "FFA"
    end

    return State.DetectedTeamScheme
end

local function rawSchemeTeammateCheck(scheme, player, entry)
    if scheme == "Team" then
        if isCombatTeam(LocalPlayer.Team) and isCombatTeam(player.Team) and not LocalPlayer.Neutral and not player.Neutral then
            return LocalPlayer.Team == player.Team
        end
        return false
    elseif scheme == "Attribute" then
        local lAttr = readTeamAttribute(LocalPlayer) or readTeamAttribute(State.LocalCharacter or LocalPlayer.Character)
        local tAttr = readTeamAttribute(player) or readTeamAttribute((entry and entry.Character) or player.Character)
        if lAttr ~= nil and tAttr ~= nil then
            return lAttr == tAttr
        end
        return false
    end
    return false
end

local function isTeammate(player, entry)
    if player == LocalPlayer then
        return true
    end
    if entry and entry.IsBot then
        local botTeamAttr = readTeamAttribute(entry.Character)
        local myTeamAttr = readTeamAttribute(LocalPlayer) or readTeamAttribute(State.LocalCharacter or LocalPlayer.Character)
        if botTeamAttr ~= nil and myTeamAttr ~= nil then
            return botTeamAttr == myTeamAttr
        end
        return false
    end

    local mode = Config.Resolver.TeamCheckMode
    if mode == "Off" then
        return false
    end

    if mode == "Team Property" then
        if LocalPlayer.Team ~= nil and player.Team ~= nil and not LocalPlayer.Neutral and not player.Neutral then
            return LocalPlayer.Team == player.Team
        end
        return false
    end

    if mode == "TeamColor" then
        if not LocalPlayer.Neutral and not player.Neutral then
            return LocalPlayer.TeamColor == player.TeamColor
        end
        return false
    end

    -- "Auto" FFA-aware mode with Zero-Enemy safety invariant
    local scheme = refreshDetectedTeamScheme()
    if scheme == "FFA" then
        return false
    end

    local matched = rawSchemeTeammateCheck(scheme, player, entry)
    if not matched then
        return false
    end

    -- Safety invariant: if this scheme would hide 100% of living opponents in Workspace, it's an FFA lobby -> render all!
    local hasAnyLivingEnemy = false
    for otherKey, otherEntry in pairs(Registry) do
        if (not otherEntry.IsBot) and otherKey ~= LocalPlayer and otherEntry.Character and otherEntry.Character.Parent and otherEntry.RootPart then
            if not rawSchemeTeammateCheck(scheme, otherKey, otherEntry) then
                hasAnyLivingEnemy = true
                break
            end
        end
    end

    if not hasAnyLivingEnemy then
        State.DetectedTeamScheme = "FFA"
        return false
    end

    return true
end

local function getCharacterHealth(entry)
    local hum = entry.Humanoid
    if hum and hum.Parent then
        local maxHp = hum.MaxHealth > 0 and hum.MaxHealth or 100
        local hp = math.clamp(hum.Health, 0, maxHp)
        return hp, maxHp, math.clamp(hp / maxHp, 0, 1)
    end

    local char = entry.Character
    if char then
        local hpVal = char:FindFirstChild("Health") or char:FindFirstChild("HP")
        local maxVal = char:FindFirstChild("MaxHealth") or char:FindFirstChild("MaxHP")
        if hpVal and (hpVal:IsA("NumberValue") or hpVal:IsA("IntValue")) then
            local maxHp = (maxVal and (maxVal:IsA("NumberValue") or maxVal:IsA("IntValue")) and maxVal.Value > 0) and maxVal.Value or 100
            local hp = math.clamp(hpVal.Value, 0, maxHp)
            return hp, maxHp, math.clamp(hp / maxHp, 0, 1)
        end

        local attrHp = char:GetAttribute("Health")
        if attrHp == nil then attrHp = char:GetAttribute("HP") end
        local attrMax = char:GetAttribute("MaxHealth")
        if attrMax == nil then attrMax = char:GetAttribute("MaxHP") end
        if type(attrHp) == "number" then
            local maxHp = (type(attrMax) == "number" and attrMax > 0) and attrMax or 100
            local hp = math.clamp(attrHp, 0, maxHp)
            return hp, maxHp, math.clamp(hp / maxHp, 0, 1)
        end
    end

    return 100, 100, 1
end

local function isEntryAlive(entry)
    if not entry then
        return false
    end
    local char = entry.Character
    if not char or not char.Parent then
        return false
    end

    local hum = entry.Humanoid
    if hum and hum.Parent then
        if hum.MaxHealth > 0 and hum.Health <= 0 then
            local customAlive = (char:GetAttribute("Alive") == true) or (type(char:GetAttribute("Health")) == "number" and char:GetAttribute("Health") > 0)
            if not customAlive then
                return false
            end
        end
    else
        if char:GetAttribute("Alive") == false or (entry.Player and entry.Player:GetAttribute("Alive") == false) then
            return false
        end
        local hpVal = char:FindFirstChild("Health") or char:FindFirstChild("HP")
        if hpVal and (hpVal:IsA("NumberValue") or hpVal:IsA("IntValue")) and hpVal.Value <= 0 then
            return false
        end
        local hp = char:GetAttribute("Health") or char:GetAttribute("HP")
        if type(hp) == "number" and hp <= 0 then
            return false
        end
    end

    return entry.RootPart ~= nil and entry.RootPart.Parent ~= nil and isFiniteVector3(entry.RootPart.Position)
end

local function getBodyAnchorPart(entry, desired)
    local cands = entry.TargetCandidates
    if desired == "Head" then
        return (entry.Head and entry.Head.Parent and entry.Head)
            or (entry.Torso and entry.Torso.Parent and entry.Torso)
            or entry.RootPart
    elseif desired == "Chest" then
        return (entry.Torso and entry.Torso.Parent and entry.Torso)
            or (cands.HumanoidRootPart and cands.HumanoidRootPart.Parent and cands.HumanoidRootPart)
            or entry.Head
            or entry.RootPart
    elseif desired == "Feet" then
        return (cands.Foot and cands.Foot.Parent and cands.Foot) or entry.RootPart
    else
        return (cands.HumanoidRootPart and cands.HumanoidRootPart.Parent and cands.HumanoidRootPart)
            or entry.Torso
            or entry.RootPart
    end
end

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function raycastPartVisible(camera, targetCharacter, targetPart)
    if not camera or not targetCharacter or not targetPart or not targetPart.Parent then
        return false
    end

    local origin = camera.CFrame.Position
    local targetPos = targetPart.Position
    local delta = targetPos - origin
    local totalDist = delta.Magnitude
    if totalDist < 0.01 then
        return true
    end

    local filterList = {OverlayGui, HighlightContainer, camera}
    local localChar = State.LocalCharacter or LocalPlayer.Character
    if localChar then
        table.insert(filterList, localChar)
    end

    RayParams.IgnoreWater = Config.ESP.IgnoreGlassWater
    local currentOrigin = origin
    local dirUnit = delta.Unit

    for _ = 1, 6 do
        local remaining = (targetPos - currentOrigin).Magnitude
        if remaining < 0.05 then
            return true
        end

        RayParams.FilterDescendantsInstances = filterList
        local result = Workspace:Raycast(currentOrigin, dirUnit * remaining, RayParams)
        if not result or not result.Instance then
            return true
        end

        local hitPart = result.Instance
        if hitPart:IsDescendantOf(targetCharacter) then
            return true
        end

        local parentName = hitPart.Parent and string.lower(hitPart.Parent.Name) or ""
        local isVfxOrDebris = string.find(parentName, "bullet", 1, true) ~= nil
            or string.find(parentName, "effect", 1, true) ~= nil
            or string.find(parentName, "debris", 1, true) ~= nil
            or string.find(parentName, "vfx", 1, true) ~= nil
            or string.find(parentName, "tracer", 1, true) ~= nil
            or string.find(parentName, "projectile", 1, true) ~= nil
        local isAccessory = hitPart:FindFirstAncestorOfClass("Accessory") ~= nil
        local isNonBlockingGlass = Config.ESP.IgnoreGlassWater
            and (hitPart.Transparency >= 0.45 or hitPart.Material == Enum.Material.Glass)

        if (not hitPart.CanCollide) or isAccessory or isVfxOrDebris or isNonBlockingGlass or hitPart.Transparency >= 0.92 then
            table.insert(filterList, hitPart)
            currentOrigin = result.Position + dirUnit * 0.05
        else
            return false
        end
    end

    return false
end

local function GetTargetVisualState(player, targetPart)
    local entry = Registry[player]
    if not entry then
        return { isVisible = false, activeColor = Config.Colors.Hidden }
    end

    if targetPart == nil and entry.FrameVisualId == State.FrameIndex and entry.FrameVisualCache then
        return entry.FrameVisualCache
    end

    local camera = State.Camera or Workspace.CurrentCamera
    local isVis = false
    if camera and entry.Character then
        if targetPart and targetPart.Parent then
            isVis = raycastPartVisible(camera, entry.Character, targetPart)
        else
            local headPart = entry.Head
            local chestPart = entry.Torso
            if headPart and headPart.Parent and raycastPartVisible(camera, entry.Character, headPart) then
                isVis = true
            elseif chestPart and chestPart.Parent and chestPart ~= headPart and raycastPartVisible(camera, entry.Character, chestPart) then
                isVis = true
            elseif entry.RootPart and entry.RootPart.Parent and entry.RootPart ~= headPart and entry.RootPart ~= chestPart then
                isVis = raycastPartVisible(camera, entry.Character, entry.RootPart)
            end
        end
    end

    local result = {
        isVisible = isVis,
        activeColor = isVis and Config.Colors.Visible or Config.Colors.Hidden,
    }

    if targetPart == nil then
        entry.FrameVisualId = State.FrameIndex
        entry.FrameVisualCache = result
    end

    return result
end

local function IsValidTarget(targetKey, opts)
    if not targetKey or targetKey == LocalPlayer then
        return false, nil, nil, math.huge
    end

    local entry = Registry[targetKey]
    if not isEntryAlive(entry) then
        return false, entry, nil, math.huge
    end

    if opts and opts.ignoreBots == true and entry.IsBot then
        return false, entry, nil, math.huge
    end

    local checkTeam = (opts and opts.checkTeam ~= nil) and opts.checkTeam or Config.ESP.TeamCheck
    if checkTeam and isTeammate(targetKey, entry) then
        return false, entry, nil, math.huge
    end

    local camera = (opts and opts.camera) or State.Camera or Workspace.CurrentCamera
    if not camera then
        return false, entry, nil, math.huge
    end

    local evalPart = (opts and opts.targetPart) or entry.RootPart
    if not evalPart or not evalPart.Parent or not isFiniteVector3(evalPart.Position) then
        return false, entry, nil, math.huge
    end

    local worldDist = (evalPart.Position - camera.CFrame.Position).Magnitude
    if not isFiniteNumber(worldDist) then
        return false, entry, nil, math.huge
    end
    local maxDist = (opts and opts.maxDistance) or Config.ESP.MaxDistance
    if worldDist > maxDist then
        return false, entry, nil, worldDist
    end

    local visState = GetTargetVisualState(targetKey, opts and opts.targetPart or nil)
    if opts and opts.checkVisible and not visState.isVisible then
        return false, entry, visState, worldDist
    end

    return true, entry, visState, worldDist
end

-- ============================================================================
-- [SECTION 6] REBUILT ESP RENDERER (WITH PROPORTIONAL DISTANCE BOX FALLBACK)
-- ============================================================================
local function computeScreenBox(camera, entry, rootVP, worldDist)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyInFront = false
    local rootPos = entry.RootPart and entry.RootPart.Position
    local maxSpread = math.max(24, (entry.Humanoid and entry.Humanoid.HipHeight or 2) * 8)

    local parts = entry.RigParts
    local validParts = 0
    if #parts > 0 then
        for _, part in ipairs(parts) do
            if part and part.Parent and (not rootPos or (part.Position - rootPos).Magnitude <= maxSpread) then
                validParts = validParts + 1
                local cf = part.CFrame
                local half = part.Size * 0.5
                for sx = -1, 1, 2 do
                    for sy = -1, 1, 2 do
                        for sz = -1, 1, 2 do
                            local corner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
                            local vp = camera:WorldToViewportPoint(corner)
                            if vp.Z > 0 then
                                anyInFront = true
                                if vp.X < minX then minX = vp.X end
                                if vp.Y < minY then minY = vp.Y end
                                if vp.X > maxX then maxX = vp.X end
                                if vp.Y > maxY then maxY = vp.Y end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Support skinned-mesh custom rigs deformed via Bone instances
    if entry.Bones and #entry.Bones > 0 then
        for _, bone in ipairs(entry.Bones) do
            if bone and bone.Parent then
                local okBone, bPos = pcall(function()
                    return bone.TransformedWorldCFrame.Position
                end)
                if okBone and bPos and (not rootPos or (bPos - rootPos).Magnitude <= maxSpread) then
                    local vp = camera:WorldToViewportPoint(bPos)
                    if vp.Z > 0 then
                        anyInFront = true
                        if vp.X < minX then minX = vp.X end
                        if vp.Y < minY then minY = vp.Y end
                        if vp.X > maxX then maxX = vp.X end
                        if vp.Y > maxY then maxY = vp.Y end
                    end
                end
            end
        end
    end

    if validParts == 0 and entry.Character then
        local cf, size
        if entry.Character:IsA("BasePart") then
            cf = entry.Character.CFrame
            size = entry.Character.Size
        elseif entry.Character:IsA("Model") then
            local ok, mcf, msize = pcall(function()
                return entry.Character:GetBoundingBox()
            end)
            if ok then
                cf = mcf
                size = msize
            end
        end
        if cf and size then
            local half = Vector3.new(math.min(size.X, 18), math.min(size.Y, 20), math.min(size.Z, 18)) * 0.5
            for sx = -1, 1, 2 do
                for sy = -1, 1, 2 do
                    for sz = -1, 1, 2 do
                        local corner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
                        local vp = camera:WorldToViewportPoint(corner)
                        if vp.Z > 0 then
                            anyInFront = true
                            if vp.X < minX then minX = vp.X end
                            if vp.Y < minY then minY = vp.Y end
                            if vp.X > maxX then maxX = vp.X end
                            if vp.Y > maxY then maxY = vp.Y end
                        end
                    end
                end
            end
        end
    end

    if anyInFront and minX < maxX and minY < maxY then
        local pad = 3
        local vpSize = camera.ViewportSize
        local rawW = (maxX - minX) + pad * 2
        local rawH = (maxY - minY) + pad * 2
        local x1 = math.clamp(minX - pad, -40, vpSize.X + 40)
        local y1 = math.clamp(minY - pad, -40, vpSize.Y + 40)
        local x2 = math.clamp(maxX + pad, -40, vpSize.X + 40)
        local y2 = math.clamp(maxY + pad, -40, vpSize.Y + 40)
        local w = x2 - x1
        local h = y2 - y1
        if w >= 6 and h >= 10 and rawW <= vpSize.X * 1.4 and rawH <= vpSize.Y * 1.4 then
            return true, x1, y1, math.max(w, 8), math.max(h, 12)
        end
    end

    -- Fallback proportional 2D box anchored around RootPart (or Head if close) projection
    if rootVP and rootVP.Z > 0 then
        local h = math.clamp(2100 / math.max(worldDist, 4), 14, 320)
        local w = h * 0.58
        return true, rootVP.X - w * 0.5, rootVP.Y - h * 0.5, w, h
    end

    return false, 0, 0, 0, 0
end

local function getHealthColor(ratio)
    if ratio >= 0.5 then
        return Color3.fromRGB(250, 204, 21):Lerp(Color3.fromRGB(56, 232, 198), (ratio - 0.5) * 2)
    else
        return Color3.fromRGB(244, 63, 94):Lerp(Color3.fromRGB(250, 204, 21), ratio * 2)
    end
end

local MAX_ACTIVE_HIGHLIGHTS = 20

local function updateAllESP(camera, viewportSize, screenCenter)
    local highlightCandidates = {}

    for targetKey, entry in pairs(Registry) do
        if not Config.ESP.Enabled then
            entry.Visuals:HideAll()
            if entry.Highlight then entry.Highlight.Enabled = false end
        else
            local valid, _, visState, worldDist = IsValidTarget(targetKey, {
                checkTeam = Config.ESP.TeamCheck,
                checkVisible = Config.ESP.VisibleCheck,
                ignoreBots = Config.ESP.IgnoreBots,
                maxDistance = Config.ESP.MaxDistance,
                camera = camera,
            })

            if not valid or not visState then
                entry.Visuals:HideAll()
                if entry.Highlight then entry.Highlight.Enabled = false end
            else
                local rootPart = entry.RootPart
                local boxColor = Config.ESP.ColorByVisibility and visState.activeColor or Config.Colors.Box
                local tracerColor = Config.ESP.ColorByVisibility and visState.activeColor or Config.Colors.Tracer

                local rootVP, rootOnScreen = camera:WorldToViewportPoint(rootPart.Position)
                local headCheckPart = entry.Head or entry.Torso
                local headInFront = false
                if headCheckPart and headCheckPart.Parent then
                    local hvp = camera:WorldToViewportPoint(headCheckPart.Position)
                    headInFront = hvp.Z > 0
                end
                local isBehind = (rootVP.Z <= 0) and (not headInFront)
                local screenPos = Vector2.new(rootVP.X, rootVP.Y)

                local boxValid, bx, by, bw, bh = false, 0, 0, 0, 0
                if not isBehind then
                    boxValid, bx, by, bw, bh = computeScreenBox(camera, entry, rootVP, worldDist)
                end

                local _, _, hpRatio = getCharacterHealth(entry)
                local hpColor = getHealthColor(hpRatio)

                local showTracer = Config.ESP.TracerESP and (not isBehind) and rootOnScreen
                local tracerFrom = Vector2.new(viewportSize.X * 0.5, viewportSize.Y)
                local tracerTo = boxValid and Vector2.new(bx + bw * 0.5, by + bh) or screenPos

                if Config.ESP.TracerOrigin == "Top" then
                    tracerFrom = Vector2.new(viewportSize.X * 0.5, 0)
                    local headPart = getBodyAnchorPart(entry, "Head")
                    if headPart and headPart.Parent then
                        local hvp = camera:WorldToViewportPoint(headPart.Position)
                        if hvp.Z > 0 then
                            tracerTo = Vector2.new(hvp.X, hvp.Y)
                        elseif boxValid then
                            tracerTo = Vector2.new(bx + bw * 0.5, by)
                        end
                    elseif boxValid then
                        tracerTo = Vector2.new(bx + bw * 0.5, by)
                    end
                elseif Config.ESP.TracerOrigin == "Center" then
                    tracerFrom = screenCenter
                    local chestPart = getBodyAnchorPart(entry, "Chest")
                    if chestPart and chestPart.Parent then
                        local cvp = camera:WorldToViewportPoint(chestPart.Position)
                        if cvp.Z > 0 then
                            tracerTo = Vector2.new(cvp.X, cvp.Y)
                        elseif boxValid then
                            tracerTo = Vector2.new(bx + bw * 0.5, by + bh * 0.45)
                        end
                    elseif boxValid then
                        tracerTo = Vector2.new(bx + bw * 0.5, by + bh * 0.45)
                    end
                else
                    tracerFrom = Vector2.new(viewportSize.X * 0.5, viewportSize.Y)
                    if boxValid then
                        tracerTo = Vector2.new(bx + bw * 0.5, by + bh)
                    else
                        local footPart = getBodyAnchorPart(entry, "Feet")
                        if footPart and footPart.Parent then
                            local fvp = camera:WorldToViewportPoint(footPart.Position)
                            if fvp.Z > 0 then
                                tracerTo = Vector2.new(fvp.X, fvp.Y)
                            end
                        end
                    end
                end

                local showArrow = false
                local arrowPos = Vector2.zero
                local arrowAngle = 0
                local arrowColor = Config.ESP.ColorByVisibility and visState.activeColor or Config.Colors.Alert360

                if Config.ESP.Alert360 then
                    local alertAllowed = (not Config.ESP.Alert360VisibleOnly) or visState.isVisible
                    if alertAllowed then
                        local localSpace = camera.CFrame:PointToObjectSpace(rootPart.Position)
                        local screenDir = Vector2.new(localSpace.X, -localSpace.Y)
                        local distFromCenter = (screenPos - screenCenter).Magnitude
                        local outOfFOV = isBehind or (not rootOnScreen) or (distFromCenter > Config.Aimbot.FOVRadius)
                        if outOfFOV and screenDir.Magnitude > 0.001 then
                            showArrow = true
                            arrowAngle = math.atan2(screenDir.Y, screenDir.X)
                            local ringR = math.min(
                                Config.ESP.AlertRingRadius,
                                math.min(viewportSize.X, viewportSize.Y) * 0.42
                            )
                            arrowPos = screenCenter + Vector2.new(math.cos(arrowAngle), math.sin(arrowAngle)) * ringR
                        end
                    end
                end

                local feetX = boxValid and (bx + bw * 0.5) or screenPos.X
                local feetY = boxValid and (by + bh + 3) or (screenPos.Y + 12)
                local footPart = getBodyAnchorPart(entry, "Feet")
                if not boxValid and footPart and footPart.Parent then
                    local fvp = camera:WorldToViewportPoint(footPart.Position)
                    if fvp.Z > 0 then
                        feetX = fvp.X
                        feetY = fvp.Y + 6
                    end
                end

                entry.Visuals:Render({
                    ShowBox = Config.ESP.BoxESP and boxValid,
                    BoxStyle = Config.ESP.BoxStyle,
                    BoxThickness = Config.ESP.BoxThickness,
                    BoxColor = boxColor,
                    BX = bx,
                    BY = by,
                    BW = bw,
                    BH = bh,
                    ShowHealth = Config.ESP.HealthBar and boxValid,
                    ShowHealthText = Config.ESP.ShowHealthPercent,
                    HealthRatio = hpRatio,
                    HealthColor = hpColor,
                    ShowName = Config.ESP.ShowName and boxValid,
                    NameText = getEntryDisplayName(entry, targetKey),
                    ShowDist = Config.ESP.ShowDistance and (not isBehind) and (boxValid or rootOnScreen),
                    DistText = string.format("%.0fm", worldDist),
                    FeetX = feetX,
                    FeetY = feetY,
                    ShowTracer = showTracer,
                    TracerFrom = tracerFrom,
                    TracerTo = tracerTo,
                    TracerColor = tracerColor,
                    LineThickness = Config.ESP.LineThickness,
                    ShowArrow = showArrow,
                    ArrowPos = arrowPos,
                    ArrowAngle = arrowAngle,
                    ArrowColor = arrowColor,
                })

                if Config.ESP.HighlightESP then
                    local hlAllowed = (not Config.ESP.HighlightVisibleOnly) or visState.isVisible
                    if hlAllowed then
                        table.insert(highlightCandidates, {
                            Entry = entry,
                            TargetKey = targetKey,
                            Dist = worldDist,
                            ActiveColor = visState.activeColor,
                        })
                    elseif entry.Highlight then
                        entry.Highlight.Enabled = false
                    end
                elseif entry.Highlight then
                    entry.Highlight.Enabled = false
                end
            end
        end
    end

    if Config.ESP.Enabled and Config.ESP.HighlightESP and #highlightCandidates > 0 then
        table.sort(highlightCandidates, function(a, b)
            return a.Dist < b.Dist
        end)

        for idx, item in ipairs(highlightCandidates) do
            local entry = item.Entry
            if idx <= MAX_ACTIVE_HIGHLIGHTS then
                if not entry.Highlight or not entry.Highlight.Parent then
                    local ok, hl = pcall(function()
                        local instance = Instance.new("Highlight")
                        instance.Name = "AKI_HL_" .. getEntryDisplayName(entry, item.TargetKey)
                        instance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        instance.Parent = HighlightContainer
                        return instance
                    end)
                    if ok and hl then
                        entry.Highlight = hl
                    end
                end
                if entry.Highlight then
                    entry.Highlight.Adornee = entry.Character
                    entry.Highlight.FillColor = item.ActiveColor
                    entry.Highlight.OutlineColor = item.ActiveColor
                    entry.Highlight.FillTransparency = Config.ESP.HighlightFillTransparency
                    entry.Highlight.OutlineTransparency = Config.ESP.HighlightOutlineTransparency
                    entry.Highlight.Enabled = true
                end
            else
                destroyHighlight(entry)
            end
        end
    end
end

-- ============================================================================
-- [SECTION 7] AIMBOT WITH KINEMATIC PREDICTION (WIRED TO ISVALIDTARGET)
-- ============================================================================
addConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.E then
        State.IsHoldingAim = true
    end
end))

addConnection(UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.E then
        State.IsHoldingAim = false
    end
end))

local function isAimbotInputActive()
    if Config.Aimbot.ActivationMode == "Hold" then
        return State.IsHoldingAim
    end
    return Config.Aimbot.Enabled
end

local function findMatchingBonePosition(entry, mode, camera, screenCenter, maxAnchorPos)
    local bones = entry and entry.Bones
    if not bones or #bones == 0 then
        return nil
    end
    local bestPos = nil
    local bestScore = math.huge
    for _, bone in ipairs(bones) do
        if bone and bone.Parent then
            local bn = string.lower(bone.Name)
            local matches = false
            if mode == "Head" then
                matches = string.find(bn, "head", 1, true) ~= nil
                    or string.find(bn, "skull", 1, true) ~= nil
                    or string.find(bn, "neck", 1, true) ~= nil
            elseif mode == "Chest" then
                matches = string.find(bn, "chest", 1, true) ~= nil
                    or string.find(bn, "upper", 1, true) ~= nil
                    or string.find(bn, "torso", 1, true) ~= nil
                    or string.find(bn, "spine", 1, true) ~= nil
            elseif mode == "Closest" then
                matches = true
            end
            if matches then
                local okPos, bPos = pcall(function()
                    return bone.TransformedWorldCFrame.Position
                end)
                if okPos and isFiniteVector3(bPos) then
                    if (not maxAnchorPos) or (bPos - maxAnchorPos).Magnitude <= 28 then
                        if mode == "Closest" and camera and screenCenter then
                            local vp, onScreen = camera:WorldToViewportPoint(bPos)
                            if vp.Z > 0 and onScreen then
                                local sd = (Vector2.new(vp.X, vp.Y) - screenCenter).Magnitude
                                if sd < bestScore then
                                    bestScore = sd
                                    bestPos = bPos
                                end
                            end
                        else
                            return bPos
                        end
                    end
                end
            end
        end
    end
    return bestPos
end

local function getAimPartForEntry(entry, camera, screenCenter)
    local mode = Config.Aimbot.TargetPart
    if mode == "Head" then
        return getBodyAnchorPart(entry, "Head")
    elseif mode == "Chest" then
        return getBodyAnchorPart(entry, "Chest")
    elseif mode == "HumanoidRootPart" then
        return getBodyAnchorPart(entry, "Root")
    else
        local cands = entry.TargetCandidates
        local bestPart = nil
        local bestDist = math.huge
        local partsToCheck = {
            entry.Head,
            entry.Torso,
            cands.HumanoidRootPart,
            entry.RootPart,
        }
        for _, rp in ipairs(entry.RigParts) do
            table.insert(partsToCheck, rp)
        end
        for _, part in ipairs(partsToCheck) do
            if part and part.Parent and isFiniteVector3(part.Position) then
                local vp, onScreen = camera:WorldToViewportPoint(part.Position)
                if vp.Z > 0 then
                    local dist = (Vector2.new(vp.X, vp.Y) - screenCenter).Magnitude
                    if not onScreen then
                        dist = dist + 2000
                    end
                    if dist < bestDist then
                        bestDist = dist
                        bestPart = part
                    end
                end
            end
        end
        return bestPart or entry.RootPart
    end
end

local function getAimWorldPosition(entry, aimPart, camera, screenCenter)
    if not entry or not aimPart or not aimPart.Parent then
        return nil
    end
    local basePos = aimPart.Position
    if not isFiniteVector3(basePos) then
        return nil
    end
    local mode = Config.Aimbot.TargetPart
    if entry.Bones and #entry.Bones > 0 and (mode == "Head" or mode == "Chest" or mode == "Closest") then
        if #entry.RigParts <= 3 or (mode == "Head" and not entry.TargetCandidates.Head) then
            local bonePos = findMatchingBonePosition(entry, mode, camera, screenCenter, basePos)
            if bonePos then
                return bonePos
            end
        end
    end
    if mode == "Head" and aimPart == entry.RootPart and not entry.TargetCandidates.Head and aimPart.Size.Y >= 2.2 then
        basePos = basePos + Vector3.new(0, math.min(aimPart.Size.Y * 0.28, 1.8), 0)
    end
    return basePos
end

local function getRawPingSeconds()
    if not StatsService then
        return 0.055
    end
    local ok, pingMs = pcall(function()
        return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and isFiniteNumber(pingMs) and pingMs > 0 then
        return math.clamp((pingMs / 1000) * 0.55, 0.01, 0.28)
    end
    return 0.055
end

local function getLocalPingSeconds()
    if not Config.Aimbot.PingCompensation or not StatsService then
        return 0
    end
    local ok, pingMs = pcall(function()
        return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and isFiniteNumber(pingMs) and pingMs > 0 then
        return math.clamp((pingMs / 1000) * 0.5, 0, 0.25)
    end
    return 0
end

local function resolveTargetVelocity(entry, part, targetPos, dt)
    if entry.LastVelFrame == State.FrameIndex and entry.LastTrackedPart == part and isFiniteVector3(entry.EstimatedVel) then
        return entry.EstimatedVel
    end
    entry.LastVelFrame = State.FrameIndex

    local pos = isFiniteVector3(targetPos) and targetPos or part.Position
    if not isFiniteVector3(pos) then
        return Vector3.zero
    end

    local frameVel = Vector3.zero
    if entry.LastTrackedPart == part and entry.LastTrackedPos and dt > 0.0005 then
        local deltaPos = pos - entry.LastTrackedPos
        if isFiniteVector3(deltaPos) and deltaPos.Magnitude < 18 then
            frameVel = deltaPos / dt
        end
    end
    entry.LastTrackedPart = part
    entry.LastTrackedPos = pos

    local physVel = Vector3.zero
    pcall(function()
        physVel = part.AssemblyLinearVelocity
    end)

    local rawVel = (isFiniteVector3(physVel) and physVel.Magnitude >= 0.25 and physVel.Magnitude <= 140) and physVel or frameVel
    if not isFiniteVector3(rawVel) or rawVel.Magnitude > 140 then
        rawVel = Vector3.zero
    end

    -- Dampen vertical spikes so jumping/ragdolling targets never snap camera toward the sky
    local horiz = Vector3.new(rawVel.X, 0, rawVel.Z)
    if horiz.Magnitude > 115 then
        horiz = horiz.Unit * 115
    end
    local clampedY = math.clamp(rawVel.Y, -60, 60) * 0.45
    local safeVel = Vector3.new(horiz.X, clampedY, horiz.Z)

    entry.EstimatedVel = entry.EstimatedVel:Lerp(safeVel, 0.52)
    if not isFiniteVector3(entry.EstimatedVel) then
        entry.EstimatedVel = Vector3.zero
    end
    return entry.EstimatedVel
end

local function evaluateAimCandidate(targetKey, camera, screenCenter)
    local entry = Registry[targetKey]
    if not entry then
        return false, nil, nil, math.huge, math.huge
    end

    local aimPart = getAimPartForEntry(entry, camera, screenCenter)
    local aimWorldPos = getAimWorldPosition(entry, aimPart, camera, screenCenter)
    if not aimPart or not aimPart.Parent or not aimWorldPos then
        return false, nil, nil, math.huge, math.huge
    end

    local vp, onScreen = camera:WorldToViewportPoint(aimWorldPos)
    if vp.Z <= 0.1 or not onScreen or not isFiniteNumber(vp.X) or not isFiniteNumber(vp.Y) then
        return false, nil, nil, math.huge, math.huge
    end

    local screenDist = (Vector2.new(vp.X, vp.Y) - screenCenter).Magnitude
    if not isFiniteNumber(screenDist) or screenDist > Config.Aimbot.FOVRadius then
        return false, nil, nil, math.huge, math.huge
    end

    local valid, _, _, worldDist = IsValidTarget(targetKey, {
        checkTeam = Config.Aimbot.TeamCheck,
        checkVisible = Config.Aimbot.VisibleCheck,
        ignoreBots = Config.Aimbot.IgnoreBots,
        maxDistance = Config.Aimbot.MaxDistance,
        camera = camera,
        targetPart = aimPart,
    })

    if not valid then
        return false, nil, nil, math.huge, math.huge
    end

    return true, entry, aimPart, screenDist, worldDist
end

local function computePredictedTargetPoint(entry, part, basePos, worldDist, dt)
    local velocity = resolveTargetVelocity(entry, part, basePos, dt)
    local projLead = (Config.Aimbot.ProjectileSpeed > 0) and (worldDist / Config.Aimbot.ProjectileSpeed) or 0
    local leadTime
    if Config.Aimbot.AutoPredict then
        local pingSec = getRawPingSeconds()
        local distFactor = math.clamp(worldDist / 1350, 0, 0.095)
        local horizSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        local speedScale = (horizSpeed < 1.2) and 0.35 or math.clamp(0.75 + (horizSpeed / 120), 0.75, 1.42)
        leadTime = math.clamp((pingSec + distFactor) * speedScale + projLead, 0.01, 0.34)
    else
        leadTime = math.clamp(Config.Aimbot.Prediction + projLead + getLocalPingSeconds(), 0, 0.36)
    end

    local predOffset = velocity * leadTime
    if not isFiniteVector3(predOffset) then
        predOffset = Vector3.zero
    elseif predOffset.Magnitude > 16 then
        predOffset = predOffset.Unit * 16
    end

    local predictedPos = basePos + predOffset
    if not isFiniteVector3(predictedPos) then
        return basePos, leadTime
    end
    return predictedPos, leadTime
end

local function updateAimbot(camera, screenCenter, dt)
    if not Config.Aimbot.Enabled or not isAimbotInputActive() then
        State.CurrentAimTarget = nil
        State.CurrentAimPart = nil
        State.CurrentAimPredictedPos = nil
        return
    end

    local chosenEntry = nil
    local chosenPart = nil
    local chosenDist = 0

    if Config.Aimbot.StickyTarget and State.CurrentAimTarget then
        local ok, entry, part, _, worldDist = evaluateAimCandidate(State.CurrentAimTarget, camera, screenCenter)
        if ok and entry and part then
            chosenEntry = entry
            chosenPart = part
            chosenDist = worldDist
        else
            State.CurrentAimTarget = nil
        end
    end

    if not chosenPart then
        local bestScreenDist = math.huge
        local bestKey = nil
        local bestEntry = nil
        local bestPart = nil
        local bestWorldDist = 0

        for targetKey in pairs(Registry) do
            local ok, entry, part, screenDist, worldDist = evaluateAimCandidate(targetKey, camera, screenCenter)
            if ok and entry and part and screenDist < bestScreenDist then
                bestScreenDist = screenDist
                bestKey = targetKey
                bestEntry = entry
                bestPart = part
                bestWorldDist = worldDist
            end
        end

        State.CurrentAimTarget = bestKey
        chosenEntry = bestEntry
        chosenPart = bestPart
        chosenDist = bestWorldDist
    end

    if not chosenPart or not chosenEntry then
        State.CurrentAimPart = nil
        State.CurrentAimPredictedPos = nil
        return
    end

    local camPos = camera.CFrame.Position
    local aimBasePos = getAimWorldPosition(chosenEntry, chosenPart, camera, screenCenter)
    if not isFiniteVector3(camPos) or not aimBasePos then
        State.CurrentAimPart = nil
        State.CurrentAimPredictedPos = nil
        return
    end

    local predictedPos = computePredictedTargetPoint(chosenEntry, chosenPart, aimBasePos, chosenDist, dt)
    State.CurrentAimPart = chosenPart
    State.CurrentAimPredictedPos = predictedPos
    State.CurrentAimFrame = State.FrameIndex

    local aimDelta = predictedPos - camPos
    if (not isFiniteVector3(predictedPos)) or aimDelta.Magnitude < 0.4 then
        return
    end

    local targetCFrame = CFrame.lookAt(camPos, predictedPos)
    local smoothness = math.clamp(Config.Aimbot.Smoothness, 1, 20)
    if smoothness <= 1.05 then
        camera.CFrame = targetCFrame
    else
        local stepAlpha = math.clamp(1 / smoothness, 0.04, 1)
        local alpha = 1 - math.pow(1 - stepAlpha, math.clamp(dt * 60, 0.25, 3))
        camera.CFrame = camera.CFrame:Lerp(targetCFrame, alpha)
    end
end

-- ============================================================================
-- Trigger Bot Engine (100% Touch-Safe: VirtualInputManager / firesignal / Tool:Activate)
-- ============================================================================
local TriggerEngine = {
    FireSignalCandidates = {},
    ActiveFireIdx = 1,
    FireSignalStatus = "Scanning...",
    ToolCandidates = {},
    ActiveToolIdx = 1,
    ToolCallStatus = "Scanning...",
    LastScanTime = 0,
    ConsecutiveZeroResponse = 0,
    LastConfirmedKey = "",
    UiListeners = {},
}

function TriggerEngine.notifyUi()
    for _, cb in ipairs(TriggerEngine.UiListeners) do
        pcall(cb)
    end
end

function TriggerEngine.getStablePath(inst)
    if not inst or not inst.Parent then
        return ""
    end
    local parts = {}
    local cur = inst
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    for _ = 1, 14 do
        if not cur then break end
        if cur == pg then
            table.insert(parts, 1, "PlayerGui")
            break
        elseif cur == bp then
            table.insert(parts, 1, "Backpack")
            break
        elseif State.LocalCharacter and cur == State.LocalCharacter then
            table.insert(parts, 1, "Character")
            break
        elseif cur == LocalPlayer then
            table.insert(parts, 1, "LocalPlayer")
            break
        elseif cur == game then
            break
        end
        table.insert(parts, 1, cur.Name)
        cur = cur.Parent
    end
    return table.concat(parts, ".")
end

function TriggerEngine.isOwnOrSystemGui(obj)
    if not obj then return true end
    if State.MainGui and obj:IsDescendantOf(State.MainGui) then return true end
    if State.OverlayGui and obj:IsDescendantOf(State.OverlayGui) then return true end
    if obj:FindFirstAncestor("TouchGui") ~= nil then return true end
    local cur = obj
    while cur do
        if cur:IsA("ScreenGui") then
            local n = string.lower(cur.Name)
            if string.find(n, "team_aki", 1, true) or n == "touchgui" or n == "chat" or n == "freecam" then
                return true
            end
            if not cur.Enabled then
                return true
            end
        elseif cur:IsA("GuiObject") and cur.Visible == false then
            return true
        end
        cur = cur.Parent
    end
    return false
end

function TriggerEngine.countEnabledConnections(sig)
    if not sig or type(getconnections) ~= "function" then
        return 0
    end
    local ok, conns = pcall(getconnections, sig)
    if not ok or type(conns) ~= "table" then
        return 0
    end
    local count = 0
    for _, c in ipairs(conns) do
        if c and c.Enabled ~= false then
            count = count + 1
        end
    end
    return count
end

function TriggerEngine.invokeSignalSafe(sig, ...)
    if not sig then
        return false
    end
    local argCount = select("#", ...)
    local args = {...}
    local invoked = false

    if type(firesignal) == "function" then
        local okFire = pcall(function()
            firesignal(sig, unpackFn(args, 1, argCount))
        end)
        if okFire then
            invoked = true
        end
    end

    if (not invoked) and type(getconnections) == "function" then
        local okConns, conns = pcall(getconnections, sig)
        if okConns and type(conns) == "table" then
            for _, conn in ipairs(conns) do
                if conn and conn.Enabled ~= false then
                    local okCall = pcall(function()
                        if type(conn.Fire) == "function" then
                            task.spawn(function()
                                pcall(conn.Fire, conn, unpackFn(args, 1, argCount))
                            end)
                            invoked = true
                        elseif type(conn.Function) == "function" then
                            task.spawn(conn.Function, unpackFn(args, 1, argCount))
                            invoked = true
                        end
                    end)
                    if okCall then
                        invoked = true
                    end
                end
            end
        end
    end

    return invoked
end

function TriggerEngine.makeFakeTouchInput(x, y, isBegin)
    return {
        UserInputType = Enum.UserInputType.Touch,
        UserInputState = isBegin and Enum.UserInputState.Begin or Enum.UserInputState.End,
        KeyCode = Enum.KeyCode.Unknown,
        Position = Vector3.new(x or 0, y or 0, 0),
        Delta = Vector3.zero,
        IsModifierKeyDown = function()
            return false
        end,
        IsA = function(_, cls)
            return cls == "InputObject" or cls == "Instance"
        end,
    }
end

TriggerEngine.POSITIVE_FIRE_WORDS = {
    "fire", "shoot", "shot", "attack", "trigger", "primary", "gun", "weapon",
    "m1", "blast", "slash", "swing", "punch", "combat", "use", "action", "hit",
}

TriggerEngine.NEGATIVE_UI_WORDS = {
    "shop", "store", "menu", "setting", "chat", "emote", "inventory", "backpack",
    "jump", "crouch", "prone", "slide", "sprint", "run", "reload", "aim", "ads",
    "scope", "zoom", "drop", "leaderboard", "spectate", "close", "exit", "cancel",
    "buy", "crate", "case", "pet", "trade", "wardrobe", "customize", "switch",
}

function TriggerEngine.scoreFireButton(btn, viewportSize)
    local combined = string.lower(btn.Name .. " " .. (btn.Parent and btn.Parent.Name or ""))
    pcall(function()
        if btn:IsA("TextButton") and type(btn.Text) == "string" then
            combined = combined .. " " .. string.lower(btn.Text)
        end
        for _, ch in ipairs(btn:GetChildren()) do
            if ch:IsA("TextLabel") and type(ch.Text) == "string" then
                combined = combined .. " " .. string.lower(ch.Text)
            end
        end
    end)

    for _, neg in ipairs(TriggerEngine.NEGATIVE_UI_WORDS) do
        if string.find(combined, neg, 1, true) then
            return -100
        end
    end

    local score = 0
    for _, pos in ipairs(TriggerEngine.POSITIVE_FIRE_WORDS) do
        if string.find(combined, pos, 1, true) then
            score = score + 35
        end
    end

    local absPos = btn.AbsolutePosition
    local absSize = btn.AbsoluteSize
    if absSize.X < 18 or absSize.Y < 18 then
        return -50
    end
    if viewportSize and viewportSize.X > 0 and absPos.X >= viewportSize.X * 0.48 then
        score = score + 14
    end
    if absSize.X >= 36 and absSize.X <= 190 and absSize.Y >= 36 and absSize.Y <= 190 then
        score = score + 10
    end
    if btn.Active ~= false then
        score = score + 6
    end
    return score
end

function TriggerEngine.scanFireSignals()
    local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local list = {}
    local savedKey = Config.TriggerBot.SavedFireSignalKey or ""
    local broken = Config.TriggerBot.BrokenFireSignals or {}
    local vp = (State.Camera and State.Camera.ViewportSize) or Vector2.new(1280, 720)

    if pg then
        for _, desc in ipairs(pg:GetDescendants()) do
            if desc:IsA("GuiButton") and (not TriggerEngine.isOwnOrSystemGui(desc)) then
                local baseScore = TriggerEngine.scoreFireButton(desc, vp)
                if baseScore > 0 then
                    local path = TriggerEngine.getStablePath(desc)
                    local sigDefs = {
                        { Name = "MouseButton1Down", Sig = desc.MouseButton1Down, Bonus = 8 },
                        { Name = "Activated", Sig = desc.Activated, Bonus = 7 },
                        { Name = "MouseButton1Click", Sig = desc.MouseButton1Click, Bonus = 6 },
                        { Name = "TouchTap", Sig = desc.TouchTap, Bonus = 5 },
                        { Name = "InputBegan", Sig = desc.InputBegan, Bonus = 3 },
                    }
                    for _, sdef in ipairs(sigDefs) do
                        local connCount = TriggerEngine.countEnabledConnections(sdef.Sig)
                        if connCount > 0 or sdef.Name == "Activated" or sdef.Name == "MouseButton1Down" then
                            local key = path .. "::" .. sdef.Name
                            local isBroken = (broken[key] == true)
                            local totalScore = baseScore + sdef.Bonus + math.min(connCount * 8, 24)
                            if key == savedKey and (not isBroken) then
                                totalScore = totalScore + 5000
                            end
                            if not isBroken then
                                table.insert(list, {
                                    Key = key,
                                    Label = desc.Name .. " -> " .. sdef.Name,
                                    Button = desc,
                                    SignalName = sdef.Name,
                                    Signal = sdef.Sig,
                                    ConnCount = connCount,
                                    Score = totalScore,
                                    Confirmed = (key == savedKey and savedKey ~= ""),
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if a.Score ~= b.Score then
            return a.Score > b.Score
        end
        return a.Key < b.Key
    end)

    -- Cap candidate list to top 16 ranked calls
    while #list > 16 do
        table.remove(list)
    end

    TriggerEngine.FireSignalCandidates = list
    if #list == 0 then
        TriggerEngine.ActiveFireIdx = 1
        TriggerEngine.FireSignalStatus = "No fire button signals found"
    else
        if TriggerEngine.ActiveFireIdx > #list or TriggerEngine.ActiveFireIdx < 1 then
            TriggerEngine.ActiveFireIdx = 1
        end
        local active = list[TriggerEngine.ActiveFireIdx]
        if active.Confirmed then
            TriggerEngine.FireSignalStatus = "Saved: " .. active.Label
        else
            TriggerEngine.FireSignalStatus = string.format("#%d Auto: %s", TriggerEngine.ActiveFireIdx, active.Label)
        end
    end
    TriggerEngine.notifyUi()
end

function TriggerEngine.scanToolCalls()
    local list = {}
    local savedKey = Config.TriggerBot.SavedToolCallKey or ""
    local broken = Config.TriggerBot.BrokenToolCalls or {}

    local toolEntries = {}
    local localChar = State.LocalCharacter or LocalPlayer.Character
    if localChar then
        for _, ch in ipairs(localChar:GetChildren()) do
            if ch:IsA("Tool") then
                table.insert(toolEntries, { Tool = ch, Equipped = true })
            end
        end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, ch in ipairs(bp:GetChildren()) do
            if ch:IsA("Tool") then
                table.insert(toolEntries, { Tool = ch, Equipped = false })
            end
        end
    end

    for _, tinfo in ipairs(toolEntries) do
        local tool = tinfo.Tool
        local eqBonus = tinfo.Equipped and 60 or 10

        -- Candidate 1: Native Tool:Activate()
        do
            local key = "Tool:" .. tool.Name .. "::Activate"
            if not broken[key] then
                local score = 100 + eqBonus + ((key == savedKey) and 5000 or 0)
                table.insert(list, {
                    Key = key,
                    Label = tool.Name .. ":Activate()",
                    Kind = "Activate",
                    Tool = tool,
                    Equipped = tinfo.Equipped,
                    Score = score,
                    Confirmed = (key == savedKey and savedKey ~= ""),
                })
            end
        end

        -- Candidate 2: Tool.Activated signal via firesignal/getconnections
        local actCount = TriggerEngine.countEnabledConnections(tool.Activated)
        if actCount > 0 then
            local key = "Tool:" .. tool.Name .. "::ActivatedSignal"
            if not broken[key] then
                local score = 88 + eqBonus + math.min(actCount * 6, 18) + ((key == savedKey) and 5000 or 0)
                table.insert(list, {
                    Key = key,
                    Label = tool.Name .. ".Activated",
                    Kind = "ActivatedSignal",
                    Tool = tool,
                    Signal = tool.Activated,
                    Equipped = tinfo.Equipped,
                    Score = score,
                    Confirmed = (key == savedKey and savedKey ~= ""),
                })
            end
        end

        -- Candidate 3: Tool child BindableEvent / Activation Remote or MouseButton1Click hooks
        for _, desc in ipairs(tool:GetDescendants()) do
            if desc:IsA("BindableEvent") then
                local dn = string.lower(desc.Name)
                if string.find(dn, "fire", 1, true) or string.find(dn, "shoot", 1, true) or string.find(dn, "attack", 1, true) or string.find(dn, "activate", 1, true) then
                    local key = "Tool:" .. tool.Name .. "::Bindable:" .. desc.Name
                    if not broken[key] then
                        local score = 70 + eqBonus + ((key == savedKey) and 5000 or 0)
                        table.insert(list, {
                            Key = key,
                            Label = tool.Name .. " -> " .. desc.Name .. ":Fire()",
                            Kind = "Bindable",
                            Tool = tool,
                            Bindable = desc,
                            Equipped = tinfo.Equipped,
                            Score = score,
                            Confirmed = (key == savedKey and savedKey ~= ""),
                        })
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if a.Score ~= b.Score then
            return a.Score > b.Score
        end
        return a.Key < b.Key
    end)

    while #list > 14 do
        table.remove(list)
    end

    TriggerEngine.ToolCandidates = list
    if #list == 0 then
        TriggerEngine.ActiveToolIdx = 1
        TriggerEngine.ToolCallStatus = "Equip or hold a Tool to scan"
    else
        if TriggerEngine.ActiveToolIdx > #list or TriggerEngine.ActiveToolIdx < 1 then
            TriggerEngine.ActiveToolIdx = 1
        end
        local active = list[TriggerEngine.ActiveToolIdx]
        if active.Confirmed then
            TriggerEngine.ToolCallStatus = "Saved: " .. active.Label
        else
            TriggerEngine.ToolCallStatus = string.format("#%d Auto: %s", TriggerEngine.ActiveToolIdx, active.Label)
        end
    end
    TriggerEngine.notifyUi()
end

function TriggerEngine.rescanAll()
    TriggerEngine.LastScanTime = os.clock()
    TriggerEngine.scanFireSignals()
    TriggerEngine.scanToolCalls()
end

function TriggerEngine.captureCombatActivitySnapshot(targetEntry)
    local ammoSum = 0
    local localChar = State.LocalCharacter or LocalPlayer.Character
    if localChar then
        for _, ch in ipairs(localChar:GetDescendants()) do
            if ch:IsA("NumberValue") or ch:IsA("IntValue") then
                local ln = string.lower(ch.Name)
                if string.find(ln, "ammo", 1, true) or string.find(ln, "clip", 1, true) or string.find(ln, "mag", 1, true) then
                    ammoSum = ammoSum + ch.Value
                end
            end
        end
    end
    local targetHp = -1
    if targetEntry and targetEntry.Humanoid and targetEntry.Humanoid.Parent then
        targetHp = targetEntry.Humanoid.Health
    end
    return ammoSum, targetHp
end

function TriggerEngine.verifyAndSaveCandidate(modeName, cand, targetEntry, beforeAmmo, beforeHp)
    if not cand or State.Unloaded then
        return
    end
    local snapKey = cand.Key
    task.delay(0.18, function()
        if State.Unloaded then return end
        local afterAmmo, afterHp = TriggerEngine.captureCombatActivitySnapshot(targetEntry)
        local reacted = (afterAmmo < beforeAmmo) or (beforeHp > 0 and afterHp >= 0 and afterHp < beforeHp)
        if reacted then
            cand.Confirmed = true
            if modeName == "firesignal" then
                if Config.TriggerBot.SavedFireSignalKey ~= snapKey then
                    Config.TriggerBot.SavedFireSignalKey = snapKey
                    TriggerEngine.FireSignalStatus = "Confirmed: " .. cand.Label
                    ConfigStore.scheduleSave()
                    TriggerEngine.notifyUi()
                end
            elseif modeName == "Tool:Activate()" then
                if Config.TriggerBot.SavedToolCallKey ~= snapKey then
                    Config.TriggerBot.SavedToolCallKey = snapKey
                    TriggerEngine.ToolCallStatus = "Confirmed: " .. cand.Label
                    ConfigStore.scheduleSave()
                    TriggerEngine.notifyUi()
                end
            end
        end
    end)
end

function TriggerEngine.advanceCandidate(modeName, markFailed)
    if modeName == "firesignal" then
        local list = TriggerEngine.FireSignalCandidates
        if #list == 0 then
            TriggerEngine.scanFireSignals()
            return
        end
        if markFailed then
            local cur = list[TriggerEngine.ActiveFireIdx]
            if cur and Config.TriggerBot.SavedFireSignalKey == cur.Key then
                Config.TriggerBot.SavedFireSignalKey = ""
                ConfigStore.scheduleSave()
            end
        end
        TriggerEngine.ActiveFireIdx = (TriggerEngine.ActiveFireIdx % #list) + 1
        local nxt = list[TriggerEngine.ActiveFireIdx]
        TriggerEngine.FireSignalStatus = nxt and string.format("#%d Trying: %s", TriggerEngine.ActiveFireIdx, nxt.Label) or "Scanning..."
    elseif modeName == "Tool:Activate()" then
        local list = TriggerEngine.ToolCandidates
        if #list == 0 then
            TriggerEngine.scanToolCalls()
            return
        end
        if markFailed then
            local cur = list[TriggerEngine.ActiveToolIdx]
            if cur and Config.TriggerBot.SavedToolCallKey == cur.Key then
                Config.TriggerBot.SavedToolCallKey = ""
                ConfigStore.scheduleSave()
            end
        end
        TriggerEngine.ActiveToolIdx = (TriggerEngine.ActiveToolIdx % #list) + 1
        local nxt = list[TriggerEngine.ActiveToolIdx]
        TriggerEngine.ToolCallStatus = nxt and string.format("#%d Trying: %s", TriggerEngine.ActiveToolIdx, nxt.Label) or "Scanning..."
    end
    TriggerEngine.ConsecutiveZeroResponse = 0
    TriggerEngine.notifyUi()
end

function TriggerEngine.markCurrentCallBroken()
    local mode = Config.TriggerBot.Mode
    if mode == "firesignal" then
        local cur = TriggerEngine.FireSignalCandidates[TriggerEngine.ActiveFireIdx]
        if cur then
            Config.TriggerBot.BrokenFireSignals[cur.Key] = true
            if Config.TriggerBot.SavedFireSignalKey == cur.Key then
                Config.TriggerBot.SavedFireSignalKey = ""
            end
            TriggerEngine.FireSignalStatus = "Flagged broken -> switched"
            TriggerEngine.scanFireSignals()
            ConfigStore.scheduleSave()
        else
            TriggerEngine.scanFireSignals()
        end
    elseif mode == "Tool:Activate()" then
        local cur = TriggerEngine.ToolCandidates[TriggerEngine.ActiveToolIdx]
        if cur then
            Config.TriggerBot.BrokenToolCalls[cur.Key] = true
            if Config.TriggerBot.SavedToolCallKey == cur.Key then
                Config.TriggerBot.SavedToolCallKey = ""
            end
            TriggerEngine.ToolCallStatus = "Flagged broken -> switched"
            TriggerEngine.scanToolCalls()
            ConfigStore.scheduleSave()
        else
            TriggerEngine.scanToolCalls()
        end
    end
    TriggerEngine.notifyUi()
end

function TriggerEngine.selectCandidateByKey(modeName, key)
    if modeName == "firesignal" then
        Config.TriggerBot.BrokenFireSignals[key] = nil
        Config.TriggerBot.SavedFireSignalKey = key
        TriggerEngine.scanFireSignals()
        for idx, c in ipairs(TriggerEngine.FireSignalCandidates) do
            if c.Key == key then
                TriggerEngine.ActiveFireIdx = idx
                c.Confirmed = true
                TriggerEngine.FireSignalStatus = "Selected: " .. c.Label
                break
            end
        end
        ConfigStore.scheduleSave()
    elseif modeName == "Tool:Activate()" then
        Config.TriggerBot.BrokenToolCalls[key] = nil
        Config.TriggerBot.SavedToolCallKey = key
        TriggerEngine.scanToolCalls()
        for idx, c in ipairs(TriggerEngine.ToolCandidates) do
            if c.Key == key then
                TriggerEngine.ActiveToolIdx = idx
                c.Confirmed = true
                TriggerEngine.ToolCallStatus = "Selected: " .. c.Label
                break
            end
        end
        ConfigStore.scheduleSave()
    end
    TriggerEngine.notifyUi()
end

function TriggerEngine.resetBrokenCalls()
    local mode = Config.TriggerBot.Mode
    if mode == "firesignal" then
        clearTable(Config.TriggerBot.BrokenFireSignals)
        TriggerEngine.scanFireSignals()
        ConfigStore.scheduleSave()
    elseif mode == "Tool:Activate()" then
        clearTable(Config.TriggerBot.BrokenToolCalls)
        TriggerEngine.scanToolCalls()
        ConfigStore.scheduleSave()
    end
    TriggerEngine.notifyUi()
end

function TriggerEngine.getPointerViewportCoords(camera)
    local vp = (camera and camera.ViewportSize) or Vector2.new(1280, 720)
    local px = math.round(math.clamp(Config.TriggerBot.PointerScaleX, 0.04, 0.96) * vp.X)
    local py = math.round(math.clamp(Config.TriggerBot.PointerScaleY, 0.06, 0.94) * vp.Y)
    return px, py
end

function TriggerEngine.sendVimTouch(isBegin, x, y)
    if not VirtualInputManager then
        return false
    end
    local touchState = isBegin and 0 or 2
    local ok = pcall(function()
        VirtualInputManager:SendTouchEvent(7, touchState, x, y)
    end)
    return ok
end

releaseTriggerFire = function()
    if State.TriggerVimTouchDown then
        State.TriggerVimTouchDown = false
        local pos = State.TriggerVimTouchPos
        TriggerEngine.sendVimTouch(false, math.round(pos.X), math.round(pos.Y))
    end
    if State.TriggerToolRef and State.TriggerToolRef.Parent then
        pcall(function()
            State.TriggerToolRef:Deactivate()
        end)
    end
    State.TriggerToolRef = nil
    State.TriggerHolding = false
end

function TriggerEngine.fireVirtualInputManager(camera, holdMode)
    local px, py = TriggerEngine.getPointerViewportCoords(camera)
    State.TriggerVimTouchPos = Vector2.new(px, py)
    if holdMode then
        if not State.TriggerVimTouchDown then
            local ok = TriggerEngine.sendVimTouch(true, px, py)
            if ok then
                State.TriggerVimTouchDown = true
                State.TriggerHolding = true
                return true
            end
        else
            return true
        end
    else
        if State.TriggerVimTouchDown then
            TriggerEngine.sendVimTouch(false, px, py)
            State.TriggerVimTouchDown = false
        end
        local ok = TriggerEngine.sendVimTouch(true, px, py)
        if ok then
            State.TriggerVimTouchDown = true
            task.delay(0.035, function()
                if not State.TriggerHolding and State.TriggerVimTouchDown then
                    State.TriggerVimTouchDown = false
                    TriggerEngine.sendVimTouch(false, px, py)
                end
            end)
            return true
        end
    end
    return false
end

function TriggerEngine.fireViaFireSignal(targetEntry, holdMode)
    if #TriggerEngine.FireSignalCandidates == 0 then
        TriggerEngine.scanFireSignals()
    end
    local cand = TriggerEngine.FireSignalCandidates[TriggerEngine.ActiveFireIdx]
    if not cand or not cand.Button or not cand.Button.Parent then
        TriggerEngine.scanFireSignals()
        cand = TriggerEngine.FireSignalCandidates[TriggerEngine.ActiveFireIdx]
    end
    if not cand then
        TriggerEngine.FireSignalStatus = "No fire signal found"
        return false
    end

    local beforeAmmo, beforeHp = TriggerEngine.captureCombatActivitySnapshot(targetEntry)
    local btn = cand.Button
    local cx = math.round(btn.AbsolutePosition.X + btn.AbsoluteSize.X * 0.5)
    local cy = math.round(btn.AbsolutePosition.Y + btn.AbsoluteSize.Y * 0.5)

    local okFire = false
    if cand.SignalName == "MouseButton1Down" then
        okFire = TriggerEngine.invokeSignalSafe(btn.MouseButton1Down, cx, cy)
    elseif cand.SignalName == "Activated" then
        okFire = TriggerEngine.invokeSignalSafe(btn.Activated, TriggerEngine.makeFakeTouchInput(cx, cy, true), 1)
    elseif cand.SignalName == "MouseButton1Click" then
        okFire = TriggerEngine.invokeSignalSafe(btn.MouseButton1Click)
    elseif cand.SignalName == "TouchTap" then
        okFire = TriggerEngine.invokeSignalSafe(btn.TouchTap, {Vector2.new(cx, cy)}, Enum.UserInputState.End)
    elseif cand.SignalName == "InputBegan" then
        okFire = TriggerEngine.invokeSignalSafe(btn.InputBegan, TriggerEngine.makeFakeTouchInput(cx, cy, true))
    end

    if okFire then
        TriggerEngine.ConsecutiveZeroResponse = 0
        TriggerEngine.verifyAndSaveCandidate("firesignal", cand, targetEntry, beforeAmmo, beforeHp)
        if not cand.Confirmed then
            -- Auto-persist working non-erroring primary signal after clean executions if game doesn't expose ammo values
            if TriggerEngine.LastConfirmedKey == cand.Key then
                cand.Confirmed = true
                Config.TriggerBot.SavedFireSignalKey = cand.Key
                TriggerEngine.FireSignalStatus = "Saved: " .. cand.Label
                ConfigStore.scheduleSave()
                TriggerEngine.notifyUi()
            else
                TriggerEngine.LastConfirmedKey = cand.Key
            end
        end
        if holdMode then
            State.TriggerHolding = true
        else
            task.delay(0.035, function()
                if not State.TriggerHolding and btn and btn.Parent then
                    pcall(TriggerEngine.invokeSignalSafe, btn.MouseButton1Up, cx, cy)
                    pcall(TriggerEngine.invokeSignalSafe, btn.InputEnded, TriggerEngine.makeFakeTouchInput(cx, cy, false))
                end
            end)
        end
        return true
    else
        TriggerEngine.ConsecutiveZeroResponse = TriggerEngine.ConsecutiveZeroResponse + 1
        if TriggerEngine.ConsecutiveZeroResponse >= 2 then
            TriggerEngine.advanceCandidate("firesignal", true)
        end
        return false
    end
end

function TriggerEngine.fireViaToolActivate(targetEntry, holdMode)
    if #TriggerEngine.ToolCandidates == 0 then
        TriggerEngine.scanToolCalls()
    end
    local cand = TriggerEngine.ToolCandidates[TriggerEngine.ActiveToolIdx]
    if not cand or not cand.Tool or not cand.Tool.Parent then
        TriggerEngine.scanToolCalls()
        cand = TriggerEngine.ToolCandidates[TriggerEngine.ActiveToolIdx]
    end
    if not cand then
        TriggerEngine.ToolCallStatus = "No valid Tool found"
        return false
    end

    local tool = cand.Tool
    local localChar = State.LocalCharacter or LocalPlayer.Character
    if localChar and tool.Parent ~= localChar then
        local hum = State.LocalHumanoid
        if hum and hum.Parent then
            pcall(function()
                hum:EquipTool(tool)
            end)
        end
    end

    local beforeAmmo, beforeHp = TriggerEngine.captureCombatActivitySnapshot(targetEntry)
    local okFire = false

    if cand.Kind == "Activate" then
        okFire = pcall(function()
            tool:Activate()
        end)
        if okFire then
            State.TriggerToolRef = tool
        end
    elseif cand.Kind == "ActivatedSignal" then
        okFire = TriggerEngine.invokeSignalSafe(tool.Activated)
    elseif cand.Kind == "Bindable" and cand.Bindable and cand.Bindable.Parent then
        okFire = pcall(function()
            cand.Bindable:Fire()
        end)
    end

    if okFire then
        TriggerEngine.ConsecutiveZeroResponse = 0
        TriggerEngine.verifyAndSaveCandidate("Tool:Activate()", cand, targetEntry, beforeAmmo, beforeHp)
        if not cand.Confirmed and tool.Parent == localChar then
            if TriggerEngine.LastConfirmedKey == cand.Key then
                cand.Confirmed = true
                Config.TriggerBot.SavedToolCallKey = cand.Key
                TriggerEngine.ToolCallStatus = "Saved: " .. cand.Label
                ConfigStore.scheduleSave()
                TriggerEngine.notifyUi()
            else
                TriggerEngine.LastConfirmedKey = cand.Key
            end
        end
        if holdMode then
            State.TriggerHolding = true
        else
            task.delay(0.035, function()
                if not State.TriggerHolding and tool and tool.Parent then
                    pcall(function()
                        tool:Deactivate()
                    end)
                end
            end)
        end
        return true
    else
        TriggerEngine.ConsecutiveZeroResponse = TriggerEngine.ConsecutiveZeroResponse + 1
        if TriggerEngine.ConsecutiveZeroResponse >= 2 then
            TriggerEngine.advanceCandidate("Tool:Activate()", true)
        end
        return false
    end
end

function TriggerEngine.dispatchFire(camera, targetEntry, holdMode)
    local mode = Config.TriggerBot.Mode
    if mode == "VirtualInputManager" then
        return TriggerEngine.fireVirtualInputManager(camera, holdMode)
    elseif mode == "firesignal" then
        return TriggerEngine.fireViaFireSignal(targetEntry, holdMode)
    elseif mode == "Tool:Activate()" then
        return TriggerEngine.fireViaToolActivate(targetEntry, holdMode)
    end
    return false
end

local function partMatchesTriggerFilter(part, entry)
    local filter = Config.TriggerBot.TargetFilter
    if filter == "Any Part" then
        return true
    end
    local n = string.lower(part.Name)
    if filter == "Head Only" then
        return part == entry.Head or string.find(n, "head", 1, true) ~= nil or string.find(n, "skull", 1, true) ~= nil
    end
    -- "Head & Chest"
    return part == entry.Head
        or part == entry.Torso
        or part == entry.RootPart
        or string.find(n, "head", 1, true) ~= nil
        or string.find(n, "torso", 1, true) ~= nil
        or string.find(n, "chest", 1, true) ~= nil
        or string.find(n, "body", 1, true) ~= nil
        or string.find(n, "core", 1, true) ~= nil
        or string.find(n, "spine", 1, true) ~= nil
        or string.find(n, "hull", 1, true) ~= nil
        or n == "humanoidrootpart"
end

local function findEntryForHitPart(hitPart)
    if not hitPart then
        return nil, nil
    end
    for player, entry in pairs(Registry) do
        if entry.Character and hitPart:IsDescendantOf(entry.Character) then
            return player, entry
        end
    end

    local localChar = State.LocalCharacter or LocalPlayer.Character
    local cur = hitPart.Parent
    for _ = 1, 4 do
        if not cur or cur == Workspace or cur == game then
            break
        end
        if cur ~= localChar and cur:IsA("Model") then
            local plr = Players:GetPlayerFromCharacter(cur)
            if plr and plr ~= LocalPlayer then
                if not Registry[plr] then
                    registerPlayerEntry(plr)
                end
                if Registry[plr] then
                    bindCharacterToEntry(Registry[plr], cur)
                    return plr, Registry[plr]
                end
            end
            local hum = cur:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                if not Registry[cur] and not Config.TriggerBot.IgnoreBots and isModelBotAlive(cur) then
                    registerBotEntry(cur)
                end
                if Registry[cur] then
                    return cur, Registry[cur]
                end
            end
        end
        cur = cur.Parent
    end

    return nil, nil
end

local function findTriggerTarget(camera, screenCenter, dt)
    local maxDist = Config.TriggerBot.MaxDistance
    local origin = camera.CFrame.Position
    local dirUnit = camera.CFrame.LookVector

    local filterList = {OverlayGui, HighlightContainer, camera}
    local localChar = State.LocalCharacter or LocalPlayer.Character
    if localChar then
        table.insert(filterList, localChar)
    end

    RayParams.IgnoreWater = Config.ESP.IgnoreGlassWater
    local currentOrigin = origin
    local remaining = maxDist

    for _ = 1, 8 do
        if remaining < 0.1 then
            break
        end
        RayParams.FilterDescendantsInstances = filterList
        local result = Workspace:Raycast(currentOrigin, dirUnit * remaining, RayParams)
        if not result or not result.Instance then
            break
        end

        local hitPart = result.Instance
        local hitDistFromCam = (result.Position - origin).Magnitude
        local hitKey, hitEntry = findEntryForHitPart(hitPart)
        local shouldContinue = false
        if hitKey and hitEntry then
            if partMatchesTriggerFilter(hitPart, hitEntry) then
                local valid = IsValidTarget(hitKey, {
                    checkTeam = Config.TriggerBot.TeamCheck,
                    checkVisible = false,
                    ignoreBots = Config.TriggerBot.IgnoreBots,
                    maxDistance = maxDist,
                    camera = camera,
                    targetPart = hitPart,
                })
                if valid then
                    return hitKey, hitEntry, hitPart, result.Position
                end
            elseif hitPart:FindFirstAncestorOfClass("Accessory") ~= nil then
                shouldContinue = true
            end
            if not shouldContinue then
                break
            end
        end

        if shouldContinue then
            table.insert(filterList, hitPart)
            remaining = remaining - (result.Position - currentOrigin).Magnitude - 0.05
            currentOrigin = result.Position + dirUnit * 0.05
        else
            local isCloseViewmodel = hitDistFromCam < 4.5 and (
                hitPart:FindFirstAncestorOfClass("Tool") ~= nil
                or string.find(string.lower(hitPart.Name), "viewmodel", 1, true) ~= nil
                or (hitPart.Parent and string.find(string.lower(hitPart.Parent.Name), "viewmodel", 1, true) ~= nil)
                or (hitPart.Parent and string.find(string.lower(hitPart.Parent.Name), "arms", 1, true) ~= nil)
            )
            local isAccessory = hitPart:FindFirstAncestorOfClass("Accessory") ~= nil
            local isNonBlockingGlass = Config.ESP.IgnoreGlassWater
                and (hitPart.Transparency >= 0.45 or hitPart.Material == Enum.Material.Glass)
            if isCloseViewmodel or (not hitPart.CanCollide) or isAccessory or isNonBlockingGlass or hitPart.Transparency >= 0.92 then
                table.insert(filterList, hitPart)
                remaining = remaining - (result.Position - currentOrigin).Magnitude - 0.05
                currentOrigin = result.Position + dirUnit * 0.05
            else
                break
            end
        end
    end

    -- Pass 2: Aimbot Lock & Prediction Synchronization
    local syncTol = math.max(Config.TriggerBot.CrosshairTolerance, 6)
    if Config.TriggerBot.SyncWithAimbot and Config.Aimbot.Enabled and State.CurrentAimTarget and State.CurrentAimFrame == State.FrameIndex then
        local aimKey = State.CurrentAimTarget
        local aimEntry = Registry[aimKey]
        local aimPart = State.CurrentAimPart
        local predPos = State.CurrentAimPredictedPos
        if aimEntry and aimPart and aimPart.Parent and predPos then
            local filterOk = (Config.TriggerBot.TargetFilter == "Any Part") or partMatchesTriggerFilter(aimPart, aimEntry)
            if filterOk then
                local vpPred, onPred = camera:WorldToViewportPoint(predPos)
                local predDist = (vpPred.Z > 0 and onPred) and (Vector2.new(vpPred.X, vpPred.Y) - screenCenter).Magnitude or math.huge
                local vpReal, onReal = camera:WorldToViewportPoint(aimPart.Position)
                local realDist = (vpReal.Z > 0 and onReal) and (Vector2.new(vpReal.X, vpReal.Y) - screenCenter).Magnitude or math.huge
                if predDist <= math.max(syncTol, 8) or realDist <= syncTol then
                    local valid = IsValidTarget(aimKey, {
                        checkTeam = Config.TriggerBot.TeamCheck,
                        checkVisible = Config.TriggerBot.VisibleCheck,
                        ignoreBots = Config.TriggerBot.IgnoreBots,
                        maxDistance = maxDist,
                        camera = camera,
                        targetPart = aimPart,
                    })
                    if valid then
                        return aimKey, aimEntry, aimPart, predPos
                    end
                end
            end
        end
    end

    -- Pass 3: Crosshair Tolerance + Predicted Lead Sweep
    local tol = Config.TriggerBot.CrosshairTolerance
    local usePredSweep = Config.TriggerBot.SyncWithAimbot and (
        Config.Aimbot.AutoPredict
        or Config.Aimbot.Prediction > 0
        or Config.Aimbot.ProjectileSpeed > 0
        or Config.Aimbot.PingCompensation
    )
    if tol > 0 or usePredSweep then
        local sweepTol = math.max(tol, usePredSweep and 6 or 0)
        local bestKey = nil
        local bestEntry = nil
        local bestPart = nil
        local bestPos = nil
        local bestScreenDist = sweepTol + 0.001

        for targetKey, entry in pairs(Registry) do
            local checkParts
            if Config.TriggerBot.TargetFilter == "Head Only" then
                checkParts = {entry.Head}
            elseif Config.TriggerBot.TargetFilter == "Head & Chest" then
                checkParts = {entry.Head, entry.Torso, entry.RootPart}
            else
                checkParts = (#entry.RigParts > 0) and entry.RigParts or {entry.Head, entry.Torso, entry.RootPart}
            end

            for _, part in ipairs(checkParts) do
                if part and part.Parent and isFiniteVector3(part.Position) then
                    local checkPos = part.Position
                    if entry.Bones and #entry.Bones > 0 and #entry.RigParts <= 2 then
                        local bMode = (Config.TriggerBot.TargetFilter == "Head Only") and "Head" or "Closest"
                        local bonePos = findMatchingBonePosition(entry, bMode, camera, screenCenter, checkPos)
                        if bonePos then
                            checkPos = bonePos
                        end
                    end

                    local sDist = math.huge
                    local matchedPos = checkPos
                    local vp, onScreen = camera:WorldToViewportPoint(checkPos)
                    if vp.Z > 0 and onScreen then
                        sDist = (Vector2.new(vp.X, vp.Y) - screenCenter).Magnitude
                    end

                    if usePredSweep then
                        local worldDist = (checkPos - origin).Magnitude
                        local predPos = computePredictedTargetPoint(entry, part, checkPos, worldDist, dt or (1 / 60))
                        local vpP, onP = camera:WorldToViewportPoint(predPos)
                        if vpP.Z > 0 and onP then
                            local pDist = (Vector2.new(vpP.X, vpP.Y) - screenCenter).Magnitude
                            if pDist < sDist then
                                sDist = pDist
                                matchedPos = predPos
                            end
                        end
                    end

                    if sDist <= bestScreenDist then
                        local valid = IsValidTarget(targetKey, {
                            checkTeam = Config.TriggerBot.TeamCheck,
                            checkVisible = Config.TriggerBot.VisibleCheck,
                            ignoreBots = Config.TriggerBot.IgnoreBots,
                            maxDistance = maxDist,
                            camera = camera,
                            targetPart = part,
                        })
                        if valid then
                            bestScreenDist = sDist
                            bestKey = targetKey
                            bestEntry = entry
                            bestPart = part
                            bestPos = matchedPos
                        end
                    end
                end
            end
        end

        if bestKey then
            return bestKey, bestEntry, bestPart, bestPos or bestPart.Position
        end
    end

    return nil, nil, nil, nil
end

local function updateTriggerBot(camera, screenCenter, now, dt)
    if not Config.TriggerBot.Enabled or not State.LocalAlive then
        State.TriggerTarget = nil
        State.TriggerAcquireTime = 0
        releaseTriggerFire()
        TriggerDot.Visible = false
        return
    end

    if (now - (TriggerEngine.LastScanTime or 0)) >= 2.0 then
        TriggerEngine.LastScanTime = now
        if Config.TriggerBot.Mode == "firesignal" and #TriggerEngine.FireSignalCandidates == 0 then
            TriggerEngine.scanFireSignals()
        elseif Config.TriggerBot.Mode == "Tool:Activate()" and #TriggerEngine.ToolCandidates == 0 then
            TriggerEngine.scanToolCalls()
        end
    end

    local targetPlayer, targetEntry = findTriggerTarget(camera, screenCenter, dt)
    local locked = (targetPlayer ~= nil)

    if Config.TriggerBot.ShowIndicator then
        TriggerDot.Visible = true
        TriggerDot.Position = UDim2.fromOffset(screenCenter.X, screenCenter.Y)
        TriggerDot.BackgroundColor3 = locked and Color3.fromRGB(56, 232, 198) or Color3.fromRGB(251, 146, 60)
        TriggerDot.Size = locked and UDim2.fromOffset(9, 9) or UDim2.fromOffset(6, 6)
    else
        TriggerDot.Visible = false
    end

    if not locked then
        State.TriggerTarget = nil
        State.TriggerAcquireTime = 0
        releaseTriggerFire()
        return
    end

    if State.TriggerTarget ~= targetPlayer then
        State.TriggerTarget = targetPlayer
        State.TriggerAcquireTime = now
    end

    if (now - State.TriggerAcquireTime) < Config.TriggerBot.ReactionDelay then
        return
    end

    if Config.TriggerBot.HoldToFire then
        if not State.TriggerHolding then
            TriggerEngine.dispatchFire(camera, targetEntry, true)
        end
    else
        if (now - State.LastTriggerFire) >= Config.TriggerBot.ShotCooldown then
            State.LastTriggerFire = now
            TriggerEngine.dispatchFire(camera, targetEntry, false)
        end
    end
end

-- ============================================================================
-- [SECTION 8] MAIN RENDER LOOP & EVERY-FRAME PLAYER COVERAGE SYNC
-- ============================================================================
local RENDER_STEP_NAME = "TEAM_AKI_RenderStep"

local function onRenderStepFrame(dt)
    if State.Unloaded then
        return
    end

    State.FrameIndex = State.FrameIndex + 1
    State.LastRenderTick = os.clock()

    local camera = Workspace.CurrentCamera
    State.Camera = camera
    if not camera then
        return
    end

    -- 1.0s periodic full player re-sync/re-render
    local now = State.LastRenderTick
    if (now - State.LastSafetySync) >= SAFETY_SYNC_INTERVAL then
        State.LastSafetySync = now
        pcall(runPeriodicSafetySync)
    end

    -- Detect LocalPlayer teleport (TP) and immediately re-sync all targets
    local localRoot = State.LocalRootPart
    if localRoot and localRoot.Parent then
        local curLocalPos = localRoot.Position
        if State.LastLocalPos and (curLocalPos - State.LastLocalPos).Magnitude >= 35 then
            State.LastLocalPos = curLocalPos
            State.CurrentAimTarget = nil
            pcall(ReloadAllSystems, "LocalTeleportDetected", false)
        else
            State.LastLocalPos = curLocalPos
        end
    end

    -- Fast per-frame player, respawn & teleport guarantee so zero spawned players are ever missed
    local missingInFrame = nil
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local entry = Registry[player]
            if not entry then
                registerPlayerEntry(player)
                entry = Registry[player]
            end
            if entry then
                local allowDeep = (entry.Character == nil) and ((now - entry.LastDeepScan) >= 0.4)
                if allowDeep then
                    entry.LastDeepScan = now
                end
                local liveChar = resolveCharacterForPlayer(player, allowDeep)
                if liveChar and liveChar.Parent then
                    if entry.Character ~= liveChar then
                        bindCharacterToEntry(entry, liveChar)
                    elseif entry.NeedsRescan
                        or (not entry.RootPart)
                        or (not entry.RootPart.Parent)
                        or (#entry.RigParts == 0 and (now - entry.LastScanTime) > 0.25)
                    then
                        entry.NeedsRescan = false
                        cacheCharacterParts(entry, liveChar)
                        attachRemoteHumanoidDeath(entry)
                    elseif entry.RootPart and entry.RootPart.Parent then
                        local curPos = entry.RootPart.Position
                        if entry.LastKnownWorldPos and (curPos - entry.LastKnownWorldPos).Magnitude >= 35 then
                            entry.LastKnownWorldPos = curPos
                            entry.EstimatedVel = Vector3.zero
                            entry.LastTrackedPos = nil
                            entry.FrameVisualCache = nil
                            cacheCharacterParts(entry, liveChar)
                            ScheduleReload("RemoteTeleport:" .. player.Name, false)
                        else
                            entry.LastKnownWorldPos = curPos
                        end
                    end
                else
                    if entry.Character ~= nil then
                        clearCharacterFromEntry(entry)
                    end
                    if not missingInFrame then
                        missingInFrame = {}
                    end
                    table.insert(missingInFrame, player)
                end
            end
        end
    end

    if missingInFrame and (now - (State.LastWorkspaceDeepScan or 0)) >= 0.75 then
        State.LastWorkspaceDeepScan = now
        local recovered = deepWorkspaceScanForMissingPlayers(missingInFrame)
        for plr, liveChar in pairs(recovered) do
            local entry = Registry[plr]
            if entry and liveChar and liveChar.Parent then
                bindCharacterToEntry(entry, liveChar)
            end
        end
    end

    if (now - (State.LastBotScan or 0)) >= 0.5 then
        State.LastBotScan = now
        pcall(syncWorkspaceBots, nil)
    end

    local viewportSize = camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)

    local showFov = Config.Aimbot.ShowFOV
    local useDrawingFov = shouldUseDrawing() and DrawingFOV ~= nil

    if DrawingFOV then
        pcall(function()
            DrawingFOV.Visible = showFov and useDrawingFov
            if showFov and useDrawingFov then
                local fovT, fovOp = VisualHelper.resolveDrawingThickness(Config.Aimbot.FOVThickness, Config.Aimbot.Enabled and 0.92 or 0.65)
                DrawingFOV.Position = screenCenter
                DrawingFOV.Radius = Config.Aimbot.FOVRadius
                DrawingFOV.Thickness = fovT
                DrawingFOV.Color = Config.Colors.FOV
                DrawingFOV.Transparency = fovOp
            end
        end)
    end

    FOVRingFrame.Visible = showFov and (not useDrawingFov)
    if FOVRingFrame.Visible then
        local diameter = Config.Aimbot.FOVRadius * 2
        local strokeT, strokeTrans = VisualHelper.resolveStrokeThickness(Config.Aimbot.FOVThickness, Config.Aimbot.Enabled and 0.14 or 0.44)
        FOVRingFrame.Size = UDim2.fromOffset(diameter, diameter)
        FOVStroke.Color = Config.Colors.FOV
        FOVStroke.Thickness = strokeT
        FOVStroke.Transparency = strokeTrans
    end

    -- Keep LocalAlive synced immediately on respawn before 1.0s periodic reload
    local liveLocalChar = LocalPlayer.Character
    if liveLocalChar and liveLocalChar.Parent and State.LocalCharacter ~= liveLocalChar then
        bindLocalCharacter(liveLocalChar)
    end

    updateAimbot(camera, screenCenter, dt)
    updateTriggerBot(camera, screenCenter, now, dt)
    updateAllESP(camera, viewportSize, screenCenter)
end

local function isCharacterOrHudDescendant(inst)
    local cur = inst
    while cur and cur ~= Workspace do
        if cur:IsA("Model") and (cur:FindFirstChildOfClass("Humanoid") or Players:GetPlayerFromCharacter(cur) ~= nil) then
            return true
        end
        cur = cur.Parent
    end
    return false
end

local function potatoOptimizeInstance(inst, saved)
    if not inst or not inst.Parent then
        return
    end
    if inst:IsA("BasePart") and not inst:IsA("Terrain") then
        if not isCharacterOrHudDescendant(inst) then
            if not saved.Parts[inst] then
                saved.Parts[inst] = {
                    Material = inst.Material,
                    CastShadow = inst.CastShadow,
                    Reflectance = inst.Reflectance,
                }
            end
            pcall(function()
                inst.Material = Enum.Material.SmoothPlastic
                inst.CastShadow = false
                inst.Reflectance = 0
            end)
        else
            pcall(function()
                inst.CastShadow = false
            end)
        end
    elseif inst:IsA("Decal") or inst:IsA("Texture") then
        if not isCharacterOrHudDescendant(inst) then
            if saved.Decals[inst] == nil then
                saved.Decals[inst] = inst.Transparency
            end
            pcall(function()
                inst.Transparency = 1
            end)
        end
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire") or inst:IsA("Smoke") or inst:IsA("Sparkles") then
        if saved.Particles[inst] == nil then
            saved.Particles[inst] = inst.Enabled
        end
        pcall(function()
            inst.Enabled = false
        end)
    elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
        if saved.Lights[inst] == nil then
            saved.Lights[inst] = inst.Enabled
        end
        pcall(function()
            inst.Enabled = false
        end)
    elseif inst:IsA("Explosion") then
        pcall(function()
            inst.Visible = false
        end)
    elseif inst:IsA("PostEffect") or inst:IsA("Clouds") then
        if saved.Effects[inst] == nil then
            saved.Effects[inst] = inst.Enabled
        end
        pcall(function()
            inst.Enabled = false
        end)
    elseif inst:IsA("Atmosphere") then
        if saved.Atmospheres[inst] == nil then
            saved.Atmospheres[inst] = {
                Density = inst.Density,
                Glare = inst.Glare,
                Haze = inst.Haze,
            }
        end
        pcall(function()
            inst.Density = 0
            inst.Glare = 0
            inst.Haze = 0
        end)
    end
end

local function applyPotatoGraphics(enabled)
    Config.Performance.PotatoGraphics = enabled == true
    if enabled then
        if not State.SavedGraphics then
            local saved = {
                QualityLevel = nil,
                MeshDetail = nil,
                GlobalShadows = nil,
                ShadowSoftness = nil,
                EnvDiffuse = nil,
                EnvSpecular = nil,
                FogEnd = nil,
                Terrain = nil,
                Effects = {},
                Atmospheres = {},
                Lights = {},
                Parts = {},
                Decals = {},
                Particles = {},
            }
            pcall(function()
                if type(settings) == "function" then
                    local renderSettings = settings().Rendering
                    saved.QualityLevel = renderSettings.QualityLevel
                    pcall(function()
                        saved.MeshDetail = renderSettings.MeshPartDetailLevel
                    end)
                end
            end)
            if Lighting then
                pcall(function()
                    saved.GlobalShadows = Lighting.GlobalShadows
                    saved.ShadowSoftness = Lighting.ShadowSoftness
                    saved.FogEnd = Lighting.FogEnd
                    pcall(function()
                        saved.EnvDiffuse = Lighting.EnvironmentDiffuseScale
                        saved.EnvSpecular = Lighting.EnvironmentSpecularScale
                    end)
                end)
            end
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                pcall(function()
                    saved.Terrain = {
                        Ref = terrain,
                        WaterWaveSize = terrain.WaterWaveSize,
                        WaterWaveSpeed = terrain.WaterWaveSpeed,
                        WaterReflectance = terrain.WaterReflectance,
                        WaterTransparency = terrain.WaterTransparency,
                        Decoration = terrain.Decoration,
                    }
                end)
            end
            State.SavedGraphics = saved
        end

        local saved = State.SavedGraphics
        pcall(function()
            if type(settings) == "function" then
                local rs = settings().Rendering
                rs.QualityLevel = Enum.QualityLevel.Level01
                pcall(function()
                    rs.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level01
                end)
            end
        end)
        if Lighting then
            pcall(function()
                Lighting.GlobalShadows = false
                Lighting.ShadowSoftness = 0
                Lighting.FogEnd = 999999
                pcall(function()
                    Lighting.EnvironmentDiffuseScale = 0
                    Lighting.EnvironmentSpecularScale = 0
                end)
            end)
            for _, desc in ipairs(Lighting:GetDescendants()) do
                potatoOptimizeInstance(desc, saved)
            end
        end
        local terrain = Workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            pcall(function()
                terrain.WaterWaveSize = 0
                terrain.WaterWaveSpeed = 0
                terrain.WaterReflectance = 0
                terrain.WaterTransparency = 1
                terrain.Decoration = false
            end)
            for _, desc in ipairs(terrain:GetChildren()) do
                potatoOptimizeInstance(desc, saved)
            end
        end

        task.spawn(function()
            local count = 0
            for _, desc in ipairs(Workspace:GetDescendants()) do
                if not Config.Performance.PotatoGraphics or State.Unloaded then
                    break
                end
                potatoOptimizeInstance(desc, saved)
                count = count + 1
                if count % 350 == 0 then
                    task.wait()
                end
            end
        end)

        if not State.PotatoDescConn then
            State.PotatoDescConn = Workspace.DescendantAdded:Connect(function(desc)
                if Config.Performance.PotatoGraphics and not State.Unloaded and State.SavedGraphics then
                    potatoOptimizeInstance(desc, State.SavedGraphics)
                end
            end)
        end
    else
        if State.PotatoDescConn then
            pcall(function()
                State.PotatoDescConn:Disconnect()
            end)
            State.PotatoDescConn = nil
        end

        local saved = State.SavedGraphics
        if saved then
            pcall(function()
                if type(settings) == "function" then
                    local rs = settings().Rendering
                    if saved.QualityLevel ~= nil then
                        rs.QualityLevel = saved.QualityLevel
                    end
                    if saved.MeshDetail ~= nil then
                        pcall(function()
                            rs.MeshPartDetailLevel = saved.MeshDetail
                        end)
                    end
                end
            end)
            if Lighting then
                pcall(function()
                    if saved.GlobalShadows ~= nil then Lighting.GlobalShadows = saved.GlobalShadows end
                    if saved.ShadowSoftness ~= nil then Lighting.ShadowSoftness = saved.ShadowSoftness end
                    if saved.FogEnd ~= nil then Lighting.FogEnd = saved.FogEnd end
                    pcall(function()
                        if saved.EnvDiffuse ~= nil then Lighting.EnvironmentDiffuseScale = saved.EnvDiffuse end
                        if saved.EnvSpecular ~= nil then Lighting.EnvironmentSpecularScale = saved.EnvSpecular end
                    end)
                end)
            end
            if saved.Terrain and saved.Terrain.Ref and saved.Terrain.Ref.Parent then
                pcall(function()
                    local t = saved.Terrain.Ref
                    t.WaterWaveSize = saved.Terrain.WaterWaveSize
                    t.WaterWaveSpeed = saved.Terrain.WaterWaveSpeed
                    t.WaterReflectance = saved.Terrain.WaterReflectance
                    t.WaterTransparency = saved.Terrain.WaterTransparency
                    t.Decoration = saved.Terrain.Decoration
                end)
            end
            for inst, wasEnabled in pairs(saved.Effects) do
                if inst and inst.Parent then pcall(function() inst.Enabled = wasEnabled end) end
            end
            for inst, props in pairs(saved.Atmospheres) do
                if inst and inst.Parent then
                    pcall(function()
                        inst.Density = props.Density
                        inst.Glare = props.Glare
                        inst.Haze = props.Haze
                    end)
                end
            end
            for inst, wasEnabled in pairs(saved.Lights) do
                if inst and inst.Parent then pcall(function() inst.Enabled = wasEnabled end) end
            end
            for inst, wasEnabled in pairs(saved.Particles) do
                if inst and inst.Parent then pcall(function() inst.Enabled = wasEnabled end) end
            end
            for inst, origTrans in pairs(saved.Decals) do
                if inst and inst.Parent then pcall(function() inst.Transparency = origTrans end) end
            end
            for inst, props in pairs(saved.Parts) do
                if inst and inst.Parent then
                    pcall(function()
                        inst.Material = props.Material
                        inst.CastShadow = props.CastShadow
                        inst.Reflectance = props.Reflectance
                    end)
                end
            end
            State.SavedGraphics = nil
        end
    end
end

if Config.Performance.PotatoGraphics then
    task.defer(function()
        if not State.Unloaded and Config.Performance.PotatoGraphics then
            applyPotatoGraphics(true)
        end
    end)
end

local function applyThicknessImmediate()
    local st, strans = VisualHelper.resolveStrokeThickness(Config.Aimbot.FOVThickness, Config.Aimbot.Enabled and 0.14 or 0.44)
    FOVStroke.Thickness = st
    FOVStroke.Transparency = strans
    if DrawingFOV then
        pcall(function()
            local fovT, fovOp = VisualHelper.resolveDrawingThickness(Config.Aimbot.FOVThickness, Config.Aimbot.Enabled and 0.92 or 0.65)
            DrawingFOV.Thickness = fovT
            DrawingFOV.Transparency = fovOp
        end)
    end
    local cam = State.Camera or Workspace.CurrentCamera
    if cam then
        local vp = cam.ViewportSize
        pcall(updateAllESP, cam, vp, Vector2.new(vp.X * 0.5, vp.Y * 0.5))
    end
end

local function bindMainRenderLoop()
    pcall(function()
        RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
    end)
    RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 50, function(dt)
        pcall(onRenderStepFrame, dt)
    end)
end

State.LastRenderTick = os.clock()
bindMainRenderLoop()

-- Heartbeat watchdog: guarantees RenderStep & 1.0s full sync NEVER stop after death/respawn/TP
addConnection(RunService.Heartbeat:Connect(function()
    if State.Unloaded then
        return
    end
    local now = os.clock()
    if (now - State.LastRenderTick) >= 0.5 then
        State.LastRenderTick = now
        bindMainRenderLoop()
    end
    if (now - State.LastSafetySync) >= SAFETY_SYNC_INTERVAL then
        State.LastSafetySync = now
        pcall(runPeriodicSafetySync)
    end
end))

-- ============================================================================
-- [SECTION 9] ADAPTIVE LIQUID-GLASS UI SHELL & STARTUP LOADER (TEAM AKI)
-- ============================================================================
local MainGui = Instance.new("ScreenGui")
MainGui.Name = "TEAM_AKI_Hub"
MainGui.IgnoreGuiInset = true
MainGui.ResetOnSpawn = false
MainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
MainGui.DisplayOrder = 1000
protectGui(MainGui)
mountGuiSafely(MainGui)
State.MainGui = MainGui

local UI = {}
UI.syncVimPointer = function() end
UI.refreshTriggerControls = function() end
UI.clampPanelToViewport = function() end

local Palette = {
    GlassBase = Color3.fromRGB(12, 16, 26),
    CardElevated = Color3.fromRGB(22, 30, 48),
    SurfaceSoft = Color3.fromRGB(38, 50, 78),
    GlassEdge = Color3.fromRGB(165, 212, 255),
    GlassSpecular = Color3.fromRGB(235, 246, 255),
    PrimaryAccent = Color3.fromRGB(88, 164, 255),
    ActiveGlow = Color3.fromRGB(56, 232, 198),
    TextHeader = Color3.fromRGB(246, 249, 255),
    TextSilver = Color3.fromRGB(184, 196, 222),
    ToggleOff = Color3.fromRGB(52, 66, 94),
    Danger = Color3.fromRGB(244, 63, 94),
    Amber = Color3.fromRGB(251, 146, 60),
}

local function tween(obj, duration, props)
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local function applyGlassStroke(target, thickness, transparency, color)
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = thickness or 1.15
    stroke.Transparency = transparency or 0.58
    stroke.Color = color or Palette.GlassEdge
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = target

    local edgeGrad = Instance.new("UIGradient")
    edgeGrad.Rotation = 42
    edgeGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.0),
        NumberSequenceKeypoint.new(0.42, 0.42),
        NumberSequenceKeypoint.new(1, 0.80),
    })
    edgeGrad.Parent = stroke

    return stroke
end

function UI.applyFrostedSurface(target, cornerRadius, bgColor, bgTransparency, strokeTransparency, addInnerSheen)
    target.BackgroundColor3 = bgColor or Palette.CardElevated
    target.BackgroundTransparency = bgTransparency or 0.58
    target.BorderSizePixel = 0

    local corner = Instance.new("UICorner")
    corner.CornerRadius = (cornerRadius == -1) and UDim.new(1, 0) or UDim.new(0, cornerRadius or 14)
    corner.Parent = target

    local stroke = applyGlassStroke(target, 1.1, strokeTransparency or 0.62, Palette.GlassEdge)

    if addInnerSheen ~= false then
        local sheen = Instance.new("UIGradient")
        sheen.Rotation = 135
        sheen.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
            ColorSequenceKeypoint.new(0.55, Color3.fromRGB(214, 228, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(186, 212, 250)),
        })
        sheen.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.0),
            NumberSequenceKeypoint.new(0.5, 0.18),
            NumberSequenceKeypoint.new(1, 0.06),
        })
        sheen.Parent = target
    end

    return stroke
end

local RootScale = Instance.new("UIScale")
RootScale.Parent = MainGui

local BASE_CARD_W = 508
local BASE_CARD_H = 458

local CardShadow = Instance.new("Frame")
CardShadow.Name = "CardShadow"
CardShadow.AnchorPoint = Vector2.new(0.5, 0.5)
CardShadow.Position = UDim2.new(0.5, 0, 0.5, 10)
CardShadow.Size = UDim2.fromOffset(BASE_CARD_W + 26, BASE_CARD_H + 26)
CardShadow.BackgroundColor3 = Color3.fromRGB(3, 6, 14)
CardShadow.BackgroundTransparency = 0.68
CardShadow.BorderSizePixel = 0
CardShadow.Active = false
CardShadow.Visible = false
CardShadow.ZIndex = 1
CardShadow.Parent = MainGui

local MainCard = Instance.new("Frame")
MainCard.Name = "MainCard"
MainCard.AnchorPoint = Vector2.new(0.5, 0.5)
MainCard.Position = UDim2.fromScale(0.5, 0.5)
MainCard.Size = UDim2.fromOffset(BASE_CARD_W, BASE_CARD_H)
MainCard.BackgroundColor3 = Palette.GlassBase
MainCard.BackgroundTransparency = 0.38
MainCard.BorderSizePixel = 0
MainCard.ClipsDescendants = true
MainCard.Active = true
MainCard.Draggable = false
MainCard.Visible = false
MainCard.ZIndex = 2
MainCard.Parent = MainGui
State.MainCard = MainCard

do
    local mainAspect = Instance.new("UIAspectRatioConstraint")
    mainAspect.AspectRatio = BASE_CARD_W / BASE_CARD_H
    mainAspect.AspectType = Enum.AspectType.ScaleWithParentSize
    mainAspect.DominantAxis = Enum.DominantAxis.Width
    mainAspect.Parent = MainCard

    local shadowAspect = Instance.new("UIAspectRatioConstraint")
    shadowAspect.AspectRatio = (BASE_CARD_W + 26) / (BASE_CARD_H + 26)
    shadowAspect.AspectType = Enum.AspectType.ScaleWithParentSize
    shadowAspect.DominantAxis = Enum.DominantAxis.Width
    shadowAspect.Parent = CardShadow

    local shadowCorner = Instance.new("UICorner")
    shadowCorner.CornerRadius = UDim.new(0, 30)
    shadowCorner.Parent = CardShadow

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 24)
    mainCorner.Parent = MainCard

    applyGlassStroke(MainCard, 1.4, 0.46, Palette.GlassEdge)

    local glassGradient = Instance.new("UIGradient")
    glassGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 44, 72)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(13, 18, 30)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 32, 54)),
    })
    glassGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.04),
        NumberSequenceKeypoint.new(0.52, 0.18),
        NumberSequenceKeypoint.new(1, 0.08),
    })
    glassGradient.Rotation = 135
    glassGradient.Parent = MainCard

    local innerRim = Instance.new("Frame")
    innerRim.Name = "InnerGlassRim"
    innerRim.AnchorPoint = Vector2.new(0.5, 0.5)
    innerRim.Position = UDim2.fromScale(0.5, 0.5)
    innerRim.Size = UDim2.new(1, -2, 1, -2)
    innerRim.BackgroundTransparency = 1
    innerRim.BorderSizePixel = 0
    innerRim.ZIndex = 2
    innerRim.Parent = MainCard

    local innerRimCorner = Instance.new("UICorner")
    innerRimCorner.CornerRadius = UDim.new(0, 23)
    innerRimCorner.Parent = innerRim
    applyGlassStroke(innerRim, 1, 0.76, Palette.GlassSpecular)

    local frostedOverlay = Instance.new("Frame")
    frostedOverlay.Name = "FrostedOverlay"
    frostedOverlay.AnchorPoint = Vector2.new(0.5, 0)
    frostedOverlay.Position = UDim2.new(0.5, 0, 0, -56)
    frostedOverlay.Size = UDim2.new(0.90, 0, 0, 114)
    frostedOverlay.BackgroundColor3 = Color3.fromRGB(185, 224, 255)
    frostedOverlay.BackgroundTransparency = 0.88
    frostedOverlay.BorderSizePixel = 0
    frostedOverlay.ZIndex = 2
    frostedOverlay.Parent = MainCard

    local frostCorner = Instance.new("UICorner")
    frostCorner.CornerRadius = UDim.new(1, 0)
    frostCorner.Parent = frostedOverlay

    local bottomSheen = Instance.new("Frame")
    bottomSheen.Name = "BottomSheen"
    bottomSheen.AnchorPoint = Vector2.new(0.5, 1)
    bottomSheen.Position = UDim2.new(0.5, 0, 1, 48)
    bottomSheen.Size = UDim2.new(0.78, 0, 0, 92)
    bottomSheen.BackgroundColor3 = Palette.ActiveGlow
    bottomSheen.BackgroundTransparency = 0.91
    bottomSheen.BorderSizePixel = 0
    bottomSheen.ZIndex = 2
    bottomSheen.Parent = MainCard

    local sheenCorner = Instance.new("UICorner")
    sheenCorner.CornerRadius = UDim.new(1, 0)
    sheenCorner.Parent = bottomSheen
end

do
    local function clampPanelToViewport()
        local cam = Workspace.CurrentCamera
        if not cam then
            return
        end
        local scale = math.max(RootScale.Scale, 0.5)
        local vp = cam.ViewportSize / scale
        local halfW = BASE_CARD_W * 0.5
        local halfH = BASE_CARD_H * 0.5
        local maxX = math.max((vp.X * 0.5) - halfW + 40, 20)
        local maxY = math.max((vp.Y * 0.5) - halfH + 40, 20)
        local pos = MainCard.Position
        local cx = math.clamp(pos.X.Offset, -maxX, maxX)
        local cy = math.clamp(pos.Y.Offset, -maxY, maxY)
        MainCard.Position = UDim2.new(0.5, cx, 0.5, cy)
        CardShadow.Position = UDim2.new(0.5, cx, 0.5, cy + 10)
    end
    UI.clampPanelToViewport = clampPanelToViewport

    local function updateResponsiveLayout()
        local cam = Workspace.CurrentCamera
        if not cam then
            return
        end
        local vp = cam.ViewportSize
        local maxScaleX = (vp.X * 0.92) / BASE_CARD_W
        local maxScaleY = (vp.Y * 0.86) / BASE_CARD_H
        local scale = math.clamp(math.min(maxScaleX, maxScaleY), 0.56, 1.15)
        RootScale.Scale = scale
        if UI.LoaderScale then
            UI.LoaderScale.Scale = scale
        end
        clampPanelToViewport()
        pcall(UI.syncVimPointer)
    end

    local viewportConn = nil
    local function bindCameraViewport()
        if viewportConn then
            pcall(function()
                viewportConn:Disconnect()
            end)
            viewportConn = nil
        end
        local cam = Workspace.CurrentCamera
        State.Camera = cam
        if cam then
            viewportConn = addConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout))
        end
        updateResponsiveLayout()
    end

    UI.updateResponsiveLayout = updateResponsiveLayout
    bindCameraViewport()
    addConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport))
end

-- Startup Loading Splash (Saki Liquid-Glass Sequence)
function UI.runStartupLoader(onComplete)
    local loaderGui = Instance.new("ScreenGui")
    loaderGui.Name = "TEAM_AKI_Loader"
    loaderGui.IgnoreGuiInset = true
    loaderGui.ResetOnSpawn = false
    loaderGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    loaderGui.DisplayOrder = 1050
    protectGui(loaderGui)
    mountGuiSafely(loaderGui)
    UI.LoaderGui = loaderGui

    local loaderScale = Instance.new("UIScale")
    loaderScale.Scale = RootScale.Scale
    loaderScale.Parent = loaderGui
    UI.LoaderScale = loaderScale

    local loaderCard = Instance.new("Frame")
    loaderCard.Name = "LoaderCard"
    loaderCard.AnchorPoint = Vector2.new(0.5, 0.5)
    loaderCard.Position = UDim2.fromScale(0.5, 0.5)
    loaderCard.Size = UDim2.fromOffset(336, 158)
    loaderCard.BackgroundColor3 = Palette.GlassBase
    loaderCard.BackgroundTransparency = 0.30
    loaderCard.BorderSizePixel = 0
    loaderCard.ClipsDescendants = true
    loaderCard.Parent = loaderGui

    local loaderAspect = Instance.new("UIAspectRatioConstraint")
    loaderAspect.AspectRatio = 336 / 158
    loaderAspect.AspectType = Enum.AspectType.ScaleWithParentSize
    loaderAspect.Parent = loaderCard

    local lc = Instance.new("UICorner")
    lc.CornerRadius = UDim.new(0, 22)
    lc.Parent = loaderCard
    applyGlassStroke(loaderCard, 1.35, 0.44, Palette.GlassEdge)

    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 46, 74)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(14, 19, 32)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 34, 56)),
    })
    grad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.5, 0.16),
        NumberSequenceKeypoint.new(1, 0.08),
    })
    grad.Rotation = 135
    grad.Parent = loaderCard

    local loaderRim = Instance.new("Frame")
    loaderRim.AnchorPoint = Vector2.new(0.5, 0.5)
    loaderRim.Position = UDim2.fromScale(0.5, 0.5)
    loaderRim.Size = UDim2.new(1, -2, 1, -2)
    loaderRim.BackgroundTransparency = 1
    loaderRim.BorderSizePixel = 0
    loaderRim.Parent = loaderCard
    local lrc = Instance.new("UICorner")
    lrc.CornerRadius = UDim.new(0, 21)
    lrc.Parent = loaderRim
    applyGlassStroke(loaderRim, 1, 0.78, Palette.GlassSpecular)

    local badge = Instance.new("TextLabel")
    badge.BackgroundTransparency = 1
    badge.Position = UDim2.fromOffset(22, 22)
    badge.Size = UDim2.new(1, -44, 0, 26)
    badge.Font = Enum.Font.GothamBold
    badge.Text = "TEAM AKI"
    badge.TextSize = 20
    badge.TextColor3 = Palette.TextHeader
    badge.TextXAlignment = Enum.TextXAlignment.Left
    badge.Parent = loaderCard

    local sub = Instance.new("TextLabel")
    sub.BackgroundTransparency = 1
    sub.Position = UDim2.fromOffset(22, 50)
    sub.Size = UDim2.new(1, -44, 0, 16)
    sub.Font = Enum.Font.GothamMedium
    sub.Text = "Mobile Liquid-Glass Tactical Suite"
    sub.TextSize = 11.5
    sub.TextColor3 = Palette.ActiveGlow
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = loaderCard

    local statusLbl = Instance.new("TextLabel")
    statusLbl.BackgroundTransparency = 1
    statusLbl.Position = UDim2.fromOffset(22, 86)
    statusLbl.Size = UDim2.new(1, -92, 0, 16)
    statusLbl.Font = Enum.Font.Gotham
    statusLbl.Text = "Loading per-game profile..."
    statusLbl.TextSize = 11
    statusLbl.TextColor3 = Palette.TextSilver
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.TextTruncate = Enum.TextTruncate.AtEnd
    statusLbl.Parent = loaderCard

    local pctLbl = Instance.new("TextLabel")
    pctLbl.BackgroundTransparency = 1
    pctLbl.AnchorPoint = Vector2.new(1, 0)
    pctLbl.Position = UDim2.new(1, -22, 0, 86)
    pctLbl.Size = UDim2.fromOffset(56, 16)
    pctLbl.Font = Enum.Font.Code
    pctLbl.Text = "0%"
    pctLbl.TextSize = 11.5
    pctLbl.TextColor3 = Palette.TextHeader
    pctLbl.TextXAlignment = Enum.TextXAlignment.Right
    pctLbl.Parent = loaderCard

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0.5, 0)
    track.Position = UDim2.new(0.5, 0, 0, 114)
    track.Size = UDim2.new(1, -44, 0, 9)
    track.BackgroundColor3 = Palette.ToggleOff
    track.BackgroundTransparency = 0.40
    track.BorderSizePixel = 0
    track.Parent = loaderCard

    local tc = Instance.new("UICorner")
    tc.CornerRadius = UDim.new(1, 0)
    tc.Parent = track
    applyGlassStroke(track, 1, 0.74, Palette.GlassEdge)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0.04, 1)
    fill.BackgroundColor3 = Palette.ActiveGlow
    fill.BorderSizePixel = 0
    fill.Parent = track

    local fc = Instance.new("UICorner")
    fc.CornerRadius = UDim.new(1, 0)
    fc.Parent = fill

    local fillGrad = Instance.new("UIGradient")
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Palette.PrimaryAccent),
        ColorSequenceKeypoint.new(1, Palette.ActiveGlow),
    })
    fillGrad.Parent = fill

    task.spawn(function()
        local stages = {
            { Ratio = 0.34, Pct = "34%", Text = "Syncing " .. (State.ConfigStatusText or "profile") .. "...", Wait = 0.24 },
            { Ratio = 0.72, Pct = "72%", Text = "Scanning fire signals & rig resolvers...", Wait = 0.28 },
            { Ratio = 1.00, Pct = "100%", Text = "Ready — Liquid-Glass Engine Online", Wait = 0.26 },
        }
        for _, st in ipairs(stages) do
            if State.Unloaded or not loaderGui.Parent then
                return
            end
            statusLbl.Text = st.Text
            pctLbl.Text = st.Pct
            tween(fill, 0.22, { Size = UDim2.fromScale(st.Ratio, 1) })
            task.wait(st.Wait)
        end
        if State.Unloaded or not loaderGui.Parent then
            return
        end
        tween(loaderCard, 0.20, {
            Size = UDim2.fromOffset(312, 144),
            BackgroundTransparency = 0.92,
        })
        task.wait(0.22)
        pcall(function()
            loaderGui:Destroy()
        end)
        UI.LoaderGui = nil
        UI.LoaderScale = nil
        if not State.Unloaded and onComplete then
            onComplete()
        end
    end)
end

do
    local headerBar = Instance.new("Frame")
    headerBar.Name = "HeaderBar"
    headerBar.AnchorPoint = Vector2.new(0.5, 0)
    headerBar.Position = UDim2.new(0.5, 0, 0, 10)
    headerBar.Size = UDim2.new(1, -24, 0, 52)
    headerBar.Active = true
    headerBar.Draggable = false
    headerBar.ZIndex = 3
    headerBar.Parent = MainCard
    UI.applyFrostedSurface(headerBar, 16, Palette.CardElevated, 0.52, 0.56)

    local headerDivider = Instance.new("Frame")
    headerDivider.AnchorPoint = Vector2.new(0.5, 1)
    headerDivider.Size = UDim2.new(1, -28, 0, 1)
    headerDivider.Position = UDim2.new(0.5, 0, 1, -1)
    headerDivider.BackgroundColor3 = Palette.GlassSpecular
    headerDivider.BackgroundTransparency = 0.82
    headerDivider.BorderSizePixel = 0
    headerDivider.Parent = headerBar

    local dividerCorner = Instance.new("UICorner")
    dividerCorner.CornerRadius = UDim.new(1, 0)
    dividerCorner.Parent = headerDivider

    local brandBadge = Instance.new("Frame")
    brandBadge.AnchorPoint = Vector2.new(0, 0.5)
    brandBadge.Position = UDim2.new(0, 12, 0.5, 0)
    brandBadge.Size = UDim2.fromOffset(94, 30)
    brandBadge.BackgroundColor3 = Palette.PrimaryAccent
    brandBadge.BackgroundTransparency = 0.68
    brandBadge.BorderSizePixel = 0
    brandBadge.ZIndex = 4
    brandBadge.Parent = headerBar

    local brandCorner = Instance.new("UICorner")
    brandCorner.CornerRadius = UDim.new(0, 10)
    brandCorner.Parent = brandBadge

    local brandStroke = Instance.new("UIStroke")
    brandStroke.Thickness = 1.1
    brandStroke.Transparency = 0.34
    brandStroke.Color = Palette.ActiveGlow
    brandStroke.Parent = brandBadge

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "BrandTitle"
    titleLabel.BackgroundTransparency = 1
    titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    titleLabel.Position = UDim2.fromScale(0.5, 0.5)
    titleLabel.Size = UDim2.fromScale(1, 1)
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.Text = "TEAM AKI"
    titleLabel.TextSize = 14
    titleLabel.TextColor3 = Palette.TextHeader
    titleLabel.ZIndex = 5
    titleLabel.Parent = brandBadge

    local subtitleLabel = Instance.new("TextLabel")
    subtitleLabel.Name = "BrandSubtitle"
    subtitleLabel.BackgroundTransparency = 1
    subtitleLabel.AnchorPoint = Vector2.new(0, 0.5)
    subtitleLabel.Position = UDim2.new(0, 114, 0.5, 0)
    subtitleLabel.Size = UDim2.new(1, -200, 0, 18)
    subtitleLabel.Font = Enum.Font.GothamMedium
    subtitleLabel.Text = "Liquid-Glass Tactical Suite"
    subtitleLabel.TextSize = 11.5
    subtitleLabel.TextColor3 = Palette.TextSilver
    subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    subtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
    subtitleLabel.ZIndex = 4
    subtitleLabel.Parent = headerBar

    local headerActions = Instance.new("Frame")
    headerActions.BackgroundTransparency = 1
    headerActions.AnchorPoint = Vector2.new(1, 0.5)
    headerActions.Position = UDim2.new(1, -10, 0.5, 0)
    headerActions.Size = UDim2.fromOffset(74, 32)
    headerActions.ZIndex = 4
    headerActions.Parent = headerBar

    local headerActionsLayout = Instance.new("UIListLayout")
    headerActionsLayout.FillDirection = Enum.FillDirection.Horizontal
    headerActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    headerActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    headerActionsLayout.Padding = UDim.new(0, 8)
    headerActionsLayout.Parent = headerActions

    local function createHeaderButton(symbol, bg, trans)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(32, 32)
        btn.BackgroundColor3 = bg
        btn.BackgroundTransparency = trans or 0.40
        btn.Font = Enum.Font.GothamBold
        btn.Text = symbol
        btn.TextSize = 15
        btn.TextColor3 = Palette.TextHeader
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.ZIndex = 5
        btn.Parent = headerActions

        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, 10)
        c.Parent = btn

        applyGlassStroke(btn, 1, 0.56, Palette.GlassEdge)
        return btn
    end

    UI.MinimizeBtn = createHeaderButton("-", Palette.SurfaceSoft, 0.42)
    UI.UnloadHeaderBtn = createHeaderButton("×", Palette.Danger, 0.34)

    local activeInput = nil
    local dragStart = nil
    local startPos = nil

    local function clearHeaderDrag()
        activeInput = nil
        dragStart = nil
        startPos = nil
        InputGuard.endDrag(headerBar)
    end

    headerBar.InputBegan:Connect(function(input)
        if activeInput or not MainCard.Visible then
            return
        end
        if input.UserInputState ~= Enum.UserInputState.Begin then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if not InputGuard.isPointInGui(headerBar, input.Position, 4) then
            return
        end
        if InputGuard.isPointInGui(UI.MinimizeBtn, input.Position, 2) or InputGuard.isPointInGui(UI.UnloadHeaderBtn, input.Position, 2) then
            return
        end
        if InputGuard.beginDrag(headerBar, input) then
            activeInput = input
            dragStart = input.Position
            startPos = MainCard.Position
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not activeInput or not dragStart or not startPos then
            return
        end
        if not MainCard.Visible then
            clearHeaderDrag()
            return
        end
        if not InputGuard.isOwner(headerBar, input) then
            if not InputGuard.isActiveState(activeInput.UserInputState) then
                clearHeaderDrag()
            end
            return
        end
        local scale = math.max(RootScale.Scale, 0.5)
        local delta = (input.Position - dragStart) / scale
        local nextPos = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
        MainCard.Position = nextPos
        CardShadow.Position = UDim2.new(
            nextPos.X.Scale,
            nextPos.X.Offset,
            nextPos.Y.Scale,
            nextPos.Y.Offset + 10
        )
        UI.clampPanelToViewport()
    end))

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if activeInput and (input == activeInput or not InputGuard.isActiveState(activeInput.UserInputState)) then
            clearHeaderDrag()
        end
    end))

    addConnection(UserInputService.TouchEnded:Connect(function(input)
        if activeInput and (input == activeInput or not InputGuard.isActiveState(activeInput.UserInputState)) then
            clearHeaderDrag()
        end
    end))

    addConnection(MainCard:GetPropertyChangedSignal("Visible"):Connect(function()
        if not MainCard.Visible and activeInput then
            clearHeaderDrag()
        end
    end))
end

local TabPages = {}
local TabButtons = {}

do
    local tabBar = Instance.new("Frame")
    tabBar.Name = "TabBar"
    tabBar.AnchorPoint = Vector2.new(0.5, 0)
    tabBar.Position = UDim2.new(0.5, 0, 0, 70)
    tabBar.Size = UDim2.new(1, -24, 0, 40)
    tabBar.ZIndex = 3
    tabBar.Parent = MainCard
    UI.applyFrostedSurface(tabBar, 14, Palette.CardElevated, 0.56, 0.58)

    local tabPadding = Instance.new("UIPadding")
    tabPadding.PaddingLeft = UDim.new(0, 4)
    tabPadding.PaddingRight = UDim.new(0, 4)
    tabPadding.PaddingTop = UDim.new(0, 4)
    tabPadding.PaddingBottom = UDim.new(0, 4)
    tabPadding.Parent = tabBar

    local tabOrder = {"Aimbot", "Trigger", "ESP", "Colors", "Settings"}

    local tabGrid = Instance.new("UIGridLayout")
    tabGrid.CellSize = UDim2.new(1 / #tabOrder, -4, 1, 0)
    tabGrid.CellPadding = UDim2.fromOffset(4, 0)
    tabGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    tabGrid.VerticalAlignment = Enum.VerticalAlignment.Center
    tabGrid.SortOrder = Enum.SortOrder.LayoutOrder
    tabGrid.Parent = tabBar

    local contentHolder = Instance.new("Frame")
    contentHolder.Name = "ContentHolder"
    contentHolder.AnchorPoint = Vector2.new(0.5, 0)
    contentHolder.Position = UDim2.new(0.5, 0, 0, 118)
    contentHolder.Size = UDim2.new(1, -24, 1, -130)
    contentHolder.BackgroundTransparency = 1
    contentHolder.ZIndex = 3
    contentHolder.Parent = MainCard

    local function createTabPage(name)
        local page = Instance.new("ScrollingFrame")
        page.Name = name .. "Page"
        page.AnchorPoint = Vector2.new(0.5, 0.5)
        page.Position = UDim2.fromScale(0.5, 0.5)
        page.Size = UDim2.fromScale(1, 1)
        page.BackgroundTransparency = 1
        page.BorderSizePixel = 0
        page.ScrollBarThickness = 5
        page.ScrollBarImageColor3 = Palette.PrimaryAccent
        page.ScrollBarImageTransparency = 0.35
        page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
        page.CanvasSize = UDim2.fromOffset(0, 0)
        page.AutomaticCanvasSize = Enum.AutomaticSize.Y
        page.Visible = (name == Config.UI.ActiveTab)
        page.ZIndex = 3
        page.Parent = contentHolder

        local list = Instance.new("UIListLayout")
        list.SortOrder = Enum.SortOrder.LayoutOrder
        list.HorizontalAlignment = Enum.HorizontalAlignment.Center
        list.Padding = UDim.new(0, 10)
        list.Parent = page

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 3)
        pad.PaddingBottom = UDim.new(0, 14)
        pad.PaddingLeft = UDim.new(0, 2)
        pad.PaddingRight = UDim.new(0, 8)
        pad.Parent = page

        TabPages[name] = page
        return page
    end

    local tabStrokes = {}

    local function switchTab(tabName)
        Config.UI.ActiveTab = tabName
        for name, page in pairs(TabPages) do
            page.Visible = (name == tabName)
        end
        for name, btn in pairs(TabButtons) do
            local isActive = (name == tabName)
            tween(btn, 0.18, {
                BackgroundColor3 = isActive and Palette.PrimaryAccent or Palette.CardElevated,
                BackgroundTransparency = isActive and 0.32 or 1,
                TextColor3 = isActive and Palette.TextHeader or Palette.TextSilver,
            })
            if tabStrokes[name] then
                tween(tabStrokes[name], 0.18, {
                    Transparency = isActive and 0.36 or 1,
                })
            end
        end
        ConfigStore.scheduleSave()
    end

    for idx, tabName in ipairs(tabOrder) do
        createTabPage(tabName)

        local isActive = (tabName == Config.UI.ActiveTab)
        local btn = Instance.new("TextButton")
        btn.Name = tabName .. "Tab"
        btn.LayoutOrder = idx
        btn.Font = Enum.Font.GothamMedium
        btn.Text = tabName
        btn.TextSize = 11
        btn.TextTruncate = Enum.TextTruncate.AtEnd
        btn.AutoButtonColor = false
        btn.BorderSizePixel = 0
        btn.BackgroundColor3 = isActive and Palette.PrimaryAccent or Palette.CardElevated
        btn.BackgroundTransparency = isActive and 0.32 or 1
        btn.TextColor3 = isActive and Palette.TextHeader or Palette.TextSilver
        btn.ZIndex = 4
        btn.Parent = tabBar

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = btn

        tabStrokes[tabName] = applyGlassStroke(btn, 1, isActive and 0.36 or 1, Palette.GlassSpecular)

        btn.Activated:Connect(function()
            switchTab(tabName)
        end)

        TabButtons[tabName] = btn
    end
end

-- ============================================================================
-- [SECTION 10] MODULAR UI COMPONENT BUILDERS & CONFIG-SYNC BINDING
-- ============================================================================
local SyncCallbacks = {}
local syncMobileAimVisibility = function() end
local syncMobileTriggerVisibility = function() end

local function SyncDependentSettings(needsFullReload, reason, skipSave)
    if not Config.Aimbot.Enabled then
        State.CurrentAimTarget = nil
        State.CurrentAimPart = nil
        State.CurrentAimPredictedPos = nil
        State.CurrentAimFrame = 0
    end
    if not Config.TriggerBot.Enabled then
        State.TriggerTarget = nil
        State.TriggerAcquireTime = 0
        releaseTriggerFire()
        TriggerDot.Visible = false
    end
    if not Config.ESP.Enabled then
        for _, entry in pairs(Registry) do
            if entry.Visuals then entry.Visuals:HideAll() end
            if entry.Highlight then entry.Highlight.Enabled = false end
        end
    elseif not Config.ESP.HighlightESP then
        for _, entry in pairs(Registry) do
            if entry.Highlight then entry.Highlight.Enabled = false end
        end
    end
    State.LastTeamScan = -1
    syncMobileAimVisibility()
    syncMobileTriggerVisibility()
    pcall(UI.syncVimPointer)
    pcall(UI.refreshTriggerControls)
    if not skipSave then
        ConfigStore.scheduleSave()
    end
    if needsFullReload then
        ScheduleReload(reason or "ConfigMutation", false)
    end
end

-- Scroll-guarded tap handler so vertical scrolling on mobile never triggers accidental mis-touches
local function bindSafeTap(btn, scrollParent, callback)
    local isScrollingFrame = scrollParent and scrollParent:IsA("ScrollingFrame")
    local trackedInput = nil
    local startPos = nil
    local startCanvasY = 0
    local maxMove = 0
    local hadValidPress = false

    btn.InputBegan:Connect(function(input)
        if input.UserInputState ~= Enum.UserInputState.Begin then
            return
        end
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            hadValidPress = true
            trackedInput = input
            startPos = input.Position
            startCanvasY = isScrollingFrame and scrollParent.CanvasPosition.Y or 0
            maxMove = 0
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not trackedInput or not startPos then
            return
        end
        if not InputGuard.isActiveState(trackedInput.UserInputState) then
            trackedInput = nil
            return
        end
        if input == trackedInput or (trackedInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
            local dist = (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(startPos.X, startPos.Y)).Magnitude
            if dist > maxMove then
                maxMove = dist
            end
        end
    end))

    local function finishTrackedTap(input)
        if input == trackedInput then
            local dist = startPos and (Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(startPos.X, startPos.Y)).Magnitude or 0
            if dist > maxMove then
                maxMove = dist
            end
            trackedInput = nil
        end
    end

    addConnection(UserInputService.InputEnded:Connect(finishTrackedTap))
    addConnection(UserInputService.TouchEnded:Connect(finishTrackedTap))

    btn.Activated:Connect(function()
        local canvasDelta = isScrollingFrame and math.abs(scrollParent.CanvasPosition.Y - startCanvasY) or 0
        local wasCleanTap = hadValidPress and (maxMove <= 10) and (canvasDelta <= 4)
        hadValidPress = false
        trackedInput = nil
        startPos = nil
        maxMove = 0
        if wasCleanTap then
            callback()
        end
    end)
end

local function createCardRow(parent, height, order)
    local card = Instance.new("Frame")
    card.LayoutOrder = order
    card.Size = UDim2.new(1, 0, 0, height)
    card.ZIndex = 4
    card.Parent = parent

    UI.applyFrostedSurface(card, 14, Palette.CardElevated, 0.62, 0.60, true)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 14)
    pad.PaddingTop = UDim.new(0, 9)
    pad.PaddingBottom = UDim.new(0, 9)
    pad.Parent = card

    return card
end

local function addToggle(parent, order, title, subtitle, getter, setter)
    local row = createCardRow(parent, subtitle and 58 or 48, order)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.AnchorPoint = Vector2.new(0, 0.5)
    label.Position = UDim2.new(0, 0, subtitle and 0.30 or 0.5, 0)
    label.Size = UDim2.new(1, -60, 0, 18)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextHeader
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = 5
    label.Parent = row

    if subtitle then
        local sub = Instance.new("TextLabel")
        sub.BackgroundTransparency = 1
        sub.AnchorPoint = Vector2.new(0, 0.5)
        sub.Position = UDim2.new(0, 0, 0.74, 0)
        sub.Size = UDim2.new(1, -60, 0, 15)
        sub.Font = Enum.Font.Gotham
        sub.Text = subtitle
        sub.TextSize = 11
        sub.TextColor3 = Palette.TextSilver
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextTruncate = Enum.TextTruncate.AtEnd
        sub.ZIndex = 5
        sub.Parent = row
    end

    local switchBtn = Instance.new("TextButton")
    switchBtn.AnchorPoint = Vector2.new(1, 0.5)
    switchBtn.Position = UDim2.new(1, 0, 0.5, 0)
    switchBtn.Size = UDim2.fromOffset(48, 26)
    switchBtn.Text = ""
    switchBtn.AutoButtonColor = false
    switchBtn.BorderSizePixel = 0
    switchBtn.ZIndex = 5
    switchBtn.Parent = row

    local swCorner = Instance.new("UICorner")
    swCorner.CornerRadius = UDim.new(1, 0)
    swCorner.Parent = switchBtn

    local swStroke = applyGlassStroke(switchBtn, 1, 0.55, Palette.GlassEdge)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Size = UDim2.fromOffset(20, 20)
    knob.BackgroundColor3 = Palette.TextHeader
    knob.BorderSizePixel = 0
    knob.ZIndex = 6
    knob.Parent = switchBtn

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function sync(instant)
        local on = getter()
        local targetTrack = on and Palette.ActiveGlow or Palette.ToggleOff
        local targetTrans = on and 0.14 or 0.38
        local targetKnobPos = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        local targetStrokeColor = on and Palette.ActiveGlow or Palette.GlassEdge
        if instant then
            switchBtn.BackgroundColor3 = targetTrack
            switchBtn.BackgroundTransparency = targetTrans
            knob.Position = targetKnobPos
            swStroke.Color = targetStrokeColor
        else
            tween(switchBtn, 0.16, {
                BackgroundColor3 = targetTrack,
                BackgroundTransparency = targetTrans,
            })
            tween(knob, 0.16, {Position = targetKnobPos})
            tween(swStroke, 0.16, {Color = targetStrokeColor})
        end
    end

    sync(true)
    table.insert(SyncCallbacks, function()
        sync(true)
    end)

    bindSafeTap(switchBtn, parent, function()
        setter(not getter())
        sync(false)
        SyncDependentSettings(false)
    end)
end

local function addSlider(parent, order, title, minVal, maxVal, step, formatFn, getter, setter)
    local row = createCardRow(parent, 68, order)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(0, 1)
    label.Size = UDim2.new(1, -130, 0, 20)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextHeader
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = 5
    label.Parent = row

    local minusBtn = Instance.new("TextButton")
    minusBtn.AnchorPoint = Vector2.new(1, 0)
    minusBtn.Position = UDim2.new(1, -98, 0, 0)
    minusBtn.Size = UDim2.fromOffset(26, 22)
    minusBtn.BackgroundColor3 = Palette.SurfaceSoft
    minusBtn.BackgroundTransparency = 0.42
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.Text = "-"
    minusBtn.TextSize = 14
    minusBtn.TextColor3 = Palette.TextHeader
    minusBtn.AutoButtonColor = false
    minusBtn.BorderSizePixel = 0
    minusBtn.ZIndex = 6
    minusBtn.Parent = row
    local mc = Instance.new("UICorner")
    mc.CornerRadius = UDim.new(0, 8)
    mc.Parent = minusBtn
    applyGlassStroke(minusBtn, 1, 0.62, Palette.GlassEdge)

    local valueLabel = Instance.new("TextLabel")
    valueLabel.BackgroundTransparency = 1
    valueLabel.AnchorPoint = Vector2.new(1, 0)
    valueLabel.Position = UDim2.new(1, -30, 0, 1)
    valueLabel.Size = UDim2.fromOffset(64, 20)
    valueLabel.Font = Enum.Font.Code
    valueLabel.TextSize = 11.5
    valueLabel.TextColor3 = Palette.ActiveGlow
    valueLabel.TextXAlignment = Enum.TextXAlignment.Center
    valueLabel.ZIndex = 5
    valueLabel.Parent = row

    local plusBtn = Instance.new("TextButton")
    plusBtn.AnchorPoint = Vector2.new(1, 0)
    plusBtn.Position = UDim2.new(1, 0, 0, 0)
    plusBtn.Size = UDim2.fromOffset(26, 22)
    plusBtn.BackgroundColor3 = Palette.SurfaceSoft
    plusBtn.BackgroundTransparency = 0.42
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.Text = "+"
    plusBtn.TextSize = 14
    plusBtn.TextColor3 = Palette.TextHeader
    plusBtn.AutoButtonColor = false
    plusBtn.BorderSizePixel = 0
    plusBtn.ZIndex = 6
    plusBtn.Parent = row
    local pc = Instance.new("UICorner")
    pc.CornerRadius = UDim.new(0, 8)
    pc.Parent = plusBtn
    applyGlassStroke(plusBtn, 1, 0.62, Palette.GlassEdge)

    local trackHitbox = Instance.new("TextButton")
    trackHitbox.BackgroundTransparency = 1
    trackHitbox.Text = ""
    trackHitbox.AutoButtonColor = false
    trackHitbox.AnchorPoint = Vector2.new(0.5, 1)
    trackHitbox.Position = UDim2.new(0.5, 0, 1, 2)
    trackHitbox.Size = UDim2.new(1, 0, 0, 28)
    trackHitbox.ZIndex = 6
    trackHitbox.Parent = row

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0.5, 0.5)
    track.Position = UDim2.fromScale(0.5, 0.5)
    track.Size = UDim2.new(1, 0, 0, 7)
    track.BackgroundColor3 = Palette.ToggleOff
    track.BackgroundTransparency = 0.40
    track.BorderSizePixel = 0
    track.ZIndex = 5
    track.Parent = trackHitbox

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track
    applyGlassStroke(track, 1, 0.72, Palette.GlassEdge)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0.5, 1)
    fill.BackgroundColor3 = Palette.PrimaryAccent
    fill.BorderSizePixel = 0
    fill.ZIndex = 6
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local fillGrad = Instance.new("UIGradient")
    fillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Palette.PrimaryAccent),
        ColorSequenceKeypoint.new(1, Palette.ActiveGlow),
    })
    fillGrad.Parent = fill

    local thumb = Instance.new("Frame")
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.Position = UDim2.fromScale(0.5, 0.5)
    thumb.Size = UDim2.fromOffset(16, 16)
    thumb.BackgroundColor3 = Palette.TextHeader
    thumb.BorderSizePixel = 0
    thumb.ZIndex = 7
    thumb.Parent = track

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(1, 0)
    thumbCorner.Parent = thumb
    applyGlassStroke(thumb, 1.2, 0.34, Palette.PrimaryAccent)

    local function sync()
        local val = math.clamp(getter(), minVal, maxVal)
        local ratio = (val - minVal) / math.max(maxVal - minVal, 0.0001)
        fill.Size = UDim2.fromScale(ratio, 1)
        thumb.Position = UDim2.fromScale(ratio, 0.5)
        valueLabel.Text = formatFn(val)
    end

    sync()
    table.insert(SyncCallbacks, sync)

    local function applyValue(raw)
        local stepped = math.round((raw - minVal) / step) * step + minVal
        local clamped = math.clamp(math.round(stepped * 1000) / 1000, minVal, maxVal)
        setter(clamped)
        sync()
        ConfigStore.scheduleSave()
    end

    bindSafeTap(minusBtn, parent, function()
        applyValue(getter() - step)
    end)

    bindSafeTap(plusBtn, parent, function()
        applyValue(getter() + step)
    end)

    local isScrollableParent = parent and parent:IsA("ScrollingFrame")
    local pendingInput = nil
    local dragStartPos = nil
    local startCanvasY = 0
    local dragging = false

    local function clearSliderDrag()
        pendingInput = nil
        dragStartPos = nil
        dragging = false
        if isScrollableParent then
            parent.ScrollingEnabled = true
        end
    end

    local function updateFromInput(posX)
        local absPos = track.AbsolutePosition.X
        local absSize = math.max(track.AbsoluteSize.X, 1)
        local ratio = math.clamp((posX - absPos) / absSize, 0, 1)
        applyValue(minVal + (maxVal - minVal) * ratio)
    end

    trackHitbox.InputBegan:Connect(function(input)
        if not pendingInput and input.UserInputState == Enum.UserInputState.Begin and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            pendingInput = input
            dragStartPos = input.Position
            startCanvasY = isScrollableParent and parent.CanvasPosition.Y or 0
            dragging = false
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                if isScrollableParent then
                    parent.ScrollingEnabled = false
                end
                updateFromInput(input.Position.X)
            end
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not pendingInput or not dragStartPos then
            return
        end
        if not InputGuard.isActiveState(pendingInput.UserInputState) then
            clearSliderDrag()
            return
        end
        if input == pendingInput or (pendingInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
            local dx = math.abs(input.Position.X - dragStartPos.X)
            local dy = math.abs(input.Position.Y - dragStartPos.Y)
            local canvasDelta = isScrollableParent and math.abs(parent.CanvasPosition.Y - startCanvasY) or 0

            if not dragging then
                if canvasDelta > 4 or (dy > 7 and dy > dx) then
                    clearSliderDrag()
                    return
                elseif dx > 7 and dx >= dy then
                    dragging = true
                    if isScrollableParent then
                        parent.ScrollingEnabled = false
                    end
                    updateFromInput(input.Position.X)
                end
            else
                updateFromInput(input.Position.X)
            end
        end
    end))

    local function finishSliderInput(input)
        if pendingInput and (input == pendingInput or not InputGuard.isActiveState(pendingInput.UserInputState)) then
            local dx = dragStartPos and math.abs(input.Position.X - dragStartPos.X) or 0
            local dy = dragStartPos and math.abs(input.Position.Y - dragStartPos.Y) or 0
            local canvasDelta = isScrollableParent and math.abs(parent.CanvasPosition.Y - startCanvasY) or 0
            if (not dragging) and dx <= 7 and dy <= 7 and canvasDelta <= 4 then
                updateFromInput(input.Position.X)
            end
            clearSliderDrag()
        end
    end

    addConnection(UserInputService.InputEnded:Connect(finishSliderInput))
    addConnection(UserInputService.TouchEnded:Connect(finishSliderInput))

    return sync
end

local function addSelector(parent, order, title, options, getter, setter, reloadOnSelect)
    local row = createCardRow(parent, 72, order)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(0, 0)
    label.Size = UDim2.new(1, 0, 0, 18)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextHeader
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = 5
    label.Parent = row

    local bar = Instance.new("Frame")
    bar.AnchorPoint = Vector2.new(0.5, 1)
    bar.Position = UDim2.new(0.5, 0, 1, 0)
    bar.Size = UDim2.new(1, 0, 0, 30)
    bar.ZIndex = 5
    bar.Parent = row
    UI.applyFrostedSurface(bar, 10, Palette.GlassBase, 0.56, 0.66, false)

    local barPad = Instance.new("UIPadding")
    barPad.PaddingLeft = UDim.new(0, 3)
    barPad.PaddingRight = UDim.new(0, 3)
    barPad.PaddingTop = UDim.new(0, 3)
    barPad.PaddingBottom = UDim.new(0, 3)
    barPad.Parent = bar

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(1 / #options, -4, 1, 0)
    grid.CellPadding = UDim2.fromOffset(4, 0)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Center
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = bar

    local btns = {}
    local btnStrokes = {}

    local function sync()
        local active = getter()
        for opt, b in pairs(btns) do
            local sel = (opt == active)
            tween(b, 0.14, {
                BackgroundColor3 = sel and Palette.PrimaryAccent or Palette.GlassBase,
                BackgroundTransparency = sel and 0.28 or 1,
                TextColor3 = sel and Palette.TextHeader or Palette.TextSilver,
            })
            if btnStrokes[opt] then
                tween(btnStrokes[opt], 0.14, {
                    Transparency = sel and 0.42 or 1,
                })
            end
        end
    end

    for i, opt in ipairs(options) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.Text = opt
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 10.5
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.ZIndex = 6
        b.Parent = bar

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 8)
        bc.Parent = b

        btnStrokes[opt] = applyGlassStroke(b, 1, 1, Palette.GlassSpecular)

        bindSafeTap(b, parent, function()
            setter(opt)
            sync()
            SyncDependentSettings(reloadOnSelect == true, "Selector:" .. title)
        end)

        btns[opt] = b
    end

    sync()
    table.insert(SyncCallbacks, sync)
end

local function addRadioGroup(parent, order, title, options, getter, setter, reloadOnSelect)
    local rowHeight = 42 + (#options * 50)
    local card = createCardRow(parent, rowHeight, order)

    local heading = Instance.new("TextLabel")
    heading.BackgroundTransparency = 1
    heading.Position = UDim2.fromOffset(0, 0)
    heading.Size = UDim2.new(1, 0, 0, 18)
    heading.Font = Enum.Font.GothamMedium
    heading.Text = title
    heading.TextSize = 13
    heading.TextColor3 = Palette.TextHeader
    heading.TextXAlignment = Enum.TextXAlignment.Left
    heading.TextTruncate = Enum.TextTruncate.AtEnd
    heading.ZIndex = 5
    heading.Parent = card

    local listHolder = Instance.new("Frame")
    listHolder.BackgroundTransparency = 1
    listHolder.Position = UDim2.fromOffset(0, 24)
    listHolder.Size = UDim2.new(1, 0, 1, -24)
    listHolder.ZIndex = 5
    listHolder.Parent = card

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 6)
    listLayout.Parent = listHolder

    local optionWidgets = {}

    local function sync()
        local activeVal = getter()
        for val, w in pairs(optionWidgets) do
            local sel = (val == activeVal)
            tween(w.Btn, 0.14, {
                BackgroundColor3 = sel and Color3.fromRGB(28, 46, 74) or Palette.GlassBase,
                BackgroundTransparency = sel and 0.36 or 0.60,
            })
            w.Stroke.Color = sel and Palette.ActiveGlow or Palette.GlassEdge
            w.Stroke.Transparency = sel and 0.24 or 0.68
            w.OuterStroke.Color = sel and Palette.ActiveGlow or Palette.TextSilver
            w.Dot.Visible = sel
            w.Title.TextColor3 = sel and Palette.TextHeader or Palette.TextSilver
        end
    end

    for idx, opt in ipairs(options) do
        local optBtn = Instance.new("TextButton")
        optBtn.LayoutOrder = idx
        optBtn.Size = UDim2.new(1, 0, 0, 44)
        optBtn.BackgroundColor3 = Palette.GlassBase
        optBtn.BackgroundTransparency = 0.60
        optBtn.Text = ""
        optBtn.AutoButtonColor = false
        optBtn.BorderSizePixel = 0
        optBtn.ZIndex = 6
        optBtn.Parent = listHolder

        local oc = Instance.new("UICorner")
        oc.CornerRadius = UDim.new(0, 12)
        oc.Parent = optBtn

        local oStroke = applyGlassStroke(optBtn, 1, 0.68, Palette.GlassEdge)

        local radioOuter = Instance.new("Frame")
        radioOuter.AnchorPoint = Vector2.new(0, 0.5)
        radioOuter.Position = UDim2.new(0, 12, 0.5, 0)
        radioOuter.Size = UDim2.fromOffset(18, 18)
        radioOuter.BackgroundTransparency = 1
        radioOuter.ZIndex = 7
        radioOuter.Parent = optBtn

        local roc = Instance.new("UICorner")
        roc.CornerRadius = UDim.new(1, 0)
        roc.Parent = radioOuter

        local outerStroke = Instance.new("UIStroke")
        outerStroke.Thickness = 1.6
        outerStroke.Color = Palette.TextSilver
        outerStroke.Parent = radioOuter

        local radioDot = Instance.new("Frame")
        radioDot.Name = "RadioDot"
        radioDot.AnchorPoint = Vector2.new(0.5, 0.5)
        radioDot.Position = UDim2.fromScale(0.5, 0.5)
        radioDot.Size = UDim2.fromOffset(9, 9)
        radioDot.BackgroundColor3 = Palette.ActiveGlow
        radioDot.BorderSizePixel = 0
        radioDot.Visible = false
        radioDot.ZIndex = 8
        radioDot.Parent = radioOuter

        local rdc = Instance.new("UICorner")
        rdc.CornerRadius = UDim.new(1, 0)
        rdc.Parent = radioDot

        local optTitle = Instance.new("TextLabel")
        optTitle.BackgroundTransparency = 1
        optTitle.Position = UDim2.new(0, 38, 0, 5)
        optTitle.Size = UDim2.new(1, -46, 0, 17)
        optTitle.Font = Enum.Font.GothamBold
        optTitle.Text = opt.Title or opt.Value
        optTitle.TextSize = 12
        optTitle.TextColor3 = Palette.TextHeader
        optTitle.TextXAlignment = Enum.TextXAlignment.Left
        optTitle.TextTruncate = Enum.TextTruncate.AtEnd
        optTitle.ZIndex = 7
        optTitle.Parent = optBtn

        local optSub = Instance.new("TextLabel")
        optSub.BackgroundTransparency = 1
        optSub.Position = UDim2.new(0, 38, 0, 23)
        optSub.Size = UDim2.new(1, -46, 0, 14)
        optSub.Font = Enum.Font.Gotham
        optSub.Text = opt.Subtitle or ""
        optSub.TextSize = 10.5
        optSub.TextColor3 = Palette.TextSilver
        optSub.TextXAlignment = Enum.TextXAlignment.Left
        optSub.TextTruncate = Enum.TextTruncate.AtEnd
        optSub.ZIndex = 7
        optSub.Parent = optBtn

        bindSafeTap(optBtn, parent, function()
            setter(opt.Value)
            sync()
            SyncDependentSettings(reloadOnSelect == true, "Radio:" .. opt.Value)
        end)

        optionWidgets[opt.Value] = {
            Btn = optBtn,
            Stroke = oStroke,
            OuterStroke = outerStroke,
            Dot = radioDot,
            Title = optTitle,
        }
    end

    sync()
    table.insert(SyncCallbacks, sync)
end

local function addSectionHeader(parent, order, title)
    local holder = Instance.new("Frame")
    holder.LayoutOrder = order
    holder.Size = UDim2.new(1, 0, 0, 24)
    holder.BackgroundTransparency = 1
    holder.ZIndex = 4
    holder.Parent = parent

    local pip = Instance.new("Frame")
    pip.AnchorPoint = Vector2.new(0, 0.5)
    pip.Position = UDim2.new(0, 2, 0.5, 0)
    pip.Size = UDim2.fromOffset(3, 12)
    pip.BackgroundColor3 = Palette.ActiveGlow
    pip.BorderSizePixel = 0
    pip.ZIndex = 5
    pip.Parent = holder

    local pipCorner = Instance.new("UICorner")
    pipCorner.CornerRadius = UDim.new(1, 0)
    pipCorner.Parent = pip

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.AnchorPoint = Vector2.new(0, 0.5)
    lbl.Position = UDim2.new(0, 10, 0.5, 0)
    lbl.Size = UDim2.new(1, -12, 1, 0)
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = string.upper(title)
    lbl.TextSize = 10.5
    lbl.TextColor3 = Palette.GlassEdge
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 5
    lbl.Parent = holder

    local rule = Instance.new("Frame")
    rule.AnchorPoint = Vector2.new(0, 1)
    rule.Position = UDim2.new(0, 2, 1, 0)
    rule.Size = UDim2.new(1, -4, 0, 1)
    rule.BackgroundColor3 = Palette.GlassEdge
    rule.BackgroundTransparency = 0.80
    rule.BorderSizePixel = 0
    rule.ZIndex = 4
    rule.Parent = holder

    local ruleCorner = Instance.new("UICorner")
    ruleCorner.CornerRadius = UDim.new(1, 0)
    ruleCorner.Parent = rule
end

-- ============================================================================
-- [SECTION 11] POPULATE TABS (AIMBOT, TRIGGER, ESP, COLORS & THICKNESS, SETTINGS)
-- ============================================================================
local ForceReloadBtn = nil
local ResetBtn = nil
local UnloadBtn = nil
local SettingsPage = TabPages["Settings"]

local function populateAllTabs()
-- 1. AIMBOT TAB
do
    local AimbotPage = TabPages["Aimbot"]
    addSectionHeader(AimbotPage, 1, "Core Aim Lock")
    addToggle(AimbotPage, 2, "Enable Aimbot", "Master toggle synced with Aim Lock GUI button", function()
        return Config.Aimbot.Enabled
    end, function(v)
        Config.Aimbot.Enabled = v
        Config.UI.MobileAimLocked = v
    end)

    addSelector(AimbotPage, 3, "Activation Mode", {"GUI Toggle", "Hold"}, function()
        return Config.Aimbot.ActivationMode
    end, function(v)
        Config.Aimbot.ActivationMode = v
    end, false)

    addSelector(AimbotPage, 4, "Target Part (R6 / R15 / Custom Rigs)", {"Head", "Chest", "HumanoidRootPart", "Closest"}, function()
        return Config.Aimbot.TargetPart
    end, function(v)
        Config.Aimbot.TargetPart = v
    end, false)

    addSlider(AimbotPage, 5, "Smoothness", 1, 20, 1, function(v)
        local n = math.round(v)
        return (n <= 1) and "1 (Instant)" or string.format("%d", n)
    end, function()
        return Config.Aimbot.Smoothness
    end, function(v)
        Config.Aimbot.Smoothness = math.round(v)
    end)

    addSectionHeader(AimbotPage, 6, "Prediction & Auto Predict")
    addToggle(AimbotPage, 7, "Auto Predict", "Automatically adjusts lead by live ping, distance & target speed", function()
        return Config.Aimbot.AutoPredict
    end, function(v)
        Config.Aimbot.AutoPredict = v
    end)

    addSlider(AimbotPage, 8, "Manual Prediction Lead Time", 0.00, 0.30, 0.01, function(v)
        return string.format("%.2fs", v)
    end, function()
        return Config.Aimbot.Prediction
    end, function(v)
        Config.Aimbot.Prediction = v
    end)

    addSlider(AimbotPage, 9, "Projectile Speed (0 = Lead Only)", 0, 2000, 50, function(v)
        local n = math.round(v)
        return (n == 0) and "Off" or string.format("%d st/s", n)
    end, function()
        return Config.Aimbot.ProjectileSpeed
    end, function(v)
        Config.Aimbot.ProjectileSpeed = math.round(v)
    end)

    addToggle(AimbotPage, 10, "Ping Auto-Compensation", "Adds half-RTT ping when Auto Predict is off", function()
        return Config.Aimbot.PingCompensation
    end, function(v)
        Config.Aimbot.PingCompensation = v
    end)

    addSectionHeader(AimbotPage, 11, "FOV & Target Filters")
    addSlider(AimbotPage, 12, "FOV Radius", 30, 420, 5, function(v)
        return string.format("%d px", math.round(v))
    end, function()
        return Config.Aimbot.FOVRadius
    end, function(v)
        Config.Aimbot.FOVRadius = v
    end)

    addToggle(AimbotPage, 13, "Show FOV Circle", "Displays centered FOV ring around crosshair", function()
        return Config.Aimbot.ShowFOV
    end, function(v)
        Config.Aimbot.ShowFOV = v
    end)

    addToggle(AimbotPage, 14, "Ignore Bots (Aimbot)", "Skips NPCs/bots so aimbot locks onto real players only", function()
        return Config.Aimbot.IgnoreBots
    end, function(v)
        Config.Aimbot.IgnoreBots = v
        syncWorkspaceBots()
    end)

    addToggle(AimbotPage, 15, "Team Check", "Skips teammates (FFA-safe Auto mode)", function()
        return Config.Aimbot.TeamCheck
    end, function(v)
        Config.Aimbot.TeamCheck = v
    end)

    addToggle(AimbotPage, 16, "Visible / Wall Check", "Blocks aim lock through solid walls", function()
        return Config.Aimbot.VisibleCheck
    end, function(v)
        Config.Aimbot.VisibleCheck = v
    end)

    addToggle(AimbotPage, 17, "Sticky Target Lock", "Maintains lock while target remains valid", function()
        return Config.Aimbot.StickyTarget
    end, function(v)
        Config.Aimbot.StickyTarget = v
    end)
end

-- 2. TRIGGER BOT TAB
do
    local TriggerPage = TabPages["Trigger"]
    addSectionHeader(TriggerPage, 1, "Trigger Bot Engine")
    addToggle(TriggerPage, 2, "Enable Trigger Bot", "100% Touch-safe firing without PC/mouse mode switching", function()
        return Config.TriggerBot.Enabled
    end, function(v)
        Config.TriggerBot.Enabled = v
        Config.UI.MobileTriggerLocked = v
        if v and (Config.TriggerBot.Mode == "firesignal" or Config.TriggerBot.Mode == "Tool:Activate()") then
            task.defer(TriggerEngine.rescanAll)
        end
    end)

    addRadioGroup(TriggerPage, 3, "Touch-Safe Firing Mode", {
        {
            Value = "VirtualInputManager",
            Title = "VirtualInputManager (Floating Pointer)",
            Subtitle = "Draggable reticle sends SendTouchEvent; touches pass through",
        },
        {
            Value = "firesignal",
            Title = "firesignal (Auto Fire Button)",
            Subtitle = "Ranks & caches working PlayerGui fire signals per game",
        },
        {
            Value = "Tool:Activate()",
            Title = "Tool:Activate() (Weapon Activation)",
            Subtitle = "Ranks & caches equipped Tool calls per game",
        },
    }, function()
        return Config.TriggerBot.Mode
    end, function(v)
        releaseTriggerFire()
        Config.TriggerBot.Mode = v
        if v == "firesignal" then
            TriggerEngine.scanFireSignals()
        elseif v == "Tool:Activate()" then
            TriggerEngine.scanToolCalls()
        end
    end, false)

    -- Mode Control & Auto-Discovery Recovery Card
    do
        local modeCard = createCardRow(TriggerPage, 132, 4)

        local modeHeader = Instance.new("TextLabel")
        modeHeader.BackgroundTransparency = 1
        modeHeader.Position = UDim2.fromOffset(0, 0)
        modeHeader.Size = UDim2.new(1, -92, 0, 18)
        modeHeader.Font = Enum.Font.GothamBold
        modeHeader.Text = "Active Mode Controls"
        modeHeader.TextSize = 12.5
        modeHeader.TextColor3 = Palette.TextHeader
        modeHeader.TextXAlignment = Enum.TextXAlignment.Left
        modeHeader.ZIndex = 5
        modeHeader.Parent = modeCard

        local modeBadge = Instance.new("TextLabel")
        modeBadge.AnchorPoint = Vector2.new(1, 0)
        modeBadge.Position = UDim2.new(1, 0, 0, -1)
        modeBadge.Size = UDim2.fromOffset(92, 20)
        modeBadge.BackgroundColor3 = Palette.GlassBase
        modeBadge.BackgroundTransparency = 0.56
        modeBadge.BorderSizePixel = 0
        modeBadge.Font = Enum.Font.Code
        modeBadge.Text = "VIM"
        modeBadge.TextSize = 10.5
        modeBadge.TextColor3 = Palette.ActiveGlow
        modeBadge.TextXAlignment = Enum.TextXAlignment.Center
        modeBadge.ZIndex = 5
        modeBadge.Parent = modeCard

        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = UDim.new(1, 0)
        badgeCorner.Parent = modeBadge
        applyGlassStroke(modeBadge, 1, 0.62, Palette.ActiveGlow)

        local statusLine = Instance.new("TextLabel")
        statusLine.BackgroundTransparency = 1
        statusLine.Position = UDim2.fromOffset(0, 23)
        statusLine.Size = UDim2.new(1, 0, 0, 16)
        statusLine.Font = Enum.Font.Gotham
        statusLine.Text = "Pointer locked"
        statusLine.TextSize = 11
        statusLine.TextColor3 = Palette.TextSilver
        statusLine.TextXAlignment = Enum.TextXAlignment.Left
        statusLine.TextTruncate = Enum.TextTruncate.AtEnd
        statusLine.ZIndex = 5
        statusLine.Parent = modeCard

        -- Subview A: VIM Lock / Unlock Pointer Controls
        local vimPane = Instance.new("Frame")
        vimPane.BackgroundTransparency = 1
        vimPane.Position = UDim2.fromOffset(0, 46)
        vimPane.Size = UDim2.new(1, 0, 1, -46)
        vimPane.ZIndex = 5
        vimPane.Parent = modeCard

        local lockBtn = Instance.new("TextButton")
        lockBtn.Position = UDim2.fromOffset(0, 2)
        lockBtn.Size = UDim2.new(0.68, -4, 0, 34)
        lockBtn.Font = Enum.Font.GothamBold
        lockBtn.Text = "Pointer Locked (Touch Pass-Through)"
        lockBtn.TextSize = 11
        lockBtn.TextColor3 = Palette.TextHeader
        lockBtn.BackgroundColor3 = Palette.ActiveGlow
        lockBtn.BackgroundTransparency = 0.62
        lockBtn.AutoButtonColor = false
        lockBtn.BorderSizePixel = 0
        lockBtn.ZIndex = 6
        lockBtn.Parent = vimPane
        local lbc = Instance.new("UICorner")
        lbc.CornerRadius = UDim.new(0, 10)
        lbc.Parent = lockBtn
        local lbStroke = applyGlassStroke(lockBtn, 1, 0.35, Palette.ActiveGlow)

        local centerBtn = Instance.new("TextButton")
        centerBtn.AnchorPoint = Vector2.new(1, 0)
        centerBtn.Position = UDim2.new(1, 0, 0, 2)
        centerBtn.Size = UDim2.new(0.32, -4, 0, 34)
        centerBtn.Font = Enum.Font.GothamMedium
        centerBtn.Text = "Reset Pos"
        centerBtn.TextSize = 11
        centerBtn.TextColor3 = Palette.TextHeader
        centerBtn.BackgroundColor3 = Palette.SurfaceSoft
        centerBtn.BackgroundTransparency = 0.44
        centerBtn.AutoButtonColor = false
        centerBtn.BorderSizePixel = 0
        centerBtn.ZIndex = 6
        centerBtn.Parent = vimPane
        local cbc = Instance.new("UICorner")
        cbc.CornerRadius = UDim.new(0, 10)
        cbc.Parent = centerBtn
        applyGlassStroke(centerBtn, 1, 0.58, Palette.GlassEdge)

        -- Subview B: firesignal / Tool:Activate() Action + Candidate Picker
        local callPane = Instance.new("Frame")
        callPane.BackgroundTransparency = 1
        callPane.Position = UDim2.fromOffset(0, 44)
        callPane.Size = UDim2.new(1, 0, 1, -44)
        callPane.Visible = false
        callPane.ZIndex = 5
        callPane.Parent = modeCard

        local actionRow = Instance.new("Frame")
        actionRow.BackgroundTransparency = 1
        actionRow.Size = UDim2.new(1, 0, 0, 32)
        actionRow.ZIndex = 5
        actionRow.Parent = callPane

        local aGrid = Instance.new("UIGridLayout")
        aGrid.CellSize = UDim2.new(0.333, -4, 1, 0)
        aGrid.CellPadding = UDim2.fromOffset(6, 0)
        aGrid.Parent = actionRow

        local function makeSmallAction(text, bg, trans)
            local b = Instance.new("TextButton")
            b.Text = text
            b.Font = Enum.Font.GothamBold
            b.TextSize = 10.5
            b.TextColor3 = Palette.TextHeader
            b.BackgroundColor3 = bg
            b.BackgroundTransparency = trans
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.AutoButtonColor = false
            b.BorderSizePixel = 0
            b.ZIndex = 6
            b.Parent = actionRow
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 10)
            c.Parent = b
            applyGlassStroke(b, 1, 0.58, Palette.GlassEdge)
            return b
        end

        local brokenBtn = makeSmallAction("Call Not Working", Palette.Danger, 0.36)
        local rescanBtn = makeSmallAction("Rescan", Palette.PrimaryAccent, 0.38)
        local resetBrokenBtn = makeSmallAction("Reset Broken", Palette.SurfaceSoft, 0.44)

        local candList = Instance.new("Frame")
        candList.BackgroundTransparency = 1
        candList.Position = UDim2.fromOffset(0, 38)
        candList.Size = UDim2.new(1, 0, 1, -38)
        candList.ZIndex = 5
        candList.Parent = callPane

        local candLayout = Instance.new("UIListLayout")
        candLayout.Padding = UDim.new(0, 4)
        candLayout.SortOrder = Enum.SortOrder.LayoutOrder
        candLayout.Parent = candList

        local candButtons = {}
        local candStrokes = {}
        local candKeys = {}
        for i = 1, 4 do
            local cb = Instance.new("TextButton")
            cb.LayoutOrder = i
            cb.Size = UDim2.new(1, 0, 0, 26)
            cb.BackgroundColor3 = Palette.GlassBase
            cb.BackgroundTransparency = 0.56
            cb.Font = Enum.Font.Code
            cb.Text = ""
            cb.TextSize = 10.5
            cb.TextColor3 = Palette.TextSilver
            cb.TextXAlignment = Enum.TextXAlignment.Left
            cb.TextTruncate = Enum.TextTruncate.AtEnd
            cb.AutoButtonColor = false
            cb.BorderSizePixel = 0
            cb.Visible = false
            cb.ZIndex = 6
            cb.Parent = candList
            local cbc2 = Instance.new("UICorner")
            cbc2.CornerRadius = UDim.new(0, 9)
            cbc2.Parent = cb
            candStrokes[i] = applyGlassStroke(cb, 1, 0.72, Palette.GlassEdge)
            local cpad = Instance.new("UIPadding")
            cpad.PaddingLeft = UDim.new(0, 10)
            cpad.PaddingRight = UDim.new(0, 10)
            cpad.Parent = cb

            bindSafeTap(cb, TriggerPage, function()
                local k = candKeys[i]
                if k then
                    TriggerEngine.selectCandidateByKey(Config.TriggerBot.Mode, k)
                end
            end)
            candButtons[i] = cb
        end

        UI.refreshTriggerControls = function()
            local mode = Config.TriggerBot.Mode
            if mode == "VirtualInputManager" then
                vimPane.Visible = true
                callPane.Visible = false
                modeCard.Size = UDim2.new(1, 0, 0, 102)
                modeHeader.Text = "VIM Floating Pointer Controls"
                modeBadge.Text = VirtualInputManager and "VIM READY" or "NO VIM"
                local locked = Config.TriggerBot.PointerLocked
                statusLine.Text = locked
                    and string.format("Locked at (%.0f%%, %.0f%%) — finger touches pass through", Config.TriggerBot.PointerScaleX * 100, Config.TriggerBot.PointerScaleY * 100)
                    or "Unlocked — drag floating pointer reticle onto fire button"
                lockBtn.Text = locked and "Unlock Pointer Position" or "Lock Pointer Position"
                lockBtn.BackgroundColor3 = locked and Palette.ActiveGlow or Palette.Amber
                lockBtn.BackgroundTransparency = locked and 0.62 or 0.42
                lbStroke.Color = locked and Palette.ActiveGlow or Palette.Amber
            else
                vimPane.Visible = false
                callPane.Visible = true
                local isFire = (mode == "firesignal")
                local cands = isFire and TriggerEngine.FireSignalCandidates or TriggerEngine.ToolCandidates
                local activeIdx = isFire and TriggerEngine.ActiveFireIdx or TriggerEngine.ActiveToolIdx
                local shownCount = math.min(#cands, 4)
                modeCard.Size = UDim2.new(1, 0, 0, 102 + (shownCount * 30))
                modeHeader.Text = isFire and "firesignal Discovery & Recovery" or "Tool:Activate() Discovery & Recovery"
                modeBadge.Text = string.format("%d FOUND", #cands)
                statusLine.Text = isFire and TriggerEngine.FireSignalStatus or TriggerEngine.ToolCallStatus

                for i = 1, 4 do
                    local btn = candButtons[i]
                    local cand = cands[i]
                    if cand then
                        candKeys[i] = cand.Key
                        local isActive = (i == activeIdx)
                        local tag = cand.Confirmed and " [SAVED]" or ""
                        btn.Text = string.format("%s#%d %s%s", isActive and "> " or "  ", i, cand.Label, tag)
                        btn.BackgroundColor3 = isActive and Color3.fromRGB(26, 48, 72) or Palette.GlassBase
                        btn.BackgroundTransparency = isActive and 0.34 or 0.56
                        btn.TextColor3 = isActive and Palette.ActiveGlow or Palette.TextSilver
                        if candStrokes[i] then
                            candStrokes[i].Color = isActive and Palette.ActiveGlow or Palette.GlassEdge
                            candStrokes[i].Transparency = isActive and 0.30 or 0.72
                        end
                        btn.Visible = true
                    else
                        candKeys[i] = nil
                        btn.Visible = false
                    end
                end
            end
        end

        bindSafeTap(lockBtn, TriggerPage, function()
            Config.TriggerBot.PointerLocked = not Config.TriggerBot.PointerLocked
            UI.syncVimPointer()
            UI.refreshTriggerControls()
            ConfigStore.scheduleSave()
        end)

        bindSafeTap(centerBtn, TriggerPage, function()
            Config.TriggerBot.PointerScaleX = 0.84
            Config.TriggerBot.PointerScaleY = 0.68
            UI.syncVimPointer()
            UI.refreshTriggerControls()
            ConfigStore.scheduleSave()
        end)

        bindSafeTap(brokenBtn, TriggerPage, function()
            TriggerEngine.markCurrentCallBroken()
            UI.refreshTriggerControls()
        end)

        bindSafeTap(rescanBtn, TriggerPage, function()
            TriggerEngine.rescanAll()
            UI.refreshTriggerControls()
        end)

        bindSafeTap(resetBrokenBtn, TriggerPage, function()
            TriggerEngine.resetBrokenCalls()
            UI.refreshTriggerControls()
        end)

        table.insert(TriggerEngine.UiListeners, UI.refreshTriggerControls)
        UI.refreshTriggerControls()
    end

    addToggle(TriggerPage, 5, "Sync With Aimbot & Prediction", "Syncs lead prediction, Auto Predict, ProjectileSpeed & Aimbot target lock", function()
        return Config.TriggerBot.SyncWithAimbot
    end, function(v)
        Config.TriggerBot.SyncWithAimbot = v
    end)

    addToggle(TriggerPage, 6, "Hold Fire While Locked", "Hold trigger continuously vs timed tap shots", function()
        return Config.TriggerBot.HoldToFire
    end, function(v)
        Config.TriggerBot.HoldToFire = v
    end)

    addSectionHeader(TriggerPage, 8, "Hitbox & Timing")
    addSelector(TriggerPage, 9, "Target Part Filter", {"Any Part", "Head & Chest", "Head Only"}, function()
        return Config.TriggerBot.TargetFilter
    end, function(v)
        Config.TriggerBot.TargetFilter = v
    end, false)

    addSlider(TriggerPage, 10, "Crosshair Tolerance", 0, 28, 1, function(v)
        local n = math.round(v)
        return (n == 0) and "0 px (Exact)" or string.format("%d px", n)
    end, function()
        return Config.TriggerBot.CrosshairTolerance
    end, function(v)
        Config.TriggerBot.CrosshairTolerance = math.round(v)
    end)

    addSlider(TriggerPage, 11, "Reaction Delay", 0.00, 0.30, 0.01, function(v)
        return string.format("%.2fs", v)
    end, function()
        return Config.TriggerBot.ReactionDelay
    end, function(v)
        Config.TriggerBot.ReactionDelay = v
    end)

    addSlider(TriggerPage, 12, "Shot Cooldown", 0.02, 0.60, 0.01, function(v)
        return string.format("%.2fs", v)
    end, function()
        return Config.TriggerBot.ShotCooldown
    end, function(v)
        Config.TriggerBot.ShotCooldown = v
    end)

    addSectionHeader(TriggerPage, 13, "Checks & Reticle HUD")
    addToggle(TriggerPage, 14, "Ignore Bots (Trigger)", "Skips NPCs/bots when Trigger Bot is active", function()
        return Config.TriggerBot.IgnoreBots
    end, function(v)
        Config.TriggerBot.IgnoreBots = v
        syncWorkspaceBots()
    end)

    addToggle(TriggerPage, 15, "Trigger Team Check", "Never shoots teammates (FFA-safe Auto mode)", function()
        return Config.TriggerBot.TeamCheck
    end, function(v)
        Config.TriggerBot.TeamCheck = v
    end)

    addToggle(TriggerPage, 16, "Trigger Visible Check", "Blocks shots when enemy is behind walls", function()
        return Config.TriggerBot.VisibleCheck
    end, function(v)
        Config.TriggerBot.VisibleCheck = v
    end)

    addToggle(TriggerPage, 17, "Show Crosshair Indicator", "Center reticle dot pulses mint when target locked", function()
        return Config.TriggerBot.ShowIndicator
    end, function(v)
        Config.TriggerBot.ShowIndicator = v
    end)
end

-- 3. ESP VISUALS TAB
do
    local EspPage = TabPages["ESP"]
    addSectionHeader(EspPage, 1, "Boxes & Silhouettes")
    addToggle(EspPage, 2, "Master ESP", "Enables or disables all ESP layers", function()
        return Config.ESP.Enabled
    end, function(v)
        Config.ESP.Enabled = v
    end)

    addToggle(EspPage, 3, "Box ESP", "Projected 2D bounding box around characters", function()
        return Config.ESP.BoxESP
    end, function(v)
        Config.ESP.BoxESP = v
    end)

    addSelector(EspPage, 4, "Box Style", {"Corner", "Full"}, function()
        return Config.ESP.BoxStyle
    end, function(v)
        Config.ESP.BoxStyle = v
    end, false)

    addToggle(EspPage, 5, "Highlight ESP", "AlwaysOnTop silhouette reactive to visibility", function()
        return Config.ESP.HighlightESP
    end, function(v)
        Config.ESP.HighlightESP = v
    end)

    addToggle(EspPage, 6, "Highlight Visible Only", "Hide highlight when enemy is behind walls", function()
        return Config.ESP.HighlightVisibleOnly
    end, function(v)
        Config.ESP.HighlightVisibleOnly = v
    end)

    addSectionHeader(EspPage, 7, "Health, Name & Feet Distance")
    addToggle(EspPage, 8, "Health Bar (0% - 100%)", "Vertical sidebar health indicator beside box", function()
        return Config.ESP.HealthBar
    end, function(v)
        Config.ESP.HealthBar = v
    end)

    addToggle(EspPage, 9, "Health % Readout", "Shows numeric 0%-100% health beside bar", function()
        return Config.ESP.ShowHealthPercent
    end, function(v)
        Config.ESP.ShowHealthPercent = v
    end)

    addToggle(EspPage, 10, "Show Player Name", "Displays player or bot name above target head", function()
        return Config.ESP.ShowName
    end, function(v)
        Config.ESP.ShowName = v
    end)

    addToggle(EspPage, 11, "Distance Under Feet", "Renders stud distance directly beneath enemy feet", function()
        return Config.ESP.ShowDistance
    end, function(v)
        Config.ESP.ShowDistance = v
    end)

    addSectionHeader(EspPage, 12, "Tracers & 360° Alerts")
    addToggle(EspPage, 13, "ESP Lines (Tracers)", "Smart-anchored tracers matched to target bones", function()
        return Config.ESP.TracerESP
    end, function(v)
        Config.ESP.TracerESP = v
    end)

    addSelector(EspPage, 14, "Tracer Origin -> Anchor", {"Bottom", "Center", "Top"}, function()
        return Config.ESP.TracerOrigin
    end, function(v)
        Config.ESP.TracerOrigin = v
    end, false)

    addToggle(EspPage, 15, "360° Off-Screen Alert", "Arrows shift dynamically between Visible and Hidden", function()
        return Config.ESP.Alert360
    end, function(v)
        Config.ESP.Alert360 = v
    end)

    addToggle(EspPage, 16, "360° Alert Visible Only", "Hide 360° arrows when enemy is behind walls", function()
        return Config.ESP.Alert360VisibleOnly
    end, function(v)
        Config.ESP.Alert360VisibleOnly = v
    end)

    addSectionHeader(EspPage, 17, "ESP Filters & Visibility")
    addToggle(EspPage, 18, "Ignore Bots (ESP)", "Hides NPCs/bots from ESP boxes, tracers & highlights", function()
        return Config.ESP.IgnoreBots
    end, function(v)
        Config.ESP.IgnoreBots = v
        syncWorkspaceBots()
    end)

    addToggle(EspPage, 19, "ESP Team Check", "Hides ESP elements for teammates (FFA-safe)", function()
        return Config.ESP.TeamCheck
    end, function(v)
        Config.ESP.TeamCheck = v
    end)

    addToggle(EspPage, 20, "Master Visible Filter", "Hides all ESP completely when behind walls", function()
        return Config.ESP.VisibleCheck
    end, function(v)
        Config.ESP.VisibleCheck = v
    end)

    addToggle(EspPage, 21, "Color By Visibility", "Tints Box, Tracer & 360° Alert by line-of-sight", function()
        return Config.ESP.ColorByVisibility
    end, function(v)
        Config.ESP.ColorByVisibility = v
    end)
end

-- 4. COLORS & THICKNESS TAB
do
    local ColorsPage = TabPages["Colors"]
    addSectionHeader(ColorsPage, 1, "Live Thickness Controls (0.1 - 10.0)")

    addSlider(ColorsPage, 2, "FOV Circle Thickness", 0.1, 10.0, 0.1, function(v)
        return string.format("%.1f px", v)
    end, function()
        return Config.Aimbot.FOVThickness
    end, function(v)
        Config.Aimbot.FOVThickness = v
        applyThicknessImmediate()
    end)

    addSlider(ColorsPage, 3, "ESP Line Thickness", 0.1, 10.0, 0.1, function(v)
        return string.format("%.1f px", v)
    end, function()
        return Config.ESP.LineThickness
    end, function(v)
        Config.ESP.LineThickness = v
        applyThicknessImmediate()
    end)

    addSlider(ColorsPage, 4, "ESP Box Thickness", 0.1, 10.0, 0.1, function(v)
        return string.format("%.1f px", v)
    end, function()
        return Config.ESP.BoxThickness
    end, function(v)
        Config.ESP.BoxThickness = v
        applyThicknessImmediate()
    end)

    addSectionHeader(ColorsPage, 5, "Channel Color Editor")

    local colorChannelDefs = {
        { Key = "Visible", Label = "Visible" },
        { Key = "Hidden", Label = "Hidden" },
        { Key = "Box", Label = "Box" },
        { Key = "Tracer", Label = "Tracer" },
        { Key = "Alert360", Label = "360 Alert" },
        { Key = "FOV", Label = "FOV Ring" },
    }

    local channelCard = createCardRow(ColorsPage, 104, 6)
    local channelTitle = Instance.new("TextLabel")
    channelTitle.BackgroundTransparency = 1
    channelTitle.Position = UDim2.fromOffset(0, 0)
    channelTitle.Size = UDim2.new(1, -60, 0, 20)
    channelTitle.Font = Enum.Font.GothamMedium
    channelTitle.Text = "Active Color Channel"
    channelTitle.TextSize = 13
    channelTitle.TextColor3 = Palette.TextHeader
    channelTitle.TextXAlignment = Enum.TextXAlignment.Left
    channelTitle.ZIndex = 5
    channelTitle.Parent = channelCard

    local liveSwatch = Instance.new("Frame")
    liveSwatch.AnchorPoint = Vector2.new(1, 0)
    liveSwatch.Position = UDim2.new(1, 0, 0, 0)
    liveSwatch.Size = UDim2.fromOffset(48, 20)
    liveSwatch.BorderSizePixel = 0
    liveSwatch.ZIndex = 5
    liveSwatch.Parent = channelCard

    local swatchCorner = Instance.new("UICorner")
    swatchCorner.CornerRadius = UDim.new(0, 8)
    swatchCorner.Parent = liveSwatch

    local swatchStroke = Instance.new("UIStroke")
    swatchStroke.Thickness = 1.1
    swatchStroke.Transparency = 0.36
    swatchStroke.Color = Palette.TextHeader
    swatchStroke.Parent = liveSwatch

    local channelBar = Instance.new("Frame")
    channelBar.AnchorPoint = Vector2.new(0.5, 1)
    channelBar.Position = UDim2.new(0.5, 0, 1, 0)
    channelBar.Size = UDim2.new(1, 0, 0, 58)
    channelBar.ZIndex = 5
    channelBar.Parent = channelCard
    UI.applyFrostedSurface(channelBar, 10, Palette.GlassBase, 0.56, 0.66, false)

    local channelPad = Instance.new("UIPadding")
    channelPad.PaddingLeft = UDim.new(0, 4)
    channelPad.PaddingRight = UDim.new(0, 4)
    channelPad.PaddingTop = UDim.new(0, 4)
    channelPad.PaddingBottom = UDim.new(0, 4)
    channelPad.Parent = channelBar

    local channelGrid = Instance.new("UIGridLayout")
    channelGrid.CellSize = UDim2.new(0.333, -4, 0, 23)
    channelGrid.CellPadding = UDim2.fromOffset(4, 4)
    channelGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    channelGrid.VerticalAlignment = Enum.VerticalAlignment.Center
    channelGrid.SortOrder = Enum.SortOrder.LayoutOrder
    channelGrid.Parent = channelBar

    local channelBtns = {}
    local channelStrokes = {}
    local syncRed = nil
    local syncGreen = nil
    local syncBlue = nil

    UI.refreshColorControls = function()
        local c = Config.Colors[Config.UI.SelectedColorKey]
        liveSwatch.BackgroundColor3 = c
        for key, btn in pairs(channelBtns) do
            local active = (key == Config.UI.SelectedColorKey)
            tween(btn, 0.14, {
                BackgroundColor3 = active and Palette.PrimaryAccent or Palette.GlassBase,
                BackgroundTransparency = active and 0.28 or 1,
                TextColor3 = active and Palette.TextHeader or Palette.TextSilver,
            })
            if channelStrokes[key] then
                tween(channelStrokes[key], 0.14, {
                    Transparency = active and 0.42 or 1,
                })
            end
        end
        if syncRed then syncRed() end
        if syncGreen then syncGreen() end
        if syncBlue then syncBlue() end
        notifyColorUpdated()
    end

    for idx, def in ipairs(colorChannelDefs) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = idx
        b.Text = def.Label
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 10.5
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.ZIndex = 6
        b.Parent = channelBar

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 8)
        bc.Parent = b

        channelStrokes[def.Key] = applyGlassStroke(b, 1, 1, Palette.GlassSpecular)

        bindSafeTap(b, ColorsPage, function()
            Config.UI.SelectedColorKey = def.Key
            UI.refreshColorControls()
            ConfigStore.scheduleSave()
        end)

        channelBtns[def.Key] = b
    end

    local function updateChannelRGB(r, g, b)
        local key = Config.UI.SelectedColorKey
        local cur = Config.Colors[key]
        local nr = (r ~= nil) and r or math.round(cur.R * 255)
        local ng = (g ~= nil) and g or math.round(cur.G * 255)
        local nb = (b ~= nil) and b or math.round(cur.B * 255)
        Config.Colors[key] = Color3.fromRGB(nr, ng, nb)
        liveSwatch.BackgroundColor3 = Config.Colors[key]
        notifyColorUpdated()
        ConfigStore.scheduleSave()
    end

    syncRed = addSlider(ColorsPage, 7, "Red Channel", 0, 255, 1, function(v)
        return string.format("%d", math.round(v))
    end, function()
        return math.round(Config.Colors[Config.UI.SelectedColorKey].R * 255)
    end, function(v)
        updateChannelRGB(math.round(v), nil, nil)
    end)

    syncGreen = addSlider(ColorsPage, 8, "Green Channel", 0, 255, 1, function(v)
        return string.format("%d", math.round(v))
    end, function()
        return math.round(Config.Colors[Config.UI.SelectedColorKey].G * 255)
    end, function(v)
        updateChannelRGB(nil, math.round(v), nil)
    end)

    syncBlue = addSlider(ColorsPage, 9, "Blue Channel", 0, 255, 1, function(v)
        return string.format("%d", math.round(v))
    end, function()
        return math.round(Config.Colors[Config.UI.SelectedColorKey].B * 255)
    end, function(v)
        updateChannelRGB(nil, nil, math.round(v))
    end)

    local swatchesCard = createCardRow(ColorsPage, 68, 10)
    local swatchTitle = Instance.new("TextLabel")
    swatchTitle.BackgroundTransparency = 1
    swatchTitle.Position = UDim2.fromOffset(0, 0)
    swatchTitle.Size = UDim2.new(1, 0, 0, 18)
    swatchTitle.Font = Enum.Font.GothamMedium
    swatchTitle.Text = "Quick Color Presets"
    swatchTitle.TextSize = 13
    swatchTitle.TextColor3 = Palette.TextHeader
    swatchTitle.TextXAlignment = Enum.TextXAlignment.Left
    swatchTitle.ZIndex = 5
    swatchTitle.Parent = swatchesCard

    local swatchRow = Instance.new("Frame")
    swatchRow.AnchorPoint = Vector2.new(0.5, 1)
    swatchRow.Position = UDim2.new(0.5, 0, 1, 0)
    swatchRow.Size = UDim2.new(1, 0, 0, 26)
    swatchRow.BackgroundTransparency = 1
    swatchRow.ZIndex = 5
    swatchRow.Parent = swatchesCard

    local swatchLayout = Instance.new("UIListLayout")
    swatchLayout.FillDirection = Enum.FillDirection.Horizontal
    swatchLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    swatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    swatchLayout.Padding = UDim.new(0, 10)
    swatchLayout.Parent = swatchRow

    local presetPalette = {
        Color3.fromRGB(56, 232, 198),
        Color3.fromRGB(88, 156, 255),
        Color3.fromRGB(244, 63, 94),
        Color3.fromRGB(251, 146, 60),
        Color3.fromRGB(168, 85, 247),
        Color3.fromRGB(250, 204, 21),
        Color3.fromRGB(242, 245, 252),
        Color3.fromRGB(52, 211, 153),
    }

    for _, swatchColor in ipairs(presetPalette) do
        local sb = Instance.new("TextButton")
        sb.Size = UDim2.fromOffset(24, 24)
        sb.Text = ""
        sb.BackgroundColor3 = swatchColor
        sb.AutoButtonColor = false
        sb.BorderSizePixel = 0
        sb.ZIndex = 6
        sb.Parent = swatchRow

        local sc = Instance.new("UICorner")
        sc.CornerRadius = UDim.new(1, 0)
        sc.Parent = sb

        local ss = Instance.new("UIStroke")
        ss.Thickness = 1
        ss.Transparency = 0.45
        ss.Color = Palette.TextHeader
        ss.Parent = sb

        bindSafeTap(sb, ColorsPage, function()
            Config.Colors[Config.UI.SelectedColorKey] = swatchColor
            UI.refreshColorControls()
            ConfigStore.scheduleSave()
        end)
    end

    UI.refreshColorControls()
end

-- 5. SETTINGS, CONFIG & PERFORMANCE TAB
do
    local settingsOrder = 1

    addSectionHeader(SettingsPage, settingsOrder, "Extreme Performance (FPS)")
    settingsOrder = settingsOrder + 1

    addToggle(SettingsPage, settingsOrder, "Potato Graphics (FPS Boost)", "Min render quality, disables shadows, particles, lights & textures", function()
        return Config.Performance.PotatoGraphics
    end, function(v)
        applyPotatoGraphics(v)
    end)
    settingsOrder = settingsOrder + 1

    addSectionHeader(SettingsPage, settingsOrder, "Auto-Save Config (Per Game)")
    settingsOrder = settingsOrder + 1

    addToggle(SettingsPage, settingsOrder, "Auto-Save & Auto-Load Profile", "Saves settings & confirmed Trigger calls per game PlaceId", function()
        return Config.UI.AutoSaveConfig
    end, function(v)
        Config.UI.AutoSaveConfig = v
        if v then
            ConfigStore.saveNow()
        end
    end)
    settingsOrder = settingsOrder + 1

    do
        local profileCard = createCardRow(SettingsPage, 52, settingsOrder)
        settingsOrder = settingsOrder + 1

        local profileLbl = Instance.new("TextLabel")
        profileLbl.BackgroundTransparency = 1
        profileLbl.AnchorPoint = Vector2.new(0, 0.5)
        profileLbl.Position = UDim2.new(0, 0, 0.5, 0)
        profileLbl.Size = UDim2.new(1, -108, 0, 18)
        profileLbl.Font = Enum.Font.Code
        profileLbl.Text = State.ConfigStatusText or "Defaults"
        profileLbl.TextSize = 11
        profileLbl.TextColor3 = Palette.ActiveGlow
        profileLbl.TextXAlignment = Enum.TextXAlignment.Left
        profileLbl.TextTruncate = Enum.TextTruncate.AtEnd
        profileLbl.ZIndex = 5
        profileLbl.Parent = profileCard

        local saveNowBtn = Instance.new("TextButton")
        saveNowBtn.AnchorPoint = Vector2.new(1, 0.5)
        saveNowBtn.Position = UDim2.new(1, 0, 0.5, 0)
        saveNowBtn.Size = UDim2.fromOffset(96, 32)
        saveNowBtn.Text = "Save Now"
        saveNowBtn.Font = Enum.Font.GothamBold
        saveNowBtn.TextSize = 11
        saveNowBtn.TextColor3 = Palette.TextHeader
        saveNowBtn.BackgroundColor3 = Palette.PrimaryAccent
        saveNowBtn.BackgroundTransparency = 0.36
        saveNowBtn.AutoButtonColor = false
        saveNowBtn.BorderSizePixel = 0
        saveNowBtn.ZIndex = 6
        saveNowBtn.Parent = profileCard
        local snc = Instance.new("UICorner")
        snc.CornerRadius = UDim.new(0, 9)
        snc.Parent = saveNowBtn
        applyGlassStroke(saveNowBtn, 1, 0.48, Palette.GlassEdge)

        table.insert(ConfigStore.StatusListeners, function(txt)
            if profileLbl and profileLbl.Parent then
                profileLbl.Text = txt
            end
        end)

        bindSafeTap(saveNowBtn, SettingsPage, function()
            ConfigStore.saveNow()
            saveNowBtn.Text = "Saved!"
            task.delay(0.8, function()
                if not State.Unloaded and saveNowBtn and saveNowBtn.Parent then
                    saveNowBtn.Text = "Save Now"
                end
            end)
        end)
    end

    addSectionHeader(SettingsPage, settingsOrder, "Detection & Render Engine")
    settingsOrder = settingsOrder + 1

    addSelector(SettingsPage, settingsOrder, "Team Check Mode", {"Auto", "Team Property", "TeamColor", "Off"}, function()
        return Config.Resolver.TeamCheckMode
    end, function(v)
        Config.Resolver.TeamCheckMode = v
    end, true)
    settingsOrder = settingsOrder + 1

    if DrawingSupported then
        addSelector(SettingsPage, settingsOrder, "ESP Render Engine", {"ScreenGui", "Drawing"}, function()
            return Config.ESP.RenderEngine
        end, function(v)
            Config.ESP.RenderEngine = v
        end, false)
        settingsOrder = settingsOrder + 1
    end

    addToggle(SettingsPage, settingsOrder, "Workspace Container Scan", "Scans custom Players / Characters / Entities folders", function()
        return Config.Resolver.CustomContainerScan
    end, function(v)
        Config.Resolver.CustomContainerScan = v
        ScheduleReload("CustomContainerScanToggle", false)
    end)
    settingsOrder = settingsOrder + 1

    addToggle(SettingsPage, settingsOrder, "Ignore Transparent Glass & Water", "Allows raycast wall check through glass/water", function()
        return Config.ESP.IgnoreGlassWater
    end, function(v)
        Config.ESP.IgnoreGlassWater = v
    end)
    settingsOrder = settingsOrder + 1

    addSectionHeader(SettingsPage, settingsOrder, "Floating Quick Buttons & Limits")
    settingsOrder = settingsOrder + 1

    addToggle(SettingsPage, settingsOrder, "Show Aim Lock GUI Button", "Displays floating draggable Aim Lock ON/OFF button", function()
        return Config.UI.ShowMobileAimButton
    end, function(v)
        Config.UI.ShowMobileAimButton = v
    end)
    settingsOrder = settingsOrder + 1

    addToggle(SettingsPage, settingsOrder, "Show Trigger Bot GUI Button", "Displays floating draggable Trigger ON/OFF button", function()
        return Config.UI.ShowMobileTriggerButton
    end, function(v)
        Config.UI.ShowMobileTriggerButton = v
    end)
    settingsOrder = settingsOrder + 1

    addSlider(SettingsPage, settingsOrder, "Max Render Distance", 200, 3500, 50, function(v)
        return string.format("%dm", math.round(v))
    end, function()
        return Config.ESP.MaxDistance
    end, function(v)
        Config.ESP.MaxDistance = v
        Config.Aimbot.MaxDistance = v
    end)
    settingsOrder = settingsOrder + 1

    addSlider(SettingsPage, settingsOrder, "360° Alert Ring Radius", 80, 280, 5, function(v)
        return string.format("%d px", math.round(v))
    end, function()
        return Config.ESP.AlertRingRadius
    end, function(v)
        Config.ESP.AlertRingRadius = v
    end)
    settingsOrder = settingsOrder + 1

    addSectionHeader(SettingsPage, settingsOrder, "System Actions")
    settingsOrder = settingsOrder + 1

    local actionCard = createCardRow(SettingsPage, 56, settingsOrder)
    local actionGrid = Instance.new("UIGridLayout")
    actionGrid.CellSize = UDim2.new(0.333, -6, 1, 0)
    actionGrid.CellPadding = UDim2.fromOffset(8, 0)
    actionGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    actionGrid.VerticalAlignment = Enum.VerticalAlignment.Center
    actionGrid.Parent = actionCard

    ForceReloadBtn = Instance.new("TextButton")
    ForceReloadBtn.Text = "Reload All"
    ForceReloadBtn.Font = Enum.Font.GothamMedium
    ForceReloadBtn.TextSize = 11.5
    ForceReloadBtn.TextColor3 = Palette.TextHeader
    ForceReloadBtn.BackgroundColor3 = Palette.PrimaryAccent
    ForceReloadBtn.BackgroundTransparency = 0.38
    ForceReloadBtn.AutoButtonColor = false
    ForceReloadBtn.BorderSizePixel = 0
    ForceReloadBtn.ZIndex = 6
    ForceReloadBtn.Parent = actionCard
    local frc = Instance.new("UICorner")
    frc.CornerRadius = UDim.new(0, 10)
    frc.Parent = ForceReloadBtn
    applyGlassStroke(ForceReloadBtn, 1, 0.52, Palette.GlassEdge)

    ResetBtn = Instance.new("TextButton")
    ResetBtn.Text = "Reset Defaults"
    ResetBtn.Font = Enum.Font.GothamMedium
    ResetBtn.TextSize = 11.5
    ResetBtn.TextColor3 = Palette.TextHeader
    ResetBtn.BackgroundColor3 = Palette.SurfaceSoft
    ResetBtn.BackgroundTransparency = 0.44
    ResetBtn.AutoButtonColor = false
    ResetBtn.BorderSizePixel = 0
    ResetBtn.ZIndex = 6
    ResetBtn.Parent = actionCard
    local rc = Instance.new("UICorner")
    rc.CornerRadius = UDim.new(0, 10)
    rc.Parent = ResetBtn
    applyGlassStroke(ResetBtn, 1, 0.58, Palette.GlassEdge)

    UnloadBtn = Instance.new("TextButton")
    UnloadBtn.Text = "Unload AKI"
    UnloadBtn.Font = Enum.Font.GothamMedium
    UnloadBtn.TextSize = 11.5
    UnloadBtn.TextColor3 = Palette.TextHeader
    UnloadBtn.BackgroundColor3 = Palette.Danger
    UnloadBtn.BackgroundTransparency = 0.34
    UnloadBtn.AutoButtonColor = false
    UnloadBtn.BorderSizePixel = 0
    UnloadBtn.ZIndex = 6
    UnloadBtn.Parent = actionCard
    local uc = Instance.new("UICorner")
    uc.CornerRadius = UDim.new(0, 10)
    uc.Parent = UnloadBtn
    applyGlassStroke(UnloadBtn, 1, 0.52, Palette.Danger)
end
end -- end populateAllTabs

populateAllTabs()

-- ============================================================================
-- [SECTION 12] FLOATING MOBILE PILL BUTTONS, VIM POINTER & CLEAN UNLOAD
-- ============================================================================
local MobileToggle = Instance.new("TextButton")
MobileToggle.Name = "TEAM_AKI_MobileToggle"
MobileToggle.AnchorPoint = Vector2.new(0, 0.5)
MobileToggle.Position = UDim2.new(0, 18, 0.25, 0)
MobileToggle.Size = UDim2.fromOffset(124, 40)
MobileToggle.Font = Enum.Font.GothamBold
MobileToggle.Text = "TEAM AKI"
MobileToggle.TextSize = 13
MobileToggle.TextColor3 = Palette.TextHeader
MobileToggle.AutoButtonColor = false
MobileToggle.Active = true
MobileToggle.Draggable = false
MobileToggle.Visible = false
MobileToggle.ZIndex = 20
MobileToggle.Parent = MainGui

local ToggleStroke = UI.applyFrostedSurface(MobileToggle, -1, Palette.GlassBase, 0.34, 0.36, true)
ToggleStroke.Thickness = 1.4
ToggleStroke.Color = Palette.ActiveGlow

local MobileAimBtn = Instance.new("TextButton")
MobileAimBtn.Name = "TEAM_AKI_MobileAim"
MobileAimBtn.AnchorPoint = Vector2.new(0, 0.5)
MobileAimBtn.Position = UDim2.new(0, 18, 0.25, 50)
MobileAimBtn.Size = UDim2.fromOffset(138, 40)
MobileAimBtn.Font = Enum.Font.GothamBold
MobileAimBtn.Text = "AIM LOCK: OFF"
MobileAimBtn.TextSize = 12
MobileAimBtn.TextColor3 = Palette.TextSilver
MobileAimBtn.AutoButtonColor = false
MobileAimBtn.Active = true
MobileAimBtn.Draggable = false
MobileAimBtn.Visible = false
MobileAimBtn.ZIndex = 20
MobileAimBtn.Parent = MainGui

local AimBtnStroke = UI.applyFrostedSurface(MobileAimBtn, -1, Palette.GlassBase, 0.34, 0.44, true)
AimBtnStroke.Thickness = 1.4

local function refreshMobileAimStyle()
    local locked = Config.Aimbot.Enabled
    Config.UI.MobileAimLocked = locked
    MobileAimBtn.Text = locked and "AIM LOCK: ON" or "AIM LOCK: OFF"
    tween(MobileAimBtn, 0.15, {
        TextColor3 = locked and Palette.ActiveGlow or Palette.TextSilver,
        BackgroundColor3 = locked and Color3.fromRGB(16, 46, 52) or Palette.GlassBase,
        BackgroundTransparency = locked and 0.28 or 0.34,
    })
    tween(AimBtnStroke, 0.15, {
        Color = locked and Palette.ActiveGlow or Palette.GlassEdge,
        Transparency = locked and 0.24 or 0.44,
    })
end

syncMobileAimVisibility = function()
    if not UI.LoaderGui then
        MobileAimBtn.Visible = Config.UI.ShowMobileAimButton
    end
    refreshMobileAimStyle()
end

local MobileTriggerBtn = Instance.new("TextButton")
MobileTriggerBtn.Name = "TEAM_AKI_MobileTrigger"
MobileTriggerBtn.AnchorPoint = Vector2.new(0, 0.5)
MobileTriggerBtn.Position = UDim2.new(0, 18, 0.25, 100)
MobileTriggerBtn.Size = UDim2.fromOffset(138, 40)
MobileTriggerBtn.Font = Enum.Font.GothamBold
MobileTriggerBtn.Text = "TRIGGER: OFF"
MobileTriggerBtn.TextSize = 12
MobileTriggerBtn.TextColor3 = Palette.TextSilver
MobileTriggerBtn.AutoButtonColor = false
MobileTriggerBtn.Active = true
MobileTriggerBtn.Draggable = false
MobileTriggerBtn.Visible = false
MobileTriggerBtn.ZIndex = 20
MobileTriggerBtn.Parent = MainGui

local TriggerBtnStroke = UI.applyFrostedSurface(MobileTriggerBtn, -1, Palette.GlassBase, 0.34, 0.44, true)
TriggerBtnStroke.Thickness = 1.4

local function refreshMobileTriggerStyle()
    local on = Config.TriggerBot.Enabled
    Config.UI.MobileTriggerLocked = on
    MobileTriggerBtn.Text = on and "TRIGGER: ON" or "TRIGGER: OFF"
    tween(MobileTriggerBtn, 0.15, {
        TextColor3 = on and Palette.Amber or Palette.TextSilver,
        BackgroundColor3 = on and Color3.fromRGB(48, 30, 18) or Palette.GlassBase,
        BackgroundTransparency = on and 0.28 or 0.34,
    })
    tween(TriggerBtnStroke, 0.15, {
        Color = on and Palette.Amber or Palette.GlassEdge,
        Transparency = on and 0.24 or 0.44,
    })
end

syncMobileTriggerVisibility = function()
    if not UI.LoaderGui then
        MobileTriggerBtn.Visible = Config.UI.ShowMobileTriggerButton
    end
    refreshMobileTriggerStyle()
end

local function makeDraggableButton(btn, onTap)
    local activeInput = nil
    local movedDist = 0
    local dragStart = nil
    local startPos = nil

    local function resetButtonDrag()
        activeInput = nil
        dragStart = nil
        startPos = nil
        InputGuard.endDrag(btn)
    end

    btn.InputBegan:Connect(function(input)
        if activeInput or not btn.Visible then
            return
        end
        if input.UserInputState ~= Enum.UserInputState.Begin then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if not InputGuard.isPointInGui(btn, input.Position, 6) then
            return
        end
        if InputGuard.beginDrag(btn, input) then
            activeInput = input
            movedDist = 0
            dragStart = input.Position
            startPos = btn.Position
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not activeInput or not dragStart or not startPos then
            return
        end
        if not btn.Visible then
            resetButtonDrag()
            return
        end
        if not InputGuard.isOwner(btn, input) then
            if not InputGuard.isActiveState(activeInput.UserInputState) then
                resetButtonDrag()
            end
            return
        end
        local scale = math.max(RootScale.Scale, 0.5)
        local delta = (input.Position - dragStart) / scale
        if delta.Magnitude > movedDist then
            movedDist = delta.Magnitude
        end
        if movedDist > 6 then
            local nextX = startPos.X.Offset + delta.X
            local nextY = startPos.Y.Offset + delta.Y
            local cam = Workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize / scale
                local btnW = btn.Size.X.Offset
                local btnH = btn.Size.Y.Offset
                local minX = -(startPos.X.Scale * vp.X) + 6
                local maxX = ((1 - startPos.X.Scale) * vp.X) - btnW - 6
                local minY = -(startPos.Y.Scale * vp.Y) + (btnH * 0.5) + 6
                local maxY = ((1 - startPos.Y.Scale) * vp.Y) - (btnH * 0.5) - 6
                if maxX >= minX then
                    nextX = math.clamp(nextX, minX, maxX)
                end
                if maxY >= minY then
                    nextY = math.clamp(nextY, minY, maxY)
                end
            end
            btn.Position = UDim2.new(
                startPos.X.Scale,
                nextX,
                startPos.Y.Scale,
                nextY
            )
        end
    end))

    local function finishButtonInput(input)
        if not activeInput then
            return
        end
        if input == activeInput or not InputGuard.isActiveState(activeInput.UserInputState) then
            local wasTap = (input == activeInput) and (movedDist <= 7) and btn.Visible
            resetButtonDrag()
            if wasTap then
                onTap()
            end
        end
    end

    addConnection(UserInputService.InputEnded:Connect(finishButtonInput))
    addConnection(UserInputService.TouchEnded:Connect(finishButtonInput))

    addConnection(btn:GetPropertyChangedSignal("Visible"):Connect(function()
        if not btn.Visible and activeInput then
            resetButtonDrag()
        end
    end))
end

-- Floating VirtualInputManager Pointer Reticle (1:1 in OverlayGui; passes finger touches through when Locked)
do
    local vimPointer = Instance.new("Frame")
    vimPointer.Name = "TEAM_AKI_VimPointer"
    vimPointer.AnchorPoint = Vector2.new(0.5, 0.5)
    vimPointer.Size = UDim2.fromOffset(54, 54)
    vimPointer.Position = UDim2.fromScale(Config.TriggerBot.PointerScaleX, Config.TriggerBot.PointerScaleY)
    vimPointer.BackgroundColor3 = Palette.GlassBase
    vimPointer.BackgroundTransparency = 0.62
    vimPointer.BorderSizePixel = 0
    vimPointer.Active = false
    vimPointer.Draggable = false
    vimPointer.Visible = false
    vimPointer.ZIndex = 12
    vimPointer.Parent = OverlayGui

    local vpCorner = Instance.new("UICorner")
    vpCorner.CornerRadius = UDim.new(1, 0)
    vpCorner.Parent = vimPointer

    local vpStroke = Instance.new("UIStroke")
    vpStroke.Thickness = 2
    vpStroke.Color = Palette.ActiveGlow
    vpStroke.Transparency = 0.22
    vpStroke.Parent = vimPointer

    local innerDot = Instance.new("Frame")
    innerDot.AnchorPoint = Vector2.new(0.5, 0.5)
    innerDot.Position = UDim2.fromScale(0.5, 0.5)
    innerDot.Size = UDim2.fromOffset(9, 9)
    innerDot.BackgroundColor3 = Palette.ActiveGlow
    innerDot.BorderSizePixel = 0
    innerDot.Active = false
    innerDot.ZIndex = 13
    innerDot.Parent = vimPointer

    local idc = Instance.new("UICorner")
    idc.CornerRadius = UDim.new(1, 0)
    idc.Parent = innerDot

    local vpTag = Instance.new("TextLabel")
    vpTag.BackgroundColor3 = Palette.GlassBase
    vpTag.BackgroundTransparency = 0.44
    vpTag.BorderSizePixel = 0
    vpTag.AnchorPoint = Vector2.new(0.5, 0)
    vpTag.Position = UDim2.new(0.5, 0, 1, 4)
    vpTag.Size = UDim2.fromOffset(88, 16)
    vpTag.Font = Enum.Font.GothamBold
    vpTag.Text = "VIM FIRE"
    vpTag.TextSize = 9.5
    vpTag.TextColor3 = Palette.ActiveGlow
    vpTag.TextStrokeTransparency = 0.35
    vpTag.TextStrokeColor3 = Color3.new(0, 0, 0)
    vpTag.Active = false
    vpTag.ZIndex = 13
    vpTag.Parent = vimPointer

    local vpTagCorner = Instance.new("UICorner")
    vpTagCorner.CornerRadius = UDim.new(1, 0)
    vpTagCorner.Parent = vpTag

    UI.syncVimPointer = function()
        local isVim = (Config.TriggerBot.Mode == "VirtualInputManager")
        local unlocked = not Config.TriggerBot.PointerLocked
        local shouldShow = (not UI.LoaderGui) and isVim and (Config.TriggerBot.Enabled or unlocked)
        vimPointer.Visible = shouldShow
        vimPointer.Position = UDim2.fromScale(Config.TriggerBot.PointerScaleX, Config.TriggerBot.PointerScaleY)
        -- Critical: Active = false passes all finger touches directly to the real game button underneath!
        vimPointer.Active = unlocked and isVim
        vimPointer.BackgroundTransparency = unlocked and 0.38 or 0.72
        vpStroke.Color = unlocked and Palette.Amber or Palette.ActiveGlow
        vpStroke.Transparency = unlocked and 0.12 or 0.34
        innerDot.BackgroundColor3 = unlocked and Palette.Amber or Palette.ActiveGlow
        vpTag.Text = unlocked and "DRAG TO BTN" or "VIM LOCKED"
        vpTag.TextColor3 = unlocked and Palette.Amber or Palette.ActiveGlow
    end

    local dragInput = nil

    local function clearPointerDrag(shouldSave)
        local hadDrag = (dragInput ~= nil)
        dragInput = nil
        InputGuard.endDrag(vimPointer)
        if shouldSave and hadDrag then
            pcall(UI.refreshTriggerControls)
            ConfigStore.scheduleSave()
        end
    end

    vimPointer.InputBegan:Connect(function(input)
        if Config.TriggerBot.PointerLocked or not vimPointer.Visible or dragInput then
            return
        end
        if input.UserInputState ~= Enum.UserInputState.Begin then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        if not InputGuard.isPointInGui(vimPointer, input.Position, 8) then
            return
        end
        if InputGuard.beginDrag(vimPointer, input) then
            dragInput = input
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if not dragInput then
            return
        end
        if Config.TriggerBot.PointerLocked or not vimPointer.Visible then
            clearPointerDrag(false)
            return
        end
        if not InputGuard.isOwner(vimPointer, input) then
            if not InputGuard.isActiveState(dragInput.UserInputState) then
                clearPointerDrag(true)
            end
            return
        end
        local cam = State.Camera or Workspace.CurrentCamera
        local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
        if vp.X > 0 and vp.Y > 0 then
            Config.TriggerBot.PointerScaleX = math.clamp(input.Position.X / vp.X, 0.04, 0.96)
            Config.TriggerBot.PointerScaleY = math.clamp(input.Position.Y / vp.Y, 0.06, 0.94)
            vimPointer.Position = UDim2.fromScale(Config.TriggerBot.PointerScaleX, Config.TriggerBot.PointerScaleY)
        end
    end))

    local function finishPointerInput(input)
        if dragInput and (input == dragInput or not InputGuard.isActiveState(dragInput.UserInputState)) then
            clearPointerDrag(true)
        end
    end

    addConnection(UserInputService.InputEnded:Connect(finishPointerInput))
    addConnection(UserInputService.TouchEnded:Connect(finishPointerInput))

    addConnection(vimPointer:GetPropertyChangedSignal("Visible"):Connect(function()
        if not vimPointer.Visible and dragInput then
            clearPointerDrag(false)
        end
    end))
end

local function setPanelVisible(visible)
    Config.UI.Visible = visible
    if visible then
        MainCard.Visible = true
        CardShadow.Visible = true
        MainCard.Size = UDim2.fromOffset(BASE_CARD_W - 24, BASE_CARD_H - 24)
        MainCard.BackgroundTransparency = 0.68
        CardShadow.BackgroundTransparency = 0.88
        tween(MainCard, 0.22, {
            Size = UDim2.fromOffset(BASE_CARD_W, BASE_CARD_H),
            BackgroundTransparency = 0.38,
        })
        tween(CardShadow, 0.22, {BackgroundTransparency = 0.68})
        tween(ToggleStroke, 0.18, {Color = Palette.ActiveGlow})
    else
        local tw = tween(MainCard, 0.16, {
            Size = UDim2.fromOffset(BASE_CARD_W - 24, BASE_CARD_H - 24),
            BackgroundTransparency = 0.86,
        })
        tween(CardShadow, 0.16, {BackgroundTransparency = 1})
        local completedConn
        completedConn = tw.Completed:Connect(function()
            if completedConn then
                completedConn:Disconnect()
            end
            if not Config.UI.Visible then
                MainCard.Visible = false
                CardShadow.Visible = false
            end
        end)
        tween(ToggleStroke, 0.18, {Color = Palette.GlassEdge})
    end
end

makeDraggableButton(MobileToggle, function()
    setPanelVisible(not Config.UI.Visible)
end)

makeDraggableButton(MobileAimBtn, function()
    local nextState = not Config.Aimbot.Enabled
    Config.Aimbot.Enabled = nextState
    Config.UI.MobileAimLocked = nextState
    if nextState and Config.Aimbot.ActivationMode == "Hold" then
        Config.Aimbot.ActivationMode = "GUI Toggle"
    end
    for _, sync in ipairs(SyncCallbacks) do
        pcall(sync)
    end
    SyncDependentSettings(false)
end)

makeDraggableButton(MobileTriggerBtn, function()
    local nextState = not Config.TriggerBot.Enabled
    Config.TriggerBot.Enabled = nextState
    Config.UI.MobileTriggerLocked = nextState
    if nextState and (Config.TriggerBot.Mode == "firesignal" or Config.TriggerBot.Mode == "Tool:Activate()") then
        task.defer(TriggerEngine.rescanAll)
    end
    for _, sync in ipairs(SyncCallbacks) do
        pcall(sync)
    end
    SyncDependentSettings(false)
end)

if UI.MinimizeBtn then
    bindSafeTap(UI.MinimizeBtn, nil, function()
        setPanelVisible(false)
    end)
end

addConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        setPanelVisible(not Config.UI.Visible)
    end
end))

bindSafeTap(ForceReloadBtn, SettingsPage, function()
    ReloadAllSystems("ManualButton", true)
    ForceReloadBtn.Text = "Reloaded!"
    task.delay(0.8, function()
        if not State.Unloaded and ForceReloadBtn and ForceReloadBtn.Parent then
            ForceReloadBtn.Text = "Reload All"
        end
    end)
end)

bindSafeTap(ResetBtn, SettingsPage, function()
    for _, secName in ipairs({"Aimbot", "TriggerBot", "ESP", "Resolver", "Performance", "Colors"}) do
        for k, v in pairs(DefaultConfig[secName]) do
            if type(v) == "table" then
                Config[secName][k] = {}
            else
                Config[secName][k] = v
            end
        end
    end
    applyPotatoGraphics(Config.Performance.PotatoGraphics)
    Config.UI.ShowMobileAimButton = true
    Config.UI.MobileAimLocked = false
    Config.UI.ShowMobileTriggerButton = true
    Config.UI.MobileTriggerLocked = false
    Config.UI.AutoSaveConfig = true
    for _, sync in ipairs(SyncCallbacks) do
        pcall(sync)
    end
    if UI.refreshColorControls then
        UI.refreshColorControls()
    end
    applyThicknessImmediate()
    SyncDependentSettings(true, "ResetDefaults", true)
    ConfigStore.saveNow()
    ResetBtn.Text = "Reset!"
    task.delay(0.8, function()
        if not State.Unloaded and ResetBtn and ResetBtn.Parent then
            ResetBtn.Text = "Reset Defaults"
        end
    end)
end)

local function unloadScript()
    if State.Unloaded then
        return
    end
    State.Unloaded = true
    State.ReloadToken = State.ReloadToken + 1
    releaseTriggerFire()
    pcall(InputGuard.forceReleaseAll)

    pcall(applyPotatoGraphics, false)

    pcall(function()
        RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
    end)

    clearLocalCharacterState()

    for _, conn in ipairs(State.Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    clearTable(State.Connections)

    local trackedCopy = {}
    for targetKey in pairs(Registry) do
        table.insert(trackedCopy, targetKey)
    end
    for _, targetKey in ipairs(trackedCopy) do
        destroyPlayerEntry(targetKey)
    end
    clearTable(Registry)

    safeDestroyDrawing(DrawingFOV)
    DrawingFOV = nil

    if UI.LoaderGui then
        pcall(function()
            UI.LoaderGui:Destroy()
        end)
        UI.LoaderGui = nil
    end

    pcall(function()
        HighlightContainer:Destroy()
    end)
    pcall(function()
        OverlayGui:Destroy()
    end)
    pcall(function()
        MainGui:Destroy()
    end)

    if globalEnv.TEAM_AKI_UNLOAD == unloadScript then
        globalEnv.TEAM_AKI_UNLOAD = nil
    end
end

globalEnv.TEAM_AKI_UNLOAD = unloadScript

if UI.UnloadHeaderBtn then
    bindSafeTap(UI.UnloadHeaderBtn, nil, unloadScript)
end
bindSafeTap(UnloadBtn, SettingsPage, unloadScript)

UI.runStartupLoader(function()
    MobileToggle.Visible = true
    syncMobileAimVisibility()
    syncMobileTriggerVisibility()
    UI.syncVimPointer()
    setPanelVisible(true)
end)
