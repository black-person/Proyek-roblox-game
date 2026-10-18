--!strict
-- Lokasi: StarterPlayer/StarterPlayerScripts/HUDController

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Sembunyikan bar HP bawaan Roblox di kanan atas
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseMedkitEvent = Remotes:WaitForChild("UseMedkitEvent") :: RemoteEvent

local function lerpNumber(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local hudGui = Instance.new("ScreenGui")
hudGui.Name = "ErratumHUD"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.Parent = playerGui

-- ================= CONTAINER KIRI BAWAH (HP & STAMINA) =================
local statusContainer = Instance.new("Frame")
statusContainer.Name = "StatusContainer"
statusContainer.Size = UDim2.fromScale(0.24, 0.09)
statusContainer.Position = UDim2.fromScale(0.02, 0.88)
statusContainer.BackgroundTransparency = 1
statusContainer.Parent = hudGui

-- BAR HP (MERAH)
local hpBg = Instance.new("Frame")
hpBg.Name = "HPBarBg"
hpBg.Size = UDim2.fromScale(1, 0.48)
hpBg.Position = UDim2.fromScale(0, 0)
hpBg.BackgroundColor3 = Color3.fromHex("#1F2A2E")
hpBg.BorderSizePixel = 0
hpBg.Parent = statusContainer

local hpCorner = Instance.new("UICorner")
hpCorner.CornerRadius = UDim.new(0.2, 0)
hpCorner.Parent = hpBg

local hpFill = Instance.new("Frame")
hpFill.Name = "Fill"
hpFill.Size = UDim2.fromScale(1, 1)
hpFill.BackgroundColor3 = Color3.fromHex("#8B1E1E")
hpFill.BorderSizePixel = 0
hpFill.Parent = hpBg

local hpFillCorner = Instance.new("UICorner")
hpFillCorner.CornerRadius = UDim.new(0.2, 0)
hpFillCorner.Parent = hpFill

local hpLabel = Instance.new("TextLabel")
hpLabel.Size = UDim2.fromScale(0.95, 0.8)
hpLabel.Position = UDim2.fromScale(0.03, 0.1)
hpLabel.BackgroundTransparency = 1
hpLabel.Font = Enum.Font.GothamBold
hpLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
hpLabel.TextScaled = true
hpLabel.TextXAlignment = Enum.TextXAlignment.Left
hpLabel.Text = "HP: 100 / 100"
hpLabel.Parent = hpBg

-- BAR STAMINA (KUNING)
local staminaBg = Instance.new("Frame")
staminaBg.Name = "StaminaBarBg"
staminaBg.Size = UDim2.fromScale(1, 0.38)
staminaBg.Position = UDim2.fromScale(0, 0.58)
staminaBg.BackgroundColor3 = Color3.fromHex("#1F2A2E")
staminaBg.BorderSizePixel = 0
staminaBg.Parent = statusContainer

local stamCorner = Instance.new("UICorner")
stamCorner.CornerRadius = UDim.new(0.25, 0)
stamCorner.Parent = staminaBg

local staminaFill = Instance.new("Frame")
staminaFill.Name = "Fill"
staminaFill.Size = UDim2.fromScale(1, 1)
staminaFill.BackgroundColor3 = Color3.fromHex("#D9A441")
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaBg

local stamFillCorner = Instance.new("UICorner")
stamFillCorner.CornerRadius = UDim.new(0.25, 0)
stamFillCorner.Parent = staminaFill

local stamLabel = Instance.new("TextLabel")
stamLabel.Size = UDim2.fromScale(0.95, 0.85)
stamLabel.Position = UDim2.fromScale(0.03, 0.075)
stamLabel.BackgroundTransparency = 1
stamLabel.Font = Enum.Font.GothamBold
stamLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
stamLabel.TextScaled = true
stamLabel.TextXAlignment = Enum.TextXAlignment.Left
stamLabel.Text = "STAMINA: 100%"
stamLabel.Parent = staminaBg

-- ================= INDIKATOR MEDKIT KANAN BAWAH =================
local medkitButton = Instance.new("TextButton")
medkitButton.Name = "MedkitButton"
medkitButton.Size = UDim2.fromScale(0.18, 0.075)
medkitButton.Position = UDim2.fromScale(0.80, 0.885)
medkitButton.BackgroundColor3 = Color3.fromHex("#131B1E")
medkitButton.BackgroundTransparency = 0.15
medkitButton.BorderSizePixel = 0
medkitButton.Text = ""
medkitButton.Parent = hudGui

local medCorner = Instance.new("UICorner")
medCorner.CornerRadius = UDim.new(0.2, 0)
medCorner.Parent = medkitButton

local medStroke = Instance.new("UIStroke")
medStroke.Color = Color3.fromHex("#5FD1B3")
medStroke.Thickness = 2
medStroke.Parent = medkitButton

local medCountLabel = Instance.new("TextLabel")
medCountLabel.Name = "CountLabel"
medCountLabel.Size = UDim2.fromScale(1, 0.55)
medCountLabel.Position = UDim2.fromScale(0, 0.08)
medCountLabel.BackgroundTransparency = 1
medCountLabel.Font = Enum.Font.GothamBold
medCountLabel.TextColor3 = Color3.fromHex("#5FD1B3")
medCountLabel.TextScaled = true
medCountLabel.Text = "MEDKIT: 0"
medCountLabel.Parent = medkitButton

local medKeyLabel = Instance.new("TextLabel")
medKeyLabel.Name = "KeyLabel"
medKeyLabel.Size = UDim2.fromScale(1, 0.35)
medKeyLabel.Position = UDim2.fromScale(0, 0.62)
medKeyLabel.BackgroundTransparency = 1
medKeyLabel.Font = Enum.Font.GothamMedium
medKeyLabel.TextColor3 = Color3.fromRGB(180, 210, 205)
medKeyLabel.TextScaled = true
medKeyLabel.Text = "[ H ]"
medKeyLabel.Parent = medkitButton

local function requestUseMedkit()
	UseMedkitEvent:FireServer()
end

medkitButton.MouseButton1Click:Connect(requestUseMedkit)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.H then
		requestUseMedkit()
	end
end)

