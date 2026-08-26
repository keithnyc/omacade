import QtQuick
import QtMultimedia
import Quickshell
import "framework"
import "framework/CabinetRegistry.js" as CabinetRegistry

ShellRoot {
  id: shell

  readonly property var cabinet: CabinetRegistry.byId("daemon-swarm")
  readonly property bool circuitMode: Quickshell.env("OMACADE_CIRCUIT") === "1"
  ArcadeTheme { id: theme }
  ArcadeData { id: arcadeData; cabinetId: shell.cabinet.scoreKey }

  SoundEffect { id: launchSound; source: Qt.resolvedUrl("assets/sfx/swarm-launch.wav"); volume: 0.42 }
  SoundEffect { id: hitSound; source: Qt.resolvedUrl("assets/sfx/swarm-hit.wav"); volume: 0.22 }
  SoundEffect { id: levelSound; source: Qt.resolvedUrl("assets/sfx/swarm-levelup.wav"); volume: 0.5 }
  SoundEffect { id: hurtSound; source: Qt.resolvedUrl("assets/sfx/swarm-hurt.wav"); volume: 0.48 }
  SoundEffect { id: deathSound; source: Qt.resolvedUrl("assets/sfx/swarm-death.wav"); volume: 0.55 }

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
    implicitHeight: 960
    minimumSize: Qt.size(700, 700)
    onVisibleChanged: if (!visible) Qt.quit()

    FocusScope {
      id: game
      anchors.fill: parent
      focus: true

      // The arena is bigger than what's ever on screen at once -- the camera follows the
      // player through it. viewportWidth/Height is the fixed visible window (matches the
      // old single-screen world size 1:1, so weapon ranges/spawn feel are unchanged).
      readonly property real worldWidth: 2400
      readonly property real worldHeight: 2400
      readonly property real viewportWidth: 900
      readonly property real viewportHeight: 900
      readonly property real worldAspect: viewportWidth / viewportHeight
      readonly property bool tooSmall: worldCanvas.width < 560 || worldCanvas.height < 560
      readonly property real playerRadius: 13
      // Background depth layers scroll at a fraction of the camera's motion (parallax);
      // the grid/border below moves 1:1 with the camera as the "ground truth" reference.
      readonly property real parallaxFar: 0.35
      readonly property real parallaxNear: 0.65
      readonly property int maxOrbs: 260
      readonly property real orbitRadius: 58 + orbitRangeLevel * 16
      readonly property real orbitSpin: orbitEvolved ? 5.4 : 3.1
      readonly property int orbitDamage: 1 + orbitLevel + (orbitEvolved ? 2 : 0)
      readonly property int orbitShardCap: 10
      readonly property int orbitShardCount: Math.min(orbitLevel, orbitShardCap)
      readonly property int maxEnemies: Math.min(240, 90 + wave * 7)
      // These are evolution-readiness thresholds, not hard caps -- every "-up" upgrade
      // stays in the pool indefinitely past this point so a build keeps growing at wave 50+.
      readonly property int burstMaxLevel: 10
      readonly property int ringMaxLevel: 10
      readonly property int orbitMaxLevel: 8
      readonly property int chainMaxLevel: 8
      readonly property int mineMaxLevel: 8
      readonly property int turretMaxLevel: 8
      readonly property int catalystMaxLevel: 10
      // Unlike the thresholds above, these ARE hard caps -- they bound how many simultaneous
      // bolts/mines/turrets can exist at once, which is what actually drives per-frame cost.
      // Uncapped, a long run turns hundreds of overlapping O(enemies) hit-scans into single-digit fps.
      readonly property int burstMultiCap: 6
      readonly property int burstSpreadCap: 6
      readonly property int mineCapBonusMax: 6
      readonly property int mineCap: 2 + Math.min(mineCapBonus, mineCapBonusMax)
      readonly property int turretCap: Math.min(6, 1 + Math.floor(turretLevel / 2))
      readonly property real slowAuraRadius: 70 + slowAuraLevel * 22
      readonly property string alertLevel: wave < 4 ? "LOW" : wave < 8 ? "ELEVATED" : wave < 14 ? "SEVERE" : "CRITICAL"
      readonly property color alertColor: alertLevel === "LOW" ? theme.green : alertLevel === "ELEVATED" ? theme.yellow : alertLevel === "SEVERE" ? theme.orange : theme.red
      // XP cost compounds past level 30 so a snowballing build can't chain level-ups every
      // 1-2 seconds forever -- the interrupt-every-second problem reported at wave 90+.
      readonly property real levelHardening: Math.pow(1.05, Math.max(0, level - 30))
      readonly property int xpToNext: Math.round((6 + level * 4) * levelHardening)
      readonly property int waveKillTarget: 8 + wave * 5
      readonly property real pickupRadius: 62 + pickupBonus * 16
      readonly property real moveSpeed: 190 * (1 + speedBonus * 0.15)
      // Hardening now kicks in earlier (wave 15) and compounds faster so builds face rising
      // resistance well before the extreme late game, instead of coasting until wave 25+.
      readonly property real waveHardening: Math.pow(1.03, Math.max(0, wave - 15))
      readonly property real enemySpeedMul: 1 + Math.min(3.2, wave * 0.07)
      readonly property real enemyHpMul: (1 + wave * 0.1) * waveHardening
      readonly property real enemyDamageMul: (1 + wave * 0.03) * Math.pow(1.015, Math.max(0, wave - 15))

      property string mode: "attract"
      property string modeBeforeScores: "attract"
      property real playerX: worldWidth / 2
      property real playerY: worldHeight / 2
      property real cameraX: worldWidth / 2
      property real cameraY: worldHeight / 2
      property int maxHp: 5
      property int hp: 5
      property real invulnerable: 0
      property real elapsed: 0
      property int level: 1
      property int xp: 0
      property int score: 0
      property int kills: 0
      property int elites: 0
      property int wave: 1
      property int waveKills: 0
      property real waveTransitionLife: 0
      property string waveReward: ""
      property int burstLevel: 1
      property int burstMultiLevel: 0
      property int burstSpreadLevel: 0
      property int ringLevel: 0
      property int orbitLevel: 0
      property int orbitRangeLevel: 0
      property int chainLevel: 0
      property int mineLevel: 0
      property bool mineCascade: false
      property int mineCapBonus: 0
      property int turretLevel: 0
      property real turretCooldown: 0
      property int speedBonus: 0
      property int pickupBonus: 0
      property int xpBonus: 0
      property int shieldBonus: 0
      property int regenLevel: 0
      property real regenTimer: 0
      property int failoverCharges: 0
      property int critLevel: 0
      property int slowAuraLevel: 0
      property int lastBossWave: 0
      property bool burstEvolved: false
      property bool ringEvolved: false
      property bool orbitEvolved: false
      property bool chainEvolved: false
      property bool mineEvolved: false
      property real burstCooldown: 0
      property real ringCooldown: 0
      property real chainCooldown: 0
      property real mineCooldown: 0
      property real spawnCooldown: 0.6
      property real eliteCooldown: 30
      property real eliteWarning: 0
      property var eliteWarningPos: ({ x: 0, y: 0 })
      property real animationTime: 0
      property real damageFlash: 0
      property real killFlash: 0
      property real shakeTime: 0
      property real shakeMag: 0
      property real lastTickMs: Date.now()
      property int enemySerial: 0
      readonly property int maxParticles: 200
      readonly property int maxDamageNumbers: 60
      property var enemies: []
      property var orbs: []
      property var bolts: []
      property var rings: []
      property var mines: []
      property var chains: []
      property var turrets: []
      property var beams: []
      property var pops: []
      property var particles: []
      property var damageNumbers: []
      property var starsFar: []
      property var starsNear: []
      property var upgradeChoices: []
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property string statusMessage: "DAEMON ONLINE"
      property string initialsInput: ""
      property bool initialsPristine: true

      Component.onCompleted: {
        // Generated across the world bounds plus a margin so both parallax layers stay
        // fully covered at every camera position (see parallaxFar/parallaxNear above).
        var marginX = viewportWidth / 2
        var marginY = viewportHeight / 2
        function scatterStars(count) {
          var generated = []
          for (var i = 0; i < count; i++)
            generated.push({ x: -marginX + Math.random() * (worldWidth + marginX * 2),
                             y: -marginY + Math.random() * (worldHeight + marginY * 2),
                             phase: Math.random() * 6.28 })
          return generated
        }
        starsFar = scatterStars(260)
        starsNear = scatterStars(160)
        resetRun()
        forceActiveFocus()
      }

      function formatTime(total) {
        var t = Math.max(0, Math.floor(total))
        var m = Math.floor(t / 60)
        var s = t % 60
        return m + ":" + (s < 10 ? "0" + s : s)
      }

      function colorFor(key) {
        if (key === "green") return theme.green
        if (key === "orange") return theme.orange
        if (key === "red") return theme.red
        if (key === "accent") return theme.accent
        if (key === "yellow") return theme.yellow
        return theme.foreground
      }

      function levelTag(lvl, maxLvl) {
        return lvl < maxLvl ? ("Lv" + lvl + "/" + maxLvl) : ("Lv" + lvl)
      }

      function burstStatusText() {
        var extra = (burstMultiLevel > 0 ? " +" + burstMultiLevel + "T" : "") + (burstSpreadLevel > 0 ? " +" + (burstSpreadLevel * 2) + "S" : "")
        if (burstEvolved) return "BURST  PACKET STORM  " + levelTag(burstLevel, burstMaxLevel) + extra
        var ready = burstLevel >= burstMaxLevel && speedBonus >= catalystMaxLevel
        return "BURST  " + levelTag(burstLevel, burstMaxLevel) + extra + (ready ? "  READY" : "")
      }

      function ringStatusText() {
        if (ringLevel === 0) return "RING   --"
        if (ringEvolved) return "RING   AEGIS PROTOCOL  " + levelTag(ringLevel, ringMaxLevel)
        var ready = ringLevel >= ringMaxLevel && shieldBonus >= catalystMaxLevel
        return "RING   " + levelTag(ringLevel, ringMaxLevel) + (ready ? "  READY" : "")
      }

      function orbitStatusText() {
        if (orbitLevel === 0) return "ORBIT  --"
        var extra = orbitRangeLevel > 0 ? " +" + orbitRangeLevel + "R" : ""
        if (orbitEvolved) return "ORBIT  ORBIT STORM  " + levelTag(orbitLevel, orbitMaxLevel) + extra
        var ready = orbitLevel >= orbitMaxLevel && slowAuraLevel >= catalystMaxLevel
        return "ORBIT  " + levelTag(orbitLevel, orbitMaxLevel) + extra + (ready ? "  READY" : "")
      }

      function chainStatusText() {
        if (chainLevel === 0) return "ARC    --"
        if (chainEvolved) return "ARC    ARC CASCADE  " + levelTag(chainLevel, chainMaxLevel)
        var ready = chainLevel >= chainMaxLevel && critLevel >= catalystMaxLevel
        return "ARC    " + levelTag(chainLevel, chainMaxLevel) + (ready ? "  READY" : "")
      }

      function mineStatusText() {
        if (mineLevel === 0) return "MINE   --"
        var tag = mineCascade ? " CHAIN" : ""
        if (mineEvolved) return "MINE   MINEFIELD PROTOCOL  " + levelTag(mineLevel, mineMaxLevel) + " CAP" + mineCap + tag
        var ready = mineLevel >= mineMaxLevel && regenLevel >= catalystMaxLevel
        return "MINE   " + levelTag(mineLevel, mineMaxLevel) + " CAP" + mineCap + tag + (ready ? "  READY" : "")
      }

      function spawnBurst(x, y, colorKey, count, speed, life) {
        var updated = particles.slice(0)
        for (var i = 0; i < count; i++) {
          var angle = Math.random() * Math.PI * 2
          var spd = speed * (0.4 + Math.random() * 0.7)
          updated.push({ x: x, y: y, vx: Math.cos(angle) * spd, vy: Math.sin(angle) * spd,
                         life: life, maxLife: life, colorKey: colorKey, size: 2.0 + Math.random() * 2.6 })
        }
        if (updated.length > maxParticles) updated = updated.slice(updated.length - maxParticles)
        particles = updated
      }

      function updateParticles(dt) {
        var active = []
        for (var i = 0; i < particles.length; i++) {
          var p = particles[i]
          p.life -= dt
          if (p.life <= 0) continue
          p.x += p.vx * dt
          p.y += p.vy * dt
          p.vx *= 0.93
          p.vy *= 0.93
          active.push(p)
        }
        particles = active
      }

      function spawnPop(x, y, colorKey, maxRadius, duration) {
        var updated = pops.slice(0)
        updated.push({ x: x, y: y, life: 0, duration: duration || 0.35, maxRadius: maxRadius || 40, colorKey: colorKey })
        pops = updated
      }

      function updatePops(dt) {
        var active = []
        for (var i = 0; i < pops.length; i++) {
          var p = pops[i]
          p.life += dt
          if (p.life < p.duration) active.push(p)
        }
        pops = active
      }

      function spawnShake(mag, time) {
        shakeMag = Math.max(shakeMag, mag)
        shakeTime = Math.max(shakeTime, time)
      }

      function resetRun() {
        playerX = worldWidth / 2
        playerY = worldHeight / 2
        cameraX = worldWidth / 2
        cameraY = worldHeight / 2
        maxHp = 5
        hp = 5
        invulnerable = 0
        elapsed = 0
        level = 1
        xp = 0
        score = 0
        kills = 0
        elites = 0
        wave = 1
        waveKills = 0
        waveTransitionLife = 0
        waveReward = ""
        burstLevel = 1
        burstMultiLevel = 0
        burstSpreadLevel = 0
        ringLevel = 0
        orbitLevel = 0
        orbitRangeLevel = 0
        chainLevel = 0
        mineLevel = 0
        mineCascade = false
        mineCapBonus = 0
        turretLevel = 0
        turretCooldown = 0
        speedBonus = 0
        pickupBonus = 0
        xpBonus = 0
        shieldBonus = 0
        regenLevel = 0
        regenTimer = 0
        failoverCharges = 0
        critLevel = 0
        slowAuraLevel = 0
        lastBossWave = 0
        burstEvolved = false
        ringEvolved = false
        orbitEvolved = false
        chainEvolved = false
        mineEvolved = false
        burstCooldown = 0
        ringCooldown = 0
        chainCooldown = 0
        mineCooldown = 0
        spawnCooldown = 0.6
        eliteCooldown = 30
        eliteWarning = 0
        enemies = []
        orbs = []
        bolts = []
        rings = []
        mines = []
        chains = []
        turrets = []
        beams = []
        pops = []
        particles = []
        damageNumbers = []
        upgradeChoices = []
        damageFlash = 0
        killFlash = 0
        shakeTime = 0
        shakeMag = 0
        leftHeld = rightHeld = upHeld = downHeld = false
        statusMessage = "DAEMON ONLINE"
      }

      function startRun() {
        resetRun()
        mode = "playing"
        lastTickMs = Date.now()
        shell.play(launchSound)
      }

      function enemyProfile(type) {
        if (type === "worm") return { hp: 1, speed: 96, radius: 9, damage: 1, xp: 2, score: 12, color: "green" }
        if (type === "fork") return { hp: 2, speed: 74, radius: 11, damage: 1, xp: 3, score: 20, color: "orange" }
        if (type === "fork-child") return { hp: 1, speed: 118, radius: 7, damage: 1, xp: 1, score: 8, color: "orange" }
        if (type === "trojan") return { hp: 5, speed: 52, radius: 15, damage: 2, xp: 6, score: 55, color: "red" }
        if (type === "boss") return { hp: 70, speed: 44, radius: 32, damage: 3, xp: 40, score: 900, color: "red" }
        if (type === "boss-swift") return { hp: 46, speed: 80, radius: 26, damage: 3, xp: 44, score: 950, color: "yellow" }
        if (type === "boss-tank") return { hp: 130, speed: 30, radius: 38, damage: 4, xp: 50, score: 1050, color: "accent" }
        return { hp: 18, speed: 62, radius: 21, damage: 2, xp: 18, score: 400, color: "accent" }
      }

      function isBossType(type) {
        return type === "boss" || type === "boss-swift" || type === "boss-tank"
      }

      function bossTypePool() {
        return ["boss", "boss-swift", "boss-tank"]
      }

      function pickEnemyType() {
        var roll = Math.random()
        if (wave < 3) return "worm"
        if (wave < 6) return roll < 0.7 ? "worm" : "fork"
        if (wave < 12) return roll < 0.5 ? "worm" : roll < 0.82 ? "fork" : "trojan"
        return roll < 0.3 ? "worm" : roll < 0.62 ? "fork" : "trojan"
      }

      function edgeSpawnPoint() {
        // Spawns just outside the player's current viewport, not the (much larger) world
        // edges -- with a scrolling camera, spawning at fixed world bounds would place
        // enemies miles from wherever the player actually is.
        var side = Math.floor(Math.random() * 4)
        var margin = 30
        var halfW = viewportWidth / 2 + margin
        var halfH = viewportHeight / 2 + margin
        var x, y
        if (side === 0) { x = playerX + (Math.random() * 2 - 1) * halfW; y = playerY - halfH }
        else if (side === 1) { x = playerX + halfW; y = playerY + (Math.random() * 2 - 1) * halfH }
        else if (side === 2) { x = playerX + (Math.random() * 2 - 1) * halfW; y = playerY + halfH }
        else { x = playerX - halfW; y = playerY + (Math.random() * 2 - 1) * halfH }
        return { x: Math.max(10, Math.min(worldWidth - 10, x)), y: Math.max(10, Math.min(worldHeight - 10, y)) }
      }

      function makeEnemy(type, pos) {
        var profile = enemyProfile(type)
        enemySerial += 1
        var scaledHp = Math.max(1, Math.round(profile.hp * enemyHpMul))
        return { id: enemySerial, type: type, x: pos.x, y: pos.y, hp: scaledHp, maxHp: scaledHp,
                 speed: profile.speed * enemySpeedMul, radius: profile.radius,
                 damage: Math.max(profile.damage, Math.round(profile.damage * enemyDamageMul)),
                 xp: profile.xp, score: profile.score, colorKey: profile.color, hitFlash: 0,
                 orbitCooldown: 0, modifier: null }
      }

      function spawnEnemyAt(type, pos) {
        if (enemies.length >= maxEnemies) return
        enemies = enemies.concat([makeEnemy(type, pos)])
      }

      function eliteModifierPool() {
        return ["shielded", "fast", "volatile"]
      }

      function spawnElite(type, pos) {
        if (enemies.length >= maxEnemies) return null
        var enemy = makeEnemy(type, pos)
        if (Math.random() < 0.65) {
          var mods = eliteModifierPool()
          enemy.modifier = mods[Math.floor(Math.random() * mods.length)]
          if (enemy.modifier === "fast") enemy.speed *= 1.55
        }
        enemies = enemies.concat([enemy])
        return enemy
      }

      function nearestEnemy() {
        var best = null
        var bestDist = Infinity
        for (var i = 0; i < enemies.length; i++) {
          var e = enemies[i]
          var dx = e.x - playerX
          var dy = e.y - playerY
          var d = dx * dx + dy * dy
          if (d < bestDist) { bestDist = d; best = e }
        }
        return best
      }

      function rollDamage(base) {
        return (critLevel > 0 && Math.random() < critLevel * 0.1) ? base * 2 : base
      }

      function spawnDamageNumber(x, y, amount, crit) {
        var updated = damageNumbers.slice(0)
        updated.push({ x: x + (Math.random() - 0.5) * 12, y: y - 8, vy: -46,
                       value: Math.round(amount), life: 0.6, maxLife: 0.6, crit: crit })
        if (updated.length > maxDamageNumbers) updated = updated.slice(updated.length - maxDamageNumbers)
        damageNumbers = updated
      }

      function updateDamageNumbers(dt) {
        var active = []
        for (var i = 0; i < damageNumbers.length; i++) {
          var d = damageNumbers[i]
          d.life -= dt
          if (d.life <= 0) continue
          d.y += d.vy * dt
          d.vy *= 0.9
          active.push(d)
        }
        damageNumbers = active
      }

      function applyDamage(target, base, flashDuration, forceCrit) {
        var amount = forceCrit ? base * 2 : rollDamage(base)
        if (target.modifier === "shielded") amount = Math.max(1, Math.round(amount * 0.6))
        target.hp -= amount
        target.hitFlash = flashDuration || 0.12
        spawnDamageNumber(target.x, target.y, amount, amount > base)
        return amount
      }

      function triggerVolatileDeath(e) {
        var blastRadius = 70
        var dx = playerX - e.x, dy = playerY - e.y
        var dist = Math.sqrt(dx * dx + dy * dy)
        spawnBurst(e.x, e.y, "red", 34, 260, 0.6)
        spawnPop(e.x, e.y, "red", blastRadius, 0.45)
        spawnShake(7, 0.22)
        if (dist < blastRadius) damagePlayer(2)
      }

      function fireBurst() {
        var target = nearestEnemy()
        if (!target) return
        var updated = bolts.slice(0)
        var damage = 1 + Math.floor((burstLevel - 1) / 2)
        var pierce = burstLevel - 1
        function pushBolt(dirX, dirY, dmg) {
          updated.push({ x: playerX, y: playerY, dirX: dirX, dirY: dirY, speed: 560,
                         damage: dmg, pierce: pierce, travelled: 0, maxRange: 760, hitIds: [], evolved: burstEvolved })
        }

        if (burstEvolved) {
          var evoDamage = damage + 2
          var targets = enemies.slice(0).sort(function(a, b) {
            var da = (a.x - playerX) * (a.x - playerX) + (a.y - playerY) * (a.y - playerY)
            var db = (b.x - playerX) * (b.x - playerX) + (b.y - playerY) * (b.y - playerY)
            return da - db
          }).slice(0, 10)
          for (var t = 0; t < targets.length; t++) {
            var tdx = targets[t].x - playerX, tdy = targets[t].y - playerY
            var tdist = Math.sqrt(tdx * tdx + tdy * tdy) || 1
            pushBolt(tdx / tdist, tdy / tdist, evoDamage)
          }
          bolts = updated
          spawnBurst(playerX, playerY, "yellow", 6, 160, 0.18)
          burstCooldown = Math.max(0.16, 1.15 - (burstLevel - 1) * 0.08 - 0.12)
          return
        }

        var dx0 = target.x - playerX, dy0 = target.y - playerY
        var dist0 = Math.sqrt(dx0 * dx0 + dy0 * dy0) || 1
        pushBolt(dx0 / dist0, dy0 / dist0, damage)

        if (burstMultiLevel > 0) {
          var candidates = enemies.slice(0).sort(function(a, b) {
            var da = (a.x - playerX) * (a.x - playerX) + (a.y - playerY) * (a.y - playerY)
            var db = (b.x - playerX) * (b.x - playerX) + (b.y - playerY) * (b.y - playerY)
            return da - db
          })
          var picked = 1
          for (var i = 0; i < candidates.length && picked < 1 + burstMultiLevel; i++) {
            if (candidates[i].id === target.id) continue
            var mdx = candidates[i].x - playerX, mdy = candidates[i].y - playerY
            var mdist = Math.sqrt(mdx * mdx + mdy * mdy) || 1
            pushBolt(mdx / mdist, mdy / mdist, damage)
            picked += 1
          }
        }

        if (burstSpreadLevel > 0) {
          var baseAngle = Math.atan2(dy0, dx0)
          for (var s = 1; s <= burstSpreadLevel; s++) {
            var offset = 0.26 * s
            pushBolt(Math.cos(baseAngle + offset), Math.sin(baseAngle + offset), damage)
            pushBolt(Math.cos(baseAngle - offset), Math.sin(baseAngle - offset), damage)
          }
        }

        bolts = updated
        spawnBurst(playerX, playerY, "accent", 3, 130, 0.14)
        burstCooldown = Math.max(0.22, 1.15 - (burstLevel - 1) * 0.08)
      }

      function pulseRing() {
        var updated = rings.slice(0)
        updated.push({ x: playerX, y: playerY, life: 0, duration: 0.4,
                       maxRadius: (70 + ringLevel * 18) * (ringEvolved ? 1.3 : 1),
                       damage: (1 + ringLevel) + (ringEvolved ? 2 : 0), hitIds: [], evolved: ringEvolved })
        rings = updated
        ringCooldown = ringEvolved ? Math.max(0.5, (2.6 - (ringLevel - 1) * 0.3) * 0.45) : Math.max(1.3, 2.6 - (ringLevel - 1) * 0.3)
      }

      function fireChain() {
        var target = nearestEnemy()
        if (!target) return
        var dmg = 1 + Math.floor(chainLevel / 2)
        var hitIds = {}
        var points = [{ x: playerX, y: playerY }]
        var current = target
        var jumps = chainEvolved ? Math.min(enemies.length, 12) : Math.min(4, 2 + Math.floor(chainLevel / 2))
        for (var j = 0; j < jumps && current; j++) {
          hitIds[current.id] = true
          applyDamage(current, dmg, 0.14, chainEvolved)
          points.push({ x: current.x, y: current.y })
          var next = null
          var bestD = chainEvolved ? Infinity : 190 * 190
          for (var i = 0; i < enemies.length; i++) {
            var e = enemies[i]
            if (hitIds[e.id]) continue
            var dx = e.x - current.x, dy = e.y - current.y
            var d = dx * dx + dy * dy
            if (d < bestD) { bestD = d; next = e }
          }
          current = next
        }
        var updatedChains = chains.slice(0)
        updatedChains.push({ points: points, life: 0, duration: 0.2, evolved: chainEvolved })
        chains = updatedChains
        shell.play(hitSound)
        chainCooldown = Math.max(0.7, 1.5 - chainLevel * 0.15)
      }

      function dropMine() {
        if (mines.length >= mineCap) return
        var updated = mines.slice(0)
        updated.push({ x: playerX, y: playerY, armTime: 0.35, life: 0, maxLife: 9, radius: 15, evolved: mineEvolved })
        mines = updated
        mineCooldown = mineEvolved ? Math.max(0.5, 4.2 - mineLevel * 0.5 - 2.4) : Math.max(2.4, 4.2 - mineLevel * 0.5)
      }

      function detonateMine(mine, blastRadius, blastDamage) {
        for (var b = 0; b < enemies.length; b++) {
          var target = enemies[b]
          var bx = target.x - mine.x, by = target.y - mine.y
          if (bx * bx + by * by <= blastRadius * blastRadius) {
            applyDamage(target, blastDamage, 0.14)
          }
        }
        spawnBurst(mine.x, mine.y, "orange", 30, 240, 0.55)
        spawnPop(mine.x, mine.y, "orange", blastRadius, 0.42)
        spawnShake(6, 0.2)
        shell.play(hitSound)
      }

      function updateMines(dt) {
        var blastRadius = (78 + mineLevel * 16) * (mineEvolved ? 1.25 : 1)
        var blastDamage = (3 + mineLevel * 2) + (mineEvolved ? 4 : 0)
        var triggeredIds = {}
        for (var i = 0; i < mines.length; i++) {
          var mine = mines[i]
          mine.life += dt
          if (mine.armTime > 0) mine.armTime -= dt
          if (mine.armTime > 0) continue
          for (var e = 0; e < enemies.length; e++) {
            var enemy = enemies[e]
            var dx = enemy.x - mine.x, dy = enemy.y - mine.y
            if (dx * dx + dy * dy <= (mine.radius + enemy.radius) * (mine.radius + enemy.radius)) { triggeredIds[i] = true; break }
          }
        }
        if (mineCascade || mineEvolved) {
          var grew = true
          while (grew) {
            grew = false
            for (var ci = 0; ci < mines.length; ci++) {
              if (triggeredIds[ci]) continue
              var candidate = mines[ci]
              for (var cj = 0; cj < mines.length; cj++) {
                if (!triggeredIds[cj]) continue
                var source = mines[cj]
                var cdx = candidate.x - source.x, cdy = candidate.y - source.y
                if (cdx * cdx + cdy * cdy <= blastRadius * blastRadius) { triggeredIds[ci] = true; grew = true; break }
              }
            }
          }
        }
        var active = []
        for (var m = 0; m < mines.length; m++) {
          var current = mines[m]
          if (triggeredIds[m]) { detonateMine(current, blastRadius, blastDamage); continue }
          if (current.life >= current.maxLife) continue
          active.push(current)
        }
        mines = active
      }

      function dropTurret() {
        if (turrets.length >= turretCap) return
        var updated = turrets.slice(0)
        var maxHp = 10 + turretLevel * 6
        updated.push({ x: playerX, y: playerY, hp: maxHp, maxHp: maxHp, life: 0, maxLife: 16 + turretLevel * 2, fireCooldown: 0.3 })
        turrets = updated
        turretCooldown = Math.max(1.6, 5 - turretLevel * 0.5)
      }

      function updateTurrets(dt) {
        if (turrets.length === 0) return
        var range = 170 + turretLevel * 16
        var fireInterval = Math.max(0.32, 1.3 - turretLevel * 0.22)
        var dmg = 3 + turretLevel * 3
        var active = []
        for (var i = 0; i < turrets.length; i++) {
          var t = turrets[i]
          t.life += dt
          t.fireCooldown -= dt
          for (var e = 0; e < enemies.length; e++) {
            var en = enemies[e]
            var dx = en.x - t.x, dy = en.y - t.y
            if (dx * dx + dy * dy <= (en.radius + 14) * (en.radius + 14)) t.hp -= en.damage * 2.4 * dt
          }
          if (t.hp <= 0) {
            spawnBurst(t.x, t.y, "red", 22, 210, 0.4)
            spawnPop(t.x, t.y, "red", 44, 0.35)
            continue
          }
          if (t.life >= t.maxLife) {
            spawnPop(t.x, t.y, "accent", 30, 0.3)
            continue
          }
          if (t.fireCooldown <= 0) {
            var target = null
            var bestD = range * range
            for (var j = 0; j < enemies.length; j++) {
              var cand = enemies[j]
              var cdx = cand.x - t.x, cdy = cand.y - t.y
              var cd = cdx * cdx + cdy * cdy
              if (cd < bestD) { bestD = cd; target = cand }
            }
            if (target) {
              applyDamage(target, dmg, 0.14)
              var updatedBeams = beams.slice(0)
              updatedBeams.push({ x1: t.x, y1: t.y, x2: target.x, y2: target.y, life: 0, duration: 0.12 })
              beams = updatedBeams
              shell.play(hitSound)
            }
            t.fireCooldown = fireInterval
          }
          active.push(t)
        }
        turrets = active
      }

      function updateBeams(dt) {
        var active = []
        for (var i = 0; i < beams.length; i++) {
          var b = beams[i]
          b.life += dt
          if (b.life < b.duration) active.push(b)
        }
        beams = active
      }

      function turretStatusText() {
        if (turretLevel === 0) return "TURRET --"
        return "TURRET " + levelTag(turretLevel, turretMaxLevel) + "  x" + turretCap
      }

      function updateChains(dt) {
        var active = []
        for (var i = 0; i < chains.length; i++) {
          var c = chains[i]
          c.life += dt
          if (c.life < c.duration) active.push(c)
        }
        chains = active
      }

      function updateWeapons(dt) {
        burstCooldown = Math.max(0, burstCooldown - dt)
        if (burstCooldown <= 0) fireBurst()
        if (ringLevel > 0) {
          ringCooldown = Math.max(0, ringCooldown - dt)
          if (ringCooldown <= 0) pulseRing()
        }
        if (chainLevel > 0) {
          chainCooldown = Math.max(0, chainCooldown - dt)
          if (chainCooldown <= 0) fireChain()
        }
        if (mineLevel > 0) {
          mineCooldown = Math.max(0, mineCooldown - dt)
          if (mineCooldown <= 0) dropMine()
        }
        if (turretLevel > 0) {
          turretCooldown = Math.max(0, turretCooldown - dt)
          if (turretCooldown <= 0) dropTurret()
        }
      }

      function updateMovement(dt) {
        var dx = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0)
        var dy = (downHeld ? 1 : 0) - (upHeld ? 1 : 0)
        if (dx !== 0 && dy !== 0) { dx *= 0.7071; dy *= 0.7071 }
        playerX = Math.max(playerRadius, Math.min(worldWidth - playerRadius, playerX + dx * moveSpeed * dt))
        playerY = Math.max(playerRadius, Math.min(worldHeight - playerRadius, playerY + dy * moveSpeed * dt))
      }

      function updateCamera(dt) {
        var targetX = Math.max(viewportWidth / 2, Math.min(worldWidth - viewportWidth / 2, playerX))
        var targetY = Math.max(viewportHeight / 2, Math.min(worldHeight - viewportHeight / 2, playerY))
        var followRate = Math.min(1, dt * 8)
        cameraX += (targetX - cameraX) * followRate
        cameraY += (targetY - cameraY) * followRate
      }

      function hasMagnetOrb() {
        for (var i = 0; i < orbs.length; i++) if (orbs[i].kind === "magnet") return true
        return false
      }

      function dropLoot(e) {
        var updated = orbs.slice(0)
        if (e.type === "rootkit" || isBossType(e.type)) {
          var lootCount = isBossType(e.type) ? 8 : 4
          var perOrb = Math.max(1, Math.round((e.xp * 1.5) / lootCount))
          for (var i = 0; i < lootCount; i++) {
            var ang = Math.random() * Math.PI * 2
            var dist = 10 + Math.random() * 34
            updated.push({ x: e.x + Math.cos(ang) * dist, y: e.y + Math.sin(ang) * dist, value: perOrb, kind: "xp" })
          }
        } else {
          updated.push({ x: e.x, y: e.y, value: e.xp, kind: "xp" })
        }
        orbs = updated
        if (!hasMagnetOrb() && Math.random() < 0.015) {
          orbs = orbs.concat([{ x: e.x + (Math.random() - 0.5) * 40, y: e.y + (Math.random() - 0.5) * 40, value: 0, kind: "magnet" }])
        }
        // The arena is much bigger than the viewport now -- orbs left behind as the player
        // roams could otherwise accumulate forever. Drop the oldest once past the cap.
        if (orbs.length > maxOrbs) orbs = orbs.slice(orbs.length - maxOrbs)
      }

      function killRewards(e) {
        score += e.score
        dropLoot(e)
        if (e.type === "rootkit" || isBossType(e.type)) {
          statusMessage = (isBossType(e.type) ? "MINI-BOSS PURGED // +" : "ROOTKIT PURGED // +") + e.score
          spawnBurst(e.x, e.y, e.colorKey, 46, 260, 0.8)
          spawnBurst(e.x, e.y, "foreground", 14, 320, 0.5)
          spawnPop(e.x, e.y, e.colorKey, 90, 0.55)
          spawnPop(e.x, e.y, "foreground", 60, 0.35)
          killFlash = 0.22
          spawnShake(7, 0.22)
        } else {
          spawnBurst(e.x, e.y, e.colorKey, 16, 220, 0.45)
          spawnBurst(e.x, e.y, "foreground", 4, 260, 0.25)
          spawnPop(e.x, e.y, e.colorKey, 42, 0.3)
          killFlash = Math.max(killFlash, 0.06)
        }
      }

      function damagePlayer(amount) {
        if (invulnerable > 0 || mode !== "playing") return
        if (ringEvolved) amount = Math.max(1, amount - 1)
        hp -= amount
        invulnerable = 0.9 + Math.min(shieldBonus, 8) * 0.15
        damageFlash = 0.4
        spawnShake(9, 0.26)
        shell.play(hurtSound)
        spawnBurst(playerX, playerY, "red", 20, 170, 0.45)
        spawnPop(playerX, playerY, "red", 50, 0.3)
        if (hp <= 0) {
          if (failoverCharges > 0) {
            failoverCharges -= 1
            hp = Math.max(1, Math.ceil(maxHp / 2))
            invulnerable = 2.2
            statusMessage = "FAILOVER TRIGGERED // INTEGRITY RESTORED"
            spawnBurst(playerX, playerY, "accent", 40, 260, 0.7)
            spawnPop(playerX, playerY, "accent", 110, 0.5)
            spawnShake(8, 0.3)
            return
          }
          hp = 0
          finishRun()
        }
      }

      function updateEnemies(dt) {
        var newBolts = []
        for (var bi = 0; bi < bolts.length; bi++) {
          var bolt = bolts[bi]
          var step = bolt.speed * dt
          bolt.x += bolt.dirX * step
          bolt.y += bolt.dirY * step
          bolt.travelled += step
          var consumed = false
          for (var ei = 0; ei < enemies.length; ei++) {
            var target = enemies[ei]
            var hdx = target.x - bolt.x
            var hdy = target.y - bolt.y
            if (hdx * hdx + hdy * hdy <= (target.radius + 4) * (target.radius + 4) && bolt.hitIds.indexOf(target.id) < 0) {
              applyDamage(target, bolt.damage)
              bolt.hitIds.push(target.id)
              bolt.pierce -= 1
              shell.play(hitSound)
              if (bolt.pierce < 0) { consumed = true; break }
            }
          }
          if (!consumed && bolt.travelled < bolt.maxRange) newBolts.push(bolt)
        }
        bolts = newBolts

        var newRings = []
        for (var ri = 0; ri < rings.length; ri++) {
          var ring = rings[ri]
          ring.life += dt
          var progress = Math.min(1, ring.life / ring.duration)
          var radius = ring.maxRadius * Math.sin(progress * Math.PI * 0.5)
          for (var rei = 0; rei < enemies.length; rei++) {
            var rtarget = enemies[rei]
            var rdx = rtarget.x - ring.x
            var rdy = rtarget.y - ring.y
            if (rdx * rdx + rdy * rdy <= radius * radius && ring.hitIds.indexOf(rtarget.id) < 0) {
              applyDamage(rtarget, ring.damage)
              ring.hitIds.push(rtarget.id)
            }
          }
          if (ring.life < ring.duration) newRings.push(ring)
        }
        rings = newRings

        if (orbitLevel > 0) {
          var orbitHitPad = orbitEvolved ? 12 : 8
          for (var s = 0; s < orbitShardCount; s++) {
            var angle = animationTime * orbitSpin + s * (Math.PI * 2 / orbitShardCount)
            var sx = playerX + Math.cos(angle) * orbitRadius
            var sy = playerY + Math.sin(angle) * orbitRadius
            for (var oi = 0; oi < enemies.length; oi++) {
              var otarget = enemies[oi]
              var odx = otarget.x - sx
              var ody = otarget.y - sy
              if (odx * odx + ody * ody <= (otarget.radius + orbitHitPad) * (otarget.radius + orbitHitPad) && (otarget.orbitCooldown || 0) <= 0) {
                applyDamage(otarget, orbitDamage)
                otarget.orbitCooldown = 0.35
              }
            }
          }
        }

        var survivors = []
        var spawnQueue = []
        for (var i = 0; i < enemies.length; i++) {
          var e = enemies[i]
          e.hitFlash = Math.max(0, (e.hitFlash || 0) - dt)
          e.orbitCooldown = Math.max(0, (e.orbitCooldown || 0) - dt)
          if (e.hp <= 0) {
            killRewards(e)
            kills += 1
            waveKills += 1
            if (e.type === "rootkit" || isBossType(e.type)) elites += 1
            if (e.modifier === "volatile") triggerVolatileDeath(e)
            if (e.type === "fork") {
              spawnQueue.push({ x: e.x, y: e.y })
              spawnQueue.push({ x: e.x, y: e.y })
            }
            continue
          }
          var dx = playerX - e.x
          var dy = playerY - e.y
          var dist = Math.sqrt(dx * dx + dy * dy) || 1
          var effSpeed = e.speed
          if (slowAuraLevel > 0 && dist < slowAuraRadius) effSpeed *= Math.max(0.35, 1 - slowAuraLevel * 0.15)
          e.x += dx / dist * effSpeed * dt
          e.y += dy / dist * effSpeed * dt
          if (dist < playerRadius + e.radius) damagePlayer(e.damage)
          survivors.push(e)
        }
        for (var q = 0; q < spawnQueue.length; q++)
          if (survivors.length < maxEnemies) survivors.push(makeEnemy("fork-child", spawnQueue[q]))
        enemies = survivors
      }

      function triggerMagnetBurst() {
        var total = 0
        for (var i = 0; i < orbs.length; i++) total += orbs[i].value + xpBonus
        var count = orbs.length
        orbs = []
        spawnBurst(playerX, playerY, "accent", 36, 300, 0.6)
        spawnBurst(playerX, playerY, "yellow", 20, 260, 0.5)
        spawnPop(playerX, playerY, "accent", 150, 0.55)
        shell.play(levelSound)
        statusMessage = count > 0 ? "MAGNET PACKET // " + count + " PACKETS COLLECTED" : "MAGNET PACKET ACTIVATED"
        if (total > 0) gainXp(total)
      }

      function updateOrbs(dt) {
        var active = []
        var magnetHit = false
        for (var i = 0; i < orbs.length; i++) {
          var orb = orbs[i]
          var dx = playerX - orb.x
          var dy = playerY - orb.y
          var dist = Math.sqrt(dx * dx + dy * dy) || 1
          if (dist < pickupRadius) {
            var pullStrength = 1 - dist / pickupRadius
            var pull = Math.min(dist, (300 + pullStrength * 520) * dt)
            orb.x += dx / dist * pull
            orb.y += dy / dist * pull
            if (Math.random() < 0.4) spawnBurst(orb.x, orb.y, orb.kind === "magnet" ? "accent" : "yellow", 1, 30, 0.18)
          }
          if (dist < 16) {
            if (orb.kind === "magnet") { magnetHit = true; continue }
            spawnBurst(orb.x, orb.y, "yellow", 18, 220, 0.42)
            spawnPop(orb.x, orb.y, "yellow", 26, 0.22)
            gainXp(orb.value + xpBonus)
            continue
          }
          active.push(orb)
        }
        orbs = active
        if (magnetHit) triggerMagnetBurst()
      }

      function gainXp(amount) {
        xp += amount
        if (xp >= xpToNext) {
          xp -= xpToNext
          levelUp()
        }
      }

      function upgradePool() {
        var pool = []
        if (ringLevel === 0) pool.push({ id: "unlock-ring", title: "FIREWALL RING", detail: "Unlock a periodic AoE pulse around you." })
        if (orbitLevel === 0) pool.push({ id: "unlock-orbit", title: "PATCH ORBIT", detail: "Unlock an orbiting shard that damages on contact." })
        if (chainLevel === 0) pool.push({ id: "unlock-chain", title: "TRACEROUTE ARC", detail: "Unlock chain lightning that arcs between nearby threats." })
        if (mineLevel === 0) pool.push({ id: "unlock-mine", title: "HONEYPOT MINE", detail: "Unlock a proximity trap that detonates on contact." })
        if (turretLevel === 0) pool.push({ id: "unlock-turret", title: "AUTO-TURRET", detail: "Deploy a stationary turret that lasers nearby threats." })
        if (ringLevel > 0) pool.push({ id: "ring-up", title: "RING OVERCLOCK", detail: "Firewall Ring: +radius, +damage, faster pulse." })
        if (orbitLevel > 0) pool.push({ id: "orbit-up", title: "ORBIT SHARD", detail: orbitLevel < orbitShardCap ? "Patch Orbit: +1 shard." : "Patch Orbit: +damage per shard (shard count capped)." })
        if (orbitLevel > 0) pool.push({ id: "orbit-range-up", title: "ORBIT EXPANSE", detail: "Patch Orbit: shards orbit further out." })
        if (chainLevel > 0) pool.push({ id: "chain-up", title: "ARC OVERCLOCK", detail: "Traceroute Arc: +damage, +1 jump, faster pulse." })
        if (mineLevel > 0) pool.push({ id: "mine-up", title: "MINE OVERCLOCK", detail: "Honeypot Mine: +blast radius, +damage, faster redeploy." })
        if (mineLevel > 0 && mineCapBonus < mineCapBonusMax) pool.push({ id: "mine-cap-up", title: "EXPANDED PAYLOAD", detail: "Honeypot Mine: +1 max deployed at once." })
        if (mineLevel > 0 && !mineCascade && !mineEvolved) pool.push({ id: "mine-cascade", title: "CASCADE TRIGGER", detail: "Honeypot Mine: blasts also detonate nearby mines." })
        if (turretLevel > 0) pool.push({ id: "turret-up", title: "TURRET OVERCLOCK", detail: "Auto-Turret: +damage, +range, faster fire and redeploy." })
        pool.push({ id: "burst-up", title: "PACKET OVERCLOCK", detail: "Packet Burst: faster fire, +pierce, +damage." })
        if (burstMultiLevel < burstMultiCap) pool.push({ id: "burst-multi-up", title: "PACKET FORK", detail: "Packet Burst: +1 simultaneous target." })
        if (burstSpreadLevel < burstSpreadCap) pool.push({ id: "burst-spread-up", title: "SPREAD ROUTING", detail: "Packet Burst: +2 angled bolts per shot." })
        pool.push({ id: "speed-up", title: "IO BOOST", detail: "+15% movement speed." })
        pool.push({ id: "hp-up", title: "INTEGRITY PATCH", detail: "+1 max integrity, heal 1." })
        pool.push({ id: "pickup-up", title: "WIDE SCAN", detail: "+ pickup radius for stray packets." })
        pool.push({ id: "xp-up", title: "CACHE BOOST", detail: "+1 value on every packet collected." })
        pool.push({ id: "shield-up", title: "HARDENED SHELL", detail: "+0.15s invulnerability after each hit." })
        pool.push({ id: "regen-up", title: "AUTO-PATCH", detail: "Slowly regenerate integrity over time." })
        pool.push({ id: "failover-up", title: "FAILOVER", detail: "+1 auto-revive at half integrity when you'd die." })
        pool.push({ id: "crit-up", title: "EXPLOIT CHANCE", detail: "+10% chance any hit deals double damage." })
        pool.push({ id: "slow-aura-up", title: "THROTTLE FIELD", detail: "Enemies near you move slower." })

        if (!burstEvolved && burstLevel >= burstMaxLevel && speedBonus >= catalystMaxLevel)
          pool.push({ id: "evolve-burst", title: "PACKET STORM", detail: "EVOLUTION: Packet Burst strikes every visible target at once." })
        if (!ringEvolved && ringLevel >= ringMaxLevel && shieldBonus >= catalystMaxLevel)
          pool.push({ id: "evolve-ring", title: "AEGIS PROTOCOL", detail: "EVOLUTION: Firewall Ring pulses rapidly and blunts incoming damage." })
        if (!orbitEvolved && orbitLevel >= orbitMaxLevel && slowAuraLevel >= catalystMaxLevel)
          pool.push({ id: "evolve-orbit", title: "ORBIT STORM", detail: "EVOLUTION: Patch Orbit shards spin faster, bigger, and hit harder." })
        if (!chainEvolved && chainLevel >= chainMaxLevel && critLevel >= catalystMaxLevel)
          pool.push({ id: "evolve-chain", title: "ARC CASCADE", detail: "EVOLUTION: Traceroute Arc always crits and chains to every threat." })
        if (!mineEvolved && mineLevel >= mineMaxLevel && regenLevel >= catalystMaxLevel)
          pool.push({ id: "evolve-mine", title: "MINEFIELD PROTOCOL", detail: "EVOLUTION: Honeypot Mine redeploys instantly and always cascades." })
        return pool
      }

      function rollUpgrades() {
        var working = upgradePool()
        var pick = []
        while (pick.length < 3 && working.length > 0) {
          var index = Math.floor(Math.random() * working.length)
          pick.push(working[index])
          working.splice(index, 1)
        }
        upgradeChoices = pick
      }

      function levelUp() {
        level += 1
        score += 40
        rollUpgrades()
        mode = "levelup"
        shell.play(levelSound)
        spawnBurst(playerX, playerY, "yellow", 40, 240, 0.7)
        spawnBurst(playerX, playerY, "foreground", 16, 300, 0.45)
        spawnPop(playerX, playerY, "accent", 110, 0.55)
        spawnPop(playerX, playerY, "yellow", 75, 0.4)
        killFlash = Math.max(killFlash, 0.14)
      }

      function announceEvolution(name) {
        statusMessage = "WEAPON EVOLVED // " + name
        spawnBurst(playerX, playerY, "accent", 50, 280, 0.8)
        spawnBurst(playerX, playerY, "yellow", 30, 320, 0.6)
        spawnPop(playerX, playerY, "accent", 160, 0.6)
        spawnPop(playerX, playerY, "yellow", 110, 0.45)
        spawnShake(9, 0.35)
        killFlash = Math.max(killFlash, 0.3)
        shell.play(levelSound)
      }

      function applyUpgrade(id) {
        if (id === "unlock-ring") { ringLevel = 1; ringCooldown = 1.0 }
        else if (id === "unlock-orbit") orbitLevel = 1
        else if (id === "unlock-chain") { chainLevel = 1; chainCooldown = 0.8 }
        else if (id === "unlock-mine") { mineLevel = 1; mineCooldown = 1.2 }
        else if (id === "unlock-turret") { turretLevel = 1; turretCooldown = 1.5 }
        else if (id === "ring-up") ringLevel += 1
        else if (id === "orbit-up") orbitLevel += 1
        else if (id === "orbit-range-up") orbitRangeLevel += 1
        else if (id === "chain-up") chainLevel += 1
        else if (id === "mine-up") mineLevel += 1
        else if (id === "mine-cap-up") mineCapBonus += 1
        else if (id === "mine-cascade") mineCascade = true
        else if (id === "turret-up") turretLevel += 1
        else if (id === "burst-up") burstLevel += 1
        else if (id === "burst-multi-up") burstMultiLevel += 1
        else if (id === "burst-spread-up") burstSpreadLevel += 1
        else if (id === "speed-up") speedBonus += 1
        else if (id === "hp-up") { maxHp += 1; hp = Math.min(maxHp, hp + 1) }
        else if (id === "pickup-up") pickupBonus += 1
        else if (id === "xp-up") xpBonus += 1
        else if (id === "shield-up") shieldBonus += 1
        else if (id === "regen-up") regenLevel += 1
        else if (id === "failover-up") failoverCharges += 1
        else if (id === "crit-up") critLevel += 1
        else if (id === "slow-aura-up") slowAuraLevel += 1
        else if (id === "evolve-burst") { burstEvolved = true; announceEvolution("PACKET STORM") }
        else if (id === "evolve-ring") { ringEvolved = true; announceEvolution("AEGIS PROTOCOL") }
        else if (id === "evolve-orbit") { orbitEvolved = true; announceEvolution("ORBIT STORM") }
        else if (id === "evolve-chain") { chainEvolved = true; announceEvolution("ARC CASCADE") }
        else if (id === "evolve-mine") { mineEvolved = true; announceEvolution("MINEFIELD PROTOCOL") }
        upgradeChoices = []
        mode = "playing"
      }

      function killsForWave(w) {
        return 8 + w * 5
      }

      function rollWaveReward() {
        var options = ["heal", "airdrop", "ammo", "shield", "score"]
        var pick = options[Math.floor(Math.random() * options.length)]
        if (pick === "heal") {
          if (hp < maxHp) { hp = maxHp; waveReward = "INTEGRITY RESTORED" }
          else { maxHp += 1; hp = maxHp; waveReward = "MAX INTEGRITY +1" }
        } else if (pick === "airdrop") {
          var bonus = 14 + wave * 2
          gainXp(bonus)
          waveReward = "PACKET AIRDROP // +" + bonus + " CACHE"
        } else if (pick === "ammo") {
          burstCooldown = 0; ringCooldown = 0; chainCooldown = 0; mineCooldown = 0
          waveReward = "AMMO CACHE // WEAPONS RECHARGED"
        } else if (pick === "shield") {
          var shieldDuration = 10 + Math.random() * 10
          invulnerable = Math.max(invulnerable, shieldDuration)
          waveReward = "EMERGENCY SHIELD // " + Math.round(shieldDuration) + "S INVULNERABLE"
        } else {
          var bonus2 = 100 + wave * 15
          score += bonus2
          waveReward = "SCORE SURGE // +" + bonus2
        }
      }

      function completeWave() {
        wave += 1
        waveKills = 0
        enemies = []
        mines = []
        bolts = []
        rings = []
        chains = []
        mode = "wavecomplete"
        waveTransitionLife = 2.0
        spawnBurst(playerX, playerY, "accent", 30, 200, 0.6)
        spawnPop(playerX, playerY, "accent", 100, 0.5)
        shell.play(levelSound)
        rollWaveReward()
      }

      function spawnBatchSize() {
        return Math.min(5, 1 + Math.floor(wave / 7))
      }

      function updateSpawns(dt) {
        spawnCooldown -= dt
        if (spawnCooldown <= 0 && enemies.length < maxEnemies) {
          var batch = spawnBatchSize()
          for (var i = 0; i < batch && enemies.length < maxEnemies; i++)
            spawnEnemyAt(pickEnemyType(), edgeSpawnPoint())
          spawnCooldown = Math.max(0.1, 0.85 - wave * 0.03) * (0.75 + Math.random() * 0.5)
        }
      }

      function updateElite(dt) {
        if (wave < 6) return
        if (eliteWarning > 0) {
          eliteWarning -= dt
          if (eliteWarning <= 0) {
            var isBoss = wantsBossSpawn()
            var bossType = bossTypePool()[Math.floor(Math.random() * bossTypePool().length)]
            var spawned = spawnElite(isBoss ? bossType : "rootkit", eliteWarningPos)
            var modTag = spawned && spawned.modifier ? " // " + spawned.modifier.toUpperCase() : ""
            if (isBoss) {
              lastBossWave = wave
              statusMessage = "MINI-BOSS BREACH" + modTag + " // DAEMON ENGAGED"
              spawnShake(10, 0.4)
              spawnBurst(eliteWarningPos.x, eliteWarningPos.y, "red", 40, 260, 0.7)
              spawnPop(eliteWarningPos.x, eliteWarningPos.y, "red", 120, 0.6)
            } else statusMessage = "ROOTKIT BREACH" + modTag + " // ELITE ENGAGED"
          }
          return
        }
        eliteCooldown -= dt
        if (eliteCooldown <= 0) {
          eliteWarningPos = edgeSpawnPoint()
          eliteWarning = 1.4
          eliteCooldown = Math.max(16, 42 - wave * 0.6)
          statusMessage = wantsBossSpawn() ? "MINI-BOSS DETECTED // INBOUND" : "ROOTKIT DETECTED // INBOUND"
        }
      }

      function wantsBossSpawn() {
        var milestone = wave >= 10 && wave % 5 === 0 && lastBossWave !== wave
        if (milestone) return true
        var bonusChance = wave >= 20 ? Math.min(0.35, (wave - 20) * 0.01) : 0
        return bonusChance > 0 && Math.random() < bonusChance
      }

      function finishRun() {
        leftHeld = rightHeld = upHeld = downHeld = false
        shell.play(deathSound)
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
        arcadeData.recordScore({ score: score, initials: initials, difficulty: "swarm", stage: wave,
                                 time: Math.round(elapsed), kills: kills, elites: elites, level: level })
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
        damageFlash = Math.max(0, damageFlash - dt)
        killFlash = Math.max(0, killFlash - dt)
        invulnerable = Math.max(0, invulnerable - dt)
        shakeTime = Math.max(0, shakeTime - dt)
        if (shakeTime <= 0) shakeMag = 0
        updateParticles(dt)
        updatePops(dt)
        updateChains(dt)
        updateDamageNumbers(dt)
        if (mode !== "playing") return
        elapsed += dt
        if (regenLevel > 0 && hp < maxHp) {
          regenTimer += dt
          var regenInterval = Math.max(3, 9 - regenLevel * 1.5)
          if (regenTimer >= regenInterval) {
            regenTimer -= regenInterval
            hp = Math.min(maxHp, hp + 1)
            spawnPop(playerX, playerY, "green", 30, 0.3)
          }
        }
        updateMovement(dt)
        updateCamera(dt)
        updateWeapons(dt)
        updateMines(dt)
        updateTurrets(dt)
        updateBeams(dt)
        updateEnemies(dt)
        if (mode !== "playing") return
        if (waveKills >= waveKillTarget) { completeWave(); return }
        updateOrbs(dt)
        if (mode !== "playing") return
        updateSpawns(dt)
        updateElite(dt)
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
        if (mode === "levelup") {
          if (event.key === Qt.Key_1 && upgradeChoices.length > 0) applyUpgrade(upgradeChoices[0].id)
          else if (event.key === Qt.Key_2 && upgradeChoices.length > 1) applyUpgrade(upgradeChoices[1].id)
          else if (event.key === Qt.Key_3 && upgradeChoices.length > 2) applyUpgrade(upgradeChoices[2].id)
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
        if (event.key === Qt.Key_Left || event.key === Qt.Key_A) leftHeld = true
        else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) rightHeld = true
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_W) upHeld = true
        else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) downHeld = true
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
        running: !game.tooSmall
        onTriggered: {
          var now = Date.now()
          var dt = Math.max(0.001, Math.min(0.05, (now - game.lastTickMs) / 1000))
          game.lastTickMs = now
          game.tick(dt)
          if (game.mode === "wavecomplete") {
            game.waveTransitionLife = Math.max(0, game.waveTransitionLife - dt)
            if (game.waveTransitionLife <= 0) game.mode = "playing"
          }
          worldCanvas.requestPaint()
          bgCanvas.requestPaint()
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
              Text { text: "THREAT LEVEL: " + game.alertLevel + "  //  KILLS " + game.waveKills + "/" + game.waveKillTarget; color: game.alertColor; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.statusMessage; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true; elide: Text.ElideRight; width: parent.width - 12 }
            }
            Repeater {
              model: [
                { label: "SCORE", value: game.score },
                { label: "WAVE", value: game.wave },
                { label: "LEVEL", value: game.level },
                { label: "INTEGRITY", value: game.hp + "/" + game.maxHp }
              ]
              delegate: Column {
                width: (parent.width * 0.60) / 4
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.label; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
                Text { text: modelData.value; color: modelData.label === "INTEGRITY" && game.hp <= 2 ? theme.red : theme.foreground; font.pixelSize: 18; font.family: "monospace"; font.bold: true }
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
            id: bgCanvas
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * game.worldAspect)
            height: width / game.worldAspect
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
              var context = getContext("2d")
              context.reset()
              context.fillStyle = theme.background
              context.fillRect(0, 0, width, height)
              var bgSx = width / game.viewportWidth
              var bgSy = height / game.viewportHeight
              context.save()
              context.scale(bgSx, bgSy)

              // Ambient glow stays centered on the viewport, not the world -- reads as a
              // constant "torchlight" around the player instead of one fixed bright spot
              // somewhere in the much larger arena.
              var glow = context.createRadialGradient(game.viewportWidth / 2, game.viewportHeight / 2, 40,
                                                        game.viewportWidth / 2, game.viewportHeight / 2, game.viewportWidth * 0.72)
              glow.addColorStop(0, theme.surface)
              glow.addColorStop(1, theme.background)
              context.fillStyle = glow
              context.fillRect(0, 0, game.viewportWidth, game.viewportHeight)

              function drawStars(list, parallax, minAlpha, maxAlpha, size) {
                context.save()
                context.translate(game.viewportWidth / 2 - game.cameraX * parallax, game.viewportHeight / 2 - game.cameraY * parallax)
                for (var i = 0; i < list.length; i++) {
                  var point = list[i]
                  context.globalAlpha = minAlpha + (maxAlpha - minAlpha) * (0.5 + 0.5 * Math.sin(game.animationTime * 1.6 + point.phase))
                  context.fillStyle = theme.foreground
                  context.fillRect(point.x, point.y, size, size)
                }
                context.restore()
              }
              drawStars(game.starsFar, game.parallaxFar, 0.08, 0.22, 1)
              drawStars(game.starsNear, game.parallaxNear, 0.16, 0.38, 1.6)
              context.globalAlpha = 1

              context.save()
              context.translate(game.viewportWidth / 2 - game.cameraX, game.viewportHeight / 2 - game.cameraY)

              context.strokeStyle = theme.muted
              context.globalAlpha = 0.08
              context.lineWidth = 1
              context.beginPath()
              for (var gridX = 0; gridX <= game.worldWidth; gridX += 60) {
                context.moveTo(gridX, 0); context.lineTo(gridX, game.worldHeight)
              }
              for (var gridY = 0; gridY <= game.worldHeight; gridY += 60) {
                context.moveTo(0, gridY); context.lineTo(game.worldWidth, gridY)
              }
              context.stroke()
              context.globalAlpha = 1

              context.strokeStyle = theme.accent
              context.globalAlpha = 0.35
              context.lineWidth = 3
              context.strokeRect(4, 4, game.worldWidth - 8, game.worldHeight - 8)
              context.globalAlpha = 1
              context.restore()

              context.restore()
            }
          }

          Canvas {
            id: worldCanvas
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height * game.worldAspect)
            height: width / game.worldAspect
            renderStrategy: Canvas.Threaded
            onPaint: {
              var context = getContext("2d")
              context.reset()
              var sx = width / game.viewportWidth
              var sy = height / game.viewportHeight
              context.save()
              context.scale(sx, sy)
              context.translate(game.viewportWidth / 2 - game.cameraX, game.viewportHeight / 2 - game.cameraY)
              if (game.shakeTime > 0) {
                var shakeAmt = game.shakeMag * Math.min(1, game.shakeTime / 0.15)
                context.translate((Math.random() - 0.5) * shakeAmt, (Math.random() - 0.5) * shakeAmt)
              }

              if (game.eliteWarning > 0) {
                var warnPulse = 30 + 14 * Math.sin(game.animationTime * 14)
                context.globalAlpha = 0.6
                context.strokeStyle = theme.red
                context.lineWidth = 3
                context.beginPath(); context.arc(game.eliteWarningPos.x, game.eliteWarningPos.y, warnPulse, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 1
              }

              for (var oi = 0; oi < game.orbs.length; oi++) {
                var orb = game.orbs[oi]
                if (orb.kind === "magnet") {
                  var magPulse = 7 + 3 * Math.sin(game.animationTime * 8 + oi)
                  context.globalAlpha = 0.28
                  context.strokeStyle = theme.accent
                  context.lineWidth = 6
                  context.beginPath(); context.arc(orb.x, orb.y, magPulse + 6, 0, Math.PI * 2); context.stroke()
                  context.globalAlpha = 0.95
                  context.fillStyle = theme.accent
                  context.beginPath(); context.arc(orb.x, orb.y, magPulse, 0, Math.PI * 2); context.fill()
                  context.globalAlpha = 1
                  context.strokeStyle = theme.foreground
                  context.lineWidth = 1.6
                  context.beginPath(); context.arc(orb.x, orb.y, magPulse, 0, Math.PI * 2); context.stroke()
                } else {
                  context.globalAlpha = 0.5 + 0.3 * Math.sin(game.animationTime * 6 + oi)
                  context.fillStyle = theme.yellow
                  context.beginPath(); context.arc(orb.x, orb.y, 5, 0, Math.PI * 2); context.fill()
                }
              }
              context.globalAlpha = 1

              for (var ei = 0; ei < game.enemies.length; ei++) {
                var en = game.enemies[ei]
                var col = game.colorFor(en.colorKey)
                var flashed = en.hitFlash > 0
                context.save()
                context.translate(en.x, en.y)
                context.globalAlpha = 0.16
                context.strokeStyle = col
                context.lineWidth = en.radius * 0.9
                context.beginPath(); context.arc(0, 0, en.radius * 0.6, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 1
                context.strokeStyle = flashed ? theme.foreground : col
                context.fillStyle = flashed ? theme.foreground : theme.background
                context.lineWidth = 2.2
                if (en.type === "worm") {
                  context.beginPath()
                  context.moveTo(0, -en.radius)
                  context.lineTo(en.radius * 0.85, en.radius * 0.7)
                  context.lineTo(-en.radius * 0.85, en.radius * 0.7)
                  context.closePath(); context.fill(); context.stroke()
                } else if (en.type === "fork" || en.type === "fork-child") {
                  context.rotate(game.animationTime * 2)
                  context.beginPath()
                  context.moveTo(0, -en.radius); context.lineTo(en.radius, 0); context.lineTo(0, en.radius); context.lineTo(-en.radius, 0)
                  context.closePath(); context.fill(); context.stroke()
                } else if (en.type === "trojan") {
                  context.beginPath()
                  for (var hx = 0; hx < 6; hx++) {
                    var hAng = Math.PI / 3 * hx
                    var hxp = Math.cos(hAng) * en.radius, hyp = Math.sin(hAng) * en.radius
                    if (hx === 0) context.moveTo(hxp, hyp); else context.lineTo(hxp, hyp)
                  }
                  context.closePath(); context.fill(); context.stroke()
                } else if (game.isBossType(en.type)) {
                  context.rotate(game.animationTime * 0.5)
                  context.beginPath()
                  for (var sx = 0; sx < 12; sx++) {
                    var sAng = Math.PI / 6 * sx
                    var sr = (sx % 2 === 0) ? en.radius : en.radius * 0.6
                    var sxp = Math.cos(sAng) * sr, syp = Math.sin(sAng) * sr
                    if (sx === 0) context.moveTo(sxp, syp); else context.lineTo(sxp, syp)
                  }
                  context.closePath(); context.fill(); context.stroke()
                  context.strokeStyle = theme.foreground
                  context.lineWidth = 1.6
                  context.globalAlpha = 0.6
                  context.beginPath(); context.arc(0, 0, en.radius * 0.45, 0, Math.PI * 2); context.stroke()
                  context.globalAlpha = 1
                } else {
                  context.rotate(game.animationTime * 0.8)
                  context.beginPath()
                  for (var rx = 0; rx < 6; rx++) {
                    var rAng = Math.PI / 3 * rx
                    var rxp = Math.cos(rAng) * en.radius, ryp = Math.sin(rAng) * en.radius
                    if (rx === 0) context.moveTo(rxp, ryp); else context.lineTo(rxp, ryp)
                  }
                  context.closePath(); context.fill(); context.stroke()
                  context.strokeStyle = theme.orange
                  context.lineWidth = 2
                  context.beginPath(); context.arc(0, 0, en.radius * 0.55, 0, Math.PI * 2); context.stroke()
                }
                context.restore()
                if (en.modifier === "shielded") {
                  context.globalAlpha = 0.55
                  context.strokeStyle = theme.accent
                  context.lineWidth = 2.4
                  context.beginPath(); context.arc(en.x, en.y, en.radius + 7, 0, Math.PI * 2); context.stroke()
                  context.globalAlpha = 1
                } else if (en.modifier === "fast") {
                  context.globalAlpha = 0.4
                  context.strokeStyle = theme.yellow
                  context.lineWidth = 1.6
                  context.beginPath(); context.arc(en.x, en.y, en.radius + 5, 0, Math.PI * 2); context.stroke()
                  context.globalAlpha = 1
                } else if (en.modifier === "volatile") {
                  context.globalAlpha = 0.35 + 0.35 * Math.sin(game.animationTime * 10)
                  context.strokeStyle = theme.red
                  context.lineWidth = 2.2
                  context.beginPath(); context.arc(en.x, en.y, en.radius + 6, 0, Math.PI * 2); context.stroke()
                  context.globalAlpha = 1
                }
                if (en.type === "rootkit" || game.isBossType(en.type)) {
                  context.fillStyle = theme.foreground
                  context.font = "bold 9px monospace"
                  context.textAlign = "center"
                  var modTag = en.modifier ? " " + en.modifier.toUpperCase() : ""
                  context.fillText(Math.max(0, en.hp) + "/" + en.maxHp + modTag, en.x, en.y - en.radius - 8)
                }
              }
              context.globalAlpha = 1

              for (var bi2 = 0; bi2 < game.bolts.length; bi2++) {
                var b = game.bolts[bi2]
                var boltCol = b.evolved ? theme.yellow : theme.accent
                var tailDX = game.playerX - b.x, tailDY = game.playerY - b.y
                var tailDist = Math.sqrt(tailDX * tailDX + tailDY * tailDY) || 1
                var tailLen = Math.min(tailDist, 16)
                var tailX = b.x + tailDX / tailDist * tailLen, tailY = b.y + tailDY / tailDist * tailLen
                context.globalAlpha = 0.3
                context.strokeStyle = boltCol
                context.lineWidth = 8
                context.beginPath(); context.moveTo(tailX, tailY); context.lineTo(b.x, b.y); context.stroke()
                context.globalAlpha = 1
                context.lineWidth = 2.6
                context.strokeStyle = theme.foreground
                context.beginPath(); context.moveTo(tailX, tailY); context.lineTo(b.x, b.y); context.stroke()
                context.fillStyle = boltCol
                context.beginPath(); context.arc(b.x, b.y, 3.2, 0, Math.PI * 2); context.fill()
                context.fillStyle = theme.foreground
                context.beginPath(); context.arc(b.x, b.y, 1.4, 0, Math.PI * 2); context.fill()
              }

              for (var mi = 0; mi < game.mines.length; mi++) {
                var mine = game.mines[mi]
                var mineCol = mine.evolved ? theme.yellow : theme.orange
                var armed = mine.armTime <= 0
                var minePulse = 0.55 + 0.35 * Math.sin(game.animationTime * (armed ? 9 : 4))
                context.globalAlpha = 0.18
                context.strokeStyle = mineCol
                context.lineWidth = 9
                context.beginPath(); context.arc(mine.x, mine.y, mine.radius + 6, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = armed ? minePulse : 0.35
                context.strokeStyle = mineCol
                context.lineWidth = 2.2
                context.beginPath(); context.arc(mine.x, mine.y, mine.radius, 0, Math.PI * 2); context.stroke()
                context.fillStyle = mineCol
                context.globalAlpha = armed ? 0.9 : 0.4
                context.beginPath(); context.arc(mine.x, mine.y, 3.4, 0, Math.PI * 2); context.fill()
              }
              context.globalAlpha = 1

              for (var tui = 0; tui < game.turrets.length; tui++) {
                var turret = game.turrets[tui]
                var turretHpRatio = Math.max(0, turret.hp / turret.maxHp)
                context.globalAlpha = 0.85
                context.fillStyle = theme.accent
                context.beginPath(); context.arc(turret.x, turret.y, 10, 0, Math.PI * 2); context.fill()
                context.strokeStyle = theme.foreground
                context.lineWidth = 1.6
                context.beginPath(); context.arc(turret.x, turret.y, 10, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 1
                context.strokeStyle = theme.muted
                context.lineWidth = 3
                context.beginPath(); context.moveTo(turret.x - 8, turret.y - 15); context.lineTo(turret.x + 8, turret.y - 15); context.stroke()
                context.strokeStyle = turretHpRatio > 0.4 ? theme.green : theme.red
                context.lineWidth = 3
                context.beginPath(); context.moveTo(turret.x - 8, turret.y - 15); context.lineTo(turret.x - 8 + 16 * turretHpRatio, turret.y - 15); context.stroke()
              }
              context.globalAlpha = 1

              for (var bmi = 0; bmi < game.beams.length; bmi++) {
                var beam = game.beams[bmi]
                var beamAlpha = Math.max(0, 1 - beam.life / beam.duration)
                context.globalAlpha = beamAlpha
                context.strokeStyle = theme.red
                context.lineWidth = 2.6
                context.beginPath(); context.moveTo(beam.x1, beam.y1); context.lineTo(beam.x2, beam.y2); context.stroke()
                context.globalAlpha = beamAlpha * 0.6
                context.lineWidth = 1
                context.strokeStyle = theme.foreground
                context.beginPath(); context.moveTo(beam.x1, beam.y1); context.lineTo(beam.x2, beam.y2); context.stroke()
              }
              context.globalAlpha = 1

              for (var ci = 0; ci < game.chains.length; ci++) {
                var chain = game.chains[ci]
                var chainCol = chain.evolved ? theme.accent : theme.yellow
                var chainProg = Math.min(1, chain.life / chain.duration)
                var chainAlpha = 1 - chainProg
                context.globalAlpha = 0.3 * chainAlpha
                context.strokeStyle = chainCol
                context.lineWidth = chain.evolved ? 10 : 8
                context.beginPath()
                for (var cp = 0; cp < chain.points.length; cp++) {
                  var pt = chain.points[cp]
                  if (cp === 0) context.moveTo(pt.x, pt.y); else context.lineTo(pt.x, pt.y)
                }
                context.stroke()
                context.globalAlpha = chainAlpha
                context.lineWidth = 2.4
                context.strokeStyle = theme.foreground
                context.beginPath()
                for (var cp2 = 0; cp2 < chain.points.length; cp2++) {
                  var pt2 = chain.points[cp2]
                  if (cp2 === 0) context.moveTo(pt2.x, pt2.y); else context.lineTo(pt2.x, pt2.y)
                }
                context.stroke()
              }
              context.globalAlpha = 1

              for (var ring2 = 0; ring2 < game.rings.length; ring2++) {
                var rg = game.rings[ring2]
                var ringCol = rg.evolved ? theme.yellow : theme.green
                var prog = Math.min(1, rg.life / rg.duration)
                var rad = rg.maxRadius * Math.sin(prog * Math.PI * 0.5)
                context.globalAlpha = 0.24
                context.fillStyle = ringCol
                context.beginPath(); context.arc(rg.x, rg.y, rad, 0, Math.PI * 2); context.fill()
                context.globalAlpha = 0.95
                context.strokeStyle = ringCol
                context.lineWidth = 4
                context.beginPath(); context.arc(rg.x, rg.y, rad, 0, Math.PI * 2); context.stroke()
              }
              context.globalAlpha = 1

              for (var popIdx = 0; popIdx < game.pops.length; popIdx++) {
                var pop = game.pops[popIdx]
                var popProg = Math.min(1, pop.life / pop.duration)
                var popRad = pop.maxRadius * Math.sin(popProg * Math.PI * 0.5)
                var popCol = game.colorFor(pop.colorKey)
                context.globalAlpha = (1 - popProg)
                context.strokeStyle = popCol
                context.lineWidth = 4
                context.beginPath(); context.arc(pop.x, pop.y, popRad, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 0.5 * (1 - popProg)
                context.lineWidth = 1.6
                context.beginPath(); context.arc(pop.x, pop.y, popRad * 0.6, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 0.4 * (1 - popProg)
                context.fillStyle = popCol
                context.beginPath(); context.arc(pop.x, pop.y, popRad * 0.18, 0, Math.PI * 2); context.fill()
              }
              context.globalAlpha = 1

              for (var pi = 0; pi < game.particles.length; pi++) {
                var particle = game.particles[pi]
                var lifeRatio = Math.max(0, particle.life / particle.maxLife)
                var pcol = game.colorFor(particle.colorKey)
                context.globalAlpha = 0.38 * lifeRatio
                context.fillStyle = pcol
                context.beginPath(); context.arc(particle.x, particle.y, particle.size * 2.4, 0, Math.PI * 2); context.fill()
                context.globalAlpha = lifeRatio
                context.beginPath(); context.arc(particle.x, particle.y, particle.size, 0, Math.PI * 2); context.fill()
              }
              context.globalAlpha = 1

              context.textAlign = "center"
              for (var dni = 0; dni < game.damageNumbers.length; dni++) {
                var dn = game.damageNumbers[dni]
                context.globalAlpha = Math.max(0, dn.life / dn.maxLife)
                context.font = dn.crit ? "bold 16px monospace" : "bold 11px monospace"
                context.fillStyle = dn.crit ? theme.yellow : theme.orange
                context.fillText(dn.value + (dn.crit ? "!" : ""), dn.x, dn.y)
              }
              context.globalAlpha = 1

              if (game.slowAuraLevel > 0) {
                context.globalAlpha = 0.12
                context.strokeStyle = theme.yellow
                context.lineWidth = 3
                context.beginPath(); context.arc(game.playerX, game.playerY, game.slowAuraRadius, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = 1
              }

              if (game.orbitLevel > 0) {
                var orbitCol = game.orbitEvolved ? theme.yellow : theme.accent
                for (var os = 0; os < game.orbitShardCount; os++) {
                  var oAng = game.animationTime * game.orbitSpin + os * (Math.PI * 2 / game.orbitShardCount)
                  var ox = game.playerX + Math.cos(oAng) * game.orbitRadius
                  var oy = game.playerY + Math.sin(oAng) * game.orbitRadius
                  context.globalAlpha = 0.32
                  context.strokeStyle = orbitCol
                  context.lineWidth = 1.6
                  context.beginPath(); context.moveTo(game.playerX, game.playerY); context.lineTo(ox, oy); context.stroke()
                  context.globalAlpha = 0.24
                  context.fillStyle = orbitCol
                  context.beginPath(); context.arc(ox, oy, game.orbitEvolved ? 12 : 9, 0, Math.PI * 2); context.fill()
                  context.globalAlpha = 1
                  context.beginPath(); context.arc(ox, oy, game.orbitEvolved ? 7 : 5, 0, Math.PI * 2); context.fill()
                }
              }
              context.globalAlpha = 1

              var blink = game.invulnerable > 0 && Math.floor(game.animationTime * 14) % 2 === 0
              if (!blink) {
                var pulse = 3 * Math.sin(game.animationTime * 5)
                context.save()
                context.translate(game.playerX, game.playerY)
                context.rotate(game.animationTime * 0.6)
                context.globalAlpha = 0.3
                context.strokeStyle = theme.accent
                context.lineWidth = 11
                context.beginPath()
                for (var v = 0; v < 6; v++) {
                  var ang = Math.PI / 3 * v
                  var rr = game.playerRadius + 6 + pulse
                  var vx = Math.cos(ang) * rr, vy = Math.sin(ang) * rr
                  if (v === 0) context.moveTo(vx, vy); else context.lineTo(vx, vy)
                }
                context.closePath(); context.stroke()
                context.globalAlpha = 0.95
                context.lineWidth = 3
                context.strokeStyle = theme.accent
                context.beginPath()
                for (var v2 = 0; v2 < 6; v2++) {
                  var ang2 = Math.PI / 3 * v2
                  var vx2 = Math.cos(ang2) * game.playerRadius, vy2 = Math.sin(ang2) * game.playerRadius
                  if (v2 === 0) context.moveTo(vx2, vy2); else context.lineTo(vx2, vy2)
                }
                context.closePath(); context.stroke()
                context.fillStyle = theme.foreground
                context.globalAlpha = 1
                context.beginPath(); context.arc(0, 0, 3, 0, Math.PI * 2); context.fill()
                context.restore()
              }

              context.restore()

              if (game.damageFlash > 0) {
                context.globalAlpha = Math.min(0.38, game.damageFlash)
                context.fillStyle = theme.red
                context.fillRect(0, 0, width, height)
                context.globalAlpha = 1
              }
              if (game.killFlash > 0) {
                context.globalAlpha = Math.min(0.24, game.killFlash)
                context.fillStyle = theme.accent
                context.fillRect(0, 0, width, height)
                context.globalAlpha = 1
              }
            }
          }

          Rectangle {
            visible: game.mode === "playing" || game.mode === "paused" || game.mode === "levelup"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 10
            width: loadoutColumn.implicitWidth + 20
            height: loadoutColumn.implicitHeight + 14
            radius: 6
            color: theme.surface
            opacity: 0.85
            border.color: theme.muted
            border.width: 1
            Column {
              id: loadoutColumn
              anchors.centerIn: parent
              spacing: 3
              Text { text: "LOADOUT"; color: theme.muted; font.pixelSize: 9; font.family: "monospace"; font.bold: true }
              Text { text: game.burstStatusText(); color: game.burstEvolved ? theme.yellow : theme.accent; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.ringStatusText(); color: game.ringEvolved ? theme.yellow : (game.ringLevel > 0 ? theme.green : theme.muted); font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.orbitStatusText(); color: game.orbitEvolved ? theme.yellow : (game.orbitLevel > 0 ? theme.green : theme.muted); font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.chainStatusText(); color: game.chainEvolved ? theme.accent : (game.chainLevel > 0 ? theme.yellow : theme.muted); font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.mineStatusText(); color: game.mineEvolved ? theme.yellow : (game.mineLevel > 0 ? theme.orange : theme.muted); font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: game.turretStatusText(); color: game.turretLevel > 0 ? theme.accent : theme.muted; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Rectangle { visible: game.speedBonus > 0 || game.pickupBonus > 0 || game.maxHp > 5 || game.xpBonus > 0 || game.shieldBonus > 0 || game.regenLevel > 0 || game.failoverCharges > 0 || game.critLevel > 0 || game.slowAuraLevel > 0; width: parent.width; height: 1; color: theme.muted }
              Text { visible: game.speedBonus > 0; text: "SPD    +" + (game.speedBonus * 15) + "%  " + game.levelTag(game.speedBonus, game.catalystMaxLevel); color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.pickupBonus > 0; text: "SCAN   +" + game.pickupBonus; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.maxHp > 5; text: "MAX HP " + game.maxHp; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.xpBonus > 0; text: "CACHE  +" + game.xpBonus; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.shieldBonus > 0; text: "SHIELD +" + game.shieldBonus + "  " + game.levelTag(game.shieldBonus, game.catalystMaxLevel); color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.regenLevel > 0; text: "REGEN  " + game.levelTag(game.regenLevel, game.catalystMaxLevel); color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.failoverCharges > 0; text: "FAILOVER x" + game.failoverCharges; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.critLevel > 0; text: "CRIT   +" + (game.critLevel * 10) + "%  " + game.levelTag(game.critLevel, game.catalystMaxLevel); color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.slowAuraLevel > 0; text: "THROTTLE " + game.levelTag(game.slowAuraLevel, game.catalystMaxLevel); color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            visible: game.mode === "attract"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 650)
            height: Math.min(parent.height - 44, 440)
            radius: 12
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              width: parent.width - 58
              spacing: 12
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "OMACADE // CABINET " + shell.cabinet.number; color: theme.accent; font.pixelSize: 14; font.family: "monospace"; font.bold: true; font.letterSpacing: 2 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.displayTitle; color: theme.foreground; font.pixelSize: 34; font.bold: true; font.letterSpacing: 3 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: shell.cabinet.tagline.toUpperCase(); color: theme.green; font.pixelSize: 13; font.family: "monospace" }
              Rectangle { width: parent.width; height: 1; color: theme.muted }
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "A ROGUE PROCESS SWARM IS SPREADING. CLEAR EACH WAVE'S KILL QUOTA TO ADVANCE.\nCOLLECT PACKETS TO LEVEL UP AND CHOOSE NEW DEFENSES."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.3 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "AUTO-FIRE TARGETS THE NEAREST THREAT  ·  CLEARING A WAVE BANKS A FREE REWARD"; color: theme.green; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "FORKS SPLIT ON DEATH  ·  ROOTKIT ELITES FROM WAVE 6  ·  MINI-BOSSES FROM WAVE 10"; color: theme.orange; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "ELITES CAN BE SHIELDED, FAST, OR VOLATILE  ·  RARE MAGNET PACKETS SWEEP THE FIELD"; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "MINI-BOSSES GROW MORE UNPREDICTABLE AT HIGH WAVES  ·  DEPLOY AN AUTO-TURRET FOR COVERING FIRE"; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "← ↑ ↓ → / WASD MOVE"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "BEST " + arcadeData.bestScore + "   ·   FURTHEST WAVE " + arcadeData.highestStage; color: theme.yellow; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PRESS ENTER TO BOOT"; color: theme.accent; font.pixelSize: 18; font.family: "monospace"; font.bold: true
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
            visible: game.mode === "paused" || game.mode === "gameover"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 560)
            height: 170
            radius: 10
            color: theme.surface
            border.color: game.mode === "gameover" ? theme.red : theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 11
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "paused" ? "DAEMON SUSPENDED" : "PROCESS TERMINATED"; color: game.mode === "gameover" ? theme.red : theme.accent; font.pixelSize: 25; font.bold: true; font.letterSpacing: 1.5 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.mode === "gameover" ? "SCORE " + game.score + " // WAVE " + game.wave + " // LEVEL " + game.level + (shell.circuitMode ? "  ·  ENTER RETURN TO CIRCUIT" : "  ·  ENTER TO REBOOT") : "P TO RESUME"; color: theme.foreground; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
              Text { visible: game.mode === "gameover"; anchors.horizontalCenter: parent.horizontalCenter; text: "SURVIVED " + game.formatTime(game.elapsed) + " // " + game.kills + " KILLS // " + game.elites + " ELITES"; color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
            }
          }

          Rectangle {
            visible: game.mode === "wavecomplete"
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 560)
            height: 170
            radius: 10
            color: theme.surface
            border.color: theme.accent
            border.width: 2
            Column {
              anchors.centerIn: parent
              spacing: 11
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "WAVE " + (game.wave - 1) + " CLEARED"; color: theme.accent; font.pixelSize: 25; font.bold: true; font.letterSpacing: 1.5 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: game.waveReward; color: theme.yellow; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "WAVE " + game.wave + " INBOUND"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
            }
          }

          Rectangle {
            visible: game.mode === "levelup"
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 660)
            height: 270
            radius: 10
            color: theme.surface
            border.color: theme.yellow
            border.width: 2
            Column {
              anchors.centerIn: parent
              width: parent.width - 40
              spacing: 14
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "LEVEL " + game.level + " // PATCH AVAILABLE"; color: theme.yellow; font.pixelSize: 22; font.bold: true }
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14
                Repeater {
                  model: game.upgradeChoices
                  delegate: Rectangle {
                    property bool isEvolution: modelData.id.indexOf("evolve-") === 0
                    width: 190; height: 140; radius: 8
                    color: theme.background
                    border.color: isEvolution ? theme.yellow : theme.accent; border.width: isEvolution ? 2 : 1
                    Column {
                      anchors.fill: parent; anchors.margins: 12; spacing: 6
                      Text { visible: parent.parent.isEvolution; text: "★ EVOLUTION"; color: theme.yellow; font.pixelSize: 9; font.bold: true; font.family: "monospace"; font.letterSpacing: 1 }
                      Text { text: (index + 1) + "  " + modelData.title; color: parent.parent.isEvolution ? theme.yellow : theme.accent; font.pixelSize: 13; font.bold: true; font.family: "monospace"; wrapMode: Text.WordWrap; width: parent.width }
                      Text { text: modelData.detail; color: theme.foreground; font.pixelSize: 10; font.family: "monospace"; wrapMode: Text.WordWrap; width: parent.width }
                    }
                  }
                }
              }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "PRESS 1 / 2 / 3 TO SELECT"; color: theme.muted; font.pixelSize: 11; font.family: "monospace" }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "NEW UPTIME RECORD"; color: theme.yellow; font.pixelSize: 22; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SCORE " + game.score + "  //  WAVE " + game.wave + "  //  LEVEL " + game.level; color: theme.foreground; font.pixelSize: 13; font.family: "monospace"; font.bold: true }
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "DAEMON SWARM // TOP TEN"; color: theme.accent; font.pixelSize: 22; font.bold: true }
              Text { text: " #    PILOT       SCORE       WAVE    TIME"; color: theme.muted; font.pixelSize: 12; font.family: "monospace"; font.bold: true }
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
                    var rowTime = row ? game.formatTime(Number(row.time || 0)) : "--:--"
                    return rank + "    " + (pilot + "        ").slice(0, 8) + "  " + points + "       " + rowWave + "      " + rowTime
                  }
                  color: row && index === 0 ? theme.yellow : row ? theme.foreground : theme.muted
                  font.pixelSize: 14; font.family: "monospace"; font.bold: row && index === 0
                  textFormat: Text.PlainText
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
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "SWARM DISPLAY TOO SMALL"; color: theme.red; font.pixelSize: 22; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Enlarge the cabinet for a 560 × 560 arena."; color: theme.foreground; font.pixelSize: 12; font.family: "monospace" }
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
            text: "← ↑ ↓ → / WASD MOVE    AUTO-FIRE    P PAUSE    H RECORDS    Q QUIT"
            color: theme.muted; font.pixelSize: 10; font.family: "monospace"; font.bold: true
          }
        }
      }
    }
  }
}
