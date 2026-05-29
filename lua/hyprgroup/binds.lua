local M = {}

local function bind_key(main_mod, key)
	if not key or key == "" then
		return nil
	end

	return main_mod .. " + " .. tostring(key)
end

local function bind_if_set(main_mod, key, dispatcher)
	local bind = bind_key(main_mod, key)

	if bind then
		hl.bind(bind, dispatcher)
	end
end

function M.apply(opts)
	local main_mod = opts.main_mod
	local script = opts.script
	local binds = opts.binds or {}
	local shell_quote = opts.shell_quote

	bind_if_set(main_mod, binds.mouse_prev, hl.dsp.group.prev({}))
	bind_if_set(main_mod, binds.mouse_next, hl.dsp.group.next({}))
	bind_if_set(main_mod, binds.prev, hl.dsp.group.prev({}))
	bind_if_set(main_mod, binds.next, hl.dsp.group.next({}))
	bind_if_set(main_mod, binds.menu, hl.dsp.exec_cmd(shell_quote(script) .. " menu"))
end

return M
