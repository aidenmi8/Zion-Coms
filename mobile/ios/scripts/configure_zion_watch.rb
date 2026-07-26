#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

IOS_DIRECTORY = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(IOS_DIRECTORY, "Runner.xcodeproj")
WATCH_SOURCE_NAMES = %w[
  ZionWatchApp.swift
  WatchInboxStore.swift
  WatchInboxCache.swift
  WatchConnectivityClient.swift
  WatchTheme.swift
  FocusedQueueView.swift
  ApprovalDetailView.swift
  MessageDetailView.swift
  PassAgentPickerView.swift
  ActionConfirmationView.swift
].freeze
WATCH_TEST_NAMES = %w[
  WatchInboxStoreTests.swift
  WatchInboxCacheTests.swift
].freeze

def ensure_group(parent, name)
  parent.groups.find { |group| group.display_name == name } ||
    parent.new_group(name, name)
end

def ensure_file(group, path)
  group.files.find { |file| file.path == path } || group.new_file(path)
end

def ensure_source(target, file)
  return if target.source_build_phase.files_references.include?(file)

  target.source_build_phase.add_file_reference(file, true)
end

def ensure_resource(target, file)
  return if target.resources_build_phase.files_references.include?(file)

  target.resources_build_phase.add_file_reference(file, true)
end

def ensure_profile_configuration(project, target)
  return if target.build_configurations.any? { |configuration| configuration.name == "Profile" }

  release = target.build_configurations.find { |configuration| configuration.name == "Release" }
  profile = project.new(Xcodeproj::Project::Object::XCBuildConfiguration)
  profile.name = "Profile"
  profile.build_settings = release.build_settings.dup
  profile.base_configuration_reference = release.base_configuration_reference
  target.build_configuration_list.build_configurations << profile
end

def configure_watch_target(target, base_configuration)
  target.build_configurations.each do |configuration|
    configuration.base_configuration_reference = base_configuration
    configuration.build_settings.merge!(
      "CODE_SIGN_STYLE" => "Automatic",
      "CURRENT_PROJECT_VERSION" => "$(FLUTTER_BUILD_NUMBER)",
      "ENABLE_PREVIEWS" => "YES",
      "GENERATE_INFOPLIST_FILE" => "YES",
      "INFOPLIST_KEY_CFBundleDisplayName" => "Zion",
      "INFOPLIST_KEY_WKApplication" => "YES",
      "INFOPLIST_KEY_WKCompanionAppBundleIdentifier" => "$(BUNDLE_IDENTIFIER)",
      "INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp" => "NO",
      "LD_RUNPATH_SEARCH_PATHS" => "$(inherited) @executable_path/Frameworks",
      "MARKETING_VERSION" => "$(FLUTTER_BUILD_NAME)",
      "PRODUCT_BUNDLE_IDENTIFIER" => "$(BUNDLE_IDENTIFIER).watchkitapp",
      "PRODUCT_NAME" => "$(TARGET_NAME)",
      "SDKROOT" => "watchos",
      "SKIP_INSTALL" => "YES",
      "SUPPORTED_PLATFORMS" => "watchos watchsimulator",
      "SWIFT_EMIT_LOC_STRINGS" => "YES",
      "SWIFT_VERSION" => "5.0",
      "TARGETED_DEVICE_FAMILY" => "4",
      "WATCHOS_DEPLOYMENT_TARGET" => "26.0"
    )
  end
end

def configure_test_target(target, base_configuration)
  target.build_configurations.each do |configuration|
    configuration.base_configuration_reference = base_configuration
    configuration.build_settings.merge!(
      "BUNDLE_LOADER" => "$(TEST_HOST)",
      "CODE_SIGN_STYLE" => "Automatic",
      "CURRENT_PROJECT_VERSION" => "1",
      "GENERATE_INFOPLIST_FILE" => "YES",
      "LD_RUNPATH_SEARCH_PATHS" =>
        "$(inherited) @executable_path/Frameworks @loader_path/Frameworks",
      "MARKETING_VERSION" => "1.0",
      "PRODUCT_BUNDLE_IDENTIFIER" => "$(BUNDLE_IDENTIFIER).watchkitapp.tests",
      "PRODUCT_NAME" => "$(TARGET_NAME)",
      "SDKROOT" => "watchos",
      "SUPPORTED_PLATFORMS" => "watchos watchsimulator",
      "SWIFT_VERSION" => "5.0",
      "TARGETED_DEVICE_FAMILY" => "4",
      "TEST_HOST" =>
        "$(BUILT_PRODUCTS_DIR)/ZionWatch.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ZionWatch",
      "WATCHOS_DEPLOYMENT_TARGET" => "26.0"
    )
  end
