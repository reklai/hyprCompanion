import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "HyprGroupRuntime.js" as HyprGroupRuntime
import "components"

ShellRoot {
	id: root

	property bool menuVisible: false
	property string commandPath: HyprGroupRuntime.commandPath
	property bool pointerKnown: false
	property int pointerX: 0
	property int pointerY: 0
	property string activeHyprlandAddress: ""
	property string snapshotAddress: ""
	property string snapshotClass: ""
	property string snapshotSource: "none"
	property string snapshotTitle: "No Active Window"
	property bool snapshotHasContainer: false
	property var snapshotGrouped: []
	property var snapshotWindowDetails: ({})
	property string selectedAddress: ""
	property bool selectActiveAfterRefresh: false
	property bool tabDragActive: false
	property bool tabPressActive: false
	property string pressedTabAddress: ""
	property string draggedTabAddress: ""
	property int draggedTabStartIndex: -1
	property int tabDropIndex: -1
	property real draggedTabOffsetY: 0
	readonly property int tabHeight: 38
	readonly property int tabGap: 2
	readonly property int tabDragThreshold: 8

	function clamp(value, minValue, maxValue) {
		return Math.max(minValue, Math.min(maxValue, value));
	}

	function focusedScreen() {
		const monitor = Hyprland.focusedMonitor;

		if (monitor) {
			for (let i = 0; i < Quickshell.screens.length; i++) {
				const screen = Quickshell.screens[i];

				if (screen.name === monitor.name) {
					return screen;
				}
			}
		}

		return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
	}

	function openMenu() {
		captureActiveWindow();
		menuVisible = true;
		Qt.callLater(() => focusTrap.forceActiveFocus());
	}

	function openMenuAt(x, y) {
		setPointer(x, y);
		openMenu();
	}

	function closeMenu() {
		menuVisible = false;
	}

	function toggleMenu() {
		if (menuVisible) {
			closeMenu();
		} else {
			openMenu();
		}
	}

	function toggleMenuAt(x, y) {
		if (menuVisible) {
			closeMenu();
		} else {
			openMenuAt(x, y);
		}
	}

	function run(action, argument, keepOpen) {
		const command = [commandPath, action];

		if (argument) {
			command.push(argument);
		}

		if (!keepOpen) {
			closeMenu();
		}

		Quickshell.execDetached(command);

		if (keepOpen) {
			refreshSnapshotTimer.restart();

			if (action === "close") {
				closeRefreshSnapshotTimer.restart();
			}
		}
	}

	function runReorder(address, targetIndex) {
		Quickshell.execDetached([commandPath, "reorder", address, String(targetIndex)]);
		refreshSnapshotTimer.restart();
	}

	function runCycle(action) {
		selectActiveAfterRefresh = true;
		run(action, "", true);
	}

	function activeWindowInShownContainer() {
		return snapshotHasContainer && activeHyprlandAddress.length > 0 && hasAddress(snapshotGrouped, activeHyprlandAddress);
	}

	function canAddToContainer() {
		return activeHyprlandAddress.length > 0 && !activeWindowInShownContainer();
	}

	function canMoveContainerHere() {
		return snapshotHasContainer && !activeWindowInShownContainer();
	}

	function canCycleContainer() {
		return snapshotHasContainer && snapshotGrouped.length > 1;
	}

	function setPointer(x, y) {
		const parsedX = Number(x);
		const parsedY = Number(y);

		if (Number.isFinite(parsedX) && Number.isFinite(parsedY)) {
			pointerX = parsedX;
			pointerY = parsedY;
			pointerKnown = true;
		} else {
			pointerKnown = false;
		}
	}

	function copyGroupedAddresses(grouped) {
		const addresses = [];

		if (!grouped) {
			return addresses;
		}

		for (let i = 0; i < grouped.length; i++) {
			addresses.push(String(grouped[i]));
		}

		return addresses;
	}

	function actualGroupedAddresses(grouped, activeAddress) {
		const addresses = [];
		const source = copyGroupedAddresses(grouped);

		if (activeAddress && source.length > 0 && !hasAddress(source, activeAddress)) {
			source.unshift(activeAddress);
		}

		for (let i = 0; i < source.length; i++) {
			const address = source[i];

			if (hasAddress(addresses, address)) {
				continue;
			}

			if (address === activeAddress || clientForAddress(address)) {
				addresses.push(address);
			}
		}

		return addresses;
	}

	function stableGroupedAddresses(nextAddresses) {
		const stable = [];

		for (let i = 0; i < snapshotGrouped.length; i++) {
			const address = snapshotGrouped[i];

			if (hasAddress(nextAddresses, address) && !hasAddress(stable, address)) {
				stable.push(address);
			}
		}

		for (let i = 0; i < nextAddresses.length; i++) {
			const address = nextAddresses[i];

			if (!hasAddress(stable, address)) {
				stable.push(address);
			}
		}

		return stable;
	}

	function hasAddress(addresses, address) {
		for (let i = 0; i < addresses.length; i++) {
			if (addresses[i] === address) {
				return true;
			}
		}

		return false;
	}

	function clearSnapshot() {
		snapshotAddress = "";
		snapshotTitle = "No Active Window";
		snapshotClass = "";
		snapshotSource = "none";
		snapshotHasContainer = false;
		snapshotGrouped = [];
		snapshotWindowDetails = {};
		selectedAddress = "";
		selectActiveAfterRefresh = false;
	}

	function captureActiveWindowFromHyprland() {
		const active = Hyprland.activeToplevel;
		const ipc = active && active.lastIpcObject ? active.lastIpcObject : null;
		const grouped = actualGroupedAddresses(ipc && ipc.grouped ? ipc.grouped : [], active ? active.address : "");

		activeHyprlandAddress = active ? active.address : "";

		if (!active || grouped.length === 0) {
			clearSnapshot();
			return;
		}

		snapshotAddress = active.address;
		snapshotTitle = active.title || "Untitled window";
		snapshotClass = ipc && ipc.class ? ipc.class : "";
		snapshotSource = "active";
		snapshotHasContainer = true;
		snapshotGrouped = stableGroupedAddresses(grouped);
		snapshotWindowDetails = {};
		ensureSelectedWindow();
	}

	function applyContainerSnapshot(snapshot) {
		if (!snapshot || !snapshot.hasContainer || !snapshot.grouped || snapshot.grouped.length === 0) {
			clearSnapshot();
			return;
		}

		snapshotAddress = String(snapshot.address || "");
		snapshotTitle = snapshot.title || "Untitled window";
		snapshotClass = snapshot.className || "";
		snapshotSource = String(snapshot.source || "none");
		snapshotHasContainer = true;
		snapshotGrouped = stableGroupedAddresses(copyGroupedAddresses(snapshot.grouped));
		snapshotWindowDetails = snapshotWindowDetailsByAddress(snapshot.windows || []);
		ensureSelectedWindow();
	}

	function snapshotWindowDetailsByAddress(windows) {
		const details = {};

		for (let i = 0; i < windows.length; i++) {
			const entry = windows[i];

			if (!entry || !entry.address) {
				continue;
			}

			details[String(entry.address)] = {
				className: entry.className || "",
				title: entry.title || ""
			};
		}

		return details;
	}

	function snapshotWindowDetailsForAddress(address) {
		return snapshotWindowDetails && snapshotWindowDetails[address] ? snapshotWindowDetails[address] : null;
	}

	function meaningfulTabLabel(value) {
		const label = String(value || "").trim();

		if (label.length === 0 || label === "Untitled window" || /^0x[0-9a-fA-F]+$/.test(label)) {
			return "";
		}

		return label;
	}

	function tabTitle(client, details, index) {
		const clientIpc = client && client.lastIpcObject ? client.lastIpcObject : null;
		const clientClass = clientIpc && clientIpc.class ? clientIpc.class : "";
		const title = meaningfulTabLabel(client && client.title ? client.title : details ? details.title : "");
		const className = meaningfulTabLabel(clientClass || (details ? details.className : ""));

		if (title) {
			return title;
		}

		if (className) {
			return className;
		}

		return "Window " + String(index + 1);
	}

	function applySnapshotText(text) {
		const trimmed = String(text || "").trim();

		if (trimmed.length === 0) {
			return;
		}

		try {
			applyContainerSnapshot(JSON.parse(trimmed));
		} catch (error) {
			captureActiveWindowFromHyprland();
		}
	}

	function captureActiveWindow() {
		captureActiveWindowFromHyprland();

		if (!snapshotProcess.running) {
			snapshotProcess.exec([commandPath, "snapshot"]);
		}
	}

	function clientForAddress(address) {
		const clients = Hyprland.toplevels ? Hyprland.toplevels.values : [];

		for (let i = 0; i < clients.length; i++) {
			const client = clients[i];

			if (client && client.address === address) {
				return client;
			}
		}

		return null;
	}

	function groupWindowEntries() {
		const entries = [];

		for (let i = 0; i < snapshotGrouped.length; i++) {
			const address = snapshotGrouped[i];
			const client = clientForAddress(address);
			const ipc = client && client.lastIpcObject ? client.lastIpcObject : null;
			const details = snapshotWindowDetailsForAddress(address);

			entries.push({
				address: address,
				active: address === snapshotAddress,
				selected: address === selectedAddress,
				className: ipc && ipc.class ? ipc.class : details ? details.className : "",
				title: tabTitle(client, details, i)
			});
		}

		return entries;
	}

	function indexForAddress(address) {
		for (let i = 0; i < snapshotGrouped.length; i++) {
			if (snapshotGrouped[i] === address) {
				return i;
			}
		}

		return -1;
	}

	function ensureSelectedWindow() {
		if (!snapshotHasContainer || snapshotGrouped.length === 0) {
			selectedAddress = "";
			selectActiveAfterRefresh = false;
			return;
		}

		if (selectActiveAfterRefresh && hasAddress(snapshotGrouped, snapshotAddress)) {
			selectedAddress = snapshotAddress;
			selectActiveAfterRefresh = false;
			return;
		}

		if (selectedAddress && hasAddress(snapshotGrouped, selectedAddress)) {
			return;
		}

		selectActiveAfterRefresh = false;
		selectedAddress = hasAddress(snapshotGrouped, snapshotAddress) ? snapshotAddress : snapshotGrouped[0];
	}

	function selectWindow(address) {
		if (hasAddress(snapshotGrouped, address)) {
			selectedAddress = address;
		}
	}

	function hasSelectedWindow() {
		return snapshotHasContainer && selectedAddress.length > 0 && hasAddress(snapshotGrouped, selectedAddress);
	}

	function windowTitleForAddress(address) {
		const index = indexForAddress(address);

		if (index < 0) {
			return "No Active Window";
		}

		const client = clientForAddress(address);
		const details = snapshotWindowDetailsForAddress(address);

		return tabTitle(client, details, index);
	}

	function windowClassForAddress(address) {
		const client = clientForAddress(address);
		const ipc = client && client.lastIpcObject ? client.lastIpcObject : null;
		const details = snapshotWindowDetailsForAddress(address);

		return ipc && ipc.class ? ipc.class : details ? details.className : "";
	}

	function selectedWindowTitle() {
		return hasSelectedWindow() ? windowTitleForAddress(selectedAddress) : "No Active Window";
	}

	function selectedWindowClassLabel() {
		if (!hasSelectedWindow()) {
			return "";
		}

		return windowClassForAddress(selectedAddress) || selectedAddress;
	}

	function selectedWindowPositionLabel() {
		if (!hasSelectedWindow()) {
			return "";
		}

		const index = indexForAddress(selectedAddress);

		if (index >= 0) {
			return String(index + 1) + " / " + String(snapshotGrouped.length);
		}

		return "1 / " + String(snapshotGrouped.length);
	}

	function containerStateLabel() {
		if (snapshotSource === "active") {
			return "Active Container";
		}

		return "No Active Container";
	}

	function clampedTabIndex(index) {
		if (snapshotGrouped.length === 0) {
			return -1;
		}

		return root.clamp(index, 0, snapshotGrouped.length - 1);
	}

	function tabIndexForLocalY(localY) {
		const slotHeight = tabHeight + tabGap;
		const centeredIndex = Math.floor((localY + (tabHeight / 2)) / slotHeight);

		return clampedTabIndex(centeredIndex);
	}

	function beginTabDrag(address, startIndex) {
		if (snapshotGrouped.length < 2) {
			return;
		}

		tabDragActive = true;
		draggedTabAddress = address;
		draggedTabStartIndex = startIndex;
		tabDropIndex = startIndex;
	}

	function beginTabPress(address) {
		if (snapshotGrouped.length < 2) {
			return;
		}

		tabPressActive = true;
		pressedTabAddress = address;
	}

	function updateTabDropIndex(localY) {
		if (!tabDragActive) {
			return;
		}

		tabDropIndex = tabIndexForLocalY(localY);
	}

	function updateTabDragPosition(localY) {
		if (!tabDragActive || draggedTabStartIndex < 0) {
			return;
		}

		const slotHeight = tabHeight + tabGap;
		const maxTop = Math.max(0, (snapshotGrouped.length - 1) * slotHeight);
		const clampedTop = root.clamp(localY, 0, maxTop);

		draggedTabOffsetY = clampedTop - (draggedTabStartIndex * slotHeight);
		updateTabDropIndex(clampedTop);
	}

	function tabDropMarkerY() {
		if (!tabDragActive || tabDropIndex < 0) {
			return -100;
		}

		const slotHeight = tabHeight + tabGap;
		const targetY = tabDropIndex * slotHeight;

		if (tabDropIndex > draggedTabStartIndex) {
			return targetY + tabHeight + Math.round(tabGap / 2);
		}

		return Math.max(0, targetY - Math.round(tabGap / 2));
	}

	function cancelTabDrag() {
		tabDragActive = false;
		tabPressActive = false;
		pressedTabAddress = "";
		draggedTabAddress = "";
		draggedTabStartIndex = -1;
		tabDropIndex = -1;
		draggedTabOffsetY = 0;
	}

	function moveAddressInSnapshot(address, targetIndex) {
		const addresses = copyGroupedAddresses(snapshotGrouped);
		const sourceIndex = addresses.indexOf(address);
		const clampedIndex = clampedTabIndex(targetIndex);

		if (sourceIndex < 0 || clampedIndex < 0 || sourceIndex === clampedIndex) {
			return false;
		}

		addresses.splice(sourceIndex, 1);
		addresses.splice(clampedIndex, 0, address);
		snapshotGrouped = addresses;

		return true;
	}

	function finishTabDrag(address) {
		const targetIndex = tabDropIndex;
		const startIndex = draggedTabStartIndex;

		cancelTabDrag();

		if (targetIndex < 0 || targetIndex === startIndex) {
			return;
		}

		moveAddressInSnapshot(address, targetIndex);
		runReorder(address, targetIndex);
	}

	Timer {
		id: refreshSnapshotTimer
		interval: 80
		repeat: false
		onTriggered: root.captureActiveWindow()
	}

	Timer {
		id: closeRefreshSnapshotTimer
		interval: 320
		repeat: false
		onTriggered: root.captureActiveWindow()
	}

	Process {
		id: snapshotProcess
		stdout: SplitParser {
			splitMarker: "\n"
			onRead: data => root.applySnapshotText(data)
		}
		onExited: (exitCode, exitStatus) => {
			if (exitCode !== 0) {
				root.captureActiveWindowFromHyprland();
			}
		}
	}

	IpcHandler {
		target: "hyprgroup"

		function open() {
			root.openMenu();
		}

		function openAt(x: string, y: string) {
			root.openMenuAt(x, y);
		}

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
		id: menuWindow

		visible: true
		screen: root.focusedScreen()
		color: "#00000000"
		aboveWindows: true
		exclusiveZone: 0
		exclusionMode: ExclusionMode.Ignore
		focusable: root.menuVisible
		mask: Region { item: root.menuVisible ? surface : emptyInputRegion }
		WlrLayershell.layer: WlrLayer.Overlay
		WlrLayershell.keyboardFocus: root.menuVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
		WlrLayershell.namespace: "hyprgroup-menu"

		anchors {
			top: true
			right: true
			bottom: true
			left: true
		}

		Item {
			id: emptyInputRegion
			width: 0
			height: 0
		}

		Item {
			id: surface
			anchors.fill: parent
			enabled: root.menuVisible
			visible: root.menuVisible

			MouseArea {
				anchors.fill: parent
				onClicked: root.closeMenu()
			}

			Rectangle {
				id: card
				readonly property int edgeMargin: 18
				readonly property int monitorWidth: menuWindow.screen ? menuWindow.screen.width : surface.width
				readonly property int monitorHeight: menuWindow.screen ? menuWindow.screen.height : surface.height
				readonly property int pointerGap: 8
				readonly property int screenX: menuWindow.screen ? menuWindow.screen.x : 0
				readonly property int screenY: menuWindow.screen ? menuWindow.screen.y : 0
				readonly property int surfaceOriginX: Math.max(0, Math.round((monitorWidth - surface.width) / 2))
				readonly property int surfaceOriginY: Math.max(0, Math.round(monitorHeight - surface.height))

				function targetX() {
					if (!root.pointerKnown) {
						return Math.round((surface.width - width) / 2);
					}

					const localPointerX = root.pointerX - screenX - surfaceOriginX;
					const target = localPointerX - Math.round(width / 2);

					return root.clamp(Math.round(target), edgeMargin, Math.max(edgeMargin, surface.width - width - edgeMargin));
				}

				function targetY() {
					if (!root.pointerKnown) {
						return Math.round((surface.height - height) / 2);
					}

					const localPointerY = root.pointerY - screenY - surfaceOriginY;
					let target = localPointerY + pointerGap;

					if (target + height + edgeMargin > surface.height) {
						target = localPointerY - height - pointerGap;
					}

					return root.clamp(Math.round(target), edgeMargin, Math.max(edgeMargin, surface.height - height - edgeMargin));
				}

				width: Math.max(420, Math.min(640, monitorWidth - 36))
				height: Math.max(280, Math.min(330, monitorHeight - 74))
				x: targetX()
				y: targetY()
				color: "#0b0f14"
				border.color: "#30363d"
				border.width: 1
				radius: 8

				MouseArea {
					anchors.fill: parent
					acceptedButtons: Qt.AllButtons
					onClicked: mouse => mouse.accepted = true
				}

				Item {
					id: focusTrap
					anchors.fill: parent
					focus: true

					Keys.onPressed: event => {
						if (event.key === Qt.Key_Escape) {
							root.closeMenu();
							event.accepted = true;
						}
					}
				}

				Column {
					anchors.fill: parent
					anchors.margins: 16
					spacing: 12

					Item {
						width: parent.width
						height: 34

						Row {
							id: headerControls
							anchors.right: parent.right
							anchors.verticalCenter: parent.verticalCenter
							spacing: 6

							Rectangle {
								id: prevButton
								width: 30
								height: 30
								opacity: root.canCycleContainer() ? 1 : 0.48
								color: root.canCycleContainer() && prevMouse.containsMouse ? "#242b35" : "#141922"
								border.color: "#3a414b"
								border.width: 1
								radius: 6

								Text {
									anchors.centerIn: parent
									text: "<"
									color: "#f8fafc"
									font.pixelSize: 16
									font.weight: Font.DemiBold
								}

								MouseArea {
									id: prevMouse
									anchors.fill: parent
									enabled: root.canCycleContainer()
									hoverEnabled: root.canCycleContainer()
									cursorShape: root.canCycleContainer() ? Qt.PointingHandCursor : Qt.ArrowCursor
									onClicked: root.runCycle("prev")
								}
							}

							Rectangle {
								id: nextButton
								width: 30
								height: 30
								opacity: root.canCycleContainer() ? 1 : 0.48
								color: root.canCycleContainer() && nextMouse.containsMouse ? "#242b35" : "#141922"
								border.color: "#3a414b"
								border.width: 1
								radius: 6

								Text {
									anchors.centerIn: parent
									text: ">"
									color: "#f8fafc"
									font.pixelSize: 16
									font.weight: Font.DemiBold
								}

								MouseArea {
									id: nextMouse
									anchors.fill: parent
									enabled: root.canCycleContainer()
									hoverEnabled: root.canCycleContainer()
									cursorShape: root.canCycleContainer() ? Qt.PointingHandCursor : Qt.ArrowCursor
									onClicked: root.runCycle("next")
								}
							}

							Rectangle {
								id: closeButton
								width: 30
								height: 30
								color: closeMouse.containsMouse ? "#242b35" : "#141922"
								border.color: "#3a414b"
								border.width: 1
								radius: 6

								Text {
									anchors.centerIn: parent
									text: "X"
									color: "#f8fafc"
									font.pixelSize: 13
									font.weight: Font.DemiBold
								}

								MouseArea {
									id: closeMouse
									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: root.closeMenu()
								}
							}
						}

						Text {
							anchors.left: parent.left
							anchors.right: headerControls.left
							anchors.rightMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							text: "HyprGroup"
							color: "#f8fafc"
							elide: Text.ElideRight
							font.pixelSize: 18
							font.weight: Font.DemiBold
						}
					}

					Row {
						width: parent.width
						height: parent.height - 34 - parent.spacing
						spacing: 12

						Column {
							id: actionPane
							width: 244
							height: parent.height
							spacing: 8

							ActionButton {
								width: parent.width
								label: "Add to Container"
								actionEnabled: root.canAddToContainer()
								onTriggered: root.run("add")
							}

							ActionButton {
								width: parent.width
								label: "Move Container Here"
								actionEnabled: root.canMoveContainerHere()
								onTriggered: root.run("move-here")
							}

							ActionButton {
								width: parent.width
								label: "Remove from Container"
								danger: true
								actionEnabled: root.hasSelectedWindow()
								onTriggered: root.run("remove", root.selectedAddress)
							}

							ActionButton {
								width: parent.width
								label: "Close Window Inside Container"
								danger: true
								actionEnabled: root.hasSelectedWindow()
								onTriggered: root.run("close", root.selectedAddress)
							}
						}

						Rectangle {
							width: 1
							height: parent.height
							color: "#30363d"
						}

						Column {
							id: detailPane
							width: parent.width - actionPane.width - 1 - (parent.spacing * 2)
							height: parent.height
							spacing: 0

							Rectangle {
								id: containerPanel
								width: parent.width
								height: parent.height
								color: "#08090c"
								border.color: "#383a40"
								border.width: 1
								radius: 8
								clip: true

								Item {
									anchors.fill: parent

									Rectangle {
										id: windowTabsPanel
										anchors.left: parent.left
										anchors.right: parent.right
										anchors.top: tabsDivider.bottom
										anchors.bottom: parent.bottom
										color: "#11141a"

										Text {
											anchors.centerIn: parent
											visible: root.groupWindowEntries().length === 0
											text: "No Active Window"
											color: "#8f949e"
											elide: Text.ElideRight
											font.pixelSize: 12
											maximumLineCount: 1
										}

										Flickable {
											id: tabFlickable
											anchors.fill: parent
											anchors.margins: 6
											visible: root.groupWindowEntries().length > 0
											clip: true
											boundsBehavior: Flickable.StopAtBounds
											contentWidth: width
											contentHeight: tabColumn.height
											interactive: contentHeight > height && !root.tabDragActive

											Column {
												id: tabColumn
												width: tabFlickable.width
												spacing: root.tabGap

												Repeater {
													model: root.groupWindowEntries()

													delegate: Item {
														id: groupTab
														readonly property bool dragged: root.tabDragActive && root.draggedTabAddress === modelData.address
														readonly property bool pressed: root.tabPressActive && root.pressedTabAddress === modelData.address

														width: tabColumn.width
														height: root.tabHeight
														opacity: dragged ? 0.95 : 1
														scale: dragged ? 1.04 : pressed ? 1.02 : 1
														x: dragged ? 2 : pressed ? 1 : 0
														z: dragged || pressed ? 2 : 0
														transform: Translate {
															y: groupTab.dragged ? root.draggedTabOffsetY : 0
														}

														Rectangle {
															anchors.fill: parent
															anchors.topMargin: 1
															anchors.leftMargin: 1
															anchors.rightMargin: 1
															anchors.bottomMargin: 1
															color: groupTab.dragged ? "#4a4234" : groupTab.pressed ? "#3d372d" : modelData.selected ? "#3d3e44" : modelData.active ? "#303238" : "#26272d"
															border.color: groupTab.dragged ? "#d8b46a" : groupTab.pressed ? "#c59f5a" : modelData.selected ? "#5a5c64" : "#3d3f47"
															border.width: groupTab.dragged || groupTab.pressed ? 2 : 1
															radius: 5
														}

														Item {
															id: tabGrip
															width: 12
															height: 18
															anchors.left: parent.left
															anchors.leftMargin: 10
															anchors.verticalCenter: parent.verticalCenter
															visible: root.snapshotGrouped.length > 1
															opacity: groupTab.dragged || groupTab.pressed ? 1 : 0.42

															Repeater {
																model: 6

																Rectangle {
																	width: 2
																	height: 2
																	x: (index % 2) * 6
																	y: Math.floor(index / 2) * 6
																	radius: 1
																	color: groupTab.dragged || groupTab.pressed ? "#f3d28b" : "#a1a1aa"
																}
															}
														}

														Rectangle {
															width: 3
															height: parent.height - 12
															anchors.left: parent.left
															anchors.leftMargin: 2
															anchors.verticalCenter: parent.verticalCenter
															visible: modelData.selected
															color: "#d4d4d8"
															radius: 1
														}

														Text {
															anchors.left: parent.left
															anchors.right: parent.right
															anchors.leftMargin: root.snapshotGrouped.length > 1 ? 30 : 14
															anchors.rightMargin: 14
															anchors.verticalCenter: parent.verticalCenter
															text: modelData.title
															color: modelData.selected ? "#f4f4f5" : "#c5c8cf"
															elide: Text.ElideRight
															horizontalAlignment: Text.AlignLeft
															font.pixelSize: 12
															font.weight: modelData.selected ? Font.DemiBold : Font.Normal
															maximumLineCount: 1
														}

														MouseArea {
															id: tabMouse
															property real pressX: 0
															property real pressY: 0
															property bool dragStarted: false
															property bool pointerDown: false

															anchors.fill: parent
															hoverEnabled: false
															preventStealing: true
															cursorShape: groupTab.dragged || groupTab.pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor

															onPressed: mouse => {
																if (mouse.button !== Qt.LeftButton) {
																	return;
																}

																pressX = mouse.x;
																pressY = mouse.y;
																pointerDown = true;
																dragStarted = false;
																root.selectWindow(modelData.address);
																root.beginTabPress(modelData.address);
															}

															onPositionChanged: mouse => {
																if (!pointerDown || (mouse.buttons & Qt.LeftButton) === 0) {
																	return;
																}

																const dx = Math.abs(mouse.x - pressX);
																const dy = Math.abs(mouse.y - pressY);
																const point = tabMouse.mapToItem(tabColumn, mouse.x, mouse.y);

																if (!dragStarted && (dx > root.tabDragThreshold || dy > root.tabDragThreshold)) {
																	dragStarted = true;
																	root.beginTabDrag(modelData.address, index);
																}

																if (root.tabDragActive && root.draggedTabAddress === modelData.address) {
																	root.updateTabDragPosition(point.y - pressY);
																}
															}

															onReleased: mouse => {
																if (mouse.button !== Qt.LeftButton || !pointerDown) {
																	return;
																}

																pointerDown = false;

																if (root.tabDragActive && root.draggedTabAddress === modelData.address) {
																	root.finishTabDrag(modelData.address);
																} else {
																	root.cancelTabDrag();
																	root.selectWindow(modelData.address);
																	root.run("select", modelData.address, true);
																}
															}

															onDoubleClicked: mouse => {
																if (mouse.button !== Qt.LeftButton) {
																	return;
																}

																root.selectWindow(modelData.address);
																root.cancelTabDrag();
																root.run("jump", modelData.address, true);
															}

															onCanceled: {
																pointerDown = false;

																if (root.draggedTabAddress === modelData.address || root.pressedTabAddress === modelData.address) {
																	root.cancelTabDrag();
																}
															}
														}
													}
												}
											}

											Rectangle {
												id: tabDropMarker
												visible: root.tabDragActive && root.tabDropIndex >= 0
												x: 6
												y: root.tabDropMarkerY()
												width: tabFlickable.width - 12
												height: 3
												color: "#d8b46a"
												radius: 1
												z: 3
											}
										}
									}

									Rectangle {
										id: tabsDivider
										anchors.left: parent.left
										anchors.right: parent.right
										anchors.top: activeWindowPanel.bottom
										height: 1
										color: "#383a40"
									}

									Item {
										id: activeWindowPanel
										anchors.left: parent.left
										anchors.right: parent.right
										anchors.top: parent.top
										height: Math.min(112, Math.max(86, parent.height - 118))

										Column {
											anchors.fill: parent
											anchors.margins: 14
											spacing: 8

											Row {
												width: parent.width
												height: 18

													Text {
														width: parent.width - positionText.width - 10
														anchors.verticalCenter: parent.verticalCenter
														text: root.containerStateLabel()
													color: "#9ca3af"
													elide: Text.ElideRight
													font.pixelSize: 12
													font.weight: Font.DemiBold
													maximumLineCount: 1
												}

												Text {
														id: positionText
														anchors.verticalCenter: parent.verticalCenter
														text: root.selectedWindowPositionLabel()
													color: "#d4d4d8"
													font.pixelSize: 12
													font.weight: Font.DemiBold
												}
											}

												Text {
													width: parent.width
													text: root.selectedWindowTitle()
												color: "#f8fafc"
												elide: Text.ElideRight
												font.pixelSize: 16
												font.weight: Font.DemiBold
												maximumLineCount: 1
											}

											Text {
													width: parent.width
													visible: root.hasSelectedWindow()
													text: root.selectedWindowClassLabel()
												color: "#9ca3af"
												elide: Text.ElideMiddle
												font.pixelSize: 12
												maximumLineCount: 1
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
