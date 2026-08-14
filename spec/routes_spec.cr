require "./spec_helper"

private struct RouteHelpersController < Kemal::Controller
  @[Get("/")]
  def root
    "Root"
  end

  @[Get("/helpers/:code")]
  def show(code : String)
    "Show #{code}"
  end

  @[Get("/helpers/:code/edit", as: helper_edit)]
  def edit(code : String)
    "Edit #{code}"
  end

  @[Get("/numbered/:id")]
  def numbered(id : Int32)
    "Numbered #{id}"
  end

  @[Get("/assets/*path")]
  def asset(path : String)
    "Asset #{path}"
  end

  @[Get("/splat/*")]
  def splat
    "Splat"
  end

  @[Get("/both")]
  @[Post("/both")]
  def both
    "Both"
  end

  @[WebSocket("/rooms/:room")]
  def chat(room : String)
    socket.send("Welcome to #{room}!")
  end
end

private module Nested
  struct DeepController < Kemal::Controller
    @[Get("/deep")]
    def index
      "Deep"
    end
  end
end

describe Kemal::Routes do
  it "names helpers after the controller and the action" do
    Kemal::Routes.route_helpers_root.should eq("/")
    Kemal::Routes.route_helpers_show("lab1").should eq("/helpers/lab1")
  end

  it "underscores namespaced controllers" do
    Kemal::Routes.nested_deep_index.should eq("/deep")
  end

  it "uses the name given by the annotation's as parameter" do
    Kemal::Routes.helper_edit("lab1").should eq("/helpers/lab1/edit")
  end

  it "escapes path parameters" do
    Kemal::Routes.route_helpers_show("lab 1/2").should eq("/helpers/lab%201%2F2")
  end

  it "types path parameters after the action's parameters" do
    Kemal::Routes.route_helpers_numbered(42).should eq("/numbered/42")
  end

  it "keeps slashes in glob parameters" do
    Kemal::Routes.route_helpers_asset("css/app.css").should eq("/assets/css/app.css")
    Kemal::Routes.route_helpers_splat("a/b").should eq("/splat/a/b")
  end

  it "generates a single helper for a method with several routes on one path" do
    Kemal::Routes.route_helpers_both.should eq("/both")
  end

  it "generates helpers for WebSocket routes" do
    Kemal::Routes.route_helpers_chat("lobby").should eq("/rooms/lobby")
  end

  it "appends extra keyword arguments as query parameters" do
    Kemal::Routes.route_helpers_show("lab1", q: "a b", page: 2)
      .should eq("/helpers/lab1?q=a+b&page=2")
  end

  it "skips nil query parameters" do
    Kemal::Routes.route_helpers_show("lab1", q: "vlan", page: nil).should eq("/helpers/lab1?q=vlan")
    Kemal::Routes.route_helpers_show("lab1", q: nil).should eq("/helpers/lab1")
  end

  it "can be included" do
    Includer.new.helper_edit("lab1").should eq("/helpers/lab1/edit")
  end
end

private class Includer
  include Kemal::Routes
end
