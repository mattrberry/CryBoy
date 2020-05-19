require "./spec_helper"

describe CPU do
  describe "registers" do
    it "do computations correctly across registers" do
      cpu = new_cpu [] of UInt8
      cpu.b = 0x00
      cpu.c = 0x00
      cpu.bc.should eq 0x0000
      cpu.c += 0x01
      cpu.b.should eq 0x00
      cpu.c.should eq 0x01
      cpu.bc.should eq 0x0001
      cpu.bc += 0x4320
      cpu.b.should eq 0x43
      cpu.c.should eq 0x21
      cpu.bc.should eq 0x4321
    end
  end

  describe "0x00" do
    it "does nothing" do
      cpu = new_cpu [0x00]
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
    end
  end

  describe "0x01" do
    it "loads bc with d16" do
      d16 = 0x1234
      cpu = new_cpu [0x01, d16 & 0xFF, d16 >> 8]
      cpu.tick

      cpu.pc.should eq 3
      cpu.sp.should eq 0xFFFE
      cpu.bc.should eq d16
    end
  end

  describe "0x02" do
    it "loads (bc) with a" do
      cpu = new_cpu [0x02]
      cpu.a = 0x34
      cpu.bc = 0xA000
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.memory[0xA000].should eq 0x34
    end
  end

  describe "0x03" do
    it "increments bc" do
      cpu = new_cpu [0x03]
      cpu.bc = 0x1234
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.bc.should eq 0x1235
    end
  end

  describe "0x04" do
    it "increments b" do
      cpu = new_cpu [0x04]
      cpu.b = 0x12
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.b.should eq 0x13
    end
  end

  describe "0x05" do
    it "decrements b" do
      cpu = new_cpu [0x05]
      cpu.b = 0x12
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.b.should eq 0x11
    end
  end

  describe "0x06" do
    it "loads b with d8" do
      d8 = 0x12
      cpu = new_cpu [0x06, d8]
      cpu.tick

      cpu.pc.should eq 2
      cpu.sp.should eq 0xFFFE
      cpu.b.should eq d8
    end
  end

  describe "0x07" do
    it "rotates accumulator left w/o carry" do
      cpu = new_cpu [0x07]
      cpu.a = 0b01011010
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.a.should eq 0b10110100
      cpu.f_c.should eq false
    end

    it "rotates accumulator left w/ carry" do
      cpu = new_cpu [0x07]
      cpu.a = 0b10100101
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.a.should eq 0b01001011
      cpu.f_c.should eq true
    end
  end

  describe "0x08" do
    it "loads (d16) with sp" do
      d16 = 0xA000
      cpu = new_cpu [0x08, d16 & 0xFF, d16 >> 8]
      cpu.tick

      cpu.pc.should eq 3
      cpu.sp.should eq 0xFFFE
      cpu.memory[0xA000] = 0xFFFE
    end
  end

  describe "0x09" do
    it "adds bc to hl" do
      cpu = new_cpu [0x09]
      cpu.hl = 0x1010
      cpu.bc = 0x1111
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.hl.should eq 0x2121
      cpu.bc.should eq 0x1111
    end
  end

  describe "0x0A" do
    it "loads a with (bc)" do
      cpu = new_cpu [0x0A, 0x12]
      cpu.bc = 0x0001_u8
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.bc.should eq 0x0001
      cpu.memory[0x01].should eq 0x12
    end
  end

  describe "0x0B" do
    it "decrememnts bc" do
      cpu = new_cpu [0x0B]
      cpu.bc = 0x1234
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.bc.should eq 0x1233
    end
  end

  describe "0x0C" do
    it "increments c" do
      cpu = new_cpu [0x0C]
      cpu.c = 0x12
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.c.should eq 0x13
    end
  end

  describe "0x0D" do
    it "decrements c" do
      cpu = new_cpu [0x0D]
      cpu.c = 0x12
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.c.should eq 0x11
    end
  end

  describe "0x0E" do
    it "loads c with d8" do
      cpu = new_cpu [0x0E, 0x12]
      cpu.tick

      cpu.pc.should eq 2
      cpu.sp.should eq 0xFFFE
      cpu.c.should eq 0x12
    end
  end

  describe "0x0F" do
    it "rotates accumulator right w/o carry" do
      cpu = new_cpu [0x0F]
      cpu.a = 0b01011010
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.a.should eq 0b00101101
      cpu.f_c.should eq false
    end

    it "rotates accumulator right w/ carry" do
      cpu = new_cpu [0x0F]
      cpu.a = 0b10100101
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
      cpu.a.should eq 0b11010010
      cpu.f_c.should eq true
    end
  end
end
