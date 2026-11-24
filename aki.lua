--[[
    ============================================================================
      TEAM AKI v2 — Adaptive Glassmorphic UI, Universal Aimbot & Rebuilt ESP
      Target Executors: Mobile Roblox Executors (Delta, Arceus X, Fluxus, Krnl)
      Compatibility: Universal R6 / R15 / Custom Rigs (Rivals, Arsenal, One Shot)
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
        ActivationMode = "Always",      -- "Always" | "Hold"
        TargetPart = "Head",            -- "Head" | "Torso" | "HumanoidRootPart" | "Closest"
        Smoothness = 0.25,              -- 0.05 (smooth) .. 1.00 (snappy)
        FOVRadius = 135,                -- pixels
        FOVThickness = 1.6,             -- pixels
        ShowFOV = true,
        TeamCheck = true,
        VisibleCheck = true,
        StickyTarget = true,
        MaxDistance = 1500,
    },
    ESP = {
        Enabled = true,
        RenderEngine = "ScreenGui",     -- "ScreenGui" (notch-safe mobile) | "Drawing"
        BoxESP = true,
        BoxStyle = "Corner",            -- "Corner" | "Full"
        BoxThickness = 1.8,             -- pixels
        HealthBar = true,               -- 0% - 100% vertical sidebar
        TracerESP = true,
        TracerOrigin = "Bottom",        -- "Bottom" | "Center" | "Top"
        LineThickness = 1.5,            -- pixels
        Alert360 = true,                -- 360-degree out-of-FOV indicator
        Alert360VisibleOnly = false,    -- If true, hides 360 alerts for targets behind walls
        AlertRingRadius = 155,
        HighlightESP = true,
        HighlightVisibleOnly = false,   -- If true, hides Highlight behind walls; else tints Visible/Hidden
        TeamCheck = true,
        VisibleCheck = false,           -- Master ESP visible-only filter
        ColorByVisibility = true,       -- Tints Box/Label/Alert/Highlight by visibility
        ShowNameDistance = true,
        MaxDistance = 1800,
        HighlightFillTransparency = 0.66,
        HighlightOutlineTransparency = 0.12,
    },
    Colors = {
        Box = Color3.fromRGB(96, 165, 250),              -- Default Box / Corner Box
        Visible = Color3.fromRGB(52, 211, 153),          -- Visible Target Tint
        Hidden = Color3.fromRGB(251, 146, 60),           -- Behind-Wall Target Tint
        Line = Color3.fromRGB(125, 211, 252),            -- Tracer Line
        HighlightVisible = Color3.fromRGB(52, 211, 153), -- Highlight when unobstructed
        HighlightHidden = Color3.fromRGB(244, 63, 94),   -- Highlight when behind cover
        AlertVisible = Color3.fromRGB(56, 189, 248),     -- 360 Alert when unobstructed
        AlertHidden = Color3.fromRGB(248, 113, 113),     -- 360 Alert when behind cover
        FOV = Color3.fromRGB(125, 211, 252),             -- FOV Circle
    },
    UI = {
        Visible = true,
        ActiveTab = "Aimbot",
        SelectedColorKey = "Box",
    },
}

local DefaultConfig = {
    Aimbot = shallowClone(Config.Aimbot),
    ESP = shallowClone(Config.ESP),
    Colors = shallowClone(Config.Colors),
}

