--!strict
-- Remote registry. The server creates every remote at boot (Net.setup); clients
-- call Net.event/Net.func which wait for them.
--
-- Client -> server
--   Shoot(dir: Vector3, power: number)        shoot the player's active ball
--   UseAbility(slot: number)
--   LeaveActivity()                           skip the tutorial / quit a practice lane
--   ShopAction(action: string, a: any, b: any) "buySkin" | "equip" | "openCrate" | "upgrade" |
--                                             "buyTokenSkin" | "celebration" | "buyPass" | "buyProduct" | "claimDaily" |
--                                             "buyLimited" | "claimGift" | "claimGroup" | "setDevice"
--   SubmitCreatorCode(code: string)
--   TutorialChoice(choice: string)            answer to the first-join invite: "play" | "skip"
-- Server -> client
--   Profile(profile)                          full profile snapshot after any change
--   Coins(coins: number, delta: number, reason: string?)
--   BallAssigned(ball: BasePart?, info)       start/stop controlling a ball
--   MatchEvent(kind: string, payload)         "intro" | "hole" | "turn" | "scorecard" | "results" | "end"
--   Toast(text: string, color: Color3?)       short in-world message near the ball
--   Fx(kind: string, payload)                 one-shot effects (sink, ability, coin popups)
--   CrateReveal(crateId, category, itemId, isNew, refund)
--   Leaderboards(data)                        all boards (client pages them locally)
--   Vote(choiceIndex: number?)                your current vote (for the local confirmation)
--   Tutorial(kind: string, payload)           "device" (first join: pick a device) | "invite" |
--                                             "steps" {Hole, Holes, Title, Steps={{Key, Done}}} | "done"
-- Functions
--   GetProfile() -> profile

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Events = {
	"Shoot",
	"UseAbility",
	"LeaveActivity",
	"ShopAction",
	"SubmitCreatorCode",
	"TutorialChoice",
	"Profile",
	"Coins",
	"BallAssigned",
	"MatchEvent",
	"Toast",
	"Fx",
	"CrateReveal",
	"Leaderboards",
	"Vote",
	"Tutorial",
}

Net.Functions = {
	"GetProfile",
}

local FOLDER = "UltimateGolfRemotes"

function Net.setup()
	assert(RunService:IsServer(), "Net.setup is server-only")
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	for _, name in Net.Events do
		local r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = folder
	end
	for _, name in Net.Functions do
		local r = Instance.new("RemoteFunction")
		r.Name = name
		r.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

local function folder(): Folder
	return ReplicatedStorage:WaitForChild(FOLDER) :: Folder
end

function Net.event(name: string): RemoteEvent
	return folder():WaitForChild(name) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	return folder():WaitForChild(name) :: RemoteFunction
end

return Net
