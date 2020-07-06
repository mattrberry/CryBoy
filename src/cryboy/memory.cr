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
  @bootrom = Bytes.new 0
  @cycle_tick_count = 0

  # keep other components in sync with memory, usually before memory access
  def tick_components(cycles = 4) : Nil
    @cycle_tick_count += cycles
    @ppu.tick cycles
    @apu.tick cycles
    @timer.tick cycles
  end

  def reset_cycle_count : Nil
    @cycle_tick_count = 0
  end

  # tick remainder of expected cycles, then reset counter
  def tick_extra(total_expected_cycles : Int) : Nil
    raise "Operation took #{@cycle_tick_count} cycles, but only expected #{total_expected_cycles}" if @cycle_tick_count > total_expected_cycles
    tick_components total_expected_cycles - @cycle_tick_count
    reset_cycle_count
  end

  def initialize(@cartridge : Cartridge, @interrupts : Interrupts, @ppu : PPU, @apu : APU, @timer : Timer, @joypad : Joypad, bootrom : String? = nil)
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
      when 0xFF40..0xFF4B then @ppu[index]
      when 0xFF4F         then @ppu[index]
      when 0xFF51..0xFF55 then @ppu[index]
      when 0xFF70         then 0xF8_u8 | @wram_bank
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
    read_byte index
  end

  # write a 8 bits to memory (doesn't tick components)
  def write_byte(index : Int, value : UInt8) : Nil
    puts "speed switch -- #{hex_str index.to_u16}: #{hex_str value}" if index == 0xFF4D
    @bootrom = Bytes.new 0 if index == 0xFF50 && value == 0x11
    # todo other dma stuff
    case index
    when ROM_BANK_0   then @cartridge[index] = value
    when ROM_BANK_N   then @cartridge[index] = value
    when VRAM         then @ppu[index] = value
    when EXTERNAL_RAM then @cartridge[index] = value
    when WORK_RAM_0   then @wram[0][index - WORK_RAM_0.begin] = value
    when WORK_RAM_N   then @wram[@wram_bank][index - WORK_RAM_N.begin] = value
    when ECHO         then @memory[index - 0x2000] = value
    when SPRITE_TABLE then @ppu[index] = value
    when NOT_USABLE   then nil # todo: should I raise here?
    when IO_PORTS
      case index
      when 0xFF00         then @joypad.write value
      when 0xFF01         then @memory[index] = value # ; print value.chr
      when 0xFF04..0xFF07 then @timer[index] = value
      when 0xFF0F         then @interrupts[index] = value
      when 0xFF10..0xFF3F then @apu[index] = value
      when 0xFF46         then dma_transfer(value.to_u16 << 8)
      when 0xFF40..0xFF4B then @ppu[index] = value
      when 0xFF4F         then @ppu[index] = value
      when 0xFF51..0xFF55 then @ppu[index] = value
      when 0xFF70         then @wram_bank = value & 0x7; @wram_bank += 1 if @wram_bank == 0
      else                     @memory[index] = value
      end
    when HRAM          then @memory[index] = value
    when INTERRUPT_REG then @interrupts[index] = value
    else                    raise "FAILED TO SET INDEX #{index}"
    end
  end

  # write 8 bits to memory and tick other components
  def []=(index : Int, value : UInt8) : Nil
    tick_components
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

  def dma_transfer(source : UInt16) : Nil
    # todo add delay
    (0x00..0x9F).each { |i| write_byte 0xFE00 + i, read_byte source + i }
  end
end
