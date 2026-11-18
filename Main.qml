import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtLocation
import QtPositioning

ApplicationWindow {
    id: win
    width: 1320
    height: 820
    minimumWidth: 1100
    minimumHeight: 700
    visible: true
    title: "ROV Ground Station"
    color: "#0b1220"
    onActiveChanged: if (!active) keys.releaseAll()

    readonly property color card: "#131c2e"
    readonly property color line: "#1f2b45"
    readonly property color text: "#e6edf7"
    readonly property color dim: "#8a99b5"
    readonly property color accent: "#22d3ee"
    readonly property color ok: "#22c55e"
    readonly property color bad: "#ef4444"
    readonly property color warn: "#f59e0b"

    component Card: Rectangle {
        color: win.card
        radius: 10
        border.color: win.line
        border.width: 1
    }

    component Tile: Rectangle {
        property string label
        property string value
        property color valueColor: win.text
        color: "#0f1829"
        radius: 8
        implicitHeight: 62
        Layout.fillWidth: true
        Column {
            anchors.centerIn: parent
            spacing: 2
            Text { text: label; color: win.dim; font.pixelSize: 11; font.letterSpacing: 1.2; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: value; color: valueColor; font.pixelSize: 22; font.bold: true; font.family: "monospace"; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }

    component ThrustBar: RowLayout {
        property string label
        property real value: 0
        Layout.fillWidth: true
        Text { text: label; color: win.dim; font.pixelSize: 11; Layout.preferredWidth: 44 }
        Rectangle {
            Layout.fillWidth: true; height: 10; radius: 5; color: "#0f1829"
            Rectangle { x: parent.width / 2 - 1; width: 2; height: parent.height; color: win.line }
            Rectangle {
                height: parent.height; radius: 5
                color: value >= 0 ? win.accent : win.warn
                width: Math.abs(value) * parent.width / 2
                x: value >= 0 ? parent.width / 2 : parent.width / 2 - width
            }
        }
    }

    component Spin: SpinBox {
        id: sb
        signal applied()
        editable: true
        implicitHeight: 38
        contentItem: TextInput {
            text: sb.displayText
            color: win.text
            font.pixelSize: 14; font.family: "monospace"
            horizontalAlignment: Qt.AlignHCenter; verticalAlignment: Qt.AlignVCenter
            selectByMouse: true
            selectionColor: win.accent
            onAccepted: { sb.value = sb.valueFromText(text, sb.locale); sb.applied() }
        }
        background: Rectangle { color: "#0f1829"; radius: 6; border.color: sb.activeFocus ? win.accent : win.line }
        up.indicator: Rectangle {
            x: parent.width - width; width: 34; height: parent.height; radius: 6
            color: sb.up.pressed ? "#26365a" : "#1a2540"
            Text { anchors.centerIn: parent; text: "+"; color: win.text; font.pixelSize: 18 }
        }
        down.indicator: Rectangle {
            x: 0; width: 34; height: parent.height; radius: 6
            color: sb.down.pressed ? "#26365a" : "#1a2540"
            Text { anchors.centerIn: parent; text: "–"; color: win.text; font.pixelSize: 18 }
        }
    }

    component Btn: Button {
        id: b
        property color tint: win.accent
        property bool active: false
        focusPolicy: Qt.NoFocus          // keep keyboard focus on the drive surface
        implicitHeight: 38
        contentItem: Text {
            text: b.text; color: b.enabled ? (b.active ? "#04121a" : win.text) : win.dim
            font.pixelSize: 13; font.bold: true
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 7
            color: !b.enabled ? "#101828" : b.active ? b.tint : b.down ? Qt.darker(b.tint, 3) : "#1a2540"
            border.color: b.enabled ? b.tint : win.line
            border.width: 1
        }
    }

    // ================================================================== instruments
    // Self-contained, read-only widgets: plain Items/Rectangles, no Canvas, no Python involved.
    // Delete any one of them (and its use site below) and the rest still works.

    // Artificial horizon. Sky/ground rotate against the aircraft by -roll and slide by pitch.
    // Nose up (pitch > 0) -> horizon moves DOWN the screen; roll right -> horizon tilts anticlockwise.
    component Horizon: Item {
        id: hz
        property real roll: 0              // degrees
        property real pitch: 0             // degrees
        readonly property real ppd: 4      // pixels per degree of pitch
        clip: true

        Item {                             // 1) roll about the screen centre
            width: hz.width * 3; height: hz.height * 3
            anchors.centerIn: parent
            rotation: -hz.roll
            Item {                         // 2) pitch shift, applied in the rolled frame
                id: pitcher
                width: parent.width; height: parent.height
                y: hz.pitch * hz.ppd
                Rectangle { width: parent.width; height: parent.height / 2; color: "#2b6cb0" }
                Rectangle { y: parent.height / 2; width: parent.width; height: parent.height / 2; color: "#7b5a36" }
                Rectangle { y: parent.height / 2 - 1; width: parent.width; height: 2; color: "white" }
                Repeater {                 // pitch ladder
                    model: [-20, -10, 10, 20]
                    delegate: Rectangle {
                        required property int modelData
                        width: Math.abs(modelData) % 20 === 0 ? 80 : 44
                        height: 2
                        color: "#ccffffff"
                        x: pitcher.width / 2 - width / 2
                        y: pitcher.height / 2 - modelData * hz.ppd - 1
                        Text { x: parent.width + 6; y: -height / 2 + 1; text: Math.abs(modelData); color: "#ccffffff"; font.pixelSize: 10 }
                    }
                }
            }
        }

        // fixed aircraft symbol
        Rectangle { x: hz.width / 2 - 52; y: hz.height / 2 - 2; width: 36; height: 4; color: win.warn }
        Rectangle { x: hz.width / 2 - 52; y: hz.height / 2 - 2; width: 4; height: 12; color: win.warn }
        Rectangle { x: hz.width / 2 + 16; y: hz.height / 2 - 2; width: 36; height: 4; color: win.warn }
        Rectangle { x: hz.width / 2 + 48; y: hz.height / 2 - 2; width: 4; height: 12; color: win.warn }
        Rectangle { x: hz.width / 2 - 4; y: hz.height / 2 - 4; width: 8; height: 8; radius: 4; color: win.warn }
    }

    // Scrolling heading tape (+/- 60 deg), centre = current heading, amber diamond = Heading Hold target.
    component CompassTape: Item {
        id: ct
        property real heading: 0
        property real target: 0
        property bool showTarget: false
        readonly property real span: 120
        readonly property real ppd: width / span
        clip: true

        function wrap180(a) { return ((a % 360) + 540) % 360 - 180 }
        function label(d) {
            if (d === 0) return "N"
            if (d === 90) return "E"
            if (d === 180) return "S"
            if (d === 270) return "W"
            return d
        }

        Repeater {
            model: 25
            delegate: Item {
                required property int index
                readonly property real deg: Math.round(ct.heading / 5) * 5 + (index - 12) * 5
                readonly property real dn: ((deg % 360) + 360) % 360
                readonly property bool major: dn % 15 === 0
                x: ct.width / 2 + (deg - ct.heading) * ct.ppd
                Rectangle { y: 45; width: 1; height: major ? 14 : 7; color: major ? win.text : win.dim }
                Text {
                    visible: major
                    y: 27; x: -implicitWidth / 2
                    text: ct.label(dn)
                    color: dn % 90 === 0 ? win.accent : win.dim
                    font.pixelSize: 12; font.bold: dn % 90 === 0
                }
            }
        }
        Rectangle { x: ct.width / 2 - 1; y: 22; width: 2; height: 40; color: win.accent; opacity: 0.55 }
        Item {                                   // heading-hold target, clamped to the edges
            visible: ct.showTarget
            readonly property real d: ct.wrap180(ct.target - ct.heading)
            readonly property bool inView: Math.abs(d) <= ct.span / 2 - 4
            x: ct.width / 2 + Math.max(-ct.span / 2 + 4, Math.min(ct.span / 2 - 4, d)) * ct.ppd
            y: 52
            Rectangle {
                x: -6; y: -6; width: 12; height: 12; rotation: 45
                color: parent.inView ? win.warn : "transparent"
                border.color: win.warn; border.width: 2
            }
        }
        Rectangle {                              // numeric readout
            x: ct.width / 2 - 28; y: 2; width: 56; height: 21; radius: 4
            color: "#04121a"; border.color: win.accent; border.width: 1
            Text { anchors.centerIn: parent; text: Math.round(ct.heading) % 360 + "°"; color: win.text; font.pixelSize: 13; font.bold: true; font.family: "monospace" }
        }
    }

    // Vertical depth tape (+/- 3 m window, depth grows downward), amber diamond = Depth Hold target.
    component DepthTape: Item {
        id: dt
        property real depth: 0
        property real target: 0
        property bool showTarget: false
        readonly property real span: 6
        readonly property real ppm: height / span
        clip: true

        Rectangle { anchors.fill: parent; color: "#0f1829"; border.color: win.line }
        Rectangle {                              // air above the surface
            width: parent.width; height: parent.height
            y: parent.height / 2 - dt.depth * dt.ppm - height
            color: "#2b6cb0"; opacity: 0.35
        }
        Repeater {
            model: 15
            delegate: Item {
                required property int index
                readonly property real m: Math.round(dt.depth * 2) / 2 + (index - 7) * 0.5
                readonly property bool major: Math.round(m * 2) % 2 === 0
                visible: m >= 0
                y: dt.height / 2 + (m - dt.depth) * dt.ppm
                Rectangle { x: 18; width: major ? 14 : 8; height: 1; color: major ? win.text : win.dim }
                Text { visible: major; x: 36; y: -height / 2; text: Math.round(m); color: win.dim; font.pixelSize: 11 }
            }
        }
        Item {                                   // depth-hold target
            visible: dt.showTarget
            x: 8
            y: Math.max(8, Math.min(dt.height - 8, dt.height / 2 + (dt.target - dt.depth) * dt.ppm))
            Rectangle {
                x: -6; y: -6; width: 12; height: 12; rotation: 45
                color: Math.abs(dt.target - dt.depth) < dt.span / 2 - 0.3 ? win.warn : "transparent"
                border.color: win.warn; border.width: 2
            }
        }
        Rectangle { x: 0; y: dt.height / 2; width: dt.width; height: 1; color: win.accent; opacity: 0.6 }
        Rectangle {
            x: dt.width - 46; y: dt.height / 2 - 10; width: 44; height: 20; radius: 4
            color: "#04121a"; border.color: win.accent; border.width: 1
            Text { anchors.centerIn: parent; text: dt.depth.toFixed(2); color: win.text; font.pixelSize: 12; font.bold: true; font.family: "monospace" }
        }
    }

    // ------------------------------------------------------------------ keyboard driving
    // W/S forward/back, A/D strafe, Q/E or Left/Right turn, R/F or Up/Down up/down
    Item {
        id: keys
        anchors.fill: parent
        focus: true
        property var down: ({})
        readonly property real gain: 0.7

        function axes() {
            var d = down
            return [
                ((d[Qt.Key_W] ? 1 : 0) - (d[Qt.Key_S] ? 1 : 0)) * gain,
                ((d[Qt.Key_D] ? 1 : 0) - (d[Qt.Key_A] ? 1 : 0)) * gain,
                // heave is +down: R / Up = ascend (negative), F / Down = descend (positive)
                ((d[Qt.Key_F] || d[Qt.Key_Down] ? 1 : 0) - (d[Qt.Key_R] || d[Qt.Key_Up] ? 1 : 0)) * gain,
                ((d[Qt.Key_E] || d[Qt.Key_Right] ? 1 : 0) - (d[Qt.Key_Q] || d[Qt.Key_Left] ? 1 : 0)) * gain
            ]
        }
        function send() { var a = axes(); backend.drive(a[0], a[1], a[2], a[3]) }
        function releaseAll() { down = ({}); backend.drive(0, 0, 0, 0) }
        function anyDown() { for (var k in down) return true; return false }

        Keys.onPressed: (e) => { if (!e.isAutoRepeat) { down[e.key] = true; send() } e.accepted = true }
        Keys.onReleased: (e) => { if (!e.isAutoRepeat) { delete down[e.key]; send() } e.accepted = true }
        onActiveFocusChanged: if (!activeFocus) releaseAll()

        // Heartbeat: while a key is held keep refreshing operator input (feeds the 1 s watchdog).
        Timer {
            interval: 100; repeat: true; running: true
            onTriggered: if (keys.anyDown()) keys.send()
        }
        TapHandler { onTapped: keys.forceActiveFocus() }
    }

    // ------------------------------------------------------------------ layout
    RowLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        // ============ left column ============
        ColumnLayout {
            Layout.preferredWidth: 380
            Layout.maximumWidth: 380
            Layout.fillHeight: true
            spacing: 12

            // status banner
            Card {
                Layout.fillWidth: true
                implicitHeight: 78
                border.color: backend.armed ? win.ok : win.bad
                border.width: 2
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    Rectangle { width: 16; height: 16; radius: 8; color: backend.armed ? win.ok : win.bad }
                    Column {
                        Layout.fillWidth: true
                        Text { text: backend.armed ? "ARMED" : "DISARMED"; color: backend.armed ? win.ok : win.bad; font.pixelSize: 22; font.bold: true }
                        Text {
                            text: "MODE  " + backend.mode.replace("_", " ")
                            color: win.dim; font.pixelSize: 12; font.letterSpacing: 1
                        }
                    }
                    Rectangle {              // flashing battery warning
                        id: batChip
                        visible: backend.voltage < 14.6
                        radius: 5
                        color: backend.voltage < 13.8 ? win.bad : win.warn
                        implicitWidth: batTxt.implicitWidth + 14
                        implicitHeight: 22
                        Text {
                            id: batTxt
                            anchors.centerIn: parent
                            text: backend.voltage < 13.8 ? "BATT CRITICAL" : "BATT LOW"
                            color: "#04121a"; font.pixelSize: 10; font.bold: true
                        }
                        SequentialAnimation on opacity {
                            running: batChip.visible
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 500 }
                            NumberAnimation { to: 1.0; duration: 500 }
                        }
                    }
                    Text { text: "t = " + backend.simTime.toFixed(0) + " s"; color: win.dim; font.pixelSize: 12; font.family: "monospace" }
                }
            }

            // telemetry
            Card {
                Layout.fillWidth: true
                implicitHeight: tele.implicitHeight + 24
                GridLayout {
                    id: tele
                    anchors.fill: parent
                    anchors.margins: 12
                    columns: 2
                    rowSpacing: 8
                    columnSpacing: 8
                    Tile { label: "ROLL"; value: backend.roll.toFixed(1) + "°" }
                    Tile { label: "PITCH"; value: backend.pitch.toFixed(1) + "°" }
                    Tile { label: "YAW / HDG"; value: backend.yaw.toFixed(1) + "°" }
                    Tile { label: "DEPTH"; value: backend.depth.toFixed(2) + " m" }
                    Tile {
                        Layout.columnSpan: 2
                        label: "BATTERY  (" + Math.round(backend.soc * 100) + "%)"
                        value: backend.voltage.toFixed(2) + " V"
                        valueColor: backend.voltage < 13.8 ? win.bad : backend.voltage < 14.6 ? win.warn : win.text
                    }
                }
            }

            // controls
            Card {
                Layout.fillWidth: true
                implicitHeight: ctl.implicitHeight + 24
                ColumnLayout {
                    id: ctl
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Btn { text: "ARM"; tint: win.ok; Layout.fillWidth: true; enabled: !backend.armed; onClicked: backend.arm() }
                        Btn { text: "DISARM"; tint: win.bad; Layout.fillWidth: true; active: !backend.armed; onClicked: backend.disarm() }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Btn { text: "Manual"; Layout.fillWidth: true; active: backend.mode === "MANUAL"; onClicked: backend.setMode("MANUAL") }
                        Btn { text: "Depth Hold"; Layout.fillWidth: true; active: backend.mode === "DEPTH_HOLD"; onClicked: backend.setMode("DEPTH_HOLD") }
                        Btn { text: "Heading Hold"; Layout.fillWidth: true; active: backend.mode === "HEADING_HOLD"; onClicked: backend.setMode("HEADING_HOLD") }
                    }

                    // target depth
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "Target depth"; color: win.dim; font.pixelSize: 12; Layout.preferredWidth: 92 }
                        Spin {
                            id: depthBox
                            Layout.fillWidth: true
                            from: 0; to: 500; stepSize: 5; value: 50
                            textFromValue: (v) => (v / 10).toFixed(1) + " m"
                            valueFromText: (t) => Math.round(parseFloat(t) * 10)
                            onApplied: { backend.setTargetDepth(value / 10); keys.forceActiveFocus() }
                        }
                        Btn { text: "Set"; implicitWidth: 56; onClicked: { backend.setTargetDepth(depthBox.value / 10); keys.forceActiveFocus() } }
                    }

                    // target heading
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text { text: "Target heading"; color: win.dim; font.pixelSize: 12; Layout.preferredWidth: 92 }
                        Spin {
                            id: headBox
                            Layout.fillWidth: true
                            from: 0; to: 359; stepSize: 5; value: 90; wrap: true
                            textFromValue: (v) => v + "°"
                            valueFromText: (t) => ((parseInt(t) % 360) + 360) % 360
                            onApplied: { backend.setTargetHeading(value); keys.forceActiveFocus() }
                        }
                        Btn { text: "Set"; implicitWidth: 56; onClicked: { backend.setTargetHeading(headBox.value); keys.forceActiveFocus() } }
                    }

                    Text {
                        Layout.fillWidth: true
                        color: win.dim; font.pixelSize: 11; font.family: "monospace"
                        text: "active target:  " + backend.targetDepth.toFixed(1) + " m   /   " + backend.targetHeading.toFixed(0) + "°"
                    }
                }
            }

            // thrust + key help
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 150
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6
                    Text { text: "THRUST  (normalised)"; color: win.dim; font.pixelSize: 11; font.letterSpacing: 1.2 }
                    ThrustBar { label: "Surge"; value: backend.thrust0 }
                    ThrustBar { label: "Sway"; value: backend.thrust1 }
                    ThrustBar { label: "Heave"; value: backend.thrust2 }
                    ThrustBar { label: "Yaw"; value: backend.thrust3 }
                    Item { Layout.fillHeight: true }
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: win.dim; font.pixelSize: 11
                        text: "Manual drive (click the dashboard first): W/S fwd/back · A/D strafe · Q/E or ←/→ turn · R/F or ↑/↓ up/down. Thrust cuts out 1 s after the last input."
                    }
                }
            }
        }

        // ============ right column ============
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            // compass tape
            Card {
                Layout.fillWidth: true
                implicitHeight: 70
                CompassTape {
                    anchors.fill: parent
                    anchors.margins: 4
                    heading: backend.yaw
                    target: backend.targetHeading
                    showTarget: backend.mode === "HEADING_HOLD"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.minimumHeight: 232
                Layout.preferredHeight: 232
                Layout.maximumHeight: 232
                spacing: 12

                // attitude + depth instruments
                Card {
                    Layout.preferredWidth: 326
                    Layout.fillHeight: true
                    Row {
                        anchors.centerIn: parent
                        spacing: 10
                        Item {
                            width: 200; height: 200
                            Horizon { anchors.fill: parent; roll: backend.roll; pitch: backend.pitch }
                            Rectangle { anchors.fill: parent; color: "transparent"; border.color: win.line; border.width: 2 }
                        }
                        DepthTape {
                            width: 92; height: 200
                            depth: backend.depth
                            target: backend.targetDepth
                            showTarget: backend.mode === "DEPTH_HOLD"
                        }
                    }
                }

                // depth vs time plot (no Canvas: Shapes + plain Items)
                Card {
                    id: plotCard
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Text { x: 14; y: 8; text: "DEPTH vs TIME  (last 60 s)"; color: win.dim; font.pixelSize: 11; font.letterSpacing: 1.2 }

                    Item {
                        id: plot
                        anchors.fill: parent
                        anchors.topMargin: 26

                        readonly property real pl: 52
                        readonly property real pr: 16
                        readonly property real pt_: 8
                        readonly property real pb: 26
                        readonly property real pw: width - pl - pr
                        readonly property real ph: height - pt_ - pb
                        readonly property real windowSec: 60

                        property var hist: []          // flat [t0, d0, t1, d1, ...], owned by QML
                        property var poly: []          // points for the trace, in plot-area coordinates
                        property real ymax: 4
                        property real tmax: 60

                        function refresh() {
                            var h = hist
                            tmax = h.length ? h[h.length - 2] : windowSec
                            var tmin = tmax - windowSec
                            var m = 0
                            for (var i = 1; i < h.length; i += 2) if (h[i] > m) m = h[i]
                            if (backend.mode === "DEPTH_HOLD" && backend.targetDepth > m) m = backend.targetDepth
                            // axis max is a multiple of 4 m so the four gridlines land on clean numbers
                            ymax = Math.max(4, Math.ceil((m + 0.5) / 4) * 4)
                            var out = []
                            for (var j = 0; j < h.length; j += 2) {
                                if (h[j] < tmin - 1) continue
                                out.push(Qt.point((h[j] - tmin) / windowSec * pw, h[j + 1] / ymax * ph))
                            }
                            poly = out
                        }

                        Connections {
                            target: backend
                            function onPlotChanged() {
                                plot.hist.push(backend.simTime, backend.depth)
                                while (plot.hist.length > 2 && plot.hist[0] < backend.simTime - 120) plot.hist.splice(0, 2)
                                plot.refresh()
                            }
                        }

                        // horizontal grid + depth labels
                        Repeater {
                            model: 5
                            delegate: Item {
                                required property int index
                                x: plot.pl; y: plot.pt_ + index * plot.ph / 4; width: plot.pw; height: 1
                                Rectangle { anchors.fill: parent; color: win.line }
                                Text {
                                    anchors.right: parent.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                                    color: win.dim; font.pixelSize: 11
                                    text: (index * plot.ymax / 4).toFixed(1) + " m"
                                }
                            }
                        }
                        // vertical grid + time labels
                        Repeater {
                            model: 7
                            delegate: Item {
                                required property int index
                                x: plot.pl + index * plot.pw / 6; y: plot.pt_; width: 1; height: plot.ph
                                Rectangle { anchors.fill: parent; color: win.line }
                                Text {
                                    anchors.top: parent.bottom; anchors.topMargin: 4; anchors.horizontalCenter: parent.horizontalCenter
                                    color: win.dim; font.pixelSize: 11
                                    text: "-" + (60 - index * 10) + " s"
                                }
                            }
                        }

                        // clipped plot area: target line + trace
                        Item {
                            x: plot.pl; y: plot.pt_; width: plot.pw; height: plot.ph
                            clip: true

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {   // depth-hold target
                                    strokeColor: backend.mode === "DEPTH_HOLD" ? win.warn : "transparent"
                                    strokeWidth: 1.5
                                    strokeStyle: ShapePath.DashLine
                                    dashPattern: [5, 4]
                                    fillColor: "transparent"
                                    startX: 0
                                    startY: backend.targetDepth / plot.ymax * plot.ph
                                    PathLine { x: plot.pw; y: backend.targetDepth / plot.ymax * plot.ph }
                                }
                                ShapePath {   // depth trace
                                    strokeColor: win.accent
                                    strokeWidth: 2
                                    fillColor: "transparent"
                                    joinStyle: ShapePath.RoundJoin
                                    PathPolyline { path: plot.poly }
                                }
                            }
                        }
                    }
                }
            }

            // OpenStreetMap
            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Plugin {
                    id: osm
                    name: "osm"
                    PluginParameter { name: "osm.useragent"; value: "ROV-Ground-Station/1.0 (technical assessment)" }
                    PluginParameter { name: "osm.mapping.providersrepository.disabled"; value: true }
                }

                Map {
                    id: map
                    anchors.fill: parent
                    anchors.margins: 1
                    plugin: osm
                    center: QtPositioning.coordinate(backend.lat, backend.lon)
                    zoomLevel: 15
                    minimumZoomLevel: 3
                    maximumZoomLevel: 19

                    property bool follow: true
                    property var lastCoord: QtPositioning.coordinate(backend.lat, backend.lon)

                    MapPolyline {
                        id: track
                        line.width: 3
                        line.color: "#22d3ee"
                        path: []
                    }

                    MapQuickItem {
                        id: marker
                        coordinate: QtPositioning.coordinate(backend.lat, backend.lon)
                        anchorPoint.x: 14; anchorPoint.y: 14
                        sourceItem: Item {
                            width: 28; height: 28
                            rotation: backend.yaw
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: backend.armed ? "#22c55e" : "#ef4444"
                                    strokeColor: "white"
                                    strokeWidth: 2
                                    startX: 14; startY: 2
                                    PathLine { x: 24; y: 25 }
                                    PathLine { x: 14; y: 20 }
                                    PathLine { x: 4; y: 25 }
                                    PathLine { x: 14; y: 2 }
                                }
                            }
                        }
                    }

                    Timer {
                        interval: 200; repeat: true; running: true
                        onTriggered: {
                            var c = QtPositioning.coordinate(backend.lat, backend.lon)
                            if (c.distanceTo(map.lastCoord) > 0.15) {
                                track.addCoordinate(c)
                                map.lastCoord = c
                                if (track.pathLength() > 600) track.removeCoordinate(0)
                            }
                            if (map.follow) map.center = c
                        }
                    }
                }

                // overlays: coordinates + HUD (top-left), follow toggle (top-right), scale bar (bottom-left)
                Column {
                    x: 12; y: 12
                    spacing: 6
                    Rectangle {
                        color: "#cc0b1220"; radius: 6
                        width: coordText.implicitWidth + 16; height: coordText.implicitHeight + 10
                        Text {
                            id: coordText
                            anchors.centerIn: parent
                            color: win.text; font.pixelSize: 12; font.family: "monospace"
                            text: backend.lat.toFixed(6) + ", " + backend.lon.toFixed(6)
                        }
                    }
                    Rectangle {
                        color: "#cc0b1220"; radius: 6
                        width: hudText.implicitWidth + 16; height: hudText.implicitHeight + 10
                        Text {
                            id: hudText
                            anchors.centerIn: parent
                            color: win.text; font.pixelSize: 12; font.family: "monospace"
                            text: "HDG " + Math.round(backend.yaw) % 360 + "°   DEPTH " + backend.depth.toFixed(1) + " m   " + backend.voltage.toFixed(1) + " V"
                        }
                    }
                }
                Btn {
                    x: parent.width - width - 12; y: 12
                    text: map.follow ? "Following" : "Follow vehicle"
                    active: map.follow
                    implicitWidth: 120; implicitHeight: 30
                    onClicked: map.follow = !map.follow
                }
                Rectangle {                       // scale bar, computed from zoom level and latitude
                    id: scaleBar
                    readonly property real mpp: 156543.03392 * Math.cos(backend.lat * Math.PI / 180) / Math.pow(2, map.zoomLevel)
                    readonly property var steps: [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]
                    function niceMetres() {
                        var best = steps[0]
                        for (var i = 0; i < steps.length; i++) if (steps[i] / mpp <= 120) best = steps[i]
                        return best
                    }
                    readonly property real metres: niceMetres()
                    readonly property real barPx: metres / mpp
                    x: 12; y: parent.height - height - 34
                    width: barPx + 16; height: 30; radius: 4
                    color: "#cc0b1220"
                    Rectangle { x: 8; y: 20; width: scaleBar.barPx; height: 2; color: "white" }
                    Rectangle { x: 8; y: 15; width: 2; height: 7; color: "white" }
                    Rectangle { x: 8 + scaleBar.barPx - 2; y: 15; width: 2; height: 7; color: "white" }
                    Text {
                        x: 8; y: 3
                        color: win.text; font.pixelSize: 11
                        text: scaleBar.metres >= 1000 ? (scaleBar.metres / 1000) + " km" : scaleBar.metres + " m"
                    }
                }
            }
        }
    }
}
