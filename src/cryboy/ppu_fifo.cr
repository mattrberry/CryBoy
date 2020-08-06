struct Pixel
  property color : UInt8               # 0-3
  property palette : UInt8             # 0-7
  property sprite_priority : UInt8     # OAM index for sprite
  property background_priority : UInt8 # OBJ-to_BG Priority bit

  def initialize(@color : UInt8, @palette : UInt8, @sprite_priority : UInt8, @background_priority : UInt8)
  end
end

class PPU < BasePPU
  @fifo = Deque(Pixel).new 8

  @cycle_counter : UInt16 = 0x0000 # count number of cycles into current line

  @fetch_counter = 0
  @fetcher_x = 0
  @lx : Int32? = nil
  @fetch_window = false

  @tile_num : UInt8 = 0x00
  @tile_data_low : UInt8 = 0x00
  @tile_data_high : UInt8 = 0x00

  @current_window_line = -1

  enum FetchStage
    GET_TILE
    GET_TILE_DATA_LOW
    GET_TILE_DATA_HIGH
    PUSH_PIXEL
    SLEEP
  end

  FETCHER_ORDER = [
    FetchStage::SLEEP, FetchStage::GET_TILE,
    FetchStage::SLEEP, FetchStage::GET_TILE_DATA_LOW,
    FetchStage::SLEEP, FetchStage::GET_TILE_DATA_HIGH,
    FetchStage::PUSH_PIXEL,
  ]

  def reset_fifo : Nil
    @fifo.clear
    @fetcher_x = 0
    @lx = nil
    @fetch_counter = 0
    @fetch_window = false
  end

  # tick ppu forward by specified number of cycles
  def tick(cycles : Int) : Nil
    if lcd_enabled?
      cycles.times do
        case self.mode_flag
        when 2 # OAM search
          if @cycle_counter == 80
            self.mode_flag = 3
            reset_fifo
          end
        when 3 # drawing
          case FETCHER_ORDER[@fetch_counter]
          in FetchStage::GET_TILE
            if @fetch_window
              window_map = window_tile_map == 0 ? 0x1800 : 0x1C00 # 0x9800 : 0x9C00
              tile_num_offset = @fetcher_x + ((@current_window_line // 8) * 32)
              @tile_num = @vram[0][window_map + tile_num_offset]
            else
              background_map = bg_tile_map == 0 ? 0x1800 : 0x1C00 # 0x9800 : 0x9C00
              tile_num_offset = ((@fetcher_x + (@scx // 8)) % 32) + ((((@ly.to_u16 + @scy) // 8) * 32) % (32 * 32))
              @tile_num = @vram[0][background_map + tile_num_offset]
            end
            @fetch_counter += 1
          in FetchStage::GET_TILE_DATA_LOW
            if bg_window_tile_data > 0
              tile_num = @tile_num
              tile_data_table = 0x0000 # 0x8000
            else
              tile_num = @tile_num.to_i8!
              tile_data_table = 0x1000 # 0x9000
            end
            # tile_num = bg_window_tile_data > 0 ? @tile_num : @tile_num.to_i8!
            tile_ptr = tile_data_table + 16 * tile_num
            if @fetch_window
              @tile_data_low = @vram[0][tile_ptr + (@current_window_line % 8) * 2]
            else
              @tile_data_low = @vram[0][tile_ptr + ((@ly.to_u16 + @scy) % 8) * 2]
            end
            @fetch_counter += 1
          in FetchStage::GET_TILE_DATA_HIGH
            if bg_window_tile_data > 0
              tile_num = @tile_num
              tile_data_table = 0x0000 # 0x8000
            else
              tile_num = @tile_num.to_i8!
              tile_data_table = 0x1000 # 0x9000
            end
            # tile_num = bg_window_tile_data > 0 ? @tile_num : @tile_num.to_i8!
            tile_ptr = tile_data_table + 16 * tile_num
            if @fetch_window
              @tile_data_high = @vram[0][tile_ptr + (@current_window_line % 8) * 2 + 1]
            else
              @tile_data_high = @vram[0][tile_ptr + ((@ly.to_u16 + @scy) % 8) * 2 + 1]
            end
            @fetch_counter += 1
            if @cycle_counter == 86
              @fetch_counter = 0 # drop first tile
            end
          in FetchStage::PUSH_PIXEL
            if @fifo.size == 0
              @fetcher_x += 1
              8.times do |col|
                if @fetch_window
                  lsb = (@tile_data_low >> (7 - ((col + 7 - @wx) % 8))) & 0x1
                  msb = (@tile_data_high >> (7 - ((col + 7 - @wx) % 8))) & 0x1
                else
                  lsb = (@tile_data_low >> (7 - col)) & 0x1
                  msb = (@tile_data_high >> (7 - col)) & 0x1
                end
                color = (msb << 1) | lsb
                @fifo.push Pixel.new(color, 0, 0, 0)
              end
              @fetch_counter += 1
            end
          in FetchStage::SLEEP
            @fetch_counter += 1
          end
          @fetch_counter %= FETCHER_ORDER.size
          if @fifo.size > 0
            palette = palette_to_array @bgp
            pixel = @fifo.shift
            @lx ||= -(7 & @scx)
            if @lx.not_nil! >= 0 # otherwise drop pixel on floor
              if bg_display?
                @framebuffer[Display::WIDTH * @ly + @lx.not_nil!] = @palettes[0][palette[pixel.color]].convert_from_cgb @ran_bios
              end
            end
            @lx = @lx.not_nil! + 1
            if @lx == Display::WIDTH
              self.mode_flag = 0
            end
            if window_enabled? && @ly >= @wy && @lx.not_nil! + 7 >= @wx && !@fetch_window
              @fifo.clear
              @fetcher_x = 0
              @fetch_counter = 0
              @fetch_window = true
              @current_window_line += 1
            end
          end
        when 0 # hblank
          if @cycle_counter == 456
            @cycle_counter = 0
            @ly += 1
            if @ly == Display::HEIGHT # final row of screen complete
              self.mode_flag = 1      # switch to vblank
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
            @ly += 1 if @ly != 0
            if @ly == 0          # end of vblank reached (ly has already shortcut to 0)
              self.mode_flag = 2 # switch to oam search
              @current_window_line = -1
            end
          end
          @ly = 0 if @ly == 153 && @cycle_counter > 4 # shortcut ly to from 153 to 0 after 4 cycles
        end
        @cycle_counter += 1
        handle_stat_interrupt
      end
    else                 # lcd is disabled
      @cycle_counter = 0 # reset cycle counter
      self.mode_flag = 0 # reset to mode 0
      @ly = 0            # reset ly
    end
  end
end
