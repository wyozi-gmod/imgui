# imgui
Immediate mode 3D2D UI for Garry's Mod

### Features

- Creating clickable buttons or tracking mouse in an area requires one line of code
- Visibility optimizations to prevent UI from being rendered if it's not visible
- Only a wrapper for `cam.Start3D2D` so all `surface` library functions are still usable
- Error handling to prevent clients from crashing if a Lua error happens

### Installation

Place `imgui.lua` somewhere in your addon or gamemode, eg. `myaddon/lua/myaddon/imgui.lua`.

On _SERVER_ do `AddCSLuaFile("imgui.lua")`

On _CLIENT_ (where you want to use imgui) do `local imgui = include("imgui.lua")`, and use through `imgui` object

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
    -- The third, fourth, fith and sixth arguments are for x, y, width and height
    -- The seventh argument is the border width (optional)
    -- The last 3 arguments are for color, hover color, and press color (optional)
    if imgui.xTextButton("Foo bar", "!Roboto@24", 0, 30, 100, 25, 1, Color(255,255,255), Color(0,0,255), Color(255,0,0)) then
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

### Debugging

![image](https://i.imgur.com/1KWwo57.png)

Setting the `developer` convar to non-zero value draws a debugging panel on top of each IMGUI panel you draw. It shows few pieces of useful information:
- The mouse coordinates or the reason why input is not enabled at the moment
- World position of the TDUI panel, our distance from it and the distance at which the interface is hidden
- World angles of the TDUI panel, the dot product between eye position and the panel and the angle between eye position and the panel
- How many milliseconds did we spend on rendering this UI per frame (averaged over 100 frames/renders)

If you wish to hide the developer panel even with `developer` cvar, set `imgui.DisableDeveloperMode = true` right after importing the library.

### API

#### 3D2D Context
Start 3D2D context 
```lua
imgui.Start3D2D(pos, angles, scale, distanceHide, distanceFadeStart)
```

Start 3D2D context on an entity. `pos`/`angles` are automatically transformed from local coordinates into world coordinates.

```lua
imgui.Entity3D2D(ent, lpos, lang, scale, distanceHide, distanceFadeStart)
```

Ends 3D2D Context
```lua
imgui.End3D2D()
```

#### Cursor
Retrieves cursor position in 3D2D space. `mx`/`my` are null if player is not looking at the interface
```lua
local mx, my = imgui.CursorPos()
```

Whether player's 3D2D cursor is within given bounds
```lua
local hovering = imgui.IsHovering(x, y, w, h)
```

Whether player is currently pressing
```lua
local pressing = imgui.IsPressing()
```

Whether player is pressed during this frame. This is guaranteed to only be called once per click
```lua
local pressed = imgui.IsPressed()
```

#### UI functions (prefixed by x to separate them from core functionality)

Draws a rectangle button without any text or content
```lua
local wasPressed = imgui.xButton(x, y, w, h, borderWidth, borderClr, hoverClr, pressColor)
```

Draws a button with text inside. The `font` parameter is passed through `imgui.xFont`, so special font syntax is supported.
The text is automatically centered within the button.
```lua
local wasPressed = imgui.xTextButton(text, font, x, y, w, h, color, hoverColor, pressColor)
```

Draws a cursor IF the cursor is within given bounds. Note: `x`,`y`,`w`,`h` should be the bounds for your whole IMGUI interface, eg. `0, 0, 512, 512` if you draw into the 3d2d space within those bounds.
```lua
imgui.xCursor(x, y, w, h)
```

#### Utility
Retrieves font name usable for Garry's Mod functions based on parameter. See __Special font API__ section below
```lua
local fontName = imgui.xFont("!Roboto@24")
```

Expands the entity's render bounds to cover the whole rectangle passed as 3D2D coordinates. Note: `x`,`y`,`w`,`h` should be the bounds for your whole IMGUI interface, eg. `0, 0, 512, 512` if you draw into the 3d2d space within those bounds.
(only usable inside `imgui.Entity3D2D` block, before `imgui.End3D2D` call)
```lua
imgui.ExpandRenderBoundsFromRect(x, y, w, h)
```

### Error recovery

One of the goals of the library is to not crash the client even if something throws an error during the 3D2D context. This is achieved by halting all rendering library-wide if we detect attempt at starting a new 3D2D context without never having called `End3D2D` in between.

The recovery protocol triggers automatically if you try to nest 3D2D contexts due to error or any other reason. You'll be notified with a `[IMGUI] Starting a new IMGUI context when previous one is still rendering. Shutting down rendering pipeline to prevent crashes..` message in console if that happens. The only way to recover from this error state is to re-initialize the whole library to reset the internal global state of IMGUI. There is no programmatic way to do this at the moment, but you can re-save the `imgui.lua` to trigger Lua autorefresh on it, or just reimport it.

### Special font API

IMGUI comes with a simplified method for creating fonts. If you use the built-in functions, such as `imgui.xTextButton`, the passed font argument will automatically go through the font syntax parser, but you can also access it directly with `imgui.xFont`.

Here's an example of using `imgui.xFont` for drawing normal text:
```lua
-- Draw 'Foo bar' using Roboto font at font size 30 at 0, 0
draw.SimpleText("Foo bar", imgui.xFont("!Roboto@30"), 0, 0)
```
