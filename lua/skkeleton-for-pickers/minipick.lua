---@diagnostic disable: duplicate-set-field
local M = {}

local skk = require("skkeleton-for-pickers.skk")
local core = require("skkeleton-for-pickers.core")

M.picker_initialized = false
M.is_routing_skk = false
M.prev_preedit = ""
local orig_getcharstr = nil

-- Cache key termcodes including <NL> for accurate skkeleton key routing
local TERMCODES = {
    del = vim.api.nvim_replace_termcodes("<Del>", true, true, true),
    bs = vim.api.nvim_replace_termcodes("<BS>", true, true, true),
    bspace = vim.api.nvim_replace_termcodes("<Bspace>", true, true, true),
    nl = vim.api.nvim_replace_termcodes("<NL>", true, true, true),
}
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

-- Helper: Retrieve current preedit string from skkeleton
local function get_current_preedit()
    local cur_preedit = ""
    local ok_preedit, preedit_res = pcall(vim.fn["denops#request"], "skkeleton", "getPreEdit", {})
    if ok_preedit and type(preedit_res) == "string" then
        cur_preedit = preedit_res
    end
    return cur_preedit
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
    local cur_preedit = get_current_preedit()

    local new_query, new_prev = core.calculate_new_query({
        query = query,
        prev_preedit = M.prev_preedit,
        result = result,
        cur_preedit = cur_preedit,
        marker_henkan = marker_henkan,
        marker_henkan_select = marker_henkan_select,
    })

    M.prev_preedit = new_prev
    MiniPick.set_picker_query(new_query)
end

function M.should_route_to_skk(char)
    local has_marker = skk.has_skkeleton_marker()
    return core.should_route_to_skk(char, has_marker, TERMCODES)
end

-- Handle normal key routing to skkeleton
function M.route_key_to_skk(char)
    M.is_routing_skk = true

    local routed_key = core.normalize_routed_key(char, TERMCODES)
    local has_marker = skk.has_skkeleton_marker()
    local plan = core.get_skk_routing_plan(routed_key, has_marker, TERMCODES)

    if plan.action == "disable_skk" then
        pcall(vim.fn["skkeleton#disable"])
        M.is_routing_skk = false
        return char
    end

    local result = skk.call_skk_handle("handleKey", { key = plan.skk_key or routed_key, expr = true })
    M.process_skk_result(result)
    M.is_routing_skk = false
    return IGNORE_CHAR
end

-- Safely check if skkeleton is currently enabled
function M.is_skk_enabled()
    local ok_s, skk_e = pcall(vim.fn["skkeleton#is_enabled"])
    return ok_s and skk_e
end

-- Side-effect layer helper: Gather markers from Neovim/skk state and pass to core
local function clean_query_with_markers(query)
    local m1, m2 = skk.get_skk_markers()
    return core.clean_query_markers(query, m1, m2)
end

-- Wrap default_match to support synchronous matching when routing skkeleton keys
function M.wrap_default_match()
    if _G.MiniPick and not _G.MiniPick.skkeleton_for_pickers_wrapped then
        _G.MiniPick.skkeleton_for_pickers_wrapped = true
        local orig_default_match = _G.MiniPick.default_match
        _G.MiniPick.default_match = function(stritems, inds, query, opts)
            if M.is_skk_enabled() then
                opts = vim.tbl_extend("force", {}, opts or {}, { sync = true })
                query = clean_query_with_markers(query)
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
    if not opts.mappings.skkeleton_for_pickers_ignore then
        opts.mappings.skkeleton_for_pickers_ignore = {
            char = IGNORE_CHAR,
            func = function() end,
        }
        modified = true
    end

    if
        opts.source
        and type(opts.source.match) == "function"
        and not opts.source.skkeleton_for_pickers_match_wrapped
    then
        local orig_match = opts.source.match
        opts.source.match = function(stritems, inds, query, opts_match)
            if M.is_skk_enabled() then
                query = clean_query_with_markers(query)
            end
            return orig_match(stritems, inds, query, opts_match)
        end
        opts.source.skkeleton_for_pickers_match_wrapped = true
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

    if should_enable and not skk_enabled then
        M.is_routing_skk = true
        skk.call_skk_handle("enable", { expr = true })
        pcall(vim.fn["skkeleton#dangerously_clear_buffer_local_mappings"])
        M.is_routing_skk = false
    elseif not should_enable and skk_enabled then
        pcall(vim.fn["skkeleton#disable"])
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
    local matched_item = vim.iter(keymaps):find(function(item)
        return char == item.raw
    end)
    if matched_item then
        return M.handle_toggle_key(matched_item.action)
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

function M.patched_getcharstr(orig_fn, ...)
    local char = orig_fn(...)

    -- Normalize backspace key
    if char == "\x7f" then
        char = "\x08"
    end

    if is_picker_win_active() then
        return M.handle_picker_char(char)
    end

    return char
end

function M.apply_patch()
    if orig_getcharstr then
        return
    end

    orig_getcharstr = vim.fn.getcharstr
    vim.fn.getcharstr = function(...)
        return M.patched_getcharstr(orig_getcharstr, ...)
    end

    _G.skkeleton_for_pickers_minipick_patched = true
end

function M.on_picker_stop()
    M.picker_initialized = false
    M.prev_preedit = ""
    pcall(vim.fn["skkeleton#disable"])
    M.restore_patch()
end

function M.restore_patch()
    if orig_getcharstr then
        vim.fn.getcharstr = orig_getcharstr
        orig_getcharstr = nil
    end
    _G.skkeleton_for_pickers_minipick_patched = nil
    _G.skkeleton_for_pickers_minipick_patched = nil
end

return M
