-- UNS screen set-up (cockpit v1): 3D avionics device, 2D panel and the UNS menu.
-- Included from main.lua after the components table (it reads datarefs created
-- by dataref_creator_1, like ils_display.lua / vhf2_display.lua).
--
-- Menu: Aircraft > UNS
--   "UNS-1 FMS"              ticked = UNS screen + UNS 2D panel (default)
--   "X-Plane FMC (default)"  ticked = X-Plane's own CDU screen + its Boeing-style popup,
--                            keys work exactly as before (for an FPS comparison)
--   "UNS-1 2D panel"         opens/closes the 2D panel (same as clicking the UNS screen)

local uns_core = request("uns_core")

local uns_sun   = globalPropertyf("sim/graphics/scenery/sun_pitch_degrees")
local uns_power = globalPropertyi("tu154b2/custom/uns1_on")
local uns_face  = globalPropertyi("tu154b2/custom/uns/face")

-- screen brightness = UNS brightness knob (instrument_brightness_ratio[16], the knob's
-- own dataref in tu154_cockpit.obj; SASL counts array elements from 1, so 17),
-- times a day/night factor like the VHF2 screen. Never fully dark at the knob's
-- minimum, so a powered UNS is always readable.
local uns_knob = globalPropertyfae("sim/cockpit2/switches/instrument_brightness_ratio", 17)
local UNS_KNOB_MIN = 0.15          -- screen level with the knob at minimum (part of full)
local UNS_NIGHT_BRIGHTNESS = 0.45
local UNS_DAY_BRIGHTNESS = 1.00
local UNS_TWILIGHT_START = -6.0
local UNS_TWILIGHT_END = 15.0

local function uns_brightness(u)
	if get(uns_power) ~= 1 or get(uns_face) ~= 1 then return 0 end
	if uns_core.unitActive and not uns_core.unitActive(u) then return 0 end
	local pitch = get(uns_sun)
	local day
	if pitch <= UNS_TWILIGHT_START then
		day = UNS_NIGHT_BRIGHTNESS
	elseif pitch >= UNS_TWILIGHT_END then
		day = UNS_DAY_BRIGHTNESS
	else
		local t = (pitch - UNS_TWILIGHT_START) / (UNS_TWILIGHT_END - UNS_TWILIGHT_START)
		day = UNS_NIGHT_BRIGHTNESS + t * (UNS_DAY_BRIGHTNESS - UNS_NIGHT_BRIGHTNESS)
	end
	-- each unit's own DIM page setting (the brightness knob dims the night texture instead)
	local dim = uns_core.unitBrt and uns_core.unitBrt(u) or 1
	return day * (UNS_KNOB_MIN + (1 - UNS_KNOB_MIN) * dim)
end

-- 3D screen: 800 x 506 dots = the 103 x 65 mm opening of the UNS bezel.
-- The text is rendered into its own texture 10 times a second (fbo + fpsLimit);
-- every other frame only that finished picture is drawn.
-- captain's UNS (unit 1, also shown on the 2D panel)
uns_screen_device = avionicsDevice {
	name = "UNS 1 Screen",
	id = "tu154b2/uns_screen",
	size = { 800, 506 },
	screenClear = true,
	brightnessCallback = function() return uns_brightness(1) end,
	components = {
		uns_screen { position = { 0, 0, 800, 506 }, fbo = true, fpsLimit = 10, unit = 1 },
	},
}
-- right UNS (unit 2)
uns_screen2_device = avionicsDevice {
	name = "UNS 2 Screen",
	id = "tu154b2/uns_screen2",
	size = { 800, 506 },
	screenClear = true,
	brightnessCallback = function() return uns_brightness(2) end,
	components = {
		uns_screen { position = { 0, 0, 800, 506 }, fbo = true, fpsLimit = 10, unit = 2 },
	},
}

if not uns_screen_device or not uns_screen2_device then
	logWarning("UNS screen: avionics device could not be created")
end

-- 2D panel (same size rules as the other 2D panels)
local uns_wh = globalPropertyi("sim/graphics/view/window_height")
local uns_coef = (get(uns_wh) / 1024) * 0.8
if uns_coef > 1 then uns_coef = 1 end
local UNS_W, UNS_H = math.floor(979 * 0.62 * uns_coef), math.floor(1033 * 0.62 * uns_coef)

uns_2d_panel = contextWindow {
	position = { 80, 60, UNS_W, UNS_H },
	noBackground = true,
	noDecore = true,
	noClose = true,
	resizeProportional = true,
	minimumSize = { 979 * 0.3, 1033 * 0.3 },
	maximumSize = { 979 * 1.2, 1033 * 1.2 },
	savePosition = true,
	name = "uns_2d_panel",
	components = {
		uns_popup { position = { 0, 0, UNS_W, UNS_H } },
	},
}

uns_core.popupWindow = uns_2d_panel   -- the 2D panel moves itself when dragged by its frame
uns_core.onPopup = function()
	uns_2d_panel:setIsVisible(not uns_2d_panel:isVisible())
end
uns_core.closePopup = function()
	if uns_2d_panel:isVisible() then uns_2d_panel:setIsVisible(false) end
end

-- Aircraft > UNS menu: which FMS is on the screens (one of the two is ticked), and the
-- 2D panel of the UNS-1
local uns_menu_item = sasl.appendMenuItem(AIRCRAFT_MENU_ID, "UNS")
local uns_menu = sasl.createMenu("UNS", AIRCRAFT_MENU_ID, uns_menu_item)
local uns_item_uns, uns_item_xp
local function uns_menu_states()
	local on = get(uns_face) == 1
	sasl.setMenuItemState(uns_menu, uns_item_uns, on and MENU_CHECKED or MENU_UNCHECKED)
	sasl.setMenuItemState(uns_menu, uns_item_xp, on and MENU_UNCHECKED or MENU_CHECKED)
end
uns_item_uns = sasl.appendMenuItem(uns_menu, "UNS-1 FMS", function()
	set(uns_face, 1)
	uns_menu_states()
end)
uns_item_xp = sasl.appendMenuItem(uns_menu, "X-Plane FMC (default)", function()
	set(uns_face, 0)
	uns_menu_states()
end)
uns_menu_states()
if sasl.appendMenuSeparator then pcall(sasl.appendMenuSeparator, uns_menu) end
local uns_popup_cmd = sasl.findCommand("tu154/uns/popup")
sasl.appendMenuItem(uns_menu, "UNS-1 2D panel", function()
	if uns_popup_cmd then sasl.commandOnce(uns_popup_cmd) end
end)
