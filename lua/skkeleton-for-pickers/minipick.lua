---@diagnostic disable: duplicate-set-field
local M = {}

local skk = require("skkeleton-for-pickers.skk")

M.picker_initialized = false
M.is_routing_skk = false
M.prev_preedit = ""
local orig_getcharstr = nil

-- Cache key termcodes and control characters to avoid repeated Neovim C-API calls
local DEL_TERMCODE = vim.api.nvim_replace_termcodes("<Del>", true, true, true)
local BS_TERMCODE = vim.api.nvim_replace_termcodes("<BS>", true, true, true)
local BSPACE_TERMCODE = vim.api.nvim_replace_termcodes("<Bspace>", true, true, true)
local NL_TERMCODE = vim.api.nvim_replace_termcodes("<NL>", true, true, true)
local IGNORE_CHAR = "\x1c"

-- Check if mini.pick is active and the current window is the prompt window
local function is_picker_win_active()
    if not (_G.MiniPick and type(_G.MiniPick.is_picker_active) == "function") then
        return false
    end
    if not _G.MiniPick.is_picker_active() then
        return false
    end
    if type(_G.MiniPick.get_picker_state) == "function" then
        local state = _G.MiniPick.get_picker_state()
        if state and state.windows and state.windows.main then
            return vim.api.nvim_get_current_win() == state.windows.main
        end
    end
    return true
end

-- Strip conversion markers (▽/▼) from the query array
function M.clean_query_markers(query)
    local marker_henkan, marker_henkan_select = skk.get_skk_markers()
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

    if not is_picker_win_active() then
        return
    end

    local query = MiniPick.get_picker_query()
    if not query then
        return
    end

    local marker_henkan, marker_henkan_select = skk.get_skk_markers()

    -- Remove the old preedit from query before processing the new result
    M.remove_old_preedit(query, M.prev_preedit, marker_henkan, marker_henkan_select)

    local cur_preedit = M.get_current_preedit()

    if type(result) == "string" and result ~= "" then
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

function M.should_route_to_skk(char)
    if char == DEL_TERMCODE or char == BS_TERMCODE or char == BSPACE_TERMCODE then
        return true
    end

    if char:byte(1) == 128 then
        return false
    end
    if char == "\x08" or char == "\x7f" then
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

-- Handle normal key routing to skkeleton
function M.route_key_to_skk(char)
    M.is_routing_skk = true

    -- Convert DEL_TERMCODE and BS_TERMCODE to Backspace (\x08) when routing to skkeleton
    local routed_key = char
    if char == DEL_TERMCODE or char == BS_TERMCODE or char == BSPACE_TERMCODE then
        routed_key = "\x08"
    end

    if routed_key == "\r" or routed_key == "\n" then
        if skk.has_skkeleton_marker() then
            local result = skk.call_skk_handle("handleKey", { key = NL_TERMCODE, expr = true })
            M.process_skk_result(result)
            M.is_routing_skk = false
            return IGNORE_CHAR
        else
            pcall(vim.fn["skkeleton#disable"])
            M.is_routing_skk = false
            return char
        end
    end

    if routed_key == "\x1b" then
        if skk.has_skkeleton_marker() then
            local result = skk.call_skk_handle("handleKey", { key = "\x07", expr = true })
            M.process_skk_result(result)
            M.is_routing_skk = false
            return IGNORE_CHAR
        else
            pcall(vim.fn["skkeleton#disable"])
            M.is_routing_skk = false
            return char
        end
    end

    local result = skk.call_skk_handle("handleKey", { key = routed_key, expr = true })
    M.process_skk_result(result)
    M.is_routing_skk = false
    return IGNORE_CHAR
end

-- Wrap default_match to support synchronous matching when routing skkeleton keys
function M.wrap_default_match()
    if _G.MiniPick and not _G.MiniPick.skkeleton_pickers_wrapped then
        _G.MiniPick.skkeleton_pickers_wrapped = true
        local orig_default_match = _G.MiniPick.default_match
        _G.MiniPick.default_match = function(stritems, inds, query, opts)
            local ok_s, skk_e = pcall(vim.fn["skkeleton#is_enabled"])
            if ok_s and skk_e then
                -- Shallow copy to avoid mutating the original options table
                opts = vim.tbl_extend("force", {}, opts or {}, { sync = true })

                -- Clean query by stripping conversion markers (▽/▼)
                query = M.clean_query_markers(query)
            end
            return orig_default_match(stritems, inds, query, opts)
        end
    end
