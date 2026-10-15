require 'test/unit'
$LOAD_PATH << File.join(__dir__, '..', 'lib')

# Workaround: sinatra/main.rb parses ARGV at require time and exits on -v.
# Clear ARGV before loading to prevent OptionParser from intercepting test flags.
saved_argv = ARGV.dup
ARGV.clear
require 'smart_proxy_for_testing'
ARGV.replace(saved_argv)
