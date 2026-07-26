-- spec/skkeleton-pickers_spec.lua
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

-- Setup mock environment for skkeleton
local mock = {
    is_enabled = false,
    enabled_count = 0,
    disabled_count = 0,
    handle_calls = {},
    handle_return = "\b\b\b漢字",
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
    if func == "enable" then
        mock.enabled_count = mock.enabled_count + 1
        mock.is_enabled = true
    elseif func == "disable" then
        mock.disabled_count = mock.disabled_count + 1
        mock.is_enabled = false
    end
    return mock.handle_return
end

vim.fn["skkeleton#get_config"] = function()
    return mock.config
end

vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "handle" then
        local func = args[1]
        local opts = args[2]
        table.insert(mock.handle_calls, { func = func, opts = opts })
        if func == "enable" then
            mock.enabled_count = mock.enabled_count + 1
            mock.is_enabled = true
        elseif func == "disable" then
            mock.disabled_count = mock.disabled_count + 1
            mock.is_enabled = false
        end
        return {
            state = vim.g["skkeleton#state"],
            result = mock.handle_return,
        }
    end
end

local function reset_mock()
    mock.is_enabled = false
    mock.enabled_count = 0
    mock.disabled_count = 0
    mock.handle_calls = {}
    mock.handle_return = "\b\b\b漢字"
    mock.config = {
        markerHenkan = "▽",
        markerHenkanSelect = "▼",
    }
end

-- Helper assertion functions
local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error(
            string.format(
                "Assertion failed: expected '%s', got '%s'. Context: %s",
                tostring(expected),
                tostring(actual),
                msg or ""
            ),
            2
        )
    end
end

local function assert_true(cond, msg)
    if not cond then
        error(string.format("Assertion failed: expected true, got false. Context: %s", msg or ""), 2)
    end
end

-- Load the plugin
local picker = require("skkeleton-pickers")

-- Test 1: Config merging
print("Running Test 1: Config merging...")
picker.setup({
    pickers = {
        telescope = { enabled = true },
    },
})
assert_eq(picker.config.pickers.telescope.enabled, true, "telescope should be enabled")
assert_eq(picker.config.pickers.mini_pick.enabled, false, "mini_pick should default to false")

-- Test 2: Buffer Setup and Keymaps
print("Running Test 2: Buffer Setup and Keymaps...")
reset_mock()
vim.keymap.set("i", "<C-j>", "<Plug>(skkeleton-toggle)", { noremap = true })

-- Re-setup for testing
picker.setup({
    pickers = {
        telescope = { enabled = true },
    },
})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, "TestTelescopePrompt")

-- Mock a buffer-local <CR> mapping (like a picker would have)
local original_cr_called = 0
vim.keymap.set("i", "<CR>", function()
    original_cr_called = original_cr_called + 1
end, { buffer = buf })

-- Set filetype to trigger autocmd
vim.bo[buf].filetype = "TelescopePrompt"

-- Call setup_buffer manually for our test buffer (or trigger autocmd)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_exec_autocmds("FileType", { group = "SkkeletonPickers", buffer = buf })

-- Wait slightly for any scheduled callback (like keymap wrapping)
vim.wait(20, function()
    return false
end)

-- Verify toggle keymap is set on the buffer
local maps = vim.api.nvim_buf_get_keymap(buf, "i")
local found_toggle = false
local found_cr = nil

for _, m in ipairs(maps) do
    local lhs = m.lhs:upper()
    if lhs == "<C-J>" then
        found_toggle = true
    elseif lhs == "<CR>" then
        found_cr = m
    end
end

assert_true(found_toggle, "Toggle keymap should be dynamically created")
assert_true(found_cr ~= nil, "CR keymap should be created")

-- Test 3: CR Mapping execution behavior
print("Running Test 3: CR Mapping execution behavior...")

-- Case A: Skkeleton disabled — should call the original picker callback
print("  Case A: Skkeleton disabled")
original_cr_called = 0
reset_mock()

local cr_callback = found_cr.callback
assert_true(type(cr_callback) == "function", "CR mapping must have a callback function")
cr_callback()

-- The original callback is called directly (not via feedkeys)
assert_eq(mock.disabled_count, 1, "Should call skkeleton#disable (idempotent no-op when disabled)")
assert_eq(original_cr_called, 1, "Original CR callback should be executed when skkeleton is disabled")

