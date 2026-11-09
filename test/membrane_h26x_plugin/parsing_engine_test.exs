defmodule Membrane.H26x.ParsingEngineTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Membrane.H26x.{NALu, ParsingEngine}
  alias Membrane.H26x.ParsingEngine.NALuParser

  @fixture "test/fixtures/h264/input-10-320x180.h264"
  # the SPS of the fixture above (High profile, profile_idc 100)
  @sps <<0x67, 0x64, 0x00, 0x0C, 0xAC, 0xD9, 0x81, 0x41, 0x9F, 0x9F, 0x01, 0x10, 0x00, 0x00, 0x03,
         0x00, 0x10, 0x00, 0x00, 0x03, 0x01, 0x40, 0xF1, 0x42, 0x99, 0xA0>>

  defp parse_all(codec, payload) do
    engine =
      ParsingEngine.new(%{
        codec: codec,
        input_stream_structure: :annexb,
        input_alignment: :bytestream
      })

    {events, engine} = ParsingEngine.push(engine, payload)
    {flush_events, _engine} = ParsingEngine.flush(engine)
    events ++ flush_events
  end

  describe "an SPS that fails to parse" do
    test "is not treated as an active parameter set and does not break the stream" do
      truncated_sps = <<0, 0, 0, 1, 0x67, 0x42>>
      events = parse_all(:h264, truncated_sps <> File.read!(@fixture))

      parameter_sets = for {:parameter_sets, parameter_sets} <- events, do: parameter_sets
      access_units = for {:access_unit, au} <- events, do: au

      assert [%{active: active}] = parameter_sets
      assert Enum.all?(active, &(&1.status == :valid))

      assert [%NALu{type: :sps, parsed_fields: %{width: 320, height: 180, profile: :high}}] =
               Enum.filter(active, &(&1.type == :sps))

      # the access unit holding the broken SPS is dropped, the following ones are decodable
      assert length(access_units) == 9
    end

    test "is not treated as an active parameter set when it is the only parameter set" do
      truncated_sps = <<0, 0, 0, 1, 0x67, 0x42>>
      assert parse_all(:h264, truncated_sps) == []
    end
  end

  describe "an SPS with a profile_idc missing from the known profiles table" do
    test "is parsed, with an unknown profile" do
      <<0x67, _profile_idc, sps_rest::binary>> = @sps
      multiview_high_sps = <<0x67, 118, sps_rest::binary>>

      {[nalu], _parser} =
        NALuParser.parse_nalus(
          Membrane.H264.NALuParser,
          [<<0, 0, 0, 1, multiview_high_sps::binary>>],
          NALuParser.new()
        )

      assert %NALu{
               type: :sps,
               status: :valid,
               parsed_fields: %{profile_idc: 118, profile: nil, width: 320, height: 180}
             } = nalu
    end
  end
end
