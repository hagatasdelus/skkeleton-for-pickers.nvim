local M = {}

M.default_config = {
    telescope = true,
    snacks = true,
    mini_pick = true,
    filetypes = {},
    toggle_key = "<C-j>",
    default_mode = "henkan",
}

M.config = {}

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})

    local active_fts = {}
    for _, ft in ipairs(M.config.filetypes or {}) do
        table.insert(active_fts, ft)
    end
    if M.config.telescope then
        table.insert(active_fts, "TelescopePrompt")
    end
    if M.config.snacks then
        table.insert(active_fts, "snacks_picker_input")
    end
    if M.config.mini_pick then
        table.insert(active_fts, "minipick")
    end

    local group = vim.api.nvim_create_augroup("SkkeletonPickers", { clear = true })

    --- Check whether the current line contains an active skkeleton conversion
    --- marker (▽ for henkan or ▼ for henkan-select), taking custom marker
    --- configuration into account.
    --- @return boolean
    local function has_skkeleton_marker()
        local marker_henkan = "▽"
        local marker_henkan_select = "▼"
        local ok_config, config = pcall(vim.fn["skkeleton#get_config"])
        if ok_config and type(config) == "table" then
            marker_henkan = config.markerHenkan or marker_henkan
            marker_henkan_select = config.markerHenkanSelect or marker_henkan_select
        end

        local ok_line, line = pcall(vim.api.nvim_get_current_line)
        if not ok_line or not line then
            return false
        end
        return (line:find(marker_henkan, 1, true) ~= nil) or (line:find(marker_henkan_select, 1, true) ~= nil)
    end

    --- Install our custom <CR> mapping on a picker buffer.
    --- This mapping does NOT use expr=true. Instead, it decides at runtime
    --- whether to let skkeleton handle the key (marker present) or to
    --- disable skkeleton and let the picker handle it (no marker / disabled).
    --- @param buf number
    local function apply_cr_map(buf)
        vim.keymap.set("i", "<CR>", function()
            local current_buf = vim.api.nvim_get_current_buf()
            local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])

            if has_skk and is_enabled then
                if has_skkeleton_marker() then
                    -- Marker present: confirm conversion without inserting a newline by sending <NL> (Ctrl-j / \n).
                    -- This avoids deleting/restoring the Neovim mapping, and keeps the prompt intact.
                    local nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
                    pcall(vim.fn["skkeleton#handle"], "handleKey", { key = nl })
                    return
                end
            end

            -- Disable skkeleton to be safe/idempotent and restore original mappings if needed
            pcall(vim.fn["skkeleton#disable"])

            -- Run the original mapping
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

    local function setup_buffer()
        local buf = vim.api.nvim_get_current_buf()
        local ft = vim.bo[buf].filetype

        if vim.tbl_contains(active_fts, ft) then
            vim.b[buf].skkeleton = true

            -- Bind toggle keymap
            vim.keymap.set("i", M.config.toggle_key, "<Plug>(skkeleton-toggle)", { buffer = buf, silent = true })

            -- Wrap <CR> keymap
            if not vim.b[buf].skkeleton_pickers_cr_wrapped then
                local map = nil
                local maps = vim.api.nvim_buf_get_keymap(buf, "i")
                for _, m in ipairs(maps) do
                    if m.lhs:upper() == "<CR>" then
                        map = m
                        break
                    end
                end
                if map then
                    vim.b[buf].skkeleton_pickers_original_cr = map
                    apply_cr_map(buf)
                    vim.b[buf].skkeleton_pickers_cr_wrapped = true

                    -- Disable skkeleton when leaving the picker buffer
                    vim.api.nvim_create_autocmd({ "BufLeave", "BufDelete" }, {
                        buffer = buf,
                        once = true,
                        callback = function()
                            pcall(vim.fn["skkeleton#disable"])
                        end,
                    })

                    -- Apply default mode (only once per buffer, when we wrap <CR>)
                    if not vim.b[buf].skkeleton_pickers_setup then
                        vim.b[buf].skkeleton_pickers_setup = true
                        local default_mode = M.config.default_mode
                        if default_mode then
                            if default_mode == "eisu" then
                                pcall(vim.fn["skkeleton#disable"])
                            else
                                local mode_map = {
                                    henkan = "hirakana",
                                    zenkaku = "zenkaku",
                                    katakana = "katakana",
                                    hankata = "hankatakana",
                                    hankatakana = "hankatakana",
                                    abbrev = "abbrev",
                                    hira = "hirakana",
                                    kata = "katakana",
                                }
                                local func = mode_map[default_mode]
                                if func then
                                    local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])
                                    if has_skk and not is_enabled then
                                        pcall(vim.fn["skkeleton#enable"])
                                    end
                                    pcall(
                                        vim.fn["skkeleton#handle"],
                                        "handleKey",
                                        { key = { "" }, ["function"] = func }
                                    )
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    vim.api.nvim_create_autocmd({ "FileType", "BufEnter", "WinEnter", "InsertEnter" }, {
        group = group,
        callback = setup_buffer,
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
                apply_cr_map(buf)
            end
        end,
    })
end

return M
