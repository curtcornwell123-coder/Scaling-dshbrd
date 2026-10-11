--!strict
-- Ball skins. Every skin is the same dimpled golf-ball mesh (Config.Ball.MeshId);
-- a skin only changes colour, material, glow, pulse and aura.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent:WaitForChild("Config"))

local Skins = {}

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"

export type Skin = {
	Id: string,
	Name: string,
	Rarity: Rarity,
	Color: Color3,
	Material: Enum.Material,
	Pulse: Color3?, -- animate Color <-> Pulse on clients
	Rainbow: boolean?,
	Light: boolean?,
	Aura: Color3?, -- built-in particle aura (Epic+ get one automatically)
	AuraStyle: string?, -- "Sparkle" (default) | "Dawn" (exclusive day-14 rays + orbit sparks)
	Source: string, -- "Starter" | "Shop" | "Featured" | "Token:<Minigame>" | "Ranked:<Tier>" | "Pass:<Id>" | "Creator" | "Achievement"
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

local function add(id: string, name: string, rarity: Rarity, hex: string, material: Enum.Material, source: string, extra: { [string]: any }?)
	local skin: any = {
		Id = id,
		Name = name,
		Rarity = rarity,
		Color = Color3.fromHex(hex),
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

-- Starter + shop pool (Coin Shop pedestals, Basic & Premium crates) ---------
add("classic_white", "Classic", "Common", "#F4F6FA", M.SmoothPlastic, "Starter")
add("sunny", "Sunny", "Common", "#FFD93B", M.SmoothPlastic, "Shop")
add("mint", "Mint", "Common", "#7CF2B8", M.SmoothPlastic, "Shop")
add("coral", "Coral", "Common", "#FF7A6B", M.SmoothPlastic, "Shop")
add("sky", "Sky", "Common", "#6BC6FF", M.SmoothPlastic, "Shop")
add("grape", "Grape", "Common", "#A98BFF", M.SmoothPlastic, "Shop")
add("tangerine", "Tangerine", "Common", "#FF9A3C", M.SmoothPlastic, "Shop")
add("bubblegum", "Bubblegum", "Common", "#FF8BD1", M.SmoothPlastic, "Shop")
add("slate", "Slate", "Common", "#5B6478", M.SmoothPlastic, "Shop")
add("lime", "Lime", "Common", "#B5F53C", M.SmoothPlastic, "Shop")

add("chrome", "Chrome", "Rare", "#D5DCE8", M.Foil, "Shop")
add("ruby", "Ruby", "Rare", "#E0115F", M.Glass, "Shop")
add("emerald", "Emerald", "Rare", "#0FBF6B", M.Glass, "Shop")
add("sapphire", "Sapphire", "Rare", "#1F5BFF", M.Glass, "Shop")
add("copper", "Copper", "Rare", "#D47A3C", M.Foil, "Shop")
add("arctic", "Arctic", "Rare", "#BFF3FF", M.Ice, "Shop")
add("volt", "Volt", "Rare", "#E6FF00", M.SmoothPlastic, "Shop", { Light = true })
add("obsidian", "Obsidian", "Rare", "#1A1A22", M.Glass, "Shop")

add("hot_neon", "Hot Neon", "Epic", "#FF00A0", M.Neon, "Shop")
add("cyber_cyan", "Cyber Cyan", "Epic", "#00E5FF", M.Neon, "Shop")
add("toxic", "Toxic", "Epic", "#66FF00", M.Neon, "Shop", { Aura = Color3.fromHex("#B6FF7A") })
add("magma", "Magma", "Epic", "#FF4A00", M.Neon, "Shop", { Pulse = Color3.fromHex("#FFB000") })
add("galaxy", "Galaxy", "Epic", "#3A1C71", M.Glass, "Shop", { Pulse = Color3.fromHex("#D76D77"), Aura = Color3.fromHex("#FFD1F0") })
add("frostbite", "Frostbite", "Epic", "#A6F0FF", M.Glass, "Shop", { Aura = Color3.fromHex("#FFFFFF") })

add("golden_ace", "Golden Ace", "Legendary", "#FFC83D", M.Foil, "Shop", { Light = true, Aura = Color3.fromHex("#FFE9A8") })
add("plasma", "Plasma", "Legendary", "#7A00FF", M.Neon, "Shop", { Pulse = Color3.fromHex("#00E5FF"), Aura = Color3.fromHex("#B8F6FF") })
add("prism", "Prism", "Legendary", "#FF0055", M.Neon, "Shop", { Rainbow = true, Light = true })
add("solar_flare", "Solar Flare", "Legendary", "#FF8A00", M.Neon, "Shop", { Aura = Color3.fromHex("#FFD36B"), Light = true })

add("chaos_core", "Chaos Core", "Mythic", "#FF0033", M.Neon, "Shop", { Pulse = Color3.fromHex("#FF7A00"), Aura = Color3.fromHex("#FF4D4D"), Light = true })
add("void_star", "Void Star", "Mythic", "#0A0014", M.Glass, "Shop", { Pulse = Color3.fromHex("#5B00B5"), Aura = Color3.fromHex("#C77DFF"), Light = true })

-- Mythic Featured Crate exclusives -------------------------------------------
add("nebula", "Nebula", "Epic", "#5E2BFF", M.Glass, "Featured", { Pulse = Color3.fromHex("#FF4FD8") })
add("eclipse", "Eclipse", "Legendary", "#101018", M.Foil, "Featured", { Aura = Color3.fromHex("#FFB347"), Light = true })
add("aurora", "Aurora", "Legendary", "#00FFC6", M.Neon, "Featured", { Pulse = Color3.fromHex("#7A5CFF"), Aura = Color3.fromHex("#C6FFF1") })
add("supernova", "Supernova", "Mythic", "#FFFFFF", M.Neon, "Featured", { Pulse = Color3.fromHex("#FFD000"), Aura = Color3.fromHex("#FFF3B0"), Light = true })
add("phantom", "Phantom", "Mythic", "#B8C7FF", M.ForceField, "Featured", { Pulse = Color3.fromHex("#6A00FF"), Aura = Color3.fromHex("#D9C7FF"), Light = true })

-- Practice-room token skins (Target / Drive / Hazard) ------------------------
add("dartboard", "Dartboard", "Common", "#F2E8CF", M.SmoothPlastic, "Token:Target")
add("bullseye", "Bullseye", "Rare", "#E63946", M.SmoothPlastic, "Token:Target", { Light = true })
add("sharpshooter", "Sharpshooter", "Epic", "#FF3D3D", M.Neon, "Token:Target", { Aura = Color3.fromHex("#FFB3B3") })
add("deadeye", "Deadeye", "Legendary", "#FF0033", M.Neon, "Token:Target", { Pulse = Color3.fromHex("#FFFFFF"), Light = true })

add("tailwind", "Tailwind", "Common", "#A8DADC", M.SmoothPlastic, "Token:Drive")
add("rocket", "Rocket", "Rare", "#457B9D", M.Foil, "Token:Drive")
add("afterburner", "Afterburner", "Epic", "#FF7B00", M.Neon, "Token:Drive", { Aura = Color3.fromHex("#FFC27A") })
add("hypersonic", "Hypersonic", "Legendary", "#00B4FF", M.Neon, "Token:Drive", { Pulse = Color3.fromHex("#FFFFFF"), Light = true })

add("caution", "Caution", "Common", "#FFD60A", M.SmoothPlastic, "Token:Hazard")
add("hazard_stripe", "Hazard Stripe", "Rare", "#FFB703", M.Foil, "Token:Hazard")
add("daredevil", "Daredevil", "Epic", "#FB5607", M.Neon, "Token:Hazard", { Aura = Color3.fromHex("#FFD0B0") })
add("untouchable", "Untouchable", "Legendary", "#8338EC", M.Glass, "Token:Hazard", { Pulse = Color3.fromHex("#3A86FF"), Light = true })

-- Ranked tier rewards ----------------------------------------------------
add("rank_gold", "Gilded", "Rare", "#E8B021", M.Foil, "Ranked:Gold")
add("rank_diamond", "Diamond Cut", "Epic", "#9BE7FF", M.Glass, "Ranked:Diamond", { Light = true })
add("rank_onyx", "Onyx", "Legendary", "#121212", M.Foil, "Ranked:Onyx", { Aura = Color3.fromHex("#8C8CFF") })
add("rank_legend", "Chaos Legend", "Mythic", "#FF0066", M.Neon, "Ranked:Chaos Legend", { Rainbow = true, Aura = Color3.fromHex("#FFFFFF"), Light = true })

-- Passes, creator codes, achievements -----------------------------------------
add("vip_aurum", "VIP Aurum", "Legendary", "#FFD45E", M.Foil, "Pass:VIP", { Light = true, Aura = Color3.fromHex("#FFF0B8") })
add("founder", "Founder", "Epic", "#2B2D42", M.SmoothPlastic, "Pass:Founder", { Pulse = Color3.fromHex("#EF233C") })
add(Config.CreatorFanSkin, "Creator Fan", "Rare", "#FF5CA8", M.SmoothPlastic, "Creator", { Light = true })
add("rookie", "Rookie", "Common", "#7AE582", M.SmoothPlastic, "Achievement")

-- 14-day login grand prize (exclusive, never in any crate) ------------------------
add("eternal_dawn", "Eternal Dawn", "Legendary", "#FFB547", M.Neon, "Login", {
	Pulse = Color3.fromHex("#FF5E7E"),
	Aura = Color3.fromHex("#FFE7A3"),
	AuraStyle = "Dawn",
	Light = true,
})
add("ace", "Ace", "Epic", "#FFFFFF", M.Foil, "Achievement", { Aura = Color3.fromHex("#FFE066"), Light = true })

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

-- Coin Shop rotation: 12 skins a day, the same in every server.
function Skins.shopRotation(day: number, count: number): { Skin }
	local pool = {}
	for _, skin in list do
		if skin.Source == "Shop" and skin.Rarity ~= "Mythic" then
			table.insert(pool, skin)
		end
	end
	local rng = Random.new(day * 7919 + 17)
	for i = #pool, 2, -1 do
		local j = rng:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local out = {}
	for i = 1, math.min(count, #pool) do
		out[i] = pool[i]
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

function Skins.apply(part: BasePart, skinId: string?)
	local skin = Skins.get(skinId)
	local auraColor, hasLight = Skins.effects(skin)
	part.Color = skin.Color
	part.Material = skin.Material
	part.Reflectance = if skin.Material == Enum.Material.Foil then 0.15 else 0
	part.Transparency = if skin.Material == Enum.Material.Glass then 0.15 else 0
	part:SetAttribute("Skin", skin.Id)
	part:SetAttribute("SkinBase", skin.Color)
	part:SetAttribute("SkinPulse", skin.Pulse)
	part:SetAttribute("SkinRainbow", skin.Rainbow == true)

	local mesh = part:FindFirstChild("DimpleMesh") :: SpecialMesh?
	if Config.Ball.MeshId ~= "" then
		if not mesh then
			local newMesh = Instance.new("SpecialMesh")
			newMesh.Name = "DimpleMesh"
			newMesh.MeshType = Enum.MeshType.FileMesh
			newMesh.MeshId = Config.Ball.MeshId
			newMesh.Parent = part
			mesh = newMesh
		end
		local m = mesh :: SpecialMesh
		m.Scale = Config.Ball.MeshScale * (part.Size.X / Config.Ball.Diameter)
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
