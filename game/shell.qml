import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("lander")

  ArcadeTheme { id: arcadeTheme }
  ArcadeData { id: arcadeData; cabinetId: shell.cabinet.scoreKey }

  readonly property color background: arcadeTheme.background
  readonly property color surface: arcadeTheme.surface
  readonly property color surfaceRaised: arcadeTheme.surfaceRaised
  readonly property color foreground: arcadeTheme.foreground
  readonly property color muted: arcadeTheme.muted
  readonly property color accent: arcadeTheme.accent
  readonly property color green: arcadeTheme.green
  readonly property color yellow: arcadeTheme.yellow
  readonly property color orange: arcadeTheme.orange
  readonly property color red: arcadeTheme.red

  readonly property string difficulty: arcadeData.difficulty
  readonly property string defaultInitials: arcadeData.defaultInitials
  readonly property bool soundEnabled: arcadeData.soundEnabled
  readonly property var scoreRows: arcadeData.scoreRows
  readonly property int bestScore: arcadeData.bestScore
  readonly property int highestStage: arcadeData.highestStage
  readonly property int successfulLandings: arcadeData.completedRuns

  function cleanInitials(value) {
    return arcadeData.cleanInitials(value)
  }

  function qualifiesForHighScore(score) {
    return arcadeData.qualifies(score)
  }

  function saveDefaultInitials(initials) {
    var cleaned = arcadeData.cleanInitials(initials)
    if (cleaned) arcadeData.patchConfig({ initials: cleaned })
  }

  function setSound(enabled) {
    arcadeData.patchConfig({ sound: enabled })
    if (!enabled) engineSound.stop()
  }

  function playEffect(effect) {
    if (!soundEnabled) return
    effect.stop()
    effect.play()
  }

  function recordLanding(score, fuel, seconds, initials, stage) {
    arcadeData.recordScore({
      score: Math.round(score),
      initials: cleanInitials(initials) || "---",
      difficulty: difficulty,
      stage: Math.max(1, Math.round(Number(stage || 1))),
      fuel: Math.round(fuel * 10) / 10,
      time: Math.round(seconds * 10) / 10,
      at: new Date().toISOString()
    })
  }

  SoundEffect {
    id: engineSound
    source: Qt.resolvedUrl("assets/sfx/engine.wav")
    loops: SoundEffect.Infinite
    volume: 0.32
  }
  SoundEffect { id: rotateSound; source: Qt.resolvedUrl("assets/sfx/rotate.wav"); volume: 0.34 }
  SoundEffect { id: touchdownSound; source: Qt.resolvedUrl("assets/sfx/touchdown.wav"); volume: 0.62 }
  SoundEffect { id: crashSound; source: Qt.resolvedUrl("assets/sfx/crash.wav"); volume: 0.72 }
  SoundEffect { id: stageClearSound; source: Qt.resolvedUrl("assets/sfx/stage-clear.wav"); volume: 0.58 }
  SoundEffect { id: startSound; source: Qt.resolvedUrl("assets/sfx/start.wav"); volume: 0.48 }
  SoundEffect { id: cometSound; source: Qt.resolvedUrl("assets/sfx/comet.wav"); volume: 0.34 }

  FloatingWindow {
    id: window
    visible: true
    title: shell.cabinet.windowTitle
    color: shell.background
    implicitWidth: 960
    implicitHeight: 700
    minimumSize: Qt.size(720, 520)
    onVisibleChanged: if (!visible) Qt.quit()

    FocusScope {
      id: game
      anchors.fill: parent
      focus: true

      property var rules: ({
        cadet: { label: "CADET", gravity: 42, thrust: 96, fuel: 100, burn: 7.5, rotate: 105, safeVy: 34, safeVx: 25, safeAngle: 14, bonus: 600 },
        pilot: { label: "PILOT", gravity: 49, thrust: 106, fuel: 90, burn: 8.5, rotate: 100, safeVy: 28, safeVx: 20, safeAngle: 10, bonus: 1100 },
        ace: { label: "ACE", gravity: 56, thrust: 116, fuel: 80, burn: 9.5, rotate: 95, safeVy: 23, safeVx: 16, safeAngle: 7, bonus: 1800 }
      })[shell.difficulty]

      property real shipX: 0
      property real shipY: 0
      property real velocityX: 0
      property real velocityY: 0
      property real angle: 0
      property real fuel: rules.fuel
      property real elapsed: 0
      property string flightState: "flying"
      property string resultMessage: ""
      property int score: 0
      property int stage: 1
      property bool attractMode: true
      property bool paused: false
      property bool leftHeld: false
      property bool rightHeld: false
      property bool thrustHeld: false
      property var terrain: []
      property var pads: []
      property var stars: []
      property var shootingStars: []
      property var particles: []
      property real skyTime: 0
      property real blastLife: 0
      property real blastMaxLife: 0.55
      property real blastX: 0
      property real blastY: 0
      property real crashVisualLife: 0
      property real crashSpin: 0
      property real terrainStep: 12
      readonly property real footOffsetX: 27
      readonly property real footOffsetY: 33
      property real worldWidth: 0
      property real worldHeight: 0
      property double previousTick: 0
      property bool initialized: false
      property bool showScores: false
      property bool enteringInitials: false
      property string initialsInput: ""
      property bool initialsPristine: true
      readonly property bool viewportTooSmall: playfield.width < 600 || playfield.height < 300

      Component.onCompleted: {
        forceActiveFocus()
        Qt.callLater(prepareAttract)
      }

      onThrustHeldChanged: syncEngineSound()
      onFuelChanged: if (fuel <= 0) syncEngineSound()
      onPausedChanged: syncEngineSound()
      onFlightStateChanged: syncEngineSound()
      onAttractModeChanged: syncEngineSound()

      Keys.onPressed: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (enteringInitials) {
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) submitInitials()
          else if (event.key === Qt.Key_Backspace) {
            initialsInput = initialsPristine ? "" : initialsInput.slice(0, -1)
            initialsPristine = false
          } else {
            var typed = shell.cleanInitials(event.text)
            if (typed && initialsInput.length < 3) {
              if (initialsPristine) initialsInput = ""
              initialsPristine = false
              initialsInput = (initialsInput + typed).slice(0, 3)
            }
          }
          event.accepted = true
          return
        }
        if (showScores) {
          if (event.key === Qt.Key_H || event.key === Qt.Key_Escape || event.key === Qt.Key_Q || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            showScores = false
          event.accepted = true
          return
        }
        if (attractMode) {
          if (event.key === Qt.Key_1) chooseDifficulty("cadet")
          else if (event.key === Qt.Key_2) chooseDifficulty("pilot")
          else if (event.key === Qt.Key_3) chooseDifficulty("ace")
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) cycleAttractDifficulty(-1)
          else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) cycleAttractDifficulty(1)
          else if (event.key === Qt.Key_H) showScores = true
          else if (event.key === Qt.Key_M) toggleSound()
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) launchFromAttract()
          else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
          leftHeld = true
          shell.playEffect(rotateSound)
        }
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
          rightHeld = true
          shell.playEffect(rotateSound)
        }
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W || event.key === Qt.Key_Space) thrustHeld = true
        else if (event.key === Qt.Key_1) chooseDifficulty("cadet")
        else if (event.key === Qt.Key_2) chooseDifficulty("pilot")
        else if (event.key === Qt.Key_3) chooseDifficulty("ace")
        else if (event.key === Qt.Key_H) showScores = true
        else if (event.key === Qt.Key_M) toggleSound()
        else if (event.key === Qt.Key_P) paused = !paused
        else if (event.key === Qt.Key_R) startFlight()
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && flightState === "landed") advanceStage()
        else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && flightState !== "flying") startFlight()
        else if (event.key === Qt.Key_Q || event.key === Qt.Key_Escape) window.visible = false
        event.accepted = true
      }

      Keys.onReleased: function(event) {
        if (event.isAutoRepeat) { event.accepted = true; return }
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) leftHeld = false
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) rightHeld = false
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W || event.key === Qt.Key_Space) thrustHeld = false
        event.accepted = true
      }

      function normalizeAngle(value) {
        var next = value % 360
        if (next > 180) next -= 360
        if (next < -180) next += 360
        return next
      }

      function chooseDifficulty(next) {
        if (["cadet", "pilot", "ace"].indexOf(next) < 0) return
        arcadeData.patchConfig({ difficulty: next })
        stage = 1
        shell.playEffect(rotateSound)
        if (!attractMode) startFlight()
      }

      function cycleAttractDifficulty(direction) {
        var names = ["cadet", "pilot", "ace"]
        var index = names.indexOf(shell.difficulty)
        chooseDifficulty(names[(index + direction + names.length) % names.length])
      }

      function toggleSound() {
        shell.setSound(!shell.soundEnabled)
        if (shell.soundEnabled) shell.playEffect(startSound)
      }

      function syncEngineSound() {
        var shouldPlay = shell.soundEnabled && thrustHeld && fuel > 0 &&
          flightState === "flying" && !paused && !attractMode
        if (shouldPlay && !engineSound.playing) engineSound.play()
        else if (!shouldPlay && engineSound.playing) engineSound.stop()
      }

      function prepareAttract() {
        stage = 1
        startFlight()
        attractMode = true
        flightState = "ready"
        thrustHeld = false
      }

      function launchFromAttract() {
        shell.playEffect(startSound)
        startFlight()
      }

      function initialsDisplay() {
        return (initialsInput + "___").slice(0, 3).split("").join(" ")
      }

      function submitInitials() {
        var initials = shell.cleanInitials(initialsInput)
        if (initials) shell.saveDefaultInitials(initials)
        shell.recordLanding(score, fuel, elapsed, initials || "---", stage)
        enteringInitials = false
        showScores = true
      }

      function advanceStage() {
        stage += 1
        startFlight()
      }

      function sculptPadHazards(points, first, last, padY, pressure, height, premium) {
        if (pressure <= 0) return
        var reach = Math.min(4 + Math.floor(pressure / 2) + (premium ? 1 : 0), 10)
        var strength = height * (0.022 + pressure * 0.0048) * (premium ? 1.35 : 0.72)
        for (var offset = 1; offset <= reach; offset++) {
          var fade = 1 - (offset - 1) / reach * 0.58
          var tooth = offset % 3 === 0 ? 0.58 : -(offset % 2 === 0 ? 0.62 : 1.0)
          var delta = strength * fade * tooth * (0.82 + Math.random() * 0.36)
          var left = first - offset
          var right = last + offset
          if (left >= 0)
            points[left] = Math.max(height * 0.47, Math.min(height * 0.95, padY + delta))
          if (right < points.length) {
            var mirrorDelta = strength * fade * (offset % 2 === 0 ? -1.0 : tooth) * (0.82 + Math.random() * 0.36)
            points[right] = Math.max(height * 0.47, Math.min(height * 0.95, padY + mirrorDelta))
          }
        }
      }

      function makeTerrain() {
        var width = playfield.width
        var height = playfield.height
        worldWidth = width
        worldHeight = height
        var count = Math.ceil(width / terrainStep) + 1
        var points = []
        var pressure = Math.min(stage - 1, 12)
        var level = height * 0.78
        for (var i = 0; i < count; i++) {
          level += (Math.random() - 0.5) * (22 + pressure * 1.6)
          level = Math.max(height * Math.max(0.54, 0.64 - pressure * 0.008),
                           Math.min(height * Math.min(0.93, 0.88 + pressure * 0.004), level))
          points.push(level)
        }

        // From stage two onward, carve broad crater bowls and lift sharper
        // mountain peaks before flattening the landing pads over the result.
        var featureCount = pressure > 0 ? Math.min(2 + Math.floor(pressure / 2), 7) : 0
        for (var feature = 0; feature < featureCount; feature++) {
          var center = Math.floor(count * (0.08 + Math.random() * 0.84))
          var radius = 3.5 + Math.random() * (3.5 + pressure * 0.22)
          var magnitude = height * (0.035 + pressure * 0.006) * (0.75 + Math.random() * 0.5)
          var crater = feature % 2 === 0
          var firstPoint = Math.max(0, Math.floor(center - radius))
          var lastPoint = Math.min(count - 1, Math.ceil(center + radius))
          for (var point = firstPoint; point <= lastPoint; point++) {
            var distance = Math.abs(point - center) / radius
            var shape = Math.pow(Math.cos(distance * Math.PI / 2), 2)
            points[point] += (crater ? 1 : -1) * magnitude * shape
            points[point] = Math.max(height * 0.50, Math.min(height * 0.94, points[point]))
          }
        }

        var widePadWidth = Math.max(72, width * (0.15 - pressure * 0.006))
        var narrowPadWidth = Math.max(60, width * (0.10 - pressure * 0.0045))
        var generatedPads = [
          { x1: width * 0.215 - widePadWidth / 2, x2: width * 0.215 + widePadWidth / 2,
            multiplier: 2 + Math.floor(pressure / 4) },
          { x1: width * 0.75 - narrowPadWidth / 2, x2: width * 0.75 + narrowPadWidth / 2,
            multiplier: 3 + Math.floor(pressure / 4) }
        ]
        for (var p = 0; p < generatedPads.length; p++) {
          var pad = generatedPads[p]
          var first = Math.max(0, Math.floor(pad.x1 / terrainStep))
          var last = Math.min(points.length - 1, Math.ceil(pad.x2 / terrainStep))
          var padY = points[first]
          for (var j = first; j <= last; j++) padY = Math.min(padY, points[j])
          for (var k = first; k <= last; k++) points[k] = padY
          pad.y = padY
          sculptPadHazards(points, first, last, padY, pressure, height, p === 1)
        }
        terrain = points
        pads = generatedPads
        var generatedStars = []
        for (var s = 0; s < 55; s++) {
          generatedStars.push({
            x: Math.random() * width,
            y: 20 + Math.random() * height * 0.52,
            radius: Math.random() < 0.12 ? 1.8 : 0.8,
            alpha: 0.25 + Math.random() * 0.65,
            phase: Math.random() * Math.PI * 2,
            twinkle: 0.8 + Math.random() * 2.0,
            twinkleStrength: Math.random() < 0.32 ? 0.68 + Math.random() * 0.22 : 0.28 + Math.random() * 0.24
          })
        }
        stars = generatedStars
        shootingStars = []
        terrainCanvas.requestPaint()
      }

      function resizeWorld() {
        var newWidth = playfield.width
        var newHeight = playfield.height
        if (viewportTooSmall) return
        if (!initialized || worldWidth <= 0 || worldHeight <= 0 || !terrain.length) {
          startFlight()
          return
        }
        if (Math.abs(newWidth - worldWidth) < 1 && Math.abs(newHeight - worldHeight) < 1) return

        var scaleX = newWidth / worldWidth
        var scaleY = newHeight / worldHeight
        var oldTerrain = terrain.slice(0)
        var oldStep = terrainStep
        var count = Math.ceil(newWidth / terrainStep) + 1
        var resizedTerrain = []
        for (var i = 0; i < count; i++) {
          var oldX = (i * terrainStep) / scaleX
          var position = oldX / oldStep
          var left = Math.max(0, Math.min(oldTerrain.length - 1, Math.floor(position)))
          var right = Math.min(oldTerrain.length - 1, left + 1)
          var fraction = position - left
          resizedTerrain.push((oldTerrain[left] * (1 - fraction) + oldTerrain[right] * fraction) * scaleY)
        }

        var resizedPads = []
        for (var p = 0; p < pads.length; p++) {
          resizedPads.push({
            x1: pads[p].x1 * scaleX,
            x2: pads[p].x2 * scaleX,
            y: pads[p].y * scaleY,
            multiplier: pads[p].multiplier
          })
        }
        var resizedStars = []
        for (var s = 0; s < stars.length; s++) {
          resizedStars.push({
            x: stars[s].x * scaleX,
            y: stars[s].y * scaleY,
            radius: stars[s].radius,
            alpha: stars[s].alpha,
            phase: stars[s].phase,
            twinkle: stars[s].twinkle,
            twinkleStrength: stars[s].twinkleStrength
          })
        }
        var resizedShootingStars = []
        for (var t = 0; t < shootingStars.length; t++) {
          resizedShootingStars.push({
            x: shootingStars[t].x * scaleX,
            y: shootingStars[t].y * scaleY,
            vx: shootingStars[t].vx * scaleX,
            vy: shootingStars[t].vy * scaleY,
            life: shootingStars[t].life,
            maxLife: shootingStars[t].maxLife,
            length: shootingStars[t].length * scaleX,
            comet: shootingStars[t].comet
          })
        }

        shipX *= scaleX
        shipY *= scaleY
        terrain = resizedTerrain
        pads = resizedPads
        stars = resizedStars
        shootingStars = resizedShootingStars
        worldWidth = newWidth
        worldHeight = newHeight
        terrainCanvas.requestPaint()
      }

      function groundAt(x) {
        if (!terrain.length) return playfield.height
        var position = Math.max(0, Math.min(playfield.width, x)) / terrainStep
        var left = Math.max(0, Math.min(terrain.length - 1, Math.floor(position)))
        var right = Math.min(terrain.length - 1, left + 1)
        var fraction = position - left
        return terrain[left] * (1 - fraction) + terrain[right] * fraction
      }

      function startFlight() {
        if (viewportTooSmall) return
        stageClearDelay.stop()
        attractMode = false
        makeTerrain()
        shipX = playfield.width * 0.5
        shipY = 82
        velocityX = (Math.random() - 0.5) * 15
        velocityY = 0
        angle = 0
        fuel = rules.fuel
        elapsed = 0
        score = 0
        flightState = "flying"
        resultMessage = ""
        paused = false
        showScores = false
        enteringInitials = false
        particles = []
        blastLife = 0
        crashVisualLife = 0
        crashSpin = 0
        leftHeld = false
        rightHeld = false
        thrustHeld = false
        previousTick = Date.now()
        initialized = true
        forceActiveFocus()
      }

      function padUnder(leftFoot, rightFoot) {
        var left = Math.min(leftFoot, rightFoot)
        var right = Math.max(leftFoot, rightFoot)
        for (var i = 0; i < pads.length; i++) {
          if (left >= pads[i].x1 && right <= pads[i].x2) return pads[i]
        }
        return null
      }

      function landingGear() {
        var radians = angle * Math.PI / 180
        var cosine = Math.cos(radians)
        var sine = Math.sin(radians)
        return {
          left: {
            x: shipX - footOffsetX * cosine - footOffsetY * sine,
            y: shipY - footOffsetX * sine + footOffsetY * cosine
          },
          right: {
            x: shipX + footOffsetX * cosine - footOffsetY * sine,
            y: shipY + footOffsetX * sine + footOffsetY * cosine
          }
        }
      }

      function spawnShootingStar() {
        if (viewportTooSmall || shootingStars.length >= 2) return
        var comet = Math.random() < 0.22
        var direction = Math.random() < 0.72 ? 1 : -1
        var speed = comet ? 190 + Math.random() * 60 : 300 + Math.random() * 130
        var downward = comet ? 0.28 + Math.random() * 0.12 : 0.34 + Math.random() * 0.18
        var duration = comet ? 1.7 : 0.9
        var next = shootingStars.slice(0)
        next.push({
          x: direction > 0 ? -30 : playfield.width + 30,
          y: 24 + Math.random() * playfield.height * 0.28,
          vx: speed * direction,
          vy: speed * downward,
          life: duration,
          maxLife: duration,
          length: comet ? 115 : 62 + Math.random() * 35,
          comet: comet
        })
        shootingStars = next
        if (comet) shell.playEffect(cometSound)
      }

      function updateSky(dt) {
        skyTime += dt
        if (!shootingStars.length) return
        var next = []
        for (var i = 0; i < shootingStars.length; i++) {
          var streak = shootingStars[i]
          var remaining = streak.life - dt
          if (remaining <= 0) continue
          next.push({
            x: streak.x + streak.vx * dt,
            y: streak.y + streak.vy * dt,
            vx: streak.vx,
            vy: streak.vy,
            life: remaining,
            maxLife: streak.maxLife,
            length: streak.length,
            comet: streak.comet
          })
        }
        shootingStars = next
      }

      function spawnLandingDust() {
        var gear = landingGear()
        var next = []
        for (var i = 0; i < 24; i++) {
          var foot = i % 2 === 0 ? gear.left : gear.right
          var outward = i % 2 === 0 ? -1 : 1
          var life = 0.48 + Math.random() * 0.42
          next.push({
            x: foot.x + (Math.random() - 0.5) * 7,
            y: foot.y - 2 - Math.random() * 3,
            vx: outward * (18 + Math.random() * 55) + (Math.random() - 0.5) * 18,
            vy: -14 - Math.random() * 42,
            life: life,
            maxLife: life,
            radius: 1.8 + Math.random() * 3.5,
            kind: "dust",
            rotation: 0
          })
        }
        particles = next
      }

      function spawnCrashParticles() {
        var next = []
        blastX = shipX
        blastY = shipY
        blastLife = blastMaxLife
        crashVisualLife = 0.85
        crashSpin = 0
        for (var i = 0; i < 38; i++) {
          var direction = Math.random() * Math.PI * 2
          var speed = 45 + Math.random() * 175
          var life = 0.42 + Math.random() * 0.72
          next.push({
            x: shipX + (Math.random() - 0.5) * 28,
            y: shipY + (Math.random() - 0.5) * 24,
            vx: Math.cos(direction) * speed,
            vy: Math.sin(direction) * speed - 20,
            life: life,
            maxLife: life,
            radius: 1.4 + Math.random() * 3.4,
            kind: i < 25 ? "spark" : "debris",
            rotation: Math.random() * Math.PI
          })
        }
        particles = next
      }

      function updateParticles(dt) {
        var next = []
        for (var i = 0; i < particles.length; i++) {
          var particle = particles[i]
          var remaining = particle.life - dt
          if (remaining <= 0) continue
          var gravity = particle.kind === "dust" ? 42 : 105
          next.push({
            x: particle.x + particle.vx * dt,
            y: particle.y + particle.vy * dt,
            vx: particle.vx * (particle.kind === "dust" ? 0.985 : 0.997),
            vy: particle.vy + gravity * dt,
            life: remaining,
            maxLife: particle.maxLife,
            radius: particle.radius,
            kind: particle.kind,
            rotation: particle.rotation + dt * 8
          })
        }
        particles = next
        blastLife = Math.max(0, blastLife - dt)
        if (crashVisualLife > 0) {
          crashVisualLife = Math.max(0, crashVisualLife - dt)
          crashSpin += 520 * dt
        }
      }

      function crash(message) {
        if (flightState !== "flying") return
        flightState = "crashed"
        resultMessage = message
        thrustHeld = false
        spawnCrashParticles()
        shell.playEffect(crashSound)
      }

      function updatePhysics(dt) {
        if (!initialized || viewportTooSmall || paused || showScores || flightState !== "flying") return
        elapsed += dt
        if (leftHeld !== rightHeld) {
          angle += (rightHeld ? 1 : -1) * rules.rotate * dt
          angle = normalizeAngle(angle)
        }
        var radians = angle * Math.PI / 180
        velocityY += rules.gravity * dt
        if (thrustHeld && fuel > 0) {
          velocityX += Math.sin(radians) * rules.thrust * dt
          velocityY -= Math.cos(radians) * rules.thrust * dt
          fuel = Math.max(0, fuel - rules.burn * dt)
        }
        shipX += velocityX * dt
        shipY += velocityY * dt

        if (shipX < 32 || shipX > playfield.width - 32 || shipY < -40) {
          crash("LOST TO THE VOID")
          return
        }

        var gear = landingGear()
        var leftSurface = groundAt(gear.left.x)
        var rightSurface = groundAt(gear.right.x)
        if (gear.left.y < leftSurface && gear.right.y < rightSurface) return

        var pad = padUnder(gear.left.x, gear.right.x)
        var landingAngle = Math.abs(normalizeAngle(angle))
        if (!pad) crash("MISSED THE PAD")
        else if (landingAngle > rules.safeAngle) crash("BAD ATTITUDE")
        else if (velocityY > rules.safeVy) crash("DESCENT TOO FAST")
        else if (Math.abs(velocityX) > rules.safeVx) crash("LATERAL SPEED TOO HIGH")
        else {
          flightState = "landed"
          shipY = pad.y - Math.max(gear.left.y - shipY, gear.right.y - shipY)
          thrustHeld = false
          spawnLandingDust()
          shell.playEffect(touchdownSound)
          stageClearDelay.restart()
          var precision = Math.max(0, 450 - Math.abs(velocityX) * 7 - velocityY * 5 - landingAngle * 12)
          score = Math.round(rules.bonus + fuel * 12 + precision * pad.multiplier + (stage - 1) * 350)
          resultMessage = "STAGE " + stage + " CLEAR · PAD ×" + pad.multiplier
          if (shell.qualifiesForHighScore(score)) {
            initialsInput = shell.defaultInitials
            initialsPristine = true
            enteringInitials = true
          } else {
            shell.recordLanding(score, fuel, elapsed, shell.defaultInitials || "---", stage)
          }
        }
      }

      Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: {
          var now = Date.now()
          if (!game.previousTick) game.previousTick = now
          var dt = Math.min(0.04, (now - game.previousTick) / 1000)
          game.previousTick = now
          game.updateSky(dt)
          game.updatePhysics(dt)
          game.updateParticles(dt)
          flameCanvas.requestPaint()
        }
      }

      Timer {
        id: viewportResizeTimer
        interval: 120
        repeat: false
        onTriggered: game.resizeWorld()
      }

      Timer {
        interval: 33
        repeat: true
        running: true
        onTriggered: {
          skyEffectsCanvas.requestPaint()
          particleCanvas.requestPaint()
        }
      }

      Timer {
        id: stageClearDelay
        interval: 150
        repeat: false
        onTriggered: shell.playEffect(stageClearSound)
      }

      Timer {
        interval: 3500
        repeat: true
        running: true
        onTriggered: {
          game.spawnShootingStar()
          interval = 6000 + Math.random() * 7000
        }
      }

      Rectangle {
        anchors.fill: parent
        color: shell.background

        Rectangle {
          id: hud
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 88
          color: shell.surface
          border.color: shell.muted
          border.width: 1

          Column {
            id: branding
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            width: Math.ceil(Math.max(brandTitle.implicitWidth, brandSubtitle.implicitWidth))
            Text {
              id: brandTitle
              text: "OMACADE // " + shell.cabinet.shortTitle
              color: shell.accent
              font.pixelSize: hud.width < 800 ? 15 : 18
              font.bold: true
              font.letterSpacing: hud.width < 800 ? 0.8 : 1.5
            }
            Text {
              id: brandSubtitle
              text: game.rules.label + " · STAGE " + game.stage + "  ·  1 / 2 / 3"
              color: shell.muted
              font.pixelSize: 12
              font.letterSpacing: 1.2
            }
          }

          Row {
            id: instruments
            anchors.left: branding.right
            anchors.leftMargin: hud.width < 800 ? 18 : 32
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            height: 48

            Repeater {
              model: [
                { label: "FUEL", value: game.fuel.toFixed(1) },
                { label: "ALT", value: Math.max(0, (game.groundAt(game.shipX) - game.shipY - game.footOffsetY) / 10).toFixed(1) },
                { label: "V/S", value: (game.velocityY / 10).toFixed(2) },
                { label: "H/S", value: (game.velocityX / 10).toFixed(2) },
                { label: "ATT", value: game.normalizeAngle(game.angle).toFixed(1) + "°" }
              ]
              delegate: Column {
                width: instruments.width / 5
                Text { text: modelData.label; color: shell.muted; font.pixelSize: 11; font.bold: true }
                Text { text: modelData.value; color: shell.foreground; font.pixelSize: hud.width < 800 ? 17 : 20; font.family: "monospace"; font.bold: true }
              }
            }
          }
        }

        Item {
          id: playfield
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: hud.bottom
          anchors.bottom: controls.top
          anchors.margins: 12
          clip: true
          onWidthChanged: viewportResizeTimer.restart()
          onHeightChanged: viewportResizeTimer.restart()

          Canvas {
            id: terrainCanvas
            anchors.fill: parent
            onPaint: {
              var context = getContext("2d")
              context.reset()
              var sky = context.createLinearGradient(0, 0, 0, height)
              sky.addColorStop(0, shell.background)
              sky.addColorStop(1, shell.surface)
              context.fillStyle = sky
              context.fillRect(0, 0, width, height)

              for (var s = 0; s < game.stars.length; s++) {
                var star = game.stars[s]
                context.globalAlpha = star.alpha * (1 - star.twinkleStrength * 0.75)
                context.fillStyle = shell.foreground
                context.beginPath()
                context.arc(star.x, star.y, star.radius, 0, Math.PI * 2)
                context.fill()
              }
              context.globalAlpha = 1

              if (!game.terrain.length) return
              context.beginPath()
              context.moveTo(0, height)
              context.lineTo(0, game.terrain[0])
              for (var i = 1; i < game.terrain.length; i++)
                context.lineTo(i * game.terrainStep, game.terrain[i])
              context.lineTo(width, height)
              context.closePath()
              var ground = context.createLinearGradient(0, height * 0.62, 0, height)
              ground.addColorStop(0, shell.surfaceRaised)
              ground.addColorStop(1, shell.background)
              context.fillStyle = ground
              context.fill()
              context.strokeStyle = shell.muted
              context.lineWidth = 2
              context.stroke()

              for (var p = 0; p < game.pads.length; p++) {
                var pad = game.pads[p]
                context.shadowBlur = 14
                context.shadowColor = shell.yellow
                context.strokeStyle = shell.yellow
                context.lineWidth = 5
                context.beginPath()
                context.moveTo(pad.x1, pad.y)
                context.lineTo(pad.x2, pad.y)
                context.stroke()
                context.shadowBlur = 0
                context.fillStyle = shell.yellow
                context.font = "bold 13px monospace"
                context.textAlign = "center"
                context.fillText("×" + pad.multiplier, (pad.x1 + pad.x2) / 2, pad.y + 22)
              }
            }
          }

          Canvas {
            id: skyEffectsCanvas
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height * 0.6
            onPaint: {
              var context = getContext("2d")
              context.reset()
              context.clearRect(0, 0, width, height)

              for (var s = 0; s < game.stars.length; s++) {
                var star = game.stars[s]
                if (star.y > height) continue
                var wave = 0.5 + 0.5 * Math.sin(game.skyTime * star.twinkle + star.phase)
                var pulse = Math.pow(wave, 3)
                context.globalAlpha = Math.min(1, star.alpha * star.twinkleStrength * pulse * 0.9)
                context.fillStyle = shell.foreground
                context.beginPath()
                context.arc(star.x, star.y, star.radius + pulse * 0.8, 0, Math.PI * 2)
                context.fill()
                if (star.twinkleStrength > 0.65 && pulse > 0.72) {
                  var glint = 2.5 + (pulse - 0.72) * 10
                  context.globalAlpha = Math.min(0.75, star.alpha * (pulse - 0.72) * 2.5)
                  context.strokeStyle = shell.foreground
                  context.lineWidth = 1
                  context.beginPath()
                  context.moveTo(star.x - glint, star.y)
                  context.lineTo(star.x + glint, star.y)
                  context.moveTo(star.x, star.y - glint)
                  context.lineTo(star.x, star.y + glint)
                  context.stroke()
                }
              }

              for (var t = 0; t < game.shootingStars.length; t++) {
                var streak = game.shootingStars[t]
                var speed = Math.sqrt(streak.vx * streak.vx + streak.vy * streak.vy)
                var tailX = streak.x - streak.vx / speed * streak.length
                var tailY = streak.y - streak.vy / speed * streak.length
                var born = streak.maxLife - streak.life
                var fade = Math.min(1, born / 0.12, streak.life / 0.28)
                var trail = context.createLinearGradient(tailX, tailY, streak.x, streak.y)
                trail.addColorStop(0, "transparent")
                trail.addColorStop(0.72, streak.comet ? shell.accent : shell.muted)
                trail.addColorStop(1, streak.comet ? shell.yellow : shell.foreground)

                context.globalAlpha = fade * (streak.comet ? 0.18 : 0.12)
                context.strokeStyle = streak.comet ? shell.accent : shell.foreground
                context.lineWidth = streak.comet ? 9 : 6
                context.beginPath()
                context.moveTo(tailX, tailY)
                context.lineTo(streak.x, streak.y)
                context.stroke()

                context.globalAlpha = fade
                context.strokeStyle = trail
                context.lineWidth = streak.comet ? 3.5 : 2
                context.beginPath()
                context.moveTo(tailX, tailY)
                context.lineTo(streak.x, streak.y)
                context.stroke()
                context.fillStyle = streak.comet ? shell.yellow : shell.foreground
                context.beginPath()
                context.arc(streak.x, streak.y, streak.comet ? 3.2 : 1.8, 0, Math.PI * 2)
                context.fill()
              }
              context.globalAlpha = 1
            }
          }

          Item {
            id: shipVisual
            width: 104
            height: 104
            x: game.shipX - width / 2
            y: game.shipY - height / 2
            visible: !game.attractMode
            rotation: game.angle + game.crashSpin
            transformOrigin: Item.Center
            opacity: game.flightState === "crashed" ? game.crashVisualLife / 0.85 : 1
            scale: game.flightState === "crashed" ? 0.68 + game.crashVisualLife / 0.85 * 0.32 : 1

            Canvas {
              id: flameCanvas
              z: -1
              x: 38
              y: 78
              width: 28
              height: 48
              visible: game.thrustHeld && game.fuel > 0 && game.flightState === "flying" && !game.paused
              onPaint: {
                var context = getContext("2d")
                context.reset()
                var glow = context.createLinearGradient(0, 0, 0, height)
                glow.addColorStop(0, shell.yellow)
                glow.addColorStop(0.45, shell.orange)
                glow.addColorStop(1, "transparent")
                context.fillStyle = glow
                context.beginPath()
                context.moveTo(width * 0.25, 0)
                context.lineTo(width * 0.75, 0)
                context.lineTo(width * (0.45 + Math.random() * 0.1), height)
                context.closePath()
                context.fill()
              }
            }

            Image {
              anchors.fill: parent
              source: Qt.resolvedUrl("assets/lander.png")
              fillMode: Image.PreserveAspectFit
              smooth: false
              mipmap: false
            }
          }

          Canvas {
            id: particleCanvas
            anchors.fill: parent
            z: 10
            onPaint: {
              var context = getContext("2d")
              context.reset()
              context.clearRect(0, 0, width, height)

              if (game.blastLife > 0) {
                var blastAge = 1 - game.blastLife / game.blastMaxLife
                context.globalAlpha = (1 - blastAge) * 0.75
                context.strokeStyle = shell.yellow
                context.lineWidth = 5 * (1 - blastAge) + 1
                context.beginPath()
                context.arc(game.blastX, game.blastY, 12 + blastAge * 78, 0, Math.PI * 2)
                context.stroke()
                context.globalAlpha = (1 - blastAge) * 0.34
                context.fillStyle = shell.orange
                context.beginPath()
                context.arc(game.blastX, game.blastY, 28 * (1 - blastAge * 0.45), 0, Math.PI * 2)
                context.fill()
              }

              for (var i = 0; i < game.particles.length; i++) {
                var particle = game.particles[i]
                var alpha = Math.max(0, particle.life / particle.maxLife)
                context.globalAlpha = particle.kind === "dust" ? alpha * 0.48 : alpha
                if (particle.kind === "dust") {
                  context.fillStyle = i % 3 === 0 ? shell.foreground : shell.muted
                  context.beginPath()
                  context.arc(particle.x, particle.y,
                              particle.radius * (1.2 + (1 - alpha) * 1.8), 0, Math.PI * 2)
                  context.fill()
                } else if (particle.kind === "spark") {
                  var speed = Math.max(1, Math.sqrt(particle.vx * particle.vx + particle.vy * particle.vy))
                  context.strokeStyle = i % 3 === 0 ? shell.foreground : i % 2 === 0 ? shell.yellow : shell.orange
                  context.lineWidth = particle.radius * 0.65
                  context.beginPath()
                  context.moveTo(particle.x, particle.y)
                  context.lineTo(particle.x - particle.vx / speed * 11,
                                 particle.y - particle.vy / speed * 11)
                  context.stroke()
                } else {
                  context.save()
                  context.translate(particle.x, particle.y)
                  context.rotate(particle.rotation)
                  context.fillStyle = i % 2 === 0 ? shell.foreground : shell.accent
                  context.fillRect(-particle.radius, -particle.radius * 0.45,
                                   particle.radius * 2, particle.radius * 0.9)
                  context.restore()
                }
              }
              context.globalAlpha = 1
            }
          }

          Rectangle {
            visible: game.attractMode && !game.viewportTooSmall && !game.showScores
            anchors.centerIn: parent
            width: Math.min(parent.width - 50, 610)
            height: Math.min(parent.height - 35, 440)
            radius: 12
            color: shell.surface
            border.color: shell.accent
            border.width: 2
            z: 14

            Column {
              anchors.centerIn: parent
              width: parent.width - 56
              spacing: 13

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "OMACADE // CABINET " + shell.cabinet.number
                color: shell.accent
                font.pixelSize: 15
                font.family: "monospace"
                font.bold: true
                font.letterSpacing: 2
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: shell.cabinet.displayTitle
                color: shell.foreground
                font.pixelSize: 42
                font.bold: true
                font.letterSpacing: 5
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: shell.cabinet.tagline.toUpperCase()
                color: shell.muted
                font.pixelSize: 12
                font.family: "monospace"
              }
              Rectangle { width: parent.width; height: 1; color: shell.muted; opacity: 0.7 }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SELECT FLIGHT SCHOOL"
                color: shell.muted
                font.pixelSize: 12
                font.family: "monospace"
                font.bold: true
              }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24
                Repeater {
                  model: [
                    { key: "1", value: "cadet", label: "CADET" },
                    { key: "2", value: "pilot", label: "PILOT" },
                    { key: "3", value: "ace", label: "ACE" }
                  ]
                  delegate: Text {
                    text: modelData.key + "  " + modelData.label
                    color: shell.difficulty === modelData.value ? shell.yellow : shell.muted
                    font.pixelSize: 15
                    font.family: "monospace"
                    font.bold: shell.difficulty === modelData.value
                  }
                }
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "BEST " + shell.bestScore + "   ·   HIGHEST STAGE " + shell.highestStage
                color: shell.foreground
                font.pixelSize: 13
                font.family: "monospace"
              }
              Text {
                id: launchPrompt
                anchors.horizontalCenter: parent.horizontalCenter
                text: "PRESS ENTER TO LAUNCH"
                color: shell.green
                font.pixelSize: 19
                font.family: "monospace"
                font.bold: true
                font.letterSpacing: 1.5
                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.35; duration: 650 }
                  NumberAnimation { to: 1; duration: 650 }
                }
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "← → / 1 2 3  SELECT    H SCORES    M SOUND " + (shell.soundEnabled ? "ON" : "OFF") + "    Q QUIT"
                color: shell.muted
                font.pixelSize: 11
                font.family: "monospace"
              }
            }
          }

          Rectangle {
            visible: !game.attractMode && !game.viewportTooSmall && !game.showScores && !game.enteringInitials && (game.paused || game.flightState !== "flying")
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 520)
            height: 150
            radius: 10
            color: shell.surface
            border.color: game.flightState === "landed" ? shell.green : game.paused ? shell.accent : shell.red
            border.width: 2

            Column {
              anchors.centerIn: parent
              spacing: 10
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: game.paused ? "PAUSED" : game.resultMessage
                color: game.flightState === "landed" ? shell.green : game.paused ? shell.accent : shell.red
                font.pixelSize: 24
                font.bold: true
                font.letterSpacing: 1.5
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: game.paused ? "Press P to resume" : game.flightState === "landed" ? "SCORE " + game.score + "  ·  ENTER FOR STAGE " + (game.stage + 1) : "ENTER TO RETRY STAGE " + game.stage
                color: shell.foreground
                font.pixelSize: 14
                font.family: "monospace"
              }
            }
          }

          Rectangle {
            visible: game.showScores && !game.enteringInitials
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 620)
            height: Math.min(parent.height - 30, 470)
            radius: 10
            color: shell.surface
            border.color: shell.accent
            border.width: 2
            z: 15

            Column {
              anchors.fill: parent
              anchors.margins: 24
              spacing: 7

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "OMACADE // TOP TEN"
                color: shell.accent
                font.pixelSize: 24
                font.bold: true
                font.letterSpacing: 1.5
              }
              Text {
                text: " #    PILOT       SCORE        CLASS"
                color: shell.muted
                font.pixelSize: 13
                font.family: "monospace"
                font.bold: true
              }
              Rectangle { width: parent.width; height: 1; color: shell.muted }
              Repeater {
                model: 10
                delegate: Text {
                  property var row: index < shell.scoreRows.length ? shell.scoreRows[index] : null
                  width: parent.width
                  text: {
                    var rank = index < 9 ? " " + String(index + 1) : String(index + 1)
                    var pilot = row ? (shell.cleanInitials(row.initials) || "---") : "---"
                    var points = row ? ("       " + String(Math.round(Number(row.score || 0)))).slice(-7) : "      -"
                    var klass = row ? String(row.difficulty || "cadet").toUpperCase() + " S" + Math.max(1, Number(row.stage || 1)) : "---"
                    return rank + "    " + (pilot + "        ").slice(0, 8) + "  " + points + "       " + klass
                  }
                  color: row && index === 0 ? shell.yellow : row ? shell.foreground : shell.muted
                  font.pixelSize: 15
                  font.family: "monospace"
                  font.bold: row && index === 0
                }
              }
              Item { width: 1; height: 3 }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "H / ENTER / ESC  CLOSE"
                color: shell.muted
                font.pixelSize: 12
                font.family: "monospace"
              }
            }
          }

          Rectangle {
            visible: game.enteringInitials
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 500)
            height: 250
            radius: 10
            color: shell.surface
            border.color: shell.yellow
            border.width: 2
            z: 16

            Column {
              anchors.centerIn: parent
              spacing: 12
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "NEW HIGH SCORE"
                color: shell.yellow
                font.pixelSize: 26
                font.bold: true
                font.letterSpacing: 2
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "STAGE " + game.stage + "  ·  SCORE " + game.score
                color: shell.foreground
                font.pixelSize: 16
                font.family: "monospace"
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: game.initialsDisplay()
                color: shell.accent
                font.pixelSize: 42
                font.family: "monospace"
                font.bold: true
                font.letterSpacing: 8
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "TYPE 3 INITIALS  ·  ENTER TO SAVE"
                color: shell.muted
                font.pixelSize: 12
                font.family: "monospace"
              }
            }
          }


          Rectangle {
            visible: game.viewportTooSmall
            anchors.fill: parent
            color: shell.background
            z: 20

            Column {
              anchors.centerIn: parent
              spacing: 12
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CABINET WINDOW TOO SMALL"
                color: shell.yellow
                font.pixelSize: 22
                font.bold: true
                font.letterSpacing: 1.4
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Enlarge the window to at least 600 × 300 pixels of play space."
                color: shell.foreground
                font.pixelSize: 14
              }
              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Current play space: " + Math.round(playfield.width) + " × " + Math.round(playfield.height)
                color: shell.muted
                font.pixelSize: 13
                font.family: "monospace"
              }
            }
          }
        }

        Rectangle {
          id: controls
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 48
          color: shell.surface
          border.color: shell.muted
          border.width: 1
          Text {
            anchors.centerIn: parent
            text: "1 CADET  2 PILOT  3 ACE    ·    ← → ROTATE    ↑ / SPACE THRUST    P PAUSE    H SCORES    M SOUND    R RETRY    Q QUIT"
            color: shell.muted
            font.pixelSize: parent.width < 800 ? 10 : 12
            font.family: "monospace"
            font.bold: true
          }
        }
      }
    }
  }
}
