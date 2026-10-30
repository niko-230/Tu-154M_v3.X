defineProperty("rt_1", globalPropertyi("sim/custom/b2/rt12_1_dis"))
defineProperty("rt_2", globalPropertyi("sim/custom/b2/rt12_2_dis"))
defineProperty("rt_3", globalPropertyi("sim/custom/b2/rt12_3_dis"))
defineProperty("rt_cap_1", globalPropertyi("sim/custom/b2/rt12_1_dis_cap"))
defineProperty("rt_cap_2", globalPropertyi("sim/custom/b2/rt12_2_dis_cap"))
defineProperty("rt_cap_3", globalPropertyi("sim/custom/b2/rt12_3_dis_cap"))
defineProperty("ard", globalPropertyi("tu154b2/custom/switchers/eng/tail_temp_heat"))

defineProperty("ssos_1", globalPropertyi("sim/custom/ssos_test_btn1"))
defineProperty("ssos_2", globalPropertyi("sim/custom/ssos_test_btn2"))
defineProperty("ssos_3", globalPropertyi("sim/custom/ssos_test_btn3"))

defineProperty("rt_test_1", globalPropertyi("sim/custom/b2/stp_test_1"))
defineProperty("rt_test_2", globalPropertyi("sim/custom/b2/stp_test_2"))
defineProperty("rt_test_3", globalPropertyi("sim/custom/b2/stp_test_3"))

defineProperty("stp_test_1", globalPropertyi("sim/custom/b2/stp_test_4"))
defineProperty("stp_test_2", globalPropertyi("sim/custom/b2/stp_test_5"))
defineProperty("stp_test_3", globalPropertyi("sim/custom/b2/stp_test_6"))

defineProperty("test_cover", globalPropertyi("sim/custom/b2/stp_test_cap"))

defineProperty("gear_fan", globalPropertyi("tu154b2/custom/switchers/eng/gear_fan"))

defineProperty("gear_test", globalPropertyi("tu154b2/custom/buttons/lamp_test_upper_gear"))

defineProperty("sbros_1", globalPropertyi("sim/custom/b2/sbros_push"))
defineProperty("sbros_2", globalPropertyi("sim/custom/b2/sbros_stop"))

defineProperty("temp_1", globalPropertyi("tu154b2/custom/buttons/eng/tail_temp_signal_control_1"))
defineProperty("temp_2", globalPropertyi("tu154b2/custom/buttons/eng/tail_temp_signal_control_2"))

defineProperty("srd_buzz", globalPropertyi("tu154b2/custom/buttons/eng/srd_buzzer_test"))

defineProperty("fuel_buzz", globalPropertyi("tu154b2/custom/switchers/eng/fuel_buzzer"))
defineProperty("fuel_cap", globalPropertyi("tu154b2/custom/switchers/eng/fuel_buzzer_cap"))

defineProperty("lamp", globalPropertyi("sim/custom/eng_light_angle_btn"))
defineProperty("lamp_2", globalPropertyi("sim/custom/eng_light_angle2"))

defineProperty("pilot_Z", globalPropertyf("sim/aircraft/view/acf_peZ"))
defineProperty("pilot_X", globalPropertyf("sim/aircraft/view/acf_peX"))
defineProperty("pilot_head", globalPropertyi("sim/graphics/view/pilots_head_psi"))


local switcher_sound_L = loadSample(moduleDirectory .. '/Custom Sounds/metal_switch_L.wav')
local switcher_sound_2_L= loadSample(moduleDirectory .. '/Custom Sounds/metal_switch2_L.wav')
local cap_sound_L = loadSample(moduleDirectory .. '/Custom Sounds/cap_L.wav')
local button_sound_L = loadSample(moduleDirectory .. '/Custom Sounds/plastic_btn_L.wav')
local lamp_sound_L = loadSample(moduleDirectory .. '/Custom Sounds/new_snds/lustra_L.wav')
local skrip_sound_L = loadSample(moduleDirectory .. '/Custom Sounds/new_snds/lustra_skrip_L.wav')

