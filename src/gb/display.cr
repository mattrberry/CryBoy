require "sdl"

class Display
  @colors = [SDL::Color[0xFF], SDL::Color[0xAA], SDL::Color[0x55], SDL::Color[0x00]]

  def initialize(@scale = 4, @width = 160, @height = 144)
    SDL.init(SDL::Init::VIDEO)
    at_exit { SDL.quit }
    @window = SDL::Window.new("CryBoy", @width * @scale, @height * @scale)
    @renderer = SDL::Renderer.new @window
    # @all_tiles_window = SDL::Window.new("ALL TILES", 256 * @scale, 256 * @scale)
    # @all_tiles_renderer = SDL::Renderer.new @all_tiles_window
  end

  def draw_scanlines : Nil
    @renderer.draw_color = SDL::Color[0xFF, 0x00, 0x00]
    (1...@width).each do |col|
      @renderer.draw_line col * @scale, 0, col * @scale, @height * @scale
    end
    (1...@height).each do |row|
      @renderer.draw_line 0, row * @scale, @width * @scale, row * @scale
    end
  end

  # a method for showing all tiles in vram at 0x8000 (for debugging)
  def draw_all_tiles(memory : Memory, scanlines : Array(Scanline))
    (0...32).each do |y|
      (0...32).each do |x|
        tile_ptr = 0x8000 + (y * 16 * 16) + (x * 16)
        # puts "tile ptr: #{hex_str tile_ptr.to_u16}"
        (0...8).each do |tile_row|
          byte_1 = memory[tile_ptr + 2 * tile_row]
          byte_2 = memory[tile_ptr + 2 * tile_row + 1]
          (0...8).each do |tile_col|
            lsb = (byte_1 >> (7 - tile_col)) & 0x1
            msb = (byte_2 >> (7 - tile_col)) & 0x1
            @all_tiles_renderer.draw_color = @colors[(msb << 1) | lsb]
            # puts "x:#{8 * x + tile_col},\ty:#{8 * y + tile_row},\tmsb:#{msb},\tlsb:#{lsb},\tcom:#{(msb << 1) | lsb}, color:#{@colors[(msb << 1) | lsb]}"
            @all_tiles_renderer.fill_rect((8 * x + tile_col) * @scale, (8 * y + tile_row) * @scale, @scale, @scale)
          end
        end
      end
    end
    @all_tiles_renderer.present
  end

  def draw(framebuffer : Array(Array(UInt8)), palette : UInt8) : Nil
    colors = [@colors[palette & 0x3], @colors[(palette >> 2) & 0x3], @colors[(palette >> 4) & 0x3], @colors[(palette >> 6) & 0x3]]
    framebuffer.each_with_index do |scanline, y|
      scanline.each_with_index do |color, x|
        @renderer.draw_color = colors[color]
        @renderer.fill_rect(x * @scale, y * @scale, @scale, @scale)
      end
    end

    # draw_scanlines
    @renderer.present
  end
end
