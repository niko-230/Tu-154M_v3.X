-- Draws red DME distance as a fixed "XXX.X" 7-segment readout, like an old
-- electronic clock: "  5.3", " 23.4", "123.4", "---.-" (no signal), blank if unpowered.
-- Converts NM->KM using the same factor and switch as course_mp.lua
-- (tu154b2/custom/switchers/nav_1/2_mile_km, 1 = km, matching B/M donor).
-- Power gated on the real Kurs-MP unit's own power condition (curs_np_on_1/2 + buses).
--
-- Rendering (2026-11-12): the digits are the engineer's МСРП clock digits (green_digit_strip.png,
-- drawn there by digitstapeLit.lua), in red: red_digit_strip.png in Custom Module, one row of
-- 11 cells (digits 0..9 and "-"), each 92 x 112 px, leaning 6 degrees (italic, baked into the
-- picture so it stays sharp; each digit leans from its bottom). Every character is one whole cell drawn into
-- a FIXED slot, so nothing ever moves; the cells already place a "1" on the right segments,
-- like a real 7-segment display.
--   [ d ][ d ][ d ] , [ d ]      (the comma is white paint on the glass, a 3D mesh)
-- The slots stay exactly where they were with the old font, so the painted comma still sits
-- in the gap before the tenths.

defineProperty("distNm", 0)
defineProperty("mileKm", 1)
defineProperty("powered", true)
defineProperty("bright", 1)    -- digit brightness knob 0..1 (dme_display.lua)

-- red МСРП clock digits: one image per cell (digits 0..9, then "-")
local CELL_W, CELL_H = 92, 112          -- one cell of red_digit_strip.png (px; 80 + 12 for the lean)
local CELL_INK_CX = 37                  -- centre of a digit's ink bottom across the cell (px)
local CELL_INK_BOTTOM = 10              -- ink bottom, from the cell's bottom (px)
local CELL_INK_H = 90                   -- ink height of a full "8" (px)
local digitImg = {}
for d = 0, 9 do digitImg[tostring(d)] = loadImage("red_digit_strip.png", d * CELL_W, 0, CELL_W, CELL_H) end
digitImg["-"] = loadImage("red_digit_strip.png", 10 * CELL_W, 0, CELL_W, CELL_H)

-- ===== Tuning (screen is 215 x 70 px) =====
-- (values picked in the DME Readout Picker)
local FONT_SIZE = 67       -- (old font size: only fixes the slot positions, which the painted comma follows)
local DIGIT_HEIGHT = 46.9  -- height of the МСРП digits (same height as the old digits)
local FIELD_SHIFT = 2.0    -- all slots moved right by this (the МСРП digits are wider; keeps the
                           -- tenths digit clear of the painted comma and the left edge as before)
