import QtQuick
import QtMultimedia
import Quickshell
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("rootbound")
  ArcadeTheme { id: theme }
  ArcadeData { id: arcadeData; cabinetId: shell.cabinet.scoreKey }

  SoundEffect { id: moveSound; source: Qt.resolvedUrl("assets/sfx/rotate.wav"); volume: 0.24 }
  SoundEffect { id: purgeSound; source: Qt.resolvedUrl("assets/sfx/start.wav"); volume: 0.36 }
  SoundEffect { id: hitSound; source: Qt.resolvedUrl("assets/sfx/crash.wav"); volume: 0.46 }
  SoundEffect { id: clearSound; source: Qt.resolvedUrl("assets/sfx/stage-clear.wav"); volume: 0.48 }

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
    implicitHeight: 720
    minimumSize: Qt.size(760, 560)
    onVisibleChanged: if (!visible) Qt.quit()

    FocusScope {
      id: game
      anchors.fill: parent
      focus: true

      readonly property int columns: 32
      readonly property int rows: 22
      property var soil: []
      property var enemies: []
      property var shards: []
      property int playerX: 16
      property int playerY: 1
      property real playerVisualX: 16
      property real playerVisualY: 1
      property int facingX: 0
      property int facingY: 1
      property int score: 0
      property int stage: 1
      property int lives: 3
      property int packages: 0
      property string mode: "attract"
      property string modeBeforeScores: "attract"
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property int moveInterval: 175
      property real pulseCooldown: 0
      property real pulseLife: 0
      property var pulsePath: []
      property string initialsInput: ""
      property bool initialsPristine: true
      property string statusMessage: ""
      property real animationTime: 0
      readonly property bool tooSmall: playfield.width < 640 || playfield.height < 390
      readonly property real cellWidth: playfield.width / columns
      readonly property real cellHeight: playfield.height / rows

      Component.onCompleted: {
        generateLevel()
        mode = "attract"
        forceActiveFocus()
      }

      function index(x, y) { return y * columns + x }
      function inside(x, y) { return x >= 0 && x < columns && y >= 0 && y < rows }
      function isSoil(x, y) { return !inside(x, y) || soil[index(x, y)] === true }

      function setSoil(x, y, value) {
        if (!inside(x, y)) return
        var next = soil.slice(0)
        next[index(x, y)] = value
        soil = next
      }

      function carveCell(buffer, x, y) {
        if (inside(x, y)) buffer[index(x, y)] = false
      }

      function openCells(buffer) {
        var result = []
        for (var y = 3; y < rows - 1; y++)
          for (var x = 1; x < columns - 1; x++)
            if (!buffer[index(x, y)]) result.push({ x: x, y: y })
        return result
      }

      function generateLevel() {
        var generated = []
        for (var i = 0; i < columns * rows; i++) generated.push(true)

        var startX = Math.floor(columns / 2)
        for (var top = 0; top <= 4; top++) carveCell(generated, startX, top)

        var levels = [4, 9, 14, 19]
        for (var row = 0; row < levels.length; row++) {
          var inset = 2 + Math.floor(Math.random() * 4)
          for (var x = inset; x < columns - inset; x++) carveCell(generated, x, levels[row])
        }
        var shafts = [4, 11, 20, 27]
        for (var shaft = 0; shaft < shafts.length; shaft++) {
          var from = 3 + Math.floor(Math.random() * 3)
          var to = rows - 2 - Math.floor(Math.random() * 2)
          for (var y = from; y <= to; y++) carveCell(generated, shafts[shaft], y)
        }

        // Offset branches make each filesystem layout less grid-perfect.
        for (var branch = 0; branch < 7 + Math.min(stage, 5); branch++) {
          var branchY = 5 + Math.floor(Math.random() * (rows - 7))
          var branchX = 2 + Math.floor(Math.random() * (columns - 7))
          var length = 3 + Math.floor(Math.random() * 6)
          for (var step = 0; step < length; step++) carveCell(generated, branchX + step, branchY)
        }

        soil = generated
        playerX = startX
        playerY = 1
        playerVisualX = playerX
        playerVisualY = playerY
        facingX = 0
        facingY = 1

        var candidates = openCells(generated)
        var spawned = []
        var enemyCount = Math.min(2 + stage, 7)
        for (var enemy = 0; enemy < enemyCount && candidates.length; enemy++) {
          var choice = candidates.splice(Math.floor(Math.random() * candidates.length), 1)[0]
          if (Math.abs(choice.x - playerX) + Math.abs(choice.y - playerY) < 10) { enemy--; continue }
          spawned.push({ x: choice.x, y: choice.y, phase: enemy >= 3 && stage >= 3, blink: Math.random() * 6.28 })
        }
        enemies = spawned

        var hidden = []
        var shardCount = Math.min(4 + stage, 10)
        while (hidden.length < shardCount) {
          var shardX = 2 + Math.floor(Math.random() * (columns - 4))
          var shardY = 5 + Math.floor(Math.random() * (rows - 7))
          var duplicate = false
          for (var check = 0; check < hidden.length; check++)
            if (hidden[check].x === shardX && hidden[check].y === shardY) duplicate = true
          if (!duplicate && generated[index(shardX, shardY)]) hidden.push({ x: shardX, y: shardY })
        }
        shards = hidden
        pulsePath = []
        pulseLife = 0
        statusMessage = "DEPTH " + stage + " MOUNTED"
        worldCanvas.requestPaint()
      }

      function startRun() {
        score = 0
        stage = 1
        lives = 3
        packages = 0
        mode = "playing"
        generateLevel()
        shell.play(purgeSound)
      }

      function movePlayer(dx, dy) {
        if (mode !== "playing") return
        var nextX = playerX + dx
        var nextY = playerY + dy
        if (!inside(nextX, nextY) || nextY === 0) return
        facingX = dx
        facingY = dy
        var digging = isSoil(nextX, nextY)
        moveInterval = digging ? 235 : 175
        if (digging) {
          setSoil(nextX, nextY, false)
          score += 10 + stage
        }
        playerX = nextX
        playerY = nextY

        var remaining = []
        for (var i = 0; i < shards.length; i++) {
          if (shards[i].x === playerX && shards[i].y === playerY) {
            packages += 1
            score += 180 + stage * 20
            shell.play(moveSound)
          } else remaining.push(shards[i])
        }
        shards = remaining
        checkCollision()
        worldCanvas.requestPaint()
      }

      function purge() {
        if (mode !== "playing" || pulseCooldown > 0) return
        pulseCooldown = 0.72
        pulseLife = 0.18
        var path = []
        for (var distance = 1; distance <= 3; distance++) {
          var x = playerX + facingX * distance
          var y = playerY + facingY * distance
          if (!inside(x, y) || isSoil(x, y)) break
          path.push({ x: x, y: y })
        }
        pulsePath = path
        shell.play(purgeSound)

        var survivors = []
        var purged = 0
        for (var i = 0; i < enemies.length; i++) {
          var hit = false
          for (var p = 0; p < path.length; p++)
            if (enemies[i].x === path[p].x && enemies[i].y === path[p].y) hit = true
          if (hit) purged += 1
          else survivors.push(enemies[i])
        }
        enemies = survivors
        if (purged) {
          score += purged * (450 + stage * 75)
          statusMessage = "PURGED " + purged + " ROGUE DAEMON" + (purged > 1 ? "S" : "")
          if (!enemies.length) {
            mode = "stageclear"
            score += stage * 500
            shell.play(clearSound)
          }
        }
        worldCanvas.requestPaint()
      }

      function availableMoves(enemy) {
        var options = []
        var directions = [{x:-1,y:0},{x:1,y:0},{x:0,y:-1},{x:0,y:1}]
        for (var i = 0; i < directions.length; i++) {
          var x = enemy.x + directions[i].x
          var y = enemy.y + directions[i].y
          if (!inside(x, y) || y === 0) continue
          if (!isSoil(x, y) || (enemy.phase && Math.random() < 0.16))
            options.push({ x: x, y: y })
        }
        return options
      }

      function moveEnemies() {
        if (mode !== "playing") return
        var moved = []
        for (var i = 0; i < enemies.length; i++) {
          var enemy = enemies[i]
          var options = availableMoves(enemy)
          if (!options.length) { moved.push(enemy); continue }
          options.sort(function(a, b) {
            var distanceA = Math.abs(a.x - playerX) + Math.abs(a.y - playerY)
            var distanceB = Math.abs(b.x - playerX) + Math.abs(b.y - playerY)
            return distanceA - distanceB
          })
          var choice = Math.random() < 0.76 ? options[0] : options[Math.floor(Math.random() * options.length)]
          moved.push({ x: choice.x, y: choice.y, phase: enemy.phase, blink: enemy.blink })
        }
        enemies = moved
        checkCollision()
        worldCanvas.requestPaint()
      }

      function checkCollision() {
        if (mode !== "playing") return
        for (var i = 0; i < enemies.length; i++) {
          if (enemies[i].x === playerX && enemies[i].y === playerY) {
            lives -= 1
            shell.play(hitSound)
            statusMessage = "SEGFAULT // LIFE LOST"
            if (lives <= 0) finishRun()
            else generateLevel()
            return
          }
        }
      }

      function finishRun() {
        leftHeld = rightHeld = upHeld = downHeld = false
        if (arcadeData.qualifies(score)) {
          initialsInput = arcadeData.defaultInitials
          initialsPristine = true
          mode = "initials"
        } else {
          arcadeData.recordScore({ score: score, initials: arcadeData.defaultInitials || "---",
                                   difficulty: "root", stage: stage, packages: packages })
          mode = "gameover"
        }
      }

      function openScores() {
        modeBeforeScores = mode
        mode = "scores"
      }

      function submitInitials() {
        var initials = arcadeData.cleanInitials(initialsInput)
        if (initials) arcadeData.patchConfig({ initials: initials })
        arcadeData.recordScore({ score: score, initials: initials || "---",
                                 difficulty: "root", stage: stage, packages: packages })
        modeBeforeScores = "gameover"
        mode = "scores"
      }

      function advanceStage() {
        stage += 1
        mode = "playing"
        generateLevel()
      }

      Keys.onPressed: function(event) {
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
        if (mode === "stageclear") {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) advanceStage()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) { leftHeld = true; movePlayer(-1, 0) }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) { rightHeld = true; movePlayer(1, 0) }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) { upHeld = true; movePlayer(0, -1) }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) { downHeld = true; movePlayer(0, 1) }
        else if (event.key === Qt.Key_Space) purge()
        else if (event.key === Qt.Key_P) mode = mode === "paused" ? "playing" : "paused"
        else if (event.key === Qt.Key_H) openScores()
        else if (event.key === Qt.Key_R) startRun()
        else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
        event.accepted = true
      }

      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) leftHeld = false
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) rightHeld = false
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) upHeld = false
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) downHeld = false
        event.accepted = true
      }

      Timer {
        interval: game.moveInterval
        repeat: true
        running: game.mode === "playing" && (game.leftHeld || game.rightHeld || game.upHeld || game.downHeld)
        onTriggered: {
          if (game.leftHeld) game.movePlayer(-1, 0)
          else if (game.rightHeld) game.movePlayer(1, 0)
          else if (game.upHeld) game.movePlayer(0, -1)
          else if (game.downHeld) game.movePlayer(0, 1)
        }
      }

      Timer {
        interval: Math.max(115, 315 - game.stage * 18)
        repeat: true
        running: game.mode === "playing"
        onTriggered: game.moveEnemies()
      }

      Timer {
        interval: 33
        repeat: true
        running: true
        onTriggered: {
          game.animationTime += 0.033
          var movementEase = 0.34
          game.playerVisualX += (game.playerX - game.playerVisualX) * movementEase
          game.playerVisualY += (game.playerY - game.playerVisualY) * movementEase
          game.pulseCooldown = Math.max(0, game.pulseCooldown - 0.033)
          game.pulseLife = Math.max(0, game.pulseLife - 0.033)
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
          height: 82
          color: theme.surface
          border.color: theme.muted
          border.width: 1
          Row {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            Column {
              width: parent.width * 0.45
              anchors.verticalCenter: parent.verticalCenter
              Text { text: "OMACADE // " + shell.cabinet.shortTitle; color: theme.accent; font.pixelSize: 19; font.bold: true; font.letterSpacing: 1.5 }
              Text { text: "/VAR/DEEP/LEVEL-" + ("0" + String(game.stage)).slice(-2); color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
            }
            Repeater {
              model: [
                { label: "SCORE", value: game.score },
                { label: "LIVES", value: game.lives },
                { label: "PKGS", value: game.packages },
                { label: "DAEMONS", value: game.enemies.length }
              ]
              delegate: Column {
                width: (parent.width * 0.55) / 4
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.label; color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                Text { text: modelData.value; color: theme.foreground; font.pixelSize: 19; font.family: "monospace"; font.bold: true }
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
            onPaint: {
              var context = getContext("2d")
              context.reset()
              context.fillStyle = theme.background
              context.fillRect(0, 0, width, height)

              for (var y = 0; y < game.rows; y++) {
                for (var x = 0; x < game.columns; x++) {
                  var cellX = x * game.cellWidth
                  var cellY = y * game.cellHeight
                  if (game.soil[game.index(x, y)]) {
                    var layer = y < 6 ? theme.surfaceRaised : y < 13 ? theme.surface : theme.background
                    context.fillStyle = layer
                    context.fillRect(cellX, cellY, game.cellWidth + 0.5, game.cellHeight + 0.5)
                    context.globalAlpha = 0.18
                    context.strokeStyle = y % 2 === 0 ? theme.muted : theme.accent
                    context.strokeRect(cellX + 1, cellY + 1, game.cellWidth - 2, game.cellHeight - 2)
                    context.globalAlpha = 1
                  } else {
                    context.fillStyle = theme.background
                    context.fillRect(cellX, cellY, game.cellWidth + 1, game.cellHeight + 1)
                  }
                }
              }

              for (var shard = 0; shard < game.shards.length; shard++) {
                var packageNode = game.shards[shard]
                var px = (packageNode.x + 0.5) * game.cellWidth
                var py = (packageNode.y + 0.5) * game.cellHeight
                context.globalAlpha = game.isSoil(packageNode.x, packageNode.y) ? 0.38 : 1
                context.fillStyle = theme.yellow
                context.beginPath()
                context.moveTo(px, py - game.cellHeight * 0.27)
                context.lineTo(px + game.cellWidth * 0.27, py)
                context.lineTo(px, py + game.cellHeight * 0.27)
                context.lineTo(px - game.cellWidth * 0.27, py)
                context.closePath()
                context.fill()
              }
              context.globalAlpha = 1

              if (game.pulseLife > 0 && game.pulsePath.length) {
                context.globalAlpha = game.pulseLife / 0.18
                context.strokeStyle = theme.accent
                context.lineWidth = 4
                context.beginPath()
                context.moveTo((game.playerX + 0.5) * game.cellWidth, (game.playerY + 0.5) * game.cellHeight)
                var end = game.pulsePath[game.pulsePath.length - 1]
                context.lineTo((end.x + 0.5) * game.cellWidth, (end.y + 0.5) * game.cellHeight)
                context.stroke()
                context.globalAlpha = 1
              }

              for (var enemy = 0; enemy < game.enemies.length; enemy++) {
                var daemon = game.enemies[enemy]
                var ex = (daemon.x + 0.5) * game.cellWidth
                var ey = (daemon.y + 0.5) * game.cellHeight
                var radius = Math.min(game.cellWidth, game.cellHeight) * 0.35
                context.globalAlpha = daemon.phase ? 0.52 + Math.sin(game.animationTime * 5 + daemon.blink) * 0.24 : 1
                context.fillStyle = daemon.phase ? theme.orange : theme.red
                context.beginPath()
                context.moveTo(ex - radius, ey - radius * 0.55)
                context.lineTo(ex - radius * 0.55, ey - radius * 1.15)
                context.lineTo(ex - radius * 0.15, ey - radius * 0.62)
                context.lineTo(ex + radius * 0.15, ey - radius * 0.62)
                context.lineTo(ex + radius * 0.55, ey - radius * 1.15)
                context.lineTo(ex + radius, ey - radius * 0.55)
                context.lineTo(ex + radius * 0.72, ey + radius)
                context.lineTo(ex - radius * 0.72, ey + radius)
                context.closePath()
                context.fill()
                context.fillStyle = theme.background
                context.fillRect(ex - radius * 0.48, ey - radius * 0.26, radius * 0.25, radius * 0.25)
                context.fillRect(ex + radius * 0.23, ey - radius * 0.26, radius * 0.25, radius * 0.25)
              }
              context.globalAlpha = 1

              var playerCenterX = (game.playerVisualX + 0.5) * game.cellWidth
              var playerCenterY = (game.playerVisualY + 0.5) * game.cellHeight
              var playerRadius = Math.min(game.cellWidth, game.cellHeight) * 0.38
              context.fillStyle = theme.accent
              context.fillRect(playerCenterX - playerRadius, playerCenterY - playerRadius,
                               playerRadius * 2, playerRadius * 2)
              context.fillStyle = theme.background
              context.fillRect(playerCenterX - playerRadius * 0.42, playerCenterY - playerRadius * 0.42,
                               playerRadius * 0.84, playerRadius * 0.84)
              context.fillStyle = theme.foreground
              context.beginPath()
              context.moveTo(playerCenterX + game.facingX * playerRadius * 1.45,
                             playerCenterY + game.facingY * playerRadius * 1.45)
              context.lineTo(playerCenterX - game.facingY * playerRadius * 0.42,
                             playerCenterY + game.facingX * playerRadius * 0.42)
              context.lineTo(playerCenterX + game.facingY * playerRadius * 0.42,
                             playerCenterY - game.facingX * playerRadius * 0.42)
              context.closePath()
              context.fill()
            }
          }

          Rectangle {
            visible: game.mode === "attract"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 600)
            height: Math.min(parent.height - 35, 430)
            radius: 12
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              width: parent.width - 54
              spacing: 13
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "OMACADE // CABINET " + shell.cabinet.number; color: theme.accent; font.pixelSize: 14; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.displayTitle; color: theme.foreground; font.pixelSize: 39; font.bold: true; font.letterSpacing: 4 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.tagline.toUpperCase(); color: theme.green; font.pixelSize: 13; font.family: "monospace" }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "CARVE THROUGH THE FILESYSTEM. RECOVER PACKAGE SHARDS.\nPURGE EVERY ROGUE DAEMON BEFORE IT FINDS ROOT."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.35 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "← ↑ ↓ →  DIG / MOVE    ·    SPACE  SUDO PURGE"; color: theme.muted; font.pixelSize: 12; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "BEST " + arcadeData.bestScore + "   ·   DEEPEST " + arcadeData.highestStage; color: theme.yellow; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "PRESS ENTER TO MOUNT"
                color: theme.accent
                font.pixelSize: 18
                font.family: "monospace"
                font.bold: true
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
            visible: game.mode === "paused" || game.mode === "stageclear" || game.mode === "gameover"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 500)
            height: 160
            radius: 10
            color: theme.surface
            border.color: game.mode === "stageclear" ? theme.green : game.mode === "paused" ? theme.accent : theme.red
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "PROCESS SUSPENDED" : game.mode === "stageclear" ? "DEPTH " + game.stage + " SANITIZED" : "KERNEL PANIC"; color: game.mode === "stageclear" ? theme.green : game.mode === "paused" ? theme.accent : theme.red; font.pixelSize: 23; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "P TO RESUME" : game.mode === "stageclear" ? "ENTER TO DESCEND" : "SCORE " + game.score + "  ·  ENTER TO REMOUNT"; color: theme.foreground; font.pixelSize: 13; font.family: "monospace" }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ROOT RECORD"; color: theme.yellow; font.pixelSize: 25; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SCORE " + game.score + "  ·  DEPTH " + game.stage; color: theme.foreground; font.pixelSize: 14; font.family: "monospace" }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ROOTBOUND // TOP TEN"; color: theme.accent; font.pixelSize: 23; font.bold: true }
              Text { text: " #    ROOT        SCORE        DEPTH"; color: theme.muted; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
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
                    var depth = row ? String(Math.max(1, Number(row.stage || 1))) : "-"
                    return rank + "    " + (pilot + "        ").slice(0, 8) + "  " + points + "       " + depth
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "TERMINAL GRID TOO SMALL"; color: theme.yellow; font.pixelSize: 22; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Enlarge the cabinet for a 640 × 390 playfield."; color: theme.foreground; font.pixelSize: 13 }
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
          Text {
            anchors.centerIn: parent
            text: "← ↑ ↓ → DIG / MOVE    SPACE SUDO PURGE    P PAUSE    H RECORDS    R REMOUNT    Q QUIT"
            color: theme.muted
            font.pixelSize: parent.width < 820 ? 10 : 12
            font.family: "monospace"
            font.bold: true
          }
        }
      }
    }
  }
}
