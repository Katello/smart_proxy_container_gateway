Sequel.migration do
  up do
    # SQLite does not support dropping columns until version 3.35, which is not in the EL8 ecosystem as of March, 2024.
    create_table(:repositories_users2) do
      foreign_key :repository_id, :repositories, on_delete: :cascade
      foreign_key :user_id, :users, on_delete: :cascade
      primary_key %i[repository_id user_id]
      index %i[repository_id user_id]
    end
    run "INSERT INTO repositories_users2(repository_id, user_id) SELECT repository_id, user_id from repositories_users"

    drop_table(:repositories_users)
    rename_table(:repositories_users2, :repositories_users)
  end

  down do
    create_table(:repositories_users2) do
      foreign_key :repository_id, :repositories
      foreign_key :user_id, :users
      primary_key %i[repository_id user_id]
      index %i[repository_id user_id]
    end
    run "INSERT INTO repositories_users2(repository_id, user_id) SELECT repository_id, user_id from repositories_users"

    drop_table(:repositories_users)
    rename_table(:repositories_users2, :repositories_users)
  end
end
