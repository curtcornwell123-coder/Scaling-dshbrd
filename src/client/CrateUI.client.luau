--!strict
-- Crate Rush client: HUD, crate shop, pet inventory and the spinning reel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local GetData = Remotes:WaitForChild("GetData") :: RemoteFunction
local RequestOpen = Remotes:WaitForChild("RequestOpen") :: RemoteEvent
local ToggleEquip = Remotes:WaitForChild("ToggleEquip") :: RemoteEvent
local EquipBest = Remotes:WaitForChild("EquipBest") :: RemoteEvent
local SellPet = Remotes:WaitForChild("SellPet") :: RemoteEvent
local DataUpdated = Remotes:WaitForChild("DataUpdated") :: RemoteEvent
local CoinsUpdated = Remotes:WaitForChild("CoinsUpdated") :: RemoteEvent
local CrateResult = Remotes:WaitForChild("CrateResult") :: RemoteEvent
local Announce = Remotes:WaitForChild("Announce") :: RemoteEvent
local Notify = Remotes:WaitForChild("Notify") :: RemoteEvent

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local FONT = Enum.Font.FredokaOne
local DARK = Color3.fromRGB(28, 30, 40)
local DARKER = Color3.fromRGB(18, 19, 26)
local WHITE = Color3.new(1, 1, 1)
local COIN = Color3.fromRGB(255, 220, 90)

-- State --------------------------------------------------------------------

type InventoryEntry = { Uid: string, PetId: string }
type Snapshot = {
	Coins: number,
	CoinsPerSecond: number,
	Inventory: { InventoryEntry },
	Equipped: { string },
	Opened: number,
	Mythics: number,
	MaxEquipped: number,
	MaxInventory: number,
}

local data: Snapshot? = nil
local selectedUid: string? = nil
local spinning = false
local resultQueue: { { crateId: string, petId: string } } = {}

-- UI helpers ---------------------------------------------------------------

local function create(className: string, props: { [string]: any }, children: { Instance }?): any
	local inst = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			(inst :: any)[key] = value
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(radius: number?): UICorner
	return create("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

local function stroke(color: Color3, thickness: number?): UIStroke
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
	}
	for k, v in props do
		if k ~= "MaxText" then
			defaults[k] = v
		end
	end
	local l = create("TextLabel", defaults)
	create("UITextSizeConstraint", { MaxTextSize = props.MaxText or 40, Parent = l })
	return l
end

local function button(props: { [string]: any }): TextButton
	local defaults = {
		AutoButtonColor = true,
		Font = FONT,
		TextColor3 = WHITE,
		TextScaled = true,
	}
	for k, v in props do
		if k ~= "MaxText" then
			defaults[k] = v
		end
	end
	local b = create("TextButton", defaults, { corner(10) })
	create("UITextSizeConstraint", { MaxTextSize = props.MaxText or 28, Parent = b })
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 4),
		Parent = b,
	})
	return b
end

local tickSound = create("Sound", {
	SoundId = "rbxasset://sounds/electronicpingshort.wav",
	Volume = 0.25,
	Parent = SoundService,
})

local function playTick()
	SoundService:PlayLocalSound(tickSound)
end

-- Root ---------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "CrateRushUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = playerGui,
})

-- HUD ------------------------------------------------------------------------

local hud = create("Frame", {
	Name = "HUD",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 52),
	Size = UDim2.fromOffset(300, 70),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.15,
	Parent = gui,
}, { corner(16), stroke(COIN, 2) })

local coinsLabel = label({
	Size = UDim2.new(1, -20, 0.6, 0),
	Position = UDim2.fromOffset(10, 4),
	Text = "💰 0",
	TextColor3 = COIN,
	MaxText = 36,
	Parent = hud,
})

local cpsLabel = label({
	Size = UDim2.new(1, -20, 0.35, 0),
	Position = UDim2.new(0, 10, 0.6, 0),
	Text = "+0 / sec",
	TextColor3 = Color3.fromRGB(200, 255, 200),
	MaxText = 20,
	Parent = hud,
})

