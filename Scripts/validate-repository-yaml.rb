#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

errors = []

def load_yaml(path, errors)
  content = File.read(path, encoding: "UTF-8")
  YAML.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: true)
rescue StandardError => e
  errors << "#{path}: #{e.class}: #{e.message}"
  nil
end

yaml_paths = Dir.glob(".github/**/*.{yml,yaml}").sort
if yaml_paths.empty?
  errors << ".github: no YAML files found"
end

yaml_paths.each do |path|
  document = load_yaml(path, errors)
  errors << "#{path}: top-level YAML value must be a mapping" unless document.nil? || document.is_a?(Hash)
end

workflow_paths = Dir.glob(".github/workflows/*.{yml,yaml}").sort
workflow_paths.each do |path|
  File.foreach(path, encoding: "UTF-8").with_index(1) do |line, line_number|
    match = line.match(/^\s*(?:-\s*)?uses:\s+([^\s#]+)/)
    next if match.nil?

    reference = match[1]
    next if reference.start_with?("./", "docker://")

    unless reference.match?(%r{\A[^@]+@[0-9a-f]{40}\z})
      errors << "#{path}:#{line_number}: external action must use a full commit SHA"
    end
  end
end

release_workflow_path = ".github/workflows/release.yml"
release_workflow = File.file?(release_workflow_path) ? File.read(release_workflow_path, encoding: "UTF-8") : ""
unless release_workflow.match?(/^on:\n  workflow_dispatch:\s*$/)
  errors << "#{release_workflow_path}: signed distribution must be workflow_dispatch-only"
end
errors << "#{release_workflow_path}: direct tag pushes must not trigger distribution" if release_workflow.match?(/^  push:\s*$/)
errors << "#{release_workflow_path}: direct tag publication must not exist" if release_workflow.match?(/^  publish:\s*$/)
errors << "#{release_workflow_path}: public release action belongs only in the manifest workflow" if release_workflow.include?("softprops/action-gh-release@")
unless release_workflow.include?("if: github.ref == 'refs/heads/main'")
  errors << "#{release_workflow_path}: manual distribution must remain restricted to main"
end

manifest_workflow_path = ".github/workflows/publish-release-manifest.yml"
manifest_workflow = File.file?(manifest_workflow_path) ? File.read(manifest_workflow_path, encoding: "UTF-8") : ""
unless manifest_workflow.include?("python3 Scripts/validate-release-manifest.py")
  errors << "#{manifest_workflow_path}: must use the testable release-manifest validator"
end
unless manifest_workflow.include?("pull-requests: read")
  errors << "#{manifest_workflow_path}: must grant read-only pull-request evidence access"
end
atomic_tag_command = "python3 Scripts/validate-release-manifest.py create-tag"
release_action_marker = "uses: softprops/action-gh-release@"
atomic_tag_index = manifest_workflow.index(atomic_tag_command)
release_action_index = manifest_workflow.index(release_action_marker)
if atomic_tag_index.nil?
  errors << "#{manifest_workflow_path}: must atomically create and verify the validated tag"
elsif !release_action_index.nil? && atomic_tag_index >= release_action_index
  errors << "#{manifest_workflow_path}: must verify the exact tag before public release creation"
end

release_sink_paths = workflow_paths.select do |path|
  File.read(path, encoding: "UTF-8").include?("softprops/action-gh-release@")
end
unless release_sink_paths == [manifest_workflow_path]
  errors << "Only #{manifest_workflow_path} may contain the public release action; found #{release_sink_paths.inspect}"
end

quality_workflow_path = ".github/workflows/quality.yml"
quality_workflow = File.file?(quality_workflow_path) ? File.read(quality_workflow_path, encoding: "UTF-8") : ""
unless quality_workflow.include?("-s Tests/ReleaseManifestTests") && quality_workflow.include?("-p 'test_*.py'")
  errors << "#{quality_workflow_path}: must run release-manifest policy regressions"
end

shared_workflow_path = ".github/workflows/positive-e2e.yml"
%w[build test registry pilots].each do |name|
  path = ".github/workflows/#{name}.yml"
  errors << "#{path}: duplicate ordinary CI entrypoint must not exist" if File.exist?(path)
end

required_gates = [
  [shared_workflow_path, "test", "test", ["build_pilot_toolchain"]],
  [shared_workflow_path, "registry_gate", "Registry Gate", ["build_pilot_toolchain"]],
  [shared_workflow_path, "pinned_gate", "Pinned Pilot Gate", %w[build_pilot_toolchain analyze]],
  [shared_workflow_path, "gate", "Mixed-Language Pilot Gate", %w[build_pilot_toolchain migrate-and-build]],
  [".github/workflows/codeql.yml", "gate", "CodeQL", ["analyze"]],
].freeze
required_gates.each do |path, gate_id, name, heavy_ids|
  workflow = load_yaml(path, errors)
  next unless workflow.is_a?(Hash)

  events = workflow["on"] || workflow[true]
  unless events.is_a?(Hash) && events.key?("pull_request") && events["pull_request"].nil? &&
      events["push"] == { "branches" => ["main"] } && !events.key?("pull_request_target")
    errors << "#{path}: required validation must run on every pull request and main push without path filters"
  end
  jobs = workflow["jobs"]
  next unless jobs.is_a?(Hash)
  gate_job = jobs[gate_id]
  unless gate_job.is_a?(Hash) && gate_job["name"] == name
    errors << "#{path}: missing required stable gate #{name.inspect}"
    next
  end
  errors << "#{path}: #{gate_id} must use always()" unless gate_job["if"] == "always()"
  errors << "#{path}: #{gate_id} must not continue on error" if gate_job.key?("continue-on-error")
  gate_steps = Array(gate_job["steps"])
  gate_steps.each do |step|
    next unless step.is_a?(Hash)
    errors << "#{path}: #{gate_id} steps must fail closed unconditionally" if step.key?("if") || step.key?("continue-on-error")
  end
  heavy_ids.each do |heavy_id|
    heavy = jobs[heavy_id]
    unless heavy.is_a?(Hash)
      errors << "#{path}: missing heavy job #{heavy_id.inspect}"
      next
    end
    if heavy.key?("if") || heavy.key?("continue-on-error")
      errors << "#{path}: heavy job #{heavy_id.inspect} must run unconditionally and fail closed"
    end
    if path == ".github/workflows/codeql.yml"
      Array(heavy["steps"]).each do |step|
        next unless step.is_a?(Hash)
        if step.key?("if") || step.key?("continue-on-error")
          errors << "#{path}: CodeQL analysis steps must run unconditionally and fail closed"
        end
      end
    end
    unless Array(gate_job["needs"]).include?(heavy_id)
      errors << "#{path}: #{gate_id} must require heavy job #{heavy_id.inspect}"
    end
    checks_result = gate_steps.any? do |step|
      next false unless step.is_a?(Hash) && step["env"].is_a?(Hash) && step["run"].is_a?(String)
      step["env"].any? do |variable, value|
        check = %Q([[ "$#{variable}" == 'success' ]])
        check += " || exit 1" if path == shared_workflow_path
        value == "${{ needs.#{heavy_id}.result }}" &&
          step["run"].lines.any? { |line| line.strip == check } &&
          step["run"].lines.any? { |line| line.strip == "set -euo pipefail" }
      end
    end
    errors << "#{path}: #{gate_id} must require successful #{heavy_id} result" unless checks_result
  end
end

pilot_workflow_path = shared_workflow_path
pilot_workflow = load_yaml(pilot_workflow_path, errors)
pilot_jobs = pilot_workflow.is_a?(Hash) ? pilot_workflow["jobs"] : nil
if pilot_jobs.is_a?(Hash)
  producer_id = "build_pilot_toolchain"
  producer = pilot_jobs[producer_id]
  if !producer.is_a?(Hash)
    errors << "#{pilot_workflow_path}: missing shared pilot artifact producer #{producer_id.inspect}"
  else
    errors << "#{pilot_workflow_path}: producer must preserve build check name" unless producer["name"] == "build"
    errors << "#{pilot_workflow_path}: shared pilot producer must run on macos-15" unless producer["runs-on"] == "macos-15"
    required_outputs = %w[archive_sha256 artifact_name artifact_run_attempt binary_sha256]
    missing_outputs = required_outputs - Hash(producer["outputs"]).keys
    errors << "#{pilot_workflow_path}: shared pilot producer is missing outputs #{missing_outputs.join(', ')}" unless missing_outputs.empty?
    producer_steps = Array(producer["steps"])
    producer_steps.each do |step|
      next unless step.is_a?(Hash)
      errors << "#{pilot_workflow_path}: producer steps must run unconditionally and fail closed" if step.key?("if") || step.key?("continue-on-error")
    end
    producer_scripts = producer_steps.map { |step| step["run"] if step.is_a?(Hash) }.compact.join("\n")
    ["swift build -j 2", "swift test -j 2", "swift run --skip-build pkglift registry validate",
     "swift build -c release -j 2 --arch arm64"].each do |command|
      unless producer_scripts.lines.count { |line| line.strip == command } == 1
        errors << "#{pilot_workflow_path}: producer must run #{command.inspect} exactly once"
      end
    end
    unless producer_scripts.include?("Scripts/package-pilot-artifact.sh")
      errors << "#{pilot_workflow_path}: shared pilot producer must use the verified packager"
    end
    unless producer_scripts.include?("git rev-parse HEAD") && producer_scripts.include?("GITHUB_SHA")
      errors << "#{pilot_workflow_path}: shared pilot producer must verify its exact source SHA"
    end
    unless producer_steps.any? { |step| step.is_a?(Hash) && step.fetch("uses", "").start_with?("actions/upload-artifact@") }
      errors << "#{pilot_workflow_path}: shared pilot producer must upload its artifact"
    end
  end

  %w[analyze migrate-and-build].each do |consumer_id|
    consumer = pilot_jobs[consumer_id]
    next unless consumer.is_a?(Hash)
    unless Array(consumer["needs"]).include?(producer_id)
      errors << "#{pilot_workflow_path}: #{consumer_id} must require the shared pilot producer"
    end
    steps = Array(consumer["steps"])
    scripts = steps.map { |step| step["run"] if step.is_a?(Hash) }.compact.join("\n")
    errors << "#{pilot_workflow_path}: #{consumer_id} must consume the shared binary instead of rebuilding" if scripts.include?("swift build")
    download = steps.find { |step| step.is_a?(Hash) && step.fetch("uses", "").start_with?("actions/download-artifact@") }
    unless download && download.dig("with", "name") == "${{ needs.build_pilot_toolchain.outputs.artifact_name }}" &&
        !download.fetch("with", {}).key?("run-id") && !download.fetch("with", {}).key?("repository")
      errors << "#{pilot_workflow_path}: #{consumer_id} must download this run's shared artifact"
    end
    verifier = steps.find { |step| step.is_a?(Hash) && step.fetch("run", "").include?("Scripts/verify-pilot-artifact.py") }
    expected = {
      "PKGLIFT_EXPECTED_ARCHIVE_SHA256" => "${{ needs.build_pilot_toolchain.outputs.archive_sha256 }}",
      "PKGLIFT_EXPECTED_BINARY_SHA256" => "${{ needs.build_pilot_toolchain.outputs.binary_sha256 }}",
      "PKGLIFT_EXPECTED_PRODUCER_ATTEMPT" => "${{ needs.build_pilot_toolchain.outputs.artifact_run_attempt }}",
      "PKGLIFT_EXPECTED_REPOSITORY" => "${{ github.repository }}",
      "PKGLIFT_EXPECTED_RUN_ID" => "${{ github.run_id }}",
      "PKGLIFT_EXPECTED_SOURCE_SHA" => "${{ github.sha }}",
    }
    unless verifier && expected.all? { |key, value| verifier.dig("env", key) == value }
      errors << "#{pilot_workflow_path}: #{consumer_id} must verify all artifact identity and checksum evidence"
    end
    runner_script = consumer_id == "analyze" ? "Scripts/run-pinned-pilot.sh" : "Scripts/run-positive-e2e-pilot.sh"
    runner_step = steps.find { |step| step.is_a?(Hash) && step.fetch("run", "").include?(runner_script) }
    unless download && verifier && runner_step && steps.index(download) < steps.index(verifier) && steps.index(verifier) < steps.index(runner_step)
      errors << "#{pilot_workflow_path}: #{consumer_id} must verify the downloaded artifact before running pilots"
    end
    [download, verifier, runner_step].compact.each do |step|
      if step.key?("if") || step.key?("continue-on-error")
        errors << "#{pilot_workflow_path}: #{consumer_id} artifact and pilot steps must fail closed unconditionally"
      end
    end
  end
end

pilot_runner_path = "Scripts/run-pinned-pilot.sh"
pilot_runner = File.file?(pilot_runner_path) ? File.read(pilot_runner_path, encoding: "UTF-8") : ""
pilot_case_match = pilot_runner.match(
  /case "\$PILOT_CASE" in\s+([a-z0-9_-]+(?:\|[a-z0-9_-]+)*)\)\s*;;/
)

if pilot_case_match.nil?
  errors << "#{pilot_runner_path}: missing statically verifiable PILOT_CASE allowlist"
else
  supported_pilot_cases = pilot_case_match[1].split("|")
  pilot_matrix = pilot_workflow.is_a?(Hash) ? pilot_workflow.dig("jobs", "analyze", "strategy", "matrix", "include") : nil

  unless pilot_matrix.is_a?(Array) && !pilot_matrix.empty?
    errors << "#{pilot_workflow_path}: analyze matrix must have a non-empty include array"
  else
    workflow_pilot_cases = []
    pilot_matrix.each_with_index do |entry, index|
      pilot_case = entry["case"] if entry.is_a?(Hash)
      if !pilot_case.is_a?(String) || pilot_case.empty?
        errors << "#{pilot_workflow_path}: analyze matrix entry #{index} requires a non-empty string case"
        next
      end

      workflow_pilot_cases << pilot_case
    end

    pilot_case_counts = Hash.new(0)
    workflow_pilot_cases.each { |pilot_case| pilot_case_counts[pilot_case] += 1 }
    duplicate_pilot_cases = pilot_case_counts.select { |_pilot_case, count| count > 1 }.keys.sort
    duplicate_pilot_cases.each do |pilot_case|
      errors << "#{pilot_workflow_path}: duplicate pilot case #{pilot_case.inspect}"
    end

    unsupported_pilot_cases = (workflow_pilot_cases - supported_pilot_cases).uniq.sort
    unsupported_pilot_cases.each do |pilot_case|
      errors << "#{pilot_workflow_path}: pilot case #{pilot_case.inspect} is not accepted by #{pilot_runner_path}"
    end

    missing_pilot_cases = (supported_pilot_cases - workflow_pilot_cases).sort
    missing_pilot_cases.each do |pilot_case|
      errors << "#{pilot_workflow_path}: missing matrix entry for supported pilot case #{pilot_case.inspect}"
    end
  end
end

dependabot = load_yaml(".github/dependabot.yml", errors)
if dependabot.is_a?(Hash)
  ecosystems = Array(dependabot["updates"]).map do |entry|
    entry["package-ecosystem"] if entry.is_a?(Hash)
  end.compact
  %w[swift github-actions].each do |ecosystem|
    errors << ".github/dependabot.yml: missing #{ecosystem} updates" unless ecosystems.count(ecosystem) == 1
  end
end

issue_forms = Dir.glob(".github/ISSUE_TEMPLATE/*.{yml,yaml}")
  .reject { |path| File.basename(path) == "config.yml" }
  .sort
allowed_types = %w[markdown input textarea dropdown checkboxes].freeze

issue_forms.each do |path|
  form = load_yaml(path, errors)
  next unless form.is_a?(Hash)

  %w[name description body].each do |key|
    errors << "#{path}: missing required top-level key #{key.inspect}" unless form.key?(key)
  end

  body = form["body"]
  unless body.is_a?(Array) && !body.empty?
    errors << "#{path}: body must be a non-empty array"
    next
  end

  seen_ids = {}
  body.each_with_index do |item, index|
    location = "#{path}: body[#{index}]"
    unless item.is_a?(Hash)
      errors << "#{location} must be a mapping"
      next
    end

    type = item["type"]
    errors << "#{location} has unsupported or missing type #{type.inspect}" unless allowed_types.include?(type)

    attributes = item["attributes"]
    errors << "#{location} attributes must be a mapping" unless attributes.is_a?(Hash)

    next if type == "markdown"

    id = item["id"]
    if !id.is_a?(String) || id.empty?
      errors << "#{location} requires a non-empty string id"
    elsif seen_ids.key?(id)
      errors << "#{location} duplicates id #{id.inspect} first used at body[#{seen_ids[id]}]"
    else
      seen_ids[id] = index
    end

    if %w[dropdown checkboxes].include?(type)
      options = attributes.is_a?(Hash) ? attributes["options"] : nil
      errors << "#{location} requires a non-empty options array" unless options.is_a?(Array) && !options.empty?
    end
  end
end

if errors.any?
  warn "Repository YAML validation failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Validated #{yaml_paths.length} YAML files, #{workflow_paths.length} SHA-pinned workflows, and #{issue_forms.length} issue forms."
