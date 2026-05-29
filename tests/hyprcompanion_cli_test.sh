#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
subject="${repo_root}/bin/hyprcompanion"
tmp_dir="$(mktemp -d)"
runtime_config_file="${repo_root}/qs/HyprCompanionRuntime.js"
runtime_config_backup="${tmp_dir}/HyprCompanionRuntime.js.backup"
runtime_config_had_file=false

if [[ -f "$runtime_config_file" ]]; then
	cp "$runtime_config_file" "$runtime_config_backup"
	runtime_config_had_file=true
fi

cleanup() {
	if [[ "$runtime_config_had_file" == true ]]; then
		cp "$runtime_config_backup" "$runtime_config_file"
	else
		rm -f "$runtime_config_file"
	fi

	rm -rf "$tmp_dir"
}

trap cleanup EXIT

mock_bin="${tmp_dir}/bin"
runtime_dir="${tmp_dir}/runtime"
active_json="${tmp_dir}/active.json"
active_after_move_json="${tmp_dir}/active-after-move.json"
active_workspace_json="${tmp_dir}/active-workspace.json"
clients_json="${tmp_dir}/clients.json"
dispatch_log="${tmp_dir}/dispatch.log"
notify_log="${tmp_dir}/notify.log"
quickshell_log="${tmp_dir}/quickshell.log"

mkdir -p "$mock_bin" "$runtime_dir"
: >"$dispatch_log"
: >"$notify_log"
: >"$quickshell_log"
printf '[]\n' >"$clients_json"

cat >"${mock_bin}/hyprctl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
	activewindow)
		cat "$HYPRCOMPANION_TEST_ACTIVE_JSON"
		;;
	activeworkspace)
		cat "$HYPRCOMPANION_TEST_ACTIVE_WORKSPACE_JSON"
		;;
	clients)
		cat "$HYPRCOMPANION_TEST_CLIENTS_JSON"
		;;
	dispatch)
		dispatcher="${2:-}"
		args="${3:-}"

		if [[ -n "$args" ]]; then
			command="${dispatcher} ${args}"
		else
			command="$dispatcher"
		fi

		printf '%s\n' "$command" >>"$HYPRCOMPANION_TEST_DISPATCH_LOG"

		if [[ -n "${HYPRCOMPANION_TEST_FAIL_DISPATCH:-}" && "$command" == *"$HYPRCOMPANION_TEST_FAIL_DISPATCH"* ]]; then
			exit 1
		fi

		if [[ -n "${HYPRCOMPANION_TEST_ERROR_DISPATCH:-}" && "$command" == *"$HYPRCOMPANION_TEST_ERROR_DISPATCH"* ]]; then
			printf 'error: fake dispatcher parse error\n'
			exit 0
		fi

		if [[ "$command" == hl.dsp.window.move* && "$command" =~ workspace[[:space:]]*=[[:space:]]*(-?[0-9]+) ]]; then
			workspace="${BASH_REMATCH[1]}"
			if [[ "$command" =~ window[[:space:]]*=[[:space:]]*\"address:(0x[0-9a-fA-F]+)\" ]]; then
				address="${BASH_REMATCH[1]}"
				tmp="${HYPRCOMPANION_TEST_CLIENTS_JSON}.$$"
				jq --arg address "$address" --argjson workspace "$workspace" 'map(if .address == $address then (.workspace.id = $workspace) else . end)' "$HYPRCOMPANION_TEST_CLIENTS_JSON" >"$tmp"
				mv "$tmp" "$HYPRCOMPANION_TEST_CLIENTS_JSON"
			else
				address="$(jq -r '.address' "$HYPRCOMPANION_TEST_ACTIVE_JSON")"
				tmp="${HYPRCOMPANION_TEST_CLIENTS_JSON}.$$"
				jq --arg address "$address" --argjson workspace "$workspace" 'map(if .address == $address then (.workspace.id = $workspace) else . end)' "$HYPRCOMPANION_TEST_CLIENTS_JSON" >"$tmp"
				mv "$tmp" "$HYPRCOMPANION_TEST_CLIENTS_JSON"
				tmp="${HYPRCOMPANION_TEST_ACTIVE_JSON}.$$"
				jq --argjson workspace "$workspace" '.workspace.id = $workspace' "$HYPRCOMPANION_TEST_ACTIVE_JSON" >"$tmp"
				mv "$tmp" "$HYPRCOMPANION_TEST_ACTIVE_JSON"
			fi
		elif [[ "$command" =~ address:(0x[0-9a-fA-F]+) ]]; then
			address="${BASH_REMATCH[1]}"
			jq --arg address "$address" '.[] | select(.address == $address)' "$HYPRCOMPANION_TEST_CLIENTS_JSON" >"$HYPRCOMPANION_TEST_ACTIVE_JSON"
		elif [[ "$command" == *"into_or_create_group"* && -n "${HYPRCOMPANION_TEST_ACTIVE_AFTER_MOVE_JSON:-}" && -f "$HYPRCOMPANION_TEST_ACTIVE_AFTER_MOVE_JSON" ]]; then
			cat "$HYPRCOMPANION_TEST_ACTIVE_AFTER_MOVE_JSON" >"$HYPRCOMPANION_TEST_ACTIVE_JSON"
		fi
		;;
	cursorpos)
		printf '100, 100\n'
		;;
	*)
		printf 'unexpected hyprctl command: %s\n' "$*" >&2
		exit 64
		;;