local sideBar = create("Frame", {
	Name = "SideBar",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(110, 240),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	create("UIListLayout", {
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
})

local cratesButton = button({
	Size = UDim2.fromOffset(110, 70),
	BackgroundColor3 = Color3.fromRGB(255, 160, 40),
	Text = "🎁 Crates",
	LayoutOrder = 1,
	Parent = sideBar,
})
stroke(WHITE, 2).Parent = cratesButton

local petsButton = button({
	Size = UDim2.fromOffset(110, 70),
	BackgroundColor3 = Color3.fromRGB(60, 170, 255),
	Text = "🐾 Pets",
	LayoutOrder = 2,
	Parent = sideBar,
})
stroke(WHITE, 2).Parent = petsButton

-- Toasts -------------------------------------------------------------------

local toastHolder = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 130),
	Size = UDim2.new(0.9, 0, 0, 200),
	BackgroundTransparency = 1,
	ZIndex = 50,
	Parent = gui,
}, {
	create("UISizeConstraint", { MaxSize = Vector2.new(560, 200) }),
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local function toast(text: string, color: Color3?, duration: number?)
	local frame = create("Frame", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = DARKER,
		BackgroundTransparency = 0.1,
		ZIndex = 50,
		Parent = toastHolder,
	}, { corner(10), stroke(color or WHITE, 2) })
	label({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		Text = text,
		TextColor3 = color or WHITE,
		MaxText = 22,
		ZIndex = 51,
		Parent = frame,
	})
	task.delay(duration or 3, function()
		frame:Destroy()
	end)
end

-- Panels -------------------------------------------------------------------

local function panel(name: string, title: string, accent: Color3): (Frame, Frame)
	local frame = create("Frame", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.8, 0.7),
		BackgroundColor3 = DARK,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	}, {
		corner(18),
		stroke(accent, 3),
		create("UISizeConstraint", { MaxSize = Vector2.new(900, 560), MinSize = Vector2.new(320, 300) }),
	})
	label({
		Size = UDim2.new(1, -120, 0, 44),
		Position = UDim2.fromOffset(16, 8),
		Text = title,
		TextColor3 = accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxText = 34,
		ZIndex = 11,
		Parent = frame,
	})
	local close = button({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.fromOffset(40, 40),
		BackgroundColor3 = Color3.fromRGB(220, 60, 70),
		Text = "X",
		ZIndex = 11,
		Parent = frame,
	})
	close.Activated:Connect(function()
		frame.Visible = false
	end)
	local body = create("Frame", {
		Name = "Body",
		Position = UDim2.fromOffset(12, 60),
		Size = UDim2.new(1, -24, 1, -72),
		BackgroundTransparency = 1,
		ZIndex = 11,
		Parent = frame,
	})
	return frame, body
end

-- Crate shop ---------------------------------------------------------------

local shopFrame, shopBody = panel("CrateShop", "🎁 Crate Shop", Color3.fromRGB(255, 160, 40))

local shopScroll = create("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	CanvasSize = UDim2.new(),
	ScrollingDirection = Enum.ScrollingDirection.X,
	ZIndex = 11,
	Parent = shopBody,
}, {
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local openButtons: { [string]: TextButton } = {}

for i, crate in Config.Crates do
	local card = create("Frame", {
		Name = crate.Id,
		Size = UDim2.new(0, 200, 1, -10),
		BackgroundColor3 = DARKER,
		LayoutOrder = i,
		ZIndex = 12,
		Parent = shopScroll,
	}, { corner(14), stroke(crate.Color, 3) })

	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 90),
		BackgroundColor3 = crate.Color,
		ZIndex = 13,
		Parent = card,
	}, { corner(14) })
	label({
		Size = UDim2.new(1, -12, 0, 50),
		Position = UDim2.fromOffset(6, 4),
		Text = "📦",
		MaxText = 44,
		ZIndex = 14,
		Parent = header,
	})
	label({
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.fromOffset(6, 54),
		Text = crate.DisplayName,
		TextStrokeTransparency = 0.3,
		MaxText = 26,
		ZIndex = 14,
		Parent = header,
	})

	local oddsList = create("Frame", {
		Position = UDim2.fromOffset(10, 100),
		Size = UDim2.new(1, -20, 1, -170),
		BackgroundTransparency = 1,
		ZIndex = 13,
		Parent = card,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for order, rarityId in Config.RarityOrder do
		local chance = crate.Odds[rarityId] or 0
		local rarity = Config.Rarities[rarityId]
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0.19, 0),
			BackgroundTransparency = 1,
			LayoutOrder = order,
			ZIndex = 13,
			Parent = oddsList,
		})
		label({
			Size = UDim2.fromScale(0.65, 1),
			Text = rarity.DisplayName,
			TextColor3 = rarity.Color,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTransparency = chance > 0 and 0 or 0.6,
			MaxText = 18,
			ZIndex = 14,
			Parent = row,
		})
		label({
			Position = UDim2.fromScale(0.65, 0),
			Size = UDim2.fromScale(0.35, 1),
			Text = (chance > 0 and chance < 1) and string.format("%.1f%%", chance) or string.format("%d%%", chance),
			TextColor3 = rarity.Color,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTransparency = chance > 0 and 0 or 0.6,
			MaxText = 18,
			ZIndex = 14,
			Parent = row,
		})
	end

	local open = button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -20, 0, 50),
		BackgroundColor3 = crate.Color,
		Text = "Open 💰" .. Config.FormatNumber(crate.Price),
		TextStrokeTransparency = 0.3,
		ZIndex = 14,
		Parent = card,
	})
	openButtons[crate.Id] = open
	open.Activated:Connect(function()
		if spinning then
			return
		end
		if data and data.Coins < crate.Price then
			toast("Not enough coins! Equip pets to earn faster.", Color3.fromRGB(255, 120, 120))
			return
		end
		RequestOpen:FireServer(crate.Id)
	end)