-- Case B: Skkeleton enabled, line has marker (▽ or ▼) — should delegate to
-- skkeleton's own <CR> mapping by removing ours and feeding <CR>
print("  Case B: Skkeleton enabled with marker")
original_cr_called = 0
reset_mock()
mock.is_enabled = true

-- Set buffer line with marker
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "▼かんじ" })

-- We need to re-apply the CR map because it may have been removed in test
-- infrastructure — get the fresh callback
maps = vim.api.nvim_buf_get_keymap(buf, "i")
found_cr = nil
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" then
        found_cr = m
        break
    end
end
-- If the mapping was removed by Case A's test, re-apply it
if not found_cr then
    -- Re-trigger setup
    vim.api.nvim_exec_autocmds("InsertEnter", { group = "SkkeletonPickers", buffer = buf })
    vim.wait(20, function()
        return false
    end)
    maps = vim.api.nvim_buf_get_keymap(buf, "i")
    for _, m in ipairs(maps) do
        if m.lhs:upper() == "<CR>" then
            found_cr = m
            break
        end
    end
end
assert_true(found_cr ~= nil, "CR mapping must exist for Case B")

cr_callback = found_cr.callback
cr_callback()

-- When markers are present, we should call skkeleton#handle directly with \n (NL) to confirm conversion
assert_eq(#mock.handle_calls, 1, "Should call skkeleton#handle once")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should call handleKey")
assert_eq(mock.handle_calls[1].opts.key, "\n", "Should pass NL key")
-- skkeleton should NOT be disabled when markers are present
assert_eq(mock.disabled_count, 0, "Should NOT disable skkeleton when marker is present")
-- Original picker callback should NOT be called when doing conversion
assert_eq(original_cr_called, 0, "Original CR should NOT be called when marker is present")

-- Case C: Skkeleton enabled, line has NO marker — should disable skkeleton
-- and feed <CR> to trigger the picker's file selection
print("  Case C: Skkeleton enabled without marker")
original_cr_called = 0
reset_mock()
mock.is_enabled = true

-- Re-apply our mapping since Case B may have removed it
-- We need to manually re-apply since skkeleton-enable-post won't fire in test
vim.b[buf].skkeleton_pickers_cr_wrapped = false
vim.b[buf].skkeleton_pickers_setup = true -- prevent re-setup of default mode

-- Re-set the original CR mapping that would have been restored by skkeleton#disable
vim.keymap.set("i", "<CR>", function()
    original_cr_called = original_cr_called + 1
end, { buffer = buf })

-- Now re-trigger setup to wrap it
vim.api.nvim_exec_autocmds("InsertEnter", { group = "SkkeletonPickers", buffer = buf })
vim.wait(20, function()
    return false
end)

maps = vim.api.nvim_buf_get_keymap(buf, "i")
found_cr = nil
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" then
        found_cr = m
        break
    end
end
assert_true(found_cr ~= nil, "CR mapping must exist for Case C")

-- Set buffer line without marker
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "かんじ" })
cr_callback = found_cr.callback
cr_callback()

assert_eq(mock.disabled_count, 1, "Should disable skkeleton when no marker")
-- Note: the original CR is called via feedkeys, which won't execute in
-- headless test. We verify that disable was called which is the key behavior.

-- Case D: Skkeleton enabled with custom markers
print("  Case D: Skkeleton enabled with custom markers")
original_cr_called = 0
reset_mock()
mock.is_enabled = true
mock.config.markerHenkan = "["
mock.config.markerHenkanSelect = "]"

-- Re-apply mapping
vim.b[buf].skkeleton_pickers_cr_wrapped = false
vim.keymap.set("i", "<CR>", function()
    original_cr_called = original_cr_called + 1
end, { buffer = buf })
vim.api.nvim_exec_autocmds("InsertEnter", { group = "SkkeletonPickers", buffer = buf })
vim.wait(20, function()
    return false
end)

maps = vim.api.nvim_buf_get_keymap(buf, "i")
found_cr = nil
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" then
        found_cr = m
        break
    end
end
assert_true(found_cr ~= nil, "CR mapping must exist for Case D")

-- Set buffer line with custom select marker
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "]かんじ" })
cr_callback = found_cr.callback
cr_callback()