esac
MOCK

cat >"${mock_bin}/notify-send" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HYPRCOMPANION_TEST_NOTIFY_LOG"
MOCK

cat >"${mock_bin}/quickshell" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$HYPRCOMPANION_TEST_QUICKSHELL_LOG"

case "${1:-}" in
	list)
		exit 0
		;;
	--path)
		exit 0
		;;
	ipc)
		exit 0
		;;
	*)
		printf 'unexpected quickshell command: %s\n' "$*" >&2
		exit 64
		;;
esac
MOCK

chmod +x "${mock_bin}/hyprctl" "${mock_bin}/notify-send" "${mock_bin}/quickshell"

export HYPRCOMPANION_TEST_ACTIVE_JSON="$active_json"
export HYPRCOMPANION_TEST_ACTIVE_AFTER_MOVE_JSON="$active_after_move_json"
export HYPRCOMPANION_TEST_ACTIVE_WORKSPACE_JSON="$active_workspace_json"
export HYPRCOMPANION_TEST_CLIENTS_JSON="$clients_json"
export HYPRCOMPANION_TEST_DISPATCH_LOG="$dispatch_log"
export HYPRCOMPANION_TEST_ERROR_DISPATCH=""
export HYPRCOMPANION_TEST_FAIL_DISPATCH=""
export HYPRCOMPANION_TEST_NOTIFY_LOG="$notify_log"
export HYPRCOMPANION_TEST_QUICKSHELL_LOG="$quickshell_log"
export PATH="${mock_bin}:${PATH}"
export XDG_RUNTIME_DIR="$runtime_dir"

state_file="${runtime_dir}/hyprcompanion-containers.tsv"

reset_logs() {
	: >"$dispatch_log"
	: >"$notify_log"
	: >"$quickshell_log"
	HYPRCOMPANION_TEST_ERROR_DISPATCH=""
	HYPRCOMPANION_TEST_FAIL_DISPATCH=""
	rm -f "$active_after_move_json"
}

write_active() {
	printf '%s\n' "$1" >"$active_json"

	if jq -e '.workspace.id | numbers' "$active_json" >/dev/null 2>&1; then
		jq -c '{id: .workspace.id, name: ((.workspace.name // (.workspace.id | tostring)) | tostring)}' "$active_json" >"$active_workspace_json"
	else
		printf '{}\n' >"$active_workspace_json"
	fi
}

write_active_workspace() {
	local workspace="$1"

	printf '{"id":%s,"name":"%s"}\n' "$workspace" "$workspace" >"$active_workspace_json"
}

assert_file_equals() {
	local file="$1"
	local expected="$2"
	local actual

	actual="$(cat "$file" 2>/dev/null || true)"

	if [[ "$actual" != "$expected" ]]; then
		printf 'Expected %s to contain:\n%s\nActual:\n%s\n' "$file" "$expected" "$actual" >&2
		return 1
	fi
}

assert_no_notifications() {
	assert_file_equals "$notify_log" ""
}

test_daemon_writes_runtime_config_with_current_script_path() {
	reset_logs
	rm -f "$runtime_config_file"

	bash "$subject" daemon

	assert_file_equals "$runtime_config_file" $'.pragma library\nvar commandPath = "'"$subject"$'";'
	assert_file_equals "$quickshell_log" $'list --path '"${repo_root}"$'/bin/../qs --any-display\n--path '"${repo_root}"$'/bin/../qs --daemonize'
}

