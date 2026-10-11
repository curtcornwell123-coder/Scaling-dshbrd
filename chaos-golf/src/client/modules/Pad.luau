--!strict
-- Controller and device helpers shared by every menu:
--   * Pad.device(): which controls to explain ("pad" | "touch" | "pc"). A live controller wins;
--     otherwise the device the player picked on first join; otherwise what we can detect.
--   * Pad.focus(button): select a button when a menu opens, only when a controller is in use.
--   * Pad.opened / Pad.closed: a stack of open menus; B closes the top one, so every
--     panel can be closed from a controller.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local State = require(script.Parent:WaitForChild("State"))

local Pad = {}

export type Device = "pad" | "touch" | "pc"

-- Profile values for the three choices offered on first join.
Pad.Choices = { "Console", "Touch", "Keyboard" }
local FROM_CHOICE: { [string]: Device } = { Console = "pad", Touch = "touch", Keyboard = "pc" }

function Pad.usingGamepad(): boolean
	local last = UserInputService:GetLastInputType()
	if string.sub(last.Name, 1, 7) == "Gamepad" then
		return true
	end
	return UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
end

function Pad.detected(): Device
	if Pad.usingGamepad() then
		return "pad"
	end
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		return "touch"
	end
	return "pc"
end

-- The player's chosen device ("Console" | "Touch" | "Keyboard"), or nil before they pick.
function Pad.choice(): string?
	local p = State.Profile
	local c = p and p.Device
	return if type(c) == "string" and FROM_CHOICE[c] then c else nil
end

function Pad.device(): Device
	if Pad.usingGamepad() then
		return "pad"
	end
	local c = Pad.choice()
	return if c then FROM_CHOICE[c] else Pad.detected()
end

function Pad.toChoice(d: Device): string
	return if d == "pad" then "Console" elseif d == "touch" then "Touch" else "Keyboard"
end

function Pad.focus(obj: GuiObject?)
	if obj and Pad.usingGamepad() then
		GuiService.SelectedObject = obj
	end
end

-- Open-menu stack -------------------------------------------------------------------

local ACTION = "UG_MenuBack"
local stack: { { Name: string, Close: () -> () } } = {}

local function handler(_: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local top = stack[#stack]
	if top then
		top.Close()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function rebind()
	if #stack > 0 then
		ContextActionService:BindActionAtPriority(ACTION, handler, false, 3000, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

local function remove(name: string)
	for i = #stack, 1, -1 do
		if stack[i].Name == name then
			table.remove(stack, i)
		end
	end
end

-- `close` must close the menu (and call Pad.closed).
function Pad.opened(name: string, close: () -> ())
	remove(name)
	table.insert(stack, { Name = name, Close = close })
	rebind()
end

function Pad.closed(name: string)
	remove(name)
	rebind()
	if #stack == 0 then
		local sel = GuiService.SelectedObject
		if sel then
			GuiService.SelectedObject = nil
		end
	end
end

function Pad.start() end

return Pad
