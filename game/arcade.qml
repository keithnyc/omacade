import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: arcade

  readonly property string gameDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  property var cabinets: CabinetRegistry.cabinets
  property int selectedIndex: 0
  property bool showScores: false
  property var stars: []
  property real starTime: 0

  ArcadeTheme { id: theme }
  ArcadeData { id: arcadeData; cabinetId: arcade.cabinets.length ? arcade.cabinets[arcade.selectedIndex].scoreKey : "" }

  SoundEffect { id: moveSound; source: Qt.resolvedUrl("assets/sfx/rotate.wav"); volume: 0.30 }
  SoundEffect { id: launchSound; source: Qt.resolvedUrl("assets/sfx/start.wav"); volume: 0.46 }

  function play(effect) {
    if (!arcadeData.soundEnabled) return
    effect.stop()
    effect.play()
  }

  function select(direction) {
    if (!cabinets.length) return
    selectedIndex = (selectedIndex + direction + cabinets.length) % cabinets.length
    arcadeData.cabinetId = cabinets[selectedIndex].scoreKey
    arcadeData.applyScores(JSON.stringify(arcadeData.scoreData || {}))
    play(moveSound)
  }

  function launchSelected() {
    if (!cabinets.length || cabinetProcess.running) return
    var cabinet = cabinets[selectedIndex]
    if (cabinet.status !== "ready") return
    play(launchSound)
    cabinetProcess.command = ["qs", "-n", "-p", gameDir + "/" + cabinet.entry]
    cabinetProcess.running = true
    lobby.visible = false
  }

  function toggleSound() {
    arcadeData.patchConfig({ sound: !arcadeData.soundEnabled })
    if (arcadeData.soundEnabled) play(launchSound)
  }

  Component.onCompleted: {
    var generated = []
    for (var i = 0; i < 75; i++) {
      generated.push({
        x: Math.random(), y: Math.random(), radius: Math.random() < 0.12 ? 1.8 : 0.8,
        alpha: 0.22 + Math.random() * 0.65, phase: Math.random() * Math.PI * 2,
        speed: 0.5 + Math.random() * 1.8
      })
    }
    stars = generated
  }

  Process {
    id: cabinetProcess
    onExited: {
      lobby.visible = true
      lobbyContent.forceActiveFocus()
      arcadeData.applyScores(JSON.stringify(arcadeData.scoreData || {}))
    }
  }

  Timer {
    interval: 33
    repeat: true
    running: true
    onTriggered: {
      arcade.starTime += 0.033
      starCanvas.requestPaint()
    }
  }

  FloatingWindow {
    id: lobby
    visible: true
    title: "Omacade"
    color: theme.background
    implicitWidth: 1040
    implicitHeight: 720
    minimumSize: Qt.size(800, 560)
    onVisibleChanged: if (!visible && !cabinetProcess.running) Qt.quit()

    FocusScope {
      id: lobbyContent
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()

      Keys.onPressed: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (arcade.showScores) {
          if (event.key === Qt.Key_H || event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            arcade.showScores = false
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) arcade.select(-1)
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) arcade.select(1)
        else if (event.key === Qt.Key_H) arcade.showScores = true
        else if (event.key === Qt.Key_M) arcade.toggleSound()
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) arcade.launchSelected()
        else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) Qt.quit()
        event.accepted = true
      }

      Rectangle {
        anchors.fill: parent
        color: theme.background

        Canvas {
          id: starCanvas
          anchors.fill: parent
          onPaint: {
            var context = getContext("2d")
            context.reset()
            context.fillStyle = theme.background
            context.fillRect(0, 0, width, height)
            for (var i = 0; i < arcade.stars.length; i++) {
              var star = arcade.stars[i]
              var pulse = 0.55 + 0.45 * Math.sin(arcade.starTime * star.speed + star.phase)
              context.globalAlpha = star.alpha * pulse
              context.fillStyle = theme.foreground
              context.beginPath()
              context.arc(star.x * width, star.y * height, star.radius, 0, Math.PI * 2)
              context.fill()
            }
            context.globalAlpha = 1
          }
        }

        Column {
          anchors.fill: parent
          anchors.margins: 34
          spacing: 22

          Row {
            width: parent.width
            height: 92
            Column {
              width: parent.width * 0.7
              Text {
                text: "O M A C A D E"
                color: theme.accent
                font.pixelSize: 38
                font.bold: true
                font.letterSpacing: 5
              }
              Text {
                text: "INSERT NO COINS  //  SELECT A CABINET"
                color: theme.muted
                font.pixelSize: 13
                font.family: "monospace"
                font.letterSpacing: 1.5
              }
            }
            Column {
              width: parent.width * 0.3
              anchors.verticalCenter: parent.verticalCenter
              Text {
                anchors.right: parent.right
                text: "PILOT " + (arcadeData.defaultInitials || "---")
                color: theme.foreground
                font.pixelSize: 14
                font.family: "monospace"
                font.bold: true
              }
              Text {
                anchors.right: parent.right
                text: "SOUND " + (arcadeData.soundEnabled ? "ON" : "OFF")
                color: arcadeData.soundEnabled ? theme.green : theme.muted
                font.pixelSize: 12
                font.family: "monospace"
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: theme.muted; opacity: 0.8 }

          Row {
            id: cabinetRow
            width: parent.width
            height: parent.height - 225
            spacing: 22

            Rectangle {
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              radius: 12
              color: theme.surface
              border.color: theme.accent
              border.width: 3

              Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14
                Text { text: "CABINET " + arcade.cabinets[arcade.selectedIndex].number; color: theme.muted; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
                Text { text: arcade.cabinets[arcade.selectedIndex].displayTitle; color: theme.foreground; font.pixelSize: 31; font.bold: true; font.letterSpacing: 2 }
                Text { text: arcade.cabinets[arcade.selectedIndex].tagline.toUpperCase(); color: theme.green; font.pixelSize: 13; font.family: "monospace" }
                Rectangle { width: parent.width; height: 1; color: theme.muted; opacity: 0.6 }
                Text { width: parent.width; text: arcade.cabinets[arcade.selectedIndex].description; wrapMode: Text.WordWrap; color: theme.foreground; font.pixelSize: 15; lineHeight: 1.25 }
                Text { width: parent.width; text: arcade.cabinets[arcade.selectedIndex].controls; wrapMode: Text.WordWrap; color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
                Item { width: 1; height: 4 }
                Text { text: "BEST SCORE     " + arcadeData.bestScore; color: theme.yellow; font.pixelSize: 15; font.family: "monospace"; font.bold: true }
                Text { text: "HIGHEST STAGE  " + arcadeData.highestStage; color: theme.foreground; font.pixelSize: 14; font.family: "monospace" }
                Item { width: 1; height: 4 }
                Text {
                  id: playPrompt
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "PRESS ENTER TO PLAY"
                  color: theme.accent
                  font.pixelSize: 18
                  font.family: "monospace"
                  font.bold: true
                  SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: 650 }
                    NumberAnimation { to: 1; duration: 650 }
                  }
                }
              }
            }

            Rectangle {
              property int previewIndex: arcade.cabinets.length > 1
                ? (arcade.selectedIndex + 1) % arcade.cabinets.length : arcade.selectedIndex
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              radius: 12
              color: theme.surface
              opacity: 0.78
              border.color: theme.muted
              border.width: 1
              Column {
                anchors.fill: parent
                anchors.margins: 28
                spacing: 14
                Text { text: "CABINET " + arcade.cabinets[parent.parent.previewIndex].number; color: theme.muted; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
                Text { width: parent.width; text: arcade.cabinets[parent.parent.previewIndex].displayTitle; wrapMode: Text.WordWrap; color: theme.foreground; font.pixelSize: 27; font.bold: true; font.letterSpacing: 2 }
                Text { width: parent.width; text: arcade.cabinets[parent.parent.previewIndex].tagline.toUpperCase(); wrapMode: Text.WordWrap; color: theme.yellow; font.pixelSize: 13; font.family: "monospace" }
                Rectangle { width: parent.width; height: 1; color: theme.muted; opacity: 0.6 }
                Text { width: parent.width; text: arcade.cabinets[parent.parent.previewIndex].description; wrapMode: Text.WordWrap; color: theme.foreground; font.pixelSize: 15; lineHeight: 1.25 }
                Text { width: parent.width; text: arcade.cabinets[parent.parent.previewIndex].controls; wrapMode: Text.WordWrap; color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
                Item { width: 1; height: 12 }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "← / →  SELECT CABINET"; color: theme.accent; font.pixelSize: 15; font.family: "monospace"; font.bold: true }
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← → SELECT    ENTER PLAY    H RECORDS    M SOUND    Q QUIT"
            color: theme.muted
            font.pixelSize: 12
            font.family: "monospace"
            font.bold: true
          }
        }

        Rectangle {
          visible: arcade.showScores
          anchors.centerIn: parent
          width: Math.min(parent.width - 60, 620)
          height: Math.min(parent.height - 50, 470)
          radius: 12
          color: theme.surface
          border.color: theme.accent
          border.width: 2
          z: 20
          Column {
            anchors.fill: parent
            anchors.margins: 26
            spacing: 8
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: arcade.cabinets[arcade.selectedIndex].shortTitle + " // TOP TEN"; color: theme.accent; font.pixelSize: 23; font.bold: true }
            Text { text: " #    PILOT       SCORE        CLASS"; color: theme.muted; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
            Rectangle { width: parent.width; height: 1; color: theme.muted }
            Repeater {
              model: 10
              delegate: Text {
                property var row: index < arcadeData.scoreRows.length ? arcadeData.scoreRows[index] : null
                width: parent.width
                text: {
                  var rank = index < 9 ? " " + String(index + 1) : String(index + 1)
                  var pilot = row ? (arcadeData.cleanInitials(row.initials) || "---") : "---"
                  var points = row ? ("       " + String(Math.round(Number(row.score || 0)))).slice(-7) : "      -"
                  var klass = row ? String(row.difficulty || "cadet").toUpperCase() + " S" + Math.max(1, Number(row.stage || 1)) : "---"
                  return rank + "    " + (pilot + "        ").slice(0, 8) + "  " + points + "       " + klass
                }
                color: row && index === 0 ? theme.yellow : row ? theme.foreground : theme.muted
                font.pixelSize: 15
                font.family: "monospace"
                font.bold: row && index === 0
              }
            }
            Item { width: 1; height: 4 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "H / ENTER / ESC  CLOSE"; color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
          }
        }
      }
    }
  }
}