test_daemon_runtime_config_respects_command_path_override() {
	local override="${tmp_dir}/custom/hyprcompanion"

	reset_logs
	rm -f "$runtime_config_file"

	HYPRCOMPANION_COMMAND_PATH="$override" bash "$subject" daemon

	assert_file_equals "$runtime_config_file" $'.pragma library\nvar commandPath = "'"$override"$'";'
	assert_file_equals "$quickshell_log" $'list --path '"${repo_root}"$'/bin/../qs --any-display\n--path '"${repo_root}"$'/bin/../qs --daemonize'
}

test_menu_calls_hyprcompanion_ipc_target() {
	reset_logs
	rm -f "$runtime_config_file"

	bash "$subject" menu

	assert_file_equals "$runtime_config_file" $'.pragma library\nvar commandPath = "'"$subject"$'";'
	assert_file_equals "$quickshell_log" $'list --path '"${repo_root}"$'/bin/../qs --any-display\n--path '"${repo_root}"$'/bin/../qs --daemonize\nipc --path '"${repo_root}"$'/bin/../qs --any-display call hyprcompanion toggleAt 100 100'
}

test_lua_setup_derives_default_script_from_loaded_path() {
	local expected
	local output

	output="$(
		lua <<LUA
hl = {}

function hl.config(_)
end

function hl.exec_cmd(command)
	print(command)
end

function hl.bind(bind, dispatcher)
	print(bind .. " => " .. dispatcher)
end

hl.dsp = {
	exec_cmd = function(command)
		return "exec:" .. command
	end,
	group = {
		prev = function()
			return "group.prev"
		end,
		next = function()
			return "group.next"
		end,
	},
}

dofile("${repo_root}/lua/hyprcompanion.lua").setup({
	binds = {
		menu = "G",
		next = "",
		prev = "",
		mouse_next = "",
		mouse_prev = "",
	},
})
LUA
	)"

	expected="HYPRCOMPANION_COMMAND_PATH='${subject}' '${subject}' daemon"
	expected+=$'\n'
	expected+="SUPER + G => exec:'${subject}' menu"

	if [[ "$output" != "$expected" ]]; then
		printf 'Unexpected Lua setup output:\n%s\n' "$output" >&2
		return 1
	fi
}

test_lua_setup_routes_cycle_binds_through_script() {
	local expected
	local output

	output="$(
		lua <<LUA
hl = {}

function hl.config(_)
end

function hl.exec_cmd(command)
	print(command)
end

function hl.bind(bind, dispatcher)
	print(bind .. " => " .. dispatcher)
end

hl.dsp = {
	exec_cmd = function(command)
		return "exec:" .. command
	end,
}

dofile("${repo_root}/lua/hyprcompanion.lua").setup({
	binds = {
		menu = "",
		next = "backslash",
		prev = "SHIFT + backslash",
		mouse_next = "mouse_up",
		mouse_prev = "mouse_down",
	},
})
LUA
	)"

	expected="HYPRCOMPANION_COMMAND_PATH='${subject}' '${subject}' daemon"
	expected+=$'\n'
	expected+="SUPER + mouse_down => exec:'${subject}' prev"
	expected+=$'\n'
	expected+="SUPER + mouse_up => exec:'${subject}' next"
	expected+=$'\n'
	expected+="SUPER + SHIFT + backslash => exec:'${subject}' prev"
	expected+=$'\n'
	expected+="SUPER + backslash => exec:'${subject}' next"

	if [[ "$output" != "$expected" ]]; then
		printf 'Unexpected Lua cycle bind output:\n%s\n' "$output" >&2
		return 1
	fi
}

test_remove_remembered_one_window_container() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf 'anchor\t0xaaa\n' >"$state_file"
	printf '[{"address":"0xaaa","workspace":{"id":1}}]\n' >"$clients_json"

	bash "$subject" remove

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_no_notifications
}

test_remove_native_group_remembers_remaining_window() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf 'anchor\t0xaaa\n' >"$state_file"
	printf '[{"address":"0xaaa","workspace":{"id":1}},{"address":"0xbbb","workspace":{"id":1}}]\n' >"$clients_json"

	bash "$subject" remove

	assert_file_equals "$dispatch_log" 'hl.dsp.window.move({ out_of_group = true })'
	assert_file_equals "$state_file" $'anchor\t0xbbb'
	assert_no_notifications
}

