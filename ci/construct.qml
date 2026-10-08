import QtQuick

// Constructs the real view and says so, so the CI gate can require a positive line.
Item {
    width: 1024; height: 768
    Loader {
        anchors.fill: parent
        source: "../src/qml/Main.qml"
        onStatusChanged: {
            if (status === Loader.Ready) console.log("VIEW-READY")
            else if (status === Loader.Error) console.log("VIEW-ERROR")
        }
    }
}
