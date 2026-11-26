#!/usr/bin/env python3
import json
import os
from pathlib import Path
import select
import shlex
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = 'source config/zsh/zz-rmux.zsh; source config/zsh/zz-tmux.zsh; '


class Harness:
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='tmux-helpers-')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.capture = self.home / 'calls.jsonl'
        self.env = {k: v for k, v in os.environ.items()
                    if k not in ('RMUX', 'RMUX_PANE', 'TMUX', 'TMUX_PANE', 'ZDOTDIR',
                                 'CC_GG_INLINE', 'DISABLE_AUTO_TITLE')}
        self.env.update(HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        MUX_CAPTURE=str(self.capture))
        stub = f'''#!{sys.executable}
import json, os, sys
from pathlib import Path
with open(os.environ['MUX_CAPTURE'], 'a') as stream:
    stream.write(json.dumps([Path(sys.argv[0]).name, sys.argv[1:]]) + '\\n')
'''
        for name in ('tmux-store', 'rmux-store', 'rmux', 'tmux', 'claude', 'copilot'):
            executable = self.bin / name
            executable.write_text(stub)
            executable.chmod(0o755)

    def shell(self, code, interactive=False, ostype=None, **env):
        prelude = f'OSTYPE={shlex.quote(ostype)}; ' if ostype else ''
        result = subprocess.run(['/bin/zsh', '-fi' if interactive else '-f', '-c',
                                 prelude + SOURCE + code],
                                cwd=ROOT, env=dict(self.env, **env), capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def calls(self):
        return [json.loads(line) for line in self.capture.read_text().splitlines()] if self.capture.exists() else []


class HelperTests(Harness, unittest.TestCase):

    def test_source_never_attaches_and_keeps_native_command(self):
        self.shell('[[ $+functions[tmux] == 0 ]]; [[ $+functions[tr] == 0 ]]')
        self.assertEqual(self.calls(), [])

    def test_helper_mapping_and_interactive_tr(self):
        self.shell('tt main; tr work; tl; td work; th; ts', interactive=True)
        self.assertEqual(self.calls(), [['tmux-store', args] for args in
                         (['attach', 'main'], ['attach', 'work'], ['list'],
                          ['delete', 'work'], ['help'], ['restart'])])

    def test_r_helpers_run_t_twins_on_macos_and_linux(self):
        for ostype in ('darwin25.0', 'linux-gnu'):
            with self.subTest(ostype=ostype):
                self.capture.unlink(missing_ok=True)
                self.shell('[[ $+functions[rmux] == 0 ]]; rr main; rl; rd main; rh; rs',
                           ostype=ostype)
                self.assertEqual(self.calls(), [['tmux-store', args] for args in
                                 (['attach', 'main'], ['list'], ['delete', 'main'],
                                  ['help'], ['restart'])])

    def test_r_helpers_keep_rmux_on_windows(self):
        for ostype in ('msys', 'cygwin', 'win32'):
            with self.subTest(ostype=ostype):
                self.capture.unlink(missing_ok=True)
                self.shell('rr main; rl; rd main; rh; rs; rmux -V', ostype=ostype)
                self.assertEqual(self.calls(), [['rmux-store', args] for args in
                                 (['rr', 'main'], ['rl'], ['rd', 'main'], ['help'],
                                  ['restart'], ['client', '-V'])])

    def test_translation_utility_stays_usable(self):
        output = self.shell("printf abc | tr a-z A-Z; print; printf abc | tr -d b; print; "
                            "printf abc | command tr a-z A-Z", interactive=True)
        self.assertEqual(output, 'ABC\nac\nABC')
        self.assertEqual(self.calls(), [])

    def test_arity_errors_do_not_call_backend(self):
        self.shell('tt >/dev/null 2>&1; [[ $? == 2 ]] || return 1; '
                   'tt one two >/dev/null 2>&1; [[ $? == 2 ]] || return 1; '
                   'td >/dev/null 2>&1; [[ $? == 2 ]] || return 1; '
                   'for helper in tl th ts; do "$helper" extra >/dev/null 2>&1; '
                   '[[ $? == 2 ]] || return 1; done')
        self.assertEqual(self.calls(), [])

    def test_detach_dispatch_prefers_rmux(self):
        self.shell('exit; logout', RMUX='rmux-socket', TMUX='compat-socket')
        self.assertEqual(self.calls(), [['rmux-store', ['client', 'detach-client']]] * 2)

    def test_native_tmux_detaches(self):
        self.shell('exit; logout', TMUX='/tmp/native,123,0')
        self.assertEqual(self.calls(), [['tmux-store', ['client', 'detach-client']]] * 2)

    def test_normal_exit_keeps_status(self):
        result = subprocess.run(['/bin/zsh', '-f', '-c', SOURCE + 'exit 7'], cwd=ROOT,
                                env=self.env, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.calls(), [])

    def test_ctrl_d_detaches_only_empty_mux_buffer(self):
        self.shell("zle() { print -r -- \"$*\"; }; BUFFER=''; _rmux_detach_or_delete_char; "
                   "BUFFER=text; _rmux_detach_or_delete_char", TMUX='/tmp/native,123,0')
        self.assertEqual(self.calls(), [['tmux-store', ['client', 'detach-client']]])
        self.capture.unlink()
        output = self.shell("zle() { print -r -- \"$*\"; }; BUFFER=''; _rmux_detach_or_delete_char")
        self.assertEqual(output.strip(), '.delete-char-or-list')
        self.assertEqual(self.calls(), [])

    def test_titles_route_to_native_store_without_path_tmux(self):
        title = 'literal #{session_name}; $(not-a-command)'
        self.shell('source config/zsh/cc.zsh; source config/zsh/gg.zsh; '
                   f'cc {shlex.quote(title)}; gg {shlex.quote(title)}', TMUX='/tmp/native,123,0')
        calls = self.calls()
        self.assertEqual([call[0] for call in calls], ['tmux-store', 'claude', 'tmux-store', 'copilot'])
        self.assertEqual(calls[0][1][0], 'rename')
        self.assertTrue(calls[0][1][1].endswith(title))
        self.assertTrue(calls[2][1][1].endswith(title))
        self.assertEqual(calls[1][1], ['--permission-mode', 'bypassPermissions', '--model',
                                     'claude-opus-5-5[1m]', '--effort', 'xhigh'])
        self.assertEqual(calls[3][1], ['--yolo', '--model', 'gpt-6-astra',
                                     '--context', 'long_context', '--effort', 'xhigh'])

    def test_titles_keep_rmux_route_when_both_markers_present(self):
        self.shell('source config/zsh/cc.zsh; cc title', RMUX='rmux-socket', TMUX='compat-socket')
        self.assertEqual([call[0] for call in self.calls()], ['rmux', 'claude'])


LAUNCHERS = 'source config/zsh/cc.zsh; source config/zsh/gg.zsh; '


class LaunchTests(Harness, unittest.TestCase):
    """cc/gg outside a multiplexer, driven through a real pseudo-terminal."""

    def setUp(self):
        super().setUp()
        self.runtime = self.bin / 'fake-tmux-runtime'
        self.runtime.write_text('#!/bin/sh\n')
        self.runtime.chmod(0o755)
        store = self.bin / 'tmux-store'
        store.write_text(f'''#!{sys.executable}
import json, os, sys
with open(os.environ['MUX_CAPTURE'], 'a') as stream:
    stream.write(json.dumps(['tmux-store', sys.argv[1:], os.isatty(0), os.isatty(1)]) + '\\n')
sys.exit(int(os.environ.get('STUB_STATUS', '0')))
''')
        self.status = self.home / 'status'
        self.prelude = (f'OSTYPE=darwin25.0; _mux_tmux_runtimes=({shlex.quote(str(self.runtime))}); ')

    def pty(self, code, send=(), timeout=10, **env):
        master, slave = os.openpty()
        process = subprocess.Popen(['/bin/zsh', '-f', '-c', code], cwd=ROOT, env=dict(self.env, **env),
                                   stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
        os.close(slave)
        output, pending = b'', list(send)
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], .1)
                if ready:
                    try:
                        chunk = os.read(master, 4096)
                    except OSError:
                        break
                    if not chunk:
                        break
                    output += chunk
                if pending and pending[0][0].encode() in output:
                    os.write(master, pending.pop(0)[1].encode())
                if process.poll() is not None and not ready:
                    break
        finally:
            os.close(master)
            if process.poll() is None:
                process.kill()
            process.wait(timeout=5)
        return output.decode(errors='replace')

    def wrapped(self, launcher, status=0, extra=''):
        code = (SOURCE + LAUNCHERS + self.prelude + extra +
                f'{launcher} "two words" "#{{x}} end;"; print -r -- "$? ${{DISABLE_AUTO_TITLE-unset}}" > '
                f'{shlex.quote(str(self.status))}')
        self.pty(code, STUB_STATUS=str(status))
        return self.status.read_text().split()

    def test_outside_mux_opens_one_tmux_window_and_returns_its_status(self):
        for launcher, program in (('cc', 'claude'), ('gg', 'copilot')):
            for status in (0, 1, 3, 125, 127):
                with self.subTest(launcher=launcher, status=status):
                    self.capture.unlink(missing_ok=True)
                    self.assertEqual(self.wrapped(launcher, status), [str(status), 'unset'])
                    calls = self.calls()
                    self.assertEqual([call[0] for call in calls], ['tmux-store'], calls)
                    name, args, stdin_tty, stdout_tty = calls[0]
                    self.assertTrue(stdin_tty and stdout_tty)
                    self.assertEqual(args[:2], ['open', str(ROOT)])
                    self.assertTrue(args[2].endswith(' two words #{x} end;'))
                    self.assertEqual(args[3:5], ['/bin/zsh', '-lic'])
                    self.assertEqual(args[6:], ['/bin/zsh', launcher, 'two words', '#{x} end;'])

    def test_guards_keep_the_inline_launch(self):
        cases = {
            'opt-out': ('', dict(CC_GG_INLINE='1')),
            'inside tmux': ('', dict(TMUX='/tmp/native,1,0')),
            'inside rmux': ('', dict(RMUX='/tmp/rmux,1,0')),
            'linux': ('OSTYPE=linux-gnu; ', {}),
            'empty tmux marker': ('', dict(TMUX='')),
            'empty rmux marker': ('', dict(RMUX='')),
            'no tmux runtime': ('_mux_tmux_runtimes=(/nonexistent/tmux); ', {}),
            'directory tmux runtime': (f'_mux_tmux_runtimes=({shlex.quote(str(self.home))}); ', {}),
            'no store function': ('unfunction _tmux_store; ', {}),
            'stale helper hash': (f'rm {shlex.quote(str(self.bin / "tmux-store"))}; '
                                  f'hash tmux-store={shlex.quote(str(self.home))}; ', {}),
            'relative zsh': ('hash zsh=zsh; ', {}),
            'stdin redirected': ('exec </dev/null; ', {}),
            'stdout redirected': (f'exec >{shlex.quote(str(self.home / "out"))}; ', {}),
        }
        for label, (extra, env) in cases.items():
            with self.subTest(label):
                self.capture.unlink(missing_ok=True)
                code = (SOURCE + LAUNCHERS + self.prelude + extra +
                        f'cc t; print -r -- $? > {shlex.quote(str(self.status))}')
                self.pty(code, **env)
                self.assertEqual(self.status.read_text().split(), ['0'])
                self.assertIn('claude', [call[0] for call in self.calls()])
                self.assertNotIn(['open'], [call[1][:1] for call in self.calls() if call[0] == 'tmux-store'])

    def test_no_terminal_keeps_the_inline_launch(self):
        self.shell(self.prelude + LAUNCHERS + 'cc t; gg t')
        self.assertEqual([call[0] for call in self.calls()], ['claude', 'copilot'])

    def window(self, launcher, zshrc):
        self.wrapped(launcher)
        args = self.calls()[0][1]
        self.capture.unlink()
        zdot = self.home / 'zdot'
        zdot.mkdir(exist_ok=True)
        (zdot / '.zshrc').write_text(f'PROMPT="READY> "; export PATH={shlex.quote(str(self.bin))}:$PATH\n' + zshrc)
        inner = ' '.join(shlex.quote(arg) for arg in args[3:])
        return self.pty(f'cd {shlex.quote(str(ROOT))} && exec {inner}',
                        send=[('READY> ', 'print -r -- $((17*19))\n'), ('323', 'builtin exit\n')],
                        ZDOTDIR=str(zdot), TMUX='/tmp/native,1,0', TMUX_PANE='%1')

    def test_window_runs_the_launcher_once_in_pane_then_keeps_a_shell(self):
        for launcher, program in (('cc', 'claude'), ('gg', 'copilot')):
            with self.subTest(launcher):
                self.capture.unlink(missing_ok=True)
                rc = ''.join(f'source {ROOT}/config/zsh/{name}\n' for name in
                             ('cc.zsh', 'gg.zsh', 'zz-rmux.zsh', 'zz-tmux.zsh'))
                output = self.window(launcher, rc)
                calls = self.calls()
                self.assertEqual([call[0] for call in calls if call[0] in ('claude', 'copilot')], [program], calls)
                self.assertIn(['tmux-store', ['rename', next(c[1][1] for c in calls if c[0] == 'tmux-store')]],
                              [c[:2] for c in calls])
                self.assertNotIn('open', [c[1][0] for c in calls if c[0] == 'tmux-store'])
                self.assertRegex(output, r'(?m)^323\r?$')

    def test_window_without_launcher_function_reports_and_keeps_a_shell(self):
        output = self.window('cc', '')
        self.assertIn('cc: launcher function not loaded', output)
        self.assertNotIn('claude', [call[0] for call in self.calls()])
        self.assertRegex(output, r'(?m)^323\r?$')


if __name__ == '__main__':
    unittest.main()
