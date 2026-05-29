local M = {}

function M.apply()
	hl.config({
		binds = {
			ignore_group_lock = true,
		},
		group = {
			auto_group = false,
			drag_into_group = 0,
			focus_removed_window = true,
			insert_after_current = true,
			col = {
				border_active = "rgba(5a5c64ff)",
				border_inactive = "rgba(383a40ff)",
				border_locked_active = "rgba(5a5c64ff)",
				border_locked_inactive = "rgba(383a40ff)",
			},
			groupbar = {
				enabled = true,
				scrolling = true,
				render_titles = true,
				stacked = false,
				gradients = true,
				height = 18,
				font_size = 12,
				rounding = 0,
				gaps_in = 0,
				gaps_out = 0,
				indicator_height = 0,
				text_padding = 6,
				col = {
					active = "rgba(3d3e44ff)",
					inactive = "rgba(26272dff)",
					locked_active = "rgba(3d3e44ff)",
					locked_inactive = "rgba(26272dff)",
				},
				text_color = "rgba(f4f4f5ff)",
				text_color_inactive = "rgba(c5c8cfff)",
				text_color_locked_active = "rgba(f4f4f5ff)",
				text_color_locked_inactive = "rgba(c5c8cfff)",
			},
		},
	})
end

return M
