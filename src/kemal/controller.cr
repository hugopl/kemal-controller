require "./from_www_form"
require "../ext/route_handler"
require "../ext/websocket_handler"
require "./print_routes"
require "./routes"

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
  # A parameter's external name (the one looked up in the request) can differ from the name used in the
  # method body by giving it an internal name, same as any other Crystal method. This is required when the
  # request field name is a reserved word, e.g. `def sign_in(next url : String)` maps the `next` request
  # parameter to the local variable `url`.
  #
  # ## Route annotation parameters
  #
  # - `path` : String - The URL path for the route (can include path parameters like `:id`)
  # - `auth` : Bool - If true, requires authentication via `authenticate!` method (default: false). Must be
  #   set explicitly when compiled with the `kemal_controller_require_auth` flag.
  # - `strip` : Bool | Array(Symbol) - If true, strips all parameters; if array, strips only specified parameters (default: false)
  # - `status` : Int32 - The HTTP status code to set before the action runs (default: 200). The action can still
  #   override it, e.g. by calling `error`.
  # - `as` : Symbol - The name of the route's URL helper in `Kemal::Routes` (default: `{controller}_{action}`)
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
  # ## Example with a custom status code
  #
  # ```
  # @[Post("/users", status: 201)]
  # def create(name : String)
  #   "Creating user with name: #{name}"
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
  # `authenticate!` can also take over the response itself, e.g. to redirect instead of
  # replying with 401:
  #
  # ```
  # def authenticate! : Bool
  #   return true if session.string?("user")
  #   redirect("/login")
  #   false
  # end
  # ```
  #
  # kemal-controller only sets the 401 status when `authenticate!` returns `false` and hasn't
  # already changed the response's status code or added a response header (e.g. via `redirect`,
  # `response.status_code =`, or setting a new response header directly). This still works when
  # `authenticate!` responds with the same status the response already had (e.g. it wants to
  # reply 200 with an `HX-Redirect` header for an htmx request), since a header was added.
  # Overwriting the *value* of a header that was already present, without changing the status or
  # adding a new header, isn't detected as taking over the response.
  #
  # ## Example with `before_all` Filters
  #
  # `before_all` registers methods to run before every route declared in the same controller
  # struct, in declaration order. Filters run after `authenticate!` and after the route's
  # `status:` has been applied, but before any parameter is parsed. Call `halt` from a filter
  # (or from an action) to abort the request.
  #
  # ```
  # struct AdminController < Kemal::Controller
  #   before_all :load_current_user
  #   before_all :require_admin
  #
  #   @[Get("/admin/dashboard")]
  #   def dashboard
  #     "Welcome, #{@user}"
  #   end
  #
  #   private def load_current_user
  #     @user = session.string?("user")
  #   end
  #
  #   private def require_admin
  #     halt(403, "Forbidden") unless @user == "admin"
  #   end
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
  #
  # ## Example with a Cast-Error Hook
  #
  # By default, if a required parameter is missing, or is present but fails to
  # cast to its declared type (e.g. `age=foo` for `age : Int32`),
  # `Kemal::ParamError` propagates uncaught. Define an opt-in
  # `{action}_on_cast_error` method, with the same parameters as the action but
  # with no type restrictions, to render a response instead:
  #
  # ```
  # @[Post("/users")]
  # def create(name : String, age : Int32)
  #   "Creating user with name: #{name}, age: #{age}"
  # end
  #
  # def create_on_cast_error(name, age)
  #   # Both `name` and `age` are unions with `Kemal::ParamError`, since
  #   # either can be missing, and `age` can also fail to cast.
  #   if age.is_a?(Kemal::ParamError)
  #     age.reason.missing? ? "age is required" : "age: #{age.value.inspect} is not a number"
  #   else
  #     "age was fine: #{age}"
  #   end
  # end
  # ```
  abstract struct Controller
    {% for type in %w(Get Post Put Patch Delete Head Options) %}
      # Annotation to define a {{type.id}} route for a controller method.
      #
      # ## Parameters
      #
      # - `path` : String - The URL path for the route (can include path parameters like `:id`)
      # - `auth` : Bool - If true, requires authentication via `authenticate!` method (default: false). Must be
      #   set explicitly when compiled with the `kemal_controller_require_auth` flag.
      # - `strip` : Bool | Array(Symbol) - If true, strips all parameters; if array, strips only specified parameters (default: false)
      # - `status` : Int32 - The HTTP status code to set before the action runs (default: 200)
      # - `as` : Symbol - The name of the route's URL helper in `Kemal::Routes` (default: `{controller}_{action}`)
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
    # - `auth` : Bool - If true, requires authentication via `authenticate!` method (default: false). Must be
    #   set explicitly when compiled with the `kemal_controller_require_auth` flag.
    # - `strip` : Bool | Array(Symbol) - If true, strips all parameters; if array, strips only specified parameters (default: false)
    # - `as` : Symbol - The name of the route's URL helper in `Kemal::Routes` (default: `{controller}_{action}`)
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

    # Raised by `halt` to abort the current request.
    #
    # The generated route handler rescues it, applies `status_code` to the response and
    # returns `response` as the body. WebSocket routes close the socket with
    # `HTTP::WebSocket::CloseCode::PolicyViolation` instead, using `response` as the reason.
    #
    # Raise it directly when `halt` isn't in scope, e.g. from a helper defined in an
    # included module rather than in the controller itself:
    #
    # ```
    # raise Kemal::Controller::Halt.new(403, "Forbidden")
    # ```
    class Halt < Exception
      # The HTTP status code to respond with.
      getter status_code : Int32

      # The response body, or the WebSocket close reason.
      getter response : String

      def initialize(status : HTTP::Status | Int32 = 200, @response : String = "")
        @status_code = status.to_i
        super("Halted with status #{@status_code}")
      end
    end

    # Aborts the current request by raising `Halt`.
    #
    # Usable from `before_all` filters, from actions, and from any other method of the
    # controller. The action (and any remaining filters) are skipped.
    #
    # NOTE: This shadows Kemal's own top-level `halt` macro inside controllers, and takes no
    # `env`/context argument. Kemal's version expands to `next`, so it never worked inside a
    # controller method to begin with.
    #
    # ## Example
    #
    # ```
    # before_all :ensure_setup
    #
    # def ensure_setup
    #   halt(403, "Forbidden") unless Config.ready?
    # end
    # ```
    macro halt(status_code = 200, response = "")
      raise ::Kemal::Controller::Halt.new({{ status_code }}, {{ response }})
    end

    # Registers methods to run before every route declared in this controller.
    #
    # Accepts symbols, bare names or strings, and may be called more than once; filters run
    # in declaration order, and only for routes declared in this controller struct. It can
    # appear anywhere in the struct body, before or after the routes it applies to.
    #
    # Filters run after `authenticate!` (for `auth: true` routes) and after the route's
    # `status:` has been applied, but before any parameter is parsed or cast. Their return
    # value is ignored; call `halt` to abort the request.
    #
    # Since a controller is a struct that is instantiated per request, a filter can assign
    # instance variables for the action to read.
    #
    # ## Example
    #
    # ```
    # struct PostsController < Kemal::Controller
    #   before_all :load_current_user
    #   before_all :require_admin
    #
    #   @[Get("/posts")]
    #   def index
    #     "Hello #{@user}"
    #   end
    #
    #   private def load_current_user
    #     @user = session.string?("user")
    #   end
    #
    #   private def require_admin
    #     halt(403, "Forbidden") unless @user == "admin"
    #   end
    # end
    # ```
    macro before_all(*names)
      {% for name in names %}
        # :nodoc:
        @[AlwaysInline]
        def __before_all_{{ name.id }}
          {{ name.id }}
        end
      {% end %}
    end

    # Runs this controller's `before_all` filters.
    #
    # No-op by default; controllers that call `before_all` get an override generated for them.
    #
    # :nodoc:
    @[AlwaysInline]
    def _run_before_all_filters : Nil
    end

    macro inherited
      macro method_added(method)
        {% verbatim do %}
          {% for http_verb in [Get, Post, Put, Patch, Delete, Head, Options] %}
            {% ann = method.annotation(http_verb.resolve) %}
            {% if ann %}
              {% verb = http_verb.stringify.split("::").last.upcase %}
              {% if flag?(:kemal_controller_require_auth) && ann[:auth] == nil %}
                {% raise "#{@type.name}##{method.name}'s '#{verb.id}' route annotation is missing an explicit " +
                         "'auth:' key. Add 'auth: true' if the route must be authenticated, or 'auth: false' " +
                         "to mark it intentionally public. Required because the 'kemal_controller_require_auth' " +
                         "compile-time flag is enabled." %}
              {% end %}
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
                  %status_before_auth = ctx.response.status_code
                  %header_count_before_auth = ctx.response.headers.size
                  if !%controller.authenticate!
                    if ctx.response.status_code == %status_before_auth && ctx.response.headers.size == %header_count_before_auth
                      ctx.response.status_code = 401
                    end
                    next
                  end
                {% end %}

                ctx.response.status_code = {{ ann[:status] || 200 }}

                begin
                  %controller._run_before_all_filters

                  %params = Kemal.parse_www_form(ctx)
                  %any_cast_error = false
                  {% for param in method.args %}
                    {% if !param.restriction %}
                      {% raise "Parameter '#{param.name}' in #{@type.name}##{method.name} must have an explicit type annotation, e.g. '#{param.name} : String'." %}
                    {% end %}
                    {% type = param.restriction.resolve %}
                    {% if param.default_value %}
                      {{ param.internal_name.id }} = begin
                        {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                      rescue ex : Kemal::ParamError
                        if ex.reason.missing?
                          {{ param.default_value }}
                        else
                          %any_cast_error = true
                          ex
                        end
                      end
                    {% else %}
                      {{ param.internal_name.id }} = begin
                        {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                      rescue ex : Kemal::ParamError
                        %any_cast_error = true
                        ex
                      end
                    {% end %}

                    {% strip = ann[:strip] %}
                    {% if strip && (strip == true || strip.includes?(param.internal_name.id.symbolize)) %}
                      {{ param.internal_name.id }} = {{ param.internal_name.id }}.strip if {{ param.internal_name.id }}.responds_to?(:strip)
                    {% end %}
                  {% end %}

                  if %any_cast_error
                    %controller.{{method.name.id}}_on_cast_error({% for param in method.args %}{{ param.internal_name.id }}, {% end %})
                  else
                    %controller.{{method.name.id}}({% for param in method.args %}{{ param.internal_name.id }}.as({{ param.restriction.resolve }}), {% end %})
                  end
                rescue %halt : Kemal::Controller::Halt
                  ctx.response.status_code = %halt.status_code
                  %halt.response
                end
              end
            {% end %}
          {% end %}

          {% ws_ann = method.annotation(WebSocket) %}
          {% if ws_ann %}
            {% if flag?(:kemal_controller_require_auth) && ws_ann[:auth] == nil %}
              {% raise "#{@type.name}##{method.name}'s 'WebSocket' route annotation is missing an explicit " +
                       "'auth:' key. Add 'auth: true' if the connection must be authenticated, or 'auth: false' " +
                       "to mark it intentionally public. Required because the 'kemal_controller_require_auth' " +
                       "compile-time flag is enabled." %}
            {% end %}
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

              begin
                %controller._run_before_all_filters

                %params = Kemal.parse_www_form(ctx)
                {% for param in method.args %}
                  {% if !param.restriction %}
                    {% raise "Parameter '#{param.name}' in #{@type.name}##{method.name} must have an explicit type annotation, e.g. '#{param.name} : String'." %}
                  {% end %}
                  {% type = param.restriction.resolve %}
                  {% if param.default_value %}
                    {{ param.internal_name.id }} = begin
                      {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                    rescue ex : Kemal::ParamError
                      raise ex unless ex.reason.missing?
                      {{ param.default_value }}
                    end
                  {% else %}
                    {{ param.internal_name.id }} = {{ type }}.from_www_form({{ param.name.stringify }}, %params)
                  {% end %}

                  {% strip = ws_ann[:strip] %}
                  {% if strip && (strip == true || strip.includes?(param.internal_name.id.symbolize)) %}
                    {{ param.internal_name.id }} = {{ param.internal_name.id }}.strip if {{ param.internal_name.id }}.responds_to?(:strip)
                  {% end %}
                {% end %}

                %controller.{{method.name.id}}({% for param in method.args %}{{ param.internal_name.id }}, {% end %})
              rescue %halt : Kemal::Controller::Halt
                %socket.close(HTTP::WebSocket::CloseCode::PolicyViolation, %halt.response.presence || "Halted")
              end
            end
          {% end %}
        {% end %}
      end

      macro finished
        {% verbatim do %}
          {% for method in @type.methods %}
            {% for http_verb in [Get, Post, Put, Patch, Delete, Head, Options] %}
              {% ann = method.annotation(http_verb.resolve) %}
              {% if ann %}
                {% hook_name = "#{method.name}_on_cast_error" %}
                {% unless @type.has_method?(hook_name) %}
                  # Default `_on_cast_error` hook: re-raises the first parameter that
                  # failed to cast, in declared order, so behaviour is unchanged for
                  # controllers that don't define their own hook.
                  @[AlwaysInline]
                  def {{ hook_name.id }}({% for param in method.args %}{{ param.internal_name.id }}, {% end %})
                    {% for param in method.args %}
                      raise {{ param.internal_name.id }} if {{ param.internal_name.id }}.is_a?(Kemal::ParamError)
                    {% end %}
                  end
                {% end %}
              {% end %}
            {% end %}
          {% end %}

          {% filters = @type.methods.select { |m| m.name.starts_with?("__before_all_") } %}
          {% unless filters.empty? %}
            # Runs this controller's `before_all` filters, in declaration order.
            #
            # `super` first, so an abstract parent controller's filters run before
            # the ones declared here.
            #
            # :nodoc:
            def _run_before_all_filters : Nil
              super
              {% for filter in filters %}
                {{ filter.name.id }}
              {% end %}
            end
          {% end %}
        {% end %}
      end
    end

    # Generates the `Kemal::Routes` URL helpers, once every controller is known.
    macro finished
      Kemal.define_route_helpers
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
