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
local active_fts = {}
local patched = false
local picker_initialized = false

--- Check whether the current line/query contains an active skkeleton conversion
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

    -- If mini.pick is active, check the picker query
    local ok_pick, pick_active = pcall(function()
        return MiniPick and MiniPick.is_picker_active()
    end)
    if ok_pick and pick_active then
        local query = MiniPick.get_picker_query()
        local query_str = table.concat(query)
        return (query_str:find(marker_henkan, 1, true) ~= nil) or (query_str:find(marker_henkan_select, 1, true) ~= nil)
    end

    local ok_line, line = pcall(vim.api.nvim_get_current_line)
    if not ok_line or not line then
        return false
    end
    return (line:find(marker_henkan, 1, true) ~= nil) or (line:find(marker_henkan_select, 1, true) ~= nil)
end

--- Call skkeleton handle by directly invoking denops#request with a crafted
--- vimStatus, bypassing skkeleton#vim_status() which returns wrong mode/prevInput
--- when called from mini.pick's normal-mode context.
---
--- ROOT CAUSE: skkeleton#vim_status() calls mode() → "n", then falls into the
--- cmdline branch: getcmdline()[:getcmdpos()-2] → "".  The denops handler at
---   main.ts:296  checks  `!prevInput.endsWith(context.toString())`
--- and resets all internal state when it's true (empty string never ends with
--- the preedit "▽…").  We fix this by providing prevInput = query_str, which
--- ends with context.toString() because we synced the query after each handle.
--- @param func string  "handleKey", "enable", "disable", etc.
--- @param opts table   { key = ..., expr = ..., ["function"] = ... }
--- @return string|nil
local function call_skk_handle(func, opts)
    -- Build prevInput from the current mini.pick query
    local query_str = ""
    local ok_pick, pick_active = pcall(function()
        return MiniPick and MiniPick.is_picker_active()
    end)
    if ok_pick and pick_active then
        local query = MiniPick.get_picker_query()
        query_str = table.concat(query)
    end

    -- Replicate key normalization from skkeleton#handle
    local normalized_opts = vim.deepcopy(opts)
    local key = normalized_opts.key
    if type(key) == "string" then
        -- Convert raw key to notation using skkeleton's lookup table
        local ok_notation, notation_map = pcall(function()
            return vim.g["skkeleton#notation#key_to_notation"]
        end)
        if ok_notation and notation_map and notation_map[key] then
            normalized_opts.key = { notation_map[key] }
        else
            normalized_opts.key = { key }
        end
    elseif type(key) == "table" then
        local ok_notation, notation_map = pcall(function()
            return vim.g["skkeleton#notation#key_to_notation"]
        end)
        if ok_notation and notation_map then
            for i, k in ipairs(key) do
                if notation_map[k] then
                    key[i] = notation_map[k]
                end
            end
        end
    else
        normalized_opts.key = { "" }
    end

    -- Construct vimStatus with correct prevInput
    local vim_status = {
        prevInput = query_str,
        completeInfo = { pum_visible = false, selected = -1 },
        completeType = "native",
        mode = "c",
    }

    -- Call denops directly
    local ok_req, ret = pcall(vim.fn["denops#request"], "skkeleton", "handle", { func, normalized_opts, vim_status })

    if ok_req and ret then
        -- Update g:skkeleton#state (replicating skkeleton#handle line 209)
        if ret.state then
            vim.g["skkeleton#state"] = ret.state
        end

        local result = ret.result or ""

        -- Handle <Cmd>...<CR> results (replicating skkeleton#handle lines 212-214)
        if result:find("^<Cmd>") then
            local cmd_body = result:sub(6)
            result = vim.api.nvim_replace_termcodes("<Cmd>" .. cmd_body .. "<CR>", true, true, true)
        end

        -- Fire autocmds (replicating skkeleton#handle line 216)
        pcall(vim.fn["skkeleton#doautocmd"])

        if opts.expr then
            return result
        end

        if result ~= "" then
            vim.api.nvim_feedkeys(result, "nit", false)
        end
        return ""
    end
    return nil
end

--- Process the output of skkeleton#handle and update the mini.pick query buffer.
--- @param result string
local function process_skk_result(result)
    if not result or result == "" then
        return
    end

    local ok_pick, pick_active = pcall(function()
        return MiniPick and MiniPick.is_picker_active()
    end)
    if not ok_pick or not pick_active then
        return
    end

    local query = MiniPick.get_picker_query()

    -- Count backspaces at the start of the result
    local bs_count = 0
    while result:sub(bs_count + 1, bs_count + 1) == "\b" do
        bs_count = bs_count + 1
    end

    -- Remove that many characters from the end of the query
    for _ = 1, bs_count do
        if #query > 0 then
            table.remove(query)
        end
    end

    -- Append the new characters
    local new_text = result:sub(bs_count + 1)
    if new_text ~= "" then
        for char in new_text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            table.insert(query, char)
        end
    end

    MiniPick.set_picker_query(query)
end

--- Determine whether a keypress should be routed to skkeleton inside mini.pick.
--- @param char string
--- @param toggle_raw string
--- @return boolean
local function should_route_to_skk(char, toggle_raw)
    if char == toggle_raw then
        return true
    end
    if char:byte(1) == 128 then
        return false
    end
    if char == "\x08" or char == "\x7f" then
        return true
    end

    local has_marker = has_skkeleton_marker()
    if has_marker then
        -- Route almost all keys to skkeleton when converting
        return true
    end

    -- If no marker, only route toggle key, backspace, and printable characters
    if char == "\r" or char == "\n" or char == "\x1b" then
        return false
    end

    -- If multi-byte (non-ASCII)
    if #char > 1 then
        return true
    end

    -- Single byte printable ASCII
    local code = char:byte(1)
    return code and code >= 32 and code <= 126
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

--- Apply the default mode configuration for the current buffer.
--- @param buf number
local function apply_default_mode(buf)
    local default_mode = M.config.default_mode
    if not default_mode then
        return
    end

    if default_mode == "eisu" then
        pcall(vim.fn["skkeleton#disable"])
        return
    end

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
    if not func then
        return
    end

    local has_skk, is_enabled = pcall(vim.fn["skkeleton#is_enabled"])
    if has_skk and not is_enabled then
        pcall(vim.fn["skkeleton#handle"], "enable", {})
    end
    pcall(vim.fn["skkeleton#handle"], "handleKey", { key = { "" }, ["function"] = func })
end

--- Setup buffer configurations for the picker prompts.
local function setup_buffer()
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype

    if not vim.tbl_contains(active_fts, ft) then
        return
    end

    vim.b[buf].skkeleton = true

    -- Bind toggle keymap
    vim.keymap.set("i", M.config.toggle_key, "<Plug>(skkeleton-toggle)", { buffer = buf, silent = true })

    -- Wrap <CR> keymap
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
        apply_default_mode(buf)
    end
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.default_config, opts or {})

    active_fts = {}
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

    -- Set up mini.pick autocommands for stop handling
    vim.api.nvim_create_autocmd("User", {
        pattern = "MiniPickStop",
        group = group,
        callback = function()
            picker_initialized = false
            if M.config.mini_pick then
                pcall(vim.fn["skkeleton#disable"])
            end
        end,
    })

    -- Set up getcharstr monkeypatch for mini.pick support
    if not patched then
        patched = true
        local orig_getcharstr = vim.fn.getcharstr
        vim.fn.getcharstr = function(...)
            local char = orig_getcharstr(...)

            if not M.config.mini_pick then
                return char
            end

            -- Normalize backspace key
            if char == "\x7f" then
                char = "\x08"
            end

            local ok_pick, pick_active = pcall(function()
                return MiniPick and MiniPick.is_picker_active()
            end)
            local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])

            if ok_pick and pick_active then
                -- Synchronous picker initialization on first getcharstr invocation
                if not picker_initialized then
                    picker_initialized = true
                    local default_mode = M.config.default_mode
                    if default_mode and default_mode ~= "eisu" then
                        call_skk_handle("enable", {})
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
                            call_skk_handle("handleKey", { key = { "" }, ["function"] = func })
                        end
                        -- Update skk_enabled state after enabling
                        ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])
                    end
                end

                local toggle_raw = vim.api.nvim_replace_termcodes(M.config.toggle_key or "<C-j>", true, true, true)

                if char == toggle_raw then
                    if ok_skk then
                        if skk_enabled then
                            pcall(vim.fn["skkeleton#disable"])
                        else
                            call_skk_handle("enable", {})
                            local default_mode = M.config.default_mode
                            if default_mode and default_mode ~= "eisu" then
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
                                    call_skk_handle("handleKey", { key = { "" }, ["function"] = func })
                                end
                            end
                        end
                    end
                    return "\x1c"
                end

                if ok_skk and skk_enabled and char ~= "" and char ~= nil then
                    if should_route_to_skk(char, toggle_raw) then
                        if char == "\r" or char == "\n" then
                            if has_skkeleton_marker() then
                                local nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
                                local result = call_skk_handle("handleKey", { key = nl, expr = true })
                                process_skk_result(result)
                                return "\x1c"
                            else
                                pcall(vim.fn["skkeleton#disable"])
                                return char
                            end
                        end

                        if char == "\x1b" then
                            if has_skkeleton_marker() then
                                local result = call_skk_handle("handleKey", { key = char, expr = true })
                                process_skk_result(result)
                                return "\x1c"
                            else
                                pcall(vim.fn["skkeleton#disable"])
                                return char
                            end
                        end

                        local result = call_skk_handle("handleKey", { key = char, expr = true })
                        process_skk_result(result)
                        return "\x1c"
                    else
                        if char == "\x1b" or char == "\r" or char == "\n" then
                            pcall(vim.fn["skkeleton#disable"])
                        end
                        return char
                    end
                end
            end

            return char
        end
    end
end

return M
