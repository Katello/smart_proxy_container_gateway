Sequel.migration do
  up do
    # TODO: Should I be migrating the existing data?

    create_table(:repositories) do
      primary_key :id
      String :name, null: false
      Boolean :auth_required, null: false
    end

    create_table(:users) do
      primary_key :id
      String :name, null: false
    end

    # Migrate unauthenticated_repositories to the new repositories table (TODO: can I select `false` like that?)
    from(:repositories).insert(%i[name auth_required],
                               from(:unauthenticated_repositories).select(:name, false))

    # Migrate names from authentication_tokens to the new users table
    from(:users).insert([:name], from(:authentication_tokens).select(:username))

    alter_table(:authentication_tokens) do
      add_foreign_key :user_id, :users
    end

    # Populate the new user_id foreign key for all authentication_tokens
    from(:authentication_tokens).insert([:user_id],
                                        from(:users).select(:id).where(name: self[:authentication_tokens][:username]))

    alter_table(:authentication_tokens) do
      drop_column :username
    end

    create_join_table(repository_id: :repositories, user_id: :users)
    drop_table :unauthenticated_repositories
  end

  down do
    alter_table(:authentication_tokens) do
      add_column :username, String
    end

    # Repopulate the name column with usernames
    from(:authentication_tokens).update(username:
                                        from(:users).select(:name).where(id: self[:authentication_tokens][:user_id]))

    alter_table(:authentication_tokens) do
      drop_foreign_key :user_id
    end

    create_table(:unauthenticated_repositories) do
      primary_key :id
      String :name, null: false
    end

    # Repopulate the unauthenticated_repositories table
    from(:unauthenticated_repositories).insert([:username],
                                               from(:repositories).select(:name).where(auth_required: true))

    drop_table :users
    drop_table :repositories
    drop_join_table(repository_id: :repositories, user_id: :users)
  end
end
