--!strict
-- Worldwide stock of the limited-edition ball (Config.Limited), shared by every server.
-- A successful reservation's number is the buyer's serial ("137 OF 500").

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GlobalStock = require(script.Parent:WaitForChild("GlobalStock"))

return GlobalStock.new("Limited", Config.Limited.Key, "UltimateGolfLimited", Config.Limited.Stock, Config.Limited.StockRefresh)
