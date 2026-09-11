# Continuous integration

Ordinary validation is coordinated in `.github/workflows/positive-e2e.yml`.
Its existing workflow identity is retained because reviewed release manifests
require a successful main push run from this path on the exact prepared source
commit. CodeQL and repository quality checks remain separate workflows.

## Shared compilation

The `build_pilot_toolchain` job, displayed as the required `build` check, performs:

1. Exact checkout verification.
2. Debug compilation, the full Swift test suite, and registry validation using
   that compiled CLI.
3. One arm64 release compilation, packaging and smoke tests.
4. Upload of the verified pilot archive, retained for one day.

The required `test` and `Registry Gate` checks succeed only when this job
succeeds. They report the outcome of real, unconditional validation in the
producer; they do not replace those validations. A build, test, registry,
packaging or upload failure blocks both checks and both pilot groups.

The pinned pilot matrix and mixed-language migration/build pilot consume the
same archive from the same workflow run. Each independently verifies the source
SHA, repository, run ID, producer attempt, architecture, archive checksum,
executable checksum and registry bundle checksum before executing it. A partial
rerun uses the original producer attempt from job outputs rather than assuming
that the consumer attempt produced a new archive. A missing or expired archive
fails closed; rerun the whole workflow to produce a new one.

The pilot gates require successful producer and consumer jobs, even when an
upstream job is failed, cancelled or skipped. The ten pinned cases retain their
individual reports and run with matrix fail-fast disabled.

## Preserved coverage

All ordinary validations run for pull requests, main pushes and manual runs.
The previous Tuesday pinned-pilot schedule now runs the consolidated workflow,
including its tests and mixed-language pilot. CodeQL retains its independent
instrumented compilation and Wednesday schedule. No path-based skipping or
cross-workflow artifact lookup is used. Required check names remain:

- `build`
- `test`
- `repository`
- `Registry Gate`
- `Pinned Pilot Gate`
- `Mixed-Language Pilot Gate`
- `CodeQL`

Signing, notarization, reviewed release manifests and public release approval
are unchanged. A passing PR run does not replace main evidence for a release.

## Measuring the change

Ordinary PR/main validation previously compiled the package independently seven
times (four debug and three release builds). It now compiles three times: one
ordinary debug build reused by tests/registry, one release build, and the
separate CodeQL build. Tests still compile their own test targets as necessary.
This is a compilation-count reduction, not a measured percentage runtime saving.

The shared producer serializes preparation before the two pilot groups, which
can increase time to an individual result even while reducing total runner
time. Compare total job time and time to all required checks over representative
PRs. Do not trigger extra full workflows solely to collect measurements. Keep
billable account usage, job time, queue time and artifact storage distinct.
