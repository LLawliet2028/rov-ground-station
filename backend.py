"""Qt glue. The simulation runs on a plain Python thread; the QML UI lives on the GUI thread.

    QML --(slots)--> Backend --(lock)--> ROVSimulator <--(50 Hz)-- SimThread (threading.Thread)
    QML <-(props)--- Backend <-(25 Hz QTimer on GUI thread, copies a snapshot under the lock)

Why a plain threading.Thread: it keeps the physics off the GUI thread without involving Qt's thread
machinery. The lock makes every access to the simulator mutually exclusive, and no Qt signal ever crosses
a thread boundary, so there is nothing to marshal between threads.
"""
import math
import threading
import time

from PySide6.QtCore import QObject, QTimer, Qt, Property, Signal, Slot

from sim import ROVSimulator, MODES

SIM_DT = 0.02                  # 50 Hz fixed physics step
UI_PERIOD_MS = 40              # UI polls state at 25 Hz
PLOT_PERIOD = 0.1              # one plot sample every 100 ms (sim time)

# Where the vehicle "is" at north=0, east=0. Change to your nearest lake / pool.
ORIGIN_LAT, ORIGIN_LON = 23.2530, 77.3700


class SimThread(threading.Thread):
    """Steps the simulator at a fixed rate, holding the lock only while stepping."""

    def __init__(self, sim, lock):
        super().__init__(name="rov-sim", daemon=True)
        self._sim = sim
        self._lock = lock
        self._stop_evt = threading.Event()

    def stop(self):
        self._stop_evt.set()

    def run(self):
        last = time.perf_counter()
        acc = 0.0
        while not self._stop_evt.is_set():
            now = time.perf_counter()
            acc += min(now - last, 0.25)          # clamp so a stall can't cause a huge catch-up
            last = now
            if acc >= SIM_DT:
                with self._lock:
                    while acc >= SIM_DT:
                        self._sim.step(SIM_DT)
                        acc -= SIM_DT
            time.sleep(0.004)


class Backend(QObject):
    changed = Signal()          # telemetry changed (~25 Hz)
    plotChanged = Signal()      # plot sample tick (~10 Hz)

    def __init__(self):
        super().__init__()
        self._lock = threading.Lock()
        self._sim = ROVSimulator()
        self._s = {}
        self._last_plot_t = -1.0
        self._refresh()                           # fill self._s before QML reads anything

        self._sim_thread = SimThread(self._sim, self._lock)
        self._sim_thread.start()

        self._ui_timer = QTimer(self)
        self._ui_timer.setTimerType(Qt.PreciseTimer)
        self._ui_timer.setInterval(UI_PERIOD_MS)
        self._ui_timer.timeout.connect(self._poll)
        self._ui_timer.start()

    # ---------------------------------------------------------------- snapshot in (GUI thread)
    def _refresh(self):
        with self._lock:
            s = self._sim.snapshot()
        for i, v in enumerate(s.pop("thrust")):   # scalars only on the Python<->QML boundary
            s[f"thr{i}"] = v
        # metres -> degrees (flat-earth approximation, fine for a few hundred metres)
        s["lat"] = ORIGIN_LAT + s["north"] / 111_320.0
        s["lon"] = ORIGIN_LON + s["east"] / (111_320.0 * math.cos(math.radians(ORIGIN_LAT)))
        self._s = s

    @Slot()
    def _poll(self):
        self._refresh()
        self.changed.emit()
        if self._s["t"] - self._last_plot_t >= PLOT_PERIOD:
            self._last_plot_t = self._s["t"]
            self.plotChanged.emit()               # QML appends (simTime, depth) to its own buffer

    # ---------------------------------------------------------------- QML -> sim
    @Slot()
    def arm(self):
        with self._lock:
            self._sim.set_armed(True)

    @Slot()
    def disarm(self):
        with self._lock:
            self._sim.set_armed(False)

    @Slot(str)
    def setMode(self, mode):
        if mode in MODES:
            with self._lock:
                self._sim.set_mode(mode)

    @Slot(float)
    def setTargetDepth(self, m):
        with self._lock:
            self._sim.set_target_depth(m)

    @Slot(float)
    def setTargetHeading(self, deg):
        with self._lock:
            self._sim.set_target_heading_deg(deg)

    @Slot(float, float, float, float)
    def drive(self, surge, sway, heave, yaw):
        with self._lock:
            self._sim.set_operator_input(surge, sway, heave, yaw)

    @Slot()
    def shutdown(self):
        self._ui_timer.stop()
        self._sim_thread.stop()
        self._sim_thread.join(1.0)

    # ---------------------------------------------------------------- props for QML
    armed = Property(bool, lambda self: self._s["armed"], notify=changed)
    mode = Property(str, lambda self: self._s["mode"], notify=changed)
    roll = Property(float, lambda self: self._s["roll"], notify=changed)
    pitch = Property(float, lambda self: self._s["pitch"], notify=changed)
    yaw = Property(float, lambda self: self._s["yaw"], notify=changed)
    depth = Property(float, lambda self: self._s["depth"], notify=changed)
    voltage = Property(float, lambda self: self._s["voltage"], notify=changed)
    soc = Property(float, lambda self: self._s["soc"], notify=changed)
    lat = Property(float, lambda self: self._s["lat"], notify=changed)
    lon = Property(float, lambda self: self._s["lon"], notify=changed)
    targetDepth = Property(float, lambda self: self._s["target_depth"], notify=changed)
    targetHeading = Property(float, lambda self: self._s["target_heading"], notify=changed)
    thrust0 = Property(float, lambda self: self._s["thr0"], notify=changed)
    thrust1 = Property(float, lambda self: self._s["thr1"], notify=changed)
    thrust2 = Property(float, lambda self: self._s["thr2"], notify=changed)
    thrust3 = Property(float, lambda self: self._s["thr3"], notify=changed)
    simTime = Property(float, lambda self: self._s["t"], notify=changed)
