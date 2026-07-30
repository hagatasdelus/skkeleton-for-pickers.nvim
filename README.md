# skkeleton-for-pickers.nvim

`skkeleton-for-pickers.nvim` is a Neovim plugin that provides seamless integration between the [skkeleton](https://github.com/vim-skk/skkeleton) Japanese input method and popular fuzzy finders, enabling smooth Japanese text input within prompt buffers.

Normally, keymaps and modes of SKK can conflict with the prompt behavior of fuzzy finders. This plugin resolves those conflicts, allowing you to use SKK Japanese input in fuzzy finders stress-free.

## Features

- **Seamless Input Experience** — Automatically derives your personal `skkeleton` keymaps (e.g. `<C-j>`) across Insert and Normal modes to toggle Japanese input seamlessly in prompt buffers.
- **Safe `<CR>` (Enter) Forwarding** — Pressing Enter confirms (Kakutei) any active preedit character, but selects/opens the highlighted item if there is no preedit text.
- **Dynamic Marker Support** — Dynamically tracks skkeleton configuration markers (e.g. `markerHenkan` and `markerHenkanSelect`), working seamlessly with custom indicators.
- **Popular Finders Support** — Out-of-the-box support for Telescope (`nvim-telescope/telescope.nvim`) and `mini.pick` (`echasnovski/mini.pick`).

## Requirements

- Neovim >= 0.10.0
- [vim-denops/denops.vim](https://github.com/vim-denops/denops.vim)
- [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton)

## Installation

### lazy.nvim

```lua
{
  "hagatasdelus/skkeleton-for-pickers.nvim",
  dependencies = {
    "vim-skk/skkeleton",
    -- Optional dependencies based on your finder:
    -- "nvim-telescope/telescope.nvim",
    -- "echasnovski/mini.pick",
  },
  config = function()
    require("skkeleton-for-pickers").setup({
      pickers = {
        telescope = { enabled = true },
        mini_pick = { enabled = true },
      },
    })
  end
}
```

### mini.deps

```lua
local MiniDeps = require('mini.deps')

MiniDeps.add({
  source = 'hagatasdelus/skkeleton-for-pickers.nvim',
  depends = { 'vim-skk/skkeleton' },
})

require('skkeleton-for-pickers').setup({
  pickers = {
    telescope = { enabled = true },
    mini_pick = { enabled = true },
  },
})
```

## Configuration

You can customize the behavior by passing options to `setup()`:

> [!NOTE]
> All pickers are disabled by default (`enabled = false`). You must explicitly set `enabled = true` for the pickers you use.

```lua
require("skkeleton-for-pickers").setup({
  pickers = {
    telescope = { enabled = true },
    mini_pick = { enabled = true },
  },
})
```

## License

MIT License