local switcher_sound_R = loadSample(moduleDirectory .. '/Custom Sounds/metal_switch_R.wav')
local switcher_sound_2_R= loadSample(moduleDirectory .. '/Custom Sounds/metal_switch2_R.wav')
local cap_sound_R = loadSample(moduleDirectory .. '/Custom Sounds/cap_R.wav')
local button_sound_R = loadSample(moduleDirectory .. '/Custom Sounds/plastic_btn_R.wav')
local lamp_sound_R = loadSample(moduleDirectory .. '/Custom Sounds/new_snds/lustra_R.wav')
local skrip_sound_R = loadSample(moduleDirectory .. '/Custom Sounds/new_snds/lustra_skrip_R.wav')

local panel_x=0.5363198
local panel_z=-20.964985
local panel2_x=0.52685744
local panel2_z=-21.232027
local dist_gain=5


local function inn_balance (src_x, src_z, x, z , cam_hdg)

	local hdg_rad = math.rad(cam_hdg)
	-- local x_s = acf_x + src_x * math.cos(hdg_rad) - src_z * math.sin(hdg_rad)
	-- local z_s = acf_z + src_x * math.sin(hdg_rad) + src_z * math.cos(hdg_rad)
	local dist = math.sqrt(math.pow(src_x - x, 2) + math.pow(src_z - z, 2))
	
	if dist < 1 then dist = 1 end
	
	local angle2source = cam_hdg + math.deg(math.atan2(x - src_x, z - src_z)) -- angle from camera to the source
	while angle2source > 180 do angle2source = angle2source - 360 end
	while angle2source < -180 do angle2source = angle2source + 360 end
	local ch_L = (0.2/math.pow(dist,2) + (1 + math.sin(math.rad(angle2source))) ) 
	local ch_R = (0.2/math.pow(dist,2) + (1 + math.sin(math.rad(-angle2source))) )
	if ch_L > 1 then ch_L = 1 end
	if ch_R > 1 then ch_R = 1 end

	
	-- local ch_L = 0.4 + (1 + math.sin(math.rad(cam_hdg))) * 0.7 * 0.6 + (1 - dist / 20)	
	
	-- local ch_R = 0.4 + (1 + math.sin(math.rad(-cam_hdg))) * 0.7 * 0.6 + (1 - dist / 20)
	
	return ch_L, ch_R
end


-- =====================================================================
-- 2026-10-29: engineer-panel controls that came with the M panel and had
-- no click sound. Each control is watched on its own (no sums), and the
-- first frame only records the start position, so loading makes no click.
-- =====================================================================
local extra_switches = {   -- metal toggle switches
	"tu154b2/custom/switchers/eng/wing_light",          -- white ground lights on wingtips
	"tu154b2/custom/switchers/eng/water_meter",
	"tu154b2/custom/switchers/eng/water_compressor_1",
	"tu154b2/custom/switchers/eng/water_compressor_2",
	"tu154b2/custom/switchers/eng/galley_heat",
	"tu154b2/custom/switchers/eng/lavatory_heat",
	"tu154b2/custom/switchers/eng/gauges_on_1",
	"tu154b2/custom/switchers/eng/gauges_on_2",
	"tu154b2/custom/switchers/eng/gauges_on_3",
	"tu154b2/custom/switchers/eng/vibro_sel_1",
	"tu154b2/custom/switchers/eng/vibro_sel_2",
	"tu154b2/custom/switchers/eng/vibro_sel_3",
	"tu154b2/custom/switchers/spu_2_power",
	"tu154b2/custom/switchers/airbleed/ground_cond_on",
	"tu154b2/custom/switchers/airbleed/skv_faster_work",
	"tu154b2/custom/switchers/airbleed/air_valve_both",
}
local extra_caps = {       -- switch covers
	"tu154b2/custom/switchers/eng/hydro_trimm_rud_1_cap",
	"tu154b2/custom/switchers/eng/srd_buzzer_cap",
	"tu154b2/custom/switchers/airbleed/ground_cond_on_cap_eng",
	"tu154b2/custom/switchers/airbleed/skv_faster_work_cap_eng",
	"sim/custom/misc/itv_cap",
}
local extra_buttons = {    -- push buttons
	"tu154b2/custom/gauges/eng/oil_qty_1_h", "tu154b2/custom/gauges/eng/oil_qty_1_p",
	"tu154b2/custom/gauges/eng/oil_qty_2_h", "tu154b2/custom/gauges/eng/oil_qty_2_p",
	"tu154b2/custom/gauges/eng/oil_qty_3_h", "tu154b2/custom/gauges/eng/oil_qty_3_p",
	"tu154b2/custom/buttons/eng/control_ut",
	"tu154b2/custom/buttons/eng/cold_eng_1", "tu154b2/custom/buttons/eng/cold_eng_2",
	"tu154b2/custom/buttons/eng/cold_eng_3", "tu154b2/custom/buttons/eng/cold_apu",
	"tu154b2/custom/buttons/eng/smoke_test",
	"tu154b2/custom/buttons/fuel/fuel_meter_summ_zero",  "tu154b2/custom/buttons/fuel/fuel_meter_summ_max",
	"tu154b2/custom/buttons/fuel/fuel_meter_tank2_zero", "tu154b2/custom/buttons/fuel/fuel_meter_tank2_max",
	"tu154b2/custom/buttons/fuel/fuel_meter_tank3_zero", "tu154b2/custom/buttons/fuel/fuel_meter_tank3_max",
	"tu154b2/custom/buttons/fuel/fuel_meter_tank4_zero", "tu154b2/custom/buttons/fuel/fuel_meter_tank4_max",
	"tu154b2/custom/buttons/lamp_test_eng_up_1", "tu154b2/custom/buttons/lamp_test_eng_up_2",
	"tu154b2/custom/gauges/acs3/left_knob_press", "tu154b2/custom/gauges/acs3/right_knob_press",
}
local extra_commands = {   -- clock (ITV) setting buttons are commands, not datarefs
	"t154/itv_h_m", "t154/itv_h_p", "t154/itv_m_m", "t154/itv_m_p",
}

