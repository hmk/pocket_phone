# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

module PocketPhone
  # One webhook delivery to the app, signed the way Sendblue signs them.
  #
  # Sendblue sends two things when a signing secret is set: the secret itself
  # in a header (`sb-signing-secret` unless you renamed it), and
  # `x-sendblue-signature: t=<unix>,v1=<hex>`, an HMAC-SHA256 of
  # "<t>.<raw body>" keyed by the secret. Both are sent here so that either
  # check can be exercised.
  module Webhook
    module_function

    # Returns a record of what happened, for the message's details:
    # { "type", "url", "status" or "error", "at" }.
    def deliver(type:, url:, payload:)
      settings = Runner.with_app do
        config = PocketPhone.config
        { secret: config.signing_secret.to_s, header: config.secret_header.to_s,
          timeout: config.webhook_timeout }
      end
      uri = absolute(url)
      body = JSON.generate(payload)
      response = post(uri, body, headers(body, settings), settings[:timeout])
      record(type, uri, "status" => response.code.to_i)
    rescue StandardError => e
      record(type, url, "error" => "#{e.class.name}: #{e.message}")
    end

    def signature(secret, body, timestamp = Time.now.to_i)
      "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")}"
    end

    def headers(body, settings)
      headers = { "Content-Type" => "application/json", "Accept" => "application/json",
                  "User-Agent" => "pocket_phone/#{VERSION}" }
      return headers if settings[:secret].empty?

      headers["x-sendblue-signature"] = signature(settings[:secret], body)
      headers[settings[:header]] = settings[:secret] unless settings[:header].empty?
      headers
    end

    def absolute(url)
      uri = URI.parse(url.to_s)
      return uri if uri.is_a?(URI::HTTP)
      raise ArgumentError, "webhook URL #{url.inspect} is a path and no request has been served yet" if PocketPhone.base_url.to_s.empty?

      URI.join(PocketPhone.base_url, url.to_s)
    end

    def post(uri, body, headers, timeout)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 5, read_timeout: timeout) do |http|
        http.post(uri.request_uri, body, headers)
      end
    end

    def record(type, url, outcome)
      { "type" => type, "url" => url.to_s, "at" => PocketPhone.now }.merge(outcome)
    end
  end
end
