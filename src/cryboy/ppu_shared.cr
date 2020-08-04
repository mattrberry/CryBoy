# This file is simply designed to hold shared features of the scanline and FIFO
# renderers while the FIFO renderer is in active development. The purpose of
# this file is solely to reduce common changes to both renderers.

struct Sprite
  def initialize(@y : UInt8, @x : UInt8, @tile_num : UInt8, @attributes : UInt8)
  end

  def to_s(io : IO)
    io << "Sprite(y:#{@y}, x:#{@x}, tile_num:#{@tile_num}, tile_ptr: #{hex_str tile_ptr}, visible:#{visible?}, priority:#{priority}, y_flip:#{y_flip?}, x_flip:#{x_flip?}, dmg_palette_number:#{dmg_palette_numpalette_number}"
  end

  def on_line(line : Int, sprite_height = 8) : Bool
    y <= line + 16 < y + sprite_height
  end

  # behavior is undefined if sprite is not on given line
  def bytes(line : Int, sprite_height = 8) : Tuple(UInt16, UInt16)
    actual_y = -16 + y
    if sprite_height == 8
      tile_ptr = 16_u16 * @tile_num
    else # 8x16 tile
      if (actual_y + 8 <= line) ^ y_flip?
        tile_ptr = 16_u16 * (@tile_num | 0x01)
      else
        tile_ptr = 16_u16 * (@tile_num & 0xFE)
      end
    end
    sprite_row = (line.to_i16 - actual_y) % 8
    if y_flip?
      {tile_ptr + (7 - sprite_row) * 2, tile_ptr + (7 - sprite_row) * 2 + 1}
    else
      {tile_ptr + sprite_row * 2, tile_ptr + sprite_row * 2 + 1}
    end
  end

  def visible? : Bool
    ((1...160).includes? y) && ((1...168).includes? x)
  end

  def y : UInt8
    @y
  end

  def x : UInt8
    @x
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

  def dmg_palette_number : UInt8
    (@attributes >> 4) & 0x1
  end

  def bank_num : UInt8
    (@attributes >> 3) & 0x1
  end

  def cgb_palette_number : UInt8
    @attributes & 0b111
  end
end

struct RGB
  property red, green, blue

  def initialize(@red : UInt8, @green : UInt8, @blue : UInt8)
  end

  def initialize(grey : UInt8)
    @red = @green = @blue = grey
  end

  def convert_from_cgb(should_convert : Bool) : RGB
    if should_convert
      {% unless flag? :graphics_test %}
        # correction algorithm from: https://byuu.net/video/color-emulation
        RGB.new(
          Math.min(240, (26_u32 * @red + 4_u32 * @green + 2_u32 * @blue) >> 2).to_u8,
          Math.min(240, (24_u32 * @green + 8_u32 * @blue) >> 2).to_u8,
          Math.min(240, (6_u32 * @red + 4_u32 * @green + 22_u32 * @blue) >> 2).to_u8
        )
      {% else %}
        # documented in https://github.com/mattcurrie/mealybug-tearoom-tests
        RGB.new(
          @red << 3 | @red >> 2,
          @green << 3 | @green >> 2,
          @blue << 3 | @blue >> 2
        )
      {% end %}
    else
      self
    end
  end
end

