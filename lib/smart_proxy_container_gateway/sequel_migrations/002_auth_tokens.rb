Sequel.migration do
  up do
    create_table(:authentication_tokens) do
      primary_key :id
      String :username, null: false
      String :token_checksum, null: false
      DateTime :expire_at, null: false
    end
  end

  down do
    drop_table(:authentication_tokens)
  end
end
