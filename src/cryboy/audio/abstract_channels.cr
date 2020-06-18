abstract class SoundChannel
  # allow channels to define the memory they map to
  # this works because Crystal's case..when syntax uses ===
  abstract def ===(value) : Bool

  @dac_enabled = true
  @enabled = false

  def enabled : Bool
    @dac_enabled && @enabled
  end

  abstract def get_amplitude : Float32

  abstract def [](index : Int) : UInt8
  abstract def []=(index : Int, value : UInt8) : Nil
end

abstract class Tone < SoundChannel
  @wave_pattern_duty : UInt8 = 0x00
  @wave_duty_pos : UInt8 = 0
  @wave_duty = [
    [0, 0, 0, 0, 0, 0, 0, 1], # 12.5%
    [1, 0, 0, 0, 0, 0, 0, 1], # 25%
    [1, 0, 0, 0, 0, 1, 1, 1], # 50%
    [0, 1, 1, 1, 1, 1, 1, 0], # 75%
  ]
  @remaining_length : UInt8 = 0x00

  # envelope
  @initial_volume : UInt8 = 0x00
  @volume : UInt8 = 0x00
  @increasing : Bool = false
  @envelope_sweep_number : UInt8 = 0x00
  @env_sweep_counter : UInt8 = 0x00

  @frequency : UInt16 = 0x0000
  @period : Int32 = 0x0000
  @counter_selection : Bool = true

  def step : Nil
    @period -= 1
    if @period <= 0
      @period = (2048 - @frequency) * 4
      @wave_duty_pos = (@wave_duty_pos + 1) % 8
    end
  end

  def length_step : Nil
    if @remaining_length > 0 && @counter_selection
      @remaining_length -= 1
      @enabled = false if @remaining_length == 0
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
    if @dac_enabled
      @wave_duty[@wave_pattern_duty][@wave_duty_pos].to_f32 * @volume / 15
    else
      0_f32
    end
  end

  def wavepattern_soundlength : UInt8
    0x3F_u8 | (@wave_pattern_duty << 6) # rest is write-only
  end

  def wavepattern_soundlength=(value : UInt8) : Nil
    @wave_pattern_duty = value >> 6
    @remaining_length = 64_u8 - (value & 0x3F)
  end

  def volume_envelope : UInt8
    (@initial_volume << 4) | (@increasing ? 0x08 : 0) | @envelope_sweep_number
  end

  def volume_envelope=(value : UInt8) : Nil
    if value & 0xF8 == 0
      @dac_enabled = false
      @enabled = false
    elsif value & 0x10 > 0
      @dac_enabled = true
    end
    @initial_volume = value >> 4
    @increasing = value & 0x08 != 0
    @envelope_sweep_number = value & 0x07
  end

  def frequency_lo : UInt8
    0xFF_u8 # write-only
  end

  def frequency_lo=(value : UInt8) : Nil
    @frequency = (@frequency & 0x0700) | value
  end

  def frequency_hi : UInt8
    0xBF_u8 | ((@counter_selection ? 1 : 0) << 6) # rest is write-only
  end

  def frequency_hi=(value : UInt8) : Nil
    @counter_selection = value & 0x40 != 0
    @frequency = (@frequency & 0x00FF) | ((value.to_u16 & 0x7) << 8)
    trigger = value & (0x1 << 7) != 0
    @enabled = true if trigger
    if trigger
      @remaining_length = 64 if @remaining_length == 0
      @period = (2048 - @frequency) * 4
      @volume = @initial_volume
      @env_sweep_counter = @envelope_sweep_number
    end
  end
end
