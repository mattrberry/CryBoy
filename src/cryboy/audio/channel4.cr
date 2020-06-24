class Channel4 < VolumeEnvelopeChannel
  @@RANGE = 0xFF20..0xFF23

  @lfsr : UInt16 = 0x0000

  @remaining_length : UInt8 = 0x00

  @shift_clock_frequency : UInt8 = 0x00
  @counter_step : UInt8 = 0x00
  @dividing_ratio : UInt8 = 0x00

  @counter_selection : Bool = true

  def reload_period : Nil
    @period = (@dividing_ratio == 0 ? 8 : 16 * @dividing_ratio) << @shift_clock_frequency
  end

  def step_wave_generation : Nil
    new_bit = (@lfsr & 0b01) ^ ((@lfsr & 0b10) >> 1)
    @lfsr >>= 1
    @lfsr |= new_bit << 14
    if @counter_step != 0
      @lfsr &= ~(1 << 6)
      @lfsr |= new_bit << 6
    end
  end

  def get_amplitude : Float32
    if @dac_enabled
      (~@lfsr & 0x1).to_f32 * @volume / 15
    else
      0_f32
    end
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF20 then 0xFF_u8 # I assume this is write-only like in the tone channels, although the pandocs say differently
    when 0xFF21 then self.volume_envelope
    when 0xFF22 then (@shift_clock_frequency << 4) | (@counter_step << 3) | @dividing_ratio
    when 0xFF23 then 0xBF_u8 | (@counter_selection ? 0x40 : 0)
    else             raise "Reading from invalid channel 4 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF20 then @remaining_length = 64_u8 - (value & 0x3F)
    when 0xFF21 then self.volume_envelope = value
    when 0xFF22
      @shift_clock_frequency = value >> 4
      @counter_step = (value >> 3) & 0x1
      @dividing_ratio = value & 0x7
    when 0xFF23
      @counter_selection = value & 0x40 != 0
      trigger = value & (0x1 << 7) != 0
      if trigger
        puts "#{typeof(self)} -- trigger"
        @enabled = true
        @remaining_length = 64 if @remaining_length == 0
        reload_period
        reset_volume_envelope
        @lfsr = 0x7FFF_u16
      end
    else raise "Writing to invalid channel 4 register: #{hex_str index.to_u16!}"
    end
  end
end
