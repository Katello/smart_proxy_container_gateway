require 'net/http'
require 'uri'
require 'digest'
require 'sequel'
module Proxy
  module ContainerGateway
    extend Proxy::DHCP::DependencyInjection
    extend ::Proxy::Util
    extend ::Proxy::Log

    inject_attr :database, :database

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

        user = params[:user].nil? ? nil : database[:useres].find(name: params[:user])

        # TODO: relies on catalog returning a query
        repositories = query ? catalog(user).filter(:name.like("%#{query}%")) : catalog(user)
        repositories.limit(limit)
      end

      def catalog(user = nil)
        if user.nil?
          unauthenticated_repos
        else
          # TODO implement as a single query
          unauthenticated_repos | user.repositories_dataset.select(:name)
        end
      end

      def unauthenticated_repos
        database[:repository].where(auth_required: false).order(:name).select(:name)
      end

      # Replaces the entire list of repositories
      def update_repository_list(repo_list)
        # TODO: make repositories_users cascade on delete repository
        database[:repositories_users].delete

        repository = database[:repository]
        repository.delete

        repository.import(
          [:name, :auth_required],
          repo_list.map { |repo| [repo['repository'], repo['auth_required'].to_s.downcase == "true"] },
        )
      end

      # Replaces the entire user-repo mapping for all logged-in users
      def update_user_repo_mapping(user_repo_maps)
        # Get hash map of all users and their repositories
        # Ex: {"users"=> [{"admin"=>[{"repository"=>"repo", "auth_required"=>"true"}]}]}
        # Go through list of repositories and add them to the DB
        repositories = database[:repositories]

        entries = user_repo_maps['users'].flat_map do |user_repo_map|
          user_repo_map.filter_map do |username, repos|
            user_repo_names = repos.filter { |repo| repo['auth_required'].to_s.downcase == "true" }.map { |repo| repo['repository'] }
            user = database[:user].find(name: username)
            # TODO: check you can select a static column like this
            repositories.where(name: user_repo_names, auth_required: true).select(:id, user_id: user.id)
          end
        end

        repository_users = database[:repository_users]
        repository_users.delete
        repositories_users.import([:repository_id, :user_id], entries)
      end

      # Replaces the user-repo mapping for a single user
      def update_user_repositories(username, repositories)
        user = database[:user].find(name: username)

        user_repositories = database[:user_repositories]
        user_repositories.delete(user_id: user.id)

        user_repositories.import(
          [:repository_id, :user_id],
          # TODO: check you can select a static column like this
          database[:repositories].where(name: repositories, auth_required: true).select(:id, user_id: user.id),
        )
      end

      def authorized_for_repo?(repo_name, user_token_is_valid, username = nil)
        repository = database[:repositories].find(name: repo_name)

        # Repository doesn't exist
        return false if repository.nil?

        # Repository doesn't require auth
        return true unless repository.auth_required

        if username && user_token_is_valid
          # User is logged in and has access to the repository
          return database[:repositories_users].where(repository_id: repository.id, user_id: database[:user].select(:id).where(name: username)).exists
        end

        false
      end

      def token_user(token)
        database[:users].find(id: database[:authentication_tokens].where(token_checksum: checksum(token)).select(:user_id))
      end

      def valid_token?(token)
        database[:authentication_tokens].where(token_checksum: checksum(token)).where do
          expire_at > Sequel::CURRENT_TIMESTAMP
        end.exists
      end

      def insert_token(username, token, expire_at_string, clear_expired_tokens: true)
        user = database[:users].find_or_create(name: username)

        authentication_tokens = database[:authentication_tokens]

        # TODO: check if this upsert is actually correct
        authentication_tokens.insert_conflict(:update).insert(token_checksum: checksum(token), expire_at: expire_at_string.to_s, user_id: user.id)

        # TODO: create a background service that does this
        authentication_tokens.where { expire_at < Sequel::CURRENT_TIMESTAMP }.delete if clear_expired_tokens
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
