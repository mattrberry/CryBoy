struct Scanline
  property scx, scy, wx, wy, tile_map

  def initialize(@scx : UInt8, @scy : UInt8, @wx : UInt8, @wy : UInt8, @tile_map : UInt8)
  end

  def to_s(io : IO)
    io << "Scanline(scx:#{scx}, scy:#{scy}, wx:#{wx}, wy:#{wy}, tile_map:#{tile_map}"
  end
end

struct Sprite
  def initialize(@y : UInt8, @x : UInt8, @tile_num : UInt8, @attributes : UInt8)
  end

  def to_s(io : IO)
    io << "Sprite(y:#{@y}, x:#{@x}, tile_num:#{@tile_num}, tile_ptr: #{hex_str tile_ptr}, visible:#{visible?}, priority:#{priority}, y_flip:#{y_flip?}, x_flip:#{x_flip?}, palette_number:#{palette_number}"
  end

  def visible? : Bool
    ((1...160).includes? y) && ((1...168).includes? x)
  end

  def y : UInt8
    @y #- 16
  end

  def x : UInt8
    @x #- 8
  end

  def tile_ptr : UInt16
    0x8000_u16 + 16 * @tile_num
  end

  def priority : UInt8
    (@attributes >> 7) & 0x1
  end

  def y_flip? : Bool
    (@attributes >> 6) & 0x1 == 1
  end

  def x_flip? : Bool
    (@attributes >> 5) & 0x1 == 1
  end

  def palette_number : UInt8
    (@attributes >> 4) & 0x1
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

  def draw_background(x : Int, y : Int, scanline : Scanline)
    background_map = bg_tile_map == 0_u8 ? 0x9800 : 0x9C00
    tile_num = @memory[background_map + (((x + scanline.scx) // 8) % 32) + ((((y + scanline.scy) // 8) * 32) % (32 * 32))]
    tile_data_table = scanline.tile_map == 0 ? 0x9000 : 0x8000
    tile_ptr = tile_data_table + 16 * tile_num
    tile_row = (y + scanline.scy) % 8
    byte_1 = @memory[tile_ptr + tile_row * 2]
    byte_2 = @memory[tile_ptr + tile_row * 2 + 1]
    lsb = (byte_1 >> (7 - ((x + scanline.scx) % 8))) & 0x1
    msb = (byte_2 >> (7 - ((x + scanline.scx) % 8))) & 0x1
    color = (msb << 1) | lsb
    @framebuffer[y][x] = color
  end

  def draw_sprites
    # puts "drawing sprites"
    (0xFF00..0xFF9F).step 4 do |sprite_address|
      sprite = Sprite.new @memory[sprite_address], @memory[sprite_address + 1], @memory[sprite_address + 2], @memory[sprite_address + 3]
      puts sprite if sprite.visible?
      if sprite.visible?
        (0...8).each do |row|
          break if sprite.y + row < 16
          byte_1 = @memory[sprite.tile_ptr + row * 2]
          byte_2 = @memory[sprite.tile_ptr + row * 2 + 1]
          (0...8).each do |col|
            break if sprite.x + col < 8
            lsb = (byte_1 >> (7 - col)) & 0x1
            msb = (byte_2 >> (7 - col)) & 0x1
            color = (msb << 1) | lsb
            @framebuffer[sprite.y - 16][sprite.x - 8] = color
          end
        end
      end
    end
  end

  def framebuffer : Array(Array(UInt8))
    @scanlines.each_with_index do |scanline, y|
      (0...160).each do |x|
        if window_enabled? && scanline.wy <= y && scanline.wx <= x
          puts "window enabled"
        elsif bg_display?
          draw_background x, y, scanline
        end
      end
    end
    # draw_sprites if sprite_enabled?
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
