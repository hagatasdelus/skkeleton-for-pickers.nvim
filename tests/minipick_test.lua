-- tests/minipick_test.lua
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        fail_count = fail_count + 1
        print(string.format("FAIL: expected '%s', got '%s'. Context: %s", tostring(expected), tostring(actual), msg or ""))
    else
        pass_count = pass_count + 1
    end
end

local function assert_true(cond, msg)
    if not cond then
        fail_count = fail_count + 1
        print(string.format("FAIL: expected true, got false. Context: %s", msg or ""))
    else
        pass_count = pass_count + 1
    end
end

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

-- Load the plugin
local picker = require("skkeleton-pickers")

-- Test 6: mini.pick integration
print("Running Test 6: mini.pick integration via getcharstr monkeypatch...")
reset_mock()

local fed_char = "a"
local orig_fn_getcharstr = vim.fn.getcharstr
vim.fn.getcharstr = function()
    return fed_char
end

package.loaded["skkeleton-pickers"] = nil
package.loaded["skkeleton-pickers.config"] = nil
package.loaded["skkeleton-pickers.buffer"] = nil
package.loaded["skkeleton-pickers.skk"] = nil
package.loaded["skkeleton-pickers.minipick"] = nil
local picker_new = require("skkeleton-pickers")

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

function _G.MiniPick.get_picker_items() return {} end
function _G.MiniPick.is_picker_active() return _G.MiniPick.is_picker_active_val end
function _G.MiniPick.get_picker_query() return _G.MiniPick.active_picker.query end
function _G.MiniPick.set_picker_query(query)
    _G.MiniPick.active_picker.query = query
    _G.MiniPick.active_picker.caret = #query + 1
    _G.MiniPick.default_match({}, {}, query, {})
end

picker_new.setup({
    mini_pick = true,
    toggle_key = "<C-j>",
    default_mode = "eisu",
})

-- Case A: Skkeleton disabled, MiniPick active
mock.is_enabled = false
fed_char = "b"
local res = vim.fn.getcharstr()
assert_eq(res, "b", "Keys should pass through to mini.pick when skkeleton is disabled")

-- Case B: Toggle key
mock.is_enabled = false
fed_char = "\n"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Toggle key should return ignore character")
assert_true(mock.is_enabled, "Skkeleton should be enabled after toggle keypress")

