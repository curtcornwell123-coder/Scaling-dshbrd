--!strict
-- Spawns glowing orbs for each equipped pet that float around the player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local PetFollower = {}

local currentPets: { [Player]: { Config.Pet } } = {}
local folders: { [Player]: Folder } = {}
local charConnections: { [Player]: RBXScriptConnection } = {}

local function petsFolder(): Folder
	local folder = Workspace:FindFirstChild("Pets") :: Folder?
	if not folder then
		local newFolder = Instance.new("Folder")
		newFolder.Name = "Pets"
		newFolder.Parent = Workspace
		folder = newFolder
	end
	return folder :: Folder
end

local function slotOffset(index: number, total: number): Vector3
	local angle = math.pi + (index - (total + 1) / 2) * 0.9
	return Vector3.new(math.sin(angle) * 5, 1.5, math.cos(angle) * -5)
end

local function makePet(pet: Config.Pet, root: BasePart, offset: Vector3): Part
	local rarity = Config.Rarities[pet.Rarity]

	local orb = Instance.new("Part")
	orb.Name = pet.Id
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * (1.4 + rarity.Order * 0.25)
	orb.Color = rarity.Color
	orb.Material = Enum.Material.Neon
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.Massless = true
	orb.CFrame = root.CFrame * CFrame.new(offset)

	local petAttachment = Instance.new("Attachment")
	petAttachment.Parent = orb

	local rootAttachment = Instance.new("Attachment")
	rootAttachment.Name = "PetSlot"
	rootAttachment.Position = offset
	rootAttachment.Parent = root

	local align = Instance.new("AlignPosition")
	align.Attachment0 = petAttachment
	align.Attachment1 = rootAttachment
	align.Responsiveness = 25
	align.MaxForce = math.huge
	align.Parent = orb

	local orient = Instance.new("AlignOrientation")
	orient.Attachment0 = petAttachment
	orient.Attachment1 = rootAttachment
	orient.Responsiveness = 25
	orient.Parent = orb

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(120, 30)
	billboard.StudsOffset = Vector3.new(0, 1.8, 0)
	billboard.MaxDistance = 50
	billboard.Parent = orb

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = rarity.Color
	label.TextStrokeTransparency = 0.2
	label.Text = pet.DisplayName
	label.Parent = billboard

	if pet.Rarity == "Mythic" or pet.Rarity == "Legendary" then
		local aura = Instance.new("ParticleEmitter")
		aura.Color = ColorSequence.new(rarity.Color)
		aura.LightEmission = 1
		aura.Size = NumberSequence.new(0.5, 0)
		aura.Lifetime = NumberRange.new(0.5, 1)
		aura.Rate = pet.Rarity == "Mythic" and 25 or 10
		aura.Speed = NumberRange.new(0.5, 1.5)
		aura.Parent = orb
	end

	-- Clean up the root attachment when the pet goes away.
	orb.Destroying:Connect(function()
		rootAttachment:Destroy()
	end)

	return orb
end

local function rebuild(player: Player)
	local old = folders[player]
	if old then
		old:Destroy()
		folders[player] = nil
	end

	local pets = currentPets[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pets or #pets == 0 or not root then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = player.Name
	folder.Parent = petsFolder()
	folders[player] = folder

	for i, pet in pets do
		local orb = makePet(pet, root, slotOffset(i, #pets))
		orb.Parent = folder
		pcall(function()
			orb:SetNetworkOwner(player)
		end)
	end
end

function PetFollower.SetPets(player: Player, pets: { Config.Pet })
	currentPets[player] = pets
	if not charConnections[player] then
		charConnections[player] = player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			rebuild(player)
		end)
	end
	rebuild(player)
end

function PetFollower.Clear(player: Player)
	currentPets[player] = nil
	local folder = folders[player]
	if folder then
		folder:Destroy()
	end
	folders[player] = nil
	local conn = charConnections[player]
	if conn then
		conn:Disconnect()
	end
	charConnections[player] = nil
end

return PetFollower
