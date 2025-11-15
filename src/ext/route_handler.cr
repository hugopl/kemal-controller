module Kemal
  class RouteHandler
    alias RouteMetadata = NamedTuple(location: String, auth: Bool, strip: Bool)

    getter routes_metadata : Hash(Route, RouteMetadata) = Hash(Route, RouteMetadata).new

    def add_route(method : String, path : String, location : String = "?", auth : Bool = false, strip : Bool = false, &handler : HTTP::Server::Context -> _)
      route = Route.new(method, path, &handler)
      @routes_metadata[route] = {location: location, auth: auth, strip: strip}
      add_to_radix_tree(method, path, route)
    end
  end
end
