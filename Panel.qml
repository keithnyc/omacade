import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.keithnyc.omacade"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string guiPath: pluginDir + "/omacade-gui"
  readonly property string configPath: Quickshell.env("HOME") + "/.local/state/omarchy/omacade.json"
  readonly property string scorePath: Quickshell.env("HOME") + "/.local/share/omacade/scores.json"

  property string difficulty: "cadet"
  property string initials: ""
  property bool sound: true
  property int bestScore: 0
  property int landings: 0
  readonly property var difficultyOptions: [
    { value: "cadet", label: "Cadet" },
    { value: "pilot", label: "Pilot" },
    { value: "ace", label: "Ace" }
  ]

  function open() {
    configFile.reload()
    scoreFile.reload()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function play() {
    if (!root.bar) return
    root.persist()
    root.close()
    root.bar.run("omarchy-launch-or-focus 'Omacade' '" + root.guiPath + "'")
  }

  function removeFromBar() {
    root.close()
    if (barProc.running) barProc.running = false
    barProc.command = ["omarchy", "plugin", "disable", "io.github.keithnyc.omacade"]
    barProc.running = true
  }

  function applyConfig(raw) {
    var data = {}
    try { data = JSON.parse(raw || "{}") } catch (e) { data = {} }
    var nextDifficulty = String(data.difficulty || "cadet")
    root.difficulty = ["cadet", "pilot", "ace"].indexOf(nextDifficulty) >= 0
      ? nextDifficulty : "cadet"
    root.sound = data.sound !== false
    root.initials = String(data.initials || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 3)
  }

  function applyScores(raw) {
    var data = {}
    try { data = JSON.parse(raw || "{}") } catch (e) { data = {} }
    var rows = Array.isArray(data.lander) ? data.lander : []
    root.bestScore = rows.length > 0 ? Number(rows[0].score || 0) : 0
    root.landings = Number(data.successful_landings || 0)
  }

  function persist() {
    configFile.setText(JSON.stringify({
      difficulty: root.difficulty,
      sound: root.sound,
      initials: root.initials
    }, null, 2) + "\n")
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
    printErrors: false
    onLoaded: root.applyScores(text())
    onLoadFailed: root.applyScores("{}")
    onFileChanged: reload()
  }

  Process { id: barProc }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Keys.onReturnPressed: root.play()
      Keys.onEnterPressed: root.play()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(10)

          PanelHero {
            title: "Omacade"
            meta: "Insert no coins"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            iconComponent: Component {
              OmacadeMark {
                implicitWidth: Style.font.display
                implicitHeight: Style.font.display
                foreground: root.contentForeground
              }
            }
          }

          PanelSectionHeader {
            text: "Cabinet  01"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Button {
            width: parent.width
            text: "Enter Omacade"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.play()
          }

          Text {
            width: parent.width
            text: root.bestScore > 0
              ? "Best  " + root.bestScore + "   ·   Landings  " + root.landings
              : "No successful landings yet"
            color: root.contentForeground
            opacity: 0.7
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: "Flight school"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          ButtonGroup {
            width: parent.width
            options: root.difficultyOptions
            value: root.difficulty
            foreground: root.contentForeground
            background: root.bar ? root.bar.background : Color.background
            accent: Color.accent
            fontFamily: root.contentFontFamily
            onChanged: function(next) {
              root.difficulty = next
              root.persist()
            }
          }

          Button {
            width: parent.width
            text: "Sound effects  " + (root.sound ? "On" : "Off")
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: {
              root.sound = !root.sound
              root.persist()
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          Button {
            width: parent.width
            text: "Remove from bar"
            bordered: true
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
            onClicked: root.removeFromBar()
          }
        }
      }
    }
  }
}
