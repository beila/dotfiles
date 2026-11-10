#!/usr/bin/env python3
"""Exercise clipboard transport with an isolated native clipboard."""

import os
import shlex
import socket
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BRIDGE = ROOT / "bin/clipboard-bridge"


class ClipboardBridgeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="clipboard-test-")
        self.directory = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.clipboard = self.directory / "clipboard"
        self.clipboard.write_bytes(b"")
        binaries = self.directory / "bin"
        binaries.mkdir()
        xclip = binaries / "xclip"
        xclip.write_text(
            '#!/bin/sh\n'
            'if [ "$TEST_NATIVE_FAILURE" = 1 ]; then exit 7; fi\n'
            'case "$*" in\n'
            '  *-out*) cat "$TEST_CLIPBOARD" ;;\n'
            '  *) cat > "$TEST_CLIPBOARD" ;;\n'
            'esac\n'
        )
        xclip.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{binaries}:{os.environ['PATH']}",
            "DISPLAY": ":clipboard-test",
            "TEST_CLIPBOARD": str(self.clipboard),
        }
        for key in ("WAYLAND_DISPLAY", "SSH_CONNECTION", "SSH_TTY", "ZMX_SESSION"):
            self.env.pop(key, None)
        self.session = f"test-{os.getpid()}-{self.directory.name}"
        self.remote_env = {
            **self.env,
            "SSH_CONNECTION": "test",
            "ZMX_SESSION": self.session,
        }
        self.path = Path(self.run_bridge("prepare", self.session).stdout.decode().strip())
        self.addCleanup(self.path.unlink, missing_ok=True)

    def run_bridge(self, *args, env=None, data=None, check=True):
        return subprocess.run(
            [str(BRIDGE), *args],
            input=data,
            env=env or self.env,
            capture_output=True,
            timeout=15,
            check=check,
        )

    def serve(self, env=None):
        process = subprocess.Popen(
            [str(BRIDGE), "serve", str(self.path)],
            env=env or self.env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )

        def stop():
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)

        self.addCleanup(stop)
        for _ in range(100):
            if self.path.exists():
                return process
            if process.poll() is not None:
                self.fail(process.communicate()[1].decode())
            time.sleep(0.01)
        self.fail("clipboard server did not start")

    def test_native_and_remote_bytes(self):
        text = "한글 and spaces\nsecond line\n\n".encode()
        self.run_bridge("copy", data=text)
        self.assertEqual(self.run_bridge("paste").stdout, text)
        self.serve()
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.path.parent.stat().st_mode), 0o700)
        self.run_bridge("copy", env=self.remote_env, data=text)
        self.assertEqual(self.clipboard.read_bytes(), text)
        self.clipboard.write_bytes(b"new local content\n")
        self.assertEqual(
            self.run_bridge("paste", env=self.remote_env).stdout, b"new local content\n"
        )
        self.run_bridge("copy", env=self.remote_env, data=b"")
        self.assertEqual(self.clipboard.read_bytes(), b"")

    def test_shell_commands_and_files(self):
        self.serve()
        source = self.directory / "space in filename"
        source.write_bytes(b"file\n")
        env = {**self.remote_env, "DOTFILES_ROOT": str(ROOT)}
        result = subprocess.run(
            [
                "zsh", "-f", "-c",
                ('fpath=("$DOTFILES_ROOT/zsh/functions" $fpath); '
                 'autoload -Uz c p; c "$1" -; p'),
                "test", str(source),
            ],
            input=b"stdin\n",
            env=env,
            capture_output=True,
            timeout=15,
            check=True,
        )
        self.assertEqual(result.stdout, b"file\nstdin\n")

    def test_reconnect_reuses_session_path(self):
        first = self.serve()
        first.terminate()
        first.wait(timeout=5)
        self.run_bridge("prepare", self.session)
        self.serve()
        self.run_bridge("copy", env=self.remote_env, data=b"reconnected")
        self.assertEqual(self.clipboard.read_bytes(), b"reconnected")
        other = {**self.remote_env, "ZMX_SESSION": self.session + "-other"}
        self.assertNotEqual(self.run_bridge("paste", env=other, check=False).returncode, 0)

    def test_disconnected_and_native_failures(self):
        failure = self.run_bridge("copy", env=self.remote_env, data=b"lost", check=False)
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn(b"reconnect with jc", failure.stderr)
        self.assertEqual(self.clipboard.read_bytes(), b"")
        self.serve({**self.env, "TEST_NATIVE_FAILURE": "1"})
        failure = self.run_bridge("paste", env=self.remote_env, check=False)
        self.assertNotEqual(failure.returncode, 0)
        self.assertIn(b"exit status 7", failure.stderr)

    def test_rejects_unsafe_path_and_protocol(self):
        self.path.symlink_to(self.clipboard)
        failure = self.run_bridge("prepare", self.session, check=False)
        self.assertNotEqual(failure.returncode, 0)
        self.assertEqual(self.clipboard.read_bytes(), b"")
        self.path.unlink()
        self.serve()
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect(str(self.path))
            client.sendall(b"invalid")
            client.shutdown(socket.SHUT_WR)
            self.assertTrue(client.recv(1024).startswith(b"\1invalid"))

    def test_neovim_clipboard(self):
        self.serve()
        home = self.directory / "home"
        home.mkdir()
        (home / ".dotfiles").symlink_to(ROOT)
        env = {
            **self.remote_env,
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(self.directory / "config"),
            "XDG_CACHE_HOME": str(self.directory / "cache"),
            "XDG_DATA_HOME": str(self.directory / "data"),
            "XDG_STATE_HOME": str(self.directory / "state"),
            "XDG_RUNTIME_DIR": str(self.directory),
            "TEST_NVIM_PLUGINS": str(
                Path.home() / ".local/share/nvim/site/pack/hm/start"
            ),
        }
        result = subprocess.run(
            ["nvim", "--headless", "-u", "NONE", "-i", "NONE", "-l",
             str(ROOT / "nvim.configsymlink/test_remote_clipboard.lua")],
            env=env,
            capture_output=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, (result.stdout + result.stderr).decode())

    @unittest.skipUnless(os.environ.get("CLIPBOARD_TEST_SSH_HOST"), "no SSH test host selected")
    def test_real_ssh_forward(self):
        self.serve()
        host = os.environ["CLIPBOARD_TEST_SSH_HOST"]
        ssh = ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10"]
        helper = "~/.dotfiles/bin/clipboard-bridge"
        prepared = subprocess.run(
            [*ssh, host, f"{helper} prepare {shlex.quote(self.session)}"],
            check=True, capture_output=True, timeout=30,
        )
        remote_path = prepared.stdout.decode().strip()

        def cleanup():
            subprocess.run(
                [*ssh, host, f"rm -f -- {shlex.quote(remote_path)}"],
                check=False, capture_output=True, timeout=30,
            )

        self.addCleanup(cleanup)
        lua = (
            'package.path=vim.fn.expand("~/.dotfiles/nvim.configsymlink/lua/?.lua;")..package.path;'
            'assert(require("remote-clipboard").setup());'
            'vim.fn.setreg("+","nvim live probe");'
            'assert(vim.fn.getreg("+")=="nvim live probe")'
        )
        command = (
            f"export ZMX_SESSION={shlex.quote(self.session)}; "
            "zsh -fc 'fpath=(~/.dotfiles/zsh/functions $fpath); "
            "autoload -Uz c p; c && p' && "
            f"nvim --headless -u NONE -i NONE -c {shlex.quote('lua ' + lua)} -c 'qa!'"
        )
        text = "SSH clipboard 한글\nwith trailing newline\n".encode()
        result = subprocess.run(
            [*ssh, "-o", "ExitOnForwardFailure=yes",
             "-R", f"{remote_path}:{self.path}", host, command],
            input=text, capture_output=True, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(result.stdout, text)
        self.assertEqual(self.clipboard.read_bytes(), b"nvim live probe")


if __name__ == "__main__":
    unittest.main()
