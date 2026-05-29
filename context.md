# HyprGroup Context

## Purpose

HyprGroup is a small wrapper around Hyprland native groups, positioned as native Hyprland groups controlled like tabs. It uses Hyprland Lua for bindings and group behavior, a Bash command script for dispatch actions, and Quickshell for the popup menu.

The public mental model is that one normal tiled window slot can hold related windows navigated like tabs. The implementation and domain language still use Container, Window, Active Container, Container Menu, and Container List.

HyprGroup owns only one managed Container: the native Hyprland group containing the runtime anchor written by `bin/hyprgroup add`. Native Hyprland groups created manually outside HyprGroup are intentionally unmanaged. They must not appear as HyprGroup Containers, and menu/CLI actions must not select, cycle, reorder, remove, close, or jump to their windows unless they are also part of the anchored Container.

## Current Bindings

Defaults are configured in `lua/hyprgroup/config.lua`; the public integration contract is one stable `lua/hyprgroup.lua` setup insertion plus bind changes inside HyprGroup. HyprGroup is relocatable: `lua/hyprgroup/init.lua` derives the default `bin/hyprgroup` path from the loaded module path, and `bin/hyprgroup daemon` writes `qs/HyprGroupRuntime.js` with the resolved command path before Quickshell starts. The intended personal dotfiles integration is an optional loader such as `hyprGroup = "enable"` plus `path_exists(hyprgroup_path)`, so the project can live in `~/code/personal/hypr/hyprGroup` as a separate repository and be removed or reintroduced without breaking Hyprland.

- `SUPER + G`: toggle the HyprGroup menu.
- `SUPER + mouse_down`: previous window in the managed Container.
- `SUPER + mouse_up`: next window in the managed Container.
- `SUPER + backslash`: next window in the managed Container.
- `SUPER + SHIFT + backslash`: previous window in the managed Container.

## Menu Behavior

- The menu is a resident Quickshell daemon and is toggled through IPC for fast open and close.
- The menu opens near the current cursor position and centers the cursor on the menu top edge when there is room.
- The menu is centered on the active monitor when no cursor position is available.
- The menu uses black and gray surfaces, white text, and neutral active accents.
- The overlay is transparent and input-masked while hidden, so it should not behave like another workspace.
- Close paths are `Esc`, the top-right `X`, or clicking outside the menu.

## Menu Actions

- `Add to Container`: add the active ungrouped window to the managed Container only when it is not already in that Container. If the active Window is already in another native Hyprland group, Add refuses it instead of adopting or modifying that manual group.
- `Move Container Here`: move the remembered Container to the current active workspace without adding the active Window to it; it can run even when the current workspace has no active Window.
- `Remove from Container`: remove the selected Container Window from its Container, or forget a selected one-window Container.
- `Close Window Inside Container`: close the selected Container Window with a normal close request. This destroys the Window; reopening happens through the app/launcher, and the reopened Window starts outside the Container until added again.
- Move Container Here, Remove from Container, and Close Window Inside Container close the menu after dispatching.
- `Prev` and `Next`: header arrow controls for cycling focus through windows in the managed Container. They first focus the remembered Container member when focus is outside it, including when focus is inside an unmanaged manual group. They must not reorder the visual Window List; the selected row follows the cycled active member.
- Action availability follows current context: Add is disabled when there is no active Window, when the active Window is already in the shown Container, or when the active Window is already in an unmanaged native group; Move Container Here is disabled when there is no remembered Container or the active Window is already in that Container; Prev and Next are disabled until the shown Container has at least two Windows; Remove and Close are disabled until a Container Window is selected.

## Window List

- The Window List is rendered as a vertical, scrollable tab list in the right pane, under the active window block.
- Each row represents an actual Hyprland grouped window from the managed Container's native group.
- The remembered Container anchor is command state only; it must not create a list row by itself.
- Group windows are shown as a Ghostty-inspired vertical, scrollable tab list under the active window details: dark gray chrome, soft active row, clear row bounds, readable titles, and a thin neutral active edge. Tab labels prefer Window title, then app class, then `Window N`; raw addresses are not shown as tab labels.
- Dragging a tab inside the Container Menu reorders the grouped Window through `bin/hyprgroup reorder ADDRESS INDEX`; it does not change the native Hyprland groupbar itself.
- Single-clicking a row selects it as the menu target and updates the Container's active member. If focus was outside that Container, HyprGroup restores the original focus so the user does not jump there.
- Double-clicking a row focuses that grouped Window, keeps the menu open, and leaves the user there.
- The selected grouped Window is highlighted with neutral contrast; destructive actions target this highlighted row.

## Right Pane

