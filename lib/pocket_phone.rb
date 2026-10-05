# frozen_string_literal: true

require "pocket_phone/version"
require "pocket_phone/configuration"
require "pocket_phone/numbers"
require "pocket_phone/database"
require "pocket_phone/store"
require "pocket_phone/payloads"
require "pocket_phone/runner"
require "pocket_phone/webhook"
require "pocket_phone/link_preview"
require "pocket_phone/carrier"
require "pocket_phone/engine"

# A fake Sendblue for development: your app sends to it instead of to
# api.sendblue.com, and you answer from a phone in the browser.
module PocketPhone
  # The line a phone texts when nothing has told us the app's real number yet.
  FALLBACK_LINE = "+15555550100"

  class << self
    # The scheme and host of the last request the engine served. Webhook URLs
    # may be configured as paths ("/webhooks/sendblue/token"); this is what
    # they are resolved against.
    attr_accessor :base_url

    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    def reset_config!
      @config = nil
    end

    def store
      Store.new(config.storage_path)
    end

    def now
      Time.now.utc.iso8601(3)
    end
  end
end