local function make_watch(list)
	local w = {}
	for i, name in ipairs(list) do w[i] = { ref = globalProperty(name), last = nil } end
	return w
end
local watch_sw  = make_watch(extra_switches)
local watch_cap = make_watch(extra_caps)
local watch_but = make_watch(extra_buttons)

local function play_at_panel(snd_L, snd_R)
	local z_pos = get(pilot_Z)
	local x_pos = get(pilot_X)
	local plt_hdg = get(pilot_head)
	local gain_L, gain_R = inn_balance(panel_x, panel_z, x_pos, z_pos, plt_hdg)
	gain_L = gain_L * 1000
	gain_R = gain_R * 1000
	local dist = 1
	if z_pos - panel_z ~= 0 then
		dist = math.min(1, 1 / math.sqrt(math.pow(z_pos - panel_z, 2) + math.pow(x_pos - panel_x, 2)) / dist_gain)
	end
	setSampleGain(snd_L, gain_L * dist)
	setSampleGain(snd_R, gain_R * dist)
	playSample(snd_L, false)
	playSample(snd_R, false)
end

local function changed(w)
	local any = false
	for _, c in ipairs(w) do
		local v = get(c.ref)
		if c.last ~= nil and v ~= c.last then any = true end
		c.last = v
	end
	return any
end

local itv_button_pressed = false
local function itv_hnd(phase)
	if phase == 0 then itv_button_pressed = true end
	return 1
end
local itv_registered = {}

local function extra_sounds()
	-- clock commands are created by xtlua, so hook them as soon as they exist
	for i, name in ipairs(extra_commands) do
		if not itv_registered[i] then
			local cmd = findCommand(name)
			if cmd then
				registerCommandHandler(cmd, 0, itv_hnd)
				itv_registered[i] = true
			end
		end
	end

	if changed(watch_sw)  then play_at_panel(switcher_sound_L, switcher_sound_R) end
	if changed(watch_cap) then play_at_panel(cap_sound_L, cap_sound_R) end
	if changed(watch_but) or itv_button_pressed then
		itv_button_pressed = false
		play_at_panel(button_sound_L, button_sound_R)
	end
end