end

project = Xcodeproj::Project.open(PROJECT_PATH)
runner = project.targets.find { |target| target.name == "Runner" }
abort("Runner target is missing") unless runner

watch = project.targets.find { |target| target.name == "ZionWatch" } ||
  project.new_target(:application, "ZionWatch", :watchos, "26.0")
watch_tests = project.targets.find { |target| target.name == "ZionWatchTests" } ||
  project.new_target(:unit_test_bundle, "ZionWatchTests", :watchos, "26.0")
watch.product_type = Xcodeproj::Constants::PRODUCT_TYPE_UTI[:application]

ensure_profile_configuration(project, watch)
ensure_profile_configuration(project, watch_tests)

flutter_group = project.main_group.groups.find { |group| group.display_name == "Flutter" }
abort("Flutter group is missing") unless flutter_group
watch_configuration_references = project.files.select do |file|
  File.basename(file.path.to_s) == "Watch.xcconfig"
end
watch_configuration =
  watch_configuration_references.min_by(&:uuid) ||
  ensure_file(flutter_group, "Watch.xcconfig")
project.targets.flat_map(&:build_configurations).each do |configuration|
  next unless watch_configuration_references.include?(
    configuration.base_configuration_reference
  )

  configuration.base_configuration_reference = watch_configuration
end
(watch_configuration_references - [watch_configuration]).each(&:remove_from_project)
unless flutter_group.children.include?(watch_configuration)
  flutter_group.children << watch_configuration
end
watch_configuration.name = "Watch.xcconfig"
watch_configuration.path = "Flutter/Watch.xcconfig"
configure_watch_target(watch, watch_configuration)
configure_test_target(watch_tests, watch_configuration)

target_attributes = project.root_object.attributes["TargetAttributes"] ||= {}
target_attributes[watch.uuid] ||= {
  "CreatedOnToolsVersion" => Xcodeproj::Constants::LAST_KNOWN_IOS_SDK.to_s
}
target_attributes[watch_tests.uuid] ||= {
  "CreatedOnToolsVersion" => Xcodeproj::Constants::LAST_KNOWN_IOS_SDK.to_s
}
target_attributes[watch_tests.uuid]["TestTargetID"] = watch.uuid

watch_group = ensure_group(project.main_group, "ZionWatch")
WATCH_SOURCE_NAMES.each do |name|
  ensure_source(watch, ensure_file(watch_group, name))
end
assets = ensure_file(watch_group, "Assets.xcassets")
ensure_resource(watch, assets)

test_group = ensure_group(project.main_group, "ZionWatchTests")
WATCH_TEST_NAMES.each do |name|
  ensure_source(watch_tests, ensure_file(test_group, name))
end

shared_group = project.main_group.groups.find { |group| group.display_name == "Shared" }
abort("Shared group is missing") unless shared_group
shared_models = ensure_file(shared_group, "WatchWireModels.swift")
ensure_source(watch, shared_models)

runner.add_dependency(watch) unless runner.dependencies.any? { |dependency| dependency.target == watch }
watch_tests.add_dependency(watch) unless watch_tests.dependencies.any? do |dependency|
  dependency.target == watch
end

embed_phase = runner.copy_files_build_phases.find do |phase|
  phase.name == "Embed Watch Content"
end || runner.new_copy_files_build_phase("Embed Watch Content")
embed_phase.dst_path = "$(CONTENTS_FOLDER_PATH)/Watch"
embed_phase.dst_subfolder_spec = "16"
unless embed_phase.files_references.include?(watch.product_reference)
  build_file = embed_phase.add_file_reference(watch.product_reference, true)
  build_file.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }
end
runner.build_phases.delete(embed_phase)
final_script_index = runner.build_phases.index do |phase|
  ["Thin Binary", "[CP] Embed Pods Frameworks"].include?(phase.display_name)
end
runner.build_phases.insert(final_script_index || runner.build_phases.length, embed_phase)

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(watch)
scheme.add_test_target(watch_tests)
scheme.set_launch_target(watch)
scheme.save_as(PROJECT_PATH, "ZionWatch", true)

puts "Configured ZionWatch and ZionWatchTests."
