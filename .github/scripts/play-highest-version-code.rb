#!/usr/bin/env ruby
# Highest versionCode Google Play already holds for the app, within a numeric
# range. Lets play-store-release.yml pick a versionCode Google Play will
# accept even when the GitHub run counter alone would collide (issue #1302):
# a re-run of an old workflow run keeps its frozen run_number, and Play
# rejects an already-used versionCode forever -- the exact duplicate-build
# failure PR #1260 fixed on the iOS side (asc-highest-build.rb, issue #1259,
# where a re-run of run #165 rebuilt build 1165 and altool rejected it).
#
# Env:
#   PLAY_STORE_JSON_KEY - the full Google Play service-account JSON (the same
#     secret the release workflow hands to upload-google-play; that service
#     account already holds Play's release-management grant, so the clamp
#     introduces no new credential).
#   PACKAGE_NAME - application id whose uploads to query (the workflow's own
#     PACKAGE_NAME env, com.wjdavis5.lunarlog).
#   RANGE_LOW / RANGE_HIGH - inclusive numeric bounds of the versionCode
#     range to scan. Production (1xxx) and QA (501xxx, issue #739) are
#     separate namespaces, so a production build never clamps against a QA
#     code or vice versa.
#
# Test seams -- never set by the release workflow; the offline end-to-end
# test (tests/play-highest-version-code.test.sh) points them at a local stub
# server so the real signing/lookup code path runs with no Google network:
#   GOOGLE_OAUTH_TOKEN_URL    - default https://oauth2.googleapis.com/token
#   ANDROIDPUBLISHER_BASE_URL - default https://androidpublisher.googleapis.com
#
# Prints the highest integer versionCode in range (nothing when none exist)
# and exits 0; exits 1 with a message on stderr for any API or key failure so
# the caller can decide warn-vs-fail. Ruby standard library only -- the same
# one-file JWT recipe as asc-highest-build.rb, RS256-signed from the service
# account's own key instead of ES256 from an Apple .p8.

require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

%w[PLAY_STORE_JSON_KEY PACKAGE_NAME RANGE_LOW RANGE_HIGH].each do |name|
  abort("play-highest-version-code.rb: missing #{name}") if ENV[name].to_s.strip.empty?
end

package    = ENV.fetch('PACKAGE_NAME')
range_low  = Integer(ENV.fetch('RANGE_LOW'), 10)
range_high = Integer(ENV.fetch('RANGE_HIGH'), 10)
abort("play-highest-version-code.rb: PACKAGE_NAME is not an application id: #{package}") unless
  package.match?(/\A[A-Za-z0-9._]+\z/)

begin
  service = JSON.parse(ENV.fetch('PLAY_STORE_JSON_KEY'))
rescue JSON::ParserError => e
  abort("play-highest-version-code.rb: PLAY_STORE_JSON_KEY is not valid JSON: #{e.message}")
end

begin
  client_email = service.fetch('client_email')
  private_key  = OpenSSL::PKey::RSA.new(service.fetch('private_key'))
rescue KeyError, OpenSSL::PKey::RSAError => e
  abort("play-highest-version-code.rb: PLAY_STORE_JSON_KEY is not a usable service account (need client_email and private_key): #{e.message}")
end

token_url      = ENV['GOOGLE_OAUTH_TOKEN_URL'].to_s.empty? ? 'https://oauth2.googleapis.com/token' : ENV['GOOGLE_OAUTH_TOKEN_URL']
publisher_base = ENV['ANDROIDPUBLISHER_BASE_URL'].to_s.empty? ? 'https://androidpublisher.googleapis.com' : ENV['ANDROIDPUBLISHER_BASE_URL']

b64 = ->(s) { Base64.urlsafe_encode64(s).delete('=') }
now = Time.now.to_i
header  = b64.call({ alg: 'RS256', typ: 'JWT' }.to_json)
payload = b64.call({ iss: client_email,
                     scope: 'https://www.googleapis.com/auth/androidpublisher',
                     aud: token_url,
                     iat: now, exp: now + 3600 }.to_json)
signed_input = "#{header}.#{payload}"
assertion = "#{signed_input}.#{b64.call(private_key.sign(OpenSSL::Digest::SHA256.new, signed_input))}"

# Exchange the signed assertion for an access token -- Google's standard
# service-account flow (https://developers.google.com/identity/protocols/
# oauth2/service-account#jwt-auth).
token_res = Net::HTTP.post_form(URI(token_url),
                                'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                                'assertion' => assertion)
unless token_res.code.to_i == 200
  abort("play-highest-version-code.rb: token exchange failed: HTTP #{token_res.code} #{token_res.body[0, 200]}")
end
token = JSON.parse(token_res.body).fetch('access_token')

def play_request(method_name, url, token)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', read_timeout: 60) do |http|
    req = Net::HTTP.const_get(method_name).new(uri)
    req['Authorization'] = "Bearer #{token}"
    http.request(req)
  end
end

# Read-only lookup inside a throwaway edit: open one, list every bundle the
# app has uploaded (archived and off-track ones included -- Play keeps them,
# the same "expired builds still reserve their numbers" semantic the ASC
# query relies on), then delete the edit. The bundles list is a single
# response; the endpoint does not paginate.
edit_path = "#{publisher_base}/androidpublisher/v3/applications/#{package}/edits"
edit_res = play_request('Post', edit_path, token)
unless edit_res.code.to_i == 200
  abort("play-highest-version-code.rb: edits insert failed: HTTP #{edit_res.code} #{edit_res.body[0, 200]}")
end
edit_id = JSON.parse(edit_res.body).fetch('id')

bundles_res = play_request('Get', "#{edit_path}/#{edit_id}/bundles", token)
unless bundles_res.code.to_i == 200
  abort("play-highest-version-code.rb: bundles query failed: HTTP #{bundles_res.code} #{bundles_res.body[0, 200]}")
end

# Cleanup is best effort: Google expires edits on its own, so a failed
# delete must never turn a good lookup into a failed one.
begin
  play_request('Delete', "#{edit_path}/#{edit_id}", token)
rescue StandardError
  nil
end

# Google's edits.bundles.list sends one integer versionCode per bundle (the
# Android Publisher v3 Bundle schema carries sha1, sha256, and versionCode --
# there is no versionCodes array, issue #1355; the versionCodes read here
# before kept `highest` nil on every real response, so the clamp never
# fired). The array shape is still honoured so an API shape revert cannot
# silently disarm the clamp again.
highest = nil
bundles = JSON.parse(bundles_res.body)['bundles'] || []
bundles_with_versions = 0
bundles.each do |bundle|
  versions = bundle.key?('versionCode') ? Array(bundle['versionCode']) : Array(bundle['versionCodes'])
  bundles_with_versions += 1 if bundle.key?('versionCode') || bundle.key?('versionCodes')
  versions.each do |version|
    version = Integer(version.to_s, 10) rescue next
    next unless version.between?(range_low, range_high)
    highest = version if highest.nil? || version > highest
  end
end
if !bundles.empty? && bundles_with_versions.zero?
  warn('play-highest-version-code.rb: bundles list carried neither versionCode nor versionCodes in any entry; treating as no uploads -- if Play holds uploads, the bundles response schema has changed')
end

puts highest unless highest.nil?
