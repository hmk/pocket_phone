# frozen_string_literal: true

# pocket_phone with a tiny app behind it, to try the whole loop without an app
# of your own:
#
#   bundle exec rake demo        # then open http://localhost:4567/pocket_phone
#
# The "app" is a bot that talks to Sendblue the way a real one does: it
# verifies the webhook signature, marks the thread read, shows typing, and
# answers through the API. The only unusual thing about it is the base URL.

require "bundler/setup"
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "net/http"
require "json"
require "pocket_phone"

PORT = ENV.fetch("PORT", "4567")
SENDBLUE = "http://localhost:#{PORT}/pocket_phone" # instead of https://api.sendblue.com
LINE = "+15550001111"
SECRET = "demo-signing-secret"

class DemoApp < Rails::Application
  config.root = __dir__
  # Routes are drawn inline below, so there is nothing for the reloader to reload them from.
  config.enable_reloading = false
  config.eager_load = false
  config.hosts.clear
  config.secret_key_base = "pocket_phone_demo"
  config.logger = Logger.new($stdout, level: :warn)
  config.consider_all_requests_local = true
end

PocketPhone.configure do |config|
  config.webhook_url = "/webhooks/sendblue"
  config.signing_secret = SECRET
  config.from_number = LINE
  config.people = [
    { name: "Alice Appleseed", number: "+15552220001", service: "iMessage" },
    { name: "Bob Droid", number: "+15552220002", service: "SMS" },
    { name: "Carol Chen", number: "+15552220003", service: "iMessage" }
  ]
end

module Bot
  module_function

  def call(path, body)
    uri = URI("#{SENDBLUE}#{path}")
    Net::HTTP.post(uri, JSON.generate(body), "Content-Type" => "application/json",
      "sb-api-key-id" => "demo", "sb-api-secret-key" => "demo")
  end

  def answer(payload)
    number = payload["from_number"]
    group = payload["group_id"].to_s
    text = payload["content"].to_s
    address = group.empty? ? { number: number } : { group_id: group }
    path = group.empty? ? "/api/send-message" : "/api/send-group-message"

    if group.empty?
      call("/api/mark-read", number: number, from_number: LINE)
      call("/api/send-typing-indicator", number: number, from_number: LINE)
      sleep 1.5
    end

    case text
    when /link/i
      call(path, address.merge(from_number: LINE, content: "Here you go https://www.ruby-lang.org/en/"))
    when /photo|image|picture/i
      call(path, address.merge(from_number: LINE, content: "One photo, as asked.",
        media_url: "https://picsum.photos/seed/pocket-phone/600/400"))
    when /love|thanks|great/i
      call("/api/send-reaction", from_number: LINE, message_handle: payload["message_handle"], reaction: "love")
      call(path, address.merge(from_number: LINE, content: "Any time."))
    else
      call(path, address.merge(from_number: LINE,
        content: %(You said “#{text.empty? ? "(an attachment)" : text}”. Try "link", "photo" or "thanks".)))
    end
  end
end

class WebhooksController < ActionController::API
  def create
    body = request.body.read
    timestamp, digest = request.headers["x-sendblue-signature"].to_s.match(/\At=(\d+),v1=(\h+)\z/)&.captures
    expected = OpenSSL::HMAC.hexdigest("SHA256", SECRET, "#{timestamp}.#{body}")
    return head(:unauthorized) unless digest && ActiveSupport::SecurityUtils.secure_compare(expected, digest)

    payload = JSON.parse(body)
    Thread.new { Bot.answer(payload) } if payload["status"] == "RECEIVED"
    head :ok
  end
end

DemoApp.initialize!
DemoApp.routes.draw do
  mount PocketPhone::Engine, at: "/pocket_phone"
  post "webhooks/sendblue" => "webhooks#create"
  root to: redirect("/pocket_phone")
end

run DemoApp
