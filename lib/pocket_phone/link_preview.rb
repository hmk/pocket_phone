# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "nokogiri"
require "uri"

module PocketPhone
  # The rich link card iMessage draws for a URL, and the rules for when it
  # draws one.
  module LinkPreview
    URL = %r{https?://[^\s<>"]+}i
    # Punctuation that ends a sentence rather than a URL. iMessage does not
    # expand a link that is touching any of it.
    TRAILING = /[.,;:!?'")\]}>]+\z/
    # What Messages sends when it fetches a page. Sites that serve og: tags
    # only to crawlers key on the facebookexternalhit / Twitterbot part.
    USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 " \
                 "(KHTML, like Gecko) Version/9.0.1 Safari/601.2.4 " \
                 "facebookexternalhit/1.1 Facebot Twitterbot/1.0"
    MAX_BYTES = 1_000_000
    MAX_REDIRECTS = 5

    SINGLE = "iMessage only previews a message with a single link"
    EDGE = "iMessage only previews a link at the very start or end of a message, " \
           "not mid-sentence or touching punctuation"

    module_function

    # Which link in this text iMessage would expand, if any, and why not when
    # it would not: { url:, reason: }. A message with no links has neither.
    def detect(text)
      text = text.to_s.strip
      urls = text.scan(URL).map { |url| url.sub(TRAILING, "") }
      return { url: nil, reason: nil } if urls.empty?
      return { url: nil, reason: SINGLE } if urls.size > 1

      url = urls.first
      at_start = text.start_with?(url) && text[url.length].to_s.match?(/\A(\s|\z)/)
      at_end = text.end_with?(url) && (text.length == url.length || text[-url.length - 1].match?(/\s/))
      at_start || at_end ? { url: url, reason: nil } : { url: nil, reason: EDGE }
    end

    # Fetch the page and read its og: tags. Never raises: a page that cannot
    # be read comes back with "error" set.
    def fetch(url)
      uri, response = get(url)
      type = response["content-type"].to_s
      preview = base(url, uri)
      if type.start_with?("image/")
        preview.merge("image" => uri.to_s)
      elsif type.include?("html") || type.empty?
        preview.merge(parse(response.body.to_s.byteslice(0, MAX_BYTES), uri))
      else
        preview.merge("title" => File.basename(uri.path))
      end
    rescue StandardError => e
      base(url, nil).merge("error" => "#{e.class.name}: #{e.message}")
    end

    def parse(html, uri)
      document = Nokogiri::HTML(html)
      meta = lambda do |*names|
        names.each do |name|
          node = document.at_css(%(meta[property="#{name}"], meta[name="#{name}"]))
          value = node && node["content"].to_s.strip
          return value unless value.nil? || value.empty?
        end
        nil
      end
      icon = document.at_css('link[rel="apple-touch-icon"], link[rel~="icon"]')

      {
        "title" => meta.call("og:title", "twitter:title") || document.at_css("title")&.text&.strip,
        "description" => meta.call("og:description", "twitter:description", "description"),
        "site_name" => meta.call("og:site_name"),
        "image" => resolve(uri, meta.call("og:image:secure_url", "og:image", "twitter:image")),
        "icon" => resolve(uri, icon && icon["href"])
      }.compact
    end

    # A page the real thing could never show: Apple's fetch happens on a
    # phone, and a phone cannot reach your laptop's localhost.
    def local?(host)
      host = host.to_s.downcase.delete_prefix("[").delete_suffix("]")
      return true if host == "localhost" || host.end_with?(".localhost", ".local", ".test", ".internal")

      address = IPAddr.new(host)
      address.loopback? || address.private? || address.link_local?
    rescue IPAddr::InvalidAddressError
      false
    end

    def get(url, redirects = MAX_REDIRECTS)
      uri = URI.parse(url)
      raise ArgumentError, "not an http(s) URL" unless uri.is_a?(URI::HTTP) && uri.host

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 3, read_timeout: 5) do |http|
        http.get(uri.request_uri, "User-Agent" => USER_AGENT, "Accept" => "text/html,*/*")
      end
      if response.is_a?(Net::HTTPRedirection) && response["location"]
        raise "too many redirects" if redirects.zero?

        return get(URI.join(uri, response["location"]).to_s, redirects - 1)
      end
      raise "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      [uri, response]
    end

    def base(url, uri)
      host = (uri || URI.parse(url)).host.to_s
      { "url" => url, "host" => host.delete_prefix("www."), "local" => local?(host),
        "fetched_at" => PocketPhone.now }
    rescue URI::InvalidURIError
      { "url" => url, "host" => "", "local" => false, "fetched_at" => PocketPhone.now }
    end

    def resolve(uri, href)
      return nil if href.nil? || href.empty?

      URI.join(uri, href).to_s
    rescue URI::Error
      nil
    end
  end
end
