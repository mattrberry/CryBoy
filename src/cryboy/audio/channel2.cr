# tone
class Channel2 < Tone
  @RANGE = 0xFF16..0xFF19

  def [](index : Int) : UInt8
    case index
    when 0xFF16 then 0x3F_u8 | (@wave_pattern_duty << 6) # rest is write-only
    when 0xFF17 then (@initial_volume << 4) | (@increasing ? 0x1 << 3 : 0) | @envelope_sweep_number
    when 0xFF18 then 0xFF_u8                                       # write-only
    when 0xFF19 then 0xBF_u8 | ((@counter_selection ? 1 : 0) << 6) # rest is write-only
    else             raise "Reading from invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    # puts "#{hex_str index.to_u16!} -> #{hex_str value}"
    case index
    when 0xFF16
      @wave_pattern_duty = value >> 6
      @remaining_length = 64_u8 - (value & 0x3F)
      # puts "wave duty: #{@wave_pattern_duty}, sound length: #{@remaining_length}"
    when 0xFF17
      @initial_volume = value >> 4
      @increasing = value & (0x1 << 3) != 0
      @envelope_sweep_number = value & 0x07
      # puts "initial volume: #{@initial_volume}, increasing: #{@increasing}, sweep number #{@envelope_sweep_number}"
    when 0xFF18
      @frequency = (@frequency & 0x700) | value
      # clock on every APU sample
      @period = APU::SAMPLE_RATE // (CPU::CLOCK_SPEED // (8 * (2048 - @frequency)))
    when 0xFF19
      @trigger = value & (0x1 << 7) != 0
      if @trigger
        # puts "wrote trigger. setting volume to #{@initial_volume}"
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
