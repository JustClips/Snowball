--!nocheck
-- A small fake of the Roblox client API, enough to run the game's client UI code in Lune
-- (no Studio): Instances with properties/children/signals/attributes, the data types the
-- UI uses, a virtual-time task scheduler, TweenService that jumps to the end, and a
-- require() that loads modules from the Rojo tree. tools/ui_render/run.luau uses it to
-- open each screen and dump the PlayerGui; render.py draws the dump.
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local R = {}

-------------------------------------------------------------------------- scheduler

local now = 0
local timers = {} -- { at, co, args }
local deferred = {}
local errors = {}
R.errors = errors

local function report(err, where)
	local msg = tostring(err)
	if not errors[msg] then
		errors[msg] = true
		print("[error] " .. (where or "") .. " " .. msg)
	end
end

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		report(debug.traceback(co, tostring(err)), "")
	end
end

local task = {}
function task.spawn(f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(t, f, ...)
	local co = if type(f) == "thread" then f else coroutine.create(f)
	table.insert(timers, { at = now + (t or 0), co = co, args = table.pack(...) })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	local start = now
	table.insert(timers, { at = now + math.max(t or 0, 1 / 60), co = co, args = table.pack() })
	coroutine.yield()
	return now - start
end
function task.cancel(co)
	for i = #timers, 1, -1 do
		if timers[i].co == co then
			table.remove(timers, i)
		end
	end
end
function task.synchronize() end
function task.desynchronize() end
R.task = task

-------------------------------------------------------------------------- signals

local Signal = {}
Signal.__index = Signal
function Signal.new(name)
	return setmetatable({ handlers = {}, waiting = {}, name = name }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true }
	local entry = { fn = fn, conn = conn }
	table.insert(self.handlers, entry)
	function conn.Disconnect()
		conn.Connected = false
	end
	conn.disconnect = conn.Disconnect
	return setmetatable(conn, {
		__index = function(_, k)
			if k == "Disconnect" then
				return function()
					conn.Connected = false
				end
			end
			return nil
		end,
	})
end
Signal.connect = Signal.Connect
function Signal:Once(fn)
	local c
	c = self:Connect(function(...)
		c.Connected = false
		fn(...)
	end)
	return c
end
function Signal:ConnectParallel(fn)
	return self:Connect(fn)
end
function Signal:Wait()
	local co = coroutine.running()
	table.insert(self.waiting, co)
	return coroutine.yield()
end
function Signal:Fire(...)
	for _, h in table.clone(self.handlers) do
		if h.conn.Connected then
			task.spawn(h.fn, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, co in w do
		resume(co, ...)
	end
end
R.Signal = Signal

-------------------------------------------------------------------------- data types

local function readonly(name, t, mt)
	mt.__type = name
	return setmetatable(t, mt)
end

local Vector2 = {}
local V2mt = {}
V2mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return Vector2.new(v.X / m, v.Y / m)
	elseif k == "Lerp" then
		return function(a, b, t)
			return Vector2.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
		end
	elseif k == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y
		end
	elseif k == "Max" then
		return function(a, b)
			return Vector2.new(math.max(a.X, b.X), math.max(a.Y, b.Y))
		end
	elseif k == "Min" then
		return function(a, b)
			return Vector2.new(math.min(a.X, b.X), math.min(a.Y, b.Y))
		end
	end
	return nil
end
local function num2(v)
	if type(v) == "number" then
		return v, v
	end
	return v.X, v.Y
end
V2mt.__add = function(a, b)
	return Vector2.new(a.X + b.X, a.Y + b.Y)
end
V2mt.__sub = function(a, b)
	return Vector2.new(a.X - b.X, a.Y - b.Y)
end
V2mt.__mul = function(a, b)
	local ax, ay = num2(a)
	local bx, by = num2(b)
	return Vector2.new(ax * bx, ay * by)
end
V2mt.__div = function(a, b)
	local ax, ay = num2(a)
	local bx, by = num2(b)
	return Vector2.new(ax / bx, ay / by)
end
V2mt.__unm = function(a)
	return Vector2.new(-a.X, -a.Y)
end
V2mt.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2mt.__tostring = function(a)
	return `{a.X}, {a.Y}`
end
function Vector2.new(x, y)
	return readonly("Vector2", { X = x or 0, Y = y or 0 }, V2mt)
end
Vector2.zero = Vector2.new(0, 0)
Vector2.one = Vector2.new(1, 1)
Vector2.xAxis = Vector2.new(1, 0)
Vector2.yAxis = Vector2.new(0, 1)
R.Vector2 = Vector2

local Vector3 = {}
local V3mt = {}
V3mt.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.max(1e-9, math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z))
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	elseif k == "Lerp" then
		return function(a, b, t)
			return a + (b - a) * t
		end
	elseif k == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	elseif k == "Cross" then
		return function(a, b)
			return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	end
	return nil
end
local function num3(v)
	if type(v) == "number" then
		return v, v, v
	end
	return v.X, v.Y, v.Z
end
V3mt.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3mt.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3mt.__mul = function(a, b)
	local ax, ay, az = num3(a)
	local bx, by, bz = num3(b)
	return Vector3.new(ax * bx, ay * by, az * bz)
end
V3mt.__div = function(a, b)
	local ax, ay, az = num3(a)
	local bx, by, bz = num3(b)
	return Vector3.new(ax / bx, ay / by, az / bz)
end
V3mt.__unm = function(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end
function Vector3.new(x, y, z)
	return readonly("Vector3", { X = x or 0, Y = y or 0, Z = z or 0 }, V3mt)
end
Vector3.zero = Vector3.new()
Vector3.one = Vector3.new(1, 1, 1)
Vector3.yAxis = Vector3.new(0, 1, 0)
Vector3.xAxis = Vector3.new(1, 0, 0)
Vector3.zAxis = Vector3.new(0, 0, 1)
R.Vector3 = Vector3

local UDim = {}
local UDmt = {}
UDmt.__add = function(a, b)
	return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDmt.__sub = function(a, b)
	return UDim.new(a.Scale - b.Scale, a.Offset - b.Offset)
end
function UDim.new(s, o)
	return readonly("UDim", { Scale = s or 0, Offset = o or 0 }, UDmt)
end
R.UDim = UDim

local UDim2 = {}
local U2mt = {}
U2mt.__index = function(u, k)
	if k == "Width" then
		return UDim.new(u.X.Scale, u.X.Offset)
	elseif k == "Height" then
		return UDim.new(u.Y.Scale, u.Y.Offset)
	elseif k == "Lerp" then
		return function(a, b, t)
			return UDim2.new(
				a.X.Scale + (b.X.Scale - a.X.Scale) * t,
				a.X.Offset + (b.X.Offset - a.X.Offset) * t,
				a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t,
				a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t
			)
		end
	end
	return nil
end
U2mt.__add = function(a, b)
	return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
U2mt.__sub = function(a, b)
	return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
U2mt.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
function UDim2.new(a, b, c, d)
	if type(a) == "table" then
		return readonly("UDim2", { X = a, Y = b }, U2mt)
	end
	return readonly("UDim2", { X = UDim.new(a, b), Y = UDim.new(c, d) }, U2mt)
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x or 0, 0, y or 0)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x or 0, 0, y or 0, 0)
end
R.UDim2 = UDim2

