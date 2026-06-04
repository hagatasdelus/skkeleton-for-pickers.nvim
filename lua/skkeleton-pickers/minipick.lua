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
    if char == "\r" or char == "\n" then
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

    if char == "\x1b" then
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

    local result = skk.call_skk_handle("handleKey", { key = char, expr = true })
    M.process_skk_result(result)
    M.is_routing_skk = false
    return "\x1c"
end

function M.setup_getcharstr_patch()
    if patched then
        return
    end
    patched = true
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
            -- Wrap default_match to support synchronous matching when routing skkeleton keys
            if MiniPick and not MiniPick.skkeleton_pickers_wrapped then
                MiniPick.skkeleton_pickers_wrapped = true
                local orig_default_match = MiniPick.default_match
                MiniPick.default_match = function(stritems, inds, query, opts)
                    local ok_s, skk_e = pcall(vim.fn["skkeleton#is_enabled"])
                    if ok_s and skk_e then
                        opts = opts or {}
                        opts.sync = true
                    end
                    return orig_default_match(stritems, inds, query, opts)
                end
            end

            -- Synchronous picker initialization on first getcharstr invocation
            M.initialize_picker_mode()

            -- Re-evaluate skkeleton enablement state after potential initialization
            local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])

            local toggle_raw = vim.api.nvim_replace_termcodes(config.options.toggle_key or "<C-j>", true, true, true)

            if char == toggle_raw then
                return M.handle_toggle_key(toggle_raw)
            end

            if ok_skk and skk_enabled and char ~= "" and char ~= nil then
                if M.should_route_to_skk(char, toggle_raw) then
                    return M.route_key_to_skk(char)
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

return M
