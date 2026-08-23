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

      readonly property real worldWidth: 900
      readonly property real worldHeight: 900
      readonly property real worldAspect: worldWidth / worldHeight
      readonly property bool tooSmall: worldCanvas.width < 560 || worldCanvas.height < 560
      readonly property real playerRadius: 13
      readonly property real orbitRadius: 58
      readonly property int orbitDamage: 1 + orbitLevel
      readonly property int maxEnemies: 90
      readonly property string alertLevel: wave < 4 ? "LOW" : wave < 8 ? "ELEVATED" : wave < 14 ? "SEVERE" : "CRITICAL"
      readonly property color alertColor: alertLevel === "LOW" ? theme.green : alertLevel === "ELEVATED" ? theme.yellow : alertLevel === "SEVERE" ? theme.orange : theme.red
      readonly property int xpToNext: 6 + level * 4
      readonly property int waveKillTarget: 8 + wave * 5
      readonly property real pickupRadius: 62 + pickupBonus * 16
      readonly property real moveSpeed: 190 * (1 + speedBonus * 0.12)
      readonly property real enemySpeedMul: 1 + Math.min(3.2, wave * 0.07)
      readonly property real enemyHpMul: 1 + wave * 0.1

      property string mode: "attract"
      property string modeBeforeScores: "attract"
      property real playerX: worldWidth / 2
      property real playerY: worldHeight / 2
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
      property int ringLevel: 0
      property int orbitLevel: 0
      property int chainLevel: 0
      property int mineLevel: 0
      property int speedBonus: 0
      property int pickupBonus: 0
      property int xpBonus: 0
      property int shieldBonus: 0
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
      property var enemies: []
      property var orbs: []
      property var bolts: []
      property var rings: []
      property var mines: []
      property var chains: []
      property var pops: []
      property var particles: []
      property var stars: []
      property var upgradeChoices: []
      property bool leftHeld: false
      property bool rightHeld: false
      property bool upHeld: false
      property bool downHeld: false
      property string statusMessage: "DAEMON ONLINE"
      property string initialsInput: ""
      property bool initialsPristine: true

      Component.onCompleted: {
        var generated = []
        for (var i = 0; i < 70; i++)
          generated.push({ x: Math.random() * worldWidth, y: Math.random() * worldHeight, phase: Math.random() * 6.28 })
        stars = generated
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
        ringLevel = 0
        orbitLevel = 0
        chainLevel = 0
        mineLevel = 0
        speedBonus = 0
        pickupBonus = 0
        xpBonus = 0
        shieldBonus = 0
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
        pops = []
        particles = []
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
        return { hp: 18, speed: 62, radius: 21, damage: 2, xp: 18, score: 400, color: "accent" }
      }

      function pickEnemyType() {
        var roll = Math.random()
        if (wave < 3) return "worm"
        if (wave < 6) return roll < 0.7 ? "worm" : "fork"
        if (wave < 12) return roll < 0.5 ? "worm" : roll < 0.82 ? "fork" : "trojan"
        return roll < 0.3 ? "worm" : roll < 0.62 ? "fork" : "trojan"
      }

      function edgeSpawnPoint() {
        var side = Math.floor(Math.random() * 4)
        var margin = 20
        if (side === 0) return { x: Math.random() * worldWidth, y: -margin }
        if (side === 1) return { x: worldWidth + margin, y: Math.random() * worldHeight }
        if (side === 2) return { x: Math.random() * worldWidth, y: worldHeight + margin }
        return { x: -margin, y: Math.random() * worldHeight }
      }

      function makeEnemy(type, pos) {
        var profile = enemyProfile(type)
        enemySerial += 1
        var scaledHp = Math.max(1, Math.round(profile.hp * enemyHpMul))
        return { id: enemySerial, type: type, x: pos.x, y: pos.y, hp: scaledHp, maxHp: scaledHp,
                 speed: profile.speed * enemySpeedMul, radius: profile.radius,
                 damage: profile.damage + Math.floor(wave / 15),
                 xp: profile.xp, score: profile.score, colorKey: profile.color, hitFlash: 0,
                 orbitCooldown: 0 }
      }

      function spawnEnemyAt(type, pos) {
        if (enemies.length >= maxEnemies) return
        enemies = enemies.concat([makeEnemy(type, pos)])
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

      function fireBurst() {
        var target = nearestEnemy()
        if (!target) return
        var dx = target.x - playerX
        var dy = target.y - playerY
        var dist = Math.sqrt(dx * dx + dy * dy) || 1
        var updated = bolts.slice(0)
        updated.push({ x: playerX, y: playerY, dirX: dx / dist, dirY: dy / dist, speed: 560,
                       damage: 1 + Math.floor((burstLevel - 1) / 2), pierce: burstLevel - 1,
                       travelled: 0, maxRange: 760, hitIds: [] })
        bolts = updated
        burstCooldown = Math.max(0.22, 1.15 - (burstLevel - 1) * 0.08)
      }

      function pulseRing() {
        var updated = rings.slice(0)
        updated.push({ x: playerX, y: playerY, life: 0, duration: 0.4,
                       maxRadius: 70 + ringLevel * 18, damage: 1 + ringLevel, hitIds: [] })
        rings = updated
        ringCooldown = Math.max(1.3, 2.6 - (ringLevel - 1) * 0.3)
      }

      function fireChain() {
        var target = nearestEnemy()
        if (!target) return
        var dmg = 1 + Math.floor(chainLevel / 2)
        var hitIds = {}
        var points = [{ x: playerX, y: playerY }]
        var current = target
        var jumps = Math.min(4, 2 + Math.floor(chainLevel / 2))
        for (var j = 0; j < jumps && current; j++) {
          hitIds[current.id] = true
          current.hp -= dmg
          current.hitFlash = 0.14
          points.push({ x: current.x, y: current.y })
          var next = null
          var bestD = 190 * 190
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
        updatedChains.push({ points: points, life: 0, duration: 0.2 })
        chains = updatedChains
        shell.play(hitSound)
        chainCooldown = Math.max(0.7, 1.5 - chainLevel * 0.15)
      }

      function dropMine() {
        var updated = mines.slice(0)
        updated.push({ x: playerX, y: playerY, armTime: 0.35, life: 0, maxLife: 9, radius: 15 })
        mines = updated
        mineCooldown = Math.max(2.4, 4.2 - mineLevel * 0.5)
      }

      function updateMines(dt) {
        var active = []
        for (var i = 0; i < mines.length; i++) {
          var mine = mines[i]
          mine.life += dt
          if (mine.armTime > 0) mine.armTime -= dt
          var armed = mine.armTime <= 0
          var triggered = false
          if (armed) {
            for (var e = 0; e < enemies.length; e++) {
              var enemy = enemies[e]
              var dx = enemy.x - mine.x, dy = enemy.y - mine.y
              if (dx * dx + dy * dy <= (mine.radius + enemy.radius) * (mine.radius + enemy.radius)) { triggered = true; break }
            }
          }
          if (triggered || mine.life >= mine.maxLife) {
            if (triggered) {
              var blastRadius = 78 + mineLevel * 16
              var blastDamage = 3 + mineLevel * 2
              for (var b = 0; b < enemies.length; b++) {
                var target = enemies[b]
                var bx = target.x - mine.x, by = target.y - mine.y
                if (bx * bx + by * by <= blastRadius * blastRadius) {
                  target.hp -= blastDamage
                  target.hitFlash = 0.14
                }
              }
              spawnBurst(mine.x, mine.y, "orange", 30, 240, 0.55)
              spawnPop(mine.x, mine.y, "orange", blastRadius, 0.42)
              spawnShake(6, 0.2)
              shell.play(hitSound)
            }
            continue
          }
          active.push(mine)
        }
        mines = active
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
      }

      function updateMovement(dt) {
        var dx = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0)
        var dy = (downHeld ? 1 : 0) - (upHeld ? 1 : 0)
        if (dx !== 0 && dy !== 0) { dx *= 0.7071; dy *= 0.7071 }
        playerX = Math.max(playerRadius, Math.min(worldWidth - playerRadius, playerX + dx * moveSpeed * dt))
        playerY = Math.max(playerRadius, Math.min(worldHeight - playerRadius, playerY + dy * moveSpeed * dt))
      }

      function killRewards(e) {
        score += e.score
        var updatedOrbs = orbs.slice(0)
        updatedOrbs.push({ x: e.x, y: e.y, value: e.xp })
        orbs = updatedOrbs
        if (e.type === "rootkit") {
          statusMessage = "ROOTKIT PURGED // +" + e.score
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
        hp -= amount
        invulnerable = 0.9 + shieldBonus * 0.15
        damageFlash = 0.4
        spawnShake(9, 0.26)
        shell.play(hurtSound)
        spawnBurst(playerX, playerY, "red", 20, 170, 0.45)
        spawnPop(playerX, playerY, "red", 50, 0.3)
        if (hp <= 0) { hp = 0; finishRun() }
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
              target.hp -= bolt.damage
              target.hitFlash = 0.12
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
              rtarget.hp -= ring.damage
              rtarget.hitFlash = 0.12
              ring.hitIds.push(rtarget.id)
            }
          }
          if (ring.life < ring.duration) newRings.push(ring)
        }
        rings = newRings

        if (orbitLevel > 0) {
          for (var s = 0; s < orbitLevel; s++) {
            var angle = animationTime * 3.1 + s * (Math.PI * 2 / orbitLevel)
            var sx = playerX + Math.cos(angle) * orbitRadius
            var sy = playerY + Math.sin(angle) * orbitRadius
            for (var oi = 0; oi < enemies.length; oi++) {
              var otarget = enemies[oi]
              var odx = otarget.x - sx
              var ody = otarget.y - sy
              if (odx * odx + ody * ody <= (otarget.radius + 8) * (otarget.radius + 8) && (otarget.orbitCooldown || 0) <= 0) {
                otarget.hp -= orbitDamage
                otarget.hitFlash = 0.12
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
            if (e.type === "rootkit") elites += 1
            if (e.type === "fork") {
              spawnQueue.push({ x: e.x, y: e.y })
              spawnQueue.push({ x: e.x, y: e.y })
            }
            continue
          }
          var dx = playerX - e.x
          var dy = playerY - e.y
          var dist = Math.sqrt(dx * dx + dy * dy) || 1
          e.x += dx / dist * e.speed * dt
          e.y += dy / dist * e.speed * dt
          if (dist < playerRadius + e.radius) damagePlayer(e.damage)
          survivors.push(e)
        }
        for (var q = 0; q < spawnQueue.length; q++)
          if (survivors.length < maxEnemies) survivors.push(makeEnemy("fork-child", spawnQueue[q]))
        enemies = survivors
      }

      function updateOrbs(dt) {
        var active = []
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
            if (Math.random() < 0.4) spawnBurst(orb.x, orb.y, "yellow", 1, 30, 0.18)
          }
          if (dist < 16) {
            spawnBurst(orb.x, orb.y, "yellow", 18, 220, 0.42)
            spawnPop(orb.x, orb.y, "yellow", 26, 0.22)
            gainXp(orb.value + xpBonus)
            continue
          }
          active.push(orb)
        }
        orbs = active
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
        if (ringLevel > 0) pool.push({ id: "ring-up", title: "RING OVERCLOCK", detail: "Firewall Ring: +radius, +damage, faster pulse." })
        if (orbitLevel > 0) pool.push({ id: "orbit-up", title: "ORBIT EXPANSION", detail: "Patch Orbit: +1 shard." })
        if (chainLevel > 0) pool.push({ id: "chain-up", title: "ARC OVERCLOCK", detail: "Traceroute Arc: +damage, +1 jump, faster pulse." })
        if (mineLevel > 0) pool.push({ id: "mine-up", title: "MINE OVERCLOCK", detail: "Honeypot Mine: +blast radius, +damage, faster redeploy." })
        pool.push({ id: "burst-up", title: "PACKET OVERCLOCK", detail: "Packet Burst: faster fire, +pierce, +damage." })
        pool.push({ id: "speed-up", title: "IO BOOST", detail: "+12% movement speed." })
        pool.push({ id: "hp-up", title: "INTEGRITY PATCH", detail: "+1 max integrity, heal 1." })
        pool.push({ id: "pickup-up", title: "WIDE SCAN", detail: "+ pickup radius for stray packets." })
        pool.push({ id: "xp-up", title: "CACHE BOOST", detail: "+1 value on every packet collected." })
        pool.push({ id: "shield-up", title: "HARDENED SHELL", detail: "+0.15s invulnerability after each hit." })
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

      function applyUpgrade(id) {
        if (id === "unlock-ring") { ringLevel = 1; ringCooldown = 1.0 }
        else if (id === "unlock-orbit") orbitLevel = 1
        else if (id === "unlock-chain") { chainLevel = 1; chainCooldown = 0.8 }
        else if (id === "unlock-mine") { mineLevel = 1; mineCooldown = 1.2 }
        else if (id === "ring-up") ringLevel += 1
        else if (id === "orbit-up") orbitLevel += 1
        else if (id === "chain-up") chainLevel += 1
        else if (id === "mine-up") mineLevel += 1
        else if (id === "burst-up") burstLevel += 1
        else if (id === "speed-up") speedBonus += 1
        else if (id === "hp-up") { maxHp += 1; hp = Math.min(maxHp, hp + 1) }
        else if (id === "pickup-up") pickupBonus += 1
        else if (id === "xp-up") xpBonus += 1
        else if (id === "shield-up") shieldBonus += 1
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
          invulnerable = Math.max(invulnerable, 3.0)
          waveReward = "EMERGENCY SHIELD // 3S INVULNERABLE"
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
        mode = "wavecomplete"
        waveTransitionLife = 2.0
        spawnBurst(playerX, playerY, "accent", 30, 200, 0.6)
        spawnPop(playerX, playerY, "accent", 100, 0.5)
        shell.play(levelSound)
        rollWaveReward()
      }

      function updateSpawns(dt) {
        spawnCooldown -= dt
        if (spawnCooldown <= 0 && enemies.length < maxEnemies) {
          spawnEnemyAt(pickEnemyType(), edgeSpawnPoint())
          spawnCooldown = Math.max(0.14, 1.0 - wave * 0.02) * (0.75 + Math.random() * 0.5)
        }
      }

      function updateElite(dt) {
        if (wave < 6) return
        if (eliteWarning > 0) {
          eliteWarning -= dt
          if (eliteWarning <= 0) {
            spawnEnemyAt("rootkit", eliteWarningPos)
            statusMessage = "ROOTKIT BREACH // ELITE ENGAGED"
          }
          return
        }
        eliteCooldown -= dt
        if (eliteCooldown <= 0) {
          eliteWarningPos = edgeSpawnPoint()
          eliteWarning = 1.4
          eliteCooldown = Math.max(16, 42 - wave * 0.6)
          statusMessage = "ROOTKIT DETECTED // INBOUND"
        }
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
        if (mode !== "playing") return
        elapsed += dt
        updateMovement(dt)
        updateWeapons(dt)
        updateMines(dt)
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
              var bgSx = width / game.worldWidth
              var bgSy = height / game.worldHeight
              context.save()
              context.scale(bgSx, bgSy)

              var glow = context.createRadialGradient(game.worldWidth / 2, game.worldHeight / 2, 40,
                                                        game.worldWidth / 2, game.worldHeight / 2, game.worldWidth * 0.72)
              glow.addColorStop(0, theme.surface)
              glow.addColorStop(1, theme.background)
              context.fillStyle = glow
              context.fillRect(0, 0, game.worldWidth, game.worldHeight)

              for (var star = 0; star < game.stars.length; star++) {
                var point = game.stars[star]
                context.globalAlpha = 0.18 + 0.3 * (0.5 + 0.5 * Math.sin(game.animationTime * 1.6 + point.phase))
                context.fillStyle = theme.foreground
                context.fillRect(point.x, point.y, 1, 1)
              }
              context.globalAlpha = 1

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
            }
          }

          Timer {
            interval: 120
            repeat: true
            running: true
            onTriggered: bgCanvas.requestPaint()
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
              var sx = width / game.worldWidth
              var sy = height / game.worldHeight
              context.save()
              context.scale(sx, sy)
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
                context.globalAlpha = 0.5 + 0.3 * Math.sin(game.animationTime * 6 + oi)
                context.fillStyle = theme.yellow
                context.beginPath(); context.arc(orb.x, orb.y, 5, 0, Math.PI * 2); context.fill()
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
                if (en.type === "rootkit") {
                  context.fillStyle = theme.foreground
                  context.font = "bold 9px monospace"
                  context.textAlign = "center"
                  context.fillText(Math.max(0, en.hp) + "/" + en.maxHp, en.x, en.y - en.radius - 8)
                }
              }
              context.globalAlpha = 1

              for (var bi2 = 0; bi2 < game.bolts.length; bi2++) {
                var b = game.bolts[bi2]
                var tailDX = game.playerX - b.x, tailDY = game.playerY - b.y
                var tailDist = Math.sqrt(tailDX * tailDX + tailDY * tailDY) || 1
                var tailLen = Math.min(tailDist, 16)
                var tailX = b.x + tailDX / tailDist * tailLen, tailY = b.y + tailDY / tailDist * tailLen
                context.globalAlpha = 0.3
                context.strokeStyle = theme.accent
                context.lineWidth = 8
                context.beginPath(); context.moveTo(tailX, tailY); context.lineTo(b.x, b.y); context.stroke()
                context.globalAlpha = 1
                context.lineWidth = 2.6
                context.strokeStyle = theme.foreground
                context.beginPath(); context.moveTo(tailX, tailY); context.lineTo(b.x, b.y); context.stroke()
                context.fillStyle = theme.accent
                context.beginPath(); context.arc(b.x, b.y, 3.2, 0, Math.PI * 2); context.fill()
                context.fillStyle = theme.foreground
                context.beginPath(); context.arc(b.x, b.y, 1.4, 0, Math.PI * 2); context.fill()
              }

              for (var mi = 0; mi < game.mines.length; mi++) {
                var mine = game.mines[mi]
                var armed = mine.armTime <= 0
                var minePulse = 0.55 + 0.35 * Math.sin(game.animationTime * (armed ? 9 : 4))
                context.globalAlpha = 0.18
                context.strokeStyle = theme.orange
                context.lineWidth = 9
                context.beginPath(); context.arc(mine.x, mine.y, mine.radius + 6, 0, Math.PI * 2); context.stroke()
                context.globalAlpha = armed ? minePulse : 0.35
                context.strokeStyle = theme.orange
                context.lineWidth = 2.2
                context.beginPath(); context.arc(mine.x, mine.y, mine.radius, 0, Math.PI * 2); context.stroke()
                context.fillStyle = theme.orange
                context.globalAlpha = armed ? 0.9 : 0.4
                context.beginPath(); context.arc(mine.x, mine.y, 3.4, 0, Math.PI * 2); context.fill()
              }
              context.globalAlpha = 1

              for (var ci = 0; ci < game.chains.length; ci++) {
                var chain = game.chains[ci]
                var chainProg = Math.min(1, chain.life / chain.duration)
                var chainAlpha = 1 - chainProg
                context.globalAlpha = 0.3 * chainAlpha
                context.strokeStyle = theme.yellow
                context.lineWidth = 8
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
                var prog = Math.min(1, rg.life / rg.duration)
                var rad = rg.maxRadius * Math.sin(prog * Math.PI * 0.5)
                context.globalAlpha = 0.24
                context.fillStyle = theme.green
                context.beginPath(); context.arc(rg.x, rg.y, rad, 0, Math.PI * 2); context.fill()
                context.globalAlpha = 0.95
                context.strokeStyle = theme.green
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

              if (game.orbitLevel > 0) {
                for (var os = 0; os < game.orbitLevel; os++) {
                  var oAng = game.animationTime * 3.1 + os * (Math.PI * 2 / game.orbitLevel)
                  var ox = game.playerX + Math.cos(oAng) * game.orbitRadius
                  var oy = game.playerY + Math.sin(oAng) * game.orbitRadius
                  context.globalAlpha = 0.32
                  context.strokeStyle = theme.accent
                  context.lineWidth = 1.6
                  context.beginPath(); context.moveTo(game.playerX, game.playerY); context.lineTo(ox, oy); context.stroke()
                  context.globalAlpha = 0.24
                  context.fillStyle = theme.accent
                  context.beginPath(); context.arc(ox, oy, 9, 0, Math.PI * 2); context.fill()
                  context.globalAlpha = 1
                  context.beginPath(); context.arc(ox, oy, 5, 0, Math.PI * 2); context.fill()
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
              Text { text: "BURST  Lv" + game.burstLevel; color: theme.accent; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: "RING   " + (game.ringLevel > 0 ? "Lv" + game.ringLevel : "--"); color: game.ringLevel > 0 ? theme.green : theme.muted; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: "ORBIT  " + (game.orbitLevel > 0 ? "Lv" + game.orbitLevel : "--"); color: game.orbitLevel > 0 ? theme.green : theme.muted; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: "ARC    " + (game.chainLevel > 0 ? "Lv" + game.chainLevel : "--"); color: game.chainLevel > 0 ? theme.yellow : theme.muted; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Text { text: "MINE   " + (game.mineLevel > 0 ? "Lv" + game.mineLevel : "--"); color: game.mineLevel > 0 ? theme.orange : theme.muted; font.pixelSize: 11; font.family: "monospace"; font.bold: true }
              Rectangle { visible: game.speedBonus > 0 || game.pickupBonus > 0 || game.maxHp > 5 || game.xpBonus > 0 || game.shieldBonus > 0; width: parent.width; height: 1; color: theme.muted }
              Text { visible: game.speedBonus > 0; text: "SPD    +" + (game.speedBonus * 12) + "%"; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.pickupBonus > 0; text: "SCAN   +" + game.pickupBonus; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.maxHp > 5; text: "MAX HP " + game.maxHp; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.xpBonus > 0; text: "CACHE  +" + game.xpBonus; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { visible: game.shieldBonus > 0; text: "SHIELD +" + game.shieldBonus; color: theme.yellow; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
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
              Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "A ROGUE PROCESS SWARM IS SPREADING. HOLD THE LINE AS LONG AS YOU CAN.\nCOLLECT PACKETS TO LEVEL UP AND CHOOSE NEW DEFENSES."; color: theme.foreground; font.pixelSize: 14; font.family: "monospace"; lineHeight: 1.3 }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "AUTO-FIRE TARGETS THE NEAREST THREAT  ·  YOU JUST NEED TO SURVIVE"; color: theme.green; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
              Text { anchors.horizontalCenter: parent.horizontalCenter; text: "FORKS SPLIT ON DEATH  ·  ROOTKIT ELITES BREACH AFTER T+2:30"; color: theme.orange; font.pixelSize: 10; font.family: "monospace"; font.bold: true }
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
                    width: 190; height: 140; radius: 8
                    color: theme.background
                    border.color: theme.accent; border.width: 1
                    Column {
                      anchors.fill: parent; anchors.margins: 12; spacing: 8
                      Text { text: (index + 1) + "  " + modelData.title; color: theme.accent; font.pixelSize: 13; font.bold: true; font.family: "monospace"; wrapMode: Text.WordWrap; width: parent.width }
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
