require 'uri'

module Proxy
  module ContainerGateway
    class ForemanApi
      def fetch_token(auth_header, params)
        url = URI.join(Proxy::SETTINGS.foreman_url, Proxy::ContainerGateway::Plugin.settings.katello_registry_path, 'token')
        url.query = process_params(params)

        req = Net::HTTP::Get.new(url)
        req.add_field('Authorization', auth_header)
        req.add_field('Accept', 'application/json')
        req.content_type = 'application/json'
        http = Net::HTTP.new(url.hostname, url.port)
        http.use_ssl = true

        http.request(req)
      end

      def process_params(params_in)
        params = params_in.slice('scope', 'account').compact
        URI.encode_www_form(params)
      end
    end
  end
end
