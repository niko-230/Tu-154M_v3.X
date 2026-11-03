-------------------------------------------------------------------------------
-- UNS-1 face for X-Plane's own FMS (cockpit v1)
--
-- X-Plane stays the brain: the route, waypoint sequencing and the GPS output
-- that the ABSU follows are all X-Plane's own FMS. This module only:
--   * draws UNS-style pages (FPL, DTO, NAV, waypoint confirm) from X-Plane's
--     flight plan, and edits that same flight plan through the SDK
--   * shows X-Plane's own CDU pages in UNS colours for everything else
--     (DATA, VNAV, LIST, HOLD, PERF, TUNE, MENU = DEP/ARR), "mirror" mode
--   * handles the UNS keys (captain's 3D keypad + 2D popup = unit 1,
--     right 3D keypad = unit 2; each unit has its own pages)
--
-- Loaded once with request("uns_core") and shared by the 3D screen and the
-- 2D popup, so the 2D popup always shows the captain's UNS (unit 1).
--
-- New-screen switch: dataref tu154b2/custom/uns/face (1 = UNS screen,
-- 0 = original X-Plane CDU screen and Boeing popup, keys behave as before).
-------------------------------------------------------------------------------

local core = {}

-------------------------------------------------------------------------------
-- settings
-------------------------------------------------------------------------------
local REFRESH = 0.25        -- s between screen rebuilds (4 per second)
local KEY_REFRESH = 0.08    -- s after a key press until the screen is rebuilt
local MSG_TIME = 4.0        -- s a message stays on the bottom line
local FPL_ROWS = 6          -- flight plan lines per page (one per line-select key)
local DTO_ROWS = 5          -- direct-to list lines per page (first line is DIRECT)
local MAX_ENTRY = 12        -- longest typed entry

-------------------------------------------------------------------------------
-- datarefs
-------------------------------------------------------------------------------
local function prop(fn, name)
	local ok, p = pcall(fn, name)
	if ok then return p end
	return nil
end
local function val(p, default)
	if p == nil then return default end
	local ok, v = pcall(get, p)
	if ok and v ~= nil then return v end
	return default
end

local dr_lat    = prop(globalPropertyd, "sim/flightmodel/position/latitude")
local dr_lon    = prop(globalPropertyd, "sim/flightmodel/position/longitude")
local dr_psi    = prop(globalPropertyf, "sim/flightmodel/position/psi")
local dr_mpsi   = prop(globalPropertyf, "sim/flightmodel/position/mag_psi")
local dr_hpath  = prop(globalPropertyf, "sim/flightmodel/position/hpath")
local dr_gs     = prop(globalPropertyf, "sim/flightmodel/position/groundspeed")
local dr_wdir   = prop(globalPropertyf, "sim/cockpit2/gauges/indicators/wind_heading_deg_mag")
local dr_wspd   = prop(globalPropertyf, "sim/cockpit2/gauges/indicators/wind_speed_kts")
local dr_time   = prop(globalPropertyf, "sim/time/total_running_time_sec")
local dr_zulu   = prop(globalPropertyf, "sim/time/zulu_time_sec")
local dr_ltime  = prop(globalPropertyf, "sim/time/local_time_sec")
local dr_lday   = prop(globalPropertyi, "sim/time/local_date_days")
local dr_power  = prop(globalPropertyi, "tu154b2/custom/uns1_on")
local dr_face   = prop(globalPropertyi, "tu154b2/custom/uns/face")     -- created in main.lua
local dr_kontur = prop(globalPropertyi, "tu154b2/custom/b2/kontur_on")
-- Each UNS unit works through its own X-Plane CDU: unit 1 (captain) = CDU 1
-- (sim/FMS/... commands), unit 2 (right) = CDU 2 (sim/FMS2/... commands). Both CDUs
-- edit the same X-Plane flight plan, but each shows its own page.
-- X-Plane EXEC light of each CDU
local EXEC = {
	prop(globalPropertyi, "sim/cockpit2/radios/indicators/fms_exec_light_pilot"),
	prop(globalPropertyi, "sim/cockpit2/radios/indicators/fms_exec_light_copilot"),
}
if EXEC[2] == nil then EXEC[2] = EXEC[1] end
local dr_exec = EXEC[1]

-- X-Plane's CDU screen text of each CDU, used for the mirrored pages
local CDU_TEXT, CDU_STYLE = { {}, {} }, { {}, {} }
for n = 1, 2 do
	for i = 0, 15 do
		CDU_TEXT[n][i]  = prop(globalPropertys, "sim/cockpit2/radios/indicators/fms_cdu" .. n .. "_text_line" .. i)
		CDU_STYLE[n][i] = prop(globalPropertys, "sim/cockpit2/radios/indicators/fms_cdu" .. n .. "_style_line" .. i)
	end
end
local cdu_text, cdu_style = CDU_TEXT[1], CDU_STYLE[1]

-- for the UNS pages of their own (PATH VNAV, PERF, TUNE, DATA), in one table
local DX = {}
do
	local function propE(name, i)      -- one element of an array dataref (SASL counts from 1)
		if globalPropertyfae == nil then return nil end
		local ok, p = pcall(globalPropertyfae, name, i)
		if ok then return p end
		return nil
	end
	DX.elev = prop(globalPropertyd, "sim/flightmodel/position/elevation")          -- m
	DX.tas  = prop(globalPropertyf, "sim/flightmodel/position/true_airspeed")      -- m/s
	DX.oat  = prop(globalPropertyf, "sim/cockpit2/temperature/outside_air_temp_degc")
	DX.wt   = prop(globalPropertyf, "sim/flightmodel/weight/m_total")              -- kg
	DX.fuel = prop(globalPropertyf, "sim/flightmodel/weight/m_fuel_total")         -- kg
	DX.ff = {}                                                                       -- kg/s per engine
	for i = 1, 3 do DX.ff[i] = propE("sim/cockpit2/engine/indicators/fuel_flow_kg_sec", i) end
	DX.com1 = prop(globalPropertyi, "sim/cockpit2/radios/actuators/com1_frequency_hz_833")
	DX.com2 = prop(globalPropertyi, "sim/cockpit2/radios/actuators/com2_frequency_hz_833")
	DX.nav1 = prop(globalPropertyi, "sim/cockpit2/radios/actuators/nav1_frequency_hz")
	DX.nav2 = prop(globalPropertyi, "sim/cockpit2/radios/actuators/nav2_frequency_hz")
	DX.adf1 = prop(globalPropertyi, "sim/cockpit2/radios/actuators/adf1_frequency_hz")
	DX.adf2 = prop(globalPropertyi, "sim/cockpit2/radios/actuators/adf2_frequency_hz")
	DX.xpdr = prop(globalPropertyi, "sim/cockpit2/radios/actuators/transponder_code")
end

local NAV_LL = NAV_LATLON or 2048
local NOT_FOUND = NAV_NOT_FOUND or -1

-------------------------------------------------------------------------------
-- colours (UNS screen colours, as in the UNS-1 manual)
-------------------------------------------------------------------------------
local C = {
	green   = { 0.20, 0.95, 0.30, 1 },
	white   = { 0.93, 0.93, 0.93, 1 },
	magenta = { 1.00, 0.35, 0.85, 1 },
	cyan    = { 0.30, 0.80, 1.00, 1 },
	amber   = { 1.00, 0.62, 0.10, 1 },
	yellow  = { 1.00, 0.95, 0.25, 1 },
	red     = { 1.00, 0.25, 0.20, 1 },
	black   = { 0.00, 0.00, 0.00, 1 },
	box     = { 0.84, 0.88, 0.90, 1 },   -- cursor box (black text on light box)
	bg      = { 0.106, 0.102, 0.094, 1 }, -- screen background (very dark warm grey)
}
core.C = C
-- X-Plane CDU style colour codes 0..7
local XP_COLOR = { [0] = C.black, C.cyan, C.red, C.yellow, C.green, C.magenta, C.amber, C.white }

-------------------------------------------------------------------------------
-- screen grid: 24 columns; rows are placed relative to the line-select keys
--   T  = title line, Lk = line of select key k (1..6),
--   Uk = small line just above Lk, Dk = small line just below Lk, B = bottom
-------------------------------------------------------------------------------
local ROWF = { T = 0.072, B = 0.915 }   -- B: bottom line (typing box), kept clear of the bezel
for k = 1, 6 do
	local f = 0.205 + (k - 1) * 0.128
	ROWF["L" .. k] = f
	ROWF["U" .. k] = f - 0.062
	ROWF["D" .. k] = f + 0.062
end
for i = 1, 6 do ROWF["S" .. i] = 0.41 + (i - 1) * 0.095 end   -- power-up self-test list
for i = 1, 8 do ROWF["P" .. i] = 0.165 + (i - 1) * 0.0857 end  -- POS INIT page lines
core.ROWF = ROWF

-------------------------------------------------------------------------------
-- small helpers
-------------------------------------------------------------------------------
-- real-time clock (keeps running while the sim is paused, so keys still show)
local clock = nil
do
	local ok, id = pcall(sasl.createPerformanceTimer)
	if ok and id then
		clock = id
		pcall(sasl.startTimer, clock)
	end
end
local function now()
	if clock then
		local ok, s = pcall(sasl.getElapsedSeconds, clock)
		if ok and type(s) == "number" then return s end
	end
	return val(dr_time, 0)
end

local function ulen(s)
	local _, n = string.gsub(s, "[^\128-\191]", "")
	return n
end
local function uchars(s)
	local t = {}
	for ch in string.gmatch(s, "[%z\1-\127\194-\244][\128-\191]*") do t[#t + 1] = ch end
	return t
end
local function usub(s, n) -- first n characters
	local t = uchars(s)
	if #t <= n then return s end
	return table.concat(t, "", 1, n)
end

local function wrap360(a)
	a = a % 360
	if a < 0 then a = a + 360 end
	return a
end
local function wrap180(a)
	a = wrap360(a)
	if a > 180 then a = a - 360 end
	return a
end

local R_NM = 3440.065
local atan2 = math.atan2 or math.atan
local function gc(la1, lo1, la2, lo2) -- distance (nm), initial true course (deg)
	local p1, p2 = math.rad(la1), math.rad(la2)
	local dl = math.rad(lo2 - lo1)
	local a = math.sin((p2 - p1) / 2) ^ 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ^ 2
	local d = 2 * R_NM * math.asin(math.min(1, math.sqrt(a)))
	local c = math.deg(atan2(math.sin(dl) * math.cos(p2),
		math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)))
	return d, wrap360(c)
end

-- magnetic = true + offset (taken from X-Plane's own heading pair, so the sign is always right)
local function magOff() return wrap180(val(dr_mpsi, 0) - val(dr_psi, 0)) end

local function fmtDeg(a) return string.format("%03d°", math.floor(wrap360(a) + 0.5) % 360) end
local function fmtDist(d)
	if d >= 100 then return string.format("%d", math.floor(d + 0.5)) end
	return string.format("%.1f", d)
end
local function fmtAlt(a)
	if not a or a <= 0 then return "------" end
	if a >= 10000 then return string.format("FL%03d", math.floor(a / 100 + 0.5)) end
	return string.format("%d", math.floor(a + 0.5))
end
local function fmtLat(la)
	local h = la >= 0 and "N" or "S"
	la = math.abs(la)
	local d = math.floor(la)
	return string.format("%s %3d %04.1f", h, d, (la - d) * 60)
end
local function fmtLon(lo)
	local h = lo >= 0 and "E" or "W"
	lo = math.abs(lo)
	local d = math.floor(lo)
	return string.format("%s%4d %04.1f", h, d, (lo - d) * 60)
end

-------------------------------------------------------------------------------
-- state
-------------------------------------------------------------------------------
-- Page state of each unit (the two units show and change pages independently).
-- What belongs to the flight itself is shared by both units: ORIGIN, DEST, the last
-- direct-to point and the database note.
local SHARED = { origin = true, dest = true, dto = true, navOld = true, userHold = true }
local SH = {}
local SHARED_MT = {
	__index = function(_, k) if SHARED[k] then return SH[k] end end,
	__newindex = function(t, k, v) if SHARED[k] then SH[k] = v else rawset(t, k, v) end end,
}
local function newState()
	return setmetatable({
		page = "FPL",        -- FPL, DTO, NAV, WPT, MIRROR, FMENU
		back = "FPL",        -- page to return to
		entry = "",          -- typed characters
		fplPage = 1,
		fplSel = "new",      -- "new" or a flight plan position
		delArmed = false,
		dtoPage = 1,
		wpt = nil,           -- waypoint confirm data
		msg = nil, msgUntil = 0,
		-- dto (last direct-to point {lat, lon}): shared, see SHARED
	}, SHARED_MT)
end
local SS = { newState(), newState() }
-- S = page state of the unit being worked on now (set by setUnit)
local S = SS[1]
core.S = SS[1]
core.SS = SS
core.SH = SH

-- the two UNS units: 1 = captain (left, also the 2D panel), 2 = right.
-- They share the flight plan; each has its own pages (through its own X-Plane CDU),
-- power (ON/OFF DIM key), self test, POS INIT, DIM page and brightness.
--   on       unit switched on with its ON/OFF DIM key. Both units start OFF (also with
--            the engines running); a unit comes on only when the UNS power is on AND
--            its ON/OFF DIM key is pressed. Losing UNS power switches it off again.
--   boot     time its self test started (nil = not running)
--   posinit  POS INIT waiting for ACCEPT on this unit
--   dim      DIM page open on this unit
local U = {
	{ on = false, was = false, boot = nil, posinit = false, dim = false, model = nil },
	{ on = false, was = false, boot = nil, posinit = false, dim = false, model = nil },
}
core.U = U
-- screen brightness of each unit, set on its DIM page (starts at 20 %).
-- (The UNS brightness knob dims the UNS night texture instead - see uns_logic.lua.)
U[1].brt = 0.2     -- 3D screens load at 20 % (the 2D panel is always at full brightness)
U[2].brt = 0.2
local function unitBrt(u)
	return math.max(0, math.min(1, U[u].brt or 1))
end
core.unitBrt = unitBrt

-- the unit being worked on now: its page state, its X-Plane CDU (text, EXEC light,
-- commands). Every key press, screen build and background job sets it first.
-- CDU 2 needs X-Plane's copilot CDU instrument in the panel (tu154.acf). If X-Plane
-- shows nothing at all on CDU 2, unit 2 falls back to CDU 1 so its pages still work.
local CUR = 1
local CURCDU = 1
local cdu2Live = false
local function setUnit(u)
	u = (u == 2) and 2 or 1
	CUR = u
	CURCDU = (u == 2 and cdu2Live) and 2 or 1
	S = SS[u]
	cdu_text, cdu_style = CDU_TEXT[CURCDU], CDU_STYLE[CURCDU]
	dr_exec = EXEC[CURCDU]
end
local function checkCdu2()
	local live = false
	for i = 0, 15 do
		local t = val(CDU_TEXT[2][i], "")
		if type(t) == "string" and string.find(t, "[^%s%z%[%]]") then live = true break end
	end
	cdu2Live = live
end
core.setUnit = setUnit
core.cdu2Live = function() return cdu2Live end

core.model = {}          -- what is on the screen now (list of text items)
core.onRedraw = nil      -- set by uns_display.lua (asks the 3D screen to redraw)
core.onPopup = nil       -- set by uns_display.lua (opens/closes the 2D popup)

local nextBuild = 0
local function dirtySoon(dt) nextBuild = math.min(nextBuild, now() + (dt or KEY_REFRESH)) end

local function msg(text)
	S.msg = text
	S.msgUntil = now() + MSG_TIME
end

-------------------------------------------------------------------------------
-- X-Plane flight plan access (0-based indices in the SDK; checked at run time)
-------------------------------------------------------------------------------
local base = 0
local function rawInfo(i)
	local ok, t, id, ref, alt, la, lo = pcall(sasl.getFMSEntryInfo, i)
	if not ok then return nil end
	return t, id, ref, alt, la, lo
end
local function valid(la, lo) return la ~= nil and lo ~= nil and not (la == 0 and lo == 0) end

local function readPlan()
	local plan = {}
	local ok, n = pcall(sasl.countFMSEntries)
	if not ok or type(n) ~= "number" then n = 0 end
	if n > 0 then
		local _, _, _, _, la0, lo0 = rawInfo(0)
		if valid(la0, lo0) then
			base = 0
		else
			local _, _, _, _, lan, lon = rawInfo(n)
			if valid(lan, lon) then base = 1 end
		end
	end
	for i = 1, n do
		local t, id, ref, alt, la, lo = rawInfo(i - 1 + base)
		plan[i] = { type = t, id = id or "", ref = ref, alt = alt or 0, lat = la or 0, lon = lo or 0 }
	end
	local okd, d = pcall(sasl.getDestinationFMSEntry)
	local dest = 0
	if okd and type(d) == "number" and n > 0 then
		dest = d - base + 1
		if dest < 1 then dest = 1 end
		if dest > n then dest = n end
	end
	return plan, dest
end
core.readPlan = readPlan

local function fi(k) return k - 1 + base end

local function writeEntry(k, e)
	if e.type ~= NAV_LL and type(e.ref) == "number" and e.ref ~= NOT_FOUND and e.ref >= 0 then
		pcall(sasl.setFMSEntryInfo, fi(k), e.ref, e.alt or 0)
	else
		pcall(sasl.setFMSEntryLatLon, fi(k), e.lat, e.lon, e.alt or 0)
	end
end

local function setDest(k)
	if k and k >= 1 then pcall(sasl.setDestinationFMSEntry, fi(k)) end
end

-- insert e before position pos (pos = n+1 appends)
local function insertAt(pos, e)
	local plan, dest = readPlan()
	local n = #plan
	if n >= 100 then msg("FPL FULL") return false end
	if pos < 1 then pos = 1 end
	if pos > n + 1 then pos = n + 1 end
	for k = n, pos, -1 do writeEntry(k + 1, plan[k]) end
	writeEntry(pos, e)
	local nd = dest
	if n == 0 then
		nd = 1
	elseif pos < dest then
		nd = dest + 1
	end
	if nd == 1 and n + 1 >= 2 then nd = 2 end  -- the departure point is never the active waypoint
	setDest(nd)
	return true
end

local function deleteAt(pos)
	local plan, dest = readPlan()
	local n = #plan
	if pos < 1 or pos > n then return end
	for k = pos, n - 1 do writeEntry(k, plan[k + 1]) end
	pcall(sasl.clearFMSEntry, fi(n))
	if n - 1 >= 1 then
		local nd = dest
		if pos < dest then nd = dest - 1 end
		if nd > n - 1 then nd = n - 1 end
		if nd == 1 and n - 1 >= 2 then nd = 2 end
		setDest(nd)
	end
end

local function setAltitude(pos, alt)
	local plan = readPlan()
	local e = plan[pos]
	if not e then return end
	e.alt = alt
	writeEntry(pos, e)
end

-- direct-to is done on X-Plane's own DIRECT TO page (defined further down, after the
-- X-Plane key engine), so X-Plane handles it itself and no extra points are added
local directTo     -- directTo(pos): fly direct to flight plan position pos
local directIdent  -- directIdent(ident): fly direct to any waypoint by name
-- flight plan edits are typed into X-Plane's own LEGS page (defined further down):
local legsInsert   -- legsInsert(ident, beforeIdent, choice): add ident before beforeIdent (nil = at the end)
local legsDelete   -- legsDelete(ident): remove that waypoint
local legsAltitude -- legsAltitude(ident, text): altitude constraint, as typed (e.g. 350 = FL350)
local legsDeleteRow, dirPickRow, directByDirPage, holdAtFix  -- UNS FPL/DTO/HOLD actions (defined further down)

local function isDtoPoint(e)
	return S.dto and e.type == NAV_LL
		and math.abs(e.lat - S.dto.lat) < 1e-4 and math.abs(e.lon - S.dto.lon) < 1e-4
end

local function entryName(e)
	if isDtoPoint(e) then return "*DIR*" end
	if e.type == NAV_LL or e.id == "" then
		local la, lo = e.lat, e.lon
		return string.format("%s%02d%s%03d", la >= 0 and "N" or "S", math.floor(math.abs(la) + 0.5),
			lo >= 0 and "E" or "W", math.floor(math.abs(lo) + 0.5))
	end
	return e.id
