--!strict
-- Global stock for the Mythic Featured Crate, shared by every server (see GlobalStock).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GlobalStock = require(script.Parent:WaitForChild("GlobalStock"))

return GlobalStock.new("Mythic", "MythicSold_" .. Config.Mythic.Season, "UltimateGolfMythic", Config.Mythic.GlobalCap, Config.Mythic.StockRefresh)
