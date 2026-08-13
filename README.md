# kemal-controller

Kemal is awesome, but sometimes you need (or just want) a bit more structure in
your web applications, kemal-controller is here to help you with that by
providing a simple way to declare all your endpoints into controller classes
where the method parameters will map to GET/PATCH/.../POST/URL parameters automatically.

Online documentation can be found at: <https://hugopl.github.io/kemal-controller/>.

Controllers are structs, so the overhead is minimal and you can still use all
Kemal features as you would normally do.

```Crystal
struct UsersController < Kemal::Controller
  @[Get("/users")]
  def index
    "Listing all users"
  end

  @[Get("/users/:id")]
  def show(id : Int32)
    "Showing user with ID: #{id}"
  end

  @[Post("/users")]
  def create(name : String, age : Int32, description : String?))
    "Creating user with name: #{name}, age: #{age} and description: #{description}"
  end
end
```

Kemal-controller also supports arrays and named tuples in arguments, so you get a type safe way to handle the endpoint parameters.

```Crystal
struct ProductsController < Kemal::Controller
  @[Get("/products")]
  def filter(categories : Array(String), price_range : NamedTuple(min : Float64, max : Float64))
    "Filtering products in categories: #{categories.join(", ")} with price between #{price_range[:min]} and #{price_range[:max]}"
  end
end
```
It supports nested named tuples/arrays in any combination as well.

```Crystal
struct OrdersController < Kemal::Controller
  @[Post("/orders")]
  def create(items : Array(NamedTuple(id : Int32, quantity : Int32)),
             shipping_address : NamedTuple(street : String, city : String, zip : String))
    "Creating order with items: #{items.inspect} to be shipped to #{shipping_address[:street]}, #{shipping_address[:city]}, #{shipping_address[:zip]}"
  end
end
```

Default values are supported — the parameter must have an explicit type annotation:

```Crystal
struct UsersController < Kemal::Controller
  @[Get("/greet")]
  def greet(name : String = "World", times : Int32 = 1)
    "Hello, #{name}! " * times
  end
end
```

If the parameter is absent from the request the default value is used. Explicit type annotations are required; omitting the type is a compile-time error.

### How the parameters are mapped?

Kemal-controller interprets the form keys almost like Rails does:

- `item[foo]=bar` becomes `item : NamedTuple(foo : String)`
- `items[]=1&items[]=2` becomes `items : Array(Int32)`
- `items[][id]=1&items[][quantity]=2&items[][id]=3&items[][quantity]=4` becomes `items : Array(NamedTuple(id : Int32, quantity : Int32))`
- `name=John` becomes `name : String`

### Supported types

- String
- Int32
- Int64
- Enums
- Bool
- NamedTuple (with nested support)
- Array (with nested support)
- Nilable versions of the above types

More types may be added in the future, feel free to open an issue or a PR if you need something specific.

### Error handling

`Kemal::ParamError` is raised for bad request parameters — either a
required (non-nilable, no default) parameter that was not present in the
request, or one that was present but couldn't be coerced to the declared type
(e.g. `"foo"` for an `Int32`, an unrecognised enum member, or an invalid
boolean literal). Its `reason` getter (a `Kemal::ParamError::Reason` enum)
tells you which: `Missing` or `CastError`. `param_name` is always set;
`expected_type` and `value` are only set when `reason` is `CastError`.

It inherits from `Exception`, so you can handle it with Kemal's
exception-specific error handler:

```Crystal
error Kemal::ParamError do |env, ex|
  env.response.status_code = ex.reason.missing? ? 400 : 422
  ex.message
end
```

See "Handling cast errors per-action" below for opting a single action into
recovering from these instead of letting them propagate.

### Handling cast errors per-action

If you'd rather recover from a bad parameter inside a specific action — to
re-render a form with a per-field error, for instance — define a sibling
`{action}_on_cast_error` method with the same parameter names, in the same
order, but with no type restrictions:

