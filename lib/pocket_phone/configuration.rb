# frozen_string_literal: true

module PocketPhone
  class Configuration
    # Settings that may be given as a value or as a callable. A callable is
    # resolved each time it is read, so it can lean on app code that is not
    # loaded yet when the initializer runs (a credentials row, say).
    LAZY = %i[
      storage_path webhook_url outbound_webhook_url typing_webhook_url
      signing_secret secret_header from_number account_email api_key_id api_secret
    ].freeze

    attr_writer(*LAZY)

    # Deliver webhooks and fetch link previews on a background thread. Turn off
    # in tests to make everything happen inline, with no delays.
    attr_accessor :async
    # Seconds between the QUEUED, SENT and DELIVERED steps of a message the app
    # sends.
    attr_accessor :delivery_delay
    # Fetch og: tags for links, the way iMessage does.
    attr_accessor :link_previews
    # How a tapback made on the phone reaches the app: :text sends it as a
    # received message ("Loved “hello”"), :none keeps it in the UI only.
    attr_accessor :inbound_reactions
    # Seconds to wait for the app to answer a webhook.
    attr_accessor :webhook_timeout
    # People to create on first use: [{ name: "Alice", number: "+15555550101",
    # service: "iMessage" }]
    attr_accessor :people

    def initialize
      @secret_header = "sb-signing-secret"
      @account_email = "pocket_phone@example.com"
      @async = true
      @delivery_delay = 0.4
      @link_previews = true
      @inbound_reactions = :text
      @webhook_timeout = 45
      @people = []
    end

    LAZY.each do |name|
      define_method(name) do
        value = instance_variable_get(:"@#{name}")
        value = value.call if value.respond_to?(:call)
        value.respond_to?(:empty?) && value.empty? ? nil : value
      end
    end

    def storage_path
      value = @storage_path
      value = value.call if value.respond_to?(:call)
      return value.to_s if value

      root = defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.to_s : Dir.pwd
      File.join(root, "tmp", "pocket_phone")
    end
  end
end
