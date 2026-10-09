--!strict
-- Shared game configuration: rarities, brainrots, conveyor odds, bases,
-- rebirths and monetization. Server and client both read this file.

local Config = {}

export type RarityId = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret" | "Celestial" | "EventSpecial"

export type Rarity = {
	Id: RarityId,
	DisplayName: string,
	Color: Color3,
	Order: number,
	Scale: number, -- model size multiplier
	SpawnWeight: number, -- relative chance to appear on the conveyor
	Announce: boolean, -- tell the whole server when one spawns
	EventOnly: boolean?, -- only on the conveyor during admin abuse
}

export type Brainrot = {
	Id: string,
	DisplayName: string,
	Rarity: RarityId,
	Price: number,
	Income: number, -- cash per second while sitting in your base
	Color: Color3,
	Accent: Color3,
	IncomeGrowth: number?, -- income multiplies by this for every rebirth the owner has
	Scale: number?, -- model size override (otherwise the rarity's size)
	Limited: boolean?, -- sold for Robux in limited numbers: can't be stolen or sold, kept on rebirth
}

-- Limited Robux brainrots. Stock is shared by every server (saved in a
-- DataStore), one per player, and each copy gets a serial number.
export type LimitedItem = {
	ProductId: number, -- developer product (0 = none)
	GamePassId: number?, -- or a gamepass (one per player); either puts her on sale
	PriceRobux: number, -- shown in the shop; the real price is set on the product
	Stock: number, -- copies for sale
	Reserved: number, -- extra copies Corny can still give once the shop stock is gone
}

export type GamePass = {
	Key: string,
	Id: number, -- paste your gamepass ID here (0 = not set up yet)
	Name: string,
	Description: string,
}

export type Product = {
	Key: string,
	Id: number, -- paste your developer product ID here (0 = not set up yet)
	Name: string,
	Description: string,
}

Config.GameName = "Brainrot Heist"
-- When a server closes for an update, how long everyone sees the "GAME
-- UPDATING!" screen before being sent off (progress saves meanwhile).
Config.UpdateNoticeSeconds = 7

local rarityOrder: { RarityId } = { "Common", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Celestial", "EventSpecial" }
Config.RarityOrder = rarityOrder

Config.Rarities = {
	Common = { Id = "Common", DisplayName = "Common", Color = Color3.fromRGB(70, 200, 90), Order = 1, Scale = 1, SpawnWeight = 60, Announce = false },
	Rare = { Id = "Rare", DisplayName = "Rare", Color = Color3.fromRGB(60, 140, 255), Order = 2, Scale = 1.15, SpawnWeight = 25, Announce = false },
	Epic = { Id = "Epic", DisplayName = "Epic", Color = Color3.fromRGB(170, 80, 255), Order = 3, Scale = 1.3, SpawnWeight = 10, Announce = false },
	Legendary = { Id = "Legendary", DisplayName = "Legendary", Color = Color3.fromRGB(255, 195, 40), Order = 4, Scale = 1.5, SpawnWeight = 4, Announce = true },
	Mythic = { Id = "Mythic", DisplayName = "Mythic", Color = Color3.fromRGB(255, 45, 60), Order = 5, Scale = 1.75, SpawnWeight = 0.9, Announce = true },
	Secret = { Id = "Secret", DisplayName = "Secret", Color = Color3.fromRGB(20, 20, 20), Order = 6, Scale = 2, SpawnWeight = 0.1, Announce = true },
	-- Celestial: above Secret, the rarest thing the conveyor can bring (about
	-- 1 in 4,000 spawns). They wear a ring of golden stars over their heads.
	Celestial = { Id = "Celestial", DisplayName = "Celestial", Color = Color3.fromRGB(120, 225, 255), Order = 7, Scale = 2, SpawnWeight = 0.025, Announce = true },
	-- Event Special: never on the conveyor. Set SpawnWeight above 0 to let
	-- non-limited Event Specials roll on the conveyor during admin abuse.
	EventSpecial = { Id = "EventSpecial", DisplayName = "Event Special", Color = Color3.fromRGB(255, 70, 190), Order = 8, Scale = 1.5, SpawnWeight = 0, Announce = true, EventOnly = true },
} :: { [RarityId]: Rarity }

-- Original characters. Add new ones here every update to keep players coming back.
Config.Brainrots = {
	-- Free: rides the conveyor like any Common, and anyone can take one for $0
	-- to start earning.
	{ Id = "PatatinoPiccolino", DisplayName = "Patatino Piccolino", Rarity = "Common", Price = 0, Income = 1, Color = Color3.fromRGB(205, 155, 95), Accent = Color3.fromRGB(90, 190, 70) },
	-- Common
	{ Id = "NoodloDoodlo", DisplayName = "Noodlo Doodlo", Rarity = "Common", Price = 25, Income = 1, Color = Color3.fromRGB(245, 215, 120), Accent = Color3.fromRGB(200, 60, 40) },
	{ Id = "PizzarinoPizzaroni", DisplayName = "Pizzarino Pizzaroni", Rarity = "Common", Price = 50, Income = 2, Color = Color3.fromRGB(240, 170, 60), Accent = Color3.fromRGB(190, 30, 30) },
	{ Id = "SockGobblino", DisplayName = "Sock Gobblino", Rarity = "Common", Price = 80, Income = 3, Color = Color3.fromRGB(230, 230, 230), Accent = Color3.fromRGB(60, 160, 220) },
	{ Id = "FrigoBurrito", DisplayName = "Frigo Burrito", Rarity = "Common", Price = 120, Income = 4, Color = Color3.fromRGB(200, 160, 110), Accent = Color3.fromRGB(120, 200, 255) },
	{ Id = "BubblegummoBlobbo", DisplayName = "Bubblegummo Blobbo", Rarity = "Common", Price = 150, Income = 5, Color = Color3.fromRGB(255, 140, 200), Accent = Color3.fromRGB(255, 205, 235) },
	{ Id = "CipollinoPiangino", DisplayName = "Cipollino Piangino", Rarity = "Common", Price = 30, Income = 1, Color = Color3.fromRGB(235, 205, 235), Accent = Color3.fromRGB(110, 190, 80) },
	{ Id = "CarotinoCorridore", DisplayName = "Carotino Corridore", Rarity = "Common", Price = 40, Income = 2, Color = Color3.fromRGB(255, 140, 40), Accent = Color3.fromRGB(80, 190, 70) },
	{ Id = "PomodorinoRimbalzo", DisplayName = "Pomodorino Rimbalzo", Rarity = "Common", Price = 60, Income = 2, Color = Color3.fromRGB(230, 50, 40), Accent = Color3.fromRGB(70, 170, 60) },
	{ Id = "BiscottinoBallerino", DisplayName = "Biscottino Ballerino", Rarity = "Common", Price = 70, Income = 3, Color = Color3.fromRGB(215, 165, 100), Accent = Color3.fromRGB(90, 50, 30) },
	{ Id = "FungoFunghetto", DisplayName = "Fungo Funghetto", Rarity = "Common", Price = 100, Income = 4, Color = Color3.fromRGB(220, 50, 50), Accent = Color3.fromRGB(245, 235, 215) },
	{ Id = "UovoSbadiglio", DisplayName = "Uovo Sbadiglio", Rarity = "Common", Price = 130, Income = 5, Color = Color3.fromRGB(250, 245, 235), Accent = Color3.fromRGB(255, 200, 60) },
	{ Id = "PeperonePiccante", DisplayName = "Peperone Piccante", Rarity = "Common", Price = 180, Income = 7, Color = Color3.fromRGB(220, 30, 30), Accent = Color3.fromRGB(60, 150, 50) },
	{ Id = "CuscinettoRonfone", DisplayName = "Cuscinetto Ronfone", Rarity = "Common", Price = 220, Income = 8, Color = Color3.fromRGB(190, 170, 240), Accent = Color3.fromRGB(150, 200, 255) },
	{ Id = "LiriliLarila", DisplayName = "Lirilì Larilà", Rarity = "Common", Price = 35, Income = 1, Color = Color3.fromRGB(90, 165, 80), Accent = Color3.fromRGB(165, 165, 175) },
	{ Id = "TimCheese", DisplayName = "Tim Cheese", Rarity = "Common", Price = 55, Income = 2, Color = Color3.fromRGB(255, 210, 80), Accent = Color3.fromRGB(255, 150, 170) },
	{ Id = "PipiKiwi", DisplayName = "Pipi Kiwi", Rarity = "Common", Price = 85, Income = 3, Color = Color3.fromRGB(140, 100, 60), Accent = Color3.fromRGB(130, 200, 70) },
	{ Id = "TalpaDiFerro", DisplayName = "Talpa di Ferro", Rarity = "Common", Price = 110, Income = 4, Color = Color3.fromRGB(115, 115, 125), Accent = Color3.fromRGB(255, 150, 40) },
	{ Id = "SvininoBombondino", DisplayName = "Svinino Bombondino", Rarity = "Common", Price = 200, Income = 7, Color = Color3.fromRGB(35, 35, 42), Accent = Color3.fromRGB(255, 160, 180) },
	-- Rare
	{ Id = "BananitoBandito", DisplayName = "Bananito Bandito", Rarity = "Rare", Price = 500, Income = 10, Color = Color3.fromRGB(255, 225, 50), Accent = Color3.fromRGB(30, 30, 30) },
	{ Id = "CroissantoFurioso", DisplayName = "Croissanto Furioso", Rarity = "Rare", Price = 900, Income = 16, Color = Color3.fromRGB(215, 150, 70), Accent = Color3.fromRGB(255, 80, 40) },
	{ Id = "TireinaFrogiva", DisplayName = "Tireina Frogiva", Rarity = "Rare", Price = 1200, Income = 20, Color = Color3.fromRGB(80, 170, 60), Accent = Color3.fromRGB(235, 200, 60) },
	{ Id = "TostinoTurbino", DisplayName = "Tostino Turbino", Rarity = "Rare", Price = 1500, Income = 25, Color = Color3.fromRGB(190, 120, 60), Accent = Color3.fromRGB(80, 80, 90) },
	{ Id = "GelatinoGigante", DisplayName = "Gelatino Gigante", Rarity = "Rare", Price = 2000, Income = 32, Color = Color3.fromRGB(150, 230, 190), Accent = Color3.fromRGB(110, 60, 40) },
	{ Id = "PretzelinoAnnodato", DisplayName = "Pretzelino Annodato", Rarity = "Rare", Price = 400, Income = 8, Color = Color3.fromRGB(180, 110, 50), Accent = Color3.fromRGB(250, 250, 250) },
	{ Id = "MelanzanaMafiosa", DisplayName = "Melanzana Mafiosa", Rarity = "Rare", Price = 650, Income = 12, Color = Color3.fromRGB(100, 40, 130), Accent = Color3.fromRGB(25, 25, 30) },
	{ Id = "AvocadinoPalestrato", DisplayName = "Avocadino Palestrato", Rarity = "Rare", Price = 1000, Income = 18, Color = Color3.fromRGB(60, 110, 40), Accent = Color3.fromRGB(200, 230, 120) },
	{ Id = "AnanassoSurfista", DisplayName = "Ananasso Surfista", Rarity = "Rare", Price = 1300, Income = 22, Color = Color3.fromRGB(240, 200, 60), Accent = Color3.fromRGB(40, 200, 200) },
	{ Id = "LumaconeTurbo", DisplayName = "Lumacone Turbo", Rarity = "Rare", Price = 1800, Income = 30, Color = Color3.fromRGB(150, 200, 110), Accent = Color3.fromRGB(230, 120, 40) },
	{ Id = "PolpettoOttopodo", DisplayName = "Polpetto Ottopodo", Rarity = "Rare", Price = 2400, Income = 38, Color = Color3.fromRGB(220, 110, 190), Accent = Color3.fromRGB(255, 190, 230) },
	{ Id = "ZucchinoZombie", DisplayName = "Zucchino Zombie", Rarity = "Rare", Price = 2800, Income = 44, Color = Color3.fromRGB(90, 140, 60), Accent = Color3.fromRGB(220, 215, 195) },
	{ Id = "FragolinaNinja", DisplayName = "Fragolina Ninja", Rarity = "Rare", Price = 3300, Income = 50, Color = Color3.fromRGB(230, 40, 60), Accent = Color3.fromRGB(25, 25, 30) },
	{ Id = "TrippiTroppi", DisplayName = "Trippi Troppi", Rarity = "Rare", Price = 450, Income = 9, Color = Color3.fromRGB(255, 130, 100), Accent = Color3.fromRGB(240, 160, 70) },
	{ Id = "BanditoBobritto", DisplayName = "Bandito Bobritto", Rarity = "Rare", Price = 800, Income = 15, Color = Color3.fromRGB(150, 95, 55), Accent = Color3.fromRGB(35, 35, 40) },
	{ Id = "CactoHipopotamo", DisplayName = "Cacto Hipopotamo", Rarity = "Rare", Price = 1100, Income = 19, Color = Color3.fromRGB(100, 170, 90), Accent = Color3.fromRGB(255, 110, 160) },
	{ Id = "TaTaTaSahur", DisplayName = "Ta Ta Ta Sahur", Rarity = "Rare", Price = 1600, Income = 27, Color = Color3.fromRGB(170, 190, 210), Accent = Color3.fromRGB(40, 40, 48) },
	{ Id = "PerochelloLemonchello", DisplayName = "Perochello Lemonchello", Rarity = "Rare", Price = 2200, Income = 36, Color = Color3.fromRGB(255, 230, 70), Accent = Color3.fromRGB(70, 190, 80) },
	{ Id = "BrrBrrPatapim", DisplayName = "Brr Brr Patapim", Rarity = "Rare", Price = 3000, Income = 46, Color = Color3.fromRGB(140, 95, 60), Accent = Color3.fromRGB(90, 180, 70) },
	-- Epic
	{ Id = "CactussoBossino", DisplayName = "Cactusso Bossino", Rarity = "Epic", Price = 5000, Income = 60, Color = Color3.fromRGB(60, 170, 70), Accent = Color3.fromRGB(255, 120, 200) },
	{ Id = "WaffelinoWizardo", DisplayName = "Waffelino Wizardo", Rarity = "Epic", Price = 9000, Income = 100, Color = Color3.fromRGB(230, 180, 90), Accent = Color3.fromRGB(90, 50, 200) },
	{ Id = "SixSeven", DisplayName = "67", Rarity = "Epic", Price = 6700, Income = 67, Color = Color3.fromRGB(40, 110, 230), Accent = Color3.fromRGB(245, 245, 250) },
	{ Id = "GnocchiNinjaro", DisplayName = "Gnocchi Ninjaro", Rarity = "Epic", Price = 15000, Income = 150, Color = Color3.fromRGB(250, 240, 200), Accent = Color3.fromRGB(20, 20, 30) },
	{ Id = "DonuttoDynamo", DisplayName = "Donutto Dynamo", Rarity = "Epic", Price = 25000, Income = 220, Color = Color3.fromRGB(255, 120, 180), Accent = Color3.fromRGB(90, 220, 255) },
	{ Id = "GelatoVulcano", DisplayName = "Gelato Vulcano", Rarity = "Epic", Price = 7500, Income = 80, Color = Color3.fromRGB(120, 70, 45), Accent = Color3.fromRGB(255, 90, 140) },
	{ Id = "PandaBambucco", DisplayName = "Panda Bambucco", Rarity = "Epic", Price = 11000, Income = 115, Color = Color3.fromRGB(245, 245, 245), Accent = Color3.fromRGB(30, 30, 35) },
	{ Id = "RoboMoka", DisplayName = "Robo Moka", Rarity = "Epic", Price = 18000, Income = 170, Color = Color3.fromRGB(190, 190, 200), Accent = Color3.fromRGB(30, 30, 35) },
	{ Id = "CoccoBello", DisplayName = "Cocco Bello", Rarity = "Epic", Price = 22000, Income = 200, Color = Color3.fromRGB(120, 80, 50), Accent = Color3.fromRGB(250, 248, 240) },
	{ Id = "Spaghettosauro", DisplayName = "Spaghettosauro", Rarity = "Epic", Price = 28000, Income = 250, Color = Color3.fromRGB(245, 210, 110), Accent = Color3.fromRGB(200, 40, 35) },
	{ Id = "FenicotteroFlamenco", DisplayName = "Fenicottero Flamenco", Rarity = "Epic", Price = 32000, Income = 280, Color = Color3.fromRGB(255, 130, 170), Accent = Color3.fromRGB(210, 30, 50) },
	{ Id = "GufoProfessore", DisplayName = "Gufo Professore", Rarity = "Epic", Price = 40000, Income = 340, Color = Color3.fromRGB(140, 100, 70), Accent = Color3.fromRGB(240, 225, 190) },
	{ Id = "CappuccinoAssassino", DisplayName = "Cappuccino Assassino", Rarity = "Epic", Price = 6000, Income = 62, Color = Color3.fromRGB(250, 248, 245), Accent = Color3.fromRGB(140, 90, 55) },
	{ Id = "BrriBrriBicus", DisplayName = "Brri Brri Bicus Dicus Bombicus", Rarity = "Epic", Price = 8000, Income = 85, Color = Color3.fromRGB(120, 170, 230), Accent = Color3.fromRGB(240, 190, 60) },
	{ Id = "TrulimeroTrulicina", DisplayName = "Trulimero Trulicina", Rarity = "Epic", Price = 13000, Income = 130, Color = Color3.fromRGB(110, 160, 220), Accent = Color3.fromRGB(255, 140, 80) },
	{ Id = "ChimpanziniBananini", DisplayName = "Chimpanzini Bananini", Rarity = "Epic", Price = 16000, Income = 160, Color = Color3.fromRGB(255, 225, 70), Accent = Color3.fromRGB(120, 85, 55) },
	{ Id = "SalaminoPenguino", DisplayName = "Salamino Penguino", Rarity = "Epic", Price = 26000, Income = 230, Color = Color3.fromRGB(190, 60, 70), Accent = Color3.fromRGB(250, 235, 225) },
	{ Id = "ZibraZubra", DisplayName = "Zibra Zubra Zibralini", Rarity = "Epic", Price = 35000, Income = 300, Color = Color3.fromRGB(245, 245, 245), Accent = Color3.fromRGB(30, 30, 35) },
	-- Legendary
	{ Id = "PinguinoHackerino", DisplayName = "Pinguino Hackerino", Rarity = "Legendary", Price = 75000, Income = 500, Color = Color3.fromRGB(40, 40, 50), Accent = Color3.fromRGB(0, 255, 120) },
	{ Id = "LasagnaLightningo", DisplayName = "Lasagna Lightningo", Rarity = "Legendary", Price = 200000, Income = 1200, Color = Color3.fromRGB(220, 90, 40), Accent = Color3.fromRGB(255, 240, 80) },
	{ Id = "TungTungSahur", DisplayName = "Tung Tung Tung Sahur", Rarity = "Legendary", Price = 350000, Income = 2000, Color = Color3.fromRGB(176, 120, 72), Accent = Color3.fromRGB(120, 78, 45) },
	{ Id = "SushitoSamurai", DisplayName = "Sushito Samurai", Rarity = "Legendary", Price = 500000, Income = 2800, Color = Color3.fromRGB(250, 130, 90), Accent = Color3.fromRGB(200, 30, 40) },
	{ Id = "LeoneLasagnone", DisplayName = "Leone Lasagnone", Rarity = "Legendary", Price = 90000, Income = 600, Color = Color3.fromRGB(245, 200, 90), Accent = Color3.fromRGB(200, 50, 35) },
	{ Id = "SqualoScarpone", DisplayName = "Squalo Scarpone", Rarity = "Legendary", Price = 120000, Income = 780, Color = Color3.fromRGB(110, 140, 180), Accent = Color3.fromRGB(245, 245, 250) },
	{ Id = "GranchioCorazzato", DisplayName = "Granchio Corazzato", Rarity = "Legendary", Price = 160000, Income = 1000, Color = Color3.fromRGB(225, 70, 50), Accent = Color3.fromRGB(190, 195, 205) },
	{ Id = "UnicorninoArcobaleno", DisplayName = "Unicornino Arcobaleno", Rarity = "Legendary", Price = 250000, Income = 1500, Color = Color3.fromRGB(250, 250, 255), Accent = Color3.fromRGB(255, 150, 220) },
	{ Id = "PinguinoPilota", DisplayName = "Pinguino Pilota", Rarity = "Legendary", Price = 420000, Income = 2400, Color = Color3.fromRGB(35, 35, 45), Accent = Color3.fromRGB(245, 245, 250) },
	{ Id = "PolipoPianista", DisplayName = "Polipo Pianista", Rarity = "Legendary", Price = 650000, Income = 3550, Color = Color3.fromRGB(150, 90, 200), Accent = Color3.fromRGB(25, 25, 30) },
	{ Id = "TigreTiramisu", DisplayName = "Tigre Tiramisù", Rarity = "Legendary", Price = 700000, Income = 3800, Color = Color3.fromRGB(240, 215, 170), Accent = Color3.fromRGB(90, 55, 35) },
	{ Id = "BurbaloniLoliloli", DisplayName = "Burbaloni Loliloli", Rarity = "Legendary", Price = 85000, Income = 560, Color = Color3.fromRGB(170, 120, 80), Accent = Color3.fromRGB(120, 80, 50) },
	{ Id = "ChefCrabracadabra", DisplayName = "Chef Crabracadabra", Rarity = "Legendary", Price = 140000, Income = 880, Color = Color3.fromRGB(230, 80, 60), Accent = Color3.fromRGB(250, 250, 250) },
	{ Id = "GlorboFruttodrillo", DisplayName = "Glorbo Fruttodrillo", Rarity = "Legendary", Price = 220000, Income = 1350, Color = Color3.fromRGB(70, 160, 70), Accent = Color3.fromRGB(90, 150, 70) },
	{ Id = "BlueberrinniOctopusini", DisplayName = "Blueberrinni Octopusini", Rarity = "Legendary", Price = 300000, Income = 1750, Color = Color3.fromRGB(70, 80, 170), Accent = Color3.fromRGB(110, 120, 210) },
	{ Id = "OrangutiniAnanassini", DisplayName = "Orangutini Ananassini", Rarity = "Legendary", Price = 480000, Income = 2700, Color = Color3.fromRGB(240, 200, 60), Accent = Color3.fromRGB(210, 110, 40) },
	{ Id = "LionelCactuseli", DisplayName = "Lionel Cactuseli", Rarity = "Legendary", Price = 800000, Income = 4300, Color = Color3.fromRGB(90, 165, 80), Accent = Color3.fromRGB(250, 190, 60) },
	-- Mythic
	{ Id = "DragoniSpaghettoni", DisplayName = "Dragoni Spaghettoni", Rarity = "Mythic", Price = 1500000, Income = 6000, Color = Color3.fromRGB(200, 30, 30), Accent = Color3.fromRGB(255, 210, 120) },
	{ Id = "BallerinaCapuchina", DisplayName = "Ballerina Capuchina", Rarity = "Mythic", Price = 2500000, Income = 10000, Color = Color3.fromRGB(245, 190, 170), Accent = Color3.fromRGB(180, 110, 60) },
	{ Id = "MeatballoSupremo", DisplayName = "Meatballo Supremo", Rarity = "Mythic", Price = 4000000, Income = 15000, Color = Color3.fromRGB(120, 60, 40), Accent = Color3.fromRGB(255, 255, 255) },
	{ Id = "TacoraptorSupremo", DisplayName = "Tacoraptor Supremo", Rarity = "Mythic", Price = 8000000, Income = 28000, Color = Color3.fromRGB(240, 190, 80), Accent = Color3.fromRGB(90, 200, 70) },
	{ Id = "FeniceFocaccia", DisplayName = "Fenice Focaccia", Rarity = "Mythic", Price = 1200000, Income = 4800, Color = Color3.fromRGB(230, 170, 80), Accent = Color3.fromRGB(255, 110, 30) },
	{ Id = "KrakenCarbonara", DisplayName = "Kraken Carbonara", Rarity = "Mythic", Price = 2000000, Income = 8000, Color = Color3.fromRGB(245, 225, 170), Accent = Color3.fromRGB(200, 90, 80) },
	{ Id = "GolemGorgonzola", DisplayName = "Golem Gorgonzola", Rarity = "Mythic", Price = 3000000, Income = 11500, Color = Color3.fromRGB(235, 230, 200), Accent = Color3.fromRGB(80, 120, 210) },
	{ Id = "CerberoCalzone", DisplayName = "Cerbero Calzone", Rarity = "Mythic", Price = 10000000, Income = 34000, Color = Color3.fromRGB(220, 160, 80), Accent = Color3.fromRGB(200, 45, 35) },
	{ Id = "LeviatanoLinguine", DisplayName = "Leviatano Linguine", Rarity = "Mythic", Price = 15000000, Income = 50000, Color = Color3.fromRGB(60, 170, 170), Accent = Color3.fromRGB(250, 230, 170) },
	{ Id = "BombardiroCrocodilo", DisplayName = "Bombardiro Crocodilo", Rarity = "Mythic", Price = 1800000, Income = 7000, Color = Color3.fromRGB(80, 150, 70), Accent = Color3.fromRGB(150, 155, 165) },
	{ Id = "BombombiniGusini", DisplayName = "Bombombini Gusini", Rarity = "Mythic", Price = 2500000, Income = 9800, Color = Color3.fromRGB(250, 250, 250), Accent = Color3.fromRGB(255, 160, 50) },
	{ Id = "FrigoCamelo", DisplayName = "Frigo Camelo", Rarity = "Mythic", Price = 5000000, Income = 18000, Color = Color3.fromRGB(240, 245, 250), Accent = Color3.fromRGB(210, 170, 110) },
	{ Id = "RhinoToasterino", DisplayName = "Rhino Toasterino", Rarity = "Mythic", Price = 6500000, Income = 22500, Color = Color3.fromRGB(200, 205, 215), Accent = Color3.fromRGB(150, 150, 160) },
	{ Id = "CocofantoElefanto", DisplayName = "Cocofanto Elefanto", Rarity = "Mythic", Price = 12000000, Income = 40000, Color = Color3.fromRGB(120, 80, 50), Accent = Color3.fromRGB(165, 165, 175) },
	-- Event Special
	-- Launch event: 500 for sale at 50 Robux + 2 reserved. Earns $2.5K/s and
	-- doubles with every rebirth, so she stays useful without breaking the economy.
	{ Id = "CignaGlamourina", DisplayName = "Cigna Glamourina", Rarity = "EventSpecial", Price = 0, Income = 2500, IncomeGrowth = 2, Limited = true, Color = Color3.fromRGB(240, 110, 200), Accent = Color3.fromRGB(255, 30, 170) },
	-- Next event: the lanky forest deer with long claws. It has its own statue
	-- beside Cigna's (Config.NextEvent) and goes on sale as soon as its
	-- gamepass is set below (LimitedItems).
	{ Id = "SixtySevenNights", DisplayName = "67 Nights Deer", Rarity = "EventSpecial", Price = 0, Income = 3000, IncomeGrowth = 2, Limited = true, Color = Color3.fromRGB(82, 64, 64), Accent = Color3.fromRGB(245, 150, 175) },
	-- Secret
	-- A little sneaker creature: kept short on purpose (Scale), but very rare.
	-- (The Id keeps its old name so saved copies still load.)
	{ Id = "ScarpinoStellino", DisplayName = "Sneakerino Shoelacini", Rarity = "Secret", Price = 25000000, Income = 120000, Scale = 1.15, Color = Color3.fromRGB(110, 130, 205), Accent = Color3.fromRGB(240, 235, 222) },
	{ Id = "IlCosmicoCannolo", DisplayName = "Il Cosmico Cannolo", Rarity = "Secret", Price = 50000000, Income = 250000, Color = Color3.fromRGB(30, 10, 60), Accent = Color3.fromRGB(255, 120, 255) },
	{ Id = "AstronautoPanino", DisplayName = "Astronauto Panino", Rarity = "Secret", Price = 120000000, Income = 550000, Color = Color3.fromRGB(235, 235, 245), Accent = Color3.fromRGB(80, 180, 255) },
	{ Id = "ReRavioliSupremo", DisplayName = "Re Ravioli Supremo", Rarity = "Secret", Price = 30000000, Income = 140000, Color = Color3.fromRGB(245, 220, 150), Accent = Color3.fromRGB(120, 40, 170) },
	{ Id = "FantasmaFettuccine", DisplayName = "Fantasma Fettuccine", Rarity = "Secret", Price = 65000000, Income = 300000, Color = Color3.fromRGB(235, 245, 255), Accent = Color3.fromRGB(250, 230, 170) },
	{ Id = "GalassiaGnocchi", DisplayName = "Galassia Gnocchi", Rarity = "Secret", Price = 200000000, Income = 900000, Color = Color3.fromRGB(60, 30, 120), Accent = Color3.fromRGB(80, 220, 255) },
	{ Id = "LaVaccaSaturnita", DisplayName = "La Vacca Saturno Saturnita", Rarity = "Secret", Price = 40000000, Income = 190000, Color = Color3.fromRGB(250, 250, 250), Accent = Color3.fromRGB(230, 190, 140) },
	{ Id = "TrenostruzzoTurbo", DisplayName = "Trenostruzzo Turbo 3000", Rarity = "Secret", Price = 90000000, Income = 410000, Color = Color3.fromRGB(200, 40, 40), Accent = Color3.fromRGB(40, 40, 48) },
	{ Id = "GraipussMedussi", DisplayName = "Graipuss Medussi", Rarity = "Secret", Price = 150000000, Income = 680000, Color = Color3.fromRGB(130, 60, 170), Accent = Color3.fromRGB(220, 160, 255) },
	-- Celestial
	{ Id = "ImperatorePizzone", DisplayName = "Imperatore Pizzone", Rarity = "Celestial", Price = 300000000, Income = 1300000, Color = Color3.fromRGB(230, 180, 100), Accent = Color3.fromRGB(210, 45, 35) },
	{ Id = "OmegaBrainrotto", DisplayName = "Omega Brainrotto", Rarity = "Celestial", Price = 600000000, Income = 2500000, Color = Color3.fromRGB(255, 150, 180), Accent = Color3.fromRGB(90, 240, 255) },
	{ Id = "LaGrandeCombinasion", DisplayName = "La Grande Combinasion", Rarity = "Celestial", Price = 1000000000, Income = 4000000, Color = Color3.fromRGB(176, 120, 72), Accent = Color3.fromRGB(255, 200, 50) },
} :: { Brainrot }

-- Mutations ----------------------------------------------------------------
-- Any brainrot on the conveyor can roll a mutation. Mutations multiply both
-- the price and the income, and change how it looks. Server Luck boosts them.

export type Mutation = {
	Id: string,
	DisplayName: string,
	Chance: number, -- percent per conveyor spawn
	Multiplier: number,
	Color: Color3,
	Exclusive: { string }?, -- only these brainrots can have it (never on the conveyor)
}

Config.Mutations = {
	-- Keep this list ordered from most to least common (the roll relies on it).
	{ Id = "Gold", DisplayName = "Gold", Chance = 4, Multiplier = 2, Color = Color3.fromRGB(255, 200, 50) },
	{ Id = "Candy", DisplayName = "Candy", Chance = 2.5, Multiplier = 2.5, Color = Color3.fromRGB(255, 160, 210) },
	{ Id = "Diamond", DisplayName = "Crystal", Chance = 2, Multiplier = 3, Color = Color3.fromRGB(140, 230, 255) },
	{ Id = "Frozen", DisplayName = "Frozen", Chance = 2, Multiplier = 3, Color = Color3.fromRGB(170, 225, 255) },
	{ Id = "Sparkle", DisplayName = "Sparkle", Chance = 1.5, Multiplier = 4, Color = Color3.fromRGB(255, 250, 170) },
	{ Id = "Electric", DisplayName = "Electric", Chance = 1.2, Multiplier = 4.5, Color = Color3.fromRGB(255, 230, 70) },
	{ Id = "Smiley", DisplayName = "Smiley", Chance = 1, Multiplier = 5, Color = Color3.fromRGB(255, 220, 60) },
	{ Id = "Radioactive", DisplayName = "Radioactive", Chance = 0.9, Multiplier = 5.5, Color = Color3.fromRGB(120, 255, 90) },
	{ Id = "Lava", DisplayName = "Lava", Chance = 0.8, Multiplier = 5, Color = Color3.fromRGB(255, 100, 20) },
	{ Id = "Galaxy", DisplayName = "Galaxy", Chance = 0.6, Multiplier = 7, Color = Color3.fromRGB(150, 100, 255) },
	{ Id = "Cursed", DisplayName = "Cursed", Chance = 0.5, Multiplier = 8, Color = Color3.fromRGB(210, 40, 60) },
	{ Id = "Rainbow", DisplayName = "Rainbow", Chance = 0.3, Multiplier = 10, Color = Color3.fromRGB(255, 120, 255) },
	{ Id = "Void", DisplayName = "Void", Chance = 0.2, Multiplier = 12, Color = Color3.fromRGB(130, 80, 210) },
	{ Id = "Divine", DisplayName = "Divine", Chance = 0.1, Multiplier = 15, Color = Color3.fromRGB(255, 235, 160) },
	-- Event-only: 1% when you get Cigna Glamourina, or given by an admin.
	{ Id = "Magic", DisplayName = "Magic", Chance = 0, Multiplier = 8, Color = Color3.fromRGB(190, 130, 255), Exclusive = { "CignaGlamourina" } },
} :: { Mutation }

Config.MagicChance = 1 -- percent, rolled when a limited event brainrot is granted
Config.CurrentEvent = "CignaGlamourina" -- the brainrot shown on the event statue
Config.NextEvent = "SixtySevenNights" -- its own statue right beside it (same as CurrentEvent = no second statue)

-- Economy ------------------------------------------------------------------

Config.StartingCash = 100
Config.SellRatio = 0.5 -- selling returns this share of the buy price

-- Conveyor -----------------------------------------------------------------

Config.ConveyorSpawnInterval = 3 -- seconds between new brainrots
Config.FreeConveyorEvery = 5 -- every 5th brainrot on the conveyor is a free one (starting money)
Config.ConveyorTravelTime = 75 -- seconds to ride from one end to the other
Config.ServerLuckMultiplier = 2 -- doubles the spawn weight of Rare and better (Mythic 0.9% -> ~1.3%)
Config.ServerLuckDuration = 15 * 60

-- Bases --------------------------------------------------------------------

Config.PlotCount = 8 -- also set Max Players to 8 in Game Settings
Config.BaseSlots = 10
Config.VipSlots = 2 -- extra slots for VIP owners
Config.LockCooldown = 30 -- vulnerable window after a lock ends

-- Base levels ----------------------------------------------------------------
-- Walls and floors are upgraded together: each base level adds a floor
-- (reached by stairs inside the base) and better walls. Players jump about
-- 7 studs high, so level 3 is the first wall nobody can jump over; from then
-- on the entrance (and its lock lasers) is the only way in.

export type WallLevel = {
	Name: string,
	Height: number,
	Cost: number, -- price of reaching this base level
	Material: Enum.Material,
	Vip: boolean?, -- only VIP owners can buy this level (and its floor)
}

Config.WallLevels = {
	{ Name = "Wood Fence", Height = 3, Cost = 0, Material = Enum.Material.WoodPlanks },
	{ Name = "Brick Wall", Height = 5.5, Cost = 50000, Material = Enum.Material.Brick },
	{ Name = "Concrete Wall", Height = 9, Cost = 2500000, Material = Enum.Material.Concrete },
	{ Name = "Steel Wall", Height = 13, Cost = 100000000, Material = Enum.Material.DiamondPlate },
	{ Name = "Platinum Wall", Height = 18, Cost = 4000000000, Material = Enum.Material.Foil },
	-- VIP only: two more floors (and 20 more slots) on top.
	{ Name = "Royal Marble Wall", Height = 18, Cost = 150000000000, Material = Enum.Material.Marble, Vip = true },
	{ Name = "Golden Palace Wall", Height = 18, Cost = 6000000000000, Material = Enum.Material.Foil, Vip = true },
} :: { WallLevel }
-- Levels everyone can reach; the ones after it are VIP only. A base gets
-- its roof once it reaches this level.
Config.StandardWallLevels = 5

-- The highest base level this player can buy.
function Config.MaxWallLevel(isVip: boolean?): number
	return if isVip then #Config.WallLevels else Config.StandardWallLevels
end

-- One floor per base level, so this list must be as long as WallLevels.
export type Story = { Name: string }

Config.Stories = {
	{ Name = "Ground Floor" },
	{ Name = "2nd Floor" },
	{ Name = "3rd Floor" },
	{ Name = "4th Floor" },
	{ Name = "5th Floor" },
	{ Name = "6th Floor (VIP)" },
	{ Name = "7th Floor (VIP)" },
} :: { Story }
assert(#Config.Stories == #Config.WallLevels, "Config: need one floor per wall level")
Config.UpperFloorSlots = 10

-- Wall skins -----------------------------------------------------------------
-- Cosmetic looks for your base walls, bought with Shards (10 per daily
-- quest, 150 per weekly quest, 100 from the weekly admin abuse gift: about
-- 760 a week at most). They can't be bought with Robux, so everyone earns
-- skins the same way.
-- A skin keeps your base level's wall height; it just changes the look.

export type WallSkin = {
	Id: string,
	Name: string,
	Cost: number, -- in Shards
	Color: Color3?,
	Material: Enum.Material?, -- nil = the base level's own material
	Glass: Color3?, -- window tint
	GlassNeon: boolean?, -- glowing windows
	-- Every floor of the base. Unset = same grey and material as the walls
	-- (so Classic floors follow the base level: wood, brick, concrete...).
	FloorColor: Color3?,
	FloorMaterial: Enum.Material?,
	-- Only this founder (Config.Founders Id) can have it; it's free for them
	-- and hidden from everyone else.
	FounderOnly: string?,
	Corn: boolean?, -- corn cobs on the walls and the Corny Games logo on the windows
	Trim: Color3?, -- glowing strips along the window sills and tops
	Moon: boolean?, -- a crescent moon over the base, with an aura once it's fully upgraded
	RoleOnly: string?, -- "Tester", "Mod" or "VIP": only players with that role can have it (free)
	Vip: boolean?, -- VIP Royale: velvet stairs (Config.VipCarpet), a VIP throne and a VIP vault
	TopSign: string?, -- a glowing sign floating over the base (in the Trim color)
	Clover: boolean?, -- four-leaf clovers on the walls (Ace's skin)
	Pattern: string?, -- "Checker", "Stripes", "Dots", "Argyle" or "Smileys" on the floors and wall bands
	PatternColor: Color3?,
	PatternRainbow: boolean?, -- every stripe/tile its own color
}

Config.WallSkins = {
	{ Id = "Classic", Name = "Classic Grey", Cost = 0 },
	-- Early: cheap and cheerful
	{ Id = "Picnic", Name = "Picnic Checker", Cost = 80, Color = Color3.fromRGB(250, 248, 240), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 220, 220), Trim = Color3.fromRGB(220, 50, 50), FloorColor = Color3.fromRGB(255, 255, 255), FloorMaterial = Enum.Material.SmoothPlastic, Pattern = "Checker", PatternColor = Color3.fromRGB(220, 50, 50) },
	{ Id = "RedBrick", Name = "Red Brick", Cost = 250, Color = Color3.fromRGB(165, 65, 50), Material = Enum.Material.Brick, FloorColor = Color3.fromRGB(150, 105, 75), FloorMaterial = Enum.Material.WoodPlanks },
	{ Id = "MintStripes", Name = "Mint Stripes", Cost = 400, Color = Color3.fromRGB(170, 240, 210), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(220, 255, 240), FloorColor = Color3.fromRGB(230, 255, 245), FloorMaterial = Enum.Material.SmoothPlastic, Pattern = "Stripes", PatternColor = Color3.fromRGB(90, 200, 160) },
	{ Id = "BubblegumDots", Name = "Bubblegum Dots", Cost = 550, Color = Color3.fromRGB(255, 120, 190), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 210, 240), FloorColor = Color3.fromRGB(255, 200, 230), FloorMaterial = Enum.Material.SmoothPlastic, Pattern = "Dots", PatternColor = Color3.fromRGB(120, 200, 255) },
	{ Id = "Candy", Name = "Candy Pink", Cost = 700, Color = Color3.fromRGB(255, 160, 205), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 225, 245), FloorColor = Color3.fromRGB(255, 225, 238), FloorMaterial = Enum.Material.SmoothPlastic, Pattern = "Dots", PatternColor = Color3.fromRGB(255, 255, 255) },
	{ Id = "SmileySunshine", Name = "Smiley Sunshine", Cost = 900, Color = Color3.fromRGB(110, 200, 255), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 240, 150), Trim = Color3.fromRGB(255, 215, 50), FloorColor = Color3.fromRGB(150, 220, 255), FloorMaterial = Enum.Material.SmoothPlastic, Pattern = "Smileys" },
	{ Id = "Ice", Name = "Frozen Ice", Cost = 1200, Color = Color3.fromRGB(175, 220, 255), Material = Enum.Material.Ice, Glass = Color3.fromRGB(225, 245, 255), FloorColor = Color3.fromRGB(215, 238, 255), FloorMaterial = Enum.Material.Ice },
	{ Id = "Gold", Name = "Royal Gold", Cost = 1500, Color = Color3.fromRGB(255, 200, 60), Material = Enum.Material.Foil, Glass = Color3.fromRGB(255, 240, 180) },
	{ Id = "Jungle", Name = "Jungle Stone", Cost = 1900, Color = Color3.fromRGB(85, 120, 70), Material = Enum.Material.Slate, Glass = Color3.fromRGB(150, 220, 120), FloorColor = Color3.fromRGB(100, 85, 60), FloorMaterial = Enum.Material.Ground, Pattern = "Stripes", PatternColor = Color3.fromRGB(70, 110, 50) },
	-- Mid: a few weeks of quests
	{ Id = "Galaxy", Name = "Galaxy", Cost = 2400, Color = Color3.fromRGB(45, 25, 85), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(200, 120, 255), GlassNeon = true, FloorColor = Color3.fromRGB(25, 15, 50), FloorMaterial = Enum.Material.Glass, Pattern = "Dots", PatternColor = Color3.fromRGB(230, 220, 255) },
	{ Id = "Cyber", Name = "Cyber Neon", Cost = 3000, Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Metal, Glass = Color3.fromRGB(0, 255, 200), GlassNeon = true, FloorColor = Color3.fromRGB(35, 35, 45), FloorMaterial = Enum.Material.DiamondPlate, Pattern = "Checker", PatternColor = Color3.fromRGB(0, 160, 140) },
	{ Id = "Crystal", Name = "Crystal Palace", Cost = 3700, Color = Color3.fromRGB(150, 225, 255), Material = Enum.Material.Glass, Glass = Color3.fromRGB(220, 250, 255), GlassNeon = true, FloorColor = Color3.fromRGB(200, 240, 255), FloorMaterial = Enum.Material.Glass },
	{ Id = "RoyalDiamonds", Name = "Royal Argyle", Cost = 4500, Color = Color3.fromRGB(90, 40, 140), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 215, 120), GlassNeon = true, Trim = Color3.fromRGB(255, 200, 60), FloorColor = Color3.fromRGB(70, 30, 110), FloorMaterial = Enum.Material.SmoothPlastic, Pattern = "Argyle", PatternColor = Color3.fromRGB(255, 200, 60) },
	-- Late: the long-term goals
	{ Id = "Lava", Name = "Lava Core", Cost = 5500, Color = Color3.fromRGB(55, 25, 20), Material = Enum.Material.CrackedLava, Glass = Color3.fromRGB(255, 120, 30), GlassNeon = true, FloorColor = Color3.fromRGB(45, 22, 18), FloorMaterial = Enum.Material.Slate },
	{ Id = "Celestial", Name = "Celestial", Cost = 7000, Color = Color3.fromRGB(245, 240, 228), Material = Enum.Material.Marble, Glass = Color3.fromRGB(255, 210, 90), GlassNeon = true, FloorColor = Color3.fromRGB(250, 246, 236), FloorMaterial = Enum.Material.Marble, Pattern = "Argyle", PatternColor = Color3.fromRGB(255, 210, 90) },
	{ Id = "RainbowRoyale", Name = "Rainbow Royale", Cost = 9000, Color = Color3.fromRGB(250, 250, 255), Material = Enum.Material.Marble, Glass = Color3.fromRGB(255, 180, 255), GlassNeon = true, Trim = Color3.fromRGB(255, 120, 255), FloorColor = Color3.fromRGB(255, 255, 255), FloorMaterial = Enum.Material.Marble, Pattern = "Stripes", PatternRainbow = true },
	{ Id = "VoidEmperor", Name = "Void Emperor", Cost = 12000, Color = Color3.fromRGB(18, 10, 30), Material = Enum.Material.Slate, Glass = Color3.fromRGB(170, 80, 255), GlassNeon = true, Trim = Color3.fromRGB(150, 60, 255), FloorColor = Color3.fromRGB(25, 15, 40), FloorMaterial = Enum.Material.Slate, Pattern = "Argyle", PatternColor = Color3.fromRGB(150, 60, 255) },
	-- VIP Royale: free with the VIP gamepass. Royal purple and gold, with
	-- velvet stairs, a VIP throne in the vault (and on the balcony) and a
	-- decked-out VIP vault.
	{ Id = "VIP", Name = "VIP Royale (VIP only)", Cost = 0, RoleOnly = "VIP", Vip = true, TopSign = "👑 VIP", Trim = Color3.fromRGB(255, 200, 60), Color = Color3.fromRGB(78, 30, 125), Material = Enum.Material.Marble, Glass = Color3.fromRGB(255, 205, 80), GlassNeon = true, FloorColor = Color3.fromRGB(52, 20, 85), FloorMaterial = Enum.Material.Marble, Pattern = "Argyle", PatternColor = Color3.fromRGB(255, 200, 60) },
	-- Role skins: free for testers (Config.TesterUserIds) and for mods (admins).
	{ Id = "Tester", Name = "Beta Tester (testers only)", Cost = 0, RoleOnly = "Tester", TopSign = "🧪 BETA TESTER", Trim = Color3.fromRGB(0, 230, 255), Color = Color3.fromRGB(235, 245, 250), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(120, 240, 255), GlassNeon = true, FloorColor = Color3.fromRGB(205, 220, 230), FloorMaterial = Enum.Material.DiamondPlate },
	{ Id = "Mod", Name = "Moderator (mods only)", Cost = 0, RoleOnly = "Mod", TopSign = "🛡️ MODERATOR", Trim = Color3.fromRGB(255, 45, 60), Color = Color3.fromRGB(28, 28, 34), Material = Enum.Material.Metal, Glass = Color3.fromRGB(255, 70, 80), GlassNeon = true, FloorColor = Color3.fromRGB(40, 40, 48), FloorMaterial = Enum.Material.DiamondPlate },
	-- Ace's own skin, in Cigna Glamourina's pinks, with a crescent moon on top.
	{ Id = "Ace", Name = "Glamourina Moon (Ace only)", Cost = 0, FounderOnly = "Ace", Moon = true, Trim = Color3.fromRGB(255, 30, 170), Color = Color3.fromRGB(240, 110, 200), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 190, 235), GlassNeon = true, FloorColor = Color3.fromRGB(255, 225, 245), FloorMaterial = Enum.Material.SmoothPlastic, Clover = true, Pattern = "Dots", PatternColor = Color3.fromRGB(255, 190, 230) },
	-- Corny's own skin, like his logo: navy walls, gold trim, corn everywhere.
	{ Id = "Corny", Name = "Corny Gold (Corny only)", Cost = 0, FounderOnly = "Corny", Corn = true, Trim = Color3.fromRGB(250, 196, 60), Color = Color3.fromRGB(25, 32, 55), Material = Enum.Material.SmoothPlastic, Glass = Color3.fromRGB(255, 205, 60), FloorColor = Color3.fromRGB(255, 215, 90), FloorMaterial = Enum.Material.SmoothPlastic },
} :: { WallSkin }

