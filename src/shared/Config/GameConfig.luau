--!strict

return table.freeze({
	combatPlaneZ = 0,
	arenaHalfWidth = 90,
	deathHeight = -35,
	turnDurationSeconds = 20,
	movementAllowanceStuds = 22,
	maxHorizontalSpeed = 20,
	maxJumpFrequencySeconds = 0.65,
	projectileStepSeconds = 1 / 60,
	projectileMaxStepsPerHeartbeat = 8,
	projectileWorldGravity = 120,
	minimumAimDegrees = 5,
	maximumAimDegrees = 175,
	minimumPower = 0.1,
	maximumPower = 1,
	remoteRateLimitSeconds = 0.12,
	developmentDataStorePrefix = "DEV_CritterClash_Profile_v1",
	stagingDataStorePrefix = "STAGING_CritterClash_Profile_v1",
	productionDataStorePrefix = "PROD_CritterClash_Profile_v1",
})
