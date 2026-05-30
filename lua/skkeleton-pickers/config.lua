local M = {}

M.default_config = {
    telescope = true,
    snacks = true,
    mini_pick = true,
    filetypes = {},
    default_mode = "eisu",
    toggle_key = "<C-j>",
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.default_config, opts or {})
end

return M