abstract class BasePPU
  @ran_bios : Bool # determine if colors should be adjusted for cgb

  @framebuffer = Array(RGB).new Display::WIDTH * Display::HEIGHT, RGB.new(0, 0, 0)

  @palettes = Array(Array(RGB)).new 8 { Array(RGB).new 4, RGB.new(0, 0, 0) }
  @palette_index : UInt8 = 0
  @auto_increment = false

  @obj_palettes = Array(Array(RGB)).new 8 { Array(RGB).new 4, RGB.new(0, 0, 0) }
  @obj_palette_index : UInt8 = 0
  @obj_auto_increment = false

  @vram = Array(Bytes).new 2 { Bytes.new Memory::VRAM.size } # 0x8000..0x9FFF
  @vram_bank : UInt8 = 0                                     # track which bank is active
  @sprite_table = Bytes.new Memory::SPRITE_TABLE.size        # 0xFE00..0xFE9F
  @lcd_control : UInt8 = 0x00_u8                             # 0xFF40
  @lcd_status : UInt8 = 0x80_u8                              # 0xFF41
  @scy : UInt8 = 0x00_u8                                     # 0xFF42
  @scx : UInt8 = 0x00_u8                                     # 0xFF43
  @ly : UInt8 = 0x00_u8                                      # 0xFF44
  @lyc : UInt8 = 0x00_u8                                     # 0xFF45
  @dma : UInt8 = 0x00_u8                                     # 0xFF46
  @bgp : UInt8 = 0x00_u8                                     # 0xFF47
  @obp0 : UInt8 = 0x00_u8                                    # 0xFF48
  @obp1 : UInt8 = 0x00_u8                                    # 0xFF49
  @wy : UInt8 = 0x00_u8                                      # 0xFF4A
  @wx : UInt8 = 0x00_u8                                      # 0xFF4B

  @current_window_line = 0

  @old_stat_flag = false

  def initialize(@display : Display, @interrupts : Interrupts, @cgb_ptr : Pointer(Bool))
    unless @cgb_ptr.value # fill default color palettes
      {% if flag? :pink %}
        @palettes[0] = @obj_palettes[0] = @obj_palettes[1] = [
          RGB.new(0xFF, 0xF6, 0xD3), RGB.new(0xF9, 0xA8, 0x75),
          RGB.new(0xEB, 0x6B, 0x6F), RGB.new(0x7C, 0x3F, 0x58),
        ]
      {% elsif flag? :graphics_test %}
        @palettes[0] = @obj_palettes[0] = @obj_palettes[1] = [
          RGB.new(0xFF, 0xFF, 0xFF), RGB.new(0xAA, 0xAA, 0xAA),
          RGB.new(0x55, 0x55, 0x55), RGB.new(0x00, 0x00, 0x00),
        ]
      {% else %}
        @palettes[0] = @obj_palettes[0] = @obj_palettes[1] = [
          RGB.new(0xE0, 0xF8, 0xCF), RGB.new(0x86, 0xC0, 0x6C),
          RGB.new(0x30, 0x68, 0x50), RGB.new(0x07, 0x17, 0x20),
        ]
      {% end %}
    end
    @ran_bios = @cgb_ptr.value
  end

  # gets ly
  def ly : UInt8
    @ly
  end

  # sets ly AND sets coincidence flag
  def ly=(value : UInt8) : Nil
    @ly = value
    self.coincidence_flag = @ly == @lyc
    @old_stat_flag = false
  end

  # handle stat interrupts
  # stat interrupts are only requested on the rising edge
  def handle_stat_interrupt : Nil
    stat_flag = (coincidence_flag && coincidence_interrupt_enabled) ||
                (mode_flag == 2 && oam_interrupt_enabled) ||
                (mode_flag == 0 && hblank_interrupt_enabled) ||
                (mode_flag == 1 && vblank_interrupt_enabled)
    if !@old_stat_flag && stat_flag
      @interrupts.lcd_stat_interrupt = true
    end
    @old_stat_flag = stat_flag
  end

  # read from ppu memory
  def [](index : Int) : UInt8
    case index
    when Memory::VRAM         then @vram[@vram_bank][index - Memory::VRAM.begin]
    when Memory::SPRITE_TABLE then @sprite_table[index - Memory::SPRITE_TABLE.begin]
    when 0xFF40               then @lcd_control
    when 0xFF41               then @lcd_status
    when 0xFF42               then @scy
    when 0xFF43               then @scx
    when 0xFF44               then self.ly
    when 0xFF45               then @lyc
    when 0xFF46               then @dma
    when 0xFF47               then @bgp
    when 0xFF48               then @obp0
    when 0xFF49               then @obp1
    when 0xFF4A               then @wy
    when 0xFF4B               then @wx
    when 0xFF4F               then @cgb_ptr.value ? 0xFE_u8 | @vram_bank : 0xFF_u8
    when 0xFF68               then @cgb_ptr.value ? 0x40_u8 | (@auto_increment ? 0x80 : 0) | @palette_index : 0xFF_u8
    when 0xFF69
      if @cgb_ptr.value
        palette_number = @palette_index // 8
        color_number = (@palette_index % 8) // 2
        color = @palettes[palette_number][color_number]
        if @palette_index % 2 == 0
          color.red | (color.green << 5)
        else
          (color.green >> 3) | (color.blue << 2)
        end
      else
        0xFF_u8
      end
    when 0xFF6A then @cgb_ptr.value ? 0x40_u8 | (@obj_auto_increment ? 0x80 : 0) | @obj_palette_index : 0xFF_u8
    when 0xFF6B
      if @cgb_ptr.value
        palette_number = @obj_palette_index // 8
        color_number = (@obj_palette_index % 8) // 2
        color = @obj_palettes[palette_number][color_number]
        if @palette_index % 2 == 0
          color.red | (color.green << 5)
        else
          (color.green >> 3) | (color.blue << 2)
        end
      else
        0xFF_u8
      end
    else raise "Reading from invalid ppu register: #{hex_str index.to_u16!}"
    end
  end

  # write to ppu memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when Memory::VRAM         then @vram[@vram_bank][index - Memory::VRAM.begin] = value
    when Memory::SPRITE_TABLE then @sprite_table[index - Memory::SPRITE_TABLE.begin] = value
    when 0xFF40
      if value & 0x80 > 0 && !lcd_enabled?
        self.ly = 0
        self.mode_flag = 2
      end
      @lcd_control = value
    when 0xFF41 then @lcd_status = (@lcd_status & 0b10000111) | (value & 0b01111000)
    when 0xFF42 then @scy = value
    when 0xFF43 then @scx = value
    when 0xFF44 then nil # read only
    when 0xFF45 then @lyc = value
    when 0xFF46 then @dma = value
    when 0xFF47 then @bgp = value
    when 0xFF48 then @obp0 = value
    when 0xFF49 then @obp1 = value
    when 0xFF4A then @wy = value
    when 0xFF4B then @wx = value
    when 0xFF4F then @vram_bank = value & 1 if @cgb_ptr.value
    when 0xFF68
      if @cgb_ptr.value
        @palette_index = value & 0x1F
        @auto_increment = value & 0x80 > 0
      end
    when 0xFF69
      if @cgb_ptr.value
        palette_number = @palette_index // 8
        color_number = (@palette_index % 8) // 2
        color = @palettes[palette_number][color_number]
        if @palette_index % 2 == 0
          color.red = value & 0b00011111
          color.green = ((value & 0b11100000) >> 5) | (color.green & 0b11000)
        else
          color.green = ((value & 0b00000011) << 3) | (color.green & 0b00111)
          color.blue = (value & 0b01111100) >> 2
        end
        @palettes[palette_number][color_number] = color
        @palette_index += 1 if @auto_increment
        @palette_index &= 0x3F
      end
    when 0xFF6A
      if @cgb_ptr.value
        @obj_palette_index = value & 0x1F
        @obj_auto_increment = value & 0x80 > 0
      end
    when 0xFF6B
      if @cgb_ptr.value
        palette_number = @obj_palette_index // 8
        color_number = (@obj_palette_index % 8) // 2
        color = @obj_palettes[palette_number][color_number]
        if @obj_palette_index % 2 == 0
          color.red = value & 0b00011111
          color.green = ((value & 0b11100000) >> 5) | (color.green & 0b11000)
        else
          color.green = ((value & 0b00000011) << 3) | (color.green & 0b00111)
          color.blue = (value & 0b01111100) >> 2
        end
        @obj_palettes[palette_number][color_number] = color
        @obj_palette_index += 1 if @obj_auto_increment
        @obj_palette_index &= 0x3F
      end
    else raise "Writing to invalid ppu register: #{hex_str index.to_u16!}"
    end
  end

  # LCD Control Register

  def lcd_enabled? : Bool
    @lcd_control & (0x1 << 7) != 0
  end

  def window_tile_map : UInt8
    @lcd_control & (0x1 << 6)
  end

  def window_enabled? : Bool
    @lcd_control & (0x1 << 5) != 0
  end

  def bg_window_tile_data : UInt8
    @lcd_control & (0x1 << 4)
  end

  def bg_tile_map : UInt8
    @lcd_control & (0x1 << 3)
  end

  def sprite_height
    @lcd_control & (0x1 << 2) != 0 ? 16 : 8
  end

  def sprite_enabled? : Bool
    @lcd_control & (0x1 << 1) != 0
  end

  def bg_display? : Bool
    @lcd_control & 0x1 != 0
  end

  # LCD Status Register

  def coincidence_interrupt_enabled : Bool
    @lcd_status & (0x1 << 6) != 0
  end

  def oam_interrupt_enabled : Bool
    @lcd_status & (0x1 << 5) != 0
  end

  def vblank_interrupt_enabled : Bool
    @lcd_status & (0x1 << 4) != 0
  end

  def hblank_interrupt_enabled : Bool
    @lcd_status & (0x1 << 3) != 0
  end

  def coincidence_flag : Bool
    @lcd_status & (0x1 << 2) != 0
  end

  def coincidence_flag=(on : Bool) : Nil
    @lcd_status = (@lcd_status & ~(0x1 << 2)) | (on ? (0x1 << 2) : 0)
  end

  def mode_flag : UInt8
    @lcd_status & 0x3
  end

  def mode_flag=(mode : UInt8)
    @lcd_status = (@lcd_status & 0b11111100) | mode
  end

  # palettes

  def palette_to_array(palette : UInt8) : Array(UInt8)
    [palette & 0x3, (palette >> 2) & 0x3, (palette >> 4) & 0x3, (palette >> 6) & 0x3]
  end
end