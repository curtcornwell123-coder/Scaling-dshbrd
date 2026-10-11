--!strict
--[[
	EventConfig
	The update countdown sign in the hub's Halloween corner. Change Title/EndsAt to announce the
	next update or event; after EndsAt the sign shows AfterTitle.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local EventConfig = {}

EventConfig.Title = "HALLOWEEN UPDATE"
EventConfig.EndsAt = 1793404800 -- 2026-10-31 00:00 UTC
EventConfig.AfterTitle = "HALLOWEEN IS HERE!"
-- Sign accent colour (pumpkin orange for Halloween).
EventConfig.Accent = Color3.fromRGB(232, 120, 24)

return TableUtil.deepFreeze(EventConfig)
