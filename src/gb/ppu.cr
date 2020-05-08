class PPU
  #   getter frame : Bytes

  def initialize(@memory : Memory)
    @frame = Bytes.new 160 * 144 { |i| (((i + i/144) % 2) + 1).to_u8 }
  end

  def frame : Bytes
    (0...32).each_with_index do |row|
      (0...32).each_with_index do |col|
        tile_number = @memory[0x9800 + row * 32 + col]
        set_tile tile_number, col + scx, row + scy
      end
    end

    @frame
  end

  def set_tile(tile_number : Int, x : Int, y : Int)
    (0...8).each do |line|
      first_byte = @memory[0x8000 + line * 2]
      second_byte = @memory[0x8000 + line * 2 + 1]
      (0...8).each do |col|
        color = (((first_byte >> (7 - col)) & 0x1) << 1) | ((second_byte >> (7 - col)) & 0x1)
        @frame[line * 160 + col] = color
      end
    end
  end

  # LCD Control Register
  def lcd_control : UInt8
    @memory[0xFF40]
  end

  def lcd_enabled? : Bool
    lcd_control >> 7 == 1
  end

  def window_enabled? : Bool
    (lcd_control >> 5) & 0x1 == 1
  end

  def sprite_height
    (lcd_control >> 2) & 0x1 == 1 ? 16 : 8
  end

  def sprite_enabled? : Bool
    (lcd_control >> 1) & 0x1 == 1
  end

  def bg_display? : Bool
    lcd_control & 0x1 == 1
  end

  # LCD Status Register
  def lcd_status : UInt8
    @memory[0xFF41]
  end

  def vblank : Bool
    (lcd_status >> 4) & 0x1 == 1
  end

  def hblank : Bool
    (lcd_status >> 3) & 0x1 == 1
  end

  def mode_flag : UInt8
    lcd_status & 0x3
  end

  def scy : UInt8
    @memory[0xFF42]
  end

  def scx : UInt8
    @memory[0xFF43]
  end

  def ly : UInt8
    @memory[0xFF44]
  end

  def lyc : UInt8
    @memory[0xFF45]
  end

  def wy : UInt8
    @memory[0xFF4A]
  end

  def wx : UInt8
    @memory[0xFF4B]
  end

  def bgp : UInt8
    @memory[0xFF47]
  end

  def obp0 : UInt8
    @memory[0xFF48]
  end

  def obp1 : UInt8
    @memory[0xFF49]
  end

  # todo CGB color palettes
  # todo CGB vram bank

  def dma : UInt8
    @memory[0xFF46]
  end

  # todo CGB vram dma transfers

end
