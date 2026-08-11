# Contributing Registry Mappings

1. Verify the upstream repository is official and contains a Swift package manifest.
2. Verify the exact products exported by that package.
3. Create a `.yml` file in the matching alphabetical folder under `Registry/`, using `Registry/_template.yml` as the template.
4. Use `confidence: verified` only when the repository and product relationship are concrete. Use a lower confidence when evidence is incomplete; it will not become `AUTO`.
5. Run:

   ```bash
   swift run pkglift registry validate
   swift test
   ```

6. Include the upstream evidence in the pull request description.

Do not add guessed repository URLs, products, or version requirements merely to make a dependency migratable.
