# frozen_string_literal: true

module PocketPhone
  # The JSON Sendblue uses to describe a message: the same shape answers a
  # send, arrives in a status callback and arrives in the receive webhook.
  module Payloads
    module_function

    def message(message, conversation)
      from_app = message["direction"] == "app"
      group = conversation["kind"] == "group"
      counterpart = from_app ? message["to_number"] : message["from_number"]

      {
        "accountEmail" => PocketPhone.config.account_email,
        "content" => message["content"].to_s,
        "is_outbound" => from_app,
        "status" => message["status"],
        "error_code" => message["error_code"],
        "error_message" => message["error_message"],
        "error_detail" => nil,
        "message_handle" => message["handle"],
        "date_sent" => message["created_at"],
        "date_updated" => message["updated_at"],
        "from_number" => message["from_number"].to_s,
        "number" => counterpart.to_s,
        "to_number" => message["to_number"].to_s,
        "sendblue_number" => conversation["line"],
        "was_downgraded" => from_app ? message["service"] != "iMessage" : nil,
        "plan" => "blue",
        "media_url" => message["media_url"].to_s,
        "message_type" => group ? "group" : "message",
        "group_id" => group ? conversation["group_id"] : "",
        "group_display_name" => group ? conversation["name"] : nil,
        "participants" => group ? conversation["participants"] : [],
        "send_style" => message["send_style"].to_s,
        "opted_out" => false,
        "service" => message["service"]
      }.tap do |payload|
        payload["media_urls"] = message["media_urls"] if message["media_urls"]
        payload["app_card"] = message["app_card"] if message["app_card"]
      end
    end

    def typing(number:, line:, is_typing:)
      { "number" => number, "is_typing" => is_typing, "from_number" => line,
        "timestamp" => PocketPhone.now }
    end
  end
end