-- Case C: Skkeleton enabled, printable key
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\bか"
_G.MiniPick.active_picker.query = { "k" }
fed_char = "a"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Printable key should be intercepted")
assert_eq(#mock.handle_calls, 1, "Should route key to skkeleton")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should handleKey")
assert_eq(mock.handle_calls[1].opts.key[1], "a", "Should pass 'a' key")
local q = _G.MiniPick.get_picker_query()
assert_eq(#q, 1, "Query should have 1 character")
assert_eq(q[1], "か", "Query should be updated")

-- Case D: Skkeleton enabled, Enter key with marker
_G.MiniPick.active_picker.query = { "▽", "か" }
mock.handle_calls = {}
mock.handle_return = "\b\bか"
fed_char = "\r"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Enter with marker should confirm conversion")
assert_eq(#mock.handle_calls, 1, "Should call handleKey")
assert_eq(mock.handle_calls[1].opts.key[1], "\n", "Should pass NL key")
q = _G.MiniPick.get_picker_query()
assert_eq(#q, 1, "Query should have 1 character")
assert_eq(q[1], "か", "Query should have confirmed text")

-- Case E: Skkeleton enabled, Enter key without marker
_G.MiniPick.active_picker.query = { "か" }
mock.handle_calls = {}
mock.disabled_count = 0
fed_char = "\r"
res = vim.fn.getcharstr()
assert_eq(res, "\r", "Enter without marker should return CR")
assert_eq(mock.disabled_count, 1, "Should disable skkeleton")

-- Case F: Backspace normalization
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\b"
_G.MiniPick.active_picker.query = { "か" }
fed_char = "\x7f"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Backspace key should be intercepted")
assert_eq(#mock.handle_calls, 1, "Should route backspace to skkeleton")
assert_eq(mock.handle_calls[1].opts.key[1], "\x08", "Should pass normalized backspace")

-- Case G: Esc with marker
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\b\bか"
_G.MiniPick.active_picker.query = { "▽", "か" }
fed_char = "\x1b"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Esc with marker should be intercepted")
assert_eq(#mock.handle_calls, 1, "Should route Esc to skkeleton")
assert_eq(mock.handle_calls[1].opts.key[1], "\x1b", "Should pass Esc")

-- Case H: Esc without marker
mock.is_enabled = true
mock.handle_calls = {}
mock.disabled_count = 0
_G.MiniPick.active_picker.query = { "か" }
fed_char = "\x1b"
res = vim.fn.getcharstr()
assert_eq(res, "\x1b", "Esc without marker should return Esc")
assert_eq(mock.disabled_count, 1, "Should disable skkeleton")

-- Case I: Ctrl-g with marker
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\b\b"
_G.MiniPick.active_picker.query = { "▽", "か" }
fed_char = "\x07"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Ctrl-g with marker should be intercepted")
assert_eq(#mock.handle_calls, 1, "Should route Ctrl-g to skkeleton")
assert_eq(mock.handle_calls[1].opts.key[1], "\x07", "Should pass Ctrl-g")

-- Case J: Ctrl-g without marker
mock.is_enabled = true
mock.handle_calls = {}
_G.MiniPick.active_picker.query = { "か" }
fed_char = "\x07"
res = vim.fn.getcharstr()
assert_eq(res, "\x07", "Ctrl-g without marker should pass through")

-- Case K: Stateful Initialization
mock.is_enabled = false
mock.enabled_count = 0
mock.handle_calls = {}

package.loaded["skkeleton-pickers"] = nil
package.loaded["skkeleton-pickers.config"] = nil
package.loaded["skkeleton-pickers.buffer"] = nil
package.loaded["skkeleton-pickers.skk"] = nil
package.loaded["skkeleton-pickers.minipick"] = nil
local picker_henkan = require("skkeleton-pickers")
picker_henkan.setup({
    mini_pick = true,
    toggle_key = "<C-j>",
    default_mode = "henkan",
})

_G.MiniPick.active_picker.query = { "a" }
fed_char = "b"
res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "User typed key should be intercepted")
assert_true(#mock.handle_calls >= 2, "Should initialize skkeleton on first getcharstr")
assert_eq(mock.handle_calls[1].func, "enable", "Should call enable first")
assert_eq(mock.handle_calls[2].func, "handleKey", "Should call handleKey for mode")
assert_eq(mock.handle_calls[2].opts["function"], "hirakana", "Should set to hirakana")

-- Case L: process_skk_result backspace safety
-- When result contains \8 but preedits are manually stripped, it must NOT delete confirmed text
_G.MiniPick = {
    active_picker = {
        query = { "あ", "い", "▽", "u" },
        caret = 5,
    },
    is_picker_active_val = true,
    default_match_opts = nil,
}
function _G.MiniPick.default_match() end
function _G.MiniPick.get_picker_query() return _G.MiniPick.active_picker.query end
function _G.MiniPick.is_picker_active() return _G.MiniPick.is_picker_active_val end
function _G.MiniPick.set_picker_query(query)
    _G.MiniPick.active_picker.query = query
end

mock.preedit = ""
-- Mock a backspace-led confirmed result
picker_henkan.setup({ mini_pick = true })
package.loaded["skkeleton-pickers.minipick"].process_skk_result("\8\8う")
local final_q = _G.MiniPick.get_picker_query()
assert_eq(#final_q, 3, "Query should have 3 characters ('あ', 'い', 'う')")
assert_eq(final_q[1], "あ", "First char should be 'あ'")
assert_eq(final_q[2], "い", "Second char should be 'い'")
assert_eq(final_q[3], "う", "Third char should be 'う'")

-- Case M: setup_buffer toggle key wrapper when enabled
local buf_toggle = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf_toggle, "TestTelescopePromptToggle")
vim.bo[buf_toggle].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf_toggle)

-- Set is_enabled after all BufLeave autocmds have executed and disabled skkeleton
mock.is_enabled = true

-- Clear any locally mapped <C-j> created by the autocmds
pcall(vim.keymap.del, "i", "<C-j>", { buffer = buf_toggle })

-- Trigger setup_buffer when enabled
package.loaded["skkeleton-pickers.buffer"].setup_buffer()
local toggle_maps = vim.api.nvim_buf_get_keymap(buf_toggle, "i")
local found_custom_toggle = false
for _, m in ipairs(toggle_maps) do
    if m.lhs:upper() == "<C-J>" then
        found_custom_toggle = true
    end
end
assert_true(not found_custom_toggle, "Toggle key should not be mapped locally when skkeleton is enabled")

-- Case N: process_skk_result duplicate key elimination during preedit transition
-- When result contains "k" and getPreEdit returns "▽k", it must not duplicate "k" in the query
_G.MiniPick = {
    active_picker = {
        query = {},
        caret = 1,
    },
    is_picker_active_val = true,
    default_match_opts = nil,
}
function _G.MiniPick.default_match() end
function _G.MiniPick.get_picker_query() return _G.MiniPick.active_picker.query end
function _G.MiniPick.is_picker_active() return _G.MiniPick.is_picker_active_val end
function _G.MiniPick.set_picker_query(query)
    _G.MiniPick.active_picker.query = query
end

-- Mock denops#request to return "▽k" for getPreEdit
local orig_denops_request = vim.fn["denops#request"]
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "▽k"
    end
    return orig_denops_request(plugin, method, args)
end

package.loaded["skkeleton-pickers.minipick"].process_skk_result("k")
local q_case_n = _G.MiniPick.get_picker_query()
assert_eq(#q_case_n, 2, "Query should have 2 characters ('▽', 'k')")
assert_eq(q_case_n[1], "▽", "First char should be '▽'")
assert_eq(q_case_n[2], "k", "Second char should be 'k'")

vim.fn["denops#request"] = orig_denops_request

vim.fn.getcharstr = orig_fn_getcharstr
_G.MiniPick = nil

print(string.format("\nminipick_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