local Color3 = {}
local C3mt = {}
C3mt.__index = function(_, k)
	if k == "Lerp" then
		return function(a, b, t)
			return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
		end
	elseif k == "ToHSV" then
		return function(c)
			local r, g, b = c.R, c.G, c.B
			local mx, mn = math.max(r, g, b), math.min(r, g, b)
			local h, s, v = 0, 0, mx
			local d = mx - mn
			s = if mx == 0 then 0 else d / mx
			if d ~= 0 then
				if mx == r then
					h = (g - b) / d % 6
				elseif mx == g then
					h = (b - r) / d + 2
				else
					h = (r - g) / d + 4
				end
				h /= 6
			end
			return h, s, v
		end
	elseif k == "ToHex" then
		return function(c)
			return string.format("%02X%02X%02X", c.R * 255, c.G * 255, c.B * 255)
		end
	end
	return nil
end
C3mt.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function Color3.new(r, g, b)
	return readonly("Color3", { R = r or 0, G = g or 0, B = b or 0 }, C3mt)
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i %= 6
	if i == 0 then
		return Color3.new(v, t, p)
	elseif i == 1 then
		return Color3.new(q, v, p)
	elseif i == 2 then
		return Color3.new(p, v, t)
	elseif i == 3 then
		return Color3.new(p, q, v)
	elseif i == 4 then
		return Color3.new(t, p, v)
	end
	return Color3.new(v, p, q)
end
function Color3.fromHex(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
Color3.toHSV = function(c)
	return C3mt.__index(c, "ToHSV")(c)
end
R.Color3 = Color3

local ColorSequenceKeypoint = {}
function ColorSequenceKeypoint.new(t, c)
	return readonly("ColorSequenceKeypoint", { Time = t, Value = c }, {})
end
local ColorSequence = {}
function ColorSequence.new(a, b)
	local kps
	if type(a) == "table" and a.R == nil then
		kps = a
	else
		kps = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
	end
	return readonly("ColorSequence", { Keypoints = kps }, {})
end
R.ColorSequence, R.ColorSequenceKeypoint = ColorSequence, ColorSequenceKeypoint

local NumberSequenceKeypoint = {}
function NumberSequenceKeypoint.new(t, v, e)
	return readonly("NumberSequenceKeypoint", { Time = t, Value = v, Envelope = e or 0 }, {})
end
local NumberSequence = {}
function NumberSequence.new(a, b)
	local kps
	if type(a) == "table" then
		kps = a
	else
		kps = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
	end
	return readonly("NumberSequence", { Keypoints = kps }, {})
end
R.NumberSequence, R.NumberSequenceKeypoint = NumberSequence, NumberSequenceKeypoint

local NumberRange = {}
function NumberRange.new(a, b)
	return readonly("NumberRange", { Min = a, Max = b or a }, {})
end
R.NumberRange = NumberRange

local Rect = {}
function Rect.new(a, b, c, d)
	if type(a) == "table" then
		return readonly("Rect", { Min = a, Max = b }, {})
	end
	return readonly("Rect", { Min = Vector2.new(a, b), Max = Vector2.new(c, d) }, {})
end
R.Rect = Rect

-- Enums: Enum.X.Y is an item; Enum.X:GetEnumItems() works for known lists.
local enumItems = {}
local function enumItem(enum, name)
	enumItems[enum] = enumItems[enum] or {}
	local item = enumItems[enum][name]
	if not item then
		item = setmetatable({ Name = name, EnumType = enum, Value = 0 }, {
			__type = "EnumItem",
			__tostring = function()
				return `Enum.{enum}.{name}`
			end,
		})
		enumItems[enum][name] = item
	end
	return item
end
local Enum = setmetatable({}, {
	__index = function(_, enum)
		return setmetatable({}, {
			__index = function(_, name)
				if name == "GetEnumItems" then
					return function()
						local out = {}
						for _, v in enumItems[enum] or {} do
							table.insert(out, v)
						end
						return out
					end
				end
				return enumItem(enum, name)
			end,
		})
	end,
})
R.Enum = Enum

local Font = {}
local FontMt = { __type = "Font" }
function Font.new(family, weight, style)
	return setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style }, FontMt)
