--[[
    ============================================================================
      TEAM AKI — Universal Adaptive Glassmorphic Hub (Mobile Roblox Executor)
      Executors : Delta, Arceus X, Fluxus, Krnl & Universal Luau Executors
      Systems   : Triple-Layer Entity Scanner, Adaptive Team/Game Resolver,
                  Pooled Drawing + ScreenGui Hybrid ESP, Kinematic Prediction
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

if type(globalEnv.TEAM_AKI_UNLOAD) == "function" then
    pcall(globalEnv.TEAM_AKI_UNLOAD)
end

local clonerefFn = (type(cloneref) == "function" and cloneref) or function(obj)
    return obj
end

local function getService(name)
    return clonerefFn(game:GetService(name))
end

local Players = getService("Players")
local RunService = getService("RunService")
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local Workspace = getService("Workspace")
local CoreGui = getService("CoreGui")
local Teams = getService("Teams")
local StatsService = nil
pcall(function()
    StatsService = getService("Stats")
end)

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    Players.PlayerAdded:Wait()
    LocalPlayer = Players.LocalPlayer
end

local function shallowClone(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

local function clearTable(tbl)
    for k in pairs(tbl) do
        tbl[k] = nil
    end
end

local function getSafeGuiParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then
            return hui
        end
    end
    local okCore = pcall(function()
        return CoreGui.Name
    end)
    if okCore then
        return CoreGui
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function protectGui(gui)
    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    elseif type(protect_gui) == "function" then
        pcall(protect_gui, gui)
    end
end

-- ============================================================================
-- [SECTION 2] CONFIGURATION & RUNTIME STATE
-- ============================================================================
local Config = {
    Aimbot = {
        Enabled = false,
        ActivationMode = "Always",      -- "Always" | "Hold" | "Mobile Button"
        TargetPart = "Head",            -- "Head" | "Chest/Torso" | "HumanoidRootPart" | "Closest"
        Smoothness = 6,                 -- 1 (instant lock) .. 20 (humanized smooth)
        PredictionStrength = 0.08,      -- 0.00 .. 0.30 seconds lead time
        ProjectileSpeed = 0,            -- 0 = pure lead time; >0 adds Distance / Speed
        PingCompensation = false,       -- Adds half-RTT network ping lead
        FOVRadius = 135,                -- pixels
        FOVThickness = 1.8,             -- 1 .. 5 pixels
        ShowFOV = true,
        TeamCheck = true,
        VisibleCheck = true,
        StickyTarget = true,
        MaxDistance = 1500,
    },
    ESP = {
        Enabled = true,
        RenderEngine = "Auto",          -- "Auto" (Drawing when available) | "Drawing" | "ScreenGui"
        BoxESP = true,
        BoxStyle = "Corner",            -- "Corner" | "Full"
        BoxThickness = 1.8,             -- 1 .. 5 pixels
        HealthBar = true,
        ShowHealthPercent = true,
        TracerESP = true,
        TracerOrigin = "Bottom",        -- "Bottom" -> Feet | "Center" -> Chest | "Top" -> Head
        LineThickness = 1.5,            -- 1 .. 5 pixels
        Alert360 = true,
        Alert360VisibleOnly = false,
        AlertRingRadius = 155,
        HighlightESP = true,
        HighlightVisibleOnly = false,
        TeamCheck = true,
        VisibleCheck = false,
        ColorByVisibility = true,
        ShowNameDistance = true,
        IgnoreGlassWater = true,
        MaxDistance = 1800,
        HighlightFillTransparency = 0.66,
        HighlightOutlineTransparency = 0.12,
    },
    Resolver = {
        TeamCheckMode = "Auto",         -- "Auto" | "Team Property" | "TeamColor" | "Off"
        CustomContainerScan = true,     -- Scans Workspace.Players / Characters / Entities
    },
    Colors = {
        Visible = Color3.fromRGB(56, 232, 198),     -- Mint-Cyan (Unobstructed)
        Hidden = Color3.fromRGB(244, 63, 94),       -- Crimson (Behind Wall / Cover)
        BoxTracer = Color3.fromRGB(88, 156, 255),   -- Electric Cyan-Indigo
        FOV = Color3.fromRGB(110, 165, 255),        -- Ice-Cyan FOV Circle
    },
    UI = {
        Visible = true,
        ActiveTab = "Aimbot",
        SelectedColorKey = "Visible",
        ShowMobileAimButton = false,
        MobileAimLocked = false,
    },
}

local DefaultConfig = {
    Aimbot = shallowClone(Config.Aimbot),
    ESP = shallowClone(Config.ESP),
    Resolver = shallowClone(Config.Resolver),
    Colors = shallowClone(Config.Colors),
}

local State = {
    Unloaded = false,
    Connections = {},
    TrackedPlayers = {},
    CurrentAimTarget = nil,
    IsHoldingAim = false,
    ColorListeners = {},
    LastReconcileTime = 0,
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

-- ============================================================================
-- [SECTION 3] POOLED DRAWING & SCREENGUI OVERLAY ENGINE
-- ============================================================================
local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "TEAM_AKI_Overlay"
OverlayGui.IgnoreGuiInset = true
OverlayGui.ResetOnSpawn = false
OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
OverlayGui.DisplayOrder = 999
protectGui(OverlayGui)
OverlayGui.Parent = getSafeGuiParent()

local EspContainer = Instance.new("Folder")
EspContainer.Name = "ESP_Elements"
EspContainer.Parent = OverlayGui

-- Highlight instances require CoreGui or Workspace ancestry to render consistently
local HighlightContainer = Instance.new("Folder")
HighlightContainer.Name = "TEAM_AKI_Highlights"
local okHighlightParent = pcall(function()
    HighlightContainer.Parent = CoreGui
end)
if not okHighlightParent or not HighlightContainer.Parent then
    HighlightContainer.Parent = Workspace
end

-- Probe native Drawing API safely (handles both table and userdata implementations)
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
    if not DrawingSupported then
        return false
    end
    if Config.ESP.RenderEngine == "ScreenGui" then
        return false
    end
    return true
end

-- Pre-allocate pooled FOV Circle Drawing if supported, plus ScreenGui fallback ring
local DrawingFOV = nil
if DrawingSupported then
    pcall(function()
        local ring = Drawing.new("Circle")
        ring.Visible = false
        ring.Filled = false
        ring.NumSides = 64
        ring.Transparency = 0.88
        ring.Thickness = Config.Aimbot.FOVThickness
        ring.Color = Config.Colors.FOV
        DrawingFOV = ring
    end)
end

local FOVRingFrame = Instance.new("Frame")
FOVRingFrame.Name = "FOVRing"
FOVRingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
FOVRingFrame.Position = UDim2.fromScale(0.5, 0.5)
FOVRingFrame.BackgroundTransparency = 1
FOVRingFrame.Visible = false
FOVRingFrame.Parent = OverlayGui

local FOVCorner = Instance.new("UICorner")
FOVCorner.CornerRadius = UDim.new(1, 0)
FOVCorner.Parent = FOVRingFrame

local FOVStroke = Instance.new("UIStroke")
FOVStroke.Thickness = Config.Aimbot.FOVThickness
FOVStroke.Transparency = 0.2
FOVStroke.Color = Config.Colors.FOV
FOVStroke.Parent = FOVRingFrame

-- Pre-allocate pooled per-player Drawing + ScreenGui visual elements (zero allocation in RenderStepped)
local function createPlayerVisuals()
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
    fullBoxStroke.Color = Config.Colors.BoxTracer
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

    -- Pre-allocate Drawing primitives at player registration time (never inside RenderStepped)
    local drawCache = nil
    if DrawingSupported then
        local ok, cache = pcall(function()
            local c = {
                Box = Drawing.new("Square"),
                Corners = {},
                HpBack = Drawing.new("Square"),
                HpFill = Drawing.new("Square"),
                HpText = Drawing.new("Text"),
                Tracer = Drawing.new("Line"),
                Arrow = Drawing.new("Triangle"),
                Label = Drawing.new("Text"),
            }
            c.Box.Visible = false
            c.Box.Filled = false
            for i = 1, 8 do
                local ln = Drawing.new("Line")
                ln.Visible = false
                c.Corners[i] = ln
            end
            c.HpBack.Visible = false
            c.HpBack.Filled = true
            c.HpBack.Color = Color3.fromRGB(11, 13, 20)
            c.HpFill.Visible = false
            c.HpFill.Filled = true

            c.HpText.Visible = false
            c.HpText.Center = false
            c.HpText.Outline = true
            c.HpText.Size = 11
            c.HpText.Color = Color3.fromRGB(242, 245, 252)

            c.Tracer.Visible = false
            c.Arrow.Visible = false
            c.Arrow.Filled = true
            c.Arrow.Thickness = 1

            c.Label.Visible = false
            c.Label.Center = true
            c.Label.Outline = true
            c.Label.Size = 13

            if Drawing.Fonts and Drawing.Fonts.UI then
                c.Label.Font = Drawing.Fonts.UI
                c.HpText.Font = Drawing.Fonts.Monospace or Drawing.Fonts.UI
            else
                c.Label.Font = 2
                c.HpText.Font = 2
            end
            return c
        end)
        if ok and cache then
            drawCache = cache
        end
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
            drawCache.HpText.Visible = false
            drawCache.Tracer.Visible = false
            drawCache.Arrow.Visible = false
            drawCache.Label.Visible = false
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
        arrowHolder.Visible = false
    end

    return {
        HideAll = function()
            hideGui()
            hideDrawing()
        end,
        Render = function(self, state)
            local useDraw = shouldUseDrawing() and drawCache ~= nil
            if useDraw then
                hideGui()
                local d = drawCache
                pcall(function()
                    -- 1. Box (Corner Brackets or Full Box)
                    if state.ShowBox then
                        local x, y, w, h = state.BX, state.BY, state.BW, state.BH
                        local t = state.BoxThickness
                        local col = state.BoxColor
                        if state.BoxStyle == "Full" then
                            d.Box.Visible = true
                            d.Box.Position = Vector2.new(x, y)
                            d.Box.Size = Vector2.new(w, h)
                            d.Box.Color = col
                            d.Box.Thickness = t
                            for i = 1, 8 do d.Corners[i].Visible = false end
                        else
                            d.Box.Visible = false
                            local cw = math.clamp(w * 0.25, 4, 24)
                            local ch = math.clamp(h * 0.22, 4, 24)
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
                            end
                        end
                    else
                        d.Box.Visible = false
                        for i = 1, 8 do d.Corners[i].Visible = false end
                    end

                    -- 2. Vertical Health Bar (0% - 100%) + Optional % Readout
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

                        if state.ShowHealthText and state.BH >= 16 then
                            d.HpText.Visible = true
                            d.HpText.Text = string.format("%d%%", math.round(state.HealthRatio * 100))
                            d.HpText.Color = state.HealthColor
                            d.HpText.Position = Vector2.new(barX - 30, math.clamp(barY + (barH - fillH) - 6, barY - 2, barY + barH - 10))
                        else
                            d.HpText.Visible = false
                        end
                    else
                        d.HpBack.Visible = false
                        d.HpFill.Visible = false
                        d.HpText.Visible = false
                    end

                    -- 3. Name & Distance Label
                    if state.ShowLabel then
                        d.Label.Visible = true
                        d.Label.Position = Vector2.new(state.BX + state.BW * 0.5, state.BY - 16)
                        d.Label.Text = state.LabelText
                        d.Label.Color = state.BoxColor
                    else
                        d.Label.Visible = false
                    end

                    -- 4. Smart Anchor-Matched Tracer Line
                    if state.ShowTracer then
                        d.Tracer.Visible = true
                        d.Tracer.From = state.TracerFrom
                        d.Tracer.To = state.TracerTo
                        d.Tracer.Color = state.TracerColor
                        d.Tracer.Thickness = state.LineThickness
                    else
                        d.Tracer.Visible = false
                    end

                    -- 5. 360-Degree Visibility-Reactive Off-Screen Alert Arrow
                    if state.ShowArrow then
                        local dir = Vector2.new(math.cos(state.ArrowAngle), math.sin(state.ArrowAngle))
                        local perp = Vector2.new(-dir.Y, dir.X)
                        local tip = state.ArrowPos
                        local baseCenter = tip - dir * 14
                        d.Arrow.Visible = true
                        d.Arrow.PointA = tip
                        d.Arrow.PointB = baseCenter + perp * 7
                        d.Arrow.PointC = baseCenter - perp * 7
                        d.Arrow.Color = state.ArrowColor
                    else
                        d.Arrow.Visible = false
                    end
                end)
                return
            end

            -- ScreenGui Fallback Path (when Drawing API is missing or ScreenGui is manually selected)
            hideDrawing()

            if state.ShowBox then
                local x, y, w, h = state.BX, state.BY, state.BW, state.BH
                local t = math.max(state.BoxThickness, 1)
                local col = state.BoxColor

                if state.BoxStyle == "Full" then
                    fullBoxFrame.Visible = true
                    fullBoxFrame.Position = UDim2.fromOffset(x, y)
                    fullBoxFrame.Size = UDim2.fromOffset(w, h)
                    fullBoxStroke.Color = col
                    fullBoxStroke.Thickness = t
                    for i = 1, 8 do cornerSegs[i].Visible = false end
                else
                    fullBoxFrame.Visible = false
                    local cw = math.clamp(w * 0.25, 4, 24)
                    local ch = math.clamp(h * 0.22, 4, 24)

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

                if state.ShowHealthText and state.BH >= 16 then
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

            if state.ShowLabel then
                nameLabel.Visible = true
                nameLabel.Position = UDim2.fromOffset(state.BX + state.BW * 0.5, state.BY - 3)
                nameLabel.Text = state.LabelText
                nameLabel.TextColor3 = state.BoxColor
            else
                nameLabel.Visible = false
            end

            if state.ShowTracer then
                local delta = state.TracerTo - state.TracerFrom
                local mid = (state.TracerFrom + state.TracerTo) * 0.5
                tracerFrame.Visible = true
                tracerFrame.Position = UDim2.fromOffset(mid.X, mid.Y)
                tracerFrame.Size = UDim2.fromOffset(math.max(delta.Magnitude, 1), math.max(state.LineThickness, 1))
                tracerFrame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                tracerFrame.BackgroundColor3 = state.TracerColor
            else
                tracerFrame.Visible = false
            end

            if state.ShowArrow then
                arrowHolder.Visible = true
                arrowHolder.Position = UDim2.fromOffset(state.ArrowPos.X, state.ArrowPos.Y)
                arrowHolder.Rotation = math.deg(state.ArrowAngle) + 90
                arrowLeft.BackgroundColor3 = state.ArrowColor
                arrowRight.BackgroundColor3 = state.ArrowColor
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
                drawCache = nil
            end
        end,
    }
end

-- ============================================================================
-- [SECTION 4] TRIPLE-LAYER ENTITY SCANNER & GAME ADAPTER
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

local CUSTOM_CHAR_FOLDERS = {"Players", "Characters", "Entities", "ActivePlayers", "Rigs", "GamePlayers"}
local RECONCILE_INTERVAL = 0.5

local function resolveCharacterForPlayer(player)
    local directChar = player.Character
    if directChar and directChar.Parent then
        return directChar
    end

    if not Config.Resolver.CustomContainerScan then
        return nil
    end

    local targetName = player.Name
    local targetDisplay = player.DisplayName
    local targetUserId = player.UserId

    -- Scan common custom Workspace character containers used by FPS/arena games
    for _, folderName in ipairs(CUSTOM_CHAR_FOLDERS) do
        local container = Workspace:FindFirstChild(folderName)
        if container then
            local byName = container:FindFirstChild(targetName) or container:FindFirstChild(targetDisplay)
            if byName and byName:IsA("Model") then
                return byName
            end
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("Model") then
                    local uid = child:GetAttribute("UserId") or child:GetAttribute("PlayerId") or child:GetAttribute("OwnerId")
                    if uid == targetUserId then
                        return child
                    end
                end
            end
        end
    end

    -- Fallback: direct Workspace child model matching player name when Player.Character is detached
    local wsChild = Workspace:FindFirstChild(targetName)
    if wsChild and wsChild:IsA("Model") and (wsChild:FindFirstChildOfClass("Humanoid") or wsChild.PrimaryPart) then
        return wsChild
    end

    return nil
end

local function cacheCharacterParts(entry, character)
    local rigParts = {}
    local targetCandidates = {}
    local largestTorsoFallback = nil
    local largestVol = 0

    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("BasePart") then
            local n = desc.Name
            if n == "Head" then
                targetCandidates.Head = desc
            elseif n == "UpperTorso" then
                targetCandidates.UpperTorso = desc
            elseif n == "Torso" or n == "Chest" then
                targetCandidates.Torso = desc
            elseif n == "HumanoidRootPart" or n == "RootPart" then
                targetCandidates.HumanoidRootPart = desc
            elseif n == "LeftFoot" or n == "RightFoot" or n == "Left Leg" or n == "Right Leg" then
                targetCandidates.Foot = targetCandidates.Foot or desc
            end

            if RIG_PART_NAMES[n] then
                table.insert(rigParts, desc)
            end

            if desc.Transparency < 1 and not desc:FindFirstAncestorOfClass("Accessory") then
                local s = desc.Size
                local vol = s.X * s.Y * s.Z
                if vol > largestVol then
                    largestVol = vol
                    largestTorsoFallback = desc
                end
            end
        end
    end

    if #rigParts == 0 then
        for _, desc in ipairs(character:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Transparency < 1 and not desc:FindFirstAncestorOfClass("Accessory") then
                table.insert(rigParts, desc)
            end
        end
    end
    if #rigParts == 0 then
        for _, desc in ipairs(character:GetDescendants()) do
            if desc:IsA("BasePart") then
                table.insert(rigParts, desc)
            end
        end
    end

    if not targetCandidates.Torso and not targetCandidates.UpperTorso then
        targetCandidates.Torso = largestTorsoFallback
    end

    entry.RigParts = rigParts
    entry.TargetCandidates = targetCandidates
    entry.Humanoid = character:FindFirstChildOfClass("Humanoid")
    entry.RootPart = targetCandidates.HumanoidRootPart
        or targetCandidates.UpperTorso
        or targetCandidates.Torso
        or targetCandidates.Head
        or character.PrimaryPart
        or largestTorsoFallback
        or rigParts[1]
    entry.LastScanTime = os.clock()
end

local function destroyHighlight(entry)
    if entry.Highlight then
        pcall(function()
            entry.Highlight:Destroy()
        end)
        entry.Highlight = nil
    end
end

local function clearCharacterState(entry)
    entry.Character = nil
    entry.Humanoid = nil
    entry.RootPart = nil
    entry.LastTrackedPart = nil
    entry.LastTrackedPos = nil
    entry.EstimatedVel = Vector3.zero
    clearTable(entry.RigParts)
    clearTable(entry.TargetCandidates)

    for _, c in ipairs(entry.CharConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearTable(entry.CharConns)

    destroyHighlight(entry)
    entry.Visuals:HideAll()
end

local function bindCharacter(entry, character)
    clearCharacterState(entry)
    if not character or State.Unloaded then
        return
    end

    entry.Character = character
    cacheCharacterParts(entry, character)

    local function onDescendantChanged(desc)
        if entry.Character == character and character.Parent and not State.Unloaded then
            if desc:IsA("BasePart") or desc:IsA("Humanoid") then
                entry.NeedsRescan = true
            end
        end
    end

    table.insert(entry.CharConns, character.DescendantAdded:Connect(onDescendantChanged))
    table.insert(entry.CharConns, character.DescendantRemoving:Connect(onDescendantChanged))
    table.insert(entry.CharConns, character.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            clearCharacterState(entry)
        end
    end))
end

local function trackPlayer(player)
    if player == LocalPlayer or State.TrackedPlayers[player] then
        return
    end

    local entry = {
        Player = player,
        Character = nil,
        Humanoid = nil,
        RootPart = nil,
        RigParts = {},
        TargetCandidates = {},
        Highlight = nil,
        NeedsRescan = false,
        LastScanTime = 0,
        LastTrackedPart = nil,
        LastTrackedPos = nil,
        EstimatedVel = Vector3.zero,
        Visuals = createPlayerVisuals(),
        PlayerConns = {},
        CharConns = {},
    }

    State.TrackedPlayers[player] = entry

    table.insert(entry.PlayerConns, player.CharacterAdded:Connect(function(char)
        bindCharacter(entry, char)
    end))

    table.insert(entry.PlayerConns, player.CharacterRemoving:Connect(function()
        clearCharacterState(entry)
    end))

    local initialChar = resolveCharacterForPlayer(player)
    if initialChar then
        bindCharacter(entry, initialChar)
    end
end

local function untrackPlayer(player)
    local entry = State.TrackedPlayers[player]
    if not entry then
        return
    end

    if State.CurrentAimTarget == player then
        State.CurrentAimTarget = nil
    end

    clearCharacterState(entry)

    for _, c in ipairs(entry.PlayerConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    clearTable(entry.PlayerConns)

    entry.Visuals:Destroy()
    State.TrackedPlayers[player] = nil
end

-- Layer 1: Immediate Startup Snapshot + Player Lifecycle Hooks
for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end
addConnection(Players.PlayerAdded:Connect(trackPlayer))
addConnection(Players.PlayerRemoving:Connect(untrackPlayer))

-- Layer 2: Fast Per-Frame Character Binding + Periodic 0.5s Reconciliation Sweep
local function syncTrackedEntry(entry, allowCustomSearch)
    local player = entry.Player
    local liveChar = player.Character
    if (not liveChar or not liveChar.Parent) and allowCustomSearch then
        liveChar = resolveCharacterForPlayer(player)
    end

    if liveChar and liveChar.Parent then
        if entry.Character ~= liveChar then
            bindCharacter(entry, liveChar)
        elseif entry.NeedsRescan
            or (not entry.RootPart)
            or (not entry.RootPart.Parent)
            or (not entry.Humanoid)
            or (not entry.Humanoid.Parent)
            or (#entry.RigParts == 0 and (os.clock() - entry.LastScanTime) > 0.25)
        then
            entry.NeedsRescan = false
            cacheCharacterParts(entry, liveChar)
        end
    elseif entry.Character ~= nil then
        clearCharacterState(entry)
    end
end

local function syncAllPlayers(isSweepTick)
    if isSweepTick then
        local seen = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                seen[player] = true
                local entry = State.TrackedPlayers[player]
                if not entry then
                    trackPlayer(player)
                    entry = State.TrackedPlayers[player]
                end
                if entry then
                    syncTrackedEntry(entry, true)
                end
            end
        end

        for player in pairs(State.TrackedPlayers) do
            if not seen[player] then
                untrackPlayer(player)
            end
        end
    else
        for _, entry in pairs(State.TrackedPlayers) do
            syncTrackedEntry(entry, false)
        end
    end
end

-- ============================================================================
-- [SECTION 5] ADAPTIVE TEAM RESOLVER, HEALTH & RAYCAST VISIBILITY
-- ============================================================================
local function readTeamAttribute(inst)
    if not inst then
        return nil
    end
    local v = inst:GetAttribute("Team")
    if v == nil then v = inst:GetAttribute("TeamId") end
    if v == nil then v = inst:GetAttribute("TeamID") end
    if v == nil then v = inst:GetAttribute("Faction") end
    if v == nil then v = inst:GetAttribute("Squad") end
    return v
end

local function readOverheadTagColor(char)
    if not char then
        return nil
    end
    for _, desc in ipairs(char:GetDescendants()) do
        if desc:IsA("BillboardGui") then
            local lbl = desc:FindFirstChildOfClass("TextLabel")
            if lbl and lbl.Visible then
                return lbl.TextColor3
            end
        end
    end
    return nil
end

local function isTeammate(player, entry)
    if player == LocalPlayer then
        return true
    end

    local mode = Config.Resolver.TeamCheckMode
    if mode == "Off" then
        return false
    end

    if mode == "Team Property" then
        if LocalPlayer.Team ~= nil and player.Team ~= nil then
            if not LocalPlayer.Neutral and not player.Neutral then
                return LocalPlayer.Team == player.Team
            end
        end
        return false
    end

    if mode == "TeamColor" then
        if not LocalPlayer.Neutral and not player.Neutral then
            return LocalPlayer.TeamColor == player.TeamColor
        end
        return false
    end

    -- "Auto" Adaptive Resolver
    if LocalPlayer.Team ~= nil and player.Team ~= nil then
        if not LocalPlayer.Neutral and not player.Neutral then
            return LocalPlayer.Team == player.Team
        end
    end

    if not LocalPlayer.Neutral and not player.Neutral and #Teams:GetTeams() > 0 then
        if LocalPlayer.TeamColor == player.TeamColor then
            return true
        end
    end

    local localAttr = readTeamAttribute(LocalPlayer)
    local targetAttr = readTeamAttribute(player)
    if localAttr ~= nil and targetAttr ~= nil then
        return localAttr == targetAttr
    end

    local targetChar = (entry and entry.Character) or player.Character
    if LocalPlayer.Character and targetChar then
        local cLocal = readTeamAttribute(LocalPlayer.Character)
        local cTarget = readTeamAttribute(targetChar)
        if cLocal ~= nil and cTarget ~= nil then
            return cLocal == cTarget
        end

        -- Overhead BillboardGui team tag color check when game hides Team property
        local lTag = readOverheadTagColor(LocalPlayer.Character)
        local tTag = readOverheadTagColor(targetChar)
        if lTag and tTag then
            local diff = math.abs(lTag.R - tTag.R) + math.abs(lTag.G - tTag.G) + math.abs(lTag.B - tTag.B)
            if diff < 0.05 then
                return true
            end
        end
    end

    return false
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
    local char = entry.Character
    if not char or not char.Parent then
        return false
    end

    if char:GetAttribute("Alive") == false or entry.Player:GetAttribute("Alive") == false then
        return false
    end

    local hum = entry.Humanoid
    if hum and hum.Parent then
        if hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead then
            return false
        end
    else
        local hp = char:GetAttribute("Health") or char:GetAttribute("HP")
        if type(hp) == "number" and hp <= 0 then
            return false
        end
    end

    return entry.RootPart ~= nil and entry.RootPart.Parent ~= nil
end

local function getBodyAnchorPart(entry, desired)
    local cands = entry.TargetCandidates
    if desired == "Head" then
        return (cands.Head and cands.Head.Parent and cands.Head)
            or (cands.UpperTorso and cands.UpperTorso.Parent and cands.UpperTorso)
            or (cands.Torso and cands.Torso.Parent and cands.Torso)
            or entry.RootPart
    elseif desired == "Chest" then
        return (cands.UpperTorso and cands.UpperTorso.Parent and cands.UpperTorso)
            or (cands.Torso and cands.Torso.Parent and cands.Torso)
            or (cands.HumanoidRootPart and cands.HumanoidRootPart.Parent and cands.HumanoidRootPart)
            or (cands.Head and cands.Head.Parent and cands.Head)
            or entry.RootPart
    elseif desired == "Feet" then
        return (cands.Foot and cands.Foot.Parent and cands.Foot) or entry.RootPart
    else
        return (cands.HumanoidRootPart and cands.HumanoidRootPart.Parent and cands.HumanoidRootPart)
            or (cands.UpperTorso and cands.UpperTorso.Parent and cands.UpperTorso)
            or (cands.Torso and cands.Torso.Parent and cands.Torso)
            or entry.RootPart
    end
end

local function getAimPart(entry, camera, screenCenter)
    local mode = Config.Aimbot.TargetPart
    if mode == "Head" then
        return getBodyAnchorPart(entry, "Head")
    elseif mode == "Chest/Torso" then
        return getBodyAnchorPart(entry, "Chest")
    elseif mode == "HumanoidRootPart" then
        return getBodyAnchorPart(entry, "Root")
    else
        local cands = entry.TargetCandidates
        local bestPart = nil
        local bestDist = math.huge
        local partsToCheck = {
            cands.Head,
            cands.UpperTorso,
            cands.Torso,
            cands.HumanoidRootPart,
        }
        for _, part in ipairs(partsToCheck) do
            if part and part.Parent then
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

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.IgnoreWater = true

local function isPartVisible(camera, targetCharacter, targetPart)
    if not targetCharacter or not targetPart or not targetPart.Parent then
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
    if LocalPlayer.Character then
        table.insert(filterList, LocalPlayer.Character)
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

        local isAccessory = hitPart:FindFirstAncestorOfClass("Accessory") ~= nil
        local isNonBlockingGlass = Config.ESP.IgnoreGlassWater
            and (hitPart.Transparency >= 0.45 or hitPart.Material == Enum.Material.Glass)

        if (not hitPart.CanCollide) or isAccessory or isNonBlockingGlass or hitPart.Transparency >= 0.92 then
            table.insert(filterList, hitPart)
            currentOrigin = result.Position + dirUnit * 0.05
        else
            return false
        end
    end

    return false
end

local function isEntryVisible(camera, entry)
    local headPart = entry.TargetCandidates.Head
    local chestPart = getBodyAnchorPart(entry, "Chest")
    if headPart and headPart.Parent and isPartVisible(camera, entry.Character, headPart) then
        return true
    end
    if chestPart and chestPart.Parent and chestPart ~= headPart and isPartVisible(camera, entry.Character, chestPart) then
        return true
    end
    if entry.RootPart and entry.RootPart ~= headPart and entry.RootPart ~= chestPart then
        return isPartVisible(camera, entry.Character, entry.RootPart)
    end
    return false
end

-- ============================================================================
-- [SECTION 6] REBUILT ESP RENDERER (CORNER BOX, HEALTH, SMART TRACERS, 360 & HL)
-- ============================================================================
local function computeScreenBox(camera, entry)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyInFront = false

    local parts = entry.RigParts
    local validParts = 0
    if #parts > 0 then
        for _, part in ipairs(parts) do
            if part and part.Parent then
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

    if validParts == 0 and entry.Character then
        local ok, cf, size = pcall(function()
            return entry.Character:GetBoundingBox()
        end)
        if ok and cf and size then
            local half = size * 0.5
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

    if not anyInFront or minX >= maxX or minY >= maxY then
        return false, 0, 0, 0, 0
    end

    local pad = 3
    return true, minX - pad, minY - pad, (maxX - minX) + pad * 2, (maxY - minY) + pad * 2
end

local function getHealthColor(ratio)
    if ratio >= 0.5 then
        return Color3.fromRGB(250, 204, 21):Lerp(Color3.fromRGB(56, 232, 198), (ratio - 0.5) * 2)
    else
        return Color3.fromRGB(244, 63, 94):Lerp(Color3.fromRGB(250, 204, 21), ratio * 2)
    end
end

local MAX_ACTIVE_HIGHLIGHTS = 28

local function updateAllESP(camera, viewportSize, screenCenter)
    local highlightCandidates = {}

    for _, entry in pairs(State.TrackedPlayers) do
        if not Config.ESP.Enabled or not isEntryAlive(entry) then
            entry.Visuals:HideAll()
            if entry.Highlight then entry.Highlight.Enabled = false end
        elseif Config.ESP.TeamCheck and isTeammate(entry.Player, entry) then
            entry.Visuals:HideAll()
            if entry.Highlight then entry.Highlight.Enabled = false end
        else
            local rootPart = entry.RootPart
            local worldDist = (rootPart.Position - camera.CFrame.Position).Magnitude

            if worldDist > Config.ESP.MaxDistance then
                entry.Visuals:HideAll()
                if entry.Highlight then entry.Highlight.Enabled = false end
            else
                local visible = isEntryVisible(camera, entry)

                if Config.ESP.VisibleCheck and not visible then
                    entry.Visuals:HideAll()
                    if entry.Highlight then entry.Highlight.Enabled = false end
                else
                    local boxColor = Config.Colors.BoxTracer
                    if Config.ESP.ColorByVisibility then
                        boxColor = visible and Config.Colors.Visible or Config.Colors.Hidden
                    end

                    local rootVP, rootOnScreen = camera:WorldToViewportPoint(rootPart.Position)
                    local isBehind = rootVP.Z <= 0
                    local screenPos = Vector2.new(rootVP.X, rootVP.Y)

                    local boxValid, bx, by, bw, bh = false, 0, 0, 0, 0
                    if not isBehind then
                        boxValid, bx, by, bw, bh = computeScreenBox(camera, entry)
                    end

                    -- 1. Health ratio (0% - 100%)
                    local _, _, hpRatio = getCharacterHealth(entry)
                    local hpColor = getHealthColor(hpRatio)

                    -- 2. Smart Anchor-Matched Tracer (Bottom->Feet, Center->Chest, Top->Head)
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

                    local tracerColor = Config.ESP.ColorByVisibility and boxColor or Config.Colors.BoxTracer

                    -- 3. Visibility-Reactive 360-Degree Off-Screen Alert
                    local showArrow = false
                    local arrowPos = Vector2.zero
                    local arrowAngle = 0
                    local arrowColor = visible and Config.Colors.Visible or Config.Colors.Hidden

                    if Config.ESP.Alert360 then
                        local alertAllowed = (not Config.ESP.Alert360VisibleOnly) or visible
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
                        ShowLabel = Config.ESP.ShowNameDistance and boxValid,
                        LabelText = string.format("%s [%.0fm]", entry.Player.DisplayName, worldDist),
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

                    -- 4. Visibility-Reactive Highlight Pool
                    if Config.ESP.HighlightESP then
                        local hlAllowed = (not Config.ESP.HighlightVisibleOnly) or visible
                        if hlAllowed then
                            table.insert(highlightCandidates, {
                                Entry = entry,
                                Dist = worldDist,
                                Visible = visible,
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
                        instance.Name = "AKI_HL_" .. entry.Player.Name
                        instance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        instance.Parent = HighlightContainer
                        return instance
                    end)
                    if ok and hl then
                        entry.Highlight = hl
                    end
                end
                if entry.Highlight then
                    local hlCol = item.Visible and Config.Colors.Visible or Config.Colors.Hidden
                    entry.Highlight.Adornee = entry.Character
                    entry.Highlight.FillColor = hlCol
                    entry.Highlight.OutlineColor = hlCol
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
-- [SECTION 7] KINEMATIC PREDICTION AIMBOT & MOBILE TOUCH SAFETY
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
    if Config.Aimbot.ActivationMode == "Always" then
        return true
    elseif Config.Aimbot.ActivationMode == "Mobile Button" then
        return Config.UI.MobileAimLocked
    end
    return State.IsHoldingAim
end

local function getLocalPingSeconds()
    if not Config.Aimbot.PingCompensation or not StatsService then
        return 0
    end
    local ok, pingMs = pcall(function()
        return StatsService.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(pingMs) == "number" and pingMs > 0 then
        return math.clamp((pingMs / 1000) * 0.5, 0, 0.25)
    end
    return 0
end

local function resolveTargetVelocity(entry, part, dt)
    local pos = part.Position
    local frameVel = Vector3.zero
    if entry.LastTrackedPart == part and entry.LastTrackedPos and dt > 0.0005 then
        local deltaPos = pos - entry.LastTrackedPos
        if deltaPos.Magnitude < 25 then
            frameVel = deltaPos / dt
        end
    end
    entry.LastTrackedPart = part
    entry.LastTrackedPos = pos

    local physVel = Vector3.zero
    pcall(function()
        physVel = part.AssemblyLinearVelocity
    end)

    -- Use AssemblyLinearVelocity when active; fallback to CFrame delta velocity for custom movers
    local rawVel = (physVel.Magnitude >= 0.25) and physVel or frameVel
    entry.EstimatedVel = entry.EstimatedVel:Lerp(rawVel, 0.55)
    return entry.EstimatedVel
end

local function validateAimEntry(entry, camera, screenCenter)
    if not entry or not isEntryAlive(entry) then
        return false, nil, math.huge
    end
    if Config.Aimbot.TeamCheck and isTeammate(entry.Player, entry) then
        return false, nil, math.huge
    end

    local part = getAimPart(entry, camera, screenCenter)
    if not part or not part.Parent then
        return false, nil, math.huge
    end

    local worldDist = (part.Position - camera.CFrame.Position).Magnitude
    if worldDist > Config.Aimbot.MaxDistance then
        return false, nil, math.huge
    end

    local vp, onScreen = camera:WorldToViewportPoint(part.Position)
    if vp.Z <= 0 or not onScreen then
        return false, nil, math.huge
    end

    local screenDist = (Vector2.new(vp.X, vp.Y) - screenCenter).Magnitude
    if screenDist > Config.Aimbot.FOVRadius then
        return false, nil, math.huge
    end

    if Config.Aimbot.VisibleCheck and not isPartVisible(camera, entry.Character, part) then
        return false, nil, math.huge
    end

    return true, part, screenDist
end

local function updateAimbot(camera, screenCenter, dt)
    if not Config.Aimbot.Enabled or not isAimbotInputActive() then
        State.CurrentAimTarget = nil
        return
    end

    local chosenEntry = nil
    local chosenPart = nil

    if Config.Aimbot.StickyTarget and State.CurrentAimTarget then
        local stickyEntry = State.TrackedPlayers[State.CurrentAimTarget]
        local ok, part = validateAimEntry(stickyEntry, camera, screenCenter)
        if ok and part then
            chosenEntry = stickyEntry
            chosenPart = part
        else
            State.CurrentAimTarget = nil
        end
    end

    if not chosenPart then
        local bestScreenDist = math.huge
        local bestPlayer = nil
        local bestEntry = nil
        local bestPart = nil

        for player, entry in pairs(State.TrackedPlayers) do
            local ok, part, screenDist = validateAimEntry(entry, camera, screenCenter)
            if ok and part and screenDist < bestScreenDist then
                bestScreenDist = screenDist
                bestPlayer = player
                bestEntry = entry
                bestPart = part
            end
        end

        State.CurrentAimTarget = bestPlayer
        chosenEntry = bestEntry
        chosenPart = bestPart
    end

    if not chosenPart or not chosenEntry then
        return
    end

    local camPos = camera.CFrame.Position
    local targetPos = chosenPart.Position
    local worldDist = (targetPos - camPos).Magnitude

    -- Kinematic velocity prediction + optional projectile travel & ping compensation
    local leadTime = Config.Aimbot.PredictionStrength
    if Config.Aimbot.ProjectileSpeed > 0 then
        leadTime = leadTime + (worldDist / Config.Aimbot.ProjectileSpeed)
    end
    leadTime = leadTime + getLocalPingSeconds()

    local velocity = resolveTargetVelocity(chosenEntry, chosenPart, dt)
    local predictedPos = targetPos + (velocity * leadTime)
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
-- [SECTION 8] MAIN RENDER LOOP (RENDERSTEPPED PRIORITY + 0.5S SWEEP)
-- ============================================================================
local RENDER_STEP_NAME = "TEAM_AKI_RenderStep"

pcall(function()
    RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
end)

RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(dt)
    if State.Unloaded then
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end

    -- Triple-layer scanner: fast per-frame binding + 0.5s full reconciliation sweep
    local now = os.clock()
    local isSweepTick = (now - State.LastReconcileTime) >= RECONCILE_INTERVAL
    if isSweepTick then
        State.LastReconcileTime = now
    end
    pcall(syncAllPlayers, isSweepTick)

    local viewportSize = camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)

    -- Update FOV Circle (Drawing API when active, ScreenGui fallback otherwise)
    local showFov = Config.Aimbot.ShowFOV and Config.Aimbot.Enabled
    local useDrawingFov = shouldUseDrawing() and DrawingFOV ~= nil

    if DrawingFOV then
        pcall(function()
            DrawingFOV.Visible = showFov and useDrawingFov
            if showFov and useDrawingFov then
                DrawingFOV.Position = screenCenter
                DrawingFOV.Radius = Config.Aimbot.FOVRadius
                DrawingFOV.Thickness = Config.Aimbot.FOVThickness
                DrawingFOV.Color = Config.Colors.FOV
            end
        end)
    end

    FOVRingFrame.Visible = showFov and (not useDrawingFov)
    if FOVRingFrame.Visible then
        local diameter = Config.Aimbot.FOVRadius * 2
        FOVRingFrame.Size = UDim2.fromOffset(diameter, diameter)
        FOVStroke.Color = Config.Colors.FOV
        FOVStroke.Thickness = Config.Aimbot.FOVThickness
    end

    -- Update Aimbot after CameraScript, then render ESP using updated camera matrix
    pcall(updateAimbot, camera, screenCenter, dt)
    pcall(updateAllESP, camera, viewportSize, screenCenter)
end)

-- ============================================================================
-- [SECTION 9] REFINED ADAPTIVE DEEP GLASSMORPHIC UI (TEAM AKI)
-- ============================================================================
local MainGui = Instance.new("ScreenGui")
MainGui.Name = "TEAM_AKI_Hub"
MainGui.IgnoreGuiInset = true
MainGui.ResetOnSpawn = false
MainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
MainGui.DisplayOrder = 1000
protectGui(MainGui)
MainGui.Parent = getSafeGuiParent()

local Palette = {
    GlassBase = Color3.fromRGB(11, 13, 20),
    CardElevated = Color3.fromRGB(18, 22, 33),
    SurfaceSoft = Color3.fromRGB(24, 30, 44),
    GlassEdge = Color3.fromRGB(110, 165, 255),
    PrimaryAccent = Color3.fromRGB(88, 156, 255),
    ActiveGlow = Color3.fromRGB(56, 232, 198),
    TextHeader = Color3.fromRGB(242, 245, 252),
    TextSilver = Color3.fromRGB(165, 176, 198),
    ToggleOff = Color3.fromRGB(42, 52, 72),
    Danger = Color3.fromRGB(244, 63, 94),
}

local function tween(obj, duration, props)
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local function applyGlassStroke(target, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = thickness or 1.2
    stroke.Transparency = transparency or 0.72
    stroke.Color = Palette.GlassEdge
    stroke.Parent = target

    local edgeGrad = Instance.new("UIGradient")
    edgeGrad.Rotation = 45
    edgeGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.0),
        NumberSequenceKeypoint.new(0.45, 0.48),
        NumberSequenceKeypoint.new(1, 0.85),
    })
    edgeGrad.Parent = stroke

    return stroke
end

local RootScale = Instance.new("UIScale")
RootScale.Parent = MainGui

local BASE_CARD_W = 496
local BASE_CARD_H = 420

-- Layered soft drop shadow behind MainCard
local CardShadow = Instance.new("Frame")
CardShadow.Name = "CardShadow"
CardShadow.AnchorPoint = Vector2.new(0.5, 0.5)
CardShadow.Position = UDim2.new(0.5, 0, 0.5, 8)
CardShadow.Size = UDim2.fromOffset(BASE_CARD_W + 22, BASE_CARD_H + 22)
CardShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
CardShadow.BackgroundTransparency = 0.55
CardShadow.BorderSizePixel = 0
CardShadow.ZIndex = 1
CardShadow.Parent = MainGui

local ShadowCorner = Instance.new("UICorner")
ShadowCorner.CornerRadius = UDim.new(0, 26)
ShadowCorner.Parent = CardShadow

local MainCard = Instance.new("Frame")
MainCard.Name = "MainCard"
MainCard.AnchorPoint = Vector2.new(0.5, 0.5)
MainCard.Position = UDim2.fromScale(0.5, 0.5)
MainCard.Size = UDim2.fromOffset(BASE_CARD_W, BASE_CARD_H)
MainCard.BackgroundColor3 = Palette.GlassBase
MainCard.BackgroundTransparency = 0.22
MainCard.BorderSizePixel = 0
MainCard.ClipsDescendants = true
MainCard.ZIndex = 2
MainCard.Parent = MainGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 18)
MainCorner.Parent = MainCard

applyGlassStroke(MainCard, 1.35, 0.72)

local GlassGradient = Instance.new("UIGradient")
GlassGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 28, 44)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(11, 13, 20)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(17, 22, 34)),
})
GlassGradient.Rotation = 135
GlassGradient.Parent = MainCard

