#!/usr/bin/env python3
"""Read-only G3 controls; never installs, builds, or applies upstream projects."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
INTAKE = ROOT / 'Documentation/Evidence/RealProjectQualification-1.0/intake.json'
CASES = {'firebaseui-project': 'firebaseui', 'hammerspoon-workspace': 'hammerspoon'}


class CommandFailure(RuntimeError):
    def __init__(self, label, outcome):
        super().__init__('Command failed: ' + label)
        self.outcome = outcome


def record_failure(summary, error, substitutions):
    summary['error'] = redact(str(error), substitutions)
    summary['status'] = error.outcome if isinstance(error, CommandFailure) else 'failed-safety'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root, exclude=()):
    """Include ignored files, directories, executable bits and symlink targets."""
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        if Path(directory) == root:
            dirs[:] = [d for d in dirs if d != '.git']
        for name in sorted(dirs + files):
            path = Path(directory) / name
            relative = path.relative_to(root).as_posix()
            if relative in exclude:
                continue
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                result[relative] = ['symlink', os.readlink(path)]
            elif stat.S_ISREG(mode):
                result[relative] = ['file', stat.S_IMODE(mode), digest(path)]
            elif stat.S_ISDIR(mode):
                result[relative] = ['directory', stat.S_IMODE(mode)]
            else:
                raise RuntimeError('Unsupported source entry')
    return result


def tree_digest(state):
    return hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()


def command_environment(environment):
    # Upstream attributes must not invoke locally configured smudge/process
    # filters. A new repository has no local config until this runner creates it.
    clean = {key: value for key, value in environment.items() if not key.startswith('GIT_')}
    clean.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_SYSTEM='/dev/null',
                 GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_COUNT='0',
                 GIT_LFS_SKIP_SMUDGE='1', GIT_TERMINAL_PROMPT='0')
    return clean


def check_selection(analysis, plan, case, source):
    project = str(source / case['root'] / case['project'])
    workspace = str(source / case['root'] / case['workspace']) if case['workspace'] else None
    require(analysis['project']['projectPath'] == project, 'Wrong analysis project')
    require(analysis['project'].get('workspacePath') == workspace, 'Wrong analysis workspace')
    require(plan['projectPath'] == project, 'Wrong plan project')
    candidates = [c for c in analysis['candidates'] if c['pod']['isDirect']]
    entries = plan['entries']
    names = [c['pod']['name'] for c in candidates]
    entry_names = [e['podName'] for e in entries]
    require(len(names) == len(set(names)) and len(entry_names) == len(set(entry_names)), 'Duplicate direct identity')
    require(set(names) == set(entry_names), 'Analysis/plan identities differ')
    require(candidates and all(c['classification'] in {'REVIEW', 'BLOCKED', 'UNKNOWN'} for c in candidates)
            and all(e['classification'] in {'REVIEW', 'BLOCKED', 'UNKNOWN'} and e['actions']
                    and all(set(a) == {'manual'} for a in e['actions']) for e in entries), 'Unexpected executable action')
    if case['id'] == 'firebaseui-project':
        local = {'FirebaseUI', 'FirebaseDatabaseUI', 'FirebaseFirestoreUI', 'FirebaseStorageUI'}
        require(set(names) == local | {'Firebase/Auth'}, 'Unexpected FirebaseUI direct set')
        for records, key in [(candidates, 'pod'), (entries, 'podName')]:
            for record in records:
                name = record[key]['name'] if key == 'pod' else record[key]
                require(record['classification'] == ('BLOCKED' if name in local else 'REVIEW'),
                        'FirebaseUI refusal changed')
    else:
        require(len(names) == 10, 'Unexpected Hammerspoon direct count')


def validate_intake(source, case):
    root = source / case['root']
    require(root.resolve().is_relative_to(source.resolve()), 'Escaping selected root')
    for entry in [*case['sourceEvidence'], {'path': 'LICENSE', 'sha256': case['licenseAtPin']['sha256']}]:
        path = source / entry['path']
        require(path.resolve().is_relative_to(source.resolve()) and path.is_file() and not path.is_symlink(),
                'Unsafe intake path')
        require(digest(path) == entry['sha256'], 'Pinned intake bytes changed')


def runtime_contract(binary, output, environment):
    require(environment.get('GITHUB_ACTIONS') == 'true'
            and environment.get('RUNNER_ENVIRONMENT') == 'github-hosted', 'Hosted GitHub runner required')
    source_sha = environment.get('PKGLIFT_ARTIFACT_SOURCE_SHA', '')
    require(re.fullmatch('[0-9a-f]{40}', source_sha) and source_sha == environment.get('GITHUB_SHA'),
            'Source artifact provenance missing or mismatched')
    require(environment.get('PKGLIFT_ARTIFACT_RUN_ID', '').isdigit()
            and environment['PKGLIFT_ARTIFACT_RUN_ID'] == environment.get('GITHUB_RUN_ID')
            and environment.get('PKGLIFT_ARTIFACT_RUN_ATTEMPT', '').isdigit(), 'Run provenance missing')
    require(binary.is_file() and not binary.is_symlink() and os.access(binary, os.X_OK)
            and digest(binary) == environment.get('PKGLIFT_BINARY_SHA256'), 'Verified executable changed')
    temporary = Path(environment['RUNNER_TEMP']).resolve(strict=True)
    require(output.is_absolute() and output.parent.resolve(strict=True) == temporary
            and not output.exists() and not output.is_symlink(), 'Output must be a new direct RUNNER_TEMP child')
    require(not temporary.is_relative_to(ROOT) and not ROOT.is_relative_to(output), 'Output overlaps source checkout')


def redact(text, paths):
    for path in sorted({str(p) for p in paths if str(p)}, key=len, reverse=True):
        text = text.replace(path, '<local>')
    text = re.sub(r'(https?://)[^/@\s]+:[^/@\s]+@', r'\1<redacted>@', text)
    text = re.sub(r'(https?://[^\s?#]+)[?#][^\s]+', r'\1?<redacted>', text)
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=CASES, required=True)
    parser.add_argument('--pkglift', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    runtime_contract(args.pkglift, args.output, os.environ)
    binary = args.pkglift.resolve(strict=True)
    case = next(c for c in json.loads(INTAKE.read_text())['cases'] if c['id'] == args.case)
    output = args.output
    output.mkdir()
    raw = output / 'raw'
    report = output / 'report'
    raw.mkdir()
    report.mkdir()
    source = output / 'source'
    summary = {'schemaVersion': 1, 'case': args.case, 'status': 'blocked-input',
               'upstreamCommit': case['commit'], 'repository': case['repository'], 'license': case['licenseAtPin']['spdx'],
               'pkgLiftSourceCommit': os.environ['PKGLIFT_ARTIFACT_SOURCE_SHA'],
               'artifactRunID': os.environ['PKGLIFT_ARTIFACT_RUN_ID'],
               'artifactProducerAttempt': os.environ['PKGLIFT_ARTIFACT_RUN_ATTEMPT'],
               'binarySHA256': digest(binary), 'runnerSHA256': digest(Path(__file__)), 'intakeSHA256': digest(INTAKE),
               'sourceRedistributed': False, 'apply': 'not-run', 'dependencyInstall': 'not-run', 'build': 'not-run',
               'commands': []}
    substitutions = [output, ROOT, Path.home(), Path(os.environ['RUNNER_TEMP']), binary.parent]

    def run(label, command, cwd=ROOT, seconds=180, failure_outcome='blocked-input'):
        command = [str(v) for v in command]
        stdout, stderr = raw / (label + '.out'), raw / (label + '.err')
        wrapper = [sys.executable, str(ROOT / 'Scripts/run-with-timeout.py'), '--seconds', str(seconds),
                   '--cwd', str(cwd), '--stdout', str(stdout), '--stderr', str(stderr), '--']
        started = time.monotonic()
        result = subprocess.run(wrapper + command, check=False, env=command_environment(os.environ))
        summary['commands'].append({'label': label, 'argv': [redact(v, substitutions) for v in command],
                                    'exitCode': result.returncode, 'durationSeconds': round(time.monotonic()-started, 3)})
        if result.returncode != 0 and stderr.is_file():
            summary['lastCommandFailure'] = {'label': label, 'stderrSHA256': digest(stderr),
                                            'stderrTail': redact(stderr.read_text(errors='replace')[-2048:], substitutions)}
        if result.returncode != 0:
            raise CommandFailure(label, failure_outcome)
        return stdout

    def git_clean():
        require(run('git-head', ['git', 'rev-parse', 'HEAD'], source).read_text().strip() == case['commit'],
                'Source HEAD changed')
        require(run('git-status', ['git', 'status', '--porcelain', '--untracked-files=all'], source).read_text() == '',
                'Source worktree is dirty')
        return run('git-index', ['git', 'ls-files', '--stage', '-z'], source).read_bytes()

    try:
        manifest = dict(line.split('=', 1) for line in (binary.parent / 'manifest.txt').read_text().splitlines())
        require(re.fullmatch('[0-9a-f]{64}', manifest.get('bundle_sha256', '')), 'Missing registry bundle identity')
        summary['registryBundleSHA256'] = manifest['bundle_sha256']
        environment = json.loads(run('environment', [sys.executable, ROOT / 'Scripts/capture-environment.py']).read_text())
        require(environment['captureStatus'] == 'complete', 'Incomplete environment')
        require(environment['system']['machine'] == 'arm64'
                and environment['system']['macOS']['version'].startswith('15.')
                and environment['commands']['xcodebuildVersion']['versionOutput'][0] == 'Xcode 16.4',
                'Unexpected qualification environment')
        (report / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
        require(run('own-head', ['git', 'rev-parse', 'HEAD']).read_text().strip() == os.environ['GITHUB_SHA'], 'Source checkout mismatch')
        version = run('version', [binary, 'version']).read_text().strip()
        summary['pkgLiftVersion'] = version
        summary['rubyVersion'] = run('ruby-version', ['ruby', '--version']).read_text().strip()
        run('init', ['git', '-c', 'init.templateDir=', 'init', '-q', source])
        run('remote', ['git', 'remote', 'add', 'origin', 'https://github.com/' + case['repository'] + '.git'], source)
        run('fetch', ['git', '-c', 'credential.helper=', 'fetch', '--depth', '1', '--filter=blob:none', '--no-tags',
                      'origin', case['commit']], source, 300)
        # The selected nested Firebase sample needs no local dependency resolution.
        if case['root'] != '.':
            run('sparse-init', ['git', 'sparse-checkout', 'init', '--cone'], source)
            run('sparse-set', ['git', 'sparse-checkout', 'set', '--', case['root']], source)
        run('checkout', ['git', '-c', 'credential.helper=', '-c', 'core.hooksPath=/dev/null',
                         'checkout', '-q', '--detach', 'FETCH_HEAD'], source, 300)
        require(run('head', ['git', 'rev-parse', 'HEAD'], source).read_text().strip() == case['commit'], 'Wrong upstream commit')
        validate_intake(source, case)
        selected = source / case['root']
        require(not (selected / '.pkglift').exists(), 'Pre-existing plan state')
        run('validate-write-root', ['bash', ROOT / 'Scripts/validate-pinned-pilot-write-root.sh', selected])
        plan_relative = (Path(case['root']) / '.pkglift/plan.json').as_posix()
        with (source / '.git/info/exclude').open('a') as handle:
            handle.write('\n/' + plan_relative + '\n')
        before_index = git_clean()
        original = snapshot(source)
        common = ['--path', selected, '--project', case['project'], '--no-color']
        if case['workspace']:
            common += ['--workspace', case['workspace']]
        analysis_path = run('analysis', [binary, 'analyze', *common, '--json'])
        portable_analysis = run('portable-analysis', [binary, 'analyze', *common, '--portable-json'])
        require(snapshot(source) == original, 'Analysis mutated source')
        portable_plan = run('portable-plan', [binary, 'plan', *common, '--portable-json'])
        plan_path = selected / '.pkglift/plan.json'
        analysis, plan = json.loads(analysis_path.read_text()), json.loads(plan_path.read_text())
        check_selection(analysis, plan, case, source)
        require(snapshot(source, (plan_relative, str(Path(plan_relative).parent))) == original,
                'Planning changed files beyond its new plan')
        require(git_clean() == before_index, 'Planning changed Git index')
        before_dry = snapshot(source)
        dry = run('dry-run', [binary, 'migrate', *common])
        require(snapshot(source) == before_dry and git_clean() == before_index, 'Dry run mutated source/index')
        os.environ['PILOT_DRY_RUN_CLEAN'] = 'true'
        os.environ['PILOT_REPOSITORY'] = case['repository']
        os.environ['PILOT_COMMIT'] = case['commit']
        os.environ['PILOT_ISSUE'] = 'G3'
        os.environ['PILOT_ROOT'] = case['root']
        os.environ['PILOT_PROJECT'] = case['project']
        os.environ['PILOT_WORKSPACE'] = case['workspace'] or '-'
        os.environ['PILOT_LICENSE'] = case['licenseAtPin']['spdx']
        run('validate-refusal', ['ruby', ROOT / 'Scripts/validate-pinned-pilot.rb', CASES[args.case], analysis_path,
                               plan_path, dry, selected, report, portable_analysis, portable_plan],
            failure_outcome='failed-safety')
        summary.update(status='passed-refusal', sourceUnchanged=True, indexUnchanged=True,
                       originalTreeSHA256=tree_digest(original), dryRunTreeSHA256=tree_digest(before_dry),
                       project=case['project'], workspace=case['workspace'], exactAutoSet=[])
    except Exception as error:
        record_failure(summary, error, substitutions)
        raise
    finally:
        # Only structured/portable reports reach the upload directory. Raw command
        # output and upstream source remain in job-local sibling directories.
        (report / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    main()
