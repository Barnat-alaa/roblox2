--!strict

export type MatchPhase =
	"WaitingForPlayers"
	| "Countdown"
	| "TurnStart"
	| "Movement"
	| "Aiming"
	| "ProjectileFired"
	| "ProjectileResolving"
	| "EnvironmentalResolution"
	| "TurnEnd"
	| "RoundEnd"
	| "MatchEnd"
	| "Results"

export type FireRequest = {
	weaponId: string,
	angle: number,
	power: number,
}

export type ShotLaunch = {
	shotId: string,
	shooterUserId: number,
	weaponId: string,
	origin: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	serverTime: number,
	seed: number,
}

return nil