end
function Font.fromEnum(e)
	return Font.new("rbxasset://fonts/families/" .. e.Name .. ".json", Enum.FontWeight.Regular)
end
function Font.fromName(name, weight, style)
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
function Font.fromId(id, weight, style)
	return Font.new("rbxassetid://" .. id, weight, style)
end
R.Font = Font

local TweenInfo = {}
function TweenInfo.new(t, style, dir, rep, rev, delay)
	return readonly("TweenInfo", {
		Time = t or 1,
		EasingStyle = style,
		EasingDirection = dir,
		RepeatCount = rep or 0,
		Reverses = rev or false,
		DelayTime = delay or 0,
	}, {})
end
R.TweenInfo = TweenInfo

-- CFrame: only what UI code touches (position + a few helpers).
local CFrame = {}
local CFmt = {}
CFmt.__index = function(cf, k)
	if k == "Position" or k == "p" then
		return Vector3.new(cf.X, cf.Y, cf.Z)
	elseif k == "LookVector" then
		return Vector3.new(0, 0, -1)
	elseif k == "UpVector" then
		return Vector3.new(0, 1, 0)
	elseif k == "RightVector" then
		return Vector3.new(1, 0, 0)
	elseif k == "Rotation" then
		return CFrame.new()
	elseif k == "Inverse" then
		return function(c)
			return CFrame.new(-c.X, -c.Y, -c.Z)
		end
	elseif k == "Lerp" then
		return function(a, b, t)
			return CFrame.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
		end
	elseif k == "ToWorldSpace" or k == "ToObjectSpace" then
		return function(a, b)
			return b
		end
	elseif k == "PointToWorldSpace" or k == "PointToObjectSpace" or k == "VectorToWorldSpace" or k == "VectorToObjectSpace" then
		return function(_, v)
			return v
		end
	elseif k == "GetComponents" then
		return function(c)
			return c.X, c.Y, c.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1
		end
	elseif k == "ToEulerAnglesXYZ" or k == "ToOrientation" or k == "ToEulerAnglesYXZ" then
		return function()
			return 0, 0, 0
		end
	end
	return nil
end
CFmt.__mul = function(a, b)
	if getmetatable(b) == V3mt then
		return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
	end
	return CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFmt.__add = function(a, b)
	return CFrame.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
CFmt.__sub = function(a, b)
	return CFrame.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return readonly("CFrame", { X = x.X, Y = x.Y, Z = x.Z }, CFmt)
	end
	return readonly("CFrame", { X = x or 0, Y = y or 0, Z = z or 0 }, CFmt)
end
CFrame.identity = CFrame.new()
function CFrame.Angles()
	return CFrame.new()
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
CFrame.fromEulerAnglesYXZ = CFrame.Angles
CFrame.fromOrientation = CFrame.Angles
function CFrame.lookAt(a)
	return CFrame.new(a)
end
function CFrame.fromAxisAngle()
	return CFrame.new()
end
function CFrame.fromMatrix(p)
	return CFrame.new(p)
end
R.CFrame = CFrame

local BrickColor = {}
function BrickColor.new()
	return readonly("BrickColor", { Color = Color3.new(0.6, 0.6, 0.6), Name = "Medium stone grey" }, {})
end
BrickColor.random = BrickColor.new
R.BrickColor = BrickColor

local RaycastParams = {}
function RaycastParams.new()
	return { FilterDescendantsInstances = {}, FilterType = nil }
end
R.RaycastParams = RaycastParams
R.OverlapParams = RaycastParams

local PhysicalProperties = {}
function PhysicalProperties.new()
	return {}
end
R.PhysicalProperties = PhysicalProperties

function R.typeof(v)
	local mt = getmetatable(v)
	if type(mt) == "table" and mt.__type then
		return mt.__type
	end
	return type(v)
end

-------------------------------------------------------------------------- instances

