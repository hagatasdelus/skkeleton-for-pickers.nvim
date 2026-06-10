-- tests/minipick_test.lua
package.path = vim.fn.getcwd() .. "/lua/?.lua;" .. vim.fn.getcwd() .. "/lua/?/init.lua;" .. package.path

local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        fail_count = fail_count + 1
        print(
            string.format("FAIL: expected '%s', got '%s'. Context: %s", tostring(expected), tostring(actual), msg or "")
        )
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

vim.fn.getcharstr = orig_fn_getcharstr
_G.skkeleton_pickers_minipick_patched = nil
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

_G.MiniPick.opts = {
    source = {},
    mappings = {},
}
function _G.MiniPick.get_picker_items()
    return {}
end
function _G.MiniPick.is_picker_active()
    return _G.MiniPick.is_picker_active_val
end
function _G.MiniPick.get_picker_query()
    return _G.MiniPick.active_picker.query
end
function _G.MiniPick.get_picker_opts()
    return _G.MiniPick.opts
end
function _G.MiniPick.set_picker_opts(opts)
    _G.MiniPick.opts = opts
end
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

vim.fn.getcharstr = orig_fn_getcharstr
_G.skkeleton_pickers_minipick_patched = nil
vim.fn.getcharstr = function()
    return fed_char
end

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
-- When result contains \8 but preedit was active (▽u), backspaces erase old preedit, not confirmed text
_G.MiniPick = {
    active_picker = {
        query = { "あ", "い", "▽", "u" },
        caret = 5,
    },
    is_picker_active_val = true,
    default_match_opts = nil,
}
function _G.MiniPick.default_match() end
function _G.MiniPick.get_picker_query()
    return _G.MiniPick.active_picker.query
end
function _G.MiniPick.is_picker_active()
    return _G.MiniPick.is_picker_active_val
end
function _G.MiniPick.set_picker_query(query)
    _G.MiniPick.active_picker.query = query
end

mock.preedit = ""
-- Mock a backspace-led confirmed result
picker_henkan.setup({ mini_pick = true })
-- Set prev_preedit to the old preedit that backspaces target
package.loaded["skkeleton-pickers.minipick"].prev_preedit = "▽u"
-- Mock getPreEdit to return empty (conversion confirmed)
local orig_denops_request_L = vim.fn["denops#request"]
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return ""
    end
    return orig_denops_request_L(plugin, method, args)
end
package.loaded["skkeleton-pickers.minipick"].process_skk_result("\8\8う")
vim.fn["denops#request"] = orig_denops_request_L
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
-- When result contains "▽k" and getPreEdit returns "▽k", it must not duplicate "k" in the query
_G.MiniPick = {
    active_picker = {
        query = {},
        caret = 1,
    },
    is_picker_active_val = true,
    default_match_opts = nil,
}
function _G.MiniPick.default_match() end
function _G.MiniPick.get_picker_query()
    return _G.MiniPick.active_picker.query
end
function _G.MiniPick.is_picker_active()
    return _G.MiniPick.is_picker_active_val
end
function _G.MiniPick.set_picker_query(query)
    _G.MiniPick.active_picker.query = query
end

-- Reset prev_preedit to empty (first key press, no prior preedit)
package.loaded["skkeleton-pickers.minipick"].prev_preedit = ""

-- Mock denops#request to return "▽k" for getPreEdit
local orig_denops_request = vim.fn["denops#request"]
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "▽k"
    end
    return orig_denops_request(plugin, method, args)
end

