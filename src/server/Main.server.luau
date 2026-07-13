--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArenaService = require(script.Parent.Services.ArenaService)
local CharacterService = require(script.Parent.Services.CharacterService)
local MatchService = require(script.Parent.Services.MatchService)
local NetworkService = require(script.Parent.Services.NetworkService)
local ProjectileService = require(script.Parent.Services.ProjectileService)

local Weapons = require(ReplicatedStorage.Shared.Config.Weapons)

local catalogueValid, catalogueReason = Weapons.validateCatalogue(Weapons.All)
assert(catalogueValid, catalogueReason or "Weapon catalogue validation failed")

ArenaService.createGreybox()
local remotes = NetworkService.create()
CharacterService.start()
MatchService.start(remotes)
ProjectileService.start(remotes)

workspace:SetAttribute("CritterClashBooted", true)
workspace:SetAttribute("CritterClashBuild", "0.1.0-dev")

print("[CritterClash] Development combat slice started")
