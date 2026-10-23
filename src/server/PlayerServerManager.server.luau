--!strict
-- Lokasi: src/server/PlayerServerManager.server.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

--Cari GameConfig dengan aman 
local SharedFolder = ReplicatedStorage:WaitForChild("Shared", 3)
	or ReplicatedStorage:WaitForChild("shared", 3)
	or ReplicatedStorage:FindFirstChild("Modules")

local GameConfigModule = ((SharedFolder and SharedFolder:FindFirstChild("GameConfig"))
	or ReplicatedStorage:FindFirstChild("GameConfig", true)) :: ModuleScript?

if not GameConfigModule or not GameConfigModule:IsA("ModuleScript") then
	error("[PlayerServerManager] KRITIS: GameConfig tidak ditemukan di ReplicatedStorage!")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule)

--Memastikan Folder Remotes & semua RemoteEvent pasti ada dan tidak duplikat
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") :: Folder?
if not Remotes then
	local newRemotes = Instance.new("Folder")
	newRemotes.Name = "Remotes"
	newRemotes.Parent = ReplicatedStorage
	Remotes = newRemotes
end

local function getOrCreateRemote(name: string): RemoteEvent
	local existing = (Remotes :: Folder):FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local SprintEvent = getOrCreateRemote("SprintEvent")
local DodgeEvent = getOrCreateRemote("DodgeEvent")
local CombatEvent = getOrCreateRemote("CombatEvent")

print("[SERVER] PlayerServerManager Aktif & Siap Menerima Input!")

local lastAttackTime: {[Player]: number} = {}
local lastDodgeTime: {[Player]: number} = {}

-- Fungsi memunculkan angka Damage melayang di atas kepala Zombie
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
	text.Text = string.format("-%d", damageAmount)
	text.Parent = bgui
	
	local tween = TweenService:Create(bgui, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = bgui.StudsOffset + Vector3.new(0, 3, 0)
	})
	tween:Play()
	Debris:AddItem(bgui, 0.75)
end

-- Fungsi membuat efek visual garis peluru (Bullet Tracer) saat Pistol menembak
local function createBulletTracer(startPos: Vector3, endPos: Vector3)
	local dist = (endPos - startPos).Magnitude
	local tracer = Instance.new("Part")
	tracer.Name = "BulletTracer"
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromHex("#D9A441")
	tracer.Size = Vector3.new(0.15, 0.15, dist)
	tracer.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -dist / 2)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.08)
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

-- ================= 1. HANDLER SPRINT =================
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

-- ================= 2. HANDLER DODGE =================
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

	-- Dorongan cepat menggunakan AssemblyLinearVelocity + LinearVelocity agar 100% terasa di R6
	rootPart.AssemblyLinearVelocity = Vector3.new(
		dodgeDir.X * GameConfig.Player.DodgeSpeed,
		rootPart.AssemblyLinearVelocity.Y,
		dodgeDir.Z * GameConfig.Player.DodgeSpeed
	)

	local attachment = Instance.new("Attachment")
	attachment.Parent = rootPart

	local linearVel = Instance.new("LinearVelocity")
	linearVel.Attachment0 = attachment
	linearVel.MaxForce = 50000
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

-- Fungsi mengenali jenis senjata
local function getWeaponType(tool: Tool): string
	local attrType = tool:GetAttribute("WeaponType")
	if typeof(attrType) == "string" then
		return attrType
	end
	local toolNameLower = string.lower(tool.Name)
	if string.find(toolNameLower, "pipa") or string.find(toolNameLower, "ironpipe") then
		return "IronPipe"
	elseif string.find(toolNameLower, "pedang") or string.find(toolNameLower, "sword") then
		return "Sword"
	elseif string.find(toolNameLower, "pistol") then
		return "Pistol"
	end
	return "Unarmed"
end

-- ================= 3. HANDLER COMBAT (MELEE & PISTOL) =================
CombatEvent.OnServerEvent:Connect(function(player: Player, aimOriginArg: unknown, aimDirArg: unknown)
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

	if isRanged and equippedTool then
		-- ================= KASUS PISTOL: TEMBAKAN JARAK JAUH =================
		local maxAmmo = GameConfig.Weapons.Pistol.MaxAmmo
		local currentAmmo = (equippedTool:GetAttribute("Ammo") :: number?) or maxAmmo
		
		if currentAmmo <= 0 then
			print("[COMBAT] Peluru Pistol sudah habis (0/10)!")
			return
		end
		
		currentAmmo -= 1
		equippedTool:SetAttribute("Ammo", currentAmmo)
		equippedTool.Name = string.format("Pistol (%d/%d)", currentAmmo, maxAmmo)
		equippedTool.ToolTip = string.format("Peluru: %d/%d", currentAmmo, maxAmmo)
		
		-- Hitung titik awal dan arah bidikan (ke posisi kursor mouse pemain)
		local startPos = rootPart.Position + Vector3.new(0, 1.5, 0)
		local rayDir = rootPart.CFrame.LookVector * 50
		
		if typeof(aimOriginArg) == "Vector3" and typeof(aimDirArg) == "Vector3" then
			startPos = aimOriginArg
			rayDir = aimDirArg.Unit * 50
		elseif typeof(aimOriginArg) == "CFrame" then
			startPos = aimOriginArg.Position
			rayDir = aimOriginArg.LookVector * 50
		end

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {character}

		local result = workspace:Raycast(startPos, rayDir, raycastParams)
		local endPos = if result then result.Position else (startPos + rayDir)
		
		-- Tampilkan garis peluru kuning dari tangan karakter ke titik tembak
		createBulletTracer(rootPart.Position + Vector3.new(0, 1, 0), endPos)

		if result and result.Instance then
			local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
			if hitModel then
				local targetHumanoid = hitModel:FindFirstChildOfClass("Humanoid")
				if targetHumanoid and targetHumanoid.Health > 0 and not Players:GetPlayerFromCharacter(hitModel) then
					targetHumanoid:TakeDamage(damage)
					showDamageIndicator(hitModel, damage)
					print(string.format("[PISTOL] Mengenai %s (-%d HP)!", hitModel.Name, damage))
				end
			end
		end

	else
		-- ================= KASUS MELEE (Tangan Kosong / Pipa Besi / Pedang) =================
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = {character}

		local hitboxCFrame = rootPart.CFrame * CFrame.new(0, 0, -(GameConfig.Player.AttackRange / 2))
		local hitboxSize = Vector3.new(5, 5.5, GameConfig.Player.AttackRange)

		local partsInBox = workspace:GetPartBoundsInBox(hitboxCFrame, hitboxSize, overlapParams)
		local hitHumanoids: {[Humanoid]: boolean} = {}
		local hitAnyTarget = false

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
						print(string.format("[MELEE] Memukul %s dengan %s (-%d HP)!", model.Name, displayLabel, damage))
					end
				end
			end
		end

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