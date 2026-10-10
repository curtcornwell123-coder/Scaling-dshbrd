--!strict
-- The shop & locker catalog: a data-driven grid (ShopCatalog config) rendered
-- on the East room terminal screen as an interactive SurfaceGui ("World"
-- mode, keeps the zero-overlay rule) or as a centred overlay opened from the
-- terminal ("Screen" mode). Also drives the Locker pedestal preview.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cosmetics = require(Shared:WaitForChild("Cosmetics"))
local Net = require(Shared:WaitForChild("Net"))
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Hud = require(script.Parent:WaitForChild("Hud"))
local State = require(script.Parent:WaitForChild("State"))
local Previews = require(script.Parent:WaitForChild("Previews"))

local Catalog = {}

local T = UIKit.Theme
local player = Players.LocalPlayer

local CANVAS_WIDTH = 1000
local CELL = UDim2.fromOffset(172, 214)

type View = {
	Root: Frame,
	Tabs: { [string]: TextButton },
	Hint: TextLabel,
	Filters: Frame,
	Grid: ScrollingFrame,
	Summary: TextLabel,
}

local view: View? = nil
local activeTab = "Featured"
local lockerFilter = "All"

-- Locker pedestal preview -------------------------------------------------------------

local previewBall: Part? = nil
local lockerIndex = 1

local function showOnPedestal(skinId: string)
	local pedestal = CollectionService:GetTagged("LockerPedestal")[1] :: BasePart?
	if not pedestal then
		return
	end
	if not previewBall then
		local p = Instance.new("Part")
		p.Name = "LockerPreview"
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * 3.4
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p:SetAttribute("SpinSpeed", 1.2)
		p.Parent = workspace
		CollectionService:AddTag(p, "Spin")
		previewBall = p
	end
	local a = pedestal:FindFirstChild("Display")
	local at = if a and a:IsA("Attachment") then a.WorldPosition else pedestal.Position + Vector3.new(0, pedestal.Size.Y / 2 + 2.6, 0)
	local ball = previewBall :: Part
	ball.CFrame = CFrame.new(at)
	Skins.apply(ball, skinId)
end

local function ownedSkins(): { string }
	local out = {}
	for _, skin in Skins.List do
		if State.owns("Skins", skin.Id) then
			table.insert(out, skin.Id)
		end
	end
	return out
end

