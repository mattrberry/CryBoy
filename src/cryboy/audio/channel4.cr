class Channel4 < SoundChannel
  RANGE = 0xFF20..0xFF23

  def ===(value) : Bool
    value.is_a?(Int) && RANGE.includes?(value)
  end

  @lfsr : UInt16 = 0x0000

  # NR41
  @length_load : UInt8 = 0x00

  # NR42
  @starting_volume : UInt8 = 0x00
  @envelope_add_mode : Bool = false
  @period : UInt8 = 0x00

  @volume_envelope_timer : UInt8 = 0x00
  @current_volume : UInt8 = 0x00

  # NR43
  @clock_shift : UInt8 = 0x00
  @width_mode : UInt8 = 0x00
  @divisor_code : UInt8 = 0x00

  def step_wave_generation : Nil
    new_bit = (@lfsr & 0b01) ^ ((@lfsr & 0b10) >> 1)
    @lfsr >>= 1
    @lfsr |= new_bit << 14
    if @width_mode != 0
      @lfsr &= ~(1 << 6)
      @lfsr |= new_bit << 6
    end
  end

  def reload_frequency_timer : Nil
    @frequency_timer = (@divisor_code == 0 ? 8_u32 : @divisor_code.to_u32 << 4) << @clock_shift
  end

  def volume_step : Nil
    if @period != 0
      @volume_envelope_timer -= 1 if @volume_envelope_timer > 0
      if @volume_envelope_timer == 0
        @volume_envelope_timer = @period
        if (@current_volume < 0xF && @envelope_add_mode) || (@current_volume > 0 && !@envelope_add_mode)
          @current_volume += (@envelope_add_mode ? 1 : -1)
        end
      end
    end
  end

  def get_amplitude : Float32
    if @enabled && @dac_enabled
      dac_input = (~@lfsr & 1) * @current_volume
      dac_output = (dac_input / 7.5) - 1
      dac_output
    else
      0
    end.to_f32
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF20 then 0xFF
    when 0xFF21 then @starting_volume << 4 | (@envelope_add_mode ? 0x08 : 0) | @period
    when 0xFF22 then @clock_shift << 4 | @width_mode << 3 | @divisor_code
    when 0xFF23 then 0xBF | (@length_enable ? 0x40 : 0)
    else             raise "Reading from invalid Channel4 register: #{hex_str index.to_u16}"
    end.to_u8
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF20
      @length_load = value & 0x3F
      # Internal values
      @length_counter = 0x40 - @length_load
    when 0xFF21
      @starting_volume = value >> 4
      @envelope_add_mode = value & 0x08 > 0
      @period = value & 0x07
      # Internal values
      @dac_enabled = value & 0xF8 > 0
      @enabled = false if !@dac_enabled
    when 0xFF22
      @clock_shift = value >> 4
      @width_mode = (value & 0x08) >> 3
      @divisor_code = value & 0x07
    when 0xFF23
      length_enable = value & 0x40 > 0
      # Obscure length counter behavior #1
      if @cycles_since_length_step < 2 ** 13 && !@length_enable && length_enable && @length_counter > 0
        @length_counter -= 1
        @enabled = false if @length_counter == 0
      end
      @length_enable = length_enable
      trigger = value & 0x80 > 0
      if trigger
        puts "triggered"
        puts "  NR41: length_load:#{@length_load}"
        puts "  NR42: starting_volume:#{@starting_volume}, envelope_add_mode:#{@envelope_add_mode}, period:#{@period}"
        puts "  NR43: clock_shift:#{@clock_shift}, width_mode:#{@width_mode}, divisor_code:#{@divisor_code}"
        puts "  NR44: length_enable:#{@length_enable}"
        @enabled = true if @dac_enabled
        # Init length
        if @length_counter == 0
          @length_counter = 0x40
          # Obscure length counter behavior #2
          @length_counter -= 1 if @length_enable && @cycles_since_length_step < 2 ** 13
        end
        # Init frequency
        @frequency_timer = (@divisor_code == 0 ? 8_u32 : @divisor_code.to_u32 << 4) << @clock_shift
        # Init volume envelope
        @volume_envelope_timer = @period
        @current_volume = @starting_volume
        # Init lfsr
        @lfsr = 0x7FFF
      end
    else raise "Writing to invalid Channel4 register: #{hex_str index.to_u16}"
    end
  end
end
