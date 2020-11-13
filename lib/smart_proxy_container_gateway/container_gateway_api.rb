require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_main'
require 'sequel'
require 'pg'

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

    get '/v2/db_test/?' do
      conn = Sequel.connect(adapter: :postgres,
                            user: Proxy::ContainerGateway::Plugin.settings.postgres_db_username,
                            password: Proxy::ContainerGateway::Plugin.settings.postgres_db_password,
                            database: 'smart_proxy_container_gateway')
      string = ""
      conn['SELECT * FROM pg_stat_activity'].each do |row|
        string += row.to_s
      end
      string
    end
  end
end
