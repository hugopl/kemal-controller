module Kemal
  def self.print_routes(io : IO = STDOUT)
    routes_metadata = Kemal::RouteHandler::INSTANCE.routes_metadata
    routes = routes_metadata.keys
    routes.sort_by! { |route| {route.path, route.method} }

    color_control_chars = Colorize.enabled? ? 10 : 0
    max_path_size : Int32 = routes.max_by(&.path.size).path.size + color_control_chars

    routes.each do |route|
      route_metadata = routes_metadata[route]
      auth = route_metadata[:auth] ? "🔒 " : "   "
      strip = route_metadata[:strip] ? "✂️ " : "  "

      if route_metadata[:location] =~ /\A(\w+)#(\w+)(.*)\z/
        class_name = $1
        method = $2
        args = $3
        location = "#{class_name.colorize.magenta}##{method.colorize.green}#{args}"
      end
      # Max width for an HTTP verb is 6 (DELETE)
      io.printf("%#{color_control_chars + 6}s #{auth}#{strip} %-#{max_path_size}s  %s\n", route.method.colorize.blue, route.path.colorize.cyan, location)
    end
    io.puts "\n#{routes.size} routes"
  end
end
