# frozen_string_literal: true

require "test_helper"

class LinkPreviewTest < PocketPhone::TestCase
  PAGE = <<~HTML
    <html><head>
      <title>Plain title</title>
      <meta property="og:title" content="A Fine Article">
      <meta property="og:site_name" content="Example News">
      <meta property="og:image" content="/images/card.png">
      <link rel="icon" href="/favicon.ico">
    </head><body></body></html>
  HTML

  def detect(text) = PocketPhone::LinkPreview.detect(text)

  test "a link alone, or at either end of a message, is previewed" do
    assert_equal "https://example.com/a", detect("https://example.com/a")[:url]
    assert_equal "https://example.com/a", detect("Look at this https://example.com/a")[:url]
    assert_equal "https://example.com/a", detect("https://example.com/a is the one")[:url]
    assert_equal "https://example.com/a", detect("Look:\nhttps://example.com/a\n")[:url]
  end

  test "a link mid-sentence or touching punctuation is not" do
    assert_nil detect("See https://example.com/a for more")[:url]
    assert_match(/start or end/, detect("See https://example.com/a for more")[:reason])
    assert_nil detect("See https://example.com/a.")[:url]
    assert_nil detect("(https://example.com/a)")[:url]
  end

  test "two links are not previewed, and no link is not a problem" do
    assert_match(/single link/, detect("https://a.example https://b.example")[:reason])
    assert_equal({ url: nil, reason: nil }, detect("no links here"))
  end

  test "og tags are read, with relative URLs resolved" do
    stub_request(:get, "https://example.com/a").to_return(body: PAGE, headers: { "Content-Type" => "text/html" })

    preview = PocketPhone::LinkPreview.fetch("https://example.com/a")

    assert_equal "A Fine Article", preview["title"]
    assert_equal "Example News", preview["site_name"]
    assert_equal "https://example.com/images/card.png", preview["image"]
    assert_equal "https://example.com/favicon.ico", preview["icon"]
    assert_equal "example.com", preview["host"]
    assert_equal false, preview["local"]
  end

  test "the page is asked for the way Messages asks" do
    stub = stub_request(:get, "https://example.com/a")
      .with(headers: { "User-Agent" => /facebookexternalhit.*Twitterbot/ })
      .to_return(body: PAGE, headers: { "Content-Type" => "text/html" })

    PocketPhone::LinkPreview.fetch("https://example.com/a")

    assert_requested stub
  end

  test "redirects are followed and failures are reported, not raised" do
    stub_request(:get, "https://short.example/x").to_return(status: 302, headers: { "Location" => "https://example.com/a" })
    stub_request(:get, "https://example.com/a").to_return(body: PAGE, headers: { "Content-Type" => "text/html" })
    stub_request(:get, "https://example.com/gone").to_return(status: 404)

    assert_equal "A Fine Article", PocketPhone::LinkPreview.fetch("https://short.example/x")["title"]
    assert_equal "RuntimeError: HTTP 404", PocketPhone::LinkPreview.fetch("https://example.com/gone")["error"]
  end

  test "a page only your machine can reach is flagged" do
    %w[localhost app.localhost myapp.test 127.0.0.1 192.168.1.20 10.0.0.5].each do |host|
      assert PocketPhone::LinkPreview.local?(host), host
    end
    refute PocketPhone::LinkPreview.local?("example.com")
    refute PocketPhone::LinkPreview.local?("8.8.8.8")
  end

  test "a message with a link gets its card in the thread" do
    PocketPhone.config.link_previews = true
    stub_request(:get, "http://localhost:3000/posts/1").to_return(body: PAGE, headers: { "Content-Type" => "text/html" })

    send_text "Read this http://localhost:3000/posts/1"
    get "/pocket_phone/conversations/#{conversation_id}"

    assert_includes response.body, "A Fine Article"
    assert_includes response.body, "http://localhost:3000/images/card.png"
    assert_includes response.body, "A real phone could not load this preview"
  end

  test "a link that would not preview says why" do
    PocketPhone.config.link_previews = true

    send_text "See https://example.com/a for more"
    get "/pocket_phone/conversations/#{conversation_id}"

    assert_includes response.body, "No link preview"
  end
end
