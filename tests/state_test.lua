package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        fail_count = fail_count + 1
        local info = debug.getinfo(2, "Sl")
        local loc = (info and info.short_src and info.currentline)
                and string.format("[%s:%d] ", info.short_src, info.currentline)
            or ""
        print(
            string.format(
                "%sFAIL: expected '%s', got '%s'. Context: %s",
                loc,
                tostring(expected),
                tostring(actual),
                msg or ""
            )
        )
    else
        pass_count = pass_count + 1
    end
end

print("Running Test 05: state.lua tests...")

local state = require("skkeleton-for-pickers.state")

-- Test helper to initialize the session state
local function reset_state()
    state.set_prev_preedit("")
    state.set_orig_getcharstr(nil)
end

-- Test 1: Session state getter/setter & reset
reset_state()
assert_eq(state.get_prev_preedit(), "", "Initial prev_preedit should be empty")
assert_eq(state.get_orig_getcharstr(), nil, "Initial orig_getcharstr should be nil")

state.set_prev_preedit("▽あい")
assert_eq(state.get_prev_preedit(), "▽あい", "Set prev_preedit")

local dummy_fn = function() end
state.set_orig_getcharstr(dummy_fn)
assert_eq(state.get_orig_getcharstr(), dummy_fn, "Set orig_getcharstr")

reset_state()
assert_eq(state.get_prev_preedit(), "", "Reset prev_preedit")
assert_eq(state.get_orig_getcharstr(), nil, "Reset orig_getcharstr")

-- Test 2: Buffer local state encapsulation (vim.b)
local buf = vim.api.nvim_create_buf(false, true)

assert_eq(state.is_skk_enabled(buf), false, "Initial buf skk_enabled")
assert_eq(state.is_cr_wrapped(buf), false, "Initial buf cr_wrapped")
assert_eq(state.get_original_cr(buf), nil, "Initial buf original_cr")

state.mark_skk_enabled(buf, true)
assert_eq(state.is_skk_enabled(buf), true, "Marked buf skk_enabled")

state.save_original_cr(buf, { lhs = "<CR>", rhs = "<Plug>(test)" })
assert_eq(state.get_original_cr(buf).lhs, "<CR>", "Saved original CR lhs")

state.mark_cr_wrapped(buf, true)
assert_eq(state.is_cr_wrapped(buf), true, "Marked buf cr_wrapped")

local ctx = state.read_buffer_context(buf)
assert_eq(ctx.skk_enabled, true, "read_buffer_context skk_enabled")
assert_eq(ctx.cr_wrapped, true, "read_buffer_context cr_wrapped")

-- Test 3: SKK global state encapsulation (vim.g)
state.set_skk_state("henkan")
assert_eq(state.get_skk_state(), "henkan", "get_skk_state")
assert_eq(vim.g["skkeleton#state"], "henkan", "vim.g['skkeleton#state']")

vim.api.nvim_buf_delete(buf, { force = true })
print(string.format("\nstate_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
