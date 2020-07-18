class Channel1
  WAVE_DUTY = [
    [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
    [1, 0, 0, 0, 0, 0, 0, 1], # 25%
    [1, 0, 0, 0, 0, 1, 1, 1], # 50%
    [0, 1, 1, 1, 1, 1, 1, 0], # 75%
  ]

  RANGE = 0xFF10..0xFF14

  def ===(value) : Bool
    value.is_a?(Int) && RANGE.includes?(value)
  end

  property enabled : Bool = false
  @dac_enabled : Bool = false

  @wave_duty_position = 0
  @wave_duty_timer = 0

  # NR10
  @sweep_period : UInt8 = 0x00
  @negate : Bool = false
  @shift : UInt8 = 0x00

  @sweep_timer : UInt8 = 0x00
  @frequency_shadow : UInt16 = 0x0000
  @sweep_enabled : Bool = false

  # NR11
  @duty : UInt8 = 0x00
  @length_load : UInt8 = 0x00

  @length_counter : UInt8 = 0x00

  # NR12
  @starting_volume : UInt8 = 0x00
  @envelope_add_mode : Bool = false
  @period : UInt8 = 0x00

  @volume_envelope_timer : UInt8 = 0x00
  @current_volume : UInt8 = 0x00

  # NR13 / NR14
  @frequency : UInt16 = 0x00
  @length_enable : Bool = false

  @frequency_timer : UInt16 = 0x0000

  def step : Nil
    if @frequency_timer == 0
      @frequency_timer = (2048_u16 - @frequency) * 4
      @wave_duty_position = (@wave_duty_position + 1) % 8
    end
    @frequency_timer -= 1
  end

  def length_step : Nil
    if @length_enable # should the length counter be respected
      @length_counter -= 1 if @length_counter > 0
      @enabled = false if @length_counter == 0
    end
  end

  def sweep_step : Nil
    if @sweep_enabled && @sweep_period > 0
      calculated = frequency_calculation
      if calculated <= 0x07FF && @shift > 0
        @frequency_shadow = @frequency = calculated
        frequency_calculation
      end
    end
  end

  def volume_step : Nil
    if @period != 0
      if @volume_envelope_timer == 0
        @volume_envelope_timer = @period
        if (@current_volume < 0xF && @envelope_add_mode) || (@current_volume > 0 && !@envelope_add_mode)
          @current_volume += (@envelope_add_mode ? 1 : -1)
        end
      end
      @volume_envelope_timer -= 1
    end
  end

  def get_amplitude : Float32
    if @enabled && @dac_enabled
      WAVE_DUTY[@duty][@wave_duty_position] * @current_volume / 0xF
    else
      0
    end.to_f32
  end

  # Calculate the new shadow frequency, disable channel if overflow 11 bits
  # https://gist.github.com/drhelius/3652407#file-game-boy-sound-operation-L243-L250
  def frequency_calculation : UInt16
    calculated = @frequency_shadow >> @shift
    calculated = @frequency_shadow + (@negate ? -1 : 1) * calculated
    @enabled = false if calculated > 0x07FF
    calculated
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF10 then 0x80 | @sweep_period << 4 | (@negate ? 0x08 : 0) | @shift
    when 0xFF11 then 0x3F | @duty << 6
    when 0xFF12 then @starting_volume << 4 | (@envelope_add_mode ? 0x08 : 0) | @period
    when 0xFF13 then 0xFF # write-only
    when 0xFF14 then 0xBF | (@length_enable ? 0x40 : 0)
    else             raise "Reading from invalid Channel1 register: #{hex_str index.to_u16}"
    end.to_u8
  end

  def []=(index : Int, value : UInt8) : Nil
    puts "#{hex_str index.to_u16} -> #{hex_str value}"
    case index
    when 0xFF10
      @sweep_period = (value & 0x70) >> 4
      @negate = value & 0x08 > 0
      @shift = value & 0x07
    when 0xFF11
      @duty = (value & 0xC0) >> 6
      @length_load = value & 0x3F
      # Internal values
      @length_counter = 0x40_u8 - @length_load
    when 0xFF12
      @starting_volume = value >> 4
      @envelope_add_mode = value & 0x08 > 0
      @period = value & 0x07
      # Internal values
      @dac_enabled = value & 0xF8 > 0
      @enabled = false if !@dac_enabled
    when 0xFF13
      @frequency = (@frequency & 0x0700) | value
    when 0xFF14
      @frequency = (@frequency & 0x00FF) | (value.to_u16 & 0x07) << 8
      @length_enable = value & 0x40 > 0
      trigger = value & 0x80 > 0
      if trigger
        puts "triggered"
        puts "  NR10:      sweep_period:#{@sweep_period}, negate:#{@negate}, shift:#{@shift}"
        puts "  NR11:      duty:#{@duty}, length_load:#{@length_load}"
        puts "  NR12:      starting_volume:#{@starting_volume}, envelope_add_mode:#{@envelope_add_mode}, period:#{@period}"
        puts "  NR13/NR14: frequency:#{@frequency}, length_enable:#{@length_enable}"
        @enabled = true
        # init length
        @length_counter = 0x40 if @length_counter == 0
        # init frequency
        @frequency_timer = (2048_u16 - @frequency) * 4
        # init volume envelope
        @volume_envelope_timer = @period
        @current_volume = @starting_volume
        # init sweep
        @frequency_shadow = @frequency
        @sweep_timer = @sweep_period
        @sweep_enabled = @sweep_period > 0 || @shift > 0
        if @shift > 0 # if sweep shift is non-zero, frequency calculation and overflow check are performed immediately
          frequency_calculation
        end
      end
    else raise "Writing to invalid Channel1 register: #{hex_str index.to_u16}"
    end
  end
end
