import QtQuick
import QtMultimedia
import Quickshell
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("packet-hop")
  readonly property bool circuitMode: Quickshell.env("OMACADE_CIRCUIT") === "1"
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
      readonly property real playfieldAspect: columns / rows
      readonly property url spriteAtlas: Qt.resolvedUrl("assets/packet-hop-sprites-v5.png")
      readonly property real spriteCell: 313.5
      readonly property real spriteScale: 0.76
      readonly property string zoneName: stage === 1 ? "/LAN" : stage === 2 ? "/WAN" : stage === 3 ? "/VPN" : "/ROOT"
      readonly property string routeRule: stage === 1 ? "LOCAL TRAFFIC // SWITCHES BUFFER"
                                            : stage === 2 ? "FIREWALLS PULSE // DPI SWEEPS"
                                            : stage === 3 ? "SSH PHASES // ROUTE EVENTS LIVE"
                                            : "ALL EVENTS LIVE // TTL TIGHT"
      readonly property real cellWidth: playfield.width / columns
      readonly property real cellHeight: playfield.height / rows
      readonly property bool tooSmall: playfield.width < 620 || playfield.height < 496

      property var lanes: []
      property var ports: []
      property var ttlPickup: ({ x: 7, y: 5, active: true })
      property var cachePickup: ({ x: 7, y: 5, active: false })
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
      property real stageTime: 0
      property real transitionLife: 0
      property string networkEvent: ""
      property string eventPhase: "idle"
      property real eventLife: 0
      property int eventLaneRow: -1
      property int eventSerial: 0
      property real lastHopAt: -10000
      property real lastNearMissAt: -10000
      property int intentX: 0
      property int intentY: 0
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property string initialsInput: ""
      property bool initialsPristine: true

      readonly property string eventName: mode === "binding" ? "PORT HANDSHAKE"
                                                : networkEvent === "packetloss" ? "PACKET LOSS"
                                                : networkEvent === "burst" ? "BURST TRAFFIC"
                                                : networkEvent === "routeflap" ? "ROUTE FLAP"
                                                : networkEvent === "cache" ? "CACHE HIT"
                                                : "LINK NOMINAL"
      readonly property string eventDetail: mode === "binding" ? "SYN  →  ACK // ROUTE ADDED"
                                                  : eventPhase === "warning" ? "L" + eventLaneRow + " // CHANGE IN " + Math.max(1, Math.ceil(eventLife)) + "S"
                                                  : networkEvent === "packetloss" ? "L" + eventLaneRow + " OFFLINE // CROSS NOW"
                                                  : networkEvent === "burst" ? "L" + eventLaneRow + " 1.7X // WATCH GAPS"
                                                  : networkEvent === "routeflap" ? "L" + eventLaneRow + " REVERSED // RE-ROUTE"
                                                  : networkEvent === "cache" ? "ROW 5 // +6 TTL +450"
                                                  : "NO ACTIVE NETWORK EVENT"
      readonly property color eventColor: mode === "binding" ? theme.green
                                             : eventPhase === "warning" ? theme.yellow
                                             : networkEvent === "packetloss" ? theme.accent
                                             : networkEvent === "burst" ? theme.red
                                             : networkEvent === "routeflap" ? theme.orange
                                             : networkEvent === "cache" ? theme.green
                                             : theme.muted

      Component.onCompleted: {
        worldCanvas.loadImage(spriteAtlas)
        buildStage()
        mode = "attract"
        forceActiveFocus()
      }

      function drawSprite(context, column, row, centerX, centerY, drawWidth, drawHeight, opacity, flipX) {
        if (!worldCanvas.isImageLoaded(spriteAtlas)) return false
        var scaledWidth = drawWidth * spriteScale
        var scaledHeight = drawHeight * spriteScale
        context.save()
        context.globalAlpha = opacity === undefined ? 1 : opacity
        context.translate(centerX, centerY)
        context.scale(flipX ? -1 : 1, 1)
        context.drawImage(spriteAtlas,
                          column * spriteCell, row * spriteCell, spriteCell, spriteCell,
                          -scaledWidth / 2, -scaledHeight / 2, scaledWidth, scaledHeight)
        context.restore()
        return true
      }

      function lane(row) {
        for (var i = 0; i < lanes.length; i++) if (lanes[i].row === row) return lanes[i]
        return null
      }

      function laneCycle(source, duration) {
        return ((stageTime + source.row * 0.19) % duration + duration) % duration
      }

      function laneIsWarning(source) {
        if (eventPhase === "warning" && source.row === eventLaneRow) return true
        if (source.kind === "ssh" && stage >= 3) {
          var sshCycle = laneCycle(source, 4.8)
          return sshCycle >= 2.9 && sshCycle < 3.45
        }
        if (source.kind === "firewall") {
          var firewallCycle = laneCycle(source, 3.8)
          return firewallCycle >= 1.85 && firewallCycle < 2.35
        }
        return false
      }

      function laneIsActive(source) {
        if (networkEvent === "packetloss" && eventPhase === "active" && source.row === eventLaneRow) return false
        if (source.kind === "ssh" && stage >= 3) {
          var sshCycle = laneCycle(source, 4.8)
          return sshCycle < 3.45 || sshCycle >= 4.25
        }
        if (source.kind === "firewall") {
          var firewallCycle = laneCycle(source, 3.8)
          return firewallCycle < 2.35
        }
        return true
      }

      function laneSpeedFactor(source) {
        var factor = 1
        if (source.kind === "package") factor = laneCycle(source, 4.2) < 0.7 ? 0 : 1
        else if (source.kind === "service") factor = 0.78 + 0.42 * (0.5 + 0.5 * Math.sin(stageTime * 2.4 + source.row))
        if (networkEvent === "burst" && eventPhase === "active" && source.row === eventLaneRow) factor *= 1.72
        return factor
      }

      function dpiBeamX(source, item) {
        return item.x + Math.sin(stageTime * 2.7 + source.row * 0.6) * item.width * 0.34
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
        networkEvent = ""
        eventPhase = "idle"
        eventLife = 0
        eventLaneRow = -1
        stageTime = 0
        var pace = 0.72 + Math.min(stage - 1, 5) * 0.13
        var networkKinds = stage === 1 ? ["pipe", "ssh", "container"]
                         : stage === 2 ? ["container", "vpn", "pipe"]
                         : stage === 3 ? ["vpn", "ssh", "vpn"]
                         : ["ssh", "vpn", "container"]
        var processKinds = stage === 1 ? ["service", "package", "window", "service", "package"]
                         : stage === 2 ? ["service", "firewall", "window", "package", "service"]
                         : stage === 3 ? ["window", "service", "firewall", "package", "window"]
                         : ["firewall", "window", "service", "firewall", "window"]
        lanes = [
          makeLane(2, "network", networkKinds[0], 1, 1.12 * pace, 4, 2.7),
          makeLane(3, "network", networkKinds[1], -1, 1.38 * pace, 4, 2.5),
          makeLane(4, "network", networkKinds[2], 1, 0.92 * pace, 4, 2.9),
          makeLane(6, "process", processKinds[0], -1, 1.48 * pace, 4, 1.65),
          makeLane(7, "process", processKinds[1], 1, 1.18 * pace, 4, 1.85),
          makeLane(8, "process", processKinds[2], -1, 1.72 * pace, 3, 2.15),
          makeLane(9, "process", processKinds[3], 1, 1.34 * pace, 4, 1.6),
          makeLane(10, "process", processKinds[4], -1, 1.58 * pace, 4, 1.8)
        ]
        ports = [
          { x: 1, bound: false }, { x: 4, bound: false }, { x: 7, bound: false },
          { x: 10, bound: false }, { x: 13, bound: false }
        ]
        ttlPickup = { x: 2 + Math.floor(Math.random() * 12), y: 5, active: true }
        cachePickup = { x: 7, y: 5, active: false }
        ttl = Math.max(25, 48 - (stage - 1) * 4.5)
        resetCourier()
        statusMessage = zoneName + " // " + routeRule
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
        lastNearMissAt = -10000
      }

      function startRun() {
        score = 0
        stage = 1
        lives = 3
        deliveries = 0
        eventSerial = 0
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
        collectCache()
        checkSafety()
        if (mode === "playing" && dy < 0) awardNearMiss(lane(playerY))
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
        if (!ttlPickup.active || playerY !== ttlPickup.y || Math.abs(playerX - ttlPickup.x) > 0.58) return
        ttlPickup = { x: ttlPickup.x, y: ttlPickup.y, active: false }
        ttl = Math.min(55, ttl + 9)
        score += 300
        statusMessage = "TTL REFRESHED +9"
        shell.play(ttlSound)
      }

      function collectCache() {
        if (!cachePickup.active || playerY !== cachePickup.y || Math.abs(playerX - cachePickup.x) > 0.58) return
        cachePickup = { x: cachePickup.x, y: cachePickup.y, active: false }
        ttl = Math.min(55, ttl + 6)
        score += 450
        statusMessage = "CACHE SERVED // +6 TTL // +450"
        finishNetworkEvent("")
        shell.play(bindSound)
      }

      function itemOverlap(item, x, margin) {
        return Math.abs(item.x - x) <= item.width * spriteScale / 2 + margin
      }

      function ridingItem(targetLane) {
        if (!targetLane || !laneIsActive(targetLane)) return null
        for (var i = 0; i < targetLane.items.length; i++)
          if (itemOverlap(targetLane.items[i], playerX, -0.08)) return targetLane.items[i]
        return null
      }

      function hazardOverlap(source, item, x, margin) {
        if (!laneIsActive(source)) return false
        if (source.kind === "window") return Math.abs(dpiBeamX(source, item) - x) <= 0.34 + margin
        return itemOverlap(item, x, margin)
      }

      function awardNearMiss(source) {
        if (!source || source.type !== "process" || Date.now() - lastNearMissAt < 450) return
        var nearest = 99
        for (var i = 0; i < source.items.length; i++) {
          var item = source.items[i]
          if (!laneIsActive(source)) continue
          var clearance = source.kind === "window"
                        ? Math.abs(dpiBeamX(source, item) - playerX) - 0.34
                        : Math.abs(item.x - playerX) - item.width * spriteScale / 2
          nearest = Math.min(nearest, clearance)
        }
        if (nearest > 0.05 && nearest < 0.34) {
          var bonus = 75 + stage * 25
          score += bonus
          lastNearMissAt = Date.now()
          statusMessage = "CLEAN HOP // NEAR MISS +" + bonus
          shell.play(ttlSound)
        }
      }

      function checkSafety() {
        if (mode !== "playing") return
        var current = lane(playerY)
        if (!current) return
        if (current.type === "network") {
          if (!ridingItem(current)) dropPacket("NO CARRIER // PACKET LOST")
        } else {
          for (var i = 0; i < current.items.length; i++) {
            if (hazardOverlap(current, current.items[i], playerX, 0.16)) {
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
        if (shell.circuitMode) { window.visible = false; return }
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
          var delta = source.direction * source.speed * laneSpeedFactor(source) * dt
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

      function reverseEventLane() {
        var updated = []
        for (var i = 0; i < lanes.length; i++) {
          var source = lanes[i]
          updated.push({ row: source.row, type: source.type, kind: source.kind,
                         direction: source.row === eventLaneRow ? -source.direction : source.direction,
                         speed: source.speed, items: source.items })
        }
        lanes = updated
      }

      function queueNetworkEvent() {
        if (mode !== "playing" || networkEvent.length > 0) return
        var choices = stage === 1 ? ["cache"]
                    : stage === 2 ? ["cache", "packetloss", "burst"]
                    : ["routeflap", "cache", "packetloss", "burst"]
        var selection = eventSerial
        eventSerial += 1
        networkEvent = choices[selection % choices.length]
        if (networkEvent === "cache") {
          var cacheX = 2 + Math.floor(Math.random() * 12)
          if (ttlPickup.active && Math.abs(cacheX - ttlPickup.x) < 1.2) cacheX = (cacheX + 4) % 13 + 1
          cachePickup = { x: cacheX, y: 5, active: true }
          eventLaneRow = 5
          eventPhase = "active"
          eventLife = 7.0
          statusMessage = "CACHE HIT // COLLECT ON ROW 5 // +TTL"
          shell.play(bindSound)
          return
        }

        var candidates = []
        for (var i = 0; i < lanes.length; i++) {
          var source = lanes[i]
          var eligible = networkEvent === "routeflap" ? source.type === "network"
                       : networkEvent === "burst" ? source.type === "process" && source.kind !== "package"
                       : source.type === "process"
          if (eligible)
            candidates.push(source)
        }
        if (!candidates.length) {
          networkEvent = ""
          return
        }
        var target = candidates[(selection + stage) % candidates.length]
        eventLaneRow = target.row
        eventPhase = "warning"
        eventLife = 1.35
        statusMessage = networkEvent === "packetloss" ? "PACKET LOSS // L" + eventLaneRow + " DROPS IN 1S"
                      : networkEvent === "burst" ? "BURST TRAFFIC // L" + eventLaneRow + " SURGES IN 1S"
                      : "ROUTE FLAP // L" + eventLaneRow + " REVERSES IN 1S"
        shell.play(ttlSound)
      }

      function activateNetworkEvent() {
        eventPhase = "active"
        if (networkEvent === "routeflap") reverseEventLane()
        eventLife = networkEvent === "packetloss" ? 2.8 : networkEvent === "burst" ? 3.2 : 3.6
        statusMessage = networkEvent === "packetloss" ? "PACKET LOSS // L" + eventLaneRow + " OFFLINE"
                      : networkEvent === "burst" ? "BURST TRAFFIC // L" + eventLaneRow + " AT 1.7X"
                      : "ROUTE FLAP // L" + eventLaneRow + " REVERSED"
        shell.play(ttlSound)
      }

      function finishNetworkEvent(message) {
        if (networkEvent === "routeflap" && eventPhase === "active") reverseEventLane()
        cachePickup = { x: cachePickup.x, y: cachePickup.y, active: false }
        networkEvent = ""
        eventPhase = "idle"
        eventLife = 0
        eventLaneRow = -1
        if (message && message.length > 0) statusMessage = message
      }

      function tickNetworkEvent(dt) {
        if (mode !== "playing" || networkEvent.length === 0) return
        eventLife = Math.max(0, eventLife - dt)
        if (eventLife > 0) return
        if (eventPhase === "warning") activateNetworkEvent()
        else finishNetworkEvent("LINK STABLE // EVENT CLEARED")
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
        if (mode === "paused") {
          if (event.key === Qt.Key_P) mode = "playing"
          event.accepted = true
          return
        }
        if (mode !== "playing" || game.tooSmall) { event.accepted = true; return }
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
        running: game.mode === "playing" && !game.tooSmall && (game.leftHeld || game.rightHeld || game.upHeld || game.downHeld)
        onTriggered: if (game.intentX !== 0 || game.intentY !== 0) game.requestHop(game.intentX, game.intentY)
      }

      Timer {
        interval: game.stage === 1 ? 9000 : game.stage === 2 ? 7500 : 6200
        repeat: true
        running: game.mode === "playing" && !game.tooSmall
        onTriggered: game.queueNetworkEvent()
      }

      Timer {
        interval: 16
        repeat: true
        running: !game.tooSmall
        onTriggered: {
          game.animationTime += 0.016
          if (game.mode === "playing") game.stageTime += 0.016
          game.tickNetworkEvent(0.016)
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
              width: parent.width * 0.38
              anchors.verticalCenter: parent.verticalCenter
              Text { text: "OMACADE // " + shell.cabinet.shortTitle; color: theme.accent; font.pixelSize: 18; font.bold: true; font.letterSpacing: 1.2 }
              Text { text: game.zoneName + "/ROUTE/STAGE-" + ("0" + game.stage).slice(-2); color: theme.green; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.routeRule; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
            }
            Repeater {
              model: [
                { label: "SCORE", value: game.score }, { label: "TTL", value: Math.ceil(game.ttl) },
                { label: "LIVES", value: game.lives }, { label: "PORTS", value: game.ports.filter(function(port) { return port.bound }).length + "/5" }
              ]
              delegate: Column {
                width: (parent.width * 0.40) / 4
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.label; color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                Text { text: modelData.value; color: modelData.label === "TTL" && game.ttl < 10 ? theme.red : theme.foreground; font.pixelSize: 18; font.family: "monospace"; font.bold: true }
              }
            }
            Rectangle {
              width: parent.width * 0.22
              height: 56
              anchors.verticalCenter: parent.verticalCenter
              radius: 6
              color: theme.background
              border.color: game.eventColor
              border.width: game.networkEvent.length > 0 || game.mode === "binding" ? 2 : 1
              opacity: game.eventPhase === "warning" ? 0.76 + 0.2 * Math.sin(game.animationTime * 15) : 1
              Column {
                anchors.centerIn: parent
                width: parent.width - 14
                spacing: 3
                Text {
                  width: parent.width; text: "●  " + game.eventName; color: game.eventColor
                  font.pixelSize: 10; font.family: "monospace"; font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width; text: game.eventDetail; color: theme.foreground
                  font.pixelSize: 8; font.family: "monospace"; font.bold: true
                  elide: Text.ElideRight
                }
              }
            }
          }
        }

        Item {
          id: playfieldSlot
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: hud.bottom
          anchors.bottom: footer.top
          readonly property real sideGutterWidth: Math.max(0, (width - playfield.width) / 2 - 24)
          readonly property real verticalGutterHeight: Math.max(0, (height - playfield.height) / 2)
          readonly property bool compactTelemetry: sideGutterWidth < 150 && verticalGutterHeight >= 58

          Rectangle {
            id: ingressRail
            visible: playfieldSlot.sideGutterWidth >= 150
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 12
            width: playfieldSlot.sideGutterWidth
            color: theme.surface
            border.color: theme.muted
            border.width: 1

            Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right; width: 2; color: theme.accent; opacity: 0.5 }
            Column {
              anchors.centerIn: parent
              width: parent.width - 28
              spacing: 16
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "// INGRESS"; color: theme.accent; font.pixelSize: 13; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.zoneName; color: theme.green; font.pixelSize: 21; font.family: "monospace"; font.bold: true }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Repeater {
                model: 8
                delegate: Row {
                  required property int index
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 10
                  Rectangle {
                    width: 8; height: 8; radius: 4
                    color: index < game.lanes.length && game.lanes[index].type === "network" ? theme.accent : theme.orange
                    opacity: 0.45 + ((index + Math.floor(game.animationTime * 3)) % 3) * 0.2
                  }
                  Text {
                    text: index < game.lanes.length
                          ? (game.lanes[index].direction > 0 ? "RX  →" : "←  TX") + "  L" + game.lanes[index].row
                          : "--"
                    color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true
                  }
                }
              }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "STACK ONLINE"; color: theme.foreground; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            id: egressRail
            visible: playfieldSlot.sideGutterWidth >= 150
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 12
            width: playfieldSlot.sideGutterWidth
            color: theme.surface
            border.color: theme.muted
            border.width: 1

            Rectangle { anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left; width: 2; color: theme.green; opacity: 0.5 }
            Column {
              anchors.centerIn: parent
              width: parent.width - 28
              spacing: 16
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "EGRESS //"; color: theme.green; font.pixelSize: 13; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ROOT PORTS"; color: theme.foreground; font.pixelSize: 15; font.family: "monospace"; font.bold: true }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Repeater {
                model: 5
                delegate: Row {
                  required property int index
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: 10
                  Text { text: "0" + (index + 1); color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
                  Rectangle {
                    width: 34; height: 8; radius: 4
                    color: index < game.ports.length && game.ports[index].bound ? theme.green : theme.surfaceRaised
                    border.color: index < game.ports.length && game.ports[index].bound ? theme.green : theme.muted
                    border.width: 1
                  }
                }
              }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "TTL  " + Math.ceil(game.ttl); color: game.ttl < 10 ? theme.red : theme.yellow; font.pixelSize: 18; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ROUTE TABLE // " + game.stage; color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            id: compactIngressRail
            visible: playfieldSlot.compactTelemetry
            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            width: playfield.width
            height: Math.min(66, playfieldSlot.verticalGutterHeight - 18)
            color: theme.surface
            border.color: theme.muted
            border.width: 1

            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: 2; color: theme.accent; opacity: 0.5 }
            Row {
              anchors.centerIn: parent
              spacing: 17
              Text { text: "// INGRESS"; color: theme.accent; font.pixelSize: 11; font.family: "monospace"; font.bold: true; font.letterSpacing: 1.4 }
              Text { text: game.zoneName; color: theme.green; font.pixelSize: 14; font.family: "monospace"; font.bold: true }
              Rectangle { width: 1; height: 24; color: theme.muted; anchors.verticalCenter: parent.verticalCenter }
              Repeater {
                model: 8
                delegate: Text {
                  required property int index
                  text: index < game.lanes.length ? "L" + game.lanes[index].row + (game.lanes[index].direction > 0 ? "→" : "←") : "--"
                  color: index < game.lanes.length && game.lanes[index].type === "network" ? theme.accent : theme.orange
                  font.pixelSize: 9; font.family: "monospace"; font.bold: true
                }
              }
              Rectangle { width: 1; height: 24; color: theme.muted; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "STACK ONLINE"; color: theme.foreground; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            id: compactEgressRail
            visible: playfieldSlot.compactTelemetry
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
            width: playfield.width
            height: Math.min(66, playfieldSlot.verticalGutterHeight - 18)
            color: theme.surface
            border.color: theme.muted
            border.width: 1

            Rectangle { anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; height: 2; color: theme.green; opacity: 0.5 }
            Row {
              anchors.centerIn: parent
              spacing: 18
              Text { text: "EGRESS //"; color: theme.green; font.pixelSize: 11; font.family: "monospace"; font.bold: true; font.letterSpacing: 1.4 }
              Text { text: "ROOT PORTS"; color: theme.foreground; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Repeater {
                model: 5
                delegate: Rectangle {
                  required property int index
                  width: 28; height: 8; radius: 4
                  color: index < game.ports.length && game.ports[index].bound ? theme.green : theme.surfaceRaised
                  border.color: index < game.ports.length && game.ports[index].bound ? theme.green : theme.muted
                  border.width: 1
                }
              }
              Rectangle { width: 1; height: 24; color: theme.muted; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "TTL  " + Math.ceil(game.ttl); color: game.ttl < 10 ? theme.red : theme.yellow; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text { text: "TABLE // " + game.stage; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
            }
          }

          Item {
            id: playfield
            anchors.centerIn: parent
            width: Math.min(playfieldSlot.width - 24,
                            (playfieldSlot.height - 24) * game.playfieldAspect)
            height: width / game.playfieldAspect
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

              // Faint packet pulses make route direction and relative speed
              // readable without becoming collision-shaped foreground noise.
              for (var flowLane = 0; flowLane < game.lanes.length; flowLane++) {
                var flow = game.lanes[flowLane]
                var flowPhase = game.animationTime * flow.speed * game.laneSpeedFactor(flow) * flow.direction * 1.45
                var flowY = (flow.row + 0.5) * game.cellHeight
                context.fillStyle = game.laneIsWarning(flow) ? theme.yellow
                                  : flow.type === "network" ? theme.accent : theme.orange
                context.globalAlpha = game.laneIsWarning(flow) ? 0.3
                                    : flow.type === "network" ? 0.16 : 0.11
                for (var marker = -1; marker <= game.columns + 1; marker += 2.5) {
                  var flowColumn = ((marker + flowPhase) % game.columns + game.columns) % game.columns
                  var flowX = (flowColumn + 0.5) * game.cellWidth
                  var tail = game.cellWidth * 0.12
                  context.fillRect(flowX - tail / 2, flowY - 1, tail, 2)
                  context.beginPath()
                  context.moveTo(flowX + flow.direction * tail * 0.85, flowY)
                  context.lineTo(flowX + flow.direction * tail * 0.42, flowY - 3)
                  context.lineTo(flowX + flow.direction * tail * 0.42, flowY + 3)
                  context.closePath()
                  context.fill()
                }
                context.globalAlpha = 1
              }

              for (var port = 0; port < game.ports.length; port++) {
                var socket = game.ports[port]
                if (game.mode === "binding" && Math.abs(socket.x - game.playerX) < 0.2) {
                  var bindX = (socket.x + 0.5) * game.cellWidth
                  var bindPulse = 0.55 + 0.35 * Math.sin(game.animationTime * 14)
                  context.strokeStyle = theme.green
                  for (var bindRing = 0; bindRing < 3; bindRing++) {
                    context.globalAlpha = Math.max(0.12, bindPulse - bindRing * 0.2)
                    context.lineWidth = 3 - bindRing * 0.6
                    context.beginPath()
                    context.arc(bindX, game.cellHeight * 0.5,
                                game.cellHeight * (0.42 + bindRing * 0.2), 0, Math.PI * 2)
                    context.stroke()
                  }
                  context.globalAlpha = 0.26
                  context.fillStyle = theme.green
                  context.fillRect(bindX - 4, game.cellHeight * 0.7, 8, game.cellHeight * 1.15)
                  context.globalAlpha = 0.7
                  context.font = "bold 10px monospace"
                  context.fillText("SYN", bindX - game.cellWidth * 0.95, game.cellHeight * 1.58)
                  context.fillText("ACK", bindX + game.cellWidth * 0.52, game.cellHeight * 1.58)
                  context.lineWidth = 2
                  context.beginPath()
                  context.moveTo(bindX - game.cellWidth * 0.45, game.cellHeight * 1.48)
                  context.lineTo(bindX + game.cellWidth * 0.45, game.cellHeight * 1.48)
                  context.stroke()
                  context.globalAlpha = 1
                }
                game.drawSprite(context, socket.bound ? 1 : 0, 3,
                                (socket.x + 0.5) * game.cellWidth, game.cellHeight * 0.5,
                                game.cellWidth * 1.55, game.cellHeight * 1.38, 1, false)
                if (socket.bound) {
                  context.globalAlpha = 0.32 + 0.15 * Math.sin(game.animationTime * 4 + socket.x)
                  context.strokeStyle = theme.green
                  context.lineWidth = 2
                  context.beginPath()
                  context.arc((socket.x + 0.5) * game.cellWidth, game.cellHeight * 0.5, game.cellHeight * 0.58, 0, Math.PI * 2)
                  context.stroke()
                  context.globalAlpha = 1
                }
              }

              for (var l = 0; l < game.lanes.length; l++) {
                var traffic = game.lanes[l]
                var spriteRow = traffic.type === "process" ? 1 : 2
                var spriteColumn = traffic.kind === "service" || traffic.kind === "pipe" ? 0
                                 : traffic.kind === "package" || traffic.kind === "container" ? 1
                                 : traffic.kind === "window" || traffic.kind === "ssh" ? 2 : 3
                var trafficActive = game.laneIsActive(traffic)
                var trafficWarning = game.laneIsWarning(traffic)
                if (trafficWarning) {
                  context.globalAlpha = 0.08 + 0.05 * Math.sin(game.animationTime * 16)
                  context.fillStyle = theme.yellow
                  context.fillRect(0, traffic.row * game.cellHeight, width, game.cellHeight)
                  context.globalAlpha = 1
                }
                var eventOnLane = game.networkEvent.length > 0 && game.eventLaneRow === traffic.row
                if (eventOnLane) {
                  var laneTop = traffic.row * game.cellHeight
                  context.globalAlpha = game.eventPhase === "warning"
                                      ? 0.12 + 0.08 * Math.sin(game.animationTime * 16) : 0.09
                  context.fillStyle = game.eventColor
                  context.fillRect(0, laneTop, width, game.cellHeight)
                  context.globalAlpha = 0.78
                  context.strokeStyle = game.eventColor
                  context.lineWidth = 2
                  context.strokeRect(1, laneTop + 1, width - 2, game.cellHeight - 2)
                  if (game.eventPhase === "warning") {
                    var sweepX = ((game.animationTime * 1.6) % 1) * width
                    context.globalAlpha = 0.22
                    context.strokeStyle = game.eventColor
                    context.lineWidth = 14
                    context.beginPath(); context.moveTo(sweepX, laneTop); context.lineTo(sweepX, laneTop + game.cellHeight); context.stroke()
                    context.globalAlpha = 0.85
                    context.lineWidth = 2.5
                    context.beginPath(); context.moveTo(sweepX, laneTop); context.lineTo(sweepX, laneTop + game.cellHeight); context.stroke()
                    context.globalAlpha = 1
                  }
                  if (game.networkEvent === "packetloss" && game.eventPhase === "active") {
                    context.globalAlpha = 0.32
                    context.lineWidth = 3
                    for (var lossMark = 0; lossMark < game.columns; lossMark += 1.5) {
                      var lossX = (lossMark + 0.5) * game.cellWidth
                      context.beginPath()
                      context.moveTo(lossX - 7, laneTop + game.cellHeight * 0.38)
                      context.lineTo(lossX + 7, laneTop + game.cellHeight * 0.62)
                      context.moveTo(lossX + 7, laneTop + game.cellHeight * 0.38)
                      context.lineTo(lossX - 7, laneTop + game.cellHeight * 0.62)
                      context.stroke()
                    }
                  }
                  context.globalAlpha = 0.94
                  context.fillStyle = theme.surface
                  context.fillRect(7, laneTop + 6, game.cellWidth * 3.25, 19)
                  context.strokeStyle = game.eventColor
                  context.lineWidth = 1
                  context.strokeRect(7, laneTop + 6, game.cellWidth * 3.25, 19)
                  context.fillStyle = game.eventColor
                  context.font = "bold 10px monospace"
                  var laneEventText = game.eventPhase === "warning" ? "[!] L" + traffic.row + " // " + game.eventName + " IN 1S"
                                    : "L" + traffic.row + " // " + game.eventDetail
                  context.fillText(laneEventText, 14, laneTop + 19)
                  context.globalAlpha = 1
                }
                for (var item = 0; item < traffic.items.length; item++) {
                  var vehicle = traffic.items[item]
                  var spriteOpacity = trafficActive ? (trafficWarning ? 0.62 + 0.28 * Math.sin(game.animationTime * 14) : 1) : 0.2
                  if (traffic.type === "network") {
                    var streakVX = (vehicle.x + 0.5) * game.cellWidth
                    var streakVY = (traffic.row + 0.5) * game.cellHeight
                    var streakTailX = streakVX - traffic.direction * game.cellWidth * vehicle.width * 0.9
                    context.globalAlpha = 0.14 * spriteOpacity
                    context.strokeStyle = theme.accent
                    context.lineWidth = game.cellHeight * 0.5
                    context.beginPath(); context.moveTo(streakTailX, streakVY); context.lineTo(streakVX, streakVY); context.stroke()
                    context.globalAlpha = 0.5 * spriteOpacity
                    context.lineWidth = 2.5
                    context.beginPath(); context.moveTo(streakTailX, streakVY); context.lineTo(streakVX, streakVY); context.stroke()
                    context.globalAlpha = 1
                  }
                  game.drawSprite(context, spriteColumn, spriteRow,
                                  (vehicle.x + 0.5) * game.cellWidth, (traffic.row + 0.5) * game.cellHeight,
                                  game.cellWidth * vehicle.width, game.cellHeight * 1.18,
                                  spriteOpacity, traffic.direction < 0)

                  if (traffic.kind === "window") {
                    var beamX = (game.dpiBeamX(traffic, vehicle) + 0.5) * game.cellWidth
                    context.globalAlpha = 0.58 + 0.24 * Math.sin(game.animationTime * 12)
                    context.fillStyle = theme.accent
                    context.fillRect(beamX - 2, (traffic.row + 0.12) * game.cellHeight, 4, game.cellHeight * 0.76)
                    context.globalAlpha = 0.18
                    context.fillRect(beamX - game.cellWidth * 0.18, (traffic.row + 0.22) * game.cellHeight,
                                     game.cellWidth * 0.36, game.cellHeight * 0.56)
                    context.globalAlpha = 1
                  } else if (traffic.kind === "package" && game.laneSpeedFactor(traffic) === 0) {
                    var switchX = (vehicle.x + 0.5) * game.cellWidth
                    context.globalAlpha = 0.7
                    context.fillStyle = theme.yellow
                    for (var bufferBit = -1; bufferBit <= 1; bufferBit++)
                      context.fillRect(switchX + bufferBit * 8 - 2, (traffic.row + 0.16) * game.cellHeight, 4, 4)
                    context.globalAlpha = 1
                  }
                }
              }

              if (game.ttlPickup.active) {
                var ttlX = (game.ttlPickup.x + 0.5) * game.cellWidth
                var ttlY = (game.ttlPickup.y + 0.5) * game.cellHeight
                context.globalAlpha = 0.6 + 0.28 * Math.sin(game.animationTime * 9)
                context.strokeStyle = theme.accent
                context.lineWidth = 2.4
                context.beginPath()
                context.arc(ttlX, ttlY, game.cellHeight * 0.4, 0, Math.PI * 2)
                context.stroke()
                context.globalAlpha = 1
                game.drawSprite(context, 2, 3, ttlX, ttlY, game.cellWidth * 1.15, game.cellHeight * 1.15, 1, false)
              }

              if (game.cachePickup.active) {
                var cacheX = (game.cachePickup.x + 0.5) * game.cellWidth
                var cacheY = (game.cachePickup.y + 0.5) * game.cellHeight
                var cachePulse = 0.68 + 0.25 * Math.sin(game.animationTime * 10)
                context.globalAlpha = cachePulse
                context.strokeStyle = theme.green
                context.lineWidth = 3
                context.beginPath()
                context.arc(cacheX, cacheY, game.cellHeight * 0.42, 0, Math.PI * 2)
                context.stroke()
                context.globalAlpha = 1
                game.drawSprite(context, 3, 3, cacheX, cacheY,
                                game.cellWidth * 1.15, game.cellHeight * 1.15, 1, false)
                context.fillStyle = theme.surface
                context.fillRect(cacheX - 54, cacheY - game.cellHeight * 0.58, 108, 17)
                context.strokeStyle = theme.green
                context.strokeRect(cacheX - 54, cacheY - game.cellHeight * 0.58, 108, 17)
                context.fillStyle = theme.green
                context.font = "bold 9px monospace"
                context.fillText("CACHE // +6 TTL", cacheX - 48, cacheY - game.cellHeight * 0.58 + 12)
              }

              var px = (game.playerVisualX + 0.5) * game.cellWidth
              var py = (game.playerVisualY + 0.5) * game.cellHeight
              var courierFrame = game.mode === "binding" ? 2 : game.mode === "dropping" ? 3 : Math.floor(game.animationTime * 5) % 2
              var courierScale = game.mode === "dropping" ? 1.9 : 1.38
              if (game.mode === "playing" || game.mode === "binding") {
                var courierPulse = 3 * Math.sin(game.animationTime * 5)
                context.globalAlpha = 0.16
                context.strokeStyle = theme.accent
                context.lineWidth = 8
                context.beginPath()
                context.arc(px, py, game.cellHeight * 0.62 + courierPulse, 0, Math.PI * 2)
                context.stroke()
                context.globalAlpha = 0.5
                context.lineWidth = 2
                context.beginPath()
                context.arc(px, py, game.cellHeight * 0.5 + courierPulse, 0, Math.PI * 2)
                context.stroke()
                context.globalAlpha = 1
              }
              var trailDX = game.playerVisualX - game.playerX
              var trailDY = game.playerVisualY - game.playerY
              if (game.mode === "playing" && Math.abs(trailDX) + Math.abs(trailDY) > 0.04) {
                for (var ghost = 3; ghost >= 1; ghost--)
                  game.drawSprite(context, courierFrame, 0,
                                  px + trailDX * game.cellWidth * ghost * 0.28,
                                  py + trailDY * game.cellHeight * ghost * 0.28,
                                  game.cellWidth * courierScale, game.cellHeight * courierScale,
                                  0.04 + ghost * 0.035, false)
              }
              game.drawSprite(context, courierFrame, 0, px, py,
                              game.cellWidth * courierScale, game.cellHeight * courierScale,
                              game.mode === "dropping" ? Math.max(0.25, game.transitionLife / 0.85) : 1, false)
            }
          }

          Rectangle {
            visible: game.mode === "playing" && game.statusMessage.length > 0
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: game.cellHeight + 8
            anchors.rightMargin: 9
            width: Math.min(parent.width - 18, routeStatus.implicitWidth + 22)
            height: 29
            radius: 5
            color: theme.surface
            border.color: game.networkEvent.length > 0 ? game.eventColor : theme.muted
            border.width: game.networkEvent.length > 0 ? 2 : 1
            opacity: game.eventPhase === "warning" ? 0.72 + 0.24 * Math.sin(game.animationTime * 15) : 0.94
            Text { id: routeStatus; anchors.centerIn: parent; text: game.statusMessage; color: game.networkEvent.length > 0 ? game.eventColor : theme.foreground; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
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
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "ROUTE A COURIER PACKET ACROSS HOSTILE PROCESS LANES.\nRIDE DATA STREAMS AND ENCRYPTED TUNNELS. BIND ALL FIVE ROOT PORTS."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.32 }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "gameover" ? "SCORE " + game.score + (shell.circuitMode ? "  ·  ENTER RETURN TO CIRCUIT" : "  ·  ENTER TO RESEND") : game.mode === "paused" ? "P TO RESUME" : game.statusMessage; color: theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PACKET::HOP // TOP TEN"; color: theme.accent; font.pixelSize: 23; font.bold: true }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Enlarge the cabinet for a 620 × 496 playfield."; color: theme.foreground; font.pixelSize: 13 }
            }
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
