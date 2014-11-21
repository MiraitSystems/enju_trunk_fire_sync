$:.push File.expand_path("../lib", __FILE__)

# Maintain your gem's version:
require "enju_trunk_fire_sync/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |s|
  s.name        = "enju_trunk_fire_sync"
  s.version     = EnjuTrunkFireSync::VERSION
  s.authors     = ["Akifumi NAKAMURA"]
  s.email       = ["nakamura.akifumi@miraitsystems.jp"]
  s.homepage    = "https://github.com/MiraitSystems/enju_trunk_fire_sync"
  s.summary     = "data synchronization program for enju trunk"
  s.description = "EnjuTrunkFireSync."

  s.files = Dir["{app,config,db,lib}/**/*"] + ["MIT-LICENSE", "Rakefile", "README.md"]
  s.test_files = Dir["spec/**/*"] - Dir["spec/dummy/log/*"] 

  s.add_dependency 'rails', '~> 3.2.15'
  s.add_dependency 'actionmailer'
  s.add_dependency 'activesupport'
  #s.add_dependency "enju_trunk"

  s.add_development_dependency "sqlite3"
  s.add_development_dependency 'rspec-rails'
end
