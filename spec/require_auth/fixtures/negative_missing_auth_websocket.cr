require "../../../src/kemal-controller"

private struct NegativeWebSocketController < Kemal::Controller
  @[WebSocket("/chat")]
  def chat
  end
end
