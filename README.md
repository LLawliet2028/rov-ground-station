# ROV Telemetry Ground Station

Native desktop app (Python 3 + PySide6 / Qt Quick QML) that simulates a small ROV and lets an operator monitor and control it. No browser or web stack.

## Run

```bash
pip install -r requirements.txt      # pins PySide6 to 6.8.x, see note below
python main.py
python -m pytest          # unit tests for the sim / safety logic
```

Needs internet for the OpenStreetMap tiles (Qt Location `osm` plugin, tiles cached on disk by Qt). Vehicle start position is `ORIGIN_LAT/LON` in `backend.py`.

**PySide6 version:** pinned to `>=6.7,<6.9`. PySide6 6.12.0 on Python 3.10 aborts with `free(): invalid pointer/size` a few seconds after startup (reproduced on a clean Python 3.10 venv; identical code is fine on 6.8.3 and on Python 3.12). Debugged by bisecting: removing the map, the thread, and the property style did not help; changing only the PySide version did.

## Controls

Click the dashboard once so it has keyboard focus, then:

| Key | Action |
|---|---|
| W / S | forward / back |
| A / D | strafe left / right |
| Q / E or ← / → | turn left / right |
| R / F or ↑ / ↓ | ascend / descend |

Arm / Disarm buttons, Manual / Depth Hold / Heading Hold buttons, and target depth / heading boxes (type a value, press Enter or click Set).
Joystick input is not implemented (Qt 6 dropped QtGamepad); keyboard only.

## Architecture

```
sim.py       pure-Python physics + control (no Qt). Unit-tested.
backend.py   SimThread (threading.Thread, 50 Hz) steps the sim under a lock;
             Backend (GUI thread) polls snapshots and exposes properties/slots to QML.
Main.qml     dashboard: telemetry tiles, controls, thrust bars, depth plot (Shapes), instrument panel, OSM map.
tests/       pytest: disarm, watchdog, lag, drag, both hold modes, wraparound, battery.
```

**Responsiveness:** physics runs on its own `threading.Thread` (50 Hz fixed step) behind a single lock. The GUI thread polls a snapshot at 25 Hz and the plot appends one sample every 100 ms to a buffer owned by QML (only scalars cross the Python↔QML boundary). A plain Python thread plus one lock keeps the design simple: no Qt signals cross threads, so there is nothing to marshal.

**Dynamics:** per-axis (surge, sway, heave, yaw) `m·a = thrust − (c_lin·v + c_quad·|v|·v)`, water-relative so a current can be added. Thrust passes through a first-order lag (tau = 0.25 s). Slightly positive buoyancy. Roll/pitch are a damped 2nd-order response to thrust plus small wobble. Battery is a state-of-charge model with load-dependent sag.

**Safety**
- Disarmed: `step()` forces command and actual thrust to exactly zero every tick (and `set_armed(False)` zeros it instantly, not after the lag).
- Operator-input watchdog: if the last input is >= 1 s old, operator axes are zeroed. Held keys re-send every 100 ms, so holding a key keeps driving; if the UI dies or focus is lost, thrust cuts out.
- In the hold modes the watchdog still applies to the operator's other axes.

**Hold modes**
- Depth Hold: PID on depth with velocity damping (D term on measured heave rate), integral with clamp + anti-windup; the integral soaks up the buoyancy offset.
- Heading Hold: PD on yaw with the error wrapped to [-180, 180) so it always turns the short way across north.
- Switching modes captures the current depth/heading as the target (no jump).

## AI tools disclosure

I used Claude (Anthropic) as a coding assistant for this project.

- **Code:** Claude wrote the initial implementation of the simulator (`sim.py`), the Qt/QML glue (`backend.py`, `main.py`), the dashboard (`Main.qml`, including the artificial horizon, compass tape and depth tape) and the unit tests (`tests/test_sim.py`).
- **Debugging:** the app aborted on my machine (Ubuntu 22.04, Python 3.10) with a heap-corruption error. I ran the app under `faulthandler` and `gdb` and sent the output to Claude. We worked through several wrong theories (cross-thread signals, QVariantList properties, Canvas, QThread) and eventually found the cause by reproducing my environment and changing one variable at a time. The cause was PySide6 6.12.0 on Python 3.10, so I pinned PySide6 to 6.8.x.
- **My part:** I specified the requirements, ran and tested the application on my own machine, reported the crashes and logs, chose which features to include, and reviewed the code. I can explain and modify every part of it.
