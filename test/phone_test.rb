# frozen_string_literal: true

require "test_helper"

class PhoneTest < PocketPhone::TestCase
  setup do
    PocketPhone.config.webhook_url = WEBHOOK
    PocketPhone.config.signing_secret = "whsec"
  end

  test "an empty phone says so" do
    get "/pocket_phone"

    assert_response :success
    assert_includes response.body, "No conversations yet"
  end

  test "a text from the phone reaches the app as a signed receive webhook" do
    delivered = nil
    stub_request(:post, WEBHOOK).with { |request| delivered = request }

    message = text_from_phone("hi there")
    payload = JSON.parse(delivered.body)

    assert_equal "RECEIVED", payload["status"]
    assert_equal false, payload["is_outbound"]
    assert_equal "hi there", payload["content"]
    assert_equal ALICE, payload["from_number"]
    assert_equal LINE, payload["to_number"]
    assert_equal "iMessage", payload["service"]
    assert_equal message["handle"], payload["message_handle"]
    assert_match(/\A[0-9A-F-]{36}\z/, payload["message_handle"])

    timestamp, digest = delivered.headers["X-Sendblue-Signature"].match(/\At=(\d+),v1=(\h+)\z/).captures
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "whsec", "#{timestamp}.#{delivered.body}"), digest
    assert_equal "whsec", delivered.headers["Sb-Signing-Secret"]
    assert_equal 200, db.message(message["handle"])["webhooks"].last["status"]
  end

  test "a webhook the app turns away is shown as not delivered" do
    stub_request(:post, WEBHOOK).to_return(status: 401)
    text_from_phone("hi")

    get "/pocket_phone/conversations/#{conversation_id}"

    assert_includes response.body, "Not Delivered"
    assert_includes response.body, "the webhook answered 401"
  end

  test "with no webhook configured the message says why it went nowhere" do
    PocketPhone.config.webhook_url = nil
    message = text_from_phone("hi")

    assert_equal "no webhook_url configured", message["webhooks"].last["error"]
  end

  test "a webhook path is resolved against the server the phone is on" do
    PocketPhone.config.webhook_url = "/webhooks/sendblue/token"
    stub = stub_request(:post, "http://www.example.com/webhooks/sendblue/token")

    text_from_phone("hi")

    assert_requested stub
  end

  test "the webhook can be sent again" do
    stub = stub_request(:post, WEBHOOK)
    message = text_from_phone("hi")

    post "/pocket_phone/messages/#{message["handle"]}/redeliver"

    assert_requested stub, times: 2
  end

  test "an attachment travels as a media_url the app can fetch" do
    delivered = nil
    stub_request(:post, WEBHOOK).with { |request| delivered = JSON.parse(request.body) }
    post "/pocket_phone/conversations", params: { number: ALICE, line: LINE }
    file = Rack::Test::UploadedFile.new(StringIO.new("pixels"), "image/png", original_filename: "photo.PNG")

    post "/pocket_phone/conversations/#{conversation_id}/messages", params: { file: file }

    assert_response :no_content
    get URI.parse(delivered["media_url"]).path
    assert_equal "pixels", response.body
  end

  test "a group message says who sent it and who else is there" do
    delivered = nil
    stub_request(:post, WEBHOOK).with { |request| delivered = JSON.parse(request.body) }
    bob = "+15554445555"
    PocketPhone.store.write { |db| [ALICE, bob].each { |n| db.ensure_person(n) } }
    post "/pocket_phone/conversations", params: { group: 1, participants: [ALICE, bob], group_name: "Trip", line: LINE }
    group = db.conversations.values.last

    post "/pocket_phone/conversations/#{group["id"]}/messages", params: { content: "bob here", as: bob }

    assert_equal bob, delivered["from_number"]
    assert_equal group["id"], delivered["group_id"]
    assert_equal "Trip", delivered["group_display_name"]
    assert_equal [ALICE, bob], delivered["participants"]
    assert_equal "group", delivered["message_type"]
  end

  test "a tapback from the phone shows on the bubble and reaches the app as text" do
    delivered = []
    stub_request(:post, WEBHOOK).with { |request| delivered << JSON.parse(request.body) }
    send_text "ship it?"
    handle = json["message_handle"]

    post "/pocket_phone/messages/#{handle}/reactions", params: { reaction: "love" }

    assert_response :no_content
    assert_equal [{ "by" => ALICE, "reaction" => "love" }], db.message(handle)["reactions"]
    assert_equal ["Loved “ship it?”"], delivered.map { |payload| payload["content"] }

    post "/pocket_phone/messages/#{handle}/reactions", params: { reaction: "love" }
    assert_empty db.message(handle)["reactions"]
    assert_equal 1, delivered.size
  end

  test "typing on the phone is reported when a typing webhook is set" do
    PocketPhone.config.typing_webhook_url = "http://app.test/typing"
    delivered = nil
    stub_request(:post, "http://app.test/typing").with { |request| delivered = JSON.parse(request.body) }
    stub_request(:post, WEBHOOK)
    text_from_phone("hi")

    post "/pocket_phone/conversations/#{conversation_id}/typing", params: { is_typing: true }

    assert_equal({ "number" => ALICE, "is_typing" => true, "from_number" => LINE }, delivered.except("timestamp"))
  end

  test "the thread shows both sides, the typing dots and a read receipt" do
    stub_request(:post, WEBHOOK)
    text_from_phone("from the phone")
    send_text "from the app"
    api "/api/mark-read", { number: ALICE, from_number: LINE }
    api "/api/send-typing-indicator", { number: ALICE, from_number: LINE }

    get "/pocket_phone/conversations/#{conversation_id}"

    assert_response :success
    assert_includes response.body, "from the phone"
    assert_includes response.body, "from the app"
    assert_includes response.body, "pp-typing"
    assert_match(/Read \d+:\d\d/, response.body)
    assert_equal 0, db.conversations[conversation_id]["unread"]
  end

  test "the page polls for changes and is told when there are none" do
    stub_request(:post, WEBHOOK)
    text_from_phone("hi")

    get "/pocket_phone/state", params: { conversation: conversation_id }
    assert_response :success
    assert_includes json["messages"], "hi"
    assert_includes json["sidebar"], "Alice"

    get "/pocket_phone/state", params: { conversation: conversation_id, version: json["version"] }
    assert_response :no_content
  end

  test "people can be switched to Android and to failing" do
    post "/pocket_phone/conversations", params: { number: ALICE, name: "Alice", line: LINE }
    post "/pocket_phone/people", params: { number: ALICE, service: "SMS", outcome: "failed" }

    assert_equal({ "number" => ALICE, "name" => "Alice", "service" => "SMS", "outcome" => "failed" }, db.people[ALICE])
  end

  test "clearing forgets conversations and keeps people" do
    stub_request(:post, WEBHOOK)
    text_from_phone("hi")

    post "/pocket_phone/clear"

    assert_empty db.conversations
    assert_empty db.messages
    assert_equal "Alice", db.people.dig(ALICE, "name")
  end
end
