-- Draws a 7-character digital frequency readout (e.g. "134.050"), same
-- character-by-character digital7.ttf technique already proven working in
-- radio_display.lua, packaged as a reusable component for an avionicsDevice.
-- Offsets scaled to match this device's real physical aspect ratio
-- (3.39:1, remeasured after the screen quad was resized) so nothing stretches.
--
-- Font size (40->80) and all x-offsets scaled 2x to match vhf2_display.lua's
-- reverted 2x canvas (220x65 -> 440x130) -- see that file for why the 4x
-- version was rolled back. Color {0.2,1,0.2,1} confirmed to exactly match
-- donor's own VHF color (vhf.lua line ~497).
--
-- Unlit segments: a faint "888.888" is drawn first at exactly the same 7
-- positions, font and size as the digits, and is shown even when the radio has
-- no power. The lit digits themselves are unchanged and still only appear when
-- powered.

defineProperty("freqHz", 0)
defineProperty("powered", function() return true end)
defineProperty("color", {0.2, 1, 0.2, 1})

-- fast-tuning "100 mode" from T154.radio.lua (1 while the fine knob is turned
-- quickly): the last two digits are hidden until the knob stops, like VHF1 in
-- cockpit v1. The unlit segments stay visible.
local vhf2_fast_mode = globalProperty("sim/custom/radios/vhf2_100mode")

font = loadFont("digital7.ttf")

-- ===== Unlit segments (values picked in the Kurs-MP Readout Picker) =====
local UNLIT_SEGMENTS = true
local UNLIT_LEVEL = 0.60
local UNLIT_BASE_COLOR = {0.14, 0.14, 0.14}   -- own unlit colour
-- ========================================================================

-- final unlit colour = base colour x level, fully opaque
local UNLIT_COLOR = {
	UNLIT_BASE_COLOR[1] * UNLIT_LEVEL, UNLIT_BASE_COLOR[2] * UNLIT_LEVEL, UNLIT_BASE_COLOR[3] * UNLIT_LEVEL, 1
}

-- the 7 character positions, unchanged
local X = { 30.0, 89.0, 148.0, 197.0, 218.8, 287.8, 356.8 }

local function split(str)
	if #str > 0 then return str:sub(1,1), split(str:sub(2)) end
end

local function drawChars(str, color)
	local chars = {split(str)}
	for i = 1, 7 do
		if chars[i] and chars[i] ~= " " then
			drawText(font, X[i], 24, chars[i], 80, true, true, TEXT_ALIGN_LEFT, color)
		end
	end
end

function draw()
	-- works whether SASL hands "powered" over as a value or as a function
	local isPowered = get(powered)
	if type(isPowered) == "function" then
		isPowered = isPowered()
	end

	-- faint unlit segments first, always visible (powered or not)
	if UNLIT_SEGMENTS then
		drawChars("888.888", UNLIT_COLOR)
	end

	if isPowered then
		-- same formula already confirmed correct in vhf.lua: freq/1000 with 3 decimals
		local str = string.format("%.3f", get(freqHz)/1000)
		while #str < 7 do str = str .. " " end
		if get(vhf2_fast_mode) == 1 then
			str = str:sub(1, 5) .. "  "
		end
		drawChars(str, get(color))
	end
end
