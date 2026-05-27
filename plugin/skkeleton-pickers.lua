if vim.g.loaded_skkeleton_pickers then
    return
end
vim.g.loaded_skkeleton_pickers = true

if vim.fn.has("nvim-0.11.0") == 0 then
    vim.api.nvim_echo(
        { { "skkeleton-pickers.nvim requires at least Neovim 0.11.0", "ErrorMsg" } },
        true,
        { err = true }
    )
    return
end
