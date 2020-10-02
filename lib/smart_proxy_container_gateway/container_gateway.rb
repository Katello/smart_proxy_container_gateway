module Proxy::ContainerGateway
  class NotFound < RuntimeError; end

  class Plugin < ::Proxy::Plugin
    plugin 'container_gateway', Proxy::ContainerGateway::VERSION

    default_settings :hello_greeting => 'O hai!'

    http_rackup_path File.expand_path('container_gateway_http_config.ru', File.expand_path('../', __FILE__))
    https_rackup_path File.expand_path('container_gateway_http_config.ru', File.expand_path('../', __FILE__))
  end
end
