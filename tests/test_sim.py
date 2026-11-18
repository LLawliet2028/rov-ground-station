import math
import sim
from sim import ROVSimulator, Params, MANUAL, DEPTH_HOLD, HEADING_HOLD

DT = 0.02


def run(s, seconds, drive=None):
    """Advance the sim; if `drive` is given, refresh operator input each step."""
    for _ in range(int(seconds / DT)):
        if drive:
            s.set_operator_input(*drive)
        s.step(DT)


def test_disarmed_thrust_is_always_zero():
    s = ROVSimulator()
    s.set_operator_input(1, 1, 1, 1)
    run(s, 1.0, drive=(1, 1, 1, 1))
    assert s.thrust == [0.0] * 4 and s.command == [0.0] * 4


def test_disarm_zeroes_thrust_immediately():
    s = ROVSimulator()
    s.set_armed(True)
    run(s, 2.0, drive=(1, 0, 0, 0))
    assert s.thrust[0] > 0.9
    s.set_armed(False)
    assert s.thrust == [0.0] * 4          # zero right away, not after a lag
    s.step(DT)
    assert s.thrust == [0.0] * 4


def test_thruster_lag_is_not_instant_but_converges():
    s = ROVSimulator()
    s.set_armed(True)
    run(s, DT, drive=(1, 0, 0, 0))
    assert 0 < s.thrust[0] < 0.2
    run(s, 2.0, drive=(1, 0, 0, 0))
    assert s.thrust[0] > 0.99


def test_manual_watchdog_zeroes_thrust_after_one_second():
    s = ROVSimulator()
    s.set_armed(True)
    run(s, 1.0, drive=(1, 0, 0, 0))
    assert s.command[0] == 1.0
    # operator stops sending input
    run(s, 0.9)
    assert s.command[0] == 1.0            # still within the 1 s window
    run(s, 0.2)
    assert s.command[0] == 0.0
    run(s, 2.0)
    assert abs(s.thrust[0]) < 1e-3


def test_drag_limits_speed():
    s = ROVSimulator()
    s.set_armed(True)
    run(s, 20.0, drive=(1, 0, 0, 0))
    p = s.p
    v = s.vel[0]
    # at terminal speed, thrust == drag
    assert math.isclose(p.max_thrust[0], p.drag_lin[0] * v + p.drag_quad[0] * v * v, rel_tol=0.02)


def test_depth_hold_converges_and_holds():
    s = ROVSimulator(start_depth=1.0)
    s.set_armed(True)
    s.set_mode(DEPTH_HOLD)
    s.set_target_depth(5.0)
    run(s, 30.0)
    assert abs(s.depth - 5.0) < 0.05
    assert abs(s.vel[2]) < 0.01


def test_depth_hold_target_is_clamped():
    s = ROVSimulator()
    s.set_target_depth(999)
    assert s.target_depth == s.p.max_depth
    s.set_target_depth(-3)
    assert s.target_depth == 0.0


def test_heading_hold_takes_shortest_way_across_north():
    s = ROVSimulator()
    s.yaw = math.radians(10)
    s.set_armed(True)
    s.set_mode(HEADING_HOLD)
    s.set_target_heading_deg(350)
    run(s, 0.5)
    assert s.vel[3] < 0                   # turning anticlockwise (20 deg), not clockwise (340 deg)
    run(s, 20.0)
    err = (math.degrees(s.yaw) - 350 + 180) % 360 - 180
    assert abs(err) < 1.0


def test_heading_hold_overshoot_is_small():
    s = ROVSimulator()
    s.set_armed(True)
    s.set_mode(HEADING_HOLD)
    s.set_target_heading_deg(90)
    peak = 0
    for _ in range(int(15 / DT)):
        s.step(DT)
        peak = max(peak, math.degrees(s.yaw) if math.degrees(s.yaw) < 180 else 0)
    assert peak < 95                      # <5 deg overshoot


def test_mode_switch_holds_current_state():
    s = ROVSimulator(start_depth=3.0)
    s.set_armed(True)
    s.set_mode(DEPTH_HOLD)
    assert s.target_depth == 3.0
    run(s, 10.0)
    assert abs(s.depth - 3.0) < 0.05


def test_depth_clamped_at_surface():
    s = ROVSimulator(start_depth=0.2)
    s.set_armed(True)
    run(s, 5.0, drive=(0, 0, -1, 0))
    assert s.depth == 0.0


def test_battery_drains_faster_under_load():
    a, b = ROVSimulator(), ROVSimulator()
    a.set_armed(True); b.set_armed(True)
    run(a, 10.0)
    run(b, 10.0, drive=(1, 1, 1, 1))
    assert b.voltage < a.voltage < 16.8
