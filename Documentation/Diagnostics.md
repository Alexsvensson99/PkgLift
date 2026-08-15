# Privacy-Preserving Diagnostics

`pkglift diagnostics` writes a local JSON report that helps reproduce project-discovery, classification, and environment problems without copying source code or complete project configuration into an issue.

The command never uploads the report.

```bash
pkglift diagnostics \
  --path /path/to/project \
  --output pkglift-diagnostics.json
```

When several Xcode candidates exist, use the same explicit selection that reproduces the problem:

```bash
pkglift diagnostics \
  --path /path/to/repository \
  --workspace Workspaces/Products.xcworkspace \
  --project Projects/App.xcodeproj \
  --output pkglift-diagnostics.json
```

## Review Before Sharing

PkgLift deliberately minimizes the report, but you should still open and review the JSON before attaching it to a public issue.

A report contains:

- the PkgLift report schema and PkgLift version;
- macOS, Xcode, Swift, and CocoaPods versions when available;
- counts of discovered projects, workspaces, targets, dependencies, packages, issues, and classifications;
- boolean Podfile risk features such as dynamic Ruby, hooks, and `use_frameworks!`;
- readiness score when analysis succeeds;
- whether the directory is not a Git repository, clean, dirty, or unknown;
- the number of changed files, but not their names;
- stable error type names for stages that could not be inspected.

A report does not contain:

- source code or complete Podfile contents;
- dependency, project, workspace, scheme, product, or target names;
- repository or package URLs;
- Git remotes or credentials;
- changed filenames;
- arbitrary error messages;
- signing identities, provisioning information, environment-variable values, or bundle identifiers;
- absolute user or project paths;
- automatic upload metadata or a remote report identifier.

Every report embeds this privacy contract in its `privacy` object.

## Partial Reports

Diagnostics can still produce a useful report when discovery or analysis fails. In that case:

- `status` is `partial`;
- the successful environment or Git summaries remain available;
- `failures` identifies the stage and concrete error type;
- arbitrary localized error text is omitted because it may contain private input.

A successful diagnostics command means that the report was written, not that every project-analysis stage succeeded.

## Output Safety

The output path is required. Relative paths are resolved from the current working directory.

PkgLift:

- creates a missing parent directory with private owner-only permissions;
- writes the JSON atomically;
- sets the report file to mode `0600`;
- refuses to overwrite an existing file unless `--overwrite` is supplied;
- refuses to replace a symbolic link or directory.

```bash
pkglift diagnostics \
  --path . \
  --output reports/pkglift-diagnostics.json \
  --overwrite
```

Choose an output location that will not be committed accidentally. A repository-local exclusion can be used for one-off reports:

```bash
printf '%s\n' 'pkglift-diagnostics.json' >> .git/info/exclude
```

## Deterministic Schema

Diagnostics use a versioned JSON schema and sorted keys. The report intentionally has no timestamp, host name, account name, random identifier, or current working directory field. Repeated runs with the same project state and toolchain produce the same structured content.

When `schemaVersion` changes, consumers should treat it as a compatibility boundary rather than assuming newly added or renamed fields.
