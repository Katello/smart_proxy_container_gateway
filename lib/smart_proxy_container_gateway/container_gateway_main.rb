require 'net/http'
require 'uri'
require 'digest'
require 'sequel'
module Proxy
  module ContainerGateway
    extend ::Proxy::Util
    extend ::Proxy::Log

    class << self
      Sequel.extension :migration, :core_extensions
      def pulp_registry_request(uri)
        http_client = Net::HTTP.new(uri.host, uri.port)
        http_client.ca_file = pulp_ca
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
        user = params[:user].nil? ? nil : User.find(name: params[:user])
        Proxy::ContainerGateway.catalog(user).each do |repo_name|
          break if repo_count >= params[:n]

          if params[:q].nil? || params[:q] == "" || repo_name.include?(params[:q])
            repo_count += 1
            repositories << { name: repo_name }
          end
        end
        repositories
      end

      def catalog(user = nil)
        if user.nil?
          unauthenticated_repos
        else
          (unauthenticated_repos + user.repositories_dataset.map(:name)).sort
        end
      end

      def unauthenticated_repos
        Repository.where(auth_required: false).order(:name).map(:name)
      end

      # Replaces the entire list of repositories
      def update_repository_list(repo_list)
        RepositoryUser.dataset.delete
        Repository.dataset.delete
        repo_list.each do |repo|
          Repository.find_or_create(name: repo['repository'],
                                    auth_required: repo['auth_required'].to_s.downcase == "true")
        end
      end

      # Replaces the entire user-repo mapping for all logged-in users
      def update_user_repo_mapping(user_repo_maps)
        # Get hash map of all users and their repositories
        # Ex: {"users"=> [{"admin"=>[{"repository"=>"repo", "auth_required"=>"true"}]}]}
        # Go through list of repositories and add them to the DB
        RepositoryUser.dataset.delete
        user_repo_maps['users'].each do |user_repo_map|
          user_repo_map.each do |user, repos|
            repos.each do |repo|
              found_repo = Repository.find(name: repo['repository'],
                                           auth_required: repo['auth_required'].to_s.downcase == "true")
              if found_repo.nil?
                logger.warn("#{repo['repository']} does not exist in this smart proxy's environments")
              elsif found_repo.auth_required
                found_repo.add_user(User.find(name: user))
              end
            end
          end
        end
      end

      # Replaces the user-repo mapping for a single user
      def update_user_repositories(username, repositories)
        user = User.where(name: username).first
        user.remove_all_repositories
        repositories.each do |repo_name|
          found_repo = Repository.find(name: repo_name)
          if found_repo.nil?
            logger.warn("#{repo_name} does not exist in this smart proxy's environments")
          elsif user.repositories_dataset.where(name: repo_name).first.nil? && found_repo.auth_required
            user.add_repository(found_repo)
          end
        end
      end

      def authorized_for_repo?(repo_name, user_token_is_valid, username = nil)
        repository = Repository.where(name: repo_name).first

        # Repository doesn't exist
        return false if repository.nil?

        # Repository doesn't require auth
        return true unless repository.auth_required

        if username && user_token_is_valid && repository.auth_required
          # User is logged in and has access to the repository
          user = User.find(name: username)
          return !user.repositories_dataset.where(name: repo_name).first.nil?
        end

        false
      end

      def token_user(token)
        User[AuthenticationToken.find(token_checksum: Digest::SHA256.hexdigest(token)).user_id]
      end

      def valid_token?(token)
        AuthenticationToken.where(token_checksum: Digest::SHA256.hexdigest(token)).where do
          expire_at > Sequel::CURRENT_TIMESTAMP
        end.count.positive?
      end

      def insert_token(username, token, expire_at_string, clear_expired_tokens: true)
        checksum = Digest::SHA256.hexdigest(token)
        user = User.find_or_create(name: username)

        AuthenticationToken.where(:token_checksum => checksum).delete
        AuthenticationToken.create(token_checksum: checksum, expire_at: expire_at_string.to_s, user_id: user.id)
        AuthenticationToken.where { expire_at < Sequel::CURRENT_TIMESTAMP }.delete if clear_expired_tokens
      end

      def initialize_db
        file_path = Proxy::ContainerGateway::Plugin.settings.sqlite_db_path
        conn = Sequel.connect("sqlite://#{file_path}")
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

      def pulp_ca
        Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_ca
      end

      def pulp_cert
        OpenSSL::X509::Certificate.new(File.read(Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_cert))
      end

      def pulp_key
        OpenSSL::PKey::RSA.new(
          File.read(Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_key)
        )
      end
    end

    class Repository < ::Sequel::Model(Proxy::ContainerGateway.initialize_db[:repositories])
      many_to_many :users
    end

    class User < ::Sequel::Model(Proxy::ContainerGateway.initialize_db[:users])
      many_to_many :repositories
      one_to_many :authentication_tokens
    end

    class RepositoryUser < ::Sequel::Model(Proxy::ContainerGateway.initialize_db[:repositories_users]); end

    class AuthenticationToken < ::Sequel::Model(Proxy::ContainerGateway.initialize_db[:authentication_tokens])
      many_to_one :users
    end
  end
end
