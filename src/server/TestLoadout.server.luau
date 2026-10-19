--!strict
-- Lokasi: src/server/TestLoadout.server.luau

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = ReplicatedStorage:WaitForChild("Shared", 5) or ReplicatedStorage:WaitForChild("shared", 5) or ReplicatedStorage:FindFirstChild("Modules")
local GameConfigModule = ((SharedFolder and SharedFolder:WaitForChild("GameConfig", 5))
	or ReplicatedStorage:WaitForChild("GameConfig", 5)) :: ModuleScript?

if not GameConfigModule or not GameConfigModule:IsA("ModuleScript") then
	error("GameConfig ModuleScript not found in ReplicatedStorage")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule)

local function giveLoadout(player: Player)
	local weaponsFolder = ServerStorage:FindFirstChild("Weapons")
	if not weaponsFolder then
		warn("[TEST LOADOUT] Folder 'Weapons' belum ada di ServerStorage!")
		return
	end
	
	local backpack = player:WaitForChild("Backpack", 5)
	if not backpack then return end
	
	-- Bersihkan duplikat jika ada
	for _, weaponTool in weaponsFolder:GetChildren() do
		if weaponTool:IsA("Tool") then
			local cloneTool = weaponTool:Clone()
			local originalName = weaponTool.Name
			
			cloneTool:SetAttribute("WeaponType", originalName)
			
			if originalName == "IronPipe" then
				local maxDur = GameConfig.Weapons.IronPipe.MaxDurability
				cloneTool:SetAttribute("Durability", maxDur)
				cloneTool.Name = string.format("Pipa Besi (%d/%d)", maxDur, maxDur)
				cloneTool.ToolTip = string.format("Durability: %d/%d", maxDur, maxDur)
			elseif originalName == "Sword" then
				local maxDur = GameConfig.Weapons.Sword.MaxDurability
				cloneTool:SetAttribute("Durability", maxDur)
				cloneTool.Name = string.format("Pedang (%d/%d)", maxDur, maxDur)
				cloneTool.ToolTip = string.format("Durability: %d/%d", maxDur, maxDur)
			elseif originalName == "Pistol" then
				local maxAmmo = GameConfig.Weapons.Pistol.MaxAmmo
				cloneTool:SetAttribute("Ammo", maxAmmo)
				cloneTool.Name = string.format("Pistol (%d/%d)", maxAmmo, maxAmmo)
				cloneTool.ToolTip = string.format("Peluru: %d/%d", maxAmmo, maxAmmo)
			end
			
			cloneTool.Parent = backpack
		end
	end
	
	player:SetAttribute("MedkitCount", 3)
	print("[TEST LOADOUT] Senjata berhasil dimasukkan ke Backpack " .. player.Name)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(_character: Model)
		task.wait(0.5)
		giveLoadout(player)
	end)
	if player.Character then
		task.spawn(function()
			task.wait(0.5)
			giveLoadout(player)
		end)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	onPlayerAdded(p)
end