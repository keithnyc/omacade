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
  },
  {
    id: "packet-hop",
    number: "03",
    title: "Packet Hop",
    displayTitle: "P A C K E T // H O P",
    shortTitle: "PACKET//HOP",
    windowTitle: "Omacade Packet Hop",
    tagline: "Cross the stack. Don't drop the packet.",
    description: "Dodge hostile processes, ride encrypted carriers, and bind every root port.",
    entry: "packet-hop.qml",
    scoreKey: "packet-hop",
    accent: "accent",
    status: "ready",
    controls: "← ↑ ↓ → HOP / ROUTE"
  },
  {
    id: "core-command",
    number: "04",
    title: "Core Command",
    displayTitle: "C O R E // C O M M A N D",
    shortTitle: "CORE//COMMAND",
    windowTitle: "Omacade Core Command",
    tagline: "Protect the stack. Detonate the threat.",
    description: "Defend critical services with expanding quarantine fields and cascading chain reactions.",
    entry: "core-command.qml",
    scoreKey: "core-command",
    accent: "red",
    status: "ready",
    controls: "MOUSE / ARROWS AIM   ·   CLICK / SPACE FIRE"
  },
  {
    id: "daemon-swarm",
    number: "05",
    title: "Daemon Swarm",
    displayTitle: "D A E M O N  S W A R M",
    shortTitle: "DAEMON SWARM",
    windowTitle: "Omacade Daemon Swarm",
    tagline: "One daemon. An endless swarm. Hold the line.",
    description: "Auto-fire against a growing swarm of rogue processes, level up, and survive as long as you can.",
    entry: "daemon-swarm.qml",
    scoreKey: "daemon-swarm",
    accent: "orange",
    status: "ready",
    controls: "← ↑ ↓ → / WASD MOVE   ·   AUTO-FIRE"
  }
]

function byId(id) {
  for (var i = 0; i < cabinets.length; i++)
    if (cabinets[i].id === id) return cabinets[i]
  return null
}
