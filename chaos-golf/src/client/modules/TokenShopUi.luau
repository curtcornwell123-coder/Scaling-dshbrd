--!strict
-- Practice range token economy on screen:
--  * a token pill (top centre) while you're inside the range, so you always see your
--    Target / Drive / Hazard tokens;
--  * the token shop panel each station's hut opens (crate + that game's skins).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Crates = require(Shared:WaitForChild("Crates"))
local Minigames = require(Shared:WaitForChild("Minigames"))
local Net = require(Shared:WaitForChild("Net"))
local Skins = require(Shared:WaitForChild("Skins"))
local UIKit = require(Shared:WaitForChild("UIKit"))

local Pad = require(script.Parent:WaitForChild("Pad"))
local State = require(script.Parent:WaitForChild("State"))

local TokenShopUi = {}

local T = UIKit.Theme
local player = Players.LocalPlayer

local gui: ScreenGui
local pill: Frame
local counts: { [string]: TextLabel } = {}
local panel: Frame? = nil
local openId: string? = nil
local panelConn: RBXScriptConnection? = nil

local function tokens(id: string): number
	local p = State.Profile
	return if p and p.Tokens then p.Tokens[id] or 0 else 0
end

local function buildPill()
	pill = UIKit.panel({
		Name = "Tokens",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(0, 36),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	UIKit.padding(pill, 0, 12)
	local layout = UIKit.list(pill, 14, true)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	for i, m in Minigames.List do
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(12, 12)
		dot.BackgroundColor3 = m.Color
		dot.BorderSizePixel = 0
		dot.LayoutOrder = i * 2
		dot.ZIndex = 11
		UIKit.corner(dot, UDim.new(1, 0))
		dot.Parent = pill
		counts[m.Id] = UIKit.text({
			Text = "0",
			TextSize = 16,
			Font = T.FontHeavy,
			Size = UDim2.fromOffset(0, 36),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = i * 2 + 1,
			ZIndex = 11,
			Parent = pill,
		})
	end
end

local function renderPill()
	for id, label in counts do
		label.Text = string.format("%s  %d", (Minigames.ById[id] :: Minigames.Minigame).Token, tokens(id))
	end
	pill.Visible = player:GetAttribute("InPractice") == true
end

local function close()
	if panelConn then
		panelConn:Disconnect()
		panelConn = nil
	end
	if panel then
		panel:Destroy()
	end
	panel = nil
	openId = nil
	Pad.closed("TokenShop")
end

local function open(id: string)
	close()
	local mg = Minigames.ById[id]
	if not mg then
		return
	end
	openId = id
	local card = UIKit.panel({
		Name = "TokenShop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(420, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 30,
		Parent = gui,
	})
	panel = card
	UIKit.padding(card, 16)
	UIKit.list(card, 8)
	UIKit.text({ Text = string.upper(mg.Token) .. " SHOP", TextSize = 22, Font = T.FontHeavy, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 0, ZIndex = 31, Parent = card })
	local balance = UIKit.text({ Text = "", TextSize = 15, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, ZIndex = 31, Parent = card })
	local buttons: { [string]: { Button: TextButton, Price: number, Skin: string? } } = {}

	local crate = Crates.get(id)
	if crate then
		local row = UIKit.card({ Size = UDim2.new(1, 0, 0, 54), LayoutOrder = 2, ZIndex = 31, Parent = card })
		UIKit.padding(row, 6, 12)
		UIKit.text({ Text = crate.Name, TextSize = 17, Font = T.FontHeavy, Size = UDim2.new(1, -150, 0, 22), ZIndex = 32, Parent = row })
		UIKit.text({ Text = "Random " .. mg.Name .. " skin", TextSize = 13, Font = T.FontMedium, TextColor3 = T.Muted, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, -150, 0, 18), ZIndex = 32, Parent = row })
		buttons.crate = {
			Button = UIKit.button("Open", "Primary", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(136, 34), TextSize = 14, ZIndex = 32, Parent = row }, function()
				Net.event("ShopAction"):FireServer("openCrate", id)
			end),
			Price = crate.Price,
		}
	end
	for i, skin in Skins.withSource("Token:" .. id) do
		local price = Crates.TokenDirectPrice[skin.Rarity] or 0
		local row = UIKit.card({ Size = UDim2.new(1, 0, 0, 46), LayoutOrder = 10 + i, ZIndex = 31, Parent = card })
		UIKit.padding(row, 0, 12)
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.fromScale(0, 0.5)
		dot.Size = UDim2.fromOffset(22, 22)
		dot.BackgroundColor3 = skin.Color
		dot.BorderSizePixel = 0
		dot.ZIndex = 32
		UIKit.corner(dot, UDim.new(1, 0))
		dot.Parent = row
		UIKit.text({ Text = skin.Name, TextSize = 16, Font = T.FontHeavy, Position = UDim2.fromOffset(32, 4), Size = UDim2.new(1, -180, 0, 20), ZIndex = 32, Parent = row })
		UIKit.text({ Text = skin.Rarity, TextSize = 13, Font = T.FontMedium, TextColor3 = Skins.Rarities[skin.Rarity].Color, Position = UDim2.fromOffset(32, 24), Size = UDim2.new(1, -180, 0, 16), ZIndex = 32, Parent = row })
		buttons[skin.Id] = {
			Button = UIKit.button("Unlock", "Primary", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(136, 32), TextSize = 14, ZIndex = 32, Parent = row }, function()
				Net.event("ShopAction"):FireServer("buyTokenSkin", skin.Id)
			end),
			Price = price,
			Skin = skin.Id,
		}
	end
	UIKit.text({ Text = "Earn " .. mg.Token .. " on the " .. mg.Name .. " lanes. Tokens can't be bought.", TextSize = 13, Font = T.FontMedium, TextColor3 = T.Muted, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 98, ZIndex = 31, Parent = card })
	UIKit.button("Close", "Ghost", { Size = UDim2.new(1, 0, 0, 30), TextSize = 14, LayoutOrder = 99, ZIndex = 31, Parent = card }, close)

	local function render()
		if panel ~= card then
			return
		end
		local have = tokens(id)
		balance.Text = string.format("You have %d %s", have, mg.Token)
		for _, b in buttons do
			if b.Skin and State.owns("Skins", b.Skin) then
				local equipped = State.equipped("Skins") == b.Skin
				UIKit.setVariant(b.Button, if equipped then "Disabled" else "Secondary", if equipped then "Equipped" else "Equip")
			elseif have >= b.Price then
				UIKit.setVariant(b.Button, "Primary", (if b.Skin then "Unlock · " else "Open · ") .. b.Price)
			else
				UIKit.setVariant(b.Button, "Disabled", b.Price .. " tokens")
			end
		end
	end
	render()
	panelConn = State.ProfileChanged:Connect(render)
	Pad.opened("TokenShop", close)
	local firstButton = buttons.crate
	Pad.focus(if firstButton then firstButton.Button else nil)
end

function TokenShopUi.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "TokenShopUi"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 7
	buildPill()
	gui.Parent = player:WaitForChild("PlayerGui")
	State.observe(function()
		renderPill()
	end)
	player:GetAttributeChangedSignal("InPractice"):Connect(function()
		renderPill()
		if player:GetAttribute("InPractice") ~= true then
			close()
		end
	end)
	Net.event("Fx").OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "tokenShop" and type(payload) == "table" and type(payload.Minigame) == "string" then
			if openId == payload.Minigame then
				close()
			else
				open(payload.Minigame)
			end
		end
	end)
end

return TokenShopUi
