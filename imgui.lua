local imgui = {}

imgui.skin = {
	background = Color(0, 0, 0, 0),
	backgroundHover = Color(0, 0, 0, 0),
	
	border = Color(255, 255, 255),
	borderHover = Color(255, 127, 0),
	
	foreground = Color(255, 255, 255),
	foregroundHover = Color(255, 127, 0),
	foregroundPress = Color(220, 80, 0),
}

local devCvar = GetConVar("developer")
function imgui.IsDeveloperMode()
	return not imgui.DisableDeveloperMode and devCvar:GetInt() > 0
end

local _devMode = false -- cached local variable updated once in a while

function imgui.Hook(name, id, callback)
	local hookUniqifier = debug.getinfo(1).short_src
	hook.Add(name, "IMGUI / " .. id .. " / " .. hookUniqifier, callback)
end

local gState = {}

imgui.Hook("PreRender", "Input", function()
	-- calculate mouse state
	local isWorldRenderPass = render.GetRenderTarget() == nil
	if isWorldRenderPass then
		local wasPressing = gState.pressing
		gState.pressing = input.IsMouseDown(MOUSE_LEFT) or input.IsKeyDown(KEY_E)
		gState.pressed = not wasPressing and gState.pressing
	end
end)

local traceResultTable = {}
local traceQueryTable = { output = traceResultTable }
local function isObstructed(eyepos, hitPos)
	local q = traceQueryTable
	q.start = eyepos
	q.endpos = hitPos
	if not q.filter then
		q.filter = { LocalPlayer() }
	end

	local tr = util.TraceLine(q)
	if tr.Hit then
		return true, tr.Entity
	else
		return false
	end
end

function imgui.Start3D2D(pos, angles, scale, distanceHide, distanceFadeStart)
	if gState.shutdown == true then
		return
	end
	
	if gState.rendering == true then
		print("[IMGUI] Starting a new IMGUI context when previous one is still rendering. Shutting down rendering pipeline to prevent crashes..")
		gState.shutdown = true
		return false
	end
	
	_devMode = imgui.IsDeveloperMode()
	
	local eyePos = LocalPlayer():EyePos()
	local eyePosToPos = pos - eyePos
	
	-- OPTIMIZATION: Test that we are in front of the UI
	do
		local normal = angles:Up()
		local dot = eyePosToPos:Dot(normal)
		
		if _devMode then gState._devDot = dot end
		
		-- since normal is pointing away from surface towards viewer, dot<0 is visible
		if dot >= 0 then
			return false
		end
	end
	
	-- OPTIMIZATION: Distance based fade/hide
	if distanceHide then
		local distance = eyePosToPos:Length()
		if distance > distanceHide then
			return false
		end
		
		if _devMode then
			gState._devDist = distance
			gState._devHideDist = distanceHide
		end
		
		if distanceHide and distanceFadeStart and distance > distanceFadeStart then
			local blend = math.min(math.Remap(distance, distanceFadeStart, distanceHide, 1, 0), 1)
			render.SetBlend(blend)
			surface.SetAlphaMultiplier(blend)
		end
	end
	
	gState.rendering = true
	gState.pos = pos
	gState.angles = angles
	gState.scale = scale
	
	cam.Start3D2D(pos, angles, scale)
	
	-- calculate mousepos
	if not vgui.CursorVisible() or vgui.IsHoveringWorld() then
		local tr = LocalPlayer():GetEyeTrace()
		local eyepos = tr.StartPos
		local eyenormal
		
		if vgui.CursorVisible() and vgui.IsHoveringWorld() then
			eyenormal = gui.ScreenToVector(gui.MousePos())
		else
			eyenormal = tr.Normal
		end
		
		local planeNormal = angles:Up()
	
		local hitPos = util.IntersectRayWithPlane(eyepos, eyenormal, pos, planeNormal)
		if hitPos then
			local obstructed, obstructer = isObstructed(eyepos, hitPos)
			if obstructed then
				gState.mx = nil
				gState.my = nil
				
				if _devMode then gState._devInputBlocker = "collision " .. obstructer:GetClass() .. "/" .. obstructer:EntIndex() end
			else
				local diff = pos - hitPos
	
				-- This cool code is from Willox's keypad CalculateCursorPos
				local x = diff:Dot(-angles:Forward()) / scale
				local y = diff:Dot(-angles:Right()) / scale
				
				gState.mx = x
				gState.my = y
			end
		else
			gState.mx = nil
			gState.my = nil
			
			if _devMode then gState._devInputBlocker = "not looking at plane" end
		end
	else
		gState.mx = nil
		gState.my = nil
		
		if _devMode then gState._devInputBlocker = "not hovering world" end
	end
	
	return true
