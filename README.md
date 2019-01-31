# imgui
Immediate mode 3D2D UI for Garry's Mod

### Features

- Creating clickable buttons or tracking mouse in an area requires one line of code
- Visibility optimizations to prevent UI from being rendered if it's not visible
- Only a wrapper for `cam.Start3D2D` so all `surface` library functions are still usable
- Error handling to prevent clients from crashing if a Lua error happens

### Installation

Place `imgui.lua` somewhere where it's accessible by client.
Include with `myimguireference = include("imgui.lua")`, and use through the `myimguireference` object.

### Example

Using it globally:
```lua
local imgui = include("imgui.lua") -- imgui.lua should be in same folder and AddCSLuaFile'd

hook.Add("PostDrawTranslucentRenderables", "PaintIMGUI", function(bDrawingSkybox, bDrawingDepth)
  -- Don't render during depth pass
  if bDrawingDepth then return end

  -- Starts the 3D2D context at given position, angle and scale.
  -- First 3 arguments are equivalent to cam.Start3D2D arguments.
  -- Fourth argument is the distance at which the UI panel won't be rendered anymore
  -- Fifth argument is the distance at which the UI will start fading away
  -- Function returns boolean indicating whether we should proceed with the rendering, hence the if statement
  -- These specific coordinates are for gm_construct at next to spawn
  if imgui.Start3D2D(Vector(980, -83, -79), Angle(0, 270, 90), 0.1, 200, 150) then
    -- This is a regular 3D2D context, so you can use normal surface functions to draw things
    surface.SetDrawColor(255, 127, 0)
    surface.DrawRect(0, 0, 100, 20)
    
    -- The main priority of the library is providing interactable panels
    -- This creates a clickable text button at x=0, y=30 with width=100, height=25
    -- The first argument is text to render inside button
    -- The second argument is special font syntax, that dynamically creates font "Roboto" at size 24
    -- The special syntax is just for convinience; you can use normal Garry's Mod font names in place
    if imgui.xTextButton("Foo bar", "!Roboto@24", 0, 30, 100, 25) then
      -- the xTextButton function returns true, if user clicked on this area during this frame
      print("yay, we were clicked :D")
    end
  
    -- End the 3D2D context
    imgui.End3D2D()
  end
end)
```

Using it inside an entity:
```lua
-- 3D2D UI should be rendered in translucent pass, so this should be either TRANSLUCENT or BOTH
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:DrawTranslucent()
  -- While you can of course use the imgui.Start3D2D function for entities, IMGUI has some special syntax
  -- This function automatically calls LocalToWorld and LocalToWorldAngles respectively on position and angles 
  if imgui.Entity3D2D(self, Vector(0, 0, 50), Angle(0, 90, 90), 0.1) then
    -- render things
    
    imgui.End3D2D()
  end
end
```
