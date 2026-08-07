require 'proxy/request'

module Proxy
  module ContainerGateway
    class ForemanApi < ::Proxy::HttpRequest::ForemanRequest
      def registry_request(auth_header, params, suffix, uuid: '', cert: false)
        path = "#{Proxy::ContainerGateway::Plugin.settings.katello_registry_path}#{suffix}"
        query = params.slice('scope', 'account').compact

        headers = {}
        headers['Authorization'] = auth_header unless cert
        headers['HostUUID'] = uuid if cert

        req = request_factory.create_get(path, query, headers)
        send_request(req)
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
