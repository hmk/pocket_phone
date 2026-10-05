# frozen_string_literal: true

require "digest"
require "securerandom"

module PocketPhone
  # Everything pocket_phone knows, as one plain hash that round-trips through
  # JSON: the app's lines, the fake people, their conversations and messages.
  class Database
    SERVICES = %w[iMessage SMS RCS].freeze
    # What happens to a message the app sends this person: it arrives, it
    # fails after being accepted, or the send is refused outright.
    OUTCOMES = %w[delivered failed rejected].freeze

    attr_reader :data

    def self.blank
      { "version" => 0, "lines" => {}, "people" => {}, "conversations" => {},
        "messages" => {}, "previews" => {} }
    end

    def initialize(data)
      @data = self.class.blank.merge(data || {})
    end

    def version = data["version"].to_i
    def lines = data["lines"]
    def people = data["people"]
    def conversations = data["conversations"]
    def messages = data["messages"]
    def previews = data["previews"]

    # --- lines and people ---------------------------------------------------

    def ensure_line(number)
      lines[number] ||= { "number" => number }
    end

    def ensure_person(number, attrs = {})
      person = people[number] ||= { "number" => number, "name" => nil,
                                    "service" => "iMessage", "outcome" => "delivered" }
      attrs.each do |key, value|
        next if value.nil? || value.to_s.empty?

        person[key.to_s] = value.to_s
      end
      person["service"] = "iMessage" unless SERVICES.include?(person["service"])
      person["outcome"] = "delivered" unless OUTCOMES.include?(person["outcome"])
      person
    end

    # --- conversations ------------------------------------------------------

    def direct(line, number, create: true)
      id = "dm_#{Digest::SHA1.hexdigest("#{line}|#{number}")[0, 16]}"
      return conversations[id] unless create

      conversations[id] ||= { "id" => id, "kind" => "direct", "line" => line, "number" => number,
                              "unread" => 0, "updated_at" => PocketPhone.now }
    end

    # The one-to-one this number is in, whichever line it is with. For calls
    # that name the person but not the line.
    def latest_direct(number)
      conversations.values
        .select { |c| c["kind"] == "direct" && c["number"] == number }
        .max_by { |c| c["updated_at"].to_s }
    end

    def group(group_id)
      conversation = conversations[group_id]
      conversation if conversation && conversation["kind"] == "group"
    end

    def create_group(line:, participants:, name: nil, group_id: nil)
      id = group_id.to_s.empty? ? SecureRandom.uuid : group_id.to_s
      participants.each { |number| ensure_person(number) }
      conversations[id] = { "id" => id, "kind" => "group", "line" => line, "group_id" => id,
                            "participants" => participants.uniq, "name" => name.to_s.empty? ? nil : name,
                            "unread" => 0, "updated_at" => PocketPhone.now }
    end

    def sorted_conversations
      conversations.values.sort_by { |c| c["updated_at"].to_s }.reverse
    end

    def group?(conversation) = conversation["kind"] == "group"

    # A group is only blue when everyone in it is; one Android phone turns the
    # whole thread into group MMS.
    def service_for(conversation)
      if group?(conversation)
        blue = conversation["participants"].all? { |n| people.dig(n, "service").to_s == "iMessage" }
        blue ? "iMessage" : "SMS"
      else
        people.dig(conversation["number"], "service") || "iMessage"
      end
    end

    def typing?(conversation)
      conversation && conversation["typing_until"].to_s > PocketPhone.now &&
        service_for(conversation) == "iMessage"
    end

    def delete_conversation(id)
      conversations.delete(id)
      messages.delete_if { |_, message| message["conversation_id"] == id }
    end

    # --- messages -----------------------------------------------------------

    def message(handle) = messages[handle.to_s]

    def messages_for(conversation)
      messages.values.select { |m| m["conversation_id"] == conversation["id"] }
    end

    def add_message(conversation, attrs)
      now = PocketPhone.now
      attrs = attrs.transform_keys(&:to_s).compact
      from_app = attrs["direction"] == "app"
      message = {
        # Sendblue's own handles look like this: lower case for what you sent,
        # upper case for what a phone sent you.
        "handle" => from_app ? SecureRandom.uuid : SecureRandom.uuid.upcase,
        "conversation_id" => conversation["id"], "created_at" => now, "updated_at" => now,
        "reactions" => [], "webhooks" => []
      }.merge(attrs)
      messages[message["handle"]] = message

      conversation["updated_at"] = now
      if from_app
        # The message is the answer the dots were promising.
        conversation.delete("typing_until")
        conversation["unread"] = conversation["unread"].to_i + 1 unless message["status"] == "ERROR"
      end
      message
    end

    # One reaction per sender per message, as in iMessage. Returns :added or
    # :removed.
    def react(message, by:, reaction:, remove: false)
      list = message["reactions"] ||= []
      existing = list.find { |r| r["by"] == by }
      list.delete(existing) if existing
      return :removed if remove || (existing && existing["reaction"] == reaction)

      list << { "by" => by, "reaction" => reaction }
      :added
    end

    def log_webhook(handle, result)
      found = message(handle) or return
      (found["webhooks"] ||= []) << result
    end
  end
end