end

function imgui.Entity3D2D(ent, lpos, lang, scale, ...)
	gState.entity = ent
	return imgui.Start3D2D(ent:LocalToWorld(lpos), ent:LocalToWorldAngles(lang), scale, ...)
end

function imgui.ExpandRenderBoundsFromRect(x, y, w, h)
	local ent = gState.entity
	if IsValid(ent) then
		-- make sure we're not applying same expansion twice
		local expansion = ent._imguiRBExpansion
		if expansion then
			local ex, ey, ew, eh = unpack(expansion)
			if ex == x and ey == y and ew == w and eh == h then
				return
			end
		end
		
		local pos = gState.pos
		local fwd, right = gState.angles:Forward(), gState.angles:Right()
		local scale = gState.scale
		local firstCorner, secondCorner =
			pos + fwd * x * scale + right * y * scale,
			pos + fwd * (x+w) * scale + right * (y+h) * scale
			
		local minrb, maxrb = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
		
		minrb.x = math.min(minrb.x, firstCorner.x, secondCorner.x)
		minrb.y = math.min(minrb.y, firstCorner.y, secondCorner.y)
		minrb.z = math.min(minrb.z, firstCorner.z, secondCorner.z)
		maxrb.x = math.max(maxrb.x, firstCorner.x, secondCorner.x)
		maxrb.y = math.max(maxrb.y, firstCorner.y, secondCorner.y)
		maxrb.z = math.max(maxrb.z, firstCorner.z, secondCorner.z)
		
		ent:SetRenderBoundsWS(minrb, maxrb)
		if _devMode then
			print("[IMGUI] Updated renderbounds of ", ent, " to ", minrb, "x", maxrb)
		end
		
		ent._imguiRBExpansion = {x, y, w, h}
	else
		if _devMode then
			print("[IMGUI] Attempted to update renderbounds when entity is not valid!! ", debug.traceback())
		end
	end
end

local function drawDeveloperInfo()
	local ang = LocalPlayer():EyeAngles()
	ang:RotateAroundAxis(ang:Right(), 90)
	ang:RotateAroundAxis(ang:Up(), -90)
	
	cam.IgnoreZ(true)
	cam.Start3D2D(gState.pos + Vector(0, 0, 30), ang, 0.15)
	surface.SetDrawColor(0, 0, 0, 200)
	surface.DrawRect(-100, 0, 200, 125)
	draw.SimpleText("imgui developer", "DefaultFixedDropShadow", 0, 5, Color(78, 205, 196), TEXT_ALIGN_CENTER, nil)
	
	local mx, my = gState.mx, gState.my
	if mx and my then
		draw.SimpleText(string.format("mouse: hovering %d x %d", mx, my), "DefaultFixedDropShadow", 0, 25, Color(0, 255, 0), TEXT_ALIGN_CENTER, nil)
	else
		draw.SimpleText(string.format("mouse: %s", gState._devInputBlocker or ""), "DefaultFixedDropShadow", 0, 25, Color(255, 0, 0), TEXT_ALIGN_CENTER, nil)
	end
	
	local pos = gState.pos
	draw.SimpleText(string.format("pos: %.2f %.2f %.2f", pos.x, pos.y, pos.z), "DefaultFixedDropShadow", 0, 45, nil, TEXT_ALIGN_CENTER, nil)
	draw.SimpleText(string.format("distance %.2f / %.2f", gState._devDist or 0, gState._devHideDist or 0), "DefaultFixedDropShadow", 0, 58, Color(200, 200, 200, 200), TEXT_ALIGN_CENTER, nil)
	
	local ang = gState.angles
	draw.SimpleText(string.format("ang: %.2f %.2f %.2f", ang.p, ang.y, ang.r), "DefaultFixedDropShadow", 0, 80, nil, TEXT_ALIGN_CENTER, nil)
	draw.SimpleText(string.format("dot %d", gState._devDot or 0), "DefaultFixedDropShadow", 0, 93, Color(200, 200, 200, 200), TEXT_ALIGN_CENTER, nil)
	
	local angToEye = (pos - LocalPlayer():EyePos()):Angle()
	angToEye:RotateAroundAxis(ang:Up(), -90)
	angToEye:RotateAroundAxis(ang:Right(), 90)
	
	draw.SimpleText(string.format("angle to eye (%d,%d,%d)", angToEye.p, angToEye.y, angToEye.r), "DefaultFixedDropShadow", 0, 106, Color(200, 200, 200, 200), TEXT_ALIGN_CENTER, nil)
	
	cam.End3D2D()
	cam.IgnoreZ(false)
