class Display
  WIDTH  = 160
  HEIGHT = 144

  PIXELFORMAT_RGB24       = (1 << 28) | (7 << 24) | (1 << 20) | (0 << 16) | (24 << 8) | (3 << 0)
  TEXTUREACCESS_STREAMING = 1

  @window : SDL::Window?
  @renderer : SDL::Renderer?
  @texture : Pointer(LibSDL::Texture)?

  def initialize(scale = 4, title : String? = nil)
    {% unless flag? :headless %}
      @window = SDL::Window.new("CryBoy" + (title.nil? ? "" : " - #{title}"), WIDTH * scale, HEIGHT * scale)
      @renderer = SDL::Renderer.new @window.not_nil!
      @renderer.not_nil!.logical_size = {WIDTH, HEIGHT}
      @texture = LibSDL.create_texture @renderer.not_nil!, PIXELFORMAT_RGB24, TEXTUREACCESS_STREAMING, WIDTH, HEIGHT
    {% end %}
  end

  def draw(framebuffer : Array(RGB)) : Nil
    {% unless flag? :headless %}
      LibSDL.update_texture @texture, nil, framebuffer, WIDTH * sizeof(RGB)
      @renderer.not_nil!.clear
      @renderer.not_nil!.copy @texture
      @renderer.not_nil!.present
    {% end %}
  end
end

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
