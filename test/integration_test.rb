require 'tempfile'
require 'json'

require 'test_helper'
require 'root/root_v2_api'
require 'smart_proxy_container_gateway/container_gateway'

class ContainerGatewayApiFeaturesTest < Test::Unit::TestCase
  include Rack::Test::Methods
  include ::Proxy::Log

  def app
    Proxy::PluginInitializer.new(Proxy::Plugins.instance).initialize_plugins
    Proxy::RootV2Api.new
  end

  def test_features
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file)
                              .with('container_gateway.yml')
                              .returns(enabled: true, db_connection_string: 'sqlite://',
                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                       :pulp_client_ssl_ca => "#{__dir__}/fixtures/mock_pulp_ca.pem")

    get '/features'

    response = JSON.parse(last_response.body)

    mod = response['container_gateway']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:container_gateway])
    assert_equal([], mod['capabilities'])
    assert_equal({}, mod['settings'])
  end
end
