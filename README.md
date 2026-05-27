# skkeleton-pickers.nvim

`skkeleton-pickers.nvim` は、Neovim の主要な Fuzzy Finder（ファジーファインダー）のプロンプトバッファ内で、[skkeleton](https://github.com/vim-skk/skkeleton) を用いたシームレスな日本語入力を可能にするための Neovim プラグインです。

通常、ファジーファインダーのプロンプトでは SKK の挙動やモード管理が干渉しあうことがありますが、本プラグインを導入することで、検索ウィンドウの起動と同時に日本語入力（SKK）をストレスなくスムーズに利用できるようになります。

---

## 🚀 主な特徴

*   **シームレスな入力体験**: ピッカーが起動すると自動的に SKK モードが有効化され、即座に日本語で検索を開始できます。
*   **安全な `<CR>` (Enter) の移譲**: 変換未確定の文字列がある場合は skkeleton の確定（Kakutei）を行い、未確定文字列がない場合は本来のピッカーの決定処理（ファイルのオープンなど）を実行します。
*   **動的なマーカー追従**: `markerHenkan` や `markerHenkanSelect` などの skkeleton カスタムマーカー設定を動的に読み込み、どのようなマーカー（例: `▽` や `▼` 以外）を設定していても完璧に動作します。
*   **主要なファインダーに対応**: Telescope、Snacks.picker をサポート。

---

## ⚠️ Supported Fuzzy Finders

現在、本プラグインが公式にサポートしている Fuzzy Finder は**以下の2種類**です。

1. **Telescope** (`nvim-telescope/telescope.nvim`)
2. **Snacks.picker** (`folke/snacks.nvim`)

### ⚠️ mini.pick についての制限事項
`mini.pick` (`echasnovski/mini.nvim`) は**サポート対象外**です。

`mini.pick` はその入力ループ処理において、Neovimのインサートモードのキーマッピングをバイパスし、低レベルな `vim.fn.getcharstr()` を用いて入力文字を直接傍受（インターセプト）する設計となっています。
一方、`skkeleton` はインサートモードのバッファローカルなキーマッピング (`inoremap`) を用いてキー入力をフックして変換を行う仕組みです。
そのため、`mini.pick` のプロンプト内では `skkeleton` のキーマップが一切起動せず、日本語入力に切り替えることができません。これは `mini.pick` の設計に起因する制約であり、本プラグイン側での解決は不可能です。

---

## Requirements

- Neovim >= 0.11.0 (組み込みパッケージマネージャ `vim.pack` を使用する場合は **Neovim >= 0.12.0**)
- [vim-denops/denops.vim](https://github.com/vim-denops/denops.vim)
- [vim-skk/skkeleton](https://github.com/vim-skk/skkeleton)

---

## Installation

### 1. lazy.nvim
```lua
{
  "hagatasdelus/skkeleton-pickers.nvim",
  dependencies = {
    "vim-skk/skkeleton",
    -- 各種お使いのファインダー
    -- "nvim-telescope/telescope.nvim",
    -- "folke/snacks.nvim",
  },
  config = function()
    require("skkeleton-pickers").setup({
      -- 必要に応じたオプションをここに記述
    })
  end
}
```

### 2. mini.deps
```lua
local MiniDeps = require('mini.deps')

MiniDeps.add({
  source = 'hagatasdelus/skkeleton-pickers.nvim',
  depends = { 'vim-skk/skkeleton' },
})

require('skkeleton-pickers').setup({})
```

### 3. vim.pack (Neovim 0.12+)
```lua
vim.pack.add({
  source = "hagatasdelus/skkeleton-pickers.nvim",
  depends = { "vim-skk/skkeleton" },
})

require("skkeleton-pickers").setup({})
```

---

## Configuration

### 基本設定

```lua
require("skkeleton-pickers").setup({
  -- 特定のピッカーでのみ有効化したい場合は false に設定可能 (デフォルトはすべて true)
  telescope = true,
  snacks = true,
  mini_pick = false, -- (注: mini.pick は設計上の制限により非対応です)

  -- 追加で有効にしたいカスタムバッファの filetype リスト
  filetypes = {},

  -- 各ファインダーのプロンプトに入った際のデフォルト動作
  -- "henkan" (即座にSKK変換モード), "zenkaku" (全角英数), "eisu" (直接入力), "katakana" (カタカナ) などを指定可能
  default_mode = "henkan", 

  -- skkeleton のトグルキー (デフォルトは "<C-j>")
  toggle_key = "<C-j>",
})
```

---

## 🔍 `<CR>` (Enter) 処理フロー

本プラグインは、プロンプト内での誤作動を防ぐために `<CR>` キー入力をインターセプトし、以下のロジックに従って適切にハンドリングします。

```mermaid
sequenceDiagram
    autonumber
    User->>Neovim: Press <CR> in insert mode
    Neovim->>skkeleton-pickers: Trigger wrapped <CR> mapping
    rect rgb(240, 248, 255)
        Note over skkeleton-pickers: Is skkeleton enabled?
    end
    alt YES (skkeleton enabled)
        Note over skkeleton-pickers: Is marker (e.g. ▽ or ▼) in current line?
        alt YES (unconfirmed text present)
            skkeleton-pickers->>skkeleton: Call skkeleton#handle("handleKey", {key = "\n"})
            skkeleton->>Neovim: Confirm conversion in place without inserting newline
            Neovim->>User: Display confirmed text (marker removed)
        else NO (no unconfirmed text)
            skkeleton-pickers->>skkeleton: Disable skkeleton
            skkeleton-pickers->>Neovim: Execute original picker mapping directly
            Neovim->>User: Picker's original action fires → select/open file immediately
        end
    else NO (skkeleton disabled)
        skkeleton-pickers->>Neovim: Execute original picker mapping directly
        Neovim->>User: Picker's original action fires → select/open file immediately
    end
```

---

## 🛠️ 動的なマーカー追従について

skkeleton では、`markerHenkan` や `markerHenkanSelect` を利用して変換中のインジケータ記号を任意にカスタマイズできます。

```lua
-- 例: マーカーをブラケットに変更する設定
vim.fn["skkeleton#config"]({
  markerHenkan = "[",
  markerHenkanSelect = "]",
})
```

`skkeleton-pickers.nvim` は、バッファ上で決定キーが押された際、現在の `skkeleton` の構成情報を自動的に取得して Plain-text サーチを行います。そのため、ユーザーがどのようなカスタム記号を設定していても、未確定テキストの有無を正確に判定して誤動作なく動作します。特別なお手元の設定変更や追加オプションは不要です。

---

## License

MIT License