end

-------------------------------------------------------------------------------
-- nav database lookup
-------------------------------------------------------------------------------
local TYPES = {
	{ NAV_AIRPORT, "ARPT" }, { NAV_VOR, "VOR" }, { NAV_NDB, "NDB" }, { NAV_FIX, "INT" },
}

-- oceanic 5-character positions (ARINC 424), as in the UNS manual:
-- 5275N = N52 W075, 75N70 = N75 W170, 5020E = N50 E020, 50E20 = N50 E120,
-- 5275W = S52 W075, 52W20 = S52 W120, 6030S = S60 E030, 60S30 = S60 E130
local function parseOceanic(s)
	if #s ~= 5 then return nil end
	local la, ch, lo
	local a, b, c = string.match(s, "^(%d%d)(%d%d)([NEWS])$")
	if a then la, lo, ch = tonumber(a), tonumber(b), c
	else
		a, c, b = string.match(s, "^(%d%d)([NEWS])(%d%d)$")
		if not a then return nil end
		la, lo, ch = tonumber(a), 100 + tonumber(b), c
	end
	if ch == "N" then return la, -lo end
	if ch == "E" then return la, lo end
	if ch == "W" then return -la, -lo end
	return -la, lo
end

local function lookup(ident, rlat, rlon)
	local out = {}
	local ola, olo = parseOceanic(ident)
	if ola then
		out[1] = { type = NAV_LL, kind = "LL", id = ident, name = "LAT/LON", lat = ola, lon = olo, dist = 0 }
		return out
	end
	for _, tp in ipairs(TYPES) do
		if tp[1] ~= nil then
			local ok, ref = pcall(sasl.findNavAid, nil, ident, rlat, rlon, nil, tp[1])
			if ok and type(ref) == "number" and ref ~= NOT_FOUND and ref >= 0 then
				local ok2, t, la, lo, h, f, hd, id, name = pcall(sasl.getNavAidInfo, ref)
				if ok2 and id == ident then
					out[#out + 1] = { ref = ref, type = t, kind = tp[2], id = id, name = name or "",
						lat = la, lon = lo, freq = f, dist = gc(rlat, rlon, la, lo) }
				end
			end
		end
	end
	table.sort(out, function(x, y) return x.dist < y.dist end)
	return out
end

-- reference point for a lookup: the waypoint before the insert position, else the aircraft
local function refPoint(pos)
	local plan = readPlan()
	local e = plan[pos - 1] or plan[pos]
	if e and valid(e.lat, e.lon) then return e.lat, e.lon end
	return val(dr_lat, 0), val(dr_lon, 0)
end

local function startLookup(ident, action, pos)
	local rla, rlo = refPoint(pos)
	local c = lookup(ident, rla, rlo)
	if #c == 0 then
		msg("NOT IN DATABASE")
		return false
	end
	S.wpt = { cands = c, idx = 1, action = action, pos = pos, back = S.page }
	S.page = "WPT"
	return true
end

local function acceptWpt()
	local w = S.wpt
	if not w then return end
	local c = w.cands[w.idx]
	local e = { type = c.type, ref = c.ref, alt = 0, lat = c.lat, lon = c.lon }
	if w.action == "dto" then
		directIdent(c.id)
		S.page = "NAV"
	else
		local plan = readPlan()
		local n = #plan
		local before = plan[w.pos] and plan[w.pos].id or nil
		-- the empty last line: the destination airport stays last, so add before it
		if not before and n >= 2 and plan[n].type == NAV_AIRPORT then before = plan[n].id end
		legsInsert(c.id, before, w.idx)
		S.fplSel = "new"
		S.fplPage = math.floor((w.pos - 1) / FPL_ROWS) + 1
		S.page = "FPL"
	end
	S.entry = ""
	S.wpt = nil
end

