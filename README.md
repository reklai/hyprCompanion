# HyprCompanion

A Hyprland Lua plugin for controlling native groups like tabs.

This plugs into the Hyprland ecosystem without replacing Hyprland's window model. It uses native Hyprland groups as the real container layer, then adds focused keybinds, a persistent Quickshell menu, and a vertical Container List for managing grouped windows as one working stack.

Use it when several related windows should occupy one workspace slot: editor, tests, docs, terminal, browser, chat, or any other small workflow cluster.

## What It Adds

- A single remembered Container built on native Hyprland groups.
- A fast `SUPER + G` Container Menu powered by a resident Quickshell process.
- Add, move, select, jump, reorder, remove, and close actions for grouped windows.
- Previous/next cycling through the HyprGroup-managed Container with keyboard and mouse-wheel binds.
- Practical tab names from window title or app class, not raw window addresses.
- Relocatable install: clone it anywhere and point Hyprland at one Lua file.

HyprGroup manages only the Container anchored through `Add to Container`. Native Hyprland groups created manually outside HyprGroup are left alone: they do not appear in the Container Menu, and HyprGroup actions will not select, cycle, reorder, remove, or close their windows.

## Requirements

- Hyprland with Lua config support.
- `hyprctl`
- `bash`
- `jq`
- `quickshell`
- Optional: `notify-send` for desktop notifications.
- Optional: `wofi` for fallback menu behavior when Quickshell is unavailable.

## Installation

Clone HyprGroup anywhere:

```sh
git clone <repo-url> ~/.local/share/hypr/hyprGroup
```

Add one line to `hyprland.lua`:

```lua
dofile(os.getenv("HOME") .. "/.local/share/hypr/hyprGroup/lua/hyprgroup.lua").setup()
```

Reload Hyprland:

```sh
hyprctl reload
```

HyprGroup resolves its own project path from the loaded Lua file. The daemon writes `qs/HyprGroupRuntime.js` with the resolved command path before Quickshell starts, so moving the plugin only requires updating the `dofile(...)` path.

## Optional Loader

If your dotfiles should keep HyprGroup optional, guard the loader:

```lua
local hyprGroup = "enable"
local hyprgroup_path = os.getenv("HOME") .. "/.local/share/hypr/hyprGroup/lua/hyprgroup.lua"

local function path_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end

	return false
end

if hyprGroup == "enable" and path_exists(hyprgroup_path) then
	dofile(hyprgroup_path).setup()
end
```

## Configuration

User-facing defaults live in `lua/hyprgroup/config.lua`:

```lua
return {
	main_mod = "SUPER",

	binds = {
		menu = "G",
		next = "backslash",
		prev = "SHIFT + backslash",
		mouse_next = "mouse_up",
		mouse_prev = "mouse_down",
	},
}
```

Change keybinds there. After the initial `dofile(...)`, users should not need to edit `bin/`, `qs/`, or their main Hyprland config to customize HyprGroup binds.

## Default Binds

- `SUPER + G`: open or close the Container Menu.
- `SUPER + backslash`: next window in the HyprGroup Container.
- `SUPER + SHIFT + backslash`: previous window in the HyprGroup Container.
- `SUPER + mouse_up`: next window in the HyprGroup Container.
- `SUPER + mouse_down`: previous window in the HyprGroup Container.

## Container Menu

`SUPER + G` opens the menu near the cursor. The left side contains actions, and the right side shows the selected Container window plus a vertical, scrollable list of grouped windows.

```text
+----------------------------------------------------------------+
| HyprGroup                                      <   >   X        |
+--------------------------+-------------------------------------+
| Add to Container         | Active Container              2 / 3 |
| Move Container Here      | tests                               |
| Remove from Container    | ghostty                             |
| Close Window Inside...   +-------------------------------------+
|                          | editor                              |
|                          | tests                               |
|                          | docs                                |
+--------------------------+-------------------------------------+
```

The menu describes the single HyprGroup-managed Container. If focus is outside that Container, HyprGroup falls back to the remembered Container, even when that Container is on another workspace. If focus is inside a separate manual Hyprland group, that group is ignored.

## Actions

- `Add to Container`: move the focused ungrouped window into the remembered Container when possible, or create the first HyprGroup Container. It refuses windows that are already inside a separate native Hyprland group.
- `Move Container Here`: move every live window in the remembered Container to the current workspace.
- `Remove from Container`: remove the selected grouped window, or forget a one-window Container.
- `Close Window Inside Container`: close the selected Container window normally.
- `Prev` / `Next`: cycle focus inside the visible Container without reordering the list.
- Single click: select a row and update the Container active member without forcing you to stay there.
- Double click: focus that grouped window and keep you there.
- Drag a row: reorder windows inside the native Hyprland group.

## CLI

The menu and binds call `bin/hyprgroup`, but actions can also be run directly:

```sh
bin/hyprgroup --help
bin/hyprgroup daemon
bin/hyprgroup menu
bin/hyprgroup add
bin/hyprgroup move-here
bin/hyprgroup remove 0x123456
bin/hyprgroup close 0x123456
bin/hyprgroup reorder 0x123456 1
bin/hyprgroup snapshot
bin/hyprgroup prev
bin/hyprgroup next
bin/hyprgroup jump 0x123456
```

## Project Layout

```text
bin/hyprgroup                  CLI actions and Quickshell daemon launcher
lua/hyprgroup.lua              Stable Hyprland entry shim
lua/hyprgroup/init.lua         Setup orchestration
lua/hyprgroup/config.lua       User-facing keybind defaults
lua/hyprgroup/binds.lua        Hyprland bind registration
lua/hyprgroup/group.lua        Native group and groupbar config
qs/shell.qml                   Quickshell overlay
qs/components/ActionButton.qml Reusable QML action control
tests/                         CLI regression tests
```

`qs/HyprGroupRuntime.js` is generated by `bin/hyprgroup daemon` and is intentionally ignored by Git.

## Development

Run the checks from the project root:

```sh
bash -n bin/hyprgroup tests/hyprgroup_cli_test.sh
bash tests/hyprgroup_cli_test.sh
luac -p lua/hyprgroup.lua lua/hyprgroup/init.lua lua/hyprgroup/config.lua lua/hyprgroup/binds.lua lua/hyprgroup/group.lua
git diff --check
```
