source 'https://rubygems.org'
gemspec

group :development do
  gem 'test-unit'
  gem 'pry'
  gem 'rubocop'
  gem 'rake'
  gem 'rack-test'
  gem 'webmock'
  gem 'mocha'
  gem 'smart_proxy', :github => "theforeman/smart-proxy", :branch => 'develop'
end

# load local gemfile
local_gemfile = File.join(__dir__, 'Gemfile.local.rb')
instance_eval(Bundler.read_file(local_gemfile)) if File.exist?(local_gemfile)
