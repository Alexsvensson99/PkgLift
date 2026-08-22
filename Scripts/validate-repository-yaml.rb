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

required_gates = {
  ".github/workflows/registry.yml" => ["name: Registry Gate", "validate"],
  ".github/workflows/pilots.yml" => ["name: Pinned Pilot Gate", "analyze"],
  ".github/workflows/positive-e2e.yml" => ["name: Mixed-Language Pilot Gate", "migrate-and-build"],
  ".github/workflows/codeql.yml" => ["name: CodeQL", "analyze"],
}.freeze
required_gates.each do |path, (marker, heavy_job_id)|
  content = File.file?(path) ? File.read(path, encoding: "UTF-8") : ""
  unless content.include?(marker)
    errors << "#{path}: missing required stable gate #{marker.inspect}"
  end

  errors << "#{path}: pull requests must run the heavy validation" unless content.match?(/^  pull_request:\s*$/)
  errors << "#{path}: pull_request_target must not execute candidate code" if content.match?(/^  pull_request_target:\s*$/)
  errors << "#{path}: path relevance must not control a required gate" if content.include?("ci-paths-relevant.py")
  errors << "#{path}: required gates must not accept skipped heavy validation" if content.include?("safely skipped")

  workflow = load_yaml(path, errors)
  jobs = workflow.is_a?(Hash) ? workflow["jobs"] : nil
  next unless jobs.is_a?(Hash)

  heavy_job = jobs[heavy_job_id]
  gate_job = jobs["gate"]
  unless heavy_job.is_a?(Hash)
    errors << "#{path}: missing heavy job #{heavy_job_id.inspect}"
    next
  end
  unless gate_job.is_a?(Hash)
    errors << "#{path}: missing gate job"
    next
  end

  errors << "#{path}: heavy job #{heavy_job_id.inspect} must run unconditionally" if heavy_job.key?("if")
  unless Array(gate_job["needs"]).include?(heavy_job_id)
    errors << "#{path}: gate must require heavy job #{heavy_job_id.inspect}"
  end
  errors << "#{path}: gate must use always()" unless gate_job["if"] == "always()"

  gate_steps = Array(gate_job["steps"])
  gate_result_refs = gate_steps.map { |step| step["env"] if step.is_a?(Hash) }.compact
    .flat_map(&:values)
    .select { |value| value.is_a?(String) }
  unless gate_result_refs.any? { |value| value.include?("needs.#{heavy_job_id}.result") }
    errors << "#{path}: gate must inspect the result of #{heavy_job_id.inspect}"
  end
  gate_scripts = gate_steps.map { |step| step["run"] if step.is_a?(Hash) }.compact.join("\n")
  errors << "#{path}: gate must require a successful heavy job" unless gate_scripts.include?("== 'success'")
  errors << "#{path}: gate must not accept skipped heavy validation" if gate_scripts.include?("'skipped'")
end

pilot_workflow_path = ".github/workflows/pilots.yml"
pilot_workflow = load_yaml(pilot_workflow_path, errors)
pilot_jobs = pilot_workflow.is_a?(Hash) ? pilot_workflow["jobs"] : nil
if pilot_jobs.is_a?(Hash)
  producer_id = "build_pilot_toolchain"
  producer = pilot_jobs[producer_id]
  analyze = pilot_jobs["analyze"]
  gate = pilot_jobs["gate"]

  if !producer.is_a?(Hash)
    errors << "#{pilot_workflow_path}: missing shared pilot artifact producer #{producer_id.inspect}"
  else
    errors << "#{pilot_workflow_path}: shared pilot producer must run unconditionally" if producer.key?("if")
    errors << "#{pilot_workflow_path}: shared pilot producer must run on macos-15" unless producer["runs-on"] == "macos-15"
    required_outputs = %w[archive_sha256 artifact_name artifact_run_attempt binary_sha256]
    missing_outputs = required_outputs - Hash(producer["outputs"]).keys
    unless missing_outputs.empty?
      errors << "#{pilot_workflow_path}: shared pilot producer is missing outputs #{missing_outputs.sort.join(', ')}"
    end

    producer_steps = Array(producer["steps"])
    producer_scripts = producer_steps.map { |step| step["run"] if step.is_a?(Hash) }.compact.join("\n")
    producer_actions = producer_steps.map { |step| step["uses"] if step.is_a?(Hash) }.compact
    unless producer_scripts.include?("Scripts/package-pilot-artifact.sh")
      errors << "#{pilot_workflow_path}: shared pilot producer must use the verified packager"
    end
    unless producer_scripts.include?("swift build -c release -j 2 --arch arm64")
      errors << "#{pilot_workflow_path}: shared pilot producer must build the arm64 release binary once"
    end
    unless producer_scripts.include?("git rev-parse HEAD") && producer_scripts.include?("GITHUB_SHA")
      errors << "#{pilot_workflow_path}: shared pilot producer must verify its exact source SHA"
    end
    unless producer_actions.any? { |action| action.start_with?("actions/upload-artifact@") }
      errors << "#{pilot_workflow_path}: shared pilot producer must upload its artifact"
    end
  end

  if analyze.is_a?(Hash)
    unless Array(analyze["needs"]).include?(producer_id)
      errors << "#{pilot_workflow_path}: analyze must require the shared pilot producer"
    end
    analyze_steps = Array(analyze["steps"])
    analyze_scripts = analyze_steps.map { |step| step["run"] if step.is_a?(Hash) }.compact.join("\n")
    analyze_actions = analyze_steps.map { |step| step["uses"] if step.is_a?(Hash) }.compact
    if analyze_scripts.include?("swift build")
      errors << "#{pilot_workflow_path}: analyze must consume the shared binary instead of rebuilding"
    end
    unless analyze_scripts.include?("Scripts/verify-pilot-artifact.py")
      errors << "#{pilot_workflow_path}: analyze must fail closed through the artifact verifier"
    end
    unless analyze_actions.any? { |action| action.start_with?("actions/download-artifact@") }
      errors << "#{pilot_workflow_path}: analyze must download the shared pilot artifact"
    end
  end

  if gate.is_a?(Hash)
    gate_needs = Array(gate["needs"])
    unless gate_needs.include?(producer_id) && gate_needs.include?("analyze")
      errors << "#{pilot_workflow_path}: pilot gate must require both producer and analyze jobs"
    end
    gate_steps = Array(gate["steps"])
    gate_values = gate_steps.map { |step| step["env"] if step.is_a?(Hash) }.compact
      .flat_map(&:values)
      .select { |value| value.is_a?(String) }
    unless gate_values.any? { |value| value.include?("needs.#{producer_id}.result") }
      errors << "#{pilot_workflow_path}: pilot gate must inspect the shared producer result"
    end
    gate_scripts = gate_steps.map { |step| step["run"] if step.is_a?(Hash) }.compact.join("\n")
    required_gate_checks = [
      %q([[ "$BUILD_RESULT" == 'success' ]]),
      %q([[ "$ANALYZE_RESULT" == 'success' ]]),
    ]
    unless required_gate_checks.all? { |check| gate_scripts.include?(check) }
      errors << "#{pilot_workflow_path}: pilot gate must require successful producer and analyze jobs"
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
