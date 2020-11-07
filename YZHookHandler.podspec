
Pod::Spec.new do |s|
s.name         = 'YZHookHandler'
s.summary      = 'YZHookHandler uses Objective-C message forwarding to hook into messages.'
s.version      = '0.0.1'
s.license      = { :type => 'MIT', :file => 'LICENSE' }
s.authors      = { 'CancerQ' => 'superyezhqiang@163.com' }
s.social_media_url   = 'https://github.com/CancerQ'
s.homepage     = 'https://github.com/CancerQ/YZHookHandler'
s.platform     = :ios, '8.0'
s.ios.deployment_target = '8.0'
s.source       = { :git => 'https://github.com/CancerQ/YZHookHandler.git', :tag => s.version.to_s }

s.requires_arc = true
s.source_files = 'YZHookHandler/*.{h,m}'

end
