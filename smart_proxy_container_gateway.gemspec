require File.expand_path('./lib/smart_proxy_container_gateway/version', __dir__)

Gem::Specification.new do |s|
  s.name = 'smart_proxy_container_gateway'
  s.version = Proxy::ContainerGateway::VERSION

  s.summary = 'Pulp 3 container registry support for Foreman/Katello Smart-Proxy'
  s.description = 'Foreman Smart Proxy plug-in for Pulp 3 container registry support'
  s.authors = ['Ian Ballou']
  s.email = 'ianballou67@gmail.com'
  s.extra_rdoc_files = ['README.md', 'LICENSE']
  s.files = Dir['{lib,settings.d,bundler.d}/**/*'] + s.extra_rdoc_files
  s.test_files = s.files.grep(%r{^(test|spec|features)/})
  s.homepage = 'https://github.com/Katello/smart_proxy_container_gateway'
  s.license = 'GPL-3.0-only'

  s.required_ruby_version = '>= 3.0'
  s.add_dependency 'activesupport', '>= 6.1', '< 8'
  s.add_dependency 'pg', '~> 1.5'
  s.add_dependency 'sequel', '~> 5.0'
  s.add_dependency 'sqlite3', '~> 1.4'
end
