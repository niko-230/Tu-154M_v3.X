--createGlobalPropertyf("tu154b2/custom/controlls/flap_debugg", 1)
--createGlobalPropertyf("tu154b2/custom/controlls/flap_debugg2", 1)

defineProperty("cl", globalPropertyf("sim/aircraft/controls/acf_flap_cl"))
defineProperty("cd", globalPropertyf("sim/aircraft/controls/acf_flap_cd"))
defineProperty("cm", globalPropertyf("sim/aircraft/controls/acf_flap_cm"))

defineProperty("cl2", globalPropertyf("sim/aircraft/controls/acf_flap2_cl"))
defineProperty("cd2", globalPropertyf("sim/aircraft/controls/acf_flap2_cd"))
defineProperty("cm2", globalPropertyf("sim/aircraft/controls/acf_flap2_cm"))

--defineProperty("flap_debug", globalPropertyf("tu154b2/custom/controlls/flap_debugg")) 
-- defineProperty("c1", globalPropertyf("tu154b2/custom/controlls/debug1"))
-- defineProperty("c2", globalPropertyf("tu154b2/custom/controlls/debug2"))

defineProperty("db1", globalPropertyf("tu154b2/custom/controlls/debug1"))
defineProperty("db2", globalPropertyf("tu154b2/custom/controlls/debug2"))
defineProperty("db3", globalPropertyf("tu154b2/custom/controlls/debug3"))

--[[
sim/aircraft/controls/acf_flap_cl	float	y
sim/aircraft/controls/acf_flap_cd	float	y
sim/aircraft/controls/acf_flap_cm	float	y
sim/aircraft/controls/acf_flap2_cl	float	y
sim/aircraft/controls/acf_flap2_cd	float	y
sim/aircraft/controls/acf_flap2_cm	float	y
--]]
defineProperty("flap", globalPropertyf("sim/flightmodel/controls/flaprat"))
defineProperty("alt", globalPropertyf("sim/flightmodel/position/y_agl"))
--defineProperty("yd", globalPropertyf("sim/cockpit2/switches/yaw_damper_on"))

defineProperty("flap_inn_L", globalPropertyf("sim/flightmodel/controls/wing1l_fla1def")) -- inner flaps left
defineProperty("flap_inn_R", globalPropertyf("sim/flightmodel/controls/wing1r_fla1def")) -- inner flaps right

defineProperty("flap_mid_L", globalPropertyf("sim/flightmodel/controls/wing2l_fla2def")) -- middle flaps left
defineProperty("flap_mid_R", globalPropertyf("sim/flightmodel/controls/wing2r_fla2def")) -- middle flaps right

-- NOTE: originally read "tu154b2/custom/SC/thrust_1"/"_3" (a SmartCopilot-bridge
-- dataref that doesn't appear to be created anywhere in this codebase -- confirmed
-- via Log.txt: "not found", then nil-value crash once actually used in arithmetic).
-- Switched to the same stock dataref rud_logic.lua already reads successfully
-- (R_1/R_2/R_3), indices 0=left engine, 2=right engine.
defineProperty("thrust_L", globalProperty("sim/cockpit2/engine/indicators/thrust_dry_n[0]")) 
defineProperty("thrust_R", globalProperty("sim/cockpit2/engine/indicators/thrust_dry_n[2]"))
defineProperty("true_airspeed", globalPropertyf("sim/flightmodel/position/true_airspeed"))

defineProperty("cl_GE1", globalProperty("sim/flightmodel/parts/CL_grndeffect[8]"))
defineProperty("cd_GE1", globalProperty("sim/flightmodel/parts/CD_grndeffect[8]"))
defineProperty("cl_GE2", globalProperty("sim/flightmodel/parts/CL_grndeffect[9]"))
defineProperty("cd_GE2", globalProperty("sim/flightmodel/parts/CD_grndeffect[9]"))

