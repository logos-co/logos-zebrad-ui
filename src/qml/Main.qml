import QtQuick
import QtQuick.Layouts

import Logos.Theme
import Logos.Controls

Item {
    id: root
    objectName: "zebradRoot"

    readonly property var backend: (typeof logos !== "undefined" && logos) ? logos.module("zebrad_ui") : null
    readonly property bool ready: backend !== null

    function j(raw, fallback) { try { return raw ? JSON.parse(raw) : fallback } catch (e) { return fallback } }
    readonly property var networks: ready ? j(backend.networksJson, ["mainnet", "testnet"]) : ["mainnet", "testnet"]
    readonly property var st: ready ? j(backend.statusJson, ({})) : ({})
    readonly property bool cfgRead: ready && backend.configJson !== ""
    readonly property var cfg: cfgRead ? j(backend.configJson, ({})) : ({})
    readonly property string nodeState: ready ? backend.state : "unavailable"
    readonly property bool running: nodeState === "running"
    readonly property bool stopped: nodeState === "stopped" || nodeState === "failed" || nodeState === "unavailable"
    readonly property bool active: nodeState === "starting" || running

    // Zebra's gauges are -1 until it first sets them.
    function num(v) { var n = Number(v); return (v === undefined || v === null || v === "" || !isFinite(n)) ? -1 : n }
    readonly property real height_: num(st.height)
    readonly property real estimated: num(st.estimatedHeight)
    readonly property real finalized: num(st.finalizedHeight)
    readonly property int peers: num(st.peers)
    // The tip estimate runs on the clock, so a node at the tip reads a few blocks short of it.
    readonly property int tipSlack: 10
    // In the spike, 4 of 18 starts held only 2 peers for 45 s to 5 min, syncing at a crawl meanwhile.
    readonly property int minPeers: 3

    // Pure, so a test can drive states a live node will not hold on demand.
    function syncState(height, estimate, peerCount) {
        if (height >= 0 && estimate > 0 && estimate - height <= root.tipSlack)
            return peerCount > 0 ? "synced" : "nopeers"
        if (peerCount < root.minPeers) return "waiting"
        return "syncing"
    }
    // Regtest blocks carry 2011 timestamps, so the estimate runs millions ahead of a chain
    // that has no network to catch up with; the module reports it 100% synced.
    readonly property bool regtest: ready && backend.network === "regtest"
    readonly property string sync: !running ? "" : regtest ? "synced" : syncState(height_, estimated, peers)
    readonly property bool synced: sync === "synced"
    readonly property bool estimateKnown: height_ >= 0 && estimated > 0
    readonly property real progress: synced ? 1 : (estimateKnown ? Math.min(1, height_ / estimated) : 0)
    readonly property real percent: num(st.syncPercent) >= 0 ? num(st.syncPercent) : progress * 100

    function syncLabel(s) {
        if (s === "synced") return "Synced"
        if (s === "nopeers") return "No peers"
        if (s === "waiting") return "Waiting for peers"
        return s === "syncing" ? "Syncing" : ""
    }
    function stateColour(s) {
        if (s === "running") return Theme.palette.success
        if (s === "starting" || s === "stopping") return Theme.palette.info
        if (s === "failed" || s === "unavailable") return Theme.palette.error
        return Theme.palette.textTertiary
    }
    function fmtNum(n) { return n < 0 ? "—" : Number(n).toLocaleString(Qt.locale(), "f", 0) }
    function fmtUptime(s) {
        s = s || 0
        var h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60)
        return h > 0 ? (h + "h " + m + "m") : (m + "m " + (s % 60) + "s")
    }

    // ---- what the node opens to other programs ----
    // rpcExposed maps each listener to its address, "" while it is closed.
    readonly property var portNames: ({ lightwalletd: "lightwalletd gRPC", jsonRpc: "JSON-RPC",
                                        indexer: "indexer gRPC", health: "health endpoint" })
    readonly property var portNotes: ({ lightwalletd: ": no TLS and no authentication.",
                                        jsonRpc: ": no TLS; callers need the cookie in the cache directory." })
    readonly property var openPorts: {
        var e = active && st.rpcExposed ? st.rpcExposed : ({})
        var out = []
        for (var k in e)
            if (typeof e[k] === "string" && e[k] !== "") out.push({ key: k, name: portNames[k] || k, addr: e[k] })
        return out
    }
    readonly property bool exposed: openPorts.length > 0
    function exposedLine() {
        return root.exposed ? root.openPorts.map(function (p) { return p.name + " on " + p.addr }).join(" · ")
                            : "Nothing. The wallet reaches the node over Logos IPC."
    }
    function exposedNotice() {
        return root.openPorts.map(function (p) { return p.name + " on " + p.addr + (root.portNotes[p.key] || ".") }).join("\n")
               + "\nAny program on this computer can reach them, and so can web pages in a browser on this computer."
    }
    // Only a loopback address keeps a port on this computer.
    function loopback(a) {
        return /^(127\.\d{1,3}\.\d{1,3}\.\d{1,3}|\[::1\]|localhost)(:\d+)?$/.test(String(a || "").trim().toLowerCase())
    }
    function suggested(kind) {
        if (kind === "lightwalletd") return "127.0.0.1:9067"
        return root.ready && backend.network === "mainnet" ? "127.0.0.1:8232" : "127.0.0.1:18232"
    }

    // ---- the settings form ----
    // The form's copy of the two expose settings: a switch turns on only through its warning.
    property bool lwdOn: false
    property bool rpcOn: false
    property string confirmKind: ""

    function loadForm() {
        cacheDirField.text = cfg.cacheDir || ""
        listenField.text = cfg.listenAddr || ""
        peersField.text = cfg.peersetInitialTargetSize !== undefined ? String(cfg.peersetInitialTargetSize) : ""
        logFilterField.text = cfg.logFilter || ""
        minerField.text = cfg.minerAddress || ""
        lwdField.text = cfg.exposeLightwalletd || ""
        rpcField.text = cfg.exposeJsonRpc || ""
        root.lwdOn = !!cfg.exposeLightwalletd
        root.rpcOn = !!cfg.exposeJsonRpc
    }
    onCfgChanged: loadForm()

    readonly property bool formValid: cacheDirField.text.trim() !== "" && listenField.text.trim() !== ""
        && logFilterField.text.trim() !== "" && /^[1-9]\d*$/.test(peersField.text.trim())
        && (!root.lwdOn || lwdField.text.trim() !== "") && (!root.rpcOn || rpcField.text.trim() !== "")

    function saveForm() {
        var c = {
            cacheDir: cacheDirField.text.trim(), listenAddr: listenField.text.trim(),
            peersetInitialTargetSize: parseInt(peersField.text.trim(), 10), logFilter: logFilterField.text.trim(),
            exposeLightwalletd: root.lwdOn ? lwdField.text.trim() : "",
            exposeJsonRpc: root.rpcOn ? rpcField.text.trim() : ""
        }
        if (backend.network === "regtest") c.minerAddress = minerField.text.trim()
        backend.saveConfig(JSON.stringify(c))
    }

    // Turning a port off needs no warning; turning one on does.
    function toggleExpose(kind) {
        if (kind === "lightwalletd" && root.lwdOn) { root.lwdOn = false; return }
        if (kind === "jsonRpc" && root.rpcOn) { root.rpcOn = false; return }
        root.confirmKind = kind
        exposeDialog.open()
    }
    function confirmExpose() {
        if (root.confirmKind === "lightwalletd") {
            root.lwdOn = true
            if (lwdField.text.trim() === "") lwdField.text = root.suggested("lightwalletd")
        } else if (root.confirmKind === "jsonRpc") {
            root.rpcOn = true
            if (rpcField.text.trim() === "") rpcField.text = root.suggested("jsonRpc")
        }
        exposeDialog.close()
    }

    Connections {
        target: (typeof logos !== "undefined") ? logos : null
        ignoreUnknownSignals: true
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent !== "zcash.node.configure") return
            var n = params && params.network ? String(params.network) : ""
            if (n !== "" && root.networks.indexOf(n) < 0) { logos.respond(requestId, false, ({}), "bad_request"); return }
            if (n !== "" && root.stopped) backend.selectNetwork(n)
            logos.respond(requestId, true, ({}), "")
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    LogosScrollView {
        anchors.fill: parent
        anchors.margins: 20

        ColumnLayout {
            width: root.width - 40
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                LogosText { text: "Zcash node"; font.pixelSize: 22; font.weight: Theme.typography.weightBold }
                LogosBadge { objectName: "stateBadge"; text: root.nodeState || "checking"; color: root.stateColour(root.nodeState) }
                Item { Layout.fillWidth: true }
                LogosText { text: "Network"; color: Theme.palette.textTertiary }
                LogosComboBox {
                    objectName: "networkCombo"
                    model: root.networks
                    enabled: root.ready && root.stopped && !backend.busy
                    currentIndex: Math.max(0, root.networks.indexOf(root.ready ? backend.network : "testnet"))
                    onActivated: function(index) { backend.selectNetwork(root.networks[index]) }
                }
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        LogosText {
                            objectName: "heightText"
                            textFormat: Text.PlainText
                            font.weight: Theme.typography.weightBold
                            text: root.running ? "Height " + root.fmtNum(root.height_)
                                                 + (root.estimated > 0 && !root.regtest ? " / " + root.fmtNum(root.estimated) : "")
                                  : root.nodeState === "starting" ? "Starting…"
                                  : root.nodeState === "stopping" ? "Stopping…"
                                  : root.nodeState === "" ? "Checking…" : "Not running"
                        }
                        Item { Layout.fillWidth: true }
                        LogosText {
                            objectName: "syncText"
                            textFormat: Text.PlainText
                            color: root.sync === "waiting" || root.sync === "nopeers" ? Theme.palette.warning : Theme.palette.textTertiary
                            text: root.syncLabel(root.sync)
                                  + (root.running && !root.synced && root.estimateKnown && root.estimated - root.height_ > root.tipSlack
                                     ? " · " + root.fmtNum(root.estimated - root.height_) + " blocks behind" : "")
                        }
                        LogosText {
                            objectName: "syncPercent"
                            visible: root.running && root.estimateKnown && !root.synced
                            textFormat: Text.PlainText
                            text: (Math.floor(root.percent * 10) / 10) + "%"
                        }
                    }

                    LogosProgressBar {
                        objectName: "syncBar"
                        Layout.fillWidth: true
                        value: root.progress
                        trackColor: Theme.palette.borderSecondary
                        indeterminate: root.nodeState === "starting" || (root.running && !root.estimateKnown)
                        fillColor: root.synced ? Theme.palette.success
                                   : (root.sync === "waiting" || root.sync === "nopeers") ? Theme.palette.warning : Theme.palette.info
                    }

                    LogosText {
                        objectName: "waitingText"
                        Layout.fillWidth: true
                        visible: root.sync === "waiting" || root.sync === "nopeers"
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        text: root.sync === "nopeers" ? "No peer connected, so no new block can arrive until Zebra finds one."
                              : (root.peers > 0 ? "Connected to " + root.peers + (root.peers === 1 ? " peer" : " peers")
                                                : "No peer connected yet")
                                + ". Zebra keeps looking for more"
                                + (root.num(root.st.uptimeSecs) < 600 ? "; after a start this has taken up to five minutes." : ".")
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 20
                        rowSpacing: 4
                        LogosText { text: "Peers"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "peersText"; textFormat: Text.PlainText; text: root.running ? root.fmtNum(root.peers) : "—" }
                        LogosText { text: "Uptime"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; text: root.running ? root.fmtUptime(root.st.uptimeSecs) : "—" }
                        LogosText { text: "Finalized"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "finalizedText"; textFormat: Text.PlainText; text: root.running ? root.fmtNum(root.finalized) : "—" }
                        LogosText { text: "Version"; color: Theme.palette.textTertiary }
                        LogosText { Layout.fillWidth: true; elide: Text.ElideRight; textFormat: Text.PlainText; text: root.st.version || "—" }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        LogosText { text: "Cache directory"; color: Theme.palette.textTertiary }
                        LogosText {
                            objectName: "cacheDirText"
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            wrapMode: Text.WrapAnywhere
                            text: (root.active && root.st.cacheDir ? root.st.cacheDir : root.cfg.cacheDir) || "—"
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20
                        LogosText { text: "Open to other programs"; color: Theme.palette.textTertiary }
                        LogosText {
                            objectName: "exposedText"
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            wrapMode: Text.Wrap
                            color: root.exposed ? Theme.palette.warning : Theme.palette.text
                            text: root.active ? root.exposedLine() : "—"
                        }
                    }

                    LogosNotice {
                        objectName: "exposedNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Warning
                        shown: root.exposed
                        title: "Ports open to every program on this computer"
                        message: root.exposedNotice()
                    }

                    LogosText {
                        Layout.fillWidth: true
                        visible: root.running && root.num(root.st.chainAgeSecs) > 10
                        textFormat: Text.PlainText
                        color: Theme.palette.textTertiary
                        text: "Status sampled " + root.num(root.st.chainAgeSecs) + " s ago."
                    }

                    LogosText {
                        objectName: "errorText"
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        color: Theme.palette.error
                        text: !root.ready ? "The node module is not available."
                              : root.nodeState === "unavailable" ? "zebrad_module is not answering."
                              : (backend.lastError || root.st.lastError || "")
                    }

                    RowLayout {
                        spacing: 10
                        LogosButton {
                            objectName: "startButton"
                            text: "Start"
                            enabled: root.ready && root.stopped && !backend.busy
                            onClicked: backend.start()
                        }
                        LogosButton {
                            objectName: "stopButton"
                            text: "Stop"
                            enabled: root.ready && root.active && !backend.busy
                            onClicked: backend.stop()
                        }
                        LogosSpinner { visible: root.ready && backend.busy; running: visible }
                    }
                }
            }

            LogosText {
                objectName: "mainnetNotice"
                Layout.fillWidth: true
                visible: root.ready && backend.network === "mainnet" && root.stopped
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                color: Theme.palette.warning
                text: "A mainnet node keeps the whole chain, unpruned: about 300 GB in "
                    + (root.cfg.cacheDir || "its cache directory") + ". The first sync takes hours to days."
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    objectName: "settingsForm"
                    spacing: 8
                    enabled: root.cfgRead && root.stopped && !backend.busy

                    LogosText { text: "Settings for " + (root.ready ? backend.network : "") + " (apply on the next start)"; font.weight: Theme.typography.weightBold }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 8
                        LogosText { text: "Cache directory"; color: Theme.palette.textTertiary }
                        LogosTextField { id: cacheDirField; objectName: "cacheDirField"; Layout.fillWidth: true }
                        LogosText { text: "Listen address"; color: Theme.palette.textTertiary }
                        LogosTextField { id: listenField; objectName: "listenField"; Layout.fillWidth: true; placeholderText: "where other Zcash nodes reach this one" }
                        LogosText { text: "Initial peers"; color: Theme.palette.textTertiary }
                        LogosTextField { id: peersField; objectName: "peersField"; Layout.fillWidth: true; placeholderText: "25" }
                        LogosText { text: "Log filter"; color: Theme.palette.textTertiary }
                        LogosTextField { id: logFilterField; objectName: "logFilterField"; Layout.fillWidth: true; placeholderText: "info" }
                        LogosText { visible: root.ready && backend.network === "regtest"; text: "Miner address"; color: Theme.palette.textTertiary }
                        LogosTextField { id: minerField; visible: root.ready && backend.network === "regtest"; Layout.fillWidth: true }
                    }

                    LogosText { Layout.topMargin: 8; text: "Open to other programs on this computer"; font.weight: Theme.typography.weightBold }
                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary
                        text: "Off by default. The wallet does not need them: it reaches the node over Logos IPC. "
                            + "Turn one on only for another program on this computer that asks for it."
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        LogosSwitch {
                            objectName: "exposeLwdSwitch"
                            Layout.preferredWidth: 200
                            text: "lightwalletd gRPC"
                            checkable: false
                            checked: root.lwdOn
                            onClicked: root.toggleExpose("lightwalletd")
                        }
                        LogosTextField { id: lwdField; objectName: "exposeLwdField"; Layout.fillWidth: true; enabled: root.lwdOn; placeholderText: root.suggested("lightwalletd") }
                    }
                    LogosText {
                        Layout.fillWidth: true
                        visible: root.lwdOn
                        wrapMode: Text.Wrap
                        color: Theme.palette.warning
                        text: "No TLS and no authentication: any program on this computer, or a web page in a browser here, "
                              + "can read the chain and send transactions through it."
                              + (lwdField.text.trim() !== "" && !root.loopback(lwdField.text) ? " This address is reachable from other computers too." : "")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        LogosSwitch {
                            objectName: "exposeRpcSwitch"
                            Layout.preferredWidth: 200
                            text: "JSON-RPC"
                            checkable: false
                            checked: root.rpcOn
                            onClicked: root.toggleExpose("jsonRpc")
                        }
                        LogosTextField { id: rpcField; objectName: "exposeRpcField"; Layout.fillWidth: true; enabled: root.rpcOn; placeholderText: root.suggested("jsonRpc") }
                    }
                    LogosText {
                        Layout.fillWidth: true
                        visible: root.rpcOn
                        wrapMode: Text.Wrap
                        color: Theme.palette.warning
                        text: "No TLS. Callers need the cookie Zebra writes in the cache directory, but any program on this computer can reach the port, and so can web pages in a browser here."
                              + (rpcField.text.trim() !== "" && !root.loopback(rpcField.text) ? " This address is reachable from other computers too." : "")
                    }

                    RowLayout {
                        Layout.topMargin: 8
                        LogosButton { objectName: "saveButton"; text: "Save settings"; enabled: root.formValid; onClicked: root.saveForm() }
                        LogosButton { text: "Revert"; onClicked: root.loadForm() }
                    }
                }
            }

            LogosFrame {
                Layout.fillWidth: true
                backgroundColor: Theme.palette.surfaceRaised
                borderColor: Theme.palette.borderSecondary
                radius: Theme.spacing.radiusLarge
                padding: Theme.spacing.large

                contentItem: ColumnLayout {
                    spacing: 6
                    LogosText { text: "Node log"; font.weight: Theme.typography.weightBold }
                    LogosText {
                        objectName: "logText"
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        wrapMode: Text.WrapAnywhere
                        font.family: Theme.typography.mono
                        font.pixelSize: 11
                        color: Theme.palette.textTertiary
                        text: root.ready && backend.logText ? backend.logText : "No log yet."
                    }
                }
            }
        }
    }

    LogosWarningDialog {
        id: exposeDialog
        objectName: "exposeDialog"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        title: root.confirmKind === "lightwalletd" ? "Open lightwalletd gRPC to other programs?" : "Open JSON-RPC to other programs?"
        message: root.confirmKind === "lightwalletd"
                 ? "This opens a TCP port with no TLS and no authentication. Anything that reaches it can read the chain and "
                   + "send transactions through your node: any program on this computer, and web pages open in a browser on "
                   + "this computer. The wallet does not need it."
                 : "This opens a TCP port with no TLS. Callers need the cookie Zebra writes in its cache directory, but any "
                   + "program on this computer can reach the port, and so can web pages open in a browser on this computer. "
                   + "The wallet does not need it."
        onClosed: root.confirmKind = ""
        leftActions: [ LogosButton { text: "Cancel"; onClicked: exposeDialog.close() } ]
        rightActions: [ LogosButton { objectName: "exposeConfirmButton"; text: "Open the port"; onClicked: root.confirmExpose() } ]
    }
}
