---@diagnostic disable: duplicate-set-field
local M = {}

local config = require("skkeleton-pickers.config")
local skk = require("skkeleton-pickers.skk")

M.picker_initialized = false
M.is_routing_skk = false
M.prev_preedit = ""
local patched = false

-- Get the skkeleton configuration markers
function M.get_skk_markers()
    local marker_henkan = "▽"
    local marker_henkan_select = "▼"
    local ok_config, cfg = pcall(vim.fn["skkeleton#get_config"])
    if ok_config and type(cfg) == "table" then
        marker_henkan = cfg.markerHenkan or marker_henkan
        marker_henkan_select = cfg.markerHenkanSelect or marker_henkan_select
    end
    return marker_henkan, marker_henkan_select
end

-- Strip conversion markers (▽/▼) from the query array
function M.clean_query_markers(query)
    local marker_henkan, marker_henkan_select = M.get_skk_markers()
    local clean_query = {}
    for _, char in ipairs(query) do
        if char ~= marker_henkan and char ~= marker_henkan_select then
            table.insert(clean_query, char)
        end
    end
    return clean_query
end

-- Remove the previous preedit from the query
function M.remove_old_preedit(query, prev_preedit, marker_henkan, marker_henkan_select)
    -- 1. Remove by character count of prev_preedit
    if prev_preedit and prev_preedit ~= "" then
        local char_count = vim.fn.strchars(prev_preedit)
        for _ = 1, char_count do
            if #query > 0 then
                table.remove(query)
            end
        end
    end

    -- 2. Fallback: Strip using markers if they are still present in the query
    local truncate_idx = nil
    for i, char in ipairs(query) do
        if char == marker_henkan or char == marker_henkan_select then
            truncate_idx = i
            break
        end
    end
    if truncate_idx then
        while #query >= truncate_idx do
            table.remove(query)
        end
    end
end

-- Retrieve the current preedit string from skkeleton
function M.get_current_preedit()
    local cur_preedit = ""
    local ok_preedit, preedit_res = pcall(vim.fn["denops#request"], "skkeleton", "getPreEdit", {})
    if ok_preedit and type(preedit_res) == "string" then
        cur_preedit = preedit_res
    end
    return cur_preedit
end

-- Parse result delta into leading backspace count and the text after it
function M.parse_result_delta(result)
    local bs_count = 0
    if result then
        while result:sub(bs_count + 1, bs_count + 1) == "\8" do
            bs_count = bs_count + 1
        end
    end
    local after_bs = result and result:sub(bs_count + 1) or ""
    return bs_count, after_bs
end

-- Extract confirmed (kakutei) text from result delta
function M.extract_kakutei(after_bs, cur_preedit)
    if cur_preedit == "" then
        return after_bs
    end

    if #after_bs > #cur_preedit and after_bs:sub(-#cur_preedit) == cur_preedit then
        -- result = [kakutei][cur_preedit]
        return after_bs:sub(1, #after_bs - #cur_preedit)
    elseif after_bs == cur_preedit then
        -- No kakutei, result is entirely the new preedit
        return ""
    else
        -- Fallback
        return ""
    end
end

-- Process the skkeleton handleKey result and update mini.pick query
function M.process_skk_result(result)
    if result == " \8" then
        return
    end

    local ok_pick, pick_active = pcall(function()
        return MiniPick and MiniPick.is_picker_active()
    end)
    if not ok_pick or not pick_active then
        return
    end

    local query = MiniPick.get_picker_query()
    local marker_henkan, marker_henkan_select = M.get_skk_markers()

    -- Remove the old preedit from query before processing the new result
    M.remove_old_preedit(query, M.prev_preedit, marker_henkan, marker_henkan_select)

    local cur_preedit = M.get_current_preedit()

    if result and result ~= "" then
        local bs_count, after_bs = M.parse_result_delta(result)
        local kakutei = M.extract_kakutei(after_bs, cur_preedit)

        -- If there was NO old preedit, apply backspaces to the confirmed query text
        if M.prev_preedit == "" and bs_count > 0 then
            for _ = 1, bs_count do
                if #query > 0 then
                    table.remove(query)
                end
            end
        end

        -- Append kakutei characters
        if kakutei ~= "" then
            for char in kakutei:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                local byte = char:byte(1)
                if #char > 1 or (byte >= 32 and byte ~= 127) then
                    table.insert(query, char)
                end
            end
        end
    end

    -- Append current preedit characters
    if cur_preedit ~= "" then
        for char in cur_preedit:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            table.insert(query, char)
        end
    end

    M.prev_preedit = cur_preedit
    MiniPick.set_picker_query(query)
end

function M.should_route_to_skk(char, toggle_raw)
    local del_termcode = vim.api.nvim_replace_termcodes("<Del>", true, true, true)
    local bs_termcode = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
    local bspace_termcode = vim.api.nvim_replace_termcodes("<Bspace>", true, true, true)
    if char == del_termcode or char == bs_termcode or char == bspace_termcode then
        return true
    end

    if char:byte(1) == 128 then
        return false
    end
    if char == "\x08" or char == "\x7f" then
        return true
    end
    if char == toggle_raw then
        return true
    end

    local has_marker = skk.has_skkeleton_marker()
    if has_marker then
        return true
    end

    if char == "\r" or char == "\n" or char == "\x1b" then
        return false
    end

    if #char > 1 then
        return true
    end

    local code = char:byte(1)
    return code and code >= 32 and code <= 126
end

-- Initialize default mode if not yet initialized
function M.initialize_picker_mode()
    if M.picker_initialized then
        return
    end
    M.picker_initialized = true
    local default_mode = config.options.default_mode
    if default_mode and default_mode ~= "eisu" then
        M.is_routing_skk = true
        skk.call_skk_handle("enable", { expr = true })
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
            skk.call_skk_handle("handleKey", { key = { "" }, ["function"] = func, expr = true })
        end
        M.is_routing_skk = false
    end
end

-- Process the toggle keypress to enable/disable skkeleton
function M.handle_toggle_key(toggle_raw)
    local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])
    if not ok_skk then
        return "\x1c"
    end

    if skk_enabled then
        pcall(vim.fn["skkeleton#disable"])
    else
        M.is_routing_skk = true
        skk.call_skk_handle("enable", { expr = true })
        local default_mode = config.options.default_mode
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
                skk.call_skk_handle("handleKey", { key = { "" }, ["function"] = func, expr = true })
            end
        end
        M.is_routing_skk = false
    end
    return "\x1c"