-- result = "▽k" (from preEdit.output with #current="")
-- getPreEdit() = "▽k"
-- kakutei = "" (result == cur_preedit, no confirmed text)
-- query = {} + preedit "▽k" = {"▽", "k"}
package.loaded["skkeleton-pickers.minipick"].process_skk_result("▽k")
local q_case_n = _G.MiniPick.get_picker_query()
assert_eq(#q_case_n, 2, "Query should have 2 characters ('▽', 'k')")
assert_eq(q_case_n[1], "▽", "First char should be '▽'")
assert_eq(q_case_n[2], "k", "Second char should be 'k'")

-- Case O: Sequential preedit update (ki → き)
-- Simulates typing 'i' after K (henkan_start), so preedit transitions from ▽k to ▽き
_G.MiniPick.active_picker.query = { "▽", "k" }
-- prev_preedit is "▽k" from Case N
-- getPreEdit returns "▽き" now
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "▽き"
    end
    return orig_denops_request(plugin, method, args)
end
-- result = "\b\b▽き" (2 BS to erase "▽k" segments, then new preedit)
package.loaded["skkeleton-pickers.minipick"].process_skk_result("\8\8▽き")
local q_case_o = _G.MiniPick.get_picker_query()
assert_eq(#q_case_o, 2, "Query should have 2 characters ('▽', 'き')")
assert_eq(q_case_o[1], "▽", "First char should be '▽'")
assert_eq(q_case_o[2], "き", "Second char should be 'き'")

-- Case P: Henkan confirmation (▽き → 機)
-- Simulates pressing space to confirm conversion
_G.MiniPick.active_picker.query = { "▽", "き" }
-- prev_preedit is "▽き" from Case O
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "" -- preedit is now empty (confirmed)
    end
    return orig_denops_request(plugin, method, args)
end
-- result = "\b\b機" (2 BS for "▽き" segments, then confirmed "機")
package.loaded["skkeleton-pickers.minipick"].process_skk_result("\8\8機")
local q_case_p = _G.MiniPick.get_picker_query()
assert_eq(#q_case_p, 1, "Query should have 1 character ('機')")
assert_eq(q_case_p[1], "機", "First char should be '機'")

-- Case Q: Consonant append during preedit (▽き → ▽きn)
-- Simulates typing 'n' after '▽き', so preedit is "▽きn" and skkeleton returns "n"
_G.MiniPick.active_picker.query = { "▽", "き" }
package.loaded["skkeleton-pickers.minipick"].prev_preedit = "▽き"
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "▽きn"
    end
    return orig_denops_request(plugin, method, args)
end
-- result = "n" (from preEdit.output where next starts with #current)
package.loaded["skkeleton-pickers.minipick"].process_skk_result("n")
local q_case_q = _G.MiniPick.get_picker_query()
assert_eq(#q_case_q, 3, "Query should have 3 characters ('▽', 'き', 'n')")
assert_eq(q_case_q[1], "▽", "First char should be '▽'")
assert_eq(q_case_q[2], "き", "Second char should be 'き'")
assert_eq(q_case_q[3], "n", "Third char should be 'n'")

-- Case R: Consonant input duplication (sora -> そら)
-- Simulates sequential typing of s, o, r, a in direct mode (no marker).
_G.MiniPick.active_picker.query = {}
package.loaded["skkeleton-pickers.minipick"].prev_preedit = ""

-- 1. Type 's' -> getPreEdit returns 's', result = 's'
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "s"
    end
    return orig_denops_request(plugin, method, args)
end
package.loaded["skkeleton-pickers.minipick"].process_skk_result("s")
local q_r1 = _G.MiniPick.get_picker_query()
assert_eq(#q_r1, 1, "Query should have 1 character after 's'")
assert_eq(q_r1[1], "s", "Char should be 's'")

-- 2. Type 'o' -> getPreEdit returns '', result = '\8そ'
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return ""
    end
    return orig_denops_request(plugin, method, args)
end
package.loaded["skkeleton-pickers.minipick"].process_skk_result("\8そ")
local q_r2 = _G.MiniPick.get_picker_query()
assert_eq(#q_r2, 1, "Query should have 1 character after 'o'")
assert_eq(q_r2[1], "そ", "Char should be 'そ'")

-- 3. Type 'r' -> getPreEdit returns 'r', result = 'r'
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "r"
    end
    return orig_denops_request(plugin, method, args)
end
package.loaded["skkeleton-pickers.minipick"].process_skk_result("r")
local q_r3 = _G.MiniPick.get_picker_query()
assert_eq(#q_r3, 2, "Query should have 2 characters after 'r'")
assert_eq(q_r3[1], "そ", "First char should be 'そ'")
assert_eq(q_r3[2], "r", "Second char should be 'r'")

-- 4. Type 'a' -> getPreEdit returns '', result = '\8ら'
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return ""
    end
    return orig_denops_request(plugin, method, args)
end
package.loaded["skkeleton-pickers.minipick"].process_skk_result("\8ら")
local q_r4 = _G.MiniPick.get_picker_query()
assert_eq(#q_r4, 2, "Query should have 2 characters after 'a'")
assert_eq(q_r4[1], "そ", "First char should be 'そ'")
assert_eq(q_r4[2], "ら", "Second char should be 'ら'")

-- Case S: Delete key handling (<Del> input on active preedit)
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\8\8\8\8\8▽からす"

_G.MiniPick.active_picker.query = { "▽", "か", "ら", "す", "ま" }
package.loaded["skkeleton-pickers.minipick"].prev_preedit = "▽からすま"

local del_termcode = vim.api.nvim_replace_termcodes("<Del>", true, true, true)
fed_char = del_termcode

-- Mock getPreEdit to return "▽からす"
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "▽からす"
    end
    return orig_denops_request(plugin, method, args)
end

res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Delete key should be intercepted and routed")
assert_eq(#mock.handle_calls, 1, "Should route to skkeleton")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should handleKey")
assert_eq(mock.handle_calls[1].opts.key[1], "\x08", "Del key should be converted to BS when routed to skkeleton")

local q_case_s = _G.MiniPick.get_picker_query()
assert_eq(#q_case_s, 4, "Query should have 4 characters ('▽', 'か', 'ら', 'す')")
assert_eq(q_case_s[1], "▽", "First char")
assert_eq(q_case_s[4], "す", "Fourth char")

-- Case T: Backspace key termcode handling (<BS> termcode input on active preedit)
mock.is_enabled = true
mock.handle_calls = {}
mock.handle_return = "\8\8\8\8\8▽からす"

_G.MiniPick.active_picker.query = { "▽", "か", "ら", "す", "ま" }
package.loaded["skkeleton-pickers.minipick"].prev_preedit = "▽からすま"

local bs_termcode = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
fed_char = bs_termcode

-- Mock getPreEdit to return "▽からす"
vim.fn["denops#request"] = function(plugin, method, args)
    if plugin == "skkeleton" and method == "getPreEdit" then
        return "▽からす"
    end
    return orig_denops_request(plugin, method, args)
end

res = vim.fn.getcharstr()
assert_eq(res, "\x1c", "Backspace termcode should be intercepted and routed")
assert_eq(#mock.handle_calls, 1, "Should route to skkeleton")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should handleKey")
assert_eq(
    mock.handle_calls[1].opts.key[1],
    "\x08",
    "BS termcode should be converted to ASCII BS when routed to skkeleton"
)

local q_case_t = _G.MiniPick.get_picker_query()
assert_eq(#q_case_t, 4, "Query should have 4 characters")
assert_eq(q_case_t[1], "▽", "First char")
assert_eq(q_case_t[4], "す", "Fourth char")

vim.fn["denops#request"] = orig_denops_request

-- Case U: default_match wrapping behavior with markers (▽/▼)
reset_mock()
mock.is_enabled = true
local passed_query_to_orig_match = nil
_G.MiniPick = {
    active_picker = { query = {}, caret = 1 },
    is_picker_active_val = true,
}
function _G.MiniPick.default_match(stritems, inds, query, opts)
    passed_query_to_orig_match = query
    return inds
end

-- Re-wrap default_match (normally done by wrap_default_match)
package.loaded["skkeleton-pickers.minipick"].skkeleton_pickers_wrapped = nil
package.loaded["skkeleton-pickers.minipick"].wrap_default_match()

MiniPick.default_match({}, { 1 }, { "▽", "か", "▼", "な" }, {})
assert_eq(#passed_query_to_orig_match, 2, "Marker characters should be stripped from query in default_match")
assert_eq(passed_query_to_orig_match[1], "か", "First char should be 'か'")
assert_eq(passed_query_to_orig_match[2], "な", "Second char should be 'な'")

-- Case V: Dynamic options wrapping on handle_picker_char
reset_mock()
mock.is_enabled = true
local passed_query_to_custom_match = nil
local set_picker_opts_called = false

local test_opts = {
    source = {
        match = function(stritems, inds, query, opts_match)
            passed_query_to_custom_match = query
            return inds
        end,
    },
    mappings = {},
}

_G.MiniPick = {
    active_picker = { query = {}, caret = 1 },
    is_picker_active_val = true,
    get_picker_opts = function()
        return test_opts
    end,
    set_picker_opts = function(opts)
        set_picker_opts_called = true
        test_opts = opts
    end,
    is_picker_active = function()
        return true
    end,
    get_picker_query = function()
        return { "▽", "て", "s", "u" }
    end,
    set_picker_query = function(q) end,
}

local minipick_mod = package.loaded["skkeleton-pickers.minipick"]
minipick_mod.handle_picker_char("a")

assert_true(set_picker_opts_called, "MiniPick.set_picker_opts should be called during handle_picker_char")
assert_true(test_opts.mappings.skkeleton_pickers_ignore ~= nil, "skkeleton_pickers_ignore mapping should be added")
assert_eq(test_opts.mappings.skkeleton_pickers_ignore.char, "\x1c", "ignore char should be Ctrl-\\")
assert_eq(type(test_opts.mappings.skkeleton_pickers_ignore.func), "function", "ignore func should be a function")

assert_true(test_opts.source.match ~= nil, "source.match should exist")
test_opts.source.match({}, { 1 }, { "▽", "て", "s", "u" }, {})
assert_true(passed_query_to_custom_match ~= nil, "Custom match function should be called")
assert_eq(#passed_query_to_custom_match, 3, "Marker characters should be stripped from query in custom match")
assert_eq(passed_query_to_custom_match[1], "て", "First char should be 'て'")
assert_eq(passed_query_to_custom_match[2], "s", "Second char")
assert_eq(passed_query_to_custom_match[3], "u", "Third char")

vim.fn.getcharstr = orig_fn_getcharstr
_G.MiniPick = nil

print(string.format("\nminipick_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
