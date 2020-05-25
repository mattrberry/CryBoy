require "spec"
require "../src/cryboy"

def new_cpu(bytes : Array(Int))
  cpu = CPU.new(new_memory(bytes), true)
  cpu.sp = 0xFFFE_u16
  cpu
end

def new_memory(bytes : Array(Int))
  rom = Bytes.new bytes.size
  bytes.each_with_index do |byte, i|
    rom[i] = byte.to_u8!
  end
  Memory.new(Cartridge.new(rom))
end
