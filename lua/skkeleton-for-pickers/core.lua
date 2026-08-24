local M = {}

--- Split a UTF-8 string into an array of single characters
---@param str string
---@return string[]
function M.utf8_chars(str)
    if not str or str == "" then
        return {}
    end
    local chars = {}
    for char in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        table.insert(chars, char)
    end
    return chars
end

--- Count character length of a UTF-8 string
---@param str string
---@return integer
function M.utf8_len(str)
    if not str or str == "" then
        return 0
    end
    return #M.utf8_chars(str)
end

--- Check if lhs represents a CR mapping
---@param lhs string
---@return boolean
function M.is_cr_lhs(lhs)
    if not lhs or type(lhs) ~= "string" then
        return false
    end
    local u = lhs:upper()
    return u == "<CR>" or u == "<ENTER>" or u == "<RETURN>"
end

--- Find a CR mapping entry from a list of keymaps
---@param maps table[]
---@return table|nil
function M.find_cr_map(maps)
    if not maps or type(maps) ~= "table" then
        return nil
    end
    return vim.iter(maps):find(function(m)
        return m and m.lhs and M.is_cr_lhs(m.lhs)
    end)
end

--- Calculate setup action plan based on buffer context (pure calculation)
---@param ctx { ft: string, is_active_ft: boolean, skk_enabled: boolean, cr_wrapped: boolean }
---@return { action: string, steps: string[]|nil }
function M.plan_buffer_setup(ctx)
    if not ctx or not ctx.is_active_ft then
        return { action = "skip" }
    end
    if ctx.ft == "minipick" then
        return { action = "patch_minipick" }
    end

    local steps = { "mark_enabled" }
    if not ctx.skk_enabled then
        table.insert(steps, "rebind_keymaps")
    end
    if not ctx.cr_wrapped then
        table.insert(steps, "wrap_cr")
    end
    return { action = "setup", steps = steps }
end

--- Check if conversion markers exist in string
---@param str string
---@param marker_henkan string
---@param marker_henkan_select string
---@return boolean
function M.check_marker_in_string(str, marker_henkan, marker_henkan_select)
    if not str or str == "" then
        return false
    end
    return (marker_henkan and marker_henkan ~= "" and str:find(marker_henkan, 1, true) ~= nil)
        or (marker_henkan_select and marker_henkan_select ~= "" and str:find(marker_henkan_select, 1, true) ~= nil)
end

--- Check if skkeleton internal state table contains conversion phase or henkanFeed
---@param state table|nil
---@return boolean
function M.check_marker_in_state(state)
    if type(state) ~= "table" then
        return false
    end
    if state.henkanFeed and state.henkanFeed ~= "" then
        return true
    end
    if
        state.phase
        and (state.phase == "henkan" or state.phase == "input:okurinasi" or state.phase == "input:okuriari")
    then
        return true
    end
    return false
end

--- Parse skkeleton action type from RHS string or maparg table
---@param rhs_or_map string|table|nil
---@return string|nil action ("enable"|"disable"|"toggle")
function M.parse_skk_action(rhs_or_map)
    if not rhs_or_map then
        return nil
    end
    local rhs = type(rhs_or_map) == "string" and rhs_or_map or (type(rhs_or_map) == "table" and rhs_or_map.rhs)
    local desc = type(rhs_or_map) == "table" and rhs_or_map.desc

    if rhs and type(rhs) == "string" then
        if rhs:find("<Plug>%(skkeleton%-disable%)") or rhs:find("skkeleton#disable") then
            return "disable"
        elseif rhs:find("<Plug>%(skkeleton%-enable%)") or rhs:find("skkeleton#enable") then
            return "enable"
        elseif rhs:find("<Plug>%(skkeleton%-toggle%)") or rhs:find("skkeleton#toggle") then
            return "toggle"
        end
    end

    local has_callback = type(rhs_or_map) == "table" and type(rhs_or_map.callback) == "function"
    if has_callback and desc and type(desc) == "string" and desc:find("skkeleton") then
        if desc:find("disable") then
            return "disable"
        elseif desc:find("enable") then
            return "enable"
        elseif desc:find("toggle") then
            return "toggle"
        end
    end

    return nil
end

--- Evaluate original CR keymap and return execution plan for feedkeys/callback
--- Pure function: performs NO side effects, API calls, or feedkeys execution.
---@param orig table|nil original keymap dictionary (from maparg/nvim_buf_get_keymap)
---@return table plan Execution plan table
function M.eval_original_cr_plan(orig)
    if not orig then
        return { type = "fallback", keys = "<CR>", replace_termcodes = true, mode = "n" }
    end

    -- Case 1: Callback function
    if orig.callback and type(orig.callback) == "function" then
        return {
            type = "callback_direct",
            callback = orig.callback,
        }
    end

    -- Case 2: String RHS
    if orig.rhs and type(orig.rhs) == "string" and orig.rhs ~= "" then
        return {
            type = "rhs_direct",
            keys = orig.rhs,
            replace_termcodes = true,
            mode = (orig.noremap == 1) and "n" or "m",
        }
    end

    return { type = "fallback", keys = "<CR>", replace_termcodes = true, mode = "n" }
end

--- Convert key notation
---@param key string
---@param notation_map table|nil
---@return string
function M.to_notation(key, notation_map)
    if notation_map and notation_map[key] then
        return notation_map[key]
    end
    return key