local CENTER_X = 100       -- horizontal centre of the whole 5-slot field
local CENTER_Y = 35        -- vertical centre of the digits (35 = middle of screen)
local DIGIT_GAP = 21       -- px of empty space between neighbouring digits
local POINT_EXTRA = 8      -- extra px added to the gap that holds the decimal point
local DIGIT_COLOR = {0.89, 0.23, 0.17, 1}   -- LED red-orange (the comma's glow; the digits are red in the picture)
local BRIGHT_MIN = 0.50      -- lit-digit brightness at the knob's lowest stop (50% of full)
local LIT_COLOR = {1, 1, 1, 1}  -- brightness of the red picture (knob)
local UNLIT_SEGMENTS = true    -- faint "888.8" behind the digits, like a real LED display
local UNLIT_LEVEL = 0.20       -- brightness of the unlit segments in daylight (0.20 = 20%; was 0.33 --
                               -- lowered 2026-11-12: the МСРП digit picture is brighter than the old font).
                               -- In-sim the screen is drawn on the emissive (LIT) layer,
                               -- which swallows very dark values: 0.05 looked fine in a
                               -- browser but was invisible in X-Plane.
-- ==========================================

-- Sharper digits: the device is drawn with 2x the dots (430 x 140, set in dme_display.lua),
-- the same method that made the VHF2 screen sharp (vhf2_display.lua 220x65 -> 440x130).
-- Your settings above stay in "215 x 70 screen" units; here they are converted
-- directly to the bigger dot count (no scale transform -- that is what broke before).
local RES = 2
FONT_SIZE = FONT_SIZE * RES
CENTER_X = CENTER_X * RES
CENTER_Y = CENTER_Y * RES
DIGIT_GAP = DIGIT_GAP * RES
POINT_EXTRA = POINT_EXTRA * RES
DIGIT_HEIGHT = DIGIT_HEIGHT * RES
FIELD_SHIFT = FIELD_SHIFT * RES

-- Font metrics of digital7.ttf (units per em 2048), used to place glyphs exactly.
local EM = 2048
local px = FONT_SIZE / EM
local DIGIT_INK_W = 782 * px           -- width of a full "8"
local DIGIT_ADV_R = 123 * px           -- empty space right of every digit's ink
local DIGIT_INK_H = 1434 * px          -- height of a digit
local BASELINE_Y = CENTER_Y - DIGIT_INK_H / 2

-- Advance width of each digit in digital7.ttf (font units), measured from the font.
local DIGIT_ADVANCE = {
	["0"] = 1028, ["1"] = 376, ["2"] = 1028, ["3"] = 931, ["4"] = 1028,
	["5"] = 1028, ["6"] = 1028, ["7"] = 931, ["8"] = 1028, ["9"] = 1028,
}

-- Evenly spaced digit slots, like the donor: [d] [d] [d] . [d]
-- The whole field is centred on CENTER_X; the decimal point sits in the gap
-- between slot 3 and slot 5 (character index 4 is the point).
local PITCH = DIGIT_INK_W + DIGIT_GAP
local FIELD_W = 3 * PITCH + POINT_EXTRA + DIGIT_INK_W
local inkLeft = {}
inkLeft[1] = CENTER_X - FIELD_W / 2
inkLeft[2] = inkLeft[1] + PITCH
inkLeft[3] = inkLeft[2] + PITCH
inkLeft[5] = inkLeft[3] + PITCH + POINT_EXTRA

local POINT_X = (inkLeft[3] + DIGIT_INK_W + inkLeft[5]) / 2   -- middle of that gap

-- Horizontal centre of a digit slot (used to centre the dashes).
local function digitInkCenter(i)
	return inkLeft[i] + DIGIT_INK_W / 2 + FIELD_SHIFT
end

-- one МСРП cell drawn so its ink is DIGIT_HEIGHT tall, centred on the slot, bottom on BASELINE_Y
local CELL_SCALE = DIGIT_HEIGHT / CELL_INK_H
local DRAW_W, DRAW_H = CELL_W * CELL_SCALE, CELL_H * CELL_SCALE

local MAX_DIST = 999.9   -- 5-character field limit

-- ===== Dark-cockpit fade for the unlit segments =====
-- The screen is drawn on X-Plane's light-emitting layer, so anything drawn there
-- glows at the same strength day and night. Real unlit segments only reflect
-- light, so their level here follows the sun: full UNLIT_LEVEL in daylight,
-- fading to UNLIT_NIGHT x UNLIT_LEVEL at night (0 = completely dark).
-- Same sun-angle dataref vhf2_display.lua already uses for its day/night dimming.
local UNLIT_NIGHT = 0.0        -- unlit level left at night (0.0 = gone, 1.0 = no fade)
local FADE_DARK_SUN = -6.0     -- sun pitch (deg) where it is fully dark (end of civil dusk)
local FADE_DAY_SUN = 10.0      -- sun pitch (deg) where the full daytime level is reached
local UNLIT_POWERED_NIGHT = 0.41 -- (0.41 x 0.20 = same night level as before: 0.25 x 0.33)
                                 -- while the device is ON, ghosts never fade below this x their
                                 -- daytime level, so they stay faintly visible at night.
                                 -- At night the whole screen also runs at only 20% (NIGHT_BRIGHTNESS in
                                 -- the _display.lua file), so 0.5 here ends up very dim.
                                 -- 0.0 = hidden at night even when ON, 1.0 = full daytime level.
-- ====================================================
local sun_pitch_unlit = globalPropertyf("sim/graphics/scenery/sun_pitch_degrees")

-- 0..1 daylight factor with a soft S-curve so the fade has no visible "step"
local function unlitDaylight()
	local t = (get(sun_pitch_unlit) - FADE_DARK_SUN) / (FADE_DAY_SUN - FADE_DARK_SUN)
	if t <= 0 then t = 0 elseif t >= 1 then t = 1 end
	t = t * t * (3 - 2 * t)
	return UNLIT_NIGHT + (1 - UNLIT_NIGHT) * t
end


-- unlit colour = red picture x UNLIT_LEVEL x (daylight, or the ON-at-night level), fully opaque
-- (one table reused every frame, so no new memory per frame)
local UNLIT_COLOR = {0, 0, 0, 1}
local UNLIT_MIN_VISIBLE = 0.02   -- below this, skip drawing the ghosts at all

local function updateUnlitColor(isPowered)
	-- daylight; while the device is ON, never below UNLIT_POWERED_NIGHT
	-- (cockpit lights do not change the ghosts)
	local light = unlitDaylight()
	if isPowered and UNLIT_POWERED_NIGHT > light then light = UNLIT_POWERED_NIGHT end
	local k = UNLIT_LEVEL * light
	UNLIT_COLOR[1] = k   -- the picture is already red: dim it evenly
	UNLIT_COLOR[2] = k
	UNLIT_COLOR[3] = k
	return k
end

-- ===== Backlit rim around the painted comma =====
-- The comma itself is white paint on the glass (3D mesh in cockpit_front_panel_RUS.obj /
-- cockpit_front_panel_kontur_RUS.obj, lit like any other surface). While the DME is on,
-- the display's red light leaks past the paint's edges: drawn here, on the screen BEHIND
-- the painted comma, as a soft red band around its outline. The paint covers the middle,
-- so only the glowing edge is seen. (values picked in the DME Painted Comma preview)
local RIM_WIDTH = 3.3    -- how far the glow reaches past the comma's edge (screen px)
local RIM_LEVEL = 0.10   -- glow strength right at the edge (0..1), fades outward
local RIM_STEPS = 4      -- soft fade made of this many bands (outer = faint, inner = strong)
-- comma shape/position: must match the 3D comma mesh (same numbers it was built from)
local COMMA_SIZE = 5.5   -- radius of the round head (screen px)
local COMMA_TAIL = 10.5  -- tail length below the head (screen px)
local COMMA_BOLD = 1.80  -- tail boldness (1 = thin tail)
local COMMA_X = 3.5      -- shift right(+)/left(-) from the old point position
local COMMA_Y = 8.0      -- shift up(+)/down(-) from the digits' bottom line

local COMMA_CX = POINT_X + COMMA_X * RES
local COMMA_CY = BASELINE_Y + COMMA_Y * RES

-- comma outline (same curve as the mesh), in device px around the comma centre:
-- round head (radius r) with a tapered tail hooking down-left (length t below the head)
local function commaOutline(r, t, w)
	local function q(p0, c, p1, s)
		return (1-s)*(1-s)*p0[1] + 2*(1-s)*s*c[1] + s*s*p1[1],
		       (1-s)*(1-s)*p0[2] + 2*(1-s)*s*c[2] + s*s*p1[2]
	end
	local pts = {}
	local a1 = math.rad(math.min(290, 250 + (w - 1) * 40))   -- where the tail leaves the head (bolder = further round)
	for i = 0, 28 do local a = a1 * i / 28; pts[#pts+1] = {r * math.cos(a), r * math.sin(a)} end
	local tip = {-0.75*r, -(r + t)}
	local inS = pts[#pts]
	for i = 1, 8 do local x, y = q(inS, {(0.05 - (w - 1)*0.6)*r, -1.15*r}, tip, i/8); pts[#pts+1] = {x, y} end
	for i = 1, 11 do local x, y = q(tip, {1.05*r, -(r + 0.35*t)}, {r, 0}, i/12); pts[#pts+1] = {x, y} end
	return pts
end

-- simple ear clipping -> list of triangles {x1,y1,x2,y2,x3,y3}
local function triangulate(p)
	local idx = {}
	local area = 0
	for i = 1, #p do local a, b = p[i], p[i % #p + 1]; area = area + a[1]*b[2] - b[1]*a[2] end
	if area > 0 then for i = 1, #p do idx[i] = i end else for i = 1, #p do idx[i] = #p + 1 - i end end
	local function cross(a, b, c) return (b[1]-a[1])*(c[2]-a[2]) - (b[2]-a[2])*(c[1]-a[1]) end
	local tris, guard = {}, 0
	while #idx > 3 and guard < 2000 do
		guard = guard + 1
		for k = 1, #idx do
			local i0 = idx[(k - 2) % #idx + 1]; local i1 = idx[k]; local i2 = idx[k % #idx + 1]
			local a, b, c = p[i0], p[i1], p[i2]
			if cross(a, b, c) > 1e-9 then
				local ear = true
				for _, j in ipairs(idx) do
					if j ~= i0 and j ~= i1 and j ~= i2 then
						local q = p[j]
						if cross(a, b, q) >= 0 and cross(b, c, q) >= 0 and cross(c, a, q) >= 0 then ear = false; break end
					end
				end
				if ear then
					tris[#tris+1] = {a[1], a[2], b[1], b[2], c[1], c[2]}
					table.remove(idx, k)
					break
				end
			end
		end
	end
	local a, b, c = p[idx[1]], p[idx[2]], p[idx[3]]
	tris[#tris+1] = {a[1], a[2], b[1], b[2], c[1], c[2]}
	return tris
end

-- precomputed once: outline points and fill triangles in device px (screen position included)
local RIM_PTS, RIM_TRIS = {}, {}
do
	local o = commaOutline(COMMA_SIZE * RES, COMMA_TAIL * RES, COMMA_BOLD)
	for i, v in ipairs(o) do RIM_PTS[i] = {COMMA_CX + v[1], COMMA_CY + v[2]} end
	RIM_TRIS = triangulate(RIM_PTS)
end

-- the outline grown by d px = the comma filled + every edge thickened + round corners.
-- Drawn opaque in one colour, so overlapping pieces do not add up.
local function fillGrown(d, color)
	for _, t in ipairs(RIM_TRIS) do drawTriangle(t[1], t[2], t[3], t[4], t[5], t[6], color) end
	local n = #RIM_PTS
	for i = 1, n do
		local a, b = RIM_PTS[i], RIM_PTS[i % n + 1]
		local ex, ey = b[1] - a[1], b[2] - a[2]
		local l = math.sqrt(ex*ex + ey*ey)
		if l > 1e-6 then
			local nx, ny = -ey / l * d, ex / l * d
			drawTriangle(a[1]+nx, a[2]+ny, b[1]+nx, b[2]+ny, b[1]-nx, b[2]-ny, color)
			drawTriangle(a[1]+nx, a[2]+ny, b[1]-nx, b[2]-ny, a[1]-nx, a[2]-ny, color)
		end
		drawCircle(a[1], a[2], d, true, color)
	end
end

local RIM_COLORS = {}
for s = 1, RIM_STEPS do RIM_COLORS[s] = {0, 0, 0, 1} end

-- k = digit brightness (knob). Bands from outside in; each band's colour is what the
-- stacked half-transparent bands of the preview add up to over the black screen.
local function drawRim(k)
	if RIM_LEVEL <= 0 or RIM_WIDTH <= 0 then return end
	local v = 0
	for s = RIM_STEPS, 1, -1 do
		local a = RIM_LEVEL * k * (RIM_STEPS - s + 1) / RIM_STEPS
		v = a + v * (1 - a)
		local c = RIM_COLORS[s]
		c[1] = DIGIT_COLOR[1] * v; c[2] = DIGIT_COLOR[2] * v; c[3] = DIGIT_COLOR[3] * v
		fillGrown(RIM_WIDTH * RES * s / RIM_STEPS, c)
	end
end
-- ==================================================

local function formatDist(dist)
	-- Truncate to 0.1 like the M donor (small +0.03 so e.g. 12.3999 shows 12.4),
	-- which counts like a real display instead of flickering on rounding.
	local shown = math.floor((dist + 0.03) * 10) / 10
	if shown <= 0 then
		return "---.-"
	end
	if shown > MAX_DIST then
		shown = MAX_DIST
	end
	-- %5.1f pads with leading spaces to exactly 5 chars: "  5.3", " 23.4", "123.4"
	return string.format("%5.1f", shown)
end


local function drawChar(i, ch, color)
	local img = digitImg[ch]
	if not img then return end           -- " " (blank) and anything else: nothing
	local x = digitInkCenter(i) - CELL_INK_CX * CELL_SCALE
	local y = BASELINE_Y - CELL_INK_BOTTOM * CELL_SCALE
	drawTexture(img, x, y, DRAW_W, DRAW_H, color or LIT_COLOR)
end

function draw()
	drawRectangle(0, 0, size[1], size[2], 0, 0, 0, 1)  -- black background

	-- called every frame (it also drives the MILE/KM lamps)
	local isPowered
	if type(get(powered)) == "function" then
		isPowered = get(powered)()
	else
		isPowered = get(powered)
	end

	-- faint unlit segments first (always visible, powered or not, like the
	-- physical segment pattern of a real display), lit digits on top
	if UNLIT_SEGMENTS and updateUnlitColor(isPowered) > UNLIT_MIN_VISIBLE then
		-- 2026-11-06: no decimal point on the screen any more -- the real unit has a
		-- white comma painted on the glass (now a 3D mesh in cockpit_front_panel_RUS.obj /
		-- cockpit_front_panel_kontur_RUS.obj, lit like any other painted surface)
		local ghost = "888 8"
		for i = 1, 5 do
			drawChar(i, ghost:sub(i, i), UNLIT_COLOR)
		end
	end

	-- no lit digits without power; only the unlit segments remain
	if isPowered then
		local dist = get(distNm)
		if get(mileKm) == 1 then
			dist = dist * 1.852  -- nm -> km, same factor as course_mp.lua
		end

		-- digit brightness knob: scales only the lit digits
		local b = get(bright)
		if b == nil then b = 1 end
		if b < 0 then b = 0 elseif b > 1 then b = 1 end
		local k = BRIGHT_MIN + (1 - BRIGHT_MIN) * b
		LIT_COLOR[1] = k   -- the picture is already red: dim it evenly
		LIT_COLOR[2] = k
		LIT_COLOR[3] = k

		-- backlit rim around the painted comma (behind the paint, before the digits)
		drawRim(k)

		local text = formatDist(dist)
		text = text:sub(1, 3) .. " " .. text:sub(5)   -- drop the point (painted comma on the glass)
		for i = 1, 5 do
			drawChar(i, text:sub(i, i), LIT_COLOR)
		end
	end

end
