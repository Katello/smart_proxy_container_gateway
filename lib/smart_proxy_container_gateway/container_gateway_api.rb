require 'sinatra'
require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'

module Proxy::ContainerGateway

  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    get '/v2/?' do
      Proxy::ContainerGateway.ping
    end

    get '/v2/:repository/manifests/:tag/?' do
      redirection_location = Proxy::ContainerGateway.get_manifests(params[:repository], params[:tag])
      redirect to(redirection_location)
    end

    get '/v2/:repository/blobs/:digest/?' do
      redirection_location = Proxy::ContainerGateway.get_blobs(params[:repository], params[:digest])
      redirect to(redirection_location)
    end

    get '/v2/_catalog/?' do
      Proxy::ContainerGateway.get_catalog
    end
  end
end
