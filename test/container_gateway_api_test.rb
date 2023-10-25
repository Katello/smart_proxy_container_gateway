require 'test_helper'
require 'webmock/test_unit'
require 'rack/test'
require 'mocha/test_unit'

class ContainerGatewayApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  require 'smart_proxy_container_gateway/container_gateway'
  Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                     :katello_registry_path => '/v2/',
                                                     :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                     :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                     :sqlite_db_path => 'container_gateway_test.db')
  require 'smart_proxy_container_gateway/container_gateway_api'

  def app
    Proxy::ContainerGateway::Api.new
  end

  def setup
    Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                       :sqlite_db_path => 'container_gateway_test.db')
  end

  def teardown
    Proxy::ContainerGateway::AuthenticationToken.dataset.delete
    Proxy::ContainerGateway::RepositoryUser.dataset.delete
    Proxy::ContainerGateway::User.dataset.delete
    Proxy::ContainerGateway::Repository.dataset.delete
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

  def test_pingv2_bad_token
    header "AUTHORIZATION", "Bearer blahblahblah"
    get '/v2'

    assert last_response.unauthorized?
  end

  def test_list_tags
    Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(true)
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/tags/list").
      to_return(:status => 200, :body => "{\"repository\":\"library/test_repo\", \"tags\":[\"latest\"]}")
    get '/v2/library/test_repo/tags/list'
    assert_equal("{\"repository\":\"library/test_repo\", \"tags\":[\"latest\"]}", last_response.body)
  end

  def test_list_tags_pagination_link
    Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(true)
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/tags/list?n=100&last=latest").
      to_return(:status => 200, :body => "{\"repository\":\"library/test_repo\", \"tags\":[\"latest\"]}",
                :headers => { 'link' => ["<#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                                         "/v2/library/test_repo/tags/list?n=100&last=latest>; rel=\"next\""] })
    get '/v2/library/test_repo/tags/list?n=100&last=latest'
    assert_equal("{\"repository\":\"library/test_repo\", \"tags\":[\"latest\"]}", last_response.body)
    assert_equal("<#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                   "/v2/library/test_repo/tags/list?n=100&last=latest>; rel=\"next\"",
                 last_response.headers['link'])
  end

  def test_redirects_manifest_request
    Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(true)
    redirect_headers = {
      'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                    "/pulp/container/library/test_repo/manifests/test_tag?validate_token=test_token"
    }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/manifests/test_tag").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    get '/v2/library/test_repo/manifests/test_tag'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
  end

  def test_redirects_blob_request
    ::Proxy::ContainerGateway.expects(:authorized_for_repo?).returns(true)
    redirect_headers = { 'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                                       "/pulp/container/library/test_repo/blobs/test_digest?validate_token=test_token" }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/blobs/test_digest").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    get '/v2/library/test_repo/blobs/test_digest'
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

  def test_put_repository_list
    repo_list = { 'repositories' => [{ 'repository' => 'test_repo', 'auth_required' => 'false' }] }
    ::Proxy::ContainerGateway.expects(:update_repository_list).with(repo_list['repositories']).returns(true)
    put '/repository_list', repo_list
    assert last_response.ok?
  end

  def test_v1_search_with_user
    ::Proxy::ContainerGateway::User.expects(:find).with(name: 'test_user').returns('test_user')
    ::Proxy::ContainerGateway.expects(:catalog).with('test_user').returns(["test_repo"])

    foreman_auth_response = { :token => 'not unauthorized' }
    stub_request(:get, "https://foreman/v2/token?account=test_user").
      with(
        headers: {
          'Authorization' => 'Basic dGVzdF91c2VyOnRlc3RfcGFzc3dvcmQ=',
          'Content-Type' => 'application/json'
        }
      ).to_return(:body => foreman_auth_response.to_json)

    header 'HTTP_USER_AGENT', 'notpodman'
    # Basic test_user:test_password
    header "AUTHORIZATION", "Basic dGVzdF91c2VyOnRlc3RfcGFzc3dvcmQ="

    get '/v1/search'
    assert last_response.ok?
    assert_equal [{ "name" => "test_repo" }], JSON.parse(last_response.body)["results"]
  end

  def test_v1_search_with_no_user
    ::Proxy::ContainerGateway.expects(:catalog).with(nil).returns(["test_repo"])
    header 'HTTP_USER_AGENT', 'notpodman'
    get '/v1/search'
    assert last_response.ok?
    assert_equal [{ "name" => "test_repo" }], JSON.parse(last_response.body)["results"]
  end

  def test_catalog_unauthorized_token
    header "AUTHORIZATION", "Basic unauthorized"
    ::Proxy::ContainerGateway.expects(:catalog).with.returns(["test_repo"])
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
      "issued_at": DateTime.now,
      "expires_in": 180
    }
    stub_request(:get, "#{::Proxy::SETTINGS.foreman_url}/v2/token?account=foo").
      to_return(:body => foreman_response.to_json)

    repo_response = { "repositories": [{ repository: "test_repo", auth_required: false }] }
    stub_request(:get, "https://foreman/v2/_catalog?account=foo").
      to_return(:body => repo_response.to_json)

    # Basic foo:bar
    header "AUTHORIZATION", "Basic Zm9vOmJhcg=="

    get '/v2/token?account=foo'

    assert last_response.ok?
    assert_equal "imarealtoken", JSON.parse(last_response.body)["token"]
  end
end
