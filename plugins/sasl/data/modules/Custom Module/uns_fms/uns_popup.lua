-- UNS 2D panel: UNS_2d.png frame with the live UNS screen and every key clickable.
-- Keys go through uns_core.lua, exactly like the 3D keypads.

local core = request("uns_core")

local PW, PH = 979, 1033                    -- UNS_2d.png size (pixels)
local SX0, SY0, SX1, SY1 = 153, 63, 829, 480 -- text area of the screen in the PNG (top-left origin)
local GX0, GY0, GX1, GY1 = 139, 51, 843, 492 -- black screen: out to the bezel's dark inner rim

local bg = sasl.gl.loadImage("UNS_2d.png")
local screenBg = sasl.gl.loadImage("UNS_2d_screen.png") -- the screen (UNS background colour) with the bezel's rounded corners (704 x 441)

-- key click zones, measured from the PNG: { key, centre x, centre y, half width, half height }
local Z = {}
local function zone(k, cx, cy, hw, hh) Z[#Z + 1] = { k, cx, cy, hw, hh } end

-- function keys
local FX = { 94, 190, 287, 384, 480, 580 }
for i, k in ipairs({ "DATA", "NAV", "VNAV", "DTO", "LIST", "PREV" }) do zone(k, FX[i], 552, 43, 32) end
for i, k in ipairs({ "HOLD", "FPL", "PERF", "TUNE", "MENU", "NEXT" }) do zone(k, FX[i], 640, 43, 32) end
-- letters
local LX = { 85, 169, 252, 337, 419, 502, 585 }
for i, k in ipairs({ "A", "B", "C", "D", "E", "F", "G" }) do zone(k, LX[i], 733, 34, 34) end
for i, k in ipairs({ "H", "I", "J", "K", "L", "M", "N" }) do zone(k, LX[i], 819, 34, 34) end
for i, k in ipairs({ "O", "P", "Q", "R", "S", "T" }) do zone(k, LX[i + 1], 898, 34, 34) end
for i, k in ipairs({ "U", "V", "W", "X", "Y", "Z" }) do zone(k, LX[i + 1], 986, 34, 34) end
-- number pad
local NX = { 695, 794, 892 }
for i, k in ipairs({ "1", "2", "3" }) do zone(k, NX[i], 551, 41, 33) end
for i, k in ipairs({ "4", "5", "6" }) do zone(k, NX[i], 635, 41, 33) end
for i, k in ipairs({ "7", "8", "9" }) do zone(k, NX[i], 719, 41, 33) end
for i, k in ipairs({ "BACK", "0", "DEL" }) do zone(k, NX[i], 803, 41, 33) end
zone("DOT", NX[1], 887, 41, 33)
zone("SLASH", NX[2], 887, 41, 33)
zone("ENTER", 745, 976, 79, 31)
-- line select keys (button plus its dash)
local LY = { 141, 196, 251, 307, 362, 417 }
for i = 1, 6 do
	zone("L" .. i, 85, LY[i], 58, 26)
	zone("R" .. i, 895, LY[i], 58, 26)
end
core.popupZones = Z

local pressedKey, pressedUntil = nil, 0
local clock = sasl.createPerformanceTimer()
sasl.startTimer(clock)
local function now() return sasl.getElapsedSeconds(clock) end

-- red close dot (top right corner of the frame), like the KLN 2D panel; it is part of
-- UNS_2d.png (smooth edges), this is its click area
local CLOSE_X, CLOSE_Y, CLOSE_R = 948, 30, 17          -- centre and radius in PNG pixels

-- dragging: press on the frame (not on a key or the close dot) and move
local drag = nil   -- { x, y } press point in component coordinates

local BLACK = { 0, 0, 0, 1 }
local WHITE = { 1, 1, 1, 1 }
local PRESS = { 1, 1, 1, 0.18 }

function draw()
	local W, H = size[1], size[2]
	sasl.gl.drawTexture(bg, 0, 0, W, H, WHITE)

	local sx, sw = SX0 / PW * W, (SX1 - SX0) / PW * W
	local sy, sh = (1 - SY1 / PH) * H, (SY1 - SY0) / PH * H
	if core.faceOn() and core.powered() then
		local gx, gw = GX0 / PW * W, (GX1 - GX0) / PW * W
		local gy, gh = (1 - GY1 / PH) * H, (GY1 - GY0) / PH * H
		sasl.gl.drawTexture(screenBg, gx, gy, gw, gh, WHITE)
		-- the 2D panel is the captain's UNS (unit 1), always at full brightness
		-- (the brightness knob and the DIM page only dim the 3D screens)
		core.draw(sw, sh, sx, sy, 1, true)    -- the background is the rounded screen image
	end

	if pressedKey and now() < pressedUntil then
		local z = pressedKey
		local zx, zy = (z[2] - z[4]) / PW * W, (1 - (z[3] + z[5]) / PH) * H
		sasl.gl.drawRectangle(zx, zy, 2 * z[4] / PW * W, 2 * z[5] / PH * H, PRESS)
	end

end

function onMouseDown(component, x, y, button)
	local W, H = size[1], size[2]
	local px, py = x / W * PW, (1 - y / H) * PH
	-- red close dot
	if (px - CLOSE_X) ^ 2 + (py - CLOSE_Y) ^ 2 <= (CLOSE_R * 1.4) ^ 2 then
		if core.closePopup then core.closePopup() end
		return true
	end
	for _, z in ipairs(Z) do
		if math.abs(px - z[2]) <= z[4] and math.abs(py - z[3]) <= z[5] then
			pressedKey, pressedUntil = z, now() + 0.12
			core.key(z[1], 1)
			return true
		end
	end
	-- anywhere else on the frame: start moving the panel
	drag = { x, y }
	return true
end

-- move the panel while the mouse button is held (like the Boeing FMC popup)
function onMouseHold(component, x, y, button)
	if not drag or not core.popupWindow then return true end
	local win = core.popupWindow
	local ok, wx, wy, ww, wh = pcall(win.getPosition, win)
	if not ok or not wx then return true end
	local scale = ww / size[1]                 -- window pixels per component unit
	local dx, dy = (x - drag[1]) * scale, (y - drag[2]) * scale
	if math.abs(dx) >= 1 or math.abs(dy) >= 1 then
		pcall(win.setPosition, win, math.floor(wx + dx + 0.5), math.floor(wy + dy + 0.5), ww, wh)
	end
	return true
end

function onMouseUp(component, x, y, button)
	drag = nil
	return true
end
