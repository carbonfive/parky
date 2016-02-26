# -*- encoding: utf-8 -*-
$LOAD_PATH << File.dirname(__FILE__) + "/lib"
require 'parky/version'

Gem::Specification.new do |s|
  s.name        = "parky"
  s.version     = Parky::VERSION
  s.authors     = ["Michael Wynholds"]
  s.email       = ["mike@carbonfive.com"]
  s.homepage    = ""
  s.summary     = %q{Parking bot for the Carbon Five LA office}
  s.description = %q{Parking bot for the Carbon Five LA office}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'slack-ruby-client'
  s.add_runtime_dependency 'sqlite3'
  s.add_runtime_dependency 'eventmachine'
  s.add_runtime_dependency 'faye-websocket'
  s.add_runtime_dependency 'tzinfo'
  s.add_runtime_dependency 'tzinfo-data'

  s.add_development_dependency 'rake'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'factory_girl'
end
