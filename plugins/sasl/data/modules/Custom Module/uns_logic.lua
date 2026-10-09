-- UNS (CDU739) power logic
-- UNS1/UNS2 power now follows the real DME (СД-75) switches per side
-- (sd75_1_on/sd75_2_on + bus36/115 volt), matching course_mp.lua's own
-- dme_power condition, instead of the earlier generic avionics-only gating.

-- sim variables
defineProperty("sim_avionics_uns", globalPropertyi("sim/cockpit2/switches/avionics_power_on")) -- default sim avionics switcher (same dataref as electric_system/electric_panel.lua's sim_avionics)
defineProperty("gps_power", globalPropertyi("sim/cockpit2/radios/actuators/gps_power")) -- drives X-Plane's native CDU739/FMS logic (pilot slot)
defineProperty("gps2_power", globalPropertyi("sim/cockpit2/radios/actuators/gps2_power")) -- copilot slot power, needed for v2's Garmin display

-- custom datarefs (created in dataref_creator_1.lua)
defineProperty("uns1_on", globalPropertyi("tu154b2/custom/uns1_on"))
defineProperty("uns2_on", globalPropertyi("tu154b2/custom/uns2_on"))
defineProperty("uns_lit", globalPropertyf("tu154b2/custom/lights/uns_lit")) -- UNS night texture on/off (created in dataref_creator_1.lua)
defineProperty("gps_toggle", globalPropertyi("tu154b2/custom/switchers/ovhd/kln_on")) -- GPS toggle: last toggle of the upper overhead row

-- UNS screen brightness at load.
-- The UNS brightness knob (tu154_cockpit.obj manip + rotating cap in cockpit_1_RUS.obj) is
-- sim/cockpit2/switches/instrument_brightness_ratio[16]. X-Plane restores its own remembered
-- value for it when the flight loads, which is why the screens always came up "as before".
-- Writing it with the "...[16]" name-in-brackets form does not reach the array element in SASL,
-- so it is opened here with globalPropertyfae (array element, SASL counts from 1: [16] -> 17)
-- and held at UNS_BRIGHT_START for the first UNS_BRIGHT_HOLD_FRAMES frames, then released so
-- the knob works normally. (In v2 the same index is the Garmin's knob.)
local UNS_BRIGHT_START = 0.0          -- 0.0 = load at minimum, 1.0 = load at maximum
local UNS_BRIGHT_HOLD_FRAMES = 300    -- about 5 seconds
local uns_bright_knob = globalPropertyfae("sim/cockpit2/switches/instrument_brightness_ratio", 17)
local uns_bright_frames = 0

-- DME (СД-75) power switches, now driving UNS power instead of the generic
-- avionics master switch - same per-side condition course_mp.lua uses for
-- its own dme_power (bus36/115 + sd75_on).
defineProperty("sd75_1_on", globalPropertyi("tu154b2/custom/switchers/ovhd/sd75_1_on"))
defineProperty("sd75_2_on", globalPropertyi("tu154b2/custom/switchers/ovhd/sd75_2_on"))
defineProperty("bus36_volt", globalPropertyf("tu154b2/custom/elec/bus36_volt_pts250_2"))
defineProperty("bus115_volt", globalPropertyf("tu154b2/custom/elec/bus115_1_volt"))

-- cockpit variant (1 = v1), native-GPS override switch, FMS map-line suppressor
defineProperty("kontur_on", globalPropertyi("tu154b2/custom/b2/kontur_on"))
defineProperty("overrideGPS", globalPropertyi("sim/operation/override/override_gps"))
defineProperty("kill_map_fms_line", globalPropertyi("sim/graphics/misc/kill_map_fms_line"))

-- combined hide flag for KLN90: hidden only when NOT in v1 AND GPS is selected in v2
-- (i.e. always visible in v1, and follows the normal GPS/KLN toggle in v2)
defineProperty("show_gns_kln", globalPropertyi("tu154b2/custom/anim/show_gns")) -- created in dataref_creator_1.lua (loads first) - was redundantly re-created here with createGlobalPropertyi, causing an "already exists" warning on every load. Now just looked up. Forced permanently to 0 below, regardless of any external app/menu
defineProperty("kln_hide_v2only", globalPropertyi("tu154b2/custom/anim/kln_hide_v2only")) -- now created early in dataref_creator_1.lua

-- force KLN90 power on directly, bypassing the physical switch/bus dependency
defineProperty("kln_power_force", globalPropertyi("custom/KLN90/kln_power"))

-- UNS brightness (v1 knob, background/glass): the manip (tu154_cockpit.obj)
-- and rotation (cockpit_1_RUS.obj) both correctly drive
-- instrument_brightness_ratio[12] - confirmed working for real interaction
-- (dragging genuinely dims/brightens the background). No Lua-side startup
-- forcing here - multiple tested approaches (bracket-in-string on 16, 17,
-- 12; two-argument form at 0.0 and 1.0) each either had no effect or an
-- unreliable one, so none is included.

-- Orphaned-function consolidation (v1 only): repurposing the right-hand
-- knob for UNS background brightness left mid_left_panel_int_set with
-- nothing driving it in v1 - in your project's cockpit_lights.lua, that
-- one dataref feeds BOTH pedestal_int (drives mid_left_panel_int, which
-- lights the ABSU/console area) AND nvu_int (drives nvu_lit) - so both
-- went dark/orphaned together in v1, matching "ABSU lights up together
-- with NVU". v2 is untouched - its own original knob still drives
-- mid_left_panel_int_set directly there, exactly as in the B donor.
--
-- Fix: in v1, mirror ovhd_panel_int_set (the overhead panel knob, already
-- driving ARK-15 and the rest of the overhead panel via ovhd_panel_int)
-- into mid_left_panel_int_set too, so turning that one physical knob now
-- also restores both orphaned functions. Both are ordinary custom
-- datarefs (unlike the broken native brightness array), so this mirror
-- is reliable. Test by turning the OVERHEAD knob specifically - a static
-- comparison won't show anything since nothing changes until it's moved.
defineProperty("ovhd_panel_int_set", globalPropertyf("tu154b2/custom/lights/ovhd_panel_int_set"))
defineProperty("mid_left_panel_int_set", globalPropertyf("tu154b2/custom/lights/mid_left_panel_int_set"))

-- helper: only write a dataref when its value actually needs to change,
-- to avoid repeatedly re-triggering "power on"/"reset" style side effects
-- on native gauges every single frame
local function set_if_changed(prop, value)
	if get(prop) ~= value then
		set(prop, value)
	end
end

-- 2026-10-06: KONTUR FP TRANSFER GUARD
-- plugins/kontur_fp_transfer (B-donor leftover, Windows-only win.xpl) copies the FO's GNS flight plan
-- into the captain's FMS every frame and, unconditionally, deletes every captain-FMS entry beyond the
-- length of the FO's plan. With the GNS never selectable (show_gns forced to 0 below) the FO plan is
-- empty, so any origin/destination typed into the UNS is wiped the next frame ("letters disappear").
-- It never loaded on Mac (no mac.xpl), which is why the UNS works there. Removed from the repo, but
-- users who still have the folder get it switched off here. Retries for a few seconds in case it
-- loads after SASL.
local kfp_done = false
local kfp_tries = 0
local function kfp_info(id)
	local a, b, c, d = sasl.getPluginInfo(id)
	if type(a) == "table" then
		return tostring(a.name or a[1] or ""), tostring(a.path or a[2] or ""), tostring(a.signature or a[3] or ""), tostring(a.description or a[4] or "")
	end
	return tostring(a or ""), tostring(b or ""), tostring(c or ""), tostring(d or "")
end
local function kfp_disable()
	if kfp_done then return end
	kfp_tries = kfp_tries + 1
	if kfp_tries > 600 then kfp_done = true return end
	if not (sasl and sasl.countPlugins and sasl.getNthPlugin and sasl.getPluginInfo and sasl.disablePlugin) then
		kfp_done = true
		return
	end
	local ok, err = pcall(function()
		local n = sasl.countPlugins()
		for i = 0, n - 1 do
			local id = sasl.getNthPlugin(i)
			if id and id >= 0 then
				local name, path, sig, desc = kfp_info(id)
				local p = string.lower(path)
				if string.find(p, "kontur_fp_transfer", 1, true) or name == "Tu-154 Kontur FP Plugin" then
					if (not sasl.isPluginEnabled) or sasl.isPluginEnabled(id) then
						sasl.disablePlugin(id)
						sasl.logInfo("kontur_fp_transfer plugin found and disabled (it wipes UNS/FMS entries): " .. path)
					end
					kfp_done = true
				end
			end
		end
	end)
	if not ok then
		sasl.logInfo("kontur_fp_transfer guard error: " .. tostring(err))
		kfp_done = true
	end
end
kfp_disable()

function update()
	kfp_disable() -- kontur_fp_transfer guard (see above)

	-- UNS screen brightness at load (see top of file)
	if uns_bright_frames < UNS_BRIGHT_HOLD_FRAMES then
		uns_bright_frames = uns_bright_frames + 1
		set(uns_bright_knob, UNS_BRIGHT_START)
	end

	-- Orphaned-function consolidation (v1 only): mirror ovhd_panel_int_set
	-- into mid_left_panel_int_set so the overhead knob also restores the
	-- pedestal/ABSU + NVU lighting that lost its control input in v1.
	-- Left alone in v2, where the original knob still owns
	-- mid_left_panel_int_set directly.
	if get(kontur_on) == 1 then
		set_if_changed(mid_left_panel_int_set, get(ovhd_panel_int_set))
	end

	local avionics = get(sim_avionics_uns) == 1

	local uns1_power = get(sd75_1_on) == 1 and get(bus36_volt) > 30 and get(bus115_volt) > 100
	local uns2_power = get(sd75_2_on) == 1 and get(bus36_volt) > 30 and get(bus115_volt) > 100

	if uns1_power then
		set_if_changed(uns1_on, 1)
	else
		set_if_changed(uns1_on, 0)
	end

	if uns2_power then
		set_if_changed(uns2_on, 1)
	else
		set_if_changed(uns2_on, 0)
	end

	if get(uns1_on) > 0 or get(uns2_on) > 0 then
		set_if_changed(gps_power, 1)
	else
		set_if_changed(gps_power, 0)
	end

	-- UNS night texture (cockpit_center_panel_v1_RUS_LIT.png) follows the GPS toggle
	-- (last toggle of the upper overhead row, kln_on): lit only while that toggle is
	-- ON and there is 27V power (avionics)
	if get(gps_toggle) == 1 and avionics then
		set_if_changed(uns_lit, 1)
	else
		set_if_changed(uns_lit, 0)
	end

	-- power the copilot Garmin gauge (v2's display) whenever avionics are on
	if avionics then
		set_if_changed(gps2_power, 1)
	else
		set_if_changed(gps2_power, 0)
	end

	if get(kontur_on) == 1 then
		set_if_changed(overrideGPS, 0)
		-- kill_map_fms_line intentionally no longer forced here - this dataref is
		-- also used by the Kontur display's own route-line rendering, and forcing
		-- it to 0 conflicted with Kontur's own logic, causing its flightplan to
		-- only render correctly while the sim was paused.
	end

	-- KLN90: hidden only if in v2 (kontur_on=0) AND GPS is the selected option (show_gns=1)
	-- always visible in v1 regardless of show_gns
	if get(kontur_on) == 0 and get(show_gns_kln) == 1 then
		set_if_changed(kln_hide_v2only, 1)
	else
		set_if_changed(kln_hide_v2only, 0)
	end

	-- force KLN90 powered whenever it's actually visible
	if get(kln_hide_v2only) == 0 then
		set_if_changed(kln_power_force, 1)
	end

	-- UNS brightness now wired directly via the ABSU/NVU knob's own
	-- manipulator in tu154_cockpit.obj - no lua bridge needed.

	-- Force GPS/GNS to never be selectable, in both v1 and v2, regardless of
	-- what any other menu/app/plugin tries to set show_gns to. KLN always wins.
	set_if_changed(show_gns_kln, 0)

end