-- Subtle cyan-indigo refraction sheen along top edge
local FrostedOverlay = Instance.new("Frame")
FrostedOverlay.Name = "FrostedOverlay"
FrostedOverlay.AnchorPoint = Vector2.new(0.5, 0)
FrostedOverlay.Position = UDim2.new(0.5, 0, 0, -56)
FrostedOverlay.Size = UDim2.new(0.84, 0, 0, 108)
FrostedOverlay.BackgroundColor3 = Palette.PrimaryAccent
FrostedOverlay.BackgroundTransparency = 0.90
FrostedOverlay.BorderSizePixel = 0
FrostedOverlay.ZIndex = 2
FrostedOverlay.Parent = MainCard

local FrostCorner = Instance.new("UICorner")
FrostCorner.CornerRadius = UDim.new(1, 0)
FrostCorner.Parent = FrostedOverlay

local function updateResponsiveLayout()
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    local vp = cam.ViewportSize
    local maxScaleX = (vp.X * 0.92) / BASE_CARD_W
    local maxScaleY = (vp.Y * 0.86) / BASE_CARD_H
    local scale = math.clamp(math.min(maxScaleX, maxScaleY), 0.58, 1.12)
    RootScale.Scale = scale
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
    if cam then
        viewportConn = addConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveLayout))
    end
    updateResponsiveLayout()