local blinkAccumulator = 0

RunService.RenderStepped:Connect(function(deltaTime: number)
	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local hpRatio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	hpFill.Size = hpFill.Size:Lerp(UDim2.fromScale(hpRatio, 1), 0.2)
	hpLabel.Text = string.format("HP: %d / %d", math.ceil(humanoid.Health), humanoid.MaxHealth)

	if hpRatio > 0 and hpRatio < 0.25 then
		blinkAccumulator += deltaTime * 8
		local alpha = (math.sin(blinkAccumulator) + 1) / 2
		hpFill.BackgroundTransparency = alpha * 0.65
	else
		blinkAccumulator = 0
		hpFill.BackgroundTransparency = 0
	end

	local stamina = (character:GetAttribute("Stamina") :: number) or 100
	local maxStamina = (character:GetAttribute("MaxStamina") :: number) or 100
	local stamRatio = math.clamp(stamina / maxStamina, 0, 1)

	staminaFill.Size = staminaFill.Size:Lerp(UDim2.fromScale(stamRatio, 1), 0.25)
	stamLabel.Text = string.format("STAMINA: %d%%", math.floor(stamRatio * 100))

	local isFull = stamRatio >= 0.99
	local targetFillTrans = if isFull then 0.45 else 0
	local targetBgTrans = if isFull then 0.55 else 0.1
	local targetTextTrans = if isFull then 0.35 else 0

	staminaFill.BackgroundTransparency = lerpNumber(staminaFill.BackgroundTransparency, targetFillTrans, 0.15)
	staminaBg.BackgroundTransparency = lerpNumber(staminaBg.BackgroundTransparency, targetBgTrans, 0.15)
	stamLabel.TextTransparency = lerpNumber(stamLabel.TextTransparency, targetTextTrans, 0.15)

	local medkitCount = (player:GetAttribute("MedkitCount") :: number) or 0
	medCountLabel.Text = string.format("MEDKIT: %d", medkitCount)
	medkitButton.BackgroundTransparency = if medkitCount > 0 then 0.15 else 0.5
	medCountLabel.TextTransparency = if medkitCount > 0 then 0 else 0.4
	medKeyLabel.TextTransparency = if medkitCount > 0 then 0 else 0.4
end)