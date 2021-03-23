require 'test_helper'
require 'webmock/test_unit'
require 'rack/test'
require 'mocha/test_unit'

# rubocop:disable Metrics/AbcSize
class ContainerGatewayBackendTest < Test::Unit::TestCase
  include Rack::Test::Methods

  require 'smart_proxy_container_gateway/container_gateway'
  Proxy::ContainerGateway::Plugin.load_test_settings(:pulp_endpoint => 'https://test.example.com',
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

  def test_update_repository_list
    repo = ::Proxy::ContainerGateway::Repository.create(name: 'some_repo', auth_required: false)
    user = ::Proxy::ContainerGateway::User.create(name: 'foreman')
    repo.add_user(user)

    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                      { 'repository' => 'test_repo2', 'auth_required' => false }])
    repo_list = ::Proxy::ContainerGateway::Repository.order(:name).all
    assert_equal 2, repo_list.count
    assert_equal 'test_repo1', repo_list.first.name
    assert_equal true, repo_list.first.auth_required
    assert_empty repo_list.first.users
    assert_equal 'test_repo2', repo_list.last.name
    assert_equal false, repo_list.last.auth_required
    assert_empty repo_list.last.users
  end

  def test_v1_search_with_user
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                      { 'repository' => 'test_repo2', 'auth_required' => false },
                                                      { 'repository' => 'test_repo3', 'auth_required' => true }])
    user = ::Proxy::ContainerGateway::User.create(name: 'foreman')
    user.add_repository(::Proxy::ContainerGateway::Repository.find(name: 'test_repo1'))

    repos_found = ::Proxy::ContainerGateway.v1_search(user: 'foreman')
    assert_equal [{ :name => 'test_repo1' }, { :name => 'test_repo2' }], repos_found
  end

  def test_v1_search_with_no_user
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                      { 'repository' => 'test_repo2', 'auth_required' => false },
                                                      { 'repository' => 'test_repo3', 'auth_required' => true }])

    repos_found = ::Proxy::ContainerGateway.v1_search
    assert_equal [{ :name => 'test_repo2' }], repos_found
  end

  def test_v1_item_limit
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                                      { 'repository' => 'test_repo2', 'auth_required' => false },
                                                      { 'repository' => 'test_repo3', 'auth_required' => false }])

    repos_found = ::Proxy::ContainerGateway.v1_search(n: '1')
    assert_equal [{ :name => 'test_repo1' }], repos_found
  end

  def test_catalog_user
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                                      { 'repository' => 'test_repo2', 'auth_required' => true },
                                                      { 'repository' => 'test_repo3', 'auth_required' => true }])
    user = ::Proxy::ContainerGateway::User.create(name: 'foreman')
    user.add_repository(::Proxy::ContainerGateway::Repository.find(name: 'test_repo2'))

    assert_equal ['test_repo1', 'test_repo2'], ::Proxy::ContainerGateway.catalog(user)
  end

  def test_catalog_no_user
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                                      { 'repository' => 'test_repo2', 'auth_required' => true },
                                                      { 'repository' => 'test_repo3', 'auth_required' => false }])
    assert_equal ['test_repo1', 'test_repo3'], ::Proxy::ContainerGateway.catalog
  end

  def test_authorized_for_repo_auth
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                                      { 'repository' => 'test_repo2', 'auth_required' => true },
                                                      { 'repository' => 'test_repo3', 'auth_required' => false }])
    user = ::Proxy::ContainerGateway::User.create(name: 'foreman')
    user.add_repository(::Proxy::ContainerGateway::Repository.find(name: 'test_repo2'))

    assert_false ::Proxy::ContainerGateway.authorized_for_repo?('test_repo2', false, 'foreman')
    assert_true ::Proxy::ContainerGateway.authorized_for_repo?('test_repo1', true, 'foreman')
    assert_true ::Proxy::ContainerGateway.authorized_for_repo?('test_repo2', true, 'foreman')
    assert_true ::Proxy::ContainerGateway.authorized_for_repo?('test_repo3', true, 'foreman')
  end

  def test_authorized_for_repo_no_auth
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => false },
                                                      { 'repository' => 'test_repo2', 'auth_required' => true },
                                                      { 'repository' => 'test_repo3', 'auth_required' => false }])

    assert_true ::Proxy::ContainerGateway.authorized_for_repo?('test_repo1', false)
    assert_false ::Proxy::ContainerGateway.authorized_for_repo?('test_repo2', false)
    assert_true ::Proxy::ContainerGateway.authorized_for_repo?('test_repo3', false)
  end

  def test_authorized_for_nonexistent_repo
    assert_false ::Proxy::ContainerGateway.authorized_for_repo?('test', false)
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

  def test_update_user_repo_mapping
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                      { 'repository' => 'test_repo2', 'auth_required' => true },
                                                      { 'repository' => 'test_repo3', 'auth_required' => true }])
    ::Proxy::ContainerGateway::User.create(name: 'foreman')
    ::Proxy::ContainerGateway::User.create(name: 'katello')
    user_repo_maps = { 'users' => [{ 'foreman' => [{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                   { 'repository' => 'test_repo2', 'auth_required' => true }] },
                                   { 'katello' => [{ 'repository' => 'test_repo2', 'auth_required' => true },
                                                   { 'repository' => 'test_repo3', 'auth_required' => true }] }] }
    ::Proxy::ContainerGateway.update_user_repo_mapping(user_repo_maps)
    assert_equal ::Proxy::ContainerGateway::Repository.where(name: ['test_repo1', 'test_repo2']).all,
                 ::Proxy::ContainerGateway::User.find(name: 'foreman').repositories
    assert_equal ::Proxy::ContainerGateway::Repository.where(name: ['test_repo2', 'test_repo3']).all,
                 ::Proxy::ContainerGateway::User.find(name: 'katello').repositories
  end

  def test_update_user_repositories
    ::Proxy::ContainerGateway.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                      { 'repository' => 'test_repo2', 'auth_required' => true },
                                                      { 'repository' => 'test_repo3', 'auth_required' => true }])
    user = ::Proxy::ContainerGateway::User.create(name: 'foreman')
    ::Proxy::ContainerGateway.update_user_repositories('foreman', ['test_repo1', 'test_repo2', 'test_repo3'])

    assert_equal ::Proxy::ContainerGateway::Repository.all, user.repositories
  end
end
# rubocop:enable Metrics/AbcSize
