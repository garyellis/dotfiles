local wezterm = require 'wezterm'
local config = {}

config.front_end = "OpenGL"
config.enable_kitty_graphics = true

config.color_scheme = 'tokyonight'
-- config.color_scheme = 'Batman'

-- config.colors = {
--  cursor_bg = "#7aa2f7",
--}

config.keys = {
  {key="Enter", mods="SHIFT", action=wezterm.action{SendString="\x1b\r"}},
}

return config

-- Ctrl+Shift+Alt+% - Split horizontally (top/bottom)
-- Ctrl+Shift+Alt+" - Split vertically (left/right)
-- Ctrl+Shift+Arrow - Navigate between panes
