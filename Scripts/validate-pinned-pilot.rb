#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"

abort "usage: validate-pinned-pilot.rb CASE ANALYSIS PLAN DRY_RUN ROOT REPORT_DIR" unless ARGV.length == 6

pilot_case, analysis_path, plan_path, dry_run_path, project_root, report_dir = ARGV
analysis = JSON.parse(File.read(analysis_path, encoding: "UTF-8"))
plan = JSON.parse(File.read(plan_path, encoding: "UTF-8"))
dry_run = File.read(dry_run_path, encoding: "UTF-8")

FileUtils.mkdir_p(report_dir)
errors = []

def direct_candidates(analysis)
  Array(analysis["candidates"])
    .select { |candidate| candidate.dig("pod", "isDirect") == true }
    .each_with_object({}) do |candidate, result|
      name = candidate.dig("pod", "name")
      result[name] = candidate if name
    end
end

def plan_entries(plan)
  Array(plan["entries"]).each_with_object({}) do |entry, result|
    name = entry["podName"]
    result[name] = entry if name
  end
end

def classification(record)
  record && record["classification"]
end

def require_classification(errors, records, name, expected)
  actual = classification(records[name])
  errors << "#{name}: expected #{expected}, got #{actual.inspect}" unless actual == expected
end

def require_not_auto(errors, records, name)
  actual = classification(records[name])
  if actual.nil?
    errors << "#{name}: dependency was not present"
  elsif actual == "AUTO"
    errors << "#{name}: unexpectedly classified AUTO"
  end
end

def replacements(project_root)
  home = ENV.fetch("HOME", "")
  runner_temp = ENV.fetch("RUNNER_TEMP", "")
  github_workspace = ENV.fetch("GITHUB_WORKSPACE", "")

  [
    [File.expand_path(project_root), "<PILOT_ROOT>"],
    [runner_temp, "<RUNNER_TEMP>"],
    [github_workspace, "<PKGLIFT_ROOT>"],
    [home, "<HOME>"],
  ].reject { |from, _| from.empty? }.sort_by { |from, _| -from.length }
end

def redact(value, substitutions)
  case value
  when Hash
    value.transform_values { |nested| redact(nested, substitutions) }
  when Array
    value.map { |nested| redact(nested, substitutions) }
  when String
    substitutions.reduce(value) { |result, (from, to)| result.gsub(from, to) }
  else
    value
  end
end

def redact_text(text, substitutions)
  substitutions.reduce(text) { |result, (from, to)| result.gsub(from, to) }
end

candidates = direct_candidates(analysis)
entries = plan_entries(plan)
features = analysis.dig("cocoaPods", "podfileFeatures") || {}

case pilot_case
when "positive"
  require_classification(errors, candidates, "SDWebImage", "AUTO")
  require_classification(errors, entries, "SDWebImage", "AUTO")
  require_not_auto(errors, candidates, "AmazonIVSPlayer")
  require_not_auto(errors, entries, "AmazonIVSPlayer")
when "mixed"
  %w[Alamofire Kingfisher].each do |name|
    require_classification(errors, candidates, name, "AUTO")
    require_classification(errors, entries, name, "AUTO")
  end

  ["Firebase/Analytics", "Firebase/RemoteConfig", "Firebase/Core", "lottie-ios"].each do |name|
    require_not_auto(errors, candidates, name)
    require_not_auto(errors, entries, name)
  end
when "negative"
  errors << "expected dynamic Ruby detection" unless features["hasDynamicRuby"] == true
  errors << "expected post_install detection" unless features["hasPostInstallHook"] == true

  auto_candidates = candidates.select { |_name, candidate| classification(candidate) == "AUTO" }.keys
  auto_entries = entries.select { |_name, entry| classification(entry) == "AUTO" }.keys
  errors << "negative pilot has AUTO candidates: #{auto_candidates.join(", ")}" unless auto_candidates.empty?
  errors << "negative pilot has AUTO plan entries: #{auto_entries.join(", ")}" unless auto_entries.empty?
else
  errors << "unknown pilot case #{pilot_case.inspect}"
end

candidates.each do |name, candidate|
  next unless entries.key?(name)
  next if classification(candidate) == classification(entries[name])

  errors << "#{name}: analysis classification #{classification(candidate).inspect} does not match plan #{classification(entries[name]).inspect}"
end

errors << "dry-run mutation check was not confirmed" unless ENV["PILOT_DRY_RUN_CLEAN"] == "true"

substitutions = replacements(project_root)
redacted_analysis = redact(analysis, substitutions)
redacted_plan = redact(plan, substitutions)
redacted_dry_run = redact_text(dry_run, substitutions)

File.write(File.join(report_dir, "analysis.json"), JSON.pretty_generate(redacted_analysis) + "\n")
File.write(File.join(report_dir, "plan.json"), JSON.pretty_generate(redacted_plan) + "\n")
File.write(File.join(report_dir, "dry-run.txt"), redacted_dry_run)

rows = candidates.keys.sort.map do |name|
  candidate = candidates.fetch(name)
  version = candidate.dig("pod", "version") || "—"
  "| `#{name}` | `#{version}` | **#{classification(candidate)}** |"
end
rows << "| — | — | No direct dependencies parsed |" if rows.empty?

summary = <<~MARKDOWN
  # PkgLift pinned pilot: #{pilot_case}

  - Tracking issue: ##{ENV.fetch("PILOT_ISSUE", "unknown")}
  - Repository: `#{ENV.fetch("PILOT_REPOSITORY", "unknown")}`
  - Commit: `#{ENV.fetch("PILOT_COMMIT", "unknown")}`
  - Workspace: `#{ENV.fetch("PILOT_WORKSPACE", "unknown")}`
  - Project: `#{ENV.fetch("PILOT_PROJECT", "automatic")}`
  - Upstream license metadata: `#{ENV.fetch("PILOT_LICENSE", "unknown")}`
  - Automated phases: analyze, plan, dry run, mutation check
  - Result: **#{errors.empty? ? "PASS" : "FAIL"}**
  - Readiness score: `#{analysis["readinessScore"]}`
  - Dynamic Ruby detected: `#{features["hasDynamicRuby"]}`
  - post_install detected: `#{features["hasPostInstallHook"]}`
  - use_frameworks detected: `#{features["useFrameworks"]}`
  - Dry run left tracked and visible untracked files unchanged: `#{ENV["PILOT_DRY_RUN_CLEAN"]}`

  ## Direct dependency classifications

  | Dependency | Locked version | Classification |
  |---|---:|---|
  #{rows.join("\n")}
MARKDOWN

unless errors.empty?
  summary << "\n## Validation errors\n\n"
  errors.each { |error| summary << "- #{error}\n" }
end

File.write(File.join(report_dir, "summary.md"), summary)

if errors.any?
  warn "Pinned pilot validation failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Pinned pilot #{pilot_case} passed with #{candidates.length} direct dependencies."
