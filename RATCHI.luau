-- LocalScript (mets-le dans StarterPlayerScripts ou StarterGui)
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

task.spawn(function()
task.wait(3)
local RS   = game:GetService("ReplicatedStorage")
local UIS  = game:GetService("UserInputService")
local Plrs = game:GetService("Players")
local LP   = Plrs.LocalPlayer
local Cam  = workspace.CurrentCamera

local Utils        = RS:WaitForChild("Utils", 30)
local CameraCtrl   = Utils:WaitForChild("CameraController", 30)
local RemoteFolder = RS:WaitForChild("Remote", 30)
local EventFolder  = RemoteFolder:WaitForChild("Event", 30)
local GameFolder   = EventFolder:WaitForChild("Game", 30)
local SyncAngles   = GameFolder:WaitForChild("[C-S]SyncCameraAngles", 30)
local CC           = require(CameraCtrl)

local FOV            = 400
local HOLD_MS        = 300
local WALL_CHECK     = true
local TEAM_CHECK     = false

local STICKY_MS         = 0
local PRIORITIZE_LOW_HP = false
local LOW_HP_THRESHOLD  = 30
local PREDICT_VELOCITY  = false
local PREDICT_FACTOR    = 0.05

local PART_ORDER = {
    "Head",
    "UpperTorso", "Torso",
    "HumanoidRootPart",
    "RightUpperArm", "LeftUpperArm", "Right Arm", "Left Arm",
    "RightLowerArm", "LeftLowerArm",
    "RightUpperLeg", "LeftUpperLeg", "Right Leg", "Left Leg",
    "RightLowerLeg", "LeftLowerLeg",
}

local phantom       = false
local phantomAngles = nil
local stickyTarget  = nil
local stickyExpire  = 0

local fovGui = Instance.new("ScreenGui")
fovGui.Name = "SA_FOV"
fovGui.ResetOnSpawn = false
fovGui.IgnoreGuiInset = true
fovGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
fovGui.Parent = LP:WaitForChild("PlayerGui")

local fovCircle = Instance.new("Frame")
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.fromScale(0.5, 0.5)
fovCircle.Size = UDim2.fromOffset(FOV * 2, FOV * 2)
fovCircle.BackgroundTransparency = 1
fovCircle.Parent = fovGui
Instance.new("UICorner", fovCircle).CornerRadius = UDim.new(1, 0)

local fovStroke = Instance.new("UIStroke")
fovStroke.Color = Color3.fromRGB(120, 200, 255)
fovStroke.Thickness = 1.5
fovStroke.Transparency = 0.3
fovStroke.Parent = fovCircle

local fovFill = Instance.new("Frame")
fovFill.AnchorPoint = Vector2.new(0.5, 0.5)
fovFill.Position = UDim2.fromScale(0.5, 0.5)
fovFill.Size = UDim2.fromScale(1, 1)
fovFill.BackgroundColor3 = Color3.fromRGB(120, 200, 255)
fovFill.BackgroundTransparency = 0.95
fovFill.BorderSizePixel = 0
fovFill.Parent = fovCircle
Instance.new("UICorner", fovFill).CornerRadius = UDim.new(1, 0)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function BuildIgnoreList(targetChar)
    local ignore = {}
    if LP.Character then table.insert(ignore, LP.Character) end
    if targetChar then table.insert(ignore, targetChar) end
    for _, name in ipairs({"HandModel", "Viewmodel", "ViewModel", "Arms", "WeaponsFolder", "ViewmodelClient", "TempHands"}) do
        local obj = workspace:FindFirstChild(name)
        if obj then table.insert(ignore, obj) end
    end
    return ignore
end

local function IsPointVisible(point, targetChar)
    rayParams.FilterDescendantsInstances = BuildIgnoreList(targetChar)
    local result = workspace:Raycast(Cam.CFrame.Position, point - Cam.CFrame.Position, rayParams)
    if result == nil then return true end
    if targetChar and result.Instance:IsDescendantOf(targetChar) then return true end
    if result.Instance.Transparency >= 0.9 then return true end
    return false
end

local function GetVisiblePart(character)
    if not character then return nil end
    for _, partName in ipairs(PART_ORDER) do
        local part = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") and part.Transparency < 0.95 then
            if not WALL_CHECK or IsPointVisible(part.Position, character) then
                return part
            end
        end
    end
    return nil
end

local function IsTeammate(character)
    if not TEAM_CHECK or not character then return false end
    local myTeam   = LP:GetAttribute("Team")
    local charTeam = character:GetAttribute("Team")
    if myTeam and charTeam then return charTeam == myTeam end
    for _, p in ipairs(Plrs:GetPlayers()) do
        if p.Character == character then
            if not p.Team or not LP.Team then return false end
            return p.Team == LP.Team
        end
    end
    return false
end

local targetsCache     = {}
local targetsCacheTime = 0
local CACHE_TTL        = 0.4

local function CollectTargets()
    if tick() - targetsCacheTime < CACHE_TTL then
        return targetsCache
    end

    local list = {}
    local seen = {}
    local function add(c)
        if c and c.Parent and not seen[c] then
            seen[c] = true
            table.insert(list, c)
        end
    end

    for _, p in ipairs(Plrs:GetPlayers()) do
        if p ~= LP and p.Character then add(p.Character) end
    end

    local pc = workspace:FindFirstChild("PlayersCharacters")
    if pc then
        for _, obj in ipairs(pc:GetChildren()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then add(obj) end
        end
    end

    local tr = workspace:FindFirstChild("Training_range")
    if tr then
        local bt = tr:FindFirstChild("Bot_template")
        if bt then
            for _, obj in ipairs(bt:GetChildren()) do
                if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then add(obj) end
            end
        end
    end

    targetsCache     = list
    targetsCacheTime = tick()
    return list
end

local function GetTarget()
    local mp = UIS:GetMouseLocation()

    if STICKY_MS > 0 and stickyTarget and tick() < stickyExpire then
        local char = stickyTarget
        local h = char:FindFirstChildOfClass("Humanoid")
        if h and h.Health > 0 and char.Parent then
            local part = GetVisiblePart(char)
            if part then
                local sp, on = Cam:WorldToViewportPoint(part.Position)
                if on and sp.Z > 0 then
                    local d = (Vector2.new(sp.X, sp.Y) - mp).Magnitude
                    if d < FOV then
                        return char, part
                    end
                end
            end
        end
        stickyTarget = nil
    end

    local best, bestDist, bestPart = nil, math.huge, nil

    for _, character in ipairs(CollectTargets()) do
        if character ~= LP.Character and not IsTeammate(character) then
            local h = character:FindFirstChildOfClass("Humanoid")
            if h and h.Health > 0 then
                local part = GetVisiblePart(character)
                if part then
                    local sp, on = Cam:WorldToViewportPoint(part.Position)
                    if on and sp.Z > 0 then
                        local d = (Vector2.new(sp.X, sp.Y) - mp).Magnitude
                        if d < FOV then
                            if PRIORITIZE_LOW_HP and h.Health <= LOW_HP_THRESHOLD then
                                d = d - 100
                            end

                            if d < bestDist then
                                bestDist = d
                                best     = character
                                bestPart = part
                            end
                        end
                    end
                end
            end
        end
    end

    if best and STICKY_MS > 0 then
        stickyTarget = best
        stickyExpire = tick() + STICKY_MS / 1000
    end

    return best, bestPart
end

local function ComputeAngles(origin, targetPos)
    local diff = targetPos - origin
    local mag  = diff.Magnitude
    if mag < 0.001 then return nil end
    return math.deg(math.asin(diff.Y / mag)),
           math.deg(math.atan2(-diff.X, -diff.Z)) % 360
end

local function ApplyPrediction(part)
    if not PREDICT_VELOCITY then return part.Position end
    if not part:IsA("BasePart") then return part.Position end
    local v = part.AssemblyLinearVelocity
    if v.Magnitude < 1 then return part.Position end
    return part.Position + v * PREDICT_FACTOR
end

local OldGetAimRay = CC.GetAimRay

CC.GetAimRay = function(self, ...)
    if phantom and phantomAngles then
        local origin = self:GetCameraPosition() or Cam.CFrame.Position
        local yawRad   = math.rad(phantomAngles.yaw)
        local pitchRad = math.rad(phantomAngles.pitch)
        local cf = CFrame.new(origin)
            * CFrame.Angles(0, yawRad, 0)
            * CFrame.Angles(pitchRad, 0, 0)
        return cf.Position, cf.LookVector
    end
    return OldGetAimRay(self, ...)
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "FireServer" and rawequal(self, SyncAngles) then
        if phantom and phantomAngles then
            return oldNamecall(self, Vector3.new(phantomAngles.pitch, phantomAngles.yaw, 0))
        end
    end
    return oldNamecall(self, ...)
end)

UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.UserInputType ~= Enum.UserInputType.MouseButton1
       and i.KeyCode ~= Enum.KeyCode.ButtonR2 then return end

    local char, part = GetTarget()
    if not char or not part then return end

    local origin = CC:GetCameraPosition() or Cam.CFrame.Position
    local aimPos = ApplyPrediction(part)
    local pitch, yaw = ComputeAngles(origin, aimPos)
    if not pitch then return end

    phantom       = true
    phantomAngles = {pitch = pitch, yaw = yaw}

    task.delay(HOLD_MS / 1000, function()
        phantom       = false
        phantomAngles = nil
    end)
end)

