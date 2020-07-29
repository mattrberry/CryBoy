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

  def convert_from_cgb : RGB
    # correction algorithm from: https://byuu.net/video/color-emulation
    RGB.new(
      Math.min(240, (26_u32 * @red + 4_u32 * @green + 2_u32 * @blue) >> 2).to_u8,
      Math.min(240, (24_u32 * @green + 8_u32 * @blue) >> 2).to_u8,
      Math.min(240, (6_u32 * @red + 4_u32 * @green + 22_u32 * @blue) >> 2).to_u8
    )
  end
end

struct Pixel
  property color : UInt8               # 0-3
  property palette : UInt8             # 0-7
  property sprite_priority : UInt8     # OAM index for sprite
  property background_priority : UInt8 # OBJ-to_BG Priority bit

  def initialize(@color : UInt8, @palette : UInt8, @sprite_priority : UInt8, @background_priority : UInt8)
  end
end

class PPU
  @framebuffer = Array(RGB).new Display::WIDTH * Display::HEIGHT, RGB.new(0, 0, 0)

  @fifo = Deque(Pixel).new 8

  @cycle_counter : UInt16 = 0x0000 # count number of cycles into current line

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

  def initialize(@display : Display, @interrupts : Interrupts, @cgb_ptr : Pointer(Bool))
    @palettes[0] = @obj_palettes[0] = @obj_palettes[1] = [
      RGB.new(0x1C, 0x1F, 0x1A), RGB.new(0x11, 0x18, 0x0E),
      RGB.new(0x06, 0x0D, 0x0A), RGB.new(0x01, 0x03, 0x04),
    ] if !@cgb_ptr.value
  end

  @old_stat_flag = false

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

  @fetch_counter = 0
  @fetcher_x = 0
  @lx : Int32? = nil

  @tile_num : UInt8 = 0x00
  @tile_data_low : UInt8 = 0x00
  @tile_data_high : UInt8 = 0x00

  # tick ppu forward by specified number of cycles
  def tick(cycles : Int) : Nil
    if lcd_enabled?
      cycles.times do
        case self.mode_flag
        when 2 # OAM search
          if @cycle_counter == 80
            self.mode_flag = 3
            @fifo.clear
            @fetcher_x = 0
            @lx = nil
            @fetch_counter = 0
          end
        when 3 # drawing
          case @fetch_counter
          when 0, 1 # fetching tile number
            if @fetch_counter == 0
              background_map = bg_tile_map == 0 ? 0x1800 : 0x1C00 # 0x9800 : 0x9C00
              tile_num_offset = ((@fetcher_x + (@scx // 8)) % 32) + ((((@ly.to_u16 + @scy) // 8) * 32) % (32 * 32))
              @tile_num = @vram[0][background_map + tile_num_offset]
            end
          when 2, 3 # fetching low tile data
            if @fetch_counter == 2
              if bg_window_tile_data > 0
                tile_num = @tile_num
                tile_data_table = 0x0000 # 0x8000
              else
                tile_num = @tile_num.to_i8!
                tile_data_table = 0x1000 # 0x9000
              end
              # tile_num = bg_window_tile_data > 0 ? @tile_num : @tile_num.to_i8!
              tile_ptr = tile_data_table + 16 * tile_num
              @tile_data_low = @vram[0][tile_ptr + ((@ly.to_u16 + @scy) % 8) * 2]
            end
          when 4, 5 # fetching high tile data
            if @fetch_counter == 4
              if bg_window_tile_data > 0
                tile_num = @tile_num
                tile_data_table = 0x0000 # 0x8000
              else
                tile_num = @tile_num.to_i8!
                tile_data_table = 0x1000 # 0x9000
              end
              # tile_num = bg_window_tile_data > 0 ? @tile_num : @tile_num.to_i8!
              tile_ptr = tile_data_table + 16 * tile_num
              @tile_data_high = @vram[0][tile_ptr + ((@ly.to_u16 + @scy) % 8) * 2 + 1]
            end
            if @cycle_counter == 86
              @fetch_counter = -1 # drop first tile
            end
          else # attempt pushing 8 pixels into fifo
            if @fifo.size == 0
              @fetcher_x += 1
              8.times do |col|
                lsb = (@tile_data_low >> (7 - col)) & 0x1
                msb = (@tile_data_high >> (7 - col)) & 0x1
                color = (msb << 1) | lsb
                @fifo.push Pixel.new(color, 0, 0, 0)
              end
              @fetch_counter = -1 # reset fetcher phase
            end
          end
          if @fifo.size > 0
            palette = palette_to_array @bgp
            pixel = @fifo.shift
            @lx ||= -(7 & @scx)
            if @lx.not_nil! >= 0
              @framebuffer[Display::WIDTH * @ly + @lx.not_nil!] = @palettes[0][palette[pixel.color]].convert_from_cgb
            end
            @lx = @lx.not_nil! + 1
            if @lx == Display::WIDTH
              self.mode_flag = 0
            end
          end
          @fetch_counter += 1
        when 0 # hblank
          if @cycle_counter == 456
            @cycle_counter = 0
            self.ly += 1
            if self.ly == Display::HEIGHT # final row of screen complete
              self.mode_flag = 1          # switch to vblank
              @interrupts.vblank_interrupt = true
              @display.draw @framebuffer # render at vblank
              @framebuffer_pos = 0
            else
              self.mode_flag = 2 # switch to oam search
            end
          end
        when 1 # vblank
          if @cycle_counter == 456
            @cycle_counter = 0
            self.ly += 1 if self.ly != 0
            if self.ly == 0      # end of vblank reached (ly has already shortcut to 0)
              self.mode_flag = 2 # switch to oam search
            end
          end
          self.ly = 0 if self.ly == 153 && @cycle_counter > 4 # shortcut ly to from 153 to 0 after 4 cycles
        end
        @cycle_counter += 1
        handle_stat_interrupt
      end
    else                 # lcd is disabled
      @cycle_counter = 0 # reset cycle counter
      self.mode_flag = 0 # reset to mode 0
      self.ly = 0        # reset ly
    end
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
