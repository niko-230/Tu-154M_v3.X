size = {500, 400}
app_nme = globalPropertyia("tu154b2/custom/radio/app_names")
app_alt = globalPropertyia("tu154b2/custom/radio/app_alt")
lat = globalPropertyfa("tu154b2/custom/radio/app_lat")
lon = globalPropertyfa("tu154b2/custom/radio/app_lon")
plane_lat = globalPropertyf("sim/flightmodel/position/latitude")
plane_lon = globalPropertyf("sim/flightmodel/position/longitude")
range_capt = globalPropertyi("sim/cockpit2/EFIS/map_range")
range_fo = globalPropertyi("sim/cockpit2/EFIS/map_range_copilot")
magdec = globalPropertyf("sim/flightmodel/position/magnetic_variation")
mag_hdg = globalPropertyf("sim/flightmodel2/position/mag_psi")
true_hdg = globalPropertyf("sim/flightmodel2/position/true_psi")
n_app = globalPropertyi("tu154b2/custom/radio/appr_n_waypoints")
brt_left = globalPropertyf("sim/custom/kontur/kntr_1_brt_sw")
brt_right = globalPropertyf("sim/custom/kontur/kntr_2_brt_sw")
nav_left = globalPropertyi("sim/custom/kontur/left_nav")
nav_right = globalPropertyi("sim/custom/kontur/right_nav")
mode_left = globalPropertyi("sim/cockpit2/EFIS/map_mode")
mode_right = globalPropertyi("sim/cockpit2/EFIS/map_mode_copilot")
taws_left = globalPropertyi("sim/custom/kontur/left_taws")
taws_right = globalPropertyi("sim/custom/kontur/right_taws")
tcas_left = globalPropertyi("sim/custom/kontur/left_tcas")
tcas_aux_left = globalPropertyi("sim/custom/kontur/left_tcas_aux")
tcas_right = globalPropertyi("sim/custom/kontur/right_tcas")
tcas_aux_right = globalPropertyi("sim/custom/kontur/right_tcas_aux")
kont_dist_mode = globalPropertyi("sim/custom/kontur/dist_mode_l")
kont_dist_mode2 = globalPropertyi("sim/custom/kontur/dist_mode_r")
menu_l = globalPropertyi("sim/custom/kontur/left_nav_menu")
menu_r = globalPropertyi("sim/custom/kontur/right_nav_menu")
ap_alt = globalPropertyi("sim/cockpit2/autopilot/altitude_dial_ft")
vvi = globalPropertyf("sim/flightmodel/position/vh_ind")
info_left = globalPropertyi("sim/custom/kontur/left_info_page")
info_right = globalPropertyi("sim/custom/kontur/right_info_page")
-- defineProperty("db1", globalPropertyf("tu154b2/custom/controlls/debug1"))
-- defineProperty("db2", globalPropertyf("tu154b2/custom/controlls/debug2"))
-- defineProperty("db3", globalPropertyf("tu154b2/custom/controlls/debug3"))
-- defineProperty("db4", globalPropertyf("tu154b2/custom/controlls/debug4"))
-- debugstr = globalPropertys("tu154b2/custom/controlls/debugstr")
-- defineProperty("arc_array", globalPropertyfa("tu154b2/custom/rls/arc"))

function getHeading(lat1,lon1,lat2,lon2)
  local b10=math.rad(lat1)
  local b11=math.rad(lon1)
  local b12=math.rad(lat2)
  local b13=math.rad(lon2)
  local hdg=math.atan2(math.sin(b13-b11)*math.cos(b12),math.cos(b10)*math.sin(b12)-math.sin(b10)*math.cos(b12)*math.cos(b13-b11))
  return math.deg(hdg)
end
function getHeadingDifference(desireddirection,current_heading)
	local err = current_heading - desireddirection
	if (err >  180) then err =err- 360 end
	if (err < -180) then err =err+ 360 end
	return err
end

function getDistance(lat1,lon1,lat2,lon2)
  local alat=math.rad(lat1)
  local alon=math.rad(lon1)
  local blat=math.rad(lat2)
  local blon=math.rad(lon2)
  local av=math.sin(alat)*math.sin(blat) + math.cos(alat)*math.cos(blat)*math.cos(blon-alon)
  if av > 1 then av=1 end
  local dist=math.acos(av) * 3440
  --print(lat1.." "..lon1.." "..lat2.." "..lon2)
  --print("Distance = "..retVal) 
  return dist
