require 'sinatra'
require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'
require 'sequel'
require 'pg'

module Proxy
  module ContainerGateway
    class Api < ::Sinatra::Base
      include ::Proxy::Log
      helpers ::Proxy::Helpers
      Sequel.extension :migration, :core_extensions

      get '/v2/?' do
        Proxy::ContainerGateway.ping
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

      get '/v2/_catalog/?' do
        content_type :json
        { repositories: Proxy::ContainerGateway.catalog }.to_json
      end

      get '/v2/unauthenticated_repository_list/?' do
        content_type :json
        { repositories: Proxy::ContainerGateway.unauthenticated_repos }.to_json
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

      def redirect_authorization_headers
        response.headers['Docker-Distribution-API-Version'] = 'registry/2.0'
        response.headers['Www-Authenticate'] = "Bearer realm=\"https://#{request.host}/v2/token\"," \
                                               "service=\"#{request.host}\"," \
                                               "scope=\"repository:registry:pull,push\""
      end
    end
  end
end
