class Timer
  @div_counter = 0_u32
  @tima_counter = 0_u32

  # maps division on cpu cycles from the clock select
  @cycle_dividers = [1024, 16, 64, 256]

  def initialize(@memory : Memory)
  end

  def tick(cycles : Int32) : Nil
    @div_counter += cycles
    if @div_counter >= 256
      self.div &+= 1
      @div_counter -= 256
    end
    @tima_counter += cycles
    while @tima_counter >= @cycle_dividers[clock_select]
      self.tima &+= 1
      @tima_counter -= @cycle_dividers[clock_select]
    end
  end

  def div : UInt8
    @memory[0xFF04]
  end

  def div=(value : UInt8) : UInt8
    @memory.raw_memory[0xFF04] = value
  end

  def tima : UInt8
    @memory[0xFF05]
  end

  def tima=(value : UInt8) : UInt8
    if tima &+ value > tima
      @memory[0xFF05] &+= value
    else
      @memory[0xFF05] = tma
      @memory.timer = true
    end
    tima
  end

  def tma : UInt8
    @memory[0xFF06]
  end

  def tac : UInt8
    @memory[0xFF07]
  end

  def stop? : Bool
    (tac >> 2) & 0x1 == 0
  end

  def clock_select : UInt8
    tac & 0b11
  end
end
