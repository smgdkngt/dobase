# frozen_string_literal: true

require "ipaddr"
require "socket"

# Mail and calendar accounts connect to servers that users type in. Refuse the ones that
# resolve to this machine or to a private network, so an account can't be used to reach
# services that aren't meant to be public, like other containers or cloud metadata.
# Self-hosters with a mail or calendar server on their own network can allow private
# addresses with ALLOW_PRIVATE_NETWORK_HOSTS=true. Local addresses are never allowed.
module RemoteHost
  class Forbidden < StandardError; end
  # The name server didn't answer this time. Asking again later may work.
  class LookupFailed < Forbidden; end

  LOCAL = %w[
    0.0.0.0/8 127.0.0.0/8 169.254.0.0/16 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 fe80::/10 ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  PRIVATE = %w[10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 100.64.0.0/10 fc00::/7].map { |range| IPAddr.new(range) }.freeze

  # Returns the addresses a host name resolves to. Tests swap this for a fake.
  mattr_accessor :resolver, default: ->(host) { Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address) }

  def self.verify!(host)
    # Belt and braces: the demo switches off whatever talks to these servers
    raise Forbidden, "Mail and calendar servers can't be reached from the demo" if Demo.enabled?
    return host if Rails.env.development?

    addresses_for(host).each do |address|
      ip = IPAddr.new(address.split("%").first).native

      if LOCAL.any? { |range| range.include?(ip) }
        raise Forbidden, "#{host} points to #{address}, a local address, which isn't allowed"
      elsif PRIVATE.any? { |range| range.include?(ip) } && !private_networks_allowed?
        raise Forbidden, "#{host} points to #{address}, an address on a private network. " \
                         "To allow servers on your own network, set ALLOW_PRIVATE_NETWORK_HOSTS=true"
      end
    end

    host
  end

  def self.addresses_for(host)
    raise Forbidden, "No server name given" if host.blank?

    address = host.delete_prefix("[").delete_suffix("]")
    return [ address ] if ip_address?(address)

    addresses = Array(resolver.call(host)).uniq
    raise Forbidden, "#{host} could not be found" if addresses.empty?
    addresses
  rescue SocketError => error
    raise LookupFailed, "#{host} could not be looked up: #{error.message}" if temporary?(error)
    raise Forbidden, "#{host} could not be found"
  end

  def self.ip_address?(address)
    IPAddr.new(address)
    true
  rescue IPAddr::InvalidAddressError
    false
  end

  def self.temporary?(error)
    error.respond_to?(:error_code) && error.error_code == Socket::EAI_AGAIN
  end

  def self.private_networks_allowed?
    ENV["ALLOW_PRIVATE_NETWORK_HOSTS"] == "true"
  end
end
