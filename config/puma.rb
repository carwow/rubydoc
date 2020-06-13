puts "puma.rb"

root = File.dirname(__FILE__) + '/../'

directory root
rackup root + 'config.ru'
preload_app!
threads 4, 16
workers 1

before_fork do
  require_relative '../lib/preload'
  AppPreloader.preload!
end
