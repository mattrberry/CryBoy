abstract class SoundChannel
  # used for mapping memory
  # inheriting classes must define @RANGE
  def ===(value) : Bool
    @RANGE.includes? value
  end

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
  property remaining_length : UInt8 = 0x00

  # envelope
  @initial_volume : UInt8 = 0x00
  @volume : UInt8 = 0x00
  @increasing : Bool = false
  @envelope_sweep_number : UInt8 = 0x00
  @current_envelope_sweep : UInt8 = 0x00

  @frequency : UInt16 = 0x0000
  @period : Int32 = 0x0000
  @trigger : Bool = false
  getter counter_selection : Bool = false

  @amp_count = 0

  def length_step : Nil
    if @trigger
      @remaining_length = 64 if @remaining_length == 0
      @remaining_length -= 1 if @remaining_length > 0
      @trigger = false if @remaining_length == 0
    end
  end

  def volume_step : Nil # todo
    if @current_envelope_sweep > 0 && ((@volume < 0xF && @increasing) || (@volume > 0x0 && !@increasing))
      @volume += (@increasing ? 1 : -1)
      @current_envelope_sweep -= 1
    end
  end

  def get_amplitude : Float32
    if @trigger
      @amp_count += 1
      if @amp_count >= @period // 8
        @amp_count -= @period // 8
        @wave_duty_pos = (@wave_duty_pos + 1) % 8
      end
      @wave_duty[@wave_pattern_duty][@wave_duty_pos].to_f32 * @volume / 15
    else
      @amp_count = 0
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
    (@initial_volume << 4) | (@increasing ? 0x1 << 3 : 0) | @envelope_sweep_number
  end

  def volume_envelope=(value : UInt8) : Nil
    @initial_volume = value >> 4
    @increasing = value & (0x1 << 3) != 0
    @envelope_sweep_number = value & 0x07
  end

  def frequency_lo : UInt8
    0xFF_u8 # write-only
  end

  def frequency_lo=(value : UInt8) : Nil
    @frequency = (@frequency & 0x700) | value
    # clock on every APU sample
    @period = APU::SAMPLE_RATE // (CPU::CLOCK_SPEED // (8 * (2048 - @frequency)))
  end

  def frequency_hi : UInt8
    0xBF_u8 | ((@counter_selection ? 1 : 0) << 6) # rest is write-only
  end

  def frequency_hi=(value : UInt8) : Nil
    @trigger = value & (0x1 << 7) != 0
    if @trigger
      @volume = @initial_volume
      @current_envelope_sweep = @envelope_sweep_number
    end
    @counter_selection = value & (0x1 << 6) != 0
    @frequency = (@frequency & 0x00FF) | ((value.to_u16 & 0x3) << 8)
    # clock on every APU sample
    @period = APU::SAMPLE_RATE // (CPU::CLOCK_SPEED // (8 * (2048 - @frequency)))
  end
end