-- =====================================================================
-- 2026-10-29: throttle lever stop click (each lever, at full forward and
-- at full back / idle). Follows the visible lever (same value that moves
-- the 3D lever). A lever must move away from the stop before it can click
-- again there, and loading the aircraft makes no click.
-- =====================================================================
local thr_click_L = loadSample(moduleDirectory .. '/Custom Sounds/throttle_click_L.wav')
local thr_click_R = loadSample(moduleDirectory .. '/Custom Sounds/throttle_click_R.wav')
local thr_x, thr_z = 0.01, -22.73            -- pilots' throttle levers (centre pedestal), sound-system coordinates

-- same distance rule as the ABSU buttons (absu_panel.lua), so the click stays audible over flight noise:
-- 0.2 m -> 75%, 0.5 m -> 50%, 1.0 m -> 30%, 1.5 m -> 20%, 2.0 m -> 10%, beyond 2 m keeps falling as 1/d
local THR_VOLUME = 0.5   -- overall loudness of the throttle click (1.0 = full, 0.5 = half)
local thr_curve = {{0.2,0.75},{0.5,0.5},{1.0,0.3},{1.5,0.2},{2.0,0.1}}
local function thr_dist(d)
	if d <= thr_curve[1][1] then return thr_curve[1][2] end
	for n = 2, #thr_curve do
		local p0, p1 = thr_curve[n-1], thr_curve[n]
		if d <= p1[1] then
			return p0[2] + (p1[2]-p0[2]) * (d-p0[1]) / (p1[1]-p0[1])
		end
	end
	local last = thr_curve[#thr_curve]
	return last[2] * last[1] / d
end
local thr_levers = {
	{ ref = globalPropertyf("tu154b2/custom/controlls/throttle_1"), at = nil },
	{ ref = globalPropertyf("tu154b2/custom/controlls/throttle_2"), at = nil },
	{ ref = globalPropertyf("tu154b2/custom/controlls/throttle_3"), at = nil },
}
local THR_END  = 0.002   -- counts as "at the stop"
local THR_AWAY = 0.03    -- must leave the stop by this much to re-arm

local function play_throttle_click()
	local z_pos = get(pilot_Z)
	local x_pos = get(pilot_X)
	local plt_hdg = get(pilot_head)
	local gain_L, gain_R = inn_balance(thr_x, thr_z, x_pos, z_pos, plt_hdg)
	gain_L = gain_L * 1000
	gain_R = gain_R * 1000
	local dist = thr_dist(math.sqrt(math.pow(z_pos - thr_z, 2) + math.pow(x_pos - thr_x, 2))) * THR_VOLUME
	setSampleGain(thr_click_L, gain_L * dist)
	setSampleGain(thr_click_R, gain_R * dist)
	playSample(thr_click_L, false)
	playSample(thr_click_R, false)
end

local function throttle_clicks()
	local click = false
	for _, lev in ipairs(thr_levers) do
		local v = get(lev.ref)
		local now
		if v >= 1 - THR_END then now = "full"
		elseif v <= THR_END then now = "idle"
		elseif v > THR_AWAY and v < 1 - THR_AWAY then now = "mid"
		else now = lev.at end                       -- near a stop but not on it: keep state
		if lev.at ~= nil and now ~= lev.at and (now == "full" or now == "idle") then click = true end
		lev.at = now or "mid"
	end
	if click then play_throttle_click() end
end


local changes_sw_prev =0
local changes_sw2_prev =0
local changes_but_prev =0
local changes_cap_prev =0
local changes_cap2_prev=0
local changes_lamp_prev=0
function update()

	local changes_sw  = get(rt_1)+get(rt_2)+get(rt_3)+get(ard)+get(gear_fan)+get(fuel_buzz)
	local changes_sw2 = get(rt_test_1)+get(rt_test_2)+get(rt_test_3)+get(stp_test_1)+get(stp_test_2)+get(stp_test_3)
	local changes_but = get(temp_1)+get(temp_2)+get(ssos_1)+get(ssos_2)+get(ssos_3)+get(srd_buzz)+get(gear_test)+get(sbros_1)+get(sbros_2)
	local changes_cap = get(rt_cap_1)+get(rt_cap_2)+get(rt_cap_3)+get(fuel_cap)
	local changes_cap2= get(test_cover)
	local changes_lamp=get(lamp_2)

	if changes_sw ~= changes_sw_prev then 		
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel_x, panel_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*1000
		gain_R=gain_R*1000
		local dist=1
		if z_pos-panel_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel_z,2)+math.pow(x_pos-panel_x,2))/dist_gain)
		end
		setSampleGain(switcher_sound_L,gain_L*dist)
		setSampleGain(switcher_sound_R,gain_R*dist)
		playSample(switcher_sound_L, false)
		playSample(switcher_sound_R, false)
	end
	if changes_sw2 ~= changes_sw2_prev then 		
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel_x, panel_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*1000
		gain_R=gain_R*1000
		local dist=1
		if z_pos-panel_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel_z,2)+math.pow(x_pos-panel_x,2))/dist_gain)
		end
		setSampleGain(switcher_sound_2_L,gain_L*dist)
		setSampleGain(switcher_sound_2_R,gain_R*dist)
		playSample(switcher_sound_2_L, false)
		playSample(switcher_sound_2_R, false)
	end
	
	if changes_but_prev~=changes_but then 		
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel_x, panel_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*1000
		gain_R=gain_R*1000
		local dist=1
		if z_pos-panel_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel_z,2)+math.pow(x_pos-panel_x,2))/dist_gain)
		end
		setSampleGain(button_sound_L,gain_L*dist)
		setSampleGain(button_sound_R,gain_R*dist)
		playSample(button_sound_L, false)
		playSample(button_sound_R, false)
	end
	
	if changes_cap_prev~=changes_cap  then 		
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel_x, panel_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*1000
		gain_R=gain_R*1000
		local dist=1
		if z_pos-panel_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel_z,2)+math.pow(x_pos-panel_x,2))/dist_gain)
		end
		setSampleGain(cap_sound_L,gain_L*dist)
		setSampleGain(cap_sound_R,gain_R*dist)
		playSample(cap_sound_L, false)
		playSample(cap_sound_R, false)
	end
	
	if changes_cap2_prev~=changes_cap2 then 		
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel_x, panel_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*700
		gain_R=gain_R*700
		local dist=1
		if z_pos-panel_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel_z,2)+math.pow(x_pos-panel_x,2))/dist_gain)
		end
		setSampleGain(skrip_sound_L,gain_L*dist)
		setSampleGain(skrip_sound_R,gain_R*dist)
		playSample(skrip_sound_L, false)
		playSample(skrip_sound_R, false)
	end
	
	if changes_lamp_prev~=changes_lamp then 		
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel2_x, panel2_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*700
		gain_R=gain_R*700
		local dist=1
		if z_pos-panel2_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel2_z,2)+math.pow(x_pos-panel2_x,2))/dist_gain)
		end
		setSampleGain(skrip_sound_L,gain_L*dist)
		setSampleGain(skrip_sound_R,gain_R*dist)
		playSample(skrip_sound_L, false)
		playSample(skrip_sound_R, false)
	end

	if get(lamp)>0 then
		local z_pos=get(pilot_Z)
		local z_pos=get(pilot_Z)
		local x_pos=get(pilot_X)
		local plt_hdg=get(pilot_head)
		local gain_L, gain_R = inn_balance (panel2_x, panel2_z, x_pos, z_pos , plt_hdg)
		gain_L=gain_L*700
		gain_R=gain_R*700
		local dist=1
		if z_pos-panel2_z~=0 then
			dist=math.min(1,1/math.sqrt(math.pow(z_pos-panel2_z,2)+math.pow(x_pos-panel2_x,2))/dist_gain)
		end
		setSampleGain(lamp_sound_L,gain_L*dist)
		setSampleGain(lamp_sound_R,gain_R*dist)
		if not isSamplePlaying(lamp_sound_L) then
			playSample(lamp_sound_L, false)
			playSample(lamp_sound_R, false)
		end
	end

	extra_sounds()
	throttle_clicks()

	changes_sw_prev  =changes_sw  
	changes_sw2_prev =changes_sw2 
	changes_but_prev =changes_but 
	changes_cap_prev =changes_cap 
	changes_cap2_prev=changes_cap2
	changes_lamp_prev=changes_lamp

end