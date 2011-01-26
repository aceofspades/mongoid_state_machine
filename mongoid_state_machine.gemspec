require File.expand_path("../lib/mongoid/state_machine", __FILE__)

Gem::Specification.new do |s|
  s.name        = "mongoid_state_machine"
  s.version     = Mongoid::StateMachine::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Bruno Azisaka Maciel"]
  s.email       = ["bruno@azisaka.com.br"]
  s.homepage    = "https://github.com/azisaka/mongoid_state_machine"
  s.summary     = "A fork from the original State Machine to run on top of Mongoid"
  s.description = "A fork from the original State Machine to run on top of Mongoid"

  s.required_rubygems_version = ">= 1.3.6"
  s.add_dependency "mongoid", ">= 2.0.0.beta.19"

  s.add_development_dependency "bundler", ">= 1.0.0"
  s.add_development_dependency "rake", ">= 0"

  s.files        = `git ls-files`.split("\n")
  s.executables  = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'

  s.rdoc_options = ["--charset=UTF-8"]
end