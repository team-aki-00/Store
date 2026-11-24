--[[
    ============================================================================
      TEAM AKI — Adaptive Glassmorphic Combat & Visual Suite
      Target Platforms: Mobile Roblox Executors (Delta, Arceus X, Fluxus, Krnl)
      Compatibility: Universal R6 / R15 / Custom Rigs (Rivals, Arsenal, One Shot)
    ============================================================================
]]

-- Wait for game data model if injected early at startup
if not game:IsLoaded() then
    pcall(function()
        game.Loaded:Wait()
    end)
end

-- ============================================================================
-- [SECTION 1] CLEANUP OF PREVIOUS INSTANCE & ENVIRONMENT SHIMS
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
        ActivationMode = "Always", -- "Always" | "Hold"
        TargetPart = "Head",       -- "Head" | "Torso" | "Closest"
        Smoothness = 0.28,         -- 0.05 (smooth) .. 1.00 (snappy)
        FOVRadius = 135,           -- pixels
        ShowFOV = true,
        TeamCheck = true,
        VisibleCheck = true,
        StickyTarget = true,
        MaxDistance = 1200,
    },
    ESP = {
        Enabled = true,
        BoxESP = true,
        TracerESP = true,
        TracerOrigin = "Bottom",   -- "Bottom" | "Center" | "Top"
        Alert360 = true,           -- Out-of-FOV / 360-degree directional indicator
        AlertRingRadius = 155,
        HighlightESP = true,
        TeamCheck = true,
        VisibleCheck = false,      -- If true, hides ESP behind walls; if false, tints by visibility
        ColorByVisibility = true,  -- Uses Visible / Hidden colors dynamically
        ShowNameDistance = true,
        MaxDistance = 1500,
        BoxThickness = 1.6,
        TracerThickness = 1.4,
        HighlightFillTransparency = 0.68,
        HighlightOutlineTransparency = 0.15,
    },
    Colors = {
        Enemy = Color3.fromRGB(244, 63, 94),       -- Crimson Rose
        Visible = Color3.fromRGB(52, 211, 153),    -- Emerald Mint
        Hidden = Color3.fromRGB(251, 146, 60),     -- Amber Orange
        Tracer = Color3.fromRGB(96, 165, 250),     -- Electric Sky
        Alert360 = Color3.fromRGB(248, 113, 113),  -- Alert Coral
        Highlight = Color3.fromRGB(56, 189, 248),  -- Cyan Highlight
        FOV = Color3.fromRGB(125, 211, 252),       -- Soft Ice Blue
    },
    UI = {
        Visible = true,
        ActiveTab = "Aimbot",
        SelectedColorKey = "Enemy",
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
-- [SECTION 3] DRAWING & SCREEN-GUI HYBRID OVERLAY ENGINE
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

-- Highlight instances require CoreGui or Workspace ancestry to render reliably across executors
local HighlightContainer = Instance.new("Folder")
HighlightContainer.Name = "TEAM_AKI_Highlights"
local okHighlightParent = pcall(function()
    HighlightContainer.Parent = CoreGui
end)
if not okHighlightParent or not HighlightContainer.Parent then
    HighlightContainer.Parent = Workspace
end

-- Probe whether native executor Drawing API works reliably (supports both table & userdata)
local DrawingSupported = false
do
    local ok, result = pcall(function()
        if Drawing and type(Drawing.new) == "function" then
            local sq = Drawing.new("Square")
            if sq ~= nil then
                sq.Visible = false
                if type(sq.Remove) == "function" then
                    sq:Remove()
                elseif type(sq.Destroy) == "function" then
                    sq:Destroy()
                end
                return true
            end
        end
        return false
    end)
    DrawingSupported = ok and result == true
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

-- ScreenGui fallback primitives (used automatically if Drawing API is unavailable or fails)
local function createFallbackBox()
    local frame = Instance.new("Frame")
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = EspContainer

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = Config.ESP.BoxThickness
    stroke.Color = Config.Colors.Enemy
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = frame

    return {
        Frame = frame,
        Stroke = stroke,
        Set = function(self, visible, x, y, w, h, color, thickness)
            self.Frame.Visible = visible
            if visible then
                self.Frame.Position = UDim2.fromOffset(x, y)
                self.Frame.Size = UDim2.fromOffset(w, h)
                self.Stroke.Color = color
                self.Stroke.Thickness = thickness
            end
        end,
        Destroy = function(self)
            pcall(function()
                self.Frame:Destroy()
            end)
        end,
    }
end

local function createFallbackLine()
    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BorderSizePixel = 0
    frame.Visible = false
    frame.Parent = EspContainer

    return {
        Frame = frame,
        Set = function(self, visible, fromPos, toPos, color, thickness)
            self.Frame.Visible = visible
            if visible then
                local delta = toPos - fromPos
                local length = delta.Magnitude
                local mid = (fromPos + toPos) * 0.5
                self.Frame.Position = UDim2.fromOffset(mid.X, mid.Y)
                self.Frame.Size = UDim2.fromOffset(math.max(length, 1), math.max(thickness, 1))
                self.Frame.Rotation = math.deg(math.atan2(delta.Y, delta.X))
                self.Frame.BackgroundColor3 = color
            end
        end,
        Destroy = function(self)
            pcall(function()
                self.Frame:Destroy()
            end)
        end,
    }
end

local function createFallbackLabel()
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Size = UDim2.fromOffset(200, 18)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 12
    label.TextColor3 = Color3.new(1, 1, 1)
    label.TextStrokeTransparency = 0.35
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.Visible = false
    label.Parent = EspContainer

    return {
        Label = label,
        Set = function(self, visible, x, y, text, color)
            self.Label.Visible = visible
            if visible then
                self.Label.Position = UDim2.fromOffset(x, y - 2)
                self.Label.Text = text
                self.Label.TextColor3 = color
            end
        end,
        Destroy = function(self)
            pcall(function()
                self.Label:Destroy()
            end)
        end,
    }
end

local function createFallbackArrow()
    local holder = Instance.new("Frame")
    holder.BackgroundTransparency = 1
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Size = UDim2.fromOffset(16, 16)
    holder.Visible = false
    holder.Parent = EspContainer

    local leftArm = Instance.new("Frame")
    leftArm.BorderSizePixel = 0
    leftArm.AnchorPoint = Vector2.new(0.5, 0.5)
    leftArm.Position = UDim2.fromScale(0.35, 0.5)
    leftArm.Size = UDim2.fromOffset(10, 3)
    leftArm.Rotation = -45
    leftArm.Parent = holder

    local rightArm = Instance.new("Frame")
    rightArm.BorderSizePixel = 0
    rightArm.AnchorPoint = Vector2.new(0.5, 0.5)
    rightArm.Position = UDim2.fromScale(0.65, 0.5)
    rightArm.Size = UDim2.fromOffset(10, 3)
    rightArm.Rotation = 45
    rightArm.Parent = holder

    return {
        Holder = holder,
        Left = leftArm,
        Right = rightArm,
        Set = function(self, visible, tipPos, angleRad, color)
            self.Holder.Visible = visible
            if visible then
                self.Holder.Position = UDim2.fromOffset(tipPos.X, tipPos.Y)
                self.Holder.Rotation = math.deg(angleRad) + 90
                self.Left.BackgroundColor3 = color
                self.Right.BackgroundColor3 = color
            end
        end,
        Destroy = function(self)
            pcall(function()
                self.Holder:Destroy()
            end)
        end,
    }
end

local function createBoxWrapper()
    if DrawingSupported then
        local ok, sq = pcall(Drawing.new, "Square")
        if ok and sq then
            pcall(function()
                sq.Visible = false
                sq.Filled = false
                sq.Thickness = Config.ESP.BoxThickness
            end)
            return {
                _obj = sq,
                Set = function(self, visible, x, y, w, h, color, thickness)
                    pcall(function()
                        self._obj.Visible = visible
                        if visible then
                            self._obj.Position = Vector2.new(x, y)
                            self._obj.Size = Vector2.new(w, h)
                            self._obj.Color = color
                            self._obj.Thickness = thickness
                        end
                    end)
                end,
                Destroy = function(self)
                    safeDestroyDrawing(self._obj)
                end,
            }
        end
    end
    return createFallbackBox()
end

local function createLineWrapper()
    if DrawingSupported then
        local ok, ln = pcall(Drawing.new, "Line")
        if ok and ln then
            pcall(function()
                ln.Visible = false
                ln.Thickness = Config.ESP.TracerThickness
            end)
            return {
                _obj = ln,
                Set = function(self, visible, fromPos, toPos, color, thickness)
                    pcall(function()
                        self._obj.Visible = visible
                        if visible then
                            self._obj.From = fromPos
                            self._obj.To = toPos
                            self._obj.Color = color
                            self._obj.Thickness = thickness
                        end
                    end)
                end,
                Destroy = function(self)
                    safeDestroyDrawing(self._obj)
                end,
            }
        end
    end
    return createFallbackLine()
end

local function createArrowWrapper()
    if DrawingSupported then
        local ok, tri = pcall(Drawing.new, "Triangle")
        if ok and tri then
            pcall(function()
                tri.Visible = false
                tri.Filled = true
                tri.Thickness = 1
            end)
            return {
                _obj = tri,
                Set = function(self, visible, tipPos, angleRad, color)
                    pcall(function()
                        self._obj.Visible = visible
                        if visible then
                            local dir = Vector2.new(math.cos(angleRad), math.sin(angleRad))
                            local perp = Vector2.new(-dir.Y, dir.X)
                            local arrowLen = 14
                            local halfWidth = 7
                            local baseCenter = tipPos - dir * arrowLen
                            self._obj.PointA = tipPos
                            self._obj.PointB = baseCenter + perp * halfWidth
                            self._obj.PointC = baseCenter - perp * halfWidth
                            self._obj.Color = color
                        end
                    end)
                end,
                Destroy = function(self)
                    safeDestroyDrawing(self._obj)
                end,
            }
        end
    end
    return createFallbackArrow()
end

local function createLabelWrapper()
    if DrawingSupported then
        local ok, txt = pcall(Drawing.new, "Text")
        if ok and txt then
            pcall(function()
                txt.Visible = false
                txt.Center = true
                txt.Outline = true
                txt.Size = 13
                if Drawing.Fonts and Drawing.Fonts.UI then
                    txt.Font = Drawing.Fonts.UI
                else
                    txt.Font = 2
                end
            end)
            return {
                _obj = txt,
                Set = function(self, visible, x, y, content, color)
                    pcall(function()
                        self._obj.Visible = visible
                        if visible then
                            self._obj.Position = Vector2.new(x, y - 16)
                            self._obj.Text = content
                            self._obj.Color = color
                        end
                    end)
                end,
                Destroy = function(self)
                    safeDestroyDrawing(self._obj)
                end,
            }
        end
    end
    return createFallbackLabel()
end

-- Screen-centered crisp FOV Ring (consistent across all mobile DPI scales)
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
FOVStroke.Thickness = 1.5
FOVStroke.Transparency = 0.25
FOVStroke.Color = Config.Colors.FOV
FOVStroke.Parent = FOVRingFrame

-- ============================================================================
-- [SECTION 4] PLAYER & CHARACTER LIFECYCLE TRACKER (R6 / R15 / CUSTOM RIGS)
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

    if #rigParts == 0 then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("BasePart") then
                table.insert(rigParts, child)
            end
        end
    end

    entry.RigParts = rigParts
    entry.TargetCandidates = targetCandidates
    entry.Humanoid = character:FindFirstChildOfClass("Humanoid")
    entry.RootPart = targetCandidates.HumanoidRootPart
        or targetCandidates.UpperTorso
        or targetCandidates.Torso
        or character.PrimaryPart
        or rigParts[1]
end

local function ensureHighlight(entry, character)
    if entry.Highlight and entry.Highlight.Parent then
        entry.Highlight.Adornee = character
        return
    end
    local ok, hl = pcall(function()
        local instance = Instance.new("Highlight")
        instance.Name = "AKI_HL_" .. entry.Player.Name
        instance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        instance.FillTransparency = Config.ESP.HighlightFillTransparency
        instance.OutlineTransparency = Config.ESP.HighlightOutlineTransparency
        instance.Enabled = false
        instance.Adornee = character
        instance.Parent = HighlightContainer
        return instance
    end)
    if ok and hl then
        entry.Highlight = hl
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

    if entry.Highlight then
        pcall(function()
            entry.Highlight:Destroy()
        end)
        entry.Highlight = nil
    end

    entry.Box:Set(false, 0, 0, 0, 0, Config.Colors.Enemy, 1)
    entry.Tracer:Set(false, Vector2.zero, Vector2.zero, Config.Colors.Tracer, 1)
    entry.Arrow:Set(false, Vector2.zero, 0, Config.Colors.Alert360)
    entry.Label:Set(false, 0, 0, "", Color3.new(1, 1, 1))
end

local function bindCharacter(entry, character)
    clearCharacterState(entry)
    if not character or State.Unloaded then
        return
    end

    entry.Character = character
    cacheCharacterParts(entry, character)
    ensureHighlight(entry, character)

    local function refreshSoon()
        if entry.Character == character and character.Parent and not State.Unloaded then
            cacheCharacterParts(entry, character)
        end
    end

    table.insert(entry.CharConns, character.ChildAdded:Connect(function(child)
        if child:IsA("BasePart") or child:IsA("Humanoid") then
            refreshSoon()
        end
    end))

    table.insert(entry.CharConns, character.ChildRemoved:Connect(function(child)
        if child:IsA("BasePart") or child:IsA("Humanoid") then
            refreshSoon()
        end
    end))

    table.insert(entry.CharConns, character.AncestryChanged:Connect(function(_, newParent)
        if not newParent then
            clearCharacterState(entry)
        end
    end))

    task.delay(0.25, refreshSoon)
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
        Box = createBoxWrapper(),
        Tracer = createLineWrapper(),
        Arrow = createArrowWrapper(),
        Label = createLabelWrapper(),
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

    entry.Box:Destroy()
    entry.Tracer:Destroy()
    entry.Arrow:Destroy()
    entry.Label:Destroy()

    State.TrackedPlayers[player] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
    trackPlayer(player)
end
addConnection(Players.PlayerAdded:Connect(trackPlayer))
addConnection(Players.PlayerRemoving:Connect(untrackPlayer))

-- ============================================================================
-- [SECTION 5] TEAM CHECK, ALIVE CHECK, TARGET PART & RAYCAST VISIBILITY LOGIC
-- ============================================================================
local function isTeammate(player)
    if player == LocalPlayer then
        return true
    end

    -- Standard Roblox Team object check
    if LocalPlayer.Team ~= nil and player.Team ~= nil then
        if not LocalPlayer.Neutral and not player.Neutral then
            return LocalPlayer.Team == player.Team
        end
    end

    -- TeamColor check only when Teams service defines teams & neither is Neutral
    if not LocalPlayer.Neutral and not player.Neutral and #Teams:GetTeams() > 0 then
        if LocalPlayer.TeamColor == player.TeamColor then
            return true
        end
    end

    -- Attribute fallback for custom team-based shooters (e.g. Rivals / custom rounds)
    local localAttr = LocalPlayer:GetAttribute("Team")
    if localAttr == nil then
        localAttr = LocalPlayer:GetAttribute("TeamId")
    end
    local targetAttr = player:GetAttribute("Team")
    if targetAttr == nil then
        targetAttr = player:GetAttribute("TeamId")
    end
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

local function isEntryAlive(entry)
    local char = entry.Character
    if not char or not char.Parent then
        return false
    end

    if char:GetAttribute("Alive") == false or entry.Player:GetAttribute("Alive") == false then
        return false
    end

    local hum = entry.Humanoid
    if hum then
        if not hum.Parent or hum.Health <= 0 then
            return false
        end
        if hum:GetState() == Enum.HumanoidStateType.Dead then
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
                local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
                if screenPos.Z > 0 then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
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
    local origin = camera.CFrame.Position
    local targetPos = targetPart.Position
    local delta = targetPos - origin
    local totalDist = delta.Magnitude
    if totalDist < 0.01 then
        return true
    end

    local filterList = {OverlayGui, camera}
    if LocalPlayer.Character then
        table.insert(filterList, LocalPlayer.Character)
    end

    local currentOrigin = origin
    local dirUnit = delta.Unit

    -- Up to 4 pierce steps to pass through non-colliding FX or invisible trigger volumes
    for _ = 1, 4 do
        local remaining = (targetPos - currentOrigin).Magnitude
        if remaining < 0.05 then
            return true
        end

        RayParams.FilterDescendantsInstances = filterList
        local result = Workspace:Raycast(currentOrigin, dirUnit * remaining, RayParams)
        if not result then
            return true
        end

        local hitPart = result.Instance
        if not hitPart then
            return true
        end

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
-- [SECTION 6] BOUNDING BOX PROJECTION & ESP RENDERER
-- ============================================================================
local function computeScreenBox(camera, entry)
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyInFront = false

    local parts = entry.RigParts
    if #parts == 0 and entry.RootPart then
        parts = {entry.RootPart}
    end

    for _, part in ipairs(parts) do
        if part and part.Parent then
            local cf = part.CFrame
            local half = part.Size * 0.5
            for sx = -1, 1, 2 do
                for sy = -1, 1, 2 do
                    for sz = -1, 1, 2 do
                        local worldCorner = cf:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
                        local vp = camera:WorldToViewportPoint(worldCorner)
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

local function hideEntryVisuals(entry)
    entry.Box:Set(false, 0, 0, 0, 0, Config.Colors.Enemy, 1)
    entry.Tracer:Set(false, Vector2.zero, Vector2.zero, Config.Colors.Tracer, 1)
    entry.Arrow:Set(false, Vector2.zero, 0, Config.Colors.Alert360)
    entry.Label:Set(false, 0, 0, "", Color3.new(1, 1, 1))
    if entry.Highlight then
        entry.Highlight.Enabled = false
    end
end

local function updateESPForEntry(entry, camera, viewportSize, screenCenter)
    if not Config.ESP.Enabled or not isEntryAlive(entry) then
        hideEntryVisuals(entry)
        return
    end

    if Config.ESP.TeamCheck and isTeammate(entry.Player) then
        hideEntryVisuals(entry)
        return
    end

    local rootPart = entry.RootPart
    local worldDist = (rootPart.Position - camera.CFrame.Position).Magnitude
    if worldDist > Config.ESP.MaxDistance then
        hideEntryVisuals(entry)
        return
    end

    local checkPart = entry.TargetCandidates.Head or rootPart
    local visible = isPartVisible(camera, entry.Character, checkPart)

    if Config.ESP.VisibleCheck and not visible then
        hideEntryVisuals(entry)
        return
    end

    local activeColor = Config.Colors.Enemy
    if Config.ESP.ColorByVisibility then
        activeColor = visible and Config.Colors.Visible or Config.Colors.Hidden
    end

    local rootVP, rootOnScreen = camera:WorldToViewportPoint(rootPart.Position)
    local isBehindCamera = rootVP.Z <= 0
    local targetScreenPos = Vector2.new(rootVP.X, rootVP.Y)

    -- 1. Box ESP & Name/Distance Label
    local boxValid, bx, by, bw, bh = false, 0, 0, 0, 0
    if (Config.ESP.BoxESP or Config.ESP.ShowNameDistance) and not isBehindCamera then
        boxValid, bx, by, bw, bh = computeScreenBox(camera, entry)
    end

    if Config.ESP.BoxESP and boxValid then
        entry.Box:Set(true, bx, by, bw, bh, activeColor, Config.ESP.BoxThickness)
    else
        entry.Box:Set(false, 0, 0, 0, 0, activeColor, 1)
    end

    if Config.ESP.ShowNameDistance and boxValid then
        local text = string.format("%s [%.0fm]", entry.Player.DisplayName, worldDist)
        entry.Label:Set(true, bx + bw * 0.5, by, text, activeColor)
    else
        entry.Label:Set(false, 0, 0, "", activeColor)
    end

    -- 2. Tracer (Line ESP)
    if Config.ESP.TracerESP and not isBehindCamera and rootOnScreen then
        local originPos
        if Config.ESP.TracerOrigin == "Top" then
            originPos = Vector2.new(viewportSize.X * 0.5, 0)
        elseif Config.ESP.TracerOrigin == "Center" then
            originPos = screenCenter
        else
            originPos = Vector2.new(viewportSize.X * 0.5, viewportSize.Y)
        end
        local anchorTo = boxValid and Vector2.new(bx + bw * 0.5, by + bh) or targetScreenPos
        entry.Tracer:Set(true, originPos, anchorTo, Config.Colors.Tracer, Config.ESP.TracerThickness)
    else
        entry.Tracer:Set(false, Vector2.zero, Vector2.zero, Config.Colors.Tracer, 1)
    end

    -- 3. 360-Degree Alert / Out-of-FOV Indicator
    if Config.ESP.Alert360 then
        local localSpace = camera.CFrame:PointToObjectSpace(rootPart.Position)
        local screenDir = Vector2.new(localSpace.X, -localSpace.Y)
        local distFromCenter = (targetScreenPos - screenCenter).Magnitude
        local outOfFOV = isBehindCamera
            or (not rootOnScreen)
            or (distFromCenter > Config.Aimbot.FOVRadius)

        if outOfFOV and screenDir.Magnitude > 0.001 then
            local angle = math.atan2(screenDir.Y, screenDir.X)
            local ringRadius = math.min(
                Config.ESP.AlertRingRadius,
                math.min(viewportSize.X, viewportSize.Y) * 0.42
            )
            local tipPos = screenCenter + Vector2.new(math.cos(angle), math.sin(angle)) * ringRadius
            entry.Arrow:Set(true, tipPos, angle, Config.Colors.Alert360)
        else
            entry.Arrow:Set(false, Vector2.zero, 0, Config.Colors.Alert360)
        end
    else
        entry.Arrow:Set(false, Vector2.zero, 0, Config.Colors.Alert360)
    end

    -- 4. Highlight ESP
    if Config.ESP.HighlightESP then
        ensureHighlight(entry, entry.Character)
        if entry.Highlight then
            local hlColor = Config.ESP.ColorByVisibility and activeColor or Config.Colors.Highlight
            entry.Highlight.FillColor = hlColor
            entry.Highlight.OutlineColor = hlColor
            entry.Highlight.FillTransparency = Config.ESP.HighlightFillTransparency
            entry.Highlight.OutlineTransparency = Config.ESP.HighlightOutlineTransparency
            entry.Highlight.Enabled = true
        end
    elseif entry.Highlight then
        entry.Highlight.Enabled = false
    end
end

-- ============================================================================
-- [SECTION 7] ADVANCED MOBILE-FRIENDLY AIMBOT CONTROLLER
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
-- [SECTION 8] MAIN RENDER LOOP (POST-CAMERA PRIORITY)
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

    local viewportSize = camera.ViewportSize
    local screenCenter = Vector2.new(viewportSize.X * 0.5, viewportSize.Y * 0.5)

    -- Update FOV Ring
    local showFov = Config.Aimbot.ShowFOV and Config.Aimbot.Enabled
    FOVRingFrame.Visible = showFov
    if showFov then
        local diameter = Config.Aimbot.FOVRadius * 2
        FOVRingFrame.Size = UDim2.fromOffset(diameter, diameter)
        FOVStroke.Color = Config.Colors.FOV
    end

    -- Update Aimbot after Roblox CameraScript
    pcall(updateAimbot, camera, screenCenter, dt)

    -- Update ESP after camera update so boxes & tracers match exact frame
    for _, entry in pairs(State.TrackedPlayers) do
        local ok = pcall(updateESPForEntry, entry, camera, viewportSize, screenCenter)
        if not ok then
            hideEntryVisuals(entry)
        end
    end
end)

