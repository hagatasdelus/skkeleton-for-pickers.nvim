local M = {}

local skk = require("skkeleton-pickers.skk")

M.active_fts = {}

function M.apply_cr_map(buf)
    vim.keymap.set("i", "<CR>", function()
        local current_buf = vim.api.nvim_get_current_buf()
        local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])

        if has_skk and is_enabled then
            if skk.has_skkeleton_marker() then
                local nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
                pcall(vim.fn["skkeleton#handle"], "handleKey", { key = nl })
                return
            end
        end

        pcall(vim.fn["skkeleton#disable"])

        local orig = vim.b[current_buf].skkeleton_pickers_original_cr
        if orig then
            if orig.callback then
                orig.callback()
                return
            elseif orig.rhs then
                local keys = vim.api.nvim_replace_termcodes(orig.rhs, true, true, true)
                vim.api.nvim_feedkeys(keys, orig.noremap == 1 and "n" or "m", false)
                return
            end
        end
        local cr = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
        vim.api.nvim_feedkeys(cr, "n", false)
    end, { buffer = buf, silent = true })
end

function M.setup_buffer()
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype

    if not vim.tbl_contains(M.active_fts, ft) then
        return
    end

    -- Skip setup for mini.pick prompt buffer since it does not use insert-mode mappings
    -- and we handle its initialization dynamically in the getcharstr patch.
    if ft == "minipick" then
        require("skkeleton-pickers.minipick").apply_patch()
        return
    end

    vim.b[buf].skkeleton = true

    -- Re-bind user's skkeleton keymaps (Insert and Normal mode) in prompt buffer if skkeleton is not currently active
    local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])
    if not (has_skk and is_enabled) then
        for _, mode in ipairs({ "i", "n" }) do
            local keymaps = skk.get_skkeleton_keymaps(mode)
            for _, item in ipairs(keymaps) do
                vim.keymap.set(mode, item.lhs, item.rhs, { buffer = buf, silent = true, remap = true })
            end
        end
    end

    -- Wrap CR mapping
    if vim.b[buf].skkeleton_pickers_cr_wrapped then
        return
    end

    local map = nil
    local maps = vim.api.nvim_buf_get_keymap(buf, "i")
    for _, m in ipairs(maps) do
        if m.lhs:upper() == "<CR>" then
            map = m
            break
        end
    end

    if not map then
        return
    end

    vim.b[buf].skkeleton_pickers_original_cr = map
    M.apply_cr_map(buf)
    vim.b[buf].skkeleton_pickers_cr_wrapped = true

    -- Disable skkeleton when leaving the picker buffer
    vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
        buffer = buf,
        once = true,
        callback = function()
            pcall(vim.fn["skkeleton#disable"])
        end,
    })
end

return M