end

-- Pet inventory ------------------------------------------------------------

local petsFrame, petsBody = panel("Pets", "🐾 Your Pets", Color3.fromRGB(60, 170, 255))

local petsHeader = create("Frame", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	ZIndex = 11,
	Parent = petsBody,
})

local petsCountLabel = label({
	Size = UDim2.new(0.5, 0, 1, 0),
	Text = "Pets 0/0  •  Equipped 0/0",
	TextXAlignment = Enum.TextXAlignment.Left,
	MaxText = 20,
	ZIndex = 12,
	Parent = petsHeader,
})

local equipBestButton = button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.fromScale(1, 0),
	Size = UDim2.new(0, 150, 1, 0),
	BackgroundColor3 = Color3.fromRGB(70, 200, 90),
	Text = "⭐ Equip Best",
	ZIndex = 12,
	Parent = petsHeader,
})
equipBestButton.Activated:Connect(function()
	EquipBest:FireServer()
end)

local petsGrid = create("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 54),
	Size = UDim2.new(0.62, -6, 1, -54),
	BackgroundColor3 = DARKER,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	ZIndex = 11,
	Parent = petsBody,
}, {
	corner(12),
	create("UIPadding", {
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
	}),
	create("UIGridLayout", {
		CellSize = UDim2.fromOffset(92, 92),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local detail = create("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 54),
	Size = UDim2.new(0.38, -6, 1, -54),
	BackgroundColor3 = DARKER,
	ZIndex = 11,
	Parent = petsBody,
}, { corner(12) })

local detailName = label({
	Position = UDim2.fromOffset(10, 10),
	Size = UDim2.new(1, -20, 0, 36),
	Text = "Select a pet",
	MaxText = 28,
	ZIndex = 12,
	Parent = detail,
})
local detailRarity = label({
	Position = UDim2.fromOffset(10, 48),
	Size = UDim2.new(1, -20, 0, 26),
	Text = "",
	MaxText = 22,
	ZIndex = 12,
	Parent = detail,
})
local detailPower = label({
	Position = UDim2.fromOffset(10, 78),
	Size = UDim2.new(1, -20, 0, 26),
	Text = "",
	TextColor3 = Color3.fromRGB(200, 255, 200),
	MaxText = 20,
	ZIndex = 12,
	Parent = detail,
})
local equipButton = button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -66),
	Size = UDim2.new(1, -20, 0, 46),
	BackgroundColor3 = Color3.fromRGB(60, 170, 255),
	Text = "Equip",
	Visible = false,
	ZIndex = 12,
	Parent = detail,
})
local sellButton = button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -20, 0, 46),
	BackgroundColor3 = Color3.fromRGB(220, 60, 70),
	Text = "Sell",
	Visible = false,
	ZIndex = 12,
	Parent = detail,
})

local function findEntry(uid: string?): InventoryEntry?
	if not data or not uid then
		return nil
	end
	for _, entry in data.Inventory do
		if entry.Uid == uid then
			return entry
		end
	end
	return nil
end

local function isEquipped(uid: string): boolean
	return data ~= nil and table.find(data.Equipped, uid) ~= nil
end

