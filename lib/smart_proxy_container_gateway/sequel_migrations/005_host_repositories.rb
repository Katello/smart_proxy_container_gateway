Sequel.migration do
  up do
    # Create the hosts table
    create_table(:hosts) do
      primary_key :id
      String :uuid, null: false, unique: true
    end

    # Create the hosts_repositories join table
    create_table(:hosts_repositories) do
      foreign_key :host_id, :hosts, on_delete: :cascade
      foreign_key :repository_id, :repositories, on_delete: :cascade
      primary_key %i[host_id repository_id]
    end
  end

  down do
    # Drop the hosts_repositories join table
    drop_table(:hosts_repositories)

    # Drop the hosts table
    drop_table(:hosts)
  end
end
