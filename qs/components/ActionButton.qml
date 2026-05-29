import QtQuick

Rectangle {
	id: root

	property string label
	property bool danger: false
	property bool actionEnabled: true
	signal triggered()

	height: 44
	opacity: actionEnabled ? 1 : 0.48
	color: actionEnabled && mouse.containsMouse ? "#242b35" : "#151a22"
	border.color: danger ? "#6b7280" : "#3a414b"
	border.width: 1
	radius: 6

	Text {
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.verticalCenter: parent.verticalCenter
		anchors.leftMargin: 14
		anchors.rightMargin: 14
		text: root.label
		color: root.actionEnabled ? "#f8fafc" : "#8f949e"
		elide: Text.ElideRight
		font.pixelSize: root.label.length > 24 ? 12 : root.label.length > 20 ? 13 : 14
	}

	MouseArea {
		id: mouse
		anchors.fill: parent
		enabled: root.actionEnabled
		hoverEnabled: root.actionEnabled
		onClicked: root.triggered()
	}
}