end

function imgui.End3D2D()
	if gState then
		if _devMode then
			drawDeveloperInfo()
		end
		
		gState.rendering = false
		cam.End3D2D()
		render.SetBlend(1)
		surface.SetAlphaMultiplier(1)
	end
end

function imgui.CursorPos()
	local mx, my = gState.mx, gState.my
	return mx, my
end

function imgui.IsHovering(x, y, w, h)
	local mx, my = gState.mx, gState.my
	return mx and my and mx >= x and mx <= (x+w) and my >= y and my <= (y+h)
end
function imgui.IsPressing()
	return gState.pressing
end
function imgui.IsPressed()
	return gState.pressed
end

-- The cache that has String->Bool mappings telling if font has been created
local _createdFonts = {}

local EXCLAMATION_BYTE = string.byte("!")
function imgui.xFont(font, defaultSize)
	-- special font
	if string.byte(font, 1) == EXCLAMATION_BYTE then
		
		-- Font not cached; parse the font
		local name, size = font:match("!([^@]+)@(.+)")
		if size then size = tonumber(size) end
		
		if not size and defaultSize then
			name = font:match("^!([^@]+)$")
			size = defaultSize
		end
		
		local fontName = string.format("IMGUI_%s_%d", name, size)

		if not _createdFonts[fontName] then
			surface.CreateFont(fontName, {
				font = name,
				size = size
			})
			_createdFonts[fontName] = true
		end

		return fontName
	end
	return font
end

local colorMat = Material("color")
function imgui.xButton(x, y, w, h, borderWidth)
	borderWidth = borderWidth or 1
	
	local bgColor = imgui.IsHovering(x, y, w, h) and imgui.skin.backgroundHover or imgui.skin.background
	local borderColor = imgui.IsHovering(x, y, w, h) and imgui.skin.borderHover or imgui.skin.border
	
	surface.SetDrawColor(bgColor)
	surface.DrawRect(x, y, w, h)
	
	if borderWidth > 0 then
		surface.SetDrawColor(borderColor)
		surface.SetMaterial(colorMat)

		surface.DrawTexturedRect(x, y, w, borderWidth)
		surface.DrawTexturedRect(x, y, borderWidth, h)
		surface.DrawTexturedRect(x, y+h-borderWidth, w, borderWidth)
		surface.DrawTexturedRect(x+w-borderWidth, y, borderWidth, h)
	end
	
	return imgui.IsHovering(x, y, w, h) and gState.pressed
end

function imgui.xCursor(x, y, w, h)
	local fgColor = gState.pressing and imgui.skin.foregroundPress or imgui.skin.foreground
	local mx, my = gState.mx, gState.my
	
	if not mx or not my then return end
	
	if x and w and (mx < x or mx > x + w) then return end
	if y and h and (my < y or my > y + h) then return end
	
	local cursorSize = math.ceil(0.3 / gState.scale)
	surface.SetDrawColor(fgColor)
	surface.DrawLine(mx - cursorSize, my, mx + cursorSize, my)
	surface.DrawLine(mx, my - cursorSize, mx, my + cursorSize)
end

function imgui.xTextButton(text, font, x, y, w, h)
	local fgColor = imgui.IsHovering(x, y, w, h) and imgui.skin.foregroundHover or imgui.skin.foreground
	
	local clicked = imgui.xButton(x, y, w, h)
	
	font = imgui.xFont(font, math.floor(h * 0.618))
	draw.SimpleText(text, font, x+w/2, y+h/2, fgColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	
	return clicked
end

return imgui
