require 'sinatra'
require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'
require 'smart_proxy_container_gateway/foreman_api'
require 'sequel'
require 'sqlite3'

module Proxy
  module ContainerGateway
    class Api < ::Sinatra::Base
      include ::Proxy::Log
      helpers ::Proxy::Helpers
      Sequel.extension :migration, :core_extensions

      get '/v1/_ping/?' do
        Proxy::ContainerGateway.ping
      end

      get '/v2/?' do
        if auth_header.present? && (auth_header.unauthorized_token? || auth_header.valid_user_token?)
          Proxy::ContainerGateway.ping
        else
          redirect_authorization_headers
          halt 401, "unauthorized"
        end
      end

      get '/v2/:repository/manifests/:tag/?' do
        unless Proxy::ContainerGateway.authorized_for_repo?(params[:repository])
          redirect_authorization_headers
          halt 401, "unauthorized"
        end
        redirection_location = Proxy::ContainerGateway.manifests(params[:repository], params[:tag])
        redirect to(redirection_location)
      end

      get '/v2/:repository/blobs/:digest/?' do
        unless Proxy::ContainerGateway.authorized_for_repo?(params[:repository])
          redirect_authorization_headers
          halt 401, "unauthorized"
        end
        redirection_location = Proxy::ContainerGateway.blobs(params[:repository], params[:digest])
        redirect to(redirection_location)
      end

      get '/v1/search/?' do
        # Checks for podman client and issues a 404 in that case. Podman
        # examines the response from a /v1_search request. If the result
        # is a 4XX, it will then proceed with a request to /_catalog
        if !request.env['HTTP_USER_AGENT'].nil? && request.env['HTTP_USER_AGENT'].downcase.include?('libpod')
          halt 404, "not found"
        end

        repositories = Proxy::ContainerGateway.v1_search(params)

        content_type :json
        { num_results: repositories.size, query: params[:q], results: repositories }.to_json
      end

      get '/v2/_catalog/?' do
        content_type :json
        { repositories: Proxy::ContainerGateway.catalog }.to_json
      end

      get '/v2/unauthenticated_repository_list/?' do
        content_type :json
        { repositories: Proxy::ContainerGateway.unauthenticated_repos }.to_json
      end

      get '/v2/token' do
        response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'

        unless auth_header.present? && auth_header.basic_auth?
          one_year = (60 * 60 * 24 * 365)
          return { token: AuthorizationHeader::UNAUTHORIZED_TOKEN, issued_at: Time.now,
expires_at: Time.now + one_year }.to_json
        end

        token_response = ForemanApi.new.fetch_token(auth_header.raw_header, request.params)
        if token_response.code.to_i != 200
          halt token_response.code.to_i, token_response.body
        else
          token_response_body = JSON.parse(token_response.body)
          ContainerGateway.insert_token(request.params['account'], token_response_body['token'],
                                        token_response_body['expires_at'])
          return token_response_body.to_json
        end
      end

      put '/v2/unauthenticated_repository_list/?' do
        if params.key? :repositories
          repo_names = params[:repositories]
        else
          repo_names = JSON.parse(request.body.read)["repositories"]
        end
      rescue JSON::ParserError
        halt 400, "malformed repositories json"
      else
        if repo_names.nil?
          Proxy::ContainerGateway.update_unauthenticated_repos([])
        else
          Proxy::ContainerGateway.update_unauthenticated_repos(repo_names)
        end
      end

      private

      def redirect_authorization_headers
        response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
        response.headers['Www-Authenticate'] = "Bearer realm=\"https://#{request.host}/v2/token\"," \
                                               "service=\"#{request.host}\"," \
                                               "scope=\"repository:registry:pull,push\""
      end

      def auth_header
        AuthorizationHeader.new(request.env['HTTP_AUTHORIZATION'])
      end

      class AuthorizationHeader
        UNAUTHORIZED_TOKEN = 'unauthorized'.freeze

        def initialize(value)
          @value = value || ''
        end

        def valid_user_token?
          token_auth? && ContainerGateway.valid_token?(@value.split(' ')[1])
        end

        def raw_header
          @value
        end

        def present?
          !@value.nil? && @value != ""
        end

        def unauthorized_token?
          @value.split(' ')[1] == UNAUTHORIZED_TOKEN
        end

        def token_auth?
          @value.split(' ')[0] == 'Bearer'
        end

        def basic_auth?
          @value.split(' ')[0] == 'Basic'
        end
      end
    end
  end
end