-- Skins are a ladder: to buy one you must own the one before it (Picnic
-- Checker -> Red Brick -> Mint Stripes -> ...). Returns the skin you need
-- first, if any.
-- Skins only some players can have: a founder's own, or a role's (free).
function Config.IsExclusiveSkin(skin: WallSkin): boolean
	return skin.FounderOnly ~= nil or skin.RoleOnly ~= nil
end

-- Whether this player may claim/wear the skin. `roles` = { Tester, Mod }.
function Config.CanUseSkin(skin: WallSkin, founderId: string?, roles: { [string]: boolean }?): boolean
	if skin.FounderOnly then
		return skin.FounderOnly == founderId
	end
	if skin.RoleOnly then
		return roles ~= nil and roles[skin.RoleOnly] == true
	end
	return true
end

function Config.SkinRequirement(skin: WallSkin): WallSkin?
	if Config.IsExclusiveSkin(skin) then
		return nil
	end
	local previous: WallSkin? = nil
	for _, other in Config.WallSkins do
		if other.Id == skin.Id then
			return previous
		end
		if other.Cost > 0 and not Config.IsExclusiveSkin(other) then
			previous = other
		end
	end
	return nil
end

-- The skin you still need before buying `skin`, or nil if you can buy it.
-- Owning any higher skin of the same ladder counts too, so skins added in
-- between later never lock out players who are already past them.
function Config.MissingSkinRequirement(skin: WallSkin, owned: { string }?): WallSkin?
	local needed = Config.SkinRequirement(skin)
	if not needed or not owned then
		return needed
	end
	if table.find(owned, needed.Id) then
		return nil
	end
	local past = false
	for _, other in Config.WallSkins do
		if other.Id == skin.Id then
			past = true
		elseif past and not Config.IsExclusiveSkin(other) and table.find(owned, other.Id) then
			return nil
		end
	end
	return needed
