#!/usr/bin/env python3
"""Exercise G4 recovery on new disposable copies of the PartialSwift fixture.

Signals use the existing XCTest-only MigrateCommand harness. No production
fault hook, classification override, cleanup, or upstream project is involved.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import time

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent


def load_script(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / 'Scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pilot = load_script('run-partial-migration-pilot')
require = pilot.require
CASE = pilot.CASES['PartialSwift']
TARGET = CASE['target']
PROJECT = TARGET + '.xcodeproj'
WORKSPACE = TARGET + '.xcworkspace'
STAGES = ('podfileWritten', 'packageAdded:0', 'productLinked:0')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root, exclude_state=False):
    """Inventory bytes, mode and internal relative symlinks; never follow links."""
    require(root.is_dir() and not root.is_symlink(), 'Snapshot root must be a real directory')
    result = {}
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if exclude_state and relative.parts[0] == '.pkglift':
            continue
        mode = path.lstat().st_mode
        name = relative.as_posix()
        if stat.S_ISLNK(mode):
            target = os.readlink(path)
            require(not os.path.isabs(target) and path.resolve(strict=True).is_relative_to(root.resolve()),
                    'Escaping or absolute snapshot symlink')
            result[name] = ['symlink', target]
        elif stat.S_ISREG(mode):
            result[name] = ['file', stat.S_IMODE(mode), digest(path)]
        elif stat.S_ISDIR(mode):
            result[name] = ['directory', stat.S_IMODE(mode)]
        else:
            raise RuntimeError('Special file in snapshot')
    return result


def source_inputs():
    paths = [ROOT / 'Package.swift', ROOT / 'Package.resolved']
    for folder in ('Sources', 'Tests', 'Registry'):
        paths.extend(p for p in (ROOT / folder).rglob('*') if p.is_file()
                     and (folder != 'Tests' or p.suffix in ('.swift', '.c', '.h')))
    return {str(p.relative_to(ROOT)): digest(p) for p in sorted(paths)}


def state_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def restore_baseline(baseline, expected, consumer):
    """Preserve incident, verify a fresh staging copy, then publish by rename."""
    require(snapshot(baseline) == expected, 'Independent baseline changed')
    require(consumer.name == 'consumer' and consumer.is_dir() and not consumer.is_symlink(),
            'Unexpected recovery consumer')
    incident = consumer.parent / 'incident'
    staging = consumer.parent / 'restoring'
    require(not os.path.lexists(incident) and not os.path.lexists(staging), 'Recovery destination already exists')
    prior = snapshot(consumer)
    consumer.rename(incident)
    shutil.copytree(baseline, staging, symlinks=True)
    require(snapshot(staging) == expected, 'Staged recovery differs from verified baseline')
    require(not os.path.lexists(consumer), 'Consumer path reappeared during recovery')
    staging.rename(consumer)
    require(snapshot(consumer) == expected, 'Restored baseline mismatch')
    require(snapshot(incident) == prior, 'Incident evidence changed during recovery')
    return state_hash(prior)


def check_internal_backup(consumer, baseline):
    backup = consumer / '.pkglift/backup'
    require((backup / 'Podfile').read_bytes() == (baseline / 'Podfile').read_bytes(), 'Internal Podfile backup mismatch')
    require(snapshot(backup / PROJECT) == snapshot(baseline / PROJECT), 'Internal project backup mismatch')


def check_completed(consumer, outcome="applied"):
    require(not os.path.lexists(consumer / '.pkglift/migration-in-progress'), 'Unexpected active marker')
    receipt = consumer / '.pkglift/backup/.pkglift-completed.json'
    require(receipt.is_file() and not receipt.is_symlink(), 'Completed backup receipt missing')
    record = json.loads(receipt.read_text())
    require(record.get('schemaVersion') == 1 and record.get('outcome') == outcome
            and record.get('backupDirectory') == str((consumer / '.pkglift/backup').resolve())
            and sorted(record.get('files', [])) == sorted(str((consumer / p).resolve()) for p in ('Podfile', PROJECT)),
            'Completed backup receipt does not match this consumer and outcome')
    return digest(receipt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New absolute task-owned directory outside source')
    parser.add_argument('--pkglift', type=Path, required=True)
    parser.add_argument('--signal-test-bundle', type=Path, required=True)
    parser.add_argument('--build-receipt', type=Path, required=True, help='Same-invocation build receipt binding source and both artifacts')
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    require(args.output.is_absolute(), 'Output must be absolute')
    output = args.output.parent.resolve(strict=True) / args.output.name
    require(output != ROOT and ROOT not in output.parents, 'Output must be outside the source checkout')
    require(not os.path.lexists(output), 'Output must not exist')
    binary = args.pkglift.resolve(strict=True)
    bundle = args.signal_test_bundle.resolve(strict=True)
    require(binary.is_file() and bundle.is_dir() and bundle.name == 'PkgLiftCLITests.xctest', 'Invalid build inputs')
    build_receipt = json.loads(args.build_receipt.read_text())
    require(binary.parent == bundle.parent and build_receipt.get('exitCode') == 0
            and build_receipt.get('sourceInputs') == source_inputs()
            and build_receipt.get('binarySHA256') == digest(binary)
            and build_receipt.get('signalTestBundleSHA256') == state_hash(snapshot(bundle))
            and build_receipt.get('buildsBothArtifacts') is True, 'Build provenance mismatch')
    fixture = ROOT / 'Fixtures/PartialSwift'
    fixture_state = snapshot(fixture)
    require('.pkglift' not in fixture_state, 'Fixture contains recovery state')
    output.mkdir()
    reports = output / 'report'
    reports.mkdir()
    # Route configurable build/package/temp roots without changing the user's home.
    child_environment = dict(os.environ)
    locations = {'TMPDIR': 'temporary', 'CP_HOME_DIR': 'cocoapods-home', 'CP_CACHE_DIR': 'cocoapods-cache',
                 'CLANG_MODULE_CACHE_PATH': 'compiler-cache', 'SWIFT_MODULECACHE_PATH': 'compiler-cache',
                 'SWIFT_MODULE_CACHE_PATH': 'compiler-cache'}
    for variable, relative in locations.items():
        directory = output / relative
        directory.mkdir(exist_ok=True)
        child_environment[variable] = str(directory)
    child_environment.update(PYTHONDONTWRITEBYTECODE='1', COCOAPODS_DISABLE_STATS='true')
    real_xcodebuild = shutil.which('xcodebuild')
    require(real_xcodebuild is not None, 'xcodebuild unavailable')
    shims = output / 'bin'
    shims.mkdir()
    extra = ['-clonedSourcePackagesDirPath', str(output / 'package-sources'),
             '-packageCachePath', str(output / 'package-cache')]
    wrapper = shims / 'xcodebuild'
    wrapper.write_text('#!' + sys.executable + '\nimport os,sys\nargs=sys.argv[1:]\n'
        + "if 'build' in args or '-resolvePackageDependencies' in args:\n"
        + '    args += ' + repr(extra) + '\n'
        + "    if '-jobs' not in args: args += " + repr(['-jobs', str(args.jobs)]) + '\n'
        + "    for value in ['CODE_SIGNING_ALLOWED=NO', 'IPHONEOS_DEPLOYMENT_TARGET=15.0', 'ARCHS=arm64']:\n"
        + '        if value not in args: args.append(value)\n'
        + 'os.execv(' + repr(real_xcodebuild) + ', [' + repr(real_xcodebuild) + ', *args])\n')
    wrapper.chmod(0o755)
    child_environment['PATH'] = str(shims) + os.pathsep + child_environment['PATH']
    summary = {'schemaVersion': 1, 'status': 'incomplete', 'repositoryOwned': True,
               'fixture': 'PartialSwift', 'sourceCommit': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
               'workingTreeHasChanges': bool(subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain'])),
               'binarySHA256': digest(binary), 'signalTestBundleSHA256': state_hash(snapshot(bundle)),
               'buildReceiptSHA256': digest(args.build_receipt),
               'runnerSHA256': digest(Path(__file__)), 'fixtureSHA256': state_hash(fixture_state),
               'helperSourceSHA256': digest(ROOT / 'Tests/PkgLiftCLITests/MigrateInterruptionTests.swift'),
               'signalExecution': 'XCTest-only harness calling real MigrateCommand; not installed-CLI signal qualification',
               'scenarios': [], 'commands': [], 'releaseAcceptance': False, 'hostedAcceptance': False,
               'buildSettings': {'configuration': 'Debug', 'sdk': 'iphonesimulator', 'architecture': 'arm64', 'deployment': '15.0'}}

    summary['configuredStorageRoots'] = locations | {'swiftPMPackageSources': 'package-sources', 'swiftPMPackageCache': 'package-cache'}
    summary['systemTemporaryBoundary'] = 'Foundation-managed per-user temporary storage is selected by macOS and was observed to ignore TMPDIR; it is not relocated by this harness.'

    def run(label, command, cwd=None, expected=0, environment=None, seconds=600):
        require(not (reports / (label + '.stdout.log')).exists(), 'Duplicate command label')
        stdout = reports / (label + '.stdout.log')
        stderr = reports / (label + '.stderr.log')
        print('Recovery: ' + label, flush=True)
        started = time.monotonic()
        with stdout.open('wb') as out, stderr.open('wb') as err:
            process = subprocess.Popen([str(v) for v in command], cwd=cwd, env=child_environment if environment is None else environment,
                                       stdout=out, stderr=err, start_new_session=True)
            try:
                code = process.wait(timeout=seconds)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise RuntimeError('Recovery command timed out: ' + label)
        summary['commands'].append({'label': label, 'exitCode': code, 'expectedExitCode': expected,
                                    'seconds': round(time.monotonic() - started, 2),
                                    'stdoutSHA256': digest(stdout), 'stderrSHA256': digest(stderr)})
        require(code == expected, 'Unexpected command outcome: ' + label)
        return stdout, stderr

    def common(consumer):
        return ['--path', consumer, '--project', PROJECT, '--no-color']

    def plan(consumer, label):
        analysis, _ = run(label + '-analyze', [binary, 'analyze', *common(consumer), '--json'])
        run(label + '-plan', [binary, 'plan', *common(consumer), '--json'])
        pilot.check_plan(json.loads(analysis.read_text()), json.loads((consumer / '.pkglift/plan.json').read_text()), CASE)
        before = snapshot(consumer)
        run(label + '-dry-run', [binary, 'migrate', *common(consumer)])
        require(snapshot(consumer) == before, 'Dry run changed recovery consumer')

    def build(consumer, label):
        run(label, ['xcodebuild', '-workspace', consumer / WORKSPACE, '-scheme', TARGET,
                    '-configuration', 'Debug', '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
                    '-derivedDataPath', output / (label + '-derived'), '-jobs', args.jobs,
                    'CODE_SIGNING_ALLOWED=NO', 'IPHONEOS_DEPLOYMENT_TARGET=15.0', 'ARCHS=arm64', 'build'], seconds=1200)

    def verify(consumer, label, expected):
        stdout, _ = run(label, [binary, 'verify', *common(consumer), '--workspace', WORKSPACE, '--build',
                               '--scheme', TARGET, '--configuration', 'Debug', '--sdk', 'iphonesimulator',
                               '--destination', 'generic/platform=iOS Simulator',
                               '--derived-data-path', output / (label + '-derived'), '--json'], expected=expected, seconds=1200)
        report = json.loads(stdout.read_text())
        require(report['passed'] == (expected == 0), 'Verification result differs from exit status')
        checks = {c['name']: c['passed'] for c in report['checks']}
        require(checks.get('build') == (expected == 0), 'Expected build check missing or different')
        require(all(passed for name, passed in checks.items() if name != 'build'), 'Failure was not isolated to build')
        return report

    try:
        environment = load_script('capture-environment').capture_environment()
        require(environment['system']['macOS']['status'] == 'passed'
                and all(v['status'] == 'passed' for v in environment['commands'].values()), 'Environment unavailable')
        (reports / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
        xctest = Path(subprocess.check_output(['xcrun', '--find', 'xctest'], text=True).strip())
        summary['xctestSHA256'] = digest(xctest)
        baseline = output / 'baseline'
        shutil.copytree(fixture, baseline, symlinks=True)
        run('baseline-install', ['pod', 'install', '--deployment'], baseline)
        pilot.check_lock((baseline / 'Podfile.lock').read_text(), [CASE['migrate'], CASE['retain']])
        build(baseline, 'baseline-build')
        baseline_state = snapshot(baseline)
        summary['baselineSHA256'] = state_hash(baseline_state)
        (reports / 'baseline-inventory.json').write_text(json.dumps(baseline_state, indent=2) + '\n')

        def new_consumer(name):
            directory = output / name
            directory.mkdir()
            consumer = directory / 'consumer'
            shutil.copytree(baseline, consumer, symlinks=True)
            require(snapshot(consumer) == baseline_state, 'Scenario does not match baseline')
            plan(consumer, name)
            return consumer

        def recover(consumer, name, row):
            row['incidentSHA256'] = restore_baseline(baseline, baseline_state, consumer)
            build(consumer, name + '-restored-build')
            require(snapshot(consumer) == baseline_state, 'Restored build changed baseline bytes')
            plan(consumer, name + '-restored')
            require(snapshot(consumer, exclude_state=True) == baseline_state, 'Replanning changed baseline')
            require(state_hash(snapshot(consumer.parent / 'incident')) == row['incidentSHA256'], 'Incident evidence changed')
            row.update(restoredBytesMatch=True, restoredBuild=True, regeneratedPlan=True, dryRunUnchanged=True,
                       incidentPreserved=True, status='passed')

        for signum in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
            for stage in STAGES:
                name = signum.name.lower() + '-' + stage.replace(':', '-')
                consumer = new_consumer(name)
                signal_environment = dict(child_environment, PKGLIFT_TEST_INTERRUPT_ROOT=str(consumer),
                                         PKGLIFT_TEST_INTERRUPT_PROJECT=str(consumer / PROJECT),
                                         PKGLIFT_TEST_INTERRUPT_STAGE=stage, PKGLIFT_TEST_INTERRUPT_SIGNAL=str(int(signum)))
                expected = -int(signum) if signum == signal.SIGKILL else 128 + int(signum)
                _, err = run(name + '-interrupt', [xctest, '-XCTest',
                    'PkgLiftCLITests.MigrateInterruptionTests/testChildProcessRaisesConfiguredSignal', bundle],
                    expected=expected, environment=signal_environment, seconds=30)
                require('reached checkpoint: ' + stage in err.read_text(), 'Requested checkpoint was not observed')
                check_internal_backup(consumer, baseline)
                row = {'name': name, 'signal': signum.name, 'checkpoint': stage, 'checkpointObserved': True,
                       'exitCode': expected, 'internalBackupMatches': True}
                if signum == signal.SIGKILL:
                    marker = consumer / '.pkglift/migration-in-progress'
                    require(marker.is_file() and not marker.is_symlink(), 'SIGKILL marker missing')
                    require(snapshot(consumer, exclude_state=True) != baseline_state, 'SIGKILL did not interrupt changed files')
                    before = snapshot(consumer)
                    out, err = run(name + '-refused-reapply', [binary, 'migrate', *common(consumer), '--apply', '--allow-dirty'], expected=1)
                    require('incomplete' in (out.read_text() + err.read_text()).lower(), 'Reapply failed for a different reason')
                    require(snapshot(consumer) == before, 'Refused reapply changed evidence')
                    row.update(activeMarker=True, reapplyRefused=True, refusalUnchanged=True)
                else:
                    row['terminalReceiptSHA256'] = check_completed(consumer, 'rolledBack')
                    require(snapshot(consumer, exclude_state=True) == baseline_state, 'Handled signal did not roll back all bytes')
                    row.update(automaticRollback=True)
                summary['scenarios'].append(row)
                recover(consumer, name, row)

        for failure in ('pod-deployment-lock-mismatch', 'verify-injected-compiler-error'):
            consumer = new_consumer(failure)
            run(failure + '-apply', [binary, 'migrate', *common(consumer), '--apply'])
            check_internal_backup(consumer, baseline)
            receipt = check_completed(consumer)
            migrated_podfile = (consumer / 'Podfile').read_bytes()
            pilot.shared.verify_migrated_podfile((baseline / 'Podfile').read_bytes(), migrated_podfile,
                                                CASE['migrate'], pilot.VERSIONS[CASE['migrate']])
            row = {'name': failure, 'applyCompleted': True, 'terminalReceiptSHA256': receipt,
                   'internalBackupMatches': True, 'faultOrigin': 'deliberate post-apply qualification fault'}
            if failure == 'pod-deployment-lock-mismatch':
                before = snapshot(consumer)
                out, err = run(failure + '-failure', ['pod', 'install', '--deployment'], cwd=consumer, expected=1)
                require('deployment' in (out.read_text() + err.read_text()).lower(), 'Unexpected CocoaPods failure')
                row['fault'] = 'Deployment install refuses the intentionally stale pre-migration lockfile'
            else:
                run(failure + '-refresh', ['pod', 'install', '--clean-install'], cwd=consumer)
                pilot.check_lock((consumer / 'Podfile.lock').read_text(), [CASE['retain']])
                require((consumer / 'Podfile.lock').read_bytes() == (consumer / 'Pods/Manifest.lock').read_bytes(), 'Retained manifest mismatch')
                verify(consumer, failure + '-positive-control', 0)
                pilot.check_resolved(consumer, [CASE['migrate']])
                source = consumer / 'App/Consumer.swift'
                source.write_bytes(source.read_bytes() + b'\n#error("PKGLIFT_RECOVERY_DRILL_INTENTIONAL")\n')
                before = snapshot(consumer)
                failed = verify(consumer, failure + '-failure', 1)
                require(source.read_bytes().endswith(b'#error("PKGLIFT_RECOVERY_DRILL_INTENTIONAL")\n'), 'Injected fault changed during verification')
                row['fault'] = 'App/Consumer.swift gets an explicit #error after a successful migrated verify --build'
                row['migratedPositiveControl'] = True
            after = snapshot(consumer)
            row.update(beforeFailureSHA256=state_hash(before), afterFailureSHA256=state_hash(after),
                       changedByExternalCommand=sorted(key for key in set(before) | set(after) if before.get(key) != after.get(key)))
            require(check_completed(consumer) == receipt, 'External command changed terminal migration state')
            require((consumer / 'Podfile').read_bytes() == migrated_podfile, 'Unexpected post-apply rollback')
            row['noAutomaticRollback'] = True
            summary['scenarios'].append(row)
            recover(consumer, failure, row)
        require(snapshot(fixture) == fixture_state, 'Repository fixture changed')
        require(snapshot(baseline) == baseline_state, 'Independent baseline changed')
        summary.update(status='passed', scenarioCount=len(summary['scenarios']), repositoryFixtureUnchanged=True,
                       independentBaselineUnchanged=True, allScenariosPassed=True, fullBaselineRestorePassed=True,
                       limitations=['Repository-owned PartialSwift on one local toolchain; not universal power-loss recovery.',
                                    'Signals are executed through the XCTest-only harness, while post-apply commands use the CLI.',
                                    'All failure trees and full-baseline copies are retained; no cleanup occurred.'])
    finally:
        (reports / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print('Recovery result: ' + summary['status'], flush=True)


if __name__ == '__main__':
    main()
