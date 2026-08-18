#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"

abort "usage: validate-pinned-pilot.rb CASE ANALYSIS PLAN DRY_RUN ROOT REPORT_DIR PORTABLE_ANALYSIS PORTABLE_PLAN" unless ARGV.length == 8

pilot_case, analysis_path, plan_path, dry_run_path, project_root, report_dir,
  portable_analysis_path, portable_plan_path = ARGV
analysis = JSON.parse(File.read(analysis_path, encoding: "UTF-8"))
plan = JSON.parse(File.read(plan_path, encoding: "UTF-8"))
dry_run = File.read(dry_run_path, encoding: "UTF-8")
portable_analysis = JSON.parse(File.read(portable_analysis_path, encoding: "UTF-8"))
portable_plan = JSON.parse(File.read(portable_plan_path, encoding: "UTF-8"))

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

def require_no_auto(errors, records, label)
  automatic = records.select { |_name, record| classification(record) == "AUTO" }.keys.sort
  errors << "#{label} has AUTO dependencies: #{automatic.join(", ")}" unless automatic.empty?
end

def require_auto_set(errors, records, expected, label)
  actual = records.select { |_name, record| classification(record) == "AUTO" }.keys.sort
  expected = expected.sort
  return if actual == expected

  errors << "#{label} expected AUTO #{expected.join(", ")}, got #{actual.join(", ")}"
end

def require_entry_count(errors, records, expected)
  return if records.length == expected

  errors << "expected #{expected} direct dependencies, got #{records.length}"
end

def require_reporting_parity(errors, raw_records, portable_records, label)
  if raw_records.keys.sort != portable_records.keys.sort
    errors << "#{label}: portable output changed dependency identities"
    return
  end

  raw_records.each do |name, raw|
    portable = portable_records.fetch(name)
    errors << "#{label} #{name}: portable classification changed" unless classification(raw) == classification(portable)
    errors << "#{label} #{name}: portable legacy reasons changed" unless Array(raw["reasons"]) == Array(portable["reasons"])
    errors << "#{label} #{name}: portable reasonDetails changed" unless Array(raw["reasonDetails"]) == Array(portable["reasonDetails"])
  end
end

def local_path_variants(path)
  expanded = File.expand_path(path)
  variants = [expanded]

  # Foundation and Xcode may canonicalize macOS' /tmp and /var aliases by
  # dropping the /private prefix even when RUNNER_TEMP retains it. Include
  # both spellings so a report cannot leak a local path through that alias.
  if expanded.start_with?("/private/")
    variants << expanded.delete_prefix("/private")
  elsif expanded.start_with?("/tmp/") || expanded.start_with?("/var/")
    variants << "/private#{expanded}"
  end

  begin
    variants << File.realpath(expanded)
  rescue SystemCallError
    # Some configured roots may not exist. The expanded spelling is still
    # useful and must remain in the replacement set.
  end

  variants.uniq
end

def replacements(project_root)
  home = ENV.fetch("HOME", "")
  runner_temp = ENV.fetch("RUNNER_TEMP", "")
  github_workspace = ENV.fetch("GITHUB_WORKSPACE", "")

  [
    [project_root, "<PILOT_ROOT>"],
    [runner_temp, "<RUNNER_TEMP>"],
    [github_workspace, "<PKGLIFT_ROOT>"],
    [home, "<HOME>"],
  ].reject { |from, _| from.empty? }
    .flat_map { |from, to| local_path_variants(from).map { |variant| [variant, to] } }
    .uniq
    .sort_by { |from, _| -from.length }
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

