require 'sinatra'
require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'
require 'smart_proxy_container_gateway/foreman_api'
require 'sqlite3'

module Proxy
  module ContainerGateway
    class Api < ::Sinatra::Base
      include ::Proxy::Log
      helpers ::Proxy::Helpers
      helpers ::Sinatra::Authorization::Helpers

      get '/v1/_ping/?' do
        Proxy::ContainerGateway.ping
      end

      get '/v2/?' do
        if auth_header.present? && (auth_header.unauthorized_token? || auth_header.valid_user_token?)
          response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
          Proxy::ContainerGateway.ping
        else
          redirect_authorization_headers
          halt 401, "unauthorized"
        end
      end

      get '/v2/*/manifests/*/?' do
        repository = params[:splat][0]
        tag = params[:splat][1]
        handle_repo_auth(repository, auth_header, request)
        redirection_location = Proxy::ContainerGateway.manifests(repository, tag)
        redirect to(redirection_location)
      end

      get '/v2/*/blobs/*/?' do
        repository = params[:splat][0]
        digest = params[:splat][1]
        handle_repo_auth(repository, auth_header, request)
        redirection_location = Proxy::ContainerGateway.blobs(repository, digest)
        redirect to(redirection_location)
      end

      get '/v1/search/?' do
        # Checks for podman client and issues a 404 in that case. Podman
        # examines the response from a /v1/search request. If the result
        # is a 4XX, it will then proceed with a request to /_catalog
        if !request.env['HTTP_USER_AGENT'].nil? && request.env['HTTP_USER_AGENT'].downcase.include?('libpod')
          halt 404, "not found"
        end

        if auth_header.present? && !auth_header.blank?
          username = auth_header.v1_foreman_authorized_username
          if username.nil?
            halt 401, "unauthorized"
          end
          params[:user] = username
        end
        repositories = Proxy::ContainerGateway.v1_search(params)

        content_type :json
        { num_results: repositories.size, query: params[:q], results: repositories }.to_json
      end

      get '/v2/_catalog/?' do
        catalog = []
        if auth_header.present?
          if auth_header.unauthorized_token?
            catalog = Proxy::ContainerGateway.catalog
          elsif auth_header.valid_user_token?
            catalog = Proxy::ContainerGateway.catalog(auth_header.user)
          else
            redirect_authorization_headers
            halt 401, "unauthorized"
          end
        else
          redirect_authorization_headers
          halt 401, "unauthorized"
        end

        content_type :json
        { repositories: catalog }.to_json
      end

      get '/v2/token' do
        response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'

        unless auth_header.present? && auth_header.basic_auth?
          one_year = (60 * 60 * 24 * 365)
          return { token: AuthorizationHeader::UNAUTHORIZED_TOKEN, issued_at: Time.now.iso8601,
                   expires_at: (Time.now + one_year).iso8601 }.to_json
        end

        token_response = ForemanApi.new.fetch_token(auth_header.raw_header, request.params)
        if token_response.code.to_i != 200
          halt token_response.code.to_i, token_response.body
        else
          token_response_body = JSON.parse(token_response.body)
          ContainerGateway.insert_token(request.params['account'], token_response_body['token'],
                                        token_response_body['expires_at'])

          repo_response = ForemanApi.new.fetch_user_repositories(auth_header.raw_header, request.params)
          if repo_response.code.to_i != 200
            halt repo_response.code.to_i, repo_response.body
          else
            ContainerGateway.update_user_repositories(request.params['account'],
                                                      JSON.parse(repo_response.body)['repositories'])
          end
          return token_response_body.to_json
        end
      end

      get '/users/?' do
        do_authorize_any

        content_type :json
        { users: User.map(:name) }.to_json
      end

      put '/user_repository_mapping/?' do
        do_authorize_any

        ContainerGateway.update_user_repo_mapping(params)
        {}
      end

      put '/repository_list/?' do
        do_authorize_any

        repositories = params['repositories'].nil? ? [] : params['repositories']
        ContainerGateway.update_repository_list(repositories)
        {}
      end

      private

      def handle_repo_auth(repository, auth_header, request)
        user_token_is_valid = false
        # FIXME: Getting unauthenticated token here...
        if auth_header.present? && auth_header.valid_user_token?
          user_token_is_valid = true
          username = auth_header.user.name
        end
        username = request.params['account'] if username.nil?

        return if Proxy::ContainerGateway.authorized_for_repo?(repository, user_token_is_valid, username)

        redirect_authorization_headers
        halt 401, "unauthorized"
      end

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

        def user
          ContainerGateway.token_user(@value.split(' ')[1])
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

        def blank?
          Base64.decode64(@value.split(' ')[1]) == ':'
        end

        # A special case for the V1 API.  Defer authentication to Foreman and return the username. `nil` if not authorized.
        def v1_foreman_authorized_username
          username = Base64.decode64(@value.split(' ')[1]).split(':')[0]
          auth_response = ForemanApi.new.fetch_token(raw_header, { 'account' => username })
          return username if auth_response.code.to_i == 200 && (JSON.parse(auth_response.body)['token'] != 'unauthenticated')

          nil
        end
      end
    end
  end
end
