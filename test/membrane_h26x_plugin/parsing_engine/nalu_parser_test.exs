defmodule Membrane.H26x.ParsingEngine.NALuParserTest do
  use ExUnit.Case, async: true

  alias Membrane.H26x.{NALu, ParsingEngine}
  alias Membrane.H26x.ParsingEngine.NALuParser

  @h264_fixture "test/fixtures/h264/input-10-320x180.h264"
  @h265_fixture "test/fixtures/h265/input-10-1920x1080.h265"

  defp parse(module, nalus_payloads, stream_structure) do
    {nalus, _parser} =
      NALuParser.parse_nalus(module, nalus_payloads, NALuParser.new(stream_structure))

    nalus
  end

  defp count_access_units(codec, payload) do
    engine =
      ParsingEngine.new(%{
        codec: codec,
        input_stream_structure: :annexb,
        input_alignment: :bytestream
      })

    {events, engine} = ParsingEngine.push(engine, payload)
    {flush_events, _engine} = ParsingEngine.flush(engine)
    Enum.count(events ++ flush_events, &match?({:access_unit, _au}, &1))
  end

  describe "a NALu too short to hold the NALu header" do
    test "is skipped in an Annex B H.264 stream (two adjacent start codes)" do
      assert [%NALu{type: :aud, status: :valid}] =
               parse(Membrane.H264.NALuParser, [<<0, 0, 1>>, <<0, 0, 0, 1, 0x09, 0xF0>>], :annexb)
    end

    test "is skipped in a length-prefixed H.264 stream (zero-length NALu)" do
      assert [%NALu{type: :aud, status: :valid}] =
               parse(
                 Membrane.H264.NALuParser,
                 [<<0, 0, 0, 0>>, <<0, 0, 0, 2, 0x09, 0xF0>>],
                 {:avc1, 4}
               )
    end

    test "is skipped in an Annex B H.265 stream (one-byte NALu)" do
      assert [%NALu{type: :aud, status: :valid}] =
               parse(
                 Membrane.H265.NALuParser,
                 [<<0, 0, 0, 1, 0x46>>, <<0, 0, 0, 1, 0x46, 0x01, 0x50>>],
                 :annexb
               )
    end

    test "does not affect the rest of the stream" do
      h264 = File.read!(@h264_fixture)
      assert count_access_units(:h264, <<0, 0, 0, 1, 0, 0, 0, 1>> <> h264) == 10
      assert count_access_units(:h264, h264 <> <<0, 0, 0, 1>>) == 10

      h265 = File.read!(@h265_fixture)
      assert count_access_units(:h265, <<0, 0, 0, 1, 0x40, 0, 0, 0, 1>> <> h265) == 10
    end
  end
end