end
local off1=0
local off2=0
local nd_show_tbl = {}
local nd_name_tbl = {}
local test_tbl = {}
for i = 1, 200, 1 do
	table.insert(nd_show_tbl, {[1] = 0, [2] = 0, [3] = 0}) -- [3] = 1: real position (used by the route line in nd_route_draw.lua)
	table.insert(nd_name_tbl, "")
end
local n_FMS = 0

-- 2026-11-07: UNS hold on the Kontur map. X-Plane puts a hold into the flight plan as the
-- hold fix twice in a row (e.g. BLO, BLO). The racetrack is built here from the values of
-- the UNS HOLDING page (uns_core.lua writes them to tu154b2/custom/uns/hold_*), in the same
-- aircraft-relative, heading-up NM frame as the waypoints, and drawn dashed by nd_route_draw.lua.
-- Without HOLDING page values for that fix: standard hold (inbound = the leg into the fix,
-- right turns, 1 minute).
local hold_show_tbl = {}
for i = 1, 120, 1 do table.insert(hold_show_tbl, {[1] = 0, [2] = 0}) end
local n_hold = 0
local hold_dr = false        -- looked up on the first update (uns_core.lua creates them at load)
local tas_dr = globalPropertyf("sim/flightmodel/position/true_airspeed")   -- m/s
local function holdLookup()
	if hold_dr ~= false then return hold_dr end
	local ok = true
	local t = {}
	for _, k in ipairs({ "set", "lat", "lon", "inbd", "turn", "time", "dist" }) do
		local fn = (k == "set" or k == "turn") and globalPropertyi or globalPropertyf
		local good, p = pcall(fn, "tu154b2/custom/uns/hold_" .. k)
		if good and p then t[k] = p else ok = false end
	end
	hold_dr = ok and t or nil
	return hold_dr
end

