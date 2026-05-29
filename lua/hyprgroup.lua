local source = debug.getinfo(1, "S").source:sub(2)
local dir = assert(source:match("(.*/)"), "Could not resolve HyprGroup entry path")

return dofile(dir .. "hyprgroup/init.lua")
