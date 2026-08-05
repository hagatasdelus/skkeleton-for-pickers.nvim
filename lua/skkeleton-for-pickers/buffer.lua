local M = {}

local skk = require("skkeleton-for-pickers.skk")
local core = require("skkeleton-for-pickers.core")
local state = require("skkeleton-for-pickers.state")

M.active_fts = {}

function M.handle_cr_key(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])

    if has_skk and is_enabled and skk.has_skkeleton_marker() then
        local nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
        pcall(vim.fn["skkeleton#handle"], "handleKey", { key = nl })
        return
    end

    pcall(vim.fn["skkeleton#disable"])

    local orig = state.get_original_cr(buf)
    if orig and orig.callback then
        orig.callback()
        return
    end

    if orig and orig.rhs then
        local keys = vim.api.nvim_replace_termcodes(orig.rhs, true, true, true)
        vim.api.nvim_feedkeys(keys, orig.noremap == 1 and "n" or "m", false)
        return
    end

    local cr = vim.api.nvim_replace_termcodes("<CR>", true, true, true)
    vim.api.nvim_feedkeys(cr, "n", false)
end

function M.apply_cr_map(buf)
    vim.keymap.set("i", "<CR>", function()
        M.handle_cr_key(buf)
    end, { buffer = buf, silent = true })
end

function M.handle_skkeleton_enable_post(is_minipick_enabled)
    local buf = vim.api.nvim_get_current_buf()
    if state.is_cr_wrapped(buf) then
        M.apply_cr_map(buf)
    end
    local is_minipick_active = _G.MiniPick
        and type(_G.MiniPick.is_picker_active) == "function"
        and _G.MiniPick.is_picker_active()
    if is_minipick_enabled and is_minipick_active and vim.bo[buf].filetype == "minipick" then
        pcall(vim.fn["skkeleton#dangerously_clear_buffer_local_mappings"])
    end
end

function M.setup_buffer()
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype

    local buf_ctx = state.read_buffer_context(buf)
    local plan = core.plan_buffer_setup({
        ft = ft,
        is_active_ft = vim.tbl_contains(M.active_fts, ft),
        skk_enabled = buf_ctx.skk_enabled,
        cr_wrapped = buf_ctx.cr_wrapped,
    })

    if plan.action == "skip" then
        return
    end

    if plan.action == "patch_minipick" then
        require("skkeleton-for-pickers.minipick").apply_patch()
        return
    end

    state.mark_skk_enabled(buf, true)

    -- Re-bind user's skkeleton keymaps (Insert and Normal mode) in prompt buffer if skkeleton is not currently active
    local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])
    if not (has_skk and is_enabled) then
        for _, mode in ipairs({ "i", "n" }) do
            for _, item in ipairs(skk.get_skkeleton_keymaps(mode)) do
                vim.keymap.set(mode, item.lhs, item.rhs, { buffer = buf, silent = true, remap = true })
            end
        end
    end

    -- Wrap CR mapping
    if state.is_cr_wrapped(buf) then
        return
    end

    local maps = vim.api.nvim_buf_get_keymap(buf, "i")
    local map = core.find_cr_map(maps)

    if not map then
        return
    end

    state.save_original_cr(buf, map)
    M.apply_cr_map(buf)
    state.mark_cr_wrapped(buf, true)

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
