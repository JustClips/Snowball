--!strict
-- Every uploaded asset the game loads at run time, by key. All from Dev's main account
-- (creator 822623546). 0 = not uploaded yet: the code uses a graybox placeholder.
-- Keys for Blender models (art thread): Roller_<Id>, Obstacle_<Kind>, Snowball, Egg_<Rarity>,
-- Summit, Track_<Zone>. Add them here when they're uploaded.
local Assets = {
	-- Dev's StudAnimalPack_100 (100 pets), uploaded 2026-11-20 as one Model.
	PetPack = 121457820511402,
	Models = {} :: { [string]: number },
	Images = {} :: { [string]: string },
}

return Assets