-- ============================================================================
-- [SECTION 9] ADAPTIVE DEEP GLASSMORPHIC GUI (TEAM AKI)
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
    ObsidianBase = Color3.fromRGB(10, 12, 18),
    CardSurface = Color3.fromRGB(17, 21, 31),
    ElevatedSurface = Color3.fromRGB(24, 30, 44),
    StrokeCool = Color3.fromRGB(115, 145, 195),
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

-- Responsive UIScale based on viewport dimensions (supports phones, tablets, desktops)
local RootScale = Instance.new("UIScale")
RootScale.Parent = MainGui

local function updateResponsiveScale()
    local cam = Workspace.CurrentCamera
    if not cam then
        return
    end
    local vp = cam.ViewportSize
    local minDim = math.min(vp.X, vp.Y)
    local scale = 1
    if minDim < 420 then
        scale = math.clamp(minDim / 460, 0.68, 0.92)
    elseif minDim < 720 then
        scale = math.clamp(minDim / 680, 0.85, 1.0)
    else
        scale = 1.0
    end
    RootScale.Scale = scale
end

updateResponsiveScale()
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
        viewportConn = addConnection(cam:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveScale))
    end
    updateResponsiveScale()
end

bindCameraViewport()
addConnection(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindCameraViewport))

-- Main Centered Card Container
local MainCard = Instance.new("Frame")
MainCard.Name = "MainCard"
MainCard.AnchorPoint = Vector2.new(0.5, 0.5)
MainCard.Position = UDim2.fromScale(0.5, 0.5)
MainCard.Size = UDim2.fromOffset(470, 390)
MainCard.BackgroundColor3 = Palette.ObsidianBase
MainCard.BackgroundTransparency = 0.14
MainCard.BorderSizePixel = 0
MainCard.ClipsDescendants = true
MainCard.Parent = MainGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 18)
MainCorner.Parent = MainCard

