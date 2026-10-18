--!strict
-- Lokasi: src/server/TestLoadout.server.luau

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local weaponsFolder = ServerStorage:WaitForChild("Weapons")

local SharedFolder = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage:FindFirstChild("shared") or ReplicatedStorage:FindFirstChild("Modules")
local GameConfigModule = ((SharedFolder and SharedFolder:FindFirstChild("GameConfig"))
	or ReplicatedStorage:FindFirstChild("GameConfig")) :: ModuleScript?

if not GameConfigModule or not GameConfigModule:IsA("ModuleScript") then
	error("GameConfig ModuleScript not found in ReplicatedStorage")
end

local dynamicRequire = require :: (ModuleScript) -> any
local GameConfig = dynamicRequire(GameConfigModule)

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function(_character: Model)
		task.wait(1.0)
		
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then return end
		
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
		print("[TEST LOADOUT] Semua senjata siap dengan Attribute WeaponType & Durability/Ammo!")
	end)
end)