end

--- Create a new query array excluding conversion markers.
--- Note: Skkeleton conversion markers are assumed to be single UTF-8 characters
--- as configured in skkeleton (defaults: '▽' and '▼').
---@param query string[]
---@param marker_henkan string
---@param marker_henkan_select string
---@return string[]
function M.clean_query_markers(query, marker_henkan, marker_henkan_select)
    if type(query) ~= "table" then
        return {}
    end
    return vim.iter(query)
        :filter(function(char)
            return char ~= marker_henkan and char ~= marker_henkan_select
        end)
        :totable()
end

--- Remove old preedit characters from query array
---@param query string[]
---@param prev_preedit string
---@param marker_henkan string
---@param marker_henkan_select string
function M.remove_old_preedit(query, prev_preedit, marker_henkan, marker_henkan_select)
    if not query or type(query) ~= "table" then
        return
    end

    if prev_preedit and prev_preedit ~= "" then
        local char_count = M.utf8_len(prev_preedit)
        for _ = 1, char_count do
            if #query > 0 then
                table.remove(query)
            end
        end
    end

    local truncate_idx = vim.iter(query):enumerate():find(function(_, char)
        return char == marker_henkan or char == marker_henkan_select
    end)

    if truncate_idx then
        while #query >= truncate_idx do
            table.remove(query)
        end
    end
end

--- Parse leading backspace count and trailing text from skkeleton handleKey result
---@param result string
---@return integer bs_count, string after_bs
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

--- Extract confirmed (kakutei) text from result delta
---@param after_bs string
---@param cur_preedit string
---@return string
function M.extract_kakutei(after_bs, cur_preedit)
    if cur_preedit == "" then
        return after_bs
    end

    if #after_bs > #cur_preedit and after_bs:sub(-#cur_preedit) == cur_preedit then
        return after_bs:sub(1, #after_bs - #cur_preedit)
    elseif after_bs == cur_preedit then
        return ""
    else
        return ""
    end
end

--- Pure calculation function for mini.pick query update
---@param params { query: string[], prev_preedit: string, result: string, cur_preedit: string, marker_henkan: string, marker_henkan_select: string }
---@return string[] new_query, string new_prev_preedit
function M.calculate_new_query(params)
    local raw_q = params.query or {}
    local query = { unpack(raw_q) }
    local prev_preedit = params.prev_preedit or ""
    local result = params.result or ""
    local cur_preedit = params.cur_preedit or ""
    local marker_henkan = params.marker_henkan
    local marker_henkan_select = params.marker_henkan_select

    M.remove_old_preedit(query, prev_preedit, marker_henkan, marker_henkan_select)

    if type(result) == "string" and result ~= "" and result ~= " \8" then
        local bs_count, after_bs = M.parse_result_delta(result)
        local kakutei = M.extract_kakutei(after_bs, cur_preedit)

        if prev_preedit == "" and bs_count > 0 then
            for _ = 1, bs_count do
                if #query > 0 then
                    table.remove(query)
                end
            end
        end

        if kakutei ~= "" then
            local kakutei_chars = M.utf8_chars(kakutei)
            for _, char in ipairs(kakutei_chars) do
                local byte = char:byte(1)
                if #char > 1 or (byte >= 32 and byte ~= 127) then
                    table.insert(query, char)
                end
            end
        end
    end

    if cur_preedit ~= "" then
        local preedit_chars = M.utf8_chars(cur_preedit)
        for _, char in ipairs(preedit_chars) do
            table.insert(query, char)
        end
    end

    return query, cur_preedit
end

--- Pure check function for BS / DEL key (matches control bytes or termcodes table entries)
---@param char string
---@param termcodes table|nil
---@return boolean
function M.is_bs_or_del(char, termcodes)
    if not char then
        return false
    end
    if char == "\x08" or char == "\x7f" then
        return true
    end
    if termcodes and type(termcodes) == "table" then
        if char == termcodes.del or char == termcodes.bs or char == termcodes.bspace then
            return true
        end
    end
    return false
end

--- Pure check function to determine if input character should route to skkeleton
---@param char string
---@param has_marker boolean
---@param termcodes table|nil
---@return boolean
function M.should_route_to_skk(char, has_marker, termcodes)
    if not char or char == "" then
        return false
    end

    if M.is_bs_or_del(char, termcodes) then
        return true
    end

    if char:byte(1) == 128 then
        return false
    end

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

--- Normalize key for skkeleton routing
---@param char string
---@param termcodes table|nil
---@return string
function M.normalize_routed_key(char, termcodes)
    if M.is_bs_or_del(char, termcodes) then
        return "\x08"
    end
    return char
end

--- Generate action plan for routing key to skkeleton
---@param routed_key string
---@param termcodes table|nil
---@return { action: string, skk_key: string }
function M.get_skk_routing_plan(routed_key, termcodes)
    if routed_key == "\r" or routed_key == "\n" or routed_key == "\x1b" then
        local nl_val = (termcodes and termcodes.nl) or "\n"
        local skk_key = (routed_key == "\x1b") and "\x07" or nl_val
        return { action = "handle_key", skk_key = skk_key }
    end

    return { action = "handle_key", skk_key = routed_key }
end

return M
