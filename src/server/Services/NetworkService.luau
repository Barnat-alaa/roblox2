--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Network.RemoteNames)

export type Remotes = {
	requestFire: RemoteEvent,
	requestMovement: RemoteEvent,
	selectWeapon: RemoteEvent,
	combatEvent: RemoteEvent,
	matchState: RemoteEvent,
}

local NetworkService = {}

local function getOrCreateRemote(folder: Folder, name: string): RemoteEvent
	local existing = folder:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s must be a RemoteEvent", name))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = folder
	return remote
end

function NetworkService.create(): Remotes
	local existingFolder = ReplicatedStorage:FindFirstChild(RemoteNames.folder)
	local folder: Folder

	if existingFolder then
		assert(existingFolder:IsA("Folder"), "CritterClashRemotes must be a Folder")
		folder = existingFolder
	else
		folder = Instance.new("Folder")
		folder.Name = RemoteNames.folder
		folder.Parent = ReplicatedStorage
	end

	return table.freeze({
		requestFire = getOrCreateRemote(folder, RemoteNames.requestFire),
		requestMovement = getOrCreateRemote(folder, RemoteNames.requestMovement),
		selectWeapon = getOrCreateRemote(folder, RemoteNames.selectWeapon),
		combatEvent = getOrCreateRemote(folder, RemoteNames.combatEvent),
		matchState = getOrCreateRemote(folder, RemoteNames.matchState),
	}) :: Remotes
end

return NetworkService
