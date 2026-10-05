# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"

require "tmpdir"
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "minitest/autorun"
require "webmock/minitest"
require "pocket_phone"

# The smallest Rails app that can mount the engine.
class DummyApp < Rails::Application
  config.root = Dir.mktmpdir("pocket_phone_dummy")
  config.eager_load = false
  config.hosts.clear
  config.secret_key_base = "pocket_phone_test"
  config.logger = Logger.new(nil)
  config.action_controller.allow_forgery_protection = false
  config.action_dispatch.show_exceptions = :none
end
DummyApp.initialize!
DummyApp.routes.draw { mount PocketPhone::Engine, at: "/pocket_phone" }

module PocketPhone
  class TestCase < ActionDispatch::IntegrationTest
    LINE = "+15550001111"
    ALICE = "+15552223333"
    WEBHOOK = "http://app.test/webhooks/sendblue/token"
    KEYS = { "sb-api-key-id" => "key", "sb-api-secret-key" => "secret" }.freeze

    setup do
      PocketPhone.reset_config!
      PocketPhone.configure do |config|
        config.storage_path = Dir.mktmpdir("pocket_phone_store")
        config.async = false
        config.link_previews = false
      end
      WebMock.disable_net_connect!
    end

    def db = PocketPhone.store.read

    def api(path, body = {}, headers: KEYS)
      post "/pocket_phone#{path}", params: body, as: :json, headers: headers
    end

    def json = JSON.parse(response.body)

    def send_text(content = "hello", number: ALICE, **extra)
      api "/api/send-message", { number: number, from_number: LINE, content: content }.merge(extra)
    end

    def conversation_id = db.direct(LINE, ALICE, create: false)["id"]

    # Text the app as Alice, returning the message.
    def text_from_phone(content = "hi there")
      post "/pocket_phone/conversations", params: { number: ALICE, name: "Alice", line: LINE }
      post "/pocket_phone/conversations/#{conversation_id}/messages", params: { content: content }
      db.messages.values.last
    end
  end
end