local MainStroke = Instance.new("UIStroke")
MainStroke.Thickness = 1.2
MainStroke.Transparency = 0.62
MainStroke.Color = Palette.StrokeCool
MainStroke.Parent = MainCard

local GlassGradient = Instance.new("UIGradient")
GlassGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(22, 28, 42)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(12, 15, 24)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 20, 32)),
})
GlassGradient.Rotation = 135
GlassGradient.Parent = MainCard

local DepthGlow = Instance.new("Frame")
DepthGlow.Name = "DepthGlow"
DepthGlow.AnchorPoint = Vector2.new(0.5, 0)
DepthGlow.Position = UDim2.new(0.5, 0, 0, -45)
DepthGlow.Size = UDim2.new(0.75, 0, 0, 90)
DepthGlow.BackgroundColor3 = Palette.Accent
DepthGlow.BackgroundTransparency = 0.90
DepthGlow.BorderSizePixel = 0
DepthGlow.ZIndex = 0
DepthGlow.Parent = MainCard

local GlowCorner = Instance.new("UICorner")
GlowCorner.CornerRadius = UDim.new(1, 0)
GlowCorner.Parent = DepthGlow

-- Header Bar (Draggable with multi-touch isolation)
local HeaderBar = Instance.new("Frame")
HeaderBar.Name = "HeaderBar"
HeaderBar.Size = UDim2.new(1, 0, 0, 52)
HeaderBar.BackgroundColor3 = Palette.CardSurface
HeaderBar.BackgroundTransparency = 0.35
HeaderBar.BorderSizePixel = 0
HeaderBar.ZIndex = 2
HeaderBar.Parent = MainCard

