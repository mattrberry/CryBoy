class Scheduler
  private class Event
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

  def schedule(cycles : Int, proc : Proc(Void)) : Nil
    @events << Event.new cycles, proc
  end

  def schedule(cycles : Int, &block : ->)
    @events << Event.new cycles, block
  end

  def tick(cycles : Int) : Nil
    cycles.times do
      update_all
      pop_current.each &.proc.call
    end
  end

  # For now, I'm choosing to just update all existing scheduled events rather
  # than storing the current cycle count and the cycle count that the event
  # should occur on. If this is a performance issue later, I'll change it.
  def update_all : Nil
    @events.each { |event| event.cycles -= 1 }
  end

  def pop_current : Array(Event)
    current_events = [] of Event
    while true
      event = get_lowest
      if !event.nil? && event.cycles <= 0
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
