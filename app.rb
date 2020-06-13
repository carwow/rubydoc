# frozen_string_literal: true

require File.join(File.dirname(__FILE__), 'init')

require 'yard'
require 'sinatra'
require 'json'
require 'fileutils'

require 'extensions'
require 'gem_updater'
require 'gems_router'
require 'gem_store'

require 'digest/sha2'
require 'rack/etag'
require 'version_sorter'
require 'pry'

class Hash; alias blank? empty? end
class NilClass; def blank?; true end end

class NoCacheEmptyBody
  def initialize(app) @app = app end
  def call(env)
    status, headers, body = *@app.call(env)
    if headers.has_key?('Content-Length') && headers['Content-Length'].to_i == 0
      headers['Cache-Control'] = 'max-age=0'
    end
    [status, headers, body]
  end
end

class DocServer < Sinatra::Base
  include YARD::Server

  DOC_PREFIXES = ['', '/search', '/list', '/static']

  def self.adapter_options
    caching = %w(staging production).include?(ENV['RACK_ENV']) ? $CONFIG.caching : false
    {
      :libraries => {},
      :options => {caching: false, single_library: false},
      :server_options => {DocumentRoot: STATIC_PATH}
    }
  end

  def self.load_configuration
    set :environment, ($CONFIG.environment || 'production').to_sym
    set :name, $CONFIG.name || 'RubyDoc.info'
    set :url, $CONFIG.url || 'https://www.rubydoc.info'

    set :disallowed_projects, []
    set :disallowed_gems, []
    set :whitelisted_projects, []
    set :whitelisted_gems, []
    set :caching, false
    set :rubygems, ""
  end

  def self.load_gems_adapter
    return if $CONFIG.disable_gems
    opts = adapter_options
    opts[:libraries] = GemStore.new
    opts[:options][:router] = GemsRouter
    set :gems_adapter, $gems_adapter = RackAdapter.new(*opts.values)
  rescue Errno::ENOENT
    log.error "No remote_gems file to load remote gems from, not serving gems."
  end

  def self.post_all(*args, &block)
    args.each {|arg| post(arg, &block) }
  end

  use Rack::ConditionalGet
  use Rack::Head
  use NoCacheEmptyBody

  enable :static
  enable :dump_errors
  enable :lock
  enable :logging
  disable :raise_errors

  set :views, TEMPLATES_PATH
  set :public_folder, STATIC_PATH
  set :repos, REPOS_PATH
  set :tmp, TMP_PATH
  set :logdir, LOG_PATH
  set :static_cache_control, [:public, :max_age => 30]

  configure do
    load_configuration
    load_gems_adapter
  end

  helpers do
    include YARD::Templates::Helpers::HtmlHelper

    def notify_error
      erb(:error)
    end

    def cache(output)
      return output if settings.caching != true
      return '' if output.nil? || output.empty?
      path = cache_file
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "w") {|f| f.write(output) }
      output
    end

    def cache_file
      path = request.path.gsub(%r{^/|/$}, '')
      path = 'index' if path == ''
      File.join(settings.public_folder, path + '.html')
    end

    def next_row(prefix = 'r', base = 1)
      prefix + (@row = @row == base ? base + 1 : base).to_s
    end

    def translate_file_links(extra)
      extra.sub(%r{^/(frames/)?file:}, '/\1file/')
    end

    def shorten_commit_link(commit)
      commit.slice(0..5)
    end

    def try_load_cached_file
      cache_control :public, :must_revalidate, :max_age => 60

      return if settings.caching != true
      path = cache_file
      if File.exist?(path)
        cache_control :public
        send_file(path, last_modified: File.mtime(path))
      else
        last_modified Time.now
      end
    end

    def try_static_cache(prefix)
      return unless prefix == '/static'
      path = File.join(settings.public_folder, params['splat'].join('/'))
      if File.exist?(path)
        cache_control :public
        send_file(path, last_modified: File.mtime(path))
      end
    end
  end

  # Filters

  # Check cache
  before { try_load_cached_file }

  # Always reset safe mode
  before { YARD::Config.options[:safe_mode] = true }

  # Indexes

  get '/' do
    @adapter = settings.gems_adapter
    @featured = settings.gems_adapter.libraries
    cache erb(:home)
  end

  get %r{/gems(?:/~([a-z]))?(?:/([0-9]+))?} do |letter, page|
    @letter = letter
    @adapter = settings.gems_adapter
    @page = (page || 1).to_i
    @max_pages = @letter ? @adapter.libraries.pages_of_letter(@letter) : 1
    @libraries = @adapter.libraries
    @libraries = @libraries.each_of_letter(@letter, @page) if @letter
    cache erb(:gems_index)
  end

  DOC_PREFIXES.each do |prefix|
    get "#{prefix}/gems/:gemname/?*" do
      try_static_cache(prefix)

      @gemname = params['gemname']
      return status(503) && "Cannot parse this gem" if settings.disallowed_gems.include?(@gemname)
      if settings.whitelisted_gems.include?(@gemname)
        puts "Dropping safe mode for #{@gemname}"
        YARD::Config.options[:safe_mode] = false
      end
      result = settings.gems_adapter.call(env)
      return status(404) && erb(:gems_404) if result.first == 404
      result
    end
  end

  # Simple search interfaces

  get '/find/gems' do
    self.class.load_gems_adapter unless defined? settings.gems_adapter
    @search = params[:q] || ''
    @page = (params[:page] || 1).to_i
    @adapter = settings.gems_adapter
    @max_pages = @adapter.libraries.pages_of_find_by(@search)
    @libraries = @adapter.libraries.find_by(@search, @page)
    erb(:gems_index)
  end

  error do
    @page_title = "Unknown Error!"
    @error = "Something quite unexpected just happened.
      If you think something is wrong, please <a href='mailto:support@rdoc.info'>email us</a>
      about it."
    notify_error
  end
end