local HeaderDivider = Instance.new("Frame")
HeaderDivider.Size = UDim2.new(1, 0, 0, 1)
HeaderDivider.Position = UDim2.new(0, 0, 1, -1)
HeaderDivider.BackgroundColor3 = Palette.StrokeCool
HeaderDivider.BackgroundTransparency = 0.78
HeaderDivider.BorderSizePixel = 0
HeaderDivider.Parent = HeaderBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "BrandTitle"
TitleLabel.BackgroundTransparency = 1
TitleLabel.Position = UDim2.fromOffset(18, 8)
TitleLabel.Size = UDim2.fromOffset(220, 20)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "TEAM AKI"
TitleLabel.TextSize = 16
TitleLabel.TextColor3 = Palette.TextPrimary
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 3
TitleLabel.Parent = HeaderBar

local SubtitleLabel = Instance.new("TextLabel")
SubtitleLabel.Name = "BrandSubtitle"
SubtitleLabel.BackgroundTransparency = 1
SubtitleLabel.Position = UDim2.fromOffset(18, 28)
SubtitleLabel.Size = UDim2.fromOffset(250, 16)
SubtitleLabel.Font = Enum.Font.Gotham
SubtitleLabel.Text = "Universal Aimbot & Visual Suite"
SubtitleLabel.TextSize = 11
SubtitleLabel.TextColor3 = Palette.TextMuted
SubtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
SubtitleLabel.ZIndex = 3
SubtitleLabel.Parent = HeaderBar