end

-- Shard Shop: the counter in the shop tent (like a ticket shop). Shards
-- come from quests and the admin abuse gift (~760 a week at most), so
-- everything here is priced to be saved up for.
export type ShardItem = { Id: string, Name: string, Description: string, Cost: number }

Config.ShardShop = {
	{ Id = "CashBoost", Name = "2x Cash (30 min)", Description = "Double your income for 30 minutes. Stacks.", Cost = 150 },
	{ Id = "ServerLuck", Name = "Server Luck (15 min)", Description = "More Rare+ spawns for EVERYONE. Be a hero.", Cost = 250 },
	{ Id = "CashBoostBig", Name = "2x Cash (3 hours)", Description = "Double your income for 3 hours. Stacks.", Cost = 600 },
	-- The same as the Infinite Laser Door gamepass. The most expensive thing
	-- in the game on purpose: months of quests and admin abuse.
	{ Id = "InfiniteLock", Name = "Infinite Laser Door", Description = "Your base lasers stay on forever. One-time, permanent.", Cost = 12500 },
} :: { ShardItem }
-- Diamonds were removed from the game; old saves and old in-game codes turn
-- every Diamond into this many Shards.
Config.ShardsPerOldDiamond = 50
Config.CashBoostSeconds = 30 * 60
Config.BigCashBoostSeconds = 3 * 60 * 60