-- Should call skkeleton#handle with \n (NL) to confirm conversion with custom marker
assert_eq(#mock.handle_calls, 1, "Should call skkeleton#handle once with custom marker")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should call handleKey")
assert_eq(mock.handle_calls[1].opts.key, "\n", "Should pass NL key")
assert_eq(mock.disabled_count, 0, "Should NOT disable skkeleton when custom marker is present")
assert_eq(original_cr_called, 0, "Original CR should NOT be called when custom marker is present")

-- Test 5: skkeleton-enable-post autocmd re-applies CR mapping
print("Running Test 5: skkeleton-enable-post re-applies CR mapping...")
reset_mock()

-- Create a new buffer
local buf3 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf3, "TestTelescopePrompt3")
vim.keymap.set("i", "<CR>", function() end, { buffer = buf3 })

picker.setup({
    pickers = {
        telescope = { enabled = true },
    },
})
reset_mock()

vim.bo[buf3].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf3)
vim.api.nvim_exec_autocmds("FileType", { group = "SkkeletonPickers", buffer = buf3 })

-- Verify CR is wrapped
maps = vim.api.nvim_buf_get_keymap(buf3, "i")
local has_cr_map = false
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_cr_map = true
    end
end
assert_true(has_cr_map, "CR mapping should be wrapped initially")
assert_true(vim.b[buf3].skkeleton_pickers_cr_wrapped == true, "Buffer should be marked as wrapped")