-------------------------------------------------------------------------------
-- model building
-------------------------------------------------------------------------------
local M
local function put(row, col, text, color, big, inv)
	M[#M + 1] = { row = row, col = col, text = text, color = color or C.green, big = (big ~= false), inv = inv }
end
local function putR(row, rcol, text, color, big, inv) -- right aligned, ends in column rcol
	put(row, rcol - ulen(text) + 1, text, color, big, inv)
end
-- the outlined ("framed") character used on the UNS pages, e.g. the H over the
-- PATH VNAV altitude column
local function putFrame(row, col, text, color)
	M[#M + 1] = { row = row, col = col, text = text, color = color or C.green, big = false, frame = true }
end
-- a straight line on the screen: columns (0..24) and screen rows (names or fractions)
local function putLine(c1, r1, c2, r2, color)
	M[#M + 1] = { shape = "line", c1 = c1, r1 = r1, c2 = c2, r2 = r2, color = color or C.amber }
end
local function title(name, p, t, menu)
	put("T", 6, name, C.green)
	if p then put("T", 13, p .. "/" .. t, C.green) end
	if menu then put("T", 20, "M", C.green, false, true) end
end
local function entryBox(row, col, width, text)
	local s = text or ""
	if ulen(s) < width then s = s .. string.rep(" ", width - ulen(s)) end
	put(row, col, s, C.box, true, true)
end

-------------------------------------------------------------------------------
-- pages
-------------------------------------------------------------------------------
local P = {}

-- FLIGHT PLAN ---------------------------------------------------------------
P.FPL = {}
function P.FPL.build()
	local plan, dest = readPlan()
	local n = #plan
	local items = n + ((n < 100) and 1 or 0)
	local pages = math.max(1, math.ceil(items / FPL_ROWS))
	if S.fplPage > pages then S.fplPage = pages end
	if S.fplPage < 1 then S.fplPage = 1 end
	local sel = S.fplSel
	local selWpt = (type(sel) == "number") and sel <= n
	title("FPL", S.fplPage, pages, true)
	if not selWpt then putR("U1", 23, "ALT/FL", C.white, false) end
	local first = (S.fplPage - 1) * FPL_ROWS + 1
	for r = 1, FPL_ROWS do
		local i = first + r - 1
		local row = "L" .. r
		if i <= n then
			local e = plan[i]
			local active = (i == dest)
			local col = active and C.magenta or C.green
			putR(row, 1, tostring(i), C.white)
			put(row, 2, ">", C.white)
			if sel == i then
				entryBox(row, 3, 6, S.entry ~= "" and S.entry or entryName(e))
			else
				put(row, 3, entryName(e), col)
			end
			if i < n then
				local d, c = gc(e.lat, e.lon, plan[i + 1].lat, plan[i + 1].lon)
				local legCol = (i + 1 == dest) and C.magenta or C.green
				put("D" .. r, 2, fmtDeg(c + magOff()), legCol, false)
				putR("D" .. r, 16, fmtDist(d) .. " NM", legCol, false)
			end
			if not selWpt then putR(row, 23, fmtAlt(e.alt), active and C.magenta or C.green) end
		elseif i == n + 1 and n < 100 then
			putR(row, 1, tostring(i), C.white)
			if sel == "new" then entryBox(row, 3, 6, S.entry) end
		end
	end
	if selWpt then
		putR("L1", 23, S.delArmed and "CONFIRM→" or "DEL→", S.delArmed and C.amber or C.white)
		putR("L2", 23, "DTO→", C.white)
		putR("L6", 23, "RTN→", C.white)
	end
end

local function fplRowItem(k)
	local plan = readPlan()
	local n = #plan
	local i = (S.fplPage - 1) * FPL_ROWS + k
	if i <= n then return i, n end
	if i == n + 1 and n < 100 then return "new", n end
	return nil, n
end

local function fplCommit()
	if S.entry == "" then return end
	local plan = readPlan()
	local pos = (type(S.fplSel) == "number") and S.fplSel or (#plan + 1)
	startLookup(S.entry, "insert", pos)
end

function P.FPL.key(k)
	local plan = readPlan()
	local n = #plan
	local selWpt = (type(S.fplSel) == "number") and S.fplSel <= n
	local lsk = string.match(k, "^L(%d)$")
	local rsk = string.match(k, "^R(%d)$")
	if lsk then
		local item = fplRowItem(tonumber(lsk))
		if item == nil then return end
		S.delArmed = false
		if S.entry ~= "" then
			S.fplSel = item
			fplCommit()
		elseif S.fplSel == item and item ~= "new" then
			S.fplSel = "new"
		else
			S.fplSel = item
		end
	elseif rsk then
		local r = tonumber(rsk)
		if selWpt then
			if r == 1 then
				if S.delArmed then
					legsDelete(plan[S.fplSel].id)
					S.delArmed = false
					S.fplSel = "new"
				else
					S.delArmed = true
				end
			elseif r == 2 then
				directTo(S.fplSel)
				S.fplSel = "new"
			elseif r == 6 then
				S.fplSel = "new"
				S.delArmed = false
			end
		elseif S.entry ~= "" and string.match(S.entry, "^%d+$") then
			-- typed number + right key = altitude for that line (up to 3 digits = flight level)
			local item = fplRowItem(r)
			if type(item) == "number" then
				legsAltitude(plan[item].id, S.entry)
				S.entry = ""
			end
		end
	elseif k == "ENTER" then
		if S.entry ~= "" then fplCommit() end
	elseif k == "DEL" then
		if S.entry ~= "" then
			S.entry = ""
		elseif selWpt then
			if S.delArmed then
				legsDelete(plan[S.fplSel].id)
				S.delArmed = false
				S.fplSel = "new"
			else
				S.delArmed = true
			end
		end
	elseif k == "BACK" then
		if S.entry ~= "" then
			S.entry = string.sub(S.entry, 1, -2)
		else
			S.fplSel = "new"
			S.delArmed = false
		end
	elseif k == "NEXT" then
		S.fplPage = S.fplPage + 1
		local pages = math.max(1, math.ceil((n + 1) / FPL_ROWS))
		if S.fplPage > pages then S.fplPage = 1 end
	elseif k == "PREV" then
		S.fplPage = S.fplPage - 1
		if S.fplPage < 1 then S.fplPage = math.max(1, math.ceil((n + 1) / FPL_ROWS)) end
	end
end

-- DIRECT TO -----------------------------------------------------------------
P.DTO = {}
function P.DTO.build()
	local plan, dest = readPlan()
	local n = #plan
	local pages = math.max(1, math.ceil(n / DTO_ROWS))
	if S.dtoPage > pages then S.dtoPage = pages end
	if S.dtoPage < 1 then S.dtoPage = 1 end
	title("DTO", S.dtoPage, pages, false)
	put("L1", 1, "DIRECT", C.green)
	entryBox("L1", 8, 6, S.entry)
	if S.busy then put("L1", 16, "WAIT", C.amber) end
	local first = (S.dtoPage - 1) * DTO_ROWS + 1
	for r = 1, DTO_ROWS do
		local i = first + r - 1
		if i <= n then
			local row = "L" .. (r + 1)
			putR(row, 1, tostring(i), C.white)
			put(row, 2, ">", C.white)
			put(row, 3, entryName(plan[i]), (i == dest) and C.magenta or C.green)
		end
	end
	putR("L6", 23, "RTN→", C.white)
end

local function dtoCommit()
	local e = S.entry
	if e == "" then return end
	local plan, dest = readPlan()
	local num = tonumber(e)
	if num and string.match(e, "^%d+$") then
		if num >= 1 and num <= #plan then
			directTo(num)
			S.entry = ""
			S.page = "NAV"
		else
			msg("INVALID ENTRY")
		end
		return
	end
	-- ident: first match from the active waypoint on, else anywhere in the plan
	local found
	for i = math.max(dest, 1), #plan do if plan[i].id == e then found = i break end end
	if not found then for i = 1, #plan do if plan[i].id == e then found = i break end end end
	if found then
		directTo(found)
		S.entry = ""
		S.page = "NAV"
		return
	end
	-- not in the flight plan: X-Plane looks it up and adds it
	directIdent(e)
	S.entry = ""
	S.page = "NAV"
end

function P.DTO.key(k)
	local plan = readPlan()
	local lsk = string.match(k, "^L(%d)$")
	if lsk then
		local r = tonumber(lsk)
		if r == 1 then return end
		local i = (S.dtoPage - 1) * DTO_ROWS + (r - 1)
		if i <= #plan then
			directTo(i)
			S.entry = ""
			S.page = "NAV"
		end
	elseif k == "R6" then
		S.entry = ""
		S.page = (S.back ~= "DTO") and S.back or "FPL"
	elseif k == "ENTER" then
		dtoCommit()
	elseif k == "BACK" then
		S.entry = string.sub(S.entry, 1, -2)
	elseif k == "DEL" then
		S.entry = ""
	elseif k == "NEXT" then
		S.dtoPage = S.dtoPage + 1
		if S.dtoPage > math.max(1, math.ceil(#plan / DTO_ROWS)) then S.dtoPage = 1 end
	elseif k == "PREV" then
		S.dtoPage = S.dtoPage - 1
		if S.dtoPage < 1 then S.dtoPage = math.max(1, math.ceil(#plan / DTO_ROWS)) end
	end
end

-- NAVIGATION ----------------------------------------------------------------
P.NAV = {}
do
-- time over the FR point: noted when the active waypoint moves on to the next one
-- (UTC seconds), watched all the time (core.update), whatever page is shown
local navLeg = { dest = nil, frTime = nil }
function core.navTrack()
	local ok, d = pcall(sasl.getDestinationFMSEntry)
	if not ok or type(d) ~= "number" then return end
	if navLeg.dest ~= d then
		if navLeg.dest and d == navLeg.dest + 1 then navLeg.frTime = val(dr_zulu, 0) else navLeg.frTime = nil end
		navLeg.dest = d
	end
end
local function utcHM(sec)
	if not sec then return nil end
	sec = math.floor(sec) % 86400
	return string.format("%02d:%02d", math.floor(sec / 3600), math.floor(sec / 60) % 60)
end
local function hplusm(min)
	if not min or min ~= min or min < 0 or min > 5999 then return nil end
	local m = math.floor(min + 0.5)
	return string.format("%d+%02d", math.floor(m / 60), m % 60)
end
-- NAV page, laid out as on the UNS-1 (JustFlight): FR / TO / NX with their times
-- (time over FR, ETA at TO and NX, UTC), the active leg (course, distance, time to go)
-- in magenta, the next leg in green; HDG / MNVR on the right; XTK, GS, HEADWIND,
-- BRG, WIND and TKE under the line.
function P.NAV.build()
	local plan, dest = readPlan()
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	local off = magOff()
	local gs = val(dr_gs, 0) * 1.943844
	local trk = wrap360(val(dr_hpath, 0) + off)
	local zulu = val(dr_zulu, 0)
	put("T", 7, "NAV", C.green)
	put("T", 13, "1/1", C.green)
	-- frame: vertical line right of the FR/TO/NX block, line across under it
	local yLine = ROWF.L3 + 0.068
	putLine(16.6, ROWF.T + 0.035, 16.6, yLine, C.amber)
	putLine(-0.8, yLine, 24.8, yLine, C.amber)

	local fr, to, nx = plan[dest - 1], plan[dest], plan[dest + 1]
	local function ok(e) return e and valid(e.lat, e.lon) end
	put("L1", 0, "FR", C.white, false)
	put("L1", 3, fr and usub(entryName(fr), 7) or "PPOS", C.green)
	putR("L1", 15, utcHM(navLeg.frTime) or "--:--", C.green)
	put("L2", 0, "TO", C.white, false)
	put("L3", 0, "NX", C.white, false)
	local disTo, brgTo, eteTo = nil, nil, nil
	if ok(to) then
		disTo, brgTo = gc(la, lo, to.lat, to.lon)
		if gs > 30 then eteTo = disTo / gs * 60 end
		put("L2", 3, usub(entryName(to), 7), C.magenta)
		putR("L2", 15, eteTo and utcHM(zulu + eteTo * 60) or "--:--", C.magenta)
		-- active leg: course of the leg, distance and time to go
		local crs = ok(fr) and select(2, gc(fr.lat, fr.lon, to.lat, to.lon)) or brgTo
		put("D1", 0, fmtDeg(crs + off), C.magenta, false)
		putR("D1", 10, fmtDist(disTo) .. "NM", C.magenta, false)
		putR("D1", 15, hplusm(eteTo) or "-+--", C.magenta, false)
	else
		put("L2", 3, "-----", C.magenta)
	end
	if ok(nx) and ok(to) then
		local dLeg, cLeg = gc(to.lat, to.lon, nx.lat, nx.lon)
		local legMin = (gs > 30) and (dLeg / gs * 60) or nil
		put("L3", 3, usub(entryName(nx), 7), C.green)
		putR("L3", 15, (eteTo and legMin) and utcHM(zulu + (eteTo + legMin) * 60) or "--:--", C.green)
		put("D2", 0, fmtDeg(cLeg + off), C.green, false)
		putR("D2", 10, fmtDist(dLeg) .. "NM", C.green, false)
		putR("D2", 15, hplusm(legMin) or "-+--", C.green, false)
	else
		put("L3", 3, "-----", C.green)
	end
	-- right: HDG (not available on the Tu-154M UNS-1: blue), MNVR = holding
	putR("L1", 23, "HDG→", C.cyan)
	putR("L2", 23, "MNVR→", C.cyan)

	-- under the line
	local xtk = nil
	if ok(fr) and ok(to) then
		local _, c12 = gc(fr.lat, fr.lon, to.lat, to.lon)
		local d13, c13 = gc(fr.lat, fr.lon, la, lo)
		xtk = math.asin(math.sin(d13 / R_NM) * math.sin(math.rad(c13 - c12))) * R_NM
	end
	put("L4", 0, "XTK", C.white)
	putR("L4", 11, xtk and string.format("%s%.2f", xtk >= 0 and "R" or "L", math.abs(xtk)) or "-----", C.green)
	put("L4", 13, "GS", C.white)
	putR("L4", 23, (gs > 30) and string.format("%d", math.floor(gs + 0.5)) or "---", C.green)
	local wd, ws = val(dr_wdir, 0), val(dr_wspd, 0)
	local hw = ws * math.cos(math.rad(wd - trk))
	put("L5", 0, hw >= 0 and "HEADWIND" or "TAILWIND", C.white)
	putR("L5", 11, string.format("%d", math.floor(math.abs(hw) + 0.5)), C.green)
	put("L5", 13, "BRG", C.white)
	putR("L5", 23, brgTo and string.format("%03d", math.floor(wrap360(brgTo + off) + 0.5) % 360) or "---", C.green)
	put("L6", 0, "WIND", C.white)
	putR("L6", 11, string.format("%03d/%3d", math.floor(wrap360(wd) + 0.5) % 360, math.floor(ws + 0.5)), C.green)
	put("L6", 13, "TKE", C.white)
	local tke = nil
	if ok(fr) and ok(to) then
		local _, c12 = gc(fr.lat, fr.lon, to.lat, to.lon)
		tke = wrap180(trk - wrap360(c12 + off))
	elseif brgTo then
		tke = wrap180(trk - wrap360(brgTo + off))
	end
	putR("L6", 23, tke and string.format("%s %03d", tke >= 0 and "R" or "L", math.floor(math.abs(tke) + 0.5)) or "-----", C.green)
end
end -- NAV

-- WAYPOINT CONFIRM ----------------------------------------------------------
P.WPT = {}
function P.WPT.build()
	local w = S.wpt
	if not w then S.page = "FPL" return P.FPL.build() end
	local c = w.cands[w.idx]
	title(c.id, w.idx, #w.cands, false)
	put("L1", 1, usub(c.name, 22), C.white)
	put("L2", 0, c.kind, C.green)
	put("L2", 7, fmtLat(c.lat), C.green)
	put("L3", 7, fmtLon(c.lon), C.green)
	if c.kind == "VOR" and c.freq then
		put("L4", 0, "FREQ", C.white)
		put("L4", 7, string.format("%.2f", c.freq / 100), C.green)
	elseif c.kind == "NDB" and c.freq then
		put("L4", 0, "FREQ", C.white)
		put("L4", 7, string.format("%d", c.freq), C.green)
	end
	put("L6", 0, "←ACCEPT", C.box, true, true)
	putR("L6", 23, "RTN→", C.white)
end
function P.WPT.key(k)
	local w = S.wpt
	if not w then return end
	if k == "ENTER" or k == "L6" then
		acceptWpt()
	elseif k == "R6" or k == "BACK" then
		S.page = w.back or "FPL"
		S.wpt = nil
	elseif k == "NEXT" then
		w.idx = w.idx + 1
		if w.idx > #w.cands then w.idx = 1 end
	elseif k == "PREV" then
		w.idx = w.idx - 1
		if w.idx < 1 then w.idx = #w.cands end
	end
end

-- X-PLANE CDU PAGES IN UNS COLOURS ------------------------------------------
-- CDU line -> screen row: 0 title, odd = small label above a key line,
-- even = key line, 13 = under the last key line, 14 = scratchpad (bottom)
local MIRROR_ROW = { [0] = "T", "U1", "L1", "U2", "L2", "U3", "L3", "U4", "L4", "U5", "L5", "U6", "L6", "D6", "B" }
local function stripz(s)
	if type(s) ~= "string" then return "" end
	local z = string.find(s, "\0", 1, true)
	if z then s = string.sub(s, 1, z - 1) end
	return s
end
-- X-Plane page title -> UNS page name (first match wins)
local UNS_TITLES = {
	{ "HOLD", "HOLDING" }, { "LEGS", "FPL" }, { "DEP/ARR", "DEP/ARR" }, { "DEPARTURES", "DEPARTURE" },
	{ "ARRIVALS", "ARRIVAL" }, { "DIR INTC", "DTO" }, { "DIRECT", "DTO" },
	{ "CO ROUTE", "STORED FPL" }, { "SEC FPLN", "SEC FPLN" }, { "FPLN", "AIRWAYS" }, { "RTE", "ROUTE" }, { "ROUTE MENU", "ROUTE MENU" }, { "INIT/REF", "DATA" },
	{ "INDEX", "DATA" }, { "IDENT", "DATA" }, { "POS INIT", "POS INIT" },
	{ "PERF INIT", "PERF INIT" }, { "NAV RAD", "TUNE" }, { "NAV RADIO", "TUNE" },
	{ "PROGRESS", "PROGRESS" }, { "FIX", "FIX" },
	{ "CLB", "VNAV CLB" }, { "CRZ", "VNAV CRZ" }, { "DES", "VNAV DES" },
	{ "SELECT", "SELECT WPT" },
}
local BOX_A, BOX_B = "\226\150\161", "\226\152\144"  -- the two box characters X-Plane uses

-- runs of characters with the same X-Plane style on one line
local function styledRuns(line)
	local txt = stripz(val(cdu_text[line], ""))
	local runs = {}
	if txt == "" then return runs, txt end
	local sty = val(cdu_style[line], "")
	local chars = uchars(txt)
	local i = 1
	while i <= #chars and i <= 24 do
		local b = string.byte(sty, i) or 0
		local j = i
		while j + 1 <= #chars and j + 1 <= 24 and (string.byte(sty, j + 1) or 0) == b do j = j + 1 end
		local rest = b % 128
		runs[#runs + 1] = {
			col = i - 1, text = table.concat(chars, "", i, j), big = b >= 128,
			inv = (rest % 128) >= 64, flash = (rest % 64) >= 32, xc = b % 8,
		}
		i = j + 1
	end
	return runs, txt
end

-- UNS colour for X-Plane text: data green, labels white, magenta/amber kept
local function unsColor(r)
	local xc = r.xc
	if xc == 5 then return C.magenta end
	if xc == 6 then return C.amber end
	if xc == 2 then return C.red end
	if xc == 3 then return C.yellow end
	if string.find(r.text, "←", 1, true) or string.find(r.text, "→", 1, true) then return C.white end
	if r.big then return C.green end
	return C.white
end

-- X-Plane page title -> (UNS name, page, total, MOD)
local function pageInfo()
	local _, title = styledRuns(0)
	local t = string.upper(title)
	local cur, tot = string.match(t, "(%d+)%s*/%s*(%d+)")
	local mod = string.find(t, "MOD", 1, true) ~= nil
	local base = string.gsub(t, "%d+%s*/%s*%d+", "")
	base = string.gsub(base, "^%s*ACT%s+", "")
	base = string.gsub(base, "^%s*MOD%s+", "")
	base = string.match(base, "^%s*(.-)%s*$") or ""
	-- whole words only ("SELECT DESIRED WPT" must not match "DES")
	local name = base
	for _, m in ipairs(UNS_TITLES) do
		local pat = "%f[%w]" .. string.gsub(m[1], "[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0") .. "%f[^%w]"
		if string.find(base, pat) then name = m[2] break end
	end
	return name, cur, tot, mod
end
core.pageInfo = pageInfo

-- X-Plane scratchpad: the line that starts with "[" (and the "]" next to it)
local function isScratchLine(txt)
	return string.match(txt, "^%s*%[") ~= nil or string.match(txt, "^%s*%]%s*$") ~= nil
		or (string.match(txt, "%]%s*$") ~= nil and string.find(txt, "[", 1, true) ~= nil)
end
local function scratchText()
	for line = 11, 15 do
		local txt = stripz(val(cdu_text[line], ""))
		if string.match(txt, "^%s*%[") then
			local sp = string.gsub(txt, "[%[%]]", "")
			return string.match(sp, "^%s*(.-)%s*$") or ""
		end
	end
	return ""
end
core.scratchText = scratchText

-- name of the waypoint on X-Plane LEGS key line k (lines 2,4,...,10)
local function legsRowName(k)
	local txt = stripz(val(cdu_text[2 * k], ""))
	local n = string.match(string.sub(txt, 1, 12), "^%s*(%S+)")
	if not n then return nil end
	return (string.gsub(n, "@$", ""))
end

local procNumberKey, buildProcPage, buildHoldPage, holdKeyFor, buildHoldFixPage
do
-- DEPARTURE / ARRIVAL (X-Plane's DEPARTURES / ARRIVALS pages) the UNS way:
-- white column headings (SEL SID, RUNWAY, ...), the list items numbered on the left
-- (type the number, ENTER = the same as its line key), the selected/active items in
-- a cursor box. The line keys stay where X-Plane has them.
local PROC_HEAD = {
	{ "SIDS", "SEL SID" }, { "SID", "SEL SID" }, { "STARS", "SEL STAR" }, { "STAR", "SEL STAR" },
	{ "RUNWAYS", "RUNWAY" }, { "APPROACHES", "APPR" }, { "APPROACH", "APPR" },
	{ "TRANSITIONS", "TRANSITION" }, { "TRANS", "TRANSITION" },
}
local function trim(x) return (string.match(x or "", "^%s*(.-)%s*$")) or "" end
-- a CDU line split into its left and right parts (parts are 2+ spaces apart)
local function splitSides(txt)
	local chars = uchars(txt)
	local segs = {}
	local i = 1
	while i <= #chars do
		if chars[i] ~= " " then
			local j = i
			while j < #chars and not (chars[j + 1] == " " and (chars[j + 2] == " " or j + 2 > #chars)) do j = j + 1 end
			segs[#segs + 1] = { col = i - 1, text = table.concat(chars, "", i, j) }
			i = j + 1
		else
			i = i + 1
		end
	end
	-- the first part is the left side (unless it starts in the right half);
	-- every further part belongs to the right side
	local left, right = {}, {}
	for i, sg in ipairs(segs) do
		if i == 1 and sg.col < 12 then left[#left + 1] = sg.text else right[#right + 1] = sg.text end
	end
	return trim(table.concat(left, " ")), trim(table.concat(right, " ")), (segs[1] and segs[1].col or 0)
end
local function procItem(x)
	local sel = string.find(x, "<SEL>", 1, true) or string.find(x, "<ACT>", 1, true)
	x = string.gsub(x, "<SEL>", "")
	x = string.gsub(x, "<ACT>", "")
	x = string.gsub(x, "^%s*<", "")
	x = string.gsub(x, ">%s*$", "")
	return trim(x), sel ~= nil
end
local function procHead(x)
	local u = trim(x)
	for _, m in ipairs(PROC_HEAD) do
		if u == m[1] then return m[2] end
	end
	return u
end
-- number n on a DEPARTURE / ARRIVAL page -> left line key on this X-Plane page
procNumberKey = function(n, page)
	local k = n - (page - 1) * 5
	if k < 1 or k > 5 then return nil end
	local left = splitSides(stripz(val(cdu_text[2 * k], "")))
	local item = procItem(left)
	if item == "" then return nil end
	return k
end
core.procNumberKey = procNumberKey

buildProcPage = function(name, cur, tot, mod)
	if mod then put("T", 0, "MOD", C.amber, false) end
	put("T", 5, name, C.green)
	if cur then put("T", 16, cur .. "/" .. tot, C.green) end
	local page = tonumber(cur) or 1
	for line = 1, 13 do
		local row = MIRROR_ROW[line]
		local txt = stripz(val(cdu_text[line], ""))
		local separator = string.match(txt, "^[%s%-]*$") and string.find(txt, "------------", 1, true)
		if txt ~= "" and not separator and not isScratchLine(txt) then
			local left, right = splitSides(txt)
			if line % 2 == 1 and line <= 11 then
				-- column headings
				if left ~= "" then put(row, 0, procHead(left), C.white, false) end
				if right ~= "" then putR(row, 23, procHead(right), C.white, false) end
			elseif line <= 10 then
				-- list items: numbered on the left, plain on the right
				local li, ls = procItem(left)
				if li ~= "" then
					putR(row, 1, string.format("%d", (page - 1) * 5 + math.floor(line / 2)), C.white)
					if ls then put(row, 3, usub(li, 10), C.box, true, true) else put(row, 3, usub(li, 10), C.green) end
				end
				local ri, rs = procItem(right)
				if ri ~= "" then
					if rs then putR(row, 23, usub(ri, 10), C.box, true, true) else putR(row, 23, usub(ri, 10), C.green) end
				end
			else
				-- prompts at the bottom (<ERASE, ROUTE>, ...): UNS arrows
				if left ~= "" then put(row, 0, (string.gsub(left, "^<", "←")), C.white) end
				if right ~= "" then putR(row, 23, (string.gsub(right, ">$", "→")), C.white) end
			end
		end
	end
	local sp = scratchText()
	if sp ~= "" then
		local w = math.max(ulen(sp), 8)
		put("B", 0, sp .. string.rep(" ", w - ulen(sp)), C.box, true, true)
	else
		put("B", 0, "#", C.white)
		put("B", 1, "--", C.box, true, true)
	end
end

-- HOLDING: the UNS / JustFlight layout built from X-Plane's own HOLD page.
-- X-Plane's fields are found by their names on its page; each UNS key presses the
-- X-Plane key of that field behind the scenes (typed text goes to X-Plane first).
--   left:  FIX, INBD, TURN, QUAD/RAD, MAX KIAS        right: TIME, DIST, ETA, EFC, SPD RULE
--   middle: the racetrack (inbound leg with arrow, fix marked; mirrored for left turns)
local HOLD_FIELDS = {     -- X-Plane label -> our name
	["FIX"] = "fix", ["QUAD/RAD"] = "quad", ["QUAD/RADIAL"] = "quad", ["INBD CRS/DIR"] = "inbd",
	["LEG TIME"] = "time", ["LEG DIST"] = "dist", ["ENTRY HOLD SPEED"] = "rule",
	["MAX KIAS"] = "kias", ["FIX ETA"] = "eta", ["EFC TIME"] = "efc",
}
-- X-Plane's HOLD page: { name = {text=, key="3l"} }, prompts = list of {text, key}
local function holdParse()
	local F, prompts = {}, {}
	for line = 1, 12 do
		local txt = stripz(val(cdu_text[line], ""))
		local l, r = splitSides(txt)
		local k = math.floor((line + 1) / 2)
		if line % 2 == 1 then
			local vtxt = stripz(val(cdu_text[line + 1], ""))
			local vl, vr = splitSides(vtxt)
			if HOLD_FIELDS[l] then F[HOLD_FIELDS[l]] = { text = vl, key = k .. "l", line = line + 1 } end
			if HOLD_FIELDS[r] then F[HOLD_FIELDS[r]] = { text = vr, key = k .. "r", line = line + 1 } end
		else
			if string.match(l, "^<") then prompts[#prompts + 1] = { text = l, key = k .. "l" } end
			if string.match(r, ">$") then prompts[#prompts + 1] = { text = r, key = k .. "r" } end
		end
	end
	return F, prompts
end
core.holdParse = holdParse

-- UNS key on HOLDING -> what to do on X-Plane's page (set while the page is built)
local holdKeys = {}
holdKeyFor = function(k) return holdKeys[k] end

-- HOLD FIX: X-Plane's "HOLD AT" page (its LEGS list with the HOLD AT box). The UNS
-- shows the flight plan points numbered (left keys), the HOLD FIX field (right key
-- 1: typed identifier or number) and PPOS. Picking a point makes the hold there.
local function holdAtKey()
	for line = 1, 12 do
		local txt = stripz(val(cdu_text[line], ""))
		if string.find(txt, "HOLD AT", 1, true) then
			-- the label line; its box is the next line (left key)
			return math.floor((line + 2) / 2)
		end
	end
	return nil
end
core.holdAtKey = holdAtKey
local function holdFixName(k)
	local txt = stripz(val(cdu_text[2 * k], ""))
	local l = splitSides(txt)
	local n = string.match(l, "^%s*(%S+)")
	if not n or string.find(n, BOX_A, 1, true) or string.find(n, BOX_B, 1, true) then return nil end
	return (string.gsub(n, "@$", ""))
end
core.holdFixName = holdFixName
buildHoldFixPage = function(cur, tot)
	put("T", 4, "HOLD FIX", C.green)
	put("T", 15, (cur or "1") .. "/" .. (tot or "1"), C.green)
	local page = tonumber(cur) or 1
	local atK = holdAtKey()
	for k = 1, 5 do
		if atK and 2 * k >= 2 * atK - 1 then break end     -- the list ends above HOLD AT
		local n = holdFixName(k)
		if n then
			local row = "L" .. k
			putR(row, 1, string.format("%d", (page - 1) * 5 + k), C.white)
			put(row, 2, ">", C.white)
			put(row, 3, usub(n, 8), C.green)
		end
	end
	putR("U1", 23, "HOLD FIX", C.white, false)
	local sp = scratchText()
	local t = (sp ~= "") and usub(sp, 5) or "-----"
	putR("L1", 23, t .. string.rep(" ", math.max(0, 5 - ulen(t))), C.box, true, true)
	-- X-Plane's PPOS (hold at present position)
	for line = 1, 12 do
		local _, r = splitSides(stripz(val(cdu_text[line], "")))
		if string.find(r, "PPOS", 1, true) then
			putR("L6", 23, "PPOS→", C.white)
			break
		end
	end
end

local holdLogged = ""
buildHoldPage = function(cur, tot, mod)
	local F, prompts = holdParse()
	holdKeys = {}
	-- X-Plane's page text goes to Log.txt once whenever it changes (to check the layout)
	local L = {}
	for i = 0, 13 do L[i] = stripz(val(cdu_text[i], "")) end
	local raw = table.concat(L, "|", 1, 13) .. L[0]
	if raw ~= holdLogged then
		holdLogged = raw
		local t = {}
		for i = 0, 13 do t[#t + 1] = string.format("%2d|%s|", i, L[i] or "") end
		sasl.logWarning("UNS HOLD page (CDU " .. CURCDU .. ")\n" .. table.concat(t, "\n"))
	end
	-- not X-Plane's hold definition (fewer than 3 of its fields): show the page as it is
	local n = 0
	for _ in pairs(F) do n = n + 1 end
	if n < 3 then return false end
	if mod then put("T", 0, "MOD", C.amber, false) end
	put("T", 6, "HOLDING", C.green)
	put("T", 15, (cur or "1") .. "/" .. (tot or "1"), C.green)
	local W, G = C.white, C.green
	local function v(f) return (f and f.text ~= "") and f.text or nil end
	-- INBD CRS/DIR "151°/R TURN" -> course, turn
	local crs, turn = nil, nil
	local inbd = v(F.inbd)
	if inbd then
		crs = string.match(inbd, "^([%d%-]+°?)")
		local d = string.match(inbd, "/%s*([LR])")
		turn = (d == "L") and "LEFT" or (d == "R") and "RIGHT" or nil
	end
	local function num(f) local t = v(f) return t and (string.match(t, "^([%d%.%-]+)") or t) or nil end
	-- left column
	local function left(row, label, value, uk, field)
		put("U" .. row, 0, label, W, false)
		put("L" .. row, 0, usub(value or "----", 7), G)
		if field then holdKeys["L" .. row] = { key = field.key, kind = uk } end
	end
	local function right(row, label, value, uk, field)
		putR("U" .. row, 23, label, W, false)
		putR("L" .. row, 23, usub(value or "----", 7), G)
		if field then holdKeys["R" .. row] = { key = field.key, kind = uk } end
	end
	left(1, "FIX", v(F.fix), "plain", F.fix)
	left(2, "INBD", crs, "plain", F.inbd)
	left(3, "TURN", turn, "turn", F.inbd)
	left(4, "QUAD/RAD", v(F.quad), "plain", F.quad)
	left(5, "MAX KIAS", num(F.kias), "plain", F.kias)
	right(1, "TIME", num(F.time), "plain", F.time)
	right(2, "DIST", num(F.dist), "plain", F.dist)
	right(3, "ETA", v(F.eta), "plain", F.eta)
	if not v(F.eta) or string.match(v(F.eta), "^[%-:%s]+$") then M[#M].color = C.cyan end   -- shown only
	right(4, "EFC", v(F.efc), "plain", F.efc)
	-- speed rule: the selected one (big on X-Plane's page) is shown
	local rule = nil
	if F.rule then
		for _, r in ipairs(styledRuns(F.rule.line)) do
			local t = trim(r.text)
			if r.big and (string.find(t, "FAA", 1, true) or string.find(t, "ICAO", 1, true)) then
				rule = string.find(t, "ICAO", 1, true) and "ICAO" or "FAA"
			end
		end
	end
	right(5, "SPD RULE", rule, "plain", F.rule)
	-- bottom: X-Plane's prompts (ERASE, NEW HOLD, EXIT HOLD ...) on keys 6
	local pl, pr = nil, nil
	for _, pp in ipairs(prompts) do
		if string.match(pp.key, "l$") and not pl then pl = pp end
		if string.match(pp.key, "r$") then pr = pp end           -- the lowest one
	end
	if pl then
		put("L6", 0, (string.gsub(pl.text, "^<", "←")), W)
		holdKeys["L6"] = { key = pl.key, kind = "plain" }
	elseif v(F.fix) and not mod then
		-- X-Plane has no exit prompt: the UNS leaves the hold by a direct-to the point
		-- after the hold fix (at once, as DTO would). Only offered while the aircraft is
		-- at the hold: the active leg goes to the hold fix, or comes from it.
		local plan, dest = readPlan()
		local function nm(e) return e and (string.gsub(e.id or "", "@$", "")) or nil end
		local fix = v(F.fix)
		local near = false
		-- the hold fix around the active leg, or the aircraft within 20 NM of it
		for i = math.max(1, dest - 2), math.min(#plan, dest + 2) do
			if nm(plan[i]) == fix then near = true end
		end
		if not near then
			local la, lo = val(dr_lat, 0), val(dr_lon, 0)
			for i = math.max(1, dest - 2), #plan do
				local e = plan[i]
				if nm(e) == fix and valid(e.lat, e.lon) and gc(la, lo, e.lat, e.lon) < 20 then near = true break end
			end
		end
		if near or (SH.userHold and fix == SH.userHold) then
			put("L6", 0, "←EXIT HOLD", W)
			holdKeys["L6"] = { kind = "exit", fix = fix }
		end
		-- the plan around the active leg goes to Log.txt once whenever it changes
		local t = {}
		for i = math.max(1, dest - 3), math.min(#plan, dest + 4) do
			t[#t + 1] = string.format("%s%d:%s", (i == dest) and "*" or "", i, plan[i].id or "")
		end
		local line = "UNS HOLD " .. tostring(fix) .. " plan: " .. table.concat(t, " ")
		if line ~= core.holdPlanLogged then
			core.holdPlanLogged = line
			sasl.logWarning(line)
		end
	end
	if pr then
		putR("L6", 23, (string.gsub(pr.text, ">$", "→")), W)
		holdKeys["R6"] = { key = pr.key, kind = "plain" }
	end

	-- the racetrack: inbound leg ends at the fix (left end); right turns: inbound leg
	-- at the bottom, left turns: at the top
	local yl = C.yellow
	local cA, cB = 10.6, 13.4
	local rTop, rBot = ROWF.L1 + 0.075, ROWF.L4 - 0.035
	local rMid = (rTop + rBot) / 2
	local radCol = (rBot - rTop) / 2 * 506 / (800 * 0.94 / 24)
	putLine(cA, rTop, cB, rTop, yl)
	putLine(cA, rBot, cB, rBot, yl)
	M[#M + 1] = { shape = "arc", c = cB, r = rMid, rad = radCol, a1 = -90, a2 = 90, color = yl }
	M[#M + 1] = { shape = "arc", c = cA, r = rMid, rad = radCol, a1 = 90, a2 = 270, color = yl }
	local rIn = (turn == "LEFT") and rTop or rBot
	local cm = (cA + cB) / 2
	local dy = 0.022
	-- arrow on the inbound leg, pointing to the fix (left)
	putLine(cm - 0.35, rIn, cm + 0.25, rIn - dy, C.green)
	putLine(cm - 0.35, rIn, cm + 0.25, rIn + dy, C.green)
	-- the fix: a small cross at the left end of the inbound leg
	putLine(cA - 0.25, rIn - dy, cA + 0.25, rIn + dy, C.green)
	putLine(cA - 0.25, rIn + dy, cA + 0.25, rIn - dy, C.green)

	-- typed text (X-Plane scratchpad) in the bottom box
	local sp = scratchText()
	if sp ~= "" then
		put("B", 0, sp .. string.rep(" ", math.max(0, 6 - ulen(sp))), C.box, true, true)
	end
end

end

P.MIRROR = {}
function P.MIRROR.build()
	local blinkOn = (math.floor(now() * 2) % 2) == 0

	-- title: UNS name, page number, MOD marker
	local name, cur, tot, mod = pageInfo()
	if S.vnavMirror and S.pageSet then
		local extra = (S.pageSet == "VNAV") and (core.vnavPtPages() - 1) or 0
		cur, tot = tostring(S.vnavMirror + extra), tostring(core.SETS[S.pageSet].n + extra)
	end
	if name == "DEPARTURE" or name == "ARRIVAL" then
		S.legsSel = nil
		return buildProcPage(name, cur, tot, mod)
	end
	if name == "HOLDING" then
		S.legsSel = nil
		if core.holdAtKey() then return buildHoldFixPage(cur, tot) end
		if buildHoldPage(cur, tot, mod) ~= false then return end
	end
	local isLegs = (name == "FPL")
	if not isLegs then S.legsSel = nil end
	local sel = isLegs and S.legsSel or nil
	-- UNS title: [MOD]  NAME  n/m  - placed so nothing overlaps
	local pg = cur and (cur .. "/" .. tot) or ""
	local nm = usub(name, 12)
	local nameCol = 6
	local pgCol = math.max(15, nameCol + ulen(nm) + 2)
	if pgCol + ulen(pg) > 24 then
		pgCol = 24 - ulen(pg)
		nameCol = math.max(mod and 4 or 0, pgCol - 2 - ulen(nm))
		if nameCol + ulen(nm) > pgCol - 1 then nm = usub(nm, math.max(1, pgCol - 1 - nameCol)) end
	end
	if mod then put("T", 0, "MOD", C.amber, false) end
	if nm ~= "" then put("T", nameCol, nm, C.green) end
	if pg ~= "" then put("T", pgCol, pg, C.green) end
	-- FPL: the framed H over the altitude column (right side), as on the UNS
	if (isLegs and not sel) or name == "DTO" then putFrame("T", 22, "H", C.green) end
	local page = tonumber(cur) or 1

	for line = 1, 13 do
		local row = MIRROR_ROW[line]
		local runs, txt = styledRuns(line)
		-- Boeing dashed separator lines are not shown
		local separator = string.match(txt, "^[%s%-]*$") and string.find(txt, "------------", 1, true)
		-- DTO: the points only, as on the UNS (X-Plane's course lines above them are left out)
		local dtoCourse = (name == "DTO") and line % 2 == 1 and line >= 3 and line <= 9
			and string.match(txt, "^%s*%d+°?%s*$") ~= nil
		if not separator and not dtoCourse and not isScratchLine(txt) then
			for _, r in ipairs(runs) do
				local s = r.text
				-- FPL: a list of points as on the UNS - X-Plane's course / distance
				-- lines between them (e.g. " 090°  10.0NM", "(DIR)16.6NM") are left out
				if name == "DTO" and line % 2 == 1 and line <= 11
					and (string.find(s, "°", 1, true) or string.find(s, "NM", 1, true)) then
					s = ""
				end
				-- arrows the UNS way
				s = string.gsub(s, "^(%s*)<", "%1←")
				s = string.gsub(s, ">(%s*)$", "→%1")
				r.text = s   -- colour rule sees the UNS arrows
				local box = string.find(s, BOX_A, 1, true) or string.find(s, BOX_B, 1, true)
				local col = r.col
				-- waypoint selected: the right side shows the UNS options instead,
				-- so X-Plane text is cut at column 11 (by character position)
				if sel and line <= 12 then
					if line == 12 or col >= 11 then
						s = ""
					else
						s = usub(s, 11 - col)
					end
				end
				-- FPL (LEGS): number the waypoints like the UNS flight plan, "3>SF701";
				-- only the name moves, the rest of the line stays under its keys
				if isLegs and line % 2 == 0 and line <= 10 and col == 0 and not string.match(s, "^%s") then
					local n = math.floor((page - 1) * 5 + line / 2 + 0.5)
					local name, restAt = string.match(s, "^(%S+)()")
					putR(row, 1, string.format("%d", n), C.white)
					put(row, 2, ">", C.white)
					if box then
						-- route discontinuity: UNS cursor box (selectable, DEL closes it)
						put(row, 3, "     ", (sel == line / 2) and C.amber or C.box, r.big, true)
						name, restAt, box = "", #s + 1, false
					elseif sel == line / 2 then
						put(row, 3, usub(name, 8), C.box, r.big, true)   -- UNS cursor on the selected point
					elseif name ~= "" then
						put(row, 3, usub(name, 8), unsColor(r), r.big)
					end
					local rest = string.sub(s, restAt)
					if not sel and string.match(rest, "%S") then
						local lead = string.match(rest, "^(%s*)")
						local rcol = math.max(ulen(name) + ulen(lead), 3 + math.min(ulen(name), 8) + 1)
						local rtxt = (string.gsub(rest, "^%s*", ""))
						-- keep it inside the screen: drop what would run past column 24
						if rcol + ulen(rtxt) > 24 then rtxt = usub(rtxt, math.max(0, 24 - rcol)) end
						if rtxt ~= "" then put(row, rcol, rtxt, unsColor(r), r.big) end
					end
					s = ""
				end
				if box then
					-- required entry: UNS cursor box
					local w = ulen(s)
					put(row, col, string.rep(" ", w), C.box, r.big, true)
				elseif s ~= "" and (not string.match(s, "^%s*$") or r.inv) then
					if not (r.flash and not blinkOn) then
						if r.inv then
							M[#M + 1] = { row = row, col = col, text = s, color = C.box, big = r.big, inv = true }
						else
							M[#M + 1] = { row = row, col = col, text = s, color = unsColor(r), big = r.big }
						end
					end
				end
			end
		end
	end

	-- selected waypoint: UNS options (white), as on the UNS flight plan page
	if sel then
		putR("L1", 23, S.legsDelArmed and "CONFIRM→" or "DEL→", S.legsDelArmed and C.amber or C.white)
		putR("L2", 23, "DTO→", C.white)
		putR("L3", 23, "HOLD→", C.white)
		putR("L6", 23, "RTN→", C.white)
	end


	-- scratchpad: what is typed goes into a UNS cursor box at the bottom (no brackets)
	local sp = scratchText()
	if sp ~= "" then
		local w = math.max(ulen(sp), 8)
		put("B", 0, sp .. string.rep(" ", w - ulen(sp)), C.box, true, true)
	end
end
-- in mirror mode the keys go to X-Plane's own CDU (handled in core.key)

-------------------------------------------------------------------------------
-- keys
-------------------------------------------------------------------------------
-- the X-Plane command behind every UNS key (same as the 3D keypad used before)
local BOEING = {
	DATA = "sim/FMS/index", NAV = "sim/FMS/legs", VNAV = "sim/FMS/clb", DTO = "sim/FMS/dir_intc",
	LIST = "sim/FMS/fix", PREV = "sim/FMS/prev", HOLD = "sim/FMS/hold", FPL = "sim/FMS/fpln",
	PERF = "sim/FMS/prog", TUNE = "sim/FMS/navrad", MENU = "sim/FMS/dep_arr", NEXT = "sim/FMS/next",
	BACK = "sim/FMS/key_clear", DEL = "sim/FMS/key_delete", DOT = "sim/FMS/key_period",
	SLASH = "sim/FMS/key_slash", ENTER = "sim/FMS/exec",
}
for c = string.byte("A"), string.byte("Z") do
	local ch = string.char(c)
	BOEING[ch] = "sim/FMS/key_" .. ch
end
for d = 0, 9 do BOEING[tostring(d)] = "sim/FMS/key_" .. d end
for k = 1, 6 do
	BOEING["L" .. k] = "sim/FMS/ls_" .. k .. "l"
	BOEING["R" .. k] = "sim/FMS/ls_" .. k .. "r"
end
core.BOEING = BOEING

local cmdCache = {}
local function xpCommand(name)
	-- unit 2 works through X-Plane's second CDU
	if CURCDU == 2 and string.sub(name, 1, 8) == "sim/FMS/" then
		name = "sim/FMS2/" .. string.sub(name, 9)
	end
	local c = cmdCache[name]
	if c == nil then
		c = sasl.findCommand(name) or false
		cmdCache[name] = c
	end
	if c then sasl.commandOnce(c) end
end

-- FPL MENU (first page at power-on, and the MENU key) ------------------------
-- ORIGIN and DEST have to be X-Plane's own origin/destination (only then does
-- X-Plane's DEP/ARR page offer runways, SIDs and STARs). They are typed on this
-- UNS page; the UNS then enters them in X-Plane's own flight plan page behind the
-- scenes, reading X-Plane's screen text to find the page and to check the result.

-- X-Plane CDU screen text, lines 0..15 (plain strings)
local function cduLines()
	local L = {}
	for i = 0, 15 do L[i] = stripz(val(cdu_text[i], "")) end
	return L
end

-- line-select key next to a word on X-Plane's screen: lines 1-2 = key 1, 3-4 = key 2 ...
local function lskOf(line, col)
	return math.floor((line + 1) / 2), (col <= 12) and "l" or "r"
end
local function findWord(L, word)
	for line = 1, 12 do
		local c = string.find(L[line], word, 1, true)
		if c then return lskOf(line, c) end
	end
	return nil
end
-- a menu entry that leads to X-Plane's flight plan page ("<RTE", "FPLN>", ...)
local PLAN_ITEMS = { "RTE", "FPLN", "FLT PLAN", "FLIGHT PLAN" }
-- never the secondary / second / alternate / company route: typing ORIGIN there makes
-- X-Plane hold a second flight plan, which its map (Kontur) then draws as well
local NOT_PRIMARY = { "SEC", "RTE 2", "RTE2", "ALTN", "CO ROUTE", "2ND" }
local function isPrimaryText(t)
	for _, w in ipairs(NOT_PRIMARY) do
		if string.find(t, w, 1, true) then return false end
	end
	return true
end
local function findPlanItem(L)
	for line = 1, 12 do
		local t = L[line] or ""
		local halves = { { string.sub(t, 1, 12), "l" }, { string.sub(t, 13), "r" } }
		for _, h in ipairs(halves) do
			local part, side = h[1], h[2]
			if isPrimaryText(part) then
				for _, w in ipairs(PLAN_ITEMS) do
					if (side == "l" and string.find(part, "<" .. w, 1, true))
						or (side == "r" and string.find(part, w .. ">", 1, true)) then
						return math.floor((line + 1) / 2), side
					end
				end
			end
		end
	end
	return nil
end
-- background jobs (several X-Plane key presses with short waits in between)
-- (one job per unit, each on its own X-Plane CDU)
local JOB = { {}, {} }
local function runJob(fn)
	JOB[CUR].co = coroutine.create(fn)
	JOB[CUR].wake = 0
end
local function wait(s)
	JOB[CUR].wake = now() + s
	coroutine.yield()
end
local function jobStep()
	for u = 1, 2 do
		local J = JOB[u]
		if J.co and now() >= (J.wake or 0) then
			setUnit(u)
			local ok, err = coroutine.resume(J.co)
			if not ok then
				sasl.logWarning("UNS job: " .. tostring(err))
				S.busy = nil
				J.co = nil
			elseif coroutine.status(J.co) == "dead" then
				J.co = nil
			end
			dirtySoon()
		end
	end
end

-- empty X-Plane's scratchpad: press CLR only while it still shows something
-- (never on an empty scratchpad - X-Plane may answer with a message), one per frame
local function clearScratchSafe()
	for _ = 1, 30 do
		if scratchText() == "" then return end
		xpCommand("sim/FMS/key_clear")
		wait(0.06)
	end
end

local function typeXP(text)
	for ch in string.gmatch(text, ".") do
		if ch == "/" then xpCommand("sim/FMS/key_slash")
		elseif ch == "." then xpCommand("sim/FMS/key_period")
		elseif BOEING[ch] then xpCommand(BOEING[ch]) end
	end
end

-- the primary flight plan page: has ORIGIN, title not secondary
local function onPrimaryPlanPage(L)
	return findWord(L, "ORIGIN") ~= nil and isPrimaryText(string.upper(L[0] or ""))
end
local function openPlanPage()
	xpCommand("sim/FMS/fpln")
	wait(0.25)
	for try = 1, 5 do
		local L = cduLines()
		if onPrimaryPlanPage(L) then return true end
		local k, side = findPlanItem(L)
		if k then
			xpCommand("sim/FMS/ls_" .. k .. side)
		else
			local ik, iside = findWord(L, "<INDEX")
			if ik and try <= 2 then
				xpCommand("sim/FMS/ls_" .. ik .. iside)
			else
				xpCommand("sim/FMS/fpln")
			end
		end
		wait(0.25)
	end
	return onPrimaryPlanPage(cduLines())
end

-- which = "ORIGIN" or "DEST"
local function setAirport(which, icao)
	runJob(function()
		S.busy = which
		if not openPlanPage() then
			msg("NO " .. which .. " PAGE - USE DATA")
			S.busy = nil
			return
		end
		local k, side = findWord(cduLines(), which)
		if not k then
			msg(which .. " NOT FOUND")
			S.busy = nil
			return
		end
		clearScratchSafe()   -- empty X-Plane's scratchpad
		wait(0.1)
		typeXP(icao)
		wait(0.15)
		xpCommand("sim/FMS/ls_" .. k .. side)
		wait(0.25)
		xpCommand("sim/FMS/exec")
		wait(0.25)
		-- check X-Plane took it
		local ok = false
		for line = 1, 12 do
			if string.find(cduLines()[line], icao, 1, true) then ok = true end
		end
		if ok then
			if which == "ORIGIN" then
				S.origin = icao
				S.dto = nil
			else
				S.dest = icao
			end
			msg(which .. " " .. icao)
		else
			msg(which .. " NOT ACCEPTED")
		end
		S.busy = nil
	end)
end

-- FLIGHT PLAN EDITS THROUGH X-PLANE'S LEGS PAGE ------------------------------
-- LEGS layout (X-Plane 12): waypoint names on lines 2,4,6,8,10 (left keys 1-5),
-- speed/altitude on the right of the same lines, page number "n/m" in the title.
local function clearScratch()
	clearScratchSafe()
end
local function legsName(line)
	local t = string.match(string.sub(line or "", 1, 12), "^%s*(%S+)")
	if not t then return nil end
	return (string.gsub(t, "@$", ""))
end
local function isEmptyRow(line)
	local l = string.sub(line or "", 1, 14)
	return string.find(l, "-----", 1, true) or string.find(l, "\226\152\144", 1, true)
		or string.find(l, "\226\150\161", 1, true)
end
-- go through all LEGS pages; rows = { {page, key, name, empty} }
local function legsScan()
	xpCommand("sim/FMS/legs")
	wait(0.25)
	local rows = {}
	for page = 1, 15 do
		local L = cduLines()
		for k = 1, 5 do
			local line = L[2 * k]
			if isEmptyRow(line) then
				rows[#rows + 1] = { page = page, key = k, empty = true }
			else
				local n = legsName(line)
				if n then rows[#rows + 1] = { page = page, key = k, name = n } end
			end
		end
		local cur, tot = string.match(L[0] or "", "(%d+)/(%d+)")
		if not cur or tonumber(cur) >= tonumber(tot) then break end
		xpCommand("sim/FMS/next")
		wait(0.2)
	end
	return rows
end
local function legsGoto(page)
	xpCommand("sim/FMS/legs")
	wait(0.2)
	for _ = 2, page do
		xpCommand("sim/FMS/next")
		wait(0.15)
	end
end
local function findRow(rows, name)
	for _, r in ipairs(rows) do if r.name == name then return r end end
	return nil
end
local function planHas(ident)
	for _, e in ipairs(readPlan()) do if e.id == ident then return true end end
	return false
end

-- empty field on an X-Plane line ("-----", boxes): returns "l" or "r"
local EMPTY_MARKS = { "-----", "\226\152\144", "\226\150\161", "_____" }
local function emptySide(line)
	line = line or ""
	local left, right
	for _, m in ipairs(EMPTY_MARKS) do
		local c = string.find(line, m, 1, true)
		while c do
			if c <= 12 then left = true else right = true end
			c = string.find(line, m, c + 1, true)
		end
	end
	if right then return "r" end
	if left then return "l" end
	return nil
end

-- type ident into X-Plane's SELECT DESIRED WPT page if it appears
local function pickIfSelect(choice)
	if string.find(cduLines()[0], "SELECT", 1, true) then
		local c = choice or 1
		if c > 6 then c = 1 end
		xpCommand("sim/FMS/ls_" .. c .. "l")
		wait(0.3)
	end
end

-- empty LEGS page (only ORIGIN/DEST so far): enter the waypoint on X-Plane's route
-- page, next to the first empty field after the ORIGIN/DEST page (X-Plane manual: FPLN,
-- NEXT PAGE, ident, key beside the next unused waypoint)
local function routePageInsert(ident, choice)
	if not openPlanPage() then return false end
	for page = 1, 6 do
		xpCommand("sim/FMS/next")
		wait(0.25)
		local L = cduLines()
		local key, side
		for k = 1, 6 do
			local sd = emptySide(L[2 * k])
			if sd == "r" then key, side = k, sd break end
			if sd == "l" and not key then key, side = k, sd end
		end
		if key then
			clearScratch()
			wait(0.1)
			typeXP(ident)
			wait(0.15)
			xpCommand("sim/FMS/ls_" .. key .. side)
			wait(0.3)
			pickIfSelect(choice)
			return true
		end
		local cur, tot = string.match(L[0] or "", "(%d+)/(%d+)")
		if cur and tonumber(cur) >= tonumber(tot) then break end
	end
	return false
end

legsInsert = function(ident, beforeIdent, choice)
	runJob(function()
		S.busy = "FPL"
		local rows = legsScan()
		local row
		if beforeIdent then row = findRow(rows, beforeIdent) end
		if not row then
			for _, r in ipairs(rows) do if r.empty then row = r break end end
			if not row then
				for i = #rows, 1, -1 do if rows[i].name then row = rows[i] break end end
			end
		end
		if row then
			legsGoto(row.page)
			clearScratch()
			wait(0.1)
			typeXP(ident)
			wait(0.15)
			xpCommand("sim/FMS/ls_" .. row.key .. "l")
			wait(0.3)
			pickIfSelect(choice)
		elseif not routePageInsert(ident, choice) then
			-- show X-Plane's page so it is visible where it stopped
			msg("NO PLACE FOR " .. ident)
			S.page = "MIRROR"
			S.busy = nil
			return
		end
		xpCommand("sim/FMS/exec")
		wait(0.3)
		msg(planHas(ident) and (ident .. " ADDED") or (ident .. " NOT ACCEPTED"))
		S.busy = nil
	end)
end

legsDelete = function(ident)
	runJob(function()
		S.busy = "FPL"
		local row = findRow(legsScan(), ident)
		if not row then
			msg("NOT ON LEGS PAGE")
			S.page = "MIRROR"
			S.busy = nil
			return
		end
		legsGoto(row.page)
		clearScratch()
		wait(0.1)
		xpCommand("sim/FMS/key_delete")
		wait(0.1)
		xpCommand("sim/FMS/ls_" .. row.key .. "l")
		wait(0.3)
		xpCommand("sim/FMS/exec")
		wait(0.3)
		msg(planHas(ident) and (ident .. " NOT DELETED") or (ident .. " DELETED"))
		S.busy = nil
	end)
end

legsAltitude = function(ident, text)
	runJob(function()
		S.busy = "FPL"
		local row = findRow(legsScan(), ident)
		if not row then
			msg("NOT ON LEGS PAGE")
			S.page = "MIRROR"
			S.busy = nil
			return
		end
		legsGoto(row.page)
		clearScratch()
		wait(0.1)
		typeXP("/" .. text)
		wait(0.15)
		xpCommand("sim/FMS/ls_" .. row.key .. "r")
		wait(0.3)
		xpCommand("sim/FMS/exec")
		wait(0.3)
		msg(ident .. " ALT " .. text)
		S.busy = nil
	end)
end

-- DIRECT TO through X-Plane's own DIR INTC page ------------------------------
directIdent = function(ident)
	if not ident or ident == "" then return end
	runJob(function()
		S.busy = "DTO"
		-- the same keys as by hand on X-Plane's LEGS page:
		-- key beside the waypoint (copies it to the scratchpad), LEGS page 1,
		-- left key 1 (makes it the active waypoint), ENTER (EXEC)
		local row = findRow(legsScan(), ident)
		clearScratch()
		wait(0.1)
		if row then
			legsGoto(row.page)
			xpCommand("sim/FMS/ls_" .. row.key .. "l")
			wait(0.25)
		else
			typeXP(ident)          -- not on the LEGS pages: type the name instead
			wait(0.15)
		end
		legsGoto(1)
		xpCommand("sim/FMS/ls_1l")
		wait(0.3)
		pickIfSelect(1)
		xpCommand("sim/FMS/exec")
		wait(0.3)
		-- check: is the point now X-Plane's active waypoint?
		local plan, dest = readPlan()
		if plan[dest] and plan[dest].id == ident then
			msg("DIRECT TO " .. ident)
		else
			msg("DTO NOT ACCEPTED")
			S.page = "MIRROR"        -- show X-Plane's LEGS page as it is
		end
		S.busy = nil
	end)
end

directTo = function(pos)
	local plan = readPlan()
	local e = plan[pos]
	if not e then return end
	if e.type == NAV_LL or e.id == "" or string.find(e.id, "^%(") then
		-- points without a typable name (lat/lon, altitude points): make it the active leg
		setDest(pos)
		msg("ACTIVE " .. entryName(e))
		return
	end
	directIdent(e.id)
end

-- delete the whole flight plan (DELETE FPL, pressed twice as in the UNS manual)
local function deleteAll()
	local plan = readPlan()
	for k = #plan, 1, -1 do pcall(sasl.clearFMSEntry, fi(k)) end
	S.dto = nil
	S.origin = nil
	S.dest = nil
	S.fplSel = "new"
	S.fplPage = 1
	S.dtoPage = 1
	S.entry = ""
	S.userHold = nil
	msg("FPL DELETED")
end

-- SAVE FPL: the route as a standard X-Plane flight plan file (.fms, version 1100) in
-- X-Plane 12/Output/FMS plans/, named ORIGIN-DEST.fms. X-Plane lists these files on its
-- route menu (LOAD FPL), and other tools (SimBrief, Little Navmap ...) read them too.
-- The route is saved as its waypoints; SIDs / STARs / approaches are chosen again on
-- DEP/ARR after loading.
local function saveFlightPlan()
	local plan = readPlan()
	local pts = {}
	local depRwy = nil
	for i, e in ipairs(plan) do
		local id = e.id or ""
		if string.match(id, "^RW%d") then
			if i <= 2 then depRwy = id end
		elseif valid(e.lat, e.lon) and id ~= "" and not string.match(id, "^%(") then
			pts[#pts + 1] = e
		end
	end
	if #pts < 2 then msg("NO ROUTE TO SAVE") return end
	local first, last = pts[1], pts[#pts]
	local orig = (first.type == NAV_AIRPORT) and first.id or (S.origin or "")
	local dest = (last.type == NAV_AIRPORT) and last.id or (S.dest or "")
	local code = { [NAV_AIRPORT or 1] = 1, [NAV_NDB or 2] = 2, [NAV_VOR or 4] = 3, [NAV_FIX or 512] = 11, [NAV_LL] = 28 }
	local root = ""
	local okp, xp = pcall(sasl.getXPlanePath)
	if okp and type(xp) == "string" then root = xp end
	if root ~= "" and not string.match(root, "[/\\]$") then root = root .. "/" end
	-- AIRAC cycle (X-Plane requires "CYCLE nnnn" as the third line): from the navigation
	-- data X-Plane uses (Custom Data first, e.g. Navigraph), else the default data,
	-- else the cycle in force today
	local cycle = nil
	for _, fp in ipairs({ "Custom Data/cycle_info.txt", "Custom Data/earth_nav.dat",
			"Resources/default data/earth_nav.dat" }) do
		local f = io.open(root .. fp, "r")
		if f then
			local head = f:read(2000) or ""
			f:close()
			cycle = string.match(head, "[Cc]ycle%s*:?%s*(%d%d%d%d)")
				or string.match(head, "AIRAC[^%d]*(%d%d%d%d)")
			if cycle then break end
		end
	end
	if not cycle then
		-- AIRAC 2401 began on 25 January 2024; a cycle is 28 days, 13 cycles a year
		local days = math.floor((os.time() - os.time({ year = 2024, month = 1, day = 25, hour = 12 })) / 86400)
		local n = math.max(0, math.floor(days / 28))
		local yy, c = 24, 1 + n
		local y = 2024
		while true do
			local t0 = os.time({ year = y + 1, month = 1, day = 1, hour = 12 })
			-- cycles that start in year y: count from the first cycle date of the year
			local first = os.time({ year = 2024, month = 1, day = 25, hour = 12 }) + 0
			local startN = 0
			while first + startN * 28 * 86400 < os.time({ year = y, month = 1, day = 1, hour = 12 }) do startN = startN + 1 end
			local endN = startN
			while first + endN * 28 * 86400 < t0 do endN = endN + 1 end
			if n < endN then yy, c = y % 100, n - startN + 1 break end
			y = y + 1
		end
		cycle = string.format("%02d%02d", yy, c)
	end
	local out = { "I", "1100 Version", "CYCLE " .. cycle }
	if orig ~= "" then out[#out + 1] = "ADEP " .. orig end
	if depRwy and orig ~= "" then out[#out + 1] = "DEPRWY " .. depRwy end
	if dest ~= "" then out[#out + 1] = "ADES " .. dest end
	out[#out + 1] = "NUMENR " .. #pts
	for i, e in ipairs(pts) do
		local via = "DRCT"
		if i == 1 and e.type == NAV_AIRPORT then via = "ADEP" end
		if i == #pts and e.type == NAV_AIRPORT then via = "ADES" end
		local id = (e.type == NAV_LL) and string.format("%+.3f_%+.3f", e.lat, e.lon) or e.id
		out[#out + 1] = string.format("%d %s %s %.6f %.6f %.6f", code[e.type] or 11, id, via,
			(e.alt or 0), e.lat, e.lon)
	end
	local name = ((orig ~= "") and orig or "UNS") .. "-" .. ((dest ~= "") and dest or "FPL")
	local path = root .. "Output/FMS plans/" .. name .. ".fms"
	local f = io.open(path, "w")
	if not f then
		msg("SAVE FAILED")
		sasl.logWarning("UNS SAVE FPL: cannot write " .. path)
		return
	end
	f:write(table.concat(out, "\n") .. "\n")
	f:close()
	msg("SAVED " .. name)
end
core.saveFlightPlan = saveFlightPlan

P.FMENU = {}
function P.FMENU.build()
	put("T", 4, "FPL MENU", C.green)
	put("T", 15, "1/1", C.green)
	put("U1", 0, "ORIGIN", C.white, false)
	putR("U1", 23, "DEST", C.white, false)
	if S.busy then
		put("L1", 10, "WAIT", C.amber, true, nil)
		M[#M].dy = 0.012
	elseif S.entry ~= "" then
		entryBox("L1", 10, 4, S.entry)         -- typing: 4 letters, centred between ORIGIN and DEST
		M[#M].dy = 0.012
	end
	-- empty ORIGIN / DEST: white 4-letter fields, ">" at the left of the ORIGIN field,
	-- "<" at the right of the DEST field (pointing to their keys), a little below the labels
	if S.origin then put("L1", 0, S.origin, C.green) else put("L1", 0, ">   ", C.box, true, true) end
	M[#M].dy = 0.012
	if S.dest then putR("L1", 23, S.dest, C.green) else putR("L1", 23, "   <", C.box, true, true) end
	M[#M].dy = 0.012
	-- left keys 3..6, right keys 3, 4, 6 (keys 2 left empty)
	put("L3", 0, "←DEP/ARR SID/STAR", C.white)
	put("L4", 0, "←LOAD FPL", C.white)        -- X-Plane's route menu (its list of .fms plans)
	put("L5", 0, "←STORE FPL", C.white)       -- the UNS writes the route as a .fms plan
	-- DELETE FPL: press twice (the second press confirms), as in the UNS manual
	if S.delFplArmed then
		put("L6", 0, "←CONFIRM DELETE", C.amber)
	else
		put("L6", 0, "←DELETE FPL", C.white)
	end
	putR("L4", 23, "FIX→", C.white)
	putR("L6", 23, "RTN→", C.white)
end
function P.FMENU.key(k)
	if S.busy then return end
	if k == "L6" then
		if S.delFplArmed then
			S.delFplArmed = false
			deleteAll()
		else
			S.delFplArmed = true
		end
		return
	end
	S.delFplArmed = false
	if k == "L1" or k == "R1" then
		local which = (k == "L1") and "ORIGIN" or "DEST"
		if string.match(S.entry, "^%w%w%w%w?$") then
			setAirport(which, S.entry)
			S.entry = ""
		else
			msg("TYPE ICAO, THEN KEY")
		end
	elseif k == "L3" then
		xpCommand("sim/FMS/dep_arr")
		S.page = "MIRROR"
	elseif k == "R6" then
		xpCommand("sim/FMS/legs")
		S.page = "MIRROR"
	elseif k == "R4" then
		xpCommand("sim/FMS/fix")
		S.page = "MIRROR"
	elseif k == "L4" then
		-- LOAD FPL: straight to X-Plane's CO ROUTE LIST (the stored .fms plans).
		-- X-Plane gets there by FPLN -> ROUTE MENU -> CO ROUTE LIST (or INDEX ->
		-- ROUTE MENU): the keys are pressed in turn until the list is shown.
		S.page = "MIRROR"
		S.busy = "PAGE"
		runJob(function()
			local function press(word)
				local nk, ns = findWord(cduLines(), word)
				if not nk then return false end
				xpCommand("sim/FMS/ls_" .. nk .. ns)
				wait(0.3)
				return true
			end
			xpCommand("sim/FMS/fpln")
			wait(0.3)
			local done = press("CO ROUTE")
			if not done and press("ROUTE MENU") then done = press("CO ROUTE") end
			if not done then
				xpCommand("sim/FMS/index")
				wait(0.3)
				if press("ROUTE MENU") then done = press("CO ROUTE") end
			end
			if not done then msg("CO ROUTE LIST NOT FOUND") end
			S.busy = nil
		end)
	elseif k == "L5" then
		saveFlightPlan()
	elseif k == "BACK" then
		S.entry = string.sub(S.entry, 1, -2)
	elseif k == "DEL" then
		S.entry = ""
	end
end

-- NAV page: the TO line key opens X-Plane's DIR INTC page
function P.NAV.key(k)
	if k == "L2" then
		xpCommand("sim/FMS/dir_intc")
		S.page = "MIRROR"
	elseif k == "R1" then
		msg("HDG NOT AVAILABLE")       -- heading is selected on the Tu-154M autopilot panel
	elseif k == "R2" then
		msg("KEY INOPERATIVE")          -- MNVR menu not simulated
	end
end

-------------------------------------------------------------------------------
local utcDate, utcTime     -- (defined with the POS INIT page)

-------------------------------------------------------------------------------
-- UNS pages of their own, laid out like the UNS-1 (JustFlight UNS-1 manual):
-- PATH VNAV, PERF, TUNE and DATA. Everything shown comes from X-Plane: the flight
-- plan (legacy FMS entries) and the aircraft datarefs - nothing is made up.
-------------------------------------------------------------------------------
local function ffKgH()                      -- total fuel flow, kg/h
	local s = 0
	for i = 1, #DX.ff do s = s + (val(DX.ff[i], 0) or 0) end
	return s * 3600
end
local function hhmm(minutes, sep)           -- 75 -> "01:15" (sep ":") or "01+15"
	if not minutes or minutes < 0 or minutes ~= minutes or minutes > 5999 then return nil end
	local m = math.floor(minutes + 0.5)
	return string.format("%02d%s%02d", math.floor(m / 60), sep or ":", m % 60)
end
local function usable(e) return e and e.id ~= "" and valid(e.lat, e.lon) end

-- route distance (nm) from the aircraft along the flight plan: to point k (k >= dest)
-- and to the last point of the plan
local function routeDist(plan, dest, k)
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	local d, pla, plo = 0, la, lo
	for i = dest, k do
		local e = plan[i]
		if usable(e) then
			d = d + gc(pla, plo, e.lat, e.lon)
			pla, plo = e.lat, e.lon
		end
	end
	return d
end


-- PATH VNAV ------------------------------------------------------------------
-- TO = first waypoint ahead with an altitude in the flight plan, NX = the next ones.
-- TGT V/S (right key 1): planned descent rate; then TO TOD (distance to the top of
-- descent) and the angle are shown. FR PPOS: distance to TO and the vertical speed
-- needed now to be at its altitude there.
local function vnavPoints(plan, dest)
	local t = {}
	for i = math.max(1, dest), #plan do
		local e = plan[i]
		if usable(e) and (e.alt or 0) > 0 then t[#t + 1] = i end
	end
	return t
end
local function fmtFt(a) return string.format("%d", math.floor(a + 0.5)) end

-- VNAV key: page 1 = this UNS PATH VNAV page; pages 2/3/4 = X-Plane's own CLB, CRZ
-- and DES pages (CRZ ALT and the other X-Plane values are entered there, on
-- X-Plane's own fields). NEXT / PREV move through the four pages.
-- page sets: page 1 = the UNS page, the next pages = X-Plane's own pages behind it
-- (a command, or the name of the item to pick on X-Plane's INIT/REF INDEX)
local SETS = {
	VNAV = { own = "VNAV", n = 4, xp = { [2] = "sim/FMS/clb", [3] = "sim/FMS/crz", [4] = "sim/FMS/des" } },
	PERF = { own = "PERF", n = 2, xp = { [2] = "sim/FMS/prog" } },
}
core.SETS = SETS

-- PATH VNAV can run over several pages: page 1 = FR / TO and 4 NX points, then 5 NX
-- points a page (rows 2..6), until the end of the plan; X-Plane's CLB / CRZ / DES follow them.
core.VNAV_P1, core.VNAV_PN = 5, 5
core.vnavPtCount = function(n) return 1 + math.ceil(math.max(0, n - core.VNAV_P1) / core.VNAV_PN) end
core.vnavPtPages = function()
	local plan, dest = readPlan()
	return core.vnavPtCount(#vnavPoints(plan, dest))
end

P.VNAV = {}
function P.VNAV.build()
	local plan, dest = readPlan()
	local pts = vnavPoints(plan, dest)
	local np = core.vnavPtCount(#pts)
	S.vnavPt = math.max(1, math.min(S.vnavPt or 1, np))
	put("T", 5, "PATH VNAV", C.green)
	put("T", 16, S.vnavPt .. "/" .. (np + 3), C.green)
	local altCol = 16                       -- altitudes end in this column
	putLine(17.2, ROWF.L1 - 0.045, 17.2, ROWF.L6 + 0.03, C.amber)
	if S.vnavPt > 1 then
		-- continuation page: the next points of the plan with their altitudes
		putFrame("L1", altCol - 2, "H", C.green)     -- as on page 1
		local first = core.VNAV_P1 + (S.vnavPt - 2) * core.VNAV_PN
		for r = 1, core.VNAV_PN do
			local i = pts[first + r]
			if i then
				local row = "L" .. (r + 1)        -- rows 2..6, as the points on page 1
				if r == 1 then put(row, 0, "NX", C.white, false) end
				put(row, 3, usub(entryName(plan[i]), 8), C.green)
				putR(row, altCol, fmtFt(plan[i].alt), C.green)
			end
		end
		return
	end
	if S.entry ~= "" and S.vnavField ~= "TGT" then
		put("B", 0, S.entry .. string.rep(" ", math.max(0, 6 - ulen(S.entry))), C.box, true, true)
	end
	local gs = val(dr_gs, 0) * 1.943844
	local alt = val(DX.elev, 0) * 3.28084
	local tgt = S.tgtVS
	putR("U1", 23, "TGT V/S", C.white, false)
	if S.vnavField == "TGT" then
		local t = (S.entry ~= "") and ("-" .. S.entry) or "-----"
		putR("L1", 23, t .. string.rep(" ", math.max(0, 5 - ulen(t))), C.box, true, true)
	else
		putR("L1", 23, tgt and string.format("%d", tgt) or "-----", C.green)
		M[#M].edit = true                       -- TGT V/S takes an entry
	end
	if tgt and gs > 30 then
		putR("D1", 23, string.format("%.1f°", math.deg(math.atan(-tgt / (gs * 101.27)))), C.green, false)
	else
		putR("D1", 23, "-.-", C.green, false)
	end
	put("L1", 0, "FR", C.white, false)
	put("L1", 3, "PPOS", C.green)
	putFrame("L1", altCol - 2, "H", C.green)
	local to = pts[1] and plan[pts[1]]
	put("L2", 0, "TO", C.white, false)
	if to then
		put("L2", 3, usub(entryName(to), 8), C.green)
		putR("L2", altCol, fmtFt(to.alt), C.green)
		local d = routeDist(plan, dest, pts[1])
		put("D1", 3, fmtDist(d) .. "NM", C.green, false)
		if gs > 30 and d > 0.1 then
			local need = -(alt - to.alt) / (d / gs * 60)
			putR("D1", altCol, string.format("%d", math.floor(need / 10 + 0.5) * 10), C.green, false)
			-- top of descent for the target vertical speed (only before it is reached)
			if tgt and tgt < 0 and alt > to.alt then
				local tod = d - (alt - to.alt) / (-tgt) * gs / 60
				if tod > 0.05 then
					put("U1", 0, "TO TOD", C.white, false)
					put("U1", 7, fmtDist(tod) .. "NM", C.green, false)
				end
			end
		else
			putR("D1", altCol, "----", C.green, false)
		end
	else
		put("L2", 3, "-----", C.green)
		putR("L2", altCol, "-----", C.green)
	end
	put("L3", 0, "NX", C.white, false)
	for r = 1, 4 do
		local i = pts[1 + r]
		local row = "L" .. (2 + r)
		if i then
			put(row, 3, usub(entryName(plan[i]), 8), C.green)
			putR(row, altCol, fmtFt(plan[i].alt), C.green)
		elseif r == 1 then
			put(row, 3, "-----", C.green)
			putR(row, altCol, "-----", C.green)
		end
	end
end

-- open page n of a page set (VNAV: 1 = PATH VNAV, 2..4 = X-Plane CLB / CRZ / DES;
-- PERF: 1 = UNS PERF, 2 = X-Plane PROGRESS; X-Plane 12 has no PERF INIT page)
local function setGoto(set, n, fromPrev)
	local st = SETS[set]
	if n < 1 then n = st.n elseif n > st.n then n = 1 end
	if set == "VNAV" and n == 1 then S.vnavPt = fromPrev and 99 or 1 end
	S.vnavField = nil
	S.entry = ""
	if n == 1 then
		S.vnavMirror = nil
		S.pageSet = nil
		S.page = st.own
		return
	end
	local how = st.xp[n]
	S.vnavMirror = n
	S.pageSet = set
	S.page = "MIRROR"
	if string.sub(how, 1, 4) == "sim/" then
		xpCommand(how)
	else
		S.busy = "PAGE"
		runJob(function()
			xpCommand("sim/FMS/index")
			wait(0.3)
			local L = cduLines()
			local k, side = findWord(L, how)
			if not k then k, side = findWord(L, (string.match(how, "^(%S+)"))) end
			if k then xpCommand("sim/FMS/ls_" .. k .. side) else msg(how .. " NOT FOUND") end
			wait(0.2)
			S.busy = nil
		end)
	end
end
core.setGoto = setGoto

function P.VNAV.key(k)
	-- TGT V/S (right key 1): type the descent rate and press right key 1 or ENTER;
	-- or press right key 1 first (cursor box), type, ENTER
	local function commit()
		if S.entry == "" then return end
		local v = tonumber(S.entry)
		if v and v >= 100 and v <= 6000 then
			S.tgtVS = -math.floor(v + 0.5)       -- descent rate, shown negative
		else
			msg("V/S 100 TO 6000")
		end
		S.entry = ""
		S.vnavField = nil
	end
	if k == "R1" and (S.vnavPt or 1) > 1 then
		return
	elseif k == "R1" then
		if S.entry ~= "" then
			commit()
		else
			S.vnavField = (S.vnavField == "TGT") and nil or "TGT"
		end
	elseif k == "ENTER" then
		commit()
	elseif k == "DEL" then
		if S.entry ~= "" then
			S.entry = ""
		else
			S.tgtVS = nil
			S.vnavField = nil
		end
	elseif k == "BACK" then
		if S.entry ~= "" then S.entry = string.sub(S.entry, 1, -2) else S.vnavField = nil end
	elseif k == "NEXT" then
		if (S.vnavPt or 1) < core.vnavPtPages() then
			S.vnavPt = (S.vnavPt or 1) + 1
			S.vnavField = nil
			S.entry = ""
		else
			setGoto("VNAV", 2)
		end
	elseif k == "PREV" then
		if (S.vnavPt or 1) > 1 then
			S.vnavPt = S.vnavPt - 1
			S.vnavField = nil
			S.entry = ""
		else
			setGoto("VNAV", 4)
		end
	end
end

-- PERF -----------------------------------------------------------------------
-- like the UNS-1 PERF page: GS, head/tailwind, ESAD, TEMP, DIST, ETE, ground/air
-- NM per kg, ETA (local), and NOW / at the destination (OVHD): weight, fuel on
-- board, endurance and range - from X-Plane's weights, fuel flow and the route.
P.PERF = {}
function P.PERF.build()
	local plan, dest = readPlan()
	local n = #plan
	local gs = val(dr_gs, 0) * 1.943844
	local tas = val(DX.tas, 0) * 1.943844
	local trk = wrap360(val(dr_hpath, 0) + magOff())
	local wd, ws = val(dr_wdir, 0), val(dr_wspd, 0)
	local hw = ws * math.cos(math.rad(wd - trk))
	local ff = ffKgH()
	local wt, fuel = val(DX.wt, 0), val(DX.fuel, 0)
	local flying = gs > 30
	local burning = ff > 50
	local dist = (n > 0 and dest >= 1) and routeDist(plan, dest, n) or nil
	local ete = (dist and flying) and (dist / gs * 60) or nil

	put("T", 6, "PERF", C.green)
	put("T", 13, "1/2", C.green)
	local W, G = C.white, C.green
	-- GS / HEADWIND
	put("U1", 0, "GS", W, false)
	putR("U1", 7, flying and string.format("%d", math.floor(gs + 0.5)) or "---", G, false)
	put("U1", 10, hw >= 0 and "HEADWIND" or "TAILWIND", W, false)
	putR("U1", 23, string.format("%d", math.floor(math.abs(hw) + 0.5)), G, false)
	-- ESAD / TEMP
	put("L1", 0, "ESAD", W, false)
	putR("L1", 7, (dist and flying and tas > 30) and string.format("%d", math.floor(dist * tas / gs + 0.5)) or "---", G, false)
	put("L1", 10, "TEMP", W, false)
	putR("L1", 23, string.format("%d", math.floor(val(DX.oat, 0) + 0.5)), G, false)
	-- DIST / GND NM/KG
	put("U2", 0, "DIST", W, false)
	putR("U2", 7, dist and string.format("%d", math.floor(dist + 0.5)) or "---", G, false)
	put("U2", 10, "GND", W, false)
	put("U2", 14, "NM/KG", G, false)
	putR("U2", 23, (flying and burning) and string.format("%.2f", gs / ff) or "---", G, false)
	-- ETE / AIR NM/KG
	put("L2", 0, "ETE", W, false)
	putR("L2", 8, hhmm(ete) or "--:--", G, false)
	put("L2", 10, "AIR", W, false)
	put("L2", 14, "NM/KG", G, false)
	putR("L2", 23, (tas > 30 and burning) and string.format("%.2f", tas / ff) or "---", G, false)
	-- ETA (local)
	put("U3", 4, "ETA", W, false)
	local eta = nil
	if ete then eta = hhmm(((val(dr_ltime, 0) / 60) + ete) % 1440) end
	put("U3", 8, eta or "--:--", G, false)
	put("U3", 15, "LCL", W, false)
	-- NOW / OVHD (destination)
	put("L3", 2, "NOW", W, false)
	put("L3", 13, "OVHD", W, false)
	putR("L3", 23, (n > 0) and usub(entryName(plan[n]), 6) or "----", G, false)
	local endur = burning and (fuel / ff * 60) or nil
	local burn = (ete and burning) and (ff * ete / 60) or nil
	local fuelD = burn and (fuel - burn) or nil
	local endurD = (fuelD and burning) and (math.max(0, fuelD) / ff * 60) or nil
	local function kg(v) return v and string.format("%d", math.floor(v + 0.5)) or "-----" end
	local function rng(m) return (m and flying) and string.format("%.1f", m / 60 * gs) or "-----" end
	putR("U4", 5, kg(wt), G, false)
	put("U4", 7, "WT", W, false)
	put("U4", 15, "WT", W, false)
	putR("U4", 23, kg(burn and (wt - burn)), G, false)
	putR("L4", 5, kg(fuel), G, false)
	put("L4", 7, "FUEL ONBRD", W, false)
	putR("L4", 23, kg(fuelD), G, false)
	putR("U5", 5, hhmm(endur, "+") or "--+--", G, false)
	put("U5", 7, "ENDURANCE", W, false)
	putR("U5", 23, hhmm(endurD, "+") or "--+--", G, false)
	putR("L5", 5, rng(endur), G, false)
	put("L5", 7, "RANGE", W, false)
	putR("L5", 23, rng(endurD), G, false)
end

-- PERF keys: NEXT / PREV to X-Plane's PERF INIT and PROGRESS pages (their values are
-- entered there, on X-Plane's own fields)
function P.PERF.key(k)
	if k == "NEXT" or k == "PREV" then setGoto("PERF", 2) end
end

-- TUNE -----------------------------------------------------------------------
-- the radios are tuned on the Tu-154 radio panels (as on the JustFlight UNS-1, where
-- TUNE is not used for tuning); the page shows what they are set to
P.TUNE = {}
function P.TUNE.build()
	put("T", 7, "TUNE", C.green)
	put("T", 13, "1/1", C.green)
	local function khz3(p) local v = val(p, 0) return v > 0 and string.format("%.3f", v / 1000) or "---.---" end
	local function nav(p) local v = val(p, 0) return v > 0 and string.format("%.2f", v / 100) or "---.--" end
	local function adf(p) local v = val(p, 0) return v > 0 and string.format("%d", v) or "----" end
	put("U1", 0, "COM1", C.white, false)
	putR("U1", 23, "NAV1", C.white, false)
	put("L1", 0, khz3(DX.com1), C.green)
	putR("L1", 23, nav(DX.nav1), C.green)
	put("U2", 0, "COM2", C.white, false)
	putR("U2", 23, "NAV2", C.white, false)
	put("L2", 0, khz3(DX.com2), C.green)
	putR("L2", 23, nav(DX.nav2), C.green)
	put("U3", 0, "ADF1", C.white, false)
	putR("U3", 23, "ADF2", C.white, false)
	put("L3", 0, adf(DX.adf1), C.green)
	putR("L3", 23, adf(DX.adf2), C.green)
	put("U4", 0, "ATC1", C.white, false)
	put("L4", 0, string.format("%04d", math.floor(val(DX.xpdr, 0))), C.green)
end

-- DATA -----------------------------------------------------------------------
-- 1/2: date, times, aircraft position (GPS), track and ground speed, FMC version
-- 2/2: NAV DATA - type an identifier, left key 1 (or ENTER): the nearest navaid,
--      fix or airport of that name from X-Plane's database
P.DATA = {}
function P.DATA.build()
	S.dataPage = (S.dataPage == 2) and 2 or 1
	put("T", 7, "DATA", C.green)
	put("T", 13, S.dataPage .. "/2", C.green)
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	if S.dataPage == 1 then
		put("U1", 0, "DATE", C.white, false)
		putR("U1", 23, "UTC", C.white, false)
		put("L1", 0, utcDate(), C.green)
		putR("L1", 23, string.sub(utcTime(), 1, 5), C.green)
		putR("U2", 23, "LCL", C.white, false)
		local lt = math.floor(val(dr_ltime, 0)) % 86400
		putR("L2", 23, string.format("%02d:%02d", math.floor(lt / 3600), math.floor(lt / 60) % 60), C.green)
		put("U3", 0, "PPOS (GPS)", C.white, false)
		put("L3", 0, fmtLat(la), C.green)
		put("L4", 0, fmtLon(lo), C.green)
		local gs = val(dr_gs, 0) * 1.943844
		put("U5", 0, "TRK", C.white, false)
		putR("U5", 23, "GS", C.white, false)
		put("L5", 0, fmtDeg(wrap360(val(dr_hpath, 0) + magOff())), C.green)
		putR("L5", 23, string.format("%d", math.floor(gs + 0.5)), C.green)
		put("L6", 0, "FMC VER", C.white, false)
		put("L6", 8, "T5M", C.green)
		putR("L6", 23, "NAV DATA→", C.white)
	else
		put("U1", 0, "NAV DATA", C.white, false)
		if S.entry ~= "" then
			entryBox("L1", 0, 6, S.entry)
		else
			put("L1", 0, (S.dataHit and S.dataHit.id) or "-----", C.green)
		end
		local h = S.dataHit
		if h then
			local kinds = { ARPT = "AIRPORT", VOR = "VOR", NDB = "NDB", INT = "WAYPOINT", LL = "LAT/LON" }
			putR("U1", 23, kinds[h.kind] or h.kind or "", C.white, false)
			put("U2", 0, "NAME", C.white, false)
			put("L2", 0, usub(string.upper(h.name or ""), 24), C.green, false)
			put("U3", 0, "POS", C.white, false)
			put("L3", 0, fmtLat(h.lat), C.green)
			put("L4", 0, fmtLon(h.lon), C.green)
			if (h.kind == "VOR" or h.kind == "NDB") and h.freq and h.freq > 0 then
				putR("U3", 23, "FREQ", C.white, false)
				putR("L3", 23, h.kind == "VOR" and string.format("%.2f", h.freq / 100) or string.format("%d", h.freq), C.green)
			end
			local d, b = gc(la, lo, h.lat, h.lon)
			put("U5", 0, "BRG", C.white, false)
			putR("U5", 23, "DIS", C.white, false)
			put("L5", 0, fmtDeg(b + magOff()), C.green)
			putR("L5", 23, fmtDist(d) .. "NM", C.green)
			if (S.dataHits or 0) > 1 then put("U6", 0, string.format("%d MORE WITH THIS NAME", S.dataHits - 1), C.white, false) end
		else
			put("U2", 0, "TYPE IDENT, THEN KEY", C.white, false)
		end
		putR("L6", 23, "RTN→", C.white)
	end
end
function P.DATA.key(k)
	if S.dataPage ~= 2 then
		if k == "R6" or k == "NEXT" or k == "PREV" then S.dataPage = 2 end
		return
	end
	if k == "L1" or (k == "ENTER" and S.entry ~= "") then
		if S.entry ~= "" then
			local c = lookup(S.entry, val(dr_lat, 0), val(dr_lon, 0))
			if #c == 0 then
				msg("NOT IN DATABASE")
			else
				S.dataHit, S.dataHits = c[1], #c
			end
			S.entry = ""
		end
	elseif k == "DEL" then
		if S.entry ~= "" then S.entry = "" else S.dataHit = nil end
	elseif k == "BACK" then
		S.entry = string.sub(S.entry, 1, -2)
	elseif k == "R6" or k == "NEXT" or k == "PREV" then
		S.dataPage = 1
		S.entry = ""
	end
end
do
-- LIST -----------------------------------------------------------------------
-- as on the UNS-1: the nearest VORs (first), airports, NDBs and intersections from
-- X-Plane's navigation database, or the flight plan's own points, numbered and
-- ordered by distance. Type the number (# field), ENTER: the identifier goes to the
-- page LIST was called from (its typing field), ready for that page's key.
local LIST_ROWS, LIST_MAX = 7, 70
local LISTC = {}                 -- [kind] = { lat, lon, t, items = { {id, lat, lon, d} } }
local listScan = nil             -- background scan (coroutine), one list at a time
local LIST_KINDS = {
	VOR = { NAV_VOR, "VORS" }, APT = { NAV_AIRPORT, "AIRPORTS" }, NDB = { NAV_NDB, "NDBS" },
	INT = { NAV_FIX, "INTERSECTIONS" },
}
local function listStart(kind)
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	local c = LISTC[kind]
	if c and (c.scanning or (gc(la, lo, c.lat, c.lon) < 10 and now() - c.t < 120)) then return end
	if listScan then return end
	local tp = LIST_KINDS[kind][1]
	LISTC[kind] = { lat = la, lon = lo, t = now(), items = (c and c.items) or {}, scanning = true }
	listScan = coroutine.create(function()
		local items = {}
		local okA, first = pcall(sasl.findFirstNavAidOfType, tp)
		local okB, last = pcall(sasl.findLastNavAidOfType, tp)
		if okA and okB and type(first) == "number" and type(last) == "number" and first >= 0 and last >= first then
			local coslat = math.cos(math.rad(la))
			local worst = math.huge
			local n = 0
			for ref = first, last do
				local ok, t, nla, nlo, _, _, _, id = pcall(sasl.getNavAidInfo, ref)
				if ok and t == tp and nla and nlo then
					local dy, dx = nla - la, (nlo - lo) * coslat
					if dx > 180 then dx = dx - 360 elseif dx < -180 then dx = dx + 360 end
					local d2 = dy * dy + dx * dx
					if #items < LIST_MAX or d2 < worst then
						items[#items + 1] = { id = id or "", lat = nla, lon = nlo, d2 = d2 }
						if #items > LIST_MAX * 2 then
							table.sort(items, function(a, b) return a.d2 < b.d2 end)
							for i = #items, LIST_MAX + 1, -1 do items[i] = nil end
							worst = items[#items].d2
						end
					end
				end
				n = n + 1
				if n % 2500 == 0 then coroutine.yield() end
			end
		end
		table.sort(items, function(a, b) return a.d2 < b.d2 end)
		for i = #items, LIST_MAX + 1, -1 do items[i] = nil end
		LISTC[kind] = { lat = la, lon = lo, t = now(), items = items }
	end)
end
local function listStep()
	if not listScan then return end
	local ok, err = coroutine.resume(listScan)
	if not ok then
		sasl.logWarning("UNS LIST: " .. tostring(err))
		listScan = nil
		for _, c in pairs(LISTC) do c.scanning = nil end
	elseif coroutine.status(listScan) == "dead" then
		listScan = nil
		dirtySoon()
	end
end
core.listStep = listStep

-- the items of a list kind ("FPLAN" = the flight plan's points)
local function listItems(kind)
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	if kind == "FPLAN" then
		local plan = readPlan()
		local t = {}
		for _, e in ipairs(plan) do
			if usable(e) then t[#t + 1] = { id = entryName(e), lat = e.lat, lon = e.lon } end
		end
		return t, false
	end
	listStart(kind)
	local c = LISTC[kind]
	return (c and c.items) or {}, c and c.scanning
end

P.LIST = {}
function P.LIST.build()
	local kind = S.listKind or "VOR"
	local items, busy = listItems(kind)
	local pages = math.max(1, math.min(10, math.ceil(#items / LIST_ROWS)))
	S.listPage = math.max(1, math.min(S.listPage or 1, pages))
	put("T", 7, "LIST", C.green)
	put("T", 13, S.listPage .. "/" .. pages, C.green)
	-- the list in its frame (columns 6..19)
	local x1, x2 = 5.6, 19.4
	local y1, y2 = ROWF.L1 - 0.05, ROWF.U5 + 0.05
	putLine(x1, y1, x2, y1, C.white)
	putLine(x1, y2, x2, y2, C.white)
	putLine(x1, y1, x1, y2, C.white)
	putLine(x2, y1, x2, y2, C.white)
	local head = (kind == "FPLAN") and "FPLAN" or LIST_KINDS[kind][2]
	put("L1", 6, usub(head, 9), C.white, false)
	put("L1", 15, "#", C.amber)
	local e = (S.entry ~= "") and S.entry or ""
	put("L1", 16, e .. string.rep(" ", math.max(0, 2 - ulen(e))), C.box, true, true)
	local rows = { "U2", "L2", "U3", "L3", "U4", "L4", "U5" }
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	local first = (S.listPage - 1) * LIST_ROWS
	if #items == 0 then
		put("L3", 7, busy and "SEARCHING" or "NONE", busy and C.amber or C.green, false)
	end
	for r = 1, LIST_ROWS do
		local it = items[first + r]
		if it then
			local row = rows[r]
			putR(row, 7, string.format("%d", first + r), C.white, false)
			put(row, 9, usub(it.id, 6), C.green, false)
			putR(row, 18, string.format("%d", math.floor(gc(la, lo, it.lat, it.lon) + 0.5)), C.green, false)
		end
	end
	-- list kinds (left), VOR and airways (right), return
	put("L1", 0, "←APT", C.white)
	put("L2", 0, "←NDB", C.white)
	put("L3", 0, "←INT", C.white)
	put("L4", 0, "←FPL", C.white)
	putR("L1", 23, "VOR→", C.white)
	putR("L2", 23, "AWY→", C.cyan)        -- airways: not available from X-Plane's database here
	putR("L6", 23, "RTN→", C.white)
end

-- the chosen identifier goes back to the page LIST was called from:
--   FPL MENU: its typing field (ORIGIN / DEST);  DATA: shown on NAV DATA (2/2);
--   X-Plane pages (FPL, DTO, HOLD FIX ...): X-Plane's scratchpad, ready for a line key;
--   pages without a waypoint field: the FPL page, with the identifier ready to insert
local function listChoose(id)
	local back = S.listBack or "FPL"
	S.entry = ""
	if back == "FMENU" then
		S.page = back
		S.entry = usub(id, 4)
	elseif back == "DATA" then
		S.page = "DATA"
		S.dataPage = 2
		local c = lookup(id, val(dr_lat, 0), val(dr_lon, 0))
		if #c > 0 then S.dataHit, S.dataHits = c[1], #c else msg("NOT IN DATABASE") end
	else
		local toFpl = (back ~= "MIRROR")
		S.page = "MIRROR"
		runJob(function()
			if toFpl then
				xpCommand("sim/FMS/legs")
				wait(0.2)
			end
			clearScratchSafe()
			typeXP(id)
		end)
	end
end
P.LIST.choose = listChoose

function P.LIST.key(k)
	local kinds = { L1 = "APT", L2 = "NDB", L3 = "INT", L4 = "FPLAN", R1 = "VOR" }
	if kinds[k] then
		S.listKind = kinds[k]
		S.listPage = 1
		S.entry = ""
	elseif k == "R2" then
		msg("AIRWAYS NOT AVAILABLE")
	elseif k == "R6" then
		S.page = S.listBack or "FPL"
		S.entry = ""
	elseif k == "ENTER" then
		local n = tonumber(S.entry)
		local items = listItems(S.listKind or "VOR")
		if n and items[n] then
			listChoose(items[n].id)
		else
			msg("INVALID ENTRY")
			S.entry = ""
		end
	elseif k == "BACK" then
		S.entry = string.sub(S.entry, 1, -2)
	elseif k == "DEL" then
		S.entry = ""
	elseif k == "NEXT" then
		S.listPage = (S.listPage or 1) + 1
	elseif k == "PREV" then
		S.listPage = math.max(1, (S.listPage or 1) - 1)
	end
end

end

core.OWN_PAGES = { VNAV = true, PERF = true, TUNE = true, DATA = true, LIST = true }

-- UNS FPL / DTO actions on X-Plane's own pages ------------------------------
-- (key sequences seen on X-Plane 12: on LEGS a line key copies the point to the
--  scratchpad; direct-to is X-Plane's DIR INTC page, "←NAME" lines on left keys)
-- EXEC when X-Plane has a change waiting (EXEC light, or MOD in the page title)
local function execIfMod()
	local _, _, _, mod = pageInfo()
	if mod or val(dr_exec, 0) == 1 then
		xpCommand("sim/FMS/exec")
		wait(0.3)
	end
end

-- DEL on LEGS
--  waypoint:       DEL key, key beside the point, check X-Plane's answer, EXEC
--  discontinuity:  the FMS way - copy the next waypoint, put it into the gap's line, EXEC
local function rowIsGap(L, k)
	local txt = (L[2 * k] or "") .. " " .. (L[2 * k - 1] or "")
	return string.find(txt, BOX_A, 1, true) ~= nil or string.find(txt, BOX_B, 1, true) ~= nil
		or string.find(txt, "DISCONTINUITY", 1, true) ~= nil or string.find(txt, "THEN", 1, true) ~= nil
end
local function scratchRefused()
	local sp = string.upper(scratchText())
	return string.find(sp, "INVALID", 1, true) ~= nil or string.find(sp, "NOT ", 1, true) ~= nil
		or string.find(sp, "INOP", 1, true) ~= nil
end
legsDeleteRow = function(k)
	runJob(function()
		S.busy = "FPL"
		local L = cduLines()
		local nm = legsRowName(k) or "POINT"
		clearScratch()
		wait(0.1)
		if rowIsGap(L, k) then
			-- next real waypoint after the gap: on this page, else first line of the next page
			local nextK
			for j = k + 1, 5 do
				local n = legsRowName(j)
				if n and not rowIsGap(L, j) then nextK = j break end
			end
			if nextK then
				xpCommand("sim/FMS/ls_" .. nextK .. "l")       -- copy it to the scratchpad
				wait(0.25)
			else
				xpCommand("sim/FMS/next")
				wait(0.25)
				xpCommand("sim/FMS/ls_1l")
				wait(0.25)
				xpCommand("sim/FMS/prev")
				wait(0.25)
			end
			xpCommand("sim/FMS/ls_" .. k .. "l")               -- into the gap's line
			wait(0.3)
			if scratchRefused() then
				clearScratch()
				msg("CANNOT CLOSE GAP")
			else
				execIfMod()
				if rowIsGap(cduLines(), k) then
					clearScratch()
					msg("CANNOT CLOSE GAP")
				else
					msg("DISCONTINUITY CLOSED")
				end
			end
		else
			xpCommand("sim/FMS/key_delete")
			wait(0.15)
			xpCommand("sim/FMS/ls_" .. k .. "l")
			wait(0.3)
			if scratchRefused() then
				clearScratch()
				msg("CANNOT DELETE " .. nm)
			else
				execIfMod()
				if legsRowName(k) == nm then
					clearScratch()
					msg("CANNOT DELETE " .. nm)
				else
					msg(nm .. " DELETED")
				end
			end
		end
		S.busy = nil
	end)
end

-- press a DIR INTC list key, EXEC if X-Plane asks
dirPickRow = function(k)
	runJob(function()
		S.busy = "DTO"
		local L = cduLines()
		local nm = string.match(L[2 * k] or "", "^%s*[<←]?%s*(%S+)") or ""
		xpCommand("sim/FMS/ls_" .. k .. "l")
		wait(0.3)
		if scratchRefused() then
			clearScratch()
			msg("DTO NOT ACCEPTED")
		else
			execIfMod()
			xpCommand("sim/FMS/legs")      -- the change shows as MOD on LEGS: EXEC there too
			wait(0.25)
			execIfMod()
			local plan, dest = readPlan()
			if plan[dest] and (string.gsub(plan[dest].id, "@$", "")) == (string.gsub(nm, "@$", "")) then
				msg("DIRECT TO " .. nm)
			else
				msg("DTO NOT ACCEPTED")
			end
		end
		S.busy = nil
	end)
end

-- DTO→ from FPL: open DIR INTC, press the key beside that point, EXEC, back to FPL
directByDirPage = function(name)
	runJob(function()
		S.busy = "DTO"
		xpCommand("sim/FMS/dir_intc")
		wait(0.3)
		local found
		for pg = 1, 6 do
			local L = cduLines()
			for k = 1, 5 do
				local n = string.match(L[2 * k] or "", "^%s*[<←]?%s*(%S+)")
				if n and (string.gsub(n, "@$", "")) == name then found = k break end
			end
			if found then break end
			local cur, tot = string.match(L[0] or "", "(%d+)%s*/%s*(%d+)")
			if not cur or tonumber(cur) >= tonumber(tot) then break end
			xpCommand("sim/FMS/next")
			wait(0.25)
		end
		if not found then
			msg(name .. " NOT ON DTO PAGE")
			xpCommand("sim/FMS/legs")          -- back to the flight plan, not X-Plane's last DTO page
			S.page = "MIRROR"
			S.busy = nil
			return
		end
		xpCommand("sim/FMS/ls_" .. found .. "l")
		wait(0.3)
		local refused = scratchRefused()
		if refused then clearScratch() else execIfMod() end
		xpCommand("sim/FMS/legs")
		wait(0.25)
		if not refused then execIfMod() end
		local plan, dest = readPlan()
		if not refused and plan[dest] and (string.gsub(plan[dest].id, "@$", "")) == name then
			msg("DIRECT TO " .. name)
		else
			msg("DTO NOT ACCEPTED")
		end
		S.busy = nil
	end)
end

-- HOLD at a fix: X-Plane's HOLD key gives "HOLD AT" (or, with a hold already in the
-- plan, NEW HOLD first); the fix name goes into it. X-Plane then shows the new hold
-- as MOD: the UNS HOLDING page, where ENTER executes it.
holdAtFix = function(name)
	S.busy = "HOLD"
	runJob(function()
		clearScratchSafe()
		xpCommand("sim/FMS/hold")
		wait(0.4)
		local L = cduLines()
		local k = findWord(L, "HOLD AT")
		if not k then
			local nk, ns = findWord(L, "NEW HOLD")
			if nk then
				xpCommand("sim/FMS/ls_" .. nk .. ns)
				wait(0.4)
				k = findWord(cduLines(), "HOLD AT")
			end
		end
		if not k then
			msg("HOLD NOT AVAILABLE")
			S.busy = nil
			return
		end
		typeXP(name)
		wait(0.2)
		xpCommand("sim/FMS/ls_" .. k .. "l")     -- the HOLD AT box is on the left
		wait(0.4)
		local left = scratchText()
		if left ~= "" then
			msg(usub(left, 24))
			clearScratchSafe()
		else
			S.userHold = name                      -- the hold made on the UNS
		end
		S.page = "MIRROR"
		S.busy = nil
	end)
end

-- UNS function key -> X-Plane FMS page it opens
local PAGE_CMD = {
	FPL = "sim/FMS/legs", LIST = "sim/FMS/legs", DTO = "sim/FMS/dir_intc",
	DATA = "sim/FMS/index", VNAV = "sim/FMS/clb", PERF = "sim/FMS/prog",
	TUNE = "sim/FMS/navrad", HOLD = "sim/FMS/hold",
}

local function faceOn() return val(dr_face, 1) == 1 end
local function powered() return val(dr_power, 0) == 1 end
core.faceOn = faceOn
core.powered = powered

local dimKey   -- DIM page keys (defined with the DIM page)

function core.key(k, u)
	u = (u == 2) and 2 or 1
	-- original screen selected: the keys work exactly as before (captain's CDU)
	if not faceOn() then
		setUnit(1)
		if BOEING[k] then xpCommand(BOEING[k]) end
		return
	end
	setUnit(u)       -- this unit's pages and its own X-Plane CDU
	if not powered() then return end
	local V = U[u]
	-- ON/OFF DIM key (where a dot used to be): unit off -> on (it recycles: self test,
	-- POS INIT); unit on -> DIM page (brightness, OFF)
	if not V.on then
		if k == "DOT" then
			V.on = true
			dirtySoon()
		end
		return
	end
	if V.boot then return end          -- this unit's self test running
	if k == "DOT" then
		V.dim = not V.dim
		dirtySoon()
		return
	end
	if V.dim then
		dimKey(u, k)
		dirtySoon()
		return
	end
	-- POS INIT (after this unit's self test): only ACCEPT (left key 6) or ENTER go on
	if V.posinit then
		if k == "L6" or k == "ENTER" then
			V.posinit = false
			-- ACCEPT also clears X-Plane's start-up message on this unit's CDU
			-- (NAV DATA OUT OF DATE), as CLR would on the Boeing CDU
			runJob(function()
				wait(0.1)
				clearScratchSafe()
			end)
			dirtySoon()
		end
		return
	end
	if S.busy then return end   -- ORIGIN/DEST being entered (about a second)

	-- X-Plane waits for ENTER: ←ENTER is offered at left key 6, same as the ENTER key
	if k == "L6" and core.waitingEnter() then
		xpCommand(BOEING.ENTER)
		dirtySoon()
		return
	end

	-- UNS pages of their own: FPL MENU (start page) and NAV (display only)
	if k == "MENU" then
		S.page = "FMENU"
		S.entry = ""
		S.delFplArmed = false
		dirtySoon()
		return
	end
	if k == "NAV" then
		S.page = "NAV"
		S.entry = ""
		dirtySoon()
		return
	end
	-- any page key ends the VNAV page set (it is set again by the VNAV key)
	if (PAGE_CMD[k] or core.OWN_PAGES[k] or k == "MENU" or k == "NAV" or k == "HOLD") and k ~= "LIST" then
		S.vnavMirror = nil
		S.pageSet = nil
	end
	-- PATH VNAV, PERF, TUNE and DATA are UNS pages of their own
	if core.OWN_PAGES[k] then
		if k == "LIST" and S.page ~= "LIST" then S.listBack = S.page end   -- RTN / choice go back there
		if k == "LIST" then S.listPage = 1 end
		S.page = k
		S.entry = ""
		if k == "VNAV" then S.vnavField = nil S.vnavPt = 1 end
		if k == "DATA" then S.dataPage = 1 end
		dirtySoon()
		return
	end
	-- every other function key opens the matching X-Plane FMS page, in UNS style
	-- HOLD key: as on the UNS it starts with the HOLD FIX list. X-Plane shows a hold
	-- that is already in the plan (e.g. one that came with a SID/STAR/approach); unless
	-- it is the hold made on the UNS, NEW HOLD is pressed to get the list of points.
	if k == "HOLD" then
		S.page = "MIRROR"
		S.entry = ""
		S.busy = "HOLD"
		runJob(function()
			xpCommand("sim/FMS/hold")
			wait(0.35)
			if not core.holdAtKey() then
				local F = core.holdParse()
				local fix = F.fix and F.fix.text or nil
				if fix and fix ~= "" and fix ~= SH.userHold then
					local nk, ns = findWord(cduLines(), "NEW HOLD")
					if nk then
						xpCommand("sim/FMS/ls_" .. nk .. ns)
						wait(0.3)
					end
				end
			end
			S.busy = nil
		end)
		dirtySoon()
		return
	end
	if PAGE_CMD[k] then
		xpCommand(PAGE_CMD[k])
		S.page = "MIRROR"
		S.entry = ""
		dirtySoon()
		return
	end

	-- on an FMS page every key goes straight to the FMS (ENTER = EXEC, BACK = CLR),
	-- except the UNS behaviour on FPL (select a point, DEL / DTO) and DTO (immediate)
	if S.page == "MIRROR" then
		-- VNAV pages 2..4 (X-Plane CLB / CRZ / DES): NEXT / PREV go through the VNAV pages
		if S.vnavMirror and S.pageSet and (k == "NEXT" or k == "PREV") then
			setGoto(S.pageSet, S.vnavMirror + ((k == "NEXT") and 1 or -1), k == "PREV")
			dirtySoon()
			return
		end
		local pname, pcur = pageInfo()
		local lsk = tonumber(string.match(k, "^L(%d)$"))
		-- HOLDING: each UNS key presses the key of its X-Plane field
		-- HOLD FIX (X-Plane's HOLD AT page): a point (left keys), a typed identifier or
		-- number (right key 1 or ENTER), PPOS (right key 6)
		local atK = (pname == "HOLDING") and core.holdAtKey() or nil
		if atK and (string.match(k, "^[LR]%d$") or (k == "ENTER" and scratchText() ~= "")) then
			local typed = scratchText()
			local pick = nil                                   -- left key of the point
			if lsk and lsk < atK then pick = lsk end
			if (k == "R1" or k == "ENTER") and typed ~= "" then
				local num = tonumber(typed)
				if num then
					local kk = num - ((tonumber(pcur) or 1) - 1) * 5
					if kk >= 1 and kk < atK and core.holdFixName(kk) then pick = kk else msg("NOT ON THIS PAGE") end
				else
					pick = "typed"
				end
			end
			if k == "R6" then
				local pk, ps = findWord(cduLines(), "PPOS")
				if pk then xpCommand("sim/FMS/ls_" .. pk .. ps) end
			elseif pick then
				S.busy = "HOLD"
				local holdName = (pick == "typed") and typed or core.holdFixName(pick)
				runJob(function()
					if pick ~= "typed" then
						clearScratchSafe()
						xpCommand("sim/FMS/ls_" .. pick .. "l")   -- X-Plane copies the point
						wait(0.3)
					end
					xpCommand("sim/FMS/ls_" .. atK .. "l")         -- into HOLD AT
					wait(0.4)
					local left = scratchText()
					if left ~= "" then
						msg(usub(left, 24))
						clearScratchSafe()
					else
						S.userHold = holdName                -- the hold made on the UNS
					end
					S.busy = nil
				end)
			end
			dirtySoon()
			return
		end
		if pname == "HOLDING" and string.match(k, "^[LR]%d$") then
			local hk = holdKeyFor(k)
			local typed = scratchText()
			if not hk then
				-- an X-Plane hold page the UNS does not lay out itself (e.g. the list of
				-- holds when there are several): the key works as on X-Plane
				if BOEING[k] then xpCommand(BOEING[k]) end
			elseif k == "L1" and string.match(typed, "^%w+$") then
				holdAtFix(typed)                 -- FIX: a new hold at the typed fix
			elseif hk and hk.kind == "exit" then
				-- EXIT HOLD: direct to the flight plan point after the hold fix
				local plan, dest = readPlan()
				local nextName = nil
				-- (X-Plane may list the hold fix more than once - the fix and its hold leg -
				-- so the point after the hold is the first one with another name)
				local function nm(e) return (string.gsub(e.id or "", "@$", "")) end
				for i = math.max(1, dest - 1), #plan do
					if nm(plan[i]) == hk.fix then
						for j = i + 1, #plan do
							if nm(plan[j]) ~= hk.fix and usable(plan[j]) then
								nextName = entryName(plan[j])
								break
							end
						end
						break
					end
				end
				if nextName then
					directByDirPage(nextName)
					S.userHold = nil
				else
					msg("NO POINT AFTER " .. hk.fix)
				end
			elseif hk and hk.kind == "turn" then
				-- TURN: typed L or R, else the other direction; X-Plane takes "/L" or "/R"
				local typed = scratchText()
				local F = core.holdParse()
				local curDir = F.inbd and string.match(F.inbd.text or "", "/%s*([LR])") or "R"
				local want = (typed == "L" or typed == "R") and typed or ((curDir == "R") and "L" or "R")
				S.busy = "HOLD"
				runJob(function()
					clearScratchSafe()
					typeXP("/" .. want)
					wait(0.1)
					xpCommand("sim/FMS/ls_" .. hk.key)
					wait(0.2)
					S.busy = nil
				end)
			elseif hk then
				xpCommand("sim/FMS/ls_" .. hk.key)
			end
			dirtySoon()
			return
		end
		-- DEPARTURE / ARRIVAL: number of a list item + ENTER = its line key
		if (pname == "DEPARTURE" or pname == "ARRIVAL") and k == "ENTER" then
			local num = tonumber(string.match(scratchText(), "^(%d+)$") or "")
			if num then
				local key = procNumberKey(num, tonumber(pcur) or 1)
				if key then
					S.busy = "SEL"
					runJob(function()
						clearScratchSafe()
						xpCommand("sim/FMS/ls_" .. key .. "l")
						wait(0.1)
						S.busy = nil
					end)
				else
					msg("NOT ON THIS PAGE")
				end
				dirtySoon()
				return
			end
		end
		if pname == "FPL" and k == "L6" and not S.legsSel then
			xpCommand("sim/FMS/fpln")            -- AWY: X-Plane's FPLN page (VIA / TO)
			dirtySoon()
			return
		end
		if pname == "FPL" then
			if S.legsSel then
				local selk = S.legsSel
				if k == "R1" or k == "DEL" then
					if S.legsDelArmed then
						S.legsDelArmed = false
						S.legsSel = nil
						legsDeleteRow(selk)
					else
						S.legsDelArmed = true
					end
					dirtySoon()
					return
				elseif k == "R2" then
					local nm = legsRowName(selk)
					S.legsSel = nil
					S.legsDelArmed = false
					if nm then directByDirPage(nm) end
					dirtySoon()
					return
				elseif k == "R3" then
					local nm = legsRowName(selk)
					S.legsSel = nil
					S.legsDelArmed = false
					if nm then holdAtFix(nm) end
					dirtySoon()
					return
				elseif k == "R6" or k == "BACK" or (lsk and lsk == selk) then
					S.legsSel = nil
					S.legsDelArmed = false
					dirtySoon()
					return
				elseif lsk and lsk <= 5 and legsRowName(lsk) then
					S.legsSel = lsk
					S.legsDelArmed = false
					dirtySoon()
					return
				end
				S.legsSel = nil
				S.legsDelArmed = false
			elseif lsk and lsk <= 5 and scratchText() == "" and legsRowName(lsk) then
				S.legsSel = lsk          -- UNS: select the point, options appear
				S.legsDelArmed = false
				dirtySoon()
				return
			end
		elseif pname == "DTO" and lsk and lsk >= 2 and lsk <= 5 and scratchText() == "" then
			dirPickRow(lsk)              -- UNS: direct-to at once (EXEC if X-Plane asks)
			dirtySoon()
			return
		end
		if BOEING[k] then xpCommand(BOEING[k]) end
		dirtySoon()
		return
	end

	-- FPL MENU: typing the ORIGIN / DEST name; PATH VNAV: the target V/S (digits);
	-- DATA 2/2: the identifier to look up
	if S.page == "FMENU" or S.page == "VNAV" or S.page == "LIST" or (S.page == "DATA" and S.dataPage == 2) then
		local ch
		local digitsOnly = (S.page == "VNAV" or S.page == "LIST")
		if string.match(k, "^%d$") or (not digitsOnly and string.match(k, "^[A-Z]$")) then ch = k end
		if ch then
			local maxLen = (S.page == "FMENU") and 4 or MAX_ENTRY   -- airport codes: 4 letters
			if ulen(S.entry) < maxLen then S.entry = S.entry .. ch end
		else
			P[S.page].key(k)
		end
		dirtySoon()
		return
	end

	local page = P[S.page]
	if page and page.key then page.key(k) end
	dirtySoon()
end

-------------------------------------------------------------------------------
-- build + update
-------------------------------------------------------------------------------
-- POWER-UP SELF TEST ---------------------------------------------------------
-- dark for 1.5 s, then UNS - 1 / TUPOLEV 154 M and the test list; PASS row by row,
-- DATABASE BANK 2 counts 10..100 %, then the FPL MENU start page
local BOOT_DARK = 1.5
local BOOT_ROWS = {
	{ "CPU", 3.5 }, { "RAM", 5.0 }, { "DATABASE", 12.6, db = true },
	{ "CONFIG MODULE", 14.0 }, { "AUXILARY", 15.0 }, { "ARINC", 16.0 },
}
local BOOT_DB_START, BOOT_DB_STEP = 6.0, 0.6    -- 10 % every 0.6 s (100 % at 12.0 s)
local BOOT_END = 17.0                            -- whole power-up procedure: 17 s

local function buildBoot(e)
	if e < BOOT_DARK then return end
	put("T", 8, "UNS - 1", C.green)
	put("L1", 1, "TUPOLEV  154 M", C.green)
	for i, r in ipairs(BOOT_ROWS) do
		local row = "S" .. i
		local label = r[1]
		if r.db and e >= BOOT_DB_START then label = "DATABASE BANK 2" end
		put(row, 1, label, C.green)
		if e >= r[2] then
			put(row, 18, "PASS", C.green)
		elseif r.db and e >= BOOT_DB_START + BOOT_DB_STEP then
			local pct = math.min(100, math.floor((e - BOOT_DB_START) / BOOT_DB_STEP) * 10)
			putR(row, 21, string.format("%d%%", pct), C.green)
		end
	end
end

-- POS INIT page (after the self test): position, date, UTC; ←ACCEPT opens FPL MENU
local MONTHS = { "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" }
utcDate = function()
	local year = tonumber(os.date("!%Y")) or 2026
	local day = val(dr_lday, 0)                      -- 0 = 1 January (local date)
	local diff = val(dr_zulu, 0) - val(dr_ltime, 0)  -- UTC date can be a day off
	if diff < -43200 then day = day + 1 elseif diff > 43200 then day = day - 1 end
	local function leap(y) return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0 end
	local mdays = { 31, leap(year) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
	if day < 0 then day = 0 end
	local m = 1
	while m < 12 and day >= mdays[m] do day = day - mdays[m]; m = m + 1 end
	return string.format("%02d-%s-%02d", day + 1, MONTHS[m], year % 100)
end
utcTime = function()
	local z = math.floor(val(dr_zulu, 0)) % 86400
	return string.format("%02d:%02d:%02d", math.floor(z / 3600), math.floor(z / 60) % 60, z % 60)
end
local function buildPosInit()
	put("T", 1, "POS", C.amber)
	put("T", 8, "INIT 1/1", C.green)
	putR("P1", 23, "DATE", C.white, false)
	put("P2", 0, "INITIAL POS", C.white, false)
	putR("P2", 23, utcDate(), C.yellow)
	put("P3", 0, "ID", C.white, false)
	put("P3", 3, "<GPS>", C.green)
	putR("P3", 23, "UTC", C.white, false)
	local la, lo = val(dr_lat, 0), val(dr_lon, 0)
	local function dm(v) local a = math.abs(v); local d = math.floor(a); return d, (a - d) * 60 end
	local ad, am = dm(la)
	local od, om = dm(lo)
	if am >= 59.95 then ad, am = ad + 1, 0 end
	if om >= 59.95 then od, om = od + 1, 0 end
	put("P4", 0, string.format("%s  %02d %04.1f", la >= 0 and "N" or "S", ad, am), C.yellow)
	putR("P4", 23, utcTime(), C.yellow)
	put("P5", 0, string.format("%s %03d %04.1f", lo >= 0 and "E" or "W", od, om), C.yellow)
	put("P6", 0, "STANDARD / EXTENDED", C.green)
	-- only when X-Plane's FMS itself says its NAV DATA is OUT OF DATE (no date shown)
	if not S.navOld then
		for i = 0, 15 do
			local t = val(cdu_text[i], "")
			if type(t) == "string" and string.find(t, "OUT OF DATE", 1, true) then S.navOld = true break end
		end
	end
	if S.navOld then put("P7", 0, "\"\"NAV DATABASE EXPIRED\"\"", C.amber, false) end
	put("L6", 0, "←ACCEPT", C.box, true, true)
	put("L6", 9, "FMC VER", C.white, false)
	putR("L6", 23, "T5M", C.green)
end

-- DIM page (ON/OFF DIM key): brightness (linked to the brightness knob) and OFF
local function buildDim(u)
	put("T", 9, "DIM 1/1", C.green)
	put("L1", 0, "←BRIGHT", C.white)
	put("L2", 0, "←DIM", C.white)
	putR("L1", 23, "OFF→", C.white)
	put("U4", 0, "BRIGHTNESS", C.white, false)
	local n = math.floor(unitBrt(u) * 10 + 0.5)
	if n > 0 then put("L4", 0, string.rep("■", n), C.green) end
	putR("L4", 23, string.format("%d%%", n * 10), C.green)
	putR("L6", 23, "RTN→", C.white)
end
dimKey = function(u, k)
	local V = U[u]
	if k == "L1" or k == "L2" then
		local v = math.floor(unitBrt(u) * 10 + 0.5) / 10 + ((k == "L1") and 0.1 or -0.1)
		V.brt = math.max(0, math.min(1, v))
	elseif k == "R1" then
		V.dim = false
		V.on = false                                        -- unit off (recycles when switched on)
	elseif k == "R6" or k == "BACK" then
		V.dim = false
	end
end

-- X-Plane waits for ENTER: EXEC light on, or MOD on an FMS page
function core.waitingEnter()
	if S.busy then return false end
	if val(dr_exec, 0) == 1 then return true end
	if S.page == "MIRROR" then
		local _, _, _, mod = pageInfo()
		return mod and true or false
	end
	return false
end

local function unitActive(u) return powered() and U[u].on end
core.unitActive = function(u) return faceOn() and unitActive(u) end

-- the page of the current unit (setUnit) into M
local function buildPage()
	M = {}
	do
		local page = P[S.page] or P.FPL
		local ok, err = pcall(page.build)
		if not ok then
			M = {}
			put("L3", 2, "UNS PAGE ERROR", C.amber)
			sasl.logWarning("UNS page " .. tostring(S.page) .. ": " .. tostring(err))
		end
		-- inoperative / display-only: on the UNS pages that only show values (NAV, PERF,
		-- PATH VNAV), a value that is not available ("----", "--:--", "-.-") is blue;
		-- fields that take an entry (marked edit) stay as they are
		if S.page == "TUNE" then
			-- TUNE is display only (tuned on the radio panels): its values are blue
			for _, it in ipairs(M) do
				if it.row ~= "T" and it.color == C.green then it.color = C.cyan end
			end
		end
		if S.page == "NAV" or S.page == "PERF" or S.page == "VNAV" then
			for _, it in ipairs(M) do
				if it.text and not it.inv and not it.edit and it.color == C.green
					and string.match(it.text, "^[%-%.:+/%s°]+$") and string.find(it.text, "-", 1, true) then
					it.color = C.cyan
				end
			end
		end
		-- X-Plane's FPLN page is the UNS airways page (AWY): its prompts say so
		if S.page == "MIRROR" then
			for _, it in ipairs(M) do
				if it.text then
					if string.match(it.text, "^←FPLN%s*$") then it.text = "←AWY"
					elseif string.match(it.text, "^%s*FPLN→$") then it.text = "AWY→" end
				end
			end
			-- FPL page: ←AWY (airways) at left key 6, unless a point is selected or ENTER is due
			local pn = pageInfo()
			if pn == "FPL" and not S.legsSel and not core.waitingEnter() then
				local keep = {}
				for _, it in ipairs(M) do
					local lead = it.text and #string.match(it.text, "^%s*") or 0
					if not ((it.row == "L6" or it.row == "D6") and it.col and it.col + lead < 8) then keep[#keep + 1] = it end
				end
				M = keep
				put("L6", 0, "←AWY", C.white)
			end
		end
		-- messages (DIRECT TO..., NOT IN DATABASE...) show for a few seconds on the
		-- title line, in place of the title, so they never cover the page lines
		if S.msg and now() < S.msgUntil then
			local keep = {}
			for _, it in ipairs(M) do
				if it.row ~= "T" then keep[#keep + 1] = it end
			end
			M = keep
			local m = usub(S.msg, 24)
			put("T", math.floor((24 - ulen(m)) / 2), m, C.amber)
		end
		-- X-Plane waits for ENTER: UNS way, ←ENTER next to left key 6 (press it, or the
		-- ENTER key). What X-Plane shows on the left of that line gives way to it.
		if core.waitingEnter() then
			local keep = {}
			for _, it in ipairs(M) do
				if not ((it.row == "L6" or it.row == "D6") and it.col < 8) then keep[#keep + 1] = it end
			end
			M = keep
			put("L6", 0, "←ENTER", C.box, true, true)
		end
	end
	return M
end

local function build()
	-- each unit: its self test, POS INIT or DIM page, otherwise its own page
	for u = 1, 2 do
		local V = U[u]
		V.model = nil
		if faceOn() and unitActive(u) then
			setUnit(u)
			if V.boot and now() - V.boot >= BOOT_END then
				V.boot = nil              -- self test done: position page, then ACCEPT
				V.posinit = true
			end
			if V.boot then
				M = {}
				buildBoot(now() - V.boot)
			elseif V.posinit then
				M = {}
				pcall(buildPosInit)
			elseif V.dim then
				M = {}
				pcall(buildDim, u)
			else
				buildPage()
			end
			V.model = M
		end
	end
	setUnit(1)
	core.model = U[1].model or {}
	M = core.model
	if core.onRedraw then core.onRedraw() end
end

-- UNS power cut or power back: X-Plane's flight plan is erased, so the restarted
-- UNS (and the Kontur) start with no route. Only real power changes do this; the
-- "New UNS screen" menu switch does not.
-- a unit's pages back to the start page (FPL MENU), nothing typed or selected
local function resetUnitPages(u)
	local s = SS[u]
	s.page = "FMENU"
	s.back = "FPL"
	s.wpt = nil
	s.entry = ""
	s.fplSel = "new"
	s.fplPage = 1
	s.dtoPage = 1
	s.delArmed = false
	s.legsSel = nil
	s.legsDelArmed = false
	s.msg = nil
	s.msgUntil = 0
	s.busy = nil
	s.tgtVS = nil
	s.vnavMirror = nil
	s.pageSet = nil
	s.delFplArmed = false
	s.dataPage = 1
	s.dataHit = nil
	s.dataHits = nil
	JOB[u].co = nil
end

local function eraseFlightPlan()
	-- X-Plane's flight plan: clear every entry, check it is really empty (repeat if not)
	for _ = 1, 3 do
		local ok, n = pcall(sasl.countFMSEntries)
		if not ok or type(n) ~= "number" or n <= 0 then break end
		for i = n - 1, 0, -1 do pcall(sasl.clearFMSEntry, i) end
	end
	-- and everything the UNS itself remembers about the old flight (both units)
	SH.origin = nil
	SH.dest = nil
	SH.dto = nil
	SH.navOld = nil
	SH.crz = nil
	SH.userHold = nil
	resetUnitPages(1)
	resetUnitPages(2)
end
local wasAny = nil
function core.update()
	checkCdu2()
	jobStep()
	core.listStep()
	core.navTrack()
	local t = now()
	-- a unit switched on (power, or its ON/OFF DIM key) recycles: self test, POS INIT,
	-- then its own start page (FPL MENU)
	local booting = false
	for u = 1, 2 do
		local V = U[u]
		if not powered() then V.on = false end   -- no UNS power: unit off until switched on again
		local a = unitActive(u)
		if a ~= V.was then
			V.was = a
			V.boot = a and t or nil
			V.posinit = false
			V.dim = false
			resetUnitPages(u)
			nextBuild = t
		end
		if V.boot then booting = true end
	end
	-- no unit on any more (power cut, or both switched off) and the first unit back on:
	-- the flight plan is erased and the UNS starts from scratch
	local any = unitActive(1) or unitActive(2)
	if any ~= wasAny then
		if wasAny ~= nil or any then eraseFlightPlan() end
		wasAny = any
		resetUnitPages(1)
		resetUnitPages(2)
		SH.navOld = nil
		nextBuild = t
	end
	if t >= nextBuild then
		build()
		nextBuild = t + (booting and 0.1 or REFRESH)
	end
end

-------------------------------------------------------------------------------
-- drawing (used by the 3D screen and by the 2D popup)
-------------------------------------------------------------------------------
local font = loadFont("DejaVuSansMono-Bold.ttf")
local CAP = 0.729  -- cap height of the font, as a part of the font size

function core.draw(W, H, x0, y0, u, noBg)
	x0 = x0 or 0
	y0 = y0 or 0
	u = (u == 2) and 2 or 1
	if not (faceOn() and unitActive(u)) then return end
	local model = U[u].model
	if not model then return end
	if #model == 0 then return end
	local mx = W * 0.03
	local cell = (W - 2 * mx) / 24
	local big = math.min(H * 0.084, cell * 1.55)
	local small = big * 0.80
	local drawText, drawRect = sasl.gl.drawText, sasl.gl.drawRectangle
	local lw = math.max(1, H * 0.006)                -- line width of frames and drawings
	-- background: the 3D screens stay black (as at night in the cockpit); the 2D panel
	-- draws its own rounded dark grey screen (UNS_2d_screen.png) behind this
	local function rowY(r)
		local f = (type(r) == "number") and r or ROWF[r]
		return f and (y0 + H * (1 - f)) or nil
	end
	local function line(xa, ya, xb, yb, color)
		if sasl.gl.drawWideLine then
			sasl.gl.drawWideLine(xa, ya, xb, yb, lw, color)
		elseif sasl.gl.drawLine then
			sasl.gl.drawLine(xa, ya, xb, yb, color)
		end
	end
	-- pass 1: the cursor boxes (white fields); pass 2: all text and drawings on top,
	-- so a box never covers a label next to it
	for _, it in ipairs(model) do
		local f = it.inv and it.row and ROWF[it.row]
		if f then
			f = f + (it.dy or 0)
			local cap = (it.big and big or small) * CAP
			local yc = y0 + H * (1 - f)
			-- cursor box: tall enough for the text, never into the line above/below
			drawRect(x0 + mx + it.col * cell, yc - cap * 0.56, ulen(it.text) * cell, cap * 1.12, it.color)
		end
	end
	for _, it in ipairs(model) do
		local f = it.row and ROWF[it.row]
		if f and it.dy then f = f + it.dy end
		if it.shape == "line" then
			local ya, yb = rowY(it.r1), rowY(it.r2)
			if ya and yb then
				line(x0 + mx + it.c1 * cell, ya, x0 + mx + it.c2 * cell, yb, it.color)
			end
		elseif it.shape == "arc" then
			-- half circle: centre (c, r), radius in columns, from angle a1 to a2 (degrees)
			local cx, cy = x0 + mx + it.c * cell, rowY(it.r)
			if cy then
				local rad = it.rad * cell
				local steps = 16
				local px, py
				for i = 0, steps do
					local a = math.rad(it.a1 + (it.a2 - it.a1) * i / steps)
					local qx, qy = cx + rad * math.cos(a), cy + rad * math.sin(a)
					if px then line(px, py, qx, qy, it.color) end
					px, py = qx, qy
				end
			end
		elseif f then
			local size = it.big and big or small
			local cap = size * CAP
			local yc = y0 + H * (1 - f)
			local by = yc - cap / 2
			local xs = x0 + mx + it.col * cell
			local chars = uchars(it.text)
			local color = it.color
			if it.inv then
				color = C.black                 -- text in a cursor box (box drawn in pass 1)
			elseif it.frame then
				-- framed (outlined) text, e.g. the H over the PATH VNAV altitudes
				local bx, by2, bw, bh = xs - cell * 0.12, yc - cap * 0.75, #chars * cell + cell * 0.24, cap * 1.5
				drawRect(bx, by2, bw, lw, color)
				drawRect(bx, by2 + bh - lw, bw, lw, color)
				drawRect(bx, by2, lw, bh, color)
				drawRect(bx + bw - lw, by2, lw, bh, color)
			end
			for i, ch in ipairs(chars) do
				if ch == "←" or ch == "→" then
					-- UNS arrows: a solid shaft and head, as on the real screen
					local cx = xs + (i - 0.5) * cell
					local half = cell * 0.48
					local hl, hh = cell * 0.40, cap * 0.40
					local th = math.max(2, cap * 0.17)
					local dir = (ch == "←") and -1 or 1
					local tip = cx + dir * half
					local base = tip - dir * hl
					local tail = cx - dir * half
					drawRect(math.min(base, tail), yc - th / 2, math.abs(base - tail), th, color)
					if sasl.gl.drawTriangle then
						sasl.gl.drawTriangle(tip, yc, base, yc + hh, base, yc - hh, color)
					else
						drawText(font, cx, by, ch, size, false, false, TEXT_ALIGN_CENTER, color)
					end
				elseif ch ~= " " then
					drawText(font, xs + (i - 0.5) * cell, by, ch, size, false, false, TEXT_ALIGN_CENTER, color)
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- commands: tu154/uns/key/<KEY> for every key, tu154/uns/popup for the 2D panel
-------------------------------------------------------------------------------
core.KEYS = {
	"DATA", "NAV", "VNAV", "DTO", "LIST", "PREV", "HOLD", "FPL", "PERF", "TUNE", "MENU", "NEXT",
	"BACK", "DEL", "DOT", "SLASH", "ENTER",
}
for c = string.byte("A"), string.byte("Z") do core.KEYS[#core.KEYS + 1] = string.char(c) end
for d = 0, 9 do core.KEYS[#core.KEYS + 1] = tostring(d) end
for k = 1, 6 do
	core.KEYS[#core.KEYS + 1] = "L" .. k
	core.KEYS[#core.KEYS + 1] = "R" .. k
end

-- tu154/uns/key/<KEY>  = captain's UNS (unit 1, also the 2D panel)
-- tu154/uns2/key/<KEY> = right UNS (unit 2)
core.cmds = {}
for u, prefix in ipairs({ "tu154/uns/key/", "tu154/uns2/key/" }) do
	for _, k in ipairs(core.KEYS) do
		local name = (k == "DOT") and "ON/OFF DIM" or k
		local cmd = sasl.createCommand(prefix .. k, (u == 1 and "UNS 1 key " or "UNS 2 key ") .. name)
		if u == 1 then core.cmds[k] = cmd end
		sasl.registerCommandHandler(cmd, 0, function(phase)
			if phase == SASL_COMMAND_BEGIN then core.key(k, u) end
			return 0
		end)
	end
end

local popupCmd = sasl.createCommand("tu154/uns/popup", "UNS 2D panel open/close")
sasl.registerCommandHandler(popupCmd, 0, function(phase)
	if phase == SASL_COMMAND_BEGIN then
		if not faceOn() then
			setUnit(1)
			xpCommand("sim/FMS/CDU_popup")
		elseif core.onPopup then
			core.onPopup()
		end
	end
	return 0
end)

return core
