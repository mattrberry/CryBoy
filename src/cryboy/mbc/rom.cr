class ROM < Cartridge
  def initialize(@rom : Bytes)
    @ram = Bytes.new ram_size
  end

  def [](index : Int) : UInt8
    case index
    when Memory::ROM_BANK_0   then @rom[index]
    when Memory::ROM_BANK_N   then @rom[index]
    when Memory::EXTERNAL_RAM then @ram[index - Memory::EXTERNAL_RAM.begin]
    else                           raise "Reading from invalid cartridge register #{hex_str index.to_u16!}"
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    case index
    when Memory::ROM_BANK_0   then nil
    when Memory::ROM_BANK_N   then nil
    when Memory::EXTERNAL_RAM then @ram[index - Memory::EXTERNAL_RAM.begin] = value
    else                           raise "Writing to invalid cartridge register: #{hex_str index.to_u16!}"
    end
  end
end
