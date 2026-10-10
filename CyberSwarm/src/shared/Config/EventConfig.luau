--!strict
--[[
	EventConfig
	The floating countdown billboard above the hub platform. Change Title/EndsAt to announce the
	next update or event; after EndsAt the billboard shows AfterTitle.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local EventConfig = {}

EventConfig.Title = "NEXT UPDATE"
EventConfig.EndsAt = 1792800000 -- 2026-10-24 00:00 UTC
EventConfig.AfterTitle = "UPDATE LIVE NOW"

return TableUtil.deepFreeze(EventConfig)
