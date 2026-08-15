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

issue_forms = Dir.glob(".github/ISSUE_TEMPLATE/*.{yml,yaml}").sort
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

puts "Validated #{yaml_paths.length} YAML files, including #{issue_forms.length} issue forms."
