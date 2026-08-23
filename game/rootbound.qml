import QtQuick
import QtMultimedia
import Quickshell
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("rootbound")
  readonly property bool circuitMode: Quickshell.env("OMACADE_CIRCUIT") === "1"
  ArcadeTheme { id: theme }
  ArcadeData { id: arcadeData; cabinetId: shell.cabinet.scoreKey }

  SoundEffect { id: digSound; source: Qt.resolvedUrl("assets/sfx/rootbound-dig.wav"); volume: 0.18 }
  SoundEffect { id: packageSound; source: Qt.resolvedUrl("assets/sfx/rootbound-package.wav"); volume: 0.34 }
  SoundEffect { id: purgeSound; source: Qt.resolvedUrl("assets/sfx/rootbound-purge.wav"); volume: 0.30 }
  SoundEffect { id: hitSound; source: Qt.resolvedUrl("assets/sfx/rootbound-hit.wav"); volume: 0.46 }
  SoundEffect { id: clearSound; source: Qt.resolvedUrl("assets/sfx/rootbound-clear.wav"); volume: 0.42 }
  SoundEffect { id: bonusSound; source: Qt.resolvedUrl("assets/sfx/rootbound-bonus.wav"); volume: 0.42 }
  SoundEffect { id: mountSound; source: Qt.resolvedUrl("assets/sfx/rootbound-mount.wav"); volume: 0.32 }
  SoundEffect { id: hazardSound; source: Qt.resolvedUrl("assets/sfx/rootbound-hazard.wav"); volume: 0.22 }

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
      readonly property int zoneIndex: Math.min(3, Math.max(0, stage - 1))
      readonly property string zoneName: ["/HOME", "/VAR", "/TMP", "/ROOT"][zoneIndex]
      readonly property color zoneAccent: zoneIndex === 0 ? theme.green
                                         : zoneIndex === 1 ? theme.orange
                                         : zoneIndex === 2 ? theme.accent : theme.red
      readonly property url spriteAtlas: Qt.resolvedUrl("assets/rootbound-sprites.png")
      readonly property real spriteCell: 313.5
      property var soil: []
      property var enemies: []
      property var shards: []
      property var hazards: []
      property var unstableCells: []
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
      property int stagePackages: 0
      property int stagePurged: 0
      property int stageStartLives: 3
      property int objectiveTarget: 0
      property bool objectiveMet: false
      property int objectiveAward: 0
      property real stageElapsed: 0
      property real deathLife: 0
      property real stageClearLife: 0
      property real stageIntroLife: 0
      property string mode: "attract"
      property string modeBeforeScores: "attract"
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property bool purgeHeld: false
      property int moveIntentX: 0
      property int moveIntentY: 0
      property int pendingMoveX: 0
      property int pendingMoveY: 0
      property double pendingMoveUntil: 0
      property int moveInterval: 145
      property double lastMoveAt: -10000
      property real pulseCooldown: 0
      property real pulseLife: 0
      property var pulsePath: []
      property var scoreBursts: []
      property var purgeParticles: []
      property string initialsInput: ""
      property bool initialsPristine: true
      property string statusMessage: ""
      property real animationTime: 0
      readonly property bool tooSmall: playfield.width < 640 || playfield.height < 390
      readonly property real cellWidth: playfield.width / columns
      readonly property real cellHeight: playfield.height / rows
      readonly property string objectiveText: zoneIndex === 0 ? "RECOVER ALL " + objectiveTarget + " PACKAGES"
                                             : zoneIndex === 1 ? "RECOVER " + objectiveTarget + " PACKAGES"
                                             : zoneIndex === 2 ? "PURGE WITHIN 45 SECONDS"
                                             : "CLEAR WITHOUT A SEGFAULT"

      Component.onCompleted: {
        worldCanvas.loadImage(spriteAtlas)
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

      function daemonState(x, y, type, blink, capture, captureLife, hitFlash) {
        return {
          x: x, y: y, type: type, blink: blink,
          capture: capture || 0,
          captureLife: captureLife || 0,
          hitFlash: hitFlash || 0
        }
      }

      function drawSprite(context, column, row, centerX, centerY, drawWidth, drawHeight,
                          opacity, flipX, flipY) {
        if (!worldCanvas.isImageLoaded(spriteAtlas)) return false
        context.save()
        context.globalAlpha = opacity === undefined ? 1 : opacity
        context.translate(centerX, centerY)
        context.scale(flipX ? -1 : 1, flipY ? -1 : 1)
        context.drawImage(spriteAtlas,
                          column * spriteCell, row * spriteCell, spriteCell, spriteCell,
                          -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight)
        context.restore()
        return true
      }

      function generateLevel(resetStageState) {
        var generated = []
        for (var i = 0; i < columns * rows; i++) generated.push(true)

        var startX = Math.floor(columns / 2)
        for (var top = 0; top <= 4; top++) carveCell(generated, startX, top)

        var levels = zoneIndex === 0 ? [4, 9, 14, 19]
                   : zoneIndex === 1 ? [4, 8, 12, 16, 20]
                   : zoneIndex === 2 ? [5, 10, 15, 19]
                   : [5, 11, 16, 20]
        for (var row = 0; row < levels.length; row++) {
          var inset = 2 + Math.floor(Math.random() * 4)
          if (zoneIndex === 2) {
            // /tmp is fragmented into short-lived cache pockets.
            for (var pocket = 0; pocket < 3; pocket++) {
              var pocketX = 1 + Math.floor(Math.random() * (columns - 8))
              var pocketLength = 3 + Math.floor(Math.random() * 5)
              for (var px = pocketX; px < Math.min(columns - 1, pocketX + pocketLength); px++)
                carveCell(generated, px, levels[row])
            }
          } else {
            for (var x = inset; x < columns - inset; x++) carveCell(generated, x, levels[row])
          }
        }
        var shafts = zoneIndex === 0 ? [4, 11, 20, 27]
                   : zoneIndex === 1 ? [5, 9, 16, 23, 28]
                   : zoneIndex === 2 ? [3, 12, 21, 29]
                   : [5, 14, 24, 28]
        for (var shaft = 0; shaft < shafts.length; shaft++) {
          var from = 3 + Math.floor(Math.random() * 3)
          var to = rows - 2 - Math.floor(Math.random() * 2)
          for (var y = from; y <= to; y++) {
            var shaftX = shafts[shaft]
            if (zoneIndex === 3 && y % 4 === shaft % 4) shaftX += shaft % 2 ? -1 : 1
            carveCell(generated, shaftX, y)
          }
        }

        // Offset branches make each filesystem layout less grid-perfect.
        var branchCount = [7, 11, 15, 18][zoneIndex] + Math.min(stage, 5)
        for (var branch = 0; branch < branchCount; branch++) {
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
        lastMoveAt = -10000
        moveIntentX = 0
        moveIntentY = 0
        pendingMoveX = 0
        pendingMoveY = 0
        pendingMoveUntil = 0
        purgeHeld = false

        if (resetStageState !== false) {
          stagePackages = 0
          stagePurged = 0
          stageStartLives = lives
          stageElapsed = 0
          objectiveMet = false
          objectiveAward = 0
        }

        var candidates = openCells(generated)
        var spawned = []
        var enemyCount = Math.min(2 + stage, 7)
        for (var enemy = 0; enemy < enemyCount && candidates.length; enemy++) {
          var choice = candidates.splice(Math.floor(Math.random() * candidates.length), 1)[0]
          if (Math.abs(choice.x - playerX) + Math.abs(choice.y - playerY) < 10) { enemy--; continue }
          var rootkitQuota = zoneIndex === 0 ? 0 : zoneIndex === 1 ? 1 : zoneIndex === 2 ? 2 : Math.ceil(enemyCount / 2)
          var rootkit = enemy >= enemyCount - rootkitQuota
          spawned.push(daemonState(choice.x, choice.y, rootkit ? "rootkit" : "zombie",
                                    Math.random() * 6.28, 0, 0, 0))
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
        if (resetStageState !== false)
          objectiveTarget = zoneIndex === 0 ? shardCount : zoneIndex === 1 ? Math.min(3, shardCount) : 0
        setupHazards(generated)
        pulsePath = []
        pulseLife = 0
        scoreBursts = []
        purgeParticles = []
        statusMessage = zoneName + " // DEPTH " + stage + " MOUNTED"
        worldCanvas.requestPaint()
      }

      function objectiveProgress() {
        if (zoneIndex <= 1) return Math.min(stagePackages, objectiveTarget) + "/" + objectiveTarget
        if (zoneIndex === 2) return Math.floor(stageElapsed) + "S / 45S"
        return lives === stageStartLives ? "CLEAN" : "FAILED"
      }

      function cellOccupied(x, y) {
        if (playerX === x && playerY === y) return true
        for (var enemy = 0; enemy < enemies.length; enemy++)
          if (enemies[enemy].x === x && enemies[enemy].y === y) return true
        for (var shard = 0; shard < shards.length; shard++)
          if (shards[shard].x === x && shards[shard].y === y) return true
        return false
      }

      function setupHazards(generated) {
        var spawned = []
        var candidates = openCells(generated)
        var count = zoneIndex === 1 ? Math.min(2 + Math.floor(stage / 3), 4)
                  : zoneIndex === 3 ? Math.min(3 + Math.floor(stage / 2), 6) : 0
        while (spawned.length < count && candidates.length) {
          var choice = candidates.splice(Math.floor(Math.random() * candidates.length), 1)[0]
          if (Math.abs(choice.x - playerX) + Math.abs(choice.y - playerY) < 8 || cellOccupied(choice.x, choice.y)) continue
          spawned.push({ type: zoneIndex === 1 ? "log" : "firewall",
                         x: choice.x, y: choice.y,
                         dir: Math.random() < 0.5 ? -1 : 1,
                         phase: Math.random() * Math.PI * 2 })
        }
        hazards = spawned
        unstableCells = []
      }

      function firewallActive(hazard) {
        return Math.sin(animationTime * 3.2 + hazard.phase) > -0.12
      }

      function hazardBlocks(x, y) {
        for (var i = 0; i < hazards.length; i++) {
          var hazard = hazards[i]
          if (hazard.x !== x || hazard.y !== y) continue
          if (hazard.type === "firewall" && firewallActive(hazard)) return true
        }
        return false
      }

      function moveZoneHazards() {
        if (mode !== "playing" || zoneIndex !== 1) return
        var moved = []
        for (var i = 0; i < hazards.length; i++) {
          var hazard = hazards[i]
          var nextX = hazard.x + hazard.dir
          var nextDir = hazard.dir
          if (!inside(nextX, hazard.y) || isSoil(nextX, hazard.y)) {
            nextDir *= -1
            nextX = hazard.x + nextDir
          }
          if (!inside(nextX, hazard.y) || isSoil(nextX, hazard.y)) nextX = hazard.x
          moved.push({ type: hazard.type, x: nextX, y: hazard.y, dir: nextDir, phase: hazard.phase })
        }
        hazards = moved
        checkHazardCollision()
        worldCanvas.requestPaint()
      }

      function checkHazardCollision() {
        if (mode !== "playing") return
        for (var i = 0; i < hazards.length; i++) {
          if (hazards[i].type === "log" && hazards[i].x === playerX && hazards[i].y === playerY) {
            beginDeath("LOG ROTATION // PROCESS CRUSHED")
            return
          }
        }
      }

      function tickUnstableTerrain(dt) {
        if (zoneIndex !== 2 || mode !== "playing") return
        var pending = []
        for (var i = 0; i < unstableCells.length; i++) {
          var cell = unstableCells[i]
          var life = cell.life - dt
          if (life <= 0) {
            if (cellOccupied(cell.x, cell.y)) pending.push({ x: cell.x, y: cell.y, life: 0.55 })
            else {
              setSoil(cell.x, cell.y, true)
              statusMessage = "/TMP CACHE REBUILT BEHIND YOU"
            }
          } else pending.push({ x: cell.x, y: cell.y, life: life })
        }
        unstableCells = pending
      }

      function startRun() {
        score = 0
        stage = 1
        lives = 3
        packages = 0
        generateLevel(true)
        mode = "stageintro"
        stageIntroLife = 1.0
        shell.play(mountSound)
      }

      function movePlayer(dx, dy) {
        if (mode !== "playing") return false
        var nextX = playerX + dx
        var nextY = playerY + dy
        if (!inside(nextX, nextY) || nextY === 0) return false
        if (hazardBlocks(nextX, nextY)) {
          facingX = dx
          facingY = dy
          statusMessage = "FIREWALL ACTIVE // ACCESS DENIED"
          shell.play(hazardSound)
          return false
        }
        facingX = dx
        facingY = dy
        var digging = isSoil(nextX, nextY)
        var digIntervals = [185, 200, 170, 215]
        moveInterval = digging ? digIntervals[zoneIndex] : 145
        if (digging) {
          setSoil(nextX, nextY, false)
          score += 10 + stage
          shell.play(digSound)
          if (zoneIndex === 2) {
            var unstable = unstableCells.slice(0)
            unstable.push({ x: nextX, y: nextY, life: 3.2 })
            unstableCells = unstable
          }
        }
        playerX = nextX
        playerY = nextY

        var remaining = []
        for (var i = 0; i < shards.length; i++) {
          if (shards[i].x === playerX && shards[i].y === playerY) {
            packages += 1
            stagePackages += 1
            score += 180 + stage * 20
            shell.play(packageSound)
          } else remaining.push(shards[i])
        }
        shards = remaining
        checkCollision()
        checkHazardCollision()
        worldCanvas.requestPaint()
        return true
      }

      function requestMove(dx, dy) {
        var now = Date.now()
        if (now - lastMoveAt < moveInterval) {
          pendingMoveX = dx
          pendingMoveY = dy
          pendingMoveUntil = now + 190
          return
        }
        pendingMoveX = 0
        pendingMoveY = 0
        pendingMoveUntil = 0
        if (movePlayer(dx, dy)) lastMoveAt = now
      }

      function flushPendingMove() {
        if (pendingMoveX === 0 && pendingMoveY === 0) return
        var now = Date.now()
        if (now > pendingMoveUntil) {
          pendingMoveX = 0
          pendingMoveY = 0
          return
        }
        if (now - lastMoveAt < moveInterval) return
        var dx = pendingMoveX
        var dy = pendingMoveY
        pendingMoveX = 0
        pendingMoveY = 0
        pendingMoveUntil = 0
        if (movePlayer(dx, dy)) lastMoveAt = now
      }

      function setMoveIntent(dx, dy) {
        moveIntentX = dx
        moveIntentY = dy
        requestMove(dx, dy)
      }

      function refreshMoveIntent() {
        if (leftHeld) { moveIntentX = -1; moveIntentY = 0 }
        else if (rightHeld) { moveIntentX = 1; moveIntentY = 0 }
        else if (upHeld) { moveIntentX = 0; moveIntentY = -1 }
        else if (downHeld) { moveIntentX = 0; moveIntentY = 1 }
        else { moveIntentX = 0; moveIntentY = 0 }
      }

      function purge() {
        if (mode !== "playing" || pulseCooldown > 0) return
        pulseCooldown = 0.36
        pulseLife = 0.14
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
        var tagged = 0
        for (var i = 0; i < enemies.length; i++) {
          var hit = false
          for (var p = 0; p < path.length; p++)
            if (enemies[i].x === path[p].x && enemies[i].y === path[p].y) hit = true
          if (!hit) {
            survivors.push(enemies[i])
            continue
          }

          var nextCapture = enemies[i].capture + 1
          if (nextCapture >= 3) {
            purged += 1
            var deletionScore = (enemies[i].type === "rootkit" ? 900 : 600) + stage * 100
            score += deletionScore
            addScoreBurst(enemies[i].x, enemies[i].y, deletionScore)
            addPurgeBurst(enemies[i].x, enemies[i].y, enemies[i].type)
          } else {
            tagged += 1
            var captureScore = nextCapture * 75
            score += captureScore
            addScoreBurst(enemies[i].x, enemies[i].y, captureScore)
            survivors.push(daemonState(enemies[i].x, enemies[i].y, enemies[i].type,
                                       enemies[i].blink, nextCapture, 2.8, 0.24))
          }
        }
        enemies = survivors
        if (purged) {
          stagePurged += purged
          statusMessage = "SUDO PURGED " + purged + " DAEMON" + (purged > 1 ? "S" : "")
          if (!enemies.length) {
            beginStageClear()
          }
        } else if (tagged) {
          statusMessage = "DAEMON " + (survivors.some(function(enemy) { return enemy.capture === 2 })
                                       ? "COMPRESSED // PURGE AGAIN" : "QUARANTINED")
        }
        worldCanvas.requestPaint()
      }

      function addScoreBurst(x, y, points) {
        var next = scoreBursts.slice(0)
        next.push({ x: x + 0.5, y: y + 0.25, text: "+" + points, life: 0.9 })
        scoreBursts = next
      }

      function addPurgeBurst(x, y, type) {
        var next = purgeParticles.slice(0)
        for (var i = 0; i < 12; i++) {
          var angle = Math.PI * 2 * i / 12 + Math.random() * 0.2
          var speed = 1.4 + Math.random() * 1.8
          next.push({ x: x + 0.5, y: y + 0.5,
                      vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed,
                      life: 0.55 + Math.random() * 0.22, type: type })
        }
        purgeParticles = next
      }

      function availableMoves(enemy) {
        var options = []
        var directions = [{x:-1,y:0},{x:1,y:0},{x:0,y:-1},{x:0,y:1}]
        for (var i = 0; i < directions.length; i++) {
          var x = enemy.x + directions[i].x
          var y = enemy.y + directions[i].y
          if (!inside(x, y) || y === 0) continue
          if (!isSoil(x, y) || (enemy.type === "rootkit" && Math.random() < 0.2))
            options.push({ x: x, y: y })
        }
        return options
      }

      function moveEnemies() {
        if (mode !== "playing") return
        var moved = []
        for (var i = 0; i < enemies.length; i++) {
          var enemy = enemies[i]
          if (enemy.capture > 0) { moved.push(enemy); continue }
          var options = availableMoves(enemy)
          if (!options.length) { moved.push(enemy); continue }
          options.sort(function(a, b) {
            var distanceA = Math.abs(a.x - playerX) + Math.abs(a.y - playerY)
            var distanceB = Math.abs(b.x - playerX) + Math.abs(b.y - playerY)
            return distanceA - distanceB
          })
          var huntsPlayer = enemy.type === "zombie" || Math.random() < 0.62
          var choice = huntsPlayer ? options[0] : options[Math.floor(Math.random() * options.length)]
          moved.push(daemonState(choice.x, choice.y, enemy.type, enemy.blink, 0, 0, 0))
        }
        enemies = moved
        checkCollision()
        worldCanvas.requestPaint()
      }

      function checkCollision() {
        if (mode !== "playing") return
        for (var i = 0; i < enemies.length; i++) {
          if (enemies[i].capture === 0 && enemies[i].x === playerX && enemies[i].y === playerY) {
            beginDeath("SEGFAULT // ROGUE DAEMON")
            return
          }
        }
      }

      function beginDeath(reason) {
        if (mode !== "playing") return
        lives -= 1
        mode = "dying"
        deathLife = 0.95
        leftHeld = rightHeld = upHeld = downHeld = purgeHeld = false
        pendingMoveX = pendingMoveY = 0
        statusMessage = reason
        addPurgeBurst(playerX, playerY, "zombie")
        shell.play(hitSound)
      }

      function resolveDeath() {
        if (lives <= 0) finishRun()
        else {
          generateLevel(false)
          mode = "stageintro"
          stageIntroLife = 0.8
        }
      }

      function beginStageClear() {
        if (mode !== "playing") return
        objectiveMet = zoneIndex <= 1 ? stagePackages >= objectiveTarget
                     : zoneIndex === 2 ? stageElapsed <= 45
                     : lives === stageStartLives
        objectiveAward = objectiveMet ? 1000 + stage * 250 : 0
        score += stage * 500 + objectiveAward
        mode = "stageclear"
        stageClearLife = 2.4
        leftHeld = rightHeld = upHeld = downHeld = purgeHeld = false
        pendingMoveX = pendingMoveY = 0
        shell.play(objectiveMet ? bonusSound : clearSound)
      }

      function finishRun() {
        leftHeld = rightHeld = upHeld = downHeld = false
        purgeHeld = false
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
        if (shell.circuitMode) { window.visible = false; return }
        modeBeforeScores = "gameover"
        mode = "scores"
      }

      function advanceStage() {
        stage += 1
        generateLevel(true)
        mode = "stageintro"
        stageIntroLife = 1.15
        shell.play(mountSound)
      }

      function tickCombatEffects(dt) {
        var thawed = []
        for (var i = 0; i < enemies.length; i++) {
          var enemy = enemies[i]
          var capture = enemy.capture
          var captureLife = Math.max(0, enemy.captureLife - dt)
          if (capture > 0 && captureLife <= 0) {
            capture -= 1
            captureLife = capture > 0 ? 1.35 : 0
          }
          thawed.push(daemonState(enemy.x, enemy.y, enemy.type, enemy.blink,
                                  capture, captureLife, Math.max(0, enemy.hitFlash - dt)))
        }
        enemies = thawed

        var labels = []
        for (var label = 0; label < scoreBursts.length; label++) {
          var scoreBurst = scoreBursts[label]
          if (scoreBurst.life > dt)
            labels.push({ x: scoreBurst.x, y: scoreBurst.y - dt * 0.75,
                          text: scoreBurst.text, life: scoreBurst.life - dt })
        }
        scoreBursts = labels

        var particles = []
        for (var particle = 0; particle < purgeParticles.length; particle++) {
          var spark = purgeParticles[particle]
          if (spark.life > dt)
            particles.push({ x: spark.x + spark.vx * dt, y: spark.y + spark.vy * dt,
                             vx: spark.vx * 0.94, vy: spark.vy * 0.94,
                             life: spark.life - dt, type: spark.type })
        }
        purgeParticles = particles
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
          else if (shell.circuitMode && mode === "gameover" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) window.visible = false
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
        if (mode === "dying" || mode === "stageintro") {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) { leftHeld = true; setMoveIntent(-1, 0) }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) { rightHeld = true; setMoveIntent(1, 0) }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) { upHeld = true; setMoveIntent(0, -1) }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) { downHeld = true; setMoveIntent(0, 1) }
        else if (event.key === Qt.Key_Space) { purgeHeld = true; purge() }
        else if (event.key === Qt.Key_P) mode = mode === "paused" ? "playing" : "paused"
        else if (event.key === Qt.Key_H) openScores()
        else if (event.key === Qt.Key_R) startRun()
        else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
        event.accepted = true
      }

      Keys.onReleased: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) { leftHeld = false; refreshMoveIntent() }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) { rightHeld = false; refreshMoveIntent() }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) { upHeld = false; refreshMoveIntent() }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) { downHeld = false; refreshMoveIntent() }
        else if (event.key === Qt.Key_Space) purgeHeld = false
        event.accepted = true
      }

      Timer {
        interval: game.moveInterval
        repeat: true
        running: game.mode === "playing" && (game.leftHeld || game.rightHeld || game.upHeld || game.downHeld)
        onTriggered: if (game.moveIntentX !== 0 || game.moveIntentY !== 0)
          game.requestMove(game.moveIntentX, game.moveIntentY)
      }

      Timer {
        interval: Math.max(115, 315 - game.stage * 18)
        repeat: true
        running: game.mode === "playing"
        onTriggered: game.moveEnemies()
      }

      Timer {
        interval: Math.max(430, 780 - game.stage * 25)
        repeat: true
        running: game.mode === "playing" && game.zoneIndex === 1
        onTriggered: game.moveZoneHazards()
      }

      Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: {
          game.animationTime += 0.016
          var movementEase = 0.22
          game.playerVisualX += (game.playerX - game.playerVisualX) * movementEase
          game.playerVisualY += (game.playerY - game.playerVisualY) * movementEase
          game.pulseCooldown = Math.max(0, game.pulseCooldown - 0.016)
          game.pulseLife = Math.max(0, game.pulseLife - 0.016)
          if (game.mode === "playing") game.stageElapsed += 0.016
          game.flushPendingMove()
          if (game.purgeHeld && game.pulseCooldown <= 0) game.purge()
          game.tickUnstableTerrain(0.016)
          if (game.mode === "dying") {
            game.deathLife = Math.max(0, game.deathLife - 0.016)
            if (game.deathLife <= 0) game.resolveDeath()
          } else if (game.mode === "stageclear") {
            game.stageClearLife = Math.max(0, game.stageClearLife - 0.016)
            if (game.stageClearLife <= 0) game.advanceStage()
          } else if (game.mode === "stageintro") {
            game.stageIntroLife = Math.max(0, game.stageIntroLife - 0.016)
            if (game.stageIntroLife <= 0) game.mode = "playing"
          }
          game.tickCombatEffects(0.016)
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
              Text { text: game.zoneName + "/DEEP/LEVEL-" + ("0" + String(game.stage)).slice(-2); color: game.zoneAccent; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
              Text { text: "BONUS: " + game.objectiveText + "  [" + game.objectiveProgress() + "]"; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
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
            onImageLoaded: requestPaint()
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
                    context.globalAlpha = 0.06 + game.zoneIndex * 0.025
                    context.fillStyle = game.zoneAccent
                    context.fillRect(cellX, cellY, game.cellWidth + 0.5, game.cellHeight + 0.5)
                    context.globalAlpha = 0.18 + game.zoneIndex * 0.025
                    context.strokeStyle = y % 2 === 0 ? theme.muted : game.zoneAccent
                    context.strokeRect(cellX + 1, cellY + 1, game.cellWidth - 2, game.cellHeight - 2)
                    if (game.zoneIndex === 1 && y % 2 === 0) {
                      context.beginPath()
                      context.moveTo(cellX + 3, cellY + game.cellHeight * 0.68)
                      context.lineTo(cellX + game.cellWidth - 3, cellY + game.cellHeight * 0.68)
                      context.stroke()
                    } else if (game.zoneIndex === 2 && (x + y) % 3 === 0) {
                      context.fillRect(cellX + game.cellWidth * 0.62, cellY + 3, 3, 3)
                    } else if (game.zoneIndex === 3 && (x + y) % 2 === 0) {
                      context.beginPath()
                      context.moveTo(cellX + 2, cellY + game.cellHeight - 3)
                      context.lineTo(cellX + game.cellWidth - 2, cellY + 3)
                      context.stroke()
                    }
                    context.globalAlpha = 1
                  } else {
                    context.fillStyle = theme.background
                    context.fillRect(cellX, cellY, game.cellWidth + 1, game.cellHeight + 1)
                  }
                }
              }

              for (var unstable = 0; unstable < game.unstableCells.length; unstable++) {
                var cacheCell = game.unstableCells[unstable]
                var ux = cacheCell.x * game.cellWidth
                var uy = cacheCell.y * game.cellHeight
                context.globalAlpha = Math.max(0.16, 1 - cacheCell.life / 3.2)
                context.strokeStyle = theme.accent
                context.lineWidth = cacheCell.life < 0.8 ? 3 : 1
                context.strokeRect(ux + 3, uy + 3, game.cellWidth - 6, game.cellHeight - 6)
              }
              context.globalAlpha = 1

              for (var hazard = 0; hazard < game.hazards.length; hazard++) {
                var node = game.hazards[hazard]
                var hx = (node.x + 0.5) * game.cellWidth
                var hy = (node.y + 0.5) * game.cellHeight
                if (node.type === "log") {
                  var logWidth = game.cellWidth * 0.82
                  var logHeight = game.cellHeight * 0.62
                  context.fillStyle = theme.orange
                  context.fillRect(hx - logWidth / 2, hy - logHeight / 2, logWidth, logHeight)
                  context.strokeStyle = theme.background
                  context.lineWidth = 2
                  for (var stripe = -1; stripe <= 1; stripe++) {
                    context.beginPath()
                    context.moveTo(hx + stripe * logWidth * 0.24 - 3, hy - logHeight / 2)
                    context.lineTo(hx + stripe * logWidth * 0.24 + 3, hy + logHeight / 2)
                    context.stroke()
                  }
                } else {
                  var active = game.firewallActive(node)
                  context.globalAlpha = active ? 0.9 : 0.2
                  context.strokeStyle = theme.red
                  context.lineWidth = active ? 4 : 2
                  context.beginPath()
                  context.moveTo(hx, hy - game.cellHeight * 0.42)
                  context.lineTo(hx, hy + game.cellHeight * 0.42)
                  context.stroke()
                  context.fillStyle = theme.yellow
                  context.fillRect(hx - 3, hy - 3, 6, 6)
                  context.globalAlpha = 1
                }
              }

              for (var shard = 0; shard < game.shards.length; shard++) {
                var packageNode = game.shards[shard]
                var px = (packageNode.x + 0.5) * game.cellWidth
                var py = (packageNode.y + 0.5) * game.cellHeight
                context.globalAlpha = game.isSoil(packageNode.x, packageNode.y) ? 0.38 : 1
                var shardOpacity = context.globalAlpha
                if (!game.drawSprite(context, 0, 3, px, py,
                                     game.cellWidth * 1.18, game.cellHeight * 1.18, shardOpacity)) {
                  context.fillStyle = theme.yellow
                  context.beginPath()
                  context.moveTo(px, py - game.cellHeight * 0.27)
                  context.lineTo(px + game.cellWidth * 0.27, py)
                  context.lineTo(px, py + game.cellHeight * 0.27)
                  context.lineTo(px - game.cellWidth * 0.27, py)
                  context.closePath()
                  context.fill()
                }
              }
              context.globalAlpha = 1

              if (game.pulseLife > 0 && game.pulsePath.length) {
                context.globalAlpha = game.pulseLife / 0.14
                context.strokeStyle = theme.accent
                context.lineWidth = 4
                context.beginPath()
                context.moveTo((game.playerX + 0.5) * game.cellWidth, (game.playerY + 0.5) * game.cellHeight)
                var end = game.pulsePath[game.pulsePath.length - 1]
                context.lineTo((end.x + 0.5) * game.cellWidth, (end.y + 0.5) * game.cellHeight)
                context.stroke()
                context.globalAlpha = 1
              }

              for (var particle = 0; particle < game.purgeParticles.length; particle++) {
                var spark = game.purgeParticles[particle]
                context.globalAlpha = Math.min(1, spark.life * 2)
                context.fillStyle = spark.type === "rootkit" ? theme.orange : theme.red
                context.fillRect(spark.x * game.cellWidth - 2, spark.y * game.cellHeight - 2, 4, 4)
              }
              context.globalAlpha = 1

              for (var enemy = 0; enemy < game.enemies.length; enemy++) {
                var daemon = game.enemies[enemy]
                var ex = (daemon.x + 0.5) * game.cellWidth
                var ey = (daemon.y + 0.5) * game.cellHeight
                var baseRadius = Math.min(game.cellWidth, game.cellHeight) * 0.35
                var capturePulse = daemon.capture > 0 ? Math.sin(game.animationTime * 8 + daemon.blink) * 0.04 : 0
                var radius = baseRadius * (1 + daemon.capture * 0.22 + capturePulse)
                var rootkit = daemon.type === "rootkit"
                var daemonOpacity = rootkit && daemon.capture === 0
                    ? 0.58 + Math.sin(game.animationTime * 5 + daemon.blink) * 0.2 : 1
                var daemonScale = 1.72 + daemon.capture * 0.28 + capturePulse
                if (game.drawSprite(context, daemon.capture, rootkit ? 2 : 1, ex, ey,
                                    game.cellWidth * daemonScale, game.cellHeight * daemonScale,
                                    daemonOpacity)) continue
                context.globalAlpha = rootkit && daemon.capture === 0
                    ? 0.56 + Math.sin(game.animationTime * 5 + daemon.blink) * 0.22 : 1
                context.fillStyle = daemon.hitFlash > 0 ? theme.foreground
                                  : daemon.capture === 2 ? theme.yellow
                                  : daemon.capture === 1 ? theme.accent
                                  : rootkit ? theme.orange : theme.red
                context.beginPath()
                if (rootkit) {
                  context.moveTo(ex, ey - radius * 1.18)
                  context.lineTo(ex + radius, ey - radius * 0.25)
                  context.lineTo(ex + radius * 0.7, ey + radius)
                  context.lineTo(ex, ey + radius * 0.62)
                  context.lineTo(ex - radius * 0.7, ey + radius)
                  context.lineTo(ex - radius, ey - radius * 0.25)
                } else {
                  context.moveTo(ex - radius, ey - radius * 0.55)
                  context.lineTo(ex - radius * 0.55, ey - radius * 1.15)
                  context.lineTo(ex - radius * 0.15, ey - radius * 0.62)
                  context.lineTo(ex + radius * 0.15, ey - radius * 0.62)
                  context.lineTo(ex + radius * 0.55, ey - radius * 1.15)
                  context.lineTo(ex + radius, ey - radius * 0.55)
                  context.lineTo(ex + radius * 0.72, ey + radius)
                  context.lineTo(ex - radius * 0.72, ey + radius)
                }
                context.closePath()
                context.fill()

                if (daemon.capture > 0) {
                  context.globalAlpha = 0.68 + Math.sin(game.animationTime * 9) * 0.18
                  context.strokeStyle = daemon.capture === 2 ? theme.yellow : theme.accent
                  context.lineWidth = 2 + daemon.capture
                  context.beginPath()
                  context.arc(ex, ey, radius * 1.16, 0, Math.PI * 2)
                  context.stroke()
                }
                context.globalAlpha = 1
                context.fillStyle = theme.background
                context.fillRect(ex - radius * 0.48, ey - radius * 0.26, radius * 0.25, radius * 0.25)
                context.fillRect(ex + radius * 0.23, ey - radius * 0.26, radius * 0.25, radius * 0.25)
              }
              context.globalAlpha = 1

              var playerCenterX = (game.playerVisualX + 0.5) * game.cellWidth
              var playerCenterY = (game.playerVisualY + 0.5) * game.cellHeight
              var playerRadius = Math.min(game.cellWidth, game.cellHeight) * 0.38
              var playerHorizontal = game.facingX !== 0
              var playerFrame = playerHorizontal ? 1 : 0
              var playerFlipX = playerHorizontal && game.facingX < 0
              var playerFlipY = !playerHorizontal && game.facingY > 0
              var deathProgress = game.mode === "dying" ? 1 - game.deathLife / 0.95 : 0
              var playerScale = 1.72 + deathProgress * 1.1
              var playerOpacity = game.mode === "dying" ? Math.max(0, game.deathLife / 0.95) : 1
              if (!game.drawSprite(context, playerFrame, 0, playerCenterX, playerCenterY,
                                   game.cellWidth * playerScale, game.cellHeight * playerScale, playerOpacity,
                                   playerFlipX, playerFlipY)) {
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

              context.font = "bold " + Math.max(11, Math.floor(game.cellHeight * 0.55)) + "px monospace"
              context.textAlign = "center"
              for (var burst = 0; burst < game.scoreBursts.length; burst++) {
                var label = game.scoreBursts[burst]
                context.globalAlpha = Math.min(1, label.life * 2)
                context.fillStyle = theme.yellow
                context.fillText(label.text, label.x * game.cellWidth, label.y * game.cellHeight)
              }
              context.globalAlpha = 1
            }
          }

          Rectangle {
            visible: game.mode === "playing" && game.statusMessage.length > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: Math.min(parent.width - 20, statusText.implicitWidth + 24)
            height: 30
            radius: 5
            color: theme.surface
            border.color: theme.muted
            border.width: 1
            opacity: 0.9
            Text {
              id: statusText
              anchors.centerIn: parent
              text: game.statusMessage
              color: theme.foreground
              font.pixelSize: 11
              font.family: "monospace"
              font.bold: true
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
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "CARVE THROUGH THE FILESYSTEM. RECOVER PACKAGE SHARDS.\nQUARANTINE, COMPRESS, THEN PURGE EVERY ROGUE DAEMON."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.35 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ZOMBIE: HUNTS TUNNELS   ·   ROOTKIT: PHASES SOIL"; color: theme.orange; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
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
            height: game.mode === "stageclear" ? 205 : 160
            radius: 10
            color: theme.surface
            border.color: game.mode === "stageclear" ? theme.green : game.mode === "paused" ? theme.accent : theme.red
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "PROCESS SUSPENDED" : game.mode === "stageclear" ? game.zoneName + " SANITIZED" : "KERNEL PANIC"; color: game.mode === "stageclear" ? game.zoneAccent : game.mode === "paused" ? theme.accent : theme.red; font.pixelSize: 23; font.bold: true }
              Text { visible: game.mode === "stageclear"; anchors.horizontalCenter: parent.horizontalCenter; text: game.objectiveMet ? "BONUS COMPLETE  +" + game.objectiveAward : "BONUS MISSED  //  " + game.objectiveText; color: game.objectiveMet ? theme.yellow : theme.muted; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "P TO RESUME" : game.mode === "stageclear" ? "DESCENDING...  ·  ENTER TO SKIP" : "SCORE " + game.score + (shell.circuitMode ? "  ·  ENTER RETURN TO CIRCUIT" : "  ·  ENTER TO REMOUNT"); color: theme.foreground; font.pixelSize: 13; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.mode === "dying" || game.mode === "stageintro"
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 520)
            height: 132
            radius: 10
            color: theme.surface
            border.color: game.mode === "dying" ? theme.red : game.zoneAccent
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 10
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "dying" ? "SEGFAULT" : "MOUNTING " + game.zoneName; color: game.mode === "dying" ? theme.red : game.zoneAccent; font.pixelSize: 25; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "dying" ? game.statusMessage : "DEPTH " + game.stage + "  //  " + game.objectiveText; color: theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
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
