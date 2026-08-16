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
  ".github/workflows/registry.yml" => "name: Registry Gate",
  ".github/workflows/pilots.yml" => "name: Pinned Pilot Gate",
  ".github/workflows/positive-e2e.yml" => "name: Mixed-Language Pilot Gate",
  ".github/workflows/codeql.yml" => "name: CodeQL",
}.freeze
required_gates.each do |path, marker|
  unless File.file?(path) && File.read(path, encoding: "UTF-8").include?(marker)
    errors << "#{path}: missing required stable gate #{marker.inspect}"
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
