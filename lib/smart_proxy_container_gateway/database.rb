require 'sequel'

module Proxy
  module ContainerGateway
    module Database
      class << self
        Sequel.extension :migration, :core_extensions
      end

      def initialize(url:, timeout:)
        @connection = Sequel.connect(url, timeout: timeout)
      end

      private

      def migrate
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
