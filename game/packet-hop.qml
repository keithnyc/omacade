import QtQuick
import QtMultimedia
import Quickshell
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("packet-hop")
  ArcadeTheme { id: theme }
  ArcadeData { id: arcadeData; cabinetId: shell.cabinet.scoreKey }

  SoundEffect { id: hopSound; source: Qt.resolvedUrl("assets/sfx/packet-hop.wav"); volume: 0.25 }
  SoundEffect { id: bindSound; source: Qt.resolvedUrl("assets/sfx/packet-bind.wav"); volume: 0.42 }
  SoundEffect { id: dropSound; source: Qt.resolvedUrl("assets/sfx/packet-drop.wav"); volume: 0.44 }
  SoundEffect { id: stageSound; source: Qt.resolvedUrl("assets/sfx/packet-stage.wav"); volume: 0.44 }
  SoundEffect { id: ttlSound; source: Qt.resolvedUrl("assets/sfx/packet-ttl.wav"); volume: 0.32 }

  function play(effect) {
    if (!arcadeData.soundEnabled) return
    effect.stop()
    effect.play()
  }

  FloatingWindow {
    id: window
    visible: true
    title: shell.cabinet.windowTitle
    color: theme.background
    implicitWidth: 960
    implicitHeight: 760
    minimumSize: Qt.size(760, 600)
    onVisibleChanged: if (!visible) Qt.quit()

    FocusScope {
      id: game
      anchors.fill: parent
      focus: true

      readonly property int columns: 15
      readonly property int rows: 12
      readonly property url spriteAtlas: Qt.resolvedUrl("assets/packet-hop-sprites.png")
      readonly property real spriteCell: 313.5
      readonly property string zoneName: stage === 1 ? "/LAN" : stage === 2 ? "/WAN" : stage === 3 ? "/VPN" : "/ROOT"
      readonly property real cellWidth: playfield.width / columns
      readonly property real cellHeight: playfield.height / rows
      readonly property bool tooSmall: playfield.width < 620 || playfield.height < 430

      property var lanes: []
      property var ports: []
      property var ttlPickup: ({ x: 7, y: 5, active: true })
      property real playerX: 7
      property int playerY: 11
      property real playerVisualX: 7
      property real playerVisualY: 11
      property int score: 0
      property int stage: 1
      property int lives: 3
      property int deliveries: 0
      property real ttl: 45
      property string mode: "attract"
      property string modeBeforeScores: "attract"
      property string statusMessage: "ROUTE READY"
      property real animationTime: 0
      property real transitionLife: 0
      property real lastHopAt: -10000
      property int intentX: 0
      property int intentY: 0
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property string initialsInput: ""
      property bool initialsPristine: true

      Component.onCompleted: {
        worldCanvas.loadImage(spriteAtlas)
        buildStage()
        mode = "attract"
        forceActiveFocus()
      }

      function drawSprite(context, column, row, centerX, centerY, drawWidth, drawHeight, opacity, flipX) {
        if (!worldCanvas.isImageLoaded(spriteAtlas)) return false
        context.save()
        context.globalAlpha = opacity === undefined ? 1 : opacity
        context.translate(centerX, centerY)
        context.scale(flipX ? -1 : 1, 1)
        context.drawImage(spriteAtlas,
                          column * spriteCell, row * spriteCell, spriteCell, spriteCell,
                          -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight)
        context.restore()
        return true
      }

      function lane(row) {
        for (var i = 0; i < lanes.length; i++) if (lanes[i].row === row) return lanes[i]
        return null
      }

      function makeLane(row, type, kind, direction, speed, count, width) {
        var items = []
        var spacing = columns / count
        var offset = Math.random() * spacing
        for (var i = 0; i < count; i++) items.push({ x: offset + i * spacing, width: width })
        return { row: row, type: type, kind: kind, direction: direction,
                 speed: speed, items: items }
      }

      function buildStage() {
        var pace = 1 + Math.min(stage - 1, 5) * 0.11
        lanes = [
          makeLane(2, "network", "pipe", 1, 1.12 * pace, 4, 2.7),
          makeLane(3, "network", "ssh", -1, 1.38 * pace, 4, 2.5),
          makeLane(4, "network", "container", 1, 0.92 * pace, 4, 2.9),
          makeLane(6, "process", "service", -1, 1.48 * pace, 4, 1.65),
          makeLane(7, "process", "package", 1, 1.18 * pace, 4, 1.85),
          makeLane(8, "process", "window", -1, 1.72 * pace, 3, 2.15),
          makeLane(9, "process", "service", 1, 1.34 * pace, 4, 1.6),
          makeLane(10, "process", stage >= 2 ? "window" : "package", -1, 1.58 * pace, 4, 1.8)
        ]
        ports = [
          { x: 1, bound: false }, { x: 4, bound: false }, { x: 7, bound: false },
          { x: 10, bound: false }, { x: 13, bound: false }
        ]
        ttlPickup = { x: 2 + Math.floor(Math.random() * 12), y: 5, active: true }
        ttl = Math.max(28, 46 - (stage - 1) * 2)
        resetCourier()
        statusMessage = zoneName + " ROUTE TABLE LOADED"
        worldCanvas.requestPaint()
      }

      function resetCourier() {
        playerX = 7
        playerY = 11
        playerVisualX = playerX
        playerVisualY = playerY
        leftHeld = rightHeld = upHeld = downHeld = false
        intentX = intentY = 0
        lastHopAt = -10000
      }

      function startRun() {
        score = 0
        stage = 1
        lives = 3
        deliveries = 0
        buildStage()
        mode = "stageintro"
        transitionLife = 1.1
        shell.play(stageSound)
      }

      function setIntent(dx, dy) {
        intentX = dx
        intentY = dy
        requestHop(dx, dy)
      }

      function refreshIntent() {
        if (leftHeld) { intentX = -1; intentY = 0 }
        else if (rightHeld) { intentX = 1; intentY = 0 }
        else if (upHeld) { intentX = 0; intentY = -1 }
        else if (downHeld) { intentX = 0; intentY = 1 }
        else { intentX = 0; intentY = 0 }
      }

      function requestHop(dx, dy) {
        if (mode !== "playing") return
        var now = Date.now()
        if (now - lastHopAt < 125) return
        if (hop(dx, dy)) lastHopAt = now
      }

      function hop(dx, dy) {
        var nextX = Math.max(0, Math.min(columns - 1, playerX + dx))
        var nextY = Math.max(0, Math.min(rows - 1, playerY + dy))
        if (nextX === playerX && nextY === playerY) return false
        if (nextY === 0) return bindPort(nextX)
        playerX = nextX
        playerY = nextY
        if (dy < 0) score += 10 + stage * 2
        shell.play(hopSound)
        collectTtl()
        checkSafety()
        worldCanvas.requestPaint()
        return true
      }

      function bindPort(x) {
        var best = -1
        var distance = 99
        for (var i = 0; i < ports.length; i++) {
          var gap = Math.abs(ports[i].x - x)
          if (!ports[i].bound && gap < distance) { best = i; distance = gap }
        }
        if (best < 0 || distance > 0.72) {
          statusMessage = "NO OPEN SOCKET // ROUTE REJECTED"
          shell.play(dropSound)
          return false
        }
        var updated = ports.slice(0)
        updated[best] = { x: updated[best].x, bound: true }
        ports = updated
        deliveries += 1
        score += 750 + stage * 150 + Math.floor(ttl * 12)
        ttl = Math.min(55, ttl + 7)
        playerX = updated[best].x
        playerY = 0
        mode = "binding"
        transitionLife = 0.72
        statusMessage = "PORT " + (best + 1) + " BOUND // ROUTE ADDED"
        shell.play(bindSound)
        return true
      }

      function collectTtl() {
        if (!ttlPickup.active || playerY !== ttlPickup.y || Math.abs(playerX - ttlPickup.x) > 0.68) return
        ttlPickup = { x: ttlPickup.x, y: ttlPickup.y, active: false }
        ttl = Math.min(55, ttl + 9)
        score += 300
        statusMessage = "TTL REFRESHED +9"
        shell.play(ttlSound)
      }

      function itemOverlap(item, x, margin) {
        return Math.abs(item.x - x) <= item.width / 2 + margin
      }

      function ridingItem(targetLane) {
        if (!targetLane) return null
        for (var i = 0; i < targetLane.items.length; i++)
          if (itemOverlap(targetLane.items[i], playerX, -0.12)) return targetLane.items[i]
        return null
      }

      function checkSafety() {
        if (mode !== "playing") return
        var current = lane(playerY)
        if (!current) return
        if (current.type === "network") {
          if (!ridingItem(current)) dropPacket("NO CARRIER // PACKET LOST")
        } else {
          for (var i = 0; i < current.items.length; i++) {
            if (itemOverlap(current.items[i], playerX, 0.12)) {
              dropPacket("PROCESS COLLISION // PACKET DROPPED")
              return
            }
          }
        }
      }

      function dropPacket(reason) {
        if (mode !== "playing") return
        lives -= 1
        mode = "dropping"
        transitionLife = 0.85
        statusMessage = reason
        leftHeld = rightHeld = upHeld = downHeld = false
        shell.play(dropSound)
      }

      function resolveDrop() {
        if (lives <= 0) finishRun()
        else {
          resetCourier()
          mode = "stageintro"
          transitionLife = 0.65
        }
      }

      function finishBinding() {
        var complete = true
        for (var i = 0; i < ports.length; i++) if (!ports[i].bound) complete = false
        if (complete) {
          score += stage * 1000
          mode = "stageclear"
          transitionLife = 2.0
          shell.play(stageSound)
        } else {
          resetCourier()
          mode = "playing"
        }
      }

      function advanceStage() {
        stage += 1
        buildStage()
        mode = "stageintro"
        transitionLife = 1.0
        shell.play(stageSound)
      }

      function finishRun() {
        leftHeld = rightHeld = upHeld = downHeld = false
        if (arcadeData.qualifies(score)) {
          initialsInput = arcadeData.defaultInitials
          initialsPristine = true
          mode = "initials"
        } else {
          arcadeData.recordScore({ score: score, initials: arcadeData.defaultInitials || "---",
                                   difficulty: "lan", stage: stage, ports: deliveries, ttl: ttl })
          mode = "gameover"
        }
      }

      function submitInitials() {
        var initials = arcadeData.cleanInitials(initialsInput)
        if (initials) arcadeData.patchConfig({ initials: initials })
        arcadeData.recordScore({ score: score, initials: initials || "---",
                                 difficulty: "lan", stage: stage, ports: deliveries, ttl: ttl })
        modeBeforeScores = "gameover"
        mode = "scores"
      }

      function openScores() {
        modeBeforeScores = mode
        mode = "scores"
      }

      function tickWorld(dt) {
        if (mode !== "playing") return
        ttl = Math.max(0, ttl - dt)
        if (ttl <= 0) { dropPacket("TTL EXPIRED // PACKET DROPPED"); return }

        var currentLane = lane(playerY)
        var carrier = currentLane && currentLane.type === "network" ? ridingItem(currentLane) : null
        var movedLanes = []
        for (var l = 0; l < lanes.length; l++) {
          var source = lanes[l]
          var movedItems = []
          var delta = source.direction * source.speed * dt
          for (var i = 0; i < source.items.length; i++) {
            var item = source.items[i]
            var x = item.x + delta
            if (source.direction > 0 && x - item.width / 2 > columns + 1) x = -item.width / 2 - 1
            else if (source.direction < 0 && x + item.width / 2 < -1) x = columns + item.width / 2 + 1
            movedItems.push({ x: x, width: item.width })
          }
          movedLanes.push({ row: source.row, type: source.type, kind: source.kind,
                            direction: source.direction, speed: source.speed, items: movedItems })
          if (carrier && source.row === playerY) {
            playerX += delta
            playerVisualX += delta
          }
        }
        lanes = movedLanes
        if (playerX < -0.35 || playerX > columns - 0.65) dropPacket("ROUTE OVERFLOW // PACKET DROPPED")
        else checkSafety()
      }

      Keys.onPressed: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (mode === "initials") {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) submitInitials()
          else if (event.key === Qt.Key_Backspace) {
            initialsInput = initialsPristine ? "" : initialsInput.slice(0, -1)
            initialsPristine = false
          } else {
            var typed = arcadeData.cleanInitials(event.text)
            if (typed && initialsInput.length < 3) {
              if (initialsPristine) initialsInput = ""
              initialsPristine = false
              initialsInput = (initialsInput + typed).slice(0, 3)
            }
          }
          event.accepted = true
          return
        }
        if (mode === "scores") {
          if (event.key === Qt.Key_H || event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            mode = modeBeforeScores === "scores" ? "attract" : modeBeforeScores
          event.accepted = true
          return
        }
        if (mode === "attract" || mode === "gameover") {
          if (event.key === Qt.Key_H) openScores()
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) startRun()
          else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
          event.accepted = true
          return
        }
        if (mode === "paused") {
          if (event.key === Qt.Key_P) mode = "playing"
          event.accepted = true
          return
        }
        if (mode !== "playing") { event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) { leftHeld = true; setIntent(-1, 0) }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) { rightHeld = true; setIntent(1, 0) }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) { upHeld = true; setIntent(0, -1) }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) { downHeld = true; setIntent(0, 1) }
        else if (event.key === Qt.Key_P) mode = "paused"
        else if (event.key === Qt.Key_H) openScores()
        else if (event.key === Qt.Key_R) startRun()
        else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
        event.accepted = true
      }

      Keys.onReleased: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) { leftHeld = false; refreshIntent() }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) { rightHeld = false; refreshIntent() }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) { upHeld = false; refreshIntent() }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) { downHeld = false; refreshIntent() }
        event.accepted = true
      }

      Timer {
        interval: 165
        repeat: true
        running: game.mode === "playing" && (game.leftHeld || game.rightHeld || game.upHeld || game.downHeld)
        onTriggered: if (game.intentX !== 0 || game.intentY !== 0) game.requestHop(game.intentX, game.intentY)
      }

      Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: {
          game.animationTime += 0.016
          game.playerVisualX += (game.playerX - game.playerVisualX) * 0.25
          game.playerVisualY += (game.playerY - game.playerVisualY) * 0.25
          game.tickWorld(0.016)
          if (game.mode === "binding" || game.mode === "dropping" || game.mode === "stageclear" || game.mode === "stageintro") {
            game.transitionLife = Math.max(0, game.transitionLife - 0.016)
            if (game.transitionLife <= 0) {
              if (game.mode === "binding") game.finishBinding()
              else if (game.mode === "dropping") game.resolveDrop()
              else if (game.mode === "stageclear") game.advanceStage()
              else game.mode = "playing"
            }
          }
          worldCanvas.requestPaint()
        }
      }

      Rectangle {
        anchors.fill: parent
        color: theme.background

        Rectangle {
          id: hud
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 84
          color: theme.surface
          border.color: theme.muted
          border.width: 1
          Row {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            Column {
              width: parent.width * 0.42
              anchors.verticalCenter: parent.verticalCenter
              Text { text: "OMACADE // " + shell.cabinet.shortTitle; color: theme.accent; font.pixelSize: 19; font.bold: true; font.letterSpacing: 1.4 }
              Text { text: game.zoneName + "/ROUTE/STAGE-" + ("0" + game.stage).slice(-2); color: theme.green; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
            }
            Repeater {
              model: [
                { label: "SCORE", value: game.score }, { label: "TTL", value: Math.ceil(game.ttl) },
                { label: "LIVES", value: game.lives }, { label: "PORTS", value: game.ports.filter(function(port) { return port.bound }).length + "/5" }
              ]
              delegate: Column {
                width: (parent.width * 0.58) / 4
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.label; color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                Text { text: modelData.value; color: modelData.label === "TTL" && game.ttl < 10 ? theme.red : theme.foreground; font.pixelSize: 18; font.family: "monospace"; font.bold: true }
              }
            }
          }
        }

        Item {
          id: playfield
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: hud.bottom
          anchors.bottom: footer.top
          anchors.margins: 12
          clip: true

          Canvas {
            id: worldCanvas
            anchors.fill: parent
            onImageLoaded: requestPaint()
            onPaint: {
              var context = getContext("2d")
              context.reset()
              context.fillStyle = theme.background
              context.fillRect(0, 0, width, height)

              for (var row = 0; row < game.rows; row++) {
                var y = row * game.cellHeight
                context.fillStyle = row <= 1 ? theme.surfaceRaised
                                  : row <= 4 ? theme.background
                                  : row === 5 || row === 11 ? theme.surface
                                  : theme.background
                context.fillRect(0, y, width, game.cellHeight)
                context.globalAlpha = row <= 1 ? 0.11 : row <= 4 ? 0.09 : row >= 6 && row <= 10 ? 0.07 : 0.04
                context.fillStyle = row <= 1 ? theme.green : row <= 4 ? theme.accent : row >= 6 && row <= 10 ? theme.red : theme.muted
                context.fillRect(0, y, width, game.cellHeight)
                context.globalAlpha = 0.18
                context.strokeStyle = theme.muted
                context.beginPath()
                context.moveTo(0, y + game.cellHeight)
                context.lineTo(width, y + game.cellHeight)
                context.stroke()
                context.globalAlpha = 1
              }

              for (var port = 0; port < game.ports.length; port++) {
                var socket = game.ports[port]
                game.drawSprite(context, socket.bound ? 1 : 0, 3,
                                (socket.x + 0.5) * game.cellWidth, game.cellHeight * 0.5,
                                game.cellWidth * 1.55, game.cellHeight * 1.38, 1, false)
              }

              for (var l = 0; l < game.lanes.length; l++) {
                var traffic = game.lanes[l]
                var spriteRow = traffic.type === "process" ? 1 : 2
                var spriteColumn = traffic.kind === "service" || traffic.kind === "pipe" ? 0
                                 : traffic.kind === "package" || traffic.kind === "container" ? 1
                                 : traffic.kind === "window" || traffic.kind === "ssh" ? 2 : 3
                for (var item = 0; item < traffic.items.length; item++) {
                  var vehicle = traffic.items[item]
                  game.drawSprite(context, spriteColumn, spriteRow,
                                  (vehicle.x + 0.5) * game.cellWidth, (traffic.row + 0.5) * game.cellHeight,
                                  game.cellWidth * vehicle.width, game.cellHeight * 1.18,
                                  1, traffic.direction < 0)
                }
              }

              if (game.ttlPickup.active)
                game.drawSprite(context, 2, 3,
                                (game.ttlPickup.x + 0.5) * game.cellWidth, (game.ttlPickup.y + 0.5) * game.cellHeight,
                                game.cellWidth * 1.15, game.cellHeight * 1.15, 1, false)

              var px = (game.playerVisualX + 0.5) * game.cellWidth
              var py = (game.playerVisualY + 0.5) * game.cellHeight
              var courierFrame = game.mode === "binding" ? 2 : game.mode === "dropping" ? 3 : Math.floor(game.animationTime * 5) % 2
              var courierScale = game.mode === "dropping" ? 1.9 : 1.38
              game.drawSprite(context, courierFrame, 0, px, py,
                              game.cellWidth * courierScale, game.cellHeight * courierScale,
                              game.mode === "dropping" ? Math.max(0.25, game.transitionLife / 0.85) : 1, false)
            }
          }

          Rectangle {
            visible: game.mode === "playing" && game.statusMessage.length > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 9
            width: Math.min(parent.width - 18, routeStatus.implicitWidth + 22)
            height: 29
            radius: 5
            color: theme.surface
            border.color: theme.muted
            opacity: 0.9
            Text { id: routeStatus; anchors.centerIn: parent; text: game.statusMessage; color: theme.foreground; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
          }

          Rectangle {
            visible: game.mode === "attract"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 620)
            height: Math.min(parent.height - 34, 450)
            radius: 12
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              width: parent.width - 54
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "OMACADE // CABINET " + shell.cabinet.number; color: theme.accent; font.pixelSize: 14; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.displayTitle; color: theme.foreground; font.pixelSize: 37; font.bold: true; font.letterSpacing: 3 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.tagline.toUpperCase(); color: theme.green; font.pixelSize: 13; font.family: "monospace" }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "ROUTE A COURIER PACKET ACROSS HOSTILE PROCESS LANES.\nRIDE DATA PIPES AND CONTAINERS. BIND ALL FIVE ROOT PORTS."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.32 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SERVICE / PACMAN / HYPR TRAFFIC  ·  TTL IS TICKING"; color: theme.orange; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "← ↑ ↓ →  HOP / ROUTE"; color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "BEST " + arcadeData.bestScore + "   ·   FURTHEST " + arcadeData.highestStage; color: theme.yellow; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PRESS ENTER TO SEND"; color: theme.accent; font.pixelSize: 18; font.family: "monospace"; font.bold: true
                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.35; duration: 620 }
                  NumberAnimation { to: 1; duration: 620 }
                }
              }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "H RECORDS    Q QUIT"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.mode === "paused" || game.mode === "stageintro" || game.mode === "binding" || game.mode === "dropping" || game.mode === "stageclear" || game.mode === "gameover"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 520)
            height: 155
            radius: 10
            color: theme.surface
            border.color: game.mode === "dropping" || game.mode === "gameover" ? theme.red : game.mode === "binding" || game.mode === "stageclear" ? theme.green : theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 11
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "ROUTE SUSPENDED" : game.mode === "stageintro" ? "ROUTING " + game.zoneName : game.mode === "binding" ? "PORT BOUND" : game.mode === "dropping" ? "PACKET DROPPED" : game.mode === "stageclear" ? "ALL PORTS BOUND" : "CONNECTION CLOSED"; color: game.mode === "dropping" || game.mode === "gameover" ? theme.red : game.mode === "binding" || game.mode === "stageclear" ? theme.green : theme.accent; font.pixelSize: 24; font.bold: true; font.letterSpacing: 1.5 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "gameover" ? "SCORE " + game.score + "  ·  ENTER TO RESEND" : game.mode === "paused" ? "P TO RESUME" : game.statusMessage; color: theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            visible: game.mode === "initials"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 500)
            height: 235
            radius: 10
            color: theme.surface
            border.color: theme.yellow
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ROUTE RECORD"; color: theme.yellow; font.pixelSize: 25; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SCORE " + game.score + "  ·  PORTS " + game.deliveries; color: theme.foreground; font.pixelSize: 14; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: (game.initialsInput + "___").slice(0, 3).split("").join(" "); color: theme.accent; font.pixelSize: 40; font.family: "monospace"; font.bold: true; font.letterSpacing: 8 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "TYPE 3 INITIALS  ·  ENTER TO COMMIT"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.mode === "scores"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 620)
            height: Math.min(parent.height - 30, 465)
            radius: 10
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.fill: parent
              anchors.margins: 24
              spacing: 8
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PACKET//HOP // TOP TEN"; color: theme.accent; font.pixelSize: 23; font.bold: true }
              Text { text: " #    ROUTER      SCORE        STAGE"; color: theme.muted; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Repeater {
                model: 10
                delegate: Text {
                  property var row: index < arcadeData.scoreRows.length ? arcadeData.scoreRows[index] : null
                  width: parent.width
                  text: {
                    var rank = index < 9 ? " " + String(index + 1) : String(index + 1)
                    var router = row ? (arcadeData.cleanInitials(row.initials) || "---") : "---"
                    var points = row ? ("       " + String(Math.round(Number(row.score || 0)))).slice(-7) : "      -"
                    var route = row ? String(Math.max(1, Number(row.stage || 1))) : "-"
                    return rank + "    " + (router + "        ").slice(0, 8) + "  " + points + "       " + route
                  }
                  color: row && index === 0 ? theme.yellow : row ? theme.foreground : theme.muted
                  font.pixelSize: 15
                  font.family: "monospace"
                  font.bold: row && index === 0
                }
              }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "H / ENTER / ESC  CLOSE"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.tooSmall
            anchors.fill: parent
            color: theme.background
            z: 30
            Column {
              anchors.centerIn: parent
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ROUTE GRID TOO SMALL"; color: theme.yellow; font.pixelSize: 22; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Enlarge the cabinet for a 620 × 430 playfield."; color: theme.foreground; font.pixelSize: 13 }
            }
          }
        }

        Rectangle {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 46
          color: theme.surface
          border.color: theme.muted
          border.width: 1
          Text { anchors.centerIn: parent; text: "← ↑ ↓ → HOP / ROUTE    P PAUSE    H RECORDS    R RESEND    Q QUIT"; color: theme.muted; font.pixelSize: parent.width < 820 ? 10 : 12; font.family: "monospace"; font.bold: true }
        }
      }
    }
  }
}
