local M = {}

M.default_config = {
    pickers = {
        telescope = {
            enabled = false,
        },
        mini_pick = {
            enabled = false,
        },
    },
}

M.options = {}

function M.setup(opts)
    M.options = vim.tbl_deep_extend("force", M.default_config, opts or {})
end

return M
