module Kemal
  def self.print_routes(io : IO = STDOUT)
    locations = Kemal::RouteHandler::INSTANCE.route_locations
    routes = locations.keys
    routes.sort_by! { |route| {route.path, route.method} }

    color_control_chars = Colorize.enabled? ? 10 : 0
    max_path_size : Int32 = routes.max_by(&.path.size).path.size + color_control_chars

    routes.each do |route|
      location = locations[route]
      if location =~ /\A(\w+)#(\w+)(.*)\z/
        class_name = $1
        method = $2
        args = $3
        location = "#{class_name.colorize.magenta}##{method.colorize.green}#{args}"
      end
      # Max width for an HTTP verb is 6 (DELETE)
      io.printf("%#{color_control_chars + 6}s  %-#{max_path_size}s  %s\n", route.method.colorize.blue, route.path.colorize.cyan, location)
    end
    io.puts "\n#{routes.size} routes"
  end
end
