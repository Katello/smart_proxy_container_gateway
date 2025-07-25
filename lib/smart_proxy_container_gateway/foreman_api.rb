require 'uri'
require 'openssl'

module Proxy
  module ContainerGateway
    class ForemanApi
      def registry_request(auth_header, params, suffix, uuid: '', cert: false)
        uri = URI.join(Proxy::SETTINGS.foreman_url, Proxy::ContainerGateway::Plugin.settings.katello_registry_path, suffix)
        uri.query = process_params(params)

        req = Net::HTTP::Get.new(uri)
        req.add_field('Authorization', auth_header) unless cert
        req.add_field('Accept', 'application/json')
        req.add_field('HostUUID', uuid) if cert
        req.content_type = 'application/json'
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true

        http.request(req)
      end

      def process_params(params_in)
        params = params_in.slice('scope', 'account').compact
        URI.encode_www_form(params)
      end

      def fetch_token(auth_header, params)
        registry_request(auth_header, params, 'token')
      end

      def fetch_user_repositories(auth_header, params)
        registry_request(auth_header, params, '_catalog')
      end

      def fetch_host_repositories(uuid, params)
        registry_request(nil, params, '_catalog', uuid: uuid, cert: true)
      end
    end
  end
end
