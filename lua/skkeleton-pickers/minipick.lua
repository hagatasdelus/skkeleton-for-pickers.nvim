local M = {}

local config = require("skkeleton-pickers.config")
local skk = require("skkeleton-pickers.skk")

M.picker_initialized = false
M.is_routing_skk = false
-- Track the previous preedit so we can compute kakutei (confirmed) text from the result delta
M.prev_preedit = ""
local patched = false

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

    -- 1. Get the config markers
    local marker_henkan = "▽"
    local marker_henkan_select = "▼"
    local ok_config, cfg = pcall(vim.fn["skkeleton#get_config"])
    if ok_config and type(cfg) == "table" then
        marker_henkan = cfg.markerHenkan or marker_henkan
        marker_henkan_select = cfg.markerHenkanSelect or marker_henkan_select
    end

    -- 2. Strip old preedit from the query to get confirmed-only portion
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

    -- 3. Get the current preedit from skkeleton (the authoritative source)
    local cur_preedit = ""
    local ok_preedit, preedit_res = pcall(vim.fn["denops#request"], "skkeleton", "getPreEdit", {})
    if ok_preedit and type(preedit_res) == "string" then
        cur_preedit = preedit_res
    end

    -- 4. Extract kakutei (confirmed) text from the result delta.
    --    The result from preEdit.output(next) has the format:
    --      BS * len(prev_preedit_segments) + kakutei + new_preedit
    --    where BS erases the old preedit, kakutei is confirmed text, and new_preedit
    --    is the current preedit state (same as getPreEdit()).
    --    We extract kakutei by:
    --      (a) stripping leading backspaces (they target the old preedit, not our query)
    --      (b) stripping the trailing cur_preedit suffix (it will be re-appended from getPreEdit)
    if result and result ~= "" then
        -- Strip leading backspaces
        local bs_count = 0
        while result:sub(bs_count + 1, bs_count + 1) == "\8" do
            bs_count = bs_count + 1
        end
        local after_bs = result:sub(bs_count + 1)

        -- Extract kakutei by removing the trailing preedit
        local kakutei = ""
        if cur_preedit ~= "" and #after_bs > #cur_preedit and after_bs:sub(-#cur_preedit) == cur_preedit then
            -- result = [kakutei][cur_preedit]
            kakutei = after_bs:sub(1, #after_bs - #cur_preedit)
        elseif cur_preedit == "" then
            -- No active preedit; everything after backspaces is kakutei
            kakutei = after_bs
        elseif cur_preedit ~= "" and after_bs == cur_preedit then
            -- No kakutei, result is entirely the new preedit
            kakutei = ""
        else
            -- Fallback: result doesn't end with cur_preedit.
            -- If cur_preedit is not empty, result only contains preedit delta, so no kakutei.
            -- If cur_preedit is empty, then everything in result (after backspaces) is kakutei.
            if cur_preedit ~= "" then
                kakutei = ""
            else
                kakutei = after_bs
            end
        end

        -- If there was NO old preedit (prev_preedit was empty) and bs_count > 0,
        -- the backspaces target confirmed text in the query (e.g., user pressed Backspace)
        if M.prev_preedit == "" and bs_count > 0 then
            for _ = 1, bs_count do
                if #query > 0 then
                    table.remove(query)
                end
            end
        end

        -- Append kakutei characters, filtering out control characters
        if kakutei ~= "" then
            for char in kakutei:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                local byte = char:byte(1)
                if #char > 1 or (byte >= 32 and byte ~= 127) then
                    table.insert(query, char)
                end
            end
        end
    end

    -- 5. Append the current preedit characters to the query
    if cur_preedit ~= "" then
        for char in cur_preedit:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            table.insert(query, char)
        end
    end

    -- 6. Update prev_preedit for the next call
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
        local ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])

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
            if not M.picker_initialized then
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
                    -- Update skk_enabled state after enabling
                    ok_skk, skk_enabled = pcall(vim.fn["skkeleton#is_enabled"])
                    M.is_routing_skk = false
                end
            end

            local toggle_raw = vim.api.nvim_replace_termcodes(config.options.toggle_key or "<C-j>", true, true, true)

            if char == toggle_raw then
                if ok_skk then
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
                end
                return "\x1c"
            end

            if ok_skk and skk_enabled and char ~= "" and char ~= nil then
                if M.should_route_to_skk(char, toggle_raw) then
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
