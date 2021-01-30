module Proxy
  module ContainerGateway
    class NotFound < RuntimeError; end

    class Plugin < ::Proxy::Plugin
      plugin 'container_gateway', Proxy::ContainerGateway::VERSION

      default_settings :pulp_endpoint => "https://#{`hostname`.strip}",
                       :katello_registry_path => '/v2/',
                       :sqlite_db_path => '/var/lib/foreman-proxy/smart_proxy_container_gateway.db'

      rackup_path File.join(__dir__, 'container_gateway_http_config.ru')
    end
  end
end