test_remove_outside_container_is_noop() {
	reset_logs
	write_active '{"address":"0xccc","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0xccc","workspace":{"id":1}}]\n' >"$clients_json"
	: >"$state_file"

	bash "$subject" remove

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_no_notifications
}

test_remove_unmanaged_native_group_is_noop() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}]\n' >"$clients_json"
	: >"$state_file"

	bash "$subject" remove

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_no_notifications
}

test_remove_selected_remembered_anchor_remembers_remaining_window() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" remove 0x111

	assert_file_equals "$dispatch_log" $'hl.dsp.focus({ window = "address:0x111" })\nhl.dsp.window.move({ out_of_group = true })'
	assert_file_equals "$state_file" $'anchor\t0x222'
	assert_no_notifications
}

test_remove_rejects_selected_window_outside_container() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '%s\n' \
		'[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},' \
		'{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	if bash "$subject" remove 0x999; then
		printf 'Expected remove outside Container to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" $'anchor\t0xaaa'
	assert_file_equals "$notify_log" "HyprCompanion Window is not in the Container."
}

test_select_group_window_restores_original_focus_when_focus_is_outside_container() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" select 0x222

	assert_file_equals "$dispatch_log" $'hl.dsp.focus({ window = "address:0x222" })\nhl.dsp.focus({ window = "address:0x999" })'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_no_notifications
}

test_select_group_window_keeps_focus_when_active_is_same_container() {
	reset_logs
	write_active '{"address":"0x111","monitor":1,"workspace":{"id":1},"grouped":["0x111","0x222"]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":1},"grouped":["0x111","0x222"]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" select 0x222

	assert_file_equals "$dispatch_log" 'hl.dsp.focus({ window = "address:0x222" })'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_no_notifications
}

test_select_rejects_window_outside_container() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '%s\n' \
		'[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},' \
		'{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	if bash "$subject" select 0x999; then
		printf 'Expected select outside Container to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" $'anchor\t0xaaa'
	assert_file_equals "$notify_log" "HyprCompanion Window is not in the Container."
}

test_add_remembered_one_window_container_is_noop() {
	reset_logs
	write_active '{"address":"0xddd","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf 'anchor\t0xddd\n' >"$state_file"
	printf '[{"address":"0xddd","workspace":{"id":1}}]\n' >"$clients_json"

	bash "$subject" add

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" $'anchor\t0xddd'
	assert_no_notifications
}

test_add_new_container_remembers_global_anchor() {
	reset_logs
	write_active '{"address":"0xeee","monitor":1,"workspace":{"id":2},"at":[0,0],"size":[100,100],"floating":false,"fullscreen":0,"grouped":[]}'
	printf '[{"address":"0xeee","workspace":{"id":2},"monitor":1,"at":[0,0],"size":[100,100],"grouped":[]}]\n' >"$clients_json"
	: >"$state_file"

	bash "$subject" add

	assert_file_equals "$dispatch_log" $'hl.dsp.window.fullscreen({ action = "unset" })\nhl.dsp.window.float({ action = "off" })\nhl.dsp.group.toggle({})\nhl.dsp.group.lock_active({ action = "lock" })'
	assert_file_equals "$state_file" $'anchor\t0xeee'
	assert_no_notifications
}

test_add_brings_global_container_to_active_workspace() {
	reset_logs
	write_active '{"address":"0x222","monitor":1,"workspace":{"id":2},"at":[300,0],"size":[100,100],"floating":false,"fullscreen":0,"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"monitor":1,"at":[0,0],"size":[100,100],"grouped":["0x111"]},' \
		'{"address":"0x222","workspace":{"id":2},"monitor":1,"at":[300,0],"size":[100,100],"grouped":[]}]' \
		>"$clients_json"
	printf '{"address":"0x222","monitor":1,"workspace":{"id":2},"at":[300,0],"size":[100,100],"floating":false,"fullscreen":0,"grouped":["0x111","0x222"]}\n' >"$active_after_move_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" add

	assert_file_equals "$dispatch_log" $'hl.dsp.window.fullscreen({ action = "unset" })\nhl.dsp.window.float({ action = "off" })\nhl.dsp.window.move({ workspace = 2, window = "address:0x111" })\nhl.dsp.window.move({ into_or_create_group = "l" })\nhl.dsp.group.lock_active({ action = "lock" })'
	assert_file_equals "$state_file" $'anchor\t0x222'
	assert_no_notifications
}