-- ported from M: slat position and on-ground detection, needed for M's tuned
-- flap aero formulas (slat interaction term, touchdown pitch softening)
-- NOTE: donor's own dataref "sim/flightmodel/controls/wing1l_sla1def" doesn't
-- resolve in this aircraft (confirmed via Log.txt: nil value, repeating error).
-- Switched to B's own proven-working slat dataref (see flaps.lua's own comment
-- "this one works too"), which is a 0-1 ratio rather than raw degrees -- scaled
-- by the acf's real _slat1_dn_max_deg (10 deg) in update() below.
defineProperty("slat_L", globalPropertyf("sim/flightmodel2/controls/slat1_deploy_ratio"))
defineProperty("gear_on_ground_L", globalProperty("sim/flightmodel2/gear/on_ground[1]"))
defineProperty("gear_on_ground_R", globalProperty("sim/flightmodel2/gear/on_ground[2]"))

defineProperty("gear1_deploy", globalProperty("sim/aircraft/parts/acf_gear_deploy[0]"))  -- deploy of front gear
defineProperty("gear2_deploy", globalProperty("sim/aircraft/parts/acf_gear_deploy[1]"))  -- deploy of right gear
defineProperty("gear3_deploy", globalProperty("sim/aircraft/parts/acf_gear_deploy[2]"))  -- deploy of left gear

defineProperty("pitch_add", globalProperty("sim/flightmodel/forces/M_plug_acf"))
defineProperty("lift_left", globalProperty("sim/flightmodel2/wing/elements/element_cl_total[2]"))
defineProperty("lift_right", globalProperty("sim/flightmodel2/wing/elements/element_cl_total[12]"))

defineProperty("dens", globalPropertyf("sim/weather/rho"))
-- sim/version/xplane_internal_version
--defineProperty("xp_version", globalPropertyi("sim/version/xplane_internal_version"))

--print("new flaps")


-- local flap1_cl_tbl = {
-- {-10, 1.029},
-- {0, 1.0},
-- {15, 1.0}, -- 1.4
-- {28, 1.1},
-- {36, 1.25},
-- {45, 1.35},
-- {100, 1.2}
-- }

-- local flap2_cl_tbl = {
-- {-10, 1.189},
-- {0, 1.1},
-- {13, 1.1}, -- 1.5
-- {25, 1.3},
-- {32, 1.45},
-- {40, 1.55},
-- {100, 1.4}
-- }



-- -- XP 11
-- local XP11 = get(xp_version) > 11000

--if XP11 then

	-- flap1_cl_tbl = {
	-- {-10, 1.029},
	-- {0, 1.0},
	-- {15, 1.0}, -- 1.4
	-- {28, 1.1*0.83},
	-- {36, 1.15},
	-- {45, 1.25*1.1},
	-- {100, 1.2}
	-- }

	-- flap2_cl_tbl = {
	-- {-10, 1.189},
	-- {0, 1.1},
	-- {13, 1.1}, -- 1.5
	-- {25, 1.3*0.83},
	-- {32, 1.35},
	-- {40, 1.45*1.1},
	-- {100, 1.4}
	-- }

--end






-- local flap1_cd_tbl = {
-- {-10, 0.064},
-- {0, 0.064},
-- {15, 0.064},
-- --{28, 1.1},
-- {36, 0.085},
-- {45, 0.07},
-- {100, 0.06}
-- }

-- local flap2_cd_tbl = {
-- {-10, 0.074},
-- {0, 0.074},
-- {13, 0.074},
-- --{25, 1.3},
-- {32, 0.1},
-- {40, 0.08},
-- {100, 0.07}
-- }



-- local flap1_cm_tbl = {
-- {-10, 0},
-- {0, -0.15},
-- {15, -0.2}, -- -0.13
-- {28, -0.475},
-- --{36, -0.2},
-- {45, -0.6},
-- {100, -0.2}
-- }

