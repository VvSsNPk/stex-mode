--- Insert a \usemodule reference into a buffer.
---
--- Direct Lua port of `stex--insert-usemodule` in stex-mode.el, which
--- is itself a port of `insertUsemodule` in vscode/src/ts/utils.ts:
--- insert after \begin{document}, skipping blank lines and existing
--- \usemodule/\importmodule lines; if there is no \begin{document} at
--- all, insert at the very top of the buffer (matching that
--- function's actual fallback behavior).

local M = {}

local function should_skip(line)
  return line:match("^%s*$") ~= nil
    or line:match("^%s*\\usemodule") ~= nil
    or line:match("^%s*\\importmodule") ~= nil
end

--- In buffer BUFNR (current buffer if nil), insert a \usemodule
--- reference to ARCHIVE's MODULE_PATH.
function M.insert_usemodule(bufnr, archive, module_path)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- 0-indexed row to insert before; 0 (the very top) unless a
  -- \begin{document} is found.  Note `i`, the 1-indexed position of
  -- the \begin{document} line itself, already equals the 0-indexed
  -- position of the line right after it -- no +1 needed.
  local insert_at = 0
  for i, line in ipairs(lines) do
    if line:match("\\begin{document}") then
      insert_at = i
      while lines[insert_at + 1] and should_skip(lines[insert_at + 1]) do
        insert_at = insert_at + 1
      end
      break
    end
  end
  local text = ("\\usemodule[%s]{%s}"):format(archive, module_path)
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { text })
end

return M
