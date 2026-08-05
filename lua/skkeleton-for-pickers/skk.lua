local M = {}

local core = require("skkeleton-for-pickers.core")
local state = require("skkeleton-for-pickers.state")

function M.get_skk_markers()
    local ok_config, cfg = pcall(vim.fn["skkeleton#get_config"])
    if not (ok_config and type(cfg) == "table") then
        return "▽", "▼"
    end
    return cfg.markerHenkan or "▽", cfg.markerHenkanSelect or "▼"
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
            local action = core.parse_skk_action(map.rhs)
            if not action then
                return nil
            end

            return {
                lhs = map.lhs,
                raw = vim.api.nvim_replace_termcodes(map.lhs, true, true, true),
                rhs = map.rhs,
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
        if core.check_marker_in_string(query_str, marker_henkan, marker_henkan_select) then
            return true
        end
    else
        local ok_line, line = pcall(vim.api.nvim_get_current_line)
        if ok_line and line then
            if core.check_marker_in_string(line, marker_henkan, marker_henkan_select) then
                return true
            end
        end
    end

    -- Check skkeleton internal state via state module
    local skk_state = state.get_skk_state()
    return core.check_marker_in_state(skk_state)
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

    if type(key) == "string" then
        normalized_opts.key = { core.to_notation(key, notation_map) }
    elseif type(key) == "table" then
        normalized_opts.key = vim.iter(key)
            :map(function(k)
                return core.to_notation(k, notation_map)
            end)
            :totable()
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
    if not (ok_req and ret) then
        return nil
    end

    -- Update g:skkeleton#state
    if ret.state then
        state.set_skk_state(ret.state)
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

return M
