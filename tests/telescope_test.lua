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

local function assert_true(cond, msg)
    if not cond then
        fail_count = fail_count + 1
        local info = debug.getinfo(2, "Sl")
        local loc = (info and info.short_src and info.currentline)
                and string.format("[%s:%d] ", info.short_src, info.currentline)
            or ""
        print(string.format("%sFAIL: expected true, got false. Context: %s", loc, msg or ""))
    else
        pass_count = pass_count + 1
    end
end

-- Mock environment for skkeleton and feedkeys
local mock = {
    is_enabled = false,
    enabled_count = 0,
    disabled_count = 0,
    handle_calls = {},
    feedkeys_calls = {},
    config = {
        markerHenkan = "▽",
        markerHenkanSelect = "▼",
    },
}

vim.fn["skkeleton#is_enabled"] = function()
    return mock.is_enabled
end

vim.fn["skkeleton#enable"] = function()
    mock.enabled_count = mock.enabled_count + 1
    mock.is_enabled = true
end

vim.fn["skkeleton#disable"] = function()
    mock.disabled_count = mock.disabled_count + 1
    mock.is_enabled = false
end

vim.fn["skkeleton#handle"] = function(func, opts)
    table.insert(mock.handle_calls, { func = func, opts = opts })
    return ""
end

vim.fn["skkeleton#get_config"] = function()
    return mock.config
end

local orig_feedkeys = vim.api.nvim_feedkeys
vim.api.nvim_feedkeys = function(keys, mode, escape_ks)
    table.insert(mock.feedkeys_calls, { keys = keys, mode = mode, escape_ks = escape_ks })
end

local function reset_mock()
    mock.is_enabled = false
    mock.enabled_count = 0
    mock.disabled_count = 0
    mock.handle_calls = {}
    mock.feedkeys_calls = {}
    mock.config = {
        markerHenkan = "▽",
        markerHenkanSelect = "▼",
    }
end

local picker = require("skkeleton-for-pickers")
local buffer = require("skkeleton-for-pickers.buffer")
local state = require("skkeleton-for-pickers.state")

-- Test 1: TelescopePrompt buffer setup & state encapsulation
print("Running Test 1: TelescopePrompt buffer setup & state encapsulation...")
reset_mock()

picker.setup({
    pickers = {
        telescope = { enabled = true },
    },
})

local buf1 = vim.api.nvim_create_buf(false, true)
vim.bo[buf1].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf1)

local orig_cr_called = 0
vim.keymap.set("i", "<CR>", function()
    orig_cr_called = orig_cr_called + 1
end, { buffer = buf1 })

buffer.setup_buffer()

assert_true(state.is_skk_enabled(buf1), "Buffer should be marked as skk_enabled")
assert_true(state.is_cr_wrapped(buf1), "Buffer should be marked as cr_wrapped")
local saved_orig = state.get_original_cr(buf1)
assert_true(saved_orig ~= nil, "Original CR map should be saved in state")
assert_eq(type(saved_orig.callback), "function", "Saved original CR should have callback function")

-- Test 2: CR key handling - callback_direct path
print("Running Test 2: CR key handling - callback_direct path...")
local buf2 = vim.api.nvim_create_buf(false, true)
vim.bo[buf2].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf2)
reset_mock()

local orig_cr_called = 0
vim.keymap.set("i", "<CR>", function()
    orig_cr_called = orig_cr_called + 1
end, { buffer = buf2 })
buffer.setup_buffer()

-- Case 2-A: Skkeleton disabled -> disables skkeleton and runs original callback
reset_mock()
orig_cr_called = 0
buffer.handle_cr_key(buf2)
assert_eq(mock.disabled_count, 1, "Should call skkeleton#disable when CR pressed")
assert_eq(orig_cr_called, 1, "Original callback should be executed directly")

-- Case 2-B: Skkeleton enabled with marker -> confirms conversion, does NOT disable skkeleton
reset_mock()
mock.is_enabled = true
orig_cr_called = 0
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "▽とうきょう" })
buffer.handle_cr_key(buf2)
assert_eq(#mock.handle_calls, 1, "Should send handleKey to skkeleton")
assert_eq(mock.handle_calls[1].func, "handleKey", "Function should be handleKey")
assert_eq(mock.disabled_count, 0, "Skkeleton should NOT be disabled when marker is present")
assert_eq(orig_cr_called, 0, "Original callback should NOT be executed when marker is present")

-- Case 2-C: Skkeleton enabled without marker -> disables skkeleton and executes original callback
reset_mock()
mock.is_enabled = true
orig_cr_called = 0
vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "とうきょう" })
buffer.handle_cr_key(buf2)
assert_eq(mock.disabled_count, 1, "Should disable skkeleton when no marker present")
assert_eq(orig_cr_called, 1, "Original callback should be executed when no marker present")

-- Test 3: CR key handling - rhs_direct path
print("Running Test 3: CR key handling - rhs_direct path...")
reset_mock()

