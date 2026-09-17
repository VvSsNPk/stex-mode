if vim.g.loaded_stexmode then
  return
end
vim.g.loaded_stexmode = true

vim.api.nvim_create_user_command("StexMathhubSearchSymbols", function()
  require("stexmode.telescope.search_symbols").search_symbols()
end, {
  desc = "Fuzzy-search FLAMS's indexed sTeX symbols and insert a \\usemodule",
})
