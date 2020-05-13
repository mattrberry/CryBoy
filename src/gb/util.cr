def repeat(hz : Int, &block)
    loop do
      start_time = Time.utc
      block.call
      end_time = Time.utc
      next_cycle = start_time + Time::Span.new nanoseconds: (1_000_000_000 / hz).to_i
      if next_cycle > end_time
        # puts "Sleeping in Repeat(hz:#{hz}) for #{next_cycle - end_time}, #{100*(next_cycle - end_time).total_microseconds//(next_cycle - start_time).total_microseconds}%"
        sleep next_cycle - end_time
      else
        puts "Took too long by #{end_time - next_cycle}"
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