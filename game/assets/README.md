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

Final generation prompt:

> Create one exact 4 by 4 transparent sprite atlas for the Omacade PACKET//HOP
> arcade cabinet in a crisp chunky 32-bit pixel-art style. Include cyan courier
> packet idle, pulse, bound, and drop states; red service, orange package cart,
> purple compositor window, and firewall hazards; cyan pipe, teal container,
> blue SSH tunnel, and orange VPN platforms; empty and filled green sockets, a
> yellow TTL clock, and a cyan routing burst. Keep every subject isolated and
> centered in an equal cell with no grid, labels, text, UI, or watermark.

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
