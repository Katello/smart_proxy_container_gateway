module Proxy
  module ContainerGateway
    class NotFound < RuntimeError; end

    class Plugin < ::Proxy::Plugin
      plugin 'container_gateway', Proxy::ContainerGateway::VERSION

      default_settings :pulp_endpoint => "https://#{`hostname`.strip}",
                       :katello_registry_path => '/v2/',
                       :sqlite_db_path => '/var/lib/foreman-proxy/smart_proxy_container_gateway.db'

      http_rackup_path File.expand_path('smart_proxy_container_gateway/container_gateway_http_config.ru',
                                        File.expand_path('..', __dir__))
      https_rackup_path File.expand_path('smart_proxy_container_gateway/container_gateway_http_config.ru',
                                         File.expand_path('..', __dir__))
    end
  end
end
