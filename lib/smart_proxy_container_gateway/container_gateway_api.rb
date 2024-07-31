require 'active_support'
require 'active_support/core_ext/integer'
require 'active_support/core_ext/string'
require 'active_support/time_with_zone'
require 'sinatra'
require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'
require 'smart_proxy_container_gateway/foreman_api'

module Proxy
  module ContainerGateway
    class Api < ::Sinatra::Base
      include ::Proxy::Log
      helpers ::Proxy::Helpers
      helpers ::Sinatra::Authorization::Helpers
      extend ::Proxy::ContainerGateway::DependencyInjection

      inject_attr :database_impl, :database
      inject_attr :container_gateway_main_impl, :container_gateway_main

      get '/v1/_ping/?' do
        pulp_response = container_gateway_main.ping(translated_headers_for_proxy)
        status pulp_response.code.to_i
        body pulp_response.body
      end

      get '/v2/?' do
        if auth_header.present? && (auth_header.unauthorized_token? || auth_header.valid_user_token?)
          response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
          pulp_response = container_gateway_main.ping(translated_headers_for_proxy)
          status pulp_response.code.to_i
          body pulp_response.body
        else
          redirect_authorization_headers
          halt 401, "unauthorized"
        end
      end

      get '/v2/*/manifests/*/?' do
        repository = params[:splat][0]
        tag = params[:splat][1]
        handle_repo_auth(repository, auth_header, request)
        pulp_response = container_gateway_main.manifests(repository, tag, translated_headers_for_proxy)
        if pulp_response.code.to_i >= 400
          status pulp_response.code.to_i
          body pulp_response.body
        else
          redirection_location = pulp_response['location']
          redirect to(redirection_location)
        end
      end

      put '/v2/*/manifests/*/?' do
        throw_unsupported_error
      end

      get '/v2/*/blobs/*/?' do
        head_or_get_blobs
      end

      head '/v2/*/blobs/*/?' do
        head_or_get_blobs
      end

      post '/v2/*/blobs/uploads/?' do
        throw_unsupported_error
      end

      put '/v2/*/blobs/uploads/*/?' do
        throw_unsupported_error
      end

      patch '/v2/*/blobs/uploads/*/?' do
        throw_unsupported_error
      end

      get '/v2/*/tags/list/?' do
        repository = params[:splat][0]
        handle_repo_auth(repository, auth_header, request)
        pulp_response = container_gateway_main.tags(repository, translated_headers_for_proxy, params)
        # "link"=>["<http://pulpcore-api/v2/container-image-name/tags/list?n=100&last=last-tag-name>; rel=\"next\""],
        # https://docs.docker.com/registry/spec/api/#pagination-1
        if pulp_response['link'].nil?
          headers['link'] = ""
        else
          headers['link'] = pulp_response['link']
        end
        status pulp_response.code.to_i
        body pulp_response.body
      end

      get '/v1/search/?' do
        # Checks for v2 client and issues a 404 in that case. Podman
        # examines the response from a /v1/search request. If the result
        # is a 4XX, it will then proceed with a request to /_catalog
        if request.env['HTTP_DOCKER_DISTRIBUTION_API_VERSION'] == 'registry/2.0'
          halt 404, "not found"
        end

        if auth_header.present? && !auth_header.blank?
          username = auth_header.v1_foreman_authorized_username
          if username.nil?
            halt 401, "unauthorized"
          end
          params[:user] = username
        end
        repositories = container_gateway_main.v1_search(params)

        content_type :json
        {
          num_results: repositories.size,
          query: params[:q],
          results: repositories.map { |repo_name| { description: '', name: repo_name } }
        }.to_json
      end

      get '/v2/_catalog/?' do
        catalog = []
        if auth_header.present?
          if auth_header.unauthorized_token?
            catalog = container_gateway_main.catalog.select_map(::Sequel[:repositories][:name])
          elsif auth_header.valid_user_token?
            catalog = container_gateway_main.catalog(auth_header.user).select_map(::Sequel[:repositories][:name])
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
          return { token: AuthorizationHeader::UNAUTHORIZED_TOKEN, issued_at: Time.now.rfc3339,
                   expires_in: 1.year.seconds.to_i }.to_json
        end

        token_response = ForemanApi.new.fetch_token(auth_header.raw_header, request.params)
        if token_response.code.to_i != 200
          halt token_response.code.to_i, token_response.body
        else
          # This returned token should follow OAuth2 spec. We need some minor conversion
          # to store the token with the expires_at time (using rfc3339).
          token_response_body = JSON.parse(token_response.body)

          if token_response_body['token'].nil?
            halt 502, "Recieved malformed token response"
          end

          # "issued_at" is an optional field. Per OAuth2 we assume time of token response as
          # the issue time if the field is ommitted.
          token_issue_time = (token_response_body["issued_at"] || token_response["Date"])&.to_time
          if token_issue_time.nil?
            halt 502, "Recieved malformed token response"
          end

          # 'expires_in' is an optional field. If not provided, assume 60 seconds per OAuth2 spec
          expires_in = token_response_body.fetch("expires_in", 60)
          expires_at = token_issue_time + expires_in.seconds

          container_gateway_main.insert_token(
            request.params['account'],
            token_response_body['token'],
            expires_at.rfc3339
          )

          repo_response = ForemanApi.new.fetch_user_repositories(auth_header.raw_header, request.params)
          if repo_response.code.to_i != 200
            halt repo_response.code.to_i, repo_response.body
          else
            container_gateway_main.update_user_repositories(request.params['account'],
                                                            JSON.parse(repo_response.body)['repositories'])
          end

          # Return the original token response from Katello
          return token_response.body
        end
      end

      get '/users/?' do
        do_authorize_any

        content_type :json
        { users: database.connection[:users].map(:name) }.to_json
      end

      put '/user_repository_mapping/?' do
        do_authorize_any

        container_gateway_main.update_user_repo_mapping(params)
        {}
      end

      put '/repository_list/?' do
        do_authorize_any

        repositories = params['repositories'].nil? ? [] : params['repositories']
        container_gateway_main.update_repository_list(repositories)
        {}
      end

      private

      def head_or_get_blobs
        repository = params[:splat][0]
        digest = params[:splat][1]
        handle_repo_auth(repository, auth_header, request)
        pulp_response = container_gateway_main.blobs(repository, digest, translated_headers_for_proxy)
        if pulp_response.code.to_i >= 400
          status pulp_response.code.to_i
          body pulp_response.body
        else
          redirection_location = pulp_response['location']
          redirect to(redirection_location)
        end
      end

      def throw_unsupported_error
        content_type :json
        body({
          "errors" => [
            {
              "code" => "UNSUPPORTED",
              "message" => "Pushing content is unsupported"
            }
          ]
        }.to_json)
        halt 404
      end

      def throw_repo_not_found_error
        content_type :json
        body({
          "errors" => [
            {
              "code" => "NAME_UNKNOWN",
              "message" => "Repository name unknown"
            }
          ]
        }.to_json)
        halt 404
      end

      def translated_headers_for_proxy
        current_headers = {}
        env = request.env.select do |key, _value|
          key.match("^HTTP_.*")
        end
        env.each do |header|
          current_headers[header[0].split('_')[1..].join('-')] = header[1]
        end
        current_headers
      end

      def handle_repo_auth(repository, auth_header, request)
        user_token_is_valid = false
        if auth_header.present? && auth_header.valid_user_token?
          user_token_is_valid = true
          username = auth_header.user[:name]
        end
        username = request.params['account'] if username.nil?

        return if container_gateway_main.authorized_for_repo?(repository, user_token_is_valid, username)

        redirect_authorization_headers
        throw_repo_not_found_error
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
        extend ::Proxy::ContainerGateway::DependencyInjection

        inject_attr :database_impl, :database
        inject_attr :container_gateway_main_impl, :container_gateway_main
        UNAUTHORIZED_TOKEN = 'unauthorized'.freeze

        def initialize(value)
          @value = value || ''
        end

        def user
          container_gateway_main.token_user(@value.split(' ')[1])
        end

        def valid_user_token?
          token_auth? && container_gateway_main.valid_token?(@value.split(' ')[1])
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