test_add_rejects_unmanaged_native_group() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}]\n' >"$clients_json"
	: >"$state_file"

	if bash "$subject" add; then
		printf 'Expected add from unmanaged native group to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_file_equals "$notify_log" "HyprCompanion Active window is already in another native group."
}

test_move_container_here_moves_remembered_container_to_active_workspace() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":2},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":2},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" move-here

	assert_file_equals "$dispatch_log" $'hl.dsp.window.move({ workspace = 2, window = "address:0x111" })\nhl.dsp.window.move({ workspace = 2, window = "address:0x222" })'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_no_notifications
}

test_move_container_here_works_without_active_window() {
	reset_logs
	write_active '{}'
	write_active_workspace 3
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":1},"grouped":["0x111","0x222"]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" move-here

	assert_file_equals "$dispatch_log" $'hl.dsp.window.move({ workspace = 3, window = "address:0x111" })\nhl.dsp.window.move({ workspace = 3, window = "address:0x222" })'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_no_notifications
}

test_move_container_here_is_noop_when_container_is_already_here() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" move-here

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_no_notifications
}

test_move_container_here_rejects_without_remembered_container() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0x999","workspace":{"id":1},"grouped":[]}]\n' >"$clients_json"
	: >"$state_file"

	if bash "$subject" move-here; then
		printf 'Expected move-here without remembered Container to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_file_equals "$notify_log" "HyprCompanion No Container to move."
}

test_move_container_here_cleans_stale_anchor() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0x999","workspace":{"id":1},"grouped":[]}]\n' >"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	if bash "$subject" move-here; then
		printf 'Expected move-here with stale Container to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_file_equals "$notify_log" "HyprCompanion No Container to move."
}

test_move_container_here_reports_failure_when_member_move_fails() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":2},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":2},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"
	HYPRCOMPANION_TEST_FAIL_DISPATCH='hl.dsp.window.move({ workspace = 2, window = "address:0x111" })'

	if bash "$subject" move-here; then
		printf 'Expected move-here dispatch failure to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" 'hl.dsp.window.move({ workspace = 2, window = "address:0x111" })'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_file_equals "$notify_log" $'HyprCompanion Hyprland did not accept the container command.\nHyprCompanion Could not move the Container.'
}

test_move_container_here_reports_failure_when_dispatcher_prints_error() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":2},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":1},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":2},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"
	HYPRCOMPANION_TEST_ERROR_DISPATCH='hl.dsp.window.move({ workspace = 2, window = "address:0x111" })'

	if bash "$subject" move-here; then
		printf 'Expected move-here dispatcher error output to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" 'hl.dsp.window.move({ workspace = 2, window = "address:0x111" })'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_file_equals "$notify_log" $'HyprCompanion Hyprland did not accept the container command.\nHyprCompanion Could not move the Container.'
}

test_reorder_moves_group_window_forward_to_index() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]}'
	printf '%s\n' \
		'[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]},' \
		'{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]},' \
		'{"address":"0xccc","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	bash "$subject" reorder 0xaaa 2

	assert_file_equals "$dispatch_log" $'hl.dsp.group.move_window({ forward = true, window = "address:0xaaa" })\nhl.dsp.group.move_window({ forward = true, window = "address:0xaaa" })'
	assert_no_notifications
}

test_reorder_moves_group_window_backward_to_index() {
	reset_logs
	write_active '{"address":"0xccc","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]}'
	printf '%s\n' \
		'[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]},' \
		'{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]},' \
		'{"address":"0xccc","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	bash "$subject" reorder 0xccc 0

	assert_file_equals "$dispatch_log" $'hl.dsp.group.move_window({ forward = false, window = "address:0xccc" })\nhl.dsp.group.move_window({ forward = false, window = "address:0xccc" })'
	assert_no_notifications
}

test_reorder_single_window_container_is_noop() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":[]}]\n' >"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	bash "$subject" reorder 0xaaa 0

	assert_file_equals "$dispatch_log" ""
	assert_no_notifications
}

