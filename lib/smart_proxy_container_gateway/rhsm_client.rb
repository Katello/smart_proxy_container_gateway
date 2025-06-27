require 'openssl'
require 'base64'

module Cert
  class RhsmClient
    attr_accessor :cert

    def initialize(cert)
      self.cert = extract(cert)
    end

    def uuid
      @uuid ||= @cert.subject.to_a.find { |entry| entry[0] == 'CN' }&.[](1)
    end

    private

    def extract(cert)
      raise('Invalid cert provided. Ensure that the provided cert is not empty.') if cert.empty?

      cert = strip_cert(cert)
      cert = Base64.decode64(cert)
      OpenSSL::X509::Certificate.new(cert)
    end

    def strip_cert(cert)
      cert = cert.to_s.gsub("-----BEGIN CERTIFICATE-----", "").gsub("-----END CERTIFICATE-----", "")
      cert.delete!(' ')
      cert.delete!("\n")
      cert
    end
  end
end
