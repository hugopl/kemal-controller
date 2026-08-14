require "uri"

module Kemal
  # URL helpers generated at compile time, one per controller route.
  #
  # Every route defined by a `Kemal::Controller` subclass gets a method here, named
  # `{controller}_{action}`: the controller's trailing `Controller` is dropped, `::` becomes
  # `_`, and the rest is underscored. `UsersController#show` becomes `users_show`,
  # `Admin::NodeGroupsController#edit` becomes `admin_node_groups_edit`. Pass `as:` to the
  # route annotation to choose the name instead.
  #
  # Path parameters become positional arguments, in the order they appear in the path, typed
  # after the action's own parameter of the same name (`String` when the action doesn't
  # declare it). Any extra keyword argument is appended as a query parameter; `nil` values
  # are skipped.
  #
  # ## Example
  #
  # ```
  # struct UsersController < Kemal::Controller
  #   @[Get("/users/:username")]
  #   def show(username : String)
  #     "User #{username}"
  #   end
  #
  #   @[Get("/users/new", as: new_user)]
  #   def new
  #     "New user form"
  #   end
  # end
  #
  # Kemal::Routes.users_show("john doe")                     # => "/users/john%20doe"
  # Kemal::Routes.new_user                                   # => "/users/new"
  # Kemal::Routes.users_show("john", tab: "profile", q: nil) # => "/users/john?tab=profile"
  # ```
  #
  # The module is `extend self`, so the helpers can also be mixed into a class or a view with
  # `include Kemal::Routes`.
  #
  # NOTE: Two routes generating the same helper name for different paths is a compile-time
  # error; give at least one of them an `as:` name. `build_path` is reserved and can't be used
  # as an `as:` name.
  module Routes
    extend self

    # :nodoc:
    def self.build_path(path : String, query) : String
      return path if query.empty?

      params = URI::Params.new
      query.each { |key, value| params.add(key.to_s, value.to_s) unless value.nil? }
      params.empty? ? path : "#{path}?#{params}"
    end
  end

  # :nodoc:
  #
  # Defines a `Kemal::Routes` method for every route of every `Kemal::Controller` subclass.
  # Called from `Kemal::Controller`'s `finished` hook, once all controllers are known.
  macro define_route_helpers
    {% begin %}
      {% paths_by_name = {} of String => String %}
      {% owners_by_name = {} of String => String %}

      module ::Kemal::Routes
        {% for controller in Kemal::Controller.all_subclasses %}
          {% prefix = controller.name.gsub(/Controller$/, "").gsub(/::/, "_").underscore %}

          {% for method in controller.methods %}
            {% for annotation_type in [Kemal::Controller::Get, Kemal::Controller::Post,
                                       Kemal::Controller::Put, Kemal::Controller::Patch,
                                       Kemal::Controller::Delete, Kemal::Controller::Head,
                                       Kemal::Controller::Options, Kemal::Controller::WebSocket] %}
              {% ann = method.annotation(annotation_type) %}
              {% if ann %}
                {% name = ann[:as] ? ann[:as].id.stringify : "#{prefix.id}_#{method.name}" %}
                {% owner = "#{controller.name}##{method.name}" %}
                {% path = ann[0] %}

                {% if name == "build_path" %}
                  {% raise "#{owner.id} can't name its URL helper 'build_path', the name is reserved by Kemal::Routes." %}
                {% end %}

                {% previous_path = paths_by_name[name] %}
                {% if previous_path && previous_path != path %}
                  {% raise "#{owner.id} and #{owners_by_name[name].id} both generate the URL helper " +
                           "'Kemal::Routes.#{name.id}', for #{path.id} and #{previous_path.id}. " +
                           "Give one of them a different name with the route annotation's 'as' parameter." %}
                {% end %}

                {% unless previous_path %}
                  {% paths_by_name[name] = path %}
                  {% owners_by_name[name] = owner %}
                  {% segments = path.split("/").reject(&.empty?) %}

                  def {{ name.id }}(
                    {% for segment in segments %}
                      {% if segment.starts_with?(":") || segment.starts_with?("*") %}
                        {% param = segment[1..-1] %}
                        {% param = "splat" if param.empty? %}
                        {% arg = method.args.find { |a| a.name.stringify == param } %}
                        {{ param.id }} : {{ (arg && arg.restriction) ? arg.restriction : String }},
                      {% end %}
                    {% end %}
                    **query,
                  ) : String
                    ::Kemal::Routes.build_path(
                      {% if segments.empty? %}
                        "/",
                      {% else %}
                        String.build do |io|
                          {% for segment in segments %}
                            io << '/'
                            {% if segment.starts_with?(":") %}
                              io << URI.encode_path_segment({{ segment[1..-1].id }}.to_s)
                            {% elsif segment.starts_with?("*") %}
                              {% param = segment[1..-1] %}
                              io << {{ (param.empty? ? "splat" : param).id }}.to_s
                            {% else %}
                              io << {{ segment }}
                            {% end %}
                          {% end %}
                        end,
                      {% end %}
                      query)
                  end
                {% end %}
              {% end %}
            {% end %}
          {% end %}
        {% end %}
      end
    {% end %}
  end
end
