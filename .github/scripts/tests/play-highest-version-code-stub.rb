#!/usr/bin/env ruby
# Offline stub of the Google endpoints play-highest-version-code.rb talks to,
# for play-highest-version-code.test.sh. Pure stdlib, single-threaded, loopback
# only. Serves until killed; writes the ephemeral port it picked to
# ARGV[2] once it is accepting.
#
# Usage:
#   ruby play-highest-version-code-stub.rb <bundles-json-file> <record-dir> <port-file>
#
# Every request is recorded verbatim (method, path, headers, body) as a file
# under <record-dir> so the bash harness can assert on what the script
# actually sent -- including the RS256 JWT assertion, which the harness
# verifies against a throwaway public key. Well-known paths:
#   POST /token                                        -> access token
#   POST /androidpublisher/v3/applications/<pkg>/edits -> edit id
#   GET  .../edits/<id>/bundles                        -> <bundles-json-file>
#   DELETE .../edits/<id>                              -> 204
# plus two canned failure packages the harness uses to exercise the script's
# abort paths:
#   boom.example        -> edits insert answers HTTP 403
#   bundleboom.example  -> bundles query answers HTTP 500

require 'json'
require 'socket'

bundles_json = File.read(ARGV.fetch(0))
record_dir   = ARGV.fetch(1)
port_file    = ARGV.fetch(2)

def respond(sock, status, reason, body)
  body ||= ''
  sock.write("HTTP/1.1 #{status} #{reason}\r\n" \
             "Content-Type: application/json\r\n" \
             "Content-Length: #{body.bytesize}\r\n" \
             "Connection: close\r\n\r\n#{body}")
end

def read_request(sock)
  request_line = sock.gets
  return nil if request_line.nil? || request_line.strip.empty?
  headers = {}
  while (line = sock.gets) && line != "\r\n" && line != "\n"
    key, value = line.split(':', 2)
    headers[key.strip.downcase] = value.strip if key && value
  end
  body_len = headers['content-length'].to_i
  body = body_len.positive? ? sock.read(body_len) : ''
  [request_line.strip, headers, body]
end

server = TCPServer.new('127.0.0.1', 0)
File.write(port_file, server.addr[1].to_s)

served = 0
loop do
  sock = server.accept
  begin
    request = read_request(sock)
    next if request.nil?
    method, path, = request[0].split
    record = File.join(record_dir, format('%02d-%s.txt', served, method))
    File.write(record, "METHOD #{method}\nPATH #{path}\n" \
                       "HEADERS #{JSON.generate(request[1])}\nBODY #{request[2]}\n")
    served += 1

    if method == 'POST' && path == '/token'
      respond(sock, 200, 'OK', JSON.generate(access_token: 'stub-access-token',
                                             expires_in: 3600, token_type: 'Bearer'))
    elsif method == 'POST' && path.start_with?('/androidpublisher/v3/applications/boom.example/edits')
      respond(sock, 403, 'Forbidden',
              JSON.generate(error: { code: 403, message: 'stub: permission denied' }))
    elsif method == 'POST' && path.end_with?('/edits')
      respond(sock, 200, 'OK', JSON.generate(id: 'stub-edit-id'))
    elsif method == 'GET' && path.end_with?('/bundles')
      if path.include?('/bundleboom.example/')
        respond(sock, 500, 'Internal Server Error',
                JSON.generate(error: { code: 500, message: 'stub: bundles blew up' }))
      else
        respond(sock, 200, 'OK', bundles_json)
      end
    elsif method == 'DELETE' && path.include?('/edits/')
      respond(sock, 204, 'No Content', '')
    else
      respond(sock, 404, 'Not Found', JSON.generate(error: "stub: unexpected #{method} #{path}"))
    end
  rescue StandardError
    nil # keep serving; the harness asserts on recorded requests, not stub health
  ensure
    begin
      sock.close
    rescue StandardError
      nil
    end
  end
end
