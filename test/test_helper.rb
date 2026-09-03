require 'test/unit'
$LOAD_PATH << File.join(__dir__, '..', 'lib')

ENV['RACK_ENV'] = 'test'

# Database configuration for tests
# Default to PostgreSQL in CI, fall back to SQLite for local development
ENV['DATABASE_URL'] ||= if ENV['CI']
                          'postgres://postgres:postgres@localhost:5432/container_gateway_test'
                        else
                          # Allow local override, otherwise use SQLite
                          'sqlite://'
                        end

# Workaround: sinatra/main.rb parses ARGV at require time and exits on -v.
# Clear ARGV before loading to prevent OptionParser from intercepting test flags.
saved_argv = ARGV.dup
ARGV.clear
require 'smart_proxy_for_testing'
ARGV.replace(saved_argv)
