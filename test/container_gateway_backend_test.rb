require 'test_helper'
require 'webmock/test_unit'
require 'rack/test'
require 'mocha/test_unit'

require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_api'

class ContainerGatewayBackendTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::ContainerGateway::Api.new
  end

  def setup
    Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                       :postgres_db_username => 'smart_proxy_container_gateway_test_user',
                                                       :postgres_db_password => 'smart_proxy_container_gateway_test_password',
                                                       :postgres_db_name => 'smart_proxy_container_gateway_test',
                                                       :postgres_db_hostname => 'localhost')
  end

  def teardown
    ::Proxy::ContainerGateway.update_unauthenticated_repos([])
  end

  def test_update_unauthenticated_repos
    ::Proxy::ContainerGateway.update_unauthenticated_repos(["test_repo1", "test_repo2"])
    assert_equal ["test_repo1", "test_repo2"], ::Proxy::ContainerGateway.unauthenticated_repos
  end

  def test_empty_unauthenticated_repos
    ::Proxy::ContainerGateway.update_unauthenticated_repos(["test_repo1", "test_repo2"])
    ::Proxy::ContainerGateway.update_unauthenticated_repos([])
    assert_empty ::Proxy::ContainerGateway.unauthenticated_repos
  end

  def test_catalog
    ::Proxy::ContainerGateway.update_unauthenticated_repos(["test_repo1", "test_repo2", "test_repo3"])
    assert_equal ["test_repo1", "test_repo2", "test_repo3"], ::Proxy::ContainerGateway.catalog
  end

  def test_authorized_for_repo?
    ::Proxy::ContainerGateway.update_unauthenticated_repos(["test_repo1", "test_repo2"])
    assert_true ::Proxy::ContainerGateway.authorized_for_repo?("test_repo1")
    assert_true ::Proxy::ContainerGateway.authorized_for_repo?("test_repo2")
  end
end