end

bindCameraViewport()
addConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport))

-- Header Bar
local HeaderBar = Instance.new("Frame")
HeaderBar.Name = "HeaderBar"
HeaderBar.Size = UDim2.new(1, 0, 0, 56)
HeaderBar.BackgroundColor3 = Palette.CardElevated
HeaderBar.BackgroundTransparency = 0.18
HeaderBar.BorderSizePixel = 0
HeaderBar.ZIndex = 3
HeaderBar.Parent = MainCard

local HeaderDivider = Instance.new("Frame")
HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
HeaderDivider.Position = UDim2.new(0, 0, 1, -1)
HeaderDivider.BackgroundColor3 = Palette.GlassEdge
HeaderDivider.BackgroundTransparency = 0.78
HeaderDivider.BorderSizePixel = 0
HeaderDivider.Parent = HeaderBar

-- Brand Badge & Accent Glow
local BrandBadge = Instance.new("Frame")
BrandBadge.AnchorPoint = Vector2.new(0, 0.5)
BrandBadge.Position = UDim2.new(0, 16, 0.5, 0)
BrandBadge.Size = UDim2.fromOffset(92, 28)
BrandBadge.BackgroundColor3 = Palette.PrimaryAccent
BrandBadge.BackgroundTransparency = 0.84
BrandBadge.BorderSizePixel = 0
BrandBadge.ZIndex = 4
BrandBadge.Parent = HeaderBar

