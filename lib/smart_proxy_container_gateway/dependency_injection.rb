module Proxy
  module ContainerGateway
    module DependencyInjection
      include Proxy::DependencyInjection::Accessors
      def container_instance
        @container_instance ||= ::Proxy::Plugins.instance.find { |p| p[:name] == :container_gateway }[:di_container]
      end
    end
  end
end