-- local flap2_cm_tbl = {
-- {-10, -0.2},
-- {0, -0.1}, -- 0
-- {13, -0.3}, -- 15
-- {25, -0.475}, -- 28,
-- --{32, -0.3}, -- 36
-- {40, -0.6}, -- 45
-- {100, -0.3}
-- }

local engine_lift_tbl={
{-300, 1},
{270, 1},
{370, 0},
{1000, 0},
}
local engine_lift_tbl2={
{-300, 0},
{0, 0},
{6000, 1},
{100000, 1},
}

-- 2026-10-27 PITCH LOGGER (temporary, for calibration against the RLE / 1997 book trim curves).
-- Every 5 s while airborne it writes one line to X-Plane's Log.txt starting with "T154PITCH".
-- Remove this block (or set PITCH_LOG = false) once the pitch package is final.-- 2026-10-27: safety guard -- never write NaN/inf into X-Plane's flight model (it can stall the sim)
function fm_ok(v, fallback, lo, hi)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return fallback end
	if lo and v < lo then return lo end -- 2026-10-27 SAFETY: keep every value sent to X-Plane in a realistic range
	if hi and v > hi then return hi end
	return v
end

FLAP45_CD_SCALE = 0.66 -- 2026-10-29: flaps-45 drag calibrated to the 1997 book (see flap1_cd/flap2_cd in update)
FLAP_CL_SCALE = 0.76 -- 2026-10-29: flap lift calibrated to the 1997 book (see flap1_cl/flap2_cl in update)
PITCH_LOG = false -- calibration logger off for release (set true to log T154PITCH lines again)
plog = {
	t = 0,
	w   = globalPropertyf("sim/flightmodel/weight/m_total"),
	cg  = globalPropertyf("sim/cockpit2/gauges/indicators/CG_indicator"),
	ias = globalPropertyf("sim/flightmodel/position/indicated_airspeed"),
	mach= globalPropertyf("sim/flightmodel/misc/machno"),
	alt = globalPropertyf("sim/flightmodel/position/elevation"),
	vs  = globalPropertyf("sim/flightmodel/position/vh_ind"),
	the = globalPropertyf("sim/flightmodel/position/theta"),
	aoa = globalPropertyf("sim/flightmodel/position/alpha"),
	stb = globalPropertyf("sim/cockpit2/controls/elevator_trim"),
	elv = globalPropertyf("tu154b2/custom/controlls/elev_L_phys"),
	ftime = globalPropertyf("tu154b2/custom/time/frame_time"),
	gnd = globalPropertyi("sim/flightmodel/failures/onground_any"),
}
function pitch_log(flap_deg, slat_ratio, thr_n)
	if not PITCH_LOG then return end
	plog.t = plog.t + (get(plog.ftime) or 0)
	if plog.t < 5 then return end
	plog.t = 0
	if (get(plog.gnd) or 1) == 1 and (get(plog.ias) or 0)*1.852 < 150 then return end -- also logs the takeoff roll/rotation above 150 km/h
	sasl.logInfo(string.format("T154PITCH GND=%d W=%.0f CG=%.1f IAS=%.0f M=%.3f ALT=%.0f VS=%.1f THE=%.1f AOA=%.1f FLAP=%.1f SLAT=%.2f STAB=%.2f ELEV=%.1f THR=%.0f",
		get(plog.gnd) or 0, get(plog.w) or 0, (get(plog.cg) or 0)*100/5.28+50, (get(plog.ias) or 0)*1.852, get(plog.mach) or 0,
		get(plog.alt) or 0, get(plog.vs) or 0, get(plog.the) or 0, get(plog.aoa) or 0,
		flap_deg, slat_ratio, (get(plog.stb) or 0)*5.5, get(plog.elv) or 0, thr_n))
end

