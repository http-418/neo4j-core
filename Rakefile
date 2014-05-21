require 'rake'
require "bundler/gem_tasks"
require 'neo4j/tasks/neo4j_server'

def jar_path
  spec = Gem::Specification.find_by_name("neo4j-community")
  gem_root = spec.gem_dir
  gem_root + "/lib/neo4j-community/jars"
end

desc "Generate YARD documentation"
task 'yard' do
  abort("can't generate YARD") unless system('yardoc - README.md')
end

desc "Run neo4j-core specs"
task 'spec-core' do
  success = system('rspec spec')
  abort("RSpec neo4j-core failed") unless success
end


task :default => ['spec-core']