task.spawn(function()
    while fovCircle.Parent do
        fovCircle.Size = UDim2.fromOffset(FOV * 2, FOV * 2)
        local T = GetTarget()
        if T then
            fovStroke.Color = Color3.fromRGB(0, 255, 120)
            fovStroke.Transparency = 0.15
            fovFill.BackgroundTransparency = 0.88
        else
            fovStroke.Color = Color3.fromRGB(120, 200, 255)
            fovStroke.Transparency = 0.4
            fovFill.BackgroundTransparency = 0.95
        end
        task.wait(0.05)
    end
end)

print("╔══════════════════════════════════════════╗")
print("║  TRUE SILENT AIM (Fixed) LOADED          ║")
print("╚══════════════════════════════════════════╝")

task.wait(3)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local espBoxes = {}
local function createESP(part)
    local box = Drawing.new("Square")
    box.Size = Vector2.new(10, 10)
    box.Color = Color3.fromRGB(255, 0, 0)
    box.Thickness = 2
    box.Filled = true
    box.Visible = true
    espBoxes[part] = box
end
local function removeESP(part)
    if espBoxes[part] then
        espBoxes[part]:Remove()
        espBoxes[part] = nil
    end
end
for _, v in pairs(workspace:GetDescendants()) do
    if v:IsA("BasePart") and v.Name == "HumanoidRootPart" then
        createESP(v)
    end