local HeaderActions = Instance.new("Frame")
HeaderActions.BackgroundTransparency = 1
HeaderActions.AnchorPoint = Vector2.new(1, 0.5)
HeaderActions.Position = UDim2.new(1, -14, 0.5, 0)
HeaderActions.Size = UDim2.fromOffset(72, 30)
HeaderActions.ZIndex = 3
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
    btn.BackgroundTransparency = 0.35
    btn.Font = Enum.Font.GothamBold
    btn.Text = symbol
    btn.TextSize = 15
    btn.TextColor3 = Palette.TextPrimary
    btn.AutoButtonColor = false
    btn.ZIndex = 4
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
                MainCard.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
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

-- Tab Navigation Bar
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.AnchorPoint = Vector2.new(0.5, 0)
TabBar.Position = UDim2.new(0.5, 0, 0, 62)
TabBar.Size = UDim2.new(1, -28, 0, 36)
TabBar.BackgroundColor3 = Palette.CardSurface
TabBar.BackgroundTransparency = 0.25
TabBar.BorderSizePixel = 0
TabBar.ZIndex = 2
TabBar.Parent = MainCard

local TabBarCorner = Instance.new("UICorner")
TabBarCorner.CornerRadius = UDim.new(0, 10)
TabBarCorner.Parent = TabBar

