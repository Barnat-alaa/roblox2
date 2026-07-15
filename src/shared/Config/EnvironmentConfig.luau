--!strict

-- Development is deliberately the only active persistence environment. Published
-- Staging and Production places must receive separate reviewed configurations.
return table.freeze({
	name = "Development",
	dataStoreName = "DEV_CritterClash_Profile_v1",
	profileKeyPrefix = "Player_",
	schemaVersion = 2,
	leaseDurationSeconds = 120,
	autosaveIntervalSeconds = 45,
	autosaveJitterSeconds = 10,
	retryAttempts = 5,
	retryBaseDelaySeconds = 0.5,
	retryMaxDelaySeconds = 8,
	shutdownTimeoutSeconds = 25,
	allowUnpublishedStudioMemory = true,
})
