require 'sequel'
module Proxy
  module ContainerGateway
    class Database
      attr_reader :connection

      def initialize(connection_string, db_max_connections, db_pool_timeout, prior_sqlite_db_path = nil)
        Sequel.default_timezone = :local
        @connection = Sequel.connect(connection_string, max_connections: db_max_connections, pool_timeout: db_pool_timeout)
        if connection_string.start_with?('sqlite://')
          @connection.run("PRAGMA foreign_keys = ON;")
          @connection.run("PRAGMA journal_mode = wal;")
        elsif prior_sqlite_db_path && File.exist?(prior_sqlite_db_path) &&
              (!@connection.table_exists?(:repositories) || @connection[:repositories].count.zero?)
          migrate_to_postgres(Sequel.sqlite(prior_sqlite_db_path), @connection)
          File.delete(prior_sqlite_db_path)
        end
        migrate
      end

      private

      def migrate
        Sequel.extension :migration, :core_extensions
        migration_path = File.join(__dir__, 'sequel_migrations')
        begin
          Sequel::Migrator.check_current(@connection, migration_path)
        rescue Sequel::Migrator::NotCurrentError
          Sequel::Migrator.run(@connection, migration_path)
        end
      end

      def migrate_to_postgres(sqlite_db, postgres_db)
        migrate
        sqlite_db.transaction do
          sqlite_db.tables.each do |table|
            next if table == :schema_info

            sqlite_db[table].each do |row|
              postgres_db[table.to_sym].insert(row)
            end
          end
        end
      end
    end
  end
end
