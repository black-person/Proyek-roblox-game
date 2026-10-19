--!strict
-- Lokasi: src/client/PlayerController.client.luau

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage:WaitForChild("Shared", 3)
	or ReplicatedStorage:WaitForChild("shared", 3)
	or ReplicatedStorage:FindFirstChild("Modules")

local GameConfigModule = ((SharedFolder and SharedFolder:FindFirstChild("GameConfig"))
	or ReplicatedStorage:FindFirstChild("GameConfig", true)) :: ModuleScript?

if not GameConfigModule or not GameConfigModule:IsA("ModuleScript") then
	error("[PlayerController] GameConfig tidak ditemukan di ReplicatedStorage!")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SprintEvent = Remotes:WaitForChild("SprintEvent") :: RemoteEvent
local DodgeEvent = Remotes:WaitForChild("DodgeEvent") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local character = (script:FindFirstAncestorOfClass("Model") or player.Character or player.CharacterAdded:Wait()) :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
local torso = character:WaitForChild("Torso") :: BasePart
local rightShoulder = torso:WaitForChild("Right Shoulder") :: Motor6D
local defaultRightShoulderC0 = rightShoulder.C0

local currentStamina: number = GameConfig.Player.MaxStamina
local isMobileSprintPressed: boolean = false
local isSprinting: boolean = false
local isDodgingClient: boolean = false
local lastStaminaUseTime: number = 0

local lastAttackClient: number = 0
local lastDodgeClient: number = 0

character:SetAttribute("MaxStamina", GameConfig.Player.MaxStamina)
character:SetAttribute("Stamina", currentStamina)

-- Fungsi mengubah status Sprint (Langsung ubah WalkSpeed di Client + sinkron ke Server)
local function setSprintState(active: boolean)
	if isSprinting == active then return end
	isSprinting = active
	if not isDodgingClient then
		humanoid.WalkSpeed = if active then GameConfig.Player.SprintSpeed else GameConfig.Player.WalkSpeed
	end
	SprintEvent:FireServer(active)
end

-- Visual Ayunan Tangan R6
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

-- Handler Dodge (Tombol V) - Dorongan Fisika Langsung Terasa!
local function handleDodgeAction(actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if actionName ~= "DodgeAction" or inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if humanoid.Health <= 0 or isDodgingClient then
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
	isDodgingClient = true
	
	if isSprinting then
		setSprintState(false)
	end
	
	-- Arah menghindar mengikuti arah jalan (WASD) atau arah hadap karakter jika diam
	local moveDir = humanoid.MoveDirection
	local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	local dodgeDir = if flatDir.Magnitude > 0.1 then flatDir.Unit else rootPart.CFrame.LookVector
	
	-- Terapkan dorongan kecepatan langsung di Client agar tidak delay
	rootPart.AssemblyLinearVelocity = Vector3.new(
		dodgeDir.X * GameConfig.Player.DodgeSpeed,
		rootPart.AssemblyLinearVelocity.Y,
		dodgeDir.Z * GameConfig.Player.DodgeSpeed
	)
	
	DodgeEvent:FireServer(dodgeDir)
	
	task.delay(GameConfig.Player.DodgeDuration, function()
		isDodgingClient = false
		humanoid.WalkSpeed = if isSprinting then GameConfig.Player.SprintSpeed else GameConfig.Player.WalkSpeed
	end)
	
	return Enum.ContextActionResult.Sink
end

-- Handler Serangan (Mengirim titik tembak ke arah kursor Mouse untuk Pistol)
local function performAttack()
	if humanoid.Health <= 0 then return end
	
	local now = os.clock()
	if (now - lastAttackClient) < GameConfig.Player.AttackCooldown then
		return
	end
	
	lastAttackClient = now
	playSwingVisual()
	
	local originPos = rootPart.Position + Vector3.new(0, 1.5, 0)
	local targetPos = mouse.Hit.Position
	local aimDirection = (targetPos - originPos)
	if aimDirection.Magnitude < 0.1 then
		aimDirection = rootPart.CFrame.LookVector
	end
	
	CombatEvent:FireServer(originPos, aimDirection.Unit)
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
	local canSprint = wantsSprint and isMoving and currentStamina > 0 and not isDodgingClient
	
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