local DEFAULTS = {
	GuiObject = {
		Size = UDim2.new(0, 100, 0, 100),
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(163, 162, 165),
		BackgroundTransparency = 0,
		BorderSizePixel = 1,
		BorderColor3 = Color3.fromRGB(27, 42, 53),
		Visible = true,
		ZIndex = 1,
		LayoutOrder = 0,
		Rotation = 0,
		ClipsDescendants = false,
		AutomaticSize = Enum.AutomaticSize.None,
		Active = false,
		Selectable = false,
		Interactable = true,
		SizeConstraint = Enum.SizeConstraint.RelativeXY,
		AbsoluteSize = Vector2.new(100, 100),
		AbsolutePosition = Vector2.new(0, 0),
		AbsoluteRotation = 0,
		GuiState = Enum.GuiState.Idle,
	},
	Text = {
		Text = "Label",
		TextColor3 = Color3.fromRGB(27, 42, 53),
		TextSize = 14,
		TextScaled = false,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
		TextTransparency = 0,
		TextStrokeTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		FontFace = Font.new("rbxasset://fonts/families/SourceSansPro.json"),
		Font = Enum.Font.SourceSans,
		LineHeight = 1,
		TextTruncate = Enum.TextTruncate.None,
		MaxVisibleGraphemes = -1,
		PlaceholderText = "",
		ClearTextOnFocus = true,
		TextBounds = Vector2.new(0, 0),
		TextFits = true,
		ContentText = "",
	},
	Image = {
		Image = "",
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0,
		ScaleType = Enum.ScaleType.Stretch,
		TileSize = UDim2.new(1, 0, 1, 0),
		SliceCenter = Rect.new(0, 0, 0, 0),
		SliceScale = 1,
		ImageRectOffset = Vector2.new(0, 0),
		ImageRectSize = Vector2.new(0, 0),
		ResampleMode = Enum.ResamplerMode.Default,
		IsLoaded = true,
	},
	Button = { AutoButtonColor = true, Modal = false, Selected = false },
	ScreenGui = {
		Enabled = true,
		DisplayOrder = 0,
		IgnoreGuiInset = false,
		ResetOnSpawn = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Global,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		AbsoluteSize = Vector2.new(1280, 720),
	},
	BillboardGui = { Enabled = true, Size = UDim2.new(0, 100, 0, 100), AlwaysOnTop = false, MaxDistance = math.huge },
	SurfaceGui = { Enabled = true },
	UIStroke = {
		Thickness = 1,
		Color = Color3.new(0, 0, 0),
		Transparency = 0,
		Enabled = true,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	},
	UICorner = { CornerRadius = UDim.new(0, 8) },
	UIGradient = {
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0),
		Rotation = 0,
		Offset = Vector2.new(0, 0),
		Enabled = true,
	},
	UIScale = { Scale = 1 },
	UIPadding = {
		PaddingLeft = UDim.new(0, 0),
		PaddingRight = UDim.new(0, 0),
		PaddingTop = UDim.new(0, 0),
		PaddingBottom = UDim.new(0, 0),
	},
	UIListLayout = {
		Padding = UDim.new(0, 0),
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Wraps = false,
		HorizontalFlex = Enum.UIFlexAlignment.None,
		VerticalFlex = Enum.UIFlexAlignment.None,
		AbsoluteContentSize = Vector2.new(0, 0),
	},
	UIGridLayout = {
		CellSize = UDim2.new(0, 100, 0, 100),
		CellPadding = UDim2.new(0, 5, 0, 5),
		FillDirection = Enum.FillDirection.Horizontal,
		FillDirectionMaxCells = 0,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.LayoutOrder,
		StartCorner = Enum.StartCorner.TopLeft,
		AbsoluteContentSize = Vector2.new(0, 0),
	},
	UIAspectRatioConstraint = {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
	},
	UISizeConstraint = { MinSize = Vector2.new(0, 0), MaxSize = Vector2.new(math.huge, math.huge) },
	UITextSizeConstraint = { MinTextSize = 1, MaxTextSize = 100 },
	ScrollingFrame = {
		CanvasSize = UDim2.new(0, 0, 2, 0),
		CanvasPosition = Vector2.new(0, 0),
		ScrollBarThickness = 12,
		ScrollBarImageColor3 = Color3.new(0, 0, 0),
		ScrollBarImageTransparency = 0,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		ScrollingEnabled = true,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		VerticalScrollBarInset = Enum.ScrollBarInset.None,
		AbsoluteCanvasSize = Vector2.new(0, 0),
		AbsoluteWindowSize = Vector2.new(0, 0),
	},
	ViewportFrame = {
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.fromRGB(140, 140, 140),
		LightDirection = Vector3.new(-1, -1, -1),
		ImageColor3 = Color3.new(1, 1, 1),
		ImageTransparency = 0,
	},
	CanvasGroup = { GroupTransparency = 0, GroupColor3 = Color3.new(1, 1, 1) },
	Sound = {
		SoundId = "",
		Volume = 0.5,
		PlaybackSpeed = 1,
		Looped = false,
		IsPlaying = false,
		TimeLength = 1,
		TimePosition = 0,
		IsLoaded = true,
	},
	BasePart = {
		Size = Vector3.new(4, 1, 2),
		Position = Vector3.new(0, 0, 0),
		CFrame = CFrame.new(),
		Anchored = false,
		CanCollide = true,
		Transparency = 0,
		Color = Color3.new(0.6, 0.6, 0.6),
	},
	Camera = { FieldOfView = 70, CFrame = CFrame.new(0, 10, 10), CameraType = Enum.CameraType.Custom },
	Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, RootPart = nil },
	ProximityPrompt = { Enabled = true, ActionText = "", ObjectText = "", HoldDuration = 0, MaxActivationDistance = 10 },
}

local CLASS_FAMILY = {
	Frame = { "GuiObject" },
	TextLabel = { "GuiObject", "Text" },
	TextButton = { "GuiObject", "Text", "Button" },
	TextBox = { "GuiObject", "Text" },
	ImageLabel = { "GuiObject", "Image" },
	ImageButton = { "GuiObject", "Image", "Button" },
	ScrollingFrame = { "GuiObject", "ScrollingFrame" },
	ViewportFrame = { "GuiObject", "ViewportFrame" },
	CanvasGroup = { "GuiObject", "CanvasGroup" },
	VideoFrame = { "GuiObject" },
	Part = { "BasePart" },
	MeshPart = { "BasePart" },
	WedgePart = { "BasePart" },
	UnionOperation = { "BasePart" },
}

