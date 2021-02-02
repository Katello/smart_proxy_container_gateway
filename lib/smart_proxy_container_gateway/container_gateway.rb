module Proxy
  module ContainerGateway
    class NotFound < RuntimeError; end

    class Plugin < ::Proxy::Plugin
      plugin 'container_gateway', Proxy::ContainerGateway::VERSION

      begin
        SETTINGS = Proxy::Settings.initialize_global_settings

        default_settings :pulp_endpoint => "https://#{`hostname`.strip}",
                         :pulp_client_ssl_ca => SETTINGS.foreman_ssl_ca,
                         :pulp_client_ssl_cert => SETTINGS.foreman_ssl_cert,
                         :pulp_client_ssl_key => SETTINGS.foreman_ssl_key,
                         :katello_registry_path => '/v2/',
                         :sqlite_db_path => '/var/lib/foreman-proxy/smart_proxy_container_gateway.db'
      rescue Errno::ENOENT
        logger.warn("Default settings could not be loaded.  Default certs will not be set.")
        default_settings :pulp_endpoint => "https://#{`hostname`.strip}",
                         :katello_registry_path => '/v2/',
                         :sqlite_db_path => '/var/lib/foreman-proxy/smart_proxy_container_gateway.db'
      end

      rackup_path File.join(__dir__, 'container_gateway_http_config.ru')
    end
  end
end
