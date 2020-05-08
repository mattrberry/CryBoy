class CPU
  macro define_register(upper, lower)
    property {{upper.id}} : UInt8 = 0_u8
    property {{lower.id}} : UInt8 = 0_u8

    def {{upper.id}}{{lower.id}} : UInt16
      (@{{upper}}.to_u16 << 8 | @{{lower}}.to_u16).not_nil!
    end

    def {{upper.id}}{{lower.id}}=(value : UInt16)
      @{{upper.id}} = (value >> 8).to_u8
      @{{lower.id}} = (value & 0xFF).to_u8
    end

    def {{upper.id}}{{lower.id}}=(value : UInt8)
      @{{upper.id}} = 0_u8
      @{{lower.id}} = value
    end
  end

  define_register a, f
  define_register b, c
  define_register d, e
  define_register h, l

  @ime = true

  def initialize(@memory : Memory, boot = false)
    @pc = 0x0000_u16
    @sp = 0xFFFE_u16
    skip_boot if !boot
  end

  def skip_boot
    @pc = 0x0100_u16
    self.af = 0x01B0_u16
    self.bc = 0x0013_u16
    self.de = 0x00D8_u16
    self.hl = 0x014D_u16
    @sp = 0xFFFE_u16
    # set IO reigster state
    @memory[0xFF10] = 0x80_u8
    @memory[0xFF11] = 0xBF_u8
    @memory[0xFF12] = 0xF3_u8
    @memory[0xFF14] = 0xBF_u8
    @memory[0xFF16] = 0x3F_u8
    @memory[0xFF19] = 0xBF_u8
    @memory[0xFF1A] = 0x7F_u8
    @memory[0xFF1B] = 0xFF_u8
    @memory[0xFF1C] = 0x9F_u8
    @memory[0xFF1E] = 0xBF_u8
    @memory[0xFF20] = 0xFF_u8
    @memory[0xFF23] = 0xBF_u8
    @memory[0xFF24] = 0x77_u8
    @memory[0xFF25] = 0xF3_u8
    @memory[0xFF26] = 0xF1_u8
    @memory[0xFF40] = 0x91_u8
    @memory[0xFF41] = 0x05_u8
    @memory[0xFF47] = 0xFC_u8
    @memory[0xFF48] = 0xFF_u8
    @memory[0xFF49] = 0xFF_u8
    # unmap the boot rom
    @memory[0xFF50] = 0x01_u8
  end

  def f_z=(on : Int | Bool)
    if on == false || on == 0
      @f &= 0b0111_0000
    else
      @f |= 0b1000_0000
    end
  end

  def f_z : Bool
    (@f >> 7) & 0xF != 0
  end

  def f_nz : Bool
    !f_z
  end

  def f_n=(on : Int | Bool)
    if on == false || on == 0
      @f &= 0b1011_0000
    else
      @f |= 0b0100_0000
    end
  end

  def f_n : Bool
    (@f >> 6) & 0xF != 0
  end

  def f_h=(on : Int | Bool)
    if on == false || on == 0
      @f &= 0b1101_0000
    else
      @f |= 0b0010_0000
    end
  end

  def f_h : Bool
    (@f >> 5) & 0xF != 0
  end

  def f_c=(on : Int | Bool)
    if on == false || on == 0
      @f &= 0b1110_0000
    else
      @f |= 0b0001_0000
    end
  end

  def f_c : Bool
    (@f >> 4) & 0xF != 0
  end

  def pop : UInt16
    @memory.read_word (@sp += 2) - 2
  end

  def push(value : UInt16) : Nil
    @memory[@sp -= 2] = value
  end

  enum FlagOp
    ZERO
    ONE
    DEFAULT
    UNCHANGED
  end

  def set_flags(res : UInt8, op1 : UInt8, op2 : UInt8, z : FlagOp, n : FlagOp, h : FlagOp, c : FlagOp, add_sub = false)
    # puts "set_flags >> res:#{res}, op1:#{op1}, op2:#{op2}, z:#{z}, n:#{n}, h:#{h}, c:#{c}, add_sub:#{add_sub}"

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

  def add(operand_1 : UInt16, operand_2 : UInt16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt16
    res = operand_1 &+ operand_2

    if z == FlagOp::ZERO
      @f &= 0b0111_0000
    elsif z == FlagOp::ONE || (z == FlagOp::DEFAULT && res == 0)
      @f |= 0b1000_0000
    end

    if n == FlagOp::ZERO
      @f &= 0b1011_0000
    elsif n == FlagOp::ONE # || todo
      @f |= 0b0100_0000
    end

    if h == FlagOp::ZERO
      @f &= 0b1101_0000
    elsif h == FlagOp::ONE # || todo
      @f |= 0b0010_0000
    end

    if c == FlagOp::ZERO
      @f &= 0b1110_0000
    elsif c == FlagOp::ONE || (c == FlagOp::DEFAULT && res < operand_1)
      @f |= 0b0001_0000
    end

    res
  end

  def sub(operand_1 : UInt16, operand_2 : UInt16, z = FlagOp::UNCHANGED, n = FlagOp::UNCHANGED, h = FlagOp::UNCHANGED, c = FlagOp::UNCHANGED) : UInt16
    res = operand_1 &- operand_2

    if z == FlagOp::ZERO
      @f &= 0b0111_0000
    elsif z == FlagOp::ONE || (z == FlagOp::DEFAULT && res == 0)
      @f |= 0b1000_0000
    end

    if n == FlagOp::ZERO
      @f &= 0b1011_0000
    elsif n == FlagOp::ONE # || todo
      @f |= 0b0100_0000
    end

    if h == FlagOp::ZERO
      @f &= 0b1101_0000
    elsif h == FlagOp::ONE # || todo
      @f |= 0b0010_0000
    end

    if c == FlagOp::ZERO
      @f &= 0b1110_0000
    elsif c == FlagOp::ONE || (c == FlagOp::DEFAULT && res > operand_1)
      @f |= 0b0001_0000
    end

    res
  end

  def tick : Nil
    opcode = read_opcode
    process_opcode opcode
  end

  def read_opcode : UInt8
    opcode = @memory[@pc]
    opcode
  end

  def process_opcode(opcode : UInt8) : Nil
    length = OPCODE_LENGTHS[opcode]
    # puts "opcode: 0x#{opcode.to_s(16).rjust(2, '0').upcase}, length: #{length}, pc: #{@pc}"
    puts "op:0x#{opcode.to_s(16).rjust(2, '0').upcase}, pc:#{@pc + 1}, sp:#{@sp}, a:#{@a}, b:#{@b}, c:#{@c}, d:#{@d}, e:#{@e}, f:#{(@f >> 4).to_s(2).rjust(4, '0')}, h:#{@h}, l:#{@l}"
    d8 : UInt8 = 0_u8
    r8 : Int8 = 0_u8
    d16 : UInt16 = 0_u16
    if length == 2
      d8 = @memory[@pc + 1]
      r8 = d8.to_i8!
    elsif length == 3
      d16_1 = @memory[@pc + 1]
      d16_2 = @memory[@pc + 2]
      d16 = @memory.read_word @pc + 1
    end
    @pc += length

    case opcode
    when 0x00 then nil
    when 0x01 then self.bc = d16
    when 0x02 then @memory[self.bc] = @a
    when 0x03 then self.bc = self.bc &+ 1
    when 0x04 then @b = add @b, 1, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x05 then @b = sub @b, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x06 then @b = d8
      # when 0x07
    when 0x08 then @memory[d16] = @sp
    when 0x09 then self.hl = add self.hl, self.bc, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x0A then @a = @memory[self.bc]
    when 0x0B then self.bc = sub self.bc, 1
    when 0x0C then @c = add @c, 0, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x0D then @c = sub @c, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x0E then @c = d8
      # when 0x0F
      # when 0x10
    when 0x11 then self.de = d16
    when 0x12 then @memory[self.de] = @a
      # when 0x13
    when 0x14 then @d = add @d, 1, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x15 then @d = sub @d, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x16 then @d = d8
      # when 0x17
    when 0x18 then @pc += r8
    when 0x19 then self.hl = add self.hl, self.de, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x1A then @a = @memory[self.de]
    when 0x1B then self.de = sub self.de, 1
    when 0x1C then @e = add @e, 0, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x1D then @e = sub @e, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x1E then @e = d8
      # when 0x1F
    when 0x20 then @pc &+= r8 if f_nz
    when 0x21 then self.hl = d16
    when 0x22 then @memory[self.hl] = @a; self.hl = self.hl &+ 1
    # when 0x23
    when 0x24 then @h = add @h, 1, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x25 then @h = sub @h, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x26 then @h = d8
      # when 0x27
      # when 0x28
    when 0x29 then self.hl = add self.hl, self.hl, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x2A then @a = @memory[self.hl]; self.hl = self.hl &+ 1
    when 0x2B then self.hl = sub self.hl, 1
    when 0x2C then @l = add @l, 0, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x2D then @l = sub @l, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x2E then @l = d8
      # when 0x2F
      # when 0x30
    when 0x31 then @sp = d16
    when 0x32 then @memory[self.hl] = @a; self.hl = self.hl &- 1
    # when 0x33
    when 0x34 then @memory[self.hl] = add @memory[self.hl], 1, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x35 then @memory[self.hl] = sub @memory[self.hl], 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x36 then @memory[self.hl] = d8
    when 0x37 then @f &= 0b1001_0000; @f |= 0b0001_0000
    # when 0x38
    when 0x39 then self.hl = add self.hl, @sp, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x3A then @a = @memory[self.hl]; self.hl = self.hl &- 1
    when 0x3B then @sp = sub @sp, 1
    when 0x3C then @a = add @a, 1, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT
    when 0x3D then @a = sub @a, 1, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT
    when 0x3E then @a = d8
      # when 0x3F
    when 0x40 then nil
    when 0x41 then @b = @c
    when 0x42 then @b = @d
    when 0x43 then @b = @e
    when 0x44 then @b = @h
    when 0x45 then @b = @l
    when 0x46 then @b = @memory[self.hl]
    when 0x47 then @b = @a
    when 0x48 then @c = @b
    when 0x49 then nil
    when 0x4A then @c = @d
    when 0x4B then @c = @e
    when 0x4C then @c = @h
    when 0x4D then @c = @l
    when 0x4E then @c = @memory[self.hl]
    when 0x4F then @c = @a
    when 0x50 then @d = @b
    when 0x51 then @d = @c
    when 0x52 then nil
    when 0x53 then @d = @e
    when 0x54 then @d = @h
    when 0x55 then @d = @l
    when 0x56 then @d = @memory[self.hl]
    when 0x57 then @d = @a
    when 0x58 then @e = @b
    when 0x59 then @e = @c
    when 0x5A then @e = @d
    when 0x5B then nil
    when 0x5C then @e = @h
    when 0x5D then @e = @l
    when 0x5E then @e = @memory[self.hl]
    when 0x5F then @e = @a
    when 0x60 then @h = @b
    when 0x61 then @h = @c
    when 0x62 then @h = @d
    when 0x63 then @h = @e
    when 0x64 then nil
    when 0x65 then @h = @l
    when 0x66 then @h = @memory[self.hl]
    when 0x67 then @h = @a
    when 0x68 then @l = @b
    when 0x69 then @l = @c
    when 0x6A then @l = @d
    when 0x6B then @l = @e
    when 0x6C then @l = @h
    when 0x6D then nil
    when 0x6E then @l = @memory[self.hl]
    when 0x6F then @l = @a
    when 0x70 then self.hl = @b.to_u16
    when 0x71 then self.hl = @c.to_u16
    when 0x72 then self.hl = @d.to_u16
    when 0x73 then self.hl = @e.to_u16
    when 0x74 then self.hl = @h.to_u16
    when 0x75 then self.hl = @l.to_u16
    when 0x76 then nil # todo halt
    when 0x77 then self.hl = @a.to_u16
    when 0x78 then @a = @b
    when 0x79 then @a = @c
    when 0x7A then @a = @d
    when 0x7B then @a = @e
    when 0x7C then @a = @h
    when 0x7D then @a = @l
    when 0x7E then @a = @memory[self.hl]
    when 0x7F then nil
    when 0x80 then @a = add @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x81 then @a = add @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x82 then @a = add @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x83 then @a = add @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x84 then @a = add @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x85 then @a = add @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x86 then @a = add @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x87 then @a = add @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x88 then @a = adc @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x89 then @a = adc @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x8A then @a = adc @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x8B then @a = adc @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x8C then @a = adc @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x8D then @a = adc @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x8E then @a = adc @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x8F then @a = adc @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x90 then @a = sub @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x91 then @a = sub @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x92 then @a = sub @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x93 then @a = sub @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x94 then @a = sub @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x95 then @a = sub @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x96 then @a = sub @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x97 then @a = sub @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x98 then @a = sbc @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x99 then @a = sbc @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x9A then @a = sbc @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x9B then @a = sbc @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x9C then @a = sbc @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x9D then @a = sbc @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x9E then @a = sbc @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0x9F then @a = sbc @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
    when 0xA0 then @a = and @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA1 then @a = and @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA2 then @a = and @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA3 then @a = and @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA4 then @a = and @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA5 then @a = and @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA6 then @a = and @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA7 then @a = and @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ONE, c = FlagOp::ZERO
    when 0xA8 then @a = xor @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xA9 then @a = xor @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xAA then @a = xor @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xAB then @a = xor @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xAC then @a = xor @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xAD then @a = xor @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xAE then @a = xor @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xAF then @a = xor @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB0 then @a = or @a, @b, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB1 then @a = or @a, @c, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB2 then @a = or @a, @d, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB3 then @a = or @a, @e, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB4 then @a = or @a, @h, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB5 then @a = or @a, @l, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB6 then @a = or @a, @memory[self.hl], z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
    when 0xB7 then @a = or @a, @a, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::ZERO, c = FlagOp::ZERO
      # when 0xB8
      # when 0xB9
      # when 0xBA
      # when 0xBB
      # when 0xBC
      # when 0xBD
      # when 0xBE
      # when 0xBF
      # when 0xC0
    when 0xC1 then self.bc = pop
      # when 0xC2
    when 0xC3 then @pc = d16
      # when 0xC4
    when 0xC5 then push self.bc
      # when 0xC6
      # when 0xC7
      # when 0xC8
    when 0xC9 then @pc = @memory.read_word @sp; @sp += 2
      # when 0xCA
      # when 0xCB
      # when 0xCC
    when 0xCD then @sp -= 2; @memory[@sp] = @pc; @pc = d16
    when 0xCE then @a = adc @a, d8, z = FlagOp::DEFAULT, n = FlagOp::ZERO, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
      # when 0xCF
      # when 0xD0
    when 0xD1 then self.de = pop
      # when 0xD2
      # when 0xD3
      # when 0xD4
    when 0xD5 then push self.de
      # when 0xD6
      # when 0xD7
      # when 0xD8
      # when 0xD9
      # when 0xDA
      # when 0xDB
      # when 0xDC
      # when 0xDD
      # when 0xDE
      # when 0xDF
    when 0xE0 then @memory[0xFF00 + d8] = @a
    when 0xE1 then self.hl = pop
    when 0xE2 then @memory[0xFF00 + @c] = @a
      # when 0xE3
      # when 0xE4
    when 0xE5 then push self.hl
      # when 0xE6
      # when 0xE7
      # when 0xE8
    when 0xE9 then @pc = self.hl # todo shouldn't this be a memory address
    when 0xEA then @memory[d16] = @a
      # when 0xEB
      # when 0xEC
      # when 0xED
      # when 0xEE
      # when 0xEF
    when 0xF0 then @a = @memory[0xFF00 + d8]
    when 0xF1 then self.af = pop
    when 0xF2 then @a = @memory[0xFF00 + @c]
    when 0xF3 then @ime = false
      # when 0xF4
    when 0xF5 then push self.af
      # when 0xF6
      # when 0xF7
    when 0xF8 then self.hl = @sp + r8.to_u16
    when 0xF9 then @sp = hl
      # when 0xFA
    when 0xFB then @ime = true
      # when 0xFC
      # when 0xFD
    when 0xFE then sub @a, d8, z = FlagOp::DEFAULT, n = FlagOp::ONE, h = FlagOp::DEFAULT, c = FlagOp::DEFAULT
      # when 0xFF
    else raise "MATCH OPCODE #{opcode.to_s(16).rjust(2, '0').upcase}"
    end
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
