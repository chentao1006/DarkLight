require 'xcodeproj'
project_path = "safari/Dark Light/Dark Light.xcodeproj"
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Dark Light Extension' }
if !target
  puts "Target 'Dark Light Extension' not found."
  exit 1
end

# Find the Resources group under Dark Light Extension
ext_group = project.main_group.find_subpath(File.join('Dark Light Extension', 'Resources'), false)
if !ext_group
  puts "Group 'Dark Light Extension/Resources' not found."
  exit 1
end

# Check if file is already in the group
file_ref = ext_group.files.find { |f| f.path == 'i18n.js' }
unless file_ref
  file_ref = ext_group.new_file('i18n.js')
  puts "Added i18n.js to group."
end

# Check if file is in the Resources build phase
resources_build_phase = target.resources_build_phase
unless resources_build_phase.files_references.include?(file_ref)
  resources_build_phase.add_file_reference(file_ref)
  puts "Added i18n.js to Resources Build Phase."
end

project.save
puts "Successfully saved project."
