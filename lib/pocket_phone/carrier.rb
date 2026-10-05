# frozen_string_literal: true

module PocketPhone
  # Moves messages between the app and the phones, after the request that
  # created them has been answered.
  module Carrier
    TAPBACK_VERBS = {
      "love" => "Loved", "like" => "Liked", "dislike" => "Disliked",
      "laugh" => "Laughed at", "emphasize" => "Emphasized", "question" => "Questioned"
    }.freeze
    # Sendblue's code for a message that was accepted and then failed to send.
    SEND_FAILED = 10_001

    module_function

    # A message the app sent: walk it through Sendblue's statuses, telling the
    # app about each one through its status callback and outbound webhook.
    def deliver_to_phone(handle)
      Runner.run do
        outcome = PocketPhone.store.read.message(handle)&.dig("outcome")
        steps = outcome == "failed" ? %w[ERROR] : %w[SENT DELIVERED]
        steps.each do |status|
          Runner.pause(PocketPhone.config.delivery_delay)
          break unless advance(handle, status)
        end
      end
    end

    # A message a phone sent: the receive webhook.
    def deliver_to_app(handle)
      Runner.run do
        database = PocketPhone.store.read
        message = database.message(handle) or next
        conversation = database.conversations[message["conversation_id"]] or next
        result = receive(Payloads.message(message, conversation))
        PocketPhone.store.write { |db| db.log_webhook(handle, result) }
      end
    end

    # A tapback made on the phone, on something the app sent. Sendblue
    # documents no webhook shape for these, so by default it travels as the
    # text an iPhone falls back to: Loved “hello”.
    def reaction_to_app(handle, by:, reaction:)
      return unless PocketPhone.config.inbound_reactions == :text

      Runner.run do
        database = PocketPhone.store.read
        target = database.message(handle) or next
        conversation = database.conversations[target["conversation_id"]] or next
        tapback = { "handle" => SecureRandom.uuid.upcase, "direction" => "phone", "status" => "RECEIVED",
                    "from_number" => by, "to_number" => conversation["line"],
                    "content" => reaction_text(target, reaction), "service" => target["service"],
                    "created_at" => PocketPhone.now, "updated_at" => PocketPhone.now }
        result = receive(Payloads.message(tapback, conversation)).merge("type" => "reaction")
        PocketPhone.store.write { |db| db.log_webhook(handle, result) }
      end
    end

    def typing_to_app(conversation, is_typing:)
      Runner.run do
        url = Runner.with_app { PocketPhone.config.typing_webhook_url } or next
        Webhook.deliver(type: "typing_indicator", url: url,
          payload: Payloads.typing(number: conversation["number"], line: conversation["line"], is_typing: is_typing))
      end
    end

    # Look up the card for a link, the way the sending phone does. Fetched
    # fresh for every message, since the page you are previewing is likely the
    # one you are editing.
    def fetch_preview(handle)
      return unless PocketPhone.config.link_previews

      message = PocketPhone.store.read.message(handle) or return
      url = LinkPreview.detect(message["content"])[:url] or return
      Runner.run do
        preview = LinkPreview.fetch(url)
        PocketPhone.store.write { |db| db.previews[url] = preview }
      end
    end

    def reaction_text(target, reaction)
      quoted = target["content"].to_s.empty? ? "an attachment" : "“#{target["content"]}”"
      verb = TAPBACK_VERBS[reaction]
      verb ? "#{verb} #{quoted}" : "Reacted #{reaction} to #{quoted}"
    end

    # --- internals ----------------------------------------------------------

    def advance(handle, status)
      payload, callback = PocketPhone.store.write do |db|
        message = db.message(handle) or next
        conversation = db.conversations[message["conversation_id"]] or next
        message["status"] = status
        message["updated_at"] = PocketPhone.now
        if status == "ERROR"
          message["error_code"] = SEND_FAILED
          message["error_message"] = "Message failed to send (simulated by pocket_phone)"
          conversation["unread"] = [conversation["unread"].to_i - 1, 0].max
        end
        [Payloads.message(message, conversation), message["status_callback"]]
      end
      return false unless payload

      outbound = Runner.with_app { PocketPhone.config.outbound_webhook_url }
      [callback, outbound].compact.uniq.each do |url|
        result = Webhook.deliver(type: "outbound #{status}", url: url, payload: payload)
        PocketPhone.store.write { |db| db.log_webhook(handle, result) }
      end
      true
    end

    def receive(payload)
      url = Runner.with_app { PocketPhone.config.webhook_url }
      return Webhook.record("receive", "", "error" => "no webhook_url configured") unless url

      Webhook.deliver(type: "receive", url: url, payload: payload)
    end
  end
end
