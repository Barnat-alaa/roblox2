--!strict

-- The development bot is a server-owned match participant, never a synthetic
-- Player. Its reserved identity stays outside live Roblox and Studio test-user
-- ranges while remaining exactly representable as a Luau number.

return table.freeze({
	userId = -1_000_000_000,
	modelName = "BotCritter",
	displayName = "Rival Critter",
	difficulty = "Normal",
	thinkDelaySeconds = 0.65,
	weaponIds = table.freeze({
		"acorn_cannon",
		"mole_drill",
	}),
})
