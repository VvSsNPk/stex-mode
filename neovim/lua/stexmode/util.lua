local M = {}

--- Percent-encode STR for use as a value in an
--- `application/x-www-form-urlencoded` POST body.
---
--- `plenary.curl`'s `-d key=value` construction (confirmed by reading
--- its source, `parse.data_body`/`util.kv_to_list`) passes VALUE
--- through to curl verbatim, with no URL-encoding of its own -- so a
--- query containing a space or `&` would otherwise corrupt the body.
--- Done ourselves here instead of relying on that.
function M.url_encode(str)
  if str == nil then
    return ""
  end
  str = tostring(str)
  str = str:gsub("\r?\n", "\r\n")
  str = str:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return str
end

return M
