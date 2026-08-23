import QtQuick
import QtMultimedia
import Quickshell
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("core-command")
  readonly property bool circuitMode: Quickshell.env("OMACADE_CIRCUIT") === "1"
  ArcadeTheme { id: theme }
  ArcadeData { id: arcadeData; cabinetId: shell.cabinet.scoreKey }

  SoundEffect { id: launchSound; source: Qt.resolvedUrl("assets/sfx/core-launch.wav"); volume: 0.38 }
  SoundEffect { id: blastSound; source: Qt.resolvedUrl("assets/sfx/core-blast.wav"); volume: 0.46 }
  SoundEffect { id: impactSound; source: Qt.resolvedUrl("assets/sfx/core-impact.wav"); volume: 0.5 }
  SoundEffect { id: waveSound; source: Qt.resolvedUrl("assets/sfx/core-wave.wav"); volume: 0.48 }

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
    implicitWidth: 1020
    implicitHeight: 760
    minimumSize: Qt.size(780, 610)
    onVisibleChanged: if (!visible) Qt.quit()

    FocusScope {
      id: game
      anchors.fill: parent
      focus: true

      readonly property real worldWidth: 1000
      readonly property real worldHeight: 600
      readonly property real worldAspect: worldWidth / worldHeight
      readonly property real groundY: 545
      readonly property var serviceNames: ["SHELL", "NET", "HOME", "PKG", "SYNC", "BOOT"]
      readonly property var serviceCapabilities: ["AIM+", "BUS+", "SCORE+", "RULES+", "REPAIR+", "ROLLBACK"]
      readonly property string zoneName: wave <= 2 ? "/EDGE" : wave <= 4 ? "/WAN" : wave <= 6 ? "/DMZ" : "/CORE"
      readonly property bool tooSmall: worldCanvas.width < 620 || worldCanvas.height < 372

      property string mode: "attract"
      property string modeBeforeScores: "attract"
      property int wave: 1
      property int score: 0
      property int spawnedThreats: 0
      property int waveThreats: 9
      property int threatsDestroyed: 0
      property int shotsFired: 0
      property int maxChain: 0
      property int currentChain: 0
      property int perfectWaves: 0
      property int selectedBattery: -1
      property real crosshairX: 500
      property real crosshairY: 250
      property real spawnCooldown: 0
      property real transitionLife: 0
      property real animationTime: 0
      property real impactFlash: 0
      property real chainLife: 0
      property real launchBusCooldown: 0
      property real lastTickMs: Date.now()
      property bool bootRecoveryAvailable: true
      property string chainText: ""
      property string statusMessage: "DEFENSE GRID READY"
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property var firewallCooldowns: [0, 0, 0]
      property var services: []
      property var batteries: []
      property var threats: []
      property var interceptors: []
      property var explosions: []
      property var stars: []
      property string initialsInput: ""
      property bool initialsPristine: true

      readonly property int onlineServices: {
        var count = 0
        for (var i = 0; i < services.length; i++) if (services[i].alive) count += 1
        return count
      }
      readonly property int totalAmmo: {
        var count = 0
        for (var i = 0; i < batteries.length; i++) if (batteries[i].alive) count += batteries[i].ammo
        return count
      }

      Component.onCompleted: {
        var generatedStars = []
        for (var i = 0; i < 62; i++) generatedStars.push({ x: Math.random() * worldWidth, y: 35 + Math.random() * 360, phase: Math.random() * 6.28 })
        stars = generatedStars
        services = freshServices()
        batteries = freshBatteries()
        forceActiveFocus()
      }

      function freshServices() {
        var positions = [120, 265, 410, 590, 735, 880]
        var result = []
        for (var i = 0; i < positions.length; i++) result.push({ x: positions[i], alive: true, name: serviceNames[i] })
        return result
      }

      function freshBatteries() {
        return [
          { x: 48, alive: true, ammo: 10 },
          { x: 500, alive: true, ammo: 12 },
          { x: 952, alive: true, ammo: 10 }
        ]
      }

      function serviceOnline(name) {
        for (var i = 0; i < services.length; i++) if (services[i].name === name) return services[i].alive
        return false
      }

      function startRun() {
        wave = 1
        score = 0
        threatsDestroyed = 0
        shotsFired = 0
        maxChain = 0
        currentChain = 0
        perfectWaves = 0
        bootRecoveryAvailable = true
        services = freshServices()
        selectedBattery = -1
        prepareWave()
        mode = "waveintro"
        transitionLife = 1.25
        shell.play(waveSound)
      }

      function prepareWave() {
        threats = []
        interceptors = []
        explosions = []
        spawnedThreats = 0
        waveThreats = 6 + wave * 3
        spawnCooldown = 0.85
        crosshairX = 500
        crosshairY = 245
        leftHeld = rightHeld = upHeld = downHeld = false
        firewallCooldowns = [0, 0, 0]
        launchBusCooldown = 0
        var ammoBase = Math.max(7, 11 - Math.floor((wave - 1) / 3)) + (serviceOnline("PKG") ? 1 : 0)
        batteries = [
          { x: 48, alive: true, ammo: ammoBase },
          { x: 500, alive: true, ammo: ammoBase + 2 },
          { x: 952, alive: true, ammo: ammoBase }
        ]
        statusMessage = zoneName + " // WAVE " + wave + " // GRID ARMED"
        worldCanvas.requestPaint()
      }

      function advanceWave() {
        wave += 1
        var repairedName = ""
        var repairInterval = serviceOnline("SYNC") ? 3 : 4
        if (wave % repairInterval === 0 && onlineServices < services.length) {
          var repaired = services.slice(0)
          for (var i = 0; i < repaired.length; i++) {
            if (!repaired[i].alive) {
              repaired[i] = { x: repaired[i].x, alive: true, name: repaired[i].name }
              repairedName = repaired[i].name
              break
            }
          }
          services = repaired
        }
        prepareWave()
        if (repairedName) statusMessage = "SYNC RESTORE // " + repairedName + " ONLINE"
        mode = "waveintro"
        transitionLife = 1.15
        shell.play(waveSound)
      }

      function threatType() {
        var roll = Math.random()
        if (wave >= 4 && roll < 0.15) return "rootkit"
        if (wave >= 3 && roll < 0.34) return "stealth"
        if (wave >= 2 && roll < 0.58) return "fork"
        return "exploit"
      }

      function livingTargets() {
        var targets = []
        for (var i = 0; i < services.length; i++) if (services[i].alive) targets.push({ kind: "service", index: i, x: services[i].x, y: groundY - 12 })
        for (var b = 0; b < batteries.length; b++) if (batteries[b].alive) targets.push({ kind: "battery", index: b, x: batteries[b].x, y: groundY - 6 })
        return targets
      }

      function spawnThreat(typeOverride, startX, startY, targetOverride) {
        var targets = livingTargets()
        if (!targets.length) return
        var target = targetOverride || targets[Math.floor(Math.random() * targets.length)]
        var type = typeOverride || threatType()
        var sx = startX === undefined ? 45 + Math.random() * 910 : startX
        var sy = startY === undefined ? -18 : startY
        var speed = 42 + Math.min(wave, 9) * 5
        if (type === "rootkit") speed *= 1.42
        else if (type === "stealth") speed *= 1.08
        else if (type === "zeroDay") speed *= 0.52
        var updated = threats.slice(0)
        updated.push({ sx: sx, sy: sy, x: sx, y: sy, tx: target.x, ty: target.y,
                       targetKind: target.kind, targetIndex: target.index, type: type,
                       speed: speed, split: false, hp: type === "zeroDay" ? 3 : 1,
                       hitCooldown: 0 })
        threats = updated
      }

      function chooseBattery(targetX) {
        if (selectedBattery >= 0 && selectedBattery < batteries.length
            && batteries[selectedBattery].alive && batteries[selectedBattery].ammo > 0) return selectedBattery
        var choice = -1
        var distance = 99999
        for (var i = 0; i < batteries.length; i++) {
          if (!batteries[i].alive || batteries[i].ammo <= 0) continue
          if (firewallCooldowns[i] > 0 || inFlightForBattery(i) >= 2) continue
          var gap = Math.abs(batteries[i].x - targetX)
          if (gap < distance) { choice = i; distance = gap }
        }
        return choice
      }

      function inFlightForBattery(index) {
        var count = 0
        for (var i = 0; i < interceptors.length; i++) if (interceptors[i].batteryIndex === index) count += 1
        return count
      }

      function fireAt(x, y) {
        if (mode !== "playing") return
        if (launchBusCooldown > 0) {
          statusMessage = "LAUNCH BUS CYCLING // HOLD FIRE"
          return
        }
        var batteryIndex = chooseBattery(x)
        if (batteryIndex < 0) {
          statusMessage = totalAmmo > 0 ? "FIREWALL GRID BUSY // SWITCH NODE OR HOLD" : "NO FIREWALL RULES // AMMO DEPLETED"
          if (totalAmmo <= 0) shell.play(impactSound)
          return
        }
        if (firewallCooldowns[batteryIndex] > 0) {
          statusMessage = "FW-" + (batteryIndex + 1) + " RECHARGING // SWITCH NODE"
          return
        }
        if (inFlightForBattery(batteryIndex) >= 2) {
          statusMessage = "FW-" + (batteryIndex + 1) + " QUEUE FULL // TWO IN FLIGHT"
          return
        }
        var updatedBatteries = batteries.slice(0)
        var battery = updatedBatteries[batteryIndex]
        updatedBatteries[batteryIndex] = { x: battery.x, alive: battery.alive, ammo: battery.ammo - 1 }
        batteries = updatedBatteries
        var updatedInterceptors = interceptors.slice(0)
        updatedInterceptors.push({ x: battery.x, y: groundY - 18, sx: battery.x, sy: groundY - 18,
                                   tx: Math.max(25, Math.min(worldWidth - 25, x)),
                                   ty: Math.max(45, Math.min(groundY - 65, y)), speed: 430,
                                   batteryIndex: batteryIndex })
        interceptors = updatedInterceptors
        var updatedCooldowns = firewallCooldowns.slice(0)
        updatedCooldowns[batteryIndex] = serviceOnline("NET") ? 0.24 : 0.34
        firewallCooldowns = updatedCooldowns
        launchBusCooldown = serviceOnline("NET") ? 0.14 : 0.20
        shotsFired += 1
        statusMessage = "QUARANTINE LAUNCHED // FW-" + (batteryIndex + 1)
        shell.play(launchSound)
      }

      function explosionRadius(blast) {
        var progress = Math.max(0, Math.min(1, blast.life / blast.duration))
        return Math.sin(progress * Math.PI) * blast.maxRadius
      }

      function addExplosion(x, y, maxRadius, kind, combo) {
        var updated = explosions.slice(0)
        updated.push({ x: x, y: y, life: 0, duration: kind === "impact" ? 0.78 : 1.35,
                       maxRadius: maxRadius, kind: kind, combo: combo || 1 })
        explosions = updated
      }

      function destroyTarget(threat) {
        if (threat.targetKind === "service") {
          var updatedServices = services.slice(0)
          var service = updatedServices[threat.targetIndex]
          if (service && service.alive && service.name !== "BOOT" && serviceOnline("BOOT") && bootRecoveryAvailable) {
            bootRecoveryAvailable = false
            statusMessage = "BOOT ROLLBACK // " + service.name + " IMPACT REVERSED"
            impactFlash = 0.18
            addExplosion(threat.tx, threat.ty, 42, "rollback", 1)
            shell.play(waveSound)
            return
          }
          if (service && service.alive) updatedServices[threat.targetIndex] = { x: service.x, alive: false, name: service.name }
          services = updatedServices
          statusMessage = service ? service.name + " OFFLINE // PAYLOAD IMPACT" : "SERVICE OFFLINE"
        } else {
          var updatedBatteries = batteries.slice(0)
          var battery = updatedBatteries[threat.targetIndex]
          if (battery && battery.alive) updatedBatteries[threat.targetIndex] = { x: battery.x, alive: false, ammo: 0 }
          batteries = updatedBatteries
          statusMessage = "FIREWALL " + (threat.targetIndex + 1) + " OFFLINE"
        }
        impactFlash = 0.45
        addExplosion(threat.tx, threat.ty, 46, "impact", 1)
        shell.play(impactSound)
      }

      function splitFork(threat, children) {
        var serviceChoices = []
        for (var i = 0; i < services.length; i++) if (services[i].alive) serviceChoices.push(i)
        if (!serviceChoices.length) return
        for (var child = 0; child < 2; child++) {
          var index = serviceChoices[(Math.floor(Math.random() * serviceChoices.length) + child) % serviceChoices.length]
          children.push({ sx: threat.x, sy: threat.y, x: threat.x, y: threat.y,
                          tx: services[index].x, ty: groundY - 12, targetKind: "service", targetIndex: index,
                          type: "exploit", speed: threat.speed * 1.12, split: true,
                          hp: 1, hitCooldown: 0 })
        }
        statusMessage = "FORK BOMB // PAYLOAD SPLIT"
      }

      function updateExplosions(dt) {
        for (var i = explosions.length - 1; i >= 0; i--) {
          var blast = explosions[i]
          blast.life += dt
          if (blast.life >= blast.duration) explosions.splice(i, 1)
        }
      }

      function updateInterceptors(dt) {
        var active = []
        for (var i = 0; i < interceptors.length; i++) {
          var shot = interceptors[i]
          var dx = shot.tx - shot.x
          var dy = shot.ty - shot.y
          var distance = Math.sqrt(dx * dx + dy * dy)
          var step = shot.speed * dt
          if (distance <= step) {
            addExplosion(shot.tx, shot.ty, 82, "quarantine", 1)
            shell.play(blastSound)
          } else {
            shot.x += dx / distance * step
            shot.y += dy / distance * step
            active.push(shot)
          }
        }
        interceptors = active
      }

      function updateThreats(dt) {
        var active = []
        var children = []
        var chainBlasts = []
        for (var i = 0; i < threats.length; i++) {
          var threat = threats[i]
          var interceptedBy = null
          if ((threat.hitCooldown || 0) <= 0) {
            for (var e = 0; e < explosions.length; e++) {
              var blast = explosions[e]
              if (blast.kind === "impact" || blast.kind === "rollback") continue
              var radius = explosionRadius(blast)
              var bx = threat.x - blast.x
              var by = threat.y - blast.y
              if (bx * bx + by * by <= radius * radius) { interceptedBy = blast; break }
            }
          }
          if (interceptedBy) {
            var chain = Math.max(game.chainLife > 0 ? game.currentChain + 1 : 1,
                                 Math.max(1, interceptedBy.combo))
            currentChain = chain
            var base = threat.type === "zeroDay" ? 420 : threat.type === "rootkit" ? 260 : threat.type === "fork" ? 180 : threat.type === "stealth" ? 210 : 120
            score += base * chain
            maxChain = Math.max(maxChain, chain)
            chainLife = 0.8
            chainBlasts.push({ x: threat.x, y: threat.y, combo: Math.min(9, chain + 1) })
            if (threat.type === "zeroDay" && threat.hp > 1) {
              chainText = "ZERO-DAY LAYER BREACHED // " + (threat.hp - 1) + " REMAIN"
              active.push({ sx: threat.x, sy: threat.y, x: threat.x, y: threat.y,
                            tx: threat.tx, ty: threat.ty, targetKind: threat.targetKind,
                            targetIndex: threat.targetIndex, type: threat.type,
                            speed: threat.speed, split: threat.split, hp: threat.hp - 1,
                            hitCooldown: 1.35 })
              statusMessage = "ZERO-DAY MUTATING // REACQUIRE TARGET"
            } else {
              threatsDestroyed += 1
              chainText = chain > 1 ? "CHAIN x" + chain + " // +" + (base * chain) : "THREAT QUARANTINED // +" + base
            }
            continue
          }

          var step = threat.speed * dt
          var nextHitCooldown = Math.max(0, (threat.hitCooldown || 0) - dt)
          if (threat.type === "fork" && !threat.split) {
            var forkY = threat.y + step
            if (forkY >= 205) {
              splitFork({ x: threat.x, y: 205, speed: threat.speed }, children)
            } else {
              threat.y = forkY
              threat.hitCooldown = nextHitCooldown
              active.push(threat)
            }
            continue
          }
          var dx = threat.tx - threat.x
          var dy = threat.ty - threat.y
          var distance = Math.sqrt(dx * dx + dy * dy)
          if (distance <= step) {
            destroyTarget(threat)
            continue
          }
          threat.x += dx / distance * step
          threat.y += dy / distance * step
          threat.hitCooldown = nextHitCooldown
          active.push(threat)
        }
        for (var c = 0; c < children.length; c++) active.push(children[c])
        threats = active
        for (var b = 0; b < chainBlasts.length; b++) addExplosion(chainBlasts[b].x, chainBlasts[b].y, 58, "chain", chainBlasts[b].combo)
      }

      function beginWaveClear() {
        if (mode !== "playing") return
        var homeBonus = serviceOnline("HOME") ? 700 : 0
        var serviceBonus = onlineServices * 350 + homeBonus
        var ammoBonus = totalAmmo * 55
        if (onlineServices === services.length) perfectWaves += 1
        score += serviceBonus + ammoBonus
        interceptors = []
        mode = "waveclear"
        transitionLife = 2.0
        statusMessage = "WAVE SECURED // SERVICES +" + serviceBonus + " // RULES +" + ammoBonus
        shell.play(waveSound)
      }

      function finishRun() {
        leftHeld = rightHeld = upHeld = downHeld = false
        if (arcadeData.qualifies(score)) {
          initialsInput = arcadeData.defaultInitials
          initialsPristine = true
          mode = "initials"
        } else {
          recordRun(arcadeData.defaultInitials || "---")
          mode = "gameover"
        }
      }

      function recordRun(initials) {
        arcadeData.recordScore({ score: score, initials: initials, difficulty: "core", stage: wave,
                                 services: onlineServices, threats: threatsDestroyed,
                                 shots: shotsFired, accuracy: shotsFired > 0 ? Math.round(threatsDestroyed * 100 / shotsFired) : 0,
                                 maxChain: maxChain, perfectWaves: perfectWaves })
      }

      function submitInitials() {
        var initials = arcadeData.cleanInitials(initialsInput)
        if (initials) arcadeData.patchConfig({ initials: initials })
        recordRun(initials || "---")
        if (shell.circuitMode) { window.visible = false; return }
        modeBeforeScores = "gameover"
        mode = "scores"
      }

      function openScores() {
        modeBeforeScores = mode
        mode = "scores"
      }

      function tick(dt) {
        animationTime += dt
        impactFlash = Math.max(0, impactFlash - dt)
        chainLife = Math.max(0, chainLife - dt)
        if (chainLife <= 0) currentChain = 0
        if (mode !== "playing") return

        for (var cooldown = 0; cooldown < firewallCooldowns.length; cooldown++)
          firewallCooldowns[cooldown] = Math.max(0, firewallCooldowns[cooldown] - dt)
        launchBusCooldown = Math.max(0, launchBusCooldown - dt)

        var reticleSpeed = (serviceOnline("SHELL") ? 285 : 220) * dt
        if (leftHeld) crosshairX -= reticleSpeed
        if (rightHeld) crosshairX += reticleSpeed
        if (upHeld) crosshairY -= reticleSpeed
        if (downHeld) crosshairY += reticleSpeed
        crosshairX = Math.max(22, Math.min(worldWidth - 22, crosshairX))
        crosshairY = Math.max(42, Math.min(groundY - 62, crosshairY))

        spawnCooldown -= dt
        if (spawnedThreats < waveThreats && spawnCooldown <= 0) {
          var salvoOrigin = 55 + Math.random() * 890
          var zeroDaySiege = wave % 5 === 0 && spawnedThreats === 0
          var salvo = spawnedThreats >= 2 && spawnedThreats + 1 < waveThreats && spawnedThreats % 4 === 2
          spawnThreat(zeroDaySiege ? "zeroDay" : undefined, zeroDaySiege ? 500 : salvoOrigin, -18)
          spawnedThreats += 1
          if (zeroDaySiege) {
            spawnCooldown = 1.1
            statusMessage = "ZERO-DAY SIEGE // THREE LAYERS DETECTED"
          } else if (salvo) {
            spawnThreat("exploit", Math.max(30, Math.min(970, salvoOrigin + (Math.random() < 0.5 ? -34 : 34))), -34)
            spawnedThreats += 1
            spawnCooldown = 0.32
            statusMessage = "THREAT SALVO // CHAIN WINDOW OPEN"
          } else {
            spawnCooldown = Math.max(0.34, 1.18 - wave * 0.065) * (0.72 + Math.random() * 0.58)
          }
        }
        updateExplosions(dt)
        updateInterceptors(dt)
        updateThreats(dt)
        if (onlineServices <= 0) { finishRun(); return }
        if (spawnedThreats >= waveThreats && threats.length === 0) beginWaveClear()
      }

      function nudgeReticle(dx, dy) {
        crosshairX = Math.max(22, Math.min(worldWidth - 22, crosshairX + dx))
        crosshairY = Math.max(42, Math.min(groundY - 62, crosshairY + dy))
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
        if (mode !== "playing") { event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) { leftHeld = true; nudgeReticle(-8, 0) }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) { rightHeld = true; nudgeReticle(8, 0) }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) { upHeld = true; nudgeReticle(0, -8) }
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) { downHeld = true; nudgeReticle(0, 8) }
        else if (event.key === Qt.Key_Space) fireAt(crosshairX, crosshairY)
        else if (event.key === Qt.Key_1) selectedBattery = 0
        else if (event.key === Qt.Key_2) selectedBattery = 1
        else if (event.key === Qt.Key_3) selectedBattery = 2
        else if (event.key === Qt.Key_0) selectedBattery = -1
        else if (event.key === Qt.Key_P) mode = "paused"
        else if (event.key === Qt.Key_H) openScores()
        else if (event.key === Qt.Key_R) startRun()
        else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
        event.accepted = true
      }

      Keys.onReleased: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) leftHeld = false
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) rightHeld = false
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) upHeld = false
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) downHeld = false
        event.accepted = true
      }

      Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: {
          var now = Date.now()
          var dt = Math.max(0.001, Math.min(0.05, (now - game.lastTickMs) / 1000))
          game.lastTickMs = now
          game.tick(dt)
          if (game.mode === "waveintro" || game.mode === "waveclear") {
            game.transitionLife = Math.max(0, game.transitionLife - dt)
            if (game.transitionLife <= 0) {
              if (game.mode === "waveclear") game.advanceWave()
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
          height: 90
          color: theme.surface
          border.color: theme.muted
          border.width: 1
          Row {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            Column {
              width: parent.width * 0.40
              anchors.verticalCenter: parent.verticalCenter
              Text { text: "OMACADE // " + shell.cabinet.shortTitle; color: theme.accent; font.pixelSize: 20; font.bold: true; font.letterSpacing: 1.5 }
              Text { text: game.zoneName + "/DEFENSE/WAVE-" + ("0" + game.wave).slice(-2); color: theme.green; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.statusMessage; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true; elide: Text.ElideRight; width: parent.width - 12 }
            }
            Repeater {
              model: [
                { label: "SCORE", value: game.score },
                { label: "SERVICES", value: game.onlineServices + "/6" },
                { label: "RULES", value: game.totalAmmo },
                { label: "CHAIN", value: "x" + Math.max(1, game.maxChain) }
              ]
              delegate: Column {
                width: (parent.width * 0.60) / 4
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.label; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
                Text { text: modelData.value; color: modelData.label === "SERVICES" && game.onlineServices <= 2 ? theme.red : modelData.label === "RULES" && game.totalAmmo <= 5 ? theme.yellow : theme.foreground; font.pixelSize: 18; font.family: "monospace"; font.bold: true }
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
          clip: true

          Canvas {
            id: worldCanvas
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * game.worldAspect)
            height: width / game.worldAspect
            renderStrategy: Canvas.Threaded
            onPaint: {
              var context = getContext("2d")
              context.reset()
              context.fillStyle = theme.background
              context.fillRect(0, 0, width, height)
              var sx = width / game.worldWidth
              var sy = height / game.worldHeight
              context.save()
              context.scale(sx, sy)

              var skyGradient = context.createLinearGradient(0, 0, 0, game.groundY)
              skyGradient.addColorStop(0, theme.background)
              skyGradient.addColorStop(1, theme.surface)
              context.fillStyle = skyGradient
              context.fillRect(0, 0, game.worldWidth, game.groundY)

              for (var star = 0; star < game.stars.length; star++) {
                var point = game.stars[star]
                context.globalAlpha = 0.24 + 0.38 * (0.5 + 0.5 * Math.sin(game.animationTime * 1.8 + point.phase))
                context.fillStyle = theme.foreground
                context.fillRect(point.x, point.y, star % 11 === 0 ? 2 : 1, star % 11 === 0 ? 2 : 1)
              }
              context.globalAlpha = 1

              context.strokeStyle = theme.muted
              context.globalAlpha = 0.09
              context.lineWidth = 1
              context.beginPath()
              for (var gridX = 0; gridX <= game.worldWidth; gridX += 50) {
                context.moveTo(gridX, 35); context.lineTo(gridX, game.groundY)
              }
              for (var gridY = 45; gridY < game.groundY; gridY += 50) {
                context.moveTo(0, gridY); context.lineTo(game.worldWidth, gridY)
              }
              context.stroke()
              context.globalAlpha = 1

              for (var t = 0; t < game.threats.length; t++) {
                var threat = game.threats[t]
                var threatColor = threat.type === "zeroDay" ? theme.red : threat.type === "fork" ? theme.orange : threat.type === "stealth" ? theme.accent : threat.type === "rootkit" ? theme.red : theme.yellow
                var threatAlpha = threat.type === "stealth" ? 0.22 + 0.7 * Math.abs(Math.sin(game.animationTime * 2.6 + t)) : 0.92
                context.globalAlpha = threatAlpha * 0.14
                context.strokeStyle = threatColor
                context.lineWidth = threat.type === "zeroDay" ? 11 : threat.type === "rootkit" ? 9 : 7
                context.beginPath(); context.moveTo(threat.sx, threat.sy); context.lineTo(threat.x, threat.y); context.stroke()
                context.globalAlpha = threatAlpha * 0.72
                context.lineWidth = threat.type === "zeroDay" ? 4 : threat.type === "rootkit" ? 3 : 2.5
                context.beginPath(); context.moveTo(threat.sx, threat.sy); context.lineTo(threat.x, threat.y); context.stroke()
                context.globalAlpha = threatAlpha * 0.9
                context.strokeStyle = theme.foreground
                context.lineWidth = 0.8
                context.beginPath(); context.moveTo(threat.sx, threat.sy); context.lineTo(threat.x, threat.y); context.stroke()
                context.globalAlpha = threatAlpha
                if (threat.type === "zeroDay") {
                  context.save()
                  context.translate(threat.x, threat.y)
                  context.rotate(game.animationTime * 0.7)
                  context.fillStyle = theme.surface
                  context.strokeStyle = theme.red
                  context.lineWidth = 4
                  context.beginPath()
                  for (var edge = 0; edge < 6; edge++) {
                    var edgeAngle = Math.PI / 3 * edge
                    var edgeX = Math.cos(edgeAngle) * 17
                    var edgeY = Math.sin(edgeAngle) * 17
                    if (edge === 0) context.moveTo(edgeX, edgeY); else context.lineTo(edgeX, edgeY)
                  }
                  context.closePath(); context.fill(); context.stroke()
                  context.rotate(-game.animationTime * 1.4)
                  context.strokeStyle = theme.orange; context.lineWidth = 2
                  context.beginPath(); context.arc(0, 0, 8, 0, Math.PI * 2); context.stroke()
                  context.restore()
                  for (var layer = 0; layer < 3; layer++) {
                    context.fillStyle = layer < threat.hp ? theme.red : theme.muted
                    context.globalAlpha = layer < threat.hp ? 1 : 0.24
                    context.fillRect(threat.x - 11 + layer * 9, threat.y + 24, 5, 3)
                  }
                  context.globalAlpha = threatAlpha
                } else if (threat.type === "fork") {
                  context.fillStyle = threatColor
                  context.fillRect(threat.x - 4, threat.y - 8, 8, 11)
                  context.strokeStyle = theme.orange; context.lineWidth = 3
                  context.beginPath()
                  context.moveTo(threat.x, threat.y - 8)
                  context.lineTo(threat.x, threat.y + 3)
                  context.lineTo(threat.x - 8, threat.y + 10)
                  context.moveTo(threat.x, threat.y + 3)
                  context.lineTo(threat.x + 8, threat.y + 10)
                  context.stroke()
                } else {
                  context.save()
                  context.translate(threat.x, threat.y)
                  context.rotate(Math.PI * 0.25)
                  context.fillStyle = threatColor
                  var payloadSize = threat.type === "rootkit" ? 10 : 7
                  context.fillRect(-payloadSize / 2, -payloadSize / 2, payloadSize, payloadSize)
                  context.fillStyle = theme.background
                  context.fillRect(-payloadSize * 0.2, -payloadSize * 0.2, payloadSize * 0.4, payloadSize * 0.4)
                  context.restore()
                }
                if (threat.y > game.groundY - 165) {
                  var targetPulse = 8 + 3 * Math.sin(game.animationTime * 12 + t)
                  context.globalAlpha = 0.34
                  context.strokeStyle = threatColor
                  context.lineWidth = 2
                  context.beginPath(); context.arc(threat.tx, game.groundY - 47, targetPulse, 0, Math.PI * 2); context.stroke()
                }
              }
              context.globalAlpha = 1

              for (var shot = 0; shot < game.interceptors.length; shot++) {
                var interceptor = game.interceptors[shot]
                context.globalAlpha = 0.16
                context.strokeStyle = theme.accent
                context.lineWidth = 9
                context.beginPath(); context.moveTo(interceptor.sx, interceptor.sy); context.lineTo(interceptor.x, interceptor.y); context.stroke()
                context.globalAlpha = 0.95
                context.lineWidth = 3
                context.beginPath(); context.moveTo(interceptor.sx, interceptor.sy); context.lineTo(interceptor.x, interceptor.y); context.stroke()
                context.strokeStyle = theme.foreground
                context.lineWidth = 1
                context.beginPath(); context.moveTo(interceptor.sx, interceptor.sy); context.lineTo(interceptor.x, interceptor.y); context.stroke()
                context.globalAlpha = 0.28
                context.fillStyle = theme.accent
                context.beginPath(); context.arc(interceptor.x, interceptor.y, 7, 0, Math.PI * 2); context.fill()
                context.globalAlpha = 1
                context.fillStyle = theme.foreground
                context.beginPath(); context.arc(interceptor.x, interceptor.y, 2.8, 0, Math.PI * 2); context.fill()
              }

              for (var e = 0; e < game.explosions.length; e++) {
                var blast = game.explosions[e]
                var radius = game.explosionRadius(blast)
                var blastColor = blast.kind === "impact" ? theme.red : blast.kind === "rollback" ? theme.green : blast.kind === "chain" ? theme.yellow : theme.accent
                context.globalAlpha = blast.kind === "impact" ? 0.18 : 0.12
                context.fillStyle = blastColor
                context.beginPath(); context.arc(blast.x, blast.y, radius, 0, Math.PI * 2); context.fill()
                context.globalAlpha = 0.82
                context.strokeStyle = blastColor
                context.lineWidth = blast.kind === "chain" ? 4 : 3
                context.beginPath(); context.arc(blast.x, blast.y, radius, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 0.42
                context.lineWidth = 1
                context.beginPath(); context.arc(blast.x, blast.y, radius * 0.72, 0, Math.PI * 2); context.stroke()
              }
              context.globalAlpha = 1

              context.fillStyle = theme.surfaceRaised
              context.fillRect(0, game.groundY, game.worldWidth, game.worldHeight - game.groundY)
              context.strokeStyle = theme.green
              context.globalAlpha = 0.7
              context.lineWidth = 3
              context.beginPath(); context.moveTo(0, game.groundY); context.lineTo(game.worldWidth, game.groundY); context.stroke()
              context.globalAlpha = 1

              for (var s = 0; s < game.services.length; s++) {
                var service = game.services[s]
                var serviceX = service.x - 35
                context.fillStyle = service.alive ? theme.surface : theme.background
                context.strokeStyle = service.alive ? theme.green : theme.red
                context.lineWidth = service.alive ? 2 : 1
                context.fillRect(serviceX, game.groundY - 43, 70, 38)
                context.strokeRect(serviceX, game.groundY - 43, 70, 38)
                for (var rack = 0; rack < 3; rack++) {
                  context.fillStyle = service.alive ? (rack % 2 ? theme.accent : theme.green) : theme.muted
                  context.globalAlpha = service.alive ? 0.75 : 0.2
                  context.fillRect(serviceX + 8, game.groundY - 35 + rack * 9, 54, 4)
                }
                context.globalAlpha = 1
                context.fillStyle = service.alive ? theme.foreground : theme.red
                context.font = "bold 10px monospace"
                context.textAlign = "center"
                context.fillText(service.name, service.x, game.groundY + 17)
                var capability = game.serviceCapabilities[s]
                if (service.name === "BOOT" && service.alive && !game.bootRecoveryAvailable) capability = "SPENT"
                context.fillStyle = service.alive ? (capability === "SPENT" ? theme.orange : theme.green) : theme.red
                context.font = "bold 7px monospace"
                context.fillText(service.alive ? capability : "OFFLINE", service.x, game.groundY + 30)
                if (!service.alive) {
                  context.strokeStyle = theme.red; context.lineWidth = 3
                  context.beginPath(); context.moveTo(serviceX + 8, game.groundY - 38); context.lineTo(serviceX + 62, game.groundY - 9); context.stroke()
                }
              }

              for (var b = 0; b < game.batteries.length; b++) {
                var battery = game.batteries[b]
                var batteryQueue = game.inFlightForBattery(b)
                context.globalAlpha = battery.alive ? 1 : 0.24
                context.fillStyle = b === game.selectedBattery ? theme.yellow : theme.accent
                context.strokeStyle = b === game.selectedBattery ? theme.yellow : theme.foreground
                context.lineWidth = b === game.selectedBattery ? 3 : 2
                context.beginPath(); context.moveTo(battery.x - 26, game.groundY - 4); context.lineTo(battery.x, game.groundY - 38); context.lineTo(battery.x + 26, game.groundY - 4); context.closePath(); context.fill(); context.stroke()
                context.fillStyle = theme.background
                context.fillRect(battery.x - 12, game.groundY - 20, 24, 16)
                context.fillStyle = theme.foreground
                context.font = "bold 10px monospace"
                context.textAlign = "center"
                context.fillText(battery.alive ? battery.ammo : "X", battery.x, game.groundY - 8)
                context.fillStyle = theme.muted
                context.font = "bold 9px monospace"
                context.fillText("FW-" + (b + 1), battery.x, game.groundY + 31)
                if (battery.alive) {
                  context.fillStyle = theme.background
                  context.fillRect(battery.x - 21, game.groundY - 50, 42, 4)
                  context.fillStyle = game.firewallCooldowns[b] > 0 ? theme.orange : theme.green
                  var nodeReload = game.serviceOnline("NET") ? 0.24 : 0.34
                  context.fillRect(battery.x - 20, game.groundY - 49, 40 * (1 - game.firewallCooldowns[b] / nodeReload), 2)
                  for (var queue = 0; queue < 2; queue++) {
                    context.fillStyle = queue < batteryQueue ? theme.yellow : theme.muted
                    context.globalAlpha = queue < batteryQueue ? 0.9 : 0.25
                    context.beginPath(); context.arc(battery.x - 5 + queue * 10, game.groundY + 42, 2.5, 0, Math.PI * 2); context.fill()
                  }
                  context.globalAlpha = 1
                }
              }
              context.globalAlpha = 1

              if (game.mode === "playing") {
                var pulse = 9 + 3 * Math.sin(game.animationTime * 6)
                context.strokeStyle = game.totalAmmo > 0 ? theme.accent : theme.red
                context.lineWidth = 2
                context.beginPath(); context.arc(game.crosshairX, game.crosshairY, pulse, 0, Math.PI * 2); context.stroke()
                context.beginPath(); context.moveTo(game.crosshairX - 17, game.crosshairY); context.lineTo(game.crosshairX - 5, game.crosshairY); context.moveTo(game.crosshairX + 5, game.crosshairY); context.lineTo(game.crosshairX + 17, game.crosshairY); context.moveTo(game.crosshairX, game.crosshairY - 17); context.lineTo(game.crosshairX, game.crosshairY - 5); context.moveTo(game.crosshairX, game.crosshairY + 5); context.lineTo(game.crosshairX, game.crosshairY + 17); context.stroke()
              }
              context.restore()

              if (game.impactFlash > 0) {
                context.globalAlpha = Math.min(0.28, game.impactFlash)
                context.fillStyle = theme.red
                context.fillRect(0, 0, width, height)
                context.globalAlpha = 1
              }
            }
          }

          MouseArea {
            anchors.fill: worldCanvas
            hoverEnabled: true
            enabled: game.mode === "playing"
            cursorShape: enabled ? Qt.BlankCursor : Qt.ArrowCursor
            onPositionChanged: function(mouse) {
              game.crosshairX = mouse.x / width * game.worldWidth
              game.crosshairY = Math.max(42, Math.min(game.groundY - 62, mouse.y / height * game.worldHeight))
            }
            onPressed: function(mouse) {
              game.crosshairX = mouse.x / width * game.worldWidth
              game.crosshairY = Math.max(42, Math.min(game.groundY - 62, mouse.y / height * game.worldHeight))
              game.fireAt(game.crosshairX, game.crosshairY)
              game.forceActiveFocus()
            }
          }

          Rectangle {
            visible: game.chainLife > 0
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 18
            width: chainLabel.implicitWidth + 28
            height: 34
            radius: 6
            color: theme.surface
            border.color: game.maxChain > 2 ? theme.yellow : theme.accent
            border.width: 2
            opacity: Math.min(1, game.chainLife * 2)
            Text { id: chainLabel; anchors.centerIn: parent; text: game.chainText; color: game.maxChain > 2 ? theme.yellow : theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
          }

          Rectangle {
            visible: game.mode === "attract"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 650)
            height: Math.min(parent.height - 44, 430)
            radius: 12
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              width: parent.width - 58
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "OMACADE // CABINET " + shell.cabinet.number; color: theme.accent; font.pixelSize: 14; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.displayTitle; color: theme.foreground; font.pixelSize: 37; font.bold: true; font.letterSpacing: 3 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.tagline.toUpperCase(); color: theme.green; font.pixelSize: 13; font.family: "monospace" }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "DEFEND SIX CRITICAL SERVICES WITH THREE FIREWALL NODES.\nDETONATE QUARANTINE FIELDS AND CHAIN THREATS TOGETHER."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.3 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ONLINE SERVICES POWER YOUR DEFENSE  ·  LOSING ONE DISABLES ITS BOOST"; color: theme.green; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "FORKS SPLIT  ·  STEALTH PHASES  ·  ROOTKITS DIVE  ·  WAVE 5 ZERO-DAY"; color: theme.orange; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "MOUSE AIM / CLICK FIRE  ·  ARROWS AIM / SPACE FIRE"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "1 / 2 / 3 FIREWALL  ·  0 AUTO  ·  2 IN FLIGHT PER NODE"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "BEST " + arcadeData.bestScore + "   ·   FURTHEST WAVE " + arcadeData.highestStage; color: theme.yellow; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PRESS ENTER TO ARM"; color: theme.accent; font.pixelSize: 18; font.family: "monospace"; font.bold: true
                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.35; duration: 620 }
                  NumberAnimation { to: 1; duration: 620 }
                }
              }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "H RECORDS    Q QUIT"; color: theme.muted; font.pixelSize: 10; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.mode === "paused" || game.mode === "waveintro" || game.mode === "waveclear" || game.mode === "gameover"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 560)
            height: 160
            radius: 10
            color: theme.surface
            border.color: game.mode === "gameover" ? theme.red : game.mode === "waveclear" ? theme.green : theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 11
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "DEFENSE GRID PAUSED" : game.mode === "waveintro" ? game.zoneName + " // WAVE " + game.wave : game.mode === "waveclear" ? "WAVE SECURED" : "CORE SERVICES LOST"; color: game.mode === "gameover" ? theme.red : game.mode === "waveclear" ? theme.green : theme.accent; font.pixelSize: 25; font.bold: true; font.letterSpacing: 1.5 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "gameover" ? "SCORE " + game.score + (shell.circuitMode ? "  ·  ENTER RETURN TO CIRCUIT" : "  ·  ENTER TO REARM") : game.mode === "paused" ? "P TO RESUME" : game.statusMessage; color: theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
              Text { visible: game.mode === "waveintro"; anchors.horizontalCenter: parent.horizontalCenter; text: game.wave % 5 === 0 ? "ZERO-DAY SIEGE // THREE QUARANTINE HITS REQUIRED" : game.wave === 1 ? "EXPLOITS INBOUND" : game.wave === 2 ? "FORK BOMBS DETECTED" : game.wave === 3 ? "STEALTH PAYLOADS DETECTED" : "ROOTKIT TRAJECTORIES DETECTED"; color: game.wave % 5 === 0 ? theme.red : theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            visible: game.mode === "initials"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 470)
            height: 255
            radius: 10
            color: theme.surface
            border.color: theme.yellow
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 13
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NEW DEFENSE RECORD"; color: theme.yellow; font.pixelSize: 22; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SCORE " + game.score + "  //  WAVE " + game.wave; color: theme.foreground; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ENTER PILOT INITIALS"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: (game.initialsInput + "___").slice(0, 3); color: theme.accent; font.pixelSize: 43; font.family: "monospace"; font.bold: true; font.letterSpacing: 10 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "TYPE 3 CHARACTERS  ·  ENTER TO SAVE"; color: theme.muted; font.pixelSize: 10; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.mode === "scores"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 620)
            height: Math.min(parent.height - 40, 470)
            radius: 10
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.fill: parent
              anchors.margins: 24
              spacing: 8
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "CORE//COMMAND // TOP TEN"; color: theme.accent; font.pixelSize: 22; font.bold: true }
              Text { text: " #    PILOT       SCORE       WAVE   CHAIN"; color: theme.muted; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Repeater {
                model: 10
                delegate: Text {
                  property var row: index < arcadeData.scoreRows.length ? arcadeData.scoreRows[index] : null
                  width: parent.width
                  text: {
                    var rank = index < 9 ? " " + (index + 1) : "10"
                    var pilot = row ? (arcadeData.cleanInitials(row.initials) || "---") : "---"
                    var points = row ? ("       " + Math.round(Number(row.score || 0))).slice(-7) : "      -"
                    var rowWave = row ? ("  " + Math.max(1, Number(row.stage || 1))).slice(-2) : " -"
                    var chain = row ? "x" + Math.max(1, Number(row.maxChain || 1)) : "--"
                    return rank + "    " + (pilot + "        ").slice(0, 8) + "  " + points + "       " + rowWave + "      " + chain
                  }
                  color: row && index === 0 ? theme.yellow : row ? theme.foreground : theme.muted
                  font.pixelSize: 14; font.family: "monospace"; font.bold: row && index === 0
                }
              }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "H / ENTER / ESC  CLOSE"; color: theme.muted; font.pixelSize: 10; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.tooSmall
            anchors.fill: parent
            color: theme.background
            opacity: 0.97
            z: 40
            Column {
              anchors.centerIn: parent
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "DEFENSE DISPLAY TOO SMALL"; color: theme.red; font.pixelSize: 22; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Enlarge the cabinet for a 620 × 372 defense grid."; color: theme.foreground; font.pixelSize: 12; font.family: "monospace" }
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
            text: "MOUSE / ← ↑ ↓ → AIM    CLICK / SPACE FIRE    1 2 3 FIREWALL    0 AUTO    P PAUSE    H RECORDS    Q QUIT"
            color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true
          }
        }
      }
    }
  }
}
