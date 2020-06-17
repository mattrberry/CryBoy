class Channel4
  def ===(value) : Bool
    value.is_a?(Int) && 0xFF20 <= value <= 0xFF23
  end

  @lfsr : UInt16 = 0x0000
  @output = 0

  property remaining_length : UInt8 = 0x00

  # envelope
  @initial_volume : UInt8 = 0x00
  @volume : UInt8 = 0x00
  @increasing : Bool = false
  @envelope_sweep_number : UInt8 = 0x00
  @env_sweep_counter : UInt8 = 0x00

  @shift_clock_frequency : UInt8 = 0x00
  @counter_step : UInt8 = 0x00
  @dividing_ratio : UInt8 = 0x00
  @period : Int32 = 0x0000

  @enabled : Bool = false
  @counter_selection : Bool = true

  def step : Nil
    @period -= 1
    if @period == 0
      @period = (@dividing_ratio == 0 ? 8 : 16 * @dividing_ratio) << @shift_clock_frequency

      new_bit = (@lfsr & 0b01) ^ ((@lfsr & 0b10) >> 1)
      @lfsr >>= 1
      @lfsr |= new_bit << 14
      if @counter_selection != 0
        @lfsr &= ~(1 << 6)
        @lfsr |= new_bit << 6
      end
    end
  end

  def length_step : Nil
    if @remaining_length > 0 && @counter_selection
      @remaining_length -= 1
    end
  end

  def volume_step : Nil
    if @envelope_sweep_number != 0
      if @env_sweep_counter == 0
        @env_sweep_counter = @envelope_sweep_number
        @volume += (@increasing ? 1 : -1) if (@volume < 0xF && @increasing) || (@volume > 0x0 && !@increasing)
      end
      @env_sweep_counter -= 1
    end
  end

  def get_amplitude : Float32
    (~@lfsr & 0x1).to_f32 * @volume / 15
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF20 then 64_u8 - @remaining_length
    when 0xFF21 then (@initial_volume << 4) | (@increasing ? 0x08 : 0) | @envelope_sweep_number
    when 0xFF22 then (@shift_clock_frequency << 4) | (@counter_step << 3) | @dividing_ratio
    when 0xFF23 then @counter_selection ? 0x40_u8 : 0x00_u8
    else             raise "Reading from invalid channel 4 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF20
      @remaining_length = 64_u8 - (value & 0x3F)
    when 0xFF21
      @initial_volume = value >> 4
      @increasing = value & 0x08 != 0
      @envelope_sweep_number = value & 0x07
    when 0xFF22
      @shift_clock_frequency = value >> 4
      @counter_step = (value >> 3) & 0x1
      @dividing_ratio = value & 0x7
    when 0xFF23
      enabled = value & 0x80 != 0
      @counter_selection = value & 0x40 != 0
      if enabled
        @remaining_length = 64 if @remaining_length == 0
        @period = (@dividing_ratio == 0 ? 8 : 16 * @dividing_ratio) << @shift_clock_frequency
        @volume = @initial_volume
        @env_sweep_counter = @envelope_sweep_number
        @lfsr = 0x7FFF_u16
        @lfsr = 0x4040_u16
      end
    else raise "Writing to invalid channel 4 register: #{hex_str index.to_u16!}"
    end
  end
end
