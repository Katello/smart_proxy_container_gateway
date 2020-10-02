require 'smart_proxy_container_gateway/container_gateway_api'

map '/container_gateway' do
  run Proxy::ContainerGateway::Api
end
