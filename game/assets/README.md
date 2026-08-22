# Lander sprite

`lander.png` is an original 256×256 transparent pixel-art asset generated for
Omacade with OpenAI's built-in image generation tool, then trimmed and reduced
with nearest-neighbor sampling for use in the game.

Final generation prompt:

> Create one original upright lunar lander spacecraft sprite, viewed perfectly
> straight-on for a classic 2D lunar landing game. Use crisp handcrafted pixel
> art, a limited 16-bit arcade palette, a compact retro-futurist triangular
> silhouette, central teal cockpit, small engine bell, and two clearly separated
> landing legs. Center exactly one symmetrical spacecraft on a genuinely
> transparent square canvas. No ground, moon, stars, exhaust, shadow, border,
> text, logo, watermark, or existing-franchise design.

# Rootbound sprite atlas

`rootbound-sprites.png` is an original 1254×1254 transparent 4×4 pixel-art
atlas generated with OpenAI's built-in image generation tool. It contains four
player directions, zombie and rootkit capture states, purge bursts, a package
shard, and small effect sprites.

Final generation prompt:

> Create one exact 4 by 4 transparent sprite atlas for the Omacade Rootbound
> arcade cabinet. Use crisp modern pixel art with a chunky 32-bit arcade
> aesthetic and hard pixel edges. Row one contains the same cyan sysadmin drone
> facing up, right, down, and left. Row two contains an active coral-red zombie,
> cyan quarantined zombie, yellow compressed zombie, and deletion burst. Row
> three contains equivalent orange angular rootkit states. Row four contains a
> golden package shard, cyan purge spark, red warning glyph, and orange phase
> spark. Keep every sprite centered and isolated in an equal cell, with no grid,
> labels, letters, UI, watermark, or background.

# Packet Hop sprite atlas

`packet-hop-sprites.png` is an original 1254×1254 transparent 4×4 pixel-art
atlas generated with OpenAI's built-in image generation tool for Cabinet 03.
It contains courier packet states, process traffic, network carriers, root
sockets, TTL pickup, and routing effects.

`packet-hop-sprites-v2.png` preserves the courier
packet, firewall, fiber, encrypted-tunnel, VPN-relay, port, TTL, and routing
cells from the original atlas. Four industrial-looking cells were replaced
with a corrupted-packet stream, rack switch, deep-packet-inspection scanner,
and segmented Ethernet-frame carrier. The four replacements were generated
with the built-in image generation tool, their preview checkerboard was removed,
and only those cells were composited over the original transparent atlas.

`packet-hop-sprites-v3.png` removes residual
industrial silhouettes that survived beneath four v2 replacements. The new
corrupted-packet swarm contains only fragmented data frames; the buffering
switch is a clean rack appliance; the DPI hazard is a stationary scanner gate;
and the rideable Ethernet carrier is a flat chain of linked frames. A grayscale
alpha mask explicitly cleared those four old cells before the replacements were
composited, preventing hidden crawler, wheel, cargo, or container pixels.

`packet-hop-sprites-v4.png` replaces v3's visually
noisy red packet swarm with two large hostile red packet cubes that deliberately
echo the cyan courier's box silhouette. The lead packet is intact; the trailing
packet has a broken corner and a short glitch trail. Only row two column one was
changed, using the same explicit alpha-mask compositing workflow as v3.

`packet-hop-sprites-v5.png` is the production atlas. Because the game repeats
each atlas cell for every traffic entity, its red hazard cell now contains one
centered hostile packet cube rather than a pre-doubled pair. A damaged rear
corner and tiny bit trail keep the corruption inside that single silhouette.

Final generation prompt:

> Create one exact 4 by 4 transparent sprite atlas for the Omacade PACKET//HOP
> arcade cabinet in a crisp chunky 32-bit pixel-art style. Include cyan courier
> packet idle, pulse, bound, and drop states; red service, orange package cart,
> purple compositor window, and firewall hazards; cyan pipe, teal container,
> blue SSH tunnel, and orange VPN platforms; empty and filled green sockets, a
> yellow TTL clock, and a cyan routing burst. Keep every subject isolated and
> centered in an equal cell with no grid, labels, text, UI, or watermark.

Final v2 edit prompt:

> Edit the supplied atlas in place while preserving its exact 1254×1254 4×4
> geometry, transparent background, cell boundaries, scale, neon pixel-art
> style, and readability at 30–56 pixels. Preserve rows one and four exactly,
> plus the firewall, fiber conduit, encrypted tunnel, and VPN relay. Replace
> only row two columns one through three with a corrupted red packet convoy,
> an orange rack switch with Ethernet ports and activity lights, and a magenta
> deep-packet-inspection scanner. Replace row three column two with a segmented
> teal Ethernet-frame carrier. Use unmistakable networking cues; no vehicles,
> shipping containers, desktop windows, text, logos, or art crossing cells.

Final v3 edit prompt:

> Surgically rebuild only row two columns one through three and row three
> column two while preserving the 1254×1254 4×4 atlas geometry and all other
> cells. Create a red swarm of small corrupted header/payload packets with bit
> trails; a low orange rack switch with RJ45 ports, activity LEDs, and buffer
> lights; a stationary magenta DPI gate with packets crossing a central scan
> beam; and a flat teal chain of linked Ethernet frames with header/payload
> divisions and edge contacts. Keep true transparency and the existing neon
> pixel-art style. No chassis, wheels, tracks, antenna mast, forklift, cargo,
> shipping container, road vehicle, rocket, exhaust, desktop window, text,
> logos, watermark, checkerboard, or art crossing cells.

Final v4 edit prompt:

> Change only row two column one. Replace the fragmented swarm with exactly two
> dominant red packet cubes traveling horizontally. Echo the courier cube's
> chunky isometric box, bright payload face, and reinforced corners. Keep the
> lead packet intact; give the trailing packet one broken corner, a few detached
> square bits, and a very short glitch trail. It must read at 30–56 pixels tall.
> No small abstract swarm, chassis, wheels, tracks, vehicle, antenna, character,
> text, logo, checkerboard, or changes outside the target cell.

Final v5 edit prompt:

> Edit this exact 1254x1254 transparent 4x4 pixel-art sprite atlas. Preserve
> every pixel outside row 2, column 1. Replace the current pair with exactly one
> centered hostile red packet cube. Match the cyan courier cube's visual
> language: bright red payload face, dark reinforced metallic corners, crisp
> square silhouette, and a small corrupted rear corner integrated into the same
> cube. Do not draw a second cube, duplicate, companion, trailer, vehicle, or
> long trail. Keep generous transparent padding and preserve the atlas geometry.

## Sound effects

The WAV files under `sfx/` are original synthesized effects generated locally
for Omacade with FFmpeg's signal and noise sources. They contain no sampled
music, voices, or third-party recordings. The set includes engine, rotation,
launch, touchdown, stage-clear, crash, and comet cues.

Rootbound has its own `rootbound-*.wav` set covering digging, package recovery,
purging, damage, stage clear, bonus completion, mounting, and firewall denial.
These are also original FFmpeg-synthesized waveforms with no sampled material.

Packet Hop's original `packet-*.wav` set covers hopping, binding, drops, stage
transitions, and TTL pickups using the same no-samples synthesis approach.
