-- Minimal Roblox stubs so pure shared modules can run in the standalone Luau VM.
local ROOT = "/home/user/Scaling-dshbrd/chaos-golf/src/shared/"
local cache = {}

local function anyIndex()
	local t = {}
	return setmetatable(t, { __index = function(_, k) return k end })
end
Enum = setmetatable({}, { __index = function(_, k) return anyIndex() end })

local function color(r, g, b)
	local c = { R = r, G = g, B = b }
	function c:Lerp(o, t) return color(r + (o.R - r) * t, g + (o.G - g) * t, b + (o.B - b) * t) end
	function c:ToHex() return "ffffff" end
	return c
end
Color3 = {
	new = color,
	fromRGB = function(r, g, b) return color(r / 255, g / 255, b / 255) end,
	fromHex = function(h) h = h:gsub("#", ""); return color(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255) end,
	fromHSV = function() return color(1, 1, 1) end,
}
Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end, one = {}, zero = {}, xAxis = {}, yAxis = {}, zAxis = {} }
UDim = { new = function() return {} end }
UDim2 = { new = function() return {} end, fromOffset = function() return {} end, fromScale = function() return {} end }
Vector2 = { new = function() return {} end }
TweenInfo = { new = function() return {} end }

Random = {}
function Random.new(seed)
	local state = (seed or os.time()) % 2147483647
	if state <= 0 then state = state + 2147483646 end
	local r = {}
	local function nxt()
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	function r:NextNumber() return nxt() end
	function r:NextInteger(a, b) return a + math.floor(nxt() * (b - a + 1)) end
	return r
end

game = { GetService = function(_, name) return setmetatable({}, { __index = function() return function() end end }) end }

local function handle(name)
	return { __module = name, WaitForChild = function(self, child) return handle(child) end, Parent = nil }
end
script = { Parent = { WaitForChild = function(_, name) return handle(name) end } }

local realRequire = require
function require(h)
	if type(h) == "table" and h.__module then
		local name = h.__module
		if cache[name] then return cache[name] end
		local f = io and io.open and io.open(ROOT .. name .. ".luau")
		error("no io")
	end
	return realRequire(h)
end
return nil
