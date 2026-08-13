require "./spec_helper"

private struct CastErrorController < Kemal::Controller
  @[Post("/nodes/:hostname")]
  def update(hostname : String, store_number : Int32, puppet_masterless : Bool)
    "update: hostname=#{hostname}, store_number=#{store_number}, puppet_masterless=#{puppet_masterless}"
  end

  def update_on_cast_error(hostname, store_number, puppet_masterless)
    "hostname=#{format(hostname)}, store_number=#{format(store_number)}, puppet_masterless=#{format(puppet_masterless)}"
  end

  @[Get("/multi")]
  def multi(id : Int32, count : Int32 = 10)
    "id=#{id}, count=#{count}"
  end

  def multi_on_cast_error(id, count)
    "id=#{format(id)}, count_is_error=#{count.is_a?(Kemal::ParamError)}, count=#{count}"
  end

  @[Get("/no-hook/:id")]
  def no_hook(id : Int32)
    "id: #{id}"
  end

  @[Post("/no-hook-required")]
  def no_hook_required(name : String)
    "name: #{name}"
  end

  private def format(value : Kemal::ParamError) : String
    "ERROR(#{value.reason})"
  end

  private def format(value) : String
    value.to_s
  end
end

describe "Kemal::Controller#_on_cast_error" do
  describe "when no hook is defined" do
    it "raises Kemal::ParamError with reason CastError, unchanged, for an invalid parameter" do
      expect_raises(Kemal::ParamError) do
        get("/no-hook/not-a-number")
      end
    end

    it "raises Kemal::ParamError with reason Missing, unchanged, for a missing required parameter" do
      expect_raises(Kemal::ParamError, "Missing parameter: name") do
        post("/no-hook-required", [] of Tuple(String, String))
      end
    end
  end

  describe "when every parameter casts successfully" do
    it "calls the real action with correctly-typed, narrowed values" do
      post("/nodes/host1", { {"store_number", "42"}, {"puppet_masterless", "true"} })
      response.body.should eq("update: hostname=host1, store_number=42, puppet_masterless=true")
    end
  end

  describe "when a single parameter fails to cast" do
    it "calls the hook, with the other parameters arriving as their normal cast type" do
      post("/nodes/host1", { {"store_number", "not_a_number"}, {"puppet_masterless", "true"} })
      response.body.should eq("hostname=host1, store_number=ERROR(CastError), puppet_masterless=true")
    end
  end

  describe "when a required parameter is missing entirely" do
    it "calls the hook with a Kemal::ParamError whose reason is Missing" do
      post("/nodes/host1", [] of Tuple(String, String))
      # puppet_masterless (Bool) defaults missing values to false rather than raising —
      # see the "default Bool values to false" behaviour in from_www_form_spec.cr.
      response.body.should eq("hostname=host1, store_number=ERROR(Missing), puppet_masterless=false")
    end
  end

  describe "when multiple parameters fail to cast at once" do
    it "delivers every failing parameter as its own Kemal::ParamError, not just the first" do
      post("/nodes/host1", { {"store_number", "not_a_number"}, {"puppet_masterless", "not_a_bool"} })
      response.body.should eq("hostname=host1, store_number=ERROR(CastError), puppet_masterless=ERROR(CastError)")
    end
  end

  describe "a missing parameter with a default value" do
    it "never arrives at the hook as an error, even when a sibling parameter fails" do
      get("/multi?id=not_a_number")
      response.body.should eq("id=ERROR(CastError), count_is_error=false, count=10")
    end

    it "does not trigger the hook at all when every parameter is fine" do
      get("/multi?id=7")
      response.body.should eq("id=7, count=10")
    end
  end
end
