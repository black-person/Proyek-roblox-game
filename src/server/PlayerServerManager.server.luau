--!strict
-- Lokasi: ServerScriptService/PlayerServerManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local gameConfigModule = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig") :: ModuleScript
local loadModule = require
local GameConfig = loadModule(gameConfigModule)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local SprintEvent = Remotes:WaitForChild("SprintEvent") :: RemoteEvent
local DodgeEvent = Remotes:WaitForChild("DodgeEvent") :: RemoteEvent
local CombatEvent = Remotes:WaitForChild("CombatEvent") :: RemoteEvent

local lastAttackTime: {[Player]: number} = {}
local lastDodgeTime: {[Player]: number} = {}

-- Fungsi memunculkan angka Damage saja (tanpa teks nama senjata)
local function showDamageIndicator(targetModel: Model, damageAmount: number)
	local head = (targetModel:FindFirstChild("Head") or targetModel:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not head then return end

	local bgui = Instance.new("BillboardGui")
	bgui.Size = UDim2.fromOffset(90, 36)
	bgui.StudsOffset = Vector3.new((math.random() - 0.5) * 2, 2.5, 0)
	bgui.AlwaysOnTop = true
	bgui.Parent = head

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = if damageAmount >= 50 then Color3.fromHex("#D9A441") else Color3.fromHex("#FF4444")
	text.TextStrokeTransparency = 0
	text.TextScaled = true
	text.Text = string.format("-%d", damageAmount) -- Hanya angka damage
	text.Parent = bgui

	local tween = TweenService:Create(bgui, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = bgui.StudsOffset + Vector3.new(0, 3, 0)
	})
	tween:Play()
	Debris:AddItem(bgui, 0.75)
end

local function checkVIPGamePass(player: Player): boolean
	if not GameConfig.GamePass or GameConfig.GamePass.VIPCardId <= 0 then
		return false
	end
	local success, hasPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, GameConfig.GamePass.VIPCardId)
	end)
	return success and hasPass
end

local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid

	humanoid.MaxHealth = GameConfig.Player.MaxHP
	humanoid.Health = GameConfig.Player.MaxHP
	humanoid.WalkSpeed = GameConfig.Player.WalkSpeed

	character:SetAttribute("IsSprinting", false)
	character:SetAttribute("IsDodging", false)
end

local function onPlayerAdded(player: Player)
	local hasVIP = checkVIPGamePass(player)
	player:SetAttribute("HasVIPCard", hasVIP)

	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastAttackTime[player] = nil
	lastDodgeTime[player] = nil
end)

-- 1. Handler Sprint
SprintEvent.OnServerEvent:Connect(function(player: Player, wantsToSprint: unknown)
	if typeof(wantsToSprint) ~= "boolean" then return end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	if character:GetAttribute("IsDodging") then return end

	character:SetAttribute("IsSprinting", wantsToSprint)
	humanoid.WalkSpeed = if wantsToSprint then GameConfig.Player.SprintSpeed else GameConfig.Player.WalkSpeed
end)

-- 2. Handler Dodge
DodgeEvent.OnServerEvent:Connect(function(player: Player, moveDir: unknown)
	if typeof(moveDir) ~= "Vector3" then return end

	local now = os.clock()
	if lastDodgeTime[player] and (now - lastDodgeTime[player]) < (GameConfig.Player.DodgeCooldown - 0.1) then
		return
	end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end
	if character:GetAttribute("IsDodging") then return end

	lastDodgeTime[player] = now
	character:SetAttribute("IsDodging", true)

	local flatDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	local dodgeDir = if flatDir.Magnitude > 0.1 then flatDir.Unit else rootPart.CFrame.LookVector

	local attachment = Instance.new("Attachment")
	attachment.Parent = rootPart

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Attachment0 = attachment
	linearVel.MaxForce = 25000
	linearVel.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linearVel.PrimaryTangentAxis = Vector3.new(1, 0, 0)
	linearVel.SecondaryTangentAxis = Vector3.new(0, 0, 1)
	linearVel.PlaneVelocity = Vector2.new(dodgeDir.X, dodgeDir.Z) * GameConfig.Player.DodgeSpeed
	linearVel.Parent = rootPart

	Debris:AddItem(linearVel, GameConfig.Player.DodgeDuration)
	Debris:AddItem(attachment, GameConfig.Player.DodgeDuration)

	task.delay(GameConfig.Player.DodgeDuration, function()
		if character and character.Parent then
			character:SetAttribute("IsDodging", false)
			local isSprinting = character:GetAttribute("IsSprinting") == true
			humanoid.WalkSpeed = if isSprinting then GameConfig.Player.SprintSpeed else GameConfig.Player.WalkSpeed
		end
	end)
end)

