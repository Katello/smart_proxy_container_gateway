require 'test_helper'
require 'webmock/test_unit'
require 'mocha/test_unit'
require 'rack/test'

require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_api'

class ContainerGatewayApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::ContainerGateway::Api.new
  end

  def test_ping
    Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key")
    Proxy::ContainerGateway::Plugin.settings.pulp_endpoint = 'https://test.example.com'
    stub_request(:get, ::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint + '/pulpcore_registry/v2/').to_return(:body => '{}')
    get '/v2'

    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
    assert_equal('{}', last_response.body)
  end
end
