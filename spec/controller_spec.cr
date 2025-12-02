require "./spec_helper"

private struct TestController < Kemal::Controller
  @[Get("/hello")]
  def hello(name : String)
    "Hello, #{name}!"
  end

  @[Post("/hello")]
  def post_hello(name : String)
    "Hello, #{name}!"
  end

  @[Get("/route/:parameter/allowed")]
  def route_parameter_allowed(parameter : String)
    "Parameter: #{parameter}"
  end

  @[Get("/strip", strip: true)]
  def strip(something : String)
    something
  end

  @[Get("/strip-nilable", strip: true)]
  def strip_nilable(something : String?)
    something.inspect
  end

  @[Get("/strip-specific", strip: %i(strippable1 strippable2))]
  def strip_specific(strippable1 : String, unstrippable : String, strippable2 : String)
    "Strippable1: '#{strippable1}', Unstrippable: '#{unstrippable}', Strippable2: '#{strippable2}'"
  end

  @[Get("/nostrip")]
  def nostrip(something : String)
    something
  end

  @[Post("/named_tuples")]
  def named_tuples(item : NamedTuple(name: String, age: Int32))
    "Name: #{item[:name]}, Age: #{item[:age]}"
  end

  @[Post("/array_of_named_tuples")]
  def array_of_named_tuples(items : Array(NamedTuple(name: String, age: Int32)))
    items.map { |item| "Name: #{item[:name]}, Age: #{item[:age]}" }.join(", ")
  end

  @[Post("/named_tuple_with_array")]
  def named_tuple_with_array(data : NamedTuple(names: Array(String), scores: Array(Int32)))
    names = data[:names].join("|")
    scores = data[:scores].map(&.to_s).join("|")
    "Names: #{names}, Scores: #{scores}"
  end

  @[Post("/integers_and_booleans")]
  def integers_and_booleans(int32 : Int32, int64 : Int64, flag : Bool, flag2 : Bool)
    "Int32: #{int32}, Int64: #{int64}, Flag: #{flag}, Flag2: #{flag2}"
  end

  @[Get("/nilable")]
  def nilable_param(number : Int32?)
    number.inspect
  end

  @[Get("/enum")]
  def enum_param(status : HTTP::Status)
    "Status: #{status}"
  end

  @[Get("/area51", auth: true)]
  def area51
    "You found area 51!"
  end

  def authenticate! : Bool
    if request.headers["Authorization"]? != "SecretToken"
      response.status_code = 401
      return false
    end
    true
  end
end

describe Kemal::Controller do
  it "can handle GET request parameters" do
    get("/hello?name=Crystal")
    response.body.should eq("Hello, Crystal!")
  end

  it "can handle POST request parameters" do
    post("/hello", { {"name", "Crystal"} })
    response.body.should eq("Hello, Crystal!")
  end

  it "can handle route parameters" do
    get("/route/Testing123/allowed")
    response.body.should eq("Parameter: Testing123")
  end

  it "can handle named tuples from POST parameters" do
    post("/named_tuples", { {"item[name]", "Alice"}, {"item[age]", "30"} })
    response.body.should eq("Name: Alice, Age: 30")
  end

  it "can handle array of named tuples from POST parameters" do
    post("/array_of_named_tuples", {
      {"items[][name]", "Alice"},
      {"items[][age]", "30"},
      {"items[][name]", "Bob"},
      {"items[][age]", "25"},
    })
    response.body.should eq("Name: Alice, Age: 30, Name: Bob, Age: 25")
  end

  it "can handle empty array" do
    post("/array_of_named_tuples")
    response.body.should eq("")
  end

  it "can handle named tuple with array from POST parameters" do
    post("/named_tuple_with_array", {
      {"data[names][]", "Alice"},
      {"data[names][]", "Bob"},
      {"data[scores][]", "85"},
      {"data[scores][]", "90"},
    })
    response.body.should eq("Names: Alice|Bob, Scores: 85|90")
  end

  it "can handle integers and booleans from POST parameters" do
    post("/integers_and_booleans", {
      {"int32", "42"},
      {"int64", "1234567890123"},
      {"flag", "true"},
      {"flag2", "0"},
    })
    response.body.should eq("Int32: 42, Int64: 1234567890123, Flag: true, Flag2: false")
  end

  it "can handle nilable parameters" do
    get("/nilable")
    response.body.should eq("nil")

    get("/nilable?number=100")
    response.body.should eq("100")
  end

  pending "can handle default values" do
    # To be implemented
  end

  it "can handle enum parameters" do
    get("/enum?status=200")
    response.body.should eq("Status: OK")

    get("/enum?status=not_found")
    response.body.should eq("Status: NOT_FOUND")
  end

  it "does not strip parameters by default" do
    get("/nostrip?something=%20Crystal%20")
    response.body.should eq(" Crystal ")
  end

  it "does strip nilable parameters" do
    get("/strip-nilable?something=%20Hello%20World%20")
    response.body.should eq("\"Hello World\"")

    get("/strip-nilable")
    response.body.should eq("nil")
  end

  it "can strip all parameters" do
    get("/strip?something=%20I%20once%20had%20spaces.%20")
    response.body.should eq("I once had spaces.")
  end

  it "can strip specific parameters" do
    get("/strip-specific?strippable1=%20First%20&unstrippable=%20 Second %20&strippable2=%20 Third %20")
    response.body.should eq("Strippable1: 'First', Unstrippable: '  Second  ', Strippable2: 'Third'")
  end

  it "can enforce authentication" do
    get("/area51")
    response.status_code.should eq(401)

    get("/area51", HTTP::Headers{"Authorization" => "SecretToken"})
    response.body.should eq("You found area 51!")
  end

  it "can print routes" do
    color_setting = Colorize.enabled?
    Colorize.enabled = false
    output = String.build { |str| Kemal.print_routes(str) }
    output.should start_with(
      "   GET 🔒    /area51                    TestController#area51()\n" \
      "  POST       /array_of_named_tuples     TestController#array_of_named_tuples(items : Array(NamedTuple(name: String, age: Int32)))\n"
    )
    output.should contain("   GET    ✂️  /strip                     TestController#strip(something : String)\n")
  ensure
    Colorize.enabled = color_setting.not_nil!
  end
end
