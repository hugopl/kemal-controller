require "./spec_helper"

describe "#from_www_form" do
  describe "Kemal.parse_www_form" do
    it "can parse www-form strings into a list of key-value pairs" do
      params = Kemal.parse_www_form("key1[]=value1&key1[]=value2", "key2=value3")
      params.should eq([
        {"key1[]", "value1", false},
        {"key1[]", "value2", false},
        {"key2", "value3", false},
      ])
    end

    it "handles empty strings" do
      params = Kemal.parse_www_form("", "")
      params.should eq([] of Tuple(String, String, Bool))
    end
  end

  describe "String.from_www_form" do
    it "can parse string params" do
      params = [{"key", "value", false}]
      String.from_www_form("key", params).should eq("value")
    end

    it "does not strip strings" do
      params = [{"key", "  value  ", false}]
      String.from_www_form("key", params).should eq("  value  ")
    end

    it "raises KeyError for missing key" do
      params = [{"other", "value", false}]
      expect_raises(KeyError, "Key not found: missing") do
        String.from_www_form("missing", params)
      end
    end

    it "handles empty string values" do
      params = [{"key", "", false}]
      String.from_www_form("key", params).should eq("")
    end

    it "handle missing Bool values as false" do
      params = [{"some_key", "", false}]
      Bool.from_www_form("key", params).should eq(false)
    end

    it "uses offset parameter correctly" do
      params = [{"key", "first", false}, {"key", "second", false}]
      String.from_www_form("key", params, 0).should eq("first")
      String.from_www_form("key", params, 1).should eq("second")
    end

    it "marks parameters as fetched" do
      params = [{"key", "value", false}]
      String.from_www_form("key", params)
      params[0][2].should eq(true)
    end

    it "skips already fetched parameters" do
      params = [{"key", "first", true}, {"key", "second", false}]
      String.from_www_form("key", params).should eq("second")
    end
  end

  describe "Union (nullable) types" do
    it "can parse nullable string params" do
      params = [{"key", "value", false}]
      (String?).from_www_form("key", params).should eq("value")
    end

    it "returns nil for missing nullable params" do
      params = [{"other", "value", false}]
      (String?).from_www_form("missing", params).should eq(nil)
    end

    it "can parse nullable int params" do
      params = [{"key", "42", false}]
      (Int32?).from_www_form("key", params).should eq(42)
    end

    it "returns nil for missing nullable int params" do
      params = [{"other", "value", false}]
      (Int32?).from_www_form("missing", params).should eq(nil)
    end
  end

  describe "Int32.from_www_form" do
    it "can parse integer params" do
      params = [{"key", "42", false}]
      Int32.from_www_form("key", params).should eq(42)
    end

    it "handles negative integers" do
      params = [{"key", "-123", false}]
      Int32.from_www_form("key", params).should eq(-123)
    end

    it "handles zero" do
      params = [{"key", "0", false}]
      Int32.from_www_form("key", params).should eq(0)
    end

    it "raises for invalid integer format" do
      params = [{"key", "not_a_number", false}]
      expect_raises(ArgumentError) do
        Int32.from_www_form("key", params)
      end
    end

    it "raises for empty string" do
      params = [{"key", "", false}]
      expect_raises(ArgumentError) do
        Int32.from_www_form("key", params)
      end
    end
  end

  describe "Int64.from_www_form" do
    it "can parse int64 params" do
      params = [{"key", "9223372036854775807", false}]
      Int64.from_www_form("key", params).should eq(9223372036854775807_i64)
    end

    it "handles negative int64" do
      params = [{"key", "-9223372036854775808", false}]
      Int64.from_www_form("key", params).should eq(-9223372036854775808_i64)
    end

    it "handles leading/trailing whitespace" do
      params = [{"key", "  42  ", false}]
      Int32.from_www_form("key", params).should eq(42)
    end

    it "raises for invalid int64 format" do
      params = [{"key", "invalid", false}]
      expect_raises(ArgumentError) do
        Int64.from_www_form("key", params)
      end
    end
  end

  describe "Bool.from_www_form" do
    it "can parse boolean params" do
      params = [{"true", "true", false}, {"false", "false", false}]
      Bool.from_www_form("true", params).should eq(true)
      Bool.from_www_form("false", params).should eq(false)
    end

    it "handles numeric boolean values" do
      params = [{"one", "1", false}, {"zero", "0", false}]
      Bool.from_www_form("one", params).should eq(true)
      Bool.from_www_form("zero", params).should eq(false)
    end

    it "raises for invalid boolean values" do
      params = [{"key", "maybe", false}]
      expect_raises(KeyError, "Invalid boolean value for key: key") do
        Bool.from_www_form("key", params)
      end
    end

    it "raises for empty boolean values" do
      params = [{"key", "", false}]
      expect_raises(KeyError, "Invalid boolean value for key: key") do
        Bool.from_www_form("key", params)
      end
    end

    it "raises for case-sensitive boolean values" do
      params = [{"key", "TRUE", false}]
      expect_raises(KeyError, "Invalid boolean value for key: key") do
        Bool.from_www_form("key", params)
      end
    end
  end

  describe "Array.from_www_form" do
    it "can parse array params" do
      params = [{"key[]", "value1", false}, {"key[]", "value2", false}]
      Array(String).from_www_form("key", params).should eq(["value1", "value2"])
    end

    it "returns empty array when no matching keys" do
      params = [{"other[]", "value", false}]
      Array(String).from_www_form("key", params).should eq([] of String)
    end

    it "can parse array of integers" do
      params = [{"numbers[]", "1", false}, {"numbers[]", "2", false}, {"numbers[]", "3", false}]
      Array(Int32).from_www_form("numbers", params).should eq([1, 2, 3])
    end

    it "can parse array of booleans" do
      params = [{"flags[]", "true", false}, {"flags[]", "false", false}, {"flags[]", "1", false}]
      Array(Bool).from_www_form("flags", params).should eq([true, false, true])
    end

    it "handles single array element" do
      params = [{"key[]", "single", false}]
      Array(String).from_www_form("key", params).should eq(["single"])
    end

    it "handles mixed array keys (should only match exact prefix)" do
      params = [{"key[]", "match", false}, {"key[0]", "nomatch", false}, {"keys[]", "nomatch", false}]
      Array(String).from_www_form("key", params).should eq(["match"])
    end
  end

  describe "NamedTuple.from_www_form" do
    it "can parse named tuple params" do
      params = [{"key[name]", "value1", false}, {"key[age]", "30", false}]
      NamedTuple(name: String, age: Int32).from_www_form("key", params).should eq(
        {name: "value1", age: 30}
      )
    end

    it "raises when required fields are missing" do
      params = [{"key[name]", "value1", false}]
      expect_raises(KeyError, "Key not found for NamedTuple: age") do
        NamedTuple(name: String, age: Int32).from_www_form("key", params)
      end
    end

    it "handles nested named tuples" do
      params = [
        {"user[profile][name]", "John", false},
        {"user[profile][email]", "john@example.com", false},
        {"user[id]", "123", false},
      ]
      NamedTuple(
        id: Int32,
        profile: NamedTuple(name: String, email: String)).from_www_form("user", params).should eq({
        id:      123,
        profile: {name: "John", email: "john@example.com"},
      })
    end

    it "can parse named tuple params with array values" do
      params = [
        {"key[name]", "value1", false},
        {"key[ages][]", "30", false},
        {"key[ages][]", "25", false},
      ]
      NamedTuple(name: String, ages: Array(Int32)).from_www_form("key", params).should eq(
        {name: "value1", ages: [30, 25]}
      )
    end

    it "handles nullable fields in named tuples" do
      params = [{"key[name]", "John", false}]
      NamedTuple(name: String, age: Int32?).from_www_form("key", params).should eq(
        {name: "John", age: nil}
      )
    end

    it "handles empty array in named tuple" do
      params = [{"key[name]", "John", false}]
      NamedTuple(name: String, tags: Array(String)).from_www_form("key", params).should eq(
        {name: "John", tags: [] of String}
      )
    end
  end

  describe "Array of NamedTuple" do
    it "can parse array of named tuple params" do
      params = [
        {"key[][name]", "value1", false},
        {"key[][age]", "30", false},
        {"key[][name]", "value2", false},
        {"key[][age]", "25", false},
      ]
      Array(NamedTuple(name: String, age: Int32)).from_www_form("key", params).should eq([
        {name: "value1", age: 30},
        {name: "value2", age: 25},
      ])
    end

    it "handles single element array of named tuples" do
      params = [
        {"key[][name]", "John", false},
        {"key[][age]", "30", false},
      ]
      Array(NamedTuple(name: String, age: Int32)).from_www_form("key", params).should eq([
        {name: "John", age: 30},
      ])
    end

    it "returns empty array when no matching named tuple keys" do
      params = [{"other[][name]", "value", false}]
      Array(NamedTuple(name: String, age: Int32)).from_www_form("key", params).should eq(
        [] of NamedTuple(name: String, age: Int32)
      )
    end

    it "handles complex nested arrays of named tuples" do
      params = [
        {"users[][name]", "John", false},
        {"users[][profile][email]", "john@example.com", false},
        {"users[][profile][verified]", "true", false},
        {"users[][name]", "Jane", false},
        {"users[][profile][email]", "jane@example.com", false},
        {"users[][profile][verified]", "false", false},
      ]
      Array(NamedTuple(
        name: String,
        profile: NamedTuple(email: String, verified: Bool))).from_www_form("users", params).should eq([
        {name: "John", profile: {email: "john@example.com", verified: true}},
        {name: "Jane", profile: {email: "jane@example.com", verified: false}},
      ])
    end

    it "handles nested array of named tuples" do
      params = [
        {"garbage", "ignore_me", false},
        {"group[][id]", "1", false},
        {"group[][members][][name]", "Alice", false},
        {"group[][members][][name]", "Bob", false},
        {"group[][id]", "2", false},
        {"group[][members][][name]", "Charlie", false},
      ]
      Array(NamedTuple(
        id: Int32,
        members: Array(NamedTuple(name: String)))).from_www_form("group", params).should eq([
        {id: 1, members: [{name: "Alice"}, {name: "Bob"}]},
        {id: 2, members: [{name: "Charlie"}]},
      ])
    end
  end

  describe "Complex nested structures" do
    it "handles deeply nested structures" do
      params = [
        {"form[user][profile][personal][name]", "John", false},
        {"form[user][profile][personal][age]", "30", false},
        {"form[user][profile][contacts][]", "email@example.com", false},
        {"form[user][profile][contacts][]", "phone@example.com", false},
        {"form[user][active]", "true", false},
      ]

      NamedTuple(
        user: NamedTuple(
          profile: NamedTuple(
            personal: NamedTuple(name: String, age: Int32),
            contacts: Array(String)),
          active: Bool)).from_www_form("form", params).should eq({
        user: {
          profile: {
            personal: {name: "John", age: 30},
            contacts: ["email@example.com", "phone@example.com"],
          },
          active: true,
        },
      })
    end
  end

  describe "Edge cases and error handling" do
    it "handles negative offset (should start from 0)" do
      params = [{"key", "value", false}]
      String.from_www_form("key", params, -1).should eq("value")
    end

    it "preserves order of parameters" do
      params = [
        {"key[]", "first", false},
        {"key[]", "second", false},
        {"other", "middle", false},
      ]
      Array(String).from_www_form("key", params).should eq(["first", "second"])
    end
  end
end