local State = {
    Unloaded = false,
    Connections = {},
    TrackedPlayers = {},
    CurrentAimTarget = nil,
    IsHoldingAim = false,
    ColorListeners = {},
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
-- [SECTION 3] HYBRID OVERLAY ENGINE (POOLED SCREENGUI + OPTIONAL DRAWING API)
-- ============================================================================
local OverlayGui = Instance.new("ScreenGui")
OverlayGui.Name = "TEAM_AKI_Overlay_v2"
OverlayGui.IgnoreGuiInset = true
OverlayGui.ResetOnSpawn = false
OverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
OverlayGui.DisplayOrder = 999
protectGui(OverlayGui)
OverlayGui.Parent = getSafeGuiParent()

local EspContainer = Instance.new("Folder")
EspContainer.Name = "ESP_Elements"
EspContainer.Parent = OverlayGui

-- Highlight instances require CoreGui or Workspace ancestry to render reliably
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
            local ln = Drawing.new("Line")
            if ln ~= nil then
                ln.Visible = false
                if type(ln.Remove) == "function" then
                    ln:Remove()
                elseif type(ln.Destroy) == "function" then
                    ln:Destroy()
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

-- Helper to create a pooled 2D Box + Corner Box + Health Bar + Tracer + 360 Arrow + Label per player
local function createPlayerVisuals()
    -- ScreenGui pooled frames (always ready, zero per-frame allocations)
    local guiRoot = Instance.new("Folder")
    guiRoot.Parent = EspContainer

    -- Full Box Frame
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

    -- 8 Corner Bracket Segments (2 per corner: horizontal + vertical)
    local cornerSegs = {}
    for i = 1, 8 do
        local seg = Instance.new("Frame")
        seg.BorderSizePixel = 0
        seg.Visible = false
        seg.ZIndex = 2
        seg.Parent = guiRoot
        cornerSegs[i] = seg
    end

    -- Health Bar (0% - 100% sidebar with dark backing)
    local hpBack = Instance.new("Frame")
    hpBack.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    hpBack.BackgroundTransparency = 0.25
    hpBack.BorderSizePixel = 0
    hpBack.Visible = false
    hpBack.ZIndex = 2
    hpBack.Parent = guiRoot

    local hpBackStroke = Instance.new("UIStroke")
    hpBackStroke.Thickness = 1
    hpBackStroke.Color = Color3.fromRGB(0, 0, 0)
    hpBackStroke.Transparency = 0.35
    hpBackStroke.Parent = hpBack

    local hpFill = Instance.new("Frame")
    hpFill.AnchorPoint = Vector2.new(0, 1)
    hpFill.Position = UDim2.fromScale(0, 1)
    hpFill.Size = UDim2.fromScale(1, 1)
    hpFill.BorderSizePixel = 0
    hpFill.ZIndex = 3
    hpFill.Parent = hpBack

    -- Tracer Line Frame
    local tracerFrame = Instance.new("Frame")
    tracerFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    tracerFrame.BorderSizePixel = 0
    tracerFrame.Visible = false
    tracerFrame.ZIndex = 1
    tracerFrame.Parent = guiRoot

    -- Name & Distance TextLabel
    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.Size = UDim2.fromOffset(220, 18)
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 12
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Visible = false
    nameLabel.ZIndex = 3
    nameLabel.Parent = guiRoot

    -- 360-Degree Directional Chevron
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

    -- Optional native Drawing primitives (lazy-initialized if Drawing mode is selected)
    local drawCache = nil
    local function ensureDrawingCache()
        if drawCache then
            return drawCache
        end
        if not DrawingSupported then
            return nil
        end
        local ok, cache = pcall(function()
            local c = {
                Box = Drawing.new("Square"),
                Corners = {},
                HpBack = Drawing.new("Square"),
                HpFill = Drawing.new("Square"),
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
            c.HpBack.Color = Color3.fromRGB(10, 12, 18)
            c.HpFill.Visible = false
            c.HpFill.Filled = true
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
            else
                c.Label.Font = 2
            end
            return c
        end)
        if ok and cache then
            drawCache = cache
            return drawCache
        end
        return nil
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
            local useDraw = shouldUseDrawing() and ensureDrawingCache() ~= nil
            if useDraw then
                hideGui()
                local d = drawCache
                pcall(function()
                    -- 1. Box (Full or Corner)
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
                            local cw = math.clamp(w * 0.25, 4, 22)
                            local ch = math.clamp(h * 0.22, 4, 22)
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

                    -- 2. Health Bar (0% - 100%)
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
                    else
                        d.HpBack.Visible = false
                        d.HpFill.Visible = false
                    end

                    -- 3. Label
                    if state.ShowLabel then
                        d.Label.Visible = true
                        d.Label.Position = Vector2.new(state.BX + state.BW * 0.5, state.BY - 16)
                        d.Label.Text = state.LabelText
                        d.Label.Color = state.BoxColor
                    else
                        d.Label.Visible = false
                    end

                    -- 4. Tracer
                    if state.ShowTracer then
                        d.Tracer.Visible = true
                        d.Tracer.From = state.TracerFrom
                        d.Tracer.To = state.TracerTo
                        d.Tracer.Color = state.TracerColor
                        d.Tracer.Thickness = state.LineThickness
                    else
                        d.Tracer.Visible = false
                    end

                    -- 5. 360 Alert Arrow
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

            -- ScreenGui Render Path (notch-safe & reliable across all mobile executors)
            hideDrawing()

            -- 1. Box (Full or Corner)
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
                    local cw = math.clamp(w * 0.25, 4, 22)
                    local ch = math.clamp(h * 0.22, 4, 22)

                    -- Top-Left H & V
                    cornerSegs[1].Position = UDim2.fromOffset(x, y)
                    cornerSegs[1].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[2].Position = UDim2.fromOffset(x, y)
                    cornerSegs[2].Size = UDim2.fromOffset(t, ch)

                    -- Top-Right H & V
                    cornerSegs[3].Position = UDim2.fromOffset(x + w - cw, y)
                    cornerSegs[3].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[4].Position = UDim2.fromOffset(x + w - t, y)
                    cornerSegs[4].Size = UDim2.fromOffset(t, ch)

                    -- Bottom-Left H & V
                    cornerSegs[5].Position = UDim2.fromOffset(x, y + h - t)
                    cornerSegs[5].Size = UDim2.fromOffset(cw, t)
                    cornerSegs[6].Position = UDim2.fromOffset(x, y + h - ch)
                    cornerSegs[6].Size = UDim2.fromOffset(t, ch)

                    -- Bottom-Right H & V
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

            -- 2. Health Bar Sidebar (0% - 100%)
            if state.ShowHealth then
                hpBack.Visible = true
                hpBack.Position = UDim2.fromOffset(state.BX - 6, state.BY)
                hpBack.Size = UDim2.fromOffset(3, math.max(state.BH, 2))
                hpFill.Size = UDim2.fromScale(1, state.HealthRatio)
                hpFill.BackgroundColor3 = state.HealthColor
            else
                hpBack.Visible = false
            end

            -- 3. Name & Distance
            if state.ShowLabel then
                nameLabel.Visible = true
                nameLabel.Position = UDim2.fromOffset(state.BX + state.BW * 0.5, state.BY - 3)
                nameLabel.Text = state.LabelText
                nameLabel.TextColor3 = state.BoxColor
            else
                nameLabel.Visible = false
            end

            -- 4. Tracer Line
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

            -- 5. 360 Alert Chevron
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
                safeDestroyDrawing(drawCache.Tracer)
                safeDestroyDrawing(drawCache.Arrow)
                safeDestroyDrawing(drawCache.Label)
                drawCache = nil
            end
        end,
    }
end

-- Screen-centered crisp FOV Circle
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
FOVStroke.Transparency = 0.22
FOVStroke.Color = Config.Colors.FOV
FOVStroke.Parent = FOVRingFrame

-- ============================================================================
-- [SECTION 4] FULL PLAYER COVERAGE & DYNAMIC RIG LIFECYCLE TRACKER
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

local function cacheCharacterParts(entry, character)
    local rigParts = {}
    local targetCandidates = {}

    for _, desc in ipairs(character:GetDescendants()) do
        if desc:IsA("BasePart") then
            if desc.Name == "Head" then
                targetCandidates.Head = desc
            elseif desc.Name == "UpperTorso" then
                targetCandidates.UpperTorso = desc
            elseif desc.Name == "Torso" then
                targetCandidates.Torso = desc
            elseif desc.Name == "HumanoidRootPart" then
                targetCandidates.HumanoidRootPart = desc
            end

            if RIG_PART_NAMES[desc.Name] then
                table.insert(rigParts, desc)
            end
        end
    end

    -- Fallback for custom character models without standard R6/R15 part names
    if #rigParts == 0 then
        for _, desc in ipairs(character:GetDescendants()) do
            if desc:IsA("BasePart") and desc.Transparency < 1 then
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

    entry.RigParts = rigParts
    entry.TargetCandidates = targetCandidates
    entry.Humanoid = character:FindFirstChildOfClass("Humanoid")
    entry.RootPart = targetCandidates.HumanoidRootPart
        or targetCandidates.UpperTorso
        or targetCandidates.Torso
        or targetCandidates.Head
        or character.PrimaryPart
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

    if player.Character then
        bindCharacter(entry, player.Character)
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

for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end
addConnection(Players.PlayerAdded:Connect(trackPlayer))
addConnection(Players.PlayerRemoving:Connect(untrackPlayer))

-- Self-healing synchronization called every frame so no player or delayed character is ever skipped
local function syncAllPlayers()
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
                local liveChar = player.Character
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
        end
    end

    -- Cleanup any orphaned entries whose player left silently
    for player in pairs(State.TrackedPlayers) do
        if not seen[player] then
            untrackPlayer(player)
        end
    end
end

-- ============================================================================
-- [SECTION 5] SHARED TARGET LOGIC (TEAM CHECK, HEALTH, RAYCAST VISIBILITY)
-- ============================================================================
local function isTeammate(player)
    if player == LocalPlayer then
        return true
    end

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

    local localAttr = LocalPlayer:GetAttribute("Team")
    if localAttr == nil then localAttr = LocalPlayer:GetAttribute("TeamId") end
    local targetAttr = player:GetAttribute("Team")
    if targetAttr == nil then targetAttr = player:GetAttribute("TeamId") end
    if localAttr ~= nil and targetAttr ~= nil and localAttr == targetAttr then
        return true
    end

    if LocalPlayer.Character and player.Character then
        local cLocal = LocalPlayer.Character:GetAttribute("Team")
        local cTarget = player.Character:GetAttribute("Team")
        if cLocal ~= nil and cTarget ~= nil and cLocal == cTarget then
            return true
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
        local attrMax = char:GetAttribute("MaxHealth")
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
    end

    return entry.RootPart ~= nil and entry.RootPart.Parent ~= nil
end

local function getAimPart(entry, camera, screenCenter)
    local cands = entry.TargetCandidates
    local mode = Config.Aimbot.TargetPart

    if mode == "Head" then
        return (cands.Head and cands.Head.Parent and cands.Head)
            or (cands.UpperTorso and cands.UpperTorso.Parent and cands.UpperTorso)
            or (cands.Torso and cands.Torso.Parent and cands.Torso)
            or entry.RootPart
    elseif mode == "Torso" then
        return (cands.UpperTorso and cands.UpperTorso.Parent and cands.UpperTorso)
            or (cands.Torso and cands.Torso.Parent and cands.Torso)
            or (cands.HumanoidRootPart and cands.HumanoidRootPart.Parent and cands.HumanoidRootPart)
            or (cands.Head and cands.Head.Parent and cands.Head)
            or entry.RootPart
    elseif mode == "HumanoidRootPart" then
        return (cands.HumanoidRootPart and cands.HumanoidRootPart.Parent and cands.HumanoidRootPart)
            or (cands.UpperTorso and cands.UpperTorso.Parent and cands.UpperTorso)
            or (cands.Torso and cands.Torso.Parent and cands.Torso)
            or entry.RootPart
    else
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

    local currentOrigin = origin
    local dirUnit = delta.Unit

    for _ = 1, 5 do
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

        if (not hitPart.CanCollide) or hitPart.Transparency >= 0.95 then
            table.insert(filterList, hitPart)
            currentOrigin = result.Position + dirUnit * 0.05
        else
            return false
        end
    end

    return false
end

-- ============================================================================
-- [SECTION 6] REBUILT ESP PROJECTION, HEALTH BAR, 360 ALERT & HIGHLIGHT POOL
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
        -- Fallback using Model:GetBoundingBox() if rig parts aren't matched or are temporarily unparented
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
        return Color3.fromRGB(250, 204, 21):Lerp(Color3.fromRGB(52, 211, 153), (ratio - 0.5) * 2)
    else
        return Color3.fromRGB(239, 68, 68):Lerp(Color3.fromRGB(250, 204, 21), ratio * 2)
    end
end

local MAX_ACTIVE_HIGHLIGHTS = 28

local function updateAllESP(camera, viewportSize, screenCenter)
    local highlightCandidates = {}

    for _, entry in pairs(State.TrackedPlayers) do
        if not Config.ESP.Enabled or not isEntryAlive(entry) then
            entry.Visuals:HideAll()
            if entry.Highlight then entry.Highlight.Enabled = false end
        elseif Config.ESP.TeamCheck and isTeammate(entry.Player) then
            entry.Visuals:HideAll()
            if entry.Highlight then entry.Highlight.Enabled = false end
        else
            local rootPart = entry.RootPart
            local worldDist = (rootPart.Position - camera.CFrame.Position).Magnitude

            if worldDist > Config.ESP.MaxDistance then
                entry.Visuals:HideAll()
                if entry.Highlight then entry.Highlight.Enabled = false end
            else
                local checkPart = entry.TargetCandidates.Head or rootPart
                local visible = isPartVisible(camera, entry.Character, checkPart)

                if Config.ESP.VisibleCheck and not visible then
                    entry.Visuals:HideAll()
                    if entry.Highlight then entry.Highlight.Enabled = false end
                else
                    local boxColor = Config.Colors.Box
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

                    -- 2. Tracer origin & anchor
                    local showTracer = Config.ESP.TracerESP and (not isBehind) and rootOnScreen
                    local tracerFrom = Vector2.new(viewportSize.X * 0.5, viewportSize.Y)
                    if Config.ESP.TracerOrigin == "Top" then
                        tracerFrom = Vector2.new(viewportSize.X * 0.5, 0)
                    elseif Config.ESP.TracerOrigin == "Center" then
                        tracerFrom = screenCenter
                    end
                    local tracerTo = boxValid and Vector2.new(bx + bw * 0.5, by + bh) or screenPos

                    -- 3. 360-Degree Alert with Visible Check support
                    local showArrow = false
                    local arrowPos = Vector2.zero
                    local arrowAngle = 0
                    local arrowColor = visible and Config.Colors.AlertVisible or Config.Colors.AlertHidden

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
                        HealthRatio = hpRatio,
                        HealthColor = hpColor,
                        ShowLabel = Config.ESP.ShowNameDistance and boxValid,
                        LabelText = string.format("%s [%.0fm]", entry.Player.DisplayName, worldDist),
                        ShowTracer = showTracer,
                        TracerFrom = tracerFrom,
                        TracerTo = tracerTo,
                        TracerColor = Config.Colors.Line,
                        LineThickness = Config.ESP.LineThickness,
                        ShowArrow = showArrow,
                        ArrowPos = arrowPos,
                        ArrowAngle = arrowAngle,
                        ArrowColor = arrowColor,
                    })

                    -- 4. Queue Highlight candidate (respects HighlightVisibleOnly & Highlight engine cap)
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

    -- Apply Highlights sorted by closest distance up to Roblox's safe engine cap
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
                    local hlCol = item.Visible and Config.Colors.HighlightVisible or Config.Colors.HighlightHidden
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
-- [SECTION 7] UNIVERSAL MOBILE-FRIENDLY AIMBOT CONTROLLER
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
    end
    return State.IsHoldingAim