end
workspace.DescendantAdded:Connect(function(descendant)
    if descendant:IsA("BasePart") and descendant.Name == "HumanoidRootPart" then
        createESP(descendant)
    end
end)
workspace.DescendantRemoving:Connect(function(descendant)
    if espBoxes[descendant] then
        removeESP(descendant)
    end
end)
RunService.Heartbeat:Connect(function()
    for part, box in pairs(espBoxes) do
        if part and part.Parent then
            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
            box.Position = Vector2.new(screenPos.X - box.Size.X / 2, screenPos.Y - box.Size.Y / 2)
            box.Visible = onScreen
        else
            removeESP(part)
        end
    end
end)

end)

-- ============================================
-- CRÉATION DU GUI COMPLET
-- ============================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HelmetLoadingHUD"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

-- Couleurs dark / néon
local COLORS = {
	Background = Color3.fromRGB(6, 8, 12),
	Panel = Color3.fromRGB(10, 13, 20),
	Accent = Color3.fromRGB(0, 200, 255),
	Accent2 = Color3.fromRGB(140, 0, 255),
	Text = Color3.fromRGB(230, 240, 255),
	Dim = Color3.fromRGB(60, 70, 90),
}

local function tween(obj, props, time, style, dir)
	style = style or Enum.EasingStyle.Quint
	dir = dir or Enum.EasingDirection.Out
	local t = TweenService:Create(obj, TweenInfo.new(time, style, dir), props)
	t:Play()
	return t
end

-- ============================================
-- PANNEAUX LATÉRAUX (style casque)
-- ============================================

local function createSidePanel(side)
	local frame = Instance.new("Frame")
	frame.Name = side .. "Panel"
	frame.BackgroundColor3 = COLORS.Panel
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(0.17, 0, 1.15, 0)
	frame.Position = side == "Left" and UDim2.new(-0.22, 0, -0.075, 0) or UDim2.new(1.05, 0, -0.075, 0)
	frame.Parent = screenGui

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 20, 30)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 10, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 5, 8))
	})
	gradient.Rotation = 90
	gradient.Parent = frame

	-- Ligne d’accent verticale
	local accent = Instance.new("Frame")
	accent.BackgroundColor3 = COLORS.Accent
	accent.BorderSizePixel = 0
	accent.Size = UDim2.new(0, 3, 0.65, 0)
	accent.Position = side == "Left" and UDim2.new(1, -3, 0.175, 0) or UDim2.new(0, 0, 0.175, 0)
	accent.Parent = frame

	local accentGrad = Instance.new("UIGradient")
	accentGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Accent),
		ColorSequenceKeypoint.new(0.5, COLORS.Accent2),
		ColorSequenceKeypoint.new(1, COLORS.Accent)
	})
	accentGrad.Rotation = 90
	accentGrad.Parent = accent

	-- Petites barres décoratives
	for i = 1, 7 do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = COLORS.Dim
		bar.BorderSizePixel = 0
		bar.Size = UDim2.new(0.5, 0, 0, 2)
		bar.Position = UDim2.new(side == "Left" and 0.22 or 0.28, 0, 0.22 + (i * 0.075), 0)
		bar.Parent = frame

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = bar
	end

	-- Petit "visor" en haut
	local topAccent = Instance.new("Frame")
	topAccent.BackgroundColor3 = COLORS.Accent
	topAccent.BorderSizePixel = 0
	topAccent.Size = UDim2.new(0.7, 0, 0, 2)
	topAccent.Position = UDim2.new(0.15, 0, 0.08, 0)
	topAccent.BackgroundTransparency = 0.3
	topAccent.Parent = frame

	return frame
