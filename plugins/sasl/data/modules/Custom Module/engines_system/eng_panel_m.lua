-- eng_panel_m.lua
-- Glue logic for the engineer panel imported from the M donor (B -> M transplant).
--
-- 1. "Контроль УТ" (EGT test): the M panel has ONE test button
--    (tu154b2/custom/buttons/eng/control_ut). This project's engine gauge logic
--    (engine_gauges.lua / engines_panel.lua) reads three per-engine test datarefs
--    (sim/custom/gauges/eng/egt_1..3_test), which used to be pushed by the old B buttons.
--    The M button now drives all three.
--
-- 2. Caps of the "ground conditioning" and "SKV faster work" switches.
--    In this project the original cap datarefs
--    (tu154b2/custom/switchers/airbleed/ground_cond_on_cap / skv_faster_work_cap)
--    are used by the captain / F-O PKP lighting knobs, so the M panel caps get
--    their own datarefs instead (pure visual caps, as in the M donor).
--
-- 3. Power switches of the EGT gauges (ТВГ, eng1..3_temp_ctrl) and of the vibration
--    gauges (vibro_pwr1..3). They were switches on the old B panel; the M panel has none,
--    so after a cold & dark start they stayed OFF for good (only the "engines running"
--    start set them to 1) and the EGT / vibration gauges and the УТ test never worked.
--    With no switch to operate, they are held ON; the gauges still need 27 V and 115 V.

createGlobalPropertyi("tu154b2/custom/switchers/airbleed/ground_cond_on_cap_eng", 0)   -- крышка наземного кондиционирования (панель БИ)
createGlobalPropertyi("tu154b2/custom/switchers/airbleed/skv_faster_work_cap_eng", 0)  -- крышка охлаждения ГК (панель БИ)

defineProperty("control_ut", globalPropertyi("tu154b2/custom/buttons/eng/control_ut")) -- кнопка контроль УТ (панель БИ, M)
defineProperty("egt_1_test", globalPropertyi("sim/custom/gauges/eng/egt_1_test"))
defineProperty("egt_2_test", globalPropertyi("sim/custom/gauges/eng/egt_2_test"))
defineProperty("egt_3_test", globalPropertyi("sim/custom/gauges/eng/egt_3_test"))

defineProperty("tvg1", globalPropertyi("sim/custom/gauges/eng/eng1_temp_ctrl"))
defineProperty("tvg2", globalPropertyi("sim/custom/gauges/eng/eng2_temp_ctrl"))
defineProperty("tvg3", globalPropertyi("sim/custom/gauges/eng/eng3_temp_ctrl"))
defineProperty("vibro_pwr1", globalPropertyi("sim/custom/gauges/eng/vibro_pwr1"))
defineProperty("vibro_pwr2", globalPropertyi("sim/custom/gauges/eng/vibro_pwr2"))
defineProperty("vibro_pwr3", globalPropertyi("sim/custom/gauges/eng/vibro_pwr3"))
local always_on = {tvg1, tvg2, tvg3, vibro_pwr1, vibro_pwr2, vibro_pwr3}

local control_ut_last = -1

function update()
	for _, p in ipairs(always_on) do
		if get(p) ~= 1 then set(p, 1) end
	end
	local ut = get(control_ut)
	if ut ~= control_ut_last then
		set(egt_1_test, ut)
		set(egt_2_test, ut)
		set(egt_3_test, ut)
		control_ut_last = ut
	end
end
