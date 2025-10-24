module Kemal
  # This monkey patch is needed because Kemal's ParamParser does not expose the raw body.
  # This is required to properly implement Web.parse_www_form which needs the raw body
  # to parse form parameters.
  class ParamParser
    @raw_body : String = ""

    def raw_body
      parse_body unless @body_parsed
      @raw_body
    end

    private def parse_body
      content_type = @request.headers["Content-Type"]?

      return unless content_type

      if content_type.try(&.starts_with?(URL_ENCODED_FORM))
        @raw_body = @request.body.try(&.gets_to_end) || ""
        @body = parse_part(@raw_body)
        return
      end

      if content_type.try(&.starts_with?(MULTIPART_FORM))
        parse_files
      end
    end
  end
end
