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
	Roll = { Id = "rbxassetid://9125945654", Volume = 0.35, Loop = true }, -- Sign Slide Snow (rolling)
	Wind = { Id = "rbxassetid://9114228832", Volume = 0.12, Loop = true }, -- Wind Constant 2
} :: { [string]: { Id: string, Volume: number, Loop: boolean? } }