function Config.GetWallSkin(id: string?): WallSkin?
	for _, skin in Config.WallSkins do
		if skin.Id == id then
			return skin
		end
	end
	return nil
end

-- Quests -----------------------------------------------------------------------
-- Everyone gets the same 3 daily and 3 weekly quests (picked from the pools
-- below). Days reset at midnight in the admin abuse time zone (Oklahoma);
-- weeks reset Monday at midnight. Both pay Shards; weekly quests are much
-- harder and pay a lot more.

export type QuestDef = {
	Id: string, -- the stat it counts (see Main.server: addQuestProgress)
	Text: string, -- "%d" is replaced with the goal
	Goal: number,
}

Config.DailyQuests = {
	{ Id = "Buy", Text = "Buy %d brainrots", Goal = 15 },
	{ Id = "BuyEpic", Text = "Buy %d Epic or better brainrots", Goal = 3 },
	{ Id = "Steal", Text = "Steal %d brainrots", Goal = 2 },
	{ Id = "Collect", Text = "Collect cash %d times", Goal = 20 },
	{ Id = "Slap", Text = "Slap %d thieves", Goal = 3 },
	{ Id = "Lock", Text = "Lock your base %d times", Goal = 5 },
	{ Id = "Minutes", Text = "Play for %d minutes", Goal = 20 },
	{ Id = "Grab", Text = "Grab %d admin drops", Goal = 1 },
} :: { QuestDef }

