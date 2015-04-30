Pod::Spec.new do |s|
  s.name     = 'WFNotificationCenter'
  s.version  = '0.1'
  s.license  = 'MIT'
  s.summary  = 'A notification center for app groups.'
  s.homepage = 'https://github.com/DeskConnect/WFNotificationCenter'
  s.author   = { 'Conrad Kramer' => 'conrad@deskconnect.com' }
  s.source   = { :git => 'https://github.com/DeskConnect/WFNotificationCenter.git',
                 :tag => s.version }
  s.source_files = 'WFNotificationCenter'
  s.requires_arc = true

  s.ios.deployment_target = '7.0'
end
