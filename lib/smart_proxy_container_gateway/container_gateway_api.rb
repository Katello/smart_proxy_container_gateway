require 'sinatra'
require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'

module Proxy
  module ContainerGateway
    class Api < ::Sinatra::Base
      include ::Proxy::Log
      helpers ::Proxy::Helpers

      get '/v2/?' do
        Proxy::ContainerGateway.ping
      end

      get '/v2/:repository/manifests/:tag/?' do
        redirection_location = Proxy::ContainerGateway.manifests(params[:repository], params[:tag])
        redirect to(redirection_location)
      end

      get '/v2/:repository/blobs/:digest/?' do
        redirection_location = Proxy::ContainerGateway.blobs(params[:repository], params[:digest])
        redirect to(redirection_location)
      end

      get '/v2/_catalog/?' do
        Proxy::ContainerGateway.catalog
      end
    end
  end
end
