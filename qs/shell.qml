import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "HyprGroupRuntime.js" as HyprGroupRuntime

ShellRoot {
	id: root

	property bool menuVisible: false
	property string commandPath: HyprGroupRuntime.commandPath

	function closeMenu() {
		menuVisible = false;
	}

	function toggleMenu() {
		menuVisible = !menuVisible;
	}

	function toggleMenuAt(x: string, y: string) {
		toggleMenu();
	}

	IpcHandler {
		target: "hyprgroup"

		function close() {
			root.closeMenu();
		}

		function toggle() {
			root.toggleMenu();
		}

		function toggleAt(x: string, y: string) {
			root.toggleMenuAt(x, y);
		}
	}

	PanelWindow {
		visible: root.menuVisible
		color: "#00000000"
		aboveWindows: true
		exclusiveZone: 0
		exclusionMode: ExclusionMode.Ignore
		focusable: root.menuVisible
		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.keyboardFocus: root.menuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

		anchors {
			top: true
			right: true
			bottom: true
			left: true
		}

		Rectangle {
			width: 360
			height: 220
			anchors.centerIn: parent
			color: "#0b0f14"
			border.color: "#30363d"
			border.width: 1
			radius: 8

			Text {
				anchors.centerIn: parent
				text: "HyprGroup"
				color: "#f8fafc"
				font.pixelSize: 18
				font.weight: Font.DemiBold
			}

			MouseArea {
				anchors.fill: parent
				onClicked: root.closeMenu()
			}
		}
	}
}