```Crystal
struct UsersController < Kemal::Controller
  @[Post("/users")]
  def create(name : String, age : Int32)
    "Creating user with name: #{name}, age: #{age}"
  end

  def create_on_cast_error(name, age)
    # Both `name` and `age` are unions with `Kemal::ParamError`, since either
    # can be missing, and `age` can also fail to cast.
    if age.is_a?(Kemal::ParamError)
      age.reason.missing? ? "age is required" : "age: #{age.value.inspect} is not a number"
    else
      "age was fine: #{age}"
    end
  end
end
```

When `create` runs, every parameter is cast independently — a bad `age`
doesn't stop `name` from being cast too. If any parameter fails, `create` is
skipped entirely and `create_on_cast_error` is called instead, receiving each
parameter as either its successfully cast value or the `Kemal::ParamError`
for that specific parameter. If none fail, `create` runs as usual with fully
typed, narrowed parameters.

This is entirely opt-in: a controller that never defines `_on_cast_error`
methods keeps today's behaviour of letting `Kemal::ParamError` propagate.

### Enums

Enums are supported as method parameters as well, anything accepted by `Enum.new` or `Enum.parse` is recognized.

### Stripping parameters

If you need to strip all parameters (like leading/trailing spaces) before they
reach your controller methods, you can use the `strip` flag on method annotation.

To strip specific parameters use an array of symbols instead of true.

```Crystal
struct UsersController < Kemal::Controller
    @[Post("/users", strip: true)]
    def create(name : String, description : String?)
      "Creating user with name: '#{name}', description: '#{description}'"
    end

    @[Get("/users/edit", strip: [:email])]
    def login(email : String, password : String)
      "Logging in user with email: '#{email}'"
    end
end
```

### Authenticated/protected routes

If you need to protect some routes with authentication you must set the `auth`
flag to true in the method annotation and implement the `authenticate! : Bool`
method in your controller.

If `authenticate!` returns false the request will be halted and no further
processing will be done, status code is set to 401 (Unauthorized).

```Crystal
struct AdminController < Kemal::Controller
  @[Get("/admin/dashboard", auth: true)]
  def dashboard
    "Welcome to the admin dashboard!"
  end

  def authenticate! : Bool
    if !current_user.try(&.current_user.admin?)
      redirect("/login")
      return false
    end
    true
  end
end
```

### WebSocket routes

WebSocket endpoints are declared with `@[WebSocket]`, taking advantage of Kemal's
own WebSocket support. The method is called once, right after the handshake
completes; use the `socket` getter to register `on_message`/`on_close`/etc.
handlers. Parameters are extracted from the handshake request the same way `Get` does.

```Crystal
struct ChatController < Kemal::Controller
  @[WebSocket("/chat/:room")]
  def chat(room : String)
    socket.send("Welcome to #{room}!")
    socket.on_message do |message|
      socket.send("#{room}: #{message}")
    end
  end
end
```

`strip` works the same as with HTTP routes. `auth` works too, but with one
difference: by the time the method runs the handshake response has already
been sent, so a failed `authenticate!` can't reply with a 401 — the socket is
closed instead with `HTTP::WebSocket::CloseCode::PolicyViolation`.

### Printing routes

You can print all registered routes by calling the `Kemal.print_routes` method,
useful for debugging purposes.

```Crystal
Kemal.config.extra_options do |parser|
  parser.on("--routes", "Show all routes") do
    Kemal.print_routes
    exit(0)
  end
end
```

On `--routes` your app will print something like:

```
   GET  /area51                    TestController#area51()
  POST  /array_of_named_tuples     TestController#array_of_named_tuples(items : Array(NamedTuple(name: String, age: Int32)))
   GET  /hello                     TestController#hello(name : String)
  POST  /hello                     TestController#post_hello(name : String)
   GET  /regular_kemal_route       ?
    WS  /chat/:room                ChatController#chat(room : String)

5 routes
```

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     kemal-controller:
       github: hugopl/kemal-controller
   ```

2. Run `shards install`


## Contributing

1. Fork it (<https://github.com/hugopl/kemal-controller/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Hugo Parente Lima](https://github.com/hugopl) - creator and maintainer
