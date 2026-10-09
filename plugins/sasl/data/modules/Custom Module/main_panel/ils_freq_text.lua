-- Draws one ILS/NAV frequency readout, e.g. "108.450"
-- (3 decimal digits, matching this project's course_mp.lua house style).
--
-- Font: digital7_space.fnt (Digital-7 Italic, wide-spaced bitmap version of the
-- M donor's digital7_it.fnt), already in Custom Module/. No extra files.
-- It is a fixed-width bitmap font: every digit, "-" and blank takes the same
-- step, and the "." tucks into the gap like a real 7-segment decimal point,
-- so the digits never move when the frequency changes.
-- Bitmap text has no size argument, so it is enlarged with a scale transform.
--
-- Optional faint unlit segments ("888.888") behind the digits, shown even when
-- unpowered. Lit digits are blank when unpowered, like the real unit.

defineProperty("freqHz", 0)
defineProperty("powered", true)

local nav_font = loadBitmapFont(moduleDirectory .. '/Custom Module/digital7_space.fnt')

-- ===== Tuning (screen is 242 x 65 px, same shape as the cockpit surface) =====
-- (values picked in the Kurs-MP Readout Picker)
local FONT_SIZE = 59       -- 62 = the font's native size; bigger stretches it (softer)
local CENTER_X = 129       -- horizontal centre of the "XXX.XXX" field
local CENTER_Y = 33        -- vertical centre of the digits
local DIGIT_COLOR = {0.99, 0.24, 0.09, 1}
local UNLIT_SEGMENTS = true    -- faint "888.888" behind the digits
local UNLIT_LEVEL = 0.33       -- brightness of the unlit segments (0.33 = 33%).
                               -- Much lower disappears in X-Plane's lit layer.
-- ==========================================

-- The device is drawn with 2x the dots (484 x 130, set in ils_display.lua), the
-- same method that made the VHF2 screen sharp. Settings above are in
-- "242 x 65 screen" units and are converted to device dots here.
local RES = 2

-- digital7_space.fnt metrics (native pixels): every character steps 44, the "."
-- steps 3; digits are 37 px tall.
local FIELD_ADV = 6 * 44 + 3           -- width of "888.888"
local GLYPH_H = 37

local SCALE = FONT_SIZE / 62 * RES     -- native font pixels -> device dots
local FIELD_X = CENTER_X * RES - FIELD_ADV * SCALE / 2
-- drawBitmapText's origin sits at the bottom of the digits, so drop it by half
-- a digit height to put the digits' middle on CENTER_Y
local FIELD_Y = CENTER_Y * RES - GLYPH_H * SCALE / 2

-- Unlit-segment colour: the digit colour dimmed against the black screen
-- (kept fully opaque so it doesn't depend on how the device texture blends alpha).
local UNLIT_COLOR = {
	DIGIT_COLOR[1] * UNLIT_LEVEL, DIGIT_COLOR[2] * UNLIT_LEVEL, DIGIT_COLOR[3] * UNLIT_LEVEL, 1
}

local function formatFreq(hz)
	-- dataref is in 10 kHz units, e.g. 10845 = 108.45 MHz -> "108.450"
	hz = math.floor(hz + 0.5)              -- guard against float noise like 10844.9999
	local mhz = math.floor(hz / 100)
	local khz_2digit = hz - mhz * 100
	-- %3d keeps the field exactly "XXX.XXX" even for an odd value like 0
	return string.format("%3d.%03d", mhz, khz_2digit * 10)
end

function draw()
	drawRectangle(0, 0, size[1], size[2], 0, 0, 0, 1)  -- black background

	local isPowered
	if type(get(powered)) == "function" then
		isPowered = get(powered)()
	else
		isPowered = get(powered)
	end

	saveGraphicsContext()
	setTranslateTransform(FIELD_X, FIELD_Y)
	setScaleTransform(SCALE, SCALE)

	-- faint unlit segments first (always visible, powered or not), lit digits on top
	if UNLIT_SEGMENTS then
		drawBitmapText(nav_font, 0, 0, "888.888", TEXT_ALIGN_LEFT, UNLIT_COLOR)
	end

	-- no lit digits without power; only the unlit segments remain
	if isPowered then
		drawBitmapText(nav_font, 0, 0, formatFreq(get(freqHz)), TEXT_ALIGN_LEFT, DIGIT_COLOR)
	end

	restoreGraphicsContext()
end
