.pragma library

var cabinets = [
  {
    id: "lander",
    number: "01",
    title: "Lander",
    displayTitle: "L A N D E R",
    shortTitle: "LANDER",
    windowTitle: "Omacade Lander",
    tagline: "Settle both feet. Master the moon.",
    description: "Precision lunar flight across increasingly hostile terrain.",
    entry: "shell.qml",
    scoreKey: "lander",
    accent: "green",
    status: "ready",
    controls: "← → ROTATE   ·   ↑ / SPACE THRUST"
  }
]

function byId(id) {
  for (var i = 0; i < cabinets.length; i++)
    if (cabinets[i].id === id) return cabinets[i]
  return null
}