Config.WeeklyQuests = {
	{ Id = "Buy", Text = "Buy %d brainrots", Goal = 400 },
	{ Id = "BuyLegendary", Text = "Buy %d Legendary or better brainrots", Goal = 15 },
	{ Id = "BuyMutated", Text = "Buy %d mutated brainrots", Goal = 20 },
	{ Id = "Steal", Text = "Steal %d brainrots", Goal = 40 },
	{ Id = "Slap", Text = "Slap %d thieves", Goal = 50 },
	{ Id = "Minutes", Text = "Play for %d minutes", Goal = 360 },
	{ Id = "Rebirth", Text = "Rebirth %d times", Goal = 2 },
	{ Id = "Upgrade", Text = "Buy %d base or lock upgrades", Goal = 3 },
} :: { QuestDef }

Config.QuestsPerPeriod = 3
Config.DailyShards = 10 -- per daily quest
Config.WeeklyShards = 150 -- per weekly quest

-- The day and week numbers quests are keyed on (local to the admin abuse
-- time zone, so "midnight" is Oklahoma midnight).
function Config.QuestPeriods(now: number): (number, number, number, number)
	local localNow = now + Config.AdminAbuseUtcOffset(now)
	local day = localNow // 86400
	-- Unix day 0 was a Thursday; +3 makes weeks start on Monday.
	local week = (day + 3) // 7
	local secondsToDay = 86400 - localNow % 86400
	local secondsToWeek = (7 - (day + 3) % 7) * 86400 - localNow % 86400
	return day, week, secondsToDay, secondsToWeek
end

-- The quests everyone gets for a given day/week. Same seed -> same quests.
function Config.PickQuests(pool: { QuestDef }, seed: number): { QuestDef }
	local rng = Random.new(seed)
	local indexes = {}
	for i = 1, #pool do
		indexes[i] = i
	end
	local picked = {}
	for i = 1, math.min(Config.QuestsPerPeriod, #pool) do
		local j = rng:NextInteger(i, #indexes)
		indexes[i], indexes[j] = indexes[j], indexes[i]
		table.insert(picked, pool[indexes[i]])
	end
	return picked
end

-- Stair carpets -------------------------------------------------------------
-- Stairs start as plain wood. Every 5 rebirths they get a fancier carpet.

export type CarpetTier = {
	Name: string,
	Color: Color3,
	Material: Enum.Material,
	Trim: Color3?, -- edge strips along both sides
	Glow: Color3?, -- neon light on the lip of every step
	Sparkle: boolean?,
	Rainbow: boolean?,
}

Config.CarpetRebirthStep = 5
Config.CarpetTiers = {
	{ Name = "Red Carpet", Color = Color3.fromRGB(170, 20, 35), Material = Enum.Material.Fabric },
	{ Name = "Royal Carpet", Color = Color3.fromRGB(95, 30, 150), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 200, 60) },
	{ Name = "Golden Carpet", Color = Color3.fromRGB(235, 185, 50), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 255, 255), Glow = Color3.fromRGB(255, 220, 120) },
	{ Name = "Crystal Carpet", Color = Color3.fromRGB(150, 225, 255), Material = Enum.Material.Glass, Trim = Color3.fromRGB(220, 250, 255), Glow = Color3.fromRGB(90, 220, 255), Sparkle = true },
	{ Name = "Rainbow Carpet", Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 200, 60), Glow = Color3.fromRGB(255, 120, 255), Sparkle = true, Rainbow = true },
} :: { CarpetTier }

