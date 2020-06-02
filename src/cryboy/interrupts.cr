class Interrupts
  property vblank_interrupt = false
  property lcd_stat_interrupt = false
  property timer_interrupt = false
  property serial_interrupt = false
  property joypad_interrupt = false

  property vblank_enabled = false
  property lcd_stat_enabled = false
  property timer_enabled = false
  property serial_enabled = false
  property joypad_enabled = false

  # read from interrupts memory
  def [](index : Int) : UInt8
    case index
    when 0xFF0F
      0xE0_u8 |
        (@joypad_interrupt ? (0x1 << 4) : 0) |
        (@serial_interrupt ? (0x1 << 3) : 0) |
        (@timer_interrupt ? (0x1 << 2) : 0) |
        (@lcd_stat_interrupt ? (0x1 << 1) : 0) |
        (@vblank_interrupt ? (0x1 << 0) : 0)
    when 0xFFFF
      0xE0_u8 |
        (@joypad_enabled ? (0x1 << 4) : 0) |
        (@serial_enabled ? (0x1 << 3) : 0) |
        (@timer_enabled ? (0x1 << 2) : 0) |
        (@lcd_stat_enabled ? (0x1 << 1) : 0) |
        (@vblank_enabled ? (0x1 << 0) : 0)
    else raise "Reading from invalid interrupts register: #{hex_str index.to_u16!}"
    end
  end

  # write to interrupts memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0xFF0F
      @vblank_interrupt = value & (0x1 << 0) > 0
      @lcd_stat_interrupt = value & (0x1 << 1) > 0
      @timer_interrupt = value & (0x1 << 2) > 0
      @serial_interrupt = value & (0x1 << 3) > 0
      @joypad_interrupt = value & (0x1 << 4) > 0
    when 0xFFFF
      @vblank_enabled = value & (0x1 << 0) > 0
      @lcd_stat_enabled = value & (0x1 << 1) > 0
      @timer_enabled = value & (0x1 << 2) > 0
      @serial_enabled = value & (0x1 << 3) > 0
      @joypad_enabled = value & (0x1 << 4) > 0
    else raise "Writing to invalid interrupts register: #{hex_str index.to_u16!}"
    end
  end
end
