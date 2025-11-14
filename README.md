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

Default values aren't supported yet, meanwhile use a nilable type and handle the defaulting logic inside the method.

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
- Bool
- NamedTuple (with nested support)
- Array (with nested support)
- Nilable versions of the above types

More types may be added in the future, feel free to open an issue or a PR if you need something specific.

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

  private def authenticate! : Bool
    if !current_user.try(&.current_user.admin?)
      redirect("/login")
      return false
    end
    true
  end
end
```

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

4 routes
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
