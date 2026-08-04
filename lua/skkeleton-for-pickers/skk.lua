local M = {}

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

function M.get_skkeleton_keymaps(mode)
    mode = mode or "i"

    local global_maps = vim.api.nvim_get_keymap(mode)
    local buf_maps = vim.api.nvim_buf_get_keymap(0, mode)

    return vim.iter({ global_maps, buf_maps })
        :filter(function(list)
            return type(list) == "table"
        end)
        :flatten(1)
        :map(function(map)
            local rhs = map.rhs or ""
            local is_skk_action = rhs:find("<Plug>%(skkeleton%-")
                or rhs:find("skkeleton#enable")
                or rhs:find("skkeleton#disable")
                or rhs:find("skkeleton#toggle")
            if not is_skk_action then
                return nil
            end

            local action = "toggle"
            if rhs:find("disable") then
                action = "disable"
            elseif rhs:find("enable") then
                action = "enable"
            end

            return {
                lhs = map.lhs,
                raw = vim.api.nvim_replace_termcodes(map.lhs, true, true, true),
                rhs = rhs,
                action = action,
                mode = mode,
            }
        end)
        :totable()
end

function M.has_skkeleton_marker()
    local marker_henkan, marker_henkan_select = M.get_skk_markers()

    -- If mini.pick is active, check the picker query
    local pick_active = false
    if _G.MiniPick and type(_G.MiniPick.is_picker_active) == "function" then
        pick_active = _G.MiniPick.is_picker_active()
    end
    if pick_active then
        local query = MiniPick.get_picker_query()
        local query_str = table.concat(query)
        if
            (marker_henkan ~= "" and query_str:find(marker_henkan, 1, true) ~= nil)
            or (marker_henkan_select ~= "" and query_str:find(marker_henkan_select, 1, true) ~= nil)
        then
            return true
        end
    else
        local ok_line, line = pcall(vim.api.nvim_get_current_line)
        if ok_line and line then
            if
                (marker_henkan ~= "" and line:find(marker_henkan, 1, true) ~= nil)
                or (marker_henkan_select ~= "" and line:find(marker_henkan_select, 1, true) ~= nil)
            then
                return true
            end
        end
    end

    -- Check skkeleton internal state via vim.g["skkeleton#state"]
    local state = vim.g["skkeleton#state"]
    if type(state) == "table" then
        if state.henkanFeed and state.henkanFeed ~= "" then
            return true
        end
        if
            state.phase
            and (state.phase == "henkan" or state.phase == "input:okurinasi" or state.phase == "input:okuriari")
        then
            return true
        end
    end

    return false
end

function M.call_skk_handle(func, opts)
    -- Build prevInput from the current mini.pick query
    local query_str = ""
    local pick_active = false
    if _G.MiniPick and type(_G.MiniPick.is_picker_active) == "function" then
        pick_active = _G.MiniPick.is_picker_active()
    end
    if pick_active then
        local query = MiniPick.get_picker_query()
        query_str = table.concat(query)
    end

    -- Replicate key normalization from skkeleton#handle
    local normalized_opts = vim.deepcopy(opts)
    local key = normalized_opts.key

    local notation_map = nil
    pcall(function()
        notation_map = vim.g["skkeleton#notation#key_to_notation"]
    end)

    local function to_notation(k)
        if notation_map and notation_map[k] then
            return notation_map[k]
        end
        return k
    end
    if type(key) == "string" then
        normalized_opts.key = { to_notation(key) }
    elseif type(key) == "table" then
        normalized_opts.key = vim.iter(key):map(to_notation):totable()
    else
        normalized_opts.key = { "" }
    end

    -- Construct vimStatus with correct prevInput
    local vim_status = {
        prevInput = query_str,
        completeInfo = { pum_visible = false, selected = -1 },
        completeType = "native",
        mode = "t",
    }

    local ok_req, ret = pcall(vim.fn["denops#request"], "skkeleton", "handle", { func, normalized_opts, vim_status })

    if ok_req and ret then
        -- Update g:skkeleton#state
        if ret.state then
            vim.g["skkeleton#state"] = ret.state
        end

        local result = ret.result or ""

        -- Handle <Cmd>...<CR> results
        if result:find("^<Cmd>") then
            local cmd_body = result:sub(6)
            result = vim.api.nvim_replace_termcodes("<Cmd>" .. cmd_body .. "<CR>", true, true, true)
        end

        -- Fire autocmds
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

return M
