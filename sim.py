"""ROV physics + control core. Pure Python, no Qt, so it can be unit-tested.

Frames / sign conventions
-------------------------
* Body axes: surge = forward (+), sway = right (+), heave = DOWN (+), yaw = clockwise (+).
* Depth is positive downwards, 0 = surface.
* Heading is in degrees, 0 = north, clockwise, in [0, 360).
* Thrust commands are normalised to [-1, 1] per axis (surge, sway, heave, yaw).
"""
import math
from dataclasses import dataclass, field

MANUAL, DEPTH_HOLD, HEADING_HOLD = "MANUAL", "DEPTH_HOLD", "HEADING_HOLD"
MODES = (MANUAL, DEPTH_HOLD, HEADING_HOLD)

SURGE, SWAY, HEAVE, YAW = range(4)


def clamp(x, lo, hi):
    return lo if x < lo else hi if x > hi else x


def wrap_pi(a):
    """Wrap an angle in radians to [-pi, pi)."""
    return (a + math.pi) % (2 * math.pi) - math.pi


@dataclass
class Params:
    # Effective mass incl. added mass [kg] and yaw inertia [kg m^2]
    mass: tuple = (18.0, 22.0, 22.0)
    inertia_z: float = 1.2
    # Max thrust per axis [N, N, N, N m]
    max_thrust: tuple = (40.0, 30.0, 30.0, 4.0)
    # Drag: F = -(linear*v + quadratic*|v|*v), for surge, sway, heave, yaw
    drag_lin: tuple = (8.0, 10.0, 10.0, 2.0)
    drag_quad: tuple = (20.0, 25.0, 25.0, 3.0)
    thruster_tau: float = 0.25        # first-order thruster lag [s]
    net_buoyancy: float = 0.5         # N, slightly positive -> drifts up if unattended
    max_depth: float = 50.0
    input_timeout: float = 1.0        # manual watchdog [s]
    # Battery (4S pack): open-circuit 13.2 V (empty) .. 16.8 V (full)
    capacity_as: float = 4000.0       # ampere-seconds (small on purpose, so the demo drains visibly)
    internal_resistance: float = 0.04
    # Depth-hold PID (output is a normalised heave command)
    depth_kp: float = 0.8
    depth_ki: float = 0.1
    depth_kd: float = 1.0
    depth_i_limit: float = 0.5
    # Heading-hold PD (output is a normalised yaw command)
    head_kp: float = 0.8
    head_kd: float = 0.5
    # Water current [m/s] in the world frame (optional extra)
    current_north: float = 0.0
    current_east: float = 0.0