end

-- Wrap the active picker's options dynamically (Lazy-load safe)
function M.wrap_active_picker_opts()
    if not is_picker_win_active() then
        return
    end

    if type(_G.MiniPick.get_picker_opts) ~= "function" or type(_G.MiniPick.set_picker_opts) ~= "function" then
        return
    end

    local opts = _G.MiniPick.get_picker_opts()
    if not opts then
        return
    end

    local modified = false
    opts.mappings = opts.mappings or {}
    if not opts.mappings.skkeleton_pickers_ignore then
        opts.mappings.skkeleton_pickers_ignore = {
            char = IGNORE_CHAR,
            func = function() end,
        }
        modified = true
    end

    if opts.source and type(opts.source.match) == "function" and not opts.source.skkeleton_pickers_match_wrapped then
        local orig_match = opts.source.match
        opts.source.match = function(stritems, inds, query, opts_match)
            local ok_s, skk_e = pcall(vim.fn["skkeleton#is_enabled"])
            if ok_s and skk_e then
                query = M.clean_query_markers(query)
            end
            return orig_match(stritems, inds, query, opts_match)
        end
        opts.source.skkeleton_pickers_match_wrapped = true
        modified = true
    end

    if modified then
        _G.MiniPick.set_picker_opts(opts)
    end
end

-- Process the toggle keypress to enable/disable skkeleton
function M.handle_toggle_key(action)
    action = action or "toggle"
    local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])
    if not ok_skk then
        return IGNORE_CHAR
    end

    local should_enable = false
    if action == "enable" then
        should_enable = true
    elseif action == "disable" then
        should_enable = false
    else
        should_enable = not skk_enabled
    end

    if should_enable then
        if not skk_enabled then
            M.is_routing_skk = true
            skk.call_skk_handle("enable", { expr = true })
            pcall(vim.fn["skkeleton#dangerously_clear_buffer_local_mappings"])
            M.is_routing_skk = false
        end
    else
        if skk_enabled then
            pcall(vim.fn["skkeleton#disable"])
        end
    end
    return IGNORE_CHAR
end

-- Process keypress logic for mini.pick and route to skkeleton if needed
function M.handle_picker_char(char)
    -- Wrap active picker's options dynamically
    M.wrap_active_picker_opts()

    -- Wrap default_match to support synchronous matching when routing skkeleton keys
    M.wrap_default_match()

    -- Check if user pressed any of their derived skkeleton keymaps
    local keymaps = skk.get_skkeleton_keymaps("i")
    for _, item in ipairs(keymaps) do
        if char == item.raw then
            return M.handle_toggle_key(item.action)
        end
    end

    -- Re-evaluate skkeleton enablement state
    local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])

    if not (ok_skk and skk_enabled and char ~= "" and char ~= nil) then
        return char
    end

    if M.should_route_to_skk(char) then
        return M.route_key_to_skk(char)
    end

    if char == "\x1b" or char == "\r" or char == "\n" then
        pcall(vim.fn["skkeleton#disable"])
    end
    return char
end

function M.apply_patch()
    if orig_getcharstr then
        return
    end

    orig_getcharstr = vim.fn.getcharstr
    vim.fn.getcharstr = function(...)
        local char = orig_getcharstr(...)

        -- Normalize backspace key
        if char == "\x7f" then
            char = "\x08"
        end

        if is_picker_win_active() then
            return M.handle_picker_char(char)
        end

        return char
    end

    _G.skkeleton_for_pickers_minipick_patched = true
    _G.skkeleton_pickers_minipick_patched = true
end

function M.restore_patch()
    if orig_getcharstr then
        vim.fn.getcharstr = orig_getcharstr
        orig_getcharstr = nil
    end
    _G.skkeleton_for_pickers_minipick_patched = nil
    _G.skkeleton_pickers_minipick_patched = nil
end

return M
