class Timer
  @div : UInt16 = 0x0000       # 16-bit divider register
  @tima : UInt8 = 0x00         # 8-bit timer register
  @tma : UInt8 = 0x00          # value to load when tima overflows
  @enabled : Bool = false      # if timer is enabled
  @clock_select : UInt8 = 0x00 # frequency flag determining when to increment tima
  @bit_for_tima = 9            # bit to detect falling edge for tima increments

  @previous_bit = false # used to detect falling edge
  @countdown = -1       # load tma and set interrupt flag when countdown is 0

  def initialize(@gb : Motherboard)
  end

  def skip_boot : Nil
    @div = 0x2674_u16
  end

  # tick timer forward by specified number of cycles
  def tick(cycles : Int) : Nil
    cycles.times do
      @countdown -= 1 if @countdown > -1
      if @countdown == 0
        @gb.interrupts.timer_interrupt = true
        @tima = @tma
      end

      @div &+= 1
      current_bit = @enabled && (@div & (1 << @bit_for_tima) != 0)
      if @previous_bit && !current_bit
        @tima &+= 1
        @countdown = 4 if @tima == 0
      end

      @previous_bit = current_bit
    end
  end

  # read from timer memory
  def [](index : Int) : UInt8
    case index
    when 0xFF04 then (@div >> 8).to_u8
    when 0xFF05 then @tima
    when 0xFF06 then @tma
    when 0xFF07 then 0xF8_u8 | (@enabled ? 0b100 : 0) | @clock_select
    else             raise "Reading from invalid timer register: #{hex_str index.to_u16!}"
    end
  end

  # write to timer memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF04 then @div = 0x0000_u16
    when 0xFF05
      if @countdown != 0 # ignore writes on cycle that tma is loaded
        @tima = value
        @countdown = -1 # abort interrupt and tma load
      end
    when 0xFF06
      @tma = value
      @tima = @tma if @countdown == 0 # write to tima on cycle that tma is loaded
    when 0xFF07
      @enabled = value & 0b100 != 0
      @clock_select = value & 0b011
      @bit_for_tima = case @clock_select
                      when 0b00 then 9
                      when 0b01 then 3
                      when 0b10 then 5
                      when 0b11 then 7
                      else           raise "Selecting bit for TIMA. Will never be reached."
                      end
    else raise "Writing to invalid timer register: #{hex_str index.to_u16!}"
    end
  end
end
