#!/usr/bin/env python3
"""QEMU serial terminal bridge."""
import pty, os, subprocess, select, sys, termios, tty

def main():
    master_fd, slave_fd = pty.openpty()
    slave_name = os.ttyname(slave_fd)
    os.close(slave_fd)

    proc = subprocess.Popen([
        "qemu-system-i386",
        "-kernel", "examples/kernel/interactive",
        "-serial", slave_name,
        "-display", "none",
        "-no-reboot"
    ])

    stdin_fd = sys.stdin.fileno()
    old = termios.tcgetattr(stdin_fd)
    tty.setraw(stdin_fd)

    try:
        while True:
            r, _, _ = select.select([stdin_fd, master_fd], [], [], 0.5)
            if stdin_fd in r:
                data = os.read(stdin_fd, 256)
                if data:
                    os.write(master_fd, data)
            if master_fd in r:
                data = os.read(master_fd, 4096)
                if data:
                    os.write(sys.stdout.fileno(), data)
    except KeyboardInterrupt:
        pass
    finally:
        termios.tcsetattr(stdin_fd, termios.TCSANOW, old)
        proc.kill()
        proc.wait()

if __name__ == "__main__":
    main()
