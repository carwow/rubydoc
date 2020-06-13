require_relative 'init'
require 'fileutils'

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
end

task :default => 'gems:update'

namespace :gems do
  desc 'Update gem list from remote'
  task :update do
    puts ">> Updating Remote Gems file (local cache)"
    load('scripts/update_remote_gems.rb')
  end
end

namespace :docs do
  desc 'Clean up old docs to conserve space'
  task :clean do
    puts ">> Removing outdated doc directories"
    load('scripts/clean_docs.rb')
  end
end

namespace :repos do
  desc 'Clean up the cached gem sources and repositories'
  task :clean do
    puts ">> Removing cached gem sources and repositories"
    load('scripts/clean_repos.rb')
  end
end

namespace :cache do
  desc 'Clean index cache pages (github, gems, featured)'
  task :clean_index do
    puts '>> Removing index cache pages'
    load('scripts/clean_index_cache.rb')
  end

  desc 'Clean HTML cache (github, gems, featured)'
  task :clean_disk_html do
    puts '>> Removing HTML cache pages'
    system 'find public/github public/gems public/featured public/docs -atime +7 -exec rm -vrf {} \;'
  end

  desc 'Clean repository cache (github, gems)'
  task :clean_disk_repos do
    puts '>> Removing gem repositories'
    system 'rm -rf repos/gems/*'
  end
end
