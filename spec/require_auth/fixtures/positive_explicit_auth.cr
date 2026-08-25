require "../../../src/kemal-controller"

private struct PositiveController < Kemal::Controller
  @[Get("/public", auth: false)]
  def public_route
    "public"
  end

  @[Get("/private", auth: true)]
  def private_route
    "private"
  end

  @[Post("/mixed", auth: false, strip: true, status: 201, as: mixed_create)]
  def mixed(name : String)
    name
  end

  @[WebSocket("/ws", auth: false)]
  def ws
  end

  def authenticate! : Bool
    true
  end
end
