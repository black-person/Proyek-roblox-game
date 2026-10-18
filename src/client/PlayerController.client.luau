--!strict
-- Lokasi: StarterPlayer/StarterCharacterScripts/PlayerController

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:FindFirstChild("shared") or ReplicatedStorage:FindFirstChild("Modules")
local GameConfigModule = ((SharedFolder and SharedFolder:FindFirstChild("GameConfig"))
	or ReplicatedStorage:FindFirstChild("GameConfig")) :: ModuleScript?

if not GameConfigModule or not GameConfigModule:IsA("ModuleScript") then
	error("GameConfig ModuleScript not found in ReplicatedStorage")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local SprintEvent = Remotes:WaitForChild("SprintEvent") :: RemoteEvent
local DodgeEvent = Remotes:WaitForChild("DodgeEvent") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local torso = character:WaitForChild("Torso") :: BasePart
local rightShoulder = torso:WaitForChild("Right Shoulder") :: Motor6D
local defaultRightShoulderC0 = rightShoulder.C0

local currentStamina: number = GameConfig.Player.MaxStamina
local isMobileSprintPressed: boolean = false
local isSprinting: boolean = false
local lastStaminaUseTime: number = 0

local lastAttackClient: number = 0
local lastDodgeClient: number = 0

character:SetAttribute("MaxStamina", GameConfig.Player.MaxStamina)
character:SetAttribute("Stamina", currentStamina)

local function setSprintState(active: boolean)
	if isSprinting == active then return end
	isSprinting = active
	SprintEvent:FireServer(active)
end

local function playSwingVisual()
	local swingUp = TweenService:Create(rightShoulder, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = defaultRightShoulderC0 * CFrame.Angles(0, 0, math.rad(110))
	})
	local swingDown = TweenService:Create(rightShoulder, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		C0 = defaultRightShoulderC0 * CFrame.Angles(0, math.rad(25), math.rad(-20))
	})
	local resetArm = TweenService:Create(rightShoulder, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		C0 = defaultRightShoulderC0
	})

	swingUp:Play()
	swingUp.Completed:Connect(function()
		swingDown:Play()
		swingDown.Completed:Connect(function()
			resetArm:Play()
		end)
	end)
end

local function handleSprintAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if actionName ~= "SprintAction" then return Enum.ContextActionResult.Pass end
	if inputState == Enum.UserInputState.Begin then
		isMobileSprintPressed = true
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		isMobileSprintPressed = false
	end
	return Enum.ContextActionResult.Pass
end

local function handleDodgeAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if actionName ~= "DodgeAction" or inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if humanoid.Health <= 0 or character:GetAttribute("IsDodging") then
		return Enum.ContextActionResult.Pass
	end

	local now = os.clock()
	if (now - lastDodgeClient) < GameConfig.Player.DodgeCooldown then
		return Enum.ContextActionResult.Pass
	end

	local staminaCost = GameConfig.Player.DodgeStaminaCost
	if currentStamina < staminaCost then
		return Enum.ContextActionResult.Pass
	end

	currentStamina = math.max(0, currentStamina - staminaCost)
	character:SetAttribute("Stamina", currentStamina)
	lastStaminaUseTime = now
	lastDodgeClient = now

	if isSprinting then
		setSprintState(false)
	end

	DodgeEvent:FireServer(humanoid.MoveDirection)
	return Enum.ContextActionResult.Sink
end

-- Serangan Terpusat (Mengirim arah kamera untuk Pistol & mengayunkan tangan untuk Melee)
local function performAttack()
	if humanoid.Health <= 0 then return end

	local now = os.clock()
	if (now - lastAttackClient) < GameConfig.Player.AttackCooldown then
		return
	end

	lastAttackClient = now
	playSwingVisual()

	local cam = workspace.CurrentCamera
	local camCFrame = if cam then cam.CFrame else character:GetPivot()
	CombatEvent:FireServer(camCFrame)
end

local function handleAttackAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if actionName == "AttackAction" and inputState == Enum.UserInputState.Begin then
		performAttack()
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("SprintAction", handleSprintAction, true, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("SprintAction", "Lari")
ContextActionService:SetPosition("SprintAction", UDim2.fromScale(0.70, 0.55))

ContextActionService:BindAction("DodgeAction", handleDodgeAction, true, Enum.KeyCode.V, Enum.KeyCode.ButtonB)
ContextActionService:SetTitle("DodgeAction", "Dodge")
ContextActionService:SetPosition("DodgeAction", UDim2.fromScale(0.82, 0.55))

ContextActionService:BindAction("AttackAction", handleAttackAction, true, Enum.KeyCode.ButtonR2)
ContextActionService:SetTitle("AttackAction", "Serang")
ContextActionService:SetPosition("AttackAction", UDim2.fromScale(0.76, 0.35))

local mouseConn = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		performAttack()
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	if humanoid.Health <= 0 then
		if isSprinting then setSprintState(false) end
		return
	end

	local isShiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	local wantsSprint = isShiftDown or isMobileSprintPressed
	local isMoving = humanoid.MoveDirection.Magnitude > 0.1
	local canSprint = wantsSprint and isMoving and currentStamina > 0 and not character:GetAttribute("IsDodging")

	if canSprint then
		if not isSprinting then
			setSprintState(true)
		end

		currentStamina = math.max(0, currentStamina - (GameConfig.Player.StaminaDrainRate * deltaTime))
		character:SetAttribute("Stamina", currentStamina)
		lastStaminaUseTime = os.clock()

		if currentStamina <= 0 then
			setSprintState(false)
		end
	else
		if isSprinting then
			setSprintState(false)
			lastStaminaUseTime = os.clock()
		end

		if currentStamina < GameConfig.Player.MaxStamina then
			if (os.clock() - lastStaminaUseTime) >= GameConfig.Player.StaminaRegenDelay then
				currentStamina = math.min(GameConfig.Player.MaxStamina, currentStamina + (GameConfig.Player.StaminaRegenRate * deltaTime))
				character:SetAttribute("Stamina", currentStamina)
			end
		end
	end
end)

character.Destroying:Connect(function()
	ContextActionService:UnbindAction("SprintAction")
	ContextActionService:UnbindAction("DodgeAction")
	ContextActionService:UnbindAction("AttackAction")
	mouseConn:Disconnect()
end)