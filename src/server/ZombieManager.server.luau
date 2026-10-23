--!strict
-- Lokasi: src/server/ZombieManager.server.luau

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local SharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:FindFirstChild("shared") or ReplicatedStorage:FindFirstChild("Modules")
local GameConfigModule = ((SharedFolder and SharedFolder:FindFirstChild("GameConfig"))
	or ReplicatedStorage:FindFirstChild("GameConfig")) :: ModuleScript?

if not GameConfigModule or not GameConfigModule:IsA("ModuleScript") then
	error("GameConfig ModuleScript not found in ReplicatedStorage")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UseMedkitEvent = Remotes:WaitForChild("UseMedkitEvent") :: RemoteEvent

local zombieTemplate = ServerStorage:WaitForChild("ZombieTemplate") :: Model
local zombiesFolder = workspace:FindFirstChild("Zombies") or Instance.new("Folder")
zombiesFolder.Name = "Zombies"
zombiesFolder.Parent = workspace

type ZombieData = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	State: "Idle" | "Chasing",
	FlankAngle: number,
	SpeedVariation: number,
	LastAttackTime: number,
	LastPathTime: number,
	IsComputingPath: boolean,
	IsDead: boolean,
}

local activeZombies: {[Model]: ZombieData} = {}
local activeZombieCount = 0
local guaranteedDropCount = 2 -- 2 zombie pertama dijamin 100% drop medkit untuk testing

-- Inisialisasi atribut jumlah Medkit pada Player
local function initPlayerMedkits(player: Player)
	if player:GetAttribute("MedkitCount") == nil then
		player:SetAttribute("MedkitCount", 0)
	end
end

Players.PlayerAdded:Connect(initPlayerMedkits)
for _, p in Players:GetPlayers() do
	initPlayerMedkits(p)
end

-- Handler saat pemain menekan tombol Pakai Medkit (Tombol H atau Klik UI Kanan Bawah)
UseMedkitEvent.OnServerEvent:Connect(function(player: Player)
	local count = (player:GetAttribute("MedkitCount") :: number) or 0
	if count <= 0 then return end
	
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.Health >= hum.MaxHealth then
		return
	end
	
	player:SetAttribute("MedkitCount", count - 1)
	hum.Health = math.min(hum.MaxHealth, hum.Health + GameConfig.Zombie.MedkitHealAmount)
	print(string.format("[MEDKIT] %s menggunakan Medkit! HP sekarang: %d/%d (Sisa Medkit: %d)", player.Name, math.ceil(hum.Health), hum.MaxHealth, count - 1))
end)

