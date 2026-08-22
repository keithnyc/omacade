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
    if (!Array.isArray(data[cabinetId])) data[cabinetId] = []
    var row = {}
    for (var field in entry) row[field] = entry[field]
    if (!row.at) row.at = new Date().toISOString()
    data[cabinetId].push(row)
    data[cabinetId].sort(function(a, b) { return Number(b.score || 0) - Number(a.score || 0) })
    data[cabinetId] = data[cabinetId].slice(0, 10)
    if (!data.stats || typeof data.stats !== "object") data.stats = {}
    var previous = data.stats[cabinetId] ? Number(data.stats[cabinetId].completed || 0) : completedRuns
    data.stats[cabinetId] = { completed: previous + 1 }
    if (cabinetId === "lander") data.successful_landings = previous + 1
    scoreFile.setText(JSON.stringify(data, null, 2) + "\n")
    applyScores(JSON.stringify(data))
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
