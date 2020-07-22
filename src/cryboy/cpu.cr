class CPU
  CLOCK_SPEED = 4194304

  macro register(upper, lower, mask = nil)
    @{{upper.id}} : UInt8 = 0_u8
    @{{lower.id}} : UInt8 = 0_u8

    def {{upper.id}} : UInt8
      @{{upper.id}} {% if mask %} & ({{mask.id}} >> 8) {% end %}
    end

    def {{upper.id}}=(value : UInt8) : UInt8
      @{{upper.id}} = value {% if mask %} & ({{mask.id}} >> 8) {% end %}
    end

    def {{lower.id}} : UInt8
      @{{lower.id}} {% if mask %} & {{mask.id}} {% end %}
    end

    def {{lower.id}}=(value : UInt8) : UInt8
      @{{lower.id}} = value {% if mask %} & {{mask.id}} {% end %}
    end

    def {{upper.id}}{{lower.id}} : UInt16
      (self.{{upper}}.to_u16 << 8 | self.{{lower}}.to_u16).not_nil!
    end

    def {{upper.id}}{{lower.id}}=(value : UInt16) : UInt16
      self.{{upper.id}} = (value >> 8).to_u8
      self.{{lower.id}} = (value & 0xFF).to_u8
      self.{{upper.id}}{{lower.id}}
    end

    def {{upper.id}}{{lower.id}}=(value : UInt8) : UInt16
      self.{{upper.id}} = 0_u8
      self.{{lower.id}} = value
      self.{{upper.id}}{{lower.id}}
    end
  end

  macro flag(name, mask)
    def f_{{name.id}}=(on : Int | Bool)
      if on == false || on == 0
        self.f &= ~{{mask}}
      else
        self.f |= {{mask.id}}
      end
    end

    def f_{{name.id}} : Bool
      self.f & {{mask.id}} == {{mask.id}}
    end

    def f_n{{name.id}} : Bool
      !f_{{name.id}}
    end
  end

  register a, f, mask: 0xFFF0
  register b, c
  register d, e
  register h, l

  flag z, 0b10000000
  flag n, 0b01000000
  flag h, 0b00100000
  flag c, 0b00010000

  property pc = 0x0000_u16
  property sp = 0x0000_u16
  getter ime = false
  @ime_enable = 0 # enable ime after this many instructions
  property halted = false
  property memory

  # hl reads are cached for each instruction
  # this is tracked here to reduce complications in the codegen
  @cached_hl_read : UInt8? = nil

  def initialize(@memory : Memory, @interrupts : Interrupts, @ppu : PPU, @apu : APU, @timer : Timer, boot = false)
    skip_boot if !boot
  end

  def skip_boot
    # https://gbdev.io/pandocs/#power-up-sequence
    @pc = 0x0100_u16
    @sp = 0xFFFE_u16
    self.af = 0x1180_u16
    self.bc = 0x0000_u16
    self.de = 0x0008_u16
    self.hl = 0x007C_u16
    @memory.skip_boot
  end

  # call to the specified interrupt vector and handle ime/halted flags
  def call_interrupt_vector(vector : UInt16) : Nil
    @ime = false
    @sp -= 2
    @memory[@sp] = @pc
    @pc = vector
    @halted = false
    @memory.tick_extra 20
  end

  # service all interrupts
  def handle_interrupts
    @halted = false if @interrupts[0xFF0F] & @interrupts[0xFFFF] & 0x1F > 0
    if @ime
      if @interrupts.vblank_interrupt && @interrupts.vblank_enabled
        @interrupts.vblank_interrupt = false
        call_interrupt_vector 0x0040_u16
      elsif @interrupts.lcd_stat_interrupt && @interrupts.lcd_stat_enabled
        @interrupts.lcd_stat_interrupt = false
        call_interrupt_vector 0x0048_u16
      elsif @interrupts.timer_interrupt && @interrupts.timer_enabled
        @interrupts.timer_interrupt = false
        call_interrupt_vector 0x0050_u16
      elsif @interrupts.serial_interrupt && @interrupts.serial_enabled
        @interrupts.serial_interrupt = false
        call_interrupt_vector 0x0058_u16
      elsif @interrupts.joypad_interrupt && @interrupts.joypad_enabled
        @interrupts.joypad_interrupt = false
        call_interrupt_vector 0x0060_u16
      end
    end
  end

  def set_ime(ime : Bool, now : Bool = false) : Nil
    if now || !ime
      @ime = ime
      @ime_enable = 0 if !ime
    else
      @ime_enable = 2 if @ime_enable == 0
    end
  end

  def memory_at_hl : UInt8
    @cached_hl_read = @memory[self.hl] if @cached_hl_read.nil?
    @cached_hl_read.not_nil!
  end

  def memory_at_hl=(val : UInt8) : Nil
    @cached_hl_read = val
    @memory[self.hl] = val
  end

  def print_state : Nil
    puts "AF:#{hex_str self.af} BC:#{hex_str self.bc} DE:#{hex_str self.de} HL:#{hex_str self.hl} | PC:#{hex_str @pc} | OP:#{hex_str @memory.read_byte @pc} | IME:#{@ime ? 1 : 0}"
  end

  # Runs for the specified number of machine cycles. If no argument provided,
  # runs only one instruction. Handles interrupts _after_ the instruction is
  # executed.
  def tick(cycles = 1) : Nil
    while cycles > 0
      if @halted
        cycles_taken = 4
      else
        cycles_taken = Opcodes::UNPREFIXED[@memory[@pc]].call self
      end
      if @ime_enable > 0
        @ime = true if @ime_enable == 1
        @ime_enable -= 1
      end
      @cached_hl_read = nil           # clear hl read cache
      @memory.tick_extra cycles_taken # tell memory component to tick extra cycles
      cycles -= cycles_taken
      handle_interrupts
    end
  end
end