local function getWeaponType(tool: Tool): string
	local toolNameLower = string.lower(tool.Name)
	if string.find(toolNameLower, "pipa") or string.find(toolNameLower, "ironpipe") then
		return "IronPipe"
	elseif string.find(toolNameLower, "pedang") or string.find(toolNameLower, "sword") then
		return "Sword"
	elseif string.find(toolNameLower, "pistol") then
		return "Pistol"
	end

	local attrType = tool:GetAttribute("WeaponType")
	if typeof(attrType) == "string" then
		return attrType
	end
	return "Unarmed"
end

-- 3. Handler Combat Event
CombatEvent.OnServerEvent:Connect(function(player: Player, targetLookCFrame: unknown)
	local now = os.clock()
	if lastAttackTime[player] and (now - lastAttackTime[player]) < (GameConfig.Player.AttackCooldown - 0.05) then
		return
	end

	local character = player.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	lastAttackTime[player] = now

	local equippedTool = character:FindFirstChildOfClass("Tool")
	local damage = GameConfig.Player.UnarmedDamage or 10
	local weaponName = "Unarmed"
	local displayLabel = "Tangan"
	local isRanged = false

	if equippedTool then
		weaponName = getWeaponType(equippedTool)
		if weaponName == "IronPipe" then
			damage = GameConfig.Weapons.IronPipe.Damage
			displayLabel = "Pipa Besi"
		elseif weaponName == "Sword" then
			damage = GameConfig.Weapons.Sword.Damage
			displayLabel = "Pedang"
		elseif weaponName == "Pistol" then
			damage = GameConfig.Weapons.Pistol.Damage
			displayLabel = "Pistol"
			isRanged = true
		end
	end

	local hitAnyTarget = false

	if isRanged and equippedTool then
		-- ================= KASUS PISTOL (RAYCAST 20 STUDS) =================
		local maxAmmo = GameConfig.Weapons.Pistol.MaxAmmo
		local currentAmmo = (equippedTool:GetAttribute("Ammo") :: number?) or maxAmmo

		if currentAmmo <= 0 then
			print("[COMBAT-PISTOL] Klik! Peluru Pistol habis (0/10)!")
			return
		end

		currentAmmo -= 1
		equippedTool:SetAttribute("Ammo", currentAmmo)
		equippedTool.Name = string.format("Pistol (%d/%d)", currentAmmo, maxAmmo)
		equippedTool.ToolTip = string.format("Peluru: %d/%d", currentAmmo, maxAmmo)

		local origin = rootPart.Position + Vector3.new(0, 1.5, 0)
		local direction = rootPart.CFrame.LookVector * 20

		if typeof(targetLookCFrame) == "CFrame" then
			origin = targetLookCFrame.Position
			direction = targetLookCFrame.LookVector * 20
		end

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {character}

		local result = workspace:Raycast(origin, direction, raycastParams)
		if result and result.Instance then
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			if hitModel then
				local targetHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and targetHumanoid.Health > 0 and not Players:GetPlayerFromCharacter(hitModel) then
					targetHumanoid:TakeDamage(damage)
					showDamageIndicator(hitModel, damage)
					hitAnyTarget = true
				end
			end
		end

	else
		-- ================= KASUS MELEE (Tangan Kosong / Pipa Besi / Pedang) =================
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character}

		local hitboxCFrame = rootPart.CFrame * CFrame.new(0, 0, -(GameConfig.Player.AttackRange / 2))
		local hitboxSize = Vector3.new(4.5, 5, GameConfig.Player.AttackRange)

		local partsInBox = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
		local hitHumanoids: {[Humanoid]: boolean} = {}

		for _, part in partsInBox do
			local model = part:FindFirstAncestorOfClass("Model")
			if model then
				local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and targetHumanoid.Health > 0 and not hitHumanoids[targetHumanoid] then
					if not Players:GetPlayerFromCharacter(model) then
						hitHumanoids[targetHumanoid] = true
						targetHumanoid:TakeDamage(damage)
						showDamageIndicator(model, damage)
						hitAnyTarget = true
					end
				end
			end
		end

		-- Kurangi durability Pipa Besi (25) / Pedang (40)
		if hitAnyTarget and equippedTool and (weaponName == "IronPipe" or weaponName == "Sword") then
			local maxDur = if weaponName == "IronPipe" then GameConfig.Weapons.IronPipe.MaxDurability else GameConfig.Weapons.Sword.MaxDurability
			local currentDurability = (equippedTool:GetAttribute("Durability") :: number?) or maxDur

			currentDurability -= 1
			equippedTool:SetAttribute("Durability", currentDurability)

			equippedTool.Name = string.format("%s (%d/%d)", displayLabel, currentDurability, maxDur)
			equippedTool.ToolTip = string.format("Durability: %d/%d", currentDurability, maxDur)

			if currentDurability <= 0 then
				equippedTool:Destroy()
			end
		end
	end
end)