-- World dump for tools/render_world.py: boots the server (so service-built props
-- exist), then builds one course per theme + the tutorial and prints every part,
-- light and SurfaceGui (text / gradient) as "@" records on stdout.
do (function()
	local function f3(v)
		return string.format("%.4f,%.4f,%.4f", v.X, v.Y, v.Z)
	end
	local function col(c)
		return string.format("%.4f,%.4f,%.4f", c.R, c.G, c.B)
	end
	local function dumpTree(root)
		for _, x in Sim.descendants(root) do
			local d = D[x]
			if d.isBasePart then
				local c = x.CFrame
				local shape = if d.cls == "Part" then x.Shape.Name else d.cls
				print(string.format("@P|%s|%s|%s|%s|%s|%s|%s|%s|%s|%.3f|%s|%s", d.cls, shape, f3(c.Position), f3(c.RightVector), f3(c.UpVector), f3(-c.LookVector),
					f3(x.Size), col(x.Color), x.Material.Name, x.Transparency, tostring(x.CastShadow), (string.gsub(Sim.fullName(x), "|", "/"))))
				for _, ch in d.children do
					local cd = D[ch]
					if cd.cls == "PointLight" or cd.cls == "SurfaceLight" or cd.cls == "SpotLight" then
						local face = if cd.cls == "PointLight" then "None" else ch.Face.Name
						print(string.format("@L|%s|%s|%s|%.3f|%.3f|%s|%s|%s", cd.cls, f3(x.Position), col(ch.Color), ch.Brightness, ch.Range, face, f3(x.CFrame.UpVector), f3(-x.CFrame.LookVector)))
					elseif cd.cls == "SurfaceGui" then
						for _, g in Sim.descendants(ch) do
							local gd = D[g]
							if gd.cls == "TextLabel" and g.Text ~= "" then
								print(string.format("@T|%d|%s|%s|%s|%s", D[x].id, ch.Face.Name, col(g.TextColor3), g.Font.Name, (string.gsub(string.gsub(g.Text, "|", "/"), "\n", "\\n"))))
								break
							elseif gd.cls == "UIGradient" then
								local kps = g.Color.Keypoints
								print(string.format("@G|%d|%s|%s|%s|%.1f", D[x].id, ch.Face.Name, col(kps[1].Value), col(kps[#kps].Value), g.Rotation))
								break
							end
						end
					end
				end
				print(string.format("@I|%d", D[x].id))
			end
		end
	end
	local which = Sim.dumpWhich or "all"
	Sim.runScript(Sim.mainServer, "server")
	Sim.run(7)
	if which == "all" or which == "lobby" then
		print("@SCENE|lobby")
		dumpTree(Sim.workspace:FindFirstChild("Lobby"))
		for _, x in Sim.workspace:GetChildren() do
			if x.Name:sub(1, 7) == "Podium_" then
				dumpTree(x)
			end
		end
	end
	if which == "all" or which == "courses" then
		Sim.asSide("server", function()
			local Maps = Sim.module("server", "Maps")
			local CourseBuilder = Sim.module("server", "CourseBuilder")
			local seen = {}
			local i = 0
			for _, map in Maps.List do
				if not seen[map.Theme] or map.Id == Sim.dumpMap then
					seen[map.Theme] = true
					i += 1
					local course = CourseBuilder.build(map, Vector3.new(4000 + i * 1100, 0, 4000), { ChaosBoxes = true })
					print("@SCENE|course_" .. map.Id)
					print(string.format("@ORIGIN|%s", f3(Vector3.new(4000 + i * 1100, 0, 4000))))
					for hi, h in course.Holes do
						print(string.format("@HOLE|%d|%s|%s|%s|%s|%s|%s", hi, f3(h.Tee), f3(h.Cup), f3(h.Overview.Position), f3(h.Overview.RightVector), f3(h.Overview.UpVector), f3(-h.Overview.LookVector)))
					end
					dumpTree(course.Model)
					course.Destroy()
				end
			end
			local tut = CourseBuilder.buildTutorial(Vector3.new(-4000, 0, 4000))
			print("@SCENE|tutorial")
			print(string.format("@ORIGIN|%s", f3(Vector3.new(-4000, 0, 4000))))
			for hi, h in tut.Holes do
				print(string.format("@HOLE|%d|%s|%s|%s|%s|%s|%s", hi, f3(h.Tee), f3(h.Cup), f3(h.Overview.Position), f3(h.Overview.RightVector), f3(h.Overview.UpVector), f3(-h.Overview.LookVector)))
			end
			dumpTree(tut.Model)
		end)
	end
	print("@END")
end)() end
