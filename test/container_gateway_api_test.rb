require 'test_helper'
require 'webmock/test_unit'
require 'rack/test'
require 'mocha/test_unit'

class ContainerGatewayApiTest < Test::Unit::TestCase
  include Rack::Test::Methods

  require 'smart_proxy_container_gateway/container_gateway'
  require 'smart_proxy_container_gateway/container_gateway_api'
  require 'smart_proxy_container_gateway/database'

  def app
    Proxy::ContainerGateway::Api.new
  end

  def setup
    Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                       :pulp_client_ssl_ca => "#{__dir__}/fixtures/mock_pulp_ca.pem",
                                                       :connection_string => 'sqlite://')
    settings = Proxy::ContainerGateway::Plugin.settings
    @database = Proxy::ContainerGateway::Database.new(settings[:connection_string])
    @container_gateway_main = Proxy::ContainerGateway::ContainerGatewayMain.new(
      database: @database, pulp_endpoint: settings[:pulp_endpoint],
      pulp_client_ssl_ca: settings[:pulp_client_ssl_ca],
      pulp_client_ssl_cert: settings[:pulp_client_ssl_cert],
      pulp_client_ssl_key: settings[:pulp_client_ssl_key]
    )
    ::Proxy::ContainerGateway::Api.any_instance.stubs(:database).returns(@database)
    ::Proxy::ContainerGateway::Api.any_instance.stubs(:container_gateway_main).returns(@container_gateway_main)
  end

  def teardown
    @database.connection[:authentication_tokens].delete
    @database.connection[:repositories_users].delete
    @database.connection[:users].delete
    @database.connection[:repositories].delete
    @database.connection[:hosts].delete
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
    ::Proxy::ContainerGateway::Api::AuthorizationHeader.any_instance.expects(:valid_user_token?).returns(true)

    header "AUTHORIZATION", "Bearer some_token"
    get '/v2'
    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
  end

  def test_pingv2_bad_token
    ::Proxy::ContainerGateway::Api::AuthorizationHeader.any_instance.expects(:valid_user_token?).returns(false)
    header "AUTHORIZATION", "Bearer blahblahblah"
    get '/v2'

    assert last_response.unauthorized?
  end

  def test_list_tags
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/tags/list").
      to_return(:status => 200, :body => "{\"repository\":\"library/test_repo\", \"tags\":[\"latest\"]}")
    get '/v2/library/test_repo/tags/list'
    assert_equal("{\"repository\":\"library/test_repo\", \"tags\":[\"latest\"]}", last_response.body)
  end

  def test_list_tags_pagination_link
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
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
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
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

  def test_redirects_manifest_request_with_client_endpoint
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
    @container_gateway_main.stubs(:client_endpoint).returns("https://loadbalancer.example.com")

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
    assert last_response.headers['Location'].include?("https://loadbalancer.example.com")
  end

  def test_redirects_blob_request
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
    redirect_headers = { 'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                                       "/pulp/container/library/test_repo/blobs/test_digest?validate_token=test_token" }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/blobs/test_digest").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    get '/v2/library/test_repo/blobs/test_digest'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
  end

  def test_redirects_blob_request_with_client_endpoint
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
    @container_gateway_main.stubs(:client_endpoint).returns("https://loadbalancer.example.com")

    redirect_headers = { 'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                                       "/pulp/container/library/test_repo/blobs/test_digest?validate_token=test_token" }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/blobs/test_digest").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    get '/v2/library/test_repo/blobs/test_digest'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
    assert last_response.headers['Location'].include?("https://loadbalancer.example.com")
  end

  def test_redirects_blob_head_request
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_repo_auth).returns({})
    redirect_headers = { 'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                                       "/pulp/container/library/test_repo/blobs/test_digest?validate_token=test_token" }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/blobs/test_digest").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    head '/v2/library/test_repo/blobs/test_digest'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
  end

  def test_unauthorized_for_manifests
    @container_gateway_main.expects(:authorized_for_repo?).returns(false)
    get '/v2/test_repo/manifests/test_tag'
    assert_equal 404, last_response.status
  end

  def test_unauthorized_for_blobs
    @container_gateway_main.expects(:authorized_for_repo?).returns(false)
    get '/v2/test_repo/blobs/test_digest'
    assert_equal 404, last_response.status
  end

  def test_put_manifests
    put '/v2/library/test_repo/manifests/test_tag'
    assert_equal 404, last_response.status
    assert_equal({ "errors" => [{ "code" => "UNSUPPORTED", "message" => "Pushing content is unsupported" }] },
                 JSON.parse(last_response.body))
  end

  def test_post_blob_uploads
    post '/v2/library/test_repo/blobs/uploads/'
    assert_equal 404, last_response.status
    assert_equal({ "errors" => [{ "code" => "UNSUPPORTED", "message" => "Pushing content is unsupported" }] },
                 JSON.parse(last_response.body))
  end

  def test_put_blob_uploads
    put '/v2/library/test_repo/blobs/uploads/test_digest'
    assert_equal 404, last_response.status
    assert_equal({ "errors" => [{ "code" => "UNSUPPORTED", "message" => "Pushing content is unsupported" }] },
                 JSON.parse(last_response.body))
  end

  def test_patch_blob_uploads
    put '/v2/library/test_repo/blobs/uploads/test_digest'
    assert_equal 404, last_response.status
    assert_equal({ "errors" => [{ "code" => "UNSUPPORTED", "message" => "Pushing content is unsupported" }] },
                 JSON.parse(last_response.body))
  end

  def test_put_repository_list
    repo_list = { 'repositories' => [{ 'repository' => 'test_repo', 'auth_required' => 'false' }] }
    @container_gateway_main.expects(:update_repository_list).with(repo_list['repositories']).returns(true)
    put '/repository_list', repo_list
    assert last_response.ok?
  end

  def test_v1_search_v2_client
    header 'DOCKER_DISTRIBUTION_API_VERSION', 'registry/2.0'
    get '/v1/search'
    assert last_response.status == 404
  end

  def test_v1_search_with_user
    user_id = @database.connection[:users].insert(name: 'test_user')
    catalog = ["test_repo"]
    @container_gateway_main.expects(:catalog).
      with(@database.connection[:users].first(id: user_id)).returns(catalog)
    catalog.expects(:limit).returns(catalog)
    catalog.expects(:select_map).returns(catalog)

    foreman_auth_response = { :token => 'not unauthorized' }
    stub_request(:get, "https://foreman/v2/token?account=test_user").
      with(
        headers: {
          'Authorization' => 'Basic dGVzdF91c2VyOnRlc3RfcGFzc3dvcmQ=',
          'Content-Type' => 'application/json'
        }
      ).to_return(:body => foreman_auth_response.to_json)

    header 'DOCKER_DISTRIBUTION_API_VERSION', 'registry/1.0'
    # Basic test_user:test_password
    header "AUTHORIZATION", "Basic dGVzdF91c2VyOnRlc3RfcGFzc3dvcmQ="

    get '/v1/search?user=test_user'
    assert last_response.ok?
    assert_equal [{ "description" => "", "name" => "test_repo" }], JSON.parse(last_response.body)["results"]
  end

  def test_v1_search_with_no_user
    catalog = ["test_repo"]
    @container_gateway_main.expects(:catalog).with(nil).returns(catalog)
    catalog.expects(:limit).returns(catalog)
    catalog.expects(:select_map).returns(catalog)
    header 'DOCKER_DISTRIBUTION_API_VERSION', 'registry/1.0'
    get '/v1/search'
    assert last_response.ok?
    assert_equal [{ "description" => "", "name" => "test_repo" }].sort, JSON.parse(last_response.body)["results"].sort
  end

  def test_catalog_unauthorized_token
    header "AUTHORIZATION", "Basic unauthorized"
    catalog = ["test_repo"]
    @container_gateway_main.expects(:catalog).returns(catalog)
    catalog.expects(:select_map).returns(catalog)
    get '/v2/_catalog'
    assert last_response.ok?
    assert_equal ["test_repo"], JSON.parse(last_response.body)["repositories"]
  end

  def test_catalog_unauthenticated_token
    header "AUTHORIZATION", "Bearer unauthenticated"
    catalog = ["test_repo"]
    @container_gateway_main.expects(:catalog).returns(catalog)
    catalog.expects(:select_map).returns(catalog)
    get '/v2/_catalog'
    assert last_response.ok?
    assert_equal ["test_repo"], JSON.parse(last_response.body)["repositories"]
  end

  def test_token_unauthorized
    ::Proxy::SETTINGS.foreman_url = 'https://foreman'
    foreman_response = {
      "token": "unauthorized"
    }
    stub_request(:get, "#{::Proxy::SETTINGS.foreman_url}/v2/token").
      to_return(:body => foreman_response.to_json)

    get '/v2/token'
    assert_equal 401, last_response.status
    assert_equal last_response.body, 'unauthorized'
  end

  def test_token_unauthenticated
    ::Proxy::SETTINGS.foreman_url = 'https://foreman'
    foreman_response = {
      "token": "unauthenticated"
    }
    stub_request(:get, "#{::Proxy::SETTINGS.foreman_url}/v2/token").
      to_return(:body => foreman_response.to_json)

    get '/v2/token'
    assert last_response.ok?
    assert_equal "unauthenticated", JSON.parse(last_response.body)["token"]
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

  def test_handle_client_cert_auth_authorized
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_client_cert_auth).returns(true)
    ::Cert::RhsmClient.any_instance.stubs(:uuid).returns('valid-uuid')
    redirect_headers = {
      'location' => "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                    "/pulp/container/library/test_repo/manifests/test_tag"
    }
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/v2/library/test_repo/manifests/test_tag").
      to_return(:status => 302, :body => '', :headers => redirect_headers)

    header 'HTTP_SSL_CLIENT_CERT', 'valid-cert'
    get '/v2/library/test_repo/manifests/test_tag'
    assert last_response.redirect?, "Last response was not a redirect: #{last_response.body}"
    assert_equal('', last_response.body)
  end

  def test_handle_client_cert_auth_unauthorized
    ::Proxy::ContainerGateway::Api.any_instance.expects(:handle_client_cert_auth).returns(false)
    ::Cert::RhsmClient.any_instance.stubs(:uuid).returns('invalid-uuid')

    header 'SSL_CLIENT_CERT', 'invalid-cert'
    get '/v2/test_repo/manifests/test_tag'

    assert_equal 404, last_response.status
    assert_includes last_response.body, 'Repository name unknown'
  end

  def test_handle_client_cert_auth_no_cert
    @container_gateway_main.expects(:cert_authorized_for_repo?).never

    get '/v2/test_repo/manifests/test_tag'

    assert_equal 404, last_response.status
    assert_includes last_response.body, 'Repository name unknown'
  end

  def test_flatpak_static_index_success
    static_index_response = {
      "Results" => [
        { "Name" => "org.test.app", "Images" => [] },
        { "Name" => "org.another.app", "Images" => [] }
      ]
    }

    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/index/static").
      to_return(:status => 200, :body => static_index_response.to_json)

    get '/index/static'
    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
    assert_equal static_index_response.to_json, last_response.body
    assert_equal 200, last_response.status
  end

  def test_flatpak_static_index_with_params
    static_index_response = {
      "Results" => [
        { "Name" => "org.test.app", "Images" => [] }
      ]
    }

    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}" \
                       "/pulpcore_registry/index/static?branch=stable&arch=x86_64").
      to_return(:status => 200, :body => static_index_response.to_json)

    get '/index/static?branch=stable&arch=x86_64'
    assert last_response.ok?, "Last response was not ok: #{last_response.body}"
    assert_equal static_index_response.to_json, last_response.body
    assert_equal 200, last_response.status
  end

  def test_flatpak_static_index_error_response
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/index/static").
      to_return(:status => 404, :body => '{"error": "not found"}')

    get '/index/static'
    assert_equal 404, last_response.status
    assert_equal '{"error": "not found"}', last_response.body
  end

  def test_flatpak_static_index_server_error
    stub_request(:get, "#{::Proxy::ContainerGateway::Plugin.settings.pulp_endpoint}/pulpcore_registry/index/static").
      to_return(:status => 500, :body => '{"error": "internal server error"}')

    get '/index/static'
    assert_equal 500, last_response.status
    assert_equal '{"error": "internal server error"}', last_response.body
  end

  def test_update_hosts_filters_nil_uuids
    hosts = [
      { 'uuid' => 'host-uuid-1' },
      { 'uuid' => nil },
      { 'uuid' => 'host-uuid-2' }
    ]

    put '/update_hosts', { 'hosts' => hosts }
    assert last_response.ok?

    # Verify only valid hosts were inserted (old behavior would have failed or inserted nil)
    assert @database.connection[:hosts].count >= 2
    assert_not_nil @database.connection[:hosts].first(uuid: 'host-uuid-1')
    assert_not_nil @database.connection[:hosts].first(uuid: 'host-uuid-2')
  end

  def test_update_hosts_filters_empty_string_uuids
    hosts = [
      { 'uuid' => 'host-uuid-1' },
      { 'uuid' => '' },
      { 'uuid' => 'host-uuid-2' }
    ]

    put '/update_hosts', { 'hosts' => hosts }
    assert last_response.ok?

    # Verify only valid hosts were inserted
    assert @database.connection[:hosts].count >= 2
    assert_not_nil @database.connection[:hosts].first(uuid: 'host-uuid-1')
    assert_not_nil @database.connection[:hosts].first(uuid: 'host-uuid-2')
  end

  def test_update_hosts_handles_missing_uuid_key
    hosts = [
      { 'uuid' => 'host-uuid-1' },
      { 'name' => 'host-without-uuid' },
      { 'uuid' => 'host-uuid-2' }
    ]

    put '/update_hosts', { 'hosts' => hosts }
    assert last_response.ok?

    # Verify only valid hosts were inserted
    assert @database.connection[:hosts].count >= 2
    assert_not_nil @database.connection[:hosts].first(uuid: 'host-uuid-1')
    assert_not_nil @database.connection[:hosts].first(uuid: 'host-uuid-2')
  end

  def test_update_hosts_with_empty_array
    put '/update_hosts', { 'hosts' => [] }
    assert last_response.ok?
  end

  def test_update_hosts_with_all_invalid_uuids
    hosts = [
      { 'uuid' => nil },
      { 'uuid' => '' },
      { 'name' => 'no-uuid' }
    ]

    put '/update_hosts', { 'hosts' => hosts }
    assert last_response.ok?

    # Verify that no hosts were added to the DB
    assert_equal 0, @database.connection[:hosts].count
  end
end
