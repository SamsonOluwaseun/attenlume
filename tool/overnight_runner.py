"""Bounded local Codex/Antigravity relay [P1-45]. No push or publication."""
import argparse
import ctypes
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

REPO = Path(__file__).resolve().parents[1]
FLUTTER = Path('C:/dev/flutter/bin/flutter.bat')
DART = Path('C:/dev/flutter/bin/dart.bat')


def atomic_json(path, value):
    tmp = path.with_suffix(path.suffix + '.tmp')
    tmp.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    tmp.replace(path)


def final_text(agent, output, final):
    if agent == 'codex' and final.exists():
        return final.read_text(encoding='utf-8', errors='replace')
    try:
        data = json.loads(output.read_text(encoding='utf-8-sig'))
        return str(data.get('response') or data.get('result') or '')
    except (ValueError, OSError):
        return ''


def quota_error(output, error):
    """Inspect actual error fields/lines, not quoted source/prompt text."""
    messages = []
    if error.exists():
        for line in error.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.lower().startswith(('error:', 'agy_error:')):
                messages.append(line)
    if output.exists():
        text = output.read_text(encoding='utf-8', errors='replace')
        for line in text.splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            if event.get('type') in {'error', 'turn.failed'} or event.get('status') == 'ERROR':
                messages.append(str(event.get('message', event.get('error', event))))
    text = '\n'.join(messages).lower()
    return any(x in text for x in ('quota', 'usage limit', 'rate limit', 'resource_exhausted',
                                  'insufficient credit', 'out of credits', '429'))


def forbidden(paths):
    bad = []
    for relative in paths:
        p = Path(relative)
        if (relative.startswith(('tool/overnight', 'tool/test_overnight'))
                or relative in {'AGENTS.md', 'CLAUDE.md', 'tool/agent-prompt.md'}
                or p.name.startswith('.env') or p.name in {'key.properties', 'local.properties'}
                or p.suffix.lower() in {'.keystore', '.jks', '.p12', '.pem', '.key', '.mobileprovision'}
                or '.git' in p.parts):
            bad.append(relative)
    return bad


def review_pass(text):
    return any(line.strip() == 'NIGHT_REVIEW_PASS' for line in text.splitlines())


