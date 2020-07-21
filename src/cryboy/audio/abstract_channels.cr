abstract class SoundChannel
  property enabled : Bool = false
  @dac_enabled : Bool = false

  # NRx1
  property length_counter = 0
  @cycles_since_length_step : UInt16 = 0x0000

  # NRx4
  @length_enable : Bool = false
  @frequency_timer : UInt32 = 0x00000000

  # step the channel, calling helpers to reload the period and step the wave generation
  def step : Nil
    if @frequency_timer == 0
      reload_frequency_timer
      step_wave_generation
    end
    @frequency_timer -= 1
    # Update frame sequencer counters
    @cycles_since_length_step += 1
  end

  # step the length, disabling the channel if the length counter expires
  def length_step : Nil
    if @length_enable && @length_counter > 0
      @length_counter -= 1
      @enabled = false if @length_counter == 0
    end
    @cycles_since_length_step = 0
  end

  # called when @frequency_timer reaches 0 and on trigger
  abstract def reload_frequency_timer : Nil

  # called when @period reaches 0
  abstract def step_wave_generation : Nil

  abstract def get_amplitude : Float32

  abstract def [](index : Int) : UInt8
  abstract def []=(index : Int, value : UInt8) : Nil
end
