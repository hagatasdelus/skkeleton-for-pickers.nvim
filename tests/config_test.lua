-- tests/config_test.lua
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
local picker = require("skkeleton-for-pickers")

-- Test 1: Config merging
print("Running Test 1: Config merging...")
picker.setup({
    pickers = {
        telescope = { enabled = true },
    },
})
assert_eq(picker.config.pickers.telescope.enabled, true, "telescope should be enabled")
assert_eq(picker.config.pickers.mini_pick.enabled, false, "mini_pick should default to false")

-- Test 2: Bypass setup for disabled pickers
print("Running Test 2: Bypass setup for disabled pickers...")
package.loaded["skkeleton-for-pickers"] = nil
package.loaded["skkeleton-for-pickers.config"] = nil
package.loaded["skkeleton-for-pickers.buffer"] = nil
package.loaded["skkeleton-for-pickers.skk"] = nil
package.loaded["skkeleton-for-pickers.minipick"] = nil
_G.skkeleton_for_pickers_minipick_patched = nil

local orig_getcharstr = vim.fn.getcharstr

local picker_bypass = require("skkeleton-for-pickers")
picker_bypass.setup({
    pickers = {
        telescope = { enabled = true },
        mini_pick = { enabled = false },
    },
})

assert_eq(picker_bypass.config.pickers.telescope.enabled, true, "telescope should be enabled")
assert_eq(picker_bypass.config.pickers.mini_pick.enabled, false, "mini_pick should be disabled")

local has_telescope = false
local has_minipick = false
local buffer_mod = require("skkeleton-for-pickers.buffer")
for _, ft in ipairs(buffer_mod.active_fts) do
    if ft == "TelescopePrompt" then
        has_telescope = true
    end
    if ft == "minipick" then
        has_minipick = true
    end
end
assert_eq(has_telescope, true, "active_fts should contain TelescopePrompt")
assert_eq(has_minipick, false, "active_fts should NOT contain minipick")

assert_eq(_G.skkeleton_for_pickers_minipick_patched, nil, "getcharstr should not be patched when mini_pick is disabled")
assert_eq(vim.fn.getcharstr, orig_getcharstr, "getcharstr function pointer should remain unchanged")

-- Test 3: Disabling mini_pick on re-setup restores patch
print("Running Test 3: Disabling mini_pick on re-setup restores patch...")
picker_bypass.setup({
    pickers = {
        mini_pick = { enabled = true },
    },
})
local minipick_mod = require("skkeleton-for-pickers.minipick")
minipick_mod.apply_patch()
assert_eq(
    _G.skkeleton_for_pickers_minipick_patched,
    true,
    "getcharstr should be patched when mini_pick is enabled and active"
)

picker_bypass.setup({
    pickers = {
        mini_pick = { enabled = false },
    },
})
assert_eq(
    _G.skkeleton_for_pickers_minipick_patched,
    nil,
    "getcharstr patch should be restored when mini_pick is re-disabled"
)

-- Test 4: Setup with mini_pick disabled does NOT disable skkeleton in normal buffers
print("Running Test 4: Setup with mini_pick disabled does NOT disable skkeleton in normal buffers...")
reset_mock()
mock.is_enabled = true
local normal_buf = vim.api.nvim_create_buf(false, true)
vim.bo[normal_buf].filetype = "markdown"
vim.api.nvim_set_current_buf(normal_buf)

picker_bypass.setup({
    pickers = {
        telescope = { enabled = true },
        mini_pick = { enabled = false },
    },
})

assert_eq(
    mock.is_enabled,
    true,
    "skkeleton should remain enabled in normal buffer when running setup with mini_pick disabled"
)
assert_eq(mock.disabled_count, 0, "skkeleton#disable should NOT be called in normal buffer during setup")

print(string.format("\nconfig_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
