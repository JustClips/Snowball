--!strict
-- HUD layout in design pixels for a 1280 x 720 screen. Every cluster has a UIScale that
-- follows the screen (Ui.autoScale: 0.62 on phones, up to 1.25 on big monitors) around its
-- anchor. tools/hud_preview.py reads THIS file and draws every mode on phone and PC
-- screens, so change numbers here, run the preview, look, then push.
return {
	Tile = 70, -- rail tile size (stud tile, its word is inside)
	TileWord = 0, -- words sit inside the tile now (UI polish 2026-11-20)
	TileGap = 10,
	StatRow = 70, -- cash row is taller: the "+$X/s" pet income sits under the number
	Chip = Vector2.new(116, 38),
	Stats = { Anchor = Vector2.new(0, 1), Pos = UDim2.new(0, 24, 1, -14), Size = Vector2.new(250, 120) },
	LeftRail = { Anchor = Vector2.new(0, 0.5), Pos = UDim2.new(0, 24, 0.5, -10), Size = Vector2.new(150, 230) },
	RightRail = { Anchor = Vector2.new(1, 0.5), Pos = UDim2.new(1, -24, 0.5, -10), Size = Vector2.new(150, 230) },
	TopRight = { Anchor = Vector2.new(1, 0), Pos = UDim2.new(1, -24, 0, 14), Size = Vector2.new(260, 88) },
	-- ROLL / STOP sit right above the bag hotbar (Dev 2026-11-20: hotbar bottom centre, ROLL moved up).
	Action = { Anchor = Vector2.new(0.5, 1), Pos = UDim2.new(0.5, 0, 1, -98), Size = Vector2.new(240, 80) },
	Goal = { Anchor = Vector2.new(0.5, 0), Pos = UDim2.new(0.5, 0, 0, 10), Size = Vector2.new(460, 58) },
	Luck = { Anchor = Vector2.new(0.5, 0), Pos = UDim2.new(0.5, 0, 0, 10), Size = Vector2.new(300, 130) },
	Meter = { Anchor = Vector2.new(0.5, 0.5), Pos = UDim2.new(0.5, 200, 0.5, 0), Size = Vector2.new(200, 380) }, -- tube + luck labels on its right
	Slot = 70, -- hotbar slot (InventoryController)
	-- Bag hotbar, bottom centre like Sweep the World: 6 slots + Bag on PC, 4 + Bag on phones,
	-- plus a red X on the left while you carry something (sized for the PC row with the X).
	Hotbar = { Anchor = Vector2.new(0.5, 1), Pos = UDim2.new(0.5, 0, 1, -10), Size = Vector2.new(616, 70) },
	Result = { Anchor = Vector2.new(0.5, 1), Pos = UDim2.new(0.5, 0, 1, -16), Size = Vector2.new(420, 250) },
}
