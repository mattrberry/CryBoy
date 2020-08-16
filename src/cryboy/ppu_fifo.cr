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
  @fifo_sprite = Deque(Pixel).new 8

  @cycle_counter : UInt16 = 0x0000 # count number of cycles into current line

  @fetch_counter = 0
  @fetch_counter_sprite = 0
  @fetcher_x = 0
  @lx : Int32 = 0
  @smooth_scroll_sampled = false
  @fetching_window = false
  @fetching_sprite = false

  @tile_num : UInt8 = 0x00
  @tile_data_low : UInt8 = 0x00
  @tile_data_high : UInt8 = 0x00

  @sprites = Array(Sprite).new

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

  # get first 10 sprites on scanline, ordered
  # the order dictates how sprites should render
  def get_sprites : Array(Sprite)
    sprites = [] of Sprite
    (0x00..0x9F).step 4 do |sprite_address|
      sprite = Sprite.new @sprite_table[sprite_address], @sprite_table[sprite_address + 1], @sprite_table[sprite_address + 2], @sprite_table[sprite_address + 3]
      if sprite.on_line @ly, sprite_height
        index = 0
        if !@cgb_ptr.value
          sprites.each do |sprite_elm|
            break if sprite.x >= sprite_elm.x
            index += 1
          end
        end
        sprites.insert index, sprite
      end
      break if sprites.size >= 10
    end
    sprites.reverse
  end

  def tick_bg_fetcher : Nil
    case FETCHER_ORDER[@fetch_counter]
    in FetchStage::GET_TILE
      if @fetching_window
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
      if @fetching_window
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
      if @fetching_window
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
          lsb = (@tile_data_low >> (7 - col)) & 0x1
          msb = (@tile_data_high >> (7 - col)) & 0x1
          color = (msb << 1) | lsb
          @fifo.push Pixel.new(bg_display? ? color : 0_u8, 0, 0, 0)
        end
        @fetch_counter += 1
      end
    in FetchStage::SLEEP
      @fetch_counter += 1
    end
    @fetch_counter %= FETCHER_ORDER.size
  end

  def tick_sprite_fetcher : Nil
    case FETCHER_ORDER[@fetch_counter_sprite]
    in FetchStage::GET_TILE
      @fetch_counter_sprite += 1
    in FetchStage::GET_TILE_DATA_LOW
      @fetch_counter_sprite += 1
    in FetchStage::GET_TILE_DATA_HIGH
      @fetching_sprite = false
      sprite = @sprites.shift
      bytes = sprite.bytes @ly, sprite_height
      existing_pixels = @fifo_sprite.size
      8.times do |col|
        x = col + sprite.x - 8
        next unless 0 <= x < Display::WIDTH # only render sprites on screen
        if sprite.x_flip?
          lsb = (@vram[0][bytes[0]] >> col) & 0x1
          msb = (@vram[0][bytes[1]] >> col) & 0x1
        else
          lsb = (@vram[0][bytes[0]] >> (7 - col)) & 0x1
          msb = (@vram[0][bytes[1]] >> (7 - col)) & 0x1
        end
        color = (msb << 1) | lsb
        if col >= existing_pixels
          @fifo_sprite.push Pixel.new(color, sprite.dmg_palette_number, 0, sprite.priority)
        end
      end
      @fetch_counter_sprite += 1
    in FetchStage::PUSH_PIXEL
      @fetch_counter_sprite += 1
    in FetchStage::SLEEP
      @fetch_counter_sprite += 1
    end
    @fetch_counter_sprite %= FETCHER_ORDER.size
  end

  def sample_smooth_scrolling
    @smooth_scroll_sampled = true
    if @fetching_window
      @lx = -Math.max(0, 7 - @wx)
    else
      @lx = -(7 & @scx)
    end
  end

  def tick_shifter : Nil
    if @fifo.size > 0
      bg_pixel = @fifo.shift
      sprite_pixel = @fifo_sprite.shift if @fifo_sprite.size > 0
      if !sprite_pixel.nil? && sprite_pixel.color > 0 && (sprite_pixel.background_priority == 0 || bg_pixel.color == 0)
        pixel = sprite_pixel
        palette = palette_to_array(sprite_pixel.palette == 0 ? @obp0 : @obp1)
      else
        pixel = bg_pixel
        palette = palette_to_array @bgp
      end
      sample_smooth_scrolling unless @smooth_scroll_sampled
      if @lx >= 0 # otherwise drop pixel on floor
        @framebuffer[Display::WIDTH * @ly + @lx] = @palettes[0][palette[pixel.color]].convert_from_cgb @ran_bios
      end
      @lx += 1
      if @lx == Display::WIDTH
        self.mode_flag = 0
      end
      if window_enabled? && @ly >= @wy && @lx + 7 >= @wx && !@fetching_window
        reset_bg_fifo fetching_window: true
      end
      if sprite_enabled? && @sprites.size > 0 && @lx + 8 == @sprites[0].x
        @fetching_sprite = true
        @fetch_counter_sprite = 0
      end
    end
  end

  def reset_bg_fifo(fetching_window : Bool) : Nil
    @fifo.clear
    @fetcher_x = 0
    @fetch_counter = 0
    @fetching_window = fetching_window
    @current_window_line += 1 if @fetching_window
  end

  def reset_sprite_fifo : Nil
    @fifo_sprite.clear
    @fetch_counter_sprite = 0
    @fetching_sprite = false
  end

  # tick ppu forward by specified number of cycles
  def tick(cycles : Int) : Nil
    if lcd_enabled?
      cycles.times do
        case self.mode_flag
        when 2 # OAM search
          if @cycle_counter == 80
            self.mode_flag = 3
            reset_bg_fifo fetching_window: window_enabled? && @ly >= @wy && @wx <= 7
            reset_sprite_fifo
            @lx = 0
            @smooth_scroll_sampled = false
            @sprites = get_sprites
          end
        when 3 # drawing
          if @fetching_sprite
            tick_sprite_fetcher
          else
            tick_bg_fetcher
            tick_shifter
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
              @current_window_line = -1
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
              # todo: I think the timing here might be _just wrong_
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