local TabBarStroke = Instance.new("UIStroke")
TabBarStroke.Thickness = 1
TabBarStroke.Transparency = 0.78
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

-- Content Area (Tab Pages)
local ContentHolder = Instance.new("Frame")
ContentHolder.Name = "ContentHolder"
ContentHolder.AnchorPoint = Vector2.new(0.5, 0)
ContentHolder.Position = UDim2.new(0.5, 0, 0, 108)
ContentHolder.Size = UDim2.new(1, -28, 1, -122)
ContentHolder.BackgroundTransparency = 1
ContentHolder.ZIndex = 2
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
    page.ZIndex = 2
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
    btn.ZIndex = 3
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
    card.BackgroundTransparency = 0.25
    card.BorderSizePixel = 0
    card.ZIndex = 3
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
    label.ZIndex = 4
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
        sub.ZIndex = 4
        sub.Parent = row
    end

    local switchBtn = Instance.new("TextButton")
    switchBtn.AnchorPoint = Vector2.new(1, 0.5)
    switchBtn.Position = UDim2.new(1, -14, 0.5, 0)
    switchBtn.Size = UDim2.fromOffset(44, 24)
    switchBtn.Text = ""
    switchBtn.AutoButtonColor = false
    switchBtn.BorderSizePixel = 0
    switchBtn.ZIndex = 4
    switchBtn.Parent = row

    local swCorner = Instance.new("UICorner")
    swCorner.CornerRadius = UDim.new(1, 0)
    swCorner.Parent = switchBtn

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0, 0.5)
    knob.Size = UDim2.fromOffset(18, 18)
    knob.BackgroundColor3 = Palette.TextPrimary
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
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
    label.ZIndex = 4
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
    valueLabel.ZIndex = 4
    valueLabel.Parent = row

    local trackHitbox = Instance.new("TextButton")
    trackHitbox.BackgroundTransparency = 1
    trackHitbox.Text = ""
    trackHitbox.AutoButtonColor = false
    trackHitbox.AnchorPoint = Vector2.new(0.5, 0)
    trackHitbox.Position = UDim2.new(0.5, 0, 0, 32)
    trackHitbox.Size = UDim2.new(1, -28, 0, 22)
    trackHitbox.ZIndex = 5
    trackHitbox.Parent = row

    local track = Instance.new("Frame")
    track.AnchorPoint = Vector2.new(0.5, 0.5)
    track.Position = UDim2.fromScale(0.5, 0.5)
    track.Size = UDim2.new(1, 0, 0, 6)
    track.BackgroundColor3 = Palette.ToggleOff
    track.BorderSizePixel = 0
    track.ZIndex = 4
    track.Parent = trackHitbox

    local trackCorner = Instance.new("UICorner")
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new("Frame")
    fill.Size = UDim2.fromScale(0.5, 1)
    fill.BackgroundColor3 = Palette.Accent
    fill.BorderSizePixel = 0
    fill.ZIndex = 5
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
    thumb.ZIndex = 6
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
    label.ZIndex = 4
    label.Parent = row

    local bar = Instance.new("Frame")
    bar.AnchorPoint = Vector2.new(0.5, 0)
    bar.Position = UDim2.new(0.5, 0, 0, 32)
    bar.Size = UDim2.new(1, -28, 0, 26)
    bar.BackgroundColor3 = Palette.ObsidianBase
    bar.BackgroundTransparency = 0.2
    bar.BorderSizePixel = 0
    bar.ZIndex = 4
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
        b.TextSize = 11
        b.AutoButtonColor = false
        b.BorderSizePixel = 0
        b.ZIndex = 5
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

