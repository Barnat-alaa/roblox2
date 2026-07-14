--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaService = require(script.Parent.Services.ArenaService)
local BotService = require(script.Parent.Services.BotService)
local CharacterService = require(script.Parent.Services.CharacterService)
local MatchService = require(script.Parent.Services.MatchService)
local NetworkService = require(script.Parent.Services.NetworkService)
local ProjectileService = require(script.Parent.Services.ProjectileService)
local TerrainService = require(script.Parent.Services.TerrainService)

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local catalogueValid, catalogueReason = Weapons.validateCatalogue(Weapons.All)
assert(catalogueValid, catalogueReason or "Weapon catalogue validation failed")

local arena = ArenaService.createGreybox()
local remotes = NetworkService.create()
TerrainService.start(remotes, arena)
CharacterService.start()
MatchService.start(remotes, arena)
ProjectileService.start(remotes)
BotService.start()

workspace:SetAttribute("CritterClashBooted", true)
workspace:SetAttribute("CritterClashBuild", "0.3.0-dev")

print("[CritterClash] Development combat slice started")