end

local function validateAimEntry(entry, camera, screenCenter)
    if not entry or not isEntryAlive(entry) then
        return false, nil, math.huge
    end
    if Config.Aimbot.TeamCheck and isTeammate(entry.Player) then
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

    local chosenPart = nil

    if Config.Aimbot.StickyTarget and State.CurrentAimTarget then
        local stickyEntry = State.TrackedPlayers[State.CurrentAimTarget]
        local ok, part = validateAimEntry(stickyEntry, camera, screenCenter)
        if ok and part then
            chosenPart = part
        else
            State.CurrentAimTarget = nil
        end
    end

    if not chosenPart then
        local bestScreenDist = math.huge
        local bestPlayer = nil
        local bestPart = nil

        for player, entry in pairs(State.TrackedPlayers) do
            local ok, part, screenDist = validateAimEntry(entry, camera, screenCenter)
            if ok and part and screenDist < bestScreenDist then
                bestScreenDist = screenDist
                bestPlayer = player
                bestPart = part
            end
        end

        State.CurrentAimTarget = bestPlayer
        chosenPart = bestPart
    end

    if not chosenPart then
        return
    end

    local camPos = camera.CFrame.Position
    local targetCFrame = CFrame.lookAt(camPos, chosenPart.Position)
    local smoothness = math.clamp(Config.Aimbot.Smoothness, 0.03, 1.0)

    if smoothness >= 0.99 then
        camera.CFrame = targetCFrame
    else
        local alpha = 1 - math.pow(1 - smoothness, math.clamp(dt * 60, 0.25, 3))
        camera.CFrame = camera.CFrame:Lerp(targetCFrame, alpha)
    end
