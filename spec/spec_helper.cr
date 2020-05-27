require "spec"
require "../src/cryboy"

# define a new CPU with the given bytes as rom
def new_cpu(bytes : Array(Int))
  cpu = CPU.new(new_memory(bytes), Timer.new, true)
  cpu.sp = 0xFFFE_u16
  cpu
end

# define a new Memory with the given bytes as rom
def new_memory(bytes : Array(Int))
  rom = Bytes.new bytes.size
  bytes.each_with_index do |byte, i|
    rom[i] = byte.to_u8!
  end
  Memory.new(Cartridge.new(rom), Joypad.new, Timer.new)
end
