# skkeleton-pickers.nvim

`skkeleton-pickers.nvim` is a Neovim plugin that provides seamless integration between the [skkeleton](https://github.com/vim-skk/skkeleton) Japanese input method and popular fuzzy finders, enabling smooth Japanese text input within prompt buffers.

Normally, keymaps and modes of SKK can conflict with the prompt behavior of fuzzy finders. This plugin resolves those conflicts, allowing you to use SKK Japanese input in fuzzy finders stress-free.

## Features

- **Seamless Input Experience** — Automatically enables SKK mode when a fuzzy finder prompts and keeps your input flow smooth.
- **Safe `<CR>` (Enter) Forwarding** — Pressing Enter confirms (Kakutei) any active preedit character, but selects/opens the highlighted item if there is no preedit text.
- **Dynamic Marker Support** — Dynamically tracks skkeleton configuration markers (e.g. `markerHenkan` and `markerHenkanSelect`), meaning it works seamlessly with custom indicators.
- **Popular Finders Support** — Out-of-the-box support for Telescope, Snacks.picker, and mini.pick.

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
    -- "folke/snacks.nvim",
    -- "echasnovski/mini.pick",
  },
  config = function()
    require("skkeleton-pickers").setup({
      -- Options (see Configuration section)
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

require('skkeleton-pickers').setup({})
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  source = "hagatasdelus/skkeleton-pickers.nvim",
  depends = { "vim-skk/skkeleton" },
})

require("skkeleton-pickers").setup({})
```

## Configuration

You can customize the behavior by passing options to `setup()`:

```lua
require("skkeleton-pickers").setup({
  -- Enable/disable integration for specific fuzzy finders (Default: true)
  telescope = true,
  snacks = true,
  mini_pick = true,

  -- Additional filetypes of custom buffers where you want to enable this integration
  filetypes = {},

  -- The default SKK mode applied when entering the prompt.
  -- Can be "henkan" (Hiragana), "zenkaku" (Zenkaku Eisu), "eisu" (Direct input), or "katakana" (Katakana)
  default_mode = "henkan",

  -- Key to toggle skkeleton (Default: "<C-j>")
  toggle_key = "<C-j>",
})
```

## License

MIT License