end

-- ============================================================================
-- [SECTION 8] MAIN RENDER LOOP (POST-CAMERA PRIORITY & FULL PLAYER SYNC)
-- ============================================================================
local RENDER_STEP_NAME = "TEAM_AKI_RenderStep_v2"

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

    -- Ensure every player & newly spawned character is tracked & healed automatically
    pcall(syncAllPlayers)

    local viewportSize = camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)

    -- Update FOV Circle & Thickness
    local showFov = Config.Aimbot.ShowFOV and Config.Aimbot.Enabled
    FOVRingFrame.Visible = showFov
    if showFov then
        local diameter = Config.Aimbot.FOVRadius * 2
        FOVRingFrame.Size = UDim2.fromOffset(diameter, diameter)
        FOVStroke.Color = Config.Colors.FOV
        FOVStroke.Thickness = Config.Aimbot.FOVThickness
    end

    -- Update Aimbot after CameraScript
    pcall(updateAimbot, camera, screenCenter, dt)

    -- Update ESP using final camera state
    pcall(updateAllESP, camera, viewportSize, screenCenter)
end)

-- ============================================================================
-- [SECTION 9] ADAPTIVE DEEP GLASSMORPHIC UI (TEAM AKI)
-- ============================================================================
local MainGui = Instance.new("ScreenGui")
MainGui.Name = "TEAM_AKI_Hub_v2"
MainGui.IgnoreGuiInset = true
MainGui.ResetOnSpawn = false
MainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
MainGui.DisplayOrder = 1000
protectGui(MainGui)
MainGui.Parent = getSafeGuiParent()

local Palette = {
    ObsidianBase = Color3.fromRGB(8, 10, 16),
    CardSurface = Color3.fromRGB(16, 20, 30),
    ElevatedSurface = Color3.fromRGB(23, 29, 44),
    StrokeCool = Color3.fromRGB(120, 152, 205),
    Accent = Color3.fromRGB(56, 189, 248),
    AccentDeep = Color3.fromRGB(37, 99, 235),
    TextPrimary = Color3.fromRGB(241, 245, 249),
    TextMuted = Color3.fromRGB(148, 163, 184),
    ToggleOff = Color3.fromRGB(45, 55, 72),
    Danger = Color3.fromRGB(244, 63, 94),
}

local function tween(obj, duration, props)
    local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local tw = TweenService:Create(obj, info, props)
    tw:Play()
    return tw
end

local RootScale = Instance.new("UIScale")
RootScale.Parent = MainGui

local BASE_CARD_W = 472
local BASE_CARD_H = 404

-- Layered soft drop shadow behind MainCard
local CardShadow = Instance.new("Frame")
CardShadow.Name = "CardShadow"
CardShadow.AnchorPoint = Vector2.new(0.5, 0.5)
CardShadow.Position = UDim2.new(0.5, 0, 0.5, 6)
CardShadow.Size = UDim2.fromOffset(BASE_CARD_W + 18, BASE_CARD_H + 18)
CardShadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
CardShadow.BackgroundTransparency = 0.58
CardShadow.BorderSizePixel = 0
CardShadow.ZIndex = 1
CardShadow.Parent = MainGui

local ShadowCorner = Instance.new("UICorner")
ShadowCorner.CornerRadius = UDim.new(0, 24)
ShadowCorner.Parent = CardShadow

local MainCard = Instance.new("Frame")
MainCard.Name = "MainCard"
MainCard.AnchorPoint = Vector2.new(0.5, 0.5)
MainCard.Position = UDim2.fromScale(0.5, 0.5)
MainCard.Size = UDim2.fromOffset(BASE_CARD_W, BASE_CARD_H)
MainCard.BackgroundColor3 = Palette.ObsidianBase
MainCard.BackgroundTransparency = 0.14
MainCard.BorderSizePixel = 0
MainCard.ClipsDescendants = true
MainCard.ZIndex = 2
MainCard.Parent = MainGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 18)
MainCorner.Parent = MainCard

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.25
MainStroke.Transparency = 0.58
MainStroke.Color = Palette.StrokeCool
MainStroke.Parent = MainCard

local GlassGradient = Instance.new("UIGradient")
GlassGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 28, 44)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 13, 21)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 20, 32)),
})
GlassGradient.Rotation = 135
GlassGradient.Parent = MainCard

-- Frosted inner top sheen
local FrostedOverlay = Instance.new("Frame")
FrostedOverlay.Name = "FrostedOverlay"
FrostedOverlay.AnchorPoint = Vector2.new(0.5, 0)
FrostedOverlay.Position = UDim2.new(0.5, 0, 0, -52)
FrostedOverlay.Size = UDim2.new(0.82, 0, 0, 105)
FrostedOverlay.BackgroundColor3 = Palette.Accent
FrostedOverlay.BackgroundTransparency = 0.91
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
    -- Fit both width and height cleanly across portrait phones, landscape phones, tablets, desktops
    local maxScaleX = (vp.X * 0.92) / BASE_CARD_W
    local maxScaleY = (vp.Y * 0.86) / BASE_CARD_H
    local scale = math.clamp(math.min(maxScaleX, maxScaleY), 0.62, 1.05)
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
HeaderBar.Size = UDim2.new(1, 0, 0, 54)
HeaderBar.BackgroundColor3 = Palette.CardSurface
HeaderBar.BackgroundTransparency = 0.32
HeaderBar.BorderSizePixel = 0
HeaderBar.ZIndex = 3
HeaderBar.Parent = MainCard