local IS_A = {
	GuiObject = { "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup", "VideoFrame" },
	GuiButton = { "TextButton", "ImageButton" },
	GuiBase2d = { "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup", "ScreenGui", "BillboardGui", "SurfaceGui" },
	LayerCollector = { "ScreenGui", "BillboardGui", "SurfaceGui" },
	BasePart = { "Part", "MeshPart", "WedgePart", "UnionOperation", "TrussPart", "SpawnLocation" },
	PVInstance = { "Model", "Part", "MeshPart", "WedgePart", "UnionOperation" },
	UIComponent = { "UIStroke", "UICorner", "UIGradient", "UIScale", "UIPadding", "UIListLayout", "UIGridLayout", "UIAspectRatioConstraint", "UISizeConstraint", "UITextSizeConstraint" },
	UIGridStyleLayout = { "UIListLayout", "UIGridLayout" },
	ValueBase = { "IntValue", "NumberValue", "StringValue", "BoolValue", "ObjectValue" },
	LuaSourceContainer = { "ModuleScript", "LocalScript", "Script" },
	Constraint = { "Weld", "WeldConstraint", "Motor6D" },
}

local EVENTS = {
	Activated = true,
	MouseButton1Click = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton2Click = true,
	MouseEnter = true,
	MouseLeave = true,
	MouseMoved = true,
	InputBegan = true,
	InputEnded = true,
	InputChanged = true,
	FocusLost = true,
	Focused = true,
	ChildAdded = true,
	ChildRemoved = true,
	DescendantAdded = true,
	DescendantRemoving = true,
	AncestryChanged = true,
	Destroying = true,
	Changed = true,
	AttributeChanged = true,
	OnClientEvent = true,
	OnServerEvent = true,
	Event = true,
	Triggered = true,
	TriggerEnded = true,
	PromptShown = true,
	PromptHidden = true,
	PromptTriggered = true,
	Touched = true,
	TouchEnded = true,
	Died = true,
	CharacterAdded = true,
	CharacterRemoving = true,
	Ended = true,
	Completed = true,
	Played = true,
	Stopped = true,
	DidLoop = true,
	KeyframeReached = true,
	MoveToFinished = true,
	StateChanged = true,
	Running = true,
	Jumping = true,
	Heartbeat = true,
	RenderStepped = true,
	Stepped = true,
	PreRender = true,
	PreSimulation = true,
	PostSimulation = true,
	PlayerAdded = true,
	PlayerRemoving = true,
	SelectionGained = true,
	SelectionLost = true,
	ReturnPressedFromOnScreenKeyboard = true,
	TouchTap = true,
	TouchLongPress = true,
	TouchPan = true,
	TouchPinch = true,
	TouchStarted = true,
	TouchMoved = true,
	JumpRequest = true,
	LastInputTypeChanged = true,
	WindowFocusReleased = true,
	WindowFocused = true,
	PromptProductPurchaseFinished = true,
	PromptGamePassPurchaseFinished = true,
	PromptPurchaseFinished = true,
	MenuOpened = true,
	MenuClosed = true,
	GamepadConnected = true,
	GamepadDisconnected = true,
	Idled = true,
	Animated = true,
	AnimationPlayed = true,
	OnInvoke = true,
	DragStart = true,
	DragEnd = true,
	DragContinue = true,
}

local inst = {} -- proxy -> state
R.state = inst
local Instance = {}
local Imt = {}

local function isA(className, want)
	if className == want or want == "Instance" then
		return true
	end
	local list = IS_A[want]
	if list then
		for _, c in list do
			if c == className then
				return true
			end
		end
	end
	return false
end

local function propChanged(s, key)
	local sig = s.propSignals[key]
	if sig then
		sig:Fire()
	end
	if s.events.Changed then
		s.events.Changed:Fire(key)
	end
end

local function setParent(self, s, parent)
	if s.parent == parent then
		return
	end
	if s.parent then
		local ps = inst[s.parent]
		for i, c in ps.children do
			if c == self then
				table.remove(ps.children, i)
				break
			end
		end
		if ps.events.ChildRemoved then
			ps.events.ChildRemoved:Fire(self)
		end
	end
	s.parent = parent
	if parent then
		local ps = inst[parent]
		table.insert(ps.children, self)
		if ps.events.ChildAdded then
			ps.events.ChildAdded:Fire(self)
		end
		-- WaitForChild waiters
		local w = ps.childWaiters[s.props.Name]
		if w then
			ps.childWaiters[s.props.Name] = nil
			for _, co in w do
				resume(co, self)
			end
		end
		local a = parent
		while a do
			local as = inst[a]
			if as.events.DescendantAdded then
				as.events.DescendantAdded:Fire(self)
			end
			a = as.parent
		end
	end
	propChanged(s, "Parent")
	if s.events.AncestryChanged then
		s.events.AncestryChanged:Fire(self, parent)
	end
end

local METHODS = {}

function R.isGui(x)
	while x do
		local c = inst[x].className
		if c == "PlayerGui" or c == "ScreenGui" or c == "Folder" and inst[x].props.Name == "Remotes" then
			return true
		end
		x = inst[x].parent
	end
	return false
end