test_reorder_rejects_unmanaged_native_group() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}]\n' >"$clients_json"
	: >"$state_file"

	if bash "$subject" reorder 0xaaa 1; then
		printf 'Expected reorder from unmanaged native group to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_file_equals "$notify_log" "HyprCompanion Window is not in the Container."
}

test_close_active_grouped_window_keeps_anchor() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}]\n' >"$clients_json"
	printf 'anchor\t0xbbb\n' >"$state_file"

	bash "$subject" close 0xaaa

	assert_file_equals "$dispatch_log" 'hl.dsp.window.close({})'
	assert_file_equals "$state_file" $'anchor\t0xbbb'
	assert_no_notifications
}

test_close_remembered_anchor_remembers_remaining_window() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" close 0x111

	assert_file_equals "$dispatch_log" $'hl.dsp.focus({ window = "address:0x111" })\nhl.dsp.window.close({})'
	assert_file_equals "$state_file" $'anchor\t0x222'
	assert_no_notifications
}

test_close_remembered_active_when_focus_is_outside_group() {
	reset_logs
	write_active '{"address":"0x999","monitor":1,"workspace":{"id":1},"grouped":[],"focusHistoryID":0}'
	printf '%s\n' \
		'[{"address":"0x111","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":8},' \
		'{"address":"0x222","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":2},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[],"focusHistoryID":0}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" close

	assert_file_equals "$dispatch_log" $'hl.dsp.focus({ window = "address:0x222" })\nhl.dsp.window.close({})'
	assert_file_equals "$state_file" $'anchor\t0x111'
	assert_no_notifications
}

test_close_one_window_container_forgets_anchor() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":[]}]\n' >"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	bash "$subject" close

	assert_file_equals "$dispatch_log" 'hl.dsp.window.close({})'
	assert_file_equals "$state_file" ""
	assert_no_notifications
}

test_close_rejects_window_outside_container() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '%s\n' \
		'[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},' \
		'{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},' \
		'{"address":"0x999","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	if bash "$subject" close 0x999; then
		printf 'Expected close outside Container to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" $'anchor\t0xaaa'
	assert_file_equals "$notify_log" "HyprCompanion Window is not in the Container."
}

test_jump_rejects_unmanaged_native_group() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}]\n' >"$clients_json"
	: >"$state_file"

	if bash "$subject" jump 0xbbb; then
		printf 'Expected jump from unmanaged native group to fail.\n' >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_file_equals "$notify_log" "HyprCompanion Window is not in the Container."
}

test_next_focuses_remembered_container_when_focus_is_outside_group() {
	reset_logs
	write_active '{"address":"0x999","title":"Loose terminal","class":"foot","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","title":"Editor","class":"code","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":8},' \
		'{"address":"0x222","title":"Tests","class":"foot","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":2},' \
		'{"address":"0x999","title":"Loose terminal","class":"foot","workspace":{"id":1},"grouped":[],"focusHistoryID":0}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" next

	assert_file_equals "$dispatch_log" $'hl.dsp.focus({ window = "address:0x222" })\nhl.dsp.group.next({})'
	assert_no_notifications
}

test_prev_focuses_remembered_container_when_focus_is_outside_group() {
	reset_logs
	write_active '{"address":"0x999","title":"Loose terminal","class":"foot","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","title":"Editor","class":"code","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":8},' \
		'{"address":"0x222","title":"Tests","class":"foot","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":2},' \
		'{"address":"0x999","title":"Loose terminal","class":"foot","workspace":{"id":1},"grouped":[],"focusHistoryID":0}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" prev

	assert_file_equals "$dispatch_log" $'hl.dsp.focus({ window = "address:0x222" })\nhl.dsp.group.prev({})'
	assert_no_notifications
}

test_next_with_stale_remembered_container_cleans_anchor_and_does_nothing() {
	reset_logs
	write_active '{"address":"0x999","title":"Loose terminal","class":"foot","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0x999","title":"Loose terminal","class":"foot","workspace":{"id":1},"grouped":[]}]\n' >"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	bash "$subject" next

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_no_notifications
}

test_prev_without_remembered_container_does_nothing() {
	reset_logs
	write_active '{"address":"0x999","title":"Loose terminal","class":"foot","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '[{"address":"0x999","title":"Loose terminal","class":"foot","workspace":{"id":1},"grouped":[]}]\n' >"$clients_json"
	: >"$state_file"

	bash "$subject" prev

	assert_file_equals "$dispatch_log" ""
	assert_file_equals "$state_file" ""
	assert_no_notifications
}