function update()
	local wp_lat = get(lat)
	local wp_lon = get(lon)
	--local magvar = get(magdec)
	--local maghead = get(mag_hdg)
	local true_hdg = get(true_hdg)
	local ac_lat=get(plane_lat)
	local ac_lon=get(plane_lon)
	
	n_FMS = sasl.countFMSEntries ()
	n_appr = get(n_app)
	-- 2026-11-03: X-Plane numbers the flight plan entries from 0 (as the UNS does in
	-- uns_core.lua readPlan). This loop used to read entries 1..n: the first point (the
	-- origin) was never drawn and one entry past the end was read. Table slot i now holds
	-- entry i-1. If entry 0 has no position but entry n has one, the numbering is from 1.
	local base = 0
	if n_FMS > 0 then
		local _, _, _, _, la0, lo0 = sasl.getFMSEntryInfo (0)
		if la0 == nil or lo0 == nil or (la0 == 0 and lo0 == 0) then
			local _, _, _, _, lan, lon = sasl.getFMSEntryInfo (n_FMS)
			if lan ~= nil and lon ~= nil and not (lan == 0 and lon == 0) then base = 1 end
		end
	end
	for i = 1, n_FMS, 1 do		
		local tpe , nme , id , altitude , enr_latitude , enr_longitude = sasl.getFMSEntryInfo (i - 1 + base)
		enr_latitude = enr_latitude or 0
		enr_longitude = enr_longitude or 0
		nme = nme or ""
		local abs_heading = getHeading(ac_lat,ac_lon,enr_latitude,enr_longitude)
		local bearing = 0
		--local mag_diff = getHeadingDifference(simDR_true_heading,simDR_mag_heading)
		local bearing=getHeadingDifference(true_hdg,abs_heading)
		local dist = getDistance(ac_lat,ac_lon,enr_latitude,enr_longitude)
		local y = dist * math.cos(math.rad(bearing))
		local x = dist * math.sin(math.rad(bearing))
		nd_show_tbl[i][1] = x
		nd_show_tbl[i][2] = y
		-- route line: entries without a real position (lat/lon 0, e.g. discontinuities) break the line
		if math.abs(enr_latitude) > 0.0001 or math.abs(enr_longitude) > 0.0001 then
			nd_show_tbl[i][3] = 1
		else
			nd_show_tbl[i][3] = 0
		end
		nd_name_tbl[i] = nme
	end
	-- hold: the first place where an entry repeats the one before it (same name and position)
	n_hold = 0
	do
		local hfix = nil
		local prev = nil
		for i = 1, n_FMS, 1 do
			local _, nme, _, _, la, lo = sasl.getFMSEntryInfo(i - 1 + base)
			if la and lo and not (la == 0 and lo == 0) then
				if prev and prev.nme == nme and math.abs(prev.la - la) < 0.0005 and math.abs(prev.lo - lo) < 0.0005 then
					hfix = { la = la, lo = lo, pla = prev.pla, plo = prev.plo }
					break
				end
				prev = { nme = nme, la = la, lo = lo, pla = prev and prev.la, plo = prev and prev.lo }
			else
				prev = nil
			end
		end
		if hfix then
			local magoff = get(mag_hdg) - true_hdg            -- magnetic = true + magoff
			while magoff > 180 do magoff = magoff - 360 end
			while magoff < -180 do magoff = magoff + 360 end
			-- standard hold first
			local inb_true = nil
			if hfix.pla then inb_true = getHeading(hfix.pla, hfix.plo, hfix.la, hfix.lo) end
			local turn, tmin, dist = 1, 1, 0
			local H = holdLookup()
			if H and get(H.set) == 1 and math.abs(get(H.lat) - hfix.la) < 0.001 and math.abs(get(H.lon) - hfix.lo) < 0.001 then
				inb_true = get(H.inbd) - magoff
				turn = (get(H.turn) == -1) and -1 or 1
				tmin = get(H.time)
				dist = get(H.dist)
			end
			if inb_true then
				local tas = math.max(get(tas_dr), 60) * 1.943844          -- kt
				local R = (tas * 0.514444) ^ 2 / (9.81 * math.tan(math.rad(25))) / 1852   -- NM, 25 deg bank
				local L = (dist and dist > 0) and dist or (tas * ((tmin and tmin > 0) and tmin or 1) / 60)   -- NM
				-- fix relative to the aircraft (heading-up NM frame), same maths as the waypoints
				local brg = getHeadingDifference(true_hdg, getHeading(ac_lat, ac_lon, hfix.la, hfix.lo))
				local d = getDistance(ac_lat, ac_lon, hfix.la, hfix.lo)
				local fx, fy = d * math.sin(math.rad(brg)), d * math.cos(math.rad(brg))
				local rel = math.rad(inb_true - true_hdg)
				local ux, uy = math.sin(rel), math.cos(rel)              -- inbound direction
				local sx, sy = uy * turn, -ux * turn                     -- side of the outbound leg
				local pts = {}
				local function add(x, y) pts[#pts + 1] = { x, y } end
				local ax, ay = fx - L * ux, fy - L * uy                  -- start of the inbound leg
				add(ax, ay); add(fx, fy)
				local function arc(cx, cy, px0, py0)
					local a0 = math.atan2(py0 - cy, px0 - cx)
					for k = 1, 24 do
						local a = a0 - turn * math.pi * k / 24          -- right turn = clockwise
						add(cx + R * math.cos(a), cy + R * math.sin(a))
					end
				end
				arc(fx + R * sx, fy + R * sy, fx, fy)                    -- turn at the fix
				local bx, by = pts[#pts][1], pts[#pts][2]
				add(bx - L * ux, by - L * uy)                            -- outbound leg
				arc(ax + R * sx, ay + R * sy, bx - L * ux, by - L * uy)  -- turn back to the inbound leg
				for k = 1, math.min(#pts, #hold_show_tbl) do
					hold_show_tbl[k][1] = pts[k][1]
					hold_show_tbl[k][2] = pts[k][2]
				end
				n_hold = math.min(#pts, #hold_show_tbl)
			end
		end
	end

	local nav_ind = get(app_nme)
	local nav_alt = get(app_alt)
	for i = 1, n_appr, 1 do	
		app_latitude = wp_lat[i]  
		app_longitude = wp_lon[i] 
		local abs_heading = getHeading(ac_lat,ac_lon,app_latitude,app_longitude)
		local bearing_app = 0
		--local mag_diff = getHeadingDifference(simDR_true_heading,simDR_mag_heading)
		local bearing_app=getHeadingDifference(true_hdg,abs_heading)
		local dist_app = getDistance(ac_lat,ac_lon,app_latitude,app_longitude)
		local y_app = dist_app * math.cos(math.rad(bearing_app))
		local x_app = dist_app * math.sin(math.rad(bearing_app))
		nd_show_tbl[n_FMS+i][1] = x_app
		nd_show_tbl[n_FMS+i][2] = y_app
		nd_show_tbl[n_FMS+i][3] = 1
		if nav_ind[i] == nav_ind[i-1] then
			nd_name_tbl[n_FMS+i] = ''
		elseif nav_ind[i] ~=-1 then
			local tpe , latitude , longitude , height , frequency , heading , id , app_name , loaded = sasl.getNavAidInfo ( nav_ind[i] )
			nd_name_tbl[n_FMS+i] = app_name
		elseif nav_alt[i] ~= 0 then
			local app_name = string.format("%s",nav_alt[i])
			app_name = '('..app_name..')'
			nd_name_tbl[n_FMS+i] = app_name
		else
			nd_name_tbl[n_FMS+i] = '(INTC)'
		end	
	end
	-- dirty trick to remove AP altitude intercept line from nd_name_tbl
	if get(vvi)>0 then
		set(ap_alt,0)
	else
		set(ap_alt,99999)
	end
end

components = {
	
	nd_route_draw {
		position = {0, 0, 500, 400},
		table_draw = nd_show_tbl,
		name_draw = nd_name_tbl,
		hold_draw = hold_show_tbl,
		n_hold = function()
			return n_hold
		end,
		n_wp = function()
			return n_FMS+n_appr
		end,
		range = function()
			return get(range_capt)
		end,
		brightness  = function()
			return get(brt_left) * (1 - get(info_left))
		end,
		navon  = function()
			return bool2int(get(nav_left)>0 and get(taws_left)~=2)
		end,
		mode  = function()
			return get(mode_left)
		end,
		dist_mode  = function()
			return get(kont_dist_mode)
		end,
		menu  = function()
			return get(menu_l)
		end,
	},
	
	nd_route_draw {
		position = {500, 0, 500, 400},
		table_draw = nd_show_tbl,
		name_draw = nd_name_tbl,
		hold_draw = hold_show_tbl,
		n_hold = function()
			return n_hold
		end,
		n_wp = function()
			return n_FMS+n_appr
		end,
		range = function()
			return get(range_fo)
		end,
		brightness  = function()
			return get(brt_right) * (1 - get(info_right))
		end,
		navon  = function()
			return bool2int(get(nav_right)>0 and get(taws_right)~=2)
		end,
		mode  = function()
			return get(mode_right)
		end,
		dist_mode  = function()
			return get(kont_dist_mode2)
		end,
		menu  = function()
			return get(menu_r)
		end,
	},
	tcas_nd_draw {
		position = {0, 0, 500, 400},
		range = function()
			return get(range_capt)
		end,
		brightness  = function()
			return get(brt_left) * (1 - get(info_left))
		end,
		navon  = function()
			return bool2int(get(tcas_left)+get(tcas_aux_left)>0)
		end,
		mode  = function()
			return get(mode_left)
		end,
		dist_mode  = function()
			return get(kont_dist_mode)
		end,
	},
	
		tcas_nd_draw {
		position = {500, 0, 500, 400},
		range = function()
			return get(range_fo)
		end,
		brightness  = function()
			return get(brt_right) * (1 - get(info_right))
		end,
		navon  = function()
			return bool2int(get(tcas_right)+get(tcas_aux_right)>0)
		end,
		mode  = function()
			return get(mode_right)
		end,
		dist_mode  = function()
			return get(kont_dist_mode2)
		end,
	},
	-- rdr_test {
		-- position = {0, 0, 500, 400},
		-- -- range = function()
			-- -- return get(range_capt)
		-- -- end,
		-- -- brightness  = function()
			-- -- return get(brt_left) * (1 - get(info_left))
		-- -- end,
		-- dist_mode  = function()
			-- return get(kont_dist_mode)
		-- end,
	-- },

}