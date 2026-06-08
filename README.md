# yank2think.nvim

Collect code selections into an LLM-ready markdown buffer, then copy them all at once to paste into ChatGPT/Claude/etc.

Yanking a single snippet loses its context. `yank2think` lets you gather selections from across your project into one **think buffer**, each entry tagged with its repo-relative path, line range, language fence, and an optional prompt — the shape LLMs parse best — then copy the whole thing with one keystroke.

```markdown
## src/handlers/search.rs (L12-30)
> Why does this panic on an empty id?

​```rust
fn search_capability(...) -> impl Responder {
    let id = id.into_inner();
    ...
}
​```

## src/registry.rs (L88-95)

​```rust
pub fn search(&self, ...) -> Report { ... }
​```
```

## Workflow

| Key | Mode | Action |
| --- | --- | --- |
| `<leader>Y` | visual | Append the selection as a new entry (prompts for an optional one-line question) |
| `<C-y>` | normal / visual | Open the think buffer in a floating, foldable view |

Inside the floating view:

| Key | Action |
| --- | --- |
| `<Tab>` | Fold / unfold the entry under the cursor |
| `y` | Copy **all** entries (with metadata) to the clipboard and close |
| `C` | Clear the think buffer |
| `q` / `<Esc>` | Close (entries are kept) |

Each entry is a collapsible markdown section (Magit-style), the view starts collapsed as a compact list, and the buffer is **editable** — tweak any entry before copying. Collapse an entry and `dd` deletes the whole section.

## Install

Requires Neovim 0.10+ (uses `vim.fs.root`).

### [vim.pack](https://neovim.io/doc/user/pack.html) (built-in, Neovim 0.12+)

```lua
vim.pack.add({ { src = "https://github.com/jgYro/yank2think.nvim" } })
require("yank2think").setup()
```

### lazy.nvim

```lua
{ "jgYro/yank2think.nvim", config = true }
```

### packer.nvim

```lua
use({ "jgYro/yank2think.nvim", config = function() require("yank2think").setup() end })
```

A floating `vim.ui.input` (e.g. [dressing.nvim](https://github.com/stevearc/dressing.nvim)) is optional but makes the prompt nicer; the default command-line input works fine too.

## Configuration

`setup()` takes a table; defaults shown:

```lua
require("yank2think").setup({
  add_keymap = "<leader>Y", -- visual: append selection (false to skip)
  open_keymap = "<C-y>",    -- normal/visual: open the think buffer (false to skip)
  register = "+",           -- register `y` copies to ("+" = system clipboard)
  prompt = true,            -- ask for a one-line prompt when adding an entry
})
```

Set a keymap to `false` to map it yourself, then call `require("yank2think").add()` / `.open()` from your own mapping.

## Notes

- The think buffer is in-memory and lives for the Neovim session (cleared on quit).
- The file path is resolved relative to the nearest `.git` root, falling back to the current working directory.

## License

MIT