local HeaderDivider = Instance.new("Frame")
HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
HeaderDivider.Position = UDim2.new(0, 0, 1, -1)
HeaderDivider.BackgroundColor3 = Palette.StrokeCool
HeaderDivider.BackgroundTransparency = 0.76
HeaderDivider.BorderSizePixel = 0
HeaderDivider.Parent = HeaderBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "BrandTitle"
TitleLabel.BackgroundTransparency = 1
TitleLabel.Position = UDim2.fromOffset(18, 9)
TitleLabel.Size = UDim2.fromOffset(220, 20)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "TEAM AKI"
TitleLabel.TextSize = 16
TitleLabel.TextColor3 = Palette.TextPrimary
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 4
TitleLabel.Parent = HeaderBar

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Name = "BrandSubtitle"
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Position = UDim2.fromOffset(18, 29)
SubtitleLabel.Size = UDim2.fromOffset(260, 16)
SubtitleLabel.Font = Enum.Font.Gotham
SubtitleLabel.Text = "Universal Aimbot & Rebuilt ESP"
SubtitleLabel.TextSize = 11
SubtitleLabel.TextColor3 = Palette.TextMuted
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
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
    btn.BackgroundTransparency = 0.3
    btn.Font = Enum.Font.GothamBold
    btn.Text = symbol
    btn.TextSize = 15
    btn.TextColor3 = Palette.TextPrimary
    btn.AutoButtonColor = false
    btn.ZIndex = 5
    btn.Parent = HeaderActions

    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 8)
    c.Parent = btn

    local s = Instance.new("UIStroke")
    s.Thickness = 1
    s.Transparency = 0.72
    s.Color = Palette.StrokeCool
    s.Parent = btn

    return btn
end

local MinimizeBtn = createHeaderButton("-", Palette.ElevatedSurface)
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
                    nextPos.Y.Offset + 6
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

-- Tab Bar
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.AnchorPoint = Vector2.new(0.5, 0)
TabBar.Position = UDim2.new(0.5, 0, 0, 64)
TabBar.Size = UDim2.new(1, -28, 0, 36)
TabBar.BackgroundColor3 = Palette.CardSurface
TabBar.BackgroundTransparency = 0.22
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 3
TabBar.Parent = MainCard

local TabBarCorner = Instance.new("UICorner")
TabBarCorner.CornerRadius = UDim.new(0, 10)
TabBarCorner.Parent = TabBar

local TabBarStroke = Instance.new("UIStroke")
TabBarStroke.Thickness = 1
TabBarStroke.Transparency = 0.76
TabBarStroke.Color = Palette.StrokeCool
TabBarStroke.Parent = TabBar

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
ContentHolder.Position = UDim2.new(0.5, 0, 0, 110)
ContentHolder.Size = UDim2.new(1, -28, 1, -124)
ContentHolder.BackgroundTransparency = 1
ContentHolder.ZIndex = 3
ContentHolder.Parent = MainCard

local TabPages = {}
local TabButtons = {}
local TabOrder = {"Aimbot", "ESP", "Colors", "System"}

local function createTabPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name .. "Page"
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 3
    page.ScrollBarImageColor3 = Palette.Accent
    page.ScrollBarImageTransparency = 0.45
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
            BackgroundColor3 = isActive and Palette.AccentDeep or Palette.CardSurface,
            BackgroundTransparency = isActive and 0.15 or 1,
            TextColor3 = isActive and Palette.TextPrimary or Palette.TextMuted,
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
    btn.TextSize = 12
    btn.AutoButtonColor = false
    btn.BorderSizePixel = 0
    btn.BackgroundColor3 = (tabName == Config.UI.ActiveTab) and Palette.AccentDeep or Palette.CardSurface
    btn.BackgroundTransparency = (tabName == Config.UI.ActiveTab) and 0.15 or 1
    btn.TextColor3 = (tabName == Config.UI.ActiveTab) and Palette.TextPrimary or Palette.TextMuted
    btn.ZIndex = 4
    btn.Parent = TabBar

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 7)
    corner.Parent = btn

    btn.Activated:Connect(function()
        switchTab(tabName)
    end)

    TabButtons[tabName] = btn
end

-- ============================================================================
-- [SECTION 10] MODULAR UI COMPONENT BUILDERS (CENTERED & ALIGNED)
-- ============================================================================
local SyncCallbacks = {}

local function createCardRow(parent, height, order)
    local card = Instance.new("Frame")
    card.LayoutOrder = order
    card.Size = UDim2.new(1, 0, 0, height)
    card.BackgroundColor3 = Palette.CardSurface
    card.BackgroundTransparency = 0.24
    card.BorderSizePixel = 0
    card.ZIndex = 4
    card.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1
    stroke.Transparency = 0.78
    stroke.Color = Palette.StrokeCool
    stroke.Parent = card

    return card
end

