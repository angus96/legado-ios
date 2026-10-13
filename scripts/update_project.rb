#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'Legado.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Legado' }

unless target
  puts "ERROR: Target 'Legado' not found!"
  exit 1
end

exclude_dirs = ['Tests/', 'Widget/', 'ShareExtension/', 'docs/', 'scripts/', '.build/', 'DerivedData/', 'inventory/']

swift_files_on_disk = Dir.glob('**/*.swift').reject { |f|
  exclude_dirs.any? { |dir| f.start_with?(dir) }
}.sort

puts "Found #{swift_files_on_disk.size} Swift files on disk"

removed = 0
added = 0

target.source_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref
  
  path = file_ref.path
  next unless path && path.end_with?('.swift')
  
  unless swift_files_on_disk.include?(path)
    puts "Removing missing file: #{path}"
    build_file.remove_from_project
    file_ref.remove_from_project
    removed += 1
  end
end

project.main_group.recursive_children.each do |child|
  next unless child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
  next unless child.path && child.path.end_with?('.swift')
  next if child.path.start_with?('Tests/')
  
  unless swift_files_on_disk.include?(child.path)
    puts "Removing orphan file ref: #{child.path}"
    child.remove_from_project
    removed += 1
  end
end

existing_paths = target.source_build_phase.files.map { |f| f.file_ref&.path }.compact

swift_files_on_disk.each do |file_path|
  next if existing_paths.include?(file_path)
  
  begin
    file_ref = project.main_group.new_file(file_path)
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added: #{file_path}"
    added += 1
  rescue => e
    puts "Warning: #{file_path}: #{e.message}"
  end
end

test_targets = [
  ['LegadoStabilityTests', :unit_test_bundle, 'Tests/Stability/'],
  ['LegadoUITests', :ui_test_bundle, 'Tests/UI/']
].map do |name, type, directory|
  test_target = project.targets.find { |item| item.name == name } || project.new_target(type, name, :ios, '16.0')
  test_target.add_dependency(target) unless test_target.dependencies.any? { |dependency| dependency.target == target }
  test_target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.legado.#{name}"
    settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    settings['SWIFT_VERSION'] = '5.0'
    settings['TARGETED_DEVICE_FAMILY'] = '1,2'
    settings['CODE_SIGNING_ALLOWED'] = 'NO'
    if type == :unit_test_bundle
      settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Legado.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Legado'
      settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    else
      settings['TEST_TARGET_NAME'] = 'Legado'
    end
  end
  existing = test_target.source_build_phase.files.map { |item| item.file_ref&.path }
  Dir.glob("#{directory}**/*.swift").each do |path|
    next if existing.include?(path)
    reference = project.main_group.recursive_children.find { |child| child.respond_to?(:path) && child.path == path }
    reference ||= project.main_group.new_file(path)
    test_target.source_build_phase.add_file_reference(reference)
  end
  test_target
end

project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.test_action.build_configuration = 'Debug'
test_targets.each do |test_target|
  scheme.add_build_target(test_target, false)
  scheme.add_test_target(test_target)
end
scheme.save_as(project_path, 'Legado', true)
puts "Project saved. Added #{added} file(s), removed #{removed} file(s)."
