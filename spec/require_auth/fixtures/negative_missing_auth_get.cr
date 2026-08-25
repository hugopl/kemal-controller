require "../../../src/kemal-controller"

private struct NegativeGetController < Kemal::Controller
  @[Post("/array_of_named_tuples", strip: true, status: 201, as: some_helper)]
  def array_of_named_tuples(items : Array(NamedTuple(name: String, age: Int32)))
    items.map(&.[:name]).join(", ")
  end
end
