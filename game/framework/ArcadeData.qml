import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property string cabinetId: ""
  readonly property string configPath: Quickshell.env("HOME") + "/.local/state/omarchy/omacade.json"
  readonly property string scorePath: Quickshell.env("HOME") + "/.local/share/omacade/scores.json"

  property var configData: ({ difficulty: "cadet", sound: true, initials: "" })
  property var scoreData: ({})
  property string difficulty: "cadet"
  property string defaultInitials: ""
  property bool soundEnabled: true
  property var scoreRows: []
  property int bestScore: 0
  property int highestStage: 1
  property int completedRuns: 0
  property int totalRuns: 0
  property var lastRun: ({})
  property var achievements: ({})
  readonly property var achievementDefinitions: [
    { id: "first-boot", title: "FIRST BOOT", detail: "Complete any cabinet run." },
    { id: "soft-landing", title: "SOFT LANDING", detail: "Land with at least 20 fuel remaining." },
    { id: "root-access", title: "ROOT ACCESS", detail: "Reach Stage 4 in Rootbound." },
    { id: "route-locked", title: "ROUTE LOCKED", detail: "Bind five ports in one Packet Hop run." },
    { id: "triple-threat", title: "TRIPLE THREAT", detail: "Record a run on the first three cabinets." },
    { id: "core-shield", title: "CORE SHIELD", detail: "Clear a wave with all six services online." },
    { id: "full-stack", title: "FULL STACK", detail: "Record a run on all four cabinets." }
  ]

  function cleanInitials(value) {
    return String(value || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 3)
  }

  function applyConfig(raw) {
    var data = {}
    try { data = JSON.parse(String(raw || "{}")) } catch (error) { data = {} }
    var candidate = String(data.difficulty || "cadet")
    data.difficulty = ["cadet", "pilot", "ace"].indexOf(candidate) >= 0 ? candidate : "cadet"
    data.sound = data.sound !== false
    data.initials = cleanInitials(data.initials)
    configData = data
    difficulty = data.difficulty
    soundEnabled = data.sound
    defaultInitials = data.initials
  }

  function applyScores(raw) {
    var data = {}
    try { data = JSON.parse(String(raw || "{}")) } catch (error) { data = {} }
    scoreData = data
    var rows = cabinetId && Array.isArray(data[cabinetId]) ? data[cabinetId] : []
    scoreRows = rows.slice(0, 10)
    bestScore = rows.length ? Number(rows[0].score || 0) : 0
    highestStage = 1
    for (var i = 0; i < rows.length; i++)
      highestStage = Math.max(highestStage, Number(rows[i].stage || 1))
    var stats = data.stats && data.stats[cabinetId] ? data.stats[cabinetId] : null
    completedRuns = stats ? Number(stats.completed || 0)
      : cabinetId === "lander" ? Number(data.successful_landings || 0) : 0
    totalRuns = totalCompleted(data)
    lastRun = data.lastRuns && data.lastRuns[cabinetId] ? data.lastRuns[cabinetId] : ({})
    achievements = deriveAchievements(data)
  }

  function rowsFor(id) {
    return scoreData && Array.isArray(scoreData[id]) ? scoreData[id] : []
  }

  function bestFor(id) {
    var rows = rowsFor(id)
    return rows.length ? Number(rows[0].score || 0) : 0
  }

  function highestFor(id) {
    var rows = rowsFor(id)
    var highest = 1
    for (var i = 0; i < rows.length; i++) highest = Math.max(highest, Number(rows[i].stage || 1))
    return highest
  }

  function completedFor(id) {
    var stats = scoreData && scoreData.stats && scoreData.stats[id] ? scoreData.stats[id] : null
    if (stats) return Number(stats.completed || 0)
    return id === "lander" && scoreData ? Number(scoreData.successful_landings || 0) : 0
  }

  function lastRunFor(id) {
    return scoreData && scoreData.lastRuns && scoreData.lastRuns[id] ? scoreData.lastRuns[id] : ({})
  }

  function achievementUnlocked(id) {
    return !!(achievements && achievements[id])
  }

  function achievementCount() {
    var count = 0
    for (var id in achievements) if (achievements[id]) count += 1
    return count
  }

  function achievementById(id) {
    for (var i = 0; i < achievementDefinitions.length; i++)
      if (achievementDefinitions[i].id === id) return achievementDefinitions[i]
    return null
  }

  function totalCompleted(data) {
    var total = 0
    var stats = data && data.stats && typeof data.stats === "object" ? data.stats : ({})
    for (var id in stats) total += Number(stats[id].completed || 0)
    if (!stats.lander && data) total += Number(data.successful_landings || 0)
    return total
  }

  function anyRowMatches(data, id, predicate) {
    var rows = data && Array.isArray(data[id]) ? data[id] : []
    for (var i = 0; i < rows.length; i++) if (predicate(rows[i])) return true
    return false
  }

  function deriveAchievements(data) {
    var earned = {}
    var stored = data && data.achievements && typeof data.achievements === "object" ? data.achievements : ({})
    for (var key in stored) earned[key] = stored[key]
    var historical = "historical"
    if (totalCompleted(data) >= 1 && !earned["first-boot"]) earned["first-boot"] = historical
    if (anyRowMatches(data, "lander", function(row) { return Number(row.fuel || 0) >= 20 }) && !earned["soft-landing"])
      earned["soft-landing"] = historical
    if (anyRowMatches(data, "rootbound", function(row) { return Number(row.stage || 1) >= 4 }) && !earned["root-access"])
      earned["root-access"] = historical
    if (anyRowMatches(data, "packet-hop", function(row) { return Number(row.ports || 0) >= 5 }) && !earned["route-locked"])
      earned["route-locked"] = historical
    if (completedCount(data, "lander") > 0 && completedCount(data, "rootbound") > 0
        && completedCount(data, "packet-hop") > 0 && !earned["triple-threat"])
      earned["triple-threat"] = historical
    if (anyRowMatches(data, "core-command", function(row) { return Number(row.perfectWaves || 0) > 0 }) && !earned["core-shield"])
      earned["core-shield"] = historical
    if (completedCount(data, "lander") > 0 && completedCount(data, "rootbound") > 0
        && completedCount(data, "packet-hop") > 0 && completedCount(data, "core-command") > 0
        && !earned["full-stack"])
      earned["full-stack"] = historical
    return earned
  }

  function evaluateAchievements(data, row) {
    var earned = {}
    var existing = data.achievements && typeof data.achievements === "object" ? data.achievements : ({})
    for (var key in existing) earned[key] = existing[key]
    var unlocked = []
    var now = new Date().toISOString()
    function unlock(id, condition) {
      if (!condition || earned[id]) return
      earned[id] = now
      unlocked.push(id)
    }
    unlock("first-boot", totalCompleted(data) >= 1)
    unlock("soft-landing", cabinetId === "lander" && Number(row.fuel || 0) >= 20)
    unlock("root-access", cabinetId === "rootbound" && Number(row.stage || 1) >= 4)
    unlock("route-locked", cabinetId === "packet-hop" && Number(row.ports || 0) >= 5)
    unlock("triple-threat", completedCount(data, "lander") > 0
                             && completedCount(data, "rootbound") > 0
                             && completedCount(data, "packet-hop") > 0)
    unlock("core-shield", cabinetId === "core-command" && Number(row.perfectWaves || 0) > 0)
    unlock("full-stack", completedCount(data, "lander") > 0
                          && completedCount(data, "rootbound") > 0
                          && completedCount(data, "packet-hop") > 0
                          && completedCount(data, "core-command") > 0)
    data.achievements = earned
    return unlocked
  }

  function completedCount(data, id) {
    var stats = data.stats && data.stats[id] ? data.stats[id] : null
    if (stats) return Number(stats.completed || 0)
    return id === "lander" ? Number(data.successful_landings || 0) : 0
  }

  function patchConfig(values) {
    var data = {}
    var source = configData || {}
    for (var key in source) data[key] = source[key]
    for (var patchKey in values) data[patchKey] = values[patchKey]
    if (data.sound === undefined) data.sound = true
    data.initials = cleanInitials(data.initials)
    configFile.setText(JSON.stringify(data, null, 2) + "\n")
    applyConfig(JSON.stringify(data))
  }

  function qualifies(score) {
    return scoreRows.length < 10 || Number(score) > Number(scoreRows[9].score || 0)
  }

  function recordScore(entry) {
    if (!cabinetId) return
    var data = {}
    var source = scoreData || {}
    for (var key in source) data[key] = source[key]
    data.achievements = deriveAchievements(data)
    if (!Array.isArray(data[cabinetId])) data[cabinetId] = []
    var previousBest = data[cabinetId].length ? Number(data[cabinetId][0].score || 0) : 0
    var previousStage = 1
    for (var oldIndex = 0; oldIndex < data[cabinetId].length; oldIndex++)
      previousStage = Math.max(previousStage, Number(data[cabinetId][oldIndex].stage || 1))
    var row = {}
    for (var field in entry) row[field] = entry[field]
    if (!row.at) row.at = new Date().toISOString()
    row.newBest = Number(row.score || 0) > previousBest
    row.newStage = Number(row.stage || 1) > previousStage
    data[cabinetId].push(row)
    data[cabinetId].sort(function(a, b) { return Number(b.score || 0) - Number(a.score || 0) })
    data[cabinetId] = data[cabinetId].slice(0, 10)
    if (!data.stats || typeof data.stats !== "object") data.stats = {}
    var previous = data.stats[cabinetId] ? Number(data.stats[cabinetId].completed || 0) : completedRuns
    data.stats[cabinetId] = { completed: previous + 1, lastPlayed: row.at }
    if (cabinetId === "lander") data.successful_landings = previous + 1
    row.unlocks = evaluateAchievements(data, row)
    if (!data.lastRuns || typeof data.lastRuns !== "object") data.lastRuns = {}
    data.lastRuns[cabinetId] = row
    scoreFile.setText(JSON.stringify(data, null, 2) + "\n")
    applyScores(JSON.stringify(data))
  }

  function reloadScores() {
    scoreFile.reload()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("{}")
    onFileChanged: reload()
  }

  FileView {
    id: scoreFile
    path: root.scorePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.applyScores(text())
    onLoadFailed: root.applyScores("{}")
    onFileChanged: reload()
  }
}
