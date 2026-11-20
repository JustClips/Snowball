--!strict
-- HUD layout in design pixels for a 1280 x 720 screen. Every cluster has a UIScale that
-- follows the screen (Ui.autoScale: 0.62 on phones, up to 1.25 on big monitors) around its
-- anchor. tools/hud_preview.py reads THIS file and draws every mode on phone and PC
-- screens, so change numbers here, run the preview, look, then push.
return {
	Tile = 64, -- rail tile size
	TileWord = 24, -- the word under a tile
	TileGap = 10,
	StatRow = 54,
	Chip = Vector2.new(116, 38),
	Stats = { Anchor = Vector2.new(0, 1), Pos = UDim2.new(0, 24, 1, -14), Size = Vector2.new(250, 104) },
	LeftRail = { Anchor = Vector2.new(0, 0.5), Pos = UDim2.new(0, 24, 0.5, -16), Size = Vector2.new(138, 290) },
	RightRail = { Anchor = Vector2.new(1, 0.5), Pos = UDim2.new(1, -24, 0.5, -16), Size = Vector2.new(138, 290) },
	TopRight = { Anchor = Vector2.new(1, 0), Pos = UDim2.new(1, -24, 0, 18), Size = Vector2.new(260, 130) },
	Action = { Anchor = Vector2.new(0.5, 1), Pos = UDim2.new(0.5, 0, 1, -14), Size = Vector2.new(240, 80) },
	Goal = { Anchor = Vector2.new(0.5, 0), Pos = UDim2.new(0.5, 0, 0, 10), Size = Vector2.new(460, 58) },
	Luck = { Anchor = Vector2.new(0.5, 0), Pos = UDim2.new(0.5, 0, 0, 10), Size = Vector2.new(300, 130) },
	Meter = { Anchor = Vector2.new(0.5, 0.5), Pos = UDim2.new(0.5, 170, 0.5, 0), Size = Vector2.new(120, 380) },
	Result = { Anchor = Vector2.new(0.5, 1), Pos = UDim2.new(0.5, 0, 1, -16), Size = Vector2.new(420, 250) },
}
