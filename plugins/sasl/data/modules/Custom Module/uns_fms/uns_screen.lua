-- UNS screen, drawn into a 3D avionics device:
--   unit 1 = captain's UNS ("tu154b2/uns_screen"), unit 2 = right UNS ("tu154b2/uns_screen2").
-- All logic lives in uns_core.lua, shared with the 2D popup (captain's unit).

local core = request("uns_core")
local kontur_on = globalPropertyi("tu154b2/custom/b2/kontur_on")

defineProperty("unit", 1)

-- device texture size (must match size in uns_display.lua). Fixed here on purpose:
-- a component inside an avionics device otherwise inherits the 4096 x 4096 panel size.
local W, H = 800, 506

function update()
	if get(unit) ~= 1 then return end   -- the shared UNS logic runs once per frame
	core.update()
	-- the 2D panel belongs to the new UNS screen in the Kontur cockpit only
	if core.closePopup and (not core.faceOn() or get(kontur_on) ~= 1) then
		core.closePopup()
	end
end

function draw()
	core.draw(W, H, 0, 0, get(unit))
end
