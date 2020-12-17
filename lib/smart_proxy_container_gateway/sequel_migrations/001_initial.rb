Sequel.migration do
  up do
    create_table(:unauthenticated_repositories) do
      primary_key :id
      String :name, null: false
    end
  end

  down do
    drop_table(:unauthenticated_repositories)
  end
end
