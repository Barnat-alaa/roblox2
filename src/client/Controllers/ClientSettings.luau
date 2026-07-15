--!strict

local Players = game:GetService("Players")

export type Values = {
	reducedEffects: boolean,
	cameraShake: number,
	uiScale: number,
}

local ClientSettings = {}

ClientSettings.DEFAULTS = table.freeze({
	reducedEffects = false,
	cameraShake = 0.65,
	uiScale = 1,
})

ClientSettings.MIN_UI_SCALE = 0.8
ClientSettings.MAX_UI_SCALE = 1.2

local function finiteNumber(value: any): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

function ClientSettings.copy(values: Values): Values
	return {
		reducedEffects = values.reducedEffects,
		cameraShake = values.cameraShake,
		uiScale = values.uiScale,
	}
end

function ClientSettings.sanitize(values: any): Values
	local source = if type(values) == "table" then values else {}
	local rawReducedEffects = source.reducedEffects
	local rawCameraShake = finiteNumber(source.cameraShake)
	local rawUIScale = finiteNumber(source.uiScale)
	return {
		reducedEffects = if type(rawReducedEffects) == "boolean"
			then rawReducedEffects
			else ClientSettings.DEFAULTS.reducedEffects,
		cameraShake = math.clamp(rawCameraShake or ClientSettings.DEFAULTS.cameraShake, 0, 1),
		uiScale = math.clamp(
			rawUIScale or ClientSettings.DEFAULTS.uiScale,
			ClientSettings.MIN_UI_SCALE,
			ClientSettings.MAX_UI_SCALE
		),
	}
end

function ClientSettings.fromPlayer(player: Player?): Values
	local target = player or Players.LocalPlayer
	return ClientSettings.sanitize({
		reducedEffects = target:GetAttribute("SettingReducedEffects"),
		cameraShake = target:GetAttribute("SettingCameraShake"),
		uiScale = target:GetAttribute("SettingUIScale"),
	})
end

function ClientSettings.publishLocal(player: Player?, values: Values)
	local target = player or Players.LocalPlayer
	local clean = ClientSettings.sanitize(values)
	target:SetAttribute("ClientReducedEffects", clean.reducedEffects)
	target:SetAttribute("ClientCameraShake", clean.cameraShake)
	target:SetAttribute("ClientUIScale", clean.uiScale)
end

function ClientSettings.readLocal(player: Player?): Values
	local target = player or Players.LocalPlayer
	local reducedEffects = target:GetAttribute("ClientReducedEffects")
	local cameraShake = target:GetAttribute("ClientCameraShake")
	local uiScale = target:GetAttribute("ClientUIScale")
	if
		type(reducedEffects) ~= "boolean"
		or finiteNumber(cameraShake) == nil
		or finiteNumber(uiScale) == nil
	then
		local replicated = ClientSettings.fromPlayer(target)
		ClientSettings.publishLocal(target, replicated)
		return replicated
	end
	return ClientSettings.sanitize({
		reducedEffects = reducedEffects,
		cameraShake = cameraShake,
		uiScale = uiScale,
	})
end

return ClientSettings
