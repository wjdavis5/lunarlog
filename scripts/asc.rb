#!/usr/bin/env ruby
# Minimal App Store Connect client for release checks in Lunarlog.
#
#   ruby scripts/asc.rb status    # app record, latest builds, version state, submission
#   ruby scripts/asc.rb builds    # every build and its processing state
#   ruby scripts/asc.rb version   # the editable version and what is attached to it
#
# Auth comes from .env at the repo root (ASC_KEY_ID, ASC_ISSUER_ID) plus the
# AuthKey_<KEY_ID>.p8 private key. Both are gitignored. The key is searched for
# in ~/Downloads, ~/.appstoreconnect/private_keys, or the current directory.
#
# Uses only Ruby standard library — no external gems required.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

APP_ID = '6808044149'.freeze

def repo_root
  @repo_root ||= `git rev-parse --show-toplevel`.strip
end

def env
  @env ||= begin
    path = File.join(repo_root, '.env')
    abort("missing #{path} - needs ASC_KEY_ID and ASC_ISSUER_ID") unless File.exist?(path)
    File.read(path).lines.map { |l|
      k, _, v = l.strip.partition('='); [k, v.gsub(/\A["']|["']\z/, '')]
    }.to_h
  end
end

def private_key_path
  candidates = Dir[File.expand_path('~/Downloads/AuthKey_*.p8')] +
               Dir[File.expand_path('~/.appstoreconnect/private_keys/AuthKey_*.p8')] +
               Dir[File.join(repo_root, 'AuthKey_*.p8')]
  candidates.first or abort('no AuthKey_*.p8 found in ~/Downloads or ~/.appstoreconnect/private_keys')
end

def jwt
  @jwt ||= begin
    b64 = ->(s) { Base64.urlsafe_encode64(s).delete('=') }
    header  = b64.call({ alg: 'ES256', kid: env.fetch('ASC_KEY_ID'), typ: 'JWT' }.to_json)
    now     = Time.now.to_i
    payload = b64.call({ iss: env.fetch('ASC_ISSUER_ID'), iat: now, exp: now + 900,
                         aud: 'appstoreconnect-v1' }.to_json)
    ec  = OpenSSL::PKey::EC.new(File.read(private_key_path))
    der = ec.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest("#{header}.#{payload}"))
    r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
    "#{header}.#{payload}.#{b64.call(r + s)}"
  end
end

def get(path)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  req = Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{jwt}")
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
  [res.code.to_i, (res.body.to_s.empty? ? {} : (JSON.parse(res.body) rescue {}))]
end

def builds(limit = 5)
  code, b = get("/v1/builds?filter[app]=#{APP_ID}&limit=#{limit}&sort=-uploadedDate")
  abort("builds query failed: HTTP #{code}") unless code == 200
  b['data'] || []
end

def editable_version
  code, v = get("/v1/apps/#{APP_ID}/appStoreVersions?limit=10")
  abort("versions query failed: HTTP #{code}") unless code == 200
  data = v['data'] || []
  data.find { |x| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED
                     METADATA_REJECTED INVALID_BINARY].include?(x.dig('attributes', 'appStoreState')) } || data.first
end

def print_builds
  puts 'BUILDS'
  list = builds
  puts '  (none uploaded yet)' if list.empty?
  list.each do |x|
    a = x['attributes']
    puts format('  build %-6s %-12s uploaded %s', a['version'], a['processingState'], a['uploadedDate'])
  end
end

def print_version
  v = editable_version
  return puts('VERSION: none') unless v
  a = v['attributes']
  puts 'VERSION'
  puts "  #{a['versionString']}  state=#{a['appStoreState']}  release=#{a['releaseType']}"

  code, full = get("/v1/appStoreVersions/#{v['id']}?include=build")
  attached = full.dig('data', 'relationships', 'build', 'data')
  if attached
    _, bd = get("/v1/builds/#{attached['id']}")
    ba = bd.dig('data', 'attributes') || {}
    puts "  attached build: #{ba['version']} (#{ba['processingState']})"
  else
    puts '  attached build: NONE'
  end

  code, _ = get("/v1/appStoreVersions/#{v['id']}/appStoreVersionSubmission")
  puts "  submitted for review: #{code == 200 ? 'YES' : 'no'}"
end

case ARGV[0]
when 'builds'  then print_builds
when 'version' then print_version
when nil, 'status'
  print_builds
  puts
  print_version
else
  abort("unknown command #{ARGV[0].inspect} (want: status, builds, version)")
end
