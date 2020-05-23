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

    def {{upper.id}}=(value : UInt8)
      @{{upper.id}} = value {% if mask %} & ({{mask.id}} >> 8) {% end %}
    end

    def {{lower.id}} : UInt8
      @{{lower.id}} {% if mask %} & {{mask.id}} {% end %}
    end

    def {{lower.id}}=(value : UInt8)
      @{{lower.id}} = value {% if mask %} & {{mask.id}} {% end %}
    end

    def {{upper.id}}{{lower.id}} : UInt16
      (self.{{upper}}.to_u16 << 8 | self.{{lower}}.to_u16).not_nil!
    end

    def {{upper.id}}{{lower.id}}=(value : UInt16)
      self.{{upper.id}} = (value >> 8).to_u8
      self.{{lower.id}} = (value & 0xFF).to_u8
    end

    def {{upper.id}}{{lower.id}}=(value : UInt8)
      self.{{upper.id}} = 0_u8
      self.{{lower.id}} = value
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
    end
    # bit 1: lcd stat
    if @memory.lcd_stat && @memory.lcd_stat_enabled
      @memory.lcd_stat = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0048_u16
    end
    # bit 2: timer
    if @memory.timer && @memory.timer_enabled
      @memory.timer = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0050_u16
    end
    # bit 3: serial
    if @memory.serial && @memory.serial_enabled
      @memory.serial = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0058_u16
    end
    # bit 4: joypad
    if @memory.joypad && @memory.joypad_enabled
      @memory.joypad = false
      @sp -= 2
      @memory[@sp] = @pc
      @pc = 0x0060_u16
    end
    # clear Interrupt Master Enable
    @ime = false
  end

  # Runs for the specified number of machine cycles. If no argument provided,
  # runs only one instruction. Handles interrupts _after_ the instruction is
  # executed.
  def tick(cycles = 1)
    while cycles > 0
      opcode = read_opcode
      cycles -= process_opcode opcode
      # interrupts
      if opcode == 0x76
        puts "HALT, who goes there (todo)"
      end
      handle_interrupts if @ime
    end
  end

  def read_opcode : UInt8
    @memory[@pc]
  end

  # process the given opcode
  # returns the number of machine cycles taken (where gb runs at 4.19MHz)
  def process_opcode(opcode : UInt8, cb = false) : Int32
    # puts "op:#{hex_str opcode}, pc:#{hex_str @pc}, sp:#{hex_str @sp}, a:#{hex_str self.a}, b:#{hex_str self.b}, c:#{hex_str self.c}, d:#{hex_str self.d}, e:#{hex_str self.e}, h:#{hex_str self.h}, l:#{hex_str self.l}, f:#{self.f.to_s(2).rjust(8, '0')}"
    # all cb-prefixed opcodes have a length of 1 + the prefix
    length = cb ? 1 : OPCODE_LENGTHS[opcode]
    d8 : UInt8 = 0_u8
    d16 : UInt16 = 0_u16
    if length == 2
      d8 = @memory[@pc + 1]
    elsif length == 3
      d16 = @memory.read_word @pc + 1
    end
    r8 : Int8 = d8.to_i8!
    # puts "op:#{hex_str opcode}, pc:#{hex_str @pc}, sp:#{hex_str @sp}, af:#{hex_str self.af}, bc:#{hex_str self.bc}, de:#{hex_str self.de}, hl:#{hex_str self.hl}, flags:#{self.f.to_s(2).rjust(8, '0')}, d8:#{hex_str d8}, d16:#{hex_str d16}"
    @pc += length

    # Everything below is automatically generated. Once the codegen code is
    # finished and cleaned up, I'll add it to the repo as well.
    if !cb
      case opcode
      when 0x00
        return 4
      when 0x01
        self.bc = d16
        return 12
      when 0x02
        @memory[self.bc] = self.a
        return 8
      when 0x03
        self.bc = add self.bc, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x04
        self.b = add self.b, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x05
        self.b = sub self.b, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x06
        self.b = d8
        return 8
      when 0x07
        self.f_z = false
        self.f_n = false
        self.f_h = false
        self.f_c = self.a & 0x80
        self.a = (self.a << 1) + (self.a >> 7)
        return 4
      when 0x08
        @memory[d16] = @sp
        return 20
      when 0x09
        self.hl = add self.hl, self.bc, z = FlagOp::UNCHANGED, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x0A
        self.a = @memory[self.bc]
        return 8
      when 0x0B
        self.bc = sub self.bc, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x0C
        self.c = add self.c, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x0D
        self.c = sub self.c, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x0E
        self.c = d8
        return 8
      when 0x0F
        self.f_z = false
        self.f_n = false
        self.f_h = false
        self.f_c = self.a & 0x1
        self.a = (self.a >> 1) + (self.a << 7)
        return 4
      when 0x10
        raise "FAILED TO MATCH 0x10"
      when 0x11
        self.de = d16
        return 12
      when 0x12
        @memory[self.de] = self.a
        return 8
      when 0x13
        self.de = add self.de, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x14
        self.d = add self.d, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x15
        self.d = sub self.d, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x16
        self.d = d8
        return 8
      when 0x17
        carry = self.a & 0x80
        self.a = (self.a << 1) + (self.f_c ? 1 : 0)
        self.f_z = false
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 4
      when 0x18
        @pc &+= r8
        return 12
      when 0x19
        self.hl = add self.hl, self.de, z = FlagOp::UNCHANGED, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x1A
        self.a = @memory[self.de]
        return 8
      when 0x1B
        self.de = sub self.de, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x1C
        self.e = add self.e, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x1D
        self.e = sub self.e, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x1E
        self.e = d8
        return 8
      when 0x1F
        carry = self.a & 0x01
        self.a = (self.a >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 4
      when 0x20
        if self.f_nz
          @pc &+= r8
          return 12
        end
        return 8
      when 0x21
        self.hl = d16
        return 12
      when 0x22
        @memory[self.hl] = self.a
        self.hl &+= 1
        return 8
      when 0x23
        self.hl = add self.hl, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x24
        self.h = add self.h, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x25
        self.h = sub self.h, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x26
        self.h = d8
        return 8
      when 0x27
        if self.f_n == 0 # last op was an addition
          if self.f_c || self.a > 0x99
            self.a &+= 0x60
            self.f_c = true
          end
          if self.f_h || self.a & 0x0F > 0x09
            self.a &+= 0x06
          end
        else # last op was a subtraction
          self.a &-= 0x60 if self.f_c
          self.a &-= 0x06 if self.f_h
        end
        return 4
      when 0x28
        if self.f_z
          @pc &+= r8
          return 12
        end
        return 8
      when 0x29
        self.hl = add self.hl, self.hl, z = FlagOp::UNCHANGED, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x2A
        self.a = @memory[self.hl]
        self.hl &+= 1
        return 8
      when 0x2B
        self.hl = sub self.hl, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x2C
        self.l = add self.l, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x2D
        self.l = sub self.l, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x2E
        self.l = d8
        return 8
      when 0x2F
        self.a = ~self.a
        self.f_n = true
        self.f_h = true
        return 4
      when 0x30
        if self.f_nc
          @pc &+= r8
          return 12
        end
        return 8
      when 0x31
        @sp = d16
        return 12
      when 0x32
        @memory[self.hl] = self.a
        self.hl &-= 1
        return 8
      when 0x33
        @sp = add @sp, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x34
        @memory[self.hl] = add @memory[self.hl], 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 12
      when 0x35
        @memory[self.hl] = sub @memory[self.hl], 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 12
      when 0x36
        @memory[self.hl] = d8
        return 12
      when 0x37
        self.f_n = false
        self.f_h = false
        self.f_c = true
        return 4
      when 0x38
        if self.f_c
          @pc &+= r8
          return 12
        end
        return 8
      when 0x39
        self.hl = add self.hl, @sp, z = FlagOp::UNCHANGED, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x3A
        self.a = @memory[self.hl]
        self.hl &-= 1
        return 8
      when 0x3B
        @sp = sub @sp, 1_u16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED
        return 8
      when 0x3C
        self.a = add self.a, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x3D
        self.a = sub self.a, 1_u16, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::UNCHANGED
        return 4
      when 0x3E
        self.a = d8
        return 8
      when 0x3F
        self.f_n = false
        self.f_h = false
        self.f_c = !self.f_c
        return 4
      when 0x40
        # self.b = self.b
        return 4
      when 0x41
        self.b = self.c
        return 4
      when 0x42
        self.b = self.d
        return 4
      when 0x43
        self.b = self.e
        return 4
      when 0x44
        self.b = self.h
        return 4
      when 0x45
        self.b = self.l
        return 4
      when 0x46
        self.b = @memory[self.hl]
        return 8
      when 0x47
        self.b = self.a
        return 4
      when 0x48
        self.c = self.b
        return 4
      when 0x49
        # self.c = self.c
        return 4
      when 0x4A
        self.c = self.d
        return 4
      when 0x4B
        self.c = self.e
        return 4
      when 0x4C
        self.c = self.h
        return 4
      when 0x4D
        self.c = self.l
        return 4
      when 0x4E
        self.c = @memory[self.hl]
        return 8
      when 0x4F
        self.c = self.a
        return 4
      when 0x50
        self.d = self.b
        return 4
      when 0x51
        self.d = self.c
        return 4
      when 0x52
        # self.d = self.d
        return 4
      when 0x53
        self.d = self.e
        return 4
      when 0x54
        self.d = self.h
        return 4
      when 0x55
        self.d = self.l
        return 4
      when 0x56
        self.d = @memory[self.hl]
        return 8
      when 0x57
        self.d = self.a
        return 4
      when 0x58
        self.e = self.b
        return 4
      when 0x59
        self.e = self.c
        return 4
      when 0x5A
        self.e = self.d
        return 4
      when 0x5B
        # self.e = self.e
        return 4
      when 0x5C
        self.e = self.h
        return 4
      when 0x5D
        self.e = self.l
        return 4
      when 0x5E
        self.e = @memory[self.hl]
        return 8
      when 0x5F
        self.e = self.a
        return 4
      when 0x60
        self.h = self.b
        return 4
      when 0x61
        self.h = self.c
        return 4
      when 0x62
        self.h = self.d
        return 4
      when 0x63
        self.h = self.e
        return 4
      when 0x64
        # self.h = self.h
        return 4
      when 0x65
        self.h = self.l
        return 4
      when 0x66
        self.h = @memory[self.hl]
        return 8
      when 0x67
        self.h = self.a
        return 4
      when 0x68
        self.l = self.b
        return 4
      when 0x69
        self.l = self.c
        return 4
      when 0x6A
        self.l = self.d
        return 4
      when 0x6B
        self.l = self.e
        return 4
      when 0x6C
        self.l = self.h
        return 4
      when 0x6D
        # self.l = self.l
        return 4
      when 0x6E
        self.l = @memory[self.hl]
        return 8
      when 0x6F
        self.l = self.a
        return 4
      when 0x70
        @memory[self.hl] = self.b
        return 8
      when 0x71
        @memory[self.hl] = self.c
        return 8
      when 0x72
        @memory[self.hl] = self.d
        return 8
      when 0x73
        @memory[self.hl] = self.e
        return 8
      when 0x74
        @memory[self.hl] = self.h
        return 8
      when 0x75
        @memory[self.hl] = self.l
        return 8
      when 0x76
        raise "FAILED TO MATCH 0x76"
      when 0x77
        @memory[self.hl] = self.a
        return 8
      when 0x78
        self.a = self.b
        return 4
      when 0x79
        self.a = self.c
        return 4
      when 0x7A
        self.a = self.d
        return 4
      when 0x7B
        self.a = self.e
        return 4
      when 0x7C
        self.a = self.h
        return 4
      when 0x7D
        self.a = self.l
        return 4
      when 0x7E
        self.a = @memory[self.hl]
        return 8
      when 0x7F
        # self.a = self.a
        return 4
      when 0x80
        self.a = add self.a, self.b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x81
        self.a = add self.a, self.c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x82
        self.a = add self.a, self.d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x83
        self.a = add self.a, self.e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x84
        self.a = add self.a, self.h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x85
        self.a = add self.a, self.l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x86
        self.a = add self.a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x87
        self.a = add self.a, self.a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x88
        self.a = adc self.a, self.b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x89
        self.a = adc self.a, self.c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x8A
        self.a = adc self.a, self.d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x8B
        self.a = adc self.a, self.e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x8C
        self.a = adc self.a, self.h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x8D
        self.a = adc self.a, self.l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x8E
        self.a = adc self.a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x8F
        self.a = adc self.a, self.a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x90
        self.f_z = self.a == self.b
        self.f_n = true
        self.f_h = self.a & 0xF < self.b & 0xF
        self.f_c = self.a < self.b
        self.a &-= self.b
        return 4
      when 0x91
        self.f_z = self.a == self.c
        self.f_n = true
        self.f_h = self.a & 0xF < self.c & 0xF
        self.f_c = self.a < self.c
        self.a &-= self.c
        return 4
      when 0x92
        self.f_z = self.a == self.d
        self.f_n = true
        self.f_h = self.a & 0xF < self.d & 0xF
        self.f_c = self.a < self.d
        self.a &-= self.d
        return 4
      when 0x93
        self.f_z = self.a == self.e
        self.f_n = true
        self.f_h = self.a & 0xF < self.e & 0xF
        self.f_c = self.a < self.e
        self.a &-= self.e
        return 4
      when 0x94
        self.f_z = self.a == self.h
        self.f_n = true
        self.f_h = self.a & 0xF < self.h & 0xF
        self.f_c = self.a < self.h
        self.a &-= self.h
        return 4
      when 0x95
        self.f_z = self.a == self.l
        self.f_n = true
        self.f_h = self.a & 0xF < self.l & 0xF
        self.f_c = self.a < self.l
        self.a &-= self.l
        return 4
      when 0x96
        self.f_z = self.a == @memory[self.hl]
        self.f_n = true
        self.f_h = self.a & 0xF < @memory[self.hl] & 0xF
        self.f_c = self.a < @memory[self.hl]
        self.a &-= @memory[self.hl]
        return 8
      when 0x97
        self.f_z = self.a == self.a
        self.f_n = true
        self.f_h = self.a & 0xF < self.a & 0xF
        self.f_c = self.a < self.a
        self.a &-= self.a
        return 4
      when 0x98
        self.a = sbc self.a, self.b, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x99
        self.a = sbc self.a, self.c, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x9A
        self.a = sbc self.a, self.d, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x9B
        self.a = sbc self.a, self.e, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x9C
        self.a = sbc self.a, self.h, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x9D
        self.a = sbc self.a, self.l, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0x9E
        self.a = sbc self.a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0x9F
        self.a = sbc self.a, self.a, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 4
      when 0xA0
        self.a = and self.a, self.b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA1
        self.a = and self.a, self.c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA2
        self.a = and self.a, self.d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA3
        self.a = and self.a, self.e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA4
        self.a = and self.a, self.h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA5
        self.a = and self.a, self.l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA6
        self.a = and self.a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 8
      when 0xA7
        self.a = and self.a, self.a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 4
      when 0xA8
        self.a = xor self.a, self.b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xA9
        self.a = xor self.a, self.c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xAA
        self.a = xor self.a, self.d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xAB
        self.a = xor self.a, self.e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xAC
        self.a = xor self.a, self.h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xAD
        self.a = xor self.a, self.l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xAE
        self.a = xor self.a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 8
      when 0xAF
        self.a = xor self.a, self.a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB0
        self.a = or self.a, self.b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB1
        self.a = or self.a, self.c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB2
        self.a = or self.a, self.d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB3
        self.a = or self.a, self.e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB4
        self.a = or self.a, self.h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB5
        self.a = or self.a, self.l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB6
        self.a = or self.a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 8
      when 0xB7
        self.a = or self.a, self.a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 4
      when 0xB8
        self.f_z = self.a == self.b
        self.f_n = true
        self.f_h = self.a & 0xF < self.b & 0xF
        self.f_c = self.a < self.b
        return 4
      when 0xB9
        self.f_z = self.a == self.c
        self.f_n = true
        self.f_h = self.a & 0xF < self.c & 0xF
        self.f_c = self.a < self.c
        return 4
      when 0xBA
        self.f_z = self.a == self.d
        self.f_n = true
        self.f_h = self.a & 0xF < self.d & 0xF
        self.f_c = self.a < self.d
        return 4
      when 0xBB
        self.f_z = self.a == self.e
        self.f_n = true
        self.f_h = self.a & 0xF < self.e & 0xF
        self.f_c = self.a < self.e
        return 4
      when 0xBC
        self.f_z = self.a == self.h
        self.f_n = true
        self.f_h = self.a & 0xF < self.h & 0xF
        self.f_c = self.a < self.h
        return 4
      when 0xBD
        self.f_z = self.a == self.l
        self.f_n = true
        self.f_h = self.a & 0xF < self.l & 0xF
        self.f_c = self.a < self.l
        return 4
      when 0xBE
        self.f_z = self.a == @memory[self.hl]
        self.f_n = true
        self.f_h = self.a & 0xF < @memory[self.hl] & 0xF
        self.f_c = self.a < @memory[self.hl]
        return 8
      when 0xBF
        self.f_z = self.a == self.a
        self.f_n = true
        self.f_h = self.a & 0xF < self.a & 0xF
        self.f_c = self.a < self.a
        return 4
      when 0xC0
        if self.f_nz
          @pc = @memory.read_word @sp; @sp += 2
          return 20
        end
        return 8
      when 0xC1
        self.bc = pop
        return 12
      when 0xC2
        if self.f_nz
          @pc = d16.to_u16
          return 16
        end
        return 12
      when 0xC3
        @pc = d16.to_u16
        return 16
      when 0xC4
        if self.f_nz
          @sp -= 2
          @memory[@sp] = @pc
          @pc = d16
          return 24
        end
        return 12
      when 0xC5
        push self.bc
        return 16
      when 0xC6
        self.a = add self.a, d8, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0xC7
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0000_u16
        return 16
      when 0xC8
        if self.f_z
          @pc = @memory.read_word @sp; @sp += 2
          return 20
        end
        return 8
      when 0xC9
        @pc = @memory.read_word @sp; @sp += 2
        return 16
        return 16
      when 0xCA
        if self.f_z
          @pc = d16.to_u16
          return 16
        end
        return 12
      when 0xCB
        # todo: This should operate as a seperate instruction, but can't be interrupted.
        #       This will require a restructure where the CPU leads the timing, rather than the PPU.
        #       https://discordapp.com/channels/465585922579103744/465586075830845475/712358911151177818
        #       https://discordapp.com/channels/465585922579103744/465586075830845475/712359253255520328
        next_op = read_opcode
        return process_opcode next_op, cb = true
        return 4
      when 0xCC
        if self.f_z
          @sp -= 2
          @memory[@sp] = @pc
          @pc = d16
          return 24
        end
        return 12
      when 0xCD
        @sp -= 2
        @memory[@sp] = @pc
        @pc = d16
        return 24
        return 24
      when 0xCE
        self.a = adc self.a, d8, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0xCF
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0008_u16
        return 16
      when 0xD0
        if self.f_nc
          @pc = @memory.read_word @sp; @sp += 2
          return 20
        end
        return 8
      when 0xD1
        self.de = pop
        return 12
      when 0xD2
        if self.f_nc
          @pc = d16.to_u16
          return 16
        end
        return 12
        # 0xD3 has no functionality
      when 0xD4
        if self.f_nc
          @sp -= 2
          @memory[@sp] = @pc
          @pc = d16
          return 24
        end
        return 12
      when 0xD5
        push self.de
        return 16
      when 0xD6
        self.f_z = self.a == d8
        self.f_n = true
        self.f_h = self.a & 0xF < d8 & 0xF
        self.f_c = self.a < d8
        self.a &-= d8
        return 8
      when 0xD7
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0010_u16
        return 16
      when 0xD8
        if self.f_c
          @pc = @memory.read_word @sp; @sp += 2
          return 20
        end
        return 8
      when 0xD9
        @ime = true
        @pc = @memory.read_word @sp; @sp += 2
        return 16
        return 16
      when 0xDA
        if self.f_c
          @pc = d16.to_u16
          return 16
        end
        return 12
        # 0xDB has no functionality
      when 0xDC
        if self.f_c
          @sp -= 2
          @memory[@sp] = @pc
          @pc = d16
          return 24
        end
        return 12
        # 0xDD has no functionality
      when 0xDE
        self.a = sbc self.a, d8, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 8
      when 0xDF
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0018_u16
        return 16
      when 0xE0
        @memory[0xFF00 + d8] = self.a
        return 12
      when 0xE1
        self.hl = pop
        return 12
      when 0xE2
        @memory[0xFF00 + self.c] = self.a
        return 8
        # 0xE3 has no functionality
        # 0xE4 has no functionality
      when 0xE5
        push self.hl
        return 16
      when 0xE6
        self.a = and self.a, d8, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
        return 8
      when 0xE7
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0020_u16
        return 16
      when 0xE8
        @sp = add @sp, r8, z = FlagOp::ZERO, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
        return 16
      when 0xE9
        @pc = self.hl.to_u16
        return 4
      when 0xEA
        @memory[d16] = self.a
        return 16
        # 0xEB has no functionality
        # 0xEC has no functionality
        # 0xED has no functionality
      when 0xEE
        self.a = xor self.a, d8, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 8
      when 0xEF
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0028_u16
        return 16
      when 0xF0
        self.a = @memory[0xFF00 + d8]
        return 12
      when 0xF1
        self.af = pop
        return 12
      when 0xF2
        self.a = @memory[0xFF00 + self.c]
        return 8
      when 0xF3
        @ime = false
        return 4
        # 0xF4 has no functionality
      when 0xF5
        push self.af
        return 16
      when 0xF6
        self.a = or self.a, d8, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
        return 8
      when 0xF7
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0030_u16
        return 16
      when 0xF8
        self.hl = @sp &+ r8
        self.f_z = false
        self.f_n = false
        self.f_h = (@sp & 0xF) + (r8 & 0xF) > 0xF
        self.f_c = self.hl < @sp
        return 12
      when 0xF9
        @sp = self.hl
        return 8
      when 0xFA
        self.a = @memory[d16]
        return 16
      when 0xFB
        @ime = true
        return 4
        # 0xFC has no functionality
        # 0xFD has no functionality
      when 0xFE
        self.f_z = self.a == d8
        self.f_n = true
        self.f_h = self.a & 0xF < d8 & 0xF
        self.f_c = self.a < d8
        return 8
      when 0xFF
        @sp -= 2
        @memory[@sp] = @pc
        @pc = 0x0038_u16
        return 16
      else raise "UNMATCHED OPCODE #{hex_str opcode}"
      end
    else
      case opcode
      when 0x00
        raise "FAILED TO MATCH CB-0x00"
        return 8
      when 0x01
        raise "FAILED TO MATCH CB-0x01"
        return 8
      when 0x02
        raise "FAILED TO MATCH CB-0x02"
        return 8
      when 0x03
        raise "FAILED TO MATCH CB-0x03"
        return 8
      when 0x04
        raise "FAILED TO MATCH CB-0x04"
        return 8
      when 0x05
        raise "FAILED TO MATCH CB-0x05"
        return 8
      when 0x06
        raise "FAILED TO MATCH CB-0x06"
        return 16
      when 0x07
        raise "FAILED TO MATCH CB-0x07"
        return 8
      when 0x08
        raise "FAILED TO MATCH CB-0x08"
        return 8
      when 0x09
        raise "FAILED TO MATCH CB-0x09"
        return 8
      when 0x0A
        raise "FAILED TO MATCH CB-0x0A"
        return 8
      when 0x0B
        raise "FAILED TO MATCH CB-0x0B"
        return 8
      when 0x0C
        raise "FAILED TO MATCH CB-0x0C"
        return 8
      when 0x0D
        raise "FAILED TO MATCH CB-0x0D"
        return 8
      when 0x0E
        raise "FAILED TO MATCH CB-0x0E"
        return 16
      when 0x0F
        raise "FAILED TO MATCH CB-0x0F"
        return 8
      when 0x10
        carry = self.b & 0x80
        self.b = (self.b << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.b == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x11
        carry = self.c & 0x80
        self.c = (self.c << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.c == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x12
        carry = self.d & 0x80
        self.d = (self.d << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.d == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x13
        carry = self.e & 0x80
        self.e = (self.e << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.e == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x14
        carry = self.h & 0x80
        self.h = (self.h << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.h == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x15
        carry = self.l & 0x80
        self.l = (self.l << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.l == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x16
        carry = @memory[self.hl] & 0x80
        @memory[self.hl] = (@memory[self.hl] << 1) + (self.f_c ? 1 : 0)
        self.f_z = @memory[self.hl] == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 16
      when 0x17
        carry = self.a & 0x80
        self.a = (self.a << 1) + (self.f_c ? 1 : 0)
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x18
        carry = self.b & 0x01
        self.b = (self.b >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.b == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x19
        carry = self.c & 0x01
        self.c = (self.c >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.c == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x1A
        carry = self.d & 0x01
        self.d = (self.d >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.d == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x1B
        carry = self.e & 0x01
        self.e = (self.e >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.e == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x1C
        carry = self.h & 0x01
        self.h = (self.h >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.h == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x1D
        carry = self.l & 0x01
        self.l = (self.l >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.l == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x1E
        carry = @memory[self.hl] & 0x01
        @memory[self.hl] = (@memory[self.hl] >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = @memory[self.hl] == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 16
      when 0x1F
        carry = self.a & 0x01
        self.a = (self.a >> 1) + (self.f_c ? 0x80 : 0x00)
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = carry
        return 8
      when 0x20
        raise "FAILED TO MATCH CB-0x20"
        return 8
      when 0x21
        raise "FAILED TO MATCH CB-0x21"
        return 8
      when 0x22
        raise "FAILED TO MATCH CB-0x22"
        return 8
      when 0x23
        raise "FAILED TO MATCH CB-0x23"
        return 8
      when 0x24
        raise "FAILED TO MATCH CB-0x24"
        return 8
      when 0x25
        raise "FAILED TO MATCH CB-0x25"
        return 8
      when 0x26
        raise "FAILED TO MATCH CB-0x26"
        return 16
      when 0x27
        raise "FAILED TO MATCH CB-0x27"
        return 8
      when 0x28
        raise "FAILED TO MATCH CB-0x28"
        return 8
      when 0x29
        raise "FAILED TO MATCH CB-0x29"
        return 8
      when 0x2A
        raise "FAILED TO MATCH CB-0x2A"
        return 8
      when 0x2B
        raise "FAILED TO MATCH CB-0x2B"
        return 8
      when 0x2C
        raise "FAILED TO MATCH CB-0x2C"
        return 8
      when 0x2D
        raise "FAILED TO MATCH CB-0x2D"
        return 8
      when 0x2E
        raise "FAILED TO MATCH CB-0x2E"
        return 16
      when 0x2F
        raise "FAILED TO MATCH CB-0x2F"
        return 8
      when 0x30
        self.b = (self.b << 4) + (self.b >> 4)
        self.f_z = self.b == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x31
        self.c = (self.c << 4) + (self.c >> 4)
        self.f_z = self.c == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x32
        self.d = (self.d << 4) + (self.d >> 4)
        self.f_z = self.d == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x33
        self.e = (self.e << 4) + (self.e >> 4)
        self.f_z = self.e == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x34
        self.h = (self.h << 4) + (self.h >> 4)
        self.f_z = self.h == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x35
        self.l = (self.l << 4) + (self.l >> 4)
        self.f_z = self.l == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x36
        @memory[self.hl] = (@memory[self.hl] << 4) + (@memory[self.hl] >> 4)
        self.f_z = @memory[self.hl] == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 16
      when 0x37
        self.a = (self.a << 4) + (self.a >> 4)
        self.f_z = self.a == 0
        self.f_n = false
        self.f_h = false
        self.f_c = false
        return 8
      when 0x38
        self.f_z = self.b <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.b & 0x1
        self.b = self.b >> 1
        return 8
      when 0x39
        self.f_z = self.c <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.c & 0x1
        self.c = self.c >> 1
        return 8
      when 0x3A
        self.f_z = self.d <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.d & 0x1
        self.d = self.d >> 1
        return 8
      when 0x3B
        self.f_z = self.e <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.e & 0x1
        self.e = self.e >> 1
        return 8
      when 0x3C
        self.f_z = self.h <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.h & 0x1
        self.h = self.h >> 1
        return 8
      when 0x3D
        self.f_z = self.l <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.l & 0x1
        self.l = self.l >> 1
        return 8
      when 0x3E
        self.f_z = @memory[self.hl] <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = @memory[self.hl] & 0x1
        @memory[self.hl] = @memory[self.hl] >> 1
        return 16
      when 0x3F
        self.f_z = self.a <= 1
        self.f_n = false
        self.f_h = false
        self.f_c = self.a & 0x1
        self.a = self.a >> 1
        return 8
      when 0x40
        bit self.b, 0
        return 8
      when 0x41
        bit self.c, 0
        return 8
      when 0x42
        bit self.d, 0
        return 8
      when 0x43
        bit self.e, 0
        return 8
      when 0x44
        bit self.h, 0
        return 8
      when 0x45
        bit self.l, 0
        return 8
      when 0x46
        bit @memory[self.hl], 0
        return 16
      when 0x47
        bit self.a, 0
        return 8
      when 0x48
        bit self.b, 1
        return 8
      when 0x49
        bit self.c, 1
        return 8
      when 0x4A
        bit self.d, 1
        return 8
      when 0x4B
        bit self.e, 1
        return 8
      when 0x4C
        bit self.h, 1
        return 8
      when 0x4D
        bit self.l, 1
        return 8
      when 0x4E
        bit @memory[self.hl], 1
        return 16
      when 0x4F
        bit self.a, 1
        return 8
      when 0x50
        bit self.b, 2
        return 8
      when 0x51
        bit self.c, 2
        return 8
      when 0x52
        bit self.d, 2
        return 8
      when 0x53
        bit self.e, 2
        return 8
      when 0x54
        bit self.h, 2
        return 8
      when 0x55
        bit self.l, 2
        return 8
      when 0x56
        bit @memory[self.hl], 2
        return 16
      when 0x57
        bit self.a, 2
        return 8
      when 0x58
        bit self.b, 3
        return 8
      when 0x59
        bit self.c, 3
        return 8
      when 0x5A
        bit self.d, 3
        return 8
      when 0x5B
        bit self.e, 3
        return 8
      when 0x5C
        bit self.h, 3
        return 8
      when 0x5D
        bit self.l, 3
        return 8
      when 0x5E
        bit @memory[self.hl], 3
        return 16
      when 0x5F
        bit self.a, 3
        return 8
      when 0x60
        bit self.b, 4
        return 8
      when 0x61
        bit self.c, 4
        return 8
      when 0x62
        bit self.d, 4
        return 8
      when 0x63
        bit self.e, 4
        return 8
      when 0x64
        bit self.h, 4
        return 8
      when 0x65
        bit self.l, 4
        return 8
      when 0x66
        bit @memory[self.hl], 4
        return 16
      when 0x67
        bit self.a, 4
        return 8
      when 0x68
        bit self.b, 5
        return 8
      when 0x69
        bit self.c, 5
        return 8
      when 0x6A
        bit self.d, 5
        return 8
      when 0x6B
        bit self.e, 5
        return 8
      when 0x6C
        bit self.h, 5
        return 8
      when 0x6D
        bit self.l, 5
        return 8
      when 0x6E
        bit @memory[self.hl], 5
        return 16
      when 0x6F
        bit self.a, 5
        return 8
      when 0x70
        bit self.b, 6
        return 8
      when 0x71
        bit self.c, 6
        return 8
      when 0x72
        bit self.d, 6
        return 8
      when 0x73
        bit self.e, 6
        return 8
      when 0x74
        bit self.h, 6
        return 8
      when 0x75
        bit self.l, 6
        return 8
      when 0x76
        bit @memory[self.hl], 6
        return 16
      when 0x77
        bit self.a, 6
        return 8
      when 0x78
        bit self.b, 7
        return 8
      when 0x79
        bit self.c, 7
        return 8
      when 0x7A
        bit self.d, 7
        return 8
      when 0x7B
        bit self.e, 7
        return 8
      when 0x7C
        bit self.h, 7
        return 8
      when 0x7D
        bit self.l, 7
        return 8
      when 0x7E
        bit @memory[self.hl], 7
        return 16
      when 0x7F
        bit self.a, 7
        return 8
      when 0x80
        self.b &= ~(0x1 << 0)
        return 8
      when 0x81
        self.c &= ~(0x1 << 0)
        return 8
      when 0x82
        self.d &= ~(0x1 << 0)
        return 8
      when 0x83
        self.e &= ~(0x1 << 0)
        return 8
      when 0x84
        self.h &= ~(0x1 << 0)
        return 8
      when 0x85
        self.l &= ~(0x1 << 0)
        return 8
      when 0x86
        @memory[self.hl] &= ~(0x1 << 0)
        return 16
      when 0x87
        self.a &= ~(0x1 << 0)
        return 8
      when 0x88
        self.b &= ~(0x1 << 1)
        return 8
      when 0x89
        self.c &= ~(0x1 << 1)
        return 8
      when 0x8A
        self.d &= ~(0x1 << 1)
        return 8
      when 0x8B
        self.e &= ~(0x1 << 1)
        return 8
      when 0x8C
        self.h &= ~(0x1 << 1)
        return 8
      when 0x8D
        self.l &= ~(0x1 << 1)
        return 8
      when 0x8E
        @memory[self.hl] &= ~(0x1 << 1)
        return 16
      when 0x8F
        self.a &= ~(0x1 << 1)
        return 8
      when 0x90
        self.b &= ~(0x1 << 2)
        return 8
      when 0x91
        self.c &= ~(0x1 << 2)
        return 8
      when 0x92
        self.d &= ~(0x1 << 2)
        return 8
      when 0x93
        self.e &= ~(0x1 << 2)
        return 8
      when 0x94
        self.h &= ~(0x1 << 2)
        return 8
      when 0x95
        self.l &= ~(0x1 << 2)
        return 8
      when 0x96
        @memory[self.hl] &= ~(0x1 << 2)
        return 16
      when 0x97
        self.a &= ~(0x1 << 2)
        return 8
      when 0x98
        self.b &= ~(0x1 << 3)
        return 8
      when 0x99
        self.c &= ~(0x1 << 3)
        return 8
      when 0x9A
        self.d &= ~(0x1 << 3)
        return 8
      when 0x9B
        self.e &= ~(0x1 << 3)
        return 8
      when 0x9C
        self.h &= ~(0x1 << 3)
        return 8
      when 0x9D
        self.l &= ~(0x1 << 3)
        return 8
      when 0x9E
        @memory[self.hl] &= ~(0x1 << 3)
        return 16
      when 0x9F
        self.a &= ~(0x1 << 3)
        return 8
      when 0xA0
        self.b &= ~(0x1 << 4)
        return 8
      when 0xA1
        self.c &= ~(0x1 << 4)
        return 8
      when 0xA2
        self.d &= ~(0x1 << 4)
        return 8
      when 0xA3
        self.e &= ~(0x1 << 4)
        return 8
      when 0xA4
        self.h &= ~(0x1 << 4)
        return 8
      when 0xA5
        self.l &= ~(0x1 << 4)
        return 8
      when 0xA6
        @memory[self.hl] &= ~(0x1 << 4)
        return 16
      when 0xA7
        self.a &= ~(0x1 << 4)
        return 8
      when 0xA8
        self.b &= ~(0x1 << 5)
        return 8
      when 0xA9
        self.c &= ~(0x1 << 5)
        return 8
      when 0xAA
        self.d &= ~(0x1 << 5)
        return 8
      when 0xAB
        self.e &= ~(0x1 << 5)
        return 8
      when 0xAC
        self.h &= ~(0x1 << 5)
        return 8
      when 0xAD
        self.l &= ~(0x1 << 5)
        return 8
      when 0xAE
        @memory[self.hl] &= ~(0x1 << 5)
        return 16
      when 0xAF
        self.a &= ~(0x1 << 5)
        return 8
      when 0xB0
        self.b &= ~(0x1 << 6)
        return 8
      when 0xB1
        self.c &= ~(0x1 << 6)
        return 8
      when 0xB2
        self.d &= ~(0x1 << 6)
        return 8
      when 0xB3
        self.e &= ~(0x1 << 6)
        return 8
      when 0xB4
        self.h &= ~(0x1 << 6)
        return 8
      when 0xB5
        self.l &= ~(0x1 << 6)
        return 8
      when 0xB6
        @memory[self.hl] &= ~(0x1 << 6)
        return 16
      when 0xB7
        self.a &= ~(0x1 << 6)
        return 8
      when 0xB8
        self.b &= ~(0x1 << 7)
        return 8
      when 0xB9
        self.c &= ~(0x1 << 7)
        return 8
      when 0xBA
        self.d &= ~(0x1 << 7)
        return 8
      when 0xBB
        self.e &= ~(0x1 << 7)
        return 8
      when 0xBC
        self.h &= ~(0x1 << 7)
        return 8
      when 0xBD
        self.l &= ~(0x1 << 7)
        return 8
      when 0xBE
        @memory[self.hl] &= ~(0x1 << 7)
        return 16
      when 0xBF
        self.a &= ~(0x1 << 7)
        return 8
      when 0xC0
        self.b |= (0x1 << 0)
        return 8
      when 0xC1
        self.c |= (0x1 << 0)
        return 8
      when 0xC2
        self.d |= (0x1 << 0)
        return 8
      when 0xC3
        self.e |= (0x1 << 0)
        return 8
      when 0xC4
        self.h |= (0x1 << 0)
        return 8
      when 0xC5
        self.l |= (0x1 << 0)
        return 8
      when 0xC6
        @memory[self.hl] |= (0x1 << 0)
        return 16
      when 0xC7
        self.a |= (0x1 << 0)
        return 8
      when 0xC8
        self.b |= (0x1 << 1)
        return 8
      when 0xC9
        self.c |= (0x1 << 1)
        return 8
      when 0xCA
        self.d |= (0x1 << 1)
        return 8
      when 0xCB
        self.e |= (0x1 << 1)
        return 8
      when 0xCC
        self.h |= (0x1 << 1)
        return 8
      when 0xCD
        self.l |= (0x1 << 1)
        return 8
      when 0xCE
        @memory[self.hl] |= (0x1 << 1)
        return 16
      when 0xCF
        self.a |= (0x1 << 1)
        return 8
      when 0xD0
        self.b |= (0x1 << 2)
        return 8
      when 0xD1
        self.c |= (0x1 << 2)
        return 8
      when 0xD2
        self.d |= (0x1 << 2)
        return 8
      when 0xD3
        self.e |= (0x1 << 2)
        return 8
      when 0xD4
        self.h |= (0x1 << 2)
        return 8
      when 0xD5
        self.l |= (0x1 << 2)
        return 8
      when 0xD6
        @memory[self.hl] |= (0x1 << 2)
        return 16
      when 0xD7
        self.a |= (0x1 << 2)
        return 8
      when 0xD8
        self.b |= (0x1 << 3)
        return 8
      when 0xD9
        self.c |= (0x1 << 3)
        return 8
      when 0xDA
        self.d |= (0x1 << 3)
        return 8
      when 0xDB
        self.e |= (0x1 << 3)
        return 8
      when 0xDC
        self.h |= (0x1 << 3)
        return 8
      when 0xDD
        self.l |= (0x1 << 3)
        return 8
      when 0xDE
        @memory[self.hl] |= (0x1 << 3)
        return 16
      when 0xDF
        self.a |= (0x1 << 3)
        return 8
      when 0xE0
        self.b |= (0x1 << 4)
        return 8
      when 0xE1
        self.c |= (0x1 << 4)
        return 8
      when 0xE2
        self.d |= (0x1 << 4)
        return 8
      when 0xE3
        self.e |= (0x1 << 4)
        return 8
      when 0xE4
        self.h |= (0x1 << 4)
        return 8
      when 0xE5
        self.l |= (0x1 << 4)
        return 8
      when 0xE6
        @memory[self.hl] |= (0x1 << 4)
        return 16
      when 0xE7
        self.a |= (0x1 << 4)
        return 8
      when 0xE8
        self.b |= (0x1 << 5)
        return 8
      when 0xE9
        self.c |= (0x1 << 5)
        return 8
      when 0xEA
        self.d |= (0x1 << 5)
        return 8
      when 0xEB
        self.e |= (0x1 << 5)
        return 8
      when 0xEC
        self.h |= (0x1 << 5)
        return 8
      when 0xED
        self.l |= (0x1 << 5)
        return 8
      when 0xEE
        @memory[self.hl] |= (0x1 << 5)
        return 16
      when 0xEF
        self.a |= (0x1 << 5)
        return 8
      when 0xF0
        self.b |= (0x1 << 6)
        return 8
      when 0xF1
        self.c |= (0x1 << 6)
        return 8
      when 0xF2
        self.d |= (0x1 << 6)
        return 8
      when 0xF3
        self.e |= (0x1 << 6)
        return 8
      when 0xF4
        self.h |= (0x1 << 6)
        return 8
      when 0xF5
        self.l |= (0x1 << 6)
        return 8
      when 0xF6
        @memory[self.hl] |= (0x1 << 6)
        return 16
      when 0xF7
        self.a |= (0x1 << 6)
        return 8
      when 0xF8
        self.b |= (0x1 << 7)
        return 8
      when 0xF9
        self.c |= (0x1 << 7)
        return 8
      when 0xFA
        self.d |= (0x1 << 7)
        return 8
      when 0xFB
        self.e |= (0x1 << 7)
        return 8
      when 0xFC
        self.h |= (0x1 << 7)
        return 8
      when 0xFD
        self.l |= (0x1 << 7)
        return 8
      when 0xFE
        @memory[self.hl] |= (0x1 << 7)
        return 16
      when 0xFF
        self.a |= (0x1 << 7)
        return 8
      else raise "UNMATCHED CB-OPCODE #{hex_str opcode}"
      end
    end
    raise "MEMES?"
  end
end

OPCODE_LENGTHS = [
  1, 3, 1, 1, 1, 1, 2, 1, 3, 1, 1, 1, 1, 1, 2, 1,
  2, 3, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1,
  2, 3, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1,
  2, 3, 1, 1, 1, 1, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
  1, 1, 3, 3, 3, 1, 2, 1, 1, 1, 3, 1, 3, 3, 2, 1,
  1, 1, 3, 0, 3, 1, 2, 1, 1, 1, 3, 0, 3, 0, 2, 1,
  2, 1, 1, 0, 0, 1, 2, 1, 2, 1, 3, 0, 0, 0, 2, 1,
  2, 1, 1, 1, 0, 1, 2, 1, 2, 1, 3, 1, 0, 0, 2, 1,
]
