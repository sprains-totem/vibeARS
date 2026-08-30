Pod::Spec.new do |s|
  s.name             = 'OpusVendored'
  s.version          = '0.3.0'
  s.summary          = 'Bundled Opus xcframework (libopus + libopusenc + opusfile)'
  s.description      = 'Vendors the prebuilt Opus.xcframework (libopus, libopusenc, opusfile) inside the repo so vibeARS can encode Opus (.opus/Ogg) on iOS without network downloads.'
  s.homepage         = 'https://github.com/sbooth/opus-binary-xcframework'
  s.license          = { :type => 'BSD-3-Clause' }
  s.author           = { 'vibeARS' => 'dev@vibears.app' }
  s.ios.deployment_target = '14.0'
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'Opus.xcframework'
  s.static_framework = true
  # Force-load the static framework so its ope_*/opus_* symbols survive the
  # linker even though Swift never references them (dart:ffi looks them up at
  # runtime via DynamicLibrary.process()).
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-force_load,${PODS_XCFRAMEWORKS_BUILD_DIR}/OpusVendored/opus.framework/opus'
  }
end