class Relay:
    def __init__(self, config, dry_run=False):
        self.config = config
        self.dry_run = dry_run
        self.repo = Path(config['repo']).resolve()
        self.logs = Path(config['logs']).resolve()
        self.logs.mkdir(parents=True, exist_ok=True)
        self.deadline = datetime.fromisoformat(config['deadline'])
        if self.deadline.tzinfo is None:
            raise ValueError('Deadline must include UTC offset')
        self.disabled = set()
        self.command_number = 0
        self.state = {'status': 'preparing', 'pid': os.getpid(), 'started': self.now(),
                      'deadline': config['deadline'], 'checkpoint': config['checkpoint'],
                      'tasks': [], 'events': [], 'commands': [],
                      'platforms': {'Android': 'toolchain/emulator available; build gates required',
                                    'Windows': 'toolchain available; build gates required',
                                    'iOS': 'Mac build/device checks pending; source update packs generated'},
                      'preflight': config.get('preflight', {})}
        self.env = os.environ.copy()
        self.env['PATH'] = 'C:/dev/flutter/bin;' + self.env.get('PATH', '')
        self.env['JAVA_HOME'] = 'C:/Program Files/Microsoft/jdk-17.0.19.10-hotspot'
        self.env['ANDROID_HOME'] = str(Path(self.env['LOCALAPPDATA']) / 'Android/Sdk')
        self.lock = self.repo / 'tool/logs/overnight.lock'

    @staticmethod
    def now():
        return datetime.now(timezone.utc).isoformat()

    def remaining(self):
        return (self.deadline - datetime.now(timezone.utc)).total_seconds()

    def save(self):
        self.state['updated'] = self.now()
        atomic_json(self.logs / 'state.json', self.state)
        lines = ['# Overnight development report', '', f"Status: **{self.state['status']}**",
                 f"Updated: {self.state['updated']}", f"Deadline: {self.state['deadline']}",
                 f"Checkpoint: `{self.config['checkpoint']}`", '',
                 '## Platform status', '']
        lines += [f'- {k}: {v}' for k, v in self.state['platforms'].items()]
        lines += ['', '## Task results', '', '| Task | Agent | Outcome | Branch / commit |',
                  '| --- | --- | --- | --- |']
        for task in self.state['tasks']:
            lines.append(f"| {task['id']} | {task.get('agent', '')} | {task['status']} | "
                         f"{task.get('branch', '')} {task.get('commit', '')} |")
        lines += ['', '## Task blockers', '']
        lines += [f"- {task['id']}: {task['reason']}" for task in self.state['tasks']
                  if task.get('reason')]
        lines += ['', '## Files changed by integrated tasks', '']
        for task in self.state['tasks']:
            if task.get('changes'):
                lines.append(f"### {task['id']} ({task.get('commit', '')})")
                lines.extend(f'- `{path}`' for path in task['changes'])
        lines += ['', '## Readiness checks', '']
        lines.extend(f'- {key}: {value}' for key, value in self.state['preflight'].items())
        lines += ['', '## Events / changes / blockers', '']
        lines += [f'- {x}' for x in self.state['events']]
        lines += ['', '## Check evidence', '']
        lines += [f"- {x['label']}: exit {x['exit_code']}; `{x['stdout']}` / `{x['stderr']}`"
                  for x in self.state['commands']]
        lines += ['', 'Full agent output, per-command logs, change diffs and before/after local-doc',
                  'snapshots are in this session folder. Failed worktrees remain for inspection.',
                  'Only tested and peer-reviewed candidates are merged. No push, store upload,',
                  'publishing, payments or real-device passes are implied. Test logs may describe',
                  'fixtures; do not share logs externally without reviewing them.',
                  'Create STOP in this session folder to stop before the next command.', '']
        content = '\n'.join(lines)
        (self.logs / 'MORNING_REPORT.md').write_text(content, encoding='utf-8')
        report = self.repo / 'docs/reports/OVERNIGHT_LATEST.md'
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(content + f'\nSession folder: {self.logs}\n', encoding='utf-8')

    def log(self, message):
        line = f'{self.now()}  {message}'
        self.state['events'].append(line)
        with (self.repo / 'tool/logs/supervisor.log').open('a', encoding='utf-8') as stream:
            stream.write(line + '\n')
        self.save()

    def command(self, args, cwd, label, minutes=20, check=True, stdin=None):
        if self.remaining() <= 5 or (self.logs / 'STOP').exists():
            raise RuntimeError('Deadline/STOP reached; candidate preserved')
        self.command_number += 1
        slug = f'{self.command_number:03}-{label}'
        out, err = self.logs / f'{slug}.log', self.logs / f'{slug}.err'
        record = {'label': label, 'args': [str(x) for x in args], 'cwd': str(cwd),
                  'stdout': out.name, 'stderr': err.name, 'started': self.now(), 'exit_code': None}
        self.state['commands'].append(record)
        self.save()
        env = self.env.copy()
        for i, directory in enumerate([str(self.repo), str(cwd), 'C:/dev/flutter']):
            env[f'GIT_CONFIG_KEY_{i}'] = 'safe.directory'
            env[f'GIT_CONFIG_VALUE_{i}'] = directory.replace('\\', '/')
        env['GIT_CONFIG_COUNT'] = '3'
        with out.open('wb') as stdout, err.open('wb') as stderr:
            process = subprocess.Popen([str(x) for x in args], cwd=cwd, env=env,
                                       stdin=subprocess.PIPE if stdin else subprocess.DEVNULL,
                                       stdout=stdout, stderr=stderr)
            self.state['active_process'] = {'pid': process.pid, 'label': label, 'started': self.now()}
            self.save()
            if stdin:
                process.stdin.write(stdin.encode('utf-8'))
                process.stdin.close()
            end = time.monotonic() + min(minutes * 60, max(1, self.remaining() - 3))
            heartbeat = time.monotonic() + 60
            while process.poll() is None:
                if time.monotonic() >= end or (self.logs / 'STOP').exists():
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    process.wait(timeout=30)
                    record['timed_out'] = True
                    break
                if time.monotonic() >= heartbeat:
                    self.state['heartbeat'] = self.now()
                    self.save()
                    heartbeat = time.monotonic() + 60
                time.sleep(2)
        record['exit_code'] = process.returncode
        record['finished'] = self.now()
        self.state.pop('active_process', None)
        self.save()
        if check and (record.get('timed_out') or process.returncode != 0):
            raise RuntimeError(f'{label} failed/timed out; see {out.name}')
        return process.returncode, out, err

    def git(self, cwd, *args):
        return subprocess.check_output(['git', '-c', f'safe.directory={Path(cwd).as_posix()}',
                                        '-C', str(cwd), *args], env=self.env).decode('utf-8').strip()

    def snapshot_docs(self, source, target):
        target.mkdir(parents=True, exist_ok=False)
        for name in ['AGENTS.md', 'CLAUDE.md', 'docs', 'assets/brand/reference',
                     'test/docs', 'tool/agent-prompt.md', 'tool/team_check.ps1']:
            src, dst = source / name, target / name
            if src.is_dir():
                shutil.copytree(src, dst, dirs_exist_ok=True)
            elif src.is_file():
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)

    def run_agent(self, agent, prompt, cwd, label, reviewer=False):
        if agent in self.disabled:
            raise RuntimeError(f'{agent} disabled after quota/failure')
        final = self.logs / f'{label}-final.md'
        if agent == 'codex':
            args = [self.config['codex'], 'exec', '--approve-for-me', '--add-dir',
                    'C:/dev/flutter', '--add-dir', str(self.logs), '-C', str(cwd), '--json',
                    '-o', str(final), '-']
            stdin = prompt
        else:
            args = [self.config['antigravity'], '--dangerously-skip-permissions', '--model',
                    'gemini-3.8-flash-high', '--output-format', 'json', '--print-timeout',
                    f"{self.config['run_minutes'] * 60}s", '-p', prompt]
            stdin = None
        code, out, err = self.command(args, cwd, label,
                                      minutes=15 if reviewer else self.config['run_minutes'],
                                      check=False, stdin=stdin)
        if quota_error(out, err):
            self.disabled.add(agent)
            self.log(f'{agent}: actual quota error; disabled for the rest of this session.')
        text = final_text(agent, out, final)
        if agent != 'codex':
            final.write_text(text, encoding='utf-8')
        if code != 0 or not text.strip():
            raise RuntimeError(f'{agent} gave no usable final response/failed; see {out.name}')
        return text

    def validate(self, worktree, prefix):
        checks = [([FLUTTER, 'pub', 'get', '--enforce-lockfile'], 'pub-get'),
                  ([FLUTTER, 'analyze', '--no-pub'], 'analyze'),
                  ([DART, 'format', '--output=none', '--set-exit-if-changed',
                    'lib', 'test', 'tool', 'integration_test'], 'format'),
                  ([FLUTTER, 'test', '--no-pub', '--reporter', 'expanded'], 'tests'),
                  ([DART, 'run', 'tool/licence_audit.dart', '--check'], 'licences'),
                  ([sys.executable, '-m', 'unittest', 'discover', '-s', 'tool/ios_sync/tests'], 'sync-tests'),
                  ([sys.executable, '-m', 'unittest', 'discover', '-s', 'tool', '-p',
                    'test_overnight_runner.py'], 'supervisor-tests'),
                  ([FLUTTER, 'build', 'apk', '--debug', '--no-pub'], 'android-build'),
                  ([FLUTTER, 'build', 'windows', '--debug', '--no-pub'], 'windows-build')]
        for args, name in checks:
            self.command(args, worktree, f'{prefix}-{name}', minutes=25)

    def task(self, spec, agent, attempt):
        slug = f"{attempt:02}-{spec['id']}"
        branch = f"overnight/{self.config['session']}/{slug}"
        worktree = Path('C:/dev/wt') / self.config['session'] / slug
        base = self.git(self.repo, 'rev-parse', 'HEAD')
        result = {'id': spec['id'], 'agent': agent, 'status': 'running', 'branch': branch,
                  'base': base, 'worktree': str(worktree)}
        self.state['tasks'].append(result)
        self.log(f'Starting {slug} with {agent}; peer reviews required before merge.')
        try:
            self.command(['git', 'worktree', 'add', '-b', branch, str(worktree), base],
                         self.repo, f'{slug}-worktree')
            self.snapshot_docs(self.repo, self.logs / f'{slug}-docs-before')
            self.snapshot_docs(self.repo, worktree / '.night-local-docs')
            # Place private/local-only docs in their original locations for the builder.
            shutil.copytree(worktree / '.night-local-docs', worktree, dirs_exist_ok=True)
            # Keep the private staging snapshot out of git add/status.
            exclude = Path(self.git(worktree, 'rev-parse', '--git-path', 'info/exclude'))
            if not exclude.is_absolute():
                exclude = worktree / exclude
            with exclude.open('a', encoding='utf-8') as f:
                f.write('\n.night-local-docs/\n')
            # A worker can commit, but cannot merge: this instruction is explicit
            # in its local operating rules as well as in its task prompt.
            with (worktree / 'AGENTS.md').open('a', encoding='utf-8') as f:
                f.write('\n\n## This overnight worker assignment\n'
                        'You are a builder in this isolated worktree. Do not merge main, '
                        'launch other agents or export iOS packs. The supervisor alone '
                        'runs independent gates, peer review and main integration.\n')
            instructions = (self.repo / 'tool/overnight-policy.md').read_text(encoding='utf-8')
            prompt = instructions + f'\nTASK: {spec["id"]}\n{spec["prompt"]}\n' + \
                     f'\nYour worktree is {worktree}. Base commit {base}. Use ADR-{spec["adr"]}. '
            text = self.run_agent(agent, prompt, worktree, f'{slug}-builder')
            self.snapshot_docs(worktree, self.logs / f'{slug}-docs-after-builder')
            files = self.git(worktree, 'diff', '--name-only', base).splitlines()
            untracked = self.git(worktree, 'ls-files', '--others', '--exclude-standard').splitlines()
            if forbidden(files + untracked):
                raise RuntimeError('Candidate touched protected supervisor/credential paths')
            self.command(['git', 'add', '--all'], worktree, f'{slug}-stage')
            staged = self.git(worktree, 'diff', '--cached', '--name-only')
            if staged:
                self.command(['git', 'commit', '-m', f'feat: overnight {spec["id"]} candidate'],
                             worktree, f'{slug}-commit')
            head = self.git(worktree, 'rev-parse', 'HEAD')
            result['commit'] = head
            if head == base:
                raise RuntimeError('No source commit; task reported without implementation')
            if forbidden(self.git(worktree, 'diff', '--name-only', base, head).splitlines()):
                raise RuntimeError('Committed candidate changed protected paths')
            self.command(['git', 'diff', '--stat', base, head], worktree, f'{slug}-diff-stat')
            self.command(['git', 'diff', '--binary', base, head], worktree, f'{slug}-changes')
            self.validate(worktree, slug)
            candidate = self.git(worktree, 'rev-parse', 'HEAD')
            if self.git(worktree, 'status', '--porcelain'):
                raise RuntimeError('Validation changed tracked/untracked source; needs a new candidate')
            peer = 'codex' if agent == 'antigravity' else 'antigravity'
            review_prompt = (f'Read-only peer review for {spec["id"]}. Do not edit or commit, '
                             f'run other agents, push, publish or access secrets. Inspect git diff '
                             f'{base}...HEAD in {worktree}, AGENTS.md and the applicable requirements. '
                             'Check concrete regressions, privacy, recording safety and accessibility. '
                             'Tests and both Android/Windows debug builds passed outside the agent. '
                             'Return NIGHT_REVIEW_PASS on its own line only if no actionable findings; '
                             'otherwise return NIGHT_REVIEW_CHANGES_REQUIRED and concrete findings. '
                             'No development changes are authorised in this review.')
            review = self.run_agent(peer, review_prompt, worktree, f'{slug}-review', reviewer=True)
            result['review_agent'] = peer
            if not review_pass(review):
                raise RuntimeError('Peer review requested changes; branch preserved for morning review')
            if (self.git(worktree, 'rev-parse', 'HEAD') != candidate
                    or self.git(worktree, 'status', '--porcelain')):
                raise RuntimeError('Review modified candidate; refusing untested merge')
            if (self.git(self.repo, 'rev-parse', 'HEAD') != base
                    or self.git(self.repo, 'status', '--porcelain')):
                raise RuntimeError('Main changed concurrently; refusing merge')
            self.command(['git', 'merge', '--ff-only', branch], self.repo, f'{slug}-merge')
            result['status'] = 'merged'
            # Preserve local decisions/requirements only after tested source is integrated.
            for doc in (worktree / 'docs').glob('*.md'):
                shutil.copy2(doc, self.repo / 'docs' / doc.name)
            report = self.repo / 'docs/reports' / f'{self.config["session"]}-{slug}.md'
            report.write_text(f'# {spec["id"]}\n\n{text}\n\nPeer ({peer}):\n{review}\n', encoding='utf-8')
            self.command([sys.executable, 'tool/ios_sync/export_update.py'],
                         self.repo, f'{slug}-mac-export')
            self.command([sys.executable, 'tool/ios_sync/export_update.py', '--check'],
                         self.repo, f'{slug}-mac-check')
            with (self.repo / 'docs/PROGRESS.md').open('a', encoding='utf-8') as f:
                f.write(f'\n\n{self.now()}: {spec["id"]} merged {candidate}; independent checks, '
                        f'Android/Windows debug builds and {peer} peer review passed. '
                        'iOS native/device validation remains pending Mac. See overnight report.\n')
            result['changes'] = self.git(self.repo, 'diff', '--name-only', base, candidate).splitlines()
            self.state['platforms']['Android'] = f'Debug build passed for {candidate}; emulator available, device behaviour unverified'
            self.state['platforms']['Windows'] = f'Debug build passed for {candidate}; hardware/tray checks require actual evidence'
            self.log(f'{spec["id"]} merged at {candidate}; Mac update exported.')
            return True
        except Exception as error:
            if result['status'] != 'merged':
                result['status'] = 'not merged'
            else:
                result['status'] = 'merged; follow-up blocked'
            result['reason'] = str(error)
            self.log(f'{spec["id"]}: {error}; worktree retained, no reset/deletion.')
            return False
        finally:
            self.save()

    def run(self):
        if self.dry_run:
            self.state['status'] = 'dry-run only'
            self.log('Configuration checked; no agent or development command launched.')
            return
        self.lock.parent.mkdir(parents=True, exist_ok=True)
        with self.lock.open('x', encoding='utf-8') as f:
            f.write(str(os.getpid()))
        try:
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000001)
            self.state['status'] = 'running'
            self.log('Owner-authorised relay started. Claude excluded; no push/publication.')
            if self.git(self.repo, 'branch', '--show-current') != 'main' or self.git(self.repo, 'status', '--porcelain'):
                raise RuntimeError('Main must be clean at launch')
            succeeded = set()
            attempt = 0
            for spec in self.config['tasks']:
                if self.remaining() < 900 or (self.logs / 'STOP').exists():
                    self.log('Less than 15 minutes remain / STOP requested; no new task.')
                    break
                if not set(spec.get('depends_on', [])).issubset(succeeded):
                    self.state['tasks'].append({'id': spec['id'], 'status': 'skipped: dependency not merged'})
                    self.save()
                    continue
                for agent in ['antigravity', 'codex']:
                    if attempt >= self.config['max_runs'] or self.remaining() < 900:
                        break
                    if agent in self.disabled or len(self.disabled) > 0:
                        self.log('An agent is quota-limited: no more tasks requiring unavailable peer review.')
                        break
                    attempt += 1
                    if self.task(spec, agent, attempt):
                        succeeded.add(spec['id'])
                        break
            self.state['status'] = 'finished'
            self.log('Relay finished; inspect task outcomes and retained branches in the morning.')
        except Exception as error:
            self.state['status'] = 'blocked'
            self.log(f'Supervisor stopped safely: {error}')
        finally:
            ctypes.windll.kernel32.SetThreadExecutionState(0x80000000)
            self.lock.unlink(missing_ok=True)
            self.state.pop('active_process', None)
            self.save()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    Relay(json.loads(args.config.read_text(encoding='utf-8-sig')), args.dry_run).run()
