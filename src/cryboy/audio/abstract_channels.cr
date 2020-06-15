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
end