test_snapshot_uses_remembered_container_when_focus_is_outside_group() {
	local output

	reset_logs
	write_active '{"address":"0x999","title":"Loose terminal","class":"foot","monitor":1,"workspace":{"id":1},"grouped":[]}'
	printf '%s\n' \
		'[{"address":"0x111","title":"Editor","class":"code","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x222","title":"Tests","class":"foot","workspace":{"id":2},"grouped":["0x111","0x222"]},' \
		'{"address":"0x999","title":"Loose terminal","class":"foot","workspace":{"id":1},"grouped":[]}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	output="$(bash "$subject" snapshot)"

	if [[ "$output" != '{"hasContainer":true,"address":"0x111","title":"Editor","className":"code","grouped":["0x111","0x222"],"windows":[{"address":"0x111","title":"Editor","className":"code"},{"address":"0x222","title":"Tests","className":"foot"}],"source":"remembered"}' ]]; then
		printf 'Unexpected snapshot:\n%s\n' "$output" >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_no_notifications
}

test_snapshot_ignores_unmanaged_active_native_group() {
	local output

	reset_logs
	write_active '{"address":"0xaaa","title":"Manual editor","class":"code","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}'
	printf '[{"address":"0xaaa","title":"Manual editor","class":"code","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]},{"address":"0xbbb","title":"Manual terminal","class":"foot","workspace":{"id":1},"grouped":["0xaaa","0xbbb"]}]\n' >"$clients_json"
	: >"$state_file"

	output="$(bash "$subject" snapshot)"

	if [[ "$output" != '{"hasContainer":false,"address":"","title":"No Active Window","className":"","grouped":[],"windows":[],"source":"none"}' ]]; then
		printf 'Unexpected unmanaged snapshot:\n%s\n' "$output" >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_no_notifications
}

test_snapshot_prefers_remembered_container_over_unmanaged_active_group() {
	local output

	reset_logs
	write_active '{"address":"0x999","title":"Manual editor","class":"code","monitor":1,"workspace":{"id":1},"grouped":["0x999","0x888"]}'
	printf '%s\n' \
		'[{"address":"0x111","title":"Editor","class":"code","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":8},' \
		'{"address":"0x222","title":"Tests","class":"foot","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":2},' \
		'{"address":"0x999","title":"Manual editor","class":"code","workspace":{"id":1},"grouped":["0x999","0x888"],"focusHistoryID":0},' \
		'{"address":"0x888","title":"Manual terminal","class":"foot","workspace":{"id":1},"grouped":["0x999","0x888"],"focusHistoryID":1}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	output="$(bash "$subject" snapshot)"

	if [[ "$output" != '{"hasContainer":true,"address":"0x222","title":"Tests","className":"foot","grouped":["0x111","0x222"],"windows":[{"address":"0x111","title":"Editor","className":"code"},{"address":"0x222","title":"Tests","className":"foot"}],"source":"remembered"}' ]]; then
		printf 'Unexpected remembered snapshot over unmanaged active group:\n%s\n' "$output" >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_no_notifications
}

test_snapshot_uses_recent_remembered_group_member_as_active_window() {
	local output

	reset_logs
	write_active '{"address":"0x999","title":"Loose terminal","class":"foot","monitor":1,"workspace":{"id":1},"grouped":[],"focusHistoryID":0}'
	printf '%s\n' \
		'[{"address":"0x111","title":"Editor","class":"code","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":8},' \
		'{"address":"0x222","title":"Tests","class":"foot","workspace":{"id":2},"grouped":["0x111","0x222"],"focusHistoryID":2},' \
		'{"address":"0x999","title":"Loose terminal","class":"foot","workspace":{"id":1},"grouped":[],"focusHistoryID":0}]' \
		>"$clients_json"
	printf 'anchor\t0x111\n' >"$state_file"

	output="$(bash "$subject" snapshot)"

	if [[ "$output" != '{"hasContainer":true,"address":"0x222","title":"Tests","className":"foot","grouped":["0x111","0x222"],"windows":[{"address":"0x111","title":"Editor","className":"code"},{"address":"0x222","title":"Tests","className":"foot"}],"source":"remembered"}' ]]; then
		printf 'Unexpected snapshot:\n%s\n' "$output" >&2
		return 1
	fi

	assert_file_equals "$dispatch_log" ""
	assert_no_notifications
}

