class Memory
  ROM_BANK_0    = 0x0000..0x3FFF
  ROM_BANK_N    = 0x4000..0x7FFF
  VRAM          = 0x8000..0x9FFF
  EXTERNAL_RAM  = 0xA000..0xBFFF
  WORK_RAM_0    = 0xC000..0xCFFF
  WORK_RAM_N    = 0xD000..0xDFFF
  ECHO          = 0xE000..0xFDFF
  SPRITE_TABLE  = 0xFE00..0xFE9F
  NOT_USABLE    = 0xFEA0..0xFEFF
  IO_PORTS      = 0xFF00..0xFF7F
  HRAM          = 0xFF80..0xFFFE
  INTERRUPT_REG = 0xFFFF

  @memory = Bytes.new 0xFFFF + 1
  @wram = Array(Bytes).new 8 { Bytes.new 4096 }
  @wram_bank : UInt8 = 1
  property bootrom = Bytes.new 0
  @cycle_tick_count = 0

  # From I conversation I had with gekkio on the EmuDev Discord: (todo)
  #
  # the DMA controller takes over the source bus, which is either the external bus or the video ram bus
  # and obviously the OAM itself since it's the target
  # nothing else is affected by DMA
  # in other words:
  # * if the external bus is the source bus, accessing these lead to conflict situations: work RAM, anything on the cartridge. Everything else (including video RAM) doesn't lead to conflicts
  # * if the video RAM is the source bus, accessing it leads to a conflict situation. Everything else (including work RAM, and the cartridge) doesn't lead to conflicts
  #
  # if the DMA source bus is read, you always get the current byte read by the DMA controller
  # accessing the target bus (= OAM) works differently, and returning 0xff is probably reasonable until more information is gathered...I haven't yet studied OAM very much so I don't yet know the right answers

  # As of right now, all my DMA implementation strives to do is get the timing
  # correct, as well as block access to OAM during DMA. That much is complete.
  @dma : UInt8 = 0x00
  @dma_position : UInt8 = 0x00
  @next_dma_source : UInt16? = nil
  @current_dma_source : UInt16? = nil

  @hdma_src : UInt16 = 0x0000
  @hdma_dst : UInt16 = 0x8000
  @hdma5 : UInt8 = 0xFF
  @hdma_length : UInt16 = 0x0000
  @hdma_pos : UInt16 = 0x0000
  @hdma_transfer_this_hblank : Bool = false

  @requested_speed_switch : Bool = false
  @current_speed : UInt8 = 1

  def stop_instr : Nil
    if @requested_speed_switch && @cgb_ptr.value
      puts "switching speeds"
      @requested_speed_switch = false
      @current_speed = (@current_speed % 2) + 1 # toggle between 1 and 2
    end
  end

  # keep other components in sync with memory, usually before memory access
  def tick_components(cycles = 4, hdma = false) : Nil
    @cycle_tick_count += cycles if !hdma
    @ppu.tick cycles // @current_speed
    @apu.tick cycles // @current_speed
    @timer.tick cycles
    dma_tick cycles
    hdma_step if !hdma
  end

  def reset_cycle_count : Nil
    @cycle_tick_count = 0
  end

  # tick remainder of expected cycles, then reset counter
  def tick_extra(total_expected_cycles : Int) : Nil
    raise "Operation took #{@cycle_tick_count} cycles, but only expected #{total_expected_cycles}" if @cycle_tick_count > total_expected_cycles
    remaining = total_expected_cycles - @cycle_tick_count
    tick_components remaining if remaining > 0
    reset_cycle_count
  end

  def initialize(@cartridge : Cartridge, @interrupts : Interrupts,
                 @ppu : PPU, @apu : APU, @timer : Timer,
                 @joypad : Joypad, @cgb_ptr : Pointer(Bool),
                 bootrom : String? = nil)
    if !bootrom.nil?
      File.open bootrom do |file|
        @bootrom = Bytes.new file.size
        file.read @bootrom
      end
    end
  end

  def skip_boot : Nil
    write_byte 0xFF05, 0x00_u8 # TIMA
    write_byte 0xFF06, 0x00_u8 # TMA
    write_byte 0xFF07, 0x00_u8 # TAC
    write_byte 0xFF10, 0x80_u8 # NR10
    write_byte 0xFF11, 0xBF_u8 # NR11
    write_byte 0xFF12, 0xF3_u8 # NR12
    write_byte 0xFF14, 0xBF_u8 # NR14
    write_byte 0xFF16, 0x3F_u8 # NR21
    write_byte 0xFF17, 0x00_u8 # NR22
    write_byte 0xFF19, 0xBF_u8 # NR24
    write_byte 0xFF1A, 0x7F_u8 # NR30
    write_byte 0xFF1B, 0xFF_u8 # NR31
    write_byte 0xFF1C, 0x9F_u8 # NR32
    write_byte 0xFF1E, 0xBF_u8 # NR33
    write_byte 0xFF20, 0xFF_u8 # NR41
    write_byte 0xFF21, 0x00_u8 # NR42
    write_byte 0xFF22, 0x00_u8 # NR43
    write_byte 0xFF23, 0xBF_u8 # NR44
    write_byte 0xFF24, 0x77_u8 # NR50
    write_byte 0xFF25, 0xF3_u8 # NR51
    write_byte 0xFF26, 0xF1_u8 # NR52
    write_byte 0xFF40, 0x91_u8 # LCDC
    write_byte 0xFF42, 0x00_u8 # SCY
    write_byte 0xFF43, 0x00_u8 # SCX
    write_byte 0xFF45, 0x00_u8 # LYC
    write_byte 0xFF47, 0xFC_u8 # BGP
    write_byte 0xFF48, 0xFF_u8 # OBP0
    write_byte 0xFF49, 0xFF_u8 # OBP1
    write_byte 0xFF4A, 0x00_u8 # WY
    write_byte 0xFF4B, 0x00_u8 # WX
    write_byte 0xFFFF, 0x00_u8 # IE
  end

  # read 8 bits from memory (doesn't tick components)
  def read_byte(index : Int) : UInt8
    return @bootrom[index] if @bootrom.size > 0 && (0x000 <= index < 0x100 || 0x200 <= index < 0x900)
    case index
    when ROM_BANK_0   then @cartridge[index]
    when ROM_BANK_N   then @cartridge[index]
    when VRAM         then @ppu[index]
    when EXTERNAL_RAM then @cartridge[index]
    when WORK_RAM_0   then @wram[0][index - WORK_RAM_0.begin]
    when WORK_RAM_N   then @wram[@wram_bank][index - WORK_RAM_N.begin]
    when ECHO         then @memory[index - 0x2000]
    when SPRITE_TABLE then @ppu[index]
    when NOT_USABLE   then 0_u8
    when IO_PORTS
      case index
      when 0xFF00         then @joypad.read
      when 0xFF04..0xFF07 then @timer[index]
      when 0xFF0F         then @interrupts[index]
      when 0xFF10..0xFF3F then @apu[index]
      when 0xFF46         then @dma
      when 0xFF40..0xFF4B then @ppu[index]
      when 0xFF4D         then 0x7E_u8 | ((@current_speed - 1) << 7) | (@requested_speed_switch ? 1 : 0)
      when 0xFF4F         then @ppu[index]
      when 0xFF51         then (@hdma_src >> 8).to_u8
      when 0xFF52         then @hdma_src.to_u8
      when 0xFF53         then (@hdma_dst >> 8).to_u8
      when 0xFF54         then @hdma_dst.to_u8
      when 0xFF55         then @hdma5 # todo
      when 0xFF68..0xFF6B then @ppu[index]
      when 0xFF70         then @cgb_ptr.value ? 0xF8_u8 | @wram_bank : @memory[index]
      else                     @memory[index]
      end
    when HRAM          then @memory[index]
    when INTERRUPT_REG then @interrupts[index]
    else                    raise "FAILED TO GET INDEX #{index}"
    end
  end

  # read 8 bits from memory and tick other components
  def [](index : Int) : UInt8
    # todo: not all of these registers are used. unused registers _should_ return 0xFF
    # - sound doesn't take all of 0xFF10..0xFF3F
    tick_components
    return 0xFF_u8 if (!@current_dma_source.nil? || @dma_position <= 0xA0) && SPRITE_TABLE.includes?(index)
    read_byte index
  end

  # write a 8 bits to memory (doesn't tick components)
  def write_byte(index : Int, value : UInt8) : Nil
    if index == 0xFF50 && value == 0x11
      @bootrom = Bytes.new 0
      @cgb_ptr.value = @cartridge.cgb != Cartridge::CGB::NONE
    end
    case index
    when ROM_BANK_0   then @cartridge[index] = value
    when ROM_BANK_N   then @cartridge[index] = value
    when VRAM         then @ppu[index] = value
    when EXTERNAL_RAM then @cartridge[index] = value
    when WORK_RAM_0   then @wram[0][index - WORK_RAM_0.begin] = value
    when WORK_RAM_N   then @wram[@wram_bank][index - WORK_RAM_N.begin] = value
    when ECHO         then @memory[index - 0x2000] = value
    when SPRITE_TABLE then @ppu[index] = value
    when NOT_USABLE   then nil
    when IO_PORTS
      case index
      when 0xFF00         then @joypad.write value
      when 0xFF01         then @memory[index] = value # ; print value.chr
      when 0xFF04..0xFF07 then @timer[index] = value
      when 0xFF0F         then @interrupts[index] = value
      when 0xFF10..0xFF3F then @apu[index] = value
      when 0xFF46         then dma_transfer value
      when 0xFF40..0xFF4B then @ppu[index] = value
      when 0xFF4D         then @requested_speed_switch = value & 0x1 > 0
      when 0xFF4F         then @ppu[index] = value
      when 0xFF51         then @hdma_src = (@hdma_src & 0x00FF) | (value.to_u16 << 8)
      when 0xFF52         then @hdma_src = (@hdma_src & 0xFF00) | (value.to_u16 & 0xF0)
      when 0xFF53         then @hdma_dst = (@hdma_dst & 0x80FF) | ((value.to_u16 & 0x1F) << 8)
      when 0xFF54         then @hdma_dst = (@hdma_dst & 0xFF00) | (value.to_u16 & 0xF0)
      when 0xFF55         then start_hdma_transfer value
      when 0xFF68..0xFF6B then @ppu[index] = value
      when 0xFF70
        if @cgb_ptr.value
          @wram_bank = value & 0x7
          @wram_bank += 1 if @wram_bank == 0
        else
          @memory[index] = value
        end
      else @memory[index] = value
      end
    when HRAM          then @memory[index] = value
    when INTERRUPT_REG then @interrupts[index] = value
    else                    raise "FAILED TO SET INDEX #{index}"
    end
  end

  # write 8 bits to memory and tick other components
  def []=(index : Int, value : UInt8) : Nil
    tick_components
    return if (!@current_dma_source.nil? || @dma_position <= 0xA0) && SPRITE_TABLE.includes?(index)
    write_byte index, value
  end

  # write 16 bits to memory
  def []=(index : Int, value : UInt16) : Nil
    self[index] = (value & 0xFF).to_u8
    self[index + 1] = (value >> 8).to_u8
  end

  # read 16 bits from memory
  def read_word(index : Int) : UInt16
    self[index].to_u16 | (self[index + 1].to_u16 << 8)
  end

  def dma_transfer(source : UInt8) : Nil
    @dma = source
    @next_dma_source = @dma.to_u16 << 8
  end

  def dma_tick(cycles : Int) : Nil
    (cycles // 4).times do
      @dma_position += 1 if @dma_position == 0xA0
      unless @current_dma_source.nil?
        write_byte 0xFE00 + @dma_position, read_byte @current_dma_source.not_nil! + @dma_position
        @dma_position += 1
        @current_dma_source = nil if @dma_position > 0x9F
      end
      unless @next_dma_source.nil?
        @current_dma_source = @next_dma_source
        @next_dma_source = nil
        @dma_position = 0x00
      end
    end
  end

  def start_hdma_transfer(value : UInt8) : Nil
    # hdma transfer takes 8 T-cycles for every 16 bytes transfered
    hdma = value & 0x80 > 0 # as opposed to gdma
    length = ((value.to_u16 & 0x7F) + 1) * 0x10
    if hdma
      @hdma_length = length
      @hdma_pos = 0
    else
      length.times do |idx|
        write_byte @hdma_dst + idx, read_byte @hdma_src + idx
        tick_components hdma: true if idx % 8 == 7 # 2 bytes per T-cycle
      end
      @hdma5 = 0xFF
    end
  end

  def hdma_step : Nil
    @hdma_transfer_this_hblank = false if @ppu.mode_flag != 0
    if @hdma_pos < @hdma_length && @ppu.mode_flag == 0 && !@hdma_transfer_this_hblank
      0x10.times do
        write_byte @hdma_dst + @hdma_pos, read_byte @hdma_src + @hdma_pos
        tick_components hdma: true if @hdma_pos % 8 == 7 # 2 bytes per T-cycle
        @hdma_pos += 1
      end
      @hdma_transfer_this_hblank = true
      @hdma5 = @hdma_pos == @hdma_length ? 0xFF_u8 : ((@hdma_length - @hdma_pos) // 0x10 - 1).to_u8
    end
  end
end
