# frozen_string_literal: true

module PocketPhone
  # What the person holding the phone does: text, tapback, try again.
  class MessagesController < ApplicationController
    def create
      upload = params[:file].presence
      media_url = upload && media_url_for(store.save_media(upload, upload.original_filename))
      content = params[:content].to_s.strip
      return head(:unprocessable_entity) if content.empty? && media_url.nil?

      message = store.write do |db|
        conversation = db.conversations[params[:id]] or next
        from = sender(db, conversation) or next
        db.add_message(conversation, "direction" => "phone", "status" => "RECEIVED",
          "from_number" => from, "to_number" => conversation["line"],
          "content" => content, "media_url" => media_url, "service" => db.service_for(conversation))
      end
      return head(:not_found) unless message

      Carrier.deliver_to_app(message["handle"])
      Carrier.fetch_preview(message["handle"])
      head :no_content
    end

    # A tapback on something the app sent. Tapping the same one again takes it
    # back, as on a phone.
    def react
      reaction = params[:reaction].to_s
      outcome, by = store.write do |db|
        message = db.message(params[:handle]) or next
        conversation = db.conversations[message["conversation_id"]] or next
        next unless message["direction"] == "app" && message["service"] == "iMessage"

        by = sender(db, conversation) or next
        [db.react(message, by: by, reaction: reaction), by]
      end
      return head(:unprocessable_entity) unless outcome

      Carrier.reaction_to_app(params[:handle], by: by, reaction: reaction) if outcome == :added
      head :no_content
    end

    # Send the receive webhook again, as Sendblue does after a 5xx. Handy for
    # checking that a redelivery is not answered twice.
    def redeliver
      message = store.read.message(params[:handle])
      return head(:not_found) unless message && message["direction"] == "phone"

      Carrier.deliver_to_app(message["handle"])
      head :no_content
    end

    private

    # Who is talking. A one-to-one has one phone in it; in a group the page
    # says which participant it is speaking as.
    def sender(db, conversation)
      return conversation["number"] unless db.group?(conversation)

      chosen = Numbers.normalize(params[:as])
      conversation["participants"].include?(chosen) ? chosen : conversation["participants"].first
    end
  end
end
