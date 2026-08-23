#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import runpy
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GAME_PATH = ROOT / "omacade"


class OmacadeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.module = runpy.run_path(str(GAME_PATH), run_name="omacade_test")

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory(prefix="omacade-test-")
        base = Path(self.temp_dir.name)
        globals_ = self.module["Lander"].__init__.__globals__
        globals_["CONFIG_PATH"] = base / "state" / "omacade.json"
        globals_["SCORE_PATH"] = base / "share" / "scores.json"
        globals_["THEME_PATH"] = base / "theme" / "colors.toml"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_generated_terrain_has_two_valid_pads(self) -> None:
        terrain = self.module["Terrain"](80, 24, 42)
        self.assertEqual(len(terrain.pads), 2)
        for pad in terrain.pads:
            self.assertGreaterEqual(pad.start, 0)
            self.assertLess(pad.end, terrain.width)
            self.assertTrue(all(terrain.heights[x] == pad.height for x in range(pad.start, pad.end + 1)))

    def test_gentle_upright_touchdown_scores(self) -> None:
        lander = self.module["Lander"](80, 24, "cadet")
        pad = lander.terrain.pads[0]
        lander.x = (pad.start + pad.end) / 2
        lander.y = pad.height - 1.0
        lander.vx = 0.0
        lander.vy = 0.1
        lander.angle = 0.0
        lander.update(0.01)
        self.assertEqual(lander.state, "landed")
        self.assertGreater(lander.score, 0)

    def test_fast_touchdown_crashes(self) -> None:
        lander = self.module["Lander"](80, 24, "ace")
        pad = lander.terrain.pads[0]
        lander.x = (pad.start + pad.end) / 2
        lander.y = pad.height - 1.0
        lander.vx = 0.0
        lander.vy = 2.0
        lander.angle = 0.0
        lander.update(0.01)
        self.assertEqual(lander.state, "crashed")
        self.assertEqual(lander.message, "DESCENT TOO FAST")

    def test_impulse_and_rotation_are_frame_rate_independent(self) -> None:
        Lander = self.module["Lander"]
        fast = Lander(80, 24, "cadet")
        slow = Lander(80, 24, "cadet")
        for lander in (fast, slow):
            lander.x = 40.0
            lander.y = 3.0
            lander.vx = 0.0
            lander.vy = 0.0
            lander.angle = 0.0
            lander.fire()
            lander.rotate(1.0)

        for _ in range(120):
            fast.update(1.0 / 120.0)
        for _ in range(30):
            slow.update(1.0 / 30.0)

        self.assertAlmostEqual(fast.x, slow.x, places=5)
        self.assertAlmostEqual(fast.y, slow.y, places=5)
        self.assertAlmostEqual(fast.vx, slow.vx, places=5)
        self.assertAlmostEqual(fast.vy, slow.vy, places=5)
        self.assertAlmostEqual(fast.angle, slow.angle, places=5)
        self.assertAlmostEqual(fast.fuel, slow.fuel, places=5)

    def test_a_tap_applies_one_exact_engine_impulse(self) -> None:
        lander = self.module["Lander"](80, 24, "cadet")
        lander.angle = 0.0
        initial_fuel = lander.fuel
        initial_vy = lander.vy
        lander.fire()
        self.assertTrue(lander.thrusting)
        self.assertAlmostEqual(lander.vy, initial_vy - lander.rules["impulse"], places=5)
        self.assertAlmostEqual(initial_fuel - lander.fuel, lander.rules["fuel_cost"], places=5)
        lander.update(0.1)
        lander.update(0.02)
        self.assertFalse(lander.thrusting)
        velocity_after_flash = lander.vy
        lander.update(0.05)
        self.assertAlmostEqual(
            lander.vy - velocity_after_flash,
            lander.rules["gravity"] * 0.05,
            places=5,
        )

    def test_input_cooldown_prevents_repeat_bursts(self) -> None:
        lander = self.module["Lander"](80, 24, "cadet")
        lander.fire()
        velocity_after_first = lander.vy
        fuel_after_first = lander.fuel
        lander.fire()
        self.assertEqual(lander.vy, velocity_after_first)
        self.assertEqual(lander.fuel, fuel_after_first)
        lander.update(0.08)
        lander.fire()
        self.assertLess(lander.vy, velocity_after_first + lander.rules["gravity"] * 0.08)
        self.assertLess(lander.fuel, fuel_after_first)

    def test_opposite_rotation_is_never_discarded(self) -> None:
        lander = self.module["Lander"](80, 24, "cadet")
        step = self.module["ROTATION_STEP"]
        lander.angle = 0.0
        lander.rotate(-step)
        self.assertEqual(lander.angle, -step)
        lander.rotate(step)
        self.assertEqual(lander.angle, 0.0)

    def test_redirected_thrust_can_immediately_correct_course(self) -> None:
        lander = self.module["Lander"](80, 24, "cadet")
        lander.vx = 0.0
        lander.vy = 0.0
        lander.angle = -30.0
        lander.fire()
        leftward_velocity = lander.vx
        self.assertLess(leftward_velocity, 0.0)

        # No time advance: changing attitude must bypass the repeat limiter.
        lander.angle = 30.0
        lander.fire()
        self.assertAlmostEqual(lander.vx, 0.0, places=5)
        self.assertEqual(lander.fuel, lander.rules["fuel"] - 2 * lander.rules["fuel_cost"])

    def test_real_input_sequence_reverses_course_in_one_frame(self) -> None:
        App = self.module["App"]
        app = App(self.module["Settings"](), self.module["Scores"](), direct=True)
        app.game.angle = 0.0
        app.game.vx = 0.0
        app.game.vy = 0.0
        app.handle("left")
        app.handle("up")
        self.assertLess(app.game.vx, 0.0)
        app.handle("right")
        app.handle("right")
        app.handle("up")
        self.assertGreater(app.game.angle, 0.0)
        self.assertAlmostEqual(app.game.vx, 0.0, places=5)

    def test_sprite_sheet_covers_nine_attitudes(self) -> None:
        sprites = self.module["LANDER_SPRITES"]
        self.assertEqual(set(sprites), set(range(-4, 5)))
        for frame in sprites.values():
            self.assertEqual(len(frame), 3)
            self.assertTrue(all(len(row) == 5 for row in frame))

    def test_graphical_cabinet_uses_transparent_png_sprite(self) -> None:
        sprite = ROOT / "game" / "assets" / "lander.png"
        qml = (ROOT / "game" / "shell.qml").read_text(encoding="utf-8")
        self.assertTrue(sprite.is_file())
        self.assertEqual(sprite.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
        self.assertIn('Qt.resolvedUrl("assets/lander.png")', qml)
        self.assertIn("Keys.onReleased", qml)
        self.assertIn("viewportTooSmall", qml)
        self.assertIn("resizeWorld", qml)
        self.assertIn('chooseDifficulty("cadet")', qml)
        self.assertIn('chooseDifficulty("pilot")', qml)
        self.assertIn('chooseDifficulty("ace")', qml)
        self.assertIn("enteringInitials", qml)
        self.assertIn("OMACADE // TOP TEN", qml)
        self.assertIn("saveDefaultInitials", qml)
        self.assertIn("footOffsetX: 27", qml)
        self.assertIn("function landingGear()", qml)
        self.assertIn("function spawnShootingStar()", qml)
        self.assertIn("function updateSky(dt)", qml)
        self.assertIn("id: skyEffectsCanvas", qml)
        self.assertIn("property int stage: 1", qml)
        self.assertIn("function advanceStage()", qml)
        self.assertIn("widePadWidth", qml)
        self.assertIn('"STAGE " + stage + " CLEAR', qml)
        self.assertIn("function sculptPadHazards", qml)
        self.assertIn("twinkleStrength", qml)
        self.assertIn("import QtMultimedia", qml)
        self.assertIn("PRESS ENTER TO LAUNCH", qml)
        self.assertIn("function spawnLandingDust()", qml)
        self.assertIn("function spawnCrashParticles()", qml)
        self.assertIn("id: particleCanvas", qml)

        sounds = {
            "engine.wav", "rotate.wav", "touchdown.wav", "crash.wav",
            "stage-clear.wav", "start.wav", "comet.wav"
        }
        for name in sounds:
            audio = ROOT / "game" / "assets" / "sfx" / name
            self.assertTrue(audio.is_file(), name)
            self.assertEqual(audio.read_bytes()[:4], b"RIFF", name)

    def test_settings_and_score_round_trip(self) -> None:
        Settings = self.module["Settings"]
        Scores = self.module["Scores"]
        settings = Settings()
        settings.difficulty = "pilot"
        settings.sound = False
        settings.initials = "KNY"
        settings.save()
        restored = Settings()
        self.assertEqual(restored.difficulty, "pilot")
        self.assertFalse(restored.sound)
        self.assertEqual(restored.initials, "KNY")

        scores = Scores()
        self.assertEqual(scores.add(1200, "pilot", 42.0, 18.5, restored.initials), 1)
        self.assertEqual(scores.add(1800, "ace", 30.0, 16.0), 1)
        self.assertEqual(Scores().best, 1800)
        self.assertEqual(Scores().landings, 2)
        self.assertEqual(Scores().data["lander"][1]["initials"], "KNY")

    def test_initials_are_sanitized_and_low_scores_still_count_as_landings(self) -> None:
        Settings = self.module["Settings"]
        Scores = self.module["Scores"]
        config_path = Settings.__init__.__globals__["CONFIG_PATH"]
        config_path.parent.mkdir(parents=True, exist_ok=True)
        config_path.write_text('{"initials": "k!2 z"}\n', encoding="utf-8")
        self.assertEqual(Settings().initials, "K2Z")

        scores = Scores()
        for value in range(100, 1100, 100):
            scores.add(value, "cadet", 50.0, 20.0, "a!*b9")
        self.assertEqual(scores.add(1, "cadet", 1.0, 99.0, "low"), 0)
        restored = Scores()
        self.assertEqual(restored.landings, 11)
        self.assertEqual(len(restored.data["lander"]), 10)
        self.assertTrue(all(row["initials"] == "AB9" for row in restored.data["lander"]))

    def test_read_regular_file_refuses_symlinks_special_files_and_oversized_data(self) -> None:
        read_regular_file = self.module["read_regular_file"]
        base = Path(self.temp_dir.name)

        normal = base / "normal.json"
        normal.write_text('{"ok": true}\n', encoding="utf-8")
        self.assertEqual(read_regular_file(normal), '{"ok": true}\n')

        target = base / "real-target.json"
        target.write_text('{"real": true}\n', encoding="utf-8")
        symlink = base / "via-symlink.json"
        symlink.symlink_to(target)
        self.assertIsNone(read_regular_file(symlink))

        fifo = base / "a-fifo"
        os.mkfifo(fifo)
        self.assertIsNone(read_regular_file(fifo))

        oversized = base / "oversized.json"
        oversized.write_text("x" * 32, encoding="utf-8")
        self.assertIsNone(read_regular_file(oversized, max_bytes=8))
        self.assertEqual(read_regular_file(oversized, max_bytes=64), "x" * 32)

        self.assertIsNone(read_regular_file(base / "does-not-exist.json"))

    def test_write_json_replaces_destination_symlink_without_writing_through_it(self) -> None:
        write_json = self.module["write_json"]
        read_regular_file = self.module["read_regular_file"]
        base = Path(self.temp_dir.name)

        other_owner_file = base / "someone-elses-file.json"
        other_owner_file.write_text('{"untouched": true}\n', encoding="utf-8")
        destination = base / "scores.json"
        destination.symlink_to(other_owner_file)

        write_json(destination, {"hello": "world"})

        self.assertFalse(destination.is_symlink())
        self.assertEqual(json.loads(read_regular_file(destination)), {"hello": "world"})
        self.assertEqual(other_owner_file.read_text(encoding="utf-8"), '{"untouched": true}\n')

        leftovers = [p for p in base.iterdir() if p.name.startswith("scores.json.") and p.name.endswith(".tmp")]
        self.assertEqual(leftovers, [])

    def test_theme_and_settings_fall_back_safely_when_state_paths_are_symlinks(self) -> None:
        Theme = self.module["Theme"]
        Settings = self.module["Settings"]
        globals_ = self.module["Lander"].__init__.__globals__
        base = Path(self.temp_dir.name)

        theme_target = base / "not-the-real-theme.toml"
        theme_target.write_text('accent = "#ff00ff"\n', encoding="utf-8")
        globals_["THEME_PATH"].parent.mkdir(parents=True, exist_ok=True)
        globals_["THEME_PATH"].symlink_to(theme_target)

        theme = Theme()
        self.assertEqual(theme.raw["accent"], self.module["FALLBACK"]["accent"])

        config_target = base / "not-the-real-config.json"
        config_target.write_text('{"difficulty": "ace"}\n', encoding="utf-8")
        globals_["CONFIG_PATH"].parent.mkdir(parents=True, exist_ok=True)
        globals_["CONFIG_PATH"].symlink_to(config_target)

        settings = Settings()
        self.assertEqual(settings.difficulty, "cadet")

    def test_cli_reports_matching_version(self) -> None:
        result = subprocess.run(
            [str(GAME_PATH), "--version"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.stdout.strip(), "Omacade 0.1.1")

    def test_graphical_framework_registers_and_launches_lander(self) -> None:
        registry = (ROOT / "game" / "framework" / "CabinetRegistry.js").read_text(encoding="utf-8")
        runtime = (ROOT / "game" / "framework" / "ArcadeData.qml").read_text(encoding="utf-8")
        theme = (ROOT / "game" / "framework" / "ArcadeTheme.qml").read_text(encoding="utf-8")
        lobby = (ROOT / "game" / "arcade.qml").read_text(encoding="utf-8")
        launcher = (ROOT / "omacade-gui").read_text(encoding="utf-8")
        desktop = (ROOT / "Omacade.desktop").read_text(encoding="utf-8")
        panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
        lander = (ROOT / "game" / "shell.qml").read_text(encoding="utf-8")

        self.assertIn('id: "lander"', registry)
        self.assertIn('entry: "shell.qml"', registry)
        self.assertIn('id: "rootbound"', registry)
        self.assertIn('entry: "rootbound.qml"', registry)
        self.assertIn('id: "packet-hop"', registry)
        self.assertIn('entry: "packet-hop.qml"', registry)
        self.assertIn('id: "core-command"', registry)
        self.assertIn('entry: "core-command.qml"', registry)
        self.assertIn("function recordScore(entry)", runtime)
        self.assertIn("property var lastRun", runtime)
        self.assertIn("achievementDefinitions", runtime)
        self.assertIn("function deriveAchievements(data)", runtime)
        self.assertIn("function achievementUnlocked(id)", runtime)
        self.assertIn("row.newBest =", runtime)
        self.assertIn("data.lastRuns[cabinetId] = row", runtime)
        for achievement in ("first-boot", "soft-landing", "root-access", "route-locked", "triple-threat", "core-shield", "full-stack", "circuit-champion"):
            self.assertIn(f'id: "{achievement}"', runtime)
        self.assertIn("property color accent", theme)
        self.assertIn("CabinetRegistry.cabinets", lobby)
        self.assertIn('title: "OMACADE // LOBBY"', lobby)
        self.assertIn("id: arcadeFloor", lobby)
        self.assertIn('text: "PLAYER PROFILE // "', lobby)
        self.assertIn("arcadeData.achievementDefinitions", lobby)
        self.assertIn("visible: arcade.showRecap", lobby)
        self.assertIn('text: "SESSION COMPLETE"', lobby)
        self.assertIn("function runDetail(run, cabinetId)", lobby)
        self.assertIn("function circuitPoints(run, cabinetId)", lobby)
        self.assertIn("function beginCircuit()", lobby)
        self.assertIn("function finishCircuit()", lobby)
        self.assertIn('OMACADE_CIRCUIT=1', lobby)
        self.assertIn('"O M A C A D E  //  C I R C U I T"', lobby)
        self.assertIn('cabinetId = "circuit"', lobby)
        self.assertIn('cabinetId === "lander" && raw <= 0', lobby)
        self.assertIn('Number(data.successful_landings || 0) + 1', runtime)
        self.assertIn("arcade.beginPilotEdit()", lobby)
        self.assertIn('arcade) target="$root/game/arcade.qml"', launcher)
        self.assertIn('lander) target="$root/game/shell.qml"', launcher)
        self.assertIn('rootbound) target="$root/game/rootbound.qml"', launcher)
        self.assertIn('packet-hop|packethop) target="$root/game/packet-hop.qml"', launcher)
        self.assertIn('core-command|corecommand) target="$root/game/core-command.qml"', launcher)
        self.assertIn('Exec=omarchy-launch-or-focus "OMACADE // LOBBY" omacade-gui', desktop)
        self.assertIn('lobbyWindowTitle: "OMACADE // LOBBY"', panel)
        self.assertIn("Util.shellQuote(root.lobbyWindowTitle)", panel)
        self.assertIn("Util.shellQuote(root.guiPath)", panel)
        self.assertIn('CabinetRegistry.byId("lander")', lander)
        self.assertIn("ArcadeData { id: arcadeData", lander)
        self.assertIn('Quickshell.env("OMACADE_CIRCUIT") === "1"', lander)
        self.assertIn("circuitRunRecorded", lander)

        rootbound = (ROOT / "game" / "rootbound.qml").read_text(encoding="utf-8")
        self.assertIn('Quickshell.env("OMACADE_CIRCUIT") === "1"', rootbound)
        self.assertIn('CabinetRegistry.byId("rootbound")', rootbound)
        self.assertIn("function movePlayer(dx, dy)", rootbound)
        self.assertIn("function moveEnemies()", rootbound)
        self.assertIn("function purge()", rootbound)
        self.assertIn("function daemonState(", rootbound)
        self.assertIn('type === "rootkit"', rootbound)
        self.assertIn("nextCapture >= 3", rootbound)
        self.assertIn("function tickCombatEffects(dt)", rootbound)
        self.assertIn("function addPurgeBurst(", rootbound)
        self.assertIn("function setupHazards(generated)", rootbound)
        self.assertIn("function tickUnstableTerrain(dt)", rootbound)
        self.assertIn("function beginDeath(reason)", rootbound)
        self.assertIn("function beginStageClear()", rootbound)
        self.assertIn('type: zoneIndex === 1 ? "log" : "firewall"', rootbound)
        self.assertIn('readonly property string objectiveText:', rootbound)
        self.assertIn('cabinetId: shell.cabinet.scoreKey', rootbound)
        self.assertIn("property int moveInterval: 145", rootbound)
        self.assertIn("moveInterval = digging ? digIntervals[zoneIndex] : 145", rootbound)
        self.assertIn("function requestMove(dx, dy)", rootbound)
        self.assertIn("function flushPendingMove()", rootbound)
        self.assertIn("function setMoveIntent(dx, dy)", rootbound)
        self.assertIn("interval: 16", rootbound)
        self.assertIn("pulseCooldown = 0.36", rootbound)
        self.assertIn("if (game.purgeHeld && game.pulseCooldown <= 0) game.purge()", rootbound)
        self.assertIn("property real playerVisualX", rootbound)
        self.assertGreaterEqual(rootbound.count("if (event.isAutoRepeat)"), 2)
        self.assertIn('["/HOME", "/VAR", "/TMP", "/ROOT"]', rootbound)
        self.assertIn('Qt.resolvedUrl("assets/rootbound-sprites.png")', rootbound)
        self.assertIn("var playerFrame = playerHorizontal ? 1 : 0", rootbound)
        self.assertIn("context.scale(flipX ? -1 : 1, flipY ? -1 : 1)", rootbound)

        sprite = (ROOT / "game" / "assets" / "rootbound-sprites.png").read_bytes()
        self.assertEqual(sprite[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(int.from_bytes(sprite[16:20], "big"), 1254)
        self.assertEqual(int.from_bytes(sprite[20:24], "big"), 1254)

        for effect in ("dig", "package", "purge", "hit", "clear", "bonus", "mount", "hazard"):
            wav = (ROOT / "game" / "assets" / "sfx" / f"rootbound-{effect}.wav").read_bytes()
            self.assertEqual(wav[:4], b"RIFF")
            self.assertEqual(wav[8:12], b"WAVE")

        packet_hop = (ROOT / "game" / "packet-hop.qml").read_text(encoding="utf-8")
        self.assertIn('Quickshell.env("OMACADE_CIRCUIT") === "1"', packet_hop)
        self.assertIn('CabinetRegistry.byId("packet-hop")', packet_hop)
        self.assertIn("function tickWorld(dt)", packet_hop)
        self.assertIn("function bindPort(x)", packet_hop)
        self.assertIn("function dropPacket(reason)", packet_hop)
        self.assertIn('makeLane(2, "network", networkKinds[0]', packet_hop)
        self.assertIn('makeLane(6, "process", processKinds[0]', packet_hop)
        self.assertIn("var pace = 0.72 + Math.min(stage - 1, 5) * 0.13", packet_hop)
        self.assertIn('stage === 3 ? ["vpn", "ssh", "vpn"]', packet_hop)
        self.assertIn('stage === 2 ? ["service", "firewall"', packet_hop)
        self.assertIn("function queueNetworkEvent()", packet_hop)
        self.assertIn("function activateNetworkEvent()", packet_hop)
        self.assertIn("function finishNetworkEvent(message)", packet_hop)
        self.assertIn("function tickNetworkEvent(dt)", packet_hop)
        self.assertIn("function reverseEventLane()", packet_hop)
        self.assertIn("function laneIsActive(source)", packet_hop)
        self.assertIn("function laneSpeedFactor(source)", packet_hop)
        self.assertIn("function dpiBeamX(source, item)", packet_hop)
        self.assertIn("function awardNearMiss(source)", packet_hop)
        self.assertIn('source.kind === "package"', packet_hop)
        self.assertIn('source.kind === "firewall"', packet_hop)
        self.assertIn('source.kind === "ssh" && stage >= 3', packet_hop)
        self.assertIn('statusMessage = "CLEAN HOP // NEAR MISS +" + bonus', packet_hop)
        self.assertIn('["cache", "packetloss", "burst"]', packet_hop)
        self.assertIn('["routeflap", "cache", "packetloss", "burst"]', packet_hop)
        self.assertIn('networkEvent === "packetloss" && eventPhase === "active"', packet_hop)
        self.assertIn('networkEvent === "burst" && eventPhase === "active"', packet_hop)
        self.assertIn('source.type === "process" && source.kind !== "package"', packet_hop)
        self.assertIn('statusMessage = "CACHE SERVED // +6 TTL // +450"', packet_hop)
        self.assertIn("onTriggered: game.queueNetworkEvent()", packet_hop)
        self.assertIn('text: "●  " + game.eventName', packet_hop)
        self.assertIn('"SYN  →  ACK // ROUTE ADDED"', packet_hop)
        self.assertNotIn("drawSprite", packet_hop)
        self.assertNotIn("spriteAtlas", packet_hop)
        self.assertIn("function drawCarrier(context, kind, laneType, cx, cy, w, h, direction, opacity)", packet_hop)
        self.assertIn("function drawPort(context, cx, cy, h, bound)", packet_hop)
        self.assertIn("function drawTtlIcon(context, cx, cy, r)", packet_hop)
        self.assertIn("function drawCacheIcon(context, cx, cy, r)", packet_hop)
        self.assertIn("function drawCourier(context, cx, cy, size, courierMode, opacity)", packet_hop)
        self.assertIn("readonly property real spriteScale: 0.76", packet_hop)
        self.assertIn("item.width * spriteScale / 2", packet_hop)
        self.assertIn("readonly property real playfieldAspect: columns / rows", packet_hop)
        self.assertIn("(playfieldSlot.height - 24) * game.playfieldAspect", packet_hop)
        self.assertIn("height: width / game.playfieldAspect", packet_hop)
        self.assertIn('text: "// INGRESS"', packet_hop)
        self.assertIn('text: "EGRESS //"', packet_hop)
        self.assertIn('text: "ROOT PORTS"', packet_hop)
        self.assertIn("readonly property bool compactTelemetry:", packet_hop)
        self.assertIn("id: compactIngressRail", packet_hop)
        self.assertIn("id: compactEgressRail", packet_hop)
        self.assertIn("var flowPhase = game.animationTime * flow.speed * game.laneSpeedFactor(flow) * flow.direction * 1.45", packet_hop)
        self.assertIn("anchors.topMargin: game.cellHeight + 8", packet_hop)

        for sprite_name in ("packet-hop-sprites.png", "packet-hop-sprites-v2.png", "packet-hop-sprites-v3.png",
                            "packet-hop-sprites-v4.png", "packet-hop-sprites-v5.png"):
            self.assertFalse((ROOT / "game" / "assets" / sprite_name).exists(), sprite_name)
        for effect in ("hop", "bind", "drop", "stage", "ttl"):
            wav = (ROOT / "game" / "assets" / "sfx" / f"packet-{effect}.wav").read_bytes()
            self.assertEqual(wav[:4], b"RIFF")
            self.assertEqual(wav[8:12], b"WAVE")

        core_command = (ROOT / "game" / "core-command.qml").read_text(encoding="utf-8")
        self.assertIn('Quickshell.env("OMACADE_CIRCUIT") === "1"', core_command)
        self.assertIn('CabinetRegistry.byId("core-command")', core_command)
        self.assertIn("function spawnThreat(", core_command)
        self.assertIn("function fireAt(x, y)", core_command)
        self.assertIn("function explosionRadius(blast)", core_command)
        self.assertIn("function updateThreats(dt)", core_command)
        self.assertIn("function splitFork(threat, children)", core_command)
        self.assertIn("function nudgeReticle(dx, dy)", core_command)
        self.assertIn("function inFlightForBattery(index)", core_command)
        self.assertIn("function serviceOnline(name)", core_command)
        self.assertIn('updatedCooldowns[batteryIndex] = serviceOnline("NET") ? 0.24 : 0.34', core_command)
        self.assertIn('launchBusCooldown = serviceOnline("NET") ? 0.14 : 0.20', core_command)
        self.assertIn("inFlightForBattery(batteryIndex) >= 2", core_command)
        self.assertIn("var ammoBonus = totalAmmo * 55", core_command)
        self.assertIn('serviceOnline("PKG") ? 1 : 0', core_command)
        self.assertIn('serviceOnline("SHELL") ? 285 : 220', core_command)
        self.assertIn('serviceOnline("SYNC") ? 3 : 4', core_command)
        self.assertIn('"BOOT ROLLBACK // "', core_command)
        self.assertIn('type === "zeroDay"', core_command)
        self.assertIn('hp: type === "zeroDay" ? 3 : 1', core_command)
        self.assertIn('"ZERO-DAY SIEGE // THREE LAYERS DETECTED"', core_command)
        self.assertIn("cursorShape: enabled ? Qt.BlankCursor : Qt.ArrowCursor", core_command)
        self.assertIn("var forkY = threat.y + step", core_command)
        self.assertIn('type === "rootkit"', core_command)
        self.assertIn('type === "stealth"', core_command)
        self.assertIn('type === "fork"', core_command)
        self.assertIn('difficulty: "core"', core_command)
        self.assertIn("property int perfectWaves", core_command)
        self.assertIn("if (onlineServices === services.length) perfectWaves += 1", core_command)
        self.assertIn("maxChain: maxChain, perfectWaves: perfectWaves", core_command)
        self.assertIn('text: "CORE::COMMAND // TOP TEN"', core_command)
        self.assertIn('statusMessage = "THREAT SALVO // CHAIN WINDOW OPEN"', core_command)
        self.assertIn("readonly property real worldAspect: worldWidth / worldHeight", core_command)
        self.assertIn("width: Math.min(parent.width, parent.height * game.worldAspect)", core_command)
        self.assertIn("height: width / game.worldAspect", core_command)
        self.assertIn("renderStrategy: Canvas.Threaded", core_command)
        self.assertIn("var dt = Math.max(0.001, Math.min(0.05", core_command)
        self.assertIn("context.lineWidth = 9", core_command)
        for effect in ("launch", "blast", "impact", "wave"):
            wav = (ROOT / "game" / "assets" / "sfx" / f"core-{effect}.wav").read_bytes()
            self.assertEqual(wav[:4], b"RIFF")
            self.assertEqual(wav[8:12], b"WAVE")

    def test_graphical_framework_registers_and_launches_daemon_swarm(self) -> None:
        registry = (ROOT / "game" / "framework" / "CabinetRegistry.js").read_text(encoding="utf-8")
        runtime = (ROOT / "game" / "framework" / "ArcadeData.qml").read_text(encoding="utf-8")
        lobby = (ROOT / "game" / "arcade.qml").read_text(encoding="utf-8")
        launcher = (ROOT / "omacade-gui").read_text(encoding="utf-8")
        swarm = (ROOT / "game" / "daemon-swarm.qml").read_text(encoding="utf-8")

        self.assertIn('id: "daemon-swarm"', registry)
        self.assertIn('entry: "daemon-swarm.qml"', registry)
        self.assertIn('id: "overclocked"', runtime)
        self.assertIn('cabinetId === "daemon-swarm" && Number(row.stage || 1) >= 10', runtime)
        self.assertIn('cabinetId === "daemon-swarm"', lobby)
        self.assertIn('daemon-swarm|daemonswarm) target="$root/game/daemon-swarm.qml"', launcher)

        self.assertIn('Quickshell.env("OMACADE_CIRCUIT") === "1"', swarm)
        self.assertIn('CabinetRegistry.byId("daemon-swarm")', swarm)
        self.assertIn('ArcadeData { id: arcadeData', swarm)
        self.assertIn("running: !game.tooSmall", swarm)
        self.assertIn("function updateEnemies(dt)", swarm)
        self.assertIn("function nearestEnemy()", swarm)
        self.assertIn("function levelUp()", swarm)
        self.assertIn("function applyUpgrade(id)", swarm)
        self.assertIn("function rollUpgrades()", swarm)
        self.assertIn('type === "rootkit"', swarm)
        self.assertIn('if (e.type === "fork")', swarm)
        self.assertIn("readonly property int maxEnemies: Math.min(240, 90 + wave * 7)", swarm)
        self.assertIn('difficulty: "swarm"', swarm)
        self.assertIn("stage: wave,", swarm)
        self.assertIn("time: Math.round(elapsed), kills: kills, elites: elites, level: level", swarm)
        self.assertIn("function completeWave()", swarm)
        self.assertIn("function rollWaveReward()", swarm)
        self.assertIn("readonly property int waveKillTarget: 8 + wave * 5", swarm)
        self.assertIn("readonly property real enemyHpMul: 1 + wave * 0.1", swarm)
        self.assertIn('mode === "wavecomplete"', swarm)
        self.assertNotIn("Math.min(4, ringLevel", swarm)
        self.assertNotIn("Math.min(5, burstLevel", swarm)
        self.assertIn("readonly property real worldAspect: worldWidth / worldHeight", swarm)
        self.assertIn("width: Math.min(parent.width, parent.height * game.worldAspect)", swarm)
        self.assertIn("renderStrategy: Canvas.Threaded", swarm)

        # Wave-complete transient-state clear (mines/bolts/rings/chains), per user feedback.
        self.assertIn("mines = []\n        bolts = []\n        rings = []\n        chains = []", swarm)
        # Enemy density should actually escalate with wave: batched spawns + faster cooldown floor.
        self.assertIn("function spawnBatchSize()", swarm)
        self.assertIn("Math.min(5, 1 + Math.floor(wave / 7))", swarm)
        # Mini-boss reuses the elite warning/spawn cycle.
        self.assertIn('type === "boss"', swarm)
        self.assertIn("enemyProfile(type)", swarm)
        # New weapon/passive upgrade tracks requested after playtesting.
        for upgrade_id in (
            "mine-cascade", "mine-cap-up", "orbit-range-up",
            "burst-multi-up", "burst-spread-up",
            "regen-up", "failover-up", "crit-up", "slow-aura-up",
        ):
            self.assertIn(f'id === "{upgrade_id}"', swarm)
        self.assertIn("function rollDamage(base)", swarm)

        for effect in ("launch", "hit", "levelup", "hurt", "death"):
            wav = (ROOT / "game" / "assets" / "sfx" / f"swarm-{effect}.wav").read_bytes()
            self.assertEqual(wav[:4], b"RIFF")
            self.assertEqual(wav[8:12], b"WAVE")

    def test_leaderboard_and_profile_text_forces_plain_text_rendering(self) -> None:
        # scores.json rows (initials, difficulty, ...) are attacker-editable
        # local state; every Text sink that renders them must force
        # Text.PlainText so a crafted value can't be interpreted as markup
        # or trigger resource loading.
        for relative_path, needle in (
            ("game/arcade.qml", 'text: "PLAYER PROFILE // " + (arcadeData.defaultInitials || "---")'),
            ("game/arcade.qml", "property var row: index < arcadeData.scoreRows.length"),
            ("game/shell.qml", "property var row: index < shell.scoreRows.length"),
            ("game/core-command.qml", "property var row: index < arcadeData.scoreRows.length"),
            ("game/rootbound.qml", "property var row: index < arcadeData.scoreRows.length"),
            ("game/daemon-swarm.qml", "property var row: index < arcadeData.scoreRows.length"),
            ("game/packet-hop.qml", "property var row: index < arcadeData.scoreRows.length"),
        ):
            source = (ROOT / relative_path).read_text(encoding="utf-8")
            index = source.index(needle)
            # The property must land within the same delegate/Text block, so
            # look for it in a window right after the needle rather than
            # anywhere in the file.
            window = source[index:index + 1200]
            self.assertIn(
                "textFormat: Text.PlainText", window,
                f"{relative_path}: missing textFormat: Text.PlainText near {needle!r}",
            )

    def test_flight_renderer_stays_inside_terminal_width(self) -> None:
        Settings = self.module["Settings"]
        Scores = self.module["Scores"]
        App = self.module["App"]
        app = App(Settings(), Scores(), direct=True)
        app.game.resize(78, 24)
        frame = app.render_game(80, 30)
        plain_lines = [
            re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", line)
            for line in frame.splitlines()
        ]
        self.assertTrue(plain_lines)
        self.assertTrue(all(len(line) <= 80 for line in plain_lines))
        plain = "\n".join(plain_lines)
        self.assertIn("OMACADE // LANDER", plain)
        self.assertIn("╱███╲", plain)
        self.assertIn("◆", plain)
        self.assertIn("▄", plain)


if __name__ == "__main__":
    unittest.main()
