do (function()
	print(string.format("sim time %.1fs", Sim.now))
	local nOk, nFail = 0, 0
	for _, f in Sim.flows do
		if f.ok then nOk += 1 else nFail += 1 end
	end
	print("FLOWS ok", nOk, "fail", nFail)
	Sim.summary()
end)() end
