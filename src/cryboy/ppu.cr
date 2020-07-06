struct Sprite
  def initialize(@y : UInt8, @x : UInt8, @tile_num : UInt8, @attributes : UInt8)
  end

  def to_s(io : IO)
    io << "Sprite(y:#{@y}, x:#{@x}, tile_num:#{@tile_num}, tile_ptr: #{hex_str tile_ptr}, visible:#{visible?}, priority:#{priority}, y_flip:#{y_flip?}, x_flip:#{x_flip?}, palette_number:#{palette_number}"
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

  def palette_number : UInt8
    (@attributes >> 4) & 0x1
  end

  def bank_num : UInt8
    (@attributes >> 3) & 0x1
  end

  def palette_num : UInt8
    @attributes & 0b111
  end
end

struct RGB
  def initialize(@red : UInt8, @green : UInt8, @blue : UInt8)
  end
end

class PPU
  @framebuffer = Array(RGB).new Display::WIDTH * Display::HEIGHT, RGB.new(0, 0, 0)
  @colors = [RGB.new(0xE0, 0xF8, 0xCF), RGB.new(0x86, 0xC0, 0x6C), RGB.new(0x30, 0x68, 0x50), RGB.new(0x07, 0x17, 0x20)]

  @counter : UInt32 = 0_u32

  @vram = Array(Bytes).new 2 { Bytes.new Memory::VRAM.size } # 0x8000..0x9FFF
  @vram_bank : UInt8 = 0                                     # track which bank is active
  @sprite_table = Bytes.new Memory::SPRITE_TABLE.size        # 0xFE00..0xFE9F
  @lcd_control : UInt8 = 0x00_u8                             # 0xFF40
  @lcd_status : UInt8 = 0x00_u8                              # 0xFF41
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
  end

  def initialize(@display : Display, @interrupts : Interrupts)
  end

  # get first 10 sprites on scanline, ordered
  # the order dictates how sprites should render, with the first ones on the bottom
  def get_sprites : Array(Sprite)
    sprites = [] of Sprite
    (0x00..0x9F).step 4 do |sprite_address|
      sprite = Sprite.new @sprite_table[sprite_address], @sprite_table[sprite_address + 1], @sprite_table[sprite_address + 2], @sprite_table[sprite_address + 3]
      if sprite.on_line self.ly, sprite_height
        index = 0
        sprites.each do |sprite_elm|
          break if sprite.x >= sprite_elm.x
          index += 1
        end
        sprites.insert index, sprite
      end
      break if sprites.size >= 10
    end
    sprites
  end

  def scanline
    @current_window_line = 0 if self.ly == 0
    should_increment_window_line = false
    bg_palette = palette_to_array @bgp
    window_map = window_tile_map == 0_u8 ? 0x1800 : 0x1C00       # 0x9800 : 0x9C00
    background_map = bg_tile_map == 0_u8 ? 0x1800 : 0x1C00       # 0x9800 : 0x9C00
    tile_data_table = bg_window_tile_data == 0 ? 0x1000 : 0x0000 # 0x9000 : 0x8000
    tile_row_window = @current_window_line % 8
    tile_row = (self.ly.to_u16 + @scy) % 8
    (0...Display::WIDTH).each do |x|
      if window_enabled? && self.ly >= @wy && x + 7 >= @wx
        should_increment_window_line = true
        tile_num_addr = window_map + ((x + 7 - @wx) // 8) + ((@current_window_line // 8) * 32)
        tile_num = @vram[0][tile_num_addr]
        tile_num = tile_num.to_i8! if bg_window_tile_data == 0
        tile_ptr = tile_data_table + 16 * tile_num
        bank_num = (@vram[1][tile_num_addr] & 0b00001000) >> 3
        byte_1 = @vram[bank_num][tile_ptr + tile_row_window * 2]
        byte_2 = @vram[bank_num][tile_ptr + tile_row_window * 2 + 1]
        lsb = (byte_1 >> (7 - ((x + 7 - @wx) % 8))) & 0x1
        msb = (byte_2 >> (7 - ((x + 7 - @wx) % 8))) & 0x1
        color = (msb << 1) | lsb
        @framebuffer[Display::WIDTH * self.ly + x] = @colors[bg_palette[color]]
      elsif bg_display?
        tile_num_addr = background_map + (((x + @scx) // 8) % 32) + ((((self.ly.to_u16 + @scy) // 8) * 32) % (32 * 32))
        tile_num = @vram[0][tile_num_addr]
        tile_num = tile_num.to_i8! if bg_window_tile_data == 0
        tile_ptr = tile_data_table + 16 * tile_num
        bank_num = (@vram[1][tile_num_addr] & 0b00001000) >> 3
        byte_1 = @vram[bank_num][tile_ptr + tile_row * 2]
        byte_2 = @vram[bank_num][tile_ptr + tile_row * 2 + 1]
        lsb = (byte_1 >> (7 - ((x + @scx) % 8))) & 0x1
        msb = (byte_2 >> (7 - ((x + @scx) % 8))) & 0x1
        color = (msb << 1) | lsb
        @framebuffer[Display::WIDTH * self.ly + x] = @colors[bg_palette[color]]
      end
    end
    @current_window_line += 1 if should_increment_window_line

    if sprite_enabled?
      get_sprites.each do |sprite|
        sprite_palette = palette_to_array(sprite.palette_number == 0 ? @obp0 : @obp1)
        bytes = sprite.bytes self.ly, sprite_height
        (0...8).each do |col|
          x = col + sprite.x - 8
          next unless 0 <= x < Display::WIDTH # only render sprites on screen
          if sprite.x_flip?
            lsb = (@vram[sprite.bank_num][bytes[0]] >> col) & 0x1
            msb = (@vram[sprite.bank_num][bytes[1]] >> col) & 0x1
          else
            lsb = (@vram[sprite.bank_num][bytes[0]] >> (7 - col)) & 0x1
            msb = (@vram[sprite.bank_num][bytes[1]] >> (7 - col)) & 0x1
          end
          color = (msb << 1) | lsb
          if color > 0 # only render opaque colors, 0 is transparent
            @framebuffer[Display::WIDTH * self.ly + x] = @colors[sprite_palette[color]] if sprite.priority == 0 || @framebuffer[Display::WIDTH * self.ly + x] == @colors[bg_palette[0]]
          end
        end
      end
    end
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

  # tick ppu forward by specified number of cycles
  def tick(cycles : Int) : Nil
    @counter += cycles
    if lcd_enabled?
      if self.mode_flag == 2 # oam search
        if @counter >= 80    # end of oam search reached
          @counter -= 80     # reset counter, saving extra cycles
          self.mode_flag = 3 # switch to drawing
        end
      elsif self.mode_flag == 3 # drawing
        if @counter >= 172      # end of drawing reached
          @counter -= 172       # reset counter, saving extra cycles
          self.mode_flag = 0    # switch to hblank
          scanline              # store scanline data
        end
      elsif self.mode_flag == 0 # hblank
        if @counter >= 204      # end of hblank reached
          @counter -= 204       # reset counter, saving extra cycles
          self.ly += 1
          if self.ly == Display::HEIGHT # final row of screen complete
            self.mode_flag = 1          # switch to vblank
            @interrupts.vblank_interrupt = true
            @display.draw @framebuffer # render at vblank
          else
            self.mode_flag = 2 # switch to oam search
          end
        end
      elsif self.mode_flag == 1 # vblank
        if @counter >= 456      # end of line reached
          @counter -= 456       # reset counter, saving extra cycles
          self.ly += 1
          if self.ly == 154    # end of vblank reached
            self.mode_flag = 2 # switch to oam search
            self.ly = 0        # reset ly
          end
        end
      else
        raise "Invalid mode #{self.mode_flag}"
      end
      handle_stat_interrupt
    else                 # lcd is disabled
      @counter = 0       # reset cycle counter
      self.mode_flag = 2 # reset to oam search mode
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
    when 0xFF4F               then 0xFE_u8 | @vram_bank
    when 0xFF51..0xFF55       then 0xFF_u8 # DMA - CGB only
    else                           raise "Reading from invalid ppu register: #{hex_str index.to_u16!}"
    end
  end

  # write to ppu memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when Memory::VRAM         then @vram[@vram_bank][index - Memory::VRAM.begin] = value
    when Memory::SPRITE_TABLE then @sprite_table[index - Memory::SPRITE_TABLE.begin] = value
    when 0xFF40               then @lcd_control = value
    when 0xFF41               then @lcd_status = (@lcd_status & 0b10000111) | (value & 0b01111000)
    when 0xFF42               then @scy = value
    when 0xFF43               then @scx = value
    when 0xFF44               then nil # read only
    when 0xFF45               then @lyc = value
    when 0xFF46               then @dma = value
    when 0xFF47               then @bgp = value
    when 0xFF48               then @obp0 = value
    when 0xFF49               then @obp1 = value
    when 0xFF4A               then @wy = value
    when 0xFF4B               then @wx = value
    when 0xFF4F               then @vram_bank = value & 1
    when 0xFF51..0xFF55       then nil # DMA - CGB only
    else                           raise "Writing to invalid ppu register: #{hex_str index.to_u16!}"
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
