-- tests/core_test.lua
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    if type(actual) == "table" and type(expected) == "table" then
        local ok = true
        if #actual ~= #expected then
            ok = false
        else
            for i = 1, #actual do
                if actual[i] ~= expected[i] then
                    ok = false
                    break
                end
            end
        end
        if not ok then
            fail_count = fail_count + 1
            print(string.format("FAIL: table mismatch. Context: %s", msg or ""))
            return
        end
        pass_count = pass_count + 1
        return
    end

    if actual ~= expected then
        fail_count = fail_count + 1
        print(
            string.format("FAIL: expected '%s', got '%s'. Context: %s", tostring(expected), tostring(actual), msg or "")
        )
    else
        pass_count = pass_count + 1
    end
end

local core = require("skkeleton-for-pickers.core")

-- Test 04-1: UTF-8 Operations
print("Running Test 04-1: UTF-8 operations...")
assert_eq(core.utf8_len("あいうえお"), 5, "utf8_len Japanese")
assert_eq(core.utf8_len("abc"), 3, "utf8_len ASCII")
assert_eq(core.utf8_len(""), 0, "utf8_len empty")
assert_eq(core.utf8_chars("あaい"), { "あ", "a", "い" }, "utf8_chars mix")

-- Test 04-2: CR LHS and Map Search
print("Running Test 04-2: CR LHS and find_cr_map...")
assert_eq(core.is_cr_lhs("<CR>"), true, "is_cr_lhs <CR>")
assert_eq(core.is_cr_lhs("<cr>"), true, "is_cr_lhs <cr>")
assert_eq(core.is_cr_lhs("<Enter>"), true, "is_cr_lhs <Enter>")
assert_eq(core.is_cr_lhs("<Return>"), true, "is_cr_lhs <Return>")
assert_eq(core.is_cr_lhs("<Tab>"), false, "is_cr_lhs <Tab>")

local maps = {
    { lhs = "<Tab>", rhs = "foo" },
    { lhs = "<CR>", rhs = "bar" },
}
local found = core.find_cr_map(maps)
assert_eq(found and found.rhs, "bar", "find_cr_map found")

-- Test 04-3: Buffer Setup Plan
print("Running Test 04-3: plan_buffer_setup...")
assert_eq(core.plan_buffer_setup({ is_active_ft = false }).action, "skip", "plan skip when not active ft")
assert_eq(
    core.plan_buffer_setup({ is_active_ft = true, ft = "minipick" }).action,
    "patch_minipick",
    "plan minipick patch"
)

local setup_plan =
    core.plan_buffer_setup({ is_active_ft = true, ft = "TelescopePrompt", skk_enabled = false, cr_wrapped = false })