local BrandCorner = Instance.new("UICorner")
BrandCorner.CornerRadius = UDim.new(0, 8)
BrandCorner.Parent = BrandBadge

local BrandStroke = Instance.new("UIStroke")
BrandStroke.Thickness = 1
BrandStroke.Transparency = 0.42
BrandStroke.Color = Palette.ActiveGlow
BrandStroke.Parent = BrandBadge

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "BrandTitle"
TitleLabel.BackgroundTransparency = 1
TitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
TitleLabel.Position = UDim2.fromScale(0.5, 0.5)
TitleLabel.Size = UDim2.fromScale(1, 1)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "TEAM AKI"
TitleLabel.TextSize = 14
TitleLabel.TextColor3 = Palette.TextHeader
TitleLabel.ZIndex = 5
TitleLabel.Parent = BrandBadge

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Name = "BrandSubtitle"
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.AnchorPoint = Vector2.new(0, 0.5)
SubtitleLabel.Position = UDim2.new(0, 118, 0.5, 0)
SubtitleLabel.Size = UDim2.new(1, -210, 0, 18)
SubtitleLabel.Font = Enum.Font.GothamMedium
SubtitleLabel.Text = "Universal Glassmorphic Combat Hub"
SubtitleLabel.TextSize = 11.5
SubtitleLabel.TextColor3 = Palette.TextSilver
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.TextTruncate = Enum.TextTruncate.AtEnd
SubtitleLabel.ZIndex = 4
SubtitleLabel.Parent = HeaderBar