addSelector(AimbotPage, 3, "Target Bone", {"Head", "Torso", "Closest"}, function()
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

addToggle(AimbotPage, 6, "Show FOV Ring", "Draws a centered FOV ring around the reticle", function()
    return Config.Aimbot.ShowFOV
end, function(v)
    Config.Aimbot.ShowFOV = v
end)

addToggle(AimbotPage, 7, "Team Check", "Ignores teammates on matching teams", function()
    return Config.Aimbot.TeamCheck
end, function(v)
    Config.Aimbot.TeamCheck = v
end)

addToggle(AimbotPage, 8, "Visible / Wall Check", "Raycasts to ignore targets behind solid cover", function()
    return Config.Aimbot.VisibleCheck
end, function(v)
    Config.Aimbot.VisibleCheck = v
end)

addToggle(AimbotPage, 9, "Sticky Target Lock", "Keeps lock on active target while valid", function()
    return Config.Aimbot.StickyTarget
end, function(v)
    Config.Aimbot.StickyTarget = v
end)

-- ESP TAB
local EspPage = TabPages.ESP
addToggle(EspPage, 1, "Master ESP", "Enables or disables all visual overlays", function()
    return Config.ESP.Enabled
end, function(v)
    Config.ESP.Enabled = v
end)

addToggle(EspPage, 2, "2D Box ESP", "Dynamic 3D-projected bounding boxes", function()
    return Config.ESP.BoxESP
end, function(v)
    Config.ESP.BoxESP = v
end)

addToggle(EspPage, 3, "Line ESP (Tracers)", "Draws tracer lines from screen edge to targets", function()
    return Config.ESP.TracerESP
end, function(v)
    Config.ESP.TracerESP = v
end)

addSelector(EspPage, 4, "Tracer Origin", {"Bottom", "Center", "Top"}, function()
    return Config.ESP.TracerOrigin
end, function(v)
    Config.ESP.TracerOrigin = v
end)

addToggle(EspPage, 5, "360° Out-of-FOV Alert", "Directional ring arrows for off-screen enemies", function()
    return Config.ESP.Alert360
end, function(v)
    Config.ESP.Alert360 = v
end)

addToggle(EspPage, 6, "Highlight ESP", "Character silhouette highlight overlay", function()
    return Config.ESP.HighlightESP
end, function(v)
    Config.ESP.HighlightESP = v
end)

addToggle(EspPage, 7, "Name & Distance", "Displays target display name and meters", function()
    return Config.ESP.ShowNameDistance
end, function(v)
    Config.ESP.ShowNameDistance = v
end)

addToggle(EspPage, 8, "ESP Team Check", "Hides ESP overlays for teammates", function()
    return Config.ESP.TeamCheck
end, function(v)
    Config.ESP.TeamCheck = v
end)

addToggle(EspPage, 9, "ESP Visible Only", "Hides ESP completely when obstructed by walls", function()
    return Config.ESP.VisibleCheck
end, function(v)
    Config.ESP.VisibleCheck = v
end)

addToggle(EspPage, 10, "Color By Visibility", "Tints visible vs hidden targets dynamically", function()
    return Config.ESP.ColorByVisibility
end, function(v)
    Config.ESP.ColorByVisibility = v
end)

-- COLORS TAB
local ColorsPage = TabPages.Colors
local ColorKeys = {"Enemy", "Visible", "Hidden", "Tracer", "Alert360", "Highlight", "FOV"}

local ChannelCard = createCardRow(ColorsPage, 84, 1)
local ChannelTitle = Instance.new("TextLabel")
ChannelTitle.BackgroundTransparency = 1
ChannelTitle.Position = UDim2.fromOffset(14, 8)
ChannelTitle.Size = UDim2.new(1, -70, 0, 18)
ChannelTitle.Font = Enum.Font.GothamMedium
ChannelTitle.Text = "Color Channel"
ChannelTitle.TextSize = 13
ChannelTitle.TextColor3 = Palette.TextPrimary
ChannelTitle.TextXAlignment = Enum.TextXAlignment.Left
ChannelTitle.ZIndex = 4
ChannelTitle.Parent = ChannelCard

local LiveSwatch = Instance.new("Frame")
LiveSwatch.AnchorPoint = Vector2.new(1, 0)
LiveSwatch.Position = UDim2.new(1, -14, 0, 8)
LiveSwatch.Size = UDim2.fromOffset(42, 18)
LiveSwatch.BorderSizePixel = 0
LiveSwatch.ZIndex = 4
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
ChannelGridHolder.Size = UDim2.new(1, -28, 0, 44)
ChannelGridHolder.BackgroundTransparency = 1
ChannelGridHolder.ZIndex = 4
ChannelGridHolder.Parent = ChannelCard

local ChannelGrid = Instance.new("UIGridLayout")
ChannelGrid.CellSize = UDim2.new(0.25, -4, 0, 20)
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

for idx, key in ipairs(ColorKeys) do
    local b = Instance.new("TextButton")
    b.LayoutOrder = idx
    b.Text = key
    b.Font = Enum.Font.GothamMedium
    b.TextSize = 10
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.ZIndex = 5
    b.Parent = ChannelGridHolder

    local bc = Instance.new("UICorner")
    bc.CornerRadius = UDim.new(0, 6)
    bc.Parent = b

    b.Activated:Connect(function()
        Config.UI.SelectedColorKey = key
        refreshColorControls()
    end)

    channelBtns[key] = b
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
SwatchTitle.ZIndex = 4
SwatchTitle.Parent = SwatchesCard

local SwatchRow = Instance.new("Frame")
SwatchRow.AnchorPoint = Vector2.new(0.5, 0)
SwatchRow.Position = UDim2.new(0.5, 0, 0, 32)
SwatchRow.Size = UDim2.new(1, -28, 0, 24)
SwatchRow.BackgroundTransparency = 1
SwatchRow.ZIndex = 4
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
    sb.ZIndex = 5
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
addSlider(SystemPage, 1, "Max Render Distance", 200, 3000, 50, function(v)
    return string.format("%dm", math.round(v))
end, function()
    return Config.ESP.MaxDistance
end, function(v)
    Config.ESP.MaxDistance = v
    Config.Aimbot.MaxDistance = v
end)

addSlider(SystemPage, 2, "360° Alert Ring Radius", 80, 280, 5, function(v)
    return string.format("%d px", math.round(v))
end, function()
    return Config.ESP.AlertRingRadius
end, function(v)
    Config.ESP.AlertRingRadius = v
end)

local ActionCard = createCardRow(SystemPage, 54, 3)
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
ResetBtn.ZIndex = 5
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
UnloadBtn.ZIndex = 5
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
MobileToggle.Size = UDim2.fromOffset(106, 38)
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
        MainCard.Size = UDim2.fromOffset(440, 360)
        MainCard.BackgroundTransparency = 0.45
        tween(MainCard, 0.2, {
            Size = UDim2.fromOffset(470, 390),
            BackgroundTransparency = 0.14,
        })
        tween(ToggleStroke, 0.18, {Color = Palette.Accent})
    else
        local tw = tween(MainCard, 0.16, {
            Size = UDim2.fromOffset(440, 360),
            BackgroundTransparency = 0.6,
        })
        local completedConn
        completedConn = tw.Completed:Connect(function()
            if completedConn then
                completedConn:Disconnect()
            end
            if not Config.UI.Visible then
                MainCard.Visible = false
            end
        end)
        tween(ToggleStroke, 0.18, {Color = Palette.StrokeCool})
    end
end

-- Distinguish tap vs drag cleanly on mobile & desktop (multi-touch isolated)
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
