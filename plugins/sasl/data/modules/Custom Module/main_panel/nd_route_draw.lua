size = {500, 400} --475 370 display bounds, 360 250 dist box bounds, 120 290 hdg box bounds, 320 top pound
defineProperty("table_draw")
defineProperty("n_wp")
wp = loadImage("nd_marks.png", 36, 0, 36, 43)
wp_mag = loadImage("nd_marks.png", 0, 0, 36, 43)
defineProperty("range")
defineProperty("brightness")
defineProperty("navon")
defineProperty("mode")
defineProperty("dist_mode")
defineProperty("menu")
defineProperty("name_draw")
gps_dest = globalPropertyi("tu154b2/custom/radio/curr_wp")
gps_dest_app = globalPropertyi("tu154b2/custom/radio/curr_wp_app")
n_wp_app = globalPropertyi("tu154b2/custom/radio/appr_n_waypoints")
local font = loadFont(moduleDirectory.."/Custom Module/Verdana.ttf")
-- defineProperty("db1", globalPropertyf("tu154b2/custom/controlls/debug1"))
-- defineProperty("db2", globalPropertyf("tu154b2/custom/controlls/debug2"))
-- defineProperty("db3", globalPropertyf("tu154b2/custom/controlls/debug3"))

-- 2026-10-31: magenta route line on Kontur.
-- X-Plane's generic map gauges drew the route line for the Boeing FMS (CDU739), but not for the
-- Citation's Primus FMS (CDU815) - that one only draws its route on its own Primus screens.
-- So the line is drawn here, between the same waypoint stars this file already places
-- (same projection, same hidden areas: info boxes, coordinate box, menu).
local route_col_r, route_col_g, route_col_b = 0.76, 0.21, 0.77 -- same magenta as the active waypoint label
local ROUTE_WIDTH = 2.5
local ROUTE_STEP = 3 -- px; the line is drawn in short pieces so it can skip the info boxes

local function route_blocked(x, y, menu_on)
	return y > 320 or (x > 360 and y > 250) or (x < 120 and y > 290) or y > 370 or x > 475 or x < 0 or y < 0
		or (x < 130 and y < 66) or (x > 70 and x < 390 and y > 140 and y < 250 and menu_on)
end

local function route_segment(x1, y1, x2, y2, menu_on, col)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.5 then return end
	local n = math.ceil(len / ROUTE_STEP)
	if n > 2000 then n = 2000 end -- far-off legs: plenty of resolution, bounded cost
	local px, py = x1, y1
	local pin = not route_blocked(px, py, menu_on)
	for k = 1, n do
		local t = k / n
		local qx, qy = x1 + dx * t, y1 + dy * t
		local qin = not route_blocked(qx, qy, menu_on)
		if pin and qin then
			sasl.gl.drawWideLine(px, py, qx, qy, ROUTE_WIDTH, col)
		end
		px, py, pin = qx, qy, qin
	end
end

function draw()
	
	local targets = get(table_draw)
	local names = get(name_draw)
	local brt = get(brightness)
	local n_waypoints = get(n_wp)
	local n_waypoints_main = n_waypoints - get(n_wp_app)
	-- sasl.gl.setRenderTarget ( nd_display )

	-- route line (drawn first, so the waypoint stars sit on top of it)
	if get(navon) ~= 0 and n_waypoints > 1 then
		local range_set = get(range)
		local rc = 1
		if range_set == 1 then rc = 10
		elseif range_set == 2 then rc = 20
		elseif range_set == 3 then rc = 40
		elseif range_set == 4 then rc = 100
		elseif range_set == 5 then rc = 200
		elseif range_set == 6 then rc = 320
		elseif range_set == 7 then rc = 640
		end
		rc = rc * (1 - 0.073 * get(dist_mode)) * 1.1
		local yoff = -4 + 130 * bool2int(get(mode) == 5) + 21
		local menu_on = get(menu) == 1
		local col = {route_col_r, route_col_g, route_col_b, brt}
		local function centre(i)
			-- star image is drawn at (x, y) with size 29 x 34 -> its centre
			return targets[i][1] / rc * 678 + 235 + 14.5, targets[i][2] / rc * 678 + yoff + 17
		end
		-- FMS route: entry i-1 -> i; approach list (if any) is joined the same way, separately
		for i = 2, n_waypoints, 1 do
			if i ~= n_waypoints_main + 1 and targets[i - 1][3] == 1 and targets[i][3] == 1 then
				local x1, y1 = centre(i - 1)
				local x2, y2 = centre(i)
				route_segment(x1, y1, x2, y2, menu_on, col)
			end
		end
	end

	for i = 1, n_waypoints, 1 do	
		local mark_img = get(wp)
		local col =  {1, 1, 1, brt}
		if (i == get(gps_dest) and i<= n_waypoints_main) or (i == get(gps_dest_app) + n_waypoints_main + 1 and i> n_waypoints_main) then
			mark_img = get(wp_mag)
			col =  {0.76, 0.21, 0.77, brt}
		end
		local text = names[i]
		
		local range_set = get(range)
		local range_coef = 1
		if range_set == 1 then range_coef = 10
		elseif range_set == 2 then range_coef = 20
		elseif range_set == 3 then range_coef = 40
		elseif range_set == 4 then range_coef = 100
		elseif range_set == 5 then range_coef = 200
		elseif range_set == 6 then range_coef = 320
		elseif range_set == 7 then range_coef = 640
		end
		range_coef = range_coef * (1-0.073*get(dist_mode)) *  1.1
		local x = targets[i][1] / range_coef * 678 + 235 
		local y = targets[i][2] / range_coef * 678 -4 + 130 * bool2int(get(mode)==5) + 21
		local hide = y>320 or (x>360 and y>250) or (x<120 and y>290) or y>370 or x>475 or x<0 or y<0 or get(navon)==0 or (x<130 and y<66) or (x>70 and x<390 and y>140 and y<250 and get(menu) == 1)
		local hide_txt = y>320 or (x>320 and y>250) or (x<120 and y>290) or y>370 or x>420 or x<0 or y<0 or get(navon)==0 or (x<130 and y<66) or (x>50 and x<390 and y>140 and y<250 and get(menu) == 1)
		-- sasl.gl.drawMaskStart ()
		-- sasl.gl.drawRectangle(-4,29,165,66, {1,1,1,1})
		-- sasl.gl.drawRectangle(-8,-5,140,29, {1,1,1,1})
		-- sasl.gl.drawUnderMask (true)
		if not hide then
			drawTexture(mark_img, x, y, 29, 34, {1,1,1,brt})
		end
		if not hide_txt then
			drawText(font, x+29, y+12 , text, 18, false, false, TEXT_ALIGN_LEFT, col)
		end
		-- sasl.gl.drawMaskEnd ()
	end
	-- sasl.gl.restoreRenderTarget()
		-- local mark_img2 = get(wp)
		-- drawTexture(mark_img2, get(db1), get(db2), 29, 34, 1,1,1)
end