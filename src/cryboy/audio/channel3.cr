class Channel3 < SoundChannel
  def ===(value) : Bool
    value.is_a?(Int) && 0xFF1A <= value <= 0xFF1E || 0xFF30 <= value <= 0xFF3F
  end

  @enabled = false
  property remaining_length = 0
  @volume = 0_f32
  @counter_selection : Bool = true
  @frequency : UInt16 = 0x0000
  @period : Int32 = 0x0000
  @wave_pattern_ram = Bytes.new 32 # stores 32 4-bit values
  @position = 0

  def step : Nil
    @period -= 1
    if @period == 0
      @period = (2048 - @frequency) * 2
      @position = (@position + 1) % 32
    end
  end

  def length_step : Nil
    if @enabled && @remaining_length > 0 && @counter_selection
      @remaining_length -= 1
      @enabled = false if @remaining_length == 0
    end
  end

  def get_amplitude : Float32
    if @enabled
      @volume * @wave_pattern_ram[@position] / 15
    else
      0_f32
    end
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF1A then @enabled ? 0x80_u8 : 0x00_u8
    when 0xFF1B then 0xFF_u8
    when 0xFF1C then 0xFF_u8
    when 0xFF1D then 0xFF_u8
    when 0xFF1E then 0xFF_u8
    when 0xFF30..0xFF3F
      index = index - 0xFF30
      (@wave_pattern_ram[index * 2] << 4) | @wave_pattern_ram[index * 2 + 1]
    else raise "Reading from invalid channel 2 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF1A
      @enabled = value & 0x80 != 0
    when 0xFF1B
      @remaining_length = 256 - (value & 0x3F)
    when 0xFF1C
      case (value >> 5) & 0x3
      when 0 then @volume = 0_f32
      when 1 then @volume = 1_f32
      when 2 then @volume = 0.5_f32
      when 3 then @volume = 0.75_f32
      end
    when 0xFF1D
      @frequency = (@frequency & 0x0700) | value
    when 0xFF1E
      @counter_selection = value & 0x40 != 0
      @frequency = (@frequency & 0x00FF) | ((value.to_u16 & 0x7) << 8)
      trigger = value & (0x1 << 7) != 0
      if trigger
        @remaining_length = 256 if @remaining_length == 0
        @period = (2048 - @frequency) * 2
      end
    when 0xFF30..0xFF3F
      index = index - 0xFF30
      @wave_pattern_ram[index * 2] = value >> 4
      @wave_pattern_ram[index * 2 + 1] = value & 0x0F
    else raise "Writing to invalid channel 2 register: #{hex_str index.to_u16!}"
    end
  end
end