end

local leftPanel = createSidePanel("Left")
local rightPanel = createSidePanel("Right")

-- ============================================
-- ZONE CENTRALE
-- ============================================

local center = Instance.new("Frame")
center.Name = "Center"
center.BackgroundTransparency = 1
center.Size = UDim2.new(0.55, 0, 0.28, 0)
center.Position = UDim2.new(0.225, 0, 0.36, 0)
center.Parent = screenGui

-- Texte principal
local mainText = Instance.new("TextLabel")
mainText.Name = "MainText"
mainText.BackgroundTransparency = 1
mainText.Size = UDim2.new(1, 0, 0.45, 0)
mainText.Position = UDim2.new(0, 0, 0.05, 0)
mainText.Font = Enum.Font.GothamBold
mainText.TextSize = 34
mainText.TextColor3 = COLORS.Text
mainText.Text = ""
mainText.TextTransparency = 1
mainText.Parent = center

-- Sous-texte
local subText = Instance.new("TextLabel")
subText.Name = "SubText"
subText.BackgroundTransparency = 1
subText.Size = UDim2.new(1, 0, 0.25, 0)
subText.Position = UDim2.new(0, 0, 0.48, 0)
subText.Font = Enum.Font.Gotham
subText.TextSize = 15
subText.TextColor3 = COLORS.Accent
subText.Text = ""
subText.TextTransparency = 1
subText.Parent = center

-- Barre de progression
local progressBG = Instance.new("Frame")
progressBG.Name = "ProgressBG"
progressBG.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
progressBG.BorderSizePixel = 0
progressBG.Size = UDim2.new(0.65, 0, 0, 5)
progressBG.Position = UDim2.new(0.175, 0, 0.85, 0)
progressBG.Parent = center

local bgCorner = Instance.new("UICorner")
bgCorner.CornerRadius = UDim.new(1, 0)
bgCorner.Parent = progressBG

local progressBar = Instance.new("Frame")
progressBar.Name = "ProgressBar"
progressBar.BackgroundColor3 = COLORS.Accent
progressBar.BorderSizePixel = 0
progressBar.Size = UDim2.new(0, 0, 1, 0)
progressBar.Parent = progressBG

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = progressBar

local barGrad = Instance.new("UIGradient")
barGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, COLORS.Accent),
	ColorSequenceKeypoint.new(1, COLORS.Accent2)
})
barGrad.Parent = progressBar

-- ============================================
-- ANIMATIONS
-- ============================================

task.wait(0.25)

-- Entrée des panneaux
tween(leftPanel, {Position = UDim2.new(-0.01, 0, -0.075, 0)}, 1.15, Enum.EasingStyle.Back)
tween(rightPanel, {Position = UDim2.new(0.84, 0, -0.075, 0)}, 1.15, Enum.EasingStyle.Back)

-- Fonction pour afficher une étape
local function showStep(main, sub, duration, progress)
	tween(mainText, {TextTransparency = 1}, 0.22)
	tween(subText, {TextTransparency = 1}, 0.22)
	task.wait(0.28)

	mainText.Text = main
	subText.Text = sub

	tween(mainText, {TextTransparency = 0}, 0.35)
	tween(subText, {TextTransparency = 0}, 0.45)
	tween(progressBar, {Size = UDim2.new(progress, 0, 1, 0)}, duration, Enum.EasingStyle.Quad)

	task.wait(duration)
end

-- ===== SÉQUENCE DEMANDÉE =====
showStep("PRÉPARATION", "Initialisation des systèmes...", 5, 0.34)
showStep("CHARGEMENT 1", "Chargement des modules principaux...", 3, 0.67)
showStep("CHARGEMENT 2", "Finalisation en cours...", 3, 1)

-- ===== SORTIE =====
task.wait(0.35)

tween(mainText, {TextTransparency = 1}, 0.4)
tween(subText, {TextTransparency = 1}, 0.4)
tween(progressBG, {BackgroundTransparency = 1}, 0.4)
tween(progressBar, {BackgroundTransparency = 1}, 0.4)

tween(leftPanel, {Position = UDim2.new(-0.28, 0, -0.075, 0)}, 0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
tween(rightPanel, {Position = UDim2.new(1.12, 0, -0.075, 0)}, 0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

task.wait(0.95)
screenGui:Destroy()