-- Fungsi membuat Drop Medkit Kecil (+25 HP, peluang 15% sesuai GDD)[cite: 15]
local function trySpawnMedkitDrop(position: Vector3)
	local roll = math.random()
	if guaranteedDropCount <= 0 and roll > GameConfig.Zombie.MedkitDropChance then
		print(string.format("[MEDKIT] Zombie mati, tidak drop medkit (Roll: %.2f > %.2f)", roll, GameConfig.Zombie.MedkitDropChance))
		return
	end
	if guaranteedDropCount > 0 then
		guaranteedDropCount -= 1
	end
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {zombiesFolder}
	local rayResult = workspace:Raycast(position + Vector3.new(0, 3, 0), Vector3.new(0, -15, 0), rayParams)
	local groundY = if rayResult then rayResult.Position.Y else (position.Y - 2.5)
	
	local medkit = Instance.new("Part")
	medkit.Name = "SmallMedkit"
	medkit.Size = Vector3.new(2.2, 1.2, 1.6)
	medkit.Position = Vector3.new(position.X, groundY + 1.5, position.Z)
	medkit.Color = Color3.fromHex("#5FD1B3") -- Biru-Hijau Penawar[cite: 15]
	medkit.Material = Enum.Material.Neon
	medkit.Anchored = true
	medkit.CanCollide = false
	medkit.Parent = workspace
	
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.fromHex("#5FD1B3")
	highlight.FillTransparency = 0.2
	highlight.OutlineColor = Color3.fromHex("#D9A441") -- Amber Interaksi[cite: 15]
	highlight.OutlineTransparency = 0
	highlight.Parent = medkit
	
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(140, 40)
	billboard.StudsOffset = Vector3.new(0, 2.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = medkit
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromHex("#5FD1B3")
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Text = "MEDKIT (+25 HP)"
	label.Parent = billboard
	
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ambil Medkit (+25 HP)"
	prompt.ObjectText = "Medkit Kecil"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = medkit
	
	local collected = false
	local spinConn: RBXScriptConnection
	
	spinConn = RunService.Heartbeat:Connect(function(dt: number)
		if not medkit or not medkit.Parent then
			spinConn:Disconnect()
			return
		end
		medkit.CFrame = medkit.CFrame * CFrame.Angles(0, math.rad(75 * dt), 0)
	end)
	
	prompt.Triggered:Connect(function(player: Player)
		if collected then return end
		collected = true
		
		local currentCount = (player:GetAttribute("MedkitCount") :: number) or 0
		player:SetAttribute("MedkitCount", currentCount + 1)
		print(string.format("[MEDKIT] %s mengambil Medkit Kecil! Total di tas: %d", player.Name, currentCount + 1))
		
		spinConn:Disconnect()
		medkit:Destroy()
	end)
	
	Debris:AddItem(medkit, 60)
end

-- Fungsi Spawn Zombie
local function spawnZombie(spawnPos: Vector3, index: number): Model?
	if activeZombieCount >= GameConfig.Zombie.MaxActiveZombies then
		return nil
	end
	
	local clone = zombieTemplate:Clone()
	clone.Name = "ZombieMahasiswa"
	
	local humanoid = clone:WaitForChild("Humanoid") :: Humanoid
	local rootPart = clone:WaitForChild("HumanoidRootPart") :: BasePart
	
	for _, desc in clone:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			if desc.Name ~= "HumanoidRootPart" then
				desc.Color = Color3.fromHex("#6F8F72") -- Hijau Zombie[cite: 15]
			end
		end
	end
	
	local speedVar = (math.random() - 0.5) * 2.4
	humanoid.MaxHealth = GameConfig.Zombie.MaxHP
	humanoid.Health = GameConfig.Zombie.MaxHP
	humanoid.WalkSpeed = GameConfig.Zombie.WalkSpeed + speedVar
	
	clone:PivotTo(CFrame.new(spawnPos))
	clone.Parent = zombiesFolder
	
	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)
	
	local flankAngle = math.rad(((index % 5) - 2) * 32 + math.random(-10, 10))
	
	local data: ZombieData = {
		Model = clone,
		Humanoid = humanoid,
		RootPart = rootPart,
		State = "Idle",
		FlankAngle = flankAngle,
		SpeedVariation = speedVar,
		LastAttackTime = 0,
		LastPathTime = 0,
		IsComputingPath = false,
		IsDead = false,
	}
	
	activeZombies[clone] = data
	activeZombieCount += 1
	
	local function handleZombieDeath()
		if data.IsDead then return end
		data.IsDead = true
		
		local deathPos = rootPart.Position
		if activeZombies[clone] then
			activeZombies[clone] = nil
			activeZombieCount = math.max(0, activeZombieCount - 1)
		end
		
		trySpawnMedkitDrop(deathPos)
		
		task.delay(2.5, function()
			if clone and clone.Parent then
				clone:Destroy()
			end
		end)
	end
	
	humanoid.Died:Connect(handleZombieDeath)
	humanoid.HealthChanged:Connect(function(newHealth: number)
		if newHealth <= 0 then
			handleZombieDeath()
		end
	end)
	
	return clone
end

local function getNearestPlayer(fromPos: Vector3): (Model?, BasePart?, Humanoid?, number)
	local nearestChar: Model? = nil
	local nearestRoot: BasePart? = nil
	local nearestHum: Humanoid? = nil
	local minDistance = math.huge
	
	for _, player in Players:GetPlayers() do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and root and hum.Health > 0 then
				local dist = (root.Position - fromPos).Magnitude
				if dist < minDistance then
					minDistance = dist
					nearestChar = char
					nearestRoot = root
					nearestHum = hum
				end
			end
		end
	end
	
	return nearestChar, nearestRoot, nearestHum, minDistance
end

