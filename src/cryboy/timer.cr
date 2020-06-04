class Timer
  @div = 0_u8
  @tima = 0_u8
  @tma = 0_u8
  @tac = 0_u8

  @div_counter = 0_u32
  @tima_counter = 0_u32

  # maps division on cpu cycles from the clock select
  @cycle_dividers = [1024, 16, 64, 256]

  def initialize(@interrupts : Interrupts)
  end

  # tick timer forward by specified number of cycles
  def tick(cycles : Int) : Bool
    timer_interrupt = false
    @div_counter += cycles
    if @div_counter >= 256
      @div &+= 1
      @div_counter -= 256
    end
    if enabled?
      @tima_counter += cycles
      while @tima_counter >= @cycle_dividers[clock_select]
        @tima &+= 1
        @tima_counter -= @cycle_dividers[clock_select]
        if @tima == 0
          @interrupts.timer_interrupt = true
          @tima = @tma
        end
      end
    end
    timer_interrupt
  end

  # read from timer memory
  def [](index : Int) : UInt8
    case index
    when 0xFF04 then @div
    when 0xFF05 then @tima
    when 0xFF06 then @tma
    when 0xFF07 then @tac
    else             raise "Reading from invalid timer register: #{hex_str index.to_u16!}"
    end
  end

  # write to timer memory
  def []=(index : Int, value : UInt8) : Bool
    case index
    when 0xFF04 then @div = 0x00_u8
    when 0xFF05 then @tima = value
    when 0xFF06 then @tma = value
    when 0xFF07 then @tac = value
    else             raise "Writing to invalid timer register: #{hex_str index.to_u16!}"
    end
    return false
  end

  # are timers enabled?
  def enabled? : Bool
    @tac & (0x1 << 2) != 0
  end

  # select timer clock speed
  def clock_select : UInt8
    @tac & 0b11
  end
end
