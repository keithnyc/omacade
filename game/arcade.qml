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
  property bool showRecap: false
  property bool editingPilot: false
  property string pilotInput: ""
  property bool pilotPristine: true
  property string launchRunAt: ""
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

  function selectIndex(index) {
    if (index < 0 || index >= cabinets.length || index === selectedIndex) return
    selectedIndex = index
    arcadeData.cabinetId = cabinets[selectedIndex].scoreKey
    arcadeData.applyScores(JSON.stringify(arcadeData.scoreData || {}))
    play(moveSound)
  }

  function launchSelected() {
    if (!cabinets.length || cabinetProcess.running) return
    var cabinet = cabinets[selectedIndex]
    if (cabinet.status !== "ready") return
    var previousRun = arcadeData.lastRunFor(cabinet.scoreKey)
    launchRunAt = previousRun && previousRun.at ? String(previousRun.at) : ""
    play(launchSound)
    cabinetProcess.command = ["qs", "-n", "-p", gameDir + "/" + cabinet.entry]
    cabinetProcess.running = true
    lobby.visible = false
  }

  function toggleSound() {
    arcadeData.patchConfig({ sound: !arcadeData.soundEnabled })
    if (arcadeData.soundEnabled) play(launchSound)
  }

  function beginPilotEdit() {
    pilotInput = arcadeData.defaultInitials
    pilotPristine = true
    editingPilot = true
  }

  function savePilot() {
    var initials = arcadeData.cleanInitials(pilotInput)
    if (initials) arcadeData.patchConfig({ initials: initials })
    editingPilot = false
  }

  function runDetail(run, cabinetId) {
    if (!run || run.score === undefined) return "NO SESSION DATA"
    if (cabinetId === "lander") return "FUEL " + Number(run.fuel || 0).toFixed(1) + "  //  FLIGHT " + Number(run.time || 0).toFixed(1) + "S"
    if (cabinetId === "rootbound") return "PACKAGES " + Number(run.packages || 0) + "  //  DEPTH " + Math.max(1, Number(run.stage || 1))
    return "PORTS " + Number(run.ports || 0) + "  //  TTL " + Math.ceil(Number(run.ttl || 0))
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
      arcadeData.reloadScores()
      recapTimer.restart()
    }
  }

  Timer {
    id: recapTimer
    interval: 240
    repeat: false
    onTriggered: {
      arcadeData.applyScores(JSON.stringify(arcadeData.scoreData || {}))
      arcade.showRecap = arcadeData.lastRun && arcadeData.lastRun.score !== undefined
                        && String(arcadeData.lastRun.at || "") !== arcade.launchRunAt
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
        if (arcade.editingPilot) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) arcade.savePilot()
          else if (event.key === Qt.Key_Escape) arcade.editingPilot = false
          else if (event.key === Qt.Key_Backspace) {
            arcade.pilotInput = arcade.pilotPristine ? "" : arcade.pilotInput.slice(0, -1)
            arcade.pilotPristine = false
          } else {
            var pilotKey = arcadeData.cleanInitials(event.text)
            if (pilotKey && arcade.pilotInput.length < 3) {
              if (arcade.pilotPristine) arcade.pilotInput = ""
              arcade.pilotPristine = false
              arcade.pilotInput = (arcade.pilotInput + pilotKey).slice(0, 3)
            }
          }
          event.accepted = true
          return
        }
        if (arcade.showRecap) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            arcade.showRecap = false
          event.accepted = true
          return
        }
        if (arcade.showScores) {
          if (event.key === Qt.Key_H || event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            arcade.showScores = false
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) arcade.select(-1)
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) arcade.select(1)
        else if (event.key === Qt.Key_H) arcade.showScores = true
        else if (event.key === Qt.Key_I) arcade.beginPilotEdit()
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
                text: arcadeData.totalRuns + " RUNS  //  " + arcadeData.achievementCount() + "/5 BADGES"
                color: theme.yellow
                font.pixelSize: 10
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
            id: arcadeFloor
            width: parent.width
            height: 78
            spacing: 12
            Repeater {
              model: arcade.cabinets
              delegate: Rectangle {
                required property int index
                required property var modelData
                width: (arcadeFloor.width - arcadeFloor.spacing * (arcade.cabinets.length - 1)) / arcade.cabinets.length
                height: arcadeFloor.height
                radius: 8
                color: index === arcade.selectedIndex ? theme.surfaceRaised : theme.surface
                border.color: index === arcade.selectedIndex ? theme.accent : theme.muted
                border.width: index === arcade.selectedIndex ? 2 : 1
                opacity: index === arcade.selectedIndex ? 1 : 0.76
                Column {
                  anchors.fill: parent
                  anchors.margins: 10
                  spacing: 3
                  Text { text: "0" + (index + 1) + " // " + modelData.shortTitle; color: index === arcade.selectedIndex ? theme.accent : theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
                  Text { text: "BEST " + arcadeData.bestFor(modelData.scoreKey); color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                  Text { text: "STAGE " + arcadeData.highestFor(modelData.scoreKey) + "  ·  RUNS " + arcadeData.completedFor(modelData.scoreKey); color: theme.muted; font.pixelSize: 9; font.family: "monospace" }
                }
                MouseArea { anchors.fill: parent; onClicked: arcade.selectIndex(index) }
              }
            }
          }

          Row {
            id: cabinetRow
            width: parent.width
            height: parent.height - 325
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
                spacing: 10
                Text { text: "CABINET " + arcade.cabinets[arcade.selectedIndex].number; color: theme.muted; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
                Text { text: arcade.cabinets[arcade.selectedIndex].displayTitle; color: theme.foreground; font.pixelSize: 31; font.bold: true; font.letterSpacing: 2 }
                Text { text: arcade.cabinets[arcade.selectedIndex].tagline.toUpperCase(); color: theme.green; font.pixelSize: 13; font.family: "monospace" }
                Rectangle { width: parent.width; height: 1; color: theme.muted; opacity: 0.6 }
                Text { width: parent.width; text: arcade.cabinets[arcade.selectedIndex].description; wrapMode: Text.WordWrap; color: theme.foreground; font.pixelSize: 15; lineHeight: 1.25 }
                Text { width: parent.width; text: arcade.cabinets[arcade.selectedIndex].controls; wrapMode: Text.WordWrap; color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
                Item { width: 1; height: 4 }
                Text { text: "BEST SCORE     " + arcadeData.bestScore; color: theme.yellow; font.pixelSize: 15; font.family: "monospace"; font.bold: true }
                Text { text: "HIGHEST STAGE  " + arcadeData.highestStage; color: theme.foreground; font.pixelSize: 14; font.family: "monospace" }
                Text {
                  property var run: arcadeData.lastRun
                  text: run && run.score !== undefined ? "LAST RUN       " + Math.round(Number(run.score || 0)) + "  //  STAGE " + Math.max(1, Number(run.stage || 1)) : "LAST RUN       --"
                  color: theme.muted; font.pixelSize: 11; font.family: "monospace"; font.bold: true
                }
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
              width: (parent.width - parent.spacing) / 2
              height: parent.height
              radius: 12
              color: theme.surface
              border.color: theme.muted
              border.width: 1
              Column {
                anchors.fill: parent
                anchors.margins: 22
                spacing: 8
                Row {
                  width: parent.width
                  Text { id: profileTitle; text: "PLAYER PROFILE // " + (arcadeData.defaultInitials || "---"); color: theme.accent; font.pixelSize: 15; font.family: "monospace"; font.bold: true }
                  Item { width: Math.max(8, parent.width - profileTitle.implicitWidth - profileEdit.implicitWidth); height: 1 }
                  Text { id: profileEdit; text: "I  EDIT"; color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                }
                Text { text: arcadeData.totalRuns + " TOTAL RUNS  ·  " + arcadeData.achievementCount() + "/5 UNLOCKED"; color: theme.yellow; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
                Rectangle { width: parent.width; height: 1; color: theme.muted; opacity: 0.6 }
                Text { text: "ACHIEVEMENTS"; color: theme.foreground; font.pixelSize: 11; font.family: "monospace"; font.bold: true; font.letterSpacing: 1.4 }
                Repeater {
                  model: arcadeData.achievementDefinitions
                  delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 37
                    radius: 5
                    color: arcadeData.achievementUnlocked(modelData.id) ? theme.surfaceRaised : theme.background
                    border.color: arcadeData.achievementUnlocked(modelData.id) ? theme.green : theme.muted
                    border.width: 1
                    opacity: arcadeData.achievementUnlocked(modelData.id) ? 1 : 0.56
                    Row {
                      anchors.fill: parent
                      anchors.margins: 7
                      spacing: 10
                      Text { text: arcadeData.achievementUnlocked(modelData.id) ? "◆" : "◇"; color: arcadeData.achievementUnlocked(modelData.id) ? theme.green : theme.muted; font.pixelSize: 14 }
                      Column {
                        width: parent.width - 30
                        Text { text: modelData.title; color: arcadeData.achievementUnlocked(modelData.id) ? theme.green : theme.foreground; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                        Text { width: parent.width; text: modelData.detail; color: theme.muted; font.pixelSize: 8; font.family: "monospace"; elide: Text.ElideRight }
                      }
                    }
                  }
                }
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "← → SELECT    ENTER PLAY    H RECORDS    I PILOT    M SOUND    Q QUIT"
            color: theme.muted
            font.pixelSize: 12
            font.family: "monospace"
            font.bold: true
          }
        }

        Rectangle {
          property var run: arcadeData.lastRun
          visible: arcade.showRecap
          anchors.centerIn: parent
          width: Math.min(parent.width - 60, 600)
          height: Math.min(parent.height - 50, 410)
          radius: 12
          color: theme.surface
          border.color: run && run.newBest ? theme.yellow : theme.accent
          border.width: 3
          z: 24
          Column {
            anchors.centerIn: parent
            width: parent.width - 56
            spacing: 12
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SESSION COMPLETE"; color: theme.accent; font.pixelSize: 13; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: arcade.cabinets[arcade.selectedIndex].shortTitle; color: theme.foreground; font.pixelSize: 28; font.bold: true; font.letterSpacing: 2 }
            Rectangle { width: parent.width; height: 1; color: theme.muted }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(Number(parent.parent.run.score || 0)); color: theme.yellow; font.pixelSize: 42; font.family: "monospace"; font.bold: true }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "STAGE " + Math.max(1, Number(parent.parent.run.stage || 1)) + "  //  " + arcade.runDetail(parent.parent.run, arcade.cabinets[arcade.selectedIndex].id); color: theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 12
              Rectangle {
                visible: parent.parent.parent.run.newBest === true
                width: 174; height: 28; radius: 5; color: theme.background; border.color: theme.yellow
                Text { anchors.centerIn: parent; text: "★ NEW PERSONAL BEST"; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              }
              Rectangle {
                visible: parent.parent.parent.run.newStage === true
                width: 150; height: 28; radius: 5; color: theme.background; border.color: theme.green
                Text { anchors.centerIn: parent; text: "▲ NEW HIGH STAGE"; color: theme.green; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              }
            }
            Text {
              property var unlockRows: parent.parent.run && Array.isArray(parent.parent.run.unlocks) ? parent.parent.run.unlocks : []
              anchors.horizontalCenter: parent.horizontalCenter
              visible: unlockRows.length > 0
              text: "ACHIEVEMENT UNLOCKED // " + (unlockRows.length > 0 && arcadeData.achievementById(unlockRows[0]) ? arcadeData.achievementById(unlockRows[0]).title : "NEW BADGE")
              color: theme.green; font.pixelSize: 12; font.family: "monospace"; font.bold: true
            }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ENTER / ESC  RETURN TO ARCADE"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
          }
        }

        Rectangle {
          visible: arcade.editingPilot
          anchors.centerIn: parent
          width: Math.min(parent.width - 60, 430)
          height: 230
          radius: 12
          color: theme.surface
          border.color: theme.accent
          border.width: 2
          z: 26
          Column {
            anchors.centerIn: parent
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PLAYER PROFILE"; color: theme.accent; font.pixelSize: 14; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ENTER PILOT INITIALS"; color: theme.foreground; font.pixelSize: 12; font.family: "monospace" }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: (arcade.pilotInput + "___").slice(0, 3); color: theme.yellow; font.pixelSize: 42; font.family: "monospace"; font.bold: true; font.letterSpacing: 10 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ENTER SAVE  //  ESC CANCEL"; color: theme.muted; font.pixelSize: 10; font.family: "monospace" }
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
