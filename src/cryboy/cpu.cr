require "./util"

enum FlagOp
  ZERO
  ONE
  DEFAULT
  UNCHANGED
end

class CPU
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
  property ime = true # todo test how this changes
  property halted = false
  property memory

  def initialize(@memory : Memory, boot = false)
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

  def pop : UInt16
    @memory.read_word (@sp += 2) - 2
  end

  def push(value : UInt16) : Nil
    @memory[@sp -= 2] = value
  end

  def set_flags(res : UInt8, op1 : UInt8, op2 : UInt8, z : FlagOp, n : FlagOp, h : FlagOp, c : FlagOp, add_sub = false)
    case z
    when FlagOp::ZERO    then self.f_z = 0
    when FlagOp::ONE     then self.f_z = 1
    when FlagOp::DEFAULT then self.f_z = res == 0
    when FlagOp::UNCHANGED
    end

    case n
    when FlagOp::ZERO    then self.f_n = 0
    when FlagOp::ONE     then self.f_n = 1
    when FlagOp::DEFAULT then self.f_n = add_sub
    when FlagOp::UNCHANGED
    end

    case h
    when FlagOp::ZERO    then self.f_h = 0
    when FlagOp::ONE     then self.f_h = 1
    when FlagOp::DEFAULT then self.f_h = (op1 ^ op2 ^ res) & 0x10 == 0x10
    when FlagOp::UNCHANGED
    end

    case c
    when FlagOp::ZERO    then self.f_c = 0
    when FlagOp::ONE     then self.f_c = 1
    when FlagOp::DEFAULT then self.f_c = res < op1
    when FlagOp::UNCHANGED
    end
  end

  def add(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 &+ op2
    set_flags res, op1, op2, z, n, h, c, add_sub = true
    res
  end

  def adc(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 &+ op2 &+ (f_c ? 1 : 0)
    set_flags res, op1, op2, z, n, h, c, add_sub = true
    res
  end

  def sub(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 &- op2
    set_flags res, op1, op2, z, n, h, c, add_sub = true
    res
  end

  def sbc(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 &- op2 &- (f_c ? 1 : 0)
    set_flags res, op1, op2, z, n, h, c, add_sub = true
    res
  end

  def and(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 & op2
    set_flags res, op1, op2, z, n, h, c
    res
  end

  def or(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 | op2
    set_flags res, op1, op2, z, n, h, c
    res
  end

  def xor(op1 : UInt8, op2 : UInt8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt8
    res = op1 ^ op2
    set_flags res, op1, op2, z, n, h, c
    res
  end

  def add(op1 : UInt16, op2 : Int8, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt16
    # todo this case is very specific, should be moved elsewhere
    res = op1 &+ op2
    self.f = 0b00000000
    self.f += (((@sp & 0xF) + (op2.to_u8! & 0xF)) > 0xF) ? 1 : 0 << 5
    self.f += (((@sp & 0xFF) + (op2.to_u8! & 0xF)) > 0xF) ? 1 : 0 << 4
    res
  end

  def add(operand_1 : UInt16, operand_2 : UInt16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt16
    res = operand_1 &+ operand_2

    if z == FlagOp::ZERO
      self.f_z = false
    elsif z == FlagOp::ONE || (z == FlagOp::DEFAULT && res == 0)
      self.f_z = true
    end

    if n == FlagOp::ZERO
      self.f_n = false
    elsif n == FlagOp::ONE # || todo
      self.f_n = true
    end

    if h == FlagOp::ZERO
      self.f_h = false
    elsif h == FlagOp::ONE # || todo
      self.f_h = true
    end

    if c == FlagOp::ZERO
      self.f_c = false
    elsif c == FlagOp::ONE || (c == FlagOp::DEFAULT && res < operand_1)
      self.f_c = true
    end

    res
  end

  def sub(operand_1 : UInt16, operand_2 : UInt16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt16
    res = operand_1 &- operand_2

    if z == FlagOp::ZERO
      self.f &= 0b0111_0000
    elsif z == FlagOp::ONE || (z == FlagOp::DEFAULT && res == 0)
      self.f |= 0b1000_0000
    end

    if n == FlagOp::ZERO
      self.f &= 0b1011_0000
    elsif n == FlagOp::ONE # || todo
      self.f |= 0b0100_0000
    end

    if h == FlagOp::ZERO
      self.f &= 0b1101_0000
    elsif h == FlagOp::ONE # || todo
      self.f |= 0b0010_0000
    end

    if c == FlagOp::ZERO
      self.f &= 0b1110_0000
    elsif c == FlagOp::ONE || (c == FlagOp::DEFAULT && res > operand_1)
      self.f |= 0b0001_0000
    end

    res
  end

  def bit(op : UInt8, bit : Int) : Nil
    self.f_z = (op >> bit) ^ 0x1
    self.f_n = false
    self.f_h = true
  end

  def handle_interrupts
    # bit 0: v-blank
    if @memory.vblank && @memory.vblank_enabled
      @memory.vblank = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0040_u16
      @halted = false
    end
    # bit 1: lcd stat
    if @memory.lcd_stat && @memory.lcd_stat_enabled
      @memory.lcd_stat = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0048_u16
      @halted = false
    end
    # bit 2: timer
    if @memory.timer && @memory.timer_enabled
      @memory.timer = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0050_u16
      @halted = false
    end
    # bit 3: serial
    if @memory.serial && @memory.serial_enabled
      @memory.serial = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0058_u16
      @halted = false
    end
    # bit 4: joypad
    if @memory.joypad && @memory.joypad_enabled
      @memory.joypad = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0060_u16
      @halted = false
    end
    # clear Interrupt Master Enable
    @ime = false
  end

  # Runs for the specified number of machine cycles. If no argument provided,
  # runs only one instruction. Handles interrupts _after_ the instruction is
  # executed.
  def tick(cycles = 1) : Nil
    while cycles > 0
      opcode = read_opcode
      cycles -= process_opcode opcode
      # interrupts
      handle_interrupts if @ime
      return if @halted
    end
  end

  def read_opcode : UInt8
    @memory[@pc]
  end

  # process the given opcode
  # returns the number of machine cycles taken (where gb runs at 4.19MHz)
  def process_opcode(opcode : UInt8, cb = false) : Int32
    # puts "op:#{hex_str opcode}, pc:#{hex_str @pc}, sp:#{hex_str @sp}, af:#{hex_str self.af}, bc:#{hex_str self.bc}, de:#{hex_str self.de}, hl:#{hex_str self.hl}, flags:#{self.f.to_s(2).rjust(8, '0')}"
    # Everything below is automatically generated.
    if !cb
      case opcode
      when 0x00 # NOP
        @pc &+= 1
        return 4
      when 0x01 # LD BC,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        self.bc = u16
        return 12
      when 0x02 # LD (BC),A
        @pc &+= 1
        @memory[self.bc] = self.a
        return 8
      when 0x03 # INC BC
        @pc &+= 1
        self.bc &+= 1
        return 8
      when 0x04 # INC B
        @pc &+= 1
        self.b &+= 1
        self.f_z = self.b == 0
        self.f_h = self.b & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x05 # DEC B
        @pc &+= 1
        self.b &-= 1
        self.f_z = self.b == 0
        self.f_h = self.b & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x06 # LD B,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.b = u8
        return 8
      when 0x07 # RLCA
        @pc &+= 1
        raise "Not currently supporting RLCA"
        self.f_z = false
        self.f_n = false
        self.f_h = false
        return 4
      when 0x08 # LD (u16),SP
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        @memory[u16] = @sp
        return 20
      when 0x09 # ADD HL,BC
        @pc &+= 1
        self.f_h = (self.hl & 0x0FFF).to_u32 + (self.bc & 0x0FFF) > 0x0FFF
        self.hl &+= self.bc
        self.f_c = self.hl < self.bc
        self.f_n = false
        return 8
      when 0x0A # LD A,(BC)
        @pc &+= 1
        self.a = @memory[self.bc]
        return 8
      when 0x0B # DEC BC
        @pc &+= 1
        self.bc &-= 1
        return 8
      when 0x0C # INC C
        @pc &+= 1
        self.c &+= 1
        self.f_z = self.c == 0
        self.f_h = self.c & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x0D # DEC C
        @pc &+= 1
        self.c &-= 1
        self.f_z = self.c == 0
        self.f_h = self.c & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x0E # LD C,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.c = u8
        return 8
      when 0x0F # RRCA
        @pc &+= 1
        raise "Not currently supporting RRCA"
        self.f_z = false
        self.f_n = false
        self.f_h = false
        return 4
      when 0x10 # STOP
        @pc &+= 2
        raise "Not currently supporting STOP"
        return 4
      when 0x11 # LD DE,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        self.de = u16
        return 12
      when 0x12 # LD (DE),A
        @pc &+= 1
        @memory[self.de] = self.a
        return 8
      when 0x13 # INC DE
        @pc &+= 1
        self.de &+= 1
        return 8
      when 0x14 # INC D
        @pc &+= 1
        self.d &+= 1
        self.f_z = self.d == 0
        self.f_h = self.d & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x15 # DEC D
        @pc &+= 1
        self.d &-= 1
        self.f_z = self.d == 0
        self.f_h = self.d & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x16 # LD D,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.d = u8
        return 8
      when 0x17 # RLA
        @pc &+= 1
        carry = self.a & 0x80
        self.a = (self.a << 1) + (self.f_c ? 1 : 0)
        self.f_c = carry
        self.f_z = false
        self.f_n = false
        self.f_h = false
        return 4
      when 0x18 # JR i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        @pc &+= i8
        return 12
      when 0x19 # ADD HL,DE
        @pc &+= 1
        self.f_h = (self.hl & 0x0FFF).to_u32 + (self.de & 0x0FFF) > 0x0FFF
        self.hl &+= self.de
        self.f_c = self.hl < self.de
        self.f_n = false
        return 8
      when 0x1A # LD A,(DE)
        @pc &+= 1
        self.a = @memory[self.de]
        return 8
      when 0x1B # DEC DE
        @pc &+= 1
        self.de &-= 1
        return 8
      when 0x1C # INC E
        @pc &+= 1
        self.e &+= 1
        self.f_z = self.e == 0
        self.f_h = self.e & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x1D # DEC E
        @pc &+= 1
        self.e &-= 1
        self.f_z = self.e == 0
        self.f_h = self.e & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x1E # LD E,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.e = u8
        return 8
      when 0x1F # RRA
        @pc &+= 1
        raise "Not currently supporting RRA"
        self.f_z = false
        self.f_n = false
        self.f_h = false
        return 4
      when 0x20 # JR NZ,i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        if self.f_nz
          @pc &+= i8
          return 12
        end
        return 8
      when 0x21 # LD HL,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        self.hl = u16
        return 12
      when 0x22 # LD (HL+),A
        @pc &+= 1
        @memory[((self.hl &+= 1) &- 1)] = self.a
        return 8
      when 0x23 # INC HL
        @pc &+= 1
        self.hl &+= 1
        return 8
      when 0x24 # INC H
        @pc &+= 1
        self.h &+= 1
        self.f_z = self.h == 0
        self.f_h = self.h & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x25 # DEC H
        @pc &+= 1
        self.h &-= 1
        self.f_z = self.h == 0
        self.f_h = self.h & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x26 # LD H,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.h = u8
        return 8
      when 0x27 # DAA
        @pc &+= 1
        raise "Not currently supporting DAA"
        self.f_h = false
        return 4
      when 0x28 # JR Z,i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        if self.f_z
          @pc &+= i8
          return 12
        end
        return 8
      when 0x29 # ADD HL,HL
        @pc &+= 1
        self.f_h = (self.hl & 0x0FFF).to_u32 + (self.hl & 0x0FFF) > 0x0FFF
        self.hl &+= self.hl
        self.f_c = self.hl < self.hl
        self.f_n = false
        return 8
      when 0x2A # LD A,(HL+)
        @pc &+= 1
        self.a = @memory[((self.hl &+= 1) &- 1)]
        return 8
      when 0x2B # DEC HL
        @pc &+= 1
        self.hl &-= 1
        return 8
      when 0x2C # INC L
        @pc &+= 1
        self.l &+= 1
        self.f_z = self.l == 0
        self.f_h = self.l & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x2D # DEC L
        @pc &+= 1
        self.l &-= 1
        self.f_z = self.l == 0
        self.f_h = self.l & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x2E # LD L,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.l = u8
        return 8
      when 0x2F # CPL
        @pc &+= 1
        raise "Not currently supporting CPL"
        self.f_n = true
        self.f_h = true
        return 4
      when 0x30 # JR NC,i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        if self.f_nc
          @pc &+= i8
          return 12
        end
        return 8
      when 0x31 # LD SP,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        @sp = u16
        return 12
      when 0x32 # LD (HL-),A
        @pc &+= 1
        @memory[((self.hl &-= 1) &+ 1)] = self.a
        return 8
      when 0x33 # INC SP
        @pc &+= 1
        @sp &+= 1
        return 8
      when 0x34 # INC (HL)
        @pc &+= 1
        @memory[self.hl] &+= 1
        self.f_z = @memory[self.hl] == 0
        self.f_h = @memory[self.hl] & 0x1F == 0x1F
        self.f_n = false
        return 12
      when 0x35 # DEC (HL)
        @pc &+= 1
        @memory[self.hl] &-= 1
        self.f_z = @memory[self.hl] == 0
        self.f_h = @memory[self.hl] & 0x0F == 0x0F
        self.f_n = true
        return 12
      when 0x36 # LD (HL),u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        @memory[self.hl] = u8
        return 12
      when 0x37 # SCF
        @pc &+= 1
        raise "Not currently supporting SCF"
        self.f_n = false
        self.f_h = false
        self.f_c = true
        return 4
      when 0x38 # JR C,i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        if self.f_c
          @pc &+= i8
          return 12
        end
        return 8
      when 0x39 # ADD HL,SP
        @pc &+= 1
        self.f_h = (self.hl & 0x0FFF).to_u32 + (@sp & 0x0FFF) > 0x0FFF
        self.hl &+= @sp
        self.f_c = self.hl < @sp
        self.f_n = false
        return 8
      when 0x3A # LD A,(HL-)
        @pc &+= 1
        self.a = @memory[((self.hl &-= 1) &+ 1)]
        return 8
      when 0x3B # DEC SP
        @pc &+= 1
        @sp &-= 1
        return 8
      when 0x3C # INC A
        @pc &+= 1
        self.a &+= 1
        self.f_z = self.a == 0
        self.f_h = self.a & 0x1F == 0x1F
        self.f_n = false
        return 4
      when 0x3D # DEC A
        @pc &+= 1
        self.a &-= 1
        self.f_z = self.a == 0
        self.f_h = self.a & 0x0F == 0x0F
        self.f_n = true
        return 4
      when 0x3E # LD A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.a = u8
        return 8
      when 0x3F # CCF
        @pc &+= 1
        raise "Not currently supporting CCF"
        self.f_n = false
        self.f_h = false
        return 4
      when 0x40 # LD B,B
        @pc &+= 1
        self.b = self.b
        return 4
      when 0x41 # LD B,C
        @pc &+= 1
        self.b = self.c
        return 4
      when 0x42 # LD B,D
        @pc &+= 1
        self.b = self.d
        return 4
      when 0x43 # LD B,E
        @pc &+= 1
        self.b = self.e
        return 4
      when 0x44 # LD B,H
        @pc &+= 1
        self.b = self.h
        return 4
      when 0x45 # LD B,L
        @pc &+= 1
        self.b = self.l
        return 4
      when 0x46 # LD B,(HL)
        @pc &+= 1
        self.b = @memory[self.hl]
        return 8
      when 0x47 # LD B,A
        @pc &+= 1
        self.b = self.a
        return 4
      when 0x48 # LD C,B
        @pc &+= 1
        self.c = self.b
        return 4
      when 0x49 # LD C,C
        @pc &+= 1
        self.c = self.c
        return 4
      when 0x4A # LD C,D
        @pc &+= 1
        self.c = self.d
        return 4
      when 0x4B # LD C,E
        @pc &+= 1
        self.c = self.e
        return 4
      when 0x4C # LD C,H
        @pc &+= 1
        self.c = self.h
        return 4
      when 0x4D # LD C,L
        @pc &+= 1
        self.c = self.l
        return 4
      when 0x4E # LD C,(HL)
        @pc &+= 1
        self.c = @memory[self.hl]
        return 8
      when 0x4F # LD C,A
        @pc &+= 1
        self.c = self.a
        return 4
      when 0x50 # LD D,B
        @pc &+= 1
        self.d = self.b
        return 4
      when 0x51 # LD D,C
        @pc &+= 1
        self.d = self.c
        return 4
      when 0x52 # LD D,D
        @pc &+= 1
        self.d = self.d
        return 4
      when 0x53 # LD D,E
        @pc &+= 1
        self.d = self.e
        return 4
      when 0x54 # LD D,H
        @pc &+= 1
        self.d = self.h
        return 4
      when 0x55 # LD D,L
        @pc &+= 1
        self.d = self.l
        return 4
      when 0x56 # LD D,(HL)
        @pc &+= 1
        self.d = @memory[self.hl]
        return 8
      when 0x57 # LD D,A
        @pc &+= 1
        self.d = self.a
        return 4
      when 0x58 # LD E,B
        @pc &+= 1
        self.e = self.b
        return 4
      when 0x59 # LD E,C
        @pc &+= 1
        self.e = self.c
        return 4
      when 0x5A # LD E,D
        @pc &+= 1
        self.e = self.d
        return 4
      when 0x5B # LD E,E
        @pc &+= 1
        self.e = self.e
        return 4
      when 0x5C # LD E,H
        @pc &+= 1
        self.e = self.h
        return 4
      when 0x5D # LD E,L
        @pc &+= 1
        self.e = self.l
        return 4
      when 0x5E # LD E,(HL)
        @pc &+= 1
        self.e = @memory[self.hl]
        return 8
      when 0x5F # LD E,A
        @pc &+= 1
        self.e = self.a
        return 4
      when 0x60 # LD H,B
        @pc &+= 1
        self.h = self.b
        return 4
      when 0x61 # LD H,C
        @pc &+= 1
        self.h = self.c
        return 4
      when 0x62 # LD H,D
        @pc &+= 1
        self.h = self.d
        return 4
      when 0x63 # LD H,E
        @pc &+= 1
        self.h = self.e
        return 4
      when 0x64 # LD H,H
        @pc &+= 1
        self.h = self.h
        return 4
      when 0x65 # LD H,L
        @pc &+= 1
        self.h = self.l
        return 4
      when 0x66 # LD H,(HL)
        @pc &+= 1
        self.h = @memory[self.hl]
        return 8
      when 0x67 # LD H,A
        @pc &+= 1
        self.h = self.a
        return 4
      when 0x68 # LD L,B
        @pc &+= 1
        self.l = self.b
        return 4
      when 0x69 # LD L,C
        @pc &+= 1
        self.l = self.c
        return 4
      when 0x6A # LD L,D
        @pc &+= 1
        self.l = self.d
        return 4
      when 0x6B # LD L,E
        @pc &+= 1
        self.l = self.e
        return 4
      when 0x6C # LD L,H
        @pc &+= 1
        self.l = self.h
        return 4
      when 0x6D # LD L,L
        @pc &+= 1
        self.l = self.l
        return 4
      when 0x6E # LD L,(HL)
        @pc &+= 1
        self.l = @memory[self.hl]
        return 8
      when 0x6F # LD L,A
        @pc &+= 1
        self.l = self.a
        return 4
      when 0x70 # LD (HL),B
        @pc &+= 1
        @memory[self.hl] = self.b
        return 8
      when 0x71 # LD (HL),C
        @pc &+= 1
        @memory[self.hl] = self.c
        return 8
      when 0x72 # LD (HL),D
        @pc &+= 1
        @memory[self.hl] = self.d
        return 8
      when 0x73 # LD (HL),E
        @pc &+= 1
        @memory[self.hl] = self.e
        return 8
      when 0x74 # LD (HL),H
        @pc &+= 1
        @memory[self.hl] = self.h
        return 8
      when 0x75 # LD (HL),L
        @pc &+= 1
        @memory[self.hl] = self.l
        return 8
      when 0x76 # HALT
        @pc &+= 1
        raise "Not currently supporting HALT"
        return 4
      when 0x77 # LD (HL),A
        @pc &+= 1
        @memory[self.hl] = self.a
        return 8
      when 0x78 # LD A,B
        @pc &+= 1
        self.a = self.b
        return 4
      when 0x79 # LD A,C
        @pc &+= 1
        self.a = self.c
        return 4
      when 0x7A # LD A,D
        @pc &+= 1
        self.a = self.d
        return 4
      when 0x7B # LD A,E
        @pc &+= 1
        self.a = self.e
        return 4
      when 0x7C # LD A,H
        @pc &+= 1
        self.a = self.h
        return 4
      when 0x7D # LD A,L
        @pc &+= 1
        self.a = self.l
        return 4
      when 0x7E # LD A,(HL)
        @pc &+= 1
        self.a = @memory[self.hl]
        return 8
      when 0x7F # LD A,A
        @pc &+= 1
        self.a = self.a
        return 4
      when 0x80 # ADD A,B
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.b & 0x0F) > 0x0F
        self.a &+= self.b
        self.f_z = self.a == 0
        self.f_c = self.a < self.b
        self.f_n = false
        return 4
      when 0x81 # ADD A,C
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.c & 0x0F) > 0x0F
        self.a &+= self.c
        self.f_z = self.a == 0
        self.f_c = self.a < self.c
        self.f_n = false
        return 4
      when 0x82 # ADD A,D
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.d & 0x0F) > 0x0F
        self.a &+= self.d
        self.f_z = self.a == 0
        self.f_c = self.a < self.d
        self.f_n = false
        return 4
      when 0x83 # ADD A,E
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.e & 0x0F) > 0x0F
        self.a &+= self.e
        self.f_z = self.a == 0
        self.f_c = self.a < self.e
        self.f_n = false
        return 4
      when 0x84 # ADD A,H
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.h & 0x0F) > 0x0F
        self.a &+= self.h
        self.f_z = self.a == 0
        self.f_c = self.a < self.h
        self.f_n = false
        return 4
      when 0x85 # ADD A,L
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.l & 0x0F) > 0x0F
        self.a &+= self.l
        self.f_z = self.a == 0
        self.f_c = self.a < self.l
        self.f_n = false
        return 4
      when 0x86 # ADD A,(HL)
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (@memory[self.hl] & 0x0F) > 0x0F
        self.a &+= @memory[self.hl]
        self.f_z = self.a == 0
        self.f_c = self.a < @memory[self.hl]
        self.f_n = false
        return 8
      when 0x87 # ADD A,A
        @pc &+= 1
        self.f_h = (self.a & 0x0F) + (self.a & 0x0F) > 0x0F
        self.a &+= self.a
        self.f_z = self.a == 0
        self.f_c = self.a < self.a
        self.f_n = false
        return 4
      when 0x88 # ADC A,B
        @pc &+= 1
        raise "Not currently supporting ADC A,B"
        self.f_n = false
        return 4
      when 0x89 # ADC A,C
        @pc &+= 1
        raise "Not currently supporting ADC A,C"
        self.f_n = false
        return 4
      when 0x8A # ADC A,D
        @pc &+= 1
        raise "Not currently supporting ADC A,D"
        self.f_n = false
        return 4
      when 0x8B # ADC A,E
        @pc &+= 1
        raise "Not currently supporting ADC A,E"
        self.f_n = false
        return 4
      when 0x8C # ADC A,H
        @pc &+= 1
        raise "Not currently supporting ADC A,H"
        self.f_n = false
        return 4
      when 0x8D # ADC A,L
        @pc &+= 1
        raise "Not currently supporting ADC A,L"
        self.f_n = false
        return 4
      when 0x8E # ADC A,(HL)
        @pc &+= 1
        raise "Not currently supporting ADC A,(HL)"
        self.f_n = false
        return 8
      when 0x8F # ADC A,A
        @pc &+= 1
        raise "Not currently supporting ADC A,A"
        self.f_n = false
        return 4
      when 0x90 # SUB A,B
        @pc &+= 1
        self.f_h = self.a & 0xF < self.b & 0xF
        self.f_c = self.a < self.b
        self.a &-= self.b
        self.f_z = self.a &- self.b == 0
        self.f_n = true
        return 4
      when 0x91 # SUB A,C
        @pc &+= 1
        self.f_h = self.a & 0xF < self.c & 0xF
        self.f_c = self.a < self.c
        self.a &-= self.c
        self.f_z = self.a &- self.c == 0
        self.f_n = true
        return 4
      when 0x92 # SUB A,D
        @pc &+= 1
        self.f_h = self.a & 0xF < self.d & 0xF
        self.f_c = self.a < self.d
        self.a &-= self.d
        self.f_z = self.a &- self.d == 0
        self.f_n = true
        return 4
      when 0x93 # SUB A,E
        @pc &+= 1
        self.f_h = self.a & 0xF < self.e & 0xF
        self.f_c = self.a < self.e
        self.a &-= self.e
        self.f_z = self.a &- self.e == 0
        self.f_n = true
        return 4
      when 0x94 # SUB A,H
        @pc &+= 1
        self.f_h = self.a & 0xF < self.h & 0xF
        self.f_c = self.a < self.h
        self.a &-= self.h
        self.f_z = self.a &- self.h == 0
        self.f_n = true
        return 4
      when 0x95 # SUB A,L
        @pc &+= 1
        self.f_h = self.a & 0xF < self.l & 0xF
        self.f_c = self.a < self.l
        self.a &-= self.l
        self.f_z = self.a &- self.l == 0
        self.f_n = true
        return 4
      when 0x96 # SUB A,(HL)
        @pc &+= 1
        self.f_h = self.a & 0xF < @memory[self.hl] & 0xF
        self.f_c = self.a < @memory[self.hl]
        self.a &-= @memory[self.hl]
        self.f_z = self.a &- @memory[self.hl] == 0
        self.f_n = true
        return 8
      when 0x97 # SUB A,A
        @pc &+= 1
        self.f_h = self.a & 0xF < self.a & 0xF
        self.f_c = self.a < self.a
        self.a &-= self.a
        self.f_z = self.a &- self.a == 0
        self.f_n = true
        return 4
      when 0x98 # SBC A,B
        @pc &+= 1
        raise "Not currently supporting SBC A,B"
        self.f_n = true
        return 4
      when 0x99 # SBC A,C
        @pc &+= 1
        raise "Not currently supporting SBC A,C"
        self.f_n = true
        return 4
      when 0x9A # SBC A,D
        @pc &+= 1
        raise "Not currently supporting SBC A,D"
        self.f_n = true
        return 4
      when 0x9B # SBC A,E
        @pc &+= 1
        raise "Not currently supporting SBC A,E"
        self.f_n = true
        return 4
      when 0x9C # SBC A,H
        @pc &+= 1
        raise "Not currently supporting SBC A,H"
        self.f_n = true
        return 4
      when 0x9D # SBC A,L
        @pc &+= 1
        raise "Not currently supporting SBC A,L"
        self.f_n = true
        return 4
      when 0x9E # SBC A,(HL)
        @pc &+= 1
        raise "Not currently supporting SBC A,(HL)"
        self.f_n = true
        return 8
      when 0x9F # SBC A,A
        @pc &+= 1
        raise "Not currently supporting SBC A,A"
        self.f_n = true
        return 4
      when 0xA0 # AND A,B
        @pc &+= 1
        raise "Not currently supporting AND A,B"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA1 # AND A,C
        @pc &+= 1
        raise "Not currently supporting AND A,C"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA2 # AND A,D
        @pc &+= 1
        raise "Not currently supporting AND A,D"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA3 # AND A,E
        @pc &+= 1
        raise "Not currently supporting AND A,E"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA4 # AND A,H
        @pc &+= 1
        raise "Not currently supporting AND A,H"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA5 # AND A,L
        @pc &+= 1
        raise "Not currently supporting AND A,L"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA6 # AND A,(HL)
        @pc &+= 1
        raise "Not currently supporting AND A,(HL)"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 8
      when 0xA7 # AND A,A
        @pc &+= 1
        raise "Not currently supporting AND A,A"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 4
      when 0xA8 # XOR A,B
        @pc &+= 1
        self.a ^= self.b
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xA9 # XOR A,C
        @pc &+= 1
        self.a ^= self.c
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xAA # XOR A,D
        @pc &+= 1
        self.a ^= self.d
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xAB # XOR A,E
        @pc &+= 1
        self.a ^= self.e
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xAC # XOR A,H
        @pc &+= 1
        self.a ^= self.h
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xAD # XOR A,L
        @pc &+= 1
        self.a ^= self.l
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xAE # XOR A,(HL)
        @pc &+= 1
        self.a ^= @memory[self.hl]
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0xAF # XOR A,A
        @pc &+= 1
        self.a ^= self.a
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB0 # OR A,B
        @pc &+= 1
        raise "Not currently supporting OR A,B"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB1 # OR A,C
        @pc &+= 1
        raise "Not currently supporting OR A,C"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB2 # OR A,D
        @pc &+= 1
        raise "Not currently supporting OR A,D"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB3 # OR A,E
        @pc &+= 1
        raise "Not currently supporting OR A,E"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB4 # OR A,H
        @pc &+= 1
        raise "Not currently supporting OR A,H"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB5 # OR A,L
        @pc &+= 1
        raise "Not currently supporting OR A,L"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB6 # OR A,(HL)
        @pc &+= 1
        raise "Not currently supporting OR A,(HL)"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0xB7 # OR A,A
        @pc &+= 1
        raise "Not currently supporting OR A,A"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 4
      when 0xB8 # CP A,B
        @pc &+= 1
        self.f_z = self.a &- self.b == 0
        self.f_h = self.a & 0xF < self.b & 0xF
        self.f_c = self.a < self.b
        self.f_n = true
        return 4
      when 0xB9 # CP A,C
        @pc &+= 1
        self.f_z = self.a &- self.c == 0
        self.f_h = self.a & 0xF < self.c & 0xF
        self.f_c = self.a < self.c
        self.f_n = true
        return 4
      when 0xBA # CP A,D
        @pc &+= 1
        self.f_z = self.a &- self.d == 0
        self.f_h = self.a & 0xF < self.d & 0xF
        self.f_c = self.a < self.d
        self.f_n = true
        return 4
      when 0xBB # CP A,E
        @pc &+= 1
        self.f_z = self.a &- self.e == 0
        self.f_h = self.a & 0xF < self.e & 0xF
        self.f_c = self.a < self.e
        self.f_n = true
        return 4
      when 0xBC # CP A,H
        @pc &+= 1
        self.f_z = self.a &- self.h == 0
        self.f_h = self.a & 0xF < self.h & 0xF
        self.f_c = self.a < self.h
        self.f_n = true
        return 4
      when 0xBD # CP A,L
        @pc &+= 1
        self.f_z = self.a &- self.l == 0
        self.f_h = self.a & 0xF < self.l & 0xF
        self.f_c = self.a < self.l
        self.f_n = true
        return 4
      when 0xBE # CP A,(HL)
        @pc &+= 1
        self.f_z = self.a &- @memory[self.hl] == 0
        self.f_h = self.a & 0xF < @memory[self.hl] & 0xF
        self.f_c = self.a < @memory[self.hl]
        self.f_n = true
        return 8
      when 0xBF # CP A,A
        @pc &+= 1
        self.f_z = self.a &- self.a == 0
        self.f_h = self.a & 0xF < self.a & 0xF
        self.f_c = self.a < self.a
        self.f_n = true
        return 4
      when 0xC0 # RET NZ
        @pc &+= 1
        if self.f_nz
          @pc = @memory.read_word @sp
          @sp += 2
          return 20
        end
        return 8
      when 0xC1 # POP BC
        @pc &+= 1
        self.bc = @memory.read_word (@sp += 2) - 2
        return 12
      when 0xC2 # JP NZ,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        raise "Not currently supporting JP NZ,u16"
        return 12
      when 0xC3 # JP u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        raise "Not currently supporting JP u16"
        return 16
      when 0xC4 # CALL NZ,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        if self.f_nz
          @sp -= 2
          @memory[@sp] = @pc
          @pc = u16
          return 24
        end
        return 12
      when 0xC5 # PUSH BC
        @pc &+= 1
        @memory[@sp -= 2] = self.bc
        return 16
      when 0xC6 # ADD A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.f_h = (self.a & 0x0F) + (u8 & 0x0F) > 0x0F
        self.a &+= u8
        self.f_z = self.a == 0
        self.f_c = self.a < u8
        self.f_n = false
        return 8
      when 0xC7 # RST 00h
        @pc &+= 1
        raise "Not currently supporting RST 00h"
        return 16
      when 0xC8 # RET Z
        @pc &+= 1
        if self.f_z
          @pc = @memory.read_word @sp
          @sp += 2
          return 20
        end
        return 8
      when 0xC9 # RET
        @pc &+= 1
        @pc = @memory.read_word @sp
        @sp += 2
        return 16
      when 0xCA # JP Z,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        raise "Not currently supporting JP Z,u16"
        return 12
      when 0xCB # PREFIX CB
        @pc &+= 1
        # todo: This should operate as a seperate instruction, but can't be interrupted.
        #       This will require a restructure where the CPU leads the timing, rather than the PPU.
        #       https://discordapp.com/channels/465585922579103744/465586075830845475/712358911151177818
        #       https://discordapp.com/channels/465585922579103744/465586075830845475/712359253255520328
        next_op = read_opcode
        cycles = process_opcode next_op, cb = true
        # izik's table lists all prefixed opcodes as a length of 2 when they should be 1
        @pc &-= 1
        return 4
      when 0xCC # CALL Z,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        if self.f_z
          @sp -= 2
          @memory[@sp] = @pc
          @pc = u16
          return 24
        end
        return 12
      when 0xCD # CALL u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        @sp -= 2
        @memory[@sp] = @pc
        @pc = u16
        return 24
      when 0xCE # ADC A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        raise "Not currently supporting ADC A,u8"
        self.f_n = false
        return 8
      when 0xCF # RST 08h
        @pc &+= 1
        raise "Not currently supporting RST 08h"
        return 16
      when 0xD0 # RET NC
        @pc &+= 1
        if self.f_nc
          @pc = @memory.read_word @sp
          @sp += 2
          return 20
        end
        return 8
      when 0xD1 # POP DE
        @pc &+= 1
        self.de = @memory.read_word (@sp += 2) - 2
        return 12
      when 0xD2 # JP NC,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        raise "Not currently supporting JP NC,u16"
        return 12
      when 0xD3 # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xD4 # CALL NC,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        if self.f_nc
          @sp -= 2
          @memory[@sp] = @pc
          @pc = u16
          return 24
        end
        return 12
      when 0xD5 # PUSH DE
        @pc &+= 1
        @memory[@sp -= 2] = self.de
        return 16
      when 0xD6 # SUB A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.f_h = self.a & 0xF < u8 & 0xF
        self.f_c = self.a < u8
        self.a &-= u8
        self.f_z = self.a &- u8 == 0
        self.f_n = true
        return 8
      when 0xD7 # RST 10h
        @pc &+= 1
        raise "Not currently supporting RST 10h"
        return 16
      when 0xD8 # RET C
        @pc &+= 1
        if self.f_c
          @pc = @memory.read_word @sp
          @sp += 2
          return 20
        end
        return 8
      when 0xD9 # RETI
        @pc &+= 1
        raise "Not currently supporting RETI"
        return 16
      when 0xDA # JP C,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        raise "Not currently supporting JP C,u16"
        return 12
      when 0xDB # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xDC # CALL C,u16
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        if self.f_c
          @sp -= 2
          @memory[@sp] = @pc
          @pc = u16
          return 24
        end
        return 12
      when 0xDD # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xDE # SBC A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        raise "Not currently supporting SBC A,u8"
        self.f_n = true
        return 8
      when 0xDF # RST 18h
        @pc &+= 1
        raise "Not currently supporting RST 18h"
        return 16
      when 0xE0 # LD (FF00+u8),A
        u8 = @memory[@pc + 1]
        @pc &+= 2
        @memory[0xFF00 &+ u8] = self.a
        return 12
      when 0xE1 # POP HL
        @pc &+= 1
        self.hl = @memory.read_word (@sp += 2) - 2
        return 12
      when 0xE2 # LD (FF00+C),A
        @pc &+= 1
        @memory[0xFF00 &+ self.c] = self.a
        return 8
      when 0xE3 # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xE4 # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xE5 # PUSH HL
        @pc &+= 1
        @memory[@sp -= 2] = self.hl
        return 16
      when 0xE6 # AND A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        raise "Not currently supporting AND A,u8"
        self.f_n = false
        self.f_h = true
        self.f_c = false
        return 8
      when 0xE7 # RST 20h
        @pc &+= 1
        raise "Not currently supporting RST 20h"
        return 16
      when 0xE8 # ADD SP,i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        self.f_h = (@sp & 0x0F) + (i8 & 0x0F) > 0x0F
        @sp &+= i8
        self.f_c = @sp < i8
        self.f_z = false
        self.f_n = false
        return 16
      when 0xE9 # JP HL
        @pc &+= 1
        raise "Not currently supporting JP HL"
        return 4
      when 0xEA # LD (u16),A
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        @memory[u16] = self.a
        return 16
      when 0xEB # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xEC # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xED # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xEE # XOR A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.a ^= u8
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0xEF # RST 28h
        @pc &+= 1
        raise "Not currently supporting RST 28h"
        return 16
      when 0xF0 # LD A,(FF00+u8)
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.a = @memory[0xFF00 &+ u8]
        return 12
      when 0xF1 # POP AF
        @pc &+= 1
        self.af = @memory.read_word (@sp += 2) - 2
        self.f_z = self.af & (0x1 << 7)
        self.f_n = self.af & (0x1 << 6)
        self.f_h = self.af & (0x1 << 5)
        self.f_c = self.af & (0x1 << 4)
        return 12
      when 0xF2 # LD A,(FF00+C)
        @pc &+= 1
        self.a = @memory[0xFF00 &+ self.c]
        return 8
      when 0xF3 # DI
        @pc &+= 1
        raise "Not currently supporting DI"
        return 4
      when 0xF4 # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xF5 # PUSH AF
        @pc &+= 1
        @memory[@sp -= 2] = self.af
        return 16
      when 0xF6 # OR A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        raise "Not currently supporting OR A,u8"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0xF7 # RST 30h
        @pc &+= 1
        raise "Not currently supporting RST 30h"
        return 16
      when 0xF8 # LD HL,SP+i8
        i8 = @memory[@pc + 1].to_i8!
        @pc &+= 2
        self.hl = @sp + i8
        self.f_z = false
        self.f_n = false
        return 12
      when 0xF9 # LD SP,HL
        @pc &+= 1
        @sp = self.hl
        return 8
      when 0xFA # LD A,(u16)
        u16 = @memory.read_word @pc + 1
        @pc &+= 3
        self.a = @memory[u16]
        return 16
      when 0xFB # EI
        @pc &+= 1
        raise "Not currently supporting EI"
        return 4
      when 0xFC # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xFD # UNUSED
        @pc &+= 1
        raise "Not currently supporting UNUSED"
        return 0
      when 0xFE # CP A,u8
        u8 = @memory[@pc + 1]
        @pc &+= 2
        self.f_z = self.a &- u8 == 0
        self.f_h = self.a & 0xF < u8 & 0xF
        self.f_c = self.a < u8
        self.f_n = true
        return 8
      when 0xFF # RST 38h
        @pc &+= 1
        raise "Not currently supporting RST 38h"
        return 16
      end
    else
      case opcode
      when 0x00 # RLC B
        @pc &+= 2
        raise "Not currently supporting RLC B"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x01 # RLC C
        @pc &+= 2
        raise "Not currently supporting RLC C"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x02 # RLC D
        @pc &+= 2
        raise "Not currently supporting RLC D"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x03 # RLC E
        @pc &+= 2
        raise "Not currently supporting RLC E"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x04 # RLC H
        @pc &+= 2
        raise "Not currently supporting RLC H"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x05 # RLC L
        @pc &+= 2
        raise "Not currently supporting RLC L"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x06 # RLC (HL)
        @pc &+= 2
        raise "Not currently supporting RLC (HL)"
        self.f_n = false
        self.f_h = false
        return 16
      when 0x07 # RLC A
        @pc &+= 2
        raise "Not currently supporting RLC A"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x08 # RRC B
        @pc &+= 2
        raise "Not currently supporting RRC B"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x09 # RRC C
        @pc &+= 2
        raise "Not currently supporting RRC C"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x0A # RRC D
        @pc &+= 2
        raise "Not currently supporting RRC D"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x0B # RRC E
        @pc &+= 2
        raise "Not currently supporting RRC E"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x0C # RRC H
        @pc &+= 2
        raise "Not currently supporting RRC H"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x0D # RRC L
        @pc &+= 2
        raise "Not currently supporting RRC L"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x0E # RRC (HL)
        @pc &+= 2
        raise "Not currently supporting RRC (HL)"
        self.f_n = false
        self.f_h = false
        return 16
      when 0x0F # RRC A
        @pc &+= 2
        raise "Not currently supporting RRC A"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x10 # RL B
        @pc &+= 2
        carry = self.b & 0x80
        self.b = (self.b << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.b == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x11 # RL C
        @pc &+= 2
        carry = self.c & 0x80
        self.c = (self.c << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.c == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x12 # RL D
        @pc &+= 2
        carry = self.d & 0x80
        self.d = (self.d << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.d == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x13 # RL E
        @pc &+= 2
        carry = self.e & 0x80
        self.e = (self.e << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.e == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x14 # RL H
        @pc &+= 2
        carry = self.h & 0x80
        self.h = (self.h << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.h == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x15 # RL L
        @pc &+= 2
        carry = self.l & 0x80
        self.l = (self.l << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.l == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x16 # RL (HL)
        @pc &+= 2
        carry = @memory[self.hl] & 0x80
        @memory[self.hl] = (@memory[self.hl] << 1) + (self.f_c ? 1 : 0)
        self.f_z = @memory[self.hl] == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 16
      when 0x17 # RL A
        @pc &+= 2
        carry = self.a & 0x80
        self.a = (self.a << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.a == 0
        self.f_c = carry
        self.f_n = false
        self.f_h = false
        return 8
      when 0x18 # RR B
        @pc &+= 2
        raise "Not currently supporting RR B"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x19 # RR C
        @pc &+= 2
        raise "Not currently supporting RR C"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x1A # RR D
        @pc &+= 2
        raise "Not currently supporting RR D"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x1B # RR E
        @pc &+= 2
        raise "Not currently supporting RR E"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x1C # RR H
        @pc &+= 2
        raise "Not currently supporting RR H"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x1D # RR L
        @pc &+= 2
        raise "Not currently supporting RR L"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x1E # RR (HL)
        @pc &+= 2
        raise "Not currently supporting RR (HL)"
        self.f_n = false
        self.f_h = false
        return 16
      when 0x1F # RR A
        @pc &+= 2
        raise "Not currently supporting RR A"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x20 # SLA B
        @pc &+= 2
        raise "Not currently supporting SLA B"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x21 # SLA C
        @pc &+= 2
        raise "Not currently supporting SLA C"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x22 # SLA D
        @pc &+= 2
        raise "Not currently supporting SLA D"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x23 # SLA E
        @pc &+= 2
        raise "Not currently supporting SLA E"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x24 # SLA H
        @pc &+= 2
        raise "Not currently supporting SLA H"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x25 # SLA L
        @pc &+= 2
        raise "Not currently supporting SLA L"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x26 # SLA (HL)
        @pc &+= 2
        raise "Not currently supporting SLA (HL)"
        self.f_n = false
        self.f_h = false
        return 16
      when 0x27 # SLA A
        @pc &+= 2
        raise "Not currently supporting SLA A"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x28 # SRA B
        @pc &+= 2
        raise "Not currently supporting SRA B"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x29 # SRA C
        @pc &+= 2
        raise "Not currently supporting SRA C"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x2A # SRA D
        @pc &+= 2
        raise "Not currently supporting SRA D"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x2B # SRA E
        @pc &+= 2
        raise "Not currently supporting SRA E"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x2C # SRA H
        @pc &+= 2
        raise "Not currently supporting SRA H"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x2D # SRA L
        @pc &+= 2
        raise "Not currently supporting SRA L"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x2E # SRA (HL)
        @pc &+= 2
        raise "Not currently supporting SRA (HL)"
        self.f_n = false
        self.f_h = false
        return 16
      when 0x2F # SRA A
        @pc &+= 2
        raise "Not currently supporting SRA A"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x30 # SWAP B
        @pc &+= 2
        raise "Not currently supporting SWAP B"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x31 # SWAP C
        @pc &+= 2
        raise "Not currently supporting SWAP C"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x32 # SWAP D
        @pc &+= 2
        raise "Not currently supporting SWAP D"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x33 # SWAP E
        @pc &+= 2
        raise "Not currently supporting SWAP E"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x34 # SWAP H
        @pc &+= 2
        raise "Not currently supporting SWAP H"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x35 # SWAP L
        @pc &+= 2
        raise "Not currently supporting SWAP L"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x36 # SWAP (HL)
        @pc &+= 2
        raise "Not currently supporting SWAP (HL)"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 16
      when 0x37 # SWAP A
        @pc &+= 2
        raise "Not currently supporting SWAP A"
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x38 # SRL B
        @pc &+= 2
        raise "Not currently supporting SRL B"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x39 # SRL C
        @pc &+= 2
        raise "Not currently supporting SRL C"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x3A # SRL D
        @pc &+= 2
        raise "Not currently supporting SRL D"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x3B # SRL E
        @pc &+= 2
        raise "Not currently supporting SRL E"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x3C # SRL H
        @pc &+= 2
        raise "Not currently supporting SRL H"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x3D # SRL L
        @pc &+= 2
        raise "Not currently supporting SRL L"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x3E # SRL (HL)
        @pc &+= 2
        raise "Not currently supporting SRL (HL)"
        self.f_n = false
        self.f_h = false
        return 16
      when 0x3F # SRL A
        @pc &+= 2
        raise "Not currently supporting SRL A"
        self.f_n = false
        self.f_h = false
        return 8
      when 0x40 # BIT 0,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x41 # BIT 0,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x42 # BIT 0,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x43 # BIT 0,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x44 # BIT 0,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x45 # BIT 0,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x46 # BIT 0,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x47 # BIT 0,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 0) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x48 # BIT 1,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x49 # BIT 1,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x4A # BIT 1,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x4B # BIT 1,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x4C # BIT 1,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x4D # BIT 1,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x4E # BIT 1,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x4F # BIT 1,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 1) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x50 # BIT 2,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x51 # BIT 2,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x52 # BIT 2,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x53 # BIT 2,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x54 # BIT 2,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x55 # BIT 2,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x56 # BIT 2,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x57 # BIT 2,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 2) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x58 # BIT 3,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x59 # BIT 3,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x5A # BIT 3,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x5B # BIT 3,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x5C # BIT 3,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x5D # BIT 3,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x5E # BIT 3,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x5F # BIT 3,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 3) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x60 # BIT 4,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x61 # BIT 4,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x62 # BIT 4,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x63 # BIT 4,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x64 # BIT 4,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x65 # BIT 4,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x66 # BIT 4,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x67 # BIT 4,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 4) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x68 # BIT 5,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x69 # BIT 5,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x6A # BIT 5,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x6B # BIT 5,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x6C # BIT 5,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x6D # BIT 5,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x6E # BIT 5,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x6F # BIT 5,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 5) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x70 # BIT 6,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x71 # BIT 6,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x72 # BIT 6,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x73 # BIT 6,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x74 # BIT 6,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x75 # BIT 6,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x76 # BIT 6,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x77 # BIT 6,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 6) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x78 # BIT 7,B
        @pc &+= 2
        self.f_z = self.b & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x79 # BIT 7,C
        @pc &+= 2
        self.f_z = self.c & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x7A # BIT 7,D
        @pc &+= 2
        self.f_z = self.d & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x7B # BIT 7,E
        @pc &+= 2
        self.f_z = self.e & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x7C # BIT 7,H
        @pc &+= 2
        self.f_z = self.h & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x7D # BIT 7,L
        @pc &+= 2
        self.f_z = self.l & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x7E # BIT 7,(HL)
        @pc &+= 2
        self.f_z = @memory[self.hl] & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 12
      when 0x7F # BIT 7,A
        @pc &+= 2
        self.f_z = self.a & (0x1 << 7) == 0
        self.f_n = false
        self.f_h = true
        return 8
      when 0x80 # RES 0,B
        @pc &+= 2
        raise "Not currently supporting RES 0,B"
        return 8
      when 0x81 # RES 0,C
        @pc &+= 2
        raise "Not currently supporting RES 0,C"
        return 8
      when 0x82 # RES 0,D
        @pc &+= 2
        raise "Not currently supporting RES 0,D"
        return 8
      when 0x83 # RES 0,E
        @pc &+= 2
        raise "Not currently supporting RES 0,E"
        return 8
      when 0x84 # RES 0,H
        @pc &+= 2
        raise "Not currently supporting RES 0,H"
        return 8
      when 0x85 # RES 0,L
        @pc &+= 2
        raise "Not currently supporting RES 0,L"
        return 8
      when 0x86 # RES 0,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 0,(HL)"
        return 16
      when 0x87 # RES 0,A
        @pc &+= 2
        raise "Not currently supporting RES 0,A"
        return 8
      when 0x88 # RES 1,B
        @pc &+= 2
        raise "Not currently supporting RES 1,B"
        return 8
      when 0x89 # RES 1,C
        @pc &+= 2
        raise "Not currently supporting RES 1,C"
        return 8
      when 0x8A # RES 1,D
        @pc &+= 2
        raise "Not currently supporting RES 1,D"
        return 8
      when 0x8B # RES 1,E
        @pc &+= 2
        raise "Not currently supporting RES 1,E"
        return 8
      when 0x8C # RES 1,H
        @pc &+= 2
        raise "Not currently supporting RES 1,H"
        return 8
      when 0x8D # RES 1,L
        @pc &+= 2
        raise "Not currently supporting RES 1,L"
        return 8
      when 0x8E # RES 1,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 1,(HL)"
        return 16
      when 0x8F # RES 1,A
        @pc &+= 2
        raise "Not currently supporting RES 1,A"
        return 8
      when 0x90 # RES 2,B
        @pc &+= 2
        raise "Not currently supporting RES 2,B"
        return 8
      when 0x91 # RES 2,C
        @pc &+= 2
        raise "Not currently supporting RES 2,C"
        return 8
      when 0x92 # RES 2,D
        @pc &+= 2
        raise "Not currently supporting RES 2,D"
        return 8
      when 0x93 # RES 2,E
        @pc &+= 2
        raise "Not currently supporting RES 2,E"
        return 8
      when 0x94 # RES 2,H
        @pc &+= 2
        raise "Not currently supporting RES 2,H"
        return 8
      when 0x95 # RES 2,L
        @pc &+= 2
        raise "Not currently supporting RES 2,L"
        return 8
      when 0x96 # RES 2,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 2,(HL)"
        return 16
      when 0x97 # RES 2,A
        @pc &+= 2
        raise "Not currently supporting RES 2,A"
        return 8
      when 0x98 # RES 3,B
        @pc &+= 2
        raise "Not currently supporting RES 3,B"
        return 8
      when 0x99 # RES 3,C
        @pc &+= 2
        raise "Not currently supporting RES 3,C"
        return 8
      when 0x9A # RES 3,D
        @pc &+= 2
        raise "Not currently supporting RES 3,D"
        return 8
      when 0x9B # RES 3,E
        @pc &+= 2
        raise "Not currently supporting RES 3,E"
        return 8
      when 0x9C # RES 3,H
        @pc &+= 2
        raise "Not currently supporting RES 3,H"
        return 8
      when 0x9D # RES 3,L
        @pc &+= 2
        raise "Not currently supporting RES 3,L"
        return 8
      when 0x9E # RES 3,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 3,(HL)"
        return 16
      when 0x9F # RES 3,A
        @pc &+= 2
        raise "Not currently supporting RES 3,A"
        return 8
      when 0xA0 # RES 4,B
        @pc &+= 2
        raise "Not currently supporting RES 4,B"
        return 8
      when 0xA1 # RES 4,C
        @pc &+= 2
        raise "Not currently supporting RES 4,C"
        return 8
      when 0xA2 # RES 4,D
        @pc &+= 2
        raise "Not currently supporting RES 4,D"
        return 8
      when 0xA3 # RES 4,E
        @pc &+= 2
        raise "Not currently supporting RES 4,E"
        return 8
      when 0xA4 # RES 4,H
        @pc &+= 2
        raise "Not currently supporting RES 4,H"
        return 8
      when 0xA5 # RES 4,L
        @pc &+= 2
        raise "Not currently supporting RES 4,L"
        return 8
      when 0xA6 # RES 4,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 4,(HL)"
        return 16
      when 0xA7 # RES 4,A
        @pc &+= 2
        raise "Not currently supporting RES 4,A"
        return 8
      when 0xA8 # RES 5,B
        @pc &+= 2
        raise "Not currently supporting RES 5,B"
        return 8
      when 0xA9 # RES 5,C
        @pc &+= 2
        raise "Not currently supporting RES 5,C"
        return 8
      when 0xAA # RES 5,D
        @pc &+= 2
        raise "Not currently supporting RES 5,D"
        return 8
      when 0xAB # RES 5,E
        @pc &+= 2
        raise "Not currently supporting RES 5,E"
        return 8
      when 0xAC # RES 5,H
        @pc &+= 2
        raise "Not currently supporting RES 5,H"
        return 8
      when 0xAD # RES 5,L
        @pc &+= 2
        raise "Not currently supporting RES 5,L"
        return 8
      when 0xAE # RES 5,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 5,(HL)"
        return 16
      when 0xAF # RES 5,A
        @pc &+= 2
        raise "Not currently supporting RES 5,A"
        return 8
      when 0xB0 # RES 6,B
        @pc &+= 2
        raise "Not currently supporting RES 6,B"
        return 8
      when 0xB1 # RES 6,C
        @pc &+= 2
        raise "Not currently supporting RES 6,C"
        return 8
      when 0xB2 # RES 6,D
        @pc &+= 2
        raise "Not currently supporting RES 6,D"
        return 8
      when 0xB3 # RES 6,E
        @pc &+= 2
        raise "Not currently supporting RES 6,E"
        return 8
      when 0xB4 # RES 6,H
        @pc &+= 2
        raise "Not currently supporting RES 6,H"
        return 8
      when 0xB5 # RES 6,L
        @pc &+= 2
        raise "Not currently supporting RES 6,L"
        return 8
      when 0xB6 # RES 6,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 6,(HL)"
        return 16
      when 0xB7 # RES 6,A
        @pc &+= 2
        raise "Not currently supporting RES 6,A"
        return 8
      when 0xB8 # RES 7,B
        @pc &+= 2
        raise "Not currently supporting RES 7,B"
        return 8
      when 0xB9 # RES 7,C
        @pc &+= 2
        raise "Not currently supporting RES 7,C"
        return 8
      when 0xBA # RES 7,D
        @pc &+= 2
        raise "Not currently supporting RES 7,D"
        return 8
      when 0xBB # RES 7,E
        @pc &+= 2
        raise "Not currently supporting RES 7,E"
        return 8
      when 0xBC # RES 7,H
        @pc &+= 2
        raise "Not currently supporting RES 7,H"
        return 8
      when 0xBD # RES 7,L
        @pc &+= 2
        raise "Not currently supporting RES 7,L"
        return 8
      when 0xBE # RES 7,(HL)
        @pc &+= 2
        raise "Not currently supporting RES 7,(HL)"
        return 16
      when 0xBF # RES 7,A
        @pc &+= 2
        raise "Not currently supporting RES 7,A"
        return 8
      when 0xC0 # SET 0,B
        @pc &+= 2
        self.b |= (0x1 << 0)
        return 8
      when 0xC1 # SET 0,C
        @pc &+= 2
        self.c |= (0x1 << 0)
        return 8
      when 0xC2 # SET 0,D
        @pc &+= 2
        self.d |= (0x1 << 0)
        return 8
      when 0xC3 # SET 0,E
        @pc &+= 2
        self.e |= (0x1 << 0)
        return 8
      when 0xC4 # SET 0,H
        @pc &+= 2
        self.h |= (0x1 << 0)
        return 8
      when 0xC5 # SET 0,L
        @pc &+= 2
        self.l |= (0x1 << 0)
        return 8
      when 0xC6 # SET 0,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 0)
        return 16
      when 0xC7 # SET 0,A
        @pc &+= 2
        self.a |= (0x1 << 0)
        return 8
      when 0xC8 # SET 1,B
        @pc &+= 2
        self.b |= (0x1 << 1)
        return 8
      when 0xC9 # SET 1,C
        @pc &+= 2
        self.c |= (0x1 << 1)
        return 8
      when 0xCA # SET 1,D
        @pc &+= 2
        self.d |= (0x1 << 1)
        return 8
      when 0xCB # SET 1,E
        @pc &+= 2
        self.e |= (0x1 << 1)
        return 8
      when 0xCC # SET 1,H
        @pc &+= 2
        self.h |= (0x1 << 1)
        return 8
      when 0xCD # SET 1,L
        @pc &+= 2
        self.l |= (0x1 << 1)
        return 8
      when 0xCE # SET 1,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 1)
        return 16
      when 0xCF # SET 1,A
        @pc &+= 2
        self.a |= (0x1 << 1)
        return 8
      when 0xD0 # SET 2,B
        @pc &+= 2
        self.b |= (0x1 << 2)
        return 8
      when 0xD1 # SET 2,C
        @pc &+= 2
        self.c |= (0x1 << 2)
        return 8
      when 0xD2 # SET 2,D
        @pc &+= 2
        self.d |= (0x1 << 2)
        return 8
      when 0xD3 # SET 2,E
        @pc &+= 2
        self.e |= (0x1 << 2)
        return 8
      when 0xD4 # SET 2,H
        @pc &+= 2
        self.h |= (0x1 << 2)
        return 8
      when 0xD5 # SET 2,L
        @pc &+= 2
        self.l |= (0x1 << 2)
        return 8
      when 0xD6 # SET 2,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 2)
        return 16
      when 0xD7 # SET 2,A
        @pc &+= 2
        self.a |= (0x1 << 2)
        return 8
      when 0xD8 # SET 3,B
        @pc &+= 2
        self.b |= (0x1 << 3)
        return 8
      when 0xD9 # SET 3,C
        @pc &+= 2
        self.c |= (0x1 << 3)
        return 8
      when 0xDA # SET 3,D
        @pc &+= 2
        self.d |= (0x1 << 3)
        return 8
      when 0xDB # SET 3,E
        @pc &+= 2
        self.e |= (0x1 << 3)
        return 8
      when 0xDC # SET 3,H
        @pc &+= 2
        self.h |= (0x1 << 3)
        return 8
      when 0xDD # SET 3,L
        @pc &+= 2
        self.l |= (0x1 << 3)
        return 8
      when 0xDE # SET 3,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 3)
        return 16
      when 0xDF # SET 3,A
        @pc &+= 2
        self.a |= (0x1 << 3)
        return 8
      when 0xE0 # SET 4,B
        @pc &+= 2
        self.b |= (0x1 << 4)
        return 8
      when 0xE1 # SET 4,C
        @pc &+= 2
        self.c |= (0x1 << 4)
        return 8
      when 0xE2 # SET 4,D
        @pc &+= 2
        self.d |= (0x1 << 4)
        return 8
      when 0xE3 # SET 4,E
        @pc &+= 2
        self.e |= (0x1 << 4)
        return 8
      when 0xE4 # SET 4,H
        @pc &+= 2
        self.h |= (0x1 << 4)
        return 8
      when 0xE5 # SET 4,L
        @pc &+= 2
        self.l |= (0x1 << 4)
        return 8
      when 0xE6 # SET 4,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 4)
        return 16
      when 0xE7 # SET 4,A
        @pc &+= 2
        self.a |= (0x1 << 4)
        return 8
      when 0xE8 # SET 5,B
        @pc &+= 2
        self.b |= (0x1 << 5)
        return 8
      when 0xE9 # SET 5,C
        @pc &+= 2
        self.c |= (0x1 << 5)
        return 8
      when 0xEA # SET 5,D
        @pc &+= 2
        self.d |= (0x1 << 5)
        return 8
      when 0xEB # SET 5,E
        @pc &+= 2
        self.e |= (0x1 << 5)
        return 8
      when 0xEC # SET 5,H
        @pc &+= 2
        self.h |= (0x1 << 5)
        return 8
      when 0xED # SET 5,L
        @pc &+= 2
        self.l |= (0x1 << 5)
        return 8
      when 0xEE # SET 5,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 5)
        return 16
      when 0xEF # SET 5,A
        @pc &+= 2
        self.a |= (0x1 << 5)
        return 8
      when 0xF0 # SET 6,B
        @pc &+= 2
        self.b |= (0x1 << 6)
        return 8
      when 0xF1 # SET 6,C
        @pc &+= 2
        self.c |= (0x1 << 6)
        return 8
      when 0xF2 # SET 6,D
        @pc &+= 2
        self.d |= (0x1 << 6)
        return 8
      when 0xF3 # SET 6,E
        @pc &+= 2
        self.e |= (0x1 << 6)
        return 8
      when 0xF4 # SET 6,H
        @pc &+= 2
        self.h |= (0x1 << 6)
        return 8
      when 0xF5 # SET 6,L
        @pc &+= 2
        self.l |= (0x1 << 6)
        return 8
      when 0xF6 # SET 6,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 6)
        return 16
      when 0xF7 # SET 6,A
        @pc &+= 2
        self.a |= (0x1 << 6)
        return 8
      when 0xF8 # SET 7,B
        @pc &+= 2
        self.b |= (0x1 << 7)
        return 8
      when 0xF9 # SET 7,C
        @pc &+= 2
        self.c |= (0x1 << 7)
        return 8
      when 0xFA # SET 7,D
        @pc &+= 2
        self.d |= (0x1 << 7)
        return 8
      when 0xFB # SET 7,E
        @pc &+= 2
        self.e |= (0x1 << 7)
        return 8
      when 0xFC # SET 7,H
        @pc &+= 2
        self.h |= (0x1 << 7)
        return 8
      when 0xFD # SET 7,L
        @pc &+= 2
        self.l |= (0x1 << 7)
        return 8
      when 0xFE # SET 7,(HL)
        @pc &+= 2
        @memory[self.hl] |= (0x1 << 7)
        return 16
      when 0xFF # SET 7,A
        @pc &+= 2
        self.a |= (0x1 << 7)
        return 8
      end
    end
    raise "Will never be reached, but the compiler doesn't seem to recognize that."
  end
end
