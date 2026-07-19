require "./from_www_form"
require "../ext/route_handler"
require "../ext/websocket_handler"
require "./print_routes"

module Kemal
  # Abstract controller class that provides a structured way to define HTTP endpoints.
  #
  # Controllers are structs, so the overhead is minimal and you can still use all
  # Kemal features. Method parameters automatically map to GET/POST/URL parameters
  # with type-safe conversion.
  #
  # ## Example
  #
  # ```
  # struct UsersController < Kemal::Controller
  #   @[Get("/users")]
  #   def index
  #     "Listing all users"
  #   end
  #
  #   @[Get("/users/:id")]
  #   def show(id : Int32)
  #     "Showing user with ID: #{id}"
  #   end
  #
  #   @[Post("/users")]
  #   def create(name : String, age : Int32, description : String?)
  #     "Creating user with name: #{name}, age: #{age}, description: #{description}"
  #   end
  # end
  # ```
  #
  # ## Supported Parameter Types
  #
  # - String
  # - Int32, Int64
  # - Bool
  # - Array (with nested support)
  # - NamedTuple (with nested support)
  # - Nilable versions of the above
  #
  # ## Parameter Mapping
  #
  # - `name=John` becomes `name : String`
  # - `item[foo]=bar` becomes `item : NamedTuple(foo: String)`
  # - `items[]=1&items[]=2` becomes `items : Array(Int32)`
  # - `items[][id]=1&items[][quantity]=2` becomes `items : Array(NamedTuple(id: Int32, quantity: Int32))`
  #
  # ## Route annotation parameters
  #
  # - `path` : String - The URL path for the route (can include path parameters like `:id`)
  # - `auth` : Bool - If true, requires authentication via `authenticate!` method (default: false)
  # - `strip` : Bool | Array(Symbol) - If true, strips all parameters; if array, strips only specified parameters (default: false)
  #
  # ## Example
  #
  # ```
  # @[Get("/users/:id")]
  # def show(id : Int32)
  #   "User #{id}"
  # end
  # ```
  #
  # ## Example with Authentication
  #
  # ```
  # @[Get("/admin/dashboard", auth: true)]
  # def dashboard
  #   "Admin Dashboard"
  # end
  #
  # def authenticate! : Bool
  #   # Return false to halt with 401 status
  #   request.headers["Authorization"]? == "SecretToken"
  # end
  # ```
  #
  # ## Example with Parameter Stripping
  #
  # ```
  # @[Post("/users", strip: true)]
  # def create(name : String, description : String?)
  #   # name and description will have leading/trailing whitespace removed
  # end
  #
  # @[Post("/login", strip: [:email])]
  # def login(email : String, password : String)
  #   # Only email will be stripped, password remains unchanged
  # end
  # ```
  abstract struct Controller
    {% for type in %w(Get Post Put Patch Delete Head Options) %}
      # Annotation to define a {{type.id}} route for a controller method.
      #
      # ## Parameters
      #
      # - `path` : String - The URL path for the route (can include path parameters like `:id`)
      # - `auth` : Bool - If true, requires authentication via `authenticate!` method (default: false)
      # - `strip` : Bool | Array(Symbol) - If true, strips all parameters; if array, strips only specified parameters (default: false)
      #
      # See `Kemal::Controller` documentation for usage examples.
      annotation {{type.id}}
      end
    {% end %}

    # Annotation to define a WebSocket route for a controller method.
    #
    # The method is called once, right after the WebSocket handshake completes. Use the
    # `socket` getter inside the method to register `on_message`, `on_close`, etc. handlers.
    # Method parameters are extracted from the handshake request the same way `Get` does,
    # i.e. from URL/query parameters.
    #
    # ## Parameters
    #
    # - `path` : String - The URL path for the route (can include path parameters like `:id`)
    # - `auth` : Bool - If true, requires authentication via `authenticate!` method (default: false)
    # - `strip` : Bool | Array(Symbol) - If true, strips all parameters; if array, strips only specified parameters (default: false)
    #
    # NOTE: Unlike HTTP routes, by the time a `@[WebSocket]` method runs the handshake response
    # has already been sent, so `auth: true` can't reply with a 401, it closes the socket instead
    # (`HTTP::WebSocket::CloseCode::PolicyViolation`) when `authenticate!` returns false.
    #
    # ## Example
    #
    # ```
    # @[WebSocket("/chat/:room")]
    # def chat(room : String)
    #   socket.send("Welcome to #{room}!")
    #   socket.on_message do |message|
    #     socket.send("#{room}: #{message}")
    #   end
    # end
    # ```
    annotation WebSocket
    end

    # Type alias for validation errors stored as field name to error message mappings.
    #
    # Used by the `error` methods to store validation errors that occurred during
    # request processing.
    alias Errors = Hash(String, String)

    macro inherited
      macro method_added(method)
        {% verbatim do %}
          {% for http_verb in [Get, Post, Put, Patch, Delete, Head, Options] %}
            {% ann = method.annotation(http_verb.resolve) %}
            {% if ann %}
              {% verb = http_verb.stringify.split("::").last.upcase %}
              {% url = ann[0] %}
              Kemal::RouteHandler::INSTANCE.add_route({{ verb }}, {{ url }},
                                                      {{ "#{@type.id}##{method.name}(#{method.args.join(", ").id})" }},
                                                       {{ !!ann[:auth] }}, {{ !!ann[:strip] }}) do |ctx|
                Log.debug do
                  "Processing request for #{{{verb}}} #{ctx.request.path} " \
                  "through #{{{ @type.name.stringify }}}##{{{ method.name.stringify }}}".colorize(:cyan)
                end

                %controller = {{ @type.id }}.new(ctx)

                {% if ann[:auth] == true %}
                  if !%controller.authenticate!
                    ctx.response.status_code = 401
                    next
                  end
                {% end %}

                ctx.response.status_code = {{ verb.id.symbolize }} == :POST ? 201 : 200

                %params = Kemal.parse_www_form(ctx)
                {% for param in method.args %}
                  {% if !param.restriction %}
                    {% raise "Parameter '#{param.name}' in #{@type.name}##{method.name} must have an explicit type annotation, e.g. '#{param.name} : String'." %}
                  {% end %}
                  {% type = param.restriction.resolve %}
                  {% if param.default_value %}
                    {{ param.name.id }} = begin
                      {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                    rescue Kemal::MissingParameterError
                      {{ param.default_value }}
                    end
                  {% else %}
                    {{ param.name.id }} = {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                  {% end %}

                  {% strip = ann[:strip] %}
                  {% if strip && (strip == true || strip.includes?(param.name.id.symbolize)) %}
                    {{ param.name.id }} = {{ param.name.id }}.strip if {{ param.name.id }}.responds_to?(:strip)
                  {% end %}
                {% end %}

                %controller.{{method.name.id}}({% for param in method.args %}{{ param.name.id }}, {% end %})
              end
            {% end %}
          {% end %}

          {% ws_ann = method.annotation(WebSocket) %}
          {% if ws_ann %}
            {% url = ws_ann[0] %}
            Kemal::WebSocketHandler::INSTANCE.add_route({{ url }},
                                                    {{ "#{@type.id}##{method.name}(#{method.args.join(", ").id})" }},
                                                     {{ !!ws_ann[:auth] }}, {{ !!ws_ann[:strip] }}) do |%socket, ctx|
              Log.debug do
                "Processing websocket request for #{ctx.request.path} " \
                "through #{{{ @type.name.stringify }}}##{{{ method.name.stringify }}}".colorize(:cyan)
              end

              %controller = {{ @type.id }}.new(ctx, %socket)

              {% if ws_ann[:auth] == true %}
                if !%controller.authenticate!
                  %socket.close(HTTP::WebSocket::CloseCode::PolicyViolation, "Unauthorized")
                  next
                end
              {% end %}

              %params = Kemal.parse_www_form(ctx)
              {% for param in method.args %}
                {% if !param.restriction %}
                  {% raise "Parameter '#{param.name}' in #{@type.name}##{method.name} must have an explicit type annotation, e.g. '#{param.name} : String'." %}
                {% end %}
                {% type = param.restriction.resolve %}
                {% if param.default_value %}
                  {{ param.name.id }} = begin
                    {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                  rescue Kemal::MissingParameterError
                    {{ param.default_value }}
                  end
                {% else %}
                  {{ param.name.id }} = {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                {% end %}

                {% strip = ws_ann[:strip] %}
                {% if strip && (strip == true || strip.includes?(param.name.id.symbolize)) %}
                  {{ param.name.id }} = {{ param.name.id }}.strip if {{ param.name.id }}.responds_to?(:strip)
                {% end %}
              {% end %}

              %controller.{{method.name.id}}({% for param in method.args %}{{ param.name.id }}, {% end %})
            end
          {% end %}
        {% end %}
      end
    end

    # The HTTP server context for the current request.
    #
    # Provides access to the underlying HTTP::Server::Context which contains
    # the request and response objects.
    getter context : HTTP::Server::Context

    # Hash of validation errors that occurred during request processing.
    #
    # Maps field names to error messages. Use `error` methods to add errors
    # and `has_error?`, `error_for?`, `error_for_base` to check for errors.
    #
    # Returns `nil` if no errors have been recorded.
    getter errors : Errors?

    # Delegates to the request object from the context.
    #
    # Provides direct access to the HTTP::Request for the current request.
    delegate request, to: @context

    # Delegates to the response object from the context.
    #
    # Provides direct access to the HTTP::Response for the current request.
    delegate response, to: @context

    # Delegates to the session object from the context.
    #
    # Provides access to the Kemal session for the current request.
    delegate session, to: @context

    # Delegates to the redirect method from the context.
    #
    # Redirects the request to another URL.
    #
    # ## Example
    #
    # ```
    # redirect("/login")
    # ```
    delegate redirect, to: @context

    # The WebSocket connection for the current request.
    #
    # Only available inside methods annotated with `@[WebSocket]`. Raises
    # `NilAssertionError` if accessed from a regular HTTP route handler.
    getter! socket : HTTP::WebSocket

    # Delegates the non-block WebSocket methods to the `socket` getter.
    #
    # Lets `@[WebSocket]` methods call `send`, `close`, etc. directly instead of
    # going through `socket`. Like `socket`, these raise `NilAssertionError` if
    # called from a regular HTTP route handler.
    delegate close, ping, pong, send, to: socket

    # Forwards the block-accepting WebSocket methods to the `socket` getter.
    #
    # These can't be handled by `delegate` because the target methods capture their
    # block (`&`), and the wrapper `delegate` generates would `yield` from inside a
    # captured block, which doesn't compile. Like `socket`, they raise
    # `NilAssertionError` when called from a regular HTTP route handler.
    def on_message(&block : String ->) : Proc(String, Nil)
      socket.on_message(&block)
    end

    # :ditto:
    def on_binary(&block : Bytes ->) : Proc(Bytes, Nil)
      socket.on_binary(&block)
    end

    # :ditto:
    def on_close(&block : HTTP::WebSocket::CloseCode, String ->) : Proc(HTTP::WebSocket::CloseCode, String, Nil)
      socket.on_close(&block)
    end

    # :ditto:
    def on_ping(&block : String ->)
      socket.on_ping(&block)
    end

    # :ditto:
    def on_pong(&block : String ->)
      socket.on_pong(&block)
    end

    # :ditto:
    def stream(binary = true, frame_size = 1024, &)
      socket.stream(binary: binary, frame_size: frame_size) do |io|
        yield io
      end
    end

    # Initializes a new controller instance.
    #
    # This is called automatically by the framework when processing a request.
    # You typically don't need to call this directly.
    #
    # ## Parameters
    #
    # - `context` : HTTP::Server::Context - The HTTP server context for the request
    # - `socket` : HTTP::WebSocket? - The WebSocket connection, only set for `@[WebSocket]` methods
    def initialize(@context : HTTP::Server::Context, @socket : HTTP::WebSocket? = nil)
    end

    # Adds a general error message to the base error field.
    #
    # This is useful for errors that don't belong to a specific field.
    # Sets the response status to 400 (Bad Request) for GET/HEAD/OPTIONS requests
    # or 422 (Unprocessable Entity) for POST/PUT/PATCH/DELETE requests.
    #
    # ## Parameters
    #
    # - `message` : String - The error message to add
    #
    # ## Example
    #
    # ```
    # def create(name : String)
    #   if name.empty?
    #     error("Name cannot be empty")
    #     render("src/views/users/new.ecr")
    #     return
    #   end
    # end
    # ```
    def error(message : String)
      error("base", message)
    end

    # Adds a field-specific error message.
    #
    # Stores an error message for a specific field and sets the appropriate HTTP status code.
    # If no custom status is provided, sets 400 (Bad Request) for GET/HEAD/OPTIONS requests
    # or 422 (Unprocessable Entity) for POST/PUT/PATCH/DELETE requests.
    #
    # ## Parameters
    #
    # - `field` : String - The name of the field that has an error
    # - `message` : String - The error message for this field
    # - `status` : HTTP::Status? - Optional custom HTTP status code (default: nil)
    #
    # ## Example
    #
    # ```
    # def create(email : String, password : String)
    #   if !email.includes?("@")
    #     error("email", "Invalid email format")
    #     render("src/views/users/new.ecr")
    #     return
    #   end
    #   if password.size < 8
    #     error("password", "Password must be at least 8 characters", HTTP::Status::BAD_REQUEST)
    #     render("src/views/users/new.ecr")
    #     return
    #   end
    # end
    # ```
    def error(field, message, status : HTTP::Status? = nil)
      errors = @errors ||= {} of String => String
      errors[field] = message
      status ||= case request.method
                 when "GET", "HEAD", "OPTIONS"         then HTTP::Status::BAD_REQUEST
                 when "POST", "PUT", "PATCH", "DELETE" then HTTP::Status::UNPROCESSABLE_ENTITY
                 else
                   Log.fatal { "Unknown HTTP method: #{request.method}" }
                   HTTP::Status::INTERNAL_SERVER_ERROR
                 end
      response.status = status
    end

    # Checks if any errors have been recorded.
    #
    # Returns `true` if there are one or more validation errors, `false` otherwise.
    #
    # ## Example
    #
    # ```
    # def create(name : String, email : String)
    #   error("name", "Name is required") if name.empty?
    #   error("email", "Email is required") if email.empty?
    #
    #   if has_error?
    #     render("src/views/users/new.ecr")
    #     return
    #   end
    #
    #   # Process the valid data
    # end
    # ```
    def has_error? : Bool
      errors = @errors
      !errors.nil? && !errors.empty?
    end

    # Returns the error message for the "base" field.
    #
    # The "base" field is used for general errors that don't belong to a specific field.
    # Returns `nil` if there is no base error.
    #
    # ## Example
    #
    # ```
    # def update
    #   error("Something went wrong")
    #   if msg = error_for_base
    #     render("src/views/error.ecr")
    #     return
    #   end
    # end
    # ```
    def error_for_base : String?
      @errors.try(&.["base"]?)
    end

    # Returns the error message for a specific field.
    #
    # Returns `nil` if there is no error for the specified field.
    #
    # ## Parameters
    #
    # - `field` : String - The name of the field to check for errors
    #
    # ## Example
    #
    # ```
    # def create(email : String)
    #   error("email", "Invalid email") unless email.includes?("@")
    #
    #   if msg = error_for?("email")
    #     render("src/views/users/new.ecr")
    #     return
    #   end
    # end
    # ```
    def error_for?(field : String) : String?
      @errors.try(&.[field]?)
    end
  end
end
