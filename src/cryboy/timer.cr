class Timer
  @div = 0_u8
  @tima = 0_u8
  @tma = 0_u8
  @enabled = false                      # whether time is enabled
  @clock_select = 0_u8                  # which clock to use
  @divisor = 0                          # which divisor to use
  @cycle_divisors = [1024, 16, 64, 256] # maps clock select to divisor on cpu cycles

  @div_counter = 0_u32
  @tima_counter = 0_u32

  def initialize(@interrupts : Interrupts)
  end

  # tick timer forward by specified number of cycles
  def tick(cycles : Int) : Nil
    @div_counter += cycles
    if @div_counter >= 256
      @div_counter -= 256
      @div &+= 1
    end
    if @enabled
      @tima_counter += cycles
      while @tima_counter >= @divisor # in case divisor has changed
        @tima_counter -= @divisor
        @tima &+= 1
        if @tima == 0
          @interrupts.timer_interrupt = true
          @tima = @tma
        end
      end
    end
  end

  # read from timer memory
  def [](index : Int) : UInt8
    case index
    when 0xFF04 then @div
    when 0xFF05 then @tima
    when 0xFF06 then @tma
    when 0xFF07 then 0xF8_u8 | (@enabled ? 0b100 : 0) | @clock_select
    else             raise "Reading from invalid timer register: #{hex_str index.to_u16!}"
    end
  end

  # write to timer memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF04 then @div = 0x00_u8
    when 0xFF05 then @tima = value
    when 0xFF06 then @tma = value
    when 0xFF07
      @enabled = value & (0x1 << 2) != 0
      @clock_select = value & 0x3
      @divisor = @cycle_divisors[@clock_select]
    else raise "Writing to invalid timer register: #{hex_str index.to_u16!}"
    end
  end
end
