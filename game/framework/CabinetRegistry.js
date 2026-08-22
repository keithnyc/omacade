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
  },
  {
    id: "rootbound",
    number: "02",
    title: "Rootbound",
    displayTitle: "R O O T B O U N D",
    shortTitle: "ROOTBOUND",
    windowTitle: "Omacade Rootbound",
    tagline: "Dig deep. Purge rogue daemons.",
    description: "Carve filesystem tunnels, recover package shards, and keep root clean.",
    entry: "rootbound.qml",
    scoreKey: "rootbound",
    accent: "yellow",
    status: "ready",
    controls: "← ↑ ↓ → DIG   ·   SPACE SUDO PURGE"
  }
]

function byId(id) {
  for (var i = 0; i < cabinets.length; i++)
    if (cabinets[i].id === id) return cabinets[i]
  return null
}
