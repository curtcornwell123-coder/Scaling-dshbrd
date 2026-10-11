--!strict
-- Ball skins. Every ball is the same premium dimpled tour-ball mesh (Config.Ball.MeshIds)
-- with real ball printing (BallPrints): brand stamp, model line, play number, alignment
-- line or track, emblem and pinstripes. A skin picks the finish (gloss, foil, gem glass,
-- or a translucent shell over a glowing core), the print design and its effects.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BallPrints = require(script.Parent:WaitForChild("BallPrints"))
local Config = require(script.Parent:WaitForChild("Config"))

local Skins = {}

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

-- Optional per-skin print overrides; Skins.design fills in the rest from the rarity.
export type DesignSpec = {
	Pattern: string?,
	Brand: string?,
	Model: string?,
	Number: string?,
	SubNumber: string?,
	Ink: Color3?,
	Accent: Color3?,
	BrandFont: Enum.Font?,
	TextFont: Enum.Font?,
	Emblem: string?,
	Core: Color3?,
	Metallic: boolean?,
}

export type Skin = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Color: Color3,
	Material: Enum.Material,
	Reflect: number?, -- reflectance override (chrome)
	Pulse: Color3?, -- animate Color <-> Pulse on clients
	Rainbow: boolean?,
	Light: boolean?,
	Aura: Color3?, -- built-in particle aura (Epic+ get one automatically)
	AuraStyle: string?, -- "Sparkle" (default) | "Dawn" (exclusive day-14 rays + orbit sparks)
	Design: DesignSpec?,
	Source: string, -- "Starter" | "Shop" | "Featured" | "Token:<Minigame>" | "Ranked:<Tier>" | "Pass:<Id>" | "Creator" | "Achievement" | "Leaderboard:<Stat>" | "Group" | "Login" | "Limited"
	Order: number,
}

Skins.Rarities = {
	Common = { Order = 1, Color = Color3.fromHex("#9AA5B8"), Price = 300 },
	Rare = { Order = 2, Color = Color3.fromHex("#3D8BFF"), Price = 900 },
	Epic = { Order = 3, Color = Color3.fromHex("#B04DFF"), Price = 2500 },
	Legendary = { Order = 4, Color = Color3.fromHex("#FFC83D"), Price = 7000 },
	Mythic = { Order = 5, Color = Color3.fromHex("#FF2D55"), Price = 6000 }, -- value only; Mythics are never sold directly
} :: { [string]: { Order: number, Color: Color3, Price: number } }

Skins.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

-- Duplicates from crates refund this share of the rarity price.
Skins.DuplicateRefund = 0.35

local M = Enum.Material
local list: { Skin } = {}
local GOLD_INK = Color3.fromHex("#E2B95B")
local SILVER_INK = Color3.fromHex("#C9D1DC")
local hex = Color3.fromHex

local function add(id: string, name: string, rarity: Rarity, color: string, material: Enum.Material, source: string, extra: { [string]: any }?)
	local skin: any = {
		Id = id,
		Name = name,
		Rarity = rarity,
		Color = hex(color),
		Material = material,
		Source = source,
		Order = #list + 1,
	}
	if extra then
		for k, v in extra do
			skin[k] = v
		end
	end
	table.insert(list, skin :: Skin)
end

