require 'rake'
require 'rake/testtask'
require 'rake/rdoctask'

desc 'Default: run unit tests.'
task :default => [:test]

desc 'Test the acts as state machine plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/test_*.rb'
  t.verbose = true
end

desc 'Generate documentation for the acts as state machine plugin.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'Mongoid State Machine'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('TODO.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end
