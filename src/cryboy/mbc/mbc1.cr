class MBC1 < Cartridge
  def initialize(@program : Bytes)
    @ram = Bytes.new ram_size
    @rom_bank = 1
    @ram_bank = 0
    @ram_enabled = false
    @mode = 0
  end

  def [](index : Int) : UInt8
    case index
    when Memory::ROM_BANK_0 then @program[index]
    when Memory::ROM_BANK_N then @program[(@rom_bank * Memory::ROM_BANK_N.size) + (index - Memory::ROM_BANK_N.begin)]
    when Memory::EXTERNAL_RAM
      if @ram_enabled
        @ram[(@ram_bank * Memory::EXTERNAL_RAM.size) + (index - Memory::EXTERNAL_RAM.begin)]
      else
        0xFF_u8
      end
    else raise "Reading from invalid cartridge register #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when 0x0000..0x1FFF then @ram_enabled = value & 0x0A == 0x0A
    when 0x2000..0x3FFF
      @rom_bank = (@rom_bank & 0b11100000) + (value & 0b00011111)
      @rom_bank += 1 if [0x00, 0x20, 0x40, 0x60].includes? @rom_bank
    when 0x4000..0x5FFF
      if @mode == 0
        @rom_bank = (@rom_bank & 0b00011111) + (value & 0b00000011)
        @rom_bank += 1 if [0x00, 0x20, 0x40, 0x60].includes? @rom_bank
      else
        @ram_bank = 0x3 & value
      end
    when 0x6000..0x7FFF then @mode = 0x1 & value
    when Memory::EXTERNAL_RAM
      if @ram_enabled
        if @mode == 0
          @ram[index - Memory::EXTERNAL_RAM.begin] = value
        else
          @ram[(@ram_bank * Memory::EXTERNAL_RAM.size) + (index - Memory::EXTERNAL_RAM.begin)] = value
        end
      end
    else raise "Writing to invalid cartridge register: #{hex_str index.to_u16!}"
    end
  end
end