local HeaderActions = Instance.new("Frame")
HeaderActions.BackgroundTransparency = 1
HeaderActions.AnchorPoint = Vector2.new(1, 0.5)
HeaderActions.Position = UDim2.new(1, -14, 0.5, 0)
HeaderActions.Size = UDim2.fromOffset(72, 30)
HeaderActions.ZIndex = 4
HeaderActions.Parent = HeaderBar

local HeaderActionsLayout = Instance.new("UIListLayout")
HeaderActionsLayout.FillDirection = Enum.FillDirection.Horizontal
HeaderActionsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
HeaderActionsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
HeaderActionsLayout.Padding = UDim.new(0, 8)
HeaderActionsLayout.Parent = HeaderActions

local function createHeaderButton(symbol, bg)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(30, 30)
    btn.BackgroundColor3 = bg
    btn.BackgroundTransparency = 0.25
    btn.Font = Enum.Font.GothamBold
    btn.Text = symbol
    btn.TextSize = 15
    btn.TextColor3 = Palette.TextHeader
    btn.AutoButtonColor = false
    btn.ZIndex = 5
    btn.Parent = HeaderActions

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = btn

    applyGlassStroke(btn, 1, 0.72)
    return btn
end

local MinimizeBtn = createHeaderButton("-", Palette.SurfaceSoft)
local UnloadHeaderBtn = createHeaderButton("×", Palette.Danger)

-- Dragging MainCard + CardShadow synced together
do
    local activeInput = nil
    local dragStart = nil
    local startPos = nil

    HeaderBar.InputBegan:Connect(function(input)
        if not activeInput and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            activeInput = input
            dragStart = input.Position
            startPos = MainCard.Position
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if activeInput and dragStart and startPos then
            if input == activeInput or (activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
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
                    nextPos.Y.Offset + 8
                )
            end
        end
    end))

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input == activeInput then
            activeInput = nil
        end
    end))
end

-- Tab Bar (Strictly Centered 4-Tab Grid)
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.AnchorPoint = Vector2.new(0.5, 0)
TabBar.Position = UDim2.new(0.5, 0, 0, 66)
TabBar.Size = UDim2.new(1, -28, 0, 38)
TabBar.BackgroundColor3 = Palette.CardElevated
TabBar.BackgroundTransparency = 0.18
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 3
TabBar.Parent = MainCard

local TabBarCorner = Instance.new("UICorner")
TabBarCorner.CornerRadius = UDim.new(0, 11)
TabBarCorner.Parent = TabBar

applyGlassStroke(TabBar, 1, 0.72)

local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingLeft = UDim.new(0, 4)
TabPadding.PaddingRight = UDim.new(0, 4)
TabPadding.PaddingTop = UDim.new(0, 4)
TabPadding.PaddingBottom = UDim.new(0, 4)
TabPadding.Parent = TabBar

local TabGrid = Instance.new("UIGridLayout")
TabGrid.CellSize = UDim2.new(0.25, -4, 1, 0)
TabGrid.CellPadding = UDim2.fromOffset(5, 0)
TabGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabGrid.VerticalAlignment = Enum.VerticalAlignment.Center
TabGrid.SortOrder = Enum.SortOrder.LayoutOrder
TabGrid.Parent = TabBar

local ContentHolder = Instance.new("Frame")
ContentHolder.Name = "ContentHolder"
ContentHolder.AnchorPoint = Vector2.new(0.5, 0)
ContentHolder.Position = UDim2.new(0.5, 0, 0, 114)
ContentHolder.Size = UDim2.new(1, -28, 1, -126)
ContentHolder.BackgroundTransparency = 1
ContentHolder.ZIndex = 3
ContentHolder.Parent = MainCard

local TabPages = {}
local TabButtons = {}
local TabOrder = {"Aimbot", "ESP Visuals", "Colors & Thickness", "Settings"}

local function createTabPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.AnchorPoint = Vector2.new(0.5, 0.5)
    page.Position = UDim2.fromScale(0.5, 0.5)
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Palette.PrimaryAccent
    page.ScrollBarImageTransparency = 0.4
    page.CanvasSize = UDim2.fromOffset(0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = (name == Config.UI.ActiveTab)
    page.ZIndex = 3
    page.Parent = ContentHolder

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.Padding = UDim.new(0, 8)
    list.Parent = page

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 2)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.PaddingLeft = UDim.new(0, 2)
    pad.PaddingRight = UDim.new(0, 6)
    pad.Parent = page

    TabPages[name] = page
    return page
end

local function switchTab(tabName)
    Config.UI.ActiveTab = tabName
    for name, page in pairs(TabPages) do
        page.Visible = (name == tabName)
    end
    for name, btn in pairs(TabButtons) do
        local isActive = (name == tabName)
        tween(btn, 0.18, {
            BackgroundColor3 = isActive and Palette.PrimaryAccent or Palette.CardElevated,
            BackgroundTransparency = isActive and 0.18 or 1,
            TextColor3 = isActive and Palette.TextHeader or Palette.TextSilver,
        })
    end
end

for idx, tabName in ipairs(TabOrder) do
    createTabPage(tabName)

    local btn = Instance.new("TextButton")
    btn.Name = tabName .. "Tab"
    btn.LayoutOrder = idx
    btn.Font = Enum.Font.GothamMedium
    btn.Text = tabName
    btn.TextSize = 10.5
    btn.TextTruncate = Enum.TextTruncate.AtEnd
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = (tabName == Config.UI.ActiveTab) and Palette.PrimaryAccent or Palette.CardElevated
    btn.BackgroundTransparency = (tabName == Config.UI.ActiveTab) and 0.18 or 1
    btn.TextColor3 = (tabName == Config.UI.ActiveTab) and Palette.TextHeader or Palette.TextSilver
    btn.ZIndex = 4
    btn.Parent = TabBar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn

    btn.Activated:Connect(function()
        switchTab(tabName)
    end)

    TabButtons[tabName] = btn
end

-- ============================================================================
-- [SECTION 10] MODULAR UI COMPONENT BUILDERS (STRICTLY CENTERED GLASS CARDS)
-- ============================================================================
local SyncCallbacks = {}

