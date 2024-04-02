require File.expand_path('./lib/smart_proxy_container_gateway/version', __dir__)

Gem::Specification.new do |s|
  s.name = 'smart_proxy_container_gateway'
  s.version = Proxy::ContainerGateway::VERSION

  s.summary = 'Pulp 3 container registry support for Foreman/Katello Smart-Proxy'
  s.description = 'Pulp 3 container registry support for Foreman/Katello Smart-Proxy'
  s.authors = ['Ian Ballou']
  s.email = 'ianballou67@gmail.com'
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = Dir['{lib,settings.d,bundler.d}/**/*'] + s.extra_rdoc_files
  s.test_files = s.files.grep(%r{^(test|spec|features)/})
  s.homepage = 'https://github.com/Katello/smart_proxy_container_gateway'
  s.license = 'GPLv3'

  s.required_ruby_version = '>= 2.7'
  s.add_dependency 'activesupport'
  s.add_dependency 'sequel'
  s.add_dependency 'sqlite3'
  s.add_dependency 'pg'
end