-- The VIP Royale skin's stairs (whatever the rebirths).
Config.VipCarpet = { Name = "VIP Velvet", Color = Color3.fromRGB(110, 35, 175), Material = Enum.Material.Fabric, Trim = Color3.fromRGB(255, 200, 60), Glow = Color3.fromRGB(255, 210, 90), Sparkle = true } :: CarpetTier

-- 0 = plain wood stairs, 1 = first carpet at 5 rebirths, and so on.
function Config.CarpetTierFor(rebirths: number): number
	return math.min(#Config.CarpetTiers, rebirths // Config.CarpetRebirthStep)
end

-- Vault ---------------------------------------------------------------------
-- A room under every base (enter through the hatch). Brainrots on its
-- podiums keep earning, can't be stolen, and stay through rebirths. Vault
-- upgrades (more podiums) are kept through rebirths too.
export type VaultLevel = { Podiums: number, Cost: number }

Config.VaultLevels = {
	{ Podiums = 2, Cost = 0 },
	{ Podiums = 4, Cost = 250000 },
	{ Podiums = 6, Cost = 10000000 },
	{ Podiums = 8, Cost = 500000000 },
	{ Podiums = 10, Cost = 25000000000 },
	{ Podiums = 12, Cost = 1000000000000 },
} :: { VaultLevel }
Config.VaultMaxPodiums = 12

-- Prestige: the more you rebirth, the cooler your base looks. Each step
-- keeps the ones before it. Colors follow your stair carpet.
Config.PrestigeLadder = {
	{ Rebirths = 1, Key = "Rims", Name = "Glowing pedestal rims" },
	{ Rebirths = 3, Key = "Torches", Name = "Torches by the door" },
	{ Rebirths = 5, Key = "Banners", Name = "Rebirth banners on the front wall" },
	{ Rebirths = 10, Key = "Pillars", Name = "Guardian pillars at the front corners" },
	{ Rebirths = 15, Key = "Runway", Name = "A royal runway to the door" },
	{ Rebirths = 20, Key = "Beacon", Name = "A sky beacon everyone can see" },
	-- The last carpet tier: a balcony over the door with a king's throne in
	-- the carpet's colors (Corny's is made of corn, Ace's is a pink bloom).
	{ Rebirths = Config.CarpetRebirthStep * #Config.CarpetTiers, Key = "Balcony", Name = "The King's balcony and throne" },
}

function Config.HasPrestige(rebirths: number, key: string): boolean
	for _, step in Config.PrestigeLadder do
		if step.Key == key then
			return rebirths >= step.Rebirths
		end
	end
	return false
end

-- Lock upgrades --------------------------------------------------------------
-- How long the entrance lasers stay on.

-- Rebirths: how many times you must have rebirthed before you can buy it.
export type LockLevel = { Duration: number, Cost: number, Rebirths: number? }

Config.LockLevels = {
	{ Duration = 30, Cost = 0 },
	{ Duration = 45, Cost = 5000 },
	{ Duration = 60, Cost = 50000 },
	{ Duration = 90, Cost = 500000 },
	{ Duration = 120, Cost = 5000000 },
	-- Rebirth-only levels (kept through rebirths, like every lock upgrade)
	{ Duration = 150, Cost = 25000000, Rebirths = 1 },
	{ Duration = 180, Cost = 250000000, Rebirths = 2 },
	{ Duration = 210, Cost = 2000000000, Rebirths = 4 },
	{ Duration = 240, Cost = 40000000000, Rebirths = 6 },
} :: { LockLevel }

-- Stealing -----------------------------------------------------------------

Config.CarryWalkSpeed = 13 -- thieves move slower while carrying (and can't sprint)
Config.SprintMultiplier = 1.45 -- Shift / SPRINT button / click the left stick
Config.NormalWalkSpeed = 16
Config.StealRange = 14
Config.SlapCooldown = 0.8
Config.SlapRange = 8
Config.SlapForce = 70
-- Corny's hammer (only that founder gets it): flings whoever it hits.
Config.HammerOwner = "Corny"
Config.HammerRange = 11
Config.HammerCooldown = 1
Config.HammerForce = 320 -- sideways
Config.HammerLift = 200 -- upward
-- Powers while the hammer is in his hand (HammerPowers.client):
Config.HammerFlySpeed = 90 -- FLY
Config.HammerSprintSpeed = 85 -- SUPER SPRINT
Config.HammerSlamCooldown = 15 -- SLAM: flings every other player on the map
-- Each swing also cracks a glowing line straight along the ground; anyone
-- standing on it takes damage and gets flung.
Config.HammerLineLength = 70
Config.HammerLineWidth = 4
Config.HammerLineDamage = 35

-- Rebirth ------------------------------------------------------------------

Config.RebirthBaseCost = 2500000
Config.RebirthCostGrowth = 6
Config.RebirthBonus = 0.5 -- +50% income per rebirth

-- Admins -------------------------------------------------------------------
-- The founders and the game's owner (or a group owner, for group games) get
-- the full admin panel, and so does everyone when testing in Studio.
-- Mods: Roblox user IDs (the number in their profile URL) listed here get the
-- small MOD PANEL instead (kick, ban, unban and announcements) and the
-- Moderator wall skin.
Config.AdminUserIds = {
	3272219254,
} :: { number }
-- Testers: get the Beta Tester wall skin (admins count as testers too).
Config.TesterUserIds = {
	3272219254,
} :: { number }
-- What mods can do from the MOD PANEL (the server refuses anything else).
Config.ModActions = { "Kick", "Ban", "Unban", "GlobalAnnounce" }
Config.AdminGroupRank = 255 -- for group games: this rank and above are admins

-- Admin abuse --------------------------------------------------------------
-- A weekly event. Everyone sees a countdown during the hour before it, and a
-- LIVE banner while it runs. The time is local to the time zone below, and
-- US daylight saving time is handled automatically.
-- Admins can also start or stop it any time from the admin panel.

Config.AdminAbuse = {
	WeekDay = 7, -- 1 = Sunday, 2 = Monday ... 7 = Saturday
	Hour = 14, -- 24-hour clock: 14 = 2 PM
	Minute = 0,
	UtcOffset = -6, -- US Central standard time (Oklahoma)
	UsDaylightSaving = true, -- adds an hour from March to November
	DurationMinutes = 60,
	CountdownMinutes = 60,
}

-- What everyone gets during admin abuse. It's rare (once a week), so it's big.
Config.AdminAbuseBoosts = {
	Income = 3, -- x3 cash for everyone while it's live (stacks with other boosts)
	Luck = 3, -- x3 luck for rare spawns and mutations (bought Server Luck is x2)
	WalkSpeed = 24, -- normal walking speed while it's live (16 normally; carrying is unchanged)
	JumpHeight = 13, -- normal jump is 7.2
}

-- Game music ------------------------------------------------------------------
-- Background music for normal play (audio ids, "rbxassetid://123..."). Plays
-- on a loop (shuffled if there's more than one), fades out while a founder
-- event plays its own song, and players can turn it off. Empty = no music.
-- More of our own songs are in assets/music/: upload one and add its id here.
Config.GameMusic = {
	"rbxassetid://119583552951911", -- "Chill Plaza" (assets/music/lobby_3_chill_plaza.mp3)
} :: { string }
Config.GameMusicVolume = 0.35

-- Founders --------------------------------------------------------------------
-- The game's founders show up as giants during admin abuse, and each has an
-- event of their own. Put each founder's Roblox UserId (the number in their
-- profile link: roblox.com/users/<UserId>/profile) or their Username here so
-- the giants wear their real avatars.
export type Founder = { Id: string, Name: string, UserId: number, Username: string }
Config.Founders = {
	{ Id = "Corny", Name = "Corny", UserId = 469657246, Username = "Cornywell10" },
	{ Id = "Ace", Name = "Ace", UserId = 8504983999, Username = "Meishappy2341" },
} :: { Founder }
-- During admin abuse they tower just outside the fence (like the devs in
-- Grow a Garden), doing one Roblox emote after another.
-- The head founder can do everything the other founders can (start Ace's
-- event too); the others only get their own.
Config.HeadFounder = "Corny"
Config.FounderGiantScale = 24 -- about 125 studs tall
Config.FounderGiantSpots = {
	Corny = Vector3.new(-170, 0, 470),
	Ace = Vector3.new(170, 0, -470),
} :: { [string]: Vector3 }
-- 99 Nights rules (Config.FounderEvents.Nights99).
Config.Nights99 = {
	HuntEvery = 40, -- seconds between hunts
	HuntWarning = 8, -- seconds to reach a campfire after the scream
	SafeRadius = 22, -- how close to a campfire counts as safe
	SafeShards = 5, -- Shards for everyone who survives a hunt
	LuckPerNight = 0.25, -- server luck gained per night survived...
	MaxLuck = 3, -- ...up to this
	ChestEvery = 10, -- seconds between supply chests
	MaxChests = 6,
	ChestBrainrotChance = 0.2, -- else cash
	ChestLuck = 2,
	ChestIncomeSeconds = 15, -- a cash chest is worth this much of your income...
	ChestMinimumCash = 300, -- ...and at least this
}

-- Cash bags from founder events: a few seconds of the grabber's own income
-- (so they matter early on without skipping the game later), at least this.
Config.FounderCashDrop = 200
Config.FounderCashDropSeconds = 8

-- Founder events: each stars only that founder, wearing their special event
-- outfit (not their normal avatar). Admins start them from the admin panel.
export type FounderEvent = {
	Founder: string,
	OutfitId: number, -- their special event outfit (0 = Corny's built-in look-alike)
	Title: string,
	Subtitle: string,
	DurationMinutes: number,
	Scale: number,
	Spots: { Vector3 }, -- where they appear (one per side of the map)
	-- "Ufo": they float in a UFO's beam throwing things (Corny's).
	-- "Ballet": they stand in the water while Cigna Glamourina dances around them (Ace's).
	Style: string,
	UfoSize: number?, -- the UFO's width
	UfoHeight: number?, -- how high the UFO hovers
	FloatHeight: number?, -- how high their feet float in the beam
	PoseAnimationId: string?, -- the pose they hold ("" = the built-in pose)
	DropEvery: number?, -- seconds between throws (nil = no throwing)
	BrainrotChance: number?, -- chance each throw is a brainrot (else a cash bag)
	BrainrotLuck: number?,
	Mutations: { { Id: string, Chance: number } }?, -- extra mutation chances on their brainrots (percent)
	Luck: number?, -- server luck while it runs (like bought Server Luck)
	Guaranteed: string?, -- a brainrot that's sure to come down the conveyor, with a rare mutation
	Dancer: string?, -- a brainrot that flies around them dancing ballet
	Colors: { Color3 }, -- intro colors
	Chips: { string }, -- the little boxes under the intro title
	Sky: string?, -- "Green", "Pink" or "Rainbow": the sky changes while it runs
	Water: boolean?, -- knee-deep water floods the map, with lily pads falling into it
	MusicId: string?, -- theme song (an audio id, "rbxassetid://123..."), "" = none
	Night: boolean?, -- it turns night while it runs
	-- Each night one of these mutations is picked at random (Chance is its
	-- percent chance of being tonight's pick) and is Boost times more likely
	-- on everything that spawns or drops until morning.
	NightMutations: { { Id: string, Chance: number, Boost: number } }?,
	Alien: boolean?, -- alien-style intro (green, sci-fi, glitchy) instead of rainbow
	Chaos: boolean?, -- sweeping green searchlights, pulsing lights, mini UFOs and abduction beams
	AnyFounder: boolean?, -- any founder can start it (not just `Founder`)
	EventName: string?, -- shown in the event label (otherwise "<FOUNDER>'S EVENT")
	-- "Forest" (99 Nights): a giant 67 Nights Deer prowls each side of the
	-- map in the dark while campfires burn and the forest fog rolls in.
	Forest: boolean?,
}
Config.FounderEvents = {
	Corny = {
		Founder = "Corny",
		Style = "Ufo",
		-- To use the real outfit: save it as a Costume on Roblox and put its
		-- outfit id here. Until then a look-alike of it is built from parts.
		OutfitId = 0,
		Title = "CORNY EVENT!",
		Subtitle = "Giant Corny has landed! Grab everything he throws!",
		DurationMinutes = 5,
		Scale = 19, -- about 120 studs tall
		-- One UFO on each side, over the open grass just behind the bases.
		Spots = { Vector3.new(0, 0, 240), Vector3.new(0, 0, -240) },
		UfoSize = 260,
		UfoHeight = 230,
		FloatHeight = 35,
		-- Floats in the UFO's beam in a wise sage pose (legs folded back,
		-- hands together). To use an animation instead, paste its id here
		-- ("rbxassetid://123...").
		PoseAnimationId = "",
		DropEvery = 9, -- seconds between throws from each UFO (two UFOs)
		BrainrotChance = 0.15,
		BrainrotLuck = 2,
		-- Sprinkles like his hat, rainbow like his pants.
		Mutations = { { Id = "Candy", Chance = 45 }, { Id = "Rainbow", Chance = 8 } },
		-- Alien colors: neon green, toxic lime, teal, and an alien purple.
		Colors = { Color3.fromRGB(70, 255, 120), Color3.fromRGB(190, 255, 70), Color3.fromRGB(0, 210, 180), Color3.fromRGB(170, 90, 255) },
		Chips = { "NIGHT FALLS", "NIGHT MUTATION", "SPRINKLE DROPS", "CASH BAGS" },
		Sky = "Green",
		Night = true,
		NightMutations = {
			{ Id = "Galaxy", Chance = 30, Boost = 5 },
			{ Id = "Radioactive", Chance = 25, Boost = 5 },
			{ Id = "Electric", Chance = 20, Boost = 5 },
			{ Id = "Void", Chance = 12, Boost = 6 },
			{ Id = "Cursed", Chance = 10, Boost = 6 },
			{ Id = "Divine", Chance = 3, Boost = 8 },
		},
		Alien = true,
		Chaos = true,
		-- Theme song: "Tractor Beam" (assets/music/alien_abduction_1_tractor_beam.mp3)
		MusicId = "rbxassetid://81256073930643",
	},
	Ace = {
		Founder = "Ace",
		Style = "Ballet",
		OutfitId = 0, -- his event look: Save My Event Look in the admin panel (or an outfit id)
		Title = "ACE'S ADMIN EVENT!",
		Subtitle = "Ace brought the ballet! x2 Luck and a guaranteed Ballerina Capuchina!",
		DurationMinutes = 5,
		Scale = 19, -- about 120 studs tall
		Spots = { Vector3.new(0, 0, 240), Vector3.new(0, 0, -240) },
		Luck = 2,
		-- Ace and his dancers throw cash bags and brainrots all event long.
		DropEvery = 8,
		BrainrotChance = 0.15,
		BrainrotLuck = 2,
		Guaranteed = "BallerinaCapuchina",
		Dancer = "CignaGlamourina",
		Colors = { Color3.fromRGB(255, 130, 200), Color3.fromRGB(255, 190, 230), Color3.fromRGB(230, 120, 255), Color3.fromRGB(255, 220, 240) },
		Chips = { "x2 LUCK", "BALLERINA GUARANTEED", "RARE MUTATION", "BALLET TIME" },
		Sky = "Pink",
		Water = true,
		-- Theme song (from Roblox's licensed music library). To use the
		-- original ballet track instead, upload assets/music/ballet_action.mp3
		-- and put its id here.
		MusicId = "rbxassetid://1836281845",
	},
	-- 99 Nights: any founder can start it, and it plays differently from the
	-- other events: nothing is thrown. The 67 Nights Deer hunts in the dark;
	-- when it screams, get to a campfire before it strikes. Survivors earn
	-- Shards, every night survived makes the whole server luckier, and
	-- supply chests hidden around the map hold cash or brainrots.
	Nights99 = {
		Founder = "The Deer",
		AnyFounder = true,
		EventName = "99 NIGHTS",
		Style = "Forest",
		Forest = true,
		OutfitId = 0,
		Title = "99 NIGHTS",
		Subtitle = "The deer hunts in the dark. When it screams, RUN TO A CAMPFIRE!",
		DurationMinutes = 5,
		Scale = 11, -- about 105 studs tall
		Spots = { Vector3.new(0, 0, 240), Vector3.new(0, 0, -240) },
		Colors = { Color3.fromRGB(150, 190, 255), Color3.fromRGB(220, 45, 55), Color3.fromRGB(70, 170, 100), Color3.fromRGB(255, 150, 50) },
		Chips = { "SURVIVE THE HUNT", "STAY BY THE FIRE", "SUPPLY CHESTS", "LUCK GROWS NIGHTLY" },
		Night = true,
	},
} :: { [string]: FounderEvent }

function Config.GetFounder(id: string): Founder?
	for _, founder in Config.Founders do
		if founder.Id == id then
			return founder
		end
	end
	return nil
end
-- A gift for every player who's online during admin abuse, at most once a
-- week (so starting it again the same week doesn't give a second one).
Config.AdminAbuseGift = {
	Shards = 100,
	BrainrotLuck = 3, -- one free brainrot, rolled with the same luck as Brainrot Rain
}

local WEEK = 7 * 24 * 3600

-- US rule: daylight time runs from the 2nd Sunday of March to the 1st Sunday
-- of November, switching at 2 AM local time.
local function isUsDaylightTime(t: { [string]: any }): boolean
	local month, day, weekday, hour = t.month, t.day, t.wday, t.hour
	if month > 3 and month < 11 then
		return true
	elseif month < 3 or month > 11 then
		return false
	end
	local lastSunday = day - (weekday - 1) -- date of the most recent Sunday
	if month == 3 then
		return lastSunday >= 8 and not (weekday == 1 and day <= 14 and hour < 2)
	end
	-- November: still daylight time until the first Sunday at 2 AM (1 AM standard).
	return lastSunday <= 0 or (weekday == 1 and day <= 7 and hour < 1)
end

-- Seconds to add to UTC to get the event's local time right now.
function Config.AdminAbuseUtcOffset(now: number): number
	local schedule = Config.AdminAbuse
	local offset = schedule.UtcOffset * 3600
	if schedule.UsDaylightSaving and isUsDaylightTime(os.date("!*t", math.floor(now + offset)) :: any) then
		offset += 3600
	end
	return offset
end

-- Returns "live" + seconds left, "soon" + seconds until it starts, or nil.
-- An admin can END this week's one early (the ReplicatedStorage attribute
-- "AdminAbuseSkipUntil" holds when the skipped one would have finished).
function Config.AdminAbuseStatus(now: number): (string?, number)
	local skipUntil = game:GetService("ReplicatedStorage"):GetAttribute("AdminAbuseSkipUntil")
	if type(skipUntil) == "number" and now < skipUntil then
		return nil, 0
	end
	local schedule = Config.AdminAbuse
	local t = os.date("!*t", math.floor(now + Config.AdminAbuseUtcOffset(now)))
	local intoWeek = (t.wday - 1) * 86400 + t.hour * 3600 + t.min * 60 + t.sec
	local start = (schedule.WeekDay - 1) * 86400 + schedule.Hour * 3600 + schedule.Minute * 60
	local duration = schedule.DurationMinutes * 60
	local untilStart = (start - intoWeek) % WEEK
	local sinceStart = (intoWeek - start) % WEEK
	if sinceStart < duration then
		return "live", duration - sinceStart
	elseif untilStart <= schedule.CountdownMinutes * 60 then
		return "soon", untilStart
	end
	return nil, 0
end

-- The only one who can give limited brainrots from the admin panel (a
-- founder Id). Each gift comes out of the shop stock.
Config.LimitedGiver = "Corny"

-- How often every server re-checks the shared stock (the signs count down
-- to it). Sales and gifts in your own server show up right away.
Config.LimitedRefreshSeconds = 300

-- "4:12" until the next stock update (`nextAt` is a unix time).
function Config.StockCountdown(nextAt: number?, now: number): string
	local left = math.max(0, math.floor((nextAt or now) - now))
	return string.format("%d:%02d", left // 60, left % 60)
end

Config.LimitedItems = {
	CignaGlamourina = { ProductId = 0, GamePassId = 2021528297, PriceRobux = 49, Stock = 500, Reserved = 2 },
	SixtySevenNights = { ProductId = 0, GamePassId = 2023520328, PriceRobux = 49, Stock = 1000, Reserved = 2 },
} :: { [string]: LimitedItem }

-- Whether a limited item can be bought yet (it has a product or a gamepass).
function Config.LimitedOnSale(item: LimitedItem): boolean
	return item.ProductId ~= 0 or (item.GamePassId or 0) ~= 0
end

-- Admin drops: what the "Brainrot Rain" and "Cash Rain" buttons drop.
Config.BrainrotRainCount = 5
Config.BrainrotRainLuck = 3 -- rain is luckier than the conveyor
Config.CashRainCount = 10
Config.DropLifetime = 90 -- seconds before an unclaimed drop disappears

-- Monetization -------------------------------------------------------------
-- Create these on the Creator Dashboard (your experience > Monetization),
-- then paste the IDs below. Items with Id = 0 show as "coming soon".
-- Prices are set on the dashboard (the shop reads them from Roblox).
-- Prices on the dashboard: 2x Cash 179, VIP 249, Infinite Laser Door 349.

Config.GamePasses = {
	{ Key = "DoubleCash", Id = 2023580373, Name = "2x Cash", Description = "Your brainrots make double cash forever." },
	{ Key = "VIP", Id = 2022590341, Name = "VIP", Description = "+2 base slots, 2 extra floors to buy, a gold crown + VIP tag, and the VIP Royale skin (velvet stairs, VIP throne and VIP vault)." },
	{ Key = "InfiniteLock", Id = 2022050385, Name = "Infinite Laser Door", Description = "Your base lasers stay on forever. Nobody can steal from you." },
} :: { GamePass }

Config.Products = {
	{ Key = "SmallCash", Id = 3717405260, Name = "Cash Bag", Description = "10 minutes of your income (at least $1K)." },
	{ Key = "BigCash", Id = 3717405370, Name = "Cash Vault", Description = "1 hour of your income (at least $25K)." },
	{ Key = "ServerLuck", Id = 3717405184, Name = "Server Luck", Description = "More Rare+ spawns for EVERYONE for 15 minutes." },
} :: { Product }

-- Codes typed into the box at the bottom of the shop. Each works once per
-- player. Add new ones here (letters are matched without caring about caps);
-- Expires is optional (unix time, e.g. from https://www.epochconverter.com).
export type Code = { Code: string, Shards: number?, Cash: number?, Expires: number? }
-- Corny can also make codes in-game (admin panel > FOUNDER > CODES); those
-- are saved for every server. Only this founder can make or delete them.
Config.CodeMaker = "Corny"
-- Most a code made in-game can give (keeps Shards worth earning).
Config.CodeLimits = { Cash = 1e15, Shards = 5000 }

Config.Codes = {
	{ Code = "RELEASE", Shards = 150 },
	{ Code = "CORNY", Cash = 5000 },
} :: { Code }

Config.SmallCashMinutes = 10
Config.SmallCashMinimum = 1000
Config.BigCashMinutes = 60
Config.BigCashMinimum = 25000

-- Lookup helpers -----------------------------------------------------------

local byId: { [string]: Brainrot } = {}
local byRarity: { [RarityId]: { Brainrot } } = {}
-- The conveyor's pools leave out limited (Robux) brainrots: those only come
-- from the shop or a gift, with a serial number. Free (Price 0) brainrots are
-- left out too: they ride the conveyor on their own rhythm (FreeConveyorEvery)
-- and never come from drops or gifts.
local conveyorByRarity: { [RarityId]: { Brainrot } } = {}
local freeBrainrots: { Brainrot } = {}
for _, brainrot in Config.Brainrots do
	byId[brainrot.Id] = brainrot
	local list = byRarity[brainrot.Rarity]
	if not list then
		list = {}
		byRarity[brainrot.Rarity] = list
	end
	table.insert(list, brainrot)
	if brainrot.Price <= 0 and not brainrot.Limited and not Config.Rarities[brainrot.Rarity].EventOnly then
		table.insert(freeBrainrots, brainrot)
	elseif not brainrot.Limited then
		conveyorByRarity[brainrot.Rarity] = conveyorByRarity[brainrot.Rarity] or {}
		table.insert(conveyorByRarity[brainrot.Rarity], brainrot)
	end
end

-- A random free brainrot for the conveyor, if there are any.
function Config.RollFree(rng: Random): Brainrot?
	if #freeBrainrots == 0 then
		return nil
	end
	return freeBrainrots[rng:NextInteger(1, #freeBrainrots)]
end

function Config.GetBrainrot(id: string): Brainrot?
	return byId[id]
end

function Config.GetGamePass(key: string): GamePass?
	for _, pass in Config.GamePasses do
		if pass.Key == key then
			return pass
		end
	end
	return nil
end

local mutationsById: { [string]: Mutation } = {}
local mutationOrder: { [string]: number } = {}
for i, mutation in Config.Mutations do
	mutationsById[mutation.Id] = mutation
	mutationOrder[mutation.Id] = i
end

-- Mutations stack: a brainrot can have up to Config.MaxMutations of them,
-- written "Gold+Galaxy" (always in Config.Mutations order, rarest last).
Config.MaxMutations = 3
-- After a mutation rolls, the chance another one rolls on top of it (and
-- again for a third).
Config.MutationStackChance = 0.12

-- Every mutation in a stack, commonest first.
function Config.SplitMutations(id: string?): { Mutation }
	local list: { Mutation } = {}
	if id then
		for part in string.gmatch(id, "[^+]+") do
			local mutation = mutationsById[part]
			if mutation and not table.find(list, mutation) and #list < Config.MaxMutations then
				table.insert(list, mutation)
			end
		end
		table.sort(list, function(x: Mutation, y: Mutation): boolean
			return mutationOrder[x.Id] < mutationOrder[y.Id]
		end)
	end
	return list
end

-- Builds a stack id from mutation ids (drops unknown ones and repeats).
function Config.JoinMutations(ids: { string }): string?
	local list = Config.SplitMutations(table.concat(ids, "+"))
	if #list == 0 then
		return nil
	end
	local parts = {}
	for _, mutation in list do
		table.insert(parts, mutation.Id)
	end
	return table.concat(parts, "+")
end

-- The rarest mutation of a stack (its color and look lead), or nil.
function Config.GetMutation(id: string?): Mutation?
	local list = Config.SplitMutations(id)
	return list[#list]
end

-- Each mutation adds a percentage of the base income and price
-- (Gold +100%, Galaxy +600%, Divine +1400%); a stack adds them all up.
function Config.MutationBonus(mutation: Mutation): number
	return math.floor((mutation.Multiplier - 1) * 100 + 0.5)
end

local function mutationMultiplier(mutationId: string?): number
	local multiplier = 1
	for _, mutation in Config.SplitMutations(mutationId) do
		multiplier += mutation.Multiplier - 1
	end
	return multiplier
end

-- "Gold Galaxy" for a stack (empty when there's no mutation).
function Config.MutationLabel(id: string?): string
	local names = {}
	for _, mutation in Config.SplitMutations(id) do
		table.insert(names, mutation.DisplayName)
	end
	return table.concat(names, " ")
end

-- Exclusive mutations (like Magic) only go on the brainrots they name.
function Config.MutationAllowed(brainrot: Brainrot, mutationId: string?): boolean
	local list = Config.SplitMutations(mutationId)
	if #list == 0 then
		return mutationId == nil
	end
	for _, mutation in list do
		if mutation.Exclusive and not table.find(mutation.Exclusive, brainrot.Id) then
			return false
		end
	end
	return true
end

function Config.PriceOf(brainrot: Brainrot, mutationId: string?): number
	return brainrot.Price * mutationMultiplier(mutationId)
end

-- The whole game's earning speed: every brainrot earns this share of its
-- listed Income (prices stay the same, so everything takes longer to afford).
Config.IncomeScale = 0.6

-- `rebirths` only matters for brainrots with IncomeGrowth.
-- Capped far past anything the economy reaches, so a huge rebirth count
-- (event brainrots double every rebirth) can't overflow to infinity.
Config.MaxIncome = 1e45

function Config.IncomeOf(brainrot: Brainrot, mutationId: string?, rebirths: number?): number
	local growth = if brainrot.IncomeGrowth then brainrot.IncomeGrowth ^ math.min(rebirths or 0, 150) else 1
	local income = brainrot.Income * Config.IncomeScale * mutationMultiplier(mutationId) * growth
	return if income ~= income then 0 else math.min(income, Config.MaxIncome)
end

function Config.SellValue(brainrot: Brainrot, mutationId: string?): number
	return math.floor(Config.PriceOf(brainrot, mutationId) * Config.SellRatio)
end

-- Saved brainrots are stored as "Id", "Id:Mutation" or "Id:Mutation:Serial"
-- (limited ones carry a serial number, e.g. "CignaGlamourina::17").
function Config.Encode(id: string, mutationId: string?, serial: number?): string
	if serial then
		return id .. ":" .. (mutationId or "") .. ":" .. serial
	end
	return if mutationId then id .. ":" .. mutationId else id
end

function Config.Decode(entry: string): (Brainrot?, string?, number?)
	local id, rest = string.match(entry, "^([^:]+):?(.*)$")
	local mutationId, serialText = string.match(rest or "", "^([^:]*):?(.*)$")
	local brainrot = id and byId[id]
	-- Exclusive mutations (Magic) are dropped from brainrots that can't have them.
	local kept = {}
	for _, mutation in Config.SplitMutations(mutationId) do
		if not mutation.Exclusive or (brainrot and table.find(mutation.Exclusive, brainrot.Id)) then
			table.insert(kept, mutation.Id)
		end
	end
	local serial = tonumber(serialText)
	return brainrot, Config.JoinMutations(kept), if serial then math.floor(serial) else nil
end

-- Rolls a mutation (or nil) for a conveyor spawn.
-- `boost`: one mutation made more likely (tonight's night mutation).
local function rollOne(rng: Random, luck: number, boost: { Id: string, Multiplier: number }?): string?
	local roll = rng:NextNumber(0, 100)
	-- Rarest first, so luck can't push a common mutation past a rare one.
	for i = #Config.Mutations, 1, -1 do
		local mutation = Config.Mutations[i]
		if not mutation.Exclusive then
			local extra = if boost and boost.Id == mutation.Id then boost.Multiplier else 1
			roll -= mutation.Chance * luck * extra
			if roll < 0 then
				return mutation.Id
			end
		end
	end
	return nil
end

-- Rolls a mutation stack (or nil): one mutation at the normal odds, then a
-- small chance of another stacking on top (Config.MutationStackChance).
function Config.RollMutation(rng: Random, luck: number, boost: { Id: string, Multiplier: number }?): string?
	local first = rollOne(rng, luck, boost)
	if not first then
		return nil
	end
	local ids = { first }
	while #ids < Config.MaxMutations and rng:NextNumber() < Config.MutationStackChance do
		local extra = rollOne(rng, math.max(luck, 1) * 6, boost)
		if not extra or table.find(ids, extra) then
			break
		end
		table.insert(ids, extra)
	end
	return Config.JoinMutations(ids)
end

function Config.RebirthCost(rebirths: number): number
	return Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths
end

function Config.RebirthMultiplier(rebirths: number): number
	return 1 + rebirths * Config.RebirthBonus
end

-- Picks a random brainrot for the conveyor. Luck boosts every rarity above
-- Common. Event-only rarities can only roll while `eventLive` is true.
function Config.RollConveyor(rng: Random, luck: number, eventLive: boolean?): Brainrot
	local total = 0
	local weights: { [RarityId]: number } = {}
	for _, rarityId: RarityId in rarityOrder do
		local rarity = Config.Rarities[rarityId]
		local weight = rarity.SpawnWeight
		if rarity.Order > 1 then
			weight *= luck
		end
		if rarity.EventOnly and not eventLive then
			weight = 0
		end
		if conveyorByRarity[rarityId] and weight > 0 then
			weights[rarityId] = weight
			total += weight
		end
	end

	local roll = rng:NextNumber(0, total)
	local chosen: RarityId = "Common"
	for _, rarityId: RarityId in rarityOrder do
		local weight = weights[rarityId]
		if weight then
			chosen = rarityId
			roll -= weight
			if roll < 0 then
				break
			end
		end
	end

	local pool = conveyorByRarity[chosen]
	return pool[rng:NextInteger(1, #pool)]
end

-- Cash never goes above this (far past anything the economy reaches), so
-- it always saves and shows correctly.
Config.MaxCash = 1e60

function Config.FormatNumber(n: number): string
	if n ~= n then
		return "0"
	elseif math.abs(n) == math.huge then
		return if n > 0 then "∞" else "-∞"
	end
	n = math.floor(n)
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc", "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg" }
	local i = 1
	local value = n
	while math.abs(value) >= 1000 and i < #suffixes do
		value /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(n)
	end
	return string.format("%.1f%s", value, suffixes[i])
end

function Config.FormatCash(n: number): string
	return "$" .. Config.FormatNumber(n)
end

return Config