local function createCardRow(parent, height, order)
    local card = Instance.new("Frame")
    card.LayoutOrder = order
    card.Size = UDim2.new(1, 0, 0, height)
    card.BackgroundColor3 = Palette.CardElevated
    card.BackgroundTransparency = 0.18
    card.BorderSizePixel = 0
    card.ZIndex = 4
    card.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = card

    applyGlassStroke(card, 1, 0.76)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 14)
    pad.PaddingRight = UDim.new(0, 14)
    pad.PaddingTop = UDim.new(0, 8)
    pad.PaddingBottom = UDim.new(0, 8)
    pad.Parent = card

    return card
end

local function addToggle(parent, order, title, subtitle, getter, setter)
    local row = createCardRow(parent, subtitle and 56 or 46, order)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.AnchorPoint = Vector2.new(0, 0.5)
    label.Position = UDim2.new(0, 0, subtitle and 0.30 or 0.5, 0)
    label.Size = UDim2.new(1, -56, 0, 18)
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
        sub.Size = UDim2.new(1, -56, 0, 15)
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
    switchBtn.Size = UDim2.fromOffset(44, 24)
    switchBtn.Text = ""
    switchBtn.AutoButtonColor = false
    switchBtn.BorderSizePixel = 0
    switchBtn.ZIndex = 5
    switchBtn.Parent = row

    local swCorner = Instance.new("UICorner")
    swCorner.CornerRadius = UDim.new(1, 0)
    swCorner.Parent = switchBtn

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Size = UDim2.fromOffset(18, 18)
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
        local targetKnobPos = on and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        if instant then
            switchBtn.BackgroundColor3 = targetTrack
            knob.Position = targetKnobPos
        else
            tween(switchBtn, 0.16, {BackgroundColor3 = targetTrack})
            tween(knob, 0.16, {Position = targetKnobPos})
        end
    end

    sync(true)
    table.insert(SyncCallbacks, function()
        sync(true)
    end)

    switchBtn.Activated:Connect(function()
        setter(not getter())
        sync(false)
    end)
end

local function addSlider(parent, order, title, minVal, maxVal, step, formatFn, getter, setter)
    local row = createCardRow(parent, 60, order)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(0, 0)
    label.Size = UDim2.new(0.68, 0, 0, 18)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextHeader
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.ZIndex = 5
    label.Parent = row

    local valueLabel = Instance.new("TextLabel")
    valueLabel.BackgroundTransparency = 1
    valueLabel.AnchorPoint = Vector2.new(1, 0)
    valueLabel.Position = UDim2.new(1, 0, 0, 0)
    valueLabel.Size = UDim2.fromOffset(96, 18)
    valueLabel.Font = Enum.Font.Code
    valueLabel.TextSize = 12
    valueLabel.TextColor3 = Palette.ActiveGlow
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.ZIndex = 5
    valueLabel.Parent = row

    local trackHitbox = Instance.new("TextButton")
    trackHitbox.BackgroundTransparency = 1
    trackHitbox.Text = ""
    trackHitbox.AutoButtonColor = false
    trackHitbox.AnchorPoint = Vector2.new(0.5, 1)
    trackHitbox.Position = UDim2.new(0.5, 0, 1, 2)
    trackHitbox.Size = UDim2.new(1, 0, 0, 24)
    trackHitbox.ZIndex = 6
    trackHitbox.Parent = row

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0.5, 0.5)
    track.Position = UDim2.fromScale(0.5, 0.5)
    track.Size = UDim2.new(1, 0, 0, 6)
    track.BackgroundColor3 = Palette.ToggleOff
    track.BorderSizePixel = 0
    track.ZIndex = 5
    track.Parent = trackHitbox

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0.5, 1)
    fill.BackgroundColor3 = Palette.PrimaryAccent
    fill.BorderSizePixel = 0
    fill.ZIndex = 6
    fill.Parent = track

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local thumb = Instance.new("Frame")
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.Position = UDim2.fromScale(0.5, 0.5)
    thumb.Size = UDim2.fromOffset(14, 14)
    thumb.BackgroundColor3 = Palette.TextHeader
    thumb.BorderSizePixel = 0
    thumb.ZIndex = 7
    thumb.Parent = track

    local thumbCorner = Instance.new("UICorner")
    thumbCorner.CornerRadius = UDim.new(1, 0)
    thumbCorner.Parent = thumb

    local function sync()
        local val = math.clamp(getter(), minVal, maxVal)
        local ratio = (val - minVal) / math.max(maxVal - minVal, 0.0001)
        fill.Size = UDim2.fromScale(ratio, 1)
        thumb.Position = UDim2.fromScale(ratio, 0.5)
        valueLabel.Text = formatFn(val)
    end

    sync()
    table.insert(SyncCallbacks, sync)

    local activeInput = nil

    local function updateFromInput(posX)
        local absPos = track.AbsolutePosition.X
        local absSize = math.max(track.AbsoluteSize.X, 1)
        local ratio = math.clamp((posX - absPos) / absSize, 0, 1)
        local raw = minVal + (maxVal - minVal) * ratio
        local stepped = math.round(raw / step) * step
        local clamped = math.clamp(stepped, minVal, maxVal)
        setter(clamped)
        sync()
    end

    trackHitbox.InputBegan:Connect(function(input)
        if not activeInput and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            activeInput = input
            updateFromInput(input.Position.X)
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if activeInput then
            if input == activeInput or (activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
                updateFromInput(input.Position.X)
            end
        end
    end))

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input == activeInput then
            activeInput = nil
        end
    end))

    return sync
end

