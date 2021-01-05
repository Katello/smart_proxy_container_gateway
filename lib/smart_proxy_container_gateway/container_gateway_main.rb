require 'net/http'
require 'uri'

module Proxy
  module ContainerGateway
    extend ::Proxy::Util
    extend ::Proxy::Log

    class << self
      def pulp_registry_request(uri)
        http_client = Net::HTTP.new(uri.host, uri.port)
        http_client.cert = pulp_cert
        http_client.key = pulp_key
        http_client.use_ssl = true

        http_client.start do |http|
          request = Net::HTTP::Get.new uri
          http.request request
        end
      end

      def ping
        uri = URI.parse("#{Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/")
        pulp_registry_request(uri).body
      end

      def manifests(repository, tag)
        uri = URI.parse(
          "#{Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/#{repository}/manifests/#{tag}"
        )
        pulp_registry_request(uri)['location']
      end

      def blobs(repository, digest)
        uri = URI.parse(
          "#{Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/#{repository}/blobs/#{digest}"
        )
        pulp_registry_request(uri)['location']
      end

      def v1_search(params = {})
        if params[:n].nil? || params[:n] == ""
          params[:n] = 25
        else
          params[:n] = params[:n].to_i
        end

        repo_count = 0
        repositories = []
        Proxy::ContainerGateway.catalog.each do |repo_name|
          break if repo_count >= params[:n]

          if params[:q].nil? || params[:q] == "" || repo_name.include?(params[:q])
            repo_count += 1
            repositories << { name: repo_name }
          end
        end
        repositories
      end

      def catalog
        unauthenticated_repos
      end

      def unauthenticated_repos
        conn = initialize_db
        conn[:unauthenticated_repositories].order(:name).map(:name)
      end

      def update_unauthenticated_repos(repo_names)
        conn = initialize_db
        unauthenticated_repos = conn[:unauthenticated_repositories]
        unauthenticated_repos.delete
        repo_names.each do |repo_name|
          unauthenticated_repos.insert(:name => repo_name)
        end
      end

      def authorized_for_repo?(repo_name)
        conn = initialize_db
        unauthenticated_repo = conn[:unauthenticated_repositories].where(name: repo_name).first
        !unauthenticated_repo.nil?
      end

      def initialize_db
        conn = Sequel.postgres(host: Proxy::ContainerGateway::Plugin.settings.postgres_db_hostname,
                               user: Proxy::ContainerGateway::Plugin.settings.postgres_db_username,
                               password: Proxy::ContainerGateway::Plugin.settings.postgres_db_password,
                               database: Proxy::ContainerGateway::Plugin.settings.postgres_db_name)
        container_gateway_path = $LOAD_PATH.detect { |path| path.include? 'smart_proxy_container_gateway' }
        begin
          Sequel::Migrator.check_current(conn, "#{container_gateway_path}/smart_proxy_container_gateway/sequel_migrations")
        rescue Sequel::Migrator::NotCurrentError
          migrate_db(conn, container_gateway_path)
        end
        conn
      end

      private

      def migrate_db(db_connection, container_gateway_path)
        Sequel::Migrator.run(db_connection, "#{container_gateway_path}/smart_proxy_container_gateway/sequel_migrations")
      end

      def pulp_cert
        OpenSSL::X509::Certificate.new(File.open(Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_cert, 'r').read)
      end

      def pulp_key
        OpenSSL::PKey::RSA.new(
          File.open(Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_key, 'r').read
        )
      end
    end
  end
end
