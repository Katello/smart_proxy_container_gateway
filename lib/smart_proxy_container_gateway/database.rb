require 'sequel'
module Proxy
  module ContainerGateway
    class Database
      attr_reader :connection

      def initialize(options = {})
        if options[:database_backend] == 'sqlite'
          @connection = Sequel.connect("sqlite://#{options[:sqlite_db_path]}", timeout: options[:sqlite_timeout])
          @connection.run("PRAGMA foreign_keys = ON;")
          @connection.run("PRAGMA journal_mode = wal;")
        else
          unless options[:postgresql_connection_string]
            fail ArgumentError, 'PostgreSQL connection string is required'
          end
          @connection = Sequel.connect(options[:postgresql_connection_string])
          if File.exist?(options[:sqlite_db_path]) && @connection[:repositories].count.zero?
            migrate_to_postgres(Sequel.sqlite(options[:sqlite_db_path]), @connection)
            File.delete(options[:sqlite_db_path])
          end
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
        sqlite_db.transaction do
          sqlite_db.tables.each do |table|
            skip if table == :schema_info
            sqlite_db[table].each do |row|
              postgres_db[table.to_sym].insert(row)
            end
          end
        end
      end
    end
  end
end