local function getSeparationOffset(zData: ZombieData): Vector3
	local separation = Vector3.zero
	local minSeparationDist = 4.5
	
	for otherModel, otherData in activeZombies do
		if otherModel ~= zData.Model and not otherData.IsDead then
			local diff = zData.RootPart.Position - otherData.RootPart.Position
			local flatDiff = Vector3.new(diff.X, 0, diff.Z)
			local dist = flatDiff.Magnitude
			if dist > 0.05 and dist < minSeparationDist then
				local pushStrength = (minSeparationDist - dist) / minSeparationDist
				separation += flatDiff.Unit * (pushStrength * 5.5)
			elseif dist <= 0.05 then
				local angle = math.random() * math.pi * 2
				separation += Vector3.new(math.cos(angle), 0, math.sin(angle)) * 4
			end
		end
	end
	
	return separation
end

local function moveZombieSmart(zData: ZombieData, targetRoot: BasePart, distToPlayer: number)
	local separationVec = getSeparationOffset(zData)
	
	local toZombie = zData.RootPart.Position - targetRoot.Position
	local flatToZombie = Vector3.new(toZombie.X, 0, toZombie.Z)
	local baseDir = if flatToZombie.Magnitude > 0.1 then flatToZombie.Unit else Vector3.new(0, 0, 1)
	
	local surroundRadius = if distToPlayer > 5 then 3.2 else 2.2
	local rotatedCFrame = CFrame.Angles(0, zData.FlankAngle, 0)
	local surroundOffset = (rotatedCFrame:VectorToWorldSpace(baseDir)) * surroundRadius
	
	local finalGoal = targetRoot.Position + surroundOffset + separationVec
	
	if distToPlayer < 18 then
		zData.Humanoid:MoveTo(finalGoal)
		return
	end
	
	if zData.IsComputingPath then return end
	zData.IsComputingPath = true
	
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = 2.2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})
		
		local success = pcall(function()
			path:ComputeAsync(zData.RootPart.Position, finalGoal)
		end)
		
		if not zData.IsDead then
			if success and path.Status == Enum.PathStatus.Success then
				local waypoints = path:GetWaypoints()
				local nextWaypoint = waypoints[2] or waypoints[1]
				if nextWaypoint then
					if nextWaypoint.Action == Enum.PathWaypointAction.Jump then
						zData.Humanoid.Jump = true
					end
					zData.Humanoid:MoveTo(nextWaypoint.Position + separationVec)
				end
			else
				zData.Humanoid:MoveTo(finalGoal)
			end
		end
		
		zData.IsComputingPath = false
	end)
end

-- Loop Update AI Zombie
task.spawn(function()
	while true do
		task.wait(0.12)
		local now = os.clock()
		
		for _, zData in activeZombies do
			if zData.IsDead or zData.Humanoid.Health <= 0 then continue end
			
			local targetChar, targetRoot, targetHum, dist = getNearestPlayer(zData.RootPart.Position)
			
			if not targetChar or not targetRoot or not targetHum then
				if zData.State ~= "Idle" then
					zData.State = "Idle"
					zData.Humanoid:MoveTo(zData.RootPart.Position)
				end
				continue
			end
			
			if zData.State == "Idle" then
				if dist <= GameConfig.Zombie.AggroRadius then
					zData.State = "Chasing"
				end
			elseif zData.State == "Chasing" then
				if dist > GameConfig.Zombie.DeaggroRadius then
					zData.State = "Idle"
					zData.Humanoid:MoveTo(zData.RootPart.Position)
				end
			end
			
			if zData.State == "Chasing" then
				if dist <= GameConfig.Zombie.AttackRange then
					if (now - zData.LastAttackTime) >= GameConfig.Zombie.AttackCooldown then
						zData.LastAttackTime = now
						
						if not targetChar:GetAttribute("IsDodging") then
							targetHum:TakeDamage(GameConfig.Zombie.AttackDamage)
							print(string.format("[ZOMBIE] Menyerang pemain! HP Pemain tersisa: %d", targetHum.Health))
						else
							print("[ZOMBIE] Serangan berhasil di-dodge oleh pemain!")
						end
					end
				end
				
				if (now - zData.LastPathTime) >= 0.12 then
					zData.LastPathTime = now
					moveZombieSmart(zData, targetRoot, dist)
				end
			end
		end
	end
end)

-- Spawn 3 Zombie Uji Coba saat game dimulai
task.delay(2, function()
	spawnZombie(Vector3.new(-126, -225.5, 602), 1)
	spawnZombie(Vector3.new(-100, -225.5, 602), 2)
	spawnZombie(Vector3.new(-146, -225.5, 601), 3)
end)