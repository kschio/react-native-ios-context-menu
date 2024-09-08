require 'json'

package = JSON.parse(File.read(File.join(__dir__, './', 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'ReactNativeIosContextMenu'
  s.version        = package['version']
  s.summary        = package['description']
  s.description    = package['description']
  s.license        = package['license']
  s.author         = package['author']
  s.homepage       = package['homepage']
  s.platform       = :ios, '15.1'
  s.swift_version  = '5.4'
  s.source         = { git: 'https://github.com/dominicstop/react-native-ios-context-menu' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.dependency 'ReactNativeIosUtilities'
  s.dependency 'DGSwiftUtilities'

  s.dependency 'ContextMenuAuxiliaryPreview', '~> 0.3'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }
  
  s.source_files = "ios/**/*.{h,m,swift}"
end
