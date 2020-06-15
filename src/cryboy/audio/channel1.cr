# tone & sweep
class Channel1 < Tone # todo: sweep
  @RANGE = 0xFF10..0xFF14

  @sweep : UInt8 = 0x00

  def sweep_step : Nil # todo
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF10 then 0x00_u8
    when 0xFF11 then 0x3F_u8 | (@wave_pattern_duty << 6) # rest is write-only
    when 0xFF12 then (@initial_volume << 4) | (@increasing ? 0x1 << 3 : 0) | @envelope_sweep_number
    when 0xFF13 then 0xFF_u8                                       # write-only
    when 0xFF14 then 0xBF_u8 | ((@counter_selection ? 1 : 0) << 6) # rest is write-only
    else             raise "Reading from invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF10
    when 0xFF11
      @wave_pattern_duty = value >> 6
      @remaining_length = 64_u8 - (value & 0x3F)
    when 0xFF12
      @initial_volume = value >> 4
      @increasing = value & (0x1 << 3) != 0
      @envelope_sweep_number = value & 0x07
    when 0xFF13
      @frequency = (@frequency & 0x700) | value
      # clock on every APU sample
      @period = APU::SAMPLE_RATE // (CPU::CLOCK_SPEED // (8 * (2048 - @frequency)))
    when 0xFF14
      @trigger = value & (0x1 << 7) != 0
      if @trigger
        @volume = @initial_volume
        @current_envelope_sweep = @envelope_sweep_number
      end
      @counter_selection = value & (0x1 << 6) != 0
      @frequency = (@frequency & 0x00FF) | ((value.to_u16 & 0x3) << 8)
      # clock on every APU sample
      @period = APU::SAMPLE_RATE // (CPU::CLOCK_SPEED // (8 * (2048 - @frequency)))
    else raise "Writing to invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end
end