local function addSelector(parent, order, title, options, getter, setter)
    local row = createCardRow(parent, 66, order)

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
    bar.Size = UDim2.new(1, 0, 0, 26)
    bar.BackgroundColor3 = Palette.GlassBase
    bar.BackgroundTransparency = 0.22
    bar.BorderSizePixel = 0
    bar.ZIndex = 5
    bar.Parent = row

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(0, 8)
    barCorner.Parent = bar

    local grid = Instance.new("UIGridLayout")
    grid.CellSize = UDim2.new(1 / #options, -4, 1, -4)
    grid.CellPadding = UDim2.fromOffset(4, 0)
    grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    grid.VerticalAlignment = Enum.VerticalAlignment.Center
    grid.SortOrder = Enum.SortOrder.LayoutOrder
    grid.Parent = bar

    local btns = {}

    local function sync()
        local active = getter()
        for opt, b in pairs(btns) do
            local sel = (opt == active)
            tween(b, 0.14, {
                BackgroundColor3 = sel and Palette.PrimaryAccent or Palette.GlassBase,
                BackgroundTransparency = sel and 0.15 or 1,
                TextColor3 = sel and Palette.TextHeader or Palette.TextSilver,
            })
        end
    end

    for i, opt in ipairs(options) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.Text = opt
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 10
        b.TextTruncate = Enum.TextTruncate.AtEnd
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.ZIndex = 6
        b.Parent = bar

        local bc = Instance.new("UICorner")
        bc.CornerRadius = UDim.new(0, 6)
        bc.Parent = b

        b.Activated:Connect(function()
            setter(opt)
            sync()
        end)

        btns[opt] = b
    end

    sync()
    table.insert(SyncCallbacks, sync)
end

-- ============================================================================
-- [SECTION 11] POPULATE TABS (AIMBOT, ESP VISUALS, COLORS & THICKNESS, SETTINGS)
-- ============================================================================
local syncMobileAimVisibility = function() end

-- 1. AIMBOT TAB
local AimbotPage = TabPages["Aimbot"]
addToggle(AimbotPage, 1, "Enable Aimbot", "Master toggle for camera target lock", function()
    return Config.Aimbot.Enabled
end, function(v)
    Config.Aimbot.Enabled = v
    if not v then State.CurrentAimTarget = nil end
end)

addSelector(AimbotPage, 2, "Activation Mode", {"Always", "Hold", "Mobile Button"}, function()
    return Config.Aimbot.ActivationMode
end, function(v)
    Config.Aimbot.ActivationMode = v
    syncMobileAimVisibility()
end)

addSelector(AimbotPage, 3, "Target Part", {"Head", "Chest/Torso", "HumanoidRootPart", "Closest"}, function()
    return Config.Aimbot.TargetPart
end, function(v)
    Config.Aimbot.TargetPart = v
end)

addSlider(AimbotPage, 4, "Smoothness", 1, 20, 1, function(v)
    local n = math.round(v)
    return (n <= 1) and "1 (Instant)" or string.format("%d", n)
end, function()
    return Config.Aimbot.Smoothness
end, function(v)
    Config.Aimbot.Smoothness = math.round(v)
end)

addSlider(AimbotPage, 5, "Prediction Strength (Lead Time)", 0.00, 0.30, 0.01, function(v)
    return string.format("%.2fs", v)
end, function()
    return Config.Aimbot.PredictionStrength
end, function(v)
    Config.Aimbot.PredictionStrength = v
end)

addSlider(AimbotPage, 6, "Projectile Speed (0 = Lead Only)", 0, 2000, 50, function(v)
    local n = math.round(v)
    return (n == 0) and "Off" or string.format("%d st/s", n)
end, function()
    return Config.Aimbot.ProjectileSpeed
end, function(v)
    Config.Aimbot.ProjectileSpeed = math.round(v)
end)

addToggle(AimbotPage, 7, "Ping Auto-Compensation", "Adds half-RTT network ping to prediction lead", function()
    return Config.Aimbot.PingCompensation
end, function(v)
    Config.Aimbot.PingCompensation = v
end)

addSlider(AimbotPage, 8, "FOV Radius", 30, 420, 5, function(v)
    return string.format("%d px", math.round(v))
end, function()
    return Config.Aimbot.FOVRadius
end, function(v)
    Config.Aimbot.FOVRadius = v
end)

addToggle(AimbotPage, 9, "Show FOV Circle", "Displays centered FOV ring around crosshair", function()
    return Config.Aimbot.ShowFOV
end, function(v)
    Config.Aimbot.ShowFOV = v
end)

addToggle(AimbotPage, 10, "Team Check", "Uses adaptive resolver to skip teammates", function()
    return Config.Aimbot.TeamCheck
end, function(v)
    Config.Aimbot.TeamCheck = v
end)

addToggle(AimbotPage, 11, "Visible / Wall Check", "Raycasts to ignore enemies behind cover", function()
    return Config.Aimbot.VisibleCheck
end, function(v)
    Config.Aimbot.VisibleCheck = v
end)

addToggle(AimbotPage, 12, "Sticky Target Lock", "Maintains lock on valid target inside FOV", function()
    return Config.Aimbot.StickyTarget
end, function(v)
    Config.Aimbot.StickyTarget = v
end)

-- 2. ESP VISUALS TAB
local EspPage = TabPages["ESP Visuals"]
addToggle(EspPage, 1, "Master ESP", "Enables or disables all ESP overlays", function()
    return Config.ESP.Enabled
end, function(v)
    Config.ESP.Enabled = v
end)

addToggle(EspPage, 2, "Box ESP", "Projected 2D bounding box around characters", function()
    return Config.ESP.BoxESP
end, function(v)
    Config.ESP.BoxESP = v
end)

addSelector(EspPage, 3, "Box Style", {"Corner", "Full"}, function()
    return Config.ESP.BoxStyle
end, function(v)
    Config.ESP.BoxStyle = v
end)

addToggle(EspPage, 4, "Health Bar (0% - 100%)", "Vertical sidebar health indicator beside box", function()
    return Config.ESP.HealthBar
end, function(v)
    Config.ESP.HealthBar = v
end)

addToggle(EspPage, 5, "Health % Readout", "Shows numeric 0%-100% health beside bar", function()
    return Config.ESP.ShowHealthPercent
end, function(v)
    Config.ESP.ShowHealthPercent = v
end)

addToggle(EspPage, 6, "ESP Lines (Tracers)", "Smart-anchored tracers matched to target bones", function()
    return Config.ESP.TracerESP
end, function(v)
    Config.ESP.TracerESP = v
end)

addSelector(EspPage, 7, "Tracer Origin -> Anchor", {"Bottom", "Center", "Top"}, function()
    return Config.ESP.TracerOrigin
end, function(v)
    Config.ESP.TracerOrigin = v
end)

addToggle(EspPage, 8, "360° Off-Screen Alert", "Arrows shift color between Visible and Hidden", function()
    return Config.ESP.Alert360
end, function(v)
    Config.ESP.Alert360 = v
end)

addToggle(EspPage, 9, "360° Alert Visible Only", "Hide 360° arrows when enemy is behind cover", function()
    return Config.ESP.Alert360VisibleOnly
end, function(v)
    Config.ESP.Alert360VisibleOnly = v
end)

addToggle(EspPage, 10, "Highlight ESP", "AlwaysOnTop silhouette reactive to visibility", function()
    return Config.ESP.HighlightESP
end, function(v)
    Config.ESP.HighlightESP = v
end)

addToggle(EspPage, 11, "Highlight Visible Only", "Hide highlight when enemy is behind walls", function()
    return Config.ESP.HighlightVisibleOnly
end, function(v)
    Config.ESP.HighlightVisibleOnly = v
end)

addToggle(EspPage, 12, "Name & Distance", "Shows target display name and stud distance", function()
    return Config.ESP.ShowNameDistance
end, function(v)
    Config.ESP.ShowNameDistance = v
end)

addToggle(EspPage, 13, "ESP Team Check", "Hides ESP elements for teammates", function()
    return Config.ESP.TeamCheck
end, function(v)
    Config.ESP.TeamCheck = v
end)

addToggle(EspPage, 14, "Master Visible Filter", "Hides all ESP completely when behind walls", function()
    return Config.ESP.VisibleCheck
end, function(v)
    Config.ESP.VisibleCheck = v
end)

addToggle(EspPage, 15, "Color By Visibility", "Tints boxes and tracers by line-of-sight", function()
    return Config.ESP.ColorByVisibility
end, function(v)
    Config.ESP.ColorByVisibility = v
end)

-- 3. COLORS & THICKNESS TAB
local ColorsPage = TabPages["Colors & Thickness"]

addSlider(ColorsPage, 1, "FOV Circle Thickness", 1.0, 5.0, 0.2, function(v)
    return string.format("%.1f px", v)
end, function()
    return Config.Aimbot.FOVThickness
end, function(v)
    Config.Aimbot.FOVThickness = v
end)

addSlider(ColorsPage, 2, "ESP Line Thickness", 1.0, 5.0, 0.2, function(v)
    return string.format("%.1f px", v)
end, function()
    return Config.ESP.LineThickness
end, function(v)
    Config.ESP.LineThickness = v
end)

addSlider(ColorsPage, 3, "ESP Box Thickness", 1.0, 5.0, 0.2, function(v)
    return string.format("%.1f px", v)
end, function()
    return Config.ESP.BoxThickness
end, function(v)
    Config.ESP.BoxThickness = v
end)

local ColorChannelDefs = {
    { Key = "Visible", Label = "Visible" },
    { Key = "Hidden", Label = "Hidden / Wall" },
    { Key = "BoxTracer", Label = "Box / Tracer" },
    { Key = "FOV", Label = "FOV Circle" },
}

local ChannelCard = createCardRow(ColorsPage, 74, 4)
local ChannelTitle = Instance.new("TextLabel")
ChannelTitle.BackgroundTransparency = 1
ChannelTitle.Position = UDim2.fromOffset(0, 0)
ChannelTitle.Size = UDim2.new(1, -60, 0, 18)
ChannelTitle.Font = Enum.Font.GothamMedium
ChannelTitle.Text = "Active Color Channel"
ChannelTitle.TextSize = 13
ChannelTitle.TextColor3 = Palette.TextHeader
ChannelTitle.TextXAlignment = Enum.TextXAlignment.Left
ChannelTitle.ZIndex = 5
ChannelTitle.Parent = ChannelCard

local LiveSwatch = Instance.new("Frame")
LiveSwatch.AnchorPoint = Vector2.new(1, 0)
LiveSwatch.Position = UDim2.new(1, 0, 0, 0)
LiveSwatch.Size = UDim2.fromOffset(44, 18)
LiveSwatch.BorderSizePixel = 0
LiveSwatch.ZIndex = 5
LiveSwatch.Parent = ChannelCard

local SwatchCorner = Instance.new("UICorner")
SwatchCorner.CornerRadius = UDim.new(0, 6)
SwatchCorner.Parent = LiveSwatch

local SwatchStroke = Instance.new("UIStroke")
SwatchStroke.Thickness = 1
SwatchStroke.Transparency = 0.4
SwatchStroke.Color = Palette.TextHeader
SwatchStroke.Parent = LiveSwatch

local ChannelBar = Instance.new("Frame")
ChannelBar.AnchorPoint = Vector2.new(0.5, 1)
ChannelBar.Position = UDim2.new(0.5, 0, 1, 0)
ChannelBar.Size = UDim2.new(1, 0, 0, 28)
ChannelBar.BackgroundColor3 = Palette.GlassBase
ChannelBar.BackgroundTransparency = 0.22
ChannelBar.BorderSizePixel = 0
ChannelBar.ZIndex = 5
ChannelBar.Parent = ChannelCard

local ChannelBarCorner = Instance.new("UICorner")
ChannelBarCorner.CornerRadius = UDim.new(0, 8)
ChannelBarCorner.Parent = ChannelBar

local ChannelGrid = Instance.new("UIGridLayout")
ChannelGrid.CellSize = UDim2.new(0.25, -4, 1, -4)
ChannelGrid.CellPadding = UDim2.fromOffset(4, 0)
ChannelGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
ChannelGrid.VerticalAlignment = Enum.VerticalAlignment.Center
ChannelGrid.SortOrder = Enum.SortOrder.LayoutOrder
ChannelGrid.Parent = ChannelBar

local channelBtns = {}
local syncRed = nil
local syncGreen = nil
local syncBlue = nil

local function refreshColorControls()
    local c = Config.Colors[Config.UI.SelectedColorKey]
    LiveSwatch.BackgroundColor3 = c
    for key, btn in pairs(channelBtns) do
        local active = (key == Config.UI.SelectedColorKey)
        tween(btn, 0.14, {
            BackgroundColor3 = active and Palette.PrimaryAccent or Palette.GlassBase,
            BackgroundTransparency = active and 0.15 or 1,
            TextColor3 = active and Palette.TextHeader or Palette.TextSilver,
        })
    end
    if syncRed then syncRed() end
    if syncGreen then syncGreen() end
    if syncBlue then syncBlue() end
    notifyColorUpdated()
end

for idx, def in ipairs(ColorChannelDefs) do
    local b = Instance.new("TextButton")
    b.LayoutOrder = idx
    b.Text = def.Label
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 10
    b.TextTruncate = Enum.TextTruncate.AtEnd
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.ZIndex = 6
    b.Parent = ChannelBar

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent = b

    b.Activated:Connect(function()
        Config.UI.SelectedColorKey = def.Key
        refreshColorControls()
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
    LiveSwatch.BackgroundColor3 = Config.Colors[key]
    notifyColorUpdated()
end

syncRed = addSlider(ColorsPage, 5, "Red Channel", 0, 255, 1, function(v)
    return string.format("%d", math.round(v))
end, function()
    return math.round(Config.Colors[Config.UI.SelectedColorKey].R * 255)
end, function(v)
    updateChannelRGB(math.round(v), nil, nil)
end)

syncGreen = addSlider(ColorsPage, 6, "Green Channel", 0, 255, 1, function(v)
    return string.format("%d", math.round(v))
end, function()
    return math.round(Config.Colors[Config.UI.SelectedColorKey].G * 255)
end, function(v)
    updateChannelRGB(nil, math.round(v), nil)
end)

syncBlue = addSlider(ColorsPage, 7, "Blue Channel", 0, 255, 1, function(v)
    return string.format("%d", math.round(v))
end, function()
    return math.round(Config.Colors[Config.UI.SelectedColorKey].B * 255)
end, function(v)
    updateChannelRGB(nil, nil, math.round(v))
end)

local SwatchesCard = createCardRow(ColorsPage, 68, 8)
local SwatchTitle = Instance.new("TextLabel")
SwatchTitle.BackgroundTransparency = 1
SwatchTitle.Position = UDim2.fromOffset(0, 0)
SwatchTitle.Size = UDim2.new(1, 0, 0, 18)
SwatchTitle.Font = Enum.Font.GothamMedium
SwatchTitle.Text = "Quick Color Presets"
SwatchTitle.TextSize = 13
SwatchTitle.TextColor3 = Palette.TextHeader
SwatchTitle.TextXAlignment = Enum.TextXAlignment.Left
SwatchTitle.ZIndex = 5
SwatchTitle.Parent = SwatchesCard

local SwatchRow = Instance.new("Frame")
SwatchRow.AnchorPoint = Vector2.new(0.5, 1)
SwatchRow.Position = UDim2.new(0.5, 0, 1, 0)
SwatchRow.Size = UDim2.new(1, 0, 0, 26)
SwatchRow.BackgroundTransparency = 1
SwatchRow.ZIndex = 5
SwatchRow.Parent = SwatchesCard

local SwatchLayout = Instance.new("UIListLayout")
SwatchLayout.FillDirection = Enum.FillDirection.Horizontal
SwatchLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SwatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center
SwatchLayout.Padding = UDim.new(0, 10)
SwatchLayout.Parent = SwatchRow

local PresetPalette = {
    Color3.fromRGB(56, 232, 198),
    Color3.fromRGB(88, 156, 255),
    Color3.fromRGB(244, 63, 94),
    Color3.fromRGB(251, 146, 60),
    Color3.fromRGB(168, 85, 247),
    Color3.fromRGB(250, 204, 21),
    Color3.fromRGB(242, 245, 252),
    Color3.fromRGB(52, 211, 153),
}

for _, swatchColor in ipairs(PresetPalette) do
    local sb = Instance.new("TextButton")
    sb.Size = UDim2.fromOffset(24, 24)
    sb.Text = ""
    sb.BackgroundColor3 = swatchColor
    sb.AutoButtonColor = false
    sb.BorderSizePixel = 0
    sb.ZIndex = 6
    sb.Parent = SwatchRow

    local sc = Instance.new("UICorner")
    sc.CornerRadius = UDim.new(1, 0)
    sc.Parent = sb

    local ss = Instance.new("UIStroke")
    ss.Thickness = 1
    ss.Transparency = 0.45
    ss.Color = Palette.TextHeader
    ss.Parent = sb

    sb.Activated:Connect(function()
        Config.Colors[Config.UI.SelectedColorKey] = swatchColor
        refreshColorControls()
    end)
end

refreshColorControls()

-- 4. SETTINGS TAB
local SettingsPage = TabPages["Settings"]
addSelector(SettingsPage, 1, "Team Check Mode", {"Auto", "Team Property", "TeamColor", "Off"}, function()
    return Config.Resolver.TeamCheckMode
end, function(v)
    Config.Resolver.TeamCheckMode = v
end)

addSelector(SettingsPage, 2, "ESP Render Engine", {"Auto", "Drawing", "ScreenGui"}, function()
    return Config.ESP.RenderEngine
end, function(v)
    Config.ESP.RenderEngine = v
end)

addToggle(SettingsPage, 3, "Workspace Container Scan", "Scans custom Players / Characters / Entities folders", function()
    return Config.Resolver.CustomContainerScan
end, function(v)
    Config.Resolver.CustomContainerScan = v
end)

addToggle(SettingsPage, 4, "Ignore Transparent Glass & Water", "Allows raycast wall check through glass/water", function()
    return Config.ESP.IgnoreGlassWater
end, function(v)
    Config.ESP.IgnoreGlassWater = v
end)

addToggle(SettingsPage, 5, "Show Mobile Aim Lock Pill", "Displays floating touch button for aim lock", function()
    return Config.UI.ShowMobileAimButton
end, function(v)
    Config.UI.ShowMobileAimButton = v
    syncMobileAimVisibility()
end)

addSlider(SettingsPage, 6, "Max Render Distance", 200, 3500, 50, function(v)
    return string.format("%dm", math.round(v))
end, function()
    return Config.ESP.MaxDistance
end, function(v)
    Config.ESP.MaxDistance = v
    Config.Aimbot.MaxDistance = v
end)

addSlider(SettingsPage, 7, "360° Alert Ring Radius", 80, 280, 5, function(v)
    return string.format("%d px", math.round(v))
end, function()
    return Config.ESP.AlertRingRadius
end, function(v)
    Config.ESP.AlertRingRadius = v
end)

local ActionCard = createCardRow(SettingsPage, 54, 8)
local ActionGrid = Instance.new("UIGridLayout")
ActionGrid.CellSize = UDim2.new(0.5, -5, 1, 0)
ActionGrid.CellPadding = UDim2.fromOffset(10, 0)
ActionGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
ActionGrid.VerticalAlignment = Enum.VerticalAlignment.Center
ActionGrid.Parent = ActionCard

local ResetBtn = Instance.new("TextButton")
ResetBtn.Text = "Reset Defaults"
ResetBtn.Font = Enum.Font.GothamMedium
ResetBtn.TextSize = 12
ResetBtn.TextColor3 = Palette.TextHeader
ResetBtn.BackgroundColor3 = Palette.SurfaceSoft
ResetBtn.AutoButtonColor = false
ResetBtn.BorderSizePixel = 0
ResetBtn.ZIndex = 6
ResetBtn.Parent = ActionCard

local ResetCorner = Instance.new("UICorner")
ResetCorner.CornerRadius = UDim.new(0, 8)
ResetCorner.Parent = ResetBtn

local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Text = "Unload TEAM AKI"
UnloadBtn.Font = Enum.Font.GothamMedium
UnloadBtn.TextSize = 12
UnloadBtn.TextColor3 = Palette.TextHeader
UnloadBtn.BackgroundColor3 = Palette.Danger
UnloadBtn.BackgroundTransparency = 0.2
UnloadBtn.AutoButtonColor = false
UnloadBtn.BorderSizePixel = 0
UnloadBtn.ZIndex = 6
UnloadBtn.Parent = ActionCard

local UnloadCorner = Instance.new("UICorner")
UnloadCorner.CornerRadius = UDim.new(0, 8)
UnloadCorner.Parent = UnloadBtn

-- ============================================================================
-- [SECTION 12] FLOATING MOBILE PILL BUTTONS & CLEAN UNLOAD
-- ============================================================================
local MobileToggle = Instance.new("TextButton")
MobileToggle.Name = "TEAM_AKI_MobileToggle"
MobileToggle.AnchorPoint = Vector2.new(0, 0.5)
MobileToggle.Position = UDim2.new(0, 18, 0.25, 0)
MobileToggle.Size = UDim2.fromOffset(114, 38)
MobileToggle.BackgroundColor3 = Palette.GlassBase
MobileToggle.BackgroundTransparency = 0.22
MobileToggle.Font = Enum.Font.GothamBold
MobileToggle.Text = "TEAM AKI"
MobileToggle.TextSize = 13
MobileToggle.TextColor3 = Palette.TextHeader
MobileToggle.AutoButtonColor = false
MobileToggle.BorderSizePixel = 0
MobileToggle.ZIndex = 20
MobileToggle.Parent = MainGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(1, 0)
ToggleCorner.Parent = MobileToggle

local ToggleStroke = applyGlassStroke(MobileToggle, 1.4, 0.35)
ToggleStroke.Color = Palette.ActiveGlow

-- Dedicated Mobile Touch Aim Lock Pill (does not interfere with thumbsticks)
local MobileAimBtn = Instance.new("TextButton")
MobileAimBtn.Name = "TEAM_AKI_MobileAim"
MobileAimBtn.AnchorPoint = Vector2.new(1, 0.5)
MobileAimBtn.Position = UDim2.new(1, -18, 0.42, 0)
MobileAimBtn.Size = UDim2.fromOffset(112, 38)
MobileAimBtn.BackgroundColor3 = Palette.GlassBase
MobileAimBtn.BackgroundTransparency = 0.22
MobileAimBtn.Font = Enum.Font.GothamBold
MobileAimBtn.Text = "AIM: OFF"
MobileAimBtn.TextSize = 12
MobileAimBtn.TextColor3 = Palette.TextSilver
MobileAimBtn.AutoButtonColor = false
MobileAimBtn.BorderSizePixel = 0
MobileAimBtn.Visible = false
MobileAimBtn.ZIndex = 20
MobileAimBtn.Parent = MainGui

local AimBtnCorner = Instance.new("UICorner")
AimBtnCorner.CornerRadius = UDim.new(1, 0)
AimBtnCorner.Parent = MobileAimBtn

local AimBtnStroke = applyGlassStroke(MobileAimBtn, 1.4, 0.45)

local function refreshMobileAimStyle()
    local locked = Config.UI.MobileAimLocked
    MobileAimBtn.Text = locked and "AIM: LOCKED" or "AIM: OFF"
    tween(MobileAimBtn, 0.15, {
        TextColor3 = locked and Palette.ActiveGlow or Palette.TextSilver,
    })
    tween(AimBtnStroke, 0.15, {
        Color = locked and Palette.ActiveGlow or Palette.GlassEdge,
    })
end

syncMobileAimVisibility = function()
    MobileAimBtn.Visible = Config.UI.ShowMobileAimButton or (Config.Aimbot.ActivationMode == "Mobile Button")
    refreshMobileAimStyle()
end

local function makeDraggableButton(btn, onTap)
    local activeInput = nil
    local movedDist = 0
    local dragStart = nil
    local startPos = nil

    btn.InputBegan:Connect(function(input)
        if not activeInput and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            activeInput = input
            movedDist = 0
            dragStart = input.Position
            startPos = btn.Position
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if activeInput and dragStart and startPos then
            if input == activeInput or (activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
                local scale = math.max(RootScale.Scale, 0.5)
                local delta = (input.Position - dragStart) / scale
                movedDist = delta.Magnitude
                if movedDist > 6 then
                    btn.Position = UDim2.new(
                        startPos.X.Scale,
                        startPos.X.Offset + delta.X,
                        startPos.Y.Scale,
                        startPos.Y.Offset + delta.Y
                    )
                end
            end
        end
    end))

    addConnection(UserInputService.InputEnded:Connect(function(input)
        if input == activeInput then
            activeInput = nil
            if movedDist <= 6 then
                onTap()
            end
        end
    end))
end

local function setPanelVisible(visible)
    Config.UI.Visible = visible
    if visible then
        MainCard.Visible = true
        CardShadow.Visible = true
        MainCard.Size = UDim2.fromOffset(BASE_CARD_W - 26, BASE_CARD_H - 26)
        MainCard.BackgroundTransparency = 0.45
        CardShadow.BackgroundTransparency = 0.85
        tween(MainCard, 0.2, {
            Size = UDim2.fromOffset(BASE_CARD_W, BASE_CARD_H),
            BackgroundTransparency = 0.22,
        })
        tween(CardShadow, 0.2, {BackgroundTransparency = 0.55})
        tween(ToggleStroke, 0.18, {Color = Palette.ActiveGlow})
    else
        local tw = tween(MainCard, 0.16, {
            Size = UDim2.fromOffset(BASE_CARD_W - 26, BASE_CARD_H - 26),
            BackgroundTransparency = 0.65,
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
    Config.UI.MobileAimLocked = not Config.UI.MobileAimLocked
    refreshMobileAimStyle()
end)

MinimizeBtn.Activated:Connect(function()
    setPanelVisible(false)
end)

addConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.RightShift then
        setPanelVisible(not Config.UI.Visible)
    end
end))

ResetBtn.Activated:Connect(function()
    for k, v in pairs(DefaultConfig.Aimbot) do
        Config.Aimbot[k] = v
    end
    for k, v in pairs(DefaultConfig.ESP) do
        Config.ESP[k] = v
    end
    for k, v in pairs(DefaultConfig.Resolver) do
        Config.Resolver[k] = v
    end
    for k, v in pairs(DefaultConfig.Colors) do
        Config.Colors[k] = v
    end
    for _, sync in ipairs(SyncCallbacks) do
        pcall(sync)
    end
    refreshColorControls()
    syncMobileAimVisibility()
end)

local function unloadScript()
    if State.Unloaded then
        return
    end
    State.Unloaded = true

    pcall(function()
        RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
    end)

    for _, conn in ipairs(State.Connections) do
        pcall(function()
            conn:Disconnect()
        end)
    end
    clearTable(State.Connections)

    local trackedCopy = {}
    for player in pairs(State.TrackedPlayers) do
        table.insert(trackedCopy, player)
    end
    for _, player in ipairs(trackedCopy) do
        untrackPlayer(player)
    end

    safeDestroyDrawing(DrawingFOV)
    DrawingFOV = nil

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

UnloadHeaderBtn.Activated:Connect(unloadScript)
UnloadBtn.Activated:Connect(unloadScript)
