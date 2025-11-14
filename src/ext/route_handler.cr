module Kemal
  class RouteHandler
    getter route_locations : Hash(Route, String) = Hash(Route, String).new

    def add_route(method : String, path : String, location : String = "?", &handler : HTTP::Server::Context -> _)
      route = Route.new(method, path, &handler)
      @route_locations[route] = location
      add_to_radix_tree(method, path, route)
    end
  end
end
