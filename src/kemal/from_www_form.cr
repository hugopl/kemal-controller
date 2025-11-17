module Kemal
  # :nodoc:
  # Internal type alias for a collection of web form parameters.
  # This is used internally by the framework and should not be used directly.
  alias WWWForm = Array(Tuple(String, String, Bool))

  # List of parameter name keywords that trigger automatic redaction in logs.
  #
  # The following parameters are automatically redacted if a request contains
  # a parameter whose name partially matches one of these keywords (case-sensitive).
  # Use lowercase parameter names to ensure proper redaction.
  #
  # Default keywords: `passw`, `secret`, `token`, `_key`, `crypt`, `salt`,
  # `certificate`, `otp`, `ssn`, `cvv`, `cvc`
  #
  # ## Example
  #
  # ```
  # Kemal.redacted_parameters << "api_key"
  # ```
  class_property redacted_parameters = %w(passw secret token _key crypt salt
    certificate otp ssn cvv cvc)

  # Exception raised when a required parameter is not found in the request.
  #
  # This error is raised when a controller method declares a non-nilable parameter
  # but the corresponding key is missing from the request data.
  #
  # ## Example
  #
  # ```
  # @[Get("/users")]
  # def index(name : String) # name is required
  #   "Hello, #{name}"
  # end
  # # GET /users without ?name=... will raise Kemal::KeyError
  # ```
  class KeyError < KeyError
    def initialize(form_key : String)
      super("Key not found in WWWForm: #{form_key}")
    end
  end

  # :nodoc:
  # Internal method to parse HTTP request parameters from the given context.
  # This is used internally by the framework and should not be called directly.
  def self.parse_www_form(context : HTTP::Server::Context) : WWWForm
    request = context.request

    # Query params
    query_params = request.query.to_s

    # Body params
    content_type = request.headers["Content-Type"]?
    body_params = if content_type && content_type.starts_with?("application/x-www-form-urlencoded")
                    context.params.raw_body
                  else
                    ""
                  end
    params = parse_www_form(query_params, body_params)

    # URL params
    context.route_lookup.params.each do |key, value|
      value = value.empty? ? "" : URI.decode(value)
      params << {key, value, false}
    end

    Log.debug do
      String.build do |str|
        str << "Parameters: "
        params.map do |key, value, _|
          value = "[redacted]" if redacted_parameters.any? { |word| key.includes?(word) }
          "#{key}: #{value.inspect}"
        end.join(str, ", ")
      end
    end
    params
  end

  # :nodoc:
  # Internal method to parse URL-encoded form strings into a WWWForm array.
  # This is used internally by the framework and should not be called directly.
  def self.parse_www_form(*params : String) : WWWForm
    param_parts = WWWForm.new
    params.each do |param|
      URI::Params.parse(param) do |key, value|
        param_parts << {key, value, false}
      end
    end
    param_parts
  end
end

# :nodoc:
def Union.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0)
  {% if !T.includes?(Nil) %}
  {% raise "Only union types including Nil are supported" %}
  {% end %}

  {% if T.size < 2 %}
  {% raise "Only nilable types are supported" %}
  {% end %}

  {% begin %}
  {% type = (T - {Nil}).first %}
  {{ type }}.from_www_form(name, params, offset)
  {% end %}
rescue KeyError
  nil
end

# :nodoc:
def Nil.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : Nil
  nil
end

# :nodoc:
def String.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : String
  params.each(within: offset..) do |key, value, fetched|
    if !fetched && key == name
      params[offset] = {key, value, true} # Mark as fetched
      return value
    end
    offset += 1
  end
  raise Kemal::KeyError.new("Key not found: #{name}")
end

# :nodoc:
def Int32.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : Int32
  value = String.from_www_form(name, params, offset)
  value.to_i32
end

# :nodoc:
def Int64.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : Int64
  value = String.from_www_form(name, params, offset)
  value.to_i64
end

# :nodoc:
def Bool.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : Bool
  value = String.from_www_form(name, params, offset)
  case value
  when "true", "1"
    true
  when "false", "0"
    false
  else
    raise Kemal::KeyError.new("Invalid boolean value for key: #{name}")
  end
end

# :nodoc:
def Array.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : Array(T)
  array = [] of T
  key_prefix = name + "[]"
  params.each(within: offset..) do |key, _value, fetched|
    if !fetched
      if key.starts_with?(key_prefix)
        item = T.from_www_form(key_prefix, params, offset)
        array << item
      elsif !array.empty?
        break
      end
    end
    offset += 1
  end
  array
end

# :nodoc:
def NamedTuple.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : NamedTuple
  {% for key in @type.keys %}
    key_{{ key }} = uninitialized typeof(element_type({{ key.symbolize }}))
    key_{{ key }}_initialized = false
  {% end %}

  params.each(within: offset..) do |key, _value, fetched|
    if !fetched
      {% for key in @type.keys %}
        key_prefix = name + {{ "[#{key}]" }}
        if key.starts_with?(key_prefix)
          break if key_{{ key }}_initialized # Probably rading an array of named tuples, so this starts a new element.

          key_{{ key }} = typeof(element_type({{ key.symbolize }})).from_www_form(key_prefix, params, offset)
          key_{{ key }}_initialized = true
        end
      {% end %}
    end
    offset += 1
  end

  {% for key in @type.keys %}
    if !key_{{ key }}_initialized
    {% if @type[key].nilable? %}
      key_{{ key }} = nil
    {% elsif @type[key] < Array %}
      key_{{ key }} = {{ @type[key] }}.new
    {% else %}
      raise Kemal::KeyError.new("Key not found for NamedTuple: {{ key }}")
    {% end %}
    end
  {% end %}

  {% begin %}
  NamedTuple.new(
    {% for key in @type.keys %}
      {{ key }}: key_{{ key }},
    {% end %}
  )
  {% end %}
end

# :nodoc:
def Time.from_www_form(name : String, params : Kemal::WWWForm, offset : Int32 = 0) : Time
  Log.fatal { "Time.from_www_form NOT IMPLEMENTED" }
  Time.utc
end
