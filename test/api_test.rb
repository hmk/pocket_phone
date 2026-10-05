# frozen_string_literal: true

require "test_helper"

class ApiTest < PocketPhone::TestCase
  test "a sent message is stored and answered in Sendblue's shape" do
    send_text "hello **there**", send_style: "slam"

    assert_response :success
    assert_equal "QUEUED", json["status"]
    assert_equal true, json["is_outbound"]
    assert_equal "iMessage", json["service"]
    assert_equal ALICE, json["number"]
    assert_equal LINE, json["from_number"]
    assert_match(/\A[0-9a-f-]{36}\z/, json["message_handle"])

    message = db.message(json["message_handle"])
    assert_equal "hello **there**", message["content"]
    assert_equal "DELIVERED", message["status"]
    assert_equal "slam", message["send_style"]
    assert_equal 1, db.direct(LINE, ALICE, create: false)["unread"]
  end

  test "a call without the key pair is refused" do
    api "/api/send-message", { number: ALICE, from_number: LINE, content: "x" }, headers: {}

    assert_response :unauthorized
    assert_equal "ERROR", json["status"]
    assert_empty db.messages
  end

  test "configured keys must match" do
    PocketPhone.config.api_secret = "the-real-one"
    send_text "hello"
    assert_response :unauthorized

    api "/api/send-message", { number: ALICE, from_number: LINE, content: "x" },
      headers: { "sb-api-key-id" => "key", "sb-api-secret-key" => "the-real-one" }
    assert_response :success
  end

  test "a number that is not E.164 is refused, as is a message with nothing in it" do
    send_text "hello", number: "555-222-3333"
    assert_response :bad_request

    api "/api/send-message", { number: ALICE, from_number: LINE }
    assert_response :bad_request
    assert_empty db.messages
  end

  test "status callbacks follow the message from SENT to DELIVERED" do
    statuses = []
    stub_request(:post, "http://app.test/status").with { |request| statuses << JSON.parse(request.body)["status"] }

    send_text "hello", status_callback: "http://app.test/status"

    assert_equal %w[SENT DELIVERED], statuses
    assert_equal ["outbound SENT", "outbound DELIVERED"], db.messages.values.last["webhooks"].map { |w| w["type"] }
  end

  test "the outbound webhook hears about every message" do
    PocketPhone.config.outbound_webhook_url = "http://app.test/outbound"
    stub = stub_request(:post, "http://app.test/outbound")

    send_text "hello"

    assert_requested stub, times: 2
  end

  test "an Android phone gets SMS, and refuses what SMS cannot carry" do
    PocketPhone.store.write { |db| db.ensure_person(ALICE, "service" => "SMS") }

    send_text "hello"
    assert_equal "SMS", json["service"]
    assert_equal true, json["was_downgraded"]

    api "/api/evaluate-service?number=#{CGI.escape(ALICE)}"
    assert_response :not_found # evaluate-service is a GET

    get "/pocket_phone/api/evaluate-service", params: { number: ALICE }, headers: KEYS
    assert_equal "SMS", json["service"]
  end

  test "a person set to refuse sends answers 200 with status ERROR" do
    PocketPhone.store.write { |db| db.ensure_person(ALICE, "outcome" => "rejected") }

    send_text "hello"

    assert_response :success
    assert_equal "ERROR", json["status"]
    assert_equal 4002, json["error_code"]
    assert_equal 0, db.direct(LINE, ALICE, create: false)["unread"]
  end

  test "a person set to fail reports ERROR through the callback" do
    PocketPhone.store.write { |db| db.ensure_person(ALICE, "outcome" => "failed") }
    statuses = []
    stub_request(:post, "http://app.test/status").with { |request| statuses << JSON.parse(request.body)["status"] }

    send_text "hello", status_callback: "http://app.test/status"

    assert_equal "QUEUED", json["status"]
    assert_equal %w[ERROR], statuses
    assert_equal 10_001, db.messages.values.last["error_code"]
  end

  test "a group is made from numbers and addressed by its id afterwards" do
    api "/api/send-group-message", { numbers: [ALICE, "+15554445555"], from_number: LINE, content: "hi all" }
    assert_response :success
    group_id = json["group_id"]
    assert_equal "group", json["message_type"]
    assert_equal [ALICE, "+15554445555"], json["participants"]

    api "/api/send-group-message", { group_id: group_id, from_number: LINE, content: "again" }
    assert_response :success
    assert_equal 2, db.messages_for(db.group(group_id)).size

    api "/api/send-group-message", { group_id: "nope", from_number: LINE, content: "x" }
    assert_response :bad_request
  end

  test "group membership can be changed, down to three people" do
    api "/api/send-group-message", { numbers: [ALICE, "+15554445555"], from_number: LINE, content: "hi" }
    group_id = json["group_id"]

    api "/api/modify-group", { group_id: group_id, modify_type: "add_recipient", number: "+15556667777", from_number: LINE }
    assert_response :success
    assert_equal 3, db.group(group_id)["participants"].size

    api "/api/modify-group", { group_id: group_id, modify_type: "remove_recipient", number: ALICE, from_number: LINE }
    assert_response :success
    api "/api/modify-group", { group_id: group_id, modify_type: "remove_recipient", number: "+15556667777", from_number: LINE }
    assert_response :bad_request
    assert_equal "group_too_small", json["error"]
  end

  test "a typing indicator shows until the message arrives" do
    send_text "first"
    api "/api/send-typing-indicator", { number: ALICE }
    assert_response :success
    assert_equal "QUEUED", json["status"]
    assert db.typing?(db.direct(LINE, ALICE, create: false))

    send_text "second"
    refute db.typing?(db.direct(LINE, ALICE, create: false))

    api "/api/send-typing-indicator", { number: ALICE, state: "sideways" }
    assert_response :bad_request
  end

  test "a tapback lands on a message the phone sent, and only there" do
    stub_request(:post, WEBHOOK)
    PocketPhone.config.webhook_url = WEBHOOK
    theirs = text_from_phone("nice")
    send_text "ours"
    ours = json["message_handle"]

    api "/api/send-reaction", { from_number: LINE, message_handle: theirs["handle"], reaction: "love" }
    assert_response :success
    assert_equal [{ "by" => "line", "reaction" => "love" }], db.message(theirs["handle"])["reactions"]

    api "/api/send-reaction", { from_number: LINE, message_handle: theirs["handle"], reaction: "🔥" }
    assert_equal "🔥", db.message(theirs["handle"])["reactions"].first["reaction"]

    api "/api/send-reaction", { from_number: LINE, message_handle: theirs["handle"], reaction: "-🔥" }
    assert_empty db.message(theirs["handle"])["reactions"]

    api "/api/send-reaction", { from_number: LINE, message_handle: ours, reaction: "love" }
    assert_response :not_found
    api "/api/send-reaction", { from_number: LINE, message_handle: theirs["handle"], reaction: "adore" }
    assert_response :bad_request
  end

  test "a tapback on an SMS is refused" do
    stub_request(:post, WEBHOOK)
    PocketPhone.config.webhook_url = WEBHOOK
    post "/pocket_phone/conversations", params: { number: ALICE, service: "SMS", line: LINE }
    post "/pocket_phone/conversations/#{conversation_id}/messages", params: { content: "green" }

    api "/api/send-reaction", { from_number: LINE, message_handle: db.messages.keys.last, reaction: "like" }

    assert_response :unprocessable_entity
  end

  test "marking read stamps the conversation" do
    send_text "hello"
    api "/api/mark-read", { number: ALICE, from_number: LINE }

    assert_response :success
    assert db.direct(LINE, ALICE, create: false)["read_at"]
  end

  test "the line's shared name and photo are kept" do
    api "/api/v2/contact-sharing/profile", { fromNumber: LINE, firstName: "Finn", photoUrl: "https://app.test/card.jpg" }

    assert_response :success
    assert_equal({ "number" => LINE, "name" => "Finn", "photo_url" => "https://app.test/card.jpg" }, db.lines[LINE])
  end

  test "a carousel needs at least two images" do
    api "/api/send-carousel", { number: ALICE, from_number: LINE, media_urls: ["https://x.test/1.png"] }
    assert_response :bad_request

    api "/api/send-carousel", { number: ALICE, from_number: LINE, media_urls: %w[https://x.test/1.png https://x.test/2.png] }
    assert_response :success
    assert_equal 2, json["media_urls"].size
  end

  test "an uploaded file comes back as a URL this server answers" do
    file = Rack::Test::UploadedFile.new(StringIO.new("fake image"), "image/png", original_filename: "cat.png")
    post "/pocket_phone/api/upload-file", params: { file: file }, headers: KEYS

    assert_response :created
    assert_match %r{\Ahttp://www.example.com/pocket_phone/media/\h+\.png\z}, json["media_url"]

    get URI.parse(json["media_url"]).path
    assert_response :success
    assert_equal "fake image", response.body
  end

  test "messages can be listed and fetched" do
    send_text "one"
    send_text "two"
    handle = json["message_handle"]

    get "/pocket_phone/api/v2/messages", params: { number: ALICE, limit: 1 }, headers: KEYS
    assert_equal 2, json.dig("pagination", "total")
    assert_equal ["two"], json["data"].map { |m| m["content"] }

    get "/pocket_phone/api/v2/messages/#{handle}", headers: KEYS
    assert_equal "two", json.dig("data", "content")
  end

  test "an endpoint that is not faked says so" do
    api "/api/v2/contacts", { number: ALICE }

    assert_response :not_found
    assert_includes json["message"], "does not fake POST /api/v2/contacts"
  end
end
