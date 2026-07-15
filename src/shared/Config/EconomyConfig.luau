--!strict

local MATCH_REWARDS = table.freeze({
	completionCoins = 40,
	completionXp = 100,
	winBonusCoins = 20,
	winBonusXp = 50,
	drawBonusCoins = 10,
	drawBonusXp = 25,
	botMultiplier = 0.85,
	botMultiplierNumerator = 85,
	botMultiplierDenominator = 100,
})

return table.freeze({
	version = 1,
	maxCoins = 2_000_000_000,
	maxXp = 2_000_000_000,
	maxMatchStat = 2_000_000_000,
	levelCap = 100,
	levelBaseXp = 150,
	levelXpStep = 50,
	maxProcessedRewards = 64,
	matchRewards = MATCH_REWARDS,
})
