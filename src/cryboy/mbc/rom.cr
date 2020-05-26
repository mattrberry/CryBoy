class ROM < Cartridge
  def initialize(@program : Bytes)
    @ram = Bytes.new Memory::EXTERNAL_RAM.size
  end

  def [](index : Int) : UInt8
    case index
    when Memory::EXTERNAL_RAM then return @ram[index - Memory::EXTERNAL_RAM.begin]
    else                           return @program[index]
    end
  end

  def []=(index : Int, value : UInt8) : Nil
    @ram[index - Memory::EXTERNAL_RAM.begin] = value if Memory::EXTERNAL_RAM.includes? index
  end
end
