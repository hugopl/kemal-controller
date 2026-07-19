require "./spec_helper"

private struct ChatController < Kemal::Controller
  @[WebSocket("/chat/:room")]
  def chat(room : String)
    socket.send("Welcome to #{room}!")
    socket.on_message do |message|
      socket.send("#{room}: #{message}")
    end
  end

  @[WebSocket("/greet", strip: true)]
  def greet(name : String = "World")
    socket.send("Hello, #{name}!")
  end

  @[WebSocket("/strip-specific/:room", strip: %i(name))]
  def strip_specific(room : String, name : String)
    socket.send("Room: '#{room}', Name: '#{name}'")
  end

  @[WebSocket("/secure", auth: true)]
  def secure
    socket.send("secret")
  end

  # Uses the delegated `send`/`on_message` methods directly instead of `socket.*`.
  @[WebSocket("/echo")]
  def echo
    send("ready")
    on_message do |message|
      send("echo: #{message}")
    end
  end

  # Regular HTTP route that touches the WebSocket-only `socket` getter.
  @[Get("/no-socket")]
  def no_socket
    socket.send("unreachable")
    "unreachable"
  end

  def authenticate! : Bool
    request.headers["Authorization"]? == "SecretToken"
  end
end

private def receive_message(client : HTTP::WebSocket) : String
  ch = Channel(String).new(1)
  client.on_message { |message| ch.send message }
  spawn { client.run }
  Fiber.yield
  ch.receive
end

describe "Kemal::Controller WebSocket support" do
  it "runs the method after the handshake and can send messages" do
    connect_websocket "/chat/general" do |client|
      receive_message(client).should eq("Welcome to general!")
    end
  end

  it "extracts URL parameters and handles on_message" do
    connect_websocket "/chat/crystal-lang" do |client|
      receive_message(client).should eq("Welcome to crystal-lang!")

      ch = Channel(String).new(1)
      client.on_message { |message| ch.send message }
      spawn { client.run }
      Fiber.yield

      client.send("hello")
      ch.receive.should eq("crystal-lang: hello")
    end
  end

  it "strips parameters when strip is set" do
    connect_websocket "/greet?name=%20Crystal%20" do |client|
      receive_message(client).should eq("Hello, Crystal!")
    end
  end

  it "uses default parameter values when the parameter is absent" do
    connect_websocket "/greet" do |client|
      receive_message(client).should eq("Hello, World!")
    end
  end

  it "strips only the specified parameters when strip is an array" do
    connect_websocket "/strip-specific/%20general%20?name=%20Crystal%20" do |client|
      receive_message(client).should eq("Room: ' general ', Name: 'Crystal'")
    end
  end

  it "delegates socket methods so they can be called directly" do
    connect_websocket "/echo" do |client|
      receive_message(client).should eq("ready")

      ch = Channel(String).new(1)
      client.on_message { |message| ch.send message }
      spawn { client.run }
      Fiber.yield

      client.send("hello")
      ch.receive.should eq("echo: hello")
    end
  end

  it "raises NilAssertionError when socket is accessed from a regular HTTP route" do
    expect_raises(NilAssertionError) do
      get("/no-socket")
    end
  end

  it "runs the method when authenticate! returns true" do
    connect_websocket "/secure", headers: HTTP::Headers{"Authorization" => "SecretToken"} do |client|
      receive_message(client).should eq("secret")
    end
  end

  it "closes the socket instead of running the method when authenticate! returns false" do
    connect_websocket "/secure" do |client|
      ch = Channel({HTTP::WebSocket::CloseCode, String}).new(1)
      client.on_close { |code, message| ch.send({code, message}) }
      spawn { client.run }

      code, message = ch.receive
      code.should eq(HTTP::WebSocket::CloseCode::PolicyViolation)
      message.should eq("Unauthorized")
    end
  end

  it "includes websocket routes in Kemal.print_routes" do
    color_setting = Colorize.enabled?
    Colorize.enabled = false
    output = String.build { |str| Kemal.print_routes(str) }
    output.should match(/WS\s+\/chat\/:room\s+ChatController#chat\(room : String\)/)
    output.should match(/WS\s+✂️\s+\/greet\s+ChatController#greet/)
    output.should match(/WS 🔒\s+\/secure\s+ChatController#secure/)
  ensure
    Colorize.enabled = color_setting.not_nil! # ameba:disable Lint/NotNil
  end
end
