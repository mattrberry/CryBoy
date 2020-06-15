class Display
  WIDTH  = 160
  HEIGHT = 144

  @colors = [SDL::Color[0xE0, 0xF8, 0xCF], SDL::Color[0x86, 0xC0, 0x6C], SDL::Color[0x30, 0x68, 0x50], SDL::Color[0x07, 0x17, 0x20]]

  def initialize(scale = 2, title : String? = nil)
    @window = SDL::Window.new("CryBoy" + (title.nil? ? "" : " - #{title}"), WIDTH * scale, HEIGHT * scale)
    @renderer = SDL::Renderer.new @window
    @renderer.logical_size = {WIDTH, HEIGHT}
  end

  def draw(framebuffer : Array(Array(UInt8)), palette : UInt8) : Nil
    framebuffer.each_with_index do |scanline, y|
      scanline.each_with_index do |color, x|
        @renderer.draw_color = @colors[color]
        @renderer.draw_point x, y
      end
    end
    @renderer.present
  end
end

###############################################################################
# Potential start to using textures rather than drawing colors.
# Could improve render speeds.

# PIXELFORMAT_RGB24       = (1 << 28) | (7 << 24) | (1 << 20) | (0 << 16) | (24 << 8) | (3 << 0)
# TEXTUREACCESS_STREAMING = 1

# @texture = LibSDL.create_texture @renderer, PIXELFORMAT_RGB24, TEXTUREACCESS_STREAMING, WIDTH, HEIGHT

# @framebuffer2 = Bytes.new WIDTH * HEIGHT * 3
# framebuffer.each_with_index do |scanline, y|
#   scanline.each_with_index do |color, x|
#     @framebuffer2.not_nil![(WIDTH * y + x) * 3 + 0] = @colors[color].r.to_u8
#     @framebuffer2.not_nil![(WIDTH * y + x) * 3 + 1] = @colors[color].g.to_u8
#     @framebuffer2.not_nil![(WIDTH * y + x) * 3 + 2] = @colors[color].b.to_u8
#   end
# end
# LibSDL.update_texture @texture, nil, pointerof(@framebuffer2), WIDTH * 3
# @renderer.clear
# @renderer.copy @texture
# @renderer.present

###############################################################################
# Method for drawing all tiles in vram

# @all_tiles_window = SDL::Window.new("ALL TILES", 128 * scale, 192 * scale)
# @all_tiles_renderer = SDL::Renderer.new @all_tiles_window
# @all_tiles_renderer.logical_size = {128, 192}

# # a method for showing all tiles in vram for debugging
# def draw_all_tiles(memory : Memory)
#   (0...24).each do |y|
#     (0...16).each do |x|
#       tile_ptr = 0x8000 + (y * 16 * 16) + (x * 16)
#       (0...8).each do |tile_row|
#         byte_1 = memory[tile_ptr + 2 * tile_row]
#         byte_2 = memory[tile_ptr + 2 * tile_row + 1]
#         (0...8).each do |tile_col|
#           lsb = (byte_1 >> (7 - tile_col)) & 0x1
#           msb = (byte_2 >> (7 - tile_col)) & 0x1
#           @all_tiles_renderer.draw_color = @colors[(msb << 1) | lsb]
#           @all_tiles_renderer.draw_point((8 * x + tile_col), (8 * y + tile_row))
#         end
#       end
#     end
#   end
#   @all_tiles_renderer.present
# end
