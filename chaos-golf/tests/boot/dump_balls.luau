-- Ball showcase dump for tools/render_balls.py: boots the server (the mesh size gets
-- published), puts one ball per skin on a grid with Skins.apply, then prints each ball,
-- its core, stripes and every print plate with its GUI content as "@" records.
do (function()
	local function f3(v)
		return string.format("%.5f,%.5f,%.5f", v.X, v.Y, v.Z)
	end
	local function col(c)
		return string.format("%.4f,%.4f,%.4f", c.R, c.G, c.B)
	end
	local function cf(c)
		return f3(c.Position) .. "|" .. f3(c.RightVector) .. "|" .. f3(c.UpVector) .. "|" .. f3(-c.LookVector)
	end
	Sim.runScript(Sim.mainServer, "server")
	Sim.run(4)
	Sim.asSide("server", function()
		local Skins = Sim.module("server", "Skins")
		local only = Sim.ballSkins
		local list = {}
		for _, skin in Skins.List do
			if not only or only[skin.Id] then
				table.insert(list, skin)
			end
		end
		local folder = Instance.new("Folder")
		folder.Name = "BallShowcase"
		folder.Parent = workspace
		local d = Sim.ballDiameter or 1.5
		for i, skin in list do
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.one * d
			p.Anchored = true
			p.CFrame = CFrame.new((i - 1) * d * 2, 50, 0)
			Skins.apply(p, skin.Id, if skin.Source == "Limited" then 137 else nil)
			p.Parent = folder
			print(string.format("@BALL|%d|%s|%s|%s|%.4f|%s|%s|%.3f|%.3f", i, skin.Id, skin.Name, cf(p.CFrame), d, col(p.Color), p.Material.Name, p.Transparency, p.Reflectance))
			local prints = p:FindFirstChild("SkinPrints")
			for _, q in prints:GetChildren() do
				if q.Name == "SkinCore" then
					print(string.format("@CORE|%d|%s|%.4f|%s", i, f3(q.Position), q.Size.X, col(q.Color)))
				elseif q.Name == "Stripe" then
					print(string.format("@RING|%d|%s|%s|%s|%s", i, cf(q.CFrame), f3(q.Size), col(q.Color), q.Material.Name))
				elseif q.Name == "Print" then
					local gui = q:FindFirstChildOfClass("SurfaceGui")
					local pps = gui.PixelsPerStud
					print(string.format("@PLATE|%d|%s|%.5f,%.5f|%.3f", i, cf(q.CFrame), q.Size.X, q.Size.Y, pps))
					local W, H = q.Size.X * pps, q.Size.Y * pps
					local function px(u, extent)
						return u.Scale * extent + u.Offset
					end
					local function walk(node, x0, y0, w0, h0)
						for _, g in node:GetChildren() do
							if g:IsA("GuiObject") then
								local w = px(g.Size.X, w0)
								local h = px(g.Size.Y, h0)
								local x = x0 + px(g.Position.X, w0) - g.AnchorPoint.X * w
								local y = y0 + px(g.Position.Y, h0) - g.AnchorPoint.Y * h
								if g:IsA("TextLabel") then
									print(string.format("@PT|%.2f,%.2f,%.2f,%.2f|%s|%s|%d|%s", x, y, w, h, col(g.TextColor3), g.Font.Name, g.TextSize, g.Text))
								else
									local corner = g:FindFirstChildOfClass("UICorner")
									local stroke = g:FindFirstChildOfClass("UIStroke")
									local grad = g:FindFirstChildOfClass("UIGradient")
									local gtxt = ""
									if grad then
										local parts = {}
										for _, k in grad.Color.Keypoints do
											table.insert(parts, string.format("%.4f:%s", k.Time, col(k.Value)))
										end
										gtxt = table.concat(parts, ";") .. "@" .. tostring(grad.Rotation)
									end
									print(string.format("@PF|%.2f,%.2f,%.2f,%.2f|%s|%.3f|%s|%s|%s", x, y, w, h, col(g.BackgroundColor3), g.BackgroundTransparency,
										if corner then tostring(corner.CornerRadius.Scale) else "0",
										if stroke then string.format("%.2f:%s", stroke.Thickness, col(stroke.Color)) else "",
										gtxt))
									walk(g, x, y, w, h)
								end
							end
						end
					end
					walk(gui, 0, 0, W, H)
				end
			end
		end
	end)
end)() end
