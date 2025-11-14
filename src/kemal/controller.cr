require "./from_www_form"

module Kemal
  abstract struct Controller
    {% for type in %w(Get Post Put Patch Delete Head Options) %}
      # This macro is used to define a route for the controller.
      #
      # @param path [String] The path for the route.
      annotation {{type.id}}
      end
    {% end %}

    alias Errors = Hash(String, String)

    macro inherited
      macro method_added(method)
        {% verbatim do %}
          {% for http_verb in [Get, Post, Put, Patch, Delete, Head, Options] %}
            {% ann = method.annotation(http_verb.resolve) %}
            {% if ann %}
              {% verb = http_verb.stringify.split("::").last.upcase %}
              {% url = ann[0] %}
              Kemal::RouteHandler::INSTANCE.add_route({{ verb }}, {{ url }}) do |ctx|
                Log.debug do
                  "Processing request for #{{{verb}}} #{ctx.request.path} " \
                  "through #{{{ @type.name.stringify }}}##{{{ method.name.stringify }}}".colorize(:cyan)
                end

                ctx.response.status_code = {{ verb.id.symbolize }} == :POST ? 201 : 200

                %params = Kemal.parse_www_form(ctx)
                {% for param in method.args %}
                  {% type = param.restriction.resolve %}
                  {{ param.name.id }} = {{ type }}.from_www_form({{ param.name.stringify }},  %params)

                  {% strip = ann[:strip] %}
                  {% if strip && (strip == true || strip.includes?(param.name.id.symbolize)) %}
                    {{ param.name.id }} = {{ param.name.id }}.strip unless {{ param.name.id }}.nil?
                  {% end %}
                {% end %}

                %controller = {{ @type.id }}.new(ctx)
                %controller.{{method.name.id}}({% for param in method.args %}{{ param.name.id }}, {% end %})
              end
            {% end %}
          {% end %}
        {% end %}
      end
    end

    getter context : HTTP::Server::Context
    getter errors : Errors?

    delegate request, to: @context
    delegate response, to: @context
    delegate session, to: @context
    delegate redirect, to: @context

    def initialize(@context : HTTP::Server::Context)
    end

    def error(message : String)
      error("base", message)
    end

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

    def has_error? : Bool
      errors = @errors
      !errors.nil? && !errors.empty?
    end

    def error_for_base : String?
      @errors.try(&.["base"]?)
    end

    def error_for?(field : String) : String?
      @errors.try(&.[field]?)
    end
  end
end
