# frozen_string_literal: true

module PocketPhone
  class ConversationsController < ApplicationController
    def index
      @db = store.read
      latest = @db.sorted_conversations.first
      return redirect_to(conversation_path(latest["id"])) if latest && params[:list].blank?

      render :show
    end

    def show
      load_conversation(params[:id])
      redirect_to root_path unless @conversation
    end

    # What the page polls. Answers 204 while nothing has changed, and the
    # freshly rendered pieces of the page when something has.
    def state
      load_conversation(params[:conversation])
      token = "#{@db.version}:#{@db.typing?(@conversation) ? 1 : 0}"
      return head(:no_content) if params[:version] == token

      render json: {
        version: token,
        gone: params[:conversation].present? && @conversation.nil?,
        sidebar: render_to_string(partial: "pocket_phone/conversations/sidebar", formats: [:html]),
        head: @conversation && render_to_string(partial: "pocket_phone/conversations/head", formats: [:html]),
        messages: @conversation && render_to_string(partial: "pocket_phone/conversations/messages", formats: [:html])
      }
    end

    # A phone starts a conversation with the app's line: one person, or a
    # group of them.
    def create
      conversation = store.write do |db|
        line = Numbers.normalize(params[:line]).presence || default_line(db)
        db.ensure_line(line)
        params[:group].present? ? create_group(db, line) : create_direct(db, line)
      end
      redirect_to(conversation ? conversation_path(conversation["id"]) : root_path)
    end

    def typing
      conversation = store.read.conversations[params[:id]]
      if conversation && conversation["kind"] == "direct"
        Carrier.typing_to_app(conversation, is_typing: params[:is_typing].to_s != "false")
      end
      head :no_content
    end

    def destroy
      store.write { |db| db.delete_conversation(params[:id]) }
      redirect_to root_path
    end

    def clear
      store.clear!
      redirect_to root_path
    end

    private

    def load_conversation(id)
      @db = store.read
      @conversation = id.present? ? @db.conversations[id] : nil
      return unless @conversation && @conversation["unread"].to_i.positive?

      # Looking at a thread is reading it.
      store.write { |db| db.conversations[id]&.store("unread", 0) }
      @db = store.read
      @conversation = @db.conversations[id]
    end

    def create_direct(db, line)
      number = Numbers.normalize(params[:number])
      return nil if number.empty?

      db.ensure_person(number, "name" => params[:name], "service" => params[:service])
      db.direct(line, number)
    end

    def create_group(db, line)
      participants = Array(params[:participants]).map { |n| Numbers.normalize(n) }.reject(&:empty?).uniq
      return nil if participants.size < 2

      db.create_group(line: line, participants: participants, name: params[:group_name])
    end
  end
end
