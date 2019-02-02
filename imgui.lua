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

	return util.TraceLine(q).Hit
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
	
	local eyePos = LocalPlayer():EyePos()
	local eyePosToPos = pos - eyePos
		
	-- OPTIMIZATION: Test that we are in front of the UI
	do
		local normal = angles:Up()
		local dot = eyePosToPos:Dot(normal)
		
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
			if isObstructed(eyepos, hitPos) then
				gState.mx = nil
				gState.my = nil
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
		end
	else
		gState.mx = nil
		gState.my = nil
	end
	
	return true
end

function imgui.Entity3D2D(ent, lpos, lang, scale, ...)
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
		
		ent._imguiRBExpansion = {x, y, w, h}
	end
end

function imgui.End3D2D()
	if gState then
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
