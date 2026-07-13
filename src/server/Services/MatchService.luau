--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Wind = require(ReplicatedStorage.Shared.Simulation.Wind)

local CharacterService = require(script.Parent.CharacterService)
local NetworkService = require(script.Parent.NetworkService)

type Remotes = NetworkService.Remotes

type MatchPhase =
	"WaitingForPlayers"
	| "Countdown"
	| "TurnStart"
	| "Aiming"
	| "ProjectileResolving"
	| "EnvironmentalResolution"
	| "TurnEnd"

local MATCH_SEED = 2_026_071_3

local MatchService = {}

local remotes: Remotes? = nil
local phase: MatchPhase = "WaitingForPlayers"
local activePlayer: Player? = nil
local deadline = 0
local roundNumber = 0
local lastActorUserId = 0
local currentWind = 0
local transitionToken = 0
local started = false

local function alivePlayers(): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid and humanoid.Health > 0 then
			table.insert(result, player)
		end
	end
	table.sort(result, function(left, right)
		return left.UserId < right.UserId
	end)
	return result
end

local function statePayload()
	return {
		phase = phase,
		activeUserId = if activePlayer then activePlayer.UserId else 0,
		deadline = deadline,
		roundNumber = roundNumber,
		wind = currentWind,
		serverTime = Workspace:GetServerTimeNow(),
	}
end

local function broadcastState(target: Player?)
	local currentRemotes = remotes
	if not currentRemotes then
		return
	end

	if target then
		currentRemotes.matchState:FireClient(target, statePayload())
	else
		currentRemotes.matchState:FireAllClients(statePayload())
	end
end

local function isCurrentTransition(token: number, expectedPhase: MatchPhase): boolean
	return token == transitionToken and phase == expectedPhase
end

local function enterWaitingState()
	transitionToken += 1
	phase = "WaitingForPlayers"
	activePlayer = nil
	deadline = 0
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)
end

local function beginNextTurn()
	local candidates = alivePlayers()
	if #candidates == 0 then
		enterWaitingState()
		return
	end

	local selectedIndex = 1
	for index, candidate in candidates do
		if candidate.UserId > lastActorUserId then
			selectedIndex = index
			break
		end
	end
	local selectedPlayer = candidates[selectedIndex]
	local wrappedRoster = lastActorUserId ~= 0 and selectedPlayer.UserId <= lastActorUserId
	if roundNumber == 0 or wrappedRoster then
		roundNumber += 1
		currentWind = Wind.forRound(MATCH_SEED, roundNumber - 1)
	end

	transitionToken += 1
	local token = transitionToken
	activePlayer = selectedPlayer
	lastActorUserId = selectedPlayer.UserId
	phase = "TurnStart"
	deadline = Workspace:GetServerTimeNow() + GameConfig.turnDurationSeconds
	CharacterService.setActivePlayer(activePlayer)
	broadcastState(nil)

	task.delay(0.65, function()
		if token ~= transitionToken or not activePlayer then
			return
		end
		phase = "Aiming"
		broadcastState(nil)
	end)
end

local function scheduleTurnIfNeeded()
	if activePlayer or phase ~= "WaitingForPlayers" or #alivePlayers() == 0 then
		return
	end

	transitionToken += 1
	local token = transitionToken
	phase = "Countdown"
	deadline = Workspace:GetServerTimeNow() + 1.5
	broadcastState(nil)
	task.delay(1.5, function()
		if token == transitionToken and not activePlayer then
			beginNextTurn()
		end
	end)
end

function MatchService.start(networkRemotes: Remotes)
	assert(not started, "MatchService may only be started once")
	started = true
	remotes = networkRemotes

	local function observePlayer(player: Player)
		local function onCharacterReady(character: Model)
			task.spawn(function()
				character:WaitForChild("Humanoid", 10)
				task.delay(0.1, scheduleTurnIfNeeded)
			end)
		end

		player.CharacterAdded:Connect(function(character)
			onCharacterReady(character)
		end)
		if player.Character then
			onCharacterReady(player.Character)
		end
		task.delay(1, function()
			broadcastState(player)
			scheduleTurnIfNeeded()
		end)
	end

	for _, player in Players:GetPlayers() do
		observePlayer(player)
	end
	Players.PlayerAdded:Connect(observePlayer)

	Players.PlayerRemoving:Connect(function(player)
		if activePlayer == player then
			activePlayer = nil
			CharacterService.setActivePlayer(nil)
			if phase == "ProjectileResolving" or phase == "EnvironmentalResolution" then
				-- The disconnected player's authoritative shot must settle before another
				-- turn starts, otherwise a late impact could resolve inside the next turn.
				broadcastState(nil)
			else
				transitionToken += 1
				task.defer(beginNextTurn)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.2)
			if phase == "WaitingForPlayers" and #alivePlayers() > 0 then
				scheduleTurnIfNeeded()
			elseif
				activePlayer
				and phase == "Aiming"
				and Workspace:GetServerTimeNow() >= deadline
			then
				phase = "TurnEnd"
				activePlayer = nil
				CharacterService.setActivePlayer(nil)
				transitionToken += 1
				local token = transitionToken
				broadcastState(nil)
				task.delay(0.75, function()
					if isCurrentTransition(token, "TurnEnd") then
						beginNextTurn()
					end
				end)
			end
		end
	end)

	task.delay(1, scheduleTurnIfNeeded)
end

function MatchService.canFire(player: Player): (boolean, string?)
	if phase ~= "Aiming" then
		return false, "match_not_aiming"
	end
	if activePlayer ~= player then
		return false, "not_your_turn"
	end
	if Workspace:GetServerTimeNow() >= deadline then
		return false, "turn_expired"
	end

	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return false, "player_not_alive"
	end

	return true, nil
end

function MatchService.beginProjectile(player: Player): (boolean, string?)
	local allowed, reason = MatchService.canFire(player)
	if not allowed then
		return false, reason
	end

	transitionToken += 1
	phase = "ProjectileResolving"
	deadline = 0
	CharacterService.setActivePlayer(nil)
	broadcastState(nil)
	return true, nil
end

function MatchService.finishProjectile()
	if phase ~= "ProjectileResolving" then
		return
	end

	transitionToken += 1
	local token = transitionToken
	phase = "EnvironmentalResolution"
	broadcastState(nil)
	task.delay(0.8, function()
		if not isCurrentTransition(token, "EnvironmentalResolution") then
			return
		end
		phase = "TurnEnd"
		activePlayer = nil
		broadcastState(nil)
		task.delay(0.55, function()
			if isCurrentTransition(token, "TurnEnd") then
				beginNextTurn()
			end
		end)
	end)
end

function MatchService.getWind(): number
	return currentWind
end

function MatchService.getRoundNumber(): number
	return roundNumber
end

return MatchService
