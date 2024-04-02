require 'sequel'
module Proxy
  module ContainerGateway
    class Database
      attr_reader :connection

      def initialize(sqlite_db_path: nil, sqlite_timeout: nil,
                     postgres_host: nil, postgres_port: nil, postgres_user: nil, postgres_name: nil, postgres_password: nil)
        unless sqlite_db_path.nil?
          @connection = Sequel.connect("sqlite://#{sqlite_db_path}", timeout: sqlite_timeout)
          @connection.run("PRAGMA foreign_keys = ON;")
          @connection.run("PRAGMA journal_mode = wal;")
        else
          @connection = Sequel.postgres(host: postgres_host, user: postgres_user,
                                        database: postgres_database, password: postgres_password)
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
    end
  end
end
