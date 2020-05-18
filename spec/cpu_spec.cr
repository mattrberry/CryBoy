require "./spec_helper"

describe CPU do
  describe "0x00" do
    it "does nothing" do
      cpu = new_cpu [0x00]
      cpu.tick

      cpu.pc.should eq 1
      cpu.sp.should eq 0xFFFE
    end
  end

  describe "0x01" do
    it "loads bc with value" do
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
end
