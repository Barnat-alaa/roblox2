--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaService = require(script.Parent.Services.ArenaService)
local BotService = require(script.Parent.Services.BotService)
local CharacterService = require(script.Parent.Services.CharacterService)
local CosmeticService = require(script.Parent.Services.CosmeticService)
local CustomizationService = require(script.Parent.Services.CustomizationService)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local LobbyService = require(script.Parent.Services.LobbyService)
local MatchService = require(script.Parent.Services.MatchService)
local MovementService = require(script.Parent.Services.MovementService)
local NetworkService = require(script.Parent.Services.NetworkService)
local ProjectileService = require(script.Parent.Services.ProjectileService)
local TelemetryService = require(script.Parent.Services.TelemetryService)
local TerrainService = require(script.Parent.Services.TerrainService)

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local catalogueValid, catalogueReason = Weapons.validateCatalogue(Weapons.All)
assert(catalogueValid, catalogueReason or "Weapon catalogue validation failed")

local arena = ArenaService.createGreybox()
local remotes = NetworkService.create()
TelemetryService.start()
DataService.start()
EconomyService.start(remotes)
TerrainService.start(remotes, arena)
CharacterService.start()
MatchService.start(remotes, arena)
LobbyService.start(remotes)
MovementService.start(remotes)
ProjectileService.start(remotes)
BotService.start()
CustomizationService.start(remotes)
CosmeticService.start()

workspace:SetAttribute("CritterClashBooted", true)
workspace:SetAttribute("CritterClashBuild", "0.7.0-dev")

print("[CritterClash] Phase 3/4 lobby, identity, and comfort slice started")
