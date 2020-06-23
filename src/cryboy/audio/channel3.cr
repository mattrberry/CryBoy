class Channel3 < SoundChannel
  @@RANGE = 0xFF1A..0xFF1E
  class_getter wave_ram = 0xFF30..0xFF3F

  def ===(value) : Bool
    value.is_a?(Int) && @@RANGE.includes?(value) || @@wave_ram.includes?(value)
  end

  @remaining_length = 0
  @output_level_raw = 0_u8
  @volume = 0_f32
  @counter_selection : Bool = true
  @frequency : UInt16 = 0x0000
  @wave_pattern_ram = Bytes.new 32 # stores 32 4-bit values
  @position = 0

  def reload_period : Nil
    @period = (2048 - @frequency) * 2
  end

  def step_wave_generation : Nil
    @position = (@position + 1) % 32
  end

  def get_amplitude : Float32
    if @dac_enabled
      @volume * @wave_pattern_ram[@position] / 15
    else
      0_f32
    end
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF1A then 0x7F_u8 | (@dac_enabled ? 0x80 : 0x00)
    when 0xFF1B then 0xFF_u8 # I assume this is write-only like in the tone channels
    when 0xFF1C then 0x9F_u8 | @output_level_raw
    when 0xFF1D then 0xFF_u8                                       # write-only
    when 0xFF1E then 0xBF_u8 | ((@counter_selection ? 1 : 0) << 6) # rest is write-only
    when 0xFF30..0xFF3F
      index = index - 0xFF30
      (@wave_pattern_ram[index * 2] << 4) | @wave_pattern_ram[index * 2 + 1]
    else raise "Reading from invalid channel 3 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF1A
      if value & 0x80 == 0
        disable_channel
      else
        enable_dac
      end
    when 0xFF1B then @remaining_length = 256 - value
    when 0xFF1C
      @output_level_raw = value
      case (value >> 5) & 0x3
      when 0 then @volume = 0_f32
      when 1 then @volume = 1_f32
      when 2 then @volume = 0.5_f32
      when 3 then @volume = 0.75_f32
      end
    when 0xFF1D then @frequency = (@frequency & 0x0700) | value
    when 0xFF1E
      @counter_selection = value & 0x40 != 0
      @frequency = (@frequency & 0x00FF) | ((value.to_u16 & 0x7) << 8)
      trigger = value & (0x1 << 7) != 0
      if trigger
        puts "#{typeof(self)} -- trigger"
        @enabled = true
        @remaining_length = 256 if @remaining_length == 0
        reload_period
        @position = 0
      end
    when 0xFF30..0xFF3F
      index = index - 0xFF30
      @wave_pattern_ram[index * 2] = value >> 4
      @wave_pattern_ram[index * 2 + 1] = value & 0x0F
    else raise "Writing to invalid channel 3 register: #{hex_str index.to_u16!}"
    end
  end
end
