-- tests/buffer_test.lua
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

-- Test 2: Buffer Setup and Keymaps
print("Running Test 2: Buffer Setup and Keymaps...")
reset_mock()

-- Set user skkeleton keymaps for testing derivation
vim.keymap.set("i", "<C-j>", "<Plug>(skkeleton-toggle)", { noremap = true })
vim.keymap.set("n", "<C-j>", "a<Plug>(skkeleton-enable)", { noremap = true })

picker.setup({
    pickers = {
        telescope = { enabled = true },
    },
})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, "TestTelescopePrompt")

local original_cr_called = 0
vim.keymap.set("i", "<CR>", function()
    original_cr_called = original_cr_called + 1
end, { buffer = buf })

vim.bo[buf].filetype = "TelescopePrompt"
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_exec_autocmds("FileType", { group = "SkkeletonPickers", buffer = buf })

vim.wait(20, function()
    return false
end)

local maps_i = vim.api.nvim_buf_get_keymap(buf, "i")
local maps_n = vim.api.nvim_buf_get_keymap(buf, "n")
local found_toggle_i = false
local found_enable_n = false
local found_cr = nil

for _, m in ipairs(maps_i) do
    local lhs = m.lhs:upper()
    if lhs == "<C-J>" then
        found_toggle_i = true
        assert_eq(m.rhs, "<Plug>(skkeleton-toggle)", "Derived Insert mode toggle key should map to plug")
    elseif lhs == "<CR>" then
        found_cr = m
    end
end

for _, m in ipairs(maps_n) do
    local lhs = m.lhs:upper()
    if lhs == "<C-J>" then
        found_enable_n = true
        assert_eq(m.rhs, "a<Plug>(skkeleton-enable)", "Derived Normal mode enable key should map")
    end
end

assert_true(found_toggle_i, "Insert mode toggle keymap should be dynamically bound")
assert_true(found_enable_n, "Normal mode enable keymap should be dynamically bound")
assert_true(found_cr ~= nil, "CR keymap should be created")

-- Test 3: CR Mapping execution behavior
print("Running Test 3: CR Mapping execution behavior...")

-- Case A: Skkeleton disabled
print("  Case A: Skkeleton disabled")
original_cr_called = 0
reset_mock()

local cr_callback = found_cr.callback
assert_true(type(cr_callback) == "function", "CR mapping must have a callback function")
cr_callback()
assert_eq(mock.disabled_count, 1, "Should call skkeleton#disable")
assert_eq(original_cr_called, 1, "Original CR callback should be executed when skkeleton is disabled")

-- Case B: Skkeleton enabled with marker
print("  Case B: Skkeleton enabled with marker")
original_cr_called = 0
reset_mock()
mock.is_enabled = true
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "▼かんじ" })

-- Re-apply if not found
maps = vim.api.nvim_buf_get_keymap(buf, "i")
found_cr = nil
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" then
        found_cr = m
        break
    end
end
if not found_cr then
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

assert_eq(#mock.handle_calls, 1, "Should call skkeleton#handle once")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should call handleKey")
assert_eq(mock.handle_calls[1].opts.key, "\n", "Should pass NL key")
assert_eq(mock.disabled_count, 0, "Should NOT disable skkeleton when marker is present")
assert_eq(original_cr_called, 0, "Original CR should NOT be called when marker is present")

-- Case C: Skkeleton enabled without marker
print("  Case C: Skkeleton enabled without marker")
original_cr_called = 0
reset_mock()
mock.is_enabled = true

vim.b[buf].skkeleton_pickers_cr_wrapped = false
vim.b[buf].skkeleton_pickers_setup = true
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
assert_true(found_cr ~= nil, "CR mapping must exist for Case C")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "かんじ" })
cr_callback = found_cr.callback
cr_callback()
assert_eq(mock.disabled_count, 1, "Should disable skkeleton when no marker")

-- Case D: Skkeleton enabled with custom markers
print("  Case D: Skkeleton enabled with custom markers")
original_cr_called = 0
reset_mock()
mock.is_enabled = true
mock.config.markerHenkan = "["
mock.config.markerHenkanSelect = "]"

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
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "]かんじ" })
cr_callback = found_cr.callback
cr_callback()

assert_eq(#mock.handle_calls, 1, "Should call skkeleton#handle once with custom marker")
assert_eq(mock.handle_calls[1].func, "handleKey", "Should call handleKey")
assert_eq(mock.handle_calls[1].opts.key, "\n", "Should pass NL key")
assert_eq(mock.disabled_count, 0, "Should NOT disable skkeleton when custom marker is present")
assert_eq(original_cr_called, 0, "Original CR should NOT be called when custom marker is present")

-- Test 5: skkeleton-enable-post re-applies CR mapping
print("Running Test 5: skkeleton-enable-post re-applies CR mapping...")
reset_mock()
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

maps = vim.api.nvim_buf_get_keymap(buf3, "i")
local has_cr_map = false
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_cr_map = true
    end
end
assert_true(has_cr_map, "CR mapping should be wrapped initially")

vim.keymap.set("i", "<CR>", "<Cmd>echo 'skkeleton'<CR>", { buffer = buf3, noremap = true, nowait = true })
maps = vim.api.nvim_buf_get_keymap(buf3, "i")
has_cr_map = false
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_cr_map = true
    end
end
assert_true(not has_cr_map, "Our CR callback should be overwritten by skkeleton")

vim.api.nvim_exec_autocmds("User", { pattern = "skkeleton-enable-post" })
maps = vim.api.nvim_buf_get_keymap(buf3, "i")
has_cr_map = false
for _, m in ipairs(maps) do
    if m.lhs:upper() == "<CR>" and m.callback then
        has_cr_map = true
    end
end
assert_true(has_cr_map, "CR mapping should be re-applied after skkeleton-enable-post")

print(string.format("\nbuffer_test finished: %d passed, %d failed", pass_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    os.exit(0)
end
