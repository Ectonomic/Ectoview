"""Turn the mouse wheel inside the test's KWin, the way a real wheel does.

usage: python3 -I eis-wheel.py   (then lines on stdin, like the fake-input helper)
  "move X Y"   the pointer to X,Y (global logical pixels)
  "wheel N"    N wheel detents (positive turns it toward you: the next desktop)
Prints "ready" once connected, then "ok" after each line.

KWin's fake-input axis carries no 120-unit wheel step, so an effect's WheelHandler sees
no wheel at all (docs/deferred.md). KWin's EIS input does: a discrete scroll reaches
effects with its v120 step (kwin src/plugins/eis/eiscontext.cpp, EIS_EVENT_SCROLL_DISCRETE).
The connection is KWin's org.kde.KWin.EIS.RemoteDesktop, as kwin-mcp's input.py uses it
(isac322/kwin-mcp, MIT), cut down to a pointer that moves and scrolls.
"""

import ctypes
import select
import sys
import time

import dbus

CAP_POINTER_ABSOLUTE, CAP_SCROLL, CAP_BUTTON = 1 << 1, 1 << 4, 1 << 5
EV_DISCONNECT, EV_SEAT_ADDED, EV_DEVICE_ADDED, EV_DEVICE_RESUMED = 2, 3, 5, 8

ei = ctypes.CDLL("libei.so.1")
P = ctypes.c_void_p
for name, res, args in [
    ("ei_new_sender", P, [P]),
    ("ei_configure_name", None, [P, ctypes.c_char_p]),
    ("ei_setup_backend_fd", ctypes.c_int, [P, ctypes.c_int]),
    ("ei_dispatch", None, [P]),
    ("ei_get_fd", ctypes.c_int, [P]),
    ("ei_get_event", P, [P]),
    ("ei_event_get_type", ctypes.c_int, [P]),
    ("ei_event_unref", P, [P]),
    ("ei_event_get_seat", P, [P]),
    ("ei_seat_has_capability", ctypes.c_int, [P, ctypes.c_uint]),
    ("ei_event_get_device", P, [P]),
    ("ei_device_has_capability", ctypes.c_int, [P, ctypes.c_uint]),
    ("ei_device_ref", P, [P]),
    ("ei_device_start_emulating", None, [P, ctypes.c_uint32]),
    ("ei_device_pointer_motion_absolute", None, [P, ctypes.c_double, ctypes.c_double]),
    ("ei_device_scroll_discrete", None, [P, ctypes.c_int32, ctypes.c_int32]),
    ("ei_device_frame", None, [P, ctypes.c_uint64]),
]:
    fn = getattr(ei, name)
    fn.restype, fn.argtypes = res, args
ei.ei_seat_bind_capabilities.restype = None


def now_us():
    return int(time.monotonic() * 1_000_000)


def main():
    remote = dbus.Interface(
        dbus.SessionBus().get_object("org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop"),
        "org.kde.KWin.EIS.RemoteDesktop",
    )
    fd, _cookie = remote.connectToEIS(dbus.Int32(CAP_POINTER_ABSOLUTE | CAP_SCROLL | CAP_BUTTON))
    ctx = ei.ei_new_sender(None)
    ei.ei_configure_name(ctx, b"ectoview-test-wheel")
    if ei.ei_setup_backend_fd(ctx, fd.take()) != 0:
        sys.exit("ei_setup_backend_fd failed")
    pointer, ready = None, False
    deadline = time.monotonic() + 5
    while not ready and time.monotonic() < deadline:
        select.select([ei.ei_get_fd(ctx)], [], [], 0.2)
        ei.ei_dispatch(ctx)
        while event := ei.ei_get_event(ctx):
            kind = ei.ei_event_get_type(event)
            if kind == EV_DISCONNECT:
                sys.exit("KWin closed the EIS connection")
            if kind == EV_SEAT_ADDED:
                seat = ei.ei_event_get_seat(event)
                caps = [c for c in (CAP_POINTER_ABSOLUTE, CAP_SCROLL, CAP_BUTTON)
                        if ei.ei_seat_has_capability(seat, c)]
                ei.ei_seat_bind_capabilities(P(seat), *[ctypes.c_uint(c) for c in caps], P(None))
            elif kind == EV_DEVICE_ADDED and pointer is None:
                device = ei.ei_event_get_device(event)
                if ei.ei_device_has_capability(device, CAP_POINTER_ABSOLUTE) and \
                        ei.ei_device_has_capability(device, CAP_SCROLL):
                    pointer = ei.ei_device_ref(device)
            elif kind == EV_DEVICE_RESUMED and pointer is not None and \
                    ei.ei_event_get_device(event) == pointer:
                ei.ei_device_start_emulating(pointer, 0)
                ready = True
            ei.ei_event_unref(event)
    if not ready:
        sys.exit("no EIS pointer that scrolls")
    print("ready", flush=True)
    for line in sys.stdin:
        word, *args = line.split()
        if word == "move":
            ei.ei_device_pointer_motion_absolute(pointer, float(args[0]), float(args[1]))
        elif word == "wheel":
            ei.ei_device_scroll_discrete(pointer, 0, 120 * int(args[0]))
        ei.ei_device_frame(pointer, now_us())
        ei.ei_dispatch(ctx)
        print("ok", flush=True)


main()
