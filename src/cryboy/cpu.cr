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

  def initialize(@memory : Memory, @interrupts : Interrupts, @ppu : PPU, @apu : APU, @timer : Timer, boot = false)
    skip_boot if !boot
  end

  def skip_boot
    # https://gbdev.io/pandocs/#power-up-sequence
    @pc = 0x0100_u16
    @sp = 0xFFFE_u16
    self.af = 0x01B0_u16
    self.bc = 0x0013_u16
    self.de = 0x00D8_u16
    self.hl = 0x014D_u16
    @memory[0xFF05] = 0x00_u8 # TIMA
    @memory[0xFF06] = 0x00_u8 # TMA
    @memory[0xFF07] = 0x00_u8 # TAC
    @memory[0xFF10] = 0x80_u8 # NR10
    @memory[0xFF11] = 0xBF_u8 # NR11
    @memory[0xFF12] = 0xF3_u8 # NR12
    @memory[0xFF14] = 0xBF_u8 # NR14
    @memory[0xFF16] = 0x3F_u8 # NR21
    @memory[0xFF17] = 0x00_u8 # NR22
    @memory[0xFF19] = 0xBF_u8 # NR24
    @memory[0xFF1A] = 0x7F_u8 # NR30
    @memory[0xFF1B] = 0xFF_u8 # NR31
    @memory[0xFF1C] = 0x9F_u8 # NR32
    @memory[0xFF1E] = 0xBF_u8 # NR33
    @memory[0xFF20] = 0xFF_u8 # NR41
    @memory[0xFF21] = 0x00_u8 # NR42
    @memory[0xFF22] = 0x00_u8 # NR43
    @memory[0xFF23] = 0xBF_u8 # NR44
    @memory[0xFF24] = 0x77_u8 # NR50
    @memory[0xFF25] = 0xF3_u8 # NR51
    @memory[0xFF26] = 0xF1_u8 # NR52
    @memory[0xFF40] = 0x91_u8 # LCDC
    @memory[0xFF42] = 0x00_u8 # SCY
    @memory[0xFF43] = 0x00_u8 # SCX
    @memory[0xFF45] = 0x00_u8 # LYC
    @memory[0xFF47] = 0xFC_u8 # BGP
    @memory[0xFF48] = 0xFF_u8 # OBP0
    @memory[0xFF49] = 0xFF_u8 # OBP1
    @memory[0xFF4A] = 0x00_u8 # WY
    @memory[0xFF4B] = 0x00_u8 # WX
    @memory[0xFFFF] = 0x00_u8 # IE
  end

  # call to the specified interrupt vector and handle ime/halted flags
  def call_interrupt_vector(vector : UInt16) : Nil
    @ime = false
    @sp -= 2
    @memory[@sp] = @pc
    @pc = vector
    @halted = false
  end

  # service all interrupts
  def handle_interrupts
    @halted = false if @interrupts[0xFF0F] & @interrupts[0xFFFF] != 0xE0_u8
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

  def set_ime(ime : Bool, do_now : Bool = false) : Nil
    if do_now
      @ime = ime
    else
      if ime # enable _after_ next instruction
        @ime_enable = 2
      else # disable immediately
        @ime = false
      end
    end
  end

  def print_state : Nil
    puts "AF:#{hex_str self.af} BC:#{hex_str self.bc} DE:#{hex_str self.de} HL:#{hex_str self.hl} | PC:#{hex_str @pc} | OP:#{hex_str @memory[@pc]} | IME:#{@ime ? 1 : 0}"
  end

  def tick_components(cycles = 4) : Nil
    @ppu.tick cycles
    @apu.tick cycles
    @timer.tick cycles
  end

  # Runs for the specified number of machine cycles. If no argument provided,
  # runs only one instruction. Handles interrupts _after_ the instruction is
  # executed.
  def tick(cycles = 1) : Nil
    while cycles > 0
      tick_components
      if @halted
        cycles_taken = 4
      else
        cycles_taken = Opcodes::UNPREFIXED[@memory[@pc]].call self
      end
      if @ime_enable > 0
        @ime = true if @ime_enable == 1
        @ime_enable -= 1
      end
      tick_components cycles_taken - 4
      cycles -= cycles_taken
      handle_interrupts
    end
  end
end
