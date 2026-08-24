local M = {}

M.AUGROUP_NAME = "SkkeletonForPickers"

-- Private session state
local session = {
    prev_preedit = "",
    orig_getcharstr = nil,
}

-- Session state accessors & lifecycles
function M.get_prev_preedit()
    return session.prev_preedit
end

function M.set_prev_preedit(val)
    session.prev_preedit = val or ""
end

function M.get_orig_getcharstr()
    return session.orig_getcharstr
end

function M.set_orig_getcharstr(fn)
    session.orig_getcharstr = fn
end

function M.stop_session()
    session.prev_preedit = ""
end

-- Buffer local state encapsulation (vim.b)
function M.is_skk_enabled(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    return vim.b[buf].skkeleton == true
end

function M.mark_skk_enabled(buf, enabled)
    buf = buf or vim.api.nvim_get_current_buf()
    vim.b[buf].skkeleton = (enabled ~= false)
end

function M.get_original_cr(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    return vim.b[buf].skkeleton_for_pickers_original_cr
end

function M.save_original_cr(buf, map)
    buf = buf or vim.api.nvim_get_current_buf()
    vim.b[buf].skkeleton_for_pickers_original_cr = map
end

function M.is_cr_wrapped(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    return vim.b[buf].skkeleton_for_pickers_cr_wrapped == true
end

function M.mark_cr_wrapped(buf, wrapped)
    buf = buf or vim.api.nvim_get_current_buf()
    vim.b[buf].skkeleton_for_pickers_cr_wrapped = (wrapped ~= false)
end

function M.read_buffer_context(buf)
    buf = buf or vim.api.nvim_get_current_buf()
    return {
        skk_enabled = M.is_skk_enabled(buf),
        cr_wrapped = M.is_cr_wrapped(buf),
    }
end

-- SKK global state encapsulation (vim.g)
function M.get_skk_state()
    return vim.g["skkeleton#state"]
end

function M.set_skk_state(st)
    vim.g["skkeleton#state"] = st
end

return M