local function addToggle(parent, order, title, subtitle, getter, setter)
    local row = createCardRow(parent, subtitle and 54 or 44, order)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.fromOffset(14, subtitle and 8 or 0)
    label.Size = UDim2.new(1, -80, 0, subtitle and 20 or 44)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 5
    label.Parent = row

    if subtitle then
        local sub = Instance.new("TextLabel")
        sub.BackgroundTransparency = 1
        sub.Position = UDim2.fromOffset(14, 28)
        sub.Size = UDim2.new(1, -80, 0, 16)
        sub.Font = Enum.Font.Gotham
        sub.Text = subtitle
        sub.TextSize = 11
        sub.TextColor3 = Palette.TextMuted
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.ZIndex = 5
        sub.Parent = row
    end

    local switchBtn = Instance.new("TextButton")
    switchBtn.AnchorPoint = Vector2.new(1, 0.5)
    switchBtn.Position = UDim2.new(1, -14, 0.5, 0)
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
    knob.BackgroundColor3 = Palette.TextPrimary
    knob.BorderSizePixel = 0
    knob.ZIndex = 6
    knob.Parent = switchBtn

    local knobCorner = Instance.new("UICorner")
    knobCorner.CornerRadius = UDim.new(1, 0)
    knobCorner.Parent = knob

    local function sync(instant)
        local on = getter()
        local targetTrack = on and Palette.Accent or Palette.ToggleOff
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
    label.Position = UDim2.fromOffset(14, 8)
    label.Size = UDim2.new(0.65, -14, 0, 20)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 5
    label.Parent = row

    local valueLabel = Instance.new("TextLabel")
    valueLabel.BackgroundTransparency = 1
    valueLabel.AnchorPoint = Vector2.new(1, 0)
    valueLabel.Position = UDim2.new(1, -14, 0, 8)
    valueLabel.Size = UDim2.fromOffset(90, 20)
    valueLabel.Font = Enum.Font.Code
    valueLabel.TextSize = 12
    valueLabel.TextColor3 = Palette.Accent
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    valueLabel.ZIndex = 5
    valueLabel.Parent = row

    local trackHitbox = Instance.new("TextButton")
    trackHitbox.BackgroundTransparency = 1
    trackHitbox.Text = ""
    trackHitbox.AutoButtonColor = false
    trackHitbox.AnchorPoint = Vector2.new(0.5, 0)
    trackHitbox.Position = UDim2.new(0.5, 0, 0, 32)
    trackHitbox.Size = UDim2.new(1, -28, 0, 22)
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
    fill.BackgroundColor3 = Palette.Accent
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
    thumb.BackgroundColor3 = Palette.TextPrimary
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
    label.Position = UDim2.fromOffset(14, 8)
    label.Size = UDim2.new(1, -28, 0, 18)
    label.Font = Enum.Font.GothamMedium
    label.Text = title
    label.TextSize = 13
    label.TextColor3 = Palette.TextPrimary
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.ZIndex = 5
    label.Parent = row

    local bar = Instance.new("Frame")
    bar.AnchorPoint = Vector2.new(0.5, 0)
    bar.Position = UDim2.new(0.5, 0, 0, 32)
    bar.Size = UDim2.new(1, -28, 0, 26)
    bar.BackgroundColor3 = Palette.ObsidianBase
    bar.BackgroundTransparency = 0.2
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
                BackgroundColor3 = sel and Palette.AccentDeep or Palette.ObsidianBase,
                BackgroundTransparency = sel and 0.1 or 1,
                TextColor3 = sel and Palette.TextPrimary or Palette.TextMuted,
            })
        end
    end

    for i, opt in ipairs(options) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.Text = opt
        b.Font = Enum.Font.GothamMedium
        b.TextSize = 10.5
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
-- [SECTION 11] POPULATE TABS (AIMBOT, ESP, COLORS, SYSTEM)
-- ============================================================================

-- AIMBOT TAB
local AimbotPage = TabPages.Aimbot
addToggle(AimbotPage, 1, "Enable Aimbot", "Smoothly aligns camera toward targets inside FOV", function()
    return Config.Aimbot.Enabled
end, function(v)
    Config.Aimbot.Enabled = v
    if not v then State.CurrentAimTarget = nil end
end)

addSelector(AimbotPage, 2, "Activation Mode", {"Always", "Hold"}, function()
    return Config.Aimbot.ActivationMode
end, function(v)
    Config.Aimbot.ActivationMode = v
end)

addSelector(AimbotPage, 3, "Target Part", {"Head", "Torso", "HumanoidRootPart", "Closest"}, function()
    return Config.Aimbot.TargetPart
end, function(v)
    Config.Aimbot.TargetPart = v
end)

addSlider(AimbotPage, 4, "Aim Smoothness", 0.05, 1.0, 0.01, function(v)
    return string.format("%.2f", v)
end, function()
    return Config.Aimbot.Smoothness
end, function(v)
    Config.Aimbot.Smoothness = v
end)

addSlider(AimbotPage, 5, "FOV Radius", 30, 420, 5, function(v)
    return string.format("%d px", math.round(v))
end, function()
    return Config.Aimbot.FOVRadius
end, function(v)
    Config.Aimbot.FOVRadius = v
end)

addSlider(AimbotPage, 6, "FOV Thickness", 0.8, 5.0, 0.2, function(v)
    return string.format("%.1f px", v)
end, function()
    return Config.Aimbot.FOVThickness
end, function(v)
    Config.Aimbot.FOVThickness = v
end)

addToggle(AimbotPage, 7, "Show FOV Ring", "Draws a centered FOV ring around the reticle", function()
    return Config.Aimbot.ShowFOV
end, function(v)
    Config.Aimbot.ShowFOV = v
end)

addToggle(AimbotPage, 8, "Team Check", "Ignores teammates on matching teams", function()
    return Config.Aimbot.TeamCheck
end, function(v)
    Config.Aimbot.TeamCheck = v
end)

addToggle(AimbotPage, 9, "Visible / Wall Check", "Raycasts to ignore targets behind solid cover", function()
    return Config.Aimbot.VisibleCheck
end, function(v)
    Config.Aimbot.VisibleCheck = v
end)

addToggle(AimbotPage, 10, "Sticky Target Lock", "Keeps lock on active target while valid", function()
    return Config.Aimbot.StickyTarget
end, function(v)
    Config.Aimbot.StickyTarget = v
end)

-- ESP TAB
local EspPage = TabPages.ESP
addToggle(EspPage, 1, "Master ESP", "Enables or disables all ESP layers", function()
    return Config.ESP.Enabled
end, function(v)
    Config.ESP.Enabled = v
end)

addToggle(EspPage, 2, "Box ESP", "2D projected bounding box around characters", function()
    return Config.ESP.BoxESP
end, function(v)
    Config.ESP.BoxESP = v
end)

addSelector(EspPage, 3, "Box Style", {"Corner", "Full"}, function()
    return Config.ESP.BoxStyle
end, function(v)
    Config.ESP.BoxStyle = v
end)

addSlider(EspPage, 4, "Box Thickness", 0.8, 5.0, 0.2, function(v)
    return string.format("%.1f px", v)
end, function()
    return Config.ESP.BoxThickness
end, function(v)
    Config.ESP.BoxThickness = v
end)

addToggle(EspPage, 5, "Health Bar (0% - 100%)", "Vertical sidebar health indicator beside box", function()
    return Config.ESP.HealthBar
end, function(v)
    Config.ESP.HealthBar = v
end)

addToggle(EspPage, 6, "Line ESP (Tracers)", "Draws tracer lines from screen edge to targets", function()
    return Config.ESP.TracerESP
end, function(v)
    Config.ESP.TracerESP = v
end)

addSelector(EspPage, 7, "Tracer Origin", {"Bottom", "Center", "Top"}, function()
    return Config.ESP.TracerOrigin
end, function(v)
    Config.ESP.TracerOrigin = v
end)