-- Glowing skins: a translucent tinted shell over a neon core (like a lit night ball).
local function glow(core: string, extra: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = extra or {}
	local design: DesignSpec = out.Design or {}
	design.Core = hex(core)
	out.Design = design
	return out
end

-- Starter + shop pool (Coin Shop cases, Basic & Premium crates) ------------------
add("classic_white", "Classic", "Common", "#F4F6FA", M.SmoothPlastic, "Starter", { Design = { Number = "1" } })
add("sunny", "Sunny", "Common", "#FFD93B", M.SmoothPlastic, "Shop")
add("mint", "Mint", "Common", "#7CF2B8", M.SmoothPlastic, "Shop")
add("coral", "Coral", "Common", "#FF7A6B", M.SmoothPlastic, "Shop")
add("sky", "Sky", "Common", "#6BC6FF", M.SmoothPlastic, "Shop")
add("grape", "Grape", "Common", "#A98BFF", M.SmoothPlastic, "Shop")
add("tangerine", "Tangerine", "Common", "#FF9A3C", M.SmoothPlastic, "Shop")
add("bubblegum", "Bubblegum", "Common", "#FF8BD1", M.SmoothPlastic, "Shop")
add("slate", "Slate", "Common", "#5B6478", M.SmoothPlastic, "Shop")
add("lime", "Lime", "Common", "#B5F53C", M.SmoothPlastic, "Shop")

add("chrome", "Chrome", "Rare", "#D5DCE8", M.Foil, "Shop", { Reflect = 0.42, Design = { Accent = hex("#1C2230") } })
add("ruby", "Ruby", "Rare", "#E0115F", M.Glass, "Shop", { Design = { Emblem = "◆" } })
add("emerald", "Emerald", "Rare", "#0FBF6B", M.Glass, "Shop", { Design = { Emblem = "◆" } })
add("sapphire", "Sapphire", "Rare", "#1F5BFF", M.Glass, "Shop", { Design = { Emblem = "◆", Accent = SILVER_INK } })
add("copper", "Copper", "Rare", "#D47A3C", M.Foil, "Shop", { Reflect = 0.28 })
add("arctic", "Arctic", "Rare", "#BFF3FF", M.Ice, "Shop", { Design = { Accent = hex("#2A6F97") } })
add("volt", "Volt", "Rare", "#E6FF00", M.Glass, "Shop", glow("#F1FF6B", { Light = true, Design = { Number = "220" } }))
add("obsidian", "Obsidian", "Rare", "#1A1A22", M.Glass, "Shop", { Design = { Accent = SILVER_INK } })

add("hot_neon", "Hot Neon", "Epic", "#FF00A0", M.Glass, "Shop", glow("#FF4FC0"))
add("cyber_cyan", "Cyber Cyan", "Epic", "#00E5FF", M.Glass, "Shop", glow("#7DF3FF", { Design = { TextFont = Enum.Font.Michroma } }))
add("toxic", "Toxic", "Epic", "#66FF00", M.Glass, "Shop", glow("#B6FF7A", { Aura = hex("#B6FF7A"), Design = { Pattern = "Hazard" } }))
add("magma", "Magma", "Epic", "#FF4A00", M.Glass, "Shop", glow("#FFB000", { Pulse = hex("#FFB000") }))
add("galaxy", "Galaxy", "Epic", "#3A1C71", M.Glass, "Shop", { Pulse = hex("#D76D77"), Aura = hex("#FFD1F0"), Design = { Pattern = "Stars", Accent = hex("#FFD1F0") } })
add("frostbite", "Frostbite", "Epic", "#A6F0FF", M.Glass, "Shop", { Aura = hex("#FFFFFF"), Design = { Accent = hex("#1F6F8B") } })

add("golden_ace", "Golden Ace", "Legendary", "#FFC83D", M.Foil, "Shop", { Light = true, Aura = hex("#FFE9A8"), Design = { Emblem = "♠", Number = "1" } })
add("plasma", "Plasma", "Legendary", "#7A00FF", M.Glass, "Shop", glow("#C07BFF", { Pulse = hex("#00E5FF"), Aura = hex("#B8F6FF") }))
add("prism", "Prism", "Legendary", "#FF0055", M.Glass, "Shop", glow("#FFFFFF", { Rainbow = true, Light = true, Design = { Ink = Color3.new(1, 1, 1) } }))
add("solar_flare", "Solar Flare", "Legendary", "#FF8A00", M.Glass, "Shop", glow("#FFD36B", { Aura = hex("#FFD36B"), Light = true, Design = { Emblem = "●" } }))

add("chaos_core", "Chaos Core", "Mythic", "#FF0033", M.Glass, "Shop", glow("#FF7A00", { Pulse = hex("#FF7A00"), Aura = hex("#FF4D4D"), Light = true }))
add("void_star", "Void Star", "Mythic", "#0A0014", M.Glass, "Shop", glow("#5B00B5", { Pulse = hex("#5B00B5"), Aura = hex("#C77DFF"), Light = true }))

-- Mythic Featured Crate exclusives -------------------------------------------
add("nebula", "Nebula", "Epic", "#5E2BFF", M.Glass, "Featured", { Pulse = hex("#FF4FD8"), Design = { Pattern = "Stars", Accent = hex("#FFB8F2") } })
add("eclipse", "Eclipse", "Legendary", "#101018", M.Foil, "Featured", { Aura = hex("#FFB347"), Light = true, Design = { Emblem = "●", Metallic = true } })
add("aurora", "Aurora", "Legendary", "#00FFC6", M.Glass, "Featured", glow("#C6FFF1", { Pulse = hex("#7A5CFF"), Aura = hex("#C6FFF1") }))
add("supernova", "Supernova", "Mythic", "#FFFFFF", M.Glass, "Featured", glow("#FFE36B", { Pulse = hex("#FFD000"), Aura = hex("#FFF3B0"), Light = true, Design = { Ink = hex("#8A5A00") } }))
add("phantom", "Phantom", "Mythic", "#B8C7FF", M.ForceField, "Featured", glow("#6A00FF", { Pulse = hex("#6A00FF"), Aura = hex("#D9C7FF"), Light = true }))

-- Practice-room token skins (Target / Drive / Hazard) ------------------------
add("dartboard", "Dartboard", "Common", "#F2E8CF", M.SmoothPlastic, "Token:Target", { Design = { Pattern = "Target", Number = "180", Accent = hex("#C1121F") } })
add("bullseye", "Bullseye", "Rare", "#E63946", M.SmoothPlastic, "Token:Target", { Light = true, Design = { Pattern = "Target", Number = "10", Emblem = "Target" } })
add("sharpshooter", "Sharpshooter", "Epic", "#FF3D3D", M.Glass, "Token:Target", glow("#FF9A9A", { Aura = hex("#FFB3B3"), Design = { Pattern = "Target", Emblem = "Target" } }))
add("deadeye", "Deadeye", "Legendary", "#FF0033", M.Glass, "Token:Target", glow("#FFFFFF", { Pulse = hex("#FFFFFF"), Light = true, Design = { Pattern = "Target", Emblem = "Target", Number = "1" } }))

add("tailwind", "Tailwind", "Common", "#A8DADC", M.SmoothPlastic, "Token:Drive", { Design = { Pattern = "Track", Accent = hex("#457B9D") } })
add("rocket", "Rocket", "Rare", "#457B9D", M.Foil, "Token:Drive", { Design = { Pattern = "Track", Emblem = "▲" } })
add("afterburner", "Afterburner", "Epic", "#FF7B00", M.Glass, "Token:Drive", glow("#FFC27A", { Aura = hex("#FFC27A"), Design = { Pattern = "Track" } }))
add("hypersonic", "Hypersonic", "Legendary", "#00B4FF", M.Glass, "Token:Drive", glow("#FFFFFF", { Pulse = hex("#FFFFFF"), Light = true, Design = { Pattern = "Track", Emblem = "▲", Number = "5" } }))

add("caution", "Caution", "Common", "#FFD60A", M.SmoothPlastic, "Token:Hazard", { Design = { Pattern = "Hazard" } })
add("hazard_stripe", "Hazard Stripe", "Rare", "#FFB703", M.Foil, "Token:Hazard", { Design = { Pattern = "Hazard" } })
add("daredevil", "Daredevil", "Epic", "#FB5607", M.Glass, "Token:Hazard", glow("#FFD0B0", { Aura = hex("#FFD0B0"), Design = { Pattern = "Hazard" } }))
add("untouchable", "Untouchable", "Legendary", "#8338EC", M.Glass, "Token:Hazard", { Pulse = hex("#3A86FF"), Light = true, Design = { Emblem = "◆" } })

add("rink", "Rink", "Common", "#E8F4FA", M.SmoothPlastic, "Token:Bank", { Design = { Pattern = "Pinstripe", Accent = hex("#2A6F97"), Number = "3" } })
add("slapshot", "Slapshot", "Rare", "#1B263B", M.SmoothPlastic, "Token:Bank", { Reflect = 0.1, Design = { Accent = hex("#5BC0EB"), Emblem = "◆" } })
add("glacier", "Glacier", "Epic", "#9AD1F5", M.Ice, "Token:Bank", { Aura = hex("#E0F7FF"), Design = { Pattern = "Track", Accent = hex("#1D5C86") } })
add("polar_crown", "Polar Crown", "Legendary", "#DDF3FF", M.Glass, "Token:Bank", glow("#FFFFFF", { Pulse = hex("#5BC0EB"), Light = true, Design = { Emblem = "★", Ink = hex("#1D5C86") } }))

add("sandstone", "Sandstone", "Common", "#D9A066", M.SmoothPlastic, "Token:Gates", { Design = { Accent = hex("#7A3E12") } })
add("mesa", "Mesa", "Rare", "#B5542C", M.SmoothPlastic, "Token:Gates", { Design = { Pattern = "Pinstripe", Accent = hex("#F2D0A4") } })
add("sidewinder", "Sidewinder", "Epic", "#C9A227", M.Foil, "Token:Gates", { Aura = hex("#FFE3A3"), Design = { Pattern = "Track", Emblem = "▲" } })
add("sun_temple", "Sun Temple", "Legendary", "#E07A2F", M.Glass, "Token:Gates", glow("#FFD36B", { Pulse = hex("#FFB000"), Light = true, Design = { Emblem = "●" } }))

-- Ranked tier rewards ----------------------------------------------------
add("rank_gold", "Gilded", "Rare", "#E8B021", M.Foil, "Ranked:Gold", { Design = { Brand = "RANKED", Emblem = "◆", Accent = hex("#5B3A00") } })
add("rank_diamond", "Diamond Cut", "Epic", "#9BE7FF", M.Glass, "Ranked:Diamond", { Light = true, Design = { Brand = "RANKED", Emblem = "◆" } })
add("rank_onyx", "Onyx", "Legendary", "#121212", M.Foil, "Ranked:Onyx", { Aura = hex("#8C8CFF"), Design = { Brand = "RANKED", Emblem = "◆", Metallic = true } })
add("rank_legend", "Chaos Legend", "Mythic", "#FF0066", M.Glass, "Ranked:Chaos Legend", glow("#FFFFFF", { Rainbow = true, Aura = hex("#FFFFFF"), Light = true, Design = { Brand = "RANKED", Ink = Color3.new(1, 1, 1) } }))

-- Passes, creator codes, achievements -----------------------------------------
add("vip_aurum", "VIP Aurum", "Legendary", "#FFD45E", M.Foil, "Pass:VIP", { Light = true, Aura = hex("#FFF0B8"), Design = { Number = "VIP" } })
add("founder", "Founder", "Epic", "#2B2D42", M.SmoothPlastic, "Pass:Founder", { Pulse = hex("#EF233C"), Reflect = 0.1, Design = { Number = "01", Accent = hex("#EF233C") } })
add(Config.CreatorFanSkin, "Creator Fan", "Rare", "#FF5CA8", M.SmoothPlastic, "Creator", { Light = true, Design = { Emblem = "♥" } })
add("rookie", "Rookie", "Common", "#7AE582", M.SmoothPlastic, "Achievement", { Design = { Number = "1" } })

-- 14-day login grand prize (exclusive, never in any crate) ------------------------
add("eternal_dawn", "Eternal Dawn", "Legendary", "#FFB547", M.Glass, "Login", glow("#FFE7A3", {
	Pulse = hex("#FF5E7E"),
	Aura = hex("#FFE7A3"),
	AuraStyle = "Dawn",
	Light = true,
	Design = { Number = "14" },
}))
add("ace", "Ace", "Epic", "#FFFFFF", M.Foil, "Achievement", { Aura = hex("#FFE066"), Light = true, Design = { Emblem = "♠", Number = "1" } })
add("kernel", "Kernel", "Epic", "#FFD447", M.SmoothPlastic, "Group", { Aura = hex("#FFE58A"), Design = { Brand = "CORNY", Accent = hex("#7A4E00") } })
-- Leaderboard balls: weekly top 3 on each board (see Config.Leaderboards.Rewards).
add("lb_champion", "Champion", "Legendary", "#F2C14E", M.Foil, "Leaderboard:Wins", { Aura = hex("#FFE08A"), Light = true, Design = { Emblem = "★", Number = "1" } })
add("lb_tycoon", "Tycoon", "Legendary", "#D7E3F4", M.Foil, "Leaderboard:Coins", { Aura = hex("#9FE8C2"), Design = { Emblem = "$", Number = "1", Accent = hex("#1F8A5B") } })
add("lb_saboteur", "Saboteur", "Legendary", "#B3122E", M.Glass, "Leaderboard:Sabotages", { Aura = hex("#FF4D6A"), Design = { Emblem = "×", Number = "1" } })

-- Limited edition: only Config.Limited.Stock ever exist, each printed with its serial.
add("corny_studio", "Corny Games Studio", "Mythic", "#0E0E12", M.SmoothPlastic, "Limited", {
	Reflect = 0.12,
	Aura = hex("#FFE08A"),
	Light = true,
	Design = {
		Pattern = "Pinstripe",
		Brand = "CORNY GAMES",
		Model = "STUDIO",
		Ink = GOLD_INK,
		Accent = GOLD_INK,
		Emblem = "★",
		Metallic = true,
	},
})

local byId: { [string]: Skin } = {}
for _, skin in list do
	assert(byId[skin.Id] == nil, "duplicate skin id " .. skin.Id)
	byId[skin.Id] = skin
end

Skins.List = list
Skins.ById = byId
Skins.Default = "classic_white"

function Skins.get(id: string?): Skin
	return (id and byId[id]) or byId[Skins.Default]
end

function Skins.price(id: string): number
	return Skins.Rarities[Skins.get(id).Rarity].Price
end

function Skins.refund(id: string): number
	return math.floor(Skins.price(id) * Skins.DuplicateRefund)
end

function Skins.withSource(source: string): { Skin }
	local out = {}
	for _, skin in list do
		if skin.Source == source then
			table.insert(out, skin)
		end
	end
	return out
end

-- Coin Shop rotation: a new set of balls every RotationSeconds, the same in every server.
-- Each set is balanced like a real pro shop: mostly Common/Rare, two Epics, one Legendary.
Skins.RotationSeconds = 600

function Skins.rotationSlot(now: number?): number
	return math.floor((now or os.time()) / Skins.RotationSeconds)
end

function Skins.rotationEndsIn(now: number?): number
	local t = now or os.time()
	return Skins.RotationSeconds - (t % Skins.RotationSeconds)
end

local QUOTA = { Common = 5, Rare = 4, Epic = 2, Legendary = 1 }

function Skins.shopRotation(slot: number, count: number): { Skin }
	local rng = Random.new(slot * 7919 + 17)
	local pools: { [string]: { Skin } } = {}
	for _, skin in list do
		if skin.Source == "Shop" and skin.Rarity ~= "Mythic" then
			pools[skin.Rarity] = pools[skin.Rarity] or {}
			table.insert(pools[skin.Rarity], skin)
		end
	end
	for _, pool in pools do
		for i = #pool, 2, -1 do
			local j = rng:NextInteger(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
	end
	local out: { Skin } = {}
	local scale = count / 12
	for _, r in Skins.RarityOrder do
		local pool = pools[r]
		local want = math.max(if QUOTA[r] then 1 else 0, math.floor((QUOTA[r] or 0) * scale + 0.5))
		while pool and want > 0 and #pool > 0 and #out < count do
			table.insert(out, table.remove(pool) :: Skin)
			want -= 1
		end
	end
	-- Top up from whatever is left if a pool ran short.
	for _, r in Skins.RarityOrder do
		local pool = pools[r]
		while pool and #pool > 0 and #out < count do
			table.insert(out, table.remove(pool) :: Skin)
		end
	end
	table.sort(out, function(a, b)
		local ra, rb = Skins.Rarities[a.Rarity].Order, Skins.Rarities[b.Rarity].Order
		if ra ~= rb then
			return ra < rb
		end
		return a.Order < b.Order
	end)
	return out
end

-- Print design --------------------------------------------------------------------

local INK_DARK = hex("#17191E")
local INK_LIGHT = hex("#F5F3EE")

local function luminance(c: Color3): number
	return 0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B
end

local function close(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.45
end

local PATTERN_BY_RARITY = { Common = "Classic", Rare = "Pinstripe", Epic = "Track", Legendary = "Halo", Mythic = "Stars" }

-- The full print design for a skin. `serial` (limited balls) is printed as the number.
function Skins.design(skin: Skin, serial: number?): BallPrints.Design
	local spec: DesignSpec = skin.Design or {}
	local order = Skins.Rarities[skin.Rarity].Order
	local dark = luminance(skin.Color) < 0.42
	local premium = order >= Skins.Rarities.Legendary.Order
	local ink = spec.Ink or (if dark then (if premium then GOLD_INK else INK_LIGHT) else INK_DARK)
	local accent = spec.Accent or skin.Pulse
	if not accent then
		if premium then
			accent = if close(skin.Color, GOLD_INK) then INK_DARK else GOLD_INK
		elseif order == 1 then
			accent = ink
		else
			accent = Skins.Rarities[skin.Rarity].Color
		end
	end
	if close(accent :: Color3, skin.Color) then
		accent = ink
	end
	local number = spec.Number
	if not number then
		number = if order <= 2 then tostring(skin.Order % 4 + 1) else tostring(skin.Order % 90 + 10)
	end
	local sub = spec.SubNumber
	if skin.Source == "Limited" then
		local cap = Config.Limited.Stock
		number = if serial then tostring(serial) else "LTD"
		sub = "OF " .. cap
	end
	return {
		Pattern = spec.Pattern or PATTERN_BY_RARITY[skin.Rarity] or "Classic",
		Brand = spec.Brand or "ULTIMATE",
		Model = spec.Model or string.upper(skin.Name),
		Number = number :: string,
		SubNumber = sub,
		Ink = ink,
		Accent = accent :: Color3,
		BrandFont = spec.BrandFont or Enum.Font.GothamBlack,
		TextFont = spec.TextFont or Enum.Font.GothamBold,
		Emblem = spec.Emblem or (if premium then "★" else nil),
		Core = spec.Core,
		Metallic = spec.Metallic or premium,
	}
end

-- Surface finish: (material, reflectance, transparency).
function Skins.finish(skin: Skin): (Enum.Material, number, number)
	local core = skin.Design and skin.Design.Core
	if core then
		if skin.Material == M.ForceField then
			return M.ForceField, 0, 0
		end
		return M.Glass, 0.06, 0.4
	end
	local m = skin.Material
	if m == M.Foil then
		return m, skin.Reflect or 0.22, 0
	elseif m == M.Glass then
		return m, skin.Reflect or 0.08, 0.1
	elseif m == M.SmoothPlastic then
		return m, skin.Reflect or 0.05, 0
	elseif m == M.Ice then
		return m, 0.04, 0.05
	end
	return m, skin.Reflect or 0, 0
end

-- Visuals ---------------------------------------------------------------

-- Makes `part` (a Ball-shaped Part) look like `skinId`. Safe to call repeatedly.
-- Pulse / Rainbow animation is done on clients by SkinFx (tag "SkinFx").
-- Rarer skins always carry built-in effects: Epic+ get an aura, Legendary+ glow.
function Skins.effects(skin: Skin): (Color3?, boolean)
	local order = Skins.Rarities[skin.Rarity].Order
	local aura = skin.Aura
	if not aura and order >= Skins.Rarities.Epic.Order then
		aura = (skin.Pulse or skin.Color):Lerp(Color3.new(1, 1, 1), 0.45)
	end
	local light = skin.Light == true or order >= Skins.Rarities.Legendary.Order
	return aura, light
end

-- Dimpled golf-ball look for every ball (match balls, shop displays, previews). BallService
-- loads whichever uploaded copy of the mesh this game may use and publishes its id and
-- native size; the mesh is then scaled to fit any ball size.
local DIMPLED = "DimpledBall"

local function meshInfo(): (string?, Vector3?)
	local id = ReplicatedStorage:GetAttribute("BallMeshId")
	local v = ReplicatedStorage:GetAttribute("BallMeshSize")
	if type(id) == "string" and id ~= "" and typeof(v) == "Vector3" and v.X > 0 then
		return id, v
	end
	return nil, nil
end

function Skins.fitMesh(part: BasePart)
	local id, native = meshInfo()
	if not id or not native then
		return
	end
	local mesh = part:FindFirstChild("DimpleMesh") :: SpecialMesh?
	if not mesh then
		local newMesh = Instance.new("SpecialMesh")
		newMesh.Name = "DimpleMesh"
		newMesh.MeshType = Enum.MeshType.FileMesh
		newMesh.Parent = part
		mesh = newMesh
	end
	local m = mesh :: SpecialMesh
	m.MeshId = id
	local d = math.min(part.Size.X, part.Size.Y, part.Size.Z)
	local n = native :: Vector3
	m.Scale = Vector3.new(d / n.X, d / n.Y, d / n.Z)
end

ReplicatedStorage:GetAttributeChangedSignal("BallMeshSize"):Connect(function()
	for _, inst in CollectionService:GetTagged(DIMPLED) do
		if inst:IsA("BasePart") then
			Skins.fitMesh(inst)
		end
	end
end)

-- `serial`: the owner's copy number on limited balls (printed on the back).
function Skins.apply(part: BasePart, skinId: string?, serial: number?)
	local skin = Skins.get(skinId)
	local auraColor, hasLight = Skins.effects(skin)
	local material, reflectance, transparency = Skins.finish(skin)
	part.Color = skin.Color
	part.Material = material
	part.Reflectance = reflectance
	part.Transparency = transparency
	part:SetAttribute("Skin", skin.Id)
	part:SetAttribute("SkinBase", skin.Color)
	part:SetAttribute("SkinPulse", skin.Pulse)
	part:SetAttribute("SkinRainbow", skin.Rainbow == true)

	CollectionService:AddTag(part, DIMPLED)
	Skins.fitMesh(part)

	-- Printing: rebuilt only when the skin, size or serial changes.
	local d = math.min(part.Size.X, part.Size.Y, part.Size.Z)
	local key = string.format("%s|%.3f|%s", skin.Id, d, tostring(serial or ""))
	if part:GetAttribute("PrintKey") ~= key then
		local old = part:FindFirstChild(BallPrints.FolderName)
		if old then
			old:Destroy()
		end
		BallPrints.build(part, Skins.design(skin, serial), d)
		part:SetAttribute("PrintKey", key)
	end

	local light = part:FindFirstChild("SkinLight") :: PointLight?
	if hasLight then
		if not light then
			local newLight = Instance.new("PointLight")
			newLight.Name = "SkinLight"
			newLight.Range = 7
			newLight.Brightness = 1.6
			newLight.Shadows = false
			newLight.Parent = part
			light = newLight
		end
		(light :: PointLight).Color = skin.Pulse or skin.Color
	elseif light then
		light:Destroy()
	end

	local aura = part:FindFirstChild("SkinAura") :: ParticleEmitter?
	if auraColor then
		if not aura then
			local e = Instance.new("ParticleEmitter")
			e.Name = "SkinAura"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.LightEmission = 1
			e.LightInfluence = 0
			e.Rate = 10
			e.Lifetime = NumberRange.new(0.5, 0.9)
			e.Speed = NumberRange.new(0.4, 1.2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Parent = part
			aura = e
		end
		local e = aura :: ParticleEmitter
		e.Color = ColorSequence.new(auraColor)
		e.Rate = if Skins.Rarities[skin.Rarity].Order >= Skins.Rarities.Legendary.Order then 16 else 10
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.25 * part.Size.X / Config.Ball.Diameter),
			NumberSequenceKeypoint.new(1, 0),
		})
	elseif aura then
		aura:Destroy()
	end

	-- Exclusive aura styles layer an extra emitter on top of the sparkles.
	local rays = part:FindFirstChild("SkinAuraRays") :: ParticleEmitter?
	if skin.AuraStyle == "Dawn" then
		if not rays then
			local e = Instance.new("ParticleEmitter")
			e.Name = "SkinAuraRays"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.LightEmission = 1
			e.LightInfluence = 0
			e.Rate = 6
			e.Lifetime = NumberRange.new(1.2, 1.6)
			e.Speed = NumberRange.new(0, 0)
			e.RotSpeed = NumberRange.new(-90, 90)
			e.Rotation = NumberRange.new(0, 360)
			e.LockedToPart = true
			e.Color = ColorSequence.new(Color3.fromHex("#FFE7A3"), Color3.fromHex("#FF5E7E"))
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.35),
				NumberSequenceKeypoint.new(1, 1),
			})
			e.Parent = part
			rays = e
		end
		(rays :: ParticleEmitter).Size = NumberSequence.new(1.6 * part.Size.X / Config.Ball.Diameter)
	elseif rays then
		rays:Destroy()
	end

	if skin.Pulse or skin.Rainbow then
		CollectionService:AddTag(part, "SkinFx")
	else
		CollectionService:RemoveTag(part, "SkinFx")
	end
end

return Skins
