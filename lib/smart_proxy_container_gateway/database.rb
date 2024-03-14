require 'sequel'
module Proxy
  module ContainerGateway
    class Database
      attr_reader :connection

      def initialize(sqlite_db_path:, timeout:)
        @connection = Sequel.connect("sqlite://#{sqlite_db_path}", timeout: timeout)
        @connection.run("PRAGMA foreign_keys = ON;")
        @connection.run("PRAGMA journal_mode = wal;")
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