addSlider(EspPage, 8, "Line Thickness", 0.8, 5.0, 0.2, function(v)
    return string.format("%.1f px", v)
end, function()
    return Config.ESP.LineThickness
end, function(v)
    Config.ESP.LineThickness = v
end)

addToggle(EspPage, 9, "360° Out-of-FOV Alert", "Directional indicators for off-screen enemies", function()
    return Config.ESP.Alert360
end, function(v)
    Config.ESP.Alert360 = v
end)

addToggle(EspPage, 10, "360° Alert Visible Check", "Hide 360° alerts when enemy is behind cover", function()
    return Config.ESP.Alert360VisibleOnly
end, function(v)
    Config.ESP.Alert360VisibleOnly = v
end)

addToggle(EspPage, 11, "Highlight ESP", "AlwaysOnTop silhouette highlight overlay", function()
    return Config.ESP.HighlightESP
end, function(v)
    Config.ESP.HighlightESP = v
end)

addToggle(EspPage, 12, "Highlight Visible Check", "Hide highlight when enemy is behind cover", function()
    return Config.ESP.HighlightVisibleOnly
end, function(v)
    Config.ESP.HighlightVisibleOnly = v
end)

addToggle(EspPage, 13, "Name & Distance", "Displays target display name and distance", function()
    return Config.ESP.ShowNameDistance
end, function(v)
    Config.ESP.ShowNameDistance = v
end)

addToggle(EspPage, 14, "ESP Team Check", "Hides ESP overlays for teammates", function()
    return Config.ESP.TeamCheck
end, function(v)
    Config.ESP.TeamCheck = v
end)

addToggle(EspPage, 15, "Master Visible Check", "Hides all ESP completely when behind walls", function()
    return Config.ESP.VisibleCheck
end, function(v)
    Config.ESP.VisibleCheck = v
end)

addToggle(EspPage, 16, "Color By Visibility", "Tints boxes and labels by line-of-sight", function()
    return Config.ESP.ColorByVisibility
end, function(v)
    Config.ESP.ColorByVisibility = v
end)

-- COLORS TAB
local ColorsPage = TabPages.Colors
local ColorChannelDefs = {
    { Key = "Box", Label = "Box" },
    { Key = "Visible", Label = "Visible" },
    { Key = "Hidden", Label = "Hidden" },
    { Key = "Line", Label = "Line" },
    { Key = "HighlightVisible", Label = "HL Vis" },
    { Key = "HighlightHidden", Label = "HL Hid" },
    { Key = "AlertVisible", Label = "360 Vis" },
    { Key = "AlertHidden", Label = "360 Hid" },
    { Key = "FOV", Label = "FOV" },
}

local ChannelCard = createCardRow(ColorsPage, 108, 1)
local ChannelTitle = Instance.new("TextLabel")
ChannelTitle.BackgroundTransparency = 1
ChannelTitle.Position = UDim2.fromOffset(14, 8)
ChannelTitle.Size = UDim2.new(1, -70, 0, 18)
ChannelTitle.Font = Enum.Font.GothamMedium
ChannelTitle.Text = "Color Channel"
ChannelTitle.TextSize = 13
ChannelTitle.TextColor3 = Palette.TextPrimary
ChannelTitle.TextXAlignment = Enum.TextXAlignment.Left
ChannelTitle.ZIndex = 5
ChannelTitle.Parent = ChannelCard

local LiveSwatch = Instance.new("Frame")
LiveSwatch.AnchorPoint = Vector2.new(1, 0)
LiveSwatch.Position = UDim2.new(1, -14, 0, 8)
LiveSwatch.Size = UDim2.fromOffset(42, 18)
LiveSwatch.BorderSizePixel = 0
LiveSwatch.ZIndex = 5
LiveSwatch.Parent = ChannelCard

local SwatchCorner = Instance.new("UICorner")
SwatchCorner.CornerRadius = UDim.new(0, 6)
SwatchCorner.Parent = LiveSwatch

local SwatchStroke = Instance.new("UIStroke")
SwatchStroke.Thickness = 1
SwatchStroke.Transparency = 0.5
SwatchStroke.Color = Palette.TextPrimary
SwatchStroke.Parent = LiveSwatch

local ChannelGridHolder = Instance.new("Frame")
ChannelGridHolder.AnchorPoint = Vector2.new(0.5, 0)
ChannelGridHolder.Position = UDim2.new(0.5, 0, 0, 32)
ChannelGridHolder.Size = UDim2.new(1, -28, 0, 68)
ChannelGridHolder.BackgroundTransparency = 1
ChannelGridHolder.ZIndex = 5
ChannelGridHolder.Parent = ChannelCard

local ChannelGrid = Instance.new("UIGridLayout")
ChannelGrid.CellSize = UDim2.new(0.333, -4, 0, 20)
ChannelGrid.CellPadding = UDim2.fromOffset(4, 4)
ChannelGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
ChannelGrid.SortOrder = Enum.SortOrder.LayoutOrder
ChannelGrid.Parent = ChannelGridHolder

local channelBtns = {}
local syncRed = nil
local syncGreen = nil
local syncBlue = nil

