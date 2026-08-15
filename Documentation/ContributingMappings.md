# Contributing Registry Mappings

1. Verify the upstream repository is official and contains a Swift package manifest.
2. Verify the exact products exported by that package.
3. Create a `.yml` file in the matching alphabetical folder under `Registry/`, using `Registry/_template.yml` as the template.
4. Record a conservative stable `swiftpm.minimumVersion` whose official upstream tag contains the listed product, plus `metadata.lastVerified` in `YYYY-MM-DD` form.
5. Use `confidence: verified` only when the repository, exact pod/subspec identifier, product, and version evidence are concrete. Use a lower confidence when evidence is incomplete; it will not become `AUTO`.
6. Run:

   ```bash
   swift run pkglift registry validate
   swift test
   ```

7. Include the upstream evidence in the pull request description.

Do not add guessed repository URLs, products, identifiers, or version evidence merely to make a dependency migratable. Omitting `minimumVersion` is valid for schema 1 and deliberately keeps the mapping review-only.
