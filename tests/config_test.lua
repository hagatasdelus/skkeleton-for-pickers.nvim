-- tests/config_test.lua
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

-- Test 1: Config merging
print("Running Test 1: Config merging...")
picker.setup({
    default_mode = "zenkaku",
    toggle_key = "<C-k>",
    telescope = false,
})
assert_eq(picker.config.default_mode, "zenkaku", "default_mode should be updated")
assert_eq(picker.config.toggle_key, "<C-k>", "toggle_key should be updated")
assert_eq(picker.config.telescope, false, "telescope should be disabled")
assert_eq(picker.config.snacks, true, "snacks should default to true")
assert_eq(picker.config.mini_pick, true, "mini_pick should default to true")

-- Test 4: Default Mode application on setup
print("Running Test 4: Default Mode application on setup...")
picker.setup({
    default_mode = "zenkaku",
    toggle_key = "<C-j>",
    telescope = true,
})
reset_mock()
local buf2 = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf2, "TestTelescopePrompt2")
vim.keymap.set("i", "<CR>", function() end, { buffer = buf2 })
vim.bo[buf2].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf2)
vim.api.nvim_exec_autocmds("FileType", { group = "SkkeletonPickers", buffer = buf2 })

assert_eq(mock.enabled_count, 1, "Should automatically enable skkeleton")
assert_eq(#mock.handle_calls, 2, "Should call skkeleton#handle to enable and change mode")
assert_eq(mock.handle_calls[1].func, "enable", "First call should be enable")
assert_eq(mock.handle_calls[2].func, "handleKey", "Second call should be handleKey")
assert_eq(mock.handle_calls[2].opts.key[1], "", "Should send empty key array")
assert_eq(mock.handle_calls[2].opts["function"], "zenkaku", "Should change to zenkaku mode")

print(string.format("\nconfig_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
