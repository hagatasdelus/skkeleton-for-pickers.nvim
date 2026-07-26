# skkeleton-pickers.nvim

`skkeleton-pickers.nvim` is a Neovim plugin that provides seamless integration between the [skkeleton](https://github.com/vim-skk/skkeleton) Japanese input method and popular fuzzy finders, enabling smooth Japanese text input within prompt buffers.

Normally, keymaps and modes of SKK can conflict with the prompt behavior of fuzzy finders. This plugin resolves those conflicts, allowing you to use SKK Japanese input in fuzzy finders stress-free.

## Features

- **Seamless Input Experience** — Automatically enables SKK mode when a fuzzy finder prompts and keeps your input flow smooth.
- **Safe `<CR>` (Enter) Forwarding** — Pressing Enter confirms (Kakutei) any active preedit character, but selects/opens the highlighted item if there is no preedit text.
- **Dynamic Marker Support** — Dynamically tracks skkeleton configuration markers (e.g. `markerHenkan` and `markerHenkanSelect`), meaning it works seamlessly with custom indicators.
- **Popular Finders Support** — Out-of-the-box support for Telescope and mini.pick.

## Requirements

- Neovim >= 0.11.0 (or Neovim >= 0.12.0 for built-in `vim.pack`)
- [vim-denops/denops.vim](https://github.com/vim-denops/denops.vim)
- [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton)

## Installation

### lazy.nvim

```lua
{
  "hagatasdelus/skkeleton-pickers.nvim",
  dependencies = {
    "vim-skk/skkeleton",
    -- Optional dependencies based on your finder:
    -- "nvim-telescope/telescope.nvim",
    -- "echasnovski/mini.pick",
  },
  config = function()
    require("skkeleton-pickers").setup({
      pickers = {
        telescope = { enabled = true },
      },
    })
  end
}
```

### mini.deps

```lua
local MiniDeps = require('mini.deps')

MiniDeps.add({
  source = 'hagatasdelus/skkeleton-pickers.nvim',
  depends = { 'vim-skk/skkeleton' },
})

require('skkeleton-pickers').setup({
  pickers = {
    telescope = { enabled = true },
  },
})
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  source = "hagatasdelus/skkeleton-pickers.nvim",
  depends = { "vim-skk/skkeleton" },
})

require("skkeleton-pickers").setup({
  pickers = {
    telescope = { enabled = true },
  },
})
```

## Configuration

You can customize the behavior by passing options to `setup()`:

> [!NOTE]
> All pickers are disabled by default (`enabled = false`). You must explicitly set `enabled = true` to enable integration.

```lua
require("skkeleton-pickers").setup({
  pickers = {
    telescope = { enabled = false },
    mini_pick = { enabled = false },
  },
})
```

## License

MIT License
