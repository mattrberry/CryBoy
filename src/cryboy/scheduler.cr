class Scheduler
  private struct Event
    property cycles, proc

    def initialize(@cycles : Int32, @proc : Proc(Void))
    end

    def to_s(io)
      io << "Event(cycles: #{@cycles}, proc: #{@proc})"
    end
  end

  # For now, I'm choosing to store the events in an unordered array. This would
  # definitely cause performance issues if there were many events, but I'm
  # currently operating under the assumption that there won't be. If this is a
  # performance issue later, I'll change it.
  @events : Array(Event) = [] of Event
  @cycles : UInt64 = 0

  def schedule(cycles : Int, proc : Proc(Void)) : Nil
    @events << Event.new cycles + @cycles, proc
  end

  def schedule(cycles : Int, &block : ->)
    @events << Event.new cycles + @cycles, block
  end

  def tick(cycles : Int) : Nil
    cycles.times do
      @cycles += 1
      pop_current.each &.proc.call
    end
  end


  def pop_current : Array(Event)
    current_events = [] of Event
    while true
      event = get_lowest
      if !event.nil? && event.cycles - @cycles <= 0
        current_events << event
        @events.delete event
      else
        return current_events
      end
    end
  end

  def get_lowest : Event?
    @events.min_by? &.cycles
  end
end
