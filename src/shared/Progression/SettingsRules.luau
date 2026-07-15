--!strict

local SettingsConfig = require(script.Parent.Parent.Config.SettingsConfig)

local SettingsRules = {}

export type Settings = {
	musicVolume: number,
	sfxVolume: number,
	cameraShake: number,
	reducedEffects: boolean,
	uiScale: number,
}

export type SettingsPatch = {
	musicVolume: number?,
	sfxVolume: number?,
	cameraShake: number?,
	reducedEffects: boolean?,
	uiScale: number?,
}

local SETTINGS_FIELDS = table.freeze({
	musicVolume = true,
	sfxVolume = true,
	cameraShake = true,
	reducedEffects = true,
	uiScale = true,
})

local function isFinite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isNumberInRange(value: unknown, minimum: number, maximum: number): boolean
	return typeof(value) == "number"
		and isFinite(value :: number)
		and (value :: number) >= minimum
		and (value :: number) <= maximum
end

local function onlyHasFields(value: { [any]: any }): boolean
	for field in value do
		if typeof(field) ~= "string" or not SETTINGS_FIELDS[field :: string] then
			return false
		end
	end
	return true
end

function SettingsRules.createDefault(): Settings
	return {
		musicVolume = SettingsConfig.defaultMusicVolume,
		sfxVolume = SettingsConfig.defaultSfxVolume,
		cameraShake = SettingsConfig.defaultCameraShake,
		reducedEffects = SettingsConfig.defaultReducedEffects,
		uiScale = SettingsConfig.defaultUiScale,
	}
end

function SettingsRules.clone(settings: Settings): Settings
	return {
		musicVolume = settings.musicVolume,
		sfxVolume = settings.sfxVolume,
		cameraShake = settings.cameraShake,
		reducedEffects = settings.reducedEffects,
		uiScale = settings.uiScale,
	}
end

function SettingsRules.validate(value: unknown): (boolean, string?)
	if typeof(value) ~= "table" then
		return false, "invalid_settings"
	end
	local settings = value :: { [any]: any }
	if not onlyHasFields(settings) then
		return false, "invalid_settings_fields"
	end
	if
		not isNumberInRange(
			settings.musicVolume,
			SettingsConfig.minimumVolume,
			SettingsConfig.maximumVolume
		)
	then
		return false, "invalid_music_volume"
	end
	if
		not isNumberInRange(
			settings.sfxVolume,
			SettingsConfig.minimumVolume,
			SettingsConfig.maximumVolume
		)
	then
		return false, "invalid_sfx_volume"
	end
	if
		not isNumberInRange(
			settings.cameraShake,
			SettingsConfig.minimumCameraShake,
			SettingsConfig.maximumCameraShake
		)
	then
		return false, "invalid_camera_shake"
	end
	if typeof(settings.reducedEffects) ~= "boolean" then
		return false, "invalid_reduced_effects"
	end
	if
		not isNumberInRange(
			settings.uiScale,
			SettingsConfig.minimumUiScale,
			SettingsConfig.maximumUiScale
		)
	then
		return false, "invalid_ui_scale"
	end
	return true, nil
end

function SettingsRules.applyPatch(settings: Settings, patchValue: unknown): (Settings?, string?)
	local currentValid, currentReason = SettingsRules.validate(settings)
	if not currentValid then
		return nil, currentReason
	end
	if typeof(patchValue) ~= "table" then
		return nil, "invalid_settings_patch"
	end
	local patch = patchValue :: { [any]: any }
	if not onlyHasFields(patch) then
		return nil, "invalid_settings_patch_fields"
	end

	local updated = SettingsRules.clone(settings)
	if patch.musicVolume ~= nil then
		updated.musicVolume = patch.musicVolume
	end
	if patch.sfxVolume ~= nil then
		updated.sfxVolume = patch.sfxVolume
	end
	if patch.cameraShake ~= nil then
		updated.cameraShake = patch.cameraShake
	end
	if patch.reducedEffects ~= nil then
		updated.reducedEffects = patch.reducedEffects
	end
	if patch.uiScale ~= nil then
		updated.uiScale = patch.uiScale
	end

	local updatedValid, updatedReason = SettingsRules.validate(updated)
	if not updatedValid then
		return nil, updatedReason
	end
	return updated, nil
end

return table.freeze(SettingsRules)