end

-- Handle normal key routing to skkeleton
function M.route_key_to_skk(char)
    M.is_routing_skk = true

    -- Convert <Del> and <BS> termcodes to Backspace (\x08) when routing to skkeleton
    local del_termcode = vim.api.nvim_replace_termcodes("<Del>", true, true, true)
    local bs_termcode = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
    local bspace_termcode = vim.api.nvim_replace_termcodes("<Bspace>", true, true, true)
    local routed_key = char
    if char == del_termcode or char == bs_termcode or char == bspace_termcode then
        routed_key = "\x08"
    end

    if routed_key == "\r" or routed_key == "\n" then
        if skk.has_skkeleton_marker() then
            local nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
            local result = skk.call_skk_handle("handleKey", { key = nl, expr = true })
            M.process_skk_result(result)
            M.is_routing_skk = false
            return "\x1c"
        else
            pcall(vim.fn["skkeleton#disable"])
            M.is_routing_skk = false
            return char
        end
    end

    if routed_key == "\x1b" then
        if skk.has_skkeleton_marker() then
            local result = skk.call_skk_handle("handleKey", { key = char, expr = true })
            M.process_skk_result(result)
            M.is_routing_skk = false
            return "\x1c"
        else
            pcall(vim.fn["skkeleton#disable"])
            M.is_routing_skk = false
            return char
        end
    end

    local result = skk.call_skk_handle("handleKey", { key = routed_key, expr = true })
    M.process_skk_result(result)
    M.is_routing_skk = false
    return "\x1c"
end

-- Wrap default_match to support synchronous matching when routing skkeleton keys
function M.wrap_default_match()
    if MiniPick and not MiniPick.skkeleton_pickers_wrapped then
        MiniPick.skkeleton_pickers_wrapped = true
        local orig_default_match = MiniPick.default_match
        MiniPick.default_match = function(stritems, inds, query, opts)
            local ok_s, skk_e = pcall(vim.fn["skkeleton#is_enabled"])
            if ok_s and skk_e then
                opts = opts or {}
                opts.sync = true

                -- Clean query by stripping conversion markers (▽/▼)
                query = M.clean_query_markers(query)
            end
            return orig_default_match(stritems, inds, query, opts)
        end
    end
end

-- Process keypress logic for mini.pick and route to skkeleton if needed
function M.handle_picker_char(char)
    -- Wrap default_match to support synchronous matching when routing skkeleton keys
    M.wrap_default_match()

    -- Synchronous picker initialization on first getcharstr invocation
    M.initialize_picker_mode()

    -- Re-evaluate skkeleton enablement state after potential initialization
    local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])
    local toggle_raw = vim.api.nvim_replace_termcodes(config.options.toggle_key or "<C-j>", true, true, true)

    if char == toggle_raw then
        return M.handle_toggle_key(toggle_raw)
    end

    if not (ok_skk and skk_enabled and char ~= "" and char ~= nil) then
        return char
    end

    if M.should_route_to_skk(char, toggle_raw) then
        return M.route_key_to_skk(char)
    end

    if char == "\x1b" or char == "\r" or char == "\n" then
        pcall(vim.fn["skkeleton#disable"])
    end
    return char
end

function M.setup_getcharstr_patch()
    if _G.skkeleton_pickers_minipick_patched then
        return
    end

    if MiniPick and not M.skkeleton_pickers_start_patched then
        M.skkeleton_pickers_start_patched = true
        local orig_start = MiniPick.start
        MiniPick.start = function(opts)
            opts = opts or {}
            opts.mappings = opts.mappings or {}

            -- Add a dummy action for \x1c (Ctrl-\) to prevent MiniPick from setting do_match = true
            -- inside H.picker_advance loop, which would trigger double-matching and kill the async grep processes
            if not opts.mappings.skkeleton_pickers_ignore then
                opts.mappings.skkeleton_pickers_ignore = {
                    char = "\x1c",
                    func = function() end,
                }
            end

            -- Clean the query from conversion markers (▽/▼) in custom source matches
            if opts.source and type(opts.source.match) == "function" then
                local orig_match = opts.source.match
                opts.source.match = function(stritems, inds, query, opts_match)
                    local ok_s, skk_e = pcall(vim.fn["skkeleton#is_enabled"])
                    if ok_s and skk_e then
                        query = M.clean_query_markers(query)
                    end
                    return orig_match(stritems, inds, query, opts_match)
                end
            end

            return orig_start(opts)
        end
    end

    local orig_getcharstr = vim.fn.getcharstr
    vim.fn.getcharstr = function(...)
        local char = orig_getcharstr(...)

        if not config.options.mini_pick then
            return char
        end

        -- Normalize backspace key
        if char == "\x7f" then
            char = "\x08"
        end

        local ok_pick, pick_active = pcall(function()
            return MiniPick and MiniPick.is_picker_active()
        end)

        if ok_pick and pick_active then
            return M.handle_picker_char(char)
        end

        return char
    end

    _G.skkeleton_pickers_minipick_patched = true
end

return M
