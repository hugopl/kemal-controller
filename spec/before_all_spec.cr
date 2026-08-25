require "./spec_helper"

# Records the filters/actions that ran during the last request, so the specs can assert on
# both which filters ran and in which order.
TRACE = [] of String

private struct FiltersController < Kemal::Controller
  # Two names in a single call...
  before_all :first, :second
  # ...and a second call, to check that calls accumulate instead of replacing each other.
  before_all :third

  @user : String? = nil

  @[Get("/filters/trace")]
  def trace
    TRACE << "action"
    @user.inspect
  end

  # Declared before `fourth` is defined, and before the `before_all fourth` below, to check
  # that a filter applies no matter where in the struct body it is declared.
  @[Get("/filters/late")]
  def late
    TRACE.join(",")
  end

  @[Get("/filters/status", status: 201)]
  def status_route
    "created"
  end

  @[Get("/filters/halt")]
  def halted
    TRACE << "action"
    "unreachable"
  end

  @[Get("/filters/cast/:ignored")]
  def cast(ignored : String, age : Int32)
    TRACE << "action"
    age.to_s
  end

  def cast_on_cast_error(ignored, age)
    TRACE << "on_cast_error"
    "cast error"
  end

  @[Get("/filters/secret", auth: true)]
  def secret
    TRACE << "action"
    "secret"
  end

  @[Get("/filters/action-halt")]
  def action_halt
    halt(410, "Gone")
    "unreachable"
  end

  @[WebSocket("/filters/socket")]
  def socket_route
    TRACE << "action"
    send(TRACE.join(","))
  end

  def authenticate! : Bool
    request.headers["Authorization"]? == "SecretToken"
  end

  # Bare name instead of a symbol.
  before_all fourth

  private def first
    TRACE << "first"
    @user = "crystal"
  end

  private def second
    TRACE << "second"
  end

  private def third
    TRACE << "third"
    case request.path
    when "/filters/halt", "/filters/cast/x" then halt(403, "Forbidden")
    when "/filters/status"                  then response.status_code = 202
    when "/filters/socket"                  then halt(403, "Nope") if request.query_params["stop"]?
    end
  end

  private def fourth
    TRACE << "fourth"
  end
end

# A second controller, to check that `FiltersController`'s filters stay put.
private struct UnfilteredController < Kemal::Controller
  @[Get("/unfiltered")]
  def index
    TRACE.join(",")
  end
end

private abstract struct BaseController < Kemal::Controller
  before_all :from_base

  private def from_base
    TRACE << "base"
  end
end

private struct ChildController < BaseController
  before_all :from_child

  @[Get("/child")]
  def index
    TRACE.join(",")
  end

  private def from_child
    TRACE << "child"
  end
end

private struct InheritOnlyController < BaseController
  @[Get("/inherit-only")]
  def index
    TRACE.join(",")
  end
end

private def trace_get(path, headers : HTTP::Headers? = nil)
  TRACE.clear
  get(path, headers)
end

describe "Kemal::Controller.before_all" do
  it "runs the filters before the action" do
    trace_get("/filters/trace")
    response.status_code.should eq(200)
    TRACE.should eq(%w(first second third fourth action))
  end

  it "lets a filter assign instance variables the action can read" do
    trace_get("/filters/trace")
    response.body.should eq(%("crystal"))
  end

  it "applies to routes declared before the before_all call" do
    trace_get("/filters/late")
    response.body.should eq("first,second,third,fourth")
  end

  it "does not run the filters of another controller" do
    trace_get("/unfiltered")
    response.body.should eq("")
  end

  it "skips the action when a filter halts" do
    trace_get("/filters/halt")
    response.status_code.should eq(403)
    response.body.should eq("Forbidden")
    TRACE.should eq(%w(first second third))
  end

  it "runs the filters after authenticate!" do
    trace_get("/filters/secret")
    response.status_code.should eq(401)
    TRACE.should be_empty

    trace_get("/filters/secret", HTTP::Headers{"Authorization" => "SecretToken"})
    response.status_code.should eq(200)
    TRACE.should eq(%w(first second third fourth action))
  end

  it "runs the filters before parameters are cast" do
    trace_get("/filters/cast/x?age=notanumber")
    response.status_code.should eq(403)
    response.body.should eq("Forbidden")
    TRACE.should eq(%w(first second third))
  end

  it "lets a filter override the route's status" do
    trace_get("/filters/status")
    response.status_code.should eq(202)
    response.body.should eq("created")
  end

  it "supports halt from inside an action" do
    trace_get("/filters/action-halt")
    response.status_code.should eq(410)
    response.body.should eq("Gone")
  end

  it "chains a parent controller's filters before the child's" do
    trace_get("/child")
    response.body.should eq("base,child")
  end

  it "inherits a parent controller's filters when the child declares none" do
    trace_get("/inherit-only")
    response.body.should eq("base")
  end

  it "runs the filters for websocket routes" do
    TRACE.clear
    connect_websocket "/filters/socket" do |client|
      ch = Channel(String).new(1)
      client.on_message { |message| ch.send message }
      spawn { client.run }
      Fiber.yield
      ch.receive.should eq("first,second,third,fourth,action")
    end
  end

  it "closes the socket when a filter halts a websocket route" do
    TRACE.clear
    connect_websocket "/filters/socket?stop=1" do |client|
      ch = Channel({HTTP::WebSocket::CloseCode, String}).new(1)
      client.on_close { |code, message| ch.send({code, message}) }
      spawn { client.run }

      code, message = ch.receive
      code.should eq(HTTP::WebSocket::CloseCode::PolicyViolation)
      message.should eq("Nope")
    end
    TRACE.should eq(%w(first second third))
  end
end
