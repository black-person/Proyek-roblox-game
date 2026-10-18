--!strict
-- Lokasi: ServerScriptService/LootSystem

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:FindFirstChild("shared")
local GameConfigModule = ((SharedFolder and SharedFolder:FindFirstChild("GameConfig"))
    or ReplicatedStorage:FindFirstChild("GameConfig")) :: ModuleScript?

if not GameConfigModule then
    error("GameConfig ModuleScript not found in ReplicatedStorage.Shared or ReplicatedStorage")
end

if not GameConfigModule:IsA("ModuleScript") then
    error("GameConfig ModuleScript not found in ReplicatedStorage.Shared or ReplicatedStorage")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule :: ModuleScript)
local _Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Inisialisasi atribut senjata pemain
local function initPlayerWeapon(player: Player)
	if player:GetAttribute("EquippedWeapon") == nil then
		player:SetAttribute("EquippedWeapon", "Unarmed")
		player:SetAttribute("WeaponDamage", GameConfig.Player.UnarmedDamage)
		player:SetAttribute("WeaponDurability", 0)
	end
end

Players.PlayerAdded:Connect(initPlayerWeapon)
for _, p in Players:GetPlayers() do
	initPlayerWeapon(p)
end

-- Fungsi membuat Peti Loot di Workspace
local function createLootChest(position: Vector3)
	local chest = Instance.new("Part")
	chest.Name = "LootChest"
	chest.Size = Vector3.new(3, 2, 2)
	chest.Position = position
	chest.Color = Color3.fromHex("#D9A441") -- Warna Amber Interaksi
	chest.Material = Enum.Material.Wood
	chest.Anchored = true
	chest.Parent = workspace

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buka Peti"
	prompt.ObjectText = "Peti Persediaan"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = chest

	local opened = false
	prompt.Triggered:Connect(function(player: Player)
		if opened then return end
		opened = true
		prompt.Enabled = false
		chest.Color = Color3.fromHex("#6B7478") -- Berubah jadi beton pudar (sudah dibuka)

		-- Sistem Drop: 30% Pipa Besi, 70% Medkit atau Kosong
		local roll = math.random()
		if roll <= GameConfig.Weapon.IronPipe.LootChance then
			-- Berikan Pipa Besi
			player:SetAttribute("EquippedWeapon", "IronPipe")
			player:SetAttribute("WeaponDamage", GameConfig.Weapon.IronPipe.Damage)
			player:SetAttribute("WeaponDurability", GameConfig.Weapon.IronPipe.MaxDurability)
			print(string.format("[LOOT] %s mendapatkan Pipa Besi! (Damage: %d, Durability: %d)", player.Name, GameConfig.Weapon.IronPipe.Damage, GameConfig.Weapon.IronPipe.MaxDurability))
		else
			-- Berikan Medkit sebagai gantinya
			local currentMedkits = (player:GetAttribute("MedkitCount") :: number) or 0
			player:SetAttribute("MedkitCount", currentMedkits + 1)
			print(string.format("[LOOT] %s membuka peti dan menemukan Medkit Kecil!", player.Name))
		end
	end)
end

-- Spawn 1 peti uji coba di dekat titik spawn awal
task.delay(1, function()
	createLootChest(Vector3.new(8, 2, -10))
end)