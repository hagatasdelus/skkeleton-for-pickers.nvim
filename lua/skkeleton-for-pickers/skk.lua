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
            local action = core.parse_skk_action(map)
            if not action then
                return nil
            end

            return {
                lhs = map.lhs,
                raw = vim.api.nvim_replace_termcodes(map.lhs, true, true, true),
                rhs = map.callback or map.rhs,
                action = action,
                mode = mode,
            }
        end)
        :totable()
end

function M.has_skkeleton_marker(input_str)
    local marker_henkan, marker_henkan_select = M.get_skk_markers()

    if input_str and input_str ~= "" then
        if core.check_marker_in_string(input_str, marker_henkan, marker_henkan_select) then
            return true
        end
    end

    -- Check skkeleton internal state via state module
    local skk_state = state.get_skk_state()
    return core.check_marker_in_state(skk_state)
end

function M.call_skk_handle(func, opts, current_text)
    -- Build prevInput from injected current_text
    local query_str = current_text or ""

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
    if not (ok_req and type(ret) == "table") then
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
