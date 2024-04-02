require 'test_helper'
require 'webmock/test_unit'
require 'rack/test'
require 'mocha/test_unit'

# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
class ContainerGatewayBackendTest < Test::Unit::TestCase
  include Rack::Test::Methods

  require 'smart_proxy_container_gateway/container_gateway'
  Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                     :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                     :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                     :sqlite_db_path => 'container_gateway_test.db')
  require 'smart_proxy_container_gateway/container_gateway_api'
  require 'smart_proxy_container_gateway/database'

  def app
    Proxy::ContainerGateway::Api.new
  end

  def setup
    Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
                                                       :pulp_client_ssl_cert => "#{__dir__}/fixtures/mock_pulp_client.crt",
                                                       :pulp_client_ssl_key => "#{__dir__}/fixtures/mock_pulp_client.key",
                                                       :sqlite_db_path => 'container_gateway_test.db')
    sqlite_db_path = Proxy::ContainerGateway::Plugin.settings[:sqlite_db_path]
    sqlite_timeout = Proxy::ContainerGateway::Plugin.settings[:sqlite_timeout]
    @database = Proxy::ContainerGateway::Database.new(sqlite_db_path: sqlite_db_path, sqlite_timeout: sqlite_timeout)
    @container_gateway_main = Proxy::ContainerGateway::ContainerGatewayMain.new
    @container_gateway_main.stubs(:database).returns(@database)
  end

  def teardown
    @database.connection[:authentication_tokens].delete
    @database.connection[:repositories_users].delete
    @database.connection[:users].delete
    @database.connection[:repositories].delete
  end

  def test_update_repository_list
    repo = ::Sequel::Model(@database.connection[:repositories]).create(name: 'some_repo', auth_required: false)
    user = ::Sequel::Model(@database.connection[:users]).create(name: 'foreman')
    @database.connection[:repositories_users].insert(%i[repository_id user_id], [repo[:id], user[:id]])

    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                                 { 'repository' => 'test_repo2', 'auth_required' => false }])
    repo_list = @database.connection[:repositories].order(:name).all
    assert_equal 2, repo_list.count
    assert_equal 'test_repo1', repo_list.first[:name]
    assert_equal true, repo_list.first[:auth_required]
    assert_equal true, @database.connection[:repositories_users].empty?
    assert_equal 'test_repo2', repo_list.last[:name]
    assert_equal false, repo_list.last[:auth_required]
  end

  def test_v1_search_with_user
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                               { 'repository' => 'test_repo2', 'auth_required' => false },
                                               { 'repository' => 'test_repo3', 'auth_required' => true }])
    user = ::Sequel::Model(@database.connection[:users]).create(name: 'foreman')
    repo1 = @database.connection[:repositories].where(name: 'test_repo1').first
    repo2 = @database.connection[:repositories].where(name: 'test_repo2').first
    @database.connection[:repositories_users].import(
      %i[repository_id user_id], [[repo1[:id], user[:id]], [repo2[:id], user[:id]]]
    )

    repos_found = @container_gateway_main.v1_search(user: 'foreman')
    assert_equal %w[test_repo1 test_repo2], repos_found
  end

  def test_v1_search_with_no_user
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                               { 'repository' => 'test_repo2', 'auth_required' => false },
                                               { 'repository' => 'test_repo3', 'auth_required' => true }])

    repos_found = @container_gateway_main.v1_search
    assert_equal %w[test_repo2], repos_found
  end

  def test_v1_item_limit
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                               { 'repository' => 'test_repo2', 'auth_required' => false },
                                               { 'repository' => 'test_repo3', 'auth_required' => false }])

    repos_found = @container_gateway_main.v1_search(n: '1')
    assert_equal %w[test_repo1], repos_found
  end

  def test_catalog_user
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                               { 'repository' => 'test_repo2', 'auth_required' => true },
                                               { 'repository' => 'test_repo3', 'auth_required' => true }])
    user = ::Sequel::Model(@database.connection[:users]).create(name: 'foreman')
    repo = @database.connection[:repositories].first(name: 'test_repo2')
    @database.connection[:repositories_users].insert(%i[repository_id user_id], [repo[:id], user[:id]])

    assert_equal ['test_repo1', 'test_repo2'], @container_gateway_main.catalog(user).
      select_map(::Sequel[:repositories][:name])
  end

  def test_catalog_no_user
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                               { 'repository' => 'test_repo2', 'auth_required' => true },
                                               { 'repository' => 'test_repo3', 'auth_required' => false }])
    assert_equal ['test_repo1', 'test_repo3'],
                 @container_gateway_main.catalog.select_map(::Sequel[:repositories][:name])
  end

  def test_authorized_for_repo_auth
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                               { 'repository' => 'test_repo2', 'auth_required' => true },
                                               { 'repository' => 'test_repo3', 'auth_required' => false }])
    user = ::Sequel::Model(@database.connection[:users]).create(name: 'foreman')
    repo = @database.connection[:repositories].first(name: 'test_repo2')
    @database.connection[:repositories_users].insert(%i[repository_id user_id], [repo[:id], user[:id]])

    assert_false @container_gateway_main.authorized_for_repo?('test_repo2', false, 'foreman')
    assert_true @container_gateway_main.authorized_for_repo?('test_repo1', true, 'foreman')
    assert_true @container_gateway_main.authorized_for_repo?('test_repo2', true, 'foreman')
    assert_true @container_gateway_main.authorized_for_repo?('test_repo3', true, 'foreman')
  end

  def test_authorized_for_repo_no_auth
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                               { 'repository' => 'test_repo2', 'auth_required' => true },
                                               { 'repository' => 'test_repo3', 'auth_required' => false }])

    assert_true @container_gateway_main.authorized_for_repo?('test_repo1', false)
    assert_false @container_gateway_main.authorized_for_repo?('test_repo2', false)
    assert_true @container_gateway_main.authorized_for_repo?('test_repo3', false)
  end

  def test_authorized_for_nonexistent_repo
    assert_false @container_gateway_main.authorized_for_repo?('test', false)
  end

  def test_insert_token
    @container_gateway_main.insert_token('joe', 'mytoken', Time.now + 60)
    assert @container_gateway_main.valid_token?('mytoken')
  end

  def test_bad_valid_token
    refute @container_gateway_main.valid_token?('notmytoken')
  end

  def test_expired_tokens_deleted
    @database.connection[:authentication_tokens].delete
    @container_gateway_main.insert_token('joe', 'myexpiredtoken',
                                           DateTime.now - (1 / 24.0), clear_expired_tokens: false)

    refute @container_gateway_main.valid_token?('mytoken')
  end

  def test_update_user_repo_mapping
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                               { 'repository' => 'test_repo2', 'auth_required' => true },
                                               { 'repository' => 'test_repo3', 'auth_required' => true }])
    foreman_user = ::Sequel::Model(@database.connection[:users]).create(name: 'foreman')
    katello_user = ::Sequel::Model(@database.connection[:users]).create(name: 'katello')
    user_repo_maps = { 'users' => [{ 'foreman' => [{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                   { 'repository' => 'test_repo2', 'auth_required' => true }] },
                                   { 'katello' => [{ 'repository' => 'test_repo2', 'auth_required' => true },
                                                   { 'repository' => 'test_repo3', 'auth_required' => true }] }] }
    @container_gateway_main.update_user_repo_mapping(user_repo_maps)

    repo1_id = @database.connection[:repositories].first(name: 'test_repo1')[:id]
    repo2_id = @database.connection[:repositories].first(name: 'test_repo2')[:id]
    repo3_id = @database.connection[:repositories].first(name: 'test_repo3')[:id]

    refute @database.connection[:repositories_users].where(user_id: foreman_user[:id], repository_id: repo1_id).empty?
    refute @database.connection[:repositories_users].where(user_id: foreman_user[:id], repository_id: repo2_id).empty?
    refute @database.connection[:repositories_users].where(user_id: katello_user[:id], repository_id: repo2_id).empty?
    refute @database.connection[:repositories_users].where(user_id: katello_user[:id], repository_id: repo3_id).empty?
  end

  def test_update_user_repositories
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                               { 'repository' => 'test_repo2', 'auth_required' => true },
                                               { 'repository' => 'test_repo3', 'auth_required' => true }])
    user = ::Sequel::Model(@database.connection[:users]).create(name: 'foreman')
    @container_gateway_main.update_user_repositories('foreman', ['test_repo1', 'test_repo2', 'test_repo3'])

    assert_equal @database.connection[:repositories].select_map(:id).sort,
                 @database.connection[:repositories_users].where(user_id: user[:id]).select_map(:repository_id).sort
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
