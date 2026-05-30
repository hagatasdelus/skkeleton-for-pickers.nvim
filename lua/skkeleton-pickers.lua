local M = {}

local config = require("skkeleton-pickers.config")
local buffer = require("skkeleton-pickers.buffer")
local minipick = require("skkeleton-pickers.minipick")

M.default_config = config.default_config
M.config = config.options

function M.setup(opts)
    config.setup(opts)
    M.config = config.options

    buffer.active_fts = {}
    for _, ft in ipairs(M.config.filetypes or {}) do
        table.insert(buffer.active_fts, ft)
    end
    if M.config.telescope then
        table.insert(buffer.active_fts, "TelescopePrompt")
    end
    if M.config.snacks then
        table.insert(buffer.active_fts, "snacks_picker_input")
    end
    if M.config.mini_pick then
        table.insert(buffer.active_fts, "minipick")
    end

    local group = vim.api.nvim_create_augroup("SkkeletonPickers", { clear = true })

    vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "WinEnter", "InsertEnter" }, {
        group = group,
        callback = buffer.setup_buffer,
    })

    -- When skkeleton enables, it overwrites all buffer-local mappings
    -- (including our <CR> wrapper) with its own <Cmd>call skkeleton#handle(...)
    -- mappings. We must re-apply our wrapper after skkeleton finishes.
    vim.api.nvim_create_autocmd("User", {
        pattern = "skkeleton-enable-post",
        group = group,
        callback = function()
            local buf = vim.api.nvim_get_current_buf()
            if vim.b[buf].skkeleton_pickers_cr_wrapped then
                buffer.apply_cr_map(buf)
            end
        end,
    })

    -- Set up mini.pick autocommands for stop handling
    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniPickStop",
        group = group,
        callback = function()
            minipick.picker_initialized = false
            if M.config.mini_pick then
                pcall(vim.fn["skkeleton#disable"])
            end
        end,
    })

    -- Set up getcharstr monkeypatch for mini.pick support
    minipick.setup_getcharstr_patch()
end

return M
