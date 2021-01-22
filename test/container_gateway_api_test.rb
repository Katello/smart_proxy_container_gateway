require 'test_helper'
require 'webmock/test_unit'
require 'rack/test'
require 'mocha/test_unit'

require 'smart_proxy_container_gateway/container_gateway'
require 'smart_proxy_container_gateway/container_gateway_api'

class ContainerGatewayApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::ContainerGateway::Api.new
  end

  def setup
    Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                       :katello_registry_path => '/v2/',
                                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                       :sqlite_db_path => 'container_gateway_test.db')
  end

  def test_ping_v1
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/").
      to_return(:body => '{}')
    get '/v1/_ping'

    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
    assert_equal('{}', last_response.body)
  end

  def test_pingv2_unauthorized_token
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/").
      to_return(:body => '{}')

    header "AUTHORIZATION", "Bearer unauthorized"
    get '/v2'

    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
    assert_equal('{}', last_response.body)
  end

  def test_pingv2_no_auth
    get '/v2'
    assert last_response.unauthorized?
  end

  def test_pingv2_user_auth
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/v2/").
      to_return(:body => '{}')
    token = 'ofyourappreciation'

    Proxy::ContainerGateway.insert_token('someuser', token, Time.now + 60)

    header "AUTHORIZATION", "Bearer #{token}"
    get '/v2'
    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
  end

  def test_ping_bad_token
    header "AUTHORIZATION", "Bearer blahblahblah"
    get '/v2'

    assert last_response.unauthorized?
  end

  def test_redirects_manifest_request
    Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(true)
    redirect_headers = {
      'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                    "/pulp/container/test_repo/manifests/test_tag?validate_token=test_token"
    }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/test_repo/manifests/test_tag").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    get '/v2/test_repo/manifests/test_tag'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
  end

  def test_redirects_blob_request
    ::Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(true)
    redirect_headers = { 'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                                       "/pulp/container/test_repo/blobs/test_digest?validate_token=test_token" }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/test_repo/blobs/test_digest").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    get '/v2/test_repo/blobs/test_digest'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
  end

  def test_unauthorized_for_manifests
    ::Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(false)
    get '/v2/test_repo/manifests/test_tag'
    assert_equal 401, last_response.status
  end

  def test_unauthorized_for_blobs
    ::Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(false)
    get '/v2/test_repo/blobs/test_digest'
    assert_equal 401, last_response.status
  end

  def test_put_unauthenticated_repository_list
    ::Proxy::ContainerGateway.expects(:update_unauthenticated_repos).with(["test_repo"]).returns(true)
    put '/v2/unauthenticated_repository_list', repositories: ["test_repo"]
    assert last_response.ok?
  end

  def test_get_unauthenticated_repository_list
    ::Proxy::ContainerGateway.expects(:unauthenticated_repos).returns(["test_repo"])
    get '/v2/unauthenticated_repository_list'
    assert last_response.ok?
    assert_equal ["test_repo"], JSON.parse(last_response.body)["repositories"]
  end

  def test_v1_search
    ::Proxy::ContainerGateway.expects(:unauthenticated_repos).returns(["test_repo"])
    header 'HTTP_USER_AGENT', 'notpodman'
    get '/v1/search'
    assert last_response.ok?
    assert_equal [{ "name" => "test_repo" }], JSON.parse(last_response.body)["results"]
  end

  def test_catalog
    ::Proxy::ContainerGateway.expects(:unauthenticated_repos).returns(["test_repo"])
    get '/v2/_catalog'
    assert last_response.ok?
    assert_equal ["test_repo"], JSON.parse(last_response.body)["repositories"]
  end

  def test_token_no_auth
    get '/v2/token'

    assert last_response.ok?
    assert_equal JSON.parse(last_response.body)["token"], 'unauthorized'
  end

  def test_token_basic_auth
    ::Proxy::SETTINGS.foreman_url = 'https://foreman'
    foreman_response = {
      "token": "imarealtoken",
        "expires_at": DateTime.now + (2 / 24.0)
    }
    stub_request(:get, "#{::Proxy::SETTINGS.foreman_url}/v2/token?account=foo").
      to_return(:body => foreman_response.to_json)

    # Basic foo:bar
    header "AUTHORIZATION", "Basic Zm9vOmJhcg=="

    get '/v2/token?account=foo'

    assert last_response.ok?
    assert_equal "imarealtoken", JSON.parse(last_response.body)["token"]
  end
end
