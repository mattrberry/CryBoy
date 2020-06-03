lib LibC
  fun nanosleep = nanosleep(req : LibC::Timespec*, rem : LibC::Timespec*) : LibC::Int
end

def nanosleep(nanoseconds : Number)
  req = LibC::Timespec.new
  req.tv_nsec = nanoseconds.to_u32
  LibC.nanosleep(pointerof(req), nil)
end

def nanosleep(time_span : Time::Span)
  nanosleep time_span.total_nanoseconds
end

def repeat(hz : Int, &block)
  period = (1_000_000_000 / hz).to_i
  loop do
    start_time = Time.utc
    block.call
    end_time = Time.utc
    next_cycle = start_time + Time::Span.new nanoseconds: period
    if next_cycle > end_time
      # puts "Sleeping in Repeat(hz:#{hz}) for #{next_cycle - end_time}, #{100*(next_cycle - end_time).total_microseconds//(next_cycle - start_time).total_microseconds}%"
      nanosleep next_cycle - end_time
    else
      # puts "Took too long by #{end_time - next_cycle}"
    end
  end
end

def repeat(hz : Int, in_fiber : Bool, &block)
  if in_fiber
    spawn same_thread: false do
      repeat hz, &block
    end
  else
    repeat hz, &block
  end
end

def hex_str(n : UInt8 | UInt16) : String
  "0x#{n.to_s(16).rjust(sizeof(typeof(n)) * 2, '0').upcase}"
end

def array_to_uint8(array : Array(Bool | Int)) : UInt8
  raise "Array needs to have a length of 8" if array.size != 8
  value = 0_u8
  array.each_with_index do |bit, index|
    value |= (bit == false || bit == 0 ? 0 : 1) << (7 - index)
  end
  value
end

def array_to_uint16(array : Array(Bool | Int)) : UInt16
  raise "Array needs to have a length of 16" if array.size != 16
  value = 0_u16
  array.each_with_index do |bit, index|
    value |= (bit == false || bit == 0 ? 0 : 1) << (15 - index)
  end
  value
end