def contains_secret_bearing_url?(value)
  case value
  when Hash
    value.values.any? { |nested| contains_secret_bearing_url?(nested) }
  when Array
    value.any? { |nested| contains_secret_bearing_url?(nested) }
  when String
    scheme_urls = value.scan(%r{\b[A-Za-z][A-Za-z0-9+.-]*://[^\s"'<>]+})
    scheme_urls.any? do |url|
      url.match?(%r{://[^/\s]*@}) || url.include?("?") || url.include?("#")
    end || value.match?(%r{(?:^|\s)[^@\s]+@[^:\s]+:[^\s]+})
  else
    false
  end
end

candidates = direct_candidates(analysis)
entries = plan_entries(plan)
portable_candidates = direct_candidates(portable_analysis)
portable_entries = plan_entries(portable_plan)
features = analysis.dig("cocoaPods", "podfileFeatures") || {}

errors << "portable analysis marker is missing or unsupported" unless portable_analysis.dig("portableOutput", "version") == 1
errors << "portable plan marker is missing or unsupported" unless portable_plan.dig("portableOutput", "version") == 1
require_reporting_parity(errors, candidates, portable_candidates, "analysis")
require_reporting_parity(errors, entries, portable_entries, "plan")

case pilot_case
when "positive"
  require_classification(errors, candidates, "SDWebImage", "AUTO")
  require_classification(errors, entries, "SDWebImage", "AUTO")
  require_not_auto(errors, candidates, "AmazonIVSPlayer")
  require_not_auto(errors, entries, "AmazonIVSPlayer")
when "mixed"
  %w[Alamofire Kingfisher lottie-ios].each do |name|
    require_classification(errors, candidates, name, "AUTO")
    require_classification(errors, entries, name, "AUTO")
  end
  require_auto_set(errors, candidates, %w[Alamofire Kingfisher lottie-ios], "Loodos analysis")
  require_auto_set(errors, entries, %w[Alamofire Kingfisher lottie-ios], "Loodos plan")

  require_classification(errors, candidates, "Firebase/RemoteConfig", "REVIEW")
  require_classification(errors, entries, "Firebase/RemoteConfig", "REVIEW")
  ["Firebase/Analytics", "Firebase/Core"].each do |name|
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
when "tinode"
  require_entry_count(errors, candidates, 11)
  require_entry_count(errors, entries, 11)
  require_no_auto(errors, candidates, "Tinode analysis")
  require_no_auto(errors, entries, "Tinode plan")
  errors << "expected dynamic Ruby detection" unless features["hasDynamicRuby"] == true
  errors << "expected post_install detection" unless features["hasPostInstallHook"] == true
when "xcodebenchmark"
  require_entry_count(errors, candidates, 42)
  require_entry_count(errors, entries, 42)
  require_no_auto(errors, candidates, "XcodeBenchmark analysis")
  require_no_auto(errors, entries, "XcodeBenchmark plan")
  errors << "expected dynamic Ruby detection" unless features["hasDynamicRuby"] == true
  errors << "expected post_install detection" unless features["hasPostInstallHook"] == true
  %w[FirebaseAuth FirebaseFirestore FirebaseRemoteConfig FirebaseStorage lottie-ios].each do |name|
    require_classification(errors, candidates, name, "REVIEW")
    require_classification(errors, entries, name, "REVIEW")
  end
when "hammerspoon"
  require_entry_count(errors, candidates, 10)
  require_entry_count(errors, entries, 10)
  require_no_auto(errors, candidates, "Hammerspoon analysis")
  require_no_auto(errors, entries, "Hammerspoon plan")
  errors << "expected dynamic Ruby detection" unless features["hasDynamicRuby"] == true
  errors << "expected post_install detection" unless features["hasPostInstallHook"] == true
when "acknowlist"
  require_entry_count(errors, candidates, 1)
  require_entry_count(errors, entries, 1)
  require_classification(errors, candidates, "AcknowList", "BLOCKED")
  require_classification(errors, entries, "AcknowList", "BLOCKED")
  require_no_auto(errors, candidates, "AcknowList analysis")
  require_no_auto(errors, entries, "AcknowList plan")
when "fastlane"
  require_classification(errors, candidates, "HexColors", "UNKNOWN")
  require_classification(errors, entries, "HexColors", "UNKNOWN")
  require_no_auto(errors, candidates, "fastlane analysis")
  require_no_auto(errors, entries, "fastlane plan")
when "firebaseui"
  require_classification(errors, candidates, "Firebase/Auth", "REVIEW")
  require_classification(errors, entries, "Firebase/Auth", "REVIEW")
  require_no_auto(errors, candidates, "FirebaseUI analysis")
  require_no_auto(errors, entries, "FirebaseUI plan")
when "firebaseauth"
  %w[FirebaseAnalytics FirebaseAuth].each do |name|
    require_classification(errors, candidates, name, "REVIEW")
    require_classification(errors, entries, name, "REVIEW")
  end
  require_no_auto(errors, candidates, "Firebase Legacy Auth analysis")
  require_no_auto(errors, entries, "Firebase Legacy Auth plan")
else
  errors << "unknown pilot case #{pilot_case.inspect}"
end

candidates.each do |name, candidate|
  next unless entries.key?(name)
  entry = entries.fetch(name)

  if classification(candidate) != classification(entry)
    errors << "#{name}: analysis classification #{classification(candidate).inspect} does not match plan #{classification(entry).inspect}"
  end
  if Array(candidate["reasons"]) != Array(entry["reasons"])
    errors << "#{name}: analysis legacy reasons do not match plan reasons"
  end
  if Array(candidate["reasonDetails"]) != Array(entry["reasonDetails"])
    errors << "#{name}: analysis reasonDetails do not match plan reasonDetails"
  end
end

candidates.each do |name, candidate|
  details = Array(candidate["reasonDetails"])
  next if details.empty?

  detailed_messages = details.map { |detail| detail["message"] }
  legacy_messages = Array(candidate["reasons"])
  errors << "#{name}: reasonDetails messages do not preserve legacy reasons" unless detailed_messages == legacy_messages
end

errors << "dry-run mutation check was not confirmed" unless ENV["PILOT_DRY_RUN_CLEAN"] == "true"

substitutions = replacements(project_root)
redacted_analysis = redact(portable_analysis, substitutions)
redacted_plan = redact(portable_plan, substitutions)
redacted_dry_run = redact_text(dry_run, substitutions)

redacted_payload = JSON.generate([redacted_analysis, redacted_plan, redacted_dry_run])
leaked_local_paths = substitutions.map(&:first).select { |path| redacted_payload.include?(path) }
unless leaked_local_paths.empty?
  errors << "redacted pilot artifact still contains #{leaked_local_paths.length} local path value(s)"
end
if contains_secret_bearing_url?([redacted_analysis, redacted_plan, redacted_dry_run])
  errors << "redacted pilot artifact still contains secret-bearing URL components"
end

if errors.empty?
  File.write(File.join(report_dir, "analysis.json"), JSON.pretty_generate(redacted_analysis) + "\n")
  File.write(File.join(report_dir, "plan.json"), JSON.pretty_generate(redacted_plan) + "\n")
  File.write(File.join(report_dir, "dry-run.txt"), redacted_dry_run)
end

rows = candidates.keys.sort.map do |name|
  candidate = candidates.fetch(name)
  version = candidate.dig("pod", "version") || "—"
  "| `#{name}` | `#{version}` | **#{classification(candidate)}** |"
end
rows << "| — | — | No direct dependencies parsed |" if rows.empty?

reason_code_counts = Hash.new(0)
candidates.each_value do |candidate|
  Array(candidate["reasonDetails"]).each do |detail|
    code = detail["code"] || "missing_code"
    reason_code_counts[code] += 1
  end
end
reason_rows = reason_code_counts.keys.sort.map do |code|
  "| `#{code}` | #{reason_code_counts.fetch(code)} |"
end
reason_rows << "| — | 0 |" if reason_rows.empty?

summary = <<~MARKDOWN
  # PkgLift pinned pilot: #{pilot_case}

  - Tracking reference: `#{ENV.fetch("PILOT_ISSUE", "unknown")}`
  - Repository: `#{ENV.fetch("PILOT_REPOSITORY", "unknown")}`
  - Commit: `#{ENV.fetch("PILOT_COMMIT", "unknown")}`
  - Project root: `#{ENV.fetch("PILOT_ROOT", ".")}`
  - Workspace: `#{ENV.fetch("PILOT_WORKSPACE", "unknown") == "-" ? "none (explicit project selection)" : ENV.fetch("PILOT_WORKSPACE", "unknown")}`
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

  ## Classification reason codes

  | Reason code | Direct-candidate occurrences |
  |---|---:|
  #{reason_rows.join("\n")}
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
