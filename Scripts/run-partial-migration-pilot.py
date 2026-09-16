#!/usr/bin/env python3
"""Prove partial migration on disposable repository-owned iOS consumers."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

# Helper imports must not dirty the checkout or its qualification metadata.
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('registry_pilot', ROOT / 'Scripts/run-registry-consumer-pilot.py')
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)
require = shared.require
CASES = {
    'PartialSwift': {'target': 'SwiftKeychainAccess', 'migrate': 'KeychainAccess', 'retain': 'SDWebImage',
                     'languages': ['swift']},
    'PartialMixed': {'target': 'PkgLiftMixedFixture', 'migrate': 'SDWebImage', 'retain': 'KeychainAccess',
                     'languages': ['objectiveC', 'swift']},
}
VERSIONS = {'KeychainAccess': '4.2.2', 'SDWebImage': '5.18.1'}
REVISIONS = {'KeychainAccess': '84e546727d66f1adc5439debad16270d0fdd04e7',
             'SDWebImage': '6e844d19679c9e0833ccc363d7f5a7c5f0c5f5d7'}
REPOSITORIES = {'KeychainAccess': 'https://github.com/kishikawakatsumi/KeychainAccess',
                'SDWebImage': 'https://github.com/SDWebImage/SDWebImage.git'}


def check_plan(analysis, plan, case):
    candidates = [c for c in analysis['candidates'] if c['pod']['isDirect']]
    require(len(candidates) == 2, 'Duplicate or unexpected direct candidate')
    direct = {c['pod']['name']: c for c in candidates}
    require(len(plan['entries']) == 2 and {e['podName'] for e in plan['entries']} == {case['migrate'], case['retain']},
            'Duplicate or unexpected plan entry')
    require(set(direct) == {case['migrate'], case['retain']}, 'Unexpected direct dependency set')
    require([n for n, c in direct.items() if c['classification'] == 'AUTO'] == [case['migrate']],
            'Reviewed analysis AUTO set changed')
    require(direct[case['retain']]['classification'] == 'BLOCKED', 'Retained dependency must remain BLOCKED')
    entries = [e for e in plan['entries'] if e['classification'] == 'AUTO']
    require(len(entries) == 1 and entries[0]['podName'] == case['migrate'], 'Reviewed plan AUTO set changed')
    entry = entries[0]
    require(entry['targetName'] == case['target'], 'Migration targets the wrong consumer')
    profile = entry['targetSourceProfile']
    require(profile['completeness'] == 'complete' and sorted(profile['languages']) == case['languages'],
            'Incomplete or changed consumer language evidence')
    require(entry['packageCandidate']['products'] == [case['migrate']], 'Unexpected migrated products')
    retained = [e for e in plan['entries'] if e['podName'] == case['retain']]
    require(len(retained) == 1 and retained[0]['classification'] == 'BLOCKED', 'Retained plan entry changed')
    require(any(r['code'] == 'configuration_denied' for r in retained[0].get('reasonDetails', [])),
            'Explicit retention policy evidence missing')


def check_lock(text, names):
    # Include SDWebImage's Core subspec but reject any other root dependency.
    pods = text.split('PODS:\n', 1)[1].split('\nDEPENDENCIES:', 1)[0]
    roots = set(re.findall(r'^  - ([^ /:(]+)(?:/[^ (]+)? \(', pods, re.MULTILINE))
    require(roots == set(names), 'Unexpected locked dependency roots')
    for name in names:
        require(re.search(r'^  - ' + re.escape(name) + r' \(' + re.escape(VERSIONS[name]) + r'\)',
                          pods, re.MULTILINE), 'Pinned dependency version changed')

    declarations = text.split('\nDEPENDENCIES:\n', 1)[1].split('\n\n', 1)[0]
    require(set(re.findall(r'^  - (.+)$', declarations, re.MULTILINE))
            == {f'{name} (= {VERSIONS[name]})' for name in names}, 'Unexpected locked direct declarations')

def check_linkage(document, case):
    objects = document['objects']
    targets = [o for o in objects.values() if o.get('isa') == 'PBXNativeTarget']
    require(len(targets) == 1 and targets[0]['name'] == case['target'], 'Unexpected target set')
    target = targets[0]
    products = [(k, o) for k, o in objects.items() if o.get('isa') == 'XCSwiftPackageProductDependency']
    require(len(products) == 1 and products[0][1]['productName'] == case['migrate'], 'Duplicate/wrong package product')
    product_id, product = products[0]
    require(target.get('packageProductDependencies') == [product_id], 'Product attached to wrong target')
    references = [(k, o) for k, o in objects.items() if o.get('isa') == 'XCRemoteSwiftPackageReference']
    require(len(references) == 1 and product['package'] == references[0][0], 'Duplicate/wrong package reference')
    reference_id, reference = references[0]
    require(reference['repositoryURL'].removesuffix('.git') == REPOSITORIES[case['migrate']].removesuffix('.git'),
            'Wrong package repository')
    require(reference['requirement'] == {'kind': 'exactVersion', 'version': VERSIONS[case['migrate']]},
            'Migration changed the pinned requirement')
    require(objects[document['rootObject']].get('packageReferences') == [reference_id], 'Package not owned by project')
    phases = [objects[key] for key in target['buildPhases']]
    frameworks = [p for p in phases if p['isa'] == 'PBXFrameworksBuildPhase']
    require(len(frameworks) == 1, 'Ambiguous framework linkage')
    linked = [objects[key].get('productRef') for key in frameworks[0]['files']]
    require(linked.count(product_id) == 1, 'SwiftPM product must link exactly once')
    all_links = [o for o in objects.values() if o.get('isa') == 'PBXBuildFile' and o.get('productRef') == product_id]
    require(len(all_links) == 1, 'Duplicate SwiftPM build file')
    require(any(p.get('isa') == 'PBXShellScriptBuildPhase' and p.get('name') == '[CP] Check Pods Manifest.lock'
                and 'Manifest.lock' in p.get('shellScript', '') for p in phases), 'CocoaPods check phase lost')
    configs = objects[target['buildConfigurationList']]['buildConfigurations']
    for key in configs:
        configuration = objects[key]
        ref = objects[configuration['baseConfigurationReference']]
        expected = f"Target Support Files/Pods-{case['target']}/Pods-{case['target']}.{configuration['name'].lower()}.xcconfig"
        require(ref['path'] == expected,
                'CocoaPods base configuration lost')


def protected_project_state(document):
    objects = document['objects']
    result = {}
    for key, obj in objects.items():
        if obj.get('isa') in {'PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'}:
            result[key] = obj
            for file_id in obj['files']:
                file = objects[file_id]
                result[file_id] = file
                result[file['fileRef']] = objects[file['fileRef']]
        elif obj.get('isa') == 'PBXNativeTarget':
            result[key] = {field: obj.get(field) for field in ('name', 'productName', 'productType', 'productReference')}
            result[key]['sourceResourcePhases'] = [p for p in obj['buildPhases']
                if objects[p]['isa'] in {'PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'}]
            for config_id in objects[obj['buildConfigurationList']]['buildConfigurations']:
                result[config_id] = objects[config_id]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', choices=CASES, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New, task-owned output directory')
    parser.add_argument('--pkglift', type=Path, required=True)
    parser.add_argument('--jobs', type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    case = CASES[args.case]
    binary = args.pkglift.resolve(strict=True)
    require(args.output.is_absolute(), 'Output directory must be absolute')
    output = args.output.parent.resolve(strict=True) / args.output.name
    require(output != ROOT and ROOT not in output.parents, 'Output must be outside the source checkout')
    output.mkdir(parents=False, exist_ok=False)
    reports = output / 'report'
    reports.mkdir()
    fixture = ROOT / 'Fixtures' / args.case
    require(not fixture.is_symlink() and not any(p.is_symlink() for p in fixture.rglob('*')), 'Fixture symlinks are not permitted')
    require(not (fixture / '.pkglift').exists(), 'Tracked fixture contains generated migration state')
    original = shared.tree_state(fixture)
    summary = {'schemaVersion': 1, 'case': args.case, 'status': 'incomplete',
               'repositoryOwned': True, 'migrated': case['migrate'], 'retained': case['retain'],
               'retentionPolicy': 'migration.deny', 'consumerLanguages': case['languages'],
               'buildSettings': {'configuration': 'Debug', 'architecture': 'arm64', 'iOSDeploymentTarget': '15.0'},
               'binarySHA256': shared.digest(binary), 'fixtureSHA256': original,
               'runnerSHA256': shared.digest(Path(__file__)),
               'releaseAcceptance': False}

    def run(label, command, cwd=None, seconds=600, json_output=False):
        path = reports / (label + ('.json' if json_output else '.log'))
        wrapper = [sys.executable, str(ROOT / 'Scripts/run-with-timeout.py'), '--seconds', str(seconds)]
        wrapper += ['--stdout', str(path), '--stderr', str(reports / (label + '.stderr.log'))] if json_output else ['--combined-log', str(path)]
        if cwd is not None:
            wrapper += ['--cwd', str(cwd)]
        print(args.case + ': ' + label, flush=True)
        subprocess.run(wrapper + ['--'] + [str(v) for v in command], check=True)
        return path

    try:
        env_spec = importlib.util.spec_from_file_location('capture_environment', ROOT / 'Scripts/capture-environment.py')
        env_module = importlib.util.module_from_spec(env_spec)
        env_spec.loader.exec_module(env_module)
        environment = env_module.capture_environment()
        (reports / 'environment.json').write_text(json.dumps(environment, indent=2) + '\n')
        require(environment['system']['macOS']['status'] == 'passed'
                and all(c['status'] == 'passed' for c in environment['commands'].values()), 'Incomplete environment probes')
        summary['sourceCommit'] = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
        summary['workingTreeHasChanges'] = bool(subprocess.check_output(['git', '-C', str(ROOT), 'status', '--porcelain']))
        for label, command in [('xcode', ['xcodebuild', '-version']), ('swift', ['swift', '--version']),
                               ('os', ['sw_vers']), ('arch', ['uname', '-m']), ('pods', ['pod', '--version']),
                               ('version', [binary, 'version'])]:
            run(label, command, seconds=60)
        migration = output / 'consumer'
        shutil.copytree(fixture, migration)
        protected = shared.tree_state(migration / 'App')
        config = (migration / '.pkglift.yml').read_bytes()
        podfile = (migration / 'Podfile').read_bytes()
        run('baseline-install', ['pod', 'install', '--deployment'], migration)
        check_lock((migration / 'Podfile.lock').read_text(), VERSIONS)
        shutil.copyfile(migration / 'Podfile.lock', reports / 'baseline-Podfile.lock')
        target = case['target']
        project = migration / (target + '.xcodeproj/project.pbxproj')
        baseline_project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project)]))
        (reports / 'baseline-project.json').write_text(json.dumps(baseline_project, indent=2) + '\n')
        derived = output / 'derived'
        workspace = migration / (target + '.xcworkspace')
        run('baseline-build', ['xcodebuild', '-workspace', workspace, '-scheme', target, '-configuration', 'Debug',
                              '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
                              '-derivedDataPath', derived, '-jobs', args.jobs, 'CODE_SIGNING_ALLOWED=NO', 'IPHONEOS_DEPLOYMENT_TARGET=15.0', 'ARCHS=arm64', 'build'], seconds=1200)
        common = ['--path', migration, '--project', target + '.xcodeproj', '--no-color']
        analysis = json.loads(run('analysis', [binary, 'analyze', *common, '--json'], json_output=True).read_text())
        run('plan-command', [binary, 'plan', *common, '--json'], json_output=True)
        shutil.copyfile(migration / '.pkglift/plan.json', reports / 'plan.json')
        check_plan(analysis, json.loads((reports / 'plan.json').read_text()), case)
        before = shared.tree_state(migration)
        run('dry-run', [binary, 'migrate', *common])
        require(before == shared.tree_state(migration), 'Dry run mutated consumer')
        run('apply', [binary, 'migrate', *common, '--apply'])
        shared.verify_migrated_podfile(podfile, (migration / 'Podfile').read_bytes(), case['migrate'], VERSIONS[case['migrate']])
        run('refresh-pods', ['pod', 'install', '--clean-install'], migration)
        lock = (migration / 'Podfile.lock').read_bytes()
        check_lock(lock.decode(), [case['retain']])
        require(lock == (migration / 'Pods/Manifest.lock').read_bytes(), 'Retained Pods manifest differs from lockfile')
        shutil.copyfile(migration / 'Podfile.lock', reports / 'retained-Podfile.lock')
        project = migration / (target + '.xcodeproj/project.pbxproj')
        doc = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(project)]))
        check_linkage(doc, case)
        require(protected_project_state(doc) == protected_project_state(baseline_project),
                'Consumer source/resource membership or target settings changed')
        # Use fresh post-migration objects, with identical configuration/settings.
        # Sharing baseline objects could hide missing consumer imports after apply.
        derived = output / 'migrated-derived'
        run('migrated-build', ['xcodebuild', '-workspace', workspace, '-scheme', target, '-configuration', 'Debug',
                              '-sdk', 'iphonesimulator', '-destination', 'generic/platform=iOS Simulator',
                              '-derivedDataPath', derived, '-jobs', args.jobs, 'CODE_SIGNING_ALLOWED=NO', 'IPHONEOS_DEPLOYMENT_TARGET=15.0', 'ARCHS=arm64', 'build'], seconds=1200)
        run('verification', [binary, 'verify', *common, '--workspace', target + '.xcworkspace', '--json'], json_output=True)
        pins = list(migration.rglob('Package.resolved'))
        require(len(pins) == 1, 'Missing/ambiguous SwiftPM lockfile')
        resolved = json.loads(pins[0].read_text())['pins']
        require(len(resolved) == 1 and resolved[0]['identity'].lower() == case['migrate'].lower()
                and resolved[0]['state']['version'] == VERSIONS[case['migrate']]
                and resolved[0]['state']['revision'] == REVISIONS[case['migrate']], 'Unexpected resolved SwiftPM dependency')
        shutil.copyfile(pins[0], reports / 'Package.resolved')
        require(protected == shared.tree_state(migration / 'App'), 'Source or resources changed')
        require(config == (migration / '.pkglift.yml').read_bytes(), 'Retention policy changed')
        require(original == shared.tree_state(fixture), 'Original fixture changed')
        summary.update(status='passed', baselineBuild='passed', migratedBuild='passed',
                       exactAutoSet=True, dryRunUnchanged=True, retainedPodsManifest=True,
                       swiftPMLinkedExactlyOnce=True, consumerBytesUnchanged=True,
                       sourceResourceMembershipUnchanged=True, freshMigratedBuild=True,
                       configurationUnchanged=True, repositoryFixtureUnchanged=True,
                       resolvedRevision=resolved[0]['state']['revision'])
    finally:
        (reports / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
