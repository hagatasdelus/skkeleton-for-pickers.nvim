local M = {}

local config = require("skkeleton-pickers.config")
local skk = require("skkeleton-pickers.skk")

M.picker_initialized = false
M.is_routing_skk = false
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

    -- Detect if there was any active preedit marker in the query beforehand
    local marker_henkan = "▽"
    local marker_henkan_select = "▼"
    local ok_config, cfg = pcall(vim.fn["skkeleton#get_config"])
    if ok_config and type(cfg) == "table" then
        marker_henkan = cfg.markerHenkan or marker_henkan
        marker_henkan_select = cfg.markerHenkanSelect or marker_henkan_select
    end

    local had_marker = false
    for _, char in ipairs(query) do
        if char == marker_henkan or char == marker_henkan_select then
            had_marker = true
            break
        end
    end

    -- 1. Extract the confirmed part by stripping any active preedit marker (▽ or ▼)
    --    and everything after it before we process the result.
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

    -- 2. Apply difference from result if it is not empty
    if result and result ~= "" then
        -- Strip any preedit (marker and everything after it) from the result to avoid duplication
        local stripped_result = result
        local idx1 = result:find(marker_henkan, 1, true)
        local idx2 = result:find(marker_henkan_select, 1, true)
        local idx = nil
        if idx1 and idx2 then
            idx = math.min(idx1, idx2)
        else
            idx = idx1 or idx2
        end
        if idx then
            stripped_result = result:sub(1, idx - 1)
        end

        -- Count backspaces at the start of the stripped result
        local bs_count = 0
        while stripped_result:sub(bs_count + 1, bs_count + 1) == "\8" do
            bs_count = bs_count + 1
        end

        -- If we had a marker, we completely ignore any leading backspaces in the result
        -- for deleting from the query because the preedit is already gone.
        local delete_count = had_marker and 0 or bs_count
        for _ = 1, delete_count do
            if #query > 0 then
                table.remove(query)
            end
        end

        -- Append the new characters, filtering out non-printable control characters
        local new_text = stripped_result:sub(bs_count + 1)
        if new_text ~= "" then
            for char in new_text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                local byte = char:byte(1)
                -- Skip single-byte control characters (0x00-0x1F and 0x7F)
                if #char > 1 or (byte >= 32 and byte ~= 127) then
                    table.insert(query, char)
                end
            end
        end
    end

    -- 3. Get the latest preedit string directly from skkeleton
    local preedit = ""
    local ok_preedit, preedit_res = pcall(vim.fn["denops#request"], "skkeleton", "getPreEdit", {})
    if ok_preedit and type(preedit_res) == "string" then
        preedit = preedit_res
    end

    -- 4. Append the characters of the preedit to the query
    if preedit ~= "" then
        for char in preedit:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            table.insert(query, char)
        end
    end

    MiniPick.set_picker_query(query)
    -- Flush event loop to allow any scheduled/deferred callbacks to execute
    pcall(vim.wait, 1, function()
        return false
    end)
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
                    if M.is_routing_skk then
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
                    skk.call_skk_handle("enable", {})
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
                        skk.call_skk_handle("handleKey", { key = { "" }, ["function"] = func })
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
                        skk.call_skk_handle("enable", {})
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
                                skk.call_skk_handle("handleKey", { key = { "" }, ["function"] = func })
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