local function refreshDetail()
	local entry = findEntry(selectedUid)
	local pet = entry and Config.GetPet(entry.PetId)
	if not entry or not pet then
		selectedUid = nil
		detailName.Text = "Select a pet"
		detailName.TextColor3 = WHITE
		detailRarity.Text = ""
		detailPower.Text = ""
		equipButton.Visible = false
		sellButton.Visible = false
		return
	end
	local rarity = Config.Rarities[pet.Rarity]
	detailName.Text = pet.DisplayName
	detailName.TextColor3 = rarity.Color
	detailRarity.Text = rarity.DisplayName
	detailRarity.TextColor3 = rarity.Color
	detailPower.Text = "+" .. Config.FormatNumber(pet.Power) .. " coins/sec"
	equipButton.Visible = true
	equipButton.Text = isEquipped(entry.Uid) and "Unequip" or "Equip"
	sellButton.Visible = true
	sellButton.Text = "Sell 💰" .. Config.FormatNumber(Config.SellValue(pet))
end

equipButton.Activated:Connect(function()
	if selectedUid then
		ToggleEquip:FireServer(selectedUid)
	end
end)

local sellConfirmUid: string? = nil
sellButton.Activated:Connect(function()
	local entry = findEntry(selectedUid)
	local pet = entry and Config.GetPet(entry.PetId)
	if not entry or not pet then
		return
	end
	-- Ask for a second click before selling anything Epic or better.
	if Config.Rarities[pet.Rarity].Order >= 3 and sellConfirmUid ~= entry.Uid then
		sellConfirmUid = entry.Uid
		sellButton.Text = "Tap again to sell!"
		task.delay(2, function()
			if sellConfirmUid == entry.Uid then
				sellConfirmUid = nil
				refreshDetail()
			end
		end)
		return
	end
	sellConfirmUid = nil
	SellPet:FireServer(entry.Uid)
end)

local function rebuildPets()
	for _, child in petsGrid:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not data then
		return
	end

	petsCountLabel.Text = string.format(
		"Pets %d/%d  •  Equipped %d/%d",
		#data.Inventory,
		data.MaxInventory,
		#data.Equipped,
		data.MaxEquipped
	)

	local entries = table.clone(data.Inventory)
	table.sort(entries, function(a, b)
		local pa, pb = Config.GetPet(a.PetId), Config.GetPet(b.PetId)
		local ea, eb = isEquipped(a.Uid), isEquipped(b.Uid)
		if ea ~= eb then
			return ea
		end
		if pa and pb and pa.Power ~= pb.Power then
			return pa.Power > pb.Power
		end
		return (tonumber(a.Uid) or 0) > (tonumber(b.Uid) or 0)
	end)

	for order, entry in entries do
		local pet = Config.GetPet(entry.PetId)
		if pet then
			local rarity = Config.Rarities[pet.Rarity]
			local tile = create("TextButton", {
				Text = "",
				AutoButtonColor = true,
				BackgroundColor3 = rarity.Color:Lerp(DARKER, 0.55),
				LayoutOrder = order,
				ZIndex = 12,
				Parent = petsGrid,
			}, { corner(10), stroke(selectedUid == entry.Uid and WHITE or rarity.Color, selectedUid == entry.Uid and 3 or 2) })
			label({
				Position = UDim2.fromOffset(4, 6),
				Size = UDim2.new(1, -8, 0.5, 0),
				Text = pet.DisplayName,
				TextColor3 = rarity.Color:Lerp(WHITE, 0.4),
				TextStrokeTransparency = 0.4,
				MaxText = 18,
				ZIndex = 13,
				Parent = tile,
			})
			label({
				Position = UDim2.new(0, 4, 0.55, 0),
				Size = UDim2.new(1, -8, 0.3, 0),
				Text = "+" .. Config.FormatNumber(pet.Power) .. "/s",
				TextColor3 = Color3.fromRGB(200, 255, 200),
				MaxText = 16,
				ZIndex = 13,
				Parent = tile,
			})
			if isEquipped(entry.Uid) then
				label({
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -2, 0, -4),
					Size = UDim2.fromOffset(26, 26),
					Text = "✅",
					ZIndex = 14,
					Parent = tile,
				})
			end
			tile.Activated:Connect(function()
				selectedUid = entry.Uid
				sellConfirmUid = nil
				rebuildPets()
			end)
		end
	end
	refreshDetail()
end

-- Panel toggles ------------------------------------------------------------

cratesButton.Activated:Connect(function()
	petsFrame.Visible = false
	shopFrame.Visible = not shopFrame.Visible
end)
petsButton.Activated:Connect(function()
	shopFrame.Visible = false
	petsFrame.Visible = not petsFrame.Visible
	if petsFrame.Visible then
		rebuildPets()
	end
end)

-- Opening reel -------------------------------------------------------------

