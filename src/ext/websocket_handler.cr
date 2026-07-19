module Kemal
  # :nodoc:
  class WebSocket
    getter path
  end

  # :nodoc:
  class WebSocketHandler
    alias WSRouteMetadata = NamedTuple(location: String, auth: Bool, strip: Bool)

    getter routes_metadata : Hash(WebSocket, WSRouteMetadata) = Hash(WebSocket, WSRouteMetadata).new

    # :nodoc:
    def add_route(path : String, location : String = "?", auth : Bool = false, strip : Bool = false, &handler : HTTP::WebSocket, HTTP::Server::Context ->)
      websocket = WebSocket.new(path, &handler)
      @routes_metadata[websocket] = {location: location, auth: auth, strip: strip}
      add_to_radix_tree(path, websocket)
    end
  end
end
