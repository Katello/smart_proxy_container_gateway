module Proxy
  module ContainerGateway
    class NotFound < RuntimeError; end

    class Plugin < ::Proxy::Plugin
      plugin 'container_gateway', Proxy::ContainerGateway::VERSION

      default_settings :pulp_endpoint => "https://#{`hostname`.strip}"

      http_rackup_path File.expand_path('container_gateway_http_config.ru', File.expand_path('..', __dir__))
      https_rackup_path File.expand_path('container_gateway_http_config.ru', File.expand_path('..', __dir__))
    end
  end
end
