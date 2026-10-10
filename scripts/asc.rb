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
  # LLA-116: this used to glob AuthKey_*.p8 and take the *first* match
  # across all three directories -- with more than one Apple Developer team
  # key ever downloaded to ~/Downloads (a stale one from another project, a
  # re-download), whichever sorted first would silently win even when it
  # wasn't the key ASC_KEY_ID actually names, so the JWT would be signed
  # with keyA but claim `kid: keyB` -- an authentication failure. Search for
  # the exact configured key's filename instead of a wildcard.
  key_id = env.fetch('ASC_KEY_ID')
  candidates = [
    File.expand_path("~/Downloads/AuthKey_#{key_id}.p8"),
    File.expand_path("~/.appstoreconnect/private_keys/AuthKey_#{key_id}.p8"),
    File.join(repo_root, "AuthKey_#{key_id}.p8"),
  ]
  candidates.find { |path| File.exist?(path) } or
    abort("no AuthKey_#{key_id}.p8 found in ~/Downloads, ~/.appstoreconnect/private_keys, " \
          "or #{repo_root} (configured ASC_KEY_ID=#{key_id})")
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
  body = res.body.to_s
  return [res.code.to_i, {}] if body.empty?
  # Issue #1834: a body that is not JSON is a failed answer, not an empty
  # one - mapping it to {} let callers read "none attached" or "no builds"
  # out of a broken response.
  [res.code.to_i, JSON.parse(body)]
rescue JSON::ParserError => e
  abort("GET #{path} returned a non-JSON body (HTTP #{res.code.to_i}): #{e.message}")
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
  abort("version detail query failed: HTTP #{code}") unless code == 200
  attached = full.dig('data', 'relationships', 'build', 'data')
  if attached
    code, bd = get("/v1/builds/#{attached['id']}")
    abort("build detail query failed: HTTP #{code}") unless code == 200
    ba = bd.dig('data', 'attributes') || {}
    puts "  attached build: #{ba['version']} (#{ba['processingState']})"
  else
    puts '  attached build: NONE'
  end

  code, _ = get("/v1/appStoreVersions/#{v['id']}/appStoreVersionSubmission")
  # Issue #1834: 404 is the API's own "nothing submitted"; anything else
  # (an expired key's 401, a 5xx) is an unknown answer, never a reassuring
  # "no" from a check that exists to be trusted.
  case code
  when 200 then puts '  submitted for review: YES'
  when 404 then puts '  submitted for review: no'
  else
    puts "  submitted for review: unknown (HTTP #{code})"
  end
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
