module Proxy
  module ContainerGateway
    class NotFound < RuntimeError; end

    class Plugin < ::Proxy::Plugin
      plugin 'container_gateway', Proxy::ContainerGateway::VERSION

      default_settings :pulp_endpoint => "https://#{`hostname`.strip}",
                       :katello_registry_path => '/v2/',
                       :sqlite_db_path => '/var/lib/foreman-proxy/smart_proxy_container_gateway.db',
                       :sqlite_timeout => 30_000

      # Load defaults that copy values from SETTINGS. This is done as
      # programmable settings since SETTINGS isn't initialized during plugin
      # loading.
      load_programmable_settings do |settings|
        settings[:pulp_client_ssl_ca] ||= SETTINGS.foreman_ssl_ca
        settings[:pulp_client_ssl_cert] ||= SETTINGS.foreman_ssl_cert
        settings[:pulp_client_ssl_key] ||= SETTINGS.foreman_ssl_key
      end

      # TODO: sqlite_db_path should able be readable or creatable. There's no
      # test for creatable
      validate_readable :pulp_client_ssl_ca, :pulp_client_ssl_cert, :pulp_client_ssl_key
      validate :pulp_endpoint, url: true

      rackup_path File.join(__dir__, 'container_gateway_http_config.ru')

      def load_dependency_injection_wirings(container, settings)
        container.singleton_dependency :database, (lambda do
          Proxy::Database.new(url: settings.sqlite_db_path, timeout: settings.sqlite_timeout)
        end)
      end
    end
  end
end
