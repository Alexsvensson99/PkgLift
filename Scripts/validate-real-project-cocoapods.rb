#!/usr/bin/env ruby
# frozen_string_literal: true

# Read project metadata and reconstruct scripts with the reviewed CocoaPods
# generator. This never installs pods, saves a project, or runs a build script.
require 'json'
require 'digest'
require 'pathname'

module G3CocoaPods
  VERSION = '1.17.0'
  GENERATORS = {
    'generator/embed_frameworks_script.rb' => 'e90b10b5f9f0b90b1331b22c853bfbca1b5f09ec9efff7d719b7883d84a75e3e',
    'generator/copy_xcframework_script.rb' => 'db32ea8fe1ebafe9c680288914af646d88311dab0c381470c1768e874be6294c',
    'generator/script_phase_constants.rb' => '5e7965c3e90964ff316e9efaf3a4c0893f7b349350ac1bf60f02e60c8489a7cb'
  }.freeze
  MANIFEST_BODY = <<~'SH'
    diff "${PODS_PODFILE_DIR_PATH}/Podfile.lock" "${PODS_ROOT}/Manifest.lock" > /dev/null
    if [ $? != 0 ] ; then
        # print error to STDERR
        echo "error: The sandbox is not in sync with the Podfile.lock. Run 'pod install' or update your CocoaPods installation." >&2
        exit 1
    fi
    # This output is used by Xcode 'outputs' to avoid re-running this script phase.
    echo "SUCCESS" > "${SCRIPT_OUTPUT_FILE_0}"
  SH
  EMBED_BODY = "\"${PODS_ROOT}/Target Support Files/Pods-Grid Feed/Pods-Grid Feed-frameworks.sh\"\n"
  COPY_BODY = "\"${PODS_ROOT}/Target Support Files/AmazonIVSPlayer/AmazonIVSPlayer-xcframeworks.sh\"\n"

  def self.require_condition(condition, message)
    raise message unless condition
  end

  def self.regular_file(root, relative)
    path = root.join(relative)
    require_condition(path.file? && !path.symlink?, "Missing or symlinked reviewed input: #{relative}")
    require_condition(path.realpath.to_s.start_with?(root.realpath.to_s + '/'), 'Escaping reviewed input')
    path
  end

  def self.validate_libraries(info)
    libraries = info.fetch('AvailableLibraries')
    require_condition(libraries.is_a?(Array) && !libraries.empty?, 'Missing XCFramework slices')
    identifiers = libraries.map { |slice| slice.fetch('LibraryIdentifier') }
    require_condition(identifiers.uniq == identifiers, 'Duplicate XCFramework slice')
    libraries.each do |slice|
      require_condition(slice['LibraryIdentifier'].match?(/\A[a-z0-9_+-]+\z/), 'Unsafe XCFramework slice identifier')
      require_condition(slice['LibraryPath'] == 'AmazonIVSPlayer.framework', 'Unexpected framework path')
      require_condition(%w[ios tvos macos watchos xros].include?(slice['SupportedPlatform']), 'Unexpected slice platform')
      require_condition([nil, 'simulator', 'maccatalyst'].include?(slice['SupportedPlatformVariant']), 'Unexpected slice variant')
      architectures = slice['SupportedArchitectures']
      require_condition(architectures.is_a?(Array) && !architectures.empty? &&
                        (architectures - %w[arm64 arm64e x86_64 i386 armv7 armv7s armv7k arm64_32]).empty?, 'Unexpected slice architectures')
    end
    require_condition(libraries.any? { |s| s['SupportedPlatform'] == 'ios' &&
      s['SupportedPlatformVariant'] == 'simulator' && s['SupportedArchitectures'].include?('arm64') }, 'No arm64 iOS simulator slice')
    libraries
  end

  def self.validate_shells(document, expected)
    objects = document.fetch('objects')
    shells = objects.select { |_id, value| value['isa'] == 'PBXShellScriptBuildPhase' }
    require_condition(shells.length == expected.length, 'Unexpected project shell phase count')
    observed = {}
    shells.each do |id, phase|
      name = phase['name']
      require_condition(expected.key?(name) && !observed.key?(name), 'Unexpected or duplicate shell phase')
      require_condition(phase['shellPath'] == '/bin/sh' && phase['shellScript'] == expected.fetch(name), 'Unreviewed shell phase body')
      owners = objects.values.select { |o| %w[PBXNativeTarget PBXAggregateTarget].include?(o['isa']) && Array(o['buildPhases']).include?(id) }
      expected_owner = name == '[CP] Copy XCFrameworks' ? 'AmazonIVSPlayer' : 'Grid Feed'
      expected_type = name == '[CP] Copy XCFrameworks' ? 'PBXAggregateTarget' : 'PBXNativeTarget'
      require_condition(owners.length == 1 && owners.first['name'] == expected_owner && owners.first['isa'] == expected_type,
                        'Shell phase has wrong target owner')
      observed[name] = phase
    end
    observed
  end

  def self.validate_phase_lists(phase, stem)
    prefix = '${PODS_ROOT}/Target Support Files/'
    require_condition(phase['inputFileListPaths'] == [prefix + stem + '-input-files.xcfilelist'] &&
                      phase['outputFileListPaths'] == [prefix + stem + '-output-files.xcfilelist'],
                      'Missing or changed phase file-list contract')
    require_condition(Array(phase['inputPaths']).empty? && Array(phase['outputPaths']).empty?,
                      'Unexpected direct phase paths')
  end

  def self.compare_script(path, expected)
    expected += "\n" unless expected.end_with?("\n") # CocoaPods save_as uses puts.
    require_condition(path.binread == expected.b, 'Generated script differs from reviewed generator output')
    Digest::SHA256.file(path).hexdigest
  end

  def self.load_generator
    begin
      gem 'cocoapods', "= #{VERSION}"
    rescue Gem::LoadError
      # Homebrew's pod wrapper uses this isolated GEM_HOME. Do not evaluate that
      # wrapper or discover Ruby code from the upstream checkout.
      installed = "/opt/homebrew/Cellar/cocoapods/#{VERSION}/libexec"
      raise unless File.directory?(installed)
      Gem.use_paths(installed, [installed, *Gem.path])
      gem 'cocoapods', "= #{VERSION}"
    end
    gem_root = Pathname(Gem.loaded_specs.fetch('cocoapods').full_gem_path).join('lib/cocoapods')
    GENERATORS.each do |relative, expected|
      require_condition(Digest::SHA256.file(gem_root.join(relative)).hexdigest == expected,
                        "CocoaPods generator bytes changed: #{relative}")
    end
    require 'cocoapods'
    require 'cocoapods/generator/embed_frameworks_script'
    require 'cocoapods/generator/copy_xcframework_script'
    require 'cocoapods/generator/script_phase_constants'
    require_condition(Pod::VERSION == VERSION, 'Wrong CocoaPods version')
  end

  def self.run(root)
    root = Pathname(root).realpath
    load_generator
    app_path = regular_file(root, 'Grid Feed.xcodeproj/project.pbxproj')
    pods_path = regular_file(root, 'Pods/Pods.xcodeproj/project.pbxproj')
    app = Xcodeproj::Plist.read_from_path(app_path)
    pods = Xcodeproj::Plist.read_from_path(pods_path)
    app_phases = validate_shells(app, '[CP] Check Pods Manifest.lock' => MANIFEST_BODY,
                               '[CP] Embed Pods Frameworks' => EMBED_BODY)
    pod_phases = validate_shells(pods, '[CP] Copy XCFrameworks' => COPY_BODY)
    manifest_phase = app_phases.fetch('[CP] Check Pods Manifest.lock')
    require_condition(manifest_phase['inputPaths'] == ['${PODS_PODFILE_DIR_PATH}/Podfile.lock', '${PODS_ROOT}/Manifest.lock'] &&
                      manifest_phase['outputPaths'] == ['$(DERIVED_FILE_DIR)/Pods-Grid Feed-checkManifestLockResult.txt'],
                      'Manifest phase input/output paths changed')
    validate_phase_lists(app_phases.fetch('[CP] Embed Pods Frameworks'), 'Pods-Grid Feed/Pods-Grid Feed-frameworks-${CONFIGURATION}')
    validate_phase_lists(pod_phases.fetch('[CP] Copy XCFrameworks'), 'AmazonIVSPlayer/AmazonIVSPlayer-xcframeworks')
    require_condition(Array(manifest_phase['inputFileListPaths']).empty? && Array(manifest_phase['outputFileListPaths']).empty?, 'Unexpected manifest file lists')
    framework_path = root.join('Pods/AmazonIVSPlayer/AmazonIVSPlayer.xcframework')
    info_path = regular_file(root, framework_path.relative_path_from(root).join('Info.plist'))
    libraries = validate_libraries(Xcodeproj::Plist.read_from_path(info_path))
    libraries.each do |library|
      regular_file(root, framework_path.relative_path_from(root).join(library['LibraryIdentifier'],
                   'AmazonIVSPlayer.framework/AmazonIVSPlayer'))
    end
    framework = Pod::Xcode::XCFramework.new('AmazonIVSPlayer', framework_path)
    require_condition(framework.build_type.dynamic_framework?, 'Expected a dynamic Amazon framework')
    configs = app.fetch('objects').values.select { |v| v['isa'] == 'XCBuildConfiguration' }.map { |v| v['name'] }.uniq.sort
    require_condition(configs == %w[Debug Release], 'Unreviewed build configurations')
    embed = Pod::Generator::EmbedFrameworksScript.new({}, configs.to_h { |c| [c, [framework]] }).generate
    copy = Pod::Generator::CopyXCFrameworksScript.new([framework], root.join('Pods'), Pod::Platform.new(:ios, '14.0')).generate
    scripts = {
      'Pods/Target Support Files/Pods-Grid Feed/Pods-Grid Feed-frameworks.sh' => embed,
      'Pods/Target Support Files/AmazonIVSPlayer/AmazonIVSPlayer-xcframeworks.sh' => copy
    }.to_h { |path, expected| [path, compare_script(regular_file(root, path), expected)] }
    # Match the complete CP 1.17 file-list contents for the selected dynamic
    # framework; missing and extra paths must not silently alter build ordering.
    expected_lists = {}
    %w[Debug Release].each do |configuration|
      prefix = "Pods/Target Support Files/Pods-Grid Feed/Pods-Grid Feed-frameworks-#{configuration}"
      expected_lists[prefix + '-input-files.xcfilelist'] = [
        '${PODS_ROOT}/Target Support Files/Pods-Grid Feed/Pods-Grid Feed-frameworks.sh',
        '${PODS_XCFRAMEWORKS_BUILD_DIR}/AmazonIVSPlayer/AmazonIVSPlayer.framework/AmazonIVSPlayer'
      ]
      expected_lists[prefix + '-output-files.xcfilelist'] = ['${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/AmazonIVSPlayer.framework']
    end
    prefix = 'Pods/Target Support Files/AmazonIVSPlayer/AmazonIVSPlayer-xcframeworks'
    expected_lists[prefix + '-input-files.xcfilelist'] = [
      '${PODS_ROOT}/Target Support Files/AmazonIVSPlayer/AmazonIVSPlayer-xcframeworks.sh',
      '${PODS_ROOT}/AmazonIVSPlayer/AmazonIVSPlayer.xcframework'
    ]
    expected_lists[prefix + '-output-files.xcfilelist'] = ['${PODS_XCFRAMEWORKS_BUILD_DIR}/AmazonIVSPlayer/AmazonIVSPlayer.framework']
    lists = expected_lists.to_h do |relative, expected|
      path = regular_file(root, relative)
      require_condition(path.read.lines.map(&:strip) == expected, 'Generated file-list contents changed')
      [relative, Digest::SHA256.file(path).hexdigest]
    end
    { schemaVersion: 1, status: 'passed', cocoaPods: VERSION, generatorSHA256: GENERATORS,
      scriptSHA256: scripts, fileListSHA256: lists, xcframeworkInfoSHA256: Digest::SHA256.file(info_path).hexdigest,
      libraryIdentifiers: libraries.map { |l| l['LibraryIdentifier'] },
      appPhaseNames: app_phases.keys.sort, podsPhaseNames: pod_phases.keys.sort }
  end
end

if $PROGRAM_NAME == __FILE__
  abort 'usage: validate-real-project-cocoapods.rb DISPOSABLE_AWS_ROOT' unless ARGV.length == 1
  puts JSON.pretty_generate(G3CocoaPods.run(ARGV.fetch(0)))
end