- The current window block represents the active grouped window when focus is inside the managed Container.
- When focus is outside the managed Container, the current window block falls back to the most recently focused Window inside the remembered Container if that Container still exists.
- The Window List runs downward from the active window block and scrolls when there are more rows than fit.
- The Window List order is stable across focus-cycle snapshots, so Prev/Next changes active selection and preview without making rows jump around.
- Container state feedback only describes whether the current active Hyprland Window is in the managed Container; it does not label remembered fallback state or unmanaged native groups as active.
- If no active or remembered Container exists, the active window block says `No Active Window`.

## Command Notes

- `bin/hyprgroup menu`: toggles the Quickshell menu and passes `hyprctl cursorpos` into the IPC call.
- `bin/hyprgroup daemon`: starts the persistent Quickshell process if it is not already running.
- `bin/hyprgroup add`: checks the active window first. If the window is already in the managed Container, it does nothing. If the window is already in another native Hyprland group, it refuses the action. Otherwise it unsets fullscreen/floating state, brings the remembered Container anchor to the active workspace when needed, moves the active window into the Container when possible, and only creates a new Container when none exists. A runtime state file stores the single Container anchor address so the Container follows the real window/group identity instead of being tied to a workspace. After creating or moving into a group, it locks the active group so future windows tile beside the Container instead of auto-entering it. HyprGroup sets `binds.ignore_group_lock = true` so scripted Add can still enter the locked Container intentionally.
- `bin/hyprgroup move-here`: clears a stale remembered anchor before acting, reads the target from `hyprctl activeworkspace -j`, resolves every live Window in the remembered Container, and moves each off-workspace member to the active workspace with the Lua dispatcher form `hl.dsp.window.move({ workspace = WORKSPACE, window = "address:ADDRESS" })`. If every Container Window is already on the active workspace, it does nothing.
- `bin/hyprgroup reorder ADDRESS INDEX`: moves the grouped Window at `ADDRESS` forward or backward until it reaches the zero-based Container `INDEX`.
- `bin/hyprgroup select ADDRESS`: validates that `ADDRESS` belongs to the managed Container, focuses it to update the native group active member, then restores the original focus when the original focus was outside that Container.
- `bin/hyprgroup close [ADDRESS]`: focuses the selected Container window when needed, repairs the remembered anchor before closing if the selected Window is the anchor, then dispatches `hl.dsp.window.close({})`. If no address is provided, it closes the active managed Container Window or the most recently focused Window in the remembered Container.
- `bin/hyprgroup snapshot`: prints JSON for the managed Container when the remembered anchor still exists. Focus inside an unmanaged native group is ignored; remembered snapshots mark the most recently focused grouped Window active, and include per-Window title and class metadata for practical tab labels.
- `bin/hyprgroup remove [ADDRESS]`: if the target Window is in the managed native Hyprland group, focuses it when needed, dispatches `hl.dsp.window.move({ out_of_group = true })`, and remembers another grouped Window as the Container anchor when the removed Window was the anchor. If the target Window is only the remembered one-window Container, it clears that runtime state instead of dispatching a no-op. If no address is provided and the active Window is outside the managed Container, it does nothing.
- `bin/hyprgroup jump ADDRESS`: validates that `ADDRESS` belongs to the managed Container, then dispatches `hl.dsp.focus({ window = "address:ADDRESS" })`.
- `bin/hyprgroup next` and `bin/hyprgroup prev`: cycle focus through windows in the managed Container. If focus is outside the managed Container, they first focus the most recently focused Window in the remembered Container so the arrows act on the Container shown in the menu.

## Implementation Notes

- `qs/shell.qml` owns the Quickshell UI, Container snapshot consumption, cursor-relative positioning, and IPC methods.
- `qs/components/ActionButton.qml` owns the reusable menu action button.
- `lua/hyprgroup.lua` is the stable Hyprland entry shim for a single `dofile(...).setup()` insertion.
- `lua/hyprgroup/init.lua` owns setup orchestration.
- `lua/hyprgroup/config.lua` owns user-facing HyprGroup defaults, including `main_mod` and keybinds. Users should change keybinds there instead of editing their main `hyprland.lua`; `setup({ script = "..." })` remains available for explicit script overrides.
- `lua/hyprgroup/binds.lua` owns Hyprland bind registration; cycle binds call the HyprGroup CLI instead of native `hl.dsp.group.next/prev` so unmanaged manual groups are not affected.
- `lua/hyprgroup/group.lua` owns native Hyprland group and groupbar config.
- `bin/hyprgroup` owns CLI actions, daemon startup, cursor capture, and Hyprland dispatch calls.
- Hyprland group semantics are native Hyprland behavior; this project provides a simpler menu and shortcuts around them.
- Native Hyprland group tabs and group borders use neutral grays. `group.groupbar.gradients` must stay enabled because Hyprland 0.55.2 ignores `groupbar.col.*` for the visible tab fill when gradients are disabled. The groupbar indicator line is disabled so it does not draw a separate colored accent.
