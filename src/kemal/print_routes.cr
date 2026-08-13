module Kemal
  # Prints all registered routes to the specified IO stream.
  #
  # Displays a formatted table of all routes registered in the application,
  # including HTTP method, path, controller/method name, and authentication/strip status.
  # Routes are sorted by path and method.
  #
  # ## Parameters
  #
  # - `io` : IO - The output stream to write to (default: STDOUT)
  #
  # ## Authentication and Stripping Indicators
  #
  # - 🔒 - Route requires authentication (auth: true)
  # - ✂️ - Route strips parameters (strip: true or strip: [...])
  #
  # ## Example
  #
  # ```
  # Kemal.print_routes
  # # Output:
  # #    GET 🔒     /area51                    TestController#area51()
  # #   POST        /array_of_named_tuples     TestController#array_of_named_tuples(items : Array(NamedTuple(name: String, age: Int32)))
  # #    GET    ✂️  /strip                     TestController#strip(something : String)
  # #
  # # 3 routes
  # ```
  #
  # ## Example with Command Line Option
  #
  # ```
  # Kemal.config.extra_options do |parser|
  #   parser.on("--routes", "Show all routes") do
  #     Kemal.print_routes
  #     exit(0)
  #   end
  # end
  # ```
  def self.print_routes(io : IO = STDOUT)
    routes_metadata = Kemal::RouteHandler::INSTANCE.routes_metadata
    ws_routes_metadata = Kemal::WebSocketHandler::INSTANCE.routes_metadata

    entries = routes_metadata.map { |route, metadata| {method: route.method, path: route.path, metadata: metadata} } +
              ws_routes_metadata.map { |socket, metadata| {method: "WS", path: socket.path, metadata: metadata} }
    entries.sort_by! { |entry| {entry[:path], entry[:method]} }

    if entries.empty?
      io.puts "No routes registered. Did you call Kemal.print_routes before requiring your controllers?"
      return
    end

    color_control_chars = Colorize.enabled? ? 10 : 0
    max_path_size : Int32 = entries.max_by(&.[:path].size)[:path].size + color_control_chars

    entries.each do |entry|
      metadata = entry[:metadata]
      auth = metadata[:auth] ? "🔒 " : "   "
      strip = metadata[:strip] ? "✂️ " : "   "

      if metadata[:location] =~ /\A(\w+)#(\w+)(.*)\z/
        class_name = $1
        method = $2
        args = $3
        location = "#{class_name.colorize.magenta}##{method.colorize.green}#{args}"
      end
      # Max width for an HTTP verb is 6 (DELETE)
      io.printf("%#{color_control_chars + 6}s #{auth}#{strip} %-#{max_path_size}s  %s\n", entry[:method].colorize.blue, entry[:path].colorize.cyan, location)
    end
    io.puts "\n#{entries.size} routes"
  end
end
