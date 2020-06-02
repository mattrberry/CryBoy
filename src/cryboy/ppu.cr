struct Sprite
  def initialize(@y : UInt8, @x : UInt8, @tile_num : UInt8, @attributes : UInt8)
  end

  def to_s(io : IO)
    io << "Sprite(y:#{@y}, x:#{@x}, tile_num:#{@tile_num}, tile_ptr: #{hex_str tile_ptr}, visible:#{visible?}, priority:#{priority}, y_flip:#{y_flip?}, x_flip:#{x_flip?}, palette_number:#{palette_number}"
  end

  def on_line(line : Int, sprite_height = 8) : Tuple(UInt16, UInt16)?
    actual_y = -16 + y
    if actual_y <= line < (actual_y + sprite_height)
      if y_flip?
        {tile_ptr + (actual_y + sprite_height - line - 1) * 2, tile_ptr + (actual_y + sprite_height - line - 1) * 2 + 1}
      else
        {tile_ptr + (line - actual_y) * 2, tile_ptr + (line - actual_y) * 2 + 1}
      end
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

  def tile_ptr : UInt16
    16_u16 * @tile_num
    # 0x8000_u16 + 16 * @tile_num
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
  property framebuffer = Array(Array(UInt8)).new 144 { Array(UInt8).new 160, 0_u8 }

  @counter : UInt32 = 0_u32

  @vram = Bytes.new Memory::VRAM.size                 # 0x8000..0x9FFF
  @sprite_table = Bytes.new Memory::SPRITE_TABLE.size # 0xFE00..0xFE9F
  @lcd_control : UInt8 = 0x00_u8                      # 0xFF40
  @lcd_status : UInt8 = 0x00_u8                       # 0xFF41
  @scy : UInt8 = 0x00_u8                              # 0xFF42
  @scx : UInt8 = 0x00_u8                              # 0xFF43
  @ly : UInt8 = 0x00_u8                               # 0xFF44
  @lyc : UInt8 = 0x00_u8                              # 0xFF45
  @dma : UInt8 = 0x00_u8                              # 0xFF46
  @bgp : UInt8 = 0x00_u8                              # 0xFF47
  @obp0 : UInt8 = 0x00_u8                             # 0xFF48
  @obp1 : UInt8 = 0x00_u8                             # 0xFF49
  @wy : UInt8 = 0x00_u8                               # 0xFF4A
  @wx : UInt8 = 0x00_u8                               # 0xFF4B

  def initialize(@display : Display, @interrupts : Interrupts)
  end

  def scanline
    window_map = window_tile_map == 0_u8 ? 0x1800 : 0x1C00      # 0x9800 : 0x9C00
    background_map = bg_tile_map == 0_u8 ? 0x1800 : 0x1C00      # 0x9800 : 0x9C00
    tile_data_table = bg_window_tile_map == 0 ? 0x1000 : 0x0000 # 0x9000 : 0x8000
    tile_row_window = (@ly.to_u16 + @scy) % 8
    tile_row = (@ly.to_u16 + @scy) % 8
    (0...160).each do |x|
      if window_enabled? && @wy <= @ly && -7 + @wx <= x
        # tile_num = @vram[window_map + (x // 8) + (@ly.to_u16 // 8) * 32]
        tile_num = @vram[window_map + (((x - @wx - 7) // 8) % 32) + ((((@ly.to_u16 - @wy) // 8) * 32) % (32 * 32))]
        tile_ptr = tile_data_table + 16 * tile_num
        byte_1 = @vram[tile_ptr + tile_row_window * 2]
        byte_2 = @vram[tile_ptr + tile_row_window * 2 + 1]
        lsb = (byte_1 >> (7 - ((x - @wx - 7) % 8))) & 0x1
        msb = (byte_2 >> (7 - ((x - @wx - 7) % 8))) & 0x1
        color = (msb << 1) | lsb
        @framebuffer[@ly][x] = color
      elsif bg_display?
        tile_num = @vram[background_map + (((x + @scx) // 8) % 32) + ((((@ly.to_u16 + @scy) // 8) * 32) % (32 * 32))]
        tile_ptr = tile_data_table + 16 * tile_num # todo other address space
        byte_1 = @vram[tile_ptr + tile_row * 2]
        byte_2 = @vram[tile_ptr + tile_row * 2 + 1]
        lsb = (byte_1 >> (7 - ((x + @scx) % 8))) & 0x1
        msb = (byte_2 >> (7 - ((x + @scx) % 8))) & 0x1
        color = (msb << 1) | lsb
        @framebuffer[@ly][x] = color
      end
    end

    if sprite_enabled?
      count = 0
      (0x00..0x9F).step 4 do |sprite_address|
        sprite = Sprite.new @sprite_table[sprite_address], @sprite_table[sprite_address + 1], @sprite_table[sprite_address + 2], @sprite_table[sprite_address + 3]
        if bytes = sprite.on_line @ly, sprite_height
          (0...8).each do |col|
            x = col + sprite.x - 8
            break unless 0 <= x < 160
            if sprite.x_flip?
              lsb = (@vram[bytes[0]] >> col) & 0x1
              msb = (@vram[bytes[1]] >> col) & 0x1
            else
              lsb = (@vram[bytes[0]] >> (7 - col)) & 0x1
              msb = (@vram[bytes[1]] >> (7 - col)) & 0x1
            end
            color = (msb << 1) | lsb
            @framebuffer[@ly][x] = color.to_u8 if color > 0
          end
        end
      end
    end
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
          @interrupts.lcd_stat_interrupt = true if hblank_interrupt_enabled
          scanline # store scanline data
        end
      elsif self.mode_flag == 0 # hblank
        if @counter >= 204      # end of hblank reached
          @counter -= 204       # reset counter, saving extra cycles
          @ly += 1
          check_lyc
          if @ly == 144        # final row of screen complete
            self.mode_flag = 1 # switch to vblank
            @interrupts.lcd_stat_interrupt = true if vblank_interrupt_enabled
            @interrupts.vblank_interrupt = true
            @display.draw framebuffer, @bgp # render at vblank
          else
            self.mode_flag = 2 # switch to oam search
            @interrupts.lcd_stat_interrupt = true if oam_interrupt_enabled
          end
        end
      elsif self.mode_flag == 1 # vblank
        if @counter >= 456      # end of line reached
          @counter -= 456       # reset counter, saving extra cycles
          @ly += 1
          check_lyc
          if @ly == 154        # end of vblank reached
            self.mode_flag = 2 # switch to oam search
            @ly = 0            # reset ly
            @interrupts.lcd_stat_interrupt = true if oam_interrupt_enabled
          end
        end
      else
        raise "Invalid mode #{self.mode_flag}"
      end
    else                 # lcd is disabled
      @counter = 0       # reset cycle counter
      self.mode_flag = 0 # default mode that allows reading all vram
      @ly = 0            # reset ly
    end
  end

  def check_lyc : Nil
    if @ly == @lyc
      @coincidence_flag = true
      if coincidence_interrupt_enabled
        @interrupts.lcd_stat_interrupt = true
      end
    else
      @coincidence_flag = false
    end
  end

  # read from ppu memory
  def [](index : Int) : UInt8
    case index
    when Memory::VRAM         then @vram[index - Memory::VRAM.begin]
    when Memory::SPRITE_TABLE then @sprite_table[index - Memory::SPRITE_TABLE.begin]
    when 0xFF40               then @lcd_control
    when 0xFF41               then @lcd_status
    when 0xFF42               then @scy
    when 0xFF43               then @scx
    when 0xFF44               then @ly
    when 0xFF45               then @lyc
    when 0xFF46               then @dma
    when 0xFF47               then @bgp
    when 0xFF48               then @obp0
    when 0xFF49               then @obp1
    when 0xFF4A               then @wy
    when 0xFF4B               then @wx
    when 0xFF4F               then 0xFF_u8 # VBK - CGB only
    when 0xFF51..0xFF55       then 0xFF_u8 # DMA - CGB only
    else                           raise "Reading from invalid ppu register: #{hex_str index.to_u16!}"
    end
  end

  # write to ppu memory
  def []=(index : Int, value : UInt8) : Nil
    case index
    when Memory::VRAM         then @vram[index - Memory::VRAM.begin] = value
    when Memory::SPRITE_TABLE then @sprite_table[index - Memory::SPRITE_TABLE.begin] = value
    when 0xFF40               then @lcd_control = value
    when 0xFF41               then @lcd_status = value
    when 0xFF42               then @scy = value
    when 0xFF43               then @scx = value
    when 0xFF44               then @ly = value
    when 0xFF45               then @lyc = value
    when 0xFF46               then @dma = value
    when 0xFF47               then @bgp = value
    when 0xFF48               then @obp0 = value
    when 0xFF49               then @obp1 = value
    when 0xFF4A               then @wy = value
    when 0xFF4B               then @wx = value
    when 0xFF4F               then nil # VBK - CGB only
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

  def bg_window_tile_map : UInt8
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
end