local buf_rhs = vim.api.nvim_create_buf(false, true)
vim.bo[buf_rhs].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf_rhs)

vim.keymap.set("i", "<CR>", "<Cmd>confirm<CR>", { buffer = buf_rhs, noremap = true })
buffer.setup_buffer()

local saved_rhs_orig = state.get_original_cr(buf_rhs)
assert_true(saved_rhs_orig ~= nil, "Original rhs CR map should be saved")
assert_eq(saved_rhs_orig.rhs, "<Cmd>confirm<CR>", "Original rhs should match")

-- When CR is pressed without marker, rhs_direct should feed keys via nvim_feedkeys
reset_mock()
mock.is_enabled = false
buffer.handle_cr_key(buf_rhs)
assert_eq(mock.disabled_count, 1, "Should call skkeleton#disable")
assert_eq(#mock.feedkeys_calls, 1, "Should feed keys for rhs_direct")
local expected_rhs_termcodes = vim.api.nvim_replace_termcodes("<Cmd>confirm<CR>", true, true, true)
assert_eq(mock.feedkeys_calls[1].keys, expected_rhs_termcodes, "Should feed the termcode-replaced rhs keys")

-- Test 4: CR key handling - fallback path (via setup_buffer when no original mapping exists)
print("Running Test 4: CR key handling - fallback path (via setup_buffer)...")
local buf_fallback = vim.api.nvim_create_buf(false, true)
vim.bo[buf_fallback].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf_fallback)

-- Reset mock after buffer switch (BufLeave on previous buffer will have fired)
reset_mock()

-- Call setup_buffer on a prompt buffer that has NO <CR> keymap
buffer.setup_buffer()

-- find_cr_map returns nil, so save_original_cr is skipped and original_cr remains nil
assert_true(state.get_original_cr(buf_fallback) == nil, "original_cr should be nil when no CR map exists")
assert_true(state.is_cr_wrapped(buf_fallback) == false, "cr_wrapped should be false when no CR map exists")

-- Trigger handle_cr_key; since original_cr is nil, core.eval_original_cr_plan returns fallback plan
buffer.handle_cr_key(buf_fallback)
assert_eq(mock.disabled_count, 1, "Should call skkeleton#disable")
assert_eq(#mock.feedkeys_calls, 1, "Should feed fallback <CR> key")
local expected_fallback_cr = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
assert_eq(mock.feedkeys_calls[1].keys, expected_fallback_cr, "Fallback keys should be termcode <CR>")

-- Test 5: skkeleton-enable-post re-wrapping on TelescopePrompt
print("Running Test 5: skkeleton-enable-post re-wrapping on TelescopePrompt...")
local buf5 = vim.api.nvim_create_buf(false, true)
vim.bo[buf5].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf5)
reset_mock()

vim.keymap.set("i", "<CR>", function() end, { buffer = buf5 })
buffer.setup_buffer()
assert_true(state.is_cr_wrapped(buf5), "Buffer should be wrapped initially")

-- Simulate skkeleton enabling and overwriting buffer-local mappings
vim.keymap.set("i", "<CR>", "<Cmd>call skkeleton#handle('handleKey', {'key': '<CR>'})<CR>", { buffer = buf5 })
local maps_before = vim.api.nvim_buf_get_keymap(buf5, "i")
local has_custom_wrapper = false
for _, m in ipairs(maps_before) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_custom_wrapper = true
    end
end
assert_true(not has_custom_wrapper, "Custom wrapper should be temporarily overwritten by skkeleton")

-- Execute skkeleton-enable-post
buffer.handle_skkeleton_enable_post(false)

local maps_after = vim.api.nvim_buf_get_keymap(buf5, "i")
local rewrapped = false
for _, m in ipairs(maps_after) do
    if m.lhs:upper() == "<CR>" and m.callback then
        rewrapped = true
    end
end
assert_true(rewrapped, "Custom CR wrapper should be re-applied after skkeleton-enable-post")

-- Test 6: BufLeave / BufDelete autocommand disables skkeleton
print("Running Test 6: BufLeave / BufDelete autocommand disables skkeleton...")
local buf6 = vim.api.nvim_create_buf(false, true)
vim.bo[buf6].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf6)
reset_mock()
mock.is_enabled = true

vim.keymap.set("i", "<CR>", function() end, { buffer = buf6 })
buffer.setup_buffer()

-- Leaving buf6 should trigger BufLeave autocmd
local dummy_other_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(dummy_other_buf)

assert_eq(mock.disabled_count, 1, "Leaving TelescopePrompt buffer should call skkeleton#disable via BufLeave")

-- Cleanup buffers
local buffers_to_delete = { buf1, buf2, buf_rhs, buf_fallback, buf5, buf6, dummy_other_buf }
for _, b in ipairs(buffers_to_delete) do
    if b and vim.api.nvim_buf_is_valid(b) then
        vim.api.nvim_buf_delete(b, { force = true })
    end
end

-- Restore feedkeys
vim.api.nvim_feedkeys = orig_feedkeys

print(string.format("\ntelescope_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