function METHODS:FindFirstChild(name, recursive)
	for _, c in inst[self].children do
		if inst[c].props.Name == name then
			return c
		end
	end
	if recursive then
		for _, c in inst[self].children do
			local f = METHODS.FindFirstChild(c, name, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function METHODS:FindFirstChildOfClass(cls)
	for _, c in inst[self].children do
		if inst[c].className == cls then
			return c
		end
	end
	return nil
end
function METHODS:FindFirstChildWhichIsA(cls, recursive)
	for _, c in inst[self].children do
		if isA(inst[c].className, cls) then
			return c
		end
	end
	if recursive then
		for _, c in inst[self].children do
			local f = METHODS.FindFirstChildWhichIsA(c, cls, true)
			if f then
				return f
			end
		end
	end
	return nil
end
function METHODS:FindFirstAncestor(name)
	local p = inst[self].parent
	while p do
		if inst[p].props.Name == name then
			return p
		end
		p = inst[p].parent
	end
	return nil
end
function METHODS:FindFirstAncestorOfClass(cls)
	local p = inst[self].parent
	while p do
		if inst[p].className == cls then
			return p
		end
		p = inst[p].parent
	end
	return nil
end
function METHODS:FindFirstAncestorWhichIsA(cls)
	local p = inst[self].parent
	while p do
		if isA(inst[p].className, cls) then
			return p
		end
		p = inst[p].parent
	end
	return nil
end
function METHODS:FindFirstDescendant(name)
	return METHODS.FindFirstChild(self, name, true)
end
function METHODS:WaitForChild(name, timeout)
	local found = METHODS.FindFirstChild(self, name)
	if found then
		return found
	end
	local s = inst[self]
	if s.autoChild then
		local made = s.autoChild(name)
		if made then
			return made
		end
	end
	-- World objects the server would build: hand back an empty Model (UI never needs them).
	if R.autoWorld and not timeout and not R.isGui(self) and s.props.Name ~= "Remotes" then
		local m = Instance.new("Model")
		m.Name = name
		setParent(m, inst[m], self)
		inst[m].autoChild = s.autoChild
		return m
	end
	local co = coroutine.running()
	if R.debugWaits then
		print("[wait] " .. tostring(s.props.Name) .. "." .. tostring(name))
	end
	s.childWaiters[name] = s.childWaiters[name] or {}
	table.insert(s.childWaiters[name], co)
	if timeout then
		task.delay(timeout, function()
			local w = s.childWaiters[name]
			if w then
				for i, c in w do
					if c == co then
						table.remove(w, i)
						resume(co, nil)
						return
					end
				end
			end
		end)
	end
	return coroutine.yield()
end
function METHODS:GetChildren()
	return table.clone(inst[self].children)
end
function METHODS:GetDescendants()
	local out = {}
	local function walk(x)
		for _, c in inst[x].children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function METHODS:IsA(cls)
	return isA(inst[self].className, cls)
end
function METHODS:IsDescendantOf(other)
	local p = inst[self].parent
	while p do
		if p == other then
			return true
		end
		p = inst[p].parent
	end
	return false
end
function METHODS:IsAncestorOf(other)
	return METHODS.IsDescendantOf(other, self)
end
function METHODS:Destroy()
	local s = inst[self]
	if s.events.Destroying then
		s.events.Destroying:Fire()
	end
	for _, c in table.clone(s.children) do
		METHODS.Destroy(c)
	end
	setParent(self, s, nil)
	s.destroyed = true
end
function METHODS:ClearAllChildren()
	for _, c in table.clone(inst[self].children) do
		METHODS.Destroy(c)
	end
end
function METHODS:Clone()
	local s = inst[self]
	local c = Instance.new(s.className)
	local cs = inst[c]
	for k, v in s.props do
		if k ~= "Parent" then
			cs.props[k] = v
		end
	end
	for k, v in s.attrs do
		cs.attrs[k] = v
	end
	cs.file = s.file
	for _, ch in s.children do
		local cc = METHODS.Clone(ch)
		setParent(cc, inst[cc], c)
	end
	return c
end
function METHODS:GetPropertyChangedSignal(prop)
	local s = inst[self]
	s.propSignals[prop] = s.propSignals[prop] or Signal.new(prop)
	return s.propSignals[prop]
end
function METHODS:GetAttribute(name)
	return inst[self].attrs[name]
end
function METHODS:GetAttributes()
	return table.clone(inst[self].attrs)
end
function METHODS:SetAttribute(name, value)
	local s = inst[self]
	if s.attrs[name] == value then
		return
	end
	s.attrs[name] = value
	local sig = s.attrSignals[name]
	if sig then
		sig:Fire()
	end
	if s.events.AttributeChanged then
		s.events.AttributeChanged:Fire(name)
	end
end
function METHODS:GetAttributeChangedSignal(name)
	local s = inst[self]
	s.attrSignals[name] = s.attrSignals[name] or Signal.new(name)
	return s.attrSignals[name]
end
function METHODS:GetFullName()
	local parts = {}
	local x = self
	while x do
		table.insert(parts, 1, inst[x].props.Name)
		x = inst[x].parent
	end
	return table.concat(parts, ".")
end
function METHODS:AddTag(tag)
	inst[self].tags[tag] = true
end
function METHODS:RemoveTag(tag)
	inst[self].tags[tag] = nil
end
function METHODS:HasTag(tag)
	return inst[self].tags[tag] == true
end
function METHODS:GetTags()
	local out = {}
	for t in inst[self].tags do
		table.insert(out, t)
	end
	return out
end
-- Generic no-ops for things UI code calls on world objects.
local NOOPS = {
	"Play",
	"Stop",
	"Pause",
	"Resume",
	"Cancel",
	"FireServer",
	"FireAllClients",
	"FireClient",
	"Emit",
	"Clear",
	"PivotTo",
	"SetPrimaryPartCFrame",
	"MoveTo",
	"Move",
	"ScaleTo",
	"AdjustSpeed",
	"AdjustWeight",
	"ApplyImpulse",
	"SetNetworkOwner",
	"BreakJoints",
	"ChangeState",
	"SetStateEnabled",
	"TweenPosition",
	"TweenSize",
	"TweenSizeAndPosition",
	"CaptureFocus",
	"ReleaseFocus",
	"Kick",
	"LoadCharacter",
	"Preload",
	"PreloadAsync",
	"SetCore",
	"SetCoreGuiEnabled",
	"BindToRenderStep",
	"UnbindFromRenderStep",
	"SetCameraMode",
	"Connect",
	"ScrollToTop",
	"Fire",
	"Invoke",
	"PlayLocalSound",
}
for _, n in NOOPS do
	METHODS[n] = function() end
end
function METHODS:GetPivot()
	return CFrame.new()
end
function METHODS:GetBoundingBox()
	return CFrame.new(), Vector3.new(4, 4, 4)
end
function METHODS:GetExtentsSize()
	return Vector3.new(4, 4, 4)
end
function METHODS:GetScale()
	return 1
end
function METHODS:GetPlayingAnimationTracks()
	return {}
end
function METHODS:LoadAnimation()
	return Instance.new("AnimationTrack")
end
function METHODS:GetMarkerReachedSignal()
	return Signal.new()
end
function METHODS:InvokeServer(...)
	local s = inst[self]
	if R.onInvoke then
		return R.onInvoke(s.props.Name, ...)
	end
	return nil
end
function METHODS:GetTouchingParts()
	return {}
end
function METHODS:GetConnectedParts()
	return {}
end
function METHODS:GetMass()
	return 1
end
function METHODS:GetState()
	return Enum.HumanoidStateType.Running
end
function METHODS:GetPlayers()
	return { R.LocalPlayer }
end
function METHODS:GetPlayerFromCharacter()
	return nil
end
function METHODS:GetPlayerByUserId(id)
	if R.LocalPlayer and inst[R.LocalPlayer].props.UserId == id then
		return R.LocalPlayer
	end
	return nil
end
function METHODS:GetFriendsOnline()
	return {}
end
function METHODS:IsFriendsWith()
	return false
end
function METHODS:GetRankInGroup()
	return 0
end
function METHODS:IsInGroup()
	return false
end
function METHODS:GetJoinData()
	return {}
end
function METHODS:WorldToViewportPoint(p)
	return Vector3.new(640, 360, 10), true
end
METHODS.WorldToScreenPoint = METHODS.WorldToViewportPoint
function METHODS:ViewportPointToRay()
	return { Origin = Vector3.new(), Direction = Vector3.new(0, -1, 0) }
end
METHODS.ScreenPointToRay = METHODS.ViewportPointToRay
function METHODS:Raycast()
	return nil
end
function METHODS:GetPartBoundsInBox()
	return {}
end
function METHODS:GetPartBoundsInRadius()
	return {}
end
function METHODS:GetPartsInPart()
	return {}
end
function METHODS:GetServerTimeNow()
	return os.time() + now
end
function METHODS:GetMouse()
	return { X = 640, Y = 360, Hit = CFrame.new(), Target = nil, Icon = "" }
end
function METHODS:GetFocusedTextBox()
	return nil
end
function METHODS:GetLastInputType()
	return R.inputType or Enum.UserInputType.MouseButton1
end
function METHODS:GetConnectedGamepads()
	return {}
end
function METHODS:GetGamepadConnected()
	return false
end
function METHODS:IsKeyDown()
	return false
end
function METHODS:IsMouseButtonPressed()
	return false
end
function METHODS:GetMouseLocation()
	return Vector2.new(640, 360)
end
function METHODS:GetGuiObjectsAtPosition()
	return {}
end
function METHODS:GetGuiInset()
	return Vector2.new(0, 58), Vector2.new(0, 0)
end
function METHODS:GetProductInfo()
	return { Name = "Product", PriceInRobux = 49, Description = "" }
end
function METHODS:UserOwnsGamePassAsync()
	return false
end
function METHODS:PlayerOwnsAsset()
	return false
end
function METHODS:GetUserThumbnailAsync()
	return "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150", true
end
function METHODS:GetNameFromUserIdAsync()
	return "Player"
end
function METHODS:GetTextSize(text, size)
	return Vector2.new(#tostring(text) * size * 0.6, size)
end
function METHODS:GetTextBoundsAsync(params)
	return Vector2.new(#tostring(params.Text) * (params.Size or 14) * 0.6, params.Size or 14)
end
function METHODS:JSONEncode(v)
	return require("@lune/serde").encode("json", v)
end
function METHODS:JSONDecode(v)
	return require("@lune/serde").decode("json", v)
end
function METHODS:GenerateGUID()
	return "00000000-0000-0000-0000-000000000000"
end
function METHODS:IsStudio()
	return false
end
function METHODS:IsClient()
	return true
end
function METHODS:IsServer()
	return false
end
function METHODS:IsRunning()
	return true
end
function METHODS:IsRunMode()
	return false
end
function METHODS:GetTagged()
	return {}
end
function METHODS:GetInstanceAddedSignal()
	return Signal.new()
end
function METHODS:GetInstanceRemovedSignal()
	return Signal.new()
end
function METHODS:AddItem(obj, t)
	task.delay(t or 10, function()
		if not inst[obj].destroyed then
			METHODS.Destroy(obj)
		end
	end)
end
function METHODS:Create(obj, info, goals)
	-- TweenService:Create: a tween that jumps to its end when played.
	local t = Instance.new("Tween")
	local ts = inst[t]
	ts.tween = { obj = obj, goals = goals, info = info }
	return t
end
function METHODS:GetValue(alpha)
	return alpha
end
function METHODS:SetPartCollisionGroup() end
function METHODS:RegisterCollisionGroup() end
function METHODS:CollisionGroupSetCollidable() end
function METHODS:GetCharacterAppearanceAsync() end
function METHODS:SetPrimaryPartCFrame() end
function METHODS:Disconnect() end

local function makeTweenPlay(t)
	return function()
		local ts = inst[t]
		local tw = ts.tween
		if not tw then
			return
		end
		for k, v in tw.goals do
			tw.obj[k] = v
		end
		if ts.events.Completed then
			task.delay(tw.info and tw.info.Time or 0, function()
				ts.events.Completed:Fire(Enum.PlaybackState.Completed)
			end)
		end
	end
end

Imt.__index = function(self, key)
	local s = inst[self]
	if key == "Parent" then
		return s.parent
	elseif key == "ClassName" then
		return s.className
	end
	local v = s.props[key]
	if v ~= nil then
		return v
	end
	if s.className == "Tween" and key == "Play" then
		return makeTweenPlay(self)
	end
	local m = METHODS[key]
	if m then
		return m
	end
	if EVENTS[key] then
		s.events[key] = s.events[key] or Signal.new(key)
		return s.events[key]
	end
	-- children by name (instance.Child)
	for _, c in s.children do
		if inst[c].props.Name == key then
			return c
		end
	end
	if s.dynamic then
		return s.dynamic(key)
	end
	return nil
end

Imt.__newindex = function(self, key, value)
	local s = inst[self]
	if key == "Parent" then
		setParent(self, s, value)
		return
	end
	if s.props[key] == value then
		return
	end
	s.props[key] = value
	if key == "Name" and s.parent then
		local ps = inst[s.parent]
		local w = ps.childWaiters[value]
		if w then
			ps.childWaiters[value] = nil
			for _, co in w do
				resume(co, self)
			end
		end
	end
	propChanged(s, key)
end
Imt.__tostring = function(self)
	return inst[self].props.Name
end
Imt.__type = "Instance"

local created = 0
function Instance.new(className, parent)
	local self = setmetatable({}, Imt)
	created += 1
	local s = {
		className = className,
		props = { Name = className },
		children = {},
		parent = nil,
		events = {},
		propSignals = {},
		attrs = {},
		attrSignals = {},
		childWaiters = {},
		tags = {},
		order = created,
	}
	inst[self] = s
	for _, fam in CLASS_FAMILY[className] or {} do
		for k, v in DEFAULTS[fam] do
			s.props[k] = v
		end
	end
	for k, v in DEFAULTS[className] or {} do
		s.props[k] = v
	end
	if className == "TextButton" then
		s.props.Text = "Button"
	elseif className == "TextLabel" and false then
		s.props.Text = "Label"
	end
	if parent then
		setParent(self, s, parent)
	end
	return self
end
R.Instance = Instance

-------------------------------------------------------------------------- clock

function R.now()
	return now
end

-- Advances virtual time: deferred work, timers, Heartbeat/RenderStepped every frame.
function R.advance(seconds, step)
	step = step or 1 / 30
	local target = now + seconds
	while true do
		while #deferred > 0 do
			local d = table.remove(deferred, 1)
			resume(d.co, table.unpack(d.args, 1, d.args.n))
		end
		local due = {}
		for i = #timers, 1, -1 do
			if timers[i].at <= now then
				table.insert(due, 1, table.remove(timers, i))
			end
		end
		table.sort(due, function(a, b)
			return a.at < b.at
		end)
		for _, t in due do
			if coroutine.status(t.co) == "suspended" then
				resume(t.co, table.unpack(t.args, 1, t.args.n))
			end
		end
		if now >= target then
			break
		end
		now = math.min(target, now + step)
		if R.frame then
			R.frame(step)
		end
	end
end

-------------------------------------------------------------------------- require

local cache = {}
function R.makeRequire(env)
	local function req(module)
		if type(module) == "string" then
			error("string require not supported: " .. module)
		end
		local s = inst[module]
		if not s or not s.file then
			error("require: not a module " .. tostring(module))
		end
		if cache[module] ~= nil then
			return cache[module]
		end
		-- Sources are read at mount time: Lune's file reads yield to its own scheduler,
		-- which a coroutine run by our fake scheduler would never get back from.
		local src = s.source or fs.readFile(s.file)
		-- Lune copies only raw keys of an environment, so give each script a full copy.
		local scriptEnv = {}
		for k, v in env do
			scriptEnv[k] = v
		end
		scriptEnv.script = module
		local fn = luau.load(src, { debugName = s.file, environment = scriptEnv })
		local result = fn()
		cache[module] = result
		return result
	end
	return req
end

-- Builds instances for a folder on disk (Rojo rules: init.luau, *.luau ModuleScripts,
-- *.client.luau LocalScripts, folders).
function R.mountFolder(path, name, parent)
	local folder
	if fs.isFile(path .. "/init.luau") then
		folder = Instance.new("ModuleScript")
		inst[folder].file = path .. "/init.luau"
		inst[folder].source = fs.readFile(path .. "/init.luau")
	else
		folder = Instance.new("Folder")
	end
	folder.Name = name
	for _, entry in fs.readDir(path) do
		local full = path .. "/" .. entry
		if fs.isDir(full) then
			R.mountFolder(full, entry, folder)
		elseif entry ~= "init.luau" and entry:match("%.luau$") then
			local cls = "ModuleScript"
			local n = entry:gsub("%.luau$", "")
			if n:match("%.client$") then
				cls = "LocalScript"
				n = n:gsub("%.client$", "")
			elseif n:match("%.server$") then
				cls = "Script"
				n = n:gsub("%.server$", "")
			end
			local m = Instance.new(cls)
			m.Name = n
			inst[m].file = full
			inst[m].source = fs.readFile(full)
			m.Parent = folder
		end
	end
	folder.Parent = parent
	return folder
end

return R