test_remove_nonanchor_window_keeps_existing_anchor() {
	reset_logs
	write_active '{"address":"0xbbb","monitor":1,"workspace":{"id":1},"grouped":["0xbbb","0xccc","0xaaa"]}'
	printf '%s\n' \
		'[{"address":"0xbbb","workspace":{"id":1},"grouped":["0xbbb","0xccc","0xaaa"]},' \
		'{"address":"0xccc","workspace":{"id":1},"grouped":["0xbbb","0xccc","0xaaa"]},' \
		'{"address":"0xaaa","workspace":{"id":1},"grouped":["0xbbb","0xccc","0xaaa"]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	bash "$subject" remove

	assert_file_equals "$dispatch_log" 'hl.dsp.window.move({ out_of_group = true })'
	assert_file_equals "$state_file" $'anchor\t0xaaa'
	assert_no_notifications
}

test_reorder_targets_dragged_window_not_active_window() {
	reset_logs
	write_active '{"address":"0xaaa","monitor":1,"workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]}'
	printf '%s\n' \
		'[{"address":"0xaaa","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]},' \
		'{"address":"0xbbb","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]},' \
		'{"address":"0xccc","workspace":{"id":1},"grouped":["0xaaa","0xbbb","0xccc"]}]' \
		>"$clients_json"
	printf 'anchor\t0xaaa\n' >"$state_file"

	bash "$subject" reorder 0xccc 0

	assert_file_equals "$dispatch_log" $'hl.dsp.group.move_window({ forward = false, window = "address:0xccc" })\nhl.dsp.group.move_window({ forward = false, window = "address:0xccc" })'
	assert_no_notifications
}

test_daemon_writes_runtime_config_with_current_script_path
test_daemon_runtime_config_respects_command_path_override
test_menu_calls_hyprcompanion_ipc_target
test_lua_setup_derives_default_script_from_loaded_path
test_lua_setup_routes_cycle_binds_through_script
test_remove_remembered_one_window_container
test_remove_native_group_remembers_remaining_window
test_remove_outside_container_is_noop
test_remove_unmanaged_native_group_is_noop
test_remove_selected_remembered_anchor_remembers_remaining_window
test_remove_rejects_selected_window_outside_container
test_remove_nonanchor_window_keeps_existing_anchor
test_select_group_window_restores_original_focus_when_focus_is_outside_container
test_select_group_window_keeps_focus_when_active_is_same_container
test_select_rejects_window_outside_container
test_add_remembered_one_window_container_is_noop
test_add_new_container_remembers_global_anchor
test_add_brings_global_container_to_active_workspace
test_add_rejects_unmanaged_native_group
test_move_container_here_moves_remembered_container_to_active_workspace
test_move_container_here_works_without_active_window
test_move_container_here_is_noop_when_container_is_already_here
test_move_container_here_rejects_without_remembered_container
test_move_container_here_cleans_stale_anchor
test_move_container_here_reports_failure_when_member_move_fails
test_move_container_here_reports_failure_when_dispatcher_prints_error
test_reorder_moves_group_window_forward_to_index
test_reorder_moves_group_window_backward_to_index
test_reorder_single_window_container_is_noop
test_reorder_rejects_unmanaged_native_group
test_reorder_targets_dragged_window_not_active_window
test_close_active_grouped_window_keeps_anchor
test_close_remembered_anchor_remembers_remaining_window
test_close_remembered_active_when_focus_is_outside_group
test_close_one_window_container_forgets_anchor
test_close_rejects_window_outside_container
test_jump_rejects_unmanaged_native_group
test_next_focuses_remembered_container_when_focus_is_outside_group
test_prev_focuses_remembered_container_when_focus_is_outside_group
test_next_with_stale_remembered_container_cleans_anchor_and_does_nothing
test_prev_without_remembered_container_does_nothing
test_snapshot_uses_remembered_container_when_focus_is_outside_group
test_snapshot_ignores_unmanaged_active_native_group
test_snapshot_prefers_remembered_container_over_unmanaged_active_group
test_snapshot_uses_recent_remembered_group_member_as_active_window

printf 'hyprcompanion CLI tests passed\n'
