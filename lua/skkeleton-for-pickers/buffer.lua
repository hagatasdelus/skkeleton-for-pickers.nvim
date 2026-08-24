local M = {}

local skk = require("skkeleton-for-pickers.skk")
local core = require("skkeleton-for-pickers.core")
local state = require("skkeleton-for-pickers.state")

M.active_fts = {}

function M.handle_cr_key(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])

    -- Since handle_cr_key is exclusively for the CR wrapper of the picker prompt (which is always a single line),
    -- the first line matches the entire prompt input. It is assumed not to be called from a multi-line buffer.
    local ok_line, line = pcall(vim.api.nvim_buf_get_lines, buf, 0, 1, false)
    local line_str = (ok_line and line and line[1]) or ""

    if has_skk and is_enabled and skk.has_skkeleton_marker(line_str) then
        local nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
        pcall(vim.fn["skkeleton#handle"], "handleKey", { key = nl })
        return
    end

    pcall(vim.fn["skkeleton#disable"])

    local orig = state.get_original_cr(buf)
    local plan = core.eval_original_cr_plan(orig)

    if plan.type == "callback_direct" and plan.callback then
        plan.callback()
        return
    end

    local keys_to_feed = nil
    if plan.type == "rhs_direct" or plan.type == "fallback" then
        keys_to_feed = plan.keys
    end

    if keys_to_feed then
        local final_keys = keys_to_feed
        if plan.replace_termcodes then
            final_keys = vim.api.nvim_replace_termcodes(keys_to_feed, true, true, true)
        end
        vim.api.nvim_feedkeys(final_keys, plan.mode or "n", false)
        return
    end
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

    if plan.action == "skip" or plan.action == "patch_minipick" then
        return plan.action
    end

    -- Clear any existing BufLeave/BufDelete autocmds for this buffer to prevent duplicates on repeated setup
    vim.api.nvim_clear_autocmds({
        group = state.AUGROUP_NAME,
        buffer = buf,
        event = { "BufLeave", "BufDelete" },
    })

    -- Disable skkeleton when leaving the picker buffer
    vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
        group = state.AUGROUP_NAME,
        buffer = buf,
        callback = function()
            pcall(vim.fn["skkeleton#disable"])
        end,
    })
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
end

return M