local TILE_W = 120
local TILE_GAP = 10
local STEP = TILE_W + TILE_GAP
local REEL_TILES = 50
local WIN_INDEX = 44
local SPIN_TIME = 5.5

local overlay = create("Frame", {
	Name = "Opening",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.35,
	Visible = false,
	ZIndex = 30,
	Parent = gui,
})

local flash = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = WHITE,
	BackgroundTransparency = 1,
	ZIndex = 45,
	Parent = overlay,
})

local reelTitle = label({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 0.5, -100),
	Size = UDim2.new(0.8, 0, 0, 50),
	Text = "Opening...",
	MaxText = 40,
	TextStrokeTransparency = 0.3,
	ZIndex = 31,
	Parent = overlay,
})

local reelWindow = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0.92, 0, 0, 150),
	BackgroundColor3 = DARKER,
	ClipsDescendants = true,
	ZIndex = 31,
	Parent = overlay,
}, {
	corner(14),
	stroke(WHITE, 3),
	create("UISizeConstraint", { MaxSize = Vector2.new(820, 150) }),
})

local reelStrip = create("Frame", {
	Size = UDim2.new(0, REEL_TILES * STEP, 1, -20),
	Position = UDim2.fromOffset(0, 10),
	BackgroundTransparency = 1,
	ZIndex = 32,
	Parent = reelWindow,
})

local marker = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 4, 1, 10),
	BackgroundColor3 = COIN,
	BorderSizePixel = 0,
	ZIndex = 40,
	Parent = reelWindow,
})

local resultCard = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 95),
	Size = UDim2.fromOffset(320, 150),
	BackgroundColor3 = DARK,
	Visible = false,
	ZIndex = 31,
	Parent = overlay,
}, { corner(16) })
local resultStroke = stroke(WHITE, 3)
resultStroke.Parent = resultCard

local resultRarity = label({
	Position = UDim2.fromOffset(10, 8),
	Size = UDim2.new(1, -20, 0, 30),
	Text = "",
	MaxText = 26,
	ZIndex = 32,
	Parent = resultCard,
})
local resultName = label({
	Position = UDim2.fromOffset(10, 38),
	Size = UDim2.new(1, -20, 0, 40),
	Text = "",
	MaxText = 34,
	TextStrokeTransparency = 0.3,
	ZIndex = 32,
	Parent = resultCard,
})
local resultButton = button({
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(0.7, 0, 0, 46),
	BackgroundColor3 = Color3.fromRGB(70, 200, 90),
	Text = "Awesome!",
	ZIndex = 32,
	Parent = resultCard,
})

local function makeReelTile(pet: Config.Pet, index: number)
	local rarity = Config.Rarities[pet.Rarity]
	local tile = create("Frame", {
		Position = UDim2.fromOffset((index - 1) * STEP, 0),
		Size = UDim2.new(0, TILE_W, 1, 0),
		BackgroundColor3 = rarity.Color:Lerp(DARKER, 0.45),
		ZIndex = 33,
		Parent = reelStrip,
	}, { corner(10), stroke(rarity.Color, 3) })
	label({
		Position = UDim2.fromOffset(6, 8),
		Size = UDim2.new(1, -12, 0.55, 0),
		Text = pet.DisplayName,
		TextStrokeTransparency = 0.3,
		MaxText = 22,
		ZIndex = 34,
		Parent = tile,
	})
	label({
		Position = UDim2.new(0, 6, 0.65, 0),
		Size = UDim2.new(1, -12, 0.28, 0),
		Text = rarity.DisplayName,
		TextColor3 = rarity.Color:Lerp(WHITE, 0.3),
		MaxText = 16,
		ZIndex = 34,
		Parent = tile,
	})
end

local cosmeticRng = Random.new()

