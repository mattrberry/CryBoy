class Channel2 < SoundChannel
  WAVE_DUTY = [
    [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
    [1, 0, 0, 0, 0, 0, 0, 1], # 25%
    [1, 0, 0, 0, 0, 1, 1, 1], # 50%
    [0, 1, 1, 1, 1, 1, 1, 0], # 75%
  ]

  RANGE = 0xFF16..0xFF19

  def ===(value) : Bool
    value.is_a?(Int) && RANGE.includes?(value)
  end

  @wave_duty_position = 0

  # NR21
  @duty : UInt8 = 0x00
  @length_load : UInt8 = 0x00

  # NR22
  @starting_volume : UInt8 = 0x00
  @envelope_add_mode : Bool = false
  @period : UInt8 = 0x00

  @volume_envelope_timer : UInt8 = 0x00
  @current_volume : UInt8 = 0x00

  # NR23 / NR24
  @frequency : UInt16 = 0x00

  def step_wave_generation : Nil
    @wave_duty_position = (@wave_duty_position + 1) % 8
  end

  def reload_frequency_timer : Nil
    @frequency_timer = (2048_u32 - @frequency) * 4
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
      dac_input = WAVE_DUTY[@duty][@wave_duty_position] * @current_volume
      dac_output = (dac_input / 7.5) - 1
      dac_output
    else
      0
    end.to_f32
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF16 then 0x3F | @duty << 6
    when 0xFF17 then @starting_volume << 4 | (@envelope_add_mode ? 0x08 : 0) | @period
    when 0xFF18 then 0xFF # write-only
    when 0xFF19 then 0xBF | (@length_enable ? 0x40 : 0)
    else             raise "Reading from invalid Channel2 register: #{hex_str index.to_u16}"
    end.to_u8
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF16
      @duty = (value & 0xC0) >> 6
      @length_load = value & 0x3F
      # Internal values
      @length_counter = 0x40 - @length_load
    when 0xFF17
      @starting_volume = value >> 4
      @envelope_add_mode = value & 0x08 > 0
      @period = value & 0x07
      # Internal values
      @dac_enabled = value & 0xF8 > 0
      @enabled = false if !@dac_enabled
    when 0xFF18
      @frequency = (@frequency & 0x0700) | value
    when 0xFF19
      @frequency = (@frequency & 0x00FF) | (value.to_u16 & 0x07) << 8
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
        puts "  NR16:      duty:#{@duty}, length_load:#{@length_load}"
        puts "  NR17:      starting_volume:#{@starting_volume}, envelope_add_mode:#{@envelope_add_mode}, period:#{@period}"
        puts "  NR18/NR19: frequency:#{@frequency}, length_enable:#{@length_enable}"
        @enabled = true if @dac_enabled
        # Init length
        if @length_counter == 0
          @length_counter = 0x40
          # Obscure length counter behavior #2
          @length_counter -= 1 if @length_enable && @cycles_since_length_step < 2 ** 13
        end
        # Init frequency
        @frequency_timer = (0x800_u32 - @frequency) * 4
        # Init volume envelope
        @volume_envelope_timer = @period
        @current_volume = @starting_volume
      end
    else raise "Writing to invalid Channel2 register: #{hex_str index.to_u16}"
    end
  end
end
