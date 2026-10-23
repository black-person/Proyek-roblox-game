--!strict
-- Lokasi: ReplicatedStorage/Modules/GameConfig

local GameConfig = {}

GameConfig.Player = {
	MaxHP = 100,
	WalkSpeed = 16,
	SprintSpeed = 24,

	MaxStamina = 100,
	StaminaDrainRate = 20,
	StaminaRegenRate = 15,
	StaminaRegenDelay = 1.0,

	DodgeCooldown = 3.0,
	DodgeDuration = 0.25,
	DodgeSpeed = 48,
	DodgeStaminaCost = 25,

	UnarmedDamage = 10,
	VIPAttackDamage = 45,
	AttackCooldown = 0.6,
	AttackRange = 6.5,
}

GameConfig.Weapons = {
	IronPipe = {
		Name = "Iron Pipe",
		Damage = 30,
		MaxDurability = 25, 
		LootChance = 0.40,
	},
	Sword = {
		Name = "Sword",
		Damage = 60,
		MaxDurability = 40,
		LootChance = 0.05,
	},
	Pistol = {
		Name = "Pistol",
		Damage = 60,
		MaxAmmo = 10,
		LootChance = 0.05,
	}
}

GameConfig.Zombie = {
	MaxHP = 100,
	WalkSpeed = 12,
	AttackDamage = 10,
	AttackCooldown = 1.5,
	AttackRange = 4.5,
	AggroRadius = 30,
	DeaggroRadius = 45,
	MaxActiveZombies = 20,
	PathUpdateInterval = 0.4,
	MedkitDropChance = 0.30,
	MedkitHealAmount = 25, 
}

GameConfig.GamePass = {
	VIPCardId = 0,
}

return table.freeze(GameConfig)