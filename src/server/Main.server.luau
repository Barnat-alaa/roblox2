--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaService = require(script.Parent.Services.ArenaService)
local BotService = require(script.Parent.Services.BotService)
local CharacterService = require(script.Parent.Services.CharacterService)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local MatchService = require(script.Parent.Services.MatchService)
local MovementService = require(script.Parent.Services.MovementService)
local NetworkService = require(script.Parent.Services.NetworkService)
local ProjectileService = require(script.Parent.Services.ProjectileService)
local TerrainService = require(script.Parent.Services.TerrainService)

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local catalogueValid, catalogueReason = Weapons.validateCatalogue(Weapons.All)
assert(catalogueValid, catalogueReason or "Weapon catalogue validation failed")

local arena = ArenaService.createGreybox()
local remotes = NetworkService.create()
DataService.start()
EconomyService.start(remotes)
TerrainService.start(remotes, arena)
CharacterService.start()
MatchService.start(remotes, arena)
MovementService.start(remotes)
ProjectileService.start(remotes)
BotService.start()

workspace:SetAttribute("CritterClashBooted", true)
workspace:SetAttribute("CritterClashBuild", "0.5.0-dev")

print("[CritterClash] Development progression slice started")