local function refreshColorControls()
    local c = Config.Colors[Config.UI.SelectedColorKey]
    LiveSwatch.BackgroundColor3 = c
    for key, btn in pairs(channelBtns) do
        local active = (key == Config.UI.SelectedColorKey)
        tween(btn, 0.12, {
            BackgroundColor3 = active and Palette.AccentDeep or Palette.ElevatedSurface,
            TextColor3 = active and Palette.TextPrimary or Palette.TextMuted,
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
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.ZIndex = 6
    b.Parent = ChannelGridHolder

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

syncRed = addSlider(ColorsPage, 2, "Red Channel", 0, 255, 1, function(v)
    return string.format("%d", math.round(v))
end, function()
    return math.round(Config.Colors[Config.UI.SelectedColorKey].R * 255)
end, function(v)
    updateChannelRGB(math.round(v), nil, nil)
end)

syncGreen = addSlider(ColorsPage, 3, "Green Channel", 0, 255, 1, function(v)
    return string.format("%d", math.round(v))
end, function()
    return math.round(Config.Colors[Config.UI.SelectedColorKey].G * 255)
end, function(v)
    updateChannelRGB(nil, math.round(v), nil)
end)

syncBlue = addSlider(ColorsPage, 4, "Blue Channel", 0, 255, 1, function(v)
    return string.format("%d", math.round(v))
end, function()
    return math.round(Config.Colors[Config.UI.SelectedColorKey].B * 255)
end, function(v)
    updateChannelRGB(nil, nil, math.round(v))
end)

local SwatchesCard = createCardRow(ColorsPage, 66, 5)
local SwatchTitle = Instance.new("TextLabel")
SwatchTitle.BackgroundTransparency = 1
SwatchTitle.Position = UDim2.fromOffset(14, 8)
SwatchTitle.Size = UDim2.new(1, -28, 0, 18)
SwatchTitle.Font = Enum.Font.GothamMedium
SwatchTitle.Text = "Quick Color Presets"
SwatchTitle.TextSize = 13
SwatchTitle.TextColor3 = Palette.TextPrimary
SwatchTitle.TextXAlignment = Enum.TextXAlignment.Left
SwatchTitle.ZIndex = 5
SwatchTitle.Parent = SwatchesCard

local SwatchRow = Instance.new("Frame")
SwatchRow.AnchorPoint = Vector2.new(0.5, 0)
SwatchRow.Position = UDim2.new(0.5, 0, 0, 32)
SwatchRow.Size = UDim2.new(1, -28, 0, 24)
SwatchRow.BackgroundTransparency = 1
SwatchRow.ZIndex = 5
SwatchRow.Parent = SwatchesCard

local SwatchLayout = Instance.new("UIListLayout")
SwatchLayout.FillDirection = Enum.FillDirection.Horizontal
SwatchLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
SwatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center
SwatchLayout.Padding = UDim.new(0, 8)
SwatchLayout.Parent = SwatchRow

local PresetPalette = {
    Color3.fromRGB(244, 63, 94),
    Color3.fromRGB(52, 211, 153),
    Color3.fromRGB(56, 189, 248),
    Color3.fromRGB(251, 146, 60),
    Color3.fromRGB(168, 85, 247),
    Color3.fromRGB(250, 204, 21),
    Color3.fromRGB(248, 250, 252),
    Color3.fromRGB(236, 72, 153),
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
    ss.Transparency = 0.5
    ss.Color = Color3.new(1, 1, 1)
    ss.Parent = sb

    sb.Activated:Connect(function()
        Config.Colors[Config.UI.SelectedColorKey] = swatchColor
        refreshColorControls()
    end)
end

refreshColorControls()

-- SYSTEM TAB
local SystemPage = TabPages.System
addSelector(SystemPage, 1, "ESP Render Engine", {"ScreenGui", "Drawing"}, function()
    return Config.ESP.RenderEngine
end, function(v)
    Config.ESP.RenderEngine = v
end)

addSlider(SystemPage, 2, "Max Render Distance", 200, 3500, 50, function(v)
    return string.format("%dm", math.round(v))
end, function()
    return Config.ESP.MaxDistance
end, function(v)
    Config.ESP.MaxDistance = v
    Config.Aimbot.MaxDistance = v
end)

addSlider(SystemPage, 3, "360° Alert Ring Radius", 80, 280, 5, function(v)
    return string.format("%d px", math.round(v))
end, function()
    return Config.ESP.AlertRingRadius
end, function(v)
    Config.ESP.AlertRingRadius = v
end)

local ActionCard = createCardRow(SystemPage, 54, 4)
local ActionPad = Instance.new("UIPadding")
ActionPad.PaddingLeft = UDim.new(0, 14)
ActionPad.PaddingRight = UDim.new(0, 14)
ActionPad.Parent = ActionCard

local ActionGrid = Instance.new("UIGridLayout")
ActionGrid.CellSize = UDim2.new(0.5, -5, 0, 34)
ActionGrid.CellPadding = UDim2.fromOffset(10, 0)
ActionGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
ActionGrid.VerticalAlignment = Enum.VerticalAlignment.Center
ActionGrid.Parent = ActionCard

local ResetBtn = Instance.new("TextButton")
ResetBtn.Text = "Reset Defaults"
ResetBtn.Font = Enum.Font.GothamMedium
ResetBtn.TextSize = 12
ResetBtn.TextColor3 = Palette.TextPrimary
ResetBtn.BackgroundColor3 = Palette.ElevatedSurface
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
UnloadBtn.TextColor3 = Palette.TextPrimary
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
-- [SECTION 12] FLOATING MOBILE TOGGLE BUTTON & CLEAN UNLOAD
-- ============================================================================
local MobileToggle = Instance.new("TextButton")
MobileToggle.Name = "TEAM_AKI_MobileToggle"
MobileToggle.AnchorPoint = Vector2.new(0, 0.5)
MobileToggle.Position = UDim2.new(0, 18, 0.25, 0)
MobileToggle.Size = UDim2.fromOffset(108, 38)
MobileToggle.BackgroundColor3 = Palette.ObsidianBase
MobileToggle.BackgroundTransparency = 0.14
MobileToggle.Font = Enum.Font.GothamBold
MobileToggle.Text = "TEAM AKI"
MobileToggle.TextSize = 13
MobileToggle.TextColor3 = Palette.TextPrimary
MobileToggle.AutoButtonColor = false
MobileToggle.BorderSizePixel = 0
MobileToggle.ZIndex = 20
MobileToggle.Parent = MainGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 12)
ToggleCorner.Parent = MobileToggle

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Thickness = 1.4
ToggleStroke.Transparency = 0.35
ToggleStroke.Color = Palette.Accent
ToggleStroke.Parent = MobileToggle

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
            BackgroundTransparency = 0.14,
        })
        tween(CardShadow, 0.2, {BackgroundTransparency = 0.58})
        tween(ToggleStroke, 0.18, {Color = Palette.Accent})
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
        tween(ToggleStroke, 0.18, {Color = Palette.StrokeCool})
    end
end

do
    local activeInput = nil
    local movedDist = 0
    local dragStart = nil
    local startPos = nil

    MobileToggle.InputBegan:Connect(function(input)
        if not activeInput and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            activeInput = input
            movedDist = 0
            dragStart = input.Position
            startPos = MobileToggle.Position
        end
    end)

    addConnection(UserInputService.InputChanged:Connect(function(input)
        if activeInput and dragStart and startPos then
            if input == activeInput or (activeInput.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
                local scale = math.max(RootScale.Scale, 0.5)
                local delta = (input.Position - dragStart) / scale
                movedDist = delta.Magnitude
                if movedDist > 6 then
                    MobileToggle.Position = UDim2.new(
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
                setPanelVisible(not Config.UI.Visible)
            end
        end
    end))
end

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
    for k, v in pairs(DefaultConfig.Colors) do
        Config.Colors[k] = v
    end
    for _, sync in ipairs(SyncCallbacks) do
        pcall(sync)
    end
    refreshColorControls()
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
