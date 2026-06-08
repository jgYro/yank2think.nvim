------------------
--
--
-- yank2think -- collect code selections into an LLM-ready markdown buffer
--
--
------------------

-- Workflow (Harpoon-ish):
--   * <leader>Y (visual)  -> append the selection (repo-relative path, line
--                            range, language-fenced code, optional prompt) as a
--                            new entry in a persistent "think buffer".
--   * <C-y> (normal/visual) -> open that buffer in a floating, Magit-style view:
--                            each entry is a collapsible markdown section.
--   In the float:  <Tab> fold/unfold the entry · y copy ALL to clipboard ·
--                  C clear · q/<Esc> close. The buffer is editable, so you can
--                  tweak entries before copying, and edits persist across opens.
--
-- The buffer itself IS the markdown that gets copied -- no hidden state to keep
-- in sync.

local M = {}

M.buf = nil -- persistent scratch buffer holding the accumulated markdown
M.win = nil -- current floating window (or nil)

--------------------------------------------------------------------------------
-- Capturing a selection
--------------------------------------------------------------------------------

-- File path relative to the git root if there is one, else relative to cwd.
local function relative_path()
  local full = vim.api.nvim_buf_get_name(0)
  if full == "" then
    return "[No Name]"
  end
  local root = vim.fs.root(0, ".git")
  if root and full:sub(1, #root) == root then
    return full:sub(#root + 2) -- strip "<root>/"
  end
  return vim.fn.fnamemodify(full, ":.")
end

-- Sorted line range of the current visual selection. Read via getpos('v') and
-- getpos('.') so it works while still IN visual mode.
local function visual_line_range()
  local l1 = vim.fn.getpos("v")[2]
  local l2 = vim.fn.getpos(".")[2]
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  return l1, l2
end

-- Render one entry as a markdown section (pure -> testable). The "## " header is
-- what the fold expression keys on, so every entry is one collapsible section.
function M.entry_lines(opts)
  local range = (opts.l1 == opts.l2) and ("L" .. opts.l1) or ("L" .. opts.l1 .. "-" .. opts.l2)
  local out = { ("## %s (%s)"):format(opts.path, range) }
  if opts.prompt and opts.prompt ~= "" then
    table.insert(out, "> " .. opts.prompt)
  end
  table.insert(out, "")
  table.insert(out, "```" .. (opts.lang or ""))
  for _, line in ipairs(opts.lines) do
    table.insert(out, line)
  end
  table.insert(out, "```")
  return out
end

--------------------------------------------------------------------------------
-- The persistent think buffer
--------------------------------------------------------------------------------

local function ensure_buf()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    return M.buf
  end
  M.buf = vim.api.nvim_create_buf(false, true) -- unlisted scratch
  vim.bo[M.buf].bufhidden = "hide" -- survive closing the float
  vim.bo[M.buf].filetype = "markdown"
  return M.buf
end

local function entry_count(buf)
  local n = 0
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:match("^## ") then
      n = n + 1
    end
  end
  return n
end

-- Append rendered lines to the buffer (a blank separator before all but the
-- first entry).
local function append_lines(buf, lines)
  local existing = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local empty = #existing == 0 or (#existing == 1 and existing[1] == "")
  local prefix = empty and {} or { "" }
  local at = empty and 0 or -1
  vim.api.nvim_buf_set_lines(buf, at, -1, false, vim.list_extend(prefix, lines))
end

-- <leader>Y: capture the selection and append it (optionally prompting first).
function M.add()
  local l1, l2 = visual_line_range()
  local lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
  local path = relative_path()
  local lang = vim.bo.filetype
  local buf = ensure_buf()

  -- Leave visual mode so the highlight clears before the input prompt.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)

  local function finish(prompt)
    append_lines(buf, M.entry_lines({ path = path, l1 = l1, l2 = l2, lang = lang, lines = lines, prompt = prompt }))
    vim.notify(("yank2think: added entry (%d total) -- %s to view"):format(entry_count(buf), M.config.open_keymap or "<C-y>"), vim.log.levels.INFO)
  end

  if M.config.prompt then
    -- Defer the prompt: the <Esc> fed above is still in the typeahead and would
    -- otherwise be swallowed by vim.ui.input, instantly cancelling it. Schedule
    -- runs after the typeahead drains (and visual mode has exited).
    vim.schedule(function()
      vim.ui.input({ prompt = "Prompt (optional): " }, finish)
    end)
  else
    finish(nil)
  end
end

--------------------------------------------------------------------------------
-- The floating, foldable view
--------------------------------------------------------------------------------

-- foldexpr: start a new level-1 fold at every "## " header, so each entry is its
-- own collapsible section.
function M.foldexpr()
  if vim.fn.getline(vim.v.lnum):match("^## ") then
    return ">1"
  end
  return "1"
end

-- Compact one-line summary shown for a collapsed entry.
function M.foldtext()
  local header = vim.fn.getline(vim.v.foldstart)
  local lnum = vim.v.foldend - vim.v.foldstart + 1
  return ("  ▸ %s  (%d lines)"):format(header:gsub("^##%s*", ""), lnum)
end

function M.close()
  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
  end
  M.win = nil
end

-- y: copy the whole buffer (live edits included) to the clipboard register.
local function copy_all()
  local buf = M.buf
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  -- Trim trailing blank lines.
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  if #lines == 0 then
    vim.notify("yank2think: buffer is empty", vim.log.levels.WARN)
    return
  end
  vim.fn.setreg(M.config.register, table.concat(lines, "\n"))
  vim.notify(("yank2think: copied %d entries to %s"):format(entry_count(buf), M.config.register == "+" and "clipboard" or ("@" .. M.config.register)), vim.log.levels.INFO)
  M.close()
end

local function clear_all()
  if M.buf and vim.api.nvim_buf_is_valid(M.buf) then
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, {})
  end
  vim.notify("yank2think: buffer cleared", vim.log.levels.INFO)