local function playOpening(crateId: string, petId: string)
	local crate = Config.GetCrate(crateId)
	local won = Config.GetPet(petId)
	if not crate or not won then
		return
	end
	local rarity = Config.Rarities[won.Rarity]

	shopFrame.Visible = false
	petsFrame.Visible = false
	overlay.Visible = true
	resultCard.Visible = false
	reelTitle.Text = crate.DisplayName
	reelTitle.TextColor3 = crate.Color

	for _, child in reelStrip:GetChildren() do
		child:Destroy()
	end
	for i = 1, REEL_TILES do
		local pet = if i == WIN_INDEX then won else Config.Roll(crate, cosmeticRng)
		makeReelTile(pet, i)
	end

	-- Land the winning tile under the marker, slightly off-centre for suspense.
	task.wait() -- let layout compute the window's size after becoming visible
	local windowWidth = reelWindow.AbsoluteSize.X
	local jitter = cosmeticRng:NextNumber(-TILE_W * 0.4, TILE_W * 0.4)
	local startX = windowWidth / 2 - TILE_W / 2
	local endX = windowWidth / 2 - ((WIN_INDEX - 1) * STEP + TILE_W / 2) + jitter
	reelStrip.Position = UDim2.fromOffset(startX, 10)

	local tween = TweenService:Create(
		reelStrip,
		TweenInfo.new(SPIN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Position = UDim2.fromOffset(endX, 10) }
	)

	local lastIndex = -1
	local tickConn = RunService.RenderStepped:Connect(function()
		local offset = windowWidth / 2 - reelStrip.Position.X.Offset
		local index = math.floor(offset / STEP)
		if index ~= lastIndex then
			lastIndex = index
			playTick()
		end
	end)

	tween:Play()
	tween.Completed:Wait()
	tickConn:Disconnect()

	-- Reveal
	resultRarity.Text = rarity.DisplayName:upper() .. "!"
	resultRarity.TextColor3 = rarity.Color
	resultName.Text = won.DisplayName
	resultName.TextColor3 = rarity.Color
	resultStroke.Color = rarity.Color
	marker.BackgroundColor3 = rarity.Color
	resultCard.Visible = true

	if rarity.Order >= 4 then
		flash.BackgroundColor3 = rarity.Color
		flash.BackgroundTransparency = 0.1
		TweenService:Create(flash, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
	end

	local closed = false
	local conn = resultButton.Activated:Connect(function()
		closed = true
	end)
	local deadline = os.clock() + 8
	while not closed and os.clock() < deadline do
		task.wait()
	end
	conn:Disconnect()

	marker.BackgroundColor3 = COIN
	overlay.Visible = false
end

local function processQueue()
	if spinning then
		return
	end
	spinning = true
	while #resultQueue > 0 do
		local nextResult = table.remove(resultQueue, 1) :: { crateId: string, petId: string }
		playOpening(nextResult.crateId, nextResult.petId)
	end
	spinning = false
end

-- Network ------------------------------------------------------------------

local function applyCoins(coins: number, cps: number)
	coinsLabel.Text = "💰 " .. Config.FormatNumber(coins)
	cpsLabel.Text = "+" .. Config.FormatNumber(cps) .. " / sec"
	for _, crate in Config.Crates do
		local open = openButtons[crate.Id]
		if open then
			open.BackgroundColor3 = coins >= crate.Price and crate.Color or crate.Color:Lerp(DARKER, 0.6)
		end
	end
end

local function applyData(snapshot: Snapshot?)
	if not snapshot then
		return
	end
	data = snapshot
	applyCoins(snapshot.Coins, snapshot.CoinsPerSecond)
	if petsFrame.Visible then
		rebuildPets()
	end
end

DataUpdated.OnClientEvent:Connect(applyData)

CoinsUpdated.OnClientEvent:Connect(function(coins: number, cps: number)
	local current = data
	if current then
		current.Coins = coins
		current.CoinsPerSecond = cps
	end
	applyCoins(coins, cps)
end)

CrateResult.OnClientEvent:Connect(function(crateId: string, petId: string)
	table.insert(resultQueue, { crateId = crateId, petId = petId })
	task.spawn(processQueue)
end)

Notify.OnClientEvent:Connect(function(message: string)
	toast(message, Color3.fromRGB(255, 120, 120))
end)

Announce.OnClientEvent:Connect(function(who: string, petId: string, crateId: string)
	local pet = Config.GetPet(petId)
	local crate = Config.GetCrate(crateId)
	if not pet or not crate then
		return
	end
	local rarity = Config.Rarities[pet.Rarity]
	local message = string.format(
		"%s pulled a %s %s from a %s!",
		who,
		rarity.DisplayName:upper(),
		pet.DisplayName,
		crate.DisplayName
	)
	-- Delay so the opener's own reel finishes before the server-wide shout.
	task.delay(who == player.DisplayName and SPIN_TIME or 0, function()
		toast("🔥 " .. message, rarity.Color, 5)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral") :: TextChannel?
		if general then
			local hex = rarity.Color:ToHex()
			pcall(function()
				general:DisplaySystemMessage(string.format('<font color="#%s">%s</font>', hex, message))
			end)
		end
	end)
end)

applyData(GetData:InvokeServer())
