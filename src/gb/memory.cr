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

  def initialize(@cartridge : Cartridge)
    @memory = Array(UInt8).new 0xFFFF + 1, 0_u8
  end

  def [](index : Int) : UInt8
    case index
    when ROM_BANK_0    then return @cartridge[index]
    when ROM_BANK_N    then return @cartridge[index]
    when VRAM          then return @memory[index]
    when EXTERNAL_RAM  then return @cartridge[index]
    when WORK_RAM_0    then return @memory[index]
    when WORK_RAM_N    then return @memory[index]
    when ECHO          then return @memory[index - 0x2000]
    when SPRITE_TABLE  then return @memory[index]
    when NOT_USABLE    then return 0_u8
    when IO_PORTS      then return @memory[index]
    when HRAM          then return @memory[index]
    when INTERRUPT_REG then return @memory[index]
    else raise "FAILED TO SET INDEX #{index}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    puts "write 0x#{value.to_s(16).rjust(2, '0').upcase} to index #{index}"
    # todo other dma stuff
    case index
    when ROM_BANK_0    then @cartridge[index] = value
    when ROM_BANK_N    then @cartridge[index] = value
    when VRAM          then @memory[index] = value
    when EXTERNAL_RAM  then @cartridge[index] = value
    when WORK_RAM_0    then @memory[index] = value
    when WORK_RAM_N    then @memory[index] = value
    when ECHO          then @memory[index - 0x2000] = value
    when SPRITE_TABLE  then @memory[index] = value
    when NOT_USABLE    then raise "Wrote to non-usable memory (todo)"
    when 0xFF46        then dma_transfer(value.to_u16 << 8)
    when IO_PORTS      then @memory[index] = value
    when HRAM          then @memory[index] = value
    when INTERRUPT_REG then @memory[index] = value
    end
  end

  def []=(index : Int, value : UInt16) : Nil
    puts "write 0x#{value.to_s(16).rjust(4, '0').upcase} to index #{index}"
    self[index] = (value && 0xFF).to_u8
    self[index + 1] = (value >> 8).to_u8
  end

  def read_word(index : Int) : UInt16
    self[index].to_u16 | (self[index + 1].to_u16 << 8)
  end

  def dma_transfer(source : UInt16) : Nil
    # todo add delay
    (0x00..0x9F).each { |i| self[0xFE00 + i] = self[source + i] }
  end
end
