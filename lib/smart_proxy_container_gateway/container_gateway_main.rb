require 'net/http'
require 'uri'

module Proxy::ContainerGateway
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self

    def pulp_registry_request(uri)
      cert = OpenSSL::X509::Certificate.new(File.open(Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_cert, 'r').read)
      key =  OpenSSL::PKey::RSA.new(File.open(Proxy::ContainerGateway::Plugin.settings.pulp_client_ssl_key, 'r').read)

      http_client = Net::HTTP.new(uri.host, uri.port)
      http_client.cert = cert
      http_client.key = key
      http_client.use_ssl = true

      http_client.start do |http|
        request = Net::HTTP::Get.new uri
        http.request request
      end
    end

    def ping
      uri = URI.parse(Proxy::ContainerGateway::Plugin.settings.pulp_endpoint + '/pulpcore_registry/v2/')
      pulp_registry_request(uri).body
    end

    def get_manifests(repository, tag)
      uri = URI.parse(Proxy::ContainerGateway::Plugin.settings.pulp_endpoint + '/pulpcore_registry/v2/' +
                      repository + '/manifests/' + tag)
      pulp_registry_request(uri)['location']
    end

    def get_blobs(repository, digest)
      uri = URI.parse(Proxy::ContainerGateway::Plugin.settings.pulp_endpoint + '/pulpcore_registry/v2/' +
                      repository + '/blobs/' + digest)
      pulp_registry_request(uri)['location']
    end

    def get_catalog
      uri = URI.parse(Proxy::ContainerGateway::Plugin.settings.pulp_endpoint + '/pulpcore_registry/v2/_catalog')
      pulp_registry_request(uri).body
    end
  end
end
