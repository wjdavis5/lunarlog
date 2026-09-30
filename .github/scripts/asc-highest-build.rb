#!/usr/bin/env ruby
# Highest already-uploaded TestFlight build number for the app, within a
# numeric range. Lets ios-release.yml pick a cfBundleVersion App Store Connect
# will accept even when the GitHub run counter alone would collide (issue
# #1259): a re-run of an old workflow run keeps its frozen run_number, and
# expired builds still reserve their numbers -- attempt 2 of run #165 rebuilt
# build 1165 and altool rejected it with
# ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE.
#
# Env:
#   ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY - App Store Connect API key
#     (the same secrets the release workflow installs for altool).
#   ASC_APP_ID   - numeric App Store Connect app id (required).
#   RANGE_LOW / RANGE_HIGH - inclusive numeric bounds of the build-number
#     range to scan. Production (1xxx) and QA (501xxx, issue #739) are
#     separate namespaces, so a production build never clamps against a QA
#     number or vice versa.
#
# Prints the highest integer build version in range (nothing when none exist)
# and exits 0; exits 1 with a message on stderr for any API or key failure so
# the caller can decide warn-vs-fail. Ruby standard library only -- same JWT
# recipe as scripts/asc.rb.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

%w[ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY ASC_APP_ID RANGE_LOW RANGE_HIGH].each do |name|
  abort("asc-highest-build.rb: missing #{name}") if ENV[name].to_s.strip.empty?
end

key_id    = ENV.fetch('ASC_KEY_ID')
issuer_id = ENV.fetch('ASC_ISSUER_ID')
app_id    = ENV.fetch('ASC_APP_ID')
range_low = Integer(ENV.fetch('RANGE_LOW'), 10)
range_high = Integer(ENV.fetch('RANGE_HIGH'), 10)

b64 = ->(s) { Base64.urlsafe_encode64(s).delete('=') }
now = Time.now.to_i
header  = b64.call({ alg: 'ES256', kid: key_id, typ: 'JWT' }.to_json)
payload = b64.call({ iss: issuer_id, iat: now, exp: now + 900,
                     aud: 'appstoreconnect-v1' }.to_json)
ec = OpenSSL::PKey::EC.new(ENV.fetch('ASC_PRIVATE_KEY'))
der = ec.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest("#{header}.#{payload}"))
r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
token = "#{header}.#{payload}.#{b64.call(r + s)}"

# Walk newest-first pages until past the range's plausible entries. Build
# numbers only ever grow within a range, so the in-range maximum is always
# among the newest uploads; five pages (1000 builds) is far past any plausible
# window and bounds the run against an app with a long history.
highest = nil
path = "/v1/builds?filter[app]=#{app_id}&limit=200&sort=-uploadedDate"
(1..5).each do
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) do |http|
    http.request(Net::HTTP::Get.new(uri, 'Authorization' => "Bearer #{token}"))
  end
  abort("asc-highest-build.rb: builds query failed: HTTP #{res.code}") unless res.code.to_i == 200
  body = JSON.parse(res.body)
  (body['data'] || []).each do |build|
    version = Integer(build.dig('attributes', 'version').to_s, 10) rescue next
    next unless version.between?(range_low, range_high)
    highest = version if highest.nil? || version > highest
  end
  nxt = body.dig('links', 'next')
  break if nxt.nil? || nxt.empty?
  path = URI(nxt).request_uri
end

puts highest unless highest.nil?
