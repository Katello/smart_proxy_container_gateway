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

  def test_v1_search_query
    ::Proxy::ContainerGateway.update_unauthenticated_repos(["test_repo1", "test_repo2"])
    assert_equal [{ :name => "test_repo1" }, { :name => "test_repo2" }], ::Proxy::ContainerGateway.v1_search
    assert_equal [{ :name => "test_repo1" }], ::Proxy::ContainerGateway.v1_search(q: "1")
    assert_equal [{ :name => "test_repo2" }], ::Proxy::ContainerGateway.v1_search(q: "2")
  end

  def test_v1_item_limit
    ::Proxy::ContainerGateway.update_unauthenticated_repos(["test_repo1", "test_repo2"])
    assert_equal [{ :name => "test_repo1" }, { :name => "test_repo2" }], ::Proxy::ContainerGateway.v1_search(n: "2")
    assert_equal [{ :name => "test_repo1" }], ::Proxy::ContainerGateway.v1_search(n: "1")
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

  def test_insert_token
    ::Proxy::ContainerGateway.insert_token('joe', 'mytoken', Time.now + 60)
    assert ::Proxy::ContainerGateway.valid_token?('mytoken')
  end

  def test_bad_valid_token
    refute ::Proxy::ContainerGateway.valid_token?('notmytoken')
  end

  def test_expired_tokens_deleted
    ::Proxy::ContainerGateway.initialize_db[:authentication_tokens].delete
    ::Proxy::ContainerGateway.insert_token('joe', 'myexpiredtoken', DateTime.now - (1 / 24.0), clear_expired_tokens: false)

    refute ::Proxy::ContainerGateway.valid_token?('mytoken')
  end
end