local function lockerStep(delta: number)
	local list = ownedSkins()
	if #list == 0 then
		return
	end
	lockerIndex = ((lockerIndex - 1 + delta) % #list) + 1
	local id = list[lockerIndex]
	showOnPedestal(id)
	local skin = Skins.get(id)
	local equipped = State.equipped("Skins") == id
	Hud.toast(string.format("%s · %s%s  (%d/%d)", skin.Name, skin.Rarity, if equipped then " · equipped" else "", lockerIndex, #list), Skins.Rarities[skin.Rarity].Color)
end

-- Cards ---------------------------------------------------------------------------

local function ctaFor(item: ShopCatalog.Item): (string, UIKit.ButtonVariant)
	if item.Action == "equip" then
		if State.equipped(item.Category :: string) == item.ItemId then
			return "Equipped", "Disabled"
		end
		return "Equip", "Primary"
	end
	if item.Action == "buySkin" and item.ItemId and State.owns("Skins", item.ItemId) then
		if State.equipped("Skins") == item.ItemId then
			return "Equipped", "Disabled"
		end
		return "Equip", "Secondary"
	end
	local price = item.Price
	if not price then
		return "Select", "Secondary"
	end
	if price.Currency == "Robux" then
		local configured = true
		if item.Action == "buyPass" then
			configured = Config.GamePasses[item.A].Id ~= 0
			if player:GetAttribute("Pass_" .. item.A) then
				return "Owned", "Disabled"
			end
		elseif item.Action == "buyProduct" then
			configured = Config.DevProducts[item.A].Id ~= 0
		end
		return if configured then price.Amount .. " Robux" else "Coming soon", if configured then "Secondary" else "Disabled"
	end
	if price.Currency == "Key" then
		return "Open · 1 Key", "Primary"
	end
	local verb = if item.Action == "openCrate" then "Open" else "Buy"
	return verb .. " · " .. UIKit.formatNumber(price.Amount), "Primary"
end

local function card(item: ShopCatalog.Item, order: number): Frame
	local c = UIKit.card({ Name = item.Key, LayoutOrder = order, Size = CELL })
	UIKit.padding(c, 10)
	local stroke = c:FindFirstChildOfClass("UIStroke")
	UIKit.hoverLift(c, stroke)

	local preview = Previews.make(item.Preview.Kind, item.Preview.Ref)
	preview.Size = UDim2.new(1, 0, 0, 100)
	preview.Parent = c

	local info = Instance.new("Frame")
	info.BackgroundTransparency = 1
	info.Position = UDim2.fromOffset(0, 108)
	info.Size = UDim2.new(1, 0, 0, 52)
	info.Parent = c
	UIKit.list(info, 2)
	local titleRow = Instance.new("Frame")
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, 20)
	titleRow.Parent = info
	UIKit.list(titleRow, 6, true)
	if item.Accent then
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = item.Accent
		dot.BorderSizePixel = 0
		UIKit.corner(dot, UDim.new(0, 2))
		dot.LayoutOrder = 1
		dot.Parent = titleRow
	end
	UIKit.text({ Text = item.Title, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, Size = UDim2.new(1, -14, 1, 0), LayoutOrder = 2, Parent = titleRow })
	UIKit.text({
		Text = item.Subtitle,
		TextSize = 12,
		Font = T.FontMedium,
		TextColor3 = T.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 28),
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = info,
	})

	local text, variant = ctaFor(item)
	UIKit.button(text, variant :: any, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 32),
		TextSize = 14,
		Parent = c,
	}, function()
		if item.Action == "buySkin" and item.ItemId and State.owns("Skins", item.ItemId) then
			Net.event("ShopAction"):FireServer("equip", "Skins", item.ItemId)
		else
			Net.event("ShopAction"):FireServer(item.Action, item.A, item.B)
		end
	end)

	-- Clicking the thumbnail of a ball shows it on the Locker pedestal.
	if item.Preview.Kind == "Ball" then
		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.new(1, 0, 0, 100)
		hit.ZIndex = 5
		hit.Parent = c
		hit.Activated:Connect(function()
			showOnPedestal(item.Preview.Ref)
		end)
	end
	return c
end

-- Rendering --------------------------------------------------------------------------

local function currentTab(): ShopCatalog.Tab
	for _, tab in ShopCatalog.Tabs do
		if tab.Id == activeTab then
			return tab
		end
	end
	return ShopCatalog.Tabs[1]
end

local function render()
	local v = view
	if not v then
		return
	end
	local profile = State.Profile
	for id, button in v.Tabs do
		UIKit.setVariant(button, if id == activeTab then "Primary" else "Secondary")
	end
	local tab = currentTab()
	v.Hint.Text = tab.Hint
	v.Filters.Visible = tab.Id == "Locker"
	for _, chip in v.Filters:GetChildren() do
		if chip:IsA("TextButton") then
			UIKit.setVariant(chip, if chip.Name == lockerFilter then "Primary" else "Ghost")
		end
	end
	if profile then
		local keys = profile.Keys or {}
		v.Summary.Text = string.format(
			"%s coins   ·   Keys  %d skin · %d trail · %d knockout · %d arrow",
			UIKit.formatNumber(profile.Coins or 0),
			keys.Skins or 0,
			keys.Trails or 0,
			keys.Knockouts or 0,
			keys.Arrows or 0
		)
	end

	local scroll = v.Grid.CanvasPosition
	for _, child in v.Grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local items = tab.Items(profile)
	local order = 0
	for _, item in items do
		if tab.Id ~= "Locker" or lockerFilter == "All" or item.Category == lockerFilter then
			order += 1
			card(item, order).Parent = v.Grid
		end
	end
	v.Grid.CanvasPosition = scroll
end