end

-- <C-y>: open the think buffer in a centered float with folds + buffer maps.
function M.open()
  local buf = ensure_buf()
  if entry_count(buf) == 0 then
    vim.notify("yank2think: buffer is empty -- select code and press " .. (M.config.add_keymap or "<leader>Y"), vim.log.levels.INFO)
    return
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  M.win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " yank2think  ·  <Tab> fold  ·  y copy  ·  C clear  ·  q close ",
    title_pos = "center",
  })

  local w = M.win
  vim.wo[w].foldmethod = "expr"
  vim.wo[w].foldexpr = 'v:lua.require("yank2think").foldexpr()'
  vim.wo[w].foldtext = 'v:lua.require("yank2think").foldtext()'
  vim.wo[w].fillchars = "fold: "
  vim.wo[w].foldenable = true
  vim.wo[w].foldlevel = 0 -- start collapsed: a compact, tabbed list of entries
  vim.wo[w].wrap = true
  vim.wo[w].conceallevel = 2

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<Tab>", "za", "Toggle entry fold")
  map("y", copy_all, "Copy all entries to clipboard")
  map("C", clear_all, "Clear think buffer")
  map("q", M.close, "Close")
  map("<Esc>", M.close, "Close")
end

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local defaults = {
  add_keymap = "<leader>Y", -- visual: append selection (false to skip)
  open_keymap = "<C-y>", -- normal/visual: open the think buffer (false to skip)
  register = "+", -- where `y` in the view copies to
  prompt = true, -- ask for a one-line prompt when adding
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  if M.config.add_keymap then
    vim.keymap.set("v", M.config.add_keymap, M.add, { desc = "yank2think: add selection", silent = true })
  end
  if M.config.open_keymap then
    -- Open the think buffer from normal OR visual mode (leaving visual mode).
    vim.keymap.set({ "n", "x" }, M.config.open_keymap, M.open, { desc = "yank2think: open" })
  end
end

return M
