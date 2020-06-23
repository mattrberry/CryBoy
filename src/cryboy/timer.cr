class Timer
  @div : UInt16 = 0x0000       # 16-bit divider register
  @tima : UInt8 = 0x00         # 8-bit timer register
  @tma : UInt8 = 0x00          # value to load when tima overflows
  @enabled : Bool = false      # if timer is enabled
  @clock_select : UInt8 = 0x00 # frequency flag determining when to increment tima
  @bit_for_tima = 9            # bit to detect falling edge for tima increments

  @previous = false

  @countdown = -1

  def initialize(@interrupts : Interrupts)
  end

  # tick timer forward by specified number of cycles
  def tick(cycles : Int) : Nil
    while cycles > 0
      # puts "===== incrementing cycle. tima: #{@tima}"
      # puts "ticking div from #{hex_str @div} to #{hex_str (@div &+ 1)}, countdown: #{@countdown}"
      cycles -= 1

      @countdown -= 1 if @countdown > -1
      # puts "decrementing countdown to #{@countdown - 1}" if @countdown > -1
      if @countdown == 0
        # puts "loading tma and setting interrupt flag"
        @interrupts.timer_interrupt = true
        @tima = @tma
      end

      @div &+= 1
      current = @enabled && (@div & (1 << @bit_for_tima) != 0)
      if @previous && !current
        @tima &+= 1
        # puts "setting countdown to 4" if @tima == 0
        @countdown = 4 if @tima == 0
      end
      @previous = current
      # puts "----- done incrementing cycle. tima: #{@tima}"
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
    when 0xFF04
      @div = 0x0000_u16
    when 0xFF05
      # puts "TIMA: #{hex_str value}, countdown: #{@countdown}"
      if @countdown != 0 # ignore writes on cycle that tma is loaded
        @tima = value
        @countdown = -1 # abort interrupt and tma load
      end
    when 0xFF06
      # puts "TMA: #{hex_str value}, countdown: #{@countdown}"
      @tma = value
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
