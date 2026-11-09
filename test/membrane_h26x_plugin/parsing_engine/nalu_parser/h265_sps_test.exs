defmodule Membrane.H265.NALuParser.Schemes.SPSTest do
  use ExUnit.Case, async: true

  import Bitwise
  import ExUnit.CaptureLog

  alias Membrane.H26x.NALu
  alias Membrane.H26x.ParsingEngine.NALuParser
  alias Membrane.H26x.ParsingEngine.NALuParser.ExpGolombConverter

  defp ue(value), do: ExpGolombConverter.to_bitstring(value)

  # Builds a minimal Main profile 64x64 SPS, letting the test override the fields
  # it is interested in. `st_ref_pic_sets` is appended verbatim after
  # `num_short_term_ref_pic_sets`.
  defp sps(overrides \\ %{}) do
    fields =
      Map.merge(
        %{
          log2_diff_max_min_luma_coding_block_size: 1,
          num_short_term_ref_pic_sets: 0,
          st_ref_pic_sets: <<>>
        },
        overrides
      )

    body =
      <<
        0::4,
        0::3,
        1::1,
        # profile_tier_level
        0::2,
        0::1,
        1::5,
        0x60000000::32,
        1::1,
        0::1,
        0::1,
        1::1,
        0::44,
        93::8,
        ue(0)::bitstring,
        ue(1)::bitstring,
        ue(64)::bitstring,
        ue(64)::bitstring,
        0::1,
        ue(0)::bitstring,
        ue(0)::bitstring,
        ue(4)::bitstring,
        1::1,
        ue(1)::bitstring,
        ue(0)::bitstring,
        ue(0)::bitstring,
        ue(0)::bitstring,
        ue(fields.log2_diff_max_min_luma_coding_block_size)::bitstring,
        ue(0)::bitstring,
        ue(2)::bitstring,
        ue(0)::bitstring,
        ue(0)::bitstring,
        0::1,
        0::1,
        0::1,
        0::1,
        ue(fields.num_short_term_ref_pic_sets)::bitstring,
        fields.st_ref_pic_sets::bitstring,
        0::1,
        0::1,
        0::1,
        0::1,
        1::1
      >>

    padding = rem(8 - rem(bit_size(body), 8), 8)
    <<0, 0, 0, 1, 0x42, 0x01, body::bitstring, 0::size(padding)>>
  end

  defp parse(sps) do
    {[nalu], _parser} =
      NALuParser.parse_nalus(Membrane.H265.NALuParser, [sps], NALuParser.new(:annexb))

    nalu
  end

  test "a well-formed SPS is parsed" do
    assert %NALu{type: :sps, status: :valid, parsed_fields: fields} = parse(sps())
    assert %{width: 64, height: 64, profile: :main, segment_addr_length: 4} = fields
  end

  test "an SPS with a coding tree block size out of the spec range is erroneous" do
    # log2_diff_max_min_luma_coding_block_size = 2^33, a 67-bit ue(v), which would make
    # `1 <<< ctb_log2_size_y` build a gigabyte-sized integer before failing
    log =
      capture_log(fn ->
        assert %NALu{type: :sps, status: :error} =
                 parse(sps(%{log2_diff_max_min_luma_coding_block_size: 1 <<< 33}))
      end)

    assert log =~ "ctb_log2_size_y is 8589934595, exceeding the maximum of 6"
  end

  test "an SPS with too many short term reference picture sets is erroneous" do
    log =
      capture_log(fn ->
        assert %NALu{type: :sps, status: :error} =
                 parse(
                   sps(%{num_short_term_ref_pic_sets: 1 <<< 20, st_ref_pic_sets: <<0::1024>>})
                 )
      end)

    assert log =~ "num_short_term_ref_pic_sets is 1048576, exceeding the maximum of 64"
  end

  test "an SPS with too many negative reference pictures in a set is erroneous" do
    log =
      capture_log(fn ->
        assert %NALu{type: :sps, status: :error} =
                 parse(
                   sps(%{
                     num_short_term_ref_pic_sets: 1,
                     st_ref_pic_sets: <<ue(1 <<< 20)::bitstring, ue(0)::bitstring, 0::1024>>
                   })
                 )
      end)

    assert log =~ "num_negative_pics is 1048576, exceeding the maximum of 16"
  end
end
