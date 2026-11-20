--!strict
-- Shared type definitions for configs, saved data and replicated state.

export type BigNum = { m: number, e: number }

export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"
export type Surface = "Snow" | "Ice" | "Powder"
export type PackQuality = "Perfect" | "Good" | "Weak"

-- One control point of the track spline (Config/Track). Blender exports the same shape.
export type TrackPoint = {
	Pos: Vector3,
	Width: number,
	Slope: number,
	Surface: Surface,
}

export type RollerDef = {
	Index: number,
	Id: string,
	Name: string,
	Power: number, -- Power per tap
	Price: number, -- cash
	RebirthsNeeded: number,
	Color: Color3, -- graybox colour until the Blender model is uploaded
}

export type RobuxRollerDef = {
	Index: number,
	Id: string,
	Name: string,
	Mult: number,
	Product: string, -- key in Config/Products ("" for pass / admin rollers)
	Color: Color3,
	Pass: string?, -- owned through this gamepass key instead of a product
	Admin: boolean?, -- only for the game's admins
}

export type PopTier = {
	Id: string,
	Name: string,
	Kind: string, -- "Train" | "Present" | "Coin" | "Luck" | "Rainbow"
	Mult: number,
	Seconds: number,
	Weight: number,
	Color: Color3,
	Product: string?,
}

export type ZoneDef = {
	Index: number,
	Id: string,
	Name: string,
	Start: number, -- studs along the track
	Power: number, -- Power needed to reach Start with a Perfect, clean roll
	CoinValue: number,
	IncomeMult: number,
	Color: Color3,
	GroundColor: Color3,
}

-- Saved per player (DataService TEMPLATE). BigNums are { m, e } tables.
export type ProfileData = {
	Version: number,
	Cash: BigNum,
	CashEarned: BigNum,
	Power: BigNum,
	Rebirths: number,
	Roller: number,
	RobuxRollers: { [string]: boolean },
	Core: number,
	EggSlots: number,
	PetSlots: number,
	PackZone: number,
	BestDistance: number,
	BestZone: number,
	ReachedVillage: boolean,
	BiggestRadius: number,
	Pets: { [string]: any },
	Eggs: { [string]: any },
	Hatching: { any },
	NextUid: number,
	Index: { [string]: boolean },
	Boosts: { [string]: any },
	Charges: { [string]: number },
	Trails: { [string]: boolean },
	Daily: { Streak: number, LastClaim: number, Weeks: number },
	Spins: number,
	CodesRedeemed: { [string]: number },
	Gamepasses: { [string]: boolean },
	GiftedPasses: { [string]: boolean },
	ReceiptsGranted: { [string]: string },
	ReceiptOrder: { string },
	LastOnline: number,
	LastRainbowPop: number,
	Flags: { [string]: any },
	Stats: { [string]: number },
	Settings: { [string]: any },
}

export type PlayerSnapshot = { [string]: any }

return {}
