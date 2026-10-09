--!strict
--[[
	TableUtil
	Table helpers for copying, reconciling saved data with defaults, and freezing config tables
	so nothing can mutate balance values at runtime.
]]

local TableUtil = {}

function TableUtil.deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value :: any do
		copy[TableUtil.deepCopy(key)] = TableUtil.deepCopy(child)
	end
	return copy :: any
end

-- Fills keys missing from target with deep copies from template. Existing values are kept,
-- which is what makes old saves pick up newly added default fields safely.
function TableUtil.reconcile(target: { [any]: any }, template: { [any]: any }): { [any]: any }
	for key, defaultValue in template do
		local current = target[key]
		if current == nil then
			target[key] = TableUtil.deepCopy(defaultValue)
		elseif type(current) == "table" and type(defaultValue) == "table" and #defaultValue == 0 then
			-- Only recurse into dictionaries; arrays (like loadouts) are player choices, not templates.
			TableUtil.reconcile(current, defaultValue)
		end
	end
	return target
end

function TableUtil.deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		for _, child in value :: any do
			TableUtil.deepFreeze(child)
		end
		table.freeze(value :: any)
	end
	return value
end

-- A table check that deliberately does not narrow the value's type. Validation code reads
-- fields off `any` data after this check, and a narrowing check would type it as a bare table.
function TableUtil.isTable(value: any): boolean
	return type(value) == "table"
end

function TableUtil.contains<T>(list: { T }, value: T): boolean
	return table.find(list, value) ~= nil
end

function TableUtil.count(map: { [any]: any }): number
	local total = 0
	for _ in map do
		total += 1
	end
	return total
end

-- O(1) removal for arrays where order does not matter.
function TableUtil.swapRemove<T>(list: { T }, index: number)
	local last = #list
	list[index] = list[last]
	list[last] = nil
end

-- True when value is a plain array with exactly `length` sequential entries and no other keys.
-- Used to validate client-sent tables before reading them.
function TableUtil.isStrictArray(value: unknown, maxLength: number): boolean
	if type(value) ~= "table" then
		return false
	end
	local length = #(value :: { any })
	if length > maxLength then
		return false
	end
	local keys = 0
	for _ in value :: { [any]: any } do
		keys += 1
		if keys > length then
			return false
		end
	end
	return keys == length
end

return TableUtil
