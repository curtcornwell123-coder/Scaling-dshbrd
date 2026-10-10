--!strict
--[[
	ReceiptLedger
	Keeps the ids of developer-product receipts already granted, so ProcessReceipt can be called
	any number of times for the same purchase and grant it exactly once. Pure.
]]

local ReceiptLedger = {}

function ReceiptLedger.has(ledger: { string }, purchaseId: string): boolean
	return table.find(ledger, purchaseId) ~= nil
end

-- Records a receipt id, dropping the oldest beyond `cap`.
function ReceiptLedger.record(ledger: { string }, purchaseId: string, cap: number)
	table.insert(ledger, purchaseId)
	while #ledger > cap do
		table.remove(ledger, 1)
	end
end

return ReceiptLedger
