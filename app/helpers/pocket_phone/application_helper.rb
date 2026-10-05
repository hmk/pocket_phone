# frozen_string_literal: true

module PocketPhone
  module ApplicationHelper
    TAPBACKS = { "love" => "❤️", "like" => "👍", "dislike" => "👎",
                 "laugh" => "😂", "emphasize" => "‼️", "question" => "❓" }.freeze
    IMAGE = /\.(png|jpe?g|gif|webp|heic|avif|svg|bmp)\z/i
    VIDEO = /\.(mp4|mov|m4v|webm)\z/i
    AUDIO = /\.(mp3|m4a|wav|caf|aac|ogg|amr)\z/i
    # Minutes of quiet before iMessage puts a timestamp between two messages.
    TIMESTAMP_GAP = 15 * 60

    def pp_base = root_path.chomp("/")

    # --- names ----------------------------------------------------------------

    def pp_person_name(number)
      @db.people.dig(number, "name").presence || Numbers.pretty(number)
    end

    def pp_line_name(line)
      @db.lines.dig(line, "name").presence || Numbers.pretty(line)
    end

    def pp_sender_name(message)
      message["direction"] == "app" ? pp_line_name(message["from_number"]) : pp_person_name(message["from_number"])
    end

    def pp_title(conversation)
      return pp_person_name(conversation["number"]) unless @db.group?(conversation)

      conversation["name"].presence || conversation["participants"].map { |n| pp_person_name(n).split.first }.to_sentence
    end

    def pp_avatar(label, key: label, photo: nil, size: nil)
      style = "--hue:#{key.to_s.sum % 360};"
      style += "width:#{size}px;height:#{size}px;font-size:#{(size * 0.4).round}px;" if size
      return tag.span(image_tag(photo, alt: ""), class: "pp-avatar", style: style) if photo.present?

      letters = label.to_s.scan(/\b[[:alpha:]]/).first(2).join.upcase
      letters = label.to_s.match?(/\p{Emoji_Presentation}/) ? label : "#" if letters.empty?
      tag.span(letters, class: "pp-avatar", style: style)
    end

    # --- time -----------------------------------------------------------------

    def pp_clock(iso)
      Time.iso8601(iso).localtime.strftime("%-l:%M %p")
    rescue ArgumentError, TypeError
      ""
    end

    def pp_stamp(iso)
      time = Time.iso8601(iso).localtime
      day = if time.to_date == Date.today then "Today"
            elsif time.to_date == Date.today - 1 then "Yesterday"
            else time.strftime("%a, %b %-d")
            end
      safe_join([tag.strong(day), " ", time.strftime("%-l:%M %p")])
    rescue ArgumentError, TypeError
      ""
    end

    def pp_gap?(previous, message)
      return true if previous.nil?

      Time.iso8601(message["created_at"]) - Time.iso8601(previous["created_at"]) > TIMESTAMP_GAP
    rescue ArgumentError, TypeError
      false
    end

    # --- message bodies -------------------------------------------------------

    def pp_linkify(text)
      pieces = text.to_s.split(/(https?:\/\/[^\s<>"]+)/i).map do |piece|
        next piece unless piece.match?(/\Ahttps?:\/\//i)

        url = piece.sub(LinkPreview::TRAILING, "")
        safe_join([link_to(url, url, target: "_blank", rel: "noopener"), piece[url.length..]])
      end
      safe_join(pieces)
    end

    def pp_media(url)
      path = url.to_s.split(/[?#]/).first
      if path.match?(VIDEO)
        tag.video(src: url, controls: true, class: "pp-media")
      elsif path.match?(AUDIO)
        tag.audio(src: url, controls: true, class: "pp-audio")
      elsif path.match?(IMAGE) || File.extname(path).empty?
        # Many image URLs have no extension; if it turns out not to be one, the
        # page swaps this for a link.
        link_to(image_tag(url, alt: "", class: "pp-media", data: { fallback: File.basename(path) }),
          url, target: "_blank", rel: "noopener")
      else
        link_to("📎 #{File.basename(path)}", url, class: "pp-file", target: "_blank", rel: "noopener")
      end
    end

    def pp_snippet(message)
      return "" unless message

      text = message["content"].to_s.strip
      text = "Attachment" if text.empty? && (message["media_url"].present? || message["media_urls"].present?)
      text = message.dig("app_card", "appName").to_s if text.empty? && message["app_card"]
      truncate(text, length: 70)
    end

    def pp_tapback(reaction) = TAPBACKS[reaction] || reaction

    def pp_preview_for(message)
      found = LinkPreview.detect(message["content"])
      preview = found[:url] && @db.previews[found[:url]]
      card = preview && preview["error"].nil? && (preview["title"].present? || preview["image"].present?)
      { url: found[:url], reason: found[:reason], preview: preview, card: card ? preview : nil }
    end

    # --- what iMessage prints under a bubble ----------------------------------

    # For a message the phone sent, the line under it: Delivered once the app
    # accepted the webhook, Read once the app marked the thread read, and Not
    # Delivered (with the reason) when the webhook failed.
    def pp_receipt(message, conversation, last:)
      hook = Array(message["webhooks"]).reverse.find { |w| w["type"] == "receive" }
      return { text: "Sending…" } if hook.nil?

      unless hook["status"].to_i.between?(200, 299)
        reason = hook["error"] || "the webhook answered #{hook["status"]}"
        return { text: "Not Delivered", failed: true, detail: reason }
      end
      return nil unless last

      read = conversation["read_at"].to_s >= message["created_at"].to_s && message["service"] == "iMessage"
      { text: read ? "Read #{pp_clock(conversation["read_at"])}" : "Delivered" }
    end

    def pp_webhook_outcome(hook)
      hook["error"] || "HTTP #{hook["status"]}"
    end

    def pp_json(value)
      JSON.pretty_generate(value)
    end
  end
end
