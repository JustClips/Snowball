--!nocheck
-- Serialises a GUI tree (ScreenGuis and everything in them) to plain JSON-able tables for
-- render.py. Works on real Roblox instances (Lune's @lune/roblox, for .rbxl files) and on
-- the fake ones from roblox.luau (the game's own UI code).
local Dump = {}

local PROPS = {
	"Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "Visible", "ZIndex",
	"LayoutOrder", "Rotation", "ClipsDescendants", "AutomaticSize", "SizeConstraint", "BorderSizePixel",
	"BorderColor3", "Text", "TextColor3", "TextSize", "TextScaled", "TextWrapped", "TextXAlignment",
	"TextYAlignment", "RichText", "TextTransparency", "FontFace", "Font", "TextStrokeTransparency",
	"TextStrokeColor3", "LineHeight", "Image", "ImageColor3", "ImageTransparency", "ScaleType", "TileSize",
	"SliceCenter", "SliceScale", "ImageRectOffset", "ImageRectSize", "Thickness", "Color", "Transparency",
	"Enabled", "ApplyStrokeMode", "LineJoinMode", "CornerRadius", "Offset", "Scale", "PaddingLeft",
	"PaddingRight", "PaddingTop", "PaddingBottom", "Padding", "FillDirection", "HorizontalAlignment",
	"VerticalAlignment", "SortOrder", "Wraps", "CellSize", "CellPadding", "FillDirectionMaxCells",
	"StartCorner", "AspectRatio", "AspectType", "DominantAxis", "MinSize", "MaxSize", "MinTextSize",
	"MaxTextSize", "CanvasSize", "CanvasPosition", "ScrollBarThickness", "ScrollBarImageColor3",
	"AutomaticCanvasSize", "ScrollingDirection", "DisplayOrder", "IgnoreGuiInset", "ScreenInsets",
	"GroupTransparency", "GroupColor3", "ZIndexBehavior", "HorizontalFlex", "VerticalFlex", "FlexMode",
	"GrowRatio", "ShrinkRatio", "MaxVisibleGraphemes", "PlaceholderText", "TextTruncate",
	"ResampleMode",
}

local GUI = {
	ScreenGui = true, Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true,
	ImageButton = true, ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true, VideoFrame = true,
	UIStroke = true, UICorner = true, UIGradient = true, UIScale = true, UIPadding = true, UIListLayout = true,
	UIGridLayout = true, UIAspectRatioConstraint = true, UISizeConstraint = true, UITextSizeConstraint = true,
	UIFlexItem = true, Folder = true,
}

local function ser(v, typeofFn)
	local t = typeofFn(v)
	if t == "number" or t == "string" or t == "boolean" then
		if t == "number" and (v ~= v or v == math.huge or v == -math.huge) then
			return if v == math.huge then 1e9 elseif v == -math.huge then -1e9 else 0
		end
		return v
	elseif t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	elseif t == "Vector2" then
		return { ser(v.X, typeofFn), ser(v.Y, typeofFn) }
	elseif t == "Color3" then
		return { v.R, v.G, v.B }
	elseif t == "EnumItem" then
		return v.Name
	elseif t == "Font" then
		local w = v.Weight
		return { family = v.Family, weight = if w then w.Name else "Regular", style = if v.Style then v.Style.Name else "Normal" }
	elseif t == "ColorSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { k.Time, k.Value.R, k.Value.G, k.Value.B })
		end
		return out
	elseif t == "NumberSequence" then
		local out = {}
		for _, k in v.Keypoints do
			table.insert(out, { k.Time, k.Value })
		end
		return out
	elseif t == "Rect" then
		return { v.Min.X, v.Min.Y, v.Max.X, v.Max.Y }
	end
	return nil
end

function Dump.node(x, typeofFn, getFn)
	local cls = x.ClassName
	if not GUI[cls] then
		return nil
	end
	local p = {}
	for _, name in PROPS do
		local ok, v = pcall(getFn, x, name)
		if ok and v ~= nil and typeofFn(v) ~= "Instance" then
			local s = ser(v, typeofFn)
			if s ~= nil then
				p[name] = s
			end
		end
	end
	if p.Image == nil then
		local ok, v = pcall(getFn, x, "ImageContent")
		if ok and v ~= nil then
			local uri = tostring(v):match("Uri=([^%)]+)")
			if uri then
				p.Image = uri
			end
		end
	end
	local kids = {}
	for _, c in x:GetChildren() do
		local d = Dump.node(c, typeofFn, getFn)
		if d then
			table.insert(kids, d)
		end
	end
	return { c = cls, n = x.Name, p = p, k = kids }
end

return Dump
