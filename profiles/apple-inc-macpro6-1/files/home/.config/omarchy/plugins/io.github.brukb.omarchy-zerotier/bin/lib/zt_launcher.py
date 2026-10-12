#!/usr/bin/env python3
"""Exec zt_helper with the API token already on stdin (never argv).

Quickshell's Process closes extra inherited fds. The old memfd→dup2(fd 3)→execv
path hit EBADF under the bar; stdin survives. This process only replaces itself
with the helper — same stdin, no new fds.
"""

from __future__ import annotations

import os
import sys


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(127)
    helper = sys.argv[1]
    os.execv(sys.executable, [sys.executable, helper, *sys.argv[2:]])


if __name__ == "__main__":
    main()
