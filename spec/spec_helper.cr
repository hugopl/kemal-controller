ENV["KEMAL_ENV"] = "test"

require "spec"
require "kemal"
require "spec-kemal"
require "../src/kemal-controller"

def post(path, params : Enumerable(Tuple(String, _)), *, headers : HTTP::Headers? = nil)
  headers ||= HTTP::Headers.new
  headers["Content-Type"] = "application/x-www-form-urlencoded"

  uri_params = params.map do |key, value|
    URI.encode_www_form(key) + '=' + URI.encode_www_form(value.to_s)
  end.join('&')

  post(path, headers, uri_params.to_s)
end

Kemal.config.always_rescue = false
Kemal.run
