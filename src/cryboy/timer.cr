class Timer
  @div = 0_u16      # 16-bit divider register
  @tima = 0_u8      # 8-bit timer register
  @bit_for_tima = 9 # bit to detect for tima increments
  @tma = 0_u8       # value to load when tima overflows
  @enabled = false  # if timer is enabled

  @clock_select = 0_u8           # clock in use, used for reading 0xFF07
  @cycles_until_tima_update = -1 # tima update and interrupt flag are delayed by 4 cycles

  def initialize(@interrupts : Interrupts)
  end

  # tick timer forward by specified number of cycles
  def tick(cycles : Int) : Nil
    while cycles > 0
      cycles -= 1
      self.div &+= 1 # step forwards div register (handles tima updates)
      tick_tima_delay
    end
  end

  # handle timer register overflow delay
  def tick_tima_delay : Nil
    if @cycles_until_tima_update > -1
      if @cycles_until_tima_update == 0
        @interrupts.timer_interrupt = true
        @tima = @tma
      end
      @cycles_until_tima_update -= 1
    end
  end

  # handle obscure timer behavior based on updates to div register
  def div=(new_div : UInt16) : Nil
    if @enabled
      if (@div & (1 << @bit_for_tima)) != 0 && (new_div & (1 << @bit_for_tima)) == 0 # falling edge
        @tima &+= 1
        @cycles_until_tima_update = 5 if @tima == 0 # initiate delay for interrupt and tma load
      end
    end
    @div = new_div
  end

  # get div register
  def div : UInt16
    @div
  end

  # read from timer memory
  def [](index : Int) : UInt8
    case index
    when 0xFF04 then (self.div >> 8).to_u8
    when 0xFF05 then @tima
    when 0xFF06 then @tma
    when 0xFF07 then 0xF8_u8 | (@enabled ? 0b100 : 0) | @clock_select
    else             raise "Reading from invalid timer register: #{hex_str index.to_u16!}"
    end
  end

  # write to timer memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF04 then self.div = 0x0000_u16 # reset div on write
    when 0xFF05
      if @cycles_until_tima_update != 0
        @tima = value
        @cycles_until_tima_update = -1 # prevent immediate load from tma
      end
    when 0xFF06 then @tma = value
    when 0xFF07
      disabled = value & (0b100) == 0
      self.div = 0x0000_u16 if disabled # reset div on disable (todo, this is wrong)
      @enabled = !disabled
      @clock_select = value & 0b011
      @bit_for_tima = case @clock_select
                      when 0b00 then 9 # 4194   Hz (clock / 1024)
                      when 0b01 then 3 # 268400 Hz (clock / 16)
                      when 0b10 then 5 # 67110  Hz (clock / 64)
                      when 0b11 then 7 # 16780  Hz (clock / 256)
                      else           raise "Not possible #{@clock_select}"
                      end
    else raise "Writing to invalid timer register: #{hex_str index.to_u16!}"
    end
  end
end
