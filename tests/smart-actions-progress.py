#!/usr/bin/env python3
"""Launcher lifecycle tests, with fake desktop tools and no graphical session."""
import ctypes
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
# Reap detached fake KDialog helpers too (the launcher cannot wait nonchildren).
ctypes.CDLL(None).prctl(36, 1, 0, 0, 0)
FAKE = r'''#!/usr/bin/python3
import json, os, signal, subprocess, sys
from pathlib import Path
root = Path(os.environ['FIXTURE'])
mode = os.environ['MODE']
name = Path(sys.argv[0]).name
args = sys.argv[1:]
def log(*event):
    with (root / 'events').open('a') as f: f.write(json.dumps(event) + '\n')
def ack():
    if not (root / 'acked').exists():
        (root / 'acked').touch()
        with (root / 'ack').open('w') as f: f.write('go\n')
if args == ['helper']:
    signal.pause()
elif name == 'kdialog':
    if '--progressbar' in args:
        child = subprocess.Popen([sys.executable, __file__, 'helper'])
        (root / 'helper').write_text(str(child.pid))
        log('open', args[-1])
        print('org.kde.kdialog-' + str(child.pid) + ' /ProgressDialog', flush=True)
    else: log('error', args[-1])
elif name.startswith('qdbus'):
    assert args[0] == 'org.kde.kdialog-' + (root / 'helper').read_text()
    assert args[1] == '/ProgressDialog'
    command = args[2:]
    log(*command)
    if command == ['close']:
        if os.environ.get('BROKEN_CLOSE'): sys.exit(1)
        os.kill(int((root / 'helper').read_text()), signal.SIGTERM)
    elif command == ['wasCancelled']:
        if mode == 'cancel': print('true')
        else:
            print('false')
            if mode in ('busy', 'failure'): ack()
    elif command == ['Set', '', 'value', '25']: ack()
elif name == 'zenity':
    if '--error' in args: log('error', args[-1])
    else:
        (root / 'zenity-pid').write_text(str(os.getpid()))
        log('zenity-open', *args)
        if mode == 'cancel': sys.exit(1)
        if mode in ('busy', 'failure'): ack()
        for line in sys.stdin:
            log('zenity-line', line.strip())
            if '25%' in line: ack()
        log('zenity-eof')
elif name == 'smart-actions':
    log('invoke', *args)
    if mode == 'cancel':
        child = subprocess.Popen([sys.executable, __file__, 'helper'])
        (root / 'converter-child').write_text(str(child.pid))
        signal.pause()
    if mode == 'progress': print('SMART_ACTIONS_PROGRESS=25', flush=True)
    else: print('Executing engine: ffmpeg', flush=True)
    if os.environ['FRONTEND'] != 'none':
        with (root / 'ack').open() as f: f.readline()
    print('converter diagnostic', file=sys.stderr, flush=True)
    log('converter-exit')
    sys.exit(7 if mode == 'failure' else 0)
'''


class Lifecycle(unittest.TestCase):
    def run_case(self, frontend, mode, dbus='qdbus6', broken_close=False):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            binary = base / 'bin'
            binary.mkdir()
            launcher = binary / 'smart-actions-launcher'
            shutil.copy2(ROOT / 'scripts/smart-actions-launcher', launcher)
            for name in ['smart-actions'] + ({'kdialog': ['kdialog', dbus], 'zenity': ['zenity'], 'none': []}[frontend]):
                path = binary / name
                path.write_text(FAKE)
                path.chmod(0o755)
            for name in ['dirname', 'readlink', 'mktemp', 'mkfifo', 'rm', 'cat']:
                (binary / name).symlink_to(shutil.which(name))
            os.mkfifo(base / 'ack')
            env = dict(os.environ, PATH=str(binary), FIXTURE=temp, MODE=mode, FRONTEND=frontend, TMPDIR=temp)
            if broken_close: env['BROKEN_CLOSE'] = '1'
            try:
                result = subprocess.run(['/bin/bash', str(launcher), 'file with spaces', 'action'], env=env, capture_output=True, text=True, timeout=10)
                events = [json.loads(line) for line in (base / 'events').read_text().splitlines()]
                self.assertEqual(result.returncode, {'failure': 7, 'cancel': 130}.get(mode, 0), result.stderr)
                self.assertIn(['invoke', 'invoke', 'action', 'file with spaces'], events)
                if frontend == 'kdialog':
                    self.assertIn(['open', '0'], events)
                    self.assertEqual(events.count(['close']), 1)
                    if mode == 'progress':
                        self.assertIn(['Set', '', 'value', '25'], events)
                    if mode not in ('failure', 'cancel'):
                        self.assertIn(['Set', '', 'value', '100'], events)
                        self.assertLess(events.index(['converter-exit']), events.index(['Set', '', 'value', '100']))
                    else:
                        self.assertNotIn(['Set', '', 'value', '100'], events)
                if mode == 'failure':
                    self.assertIn('converter diagnostic', result.stderr)
                    if frontend != 'none': self.assertTrue(any(e[0] == 'error' and 'converter diagnostic' in e[1] for e in events))
                if frontend == 'zenity' and mode == 'progress':
                    self.assertIn(['zenity-line', '# Processing file... 25%'], events)
                if frontend == 'zenity' and mode not in ('failure', 'cancel'):
                    self.assertIn(['zenity-line', '100'], events)
                    self.assertIn(['zenity-eof'], events)
                self.assertFalse(list(base.glob('tmp.*')), 'temporary pipes/logs leaked')
                if (base / 'zenity-pid').exists():
                    self.assertFalse(Path('/proc', (base / 'zenity-pid').read_text()).exists())
            finally:
                for helper in [base / 'helper', base / 'converter-child']:
                    if not helper.exists(): continue
                    pid = int(helper.read_text())
                    # A helper still running after launcher return is a leak.
                    waited, _ = os.waitpid(pid, os.WNOHANG)
                    if not waited:
                        os.kill(pid, signal.SIGKILL)
                        os.waitpid(pid, 0)
                        self.fail('orphaned progress helper')

    def test_lifecycle(self):
        for frontend in ['kdialog', 'zenity', 'none']:
            for mode in ['progress', 'busy', 'failure']:
                with self.subTest(frontend=frontend, mode=mode): self.run_case(frontend, mode)

    def test_kde5_qdbus(self):
        self.run_case('kdialog', 'progress', 'qdbus')

    def test_cancel(self):
        self.run_case('kdialog', 'cancel')
        self.run_case('zenity', 'cancel')

    def test_close_failure_stops_only_own_helper(self):
        self.run_case('kdialog', 'progress', broken_close=True)


if __name__ == '__main__':
    import signal
    unittest.main()
