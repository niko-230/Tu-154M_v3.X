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

createGlobalPropertyi("tu154b2/custom/switchers/airbleed/ground_cond_on_cap_eng", 0)   -- крышка наземного кондиционирования (панель БИ)
createGlobalPropertyi("tu154b2/custom/switchers/airbleed/skv_faster_work_cap_eng", 0)  -- крышка охлаждения ГК (панель БИ)

defineProperty("control_ut", globalPropertyi("tu154b2/custom/buttons/eng/control_ut")) -- кнопка контроль УТ (панель БИ, M)
defineProperty("egt_1_test", globalPropertyi("sim/custom/gauges/eng/egt_1_test"))
defineProperty("egt_2_test", globalPropertyi("sim/custom/gauges/eng/egt_2_test"))
defineProperty("egt_3_test", globalPropertyi("sim/custom/gauges/eng/egt_3_test"))

local control_ut_last = -1

function update()
	local ut = get(control_ut)
	if ut ~= control_ut_last then
		set(egt_1_test, ut)
		set(egt_2_test, ut)
		set(egt_3_test, ut)
		control_ut_last = ut
	end
end
