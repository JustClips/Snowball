--!strict
-- Sound effects (Dev 2026-11-20: real, good sounds). All from Roblox's licensed Creator
-- Store libraries (ProSoundEffects, APM Music, Roblox UI), free to use in any experience.
-- Ui.sound(name) plays one locally; Loop = true sounds are started by the controllers.
return {
	Click = { Id = "rbxassetid://15675059323", Volume = 0.4 }, -- Roblox_UI_Bright_Click
	Tap = { Id = "rbxassetid://15675032796", Volume = 0.4 }, -- Roblox_UI_Small_Click
	Pop = { Id = "rbxassetid://15675055424", Volume = 0.6 }, -- Roblox_UI_Cute_Pop
	Rep = { Id = "rbxassetid://9119310905", Volume = 0.45 }, -- Snowball Hits Lands Semi-Deep Snow 8
	Perfect = { Id = "rbxassetid://9116395089", Volume = 0.7 }, -- Magic Glows Chiming Hits 4
	Good = { Id = "rbxassetid://9126073001", Volume = 0.55 }, -- Synth Sparkle Bell Ding
	Weak = { Id = "rbxassetid://9119316414", Volume = 0.5 }, -- Snow Impact Big Hits Semi-Deep 1
	Launch = { Id = "rbxassetid://107073250463751", Volume = 0.7 }, -- Whoosh Heavy Low
	Smash = { Id = "rbxassetid://9120957463", Volume = 0.5 }, -- Wood Roof Crash 1
	SnowHit = { Id = "rbxassetid://9125965053", Volume = 0.5 }, -- Snow Impact Stomping
	Crack = { Id = "rbxassetid://9114858583", Volume = 0.7 }, -- Ice Crackle Large Block Cracks 1
	Shatter = { Id = "rbxassetid://9125610574", Volume = 0.6 }, -- Ice Break Small Pieces
	Coin = { Id = "rbxassetid://127645268874265", Volume = 0.35 }, -- Roblox CoinTransfer_01
	Cash = { Id = "rbxassetid://9113728625", Volume = 0.45 }, -- Cash Register 1
	Egg = { Id = "rbxassetid://9116394545", Volume = 0.55 }, -- Magic Glows Chiming Hits 1
	EggCrack = { Id = "rbxassetid://9113959343", Volume = 0.6 }, -- Crack Egg Crunchy 11
	Reveal = { Id = "rbxassetid://1845399641", Volume = 0.5 }, -- APM Ta Dah
	Upgrade = { Id = "rbxassetid://1844692556", Volume = 0.5 }, -- APM Game Show
	Winner = { Id = "rbxassetid://1844584698", Volume = 0.45 }, -- APM Winner
	-- Egg hatch show (HatchController, same library sounds as Sweep the World's show, the
	-- shell ones swapped for ice)
	Wobble = { Id = "rbxassetid://9119310905", Volume = 0.5 }, -- Snowball Hits Lands Semi-Deep Snow 8 (egg knock)
	Charge = { Id = "rbxassetid://9116421342", Volume = 0.55 }, -- Magic Transformation 5
	Hatch = { Id = "rbxassetid://9117841338", Volume = 0.8 }, -- Pop Airy 1
	Sparkle = { Id = "rbxassetid://9116395085", Volume = 0.45 }, -- Magic Glows Chiming Hits 5
	RareReveal = { Id = "rbxassetid://1836860398", Volume = 0.55 }, -- APM Winning Spirit (sting)
	HatchLift = { Id = "rbxassetid://15674975792", Volume = 0.45 }, -- Roblox_UI_Whoosh_03 (egg floats up)
	HatchTier = { Id = "rbxassetid://9126073318", Volume = 0.4 }, -- Synth Sparkle Bell Ding 2 (rarity climb)
	HatchChip = { Id = "rbxassetid://9125610574", Volume = 0.4 }, -- Ice Break Small Pieces (ice chips off)
	HatchRise = { Id = "rbxassetid://9125805781", Volume = 0.5 }, -- Rising Whoosh Hissing Build Up 2
	HatchSuck = { Id = "rbxassetid://9126102694", Volume = 0.55 }, -- Time Warp Searing Build Up Large Suck Rumble
	HatchShatter = { Id = "rbxassetid://9114858583", Volume = 0.75 }, -- Ice Crackle Large Block Cracks 1 (the burst)
	HatchBoom = { Id = "rbxassetid://9120769331", Volume = 0.55 }, -- Wind Whoosh Sonic Boom Low End Impact 1 (Rare+)
	HatchShimmer = { Id = "rbxassetid://9120297092", Volume = 0.45 }, -- Twiddly Power Ons Glittery Metallic 1 (Epic+)
	HatchGong = { Id = "rbxassetid://9125585534", Volume = 0.4 }, -- Gong Chinese Style Single Hit (Mythic+)
	Roll = { Id = "rbxassetid://9125945654", Volume = 0.35, Loop = true }, -- Sign Slide Snow (rolling)
	Wind = { Id = "rbxassetid://9114228832", Volume = 0.12, Loop = true }, -- Wind Constant 2
} :: { [string]: { Id: string, Volume: number, Loop: boolean? } }
