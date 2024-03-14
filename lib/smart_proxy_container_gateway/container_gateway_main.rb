require 'net/http'
require 'uri'
require 'digest'
module Proxy
  module ContainerGateway
    extend ::Proxy::Util
    extend ::Proxy::Log

    class << self
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

      def tags(repository, params = {})
        query = "?"
        unless params[:n].nil? || params[:n] == ""
          query = "#{query}n=#{params[:n]}"
          query = "#{query}&" unless params[:last].nil?
        end
        query = "#{query}last=#{params[:last]}" unless params[:last].nil? || params[:last] == ""

        uri = URI.parse(
          "#{Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/#{repository}/tags/list#{query}"
        )
        pulp_registry_request(uri)
      end

      def v1_search(params = {})
        if params[:n].nil? || params[:n] == ""
          limit = 25
        else
          limit = params[:n].to_i
        end

        query = params[:q]
        query = nil if query == ''

        user = params[:user].nil? ? nil : database[:users][{ name: params[:user] }]

        # TODO: rely on catalog returning a query
        repositories = query ? catalog(database, user).filter(:name.like("%#{query}%")) : catalog(database, user)
        repositories.limit(limit)
      end

      def catalog(database, user = nil)
        if user.nil?
          unauthenticated_repos(database)
        else
          query = "SELECT repositories.name AS name FROM repositories" \
            " INNER JOIN repositories_users ON repositories.id = repositories_users.repository_id" \
            " INNER JOIN users ON repositories_users.user_id = users.id " \
            " WHERE users.id = #{user[:id]} OR repositories.auth_required = FALSE"
          database.connection.fetch(query).order(:name).all.map { |repo| repo[:name] }
        end
      end

      def unauthenticated_repos(database)
        database.connection[:repositories].where(auth_required: false).order(:name).select_map(:name)
      end

      # Replaces the entire list of repositories
      def update_repository_list(database, repo_list)
        # repositories_users cascades on deleting repositories (or users)
        database.connection.transaction do
          repository = database.connection[:repositories]
          repository.delete

          repository.import(
            %i[name auth_required],
            repo_list.map { |repo| [repo['repository'], repo['auth_required'].to_s.downcase == "true"] }
          )
        end
      end

      # Replaces the entire user-repo mapping for all logged-in users
      def update_user_repo_mapping(database, user_repo_maps)
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

        repositories_users = database.connection[:repositories_users]
        database.connection.transaction do
          repositories_users.delete
          repositories_users.import(%i[repository_id user_id], entries[0])
        end
      end

      # Replaces the user-repo mapping for a single user
      def update_user_repositories(database, username, repositories)
        user = database.connection[:users][{ name: username }]

        user_repositories = database.connection[:repositories_users]
        database.connection.transaction do
          user_repositories.where(user_id: user[:id]).delete

          user_repositories.import(
            %i[repository_id user_id],
            database.connection[:repositories].where(name: repositories, auth_required: true).select(:id).map do |repo|
              [repo[:id], user[:id]]
            end
          )
        end
      end

      def authorized_for_repo?(database, repo_name, user_token_is_valid, username = nil)
        repository = database.connection[:repositories][{ name: repo_name }]

        # Repository doesn't exist
        return false if repository.nil?

        # Repository doesn't require auth
        return true unless repository[:auth_required]

        if username && user_token_is_valid
          # User is logged in and has access to the repository
          return database.connection[:repositories_users].where(
            repository_id: repository[:id], user_id: database.connection[:users].where(name: username)
          ).exists
        end

        false
      end

      def token_user(database, token)
        database.connection[:users][{
          id: database.connection[:authentication_tokens].where(token_checksum: checksum(token)).select(:user_id)
        }]
      end

      def valid_token?(database, token)
        database.connection[:authentication_tokens].where(token_checksum: checksum(token)).where do
          expire_at > Sequel::CURRENT_TIMESTAMP
        end.exists
      end

      def insert_token(database, username, token, expire_at_string, clear_expired_tokens: true)
        checksum = Digest::SHA256.hexdigest(token)
        user = Sequel::Model(database.connection[:users]).find_or_create(name: username)

        database.connection[:authentication_tokens].where(:token_checksum => checksum).delete
        Sequel::Model(database.connection[:authentication_tokens]).
          create(token_checksum: checksum, expire_at: expire_at_string.to_s, user_id: user.id)
        return unless clear_expired_tokens

        database.connection[:authentication_tokens].where { expire_at < Sequel::CURRENT_TIMESTAMP }.delete
      end

      private

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

      def checksum(token)
        Digest::SHA256.hexdigest(token)
      end
    end
  end
end
