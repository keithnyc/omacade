import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  readonly property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  property color background: "#161616"
  property color surface: "#1e1e1e"
  property color surfaceRaised: "#282828"
  property color foreground: "#d4be98"
  property color muted: "#7c6f64"
  property color accent: "#7daea3"
  property color green: "#a9b665"
  property color yellow: "#d8a657"
  property color orange: "#e78a4e"
  property color red: "#ea6962"

  function colorFromTheme(raw, key, fallback) {
    var expression = new RegExp("^" + key + "\\s*=\\s*\"([^\"]+)\"", "m")
    var match = String(raw || "").match(expression)
    return match ? match[1] : fallback
  }

  function apply(raw) {
    background = colorFromTheme(raw, "darker_background", "#161616")
    surface = colorFromTheme(raw, "dark_background", "#1e1e1e")
    surfaceRaised = colorFromTheme(raw, "background", "#282828")
    foreground = colorFromTheme(raw, "foreground", "#d4be98")
    muted = colorFromTheme(raw, "muted", "#7c6f64")
    accent = colorFromTheme(raw, "accent", "#7daea3")
    green = colorFromTheme(raw, "green", "#a9b665")
    yellow = colorFromTheme(raw, "yellow", "#d8a657")
    orange = colorFromTheme(raw, "orange", "#e78a4e")
    red = colorFromTheme(raw, "red", "#ea6962")
  }

  FileView {
    path: root.themePath
    watchChanges: true
    printErrors: false
    onLoaded: root.apply(text())
    onFileChanged: reload()
  }
}
