struct Scanline
  property scx, scy, wx, wy, tile_map

  def initialize(@scx : UInt8, @scy : UInt8, @wx : UInt8, @wy : UInt8, @tile_map : UInt8)
  end

  def to_s(io : IO)
    io << "Scanline(scx:#{scx}, scy:#{scy}, wx:#{wx}, wy:#{wy}, tile_map:#{tile_map}"
  end
end

class PPU
  property scanlines

  def initialize(@memory : Memory)
    @scanlines = Array(Scanline).new 144, Scanline.new(0, 0, 0, 0, 0)
    @framebuffer = Array(Array(UInt8)).new 144 { Array(UInt8).new 160, 0_u8 }
  end

  def scanline(y : Int)
    @scanlines[y] = Scanline.new scx, scy, wx, wy, bg_window_tile_map
  end

  def framebuffer : Array(Array(UInt8))
    background_map = bg_tile_map == 0_u8 ? 0x9800 : 0x9C00
    @scanlines.each_with_index do |scanline, y|
      (0...160).each do |x|
        if window_enabled? && scanline.wy <= y && scanline.wx <= x
          puts "window enabled"
        elsif bg_display?
          tile_num = @memory[background_map + (((x + scanline.scx) // 8) % 32) + ((((y + scanline.scy) * 32) // 8) % 1024)]
          tile_num = tile_num.to_i8! if scanline.tile_map == 0
          tile_data_table = scanline.tile_map == 0 ? 0x9000 : 0x8000
          tile_ptr = tile_data_table + 16 * tile_num
          tile_row_1 = @memory[tile_ptr + ((y + scanline.scy) % 8)]
          tile_row_2 = @memory[tile_ptr + ((y + scanline.scy) % 8) + 1]
          @framebuffer[y][x] = (((tile_row_1 >> (7 - (x % 8))) & 0x1) << 1) | ((tile_row_2 >> (7 - (x % 8))) & 0x1)
          # @framebuffer[y][x] = ((x + y) % 4).to_u8
        end
      end
    end
    @framebuffer
  end

  # LCD Control Register
  def lcd_control : UInt8
    @memory[0xFF40]
  end

  def lcd_enabled? : Bool
    lcd_control >> 7 == 1
  end

  def window_tile_map : UInt8
    (lcd_control >> 6) & 0x1
  end

  def window_enabled? : Bool
    (lcd_control >> 5) & 0x1 == 1
  end

  def bg_window_tile_map : UInt8
    (lcd_control >> 4) & 0x1
  end

  def bg_tile_map : UInt8
    (lcd_control >> 3) & 0x1
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
