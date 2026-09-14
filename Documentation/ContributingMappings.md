# Contributing Registry Mappings

1. Verify the upstream repository is official and contains a Swift package manifest.
2. Verify the exact products exported by that package.
3. Verify every value in `swiftpm.supportedConsumerLanguages` and every schema-2 `swiftpm.supportedConsumerPlatforms` entry with a reproducible compiling consumer. A mixed target needs evidence for every consumer language; package implementation language is not sufficient. Record only platforms and minimum deployment targets covered by that evidence.
4. Create a `.yml` file in the matching alphabetical folder under `Registry/`, using `Registry/_template.yml` as the template.
5. Record a conservative stable `swiftpm.minimumVersion` whose official upstream tag contains the listed product and verified consumer-language support, plus `metadata.lastVerified` in `YYYY-MM-DD` form.
6. Use `confidence: verified` only when the repository, exact pod/subspec identifier, product, version, consumer-language, and consumer-platform evidence are concrete. Use a lower confidence when evidence is incomplete; it will not become `AUTO`.
7. Run:

   ```bash
   swift run pkglift registry validate
   swift test
   ```

8. Include the upstream evidence in the pull request description.

Do not add guessed repository URLs, products, identifiers, version evidence, consumer-language support, or consumer-platform support merely to make a dependency migratable. Omitting `minimumVersion` or `supportedConsumerLanguages` is valid for older schema-1 mappings and deliberately keeps the mapping review-only. Schema 1 must omit `supportedConsumerPlatforms`. New executable mappings use schema 2 and require version, language, and non-empty platform evidence; older PkgLift versions then reject the mapping instead of ignoring its platform boundary.
