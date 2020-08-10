class Scheduler
  private class ScheduledEvent
    property cycles, proc

    def initialize(@cycles : Int32, @proc : Proc(Void))
    end

    def to_s(io)
      io << "ScheduledEvent(cycles: #{@cycles}, proc: #{@proc})"
    end
  end

  @events : Array(ScheduledEvent) = [] of ScheduledEvent

  def schedule(cycles : Int32, proc : Proc(Void)) : Nil
    @events << ScheduledEvent.new cycles, proc
  end

  def tick(cycles : Int) : Nil
    cycles.times do
      update_all
      pop_current.each do |event|
        event.proc.call
      end
    end
  end

  def update_all : Nil
    @events.each do |event|
      event.cycles -= 1
    end
  end

  def pop_current : Array(ScheduledEvent)
    current_events = [] of ScheduledEvent
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

  def get_lowest : ScheduledEvent?
    @events.min_by? { |event| event.cycles }
  end
end
