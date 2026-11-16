#!/usr/bin/env python3
"""Check remote host labels with the installed Powerlevel10k in a real terminal."""

import errno
import os
import pty
import select
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

LOADER = Path(__file__).resolve().with_name("p10k.zsh")
CONFIG = LOADER.with_name("p10k.zsh.symlink")
THEME = Path.home() / ".nix-profile/share/zsh-powerlevel10k"
ZSH = shutil.which("zsh")
READY = b"\x1b[?2004h"


class Shell:
    def __init__(self, env):
        self.pid, self.fd = pty.fork()
        self.exited = False
        if self.pid == 0:
            os.chdir(env["HOME"])
            os.execve(ZSH, [ZSH, "-di"], env)

    def prompt(self, command=None):
        if command is not None:
            os.write(self.fd, command.encode() + b"\n")
        output = bytearray()
        deadline = time.monotonic() + 10
        while READY not in output and time.monotonic() < deadline:
            if select.select([self.fd], [], [], 0.1)[0]:
                try:
                    data = os.read(self.fd, 65536)
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
                    break
                if not data:
                    break
                output.extend(data)
        if READY not in output:
            raise AssertionError(f"Prompt did not appear: {bytes(output)!r}")
        return bytes(output)

    def close(self):
        os.write(self.fd, b"exit\n")
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if os.waitpid(self.pid, os.WNOHANG)[0]:
                self.exited = True
                break
            time.sleep(0.02)
        if not self.exited:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        os.close(self.fd)


@unittest.skipUnless(ZSH and THEME.is_dir(), "Requires Zsh and Powerlevel10k")
class PromptTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="test-p10k-")
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        theme_link = self.home / ".nix-profile/share/zsh-powerlevel10k"
        theme_link.parent.mkdir(parents=True)
        theme_link.symlink_to(THEME, target_is_directory=True)
        (self.home / ".p10k.zsh").symlink_to(CONFIG)
        (self.home / ".zshrc").write_text(
            "HISTFILE=/dev/null\n"
            "HOST=raw-host.example\n"
            "stty cols 240 rows 30\n"
            f"source {shlex.quote(str(LOADER))}\n"
        )
        commands = self.home / "bin"
        commands.mkdir()
        hostnamectl = commands / "hostnamectl"
        hostnamectl.write_text(
            "#!/bin/sh\n"
            'printf "%s\\n" "$*" >> "$TEST_HOST_CALLS"\n'
            'printf "%s\\n" "$TEST_PRETTY"\n'
            'exit "$TEST_HOST_EXIT"\n'
        )
        hostnamectl.chmod(0o755)
        self.env = {
            "HOME": str(self.home),
            "ZDOTDIR": str(self.home),
            "PATH": f"{commands}:{os.environ['PATH']}",
            "TERM": "xterm-256color",
            "LANG": "C.UTF-8",
            "USER": os.environ.get("USER", "test-user"),
            "LOGNAME": os.environ.get("LOGNAME", "test-user"),
            "XDG_CACHE_HOME": str(self.home / "cache"),
            "TEST_HOST_CALLS": str(self.home / "host-calls"),
            "TEST_PRETTY": "Test Host",
            "TEST_HOST_EXIT": "0",
        }

    def start(self, remote=True, **changes):
        env = self.env | changes
        if remote:
            env["SSH_CONNECTION"] = "192.0.2.1 12345 192.0.2.2 22"
        shell = Shell(env)
        self.addCleanup(shell.close)
        return shell

    def test_remote_first_prompt_and_reload(self):
        shell = self.start(ZMX_SESSION="remote-work")
        first = shell.prompt()
        self.assertEqual(first.count(b"REMOTE  "), 1, repr(first))
        self.assertGreaterEqual(first.count(b"@Test Host"), 2)
        self.assertIn(b"zmx:remote-work", first)
        self.assertNotIn(b"raw-host", first)
        self.assertNotIn(b"REMOTE  ", shell.prompt(""))
        reloaded = shell.prompt(f"source {shlex.quote(str(LOADER))}")
        self.assertNotIn(b"REMOTE  ", reloaded)
        self.assertIn(b"@Test Host", reloaded)
        self.assertEqual((self.home / "host-calls").read_text(), "--pretty\n")

    def test_local_context_stays_hidden(self):
        output = self.start(remote=False).prompt()
        self.assertNotIn(b"REMOTE  ", output)
        self.assertNotIn(b"@Test Host", output)

    def test_interactive_command_has_no_banner(self):
        env = self.env | {"SSH_TTY": "/dev/pts/123"}
        result = subprocess.run(
            [ZSH, "-dic", "print -r -- COMMAND_DONE"],
            env=env,
            cwd=self.home,
            capture_output=True,
            check=True,
        )
        self.assertEqual(result.stdout, b"COMMAND_DONE\n")

    def test_empty_pretty_name_uses_short_host(self):
        output = self.start(TEST_PRETTY=" \t").prompt()
        self.assertGreaterEqual(output.count(b"@raw-host"), 2)
        self.assertNotIn(b".example", output)

    def test_failed_lookup_uses_short_host(self):
        output = self.start(TEST_HOST_EXIT="1").prompt()
        self.assertGreaterEqual(output.count(b"@raw-host"), 2)
        self.assertNotIn(b"Test Host", output)

    def test_pretty_name_is_literal(self):
        sentinel = self.home / "unexpected-command"
        pretty = f"lab %F{{red}} $(touch {sentinel})"
        output = self.start(TEST_PRETTY=pretty).prompt()
        self.assertGreaterEqual(output.count(f"@{pretty}".encode()), 2)
        self.assertFalse(sentinel.exists())


if __name__ == "__main__":
    unittest.main()
