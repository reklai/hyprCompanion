# HyprCompanion

A Hyprland Lua plugin for controlling native groups like tabs.

This plugs into the Hyprland ecosystem without replacing Hyprland's window model. It uses native Hyprland groups as the real container layer, then adds focused keybinds, a persistent Quickshell menu, and a vertical Container List for managing grouped windows as one working stack.

Use it when several related windows should occupy one workspace slot: editor, tests, docs, terminal, browser, chat, or any other small workflow cluster.

## What It Adds

- A single remembered Container built on native Hyprland groups.
- A fast `SUPER + G` Container Menu powered by a resident Quickshell process.
- Add, move, select, jump, reorder, remove, and close actions for grouped windows.
- Previous/next cycling through the HyprCompanion-managed Container with keyboard and mouse-wheel binds.
- Practical tab names from window title or app class, not raw window addresses.
- Relocatable install: clone it anywhere and point Hyprland at one Lua file.

HyprCompanion manages only the Container anchored through `Add to Container`. Native Hyprland groups created manually outside HyprCompanion are left alone: they do not appear in the Container Menu, and HyprCompanion actions will not select, cycle, reorder, remove, or close their windows.

## Requirements

- Hyprland with Lua config support.
- `hyprctl`
- `bash`
- `jq`
- `quickshell`
- Optional: `notify-send` for desktop notifications.
- Optional: `wofi` for fallback menu behavior when Quickshell is unavailable.

## Installation

Clone HyprCompanion anywhere:

```sh
git clone <repo-url> ~/.local/share/hypr/hyprCompanion
```

Add one line to `hyprland.lua`:

```lua
dofile(os.getenv("HOME") .. "/.local/share/hypr/hyprCompanion/lua/hyprcompanion.lua").setup()
```

Reload Hyprland:

```sh
hyprctl reload
```

HyprCompanion resolves its own project path from the loaded Lua file. The daemon writes `qs/HyprCompanionRuntime.js` with the resolved command path before Quickshell starts, so moving the plugin only requires updating the `dofile(...)` path.

## Optional Loader

If your dotfiles should keep HyprCompanion optional, guard the loader:

```lua
local hyprCompanion = "enable"
local hyprcompanion_path = os.getenv("HOME") .. "/.local/share/hypr/hyprCompanion/lua/hyprcompanion.lua"

local function path_exists(path)
	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end

	return false
end

if hyprCompanion == "enable" and path_exists(hyprcompanion_path) then
	dofile(hyprcompanion_path).setup()
end
```

## Configuration

User-facing defaults live in `lua/hyprcompanion/config.lua`:

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

Change keybinds there. After the initial `dofile(...)`, users should not need to edit `bin/`, `qs/`, or their main Hyprland config to customize HyprCompanion binds.

## Default Binds

- `SUPER + G`: open or close the Container Menu.
- `SUPER + backslash`: next window in the HyprCompanion Container.
- `SUPER + SHIFT + backslash`: previous window in the HyprCompanion Container.
- `SUPER + mouse_up`: next window in the HyprCompanion Container.
- `SUPER + mouse_down`: previous window in the HyprCompanion Container.

## Container Menu

`SUPER + G` opens the menu near the cursor. The left side contains actions, and the right side shows the selected Container window plus a vertical, scrollable list of grouped windows.

```text
+----------------------------------------------------------------+
| HyprCompanion                                      <   >   X        |
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

The menu describes the single HyprCompanion-managed Container. If focus is outside that Container, HyprCompanion falls back to the remembered Container, even when that Container is on another workspace. If focus is inside a separate manual Hyprland group, that group is ignored.

## Actions

- `Add to Container`: move the focused ungrouped window into the remembered Container when possible, or create the first HyprCompanion Container. It refuses windows that are already inside a separate native Hyprland group.
- `Move Container Here`: move every live window in the remembered Container to the current workspace.
- `Remove from Container`: remove the selected grouped window, or forget a one-window Container.
- `Close Window Inside Container`: close the selected Container window normally.
- `Prev` / `Next`: cycle focus inside the visible Container without reordering the list.
- Single click: select a row and update the Container active member without forcing you to stay there.
- Double click: focus that grouped window and keep you there.
- Drag a row: reorder windows inside the native Hyprland group.

## CLI

The menu and binds call `bin/hyprcompanion`, but actions can also be run directly:

```sh
bin/hyprcompanion --help
bin/hyprcompanion daemon
bin/hyprcompanion menu
bin/hyprcompanion add
bin/hyprcompanion move-here
bin/hyprcompanion remove 0x123456
bin/hyprcompanion close 0x123456
bin/hyprcompanion reorder 0x123456 1
bin/hyprcompanion snapshot
bin/hyprcompanion prev
bin/hyprcompanion next
bin/hyprcompanion jump 0x123456
```

## Project Layout

```text
bin/hyprcompanion                  CLI actions and Quickshell daemon launcher
lua/hyprcompanion.lua              Stable Hyprland entry shim
lua/hyprcompanion/init.lua         Setup orchestration
lua/hyprcompanion/config.lua       User-facing keybind defaults
lua/hyprcompanion/binds.lua        Hyprland bind registration
lua/hyprcompanion/group.lua        Native group and groupbar config
qs/shell.qml                   Quickshell overlay
qs/components/ActionButton.qml Reusable QML action control
tests/                         CLI regression tests
```

`qs/HyprCompanionRuntime.js` is generated by `bin/hyprcompanion daemon` and is intentionally ignored by Git.

## Development

Run the checks from the project root:

```sh
bash -n bin/hyprcompanion tests/hyprcompanion_cli_test.sh
bash tests/hyprcompanion_cli_test.sh
luac -p lua/hyprcompanion.lua lua/hyprcompanion/init.lua lua/hyprcompanion/config.lua lua/hyprcompanion/binds.lua lua/hyprcompanion/group.lua
git diff --check
```