class ROVSimulator:
    def __init__(self, params=None, start_depth=1.0):
        self.p = params or Params()
        self.t = 0.0
        self.armed = False
        self.mode = MANUAL

        # Pose (radians internally)
        self.north = 0.0
        self.east = 0.0
        self.depth = start_depth
        self.yaw = 0.0
        self.roll = self.pitch = 0.0
        self.roll_rate = self.pitch_rate = 0.0

        # Body velocities
        self.vel = [0.0, 0.0, 0.0, 0.0]   # surge, sway, heave, yaw-rate

        # Thrust chain: operator input -> command -> (lag) -> actual thrust
        self.operator = [0.0] * 4
        self.last_input_t = -math.inf
        self.command = [0.0] * 4
        self.thrust = [0.0] * 4           # normalised, after lag

        self.target_depth = start_depth
        self.target_heading = 0.0         # radians
        self._depth_i = 0.0

        self.soc = 1.0
        self.voltage = 16.8
        self.current_draw = 0.0

    # ------------------------------------------------------------------ commands
    def set_armed(self, armed):
        if armed == self.armed:
            return
        self.armed = armed
        self.operator = [0.0] * 4
        self.last_input_t = -math.inf
        self._depth_i = 0.0
        if not armed:
            self._zero_thrust()

    def set_mode(self, mode):
        if mode not in MODES or mode == self.mode:
            return
        self.mode = mode
        # Bumpless transfer: hold whatever we're at right now until told otherwise.
        self.target_depth = self.depth
        self.target_heading = self.yaw % (2 * math.pi)
        self._depth_i = 0.0

    def set_target_depth(self, metres):
        self.target_depth = clamp(float(metres), 0.0, self.p.max_depth)
        self._depth_i = 0.0

    def set_target_heading_deg(self, deg):
        self.target_heading = math.radians(float(deg) % 360.0)

    def set_operator_input(self, surge, sway, heave, yaw):
        """Operator sticks / keys. Every call counts as 'operator input' for the watchdog."""
        self.operator = [clamp(float(x), -1.0, 1.0) for x in (surge, sway, heave, yaw)]
        self.last_input_t = self.t

    def _zero_thrust(self):
        self.command = [0.0] * 4
        self.thrust = [0.0] * 4

    # ------------------------------------------------------------------ control
    def _operator_axes(self):
        if self.t - self.last_input_t >= self.p.input_timeout:
            return [0.0] * 4              # watchdog: stale input -> no thrust
        return self.operator

    def _compute_command(self, dt):
        op = self._operator_axes()
        cmd = list(op)
        if self.mode == DEPTH_HOLD:
            cmd[HEAVE] = self._depth_pid(dt)
        elif self.mode == HEADING_HOLD:
            cmd[YAW] = self._heading_pd()
        return [clamp(c, -1.0, 1.0) for c in cmd]

    def _depth_pid(self, dt):
        p = self.p
        err = self.target_depth - self.depth
        out_unsat = p.depth_kp * err + p.depth_ki * self._depth_i - p.depth_kd * self.vel[HEAVE]
        # Anti-windup: only integrate while the output isn't saturated
        if abs(out_unsat) < 1.0:
            self._depth_i = clamp(self._depth_i + err * dt, -p.depth_i_limit / max(p.depth_ki, 1e-9),
                                  p.depth_i_limit / max(p.depth_ki, 1e-9))
        return p.depth_kp * err + p.depth_ki * self._depth_i - p.depth_kd * self.vel[HEAVE]

    def _heading_pd(self):
        err = wrap_pi(self.target_heading - self.yaw)   # shortest way round
        return self.p.head_kp * err - self.p.head_kd * self.vel[YAW]

    # ------------------------------------------------------------------ physics
    def step(self, dt):
        p = self.p
        self.t += dt

        # 1. Commands and thruster response
        if self.armed:
            self.command = self._compute_command(dt)
            alpha = 1.0 - math.exp(-dt / p.thruster_tau)
            self.thrust = [a + (c - a) * alpha for a, c in zip(self.thrust, self.command)]
        else:
            self._zero_thrust()           # hard guarantee: disarmed => zero thrust

        # 2. Forces -> accelerations (body frame, water-relative velocity for drag)
        cn, ce = p.current_north, p.current_east
        cy, sy = math.cos(self.yaw), math.sin(self.yaw)
        rel = [self.vel[0] - (cn * cy + ce * sy),
               self.vel[1] - (-cn * sy + ce * cy),
               self.vel[2],
               self.vel[3]]
        masses = (p.mass[0], p.mass[1], p.mass[2], p.inertia_z)
        for i in range(4):
            force = self.thrust[i] * p.max_thrust[i] - (p.drag_lin[i] * rel[i] + p.drag_quad[i] * abs(rel[i]) * rel[i])
            if i == HEAVE:
                force -= p.net_buoyancy   # buoyancy pushes up (= negative heave)
            self.vel[i] += force / masses[i] * dt

        # 3. Kinematics
        u, v, w, r = self.vel
        self.north += (u * cy - v * sy) * dt
        self.east += (u * sy + v * cy) * dt
        self.yaw = wrap_pi(self.yaw + r * dt) % (2 * math.pi)
        self.depth += w * dt
        if self.depth < 0.0:
            self.depth, self.vel[HEAVE] = 0.0, max(self.vel[HEAVE], 0.0)
        elif self.depth > p.max_depth:
            self.depth, self.vel[HEAVE] = p.max_depth, min(self.vel[HEAVE], 0.0)

        # 4. Roll / pitch: lightly damped 2nd-order response to thrust, plus a little wave wobble
        self._step_attitude(dt)

        # 5. Battery
        load = sum(abs(x) for x in self.thrust)
        self.current_draw = (0.8 + 9.0 * load) if self.armed else 0.3
        self.soc = max(0.0, self.soc - self.current_draw * dt / p.capacity_as)
        self.voltage = 13.2 + 3.6 * self.soc - self.current_draw * p.internal_resistance

    def _step_attitude(self, dt, wn=6.0, zeta=0.5):
        pitch_t = math.radians(4.0) * self.thrust[SURGE] + math.radians(0.4) * math.sin(0.7 * self.t + 1.0)
        roll_t = math.radians(5.0) * self.thrust[SWAY] + math.radians(0.5) * math.sin(0.9 * self.t)
        self.roll_rate += (wn * wn * (roll_t - self.roll) - 2 * zeta * wn * self.roll_rate) * dt
        self.pitch_rate += (wn * wn * (pitch_t - self.pitch) - 2 * zeta * wn * self.pitch_rate) * dt
        self.roll += self.roll_rate * dt
        self.pitch += self.pitch_rate * dt

    # ------------------------------------------------------------------ output
    def snapshot(self):
        return {
            "t": self.t,
            "armed": self.armed,
            "mode": self.mode,
            "roll": math.degrees(self.roll),
            "pitch": math.degrees(self.pitch),
            "yaw": math.degrees(self.yaw) % 360.0,
            "depth": self.depth,
            "voltage": self.voltage,
            "soc": self.soc,
            "north": self.north,
            "east": self.east,
            "thrust": list(self.thrust),
            "target_depth": self.target_depth,
            "target_heading": math.degrees(self.target_heading) % 360.0,
        }