-- Simulate skkeleton overwriting our CR mapping (as skkeleton#map does)
vim.keymap.set("i", "<CR>", "<Cmd>echo 'skkeleton'<CR>", { buffer = buf3, noremap = true, nowait = true })

-- Verify our mapping is gone
maps = vim.api.nvim_buf_get_keymap(buf3, "i")
has_cr_map = false
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_cr_map = true
    end
end
assert_true(not has_cr_map, "Our CR callback mapping should be overwritten by skkeleton")

-- Fire skkeleton-enable-post
vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-enable-post" })

-- Verify our mapping is re-applied
maps = vim.api.nvim_buf_get_keymap(buf3, "i")
has_cr_map = false
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_cr_map = true
    end
end
assert_true(has_cr_map, "CR mapping should be re-applied after skkeleton-enable-post")

-- Test 6: mini.pick integration via getcharstr monkeypatch
print("Running Test 6: mini.pick integration via getcharstr monkeypatch...")
reset_mock()

-- Mock vim.fn.getcharstr BEFORE loading/setting up
local fed_char = "a"
local orig_fn_getcharstr = vim.fn.getcharstr
vim.fn.getcharstr = function()
    return fed_char
end

-- Clear package cache and reload
package.loaded["skkeleton-pickers"] = nil
local picker_new = require("skkeleton-pickers")

-- Mock MiniPick global table
_G.MiniPick = {
    active_picker = {
        query = { "a" },
        caret = 2,
    },
    is_picker_active_val = true,
    default_match_opts = nil,
}

function _G.MiniPick.default_match(stritems, inds, query, opts)
    _G.MiniPick.default_match_opts = opts
    return inds
end

function _G.MiniPick.get_picker_items()
    return {}
end

function _G.MiniPick.is_picker_active()
    return _G.MiniPick.is_picker_active_val
end

function _G.MiniPick.get_picker_query()
    return _G.MiniPick.active_picker.query
end

function _G.MiniPick.set_picker_query(query)
    _G.MiniPick.active_picker.query = query
    _G.MiniPick.active_picker.caret = #query + 1
    _G.MiniPick.default_match({}, {}, query, {})
end

-- Setup with mini.pick enabled
picker_new.setup({
    pickers = {
        mini_pick = { enabled = true },
    },
})

-- Simulate MiniPickStart event
vim.api.nvim_exec_autocmds("User", { pattern = "MiniPickStart" })

-- Case A: Skkeleton disabled, MiniPick active
-- Typing "b" should pass through directly
mock.is_enabled = false
fed_char = "b"
local res = vim.fn.getcharstr()
assert_eq(res, "b", "Keys should pass through to mini.pick when skkeleton is disabled")

-- Case B: Derived toggle key
-- Typing derived toggle key (<C-j>) should enable skkeleton and return \x1c
vim.keymap.set("i", "<C-j>", "<Plug>(skkeleton-toggle)", { noremap = true })
mock.is_enabled = false
fed_char = vim.api.nvim_replace_termcodes("<C-j>", true, true, true)
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Derived toggle key should be intercepted and return ignore character")
assert_true(mock.is_enabled, "Skkeleton should be enabled after toggle keypress")

-- Case C: Skkeleton enabled, printable key
-- Mock skkeleton#handle to return "\bか"
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\bか"

_G.MiniPick.active_picker.query = { "k" }
fed_char = "a"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Printable key should be intercepted and return ignore character")
assert_eq(#mock.handle_calls, 1, "Should route key to skkeleton")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should handleKey")
assert_eq(mock.handle_calls[1].opts.key[1], "a", "Should pass 'a' key")
-- Check query was updated: "k" was popped, "か" was appended
local q = _G.MiniPick.get_picker_query()
assert_eq(#q, 1, "Query should have 1 character")
assert_eq(q[1], "か", "Query should be updated with Japanese character")
assert_true(_G.MiniPick.default_match_opts ~= nil, "Should have called default_match")
assert_true(_G.MiniPick.default_match_opts.sync == true, "Should have forced opts.sync = true")

-- Case D: Skkeleton enabled, Enter key with marker
_G.MiniPick.active_picker.query = { "▽", "か" }
mock.handle_calls = {}
mock.handle_return = "\b\bか" -- remove ▽か, insert か
fed_char = "\r"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Enter with marker should confirm conversion and return ignore character")
assert_eq(#mock.handle_calls, 1, "Should call handleKey")
assert_eq(mock.handle_calls[1].opts.key[1], "\n", "Should pass NL key to confirm")
q = _G.MiniPick.get_picker_query()
assert_eq(#q, 1, "Query should have 1 character")
assert_eq(q[1], "か", "Query should have confirmed text without marker")

-- Case E: Skkeleton enabled, Enter key without marker
-- Since query is {"か"} (no marker), it should disable skkeleton and return "\r"
_G.MiniPick.active_picker.query = { "か" }
mock.handle_calls = {}
mock.disabled_count = 0
fed_char = "\r"
res = vim.fn.getcharstr()
assert_eq(res, "\r", "Enter without marker should return CR key to select file")
assert_eq(mock.disabled_count, 1, "Should disable skkeleton")

-- Case F: Backspace normalization (\x7f -> \x08 -> <bs>)
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\b"
_G.MiniPick.active_picker.query = { "か" }
fed_char = "\x7f"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Backspace key should be intercepted and return ignore character")
assert_eq(#mock.handle_calls, 1, "Should route backspace to skkeleton")
assert_eq(mock.handle_calls[1].opts.key[1], "\x08", "Should pass normalized backspace key")

-- Case G: Esc with marker (should route to skkeleton)
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\b\bか"
_G.MiniPick.active_picker.query = { "▽", "か" }
fed_char = "\x1b"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Esc with marker should be intercepted and return ignore character")
assert_eq(#mock.handle_calls, 1, "Should route Esc to skkeleton")
assert_eq(mock.handle_calls[1].opts.key[1], "\x1b", "Should pass Esc key")

-- Case H: Esc without marker (should disable skkeleton and return Esc)
mock.is_enabled = true
mock.handle_calls = {}
mock.disabled_count = 0
_G.MiniPick.active_picker.query = { "か" }
fed_char = "\x1b"
res = vim.fn.getcharstr()
assert_eq(res, "\x1b", "Esc without marker should return Esc key to abort picker")
assert_eq(mock.disabled_count, 1, "Should disable skkeleton")

-- Case I: Ctrl-g with marker (should route to skkeleton)
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\b\b"
_G.MiniPick.active_picker.query = { "▽", "か" }
fed_char = "\x07"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Ctrl-g with marker should be intercepted and return ignore character")
assert_eq(#mock.handle_calls, 1, "Should route Ctrl-g to skkeleton")
assert_eq(mock.handle_calls[1].opts.key[1], "\x07", "Should pass Ctrl-g key")

-- Case J: Ctrl-g without marker (should not route to skkeleton, should pass through)
mock.is_enabled = true
mock.handle_calls = {}
_G.MiniPick.active_picker.query = { "か" }
fed_char = "\x07"
res = vim.fn.getcharstr()
assert_eq(res, "\x07", "Ctrl-g without marker should pass through directly")
assert_eq(#mock.handle_calls, 0, "Should NOT route Ctrl-g to skkeleton when no marker")

-- Restore original getcharstr to clean up the test environment
vim.fn.getcharstr = orig_fn_getcharstr
_G.MiniPick = nil

print("All tests passed successfully!")
os.exit(0)
