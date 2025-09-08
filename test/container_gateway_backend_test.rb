require 'test_helper'
require 'mocha/test_unit'

# rubocop:disable Metrics/AbcSize
class ContainerGatewayBackendTest < Test::Unit::TestCase
  require 'smart_proxy_container_gateway/container_gateway'
  require 'smart_proxy_container_gateway/container_gateway_api'
  require 'smart_proxy_container_gateway/database'

  def setup
    @database = Proxy::ContainerGateway::Database.new('sqlite://')
    @container_gateway_main = Proxy::ContainerGateway::ContainerGatewayMain.new(
      database: @database, pulp_endpoint: 'https://test.example.com',
      pulp_client_ssl_ca: "#{__dir__}/fixtures/mock_pulp_ca.pem",
      pulp_client_ssl_cert: "#{__dir__}/fixtures/mock_pulp_client.crt",
      pulp_client_ssl_key: "#{__dir__}/fixtures/mock_pulp_client.key"
    )
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

  def updates_host_repositories_correctly
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                    { 'repository' => 'test_repo2', 'auth_required' => true }])
    @database.connection[:hosts].insert(uuid: 'host-uuid-1')

    @container_gateway_main.update_host_repositories('host-uuid-1', ['test_repo1'])

    host = @database.connection[:hosts].first(uuid: 'host-uuid-1')
    repo = @database.connection[:repositories].first(name: 'test_repo1')
    assert_equal [[repo[:id], host[:id]]], @database.connection[:hosts_repositories].select_map(%i[repository_id host_id])
  end

  def clears_existing_host_repositories_before_update
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                    { 'repository' => 'test_repo2', 'auth_required' => true }])
    host = @database.connection[:hosts].insert(uuid: 'host-uuid-1')
    repo = @database.connection[:repositories].first(name: 'test_repo1')
    @database.connection[:hosts_repositories].insert(repository_id: repo[:id], host_id: host[:id])

    @container_gateway_main.update_host_repositories('host-uuid-1', ['test_repo2'])

    updated_repo = @database.connection[:repositories].first(name: 'test_repo2')
    assert_equal [[updated_repo[:id], host[:id]]],
                 @database.connection[:hosts_repositories].select_map(%i[repository_id host_id])
  end

  def updates_host_repo_mapping_correctly
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                    { 'repository' => 'test_repo2', 'auth_required' => true }])
    @database.connection[:hosts].insert(uuid: 'host-uuid-1')
    @database.connection[:hosts].insert(uuid: 'host-uuid-2')

    host_repo_maps = {
      'hosts' => [
        { 'host-uuid-1' => [{ 'repository' => 'test_repo1', 'auth_required' => true }] },
        { 'host-uuid-2' => [{ 'repository' => 'test_repo2', 'auth_required' => true }] }
      ]
    }

    @container_gateway_main.update_host_repo_mapping(host_repo_maps)

    host1 = @database.connection[:hosts].first(uuid: 'host-uuid-1')
    host2 = @database.connection[:hosts].first(uuid: 'host-uuid-2')
    repo1 = @database.connection[:repositories].first(name: 'test_repo1')
    repo2 = @database.connection[:repositories].first(name: 'test_repo2')

    assert_equal [[repo1[:id], host1[:id]], [repo2[:id], host2[:id]]],
                 @database.connection[:hosts_repositories].select_map(%i[repository_id host_id])
  end

  def clears_existing_host_repo_mapping_before_update
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true },
                                                    { 'repository' => 'test_repo2', 'auth_required' => true }])
    host = @database.connection[:hosts].insert(uuid: 'host-uuid-1')
    repo = @database.connection[:repositories].first(name: 'test_repo1')
    @database.connection[:hosts_repositories].insert(repository_id: repo[:id], host_id: host[:id])

    host_repo_maps = {
      'hosts' => [
        { 'host-uuid-1' => [{ 'repository' => 'test_repo2', 'auth_required' => true }] }
      ]
    }

    @container_gateway_main.update_host_repo_mapping(host_repo_maps)

    updated_repo = @database.connection[:repositories].first(name: 'test_repo2')
    assert_equal [[updated_repo[:id], host[:id]]],
                 @database.connection[:hosts_repositories].select_map(%i[repository_id host_id])
  end

  def test_build_host_repository_mapping_with_nil_hosts
    host_repo_maps = { 'hosts' => nil }
    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)
    assert_empty result
  end

  def test_build_host_repository_mapping_with_empty_hosts
    host_repo_maps = { 'hosts' => [] }
    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)
    assert_empty result
  end

  def test_build_host_repository_mapping_with_nonexistent_host
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true }])

    host_repo_maps = {
      'hosts' => [
        { 'nonexistent-uuid' => [{ 'repository' => 'test_repo1', 'auth_required' => true }] }
      ]
    }

    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)
    assert_empty result
  end

  def test_build_host_repository_mapping_with_nil_repos
    @database.connection[:hosts].insert(uuid: 'host-uuid-1')

    host_repo_maps = {
      'hosts' => [
        { 'host-uuid-1' => nil }
      ]
    }

    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)
    assert_empty result
  end

  def test_build_host_repository_mapping_with_empty_repos
    @database.connection[:hosts].insert(uuid: 'host-uuid-1')

    host_repo_maps = {
      'hosts' => [
        { 'host-uuid-1' => [] }
      ]
    }

    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)
    assert_empty result
  end

  def test_build_host_repository_mapping_filters_non_auth_required_repos
    repo_list = [{ 'repository' => 'public_repo', 'auth_required' => false },
                 { 'repository' => 'private_repo', 'auth_required' => true }]
    @container_gateway_main.update_repository_list(repo_list)
    @database.connection[:hosts].insert(uuid: 'host-uuid-1')

    host_repo_maps = {
      'hosts' => [
        { 'host-uuid-1' => [
          { 'repository' => 'public_repo', 'auth_required' => false },
          { 'repository' => 'private_repo', 'auth_required' => true }
        ] }
      ]
    }

    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)

    host = @database.connection[:hosts].first(uuid: 'host-uuid-1')
    private_repo = @database.connection[:repositories].first(name: 'private_repo')

    assert_equal [[private_repo[:id], host[:id]]], result
  end

  def test_build_host_repository_mapping_handles_mixed_scenarios
    @container_gateway_main.update_repository_list([{ 'repository' => 'test_repo1', 'auth_required' => true }])
    @database.connection[:hosts].insert(uuid: 'valid-host')

    host_repo_maps = {
      'hosts' => [
        { 'valid-host' => [{ 'repository' => 'test_repo1', 'auth_required' => true }] },
        { 'invalid-host' => [{ 'repository' => 'test_repo1', 'auth_required' => true }] },
        { 'empty-repos-host' => [] }
      ]
    }

    result = @container_gateway_main.build_host_repository_mapping(host_repo_maps)

    host = @database.connection[:hosts].first(uuid: 'valid-host')
    repo = @database.connection[:repositories].first(name: 'test_repo1')

    assert_equal [[repo[:id], host[:id]]], result
  end
end
# rubocop:enable Metrics/AbcSize
