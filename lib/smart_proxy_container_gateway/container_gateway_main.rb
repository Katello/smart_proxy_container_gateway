require 'net/http'
require 'uri'
require 'digest'
require 'smart_proxy_container_gateway/dependency_injection'
require 'sequel'
module Proxy
  module ContainerGateway
    extend ::Proxy::Util
    extend ::Proxy::Log

    class ContainerGatewayMain
      attr_reader :database, :client_endpoint

      # rubocop:disable Metrics/ParameterLists, Layout/LineLength
      def initialize(database:, pulp_endpoint:, pulp_client_ssl_ca:, pulp_client_ssl_cert:, pulp_client_ssl_key:, client_endpoint: nil)
        @database = database
        @pulp_endpoint = pulp_endpoint
        @client_endpoint = client_endpoint || pulp_endpoint
        @pulp_client_ssl_ca = pulp_client_ssl_ca
        @pulp_client_ssl_cert = OpenSSL::X509::Certificate.new(File.read(pulp_client_ssl_cert))
        @pulp_client_ssl_key = OpenSSL::PKey::RSA.new(
          File.read(pulp_client_ssl_key)
        )
      end
      # rubocop:enable Metrics/ParameterLists, Layout/LineLength

      def pulp_registry_request(uri, headers)
        http_client = Net::HTTP.new(uri.host, uri.port)
        http_client.ca_file = @pulp_client_ssl_ca
        http_client.cert = @pulp_client_ssl_cert
        http_client.key = @pulp_client_ssl_key
        http_client.use_ssl = true

        http_client.start do |http|
          request = Net::HTTP::Get.new uri
          headers.each do |key, value|
            request[key] = value
          end
          http.request request
        end
      end

      def ping(headers)
        uri = URI.parse("#{@pulp_endpoint}/pulpcore_registry/v2/")
        pulp_registry_request(uri, headers)
      end

      def manifests(repository, tag, headers)
        uri = URI.parse(
          "#{@pulp_endpoint}/pulpcore_registry/v2/#{repository}/manifests/#{tag}"
        )
        pulp_registry_request(uri, headers)
      end

      def blobs(repository, digest, headers)
        uri = URI.parse(
          "#{@pulp_endpoint}/pulpcore_registry/v2/#{repository}/blobs/#{digest}"
        )
        pulp_registry_request(uri, headers)
      end

      def tags(repository, headers, params = {})
        query = "?"
        unless params[:n].nil? || params[:n] == ""
          query = "#{query}n=#{params[:n]}"
          query = "#{query}&" unless params[:last].nil?
        end
        query = "#{query}last=#{params[:last]}" unless params[:last].nil? || params[:last] == ""

        uri = URI.parse(
          "#{@pulp_endpoint}/pulpcore_registry/v2/#{repository}/tags/list#{query}"
        )
        pulp_registry_request(uri, headers)
      end

      def v1_search(params = {})
        if params[:n].nil? || params[:n] == ""
          limit = 25
        else
          limit = params[:n].to_i
        end
        return [] unless limit.positive?

        query = params[:q]
        query = nil if query == ''

        user = params[:user].nil? ? nil : database.connection[:users][{ name: params[:user] }]

        repositories = query ? catalog(user).grep(:name, "%#{query}%") : catalog(user)
        repositories.limit(limit).select_map(::Sequel[:repositories][:name])
      end

      def catalog(user = nil)
        if user.nil?
          unauthenticated_repos
        else
          database.connection[:repositories].
            left_join(:repositories_users, repository_id: :id).
            left_join(:users, ::Sequel[:users][:id] => :user_id).where(user_id: user[:id]).
            or(Sequel[:repositories][:auth_required] => false).order(::Sequel[:repositories][:name])
        end
      end

      def host_catalog(host_uuid = nil)
        if host_uuid.nil?
          unauthenticated_repos
        else
          database.connection[:repositories].
            left_join(:hosts_repositories, repository_id: :id).
            left_join(:hosts, ::Sequel[:hosts][:id] => :host_id).where(uuid: host_uuid).
            or(Sequel[:repositories][:auth_required] => false).order(::Sequel[:repositories][:name])
        end
      end

      def unauthenticated_repos
        database.connection[:repositories].where(auth_required: false).order(:name)
      end

      # Replaces the entire list of repositories
      def update_repository_list(repo_list)
        # repositories_users cascades on deleting repositories (or users)
        database.connection.transaction(isolation: :serializable, retry_on: [Sequel::SerializationFailure]) do
          repository = database.connection[:repositories]
          repository.delete

          repository.import(
            %i[name auth_required],
            repo_list.map { |repo| [repo['repository'], repo['auth_required'].to_s.downcase == "true"] }
          )
        end
      end

      # Replaces the entire user-repo mapping for all logged-in users
      def update_user_repo_mapping(user_repo_maps)
        # Get hash map of all users and their repositories
        # Ex: {"users"=> [{"admin"=>[{"repository"=>"repo", "auth_required"=>"true"}]}]}
        # Go through list of repositories and add them to the DB
        repositories = database.connection[:repositories]

        entries = user_repo_maps['users'].flat_map do |user_repo_map|
          user_repo_map.filter_map do |username, repos|
            user_repo_names = repos.filter { |repo| repo['auth_required'].to_s.downcase == "true" }.map do |repo|
              repo['repository']
            end
            user = database.connection[:users][{ name: username }]
            repositories.where(name: user_repo_names, auth_required: true).select(:id).map { |repo| [repo[:id], user[:id]] }
          end
        end
        entries.flatten!(1)

        repositories_users = database.connection[:repositories_users]
        database.connection.transaction(isolation: :serializable, retry_on: [Sequel::SerializationFailure]) do
          repositories_users.delete
          repositories_users.import(%i[repository_id user_id], entries)
        end
      end

      # Replaces the user-repo mapping for a single user
      def update_user_repositories(username, repositories)
        user = database.connection[:users][{ name: username }]

        user_repositories = database.connection[:repositories_users]
        database.connection.transaction(isolation: :serializable,
                                        retry_on: [Sequel::SerializationFailure],
                                        num_retries: 10) do
          user_repositories.where(user_id: user[:id]).delete

          user_repositories.import(
            %i[repository_id user_id],
            database.connection[:repositories].where(name: repositories, auth_required: true).select(:id).map do |repo|
              [repo[:id], user[:id]]
            end
          )
        end
      end

      # Replaces the entire host-repo mapping for all hosts.
      # Assumes host is present in the DB.
      def update_host_repo_mapping(host_repo_maps)
        # Get DB tables
        hosts_repositories = database.connection[:hosts_repositories]

        # Build list of [repository_id, host_id] pairs
        entries = build_host_repository_mapping(host_repo_maps)

        # Insert all in a single transaction
        database.connection.transaction(isolation: :serializable, retry_on: [Sequel::SerializationFailure]) do
          hosts_repositories.delete
          hosts_repositories.import(%i[repository_id host_id], entries)
        end
      end

      def build_host_repository_mapping(host_repo_maps)
        hosts = database.connection[:hosts]
        repositories = database.connection[:repositories]
        entries = host_repo_maps['hosts'].flat_map do |host_map|
          host_map.filter_map do |host_uuid, repos|
            host = hosts[{ uuid: host_uuid }]
            next unless host

            repo_names = repos
                         .select { |repo| repo['auth_required'].to_s.downcase == "true" }
                         .map { |repo| repo['repository'] }

            repositories
              .where(name: repo_names, auth_required: true)
              .select(:id)
              .map { |repo| [repo[:id], host[:id]] }
          end
        end
        entries.flatten!(1)
      end

      def update_host_repositories(uuid, repositories)
        host = find_or_create_host(uuid)
        hosts_repositories = database.connection[:hosts_repositories]
        database.connection.transaction(isolation: :serializable,
                                        retry_on: [Sequel::SerializationFailure],
                                        num_retries: 10) do
          hosts_repositories.where(host_id: host[:id]).delete
          return if repositories.nil? || repositories.empty?

          hosts_repositories.import(
            %i[repository_id host_id],
            database.connection[:repositories].where(name: repositories, auth_required: true).select(:id).map do |repo|
              [repo[:id], host[:id]]
            end
          )
        end
      end

      def find_or_create_host(uuid)
        database.connection[:hosts].insert_conflict(target: :uuid, action: :ignore).insert(uuid: uuid)
        database.connection[:hosts][{ uuid: uuid }]
      end

      # Returns:
      # true if the user is authorized to access the repo, or
      # false if the user is not authorized to access the repo or if it does not exist
      def authorized_for_repo?(repo_name, user_token_is_valid, username = nil)
        repository = database.connection[:repositories][{ name: repo_name }]

        # Repository doesn't exist
        return false if repository.nil?

        # Repository doesn't require auth
        return true unless repository[:auth_required]

        if username && user_token_is_valid
          # User is logged in and has access to the repository
          return !database.connection[:repositories_users].where(
            repository_id: repository[:id], user_id: database.connection[:users].first(name: username)[:id]
          ).empty?
        end

        false
      end

      def cert_authorized_for_repo?(repo_name, uuid)
        database.connection.transaction(isolation: :serializable, retry_on: [Sequel::SerializationFailure]) do
          repository = database.connection[:repositories][{ name: repo_name }]
          return false if repository.nil?
          return true unless repository[:auth_required]

          database.connection[:hosts_repositories]
                  .where(repository_id: repository[:id])
                  .join(:hosts, id: :host_id)
                  .where(Sequel[:hosts][:uuid] => uuid)
                  .any?
        end
      end

      def token_user(token)
        database.connection[:users][{
          id: database.connection[:authentication_tokens].where(token_checksum: checksum(token)).select(:user_id)
        }]
      end

      def valid_token?(token)
        !database.connection[:authentication_tokens].where(token_checksum: checksum(token)).where do
          expire_at > Sequel::CURRENT_TIMESTAMP
        end.empty?
      end

      def insert_token(username, token, expire_at_string, clear_expired_tokens: true)
        checksum = Digest::SHA256.hexdigest(token)
        user = Sequel::Model(database.connection[:users]).find_or_create(name: username)

        database.connection.transaction(isolation: :serializable, retry_on: [Sequel::SerializationFailure]) do
          database.connection[:authentication_tokens].where(:token_checksum => checksum).delete
          Sequel::Model(database.connection[:authentication_tokens]).
            create(token_checksum: checksum, expire_at: expire_at_string.to_s, user_id: user.id)
          return unless clear_expired_tokens

          database.connection[:authentication_tokens].where { expire_at < Sequel::CURRENT_TIMESTAMP }.delete
        end
      end

      private

      def checksum(token)
        Digest::SHA256.hexdigest(token)
      end
    end
  end
end
