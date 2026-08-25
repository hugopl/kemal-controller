require "./spec_helper"

private def build_fixture(name : String, flag_enabled : Bool) : {Process::Status, String, String}
  args = ["build", "--no-codegen", "spec/require_auth/fixtures/#{name}.cr"]
  args << "-Dkemal_controller_require_auth" if flag_enabled

  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run("crystal", args, output: output, error: error)
  {status, output.to_s, error.to_s}
end

describe "kemal_controller_require_auth flag" do
  it "compiles a controller with every auth: key explicit, flag enabled" do
    status, _, error = build_fixture("positive_explicit_auth", flag_enabled: true)
    status.success?.should be_true, error
  end

  it "fails to compile a Get annotation missing auth:, flag enabled" do
    status, _, error = build_fixture("negative_missing_auth_get", flag_enabled: true)
    status.success?.should be_false
    error.should contain("missing an explicit 'auth:' key")
  end

  it "fails to compile a WebSocket annotation missing auth:, flag enabled" do
    status, _, error = build_fixture("negative_missing_auth_websocket", flag_enabled: true)
    status.success?.should be_false
    error.should contain("missing an explicit 'auth:' key")
  end

  it "compiles the same missing-auth annotations fine when the flag is off" do
    status, _, error = build_fixture("negative_missing_auth_get", flag_enabled: false)
    status.success?.should be_true, error

    status, _, error = build_fixture("negative_missing_auth_websocket", flag_enabled: false)
    status.success?.should be_true, error
  end
end
