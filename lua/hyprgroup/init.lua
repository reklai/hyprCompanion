local source = debug.getinfo(1, "S").source:sub(2)
local module_dir = assert(source:match("(.*/)"), "Could not resolve HyprGroup module path")

local binds = dofile(module_dir .. "binds.lua")
local group = dofile(module_dir .. "group.lua")
local project_root = assert(module_dir:match("(.*/)lua/hyprgroup/$"), "Could not resolve HyprGroup project path")
local default_script = project_root .. "bin/hyprgroup"

local M = {}

local function shell_quote(value)
	return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function load_config()
	local config = dofile(module_dir .. "config.lua")

	assert(type(config) == "table", "HyprGroup config.lua must return a table")

	return config
end

local function merged_config(opts)
	local config = load_config()

	opts = opts or {}
	config.binds = config.binds or {}

	for key, value in pairs(opts) do
		if key ~= "binds" then
			config[key] = value
		end
	end

	if type(opts.binds) == "table" then
		for key, value in pairs(opts.binds) do
			config.binds[key] = value
		end
	end

	return config
end

function M.setup(opts)
	local config = merged_config(opts)
	local main_mod = config.main_mod or "SUPER"
	local script = config.script or default_script

	group.apply()
	hl.exec_cmd("HYPRGROUP_COMMAND_PATH=" .. shell_quote(script) .. " " .. shell_quote(script) .. " daemon")
	binds.apply({
		main_mod = main_mod,
		script = script,
		binds = config.binds,
		shell_quote = shell_quote,
	})
end

return M
