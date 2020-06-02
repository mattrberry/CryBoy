lib LibSDL
  fun queue_audio = SDL_QueueAudio(dev : AudioDeviceID, data : Void*, len : UInt32) : Int
  fun get_queued_audio_size = SDL_GetQueuedAudioSize(dev : AudioDeviceID) : UInt32
  fun delay = SDL_Delay(ms : UInt32) : Nil
end

abstract class SoundChannel
  # useful for mapping memory
  # inheriting classes must define @RANGE
  def ===(value) : Bool
    @RANGE.includes? value
  end

  abstract def [](index : Int) : UInt8
  abstract def []=(index : Int, value : UInt8) : Nil
end

# tone & sweep
class Channel1 < SoundChannel # todo: sweep
  @RANGE = 0xFF10..0xFF14

  property sweep : UInt8 = 0x00
  property wave_pattern_duty : UInt8 = 0x00
  property sound_length_data : UInt8 = 0x00

  # envelope
  property volume : UInt8 = 0x00
  property increasing : Bool = false
  property envelope_sweep_number : UInt8 = 0x00

  property frequency : UInt16 = 0x0000
  property trigger : Bool = false
  property counter_selection : Bool = false

  def remaining_length : UInt8
    64_u8 - @sound_length_data
  end

  def remaining_length=(value : UInt8) : Nil
    @sound_length_data = 64_u8 - value
  end

  def length_step : Nil
    if @trigger
      self.remaining_length = 64 if self.remaining_length == 0
      self.remaining_length -= 1 if self.remaining_length > 0
      @trigger = false if self.remaining_length == 0
    end
  end

  def sweep_step : Nil # Todo
  end

  def volume_step : Nil # todo
  end

  def get_amplitude(buffer_pos : Int) : Float32
    if @trigger
      1000_f32 * ((buffer_pos % period) < (period / 2) ? 1 : -1)
    else
      0_f32
    end
  end

  def actual_frequency : Int32
    CPU::CLOCK_SPEED // (32 * (2048 - @frequency))
  end

  def period : Int32
    APU::CHANNELS * APU::SAMPLE_RATE // actual_frequency
  end

  def [](index : Int) : UInt8
    case index
    when 0xFF10 then 0x00_u8
    when 0xFF11 then 0x3F_u8 | (@wave_pattern_duty << 6) # rest is write-only
    when 0xFF12 then (@volume << 4) | (@increasing ? 0x1 << 3 : 0) | @envelope_sweep_number
    when 0xFF13 then 0xFF_u8                                      # write-only
    when 0xFF14 then 0xBF_u8 | ((counter_selection ? 1 : 0) << 6) # rest is write-only
    else             raise "Reading from invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF10
    when 0xFF11
      @wave_pattern_duty = value >> 6
      @sound_length_data = value & 0x3F
    when 0xFF12
      @volume = value >> 4
      @increasing = value & (0x1 << 3) == 1
      @envelope_sweep_number = value & 0x07
    when 0xFF13
      @frequency = (@frequency & 0x700) | value
      puts actual_frequency
    when 0xFF14
      @trigger = value & (0x1 << 7) != 0
      @counter_selection = value & (0x1 << 6) != 0
      @frequency = (@frequency & 0x00FF) | ((value.to_u16 & 0x3) << 8)
      puts actual_frequency
    else raise "Writing to invalid channel 1 register: #{hex_str index.to_u16!}"
    end
  end
end

class APU
  BUFFER_SIZE =  4096
  SAMPLE_RATE = 65536
  CHANNELS    =     2

  FRAME_SEQUENCER_RATE = 512 # Hz

  @channel1 = Channel1.new
  @sound_enabled : Bool = false

  @buffer = StaticArray(Float32, BUFFER_SIZE).new 0
  @buffer_pos = 0
  @cycles = 0_u64
  @frame_sequencer_stage = 0

  def initialize
    @audiospec = LibSDL::AudioSpec.new
    @audiospec.freq = SAMPLE_RATE
    @audiospec.format = LibSDL::AUDIO_F32SYS
    @audiospec.channels = CHANNELS
    @audiospec.samples = BUFFER_SIZE
    @audiospec.callback = nil
    @audiospec.userdata = nil

    @obtained_spec = LibSDL::AudioSpec.new
    raise "Failed to open audio" if LibSDL.open_audio(pointerof(@audiospec), pointerof(@obtained_spec)) > 0
    LibSDL.pause_audio 0

    # (0..10).each do
    #   buffer = new_buffer(hz: 400)
    #   LibSDL.queue_audio 1, pointerof(buffer), BUFFER_SIZE * sizeof(Float32)
    # end
  end

  # def new_buffer(hz : Int) : StaticArray(Float32, 4096)
  #   period = CHANNELS * SAMPLE_RATE // hz
  #   StaticArray(Float32, 4096).new do |i|
  #     if i % period < period // 2
  #       1000_f32
  #     else
  #       -1000_f32
  #     end
  #   end
  # end

  # tick apu forward by specified number of cycles
  def tick(cycles : Int) : Nil
    (0...cycles).each do
      @cycles &+= 1

      # tick frame sequencer
      if @cycles % (CPU::CLOCK_SPEED // FRAME_SEQUENCER_RATE) == 0
        case @frame_sequencer_stage
        when 0
          @channel1.length_step
        when 1 then nil
        when 2
          @channel1.length_step
          @channel1.sweep_step
        when 3 then nil
        when 4
          @channel1.length_step
        when 5 then nil
        when 6
          @channel1.length_step
          @channel1.sweep_step
        when 7
          @channel1.volume_step
        else nil
        end
        @frame_sequencer_stage = 0 if (@frame_sequencer_stage += 1) > 7
      end

      # put 1 frame in buffer
      if @cycles % (CPU::CLOCK_SPEED // SAMPLE_RATE) == 0
        amplitude = @channel1.get_amplitude @buffer_pos
        @buffer[@buffer_pos] = amplitude      # left
        @buffer[@buffer_pos + 1] == amplitude # right
        @buffer_pos += 2
      end

      # push to SDL if buffer is full
      if @buffer_pos >= BUFFER_SIZE
        while LibSDL.get_queued_audio_size(1) > BUFFER_SIZE * sizeof(Float32)
          puts "delay" # never seems to happen
          LibSDL.delay(1)
        end
        LibSDL.queue_audio 1, pointerof(@buffer), BUFFER_SIZE * sizeof(Float32)
        @buffer_pos = 0
      end
    end
  end

  # read from apu memory
  def [](index : Int) : UInt8
    return 0xFF_u8 if !@sound_enabled && index != 0xFF26
    case index
    when @channel1 then @channel1[index]
    when 0xFF26    then 0x70_u8 | (@sound_enabled ? 0x1 << 7 : 0x0) | (@channel1.counter_selection ? 0x1 : 0x0)
    else                0xFF_u8
    end
  end

  # write to apu memory
  def []=(index : Int, value : UInt8) : Nil
    puts "#{hex_str index.to_u16!} -> #{hex_str value}"
    return if !@sound_enabled && index != 0xFF26
    case index
    when @channel1 then @channel1[index] = value
    when 0xFF24
    when 0xFF25
    when 0xFF26 then @sound_enabled = value & 0x80 == 0x80 # todo: bits 0-3
    end
  end
end