assert_eq(setup_plan.action, "setup", "plan setup")
assert_eq(#setup_plan.steps, 3, "3 steps for full setup")

-- Test 04-4: Marker Check, SKK Action Parse, Notation
print("Running Test 04-4: Marker & SKK Action Parse & Notation...")
assert_eq(core.check_marker_in_string("test▽input", "▽", "▼"), true, "check_marker_in_string henkan")
assert_eq(core.check_marker_in_string("test▼input", "▽", "▼"), true, "check_marker_in_string select")
assert_eq(core.check_marker_in_string("testinput", "▽", "▼"), false, "check_marker_in_string none")

assert_eq(core.check_marker_in_state({ henkanFeed = "a" }), true, "check_marker_in_state feed")
assert_eq(core.check_marker_in_state({ phase = "henkan" }), true, "check_marker_in_state phase henkan")

assert_eq(core.parse_skk_action("<Plug>(skkeleton-enable)"), "enable", "parse_skk_action enable")
assert_eq(core.parse_skk_action("<Plug>(skkeleton-disable)"), "disable", "parse_skk_action disable")
assert_eq(core.parse_skk_action("<Plug>(skkeleton-toggle)"), "toggle", "parse_skk_action toggle")
assert_eq(core.parse_skk_action("some_other_mapping"), nil, "parse_skk_action none")

assert_eq(core.to_notation("a", { ["a"] = "A" }), "A", "to_notation map hit")
assert_eq(core.to_notation("b", { ["a"] = "A" }), "b", "to_notation map miss")

-- Test 04-5: Query Operations
print("Running Test 04-5: Query operations...")
assert_eq(core.clean_query_markers({ "a", "▽", "b", "▼" }, "▽", "▼"), { "a", "b" }, "clean_query_markers")

local q1 = { "k", "a", "▽", "か" }
core.remove_old_preedit(q1, "か", "▽", "▼")
assert_eq(q1, { "k", "a" }, "remove_old_preedit with count & marker")

local bs_c, after_bs = core.parse_result_delta("\b\b漢字")
assert_eq(bs_c, 2, "parse_result_delta bs count")
assert_eq(after_bs, "漢字", "parse_result_delta text")

assert_eq(core.extract_kakutei("漢字か", "か"), "漢字", "extract_kakutei with preedit")

local new_q, new_prev = core.calculate_new_query({
    query = { "h", "o" },
    prev_preedit = "",
    result = "ほ",
    cur_preedit = "ほ",
    marker_henkan = "▽",
    marker_henkan_select = "▼",
})
assert_eq(new_q, { "h", "o", "ほ" }, "calculate_new_query new preedit")
assert_eq(new_prev, "ほ", "calculate_new_query return new_prev")

-- Test 04-6: SKK Routing & Key Normalization & Termcodes
print("Running Test 04-6: SKK routing & termcodes...")
local dummy_termcodes = {
    del = "<DEL_KEY>",
    bs = "<BS_KEY>",
    bspace = "<BSPACE_KEY>",
    nl = "<NL_KEY>",
}
assert_eq(core.should_route_to_skk("<BS_KEY>", false, dummy_termcodes), true, "should_route_to_skk BS termcode")
assert_eq(core.should_route_to_skk("a", false, dummy_termcodes), true, "should_route_to_skk ASCII char")

assert_eq(core.normalize_routed_key("<DEL_KEY>", dummy_termcodes), "\x08", "normalize_routed_key DEL termcode")
assert_eq(core.normalize_routed_key("a", dummy_termcodes), "a", "normalize_routed_key normal")

local plan_no_marker = core.get_skk_routing_plan("\r", false, dummy_termcodes)
assert_eq(plan_no_marker.action, "disable_skk", "routing plan disable for CR without marker")

local plan_marker = core.get_skk_routing_plan("\r", true, dummy_termcodes)
assert_eq(plan_marker.action, "handle_key", "routing plan handle_key for CR with marker")
assert_eq(plan_marker.skk_key, "<NL_KEY>", "routing plan key uses injected termcodes.nl")

-- Test 09-1: Enhanced parse_skk_action
print("Running Test 09-1: Enhanced parse_skk_action...")
assert_eq(core.parse_skk_action("<Plug>(skkeleton-enable)"), "enable", "parse rhs enable")
assert_eq(core.parse_skk_action("<Plug>(skkeleton-disable)"), "disable", "parse rhs disable")
assert_eq(core.parse_skk_action("<Plug>(skkeleton-toggle)"), "toggle", "parse rhs toggle")
assert_eq(core.parse_skk_action({ rhs = "<Plug>(skkeleton-toggle)" }), "toggle", "parse map table with rhs")
assert_eq(
    core.parse_skk_action({ callback = function() end, desc = "skkeleton toggle" }),
    "toggle",
    "parse map with desc toggle"
)
assert_eq(
    core.parse_skk_action({ callback = function() end, desc = "skkeleton enable" }),
    "enable",
    "parse map with desc enable"
)
assert_eq(core.parse_skk_action({ callback = function() end }), nil, "strict parse: no desc or rhs returns nil")

-- Test 09-2: eval_original_cr_plan pure function
print("Running Test 09-2: eval_original_cr_plan pure function...")

-- Case 1: nil orig -> fallback
local p1 = core.eval_original_cr_plan(nil)
assert_eq(p1.type, "fallback", "nil orig type fallback")
assert_eq(p1.keys, "<CR>", "nil orig keys <CR>")
assert_eq(p1.replace_termcodes, true, "nil orig replace_termcodes true")
assert_eq(p1.mode, "n", "nil orig mode n")

-- Case 2: Direct callback
local dummy_fn = function() end
local p2 = core.eval_original_cr_plan({ callback = dummy_fn })
assert_eq(p2.type, "callback_direct", "callback direct type")
assert_eq(p2.callback, dummy_fn, "callback direct function match")

-- Case 3: Direct RHS string
local p3 = core.eval_original_cr_plan({ rhs = "<Cmd>confirm<CR>", noremap = 1 })
assert_eq(p3.type, "rhs_direct", "rhs direct type")
assert_eq(p3.keys, "<Cmd>confirm<CR>", "rhs direct keys match")
assert_eq(p3.replace_termcodes, true, "rhs direct replace_termcodes true")
assert_eq(p3.mode, "n", "rhs direct mode n")

print(string.format("\ncore_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
