require 'openssl'
require 'webrick'
require 'webrick/https'
require 'socket'
require 'tempfile'

module TLSServer
  ServerInfo = Struct.new(
    :url, :server, :ca_path,
    :client_cert_path, :client_key_path,
    keyword_init: true
  )

  module_function

  # Generate a self-signed CA certificate and key
  def generate_ca
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse('/CN=Typhoid Test CA')
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = cert
    cert.add_extension(ef.create_extension('basicConstraints', 'CA:TRUE', true))
    cert.add_extension(ef.create_extension('keyUsage', 'keyCertSign,cRLSign', true))
    cert.sign(key, OpenSSL::Digest.new('SHA256'))

    [cert, key]
  end

  # Generate a leaf certificate signed by the CA
  def generate_leaf(ca_cert, ca_key, cn: 'localhost', sans: ['localhost', '127.0.0.1'], not_before: nil, not_after: nil)
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = ca_cert.subject
    cert.public_key = key.public_key
    cert.not_before = not_before || Time.now - 3600
    cert.not_after = not_after || Time.now + 3600

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_cert

    san_entries = sans.map do |s|
      s.match?(/\A\d+\.\d+\.\d+\.\d+\z/) ? "IP:#{s}" : "DNS:#{s}"
    end
    cert.add_extension(ef.create_extension('subjectAltName', san_entries.join(',')))
    cert.add_extension(ef.create_extension('keyUsage', 'digitalSignature,keyEncipherment', true))
    cert.add_extension(ef.create_extension('extendedKeyUsage', 'serverAuth'))
    cert.sign(ca_key, OpenSSL::Digest.new('SHA256'))

    [cert, key]
  end

  # Generate a client certificate signed by the CA (for mTLS)
  def generate_client_cert(ca_cert, ca_key, cn: 'test-client')
    key = OpenSSL::PKey::RSA.new(2048)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 3
    cert.subject = OpenSSL::X509::Name.parse("/CN=#{cn}")
    cert.issuer = ca_cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 3600

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = ca_cert
    cert.add_extension(ef.create_extension('keyUsage', 'digitalSignature', true))
    cert.add_extension(ef.create_extension('extendedKeyUsage', 'clientAuth'))
    cert.sign(ca_key, OpenSSL::Digest.new('SHA256'))

    [cert, key]
  end

  # Write a PEM to a Tempfile, return the path
  def write_pem(pem_string, prefix)
    f = Tempfile.new([prefix, '.pem'])
    f.write(pem_string)
    f.flush
    f.path
  end

  # Wait for a TCP port to accept connections
  def wait_for_port(port, host: 'localhost', timeout: 5)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      TCPSocket.new(host, port).close
      return true
    rescue Errno::ECONNREFUSED
      raise "Server on port #{port} didn't start within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end

  # Start a WEBrick HTTPS server on an ephemeral port.
  #
  # Options:
  #   leaf_cn:             CN for the server cert (default: 'localhost')
  #   leaf_sans:           SAN entries (default: ['localhost', '127.0.0.1'])
  #   leaf_not_before:     Override cert validity start
  #   leaf_not_after:      Override cert validity end
  #   ssl_version:         e.g. :TLSv1_2 (default: let OpenSSL decide)
  #   ciphers:             OpenSSL cipher string (default: nil)
  #   require_client_cert: enable mTLS (default: false)
  #   mount_proc:          block receives (req, res) for request handling
  #
  # Returns a ServerInfo struct. Call server_info.server.shutdown when done.
  def start(leaf_cn: 'localhost', leaf_sans: ['localhost', '127.0.0.1'],
            leaf_not_before: nil, leaf_not_after: nil,
            ssl_version: nil, ciphers: nil,
            require_client_cert: false, &mount_proc)

    ca_cert, ca_key = generate_ca
    leaf_cert, leaf_key = generate_leaf(
      ca_cert, ca_key,
      cn: leaf_cn, sans: leaf_sans,
      not_before: leaf_not_before, not_after: leaf_not_after
    )

    ssl_config = {
      SSLEnable: true,
      SSLCertificate: leaf_cert,
      SSLPrivateKey: leaf_key,
      SSLExtraChainCerts: [ca_cert]
    }

    if ssl_version
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.min_version = ssl_version
      ctx.max_version = ssl_version
      ctx.ciphers = ciphers if ciphers
      ssl_config[:SSLContext] = ctx
      # WEBrick needs these even when SSLContext is provided
      ssl_config[:SSLContext].cert = leaf_cert
      ssl_config[:SSLContext].key = leaf_key
      ssl_config[:SSLContext].extra_chain_cert = [ca_cert]
    end

    if require_client_cert
      ca_pem_path = write_pem(ca_cert.to_pem, 'typhoid-server-ca')
      ssl_config[:SSLVerifyClient] = OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT | OpenSSL::SSL::VERIFY_PEER
      ssl_config[:SSLClientCA] = [ca_cert]
      ssl_config[:SSLCACertificateFile] = ca_pem_path
    end

    server = WEBrick::HTTPServer.new(
      Port: 0,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: [],
      **ssl_config
    )

    handler = mount_proc || proc do |_req, res|
      res['Content-Type'] = 'application/json'
      res.body = '{"status":"ok"}'
    end
    server.mount_proc('/', &handler)

    Thread.new { server.start }

    port = server.listeners.first.addr[1]
    wait_for_port(port)

    ca_path = write_pem(ca_cert.to_pem, 'typhoid-ca')

    info = ServerInfo.new(
      url: "https://localhost:#{port}/",
      server: server,
      ca_path: ca_path
    )

    if require_client_cert
      client_cert, client_key = generate_client_cert(ca_cert, ca_key)
      info.client_cert_path = write_pem(client_cert.to_pem, 'typhoid-client-cert')
      info.client_key_path = write_pem(client_key.to_pem, 'typhoid-client-key')
    end

    info
  end
end