local function build(parent: Instance, closable: (() -> ())?): View
	local root = Instance.new("Frame")
	root.Name = "Catalog"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = T.Base
	root.BorderSizePixel = 0
	UIKit.corner(root)
	UIKit.padding(root, 18)
	root.Parent = parent

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 40)
	header.Parent = root
	UIKit.list(header, 8, true)
	UIKit.text({ Text = "SHOP", TextSize = 26, Font = T.FontHeavy, Size = UDim2.fromOffset(90, 40), LayoutOrder = 0, Parent = header })
	local tabs: { [string]: TextButton } = {}
	for i, tab in ShopCatalog.Tabs do
		tabs[tab.Id] = UIKit.button(tab.Name, "Secondary", { Size = UDim2.fromOffset(104, 36), LayoutOrder = i, TextSize = 15, Parent = header }, function()
			activeTab = tab.Id
			render()
		end)
	end
	if closable then
		local close = UIKit.button("Close", "Ghost", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(84, 36), Parent = root }, closable)
		close.ZIndex = 3
	end

	local summary = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Gold, Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 18), Parent = root })
	local hint = UIKit.text({ Text = "", TextSize = 14, Font = T.FontMedium, TextColor3 = T.Muted, Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 18), Parent = root })

	local filters = Instance.new("Frame")
	filters.BackgroundTransparency = 1
	filters.Position = UDim2.fromOffset(0, 92)
	filters.Size = UDim2.new(1, 0, 0, 30)
	filters.Visible = false
	filters.Parent = root
	UIKit.list(filters, 6, true)
	for i, f in ShopCatalog.LockerFilters do
		local label = if f == "All" then "All" else Cosmetics.CategoryInfo[f].Name
		local chip = UIKit.button(label, "Ghost", { Name = f, Size = UDim2.fromOffset(if f == "All" then 56 else 132, 28), TextSize = 13, LayoutOrder = i, Parent = filters }, function()
			lockerFilter = f
			render()
		end)
		chip.Name = f
	end

	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.Position = UDim2.fromOffset(0, 128)
	grid.Size = UDim2.new(1, 0, 1, -128)
	grid.CanvasSize = UDim2.new()
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = T.Stroke
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.Parent = root
	UIKit.grid(grid, CELL, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.Parent = grid

	return { Root = root, Tabs = tabs, Hint = hint, Filters = filters, Grid = grid, Summary = summary }
end

local function mountWorld(screen: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "CatalogSurface"
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = CANVAS_WIDTH / math.max(screen.Size.X, 1)
	gui.LightInfluence = 0
	gui.MaxDistance = 40
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	view = build(gui, nil)
	render()
end

local function mountScreen(screen: BasePart)
	local gui = Instance.new("ScreenGui")
	gui.Name = "CatalogOverlay"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(940, 580)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local constraint = Instance.new("UIAspectRatioConstraint")
	constraint.AspectRatio = 940 / 580
	constraint.Parent = holder
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(940, 580)
	sizeLimit.Parent = holder
	view = build(holder, function()
		gui.Enabled = false
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open shop"
	prompt.ObjectText = "Catalog"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen
	prompt.Triggered:Connect(function()
		gui.Enabled = true
		render()
	end)
end

local function hookLockerButtons()
	local function hook(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		local action = part:GetAttribute("Action")
		local prompt = Instance.new("ProximityPrompt")
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.ObjectText = "Locker"
		prompt.ActionText = if action == "prev" then "Previous skin" elseif action == "next" then "Next skin" else "Equip shown skin"
		prompt.KeyboardKeyCode = if action == "prev" then Enum.KeyCode.Q elseif action == "next" then Enum.KeyCode.E else Enum.KeyCode.F
		prompt.Parent = part
		prompt.Triggered:Connect(function()
			if action == "prev" then
				lockerStep(-1)
			elseif action == "next" then
				lockerStep(1)
			else
				local list = ownedSkins()
				local id = list[lockerIndex]
				if id then
					Net.event("ShopAction"):FireServer("equip", "Skins", id)
				end
			end
		end)
	end
	for _, p in CollectionService:GetTagged("LockerButton") do
		hook(p)
	end
	CollectionService:GetInstanceAddedSignal("LockerButton"):Connect(hook)
end

function Catalog.start()
	task.spawn(function()
		local screen = CollectionService:GetTagged("CatalogScreen")[1]
		while not screen do
			CollectionService:GetInstanceAddedSignal("CatalogScreen"):Wait()
			screen = CollectionService:GetTagged("CatalogScreen")[1]
		end
		if Config.UI.ShopMode == "Screen" then
			mountScreen(screen :: BasePart)
		else
			mountWorld(screen :: BasePart)
		end
	end)
	hookLockerButtons()
	State.observe(function(profile)
		render()
		if profile and profile.Equipped and not previewBall then
			showOnPedestal(profile.Equipped.Skins)
		end
	end)
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Pass_" then
			render()
		end
	end)
	Net.event("Fx").OnClientEvent:Connect(function(kind: string)
		if kind == "shopRotated" then
			render()
		end
	end)
end

return Catalog
