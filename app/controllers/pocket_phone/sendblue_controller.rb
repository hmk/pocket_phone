# frozen_string_literal: true

module PocketPhone
  # The part of Sendblue's API that pocket_phone answers. Requests are
  # checked the way Sendblue checks them, so a client that would be refused
  # for real is refused here too; nothing leaves the machine.
  class SendblueController < ActionController::API
    TAPBACKS = %w[love like dislike laugh emphasize question].freeze
    # Sendblue's code for a number it will not send to.
    BLOCKED = 4002

    # A request Sendblue would turn down, with the status and body it uses.
    class Refusal < StandardError
      attr_reader :status, :body

      def initialize(status, body)
        @status = status
        @body = body
        super(body["message"] || body["error_message"])
      end
    end

    wrap_parameters false
    rescue_from(Refusal) { |refusal| render json: refusal.body, status: refusal.status }
    before_action :remember_base_url, :require_credentials

    # --- sending ----------------------------------------------------------

    def send_message
      number = recipient!(params[:number])
      line = line!
      body = message_body!

      message, conversation = store.write do |db|
        db.ensure_line(line)
        person = db.ensure_person(number)
        conversation = db.direct(line, number)
        attrs = body.merge("to_number" => number, "service" => person["service"], "outcome" => person["outcome"])
        [db.add_message(conversation, outbound(line, attrs)), conversation]
      end
      carry(message)
      render json: Payloads.message(message, conversation)
    end

    # A group is addressed by `group_id`, or made on the spot from `numbers`.
    def send_group_message
      line = line!
      body = message_body!
      numbers = Array(params[:numbers]).map(&:to_s)
      numbers.each { |number| recipient!(number) }
      group_id = params[:group_id].to_s

      message, conversation = store.write do |db|
        db.ensure_line(line)
        conversation = db.group(group_id) if group_id.present?
        if conversation.nil?
          next if numbers.size < 2

          conversation = db.create_group(line: line, participants: numbers, group_id: group_id)
        end
        attrs = body.merge("service" => db.service_for(conversation), "outcome" => "delivered")
        [db.add_message(conversation, outbound(line, attrs)), conversation]
      end
      unless message
        refuse!(400, group_id.present? ? "Group #{group_id} was not found; send `numbers` to create it." :
          "You must specify a `group_id` or at least two `numbers`.")
      end

      carry(message)
      render json: Payloads.message(message, conversation)
    end

    def send_carousel
      number = recipient!(params[:number])
      line = line!
      urls = Array(params[:media_urls]).map(&:to_s)
      refuse!(400, "You must provide between 2 and 20 HTTPS image URLs.") unless urls.size.between?(2, 20)

      message, conversation = store.write do |db|
        db.ensure_line(line)
        person = db.ensure_person(number)
        refuse!(422, "Carousels are only supported on iMessage") unless person["service"] == "iMessage"

        conversation = db.direct(line, number)
        attrs = { "to_number" => number, "media_urls" => urls, "service" => "iMessage",
                  "outcome" => person["outcome"], "send_style" => params[:send_style].presence }
        [db.add_message(conversation, outbound(line, attrs)), conversation]
      end
      carry(message)
      render json: Payloads.message(message, conversation)
    end

    # --- the small gestures -----------------------------------------------

    def send_typing_indicator
      refuse!(400, "You must specify a `number` in the request body.") if params[:number].blank?
      number = recipient!(params[:number])
      state = params[:state].presence || "start"
      refuse!(400, '`state` must be either "start" or "stop".') unless %w[start stop].include?(state)
      duration = Integer(params[:max_duration_ms].presence || 60_000, exception: false)
      unless duration&.between?(1, 300_000)
        refuse!(400, "`max_duration_ms` must be an integer between 1 and 300000.")
      end

      store.write do |db|
        line = Numbers.normalize(params[:from_number])
        conversation = line.empty? ? db.latest_direct(number) : db.direct(line, number, create: false)
        next unless conversation

        if state == "start"
          conversation["typing_until"] = (Time.now.utc + (duration / 1000.0)).iso8601(3)
        else
          conversation.delete("typing_until")
        end
      end
      render json: { status: "QUEUED", status_code: 200, error_message: nil, number: number }
    end

    def send_reaction
      line!
      reaction = params[:reaction].to_s
      remove = reaction.start_with?("-")
      name = reaction.delete_prefix("-")
      unless TAPBACKS.include?(name) || single_emoji?(name)
        refuse!(400, "Invalid reaction. Must be one of love, like, dislike, laugh, emphasize, question, " \
                     "or exactly one emoji")
      end

      store.write do |db|
        message = db.message(params[:message_handle])
        unless message && message["direction"] == "phone"
          refuse!(404, "The message to react to was not found for this account")
        end
        refuse!(422, "Reactions are only supported on iMessage messages") unless message["service"] == "iMessage"

        db.react(message, by: "line", reaction: name, remove: remove)
      end
      render json: { status: "OK", message: "Reaction request sent",
                     message_handle: params[:message_handle], reaction: reaction }
    end

    def mark_read
      number = recipient!(params[:number])
      line = line!
      store.write do |db|
        conversation = db.direct(line, number, create: false)
        conversation["read_at"] = PocketPhone.now if conversation
      end
      render json: { status: "OK", message: "Mark read request sent", number: number }
    end

    def evaluate_service
      number = recipient!(params[:number])
      render json: { number: number, service: store.read.people.dig(number, "service") || "iMessage" }
    end

    # The name and photo iMessage shows for the line.
    def contact_profile
      line = Numbers.normalize(params[:fromNumber] || params[:from_number])
      refuse!(400, "You must specify a `fromNumber` in the request body.") if line.empty?

      name = [params[:firstName] || params[:first_name], params[:lastName] || params[:last_name]].compact.join(" ")
      store.write do |db|
        profile = db.ensure_line(line)
        profile["name"] = name.presence
        profile["photo_url"] = (params[:photoUrl] || params[:photo_url]).presence
      end
      render json: { status: "OK" }
    end

    def modify_group
      number = recipient!(params[:number])
      type = params[:modify_type].to_s
      refuse!(400, '`modify_type` must be "add_recipient" or "remove_recipient".') unless
        %w[add_recipient remove_recipient].include?(type)

      echo = { "group_id" => params[:group_id].to_s, "modify_type" => type, "number" => number }
      store.write do |db|
        conversation = db.group(params[:group_id]) or
          refuse!(404, "Group #{params[:group_id]} was not found", echo.merge("error" => "group_not_found"))
        if type == "add_recipient"
          db.ensure_person(number)
          conversation["participants"] |= [number]
        elsif conversation["participants"].size <= 2
          refuse!(400, "Cannot remove from a group with 3 total members; Apple requires at least 3.",
            echo.merge("error" => "group_too_small"))
        else
          conversation["participants"] -= [number]
        end
      end
      render json: { "status" => "OK" }.merge(echo)
    end

    # --- media ------------------------------------------------------------

    def upload_file
      file = params[:file]
      refuse!(400, "You must attach a `file`.") unless file.respond_to?(:original_filename)

      name = store.save_media(file, file.original_filename)
      render status: :created, json: { status: "OK", message: "File uploaded successfully",
                                       media_url: media_url_for(name), mediaObjectId: name }
    end

    def upload_media_object
      refuse!(400, "You must specify a `media_url` in the request body.") if params[:media_url].blank?

      render status: :created, json: { status: "OK", message: "File uploaded successfully",
                                       mediaObjectId: File.basename(URI.parse(params[:media_url].to_s).path) }
    end

    # --- reading back -----------------------------------------------------

    def messages
      db = store.read
      found = db.messages.values.reverse.filter_map do |message|
        conversation = db.conversations[message["conversation_id"]]
        conversation && Payloads.message(message, conversation)
      end
      found.select! { |m| m["is_outbound"].to_s == params[:is_outbound] } if params[:is_outbound].present?
      %w[status service group_id from_number to_number number].each do |field|
        found.select! { |m| m[field].to_s == params[field].to_s } if params[field].present?
      end
      limit = params.fetch(:limit, 100).to_i.clamp(1, 100)
      offset = [params[:offset].to_i, 0].max
      render json: { status: "OK", data: found[offset, limit] || [],
                     pagination: { limit: limit, offset: offset, total: found.size } }
    end

    def message
      db = store.read
      found = db.message(params[:handle]) or refuse!(404, "Message not found")
      render json: { status: "OK", data: Payloads.message(found, db.conversations[found["conversation_id"]]) }
    end

    def delete_message
      deleted = store.write { |db| db.messages.delete(params[:handle]) }
      refuse!(404, "Message not found") unless deleted

      render json: { status: "OK", message: "Message deleted" }
    end

    def missing
      refuse!(404, "pocket_phone does not fake #{request.method} #{request.path.delete_prefix(request.script_name)} yet")
    end

    private

    def store = PocketPhone.store

    def remember_base_url
      PocketPhone.base_url = request.base_url
    end

    # Sendblue wants both keys on every call. With none configured here any
    # pair will do, so long as the client sent one.
    def require_credentials
      key = request.headers["sb-api-key-id"].to_s
      secret = request.headers["sb-api-secret-key"].to_s
      expected_key = PocketPhone.config.api_key_id
      expected_secret = PocketPhone.config.api_secret
      valid = key.present? && secret.present? &&
              (expected_key.nil? || expected_key.to_s == key) &&
              (expected_secret.nil? || expected_secret.to_s == secret)
      refuse!(401, "Missing or invalid `sb-api-key-id` / `sb-api-secret-key` headers.") unless valid
    end

    def refuse!(status, message, extra = {})
      raise Refusal.new(status, { "status" => "ERROR", "message" => message, "error_message" => message }.merge(extra))
    end

    def recipient!(value)
      refuse!(400, "You must specify a `number` in the request body.") if value.blank?
      refuse!(400, "`#{value}` is not a valid E.164 phone number (for example +19998887777).") unless
        Numbers.valid?(value)

      value.to_s
    end

    def line!
      value = params[:from_number]
      refuse!(400, "You must specify a `from_number` in the request body.") if value.blank?
      refuse!(400, "`from_number` must be an E.164 phone number on your account.") unless
        value.to_s.match?(Numbers::E164)

      value.to_s
    end

    def message_body!
      card = params[:app_card].presence && params[:app_card].to_unsafe_h
      if params[:content].blank? && params[:media_url].blank? && card.nil?
        refuse!(400, "You must specify `content`, a `media_url` or an `app_card`.")
      end
      refuse!(400, "An `app_card` cannot be combined with `media_url`.") if card && params[:media_url].present?

      { "content" => params[:content].to_s, "media_url" => params[:media_url].presence,
        "send_style" => params[:send_style].presence, "app_card" => card }
    end

    def outbound(line, attrs)
      attrs = attrs.merge("direction" => "app", "from_number" => line, "status" => "QUEUED",
        "status_callback" => params[:status_callback].presence,
        "request" => request.request_parameters.except("format"))
      return attrs unless attrs["outcome"] == "rejected"

      # Sendblue answers 200 with status ERROR when it refuses a send, so
      # the HTTP status alone does not say whether a message went out.
      attrs.merge("status" => "ERROR", "error_code" => BLOCKED,
        "error_message" => "This number cannot be messaged (simulated by pocket_phone)")
    end

    def carry(message)
      return if message["status"] == "ERROR"

      Carrier.deliver_to_phone(message["handle"])
      Carrier.fetch_preview(message["handle"])
    end

    def single_emoji?(text)
      text.match?(/\A\X\z/) && text.match?(/\p{Emoji}/) && !text.match?(/\A[0-9#*]\z/)
    end

    def media_url_for(name)
      "#{request.base_url}#{request.script_name}/media/#{name}"
    end
  end
end
