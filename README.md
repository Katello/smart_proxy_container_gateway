# Smart Proxy - Container Gateway

A Foreman smart proxy plugin for Katello.  Implements container registry functions for Pulp 3-enabled smart proxy mirrors.

# Example Apache /etc/httpd/conf.d/05-foreman-ssl.d/docker_proxy.conf

```
<Location /pulpcore_registry/v2/>
   SSLRequire %{SSL_CLIENT_S_DN_CN} eq "admin"
</Location>

ProxyPass /pulpcore_registry/v2/ http://127.0.0.1:24817/v2/
ProxyPassReverse /pulpcore_registry/v2/ http://127.0.0.1:24817/v2/

ProxyPass /pulp/container http://127.0.0.1:24816/pulp/container
ProxyPassReverse http://127.0.0.1:24816/pulp/container  /pulp/container

ProxyPass /v2 https://127.0.0.1:9090/container_gateway/v2
ProxyPassReverse https://127.0.0.1:9090/container_gateway/v2 /v2
```