function update()
	local r_1=get(thrust_L) or 0
	local r_3=get(thrust_R) or 0
	local tas=(get(true_airspeed) or 0)*3.6
	local q=(get(dens) or 0)/2*math.pow(tas/3.6,2)
	local lift=((get(lift_left) or 0)+(get(lift_right) or 0))/2*q
	local flap_inn = math.max(get(flap_inn_L) or 0, 15)
	local flap_out = math.max(get(flap_mid_L) or 0, 15)
	-- Slat contributions (2026-08-21 tuning):
	-- Real slat deploys to 22 deg per 1997 PDF. Lua now scales ratio to 22 deg for Cl/Cd benefit.
	-- slat_cm_add coefficient REDUCED to keep total nose-up Cm same as pre-22 deg change,
	-- avoiding the worsened balloon. acf _slat1_dn_max_deg reverted to 10 (visual) since
	-- native model uses _slat1_inc=8 deg for main slat effect regardless of max angle.
	local slat = (get(slat_L) or 0) * 22 -- 0-22 scale for Cl/Cd (was *10, now *22 for lift benefit)
	local slat_cm_scale = 10/22  -- Cm stays at same total as before: 22 * (0.0024*10/22) = 0.024
	local main_on_ground = ((get(gear_on_ground_L) or 0) + (get(gear_on_ground_R) or 0)) > 0.5

	-- ported from M (donor's own comment: "optimized for 78-80% RPM mode and soft
	-- touchdown"): slat interaction terms
	local slat_cl_add = slat * 0.0016  -- original M donor coefficient
	-- 2026-10-27 SIGN FIX: X-Plane flap Cm is nose-down when NEGATIVE (M values -0.30/-0.34). The old "+ slat*0.006"
	-- made the flaps LESS nose-down when slats deploy, i.e. a nose-UP of ~6% MAC equivalent with full slats -- the
	-- opposite of what this comment intends. Now subtracts, so slats give the intended nose-down correction.
	local slat_cm_add = -slat * 0.006   -- INCREASED: real 22 deg slats produce ~2.5x more nose-down Cm than 10 deg sim. Directly counteracts native XP12 pitch-up from _slat1_inc=8 during deployment. Calibrated to eliminate balloon without affecting landing balance.
	local slat_cd_add = slat * 0.0007

	-- Ground Effect Correction (M's formula)
	local GE_lift=get(cl_GE1) or 1.0
	if GE_lift < 1.0 then GE_lift = 1.0 end
	if GE_lift > 1.12 then GE_lift = 1.12 end

	-- ported from M: Drag Correction (quadratic, replaces B's linear formula)
	local flap1_cd = (2.80e-05*math.pow(flap_inn,2) + 3.75e-03*flap_inn + 0.058) + slat_cd_add
	local flap2_cd = (3.15e-05*math.pow(flap_out,2) + 3.95e-03*flap_out + 0.063) + slat_cd_add
	local cd_corr = 0.00115*math.pow(GE_lift,33.0) + 0.99
	-- ported from M: "clean M aerodynamics" -7% multiplier
	-- CALIBRATED (2026-08-21): factor reduced from 0.93 to 0.74 based on observed
	-- 8-10% excess power needed on approach vs M donor (same conditions). At approach
	-- flap drag ~50% of total drag -> 20% reduction in flap Cd -> ~10% total drag reduction.
	flap1_cd = flap1_cd*cd_corr*0.74
	flap2_cd = flap2_cd*cd_corr*0.74
	-- 2026-10-29 BOOK CALIBRATION (Бехтир 1997, Table 1: flaps 45 + gear Kmax 5.6; section 6.15: glideslope needs
	-- 75-80% N2): a logged steady flaps-45 descent (76 t, Cy 1.15) gave L/D 4.5 vs ~5.4 from the book polar, i.e.
	-- ~20% too much drag, which is why the glideslope needed ~84% N2. Engine part-power thrust checked OK.
	-- Only the extra flap drag beyond 28 deg is reduced (flaps 28 unchanged, full effect at 45).
	local fl45 = math.max(0, math.min(1, (flap_inn - 28) / 17))
	local cd45 = 1 - (1 - FLAP45_CD_SCALE) * fl45
	flap1_cd = flap1_cd * cd45
	flap2_cd = flap2_cd * cd45

	-- ported from M: Pitch Moment Correction (quadratic, with slat term and
	-- touchdown softening B's formula didn't have)
	-- 2026-10-27: B's validated pitch moments (Tu-154B2-CE, matched to real trim curves). Slats add no Lua moment
	-- in B (the acf slats are back to B: full span, 6 deg).
	local flap1_cm = -2.7331754902e-04*math.pow(math.max(flap_inn,21),2) + 1.1752654608e-02*math.max(flap_inn,21) - 5.9845867059e-01
	local flap2_cm = -5.7882916049e-04*math.pow(math.max(flap_out,19),2) + 2.1995508099e-02*math.max(flap_out,19) - 6.1310759716e-01
	local cm_corr = (0.456458958233361*math.pow(GE_lift,2) - 0.120923847390904*GE_lift - 0.268038425904725) / (GE_lift - 0.932574423700116) -- B
	flap1_cm = flap1_cm*cm_corr
	flap2_cm = flap2_cm*cm_corr

	-- ported from M: Lift Correction (quadratic, with slat term)
	local flap1_cl = (6.00e-04*math.pow(flap_inn,2) - 1.30e-02*flap_inn + 1.08) + slat_cl_add
	local flap2_cl = (7.85e-04*math.pow(flap_out,2) - 1.20e-02*flap_out + 1.18) + slat_cl_add
	-- 2026-10-29 BOOK CALIBRATION (Бехтир 1997, Table 1 / Table 19 / section 6.4): with flaps out the sim made the
	-- book's lift coefficient at ~2-3 deg less angle of attack than the real M (flaps 28: zero-lift angle -5.3 vs
	-- book -3.6; flaps 45: -9.2 vs -6.6). Result: near-flat lift-off (pitch +1 vs book ~+6..7), glideslope
	-- attitude ~2 deg too nose-low, touchdown at pitch -0.6 instead of book AoA 7-8 deg, and too little elevator
	-- needed at rotation and on the glideslope. One factor brings both flap settings onto the book curves.
	flap1_cl = flap1_cl * FLAP_CL_SCALE
	flap2_cl = flap2_cl * FLAP_CL_SCALE

	-- Engine pitch moment -- M donor's exact formula (re-applied 2026-08-20 after revert).
	-- Key fix: lift_tot = lift * q (dynamic pressure), making engine_pitch V^2-proportional.
	-- Without this, engine nose-up moment is near-constant -> balloon at flap 15 at high IAS.
	-- Constants 0.05/2.6/1.45 match M donor exactly. gear_pitch removed (M has no equivalent).
	local spd=interpolate(engine_lift_tbl,tas)
	local lft=interpolate(engine_lift_tbl2,lift) -- lift already includes *q from line above
	local engine_pitch=80000*0.05285*9.81*2.7*(1.5*(r_1+r_3)/100000)*spd*lft -- B
	local gear_pitch=4900*9.81*(0.1*(1-(get(gear1_deploy) or 1))+0.45*(1-(get(gear2_deploy) or 1))+0.45*(1-(get(gear3_deploy) or 1))) -- B: gear retraction nose-up
	if tas>80 then
		set(pitch_add,fm_ok(engine_pitch+gear_pitch,0,-100000,400000))
	end
	set(cl, fm_ok(flap1_cl,1.0,0.5,2.6))
	set(cl2, fm_ok(flap2_cl,1.0,0.5,2.6))
	
	set(cd, fm_ok(flap1_cd,0.06,0.0,0.3))
	set(cd2, fm_ok(flap2_cd,0.06,0.0,0.3))
	
	
	set(cm, fm_ok(flap1_cm,-0.3,-1.0,0.2))
	set(cm2, fm_ok(flap2_cm,-0.3,-1.0,0.2))
	pitch_log(get(flap_inn_L) or 0, get(slat_L) or 0, r_1+r_3) -- calibration logger (thrust of engines 1+3, N)
	

end
