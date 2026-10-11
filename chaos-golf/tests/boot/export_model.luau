-- Model export for tools/export/model_to_rojo.py: boots the server, then prints the
-- instance tree under Sim.exportPath (e.g. "Lobby/Hub/Fountain") as "@N"/"@Q" records.
do (function()
	local function num(n)
		return string.format("%.5f", n)
	end
	local function v3(v)
		return num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z)
	end
	local function c3(c)
		return num(c.R) .. "," .. num(c.G) .. "," .. num(c.B)
	end
	local function cf(c)
		return v3(c.Position) .. ";" .. v3(c.RightVector) .. ";" .. v3(c.UpVector) .. ";" .. v3(-c.LookVector)
	end
	local PROPS = {
		Part = { "Shape", "Size", "CFrame", "Color", "Material", "Transparency", "Reflectance", "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow" },
		WedgePart = { "Size", "CFrame", "Color", "Material", "Transparency", "Reflectance", "Anchored", "CanCollide", "CanQuery", "CanTouch", "CastShadow" },
		Attachment = { "CFrame" },
		Beam = { "Attachment0", "Attachment1", "CurveSize0", "CurveSize1", "Texture", "TextureMode", "TextureLength", "TextureSpeed", "Color", "Transparency", "LightEmission", "LightInfluence", "Width0", "Width1", "FaceCamera", "Segments" },
		ParticleEmitter = { "Texture", "Color", "LightEmission", "LightInfluence", "Transparency", "Size", "Rate", "Lifetime", "Speed", "SpreadAngle", "Acceleration", "EmissionDirection", "Rotation", "RotSpeed" },
		SpotLight = { "Face", "Angle", "Range", "Brightness", "Color", "Shadows" },
		PointLight = { "Range", "Brightness", "Color", "Shadows" },
		SurfaceLight = { "Face", "Angle", "Range", "Brightness", "Color", "Shadows" },
	}
	local ids = {}
	local nextId = 0
	local function idOf(x)
		if not ids[x] then
			nextId += 1
			ids[x] = nextId
		end
		return ids[x]
	end
	local function value(v)
		local t = Sim.typeof(v)
		if t == "Vector3" then
			return "V3", v3(v)
		elseif t == "CFrame" then
			return "CF", cf(v)
		elseif t == "Color3" then
			return "C3", c3(v)
		elseif t == "EnumItem" then
			return "EN", v.Name
		elseif t == "boolean" then
			return "B", tostring(v)
		elseif t == "number" then
			return "F", num(v)
		elseif t == "string" then
			return "S", v
		elseif t == "Vector2" then
			return "V2", num(v.X) .. "," .. num(v.Y)
		elseif t == "NumberRange" then
			return "NR", num(v.Min) .. "," .. num(v.Max)
		elseif t == "ColorSequence" then
			local parts = {}
			for _, k in v.Keypoints do
				table.insert(parts, num(k.Time) .. ":" .. c3(k.Value))
			end
			return "CS", table.concat(parts, ";")
		elseif t == "NumberSequence" then
			local parts = {}
			for _, k in v.Keypoints do
				table.insert(parts, num(k.Time) .. ":" .. num(k.Value) .. ":" .. num(k.Envelope))
			end
			return "NS", table.concat(parts, ";")
		elseif t == "Instance" then
			return "REF", tostring(idOf(v))
		end
		return nil, nil
	end
	local function walk(x, parentId)
		local d = D[x]
		local id = idOf(x)
		print(string.format("@N|%d|%d|%s|%s", id, parentId, d.cls, x.Name))
		for _, prop in PROPS[d.cls] or {} do
			local ok, v = pcall(function()
				return x[prop]
			end)
			if ok and v ~= nil then
				local kind, s = value(v)
				if kind then
					print(string.format("@Q|%d|%s|%s|%s", id, prop, kind, s))
				end
			end
		end
		for _, ch in d.children do
			walk(ch, id)
		end
	end
	Sim.runScript(Sim.mainServer, "server")
	Sim.run(3)
	local node = Sim.workspace
	for seg in string.gmatch(Sim.exportPath, "[^/]+") do
		node = node and node:FindFirstChild(seg)
	end
	assert(node, "export path not found: " .. Sim.exportPath)
	walk(node, 0)
end)() end
