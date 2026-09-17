-- Runs against Swift-generated palettes in an isolated, long-lived Neovim.
local function run()
  local root = assert(vim.env.MWALL_NVIM_TEST_DIR)
  local live = root .. "/live"
  vim.fn.mkdir(live .. "/colors", "p")
  vim.fn.mkdir(live .. "/plugin", "p")
  vim.opt.runtimepath:prepend(live)
  if vim.loader then
    vim.loader.enable()
  end

  local function read(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*a")
    file:close()
    return data
  end

  local function replace(path, data)
    local file = assert(io.open(path .. ".new", "wb"))
    file:write(data)
    file:close()
    assert(vim.uv.fs_rename(path .. ".new", path))
  end

  local function palette(version, scheme)
    return read(root .. "/" .. version .. "/colors/" .. scheme .. ".lua")
  end

  local schemes = { "mwall", "mwall-dark", "mwall-light" }
  for _, scheme in ipairs(schemes) do
    replace(live .. "/colors/" .. scheme .. ".lua", palette("first", scheme))
  end
  replace(live .. "/plugin/mwall-reload.lua", read(root .. "/first/plugin/mwall-reload.lua"))

  local events, warnings = 0, 0
  vim.notify = function() warnings = warnings + 1 end
  vim.api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      events = events + 1
      -- User transparency/highlight customizations must survive every reload.
      vim.api.nvim_set_hl(0, "Normal", { fg = "#abcdef", bg = "NONE" })
    end,
  })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved work", "keep my cursor" })
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  local buffer = vim.api.nvim_get_current_buf()

  local function foreground()
    return vim.api.nvim_get_hl(0, { name = "Function", link = false }).fg
  end

  local function wait_for(predicate, message)
    assert(vim.wait(3500, predicate, 25), message)
  end

  -- Upgrade an editor that already selected an older generated theme.
  local current_path = live .. "/colors/mwall.lua"
  local legacy = palette("first", "mwall"):gsub('vim.cmd%("runtime plugin/mwall%-reload.lua"%)', "")
  replace(current_path, legacy)
  vim.cmd.colorscheme("mwall")
  assert(not vim.g.loaded_mwall_reload, "legacy fixture unexpectedly loaded the plugin")
  replace(current_path, palette("second", "mwall"))
  vim.cmd("runtime plugin/mwall-reload.lua")
  wait_for(function() return foreground() == 0xd25a96 end, "live activation did not refresh the old session")
  replace(current_path, palette("first", "mwall"))

  for _, scheme in ipairs(schemes) do
    vim.cmd.colorscheme(scheme)
    assert(vim.g.loaded_mwall_reload, "colorscheme did not bootstrap the reloader")
    -- Re-sourcing must not create duplicate timers or autocmds.
    vim.cmd("runtime plugin/mwall-reload.lua")
    vim.cmd("runtime plugin/mwall-reload.lua")
    local before = events
    local path = live .. "/colors/" .. scheme .. ".lua"
    replace(path, palette("second", scheme))
    wait_for(function() return foreground() == 0xd25a96 end, scheme .. " did not reload")
    assert(events == before + 1, "expected exactly one ColorScheme event")
    assert(vim.g.colors_name == scheme, "reload changed the selected variant")
    assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == nil,
      "ColorScheme transparency override was lost")
    local after = events
    replace(path, palette("second", scheme))
    vim.wait(1200, function() return events > after end, 25)
    assert(events == after, "identical content should not reload")

    assert(vim.api.nvim_get_current_buf() == buffer and vim.bo.modified)
    assert(vim.api.nvim_buf_get_lines(buffer, 0, 1, false)[1] == "unsaved work")
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 3 }))
    if scheme == "mwall-dark" then assert(vim.o.background == "dark") end
    if scheme == "mwall-light" then assert(vim.o.background == "light") end
  end

  local path = live .. "/colors/mwall-light.lua"
  replace(path, "this is invalid Lua!")
  wait_for(function() return warnings == 1 end, "invalid Lua was not reported")
  assert(foreground() == 0xd25a96, "invalid Lua destroyed the existing highlights")
  vim.wait(1200, function() return warnings > 1 end, 25)
  assert(warnings == 1, "the same error was reported repeatedly")
  assert(vim.uv.fs_unlink(path))
  vim.wait(1200, function() return warnings > 1 end, 25)
  assert(warnings == 1, "missing file caused notification spam")
  replace(path, palette("first", "mwall-light"))
  wait_for(function() return foreground() == 0x3c82be end, "did not recover after replacement")

  vim.g.mwall_auto_reload = false
  replace(path, palette("second", "mwall-light"))
  local before = events
  vim.wait(1200, function() return events > before end, 25)
  assert(events == before and foreground() == 0x3c82be, "opt-out was ignored")
  vim.g.mwall_auto_reload = true
  wait_for(function() return foreground() == 0xd25a96 end, "did not resume after opt-in")

  vim.cmd.colorscheme("habamax")
  before = events
  for _, scheme in ipairs(schemes) do
    replace(live .. "/colors/" .. scheme .. ".lua", palette("first", scheme))
  end
  vim.wait(1200, function() return events > before end, 25)
  assert(events == before and vim.g.colors_name == "habamax", "unrelated theme was overridden")

  vim.cmd.colorscheme("mwall-dark")
  assert(vim.o.background == "dark")
  vim.cmd.colorscheme("mwall-light")
  assert(vim.o.background == "light", "external dark/light selection stopped working")
  assert(warnings == 1)
  print("MWall live reload PASS: three variants, atomic writes, overrides, recovery, opt-out, buffers")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
